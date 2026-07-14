# G24 - Prefill mass seed, observe-only

Date: 2026-07-14
Branch: `port/windows-dynamic-arena-0051`
Base HEAD: `fb663f100b34caffa585a9c968e8740c4276f887`

## Status

Feasibility and safety smoke only (`n=1` per arm). This is not a throughput
verdict and does not satisfy the `n>=3` promotion rule.

## Question

Can the exact selected router IDs and normalized gate weights observed during
prefill seed a bounded expert-layer candidate set that predicts the first
decode tokens, without changing routing, masks, arena publication, or
residency?

## Implementation

`DS4_CUDA_PREFILL_MASS_OBSERVE=1`:

1. Arms at the request boundary.
2. During semantic prefill, accumulates
   `mass[layer, expert] += selected_gate_weight` and hit counts.
3. At the existing post-prefill boundary, ranks expert-layer entries by mass,
   with stable entry-ID tie-breaking.
4. Selects at most the current pinned-arena slot capacity.
5. During decode, measures selected-ID membership in that candidate set.

The implementation is observe-only. It does not call arena begin/publish, does
not change router scores or selected IDs, and does not apply a mask. Decode
coverage uses selected IDs already present on the host path. The only added
runtime transfer is the selected-weight D2H during prefill while the flag is
enabled.

The harness exposes `-PrefillMassObserve`, records the effective env, parses
the observer telemetry into JSON, and fails closed if arm/finalize/candidate
or decode coverage is missing or malformed.

## Common protocol

```text
model: C:\ds4-models\ds4-2bit.gguf
prompt: Explain in one concise paragraph why Julius Caesar crossed the Rubicon.
prompt mode: chat, nothink, temperature 0
max tokens: 16
context: 256
masked RAM budget: 2 GiB
VRAM reserve: 1024 MiB
MoE I/O QD: 1
REAP prefetch threads: 8
expert cache: off
SPEX: off
decode observer/grow: off
```

Expected and observed output SHA-256 in every arm:

```text
b037ce25fab7393eeb9fc5b7bf7f5b8ef70768aea476cd1c09b0ffa348323b30
```

Output:

```text
Julius Caesar crossed the Rubicon River in 49 BCE because he faced an
```

## Results

| Arm | Arena | Observe | Unique prefill entries | Candidate | Prefill mass coverage | Decode selected-ID hit rate | TTFT | Server decode |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| OFF safety | 2 GiB | no | n/a | n/a | n/a | n/a | 4.369 s | 2.81 t/s |
| ON safety | 2 GiB | yes | 1,980 | 303 | 50.03% | 25.78% | 4.369 s | 2.82 t/s |
| ON capacity probe | 30 GiB | yes | 1,980 | 1,980 / 4,551 slots | 100.00% | 68.20% | 16.187 s | 1.27 t/s |

The OFF/ON 2 GiB arms used the same executable. The 30 GiB capacity probe was
run after a telemetry-only off-by-one correction to the final decode-token
counter. All arms were hash-exact. The close 2 GiB timing values are descriptive
only; `n=1` is insufficient for a performance claim.

## Measured coverage curve, 30 GiB

| Completed decode tokens | Cumulative selected slots | Candidate hits | Hit rate |
|---:|---:|---:|---:|
| 1 | 240 | 201 | 83.75% |
| 2 | 480 | 389 | 81.04% |
| 4 | 960 | 762 | 79.37% |
| 8 | 1,920 | 1,485 | 77.34% |
| 16 | 3,840 | 2,619 | 68.20% |

The prefill contained 17 routed rows per non-hash layer, 40 routed layers,
4,080 selected slots, and total normalized selected mass 1,020.000002.

## Interpretation

1. The prefill footprint is immediately useful but not sufficient by itself:
   it covers 83.75% of the first decode token and 68.20% cumulatively at token
   16 for this prompt.
2. A 2 GiB arena is too narrow for this seed: it retains half of prefill mass
   but only 25.78% of subsequent selected calls.
3. Merely allocating 30 GiB pinned/shared RAM while leaving it empty is harmful:
   shared-memory pressure rises without producing arena hits. This probe must
   not be used as a serving configuration.
4. The next isolated experiment is to bulk-WRAP only the ranked prefill set at
   the post-prefill boundary. REAP/LiveMask remains disabled for that test.
5. Only after bulk-WRAP safety and causal A/B are measured should the continuous
   mass controller be ported and composed to recover drift after token 1.

## Artifacts

```text
g7_runs/g7_g24_prefill_mass_off_safety_n1_result.json
g7_runs/g7_g24_prefill_mass_off_safety_n1_stderr.log
g7_runs/g7_g24_prefill_mass_on_safety_n1_result.json
g7_runs/g7_g24_prefill_mass_on_safety_n1_stderr.log
g7_runs/g7_g24_prefill_mass_on_arena30_safety_n1_result.json
g7_runs/g7_g24_prefill_mass_on_arena30_safety_n1_stderr.log
```
