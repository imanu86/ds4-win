# G38 Capacity-Bounded Prefill Waves

Date: 2026-07-15  
Host: native Windows, RTX 3060 12 GiB, 64 GiB RAM  
Branch: `port/windows-dynamic-arena-0051`

## Question

Can one wide prefill chunk retain G37's per-layer expert union while bounding
compact staging VRAM, by executing the exact union in smaller expert waves and
summing each original routed pair once?

## Implementation

`DS4_CUDA_PREFILL_WAVES=1` enables an opt-in path only when `n_tokens > 1` and
the selected loader owns the expert transport. The runtime:

1. reads the exact router selection once and builds the complete sorted union;
2. derives an expert capacity from free/reusable VRAM, or accepts
   `DS4_CUDA_PREFILL_WAVE_FORCE_EXPERTS=N` for validation;
3. partitions that unchanged union into waves;
4. stages only the current wave and remaps only original token/route pairs that
   select an expert in that wave;
5. executes exact gate/up, SwiGLU and down kernels for those pairs;
6. writes every partial down result to its original six-route slot and invokes
   the normal ordered `moe_sum_kernel` once after the last wave.

The v1 path intentionally bypasses prefill cache admission and expert-tile
kernels. It records one upload event per wave but serializes stream 0 before
reusing the staging buffers. It is therefore a capacity and correctness
checkpoint, not yet the final overlap implementation. The default path is
unchanged when the environment variable is absent.

The harness records requested and observed wave width, activations, layer count,
wave count, active pairs, unique experts, upload waits and failures. A forced
wave request fails closed if the runtime does not report an activation.

## Exactness fixes found during smoke testing

Two initial smoke runs exposed implementation bugs and are excluded from all
performance comparisons:

- `xq` initially aliased the routed `down` scratch, so wave 1 overwrote input
  quantization needed by later waves. G38 now allocates one combined temporary
  region for persistent `xq` plus the active-pair index buffer.
- wave state could survive into decode when a resident-route path skipped the
  selected-loader reset. `routed_moe_launch` now clears wave state at every
  invocation before selecting any transport path.

Invalid forced widths, arithmetic overflow, debug-dump composition and staging
failure are rejected rather than silently changing execution.

## Protocol

The final counter-ordered matrix used:

- model: `C:\ds4-models\ds4-2bit.gguf`, 86,720,111,488 bytes;
- prompt: 43-token cyberpunk single-file HTML request;
- context 256, max generation 12, greedy/nothink server defaults;
- cache336 LRU, GPU-resident decode routes, 2 GiB stream budget;
- Q8-F16 cache disabled, embedding-row staging enabled;
- no tiering, dynamic arena, REAP mask, SPEX or split hit/miss;
- one discarded warmup plus `n=3` measured requests per process;
- two counter-ordered processes per arm, 18 measured requests total;
- expected content SHA-256
  `921a62bdb39d9d07161326274fcbc0070f3c4b9e75153d27b1b6dc96811f6e88`.

Order:

`production A -> wave31 A -> generic A -> generic B -> wave31 B -> production B`

`generic` disables expert tiles and P2 so wave partitioning is compared with the
same generic sorted kernel family. `production` retains the normal optimized
kernel selection. All 18 measured outputs and all six warmups matched the
expected hash.

## Results

| Arm | TTFT | Client t/s | Decode t/s | Process reads | Peak dedicated VRAM | Union experts | Waves |
|---|---:|---:|---:|---:|---:|---:|---:|
| production | 7.319 s | 0.945 | 2.230 | 164.49 GiB | 10.900 GiB | 11,764 | 0 |
| generic | 11.007 s | 0.732 | 2.230 | 164.55 GiB | 10.900 GiB | 11,716 | 0 |
| wave31 | 10.141 s | 0.836 | 2.945 | 131.14 GiB | 10.437 GiB | 11,716 | 456 |

Wave31 versus production:

- TTFT: `+38.56%`;
- client throughput: `-11.47%`;
- short decode throughput: `+32.06%`;
- process reads: `-20.27%`;
- peak dedicated VRAM: `-4.25%`.

Wave31 is `7.86%` faster in TTFT than the same generic-kernel baseline. Generic
and wave31 both observed exactly 11,716 cumulative union experts; partitioning
did not introduce additional routing drift relative to that kernel policy.
Production observed 11,764 because its tile-capable execution path differs, so
G38 proves exact content and generic-path equivalence, not graph identity with
the production arm.

The higher decode result follows from this short request after the wave path
bypassed prefill cache admission. It is directional only and is not a long-run
decode verdict.

## Boundary safety probes

These probes validate mechanism breadth only; `n=1` is never used as a
performance verdict.

| Forced width | Layers | Waves | Active pairs | Unique experts | Failures | Exact |
|---:|---:|---:|---:|---:|---:|---|
| 7 | 42 | 435 | 10,836 | 2,929 | 0 | yes, 12 tokens |
| 1 | 42 | 2,929 | 10,836 | 2,929 | 0 | yes, first token |

## Verdict

G38 validates an exact capacity-bounded wave mechanism over the full measured
union, including the one-expert boundary. V1 is rejected for production
promotion because serialized staging and generic per-wave kernels cost 38.56%
TTFT against production. It should remain opt-in.

The measured reductions in process reads and peak VRAM justify one focused G39:
double-buffer wave weights and pair metadata, upload wave N+1 while wave N
computes, and recover tile-capable kernels where their layout permits. Preserve
the full-union router contract and final ordered sum; do not narrow the mask to
fit staging capacity.

## Provenance

- executable SHA-256:
  `7b083a625215775443c7d777aa6f2af522d2f0ea02adca4a7017d2ae225965c8`
- build input fingerprint:
  `28d0bfbbd590f15f1e5dfa66f041b432c6b1af998f3c8071d1e945eca9d3a86e`
- CUDA source SHA-256:
  `a69896c3b985e06b060a25cbd663fe35a982d232691aa6df278e30f5d6c14199`
- harness SHA-256:
  `d07dcbea27c4e91ff09c3a1ac711180ed5be165329f3818742bb091ff7e07044`
- matrix runner SHA-256:
  `a8314a6ad3e72606b7c23ffec4747d2318c7791555315cf136c1f74e193809ba`
- matrix JSON SHA-256:
  `22fbd216fad414d7bf828e53f3ac104f1ecf710cf4a33236e70445a00ac9747c`
- wave7 result SHA-256:
  `58e82a88e137bcfa54e2f77c3b9dfa1980c07801ccaf997679f937ec8efb5b13`
- wave1 result SHA-256:
  `a42e1e15cc66ca13287496d27c6b760ff7c54ca207e91f06fbcbcd0ee27e29a7`

Raw local artifacts:

- `g7_runs/g38_prefill_waves_ab_result.json`
- `g7_runs/g7_g38_wave7_safety_n1_result.json`
- `g7_runs/g7_g38_wave1_safety_n1_result.json`

