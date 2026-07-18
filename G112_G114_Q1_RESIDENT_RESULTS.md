# G112-G114 Q1_0 resident transport results

Date: 2026-07-18

## Question

Can a full request-scoped Q1_0 snapshot remove SSD traffic and raise decode
throughput, while a small exact-IQ2 VRAM seed recovers quality?

These runs are safety runs (`n=1`). They are transport and quality-gate
evidence only. None is SOTA-eligible, and no general quality verdict is made
from a single sample.

## Fixed protocol

- Model: `C:\ds4-models\ds4-2bit.gguf`
- Model SHA-256: `efc7ed607ff27076e3e501fc3fefefa33c0ed8cf1eff483a2b7fdc0c2e616668`
- Q1_0 sidecar: `C:\ds4-models\ds4-q1-layers0-42-derived.gguf`
- Sidecar SHA-256: `05040393f5e94bf054a593e4d2d021ff44a6f446f2328a75e4f833a1fbe20207`
- Prompt: Cyberpunk HTML, `--nothink`, greedy, 256 generated tokens,
  context 8192, prefill chunk 256.
- Q1_0 snapshot: 11,008 routed experts, about 36.4 GiB total;
  30 GiB pinned plus pageable overflow.
- The router selection is unchanged. Only the representation used for a
  selected route changes.

## Results

| Run | Representation actually used | Server decode | Steady decode | WRAP | TTFT/prompt | SSD/direct pread | Grade |
|---|---:|---:|---:|---:|---:|---:|---:|
| G112 pure Q1 | 0 IQ2 + 6 Q1 per layer | 6.76 t/s | about 6.77 t/s | 29.416 s | not ledgered | 0 | L0 |
| G113 seed7 | about 1.23 IQ2 + 4.77 Q1 | 6.21 t/s | about 6.94 t/s | 29.367 s | seed 4.622 s | 0 | L1 |
| G113 seed8 | about 1.15 IQ2 + 4.85 Q1 | 6.22 t/s | about 6.96 t/s | 29.418 s | 55.930 s; seed 4.783 s | 0 | L1 |
| G114 global320 floor4 | about 1.34 IQ2 + 4.66 Q1 | 6.22 t/s | 6.90-7.05 t/s | 29.416 s | 55.025 s; seed 4.846 s | 0 | L1 |

The G113/G114 server average includes the one-time IQ2 seed upload. The later
50-token chunks are the useful steady-decode measurement. End-to-end throughput
is much lower because it includes WRAP, prompt processing, and seed setup.

## Measured transport facts

- G112: 66,048 Q1 routes, 0 IQ2 routes, 0 Q1 misses, 0 direct preads.
- G113 seed7: 52,460 Q1 routes and 13,588 exact IQ2 VRAM routes, 0 misses.
- G113 seed8: 53,351 Q1 routes and 12,697 exact IQ2 VRAM routes, 0 misses.
- G114 global320: 51,299 Q1 routes and 14,749 exact IQ2 VRAM routes, 0 misses.
- The global-mass seed raised the IQ2 share, but not enough to recover valid
  HTML/CSS in this safety sample.

## Honest conclusion

The all-Q1 snapshot succeeds as a transport experiment: it removes SSD from
decode and demonstrates a roughly 6.8-7.0 t/s steady ceiling on the RTX 3060.
It fails the quality gate. Adding 280-320 exact IQ2 VRAM entries improves the
representation mix only to roughly one IQ2 route out of six, and both tested
seed policies still produced malformed or incomplete HTML/CSS.

This is not the intended 5+1 architecture. The next candidate must explicitly
choose the lowest router-weight route as Q1_0 and serve the other five routes
from resident IQ2. It must also keep both representations for the admitted
sparse candidate set in host memory, otherwise the five IQ2 routes reintroduce
SSD transport and invalidate the design.

## Gate for the next candidate

1. Exactly one Q1 route and five IQ2 routes per routed layer/call, selected by
   router weight rather than accidental cache residency.
2. Zero IQ2 SSD bytes, zero Q1 SSD bytes, and zero direct-pread fallbacks during
   decode.
3. One Cyberpunk safety run first; stop if it is L0/L1.
4. Run `n>=3` only after the safety output reaches at least L2.
5. Compare the valid result against G73 (4.9867 t/s, exact `n=3`) rather than
   against the unqualified 6.8-7.0 t/s transport ceiling.
