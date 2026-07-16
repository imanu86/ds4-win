# G69 Waved Source-Mmap Reclaim Protocol

Date: 2026-07-16

## Question

Can bounded, source-sorted copy waves keep the full G46 30 GiB / 4551-slot
arena alive at context 8192 by reclaiming each wave only after all of its
workers have joined, across `gate`, `up` and `down`?

G69 changes only source-copy scheduling and selective mmap reclamation. It does
not use a sparse bake, a smaller arena, process-wide trimming or another new
performance lever.

## Measured Basis And Frozen Wave

G68 proved that selective reclaim works, but whole-phase barriers were too
late. Gate and up each touched about 9.852 GB and recovered the same working-set
amount. The final 12.527 GB down phase then reached only 65,990,656 available
bytes and triggered the unchanged three-sample guard before its barrier.

The first G69 safety freezes a `4.0 GiB` maximum page-aligned source range per
wave. With G68's measured 8.66 GiB available immediately after arena allocation,
this is intended to leave more than the 2 GiB runtime floor before each reclaim.
It is a preregistered safety point, not a claimed optimum.

Implementation commit: `be6f1fe`. Build manifest input fingerprint:
`ec0b8f38798869d93007809752eae9262d2cb79a75704452fe0e7add7fdc9af1`.
Executable SHA-256:
`9bbcbc57714611bd3873beedc7fc4f0829ee463e0499793b86295eb085cca501`.

## Runtime Contract

- `ArenaWrapUnlockSourceRanges` remains required and default-off.
- `ArenaWrapUnlockWaveGiB=4` enables wave mode.
- Every wave contains a source-sorted union of page-aligned ranges no larger
  than 4 GiB; an individual part larger than the cap fails closed.
- Worker cursor bounds isolate one wave. All workers join before its ranges are
  passed to `VirtualUnlock`.
- Successfully copied and reclaimed parts remain valid destination-arena data.
- Checksum order remains `gate || up || down` for every load.
- Telemetry emits one aggregate row per phase, including wave count and maximum
  page-aligned bytes in any wave, plus a three-phase summary.
- Process-wide trim and sequential/random file sources remain forbidden.
- Wave value zero preserves the prior G68 phase-barrier behavior.

## Frozen Safety Arm

One `n=1` full-model safety run:

- tag `g69_wave4_g46safety`;
- model `C:\ds4-models\ds4-2bit.gguf`;
- context 8192, max eight tokens, temp 0, nothink;
- exact G68/G46 composition, fixed 30 GiB arena and 4551 slots;
- selective source reclaim with a 4 GiB wave cap.

Exact command:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\g7_measure.ps1 `
  -MaxTokens 8 -Repeats 1 -Tag g69_wave4_g46safety `
  -Prompt "Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document." `
  -Context 8192 -BudgetGB 2 -ReserveMB 1024 -DynamicArenaGiB 30 `
  -ArenaWrapTrustWorkerChecksum -ArenaWrapSourceParts `
  -ArenaWrapUnlockSourceRanges -ArenaWrapUnlockWaveGiB 4 `
  -DisableQ8F16Cache -EmbedRowStaging `
  -PrefillMassWrap -ComposePrefillMassTiering `
  -ExpertCacheN 320 -ExpertCacheReserveGB 0.125 -ExpertCachePolicy lru `
  -GpuResidentRoutes -RouteNoDefaultSync `
  -ExpertTiering enforce -ExpertTierPolicy mass-lfru `
  -ExpertTierClockCalls 430 -ExpertTierReplacementBudget 16 `
  -ExpertTierMinFrequency 3 -ExpertTierHysteresis 1.25 `
  -ReapPrefetchThreads 8 -ModelPath C:\ds4-models\ds4-2bit.gguf `
  -TimeoutSec 1800
```

## Required Evidence

- quiescent preflight and no overlapping DS4 process;
- arena exactly 30 GiB / 4551 slots and WRAP published;
- exactly three successful aggregate rows: `gate`, `up`, `down`;
- each phase has positive waves/ranges/bytes, zero failures and complete
  `true + error_not_locked == calls` accounting;
- measured maximum page-aligned bytes per wave is at most 4 GiB;
- summary equals phase-row totals and reports all three phases;
- minimum available host memory remains above the unchanged guard;
- non-empty output, clean exit, positive route calls and default-sync zero;
- zero tier backing misses, forbidden SSD-to-VRAM bytes and tier failures;
- process reads, disk reads, TTFT and decode are retained as safety diagnostics,
  not promoted from this single run.

## Decision

If the safety arm passes, preregister an interleaved unlock-off/on `n>=3` A/B
at the original G46 workload, followed by long n>=3 L0-L3 quality. If it fails,
record the exact wave and phase without changing the cap or composing another
lever. Smaller waves are a later isolated sweep only if the measured failure is
still source-memory pressure rather than a correctness or transport fault.
