$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $root 'ds4_cuda.cu'
$source = [System.IO.File]::ReadAllText($sourcePath)
$corePath = Join-Path $root 'ds4.c'
$core = [System.IO.File]::ReadAllText($corePath)

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "G133 M1 static contract failed: $Message" }
}

function Slice-TextBetween([string]$Text, [string]$Start, [string]$End) {
    $startIndex = $Text.IndexOf($Start, [StringComparison]::Ordinal)
    Assert-True ($startIndex -ge 0) "missing start marker: $Start"
    $endIndex = $Text.IndexOf($End, $startIndex, [StringComparison]::Ordinal)
    Assert-True ($endIndex -gt $startIndex) "missing end marker: $End"
    return $Text.Substring($startIndex, $endIndex - $startIndex)
}

function Slice-Between([string]$Start, [string]$End) {
    return Slice-TextBetween $source $Start $End
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

# Round-2 R1/R4: core target positions own epoch advance; attribution stays reporting-only.
$decodeLayer = Slice-TextBetween $core 'static bool metal_graph_encode_decode_layer(' `
    'static bool metal_graph_matmul_plain_tensor('
Assert-True ($decodeLayer.Contains('if (il == 0u) ds4_gpu_g133_decode_position_begin();')) `
    'shared layer-0 target-decode boundary must advance the G133 epoch'
$epochHook = Slice-Between 'extern "C" void ds4_gpu_g133_decode_position_begin(void)' `
    'static void cuda_g133_refresh_entry('
Assert-True ($epochHook.Contains('g_cuda_g133_decode_position_epoch++')) `
    'core position hook must advance the authoritative G133 epoch'
$tierPrepare = Slice-Between 'static int cuda_moe_tiering_prepare(void)' `
    'static int cuda_moe_tiering_snapshot_ram_ptrs('
Assert-True ($tierPrepare.Contains('g_cuda_g133_decode_position_epoch')) `
    'lazy tiering setup must inherit the authoritative core epoch'
$tokenHook = Slice-Between 'extern "C" void ds4_gpu_g130_attribution_token_begin(' `
    'extern "C" void ds4_gpu_g130_attribution_token_end('
Assert-True (-not $tokenHook.Contains('g133_decode_position') -and
             -not $tokenHook.Contains('g133_decode_token')) `
    'G133 epoch advance must not be coupled to attribution-only code'
$attribReturnAt = $tokenHook.IndexOf('if (!g_cuda_g130_attribution_enabled) return;')
$attribG133At = $tokenHook.IndexOf('cuda_g133_tier_requested()')
Assert-True ($attribReturnAt -ge 0 -and $attribG133At -gt $attribReturnAt) `
    'attribution-disabled early return must precede every G133 token-hook check'

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
$txnGuard = Slice-Between 'struct cuda_dynamic_arena_transaction_guard {' `
    'static int cuda_dynamic_arena_wrap_publish_target('
Assert-True ($txnGuard.Contains('~cuda_dynamic_arena_transaction_guard()')) `
    'arena wrap must use an RAII transaction guard'
$guardJoinAt = $txnGuard.IndexOf('join_started_workers();')
$guardAbortAt = $txnGuard.IndexOf('ds4_gpu_dynamic_arena_abort(txn);')
Assert-True ($guardJoinAt -ge 0 -and $guardAbortAt -gt $guardJoinAt) `
    'transaction guard unwind must join workers before aborting writer claims'

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
$ramPick = Slice-Between 'static int cuda_moe_tiering_pick_ram_slot(' `
    'struct cuda_q1_0_promotion_record_context {'
Assert-True ($ramPick.Contains('cuda_g133_ram_demotion_eligible(entry)')) `
    'RAM victim path must require G133 demotion eligibility'
Assert-True ($ramPick.Contains('candidate_score <=') -and
             $ramPick.Contains('g133_demotion_margin')) `
    'RAM victim path must enforce an admission margin'
Assert-True ($ramPick.Contains('after_writer_cas_loss') -and
             $ramPick.Contains('lost_entry = best_entry')) `
    'RAM victim selection must retry alternate eligible victims after writer CAS loss'
$enforce = Slice-Between 'static int cuda_moe_tiering_enforce_request(' `
    'static void *cuda_moe_route_worker(void *arg) {'
$syncAt = $enforce.IndexOf('cudaStreamSynchronize(cache->route_upload_stream)')
$commitAt = $enforce.IndexOf('cuda_moe_tiering_commit_vram_reservations(')
$refundAt = $enforce.IndexOf('cuda_moe_tiering_refund_failed_promotions(')
Assert-True ($syncAt -ge 0 -and $commitAt -gt $syncAt) `
    'promotion counters and tier state must commit only after upload sync'
Assert-True ($refundAt -gt $syncAt) `
    'failed promotions must have a provisional-budget refund path'
$deniedAt = $enforce.IndexOf('serve_transient_on_admission_denial')
$preadAt = $enforce.IndexOf('cuda_pread_full(&g_model_file, host_gate')
$transientAt = $enforce.IndexOf('moe_publish_transient_route_kernel')
Assert-True ($deniedAt -ge 0 -and $preadAt -gt $deniedAt -and
             $transientAt -gt $preadAt) `
    'RAM admission denial must use the exact SSD-to-transient serving path'
Assert-True ($enforce.Contains('!serve_transient_on_admission_denial')) `
    'RAM-required failure must exclude policy-denied transient serves'
Assert-True ($source.Contains('(double)g133_knock_x <= g133_demotion_margin') -and
             $source.Contains('must exceed demotion margin')) `
    'DS4_G133_KNOCK_X=1 must be rejected when margin consumes its threshold'
$demotion = Slice-Between 'static int cuda_g133_ram_demotion_eligible(' `
    'static double cuda_moe_tiering_lfru('
Assert-True ($demotion.Contains('demote_threshold == 0.0') -and
             $demotion.Contains('entry.g133_knock <= 0.0')) `
    'zero-heat RAM entries must be eligible at a zero demotion threshold'
Assert-True (-not $source.Contains('DS4_G132_U1_ATTRIBUTION')) `
    'G132 attribution alias must remain absent from the base path'
foreach ($field in @('upload_sync_wait_ms', 'vram_hit_pct', 'ram_hit_pct',
                     'promotions', 'reaps',
                     'knock_promotions', 'thrash_guard_trips')) {
    Assert-True ($source.Contains($field)) "missing attribution field $field"
}

Write-Output 'G133 M1 static contract: PASS'
