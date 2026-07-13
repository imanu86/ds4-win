# ds4 — native Windows port (register-mmap zero-copy)

Native-Windows (no WSL) build of ds4 that recovers RAM→VRAM H2D bandwidth for MoE
inference on consumer NVIDIA GPUs. Built on the Win32 platform layer from
[hawkli-1994/ds4-win](https://github.com/hawkli-1994/ds4-win) (`codex/windows-cuda`),
itself a port of [antirez/ds4](https://github.com/antirez/ds4).

## Why this fork exists

WSL2 throttles pinned H2D RAM→VRAM to ~3 GiB/s (GPU paravirtualization). Native
Windows hits **~24 GiB/s** (PCIe 4.0 x16) — an ~8× win that directly unblocks the
per-token expert streaming that dominates ds4 decode on a 12 GiB card.

The upstream `ds4-win` port **compiled but was never run with a real model**, and it
**hard-disabled** the register-mmap zero-copy path on Windows (falling back to pageable
chunked copies at ~11 GiB/s) — on the untested assumption that `cudaHostRegister` fails
on a `MapViewOfFile` view. **That assumption is wrong.**

## Measured (RTX 3060 12 GiB, driver 596.21, Windows 11)

`cuMemHostRegister(READ_ONLY|DEVICEMAP)` on a `MapViewOfFile(FILE_MAP_READ)` section
view **succeeds** and DMAs at **24.44 / 24.39 GiB/s** (512 MiB / 4 GiB), byte-exact.
The Win32 platform layer (file/mmap/thread) passes a native runtime smoke **12/12**
(64-bit `OffsetHigh` reads, 4.5 GiB mmap, 8-thread concurrent `pread`). See `tools/`.

## What this branch changes vs `ds4-win` @ 2fba7fe

`ds4_cuda.cu` (patch `0050win-register-mmap-enable`):
- **Enables the per-range `cudaHostRegister(Mapped|ReadOnly)` + `cudaHostGetDevicePointer`
  zero-copy path on Windows**, budget-gated (`cuda_host_register_budget_bytes()`,
  default 24 GiB on Win32, honoring `DS4_CUDA_STREAM_FROM_RAM_MASKED_BUDGET_GB`) so
  cumulative host registrations never exceed the WDDM ~24 GiB host-pin cap.
- **Fixes two load-blocking crashes**: the Windows model upload no longer `cudaMalloc`s
  the entire model (an 80 GiB model can't fit 12 GiB VRAM → was a startup abort), and an
  intentional env-skip of the chunked copy is no longer treated as fatal. The chunked
  copy is now opt-in (`DS4_CUDA_COPY_MODEL_CHUNKED`) and non-fatal, mirroring Linux, so
  the model loads and reaches the register-mmap / fd-streaming path.

**Deferred** (apply with a live compiler): guard `cuda_model_ptr` against returning a host
pointer as a device pointer on VRAM exhaustion; implement `os_mmap_warm` via
`PrefetchVirtualMemory`; a `FILE_FLAG_SEQUENTIAL_SCAN` handle for the streaming reads.

## Build (MSVC + CUDA 12.6, RTX 3060 = sm_86)

Prereqs: VS 2022 "Desktop development with C++" + CMake ≥3.24; CUDA Toolkit 12.6.x with
the "Visual Studio Integration" component.

```powershell
cmake -S . -B build -G "Visual Studio 17 2022" -A x64 -DDS4_CUDA_ARCHITECTURES=86
cmake --build build --config Release --parallel
```
If nvcc rejects a newer MSVC ("unsupported Microsoft Visual Studio version"), add
`-DCMAKE_CUDA_FLAGS="-allow-unsupported-compiler"` to the configure line.

Output: `build\Release\ds4_server.exe` (copy `cudart64_12.dll`, `cublas64_12.dll`,
`cublasLt64_12.dll` from `%CUDA_PATH%\bin` next to it).

## Status

- [x] Register-mmap mechanism validated on hardware (24.4 GiB/s) — `tools/mapviewoffile_register_probe_win.cpp`
- [x] Win32 platform layer runtime-smoke 12/12 — `tools/os_layer_test.c`
- [x] Register-mmap + load-fix patch authored (this branch)
- [ ] Native build (`ds4_server.exe`) — pending toolchain
- [ ] End-to-end model smoke (ds4-2bit.gguf) with measured t/s
- [ ] Deferred runtime fixes applied + compiled

Research record, bandwidth study, and per-finding verification live in the `reap-loop`
repo under `docs/PORT_WINDOWS_NATIVE/` and `runs/ds4/`.
