# G109 Q1_0 runtime smoke protocol

Status: gates A-D and the isolated C/D transport matrix completed. Mixed
IQ2/Q1_0 composition and the SOTA A/B remain pending.

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

Frozen artifacts for the first run:

- native branch/runtime commit: `feature/q1-0-resident-base` / `eabf03c`;
- resident-arena implementation: `c6fbb2b`;
- Q1_0 runner gate: `1f661f0`;
- Q1_0 arena geometry fix: `eabf03c`;
- sidecar: `C:\ds4-models\ds4-q1-layer42-derived-iq2-84b4ffb.gguf`;
- sidecar bytes/SHA-256: `907428832` /
  `58d537738ac80df504d9954a694703c37cc5f9ee236ca8c06ce94cea1ab8ef26`;
- receipt SHA-256:
  `6a36ae77c20e60f2e8a6be57b64f1f8eb524def9d9d119201c81e92c56312462`;
- converter/helper commits: `84b4ffb` / `2dd1b0a`;
- helper SHA-256:
  `71df7699bb4189ecd18bd33858cb0877c34fcfa1535f833d88fcc1eac38e282a`;
- active routed layer: `42`; full resident bootstrap: `256` experts;
- Q1_0 resident payload: `907419648` bytes (`865.383 MiB`).

The Release build manifest must be regenerated after the final protocol commit
so its HEAD and executable provenance match the exact run state.

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

For this first single-layer smoke, `DS4_CUDA_DYNAMIC_ARENA_GB=1` is sufficient:
the required 256 slots occupy 864 MiB. The bootstrap accepts exactly 256 cold
loads, or exactly zero loads when a later session republishes an already-full
snapshot. Any partial count fails closed.

## Current composition boundary

The resident Q1_0 mode owns the single native host arena in this patch. It
therefore disables the IQ2 host arena, dynamic mass masks and mixed-host
resolver instead of pretending to compose them. G46/G73 expert tiering and
prefill-mass composition must not be enabled in gate D.

Consequently, gate D is only evidence that selected Q1_0 experts are served
from pinned host RAM with zero routed `pread`. It is not a comparison with the
current G73 throughput stack. Before a SOTA A/B, implement and gate one of:

1. disjoint Q1_0 and IQ2 host arenas with a representation-neutral resolver;
2. a unified arena whose entries carry backing/source identity; or
3. a full routed-layer Q1_0 sidecar that removes the mixed-backing boundary.

## Promotion to measurement

Only after A through D pass may a performance comparison run. It must use at
least three independent clean processes per arm and compare the same prompt,
model, active layer range, router decisions and semantic arena entries.

The control is IQ2 host-resident transport. The candidate is Q1_0
host-resident transport. Report server decode, TTFT, route H2D bytes, copy
submissions, wait time, GPU utilization, host residency and all Q1_0 counters.
Outliers trigger a complete three-process rerun. Quality requires separately
retained outputs and L0-L3 grading; no repeat flag or `n=1` result is a verdict.

An intermediate direct-file versus resident-arena matrix may isolate the Q1_0
transport mechanism after A-D. Such a matrix must also use at least three clean
independent processes per arm, retain exact outputs and use a balanced order.
It cannot be called a SOTA comparison because both arms execute Q1_0 at only the
active sidecar layers and omit the complete G46/G73 IQ2 composition.
