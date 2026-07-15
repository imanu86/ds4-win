# G40 Production Prefill Plus Mass/LFRU on Cyberpunk

Date: 2026-07-15
Host: native Windows, RTX 3060 12 GiB, 64 GiB RAM
Branch: `port/windows-dynamic-arena-0051`

## Question

Does the short-prompt G36 mass/LFRU win compose with the current production
full-chunk prefill on the 43-token cyberpunk coding prompt, and does it reduce
the decode miss pressure observed in G39?

## Protocol

Runner: `g40_mass_lfru_cyberpunk_ab.ps1`.

Common configuration:

| Parameter | Value |
|---|---|
| Model | `C:\ds4-models\ds4-2bit.gguf` |
| Prompt | G39 43-token cyberpunk single-file HTML request |
| Context / generation | 256 / max 12, greedy no-think server path |
| Expected output hash | `921a62bdb39d9d07161326274fcbc0070f3c4b9e75153d27b1b6dc96811f6e88` |
| Prefill | production full chunk, union telemetry enabled |
| Expert cache | 336 slots, LRU, GPU-resident decode routes |
| Streaming | 2 GiB budget, 4096 MiB load reserve, 128 MiB runtime reserve |
| Other toggles | Q8-F16 off, embedding-row staging on |
| Repetition | one discarded warmup plus `n=3` measured requests/process |

Arms:

- `production`: no dynamic arena, tiering off;
- `arena_control`: 8 GiB pinned dynamic arena allocated, tiering off;
- `mass_lfru`: the same 8 GiB arena plus enforce-mode mass/LFRU, clock 430,
  replacement budget 16, minimum frequency 3 and hysteresis 1.25.

Counter-order:

`production A -> arena-control A -> mass-LFRU A -> mass-LFRU B -> arena-control B -> production B`

Every arm has two process replications, six measured requests and two discarded
warmups. All 18 measured outputs and six warmups matched the expected hash.
This is an exact short-prefix transport test, not an L0-L3 long-output quality
verdict.

## Accounting Difference

Production reported 42 routed prefill/decode layers per request. Merely enabling
the 8 GiB arena made 43 layers observable in both arena arms. The runner records
and validates this measured difference instead of forcing identical counters.
It is one reason to retain the no-arena production arm as well as the matched
arena control.

Neither arena arm enabled prefill-mass observation or WRAP publication. The
8 GiB allocation was therefore available but not bulk-populated from the
prompt; resident-arena telemetry remained zero before decode. This was
intentional for isolating direct composition with G36, and it distinguishes
this test from the next bulk-seed gate.

## Results

| Arm | TTFT | Client t/s | Decode t/s | Process reads | Shared peak |
|---|---:|---:|---:|---:|---:|
| production | 7.912 s | 0.8754 | 2.0683 | 164.37 GiB | 2.375 GiB |
| arena control | 7.905 s | 0.8615 | 1.9900 | 174.99 GiB | 8.371 GiB |
| mass/LFRU | 7.913 s | 0.3554 | 0.4633 | 433.99 GiB | 8.371 GiB |

Arena allocation alone left TTFT effectively unchanged, reduced short decode
3.79%, increased missing experts 3.91%, and added one observed routed layer.

Mass/LFRU versus the matched arena control:

- TTFT: effectively unchanged (`+0.11%`);
- client throughput: `-58.74%`;
- decode throughput: `-76.72%`;
- process reads: `+148.00%`;
- all-hit route calls: 28 -> 137 (`+389.29%`);
- miss-worker jobs: 2,036 -> 1,927 (`-5.35%`);
- missing experts: 7,444 -> 6,155 (`-17.32%`).

| Arm | Route calls | All-hit | Miss jobs | Missing experts | Worker ms/job | Wait ms/call |
|---|---:|---:|---:|---:|---:|---:|
| production | 2,016 | 28 | 1,988 | 7,164 | 4.870 | 4.798 |
| arena control | 2,064 | 28 | 2,036 | 7,444 | 5.012 | 4.940 |
| mass/LFRU | 2,064 | 137 | 1,927 | 6,155 | 9.158 | 8.548 |

Both mass/LFRU replications were deterministic: 2,125 cold-to-RAM admissions,
400 VRAM promotions, 64 physical replacements, 5,755 transient routes, 336
final protected VRAM states, 15,040,512,000 SSD bytes and 43,564,400,640 RAM-to-
GPU bytes. No tier or route failures were reported.

## Verdict

The policy signal improved residency: more all-hit calls and fewer missing
experts. The current incremental transport actuator made each remaining miss
far more expensive and read 2.48 times the arena-control bytes, so the composed
path is a strong negative performance result on this workload.

This does not retract the G36 short-prompt measurement. It shows that the G36
configuration does not transfer to a broader first-request coding prompt. The
next isolated gate is prefill-mass bulk publication: learn the request working
set during the normal unbiased prefill, load it into pinned RAM in one bounded
transaction before decode, and then let slow-clock mass/LFRU protect only the
VRAM subset. Do not tune mass thresholds before measuring that transport change.

## Provenance

- HEAD: `5633856d43d353469fe506e2c013add15f03a25c`;
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
  `e579a0e86d4376b67d368d22cb1d8056ff98f7e8f54d08af33b603f669cfaee0`;
- matrix SHA-256:
  `a9553908ee9ad7798b8a9fd65ac9ca0acaf77154b503c8c55c1e6daee8137024`.

Raw local artifact: `g7_runs/g40_mass_lfru_cyberpunk_ab_result.json`.
