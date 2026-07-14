# G22: same-process learned-arena causal gate

Date: 2026-07-14

## Question

Does the greater-than-4 decode rate observed after the first request come from
reusing the learned pinned expert arena, or only from unrelated Windows file
cache warming?

G22 isolates arena lookup inside one server process. Request 1 is an identical
priming request that learns and publishes the arena. Request 2 either keeps or
disables lookup of that already-published arena. Allocation, process lifetime,
model mapping and Windows standby state are otherwise preserved.

## Common protocol

| Parameter | Value |
|---|---:|
| Source HEAD at replicated build | `7d34a2cab20b290b13807c2c912dbb893fbafcd2` |
| Executable SHA-256 | `b040abe8828878b7e44d762d205c49b0eb536b0d13890842e80381281825f878` |
| Model | `C:\ds4-models\ds4-2bit.gguf` |
| Model bytes | 86,720,111,488 |
| GPU | RTX 3060 12 GiB, driver 596.21 |
| Prompt | `Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document.` |
| Prompt SHA-256 | `38f6ec5ee5403f59dd2418eb5d9a5a94a0f0da19df015060383bb1ae46003bb6` |
| Decode | greedy server default, maximum 256 tokens |
| Context / prefill chunk | 256 / 256 |
| Raw / compressed KV rows | 256 / 66 |
| Dynamic pinned arena | 30 GiB, W64, min_hits=1 |
| Published residency | 3,576 expert-layer slots / 23.57 GiB |
| Masked RAM budget / CUDA reserve | 2 GiB / 1,024 MiB |
| WRAP workers / MoE I/O queue | 8 / 1 |
| Expert cache / SPEX / overlap | off / off / off |
| Expected output SHA-256 | `f2677447c1a5e95934469c6c8f07ee943ccd9c079ef9350b07c2d0ce8fc1b576` |

The G22 hook is test-only and opt-in:

```text
DS4_CUDA_DYNAMIC_ARENA_CARRY_ACROSS_REQUESTS=1  # keep
DS4_CUDA_DYNAMIC_ARENA_CARRY_ACROSS_REQUESTS=0  # drop lookup
```

When enabled, request 1 learns normally. Later requests freeze the observer so
the DROP arm cannot silently rebuild the arena. DROP bypasses arena lookup but
does not free or resize the allocation, preserving the same process and memory
layout.

## Safety A/B

| Request-2 arm | Carry telemetry | Server decode t/s | Client completion t/s | TTFT s | Exact output |
|---|---|---:|---:|---:|:---:|
| DROP | `snapshot=3577 resident=3576 lookup=disabled observer=frozen` | 1.42 | 1.269 | 18.148 | yes |
| KEEP | `snapshot=3577 resident=3576 lookup=enabled observer=frozen` | 4.32 | 3.852 | 6.034 | yes |

Both measured responses produced 213 completion tokens and the same expected
content hash. The server-wide reference run before the explicit hook produced
4.29 t/s on request 2, reproducing the historical G19B2 greater-than-4 tail in
the same local RTX 3060 environment. It used the previous executable and
republished the arena, so it is supporting continuity evidence, not a third
KEEP replica.

KEEP is 3.04x the DROP server decode rate in this paired safety run. This is
strong mechanism evidence because each compared request occurs after the same
priming operation and the KEEP/DROP change is inside a preserved process. The
arms still used separate server processes in a fixed order, with different
unpurged standby levels. By itself it was n=1 per arm and was not a
sustained-performance or cold-cache verdict; the independent replication below
was therefore required before promotion.

The arena final counters are process-cumulative. KEEP records 72,998 hits and
23,468 misses across both requests. DROP records only the first request's
27,890 hits and 10,534 misses because request-2 lookup is deliberately bypassed;
those counters must not be interpreted as request-2 disk traffic. Win32 process
read bytes also exclude mmap page-ins, so G22 proves lookup causality, not a
complete storage-traffic decomposition.

## Independent order-balanced replication

The preregistered campaign used six independent server processes in this exact
order:

```text
DROP, KEEP, KEEP, DROP, DROP, KEEP
```

Each process performed one identical priming request and one measured request.
All six measured responses produced 213 tokens with the expected content hash.

| Arm | Independent server decode samples (t/s) | Median t/s | Minimum t/s | Median TTFT |
|---|---|---:|---:|---:|
| DROP | 1.42, 1.56, 1.57 | 1.56 | 1.42 | 16.142 s |
| KEEP | 4.55, 4.42, 4.60 | 4.55 | 4.42 | 5.646 s |

The KEEP/DROP median ratio is 2.92x. The preregistered promotion gate passed:

1. three valid independent processes per arm;
2. KEEP median at least 4.0 t/s;
3. every KEEP at least 3.8 t/s;
4. KEEP/DROP median ratio at least 2.0; and
5. all expected output hashes exact.

Retained learned arena residency is therefore promoted to the Windows-native
transport baseline for subsequent isolated tests. This result is a causal
transport and exact-output result on one repeated prompt. It is not evidence
that a residency set learned from one domain is optimal for another domain,
and it is not an L0-L3 quality campaign.

## Harness gate

`g7_measure.ps1` now fails closed when carry testing is requested unless:

1. every expected request emits an arena-carry marker;
2. the final request reports the requested KEEP/DROP mode and lookup state;
3. the learned snapshot and resident set are non-empty;
4. the observer remains frozen after request 1; and
5. exactly one observer publication and one WRAP publication occur.

## Reproduction

Use the same command twice, changing only the final carry value:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\g7_measure.ps1 `
  -Tag g22_carry_<keep-or-drop>_w64_m1_arena30_cyber256_n1 `
  -Prompt 'Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document.' `
  -ModelPath 'C:\ds4-models\ds4-2bit.gguf' `
  -MaxTokens 256 -Repeats 1 -Warmup -BudgetGB 2 -ReserveMB 1024 `
  -DynamicArenaGiB 30 -DynamicArenaObservedWindow 64 `
  -DynamicArenaObservedMinHits 1 -DynamicArenaCarry <keep-or-drop> `
  -ReapPrefetchThreads 8 -IoQD 1 -Context 256 `
  -ExpectedContentSHA256 f2677447c1a5e95934469c6c8f07ee943ccd9c079ef9350b07c2d0ce8fc1b576 `
  -TimeoutSec 900
```

## Artifacts

- `g7_runs/g7_g22_sameproc_reuse_w64_m1_arena30_cyber256_safety_n1_*`
- `g7_runs/g7_g22_carry_drop_w64_m1_arena30_cyber256_safety_n1_*`
- `g7_runs/g7_g22_carry_keep_w64_m1_arena30_cyber256_safety_n1_*`
- `g7_runs/g7_g22_carry_ab_20260714_{1..6}_*`
- `g7_runs/g7_g22_carry_ab_20260714_aggregate.json`

## Next decision

Do not optimize the repeated-prompt number in isolation. The next measurement
is a cross-domain request-2 gate using this promoted configuration: request 1
learns on the Cyber HTML prompt, while request 2 uses a distinct deterministic
prompt. Compare retained residency with lookup disabled before adding dynamic
growth or rotation. This establishes whether the current arena is a reusable
transport cache or merely a same-prompt specialization. If transfer is weak,
test one adaptation lever at a time, beginning with the already-measured
grow-only residency mechanism.
