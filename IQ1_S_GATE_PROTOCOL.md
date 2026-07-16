# IQ1_S Gate Protocol

Scope for this gate:

- New standalone target: `ds4_iq1_s_bench`.
- New files only: `ds4_iq1_s_bench.cu`, `ds4_iq1_tables_cuda.inc`, `IQ1_S_GATE_PROTOCOL.md`.
- Existing runtime files `ds4.c` and `ds4_cuda.cu` are not included or modified.
- The only build-system change is adding the benchmark target to `CMakeLists.txt`.

Provenance:

- Source repository: `ggml-org/llama.cpp`
- Commit: `b15ca938ad00aa6b3ee6c2edda7363fd02826b18`
- Upstream files:
  - `ggml/src/ggml-common.h`
  - `ggml/src/ggml-cuda/vecdotq.cuh`
- Ported items:
  - `block_iq1_s` layout: 50 bytes per 256 weights, 1.5625 bpw
  - `IQ1S_DELTA = 0.125f`
  - `iq1s_grid_gpu` lookup table
- device IQ1_S dot/dequant math against upstream Q8_1 and DS4 Q8_K
  activation blocks

DS4 geometry used by the benchmark:

- `n_embd = 4096`
- `n_ff_exp = 2048`
- `n_expert = 256`
- Current routed expert transfer layout:
  - gate: IQ2_XXS, `4096 / 256 * 66 = 1056` bytes per row
  - up: IQ2_XXS, `4096 / 256 * 66 = 1056` bytes per row
  - down: Q2_K, `2048 / 256 * 84 = 672` bytes per row
  - one expert gate/up/down: `2162688 + 2162688 + 2752512 = 7077888` bytes
  - equivalent per 3x256 weights: `66 + 66 + 84 = 216` bytes
- IQ1_S comparison transfer layout:
  - gate: `4096 / 256 * 50 = 800` bytes per row
  - up: `4096 / 256 * 50 = 800` bytes per row
  - down: `2048 / 256 * 50 = 400` bytes per row
  - one expert gate/up/down: `1638400 + 1638400 + 1638400 = 4915200` bytes
  - equivalent per 3x256 weights: `50 + 50 + 50 = 150` bytes

Validation:

- IQ1_S blocks are generated deterministically with valid table indices, high-bit packing, scale bits, and delta sign bit.
- Q8_1 activation blocks are generated deterministically from float values and quantized on host.
- GPU dot is compared against a CPU reference using the same imported table.
- The DS4-specific IQ1_S x Q8_K dot is independently compared with both a
  scalar dequantized reference and a packed CPU reference.
- GPU dequant is compared against a CPU reference using the same imported table.
- Declared tolerances:
  - dot max absolute error: `1e-4`
  - dequant max absolute error: `1e-6`

Measurements:

- Pinned H2D copy of one complete current DS4 expert gate/up/down geometry.
- Pinned H2D copy of one complete IQ1_S x3 expert gate/up/down geometry.
- IQ1_S dot kernel over deterministic blocks.
- IQ1_S dequant kernel over deterministic blocks.

Output:

- The executable writes one machine-readable JSON object to stdout.
- Default command:

```powershell
.\build\Release\ds4_iq1_s_bench.exe
```

- Optional command:

```powershell
.\build\Release\ds4_iq1_s_bench.exe 200 98304
```

- Optional flat real-weight command. The file must contain exactly 98,304
  IQ1_S blocks, ordered as one DS4 expert's gate, up, and down tensors:

```powershell
.\build\Release\ds4_iq1_s_bench.exe 200 98304 C:\path\expert_iq1_s.bin
```

- Optional representative GGUF command. The benchmark opens the GGUF read-only
  and accepts either one GGUF v3 shard or a byte-for-byte physical
  concatenation of split GGUF v3 shards. It samples expert 0 from:
  - `blk.0.ffn_gate_exps.weight` IQ1_S
  - `blk.0.ffn_up_exps.weight` IQ1_S
  - `blk.0.ffn_down_exps.weight` Q2_K
  - `blk.1.ffn_down_exps.weight` Q2_K
  - `blk.2.ffn_down_exps.weight` Q2_K
  - `blk.3.ffn_gate_exps.weight` IQ1_S
  - `blk.3.ffn_up_exps.weight` IQ1_S
  - `blk.3.ffn_down_exps.weight` IQ1_S
  - `blk.42.ffn_gate_exps.weight` IQ1_S
  - `blk.42.ffn_up_exps.weight` IQ1_S
  - `blk.42.ffn_down_exps.weight` IQ1_S

  Each sampled tensor must have the exact DS4 routed-expert shape and expected
  quant type. Missing tensors, wrong types, wrong shapes, or short reads are
  fatal before measurement:

```powershell
.\build\Release\ds4_iq1_s_bench.exe 200 1 D:\ds4-models\DeepSeek-V4-Flash-IQ1_S-XL.gguf
```

  Concatenated input follows the production loader contract. The maximum tensor
  extent in shard N is the physical header offset of shard N+1. Every shard
  must carry coherent `split.no`, `split.count`, and `split.tensors.count`
  metadata in ascending order; duplicate tensor names, unsupported tensor types
  needed for extent discovery, count mismatches, truncated shards, and trailing
  or missing bytes are fatal. Tensor-relative offsets are adjusted by each
  shard's physical base. Every `real_samples` JSON item records
  `source_shard`, shard count/base/data base, tensor-relative offset, final
  physical offset, and sampled byte count.

- Optional CPU-only cross-quant checkpoint-correlation mode. This mode does not
  initialize CUDA. It accepts two extracted `.f32` row-output vectors produced
  from the same deterministic input and reports cosine, Pearson correlation,
  relative L2 error, and max absolute error. Use this to separate kernel/offset
  bugs from expected checkpoint differences when comparing main-model
  IQ2_XXS/Q2_K expert outputs with sidecar IQ1_S/Q2_K outputs:

```powershell
.\build\Release\ds4_iq1_s_bench.exe --correlate-outputs `
  C:\path\main_blk3_gate_expert0_output.f32 `
  C:\path\sidecar_blk3_gate_expert0_output.f32 `
  blk.3:gate:expert0 `
  deterministic_input_v1
```

  Extraction inputs must be raw little-endian `float32` vectors with identical
  length. The metadata argument must identify `layer:part:expert`; the source
  note should identify the deterministic input recipe or receipt used to create
  both vectors.

## Structural diagnostics

`g7_measure.ps1` can restrict sidecar substitution to an inclusive layer range
with `-Iq1SLayerFirst` and `-Iq1SLayerLast`. The default remains the full
`0..42` range. This is an isolation control only; it does not define the final
cold-expert policy.

Repeated n=1 structural diagnostics may pass `-ReuseVerifiedIq1SReceipt` to
avoid re-reading the 61.5 GB sidecar solely for SHA-256. The switch is refused
unless `-GateKind structural-safety` is active. Path, byte count, expected hash,
receipt status, and receipt provenance are still checked, and the result records
`iq1_s_sidecar_hash_method=verified_receipt_reuse`. Benchmark and quality gates
must continue to compute the full file hash.

`-Iq1SMixedColdOne` enables the first bounded mixed-format decode fixture. It
requires the validated sidecar, leaves prefill on the primary 2-bit model, and
for each active decode layer preserves the router's six selected ids and gate
weights while executing the lowest-weight slot through IQ1_S. The other five
slots remain on the primary 2-bit path. Runtime telemetry must report exactly
`hot_main=5*calls`, `cold_iq1=calls`, and zero failures.

This first fixture deliberately zeroes the cold slot's weight in a six-slot
primary launch and then adds the one-slot IQ1_S result. It proves mixed-format
calculation and single accumulation, but still loads/calculates the zero-weight
primary slot. Therefore its timings and transport volume are not performance
evidence. The next implementation gate must build separate five-slot and
one-slot work lists so the primary copy of the cold expert is never fetched.

### G77 mixed layer-3 smoke

The first end-to-end structural run used the same short prompt and launch
controls as the coherent G76 layer-3 diagnostic, with mixed mode active only
for layer 3:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\g7_measure.ps1 `
  -Tag g77_mixed_iq1_cold1_layer3_n1 `
  -ModelPath C:\ds4-models\ds4-2bit.gguf `
  -Iq1SExpertSidecar D:\ds4-models\DeepSeek-V4-Flash-IQ1_S-XL.gguf `
  -ExpectedIq1SExpertSidecarSHA256 b049d1eb34c068f19ab007b33c22a7d758b578bf2b10d9276e79654f85d35047 `
  -ExpectedIq1SExpertSidecarBytes 61540805344 `
  -ReuseVerifiedIq1SReceipt -Iq1SLayerFirst 3 -Iq1SLayerLast 3 `
  -Iq1SMixedColdOne -Prompt "Say hello in one short sentence." `
  -MaxTokens 32 -Repeats 1 -GateKind structural-safety -Context 256 `
  -BudgetGB 28 -ReserveMB 1024 -RuntimeReserveMB 256 `
  -DisableQ8F16Cache -EmbedRowStaging -IoQD 4 -OverlapSharedFull
```

Measured result: output `Hello!`; mixed calls `2`; primary hot contributions
`10`; IQ1_S cold contributions `2`; sidecar selected loads `2`; failures `0`;
last active layer `3`. This is a structural `n=1` PASS only. It is explicitly
not quality-eligible or SOTA-eligible.

### G77 mixed all-layer smoke

The same fixture was then enabled for the complete inclusive `0..42` range.
The run produced `Hello! How can I assist you today?`, with `387` mixed calls,
`1935` primary hot contributions, `387` IQ1_S cold contributions, `387`
sidecar selected loads, and zero mixed or sidecar failures. Result JSON SHA-256:
`9de63ea52caf541b1868bbe20f53e2f0bd610ddc0d020facd4a8f582c6d0f00e`.
This remains an `n=1` structural result and makes no generalized quality claim.

### Environment-off G74 control

After the mixed implementation was committed, the frozen G74 control arm was
run with no sidecar and no mixed environment variable. It reproduced the exact
historical content SHA-256
`31cbc6504dcb57d42aeff9dbceb3aed943bcb32dae19a2edbf552e9fd2f52eb8`.
No IQ1_S or mixed telemetry appeared. The observed decode rate was `4.89 t/s`,
but this was one exactness run and is not a statistical SOTA claim. Result JSON
SHA-256: `42a57333dbce70cf20df8651fe1de81e7da9109e0e90b5459289d53682aef4f5`.

The G74 packed-copy candidate still refuses the existing unequal primary
gate/down expert sizes (`2162688/2752512`). That guard predates the IQ1_S mixed
change, and the historical G74 summary was already stopped at its candidate
safety gate. It is not evidence of an IQ1_S regression.

## G75 measured gate

The real-weight gate sampled only the required byte ranges from
`persadian/DeepSeek-V4-Flash-IQ1_S-XL`, revision
`7e641d4869031039314f0ae48c79a4f2a7862230`. No full-model download was
started.

- tensor sample: layer 3, expert 0, gate + up + down
- sampled bytes: 4,915,200
- sampled SHA-256:
  `0f5b7b4505e4e3b83517d4881463ddd5414f1f21f30bfd3f440981bb70e8f2c0`
- repetitions: n=3, 200 inner iterations each
- validation: PASS in all three runs
- maximum IQ1_S x Q8_K absolute error: `6.55651093e-7`
- current-format pinned H2D mean: `0.270876667 ms`
- IQ1_S pinned H2D mean: `0.188821000 ms`
- IQ1_S x Q8_K kernel mean: `0.689211667 ms`
- measured H2D latency reduction: 30.3 percent

Machine-readable receipts are under
`g7_runs/g75_iq1_s_real_expert_gate/`.

Safety rule:

- Build is allowed while other work is active.
- Do not launch the benchmark if a DS4 server, DS4 benchmark, or G74 orchestrator/run process is active.

## G76-G93 measured checkpoint

Only G86 contains clean repeated performance measurements. All other entries
below are structural evidence unless explicitly stated otherwise.

| Gate | Scope | Evidence | Allowed conclusion |
|---|---|---|---|
| G76-G83 | Sidecar, split routing, RAM cache | IQ1_S runtime observed; physical `5:1` split and join; cache hits appear; zero mixed failures in retained smokes | Structural and transport plumbing only |
| G86 control | Clean benchmark, `n=3` | 3.460 total t/s; 5.417 server decode t/s; TTFT 6.965 s | Baseline for this prompt and host state |
| G86 IQ1_S | Clean benchmark, `n=3`, RAM cache 8 GiB | 2.194 total t/s; 3.430 server decode t/s; TTFT 10.505 s; 87.71% cache hits; 41.112 GiB SSD avoided | IQ1_S cache reduces SSD traffic but is slower than control in this configuration |
| G89 | Structural profile, transient VRAM cache 1/layer | 53/640 hits, 587 misses, zero failures | Cache is functional; no speed claim |
| G90 | Structural profile, transient VRAM cache 2/layer | 78/640 hits, 562 misses, zero failures | Second slot adds only 25 hits and consumes primary-cache VRAM |
| G91 | Structural no-main-sync profile | Exact output; explicit main sync approximately zero; cost moved into cold submission | Removing one sync alone does not prove overlap |
| G93 | Structural GPU-planner profile | Exact shared output SHA-256 `c7c8e02137fd31de53dc88a5645b3c6a92ab98d844e42ddcc00c52257d63823d`; planner 640/640; wait 0.085 ms total; zero failures; router D2H 6.302 ms; metadata 3.624 ms | Planner preserves the deterministic output and removes most router/metadata readback |

G92 and G93 ran while Windows `ScheduledDefrag` kept the IQ1_S source disk
above 90 percent busy. Their SSD, H2D, cold-submit, TTFT, throughput, and total
latency values are invalid for performance comparison. They must not enter the
SOTA ledger.

The G86 outputs were only 64 tokens and have no recorded human L0-L3 grades.
Consequently neither G86 nor the structural gates establish quality
equivalence or lossless behavior.

### G94 clean GPU-planner A/B

The clean cache-4 gate used identical binary, model, sidecar, 20-GiB primary
arena, prompt, warmup, and three measured repeats per arm. All six measured
outputs had the same SHA-256. Planner-on raised server decode from 2.073 to
2.223 t/s (`+7.23%`) and harness throughput from 1.543 to 1.630 t/s (`+5.68%`).
Mean TTFT changed from 10.588 to 10.458 seconds. The planner reconciled
10240/10240 calls, accumulated 1.363 ms wait, and reported zero failures. This
is a short performance/exactness gate and carries no L0-L3 quality claim.

The cache-8 attempt is not a result: the fail-closed runtime monitor aborted it
after available Windows memory fell below 0.5 GiB. The 2048-token/context-4096
G95 control was also stopped as an impractical protocol probe after generation
100 measured 0.47 t/s with only 276/320 resident expert-cache slots. No timing
or quality verdict may be derived from either aborted run.

### Next gates

Repeat the current-build environment-off G74 exactness gate when at least 32
GiB of host memory are available. Run G95 at 768 max tokens, context 1024,
`stop="</html>"`, and `n>=3` per arm, preserving every raw output and recording
human L0-L3 grades. Promotion
into authoritative 2-bit pinned RAM and next-token 2-bit VRAM eligibility are
separate later gates; the current IQ1_S cold path does not prove them.
