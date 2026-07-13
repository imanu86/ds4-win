# G13: SPEX hidden next-layer dry-run on native Windows

Date: 2026-07-14

## Scope

This milestone ports the SPX1 hidden-state predictor to the native Windows CUDA
runtime and measures it without changing router decisions, masks, expert
residency, or generated tokens. It does not implement speculative expert
prefetch yet.

The predictor file used by every run was:

```
C:\Users\imanu\source\repos\moe-aggressive-commit\runs\spex\spex_model\ds4flash_d2_nextlayer.spex
SHA256 a86288c3a29be97179230a3ed86eebdcd7293ab33987ed7aa57850213325f3c7
SPX1 v1 predictor=2 layers=43 hidden=4096 experts=256 weights=86.00 MiB
```

## Runtime design

1. Load and validate the SPX1 header and FP16 weights at graph creation.
2. Upload the 43 hidden-to-next-layer matrices to a GPU tensor.
3. After `ffn_norm` at layer L, score the experts predicted for layer L+1.
4. Read only the predicted IDs asynchronously; never read hidden state or
   scores back to the CPU.
5. At layer L+1, compare the prediction against the real selected-expert IDs
   already known by the selected-load runtime metadata.
6. Keep the actual router authoritative. Dry-run predictions cannot change
   routing, masks, cache admission, or loads.

Normal decode explicitly owns the predictor lifecycle. MTP/speculative graph
paths cannot schedule or consume SPEX work. The selected-expert snapshot is
invalidated on every routed-MoE invocation, including bypass paths.

The readback is consumed at the beginning of the target layer rather than at
the end of the source layer. This gives the GPU the rest of the source layer to
finish the score/topK/D2H chain and is also the correct deadline for a future
prefetch consumer.

## Controls

```
DS4_SPEX_HIDDEN_GPU_DRY_RUN=1
DS4_SPEX_FILE=<SPX1 file>
DS4_SPEX_CAP=1..6
DS4_SPEX_AB_STAGE=resident|score|topk|full
DS4_SPEX_FUSED_TOPK=1
DS4_SPEX_DRY_RUN_STATS_EVERY=<completed-token interval>
```

`DS4_SPEX_AB_STAGE` is cumulative:

| Stage | Work performed |
|---|---|
| `resident` | load/upload 86 MiB only |
| `score` | resident + hidden score kernel |
| `topk` | score + generic topK kernel |
| `full` | topK + event/D2H/readback + measured router comparison |

`DS4_SPEX_FUSED_TOPK=1` is diagnostic and remains off by default. Its single
block coalesced score+topK kernel preserved measured recall but was slower.

The harness now records executable, source, harness, prompt, and SPEX hashes
before launch. It also asks the server to exit cleanly after warmup plus N
requests, so final counters are flushed instead of being lost to `Kill()`.

## Protocol

Common native-Windows configuration:

```
model=C:\ds4-models\ds4-2bit.gguf
model_bytes=86720111488
GPU=RTX 3060 12GB, WDDM, sm_86
CUDA=12.6
budget_gb=2
reserve_mb=1024
warmup=true
temperature=0 (server harness default)
selected-load enabled
expert cache disabled
shared overlap disabled
MoE I/O queue depth=1
```

No performance verdict below comes from a safety `n=1` run. Safety runs only
gate exact output, counter closure, and runtime errors.

Cyber prompt (`64` requested tokens, `n=3`):

```
Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document.
```

Prompt SHA256:
`38f6ec5ee5403f59dd2418eb5d9a5a94a0f0da19df015060383bb1ae46003bb6`

## Results

### Long prompt A/B

Same executable SHA256 prefix `94179de7961e`, same prompt, and three measured
repetitions per arm:

| Arm | Periodic stats | HTTP t/s | Server decode t/s | Prefill/TTFT | K6 recall | Output hash |
|---|---:|---:|---:|---:|---:|---|
| SPEX off | off | 1.268 | 1.740 | 13.679 s | n/a | `fd6c4522975a` |
| SPEX full | every token | 1.030 | 1.327 | 13.911 s | 0.3212 | `fd6c4522975a` |
| SPEX full | final only | 1.147 | 1.530 | 13.859 s | 0.3212 | `fd6c4522975a` |

Measured conclusions:

- K6 recall was `32.12%`: `20,720` hits over `64,512` actual selections.
- Final-only telemetry cost `12.1%` server decode throughput in this long A/B.
- Per-token telemetry increased the measured decode penalty to `23.8%` and is
  not a valid low-overhead benchmark mode.
- All six measured outputs were bit-identical across and within the two valid
  arms. SPEX did not alter generation.

### Cumulative stage isolation

Short `Hi` prompt, 12 requested tokens, 9 generated tokens, `n=3`, executable
SHA256 prefix `defdafc93ef3`:

| Stage | Server decode t/s | Delta vs off | Event query misses | Recall |
|---|---:|---:|---:|---:|
| off | 2.847 | reference | 0 | n/a |
| resident | 2.813 | -1.2% | 0 | n/a |
| score | 2.867 | +0.7% | 0 | n/a |
| topk | 2.813 | -1.2% | 0 | n/a |
| full | 2.717 | -4.6% | 36 | 0.3078 |

The score-only result is within run noise; this matrix does not prove a speedup.
It does show that the measured full handoff is more expensive than weight
residency, score, or generic topK alone.

### Current-binary fused A/B

Short prompt, `n=3`, executable SHA256 prefix `067f8c711657`:

| Arm | Server decode t/s | K6 recall | Output hash |
|---|---:|---:|---|
| SPEX off | 2.883 | n/a | `fda564ba3f7a` |
| full generic | 2.787 | 0.3078 | `fda564ba3f7a` |
| full fused | 2.710 | 0.3078 | `fda564ba3f7a` |

The fused kernel was `2.8%` slower than the generic full path and `6.0%` below
SPEX-off decode. It is retained only as an opt-in negative experiment.

## Integrity gates

The harness rejects a full SPEX run unless all of the following hold:

- the requested stage and fused flag are observed in runtime logs;
- SPEX never disables itself;
- `scheduled == ready > 0`;
- the actual selected-expert metadata is present for every compared layer;
- all HTTP requests complete with positive token usage.

The final current safety run measured `756/756` predictions consumed,
`no_actual=0`, K6 recall `0.3078`, and the exact expected greedy text:
`Hello! How can I help you today?`

## Decision and next step

The signal gate passes: runtime K6 recall is repeatable at roughly 31-32% and
generation remains bit-identical. The synchronous CPU handoff gate does not
pass: it imposes a 3-12% decode penalty depending on prompt/run shape.

Do not wire the current blocking readback directly into expert prefetch. The
next implementation should use a bounded pinned-host ring plus a loader worker:

1. enqueue topK D2H without waiting in the decode thread;
2. retain token/layer identity and actual selected IDs in ring metadata;
3. let a worker poll completed events and issue compact expert prefetch;
4. drop stale predictions rather than blocking decode;
5. measure prediction lead time, useful-hit rate, bytes prefetched, late hits,
   dropped entries, and net decode t/s;
6. keep routing and masks unchanged until that prefetch-only gate passes.

This is not a static domain mask and does not train on the active prompt or on
a mask. It is an online hidden-state prediction of next-layer expert demand.
