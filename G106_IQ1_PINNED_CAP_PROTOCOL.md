# G106: IQ1_S pinned host-tier capacity gate

Date: 2026-07-17

## Question

With the current native-Windows DS4 stack and a 20 GiB IQ2 dynamic arena,
how large can the pinned IQ1_S host cache be before WDDM refuses the
allocation or Windows starts paging? This is a structural capacity gate, not a
throughput or quality experiment.

## Frozen runtime configuration

- Main model: `C:\ds4-models\ds4-2bit.gguf`
- IQ1_S sidecar: `C:\ds4-models\DeepSeek-V4-Flash-IQ1_S-XL.gguf`
- CUDA dynamic IQ2 arena: 20 GiB
- VRAM expert-cache request: 320 experts
- IQ1 fixture: one forced IQ1 route per routed layer (`mixed cold one`)
- G73 transport controls: source-parts WRAP, unlocked source ranges,
  no Q8-F16 cache, GPU resident routes, no default route sync, split-fused
- Prompt: the frozen cyberpunk single-file HTML prompt used by G103-G105
- Sampling: temp 0 / nothink through the existing harness
- Process count: n=1, structural-safety only

Runtime contamination aborts were armed for three consecutive samples:

- hard available-RAM floor: 4 GiB
- system page-output ceiling: 512 pages/s
- private working-set ratio below 0.70 only after private bytes reach 40 GiB
- legacy low-RAM plus disk-queue gate retained

The new guard is opt-in. Its default-off behavior preserves prior protocols.

## Results

| IQ1 pinned request | Tokens | IQ1 slots used/capacity | Min available RAM | Peak shared WDDM | Peak page-out/s | VRAM expert slots | Result |
|---:|---:|---:|---:|---:|---:|---:|---|
| 6 GiB | 16 | 488 / 1310 | 26.867 GiB | 26.373 GiB | 0 | 320 | PASS |
| 6 GiB | 64 | 1259 / 1310 | 26.236 GiB | 26.373 GiB | 0 | 320 | PASS, near-full cache |
| 8 GiB | 16 | 488 / 1747 | 24.891 GiB | 28.373 GiB | 0 | 296 | PASS |
| 10 GiB | 16 | 488 / 2184 | 22.923 GiB | 30.373 GiB | 0 | 296 | PASS |
| 11 GiB | 8 requested | 0 / allocation failed | n/a | n/a | n/a | n/a | FAIL CLOSED |

The 11 GiB arm reached the first routed IQ1 load and failed with:

`IQ1_S pinned RAM cache allocation failed: out of memory requested=10.995 GiB`

The first 6 GiB attempt was intentionally excluded. The initial residency
threshold (0.80 with an 8 GiB private-byte floor) killed a healthy CUDA startup
while 35 GiB remained available and page-out was zero. That calibration error
led to the 40 GiB/0.70 residency gate above and to explicit monitor-abort
reasons in HTTP failure reports.

## Decision

- Measured allocation boundary for this exact stack: 10 GiB passes; 11 GiB is
  the first failed pinned IQ1 request.
- The first dynamic-policy candidate is 6 GiB, not 10 GiB. At 6 GiB the full
  320-slot VRAM cache survives; 8 and 10 GiB reduce it to 296 slots.
- No G106 timing is SOTA-eligible. The forced IQ1 fixture is known to be the
  wrong routing policy and the runs are n=1.
- No quality verdict is made. The short snippets are structural smoke output,
  not L0-L3 grading.
- The next runtime gate must substitute IQ1 only for a route proven to be
  IQ2-SSD-cold while preserving IQ2 VRAM and IQ2 arena/RAM hits.

Machine-readable evidence is in `G106_IQ1_PINNED_CAP_RECEIPT.json`.
