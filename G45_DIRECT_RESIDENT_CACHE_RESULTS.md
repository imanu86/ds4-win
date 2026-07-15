# G45 protected direct-resident cache coverage

Date: 2026-07-15

Branch: `port/windows-dynamic-arena-0051`

Measured parent: `a8e48d7c4872e406f5f5a3764d45660315a0f687`

## Question

Does increasing the protected direct-resident expert set reduce pinned-RAM H2D
traffic and improve a longer decode while preserving exact output, the
request-scoped closed snapshot, and zero SSD traffic?

G45 changes only:

```text
DS4_CUDA_STREAMING_EXPERT_CACHE_N=256 -> 320
```

Both arms use the same 0.125 GiB cache reserve, 30 GiB pinned host snapshot,
source-parts WRAP, mass/LFRU policy, prompt, context, binary and expected output
hash.

## Capacity gate

The requested cache size is not necessarily the effective size under WDDM.
The runtime limits the allocation from the free dedicated VRAM observed when
the cache is created. G45 therefore treats an effective capacity different
from the requested capacity as a failed protocol, not as another sample of the
same arm.

Exploration measured:

| Tag | Requested | Reserve GiB | Effective | Status |
|---|---:|---:|---:|---|
| `g45_cache336_safety_n1` | 336 | 0.5 | 284 | capacity gate only |
| `g45_cache384_reserve0125_safety_n1` | 384 | 0.125 | 341 | capacity gate only |
| `g45_cache336_reserve0125_long64_candidate_n1` | 336 | 0.125 | 336 | exact n=1 |
| `g45_cache336_a` | 336 | 0.125 | 336 | exact, aborted matrix |
| `g45_cache336_b` | 336 | 0.125 | 321 | rejected; matrix stopped |
| `g45_cache320_reserve0125_long64_safety_n1` | 320 | 0.125 | 320 | exact safety gate |

The two consecutive 336 attempts produced different effective capacities.
This makes 336 unsafe as a reproducible RTX 3060 configuration. The controlled
A/B uses 320, which was granted in the safety gate and all three candidate
replicas.

The rejected 336 artifacts are retained. They are mechanism evidence only and
are not mixed into the throughput verdict.

## Protocol

| Parameter | Value |
|---|---|
| Model | `C:\ds4-models\ds4-2bit.gguf` |
| Model bytes | 86,720,111,488 |
| GPU | RTX 3060 12 GB, WDDM, driver 596.21 |
| Prompt | cyberpunk single-file HTML request below |
| Context | 256 |
| Generated tokens | 64 |
| Sampling | deterministic server path |
| Expected SHA-256 | `31cbc6504dcb57d42aeff9dbceb3aed943bcb32dae19a2edbf552e9fd2f52eb8` |
| Independent processes | 3 per arm |
| Order | 256 A, 320 A, 320 B, 256 B, 256 C, 320 C |
| Dynamic arena | 30 GiB, 4,551 expert entries |
| Snapshot | prefill-ranked, request-scoped closed |
| WRAP | `source-parts`, 8 workers, trusted worker FNV |
| Startup reserve | 1,024 MiB |
| Expert-cache reserve | 0.125 GiB in both arms |
| Q8-F16 cache | disabled |
| Tiering | enforce, mass-LFRU |
| Policy clock | 430 route calls |
| Replacement budget | 16 |
| Minimum frequency | 3 |
| Hysteresis | 1.25 |
| GPU-resident routes | enabled |
| Split hit/miss | disabled |
| REAP/SPEX dynamic prediction | disabled |

Prompt:

```text
Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document.
```

The 64-token output is intentionally a truncated deterministic prefix. G45
tests transport exactness and decode throughput; it does not claim a complete
HTML document or an L0-L3 quality result.

## Provenance

```text
executable sha256: 801ea8ff8531245ff3083d71cdc5b5b55b93f0b1dc4904bee30d24d0dd653026
ds4_cuda.cu sha256: be4103d78f05d0f565cf2103b0d93b2c04f517e1ac7ebd057951c6db67d34063
build manifest sha256: 100abc59ee94c04a4399a91f567235c7f341f5fca004985290a74e53c99a5fd6
build input fingerprint: 752b0f3035f44c205e1cdf104b07c078b79a29594100481c7d60f90762b130c8
harness sha256: 235d4220e3903425ae55c32cec950a01a58bf601f6b55d80c2784995aa069533
execution runner sha256: 23699ea6251ad4bffb5e03d077de0fdfa9be9095c55ac15171e680463132a31d
corrected summary runner sha256: c9ceca6fc95467bd76ec65ecf9c4644a7470fb6108cf93da25214b7980629ad7
```

The build manifest reports a dirty worktree because untracked build and run
artifacts are present. All six runs nevertheless agree on HEAD, executable,
source, manifest, harness and model provenance. No tracked source changed
between replicas.

The first summary exposed a PowerShell median-index bug: converting `3 / 2` to
`int` selected index 2 instead of index 1. The runner was corrected and the
summary was regenerated from the same six authoritative per-run JSON files
with `-SummarizeExisting`. Both runner hashes are recorded above. No runtime
measurement was repeated or altered for that correction.

## Results

### Controlled A/B, n=3 independent processes per arm

| Metric | 256 protected | 320 protected | Delta |
|---|---:|---:|---:|
| Server decode, mean t/s | 4.4367 | 4.4767 | +0.90% |
| Server decode, median t/s | 4.44 | 4.48 | +0.04 t/s |
| Decode seconds, mean | 14.4247 | 14.2963 | -0.89% |
| Pinned-RAM H2D, mean GiB | 75.0344 | 71.5803 | -3.4541 GiB (-4.60%) |
| VRAM route hits, mean | 5,129 | 5,653 | +524 |
| Pinned-RAM route hits, mean | 11,383 | 10,859 | -524 (-4.60%) |
| All-hit route calls, mean | 14 | 19 | +5 |
| Worker time, ms/job | 1.6853 | 1.6207 | -3.84% |
| Worker-ready wait, ms/call | 1.6727 | 1.6047 | -4.07% |
| VRAM peak, mean MiB | 11,076.0 | 11,517.3 | +441.3 MiB |
| TTFT, median seconds | 44.604 | 44.754 | +0.150 s |
| WRAP, median seconds | 23.084 | 24.640 | +1.556 s |
| Snapshot misses, sum | 0 | 0 | exact closed snapshot |
| SSD bytes, sum | 0 | 0 | unchanged |
| Tier/route failures, sum | 0 | 0 | unchanged |

Per-run decode throughput was tightly grouped:

```text
cache 256: 4.44, 4.44, 4.43 t/s
cache 320: 4.48, 4.48, 4.47 t/s
```

The transport counters are deterministic for a given capacity across all
three replicas. The 64 extra slots replace exactly 524 pinned-RAM routes with
VRAM hits over 64 generated tokens and remove 3.454 GiB of H2D traffic.

### TTFT outlier

`g45_stable_cache256_c` reported 377.736 seconds TTFT while decode remained
4.43 t/s. The source-parts WRAP inside that request was only 23.084 seconds:

```text
prompt start 13:44:20
arena WRAP profile total 23.084 s
prompt done 13:50:37 (377.719 s)
decode 64 tokens 14.438 s
```

The stall is therefore outside the measured WRAP interval and before the first
token. Current telemetry does not localize it further; it is recorded as an
unlocalized prefill/WDDM stall. The TTFT mean is not used for the cache verdict.

## Verdict

320 protected expert slots are the best measured reproducible capacity for the
current RTX 3060 configuration. The A/B is exact, SSD-free and replicated. It
provides a small but consistent decode gain (+0.90%) and a larger direct
mechanism improvement (-4.60% pinned-RAM H2D) at a cost of about 441 MiB more
peak VRAM.

Do not use 336 as the default: WDDM granted 336 in one process and only 321 in
the next. Do not infer HTML quality from this 64-token exactness protocol.

The next ranked transport lever is not the old G33 split flag unchanged. G33
was exact but throughput-neutral because it added masked launches and a final
scratch sum. The next isolated experiment should remove the redundant default
stream synchronization in the GPU-resident route handoff, relying on the
already existing mapped request sequence plus worker-ready publication. It
must remain opt-in and pass exact safety before an n=3 A/B.

## Command

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\g45_direct_resident_cache_ab.ps1
```

Summary-only validation after the median fix:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\g45_direct_resident_cache_ab.ps1 `
  -SummarizeExisting `
  -ExecutionRunnerSHA256 23699ea6251ad4bffb5e03d077de0fdfa9be9095c55ac15171e680463132a31d
```

## Primary artifacts

- `g45_direct_resident_cache_ab.ps1`
- `g7_runs/g45_direct_resident_cache_ab_result.json`
- `g7_runs/g7_g45_stable_cache{256,320}_{a,b,c}_result.json`
- matching raw outputs, stderr logs, runtime telemetry and memory preflight JSON
- rejected-capacity tags listed in the capacity gate table
