$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$core = Join-Path $root "ds4.c"
$cuda = Join-Path $root "ds4_cuda.cu"
$header = Join-Path $root "ds4_gpu.h"

foreach ($path in @($core, $cuda, $header)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "G110 mixed Q1 resolver required file missing: $path"
    }
}

$tokens = $null
$errors = $null
[Management.Automation.Language.Parser]::ParseFile(
    $MyInvocation.MyCommand.Path, [ref]$tokens, [ref]$errors) | Out-Null
if ($errors -and $errors.Count -gt 0) {
    throw "G110 mixed Q1 resolver test AST parse failed: $($errors[0].Message)"
}

function Get-SourceBlock {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Start,
        [Parameter(Mandatory = $true)][string]$End,
        [Parameter(Mandatory = $true)][string]$Name
    )
    $startIndex = $Text.IndexOf($Start, [StringComparison]::Ordinal)
    if ($startIndex -lt 0) { throw "G110 block start missing: $Name" }
    $endIndex = $Text.IndexOf(
        $End, $startIndex + $Start.Length, [StringComparison]::Ordinal)
    if ($endIndex -lt 0) { throw "G110 block end missing: $Name" }
    return $Text.Substring($startIndex, $endIndex - $startIndex)
}

function Require-Text {
    param([string]$Text, [string]$Needle, [string]$Contract)
    if ($Text.IndexOf($Needle, [StringComparison]::Ordinal) -lt 0) {
        throw "G110 contract missing ($Contract): $Needle"
    }
}

function Forbid-Text {
    param([string]$Text, [string]$Needle, [string]$Contract)
    if ($Text.IndexOf($Needle, [StringComparison]::Ordinal) -ge 0) {
        throw "G110 forbidden text ($Contract): $Needle"
    }
}

$coreText = Get-Content -LiteralPath $core -Raw
$cudaText = Get-Content -LiteralPath $cuda -Raw
$headerText = Get-Content -LiteralPath $header -Raw

$source = Get-SourceBlock $coreText `
    "static ds4_routed_expert_source routed_expert_source(" `
    "typedef struct {" "primary source during dual mode"
Require-Text $source 'q1_0_dual_arena_requested() <= 0' `
    "dual mode keeps prefill and default decode on authoritative IQ2"

$decode = Get-SourceBlock $coreText `
    "static bool metal_graph_encode_decode_layer(" `
    "/* Encode the final HC collapse" "decode dispatch"
foreach ($needle in @(
    'const bool q1_0_mixed_cold =',
    'q1_0_dual_arena_requested() > 0',
    '!q1_0_mixed_cold',
    'ds4_gpu_routed_moe_mixed_q1_0_one_tensor(')) {
    Require-Text $decode $needle "dual decode enters per-expert resolver"
}

Require-Text $headerText `
    'int ds4_gpu_routed_moe_mixed_q1_0_one_tensor(' `
    "public CUDA boundary"
Require-Text $headerText `
    'int ds4_gpu_set_primary_moe_geometry(' `
    "metadata-only primary IQ2 geometry boundary"

$primaryBindIndex = $coreText.IndexOf(
    'ds4_gpu_set_primary_moe_geometry(', [StringComparison]::Ordinal)
$q1BindIndex = $coreText.IndexOf(
    'ds4_gpu_dynamic_arena_bind_q1_0_snapshot(', [StringComparison]::Ordinal)
if ($primaryBindIndex -lt 0 -or $q1BindIndex -lt 0 -or
    $primaryBindIndex -ge $q1BindIndex) {
    throw "G110 primary IQ2 geometry must bind before the Q1 snapshot arena"
}

$primaryGeometry = Get-SourceBlock $cudaText `
    'extern "C" int ds4_gpu_set_primary_moe_geometry(' `
    'extern "C" int ds4_gpu_dynamic_arena_bind_q1_0(' `
    "primary IQ2 metadata catalog"
foreach ($needle in @(
    'model_map != g_model_host_base',
    'model_size != g_model_registered_size',
    'geometry.gate_expert_bytes, n_expert, model_size',
    'geometry.up_expert_bytes, n_expert, model_size',
    'geometry.down_expert_bytes, n_expert, model_size',
    'g_primary_moe_geometry.assign(',
    'storage=metadata-only')) {
    Require-Text $primaryGeometry $needle `
        "primary IQ2 catalog validates authoritative model ranges"
}

$seed = Get-SourceBlock $cudaText `
    'static int cuda_moe_prefill_vram_seed(' `
    'static cuda_moe_expert_cache *cuda_moe_expert_cache_prepare(' `
    "one-time exact IQ2 VRAM seed"
foreach ($needle in @(
    'const int primary_mmap_source =',
    'g_primary_moe_geometry_map != g_model_host_base',
    '? g_primary_moe_geometry[layer]',
    ': g_dynamic_arena.layers[layer]',
    '[prefill-vram-seed-source]',
    'semantics=one-time-exact-iq2')) {
    Require-Text $seed $needle "seed source and telemetry stay IQ2-exact"
}
if (($seed.Split('? g_primary_moe_geometry[layer]').Count - 1) -lt 2) {
    throw "G110 seed upload and cache keys must use the same IQ2 geometry"
}

$identity = Get-SourceBlock $coreText `
    "static void q1_0_sidecar_validate_router_identity(" `
    "static void mtp_weights_bind(" "Q1 router identity"
foreach ($needle in @(
    'blk.%u.ffn_gate_inp.weight',
    'iq1_s_identity_compare_tensor(',
    'Q1_0 router identity validated:',
    'q1_0_sidecar_validate_router_identity(')) {
    Require-Text $identity $needle "primary router IDs match Q1 expert identity"
}

$active = Get-SourceBlock $cudaText `
    "static int cuda_q1_0_dual_arena_layer_active(uint32_t layer)" `
    "struct cuda_dynamic_arena_observer" "Q1 arena provenance"
foreach ($needle in @(
    'cuda_q1_0_resident_arena_requested()',
    'CUDA_DYNAMIC_ARENA_BACKING_Q1_0',
    'g_q1_0_dynamic_arena.model_map == g_q1_0_sidecar_host_base',
    'g_q1_0_dynamic_arena.model_size == g_q1_0_sidecar_size',
    'g_q1_0_dynamic_arena.snapshot_generation != 0',
    'g_dynamic_arena.backing == CUDA_DYNAMIC_ARENA_BACKING_PRIMARY',
    'cuda_host_ranges_disjoint(')) {
    Require-Text $active $needle "resident Q1 provenance is exact"
}

$resolver = Get-SourceBlock $cudaText `
    "static cuda_q1_0_mixed_representation cuda_q1_0_mixed_resolve(" `
    'extern "C" int ds4_gpu_routed_moe_mixed_q1_0_one_tensor(' `
    "representation decision table"
foreach ($needle in @(
    'g_moe_tiering.mode != CUDA_MOE_TIER_ENFORCE',
    '!g_moe_tiering.compose_prefill_mass_tiering',
    '!g_moe_tiering.compose_router_open',
    'cuda_moe_tiering_has_exact_vram(layer, expert)',
    'tier.state == CUDA_MOE_TIER_VRAM_PROTECTED',
    'cuda_moe_tiering_snapshot_ram_ptrs(',
    'cuda_moe_tiering_ram_ptrs(',
    'tier.state != CUDA_MOE_TIER_SSD_COLD || tier.has_2bit_ram',
    'cuda_q1_0_resident_ram_ptrs(')) {
    Require-Text $resolver $needle "fail-closed IQ2-hot/Q1-cold ordering"
}
$snapshotBranch = Get-SourceBlock $resolver `
    "if (cuda_q1_0_snapshot_backing_requested())" `
    "if (g_moe_tiering.mode != CUDA_MOE_TIER_ENFORCE" `
    "exclusive Q1 snapshot representation ordering"
foreach ($needle in @(
    'cuda_moe_tiering_has_exact_vram(layer, expert)',
    'cuda_q1_0_resident_ram_ptrs(',
    'generic snapshot/tier RAM pointers would alias Q1_0 slots')) {
    Require-Text $snapshotBranch $needle "exclusive Q1 snapshot keeps only exact IQ2 VRAM"
}
foreach ($forbidden in @(
    'cuda_moe_tiering_snapshot_ram_ptrs(',
    'cuda_moe_tiering_ram_ptrs(')) {
    if ($snapshotBranch.Contains($forbidden)) {
        throw "exclusive Q1 snapshot must not interpret Q1 bytes as IQ2: $forbidden"
    }
}

$mixed = Get-SourceBlock $cudaText `
    'extern "C" int ds4_gpu_routed_moe_mixed_q1_0_one_tensor(' `
    'extern "C" int ds4_gpu_routed_moe_mixed_iq1_one_tensor(' `
    "mixed execution"
foreach ($needle in @(
    'main_model_map != g_model_host_base',
    'main_model_size != g_model_registered_size',
    'q1_model_map != g_q1_0_sidecar_host_base',
    'q1_geometry.gate_offset != q1_gate_offset',
    'cuda_moe_expert_cache_prepare(',
    'reason=iq2-vram-cache-not-ready',
    'g_moe_tiering.entries.size() !=',
    '(size_t)CUDA_MOE_LAYER_COUNT * 256u',
    'cuda_q1_0_mixed_resolve(',
    'reason=unresolved',
    '[q1-0-mixed-route]',
    'representation=%s',
    'if (cold_count == 0u)',
    'if (hot_count != 0u)',
    '41u, 41u',
    'cuda_moe_tiering_observe_route(',
    'g_moe_tiering.snapshot_backing_hits += cold_count',
    'reason=current-token-iq2-ssd',
    'g_q1_0_mixed_iq2_ssd_violations++')) {
    Require-Text $mixed $needle "router unchanged, split compute and future mass"
}
$prepareIndex = $mixed.IndexOf(
    'cuda_moe_expert_cache_prepare(', [StringComparison]::Ordinal)
$resolveIndex = $mixed.IndexOf(
    'cuda_q1_0_mixed_resolve(', [StringComparison]::Ordinal)
if ($prepareIndex -lt 0 -or $resolveIndex -lt 0 -or
    $prepareIndex -ge $resolveIndex) {
    throw "G110 Q1 resolver must prepare the exact IQ2 VRAM cache before classification"
}
Require-Text $cudaText 'promotion=off' `
    "first mixed resolver smoke cannot promote synchronously"
foreach ($needle in @(
    'cuda_pread_full(',
    'cuda_moe_tiering_load_to_ram(',
    'cuda_moe_tiering_stage_iq1_cold_to_2bit_ram(')) {
    Forbid-Text $mixed $needle "current-token Q1 cannot trigger IQ2 SSD work"
}

$composeMask = Get-SourceBlock $cudaText `
    "static int cuda_prefill_mass_compose_apply_router_mask(void)" `
    "static void cuda_prefill_mass_observer_reset(void)" `
    "router admissibility stays representation-neutral"
foreach ($needle in @('q1_full_layers', 'q1_resident_layer')) {
    Forbid-Text $composeMask $needle `
        "Q1 residency cannot silently rewrite a closed router mask"
}
Require-Text $composeMask 'semantics=request-scoped-open' `
    "explicit open-router mode remains the only admissibility mechanism"

Write-Host "test_g110_q1_mixed_resolver_static.ps1: PASS"
