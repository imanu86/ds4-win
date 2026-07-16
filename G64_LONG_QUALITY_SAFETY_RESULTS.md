# G64 Long-Quality Safety Gate

Date: 2026-07-16

## Scope

This receipt records the mandatory short `n=1` context-8192 safety gate for
the preregistered G64 long-output comparison. It is a capacity and structural
safety result only. It carries no throughput, TTFT, long-output quality or
G46-versus-K60 verdict.

## Command

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\g64_long_g46_full_vs_g63_k60.ps1 -SafetyOnly -MaxTokens 64 -Context 8192 -TimeoutSec 1800
```

- Runner commit: `4b4f64d`
- Runner SHA-256: `88e89c9eb87286a202706b2b27613c54b9192f8e7ae293ac67523d6247216bfa`
- Frozen first arm: `g46_full`
- Model: `C:\ds4-models\ds4-2bit.gguf`
- Prompt tokens observed by the server: `43`
- Sampling: temperature `0`, nothink
- Context buffers: `333.21 MiB` (`ctx=8192`, prefill chunk `2048`)

## Measured Result

The first `g46_full` safety arm failed closed during the initial WRAP arena
fill, before the first generated token. The K60 arm was not started.

- DynamicArena: `30.00 GiB`, `4551` slots, `6.75 MiB/slot`
- Arena transition reached: `base=0 target=1 resident=4551 loads=4551`
- Last server phase: WRAP fill; no decode began
- Runtime-monitor elapsed at abort: `59.873 s`
- Windows available memory at abort: `269,651,968 bytes` (`0.251 GiB`)
- Consecutive low-memory samples: `3`
- `contamination_abort`: `true`
- Process working set at abort: `41,910,218,752 bytes`
- Process private bytes at abort: `44,046,032,896 bytes`
- Process read transfer at abort: `36,265,349,863 bytes`
- Page faults at abort: `15,889,737`
- Disk queue length at abort: `13`
- Disk read rate at abort: `1,266,130,874 bytes/s`
- GPU utilization at abort: `0%`; dedicated VRAM: `10,847 MiB`
- Post-run: no `ds4_server` process remained and VRAM returned to baseline

The later harness message about RouteNoDefaultSync is secondary: the process
was terminated by the runtime contamination guard before any route call could
complete. It is not the root cause of this safety failure.

## Classification

Measured classification: **cold-source WRAP memory-capacity failure** for the
exact G46 composition at context 8192. The pre-registered memory guard remains
unchanged and correctly prevented paging from contaminating a long run.

The runner verifies the K60 payload before the frozen first G46 arm. That
verification reads retained K60 extents and can warm their source working set,
while the full-model G46 arm then starts from a different source-cache state.
Consequently this receipt must not be used for a fair startup/TTFT comparison,
and the earlier short G63 TTFT advantage remains a measured short-run result,
not a general cold-start claim.

## Next Gate

The isolated K60 safety arm below answered the original next-gate question.
Do not launch the six long quality rows until the shared WRAP capacity failure
and source-cache symmetry are resolved.

## Isolated K60 Safety

The runner was extended without changing DS4 flags or guards so one safety arm
could be selected independently.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\g64_long_g46_full_vs_g63_k60.ps1 -SafetyOnly -SafetyArm g63_k60 -MaxTokens 64 -Context 8192 -TimeoutSec 1800
```

- Runner commit: `ac518c7`
- Runner SHA-256: `8916be8882eb9dfd62b5fad449c299b134ccb41571d475dc888e87e9ea0953f1`
- Arm: `g63_k60`
- Model: `C:\ds4-models\ds4-2bit-k60-mass-full-decode.gguf`
- Preflight available memory after cleanup: `51,288,727,552 bytes`
- Embedded mask verified and installed: `4080` pruned experts across `40` layers
- Sparse runtime guards: retained `6928`, rejected `0`
- Sparse candidates skipped and replaced during compose: `1579`

The K60 arm also failed closed during the initial WRAP arena fill, before the
first generated token:

- DynamicArena: `30.00 GiB`, `4551` slots, `6.75 MiB/slot`
- Arena transition reached: `base=0 target=1 resident=4551 loads=4551`
- Runtime-monitor elapsed at abort: `56.458 s`
- Windows available memory at abort: `272,769,024 bytes` (`0.254 GiB`)
- Consecutive low-memory samples: `3`
- `contamination_abort`: `true`
- Peak process working set: `50,192,482,304 bytes`
- Peak private bytes: `44,099,170,304 bytes`
- Process read transfer: `33,894,227,872 bytes`
- Page faults at abort: `16,954,373`
- Peak disk queue length: `11`
- GPU utilization at abort: `0%`; dedicated VRAM: `10,838 MiB`
- Post-run: no `ds4_server` process remained and VRAM returned to baseline

This is a second `n=1` safety result, not a quality or throughput verdict. It
demonstrates that physically removing SSD payload alone does not solve the
context-8192 capacity gate while both arms still construct the same 30 GiB,
4551-slot runtime arena.

## Measured Comparison

| Safety arm | Abort elapsed | Available at abort | Process reads | Arena slots | First token |
|---|---:|---:|---:|---:|---:|
| G46 full | 59.873 s | 0.251 GiB | 36.265 GB | 4551 | no |
| G63 K60 | 56.458 s | 0.254 GiB | 33.894 GB | 4551 | no |

The next frozen experiment is an identical-arm capacity A/B with the existing
`ArenaWrapTrimBetweenPhases` enabled. That implementation trims between the
`gate`, `up` and `down` source-parts phases. If the unchanged guard still
aborts, the next implementation target is finer-grained trim after completed
source parts, before final snapshot publication, with per-trim memory and
latency telemetry.
