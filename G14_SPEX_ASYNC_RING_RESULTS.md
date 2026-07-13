# G14: SPEX async readback ring

Date: 2026-07-13

Parent: `9cbdf97` (`experiment: port SPEX hidden dry-run to native Windows`)

## Question

Can a multi-slot, nonblocking D2H handoff remove the decode-thread wait added by
the G13 SPEX hidden dry-run without changing routing or output?

## Implementation

- Added a configurable pinned-host readback ring (`DS4_SPEX_RING_SLOTS=1|2|4|8`).
- Allocated one device top-K tensor per ring slot so a later layer cannot overwrite
  IDs while an earlier D2H is still pending.
- Kept the one-slot path as the G13 blocking control.
- For rings larger than one, the decode thread only queries readiness. A late
  prediction is dropped and counted; decode never waits for it.
- Added `ring`, `late`, `ring_full`, and `stale` counters to final telemetry and
  the PowerShell result JSON.
- Added an ordered variant that queues the 24-byte K6 D2H and completion event on
  CUDA stream 0. This removes the separate dependency event and
  `cudaStreamWaitEvent` used by the original multi-stream attempt.
- Teardown waits for every pending completion event before freeing pinned slots.

The experiment remains dry-run only. Predicted IDs never change router scores,
selected experts, masks, cache policy, or model weights.

## Protocol

Hardware: RTX 3060 12 GB, native Windows/WDDM, CUDA 12.6.

Model: `C:\ds4-models\ds4-2bit.gguf`, 86,720,111,488 bytes.

SPEX artifact: `ds4flash_d2_nextlayer.spex`, SHA-256
`a86288c3a29be97179230a3ed86eebdcd7293ab33987ed7aa57850213325f3c7`.

Common runner arguments:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\g7_measure.ps1 `
  -MaxTokens 12 -Repeats 3 -BudgetGB 2 -ReserveMB 1024 -Warmup `
  -ExpectedContentSHA256 fda564ba3f7a0f028106d468420f674898ed99ac5bf2765ac9586206e39d73c5 `
  -ModelPath C:\ds4-models\ds4-2bit.gguf
```

SPEX variants also used:

```powershell
-SpexDryRun `
-SpexFile C:\Users\imanu\source\repos\moe-aggressive-commit\runs\spex\spex_model\ds4flash_d2_nextlayer.spex `
-SpexCap 6 -SpexStage full -SpexStatsEvery 1000000 `
-SpexRingSlots <1|4>
```

The server was restarted for each configuration. Each server received one
discarded warmup request followed by three measured requests. The prompt was
`Hi`, greedy/nothink behavior came from the server defaults used by the same
harness, and every measured output was exactly:

```text
Hello! How can I help you today?
```

All output hashes were identical:
`fda564ba3f7a0f028106d468420f674898ed99ac5bf2765ac9586206e39d73c5`.

## Results

The server-reported decode rate is the primary metric.

| Final gate variant | Decode t/s mean | Min-max | Compared layers | Ready-subset recall@6 | Coverage | Late | Ring full |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| SPEX off | 2.887 | 2.86-2.93 | 0 | n/a | n/a | 0 | 0 |
| SPEX full, ring 1 blocking | 2.827 | 2.75-2.88 | 1512 | 0.3078 | 100% | 0 | 0 |
| SPEX full, ring 4 ordered | 2.807 | 2.79-2.82 | 1476 | 0.3144 | 97.6% | 36 | 0 |

Relative to SPEX off in the final gate matrix, ring 1 was 2.1% slower and ring
4 was 2.8% slower. These are `n=3` descriptive measurements over short
completions, not a claim of statistical significance.

Ring-4 recall is explicitly scoped to the 97.6% of predictions that arrived in
time. No value is imputed for late predictions, so it must not be reported as
full-layer recall.

Two earlier `n=3` development matrices are retained because they show that the
ring1/ring4 ordering is not stable at this run length:

| Matrix | SPEX off | Ring 1 | Ring 4 | Ring 4 vs off |
| --- | ---: | ---: | ---: | ---: |
| Separate D2H stream and dependency events | 2.907 | 2.840 | 2.793 | -3.9% |
| Ordered stream-0 D2H, before teardown-only fix | 2.980 | 2.817 | 2.733 | -8.3% |
| Ordered stream-0 D2H, teardown-only fix | 2.877 | 2.653 | 2.773 | -3.6% |
| Failure-path and baseline-hash gate | 2.837 | 2.840 | 2.777 | -2.1% |
| Final strict completeness/coverage gate | 2.887 | 2.827 | 2.807 | -2.8% |

Both ring-4 safety runs (`n=1`, excluded from the performance verdict) produced
the same output, scheduled 756 predictions, consumed 738, dropped 18 late, and
had zero ring-full events.

## Verdict

The ring is correct enough for a nonblocking experimental handoff, but none of
the three measured matrices recovers SPEX-off throughput on this Windows/WDDM
setup. Removing the explicit CPU wait is insufficient: a per-layer 24-byte D2H
plus event still adds GPU/driver work, and ordering it on stream 0 can serialize
the decode stream. The short-run data does not establish whether ring 1 or ring
4 is intrinsically faster.

Do not claim this as a speedup. Keep it as an opt-in diagnostic primitive and do
not enable it by default.

## Next experiment

The next functional milestone is a dedicated keyed prefetch worker. It must:

1. carry `epoch`, token/decode sequence, source layer, and target layer;
2. own its file handle, pinned staging, CUDA stream, and destination slab;
3. never wait on the decode thread;
4. expose a prefetched expert only when the runtime-selected ID and key match;
5. fall back immediately to the existing selected-load path on miss, late work,
   stale work, ring pressure, or any SPEX failure;
6. leave router scores and masks unchanged until exactness and `n>=3` performance
   gates pass.

All G14 result JSON files committed with this report are the authoritative
provenance records for the two safety runs and all three `n=3` matrices.
