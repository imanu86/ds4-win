# G28 static K8 residency and embedding row staging

Date: 2026-07-14

Status: deferred by user after three final gates. Do not continue K8 experiments
until the TODO entry at the end is explicitly resumed.

## Objective

Measure the upper bound of a static eight-expert-per-layer mask on the native
Windows CUDA port. The experiment was intended to distinguish three costs:

1. loading routed experts from storage;
2. keeping the complete K8 expert universe in VRAM;
3. the remaining dense/shared-weight and per-layer execution overhead.

This is not a quality result. The mask was learned from the `coffee` session
and the short transport probes used a different `Hi` prompt. Their output must
not be graded as evidence for or against the K8 hypothesis.

## Corrected K8 geometry

The original mask covered only layers 3..42. G28 added real mask overrides for
the first two hash-routed layers and generated a full 42-layer mask:

- mask: `g7_runs/g28_sessK8_coffee_full42.txt`
- SHA-256: `18d7d1a36d5d663e44d646acfd378a5594409d25bab7a07b903c8eaafea81e60`
- pruned rows: 10,416 (`42 * 248`)
- retained experts: 336 (`42 * 8`)
- retained routed-expert payload: about 2.21 GiB

Layer 1 retained experts:

```text
32 81 117 182 104 96 34 155
```

Layer 2 retained experts:

```text
84 219 39 74 34 210 159 44
```

The no-mask regression remained exact after the hash-layer override. The
16-token Caesar output matched SHA-256
`b037ce25fab7393eeb9fc5b7bf7f5b8ef70768aea476cd1c09b0ffa348323b30`.

## Runtime-reserve and startup ownership fixes

`DS4_CUDA_STREAM_RUNTIME_RESERVE_MB` now permits a large startup reserve while
allocating the resident expert cache and a smaller reserve after that cache is
ready. The switch is ordered by `g_model_expert_cache_ready`; switching before
expert-cache allocation reduced the cache to 247 slots and was rejected.

When `DS4_CUDA_STREAMING_EXPERT_CACHE_N` is enabled, startup tensor preloading
excludes routed-expert slabs. This prevents the startup model cache from
duplicating 72.56 GiB of expert tensors whose residency belongs to the
dedicated cache.

With 336 slots allocated, expert-cache telemetry reached 328 resident entries,
4,602 hits, 328 compulsory misses, and zero expert evictions. The routed expert
universe therefore fit in VRAM; expert eviction was not the remaining ceiling.

## Sawtooth diagnosis

The Windows Task Manager sawtooth was real load/stall behavior. Before the
embedding fix, a one-token K8 probe reported:

- about 19.18 GiB of Win32 process reads;
- 309 streamed model-range evictions;
- about 16.5% median GPU utilization;
- 0.10 server decode tokens/s;
- zero expert-cache evictions.

The cycling object was the dense/shared model cache, not the K8 expert cache.
In particular, decode requested the complete approximately 0.99 GiB
`token_embd.weight` table to read one approximately 10 KiB row.

## Embedding row staging

`DS4_CUDA_EMBED_ROW_STAGING=1` is an opt-in experiment. It:

- excludes `token_embd.weight` from the startup CUDA cache;
- gathers only requested F16 embedding rows into grow-only pinned host memory;
- uploads a compact row buffer to CUDA;
- uses a compact kernel for single-token and batch embedding lookup;
- releases both staging buffers on model-map replacement and GPU cleanup.

The standard path is unchanged when the option is disabled. A no-mask exactness
gate produced the same 16-token output hash as the reference.

## Measured probes

All rows below are diagnostic `n=1` experiments unless explicitly marked. They
are mechanism evidence, not repeated performance verdicts.

| Tag | Key difference | Server decode t/s | TTFT s | Process reads GiB | Expert cache | Expert evictions |
|---|---|---:|---:|---:|---|---:|
| `g28_k8_exclude_experts_diag_n1` | K8, routed slabs excluded | 0.10 | 3.733 | 19.176 | 326/336 | 0 |
| `g28_k8_exclude_experts_budget4_diag_n1` | mapped budget 4 GiB | 0.10 | 3.677 | 18.125 | 315/336 | 0 |
| `g28_k8_tensorgranular_diag_n1` | tensor-granular startup spans | 0.07 | 3.211 | 18.178 | 326/336 | 0 |
| `g28_embed_rows_nomask_exact_n1` | row staging, no K8 | 0.80 | 54.480 | 58.117 | off | 0 |
| `g28_k8_embed_rows_diag_n1` | K8 plus row staging | 1.78 | 7.092 | 7.353 | 326/336 | 0 |
| `g28_k8_embed_rows_warm16_n1` | one-token warmup, then 16 tokens | 2.01 | 1.270 | 7.418 total | 328/336, 4,602 hits | 0 |

The row-staging K8 diagnostic reduced model-range evictions from 309 to 1 and
process reads from 19.18 to 7.35 GiB. The warm decode nevertheless stopped at
2.01 t/s. The result isolates the next ceiling: every layer still performs
router-ID D2H, CPU lookup/deduplication, cache-slot-to-compact D2D copies, and an
upload-stream synchronization before launching MoE kernels.

The no-mask row-staging run is a negative performance result: exactness passed,
but excluding the embedding table changed cache pressure and increased total
reads. Row staging must remain opt-in and must not be promoted as a general
speedup from these measurements.

## Provenance

- branch: `port/windows-dynamic-arena-0051`
- base commit: `c4bb45de31d122a5f1e7b7e11bfbf18ec242dffe`
- GPU: NVIDIA GeForce RTX 3060 12 GB, native Windows/WDDM
- model: `D:\ds4-models\ds4-2bit.gguf`
- final measured executable SHA-256:
  `1debd6200c02920b7bd7e5b1f933419dc13d58eee1c9d167578af2887a751c4c`
- build input fingerprint:
  `f00220f207ba61d3ac66445d230a9d42449cf346743d4f498aada9dc5b2a6595`

## Decision and deferred TODO

K8 work is paused. No fourth gate was run after the user stopped the study.
Do not infer a final K8 throughput or quality verdict from `n=1`.

If resumed, choose exactly one of these implementations before running more
tests:

1. **Direct resident-slot execution.** Build a device-side
   `expert_id -> resident_slot` map and let MoE kernels index the stable resident
   cache directly. Eliminate per-layer D2H lookup, slot-to-compact D2D copies,
   and upload-stream synchronization. Validate fallback on a true miss.
2. **Physical K8 GGUF bake.** Rewrite routed-expert tensors and all associated
   router/hash metadata to contain only the retained experts. The resulting
   model must actually fit in VRAM and must not retain full 256-expert tensor
   shapes or storage.

Either path requires a mask learned from the same evaluation prompt/domain,
greedy `nothink`, an exact no-mask regression, and quality grading on at least
three independent valid runs before any claim.
