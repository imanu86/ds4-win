# G125 Nested Residual GPU Join Safety Protocol

G125 is a fail-closed n=1 structural safety gate for
`DS4_NESTED_RESIDUAL_GPU_JOIN=1`. It verifies that the nested residual path
can join base and residual tensors on GPU while preserving the existing G123
/ G124 full/open routing contract and exact output hash.

## Scope

- Structural safety only, `n=1`.
- No SOTA verdict.
- No quality verdict.
- No performance/A/B conclusion from this run.
- Exactness is established only for the single configured prompt/output SHA,
  with runtime reconstruction verification enabled.

The runner is `g125_nested_gpu_join_safety.ps1`. It reuses the G124/G123
model, nested sidecar, cyberpunk prompt, and expected content SHA. The expected
content SHA is resolved from existing G124/G123 receipts or runners rather than
invented in the G125 script.

## Required Child Shape

The child is invoked through `g7_harness_bootstrap.ps1` and `g7_measure.ps1`
with:

- `-GateKind structural-safety`
- `-Repeats 1`
- `-MaxTokens 64`
- `-Context 256`
- `temperature = 0` and `think = false` from the harness request body
- `-ExpectedContentSHA256 <resolved G123/G124 content SHA>`
- `-ReuseVerifiedModelReceipt`
- nested residual sidecar SHA, source SHA, and payload SHA checks
- `-NestedResidualStructuralN1`
- `-NestedResidualVerifyReconstruction`
- `-NestedResidualGpuCache`
- `-NestedResidualGpuJoin`
- full/open routing: `-ComposePrefillMassOpenRouter`, `-ForceOpenRouter`,
  `-GpuResidentRoutes`, `-RouteNoDefaultSync`, `-SplitFused`
- no REAP/static/closed mask inputs

The bootstrap and harness keep the existing build manifest/provenance and
machine quiescence gates used by G124.

## Fail-Closed Runtime Counters

The harness parses exactly one GPU join summary when requested. It accepts
summary keys with no prefix or with `gpu_join_`, `nested_residual_`, or
`nested_residual_gpu_join_` prefixes.

G125 requires:

- GPU join requested and observed.
- Nested residual GPU cache requested and observed.
- Nested residual VRAM route misses are greater than zero.
- Nested residual VRAM host fills and host bytes are zero in GPU-join mode.
- Nested residual VRAM H2D bytes are greater than zero and equal to
  `misses * 7077888`.
- Runtime requested and observed counters equal `1`.
- `calls > 0`.
- `blocks > 0`.
- `base_h2d_bytes > 0`.
- `residual_h2d_bytes > 0`.
- `native_h2d_bytes == 0`.
- `gpu_join_wait_calls` is parsed and exported.
- `gpu_join_wait_seconds` is parsed and exported.
- `gpu_join_verify_seconds` is parsed/exported as
  `nested_residual_gpu_join_verify_seconds`.
- `cpu_reconstruct_calls == 0`.
- `verify_mismatches == 0`.
- `failures == 0`.
- Nested residual mismatches/failures remain zero.
- Output content SHA exactly matches the resolved expected SHA.

If GPU join telemetry appears while `-NestedResidualGpuJoin` is not requested,
the harness fails closed.

## Timing Interpretation

The receipt separates:

- candidate request seconds,
- GPU join candidate seconds,
- GPU join wait seconds,
- verification overhead seconds from `nested_residual_gpu_join_verify_seconds`.

`gpu_join_seconds` is enqueue-side timing. `gpu_join_wait_seconds` captures
scratch/event completion pressure, especially when verification is off. These
timers may overlap with each other and with other request timers, so they must not be summed into a performance claim. These timing fields are diagnostic only
in G125. They do not imply a speedup, regression, or SOTA result.

The G125 runner must not derive verification overhead from
`nested_residual_profile.verify_seconds`; that field belongs to the CPU-join
profiler and G125 does not request `-NestedResidualProfile`.

## Measured Safety Result

The current-build `n=1` safety gate passed with exact output, 1,261 GPU join
calls, positive base and residual H2D, zero native H2D, zero CPU
reconstruction, zero verification mismatch and zero runtime failure. This is
structural evidence only.

Receipt:

`C:\Users\imanu\AppData\Local\Packages\Claude_pzs8sxrjxfjjc\LocalCache\Local\ds4-win-work\g7_runs\g7_g125_nested_gpu_join_safety_current_build_clean_20260718T182935501Z_eb824ebedb_receipt.json`

SHA-256:

`ae15a6d3d3bc35e75b46befd8d18d7886f571e47d93561d146ada3ccf20f58fb`

## After G125 Passes

Only after G125 exactness and structural safety pass may a later protocol run an
`n >= 3` A/B comparison. That later comparison must keep exact output checking,
machine quiescence gates, build provenance, and equal host-budget accounting.

Exactness and quality are not inferred from this n=1 run beyond the single
configured output SHA and runtime reconstruction checks.

## Local Static Validation

Run only PowerShell static/parse tests for this protocol unless explicitly
authorized to run DS4:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/test_g125_nested_gpu_join_static.ps1
```

The static test validates runner syntax, `WhatIf`, required harness parser
markers, fail-closed markers, and the absence of forbidden DS4 runtime launch.
