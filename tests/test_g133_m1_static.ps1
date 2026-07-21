$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $root 'ds4_cuda.cu'
$source = [System.IO.File]::ReadAllText($sourcePath)

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "G133 M1 static contract failed: $Message" }
}

function Slice-Between([string]$Start, [string]$End) {
    $startIndex = $source.IndexOf($Start, [StringComparison]::Ordinal)
    Assert-True ($startIndex -ge 0) "missing start marker: $Start"
    $endIndex = $source.IndexOf($End, $startIndex, [StringComparison]::Ordinal)
    Assert-True ($endIndex -gt $startIndex) "missing end marker: $End"
    return $source.Substring($startIndex, $endIndex - $startIndex)
}

# R1: all new residency history is per expert, never per cache/arena slot.
Assert-True (([regex]::Matches($source, 'struct cuda_moe_tier_entry\s*\{')).Count -eq 1) `
    'cuda_moe_tier_entry must remain unique'
$tierEntry = Slice-Between 'struct cuda_moe_tier_entry {' 'struct cuda_moe_tiering {'
foreach ($field in @('g133_heat', 'g133_knock', 'g133_touch_streak',
                     'g133_ram_candidate', 'g133_vram_candidate')) {
    Assert-True ($tierEntry.Contains($field)) "missing per-expert field $field"
}
$arenaSlot = Slice-Between 'struct cuda_dynamic_arena_slot {' 'enum : uint32_t {'
$cacheSlot = Slice-Between 'struct cuda_moe_cache_slot {' 'enum cuda_moe_tier_mode'
Assert-True (-not $arenaSlot.Contains('g133_')) 'arena slot gained G133 residency state'
Assert-True (-not $cacheSlot.Contains('g133_')) 'VRAM cache slot gained G133 residency state'

# R2/R3: transaction-wide claims precede victim mutation and release at both terminals.
$arenaBegin = Slice-Between 'extern "C" int ds4_gpu_dynamic_arena_begin(' `
    'static int cuda_dynamic_arena_finish_load_impl('
$claimAt = $arenaBegin.IndexOf('cuda_dynamic_arena_slot_writer_try_acquire')
$mutateAt = $arenaBegin.IndexOf('slot.state = DS4_GPU_ARENA_RETIRING')
Assert-True ($claimAt -ge 0 -and $mutateAt -gt $claimAt) `
    'writer CAS must precede generic arena victim mutation'
Assert-True ($arenaBegin.Contains('ds4_gpu_dynamic_arena_abort(txn)')) `
    'claim failure must abort the complete transaction'
Assert-True (([regex]::Matches($source,
    'cuda_dynamic_arena_txn_release_writer_claims\(txn\)')).Count -eq 2) `
    'writer claims must release exactly at publish and abort terminals'

# R4: observation and policy remain inside the route worker before enforce/upload.
$routeWorker = Slice-Between 'static void *cuda_moe_route_worker(void *arg) {' `
    'static int cuda_moe_expert_cache_copy_to_compact_async('
$observeAt = $routeWorker.IndexOf('cuda_moe_tiering_observe_route(')
$enforceAt = $routeWorker.IndexOf('cuda_moe_tiering_enforce_request(')
Assert-True ($observeAt -ge 0 -and $enforceAt -gt $observeAt) `
    'decode heat observation must precede route-worker enforcement'

# R5/S2-S5: master gate, mass seed, decayed-heat victims, budget, and telemetry.
Assert-True ($source.Contains('getenv("DS4_G133_TIER")')) 'missing master gate'
foreach ($knob in @('DS4_G133_KNOCK_X', 'DS4_G133_KNOCK_Y',
                    'DS4_G133_DECAY', 'DS4_G133_SEED_DYNAMIC',
                    'DS4_G133_PROMOTE_BUDGET')) {
    Assert-True ($source.Contains($knob)) "missing knob $knob"
}
$seed = Slice-Between 'static int cuda_moe_prefill_vram_seed(' `
    'static cuda_moe_expert_cache *cuda_moe_expert_cache_prepare('
Assert-True ($seed.Contains('g_prefill_mass_observer.mass[entry_index]')) `
    'dynamic seed must consume prefill demand mass'
$pick = Slice-Between 'static int cuda_moe_tiering_pick_vram_slot(' `
    'static int cuda_moe_tiering_enforce_request('
Assert-True ($pick.Contains('cuda_g133_decayed_heat')) `
    'VRAM victim selection must use decayed heat'
Assert-True ($pick.Contains('g133_promote_remaining')) `
    'promotion path must enforce the per-token budget'
foreach ($field in @('h2d_ms', 'warm_hit_pct', 'promotions', 'reaps',
                     'knock_promotions', 'thrash_guard_trips')) {
    Assert-True ($source.Contains($field)) "missing attribution field $field"
}

Write-Output 'G133 M1 static contract: PASS'
