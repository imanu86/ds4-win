# G105 IQ1_S Full-Resident Structural Protocol

G105 is a preregistered `n=1` structural gate for the opt-in full-resident
IQ1_S host cache. It may prove residency, accounting and exactness only. It
must not be used for throughput, latency, SOTA or quality claims.

## Scope

- Harness: `g7_measure.ps1`
- Static test: `tests\test_g105_static_contract.ps1`
- Runner: `g105_iq1_full_resident.ps1`
- Static check must not require model files, build, GPU, DS4 launch, or host
  allocation.
- Runtime gate is one independent `GateKind structural-safety` process.

## Frozen Configuration

The candidate keeps the G103/G104 IQ1_S semantics while replacing on-demand
sidecar reads with full host residency:

- main model `C:\ds4-models\ds4-2bit.gguf`
- IQ1_S sidecar `C:\ds4-models\DeepSeek-V4-Flash-IQ1_S-XL.gguf`
- IQ1_S routed layers `3..42`
- 40 routed layers, 256 experts per layer, 10,240 resident entries
- one cold IQ1_S expert per routed layer through the mixed GPU planner
- `DS4_IQ1_S_RAM_CACHE_GB=46.875`
- `DS4_IQ1_S_RAM_CACHE_PAGEABLE=1`
- `DS4_IQ1_S_RAM_CACHE_PRELOAD_ALL=1`
- pageable Windows `VirtualAlloc`, not CUDA pinned memory and not mapped memory
- one-time preload is separate from decode accounting
- frozen-full policy after preload

The cache size is exact: `4,915,200` bytes per expert slot and
`50,331,648,000` bytes total (`46.875 GiB`).

## Required Invocation Shape

The structural process must use `g7_measure.ps1` with the IQ1 sidecar and:

- `-GateKind structural-safety`
- `-MinimumAvailableGiB 54`
- `-RuntimeMinimumAvailableGiB 1`
- `-Iq1SLayerFirst 3`
- `-Iq1SLayerLast 42`
- `-Iq1SMixedColdOne`
- `-Iq1SMixedGpuPlan`
- `-Iq1SRamCacheGiB 46.875`
- `-Iq1SRamCachePageable`
- `-Iq1SRamCachePreloadAll`
- `-ReuseVerifiedModelReceipt`
- `-ReuseVerifiedIq1SReceipt`

`MinimumAvailableGiB 54` is a hard preflight floor. The 1 GiB runtime floor
allows the intended 46.875 GiB allocation while still pairing low-memory
samples with disk-queue contamination detection. Any paging pressure, runtime
RAM contamination, or disk queue contamination invalidates the process.
The gate must not waive memory preflight, system quiescence preflight, process
isolation, runtime contamination sampling, model receipt validation, or sidecar
receipt validation.

## Forbidden Features

The G105 candidate must not enable:

- `Iq1Promotion`
- `ComposePrefillMassOpenRouter`
- `ComposePrefillMassReserveSlots`
- `RoutePackedCopy`
- `Iq1SPackedH2D`
- IQ1_S VRAM cache
- performance or quality aggregation

## Structural Gates

The candidate passes only if all required telemetry is present and consistent:

- IQ1_S sidecar and mixed runtime observed
- IQ1_S GPU planner requested and observed
- RAM-cache ready marker reports `pinned=0 pageable=1 mapped=0`
- policy is `frozen-full` and `preload_all=1`
- capacity `10240`
- count `10240`
- slot bytes `4915200`
- allocated bytes `50331648000`
- decode `ssd_bytes=0`
- misses `0`
- evictions `0`
- failures `0`
- `frozen=1`
- `preload_layers=40`
- `preload_entries=10240`
- `preload_read_calls=30720`
- `preload_ssd_bytes=50331648000`
- preload milliseconds greater than zero
- H2D bytes equal cache hits times slot bytes
- no forbidden direct cold SSD-to-VRAM path
- IQ2 tier backing `ssd_bytes=0`
- runtime contamination fields show no abort and no contamination reason

Preload counters are allowed to read the IQ1_S sidecar exactly once before
decode. Decode counters must remain SSD-clean: preload bytes do not count as
decode `iq1_s_ram_cache_ssd_bytes`.

## Exactness Gates

Candidate output must be non-empty, finished, runtime-clean, and exact. The
expected candidate content SHA-256 is the existing G103 IQ1_S semantic digest:

`4aaf0f0813f4cb15ac21a88f195f4f7d2c2af797e81524935e22eea60603c6b1`

The env-off control remains unchanged G74/G73 `static32_split_fused` exactness:

`31cbc6504dcb57d42aeff9dbceb3aed943bcb32dae19a2edbf552e9fd2f52eb8`

G105 does not compare timing or quality: no throughput claim and no quality
claim are allowed. A single structural candidate process can only say whether
the full-resident contract held.

## Env-Off Regression Guard

When `DS4_IQ1_S_RAM_CACHE_PAGEABLE`, `DS4_IQ1_S_RAM_CACHE_PRELOAD_ALL`, and
`DS4_IQ1_S_RAM_CACHE_GB` are absent or zero, the G74 route-packed-copy and G73
static32+SplitFused paths must remain byte-exact and must not emit IQ1_S
full-resident telemetry. Env-off behavior is a regression guard, not a G105
performance control.

## Failure Semantics

Any missing marker, counter mismatch, allocation failure, preload failure,
miss, eviction, decode SSD byte, nonzero failure counter, unexpected paging or
disk contamination, hash mismatch, or env-off G74 change fails the gate closed.
No partial pass may be reinterpreted as performance evidence.
