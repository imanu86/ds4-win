# G65 WRAP Trim Capacity Results

Date: 2026-07-16

## Scope

This is an `n=1` structural/capacity result. It is not an n>=3 performance or
quality verdict. The run was deliberately stopped after the server had emitted
a measured token-50 progress line because the transport behavior was already
catastrophic and continuing could not establish a useful safety property.

## Frozen Full-Model Arm

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\g7_measure.ps1 -MaxTokens 64 -Repeats 1 -Tag g65_trim_g46safety -Prompt "Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document." -Context 8192 -BudgetGB 2 -ReserveMB 1024 -DynamicArenaGiB 30 -ArenaWrapTrustWorkerChecksum -ArenaWrapSourceParts -ArenaWrapTrimBetweenPhases -DisableQ8F16Cache -EmbedRowStaging -PrefillMassWrap -ComposePrefillMassTiering -ExpertCacheN 320 -ExpertCacheReserveGB 0.125 -ExpertCachePolicy lru -GpuResidentRoutes -RouteNoDefaultSync -ExpertTiering enforce -ExpertTierPolicy mass-lfru -ExpertTierClockCalls 430 -ExpertTierReplacementBudget 16 -ExpertTierMinFrequency 3 -ExpertTierHysteresis 1.25 -ReapPrefetchThreads 8 -ModelPath C:\ds4-models\ds4-2bit.gguf -TimeoutSec 1800
```

- Preflight available memory: `46.05 GiB` after cleanup.
- Context: `8192`; context buffers: `333.21 MiB`.
- DynamicArena: `30.00 GiB`, `4551` slots.
- WRAP trim: `2` calls, `2` succeeded, `0` failed, `3.700502 s`.
- WRAP publish: `4551` loads, `13653` parts, `8` workers,
  `32.312 s` total.
- Prefill completed in `57.913 s`.
- Server progress: token `50`, chunk and average decode both `0.08 t/s`,
  `590.099 s` decode.
- Model-cache load messages before stop: `71`, generally reporting about
  `5.3 GiB` cached per event.
- Runtime-monitor duration: `819.785 s`.
- Process read transfer at stop: `491,538,829,532 bytes`.
- Minimum Windows available memory: `2,117,402,624 bytes` (`1.972 GiB`).
- Peak working set: `40,515,010,560 bytes`.
- Peak private bytes: `45,181,939,712 bytes`.
- Page faults at final sample: `21,374,263`.
- Peak aggregate disk queue: `52`.
- Runtime contamination abort: not observed.
- Post-stop: no `ds4_server` remained; GPU returned to `0%` and `575 MiB`.

## Finding

`ArenaWrapTrimBetweenPhases` changed the outcome from a WRAP capacity abort to
a completed arena publication, but it is not an acceptable runtime solution.
Its process-wide `SetProcessWorkingSetSize(..., -1, -1)` call evicted useful
model working-set pages as well as consumed source pages. Decode then repeatedly
faulted/re-read multi-GiB model spans. The run therefore passed only the WRAP
capacity gate and failed the practical transport gate.

The secondary missing-route assertion after the operator stop is not a root
cause and carries no routing verdict: the request and harness were terminated
before normal completion.

## K60 Decision

The preregistered K60 64-token arm was not launched with the same process-wide
trim. The full-model arm had already crossed the explicit practical stop rule:
token 50 at 0.08 t/s with 491.54 GB process reads. Repeating that mechanism for
another long safety run would not test the required selective-source fix.

This does not claim that K60 would have identical throughput. It records only
that the common process-wide trim mechanism is rejected for the next composite.

## Next Implementation Gate

Implement selective, source-part-granular reclamation after a part has been
copied/checksummed and before final snapshot publication. It must not trim the
whole process working set. Add per-reclaim telemetry: phase, part/load cursor,
bytes consumed, duration, result/error, process working set, Windows available
memory, page faults and read-transfer bytes before/after. Then run an `n=1`
capacity/transport safety before any n>=3 benchmark.
