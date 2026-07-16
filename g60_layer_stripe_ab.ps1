# G60 layer-stripe A/B runner (PowerShell 5.1, ASCII).
param(
    [switch]$SafetyOnly,
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
$controlExpected = "31cbc6504dcb57d42aeff9dbceb3aed943bcb32dae19a2edbf552e9fd2f52eb8"
$executable = Join-Path $root "build\Release\ds4_server.exe"
$buildManifest = Join-Path $root "build\Release\g7_build_manifest.json"
$fileQD = 8

function Get-G60SHA256 {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "G60 provenance file missing: $Path"
    }
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-G60Mean {
    param(
        [Parameter(Mandatory=$true)][object[]]$Rows,
        [Parameter(Mandatory=$true)][string]$Property
    )
    $values = @($Rows | ForEach-Object { $_.$Property } |
        Where-Object { $null -ne $_ } | ForEach-Object { [double]$_ })
    if ($values.Count -eq 0) { return $null }
    [math]::Round(($values | Measure-Object -Average).Average, 6)
}

function Get-G60Median {
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

function Get-G60DeltaPercent {
    param([object]$Control, [object]$Stripe)
    if ($null -eq $Control -or $null -eq $Stripe) { return $null }
    if ([double]$Control -eq 0.0) { return $null }
    [math]::Round((([double]$Stripe - [double]$Control) /
        [double]$Control) * 100.0, 6)
}

function Assert-G60Property {
    param(
        [Parameter(Mandatory=$true)][object]$Object,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Tag
    )
    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) {
        throw "G60 required field missing: tag=$Tag field=$Name"
    }
}

function Get-G60Property {
    param([object]$Object, [string]$Name)
    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) {
        return $null
    }
    $Object.PSObject.Properties[$Name].Value
}

function Convert-G60BytesToGiB {
    param([object]$Value)
    if ($null -eq $Value) { return $null }
    [math]::Round(([double]$Value / 1GB), 6)
}

function Test-G60HarnessParameter {
    param([Parameter(Mandatory=$true)][string]$ParameterName)
    $content = Get-Content -LiteralPath $harness -Raw
    return ($content -match ("\$" + [regex]::Escape($ParameterName) +
        "(\s|=|,|\))"))
}

$provenance = [pscustomobject]@{
    executable_sha256 = Get-G60SHA256 $executable
    harness_sha256 = Get-G60SHA256 $harness
    runtime_monitor_harness_sha256 = Get-G60SHA256 $runtimeMonitor
    ds4_cuda_sha256 = Get-G60SHA256 (Join-Path $root "ds4_cuda.cu")
    ds4_c_sha256 = Get-G60SHA256 (Join-Path $root "ds4.c")
    ds4_server_c_sha256 = Get-G60SHA256 (Join-Path $root "ds4_server.c")
    build_manifest_sha256 = Get-G60SHA256 $buildManifest
}
$executionRunnerHashAtStart = Get-G60SHA256 $MyInvocation.MyCommand.Path
$executionRunnerHashForRuns = if ($SummarizeExisting) {
    $ExecutionRunnerSHA256.ToLowerInvariant()
} else {
    $executionRunnerHashAtStart
}

function Invoke-G60Run {
    param(
        [Parameter(Mandatory=$true)][string]$Tag,
        [Parameter(Mandatory=$true)]
        [ValidateSet("control", "stripe")]
        [string]$Arm
    )

    $isStripe = ($Arm -eq "stripe")
    $resultPath = Join-Path $outdir ("g7_" + $Tag + "_result.json")
    $launchProvenancePath = Join-Path $outdir `
        ("g7_" + $Tag + "_g60_launch_provenance.json")
    $args = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $harness,
        "-MaxTokens", "64", "-Repeats", "1", "-Tag", $Tag,
        "-Prompt", $prompt, "-Context", "256",
        "-BudgetGB", "2", "-ReserveMB", "1024",
        "-DynamicArenaGiB", "30", "-ArenaWrapTrustWorkerChecksum",
        "-ArenaWrapSourceParts", "-ArenaWrapSequentialFile",
        "-ArenaWrapSequentialWorkers", "1",
        "-ArenaWrapFileQD", ([string]$fileQD),
        "-DisableQ8F16Cache", "-EmbedRowStaging",
        "-ReapPrefetchThreads", "8",
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
    if ($isStripe) {
        $args += @("-PrefillMassLayerFullEvery", "5",
            "-PrefillMassLayerFullPhase", "0")
    } else {
        $args += @("-ExpectedContentSHA256", $controlExpected)
    }

    if (($Resume -or $SummarizeExisting) -and
        (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        Write-Host ("[g60] validate existing tag=" + $Tag +
            " arm=" + $Arm)
    } elseif ($SummarizeExisting) {
        throw "G60 existing result missing: tag=$Tag"
    } else {
        Write-Host ("[g60] start tag=" + $Tag +
            " arm=" + $Arm)
        $launchProvenance = [pscustomobject]@{
            schema = "g60_launch_provenance_v1"
            tag = $Tag
            arm = $Arm
            source = "sequential-file"
            copy_workers = 1
            file_qd = $fileQD
            prefill_mass_layer_full_every = if ($isStripe) { 5 } else { 0 }
            prefill_mass_layer_full_phase = 0
            expected_content_sha256 = if ($isStripe) { "" } else { $controlExpected }
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
            created_utc = [DateTime]::UtcNow.ToString("o")
        }
        $launchProvenance | ConvertTo-Json -Depth 5 |
            Set-Content -LiteralPath $launchProvenancePath -Encoding UTF8
        & powershell.exe @args | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) { throw "G60 run failed: $Tag" }
    }

    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        throw "G60 result missing: tag=$Tag"
    }
    if (-not (Test-Path -LiteralPath $launchProvenancePath -PathType Leaf)) {
        throw "G60 launch provenance missing: tag=$Tag"
    }
    $launch = Get-Content -LiteralPath $launchProvenancePath -Raw |
        ConvertFrom-Json
    if ($launch.schema -ne "g60_launch_provenance_v1" -or
        $launch.tag -ne $Tag -or $launch.arm -ne $Arm -or
        $launch.source -ne "sequential-file" -or
        [int]$launch.copy_workers -ne 1 -or
        [int]$launch.file_qd -ne $fileQD -or
        [int]$launch.prefill_mass_layer_full_every -ne
            $(if ($isStripe) { 5 } else { 0 }) -or
        [int]$launch.prefill_mass_layer_full_phase -ne 0 -or
        $launch.expected_content_sha256 -ne
            $(if ($isStripe) { "" } else { $controlExpected }) -or
        $launch.execution_runner_sha256 -ne $executionRunnerHashForRuns -or
        $launch.executable_sha256 -ne $provenance.executable_sha256 -or
        $launch.harness_sha256 -ne $provenance.harness_sha256 -or
        $launch.runtime_monitor_harness_sha256 -ne
            $provenance.runtime_monitor_harness_sha256 -or
        $launch.ds4_cuda_sha256 -ne $provenance.ds4_cuda_sha256 -or
        $launch.ds4_c_sha256 -ne $provenance.ds4_c_sha256 -or
        $launch.ds4_server_c_sha256 -ne $provenance.ds4_server_c_sha256 -or
        $launch.build_manifest_sha256 -ne $provenance.build_manifest_sha256 -or
        $launch.prompt -ne $prompt) {
        throw "G60 launch provenance mismatch: tag=$Tag"
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
        "prefill_mass_layer_stripe_event_count",
        "prefill_mass_layer_stripe_failed_count",
        "prefill_mass_layer_stripe_result",
        "prefill_mass_layer_stripe_stride",
        "prefill_mass_layer_stripe_phase",
        "prefill_mass_layer_stripe_routed_layers",
        "prefill_mass_layer_stripe_full_layers",
        "prefill_mass_layer_stripe_partial_layers",
        "prefill_mass_layer_stripe_full_keep",
        "prefill_mass_layer_stripe_partial_keep_min",
        "prefill_mass_layer_stripe_partial_keep_max",
        "prefill_mass_layer_stripe_routed_candidate",
        "prefill_mass_layer_stripe_total_candidate",
        "prefill_mass_layer_stripe_capacity",
        "server_exit_code")) {
        Assert-G60Property -Object $r -Name $name -Tag $Tag
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
        $r.results.Count -ne 1 -or
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
        [int]$r.arena_wrap_file_qd_requested -ne $fileQD -or
        [int]$r.arena_wrap_file_qd_requested_observed -ne $fileQD -or
        [int]$r.arena_wrap_file_qd_observed -ne $fileQD -or
        [uint64]$r.arena_wrap_file_submits -ne [uint64]$r.arena_wrap_part_count -or
        [uint64]$r.arena_wrap_file_completions -ne [uint64]$r.arena_wrap_part_count -or
        [uint32]$r.arena_wrap_file_failures -ne 0 -or
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
        throw "G60 common contract mismatch: tag=$Tag"
    }

    if ($isStripe) {
        if ($r.expected_content_sha256 -ne "" -or
            [string]::IsNullOrWhiteSpace([string]$r.results[0].content_sha256) -or
            [int]$r.prefill_mass_layer_full_every_requested -ne 5 -or
            [int]$r.prefill_mass_layer_full_phase_requested -ne 0 -or
            -not [bool]$r.prefill_mass_layer_stripe_observed -or
            [int]$r.prefill_mass_layer_stripe_event_count -ne 1 -or
            [int]$r.prefill_mass_layer_stripe_failed_count -ne 0 -or
            $r.prefill_mass_layer_stripe_result -ne "applied" -or
            [int]$r.prefill_mass_layer_stripe_stride -ne 5 -or
            [int]$r.prefill_mass_layer_stripe_phase -ne 0 -or
            [int]$r.prefill_mass_layer_stripe_routed_layers -ne 40 -or
            [int]$r.prefill_mass_layer_stripe_full_layers -ne 8 -or
            [int]$r.prefill_mass_layer_stripe_partial_layers -ne 32 -or
            [int]$r.prefill_mass_layer_stripe_full_keep -ne 256 -or
            [int]$r.prefill_mass_layer_stripe_partial_keep_min -ne 54 -or
            [int]$r.prefill_mass_layer_stripe_partial_keep_max -ne 55 -or
            [int64]$r.prefill_mass_layer_stripe_routed_candidate -ne 3783 -or
            [int64]$r.prefill_mass_layer_stripe_total_candidate -ne 4551 -or
            [int64]$r.prefill_mass_layer_stripe_capacity -ne 4551 -or
            $r.prefill_mass_layer_stripe_semantics -ne "budget-preserving") {
            throw "G60 stripe telemetry mismatch: tag=$Tag"
        }
    } else {
        if ($r.expected_content_sha256 -ne $controlExpected -or
            $r.results[0].content_sha256 -ne $controlExpected -or
            [int]$r.prefill_mass_layer_full_every_requested -ne 0 -or
            [int]$r.prefill_mass_layer_full_phase_requested -ne 0 -or
            [bool]$r.prefill_mass_layer_stripe_observed -or
            [int]$r.prefill_mass_layer_stripe_event_count -ne 0 -or
            [int]$r.prefill_mass_layer_stripe_failed_count -ne 0 -or
            $r.prefill_mass_layer_stripe_result -ne "not_observed") {
            throw "G60 control hash/stripe isolation mismatch: tag=$Tag"
        }
    }

    $wrapSeconds = if ($null -ne $r.arena_wrap_profile_total_seconds) {
        [double]$r.arena_wrap_profile_total_seconds
    } else {
        [double]$r.prefill_mass_wrap_seconds
    }

    [pscustomobject]@{
        tag = $Tag
        arm = $Arm
        file_qd_requested = [int]$fileQD
        file_qd_requested_observed =
            [int]$r.arena_wrap_file_qd_requested_observed
        file_qd_observed = [int]$r.arena_wrap_file_qd_observed
        file_submits = [uint64]$r.arena_wrap_file_submits
        file_completions = [uint64]$r.arena_wrap_file_completions
        file_failures = [uint32]$r.arena_wrap_file_failures
        launch_provenance_path = $launchProvenancePath
        launch_provenance_sha256 = Get-G60SHA256 $launchProvenancePath
        execution_runner_sha256 = [string]$launch.execution_runner_sha256
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
        expected_content_sha256 = $r.expected_content_sha256
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
        mass_coverage = [double]$r.prefill_mass_coverage
        mass_candidate_entries = [int64]$r.prefill_mass_candidate_entries
        mass_capacity_entries = [int64]$r.prefill_mass_capacity_entries
        mass_candidate_mass = [double]$r.prefill_mass_candidate_mass
        compose_hash_layers = [int]$r.prefill_mass_compose_hash_layers
        compose_hash_seed_entries =
            [int64]$r.prefill_mass_compose_hash_seed_entries
        compose_ranked_entries =
            [int64]$r.prefill_mass_compose_ranked_entries
        compose_total_candidate =
            [int64]$r.prefill_mass_compose_total_candidate
        compose_capacity = [int64]$r.prefill_mass_compose_capacity
        candidate_fingerprint =
            [string]$r.prefill_mass_compose_candidate_fnv1a64
        stripe_event_count =
            [int]$r.prefill_mass_layer_stripe_event_count
        stripe_failed_count =
            [int]$r.prefill_mass_layer_stripe_failed_count
        stripe_result = [string]$r.prefill_mass_layer_stripe_result
        stripe_stride = [int]$r.prefill_mass_layer_stripe_stride
        stripe_phase = [int]$r.prefill_mass_layer_stripe_phase
        stripe_routed_layers =
            [int]$r.prefill_mass_layer_stripe_routed_layers
        stripe_full_layers =
            [int]$r.prefill_mass_layer_stripe_full_layers
        stripe_partial_layers =
            [int]$r.prefill_mass_layer_stripe_partial_layers
        stripe_full_keep = [int]$r.prefill_mass_layer_stripe_full_keep
        stripe_partial_keep_min =
            [int]$r.prefill_mass_layer_stripe_partial_keep_min
        stripe_partial_keep_max =
            [int]$r.prefill_mass_layer_stripe_partial_keep_max
        stripe_routed_candidate =
            [int64]$r.prefill_mass_layer_stripe_routed_candidate
        stripe_total_candidate =
            [int64]$r.prefill_mass_layer_stripe_total_candidate
        stripe_capacity = [int64]$r.prefill_mass_layer_stripe_capacity
        ram_h2d_gib = Convert-G60BytesToGiB $tier.ram_h2d_bytes
        route_h2d_gib =
            Convert-G60BytesToGiB $r.gpu_resident_routes_h2d_bytes
        route_calls = [uint64]$r.gpu_resident_routes_calls
        route_all_hit_calls = [uint64]$r.gpu_resident_routes_all_hit
        route_vram_routes = [uint64]$r.gpu_resident_routes_vram_routes
        route_pinned_ram_routes =
            [uint64]$r.gpu_resident_routes_pinned_ram_routes
        route_worker_jobs = [uint64]$r.gpu_resident_routes_worker_jobs
        route_miss_experts = [uint64]$r.gpu_resident_routes_miss_experts
        route_worker_ms_per_job =
            [double]$r.gpu_resident_routes_worker_ms_per_job
        route_wait_ms_per_call =
            [double]$r.gpu_resident_routes_wait_ms_per_call
        route_resolve_ms_per_call =
            [double]$r.gpu_resident_routes_resolve_ms_per_call
        windows_available_min_gib =
            Convert-G60BytesToGiB $rt.windows_available_min_bytes
        working_set_peak_gib =
            Convert-G60BytesToGiB $rt.process_working_set_peak_bytes
        private_peak_gib =
            Convert-G60BytesToGiB $rt.process_private_peak_bytes
        gpu_shared_peak_gib =
            Convert-G60BytesToGiB $rt.gpu_process_shared_peak_bytes
        gpu_dedicated_peak_gib =
            Convert-G60BytesToGiB $rt.gpu_process_dedicated_peak_bytes
        page_fault_delta = Get-G60Property $rt "page_fault_delta"
        process_read_gib =
            Convert-G60BytesToGiB $rt.win32_process_read_transfer_delta_bytes
        process_write_gib =
            Convert-G60BytesToGiB $rt.win32_process_write_transfer_delta_bytes
        aggregate_disk_read_gib = Convert-G60BytesToGiB `
            (Get-G60Property $rt "aggregate_disk_read_bytes_estimated")
        aggregate_disk_read_mib_per_second =
            Get-G60Property $rt "aggregate_disk_read_mib_per_second"
        aggregate_disk_read_throughput_mib_per_second =
            Get-G60Property $rt "aggregate_disk_read_throughput_mib_per_second"
        aggregate_disk_queue_length_peak =
            Get-G60Property $rt "aggregate_disk_queue_length_peak"
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
    "ArenaWrapFileQD",
    "PrefillMassLayerFullEvery",
    "PrefillMassLayerFullPhase")) {
    if (-not $SummarizeExisting -and
        -not (Test-G60HarnessParameter -ParameterName $parameter)) {
        throw "Harness does not expose -$parameter; refusing to launch model."
    }
}

if ($SafetyOnly) {
    $runPlan = @(
        @{ Tag = "g60_layer_stripe_control_safety"; Arm = "control" },
        @{ Tag = "g60_layer_stripe_stripe_safety"; Arm = "stripe" }
    )
} else {
    $runPlan = @(
        @{ Tag = "g60_layer_stripe_control_a"; Arm = "control" },
        @{ Tag = "g60_layer_stripe_stripe_a"; Arm = "stripe" },
        @{ Tag = "g60_layer_stripe_stripe_b"; Arm = "stripe" },
        @{ Tag = "g60_layer_stripe_control_b"; Arm = "control" },
        @{ Tag = "g60_layer_stripe_control_c"; Arm = "control" },
        @{ Tag = "g60_layer_stripe_stripe_c"; Arm = "stripe" }
    )
}

$runs = @()
foreach ($item in $runPlan) {
    $runs += Invoke-G60Run -Tag $item.Tag -Arm $item.Arm
}

$provenanceFields = @(
    "head", "executable_sha256", "ds4_cuda_sha256", "ds4_c_sha256",
    "ds4_server_c_sha256", "build_manifest_sha256",
    "build_input_fingerprint_sha256", "harness_sha256",
    "runtime_monitor_harness_sha256", "model",
    "model_bytes", "model_last_write_utc", "build_worktree_dirty",
    "server_exit_code", "expert_cache_capacity", "file_qd_requested",
    "file_qd_requested_observed", "file_qd_observed",
    "execution_runner_sha256"
)
foreach ($field in $provenanceFields) {
    $values = @($runs | ForEach-Object { [string]($_.$field) } |
        Select-Object -Unique)
    if ($values.Count -ne 1) {
        throw "G60 mixed provenance or contract across runs: field=$field"
    }
}

$controlRows = @($runs | Where-Object { $_.arm -eq "control" })
$stripeRows = @($runs | Where-Object { $_.arm -eq "stripe" })
$expectedPerArm = if ($SafetyOnly) { 1 } else { 3 }
if ($controlRows.Count -ne $expectedPerArm -or
    $stripeRows.Count -ne $expectedPerArm) {
    throw "G60 replication mismatch"
}

$stripeHashes = @($stripeRows | ForEach-Object { [string]$_.content_sha256 } |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
    Select-Object -Unique)
if ($stripeHashes.Count -ne 1) {
    throw "G60 stripe output hashes are not identical and non-empty"
}

function New-G60ArmSummary {
    param(
        [Parameter(Mandatory=$true)][string]$Arm,
        [Parameter(Mandatory=$true)][object[]]$Rows
    )
    [pscustomobject]@{
        arm = $Arm
        independent_processes = $Rows.Count
        file_qd = $fileQD
        output_hashes = @($Rows | ForEach-Object { $_.content_sha256 })
        candidate_fingerprints =
            @($Rows | ForEach-Object { $_.candidate_fingerprint })
        ttft_mean_seconds = Get-G60Mean $Rows "ttft_seconds"
        ttft_median_seconds = Get-G60Median $Rows "ttft_seconds"
        wrap_seconds_mean = Get-G60Mean $Rows "wrap_seconds"
        wrap_seconds_median = Get-G60Median $Rows "wrap_seconds"
        wrap_copy_seconds_mean = Get-G60Mean $Rows "wrap_copy_seconds"
        wrap_copy_seconds_median = Get-G60Median $Rows "wrap_copy_seconds"
        wrap_checksum_seconds_mean =
            Get-G60Mean $Rows "wrap_checksum_seconds"
        decode_tokens_per_second_mean =
            Get-G60Mean $Rows "decode_tokens_per_second"
        decode_tokens_per_second_median =
            Get-G60Median $Rows "decode_tokens_per_second"
        decode_seconds_mean = Get-G60Mean $Rows "decode_seconds"
        mass_coverage_mean = Get-G60Mean $Rows "mass_coverage"
        mass_coverage_median = Get-G60Median $Rows "mass_coverage"
        ram_h2d_gib_mean = Get-G60Mean $Rows "ram_h2d_gib"
        ram_h2d_gib_median = Get-G60Median $Rows "ram_h2d_gib"
        route_h2d_gib_mean = Get-G60Mean $Rows "route_h2d_gib"
        route_h2d_gib_median = Get-G60Median $Rows "route_h2d_gib"
        windows_available_min_gib_mean =
            Get-G60Mean $Rows "windows_available_min_gib"
        working_set_peak_gib_mean =
            Get-G60Mean $Rows "working_set_peak_gib"
        private_peak_gib_mean = Get-G60Mean $Rows "private_peak_gib"
        gpu_shared_peak_gib_mean =
            Get-G60Mean $Rows "gpu_shared_peak_gib"
        process_read_gib_mean = Get-G60Mean $Rows "process_read_gib"
        process_write_gib_mean = Get-G60Mean $Rows "process_write_gib"
        page_fault_delta_mean = Get-G60Mean $Rows "page_fault_delta"
        aggregate_disk_read_gib_mean =
            Get-G60Mean $Rows "aggregate_disk_read_gib"
        aggregate_disk_read_mib_per_second_mean =
            Get-G60Mean $Rows "aggregate_disk_read_mib_per_second"
        aggregate_disk_read_throughput_mib_per_second_mean =
            Get-G60Mean $Rows "aggregate_disk_read_throughput_mib_per_second"
        aggregate_disk_queue_length_peak_mean =
            Get-G60Mean $Rows "aggregate_disk_queue_length_peak"
        file_submits_sum =
            ($Rows | Measure-Object -Property file_submits -Sum).Sum
        file_completions_sum =
            ($Rows | Measure-Object -Property file_completions -Sum).Sum
        file_failures_sum =
            ($Rows | Measure-Object -Property file_failures -Sum).Sum
        snapshot_misses_sum =
            ($Rows | Measure-Object -Property snapshot_misses -Sum).Sum
        ssd_bytes_sum =
            ($Rows | Measure-Object -Property ssd_bytes -Sum).Sum
        failures_sum =
            ($Rows | Measure-Object -Property failures -Sum).Sum
    }
}

$controlSummary = New-G60ArmSummary -Arm "control" -Rows $controlRows
$stripeSummary = New-G60ArmSummary -Arm "stripe" -Rows $stripeRows
$armSummary = @($controlSummary, $stripeSummary)

$deltaPercent = [pscustomobject]@{
    stripe_vs_control_decode_tps_mean =
        Get-G60DeltaPercent $controlSummary.decode_tokens_per_second_mean `
            $stripeSummary.decode_tokens_per_second_mean
    stripe_vs_control_decode_tps_median =
        Get-G60DeltaPercent $controlSummary.decode_tokens_per_second_median `
            $stripeSummary.decode_tokens_per_second_median
    stripe_vs_control_ttft_mean =
        Get-G60DeltaPercent $controlSummary.ttft_mean_seconds `
            $stripeSummary.ttft_mean_seconds
    stripe_vs_control_ttft_median =
        Get-G60DeltaPercent $controlSummary.ttft_median_seconds `
            $stripeSummary.ttft_median_seconds
    stripe_vs_control_wrap_mean =
        Get-G60DeltaPercent $controlSummary.wrap_seconds_mean `
            $stripeSummary.wrap_seconds_mean
    stripe_vs_control_wrap_median =
        Get-G60DeltaPercent $controlSummary.wrap_seconds_median `
            $stripeSummary.wrap_seconds_median
    stripe_vs_control_mass_coverage_mean =
        Get-G60DeltaPercent $controlSummary.mass_coverage_mean `
            $stripeSummary.mass_coverage_mean
    stripe_vs_control_mass_coverage_median =
        Get-G60DeltaPercent $controlSummary.mass_coverage_median `
            $stripeSummary.mass_coverage_median
    stripe_vs_control_ram_h2d_gib_mean =
        Get-G60DeltaPercent $controlSummary.ram_h2d_gib_mean `
            $stripeSummary.ram_h2d_gib_mean
    stripe_vs_control_route_h2d_gib_mean =
        Get-G60DeltaPercent $controlSummary.route_h2d_gib_mean `
            $stripeSummary.route_h2d_gib_mean
}

$summary = [pscustomobject]@{
    schema = "g60_layer_stripe_ab_v1"
    question = "Does budget-preserving prefill mass layer striping every 5 layers phase 0 improve G55 QD8 sequential-file behavior on the exact cyberpunk prompt and config?"
    prompt = $prompt
    context = 256
    max_tokens = 64
    model = $model
    arena_gib = 30
    cache_experts = 320
    cache_reserve_gib = 0.125
    file_qd = $fileQD
    source = "sequential-file"
    copy_workers = 1
    sequential_workers = 1
    route_no_default_sync = $true
    q8_f16_cache = "disabled"
    safety_only = [bool]$SafetyOnly
    independent_processes_per_arm = $expectedPerArm
    within_process_repeats = 1
    system_file_cache_flushed_between_runs = $false
    control_expected_content_sha256 = $controlExpected
    stripe_expected_content_sha256 = ""
    stripe_output_sha256 = $stripeHashes[0]
    summarized_existing_results = [bool]$SummarizeExisting
    execution_runner_sha256 = $executionRunnerHashForRuns
    summary_runner_sha256 = Get-G60SHA256 $MyInvocation.MyCommand.Path
    order_contract = if ($SafetyOnly) {
        "safety-only one independent process per arm; control,stripe; no winner declaration; no L0-L3 grading on 64 tokens"
    } else {
        "counterbalanced arm order control,stripe,stripe,control,control,stripe; n=3 independent processes per arm; no winner declaration from n=1; no L0-L3 grading on 64 tokens"
    }
    order = @($runs | ForEach-Object { $_.tag })
    order_arm = @($runs | ForEach-Object { $_.arm })
    control_contract = "ExpectedContentSHA256 fixed to control hash; zero stripe request and zero stripe telemetry"
    stripe_contract = "No control hash comparison; -PrefillMassLayerFullEvery 5 -PrefillMassLayerFullPhase 0; three stripe outputs must share one non-empty SHA"
    excluded_features = @(
        "split-hit-miss", "SPEX", "static-mask", "trim", "diagnostics",
        "arena-wrap-part-profile", "default-sync", "Q8F16-cache")
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
    }
    required_stripe_telemetry = [pscustomobject]@{
        event_count = 1
        failed_count = 0
        stride = 5
        phase = 0
        routed_layers = 40
        full_layers = 8
        partial_layers = 32
        full_keep = 256
        partial_keep_min = 54
        partial_keep_max = 55
        routed_candidate = 3783
        total_candidate = 4551
        capacity = 4551
        snapshot_misses = 0
        ssd_bytes = 0
        failures = 0
        default_sync_calls = 0
        file_qd = 8
    }
    runs = $runs
    arm_summary = $armSummary
    delta_percent = $deltaPercent
    winner = ""
    interpretation_note = "No winner declared here; n=3 per arm unless SafetyOnly and 64-token outputs are not L0-L3 graded."
}

$summaryPath = Join-Path $outdir "g60_layer_stripe_ab_result.json"
$summary | ConvertTo-Json -Depth 10 |
    Set-Content -LiteralPath $summaryPath -Encoding UTF8
foreach ($arm in $armSummary) {
    Write-Host ("[g60] arm=" + $arm.arm +
        " n=" + $arm.independent_processes +
        " wrap_med=" + $arm.wrap_seconds_median +
        " ttft_med=" + $arm.ttft_median_seconds +
        " decode_tps_med=" + $arm.decode_tokens_per_second_median +
        " coverage_med=" + $arm.mass_coverage_median +
        " route_h2d_gib_mean=" + $arm.route_h2d_gib_mean +
        " hashes=" + (($arm.output_hashes | Select-Object -Unique) -join ",") +
        " fingerprints=" +
            (($arm.candidate_fingerprints | Select-Object -Unique) -join ",") +
        " file_submits=" + $arm.file_submits_sum +
        " file_completions=" + $arm.file_completions_sum +
        " file_failures=" + $arm.file_failures_sum)
}
Write-Host ("[g60] matrix complete: " + $summaryPath)
