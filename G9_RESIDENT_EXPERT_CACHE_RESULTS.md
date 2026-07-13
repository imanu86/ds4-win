# G9 native-Windows resident expert cache experiment

Date: 2026-07-13

## Scope

This experiment adds an opt-in exact-byte LRU cache for routed experts behind
the existing compact selected-load path. It does not change router scores,
selected expert IDs, quantization, REAP-LOOP, SPEX, or PACE.

Configuration:

- `DS4_CUDA_STREAMING_EXPERT_CACHE_N`: requested resident slots; unset/zero disables.
- `DS4_CUDA_STREAMING_EXPERT_CACHE_RESERVE_GB`: free-VRAM floor, default 0.5 GiB.
- `DS4_CUDA_MOE_CACHE_STATS=1`: low-rate diagnostic counters; disabled in timing arms.

Each DeepSeek-V4 expert occupies 6.75 MiB in this GGUF: 2.0625 MiB gate,
2.0625 MiB up, and 2.625 MiB down. Slots hold the native quantized bytes.
Hits copy exact bytes device-to-device into the existing compact gather. Misses
are admitted through the existing pinned staging/upload stream. A slot becomes
valid only after the upload stream synchronizes successfully.

Measured source and binary:

- `ds4_cuda.cu`: `e776535557f89e9ee5da019be6f81ea75a8fac5bcfd1cb77caaa68f8326026c6`
- `ds4_server.exe`: `e326de3c8b2c3497a846778194cee83bda12bd5cb1351987e37bceda6f7ea982`
- `g7_measure.ps1`: `583fc339cf5cc078c6839f18065d666680a6f6c526ce56f3b46a5fb54105c552`

## Protocol

- RTX 3060 12 GB, native Windows CUDA 12.6, WDDM.
- Model `C:\ds4-models\ds4-2bit.gguf`.
- Prompt `Hi`, temperature 0, thinking disabled, max 12 tokens.
- Same binary and launch configuration for every arm.
- One discarded identical warmup followed by three measured requests.
- Clean timing: cache statistics and other verbose diagnostics disabled.
- Correctness: API token count plus full UTF-8 output SHA-256.

## Timing result

| requested slots | actual slots | n | end-to-end t/s mean | min-max | server decode t/s | output |
|---:|---:|---:|---:|---:|---:|---|
| 0 | 0 | 3 | 2.092 | 2.024-2.145 | 2.91 | identical |
| 32 | 32 | 3 | 2.034 | 2.005-2.060 | 2.83 | identical |
| 64 | 64 | 3 | 2.009 | 1.998-2.022 | 2.78 | identical |
| 96 | 76 | 3 | 1.908 | 1.773-2.065 | 2.65 | identical |

All arms produced `Hello! How can I help you today?` with SHA-256
`fda564ba3f7a0f028106d468420f674898ed99ac5bf2765ac9586206e39d73c5`.

## Mechanism measurement

Two separate one-repeat safety/diagnostic runs enabled cache counters. They are
not used as performance verdicts:

| requested/actual slots | lookup hits | misses | evictions | direct overflow |
|---:|---:|---:|---:|---:|
| 32/32 | 0 | 5,782 | 5,750 | 0 |
| 96/76 | 0 | 5,782 | 5,706 | 0 |

The cache is bit-correct, but a global LRU of at most 76 slots cannot retain an
expert identity across a full traversal of the model layers. Every lookup is a
miss, so the experiment pays an additional cache-to-compact D2D copy without
avoiding any host-to-device load. This measured zero-hit behavior explains the
monotonic timing regression; it is not a quality failure.

## Decision

Keep the implementation opt-in as a measured negative baseline. Do not enable
global LRU in the default recipe on the 12 GB card.

The next variant must make a small cache survive the layer traversal. The
planned arm partitions residency by layer, retains only a small hot lane per
layer, chooses admission from current router weight/mass, and streams all other
misses directly to compact so they do not pay the extra D2D copy. This changes
residency only and remains independent of REAP/SPEX selection.

