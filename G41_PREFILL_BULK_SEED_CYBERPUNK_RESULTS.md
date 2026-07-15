# G41 Cyberpunk Prefill-Mass Bulk Seed

Date: 2026-07-15
Host: native Windows, RTX 3060 12 GiB, 64 GiB RAM
Branch: `port/windows-dynamic-arena-0051`

## Question

Does one request-scoped prefill-mass WRAP into a large pinned-RAM arena reduce
the cyberpunk prompt's decode misses and improve decode enough to justify the
fully charged publication cost?

This gate isolates bulk seed transport. Expert cache, mass/LFRU, REAP mask and
SPEX are off because the current runtime intentionally forbids them from
co-owning a published arena snapshot.

## Protocol

Runner: `g41_prefill_bulk_seed_cyberpunk_ab.ps1`.

| Parameter | Value |
|---|---|
| Model | `C:\ds4-models\ds4-2bit.gguf` |
| Prompt | G39/G40 43-token cyberpunk single-file HTML request |
| Context / generation | 256 / max 12, greedy no-think server path |
| Expected hash | `921a62bdb39d9d07161326274fcbc0070f3c4b9e75153d27b1b6dc96811f6e88` |
| Prefill | production full chunk plus unbiased prefill-mass observation |
| Dynamic arena | 30 GiB pinned host RAM, 4,551 expert slots |
| Streaming | 2 GiB budget, 1024 MiB load reserve, 128 MiB runtime reserve |
| Other toggles | Q8-F16 off, embedding-row staging on, I/O QD 1, 8 WRAP workers |
| Repetition | three independent one-request processes per arm, no warmup |

Arms:

- `observe`: collect the same prefill mass, allocate the same arena, publish
  nothing;
- `wrap`: rank the same unbiased mass and publish the complete candidate once
  before decode. Router remains `unbiased` and mask remains `off`.

Counter-order:

`observe A -> WRAP A -> WRAP B -> observe B -> observe C -> WRAP C`

The harness requires one request and no warmup for first-snapshot WRAP. The
`n=3` requirement is therefore satisfied by three independent processes per
arm, not by three requests sharing one snapshot. All six outputs matched the
expected hash.

## Capacity Note

The first attempted 31 GiB control failed closed before measurement:
`cudaHostAlloc` reported out of memory after the complete DS4 process had
already prepared 9.62 GiB of CUDA startup cache. A bare G17 allocator probe had
previously succeeded at 31 GiB only by leaving about 5 MiB physical RAM free.
The complete runtime has prior pinned allocations, so G41 uses the previously
measured stable 30 GiB process-level capacity. The failed attempt is not part of
either arm's aggregate.

## Results

| Metric | Observe | Bulk WRAP | Delta |
|---|---:|---:|---:|
| TTFT | 20.489 s | 44.710 s | +24.220 s |
| WRAP publication | 0 s | 24.657 s | +24.657 s |
| Server decode | 1.48 t/s | 2.31 t/s | +56.08% |
| Client throughput, 12-token run | 0.4139 t/s | 0.2386 t/s | -42.36% |
| Process reads | 51.433 GiB | 36.943 GiB | -28.17% |
| Shared-memory peak | 30.332 GiB | 30.332 GiB | flat |
| Minimum available RAM | 18.950 GiB | 3.454 GiB | -15.496 GiB |

The 43-token prompt selected 2,657 unique `(layer, expert)` entries. All 2,657
fit in the 4,551-slot arena, covered 100% of observed prefill gate mass and were
published in every WRAP replication. Candidate membership covered 84.83% of
selected decode IDs. Runtime arena accounting was deterministic at 2,443 hits
and 653 misses, a 78.91% hit rate, with 16.10 GiB RAM-to-GPU traffic and zero
fatal errors.

Individual decode rates were 1.52, 1.46 and 1.46 t/s for observe, versus 2.33,
2.32 and 2.28 t/s for WRAP. Publication times were 25.945, 23.297 and 24.730
seconds.

## Verdict

The pay-once transport hypothesis passes its isolated mechanism gate: the
prefill-derived set is deterministic, exact, fits pinned RAM, covers most decode
routes, raises decode 56.08% and reduces charged process reads 28.17%.

It does not pass end-to-end on a 12-token decode because publication doubles
TTFT. At the measured mean rates, simple arithmetic projects a break-even near
100 generated tokens; this is explicitly not a measured break-even result. A
long decode must measure it directly.

The next code gate is arena co-ownership: keep the immutable prefill snapshot as
the RAM backing store, let the 336-slot cache plus mass/LFRU manage only VRAM
protection, and forbid a cold SSD entry from promoting directly to VRAM. The
existing guardrails must not simply be deleted; they must be replaced by these
ownership invariants and corresponding fail-closed telemetry.

## Provenance

- measured HEAD: `6298b66`;
- executable SHA-256:
  `4a390be7a8e490ef70d14b4f316b7efe04dd9ecd00e09e096eed556d317e49b1`;
- CUDA source SHA-256:
  `863b26ac3538492bef1b0f38c2f7fe36f7600632a4dfdfad3768f8fc124e014d`;
- build-input fingerprint:
  `3a6dd4c946c03229b455811cc7c9bf49fc5ee3f172ace91da07e76237c618d59`;
- build manifest SHA-256:
  `e5f3f6512294b927e7c98a59cf97f08f6d15bf8bb69d91775d38e8f9dc0c2d62`;
- harness SHA-256:
  `4f951488e1a83a595b5f85829e578c2d3626600d11c1f5a7fe422823c39d52f2`;
- runner SHA-256:
  `408d945173fe6598f1bf391e2500f35ed95b54e4b16f68eb2a1046cc84245084`;
- matrix SHA-256:
  `7c389f9f73ea442bc9a5020b6b977e71919b2f6e2f4e5a68d257c3aaa5eeefad`.

Raw local artifact: `g7_runs/g41_prefill_bulk_seed_cyberpunk_ab_result.json`.
