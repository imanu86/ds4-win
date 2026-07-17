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
