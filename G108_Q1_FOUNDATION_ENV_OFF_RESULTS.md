# G108 Q1_0 foundation env-off safety

Status: structural exactness safety only. This is not a throughput or quality
result.

Date: 2026-07-17

## Purpose

Verify that the corrected Q1_0 foundation is inert when its opt-in environment
variables are disabled. The run reproduces the G73 static-32 split-fused stack
against the authoritative IQ2 model and expected greedy output.

## Provenance

- DS4 commit: `6a445781882285f3c60431114b1701bb8cfda8ab`
- executable SHA-256:
  `dc6bab660839349e07193683881e52d6ddc9b33344997fa8c5cc60805fdd3e19`
- build manifest SHA-256:
  `792add4330f71b62f44ec2f5b8bed0b4e027db50a795de8005ec236385e9ad7c`
- build input fingerprint SHA-256:
  `053df537a7ecce0612d1cb83a978a3a1271cc463a1599b658f09017399760bc1`
- model: `C:\ds4-models\ds4-2bit.gguf`
- prompt SHA-256:
  `38f6ec5ee5403f59dd2418eb5d9a5a94a0f0da19df015060383bb1ae46003bb6`
- raw result:
  `g7_runs/g7_g108_q1_foundation_env_off_safety_exact_result.json`

The first launch stopped before opening the model because the build manifest
was stale. It produced no DS4 inference result. `g7_build.ps1` regenerated the
manifest and executable provenance before the recorded run.

## Configuration

- one process and one repeat (`n=1`), greedy, no-think
- context 256, maximum 64 generated tokens
- 30 GiB dynamic arena, source-parts WRAP, 4 GiB unlock waves
- prefill mass observation, WRAP and mass/tiering composition
- IQ2 expert cache 320, LRU
- mass-LFRU tiering: clock 430, replacement budget 32, minimum frequency 3,
  hysteresis 1.25
- GPU-resident routes, no default-stream sync, split-fused hit/miss execution
- Q1_0 and IQ1_S sidecars disabled

Server arguments:

```text
-m C:\ds4-models\ds4-2bit.gguf --cuda -c 256 -n 64 --host 127.0.0.1 --port 8000
```

## Structural gate

| Check | Measured result |
|---|---:|
| Server exit | `0` |
| Expected content SHA-256 | `31cbc6504dcb57d42aeff9dbceb3aed943bcb32dae19a2edbf552e9fd2f52eb8` |
| Observed content SHA-256 | `31cbc6504dcb57d42aeff9dbceb3aed943bcb32dae19a2edbf552e9fd2f52eb8` |
| Outputs identical | `true` |
| Q1_0/IQ1_S runtime observed | `false` |
| Prefill candidates / arena slots | `4551 / 4551` |
| Snapshot backing misses | `0` |
| Tiering SSD bytes | `0` |
| RAM-to-GPU expert bytes | `75,676,778,496` |
| Arena allocation | `32,211,468,288` bytes |
| Prefill WRAP | `26.354 s` |
| Peak dedicated VRAM | `11,743 MiB` |

The env-off exactness gate passes: the Q1_0 foundation does not change the
known G73 output or activate a Q1 path.

## Ineligible timing

The single run reported `8.3 t/s` server decode and `51.241 s` prefill/TTFT.
These measurements are retained for provenance but are explicitly ineligible
for the SOTA ledger or a performance verdict: `n=1`,
`quality_eligible=false`, `sota_eligible=false`, contamination reason
`repeats-less-than-3-not-quality-eligible`.

