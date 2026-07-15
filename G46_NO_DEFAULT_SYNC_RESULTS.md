# G46 GPU-resident route handoff without default-stream sync

Date: 2026-07-15

Branch: `port/windows-dynamic-arena-0051`

Measured parent: `22d92af09df43cd5bb604ade5a66494eb8d7206f`

## Question

Can the GPU-resident route handoff omit its explicit
`cudaStreamSynchronize(0)` and rely on the existing mapped request sequence and
worker-ready publication without changing output, residency, or transport?

G46 is opt-in through:

```text
DS4_CUDA_MOE_ROUTE_NO_DEFAULT_SYNC=1
```

The default behavior is unchanged when the variable is absent. G46 changes no
mask, expert set, cache capacity, tier policy, prompt, or sampling parameter.

## Mechanism

The route worker still waits for the request sequence, performs every required
pinned-RAM H2D transfer, records completion, and publishes the worker-ready
sequence. The requesting thread still waits for that publication before using
the compact route tensor. The candidate removes only the earlier default-stream
synchronization before request publication.

Telemetry distinguishes both paths:

```text
default_sync=<calls> no_default_sync=<calls>
```

The harness rejects a run unless every GPU-resident route call is accounted for
by exactly one of those counters.

## Protocol

| Parameter | Value |
|---|---|
| Model | `C:\ds4-models\ds4-2bit.gguf` |
| Model bytes | 86,720,111,488 |
| GPU | RTX 3060 12 GB, WDDM |
| Context | 256 |
| Generated tokens | 64 |
| Expected SHA-256 | `31cbc6504dcb57d42aeff9dbceb3aed943bcb32dae19a2edbf552e9fd2f52eb8` |
| Independent processes | 3 per arm |
| Order | default A, no-sync A, no-sync B, default B, default C, no-sync C |
| Dynamic arena | 30 GiB, 4,551 expert entries |
| Snapshot | prefill-ranked, request-scoped closed |
| WRAP | `source-parts`, 8 workers, trusted worker FNV |
| Protected VRAM slots | 320, effective capacity required to equal request |
| Startup reserve | 1,024 MiB |
| Expert-cache reserve | 0.125 GiB |
| Q8-F16 cache | disabled |
| Tiering | enforce, mass-LFRU |
| Policy clock / budget | 430 route calls / 16 replacements |
| Minimum frequency / hysteresis | 3 / 1.25 |
| GPU-resident routes | enabled |
| Split hit/miss | disabled |
| REAP/SPEX dynamic prediction | disabled |

Prompt:

```text
Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document.
```

The 64-token output is an intentionally truncated deterministic prefix. This is
an exact transport/throughput protocol, not an L0-L3 document-quality verdict.

## Provenance

```text
HEAD: 22d92af09df43cd5bb604ade5a66494eb8d7206f
executable sha256: e48237f6696e8737a4e2bc21a2e75250207650e62fbf92a3377d51b3a7194080
ds4_cuda.cu sha256: a58c5ca99522212c7414fbb69f2372ef5aef7b3eb366eda06867b9cfb0293ca7
ds4.c sha256: 8fc9fb3ff9d79bc4139cfaa83930b735b007b140ce1ed6b3105f26b996b0e6d9
build manifest sha256: d493c6c71c143857057c6fbf8f1dac142f75f0bbada89ffab7f8e3b931156245
build input fingerprint: a681c0fed0a456b21de34e71e46c9cdb5254fe6a1e4424a5b5c622a25aae9a08
harness sha256: 0623a8b52dd59dab8621603c177b006aba53acdc02532af2f16ebcd696ac073b
pre-resume runner sha256: 9ee6f7258510acaa6d6c1fec092ac10a49893d2796d744eafe5667d87ba9f926
resume runner sha256: c2e23280c7099078fd93e00e913ea3444b570cc6094f484b3b4cd3641912b32f
```

Another Codex task briefly started three candidate-only tags named
`g46_no_default_sync_64_{a,b,c}`. They are retained as exploratory artifacts and
are not included in this verdict. It also stopped the first matrix coordinator
after the first two authoritative runs. `-Resume` was then added to the runner:
it revalidated the two complete per-run JSON files and executed the four missing
processes. The resume change affects orchestration only; all six authoritative
runs have identical binary, source, harness, model, prompt, hash and runtime
contract provenance.

## Results

| Metric | Default sync | No default sync | Delta |
|---|---:|---:|---:|
| Server decode, mean t/s | 4.4600 | 4.5633 | +2.32% |
| Server decode, median t/s | 4.46 | 4.58 | +2.69% |
| Decode seconds, mean | 14.348 | 14.021 | -2.28% |
| Route resolve, mean ms/call | 2.813 | 0.000 | moved out of caller |
| Worker-ready wait, mean ms/call | 1.615 | 4.446 | synchronization shifts here |
| Total handoff, mean ms/call | 4.428 | 4.446 | +0.41% |
| Route worker, mean ms/job | 1.631 | 1.621 | -0.57% |
| VRAM route hits, mean | 5,653 | 5,653 | identical |
| Pinned-RAM route hits, mean | 10,859 | 10,859 | identical |
| Pinned-RAM H2D, mean GiB | 71.5803 | 71.5803 | identical |
| VRAM peak, mean MiB | 11,517.0 | 11,514.7 | -2.3 MiB |
| Snapshot misses, sum | 0 | 0 | exact closed snapshot |
| SSD bytes, sum | 0 | 0 | unchanged |
| Tier/route failures, sum | 0 | 0 | unchanged |

Per-run decode throughput:

```text
default sync:    4.46, 4.46, 4.46 t/s
no default sync: 4.53, 4.58, 4.58 t/s
```

Every process produced the expected content hash. Default runs reported all
2,752 route calls in `default_sync`; candidate runs reported all 2,752 calls in
`no_default_sync`. No decode outlier is present. TTFT ranged from 37.113 to
54.283 seconds in the default arm and 42.915 to 46.425 seconds in the candidate
arm; none reproduces the 204-355 second post-WRAP stall measured in G45, so the
three-extra-run outlier rule was not triggered for G46.

The synchronization cost did not disappear: route resolve time moved into the
worker-ready wait. The measured decode gain therefore comes from removing the
default-stream-wide serialization point, not from reducing expert H2D work.

## Verdict

G46 is exact and positive on this controlled n=3 transport protocol. It raises
the current closed-snapshot/cache320 decode from 4.46 to 4.56 t/s without
changing selected experts, transport volume, residency, or SSD traffic.

Keep the path opt-in until it passes at least one cross-prompt exactness matrix.
The next transport work should target the 10,859 pinned-RAM routes and 71.58 GiB
of repeated H2D directly; eliminating this synchronization alone cannot deliver
the larger target gain.

## Command

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\g46_no_default_sync_ab.ps1
```

After an interrupted coordinator:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\g46_no_default_sync_ab.ps1 -Resume
```

## Primary artifacts

- `g46_no_default_sync_ab.ps1`
- `g7_runs/g46_no_default_sync_ab_result.json`
- `g7_runs/g7_g46_{default,nosync}_{a,b,c}_result.json`
