# G98 IQ1_S promotion performance A/B (PowerShell 5.1, ASCII).
param(
    [switch]$StaticCheckOnly,
    [switch]$Resume,
    [ValidateRange(1, 512)][int]$PromotionSlots = 16
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$harness = Join-Path $root "g7_measure.ps1"
$runtimeMonitor = Join-Path $root "g7_runtime_monitor.ps1"
$outdir = Join-Path $root "g7_runs"
$executable = Join-Path $root "build\Release\ds4_server.exe"
$buildManifest = Join-Path $root "build\Release\g7_build_manifest.json"

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

$summaryPath = Join-Path $outdir "g98_iq1_promotion_perf_ab_result.json"
$armPlan = @(
    @{ Tag = "g98_iq1_promotion_off_n3"; Arm = "control-promotion-off"; Promotion = $false },
    @{ Tag = "g98_iq1_promotion_slots16_n3"; Arm = "candidate-promotion-slots16"; Promotion = $true }
)

function Get-G98SHA256 {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "G98 provenance file missing: $Path"
    }
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-G98Property {
    param([object]$Object, [string]$Name)
    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) {
        return $null
    }
    $Object.PSObject.Properties[$Name].Value
}

function Assert-G98Property {
    param(
        [Parameter(Mandatory=$true)][object]$Object,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Tag
    )
    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) {
        throw "G98 required field missing: tag=$Tag field=$Name"
    }
}

function Convert-G98BytesToGiB {
    param([object]$Value)
    if ($null -eq $Value) { return $null }
    [math]::Round(([double]$Value / 1GB), 6)
}

function Test-G98HarnessParameter {
    param([Parameter(Mandatory=$true)][string]$ParameterName)
    $content = Get-Content -LiteralPath $harness -Raw
    return ($content -match ("\$" + [regex]::Escape($ParameterName) +
        "(\s|=|,|\))"))
}

function Get-G98ComparableArgs {
    param([Parameter(Mandatory=$true)][object[]]$Args)
    $normalized = @()
    for ($i = 0; $i -lt $Args.Count; $i++) {
        $value = [string]$Args[$i]
        if ($value -eq "-Tag") {
            $i++
            continue
        }
        if ($value -eq "-Iq1Promotion") {
            continue
        }
        if ($value -eq "-Iq1PromotionProbationSlots") {
            $i++
            continue
        }
        $normalized += $value
    }
    return $normalized
}

function Assert-G98StaticContract {
    if (-not (Test-Path -LiteralPath $harness -PathType Leaf)) {
        throw "G98 harness missing: $harness"
    }
    if (-not (Test-Path -LiteralPath $runtimeMonitor -PathType Leaf)) {
        throw "G98 runtime monitor missing: $runtimeMonitor"
    }
    foreach ($parameter in @(
        "WarmupMaxTokens", "Repeats", "BudgetGB", "ReserveMB",
        "DynamicArenaGiB", "ArenaWrapTrustWorkerChecksum",
        "ArenaWrapSourceParts", "ArenaWrapUnlockSourceRanges",
        "ArenaWrapUnlockWaveGiB", "PrefillMassWrap",
        "ComposePrefillMassTiering", "ComposePrefillMassOpenRouter",
        "ComposePrefillMassReserveSlots",
        "DisableQ8F16Cache",
        "EmbedRowStaging", "ExpertCacheN", "ExpertCacheReserveGB",
        "ExpertCachePolicy", "ExpertTiering", "ExpertTierPolicy",
        "ExpertTierClockCalls", "ExpertTierReplacementBudget",
        "ExpertTierMinFrequency", "ExpertTierHysteresis",
        "GpuResidentRoutes", "RouteNoDefaultSync", "RoutePackedCopy",
        "SplitFused", "ReapPrefetchThreads", "ExpectedModelSHA256",
        "Iq1SExpertSidecar", "ExpectedIq1SExpertSidecarSHA256",
        "ExpectedIq1SExpertSidecarBytes", "Iq1SLayerFirst",
        "Iq1SLayerLast", "Iq1SMixedColdOne", "Iq1SMixedGpuPlan",
        "Iq1Promotion", "Iq1PromotionProbationSlots",
        "Iq1SRamCacheGiB", "GateKind", "QuiescenceCooldownSec",
        "RuntimeMinimumAvailableGiB", "RuntimeMaximumDiskQueueLength",
        "RuntimeContaminationSamples")) {
        if (-not (Test-G98HarnessParameter -ParameterName $parameter)) {
            throw "Harness does not expose -$parameter; refusing to run."
        }
    }

    $harnessText = Get-Content -LiteralPath $harness -Raw
    foreach ($requiredText in @(
        "temperature = 0",
        "think = `$false",
        "runtime-contamination-abort",
        "DS4_IQ1_PROMOTION_PROBATION_SLOTS",
        "DS4_CUDA_PREFILL_TIER_ROUTER",
        "DS4_CUDA_PREFILL_TIER_RESERVE_SLOTS",
        "compose_prefill_mass_open_router_requested",
        "compose_prefill_mass_reserve_slots_requested",
        "iq1-promotion",
        "promotion_2bit_ssd_seconds",
        "iq1_promotion_runtime_observed",
        "route_packed_copy_requested")) {
        if ($harnessText -notmatch [regex]::Escape($requiredText)) {
            throw "G98 harness static marker missing: $requiredText"
        }
    }
    if ($expectedModelSHA256 -notmatch '^[0-9a-f]{64}$' -or
        $expectedIq1SidecarSHA256 -notmatch '^[0-9a-f]{64}$' -or
        $expectedPromptSHA256 -notmatch '^[0-9a-f]{64}$' -or
        $expectedIq1SidecarBytes -le 0) {
        throw "G98 provenance constants are invalid."
    }

    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $PSCommandPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
    if ($parseErrors -and $parseErrors.Count -gt 0) {
        throw "G98 AST parse failed: $($parseErrors[0].Message)"
    }

    $controlArgs = New-G98Args -Tag "static_control" -Promotion $false
    $candidateArgs = New-G98Args -Tag "static_candidate" -Promotion $true
    $controlComparable = @(Get-G98ComparableArgs -Args $controlArgs)
    $candidateComparable = @(Get-G98ComparableArgs -Args $candidateArgs)
    if (($controlComparable -join "`n") -ne ($candidateComparable -join "`n")) {
        throw "G98 static diff failed: arms differ outside promotion flags/tag."
    }
    if (@($controlArgs | Where-Object { $_ -eq "-Iq1Promotion" }).Count -ne 0) {
        throw "G98 static diff failed: control enables promotion."
    }
    if (@($candidateArgs | Where-Object { $_ -eq "-Iq1Promotion" }).Count -ne 1) {
        throw "G98 static diff failed: candidate does not enable promotion exactly once."
    }
    if (@($candidateArgs | Where-Object { $_ -eq "-ComposePrefillMassOpenRouter" }).Count -ne 1) {
        throw "G98 static diff failed: candidate does not enable open-router promotion exactly once."
    }
    if (@($controlArgs | Where-Object { $_ -eq "-ComposePrefillMassOpenRouter" }).Count -ne 1) {
        throw "G98 static diff failed: control does not enable open-router baseline exactly once."
    }
    if (@($controlArgs | Where-Object { $_ -eq "-ComposePrefillMassReserveSlots" }).Count -ne 1 -or
        @($candidateArgs | Where-Object { $_ -eq "-ComposePrefillMassReserveSlots" }).Count -ne 1) {
        throw "G98 static diff failed: an arm does not reserve matched open-router capacity exactly once."
    }
}

function New-G98Args {
    param([Parameter(Mandatory=$true)][string]$Tag,
          [Parameter(Mandatory=$true)][bool]$Promotion)
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
        "-DynamicArenaGiB", "12",
        "-ArenaWrapTrustWorkerChecksum",
        "-ArenaWrapSourceParts",
        "-ArenaWrapUnlockSourceRanges",
        "-ArenaWrapUnlockWaveGiB", "4",
        "-DisableQ8F16Cache",
        "-EmbedRowStaging",
        "-PrefillMassWrap",
        "-ComposePrefillMassTiering",
        "-ComposePrefillMassOpenRouter",
        "-ComposePrefillMassReserveSlots", ([string]$PromotionSlots),
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
        "-RoutePackedCopy",
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
        "-Iq1SMixedGpuPlan",
        "-Iq1SRamCacheGiB", "1",
        "-GateKind", "benchmark",
        "-QuiescenceCooldownSec", "90",
        "-RuntimeMinimumAvailableGiB", "4",
        "-RuntimeMaximumDiskQueueLength", "8",
        "-RuntimeContaminationSamples", "3"
    )
    if ($Promotion) {
        $args += "-Iq1Promotion"
        $args += "-Iq1PromotionProbationSlots"
        $args += ([string]$PromotionSlots)
    }
    return $args
}

function Assert-G98RunContract {
    param([Parameter(Mandatory=$true)][object]$Result,
          [Parameter(Mandatory=$true)][string]$Tag,
          [Parameter(Mandatory=$true)][string]$Arm,
          [Parameter(Mandatory=$true)][bool]$PromotionExpected,
          [Parameter(Mandatory=$true)][object]$Provenance)

    foreach ($name in @(
        "server_exit_code", "prompt_sha256", "warmup_prompt_sha256",
        "model_sha256", "iq1_s_sidecar_sha256",
        "iq1_s_mixed_runtime_observed",
        "iq1_s_mixed_gpu_plan_requested",
        "iq1_s_mixed_gpu_plan_runtime_observed",
        "iq1_promotion_requested",
        "iq1_promotion_probation_slots_requested",
        "iq1_promotion_runtime_observed",
        "iq1_promotion_line_count",
        "iq1_promotion_2bit_ssd_bytes",
        "iq1_promotion_2bit_ssd_seconds",
        "iq1_promotion_2bit_ssd_bytes_per_second",
        "iq1_promotion_direct_ssd_to_vram_rejected",
        "iq1_promotion_failures",
        "compose_prefill_mass_open_router_requested",
        "compose_prefill_mass_reserve_slots_requested",
        "route_packed_copy_requested",
        "route_packed_copy_observed",
        "expert_tiering",
        "runtime_telemetry",
        "system_quiescence_preflight")) {
        Assert-G98Property -Object $Result -Name $name -Tag $Tag
    }

    $tier = $Result.expert_tiering
    $rt = $Result.runtime_telemetry
    $sys = $Result.system_quiescence_preflight
    $contentHashes = @($Result.results | ForEach-Object {
        [string]$_.content_sha256
    })
    if ($contentHashes.Count -ne 3) {
        throw "G98 repeat count mismatch: tag=$Tag"
    }
    $uniqueContentHashes = @($contentHashes | Select-Object -Unique)
    if ($uniqueContentHashes.Count -ne 1) {
        throw "G98 intra-arm determinism failed: tag=$Tag"
    }
    foreach ($hash in $contentHashes) {
        if ($hash -notmatch '^[0-9a-fA-F]{64}$') {
            throw "G98 invalid repeat content hash: tag=$Tag"
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
        [double]$Result.dynamic_arena_gib_requested -ne 12.0 -or
        [bool]$Result.q8_f16_cache_disabled -ne $true -or
        [bool]$Result.embed_row_staging_requested -ne $true -or
        [bool]$Result.outputs_identical -ne $true -or
        [bool]$Result.non_identical_repeat_outputs_allowed -ne $false -or
        [bool]$Result.arena_wrap_trust_worker_checksum_requested -ne $true -or
        [string]$Result.arena_wrap_schedule_requested -ne "source-parts" -or
        [string]$Result.arena_wrap_schedule_observed -ne "source-parts" -or
        [string]$Result.arena_wrap_source_requested -ne "mmap" -or
        [string]$Result.arena_wrap_source_observed -ne "mmap" -or
        [bool]$Result.arena_wrap_unlock_source_ranges_requested -ne $true -or
        [double]$Result.arena_wrap_unlock_wave_gib_requested -ne 4.0 -or
        [bool]$Result.arena_wrap_unlock_source_ranges_observed -ne $true -or
        [bool]$Result.prefill_mass_wrap_requested -ne $true -or
        [bool]$Result.prefill_mass_wrap_observed -ne $true -or
        [bool]$Result.compose_prefill_mass_tiering_requested -ne $true -or
        [bool]$Result.compose_prefill_mass_open_router_requested -ne $true -or
        [int]$Result.compose_prefill_mass_reserve_slots_requested -ne $PromotionSlots -or
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
        [UInt64]$tier.failures -ne 0 -or
        [UInt64]$tier.forbidden_cold_ssd_to_vram -ne 0 -or
        [UInt64]$tier.cold_to_vram -ne 0 -or
        [UInt64]$tier.snapshot_backing_entries -ne
            [UInt64]$Result.prefill_mass_wrap_candidate_entries -or
        [bool]$Result.gpu_resident_routes_requested -ne $true -or
        [bool]$Result.gpu_resident_routes_observed -ne $true -or
        [bool]$Result.route_no_default_sync_requested -ne $true -or
        [UInt64]$Result.gpu_resident_routes_default_sync_calls -ne 0 -or
        [UInt64]$Result.gpu_resident_routes_no_default_sync_calls -ne
            [UInt64]$Result.gpu_resident_routes_calls -or
        [UInt64]$Result.gpu_resident_routes_errors -ne 0 -or
        [bool]$Result.route_packed_copy_requested -ne $true -or
        [bool]$Result.route_packed_copy_observed -ne $true -or
        [UInt64]$Result.route_packed_copy_bytes -le 0 -or
        [UInt64]$Result.route_packed_copy_legacy_submissions -ne 0 -or
        [bool]$Result.split_fused_requested -ne $true -or
        [bool]$Result.split_fused_observed -ne $true -or
        [int]$Result.reap_prefetch_threads_requested -ne 8 -or
        [bool]$Result.iq1_s_mixed_cold_one -ne $true -or
        [bool]$Result.iq1_s_mixed_runtime_observed -ne $true -or
        [UInt64]$Result.iq1_s_mixed_failures -ne 0 -or
        [bool]$Result.iq1_s_mixed_gpu_plan_requested -ne $true -or
        [bool]$Result.iq1_s_mixed_gpu_plan_runtime_observed -ne $true -or
        [UInt64]$Result.iq1_s_mixed_gpu_plan_calls -le 0 -or
        [UInt64]$Result.iq1_s_mixed_gpu_plan_failures -ne 0 -or
        [double]$Result.iq1_s_ram_cache_requested_gib -ne 1.0 -or
        [bool]$Result.iq1_s_ram_cache_runtime_observed -ne $true -or
        [UInt64]$Result.iq1_s_ram_cache_failures -ne 0 -or
        [bool]$Result.iq1_s_packed_h2d_requested -ne $false -or
        [bool]$Result.iq1_s_no_main_sync_requested -ne $false -or
        [bool]$Result.spex_dry_run_requested -ne $false -or
        [bool]$Result.spex_observed -ne $false -or
        [bool]$Result.memory_preflight.ready_to_launch -ne $true -or
        [bool]$Result.process_isolation_preflight.ready_to_launch -ne $true -or
        [bool]$sys.skipped -ne $false -or
        [int]$sys.requested_cooldown_seconds -ne 90 -or
        [bool]$sys.ready_to_launch -ne $true -or
        [bool]$rt.contamination_abort_observed -ne $false -or
        [string]$Result.contamination_reason -ne "" -or
        [double]$rt.contamination_runtime_minimum_available_gib -ne 4.0 -or
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
        throw "G98 contract mismatch: tag=$Tag arm=$Arm"
    }

    if ([bool]$Result.iq1_promotion_requested -ne $PromotionExpected -or
        [bool]$Result.iq1_promotion_runtime_observed -ne $PromotionExpected) {
        throw "G98 promotion marker mismatch: tag=$Tag"
    }

    if ($PromotionExpected) {
        $expectedRequests = [int]$Result.request_count_expected
        if ([int]$Result.iq1_promotion_probation_slots_requested -ne
            $PromotionSlots -or
            [int]$Result.iq1_promotion_line_count -ne $expectedRequests -or
            [UInt64]$Result.iq1_promotion_cold_to_2bit_ram -le 0 -or
            [UInt64]$Result.iq1_promotion_2bit_ssd_bytes -le 0 -or
            [double]$Result.iq1_promotion_2bit_ssd_seconds -le 0.0 -or
            [double]$Result.iq1_promotion_2bit_ssd_bytes_per_second -le 0.0 -or
            [UInt64]$Result.iq1_promotion_direct_ssd_to_vram_rejected -ne 0 -or
            [UInt64]$Result.iq1_promotion_failures -ne 0 -or
            [string]$Result.effective_ds4_environment.DS4_CUDA_PREFILL_TIER_ROUTER -ne
                "open" -or
            [string]$Result.effective_ds4_environment.DS4_CUDA_PREFILL_TIER_RESERVE_SLOTS -ne
                ([string]$PromotionSlots) -or
            [string]$Result.effective_ds4_environment.DS4_IQ1_PROMOTION_PROBATION_SLOTS -ne
                ([string]$PromotionSlots) -or
            [UInt64]$tier.snapshot_backing_entries -ne
                [UInt64]$Result.prefill_mass_wrap_candidate_entries -or
            [UInt64]$Result.iq1_promotion_snapshot_evictions -ne 0 -or
            [UInt64]$Result.iq1_promotion_reserved_slots -ne
                ([string]$PromotionSlots)) {
            throw "G98 candidate promotion aggregate contract mismatch"
        }
        if (@($Result.iq1_promotion_requests).Count -ne $expectedRequests) {
            throw "G98 candidate promotion request count mismatch"
        }
        foreach ($row in @($Result.iq1_promotion_requests)) {
            if ([UInt64]$row.requested_slots -ne [UInt64]$PromotionSlots -or
                [UInt64]$row.reserved_slots -ne [UInt64]$PromotionSlots -or
                [UInt64]$row.snapshot_evictions -ne 0 -or
                [UInt64]$row.cold_observed -le 0 -or
                [UInt64]$row.cold_to_2bit_ram -le 0 -or
                [UInt64]$row.promotion_2bit_ssd_bytes -le 0 -or
                [double]$row.promotion_2bit_ssd_seconds -le 0.0 -or
                [UInt64]$row.direct_ssd_to_vram_rejected -ne 0 -or
                [UInt64]$row.failures -ne 0) {
                throw "G98 candidate promotion row contract mismatch"
            }
        }
    } else {
        if ([int]$Result.iq1_promotion_line_count -ne 0 -or
            [UInt64]$Result.iq1_promotion_cold_to_2bit_ram -ne 0 -or
            [UInt64]$Result.iq1_promotion_2bit_ssd_bytes -ne 0 -or
            [double]$Result.iq1_promotion_2bit_ssd_seconds -ne 0.0 -or
            [double]$Result.iq1_promotion_2bit_ssd_bytes_per_second -ne 0.0 -or
            [UInt64]$Result.iq1_promotion_direct_ssd_to_vram_rejected -ne 0 -or
            [UInt64]$Result.iq1_promotion_failures -ne 0 -or
            [string]$Result.effective_ds4_environment.DS4_CUDA_PREFILL_TIER_ROUTER -ne
                "open" -or
            [string]$Result.effective_ds4_environment.DS4_CUDA_PREFILL_TIER_RESERVE_SLOTS -ne
                ([string]$PromotionSlots)) {
            throw "G98 control promotion telemetry appeared while disabled"
        }
    }
}

function Invoke-G98Arm {
    param([Parameter(Mandatory=$true)][string]$Tag,
          [Parameter(Mandatory=$true)][string]$Arm,
          [Parameter(Mandatory=$true)][bool]$Promotion,
          [Parameter(Mandatory=$true)][object]$Provenance)

    $resultPath = Join-Path $outdir ("g7_" + $Tag + "_result.json")
    $rawPath = Join-Path $outdir ("g7_" + $Tag + "_raw_outputs.json")
    $failurePath = Join-Path $outdir ("g7_" + $Tag + "_failure.json")
    $args = New-G98Args -Tag $Tag -Promotion $Promotion

    if ($Resume -and (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        Write-Host ("[g98] resume validate tag=" + $Tag + " arm=" + $Arm)
    } else {
        Write-Host ("[g98] start tag=" + $Tag + " arm=" + $Arm)
        & powershell.exe @args | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) { throw "G98 arm failed: $Tag" }
    }

    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        throw "G98 result missing: tag=$Tag"
    }
    if (-not (Test-Path -LiteralPath $rawPath -PathType Leaf)) {
        throw "G98 raw outputs missing: tag=$Tag"
    }
    if (Test-Path -LiteralPath $failurePath -PathType Leaf) {
        throw "G98 failure artifact present: tag=$Tag path=$failurePath"
    }

    $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    Assert-G98RunContract -Result $result -Tag $Tag -Arm $Arm `
        -PromotionExpected $Promotion -Provenance $Provenance
    $tier = $result.expert_tiering
    $rt = $result.runtime_telemetry

    [pscustomobject]@{
        tag = $Tag
        arm = $Arm
        promotion = [bool]$Promotion
        promotion_slots = $(if ($Promotion) { $PromotionSlots } else { 0 })
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
        repeat_count = [int]$result.results.Count
        request_count_expected = [int]$result.request_count_expected
        content_sha256_by_repeat = @($result.results | ForEach-Object {
            [string]$_.content_sha256
        })
        deterministic_content_sha256 = [string]$result.results[0].content_sha256
        warmup_content_sha256 = [string]$result.warmup_result.content_sha256
        outputs_identical = [bool]$result.outputs_identical
        mean_tokens_per_second = [double]$result.mean_tokens_per_second
        server_decode_mean_tokens_per_second =
            [double]$result.server_decode_mean_tokens_per_second
        server_prefill_ttft_mean_seconds =
            [double]$result.server_prefill_ttft_mean_seconds
        warmup_seconds = [double]$result.warmup_seconds
        load_seconds = [double]$result.load_seconds
        iq1_s_mixed_calls = [UInt64]$result.iq1_s_mixed_calls
        iq1_s_mixed_hot_main = [UInt64]$result.iq1_s_mixed_hot_main
        iq1_s_mixed_cold_iq1 = [UInt64]$result.iq1_s_mixed_cold_iq1
        iq1_s_mixed_gpu_plan_calls =
            [UInt64]$result.iq1_s_mixed_gpu_plan_calls
        iq1_s_ram_cache_hits = [UInt64]$result.iq1_s_ram_cache_hits
        iq1_s_ram_cache_misses = [UInt64]$result.iq1_s_ram_cache_misses
        iq1_s_ram_cache_hit_rate = [double]$result.iq1_s_ram_cache_hit_rate
        route_packed_copy_bytes = [UInt64]$result.route_packed_copy_bytes
        route_calls = [UInt64]$result.gpu_resident_routes_calls
        route_worker_jobs = [UInt64]$result.gpu_resident_routes_worker_jobs
        route_wait_ms_per_call =
            [double]$result.gpu_resident_routes_wait_ms_per_call
        tier_failures = [UInt64]$tier.failures
        tier_snapshot_backing_misses = [UInt64]$tier.snapshot_backing_misses
        tier_forbidden_cold_ssd_to_vram =
            [UInt64]$tier.forbidden_cold_ssd_to_vram
        tier_cold_to_vram = [UInt64]$tier.cold_to_vram
        tier_ram_h2d_gib = Convert-G98BytesToGiB $tier.ram_h2d_bytes
        promotion_line_count = [int]$result.iq1_promotion_line_count
        promotion_cold_to_2bit_ram =
            [UInt64]$result.iq1_promotion_cold_to_2bit_ram
        promotion_2bit_ssd_bytes =
            [UInt64]$result.iq1_promotion_2bit_ssd_bytes
        promotion_2bit_ssd_seconds =
            [double]$result.iq1_promotion_2bit_ssd_seconds
        promotion_2bit_ssd_bytes_per_second =
            [double]$result.iq1_promotion_2bit_ssd_bytes_per_second
        promotion_direct_rejected =
            [UInt64]$result.iq1_promotion_direct_ssd_to_vram_rejected
        promotion_failures = [UInt64]$result.iq1_promotion_failures
        process_read_gib =
            Convert-G98BytesToGiB $rt.win32_process_read_transfer_delta_bytes
        aggregate_disk_read_gib =
            Convert-G98BytesToGiB $rt.aggregate_disk_read_bytes_estimated
        contamination_abort_observed =
            [bool]$rt.contamination_abort_observed
        clean = $true
    }
}

New-Item -ItemType Directory -Force -Path $outdir | Out-Null
Assert-G98StaticContract

$selfSha = Get-G98SHA256 $MyInvocation.MyCommand.Path
$staticChecks = [pscustomobject]@{
    schema = "g98_iq1_promotion_perf_ab_v1"
    script_parse_ok = $true
    ast_parse_ok = $true
    static_diff_ok = $true
    harness_present = (Test-Path -LiteralPath $harness -PathType Leaf)
    runtime_monitor_present =
        (Test-Path -LiteralPath $runtimeMonitor -PathType Leaf)
    static_check_only = [bool]$StaticCheckOnly
    no_build_gpu_or_ds4_launch_in_static_check = [bool]$StaticCheckOnly
    prompt_sha256 = $expectedPromptSHA256
    temperature_zero_and_nothink_harness_static_marker = $true
    repeats_per_arm = 3
    warmup_max_tokens = 64
    max_tokens = 64
    context = 256
    dynamic_arena_gib = 12
    iq1_s_ram_cache_gib = 1
    expert_cache_n = 320
    gpu_planner_on_both_arms = $true
    route_packed_copy = $true
    compose_prefill_mass_open_router = $true
    compose_prefill_mass_reserve_slots = $PromotionSlots
    promotion_control = "open-router reserve16, promotion off"
    promotion_candidate = "open-router reserve16, -Iq1Promotion slots16"
    quiescence_required = $true
    quiescence_cooldown_seconds = 90
    contamination_abort_fail_closed = $true
    require_same_provenance_except_promotion = $true
    require_intra_arm_determinism = $true
    do_not_require_cross_arm_equality = $true
    performance_claim_requires_clean_n3_timing = $true
    quality_claim = "none"
    runner_sha256 = $selfSha
}

if ($StaticCheckOnly) {
    Write-Host "[g98] static check OK; no build, GPU, DS4, or benchmark launched."
    $staticChecks | ConvertTo-Json -Depth 5
    return
}

foreach ($path in @($executable, $buildManifest)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "G98 requires existing provenance artifact; no build is launched: $path"
    }
}
$provenance = [pscustomobject]@{
    executable_sha256 = Get-G98SHA256 $executable
    harness_sha256 = Get-G98SHA256 $harness
    runtime_monitor_harness_sha256 = Get-G98SHA256 $runtimeMonitor
    ds4_cuda_sha256 = Get-G98SHA256 (Join-Path $root "ds4_cuda.cu")
    ds4_c_sha256 = Get-G98SHA256 (Join-Path $root "ds4.c")
    ds4_server_c_sha256 = Get-G98SHA256 (Join-Path $root "ds4_server.c")
    build_manifest_sha256 = Get-G98SHA256 $buildManifest
}

$runs = @()
foreach ($item in $armPlan) {
    $runs += Invoke-G98Arm -Tag $item.Tag -Arm $item.Arm `
        -Promotion ([bool]$item.Promotion) -Provenance $provenance
}

foreach ($field in @(
    "head", "executable_sha256", "ds4_cuda_sha256", "ds4_c_sha256",
    "ds4_server_c_sha256", "build_manifest_sha256",
    "build_input_fingerprint_sha256", "harness_sha256",
    "runtime_monitor_harness_sha256", "model", "model_bytes",
    "model_sha256", "iq1_s_sidecar", "iq1_s_sidecar_bytes",
    "iq1_s_sidecar_sha256", "repeat_count", "outputs_identical")) {
    $values = @($runs | ForEach-Object { [string]($_.$field) } |
        Select-Object -Unique)
    if ($values.Count -ne 1) {
        throw "G98 mixed provenance/settings across arms: field=$field"
    }
}

$control = @($runs | Where-Object { $_.promotion -eq $false })[0]
$candidate = @($runs | Where-Object { $_.promotion -eq $true })[0]
if ($control.repeat_count -ne 3 -or $candidate.repeat_count -ne 3) {
    throw "G98 n=3 requirement not met."
}
if ($control.promotion_line_count -ne 0 -or
    $candidate.promotion_line_count -ne $candidate.request_count_expected) {
    throw "G98 promotion isolation/request coverage failed."
}

$crossArmEqual = ([string]$control.deterministic_content_sha256 -eq
    [string]$candidate.deterministic_content_sha256)
$bothClean = @($runs | Where-Object { -not $_.clean }).Count -eq 0
$timingValid = [bool]($bothClean -and $control.repeat_count -eq 3 -and
    $candidate.repeat_count -eq 3 -and
    [double]$control.server_decode_mean_tokens_per_second -gt 0.0 -and
    [double]$candidate.server_decode_mean_tokens_per_second -gt 0.0)
$decodeDeltaPercent = if ($timingValid) {
    [math]::Round(
        100.0 * ([double]$candidate.server_decode_mean_tokens_per_second -
        [double]$control.server_decode_mean_tokens_per_second) /
        [double]$control.server_decode_mean_tokens_per_second, 6)
} else { $null }
$harnessDeltaPercent = if ($timingValid -and
    [double]$control.mean_tokens_per_second -gt 0.0) {
    [math]::Round(
        100.0 * ([double]$candidate.mean_tokens_per_second -
        [double]$control.mean_tokens_per_second) /
        [double]$control.mean_tokens_per_second, 6)
} else { $null }
$performanceClaim = if ($timingValid) {
    "valid only for this clean n=3 timing A/B"
} else {
    "withheld: clean n=3 timing contract not satisfied"
}

$summary = [pscustomobject]@{
    schema = "g98_iq1_promotion_perf_ab_v1"
    question = "Open-router reserve16 promotion OFF versus identical setup with -Iq1Promotion -Iq1PromotionProbationSlots 16."
    gate_kind = "benchmark"
    quality_claim = "none"
    general_sota_claim = "none"
    performance_claim = $performanceClaim
    prompt = $prompt
    prompt_sha256 = $expectedPromptSHA256
    temperature = 0
    think = $false
    max_tokens = 64
    warmup_max_tokens = 64
    context = 256
    repeats_per_arm = 3
    dynamic_arena_gib = 12
    iq1_s_ram_cache_gib = 1
    iq1_s_layers = "3..42"
    mixed_cold_one = $true
    gpu_planner = "on in both arms"
    promotion_only_difference = $true
    promotion_candidate_slots = $PromotionSlots
    compose_prefill_mass_open_router = $true
    compose_prefill_mass_reserve_slots = $PromotionSlots
    quiescence = [pscustomobject]@{
        skipped = $false
        cooldown_seconds = 90
        abort_fail_closed_on_contamination = $true
    }
    arena_wrap = [pscustomobject]@{
        schedule = "source-parts"
        source = "mmap"
        trust_worker_checksum = $true
        unlock_source_ranges = $true
        unlock_wave_gib = 4
    }
    prefill_mass = [pscustomobject]@{
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
        route_packed_copy = $true
        split_fused = $true
        reap_prefetch_threads = 8
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
        same_provenance_binary_harness_config_except_promotion = $true
        clean_quiescence = $bothClean
        n3_each_arm = $true
        intra_arm_determinism = $true
        cross_arm_equal_recorded_not_required = $crossArmEqual
        gpu_planner_on_both_arms = $true
        promotion_off_control = $true
        promotion_candidate_all_requests = $true
        promotion_cold_to_2bit_ram_positive =
            ($candidate.promotion_cold_to_2bit_ram -gt 0)
        promotion_ssd_bytes_seconds_bandwidth_positive =
            ($candidate.promotion_2bit_ssd_bytes -gt 0 -and
            $candidate.promotion_2bit_ssd_seconds -gt 0.0 -and
            $candidate.promotion_2bit_ssd_bytes_per_second -gt 0.0)
        direct_reject_failures_snapshot_misses_forbidden_cold_to_vram_zero =
            $true
        performance_claim_allowed = $timingValid
    }
    runs = $runs
    deltas = [pscustomobject]@{
        candidate_minus_control_decode_tps =
            [math]::Round([double]$candidate.server_decode_mean_tokens_per_second -
            [double]$control.server_decode_mean_tokens_per_second, 6)
        candidate_minus_control_decode_tps_percent = $decodeDeltaPercent
        candidate_minus_control_harness_tps =
            [math]::Round([double]$candidate.mean_tokens_per_second -
            [double]$control.mean_tokens_per_second, 6)
        candidate_minus_control_harness_tps_percent = $harnessDeltaPercent
        candidate_minus_control_ttft_seconds =
            [math]::Round([double]$candidate.server_prefill_ttft_mean_seconds -
            [double]$control.server_prefill_ttft_mean_seconds, 6)
    }
}

$summary | ConvertTo-Json -Depth 10 |
    Set-Content -LiteralPath $summaryPath -Encoding UTF8
Write-Host ("[g98] A/B complete: " + $summaryPath)
