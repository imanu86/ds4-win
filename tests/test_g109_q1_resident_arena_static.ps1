$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$core = Join-Path $root "ds4.c"
$cuda = Join-Path $root "ds4_cuda.cu"
$gpuHeader = Join-Path $root "ds4_gpu.h"

foreach ($path in @($core, $cuda, $gpuHeader)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "G109 Q1 resident arena required file missing: $path"
    }
}

$tokens = $null
$errors = $null
[Management.Automation.Language.Parser]::ParseFile(
    $MyInvocation.MyCommand.Path, [ref]$tokens, [ref]$errors) | Out-Null
if ($errors -and $errors.Count -gt 0) {
    throw "G109 Q1 resident arena test AST parse failed: $($errors[0].Message)"
}

function Get-SourceBlock {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Start,
        [Parameter(Mandatory = $true)][string]$End,
        [Parameter(Mandatory = $true)][string]$Name
    )
    $startIndex = $Text.IndexOf($Start, [StringComparison]::Ordinal)
    if ($startIndex -lt 0) { throw "G109 source block start missing: $Name" }
    $endIndex = $Text.IndexOf($End, $startIndex + $Start.Length,
        [StringComparison]::Ordinal)
    if ($endIndex -lt 0) { throw "G109 source block end missing: $Name" }
    return $Text.Substring($startIndex, $endIndex - $startIndex)
}

function Require-Text {
    param([string]$Text, [string]$Needle, [string]$Contract)
    if ($Text.IndexOf($Needle, [StringComparison]::Ordinal) -lt 0) {
        throw "G109 Q1 resident arena contract missing ($Contract): $Needle"
    }
}

function Forbid-Text {
    param([string]$Text, [string]$Needle, [string]$Contract)
    if ($Text.IndexOf($Needle, [StringComparison]::Ordinal) -ge 0) {
        throw "G109 Q1 resident arena forbidden text ($Contract): $Needle"
    }
}

$coreText = Get-Content -LiteralPath $core -Raw
$cudaText = Get-Content -LiteralPath $cuda -Raw
$headerText = Get-Content -LiteralPath $gpuHeader -Raw

$envGate = Get-SourceBlock $coreText `
    "static int q1_0_resident_arena_requested(void)" `
    "static bool iq1_s_mixed_cold_one_requested(void)" "resident env gate"
foreach ($needle in @(
    'getenv("DS4_Q1_0_RESIDENT_ARENA")',
    'strcmp(value, "0") == 0',
    'strcmp(value, "1") == 0',
    'expected 0 or 1',
    'return -1;')) {
    Require-Text $envGate $needle "strict opt-in"
}
foreach ($needle in @(
    'DS4_Q1_0_SELECTED_LOAD=1',
    'Q1_0 resident arena requires DS4_CUDA_DYNAMIC_ARENA_GB>0',
    'Q1_0 resident mode failed closed')) {
    Require-Text $coreText $needle "startup fail closed"
}

$geometry = Get-SourceBlock $coreText `
    "static bool dynamic_arena_build_q1_0_layers(" `
    "static bool dynamic_arena_source(" "Q1 geometry"
foreach ($needle in @(
    'memset(layers, 0, sizeof(layers[0]) * DS4_N_LAYER);',
    'for (uint32_t il = g_q1_0_sidecar.first_layer;',
    'il <= g_q1_0_sidecar.last_layer; il++)',
    'g_q1_0_sidecar.gate[il]',
    'g_q1_0_sidecar.up[il]',
    'g_q1_0_sidecar.down[il]')) {
    Require-Text $geometry $needle "active-range-only geometry"
}
foreach ($needle in @(
    '? tensor->type == DS4_TENSOR_Q1_0',
    ': tensor_is_routed_expert_type(tensor->type)',
    'g_q1_0_sidecar.gate[il], il, "Q1_0 gate",',
    'true,')) {
    Require-Text $coreText $needle "Q1-only geometry type gate"
}
Forbid-Text $geometry 'for (uint32_t il = 0; il < DS4_N_LAYER; il++)' `
    "active-range-only geometry"

$bind = Get-SourceBlock $cudaText `
    "static int cuda_dynamic_arena_bind(" `
    'extern "C" int ds4_gpu_dynamic_arena_bind(' "typed arena bind"
foreach ($needle in @(
    'backing == CUDA_DYNAMIC_ARENA_BACKING_Q1_0',
    '? active_layer_first : 0u;',
    '? active_layer_last : n_layer - 1u;',
    'for (uint32_t il = geometry_first; il <= geometry_last; il++)')) {
    Require-Text $bind $needle "active-range-only bind"
}
foreach ($needle in @(
    'active_layer_first',
    'active_layer_last')) {
    Require-Text $headerText $needle "Q1 bind API"
}

$arenaPublish = Get-SourceBlock $cudaText `
    'extern "C" int ds4_gpu_dynamic_arena_publish(' `
    'extern "C" void ds4_gpu_dynamic_arena_abort(' `
    "arena publication"
foreach ($needle in @(
    'g_dynamic_arena.backing == CUDA_DYNAMIC_ARENA_BACKING_Q1_0',
    'g_dynamic_arena.active_layer_last -',
    'g_dynamic_arena.active_layer_first',
    'target_out_of_range',
    'target_entries != (uint32_t)expected',
    'reason=full-bootstrap-snapshot-required',
    'g_q1_0_resident_bootstrap_entries = q1_bootstrap_entries;')) {
    Require-Text $arenaPublish $needle "full bootstrap publication"
}

$wrapControl = Get-SourceBlock $cudaText `
    "static int cuda_prefill_mass_wrap_requested(void)" `
    "static int cuda_prefill_mass_observe_requested(void)" `
    "prefill wrap control"
Require-Text $wrapControl 'getenv("DS4_CUDA_PREFILL_MASS_WRAP")' `
    "legacy wrap env preserved"
Forbid-Text $wrapControl 'CUDA_DYNAMIC_ARENA_BACKING_Q1_0' `
    "Q1 does not force prefill wrap"

$prefillReset = Get-SourceBlock $cudaText `
    "static void cuda_prefill_mass_observer_reset(void)" `
    "static int cuda_prefill_mass_publish_candidate(void)" `
    "prefill observer reset"
foreach ($needle in @(
    'cuda_prefill_mass_observer_release(1);',
    'g_dynamic_arena.backing == CUDA_DYNAMIC_ARENA_BACKING_Q1_0',
    'prefill_mass=disabled snapshot=full-bootstrap router=unchanged dynamic_masks=not-implemented',
    'return;')) {
    Require-Text $prefillReset $needle "Q1 prefill observer disabled"
}
if ($prefillReset.IndexOf('return;', [StringComparison]::Ordinal) -gt
    $prefillReset.IndexOf('const int wrap =', [StringComparison]::Ordinal)) {
    throw "G109 Q1 prefill observer is not disabled before wrap learning"
}

$carry = Get-SourceBlock $cudaText `
    "static int cuda_dynamic_arena_carry_mode(void)" `
    "static uint32_t cuda_dynamic_arena_active_count(void)" `
    "Q1 snapshot carry"
Require-Text $carry 'CUDA_DYNAMIC_ARENA_BACKING_Q1_0' `
    "Q1 snapshot carry"
Require-Text $carry 'return 1;' "Q1 snapshot carry"

$observerReset = Get-SourceBlock $cudaText `
    'extern "C" void ds4_gpu_dynamic_arena_observer_reset(void) {' `
    "static void cuda_dynamic_arena_observe_selected(" `
    "dynamic observer reset"
foreach ($needle in @(
    'g_dynamic_arena.backing == CUDA_DYNAMIC_ARENA_BACKING_Q1_0',
    'cuda_prefill_mass_observer_release(1);',
    'cuda_dynamic_arena_observer_release();',
    'cuda_reap_mass_observer_release(1);',
    'return;')) {
    Require-Text $observerReset $needle "Q1 dynamic observers disabled"
}
if ($observerReset.IndexOf('cuda_prefill_mass_observer_finalize();',
        [StringComparison]::Ordinal) -lt
    $observerReset.IndexOf('return;', [StringComparison]::Ordinal)) {
    throw "G109 Q1 observer reset reaches prefill finalize"
}

Forbid-Text $cudaText 'g_q1_0_resident_prefill_finalized' `
    "no prefill-finalized gate"
Forbid-Text $cudaText 'g_q1_0_resident_candidates' `
    "no learned Q1 candidates"
Require-Text $cudaText 'g_q1_0_resident_bootstrap_entries' `
    "summary uses bootstrap entries"
Require-Text $cudaText 'candidate_entries=%u iq2_vram_cache=q1-routes-bypass' `
    "summary reports bootstrap entries"

$loader = Get-SourceBlock $cudaText `
    "static int cuda_moe_selected_load_q1_0(" `
    "static cuda_moe_expert_cache *cuda_moe_gpu_resident_routes_begin(" `
    "Q1 selected loader"
$branchPattern = '(?s)if \(cuda_q1_0_resident_arena_requested\(\)\) \{(?<resident>.*?)\r?\n    \} else \{\r?\n        std::vector<uint8_t> host_gate;(?<direct>.*)'
$branchMatch = [regex]::Match($loader, $branchPattern)
if (-not $branchMatch.Success) {
    throw "G109 Q1 selected loader resident/direct split missing"
}
$resident = $branchMatch.Groups["resident"].Value
$direct = $branchMatch.Groups["direct"].Value
foreach ($needle in @(
    'cuda_dynamic_arena_copy_expert_async(',
    'CUDA_DYNAMIC_ARENA_ENQUEUED',
    'cudaMemcpyAsync(',
    'g_q1_0_resident_hits += compact_count;',
    'g_q1_0_resident_h2d_bytes += route_h2d_bytes;')) {
    Require-Text $resident $needle "resident pinned H2D"
}
Forbid-Text $resident 'cuda_pread_full(' "resident path has no pread"
Forbid-Text $resident 'g_q1_0_direct_pread_fallbacks' `
    "resident path has no fallback"
Forbid-Text $resident 'resident_prefill_finalized' `
    "resident path is independent of prefill learning"
Forbid-Text $resident 'resident_candidates' `
    "resident path is independent of learned candidates"
foreach ($needle in @(
    'g_q1_0_direct_pread_fallbacks++;',
    'cuda_pread_full(',
    '&g_q1_0_sidecar_file',
    'g_q1_0_direct_pread_bytes += cgate * 2u + cdown;')) {
    Require-Text $direct $needle "legacy direct path preserved"
}

foreach ($needle in @(
    'iq2_vram_cache=q1-routes-bypass',
    'iq2_host_arena=disabled',
    'mixed_host_backing=not-implemented',
    '!route_iq1_s && !route_q1_0')) {
    Require-Text $cudaText $needle "IQ2/Q1 isolation"
}
foreach ($needle in @(
    'reason=mixed-host-resolver-not-implemented router=unchanged',
    'g_dynamic_arena.backing == CUDA_DYNAMIC_ARENA_BACKING_Q1_0 &&',
    'reason=mixed-host-resolver-not-implemented expert_tiering=%d compose=%d router_open=%d')) {
    Require-Text $cudaText $needle "mixed resolver fail closed"
}

$readyPrefix = 'ds4: CUDA dynamic arena ready %.2f GiB, %u slots, %.2f MiB/slot, available_ram=%.2f GiB bytes=%llu slot_bytes=%llu backing=%s'
Require-Text $cudaText $readyPrefix "backward-compatible ready log"
Forbid-Text $cudaText 'ds4: CUDA dynamic arena ready backing=' `
    "backward-compatible ready log"
Require-Text $cudaText `
    'ds4: [arena] final hits=%llu misses=%llu fatal=%llu uploaded=%.2f GiB\n"' `
    "byte-compatible primary final log"
Require-Text $cudaText `
    'ds4: [arena] final hits=%llu misses=%llu fatal=%llu uploaded=%.2f GiB backing=q1_0' `
    "Q1 final log backing suffix"

$bootstrap = Get-SourceBlock $coreText `
    "static bool q1_0_resident_arena_bootstrap(" `
    "static uint32_t dynamic_arena_test_keep(void)" "Q1 bootstrap"
foreach ($needle in @(
    'for (uint32_t layer = first_layer; layer <= last_layer; layer++)',
    'memset(target + layer * DS4_N_EXPERT, 1, DS4_N_EXPERT);',
    '(last_layer - first_layer + 1u) * DS4_N_EXPERT;',
    '(load_count != 0 && !loads)',
    '(load_count != 0 && load_count != bootstrap_entries)',
    'ds4_gpu_dynamic_arena_publish(txn, &snapshot_generation)')) {
    Require-Text $bootstrap $needle "all active experts bootstrap"
}
if ([regex]::Matches($bootstrap,
        [regex]::Escape('ds4_gpu_dynamic_arena_abort(txn);')).Count -lt 3) {
    throw "G109 Q1 bootstrap lacks transaction cleanup on every error path"
}
$sessionArena = Get-SourceBlock $coreText `
    'int ds4_session_create(ds4_session **out, ds4_engine *e, int ctx_size)' `
    'void ds4_session_free(ds4_session *s)' "session arena setup"
foreach ($needle in @(
    'metal_graph_free(&s->graph);',
    'free(s);',
    'return 1;')) {
    Require-Text $sessionArena $needle "session cleanup on Q1 failure"
}
if ([regex]::Matches($sessionArena,
        [regex]::Escape('ds4_gpu_dynamic_arena_release();')).Count -lt 2) {
    throw "G109 Q1 session setup lacks arena cleanup on bind/preload errors"
}
$release = Get-SourceBlock $cudaText `
    'extern "C" void ds4_gpu_dynamic_arena_release(void)' `
    "static int cuda_dynamic_arena_bind(" "arena release"
foreach ($needle in @(
    'cuda_dynamic_arena_storage_release();',
    'g_dynamic_arena.active_layer_first = 0;',
    'g_dynamic_arena.active_layer_last = 0;',
    'g_dynamic_arena.backing = CUDA_DYNAMIC_ARENA_BACKING_NONE;')) {
    Require-Text $release $needle "arena cleanup"
}

Write-Host "test_g109_q1_resident_arena_static.ps1: PASS"
