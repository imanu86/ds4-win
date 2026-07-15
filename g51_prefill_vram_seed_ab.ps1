# G51 request-scoped prefill VRAM seed A/B (PowerShell 5.1, ASCII).
param(
    [switch]$SafetyOnly,
    [switch]$Resume,
    [switch]$SummarizeExisting,
    [switch]$SkipSystemQuiescencePreflight,
    [ValidateRange(1, 64)][int]$TransportFileQD = 8,
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

function Get-G51SHA256 {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "G51 provenance file missing: $Path"
    }
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-G51Mean {
    param(
        [Parameter(Mandatory=$true)][object[]]$Rows,
        [Parameter(Mandatory=$true)][string]$Property
    )
    $values = @($Rows | ForEach-Object { $_.$Property } |
        Where-Object { $null -ne $_ })
    if ($values.Count -eq 0) { return $null }
    [math]::Round(($values | Measure-Object -Average).Average, 6)
}

function Get-G51Median {
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

function Assert-G51Property {
    param(
        [Parameter(Mandatory=$true)][object]$Object,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Tag
    )
    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) {
        throw "G51 required field missing: tag=$Tag field=$Name"
    }
}

function Get-G51Property {
    param([object]$Object, [string]$Name)
    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) {
        return $null
    }
    $Object.PSObject.Properties[$Name].Value
}

function Convert-G51BytesToGiB {
    param([object]$Value)
    if ($null -eq $Value) { return $null }
    [math]::Round(([double]$Value / 1GB), 6)
}

function Test-G51HarnessParameter {
    param([Parameter(Mandatory=$true)][string]$ParameterName)
    $content = Get-Content -LiteralPath $harness -Raw
    return ($content -match ("\$" + [regex]::Escape($ParameterName) +
        "(\s|=|,|\))"))
}

$provenance = [pscustomobject]@{
    executable_sha256 = Get-G51SHA256 $executable
    harness_sha256 = Get-G51SHA256 $harness
    runtime_monitor_harness_sha256 = Get-G51SHA256 $runtimeMonitor
    ds4_cuda_sha256 = Get-G51SHA256 (Join-Path $root "ds4_cuda.cu")
    ds4_c_sha256 = Get-G51SHA256 (Join-Path $root "ds4.c")
    ds4_server_c_sha256 = Get-G51SHA256 (Join-Path $root "ds4_server.c")
    build_manifest_sha256 = Get-G51SHA256 $buildManifest
}
$executionRunnerHashAtStart = Get-G51SHA256 $MyInvocation.MyCommand.Path
$executionRunnerHashForRuns = if ($SummarizeExisting) {
    $ExecutionRunnerSHA256.ToLowerInvariant()
} else {
    $executionRunnerHashAtStart
}

function Invoke-G51Run {
    param(
        [Parameter(Mandatory=$true)][string]$Tag,
        [Parameter(Mandatory=$true)]
        [ValidateSet("control", "prefill-vram-seed")]
        [string]$Arm,
        [Parameter(Mandatory=$true)][ValidateRange(0, 8)]
        [int]$PrefillVramSeedPerLayer
    )

    $resultPath = Join-Path $outdir ("g7_" + $Tag + "_result.json")
    $launchProvenancePath = Join-Path $outdir `
        ("g7_" + $Tag + "_g51_launch_provenance.json")
    $args = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $harness,
        "-MaxTokens", "64", "-Repeats", "1", "-Tag", $Tag,
        "-Prompt", $prompt, "-Context", "256",
        "-BudgetGB", "2", "-ReserveMB", "1024",
        "-DynamicArenaGiB", "30", "-ArenaWrapTrustWorkerChecksum",
        "-ArenaWrapSourceParts", "-ArenaWrapSequentialFile",
        "-ArenaWrapSequentialWorkers", "1",
        "-ArenaWrapFileQD", ([string]$TransportFileQD),
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
    if ($Arm -eq "prefill-vram-seed") {
        $args += @("-PrefillVramSeedPerLayer",
            ([string]$PrefillVramSeedPerLayer))
    }
    if ($SkipSystemQuiescencePreflight) {
        $args += "-SkipSystemQuiescencePreflight"
    }

    if (($Resume -or $SummarizeExisting) -and
        (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        Write-Host ("[g51] validate existing tag=" + $Tag +
            " arm=" + $Arm + " transport_qd=" + $TransportFileQD)
    } elseif ($SummarizeExisting) {
        throw "G51 existing result missing: tag=$Tag"
    } else {
        Write-Host ("[g51] start tag=" + $Tag + " arm=" + $Arm +
            " seed_per_layer=" + $PrefillVramSeedPerLayer +
            " transport_qd=" + $TransportFileQD)
        $launchProvenance = [pscustomobject]@{
            schema = "g51_launch_provenance_v1"
            tag = $Tag
            arm = $Arm
            prefill_vram_seed_per_layer = $PrefillVramSeedPerLayer
            source = "sequential-file"
            copy_workers = 1
            file_qd = $TransportFileQD
            safety_only = [bool]$SafetyOnly
            system_quiescence_skipped =
                [bool]$SkipSystemQuiescencePreflight
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
            config = [pscustomobject]@{
                max_tokens = 64
                repeats = 1
                context = 256
                budget_gb = 2
                reserve_mb = 1024
                dynamic_arena_gib = 30
                transport_source = "sequential-file"
                transport_schedule = "source-parts"
                transport_trusted_worker_checksum = $true
                transport_copy_workers = 1
                transport_sequential_workers = 1
                transport_file_qd = $TransportFileQD
                expert_cache_n = 320
                expert_cache_reserve_gb = 0.125
                expert_cache_policy = "lru"
                expert_tiering = "enforce"
                expert_tier_policy = "mass-lfru"
                prefill_vram_seed_per_layer = $PrefillVramSeedPerLayer
            }
            created_utc = [DateTime]::UtcNow.ToString("o")
        }
        $launchProvenance | ConvertTo-Json -Depth 6 |
            Set-Content -LiteralPath $launchProvenancePath -Encoding UTF8
        & powershell.exe @args | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) { throw "G51 run failed: $Tag" }
    }

    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        throw "G51 result missing: tag=$Tag"
    }
    if (-not (Test-Path -LiteralPath $launchProvenancePath -PathType Leaf)) {
        throw "G51 launch provenance missing: tag=$Tag"
    }
    $launch = Get-Content -LiteralPath $launchProvenancePath -Raw |
        ConvertFrom-Json
    if ($launch.schema -ne "g51_launch_provenance_v1" -or
        $launch.tag -ne $Tag -or $launch.arm -ne $Arm -or
        [int]$launch.prefill_vram_seed_per_layer -ne
            $PrefillVramSeedPerLayer -or
        $launch.source -ne "sequential-file" -or
        [int]$launch.copy_workers -ne 1 -or
        [int]$launch.file_qd -ne $TransportFileQD -or
        [bool]$launch.safety_only -ne [bool]$SafetyOnly -or
        [bool]$launch.system_quiescence_skipped -ne
            [bool]$SkipSystemQuiescencePreflight -or
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
        $launch.expected_content_sha256 -ne $expected -or
        [int]$launch.config.max_tokens -ne 64 -or
        [int]$launch.config.repeats -ne 1 -or
        [int]$launch.config.context -ne 256 -or
        [int]$launch.config.budget_gb -ne 2 -or
        [int]$launch.config.reserve_mb -ne 1024 -or
        [int]$launch.config.dynamic_arena_gib -ne 30 -or
        $launch.config.transport_source -ne "sequential-file" -or
        $launch.config.transport_schedule -ne "source-parts" -or
        [bool]$launch.config.transport_trusted_worker_checksum -ne $true -or
        [int]$launch.config.transport_copy_workers -ne 1 -or
        [int]$launch.config.transport_sequential_workers -ne 1 -or
        [int]$launch.config.transport_file_qd -ne $TransportFileQD -or
        [int]$launch.config.expert_cache_n -ne 320 -or
        [double]$launch.config.expert_cache_reserve_gb -ne 0.125 -or
        $launch.config.expert_cache_policy -ne "lru" -or
        $launch.config.expert_tiering -ne "enforce" -or
        $launch.config.expert_tier_policy -ne "mass-lfru" -or
        [int]$launch.config.prefill_vram_seed_per_layer -ne
            $PrefillVramSeedPerLayer) {
        throw "G51 launch provenance mismatch: tag=$Tag"
    }

    $r = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    $tier = $r.expert_tiering
    $mem = $r.memory_preflight
    $proc = $r.process_isolation_preflight
    $sys = $r.system_quiescence_preflight
    $rt = $r.runtime_telemetry
    $wantSeed = ($Arm -eq "prefill-vram-seed")
    $systemQuiescenceSkippedObserved =
        [bool](Get-G51Property $sys "skipped")

    foreach ($name in @(
        "server_exit_code",
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
        "arena_wrap_layout_profile_requested",
        "arena_wrap_layout_profile_observed",
        "arena_wrap_part_count",
        "prefill_vram_seed_requested_per_layer",
        "prefill_vram_seed_observed",
        "prefill_vram_seed_result",
        "prefill_vram_seed_layers",
        "prefill_vram_seed_entries",
        "prefill_vram_seed_bytes",
        "prefill_vram_seed_seconds",
        "prefill_vram_seed_failures",
        "prefill_mass_compose_candidate_fnv1a64")) {
        Assert-G51Property -Object $r -Name $name -Tag $Tag
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
        [int]$r.server_exit_code -ne 0 -or
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
        [bool]$r.arena_wrap_random_file_requested -ne $false -or
        $r.arena_wrap_source_requested -ne "sequential-file" -or
        $r.arena_wrap_source_observed -ne "sequential-file" -or
        [int]$r.arena_wrap_sequential_workers_requested -ne 1 -or
        [int]$r.arena_wrap_copy_workers -ne 1 -or
        [int]$r.arena_wrap_file_qd_requested -ne $TransportFileQD -or
        [int]$r.arena_wrap_file_qd_requested_observed -ne
            $TransportFileQD -or
        [int]$r.arena_wrap_file_qd_observed -ne $TransportFileQD -or
        [uint64]$r.arena_wrap_file_failures -ne 0 -or
        [bool]$r.arena_wrap_layout_profile_requested -or
        [bool]$r.arena_wrap_layout_profile_observed -or
        [bool]$r.arena_wrap_part_profile_requested -or
        [bool]$r.arena_wrap_part_profile_observed -or
        [bool]$r.arena_wrap_trim_between_phases_requested -or
        [bool]$r.arena_wrap_trim_observed -or
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
        $systemQuiescenceSkippedObserved -ne
            [bool]$SkipSystemQuiescencePreflight -or
        ($SkipSystemQuiescencePreflight -eq $false -and
            $sys.ready_to_launch -ne $true) -or
        $rt.contamination_abort_observed -ne $false -or
        $rt.contamination_runtime_minimum_available_gib -ne 2 -or
        $rt.contamination_runtime_maximum_disk_queue_length -ne 8 -or
        $rt.contamination_runtime_consecutive_samples -ne 3 -or
        $null -eq $rt.aggregate_disk_queue_length_peak -or
        $null -eq $rt.aggregate_disk_read_bytes_estimated) {
        throw "G51 contract mismatch: tag=$Tag"
    }

    if ($TransportFileQD -gt 1) {
        if ([uint64]$r.arena_wrap_file_submits -ne
                [uint64]$r.arena_wrap_part_count -or
            [uint64]$r.arena_wrap_file_completions -ne
                [uint64]$r.arena_wrap_part_count) {
            throw "G51 file QD counter mismatch: tag=$Tag"
        }
    } elseif ([uint64]$r.arena_wrap_file_submits -ne 0 -or
        [uint64]$r.arena_wrap_file_completions -ne 0) {
        throw "G51 legacy QD1 counter mismatch: tag=$Tag"
    }

    if ($wantSeed) {
        if ($r.prefill_vram_seed_requested_per_layer -ne 8 -or
            -not $r.prefill_vram_seed_observed -or
            $r.prefill_vram_seed_result -ne "ok" -or
            $r.prefill_vram_seed_layers -ne 40 -or
            $r.prefill_vram_seed_entries -ne 320 -or
            $r.prefill_vram_seed_failures -ne 0) {
            throw "G51 candidate seed mismatch: tag=$Tag"
        }
    } else {
        if ($r.prefill_vram_seed_requested_per_layer -ne 0 -or
            $r.prefill_vram_seed_observed -or
            $r.prefill_vram_seed_entries -ne 0) {
            throw "G51 control seed observed unexpectedly: tag=$Tag"
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
        requested_prefill_vram_seed_per_layer = $PrefillVramSeedPerLayer
        transport_file_qd_requested = [int]$TransportFileQD
        transport_file_qd_requested_observed =
            [int]$r.arena_wrap_file_qd_requested_observed
        transport_file_qd_observed = [int]$r.arena_wrap_file_qd_observed
        file_submits = [uint64]$r.arena_wrap_file_submits
        file_completions = [uint64]$r.arena_wrap_file_completions
        file_failures = [uint64]$r.arena_wrap_file_failures
        source_requested = [string]$r.arena_wrap_source_requested
        source_observed = [string]$r.arena_wrap_source_observed
        sequential_file_requested =
            [bool]$r.arena_wrap_sequential_file_requested
        random_file_requested = [bool]$r.arena_wrap_random_file_requested
        copy_workers = [int]$r.arena_wrap_copy_workers
        sequential_workers_requested =
            [int]$r.arena_wrap_sequential_workers_requested
        arena_wrap_part_count = [uint64]$r.arena_wrap_part_count
        launch_provenance_path = $launchProvenancePath
        launch_provenance_sha256 = Get-G51SHA256 $launchProvenancePath
        execution_runner_sha256 = [string]$launch.execution_runner_sha256
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
        ram_h2d_gib = Convert-G51BytesToGiB $tier.ram_h2d_bytes
        promotions = [uint64]$tier.vram_promotions
        demotions = [uint64]$tier.vram_demotions
        route_calls = [uint64]$r.gpu_resident_routes_calls
        route_all_hit_calls = [uint64]$r.gpu_resident_routes_all_hit
        route_vram_routes = [uint64]$r.gpu_resident_routes_vram_routes
        route_pinned_ram_routes =
            [uint64]$r.gpu_resident_routes_pinned_ram_routes
        route_h2d_gib =
            Convert-G51BytesToGiB $r.gpu_resident_routes_h2d_bytes
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
        prefill_vram_seed_requested_per_layer =
            [int]$r.prefill_vram_seed_requested_per_layer
        prefill_vram_seed_observed = [bool]$r.prefill_vram_seed_observed
        prefill_vram_seed_result = [string]$r.prefill_vram_seed_result
        prefill_vram_seed_layers = [int]$r.prefill_vram_seed_layers
        prefill_vram_seed_entries = [int]$r.prefill_vram_seed_entries
        prefill_vram_seed_bytes = [uint64]$r.prefill_vram_seed_bytes
        prefill_vram_seed_gib =
            Convert-G51BytesToGiB $r.prefill_vram_seed_bytes
        prefill_vram_seed_seconds = [double]$r.prefill_vram_seed_seconds
        prefill_vram_seed_failures = [uint64]$r.prefill_vram_seed_failures
        windows_available_min_gib =
            Convert-G51BytesToGiB $rt.windows_available_min_bytes
        working_set_peak_gib =
            Convert-G51BytesToGiB $rt.process_working_set_peak_bytes
        private_peak_gib =
            Convert-G51BytesToGiB $rt.process_private_peak_bytes
        gpu_shared_peak_gib =
            Convert-G51BytesToGiB $rt.gpu_process_shared_peak_bytes
        gpu_dedicated_peak_gib =
            Convert-G51BytesToGiB $rt.gpu_process_dedicated_peak_bytes
        page_fault_delta = Get-G51Property $rt "page_fault_delta"
        process_read_gib =
            Convert-G51BytesToGiB $rt.win32_process_read_transfer_delta_bytes
        process_write_gib =
            Convert-G51BytesToGiB $rt.win32_process_write_transfer_delta_bytes
        process_read_operation_delta =
            Get-G51Property $rt "win32_process_read_operation_delta"
        process_other_operation_delta =
            Get-G51Property $rt "win32_process_other_operation_delta"
        process_read_throughput_mib_per_second =
            Get-G51Property $rt "process_read_throughput_mib_per_second"
        aggregate_disk_read_gib = Convert-G51BytesToGiB `
            (Get-G51Property $rt "aggregate_disk_read_bytes_estimated")
        aggregate_disk_read_mib_per_second =
            Get-G51Property $rt "aggregate_disk_read_mib_per_second"
        aggregate_disk_read_throughput_mib_per_second =
            Get-G51Property $rt "aggregate_disk_read_throughput_mib_per_second"
        aggregate_disk_queue_length =
            Get-G51Property $rt "aggregate_disk_queue_length_median"
        aggregate_disk_queue_length_peak =
            Get-G51Property $rt "aggregate_disk_queue_length_peak"
        mmap_backed_file_io_measured =
            Get-G51Property $rt "mmap_backed_file_io_measured"
        contamination_abort_observed =
            [bool]$rt.contamination_abort_observed
        snapshot_misses = [uint64]$tier.snapshot_backing_misses
        ssd_bytes = [uint64]$tier.ssd_bytes
        failures = [uint64]$tier.failures
        memory_preflight_ready = [bool]$mem.ready_to_launch
        process_preflight_ready = [bool]$proc.ready_to_launch
        system_preflight_ready = [bool]$sys.ready_to_launch
        system_quiescence_skipped = $systemQuiescenceSkippedObserved
        timing_valid = (-not [bool]$SafetyOnly -and
            -not [bool]$SkipSystemQuiescencePreflight)
    }
}

New-Item -ItemType Directory -Force -Path $outdir | Out-Null
if ($SkipSystemQuiescencePreflight -and -not $SafetyOnly) {
    throw "G51 normal n=3 refuses -SkipSystemQuiescencePreflight"
}
if ($SummarizeExisting -and
    $ExecutionRunnerSHA256 -notmatch '^[0-9a-fA-F]{64}$') {
    throw "SummarizeExisting requires -ExecutionRunnerSHA256"
}
foreach ($parameter in @(
    "PrefillVramSeedPerLayer",
    "ArenaWrapSequentialFile",
    "ArenaWrapSequentialWorkers",
    "ArenaWrapFileQD",
    "SkipSystemQuiescencePreflight")) {
    if (-not $SummarizeExisting -and
        -not (Test-G51HarnessParameter -ParameterName $parameter)) {
        throw "Harness does not expose -$parameter; refusing to launch model."
    }
}

$runs = @()
if ($SafetyOnly) {
    $runPlan = @(
        @{
            Tag = "g51_prefill_vram_seed_on_safety"
            Arm = "prefill-vram-seed"
            Seed = 8
        }
    )
} else {
    $runPlan = @(
        @{ Tag = "g51_prefill_vram_seed_off_a"; Arm = "control"; Seed = 0 },
        @{
            Tag = "g51_prefill_vram_seed_on_a"
            Arm = "prefill-vram-seed"
            Seed = 8
        },
        @{
            Tag = "g51_prefill_vram_seed_on_b"
            Arm = "prefill-vram-seed"
            Seed = 8
        },
        @{ Tag = "g51_prefill_vram_seed_off_b"; Arm = "control"; Seed = 0 },
        @{ Tag = "g51_prefill_vram_seed_off_c"; Arm = "control"; Seed = 0 },
        @{
            Tag = "g51_prefill_vram_seed_on_c"
            Arm = "prefill-vram-seed"
            Seed = 8
        }
    )
}
foreach ($item in $runPlan) {
    $runs += Invoke-G51Run -Tag $item.Tag -Arm $item.Arm `
        -PrefillVramSeedPerLayer $item.Seed
}

$provenanceFields = @(
    "head", "executable_sha256", "ds4_cuda_sha256", "ds4_c_sha256",
    "ds4_server_c_sha256", "build_manifest_sha256",
    "build_input_fingerprint_sha256", "harness_sha256",
    "runtime_monitor_harness_sha256", "model",
    "model_bytes", "model_last_write_utc", "build_worktree_dirty",
    "server_exit_code", "expert_cache_capacity", "content_sha256",
    "copy_workers", "sequential_workers_requested", "source_requested",
    "source_observed", "sequential_file_requested",
    "random_file_requested", "execution_runner_sha256",
    "transport_file_qd_requested", "transport_file_qd_requested_observed",
    "transport_file_qd_observed", "timing_valid", "candidate_mask_fnv1a64"
)
foreach ($field in $provenanceFields) {
    $values = @($runs | ForEach-Object { [string]($_.$field) } |
        Select-Object -Unique)
    if ($values.Count -ne 1) {
        throw "G51 mixed provenance or contract across runs: field=$field"
    }
}
if ([int]$runs[0].expert_cache_capacity -lt 300 -or
    [int]$runs[0].expert_cache_capacity -gt 320) {
    throw "G51 effective expert cache capacity outside 300..320"
}
if ([int]$runs[0].copy_workers -ne 1) {
    throw "G51 copy_workers contract mismatch"
}

$armSummary = @()
foreach ($arm in @("control", "prefill-vram-seed")) {
    $rows = @($runs | Where-Object { $_.arm -eq $arm })
    $expectedRows = if ($SafetyOnly -and $arm -eq "prefill-vram-seed") {
        1
    } elseif ($SafetyOnly) {
        0
    } else {
        3
    }
    if ($rows.Count -ne $expectedRows) {
        throw "G51 replication mismatch: arm=$arm"
    }
    if ($rows.Count -eq 0) { continue }
    $armSummary += [pscustomobject]@{
        arm = $arm
        independent_processes = $rows.Count
        transport_file_qd = $TransportFileQD
        file_submits_sum =
            ($rows | Measure-Object -Property file_submits -Sum).Sum
        file_completions_sum =
            ($rows | Measure-Object -Property file_completions -Sum).Sum
        file_failures_sum =
            ($rows | Measure-Object -Property file_failures -Sum).Sum
        decode_tokens_per_second_mean =
            Get-G51Mean $rows "decode_tokens_per_second"
        decode_tokens_per_second_median =
            Get-G51Median $rows "decode_tokens_per_second"
        decode_seconds_mean = Get-G51Mean $rows "decode_seconds"
        decode_seconds_median = Get-G51Median $rows "decode_seconds"
        ttft_mean_seconds = Get-G51Mean $rows "ttft_seconds"
        ttft_median_seconds = Get-G51Median $rows "ttft_seconds"
        wrap_seconds_mean = Get-G51Mean $rows "wrap_seconds"
        wrap_seconds_median = Get-G51Median $rows "wrap_seconds"
        wrap_copy_seconds_mean = Get-G51Mean $rows "wrap_copy_seconds"
        wrap_copy_seconds_median = Get-G51Median $rows "wrap_copy_seconds"
        wrap_checksum_seconds_mean =
            Get-G51Mean $rows "wrap_checksum_seconds"
        vram_hits_mean = Get-G51Mean $rows "vram_hits"
        ram_hits_mean = Get-G51Mean $rows "ram_hits"
        ram_h2d_gib_mean = Get-G51Mean $rows "ram_h2d_gib"
        promotions_mean = Get-G51Mean $rows "promotions"
        demotions_mean = Get-G51Mean $rows "demotions"
        route_vram_routes_mean = Get-G51Mean $rows "route_vram_routes"
        route_pinned_ram_routes_mean =
            Get-G51Mean $rows "route_pinned_ram_routes"
        route_h2d_gib_mean = Get-G51Mean $rows "route_h2d_gib"
        route_worker_jobs_mean = Get-G51Mean $rows "route_worker_jobs"
        route_wait_ms_per_call_mean =
            Get-G51Mean $rows "route_wait_ms_per_call"
        route_worker_ms_per_job_mean =
            Get-G51Mean $rows "route_worker_ms_per_job"
        prefill_vram_seed_gib_mean =
            Get-G51Mean $rows "prefill_vram_seed_gib"
        prefill_vram_seed_seconds_mean =
            Get-G51Mean $rows "prefill_vram_seed_seconds"
        windows_available_min_gib_mean =
            Get-G51Mean $rows "windows_available_min_gib"
        working_set_peak_gib_mean =
            Get-G51Mean $rows "working_set_peak_gib"
        private_peak_gib_mean = Get-G51Mean $rows "private_peak_gib"
        gpu_shared_peak_gib_mean =
            Get-G51Mean $rows "gpu_shared_peak_gib"
        gpu_dedicated_peak_gib_mean =
            Get-G51Mean $rows "gpu_dedicated_peak_gib"
        process_read_gib_mean = Get-G51Mean $rows "process_read_gib"
        process_write_gib_mean = Get-G51Mean $rows "process_write_gib"
        page_fault_delta_mean = Get-G51Mean $rows "page_fault_delta"
        aggregate_disk_read_gib_mean =
            Get-G51Mean $rows "aggregate_disk_read_gib"
        aggregate_disk_read_mib_per_second_mean =
            Get-G51Mean $rows "aggregate_disk_read_mib_per_second"
        aggregate_disk_read_throughput_mib_per_second_mean =
            Get-G51Mean $rows "aggregate_disk_read_throughput_mib_per_second"
        aggregate_disk_queue_length_peak_mean =
            Get-G51Mean $rows "aggregate_disk_queue_length_peak"
        contamination_abort_observed_count =
            @($rows | Where-Object { $_.contamination_abort_observed }).Count
        snapshot_misses_sum =
            ($rows | Measure-Object -Property snapshot_misses -Sum).Sum
        ssd_bytes_sum = ($rows | Measure-Object -Property ssd_bytes -Sum).Sum
        failures_sum = ($rows | Measure-Object -Property failures -Sum).Sum
    }
}

$observedEffect = $null
if (-not $SafetyOnly) {
    $controlSummary = @($armSummary | Where-Object {
        $_.arm -eq "control"
    })[0]
    $seedSummary = @($armSummary | Where-Object {
        $_.arm -eq "prefill-vram-seed"
    })[0]
    $routeH2DSavedGiB = [double]$controlSummary.route_h2d_gib_mean -
        [double]$seedSummary.route_h2d_gib_mean
    $seedCostGiB = [double]$seedSummary.prefill_vram_seed_gib_mean
    $netH2DSavedGiB = $routeH2DSavedGiB - $seedCostGiB
    $decodeDeltaPercent = if (
        [double]$controlSummary.decode_tokens_per_second_mean -ne 0.0) {
        100.0 * (
            [double]$seedSummary.decode_tokens_per_second_mean -
            [double]$controlSummary.decode_tokens_per_second_mean
        ) / [double]$controlSummary.decode_tokens_per_second_mean
    } else { $null }
    $observedEffect = [pscustomobject]@{
        window_generated_tokens = 64
        control_route_h2d_gib_mean =
            [double]$controlSummary.route_h2d_gib_mean
        seed_route_h2d_gib_mean = [double]$seedSummary.route_h2d_gib_mean
        route_h2d_saved_gib_mean = [math]::Round($routeH2DSavedGiB, 6)
        one_time_seed_h2d_gib_mean = [math]::Round($seedCostGiB, 6)
        net_h2d_saved_after_seed_gib_mean =
            [math]::Round($netH2DSavedGiB, 6)
        seed_amortized_within_observed_window = ($netH2DSavedGiB -gt 0.0)
        pinned_ram_routes_delta_mean = [math]::Round(
            [double]$seedSummary.route_pinned_ram_routes_mean -
            [double]$controlSummary.route_pinned_ram_routes_mean, 6)
        vram_routes_delta_mean = [math]::Round(
            [double]$seedSummary.route_vram_routes_mean -
            [double]$controlSummary.route_vram_routes_mean, 6)
        decode_tokens_per_second_delta_percent = if (
            $null -eq $decodeDeltaPercent) { $null } else {
            [math]::Round($decodeDeltaPercent, 6)
        }
        interpretation =
            "Measured n=3-per-arm deltas only; route H2D excludes the explicit one-time seed upload."
    }
}

$summary = [pscustomobject]@{
    schema = if ($SafetyOnly) {
        "g51_prefill_vram_seed_safety_v1"
    } else {
        "g51_prefill_vram_seed_ab_v2"
    }
    question = if ($SafetyOnly) {
        "Functional safety gate for request-scoped prefill VRAM seed; no A/B or performance verdict."
    } else {
        "Current fail-closed transport control versus request-scoped prefill VRAM seed of 8 experts per routed layer on the exact G45 cyberpunk prompt."
    }
    prompt = $prompt
    context = 256
    max_tokens = 64
    arena_gib = 30
    cache_experts = 320
    cache_reserve_gib = 0.125
    expected_content_sha256 = $expected
    safety_only = [bool]$SafetyOnly
    timing_valid = (-not [bool]$SafetyOnly -and
        -not [bool]$SkipSystemQuiescencePreflight)
    independent_processes_per_arm = if ($SafetyOnly) { $null } else { 3 }
    safety_independent_processes = if ($SafetyOnly) { 1 } else { 0 }
    within_process_repeats = 1
    system_file_cache_flushed_between_runs = $false
    order_contract = if ($SafetyOnly) {
        "safety-only candidate n=1; sequential-file/source-parts/workers1/trusted checksum/file-QD parameterized; timing_valid=false when system quiescence is explicitly skipped"
    } else {
        "counterbalanced order control,on,on,control,control,on; both arms sequential-file/source-parts/workers1/trusted checksum/file-QD parameterized"
    }
    order = @($runs | ForEach-Object { $_.tag })
    order_arm = @($runs | ForEach-Object { $_.arm })
    control_seed_per_layer = 0
    candidate_seed_per_layer = 8
    transport_config = [pscustomobject]@{
        schedule = "source-parts"
        source = "sequential-file"
        trusted_worker_checksum = $true
        copy_workers = 1
        sequential_workers = 1
        file_qd = $TransportFileQD
    }
    source = "sequential-file"
    copy_workers = 1
    sequential_workers = 1
    transport_file_qd = $TransportFileQD
    route_no_default_sync = $true
    q8_f16_cache = "disabled"
    excluded_features = @(
        "split-hit-miss", "SPEX", "static-mask", "trim", "diagnostics",
        "arena-wrap-part-profile", "arena-wrap-layout-profile")
    summarized_existing_results = [bool]$SummarizeExisting
    execution_runner_sha256 = $executionRunnerHashForRuns
    summary_runner_sha256 = Get-G51SHA256 $MyInvocation.MyCommand.Path
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
        transport_file_qd_requested = $runs[0].transport_file_qd_requested
        transport_file_qd_observed = $runs[0].transport_file_qd_observed
    }
    runs = $runs
    arm_summary = $armSummary
    observed_effect = $observedEffect
}

$summaryName = if ($SafetyOnly) {
    "g51_prefill_vram_seed_safety_result.json"
} else {
    "g51_prefill_vram_seed_ab_result.json"
}
$summaryPath = Join-Path $outdir $summaryName
$summary | ConvertTo-Json -Depth 10 |
    Set-Content -LiteralPath $summaryPath -Encoding UTF8
foreach ($arm in $armSummary) {
    Write-Host ("[g51] arm=" + $arm.arm +
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
Write-Host ("[g51] matrix complete: " + $summaryPath)
