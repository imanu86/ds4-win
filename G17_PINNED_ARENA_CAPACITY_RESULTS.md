# G17 pinned arena capacity results

## Scope

`g17_arena_probe.cu` measures a fresh-process `cudaHostAllocDefault` allocation,
page touch, chunked H2D bandwidth, `cudaFreeHost`, and CUDA VRAM before and after.
It does not use `Mapped`, `cudaHostGetDevicePointer`, the ds4 model, or a static
expert mask.

The first sweep was run before the mandatory memory preflight existed. A later
pre-restart snapshot records the long-lived host state, but the probe JSONL alone
does not attribute the 31/32 GiB boundary to that state.

## Observations

| Arena | Result | H2D GiB/s | Available before | Available after free |
|---:|:---:|---:|---:|---:|
| 16 GiB | pass | 24.46 | 22.81 GiB | 23.88 GiB |
| 20 GiB | pass | 24.44 | 23.98 GiB | 24.19 GiB |
| 24 GiB | pass | 24.35 | 24.35 GiB | 25.38 GiB |
| 28 GiB | pass | 20.75 | 25.79 GiB | 31.48 GiB |
| 29 GiB | pass | 24.44 | 30.21 GiB | 30.23 GiB |
| 30 GiB | pass | 24.41 | 30.29 GiB | 30.70 GiB |
| 31 GiB | pass | 24.44 | 30.81 GiB | 31.62 GiB |
| 32 GiB | fail | n/a | 30.89 GiB | 30.74 GiB |
| 36 GiB | fail | n/a | 30.84 GiB | 30.77 GiB |

The host allocation did not reduce CUDA free VRAM. The temporary device buffer
did, as expected. Every successful run recovered physical availability to at
least the pre-allocation value after `cudaFreeHost`.

Raw local records:

- `g7_runs/g17_arena_probe_16_28_20260714_052019.jsonl`
- `g7_runs/g17_arena_probe_29_31_20260714_052231.jsonl`
- `g7_runs/g17_arena_probe_32_36_20260714_052136.jsonl`

These raw local files intentionally remain untracked; this document records their
measured table in the repository.

## Interpretation limits

The measured data supports three statements only:

1. `cudaHostAllocDefault` can pin at least 31 GiB on this native Windows host.
2. There is no measured proportional VRAM tax from that host allocation.
3. The 32 GiB failure coincided with less than 32 GiB of available RAM.

It does not establish a 31 GiB Windows/WDDM ceiling and does not show retained
pinned physical memory after `cudaFreeHost`.

`G17_WINDOWS_MEMORY_SNAPSHOT_20260714.json` is the committed pre-restart
preflight artifact for uptime, available/committed memory, standby, allocated and
resident pool, and process totals. A separate non-elevated pool-tag query was
partial and was not captured by the G17 probe, so this report makes no ownership
claim. Restart is the only dependable clean reset for the next capacity
certification.

That artifact measured 137.24 hours uptime, 27.63 GiB available, 63.01/124.88
GiB committed, 25.81 GiB free/zero, 1.82 GiB standby, 12.60 GiB allocated paged
pool of which 2.73 GiB was resident, 1.78 GiB nonpaged pool, 7.80 GiB summed
process working sets, and 21.04 GiB summed process private memory. The mandatory
`wsl --shutdown` completed and available RAM remained 27.63 GiB at the recorded
precision.

## Slot budget

One expert slot is 6.75 MiB. For the 40 maskable routed layers:

| Target | Experts | Payload | With 80 entrant spare slots |
|---:|---:|---:|---:|
| K23 | 920 | 6.06 GiB | 6.59 GiB |
| K50 | 2,000 | 13.18 GiB | 13.71 GiB |
| K96 | 3,840 | 25.31 GiB | 25.84 GiB |
| K154 | 6,160 | 40.61 GiB | 41.13 GiB |
| K176 | 7,040 | 46.41 GiB | 46.93 GiB |
| K256 | 10,240 | 67.50 GiB | 68.03 GiB |

A clean 50 GiB arena would therefore cover K154 plus substantial transactional
headroom, or K176 with less spare capacity. The three hash layers remain on the
fallback path in the G19 design.

## Clean certification protocol

1. Use Windows Restart, not hibernate or Fast Startup shutdown.
2. After login, wait at least 60 seconds without starting GPU-heavy applications.
3. Record preflight counters before any large CUDA allocation.
4. Run one arena size per fresh process; record immediate, +60 s, and +5 min state.
5. Stop if memory does not return to its pre-run band.
6. Run performance A/B arms before destructive capacity sweeps.

The first clean target is 50 GiB. It is pending a restart and must not be claimed
from the current sweep.

After the clean arena measurement, run a separate WSL retention control:

1. Record a stable Windows-only baseline before WSL has started.
2. Start one WSL distribution without ds4 and record the same counters.
3. Run `wsl --shutdown` and sample immediately, after 60 seconds, and after five
   minutes.
4. Compare available memory, pool sizes, and pool tags with the original band.

The current observation that both distributions were stopped and another
`wsl --shutdown` did not reclaim memory is insufficient to prove or disprove an
earlier WSL shutdown leak.
