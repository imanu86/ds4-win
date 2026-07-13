# G11 native Windows shared/selected overlap

Date: 2026-07-13
Branch: `port/register-mmap-0050`
Parent: `2d3c1c7` (`experiment: reject layer-local resident expert cache`)

## Question

Can decode overlap the CPU `pread` plus pinned H2D selected-expert path with the
independent shared-expert gate/up/SwiGLU kernels?

The experiment is opt-in:

```text
DS4_CUDA_MOE_OVERLAP_SHARED=1
```

It applies only to one-token decode, with selected-load enabled and the resident
expert cache disabled. Batch/prefill and the default path are unchanged.

## Implementation

After the router completes, `ds4_gpu_routed_moe_prepare_selected()` reads the six
selected IDs to host and stores a key for the exact layer/tensor invocation. The
decode graph then launches shared gate/up/SwiGLU on CUDA stream 0. The existing
routed call consumes the prepared IDs, skips its duplicate D2H, and performs serial
file reads plus H2D uploads while the shared kernels are already in flight. The
routed kernels retain their existing upload synchronization and execute after the
shared kernels because both use stream 0.

No router choice, weight byte, quantization, sampling parameter, or arithmetic kernel
was changed. Prepared state is consumed only on an exact key match and is invalidated
otherwise.

The more invasive variant that also overlaps shared-down was deliberately not folded
into this measurement. The current fused shared-down/HC kernel reads `routed_out`, so
that variant requires a true prepare/submit/event split and a standalone shared-down
branch.

## Same-binary short A/B

Source SHA `0e149d356862...`, executable SHA `a5d0a6a9b88b...`, prompt `Hi`,
greedy no-think, 9 requested tokens, one discarded warmup, and `n=3` measured
repeats:

| Arm | Mean t/s | Min-max | Delta | Output SHA |
|---|---:|---:|---:|---|
| baseline | 2.055513 | 2.012298-2.095475 | reference | `fda564ba...` |
| shared gate/up overlap | 2.084549 | 2.056554-2.106238 | +1.4% | `fda564ba...` |

Artifacts:

- `g7_runs/g7_g11_overlap_baseline_hi9_clean_n3_result.json`
- `g7_runs/g7_g11_overlap_shared_hi9_clean_n3_result.json`

## Same-binary coding A/B

Prompt:

```text
Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document.
```

The source, executable, sampling, and launch parameters match the short A/B except
for 64 requested tokens. One warmup was discarded and each arm has `n=3` measured
repeats.

| Arm | Mean t/s | Min-max | Delta | Output SHA |
|---|---:|---:|---:|---|
| baseline | 1.553706 | 1.540731-1.563256 | reference | `fd6c4522...` |
| shared gate/up overlap | 1.531502 | 1.527684-1.534176 | -1.4% | `fd6c4522...` |

Artifacts:

- `g7_runs/g7_g11_overlap_baseline_cyber64_clean_n3_result.json`
- `g7_runs/g7_g11_overlap_shared_cyber64_clean_n3_result.json`

Generated UTF-8 output bytes are identical within and across each A/B. This is not a
logit-equivalence claim.

## Review and final safety

Static review found no P0/P1 correctness issue. It found two telemetry issues, fixed
after the performance A/B:

1. A stage-profiler boundary between shared launch and selected fill performed a
   device sync and would erase the overlap when profiling was enabled. The overlap
   path now exposes one combined `shared_gate_up+routed_moe` stage boundary after the
   routed call.
2. The harness previously recorded only that overlap was requested. It now rejects
   incompatible cache/no-selected-load combinations and records both requested and
   observed state from a backend consumption marker.

The final telemetry-only build (source `a895a897ae36...`, executable
`d89a21eb54e1...`) passed one safety run with:

```text
overlap_shared requested/observed: True / True
output: Hello! How can I help you today?
output SHA: fda564ba3f7a0f028106d468420f674898ed99ac5bf2765ac9586206e39d73c5
```

This `n=1` run verifies mechanism and output only; it is not a performance verdict.

Artifact:

- `g7_runs/g7_g11_overlap_final_observed_safety_n1_result.json`

## Verdict

The gate/up-only overlap is rejected as a production default. It is a small positive
on the nine-token prompt but regresses the coding workload by 1.4%. It remains opt-in
as a measured stepping stone for a complete submit/event experiment.

The next valid overlap experiment must move all selected planning before shared
compute, launch standalone shared gate/up/down, submit selected file/H2D work while
that full shared path is in flight, wait via a CUDA event, then run routed compute and
combine outputs. Any fill failure must arm a one-shot whole-block fallback without
reusing stale prepared state.
