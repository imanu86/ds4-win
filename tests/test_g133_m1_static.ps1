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

# Round-3 D1-D3/D6: target positions create immutable route epochs; workers
# consume only their request snapshot and request generation follows the arena.
$routeRequest = Slice-Between 'struct cuda_moe_route_request {' `
    'struct ds4_gpu_async_read {'
Assert-True ($routeRequest.Contains('ds4_gpu_g133_epoch g133_epoch;')) `
    'route request must carry an immutable G133 epoch snapshot'
$routeKernel = Slice-Between '__global__ static void moe_resolve_resident_routes_kernel(' `
    '__global__ static void iq1_mixed_cold_one_plan_kernel('
$snapshotAt = $routeKernel.IndexOf('request->g133_epoch = g133_epoch;')
$publishAt = $routeKernel.IndexOf('request->sequence = sequence;')
Assert-True ($snapshotAt -ge 0 -and $publishAt -gt $snapshotAt) `
    'route epoch snapshot must be written before request publication'

$decodeLayer = Slice-TextBetween $core 'static bool metal_graph_encode_decode_layer(' `
    'static bool metal_graph_matmul_plain_tensor('
Assert-True (-not $decodeLayer.Contains('il == 0u') -and
             $decodeLayer.Contains('ds4_gpu_g133_epoch     g133_epoch')) `
    'decode layer must receive an explicit epoch instead of inferring layer zero'
$decodeOne = Slice-TextBetween $core 'static bool metal_graph_encode_token_raw_swa(' `
    'static bool metal_graph_eval_token_raw_swa('
Assert-True ($decodeOne.Contains('ds4_gpu_g133_decode_position_begin()') -and
             $decodeOne.Contains('g133_epoch);')) `
    'ordinary target decode must create one explicit position epoch'
$decodeTwo = Slice-TextBetween $core 'static bool metal_graph_verify_decode2_exact(' `
    'static uint32_t metal_graph_raw_cap_for_context('
Assert-True ($decodeTwo.Contains('g133_epoch0') -and
             $decodeTwo.Contains('g133_epoch1') -and
             ([regex]::Matches($decodeTwo,
                 'ds4_gpu_g133_decode_position_begin\(\)')).Count -eq 2) `
    'exact two-position verification must create two distinct epochs'
$decodeBench = Slice-TextBetween $core 'static int metal_graph_decode_test(' `
    'static int metal_graph_first_token_full_test('
Assert-True ($decodeBench.Contains('ds4_gpu_g133_decode_position_begin()')) `
    'nonzero-layer decode benchmark must create a position epoch'

$epochHook = Slice-Between 'static ds4_gpu_g133_epoch cuda_g133_decode_position_enabled(void)' `
    'static void cuda_g133_refresh_entry('
Assert-True ($epochHook.Contains('g_cuda_g133_decode_position_epoch++')) `
    'core position hook must advance the authoritative G133 epoch'
Assert-True ($epochHook.Contains('g_cuda_request_epoch')) `
    'position epoch generation must reuse the authoritative request epoch'
$requestBegin = Slice-Between 'extern "C" void ds4_gpu_dynamic_arena_request_begin(void)' `
    'extern "C" void ds4_gpu_dynamic_arena_observer_reset(void)'
Assert-True ($requestBegin.Contains('g_cuda_request_epoch++') -and
             $requestBegin.Contains('g_cuda_g133_decode_position_epoch = 0u;')) `
    'G133 generation and position reset must bind to the arena request boundary'

$routeWorker = Slice-Between 'static void *cuda_moe_route_worker(void *arg) {' `
    'static int cuda_moe_expert_cache_copy_to_compact_async('
Assert-True ($routeWorker.Contains('request.g133_epoch') -and
             $routeWorker.Contains('route_consumed_sequence = sequence;') -and
             -not $routeWorker.Contains('g_cuda_request_epoch') -and
             -not $routeWorker.Contains('g_cuda_g133_decode_position_epoch')) `
    'route worker must consume only its immutable request epoch snapshot'
$routeBegin = Slice-Between 'static cuda_moe_expert_cache *cuda_moe_gpu_resident_routes_begin(' `
    'static cuda_moe_expert_cache *cuda_moe_gpu_resident_routes_finish('
Assert-True ($routeBegin.Contains('route_consumed_sequence') -and
             $routeBegin.Contains('prior_sequence')) `
    'route request storage must not be reused before worker snapshot acknowledgement'

$dispatch = Slice-Between 'static uint64_t g_cuda_g133_decode_position_epoch = 0u;' `
    'struct cuda_g133_telemetry_counters {'
Assert-True ($dispatch.Contains('ds4_gpu_g133_decode_position_begin') -and
             $dispatch.Contains('cuda_g133_decode_position_noop;') -and
             $dispatch.Contains('cuda_g133_decode_position_enabled')) `
    'G133 position hook must use initialization-time no-op/enabled dispatch'
$gpuInit = Slice-Between 'extern "C" int ds4_gpu_init(void)' `
    'extern "C" void ds4_gpu_cleanup(void)'
Assert-True ($gpuInit.Contains('cuda_g133_initialize_dispatch()')) `
    'CUDA startup must resolve the G133 hook dispatch once'
$tokenHook = Slice-Between 'extern "C" void ds4_gpu_g130_attribution_token_begin(' `
    'extern "C" void ds4_gpu_g130_attribution_token_end('
Assert-True (-not $tokenHook.Contains('g133_decode_position') -and
             -not $tokenHook.Contains('g133_decode_token')) `
    'G133 epoch advance must not be coupled to attribution-only code'
Assert-True (-not $tokenHook.Contains('cuda_g133_tier_requested()') -and
             $tokenHook.Contains('g_cuda_g133_attribution_snapshot(state);')) `
    'attribution-enabled/G133-unset token path must have no per-position feature check'

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
Assert-True ($ramPick.Contains('cuda_g133_ram_demotion_eligible(entry, g133_epoch)')) `
    'RAM victim path must require G133 demotion eligibility'
Assert-True ($ramPick.Contains('candidate_score <=') -and
             $ramPick.Contains('g133_demotion_margin')) `
    'RAM victim path must enforce an admission margin'
Assert-True ($ramPick.Contains('after_writer_cas_loss') -and
             $ramPick.Contains('lost_entry = best_entry')) `
    'RAM victim selection must retry alternate eligible victims after writer CAS loss'
$enforce = Slice-Between 'static int cuda_moe_tiering_enforce_request(' `
    'static void *cuda_moe_route_worker(void *arg) {'
$reservationFinish = Slice-Between 'static int cuda_moe_tiering_finish_vram_reservations(' `
    'static int cuda_moe_tiering_enforce_request('
$syncAt = $reservationFinish.IndexOf('cudaStreamSynchronize(cache->route_upload_stream)')
$commitAt = $reservationFinish.IndexOf('cuda_moe_tiering_commit_vram_reservations(')
$refundAt = $reservationFinish.IndexOf('cuda_moe_tiering_refund_failed_promotions(')
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
$settleAt = $enforce.IndexOf('cuda_moe_tiering_finish_vram_reservations(')
Assert-True ($settleAt -ge 0 -and $settleAt -lt $preadAt) `
    'other experts provisional VRAM reservations must settle before transient SSD read'
$routeFinish = Slice-Between 'static cuda_moe_expert_cache *cuda_moe_gpu_resident_routes_finish(' `
    'static cuda_moe_expert_cache *cuda_moe_gpu_resident_routes_submit('
Assert-True ($routeFinish.Contains('route_transient_read_sequence') -and
             $routeFinish.Contains('wait_deadline = cuda_wall_sec() + 5.0;')) `
    'readiness watchdog must extend while transient SSD service is active'
Assert-True ($source.Contains('(double)g133_knock_x <= g133_demotion_margin') -and
             $source.Contains('must exceed demotion margin')) `
    'DS4_G133_KNOCK_X=1 must be rejected when margin consumes its threshold'
Assert-True ($source.Contains('!(g133_decay > 0.0 && g133_decay < 1.0)') -and
             $source.Contains('must satisfy 0 < decay < 1')) `
    'DS4_G133_DECAY must reject both zero and one with a clear diagnostic'
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
