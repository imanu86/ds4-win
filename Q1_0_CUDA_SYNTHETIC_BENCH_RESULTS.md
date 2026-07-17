# Q1_0 CUDA synthetic benchmark

Status: structural and kernel-only measurement. This is not a DS4 throughput or
quality result.

Date: 2026-07-17

## Provenance

- DS4 base commit: `60f743de1104b1c8be6aadedde1f80d5470899dc`
- GPU: NVIDIA GeForce RTX 3060, SM 86
- CUDA: 12.6, nvcc 12.6.85
- source SHA-256:
  `48cf9208ef84002e759a900480603ada0dfc43aba468bd175e2d04debbecfc3d`
- executable SHA-256:
  `2052669412c7af7d70118201a77d5629ffcb668950c40dd04e42ddbc61306c69`

The benchmark is standalone. It does not open a DS4 model, start a server or
modify the production Q1_0 dispatch.

## Correctness gate

The test covers the Q1_0 `128 weights / 18 bytes` layout, `bit 1 = +d` polarity,
dequantization and the dot product of two Q1_0 blocks against one 256-value
Q8_K activation block. Each Q1_0 block reads `qs[0..15]`; only the Q8_K and
`bsums` indices move to the second half.

The old defective implementation read `x1->qs[16..31]`. The benchmark emulates
that exact byte-base bug from known post-block guard bytes and requires its
result to differ from the valid reference.

Command:

```powershell
.\build\Release\ds4_q1_0_bench.exe 1000 4096
```

Measured validation:

```json
{
  "checked_pairs": 512,
  "dot_max_abs": 0,
  "formula_vs_dequant_ref_max_abs": 0,
  "dequant_max_abs": 0,
  "guard_ok": true,
  "old_byte_base_bug_probe_min_abs": 0.04296875,
  "pass": true
}
```

Compute Sanitizer command:

```powershell
compute-sanitizer --tool memcheck --error-exitcode=99 `
  .\build\Release\ds4_q1_0_bench.exe 1 32
```

Result: `ERROR SUMMARY: 0 errors`, validation pass.

## Kernel-only timing

```json
{
  "iters": 1000,
  "pairs": 4096,
  "dot_kernel_ms": 0.009572,
  "dequant_kernel_ms": 0.020169,
  "dot_pairs_per_s": 427898997.533,
  "dequant_values_per_s": 51990745876.367
}
```

These numbers exclude model routing, sidecar reads, H2D transport, launch
composition and output generation. They support only the narrow conclusion
that the isolated Q1_0 arithmetic is small compared with the measured DS4
route transport cost. Runtime performance still requires a controlled A/B with
at least three independent clean processes.
