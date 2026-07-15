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
- parity slabs are allocated only after the parity compute fence.

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
| production | 7.592 s | 0.9066 | 2.1267 | 164.55 GiB | 10.900 GiB |
| serial wave31 | 10.133 s | 0.8389 | 2.8800 | 131.14 GiB | 10.437 GiB |
| overlap wave31 | 8.577 s | 0.9464 | 2.9283 | 131.31 GiB | 10.642 GiB |

Overlap versus the same serial wave path:

- TTFT: `-15.36%`;
- client throughput: `+12.81%`;
- short decode throughput: `+1.68%`;
- process reads: effectively unchanged (`+0.13%`);
- peak dedicated VRAM: `+1.97%`, the expected second slab cost.

Overlap versus production:

- TTFT: `+12.97%` slower;
- client throughput: `+4.39%` on this short request;
- short decode throughput: `+37.70%`, directional only;
- process reads: `-20.20%`;
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

G39 is an exact positive overlap mechanism: it recovers 15.36% TTFT from G38's
serial wave implementation while preserving the full expert union. It is not a
production prefill win yet because generic wave kernels remain 12.97% slower
than the normal optimized path. Keep both G38 and G39 opt-in.

The next isolated prefill lever is tile-capable wave execution. Separately,
compose the current production full-chunk prefill with G36 mass/LFRU to obtain a
real end-to-end SOTA instead of comparing records from different configurations.

## Provenance

- measured base HEAD: `32f0292ea4063c81a59387e01d0d43d43ae84100`;
- executable SHA-256:
  `5bb481a2ecd7b5270de57bf4e6caec77877fd7ac200f4170d4a092725d40b6c5`;
- CUDA source SHA-256:
  `b04fbdd0f852dba26e5be7c410434475223a0fa77efc746b1142649f7e0b8b98`;
- build-input fingerprint:
  `afaa35af22b1dbafe5ea28aa5f5067b6e612f067ae2ba7006eee51589d9f03a0`;
- build manifest SHA-256:
  `1bd8ad6642989c024139ffe5f70a6ef44f2498e703442ac768fd0697b1f3df3f`;
- harness SHA-256:
  `4f951488e1a83a595b5f85829e578c2d3626600d11c1f5a7fe422823c39d52f2`;
- runner SHA-256:
  `dbd1880bd3edcbdfb9eebf1ca4df68826916be83dbc7c06119d9b19658d5f735`;
- final matrix SHA-256:
  `7b0186e54b183bf0748dc73adc427e8b014ef14fab57d61dff0507b4a1c309ad`;
- hardened `IoQD=2` safety result SHA-256:
  `c18419a014cc5cb44996e1614b0c7327147b9dc626754d981dce4453235921ec`.
- hardened default-off safety result SHA-256:
  `4e30e1b7bc6194d4e025b778983cb1b12d7387a85e1f7f9347ecaa45bf56fef2`.

The build manifest records a dirty worktree because source, harness and runner
were intentionally measured before their experiment commit. Their exact hashes
and the complete compile-input fingerprint above pin the measured state.

Raw local artifacts:

- `g7_runs/g39_prefill_wave_overlap_ab_result.json`;
- `g7_runs/g7_g39_overlap31_hardened_safety_n1_result.json`;
- `g7_runs/g7_g39_overlap31_hardened_qd2_safety_n1_result.json`.
