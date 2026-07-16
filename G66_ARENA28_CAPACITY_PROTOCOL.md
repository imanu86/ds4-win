# G66 Arena-28 Capacity Protocol

Date: 2026-07-16

## Question

Does reducing the DynamicArena from 30 GiB/4551 slots to 28 GiB provide enough
host-memory headroom for context 8192 without process-wide working-set trim,
while preserving the rest of the G46 composition for the full model and K60?

## Scope

This is an `n=1` capacity, exactness and transport safety per arm. Max generation
is eight tokens because the capacity failure occurs during WRAP, before decode.
No throughput, TTFT or quality verdict can be made from this gate.

## Frozen Arms And Order

1. `g66_arena28_g46safety`: full model.
2. `g66_arena28_k60safety`: K60 sparse bake.

Common flags are the complete G46 composition except for the single frozen
arena change `DynamicArenaGiB=28`:

- context `8192`, max tokens `8`, temperature `0`, nothink;
- source-parts WRAP and trusted worker checksum;
- no `ArenaWrapTrimBetweenPhases`;
- PrefillMassWrap and ComposePrefillMassTiering;
- expert cache `320`, LRU, reserve `0.125 GiB`;
- GPU-resident routes and RouteNoDefaultSync;
- mass-LFRU tiering: clock `430`, replacement budget `16`, minimum frequency
  `3`, hysteresis `1.25`;
- Q8/F16 cache disabled, embedded-row staging, eight REAP prefetch threads;
- unchanged preflight, isolation and runtime contamination guards.

K60 additionally receives only `AllowEmbeddedBakeMask` and expected embedded
mask SHA-256
`5b6d98504ba830c1a50945a93d1a6017b1956bd17c56df8c0b1bdf92c1564e97`.

## Required Evidence

- no overlapping DS4 process and clean preflight;
- arena requested/observed as 28 GiB with allocated slot count recorded;
- WRAP publishes and request completes without contamination abort;
- non-empty deterministic output, route calls positive and default-sync zero;
- zero tier backing misses, forbidden SSD-to-VRAM transfers, SSD bytes and
  tier failures;
- K60 only: embedded sparse mask/hash observed, candidate replacement and mask
  restoration succeed with zero rejection/failure.

## Decision

If an arm passes, it becomes eligible for a separately preregistered n>=3 short
performance gate and the G64 long L0-L3 quality matrix. If the smaller arena
creates misses or exactness failures, record them rather than increasing the
arena ad hoc. The process-wide G65 trim remains disabled in every G66 run.
