# G43 WRAP Worker Checksum Results

Date: 2026-07-15
Host: native Windows, RTX 3060 12 GiB, 64 GiB RAM
Branch: `port/windows-dynamic-arena-0051`

## Question

Can request-scoped snapshot publication avoid a second serial read of the full
30 GiB pinned arena by trusting the checksum already computed by each joined
copy worker, without changing exact output, decode routing or storage tiering?

## Implementation

The existing WRAP worker copies one complete IQ2XXS expert triplet from the
model `mmap` into its pinned arena slot, then computes FNV-1a over the complete
slot. All workers are joined before any slot is finalized or published.

G43 adds an opt-in `DS4_CUDA_ARENA_WRAP_TRUST_WORKER_CHECKSUM=1` path. It stores
the checksum produced by the worker and skips only the second serial FNV pass in
`finish_load`. The public `ds4_gpu_dynamic_arena_finish_load` API and default
path still perform the second checksum. Invalid environment values disable the
optimization. Publication remains transactional and requires every copy and
finish operation to succeed.

WRAP now reports `begin`, `copy_checksum`, `finish`, `publish` and `total`
phase times. Runner `g43_wrap_checksum_ab.ps1` validates the expected checksum
mode and fails closed on missing or duplicate profile lines.

## Protocol

Both arms use the accepted G42 closed-snapshot configuration:

| Parameter | Value |
|---|---|
| Model | `C:\ds4-models\ds4-2bit.gguf` (86,720,111,488 bytes) |
| Prompt | 43-token cyberpunk single-file HTML request |
| Context / generation | 256 / max 12, greedy no-think server path |
| Expected output SHA-256 | `921a62bdb39d9d07161326274fcbc0070f3c4b9e75153d27b1b6dc96811f6e88` |
| Snapshot | 4,551 entries in a 30 GiB pinned arena, eight workers |
| VRAM tier | cache256, mass/LFRU clock 430, budget 16, min-frequency 3, hysteresis 1.25 |
| Memory partition | 2 GiB stream budget, 1,024 MiB load reserve, Q8-F16 off |
| Other | full prefill chunk, embedding staging, I/O QD 1, GPU-resident routes |
| Repetition | three independent one-request processes per arm, no warmup |

Arms:

- `finish-verify`: worker FNV plus the original serial finish FNV;
- `worker-checksum`: worker FNV only, after all worker threads join.

Counter-order:

`verify A -> worker A -> worker B -> verify B -> verify C -> worker C`

This is an exact short-prefix transport gate, not an L0-L3 long-output quality
verdict.

## Results

| Metric | Finish verify | Worker checksum | Delta |
|---|---:|---:|---:|
| TTFT | 86.028 s | 47.355 s | -38.673 s (-44.95%) |
| WRAP total | 65.214 s | 27.251 s | -37.963 s (-58.21%) |
| Copy plus worker checksum | 32.758 s | 27.236 s | -5.522 s |
| Finish checksum | 32.433 s | 0.001 s | -32.432 s |
| Publish | 0.017 s | 0.008 s | -0.009 s |
| Server decode | 4.093 t/s | 4.093 t/s | 0.00% |
| Process reads | 23.598 GiB | 23.211 GiB | -0.387 GiB |
| Peak dedicated VRAM | 10.443 GiB | 10.443 GiB | 0 |
| Minimum available RAM | 0.226 GiB | 0.325 GiB | +0.099 GiB |

Individual phase results:

| Run | Arm | TTFT | Decode | Copy+worker FNV | Finish FNV | WRAP |
|---|---|---:|---:|---:|---:|---:|
| verify A | finish verify | 86.994 s | 4.03 t/s | 34.706 s | 31.913 s | 66.644 s |
| worker A | worker checksum | 48.766 s | 4.06 t/s | 28.876 s | 0.001 s | 28.892 s |
| worker B | worker checksum | 49.095 s | 4.13 t/s | 28.741 s | 0.001 s | 28.755 s |
| verify B | finish verify | 94.232 s | 4.20 t/s | 40.565 s | 31.821 s | 72.410 s |
| verify C | finish verify | 76.857 s | 4.05 t/s | 23.003 s | 33.565 s | 56.589 s |
| worker C | worker checksum | 44.203 s | 4.09 t/s | 24.090 s | 0.001 s | 24.106 s |

All six runs produced the exact expected hash. Every run also measured the same
516 route calls, 3,096 selections, 886 VRAM hits and 2,210 pinned-RAM hits.
Snapshot misses, cold-to-RAM, cold-to-VRAM, SSD bytes and tiering failures were
zero in both arms.

## Negative and Variability Evidence

The initial profiling run with the original double checksum measured:

- `copy_checksum=253.623 s`;
- `finish=32.347 s`;
- `total=286.070 s`;
- exact output, zero SSD and 4.01 t/s decode.

This run is not part of the balanced performance verdict. It demonstrates that
the first `mmap` copy is still highly sensitive to Windows page-fault/cache
state. In the accepted matrix, copy plus worker checksum varied from 23.003 to
40.565 seconds. The removed finish pass was much more stable at 31.821-33.565
seconds.

## Verdict

G43 passes. The second full-arena checksum was redundant on the joined WRAP
path and cost 32.433 seconds on average. Removing it cuts WRAP 58.21% and TTFT
44.95%, while exact output, decode speed, route accounting, VRAM residency and
zero-SSD closure remain unchanged.

The next isolated lever is the first copy, not another mask. Test a globally
source-ordered or part-major copy schedule against the current expert-major
schedule, with the same phase telemetry and balanced `n>=3` protocol. Preserve
the 1,024 MiB reserve and measure RAM headroom, because the 30 GiB arena still
leaves less than 0.4 GiB available at the observed minima.

## Provenance

- implementation/runner commit: `4a3b792bbaa74eee9d6402d9041bcc5cc3b03bf9`;
- executable SHA-256: `c3323946ecd9714b253ff39f94a7acfb365cce72592a218fcd52dc8886c80b08`;
- CUDA source SHA-256: `88e44daff0b406f41bfcf1782de059e9e4f07fdf19a217066b7e90d5bd75a49a`;
- build-input fingerprint: `ea39b1d3f18426e22f45f899f4407dc328b795b2ed3a916c9c379d2eb19b395a`;
- build manifest SHA-256: `a8c24da98632e0f0b740b3bdfd1d94f54737c0c2fedfb3953038daa0ceb8865e`;
- harness SHA-256: `58ee076b00cf8335d9199fdef67d6db39f6368d54a803225b907c33335803ef1`;
- runner SHA-256: `5ca8f15395505b6e808b7dc86ed4c15bd22bdf64ce481bb415b0017f1cd07d4b`;
- matrix SHA-256: `109cd153e2c1bdc3a16042cadae8c3c7d07159dc4661c072e4df11f770704120`.

The build manifest reports a dirty worktree because historical run/build
artifacts are untracked. Tracked sources were clean at measured HEAD, and the
manifest records every build-input hash plus the executable hash.

Raw local artifact: `g7_runs/g43_wrap_checksum_ab_result.json`.
