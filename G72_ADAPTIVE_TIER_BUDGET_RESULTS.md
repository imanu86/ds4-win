# G72 Adaptive Tier Budget Results

Date: 2026-07-16

## Scope

Measurement-only report for `static32` versus `adaptive16_32` on the frozen G70 full-model workload. Matrix completed with n=3 independent accepted runs per arm. The adaptive safety run passed before the matrix. Outlier extension was not triggered.

## Exactness, Gates, and Provenance

Performance claim allowed: yes.

All accepted matrix runs matched the required prompt SHA-256, expected content SHA-256, model path, context, max token count, 30 GiB dynamic arena, 4551 arena slots, expert cache capacity 320, source-parts WRAP publication, reclaim contract, no-default-sync routing, zero backing misses, zero forbidden SSD-to-VRAM transfers, zero tier SSD bytes, zero tier failures, zero GPU route errors, and identical provenance.

Reclaim was exactly 3 phases and 9 waves per accepted run, max wave bytes 4,293,894,144, failures 0. Route calls were 2,752 per run; default-sync calls were 0 and no-default-sync calls were 2,752.

Static arm telemetry matched the contract: adaptive requested/enabled false, base budget 32, final current budget 32. Adaptive arm telemetry matched the contract: adaptive requested/enabled true, base 16, min 16, max 32, step 8, pressure threshold 64, final current budget 32, ups 2, downs 0, pressure epochs 5.

## Per-Run Primary Measurements

| run | arm | decode tok/s | TTFT s | WRAP s | TTFT-WRAP s | RAM hits | RAM H2D GiB | VRAM hits | promotions | replacements | budget skips | route wait ms/call | worker ms/job |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| g72_static32_a | static32 | 4.62 | 53.536 | 30.129 | 23.407 | 10692 | 70.479492 | 5820 | 512 | 192 | 4731 | 4.326 | 1.589 |
| g72_static32_b | static32 | 4.60 | 52.245 | 29.144 | 23.101 | 10692 | 70.479492 | 5820 | 512 | 192 | 4731 | 4.301 | 1.593 |
| g72_static32_c | static32 | 4.62 | 52.697 | 29.041 | 23.656 | 10692 | 70.479492 | 5820 | 512 | 192 | 4731 | 4.300 | 1.580 |
| g72_adaptive16_32_a | adaptive16_32 | 4.62 | 52.691 | 29.007 | 23.684 | 10668 | 70.321289 | 5844 | 488 | 168 | 4736 | 4.295 | 1.582 |
| g72_adaptive16_32_b | adaptive16_32 | 4.58 | 56.983 | 33.213 | 23.770 | 10668 | 70.321289 | 5844 | 488 | 168 | 4736 | 4.321 | 1.595 |
| g72_adaptive16_32_c | adaptive16_32 | 4.62 | 52.826 | 29.192 | 23.634 | 10668 | 70.321289 | 5844 | 488 | 168 | 4736 | 4.291 | 1.574 |

All accepted runs had RAM evictions 0, admission skips 0, GPU route cache admissions equal to promotions, and GPU route cache evictions equal to replacements.

## Arm Means and Effects

| metric | static32 mean | adaptive16_32 mean | adaptive effect |
|---|---:|---:|---:|
| decode tokens/s | 4.613333 | 4.606667 | -0.006666 (-0.144%) |
| decode tokens/s median | 4.62 | 4.62 | 0.00 (0.000%) |
| TTFT s | 52.826000 | 54.166667 | +1.340667 (+2.538%) |
| WRAP s | 29.438000 | 30.470667 | +1.032667 (+3.508%) |
| TTFT-WRAP s | 23.388000 | 23.696000 | +0.308000 (+1.317%) |
| RAM hits | 10692 | 10668 | -24 (-0.224%) |
| RAM H2D GiB | 70.479492 | 70.321289 | -0.158203 (-0.224%) |
| VRAM hits | 5820 | 5844 | +24 (+0.412%) |
| VRAM promotions | 512 | 488 | -24 (-4.688%) |
| policy replacements | 192 | 168 | -24 (-12.500%) |
| policy budget skips | 4731 | 4736 | +5 (+0.106%) |
| route wait ms/call | 4.309000 | 4.302333 | -0.006667 (-0.155%) |
| route worker ms/job | 1.587333 | 1.583667 | -0.003666 (-0.231%) |

Adaptive telemetry means: requested/enabled true, base/current 16/32, min/max/step 16/32/8, pressure threshold 64, ups 2, downs 0, pressure epochs 5, quiet epochs 0, last budget skip delta 1156, last replacement delta 32.

## Diagnostics

Minimum available RAM across accepted matrix runs was 2.212582 GiB. Disk-read estimates ranged from 52.651019 to 57.722890 GiB. Process read ranged from 23.955118 to 25.319056 GiB. Quiescence and preflight gates were ready for all accepted matrix runs.

One failed/retried WRAP process is recorded as an infrastructure-invalid attempt, not a performance datapoint. The retry reused the same tag, so the successful transcript replaced the first attempt's stderr; this limitation and the observed failure are disclosed in `g7_runs/g72_static32_c_infrastructure_retry_incident.json`. No root cause is established from the available evidence.

## Verdict

`adaptive16_32` is correct: it preserved exactness, provenance, reclaim, cache, no-sync routing, zero-SSD, miss, and failure gates while reaching final budget 32 through the required two upward steps.

It is not throughput SOTA on this workload. Mean decode throughput was slightly lower than `static32` (-0.144%), median decode throughput was tied, and mean WRAP/TTFT/TTFT-WRAP were higher. Adaptive did reduce RAM hits, RAM H2D, promotions, and policy replacements, but the reductions were small and did not translate into a throughput win.

Default remains `static32` because it is simpler and at least as fast for this measured workload.
