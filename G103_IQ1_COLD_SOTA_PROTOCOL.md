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
- `Iq1SRamCacheGiB 1`

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
- suite receipt reuse

## Execution Plan

1. Run candidate safety `n=1` with `GateKind structural-safety`.
2. Run 3 independent processes per arm, interleaved:
   control 1, candidate 1, control 2, candidate 2, control 3, candidate 3.
3. If either arm has a max/min outlier ratio greater than `20%` on primary
   timing metrics after `n=3`, run 3 additional independent processes per arm,
   still interleaved.

Safety `n=1` is structural only and can never support a quality or SOTA claim.

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
