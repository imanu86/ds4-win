# G127-G130 full-open base/residual architecture

## Objective

Reach useful DS4 decode throughput on the RTX 3060 12 GB / 64 GB host while
preserving the original router decision. The router always sees all 256
experts. Residency and representation may change; expert admissibility may
not.

The target is more than 6 server decode tokens/s with exact provenance,
uncontaminated `n >= 3` measurements and L0-L3 output grading. A throughput
result without those gates is a transport observation, not SOTA.

## Measured starting point

- G112 proves the full/open Q1_0 transport ceiling is high enough: 6.76 t/s,
  but the single run graded L0.
- G123 is the current exact full/open IQ2 control: 1.65 t/s mean at n=3.
- G126 makes exact nested reconstruction cheap enough to be useful: GPU join
  reaches 1.57 t/s versus 1.153333 for CPU join, with exact output at n=3.
- G126 still preads the residual for every GPU join and transfers base plus
  residual on every non-VRAM route.
- G73 is 4.986667 t/s, but decode is request-scoped closed. It is historical
  transport evidence, not a full/open quality reference.

## Why the independent Q1_0 path is not the final architecture

The all-routed Q1_0 catalog is about 36.4 GiB. Keeping it resident leaves too
little host memory for enough exact IQ2 experts. The measured Q1-dominant runs
remain L0-L1. Keeping a full Q1_0 copy plus a large independent IQ2 copy also
duplicates most of the information and exceeds the useful host budget.

The nested representation keeps one resident base and a separate exact
residual:

- resident base: about 3.75 MiB/expert, 37.5 GiB for routed layers 3..42;
- exact residual: 3 MiB/expert, 30 GiB for all routed experts;
- base plus residual reconstructs the authoritative IQ2_XXS/Q2_K bytes;
- a bounded residual catalog can therefore make more experts exact than an
  equal-size independent IQ2 catalog.

Q1_0 remains a measured transport ceiling and a useful kernel reference. The
active quality-preserving representation is the exact-upgradable nested base.

## Memory budget

The initial RTX 3060 host budget is:

- 30 GiB maximum pinned host memory across base and residual storage;
- pageable overflow for the remaining resident base/residual bytes;
- at least 4 GiB physical host headroom before a benchmark starts;
- no mapped/device-visible host window;
- no second full IQ2 host copy.

The first all-layer target is 37.5 GiB base plus 12-14 GiB residual capacity.
The exact residual capacity is selected from measured host headroom, never
hard-coded as a claim that the machine can always sustain 14 GiB.

## Authoritative per-route decision

For every router-selected `(layer, expert, weight)`:

1. Exact IQ2 already resident in a protected VRAM slot: launch it directly.
2. Base resident and residual resident in host RAM: upload both, reconstruct
   exact IQ2 on GPU, and publish/admit the exact result to the VRAM cache.
3. Residual absent and this is the lowest-weight unresolved route: a later
   gated phase may use base-only for this token and start residual promotion.
4. Residual absent for any higher-weight unresolved route: wait for the exact
   residual or fail closed. Never substitute a different expert.

G127 and G128 are exact-only. Rule 3 is disabled until G129 and cannot affect
their output.

## G127: residual-only host cache for GPU join

G127 removes the repeated residual pread in
`cuda_nested_residual_join_to_device_exact()`.

Implementation contract:

- cache residual bytes, not reconstructed native experts;
- key every entry by `(layer, expert)`;
- support pinned storage first and optional pageable overflow later;
- GPU join resolves the residual cache before any file read;
- one miss performs one expert-major residual pread and publishes the entry;
- reuse is protected by the existing completion event before eviction;
- CPU reconstruction remains zero when GPU join is enabled;
- router selection, weights and launch order are unchanged;
- exact reconstruction verification remains available and fail-closed.

Required new counters:

- residual cache hits, misses, evictions and resident entries;
- pinned/pageable residual hits and bytes uploaded;
- residual pread bytes avoided;
- GPU join calls that consumed cached residuals;
- invariant failures.

G127 safety requires exact output SHA, zero mismatch/failure, nonzero residual
cache hits, fewer residual preads than G126 for the same route trace and zero
CPU reconstruction. Its n=3 performance verdict is against G126 GPU join and
G123 exact full/open IQ2.

## G128: all-layer resident base with split storage

G128 extends the nested base to all routed layers without one impossible
37.5 GiB `cudaHostAlloc`.

- allocate a configured pinned budget and pageable overflow separately;
- give each `(layer, expert)` an explicit base pointer and storage class;
- distribute pinned slots by prefill mass, with a per-layer floor;
- keep the router open and retain every base in either pinned or pageable RAM;
- load the residual cache by prefill mass and update it on a slower LFRU clock;
- do not rotate physical storage on every token.

The all-layer sidecar is generated only after G127 passes exact safety and
shows that residual cache reuse is real. The sidecar may live on D:, while the
resident bytes used during decode are in host RAM.

## G129: one base-only lane plus exact promotion

G129 enables the quality experiment requested by the project:

- at most one unresolved lane per layer may run base-only;
- it must be the selected lane with the lowest current router weight;
- all other selected lanes remain exact;
- the missed residual is requested immediately for a future token;
- promotion never changes the current selected expert ID;
- if more than one lane is unresolved, higher-weight lanes wait for exact
  residuals;
- an environment gate defaults this behavior off.

Required counters include base-only calls/lanes, selected weight, promotion
requested/completed/cancelled, exact waits, and tokens until promoted. Quality
is graded L0-L3 at n>=3; no repeat flag is a verdict.

## G130: remove duplicate launch work

Only after G129 quality passes:

- quantize the MoE input once;
- partition exact-VRAM, exact-join and base-only lanes without D2H selection
  round trips;
- launch one coordinated MoE path and one output reduction;
- retain SplitFused for native exact lanes;
- overlap cancellable residual promotion with useful GPU work.

SPEX may rank future residual promotions only after this transport path is
fast enough to overlap. SPEX never trains on a prompt-specific mask and never
changes router selection.

## Permanent gates

- Full/open router: no REAP mask, no static domain mask, no candidate-set
  pruning.
- Model, sidecar, payload and binary provenance recorded by SHA-256.
- Safety run before every rebuilt benchmark binary.
- Exactly one DS4 process during each measurement.
- Quiescence and contamination gates must pass.
- n>=3 independent processes for performance or quality verdicts.
- L0-L3 grading for generated output.
- Every negative result remains in the ledger with its complete launch
  parameters.
