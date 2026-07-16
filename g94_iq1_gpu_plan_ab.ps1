# G94 IQ1_S mixed GPU-plan A/B (PowerShell 5.1, ASCII).
param(
    [switch]$StaticCheckOnly,
    [switch]$Resume
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$harness = Join-Path $root "g7_measure.ps1"
$buildRunner = Join-Path $root "g7_build.ps1"
$runtimeMonitor = Join-Path $root "g7_runtime_monitor.ps1"
$outdir = Join-Path $root "g7_runs"
$executable = Join-Path $root "build\Release\ds4_server.exe"
$buildManifest = Join-Path $root "build\Release\g7_build_manifest.json"
$summaryPath = Join-Path $outdir "g94_iq1_gpu_plan_ab_result.json"

$model = "C:\ds4-models\ds4-2bit.gguf"
$expectedModelSHA256 =
    "efc7ed607ff27076e3e501fc3fefefa33c0ed8cf1eff483a2b7fdc0c2e616668"
$iq1Sidecar = "D:\ds4-models\DeepSeek-V4-Flash-IQ1_S-XL.gguf"
$expectedIq1SidecarSHA256 =
    "b049d1eb34c068f19ab007b33c22a7d758b578bf2b10d9276e79654f85d35047"
[UInt64]$expectedIq1SidecarBytes = 61540805344
$prompt = "Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document."
$expectedPromptSHA256 =
    "38f6ec5ee5403f59dd2418eb5d9a5a94a0f0da19df015060383bb1ae46003bb6"

$armPlan = @(
    @{ Tag = "g94_iq1_gpu_plan_off_n3"; Arm = "baseline-mixed"; Planner = $false },
    @{ Tag = "g94_iq1_gpu_plan_on_n3"; Arm = "gpu-plan-on"; Planner = $true }
)

function Get-G94SHA256 {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "G94 provenance file missing: $Path"
    }
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-G94Property {
    param([object]$Object, [string]$Name)
    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) {
        return $null
    }
    $Object.PSObject.Properties[$Name].Value
}

function Assert-G94Property {
    param(
        [Parameter(Mandatory=$true)][object]$Object,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Tag
    )
    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) {
        throw "G94 required field missing: tag=$Tag field=$Name"
    }
}

function Convert-G94BytesToGiB {
    param([object]$Value)
    if ($null -eq $Value) { return $null }
    [math]::Round(([double]$Value / 1GB), 6)
}

function Get-G94Mean {
    param([Parameter(Mandatory=$true)][object[]]$Rows,
          [Parameter(Mandatory=$true)][string]$Property)
    $values = @($Rows | ForEach-Object { $_.$Property } |
        Where-Object { $null -ne $_ } | ForEach-Object { [double]$_ })
    if ($values.Count -eq 0) { return $null }
    [math]::Round(($values | Measure-Object -Average).Average, 6)
}

function Get-G94Median {
    param([Parameter(Mandatory=$true)][object[]]$Rows,
          [Parameter(Mandatory=$true)][string]$Property)
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

function Test-G94HarnessParameter {
    param([Parameter(Mandatory=$true)][string]$ParameterName)
    $content = Get-Content -LiteralPath $harness -Raw
    return ($content -match ("\$" + [regex]::Escape($ParameterName) +
        "(\s|=|,|\))"))
}

function Assert-G94StaticContract {
    if (-not (Test-Path -LiteralPath $harness -PathType Leaf)) {
        throw "G94 harness missing: $harness"
    }
    if (-not (Test-Path -LiteralPath $runtimeMonitor -PathType Leaf)) {
        throw "G94 runtime monitor missing: $runtimeMonitor"
    }
    if (-not (Test-Path -LiteralPath $buildRunner -PathType Leaf)) {
        throw "G94 provenance build runner missing: $buildRunner"
    }
    foreach ($parameter in @(
        "WarmupMaxTokens", "Repeats", "BudgetGB", "ReserveMB",
        "DynamicArenaGiB", "ArenaWrapTrustWorkerChecksum",
        "ArenaWrapSourceParts", "ArenaWrapUnlockSourceRanges",
        "ArenaWrapUnlockWaveGiB", "PrefillMassObserve",
        "PrefillMassWrap", "ComposePrefillMassTiering",
        "DisableQ8F16Cache", "EmbedRowStaging", "ExpertCacheN",
        "ExpertCacheReserveGB", "ExpertCachePolicy", "ExpertTiering",
        "ExpertTierPolicy", "ExpertTierClockCalls",
        "ExpertTierReplacementBudget", "ExpertTierMinFrequency",
        "ExpertTierHysteresis", "GpuResidentRoutes",
        "RouteNoDefaultSync", "SplitFused", "ReapPrefetchThreads",
        "ExpectedModelSHA256", "Iq1SExpertSidecar",
        "ExpectedIq1SExpertSidecarSHA256",
        "ExpectedIq1SExpertSidecarBytes", "Iq1SLayerFirst",
        "Iq1SLayerLast", "Iq1SMixedColdOne", "Iq1SMixedGpuPlan",
        "Iq1SRamCacheGiB", "GateKind", "SkipSystemQuiescencePreflight",
        "Iq1SProfile")) {
        if (-not (Test-G94HarnessParameter -ParameterName $parameter)) {
            throw "Harness does not expose -$parameter; refusing to run."
        }
    }
    if ($expectedModelSHA256 -notmatch '^[0-9a-f]{64}$' -or
        $expectedIq1SidecarSHA256 -notmatch '^[0-9a-f]{64}$' -or
        $expectedPromptSHA256 -notmatch '^[0-9a-f]{64}$') {
        throw "G94 expected SHA-256 constants must be lowercase hex."
    }
    if ($expectedIq1SidecarBytes -le 0) {
        throw "G94 IQ1_S sidecar byte provenance is empty."
    }
}

function Invoke-G94BuildOnce {
    if (Test-Path -LiteralPath $executable -PathType Leaf) {
        Write-Host "[g94] build artifact exists; running single build refresh"
    } else {
        Write-Host "[g94] build artifact missing; running single build"
    }
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
        -File $buildRunner
    if ($LASTEXITCODE -ne 0) { throw "G94 build failed" }
    if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
        throw "G94 executable missing after build"
    }
}

function New-G94Args {
    param([Parameter(Mandatory=$true)][string]$Tag,
          [Parameter(Mandatory=$true)][bool]$Planner)
    $args = @(
        "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", $harness,
        "-Tag", $Tag,
        "-MaxTokens", "64",
        "-Warmup", "-WarmupMaxTokens", "64",
        "-Repeats", "3",
        "-TimeoutSec", "1800",
        "-Prompt", $prompt,
        "-Context", "256",
        "-BudgetGB", "2", "-ReserveMB", "1024",
        "-DynamicArenaGiB", "20",
        "-ArenaWrapTrustWorkerChecksum",
        "-ArenaWrapSourceParts",
        "-ArenaWrapUnlockSourceRanges",
        "-ArenaWrapUnlockWaveGiB", "4",
        "-DisableQ8F16Cache",
        "-EmbedRowStaging",
        "-PrefillMassWrap",
        "-ComposePrefillMassTiering",
        "-ExpertCacheN", "320",
        "-ExpertCacheReserveGB", "0.125",
        "-ExpertCachePolicy", "lru",
        "-ExpertTiering", "enforce",
        "-ExpertTierPolicy", "mass-lfru",
        "-ExpertTierClockCalls", "430",
        "-ExpertTierReplacementBudget", "32",
        "-ExpertTierMinFrequency", "3",
        "-ExpertTierHysteresis", "1.25",
        "-GpuResidentRoutes",
        "-RouteNoDefaultSync",
        "-SplitFused",
        "-ReapPrefetchThreads", "8",
        "-ModelPath", $model,
        "-ExpectedModelSHA256", $expectedModelSHA256,
        "-Iq1SExpertSidecar", $iq1Sidecar,
        "-ExpectedIq1SExpertSidecarSHA256", $expectedIq1SidecarSHA256,
        "-ExpectedIq1SExpertSidecarBytes", ([string]$expectedIq1SidecarBytes),
        "-Iq1SLayerFirst", "3",
        "-Iq1SLayerLast", "42",
        "-Iq1SMixedColdOne",
        "-Iq1SRamCacheGiB", "8",
        "-GateKind", "benchmark"
    )
    if ($Planner) { $args += "-Iq1SMixedGpuPlan" }
    return $args
}

function Assert-G94RunContract {
    param([Parameter(Mandatory=$true)][object]$Result,
          [Parameter(Mandatory=$true)][string]$Tag,
          [Parameter(Mandatory=$true)][string]$Arm,
          [Parameter(Mandatory=$true)][bool]$PlannerExpected,
          [Parameter(Mandatory=$true)][object]$Provenance)

    $tier = $Result.expert_tiering
    $mem = $Result.memory_preflight
    $proc = $Result.process_isolation_preflight
    $sys = $Result.system_quiescence_preflight
    $rt = $Result.runtime_telemetry

    foreach ($name in @(
        "server_exit_code", "model_sha256", "model_bytes",
        "iq1_s_sidecar_sha256", "iq1_s_sidecar_bytes",
        "iq1_s_mixed_runtime_observed", "iq1_s_mixed_calls",
        "iq1_s_mixed_hot_main", "iq1_s_mixed_cold_iq1",
        "iq1_s_mixed_failures", "iq1_s_mixed_gpu_plan_requested",
        "iq1_s_mixed_gpu_plan_runtime_observed",
        "iq1_s_mixed_gpu_plan_calls",
        "iq1_s_mixed_gpu_plan_failures", "prefill_mass_observe_requested",
        "prefill_mass_wrap_requested", "prefill_mass_wrap_observed",
        "prefill_mass_wrap_result", "prefill_mass_wrap_reason",
        "prefill_mass_wrap_mask", "arena_wrap_unlock_source_ranges_requested",
        "arena_wrap_unlock_wave_gib_requested",
        "arena_wrap_unlock_source_ranges_observed",
        "arena_wrap_schedule_requested", "arena_wrap_schedule_observed",
        "arena_wrap_checksum_observed", "gpu_resident_routes_requested",
        "gpu_resident_routes_observed", "gpu_resident_routes_errors",
        "route_no_default_sync_requested", "split_fused_requested",
        "split_fused_observed")) {
        Assert-G94Property -Object $Result -Name $name -Tag $Tag
    }

    $systemQuiescenceSkipped = [bool](Get-G94Property $sys "skipped")
    $contentHashes = @($Result.results | ForEach-Object {
        [string]$_.content_sha256
    })
    if ($contentHashes.Count -ne 3) {
        throw "G94 repeat count mismatch: tag=$Tag"
    }
    foreach ($hash in $contentHashes) {
        if ($hash -notmatch '^[0-9a-fA-F]{64}$') {
            throw "G94 invalid repeat content hash: tag=$Tag"
        }
    }

    if ($Result.tag -ne $Tag -or
        $Result.prompt -ne $prompt -or
        $Result.prompt_sha256 -ne $expectedPromptSHA256 -or
        $Result.warmup_prompt_sha256 -ne $expectedPromptSHA256 -or
        $Result.model -ne $model -or
        $Result.model_sha256 -ne $expectedModelSHA256 -or
        [UInt64]$Result.model_bytes -le 0 -or
        $Result.iq1_s_sidecar -ne $iq1Sidecar -or
        $Result.iq1_s_sidecar_sha256 -ne $expectedIq1SidecarSHA256 -or
        [UInt64]$Result.iq1_s_sidecar_bytes -ne $expectedIq1SidecarBytes -or
        [int]$Result.server_exit_code -ne 0 -or
        $Result.gate_kind -ne "benchmark" -or
        [bool]$Result.diagnostics -or
        [bool]$Result.iq1_s_profile_requested -or
        [int]$Result.repeats -ne 3 -or
        [bool]$Result.warmup -ne $true -or
        [int]$Result.requested_max_tokens -ne 64 -or
        [int]$Result.requested_warmup_max_tokens -ne 64 -or
        [int]$Result.context_requested -ne 256 -or
        [int]$Result.context_observed -ne 256 -or
        [int]$Result.budget_gb -ne 2 -or
        [int]$Result.reserve_mb -ne 1024 -or
        [double]$Result.dynamic_arena_gib_requested -ne 20.0 -or
        [bool]$Result.q8_f16_cache_disabled -ne $true -or
        [bool]$Result.embed_row_staging_requested -ne $true -or
        [bool]$Result.outputs_identical -ne $true -or
        [bool]$Result.non_identical_repeat_outputs_allowed -ne $false -or
        [bool]$Result.arena_wrap_trust_worker_checksum_requested -ne $true -or
        [string]$Result.arena_wrap_schedule_requested -ne "source-parts" -or
        [string]$Result.arena_wrap_schedule_observed -ne "source-parts" -or
        [string]$Result.arena_wrap_source_requested -ne "mmap" -or
        [string]$Result.arena_wrap_source_observed -ne "mmap" -or
        [string]$Result.arena_wrap_checksum_observed -ne
            "fnv1a64-worker-only" -or
        [bool]$Result.arena_wrap_unlock_source_ranges_requested -ne $true -or
        [double]$Result.arena_wrap_unlock_wave_gib_requested -ne 4.0 -or
        [bool]$Result.arena_wrap_unlock_source_ranges_observed -ne $true -or
        [bool]$Result.prefill_mass_observe_requested -ne $false -or
        [bool]$Result.prefill_mass_wrap_requested -ne $true -or
        [bool]$Result.prefill_mass_wrap_observed -ne $true -or
        [string]$Result.prefill_mass_wrap_result -ne "published" -or
        [string]$Result.prefill_mass_wrap_reason -ne "ok" -or
        [string]$Result.prefill_mass_wrap_mask -ne "request-scoped-closed" -or
        [bool]$Result.compose_prefill_mass_tiering_requested -ne $true -or
        [bool]$tier.compose_prefill_mass_tiering_observed -ne $true -or
        [int]$Result.expert_cache_requested -ne 320 -or
        [double]$Result.expert_cache_reserve_gb -ne 0.125 -or
        [string]$Result.expert_cache_policy -ne "lru" -or
        [string]$Result.expert_tiering_requested -ne "enforce" -or
        [string]$Result.expert_tier_policy_requested -ne "mass-lfru" -or
        [int]$Result.expert_tier_clock_calls_requested -ne 430 -or
        [int]$Result.expert_tier_replacement_budget_requested -ne 32 -or
        [int]$Result.expert_tier_min_frequency_requested -ne 3 -or
        [double]$Result.expert_tier_hysteresis_requested -ne 1.25 -or
        [string]$tier.mode -ne "enforce" -or
        [string]$tier.policy -ne "mass-lfru" -or
        [int]$tier.clock_calls -ne 430 -or
        [int]$tier.replacement_budget -ne 32 -or
        [int]$tier.min_frequency -ne 3 -or
        [double]$tier.hysteresis -ne 1.25 -or
        [UInt64]$tier.failures -ne 0 -or
        [UInt64]$tier.forbidden_cold_ssd_to_vram -ne 0 -or
        [bool]$Result.gpu_resident_routes_requested -ne $true -or
        [bool]$Result.gpu_resident_routes_observed -ne $true -or
        [bool]$Result.route_no_default_sync_requested -ne $true -or
        [UInt64]$Result.gpu_resident_routes_default_sync_calls -ne 0 -or
        [UInt64]$Result.gpu_resident_routes_no_default_sync_calls -ne
            [UInt64]$Result.gpu_resident_routes_calls -or
        [UInt64]$Result.gpu_resident_routes_errors -ne 0 -or
        [bool]$Result.split_fused_requested -ne $true -or
        [bool]$Result.split_fused_observed -ne $true -or
        [bool]$Result.split_hit_miss_requested -ne $false -or
        [int]$Result.reap_prefetch_threads_requested -ne 8 -or
        [bool]$Result.iq1_s_mixed_cold_one -ne $true -or
        [bool]$Result.iq1_s_mixed_runtime_observed -ne $true -or
        [int]$Result.iq1_s_mixed_last_slot -ne 5 -or
        [UInt64]$Result.iq1_s_mixed_hot_main -ne
            (5 * [UInt64]$Result.iq1_s_mixed_cold_iq1) -or
        [UInt64]$Result.iq1_s_mixed_failures -ne 0 -or
        [int]$Result.iq1_s_mixed_last_layer -ne 42 -or
        [string]$Result.effective_ds4_environment.DS4_IQ1_S_LAYER_FIRST -ne
            "3" -or
        [string]$Result.effective_ds4_environment.DS4_IQ1_S_LAYER_LAST -ne
            "42" -or
        [double]$Result.iq1_s_ram_cache_requested_gib -ne 8.0 -or
        [bool]$Result.iq1_s_ram_cache_runtime_observed -ne $true -or
        [UInt64]$Result.iq1_s_ram_cache_failures -ne 0 -or
        [bool]$Result.iq1_s_mixed_gpu_plan_requested -ne
            $PlannerExpected -or
        [bool]$Result.iq1_s_mixed_gpu_plan_runtime_observed -ne
            $PlannerExpected -or
        ($PlannerExpected -and
            [UInt64]$Result.iq1_s_mixed_gpu_plan_calls -le 0) -or
        ((-not $PlannerExpected) -and
            [UInt64]$Result.iq1_s_mixed_gpu_plan_calls -ne 0) -or
        [UInt64]$Result.iq1_s_mixed_gpu_plan_failures -ne 0 -or
        [bool]$Result.iq1_s_profile_requested -ne $false -or
        [bool]$Result.iq1_s_packed_h2d_requested -ne $false -or
        [bool]$Result.iq1_s_no_main_sync_requested -ne $false -or
        [bool]$Result.spex_dry_run_requested -ne $false -or
        [bool]$Result.spex_observed -ne $false -or
        [bool]$mem.ready_to_launch -ne $true -or
        [bool]$proc.ready_to_launch -ne $true -or
        $systemQuiescenceSkipped -ne $false -or
        [bool]$sys.ready_to_launch -ne $true -or
        [bool]$rt.contamination_abort_observed -ne $false -or
        [string]$Result.contamination_reason -ne "" -or
        [bool]$Result.quality_eligible -ne $true -or
        [bool]$Result.sota_eligible -ne $true -or
        [double]$rt.contamination_runtime_minimum_available_gib -ne 2.0 -or
        [double]$rt.contamination_runtime_maximum_disk_queue_length -ne 8.0 -or
        [int]$rt.contamination_runtime_consecutive_samples -ne 3 -or
        $Result.executable_sha256 -ne $Provenance.executable_sha256 -or
        $Result.harness_sha256 -ne $Provenance.harness_sha256 -or
        $Result.runtime_monitor_harness_sha256 -ne
            $Provenance.runtime_monitor_harness_sha256 -or
        $Result.ds4_cuda_sha256 -ne $Provenance.ds4_cuda_sha256 -or
        $Result.ds4_c_sha256 -ne $Provenance.ds4_c_sha256 -or
        $Result.ds4_server_c_sha256 -ne $Provenance.ds4_server_c_sha256 -or
        $Result.build_manifest_sha256 -ne $Provenance.build_manifest_sha256) {
        throw "G94 contract mismatch: tag=$Tag arm=$Arm"
    }
}

function Invoke-G94Arm {
    param([Parameter(Mandatory=$true)][string]$Tag,
          [Parameter(Mandatory=$true)][string]$Arm,
          [Parameter(Mandatory=$true)][bool]$Planner,
          [Parameter(Mandatory=$true)][object]$Provenance)

    $resultPath = Join-Path $outdir ("g7_" + $Tag + "_result.json")
    $rawPath = Join-Path $outdir ("g7_" + $Tag + "_raw_outputs.json")
    $failurePath = Join-Path $outdir ("g7_" + $Tag + "_failure.json")
    $args = New-G94Args -Tag $Tag -Planner $Planner

    if ($Resume -and (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        Write-Host ("[g94] resume validate tag=" + $Tag + " arm=" + $Arm)
    } else {
        Write-Host ("[g94] start tag=" + $Tag + " arm=" + $Arm)
        & powershell.exe @args | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) { throw "G94 arm failed: $Tag" }
    }

    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        throw "G94 result missing: tag=$Tag"
    }
    if (-not (Test-Path -LiteralPath $rawPath -PathType Leaf)) {
        throw "G94 raw outputs missing: tag=$Tag"
    }
    if (Test-Path -LiteralPath $failurePath -PathType Leaf) {
        throw "G94 failure artifact present: tag=$Tag path=$failurePath"
    }

    $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    Assert-G94RunContract -Result $result -Tag $Tag -Arm $Arm `
        -PlannerExpected $Planner -Provenance $Provenance
    $tier = $result.expert_tiering
    $rt = $result.runtime_telemetry

    [pscustomobject]@{
        tag = $Tag
        arm = $Arm
        planner = [bool]$Planner
        result_path = $resultPath
        raw_outputs_path = $rawPath
        head = $result.head
        executable_sha256 = $result.executable_sha256
        ds4_cuda_sha256 = $result.ds4_cuda_sha256
        ds4_c_sha256 = $result.ds4_c_sha256
        ds4_server_c_sha256 = $result.ds4_server_c_sha256
        build_manifest_sha256 = $result.build_manifest_sha256
        build_input_fingerprint_sha256 =
            $result.build_manifest_input_fingerprint_sha256
        harness_sha256 = $result.harness_sha256
        runtime_monitor_harness_sha256 =
            $result.runtime_monitor_harness_sha256
        model = $result.model
        model_bytes = [UInt64]$result.model_bytes
        model_sha256 = $result.model_sha256
        iq1_s_sidecar = $result.iq1_s_sidecar
        iq1_s_sidecar_bytes = [UInt64]$result.iq1_s_sidecar_bytes
        iq1_s_sidecar_sha256 = $result.iq1_s_sidecar_sha256
        server_exit_code = [int]$result.server_exit_code
        repeat_count = [int]$result.results.Count
        content_sha256_by_repeat = @($result.results | ForEach-Object {
            [string]$_.content_sha256
        })
        warmup_content_sha256 = [string]$result.warmup_result.content_sha256
        outputs_identical = [bool]$result.outputs_identical
        mean_tokens_per_second = [double]$result.mean_tokens_per_second
        min_tokens_per_second = [double]$result.min_tokens_per_second
        max_tokens_per_second = [double]$result.max_tokens_per_second
        server_decode_mean_tokens_per_second =
            [double]$result.server_decode_mean_tokens_per_second
        server_decode_min_tokens_per_second =
            [double]$result.server_decode_min_tokens_per_second
        server_decode_max_tokens_per_second =
            [double]$result.server_decode_max_tokens_per_second
        server_prefill_ttft_mean_seconds =
            [double]$result.server_prefill_ttft_mean_seconds
        warmup_seconds = [double]$result.warmup_seconds
        load_seconds = [double]$result.load_seconds
        iq1_s_mixed_calls = [UInt64]$result.iq1_s_mixed_calls
        iq1_s_mixed_hot_main = [UInt64]$result.iq1_s_mixed_hot_main
        iq1_s_mixed_cold_iq1 = [UInt64]$result.iq1_s_mixed_cold_iq1
        iq1_s_mixed_gpu_plan_calls =
            [UInt64]$result.iq1_s_mixed_gpu_plan_calls
        iq1_s_mixed_gpu_plan_wait_ms =
            [double]$result.iq1_s_mixed_gpu_plan_wait_ms
        iq1_s_mixed_failures = [UInt64]$result.iq1_s_mixed_failures
        iq1_s_mixed_gpu_plan_failures =
            [UInt64]$result.iq1_s_mixed_gpu_plan_failures
        iq1_s_ram_cache_hits = [UInt64]$result.iq1_s_ram_cache_hits
        iq1_s_ram_cache_misses = [UInt64]$result.iq1_s_ram_cache_misses
        iq1_s_ram_cache_hit_rate = [double]$result.iq1_s_ram_cache_hit_rate
        split_fused_calls = [UInt64]$result.split_fused_calls
        split_fused_hits = [UInt64]$result.split_fused_hits
        split_fused_misses = [UInt64]$result.split_fused_misses
        route_calls = [UInt64]$result.gpu_resident_routes_calls
        route_worker_jobs = [UInt64]$result.gpu_resident_routes_worker_jobs
        route_miss_experts = [UInt64]$result.gpu_resident_routes_miss_experts
        route_worker_ms_per_job =
            [double]$result.gpu_resident_routes_worker_ms_per_job
        route_wait_ms_per_call =
            [double]$result.gpu_resident_routes_wait_ms_per_call
        route_errors = [UInt64]$result.gpu_resident_routes_errors
        tier_failures = [UInt64]$tier.failures
        tier_vram_hits = [UInt64]$tier.vram_hits
        tier_ram_hits = [UInt64]$tier.ram_hits
        tier_ram_h2d_gib = Convert-G94BytesToGiB $tier.ram_h2d_bytes
        arena_wrap_seconds =
            [double]$result.arena_wrap_profile_total_seconds
        prefill_mass_wrap_seconds =
            [double]$result.prefill_mass_wrap_seconds
        process_read_gib =
            Convert-G94BytesToGiB $rt.win32_process_read_transfer_delta_bytes
        aggregate_disk_read_gib =
            Convert-G94BytesToGiB $rt.aggregate_disk_read_bytes_estimated
        aggregate_disk_queue_length_peak =
            Get-G94Property $rt "aggregate_disk_queue_length_peak"
        windows_available_min_gib =
            Convert-G94BytesToGiB $rt.windows_available_min_bytes
        gpu_dedicated_peak_gib =
            Convert-G94BytesToGiB $rt.gpu_process_dedicated_peak_bytes
        gpu_shared_peak_gib =
            Convert-G94BytesToGiB $rt.gpu_process_shared_peak_bytes
        working_set_peak_gib =
            Convert-G94BytesToGiB $rt.process_working_set_peak_bytes
        clean = $true
    }
}

New-Item -ItemType Directory -Force -Path $outdir | Out-Null
Assert-G94StaticContract

$selfSha = Get-G94SHA256 $MyInvocation.MyCommand.Path
$staticChecks = [pscustomobject]@{
    script_parse_ok = $true
    harness_present = (Test-Path -LiteralPath $harness -PathType Leaf)
    runtime_monitor_present =
        (Test-Path -LiteralPath $runtimeMonitor -PathType Leaf)
    static_check_only = [bool]$StaticCheckOnly
    resume = [bool]$Resume
    no_gpu_or_ds4_launch_in_static_check = [bool]$StaticCheckOnly
    required_repeats_per_arm = 3
    build_once_in_normal_mode = $true
    no_profile = $true
    quiescence_required = $true
    no_quality_or_general_sota_claim = $true
    runner_sha256 = $selfSha
}

if ($StaticCheckOnly) {
    Write-Host "[g94] static check OK; no build, GPU, DS4, or benchmark launched."
    $staticChecks | ConvertTo-Json -Depth 5
    return
}

Invoke-G94BuildOnce
$provenance = [pscustomobject]@{
    executable_sha256 = Get-G94SHA256 $executable
    harness_sha256 = Get-G94SHA256 $harness
    runtime_monitor_harness_sha256 = Get-G94SHA256 $runtimeMonitor
    ds4_cuda_sha256 = Get-G94SHA256 (Join-Path $root "ds4_cuda.cu")
    ds4_c_sha256 = Get-G94SHA256 (Join-Path $root "ds4.c")
    ds4_server_c_sha256 = Get-G94SHA256 (Join-Path $root "ds4_server.c")
    build_manifest_sha256 = Get-G94SHA256 $buildManifest
}

$runs = @()
foreach ($item in $armPlan) {
    $runs += Invoke-G94Arm -Tag $item.Tag -Arm $item.Arm `
        -Planner ([bool]$item.Planner) -Provenance $provenance
}

foreach ($field in @(
    "head", "executable_sha256", "ds4_cuda_sha256", "ds4_c_sha256",
    "ds4_server_c_sha256", "build_manifest_sha256",
    "build_input_fingerprint_sha256", "harness_sha256",
    "runtime_monitor_harness_sha256", "model", "model_bytes",
    "model_sha256", "iq1_s_sidecar", "iq1_s_sidecar_bytes",
    "iq1_s_sidecar_sha256", "server_exit_code", "repeat_count",
    "outputs_identical", "warmup_content_sha256")) {
    $values = @($runs | ForEach-Object { [string]($_.$field) } |
        Select-Object -Unique)
    if ($values.Count -ne 1) {
        throw "G94 mixed provenance/settings across arms: field=$field"
    }
}

$off = @($runs | Where-Object { $_.planner -eq $false })[0]
$on = @($runs | Where-Object { $_.planner -eq $true })[0]
if ($off.repeat_count -lt 3 -or $on.repeat_count -lt 3) {
    throw "G94 n>=3 requirement not met."
}
for ($i = 0; $i -lt 3; $i++) {
    if ([string]$off.content_sha256_by_repeat[$i] -ne
        [string]$on.content_sha256_by_repeat[$i]) {
        throw ("G94 per-repeat output hash mismatch at repeat " + ($i + 1))
    }
}
if ($off.iq1_s_mixed_gpu_plan_calls -ne 0 -or
    $on.iq1_s_mixed_gpu_plan_calls -le 0) {
    throw "G94 planner marker isolation failed."
}

$armSummary = @()
foreach ($planner in @($false, $true)) {
    $rows = @($runs | Where-Object { $_.planner -eq $planner })
    if ($rows.Count -ne 1 -or [int]$rows[0].repeat_count -ne 3) {
        throw "G94 arm replication mismatch."
    }
    $armSummary += [pscustomobject]@{
        arm = $rows[0].arm
        planner = [bool]$planner
        independent_processes = 1
        repeats = [int]$rows[0].repeat_count
        mean_tokens_per_second = $rows[0].mean_tokens_per_second
        server_decode_mean_tokens_per_second =
            $rows[0].server_decode_mean_tokens_per_second
        server_prefill_ttft_mean_seconds =
            $rows[0].server_prefill_ttft_mean_seconds
        warmup_seconds = $rows[0].warmup_seconds
        arena_wrap_seconds = $rows[0].arena_wrap_seconds
        prefill_mass_wrap_seconds = $rows[0].prefill_mass_wrap_seconds
        planner_calls = $rows[0].iq1_s_mixed_gpu_plan_calls
        planner_wait_ms = $rows[0].iq1_s_mixed_gpu_plan_wait_ms
        iq1_s_ram_cache_hit_rate = $rows[0].iq1_s_ram_cache_hit_rate
        route_worker_ms_per_job = $rows[0].route_worker_ms_per_job
        route_wait_ms_per_call = $rows[0].route_wait_ms_per_call
        tier_ram_h2d_gib = $rows[0].tier_ram_h2d_gib
        process_read_gib = $rows[0].process_read_gib
        aggregate_disk_read_gib = $rows[0].aggregate_disk_read_gib
        aggregate_disk_queue_length_peak =
            $rows[0].aggregate_disk_queue_length_peak
        clean = [bool]$rows[0].clean
    }
}

$bothClean = @($runs | Where-Object { -not $_.clean }).Count -eq 0
$decodeDeltaPercent = if ($bothClean -and
    [double]$off.server_decode_mean_tokens_per_second -ne 0.0) {
    [math]::Round(
        100.0 * ([double]$on.server_decode_mean_tokens_per_second -
        [double]$off.server_decode_mean_tokens_per_second) /
        [double]$off.server_decode_mean_tokens_per_second, 6)
} else { $null }
$harnessDeltaPercent = if ($bothClean -and
    [double]$off.mean_tokens_per_second -ne 0.0) {
    [math]::Round(
        100.0 * ([double]$on.mean_tokens_per_second -
        [double]$off.mean_tokens_per_second) /
        [double]$off.mean_tokens_per_second, 6)
} else { $null }

$performanceVerdict = if ($bothClean -and
    $off.repeat_count -ge 3 -and $on.repeat_count -ge 3) {
    if ($decodeDeltaPercent -gt 0.0) {
        "gpu-plan-on faster on clean benchmark n=3 repeats per arm"
    } elseif ($decodeDeltaPercent -lt 0.0) {
        "gpu-plan-on slower on clean benchmark n=3 repeats per arm"
    } else {
        "no decode throughput delta on clean benchmark n=3 repeats per arm"
    }
} else {
    "withheld: both arms must be clean with n>=3"
}

$summary = [pscustomobject]@{
    schema = "g94_iq1_gpu_plan_ab_v1"
    question = "Current mixed IQ1_S baseline with GPU planner OFF versus identical setup with -Iq1SMixedGpuPlan ON."
    gate_kind = "benchmark"
    quality_claim = "none"
    general_sota_claim = "none"
    prompt = $prompt
    prompt_sha256 = $expectedPromptSHA256
    max_tokens = 64
    context = 256
    warmup_max_tokens = 64
    repeats_per_arm = 3
    budget_gb = 2
    reserve_mb = 1024
    dynamic_arena_gib = 20
    iq1_s_ram_cache_gib = 8
    iq1_s_layers = "3..42"
    mixed_cold_one = $true
    q8_f16_cache = "disabled"
    embed_row_staging = $true
    arena_wrap = [pscustomobject]@{
        schedule = "source-parts"
        source = "mmap"
        trust_worker_checksum = $true
        unlock_source_ranges = $true
        unlock_wave_gib = 4
    }
    prefill_mass = [pscustomobject]@{
        explicit_observe = $false
        wrap = $true
        compose_tiering = $true
    }
    expert_cache = [pscustomobject]@{
        cache_n = 320
        reserve_gib = 0.125
        policy = "lru"
    }
    expert_tiering = [pscustomobject]@{
        mode = "enforce"
        policy = "mass-lfru"
        clock_calls = 430
        replacement_budget = 32
        min_frequency = 3
        hysteresis = 1.25
    }
    route = [pscustomobject]@{
        gpu_resident_routes = $true
        route_no_default_sync = $true
        split_fused = $true
        reap_prefetch_threads = 8
    }
    model_provenance = [pscustomobject]@{
        path = $model
        sha256 = $expectedModelSHA256
        bytes = $runs[0].model_bytes
    }
    iq1_s_sidecar_provenance = [pscustomobject]@{
        path = $iq1Sidecar
        sha256 = $expectedIq1SidecarSHA256
        bytes = $expectedIq1SidecarBytes
    }
    order = @($runs | ForEach-Object { $_.tag })
    order_arm = @($runs | ForEach-Object { $_.arm })
    raw_json_preserved = @($runs | ForEach-Object { $_.raw_outputs_path })
    result_json_preserved = @($runs | ForEach-Object { $_.result_path })
    runner_sha256 = $selfSha
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
    }
    checks = [pscustomobject]@{
        same_provenance_settings = $true
        clean_quiescence = $bothClean
        zero_failures = $bothClean
        n_ge_3_each_arm = ($off.repeat_count -ge 3 -and
            $on.repeat_count -ge 3)
        per_repeat_output_hashes_identical = $true
        mixed_5_to_1 = $true
        planner_marker_only_in_on_arm = $true
        profile_disabled = $true
    }
    runs = $runs
    arm_summary = $armSummary
    deltas = [pscustomobject]@{
        gpu_plan_on_minus_off_decode_tps =
            [math]::Round([double]$on.server_decode_mean_tokens_per_second -
            [double]$off.server_decode_mean_tokens_per_second, 6)
        gpu_plan_on_minus_off_decode_tps_percent = $decodeDeltaPercent
        gpu_plan_on_minus_off_harness_tps =
            [math]::Round([double]$on.mean_tokens_per_second -
            [double]$off.mean_tokens_per_second, 6)
        gpu_plan_on_minus_off_harness_tps_percent = $harnessDeltaPercent
        gpu_plan_on_minus_off_ttft_seconds =
            [math]::Round([double]$on.server_prefill_ttft_mean_seconds -
            [double]$off.server_prefill_ttft_mean_seconds, 6)
        gpu_plan_on_minus_off_route_wait_ms_per_call =
            [math]::Round([double]$on.route_wait_ms_per_call -
            [double]$off.route_wait_ms_per_call, 6)
        gpu_plan_on_minus_off_tier_ram_h2d_gib =
            [math]::Round([double]$on.tier_ram_h2d_gib -
            [double]$off.tier_ram_h2d_gib, 6)
    }
    performance_verdict = $performanceVerdict
}

$summary | ConvertTo-Json -Depth 10 |
    Set-Content -LiteralPath $summaryPath -Encoding UTF8
Write-Host ("[g94] matrix complete: " + $summaryPath)
