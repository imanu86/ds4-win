# G65 WRAP Trim Capacity Protocol

Date: 2026-07-16

## Question

Can the already implemented `ArenaWrapTrimBetweenPhases` keep the exact G46
30 GiB/4551-slot WRAP below the unchanged Windows low-memory guard at context
8192, for either the full model or the K60 sparse bake?

## Scope

This is an `n=1` structural capacity and safety gate per arm. It cannot support
a throughput, TTFT, quality or G46-versus-K60 verdict. A successful arm only
means that it reaches and completes the 64-token request without allocation,
runtime-integrity or contamination failure.

## Frozen Arms

1. `g65_trim_g46safety`: `C:\ds4-models\ds4-2bit.gguf`.
2. `g65_trim_k60safety`: `C:\ds4-models\ds4-2bit-k60-mass-full-decode.gguf`.

Both arms use the complete G46 composition:

- context `8192`, max tokens `64`, temperature `0`, nothink;
- DynamicArena `30 GiB`, source-parts WRAP, trusted worker checksum;
- PrefillMassWrap and ComposePrefillMassTiering;
- expert cache `320`, LRU, reserve `0.125 GiB`;
- GPU-resident routes and RouteNoDefaultSync;
- mass-LFRU tiering: clock `430`, replacement budget `16`, minimum frequency
  `3`, hysteresis `1.25`;
- disabled Q8/F16 cache, embedded-row staging and eight REAP prefetch threads;
- memory cleanup/preflight, process isolation, quiescence and runtime
  contamination monitor unchanged.

G65 adds exactly one common mechanism:

- `ArenaWrapTrimBetweenPhases`, which invokes a process working-set trim after
  completed `gate` and `up` source-parts phases, before the following phase.

The K60 arm additionally uses only its required embedded-bake authorization:
`AllowEmbeddedBakeMask` and expected mask SHA-256
`5b6d98504ba830c1a50945a93d1a6017b1956bd17c56df8c0b1bdf92c1564e97`.

## Commands

The commands use `g7_measure.ps1` with identical arguments except model, tag
and the two K60 authorization switches. The fixed prompt is:

`Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document.`

Run order is full then K60. Do not overlap processes.

## Required Evidence

- preflight ready and no process-isolation conflict;
- runtime monitor enabled and memory guard unchanged;
- WRAP schedule/checksum/source-parts observed;
- trim requested and observed, with calls/success/failure/seconds recorded;
- if the request completes: non-empty output, server exit `0`, route calls
  positive, default-sync calls `0`, zero tier SSD bytes/backing misses/failures;
- K60 only: embedded mask/hash observed, sparse candidate replacement and
  request-end restore successful;
- if the request aborts: preserve stderr, launch/preflight provenance and the
  complete runtime telemetry; do not reinterpret a secondary route assertion
  as the root cause when no route completed.

## Decision

- If neither arm passes, implement finer-grained source-part trim before final
  snapshot publication, with per-trim memory and latency telemetry.
- If one or both pass, repeat only the passing composition at `n>=3` before any
  performance claim. Startup/TTFT remains contaminated by asymmetric source
  working-set state unless a separate symmetric cache protocol is registered.

