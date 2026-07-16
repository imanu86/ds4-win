# G68 Selective Source-Mmap Reclaim Protocol

Date: 2026-07-16

## Question

Can the full-model G46 composition keep its complete 30 GiB / 4551-slot pinned
arena at context 8192 by removing only already-consumed expert source pages from
the Windows working set after the `gate` and `up` copy barriers?

This is a replacement for neither G46 nor dynamic REAP. It isolates one host
memory transport lever and does not involve K60/K75 sparse bakes.

## Measured Basis

- G64 full G46 reached only 0.251 GiB available and aborted during initial WRAP.
- G65 process-wide trimming let WRAP finish, but evicted useful model pages and
  produced 0.08 t/s with 491.539 GB of process reads by token 50.
- G67's adaptive cap completed safely with only 2470 slots, but decode fell to
  0.13 t/s and process reads reached 87.493 GiB in eight tokens.
- G56 measured 9,842,393,088 source bytes in each of the `gate` and `up`
  phases. These are the only ranges G68 asks Windows to remove.

## Runtime Change

Implementation commit: `b1eacea`. Build manifest input fingerprint:
`d0a434ceb0acd49372ed028fe49b64d0660c08f09203db78ed970097165b72ee`.
Executable SHA-256:
`4f3565c3778263baf164fb596ee4bdc3dba6315f9658833fcce5e1166ff38f84`.

Opt-in `DS4_CUDA_ARENA_WRAP_UNLOCK_SOURCE_RANGES=1`, exposed by
`-ArenaWrapUnlockSourceRanges`, requires source-parts WRAP and trusted worker
checksums. After each completed `gate` and `up` barrier it:

1. selects only successful parts in that phase;
2. page-aligns, sorts and coalesces their source-mmap ranges;
3. calls `VirtualUnlock` without touching the pinned destination arena;
4. accepts `TRUE` and documented `FALSE/ERROR_NOT_LOCKED` behavior;
5. fails closed on every other Win32 error.

It is incompatible with process-wide trim and sequential/random file source
modes. Default-off behavior and the historical trim switch remain unchanged.

## Frozen Safety Arm

One `n=1` full-model safety run:

- tag: `g68_source_unlock_g46safety`;
- model: `C:\ds4-models\ds4-2bit.gguf`;
- context 8192, max eight tokens, temp 0, nothink;
- requested arena 30 GiB, no adaptive arena reserve;
- source-parts WRAP, trusted worker checksum, selective source unlock;
- PrefillMassWrap plus ComposePrefillMassTiering;
- cache 320 LRU, reserve 0.125 GiB;
- GPU-resident routes and RouteNoDefaultSync;
- mass-LFRU tiering `430/16/3/1.25`;
- disabled Q8/F16 cache, embedded-row staging, eight REAP prefetch threads;
- process-wide trim and file-source modes forbidden.

Exact command:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\g7_measure.ps1 `
  -MaxTokens 8 -Repeats 1 -Tag g68_source_unlock_g46safety `
  -Prompt "Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document." `
  -Context 8192 -BudgetGB 2 -ReserveMB 1024 -DynamicArenaGiB 30 `
  -ArenaWrapTrustWorkerChecksum -ArenaWrapSourceParts `
  -ArenaWrapUnlockSourceRanges -DisableQ8F16Cache -EmbedRowStaging `
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

- machine quiescent and no overlapping DS4 process;
- arena exactly 30 GiB / 4551 slots and WRAP published;
- exactly two source-unlock rows (`gate`, `up`) and one complete summary;
- all range calls accounted as `true + error_not_locked`, with zero failures;
- positive released-range bytes and before/after host-memory telemetry;
- unchanged contamination guard, non-empty output and clean exit;
- positive route calls, default-sync zero, zero backing misses, forbidden
  SSD-to-VRAM transfers, SSD bytes and tier failures;
- process reads, aggregate disk reads, minimum host memory, TTFT and decode are
  recorded as safety diagnostics only.

## Decision

This single run can establish only structural and capacity safety. If it passes,
the next commit preregisters an interleaved unlock-off/on `n>=3` A/B at the
original G46 workload, followed by long L0-L3 quality. If it fails, record the
failure without changing arena size or combining another lever. If capacity
passes but residual source-page pressure remains, a separate test may extend
selective reclaim to the completed `down` phase.
