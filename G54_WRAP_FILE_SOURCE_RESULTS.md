# G54 direct-file WRAP source results

## Question

Does a random-access Win32 file handle improve the exact request-scoped arena
WRAP over the existing sequential-file handle when both use one copy worker?

This isolates the file access hint. Both arms keep the accepted G45/G46
configuration: 30 GiB pinned arena, source-parts order, worker-only checksum,
cache 320, request-scoped closed snapshot, mass/LFRU tiering, GPU-resident
routes and no default-stream synchronization.

## Protocol

- prompt: cyberpunk single-file HTML, context 256, 64 generated tokens;
- independent processes: n=3 per arm;
- order: random, sequential, sequential, random, random, sequential;
- expected output SHA-256:
  `31cbc6504dcb57d42aeff9dbceb3aed943bcb32dae19a2edbf552e9fd2f52eb8`;
- effective cache capacity: exactly 320 in every run;
- fail closed on output mismatch, snapshot miss, SSD traffic, tier failure,
  source mismatch, process contamination or mixed provenance.

The first attempt correctly stopped before the second process because the
system-quiescence preflight found sustained disk traffic. Sampling identified
`BackgroundDownload.exe` from Visual Studio Installer at about 30 MiB/s. It
was stopped, the system returned to zero disk queue, and the matrix resumed.
That refused launch is not a result row.

## Results

| Arm | WRAP mean | WRAP median | TTFT mean | Decode mean | Aggregate disk read | Aggregate read rate |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| sequential-file | 50.195 s | 50.255 s | 72.117 s | 4.553 t/s | 51.128 GiB | 539.6 MiB/s |
| random-file | 50.793 s | 50.526 s | 73.130 s | 4.533 t/s | 49.734 GiB | 517.8 MiB/s |

Random versus sequential:

- WRAP mean: +0.598 s (+1.19%);
- TTFT mean: +1.013 s (+1.40%);
- decode mean: -0.020 t/s (-0.44%).

| Run | Source | WRAP | TTFT | Decode | Disk read | Queue peak | Min available RAM |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| A | random | 51.503 s | 73.949 s | 4.58 t/s | 50.778 GiB | 16 | 17.421 GiB |
| A | sequential | 50.549 s | 72.073 s | 4.55 t/s | 50.641 GiB | 28 | 17.602 GiB |
| B | sequential | 49.782 s | 71.939 s | 4.57 t/s | 51.618 GiB | 20 | 17.556 GiB |
| B | random | 50.526 s | 72.527 s | 4.53 t/s | 48.926 GiB | 3 | 17.371 GiB |
| C | random | 50.351 s | 72.913 s | 4.49 t/s | 49.498 GiB | 32 | 17.888 GiB |
| C | sequential | 50.255 s | 72.338 s | 4.54 t/s | 51.126 GiB | 25 | 17.881 GiB |

All six outputs were exact. Every run reported zero snapshot misses, zero SSD
bytes, zero tier failures and no contamination abort. Queue peaks are
aggregate disk telemetry and occurred during DS4's own measured I/O; they are
not attributed to a background process.

## Verdict

Reject `random-file` as a performance lever. It is exact and memory-safe, but
it is slightly slower than the sequential-file baseline in this controlled
n=3 matrix.

Keep direct sequential-file WRAP with one worker as the current source path.
G54 also narrows the next bottleneck: each publication still performs 13,653
source-part reads for 4,551 experts and copies 32,211,468,288 bytes. The next
gate should measure source-range adjacency and the real amplification of
coalescing nearby parts before implementing batched or overlapped reads.

## Provenance

- measured HEAD: `d1d2771deff6eaeb0ac22fd3cf4389c0b3a85c57`;
- executable SHA-256:
  `740c54f91d62aa5ce04b25d35b4896e165975b243e51ec8120911335b37edea0`;
- execution runner SHA-256:
  `b710270aa27fb91d3c5cab2623bd40abc13c4f452149645c2a957d6e8e54e0e2`;
- summary: `g7_runs/g54_wrap_file_source_ab_result.json`;
- per-run results: `g7_runs/g7_g54_wrap_{random,sequential}_file_w1_{a,b,c}_result.json`.
