# G35: Real Expert Tiering

Date: 2026-07-15

Platform: native Windows, RTX 3060 12 GB, 64 GB RAM

Model: `C:\ds4-models\ds4-2bit.gguf`

## Question

Can exact routed experts follow the physical policy

`SSD_COLD -> RAM_PROBATION -> RAM_WARM -> VRAM_PROTECTED`

without allowing a first cold touch to enter persistent VRAM, while improving
steady-state decode throughput?

## Implementation

`DS4_EXPERT_TIERING=enforce` is off by default and requires GPU-resident routes,
an idle pinned dynamic arena and the Q8-F16 cache disabled.

- A first cold touch is read once into an exclusive pinned-RAM arena slot.
- The current exact computation uses a six-route transient GPU slab. The
  transient pointer is never published in the persistent expert cache map.
- A second touch promotes the exact bytes from pinned RAM to a persistent VRAM
  slot.
- VRAM eviction demotes to `RAM_WARM`; the pinned RAM copy is retained, so a
  later promotion does not require SSD.
- Router IDs, router weights, masks and numeric representation are unchanged.
- Per-expert frequency, recency, router-weight mass and an LFRU score are
  recorded. G35 does not yet use mass/LFRU to throttle physical promotion.
- Arena ownership is exclusive while enforcement is active. Slot generations
  guard cleanup and stale RAM state self-heals by re-admitting from SSD.

The selected-load prefill path remains exact through its compact buffers but is
not allowed to populate persistent VRAM while tiering enforcement is active.
Decode fails closed if the GPU route worker is unavailable.

## Protocol

Runner: `g35_tiering_ab.ps1`

Order: `off / enforce / enforce / off`

Each run: one discarded warmup plus `n=3` measured requests.

Common configuration:

- prompt `Hi`, context 256, max 12; model stops after 9 tokens;
- dynamic arena 8 GiB in both arms;
- expert cache 336, LRU;
- GPU-resident routes on;
- stream budget 2 GiB, startup reserve 4096 MiB, runtime reserve 128 MiB;
- embedding-row staging on;
- Q8-F16 cache off;
- SPEX, REAP physical rotation, split hit/miss and arena observers off.

Every measured output and warmup had content hash
`fda564ba3f7a0f028106d468420f674898ed99ac5bf2765ac9586206e39d73c5`.

## Results

| Run | Mode | Client t/s | Server decode t/s | Prefill/TTFT | Warmup |
|---|---|---:|---:|---:|---:|
| control A | off | 2.217359 | 3.230000 | 1.272 s | 4.300 s |
| enforce A | enforce | 2.891688 | 4.993333 | 1.311 s | 11.403 s |
| enforce B | enforce | 2.890190 | 4.956667 | 1.300 s | 11.360 s |
| control B | off | 2.179893 | 3.226667 | 1.337 s | 4.102 s |

Aggregates:

| Metric | Control | Enforce | Delta |
|---|---:|---:|---:|
| server decode t/s | 3.228333 | 4.975000 | +54.10% |
| client t/s | 2.198626 | 2.890939 | +31.49% |
| process reads/run | 60.275 GiB | 31.001 GiB | -48.57% |
| warmup | 4.201 s | 11.381 s | +7.180 s |

Both enforcement runs were deterministic and reported:

- 1,005 cold touches and 1,005 `cold_to_ram` transitions;
- zero `cold_to_vram`, zero RAM admission skips and zero failures;
- 1,005 transient first-touch GPU uses;
- 4,299 RAM hits/promotions and 3,963 VRAM demotions;
- 1,005 experts retained in pinned RAM at shutdown, of which 336 were also in
  persistent VRAM;
- 6.625 GiB exact SSD admission reads and 34.963 GiB RAM-to-GPU traffic.

## Verdict

Promote P3 as an exact positive mechanism and throughput checkpoint. The
pay-once pinned-RAM tier materially reduces repeated file reads and raises hot
decode above the prior 3.4 t/s local target.

Do not yet call the policy optimal. Promoting every second touch causes 4,299
promotions and 3,963 demotions in this short matrix. The next isolated test is
mass/LFRU admission at a slower clock with hysteresis, preserving the G35
first-touch invariant while reducing physical VRAM rotation.

## Provenance

- `ds4_cuda.cu` SHA-256:
  `2b876f096c8f2ff80936b15613ddfc8c4779431dd739d4f94a75fef5e2b75290`
- executable SHA-256:
  `1ba3a51f2e13bad2f48bad6ed3067587ef4d41c58dacd4ed912f783be21ca554`
- build input fingerprint:
  `e23c12c92a95d05ec949048d8bee0d8f9192ad292c1221ffbf6fa45d3c3dbfd7`
- `g7_measure.ps1` SHA-256:
  `81927fb9641af2d233b9163ada4bc9061f491aaf0744313c7f1f6de05197d74c`
- `g35_tiering_ab.ps1` SHA-256:
  `b879b00b331197e7e60a13c53ad17fcf5c8783d0596041daa54ee54a177b230e`
- matrix JSON SHA-256:
  `6b860294fe60921d32314b4077f379496ce2fbac77df3dd9f9f1ac0e117b8c86`

Primary artifacts are under `g7_runs/g7_g35_*` and
`g7_runs/g35_tiering_ab_result.json`.
