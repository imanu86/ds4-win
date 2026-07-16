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

- Optional real-weight command. The file must contain exactly 98,304 IQ1_S
  blocks, ordered as one DS4 expert's gate, up, and down tensors:

```powershell
.\build\Release\ds4_iq1_s_bench.exe 200 98304 C:\path\expert_iq1_s.bin
```

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
