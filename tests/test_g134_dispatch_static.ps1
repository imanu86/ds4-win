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
             $gate.Contains('static int initialized = 0;') -and
             $gate.Contains('strcmp(value, "0") == 0') -and
             $gate.Contains('strcmp(value, "1") != 0') -and
             $gate.Contains('g_cuda_g134_dispatch_enabled = 1') -and
             $gate.Contains('cuda_g134_dispatch_select_enabled();')) `
    'master gate must be strict, startup-cached, and OFF by default with cached mixed dispatch'
Assert-True ($gate.Contains('os_mutex_lock(&g_cuda_g134_dispatch_staging_mutex)') -and
             $gate.Contains('cudaMemcpyAsync(') -and
             $gate.Contains('G134 dispatch selected D2H') -and
             $gate.Contains('G134 dispatch weights D2H') -and
             $gate.Contains('G134 dispatch selection ready') -and
             ([regex]::Matches($gate, 'G134 dispatch selection ready')).Count -eq 1 -and
             $gate.Contains('cudaStreamSynchronize(0)') -and
             $gate.Contains('memcpy(selected_host, staging->selected') -and
             $gate.Contains('os_mutex_unlock(&g_cuda_g134_dispatch_staging_mutex)')) `
    'pinned staging must hold ownership across acquire, sync, host copy, and release'
Assert-True ($gate.Contains('Decode is serialized today') -and
             $gate.Contains('global pinned staging record')) `
    'staging ownership policy must be documented at the guard'

$legacyD2H = Slice-Between 'static int cuda_q1_0_mixed_selection_d2h<false>(' `
    'template <>'
Assert-True ($legacyD2H.Contains('cudaMemcpy(selected_host, selected->ptr') -and
             $legacyD2H.Contains('cudaMemcpy(weights_host, weights->ptr') -and
             $legacyD2H.Contains('"Q1_0 mixed selected D2H"') -and
             $legacyD2H.Contains('"Q1_0 mixed weights D2H"')) `
    'OFF specialization must keep the original direct synchronous selected/weights D2H'
Assert-True (-not $legacyD2H.Contains('G134 dispatch') -and
             -not $legacyD2H.Contains('cudaMemcpyAsync(') -and
             -not $legacyD2H.Contains('cudaStreamSynchronize(') -and
             -not $legacyD2H.Contains('os_mutex_lock(')) `
    'OFF specialization must not route selected/weights D2H through G134 staging'

$gpuInit = Slice-Between 'extern "C" int ds4_gpu_init(void)' `
    'extern "C" void ds4_gpu_cleanup(void)'
Assert-True ($gpuInit.Contains('cuda_g134_initialize_dispatch()') -and
             $gpuInit.Contains('cuda_g134_dispatch_staging_init()')) `
    'startup must initialize the cached dispatch flag and enabled-only staging owner'
$gpuCleanup = Slice-Between 'extern "C" void ds4_gpu_cleanup(void)' `
    'extern "C" int ds4_gpu_synchronize(void)'
Assert-True ($gpuCleanup.Contains('cudaFreeHost(g_cuda_g134_dispatch_staging)') -and
             $gpuCleanup.Contains('g_cuda_g134_dispatch_staging = NULL') -and
             $gpuCleanup.Contains('os_mutex_destroy(&g_cuda_g134_dispatch_staging_mutex)')) `
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
Assert-True (-not $mixed.Contains('getenv(')) `
    'mixed decode path must not read environment variables'
Assert-True ($source.Contains('g_cuda_g134_mixed_q1_0_launch =') -and
             $source.Contains('ds4_gpu_routed_moe_mixed_q1_0_one_tensor_impl<false>') -and
             $source.Contains('ds4_gpu_routed_moe_mixed_q1_0_one_tensor_impl<true>') -and
             $mixed.Contains('g_cuda_g134_mixed_q1_0_launch(') -and
             $mixed.Contains('cuda_q1_0_mixed_selection_d2h<DispatchPlan>(') -and
             $mixed.Contains('if (DispatchPlan) {') -and
             $mixed.Contains('cuda_g134_dispatch_plan_build(')) `
    'mixed decode must be startup-dispatched and compile-time split between plan and legacy structures'
Assert-True (-not $mixed.Contains('g_cuda_g134_dispatch_enabled')) `
    'mixed decode implementation must not branch on the global dispatch flag'
Assert-True ($mixed.Contains('CUDA_G130_ATTRIB_DISPATCH_PLAN') -and
             $mixed.Contains('CUDA_G130_ATTRIB_DISPATCH_LEGACY')) `
    'attribution must distinguish plan and legacy host dispatch time'

$q1Load = Slice-Between 'static int cuda_moe_selected_load_q1_0(' `
    'static cuda_moe_expert_cache *cuda_moe_gpu_resident_routes_begin('
Assert-True ($q1Load.Contains('lru_slots_plan[CUDA_MOE_ROUTE_COUNT]') -and
             $q1Load.Contains('const int fixed_plan_lru =') -and
             $q1Load.Contains('DispatchPlan &&') -and
             $q1Load.Contains('selected_host_arg &&') -and
             $q1Load.Contains('lru_slots_legacy.resize(compact_count)')) `
    'mixed plan LRU bookkeeping must use bounded layer arrays while legacy remains dynamic'
Assert-True (-not $q1Load.Contains('g_cuda_g134_dispatch_enabled')) `
    'selected-load LRU bookkeeping must not branch on the global dispatch flag'

$routed = Slice-Between 'static int routed_moe_launch(' `
    'extern "C" int ds4_gpu_routed_moe_one_tensor('
Assert-True ($routed.Contains('routed_moe_launch_impl<false>(') -and
             $routed.Contains('template <bool DispatchPlan>') -and
             $routed.Contains('cuda_moe_selected_load_q1_0<DispatchPlan>(')) `
    'routed MoE must expose the original signature and split implementation at compile time'
Assert-True (-not $routed.Contains('g134_bounded_lru')) `
    'routed MoE OFF call surface must not carry the G134 bounded-LRU parameter'

foreach ($field in @('"dispatch_plan"', '"dispatch_legacy"')) {
    Assert-True ($source.Contains($field)) "missing attribution field $field"
}

Write-Output 'G134 dispatch static contract: PASS'
