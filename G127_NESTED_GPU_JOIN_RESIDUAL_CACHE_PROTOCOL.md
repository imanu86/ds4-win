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

## Result

G127 completed the balanced six-process sequence with three independent
processes per arm. All six accepted outputs were exact and uncontaminated,
with machine-quiescence preflight failures `0` and runtime contamination peak
`0` on every row.

The admitted G127 safety receipt is:

`C:\Users\imanu\Documents\Codex\2026-07-07\cia\work\ds4-win-publish-g126-20260718-v2\g7_runs\g7_g127_clean_safety_v2_20260718T221247584Z_10b3d546a4_receipt.json`

SHA-256:

`906dbf4cec4e2e53a49de3568aabd19346da6809bef0eba68cc9eb3166e704b0`

The linked safety result SHA-256 is
`85c9ecb678e9ecb0bcfa9b0ce1ec87136d03d67029134aa2bda492029c372a37`.
The receipt binds exact content SHA
`fd6c4522975a71e252b90199d49cfe3236310e2a7285dc0fc4d0e9d0e4885510`,
prompt SHA
`38f6ec5ee5403f59dd2418eb5d9a5a94a0f0da19df015060383bb1ae46003bb6`,
configuration SHA
`99b58845fa0aae49f3e29774c7834bcb50a48fc8ddafd795442989f3cfb9af23`,
model SHA
`efc7ed607ff27076e3e501fc3fefefa33c0ed8cf1eff483a2b7fdc0c2e616668`,
sidecar SHA
`07199bc5503aa6e2dea10f702c1ca9e8f05a5bf466a56cbed031f6a5fca4bdf9`,
sidecar payload SHA
`02c8cb248a8184e365e2e486653484165db39402fd28320ba621fb4fdb3f7bd8`,
executable SHA
`d610f60eb6e6322ff444a49d0b2a4ae45e45ac9a5ac60688acc537f05621155c`,
build manifest SHA
`277f948355d9758aee09fa84b34ec5ce3679c8308849bbf4326bc3e84d95ac6a`,
build input fingerprint SHA
`3387d4a2d987b6a1a9423ab99fa55d5323f585a788d94d546bd4a5f211ecf268`,
build head `84d2b66eb30cdaec0df75daf179249b08dcc1d94`, harness SHA
`8265416a6b0897c45cfc2c403a848e92c0335976a64330a9eb4066148fd445c1`,
and bootstrap SHA
`1f0da3473ad707c605d32dd55da454f9ebf74456ed479204a2763668f203fee0`.
Safety exactness counters were reconstruction verify `true`, verify calls
`3783`, verify bytes `8925216768`, verify mismatches `0`, nested mismatches
`0`, nested failures `0`, GPU-join failures `0`, CPU reconstruct calls `0`,
native H2D bytes `0`, selected-load fallbacks `0`, and fallback markers `0`.
Safety quiescence was ready-to-launch `true`, skipped `false`, preflight
failures `0`, and runtime contamination consecutive peak `0`.

The first G127 safety attempt
`g7_g127_clean_safety_20260718T220600228Z_87825500c7` is deliberately not an
admitted safety receipt. It produced only preflight, raw-output, telemetry and
stderr artifacts, with `raw_outputs.complete=false` and no `_receipt.json`.
That attempt failed closed at the accounting/protocol layer and carries no
performance, quality, SOTA or A/B claim, even though its raw runtime log is
retained for provenance.

| Pos | Arm | Repeat | Exact | Clean | E2E t/s | Decode t/s | TTFT s | Residual preads | Residual bytes | Cache hits | Cache misses | Pread bytes avoided |
|---:|---|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | control | 1 | true | true | `0.643550` | `1.58` | `58.677` | `1261` | `3966763008` | `0` | `0` | `0` |
| 2 | candidate | 1 | true | true | `0.655797` | `1.59` | `56.863` | `869` | `2733637632` | `392` | `869` | `1233125376` |
| 3 | candidate | 2 | true | true | `0.654041` | `1.58` | `56.876` | `869` | `2733637632` | `392` | `869` | `1233125376` |
| 4 | control | 2 | true | true | `0.629410` | `1.57` | `60.557` | `1261` | `3966763008` | `0` | `0` | `0` |
| 5 | control | 3 | true | true | `0.636016` | `1.57` | `59.496` | `1261` | `3966763008` | `0` | `0` | `0` |
| 6 | candidate | 3 | true | true | `0.645700` | `1.59` | `58.501` | `869` | `2733637632` | `392` | `869` | `1233125376` |

| Metric | Control mean | Candidate mean | Delta |
|---|---:|---:|---:|
| E2E tokens/s | `0.6363253333333333` | `0.651846` | `+2.439108715877003%` |
| Server decode tokens/s | `1.5733333333333335` | `1.5866666666666667` | `+0.8474576271186418%` |
| TTFT seconds | `59.576666666666675` | `57.413333333333334` | `-2.163333333333341` |

Transport moved in the intended direction and was stable across all three
candidate rows: residual preads were `1261` per control row versus `869` per
candidate row, and candidate avoided `1233125376` residual pread bytes on each
row. Aggregated residual preads fell from `3783` to `2607`; residual bytes
fell from `11900289024` to `8200912896`; total candidate pread bytes avoided
were `3699376128`.

The scoped verdict is therefore honest but narrow: pread avoidance is stable
and exact under the recorded provenance/quiescence gates, while server decode
improved only `+0.847%`. G127 is not SOTA, is not a general latency or quality
claim, and does not replace longer L0-L3 grading.

Authoritative aggregate:

`C:\Users\imanu\Documents\Codex\2026-07-07\cia\work\ds4-win-publish-g126-20260718-v2\g7_runs\g7_g127_clean_ab_20260718T221539174Z_6088859efa_result.json`

SHA-256:

`b580aba04d5b138c786b634570b06544f1ec2387e1380afad79d38f9ab8c8902`

## Static-only validation for this task

Run only:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/test_g127_nested_gpu_join_residual_cache_static.ps1
git diff --check
```

The test parses the harness and both runners, verifies the G127 receipt
contracts, runs safety and A/B `WhatIf`, and never launches DS4 or uses the GPU.
