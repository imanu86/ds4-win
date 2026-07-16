# G72 Adaptive Tier Budget A/B Protocol

Date: 2026-07-16

## Question

On the exact full-model G70 workload, does adaptive mass-LFRU replacement
budget control starting at 16 and allowed to rise to 32 match or improve the
static 32 budget without breaking exactness, reclaim, cache, no-sync routing or
zero-SSD guarantees?

This is a static32 versus adaptive16_32 policy A/B. The only experimental
variable is the expert tier replacement-budget policy:

- `static32`: `-ExpertTierReplacementBudget 32`, adaptive budget disabled.
- `adaptive16_32`: `-ExpertTierReplacementBudget 16
  -ExpertTierAdaptiveBudget -ExpertTierAdaptiveMin 16
  -ExpertTierAdaptiveMax 32 -ExpertTierAdaptiveStep 8
  -ExpertTierAdaptivePressureThreshold 64`.

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

The preregistered runner is `g72_adaptive_tier_budget_ab.ps1`.

Supported modes:

- default: execute the protocol;
- `-StaticCheckOnly`: parse the runner and check that the required harness
  switches exist without launching DS4;
- `-Resume`: reuse completed per-tag result JSON files and continue missing
  tags;
- `-SummarizeExisting`: summarize only already present result JSON files and
  fail closed if any required tag is missing.

The runner writes `g7_runs/g72_adaptive_tier_budget_ab_result.json`.

## Sequence

1. Run the static check first:
   `powershell -NoProfile -ExecutionPolicy Bypass -File .\g72_adaptive_tier_budget_ab.ps1 -StaticCheckOnly`.
2. Run one exact candidate safety process first:
   `g72_adaptive16_32_safety_exact`.
3. If candidate safety fails any contract, stop; no A/B matrix.
4. If candidate safety passes, run the preregistered interleaved matrix with
   three independent processes per arm:
   `static32_a`, `adaptive16_32_a`, `adaptive16_32_b`, `static32_b`,
   `static32_c`, `adaptive16_32_c`.
5. If the outlier rule triggers after n=3, run exactly three more independent
   processes per arm before any verdict:
   `static32_x1`, `adaptive16_32_x1`, `static32_x2`,
   `adaptive16_32_x2`, `static32_x3`, `adaptive16_32_x3`.

Safety timing is diagnostic only. A verdict must never be made from n=1.

## Required Contract

Every accepted run must satisfy all G71 exactness, reclaim, cache, no-sync, zero
SSD, miss and failure gates:

- exact expected content SHA-256 and G46 prompt SHA-256;
- model path `C:\ds4-models\ds4-2bit.gguf`;
- context 256 and max 64;
- dynamic arena requested 30 GiB and allocated 4551 slots;
- expert cache requested and observed capacity 320;
- expert tiering observed as `enforce/mass-lfru` with clock 430, min frequency
  3, hysteresis 1.25 and the arm-specific budget policy;
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

Arm-specific checks are read from `expert_tiering`:

- `static32`: adaptive requested and enabled are false; replacement budget base
  is 32; final current budget is 32.
- `adaptive16_32`: adaptive requested and enabled are true; base budget is 16;
  min 16, max 32, step 8, pressure threshold 64; final current budget is 32;
  ups equals 2; downs equals 0; pressure epochs are at least 2.

## Primary Metrics

Report per-run values and per-arm mean/median where applicable:

- decode tokens per second;
- pinned-RAM hits and RAM H2D GiB;
- VRAM hits;
- VRAM promotions, free promotions, policy replacements, budget skips,
  admission skips and evictions;
- adaptive telemetry: requested/enabled, base/current budget, min/max/step,
  pressure threshold, ups, downs, pressure epochs, quiet epochs, last budget
  skip delta and last replacement delta;
- GPU resident route cache admissions/evictions;
- GPU route worker ms/job and wait ms/call.

TTFT, WRAP time, TTFT-WRAP, minimum available RAM, process read GiB, disk-read
estimate, quiescence and provenance are required diagnostics.

## Provenance

The matrix is valid only if all successful matrix runs have identical:

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

- Candidate adaptive16_32 safety contract failure: stop immediately; no matrix.
- Any matrix contract, preflight or provenance mismatch: stop and mark invalid.
- Any expected SHA mismatch: stop and mark invalid.
- Any source reclaim phase/wave/failure mismatch: stop and mark invalid.
- Any backing miss, SSD byte, tier failure, arena slot mismatch, cache capacity
  mismatch, VRAM state mismatch or default-sync call: stop and mark invalid.
- Any static/adaptive budget telemetry mismatch: stop and mark invalid.
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

A performance claim is allowed only from same-provenance n>=3 per arm. Prefer
adaptive16_32 only if it preserves exactness and all gates while reducing RAM
hits, RAM H2D, worker wait or replacement pressure without decode, WRAP or
TTFT-WRAP regression.

If adaptive only reaches static32 behavior with no mechanism improvement, keep
static32 as the simpler policy.
