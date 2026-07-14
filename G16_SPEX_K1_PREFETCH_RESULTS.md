# G16: functional SPEX K1 expert prefetch

Date: 2026-07-13

Parent commit: `b730e3e` (`experiment: profile SPEX prefetch width`)

## Question

Can the measured next-layer SPEX K1 prediction move one complete expert off
the synchronous selected-load path on native Windows, without changing router
selection or model output, and improve decode throughput?

## Implementation

The opt-in `DS4_SPEX_PREFETCH_K=1` path adds a two-slot worker queue. The worker
owns a duplicated model handle, page-locked host staging, a dedicated CUDA
stream, and dedicated device slabs. Each job reads one gate, up, and down
expert (7,077,888 bytes, 6.75 MiB) with positioned reads and uploads it outside
the decode thread.

The existing ring1 prediction readback is retired immediately after SPEX
scoring in the source layer when functional prefetch is enabled. This does not
add a prediction wait: it moves the existing ring1 wait earlier and gives the
worker the remainder of the source layer in which to load the target expert.

At selected-load time, a slab is consumed only when all of these match:

- epoch, decode sequence, source layer, and target layer;
- target gate/up/down offsets;
- the predicted expert is present in the actual router-selected compact set;
- the worker has published the slot as ready.

On a match, three device-to-device copies place that expert in its normal
compact gather slot. All other experts use the unchanged selected-load path.
Queued/loading/mismatched jobs never make decode wait; they are discarded and
the normal path runs. Resident expert cache and disabled selected-load are
incompatible with this experiment; a whole model-window hit explicitly
cancels its pending job.

The reviewed worker fences its upload stream even after a partial H2D enqueue
failure. An unfenceable slot is quarantined, the queue disables itself, and
the condition is exposed through `poisoned`, `errors`, and `disabled` counters.
Telemetry distinguishes router `matched` jobs from jobs that reached compact
gather `consumed`; bytes-used increments only at consumption.

The harness records requested/observed K, activation, submitted/loaded/matched/
consumed/no-hit/late/canceled/poisoned/error counts, bytes read/used, source and
executable hashes, HTTP result count, and the externally supplied output hash.
Functional runs require conserved accounting.

## Safety progression

Submitting at target-layer entry produced 756 submitted jobs, 756 late jobs,
zero hits, and zero errors. Moving the same ring1 retirement and submit point
into the source layer produced 756 loaded jobs, 406 matches, 350 no-hit jobs,
zero late jobs, and zero errors. Prediction telemetry was then retained per
target layer instead of being overwritten by the following prediction.

Independent review found and prompted fixes for partial-H2D error fencing,
quarantine, incompatible modes, cancellation, matched-versus-consumed
accounting, and harness conservation checks. The final reviewed executable
`c034c4c597cbb0a4e64b3048d5f0da18bc5a84ea36e9ec564035c4f55f18c202`
passed a strict warm safety run with:

- 756 submitted and loaded;
- 406 matched and 406 consumed;
- 350 no-hit;
- zero dropped, canceled, late, poisoned, or error jobs;
- 756 ready predictions and 756 compared layers.

Every safety output was exactly:

```text
Hello! How can I help you today?
```

SHA-256: `fda564ba3f7a0f028106d468420f674898ed99ac5bf2765ac9586206e39d73c5`.

## A/B protocol

Each pair used one identical executable for control and treatment, native
Windows/WDDM, RTX 3060 12 GB, the same 86,720,111,488-byte model, greedy/no-think,
one discarded warmup, three measured requests, 2 GB model-stream budget, 1 GB
reserve, selected load enabled, I/O QD1, no resident expert cache, SPEX full
stage, cap1, and ring1.

Two short `Hi` pairs requested 12 tokens and stopped naturally after nine. The
long pair used the established 64-token cyberpunk HTML prompt and its external
expected SHA-256
`fd6c4522975a71e252b90199d49cfe3236310e2a7285dc0fc4d0e9d0e4885510`.
The second short pair and Cyber64 pair used executable
`5b6c4822a6ef24c7a084ffedcc8ab27dc38ee5bc54c0d07d7ba8c9a39f054ccf`.

Predictor-only command suffix:

```powershell
-Warmup -Repeats 3 -MaxTokens <12|64> -BudgetGB 2 -ReserveMB 1024 `
-SpexDryRun -SpexStage full -SpexCap 1 -SpexRingSlots 1
```

Functional prefetch adds:

```powershell
-SpexPrefetchK 1
```

Complete commands, SPEX/model/source/executable hashes, and outputs are
preserved in each result JSON.

## Measured results

| Pair | Predictor-only t/s | K1 prefetch t/s | Delta | Layer predictions | Legacy matched/no-hit | Output |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| `Hi` A | 2.856667 | 2.836667 | -0.70% | 1,512 | 812 / 700 | exact |
| `Hi` B | 2.766667 | 2.850000 | +3.01% | 1,512 | 812 / 700 | exact |
| Cyber64 | 1.516667 | 0.693333 | -54.29% | 10,752 | 5,992 / 4,760 | exact |

The short pairs reverse sign. Their control-to-control shift is larger than
the first observed effect, so they support mechanics only, not a throughput
direction.

Cyber64 has narrow control dispersion (1.51-1.53 t/s) and a large treatment
effect. The K1 worker read 76,101,451,776 bytes; the pre-review counter
classified 42,410,704,896 bytes as matched and 33,690,746,880 bytes as unused.
Treatment repeat one reached 1.34 t/s, then repeats two and three fell to 0.37
t/s while stderr repeatedly reported model-tensor reloads. Mean server decode
throughput was 0.693333 t/s. The log proves the reloads and progressive
slowdown occurred together; cache/page pressure is the leading explanation,
not a separately isolated claim.

All repeated outputs were identical inside each run and matched their external
baseline hashes. The performance A/B predates the review-only error/accounting
hardening; the reviewed binary was rebuilt and passed strict safety.

## Verdict

The worker, early-submit window, exact-key consumption, and nonblocking
fallback are functional. **Unconditional learned K1 prefetch is rejected for
performance.** Its measured precision is 53.70% on `Hi` and 55.73% on
Cyber64, creating too much unused traffic. The long test measures a severe
progressive regression. Do not widen this learned path to K2/K4/K6.

A score-confidence gate remains a research question, but it is not the next
lever. PocketMoE demonstrates a stronger transferable experiment:
DeepSeek-V4's first three hash-routed layers expose their exact six expert IDs
through `tid2eid`. G17 should pre-stage exact K6 for those layers only, with
SPEX and resident caches off, direct upload into the consumable slab,
consume/stage CUDA events, `bytes_read == bytes_used`, and no speculative I/O.
This tests the overlap infrastructure at 100% precision before returning to
learned prediction.

## Artifacts

- `g7_runs/g7_g16_k1_prefetch_safety_n1_result.json`: target-entry submit,
  100% late negative result.
- `g7_runs/g7_g16_k1_early_safety_n1_result.json`: early-submit functional
  safety before per-layer telemetry repair.
- `g7_runs/g7_g16_k1_early_stats_safety_n1_result.json`: aligned telemetry.
- `g7_runs/g7_g16_final_k1_predictor_only_hi12_n3_result.json` and matching
  prefetch JSON: first short pair.
- `g7_runs/g7_g16_final2_k1_predictor_only_hi12_n3_result.json` and matching
  prefetch JSON: current-source short pair with reversed sign.
- `g7_runs/g7_g16_final_cyber64_k1_predictor_only_n3_result.json` and matching
  prefetch JSON: decisive long-prompt regression.
- `g7_runs/g7_g16_final_reviewed_k1_safety_n1_result.json`: strict safety and
  matched-versus-consumed accounting on the reviewed binary.
