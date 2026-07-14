# G17 native Windows dynamic arena allocator

Date: 2026-07-14
Branch: `port/windows-dynamic-arena-0051`

## Scope

This gate adds the disabled-by-default substrate for patch 0051:

- one contiguous `cudaHostAllocDefault` expert arena;
- whole-expert slots (`gate + up + down`, 6.75 MiB on ds4-2bit);
- active and staging binding tables with generation metadata;
- lifecycle ordering that drains CUDA before freeing pinned memory or unmapping
  the model;
- automatic exclusion of the old `cudaHostRegisterMapped` window whenever
  `DS4_CUDA_DYNAMIC_ARENA_GB` is enabled;
- small pinned staging resources allocated before the large arena.

The arena is not yet populated or consumed. No transport or mask performance
claim is made by this gate.

## Build

Release build completed with CUDA 12.6 and `sm_86`.

## Exactness and smoke A/B

Common command shape:

```powershell
powershell -File .\g7_measure.ps1 -MaxTokens 12 -Repeats 3 -Warmup `
  -BudgetGB 2 -ReserveMB 1024 -ModelPath C:\ds4-models\ds4-2bit.gguf
```

| Arm | Arena | Slots | Server decode t/s mean | Output |
|---|---:|---:|---:|---|
| `g17_allocator_off_hi12_n3` | off | 0 | 2.903 | exact across n=3 |
| `g17_allocator_1g_hi12_n3` | 1.00 GiB | 151 | 2.850 | exact across n=3 |

Both arms produced `Hello! How can I help you today?`. The small difference is
not treated as directional evidence on this short benchmark.

The enabled log reported:

```text
ds4: CUDA dynamic arena ready 1.00 GiB, 151 slots, 6.75 MiB/slot, available_ram=19.53 GiB
```

No `registered ... host window` line appeared in the arena arm.

## Remaining gates

1. Capacity/bandwidth sweep in fresh processes.
2. Transaction state machine and WRAP-copy into leased slots.
3. Generation-validated H2D arena hits in selected-load.
4. Atomic router-mask plus binding publication.
5. REAP/PACE policy and mass-pinned VRAM direct-use tier.
