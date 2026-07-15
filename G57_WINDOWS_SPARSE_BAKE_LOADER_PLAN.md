# G57 Windows sparse-bake loader plan

Status: design frozen; implementation and GPU validation blocked until the
K60/K75 Windows verifier reports `GPU/DISCO LIBERI`.

## Purpose

Consume a physically sparse, self-describing DS4 bake without ever treating an
absent routed expert as a valid zero-filled expert. K60 is the primary target;
K75 is a headroom fallback. These are explicit bake-scoped static models, not
reusable request/domain masks and not a replacement for dynamic REAP tiering on
the full model.

## Measured artifacts

| Bake | Pack bytes | Payload bytes | Held-out call coverage | Held-out gate-mass coverage | Quality conditions |
|---|---:|---:|---:|---:|---|
| K60 mass | 57,842,530,728 | 57,842,328,448 | 90.4551% | 91.4909% | L2/L2/L2 |
| K75 mass | 68,600,895,205 | 68,600,718,208 | 96.9771% | 97.5360% | L1/L2/L2 |

The three quality values are temperature robustness conditions, not iid n=3.
No quality verdict stronger than the recorded grades is claimed. The K75 result
also shows that greater retained coverage did not automatically improve the
observed grade.

## Producer format

The R2 transport pack is:

```text
PACK_MAGIC[16]
payload[payload_bytes]
manifest_json[manifest_len]
PACK_FOOTER[88]
```

`PACK_MAGIC` is `DS4BAKEPACKv1` with NUL padding. The little-endian footer is
`<16sQ32s32s>`: end magic, manifest length, payload SHA-256, and manifest
SHA-256. The payload contains retained extents concatenated in manifest order;
it has no per-extent tags.

The Windows unpacker creates an NTFS sparse GGUF-shaped file:

```text
original GGUF logical region[source_model_size]
manifest_json[manifest_len]
retained_bitset[mask_len]
FILE_FOOTER[56]
```

The footer is little-endian `<16sIIIIQQII>`: `DS4BAKEFILEv1`, version, layer
count, expert count, mask length, original source size, manifest length,
manifest CRC32, and mask CRC32.

The retained bitset is layer-major and uses 32 bytes per layer for 256 experts.
Bit `expert % 8` in byte `layer * 32 + expert / 8` is one when that expert is
physically present. A zero bit means the corresponding expert slices are sparse
holes and must never be routed or read.

Canonical producer and verifier:

- `reap-loop/scripts/ds4_windows_sparse_bake.py`
- `reap-loop/tests/test_ds4_windows_sparse_bake.py`

## Runtime hazard

The current Windows runtime maps the entire file and resolves tensor bytes as
`model.map + tensor.abs_offset`. Windows sparse holes therefore return zeros.
Without a runtime-enforced retained bitset, inference can silently consume
zero-filled expert weights.

Router bias alone is insufficient. Early layers use
`layer_hash_selected_experts()`, which reads the token-id routing table and can
bypass top-k REAP bias. Every route and every final expert-use boundary must be
protected.

The draft `reap-loop/patches/ds4/0053-windows-embedded-bake-mask.patch` is a
useful parser sketch but must not be applied unchanged because:

1. It installs the bake mask in process-global REAP state instead of engine
   state.
2. It does not add the required final selected-expert guard.
3. It does not make hash routing fail closed on absent experts.
4. It does not validate enough manifest identity to bind the bake to the
   intended source model.

## Required engine contract

Add immutable bake metadata to `ds4_engine` ownership. The model loader may hold
the parsed trailer while opening, but the effective allowed set and its identity
must become per-engine state before any backend cache or request is created.

The engine state must include:

- `bake_embedded` and format version.
- Logical source GGUF size and physical mapped size.
- Layer/expert dimensions and retained bitset.
- Manifest/mask checksums and source-model identity from the manifest.
- Per-layer retained counts.

No global mutable bake mask is allowed. Existing external REAP masks remain a
separate mechanism and must conflict fail closed with a sparse bake.

## Loader gates

Run these gates immediately after mmap and before normal GGUF bounds validation:

1. Probe the final 56 bytes for `DS4BAKEFILEv1`. A normal GGUF without this
   footer continues unchanged.
2. Validate version, expected geometry, mask length, overflow-safe trailer
   arithmetic, and exact physical mapped size.
3. Validate manifest and mask CRC32 values.
4. Parse the compact JSON manifest with a structured parser or a narrow,
   fail-closed parser. Do not use substring extraction.
5. Reconstruct the retained bitset from manifest layer selections and require
   exact equality with the embedded bitset.
6. Validate source size, tensor geometry, retained counts, extent ordering,
   non-overlap, and that every retained expert has all gate/up/down slices
   present. If `source_model_sha256` is present, require a valid 64-hex value
   and match it to an explicitly supplied expected identity.
7. Require at least `DS4_N_EXPERT_USED` retained experts in every routed layer.
8. Set the logical model size to `source_model_size` before ordinary tensor
   range checks so the appended trailer is never exposed as GGUF tensor data.

Any recognized but invalid bake footer is fatal. There is no permissive fallback
to an ordinary GGUF once the bake magic is present.

The current K60/K75 manifests record `source_model_sha256: null`; runtime code
must not claim that hash was verified. Their identity chain is the externally
verified full pack SHA-256, the embedded manifest/mask CRCs, and an exact match
of source size plus routed GGUF tensor geometry. Future packs should include the
source hash so the additional runtime gate can become mandatory.

## Routing and read guards

The embedded bitset defines a hard allowed set for this physical bake:

- Top-k routing: apply the immutable bake bias before selection on CPU and GPU.
- Hash routing: validate all six table-selected experts against the bitset. An
  absent expert is a fatal model/route incompatibility; do not substitute a
  different expert silently.
- CPU expert math: assert every selected expert is retained before resolving
  gate/up/down pointers.
- CUDA staging: assert every selected expert is retained before
  `cuda_moe_selected_load()` or any arena/cache source span is constructed.
- Cache/preload enumeration: never schedule absent expert extents.

The final CPU/CUDA guards are mandatory even after router masking. They turn a
missed integration path into a clear startup/request failure instead of a
plausible-looking but corrupt output.

## Implementation sequence

1. Parser-only unit tests using tiny synthetic sparse files: normal GGUF,
   valid bake, bad magic/version, overflow, CRC mismatch, bitset/manifest
   mismatch, too few retained experts, and conflicting external mask.
2. Per-engine metadata and normal-GGUF no-op compatibility.
3. CPU top-k/hash/use guards with a synthetic route test.
4. CUDA bias installation and pre-staging guard.
5. Sparse-aware startup cache enumeration.
6. K60 startup safety run: manifest identity, retained counts, no absent reads,
   server exit zero, and coherent temp0/nothink output. This n=1 run is only a
   functional gate.
7. K60 quality and performance run under a quiescent machine. Performance and
   quality claims require the existing n>=3 protocol and grading rules.
8. Consider K75 only after measured Windows memory headroom and K60 results.

## Non-goals

- No dynamic mask changes outside the physically retained set.
- No silent fallback from an absent expert to zero weights or a replacement.
- No SOTA claim from the contaminated G55 safety window or from n=1.
- No GPU run while downloads, hashing, unpacking, or verification contaminate
  the machine.

## Current unblock conditions

Implementation can begin from this contract, but local artifact validation and
all DS4 runs remain blocked until the external verifier completes:

1. exact downloaded size;
2. full pack SHA-256 against producer receipts;
3. NTFS sparse unpack;
4. manifest/bitset/footer inspection;
5. explicit `GPU/DISCO LIBERI` handoff.
