# G128 All-Layer Nested Storage Protocol

## Scope

G128 is the all-layer exact nested-residual storage contract for DS4 routed MoE
layers `3..42`. The authority for this document is the current runtime
implementation in `ds4_cuda.cu` and the current harness contract in
`g7_measure.ps1`.

G128 is not a sparse-mask experiment and not a performance claim. The router is full/open throughout:

- all routed layers keep all 256 experts admissible;
- selected experts are the router-selected experts;
- no REAP mask, no static mask, no closed candidate set, no baked mask, SPEX
  substitution or route pruning is active;
- storage class may change, expert admissibility may not;
- every covered selected route must reconstruct the authoritative native expert
  bytes exactly or fail closed.

The routing contract recorded by the runner/receipt is:

```text
full/open routing preserved; no REAP/static/closed masks
```

## Sidecar Contract

`DS4_NESTED_RESIDUAL_SIDECAR` points to the real nested-residual sidecar. For
G128 all-layer storage, coverage must be exactly:

```text
all_layer_first=3
all_layer_last=42
all_layer_count=40
```

Measured all-layer sidecar geometry for layers `3..42`:

```text
records=120
payload_bytes=32,212,254,720
file_bytes=32,212,267,792
```

The runtime enforces this when either pageable base or pageable residual cache
is requested. Any missing, duplicated or out-of-range routed layer is fatal
before a run can make a claim.

For every `(layer, expert)` in layers `3..42`, the sidecar must provide the
three routed expert parts used by DS4:

- gate;
- up;
- down.

The nested base is the exact high-bit component split from the authoritative
IQ2_XXS/Q2_K tensors; it is not the lossy standard Q1_0 quantizer. Combining
that base with the sidecar residual reconstructs the original native bytes.

For each part the sidecar must bind exact source offsets, native bytes, nested
base bytes and exact residual bytes. The harness also pins provenance with:

- `ExpectedNestedResidualSidecarSHA256`;
- `ExpectedNestedResidualSourceSHA256`;
- `ExpectedNestedResidualPayloadSHA256`.

`ExpectedNestedResidualSourceSHA256` must equal the verified primary model
SHA-256. The sidecar is isolated from `Q1_0`, `IQ1_S`, REAP masks and SPEX.

## Required Harness Switches

The current `g7_measure.ps1` knobs for G128 are:

```powershell
-NestedResidualSidecar <path>
-ExpectedNestedResidualSidecarSHA256 <sha256>
-ExpectedNestedResidualSourceSHA256 <sha256>
-ExpectedNestedResidualPayloadSHA256 <sha256>
-NestedResidualVerifyReconstruction
-NestedResidualPageableBase
-NestedResidualBasePinnedGiB <0..30>
-NestedResidualCachePageable
-NestedResidualCacheExperts <40..4096>
-NestedResidualGpuCache
-NestedResidualGpuJoin
-NestedResidualGpuJoinResidualCache
-GpuResidentRoutes
-SplitFused
-ForceOpenRouter
```

For the first safety gate, the run also uses:

```powershell
-GateKind structural-safety
-Repeats 1
-NestedResidualStructuralN1
```

For later benchmark members, `-GateKind benchmark` is allowed only through an
explicit outer benchmark suite with `-AllowNestedResidualBenchmarkSuite` and
`-OuterNestedResidualBenchmarkProcessCount >= 3`. Without runtime reconstruction
verification, benchmark members must consume a hash-pinned safety receipt.

## Runtime Environment

The harness maps the switches above to these runtime environment variables:

```text
DS4_NESTED_RESIDUAL_SIDECAR=<path>
DS4_NESTED_RESIDUAL_EXACT=1
DS4_NESTED_RESIDUAL_EXPECTED_SOURCE_SHA256=<sha256>
DS4_NESTED_RESIDUAL_EXPECTED_PAYLOAD_SHA256=<sha256>
DS4_NESTED_RESIDUAL_VERIFY_RECONSTRUCTION=1
DS4_NESTED_RESIDUAL_PROFILE=1                  # optional
DS4_NESTED_RESIDUAL_CACHE_EXPERTS=<1..4096>
DS4_NESTED_RESIDUAL_PAGEABLE_BASE=1
DS4_NESTED_RESIDUAL_BASE_PINNED_GIB=<0..30>
DS4_NESTED_RESIDUAL_CACHE_PAGEABLE=1
DS4_NESTED_RESIDUAL_GPU_CACHE=1
DS4_NESTED_RESIDUAL_GPU_JOIN=1
DS4_NESTED_RESIDUAL_GPU_JOIN_RESIDUAL_CACHE=1
```

`DS4_CUDA_PREFILL_TIER_ROUTER` is forced to `open`.

`DS4_NESTED_RESIDUAL_CACHE_EXPERTS` accepts values up to `64` for pinned cache.
For G128, values above `64` are valid only when
`DS4_NESTED_RESIDUAL_CACHE_PAGEABLE=1`; the absolute harness/runtime cap is
`4096`.

## Storage Contract

G128 has two independent host storage classes:

- nested base storage;
- exact residual-cache storage.

Nested base storage is split between pinned host memory and pageable host
memory:

- `DS4_NESTED_RESIDUAL_PAGEABLE_BASE=1` enables pageable overflow;
- `DS4_NESTED_RESIDUAL_BASE_PINNED_GIB` is the pinned host budget and must be
  provided when pageable base is enabled;
- the effective accepted range is greater than zero through `30` GiB;
- entries that fit the budget are assigned to pinned storage;
- the remaining base entries stay resident in pageable host memory;
- every base entry is addressable through the `(layer, expert)` map and records
  whether it is pinned or pageable.

Exact residual-cache storage is pageable in G128:

- `DS4_NESTED_RESIDUAL_CACHE_PAGEABLE=1` requires
  `DS4_NESTED_RESIDUAL_GPU_JOIN_RESIDUAL_CACHE=1`;
- the cache stores exact residual bytes, not base bytes;
- misses may read the residual from the sidecar file through the exact residual
  path and are counted separately;
- cache entries are not allowed to change router choice or output bytes.

Pageable here means host-resident pageable storage. It is not device-mapped
zero-copy and not a hidden SSD lane for base bytes.

For DS4 layers `3..42`, the exact nested geometry is `37.5 GiB` of resident
base storage. Each residual-cache slot is `3 MiB`. The canonical first G128
candidate uses:

```text
dynamic arena                 2.0 GiB pinned
nested base pinned           28.0 GiB pinned
nested base pageable          9.5 GiB pageable
residual cache 320 slots      0.9375 GiB pageable
candidate host allocation    40.4375 GiB
```

The dynamic arena plus nested pinned-base budget must not exceed `30 GiB`.
The harness preflight requires the complete expected host allocation plus a
`4 GiB` safety margin before launch. The A/B control keeps the contemporary
full/open native path at a `30 GiB` dynamic arena; it does not enable any
nested-residual switch.

The expected output path for the measured all-layer sidecar is
`D:\ds4-models\ds4-nested-residual-layers3-42.ds4nr` because `C:` has
insufficient free space. `D:`/SATA is allowed only for structural safety; it
must not support throughput, TTFT, t/s or SOTA claims.

## Cache Partition

When pageable residual cache and all-layer storage are both enabled, the runtime
partitions residual-cache slots by routed layer.

The runtime requires at least one residual-cache slot per ready routed layer:

```text
NestedResidualCacheExperts >= 40
```

For layers `3..42`, slots are distributed by quotient/remainder:

- `cache_layer_partitioned=1`;
- each ready layer receives `floor(capacity / 40)` or `ceil(capacity / 40)`
  slots;
- `layer_slots_max` must be at most `layer_slots_min + 1`;
- LRU lookup, victim selection and cached-slot validation scan only the owning
  layer partition;
- a cached expert found outside its layer partition is an invariant failure.

Example: `NestedResidualCacheExperts=320` gives 8 residual-cache slots per
routed layer.

## Exact GPU Join Path

For every selected route on a covered layer:

1. The runtime resolves the selected expert's nested base entry from pinned or
   pageable host storage.
2. The runtime resolves the exact residual bytes from the pageable residual
   cache or, on miss, from the sidecar residual source.
3. Base and residual are copied to the GPU join scratch buffers.
4. The GPU reconstructs the authoritative native expert bytes.
5. With `DS4_NESTED_RESIDUAL_VERIFY_RECONSTRUCTION=1`, the reconstructed bytes
   are copied back to verify exactness.
6. Any mismatch, missing source range, invalid storage map, CPU reconstruction,
   native H2D shortcut or fallback outside this path fails closed.

G128 must not use a base-only approximation. The later physical-rotation work
can build on this, but G128 itself is exact.

## Runtime Telemetry

The runtime summary names currently emitted by `ds4_cuda.cu` are:

```text
ds4: [nested-residual] bootstrap-ready ...
ds4: [nested-residual] result=summary ...
ds4: [nested-residual-base-storage] result=summary ...
ds4: [nested-residual-cache-pageable] result=summary ...
ds4: [nested-residual-vram] result=summary ...
ds4: [nested-residual-gpu-join] result=summary ...
ds4: [nested-residual-residual-cache] result=summary ...
ds4: [nested-residual-profile] result=summary ...       # optional
```

`[nested-residual] bootstrap-ready` must expose:

```text
base_bytes
base_pinned_bytes
base_pageable_bytes
base_pinned_entries
base_pageable_entries
cache_entries
cache_bytes
cache_pageable
cache_layer_partitioned
all_layer
all_layer_first
all_layer_last
all_layer_count
router=open
exact=1
```

`[nested-residual-base-storage]` must expose:

```text
pinned_entries
pinned_bytes
pinned_hits
pinned_h2d_bytes
pageable_entries
pageable_bytes
pageable_hits
pageable_h2d_bytes
invariant_failures
mapped=0
router=open
exact=1
```

`[nested-residual-cache-pageable]` must expose:

```text
pinned_entries
pinned_bytes
pinned_hits
pinned_h2d_bytes
pageable_entries
pageable_bytes
pageable_hits
pageable_h2d_bytes
cached_join_calls
partitioned
layer_slots_min
layer_slots_max
invariant_failures
```

The harness persists the corresponding JSON result fields, including:

```text
nested_residual_pageable_base_requested
nested_residual_base_pinned_gib_requested
nested_residual_cache_pageable_requested
nested_residual_all_layer_first_layer
nested_residual_all_layer_last_layer
nested_residual_all_layer_count
nested_residual_base_pinned_entries
nested_residual_base_pinned_bytes
nested_residual_base_pinned_hits
nested_residual_base_pinned_h2d_bytes
nested_residual_base_pageable_entries
nested_residual_base_pageable_bytes
nested_residual_base_pageable_hits
nested_residual_base_pageable_h2d_bytes
nested_residual_storage_invariant_failures
nested_residual_cache_pinned_entries
nested_residual_cache_pinned_bytes
nested_residual_cache_pinned_hits
nested_residual_cache_pinned_h2d_bytes
nested_residual_cache_pageable_entries
nested_residual_cache_pageable_bytes
nested_residual_cache_pageable_hits
nested_residual_cache_pageable_h2d_bytes
nested_residual_cache_pageable_cached_join_calls
nested_residual_cache_layer_partitioned
nested_residual_cache_layer_slots_min
nested_residual_cache_layer_slots_max
nested_residual_cache_pageable_invariant_failures
```

Telemetry appearing while the matching request switch is disabled is a harness
failure. A G128 request missing the storage summaries is also a failure.

## Safety Gate

A structural `n=1` safety run is mandatory before any `n>=3` benchmark. The
first executable gate is structural safety, not a benchmark:

- `GateKind=structural-safety`;
- `Repeats=1`;
- no warmup;
- `NestedResidualStructuralN1`;
- exact reconstruction verification enabled.

The safety result must prove:

- the sidecar path, byte count and SHA-256 match the pinned provenance;
- source and payload SHA-256 match the expected provenance;
- full/open router and no mask/pruning isolation;
- all-layer sidecar coverage is exactly `3..42` and count `40`;
- pageable base and pageable residual cache were requested and observed;
- base pinned and base pageable counters are nonzero when budget produces both
  classes;
- residual cache is pageable, partitioned and has nonzero layer slots;
- `layer_slots_max <= layer_slots_min + 1`;
- GPU join was requested and observed;
- verify calls and verify bytes are positive;
- reconstruction mismatches are zero;
- native H2D bytes are zero;
- CPU reconstruction calls are zero;
- nested, VRAM, GPU-join, base-storage and cache-pageable invariant failures
  are zero;
- output SHA matches the expected temp0/nothink safety output;
- process isolation, disk contamination, model provenance and build provenance
  gates pass.

No SOTA, TTFT, t/s or quality verdict may be taken from this `n=1` structural
safety result.

## Benchmark And Quality Gate

Only after a passing hash-pinned safety receipt may G128 enter benchmark or
quality evaluation.

Benchmark requirements:

- explicit outer benchmark suite;
- at least `n>=3` independent child runs;
- same model, prompt, build, harness and sidecar provenance across children;
- contamination and quiescence gates pass;
- receipt and result SHA values are recorded;
- exactness gates remain enabled or are justified by a matching safety receipt.

Quality requirements:

- `n>=3`;
- L0-L3 grading;
- no verdict from `n=1`, `repeat_flag` or a single malformed run;
- negative results are recorded honestly.

Performance claims must remain descriptive until the exact protocol and
quality gates both pass.

## Fail-Closed Conditions

The runtime or harness must abort before any performance/quality claim when:

- G128 env gates are partially provided;
- `NestedResidualSidecar` is missing;
- any expected SHA-256 is absent or mismatched;
- expected nested source SHA-256 differs from the verified primary model SHA;
- Q1_0, IQ1_S, REAP masks or SPEX are combined with G128;
- `NestedResidualPageableBase` is set without `NestedResidualGpuCache` and
  `NestedResidualGpuJoin`;
- `NestedResidualBasePinnedGiB` is absent while pageable base is enabled;
- `NestedResidualBasePinnedGiB` is outside `0..30`;
- all-layer storage is requested without both pageable base and pageable
  residual cache;
- `NestedResidualCacheExperts < 40` for G128 all-layer storage;
- `NestedResidualCacheExperts > 64` without pageable residual cache;
- `NestedResidualCacheExperts > 4096`;
- `NestedResidualCachePageable` is set without
  `NestedResidualGpuJoinResidualCache`;
- sidecar coverage is not exactly layers `3..42`;
- residual cache partitioning is absent or invalid;
- any selected route falls back to an unverified whole-tensor/native path;
- reconstruction verification is disabled for safety;
- any mismatch, native H2D, CPU reconstruction or invariant failure is observed;
- telemetry summaries are missing, duplicated, conflated or emitted while the
  matching feature is disabled.

## Current Static Checks

The document is intentionally tied to current code symbols and harness fields.
The static checks for this protocol are expected to inspect, without launching
DS4 or using the GPU:

- runtime env names in `ds4_cuda.cu`;
- bootstrap and summary telemetry names;
- all-layer coverage fields;
- pageable base and pageable residual cache counters;
- cache partition fields;
- harness switches and result JSON fields;
- safety-before-benchmark gate semantics.

This protocol file does not create a benchmark, does not allocate GPU memory,
does not generate a sidecar and does not claim a speedup.
