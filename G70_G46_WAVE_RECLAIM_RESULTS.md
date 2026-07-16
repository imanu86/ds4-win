# G70 Full-Model G46 Waved Reclaim Results

Date: 2026-07-16

## Verdict

`CAPACITY ASYMMETRY CONFIRMED / CANDIDATE-ONLY N=3 EXACT / NO CAUSAL A/B CLAIM`.

The legacy G46 arm without source-range reclaim could not build the full
30 GiB / 4551-slot arena under the current 38 GiB-available host state. The
4 GiB waved-reclaim candidate did build the same full arena and preserved the
G46 64-token exact output in every completed run.

The authoritative same-HEAD candidate cohort measured `4.58 t/s` mean and
`4.59 t/s` median. This is a valid absolute full-model result. It is not a
same-provenance causal speed comparison against legacy G46 because that arm
failed the capacity gate before token one.

## Frozen Configuration

- model: `C:\ds4-models\ds4-2bit.gguf`, 86,720,111,488 bytes;
- prompt: G46 cyberpunk single-file HTML prompt;
- context 256, max 64, temp 0, nothink;
- expected SHA-256:
  `31cbc6504dcb57d42aeff9dbceb3aed943bcb32dae19a2edbf552e9fd2f52eb8`;
- dynamic arena: 30 GiB / 4551 slots;
- source-parts WRAP, eight workers, trusted worker checksum;
- source-range reclaim: enabled, 4 GiB page-aligned waves;
- expert cache: 320 slots, 0.125 GiB reserve, LRU;
- GPU-resident routes and no-default-sync enabled;
- prefill mass WRAP plus composed enforce tiering;
- mass/LFRU clock 430, budget 16, minimum frequency 3, hysteresis 1.25;
- Q8-F16 cache disabled; embedding row staging enabled.

## Legacy Capacity Gate

The legacy safety process started with about 38 GiB available. During WRAP its
last three telemetry samples recorded `6,344,704`, `423,350,272` and
`740,655,104` available bytes while disk queue was 16, 12 and 16. The unchanged
guard observed three consecutive low-memory/deep-queue samples and terminated
the request at 42.544 seconds.

No legacy token or throughput value exists. This is capacity evidence only.

## Candidate Safety

The first candidate safety published all 4551 slots, completed nine reclaim
waves, produced the expected content hash and measured `4.55 t/s`. Reclaim
reported zero failures, snapshot misses, SSD bytes and tier failures. This was
`n=1`; its timing is not a verdict.

## Authoritative Candidate Cohort

The initial `a/b/c` cohort was followed by the preregistered outlier extension.
The runner/outlier summarizer was repaired between those cohorts without
changing the runtime binary, CUDA source, harness, model or launch contract.
The `x1/x2/x3` extension therefore forms the authoritative same-HEAD `n=3`
cohort. The earlier rows remain diagnostic and are not pooled into its means.

| Run | Decode t/s | TTFT | WRAP | TTFT-WRAP | Min available | Exact |
|---|---:|---:|---:|---:|---:|---|
| x1 | 4.59 | 52.644 s | 29.103 s | 23.541 s | 2.585 GiB | yes |
| x2 | 4.56 | 53.111 s | 29.911 s | 23.200 s | 2.514 GiB | yes |
| x3 | 4.59 | 52.247 s | 28.937 s | 23.310 s | 2.940 GiB | yes |
| mean | 4.58 | 52.667 s | 29.317 s | 23.350 s | - | 3/3 |
| median | 4.59 | 52.644 s | 29.103 s | 23.310 s | - | 3/3 |

All three runs had the same deterministic transport population:

- VRAM route hits: 5653;
- pinned-RAM route hits: 10,859;
- pinned-RAM H2D: 71.580322 GiB;
- snapshot backing misses: 0;
- SSD bytes: 0;
- tier and route failures: 0;
- default-sync calls: 0;
- arena reclaim: three phases, nine waves, zero failures.

Mean Win32 process-read delta was 24.163451 GiB. Mean aggregate disk-read
estimate was 56.414932 GiB. The latter includes mmap page-ins and remains a
diagnostic estimate, not a direct process-read counter.

## Diagnostic WRAP Outlier

The excluded initial cohort measured decode `4.59`, `4.53` and `4.51 t/s`.
Run `c` remained exact but WRAP took `354.613 s`, versus `28.737` and
`28.571 s` in `a/b`. Its TTFT was `378.667 s`, while TTFT-WRAP remained only
`24.054 s`.

Phase logs localized the stall inside source-parts WRAP: gate and up completed,
then mmap page-in traffic delayed the remaining source copy. It was not a
decode slowdown and not a post-WRAP stall. The extension then produced three
normal WRAP times from 28.937 to 29.911 seconds. This establishes an
intermittent cold/source-page WRAP problem; it does not yet identify its cause.

## Comparison Context

Historical G46 measured `4.563333 t/s` mean and `4.58 t/s` median on the same
64-token prompt. G70's authoritative absolute result is `4.58` mean and `4.59`
median, about `+0.365%` and `+0.218%` descriptively. Those deltas are not a
causal reclaim win because no contemporary legacy arm passed capacity.

The operational improvement is measured capacity robustness: G70 preserves
G46-class decode while the legacy full arena aborts under the current host
state. K60/K75 sparse bakes remain an advanced fallback and are not part of the
active roadmap.

## Decision

Keep waved source-range reclaim as the full-model capacity mechanism. Do not
spend the next experiment tuning sparse bakes or repeating G33 split hit/miss.

The next isolated performance target is the unchanged decode transport:
10,859 pinned-RAM routes and 71.580322 GiB H2D over 64 tokens. G71 should make
the VRAM tier budget/protection responsive to measured RAM-hit/H2D pressure,
while preserving cache capacity 320, exact router selection, zero SSD and the
same output hash.

Separately, a later TTFT experiment should trace and reduce the intermittent
source-page WRAP stall. It must not be composed into the first G71 tier-policy
A/B.

## Provenance

- primary run HEAD: `f7dd4c9d567ea0f1ae340f337fe0095717c06d8b`;
- implementation: `be6f1fe`;
- executable SHA-256:
  `9bbcbc57714611bd3873beedc7fc4f0829ee463e0499793b86295eb085cca501`;
- `ds4_cuda.cu` SHA-256:
  `38f4316d7434339167bff4246f16dce1475a9e19ca69f804b63e969afb2b9222`;
- build input fingerprint:
  `ec0b8f38798869d93007809752eae9262d2cb79a75704452fe0e7add7fdc9af1`;
- harness SHA-256:
  `db3a64739dc80d665806176fdb655e63b2c116e87ec793accaf448f25f31c0a7`.

Primary summary:
`g7_runs/g70_g46_wave_reclaim_ab_result.json`.
