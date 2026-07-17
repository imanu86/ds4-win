# G109 Q1_0 runtime smoke results

Status: A, C and D v2 produced valid structural evidence. B produced the
expected fail-closed diagnostic. D v1 failed before serving because the Q1_0
arena geometry was rejected; this was fixed by `eabf03c`.

Date: 2026-07-17

Gates A-D are structural `n=1` evidence. A subsequent balanced C/D transport
matrix used three independent clean processes per arm. That matrix supports a
narrow transport comparison, but remains ineligible for SOTA or quality claims:
the Q1_0 sidecar covers only routed layer 42 and is derived from IQ2, not a
quality-optimal Q1_0 quantization.

## Evidence

Read-only artifacts used:

- `G109_Q1_0_RUNTIME_SMOKE_PROTOCOL.md`
- `g7_runs/g7_g109_a_env_off_exact_n1_result.json`
- `g7_runs/g7_g109_b_q1_no_selected_fail_closed_n1_stderr.log`
- `g7_runs/g7_g109_c_q1_direct_file_structural_n1_result.json`
- `g7_runs/g7_g109_d_q1_resident_arena_structural_n1_v2_result.json`
- `g7_runs/g7_g109_d_q1_resident_arena_structural_n1_failure.json`
- `g7_runs/g7_g109_d_q1_resident_arena_structural_n1_stderr.log`
- `g7_runs/g7_g109_c_q1_direct_file_structural_n1_stderr.log`
- `g7_runs/g7_g109_d_q1_resident_arena_structural_n1_v2_stderr.log`
- `g7_runs/g7_g109_cd_direct_p1_result.json`
- `g7_runs/g7_g109_cd_resident_p1_result.json`
- `g7_runs/g7_g109_cd_resident_p2_result.json`
- `g7_runs/g7_g109_cd_direct_p2_result.json`
- `g7_runs/g7_g109_cd_direct_p3_result.json`
- `g7_runs/g7_g109_cd_resident_p3_result.json`
- `C:\ds4-models\ds4-q1-layer42-derived-iq2-84b4ffb.gguf.receipt.json`

No DS4 or GPU run was started while compiling this report. Runtime and runner
code were not edited by the reporting pass.

## Provenance

Code provenance referenced by the protocol and run artifacts:

- `c6fbb2b673dfd9a93615dfabd25ee59bb9e78471`: add Q1_0 resident host arena
- `1f661f08c0c89a1bd6b0e87c5b91a8c074a387e5`: test: gate Q1_0 resident arena telemetry
- `eabf03c877a18b87fd62a88229eef91f8ac23b9e`: fix: accept Q1_0 arena tensor geometry

Run provenance:

- A and C ran at HEAD/build-manifest HEAD `7c50d90b4ab04c7d216723f9d8e7654ac11d615a`.
- D v2 ran at HEAD/build-manifest HEAD `eabf03c877a18b87fd62a88229eef91f8ac23b9e`.
- All six C/D matrix processes used executable SHA-256
  `51c2b5609664766b57ab90a5696438729ce12a8b47b9fe736b05c3325eccfc22`
  and passed the quiescence preflight with no failures.
- Worktree was dirty in the result JSONs; this report does not attempt to
  normalize or reinterpret that state.
- GPU identity in A/C/D v2: NVIDIA GeForce RTX 3060, driver `596.21`, bus
  `00000000:0A:00.0`.

Q1_0 sidecar provenance:

- Sidecar: `C:\ds4-models\ds4-q1-layer42-derived-iq2-84b4ffb.gguf`
- Bytes: `907428832`
- SHA-256: `58d537738ac80df504d9954a694703c37cc5f9ee236ca8c06ce94cea1ab8ef26`
- Receipt SHA-256: `6a36ae77c20e60f2e8a6be57b64f1f8eb524def9d9d119201c81e92c56312462`
- Manifest SHA-256 from receipt: `c2156144f208c1312ed7a2a8a7d9700637613dea2cc31214d22779724dc0e786`
- Converter commit: `84b4ffbb91546800fdca0fac64c569262e1fcb7a`
- Helper commit: `2dd1b0a43dc387f62253e9096a9de8bdf2d7aca6`
- Helper SHA-256: `71df7699bb4189ecd18bd33858cb0877c34fcfa1535f833d88fcc1eac38e282a`
- Layer: `42`
- `derived_from_iq2=true`
- `not_quality_optimal=true`

## Gate A: env-off exactness

Result: pass as a regression safety gate.

- Artifact: `g7_runs/g7_g109_a_env_off_exact_n1_result.json`
- Server exit code: `0`
- Repeats: `1`
- Warmup: `false`
- Expected/content SHA-256: `31cbc6504dcb57d42aeff9dbceb3aed943bcb32dae19a2edbf552e9fd2f52eb8`
- Q1_0 sidecar enabled: `false`
- Q1_0 runtime observed: `false`
- Q1_0 route calls: `0`
- Q1_0 route slots: `0`
- Q1_0 selected loads: `0`
- Q1_0 failures: `0`
- Q1_0 resident mode: `0`
- Q1_0 resident hits/misses: `0` / `0`
- Q1_0 resident H2D bytes: `0`
- Q1_0 direct pread fallbacks/bytes: `0` / `0`
- Structural smoke eligible: `false`
- Performance eligible: `false`
- Quality eligible: `false`

This only confirms that the env-off path did not observe Q1_0 and preserved the
known content hash for this single process.

## Gate B: negative opt-in

Result: pass as a fail-closed diagnostic.

- Artifact: `g7_runs/g7_g109_b_q1_no_selected_fail_closed_n1_stderr.log`
- Sidecar validated for active layer `42..42`.
- The runtime installed the Q1_0 sidecar, then reached a routed Q1_0 path
  without `DS4_Q1_0_SELECTED_LOAD=1`.
- Diagnostic observed: `Q1_0 sidecar requires opt-in selected expert loading at layer=42`.
- The server then reached the benchmark shutdown path cleanly.

No fallback to the IQ2 whole-tensor loader is evidenced in this log. The named
evidence set does not include a B result JSON, so this gate is reported from
stderr diagnostics rather than from a counter row.

## Gate C: direct-file structural smoke

Result: pass as a direct-file structural smoke.

- Artifact: `g7_runs/g7_g109_c_q1_direct_file_structural_n1_result.json`
- Server exit code: `0`
- Repeats: `1`
- Warmup: `false`
- Sidecar: `C:\ds4-models\ds4-q1-layer42-derived-iq2-84b4ffb.gguf`
- `DS4_Q1_0_SELECTED_LOAD=1`
- `DS4_Q1_0_RESIDENT_ARENA` unset
- Active layer: `42..42`
- Sidecar provenance verified: `true`
- Q1_0 runtime observed: `true`
- Q1_0 route calls: `9`
- Q1_0 route slots: `78`
- Q1_0 selected loads: `9`
- Q1_0 failures: `0`
- Resident mode: `0`
- Resident hits/misses/H2D bytes: `0` / `0` / `0`
- Direct pread fallbacks: `9`
- Direct pread bytes: `251265024`
- Bootstrap entries: `0`
- Runtime contract valid: `true`
- Structural smoke eligible: `true`
- Performance eligible: `false`
- Quality eligible: `false`
- Retained output SHA-256: `8a17fc0dc61e8520bdbe3a735b000358a6476cbe9f0e3d86c54a51cf26b5d009`
- Retained output text: `Hello! How can I help you today`

The stderr summary agrees with the JSON counters and reports
`iq2_vram_cache=q1-routes-bypass`, `iq2_host_arena=unchanged` and
`mixed_host_backing=n/a`.

## Gate D v1: geometry blocker

Result: failed before serving, then fixed by `eabf03c`.

- Failure artifact: `g7_runs/g7_g109_d_q1_resident_arena_structural_n1_failure.json`
- Failure reason: `server-not-ready`
- Failure HEAD: `7c50d90b4ab04c7d216723f9d8e7654ac11d615a`
- Stderr blocker: `CUDA dynamic arena rejected layer 42 Q1_0 gate tensor geometry`
- Follow-on diagnostic: `CUDA dynamic arena requested but unavailable; Q1_0 resident mode failed closed`
- Summary counters at failure: calls `0`, slots `0`, selected loads `0`,
  failures `0`, resident mode `1`, resident hits `0`, resident misses `0`,
  resident H2D bytes `0`, direct pread fallbacks `0`, direct pread bytes `0`,
  candidate entries `0`

The blocker was not a routed-execution miss or a mixed-backing ambiguity. It was
an arena tensor geometry rejection before a CUDA session was created. Commit
`eabf03c877a18b87fd62a88229eef91f8ac23b9e` fixed that by accepting the Q1_0
arena tensor geometry.

## Gate D v2: resident-arena structural smoke

Result: pass as resident Q1_0 structural evidence.

- Artifact: `g7_runs/g7_g109_d_q1_resident_arena_structural_n1_v2_result.json`
- Server exit code: `0`
- Repeats: `1`
- Warmup: `false`
- Sidecar: `C:\ds4-models\ds4-q1-layer42-derived-iq2-84b4ffb.gguf`
- `DS4_Q1_0_SELECTED_LOAD=1`
- `DS4_Q1_0_RESIDENT_ARENA=1`
- Active layer: `42..42`
- Sidecar provenance verified: `true`
- Q1_0 runtime observed: `true`
- Q1_0 route calls: `9`
- Q1_0 route slots: `78`
- Q1_0 selected loads: `9`
- Q1_0 failures: `0`
- Resident mode: `1`
- Resident hits: `71`
- Resident misses: `0`
- Resident H2D bytes: `251265024`
- Direct pread fallbacks: `0`
- Direct pread bytes: `0`
- Bootstrap entries: `256`
- Runtime contract valid: `true`
- Structural smoke eligible: `true`
- Performance eligible: `false`
- Quality eligible: `false`
- Dynamic arena allocated bytes: `1072300032`
- Dynamic arena allocated slots: `303`
- Dynamic arena slot bytes: `3538944`
- Retained output SHA-256: `8a17fc0dc61e8520bdbe3a735b000358a6476cbe9f0e3d86c54a51cf26b5d009`
- Retained output text: `Hello! How can I help you today`

The D v2 stderr gives the resident boundary explicitly:

- Q1_0 arena bound with `backing=q1_0`, layers `42..42`
- `iq2_host_arena=disabled`
- `mixed_host_backing=not-implemented`
- `iq2_vram_cache=q1-routes-bypass`
- Arena capacity: requested/chosen `1072300032` bytes, `303` slots,
  `3538944` bytes per slot
- Bootstrap: `entries=256`, `source=sidecar-mmap`, `route_pread=disabled`
- Router unchanged, dynamic masks not implemented
- Final arena line: hits `71`, misses `0`, fatal `0`, uploaded `0.23 GiB`,
  backing `q1_0`

## Isolated C/D transport matrix (`n=3` per arm)

Question: after proving both Q1_0 paths structurally, does replacing the
per-route direct file read with the resident host arena improve the same
single-layer Q1_0 workload?

Protocol: six independent processes in balanced order `C-D-D-C-C-D`, prompt
`Hi`, greedy/no-think, context `256`, eight generated tokens, one active Q1_0
layer (`42`), no Q8/F16 cache and three-sample quiescence preflight before each
process. C is the direct-file Q1_0 loader. D is the resident Q1_0 arena. This is
an isolated transport comparison, not an IQ2-versus-Q1_0 or G46/G73 SOTA A/B.

| Arm | Process decode t/s | Mean / median | HTTP t/s mean | TTFT mean / median |
|---|---:|---:|---:|---:|
| C direct file | `2.45, 2.58, 2.58` | `2.5367 / 2.58` | `1.2845` | `2.7173 / 2.714 s` |
| D resident arena | `2.61, 2.44, 2.67` | `2.5733 / 2.61` | `1.2895` | `2.7247 / 2.650 s` |

Measured candidate deltas versus direct file:

- server decode mean: `+1.4455%`;
- HTTP end-to-end t/s mean: `+0.3923%`;
- TTFT mean: `+0.2699%` (slower); the median moved from `2.714` to `2.650 s`;
- all six outputs were byte-identical, retained output SHA-256
  `8a17fc0dc61e8520bdbe3a735b000358a6476cbe9f0e3d86c54a51cf26b5d009`;
- every process recorded nine Q1_0 route loads and `251265024` route bytes;
- C read `753795072` total bytes through nine direct-file fallbacks per process;
- D moved the same `753795072` total bytes H2D from resident RAM, with `71`
  resident hits per process, zero resident misses and zero routed direct reads.

Verdict: elimination of routed `pread` is measured and exact for this fixture.
The throughput effect is small relative to the run-to-run range; the earlier
single-process apparent 2x uplift is not reproduced by the balanced matrix and
must not be retained as a performance result. On this warm 865 MiB, one-layer
fixture, file reads are not the dominant decode cost. Per-route H2D/sync remains,
and the resident Q1_0 path still excludes the complete G46/G73 stack.

## Current mixed-arena boundary

Gate D proves only that selected Q1_0 routed experts for layer 42 can be served
from the resident host arena with zero routed direct pread. It does not prove
composition with the current G73/G46 throughput stack.

The current Q1_0 resident mode owns the native host arena. In D v2, the runtime
explicitly disabled the IQ2 host arena and reported mixed host backing as not
implemented. It also bypassed the IQ2 VRAM cache for Q1_0 routes. Therefore this
run is not a comparison against mixed IQ2/Q1_0 arena composition, prefill-mass
tiering, dynamic mass masks or a representation-neutral resolver.

Before any SOTA A/B or performance comparison, the boundary remains one of:

1. implement disjoint Q1_0 and IQ2 host arenas with a representation-neutral
   resolver;
2. implement a unified arena with explicit backing/source identity per entry; or
3. provide a full routed-layer Q1_0 sidecar that removes the mixed-backing
   boundary for the measured domain.

## Conclusion

G109 establishes structural viability for the first native Windows Q1_0 routed
expert sidecar:

- env-off exactness remained clean in A;
- missing selected-load opt-in failed closed in B;
- direct-file selected Q1_0 routing was observed in C;
- resident Q1_0 arena routing was observed in D v2 after the D v1 geometry fix.

Gates A-D alone do not establish speedup, quality, SOTA status, or full-domain
residency. The C/D matrix establishes only a small isolated transport delta.
The sidecar is single-layer, and the current arena model is not yet
mixed-backing capable.
