# G71 Tier Budget A/B Protocol

Date: 2026-07-16

## Question

On the exact full-model G70 workload, does increasing the mass-LFRU expert
tiering replacement budget from 16 to 32 reduce pinned-RAM pressure without
breaking exactness, capacity, no-default-sync routing, or source-reclaim
provenance?

This is a static policy A/B. The only experimental variable is
`ExpertTierReplacementBudget`:

- `control`: 16, the G70 budget.
- `candidate`: 32.

Adaptive code is explicitly out of scope for this protocol. First run this
static test. Adaptive budget control may be designed only if budget 32 shows a
useful mechanism in the primary metrics, such as lower RAM hits/H2D or better
worker wait without a decode/TTFT regression and without added failures.

## Frozen Workload

- model: `C:\ds4-models\ds4-2bit.gguf`;
- prompt: G46 cyberpunk single-file HTML prompt;
- prompt SHA-256:
  `38f6ec5ee5403f59dd2418eb5d9a5a94a0f0da19df015060383bb1ae46003bb6`;
- expected content SHA-256:
  `31cbc6504dcb57d42aeff9dbceb3aed943bcb32dae19a2edbf552e9fd2f52eb8`;
- context 256, max 64, temperature zero, no thinking;
- dynamic arena 30 GiB, expected allocation 4551 slots;
- source-parts WRAP with trusted worker checksum;
- source reclaim enabled with 4 GiB waves;
- expert cache requested and observed capacity 320, reserve 0.125 GiB;
- GPU resident routes enabled with `RouteNoDefaultSync`;
- prefill mass WRAP plus `ComposePrefillMassTiering`;
- expert tiering `enforce`, policy `mass-lfru`, clock 430, min frequency 3,
  hysteresis 1.25;
- Q8/F16 cache disabled and embedding row staging enabled.

## Runner

The preregistered runner is `g71_tier_budget_ab.ps1`.

Supported modes:

- default: execute the protocol;
- `-StaticCheckOnly`: parse the runner and check that the required harness
  switches exist without launching DS4;
- `-Resume`: reuse completed per-tag result JSON files and continue missing
  tags;
- `-SummarizeExisting`: summarize only already present result JSON files and
  fail closed if any required tag is missing.

The runner writes `g7_runs/g71_tier_budget_ab_result.json`.

## Sequence

1. Run the static check first:
   `powershell -NoProfile -ExecutionPolicy Bypass -File .\g71_tier_budget_ab.ps1 -StaticCheckOnly`.
2. Run one exact candidate32 safety process first:
   `g71_candidate32_safety_exact`.
3. If candidate32 safety fails any contract, stop; no A/B matrix.
4. If candidate32 safety passes, run the preregistered interleaved matrix with
   three independent processes per arm:
   `control_a`, `candidate_a`, `candidate_b`, `control_b`, `control_c`,
   `candidate_c`.
5. If the outlier rule triggers after n=3, run exactly three more independent
   processes per arm before any verdict:
   `control_x1`, `candidate_x1`, `control_x2`, `candidate_x2`, `control_x3`,
   `candidate_x3`.

Safety timing is diagnostic only. A verdict must never be made from n=1.

## Required Contract

Every accepted run must satisfy all of these checks:

- exact expected content SHA-256 and G46 prompt SHA-256;
- model path `C:\ds4-models\ds4-2bit.gguf`;
- context 256 and max 64;
- dynamic arena requested 30 GiB and allocated 4551 slots;
- expert cache requested and observed capacity 320;
- expert tiering observed as `enforce/mass-lfru` with clock 430, min frequency
  3, hysteresis 1.25 and the arm-specific replacement budget;
- source-parts WRAP, trusted worker checksum, WRAP published, request-scoped
  closed mask;
- source reclaim requested and observed with exactly three completed phases,
  exactly nine waves, max wave bytes at or below 4 GiB and zero failures;
- `ComposePrefillMassTiering` observed with 320 VRAM states;
- zero snapshot backing misses, zero forbidden SSD-to-VRAM transfers, zero tier
  SSD bytes and zero tier failures;
- GPU resident route errors zero;
- no-default-sync requested, default-sync calls zero, no-default-sync calls equal
  route calls;
- memory preflight, process isolation preflight and system quiescence preflight
  all report ready to launch.

## Primary Metrics

Report per-run values and per-arm mean/median where applicable:

- decode tokens per second;
- pinned-RAM hits and RAM H2D GiB;
- VRAM promotions, free promotions, policy replacements, budget skips,
  admission skips and evictions;
- GPU resident route cache admissions/evictions;
- GPU route worker ms/job and wait ms/call.

TTFT, WRAP time, TTFT-WRAP, minimum available RAM, process read GiB, disk-read
estimate, quiescence and provenance are required diagnostics.

## Provenance

The matrix is valid only if all successful runs have identical:

- git head;
- executable SHA-256;
- `ds4_cuda.cu` SHA-256;
- `ds4.c` SHA-256;
- build manifest SHA-256;
- build input fingerprint SHA-256;
- harness SHA-256;
- model path, byte size and last-write timestamp;
- prompt SHA-256.

Each run keeps the harness-generated memory, process isolation and system
quiescence preflight artifacts.

## Stop Conditions

- Candidate32 safety contract failure: stop immediately; no matrix.
- Any matrix contract, preflight or provenance mismatch: stop and mark invalid.
- Any expected SHA mismatch: stop and mark invalid.
- Any source reclaim phase/wave/failure mismatch: stop and mark invalid.
- Any backing miss, SSD byte, tier failure, arena slot mismatch, cache capacity
  mismatch, VRAM state mismatch or default-sync call: stop and mark invalid.
- Any generic capacity, quiescence or process-isolation failure is a failed run,
  not a performance datapoint.

## Outlier Rule

After the first n=3 matrix, inspect each arm independently. If any of
`decode_tokens_per_second`, `wrap_seconds`, or `ttft_minus_wrap_seconds` has a
max/min spread greater than 20% within either arm, treat the matrix as
outlier-contaminated and run exactly three additional independent processes per
arm before any verdict.

The final summary must report whether this extension was triggered. No result
may be promoted from a single safety run.

## Interpretation

A useful budget32 signal requires exactness plus the full required contract and
same-provenance n>=3 evidence. Prefer candidate32 only if it reduces RAM/H2D or
worker wait through a clear tier-policy mechanism without adding failures,
default sync, SSD traffic, WRAP instability, or decode/TTFT regression.

If candidate32 only changes decode noise while RAM hits, H2D and policy
replacement counters remain effectively unchanged, keep budget16 and do not
write adaptive policy code.
