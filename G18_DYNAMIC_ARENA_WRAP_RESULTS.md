# G18 Dynamic Arena WRAP Gate Report

## Gate summary

G18 implements the dynamic-arena lifecycle as `prepare -> WRAP -> publish/abort`, with per-layer geometry. Arena storage is pinned `Default`, not `Mapped`, and selected loads use direct pinned H2D transfer into the compact representation. The feature remains off by default behind `DS4_CUDA_DYNAMIC_ARENA_GB`; `DS4_CUDA_DYNAMIC_ARENA_TEST_KEEP` is diagnostic-only.

Bindings validate model-map identity, tensor offsets, layer, expert, byte
geometry, slot generation, and snapshot generation. A load checksum is
recomputed by the CUDA runtime before a slot can become staged. Transactions
use spare slots and therefore never overwrite the published generation before
publish; insufficient staging capacity fails without weakening the old
snapshot.

## Measured fixture

Final review-fix validation enabled the arena, keep-1 transport fixture, and
the non-destructive abort test:

```powershell
$env:DS4_CUDA_DYNAMIC_ARENA_GB='1'
$env:DS4_CUDA_DYNAMIC_ARENA_TEST_KEEP='1'
$env:DS4_CUDA_DYNAMIC_ARENA_TEST_ABORT='1'
```

Common command shape:

```powershell
powershell -ExecutionPolicy Bypass -File .\g7_measure.ps1 `
  -MaxTokens 12 -Repeats 3 -Warmup -BudgetGB 2 -ReserveMB 1024 `
  -ExpectedContentSHA256 fda564ba3f7a0f028106d468420f674898ed99ac5bf2765ac9586206e39d73c5 `
  -ModelPath C:\ds4-models\ds4-2bit.gguf `
  -Tag g18_reviewfix_keep1_abort_hi12_n3
```

- 151 slots; 6.75 MiB
- 43 resident / 43 loads
- Publish generation 1
- 44 arena hits; 12,712 misses
- Fatal errors: 0
- Uploaded: 0.29 GiB
- Abort validation: passed, returning to keep-1 required 0 reloads
- Server decode mean/min/max: 2.706667 / 2.60 / 2.82 t/s
- Exact repeats: `n=3`
- Output: `Hello! How can I help you today?`
- Output matched the explicit expected SHA-256 on all repeats
- The recorded `ds4_cuda.cu` SHA-256 matched the tested working copy

An earlier consecutive pre-review A/B measured
`g18_final_off_hi12_n3` at
2.743333 / 2.70 / 2.82 server decode t/s and produced the same output hash on
all three repeats. Its keep-1 arm measured 2.913333 / 2.87 / 2.99 t/s, 6.2%
faster in that ordered observation,
but this is not treated as a causal performance verdict: the fixture covers
only 44 of 12,756 arena lookups, the benchmark is short, and arm ordering plus
Windows file-cache state were not controlled. The final review-fix window was
slower than both, reinforcing that no directional performance claim is valid
from these short samples. For descriptive context only, the earlier G17 1 GiB
allocator measured a 2.85 t/s mean.

This first-expert fixture is transport/lifetime proof, not a useful residency
policy. It demonstrates that generation-validated hits bypass pread/staging and
reach the compact execution buffer without changing greedy output.

The first large standalone sweep is now summarized in
`G17_PINNED_ARENA_CAPACITY_RESULTS.md`. It demonstrated 31 GiB allocation and
direct H2D without proportional VRAM consumption, but the host was not clean;
the 50 GiB certification remains pending a Windows restart.

## Gate status

Transport/lifetime behavior is demonstrated for this fixture. Policy value and
performance remain ungated pending G19's session-learned policy integration and
a clean-host capacity/performance sequence.
