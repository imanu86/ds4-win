# G31 router D2H profile and mapped-mailbox gate

Date: 2026-07-15

Parent: `a924847` (`G30: execute mixed MoE routes from direct VRAM slots`)

GPU: RTX 3060 12 GB, native Windows/WDDM

Model: `C:\ds4-models\ds4-2bit.gguf` (86,720,111,488 bytes)

## Question

After G30 removed cache-to-compact D2D copies from resident routes, how much
time remains in the CPU selected-expert control path? Can a tiny mapped pinned
mailbox replace the selected-ID D2H copy without changing routing or output?

## Instrumentation

`DS4_CUDA_MOE_ROUTE_PROFILE=1` measures five sections of every successful
`cuda_moe_selected_load()` call:

1. selected-ID D2H and its synchronization;
2. residency/mass observers;
3. CPU dedupe and expert-to-slot mapping;
4. transport/cache work;
5. route-table publication.

The rejected experimental arm, enabled by
`DS4_CUDA_MOE_ROUTER_MAILBOX=1`, launches one GPU thread after routing. It
writes the six selected IDs into a 32-byte `cudaHostAllocMapped` payload,
publishes a sequence after `__threadfence_system()`, and lets the CPU poll the
sequence. Failure falls back to the original exact D2H copy.

This is a mechanism gate (`n=1`), not a throughput verdict. Its purpose is to
decide whether the mailbox removes the measured synchronization before paying
for a clean `n>=3` A/B.

## Controlled commands

Both arms used the same current source and executable
`c8224e792d783cd1a0fcd577f84b878a3dfd4f6c041f22f5ce1870ab2a757523`.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\g7_measure.ps1 `
  -MaxTokens 16 -Warmup -WarmupMaxTokens 16 -Repeats 1 `
  -Tag g31_mailbox_off_repro_n1 -Prompt Hi -WarmupPrompt Hi -Context 256 `
  -BudgetGB 2 -ReserveMB 4096 -RuntimeReserveMB 128 `
  -ExpertCacheN 336 -ExpertCacheReserveGB 0.5 -ExpertCachePolicy lru `
  -DisableQ8F16Cache -EmbedRowStaging -MixedDirectCache -RouteProfile `
  -ModelPath C:\ds4-models\ds4-2bit.gguf
```

The ON arm is identical except for the tag and `-RouterMailbox`.

## Measurements

| Arm | Calls | D2H section | Transport | Publish | Mailbox wait | Fallbacks | Server decode |
|---|---:|---:|---:|---:|---:|---:|---:|
| D2H copy | 840 | 2.853 ms/call | 4.806 ms/call | 0.026 ms/call | n/a | n/a | 3.56 t/s |
| mapped mailbox | 840 | 2.810 ms/call | 4.739 ms/call | 0.027 ms/call | 2.100 ms/call over 720 decode calls | 0 | 3.43 t/s |

Both arms produced exactly `Hello! How can I help you today?` with SHA-256
`fda564ba3f7a0f028106d468420f674898ed99ac5bf2765ac9586206e39d73c5`.

The earlier independent profile measured 2.904 ms/call for the same D2H
section, so the reproduced 2.853 ms value is consistent. CPU observe and map
were 0.000 and 0.001 ms/call respectively.

## Decision

Reject the separate-kernel mapped mailbox. It is exact and had zero fallback,
but it did not remove the control-path wait: the CPU still waits for WDDM to
schedule and complete GPU work. The 24-byte copy is not the bottleneck.

Do not interpret the single-run 3.56 versus 3.43 t/s values as a performance
regression claim. The direct instrumentation is sufficient to reject this
mechanism because the targeted 2.85 ms section remains 2.81 ms.

At 42 routed MoE layers, 2.85 ms/layer is about 120 ms/token. Removing that
wait would move a 3.4 t/s decode path from roughly 294 ms/token toward a
theoretical 174 ms/token, before new bottlenecks, or about 5.7 t/s. This is a
budget calculation from measured components, not a measured throughput claim.

## Next architecture

The next gate must keep the all-resident decision on GPU:

1. maintain a device `expert_id -> resident slot` map;
2. build resident route pointers on GPU;
3. launch resident expert work without a host selected-ID round trip;
4. notify a host miss worker only for true misses;
5. join resident and miss contributions once, preserving exact router IDs and
   exact weights.

Artifacts are under `g7_runs/g7_g31_mailbox_{off,on}_repro_n1_*`.
