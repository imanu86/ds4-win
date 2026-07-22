$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$source = Get-Content -LiteralPath (Join-Path $root 'ds4_cuda.cu') -Raw
$osFile = Get-Content -LiteralPath (Join-Path $root 'src\platform\os_file.c') -Raw
$osFileHeader = Get-Content -LiteralPath (Join-Path $root 'src\platform\os_file.h') -Raw
$osThread = Get-Content -LiteralPath (Join-Path $root 'src\platform\os_thread.h') -Raw
$presetPath = Join-Path $root 'tests\g73_open.env.ps1'
$preset = Get-Content -LiteralPath $presetPath -Raw

function Assert-Contains([string]$Text, [string]$Needle, [string]$Message) {
    if (-not $Text.Contains($Needle)) { throw $Message }
}
function Slice-Between([string]$Text, [string]$Start, [string]$End) {
    $begin = $Text.IndexOf($Start)
    if ($begin -lt 0) { throw "missing slice start: $Start" }
    $finish = $Text.IndexOf($End, $begin + $Start.Length)
    if ($finish -lt 0) { throw "missing slice end: $End" }
    return $Text.Substring($begin, $finish - $begin)
}

$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
    $presetPath, [ref]$tokens, [ref]$errors)
if ($errors -and $errors.Count) { throw 'G73-OPEN preset has PowerShell syntax errors' }

Assert-Contains $source 'getenv("DS4_G73_OPEN")' 'missing OFF-default G73-OPEN gate'
Assert-Contains $source '!cuda_g73_open_requested()) {' 'cold admission must be bypassed only in G73-OPEN'
Assert-Contains $source 'cuda_moe_transient_pread_chunked(' 'missing bounded exact transient read'
Assert-Contains $source 'request->absolute_deadline = absolute_deadline;' 'route request does not carry one absolute deadline'
Assert-Contains $source 'cuda_moe_fill_span_bounded(' 'selected fallback is not deadline bounded'
Assert-Contains $source 'cuda_g73_terminal_exact_load(' 'missing exact preallocated terminal'
Assert-Contains $source 'terminal-corrupt-model-range' 'corrupt terminal range must be a hard error'
Assert-Contains $osFile 'os_pread_cancellable_timeout(' 'platform reads lack a cancellable timeout API'
Assert-Contains $osFile 'CancelIoEx' 'Windows timed read does not cancel the overlapped operation'
$pread = Slice-Between $osFile 'int64_t os_pread_cancellable_timeout(' `
    'int64_t os_pread_cancellable('
Assert-Contains $pread 'const uint64_t max_chunk = 1024u * 1024u;' `
    'POSIX cancellable pread is not chunk-bounded'
Assert-Contains $pread 'remaining > 0x100000ull' `
    'Windows cancellable pread is not capped at 1 MiB'
Assert-Contains $pread 'atomic_load_explicit(' 'POSIX cancellable pread ignores cancellation'
Assert-Contains $pread 'os_monotonic_sec() >= deadline' 'POSIX cancellable pread ignores its deadline'
Assert-Contains $pread 'WaitForSingleObject(state->event, 50u)' 'Windows post-cancel completion wait is not bounded'
if ($pread -match 'GetOverlappedResult\([\s\S]*?TRUE\)') {
    throw 'Windows cancellable pread still contains an infinite GetOverlappedResult wait'
}
$terminal = Slice-Between $source 'static int cuda_g73_terminal_exact_load(' `
    'static int cuda_g73_outcomes_conserved('
Assert-Contains $terminal 'double absolute_deadline' 'terminal exact does not receive the token deadline'
Assert-Contains $terminal 'cuda_g73_terminal_read_part(' 'terminal exact does not use bounded file reads'
Assert-Contains $source 'os_pread_plain(' 'terminal exact lacks its plain synchronous read path'
Assert-Contains $source 'cuda_g73_terminal_mutex_guard g73_terminal_guard;' `
    'terminal caller lacks scoped mutex ownership'
Assert-Contains $source 'g73_terminal_guard.held_for(&g_cuda_g73_terminal)' `
    'terminal storage consumption is not ownership-asserted'
Assert-Contains $terminal 'assert(terminal.mutex_owned);' `
    'terminal loader does not require caller-held ownership'
Assert-Contains $terminal 'budget_overrun' 'terminal overruns are not explicitly logged'
Assert-Contains $terminal 'WDDM offers' 'accepted WDDM bandwidth assumption is undocumented'
Assert-Contains $terminal 'cudaMemcpy(' 'terminal exact does not perform its completing H2D'
if ($terminal.Contains('cudaMalloc(') -or $terminal.Contains('.resize(') -or
    $terminal.Contains('model_map +')) {
    throw 'terminal exact performs serving-path acquisition or mmap access'
}
if ($terminal.Contains('cudaStreamSynchronize(')) { throw 'terminal exact has an unbounded stream wait' }
if ($terminal.Contains('os_pread_cancellable') -or
    $terminal.Contains('cuda_g73_terminal_claim_pinned_arena')) {
    throw 'terminal exact depends on a shared serving resource'
}
Assert-Contains $source 'BOOT CONFIG ERROR: terminal' 'terminal preallocation failure is not a boot error'
Assert-Contains $source 'os_pread_cancellable_pending(' 'persistent I/O slots do not prevent buffer reuse'
$reservationFinish = Slice-Between $source `
    'static int cuda_moe_tiering_finish_vram_reservations(' `
    'static void cuda_g73_classify_request('
if ($reservationFinish.Contains('cudaStreamSynchronize(')) {
    throw 'tiering reservation completion has an unbounded stream wait'
}
Assert-Contains $source 'cuda_g73_open_maybe_schedule_rotation(' 'missing G133-to-SSD-wrap rotator seam'
Assert-Contains $source 'g73_open_rotation' 'SSD-wrap jobs must distinguish exact G73 rotation from Q1 promotion'
Assert-Contains $source 'cuda_q1_0_ssd_wrap_fail_and_release_all_locked(' 'missing atomic rotator teardown'
$finishOne = Slice-Between $source 'static int cuda_q1_0_ssd_wrap_finish_one(' `
    'static int cuda_q1_0_ssd_wrap_poll_internal('
Assert-Contains $finishOne 'CUDA_Q1_0_SSD_WRAP_RAM_COMMITTING;' `
    'rotator does not mark publication before dropping its mutex'
Assert-Contains $finishOne 'os_mutex_unlock(&state.mutex);' `
    'rotator still holds its mutex through publication'
$releaseAll = Slice-Between $source `
    'static void cuda_q1_0_ssd_wrap_fail_and_release_all_locked(' `
    'static void cuda_q1_0_ssd_wrap_disable('
Assert-Contains $releaseAll 'job.state == CUDA_Q1_0_SSD_WRAP_RAM_COMMITTING' `
    'release-all does not skip committing jobs'
Assert-Contains $releaseAll 'os_cond_timedwait_ms(' `
    'release-all does not bounded-await committing jobs'
Assert-Contains $releaseAll 'writer claim/slot safe-leaked ' `
    'release-all lacks the permanent dead-slot terminal'
Assert-Contains $source 'state.tier_generation++' `
    'tier reset does not advance the rotator publication generation'
Assert-Contains $source 'local.tier_generation != state.tier_generation' `
    'rotator publisher does not revalidate tier generation'
Assert-Contains $source 'retained_entries->swap(g_moe_tiering.entries)' `
    'tier reset does not retain entries referenced by a stalled publisher'
$submit = Slice-Between $source 'static int cuda_q1_0_ssd_wrap_submit(' `
    'static void cuda_g73_open_maybe_schedule_rotation('
Assert-Contains $submit 'if (state.failed || state.stop) {' `
    'rotator submission does not recheck teardown state under the mutex'
Assert-Contains $submit 'cuda_dynamic_arena_slot_writer_release(&slot);' `
    'rotator teardown-race refusal does not release its writer claim'
Assert-Contains $source 'request-boundary-transport-stall' 'request-boundary transport stall is not fatal'
Assert-Contains $source 'cuda_q1_0_ssd_wrap_release_boundary_jobs_locked(' `
    'missing normal request-boundary release/rearm path'
$boundaryFlush = Slice-Between $source 'static void cuda_q1_0_ssd_wrap_flush(void) {' `
    'static void cuda_q1_0_ssd_wrap_release(int report)'
Assert-Contains $boundaryFlush 'cuda_q1_0_ssd_wrap_poll_internal(1)' `
    'request boundary does not force-publish ready rotations'
Assert-Contains $boundaryFlush 'request-boundary-release' `
    'request boundary does not use nonfatal release/rearm cleanup'
Assert-Contains $source 'state.stop = 0;' `
    'normal request-boundary cleanup does not explicitly re-arm the rotator'
Assert-Contains $osThread 'os_cond_timedwait_ms(' 'rotator condition wait is not timed'
Assert-Contains $source 'using preallocated exact terminal' 'missing never-refusing terminal fallback'
foreach ($counter in @('out_of_mask_routes', 'served_transient',
        'served_promoted', 'served_selected_fallback', 'served_terminal_exact',
        'clamped', 'request_refused', 'rotation_promotions', 'rotation_reaps')) {
    Assert-Contains $source $counter "missing G73 attribution counter: $counter"
}
Assert-Contains $source 'out_of_mask_routes != served + clamped + request_refused' 'missing token attribution conservation assertion'
Assert-Contains $source 'clamped != 0u || request_refused != 0u' 'clamp/refusal are not structural-zero assertions'
Assert-Contains $source '!cuda_g73_commit_outcomes(layer_index, g73_outcomes)' 'outcomes are not committed after exact launch acceptance'
if ($source -match 'served_lane_a') { throw 'obsolete pre-success lane-A counter remains' }
if ($source -match 'g_cuda_g133_telemetry\.(clamped|request_refused)\s*[,\)]') {
    throw 'clamped/request_refused has a producer; both must remain structural zero'
}

Assert-Contains $source 'g_cuda_routed_moe_launch_dispatch' 'missing init-time routed-MoE dispatch'
Assert-Contains $source '&routed_moe_launch_impl<false>' 'OFF does not select the M1 specialization'
Assert-Contains $source ': cudaStreamSynchronize(0);' `
    'OFF resolver no longer uses its original synchronization'
$routeImpl = Slice-Between $source 'static int routed_moe_launch_impl(' `
    'static auto g_cuda_routed_moe_launch_dispatch'
if ($routeImpl.Contains('g_cuda_g73_open_enabled')) {
    throw 'OFF hot routed-MoE specialization loads g_cuda_g73_open_enabled'
}
$workerImpl = Slice-Between $source 'static void *cuda_moe_route_worker(void *arg) {' `
    'static int cuda_moe_expert_cache_copy_to_compact_async('
if ($workerImpl.Contains('g_cuda_g73_open_enabled')) {
    throw 'OFF route-worker specialization loads g_cuda_g73_open_enabled'
}
Assert-Contains $source 'cuda_g133_attribution_append_enabled' 'missing original OFF attribution formatter'
Assert-Contains $source 'cuda_g73_attribution_append_enabled' 'missing isolated G73 attribution formatter'
Assert-Contains $source 'g_cuda_g133_attribution_append =' 'formatter is not selected at initialization'
Assert-Contains $source 'cuda_g73_validate_hermetic_environment()' 'missing runtime hermetic validation'
Assert-Contains $source 'ds4_gpu_g73_open_selftest(' 'missing real in-process G73 self-test'
Assert-Contains $source 'selftest-stop-after-writer-claim' 'self-test does not exercise teardown versus submit'
Assert-Contains $source 'selftest-teardown-during-committing' `
    'self-test does not exercise teardown during COMMITTING publication'
Assert-Contains $source 'teardown_during_committing=generation-abandon' `
    'self-test does not assert generation-abandon publication'
Assert-Contains $source 'cross_request_rearm=%s' `
    'self-test does not report the cross-request rotator assertion'
Assert-Contains $source 'second-submit-promoted' `
    'self-test does not assert second-request rotator submission and promotion'
Assert-Contains $source 'os_pread_cancellable_timeout(' 'self-test does not exercise real pread timeout/cancel'
Assert-Contains $osFileHeader 'unsigned char opaque[256];' `
    'POSIX cancellable state is not ABI-opaque'
if ($osFileHeader.Contains('_Atomic')) {
    throw 'C/C++ header exposes incompatible atomic object views'
}
if (Test-Path -LiteralPath (Join-Path $root 'tests\test_g73_open_fault_model.ps1')) {
    throw 'fake PowerShell G73 state machine still exists'
}

foreach ($setting in @(
        '$env:DS4_G73_OPEN = ''1''',
        '$env:DS4_CUDA_DYNAMIC_ARENA_GB = ''30''',
        '$env:DS4_CUDA_STREAMING_EXPERT_CACHE_N = ''320''',
        '$env:DS4_CUDA_PREFILL_TIER_ROUTER = ''open''',
        '$env:DS4_EXPERT_TIERING = ''enforce''',
        '$env:DS4_G133_TIER = ''1''',
        '$env:DS4_G130_U1_ATTRIBUTION = ''1''',
        '$env:DS4_CUDA_MOE_SPLIT_FUSED = ''0''')) {
    Assert-Contains $preset $setting "preset missing: $setting"
}
foreach ($q1 in @('DS4_Q1_0_MIXED_COLD_ONE', 'DS4_IQ1_S_MIXED_COLD_K',
        'DS4_Q1_0_SELECTED_LOAD', 'DS4_Q1_0_EXPERT_SIDECAR',
        'DS4_Q1_0_RESIDENT_ARENA', 'DS4_Q1_0_DUAL_ARENA',
        'DS4_Q1_0_DUAL_SPARSE_COMPANION', 'DS4_Q1_0_PAGEABLE_OVERFLOW',
        'DS4_IQ1_PROMOTION_PROBATION_SLOTS')) {
    Assert-Contains $preset "'$q1'" "preset does not disable $q1"
    Assert-Contains $source "`"$q1`"" "runtime validation does not reject $q1"
}
Assert-Contains $preset 'Remove-Item -LiteralPath "Env:$quantServingVar"' 'preset namespace clearing is not data-driven'

Write-Host 'G73-OPEN static contract passed'
