# G111 Q1_0 Sparse Snapshot Protocol

G111 replaces the 30 GiB IQ2 host snapshot used by G73 with a Q1_0 host
snapshot learned from the same unbiased prefill routing. It does not add a
second host snapshot.

## Frozen architecture

- Primary model and router remain IQ2/Q2 and unchanged.
- Prefill observes full router mass exactly as G73.
- At the WRAP boundary, the mass-ranked candidate bitmap is copied from the
  Q1_0 sidecar into a pinned host arena.
- Hash-routed layers 0..2 retain all 256 experts (768 fixed entries); layers
  3..42 contribute the 3,783 mass-ranked entries. The Q1 sidecar therefore
  covers layers 0..42 even though adaptive ranking starts at layer 3.
- The request-scoped closed router mask is applied only after the complete Q1
  snapshot is published.
- Exact IQ2 experts already present in the 320-slot VRAM cache have priority.
- Every other selected expert must resolve to the published Q1 snapshot.
- A missing Q1 binding, SSD read, direct pread fallback, partial publication,
  or simultaneous IQ2 host snapshot invalidates the run.

For the G73 candidate count of 4,551 entries, Q1_0 requires about 15 GiB
instead of about 30 GiB for IQ2. Q1 still performs explicit pinned-RAM to GPU
copies; it is not device-mapped and consumes no proportional VRAM.

## Gates

1. Build and static contract pass.
2. One short structural run proves candidate publication, exact IQ2 VRAM
   priority, Q1 resident hits, zero Q1 misses, zero direct pread, and zero SSD.
3. One greedy/no-think exactness safety run uses the frozen G73 prompt.
4. Only after safety passes, run a counterbalanced G73 control versus G111
   candidate matrix with at least three independent clean processes per arm.
5. Throughput claims require matching provenance and L0-L3 quality grading;
   no verdict is permitted from a single run.
