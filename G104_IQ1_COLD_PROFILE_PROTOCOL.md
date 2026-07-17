# G104 IQ1_S Cold-Path Profile Protocol

G104 profiles the negative G103 candidate without changing its placement or
execution policy. The only runtime delta is `Iq1SProfile`.

## Frozen Configuration

- G73 arena30/4551, cache320, source-parts WRAP, composed prefill-mass
  tiering, static budget32, GPU-resident no-default-sync routes and SplitFused
- IQ1_S sidecar on C:, layers 3 through 42
- one cold IQ1_S expert per routed layer through the mixed GPU planner
- 0.5 GiB pinned IQ1 RAM cache
- promotion, open-router reserve, RoutePackedCopy, packed IQ1 H2D and IQ1
  VRAM cache disabled
- same 64-token cyberpunk prompt as G103

## Scope

This is one `structural-safety` process. It may measure profile counters but
cannot support a throughput, SOTA or quality claim. The runner must report:

- IQ1 SSD read calls and cumulative milliseconds
- H2D batches, copies, enqueue milliseconds, syncs and sync milliseconds
- mixed router D2H and metadata H2D milliseconds
- hot-IQ2 submit/sync, cold-IQ1 submit and join-submit milliseconds
- the G103 cache hit/miss and byte counters

The profile fails closed if any required counter is absent or inconsistent.
The result chooses the next single transport lever; it does not compose cache,
packed H2D, prefetch, promotion or SPEX in the same experiment.

## Measured Result

The structural profile completed on 2026-07-17 with result SHA-256
`18821f6579f34c3b595d3b8fb8f73e649a42449cbbdb3669598cb6b907c0d400`.
It reproduced the G103 placement exactly: 2,560 mixed calls, 178 cache hits,
2,382 misses and 10.904 GiB read from the IQ1 sidecar, with zero failures.

| Profile stage | Cumulative ms | Per relevant call |
| --- | ---: | ---: |
| SSD read | 6,595.827 | 2.7690 per miss |
| H2D enqueue | 6,805.673 | 2.6585 per mixed call |
| H2D sync | 561.803 | 0.2195 per mixed call |
| hot-IQ2 main submit | 12,957.775 | 5.0616 per mixed call |
| cold-IQ1 submit | 7,724.433 | 3.0174 per mixed call |
| router D2H | 7.794 | 0.003045 per mixed call |
| metadata H2D | 14.857 | 0.005804 per mixed call |
| join submit | 17.965 | 0.007018 per mixed call |

The three IQ1 tensors produced 7,680 H2D copies and 2,560 syncs. SSD read plus
H2D enqueue/sync accounts for 13,963.303 cumulative milliseconds. These timers
can overlap and profiling itself adds overhead, so they are stage attribution,
not an additive wall-clock model or a performance verdict.

The result rejects SSD-on-demand as the target placement. The next design gate
must allocate and preload all 10,240 routed IQ1 experts in one host-resident
arena: `4,915,200` bytes per slot, `46.875 GiB` total. This replaces the G73
30 GiB IQ2 host arena rather than being added to it. Packed IQ1 H2D remains a
separate subsequent lever because residency removes SSD reads but not the
7,680 copy submissions.
