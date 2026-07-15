# G42 Request-Scoped Closed Snapshot and VRAM Tiering

Date: 2026-07-15
Host: native Windows, RTX 3060 12 GiB, 64 GiB RAM
Branch: `port/windows-dynamic-arena-0051`

## Question

Can one unbiased prompt prefill build a request-scoped closed expert set that
eliminates SSD decode misses, while an independent mass/LFRU policy protects a
256-expert VRAM subset and leaves the immutable snapshot in pinned RAM?

This is not a reusable static domain mask. The set is learned from the current
request, applied only after its prefill and removed at request end.

## Implementation

G42 composes four mechanisms:

1. Prefill records the complete 256-way router probability row for each token
   and semantic layer. Mass is normalized per row and accumulated without a
   router mask.
2. All 256 experts from each of the three hash-routed layers are included. The
   remaining capacity is filled by semantic `(layer, expert)` entries ranked by
   accumulated prefill mass.
3. One 30 GiB pinned-RAM snapshot publishes exactly 4,551 complete IQ2XXS
   expert triplets. A request-scoped router bias then excludes semantic experts
   outside the snapshot.
4. Mass/LFRU protects 256 snapshot-backed experts in VRAM. Other selected
   experts may move only from the immutable pinned snapshot to VRAM. SSD-cold
   entries cannot promote directly to VRAM.

The accepted code also fails closed if snapshot publication and mask
publication do not both succeed. It resets any partial composed mask, poisons
arena submissions and refuses decode rather than falling back to model-map or
SSD transport. The batch MoE API signature was kept coherent with Metal.

## Protocol

Runner: `g42_closed_snapshot_cache256_ab.ps1`.

| Parameter | Value |
|---|---|
| Model | `C:\ds4-models\ds4-2bit.gguf` (86,720,111,488 bytes) |
| Prompt | 43-token cyberpunk single-file HTML request used by G39-G41 |
| Context / generation | 256 / max 12, greedy no-think server path |
| Expected hash | `921a62bdb39d9d07161326274fcbc0070f3c4b9e75153d27b1b6dc96811f6e88` |
| Prefill | production full chunk plus unbiased full-probability mass |
| Dynamic arena | 30 GiB pinned host RAM, 4,551 slots, 8 WRAP workers |
| Streaming | 2 GiB budget, 1,024 MiB load reserve, no runtime reserve |
| VRAM tier | cache 256, LRU slots, mass/LFRU clock 430, budget 16, min-frequency 3, hysteresis 1.25 |
| Other toggles | Q8-F16 off, embedding-row staging on, I/O QD 1, GPU-resident routes on for G42 |
| Repetition | three independent one-request processes per arm, no warmup |

Arms:

- `control`: G41-style selected-top6 prefill bulk WRAP, no closed mask, no
  expert cache and no tiering;
- `closed`: full-probability 4,551-entry snapshot, request-scoped closed mask,
  cache256 and enforce-mode mass/LFRU.

Counter-order:

`control A -> closed A -> closed B -> control B -> control C -> closed C`

Every process started from a memory preflight and served exactly one request.
All six outputs matched the expected hash. This is an exact 12-token transport
gate, not an L0-L3 long-output quality verdict.

## Final Results

| Metric | Control | Closed G42 | Delta |
|---|---:|---:|---:|
| TTFT | 44.451 s | 82.078 s | +37.627 s |
| Snapshot publication | 22.982 s | 62.407 s | +39.425 s |
| Server decode | 2.277 t/s | 4.083 t/s | +79.36% |
| Client throughput, 12-token run | 0.2395 t/s | 0.1414 t/s | -40.97% |
| Process reads | 36.772 GiB | 23.190 GiB | -36.93% |
| Peak dedicated VRAM | 10.121 GiB | 10.443 GiB | +0.323 GiB |
| Minimum available RAM | 5.255 GiB | 0.363 GiB | -4.892 GiB |

Individual runs:

| Run | TTFT | Decode | WRAP | Reads | Peak VRAM | Min available RAM |
|---|---:|---:|---:|---:|---:|---:|
| control A | 44.527 s | 2.24 t/s | 23.286 s | 37.089 GiB | 10.128 GiB | 5.168 GiB |
| closed A | 91.830 s | 4.18 t/s | 72.145 s | 23.232 GiB | 10.443 GiB | 0.282 GiB |
| closed B | 78.182 s | 4.05 t/s | 58.497 s | 23.169 GiB | 10.443 GiB | 0.065 GiB |
| control B | 43.645 s | 2.31 t/s | 22.711 s | 36.355 GiB | 10.109 GiB | 5.377 GiB |
| control C | 45.180 s | 2.28 t/s | 22.950 s | 36.870 GiB | 10.124 GiB | 5.220 GiB |
| closed C | 76.221 s | 4.02 t/s | 56.579 s | 23.169 GiB | 10.443 GiB | 0.741 GiB |

The closed arm was deterministic in routing accounting:

- 4,551 snapshot entries: 768 hash-layer entries plus 3,783 mass-ranked
  semantic entries;
- 58.74% of normalized full-router prefill mass retained;
- 516 routed layer calls and 3,096 selected expert uses per request;
- 886 VRAM hits and 2,210 pinned-RAM hits per request;
- 4.283 RAM-served experts per routed layer call;
- 14.568 GiB RAM-to-VRAM traffic per request;
- 288 promotions, 32 demotions and 1,922 transient uses;
- zero snapshot misses, zero cold-to-RAM, zero cold-to-VRAM, zero SSD bytes and
  zero runtime failures in all three independent processes.

The control retained only 2,657 prefill-selected entries. It deterministically
recorded 2,443 arena hits and 653 arena misses during decode, a 78.91% arena hit
rate, plus 16.10 GiB arena-to-GPU traffic.

## VRAM Reserve Finding

The first attempted matrix used `DS4_CUDA_STREAM_RESERVE_MB=4096`. This was a
protocol error for this composition: it reduced the startup hot-weight cache
from 7.21 GiB to about 4.94 GiB and caused repeated non-expert tensor reloads.

The first pair measured:

| Arm | Reserve | TTFT | Decode | Process reads | Peak dedicated VRAM |
|---|---:|---:|---:|---:|---:|
| control | 4,096 MiB | 43.560 s | 0.14 t/s | 116.164 GiB | 7.256 GiB |
| closed | 4,096 MiB | 90.682 s | 0.15 t/s | 109.026 GiB | 7.197 GiB |

The closed route worker cost 5.948 ms/job. An isolated safety rerun changing
only the reserve to 1,024 MiB produced exact output, zero SSD, 4.11 t/s, 23.232
GiB reads, 10.443 GiB peak dedicated VRAM and 1.796 ms/job. This `n=1`
comparison identifies the configuration mechanism; the accepted performance
verdict is the separate `n=3` matrix above.

Earlier `n=1` cache probes at reserve 4,096 MiB are therefore not promoted as a
cache-capacity verdict. Cache336 additionally crossed a measured VRAM cliff and
fell to 0.51 t/s with 1,495 hot-cache evictions. Cache256 is the accepted G42
candidate, while cache-size optimization under the corrected 1,024 MiB reserve
remains unmeasured.

## Verdict

G42 passes the mechanism and steady-decode gates. It makes the request-scoped
arena closed in measured runtime, eliminates SSD decode traffic and raises
server decode by 79.36% to a reproducible 4.083 t/s mean on the local RTX 3060.

It does not pass the 12-token end-to-end gate because publication dominates
TTFT. Arithmetic from the measured means projects break-even at 194 generated
tokens; this is not a measured break-even. A long `n>=3` run must measure it
directly and grade complete outputs L0-L3.

The next performance target is the 62.407-second publication, not another mask:
reuse the ordinary prefill reads, batch and order snapshot fills, and avoid
touching all 30 GiB synchronously before the first token. RAM headroom is also
too small for production: the accepted closed arm reached only 0.065-0.741 GiB
minimum available memory. Arena capacity and population policy must retain
headroom without reintroducing SSD misses.

## Provenance

- measured HEAD: `4640c339eb70f4aaa08d3a05527300d21b17f665`;
- executable SHA-256:
  `877f34ea4009d67c63eaeba2fc3de8fc1f69e7b36476ba5c5e6bf5c3eed4beef`;
- CUDA source SHA-256:
  `8c992134d7fa4bf7790e796baafa5ac992fd7b6894ade33e9d55b45bb9aa4f9e`;
- build-input fingerprint:
  `ca47167e6141586482b9675874bef35c491b36aa638c8bdd9b710e8060b15f85`;
- build manifest SHA-256:
  `639c78dc0a9eeeec0ace7af676ef5327b72a3f1c2a9518cdf8558fdc9c7d7a67`;
- harness SHA-256:
  `cb362cee7045805282bd240a3b0102f7b1951ade602352248e3ea042fa61fc75`;
- runner SHA-256:
  `86af52a4e82e99ae5ee9dd06aaa321fc70f8d4c67d5935cd128eff5608ccbc2c`;
- matrix SHA-256:
  `9e09e68d5c6a9e4e4c815f55f15b691a07aa79338ab5d2981c8a4a9911d4fa79`.

Raw local artifact: `g7_runs/g42_closed_snapshot_cache256_ab_result.json`.
