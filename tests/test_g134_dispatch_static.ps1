$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$source = [System.IO.File]::ReadAllText((Join-Path $root 'ds4_cuda.cu'))

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "G134 dispatch static contract failed: $Message" }
}

function Slice-Between([string]$Start, [string]$End) {
    $startIndex = $source.IndexOf($Start, [StringComparison]::Ordinal)
    Assert-True ($startIndex -ge 0) "missing start marker: $Start"
    $endIndex = $source.IndexOf($End, $startIndex, [StringComparison]::Ordinal)
    Assert-True ($endIndex -gt $startIndex) "missing end marker: $End"
    return $source.Substring($startIndex, $endIndex - $startIndex)
}

$gate = Slice-Between 'static int g_cuda_g134_dispatch_enabled = 0;' `
    'struct cuda_g133_telemetry_counters {'
Assert-True ($gate.Contains('getenv("DS4_G134_DISPATCH")') -and
             $gate.Contains('strcmp(value, "0") == 0') -and
             $gate.Contains('strcmp(value, "1") != 0') -and
             $gate.Contains('g_cuda_g134_dispatch_enabled = 1')) `
    'master gate must be strict, startup-cached, and OFF by default'

$gpuInit = Slice-Between 'extern "C" int ds4_gpu_init(void)' `
    'extern "C" void ds4_gpu_cleanup(void)'
Assert-True ($gpuInit.Contains('cuda_g134_initialize_dispatch()') -and
             $gpuInit.Contains('cudaHostAlloc(') -and
             $gpuInit.Contains('cudaHostAllocPortable')) `
    'startup must allocate the one pinned layer-plan staging record only when enabled'
$gpuCleanup = Slice-Between 'extern "C" void ds4_gpu_cleanup(void)' `
    'extern "C" int ds4_gpu_synchronize(void)'
Assert-True ($gpuCleanup.Contains('cudaFreeHost(g_cuda_g134_dispatch_staging)') -and
             $gpuCleanup.Contains('g_cuda_g134_dispatch_staging = NULL')) `
    'pinned plan staging must have a cleanup terminal'

$plan = Slice-Between 'struct cuda_g134_dispatch_plan {' `
    'extern "C" int ds4_gpu_routed_moe_mixed_q1_0_one_tensor('
foreach ($field in @('hot_selected', 'hot_weights', 'cold_selected',
                     'cold_weights', 'cpu_selected', 'cpu_weights',
                     'route_representations', 'route_tiers',
                     'route_cpu_slot_identities', 'hot_count', 'cold_count',
                     'cpu_count')) {
    Assert-True ($plan.Contains($field)) "layer plan is missing $field"
}
Assert-True ($plan.Contains('cuda_g134_dispatch_plan_build(') -and
             $plan.Contains('cuda_g134_dispatch_resolve(') -and
             $plan.Contains('if (!cold_one_requested) cuda_q1_0_mixed_capture_router_mode();') -and
             $plan.Contains('const int tier_table_valid =') -and
             $plan.Contains('g_moe_tiering.entries.data() +') -and
             $plan.Contains('cuda_g132_cpu_lane_reserve_resident_iq2_ptrs(')) `
    'plan build must phase route mode, cache base, pointer resolution, and CPU reservation'
Assert-True (-not $plan.Contains('<<<') -and
             -not $plan.Contains('cudaMemcpy(') -and
             -not $plan.Contains('cudaMemcpyAsync(') -and
             -not $plan.Contains('cudaStreamSynchronize(')) `
    'host plan construction must not interleave device work or host round-trips'

$mixed = Slice-Between `
    'extern "C" int ds4_gpu_routed_moe_mixed_q1_0_one_tensor(' `
    'extern "C" int ds4_gpu_routed_moe_mixed_iq1_one_tensor('
Assert-True ($mixed.Contains('if (g_cuda_g134_dispatch_enabled) {') -and
             $mixed.Contains('} else {') -and
             $mixed.Contains('cuda_g134_dispatch_plan_build(')) `
    'mixed decode must select exactly one gated plan/legacy structure'
Assert-True ($mixed.Contains('cudaMemcpyAsync(') -and
             $mixed.Contains('G134 dispatch selected D2H') -and
             $mixed.Contains('G134 dispatch weights D2H') -and
             $mixed.Contains('G134 dispatch selection ready') -and
             ([regex]::Matches($mixed, 'G134 dispatch selection ready')).Count -eq 1) `
    'enabled selection metadata must use two enqueues and one layer-ready fence'
Assert-True ($mixed.Contains('Q1_0 mixed selected D2H') -and
             $mixed.Contains('Q1_0 mixed weights D2H')) `
    'flag-off legacy synchronous copies must remain present'
Assert-True ($mixed.Contains('CUDA_G130_ATTRIB_DISPATCH_PLAN') -and
             $mixed.Contains('CUDA_G130_ATTRIB_DISPATCH_LEGACY')) `
    'attribution must distinguish plan and legacy host dispatch time'

$q1Load = Slice-Between 'static int cuda_moe_selected_load_q1_0(' `
    'static cuda_moe_expert_cache *cuda_moe_gpu_resident_routes_begin('
Assert-True ($q1Load.Contains('lru_slots_plan[CUDA_MOE_ROUTE_COUNT]') -and
             $q1Load.Contains('const int fixed_plan_lru =') -and
             $q1Load.Contains('g_cuda_g134_dispatch_enabled &&') -and
             $q1Load.Contains('selected_host_arg &&') -and
             $q1Load.Contains('lru_slots_legacy.resize(compact_count)')) `
    'mixed plan LRU bookkeeping must use bounded layer arrays while legacy remains dynamic'

foreach ($field in @('"dispatch_plan"', '"dispatch_legacy"')) {
    Assert-True ($source.Contains($field)) "missing attribution field $field"
}

Write-Output 'G134 dispatch static contract: PASS'
