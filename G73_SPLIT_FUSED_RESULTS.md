# G73 Split-Fused Static32 Results

Date: 2026-07-16

## Scope

Measurement-only report for `static32` versus `static32_split_fused` on the exact frozen G72 static32 full-model workload. Matrix completed with n=3 independent accepted runs per arm. The split-fused safety run passed before the matrix; its n=1 timing is not part of the performance verdict. Outlier extension was not triggered.

## Exactness, Gates, and Provenance

Performance claim allowed: yes.

All accepted matrix runs matched the required prompt SHA-256, expected content SHA-256, model path, context, max token count, 30 GiB dynamic arena, 4551 arena slots, expert cache capacity 320, source-parts WRAP publication, reclaim contract, no-default-sync routing, zero backing misses, zero forbidden SSD-to-VRAM transfers, zero tier SSD bytes, zero tier failures, zero GPU route errors, and identical provenance.

Reclaim was exactly 3 phases and 9 waves per accepted run, max wave bytes 4,293,894,144, failures 0. Route calls were 2,752 per run; default-sync calls were 0 and no-default-sync calls were 2,752.

Control telemetry matched the contract: split-fused requested/observed false and split-fused calls 0. Candidate telemetry matched the contract: split-fused requested/observed true, split-fused calls 2,752, hits 5,820, misses 10,692, hits plus misses 16,512 selected experts, and positive avoided counters of 175,177,728 bytes each for miss scratch and sum-read.

## Per-Run Primary Measurements

| run | arm | decode tok/s | TTFT s | WRAP s | TTFT-WRAP s | split calls | split hits | split misses | avoided bytes | RAM hits | RAM H2D GiB | VRAM hits | promotions | replacements | budget skips | route wait ms/call | worker ms/job |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| g73_static32_a | static32 | 4.62 | 52.660 | 29.250 | 23.410 | 0 | 0 | 0 | 0 | 10692 | 70.479492 | 5820 | 512 | 192 | 4731 | 4.300 | 1.582 |
| g73_static32_b | static32 | 4.58 | 52.881 | 29.303 | 23.578 | 0 | 0 | 0 | 0 | 10692 | 70.479492 | 5820 | 512 | 192 | 4731 | 4.334 | 1.585 |
| g73_static32_c | static32 | 4.63 | 56.869 | 33.119 | 23.750 | 0 | 0 | 0 | 0 | 10692 | 70.479492 | 5820 | 512 | 192 | 4731 | 4.309 | 1.576 |
| g73_static32_split_fused_a | static32_split_fused | 4.98 | 58.153 | 34.371 | 23.782 | 2752 | 5820 | 10692 | 175177728 | 10692 | 70.479492 | 5820 | 512 | 192 | 4731 | 3.956 | 1.526 |
| g73_static32_split_fused_b | static32_split_fused | 4.97 | 53.406 | 29.650 | 23.756 | 2752 | 5820 | 10692 | 175177728 | 10692 | 70.479492 | 5820 | 512 | 192 | 4731 | 3.944 | 1.525 |
| g73_static32_split_fused_c | static32_split_fused | 5.01 | 52.703 | 29.157 | 23.546 | 2752 | 5820 | 10692 | 175177728 | 10692 | 70.479492 | 5820 | 512 | 192 | 4731 | 3.922 | 1.517 |

All accepted runs had RAM evictions 0, admission skips 0, GPU route cache admissions 512, and GPU route cache evictions 192.

## Arm Means and Effects

| metric | static32 mean | static32_split_fused mean | split-fused effect |
|---|---:|---:|---:|
| decode tokens/s | 4.610000 | 4.986667 | +0.376667 (+8.171%) |
| decode tokens/s median | 4.62 | 4.98 | +0.36 (+7.792%) |
| TTFT s | 54.136667 | 54.754000 | +0.617333 (+1.140%) |
| WRAP s | 30.557333 | 31.059333 | +0.502000 (+1.643%) |
| TTFT-WRAP s | 23.579333 | 23.694667 | +0.115334 (+0.489%) |
| route wait ms/call | 4.314333 | 3.940667 | -0.373666 (-8.661%) |
| route worker ms/job | 1.581000 | 1.522667 | -0.058333 (-3.690%) |
| split-fused calls | 0 | 2752 | +2752 |
| split-fused hits | 0 | 5820 | +5820 |
| split-fused misses | 0 | 10692 | +10692 |
| miss-scratch bytes avoided | 0 | 175177728 | +175177728 |
| sum-read bytes avoided | 0 | 175177728 | +175177728 |
| RAM hits | 10692 | 10692 | 0 (0.000%) |
| RAM H2D GiB | 70.479492 | 70.479492 | 0.000000 (0.000%) |
| VRAM hits | 5820 | 5820 | 0 (0.000%) |
| VRAM promotions | 512 | 512 | 0 (0.000%) |
| policy replacements | 192 | 192 | 0 (0.000%) |
| policy budget skips | 4731 | 4731 | 0 (0.000%) |

## Diagnostics

Minimum available RAM across accepted matrix runs was 1.946148 GiB. Disk-read estimates ranged from 52.232415 to 57.530310 GiB. Process read ranged from 24.017618 to 24.517618 GiB. Quiescence and preflight gates were ready for all accepted matrix runs.

Safety timing is intentionally excluded from the verdict. The safety run established exactness and split-fused accounting before the matrix; only the same-provenance n=3 per-arm matrix supports performance interpretation.

## Verdict

`static32_split_fused` is correct: it preserved exactness, provenance, reclaim, cache, no-sync routing, zero-SSD, miss, and failure gates while satisfying the split-fused accounting gates.

The mechanism evidence is positive. Split-fused executed once per route call, accounted for every selected expert through hit plus miss counters, avoided 175,177,728 bytes of miss scratch and 175,177,728 bytes of sum-read work per run, and reduced mean route wait by 8.661% and worker ms/job by 3.690% with unchanged RAM/VRAM/cache/tiering counts.

It is a throughput win on mean and median decode for this n=3 matrix, but not a clean default promotion under the preregistered preference rule because mean WRAP rose 1.643% and mean TTFT-WRAP rose 0.489%. Treat it as a correct overhead-reduction candidate with promising decode throughput, not yet a strict replacement for `static32`.
