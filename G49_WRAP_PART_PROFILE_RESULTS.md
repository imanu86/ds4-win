# G49 WRAP source-parts per-worker profile

Date: 2026-07-15

## Question

Can an opt-in CPU-only profile localize the intermittent WRAP long tail without
changing output or adding GPU readback/synchronization, and is its measurement
overhead acceptable?

This is a diagnostics gate, not a decode-throughput lever.

## Change

`DS4_CUDA_ARENA_WRAP_PART_PROFILE=1` instruments only the `source-parts`
WRAP copy path. `DS4_CUDA_ARENA_WRAP_SLOW_PART_MS` controls the slow-copy
threshold (25 ms here).

The disabled path checks the profile flag once and then enters the original
copy loop. The enabled path records local per-phase-worker parts, bytes, active
time, memcpy time, slow-part count, and the maximum single-part latency. The
coordinator records main-worker and join time. There is no per-part logging,
GPU readback, CUDA event, or added CUDA sync.

## Provenance

- Git HEAD before the G49 commit: `aeb839aec775f4e8eb16384a53aa964feca9353e`
- Executable SHA256: `6b70435fa4cedbeb196b39dba7b3ecc342aa620f633700c85c38a265ef0151f7`
- `ds4_cuda.cu` SHA256: `92719b68dbc445d4c21c8658101a4ea79651a4f02dc93a1aaf79bab77a901427`
- Harness SHA256: `cd2a134062af28fce1240b90b53d868ba3c5d1336f3d1178227d487d6fe048d5`
- Build-manifest SHA256: `e7cbbf4e21e42c04393fd650f4c6212da316b2ee59bcaadbd6b0e1da1749ee2e`
- Runner SHA256: `0e665ea75fc1446f5cafa6c2c2f47719d486ebc7f18367ffa79b4c9ada01d96c`
- Model: `C:\ds4-models\ds4-2bit.gguf`
- Raw matrix: `g7_runs/g49_wrap_part_profile_ab_result.json`
- Raw matrix SHA256: `4d042457dfc1adf0a4378c633dc7ad9aa9fec8bed73869b4c2a316076686ca1d`

## Protocol

Order: `off-a,on-a,off-b,on-b,off-c,on-c`; one fresh process per run.

```text
--cuda -c 256 -n 8 --host 127.0.0.1 --port 8000
BudgetGB=2 ReserveMB=1024 DynamicArenaGiB=30
ArenaWrapSourceParts=1 ArenaWrapTrustWorkerChecksum=1
DisableQ8F16Cache=1 EmbedRowStaging=1
PrefillMassWrap=1 ComposePrefillMassTiering=1
ExpertCacheN=320 ExpertCacheReserveGB=0 ExpertCachePolicy=lru
GpuResidentRoutes=1 RouteNoDefaultSync=1
ExpertTiering=enforce ExpertTierPolicy=mass-lfru
ExpertTierClockCalls=430 ExpertTierReplacementBudget=16
ExpertTierMinFrequency=3 ExpertTierHysteresis=1.25
RequestPhaseTrace=1 ReapPrefetchThreads=8
temperature=0 nothink=true
```

The on arm additionally uses `ArenaWrapPartProfile=1` and
`ArenaWrapSlowPartMs=25`.

Prompt:

```text
Rispondi in italiano con quattro punti numerati: spiega la differenza tra RAM,
VRAM e memoria virtuale. Sii conciso.
```

## Exactness and transport

All six runs produced the same eight-token byte sequence and content SHA256
`b78be49a2b62f691ee8a8b5b486b2735275cc85bbbc98ee3102c06116487a5e8`.

Every run measured 344 route calls, 355 VRAM routes, 1,709 pinned-RAM routes,
11.2654 GiB RAM-to-VRAM traffic, and zero SSD bytes, snapshot misses, route
errors, or tier failures.

## Results

| Run | Profile | WRAP s | TTFT s | Decode t/s |
|---|---:|---:|---:|---:|
| off-a | off | 24.072 | 44.300 | 3.63 |
| on-a | on | 27.211 | 47.225 | 3.73 |
| off-b | off | 25.849 | 45.935 | 3.72 |
| on-b | on | 25.754 | 46.221 | 3.60 |
| off-c | off | 26.795 | 46.615 | 3.72 |
| on-c | on | 32.596 | 52.092 | 3.49 |

WRAP off mean/median: 25.572/25.849 s.

WRAP on mean/median: 28.520/27.211 s.

Measured profiling cost: +11.5% mean and +5.3% median WRAP time. Therefore the
profile remains opt-in and is not suitable for normal performance runs. No run
crossed the predeclared 2x-combined-median outlier rule, so the three-extra-run
extension was not required.

Profile-on detail:

| Run | memcpy sum s | Main s | Join s | Phase-worker active min/max s | Phase-worker parts min/max | Slow parts | Max part ms | Kind |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| on-a | 188.420 | 27.077 | 0.069 | 4.158 / 12.558 | 501 / 662 | 121 | 6948.027 | up |
| on-b | 177.052 | 25.684 | 0.011 | 4.242 / 11.371 | 513 / 735 | 153 | 5555.590 | up |
| on-c | 231.709 | 32.497 | 0.038 | 7.210 / 15.932 | 535 / 607 | 2314 | 4308.179 | down |

Each run copied exactly 13,653 parts and 32,211,468,288 bytes over three
phases with eight workers. Maximum parts were 2,162,688-byte `up` copies or a
2,752,512-byte `down` copy.

## Measured conclusion

Coordinator join is not the normal wall: it consumed 11-69 ms, while aggregate
worker memcpy time was 177-232 seconds and individual 2-3 MiB copies took up to
6.95 seconds. During the profiled runs, available physical memory fell to
approximately 1 MiB, 2 MiB, and 254 MiB respectively.

This does not prove that memory pressure causes every historical 145-267 second
WRAP. It identifies a discriminating next test: keep the same source-parts
protocol while explicitly releasing pageable mmap source pages between the
gate/up/down phases, then compare n>=3 exact runs. On Windows, the existing
`cuda_model_discard_source_pages()` currently does nothing because only its
POSIX implementation is active.
