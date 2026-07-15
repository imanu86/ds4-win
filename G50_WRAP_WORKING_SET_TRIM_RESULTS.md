# G50 Windows WRAP working-set trim

Date: 2026-07-15

## Question

Can Windows release pageable mmap source pages between the `gate`, `up`, and
`down` source-parts WRAP phases, preserving the 30 GiB CUDA-pinned arena while
preventing the near-zero-available-RAM stalls measured in G48/G49?

The tested mechanism is deliberately opt-in. It is not a static domain mask.
The request-scoped candidate set is learned from the current prompt prefill.

## Change

`DS4_CUDA_ARENA_WRAP_TRIM_BETWEEN_PHASES=1` calls
`SetProcessWorkingSetSize(GetCurrentProcess(), (SIZE_T)-1, (SIZE_T)-1)` after
the `gate` and `up` worker joins. It is accepted by the harness only with the
three-phase `source-parts` schedule and trusted worker checksums.

Runtime telemetry reports calls, successes, failures, elapsed time, and the
last Win32 error. The default path does not call the API. Microsoft documents
that the `-1/-1` form removes as many pages as possible from the process
working set:

- https://learn.microsoft.com/en-us/windows/win32/api/memoryapi/nf-memoryapi-setprocessworkingsetsize
- https://learn.microsoft.com/en-us/windows/win32/api/psapi/nf-psapi-emptyworkingset

## Provenance

- Git HEAD before the G50 commit: `51ca565be5c861e3962c58d611dc5fbfe8bd9a76`
- Executable SHA256: `c652994a2fa86f87c0604a96e8d473c767850dde781f4bd4891ec307bd16bccf`
- `ds4_cuda.cu` SHA256: `ef742a9a208d23e622736ae8e5994f37bd196311eb19acf1431d71c3534e8e97`
- Measurement harness SHA256: `9ec229f0f0ece34be730c5f86ef015d8d70271e4b376b5becad03f6ae36a4024`
- Post-study harness with process-isolation gate SHA256: `c2505e10eb36b41a2a90342017dcb29810615fef576a90b9f9e1eb3975c14700`
- Build-manifest SHA256: `3f69d5a7b40a3348f92f96669836c55301e77da9a6397b39e1c18ab179141db5`
- Runner SHA256: `c3a5213fc383ce84ea23ae31077c74339633419ab4f8044edc488304a9db969a`
- Model: `C:\ds4-models\ds4-2bit.gguf` (86,720,111,488 bytes)
- Aggregate matrix: `g7_runs/g50_wrap_trim_ab_result.json`
- Aggregate matrix SHA256: `a6dcb05492aaf6917eb366b096a6f961d58a17901f235bc661dec8a0ca61ad21`

## Protocol

Base order: `off-a,on-a,off-b,on-b,off-c,on-c`, one fresh process per run.
The predeclared outlier rule was WRAP time greater than twice the combined
base median. Both arms triggered it, so three extra processes per arm were
planned. Five of six extensions completed. `on-x3` was stopped after sustained
100% disk activity made Windows unusable; it has no result row and is not
imputed.

```text
--cuda -c 256 -n 8 --host 127.0.0.1 --port 8000
BudgetGB=2 ReserveMB=1024 DynamicArenaGiB=30
ArenaWrapSourceParts=1 ArenaWrapTrustWorkerChecksum=1
DisableQ8F16Cache=1 EmbedRowStaging=1
PrefillMassWrap=1 ComposePrefillMassTiering=1
ExpertCacheN=320 ExpertCacheReserveGB=0 ExpertCachePolicy=lru
GpuResidentRoutes=1 RouteNoDefaultSync=1
ExpertTiering=enforce ExpertTierPolicy=mass-lfru
ExpertTierClockCalls=430 ExpertTierReplacementBudget=16
ExpertTierMinFrequency=3 ExpertTierHysteresis=1.25
RequestPhaseTrace=1 ReapPrefetchThreads=8
temperature=0 nothink=true
```

The on arm additionally uses `ArenaWrapTrimBetweenPhases=1`.

Prompt:

```text
Rispondi in italiano con quattro punti numerati: spiega la differenza tra RAM,
VRAM e memoria virtuale. Sii conciso.
```

## Process isolation audit

The 11 completed measurements used 11 distinct `ds4_server.exe` PIDs. Runtime
telemetry intervals were checked chronologically and none overlapped the
previous process. Starts were separated from the previous telemetry end by
approximately 6-8 seconds, except the intentionally delayed `on-c` start.

After the operator interruption, the entire G50 process tree was stopped and
the machine returned to 51.8 GiB available RAM with no DS4 listener or CUDA
compute process. A post-study harness gate now:

1. acquires `Local\DS4_G7_MEASUREMENT_LOCK` non-blockingly;
2. fails closed if another `ds4_server.exe`, `g7_measure.ps1`, or
   `g7_runtime_monitor.ps1` process is present;
3. records the process-isolation preflight in each future result.

The mutex rejection path was tested with a separate holder process and refused
the second harness before model launch.

## Exactness and transport

All 11 completed runs produced the same eight-token byte sequence and content
SHA256 `b78be49a2b62f691ee8a8b5b486b2735275cc85bbbc98ee3102c06116487a5e8`.
Every completed on run reported two successful trim calls, zero failed calls,
and Win32 error zero. Every completed run retained zero SSD bytes, snapshot
misses, route errors, and tier failures. Decode results are therefore exact for
this narrow eight-token check; this is not an L0-L3 quality verdict.

## Results

| Run | Trim | Load s | Prefill s | WRAP s | TTFT s | Decode t/s | Trim s | Available min GiB | WS peak GiB |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| off-a | off | 10.175 | 18.488 | 29.843 | 48.526 | 3.58 | 0 | 0.225 | 51.205 |
| on-a | on | 10.131 | 19.596 | 23.197 | 42.989 | 3.57 | 3.441 | 9.003 | 38.064 |
| off-b | off | 10.166 | 18.210 | 28.577 | 47.001 | 3.65 | 0 | 0.001 | 49.808 |
| on-b | on | 9.623 | 19.729 | 23.406 | 43.354 | 3.56 | 3.584 | 9.085 | 38.865 |
| off-c | off | 10.737 | 20.155 | 166.866 | 187.257 | 3.28 | 0 | 0.147 | 49.186 |
| on-c | on | 110.010 | 171.330 | 89.542 | 261.102 | 3.46 | 3.362 | 6.762 | 38.893 |
| off-x1 | off | 9.719 | 19.489 | 27.350 | 47.043 | 3.67 | 0 | 0.231 | 49.705 |
| off-x2 | off | 9.702 | 20.139 | 27.793 | 48.152 | 3.72 | 0 | 0.188 | 51.096 |
| off-x3 | off | 10.284 | 20.225 | 25.079 | 45.526 | 3.67 | 0 | 0.003 | 51.427 |
| on-x1 | on | 9.703 | 20.046 | 23.235 | 43.489 | 3.70 | 3.454 | 7.830 | 38.396 |
| on-x2 | on | 9.667 | 20.418 | 372.042 | 392.781 | 3.41 | 3.387 | 8.933 | 38.975 |

Base n=3 WRAP mean/median:

- off: 75.095 / 29.843 seconds;
- on: 45.382 / 23.406 seconds.

Expanded completed-process WRAP mean/median:

- off n=6: 50.918 / 28.185 seconds;
- on n=5: 106.284 / 23.406 seconds.

The normal-case median improves, but the candidate has a 372.042-second WRAP
tail. It also causes approximately 20.3-21.3 million page faults per completed
on process, versus 17.0-18.7 million in the off arm.

`on-c` separately measured a 110.010-second load and 171.330-second prefill
before its 89.542-second WRAP. `on-x2` had a normal 9.667-second load and
20.418-second prefill, proving its 372.042-second tail was inside WRAP.
`on-x3` had already measured a 139.586-second startup-cache preparation before
the operator stopped it for sustained disk saturation; it is retained as an
interrupted system-impact observation, not a performance sample.

## Measured conclusion

**Reject global working-set trim as a runtime lever.** It frees enough pageable
memory to raise the normal available-RAM minimum from nearly zero to roughly
8-9 GiB and lowers normal WRAP latency, but it indiscriminately evicts mmap
source pages and other process pages needed by subsequent phases. The result is
catastrophic repaging, long WRAP tails, sustained 100% disk activity, and an
unusable host.

The two Win32 API calls themselves take only about 3.4-3.6 seconds. The
372-second failure is therefore downstream copy/page-in time, not API call
latency.

G50 does not establish a causal explanation for every historical startup or
prefill tail. It does establish that a whole-process working-set purge is too
broad. Any follow-up must be range-selective and must demonstrate bounded disk
traffic before a full model run. The G50 switch remains default-off and must
not be enabled in normal launch recipes.
