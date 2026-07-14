# G21: Windows cache-state discriminator and Q8-F16 safety gate

Date: 2026-07-14

## Questions

1. Why can the same native-Windows runtime alternate between about 0.4 and
   2.0 decode tokens/s without a source or executable change?
2. Does a bounded Q8-to-F16 fixed-tensor cache help the established warm-state
   configuration?

The model remains `ds4-2bit.gguf` in every run. `Q8-F16` is an optional VRAM
cache that expands eligible fixed Q8 tensors to F16. It does not change the
GGUF quantization and it does not expand the 2-bit MoE experts.

## Common protocol

| Parameter | Value |
|---|---:|
| HEAD | `5ed1e46f8f27e01afe8a1065824bfe690a9aa795` |
| Executable SHA-256 | `db610b50b6d4652b392c002e73849ff10b279e159425e94a325c11e365ca5180` |
| `ds4_cuda.cu` physical SHA-256 | `d222b3d46259d3984d5b12b3b9fac2c04fb223eef2030d10f50e6519a98cb4db` |
| Model | `C:\ds4-models\ds4-2bit.gguf` |
| Model bytes | 86,720,111,488 |
| GPU | RTX 3060 12 GiB, driver 596.21 |
| Prompt | `Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document.` |
| Prompt SHA-256 | `38f6ec5ee5403f59dd2418eb5d9a5a94a0f0da19df015060383bb1ae46003bb6` |
| Decode | greedy server default, 64 tokens |
| Context / prefill chunk | 256 / 256 |
| Raw / compressed KV rows | 256 / 66 |
| Dynamic pinned arena | 12 GiB, W16, min_hits=3 |
| Masked RAM budget / CUDA reserve | 2 GiB / 1,024 MiB |
| WRAP workers / MoE I/O queue | 8 / 1 |
| Expert cache / SPEX / overlap | off / off / off |
| Expected output SHA-256 | `fd6c4522975a71e252b90199d49cfe3236310e2a7285dc0fc4d0e9d0e4885510` |

Every run used a new server process. The harness cleared inherited `DS4_*`
variables, validated the build manifest and required the complete runtime,
WDDM, NVIDIA and memory-preflight telemetry.

## Cache-state discriminator

The following two processes ran consecutively with no rebuild. The first used
grow8 and populated a larger pinned arena; the immediately following process
disabled growth.

| Run | Grow interval | Decode t/s | TTFT s | Resident experts | Useful arena GiB | Hits / misses | Process read GiB | Exact output |
|---|---:|---:|---:|---:|---:|---:|---:|:---:|
| `cache_state_discriminator_grow8_n1` | 8 | 2.02 | 12.308 | 1,291 | 8.510 | 6,260 / 6,106 | 106.783 | yes |
| `cache_state_discriminator_postgrow_off_n1` | 0 | 2.05 | 15.494 | 439 | 2.894 | 4,247 / 8,119 | 120.336 | yes |

The second process remained fast despite losing the arena growth and its hit
rate. Session reconstruction confirms that no build occurred between the
earlier slow grow-off process, the grow8 process and the later fast grow-off
process. The memory preflight also records
`standby_purge.status=unavailable_not_installed`; Windows had about 35-37 GiB
of standby pages before these runs.

This is n=1 mechanism evidence, not a performance verdict. It establishes that
the prior G20 n=3 comparison measured a warm standby-cache state. It does not
establish cold-start throughput. A cold claim requires an observed successful
standby-list purge or a reboot-controlled protocol.

## Q8-F16 safety gate

The Q8 arm changed only:

```text
DS4_CUDA_Q8_F16_CACHE_MB=256
DS4_CUDA_Q8_F16_CACHE_RESERVE_MB=1280
```

It ran immediately after the 2.05 t/s warm-state control above.

| Metric | Warm control | Q8-F16 safety arm |
|---|---:|---:|
| Decode t/s | 2.05 | 0.38 |
| TTFT s | 15.494 | 15.563 |
| Server total s | 46.655 | 184.326 |
| Process read GiB | 120.336 | 614.023 |
| Arena resident experts | 439 | 446 |
| Arena hits / misses | 4,247 / 8,119 | 4,631 / 7,735 |
| Arena H2D GiB | 28.00 | 30.53 |
| WDDM shared peak GiB | 12.328 | 12.328 |
| WDDM dedicated peak GiB | 9.938 | 9.654 |
| NVIDIA VRAM peak MiB | 10,821 | 10,520 |
| GPU utilization median | 32% | 33% |
| Output expected hash | yes | no |

The runtime repeatedly dropped its model-tensor cache from roughly 7.6 GiB
while trying to honor the Q8-F16 allocation. The first 8 MiB expansion was
already rejected by the 1.25 GiB reserve. Decode fell to 0.38 t/s, process read
traffic reached 614.023 GiB and the greedy output hash changed.

The safety gate therefore rejects this Q8-F16 configuration. Per protocol it
was not repeated n=3: a hash mismatch plus a gross throughput collapse is a
fail-closed condition, not a candidate for promotion. This is not a claim that
every possible Q8-F16 budget is harmful; only this exact 256/1280 MiB arm was
measured.

## Measurement limitation fixed

The pre-G21 harness validated the expected hash before writing the result JSON.
Consequently this failed arm retained telemetry and stderr but not the actual
response body/hash. The expected-hash failure is known, but the differing hash
cannot be reconstructed and is recorded as `null` rather than inferred.

`g7_measure.ps1` now writes `g7_<tag>_raw_outputs.json` before any repeated- or
expected-hash assertion. Future failed safety arms retain their exact output,
hash and provenance.

## Artifacts

- Cache discriminator pairs: `g7_runs/g7_g21_cache_state_discriminator_*`
- Q8 failure record: `g7_runs/g7_g21_q8_cap256_reserve1280_postprime_safety_n1_failure.json`
- Q8 preflight, runtime telemetry and stderr:
  `g7_runs/g7_g21_q8_cap256_reserve1280_postprime_safety_n1_*`

## Next isolated step

Establish an explicit benchmark state contract before another runtime lever:

1. label every run `cold`, `primed` or `uncontrolled`;
2. for warm comparisons, execute and record the same fixed priming run before
   every independent replica;
3. for cold comparisons, require a successful standby purge or reboot marker;
4. never mix cache states inside an n>=3 verdict.
