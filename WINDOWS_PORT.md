# ds4 native Windows port

Native Windows, no WSL, CUDA port of ds4 for the RTX 3060 12 GiB and a 64 GiB
host. The working branch is `port/windows-dynamic-arena-0051`.

## Current measured architecture

- Win32 file, mmap, and thread platform layer from `hawkli-1994/ds4-win`.
- Selected expert loading into one preallocated compact device slab. The old
  per-miss `cudaMalloc` path is gone.
- Event-based device stream-pool retirement and bounded expert-cache experiments.
- Functional hidden-state SPEX scoring, top-K, ring, and K1 prefetch experiments.
- One large `cudaHostAllocDefault` dynamic arena. It is pinned but is not
  device-mapped and therefore does not consume proportional VRAM.
- Transactional arena updates: `begin -> WRAP -> finish -> publish/abort`.
  Published bindings remain valid until a complete replacement is ready.
- Direct H2D from arena hits into the compact selected-expert buffer, with model,
  layer, expert, offset, geometry, generation, and checksum validation.
- Opt-in exact tiering with `DS4_EXPERT_TIERING=enforce`: first cold touch ends
  in pinned RAM and uses transient GPU staging; persistent VRAM admission starts
  only on reuse, and VRAM eviction retains a warm RAM copy.

The earlier mapped-register window is not the production path on this 12 GiB
card. It consumed proportional VRAM, displaced reusable hot weights, and reduced
decode throughput. The dynamic arena deliberately uses `cudaHostAllocDefault`
without `Mapped` or `cudaHostGetDevicePointer`.

## Measured status

The final G18 correctness fixture used a 1 GiB arena and one retained expert per
layer. It produced the explicit expected greedy output hash on three repeats,
validated non-destructive abort, and measured 2.706667 t/s mean decode. This is a
transport/lifetime proof, not a residency-policy performance verdict.

The standalone G17 capacity probe measured successful pinned allocations from
16 through 31 GiB and 20.75-24.46 GiB/s H2D. A clean post-restart control then
measured 31 GiB pass 3/3 and 32 GiB fail 3/3 with about 55 GiB available. Every
successful `cudaFreeHost` returned available memory to its pre-allocation band.
Consequently:

- this native Windows/WDDM host has a reproducible single-allocation boundary
  between 31 and 32 GiB, independent of ordinary available-RAM pressure;
- segmented controls passed `2 x 15 GiB` 3/3 but failed `2 x 25 GiB` 3/3 on
  the second allocation, establishing that the measured pin budget is global;
- the data does not prove a CUDA or NVIDIA memory-retention leak;
- a 50 GiB pinned arena is not available on this 64 GiB host; the runtime design
  must use a <=31 GiB pinned tier plus pageable cold storage.

See `G17_PINNED_ARENA_CAPACITY_RESULTS.md` and
`G18_DYNAMIC_ARENA_WRAP_RESULTS.md` for commands, caveats, and raw-result names.

G35 is the first exact positive physical-tiering checkpoint. With the same
8 GiB arena allocated in both arms, cache336 LRU and one discarded warmup plus
three measured requests, server decode increased from 3.228333 to 4.975000 t/s
(+54.10%). All outputs and warmups matched the expected greedy hash. Enforcement
recorded 1,005 cold-to-RAM transitions, zero cold-to-VRAM transitions and zero
runtime failures. The initial fill cost increased by about 7.18 seconds; the
next gate is slower mass/LFRU promotion with hysteresis to reduce the observed
4,299 promotions and 3,963 demotions. See
`G35_REAL_EXPERT_TIERING_RESULTS.md`.

## 0051 remaining work

G19 connects a session-learned W16/K23 mechanism gate to the G18 transaction.
The policy must observe all 256 unbiased router scores, construct an immutable
candidate, WRAP every entrant, prepare the matching router-bias rows, and publish
arena bindings plus mask as one generation. It must never publish a mask before
its experts are ready and must never narrow K to fit capacity.

K23 is only the integration fixture. The production direction remains a dynamic,
current-interaction policy with a wider target, not a static domain mask and not
a prompt-trained mask. See `G19_0051_POLICY_INTEGRATION_PLAN.md`.

Follow-on measured gates are:

1. Replace G35 second-touch promotion with mass/LFRU admission at a slow clock
   and hysteresis, without weakening the cold-to-RAM invariant.
2. Chunked, preemptible gate/up/down WRAP so confirmed entrants can preempt
   speculative traffic.
3. Parallel transfer streams where the trace proves serialization remains.
4. A separately gated hybrid CPU/GPU cold-expert fallback. External systems make
   this promising, but it is not yet a result on this engine or machine.

## Build

```powershell
$env:CUDA_PATH = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.6"
$env:PATH = "$env:CUDA_PATH\bin;$env:PATH"
$cmake = "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
& $cmake --build build --config Release --parallel
```

The standard harness is `g7_measure.ps1`. Memory preflight is enabled by default;
it shuts down WSL, refuses a concurrent `ds4_server`, records host-memory state,
and enforces an automatic arena-plus-2-GiB available-RAM guard. The standalone
capacity probe applies the same reserve to every requested size. Performance
verdicts require at least three repeats and an explicit expected output hash when
one is available.
