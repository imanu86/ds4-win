# IQ1_S Sidecar Design

## Scope

This document describes a fail-closed sidecar architecture for using a public
IQ1_S GGUF as an auxiliary source for routed MoE experts. The existing main
GGUF 2-bit model remains unchanged and remains the authoritative model.

The sidecar is not a replacement for the main model. It is only an optional
public IQ1_S source for routed experts when all routing, tensor identity,
integrity, residency, and quality gates pass. The environment variable is off
by default, so the unchanged main 2-bit path remains the normal fallback
between runs. Once a sidecar-enabled engine has validated and selected the
sidecar, a runtime source or upload failure aborts fail-closed instead of
silently mixing an unverified fallback into that run.

## Non-Goals

- Do not mutate, rewrite, or regenerate the main GGUF.
- Do not claim the sidecar path is lossless.
- Do not use the sidecar as a general tensor override.
- Do not route non-expert tensors through the sidecar.
- Do not rely on a single safety run as proof of quality.

## Model Roles

### Main GGUF

The main GGUF is the existing 2-bit model. It stays byte-for-byte outside the
sidecar design surface and remains the only mandatory inference source.

The main model owns:

- tokenizer and metadata contract;
- base graph topology;
- non-routed tensors;
- fallback expert tensors;
- correctness baseline.

### IQ1_S Sidecar

The sidecar is a public IQ1_S GGUF used only for routed experts. It is treated
as a lower-precision auxiliary cache source, not as an equivalent copy of the
main model.

The sidecar may provide:

- selected routed expert tensors;
- per-layer expert payloads eligible for staging;
- metadata needed to validate tensor identity and provenance.

The sidecar must not provide:

- attention tensors;
- token embeddings;
- output tensors;
- router/gate tensors;
- any tensor whose identity cannot be matched exactly to an expected routed
  expert tensor.

## Quantization Layout

The intended mixed layout is:

- layers 0-2: `down` tensors remain `Q2_K`;
- layers 3-42: routed expert `down` tensors may use `IQ1_S`;
- all other main 2-bit tensors remain unchanged.

This layout is a deployment policy for sidecar-eligible routed experts. It is
not a statement that IQ1_S is quality-equivalent to the original 2-bit path.

## Data Path

The first measured sidecar path is:

```text
SSD IQ1_S -> selected-load host staging -> compact VRAM IQ1_S buffer -> IQ1_S CUDA kernels
```

It keeps IQ1_S compressed across transport and executes the routed expert with
dedicated IQ1_S x Q8_K CUDA kernels. There is no IQ1_S-to-2-bit promotion in
this first implementation and no claim that the public IQ1_S weights recover
the main model's original routed weights.

### SSD IQ1_S

The public sidecar file is stored on SSD and addressed as an optional expert
source. Reads are demand-driven by routing decisions and bounded by the
configured cache and prefetch policy.

### RAM IQ1_S

IQ1_S expert payloads are staged by the existing selected-loader after tensor
identity, layer, expert, shape, quantization, and provenance checks pass. The
initial gate deliberately bypasses the generic persistent resident-route and
tiering caches until those structures become source-aware.

### Host Staging

The selected loader reads the compact IQ1_S gate/up/down spans into its host
staging buffers. This transports fewer bytes than the current 2-bit expert and
preserves the IQ1_S representation for upload.

### VRAM Residency

VRAM receives compact validated IQ1_S payloads and dedicated kernels consume
them directly. The first safety gate uses transient selected-load buffers, not
the existing persistent 2-bit resident cache. Persistent IQ1_S residency and
dynamic promotion to the 2-bit warm tier are later stages, gated separately.

## Fail-Closed Rules

The sidecar path is disabled by default unless explicitly configured.

The system must fail closed on:

- missing sidecar file;
- unsupported sidecar quantization;
- tokenizer or architecture mismatch;
- tensor name mismatch;
- layer or expert id mismatch;
- shape, stride, or size mismatch;
- unsupported layer policy;
- failed checksum or provenance validation;
- failed RAM staging;
- failed promotion;
- failed pinned allocation;
- failed VRAM upload;
- cache accounting inconsistency;
- runtime telemetry inconsistency;
- quality or safety gate failure.

With the environment variable disabled, the engine uses the unchanged main
2-bit path. With the sidecar explicitly enabled, fail-closed means startup or
the request fails on a validation/load/upload error. It must not silently
substitute a partially loaded sidecar tensor or mix sources inside a measured
run.

## Routing Contract

The sidecar participates only after the router selects an expert. The router and
gate tensors themselves remain owned by the main model.

For each routed expert lookup:

1. Resolve the selected layer and expert id from the main model route.
2. Check whether that `(layer, expert)` is sidecar-eligible.
3. Validate the sidecar tensor identity against the expected routed expert
   tensor.
4. Stage the compact source span through the selected loader.
5. Upload the compact IQ1_S payload to the route buffer.
6. Execute with the dedicated IQ1_S CUDA path (and Q2_K down projection for
   layers 0-2, matching the public sidecar layout).
7. Abort the sidecar-enabled run on any source, validation, or upload failure.

The sidecar must never influence routing decisions directly. It is an expert
payload source after routing, not a router replacement.

## Gate Safety and Quality Gates

Validation is split into a safety gate and a quality gate.

### Safety Gate

The first gate is `n=1`. Its purpose is to catch obvious functional failures:

- crashes;
- failed loads;
- invalid tensor matches;
- NaN or Inf output;
- broken routing;
- impossible telemetry;
- gross output corruption.

Passing `n=1` only means the path is safe enough for broader measurement. It is
not a quality claim.

### Quality Gate

Quality evaluation requires `n>=3` runs per relevant prompt set or benchmark
slice. The minimum quality gate should compare sidecar-enabled runs against the
unchanged main 2-bit baseline with the same prompts, seeds where applicable,
runtime settings, and measurement harness.

The quality gate should record:

- exact model and sidecar paths;
- command line and environment;
- prompt set;
- seed policy;
- per-run outputs or hashes;
- latency and throughput metrics;
- memory telemetry;
- sidecar hit/miss and fallback rates;
- any refusals, malformed outputs, or semantic regressions.

## Telemetry

Runtime telemetry is required for sidecar experiments and should be emitted in a
machine-readable format such as JSONL.

Recommended fields:

- run id and timestamp;
- main model path and content hash;
- sidecar path and content hash;
- sidecar enabled flag;
- layer policy;
- routed layer id;
- routed expert id;
- tensor name;
- source selected: `main_2bit` or `sidecar_iq1_s` (a future mixed-tier
  implementation must label any explicit fallback separately);
- SSD read bytes and latency;
- RAM staging bytes and latency;
- selected-load and compact upload latency;
- pinned memory bytes;
- VRAM upload bytes and latency;
- VRAM resident bytes;
- cache hit, miss, eviction, and fallback counters;
- validation failure reason;
- output health indicators.

Telemetry must distinguish "sidecar disabled", "sidecar miss", and "sidecar
validation failed". These states have different operational meaning.

## Provenance

Every sidecar run must record enough provenance to reproduce or reject the run.

Required provenance:

- main GGUF path, size, and hash;
- sidecar GGUF path, size, and hash;
- source repository or download URL for the public IQ1_S sidecar;
- conversion or quantization command used for the sidecar, if locally produced;
- quantization type and per-layer policy;
- imatrix source and command, if used;
- code revision;
- build configuration;
- runtime flags;
- hardware summary.

If any provenance field is unavailable, the run should be marked incomplete and
excluded from quality claims.

## Imatrix Limits

If the sidecar was produced with an imatrix derived from WikiText, document that
scope explicitly. A WikiText imatrix is a calibration artifact for that corpus
and should not be presented as representative of all downstream tasks,
languages, domains, or long-context behavior.

Known limits:

- WikiText is English-heavy and prose-biased.
- It may underrepresent code, multilingual prompts, tool traces, structured
  data, and domain-specific terminology.
- It does not prove preservation of routed expert behavior.
- It does not justify a lossless or equivalent-quality claim.

Quality claims must come from downstream evaluation of the actual sidecar path,
not from imatrix provenance alone.

## Claims Policy

Allowed claims:

- The main GGUF 2-bit model is unchanged.
- The public IQ1_S sidecar is used only for eligible routed experts.
- With the sidecar disabled, the runtime preserves the main 2-bit path.
- With the sidecar enabled, validation or transport failures abort instead of
  silently mixing sources.
- Layers 0-2 keep `down` tensors in `Q2_K`.
- Layers 3-42 may source eligible routed expert `down` tensors from IQ1_S.
- Safety requires an initial `n=1` gate.
- Quality requires `n>=3` evaluation before making quality statements.

Disallowed claims:

- IQ1_S sidecar execution is lossless.
- IQ1_S sidecar output is equivalent to the main 2-bit model without evaluation.
- WikiText imatrix calibration proves broad downstream quality.
- A single successful run establishes quality.
- Sidecar use is safe if tensor identity or provenance is incomplete.

## Operational Summary

The architecture keeps the main GGUF 2-bit model as the authoritative and
unchanged baseline. A public IQ1_S sidecar can reduce transport and storage cost
for routed experts, but only after strict identity, provenance, residency,
telemetry, and quality checks.

The safe default is always the existing main 2-bit path. Returning to it means
starting a run with the sidecar disabled, not substituting weights mid-run. The
sidecar path is an optional optimization experiment, not a new source of truth.

## Measured Gates

### Real Expert Microbenchmark

Three repetitions on the RTX 3060 validated the real IQ1_S expert layout and
kernel against the CPU reference. Maximum absolute error was
`6.55651093e-7`. Mean H2D time fell from `0.270876667 ms` for the current
`7,077,888`-byte expert to `0.188821 ms` for the `4,915,200`-byte IQ1_S expert,
a measured `30.3%` reduction. The IQ1_S x Q8_K kernel mean was
`0.689211667 ms`. These are component measurements, not end-to-end throughput
or quality claims.

### Environment-Off Regression

Run `g75_iq1_runtime_g73_regression_contaminated_retry` completed with server
exit code zero and reproduced the expected G73 output SHA-256 exactly:
`31cbc6504dcb57d42aeff9dbceb3aed943bcb32dae19a2edbf552e9fd2f52eb8`.
The IQ1_S sidecar was disabled. System quiescence was intentionally skipped
while the sidecar download used another physical disk, so all timing from this
run is excluded from SOTA and A/B claims. This gate proves only that the new
runtime leaves the established path unchanged when disabled.
