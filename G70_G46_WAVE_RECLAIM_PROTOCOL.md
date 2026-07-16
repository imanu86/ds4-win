# G70 G46 Wave Reclaim A/B Protocol

Date: 2026-07-16

## Question

On the original G46 workload, does source-range reclaim with bounded 4 GiB
waves preserve exactness and improve the full G46 composition versus the same
composition without reclaim?

This protocol compares only one lever: `ArenaWrapUnlockSourceRanges` plus
`ArenaWrapUnlockWaveGiB=4`. It keeps the G46 workload and composition frozen:
full `C:\ds4-models\ds4-2bit.gguf`, G46 prompt and expected content hash,
context 256, max 64, no-default-sync GPU resident routes, cache 320, arena
30 GiB / 4551 slots, source-parts WRAP, trusted worker checksum, prefill mass
WRAP plus compose prefill mass tiering, and mass-LFRU expert tiering.

## Arms

- `legacy`: exact G46 composition, no source-range reclaim.
- `candidate`: exact G46 composition, `ArenaWrapUnlockSourceRanges` and
  `ArenaWrapUnlockWaveGiB=4`.

Both arms must request `RouteNoDefaultSync`. Default-sync calls must be zero and
no-default-sync calls must equal route calls.

## Runner

The preregistered runner is `g70_g46_wave_reclaim_ab.ps1`.

Supported modes:

- default: execute the protocol;
- `-Resume`: reuse completed per-tag result JSON files and continue missing
  tags;
- `-SummarizeExisting`: summarize only already present result JSON files and
  fail closed if any required tag is missing.

The runner writes `g7_runs/g70_g46_wave_reclaim_ab_result.json`.

## Sequence

1. Run one exact legacy safety process first.
2. If legacy safety fails due to a measured memory guard or arena-capacity
   symptom, record `capacity_asymmetry_recorded=true`. A generic quiescence or
   disk-queue failure is not classified as capacity.
3. If legacy safety passes, run one exact candidate safety process.
4. If legacy failed only for measured capacity and candidate safety passes, run
   three independent candidate-only processes. These measurements are
   descriptive and may establish exact standalone behavior, but are not an A/B
   and cannot support a causal reclaim performance claim.
5. If both safeties pass, run an interleaved matrix with three independent
   processes per arm:
   `legacy_a`, `candidate_a`, `legacy_b`, `candidate_b`, `legacy_c`,
   `candidate_c`.
6. If the outlier rule triggers after n=3, run exactly three more independent
   processes for every measured arm before any verdict.

Safety timings are diagnostics only. A verdict must never be made from n=1.

## Required Contract

Every accepted run must satisfy all of these checks:

- expected content SHA-256:
  `31cbc6504dcb57d42aeff9dbceb3aed943bcb32dae19a2edbf552e9fd2f52eb8`;
- model path `C:\ds4-models\ds4-2bit.gguf`;
- context 256 and max 64;
- dynamic arena requested 30 GiB and allocated 4551 slots;
- expert cache requested and observed capacity 320;
- source-parts WRAP, trusted worker checksum, WRAP published, request-scoped
  closed mask;
- `ComposePrefillMassTiering` observed with 320 VRAM states;
- zero snapshot backing misses, zero tier SSD bytes and zero tier failures;
- GPU resident route errors zero;
- no-default-sync requested, default-sync calls zero, no-default-sync calls equal
  route calls;
- memory preflight, process isolation preflight and system quiescence preflight
  all report ready to launch.

Candidate runs additionally require:

- source-range reclaim requested and observed;
- exactly three completed phases;
- wave cap observed as 4 GiB;
- maximum page-aligned wave bytes at or below 4 GiB;
- unlock failures zero;
- unlock calls accounted by `true + ERROR_NOT_LOCKED`.

Legacy runs additionally require that source-range reclaim is not observed.

## Provenance

The matrix is valid only if all successful runs have identical:

- git head;
- executable SHA-256;
- `ds4_cuda.cu` SHA-256;
- `ds4.c` SHA-256;
- build manifest SHA-256;
- build input fingerprint SHA-256;
- harness SHA-256;
- model path, byte size and last-write timestamp.

Each run keeps the harness-generated memory, process isolation and system
quiescence preflight artifacts.

## Stop Conditions

- Legacy safety capacity failure: record capacity asymmetry, then permit only a
  candidate safety plus candidate-only n>=3 descriptive sequence. No A/B or
  causal performance claim.
- Legacy safety contract failure: stop; no matrix.
- Candidate safety contract failure: stop; no matrix.
- Any matrix contract, preflight or provenance mismatch: stop and mark invalid.
- Any expected SHA mismatch: stop and mark invalid.
- Any backing miss, SSD byte, tier failure, arena slot mismatch, cache capacity
  mismatch or default-sync call: stop and mark invalid.

## Outlier Rule

After the first n=3 matrix, inspect each arm independently. If either
`decode_tokens_per_second` or `ttft_minus_wrap_seconds` has a max/min spread
greater than 20% within either arm, treat the matrix as outlier-contaminated and
run exactly three additional independent processes per arm.

The final summary must report whether this extension was triggered. No result
may be promoted from a single safety run.

## Interpretation

If legacy cannot pass the first safety under the current host state, a clean
candidate-only n>=3 sequence may report its own absolute metrics and exactness.
The only cross-arm statement permitted is capacity asymmetry; historical G46
timing is context, not a same-provenance speed control.

If both safeties and the full matrix pass with identical provenance, the runner
may summarize timing and transport diagnostics for the two arms. The protocol
still requires the raw JSON and preflight artifacts to remain the primary
evidence.
