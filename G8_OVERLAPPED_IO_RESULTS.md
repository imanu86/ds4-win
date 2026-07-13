# G8 native-Windows selected-load I/O experiment

Date: 2026-07-13

## Scope

This experiment tests only concurrent Windows `ReadFile` submission for the
selected-expert fill. It reuses the four existing `cudaMallocHost` staging
buffers, leaves the final per-layer `cudaStreamSynchronize` in place, and is
disabled by default (`DS4_CUDA_MOE_IO_QD=1`).

Hardware/runtime:

- RTX 3060 12 GB, sm_86, WDDM
- native Windows CUDA 12.6; no WSL and no HMM
- model `C:\ds4-models\ds4-2bit.gguf`, 86,720,111,488 bytes
- host-register prefix budget 2 GiB; VRAM reserve 1024 MiB
- prompt `Hi`, greedy temperature 0, thinking disabled
- one discarded warmup followed by three measured requests

The final measured source, binary, and harness were:

- `ds4_cuda.cu`: `1808dcdda5294f2a8a23d4f2d41f9089d8b7c1b682c332a3ba9627aa476a318f`
- `ds4_server.exe`: `6cec0d9a7c6fee81dd2af86b326914e2974b8e219a060e25fd34ffe894ed74eb`
- `g7_measure.ps1`: `979324b577a3a67232d4ecb245069cbf7961a292a75b42307a2dbe572821356e`

## Protocol correction

The original harness divided requested tokens by wall time even when the model
stopped after 9 of the requested 12 tokens. It also enabled verbose per-layer
logging. The corrected harness uses API `usage.completion_tokens`, hashes every
output, separates warmup, requires explicit repeats, and can disable all
diagnostics.

Same `7f647e0` binary, same inputs:

| mode | n | mean end-to-end t/s | min-max | output |
|---|---:|---:|---:|---|
| clean | 3 | 2.042 | 2.002-2.110 | identical |
| diagnostics | 3 | 0.706 | 0.684-0.730 | identical |

The old `0.907 t/s` result was therefore not a clean steady-state baseline.
Instrumentation reduced measured end-to-end throughput by about 65% in this
controlled comparison.

## Queue-depth result

All queue-depth arms used the same newly built binary and produced the same
9-token output with SHA-256
`fda564ba3f7a0f028106d468420f674898ed99ac5bf2765ac9586206e39d73c5`.

| I/O QD | n | mean end-to-end t/s | min-max | mean server decode t/s |
|---:|---:|---:|---:|---:|
| 1 | 3 | 2.240 | 2.207-2.264 | 3.11 |
| 2 | 3 | 2.016 | 1.976-2.054 | 2.78 |
| 4 | 3 | 1.913 | 1.881-1.936 | 2.62 |

The harness observed the requested path in every QD2/QD4 arm and recorded zero
overlapped-I/O fallbacks. QD2 regresses by 10.0% and QD4 by 14.6% end to end
relative to the same-binary QD1 arm. The measured warm path does not
benefit from concurrent file submissions; page-cache hits plus the extra event
and overlapped-I/O bookkeeping are the likely mechanism, but that explanation is
an inference rather than a measured fact.

This is deliberately a warm-path result: the discarded warmup uses the same
greedy prompt as the measured requests. It does not establish cold-cache or
long-run tail behavior.

## Commands

```powershell
$cuda = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.6"
$cm = "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
& $cm --build build --config Release --parallel -- "/p:CudaToolkitDir=$cuda/"

powershell -NoProfile -ExecutionPolicy Bypass -File .\g7_measure.ps1 `
  -MaxTokens 12 -Repeats 3 -BudgetGB 2 -ReserveMB 1024 `
  -IoQD 1 -ModelPath "C:\ds4-models\ds4-2bit.gguf" -Warmup `
  -Tag qd_final3_qd1_clean_n3
```

The QD2 and QD4 arms change only `-IoQD` and the tag.

## Decision

Keep the overlapped path opt-in for reproducibility, but do not enable it in the
default recipe. The next measured lever should target a missing persistent
expert cache or the per-layer host synchronization, not more file queue depth.
