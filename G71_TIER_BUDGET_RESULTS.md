# G71 Tier Replacement-Budget Results

Date: 2026-07-16

## Result

G71 is a positive full-model transport result. Raising the existing mass-LFRU
replacement budget from 16 to 32 reduced RAM-to-VRAM traffic and improved decode
throughput on the frozen G70 workload.

The preregistered outlier rule triggered because one candidate run spent
244.670 seconds in WRAP. Three additional independent processes per arm were
therefore collected. The final comparison uses six exact processes per arm.

| Metric | Budget 16 | Budget 32 | Change |
|---|---:|---:|---:|
| Decode mean, t/s | 4.565000 | 4.611667 | +1.02% |
| Decode median, t/s | 4.560000 | 4.615000 | +1.21% |
| RAM hits | 10,859 | 10,692 | -167 (-1.54%) |
| RAM H2D, GiB | 71.580322 | 70.479492 | -1.100830 (-1.54%) |
| VRAM promotions | 416 | 512 | +96 |
| Policy replacements | 96 | 192 | +96 |
| Policy budget skips | 5,040 | 4,731 | -309 |
| Route wait, ms/call | 4.397000 | 4.336833 | -1.37% |
| Route worker, ms/job | 1.624500 | 1.586667 | -2.33% |

All six processes in both arms produced the expected content SHA-256. Every
accepted run had 4,551 arena slots, 320 VRAM states, zero snapshot backing
misses, zero SSD bytes, zero tier failures, zero forbidden cold-SSD-to-VRAM
transfers and zero default-stream synchronization calls.

## WRAP Outlier

`g71_candidate_b` had TTFT 269.093 seconds and WRAP 244.670 seconds while its
decode remained 4.62 t/s and all tier counters exactly matched every other
budget-32 process. The extension cohort returned to about 29 seconds WRAP.

This outlier is retained in the raw data and in the all-run TTFT/WRAP mean. It
does not explain the decode or H2D result: the transport counters were constant
within each arm across all six processes.

## Interpretation

Budget 32 is the new static tier-budget candidate for this workload. The causal
mechanism is measured: it permits 96 additional useful replacements, removes
167 RAM fetches and 1.100830 GiB of H2D traffic, and reduces route worker/wait
time without changing output or introducing misses.

This is not yet a long-output quality claim and it does not establish that 32 is
globally optimal. The next experiment may implement a bounded adaptive budget,
but only as a separate A/B against this measured static-32 candidate.

Canonical machine-readable summary:
`g7_runs/g71_tier_budget_ab_result.json`.

