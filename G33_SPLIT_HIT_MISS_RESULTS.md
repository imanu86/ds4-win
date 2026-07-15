# G33 split resident hits from exact misses

Date: 2026-07-15

Branch: `port/windows-dynamic-arena-0051`

Parent commit: `1126211c24409108ebeaaedb8498db4426a39fb8`

## Question

Can resident expert routes start computing while the exact miss worker reads and
uploads cold routes, then join once without changing greedy output?

The opt-in toggle is:

```text
DS4_CUDA_MOE_SPLIT_HIT_MISS=1
```

The harness exposes it as `-SplitHitMiss` and requires
`-GpuResidentRoutes -ExpertCacheN N`. It remains off by default.

## Mechanism

1. The GPU resolver writes the exact route pointers already resident in VRAM,
   clears miss pointers and publishes a stable six-bit hit mask.
2. The default stream quantizes the input and computes gate/up/mid/down only
   for hit slots while the host worker reads and uploads misses.
3. One host join waits for both the hit work and the exact miss worker.
4. The same kernels compute the miss slots after their pointers are published.
5. Hit and miss results occupy their original route slots in a small
   `6 * out_dim * sizeof(float)` scratch buffer. One final `moe_sum_kernel`
   adds slots 0..5 in original order.

The scratch buffer is about 96 KiB at `out_dim=4096`; G33 does not add another
expert copy. Router IDs and weights remain authoritative. No prediction, mask
change, REAP, dynamic arena or SPEX policy is composed into this A/B.

## Safety and review

Release build succeeded. The safety run produced:

```text
Hello! How can I help you today?
```

The enforced SHA-256 was unchanged from G32:

```text
fda564ba3f7a0f028106d468420f674898ed99ac5bf2765ac9586206e39d73c5
```

The safety run exercised 378 split layer calls with zero worker errors.

A read-only static review found no CUDA correctness issue. It did find that the
harness initially reported `split_calls` without failing when a requested path
was bypassed. The harness now fails closed when `-SplitHitMiss` is requested but
the runtime reports no split calls. PowerShell syntax validation passed after
that fix.

## Common configuration

| Parameter | Value |
|---|---|
| Model | `C:\ds4-models\ds4-2bit.gguf` (86,720,111,488 bytes) |
| GPU | RTX 3060 12 GB, WDDM, driver 596.21 |
| Prompt | `Hi` |
| Sampling | greedy/default server path; output hash enforced |
| Context | 256 |
| Max tokens | 12 (EOS after 9 generated tokens) |
| Warmup | same prompt and cap, discarded |
| Expert cache | 336 slots, LRU, 0.5 GiB reserve |
| Stream window | 2 GiB |
| Startup/runtime reserve | 4096/128 MiB |
| Q8-F16 cache | disabled |
| Embedding row staging | enabled |
| REAP/SPEX/dynamic arena | disabled |

Measured binary:

```text
executable sha256: 0f8c431940846e85e7bb46d6ac29ed3a963f1047647d564719ec74143a110001
build input fingerprint: bac56d783559251e888fa55deae06a379bf7c28904c95d9c5dcdc1cca3768744
```

## Results

### Primed n=3

| Variant | Server decode t/s | Client end-to-end t/s | Exact |
|---|---:|---:|---|
| G32 synchronous worker | 3.2233 | 2.1721 | yes |
| G33 split hit/miss | 3.2633 | 2.1510 | yes |
| Delta | +1.24% | -0.97% | unchanged |

### Reverse-order primed n=5

| Variant | Server decode t/s | Client end-to-end t/s | Exact |
|---|---:|---:|---|
| G33 split hit/miss | 3.1860 | 2.1430 | yes |
| G32 synchronous worker | 3.2060 | 2.1670 | yes |
| Delta split vs control | -0.62% | -1.11% | unchanged |

### Aggregate across eight measured requests per variant

| Variant | Server decode t/s | Client end-to-end t/s |
|---|---:|---:|
| G32 synchronous worker | 3.2125 | 2.1689 |
| G33 split hit/miss | 3.2150 | 2.1460 |
| Delta | +0.08% | -1.06% |

This aggregate is descriptive, not a replacement for the two controlled runs.

### Runtime counters

| Run | Resolver/default-stream sync | Worker-ready wait | Worker job |
|---|---:|---:|---:|
| n=3 control | 2.578 ms/layer | 3.865 ms/layer | 3.861 ms/job |
| n=3 split | 2.734 ms/layer | 3.630 ms/layer | 3.920 ms/job |
| n=5 control | 2.682 ms/layer | 3.770 ms/layer | 3.806 ms/job |
| n=5 split | 2.725 ms/layer | 3.701 ms/layer | 3.978 ms/job |

All primed runs observed the same route population as G32: 42.24% route hits
and only 0.79% all-hit layers. There were zero worker errors.

## Commands

Control, replacing `N` with 3 or 5 and using the matching tag:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\g7_measure.ps1 `
  -MaxTokens 12 -Repeats N -Warmup -Tag TAG -Prompt Hi -Context 256 `
  -BudgetGB 2 -ReserveMB 4096 -RuntimeReserveMB 128 `
  -ExpertCacheN 336 -ExpertCacheReserveGB 0.5 -ExpertCachePolicy lru `
  -DisableQ8F16Cache -EmbedRowStaging -GpuResidentRoutes `
  -ExpectedContentSHA256 fda564ba3f7a0f028106d468420f674898ed99ac5bf2765ac9586206e39d73c5 `
  -ExpectedWarmupContentSHA256 fda564ba3f7a0f028106d468420f674898ed99ac5bf2765ac9586206e39d73c5 `
  -ModelPath C:\ds4-models\ds4-2bit.gguf
```

G33 adds `-SplitHitMiss` to that command.

## Verdict

G33 is exact and the intended overlap is measured: worker-ready wait decreases.
It is not a throughput win. Across the counter-ordered n=3 and n=5 comparisons,
server decode is effectively unchanged while client end-to-end throughput is
about 1% lower. The extra masked launches and final materialized sum consume the
small amount of overlap exposed by the current hit distribution.

Keep the implementation opt-in as a measured mechanism checkpoint. Do not
compose policy into it or enable it by default. A future revisit requires either
substantially more resident hits per layer or a fused hit/miss execution path
that avoids the extra launch and scratch costs.

## Primary artifacts

- `g7_runs/g7_g33_split_hit_miss_safety_n1_{result,raw_outputs,stderr,runtime_telemetry,memory_preflight}.*`
- `g7_runs/g7_g33_control_syncworker_hi12_primed_n3_{result,raw_outputs,stderr,runtime_telemetry,memory_preflight}.*`
- `g7_runs/g7_g33_split_hit_miss_hi12_primed_n3_{result,raw_outputs,stderr,runtime_telemetry,memory_preflight}.*`
- `g7_runs/g7_g33_split_hit_miss_hi12_primed_n5_{result,raw_outputs,stderr,runtime_telemetry,memory_preflight}.*`
- `g7_runs/g7_g33_control_syncworker_hi12_primed_n5_{result,raw_outputs,stderr,runtime_telemetry,memory_preflight}.*`
