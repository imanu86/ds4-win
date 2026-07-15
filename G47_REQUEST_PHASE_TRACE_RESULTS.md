# G47 request-phase trace and overhead gate

Date: 2026-07-15

Branch: `port/windows-dynamic-arena-0051`

Measured parent: `b9fa97ff1686fc289c7f1020e499988efd3f04b4`

## Question

Can CPU-only monotonic timestamps localize request time around prefill, WRAP,
decode entry, and first token without changing exact output or materially
slowing the G46 path?

G47 is opt-in through:

```text
DS4_REQUEST_PHASE_TRACE=1
```

The default path emits no phase lines. G47 adds no GPU readback, CUDA event,
device allocation, or synchronization.

## Events

The server records request-local boundaries:

```text
prompt-start
session-sync-enter / session-sync-return
decode-enter
first-sample-enter / first-sample-return
first-eval-enter / first-eval-return
first-token-ready
request-end
```

The CUDA prefill finalizer records:

```text
prefill-finalize-enter / prefill-finalize-return
wrap-enter
wrap-copy-enter / wrap-copy-return
wrap-terminal
```

All timestamps use the existing CPU monotonic clock. The harness requires the
16 events exactly once and in order for this one-request protocol. It rejects a
trace-on run with missing, duplicate, out-of-order, or extra events, and rejects
any phase line in the trace-off arm.

Every early return after `prefill-finalize-enter` now emits the matching return
event. The current harness intentionally supports one non-warmup request with
prefill-mass WRAP and no KV-prefix sub-sync; multi-request and KV-prefix traces
remain outside this gate.

## Protocol

| Parameter | Value |
|---|---|
| Model | `C:\ds4-models\ds4-2bit.gguf` |
| Model bytes | 86,720,111,488 |
| GPU | RTX 3060 12 GB, WDDM |
| Context | 256 |
| Generated tokens | 64 |
| Expected SHA-256 | `31cbc6504dcb57d42aeff9dbceb3aed943bcb32dae19a2edbf552e9fd2f52eb8` |
| Primary order | off A, on A, on B, off B, off C, on C |
| Outlier recheck | off D, on D, on E, off E, off F, on F |
| Independent processes | 6 per arm total |
| Dynamic arena | 30 GiB, 4,551 expert entries |
| Snapshot | prefill-ranked, request-scoped closed |
| WRAP | `source-parts`, 8 workers, trusted worker FNV |
| Protected VRAM slots | 320, effective capacity required to equal request |
| Startup reserve | 1,024 MiB |
| Expert-cache reserve | 0 GiB for stable effective capacity 320 |
| Q8-F16 cache | disabled |
| Tiering | enforce, mass-LFRU |
| Policy clock / budget | 430 route calls / 16 replacements |
| Minimum frequency / hysteresis | 3 / 1.25 |
| GPU-resident routes | enabled, no-default-sync enabled |
| Split hit/miss | disabled |
| REAP/SPEX dynamic prediction | disabled |

Prompt:

```text
Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document.
```

The 64-token output is an intentionally truncated deterministic prefix. This is
an exact telemetry/overhead protocol, not an L0-L3 quality verdict.

## Capacity control

A final-binary safety run with the former 0.125 GiB expert-cache reserve reached
only 309 of 320 requested slots while WDDM had about 719 MiB in use at idle. It
was exact but excluded from the A/B matrix because the effective architecture
did not match G46.

An isolated safety run with reserve 0 reached 320/320 without OOM, preserved the
12-token expected hash, and reported zero SSD bytes and zero tier failures. Both
A/B arms therefore used reserve 0 and required effective capacity 320. This
restores the same actual protected-slot count as G46; it does not increase the
requested cache.

## Provenance

```text
HEAD: b9fa97ff1686fc289c7f1020e499988efd3f04b4
executable sha256: 3f8a15b56681d8a6a3d0294057793b430b5bd6641e9da4406055ec2f4e29cc7b
ds4_cuda.cu sha256: a69eea03c00d994ab9fd3a481705232f869c0b0a2bd6adf2e6fa3fd6571f8ba9
ds4.c sha256: 8fc9fb3ff9d79bc4139cfaa83930b735b007b140ce1ed6b3105f26b996b0e6d9
ds4_server.c sha256: 3358c8e053439306838763e5cac4774d40277a96e73e1f757a4a7cbffeb5c8c4
build manifest sha256: 4b2b5dfe729cf8987052c39c3210a9f697078f537a0fac2d221136b0a08c8d6c
build input fingerprint: 5a010749da6eb3018e7b0a20885f229dacd3aff28d6beaf82fb48f0cd681a87c
harness sha256: 401c171cb425622acefbe3c3a78168f23d05ca8222a43c166e02cf4eebe6b29a
primary runner sha256: 3a79f3ed397b9a6b5a8f882c556f2206be9efcc004357525685314fd3e24cc7b
recheck runner sha256: 10b5809195e9e36ccf29fa6d0cf1f08595b738c64f16baceff44040342457c29
```

The runner's `-Resume` path validates its tag and the current hashes of the
harness, sources, executable, and build manifest before accepting an existing
per-run JSON file.

## Overhead results

The primary n=3 matrix produced:

```text
trace off: 4.30, 4.50, 4.51 t/s
trace on:  4.35, 4.49, 4.48 t/s
```

The first sample in each arm was lower than the other two. Per the permanent
outlier rule, three additional independent processes were run for each arm:

```text
trace off recheck: 4.49, 4.50, 4.50 t/s
trace on recheck:  4.47, 4.46, 4.45 t/s
```

Combined n=6 per arm:

| Metric | Trace off | Trace on | Delta on vs off |
|---|---:|---:|---:|
| Server decode, mean t/s | 4.4667 | 4.4500 | -0.37% |
| Server decode, median t/s | 4.500 | 4.465 | -0.78% |
| Decode seconds, mean | 14.3277 | 14.3747 | +0.33% |
| TTFT, mean seconds | 45.3057 | 45.0570 | -0.55% |
| Client wall, mean seconds | 60.0401 | 59.8258 | -0.36% |
| Client wall, median seconds | 59.1633 | 59.6789 | +0.87% |

The direction changes across metrics and is below one percent. The measured
cost of the CPU-only trace is therefore small enough for controlled diagnostic
runs. It is not claimed to be zero.

All 12 processes produced the expected content hash. Every process had 5,653
VRAM route hits, 10,859 pinned-RAM route hits, 71.5803 GiB pinned-RAM H2D, zero
snapshot misses, zero SSD bytes, and zero tier/route failures.

## Phase results

Across the six trace-on processes:

| Phase | Mean seconds | Median | Min | Max |
|---|---:|---:|---:|---:|
| Prefill compute before finalize | 21.2525 | 21.0121 | 20.7459 | 22.1274 |
| WRAP timeline | 23.6924 | 23.3947 | 21.8956 | 25.7097 |
| WRAP copy | 23.6325 | 23.3387 | 21.8422 | 25.6526 |
| After WRAP to finalize return | 0.0055 | 0.0056 | 0.0047 | 0.0060 |
| Finalize return to sync return | 0.0065 | 0.0064 | 0.0060 | 0.0072 |
| Sync return to decode entry | 0.0171 | 0.0171 | 0.0159 | 0.0183 |
| First sample | 0.0119 | 0.0117 | 0.0102 | 0.0141 |
| First eval | 0.5318 | 0.5271 | 0.4754 | 0.6212 |
| Decode entry to first token | 0.5759 | 0.5685 | 0.5225 | 0.6618 |
| Prompt start to first token | 45.6148 | 45.5495 | 43.4833 | 47.6217 |

For normal runs, the measured time after WRAP terminal through session-sync
return is about 12 milliseconds on average. Normal TTFT is instead dominated by
prefill compute plus the 30 GiB WRAP copy.

No G47 process reproduced the earlier 200-370 second TTFT events. G47 therefore
does not identify the source of those intermittent outliers yet. It does show
that calling them a post-WRAP stall is unsupported for normal runs; the trace is
now ready to localize the next reproduced event by measurement.

## Verdict

G47 is exact and operational for the controlled one-request protocol. Its
measured overhead is below one percent on combined n=6, with unchanged routing,
residency, transport volume, and output.

Keep it opt-in. Enable it when investigating TTFT or WRAP anomalies, and disable
it for final performance verdicts unless a paired trace-off arm is present.

## Commands

Primary balanced matrix:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\g47_phase_trace_overhead_ab.ps1
```

Three-extra-process outlier recheck per arm:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\g47_phase_trace_overhead_ab.ps1 -OutlierRecheck
```

## Primary artifacts

- `g47_phase_trace_overhead_ab.ps1`
- `g7_runs/g47_phase_trace_overhead_ab_result.json`
- `g7_runs/g47_phase_trace_outlier_recheck_result.json`
- `g7_runs/g7_g47_trace_{off,on}_{a,b,c,d,e,f}_result.json`
