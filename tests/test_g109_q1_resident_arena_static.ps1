$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$core = Join-Path $root "ds4.c"
$cuda = Join-Path $root "ds4_cuda.cu"
$gpuHeader = Join-Path $root "ds4_gpu.h"

foreach ($path in @($core, $cuda, $gpuHeader)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "G109/G110 Q1 arena required file missing: $path"
    }
}

$tokens = $null
$errors = $null
[Management.Automation.Language.Parser]::ParseFile(
    $MyInvocation.MyCommand.Path, [ref]$tokens, [ref]$errors) | Out-Null
if ($errors -and $errors.Count -gt 0) {
    throw "G109/G110 Q1 arena test AST parse failed: $($errors[0].Message)"
}

function Get-SourceBlock {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Start,
        [Parameter(Mandatory = $true)][string]$End,
        [Parameter(Mandatory = $true)][string]$Name
    )
    $startIndex = $Text.IndexOf($Start, [StringComparison]::Ordinal)
    if ($startIndex -lt 0) { throw "G109/G110 block start missing: $Name" }
    $endIndex = $Text.IndexOf($End, $startIndex + $Start.Length,
        [StringComparison]::Ordinal)
    if ($endIndex -lt 0) { throw "G109/G110 block end missing: $Name" }
    return $Text.Substring($startIndex, $endIndex - $startIndex)
}

function Require-Text {
    param([string]$Text, [string]$Needle, [string]$Contract)
    if ($Text.IndexOf($Needle, [StringComparison]::Ordinal) -lt 0) {
        throw "G109/G110 contract missing ($Contract): $Needle"
    }
}

function Forbid-Text {
    param([string]$Text, [string]$Needle, [string]$Contract)
    if ($Text.IndexOf($Needle, [StringComparison]::Ordinal) -ge 0) {
        throw "G109/G110 forbidden text ($Contract): $Needle"
    }
}

$coreText = Get-Content -LiteralPath $core -Raw
$cudaText = Get-Content -LiteralPath $cuda -Raw
$headerText = Get-Content -LiteralPath $gpuHeader -Raw

$envGate = Get-SourceBlock $coreText `
    "static int q1_0_resident_arena_requested(void)" `
    "static bool iq1_s_mixed_cold_one_requested(void)" "Q1 env gates"
foreach ($needle in @(
    'getenv("DS4_Q1_0_RESIDENT_ARENA")',
    'getenv("DS4_Q1_0_DUAL_ARENA")',
    'getenv("DS4_Q1_0_SNAPSHOT_BACKING")',
    'strcmp(value, "0") == 0',
    'strcmp(value, "1") == 0',
    'expected 0 or 1',
    'return -1;')) {
    Require-Text $envGate $needle "strict opt-in"
}

foreach ($needle in @(
    '(q1_0_dual_arena > 0 && q1_0_resident_arena <= 0)',
    'DS4_Q1_0_SELECTED_LOAD=1',
    'Q1_0 resident arena requires DS4_CUDA_DYNAMIC_ARENA_GB>0')) {
    Require-Text $coreText $needle "startup fail closed"
}

$geometry = Get-SourceBlock $coreText `
    "static bool dynamic_arena_build_q1_0_layers(" `
    "static bool dynamic_arena_source(" "Q1 geometry"
foreach ($needle in @(
    'for (uint32_t il = g_q1_0_sidecar.first_layer;',
    'il <= g_q1_0_sidecar.last_layer; il++)',
    'g_q1_0_sidecar.gate[il]',
    'g_q1_0_sidecar.up[il]',
    'g_q1_0_sidecar.down[il]',
    'true,')) {
    Require-Text $geometry $needle "active-range Q1-only geometry"
}

foreach ($needle in @(
    'static cuda_dynamic_arena g_dynamic_arena;',
    'static cuda_dynamic_arena g_q1_0_dynamic_arena;',
    'static int cuda_q1_0_dual_arena_requested(void)',
    'static int cuda_q1_0_exclusive_arena_active(void)',
    'static int cuda_q1_0_dual_arena_layer_active(uint32_t layer)')) {
    Require-Text $cudaText $needle "two typed arena instances"
}
$exclusiveGuardCount = [regex]::Matches(
    $cudaText, [regex]::Escape('cuda_q1_0_exclusive_arena_active()')).Count
if ($exclusiveGuardCount -lt 7) {
    throw "G109/G110 legacy Q1 guards were not migrated to the separate arena"
}
foreach ($needle in @(
    'static int cuda_q1_0_snapshot_backing_requested(void)',
    'extern "C" int ds4_gpu_dynamic_arena_bind_q1_0_snapshot(',
    'policy=sparse-prefill-ranked iq2_host_snapshot=disabled')) {
    Require-Text $cudaText $needle "explicit sparse snapshot backing"
}

$copy = Get-SourceBlock $cudaText `
    "static cuda_dynamic_arena_copy_status cuda_dynamic_arena_copy_expert_async(" `
    "static void cuda_dynamic_arena_storage_release(void)" "typed arena copy"
foreach ($needle in @(
    'cuda_dynamic_arena &arena',
    'model_map != arena.model_map',
    'arena.active[entry]',
    'arena.bytes_uploaded +=')) {
    Require-Text $copy $needle "representation-neutral copy"
}
Forbid-Text $copy 'g_dynamic_arena.active[entry]' "copy does not hardcode primary"

$q1Bind = Get-SourceBlock $cudaText `
    'extern "C" int ds4_gpu_dynamic_arena_bind_q1_0(' `
    'extern "C" int ds4_gpu_dynamic_arena_prepare_q1_0(' "Q1 bind"
foreach ($needle in @(
    'cuda_dynamic_arena &arena = g_q1_0_dynamic_arena;',
    'arena.backing = CUDA_DYNAMIC_ARENA_BACKING_Q1_0;',
    'cuda_q1_0_dynamic_arena_release(0);',
    'mixed_host_backing=%s')) {
    Require-Text $q1Bind $needle "Q1 binds separate arena"
}
Forbid-Text $q1Bind 'ds4_gpu_dynamic_arena_release();' `
    "Q1 bind cannot release primary arena"

$q1Prepare = Get-SourceBlock $cudaText `
    'extern "C" int ds4_gpu_dynamic_arena_prepare_q1_0(' `
    'extern "C" int ds4_gpu_dynamic_arena_prepare(' "Q1 bootstrap"
foreach ($needle in @(
    'required_entries',
    'requested_bytes < required_bytes',
    'cudaHostAllocDefault',
    'active.assign(binding_count, empty);',
    'memcpy(destination, gate',
    'memcpy(destination + geometry.gate_expert_bytes',
    'DS4_GPU_ARENA_READY',
    'arena.snapshot_generation = 1;',
    'g_q1_0_resident_bootstrap_entries = (uint32_t)required_entries;',
    'route_pread=disabled')) {
    Require-Text $q1Prepare $needle "full atomic Q1 bootstrap"
}
if ($q1Prepare.IndexOf('arena.host_base = host;', [StringComparison]::Ordinal) -lt
    $q1Prepare.LastIndexOf('memcpy(', [StringComparison]::Ordinal)) {
    throw "G109/G110 Q1 arena is published before all copies complete"
}
$slotsSwap = $q1Prepare.IndexOf('arena.slots.swap(slots);',
    [StringComparison]::Ordinal)
$activeSwap = $q1Prepare.IndexOf('arena.active.swap(active);',
    [StringComparison]::Ordinal)
$hostPublish = $q1Prepare.IndexOf('arena.host_base = host;',
    [StringComparison]::Ordinal)
$snapshotPublish = $q1Prepare.IndexOf('arena.snapshot_generation = 1;',
    [StringComparison]::Ordinal)
$unblock = $q1Prepare.IndexOf('arena.submissions_blocked = 0;',
    [StringComparison]::Ordinal)
if ($slotsSwap -lt 0 -or $activeSwap -lt 0 -or $hostPublish -lt 0 -or
    $snapshotPublish -lt 0 -or $unblock -lt 0 -or
    $slotsSwap -gt $hostPublish -or $activeSwap -gt $hostPublish -or
    $hostPublish -gt $snapshotPublish -or $snapshotPublish -gt $unblock) {
    throw "G109/G110 Q1 snapshot publication is not atomic/fail-closed"
}

$loader = Get-SourceBlock $cudaText `
    "static int cuda_moe_selected_load_q1_0(" `
    "static cuda_moe_expert_cache *cuda_moe_gpu_resident_routes_begin(" `
    "Q1 selected loader"
$branchPattern = '(?s)if \(cuda_q1_0_resident_transport_requested\(\)\) \{(?<resident>.*?)\r?\n    \} else \{\r?\n        std::vector<uint8_t> host_gate;(?<direct>.*)'
$branchMatch = [regex]::Match($loader, $branchPattern)
if (-not $branchMatch.Success) {
    throw "G109/G110 Q1 selected loader resident/direct split missing"
}
$resident = $branchMatch.Groups["resident"].Value
$direct = $branchMatch.Groups["direct"].Value
foreach ($needle in @(
    'cuda_q1_0_route_arena(layer_index)',
    'q1_arena->backing',
    'cuda_dynamic_arena_copy_expert_async(',
    '*q1_arena,',
    'CUDA_DYNAMIC_ARENA_ENQUEUED',
    'g_q1_0_resident_hits += compact_count;',
    'g_q1_0_resident_h2d_bytes += route_h2d_bytes;')) {
    Require-Text $resident $needle "resident Q1 resolver"
}
Forbid-Text $resident 'cuda_pread_full(' "resident path has no pread"
Forbid-Text $resident 'g_q1_0_direct_pread_fallbacks' `
    "resident path has no direct fallback"
foreach ($needle in @(
    'g_q1_0_direct_pread_fallbacks++;',
    'cuda_pread_full(',
    '&g_q1_0_sidecar_file')) {
    Require-Text $direct $needle "legacy direct path preserved"
}

$sessionArena = Get-SourceBlock $coreText `
    'int ds4_session_create(ds4_session **out, ds4_engine *e, int ctx_size)' `
    'void ds4_session_free(ds4_session *s)' "session dual setup"
foreach ($needle in @(
    'q1_0_resident_arena <= 0 || q1_0_dual_arena > 0',
    'ds4_gpu_dynamic_arena_bind(',
    'ds4_gpu_dynamic_arena_prepare(',
    'ds4_gpu_dynamic_arena_bind_q1_0(',
    'ds4_gpu_dynamic_arena_prepare_q1_0(',
    'q1_slots != required_slots',
    'q1_generation == 0',
    'Q1_0 dual mode failed closed')) {
    Require-Text $sessionArena $needle "primary plus Q1 setup"
}

foreach ($needle in @(
    'int ds4_gpu_dynamic_arena_prepare_q1_0(',
    'uint64_t *snapshot_generation')) {
    Require-Text $headerText $needle "Q1 bootstrap API"
}

$release = Get-SourceBlock $cudaText `
    'static void cuda_q1_0_dynamic_arena_release(int report)' `
    "static int cuda_dynamic_arena_bind(" "dual arena release"
foreach ($needle in @(
    'cudaFreeHost(arena.host_base)',
    'arena = cuda_dynamic_arena{};',
    'static void cuda_primary_dynamic_arena_release(int report)',
    'cuda_q1_0_dynamic_arena_release(1);',
    'cuda_primary_dynamic_arena_release(1);',
    'cuda_dynamic_arena_storage_release();')) {
    Require-Text $release $needle "both arenas released"
}
$primaryBind = Get-SourceBlock $cudaText `
    'static int cuda_dynamic_arena_bind(' `
    'extern "C" int ds4_gpu_dynamic_arena_bind(' "primary bind lifecycle"
Require-Text $primaryBind 'cuda_primary_dynamic_arena_release(1);' `
    "primary rebind releases primary only"
Forbid-Text $primaryBind 'ds4_gpu_dynamic_arena_release();' `
    "primary rebind cannot release Q1 arena"

$q1Summary = Get-SourceBlock $cudaText `
    'if (g_q1_0_sidecar_file_valid || g_q1_0_route_calls != 0)' `
    'if (g_q1_0_sidecar_file_valid)' "dual telemetry summary"
foreach ($needle in @(
    'cuda_q1_0_dual_arena_requested()',
    '? "enabled" : "disabled"',
    '? "dual-arena" : "disabled"')) {
    Require-Text $q1Summary $needle "dual telemetry is composition-aware"
}

Write-Host "test_g109_q1_resident_arena_static.ps1: PASS"
