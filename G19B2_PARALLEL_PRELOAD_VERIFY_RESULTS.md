# G19B2 parallel preload verification

## Objective

G19B verified every completed expert preload with a scalar FNV-1a pass inside
the selected-load token path. A wide W64 observation mirrored 23.57 GiB and
made that validation visible in the bootstrap latency. G19B2 keeps the source
`memcmp`, but leaves completed slots inactive until a bounded parallel checksum
pass at the publication boundary.

The transition remains transactional: every checksum and every binding is
validated before any slot changes from `LOADING` to `STAGED`. The active arena
generation is unchanged on failure. Telemetry reports the workers that actually
started and the verification duration.

## Wide mechanism observation

Two adjacent single-sample runs used the same binary configuration except for
the checksum placement. These are mechanism observations, not an n>=3
performance verdict.

Common configuration:

- native Windows, RTX 3060 12 GB, CUDA 12.6;
- Cyber HTML prompt, greedy/nothink, max 256;
- 30 GiB pinned arena, W64, min-hits 1;
- selected-load on, expert cache/SPEX/overlap off, I/O QD 1;
- RAM-stream budget 2 GiB and VRAM reserve 1,024 MiB.

| Metric | Inline FNV | Parallel boundary FNV |
|---|---:|---:|
| generated tokens | 213 | 213 |
| resident experts | 3,576 | 3,576 |
| mirrored payload | 23.57 GiB | 23.57 GiB |
| arena hits / misses | 27,890 / 10,534 | 27,890 / 10,534 |
| time at token 50 | 60.481 s | 37.121 s |
| server decode | 1.85 t/s | 2.37 t/s |
| final chunk | 4.34 t/s | 4.26 t/s |
| total decode | 114.862 s | 89.725 s |
| boundary verification | inline | 2.878 s, 8 workers |

Both runs produced SHA-256
`f2677447c1a5e95934469c6c8f07ee943ccd9c079ef9350b07c2d0ce8fc1b576`
and zero arena fatal errors. The final chunks above 4 t/s demonstrate that the
direct pinned-RAM path can exceed the historical approximately 3.4 t/s WSL
number once warm. They do not constitute an OS A/B: that WSL result used a
different K23 policy and launch configuration.

## Exact safety run

The reviewed implementation was rebuilt and checked with W16/min-hits-3,
12 GiB arena, and the historical Cyber64 expected hash:

- output SHA-256:
  `fd6c4522975a71e252b90199d49cfe3236310e2a7285dc0fc4d0e9d0e4885510`;
- resident/preloaded: 439/439;
- boundary loads: 0;
- verification: 0.371 seconds with 8 workers;
- hits/misses: 4,247/8,119;
- fatal errors: 0.

Artifact prefix:
`g7_runs/g7_g19b2_reviewfix_w16_m3_arena12_cyber64_safety_n1_*`.

## Decision and next gate

Keep the parallel boundary verification. The next transport gate is a grow-only
session arena: continue observing after the first publication, mirror recurring
misses into unused slots, and periodically publish `active READY + completed
preloads` with zero boundary rereads. No eviction is needed for the first gate.

After coverage growth is measured, test independently:

1. VRAM reserve 1,024/512/256 MiB on a realistic context;
2. a mass-ranked per-layer VRAM tier;
3. upload-event handoff instead of the per-layer host synchronization;
4. live adaptive masks only after transport coverage is understood.
