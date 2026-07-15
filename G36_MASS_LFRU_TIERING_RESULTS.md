# G36: Mass/LFRU Slow-Clock Tiering

## Question

Can an exact, slow-clock mass/LFRU admission policy retain the G35 pinned-RAM
tiering gain while reducing physical VRAM churn?

G36 changes placement only. It does not change router scores, selected expert
IDs, masks, quantized expert bytes, sampling, or output arithmetic.

## Policy

The G35 `second-touch` policy remains the default and the A/B control. The new
opt-in policy is:

```text
DS4_EXPERT_TIERING=enforce
DS4_EXPERT_TIER_POLICY=mass-lfru
DS4_EXPERT_TIER_CLOCK_CALLS=430
DS4_EXPERT_TIER_REPLACEMENT_BUDGET=16
DS4_EXPERT_TIER_MIN_FREQUENCY=3
DS4_EXPERT_TIER_HYSTERESIS=1.25
```

The cold invariant is unchanged: first touch is
`SSD_COLD -> RAM_PROBATION`, followed by transient H2D for the exact current
route. A cold expert never enters persistent VRAM directly.

For each selected route, G36 updates:

```text
mass = 0.95 * mass + abs(router_weight)
score = mass * (1 + ln(1 + frequency)) / (1 + age / clock_calls)
```

Free VRAM slots may be filled after three observed uses. Once full, the
candidate must beat the lowest-score unclaimed VRAM resident by the 1.25
hysteresis factor. Physical replacements are limited to 16 per 430 route-worker
calls, approximately ten generated tokens across 43 routed layers. Rejected
candidates remain in pinned RAM and use exact transient H2D.

## Protocol

Runner: `g36_mass_lfru_ab.ps1`

Order: `second-touch / mass-lfru / mass-lfru / second-touch`.

Each process used one discarded warmup and `n=3` measured requests:

- native Windows, RTX 3060 12 GB;
- model `C:\ds4-models\ds4-2bit.gguf`, 86,720,111,488 bytes;
- prompt `Hi`, context 256, max 12, greedy no-think response ending after nine
  tokens;
- cache336 LRU, GPU-resident routes, 8 GiB exclusive pinned arena;
- 2 GiB streaming budget, 4 GiB load reserve, 128 MiB runtime reserve;
- Q8-F16 cache off, embedding-row staging on;
- REAP, SPEX, split hit/miss, mask and other observers off;
- expected warmup and measured output SHA-256
  `fda564ba3f7a0f028106d468420f674898ed99ac5bf2765ac9586206e39d73c5`.

The harness fails closed on build inputs, executable hash, effective environment,
runtime transition accounting, output hash, and the replacement budget.

## Results

All 12 measured outputs and all four warmups matched the expected hash.

| Metric | G35 second-touch | G36 mass/LFRU | Delta |
|---|---:|---:|---:|
| Server decode | 4.9483 t/s | 5.5567 t/s | +12.29% |
| Client throughput | 2.8195 t/s | 3.0439 t/s | +7.96% |
| Warmup | 11.498 s | 11.384 s | -0.114 s |
| VRAM hits | 3,984 | 5,089 | +27.74% |
| VRAM promotions | 4,299 | 384 | -91.07% |
| VRAM demotions/replacements | 3,963 | 48 | -98.79% |
| Transient routes | 1,005 | 3,815 | +279.60% |
| RAM H2D | 34.963 GiB | 27.679 GiB | -20.83% |
| Process reads | 31.001 GiB | 31.001 GiB | unchanged |
| Final VRAM residents | 336 | 336 | unchanged |

Both G36 runs were counter-identical: 336 free-slot promotions, 48 replacements,
three active policy epochs, 2,010 minimum-frequency skips, 1,753 budget skips,
52 score/hysteresis skips, zero cold-to-VRAM transitions, and zero failures.

## Interpretation

This is an exact positive mechanism and short-prompt throughput result. The gain
does not come from fewer model-file reads: both arms admitted the same 1,005
unique cold experts to pinned RAM and read the same 31.001 GiB per process. It
comes from a more stable VRAM hotset and less repeated RAM-to-GPU movement.

The result does not prove a universal policy for long generations or domain
changes. The prompt is deliberately short and deterministic, and the score,
clock, budget, frequency floor, and hysteresis have only one measured setting.
Before making this the default, repeat on a longer exact workload and a domain
switch where adaptation is required. Keep `second-touch` as the default until
that broader gate passes.

## Provenance

- base HEAD during measurement:
  `083c30572dd4a010f4b6df5ee38c1dd609083818`;
- `ds4_cuda.cu` SHA-256:
  `d6f3daa3fc3554dad0bf11c5c4a93d3744fc2f9be1a508347b11ef521890ae17`;
- executable SHA-256:
  `800471b264c5deb57d1ae4db7017bdaddfbbe96f370c9f4aa35367ddae84675a`;
- build input fingerprint:
  `385e25188f19f468e821852aad94c44e21d6be9b8ed39eedd123f477ed4a2c8e`;
- `g7_measure.ps1` SHA-256:
  `0f8f8099014e7744d68016257334fe86806d28925ee2255cad198648ae521f7f`;
- `g36_mass_lfru_ab.ps1` SHA-256:
  `7fa5c9294fac5114cba43ebd4c1b3b5168c42b3280e41203d2b2b6a344583c8e`;
- final matrix SHA-256:
  `877eb5a6bffd9c61c041b805e972433057a02866db30bb254912d5271bb6dbf5`.

The build manifest records a dirty worktree because the measured source and
harness were intentionally uncommitted during the experiment. Their exact
hashes and the complete compile-input fingerprint above make that state
reproducible. The final matrix artifact is
`g7_runs/g36_mass_lfru_ab_result.json`.
