# IQ1_S Dynamic Tier Plan

## Objective

Integrate IQ1_S as the cold routed-expert representation while preserving the
existing 2-bit model as the authoritative warm representation.

The target data path is:

```text
SSD IQ1_S
  -> persistent IQ1_S cache in normal RAM
  -> cold-token execution with IQ1_S kernels
  -> deferred 2-bit load into the existing pinned arena
  -> 2-bit VRAM eligibility starting on the next token
```

This is a transport and residency policy, not a claim that IQ1_S is lossless.
The router, selected expert ids, and gate weights remain unchanged.

## Required Residency Contract

### SSD Cold Tier

- The IQ1_S sidecar is the compact source for cold routed experts.
- The main GGUF remains the source of the authoritative 2-bit representation.
- A sidecar-enabled run must validate sidecar identity and provenance before
  serving any routed expert.

### Normal-RAM IQ1_S Tier

- Add a persistent, pageable host cache dedicated to IQ1_S expert payloads.
- The cache owns IQ1_S data only. It must not reuse a 2-bit arena slot or claim
  2-bit residency.
- A cache entry is keyed by at least `(layer, expert, generation)` and has an
  explicit state such as `empty`, `loading`, `ready`, or `failed`.
- On an IQ1_S RAM hit, copy the compact payload through existing bounded pinned
  staging and upload it for the cold execution path.
- On a miss, read IQ1_S once from the sidecar, retain it in normal RAM, and use
  it for the current cold execution if the read succeeds.

### Cold IQ1_S Execution

- The current token may execute a cold selected expert with IQ1_S gate/up/down
  kernels.
- Layers 0-2 retain their sidecar `down` tensor in Q2_K; layers 3-42 use IQ1_S.
- Hot 2-bit VRAM hits and cold IQ1_S misses should be split into separate work
  lists. Execute hot work with the existing 2-bit path and cold work with the
  IQ1_S path, then perform one join/accumulation.
- Do not place a format branch inside every dot product when two compact work
  lists can preserve the existing specialized kernels.

### Deferred 2-bit Promotion

- Mass/LFRU policy observes the current route without changing the expert
  representation during that token.
- If an IQ1_S expert crosses the promotion threshold, enqueue a load of its
  authoritative 2-bit payload from the main GGUF into the existing pinned
  arena.
- Promotion must use the main-model 2-bit layer geometry and offsets, never the
  IQ1_S request geometry.
- Publish the new 2-bit binding atomically only after the full expert is loaded
  and validated.
- The promoted expert becomes eligible for the persistent 2-bit VRAM cache no
  earlier than the next token.

### VRAM Protected Tier

- Persistent VRAM expert slots contain 2-bit experts only in the first dynamic
  tier implementation.
- Existing mass/LFRU replacement and protection policy remains authoritative.
- IQ1_S may use transient compact device buffers for cold execution but must
  not masquerade as a 2-bit resident cache entry.

## Absolute Prohibition

```text
SSD cold -> VRAM 2-bit
```

is forbidden.

A cold expert cannot be fetched from SSD and published directly into the
persistent 2-bit VRAM cache. The only legal 2-bit promotion path is:

```text
main GGUF 2-bit -> existing pinned 2-bit arena -> validated publication
                 -> VRAM eligibility on the next token
```

The runtime must count attempted violations in
`forbidden_cold_ssd_to_vram`; the counter must remain zero. A nonzero value is
a failed run, not a warning.

## Existing Code Insertion Points

The symbol names are the stable references; line numbers may move as the
implementation evolves.

### Sidecar Binding and Route Source

- `ds4.c:iq1_s_sidecar_bind`: validate sidecar topology, routed tensors,
  formats, sizes, and checkpoint provenance.
- `ds4.c` routed MoE call sites near `routed_moe_launch`: select the validated
  source without allowing the sidecar to affect router output.
- `ds4_cuda.cu:ds4_gpu_set_iq1_s_sidecar`: install the duplicated sidecar file
  and mapped source used by CUDA loading code.

### Existing 2-bit Pinned Arena

- `ds4_cuda.cu:g_dynamic_arena`: retain as the only pinned host arena for
  authoritative 2-bit experts.
- Dynamic-arena layer descriptors and bindings: use these offsets and strides
  for deferred 2-bit promotion, even when the current request executes IQ1_S.
- `ds4_cuda.cu:cuda_moe_tiering_load_to_ram`: refactor into the promotion entry
  point that explicitly accepts main-model 2-bit geometry.

### Existing Tiering and VRAM Cache

- `ds4_cuda.cu:cuda_moe_tiering_state` and the mass/LFRU update path: add
  orthogonal IQ1_S RAM-cache state; do not overload `ram_slot`, which means a
  valid 2-bit pinned-arena binding.
- Existing persistent expert-cache structures near the tiering state: keep
  their payload contract 2-bit-only.
- Existing replacement decision and tiering-enforcement paths: enqueue 2-bit
  promotion after current-token routing, and publish only when ready.

### Selected Loading and Hit/Miss Split

- `ds4_cuda.cu:cuda_moe_selected_load`: fail closed for IQ1_S load failures;
  never fall back to main-file pointers with sidecar offsets.
- `ds4_cuda.cu:cuda_model_stream_span_into` and
  `cuda_moe_fill_span`: make source ownership explicit for every span.
- Existing selected-route hit/miss split near `routed_moe_launch`: extend it to
  produce a 2-bit hot list and IQ1_S cold list before the single output join.

## Phased Patch Sequence

### Phase 0: Harden the Current Sidecar Gate

1. Make every IQ1_S selected-load failure fatal for the request.
2. Reject `DS4_CUDA_MOE_NO_SELECTED_LOAD` when the sidecar is enabled.
3. Verify the observed sidecar SHA in the general harness, not only in a
   wrapper before launch.
4. Bind the expected sidecar fingerprint to the runtime configuration.
5. Mark structural `n=1` results as `sota_eligible=false` and
   `quality_eligible=false` in the primary result JSON.
6. Require exactly one coherent IQ1_S runtime summary and a minimal output
   health predicate.

Exit gate: environment-off is bit-exact with the G74 baseline, and the IQ1_S
structural safety run fails closed under injected I/O and provenance faults.

### Phase 1: Persistent IQ1_S Cache in Normal RAM

1. Add `cuda_iq1_host_cache` with source-aware keys, generations, byte
   accounting, and explicit entry states.
2. Retain compact IQ1_S expert payloads in pageable RAM after the first read.
3. Copy cache hits through bounded pinned staging for H2D.
4. Add deterministic capacity and eviction policy without touching the 2-bit
   pinned arena.
5. Support mixed Q2_K down tensors for layers 0-2.

Exit gate: repeated cold routes become RAM hits, sidecar SSD bytes fall as
expected, and output remains structurally valid.

### Phase 2: Deferred 2-bit Promotion

1. Add separate IQ1_S cache binding fields to tiering state.
2. Generate promotion candidates from measured mass/frequency policy.
3. Load candidates from the main GGUF into the existing pinned 2-bit arena.
4. Publish the 2-bit binding atomically after validation.
5. Enforce a token epoch: an expert promoted during token `T` cannot become a
   2-bit VRAM candidate before token `T+1`.

Exit gate: every promoted expert has an auditable IQ1_S-cold event followed by
a 2-bit pinned-ready event, with no direct cold-to-VRAM transition.

### Phase 3: Mixed 2-bit/IQ1_S Execution

1. Resolve selected experts into hot 2-bit and cold IQ1_S work lists.
2. Launch resident 2-bit hits without waiting for cold reads where dependency
   ordering permits it.
3. Execute cold experts with format-specific IQ1_S/Q2_K kernels.
4. Join exactly once and preserve router weights and selected ids.
5. Compare serial and split execution for exactness before making performance
   claims.

Exit gate: no per-expert format ambiguity, no duplicate expert contribution,
and one measured join.

### Phase 4: Predictive Prefetch

Only after Phases 0-3 pass:

1. Allow SPEX to prefetch IQ1_S into normal RAM.
2. Allow a separately gated prediction to schedule deferred 2-bit promotion.
3. Make every prediction cancellable and account for useful, late, canceled,
   and wasted work.
4. Never let prediction bypass the pinned 2-bit arena or current-token epoch.

## Telemetry

Emit machine-readable counters and timings at run and layer scope.

### Source and Cache

- `iq1_ssd_read_calls`, `iq1_ssd_read_bytes`, `iq1_ssd_read_ms`
- `iq1_ram_hits`, `iq1_ram_misses`, `iq1_ram_evictions`
- `iq1_ram_ready_bytes`, `iq1_ram_capacity_bytes`
- `iq1_selected_loads`, `iq1_selected_load_failures`
- `iq1_h2d_calls`, `iq1_h2d_bytes`, `iq1_h2d_ms`

### Current-Token Execution

- `hot_2bit_experts`, `cold_iq1_experts`
- `hot_2bit_kernel_ms`, `cold_iq1_kernel_ms`, `mixed_join_ms`
- `iq1_q2k_down_experts` for layers 0-2
- `duplicate_contribution_failures`

### Promotion

- `promotion_candidates`, `promotion_enqueued`, `promotion_completed`
- `promotion_failed`, `promotion_canceled`
- `promotion_2bit_ssd_bytes`, `promotion_2bit_load_ms`
- `promotion_ready_token`, `promotion_first_vram_eligible_token`
- `forbidden_cold_ssd_to_vram`

### Residency

- counts and bytes for `SSD_IQ1_COLD`, `RAM_IQ1_READY`,
  `RAM_2BIT_PINNED`, and `VRAM_2BIT_PROTECTED`
- transitions between every pair of states
- generation mismatches and stale-binding rejections

### Provenance and Eligibility

- observed SHA-256 for main model and sidecar
- source URL, quantization layout, and imatrix provenance
- code revision, source-tree digest, build digest, command, and environment
- `gate_kind`, `quality_eligible`, `sota_eligible`, and contamination reason

## Fail-Closed Invariants

1. Sidecar disabled preserves the G74 path bit-for-bit.
2. IQ1_S selected-load failure never falls back through a main-model pointer
   using sidecar offsets.
3. The sidecar cannot serve MTP, attention, embeddings, shared experts, router,
   or output tensors.
4. Sidecar and primary model must have validated checkpoint identity, not only
   compatible tensor shapes.
5. `ram_slot` means a validated 2-bit pinned-arena binding only.
6. IQ1_S cache state is orthogonal to 2-bit pinned and VRAM residency.
7. The persistent VRAM expert cache contains 2-bit experts only.
8. A promotion cannot alter the representation used by the current token.
9. An expert promoted during token `T` is VRAM-eligible no earlier than `T+1`.
10. `forbidden_cold_ssd_to_vram` is always zero.
11. No partial expert is published after failed, canceled, or stale I/O.
12. Layer 0-2 down tensors use the validated Q2_K sidecar layout.
13. Router ids and gate weights are unchanged by storage tier.
14. All telemetry totals reconcile; inconsistency invalidates the run.

## Test Matrix

### Static and Unit Tests

- GGUF and concatenated-shard parser tests.
- Exact IQ1_S and Q2_K expert-size/stride tests.
- Main/sidecar checkpoint mismatch rejection.
- Source-aware span tests that inject wrong file, offset, and generation.
- IQ1_S RAM-cache hit, miss, eviction, duplicate-load, and stale-generation
  tests.
- Promotion epoch test proving `T -> T+1` eligibility.
- Direct `SSD cold -> VRAM 2-bit` rejection test.
- Counter reconciliation and single-summary parser tests.

### Environment-Off Regression

- Run the clean G74 configuration with the sidecar environment disabled.
- Require the established greedy output hash.
- Require no IQ1_S file open, route call, allocation, cache event, or telemetry
  event.
- Timing comparisons require a quiescent machine and the existing clean-run
  protocol.

### IQ1_S Structural Safety

- First run is `n=1`, `temp=0`, `nothink` and is structural only.
- Require observed model/sidecar hashes, one runtime summary, finite output,
  nonempty coherent text, route calls and slots greater than zero, selected
  loads consistent with route calls, and zero failures.
- Mark `quality_eligible=false` and `sota_eligible=false` in the primary result.
- Inject missing file, wrong SHA, truncated read, OOM, canceled load, and stale
  cache generation; each must fail closed.

### Cache and Promotion A/B

- A: IQ1_S direct selected-load without persistent normal-RAM cache.
- B: persistent IQ1_S normal-RAM cache.
- C: B plus deferred 2-bit promotion.
- D: C plus mixed split execution.
- Record SSD bytes, RAM hits, H2D bytes, promotion latency, VRAM transitions,
  TTFT, prefill, and decode throughput.
- Warm/cold state and contamination status must be explicit for every run.

### Quality Gate

- Compare unchanged 2-bit baseline against each eligible IQ1_S tier variant.
- Use the same prompt set, settings, and run order policy.
- Require at least `n>=3` per arm and human/registered L0-L3 grading.
- Preserve raw output and logs for every replicate.
- Never infer quality from output hash, repeat flags, routing coverage, or
  `n=1` safety.
- Do not claim lossless behavior unless a later protocol directly establishes
  it over the declared evaluation surface.

## Initial Success Criteria

The first dynamic tier is ready for broader optimization only when:

- environment-off remains exact with G74;
- the IQ1_S sidecar safety gate passes and all injected failures fail closed;
- repeated cold experts hit persistent normal RAM instead of SSD;
- promotion uses the existing 2-bit pinned arena and activates no earlier than
  the next token;
- persistent VRAM entries are demonstrably 2-bit only;
- `forbidden_cold_ssd_to_vram=0`;
- all residency and transport counters reconcile;
- an `n>=3` L0-L3 quality A/B is complete before any quality claim;
- clean performance measurements are recorded separately from safety runs.
