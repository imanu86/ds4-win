# G66 Arena-28 Capacity Results

Date: 2026-07-16

## Scope

This is an `n=1` context-8192 capacity result for the first frozen arm. It
contains no performance or quality verdict. The K60 arm was not launched after
the common full-model composition failed before its first token.

## Full-Model Arm

The exact command is the G65 command recorded in
`G65_WRAP_TRIM_CAPACITY_RESULTS.md`, with these frozen changes only:

- tag `g66_arena28_g46safety`;
- max tokens `8`;
- `DynamicArenaGiB=28`;
- `ArenaWrapTrimBetweenPhases` absent.

Measured preflight and runtime:

- Available memory after cleanup: `46,729,895,936 bytes` (`43.520 GiB`).
- DynamicArena: `28.00 GiB`, `4247` slots (`304` fewer than G46/G63).
- Available memory immediately after arena prepare: `14.62 GiB`.
- Prefill-mass candidates: `4247`; ranked entries: `3479`.
- Candidate gate-mass coverage: `0.5566`.
- Last completed phase: arena fill began with `4247` loads.
- Runtime-monitor elapsed at abort: `53.678 s`.
- Minimum observed Windows available memory: `7,385,088 bytes`.
- Final abort sample available memory: `578,990,080 bytes`.
- Peak working set: `43,776,376,832 bytes`.
- Peak private bytes: `41,948,323,840 bytes`.
- Process read transfer: `36,265,359,070 bytes`.
- Page faults at final sample: `14,969,161`.
- Peak disk queue length: `34`.
- `contamination_abort`: `true`.
- First token: not reached.
- Post-run: no `ds4_server` process remained.

## Comparison With G64

| Gate | Preflight available | Arena | Slots | Minimum available | Result |
|---|---:|---:|---:|---:|---|
| G64 G46 | 49.24 GiB | 30 GiB | 4551 | 0.251 GiB | abort |
| G66 G46 | 43.52 GiB | 28 GiB | 4247 | 0.0069 GiB | abort |

The 2 GiB arena reduction did not establish a capacity improvement because the
G66 host started with about 5.72 GiB less available memory. This result rejects
a fixed 28 GiB arena as a generally safe context-8192 setting on this host. It
does not establish whether 28 GiB would pass from the G64 preflight state.

## K60 Decision

The K60 arm was not run with the same fixed arena after the common composition
failed. No K60 arena-28 capacity or performance claim is made.

## Next Gate

Arena capacity must be derived from measured available memory at runtime while
preserving an explicit post-allocation reserve, rather than selected as a fixed
GiB value. The requested arena remains an upper bound; the chosen byte/slot
count and the pre-allocation memory observation must be logged. Default behavior
must remain unchanged when the new cap is disabled.
