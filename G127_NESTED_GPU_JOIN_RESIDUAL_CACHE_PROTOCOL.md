# G127 Nested GPU Join Residual Cache Protocol

## Purpose and mandatory order

G127 measures one transport lever: a residual-only host cache consumed by the
exact nested-residual GPU join path. It has two separate gates, in this order:

1. `g127_nested_gpu_join_residual_cache_safety.ps1` runs one structural safety
   request on the current build and writes a unique, immutable, hash-pinned
   G127 receipt.
2. `g127_nested_gpu_join_residual_cache_ab.ps1` validates that receipt against
   the current executable, build manifest, harness, bootstrap, model, sidecar,
   prompt, expected output and configuration before constructing or launching
   any of its six benchmark children.

G125 remains a hash-pinned historical prerequisite recorded by the G127
safety receipt. It does not replace the G127 current-build safety gate.

## Runtime summary

With the new cache enabled, the runtime must emit exactly one line:

```text
ds4: [nested-residual-residual-cache] result=summary enabled=%u hits=%llu misses=%llu evictions=%llu entries=%u capacity=%u pread_bytes=%llu pread_bytes_avoided=%llu h2d_bytes=%llu cached_join_calls=%llu invariant_failures=%llu
```

The harness switch `-NestedResidualGpuJoinResidualCache` exports
`DS4_NESTED_RESIDUAL_GPU_JOIN_RESIDUAL_CACHE=1` and requires both
`-NestedResidualGpuJoin` and `-NestedResidualGpuCache`.

## G127 structural safety

The safety runner uses:

- `-GateKind structural-safety`, `-Repeats 1`, no warmup;
- `-MaxTokens 64`, `-Context 256`, temperature `0`, think `false`;
- canonical cyberpunk prompt and hash-pinned expected output SHA;
- canonical model and nested sidecar with model/source/payload SHA checks;
- `-NestedResidualStructuralN1`;
- `-NestedResidualVerifyReconstruction`;
- `-NestedResidualGpuCache`;
- `-NestedResidualGpuJoin`;
- `-NestedResidualGpuJoinResidualCache`;
- full/open router, with no REAP/static/closed mask;
- `-DynamicArenaGiB 25.828125`, `-ExpertCacheN 320`, and
  `-NestedResidualCacheExperts 64`;
- machine-quiescence preflight and runtime contamination monitoring.

The safety is fail-closed unless all of these measured conditions hold:

- output SHA exactly matches the expected temp0 output;
- exact reconstruction verification is enabled and has positive calls/bytes;
- `enabled == 1`;
- `hits > 0` and `misses > 0`;
- `capacity > 0` and `entries <= capacity`;
- `pread_bytes_avoided > 0`;
- `cached_join_calls > 0`;
- `invariant_failures == 0`;
- reconstruction mismatches, nested failures, GPU-join failures, CPU
  reconstruction calls and native H2D bytes are all zero;
- selected-load fallback counter and fallback log markers are zero;
- quiescence preflight passes without being skipped and runtime contamination
  peak is zero.

The receipt schema is
`ds4_g127_nested_gpu_join_residual_cache_safety_v1`. It stores the result path
and SHA-256, configuration fingerprint, executable/build-manifest/input
fingerprint hashes, harness/bootstrap hashes, model/sidecar provenance,
G125 prerequisite and all safety counters. The unique receipt filename is not
overwritten. The runner prints both:

```text
G127_SAFETY_RECEIPT=<absolute path>
G127_SAFETY_RECEIPT_SHA256=<sha256>
```

This `n=1` run is structural evidence only: no SOTA, speed or general quality
claim is allowed.

## A/B receipt gate

The A/B runner requires both parameters:

```powershell
-G127SafetyReceipt <absolute receipt path>
-ExpectedG127SafetyReceiptSHA256 <64-hex SHA-256>
```

Before the six child plans are created, it validates the receipt and linked
result, including their hashes. The receipt must match the current executable,
build manifest and input fingerprint, current harness/bootstrap, safety
configuration fingerprint, canonical model/sidecar/prompt/output, G125
prerequisite, full/open routing, exactness, cache counters and quiescence.
The runner then keeps read locks on the receipt, linked result, executable,
build manifest, harness and bootstrap for the entire A/B. Each child also
passes the same G127 receipt and SHA to the harness. A G125-only receipt is
rejected when the residual cache is requested.

## Shared benchmark launch

Every child uses the G126 host and routing contract:

- `-GateKind benchmark`, `-Repeats 1`;
- `-MaxTokens 64`, `-Context 256`;
- exact expected output SHA;
- same model, prompt and nested sidecar;
- `-NestedResidualCacheExperts 64`;
- `-NestedResidualGpuCache` and `-NestedResidualGpuJoin`;
- hash-pinned G127 safety receipt;
- `-AllowNestedResidualBenchmarkSuite`;
- `-OuterNestedResidualBenchmarkProcessCount 3`;
- `-DynamicArenaGiB 25.828125`, `-ExpertCacheN 320`;
- full/open routing flags from G126.

The host accounting remains `30.0 GiB`: primary arena `25.828125 GiB`, nested
base `3.75 GiB`, exact cache `0.421875 GiB`.

The balanced order is:

1. control r1
2. candidate r1
3. candidate r2
4. control r2
5. control r3
6. candidate r3

Control uses GPU join with the residual cache off. Candidate adds
`DS4_NESTED_RESIDUAL_GPU_JOIN_RESIDUAL_CACHE=1`.

## Per-child and aggregate gates

Every child must preserve exact output, full/open routing, machine quiescence,
zero nested mismatch/failure, zero GPU-join mismatch/failure, zero CPU
reconstruction, zero native H2D and zero selected-load fallback.

For control, residual-cache requested/observed and every residual-cache counter
must remain zero.

For candidate:

- requested/observed are true and `enabled == 1`;
- `hits > 0`, `misses > 0`, `capacity > 0`;
- `entries <= capacity`;
- `pread_bytes_avoided > 0`, `cached_join_calls > 0`;
- `invariant_failures == 0`.

Across the three exact, uncontaminated rows per arm, candidate residual preads
and residual bytes must both be lower than control, and total avoided pread
bytes must be positive. Only then can G127 report its scoped transport A/B.

## Static-only validation for this task

Run only:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/test_g127_nested_gpu_join_residual_cache_static.ps1
git diff --check
```

The test parses the harness and both runners, verifies the G127 receipt
contracts, runs safety and A/B `WhatIf`, and never launches DS4 or uses the GPU.
