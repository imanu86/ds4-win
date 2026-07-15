# G53 sequential-file WRAP worker-count A/B (PowerShell 5.1, ASCII).
param(
    [switch]$Resume,
    [switch]$SummarizeExisting,
    [string]$ExecutionRunnerSHA256 = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$harness = Join-Path $root "g7_measure.ps1"
$runtimeMonitor = Join-Path $root "g7_runtime_monitor.ps1"
$outdir = Join-Path $root "g7_runs"
$model = "C:\ds4-models\ds4-2bit.gguf"
$prompt = "Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document."
$expected = "31cbc6504dcb57d42aeff9dbceb3aed943bcb32dae19a2edbf552e9fd2f52eb8"
$executable = Join-Path $root "build\Release\ds4_server.exe"
$buildManifest = Join-Path $root "build\Release\g7_build_manifest.json"

function Get-G53SHA256 {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "G53 provenance file missing: $Path"
    }
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-G53Mean {
    param(
        [Parameter(Mandatory=$true)][object[]]$Rows,
        [Parameter(Mandatory=$true)][string]$Property
    )
    $values = @($Rows | ForEach-Object { $_.$Property } |
        Where-Object { $null -ne $_ })
    if ($values.Count -eq 0) { return $null }
    [math]::Round(($values | Measure-Object -Average).Average, 6)
}

function Get-G53Median {
    param(
        [Parameter(Mandatory=$true)][object[]]$Rows,
        [Parameter(Mandatory=$true)][string]$Property
    )
    $values = @($Rows | ForEach-Object { $_.$Property } |
        Where-Object { $null -ne $_ } |
        ForEach-Object { [double]$_ } | Sort-Object)
    if ($values.Count -eq 0) { return $null }
    $middle = [int][math]::Floor($values.Count / 2.0)
    if (($values.Count % 2) -eq 1) {
        return [math]::Round($values[$middle], 6)
    }
    [math]::Round(($values[$middle - 1] + $values[$middle]) / 2.0, 6)
}

function Assert-G53Property {
    param(
        [Parameter(Mandatory=$true)][object]$Object,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Tag
    )
    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) {
        throw "G53 required field missing: tag=$Tag field=$Name"
    }
}

function Get-G53Property {
    param([object]$Object, [string]$Name)
    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) {
        return $null
    }
    $Object.PSObject.Properties[$Name].Value
}

function Convert-G53BytesToGiB {
    param([object]$Value)
    if ($null -eq $Value) { return $null }
    [math]::Round(([double]$Value / 1GB), 6)
}

function Test-G53HarnessParameter {
    param([Parameter(Mandatory=$true)][string]$ParameterName)
    $content = Get-Content -LiteralPath $harness -Raw
    return ($content -match ("\$" + [regex]::Escape($ParameterName) +
        "(\s|=|,|\))"))
}

$provenance = [pscustomobject]@{
    executable_sha256 = Get-G53SHA256 $executable
    harness_sha256 = Get-G53SHA256 $harness
    runtime_monitor_harness_sha256 = Get-G53SHA256 $runtimeMonitor
    ds4_cuda_sha256 = Get-G53SHA256 (Join-Path $root "ds4_cuda.cu")
    ds4_c_sha256 = Get-G53SHA256 (Join-Path $root "ds4.c")
    ds4_server_c_sha256 = Get-G53SHA256 (Join-Path $root "ds4_server.c")
    build_manifest_sha256 = Get-G53SHA256 $buildManifest
}
$executionRunnerHashAtStart = Get-G53SHA256 $MyInvocation.MyCommand.Path

function Invoke-G53Run {
    param(
        [Parameter(Mandatory=$true)][string]$Tag,
        [Parameter(Mandatory=$true)]
        [ValidateSet(1, 4)]
        [int]$Workers
    )

    $resultPath = Join-Path $outdir ("g7_" + $Tag + "_result.json")
    $args = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $harness,
        "-MaxTokens", "64", "-Repeats", "1", "-Tag", $Tag,
        "-Prompt", $prompt, "-Context", "256",
        "-BudgetGB", "2", "-ReserveMB", "1024",
        "-DynamicArenaGiB", "30", "-ArenaWrapTrustWorkerChecksum",
        "-ArenaWrapSourceParts", "-ArenaWrapSequentialFile",
        "-ArenaWrapSequentialWorkers", ([string]$Workers),
        "-DisableQ8F16Cache", "-EmbedRowStaging",
        "-ReapPrefetchThreads", "8", "-ExpectedContentSHA256", $expected,
        "-ModelPath", $model, "-TimeoutSec", "1200",
        "-PrefillMassWrap", "-ComposePrefillMassTiering",
        "-ExpertCacheN", "320", "-ExpertCacheReserveGB", "0.125",
        "-ExpertCachePolicy", "lru", "-GpuResidentRoutes",
        "-RouteNoDefaultSync",
        "-ExpertTiering", "enforce", "-ExpertTierPolicy", "mass-lfru",
        "-ExpertTierClockCalls", "430",
        "-ExpertTierReplacementBudget", "16",
        "-ExpertTierMinFrequency", "3",
        "-ExpertTierHysteresis", "1.25"
    )

    if (($Resume -or $SummarizeExisting) -and
        (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        Write-Host ("[g53] validate existing tag=" + $Tag +
            " workers=" + $Workers)
    } elseif ($SummarizeExisting) {
        throw "G53 existing result missing: tag=$Tag"
    } else {
        Write-Host ("[g53] start tag=" + $Tag + " workers=" + $Workers)
        & powershell.exe @args | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) { throw "G53 run failed: $Tag" }
    }

    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        throw "G53 result missing: tag=$Tag"
    }
    $r = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    $tier = $r.expert_tiering
    $mem = $r.memory_preflight
    $proc = $r.process_isolation_preflight
    $sys = $r.system_quiescence_preflight
    $rt = $r.runtime_telemetry

    foreach ($name in @(
        "arena_wrap_source_requested",
        "arena_wrap_source_observed",
        "arena_wrap_sequential_workers_requested",
        "arena_wrap_copy_workers")) {
        Assert-G53Property -Object $r -Name $name -Tag $Tag
    }

    if ($r.tag -ne $Tag -or $r.prompt -ne $prompt -or
        $r.model -ne $model -or $r.repeats -ne 1 -or $r.warmup -or
        $r.requested_max_tokens -ne 64 -or $r.context_requested -ne 256 -or
        $r.executable_sha256 -ne $provenance.executable_sha256 -or
        $r.harness_sha256 -ne $provenance.harness_sha256 -or
        $r.runtime_monitor_harness_sha256 -ne
            $provenance.runtime_monitor_harness_sha256 -or
        $r.ds4_cuda_sha256 -ne $provenance.ds4_cuda_sha256 -or
        $r.ds4_c_sha256 -ne $provenance.ds4_c_sha256 -or
        $r.ds4_server_c_sha256 -ne $provenance.ds4_server_c_sha256 -or
        $r.build_manifest_sha256 -ne $provenance.build_manifest_sha256 -or
        -not $r.outputs_identical -or
        $r.expected_content_sha256 -ne $expected -or
        $r.results.Count -ne 1 -or
        $r.results[0].content_sha256 -ne $expected -or
        $r.budget_gb -ne 2 -or $r.reserve_mb -ne 1024 -or
        $r.dynamic_arena_gib_requested -ne 30 -or
        -not $r.arena_wrap_trust_worker_checksum_requested -or
        $r.arena_wrap_schedule_observed -ne "source-parts" -or
        $r.arena_wrap_checksum_observed -ne "fnv1a64-worker-only" -or
        [bool]$r.arena_wrap_sequential_file_requested -ne $true -or
        $r.arena_wrap_source_requested -ne "sequential-file" -or
        $r.arena_wrap_source_observed -ne "sequential-file" -or
        [int]$r.arena_wrap_sequential_workers_requested -ne $Workers -or
        [int]$r.arena_wrap_copy_workers -ne $Workers -or
        -not $r.prefill_mass_wrap_requested -or
        -not $r.prefill_mass_wrap_observed -or
        $r.prefill_mass_wrap_result -ne "published" -or
        $r.prefill_mass_wrap_reason -ne "ok" -or
        $r.prefill_mass_wrap_mask -ne "request-scoped-closed" -or
        -not $r.compose_prefill_mass_tiering_requested -or
        -not $tier.compose_prefill_mass_tiering_observed -or
        -not $r.gpu_resident_routes_requested -or
        -not $r.gpu_resident_routes_observed -or
        -not $r.route_no_default_sync_requested -or
        $r.gpu_resident_routes_default_sync_calls -ne 0 -or
        $r.gpu_resident_routes_no_default_sync_calls -ne
            $r.gpu_resident_routes_calls -or
        $r.gpu_resident_routes_errors -ne 0 -or
        $r.split_hit_miss_requested -or
        $r.spex_dry_run_requested -or
        $r.spex_observed -or
        $r.q8_f16_cache_disabled -ne $true -or
        $r.diagnostics -or
        $r.arena_wrap_trim_between_phases_requested -or
        $r.arena_wrap_trim_observed -or
        $r.arena_wrap_part_profile_requested -or
        $r.arena_wrap_part_profile_observed -or
        $r.expert_cache_requested -ne 320 -or
        $r.expert_cache_capacity -lt 300 -or
        $r.expert_cache_capacity -gt 320 -or
        $r.expert_cache_reserve_gb -ne 0.125 -or
        $r.expert_cache_policy -ne "lru" -or
        $r.expert_tiering_requested -ne "enforce" -or
        $r.expert_tier_policy_requested -ne "mass-lfru" -or
        $r.expert_tier_clock_calls_requested -ne 430 -or
        $r.expert_tier_replacement_budget_requested -ne 16 -or
        $r.expert_tier_min_frequency_requested -ne 3 -or
        $r.expert_tier_hysteresis_requested -ne 1.25 -or
        $tier.mode -ne "enforce" -or
        $tier.policy -ne "mass-lfru" -or
        $tier.clock_calls -ne 430 -or
        $tier.replacement_budget -ne 16 -or
        $tier.min_frequency -ne 3 -or
        $tier.hysteresis -ne 1.25 -or
        $tier.states_vram -ne $r.expert_cache_capacity -or
        $tier.snapshot_backing_misses -ne 0 -or
        $tier.ssd_bytes -ne 0 -or
        $tier.failures -ne 0 -or
        $tier.forbidden_cold_ssd_to_vram -ne 0 -or
        $mem.ready_to_launch -ne $true -or
        $proc.ready_to_launch -ne $true -or
        $sys.ready_to_launch -ne $true -or
        $rt.contamination_abort_observed -ne $false -or
        $rt.contamination_runtime_minimum_available_gib -ne 2 -or
        $rt.contamination_runtime_maximum_disk_queue_length -ne 8 -or
        $rt.contamination_runtime_consecutive_samples -ne 3 -or
        $null -eq $rt.aggregate_disk_queue_length_peak -or
        $null -eq $rt.aggregate_disk_read_bytes_estimated) {
        throw "G53 contract mismatch: tag=$Tag"
    }

    $wrapSeconds = if ($null -ne $r.arena_wrap_profile_total_seconds) {
        [double]$r.arena_wrap_profile_total_seconds
    } else {
        [double]$r.prefill_mass_wrap_seconds
    }

    [pscustomobject]@{
        tag = $Tag
        arm = ("workers-" + $Workers)
        workers_requested = [int]$Workers
        workers_observed = [int]$r.arena_wrap_copy_workers
        result_path = $resultPath
        head = $r.head
        executable_sha256 = $r.executable_sha256
        ds4_cuda_sha256 = $r.ds4_cuda_sha256
        ds4_c_sha256 = $r.ds4_c_sha256
        ds4_server_c_sha256 = $r.ds4_server_c_sha256
        build_manifest_sha256 = $r.build_manifest_sha256
        build_input_fingerprint_sha256 =
            $r.build_manifest_input_fingerprint_sha256
        harness_sha256 = $r.harness_sha256
        runtime_monitor_harness_sha256 = $r.runtime_monitor_harness_sha256
        model = $r.model
        model_bytes = $r.model_bytes
        model_last_write_utc = $r.model_last_write_utc
        build_worktree_dirty = $r.build_manifest_worktree_dirty_at_build_start
        expert_cache_capacity = [int]$r.expert_cache_capacity
        content_sha256 = $r.results[0].content_sha256
        source_requested = [string]$r.arena_wrap_source_requested
        source_observed = [string]$r.arena_wrap_source_observed
        sequential_file_requested =
            [bool]$r.arena_wrap_sequential_file_requested
        ttft_seconds = [double]$r.server_prefill_ttft_mean_seconds
        wrap_seconds = $wrapSeconds
        wrap_copy_seconds =
            if ($null -ne $r.arena_wrap_source_parts_copy_seconds) {
                [double]$r.arena_wrap_source_parts_copy_seconds
            } else { $null }
        wrap_checksum_seconds =
            if ($null -ne $r.arena_wrap_source_parts_checksum_seconds) {
                [double]$r.arena_wrap_source_parts_checksum_seconds
            } else { $null }
        decode_tokens_per_second =
            [double]$r.server_decode_mean_tokens_per_second
        decode_seconds = [double]$r.server_runs[0].server_decode_seconds
        vram_hits = [uint64]$tier.vram_hits
        ram_hits = [uint64]$tier.ram_hits
        ram_h2d_gib = Convert-G53BytesToGiB $tier.ram_h2d_bytes
        route_calls = [uint64]$r.gpu_resident_routes_calls
        route_all_hit_calls = [uint64]$r.gpu_resident_routes_all_hit
        route_vram_routes = [uint64]$r.gpu_resident_routes_vram_routes
        route_pinned_ram_routes =
            [uint64]$r.gpu_resident_routes_pinned_ram_routes
        route_h2d_gib =
            Convert-G53BytesToGiB $r.gpu_resident_routes_h2d_bytes
        route_worker_jobs = [uint64]$r.gpu_resident_routes_worker_jobs
        route_miss_experts = [uint64]$r.gpu_resident_routes_miss_experts
        route_worker_ms_per_job =
            [double]$r.gpu_resident_routes_worker_ms_per_job
        route_wait_ms_per_call =
            [double]$r.gpu_resident_routes_wait_ms_per_call
        route_resolve_ms_per_call =
            [double]$r.gpu_resident_routes_resolve_ms_per_call
        windows_available_min_gib =
            Convert-G53BytesToGiB $rt.windows_available_min_bytes
        working_set_peak_gib =
            Convert-G53BytesToGiB $rt.process_working_set_peak_bytes
        private_peak_gib =
            Convert-G53BytesToGiB $rt.process_private_peak_bytes
        gpu_shared_peak_gib =
            Convert-G53BytesToGiB $rt.gpu_process_shared_peak_bytes
        gpu_dedicated_peak_gib =
            Convert-G53BytesToGiB $rt.gpu_process_dedicated_peak_bytes
        page_fault_delta = Get-G53Property $rt "page_fault_delta"
        process_read_gib =
            Convert-G53BytesToGiB $rt.win32_process_read_transfer_delta_bytes
        process_write_gib =
            Convert-G53BytesToGiB $rt.win32_process_write_transfer_delta_bytes
        process_read_operation_delta =
            Get-G53Property $rt "win32_process_read_operation_delta"
        process_other_operation_delta =
            Get-G53Property $rt "win32_process_other_operation_delta"
        process_read_throughput_mib_per_second =
            Get-G53Property $rt "process_read_throughput_mib_per_second"
        aggregate_disk_read_gib = Convert-G53BytesToGiB `
            (Get-G53Property $rt "aggregate_disk_read_bytes_estimated")
        aggregate_disk_read_mib_per_second =
            Get-G53Property $rt "aggregate_disk_read_mib_per_second"
        aggregate_disk_read_throughput_mib_per_second =
            Get-G53Property $rt "aggregate_disk_read_throughput_mib_per_second"
        aggregate_disk_queue_length =
            Get-G53Property $rt "aggregate_disk_queue_length_median"
        aggregate_disk_queue_length_peak =
            Get-G53Property $rt "aggregate_disk_queue_length_peak"
        mmap_backed_file_io_measured =
            Get-G53Property $rt "mmap_backed_file_io_measured"
        snapshot_misses = [uint64]$tier.snapshot_backing_misses
        ssd_bytes = [uint64]$tier.ssd_bytes
        failures = [uint64]$tier.failures
        memory_preflight_ready = [bool]$mem.ready_to_launch
        process_preflight_ready = [bool]$proc.ready_to_launch
        system_preflight_ready = [bool]$sys.ready_to_launch
    }
}

New-Item -ItemType Directory -Force -Path $outdir | Out-Null
if ($SummarizeExisting -and
    $ExecutionRunnerSHA256 -notmatch '^[0-9a-fA-F]{64}$') {
    throw "SummarizeExisting requires -ExecutionRunnerSHA256"
}
foreach ($parameter in @(
    "ArenaWrapSequentialFile",
    "ArenaWrapSequentialWorkers")) {
    if (-not $SummarizeExisting -and
        -not (Test-G53HarnessParameter -ParameterName $parameter)) {
        throw "Harness does not expose -$parameter; refusing to launch model."
    }
}

$runs = @()
$runPlan = @(
    @{ Tag = "g53_wrap_seq_workers_4_a"; Workers = 4 },
    @{ Tag = "g53_wrap_seq_workers_1_a"; Workers = 1 },
    @{ Tag = "g53_wrap_seq_workers_1_b"; Workers = 1 },
    @{ Tag = "g53_wrap_seq_workers_4_b"; Workers = 4 },
    @{ Tag = "g53_wrap_seq_workers_4_c"; Workers = 4 },
    @{ Tag = "g53_wrap_seq_workers_1_c"; Workers = 1 }
)
foreach ($item in $runPlan) {
    $runs += Invoke-G53Run -Tag $item.Tag -Workers $item.Workers
}

$provenanceFields = @(
    "head", "executable_sha256", "ds4_cuda_sha256", "ds4_c_sha256",
    "ds4_server_c_sha256", "build_manifest_sha256",
    "build_input_fingerprint_sha256", "harness_sha256",
    "runtime_monitor_harness_sha256", "model",
    "model_bytes", "model_last_write_utc", "build_worktree_dirty",
    "expert_cache_capacity", "content_sha256", "source_requested",
    "source_observed", "sequential_file_requested"
)
foreach ($field in $provenanceFields) {
    $values = @($runs | ForEach-Object { [string]($_.$field) } |
        Select-Object -Unique)
    if ($values.Count -ne 1) {
        throw "G53 mixed provenance or contract across runs: field=$field"
    }
}
if ([int]$runs[0].expert_cache_capacity -lt 300) {
    throw "G53 effective expert cache capacity below 300"
}

$armSummary = @()
foreach ($workers in @(1, 4)) {
    $rows = @($runs | Where-Object { $_.workers_requested -eq $workers })
    if ($rows.Count -ne 3) {
        throw "G53 replication mismatch: workers=$workers"
    }
    $observed = @($rows | ForEach-Object { $_.workers_observed } |
        Select-Object -Unique)
    if ($observed.Count -ne 1 -or [int]$observed[0] -ne $workers) {
        throw "G53 observed worker mismatch in summary: workers=$workers"
    }
    $armSummary += [pscustomobject]@{
        arm = ("workers-" + $workers)
        sequential_workers_requested = $workers
        sequential_workers_observed = [int]$observed[0]
        independent_processes = $rows.Count
        ttft_mean_seconds = Get-G53Mean $rows "ttft_seconds"
        ttft_median_seconds = Get-G53Median $rows "ttft_seconds"
        wrap_seconds_mean = Get-G53Mean $rows "wrap_seconds"
        wrap_seconds_median = Get-G53Median $rows "wrap_seconds"
        wrap_copy_seconds_mean = Get-G53Mean $rows "wrap_copy_seconds"
        wrap_copy_seconds_median = Get-G53Median $rows "wrap_copy_seconds"
        decode_tokens_per_second_mean =
            Get-G53Mean $rows "decode_tokens_per_second"
        decode_tokens_per_second_median =
            Get-G53Median $rows "decode_tokens_per_second"
        decode_seconds_mean = Get-G53Mean $rows "decode_seconds"
        windows_available_min_gib_mean =
            Get-G53Mean $rows "windows_available_min_gib"
        working_set_peak_gib_mean =
            Get-G53Mean $rows "working_set_peak_gib"
        private_peak_gib_mean = Get-G53Mean $rows "private_peak_gib"
        gpu_shared_peak_gib_mean =
            Get-G53Mean $rows "gpu_shared_peak_gib"
        process_read_gib_mean = Get-G53Mean $rows "process_read_gib"
        process_write_gib_mean = Get-G53Mean $rows "process_write_gib"
        page_fault_delta_mean = Get-G53Mean $rows "page_fault_delta"
        aggregate_disk_read_gib_mean =
            Get-G53Mean $rows "aggregate_disk_read_gib"
        aggregate_disk_read_mib_per_second_mean =
            Get-G53Mean $rows "aggregate_disk_read_mib_per_second"
        aggregate_disk_read_throughput_mib_per_second_mean =
            Get-G53Mean $rows "aggregate_disk_read_throughput_mib_per_second"
        aggregate_disk_queue_length_peak_mean =
            Get-G53Mean $rows "aggregate_disk_queue_length_peak"
        snapshot_misses_sum =
            ($rows | Measure-Object -Property snapshot_misses -Sum).Sum
        ssd_bytes_sum = ($rows | Measure-Object -Property ssd_bytes -Sum).Sum
        failures_sum = ($rows | Measure-Object -Property failures -Sum).Sum
    }
}

$summary = [pscustomobject]@{
    schema = "g53_wrap_sequential_workers_ab_v1"
    question = "Arena WRAP sequential-file copy workers 1 versus 4 on the exact G45 cyberpunk prompt and config."
    prompt = $prompt
    context = 256
    max_tokens = 64
    arena_gib = 30
    cache_experts = 320
    cache_reserve_gib = 0.125
    expected_content_sha256 = $expected
    independent_processes_per_arm = 3
    within_process_repeats = 1
    system_file_cache_flushed_between_runs = $false
    order_contract = "counterbalanced workers 4,1,1,4,4,1; ArenaWrapSequentialFile enabled in both arms; interpret cold-start TTFT separately from decode and within-process memory telemetry"
    order = @($runs | ForEach-Object { $_.tag })
    order_workers = @($runs | ForEach-Object { $_.workers_requested })
    control_workers = 1
    candidate_workers = 4
    source = "sequential-file"
    route_no_default_sync = $true
    q8_f16_cache = "disabled"
    excluded_features = @(
        "split-hit-miss", "SPEX", "static-mask", "trim", "diagnostics",
        "arena-wrap-part-profile")
    summarized_existing_results = [bool]$SummarizeExisting
    execution_runner_sha256 = if ($SummarizeExisting) {
        $ExecutionRunnerSHA256.ToLowerInvariant()
    } else {
        $executionRunnerHashAtStart
    }
    summary_runner_sha256 = Get-G53SHA256 $MyInvocation.MyCommand.Path
    provenance = [pscustomobject]@{
        head = $runs[0].head
        executable_sha256 = $runs[0].executable_sha256
        ds4_cuda_sha256 = $runs[0].ds4_cuda_sha256
        ds4_c_sha256 = $runs[0].ds4_c_sha256
        ds4_server_c_sha256 = $runs[0].ds4_server_c_sha256
        build_manifest_sha256 = $runs[0].build_manifest_sha256
        build_input_fingerprint_sha256 =
            $runs[0].build_input_fingerprint_sha256
        harness_sha256 = $runs[0].harness_sha256
        runtime_monitor_harness_sha256 =
            $runs[0].runtime_monitor_harness_sha256
        model = $runs[0].model
        model_bytes = $runs[0].model_bytes
        model_last_write_utc = $runs[0].model_last_write_utc
        build_worktree_dirty = $runs[0].build_worktree_dirty
        effective_expert_cache_capacity = $runs[0].expert_cache_capacity
    }
    runs = $runs
    arm_summary = $armSummary
}

$summaryPath = Join-Path $outdir "g53_wrap_sequential_workers_ab_result.json"
$summary | ConvertTo-Json -Depth 10 |
    Set-Content -LiteralPath $summaryPath -Encoding UTF8
Write-Host ("[g53] matrix complete: " + $summaryPath)
