# G20: grow-only dynamic pinned arena

Date: 2026-07-14

## Question

Can the current-session pinned host arena grow after its initial W16 publication,
without evicting an already resident expert, while preserving exact output and
improving decode throughput?

This experiment changes residency only. It does not mask the router, deny an
expert, alter top-k, or apply a static domain mask. Misses remain legal and use
the normal selected-load path.

## Implementation

`DS4_CUDA_DYNAMIC_ARENA_GROW_INTERVAL=N` keeps observing unmasked router
selections after the initial window. Every N decode tokens it publishes the
grow-only union of:

- all entries already present in the active arena snapshot;
- newly observed entries whose current-session count reached `min_hits`.

No active entry is rotated or evicted. Publication is transactional. A failed
growth keeps the last valid snapshot and frees only unpublished staging slots.
`0` or an unset variable preserves the prior one-shot behavior.

## Protocol

Six independent server processes were run in order `OFF, ON, ON, OFF, OFF, ON`,
giving n=3 per arm. `-Repeats 3` in one process was deliberately not used,
because live KV reuse and an already published arena would contaminate later
replicas.

Common parameters:

| Parameter | Value |
|---|---:|
| Model | `C:\ds4-models\ds4-2bit.gguf` |
| Model bytes | 86,720,111,488 |
| GPU | RTX 3060 12 GiB, driver 596.21 |
| Decode | greedy server default, 64 tokens |
| Context / prefill chunk | 256 / 256 |
| Raw / compressed KV rows | 256 / 66 |
| Pinned arena allocation | 12 GiB, 1,820 slots |
| Initial observer | W16, min_hits=3 |
| Grow arm | interval 8 |
| Control arm | interval 0 |
| Masked RAM budget / CUDA reserve | 2 GiB / 1,024 MiB |
| WRAP workers | 8 |
| MoE I/O queue depth | 1 |
| Expert cache / SPEX / overlap | off / off / off |
| Expected output SHA-256 | `fd6c4522975a71e252b90199d49cfe3236310e2a7285dc0fc4d0e9d0e4885510` |

The runner clears every inherited `DS4_*` variable before applying this
configuration, records the complete effective environment and command line,
and fails closed if WDDM/NVIDIA telemetry, observed context, or exact output is
missing.

## Results

| Run | Arm | Decode t/s | TTFT s | Hit rate | Useful arena GiB | Occupancy | H2D GiB | WDDM shared peak GiB | Dedicated peak GiB | RAM available min GiB |
|---:|:---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | OFF | 2.09 | 13.841 | 34.34% | 2.894 | 24.12% | 28.00 | 12.328 | 9.953 | 33.402 |
| 2 | ON | 2.14 | 14.959 | 50.62% | 8.510 | 70.93% | 41.26 | 12.328 | 9.937 | 33.525 |
| 3 | ON | 2.02 | 14.570 | 50.62% | 8.510 | 70.93% | 41.26 | 12.328 | 10.093 | 33.300 |
| 4 | OFF | 1.87 | 15.752 | 34.34% | 2.894 | 24.12% | 28.00 | 12.328 | 9.953 | 33.018 |
| 5 | OFF | 1.97 | 15.275 | 34.34% | 2.894 | 24.12% | 28.00 | 12.328 | 9.953 | 33.005 |
| 6 | ON | 2.01 | 15.918 | 50.62% | 8.510 | 70.93% | 41.26 | 12.328 | 9.953 | 33.042 |

Decode medians:

- one-shot OFF: **1.97 t/s** (`2.09, 1.87, 1.97`);
- grow8 ON: **2.02 t/s** (`2.14, 2.02, 2.01`);
- observed median difference: **+2.5%**.

All six outputs had the required exact hash. Arena hit/miss counts were
deterministic within each arm: OFF `4,247 / 8,119`; ON `6,260 / 6,106`.

## Interpretation

The mechanism works and materially changes residency: useful pinned contents
grow from 2.89 to 8.51 GiB and hit rate rises by 16.28 percentage points. On this
short 64-token workload, however, the throughput effect is small relative to
run-to-run variance. Grow8 is therefore a valid positive candidate, not a claim
that the native Windows performance gap is solved.

The 12.328 GiB WDDM shared value is the allocated pinned arena, not its useful
occupancy. Actual useful occupancy must be read from the runtime publication
metadata above.

`uploaded` in the engine log was clarified as pinned-host-arena to compact-VRAM
H2D traffic. It is not SSD traffic. Win32 process transfer counters are retained
but explicitly marked as incomplete for mmap page-ins; no disk-I/O verdict is
made from them.

## Invalid intermediate result

Two earlier grow-off safety runs at `0.39-0.41 t/s` used executable SHA-256
`d11ac45980...`. The current source rebuilt as `75ae5a517...` gives `2.07 t/s`
in the same n=1 safety configuration and `1.97 t/s` median in the controlled
n=3 arm. Source reconstruction found no grow-off hot-path work capable of a 5x
regression. The old number is retained as a stale/intermediate-binary failure,
not used as a baseline or as evidence for growth.

## Artifacts

- Aggregate: `g7_runs/g7_g20_grow_ab_20260714_085148_aggregate.json`
- Per-run result JSON, raw runtime telemetry, memory preflight and stderr:
  `g7_runs/g7_g20_grow_ab_20260714_085148_{1..6}_*`
- Reproducible orchestrator: `g7_ab_dynamic_arena_grow.ps1`

## Next isolated levers

1. Verify a longer decode where growth reaches capacity; do not combine another
   lever in that run.
2. Sweep the separate Q8-F16 VRAM reserve with grow policy fixed, because the
   current run peaks near 9.95 GiB dedicated while the Q8 path keeps a 4 GiB
   default reserve.
3. Test prefill chunk and MoE I/O queue depth independently on long fresh prompts.
4. Add build-manifest validation so an executable/source mismatch fails closed.
