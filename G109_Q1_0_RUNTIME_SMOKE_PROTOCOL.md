# G109 Q1_0 runtime smoke protocol

Status: preregistered structural protocol. No run or claim yet.

Date: 2026-07-17

## Scope

G109 validates the first real Q1_0 routed-expert sidecar in native Windows.
The initial sidecar may cover one routed layer and may be deterministically
derived from the authoritative IQ2/Q2 model. Such a file is a transport and
runtime fixture, not a quality-optimal Q1_0 quantization.

The direct-`pread` selected loader is accepted only for the first structural
smoke. It is not a performance candidate. The candidate path serves the same
Q1_0 entries from a resident host arena and performs no per-route SSD read.

## Provenance gate

Before starting DS4, record and verify:

- native commit, executable hash and build-manifest hash;
- primary model receipt and identity;
- Q1_0 sidecar path, logical/allocated size and manifest;
- source tensor names, source offsets and hashes used by the converter;
- sidecar tensor names, type 41, dimensions, offsets and hashes;
- active layer range;
- `derived_from_IQ2=true` and `not_quality_optimal=true` when applicable.

Any source, shape, type, offset, range or hash mismatch aborts before CUDA
dispatch.

## Ordered gates

### A. Env-off exactness

Run one greedy/no-think repeat of the G73 static-32 split-fused configuration
without Q1_0 environment variables. Require exit zero, the known expected
content hash, no Q1_0 runtime observation and no Q1_0 counters. This is a
regression safety only; timing is ineligible.

### B. Negative opt-in

Open the valid sidecar without `DS4_Q1_0_SELECTED_LOAD=1`. Require a clear
fail-closed diagnostic when the first Q1_0 route is reached. No fallback to the
IQ2 whole-tensor loader is allowed.

### C. Direct-file structural smoke

Enable:

```text
DS4_Q1_0_EXPERT_SIDECAR=<receipt-bound sidecar>
DS4_Q1_0_LAYER_FIRST=<single routed layer>
DS4_Q1_0_LAYER_LAST=<same routed layer>
DS4_Q1_0_SELECTED_LOAD=1
```

Use one short greedy/no-think request. Require:

- server process exits normally;
- Q1_0 binder and CUDA file source are observed;
- route calls, route slots and selected loads are all nonzero;
- selected-load failures are zero;
- every reported Q1_0 route is backed by the Q1_0 sidecar source;
- output and raw log are retained.

No speed or quality verdict is permitted from this run. A malformed output is
recorded honestly but does not by itself distinguish converter quality from a
runtime error.

### D. Resident-arena structural smoke

Repeat C with the resident Q1_0 arena enabled. Require the same structural
conditions plus:

- Q1_0 resident hits are nonzero;
- direct Q1_0 file reads during routed execution are zero;
- Q1_0 arena misses and failures are zero for the published entries;
- Q1_0 H2D bytes are measured directly;
- the 320-entry IQ2 VRAM cache is not populated with Q1_0 bytes;
- router-selected IDs and weights are unchanged by representation selection.

If the sidecar covers only one layer, the result validates only that layer and
cannot be extrapolated to full-domain residency.

## Promotion to measurement

Only after A through D pass may a performance comparison run. It must use at
least three independent clean processes per arm and compare the same prompt,
model, active layer range, router decisions and semantic arena entries.

The control is IQ2 host-resident transport. The candidate is Q1_0
host-resident transport. Report server decode, TTFT, route H2D bytes, copy
submissions, wait time, GPU utilization, host residency and all Q1_0 counters.
Outliers trigger a complete three-process rerun. Quality requires separately
retained outputs and L0-L3 grading; no repeat flag or `n=1` result is a verdict.

