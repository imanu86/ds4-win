# G129: full/open Q1_0 base with dynamic exact-IQ2 promotion

## Objective

Combine the measured Q1_0 transport ceiling with the request-scoped dynamic
residency policy from G73, without a closed expert mask. The router must remain
full/open for every token. Q1_0 is the complete resident fallback; exact IQ2 is
the promoted representation for experts whose observed demand justifies it.

G129 is successful only if a clean long-form campaign reaches at least L2 and
more than 6.0 server decode tokens/s with `n >= 3`. An `n=1` run is structural
safety evidence only.

## Storage contract

The two host arenas have different ownership and must never alias:

1. `g_q1_0_dynamic_arena` owns all 11,008 Q1_0 routed experts. Its slots are
   immutable after publication. A bounded prefix is page-locked and the
   remainder is pageable overflow.
2. `g_dynamic_arena` owns exact IQ2 probation/warm entries only. It is smaller,
   page-locked, and has a pre-reserved open-router replacement pool.
3. The device expert cache owns exact IQ2 VRAM entries. It is seeded from full
   prefill mass and subsequently rotates by mass-LFRU.
4. The primary IQ2 model file remains authoritative storage. It may feed the
   exact-IQ2 probation arena after an admission decision, but never feeds VRAM
   directly for a Q1_0 fallback route in the same token.
5. On Windows, once each Q1_0 sidecar layer has been copied into its final
   pinned/pageable destination and checksummed, the sidecar mmap source range is
   page-aligned and passed through the same `VirtualUnlock` hint semantics used
   by the WRAP source path. `ERROR_NOT_LOCKED` is reported as telemetry, not as
   an exactness failure; the destination arena and provenance are unchanged.
   A `success=0/not_locked=N` outcome only proves that the page-aligned hint was
   attempted against ranges that were not locked by this process. It does not
   prove that Windows reclaimed file-backed source pages or that the bootstrap
   memory peak has been reduced; replacing the mmap copy with chunked `pread`
   is a separate patch set if the next safety still shows pressure.

Initial host-memory budget for the RTX 3060 / 64 GiB machine:

- exact IQ2 primary arena: 5.5 GiB, enough for all 768 experts in the first
  three hash-routed layers plus the open-router reserve;
- complete Q1_0 arena: 24.5 GiB pinned plus pageable overflow;
- total requested page-locked arena memory: 30.0 GiB;
- exact IQ2 open-router reserve: 64 expert slots;
- exact IQ2 VRAM cache: 320 expert slots;
- mass-LFRU tier replacement budget: 32 entries per policy epoch.

The runner must record chosen, capped, pageable, and total bytes. Allocation is
fail-closed when the complete Q1_0 base or the separate exact probation pool is
not present.

## Route and promotion contract

For each selected route:

1. Use exact IQ2 directly when the expert is already protected in VRAM.
2. Use exact IQ2 from snapshot/probation RAM when present; the route worker may
   promote it to VRAM according to mass-LFRU.
3. Otherwise use resident Q1_0 for the current token.
4. Account Q1_0 demand exactly once using router weight, frequency, and recency.
5. After the current Q1_0 work is queued, apply the admission gate to the
   already-observed expert. If admitted, stage exact IQ2 into RAM probation.
6. Set `vram_eligible_after_call = call_tick + 1`; direct SSD-to-VRAM promotion
   in the current token is forbidden.

Every effective Q1_0 dynamic promotion load attempt must also emit a structured
per-expert record, followed by exactly one terminal success or failure record.
This structured per-expert artifact is O(promotions), not O(routes).
Normal policy rejects such as touches, weight, mass, request/window budget,
existing exact-IQ2 residency, and RAM admit skip remain aggregate counters only;
they must not flood stderr or the JSONL artifact. Exceptional structural rejects
such as `request_epoch_missing`, `reason=call_tick_overflow`, source/range
overflow, RAM admission allocation failure, destination offset overflow, or
provenance-destination mismatch emit exactly one bounded fail-closed reject
record before returning. `request_epoch` is the authoritative request-boundary telemetry
counter, incremented once at request begin before carry/dynamic-arena early
returns; it is not the carry-specific `g_dynamic_arena.request_sequence` and is
not the promotion window. `promotion_window_epoch` is recorded separately.
`call_tick` advancement is saturating and fail-closed: at `UINT64_MAX` the
tick must not wrap, no promotion attempt/load may start, and Q1_0 dynamic
promotion records must use `reason=call_tick_overflow`.
Attempt and success records must carry request epoch, record id, layer/expert,
observation/current call, first eligible call strictly greater than the
observation call, touch count, weight/mass, admission gate values, resident Q1_0
sidecar provenance, exact IQ2 destination base/stride/effective
offset/bytes/provenance, Q1_0 source base/stride/effective offset/bytes, and
explicit no-same-call/no-current-token-direct-SSD flags. The harness
materializes these rows as a strict JSONL artifact with exactly one canonical
object per physical line and records its path, SHA-256, count, and physical-line
count in the result and safety receipt. Existing JSONL is never trusted by
presence alone: failure paths must validate it with the same strict schema,
canonical roundtrip, pairing, budget, offset, and provenance checks, or
regenerate it from canonical stderr markers and report why. The physical-line
count is part of the receipt contract. Aggregate attempts, successes, rejects,
and failures must match the artifact exactly; request and
`request_epoch + promotion_window_epoch` budget counters must be unique,
monotonic, and within the configured budgets. Attempts are emitted only after
RAM slot/victim admission succeeds and immediately before the first `pread`;
each attempt must have exactly one terminal success or failure matched by
`request_epoch + record_id` and the full immutable identity, including
layer/expert/calls, touch/weight/mass, gate values, source/destination
base/stride/effective offsets, bytes, SHA-256, and file sizes. Record volume is
bounded by `attempts + successes + failures + structural_rejects`, with
`successes + failures == attempts` and `structural_rejects <= 16`; the enforced
upper bound is therefore `2 * attempts + 16`, and failure terminals are not
counted twice. The safety
runner must canonicalize promotion artifact paths and require containment under
`g7_runs` using a directory-separator-bounded comparison; sibling paths such as
`g7_runs_evil` and traversal/reparse escapes are fail-closed.

The mixed Q1_0/exact-IQ2 resolver and its telemetry are mandatory for the
full/open G129 control and promotion arms. Disabling dynamic promotion disables
only mutation of the exact-IQ2 probation arena; it must not disable tier-entry
construction, exact-IQ2 VRAM/cache resolution, route-entry accounting, or the
Q1_0 fallback decision. The mixed summary must expose `router_mode=open|closed`
as the authoritative router eligibility mode and may keep the legacy
`router=unchanged` transition/state label only as diagnostic telemetry. The
`router_mode` value is captured request-scoped when the mixed resolver is
actually invoked with enforce mode, prefill-mass tiering, open router, and no
snapshot backing; it is reported before that capture is reset. G129 validates
`router_mode=open`; it must not accept `router=unchanged` as proof of full/open
routing.

For G129 full/open Q1_0 resident plus dual-arena mixed, SplitFused accounting
is the primary-model exact-IQ2 transport denominator, not the full router
denominator. The harness must prove `tier_route_entries == trace_rows`,
`trace_rows == q1_resident + iq2_vram + iq2_snapshot_ram + iq2_tier_ram`, and
`split_fused_hits + split_fused_misses == iq2_vram + iq2_snapshot_ram +
iq2_tier_ram`. The Q1_0 resident routes are excluded from SplitFused only after
the mixed route trace proves them separately. Non-Q1/mixed configurations keep
the legacy `6 * gpu_resident_route_calls` SplitFused invariant.

The first measured admission policy is inherited from the useful G100/G101
combined arm:

- minimum touches: 2;
- minimum absolute router weight: 0.02;
- minimum mass: 0;
- request budget: 64;
- window: 40 routed-layer calls;
- window budget: 1 promotion.

These values are a frozen first causal test, not claimed final tuning.

## Control and promotion arms

Future A/B runs use the same full/open Q1_0 fallback configuration:

- G129-control: complete Q1_0 resident fallback, exact IQ2 arena/cache, full/open
  router, mixed resolver ON, dynamic promotion OFF, zero promotion events, and
  no promotion gates.
- G129-promotion: the same configuration with dynamic promotion ON and only the
  causal admission gates above added.

The arms must not differ in arena sizes, expert coverage, cache320 seeding,
clock430, minfreq3, hysteresis1.25, split-fused, no-default-sync, prompt,
context, or max tokens.

## Prediction contract

G129 does not claim SPEX prediction. Initial VRAM seeding uses full-router
prefill mass, while decode replacement uses observed mass/frequency/recency.
SPEX remains observe-only until this transport and promotion path passes the
quality and throughput gates. Any later SPEX experiment must be a separate arm.

## Required telemetry

The result must expose at least:

- `router_mode=open` and proof that no expert bias/mask was installed;
- Q1_0 total, pinned, and pageable slots/bytes;
- exact IQ2 snapshot/probation slots and reserve size;
- Windows Q1_0 sidecar mmap source unlock ranges, bytes, success, not_locked,
  failed, and before/after available/working-set samples;
- optional `DS4_Q1_0_PROFILE=1` diagnostics, OFF by default: pinned/pageable
  resident route hits, H2D bytes and enqueue seconds; upload-stream sync seconds
  attributed by expert bytes; aggregate Q1 kernel and Q1+IQ2 join seconds; and
  `QueryWorkingSetEx` samples of only the sidecar source mapping at `pre-copy`,
  `post-bootstrap`, and `post-unlock-settle` (resident, shared, and known
  file-mapped bytes). When requested, missing, negative, or incoherent profile
  fields fail closed; when OFF they do not alter legacy gates;
- exact IQ2 VRAM slots, admissions, replacements, and demotions;
- Q1_0 routes, exact IQ2 VRAM routes, exact IQ2 RAM routes, tier-route entries,
  and joins;
- SplitFused primary-route basis, observed routes, expected routes, and the
  Q1_0 resident route count excluded from the primary-model transport
  denominator;
- promotion candidates, skips by each gate, promotions, bytes, and seconds;
- per-expert Q1_0 promotion attempt and terminal success/failure records, bounded
  exceptional reject records, `telemetry_record_count <= 2*attempts + failures +
  bounded_exception_limit`, plus the JSONL artifact path, SHA-256, count, and
  physical-line count;
- direct SSD-to-VRAM rejects and current-token IQ2 SSD violations;
- output, provenance, TTFT, prefill, server decode t/s, and L0-L3 grade.

## Input-only activation recovery trace

`DS4_EXPERT_RECOVERY_TRACE=1` is a diagnostic, OFF-default G129 mode for one
explicitly filtered layer/expert. The harness also requires layer, expert,
maximum-sample, byte-budget, canonical `g7_runs` output-prefix, and complete
model/sidecar/build provenance. A trace run is exactly one structural-safety
request with no warmup, full/open routing, no mask, the resident dual-arena
mixed resolver, and mixed route telemetry. The hard cap is 256 samples.

The capture records the selected expert's input activation, authoritative
request epoch, routed-layer call tick, request-local token index, top-k rank,
gate weight, and resolved Q1/IQ2 representation. The selected route has already
completed before capture. No individual teacher output is copied: there is no
stable per-expert output host boundary without adding another synchronization,
so this is an input-only activation recovery dataset. The offline exact-IQ2
teacher reconstructs each target output from the captured input and the
hash-bound primary IQ2 weights.

When tracing is OFF, no vector copy, synchronization, file creation, or policy
mutation is permitted. When ON, its D2H synchronization makes the run
diagnostic-only and ineligible for performance, quality, or SOTA claims. The
runtime writes a canonical little-endian float32 vector file and one strict
canonical JSON object per physical JSONL line. A strict manifest binds
dtype/shape/count/offsets, target identity, epoch/call ranges, file SHA-256,
model and Q1 sidecar identity, build manifest/fingerprint, and executable.
Vector plus JSONL plus manifest bytes must fit the configured budget. Partial
files are never accepted: vector and JSONL are flushed and moved first, and the
manifest is moved last as the atomic commit marker.

The first authorized teacher acquisition after CPU certification is one short
G129 full/open structural `n=1` using the exact-IQ2 primary model and verified
Q1 sidecar, with one target layer/expert and at most 256 samples. It can prove
artifact integrity, targeting, router metadata, and offline-teacher input
availability. It cannot yet prove activation-recovery quality, held-out
generalization, representative sampling, throughput, visual quality, or SOTA.

## SSD-WRAP exact-IQ2 host hierarchy

`DS4_Q1_0_PROMOTION_SSD_WRAP=1` enables an experimental promotion transport
that is OFF by default. When OFF, it creates no queue, worker, staging ring,
file handle, event, allocation, or telemetry, and the existing synchronous
Q1_0 promotion path remains unchanged. Enabling it does not change router
eligibility, promotion ranking, admission gates, request/window budgets, Q1_0
fallback coverage, quantization, or exact-IQ2 provenance.

An admitted expert follows this request-scoped state machine:

`REQUESTED -> SSD_INFLIGHT -> RAM_READY -> RAM_COMMITTING -> ELIGIBLE`

The current call always continues with resident packed Q1_0. The worker reads
exact IQ2 only into a fixed SSD ring. The request thread verifies all three
gate/up/down reads and checksums before publishing a stable host slot, and
`first_eligible_call` remains strictly greater than `observation_call`.
Deduplication is by layer/expert. Queue, wave count, bytes, and age are bounded;
queue pressure, stale work, or an occupied ring keeps the expert on Q1_0 and
never makes decode wait. Source-offset sorting is allowed, but coalescing is
allowed only when both source and destination ranges are contiguous and bound
to the same verified model receipt. A failed or partial read never publishes a
slot. Direct SSD-to-VRAM and same-call eligibility remain forbidden.

The exact-IQ2 host budget remains exactly 5.5 GiB. Four exact-expert slots are
reserved inside that budget as two fixed SSD-read ring slots and two fixed
pinned H2D-bounce slots; they are not additional RAM. Stable exact-IQ2 entries
have exclusive ownership in either the pinned or pageable-resident pool.
Transient duplication is limited to one bounded ring transition. A pageable
hit uses `PAGEABLE_READY -> PINNED_READY` through a bounded host memcpy into the
fixed pinned H2D ring, followed by asynchronous H2D. The hot path never performs
dynamic `cudaHostRegister` or `cudaHostUnregister`. Under host pressure,
pageable exact-IQ2 probation may be dropped before the full/open resident Q1_0
fallback is affected.

Three same-budget configurations are retained for a later short comparison:

- all-pinned control: 5.5 GiB pinned, 0 GiB pageable, including the four ring
  slots;
- 1.5 GiB pinned / 4.0 GiB pageable;
- 2.0 GiB pinned / 3.5 GiB pageable.

The first structural SSD-WRAP safety uses 2.0 GiB pinned / 3.5 GiB pageable.
At the measured 7,077,888 bytes per exact expert, a worst-case gate cadence of
43 routed layers / 40 calls * 6 tokens/s requests about 45.65 MB/s from SSD.
That is already about 93 percent of the observed 49.1 MB/s synchronous source
rate, so decode must retain Q1_0 under backpressure. The 2.0 GiB split keeps
roughly 299 stable pinned slots after the four rings, close to cache320, while
preserving roughly 531 pageable probation slots. This is a CPU cost-model
choice, not a throughput claim.

When enabled, strict telemetry reports per wave requests/dedup/ranges, requested
and useful bytes, queue depth, service time, coalescing, stale/drop counts,
RAM-ready and first-use counts, pinned/pageable/SSD/VRAM hits, host-copy bytes
and seconds, H2D-ready/wait, churn, and wasted promotions. Windows working-set
samples use `QueryWorkingSetEx` outside the token loop to distinguish resident,
paged-out, shared, and locked pageable-pool pages; process hard-fault deltas are
reported separately. Missing, negative, over-budget, or incoherent telemetry
fails closed only when SSD-WRAP is requested.

## Execution gates

1. Static contract tests and Release build must pass.
2. A short `n=1` safety run must show full/open routing, both disjoint arenas,
   nonzero Q1_0 and exact-IQ2 routes, Q1_0 source-unlock telemetry on Windows,
   zero failures, and zero forbidden direct SSD-to-VRAM transitions.
3. A long cyberpunk `n=1` output is graded immediately. Stop this arm if it is
   L0 or L1.
4. Only an L2/L3 safety output advances to counterbalanced `n >= 3` measurement.
5. SOTA eligibility requires median L3 and mean server decode above 6.0 t/s;
   `repeat_flag`, a short exact hash, or an `n=1` run is never a verdict.
6. Any child runtime failure before result parsing must materialize the promotion
   JSONL artifact when records exist, the harness `failure.json`, and the G129
   safety failure receipt automatically, including SHA-256 for failure,
   runtime telemetry, stdout/stderr, raw outputs, and the promotion artifact.
   The safety failure receipt SHA-256 is exposed by a deterministic companion
   index, not by self-hashing the receipt JSON. The bootstrap child uses the
   `--` delimiter consumed by `g7_harness_bootstrap.ps1`; no stop-parsing token
   is forwarded to the harness.
