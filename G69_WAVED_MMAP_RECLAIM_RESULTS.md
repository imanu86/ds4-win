# G69 Waved Source-Mmap Reclaim Results

Date: 2026-07-16

## Verdict

`STRUCTURAL AND CAPACITY SAFETY PASS / PERFORMANCE NOT PROMOTED`.

The full-model G46 composition allocated and published its complete 30 GiB,
4551-slot arena at context 8192. Bounded source-copy waves completed all three
expert tensor phases without crossing their 4 GiB page-aligned cap or triggering
the memory guard.

This was one preregistered eight-token safety run. Its timing is diagnostic only.

## Frozen Run

- tag: `g69_wave4_g46safety`;
- implementation: `be6f1fe`;
- protocol: `3a835fd`;
- build input fingerprint:
  `ec0b8f38798869d93007809752eae9262d2cb79a75704452fe0e7add7fdc9af1`;
- executable SHA-256:
  `9bbcbc57714611bd3873beedc7fc4f0829ee463e0499793b86295eb085cca501`;
- full model, context 8192, max 8 tokens, temp 0, nothink;
- fixed arena 30 GiB / 4551 slots and exact remaining G46 composition;
- source unlock wave cap 4.0 GiB.

Preflight available host memory was `37.44 GiB`. Runtime observed only
`36.493 GiB` before allocating the full arena and `6.74 GiB` immediately after,
making this a stricter host-memory state than G68.

## Wave Measurements

| Phase | waves | max page-aligned wave | parts | ranges | total reclaimed | unlock time |
|---|---:|---:|---:|---:|---:|---:|
| gate | 3 | 4,293,894,144 B | 4551 | 2395 | 9,852,203,008 B | 1.107160 s |
| up | 3 | 4,293,894,144 B | 4551 | 2395 | 9,852,203,008 B | 0.903053 s |
| down | 3 | 4,293,083,136 B | 4551 | 2397 | 12,536,500,224 B | 1.437156 s |

Summary: 3 phases, 9 waves, 7187 coalesced ranges,
`32,240,906,240` requested bytes, `3.447369 s`, zero failures. All 7187 calls
returned the documented `ERROR_NOT_LOCKED` working-set release path. Maximum
wave size stayed `1,073,152` bytes below the frozen 4 GiB cap.

WRAP published all 4551 loads in `29.089 s` (`29.077 s` source-copy time).
The minimum host memory recorded by runtime telemetry was `2,776,780,800` bytes,
above the unchanged 2 GiB guard.

## Structural Gates

- HTTP request and process exit: pass;
- deterministic non-empty eight-token output:
  `c7c8e02137fd31de53dc88a5645b3c6a92ab98d844e42ddcc00c52257d63823d`;
- GPU-resident route calls: `344`;
- default-sync calls: `0`; no-default-sync calls: `344`;
- snapshot backing misses: `0`;
- tier SSD bytes: `0`;
- tier failures: `0`;
- contamination abort: false.

## Diagnostic Timing

- TTFT: `55.559 s`;
- server decode: `0.13 t/s`;
- client eight-token time: `117.000034 s` (`0.068376 t/s`);
- pinned-RAM route hits: `1692`; VRAM route hits: `372`;
- pinned-RAM H2D: `11,975,786,496` bytes;
- Win32 process-read delta: `93,810,879,312` bytes (`87.368 GiB`);
- aggregate disk-read estimate: `126,863,577,647` bytes (`118.151 GiB`);
- peak disk queue: `23`.

The capacity mechanism therefore works, but this long safety run still had too
little post-arena headroom to preserve the non-expert hot working set. It does
not establish that wave reclaim is slower or faster than G46: there is no n>=3
same-workload baseline in the current host-memory state.

## Decision

Wave reclaim is eligible for an interleaved `n>=3` exact A/B on the original
G46 context-256, 64-token workload. That comparison must record preflight host
memory for every independent process. If the legacy no-unlock arm cannot pass
the unchanged memory guard from the current host state, do not fabricate a
timing comparison; record the capacity asymmetry and either restore comparable
headroom or run candidate-only exactness without a SOTA claim.

The next performance target remains the measured G46 transport cost: 10,859
pinned-RAM routes and 71.58 GiB repeated H2D over 64 tokens, followed by direct
resident slots, hit/miss separation and dynamic REAP tiering.

Primary artifacts:

- `g7_runs/g7_g69_wave4_g46safety_result.json`;
- `g7_runs/g7_g69_wave4_g46safety_raw_outputs.json`;
- `g7_runs/g7_g69_wave4_g46safety_runtime_telemetry.jsonl`;
- `g7_runs/g7_g69_wave4_g46safety_memory_preflight.json`;
- `g7_runs/g7_g69_wave4_g46safety_process_isolation_preflight.json`;
- `g7_runs/g7_g69_wave4_g46safety_system_quiescence_preflight.json`;
- `g7_runs/g7_g69_wave4_g46safety_stderr.log`;
- `g7_runs/g7_g69_wave4_g46safety_stdout.log`.
