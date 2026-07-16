# G68 Selective Source-Mmap Reclaim Results

Date: 2026-07-16

## Verdict

`PARTIAL CAPACITY PASS / SAFETY FAIL`.

Selective `VirtualUnlock` released the measured `gate` and `up` source-mmap
working-set pages without an API failure. The full 30 GiB / 4551-slot G46 arena
nevertheless did not reach publication: the unchanged memory guard terminated
the server during the final `down` copy before token one.

This was one preregistered safety run. It is not a throughput or quality result.

## Frozen Run

- tag: `g68_source_unlock_g46safety`;
- implementation: `b1eacea`;
- protocol: `f9c49a4`;
- build input fingerprint:
  `d0a434ceb0acd49372ed028fe49b64d0660c08f09203db78ed970097165b72ee`;
- executable SHA-256:
  `4f3565c3778263baf164fb596ee4bdc3dba6315f9658833fcce5e1166ff38f84`;
- full model, context 8192, max eight tokens, temp 0, nothink;
- exact remaining G46 composition from the protocol.

Preflight available host memory was `38.71 GiB`; runtime `[arena-cap]` observed
`38.043 GiB` before allocation and created the complete `32,211,468,288`-byte,
`4551`-slot arena. Available memory immediately after the arena was `8.66 GiB`.

## Selective Reclaim Measurements

| Phase | parts | coalesced ranges | requested bytes | available before | available after | result |
|---|---:|---:|---:|---:|---:|---|
| gate | 4551 | 2395 | 9,852,203,008 | 68,747,264 B | 9,432,907,776 B | 2395 `ERROR_NOT_LOCKED`, 0 failures |
| up | 4551 | 2395 | 9,852,203,008 | 873,553,920 B | 10,421,305,344 B | 2395 `ERROR_NOT_LOCKED`, 0 failures |

The two calls took `1.392817 s` and `1.138859 s`. Process working set changed:

- gate: `30,274,732,032 -> 20,422,537,216` bytes;
- up: `34,879,746,048 -> 25,027,543,040` bytes.

The Win32 result matches the documented non-locked-page behavior used by the
protocol: `FALSE/ERROR_NOT_LOCKED` removed the pages from the process working
set. No process-wide trim was enabled.

## Final Failure

The `down` phase has no G68 reclaim point until after its complete copy. The
guard observed the following final samples:

| elapsed | available bytes | consecutive low samples | page faults | disk queue |
|---:|---:|---:|---:|---:|
| 64.928 s | 1,708,126,208 | 1 | 18,280,705 | 11 |
| 66.213 s | 240,553,984 | 2 | 18,903,166 | 9 |
| 67.510 s | 65,990,656 | 3 | 19,412,649 | 12 |

The third sample set `contamination_abort=true`. The HTTP request then failed
because the guarded server closed. WRAP did not publish, no route call and no
token completed; the later RouteNoDefaultSync harness error is secondary to the
intentional memory abort.

## Decision

The finding is positive but incomplete: selective source-page reclaim works and
preserves unrelated working-set pages, but a phase-level barrier is too late for
the 12,526,682,112-byte `down` phase under the measured host headroom.

The next isolated implementation must split source-sorted phase copies into
bounded waves and reclaim each completed wave only after all its workers join.
It must cover `gate`, `up` and `down`, preserve checksum order and keep the full
4551-slot arena. No bake, smaller arena or second performance lever is composed
into that test.

Artifacts:

- `g7_runs/g7_g68_source_unlock_g46safety_memory_preflight.json`;
- `g7_runs/g7_g68_source_unlock_g46safety_process_isolation_preflight.json`;
- `g7_runs/g7_g68_source_unlock_g46safety_runtime_telemetry.jsonl`;
- `g7_runs/g7_g68_source_unlock_g46safety_stderr.log`.
