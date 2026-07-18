# G110 Q1_0 Dual Arena Protocol

## Scope

Define the fail-closed protocol for opt-in composition under:

```text
DS4_Q1_0_DUAL_ARENA=1
```

The composite is disabled by default. When the env flag is absent, empty, or exactly `0`, DS4 must behave exactly as the current single-arena build behaves. Any other value except exact `1` is invalid and must fail closed.

The env flag is intentionally strict:

- Unset: off.
- `0`: off.
- `1`: on, subject to all structural and provenance gates.
- Any other value: fail closed; the dual arena must not activate and the run must not be treated as a valid composite run.

This file defines protocol only. It does not authorize DS4/GPU runs, SOTA claims, commits, or changes outside this document.

## Composition Model

The dual-arena composite has two physically and logically separate arenas:

1. Primary arena: existing G46 arena, unchanged.
2. Q1_0 arena: new static Q1_0 arena, separate from G46.

The G46 arena remains the source of truth for existing behavior. The Q1_0 arena is an opt-in companion structure and must not alter G46 layout, allocation policy, addressing, lifetime, or validation semantics.

No shared mutable state may be introduced between the arenas except through the explicit resolver contract described below.

## Fail-Closed Default

The implementation must fail closed at every boundary:

- If `DS4_Q1_0_DUAL_ARENA` is unset, behavior is byte-for-byte and decision-for-decision equivalent to the non-composite path.
- If `DS4_Q1_0_DUAL_ARENA=0`, the composite remains disabled.
- If `DS4_Q1_0_DUAL_ARENA` is set to any value other than exact ASCII `0` or `1`, the run fails closed and must not continue as a composite run.
- If the Q1_0 static arena cannot be proven complete, aligned, bounded, and addressable, the composite remains disabled.
- If resolver provenance is incomplete or ambiguous, the composite remains disabled.
- If any negative gate fires, the composite remains disabled.
- If the structural dual gate fails, the composite remains disabled.
- If validation has not reached `n >= 3` and L0-L3, the composite remains non-claimable.

No fallback may silently mix partially validated Q1_0 data into the primary path.

## Env-Off Exactness

Env-off exactness is mandatory.

With `DS4_Q1_0_DUAL_ARENA` absent or exactly `0`:

- The G46 arena must be initialized exactly as before.
- The Q1_0 arena must not be allocated, populated, resolved, queried, or observed.
- No Q1_0 env flags may be set or consumed for the run, including `DS4_Q1_0_EXPERT_SIDECAR`, `DS4_Q1_0_SELECTED_LOAD`, `DS4_Q1_0_RESIDENT_ARENA`, `DS4_Q1_0_DUAL_ARENA=1`, `DS4_Q1_0_LAYER_FIRST`, or `DS4_Q1_0_LAYER_LAST`.
- Resolver code must return the existing G46 backing path without side effects.
- Provenance records for Q1_0 must not be emitted.
- Metrics must not add composite-only counters that perturb output, logs, timings used by gates, or persisted artifacts.
- Test output must demonstrate exact equality against the current G46 baseline for every observable surface used by G46 gates.

Env-off behavior is not "compatible enough"; it is exactness against the current G46 baseline with no Q1 flags.

With `DS4_Q1_0_DUAL_ARENA` set to any value other than exact ASCII `0` or `1`, DS4 must fail closed before composite initialization. Such a run is invalid for both env-off exactness and env-on validation.

## Backing Resolver

All backing selection must pass through a single explicit resolver.

The resolver receives:

- Requested logical backing key.
- Current env state.
- Primary G46 arena descriptor.
- Q1_0 static arena descriptor, only when the composite is enabled and structurally valid.
- Provenance sink.

The resolver returns one of:

- `G46_PRIMARY`
- `Q1_0_STATIC`
- `COMPOSITE_DISABLED`
- `RESOLUTION_ERROR`

The resolver must never infer Q1_0 backing from incidental address ranges, filenames, allocation order, or implicit global state. The choice must be explicit, deterministic, and provenance-backed.

Resolver rules:

- Existing G46 requests resolve to `G46_PRIMARY` unless an explicit, validated composite mapping says otherwise.
- Q1_0 requests resolve to `Q1_0_STATIC` only when the env flag is exactly `1`, the Q1_0 arena has passed structural validation, and provenance can identify the source and mapping.
- Ambiguous backing keys are hard failures.
- Missing Q1_0 entries are hard failures for composite use and must not fall back to approximate G46 data.
- Resolver failure disables composite use for the affected run.

### Per-selected-expert contract

The executable resolver operates after the unchanged router has selected its
six expert IDs and weights. For each selected expert it must use this order:

1. exact IQ2 copy in protected VRAM;
2. exact IQ2 copy in the published request snapshot in pinned RAM;
3. exact IQ2 copy in the tier-owned probation/warm RAM pool;
4. resident Q1_0 only when the authoritative IQ2 state is `SSD_COLD` and no
   IQ2 RAM copy exists;
5. otherwise fail closed.

Router admissibility and representation residency are separate concerns. Q1_0
residency must not add an expert to a closed router mask. The first executable
composite therefore uses the explicit request-scoped open-router mode.

The current token must never read an IQ2 expert from SSD after the resolver has
selected Q1_0. IQ2 promotion is disabled in the first structural smoke. Router
mass and frequency are still observed for Q1_0 routes so a later asynchronous
promotion policy can act on future tokens.

The hot IQ2 subset and cold Q1_0 subset execute independently with the original
router IDs and weights. Their output vectors are summed once. Selection and
weights are never recomputed, renormalized, or trained from the prompt.

Structural runs enable `DS4_Q1_0_MIXED_TRACE=1`. They emit one provenance row
for every selected route: layer, route index, expert ID, unchanged router
weight, chosen representation, authoritative tier state, IQ2-RAM presence and
both arena snapshot generations. Aggregate-only telemetry is insufficient.

The mixed wrapper snapshots the IQ2 tier SSD counters before dispatching its
hot subset. Any increase in IQ2 SSD bytes or cold-to-RAM loads during that
dispatch is a fail-closed violation. This is scoped to the mixed layer and does
not confuse unrelated transport in other layers with the selected Q1_0 route.

## Provenance

Every composite-backed decision must carry provenance sufficient to reconstruct why the resolver selected its backing.

Required provenance:

- The active Q1 sidecar carries a byte-identical copy of the primary
  `ffn_gate_inp.weight`; startup compares it before router IDs may address Q1
  experts. Matching only model name, norms, or routing bias is insufficient.
- The mixed resolver validates the complete `40 * 256` tier table before any
  per-route entry access and fails closed on malformed state.
- Env flag value and exact enablement decision.
- G46 arena identity, version, and immutable descriptor.
- Q1_0 arena identity, version, static descriptor, bounds, alignment, and source artifact identity.
- Logical key requested.
- Resolver decision.
- Negative gate results.
- Structural dual gate result.
- Validation level reached.
- Run index for `n >= 3` validation.

Provenance must be emitted only when composite code is enabled. Env-off runs must not gain Q1_0 provenance noise.

## Negative Gates

Any negative gate failure disables the composite. Negative gates include:

- Env flag is unset or exactly `0`, which disables the composite.
- Env flag is any value other than exact ASCII `0` or `1`, which fails closed.
- Q1_0 static arena descriptor is missing, mutable, malformed, unaligned, out of bounds, or not reproducible.
- Q1_0 arena overlaps G46 arena in address space or ownership.
- Resolver observes ambiguous backing.
- Resolver observes a key that can resolve differently across identical inputs.
- Q1_0 data requires mutation to participate.
- G46 behavior changes while env-off.
- Composite path changes G46 arena layout or lifecycle.
- Provenance is missing, partial, or inconsistent.
- Any validation sample fails, flakes, or cannot be replayed.

The default response to uncertainty is disabling the composite.

## Structural Dual Gate

Before performance or quality validation, the structural dual gate must prove:

- G46 primary arena is unchanged.
- Q1_0 arena is static and separate.
- No allocation, aliasing, or ownership overlap exists between arenas.
- Resolver covers every composite mapping explicitly.
- Env-off exactness is demonstrated.
- Env-on initialization is deterministic.
- Failure paths disable composite use rather than degrading into mixed partial state.
- Provenance is complete for each resolver decision.

The structural dual gate is a prerequisite for all downstream claims.

### First executable smoke

The first run is targeted transport evidence, not a performance or quality
sample:

- one process, one generated token, temperature zero and no visible thinking;
- the G73 transport stack for the primary IQ2 path;
- a 6 GiB primary arena with 32 open-router reserve slots, deliberately small
  enough to exercise at least one real Q1_0 cold route;
- the verified layer-42 Q1_0 sidecar in a separate resident arena;
- synchronous IQ2 promotion disabled;
- required counters: mixed calls, Q1_0 resident routes and joins all positive;
- required zero counters: mixed failures, Q1_0 resident misses, Q1_0 direct
  pread fallbacks/bytes, mixed-layer IQ2 SSD bytes/violations and unresolved
  resolver decisions;
- exactly six per-route provenance rows, all bound to layer 42, unique route
  and expert IDs, `SSD_COLD`, no IQ2 RAM copy and a live Q1_0 snapshot;
- response content SHA-256 fixed to the known temp-zero one-token `Hello`
  result; `outputs_identical` from a single repeat is not an exactness gate;
- result source, header, harness and executable hashes must match current files,
  including when `-SummarizeExisting` is used.

If this passes, the same mechanism moves to the full 30 GiB G73 arena. Only
that full-size run can precede exactness, `n >= 3`, L0-L3 and performance work.

## Validation Ladder

After negative gates and the structural dual gate pass, validation proceeds through:

- `n >= 3`: at least three independent reproducible runs.
- `L0`: build and initialization correctness.
- `L1`: resolver and provenance correctness.
- `L2`: functional parity or intended-delta validation.
- `L3`: performance and stability validation under composite mode.

All levels must pass before the composite is treated as validated. A lower-level pass does not authorize higher-level claims.

## G109 Constraint

G109 n3 eliminated `pread`, but the observed result was only a `+1.4455%` isolated decode improvement.

That result is not a composite validation result. It does not prove the Q1_0 dual-arena protocol, does not satisfy the structural dual gate, and does not establish SOTA.

No SOTA claim is valid until the full composite passes:

- Fail-closed env exactness.
- Negative gates.
- Structural dual gate.
- `n >= 3`.
- L0-L3 validation.

Until then, the only allowed statement is that G109 n3 removed `pread` and showed a `+1.4455%` isolated decode improvement.
