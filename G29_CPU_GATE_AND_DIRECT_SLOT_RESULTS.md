# G29 CPU miss gate and direct resident-slot tranche

Date: 2026-07-15

## Scope

This gate measures one real routed expert on the native Windows runtime before
implementing mixed hit/miss execution. It also tests a first conservative
direct-slot tranche: decode may read the persistent VRAM expert cache in place
only when every selected expert is already valid. Any miss falls back to the
unchanged compact gather path.

The direct path is opt-in through `DS4_CUDA_MOE_DIRECT_CACHE_HITS=1`. It does
not change router scores, selected IDs, weights, quantization, masks, REAP,
SPEX, or output sampling.

## CPU versus transfer plus GPU gate

The diagnostic uses layer 10 because layer 0 is inside the 2 GiB registered
host window and therefore cannot measure selected-load transport. CPU and CUDA
consume the same real activation, selected experts, IQ2_XXS gate/up tensors,
Q2_K down tensors, SwiGLU clamp, and router weights.

Common configuration:

- model: `C:\ds4-models\ds4-2bit.gguf`, 86,720,111,488 bytes;
- GPU: RTX 3060 12 GiB, native Windows/WDDM;
- CPU: 12 DS4 worker threads;
- registered mmap window: 2 GiB;
- resident expert cache: one slot, deliberately preventing reuse;
- Q8/F16 cache disabled; embedding row staging enabled;
- prompt: `Hi`;
- layer: 10; selected expert measured individually: 219.

Measured times:

| Component | Samples | Result |
|---|---:|---:|
| CPU complete single expert, warm mmap | 5 passes x 5 iterations | 0.994 ms mean |
| CPU complete selected top-6, first pass | 1 | 11.913 ms |
| CPU complete selected top-6, subsequent warm passes | 4 x 3 iterations | 5.698 ms mean |
| CUDA complete top-6, first pass | 1 | 0.529 ms |
| CUDA complete top-6, subsequent warm passes | 4 | 0.431 ms mean |
| Selected-load fetch, one-slot cache | 60 calls / 360 experts | 1.15 ms per expert |

The CPU result is a mechanism gate, not an end-to-end speed verdict. One warm
CPU expert is slightly cheaper than the measured warm selected-load cost before
the 0.431 ms CUDA top-6 kernel is added. CPU is therefore retained as a serious
candidate for one or a few true misses. Resident VRAM hits still belong on the
GPU: the complete warm top-6 CUDA compute is more than ten times faster than
the warm CPU top-6 compute.

## Direct resident-cache tranche

When all selected experts hit the persistent cache, the implementation:

1. remaps selected IDs to stable cache slots;
2. binds gate/up/down directly to the persistent cache slabs;
3. skips three device-to-device copies per expert;
4. skips the selected-upload-stream synchronization.

The current tranche deliberately retains router D2H and CPU cache lookup. It
is an exact fallback scaffold, not yet the final device-side slot map.

### Exactness safety gate

The diagnostic OFF and ON arms produced identical text and SHA-256:

```text
Ciao! Come posso aiutarti oggi?
f8cb801455943e72125e6766c5ee2bbc55e0f693d975a7b1b746cf1b78a02283
```

Both arms reported 1,210 cache hits, 5,882 misses and 5,546 evictions. The ON
arm found only eight all-hit layer calls across warmup plus measurement. Its
single-sample throughput is not used as a verdict.

### Clean n=3 A/B

Protocol: one identical 16-token warmup, then three measured requests in the
same process; greedy server default, `nothink`, context 256, 336 requested
cache slots, 4,096 MiB startup reserve, 128 MiB runtime reserve, 2 GiB mapped
budget, no diagnostics.

| Arm | Server decode t/s mean | Min-max | TTFT mean | Output |
|---|---:|---:|---:|---|
| direct OFF | 3.41 | 3.39-3.43 | 4.024 s | identical |
| direct ON | 3.35 | 3.27-3.41 | 3.984 s | identical |

This global-LRU composition is rejected as a performance win. Its dynamic
working set produces too few all-six-hit calls, so the direct path rarely
engages. The result does not reject direct resident execution under a protected
hot lane; it rejects waiting for six simultaneous hits before doing useful
work.

## Decision

The next implementation must split hits from misses:

- launch every resident hit directly from stable VRAM slots;
- route each true miss to CPU or a transient H2D lane;
- join once before the routed output is consumed;
- then replace router D2H/CPU lookup with a device `expert_id -> slot` map.

Do not repeat the all-hit global-LRU test. The CPU miss arm and the transient
H2D miss arm need isolated exact A/B measurements after mixed execution exists.

## Provenance

- base commit: `8a2d3756411c329240e4e4006093ba7c8f9b56f2`;
- build fingerprint: `147c23cdbee821c393fb07779bb340a236eecb38e26b1ddbaac237ff0017301a`;
- `ds4_server.exe`: `c1775bea2a49baf485701358fe2deefb71591e8b8bf0e087170f4fbc1da0bc2d`;
- `ds4_moe_gate_bench.exe`: `6df1ac114a81f0c9a7741306fb25baa5c92a8c206773ae05a8b630c5c25e49f0`;
- `ds4.c`: `83798ae984860f5350075e03f876dba4eca94acfbcf4130643b9cd2bab4fa06f`;
- `ds4_cuda.cu`: `fbb5d359fd5880e2421b28be993a3985886c134b4f18b555763431d9dc016ce5`;
- harness: `6df0f9860b744f7539e784af0958a1927d951ed2881530a8259688cc01820c5a`.

Primary artifacts:

- `g7_runs/g29_gate_layer10_warm5.stderr.log`;
- `g7_runs/g29_gate_layer10_fetch60.stderr.log`;
- `g7_runs/g7_g29_directslots_{off,on}_safety_n1_*`;
- `g7_runs/g7_g29_directslots_{off,on}_clean_n3_*`.
