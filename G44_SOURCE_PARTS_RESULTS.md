# G44 Source-Ordered WRAP Results

Date: 2026-07-15
Host: native Windows, RTX 3060 12 GiB, 64 GiB RAM
Branch: `port/windows-dynamic-arena-0051`

## Question

Can the first request-scoped 30 GiB arena publication become faster and less
sensitive to Windows `mmap` page-fault state by copying expert tensor parts in
global source-offset order, while preserving the exact full-slot checksum,
output, routing and storage tiering?

## Implementation

The G43 control schedules one complete expert at a time. Each worker copies the
expert's gate, up and down tensors and then hashes the complete destination
slot. Even though loads are ordered by their gate offset, each worker jumps
between three distant source regions for every expert.

G44 adds the opt-in environment variable:

`DS4_CUDA_ARENA_WRAP_SCHEDULE=source-parts`

It creates three descriptors for every load, globally sorts them by model-file
offset, and copies them in three barriered phases: gate, then up, then down.
Each worker continues the same FNV-1a state after copying its part. The phase
barriers guarantee one writer per expert checksum and preserve the exact FNV of
the canonical contiguous slot (`gate || up || down`) without a cold reread.

The default remains `expert-major`. Invalid schedule values fall back to the
default with a warning. The non-trusted checksum mode still performs the full
post-copy verification. Publication remains transactional and fail-closed.

The harness records and asserts the observed schedule, checksum mode, load and
part counts, copy/checksum worker counts, and all phase timings. A source-parts
run is rejected unless it reports exactly three parts per load and no separate
checksum workers in trusted-worker mode.

## Protocol

Both arms use the accepted G42/G43 closed-snapshot configuration:

| Parameter | Value |
|---|---|
| Model | `C:\ds4-models\ds4-2bit.gguf` (86,720,111,488 bytes) |
| Prompt | 43-token cyberpunk single-file HTML request |
| Context / generation | 256 / max 12, greedy no-think server path |
| Expected output SHA-256 | `921a62bdb39d9d07161326274fcbc0070f3c4b9e75153d27b1b6dc96811f6e88` |
| Snapshot | 4,551 entries, 30 GiB pinned arena, eight workers |
| VRAM tier | cache256, mass/LFRU clock 430, budget 16, min-frequency 3, hysteresis 1.25 |
| Memory partition | 2 GiB stream budget, 1,024 MiB load reserve, Q8-F16 off |
| Other | full prefill chunk, embedding staging, I/O QD 1, GPU-resident routes |
| Repetition | three independent one-request processes per arm, no warmup |

Arms:

- `expert-major`: G43 worker checksum, complete expert per work item;
- `source-parts`: exact incremental FNV across source-ordered parts.

Counter-order:

`expert A -> source A -> source B -> expert B -> expert C -> source C`

This is an exact short-prefix transport gate. It is not an L0-L3 long-output
quality verdict.

## Results

The median is the primary statistic because one expert-major run encountered a
large Windows page-fault/cache stall. The mean is retained as evidence, not
used as the headline estimate.

| Metric | Expert-major | Source-parts | Delta |
|---|---:|---:|---:|
| WRAP median | 31.947 s | 25.829 s | -6.118 s (-19.15%) |
| WRAP range | 30.109-201.671 s | 25.040-26.301 s | source-parts stable in this matrix |
| TTFT median | 52.508 s | 46.184 s | -6.324 s (-12.04%) |
| TTFT range | 50.314-222.119 s | 45.264-47.078 s | source-parts stable in this matrix |
| WRAP mean | 87.909 s | 25.723 s | outlier-sensitive; not the primary effect |
| Server decode mean | 4.040 t/s | 4.100 t/s | no decode claim; lever is startup-only |
| Process reads mean | 23.190 GiB | 23.211 GiB | +0.021 GiB |
| Minimum available RAM mean | 0.186 GiB | 0.129 GiB | both remain close to the limit |

Individual runs:

| Run | Arm | TTFT | Decode | WRAP | Standby before |
|---|---|---:|---:|---:|---:|
| expert A | expert-major | 50.314 s | 4.05 t/s | 30.109 s | 23.226 GiB |
| source A | source-parts | 45.264 s | 4.04 t/s | 25.040 s | 22.682 GiB |
| source B | source-parts | 46.184 s | 4.11 t/s | 25.829 s | 22.842 GiB |
| expert B | expert-major | 52.508 s | 4.08 t/s | 31.947 s | 23.222 GiB |
| expert C | expert-major | 222.119 s | 3.99 t/s | 201.671 s | 23.390 GiB |
| source C | source-parts | 47.078 s | 4.15 t/s | 26.301 s | 23.252 GiB |

All six runs produced the exact expected hash. Every run measured the same 516
route calls, 3,096 selections, 886 VRAM hits and 2,210 pinned-RAM hits.
Snapshot misses, SSD bytes, tiering failures, cold-to-RAM and cold-to-VRAM were
zero in every arm.

## Negative and Variability Evidence

The first source-parts prototype used one global part-copy phase followed by a
separate full-arena checksum phase. One representative run measured 24.614 s
for source-ordered copy plus 4.665 s for the cold checksum, totaling 29.293 s;
the checksum erased the apparent copy advantage. An earlier cold-state safety
run took 288.760 s. These `n=1` runs are mechanism evidence, not verdicts.

G44 therefore changed to exact incremental FNV while each copied part was hot.
The accepted source-parts matrix then stayed within a 1.261-second WRAP range.
The expert-major outlier occurred with 23.390 GiB of standby memory, close to
the other five starts, so total standby size alone does not explain it. The
harness cannot purge the Windows standby list on this host; cache composition
and page-fault order remain uncontrolled external variables.

The original matrix summary mistakenly read `standby_cache_bytes`; the
preflight schema calls the field `standby_bytes`. The table above is recovered
directly from each authoritative per-run JSON. The runner was corrected after
the matrix without changing any invocation, timing or runtime code.

## Verdict

G44 passes as a startup optimization for this exact G42/G43 configuration.
Source-offset scheduling reduces median WRAP by 19.15% and median TTFT by
12.04%, preserves the canonical full-slot checksum and exact output, and
substantially narrows the observed first-copy variance. It does not improve
steady decode because it changes only snapshot construction.

The next ranked bottleneck is the 2,210 pinned-RAM routes per 12-token request.
Proceed to direct resident-slot execution and explicit hit/miss separation:
VRAM hits should enter the MoE kernel without upload or synchronization, while
only RAM misses use the transport worker and one final join.

## Provenance

- measured source/runner implementation commit: `48234f31ec5828ae094496e42eb01f498e4b87c8`;
- measured base HEAD before commit: `af1899295dfee7878435ab997feaaa5b1bf1af89`;
- executable SHA-256: `801ea8ff8531245ff3083d71cdc5b5b55b93f0b1dc4904bee30d24d0dd653026`;
- CUDA source SHA-256: `be4103d78f05d0f565cf2103b0d93b2c04f517e1ac7ebd057951c6db67d34063`;
- build-input fingerprint: `752b0f3035f44c205e1cdf104b07c078b79a29594100481c7d60f90762b130c8`;
- build manifest SHA-256: `65e875fd4db81c7377e695c85bf385b44a829951c2176e5bf9309ca6014cc85c`;
- harness SHA-256: `235d4220e3903425ae55c32cec950a01a58bf601f6b55d80c2784995aa069533`;
- measured runner SHA-256: `c0a7a769d86da6b060dabe18ad2ae9450498fc029e4511c1bfa54638a1cb8a06`;
- matrix SHA-256: `a61ae1ef77b7defea293caa68b609e0765f21235a36dbd100bf56edc774791c0`.

The measured build manifest reports a dirty worktree because G44 was measured
before its implementation commit and historical run/build artifacts are
untracked. The manifest records every build-input hash plus the executable
hash; the committed CUDA source is byte-identical to the measured source.

Raw local artifact: `g7_runs/g44_source_parts_ab_result.json`.
