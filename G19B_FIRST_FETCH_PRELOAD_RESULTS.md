# G19B first-fetch arena preload

## Objective

Remove G19A's duplicate boundary read without weakening G18's atomic arena
publication. During the W16 observation window, selected-load already streams
new gate/up/down spans through a small pinned ring. G19B mirrors those exact
bytes into exclusively owned inactive arena slots, verifies each complete
triplet, and leaves it `STAGED`. At token 17, `begin()` adopts matching staged
slots and returns descriptors only for genuinely missing entrants.

This remains residency-only. Router probabilities, top-k, masks, and generated
bytes are unchanged.

## Safety invariants

- Inactive `LOADING` and `STAGED` preload slots have explicit ownership and are
  unavailable to transaction allocation.
- Resolution order is retained active `READY`, matching preload `STAGED`, then
  a new load descriptor.
- Model-map identity, layer, expert, source offset, byte count, and the fixed
  `gate | up | down` layout must all match arena geometry before mirroring.
- Every copied span is compared with its staging source. A slot becomes
  `STAGED` only after all three parts and an FNV-1a checksum.
- `publish()` validates the complete target without side effects, then promotes
  and swaps. A late validation failure cannot leave an orphan `READY` slot.
- Abort preserves the prior active generation. Session reset frees only
  inactive preloads and retains active residency as a hint.

The existing abort fixture passed after these changes: a forced entrant was
aborted, the prior keep-1 snapshot required zero reloads, fatal errors were
zero, and the `Hi` output hash remained
`fda564ba3f7a0f028106d468420f674898ed99ac5bf2765ac9586206e39d73c5`.

## Frequency threshold

Mirroring every expert seen once still writes 9.46 GiB for Cyber64. The
disabled-by-default parameter
`DS4_CUDA_DYNAMIC_ARENA_OBSERVED_MIN_HITS=N` admits only experts selected at
least N times during W16. The current token's ordinary selected-load supplies
the bytes at the threshold crossing, so no extra model read is required.

Single-sample mechanism sweep (not a performance verdict):

| min hits | resident | mirrored GiB | arena hits | server decode t/s | tail t/s |
|---:|---:|---:|---:|---:|---:|
| 1 | 1,435 | 9.46 | 6,272 | 1.88 | about 2.5 |
| 2 | 734 | 4.84 | 5,037 | 2.01 | 2.39 |
| 3 | 439 | 2.89 | 4,247 | **2.17** | 2.27 |
| 4 | 317 | 2.09 | 3,667 | 2.15 | not used for selection |

All four produced the exact historical Cyber64/64 hash
`fd6c4522975a71e252b90199d49cfe3236310e2a7285dc0fc4d0e9d0e4885510`.
The `min_hits=3` candidate was therefore promoted to the controlled test.

## Controlled 128-token A/B

Six independent server processes, no shared warmup, counterbalanced order
`OFF, ON, ON, OFF, OFF, ON`.

Common configuration:

- native Windows, RTX 3060 12 GB, CUDA 12.6;
- `ds4-2bit.gguf`, Cyber64 prompt, greedy/nothink, max 128;
- 12 GiB dynamic arena for both arms;
- selected-load on, expert cache/SPEX/overlap off, I/O QD 1;
- RAM-stream budget 2 GiB, reserve 1,024 MiB;
- ON: W16, `min_hits=3`.

| Run | Arm | decode t/s | final 28 t/s | decode s | resident | hits/misses |
|---|---:|---:|---:|---:|---:|---:|
| 1 | OFF | 2.16 | 2.21 | 59.395 | 0 | 0 / 0 |
| 2 | ON | 2.33 | 2.65 | 54.950 | 439 | 8,410 / 20,468 |
| 3 | ON | 2.30 | 2.63 | 55.558 | 439 | 8,410 / 20,468 |
| 4 | OFF | 2.04 | 2.16 | 62.602 | 0 | 0 / 0 |
| 5 | OFF | 2.05 | 2.17 | 62.385 | 0 | 0 / 0 |
| 6 | ON | 2.31 | 2.64 | 55.315 | 439 | 8,410 / 20,468 |
| Mean | OFF (n=3) | **2.083** | **2.180** | **61.461** | 0 | 0 / 0 |
| Mean | ON (n=3) | **2.313** | **2.640** | **55.274** | 439 | 8,410 / 20,468 |

G19B improves end-to-end decode by 11.0%, saves 6.187 seconds per 128-token
run, and improves the final block by 21.1%. Every run produced the same complete
SHA-256:
`84e295af09e93a34a4ba2bc70c69f2b6f8ee0f129070e6c07d3ba31ea6f97bb1`.
Each ON boundary reported `loads=0`, 439 preloaded slots, 2.89 GiB mirrored,
and a 0.004-0.005 second atomic publish.

## Negative result

Reading each first-fetch span directly from `ReadFile` into its long-lived arena
slot was correct but slower on this WDDM host: the Cyber64/64 safety run fell to
1.78 t/s. The small rotating staging ring plus a verified RAM mirror remains the
measured winner (1.88 t/s with min-hits 1 in the adjacent safety run).

## Next gate

G19B proves a useful dynamic residency substrate. G19C can now add the actual
session-learned router policy: observe full unbiased router probabilities,
build a bounded adaptive keep set, and publish mask/bias with the already staged
residency under one generation. Quality must then be graded L0-L3 at n>=3;
unlike G19A/B, exact output equality will no longer be assumed.
