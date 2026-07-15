# G55 WRAP file-QD functional safety

Date: 2026-07-15

## Question

Can one Windows thread keep eight overlapped model-file reads in flight and
write each part directly into its final pinned arena slot without changing the
request-scoped snapshot or output?

This is a functional safety result only. Two `rclone` downloads were active on
physical disk D: while DS4 read the model from physical disk C:. System
quiescence was intentionally skipped and recorded as such. No timing,
throughput, cache-rate, TTFT, or decode value from this run is valid for a
performance verdict or the SOTA ledger.

## Provenance

- Branch: `port/windows-dynamic-arena-0051`
- Harness HEAD: `975097a`
- G55 implementation commit: `438dcd6`
- Executable SHA-256:
  `3c1d101f1a39edc66df639c3fcfd88e9b378fc429f2e141c6d3a5c22c7e931b9`
- Build input fingerprint:
  `014a1b9df4e22f1d4b91fee8849b26a81022ccd700100ed1e20be7e7a889137d`
- Tag: `g55_wrap_file_qd8_contaminated_functional_safety`
- Start: `2026-07-15T18:19:39Z`
- Result written: `2026-07-15T18:21:04.7265217Z`
- Model: `C:\ds4-models\ds4-2bit.gguf`
- `system_quiescence_skipped=true`

## Functional result

- `server_exit_code=0`
- requested/observed file QD: `8/8`
- file submissions/completions/failures: `13653/13653/0`
- arena publication: `published`
- snapshot backing misses: `0`
- output SHA-256:
  `31cbc6504dcb57d42aeff9dbceb3aed943bcb32dae19a2edbf552e9fd2f52eb8`
- expected output SHA-256: identical
- DS4 processes after run: `0`
- post-run GPU state: `0%`, `715/12288 MiB`

The mechanism passes functional safety. The observed WRAP duration was
`32.199 s`, versus about `50.2 s` for the earlier clean QD1 G54 runs, but this
is only a hypothesis-generating signal because background downloads remained
active. It must not be claimed as a speedup.

## Decision

Keep the QD path default-off. Once GPU and all disks are quiescent, run the
counterbalanced G55 matrix with three independent processes per arm: QD1 versus
QD8, exact G45/G54 prompt and configuration. Accept a performance change only
if all runs preserve output hash, effective cache capacity, zero snapshot
misses, zero SSD fallback, zero tier failures, zero file-read failures, and
clean contamination telemetry.
