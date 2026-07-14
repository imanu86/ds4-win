# G19A observed-residency gate

## Scope

G19A connects G18's transactional pinned arena to real current-session routing
without changing router scores, top-k, or masks. It is a residency-only
mechanism gate, not the G19 LIVEMASK implementation.

With `DS4_CUDA_DYNAMIC_ARENA_OBSERVED_WINDOW=W`, decode observes the exact
top-6 IDs that selected-load already copies to the host. For layers 3..42 it
builds the union seen during the first W decode tokens. At the next token
boundary it:

1. starts a G18 arena transaction;
2. orders missing experts by model-file offset;
3. copies full gate/up/down triplets with bounded workers;
4. verifies every slot with FNV-1a;
5. publishes all bindings atomically, or aborts and keeps the old snapshot.

The policy is disabled by default. `ds4_session_sync()` resets observation for
each successful interaction while an older arena snapshot remains only a
residency hint.

## Correctness gate

Build: native Windows CUDA 12.6, RTX 3060 12 GB, model
`C:\ds4-models\ds4-2bit.gguf`, branch `port/windows-dynamic-arena-0051`.

- Policy-off `Hi`, greedy/nothink: exact output
  `Hello! How can I help you today?`.
- SHA-256:
  `fda564ba3f7a0f028106d468420f674898ed99ac5bf2765ac9586206e39d73c5`.
- Cyber64 policy-on: exact historical policy-off SHA-256
  `fd6c4522975a71e252b90199d49cfe3236310e2a7285dc0fc4d0e9d0e4885510`.
- All six controlled A/B outputs had that same Cyber64 hash.
- Arena fatal errors: zero in every run.

This equality is expected: G19A changes only where bytes reside.

## Controlled A/B

The comparison holds arena allocation constant at 12 GiB so it does not
confound observer effects with the mapped-window switch. Each sample is a new
server process, with no shared warmup session. Order was counterbalanced
`OFF, ON, ON, OFF, OFF, ON`.

Common parameters:

- prompt: Cyber64 (`prompt_sha256=38f6ec5e...3b6`);
- `max_tokens=64`, greedy, nothink;
- `DS4_CUDA_DYNAMIC_ARENA_GB=12` (1,820 slots);
- selected-load enabled, expert cache off, SPEX off, I/O QD 1;
- RAM-stream budget 2 GiB, reserve 1,024 MiB;
- ON only: observed window 16 and 8 WRAP workers.

| Run | Arm | Server decode t/s | Tail 14 t/s | WRAP s | Hits | Misses |
|---|---:|---:|---:|---:|---:|---:|
| 1 | OFF | 2.38 | 1.98 | 0 | 0 | 0 |
| 2 | ON | 1.87 | 2.59 | 10.733 | 6,272 | 6,094 |
| 3 | ON | 1.95 | 2.62 | 10.705 | 6,272 | 6,094 |
| 4 | OFF | 2.24 | 1.94 | 0 | 0 | 0 |
| 5 | OFF | 2.21 | 1.95 | 0 | 0 | 0 |
| 6 | ON | 1.87 | 2.51 | 10.386 | 6,272 | 6,094 |
| Mean | OFF (n=3) | **2.277** | **1.957** | 0 | 0 | 0 |
| Mean | ON (n=3) | **1.897** | **2.573** | **10.608** | 6,272 | 6,094 |

Every ON run learned exactly 1,435 resident experts (about 9.7 GiB), published
generation 1, and produced the same 50.7% hit share. Subtracting only the
separately measured WRAP wall time gives an informational, not causal,
throughput estimate of 2.769 t/s.

## Verdict

The mechanism is correct and residency improves measured post-publish decode:
the final 14-token block rises from 1.957 to 2.573 t/s (+31.5%). The current
synchronous implementation is not production-useful for a 64-token response:
the 10.608-second duplicate WRAP read makes total decode 16.7% slower.

The next gate must remove that duplicate read. During W16, selected-load already
streams every newly observed gate/up/down triplet through pinned staging. G19B
should mirror those bytes into inactive arena slots on the same fetch, then make
the token-17 transaction retain and publish the verified preloaded slots. This
preserves atomic publication while distributing a RAM memcpy/checksum instead
of rereading about 9.7 GiB at the boundary.

## Harness

`g7_measure.ps1` now records the requested arena/window/worker parameters and
parses observer, WRAP, generation, final hit/miss/fatal, and uploaded-GiB
telemetry into each result JSON.

Artifacts are under `g7_runs/g7_g19a_*` and remain local benchmark output.
