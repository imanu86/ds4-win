# G39 Double-Buffered Prefill Wave Overlap

Date: 2026-07-15
Host: native Windows, RTX 3060 12 GiB, 64 GiB RAM
Branch: `port/windows-dynamic-arena-0051`

## Question

Can G38's exact capacity-bounded prefill waves overlap upload of wave N+1 with
compute of wave N, without changing the full-union router contract or final
ordered route sum?

## Implementation

`DS4_CUDA_PREFILL_WAVE_DOUBLE_BUFFER=1` requires
`DS4_CUDA_PREFILL_WAVES=1` and enables two parity-owned sets of:

- gate, up and down quantized expert slabs;
- remapped route-slot and active-pair device arrays;
- upload-ready and compute-done CUDA events.

Wave 0 is staged before execution. After stream 0 launches one wave's down
kernel and records its compute event, the host stages the next wave on the
nonblocking upload stream. Stream 0 waits only for the next parity's upload
event. Before a parity is reused, the host waits for that parity's persistent
compute-done event; this ownership survives routed-MoE layer boundaries.

The implementation remains opt-in and uses G38's generic sorted kernels. It
does not narrow router selection, alter weights, admit prefill experts to the
decode cache, or change the final ordered six-route sum.

G39 also hardens the shared pinned staging ring:

- resize drains the upload stream before destroying pinned buffers/events;
- serial and overlapped readers share the same CUDA-event ownership check;
- parity slabs are allocated only after both the prior upload fence and parity
  compute fence;
- failed mid-wave launches seal already-enqueued parity work, or synchronously
  drain stream 0 if event publication itself fails.

## Exactness failures found before the final matrix

Three failed `n=1` safety runs are retained as debugging evidence and excluded
from every performance aggregate:

1. Pair metadata was initially copied from a pageable vector to one shared
   device array after the upload-ready event. The vector could be overwritten
   by wave N+2 before stream 0 consumed it.
2. Per-parity compute ownership was reset at every routed-MoE call. Layer N+1
   could therefore overwrite a slab still used by layer N. This produced
   repeated begin-of-sentence tokens without launch blocking.
3. The model staging ring had separate producer-local ownership flags. The
   final code uses the shared CUDA event as the sole overwrite fence.

`CUDA_LAUNCH_BLOCKING=1` made the first implementation exact and was used only
to identify the race. It is not present in any accepted measurement.

A post-matrix review then found two latent error-path ownership gaps: slab
resize could precede a prior upload fence, and a failed mid-wave launch could
leave already-enqueued compute without parity ownership. Both were fixed before
the accepted matrix below was rerun. No failed request was used as performance
evidence.

## Protocol

Runner: `g39_prefill_wave_overlap_ab.ps1`.

Common configuration:

| Parameter | Value |
|---|---|
| Model | `C:\ds4-models\ds4-2bit.gguf` |
| Model size / mtime | 86,720,111,488 bytes / `2026-07-04T05:29:32.5463725Z` |
| Prompt | 43-token cyberpunk single-file HTML request |
| Context / generation | 256 / max 12, greedy no-think server path |
| Expected output hash | `921a62bdb39d9d07161326274fcbc0070f3c4b9e75153d27b1b6dc96811f6e88` |
| Expert cache | 336 slots, LRU, GPU-resident decode routes |
| Streaming | 2 GiB budget, 4096 MiB load reserve, 128 MiB runtime reserve |
| Other toggles | Q8-F16 off, embedding-row staging on, full prompt chunk |
| Isolated off | tiering, arena, REAP/mask, SPEX, split hit/miss |
| Repetition | one discarded warmup plus `n=3` measured requests/process |

Arms:

- `production`: normal optimized prefill kernels;
- `serial`: G38 generic sorted wave31;
- `overlap`: the same generic wave31 path plus G39 double buffering.

Counter-order:

`serial A -> overlap A -> production A -> production B -> overlap B -> serial B`

Every arm therefore has two process replications, six measured requests and two
discarded warmups. The runner fails closed on build/model/harness provenance,
all output hashes, 42 routed layers per request, the full 43-token prompt, every
active pair, every wave upload/compute event and zero runtime failures.

## Results

All 18 measured outputs and all six warmups matched the expected hash.

| Arm | TTFT | Client t/s | Decode t/s | Process reads | Peak dedicated VRAM |
|---|---:|---:|---:|---:|---:|
| production | 7.862 s | 0.8759 | 2.0533 | 164.45 GiB | 10.900 GiB |
| serial wave31 | 10.388 s | 0.8192 | 2.8200 | 131.32 GiB | 10.437 GiB |
| overlap wave31 | 8.583 s | 0.9308 | 2.7883 | 131.31 GiB | 10.642 GiB |

Overlap versus the same serial wave path:

- TTFT: `-17.38%`;
- client throughput: `+13.62%`;
- short decode throughput: `-1.12%`, effectively flat for this short request;
- process reads: effectively unchanged (`-0.04%`);
- peak dedicated VRAM: `+1.97%`, the expected second slab cost.

Overlap versus production:

- TTFT: `+9.18%` slower;
- client throughput: `+6.26%` on this short request;
- short decode throughput: `+35.80%`, directional only;
- process reads: `-20.15%`;
- peak dedicated VRAM: `-2.37%`.

Both overlap replications recorded 456 waves, 454 parity-reuse fences, 456
compute records and zero failures. Serial and overlap observed the same 11,716
cumulative union experts. Production observed 11,764 because it retained its
different tile-capable kernel policy.

The decode result is not a cache-policy verdict. This isolated wave path does
not admit the prefill union to the decode cache: each four-request process saw
2,016 route calls, only 24 all-hit calls, 1,992 miss-worker jobs and 7,141
miss experts. Composition with G36 tiering is a separate required experiment.

## Safety probes

After the final hardening:

- the normal `IoQD=1` 12-token probe matched the expected hash across all 42
  layers, 114 waves and zero failures;
- an `IoQD=2` 12-token probe exercised the shared overlapped staging reader and
  also matched the expected hash with 42 layers, 114 waves and zero failures.

These are `n=1` mechanism probes, not performance verdicts.

## Verdict

G39 is an exact positive overlap mechanism: it recovers 17.38% TTFT from G38's
serial wave implementation while preserving the full expert union. It is not a
production prefill win yet because generic wave kernels remain 9.18% slower
than the normal optimized path. Keep both G38 and G39 opt-in.

The next isolated prefill lever is tile-capable wave execution. Separately,
compose the current production full-chunk prefill with G36 mass/LFRU to obtain a
real end-to-end SOTA instead of comparing records from different configurations.

## Provenance

- measured base HEAD: `78f50cb2855ac959b31526010ecac2f6a419e41b`;
- executable SHA-256:
  `4a390be7a8e490ef70d14b4f316b7efe04dd9ecd00e09e096eed556d317e49b1`;
- CUDA source SHA-256:
  `863b26ac3538492bef1b0f38c2f7fe36f7600632a4dfdfad3768f8fc124e014d`;
- build-input fingerprint:
  `3a6dd4c946c03229b455811cc7c9bf49fc5ee3f172ace91da07e76237c618d59`;
- build manifest SHA-256:
  `e5f3f6512294b927e7c98a59cf97f08f6d15bf8bb69d91775d38e8f9dc0c2d62`;
- harness SHA-256:
  `4f951488e1a83a595b5f85829e578c2d3626600d11c1f5a7fe422823c39d52f2`;
- runner SHA-256:
  `dbd1880bd3edcbdfb9eebf1ca4df68826916be83dbc7c06119d9b19658d5f735`;
- final matrix SHA-256:
  `b1f6ed162a42f772ccb42f60087fdc38aabc87507fd7dcae33b29f2a307fbfd1`;
- post-review `IoQD=2` safety result SHA-256:
  `a9737eabe1ff38eea622d09a0b556e1339e1689233234eb2f1cf8ceb943917d1`.

The build manifest records a dirty worktree because source, harness and runner
were intentionally measured before their experiment commit. Their exact hashes
and the complete compile-input fingerprint above pin the measured state.

Raw local artifacts:

- `g7_runs/g39_prefill_wave_overlap_ab_result.json`;
- `g7_runs/g7_g39_postreview_qd2_safety_n1_result.json`.
