# G107 IQ1_S cold-only residency gate

Date: 2026-07-17

Implementation: `83aec83` (`feature/iq1-probation-promotion`)

## Question

Can the existing IQ1_S sidecar replace only a selected routed expert whose
authoritative IQ2 representation is truly cold on SSD, without degrading any
VRAM- or RAM-resident route?

## Protocol

Runner: `run_g107_iq1_cold_only.ps1`

Validated tag: `g107_iq1_cold_only_fallback_validated_n3`

- RTX 3060 12 GB, native Windows, CUDA 12.6.
- Main model: `C:\ds4-models\ds4-2bit.gguf`.
- IQ1_S sidecar: `C:\ds4-models\DeepSeek-V4-Flash-IQ1_S-XL.gguf`.
- Temp 0, no-think, 64 generated tokens, three requests in one process.
- Prefill-mass WRAP arena: 30 GiB / 4,551 expert slots.
- Request-scoped closed mass mask: 3,783 ranked entries plus 768 hash-seed
  entries in the arena candidate set.
- GPU expert cache: 320 entries; split-fused route path; tiering enforce,
  mass-LFRU.
- Cold-only rule: IQ1_S may be substituted only when the main IQ2 expert is
  classified as SSD cold and the exact IQ1_S representation is already in the
  RAM cache. Unknown residency and IQ1 cache misses fall back to all-main IQ2.
- Gate: structural safety and exactness. This is not an L0-L3 quality run.

Build manifest:

- source input fingerprint:
  `e3043854711f366693559a4f1cf05ec0f509244c52b0fc6aa7c6553b7b46e5d2`
- executable SHA-256:
  `8720ce9116b98e4b766d81423b3ec242cadc6517ac7e31725fd56c714fe159b3`

## Measured result

All three outputs were byte-identical to the expected baseline:

`31cbc6504dcb57d42aeff9dbceb3aed943bcb32dae19a2edbf552e9fd2f52eb8`

| Metric | Measured value |
| --- | ---: |
| server decode t/s | 4.47 / 4.48 / 4.50 |
| end-to-end seconds | 63.944 / 22.568 / 19.330 |
| mean server prefill/TTFT | 20.869 s |
| routed calls | 7,680 |
| selected routed experts | 46,080 |
| main VRAM routes | 17,439 |
| main snapshot-RAM routes | 28,641 |
| main tier-RAM routes | 0 |
| main SSD-cold routes | 0 |
| IQ1_S RAM hits | 0 |
| IQ1_S substitutions | 0 |
| all-main fallbacks | 7,680 |
| uncertain residency | 0 |
| failures | 0 |
| IQ2 snapshot-to-VRAM bytes | 227,030,335,488 |
| forbidden direct SSD-to-VRAM | 0 |

The requested 6 GiB IQ1_S cache remained deliberately unmaterialized because
there was no eligible route. The receipt records
`iq1_s_ram_cache_deferred_unused=true`.

## Decision

G107 proves the residency gate and all-main fallback are exact and fail closed.
It does not show a performance benefit because the SOTA-like closed mass mask
produced no SSD-cold selected route in any of the three requests.

The remaining transport cost in this protocol is RAM-to-VRAM: 28,641 routed
expert selections came from the 30 GiB IQ2 snapshot and transferred about
211.44 GiB in aggregate. Therefore the next compression experiment must target
the RAM-resident representation itself, not add an IQ1 stage only after an SSD
miss.

Q1_0 (1.125 bpw, 3.375 MiB per complete routed expert, 33.75 GiB for all routed
experts in layers 3..42) is the current candidate for that resident cold base.
Its runtime port must remain a separate, fail-closed path until selected-load
and qwarp kernels are validated.

## Artifacts

The complete result, raw output, HTTP checkpoint, stderr, runtime telemetry and
preflight receipts are stored under `g7_runs/` with the validated tag above.
