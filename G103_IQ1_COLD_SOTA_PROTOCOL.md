# G103 IQ1_S Cold SOTA A/B Protocol

G103 is a preregistered A/B runner for comparing the exact G73
`static32_split_fused` control against the same stack with an IQ1_S cold sidecar.

## Scope

- Runner: `g103_iq1_cold_sota_ab.ps1`
- Static test: `tests\test_g103_static_contract.ps1`
- Summary artifact: `g7_runs\g103_iq1_cold_sota_ab_result.json`
- Static check must not require model files, build, GPU, or DS4 launch.
- Runtime must not use `D:` and must not create or modify files under
  `C:\ds4-models`; required verified receipts must already exist beside the
  model files.

## Model And Prompt Provenance

- Main model: `C:\ds4-models\ds4-2bit.gguf`
- Main model SHA-256:
  `efc7ed607ff27076e3e501fc3fefefa33c0ed8cf1eff483a2b7fdc0c2e616668`
- IQ1_S sidecar: `C:\ds4-models\DeepSeek-V4-Flash-IQ1_S-XL.gguf`
- IQ1_S sidecar SHA-256:
  `b049d1eb34c068f19ab007b33c22a7d758b578bf2b10d9276e79654f85d35047`
- IQ1_S sidecar bytes: `61540805344`
- Prompt: exact G73 cyberpunk HTML prompt.
- Prompt SHA-256:
  `38f6ec5ee5403f59dd2418eb5d9a5a94a0f0da19df015060383bb1ae46003bb6`

## Arms

Control is exact G73 `static32_split_fused`:

- `DynamicArenaGiB 30`, expected slots `4551`
- `ExpertCacheN 320`
- WRAP source-parts, trust worker checksum, unlock source ranges, wave `4 GiB`
- `PrefillMassWrap` plus `ComposePrefillMassTiering`
- tier enforce `mass-lfru`, clock `430`, budget `32`, min frequency `3`,
  hysteresis `1.25`
- GPU resident routes, `RouteNoDefaultSync`, `SplitFused`
- `ExpectedContentSHA256`
  `31cbc6504dcb57d42aeff9dbceb3aed943bcb32dae19a2edbf552e9fd2f52eb8`
- `ReuseVerifiedModelReceipt`

Candidate is the same stack plus:

- `Iq1SExpertSidecar C:\ds4-models\DeepSeek-V4-Flash-IQ1_S-XL.gguf`
- `ReuseVerifiedModelReceipt` and `ReuseVerifiedIq1SReceipt`
- `Iq1SLayerFirst 3`, `Iq1SLayerLast 42`
- `Iq1SMixedColdOne`
- `Iq1SMixedGpuPlan`
- `Iq1SRamCacheGiB 0.5`

The original preregistration used 1 GiB. The first post-reboot structural
safety run measured a fail-closed `cudaHostAlloc` OOM after the unchanged
30 GiB G73 arena had been published. A same-stack 0.5 GiB probe then
completed with 109 pinned IQ1_S slots and zero cache/runtime failures. G103
therefore uses 0.5 GiB so the candidate remains additive to the complete G73
arena instead of shrinking the SOTA arena. The failed 1 GiB run and the 0.5
GiB feasibility probe are structural evidence only, never performance or
quality verdicts.

Candidate must not use `ExpectedContentSHA256`, because IQ1 quantization may
change the output hash. It must record the observed output hash.

## Forbidden Features

The runner must not enable:

- `Iq1Promotion`
- `ComposePrefillMassOpenRouter`
- `ComposePrefillMassReserveSlots`
- `RoutePackedCopy`
- `Iq1SPackedH2D`
- IQ1_S VRAM cache
- path-bound receipt reuse for benchmark members

## Execution Plan

1. Run candidate safety `n=1` with `GateKind structural-safety`.
   Use `g103_iq1_cold_sota_ab.ps1 -SafetyOnly`; this writes a structural
   summary and exits before the matrix. Continue later with `-Resume`.
2. Run 3 independent processes per arm, interleaved:
   control 1, candidate 1, control 2, candidate 2, control 3, candidate 3.
3. If either arm has a max/min outlier ratio greater than `20%` on primary
   timing metrics after `n=3`, run 3 additional independent processes per arm,
   still interleaved.

Safety `n=1` is structural only and can never support a quality or SOTA claim.

Each benchmark arm is also one independent `Repeats=1` process. Its member
receipt must remain individually non-eligible with reason
`repeats-less-than-3-not-quality-eligible`; only this runner's interleaved
aggregate of at least three independent processes per arm may support a
performance comparison. The safety member must use the exact reason
`structural-safety-gate-not-quality-eligible`.

Native child stdout is consumed by `Out-Host`; only the typed arm receipt is
allowed onto the runner's success pipeline. This prevents harness progress
lines from becoming false matrix rows or replacing the safety receipt.

Path-bound receipt reuse is restricted to structural safety by the harness.
For the benchmark matrix, the parent holds read/deny-write/delete locks on the
IQ2 model and IQ1_S sidecar, creates one full-hash model+IQ1 suite receipt, and
reuses it only for candidate members. Control members remain sidecar-free G73
and independently hash the IQ2 model, so provenance amortization cannot alter
the control runtime configuration.

## Gates

Candidate gate requires:

- arena slots `4551` and arena not capped
- cache `320`
- SplitFused requested, observed, and accounting matches route calls
- IQ1_S sidecar runtime observed
- IQ1_S mixed runtime observed
- IQ1_S GPU planner requested and observed
- failures equal zero across tiering, sidecar, RAM cache, mixed, planner, and
  promotion telemetry
- mixed calls, cold IQ1 calls, and joins all greater than zero
- promotion requested false
- RoutePackedCopy false
- no forbidden direct cold SSD to VRAM
- `tier.ssd_bytes` remains zero for IQ2 backing
- `iq1_s_ram_cache_ssd_bytes` is allowed and measured separately

Candidate output gate requires valid non-empty output, clean finish, nonfinite
runtime state, zero reported failures, and deterministic content hash across at
least three independent candidate processes. The current harness does not emit
a general nonfinite-output counter unless the intrusive IQ1 debug path is
enabled, so G103 does not infer a zero count from missing telemetry.

All accepted matrix processes must share the same git head, executable, CUDA
and C source hashes, build manifest/fingerprint, harness, model and prompt
provenance. Runtime contamination aborts and non-empty contamination reasons
invalidate the process. G73 reclaim accounting remains fixed at three phases,
nine waves, waves at most 4 GiB and zero failures.

## Measured Result

The preregistered interleaved matrix completed on 2026-07-17 with three
independent processes per arm and no outlier extension:

| Arm | Server decode t/s | Mean | Median |
| --- | --- | ---: | ---: |
| G73 control | 5.04, 5.11, 4.96 | 5.0367 | 5.04 |
| G73 plus one cold IQ1_S expert | 2.71, 2.71, 2.69 | 2.7033 | 2.71 |

The candidate is 46.32% slower in server decode throughput. Every candidate
process recorded 2,560 mixed calls, 178 IQ1 RAM-cache hits, 2,382 misses,
2,273 evictions, 10.904 GiB read from the IQ1 sidecar, 11.719 GiB sent over
IQ1 H2D, and zero failures. The 109-slot cache therefore achieved only a
6.95% hit rate. The G73 IQ2 backing path remained at zero SSD bytes.

The control retained the expected content SHA-256
`31cbc6504dcb57d42aeff9dbceb3aed943bcb32dae19a2edbf552e9fd2f52eb8`.
The candidate was deterministic across all three processes with content
SHA-256
`4aaf0f0813f4cb15ac21a88f195f4f7d2c2af797e81524935e22eea60603c6b1`.
This 64-token matrix is not a quality verdict; L0-L3 quality remains a
separate n>=3 gate.

The aggregate initially stopped after all six valid runs because it requested
the nonexistent `build_input_fingerprint_sha256` field instead of the emitted
`build_manifest_input_fingerprint_sha256`. Resume now validates the existing
full-hash suite receipt against current path, bytes, timestamps, file IDs and
declared hashes under the parent locks. The corrected aggregate reused the six
raw results without launching DS4 again.

## Next Gate

Profile one candidate process to split IQ1 SSD read, H2D enqueue/sync, hot-IQ2
submit, cold-IQ1 submit and join time. Only after that structural profile,
test one transport lever at a time. The predictive branch may combine router
weight, recent mass and SPEX surprise `-p_i log(q_i)`; cross-entropy controls
probation width and promotion urgency, not quality by itself.
