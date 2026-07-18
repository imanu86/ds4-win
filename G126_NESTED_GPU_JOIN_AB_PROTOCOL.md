# G126 Nested GPU Join A/B Protocol

## Purpose

G126 measures the nested-residual transport lever only:

- control: nested residual cache with CPU reconstruction join;
- candidate: nested residual cache with exact GPU join;
- router: full/open, with no REAP/static/closed mask;
- prompt/output: canonical 64-token cyberpunk exact-output gate.

The benchmark is valid only as an n>=3 A/B throughput comparison between the two join transports. It is not a general quality verdict and does not replace longer L0-L3 grading.

## Required Safety Receipt

The candidate may run without runtime reconstruction verification only when it provides both:

- `-NestedResidualGpuJoinSafetyReceipt`
- `-ExpectedNestedResidualGpuJoinSafetyReceiptSHA256`

The canonical current-build receipt is:

`C:\Users\imanu\AppData\Local\Packages\Claude_pzs8sxrjxfjjc\LocalCache\Local\ds4-win-work\g7_runs\g7_g125_nested_gpu_join_safety_current_build_clean_20260718T182935501Z_eb824ebedb_receipt.json`

with SHA-256:

`ae15a6d3d3bc35e75b46befd8d18d7886f571e47d93561d146ada3ccf20f58fb`

That receipt is hash-pinned and build-bound. If the DS4 executable or build manifest changes, G125 safety must be regenerated before G126 can claim a valid candidate benchmark.

## Execution Order

The order is deterministic and balanced to reduce thermal/cache drift:

1. `cpu_join` repeat 1
2. `gpu_join` repeat 1
3. `gpu_join` repeat 2
4. `cpu_join` repeat 2
5. `cpu_join` repeat 3
6. `gpu_join` repeat 3

This is the AB/BA/AB pattern while retaining exactly three independent processes per arm. The runner records `order_position` in both plan and result rows.

## Candidate Gate

For every `gpu_join` child:

- exact output SHA must match the canonical G125/G123 output;
- `nested_residual_gpu_join_requested=true`;
- `nested_residual_gpu_join_observed=true`;
- runtime requested/observed must both be `1`;
- `nested_residual_gpu_join_calls > 0`;
- base and residual H2D bytes must be greater than zero;
- native H2D bytes must be zero;
- CPU reconstruct calls must be zero;
- verify calls, verify bytes, and verify seconds must all be zero;
- verify mismatches and failures must be zero;
- `nested_residual_gpu_join_safety_receipt_validated=true`;
- safety receipt path and SHA must match the pinned receipt;
- nested VRAM host fills/host bytes must be zero;
- nested VRAM H2D bytes must equal `misses * 7077888`.

The zero verify counters prove that the expensive G125 D2H readback is absent from G126.

## Control Gate

For every `cpu_join` child:

- GPU join requested and observed must be false;
- runtime requested/observed must both be zero;
- every GPU-join counter must be zero;
- safety receipt validation must be false/empty;
- nested VRAM host fills and host bytes must equal misses times one native expert;
- nested VRAM H2D bytes must equal `misses * 7077888`.

## Result

G126 completed the balanced six-process sequence with three independent
processes per arm. All six accepted outputs were exact and uncontaminated.

| Arm | Decode t/s | Mean | Median |
|---|---|---:|---:|
| CPU join | `1.15, 1.16, 1.15` | `1.153333` | `1.15` |
| GPU join | `1.56, 1.58, 1.57` | `1.570000` | `1.57` |

The measured mean decode delta is `+36.1272%`. End-to-end timing is retained
as batch-only/noisy because TTFT and WRAP varied widely; it is not a general
latency claim. G126 remains below the G123 full/open IQ2 control at `1.65 t/s`
and is not comparable as absolute SOTA to request-scoped/closed G73.

Authoritative aggregate:

`C:\Users\imanu\AppData\Local\Packages\Claude_pzs8sxrjxfjjc\LocalCache\Local\ds4-win-work\g7_runs\g7_g126_nested_gpu_join_ab_current_build_clean_v2_20260718T183831489Z_b4d8a5d111_result.json`

SHA-256:

`c1f7849aa0da33c4b6d8279073954ba39f556fc485215e6d4058e809fbe9eaa6`
