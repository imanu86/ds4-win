# G30 mixed direct route-pointer tranche

Date: 2026-07-15

## Scope

G29 could read the persistent VRAM expert cache directly only when all six
decode routes were already valid hits. A single miss forced every cache hit
through three device-to-device copies into the compact gate/up/down buffers.

G30 adds an opt-in decode-only route-pointer table. Each of the six route slots
points independently to either:

- the stable persistent VRAM expert-cache slot; or
- the existing compact transient buffer used by an arena hit or true miss.

Two specialized decode kernels consume the per-route pointers for IQ2_XXS
gate/up and Q2_K down. Route order, weights and down accumulation order remain
unchanged. The feature is enabled with `DS4_CUDA_MOE_MIXED_DIRECT=1` or the
harness switch `-MixedDirectCache`.

The path is restricted to `n_tokens=1`, `n_expert=6`, the existing LUT gate
kernel and the existing direct sum-6 down kernel. Prefill, SPEX buffers and all
unsupported configurations keep the old exact path.

## Exactness gates

All arms used the same native Windows build, RTX 3060 12 GiB, model
`C:\ds4-models\ds4-2bit.gguf`, greedy server output, context 256, 2 GiB mapped
budget, Q8/F16 cache disabled and embedding-row staging enabled.

Every safety and clean arm produced the same output and SHA-256:

```text
Hello! How can I help you today?
fda564ba3f7a0f028106d468420f674898ed99ac5bf2765ac9586206e39d73c5
```

Two independently observed pointer compositions passed:

| Cache policy | Calls observed | Cache routes | Compact routes | Composition per layer |
|---|---:|---:|---:|---|
| global LRU, 336 slots | 420 | 2,520 | 0 | 6 + 0 |
| layer-top1, 48 slots | 420 | 420 | 2,100 | 1 + 5 |

The second row is the actual mixed-address safety gate: one route reads a
persistent VRAM slot while five routes read compact transient storage in the
same gate/up and down launches.

## Clean n=3 A/B

Protocol: one identical 16-token warmup followed by three measured requests in
the same process. Diagnostics and route logging were disabled. Each arm used
the same prompt, build, cache policy and memory configuration.

| Policy | Arm | Server decode t/s mean | Min-max | TTFT mean | Output |
|---|---|---:|---:|---:|---|
| LRU 336 | compact copies | 3.313 | 3.25-3.36 | 1.395 s | exact |
| LRU 336 | mixed pointers | 3.540 | 3.53-3.55 | 1.388 s | exact |
| LRU 336, final guard build | compact copies | 3.333 | 3.27-3.37 | 1.345 s | exact |
| LRU 336, final guard build | mixed pointers | 3.440 | 3.36-3.54 | 1.440 s | exact |
| layer-top1 48 | compact copies | 2.837 | 2.76-2.91 | 1.335 s | exact |
| layer-top1 48 | mixed pointers | 2.910 | 2.82-2.96 | 1.293 s | exact |

The six-cache-route result was replicated on two builds: +6.8% first and +3.2%
after adding the final model-shape guard. The one-cache/five-compact result was
+2.6%. These are short-run deltas, not a claim that +6.8% is guaranteed. Win32
process-read deltas were unchanged inside each A/B: 57.483 GiB for LRU and
74.935 GiB for layer-top1. The gain therefore comes from removing
device-to-device repacking and its associated stream work, not from changing
model-file reads.

## What this proves and does not prove

This promotes per-route direct expert addresses as a useful mechanism. It also
proves exact mixed backing in one decode kernel. It does not yet complete the
Rank 1 architecture:

- router IDs still cross GPU -> CPU;
- cache lookup, deduplication and admission still run on CPU;
- a tiny route-pointer table still crosses CPU -> GPU once per layer;
- misses are still synchronously filled before the combined kernel starts;
- no resident-hit / CPU-miss overlap exists yet.

The next isolated tranche is the device `expert_id -> slot` map and GPU route
address construction. After that exact gate, split resident hits from true
misses and use the G29 CPU result to compare CPU IQ2XXS misses against transient
H2D misses. SPEX CPU speculation remains a later measured composition, never
an authority over the exact router.

## Provenance

- base commit: `3cf34c7624f018c1736eea51cb7c9bd4b8ddfd7d`;
- initial build input fingerprint: `d8d87809a24a66c812719193270252df55be99cd9e5ada4984dec6a9ae801a29`;
- initial `ds4_server.exe`: `1189080d14db8a186e39d2b471ec13d8403f65f3d0ea8ea9ced333e85d7c62e7`;
- final build input fingerprint: `edcb1434675ba7934da7c3a4d1dedbe88c3bc0c8c61cf16302ac90127de2890b`;
- final `ds4_server.exe`: `c53a975a6492fa81f8ba8ae5dfddedb284eb88e556412c37df80df9d17a2a4f7`;
- final `ds4_cuda.cu`: `96ac837ca4c0c45f68532fb20b1eb7578042ab8f4f52b288ab5a1995daed7add`;
- performance/safety harness: `8215e2e96034b093e6c04c24987c1c975809e89e8020f314b70749b61384225f`;
- final harness after the telemetry-only parser addition:
  `63df38e7d12db22a928ead31050e7dd5fa00de7c61d60cc0366bb9da763c16e1`.

Primary artifacts use the prefixes:

- `g7_runs/g7_g30_mixedptr_{off,on}_{safety_n1,clean_n3}_*`;
- `g7_runs/g7_g30_mixedptr_layer1_{off,on}_{safety_n1,clean_n3}_*`;
- `g7_runs/g7_g30_mixedptr_layer1_parser_safety_n1_*`;
- `g7_runs/g7_g30_final_{off,on}_clean_n3_*`.
