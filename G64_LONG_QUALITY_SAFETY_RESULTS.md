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

Run a K60-only context-8192 safety arm to determine whether the physically
sparse source can complete the same 30 GiB WRAP without crossing the unchanged
memory guard. This remains `n=1` safety evidence only. Do not launch the six
long quality rows until both capacity and source-cache symmetry are resolved.

