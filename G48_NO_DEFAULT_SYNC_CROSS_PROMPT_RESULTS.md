# G48 no-default-sync cross-prompt exactness

Date: 2026-07-15

Branch: `port/windows-dynamic-arena-0051`

Measured HEAD: `134a984c5ffe20703f2dcf63e50c8547d858119a`

## Question

Does the G46 no-default-sync route handoff preserve exact output beyond the
single cyberpunk HTML prefix used for its throughput A/B?

This is an exactness-only gate. It uses one independent process per arm and
prompt, makes no throughput verdict, and does not grade the intentionally
truncated 64-token outputs L0-L3.

## Protocol

Each case runs a default-sync reference followed by a no-default-sync candidate.
The candidate receives the reference content SHA-256 as
`ExpectedContentSHA256`; the runner also compares the full content and token
count case-sensitively.

Both arms retain the accepted G46/G47 architecture:

| Parameter | Value |
|---|---|
| Model | `C:\ds4-models\ds4-2bit.gguf` |
| Model bytes | 86,720,111,488 |
| GPU | RTX 3060 12 GB, WDDM |
| Context | 256 |
| Generated tokens | 64 |
| Dynamic arena | 30 GiB, 4,551 expert entries |
| Snapshot | prefill-ranked, request-scoped closed |
| WRAP | `source-parts`, 8 workers, trusted worker FNV |
| Protected VRAM slots | requested and effective 320 |
| Expert-cache reserve | 0 GiB |
| Q8-F16 cache | disabled |
| Tiering | enforce, mass-LFRU |
| GPU-resident routes | enabled |
| Request-phase trace | disabled in both arms |
| Split hit/miss and dynamic REAP/SPEX | disabled |

The three prompt shapes are an Italian explanation, a C function with overflow
handling, and a PostgreSQL aggregate query.

## Provenance

```text
HEAD: 134a984c5ffe20703f2dcf63e50c8547d858119a
executable sha256: 3f8a15b56681d8a6a3d0294057793b430b5bd6641e9da4406055ec2f4e29cc7b
ds4_cuda.cu sha256: a69eea03c00d994ab9fd3a481705232f869c0b0a2bd6adf2e6fa3fd6571f8ba9
ds4.c sha256: 8fc9fb3ff9d79bc4139cfaa83930b735b007b140ce1ed6b3105f26b996b0e6d9
ds4_server.c sha256: 3358c8e053439306838763e5cac4774d40277a96e73e1f757a4a7cbffeb5c8c4
build manifest sha256: 82ffeb831dfd86421f9f2722ef00f88b0fbccfc39c24e68172b4d3bbecf867d6
build input fingerprint: 5a010749da6eb3018e7b0a20885f229dacd3aff28d6beaf82fb48f0cd681a87c
harness sha256: 401c171cb425622acefbe3c3a78168f23d05ca8222a43c166e02cf4eebe6b29a
primary runner sha256: f4c7b42f8b14ed426710936761df0682c775aa51e67e25c3a13d35a65a7dab70
outlier-recheck runner sha256: 7f7a6fe8cfddd5c365533dddc7986afb2aa1e87fc48565ed67e707821d5046d0
```

## Exactness results

| Case | Expected/content SHA-256 | Default t/s | No-sync t/s | Exact |
|---|---|---:|---:|---:|
| Italian explanation | `c592c46ecb710dcd9eeb0f01dde6a47c09690e3c62543f40e3c25f5880ecdbab` | 4.55 | 4.66 | yes |
| C function | `0f0d1665eecb3e1266f95cf331266b0683a0f4afc2296abf083badf5e30b2944` | 4.43 | 4.58 | yes |
| PostgreSQL query | `3ed0b67ec5f801b5ff6c05f5e3a755f109d1470bae0eae7947724eadf76a521b` | 4.34 | 4.42 | yes |

The t/s columns are observations only. With `n=1` they do not support a
performance comparison.

Every pair had identical full output, completion count, route call count,
residency and transport between its two arms. All six authoritative processes
had 2,752 route calls, effective cache 320, zero snapshot misses, zero SSD bytes,
zero tier/route failures, and complete default/no-sync accounting.

The prompt-specific route populations were:

| Case | VRAM routes | Pinned-RAM routes | Pinned-RAM H2D |
|---|---:|---:|---:|
| Italian explanation | 6,669 | 9,843 | 64.8831 GiB |
| C function | 5,704 | 10,808 | 71.2441 GiB |
| PostgreSQL query | 4,825 | 11,687 | 77.0383 GiB |

G46 no-default-sync therefore passes this three-shape exactness gate. This does
not establish quality, stochastic equivalence, or a cross-prompt throughput
gain.

## Excluded context-512 attempt

The first C attempt used context 512. It completed exactly but WDDM allowed only
315 of 320 protected slots, so the runner rejected it before starting its
candidate pair. The excluded run had TTFT 53.173 s and WRAP 33.568 s. It remains
preserved as `g7_g48_c_function_default_result.json` and is not part of the G48
verdict.

## Reproduced WRAP outlier

The first Italian default-sync process had TTFT 332.473 s. Per the permanent
outlier rule, three additional identical default-sync processes were run with
the same expected hash.

| Process | TTFT | WRAP copy/timeline | TTFT minus WRAP | Decode t/s |
|---|---:|---:|---:|---:|
| Reference | 332.473 s | 267.330 / 267.347 s | 65.126 s | 4.55 |
| Recheck A | 47.327 s | 27.112 / 27.128 s | 20.199 s | 4.53 |
| Recheck B | 262.228 s | 145.234 / 145.254 s | 116.974 s | 4.35 |
| Recheck C | 45.348 s | 25.076 / 25.093 s | 20.255 s | 4.32 |

All four outputs and transport paths were identical: content SHA, 6,669 VRAM
routes, 9,843 pinned-RAM routes, 64.8831 GiB H2D, zero snapshot misses, zero SSD
and zero failures. The long runs did not perform more decode transport.

The two long processes read 23.485 and 22.272 GiB through Win32 process I/O and
reported 18.5 and 17.1 million page faults. The two normal rechecks read 22.335
and 22.210 GiB and reported 17.4 and 17.8 million page faults. The measured byte
and fault counts therefore do not explain the elapsed-time multiplier by
themselves.

The authoritative log places both long intervals after `[arena] begin` and
before `[arena] publish`; the WRAP profile attributes 267.330 and 145.234 s to
the source-parts copy. `TTFT - WRAP` also rises in the long runs, so the slowdown
is not confined to the WRAP workers. Decode remains in the normal range after
publication.

Two long events in this four-process series establish reproducibility, not a
population frequency. No causal attribution to WDDM, NVMe, antivirus, memory
compression or paging is made without a discriminating measurement.

## Verdict

G48 promotes G46 past the requested cross-prompt exactness gate while keeping it
opt-in. It also replaces the earlier vague "post-WRAP stall" with a measured
finding: the reproduced long events occur during prefill and source-parts WRAP,
with the largest measured interval inside the WRAP copy.

The next diagnostic should add per-worker WRAP progress/latency plus concurrent
Windows memory-pressure and I/O sampling. Do not optimize decode or SPEX in
response to this TTFT event; decode transport is unchanged after WRAP completes.

## Commands

Cross-prompt exactness:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\g48_no_default_sync_cross_prompt.ps1
```

Three-extra-process outlier recheck:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\g48_no_default_sync_cross_prompt.ps1 -OutlierRecheck
```

## Primary artifacts

- `g48_no_default_sync_cross_prompt.ps1`
- `g7_runs/g48_no_default_sync_cross_prompt_result.json`
- `g7_runs/g48_italian_default_outlier_recheck_result.json`
- `g7_runs/g7_g48_{italian_explanation,c_function_ctx256,postgres_query}_{default,nosync}_result.json`
- `g7_runs/g7_g48_italian_default_outlier_recheck_{a,b,c}_result.json`
