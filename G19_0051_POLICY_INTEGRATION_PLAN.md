# G19 0051 policy integration plan

## Objective

Connect the existing session-learned REAP/PACE policy to G18's transactional
pinned arena without reviving the unsafe ordering `publish mask -> fetch later`.
G19 is a mechanism gate: W16 observes the current interaction, then proposes K23
for the 40 maskable routed layers. It is not a static domain mask, a baked mask,
or a prompt-trained policy.

K23 is intentionally temporary. Existing quality evidence rejects it as the
final production width; the current 0051 design targets a substantially wider,
adaptive current-interaction set, with K154 as the principal capacity point.

## Checkpoint chain

- `a880b01`: pinned `cudaHostAllocDefault` arena substrate.
- `ad4c66b`: standalone native pinned-capacity probe.
- `3304111`: transactional WRAP, direct arena hits, and rollback validation.
- `d797516`: mandatory Windows memory preflight and allocation guards.

## Required transaction

1. Observe token `t` from every non-hash router's full 256-value unbiased
   `router_probs` row. Observation must remain active even when SPEX is off.
2. Commit the W16 history and construct an immutable inactive host snapshot for
   token `t+1`. Do not mutate the active mask in place.
3. Keep exactly 23 experts in layers 3..42 for this gate; leave hash layers
   unmasked and on fallback.
4. Call `ds4_gpu_dynamic_arena_begin()` with the complete candidate set. G18
   retains matching READY slots and returns only missing entrants.
5. Sort entrants by source offset and WRAP complete gate/up/down triplets using
   bounded Windows workers. Join every worker and call
   `ds4_gpu_dynamic_arena_finish_load()` for every descriptor.
6. Prepare inactive router-bias rows as
   `original_bias[e] + (pruned ? -1e9f : 0)`.
7. Publish arena bindings and bias rows as one generation, then release-store the
   matching host snapshot. The next command interval sees both or neither.
8. On any allocation, I/O, checksum, upload, or publication failure, abort and
   retain the old arena plus old mask. Never reduce K to fit capacity.

## Code hooks

- Add immutable active/staging policy snapshots and the W16 observer near the
  router state in `ds4.c`.
- Invoke the policy tick at the top of `metal_graph_eval_token_raw_swa()`, before
  `ds4_gpu_begin_commands()`, after the previous token has completed.
- Add layer identity to router-select GPU APIs so CUDA selects the active bias row.
- Extend the arena publication API to swap active/staging bindings and bias rows
  together.
- Add reset/arm hooks to every successful `ds4_session_sync()` exit. Reset returns
  routing to unmasked K0 while the prior arena remains only a residency hint.
- Require hidden SPEX prefetch off for G19 unless queue quiescence is implemented.

## Runtime fixture

```text
DS4_PACE_LIVEMASK=1
DS4_PACE_LIVEMASK_BOOTSTRAP=10
DS4_PACE_LIVEMASK_WINDOW=16
DS4_PACE_LIVEMASK_K=23
DS4_REAP_PREFETCH_THREADS=8
```

Keep adaptive K off for the mechanism gate. Keep `DS4_REAP_MASK_FILE`, static
domain masks, and the old per-layer actuator unset. Keep selected-load enabled so
published arena hits reach the compact expert buffer.

Capacity must be at least 920 active slots plus all entrants required by the next
proposal. Reserving two entrants for each of 40 layers requires 1,000 slots, or
6.59 GiB. Insufficient capacity is a transaction failure, not permission to
narrow the mask.

## Verification gates

1. Build and a diagnostic transaction test with forced entrant, checksum failure,
   and rollback.
2. Greedy expected-output hash equality with policy disabled, `n >= 3`.
3. W16/K23 mechanism run with trace proving: observe, candidate, entrant set,
   WRAP complete, combined publish, arena hits, and no pre-publication mask use.
4. Quality grading remains L0-L3 on complete outputs. Repeat flags and single
   samples are never verdicts.
5. Performance A/B uses clean-host memory preflight and counterbalanced arm order.

## Follow-on gates from modest-hardware research

The external landscape review in
`reap-loop/.claude/worktrees/adoring-rosalind-44324f/docs/PORT_WINDOWS_NATIVE/06_MOE_MODEST_HW_RESEARCH.md`
supports testing, but does not itself measure this engine:

- chunk gate/up/down transfers and let confirmed entrants preempt speculative I/O;
- parallelize transfer only after traces show remaining serialization;
- prefer frequency/mass-aware residency over pure LRU;
- evaluate a hybrid CPU/GPU cold-expert path separately, because other engines
  avoid paying synchronous H2D on every miss.

These remain hypotheses until measured locally with correctness controls.
