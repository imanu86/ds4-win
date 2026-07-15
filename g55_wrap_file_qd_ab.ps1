# G55 sequential-file file-QD A/B (PowerShell 5.1, ASCII).
param(
    [switch]$SafetyOnly,
    [switch]$Resume,
    [switch]$SummarizeExisting,
    [ValidateRange(2, 64)][int]$CandidateFileQD = 8,
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

function Get-G55SHA256 {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "G55 provenance file missing: $Path"
    }
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-G55Mean {
    param(
        [Parameter(Mandatory=$true)][object[]]$Rows,
        [Parameter(Mandatory=$true)][string]$Property
    )
    $values = @($Rows | ForEach-Object { $_.$Property } |
        Where-Object { $null -ne $_ })
    if ($values.Count -eq 0) { return $null }
    [math]::Round(($values | Measure-Object -Average).Average, 6)
}

function Get-G55Median {
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

function Assert-G55Property {
    param(
        [Parameter(Mandatory=$true)][object]$Object,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Tag
    )
    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) {
        throw "G55 required field missing: tag=$Tag field=$Name"
    }
}

function Get-G55Property {
    param([object]$Object, [string]$Name)
    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) {
        return $null
    }
    $Object.PSObject.Properties[$Name].Value
}

function Convert-G55BytesToGiB {
    param([object]$Value)
    if ($null -eq $Value) { return $null }
    [math]::Round(([double]$Value / 1GB), 6)
}

function Test-G55HarnessParameter {
    param([Parameter(Mandatory=$true)][string]$ParameterName)
    $content = Get-Content -LiteralPath $harness -Raw
    return ($content -match ("\$" + [regex]::Escape($ParameterName) +
        "(\s|=|,|\))"))
}

$provenance = [pscustomobject]@{
    executable_sha256 = Get-G55SHA256 $executable
    harness_sha256 = Get-G55SHA256 $harness
    runtime_monitor_harness_sha256 = Get-G55SHA256 $runtimeMonitor
    ds4_cuda_sha256 = Get-G55SHA256 (Join-Path $root "ds4_cuda.cu")
    ds4_c_sha256 = Get-G55SHA256 (Join-Path $root "ds4.c")
    ds4_server_c_sha256 = Get-G55SHA256 (Join-Path $root "ds4_server.c")
    build_manifest_sha256 = Get-G55SHA256 $buildManifest
}
$executionRunnerHashAtStart = Get-G55SHA256 $MyInvocation.MyCommand.Path
$executionRunnerHashForRuns = if ($SummarizeExisting) {
    $ExecutionRunnerSHA256.ToLowerInvariant()
} else {
    $executionRunnerHashAtStart
}

function Invoke-G55Run {
    param(
        [Parameter(Mandatory=$true)][string]$Tag,
        [Parameter(Mandatory=$true)]
        [ValidateRange(1, 64)]
        [int]$FileQD
    )

    $resultPath = Join-Path $outdir ("g7_" + $Tag + "_result.json")
    $launchProvenancePath = Join-Path $outdir `
        ("g7_" + $Tag + "_g55_launch_provenance.json")
    $args = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $harness,
        "-MaxTokens", "64", "-Repeats", "1", "-Tag", $Tag,
        "-Prompt", $prompt, "-Context", "256",
        "-BudgetGB", "2", "-ReserveMB", "1024",
        "-DynamicArenaGiB", "30", "-ArenaWrapTrustWorkerChecksum",
        "-ArenaWrapSourceParts", "-ArenaWrapSequentialFile",
        "-ArenaWrapSequentialWorkers", "1",
        "-ArenaWrapFileQD", ([string]$FileQD),
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
        Write-Host ("[g55] validate existing tag=" + $Tag +
            " file_qd=" + $FileQD)
    } elseif ($SummarizeExisting) {
        throw "G55 existing result missing: tag=$Tag"
    } else {
        Write-Host ("[g55] start tag=" + $Tag +
            " file_qd=" + $FileQD)
        $launchProvenance = [pscustomobject]@{
            schema = "g55_launch_provenance_v1"
            tag = $Tag
            source = "sequential-file"
            copy_workers = 1
            file_qd = $FileQD
            execution_runner_sha256 = $executionRunnerHashAtStart
            executable_sha256 = $provenance.executable_sha256
            harness_sha256 = $provenance.harness_sha256
            runtime_monitor_harness_sha256 =
                $provenance.runtime_monitor_harness_sha256
            ds4_cuda_sha256 = $provenance.ds4_cuda_sha256
            ds4_c_sha256 = $provenance.ds4_c_sha256
            ds4_server_c_sha256 = $provenance.ds4_server_c_sha256
            build_manifest_sha256 = $provenance.build_manifest_sha256
            prompt = $prompt
            expected_content_sha256 = $expected
            created_utc = [DateTime]::UtcNow.ToString("o")
        }
        $launchProvenance | ConvertTo-Json -Depth 5 |
            Set-Content -LiteralPath $launchProvenancePath -Encoding UTF8
        & powershell.exe @args | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) { throw "G55 run failed: $Tag" }
    }

    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        throw "G55 result missing: tag=$Tag"
    }
    if (-not (Test-Path -LiteralPath $launchProvenancePath -PathType Leaf)) {
        throw "G55 launch provenance missing: tag=$Tag"
    }
    $launch = Get-Content -LiteralPath $launchProvenancePath -Raw |
        ConvertFrom-Json
    if ($launch.schema -ne "g55_launch_provenance_v1" -or
        $launch.tag -ne $Tag -or $launch.source -ne "sequential-file" -or
        [int]$launch.copy_workers -ne 1 -or
        [int]$launch.file_qd -ne $FileQD -or
        $launch.execution_runner_sha256 -ne $executionRunnerHashForRuns -or
        $launch.executable_sha256 -ne $provenance.executable_sha256 -or
        $launch.harness_sha256 -ne $provenance.harness_sha256 -or
        $launch.runtime_monitor_harness_sha256 -ne
            $provenance.runtime_monitor_harness_sha256 -or
        $launch.ds4_cuda_sha256 -ne $provenance.ds4_cuda_sha256 -or
        $launch.ds4_c_sha256 -ne $provenance.ds4_c_sha256 -or
        $launch.ds4_server_c_sha256 -ne $provenance.ds4_server_c_sha256 -or
        $launch.build_manifest_sha256 -ne $provenance.build_manifest_sha256 -or
        $launch.prompt -ne $prompt -or
        $launch.expected_content_sha256 -ne $expected) {
        throw "G55 launch provenance mismatch: tag=$Tag"
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
        "arena_wrap_copy_workers",
        "arena_wrap_random_file_requested",
        "arena_wrap_file_qd_requested",
        "arena_wrap_file_qd_requested_observed",
        "arena_wrap_file_qd_observed",
        "arena_wrap_file_submits",
        "arena_wrap_file_completions",
        "arena_wrap_file_failures",
        "prefill_mass_compose_candidate_fnv1a64",
        "server_exit_code")) {
        Assert-G55Property -Object $r -Name $name -Tag $Tag
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
        [int]$r.server_exit_code -ne 0 -or
        $r.budget_gb -ne 2 -or $r.reserve_mb -ne 1024 -or
        $r.dynamic_arena_gib_requested -ne 30 -or
        -not $r.arena_wrap_trust_worker_checksum_requested -or
        $r.arena_wrap_schedule_observed -ne "source-parts" -or
        $r.arena_wrap_checksum_observed -ne "fnv1a64-worker-only" -or
        [bool]$r.arena_wrap_sequential_file_requested -ne $true -or
        [bool]$r.arena_wrap_random_file_requested -ne $false -or
        $r.arena_wrap_source_requested -ne "sequential-file" -or
        $r.arena_wrap_source_observed -ne "sequential-file" -or
        [int]$r.arena_wrap_sequential_workers_requested -ne 1 -or
        [int]$r.arena_wrap_copy_workers -ne 1 -or
        [int]$r.arena_wrap_file_qd_requested -ne $FileQD -or
        [int]$r.arena_wrap_file_qd_requested_observed -ne $FileQD -or
        [int]$r.arena_wrap_file_qd_observed -ne $FileQD -or
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
        throw "G55 contract mismatch: tag=$Tag"
    }
    if ($FileQD -gt 1 -and
        ([uint64]$r.arena_wrap_file_submits -ne [uint64]$r.arena_wrap_part_count -or
         [uint64]$r.arena_wrap_file_completions -ne [uint64]$r.arena_wrap_part_count -or
         [uint32]$r.arena_wrap_file_failures -ne 0)) {
        throw "G55 file QD counter mismatch: tag=$Tag"
    } elseif ($FileQD -eq 1 -and
        ([uint64]$r.arena_wrap_file_submits -ne 0 -or
         [uint64]$r.arena_wrap_file_completions -ne 0 -or
         [uint32]$r.arena_wrap_file_failures -ne 0)) {
        throw "G55 QD1 legacy counter mismatch: tag=$Tag"
    }

    $wrapSeconds = if ($null -ne $r.arena_wrap_profile_total_seconds) {
        [double]$r.arena_wrap_profile_total_seconds
    } else {
        [double]$r.prefill_mass_wrap_seconds
    }

    [pscustomobject]@{
        tag = $Tag
        arm = ("qd-" + $FileQD)
        file_qd_requested = [int]$FileQD
        file_qd_requested_observed =
            [int]$r.arena_wrap_file_qd_requested_observed
        file_qd_observed = [int]$r.arena_wrap_file_qd_observed
        file_submits = [uint64]$r.arena_wrap_file_submits
        file_completions = [uint64]$r.arena_wrap_file_completions
        file_failures = [uint32]$r.arena_wrap_file_failures
        source_requested = [string]$r.arena_wrap_source_requested
        source_observed = [string]$r.arena_wrap_source_observed
        launch_provenance_path = $launchProvenancePath
        launch_provenance_sha256 = Get-G55SHA256 $launchProvenancePath
        execution_runner_sha256 = [string]$launch.execution_runner_sha256
        sequential_file_requested =
            [bool]$r.arena_wrap_sequential_file_requested
        random_file_requested = [bool]$r.arena_wrap_random_file_requested
        copy_workers = [int]$r.arena_wrap_copy_workers
        sequential_workers_requested =
            [int]$r.arena_wrap_sequential_workers_requested
        arena_wrap_part_count = [uint64]$r.arena_wrap_part_count
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
        server_exit_code = [int]$r.server_exit_code
        build_worktree_dirty = $r.build_manifest_worktree_dirty_at_build_start
        expert_cache_capacity = [int]$r.expert_cache_capacity
        content_sha256 = $r.results[0].content_sha256
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
        ram_h2d_gib = Convert-G55BytesToGiB $tier.ram_h2d_bytes
        route_calls = [uint64]$r.gpu_resident_routes_calls
        route_all_hit_calls = [uint64]$r.gpu_resident_routes_all_hit
        route_vram_routes = [uint64]$r.gpu_resident_routes_vram_routes
        route_pinned_ram_routes =
            [uint64]$r.gpu_resident_routes_pinned_ram_routes
        route_h2d_gib =
            Convert-G55BytesToGiB $r.gpu_resident_routes_h2d_bytes
        route_worker_jobs = [uint64]$r.gpu_resident_routes_worker_jobs
        route_miss_experts = [uint64]$r.gpu_resident_routes_miss_experts
        route_worker_ms_per_job =
            [double]$r.gpu_resident_routes_worker_ms_per_job
        route_wait_ms_per_call =
            [double]$r.gpu_resident_routes_wait_ms_per_call
        route_resolve_ms_per_call =
            [double]$r.gpu_resident_routes_resolve_ms_per_call
        candidate_mask_fnv1a64 =
            [string]$r.prefill_mass_compose_candidate_fnv1a64
        windows_available_min_gib =
            Convert-G55BytesToGiB $rt.windows_available_min_bytes
        working_set_peak_gib =
            Convert-G55BytesToGiB $rt.process_working_set_peak_bytes
        private_peak_gib =
            Convert-G55BytesToGiB $rt.process_private_peak_bytes
        gpu_shared_peak_gib =
            Convert-G55BytesToGiB $rt.gpu_process_shared_peak_bytes
        gpu_dedicated_peak_gib =
            Convert-G55BytesToGiB $rt.gpu_process_dedicated_peak_bytes
        page_fault_delta = Get-G55Property $rt "page_fault_delta"
        process_read_gib =
            Convert-G55BytesToGiB $rt.win32_process_read_transfer_delta_bytes
        process_write_gib =
            Convert-G55BytesToGiB $rt.win32_process_write_transfer_delta_bytes
        process_read_operation_delta =
            Get-G55Property $rt "win32_process_read_operation_delta"
        process_other_operation_delta =
            Get-G55Property $rt "win32_process_other_operation_delta"
        process_read_throughput_mib_per_second =
            Get-G55Property $rt "process_read_throughput_mib_per_second"
        aggregate_disk_read_gib = Convert-G55BytesToGiB `
            (Get-G55Property $rt "aggregate_disk_read_bytes_estimated")
        aggregate_disk_read_mib_per_second =
            Get-G55Property $rt "aggregate_disk_read_mib_per_second"
        aggregate_disk_read_throughput_mib_per_second =
            Get-G55Property $rt "aggregate_disk_read_throughput_mib_per_second"
        aggregate_disk_queue_length =
            Get-G55Property $rt "aggregate_disk_queue_length_median"
        aggregate_disk_queue_length_peak =
            Get-G55Property $rt "aggregate_disk_queue_length_peak"
        mmap_backed_file_io_measured =
            Get-G55Property $rt "mmap_backed_file_io_measured"
        contamination_abort_observed =
            [bool]$rt.contamination_abort_observed
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
    "ArenaWrapSequentialWorkers",
    "ArenaWrapFileQD")) {
    if (-not $SummarizeExisting -and
        -not (Test-G55HarnessParameter -ParameterName $parameter)) {
        throw "Harness does not expose -$parameter; refusing to launch model."
    }
}

$runs = @()
if ($SafetyOnly) {
    $runPlan = @(
        @{ Tag = ("g55_wrap_file_qd_" + $CandidateFileQD + "_safety"); FileQD = $CandidateFileQD }
    )
} else {
    $runPlan = @(
        @{ Tag = "g55_wrap_file_qd_1_a"; FileQD = 1 },
        @{ Tag = ("g55_wrap_file_qd_" + $CandidateFileQD + "_a"); FileQD = $CandidateFileQD },
        @{ Tag = ("g55_wrap_file_qd_" + $CandidateFileQD + "_b"); FileQD = $CandidateFileQD },
        @{ Tag = "g55_wrap_file_qd_1_b"; FileQD = 1 },
        @{ Tag = "g55_wrap_file_qd_1_c"; FileQD = 1 },
        @{ Tag = ("g55_wrap_file_qd_" + $CandidateFileQD + "_c"); FileQD = $CandidateFileQD }
    )
}
foreach ($item in $runPlan) {
    $runs += Invoke-G55Run -Tag $item.Tag -FileQD $item.FileQD
}

$provenanceFields = @(
    "head", "executable_sha256", "ds4_cuda_sha256", "ds4_c_sha256",
    "ds4_server_c_sha256", "build_manifest_sha256",
    "build_input_fingerprint_sha256", "harness_sha256",
    "runtime_monitor_harness_sha256", "model",
    "model_bytes", "model_last_write_utc", "build_worktree_dirty",
    "server_exit_code",
    "expert_cache_capacity", "content_sha256", "copy_workers",
    "sequential_workers_requested", "source_requested", "source_observed",
    "sequential_file_requested", "random_file_requested",
    "execution_runner_sha256", "candidate_mask_fnv1a64"
)
foreach ($field in $provenanceFields) {
    $values = @($runs | ForEach-Object { [string]($_.$field) } |
        Select-Object -Unique)
    if ($values.Count -ne 1) {
        throw "G55 mixed provenance or contract across runs: field=$field"
    }
}
if ([int]$runs[0].expert_cache_capacity -lt 300) {
    throw "G55 effective expert cache capacity below 300"
}
if ([int]$runs[0].copy_workers -ne 1) {
    throw "G55 copy_workers contract mismatch"
}

$armSummary = @()
foreach ($fileQD in @(1, $CandidateFileQD)) {
    $rows = @($runs | Where-Object { $_.file_qd_requested -eq $fileQD })
    $expectedRows = if ($SafetyOnly -and $fileQD -eq $CandidateFileQD) { 1 } elseif ($SafetyOnly) { 0 } else { 3 }
    if ($rows.Count -ne $expectedRows) {
        throw "G55 replication mismatch: file_qd=$fileQD"
    }
    if ($rows.Count -eq 0) { continue }
    $requested = @($rows | ForEach-Object { $_.file_qd_requested_observed } |
        Select-Object -Unique)
    $observed = @($rows | ForEach-Object { $_.file_qd_observed } |
        Select-Object -Unique)
    if ($requested.Count -ne 1 -or [int]$requested[0] -ne $fileQD -or
        $observed.Count -ne 1 -or [int]$observed[0] -ne $fileQD) {
        throw "G55 file QD mismatch in summary: file_qd=$fileQD"
    }
    $armSummary += [pscustomobject]@{
        arm = ("qd-" + $fileQD)
        file_qd_requested = $fileQD
        file_qd_requested_observed = [int]$requested[0]
        file_qd_observed = [int]$observed[0]
        copy_workers = 1
        independent_processes = $rows.Count
        file_submits_sum =
            ($rows | Measure-Object -Property file_submits -Sum).Sum
        file_completions_sum =
            ($rows | Measure-Object -Property file_completions -Sum).Sum
        file_failures_sum =
            ($rows | Measure-Object -Property file_failures -Sum).Sum
        ttft_mean_seconds = Get-G55Mean $rows "ttft_seconds"
        ttft_median_seconds = Get-G55Median $rows "ttft_seconds"
        wrap_seconds_mean = Get-G55Mean $rows "wrap_seconds"
        wrap_seconds_median = Get-G55Median $rows "wrap_seconds"
        wrap_copy_seconds_mean = Get-G55Mean $rows "wrap_copy_seconds"
        wrap_copy_seconds_median = Get-G55Median $rows "wrap_copy_seconds"
        wrap_checksum_seconds_mean =
            Get-G55Mean $rows "wrap_checksum_seconds"
        decode_tokens_per_second_mean =
            Get-G55Mean $rows "decode_tokens_per_second"
        decode_tokens_per_second_median =
            Get-G55Median $rows "decode_tokens_per_second"
        decode_seconds_mean = Get-G55Mean $rows "decode_seconds"
        windows_available_min_gib_mean =
            Get-G55Mean $rows "windows_available_min_gib"
        working_set_peak_gib_mean =
            Get-G55Mean $rows "working_set_peak_gib"
        private_peak_gib_mean = Get-G55Mean $rows "private_peak_gib"
        gpu_shared_peak_gib_mean =
            Get-G55Mean $rows "gpu_shared_peak_gib"
        process_read_gib_mean = Get-G55Mean $rows "process_read_gib"
        process_write_gib_mean = Get-G55Mean $rows "process_write_gib"
        page_fault_delta_mean = Get-G55Mean $rows "page_fault_delta"
        aggregate_disk_read_gib_mean =
            Get-G55Mean $rows "aggregate_disk_read_gib"
        aggregate_disk_read_mib_per_second_mean =
            Get-G55Mean $rows "aggregate_disk_read_mib_per_second"
        aggregate_disk_read_throughput_mib_per_second_mean =
            Get-G55Mean $rows "aggregate_disk_read_throughput_mib_per_second"
        aggregate_disk_queue_length_peak_mean =
            Get-G55Mean $rows "aggregate_disk_queue_length_peak"
        contamination_abort_observed_count =
            @($rows | Where-Object { $_.contamination_abort_observed }).Count
        snapshot_misses_sum =
            ($rows | Measure-Object -Property snapshot_misses -Sum).Sum
        ssd_bytes_sum = ($rows | Measure-Object -Property ssd_bytes -Sum).Sum
        failures_sum = ($rows | Measure-Object -Property failures -Sum).Sum
    }
}

$summary = [pscustomobject]@{
    schema = "g55_wrap_file_qd_ab_v1"
    question = "Does sequential-file file QD greater than 1 improve arena WRAP over QD1 on the exact G45 cyberpunk prompt and config?"
    prompt = $prompt
    context = 256
    max_tokens = 64
    arena_gib = 30
    cache_experts = 320
    cache_reserve_gib = 0.125
    expected_content_sha256 = $expected
    safety_only = [bool]$SafetyOnly
    independent_processes_per_arm = if ($SafetyOnly) { 1 } else { 3 }
    within_process_repeats = 1
    system_file_cache_flushed_between_runs = $false
    order_contract = if ($SafetyOnly) {
        "safety-only candidate n=1; sequential-file/source-parts/workers1/trusted checksum; interpret cold-start TTFT separately from decode and within-process memory telemetry"
    } else {
        "counterbalanced QD order 1,candidate,candidate,1,1,candidate; sequential-file/source-parts/workers1/trusted checksum; interpret cold-start TTFT separately from decode and within-process memory telemetry"
    }
    order = @($runs | ForEach-Object { $_.tag })
    order_file_qd = @($runs | ForEach-Object { $_.file_qd_requested })
    control_file_qd = 1
    candidate_file_qd = $CandidateFileQD
    source = "sequential-file"
    copy_workers = 1
    sequential_workers = 1
    route_no_default_sync = $true
    q8_f16_cache = "disabled"
    excluded_features = @(
        "split-hit-miss", "SPEX", "static-mask", "trim", "diagnostics",
        "arena-wrap-part-profile")
    summarized_existing_results = [bool]$SummarizeExisting
    execution_runner_sha256 = $executionRunnerHashForRuns
    summary_runner_sha256 = Get-G55SHA256 $MyInvocation.MyCommand.Path
    launch_time_provenance = [pscustomobject]@{
        execution_runner_sha256_for_runs = $executionRunnerHashForRuns
        summary_runner_sha256_at_start = $executionRunnerHashAtStart
        executable_sha256 = $provenance.executable_sha256
        harness_sha256 = $provenance.harness_sha256
        runtime_monitor_harness_sha256 =
            $provenance.runtime_monitor_harness_sha256
        ds4_cuda_sha256 = $provenance.ds4_cuda_sha256
        ds4_c_sha256 = $provenance.ds4_c_sha256
        ds4_server_c_sha256 = $provenance.ds4_server_c_sha256
        build_manifest_sha256 = $provenance.build_manifest_sha256
    }
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
        copy_workers = $runs[0].copy_workers
        sequential_workers = $runs[0].sequential_workers_requested
        source_requested = $runs[0].source_requested
        source_observed = $runs[0].source_observed
    }
    runs = $runs
    arm_summary = $armSummary
}

$summaryPath = Join-Path $outdir "g55_wrap_file_qd_ab_result.json"
$summary | ConvertTo-Json -Depth 10 |
    Set-Content -LiteralPath $summaryPath -Encoding UTF8
foreach ($arm in $armSummary) {
    Write-Host ("[g55] arm=" + $arm.arm +
        " n=" + $arm.independent_processes +
        " wrap_med=" + $arm.wrap_seconds_median +
        " ttft_med=" + $arm.ttft_median_seconds +
        " decode_tps_med=" + $arm.decode_tokens_per_second_median +
        " disk_read_gib_mean=" + $arm.aggregate_disk_read_gib_mean +
        " disk_q_peak_mean=" + $arm.aggregate_disk_queue_length_peak_mean +
        " file_submits=" + $arm.file_submits_sum +
        " file_completions=" + $arm.file_completions_sum +
        " file_failures=" + $arm.file_failures_sum)
}
Write-Host ("[g55] matrix complete: " + $summaryPath)
