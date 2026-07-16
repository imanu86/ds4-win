# G67 Adaptive Arena Reserve Results

Date: 2026-07-16

## Scope

This is an `n=1` full-model safety and transport result. It establishes that
the adaptive cap works and completes a request; it cannot support a performance
or quality verdict. The planned K60 arm was cancelled by explicit project
decision: sparse bakes are now a low-priority fallback and the main roadmap
continues on the full dynamic model.

## Full-Model Result

- Head: `9232851217dc87afaf13040543597a03e39cff7e`.
- Executable SHA-256:
  `4693d870b62a56b6c3f265e3825697e362310362d7e5821f1d190c55017592aa`.
- Build input fingerprint:
  `13ecb3b2f0d0eaeccf1141e44d7f1e673c77cbdd2bbb76d245e6d048095d5102`.
- Context `8192`, max tokens `8`, temperature zero, nothink.
- Requested arena: `29.999 GiB`; reserve: `22 GiB`.
- Available before arena allocation: `38.285 GiB`.
- Chosen arena: `17,482,383,360 bytes`, `2470` slots; cap applied.
- Minimum Windows available memory: `4,965,957,632 bytes` (`4.625 GiB`).
- WRAP: `2470` loads in `10.628 s`; publication succeeded.
- Prefill-mass candidate coverage: `0.3516`.
- TTFT/prefill: `34.665 s`.
- Server decode: `0.13 t/s`; eight tokens in `60.117 s` decode.
- Process read delta: `93,945,097,040 bytes` (`87.493 GiB`).
- Aggregate disk-read estimate: `100,163,529,435 bytes` (`93.285 GiB`).
- Route calls: `344`; default-sync calls: `0`; route errors: `0`.
- Snapshot backing misses: `0`; forbidden cold SSD-to-VRAM: `0`;
  tier SSD bytes: `0`; tier failures: `0`.
- Completion: `8` tokens, `finish_reason=length`, server exit `0`.
- Content SHA-256:
  `c7c8e02137fd31de53dc88a5645b3c6a92ab98d844e42ddcc00c52257d63823d`.

## Finding

The adaptive cap is a valid safety mechanism: it automatically reduced the
arena to the host state, preserved more than the requested runtime guard and
completed the request without SSD expert misses or contamination abort.

It is not a performance solution. With only 2470 slots, process/disk reads
exploded to roughly 94-100 GB for eight tokens and decode fell to 0.13 t/s.
This reproduces the central transport finding without a sparse bake: avoiding
expert SSD misses is insufficient when the runtime repeatedly reloads other
model spans and the resident arena is too narrow.

## Decision

- Keep the adaptive reserve as fail-closed safety infrastructure.
- Do not promote the 22 GiB point or the 2470-slot result.
- Do not run the K60 arm or further sparse-bake tuning in the current roadmap.
- Resume the full-model 0051 path: retain a wide pinned arena while reclaiming
  only consumed source-mmap expert ranges, then continue direct resident slots,
  hit/miss separation and dynamic tiering.
