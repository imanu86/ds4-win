$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $root 'ds4_cuda.cu'
$source = [System.IO.File]::ReadAllText($sourcePath)
$corePath = Join-Path $root 'ds4.c'
$core = [System.IO.File]::ReadAllText($corePath)
$osFilePath = Join-Path $root 'src/platform/os_file.c'
$osFile = [System.IO.File]::ReadAllText($osFilePath)
$osThreadPath = Join-Path $root 'src/platform/os_thread.c'
$osThread = [System.IO.File]::ReadAllText($osThreadPath)

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

# R1: correctness residency state and bounded advisory state are distinct.
Assert-True (([regex]::Matches($source, 'struct cuda_moe_tier_entry\s*\{')).Count -eq 1) `
    'cuda_moe_tier_entry must remain unique'
$advisoryEntry = Slice-Between 'struct cuda_g133_advisory_entry {' `
    'struct cuda_moe_tier_entry {'
$tierEntry = Slice-Between 'struct cuda_moe_tier_entry {' 'struct cuda_moe_tiering {'
Assert-True ($advisoryEntry.Contains('std::atomic<uint64_t> decayed_heat') -and
             $advisoryEntry.Contains('std::atomic<uint64_t> streak_epoch') -and
             $advisoryEntry.Contains('promotion-age window counter') -and
             $advisoryEntry.Contains('One relaxed load snapshots all') -and
             $advisoryEntry.Contains('cuda_g133_advisory_pack(') -and
             $advisoryEntry.Contains('memory_order_relaxed') -and
             $advisoryEntry.Contains('no per-position history') -and
             -not $advisoryEntry.Contains('promotion_epoch')) `
    'advisory state must be bounded relaxed atomics with documented tolerance'
Assert-True ($tierEntry.Contains('cuda_g133_advisory_entry g133_advisory') -and
             $tierEntry.Contains('ram_slot') -and
             $tierEntry.Contains('ram_generation')) `
    'per-expert advisory state must be split from strict lifecycle fields'
Assert-True (-not $tierEntry.Contains('std::vector') -and
             -not $source.Contains('g133_observed_position_epochs') -and
             -not $source.Contains('g133_observed_base_position_epoch')) `
    'G133 must not retain unbounded per-position storage or marker machinery'
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

$epochHook = Slice-Between 'extern "C" ds4_gpu_g133_epoch ds4_gpu_g133_decode_position_begin(void)' `
    'static void cuda_g133_refresh_entry('
Assert-True ($epochHook.Contains('g_cuda_g133_decode_position_epoch++')) `
    'core position hook must advance the authoritative G133 epoch'
Assert-True ($epochHook.Contains('g_cuda_request_epoch')) `
    'position epoch generation must reuse the authoritative request epoch'
$requestBegin = Slice-Between 'extern "C" int ds4_gpu_dynamic_arena_request_begin(void)' `
    'extern "C" void ds4_gpu_dynamic_arena_observer_reset(void)'
Assert-True ($requestBegin.Contains('g_cuda_request_epoch++') -and
             $requestBegin.Contains('g_cuda_g133_decode_position_epoch = 0u;') -and
             $requestBegin.Contains('20 request-local position bits')) `
    'request generation must advance while resetting request-local position time'

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

# Round-8 D1-D3: promotion uses a reachable consecutive-touch integer streak;
# one pack/unpack helper pair owns the advisory word layout, streaks saturate,
# and demotion uses one coherent snapshot with immediate no-touch gaps plus
# promotion age. EMA heat ranks victims only.
$g133Record = Slice-Between 'static void cuda_g133_record_observation(' `
    'static double cuda_g133_decayed_heat('
Assert-True ($g133Record.Contains('decayed_heat.store(') -and
             $g133Record.Contains('streak_epoch.compare_exchange_weak(') -and
             $g133Record.Contains('cuda_g133_advisory_pack(next)') -and
             $g133Record.Contains('cuda_g133_advisory_unpack(prior)') -and
             $g133Record.Contains('cuda_g133_advisory_epoch_consecutive') -and
             $g133Record.Contains('prior_fields.streak < CUDA_G133_STREAK_MAX') -and
             $g133Record.Contains('(uint32_t)CUDA_G133_STREAK_MAX') -and
             $g133Record.Contains('std::memory_order_relaxed') -and
             -not $g133Record.Contains('std::lower_bound') -and
             -not $g133Record.Contains('.insert(')) `
    'G133 observations must remain bounded O(1) relaxed-atomic updates'
$ramCandidate = Slice-Between 'static int cuda_g133_ram_candidate(' `
    'static void cuda_g133_update_entry_candidate_state('
Assert-True ($ramCandidate.Contains('cuda_g133_consecutive_streak') -and
             -not $ramCandidate.Contains('cuda_g133_advisory_heat')) `
    'KNOCK promotion gates must use only the reachable integer streak'
$epochPacking = Slice-Between 'static const uint64_t CUDA_G133_TOUCH_SCALE' `
    'static uint32_t cuda_g133_consecutive_streak('
$packingHelpers = Slice-Between 'static inline uint64_t cuda_g133_advisory_pack(' `
    'struct cuda_g133_advisory_entry {'
Assert-True (([regex]::Matches($source,
                 'static inline uint64_t cuda_g133_advisory_pack\(')).Count -eq 1 -and
             ([regex]::Matches($source,
                 'static inline cuda_g133_advisory_fields cuda_g133_advisory_unpack\(')).Count -eq 1) `
    'G133 advisory word must have exactly one pack helper and one unpack helper'
Assert-True ($source.Contains('CUDA_G133_PROMOTION_AGE_BITS = 12u') -and
             $source.Contains('CUDA_G133_EPOCH_POSITION_BITS = 20u') -and
             $source.Contains('CUDA_G133_EPOCH_REQUEST_BITS') -and
             $source.Contains('static_assert(CUDA_G133_EPOCH_REQUEST_BITS >= 24u') -and
             $epochPacking.Contains('epoch.request_epoch') -and
             $epochPacking.Contains('epoch.position_epoch') -and
             $epochPacking.Contains('promotion_age') -and
             $epochPacking.Contains('CUDA_G133_EPOCH_REQUEST_MASK') -and
             $epochPacking.Contains('cuda_g133_advisory_epoch_consecutive') -and
             $epochPacking.Contains('(int32_t)(current.position_epoch - prior.position_epoch)') -and
             -not $packingHelpers.Contains('std::min')) `
    'packed advisory word must contain streak, promotion age, position, and request generation'
$rawAdvisoryShiftLines = @($source -split '\r?\n' | Where-Object {
    ($_ -match 'g133|advisory|streak_epoch') -and ($_ -match '<<\s*(8|32)\b')
})
Assert-True ($rawAdvisoryShiftLines.Count -eq 0) `
    'G133 advisory sites must not hand-roll raw << 8 or << 32 packing'
$observe = Slice-Between 'static cuda_moe_tier_state cuda_moe_tiering_observe_route(' `
    'static uint64_t cuda_iq1_promotion_current_request_epoch(void)'
Assert-True ($observe.IndexOf('cuda_g133_record_observation(') -ge 0 -and
             $observe.IndexOf('entry.frequency++') -gt
                 $observe.IndexOf('cuda_g133_record_observation(')) `
    'advisory observation must precede generic route accounting'
$promoteRefresh = Slice-Between 'static void cuda_g133_advisory_budget_refresh(' `
    'static int cuda_g133_advisory_budget_reserve('
Assert-True ($promoteRefresh.Contains('max_epoch.load(') -and
             $promoteRefresh.Contains('compare_exchange_weak(') -and
             $promoteRefresh.Contains('cuda_g133_advisory_unpack(current)') -and
             $promoteRefresh.Contains('cuda_g133_advisory_unpack(maximum)') -and
             $promoteRefresh.Contains('remaining.store(')) `
    'promotion budget refresh must be keyed on wrap-safe atomic epoch order'

$dispatch = Slice-Between 'static uint64_t g_cuda_g133_decode_position_epoch = 0u;' `
    'struct cuda_g133_telemetry_counters {'
Assert-True ($dispatch.Contains('ds4_gpu_g133_enabled = 0') -and
             $dispatch.Contains('ds4_gpu_g133_enabled = 1') -and
             -not $dispatch.Contains('cuda_g133_decode_position_noop') -and
             -not $dispatch.Contains('ds4_gpu_g133_position_begin_fn')) `
    'G133 position hook must use an initialization-cached direct-call gate'
$gpuInit = Slice-Between 'extern "C" int ds4_gpu_init(void)' `
    'extern "C" void ds4_gpu_cleanup(void)'
Assert-True ($gpuInit.Contains('cuda_g133_initialize_dispatch()')) `
    'CUDA startup must resolve the G133 hook dispatch once'
$decodeGate = Slice-TextBetween $core 'static bool metal_graph_encode_token_raw_swa(' `
    'static bool metal_graph_eval_token_raw_swa('
Assert-True (([regex]::Matches($decodeGate,
                 'if \(ds4_gpu_g133_enabled\)')).Count -eq 1 -and
             $decodeGate.Contains('behavioral: this one cached') -and
             $decodeGate.Contains('token-hash/performance equality')) `
    'ordinary decode must use one cached branch and document the behavioral OFF gate'
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
Assert-True ($routeWorker.Contains('cuda_moe_route_worker_publish_completed')) `
    'route worker must publish a completion sequence after policy work'
$completionPublish = Slice-Between 'static void cuda_moe_route_worker_publish_completed(' `
    'static int cuda_moe_route_worker_drain_completed('
Assert-True ($completionPublish.Contains('route_completed_sequence = sequence;')) `
    'worker-completed publication must store the completed sequence'
$cacheFields = Slice-Between 'struct cuda_moe_expert_cache {' `
    'static cuda_moe_expert_cache g_moe_expert_cache;'
Assert-True ($cacheFields.Contains('route_consumed_sequence') -and
             $cacheFields.Contains('route_completed_sequence')) `
    'copy acknowledgement and worker completion must remain distinct sequences'
$boundaryDrainAt = $requestBegin.IndexOf('cuda_moe_route_worker_drain_completed(')
$boundaryFlushAt = $requestBegin.IndexOf('cuda_q1_0_ssd_wrap_flush();')
$boundaryEpochAt = $requestBegin.IndexOf('g_cuda_request_epoch++')
Assert-True ($requestBegin.Contains('const int shared_policy_active =') -and
             $requestBegin.Contains('if (shared_policy_active') -and
             $boundaryDrainAt -ge 0 -and $boundaryFlushAt -gt $boundaryDrainAt -and
             $boundaryEpochAt -gt $boundaryFlushAt -and
             $requestBegin.Contains('return 0;')) `
    'active G133 boundary must drain before SSD flush/epoch and fail closed'
Assert-True ($core.Contains('if (!ds4_gpu_dynamic_arena_request_begin())')) `
    'request-boundary failure must propagate to the session API'
$mixedPolicy = Slice-Between 'extern "C" int ds4_gpu_routed_moe_mixed_q1_0_one_tensor(' `
    'extern "C" int ds4_gpu_routed_moe_mixed_iq1_one_tensor('
$mixedDrainAt = $mixedPolicy.IndexOf('cuda_moe_route_worker_drain_completed("q1-0-mixed-policy")')
$mixedObserveAt = $mixedPolicy.IndexOf('cuda_moe_tiering_observe_route(')
Assert-True ($mixedDrainAt -ge 0 -and $mixedObserveAt -gt $mixedDrainAt) `
    'decode-thread mixed-Q1 policy mutation must drain worker completion first'
Assert-True ($mixedPolicy.Contains('if (cuda_g133_shared_policy_active()') -and
             $requestBegin.Contains('shared_policy_active &&')) `
    'new request and mixed-policy waits must be gated off the disabled path'
Assert-True (([regex]::Matches($source,
                 'if \(cuda_g133_shared_policy_active\(\) &&\s*!cuda_moe_route_worker_drain_completed')).Count -eq 5) `
    'all mixed and route-failure completion drains must be purity-gated'

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
Assert-True ($pick.Contains('cuda_g133_advisory_budget_reserve')) `
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
$preadAt = $enforce.IndexOf('cuda_moe_transient_pread_chunked(')
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
$routeFailure = Slice-TextBetween $routeFinish `
    'if (*(volatile uint32_t *)cache->route_failed_host == sequence)' `
    'const cuda_moe_route_request *request = cache->route_request_host;'
$failureDrainAt = $routeFailure.IndexOf('cuda_moe_route_worker_drain_completed(')
$failureInvalidateAt = $routeFailure.IndexOf('cuda_moe_expert_cache_invalidate();')
Assert-True ($failureDrainAt -ge 0 -and $failureInvalidateAt -gt $failureDrainAt) `
    'decode-thread failure invalidation must drain worker completion first'
Assert-True ($routeFailure.Contains('cuda_g133_shared_policy_active() &&')) `
    'route-failure completion drain must preserve disabled-path purity'
Assert-True ($routeFinish.Contains('if (cuda_moe_route_worker_cancel_and_join(') -and
             $routeFinish.IndexOf('cuda_moe_expert_cache_invalidate();') -gt
                 $routeFinish.IndexOf('cuda_moe_route_worker_cancel_and_join')) `
    'only a completed bounded join may precede correctness-state invalidation'
Assert-True ($routeFinish.Contains('progress > last_read_progress') -and
             $routeFinish.Contains('transient_absolute_deadline') -and
             $routeFinish.Contains('std::memory_order_acquire') -and
             $routeFinish.Contains('Establish a request-local baseline') -and
             $routeFinish.Contains('cuda_moe_route_worker_cancel_and_join')) `
    'watchdog must use request-local acquire progress and join on cancellation'
$chunkedRead = Slice-Between 'static int cuda_moe_transient_pread_chunked(' `
    'static void cuda_moe_route_worker_publish_completed('
Assert-True ($chunkedRead.Contains('const uint64_t chunk_bytes = 1u << 20;') -and
             $chunkedRead.Contains('os_pread_cancellable(') -and
             $chunkedRead.Contains('fetch_add(') -and
             $chunkedRead.Contains('std::memory_order_release') -and
             $chunkedRead.Contains('cuda_wall_sec() >= absolute_deadline')) `
    'transient SSD service must use observable chunks with an absolute deadline'
$enforceDeadline = Slice-Between 'static int cuda_moe_tiering_enforce_request(' `
    'static void *cuda_moe_route_worker(void *arg) {'
Assert-True (([regex]::Matches($enforceDeadline,
                 'cuda_g133_transient_io_timeout_seconds\(\)')).Count -eq 1 -and
             $enforceDeadline.Contains('transient_request_deadline') -and
             -not $enforceDeadline.Contains('const double absolute_deadline =')) `
    'transient service must use one request-wide absolute deadline'
Assert-True ($enforceDeadline.IndexOf('os_pread_cancellable_reset(') -ge 0 -and
             $enforceDeadline.IndexOf('route_transient_read_sequence.store(') -gt
                 $enforceDeadline.IndexOf('os_pread_cancellable_reset(')) `
    'only the G133 transient path may reset cancellation before publishing its read'
Assert-True ($osFile.Contains('CancelIoEx(state->file, &state->overlapped)') -and
             $source.Contains('os_pread_cancel(&cache->route_transient_pread, sequence)') -and
             -not $source.Contains('CancelSynchronousIo')) `
    'Windows transient cancellation must target the live OVERLAPPED with CancelIoEx'
$cancellablePread = Slice-TextBetween $osFile 'int64_t os_pread_cancellable(' `
    'int64_t os_pread('
$armAt = $cancellablePread.IndexOf('InterlockedExchange(&state->active, 1);')
$cancelCheckAt = $cancellablePread.IndexOf('&state->cancel_sequence, 0, 0')
Assert-True ($armAt -ge 0 -and $cancelCheckAt -gt $armAt -and
             ([regex]::Matches($cancellablePread,
                 '&state->cancel_sequence, 0, 0')).Count -ge 2) `
    'cancellable pread must arm before checking cancel and recheck after submission'
$genericPreadAt = $osFile.IndexOf('int64_t os_pread(')
Assert-True ($genericPreadAt -ge 0) 'missing generic os_pread'
$genericPread = $osFile.Substring($genericPreadAt)
Assert-True ($genericPread.Contains('OVERLAPPED ol;') -and
             -not $genericPread.Contains('os_pread_cancellable(') -and
             -not $genericPread.Contains('Interlocked')) `
    'generic os_pread must retain its original non-cancellable path'
$cancelJoin = Slice-Between 'static int cuda_moe_route_worker_cancel_and_join(' `
    'static int cuda_moe_route_worker_drain_completed('
Assert-True ($cancelJoin.Contains('os_thread_join_timeout') -and
             $cancelJoin.Contains('route_transient_dead_sequence.store(') -and
             $cancelJoin.Contains('route_worker_safe_leaked = 1') -and
             $cancelJoin.Contains('os_thread_detach') -and
             $cancelJoin.Contains('writer slot/cache safe-leaked permanently')) `
    'route cancellation must bound its join and safe-leak a still-written slot'
$cachePrepare = Slice-Between 'static cuda_moe_expert_cache *cuda_moe_expert_cache_prepare(' `
    'static int cuda_moe_expert_cache_find('
Assert-True ($cachePrepare.Contains(
                 'if (g_moe_expert_cache.route_worker_safe_leaked) return NULL;')) `
    'a safe-leaked route cache must remain permanently dead and never be reused'
Assert-True ($osThread.Contains('WaitForSingleObject(t, (DWORD)timeout_ms)') -and
             $osThread.Contains('pthread_timedjoin_np')) `
    'Windows and Linux route joins must both expose a bounded wait'
Assert-True ($source.Contains('getenv("DS4_G133_TRANSIENT_IO_TIMEOUT_S")') -and
             $source.Contains('static double timeout_seconds = 30.0;')) `
    'transient SSD absolute timeout must expose the default-30-second environment contract'
Assert-True ($source.Contains('"DS4_G133_KNOCK_X", 3u, 1u,') -and
             $source.Contains('"DS4_G133_KNOCK_Y", 5u, 1u,') -and
             $source.Contains('DS4_G133_KNOCK_X+DS4_G133_KNOCK_Y') -and
             $source.Contains('must be <= %llu because G133 advisory streak is %u bits') -and
             $source.Contains('ds4_gpu_g133_validate_context') -and
             $source.Contains('G133 advisory position epoch is %u bits') -and
             -not $source.Contains('must exceed demotion margin')) `
    'DS4_G133 KNOCK and context bounds must match the packed representation'
Assert-True ($source.Contains('!(g133_decay > 0.0 && g133_decay < 1.0)') -and
             $source.Contains('must satisfy 0 < decay < 1')) `
    'DS4_G133_DECAY must reject both zero and one with a clear diagnostic'
$demotion = Slice-Between 'static int cuda_g133_demotion_eligible_at(' `
    'static void cuda_g133_update_entry_candidate_state('
Assert-True ($demotion.Contains('streak_broken') -and
             $demotion.Contains('promotion_age_ready') -and
             $demotion.Contains('snapshot.promotion_age') -and
             $demotion.Contains('!cuda_g133_advisory_same_epoch(prior, current)') -and
             $demotion.Contains('g133_knock_y') -and
             -not $demotion.Contains('promotion_epoch') -and
             -not $demotion.Contains('cuda_g133_advisory_epoch_consecutive') -and
             -not $demotion.Contains('cuda_g133_advisory_heat')) `
    'G133 demotion eligibility must be immediate broken-streak plus promotion-age only'
Assert-True (-not $source.Contains('DS4_G132_U1_ATTRIBUTION')) `
    'G132 attribution alias must remain absent from the base path'
foreach ($field in @('upload_sync_wait_ms', 'vram_hit_pct', 'ram_hit_pct',
                     'promotions', 'reaps',
                     'knock_promotions', 'thrash_guard_trips')) {
    Assert-True ($source.Contains($field)) "missing attribution field $field"
}

Write-Output 'G133 M1 static contract: PASS'
