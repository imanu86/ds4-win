# G32 GPU-resident route resolver and exact miss worker

Date: 2026-07-15

Branch: `port/windows-dynamic-arena-0051`

Parent commit: `dbc7e1e3876065aa755068675594ae42537b748b`

## Question

Can decode keep resident routed experts in persistent VRAM slots and execute
directly from those slots, while resolving only exact misses through a separate
host worker, without changing model output?

The G32 toggle is:

```text
DS4_CUDA_MOE_GPU_RESIDENT_ROUTES=1
```

The harness exposes it as `-GpuResidentRoutes`. It is off by default and is
gated away from SPEX, layer-top1, dynamic-arena observation, prefill-mass
observation, REAP-mass observation and non-decode (`n_tokens != 1`) paths.

## Implemented mechanism

1. Keep a device map from `(layer, expert_id)` to a persistent cache slot.
2. Resolve the six exact router IDs on GPU into 18 direct gate/up/down pointers.
3. Publish exact misses through a small mapped host mailbox.
4. Read missing IQ2XXS experts from the model into pinned host staging.
5. Upload misses on a nonblocking stream, update the device map and direct route
   pointers, then publish completion.
6. Execute all six exact routes through the existing pointer kernels. Router IDs
   and weights remain authoritative; G32 does not predict or alter the mask.

The currently working Windows path synchronizes the default stream after
the resolver, then waits on the exact miss worker. This preserves correctness
but does not remove the per-layer WDDM synchronization tax.

The wait is bounded to five seconds. A completed worker job that reports a
read/upload failure invalidates the whole expert cache and falls back to the
existing selected-load path. A lost/stalled worker or resolver synchronization
error remains fail-closed because concurrent cache mutation cannot be repaired
safely while the worker state is unknown.

## Rejected synchronization mechanisms

### GPU spin kernel

A one-thread kernel waiting on a completion sequence deadlocked. The resolver
published `seq=1 layer=1 misses=6`, but the upload-stream publication could not
run while the wait kernel occupied the WDDM queue. Evidence:

- `g7_runs/g7_g32_gpu_routes_debug_n1_stderr.log`
- `g7_runs/g7_g32_gpu_routes_flushfix_safety_n1_stderr.log`

### CUDA driver stream memory wait

`CU_DEVICE_ATTRIBUTE_CAN_USE_STREAM_MEM_OPS_V1` returned zero on the RTX 3060
under WDDM (driver 596.21). The opt-in therefore fell back and the harness
correctly reported `requested=true`, `observed=false`. Evidence:

- `g7_runs/g7_g32_streamwait_debug_n1_result.json`
- `g7_runs/g7_g32_streamwait_debug_n1_stderr.log`

### Ordered host callback

The resolver completed and the worker observed `seq=1 layer=1 misses=6`, but
CUDA work submitted by the worker did not advance while the ordered host
callback was pending. The run was terminated rather than treated as a result.
Evidence:

- `g7_runs/g7_g32_hostgate_debug_n1_stderr.log`

These are mechanism failures, not performance samples.

## Exactness gate

The working synchronous fallback produced the same greedy output in the
off/on safety pair:

```text
Hello! How can I help you today?
```

SHA-256 for both outputs:

```text
fda564ba3f7a0f028106d468420f674898ed99ac5bf2765ac9586206e39d73c5
```

The primed `n=3` runs also enforced this hash for warmup and every measured
request.

## Primed n=3 A/B

Common configuration:

| Parameter | Value |
|---|---|
| Model | `C:\ds4-models\ds4-2bit.gguf` (86,720,111,488 bytes) |
| GPU | RTX 3060 12 GB, WDDM, driver 596.21 |
| Prompt | `Hi` |
| Sampling | greedy/default server path; output hash enforced |
| Context | 256 |
| Max tokens | 12 (EOS after 9 generated tokens) |
| Warmup | same prompt and 12-token cap, discarded |
| Repeats | 3 measured requests |
| Expert cache | 336 slots, LRU, 0.5 GiB reserve |
| Stream window | 2 GiB |
| Startup/runtime reserve | 4096/128 MiB |
| Q8-F16 cache | disabled |
| Embedding row staging | enabled |
| REAP/SPEX/dynamic arena | disabled |

Results:

| Variant | Server decode t/s mean | Client end-to-end t/s mean | Exact | G32 observed |
|---|---:|---:|---|---|
| off | 3.273 | 2.1625 | yes | no |
| on | 3.223 | 2.0720 | yes | yes |
| delta | -1.53% | -4.19% | unchanged | - |

G32 on-path totals include the discarded warmup plus three measured requests:

| Counter | Measured value |
|---|---:|
| layer calls | 1,512 |
| exact expert routes | 9,072 |
| resident route hits | 3,832 (42.24%) |
| miss experts | 5,240 (57.76%) |
| all-hit layers | 12 (0.79%) |
| worker jobs | 1,500 |
| worker errors | 0 |
| resolver synchronization | 2.629 ms/call |
| ready/worker wait | 3.747 ms/call |
| worker duration | 3.779 ms/job |

Commands:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\g7_measure.ps1 `
  -MaxTokens 12 -Repeats 3 -Warmup `
  -Tag g32_syncworker_off_hi12_primed_n3 -Prompt Hi -Context 256 `
  -BudgetGB 2 -ReserveMB 4096 -RuntimeReserveMB 128 `
  -ExpertCacheN 336 -ExpertCacheReserveGB 0.5 -ExpertCachePolicy lru `
  -DisableQ8F16Cache -EmbedRowStaging `
  -ExpectedContentSHA256 fda564ba3f7a0f028106d468420f674898ed99ac5bf2765ac9586206e39d73c5 `
  -ExpectedWarmupContentSHA256 fda564ba3f7a0f028106d468420f674898ed99ac5bf2765ac9586206e39d73c5 `
  -ModelPath C:\ds4-models\ds4-2bit.gguf

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\g7_measure.ps1 `
  -MaxTokens 12 -Repeats 3 -Warmup `
  -Tag g32_syncworker_on_hi12_primed_n3 -Prompt Hi -Context 256 `
  -BudgetGB 2 -ReserveMB 4096 -RuntimeReserveMB 128 `
  -ExpertCacheN 336 -ExpertCacheReserveGB 0.5 -ExpertCachePolicy lru `
  -DisableQ8F16Cache -EmbedRowStaging -GpuResidentRoutes `
  -ExpectedContentSHA256 fda564ba3f7a0f028106d468420f674898ed99ac5bf2765ac9586206e39d73c5 `
  -ExpectedWarmupContentSHA256 fda564ba3f7a0f028106d468420f674898ed99ac5bf2765ac9586206e39d73c5 `
  -ModelPath C:\ds4-models\ds4-2bit.gguf
```

Final measured binary:

```text
executable sha256: b34e4636f8da7895928aa0a88dedb7bc16baf92ffed70f23e63ef67061b6cc06
build input fingerprint: 031a0de910d2328204607a04ce4fd660d3528e4ff20407fb757a6505b253182a
```

Primary artifacts:

- `g7_runs/g7_g32_syncworker_off_hi12_primed_n3_result.json`
- `g7_runs/g7_g32_syncworker_off_hi12_primed_n3_raw_outputs.json`
- `g7_runs/g7_g32_syncworker_off_hi12_primed_n3_stderr.log`
- `g7_runs/g7_g32_syncworker_on_hi12_primed_n3_result.json`
- `g7_runs/g7_g32_syncworker_on_hi12_primed_n3_raw_outputs.json`
- `g7_runs/g7_g32_syncworker_on_hi12_primed_n3_stderr.log`

## Verdict

The direct-slot and exact-worker mechanism is correct, but this synchronous
WDDM realization is not a throughput win at 336 slots. It remains opt-in. The
small regression is measured at `n=3`; the failed spin/wait/callback variants
are recorded only as mechanism failures.

The central finding is structural: a 42.24% per-route hit rate produces only
0.79% all-hit layers. A conditional fast path cannot pay while nearly every
layer still needs at least one cold expert and WDDM cannot express the desired
device-side wait with CUDA stream memory operations.

## Next step

Do not add more policy to this path yet. The next isolated transport experiment
should be one of:

1. split hit and miss execution so resident routes start before exact misses;
2. evaluate a WDDM-native external-fence primitive (for example a D3D12 shared
   fence imported as a CUDA external semaphore) before implementing it broadly;
3. increase all-hit-layer probability through measured residency selection,
   without changing the exact router or composing REAP/SPEX in the same A/B.
