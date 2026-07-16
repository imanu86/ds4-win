# G74 Route-Packed-Copy Static32+SplitFused A/B Protocol

Date: 2026-07-16

## Question

On the exact frozen G73 static32+SplitFused workload, does adding
`-RoutePackedCopy` preserve exactness and all safety gates while replacing
legacy per-tensor route-miss submissions with one packed copy per missed expert?

The frozen control is full G73 `static32_split_fused`. The candidate is
identical plus `-RoutePackedCopy`.

## Frozen Workload

- model: `C:\ds4-models\ds4-2bit.gguf`;
- prompt: G46 cyberpunk single-file HTML prompt;
- prompt SHA-256:
  `38f6ec5ee5403f59dd2418eb5d9a5a94a0f0da19df015060383bb1ae46003bb6`;
- expected content SHA-256:
  `31cbc6504dcb57d42aeff9dbceb3aed943bcb32dae19a2edbf552e9fd2f52eb8`;
- context 256, max tokens 64, temperature zero, no thinking;
- dynamic arena 30 GiB, expected allocation 4551 slots;
- source-parts WRAP with trusted worker checksum;
- source reclaim enabled with 4 GiB waves, exactly 3 phases and 9 waves;
- expert cache requested and observed capacity 320, reserve 0.125 GiB;
- GPU resident routes enabled with `RouteNoDefaultSync`;
- prefill mass WRAP plus `ComposePrefillMassTiering`;
- expert tiering `enforce`, policy `mass-lfru`, clock 430, static replacement
  budget 32, min frequency 3, hysteresis 1.25;
- Q8/F16 cache disabled and embedding row staging enabled;
- `-SplitFused` enabled in both arms.

## Runner

The preregistered runner is `g74_route_packed_copy_ab.ps1`.

Supported modes:

- default: execute the protocol;
- `-StaticCheckOnly`: parse the runner and check required harness switches and
  counters exist without launching DS4;
- `-Resume`: reuse completed per-tag result JSON files and continue missing
  tags;
- `-SummarizeExisting`: summarize only already present result JSON files and
  fail closed if any required tag is missing.

The runner writes `g7_runs/g74_route_packed_copy_ab_result.json`.

## Sequence

1. Run the static check first:
   `powershell -NoProfile -ExecutionPolicy Bypass -File .\g74_route_packed_copy_ab.ps1 -StaticCheckOnly`.
2. Run one exact candidate safety process first:
   `g74_static32_split_fused_route_packed_copy_safety_exact`.
3. If candidate safety fails any contract, stop; no A/B matrix.
4. If candidate safety passes, run the preregistered interleaved matrix with
   three independent processes per arm:
   `static32_split_fused_a`,
   `static32_split_fused_route_packed_copy_a`,
   `static32_split_fused_route_packed_copy_b`,
   `static32_split_fused_b`,
   `static32_split_fused_c`,
   `static32_split_fused_route_packed_copy_c`.
5. If the outlier rule triggers after n=3, run exactly three more independent
   processes per arm before any verdict:
   `static32_split_fused_x1`,
   `static32_split_fused_route_packed_copy_x1`,
   `static32_split_fused_x2`,
   `static32_split_fused_route_packed_copy_x2`,
   `static32_split_fused_x3`,
   `static32_split_fused_route_packed_copy_x3`.

Safety timing is diagnostic only. A verdict must never be made from n=1.

## Required Contract

Every accepted run must satisfy all existing exactness, reclaim, cache,
no-sync, zero SSD, miss and failure gates:

- exact expected content SHA-256 and G46 prompt SHA-256;
- model path `C:\ds4-models\ds4-2bit.gguf`;
- context 256 and max tokens 64;
- dynamic arena requested 30 GiB and allocated 4551 slots;
- expert cache requested and observed capacity 320;
- expert tiering observed as `enforce/mass-lfru` with clock 430, static
  replacement budget 32, min frequency 3 and hysteresis 1.25;
- adaptive budget requested and enabled are false in both arms;
- source-parts WRAP, trusted worker checksum, WRAP published, request-scoped
  closed mask;
- source reclaim requested and observed with exactly three completed phases,
  exactly nine waves, max wave bytes at or below 4 GiB and zero failures;
- `ComposePrefillMassTiering` observed with 320 VRAM states;
- zero snapshot backing misses, zero forbidden SSD-to-VRAM transfers, zero tier
  SSD bytes and zero tier failures;
- GPU resident route errors zero;
- no-default-sync requested, default-sync calls zero, no-default-sync calls
  equal route calls;
- memory preflight, process isolation preflight and system quiescence preflight
  all report ready to launch.

Both arms must keep the G73 SplitFused contract exactly:

- split-fused requested and observed must both be true;
- `split_fused_calls` must equal `gpu_resident_routes_calls`;
- `split_fused_hits + split_fused_misses` must equal
  `expert_tiering.selected`;
- `split_fused_miss_scratch_bytes_avoided` and
  `split_fused_sum_read_bytes_avoided` must both be positive.

Candidate-specific packed-copy gates:

- `packed_copy_requested` and `packed_copy_observed` must both be true;
- `packed_copy_experts` must equal 10692, or at minimum be greater than zero
  and equal route miss experts (`split_fused_misses`);
- `packed_copy_submissions` must equal `packed_copy_experts`;
- `packed_copy_bytes` must equal `expert_tiering.ram_h2d_bytes`;
- `legacy_submissions` must be zero.

Control-specific packed-copy gates:

- packed copy requested, observed, experts, submissions and bytes must all be
  off or zero;
- `legacy_submissions` must equal `3 * split_fused_misses`.

## Primary Metrics

Report per-run values and per-arm mean/median where applicable:

- decode tokens per second;
- route wait ms/call and worker ms/job;
- packed-copy experts, packed-copy submissions and legacy submissions;
- packed-copy bytes, tier RAM H2D bytes and RAM H2D GiB;
- split-fused calls, hits, misses and avoided-byte counters;
- pinned-RAM hits and VRAM hits;
- VRAM promotions, free promotions, policy replacements, budget skips,
  admission skips and evictions;
- GPU resident route cache hits, misses, admissions and evictions.

Minimum available RAM, process read GiB, disk-read estimate, quiescence and
provenance are required diagnostics.

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

- Candidate `static32_split_fused_route_packed_copy` safety contract failure:
  stop immediately; no matrix.
- Any matrix contract, preflight or provenance mismatch: stop and mark invalid.
- Any expected SHA mismatch: stop and mark invalid.
- Any source reclaim phase/wave/failure mismatch: stop and mark invalid.
- Any backing miss, SSD byte, tier failure, arena slot mismatch, cache capacity
  mismatch, VRAM state mismatch or default-sync call: stop and mark invalid.
- Any SplitFused accounting mismatch in either arm: stop and mark invalid.
- Any packed-copy or legacy-submission accounting mismatch: stop and mark
  invalid.
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
RoutePackedCopy only if it preserves exactness, SplitFused accounting and all
packed-copy gates while improving decode throughput or route wait/worker time
without WRAP or TTFT-WRAP regression.
