# G127P Heterogeneous Route Packed Copy Protocol

## Purpose

G127P is a protocol-only benchmark harness for the full/open G127 workload. It
does not change the runtime. It compares:

- control: G127 residual-cache path;
- candidate: the same G127 residual-cache path plus `-RoutePackedCopy`.

The candidate is meant to validate a heterogeneous route packed-copy runtime,
not the older closed/static G74 path.

## Fixed base

G127P inherits the G127 current-build contract:

- model `C:\ds4-models\ds4-2bit.gguf`;
- nested residual sidecar
  `C:\ds4-models\ds4-nested-residual-layers3-16-29-42.ds4nr`;
- full/open router;
- no REAP/static/closed mask;
- temp `0`, no-think;
- `MaxTokens=64`, `Context=256`;
- dynamic arena `25.828125 GiB`;
- expert cache `320`;
- nested residual cache `64`;
- nested residual GPU cache, GPU join, and residual-cache enabled;
- exact SHA, provenance, current build, quiescence and contamination gates.

Before G127P is run, the old/current-build G127 safety receipt must be
regenerated externally with `g127_nested_gpu_join_residual_cache_safety.ps1`
after the code/harness commit and a clean build. The G127P runner validates
that receipt and its SHA-256 before any child is planned.

The candidate structural safety then proves packed-copy exactness for the new
`-RoutePackedCopy` configuration. That structural safety must not receive
`-NestedResidualGpuJoinSafetyReceipt` or
`-ExpectedNestedResidualGpuJoinSafetyReceiptSHA256`, because the harness
forbids a receipt on verified structural safety. The benchmark children use
the current-build G127 receipt only to satisfy the nested GPU-join harness
requirement.

`-ReuseVerifiedModelReceipt` is restricted to candidate structural safety.
Benchmark children must not receive it: each benchmark performs the normal
model verification accepted by `GateKind=benchmark`. The G127 safety receipt
passed to benchmark children is a separate nested GPU-join prerequisite and
does not authorize model-receipt reuse.

## Mandatory execution order

The order is fixed and fail-closed. Candidate safety is executed and validated
immediately before any benchmark child is launched. Each benchmark child is
validated immediately after it finishes.

1. candidate safety n=1, `-RoutePackedCopy`;
2. control r1;
3. candidate r1;
4. candidate r2;
5. control r2;
6. control r3;
7. candidate r3.

The safety child is structural only. It has no SOTA, timing or quality verdict.

For a resumed batch, `-ResumeBatchTag` reuses and immediately validates an
existing candidate safety result. It must never rerun that safety. If the
expected safety result is absent, resume fails closed before any benchmark.
Existing benchmark results are likewise reused and validated; only missing
benchmark children are launched. The current recovery tag is
`g127p_clean_20260718T231000906Z_9648b4bc65`.

## Candidate route-packed gates

The candidate is fail-closed unless every measured child satisfies:

- `route_packed_copy_requested == true`;
- `route_packed_copy_observed == true`;
- `route_packed_copy_runtime_requested == 1`;
- `route_packed_copy_experts > 0`;
- `route_packed_copy_submissions == 2 * route_packed_copy_experts`;
- `route_packed_copy_bytes > 0`;
- `route_packed_copy_legacy_submissions == 0`;
- `gpu_resident_routes_miss_experts >= nested_residual_vram_misses`;
- `route_packed_copy_experts ==
  gpu_resident_routes_miss_experts - nested_residual_vram_misses`;
- nested GPU-join counters remain valid and independent from packed copy.

No hardcoded expert counts are allowed. Safety measures the counts; A/B only
checks invariants derived from those counters.

The packed experts are only the non-nested route misses that pass through the
route copy path. Nested residual GPU-join routes are expected to bypass packed
copy and keep their own counters valid. In the existing measured G127 shape,
the invariant is the form `11373 - 995 = 10378`, but G127P must derive the
numbers from counters, never from hardcoded values.

## Control gates

Control is fail-closed unless packed copy remains off:

- `route_packed_copy_requested == false`;
- `route_packed_copy_observed == false`;
- `route_packed_copy_runtime_requested == 0`;
- `route_packed_copy_experts == 0`;
- `route_packed_copy_submissions == 0`;
- `route_packed_copy_bytes == 0`;
- `route_packed_copy_legacy_submissions > 0`.

The legacy submission count must be positive so the control proves it exercised
the route-copy surface that the candidate intends to replace.

## Shared exactness and provenance gates

Every child must preserve:

- exact expected output SHA;
- current executable, build manifest, harness and bootstrap provenance;
- G127 safety receipt hash binding;
- full/open routing;
- zero nested residual mismatch/failure;
- zero nested residual VRAM failure;
- zero GPU-join mismatch/failure;
- zero CPU reconstruction;
- zero native H2D bytes;
- zero selected-load fallbacks;
- machine quiescence preflight ready, not skipped;
- runtime contamination consecutive peak zero.

Before benchmark launch, the aggregate records the build-manifest head and
dirty-at-build-start flag, executable SHA-256, build-manifest SHA-256 and input
fingerprint, harness SHA-256, bootstrap SHA-256, outer runner SHA-256, and G127
safety receipt SHA-256. Every child row records the SHA-256 of the exact result
JSON that was parsed. Child results are bound to the executable, manifest,
manifest fingerprint, build head/dirty state, harness, and, for benchmark
children, the validated G127 safety receipt.

After candidate safety validation and again after the final benchmark child,
the runner recomputes aggregate provenance. It fails closed if the outer
runner, harness, bootstrap, executable, build manifest/fingerprint, build
head/dirty state, G127 safety receipt, linked safety result, or safety
configuration changed since preflight. No aggregate JSON is emitted from a
mixed-provenance run.

## Verdict rule

G127P needs three exact, uncontaminated benchmark processes per arm. No verdict
is allowed from the safety run or from n=1. The G127 outlier rule is inherited:
if an arm has a max/min ratio above `1.20` on primary timing metrics after n=3,
the result must be marked as requiring extension rather than promoted as a
final performance claim.

The result is scoped to heterogeneous route packed-copy on G127 full/open. It
does not make a quality or long-context claim and does not alter the G73
closed/static historical result.

## Static-only validation for this task

Run only:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/test_g127p_hetero_route_packed_copy_static.ps1
git diff --check
```

This parses the new runner and checks the protocol markers. It does not launch
DS4, does not build and does not use the GPU.
