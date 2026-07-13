# G15: SPEX prediction-cap profile

Date: 2026-07-13

Runtime commit: `525e2c2` (`experiment: add nonblocking SPEX readback ring`)

## Question

How many next-layer experts should the first functional prefetch worker load?
K6 maximizes measured set recall, but each complete expert is 6.75 MiB, so a
wide speculative load can add more I/O than it removes.

## Protocol

All variants used the same executable, model, `Hi` prompt, discarded warmup,
three measured greedy requests, blocking ring1 for 100% prediction coverage,
and an externally supplied expected output hash.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\g7_measure.ps1 `
  -MaxTokens 12 -Repeats 3 -BudgetGB 2 -ReserveMB 1024 -Warmup `
  -ExpectedContentSHA256 fda564ba3f7a0f028106d468420f674898ed99ac5bf2765ac9586206e39d73c5 `
  -ModelPath C:\ds4-models\ds4-2bit.gguf `
  -SpexDryRun `
  -SpexFile C:\Users\imanu\source\repos\moe-aggressive-commit\runs\spex\spex_model\ds4flash_d2_nextlayer.spex `
  -SpexStage full -SpexRingSlots 1 -SpexCap <1|2|4>
```

Every output was exactly `Hello! How can I help you today?` and matched the
baseline SHA-256. Each configuration compared 1,512 layer predictions against
9,072 actual router-selected experts.

## Measured results

| Predicted K | Hits | Recall | Prediction precision | Mean useful experts/layer |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 812 | 0.0895 | 0.5370 | 0.5370 |
| 2 | 1,404 | 0.1548 | 0.4643 | 0.9286 |
| 4 | 2,304 | 0.2540 | 0.3810 | 1.5238 |
| 6 | 2,792 | 0.3078 | 0.3078 | 1.8466 |

K6 is the G14 full-coverage ring1 measurement. Precision is measured hits
divided by emitted predictions; useful experts per layer is measured hits
divided by compared layers.

## Decision

Start functional prefetch at K1. It has the best measured precision and limits
speculative traffic to one 6.75 MiB expert per target layer. K2 is the first
follow-up only if K1 demonstrates a net throughput benefit. K4/K6 remain
diagnostic settings and must not be assumed faster merely because recall is
higher.

This result selects a test point; it is not yet evidence that prefetch improves
throughput.
