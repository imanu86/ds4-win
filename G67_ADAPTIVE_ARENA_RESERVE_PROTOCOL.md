# G67 Adaptive Arena Reserve Protocol

Date: 2026-07-16

## Question

Can an opt-in runtime cap preserve a measured 22 GiB of available host memory
before allocating DynamicArena, allowing context-8192 WRAP to complete without
the destructive process-wide trim and without selecting a fixed arena size?

## Basis For The First Reserve

G64 full fell from 18.51 GiB available after arena preparation to 0.251 GiB at
abort, a measured delta of about 18.26 GiB during source-backed WRAP. The first
22 GiB reserve combines that observed demand, the unchanged 2 GiB runtime guard
and additional margin. This is a preregistered safety point, not a claimed
optimum.

## Runtime Change

- Requested DynamicArena remains 30 GiB and is an upper bound.
- `DynamicArenaMinAvailableGiB=22` asks the runtime to subtract 22 GiB from
  `GlobalMemoryStatusEx.ullAvailPhys` immediately before `cudaHostAlloc`.
- The remaining budget is rounded down to whole expert slots.
- If less than one slot fits, the arena is disabled fail-closed.
- Default value zero preserves prior behavior.
- Requested/chosen bytes and slots, available-before, reserve, cap status and
  reason must be present in `[arena-cap]` telemetry and the result JSON.

Implementation commit: `5df6c8e`. Build manifest input fingerprint:
`13ecb3b2f0d0eaeccf1141e44d7f1e673c77cbdd2bbb76d245e6d048095d5102`.
Executable SHA-256:
`4693d870b62a56b6c3f265e3825697e362310362d7e5821f1d190c55017592aa`.

## Frozen Arms And Order

1. `g67_autocap22_g46safety`: full model.
2. `g67_autocap22_k60safety`: K60 sparse bake, only if the common arm passes.

Both are `n=1` safety/transport gates with context 8192, max eight tokens,
temperature zero and nothink. They use the G46/G63 composition with requested
arena 30 GiB, source-parts WRAP, trusted worker checksum, PrefillMassWrap,
ComposePrefillMassTiering, cache 320 LRU/reserve 0.125 GiB, GPU-resident routes,
RouteNoDefaultSync, mass-LFRU tiering (`430/16/3/1.25`), disabled Q8/F16 cache,
embedded-row staging and eight REAP prefetch threads.

`ArenaWrapTrimBetweenPhases` is forbidden. K60 additionally receives only its
embedded-bake authorization and expected mask SHA-256
`5b6d98504ba830c1a50945a93d1a6017b1956bd17c56df8c0b1bdf92c1564e97`.

## Required Evidence

- preflight ready and no overlapping DS4 process;
- `[arena-cap]` requested 30 GiB, reserve 22 GiB, cap result ready and chosen
  slots/bytes exactly equal to the subsequent arena allocation;
- memory contamination guard unchanged and no abort;
- WRAP publish, non-empty deterministic output and clean process exit;
- route calls positive, default-sync zero, zero tier backing misses, forbidden
  SSD-to-VRAM transfers, SSD bytes and failures;
- K60 only: embedded mask/hash, sparse replacement and restore all observed
  with zero rejection/failure.

## Decision

A passing arm is eligible for n>=3 performance only at the exact observed slot
count or under a separately registered adaptive-cap policy that records every
chosen count. Long quality still requires the G64 n>=3 L0-L3 protocol. A safety
failure is recorded as capacity evidence; do not lower the reserve ad hoc.
