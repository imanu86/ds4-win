# G34 SPEX-predicted IQ2XXS CPU sidecar

Date: 2026-07-15

Branch: `port/windows-dynamic-arena-0051`

## Question

Can next-layer SPEX predictions start useful routed-expert IQ2XXS work on CPU
while the exact GPU router and resident/miss transport continue, without changing
routing or output, and improve the current G32 path?

The opt-in toggle is:

```text
DS4_SPEX_CPU_PROBE_K=1|2
```

The harness exposes it as `-SpexCpuProbeK 1|2` and requires SPEX full stage,
`SpexCap >= K`, and functional GPU prefetch off.

## Implementation

The probe is observe-only. For each target layer with a ready SPEX prediction:

1. an ordered asynchronous D2H copies the target `ffn_norm` (4096 floats,
   16 KiB) into an eight-slot pinned ring;
2. one dedicated CPU worker quantizes that hidden vector to Q8_K;
3. the worker reads each predicted expert's IQ2XXS gate/up rows from the model
   mapping and computes gate, up, clamp and SwiGLU serially;
4. it retains only a checksum and timing/counter telemetry.

The exact GPU router remains authoritative. The sidecar never writes router IDs,
weights, CUDA expert cache, arena, MoE tensors, or model output. Its CPU result is
not consumed by inference in G34.

G34 also fixes an observability hole in G32: the GPU-resident route resolver now
publishes its already-known six exact IDs into `g_moe_last_selected`. This adds no
new D2H or expert copy and restores SPEX actual-set accounting under
`-GpuResidentRoutes`.

The final review also moved exact-sidecar observation after routed MoE in both
normal and shared-overlap schedules, and made the harness fail closed on the
expected SPEX artifact hash:

```text
a86288c3a29be97179230a3ed86eebdcd7293ab33987ed7aa57850213325f3c7
```

## Safety

The release build succeeded with:

```text
executable sha256: 44fdcbaa7bf2da2a1920036bb061770a9b21eb30114ede55b0a4b73a9d9d1b76
build input fingerprint: 02f87221faee274becfb095de6b3287ba5dd23a4e419422092c1115dd08d8f2a
harness sha256: d33d764bc084a054add3b9f3df54de59a9bbc9e12c6fbfd424ac57296522a850
```

Every warmup and all 24 measured responses were exactly:

```text
Hello! How can I help you today?
```

Enforced SHA-256:

```text
fda564ba3f7a0f028106d468420f674898ed99ac5bf2765ac9586206e39d73c5
```

The corrected exact-set telemetry reproduces the historical G15 measurements:

| SPEX cap | Hits | Actual | Recall | Precision |
|---:|---:|---:|---:|---:|
| 1 | 812 | 9,072 | 8.95% | 53.70% |
| 2 | 1,404 | 9,072 | 15.48% | 46.43% |

## Protocol

Each isolated pair was run in both orders. Every run used one discarded warmup
and `n=3` measured requests. Control kept the same SPEX score/topK width as its
treatment, so the delta isolates the CPU sidecar rather than SPEX itself.

Common configuration:

| Parameter | Value |
|---|---|
| Model | `C:\ds4-models\ds4-2bit.gguf` |
| GPU | RTX 3060 12 GB, native Windows/WDDM |
| Prompt | `Hi` |
| Context / max tokens | 256 / 12 (EOS after 9) |
| Expert cache | 336 slots, LRU, GPU-resident route resolver |
| Stream window | 2 GiB |
| Startup/runtime reserve | 4096 / 128 MiB |
| Q8-F16 cache | disabled |
| Embedding row staging | enabled |
| REAP / dynamic arena / G33 split | disabled |

The complete reproducible matrix is `g34_spex_cpu_ab.ps1`.

## Throughput

| Pair/run | Server t/s | Client t/s | Exact |
|---|---:|---:|---|
| cap1 control A | 3.1567 | 2.1101 | yes |
| K1 CPU A | 3.0333 | 2.0561 | yes |
| K1 CPU B | 3.0833 | 2.0773 | yes |
| cap1 control B | 3.1733 | 2.1147 | yes |
| cap2 control A | 3.1133 | 2.0790 | yes |
| K2 CPU A | 3.1167 | 2.0956 | yes |
| K2 CPU B | 3.0633 | 2.0953 | yes |
| cap2 control B | 3.1267 | 2.1235 | yes |

Counter-order means:

| Width | Control server | CPU server | Delta | Control client | CPU client | Delta |
|---|---:|---:|---:|---:|---:|---:|
| K1 | 3.1650 | 3.0583 | -3.37% | 2.1124 | 2.0667 | -2.16% |
| K2 | 3.1200 | 3.0900 | -0.96% | 2.1012 | 2.0955 | -0.27% |

## Sidecar mechanics

Aggregated across both treatment runs:

| Metric | K1 | K2 |
|---|---:|---:|
| possible jobs | 3,024 | 3,024 |
| submitted / dropped | 3,020 / 4 | 2,478 / 546 |
| dropped | 0.13% | 18.06% |
| predicted experts | 3,020 | 4,956 |
| exact matches | 1,621 (53.68%) | 2,343 (47.28%) |
| jobs ready at transport join | 1,255 (41.56%) | 11 (0.44%) |
| matched experts also ready | 616 | 9 |
| useful-ready / predictions | 20.40% | 0.18% |
| CPU time per submitted job | 4.58 ms | 8.95 ms |
| queue time per submitted job | 2.21 ms | 47.76 ms |
| page faults, control -> CPU mean | 88,162 -> 234,751 (2.66x) | 86,973 -> 387,786 (4.46x) |

`ready_at_transport` is sampled when the exact GPU-resident transport path has
returned to the graph executor. It is not evidence that the CPU result was ready
before the exact router decision.

## Verdict

The mechanism is real and exact, but unconditional speculative IQ2XXS execution
on one CPU worker is rejected as a throughput lever.

K1 is the only width that mostly keeps up, yet only 20.40% of predictions are
both correct and ready at the measured join, while server throughput falls
3.37% and page faults rise 2.66x. K2 overloads the queue: 18.06% of jobs are
dropped and only 0.18% of predicted experts are useful and ready.

Keep G34 opt-in as a measured feasibility probe. The data favors using SPEX to
stage or pin high-confidence expert bytes in RAM, not to execute unconditional
IQ2XXS gate/up on CPU. Any revisit must first reduce prediction waste and prove
that the saved transport exceeds D2H, CPU contention and page-cache pressure.

## Primary artifacts

- `g7_runs/g7_g34_cap1_control_primed_n3_a_*`
- `g7_runs/g7_g34_k1_cpu_primed_n3_a_*`
- `g7_runs/g7_g34_k1_cpu_primed_n3_b_*`
- `g7_runs/g7_g34_cap1_control_primed_n3_b_*`
- `g7_runs/g7_g34_cap2_control_primed_n3_a_*`
- `g7_runs/g7_g34_k2_cpu_primed_n3_a_*`
- `g7_runs/g7_g34_k2_cpu_primed_n3_b_*`
- `g7_runs/g7_g34_cap2_control_primed_n3_b_*`
