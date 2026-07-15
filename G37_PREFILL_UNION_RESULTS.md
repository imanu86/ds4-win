# G37: Existing Prefill Union and Chunk Amplification

Date: 2026-07-15  
Hardware: RTX 3060 12 GiB, native Windows/WDDM, 64 GiB host RAM  
Branch: `port/windows-dynamic-arena-0051`  
Measured base HEAD: `b1ef49c5c8208f7a74a965545a34dde8468a6721`

## Question

Does the native CUDA prefill path already load every routed expert once per
layer/chunk, and how much extra transport is caused by splitting one prompt into
smaller chunks?

## Code finding

The first half was already implemented. `cuda_moe_selected_load()` reads all
`n_tokens * top_k` selected IDs, builds one ascending compact union for the
current layer/chunk, and remaps every route slot to that union. Therefore the
same expert is not loaded twice inside one layer/chunk. Reloads can still occur
when the next chunk reaches the same layer after traversing all 42 MoE layers.

G37 adds only opt-in measurement:

```text
DS4_CUDA_PREFILL_UNION_STATS=1
```

It reports route slots, unique experts, logical source span bytes, arena H2D,
cache D2D, and upload syncs. `g7_measure.ps1` now also accepts
`-PrefillChunk -1|0|N`, where `-1` keeps the runtime default and `0` explicitly
requests one full-prompt batch.

## Protocol

Common configuration:

| Parameter | Value |
|---|---|
| Model | `C:\ds4-models\ds4-2bit.gguf` |
| Model size / mtime | 86,720,111,488 bytes / `2026-07-04T05:29:32.5463725Z` |
| Prompt | Cyberpunk single-file HTML request, 43 prompt tokens |
| Context / generation | 256 / max 1, greedy no-think server path |
| Expected output | `Here` |
| Expected SHA-256 | `aa3b17600d88d3161605db8389b5bf03d4e94debcc8eeb74dca27aed95a154ab` |
| Expert cache | 336 slots, LRU, GPU-resident decode routes |
| Stream budget | 2 GiB; reserve 4096 MiB; runtime reserve 128 MiB |
| Other toggles | Q8-F16 off; embed-row staging on; I/O QD 1 |
| Isolated off | tiering, dynamic arena, REAP/masks, SPEX, split hit/miss, overlap |
| Repetition | one discarded warmup plus `n=3` measured requests per process |

The runner first used counter-order `stats-off / stats-on / stats-on /
stats-off` at full chunk. It then used `full / 16 / 8 / 16 / full`. All nine
processes shared identical executable, source, build-manifest, harness and model
provenance before aggregation.

Command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\g37_prefill_union_sweep.ps1
```

## Results

Telemetry overhead:

| Arm | Mean prefill/TTFT | Client t/s |
|---|---:|---:|
| Stats off | 7.557166 s | 0.106116 |
| Stats on | 7.541334 s | 0.106112 |
| Delta | -0.015832 s (-0.209%) | -0.004% |

Chunk sweep; counters include the warmup and three measured requests in each
process. Full and chunk-16 are means of two counter-ordered processes; chunk-8
is one process containing `n=3` measured requests but has no second process or
counter-order replication.

| Chunk | TTFT | Unique expert-unions | Dedup ratio | Logical source spans | Win32 process reads | Upload syncs | Max union |
|---:|---:|---:|---:|---:|---:|---:|---:|
| full (43) | 7.547166 s | 11,764 | 3.684x | 77.506 GiB | 123.781 GiB | 168 | 145 |
| 16 | 8.609167 s | 17,956 | 2.414x | 118.263 GiB | 125.175 GiB | 504 | 82 |
| 8* | 10.392667 s | 22,632 | 1.915x | 149.087 GiB | 155.399 GiB | 1,008 | 46 |

Relative to full chunk:

- chunk 16: unique unions +52.64%, logical source spans +52.59%, TTFT +14.07%;
- chunk 8: unique unions +92.38%, logical source spans +92.35%, Win32 process
  reads +25.54%, TTFT +37.70%.

`*` The chunk-8 deltas are a single-process, `n=3` observation and are not a
counter-ordered verdict. They are directional evidence for amplification; the
full and chunk-16 arms carry the replicated comparison.

All 27 measured outputs and all nine warmups matched the expected hash. The two
preceding `n=1` mechanism smokes also matched but are not used for the performance
verdict.

## Interpretation

This closes P4-A as a code and measurement finding: per-layer/chunk batch-union
already exists and is exact. The remaining redundancy is across chunks. Larger
chunks materially reduce repeated expert unions, logical selected-loader traffic
and synchronization on this 43-token prompt.

`source_span_bytes` is a logical selected-loader byte count, not a claim about
physical SSD traffic. The Win32 process counter excludes mmap page-ins and also
contains non-expert process reads. Both are retained because they answer
different questions.

This result justifies a separate P4-B design: use expert waves only when a wider
prompt batch would exceed the available compact staging capacity. Waves must
preserve the wide chunk's single union while bounding staging VRAM and summing
partial expert outputs exactly. They should not be added to a prompt whose full
union already fits, because that would add launches without removing a reload.

## Provenance

| Artifact | SHA-256 |
|---|---|
| `ds4_cuda.cu` | `3793eff0b8bf910054663c919feab13be938e29bdcbd5a5cf90181ebe38636bc` |
| `g7_measure.ps1` | `2e9183693ccb4cd8070a8832571724762860d77607bdc7dc2e9a5096899c860b` |
| `g37_prefill_union_sweep.ps1` | `b6dbf700d8e35d4cd5b953922ddba89b9262bd810326abde34e34984e1acf1f6` |
| Matrix JSON | `10df0586b2da1c6f9fb3a573e10c762dea1cbed28c2def5af98d9651ec731709` |
| Executable | `a2c6eddd897a4213483139c42b71cf4cd867653b961947b6af0d5129f4a0b0c8` |
| Build input fingerprint | `354b29cb45c6ea44e9b13dd4354899f3bd854300edd35016ea412ee055ac2793` |

The manifest records a dirty worktree because the measured source and harness
were intentionally built before their experiment commit. Exact source hashes,
the build fingerprint and executable hash pin the measured state.
