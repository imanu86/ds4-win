# G100 IQ1_S promotion gate lever sweep (PowerShell 5.1, ASCII).
param(
    [switch]$StaticCheckOnly,
    [switch]$Resume,
    [ValidateSet("all", "legacy", "confirm-only", "budget-only",
        "weight-only", "combined")]
    [string]$Arm = "all"
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

$prompt = "Hi"
$summaryPath = Join-Path $outdir "g100_iq1_promotion_gate_sweep_result.json"
$promotionSlots = 16

$armPlan = @(
    [pscustomobject]@{
        Arm = "legacy"
        Tag = "g100_iq1_promotion_gate_legacy_n1"
        MinTouches = 1
        MinWeight = 0.0
        MinMass = 0.0
        RequestBudget = 0
        WindowCalls = 0
        WindowBudget = 0
        Description = "touch1 no thresholds unlimited"
    },
    [pscustomobject]@{
        Arm = "confirm-only"
        Tag = "g100_iq1_promotion_gate_confirm_only_n1"
        MinTouches = 2
        MinWeight = 0.0
        MinMass = 0.0
        RequestBudget = 0
        WindowCalls = 0
        WindowBudget = 0
        Description = "touch2"
    },
    [pscustomobject]@{
        Arm = "budget-only"
        Tag = "g100_iq1_promotion_gate_budget_only_n1"
        MinTouches = 1
        MinWeight = 0.0
        MinMass = 0.0
        RequestBudget = 16
        WindowCalls = 40
        WindowBudget = 1
        Description = "touch1 request-budget16 window40 budget1"
    },
    [pscustomobject]@{
        Arm = "weight-only"
        Tag = "g100_iq1_promotion_gate_weight_only_n1"
        MinTouches = 1
        MinWeight = 0.02
        MinMass = 0.0
        RequestBudget = 0
        WindowCalls = 0
        WindowBudget = 0
        Description = "touch1 minWeight.02"
    },
    [pscustomobject]@{
        Arm = "combined"
        Tag = "g100_iq1_promotion_gate_combined_n1"
        MinTouches = 2
        MinWeight = 0.02
        MinMass = 0.0
        RequestBudget = 16
        WindowCalls = 40
        WindowBudget = 1
        Description = "touch2 minWeight.02 request-budget16 window40 budget1"
    }
)

$promotionGateEnvNames = @(
    "DS4_IQ1_PROMOTION_MIN_TOUCHES",
    "DS4_IQ1_PROMOTION_MIN_WEIGHT",
    "DS4_IQ1_PROMOTION_MIN_MASS",
    "DS4_IQ1_PROMOTION_REQUEST_BUDGET",
    "DS4_IQ1_PROMOTION_WINDOW_CALLS",
    "DS4_IQ1_PROMOTION_WINDOW_BUDGET"
)

function Get-G100SHA256 {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "G100 provenance file missing: $Path"
    }
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-G100Property {
    param([object]$Object, [string]$Name)
    if ($null -eq $Object -or
        $null -eq $Object.PSObject.Properties[$Name]) {
        return $null
    }
    $Object.PSObject.Properties[$Name].Value
}

function Assert-G100Property {
    param(
        [Parameter(Mandatory=$true)][object]$Object,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Tag
    )
    if ($null -eq $Object -or
        $null -eq $Object.PSObject.Properties[$Name]) {
        throw "G100 required field missing: tag=$Tag field=$Name"
    }
}

function Test-G100HarnessParameter {
    param([Parameter(Mandatory=$true)][string]$ParameterName)
    $content = Get-Content -LiteralPath $harness -Raw
    return ($content -match ("\$" + [regex]::Escape($ParameterName) +
        "(\s|=|,|\))"))
}

function Convert-G100NullableString {
    param([object]$Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [double]) {
        return ([double]$Value).ToString(
            "0.################", [Globalization.CultureInfo]::InvariantCulture)
    }
    return [string]$Value
}

function Get-G100SelectedArms {
    if ($Arm -eq "all") { return @($armPlan) }
    return @($armPlan | Where-Object { $_.Arm -eq $Arm })
}

function Get-G100ComparableArgs {
    param([Parameter(Mandatory=$true)][object[]]$Args)
    $normalized = @()
    $armValueArgs = @(
        "-Iq1PromotionMinTouches", "-Iq1PromotionMinWeight",
        "-Iq1PromotionMinMass", "-Iq1PromotionRequestBudget",
        "-Iq1PromotionWindowCalls", "-Iq1PromotionWindowBudget")
    for ($i = 0; $i -lt $Args.Count; $i++) {
        $value = [string]$Args[$i]
        if ($value -eq "-Tag" -or $armValueArgs -contains $value) {
            $i++
            continue
        }
        $normalized += $value
    }
    return $normalized
}

function Assert-G100StaticContract {
    if (-not (Test-Path -LiteralPath $harness -PathType Leaf)) {
        throw "G100 harness missing: $harness"
    }
    if (-not (Test-Path -LiteralPath $runtimeMonitor -PathType Leaf)) {
        throw "G100 runtime monitor missing: $runtimeMonitor"
    }
    foreach ($parameter in @(
        "WarmupMaxTokens", "Repeats", "BudgetGB", "ReserveMB",
        "DynamicArenaGiB", "ArenaWrapTrustWorkerChecksum",
        "ArenaWrapSourceParts", "ArenaWrapUnlockSourceRanges",
        "ArenaWrapUnlockWaveGiB", "PrefillMassWrap",
        "ComposePrefillMassTiering", "ComposePrefillMassOpenRouter",
        "ComposePrefillMassReserveSlots", "DisableQ8F16Cache",
        "EmbedRowStaging", "ExpertCacheN", "ExpertCacheReserveGB",
        "ExpertCachePolicy", "ExpertTiering", "ExpertTierPolicy",
        "ExpertTierClockCalls", "ExpertTierReplacementBudget",
        "ExpertTierMinFrequency", "ExpertTierHysteresis",
        "GpuResidentRoutes", "RouteNoDefaultSync", "SplitFused",
        "ReapPrefetchThreads", "ExpectedModelSHA256",
        "ReuseVerifiedModelReceipt", "Iq1SExpertSidecar",
        "ExpectedIq1SExpertSidecarSHA256",
        "ExpectedIq1SExpertSidecarBytes", "ReuseVerifiedIq1SReceipt",
        "Iq1SLayerFirst", "Iq1SLayerLast", "Iq1SMixedColdOne",
        "Iq1SMixedGpuPlan", "Iq1Promotion",
        "Iq1PromotionProbationSlots", "Iq1PromotionMinTouches",
        "Iq1PromotionMinWeight", "Iq1PromotionMinMass",
        "Iq1PromotionRequestBudget", "Iq1PromotionWindowCalls",
        "Iq1PromotionWindowBudget", "Iq1SRamCacheGiB", "GateKind",
        "SkipSystemQuiescencePreflight", "QuiescenceCooldownSec")) {
        if (-not (Test-G100HarnessParameter -ParameterName $parameter)) {
            throw "Harness does not expose -$parameter; refusing to run."
        }
    }

    $harnessText = Get-Content -LiteralPath $harness -Raw
    foreach ($requiredText in @(
        "temperature = 0",
        "think = `$false",
        "DS4_IQ1_PROMOTION_PROBATION_SLOTS",
        "DS4_CUDA_PREFILL_TIER_ROUTER",
        "DS4_CUDA_PREFILL_TIER_RESERVE_SLOTS",
        "compose_prefill_mass_open_router_requested",
        "compose_prefill_mass_reserve_slots_requested",
        "iq1-promotion",
        "promotion_2bit_ssd_bytes",
        "iq1_promotion_probation_backing_reclaims",
        "general_backing_reclaims",
        "route_packed_copy_requested",
        "quality_eligible",
        "sota_eligible")) {
        if ($harnessText -notmatch [regex]::Escape($requiredText)) {
            throw "G100 harness static marker missing: $requiredText"
        }
    }

    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $PSCommandPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
    if ($parseErrors -and $parseErrors.Count -gt 0) {
        throw "G100 AST parse failed: $($parseErrors[0].Message)"
    }

    $baseline = @(Get-G100ComparableArgs -Args (
        New-G100Args -Plan $armPlan[0]))
    foreach ($plan in $armPlan) {
        $args = @(New-G100Args -Plan $plan)
        $comparable = @(Get-G100ComparableArgs -Args $args)
        if (($baseline -join "`n") -ne ($comparable -join "`n")) {
            throw "G100 static arg diff failed: arm=$($plan.Arm)"
        }
        foreach ($requiredArg in @(
            "-ReuseVerifiedModelReceipt", "-ReuseVerifiedIq1SReceipt",
            "-ComposePrefillMassOpenRouter", "-ComposePrefillMassReserveSlots",
            "-Iq1Promotion", "-Iq1PromotionProbationSlots",
            "-Iq1PromotionMinTouches", "-Iq1PromotionMinWeight",
            "-Iq1PromotionMinMass", "-Iq1PromotionRequestBudget",
            "-Iq1PromotionWindowCalls", "-Iq1PromotionWindowBudget")) {
            if (@($args | Where-Object { $_ -eq $requiredArg }).Count -ne 1) {
                throw "G100 required arg missing: arm=$($plan.Arm) arg=$requiredArg"
            }
        }
        foreach ($forbiddenArg in @("-RoutePackedCopy")) {
            if (@($args | Where-Object { $_ -eq $forbiddenArg }).Count -ne 0) {
                throw "G100 forbidden arg present: arm=$($plan.Arm) arg=$forbiddenArg"
            }
        }
    }

    if ($expectedModelSHA256 -notmatch '^[0-9a-f]{64}$' -or
        $expectedIq1SidecarSHA256 -notmatch '^[0-9a-f]{64}$' -or
        $expectedIq1SidecarBytes -le 0) {
        throw "G100 provenance constants are invalid."
    }
}

function New-G100Args {
    param([Parameter(Mandatory=$true)][object]$Plan)
    @(
        "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", $harness,
        "-Tag", $Plan.Tag,
        "-MaxTokens", "16",
        "-Warmup", "-WarmupMaxTokens", "16",
        "-Repeats", "1",
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
        "-ComposePrefillMassReserveSlots", ([string]$promotionSlots),
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
        "-ReuseVerifiedModelReceipt",
        "-Iq1SExpertSidecar", $iq1Sidecar,
        "-ExpectedIq1SExpertSidecarSHA256", $expectedIq1SidecarSHA256,
        "-ExpectedIq1SExpertSidecarBytes", ([string]$expectedIq1SidecarBytes),
        "-ReuseVerifiedIq1SReceipt",
        "-Iq1SLayerFirst", "3",
        "-Iq1SLayerLast", "42",
        "-Iq1SMixedColdOne",
        "-Iq1SMixedGpuPlan",
        "-Iq1Promotion",
        "-Iq1PromotionProbationSlots", ([string]$promotionSlots),
        "-Iq1PromotionMinTouches", ([string]$Plan.MinTouches),
        "-Iq1PromotionMinWeight", (Convert-G100NullableString $Plan.MinWeight),
        "-Iq1PromotionMinMass", (Convert-G100NullableString $Plan.MinMass),
        "-Iq1PromotionRequestBudget", ([string]$Plan.RequestBudget),
        "-Iq1PromotionWindowCalls", ([string]$Plan.WindowCalls),
        "-Iq1PromotionWindowBudget", ([string]$Plan.WindowBudget),
        "-Iq1SRamCacheGiB", "1",
        "-GateKind", "structural-safety",
        "-SkipSystemQuiescencePreflight",
        "-QuiescenceCooldownSec", "90"
    )
}

function Set-G100PromotionGateEnvironment {
    param([Parameter(Mandatory=$true)][object]$Plan)
    foreach ($name in $promotionGateEnvNames) {
        [System.Environment]::SetEnvironmentVariable(
            $name, $null, [System.EnvironmentVariableTarget]::Process)
    }
    [System.Environment]::SetEnvironmentVariable(
        "DS4_IQ1_PROMOTION_MIN_TOUCHES",
        ([string]$Plan.MinTouches),
        [System.EnvironmentVariableTarget]::Process)
    foreach ($pair in @(
        @("DS4_IQ1_PROMOTION_MIN_WEIGHT", $Plan.MinWeight),
        @("DS4_IQ1_PROMOTION_MIN_MASS", $Plan.MinMass),
        @("DS4_IQ1_PROMOTION_REQUEST_BUDGET", $Plan.RequestBudget),
        @("DS4_IQ1_PROMOTION_WINDOW_CALLS", $Plan.WindowCalls),
        @("DS4_IQ1_PROMOTION_WINDOW_BUDGET", $Plan.WindowBudget))) {
        [System.Environment]::SetEnvironmentVariable(
            [string]$pair[0], (Convert-G100NullableString $pair[1]),
            [System.EnvironmentVariableTarget]::Process)
    }
}

function Clear-G100PromotionGateEnvironment {
    foreach ($name in $promotionGateEnvNames) {
        [System.Environment]::SetEnvironmentVariable(
            $name, $null, [System.EnvironmentVariableTarget]::Process)
    }
}

function Get-G100ExpectedGateConfig {
    param([Parameter(Mandatory=$true)][object]$Plan)
    [pscustomobject]@{
        min_touches = [int]$Plan.MinTouches
        min_weight = [double]$Plan.MinWeight
        min_mass = [double]$Plan.MinMass
        request_budget = [int]$Plan.RequestBudget
        window_calls = [int]$Plan.WindowCalls
        window_budget = [int]$Plan.WindowBudget
    }
}

function Assert-G100GateConfig {
    param(
        [Parameter(Mandatory=$true)][object]$Observed,
        [Parameter(Mandatory=$true)][object]$Expected,
        [Parameter(Mandatory=$true)][string]$Tag
    )
    if ($null -eq $Observed) {
        throw "G100 promotion gate config missing: tag=$Tag"
    }
    foreach ($name in @("min_touches", "min_weight", "min_mass",
        "request_budget", "window_calls", "window_budget")) {
        Assert-G100Property -Object $Observed -Name $name -Tag $Tag
    }
    if ([int]$Observed.min_touches -ne [int]$Expected.min_touches) {
        throw "G100 min_touches mismatch: tag=$Tag"
    }
    foreach ($name in @("request_budget", "window_calls", "window_budget")) {
        if ([int](Get-G100Property -Object $Observed -Name $name) -ne
            [int](Get-G100Property -Object $Expected -Name $name)) {
            throw "G100 gate field mismatch: tag=$Tag field=$name"
        }
    }
    foreach ($name in @("min_weight", "min_mass")) {
        if ([math]::Abs(
            [double](Get-G100Property -Object $Observed -Name $name) -
            [double](Get-G100Property -Object $Expected -Name $name)) -gt
            0.000001) {
            throw "G100 gate float mismatch: tag=$Tag field=$name"
        }
    }
}

function Assert-G100RunContract {
    param(
        [Parameter(Mandatory=$true)][object]$Result,
        [Parameter(Mandatory=$true)][object]$Plan,
        [Parameter(Mandatory=$true)][object]$Provenance
    )

    $tag = [string]$Plan.Tag
    foreach ($name in @(
        "server_exit_code", "results", "model_sha256", "model_hash_method",
        "model_receipt_path", "model_receipt_sha256",
        "iq1_s_sidecar_sha256", "iq1_s_sidecar_hash_method",
        "iq1_s_sidecar_receipt_path", "iq1_s_sidecar_receipt_sha256",
        "iq1_s_mixed_runtime_observed",
        "iq1_s_mixed_gpu_plan_runtime_observed",
        "iq1_promotion_requested",
        "iq1_promotion_probation_slots_requested",
        "iq1_promotion_runtime_observed",
        "iq1_promotion_line_count",
        "iq1_promotion_requested_slots",
        "iq1_promotion_reserved_slots",
        "iq1_promotion_snapshot_evictions",
        "iq1_promotion_cold_observed",
        "iq1_promotion_cold_to_2bit_ram",
        "iq1_promotion_2bit_ssd_bytes",
        "iq1_promotion_2bit_ssd_seconds",
        "iq1_promotion_2bit_ssd_bytes_per_second",
        "iq1_promotion_direct_ssd_to_vram_rejected",
        "iq1_promotion_probation_backing_reclaims",
        "iq1_promotion_failures",
        "compose_prefill_mass_open_router_requested",
        "compose_prefill_mass_reserve_slots_requested",
        "route_packed_copy_requested", "route_packed_copy_observed",
        "route_packed_copy_bytes", "expert_tiering",
        "system_quiescence_preflight", "quality_eligible",
        "sota_eligible", "contamination_reason",
        "effective_ds4_environment")) {
        Assert-G100Property -Object $Result -Name $name -Tag $tag
    }

    foreach ($newField in @(
        "iq1_promotion_requested_config",
        "iq1_promotion_min_touches", "iq1_promotion_min_weight",
        "iq1_promotion_min_mass", "iq1_promotion_request_budget",
        "iq1_promotion_window_calls", "iq1_promotion_window_budget",
        "iq1_promotion_cold_gate_candidates",
        "iq1_promotion_weight_ge_001", "iq1_promotion_weight_ge_002",
        "iq1_promotion_weight_ge_005", "iq1_promotion_weight_ge_010",
        "iq1_promotion_skips_touches", "iq1_promotion_skips_weight",
        "iq1_promotion_skips_mass",
        "iq1_promotion_skips_request_budget",
        "iq1_promotion_skips_window_budget")) {
        Assert-G100Property -Object $Result -Name $newField -Tag $tag
    }

    $tier = $Result.expert_tiering
    foreach ($name in @("forbidden_cold_ssd_to_vram", "cold_to_vram",
        "failures", "general_backing_reclaims")) {
        Assert-G100Property -Object $tier -Name $name -Tag $tag
    }

    $expectedRequests = [int]$Result.request_count_expected
    if ($expectedRequests -le 0) {
        throw "G100 request_count_expected invalid: tag=$tag"
    }
    $contentHashes = @($Result.results | ForEach-Object {
        [string]$_.content_sha256
    })
    if ($contentHashes.Count -ne 1 -or
        $contentHashes[0] -notmatch '^[0-9a-fA-F]{64}$') {
        throw "G100 output hash contract failed: tag=$tag"
    }

    $expectedGate = Get-G100ExpectedGateConfig -Plan $Plan
    Assert-G100GateConfig -Observed $Result.iq1_promotion_requested_config `
        -Expected $expectedGate -Tag $tag
    if ([int]$Result.iq1_promotion_min_touches -ne
        [int]$Plan.MinTouches -or
        [string]$Result.effective_ds4_environment.DS4_IQ1_PROMOTION_MIN_TOUCHES -ne
            ([string]$Plan.MinTouches)) {
        throw "G100 effective min-touch mismatch: tag=$tag"
    }

    if ([math]::Abs([double]$Result.iq1_promotion_min_weight -
        [double]$Plan.MinWeight) -gt 0.000001) {
        throw "G100 min-weight telemetry mismatch: tag=$tag"
    }
    if ([math]::Abs([double]$Result.iq1_promotion_min_mass -
        [double]$Plan.MinMass) -gt 0.000001) {
        throw "G100 min-mass telemetry mismatch: tag=$tag"
    }
    foreach ($pair in @(
        @("iq1_promotion_request_budget", $Plan.RequestBudget),
        @("iq1_promotion_window_calls", $Plan.WindowCalls),
        @("iq1_promotion_window_budget", $Plan.WindowBudget))) {
        $observed = Get-G100Property -Object $Result -Name ([string]$pair[0])
        if ([int]$observed -ne [int]$pair[1]) {
            throw "G100 budget telemetry mismatch: tag=$tag field=$($pair[0])"
        }
    }

    if ($Result.tag -ne $tag -or
        $Result.prompt -ne $prompt -or
        $Result.model -ne $model -or
        $Result.model_sha256 -ne $expectedModelSHA256 -or
        [string]$Result.model_hash_method -ne "verified_receipt_reuse" -or
        [string]::IsNullOrWhiteSpace([string]$Result.model_receipt_path) -or
        [string]$Result.model_receipt_sha256 -notmatch '^[0-9a-fA-F]{64}$' -or
        $Result.iq1_s_sidecar -ne $iq1Sidecar -or
        $Result.iq1_s_sidecar_sha256 -ne $expectedIq1SidecarSHA256 -or
        [string]$Result.iq1_s_sidecar_hash_method -ne
            "verified_receipt_reuse" -or
        [string]::IsNullOrWhiteSpace(
            [string]$Result.iq1_s_sidecar_receipt_path) -or
        [string]$Result.iq1_s_sidecar_receipt_sha256 -notmatch
            '^[0-9a-fA-F]{64}$' -or
        [int]$Result.server_exit_code -ne 0 -or
        [string]$Result.gate_kind -ne "structural-safety" -or
        [int]$Result.repeats -ne 1 -or
        [bool]$Result.warmup -ne $true -or
        [int]$Result.requested_max_tokens -ne 16 -or
        [int]$Result.requested_warmup_max_tokens -ne 16 -or
        [int]$Result.context_requested -ne 256 -or
        [double]$Result.dynamic_arena_gib_requested -ne 12.0 -or
        [bool]$Result.compose_prefill_mass_tiering_requested -ne $true -or
        [bool]$Result.compose_prefill_mass_open_router_requested -ne $true -or
        [int]$Result.compose_prefill_mass_reserve_slots_requested -ne
            $promotionSlots -or
        [int]$Result.expert_cache_requested -ne 320 -or
        [bool]$Result.gpu_resident_routes_requested -ne $true -or
        [bool]$Result.route_no_default_sync_requested -ne $true -or
        [bool]$Result.route_packed_copy_requested -ne $false -or
        [bool]$Result.route_packed_copy_observed -ne $false -or
        [UInt64]$Result.route_packed_copy_bytes -ne 0 -or
        [bool]$Result.iq1_s_mixed_cold_one -ne $true -or
        [bool]$Result.iq1_s_mixed_runtime_observed -ne $true -or
        [bool]$Result.iq1_s_mixed_gpu_plan_requested -ne $true -or
        [bool]$Result.iq1_s_mixed_gpu_plan_runtime_observed -ne $true -or
        [double]$Result.iq1_s_ram_cache_requested_gib -ne 1.0 -or
        [bool]$Result.iq1_promotion_requested -ne $true -or
        [bool]$Result.iq1_promotion_runtime_observed -ne $true -or
        [int]$Result.iq1_promotion_probation_slots_requested -ne
            $promotionSlots -or
        [int]$Result.iq1_promotion_line_count -ne $expectedRequests -or
        [UInt64]$Result.iq1_promotion_direct_ssd_to_vram_rejected -ne 0 -or
        [UInt64]$Result.iq1_promotion_failures -ne 0 -or
        [UInt64]$tier.failures -ne 0 -or
        [UInt64]$tier.forbidden_cold_ssd_to_vram -ne 0 -or
        [UInt64]$tier.cold_to_vram -ne 0 -or
        [UInt64]$tier.general_backing_reclaims -le 0 -or
        [string]$Result.effective_ds4_environment.DS4_CUDA_PREFILL_TIER_ROUTER -ne
            "open" -or
        [string]$Result.effective_ds4_environment.DS4_CUDA_PREFILL_TIER_RESERVE_SLOTS -ne
            ([string]$promotionSlots) -or
        [string]$Result.effective_ds4_environment.DS4_IQ1_PROMOTION_PROBATION_SLOTS -ne
            ([string]$promotionSlots) -or
        [bool]$Result.system_quiescence_preflight.skipped -ne $true -or
        [bool]$Result.quality_eligible -ne $false -or
        [bool]$Result.sota_eligible -ne $false -or
        [string]$Result.contamination_reason -ne
            "structural-safety-gate-not-quality-eligible" -or
        $Result.executable_sha256 -ne $Provenance.executable_sha256 -or
        $Result.harness_sha256 -ne $Provenance.harness_sha256 -or
        $Result.runtime_monitor_harness_sha256 -ne
            $Provenance.runtime_monitor_harness_sha256 -or
        $Result.build_manifest_sha256 -ne $Provenance.build_manifest_sha256) {
        throw "G100 structural contract mismatch: tag=$tag"
    }

    if (@($Result.iq1_promotion_requests).Count -ne $expectedRequests) {
        throw "G100 promotion request row count mismatch: tag=$tag"
    }
    [UInt64]$probationBackingReclaimsTotal = 0
    [UInt64]$promotionSsdBytesTotal = 0
    foreach ($row in @($Result.iq1_promotion_requests)) {
        foreach ($name in @("requested_slots", "reserved_slots",
            "reserve_strategy", "snapshot_evictions", "cold_observed",
            "cold_to_2bit_ram", "cold_existing_2bit",
            "promotion_2bit_ssd_bytes",
            "promotion_2bit_ssd_seconds", "direct_ssd_to_vram_rejected",
            "probation_backing_reclaims", "failures")) {
            Assert-G100Property -Object $row -Name $name -Tag $tag
        }
        $probationBackingReclaimsTotal +=
            [UInt64]$row.probation_backing_reclaims
        $promotionSsdBytesTotal += [UInt64]$row.promotion_2bit_ssd_bytes
        if ([UInt64]$row.requested_slots -ne [UInt64]$promotionSlots -or
            [UInt64]$row.reserved_slots -ne [UInt64]$promotionSlots -or
            [string]$row.reserve_strategy -ne "pre-reserved-open-router" -or
            [UInt64]$row.snapshot_evictions -ne 0 -or
            [UInt64]$row.cold_observed -le 0 -or
            [double]::IsNaN([double]$row.promotion_2bit_ssd_seconds) -or
            [double]::IsInfinity([double]$row.promotion_2bit_ssd_seconds) -or
            [double]$row.promotion_2bit_ssd_seconds -lt 0.0 -or
            [UInt64]$row.direct_ssd_to_vram_rejected -ne 0 -or
            [UInt64]$row.failures -ne 0) {
            throw "G100 promotion row contract mismatch: tag=$tag"
        }
    }
    if ($probationBackingReclaimsTotal -ne
        [UInt64]$Result.iq1_promotion_probation_backing_reclaims -or
        $promotionSsdBytesTotal -ne
            [UInt64]$Result.iq1_promotion_2bit_ssd_bytes) {
        throw "G100 promotion aggregate mismatch: tag=$tag"
    }
    [UInt64]$suppressed =
        [UInt64]$Result.iq1_promotion_skips_touches +
        [UInt64]$Result.iq1_promotion_skips_weight +
        [UInt64]$Result.iq1_promotion_skips_mass +
        [UInt64]$Result.iq1_promotion_skips_request_budget +
        [UInt64]$Result.iq1_promotion_skips_window_budget
    [UInt64]$candidates = [UInt64]$Result.iq1_promotion_cold_gate_candidates
    [UInt64]$promoted = [UInt64]$Result.iq1_promotion_cold_to_2bit_ram
    if ($candidates -le 0 -or $candidates -ne ($promoted + $suppressed)) {
        throw "G100 candidate accounting mismatch: tag=$tag"
    }
    switch ($Plan.Arm) {
        "legacy" {
            if ($promotionSsdBytesTotal -le 0 -or $suppressed -ne 0) {
                throw "G100 legacy gate contract mismatch: tag=$tag"
            }
        }
        "confirm-only" {
            if ([UInt64]$Result.iq1_promotion_skips_touches -le 0 -or
                ($suppressed -ne [UInt64]$Result.iq1_promotion_skips_touches)) {
                throw "G100 confirm-only gate did not isolate touch suppression: tag=$tag"
            }
        }
        "budget-only" {
            if ([UInt64]$Result.iq1_promotion_skips_window_budget -le 0 -or
                ($suppressed -ne [UInt64]$Result.iq1_promotion_skips_window_budget)) {
                throw "G100 budget-only gate did not isolate window suppression: tag=$tag"
            }
        }
        "weight-only" {
            [UInt64]$expectedWeightSkips = $candidates -
                [UInt64]$Result.iq1_promotion_weight_ge_002
            if ([UInt64]$Result.iq1_promotion_skips_weight -ne
                $expectedWeightSkips -or $suppressed -ne $expectedWeightSkips) {
                throw "G100 weight-only gate accounting mismatch: tag=$tag"
            }
        }
        "combined" {
            if ([UInt64]$Result.iq1_promotion_skips_touches -le 0 -or
                [UInt64]$Result.iq1_promotion_skips_window_budget -le 0 -or
                [UInt64]$Result.iq1_promotion_skips_weight -ne 0 -or
                [UInt64]$Result.iq1_promotion_skips_mass -ne 0 -or
                [UInt64]$Result.iq1_promotion_skips_request_budget -ne 0) {
                throw "G100 combined gate contract mismatch: tag=$tag"
            }
        }
    }
}

function Invoke-G100Arm {
    param(
        [Parameter(Mandatory=$true)][object]$Plan,
        [Parameter(Mandatory=$true)][object]$Provenance
    )
    $resultPath = Join-Path $outdir ("g7_" + $Plan.Tag + "_result.json")
    $rawPath = Join-Path $outdir ("g7_" + $Plan.Tag + "_raw_outputs.json")
    $failurePath = Join-Path $outdir ("g7_" + $Plan.Tag + "_failure.json")
    $args = New-G100Args -Plan $Plan

    if ($Resume -and (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        Write-Host ("[g100] resume validate tag=" + $Plan.Tag +
            " arm=" + $Plan.Arm)
    } else {
        Write-Host ("[g100] start tag=" + $Plan.Tag +
            " arm=" + $Plan.Arm + " gate=" + $Plan.Description)
        try {
            Set-G100PromotionGateEnvironment -Plan $Plan
            & powershell.exe @args | ForEach-Object { Write-Host $_ }
            if ($LASTEXITCODE -ne 0) {
                throw "G100 arm failed: $($Plan.Tag)"
            }
        } finally {
            Clear-G100PromotionGateEnvironment
        }
    }

    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        throw "G100 result missing: tag=$($Plan.Tag)"
    }
    if (-not (Test-Path -LiteralPath $rawPath -PathType Leaf)) {
        throw "G100 raw outputs missing: tag=$($Plan.Tag)"
    }
    if (Test-Path -LiteralPath $failurePath -PathType Leaf) {
        throw "G100 failure artifact present: tag=$($Plan.Tag) path=$failurePath"
    }

    $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    Assert-G100RunContract -Result $result -Plan $Plan `
        -Provenance $Provenance
    $tier = $result.expert_tiering

    [pscustomobject]@{
        arm = [string]$Plan.Arm
        tag = [string]$Plan.Tag
        description = [string]$Plan.Description
        result_path = $resultPath
        raw_outputs_path = $rawPath
        output_sha256 = [string]$result.results[0].content_sha256
        gate_config = $result.iq1_promotion_requested_config
        cold_gate_candidates =
            [UInt64]$result.iq1_promotion_cold_gate_candidates
        skips_touches = [UInt64]$result.iq1_promotion_skips_touches
        skips_weight = [UInt64]$result.iq1_promotion_skips_weight
        skips_request_budget =
            [UInt64]$result.iq1_promotion_skips_request_budget
        skips_window_budget =
            [UInt64]$result.iq1_promotion_skips_window_budget
        effective_ds4_environment = $result.effective_ds4_environment
        promotion_requested = [bool]$result.iq1_promotion_requested
        promotion_line_count = [int]$result.iq1_promotion_line_count
        promotion_ssd_bytes =
            [UInt64]$result.iq1_promotion_2bit_ssd_bytes
        promotion_ssd_seconds =
            [double]$result.iq1_promotion_2bit_ssd_seconds
        promotion_direct_rejected =
            [UInt64]$result.iq1_promotion_direct_ssd_to_vram_rejected
        promotion_failures = [UInt64]$result.iq1_promotion_failures
        promotion_probation_backing_reclaims =
            [UInt64]$result.iq1_promotion_probation_backing_reclaims
        tier_forbidden_cold_ssd_to_vram =
            [UInt64]$tier.forbidden_cold_ssd_to_vram
        tier_cold_to_vram = [UInt64]$tier.cold_to_vram
        tier_failures = [UInt64]$tier.failures
        tier_general_backing_reclaims =
            [UInt64]$tier.general_backing_reclaims
        model_hash_method = [string]$result.model_hash_method
        model_receipt_path = [string]$result.model_receipt_path
        model_receipt_sha256 = [string]$result.model_receipt_sha256
        iq1_s_sidecar_hash_method =
            [string]$result.iq1_s_sidecar_hash_method
        iq1_s_sidecar_receipt_path =
            [string]$result.iq1_s_sidecar_receipt_path
        iq1_s_sidecar_receipt_sha256 =
            [string]$result.iq1_s_sidecar_receipt_sha256
        clean = $true
    }
}

New-Item -ItemType Directory -Force -Path $outdir | Out-Null
Assert-G100StaticContract

$selectedArms = @(Get-G100SelectedArms)
$selfSha = Get-G100SHA256 $MyInvocation.MyCommand.Path
$staticChecks = [pscustomobject]@{
    schema = "g100_iq1_promotion_gate_sweep_v1"
    script_parse_ok = $true
    ast_parse_ok = $true
    static_arg_diff_ok = $true
    static_check_only = [bool]$StaticCheckOnly
    no_build_gpu_or_ds4_launch_in_static_check = [bool]$StaticCheckOnly
    selected_arm = $Arm
    selected_tags = @($selectedArms | ForEach-Object { $_.Tag })
    prompt = $prompt
    temperature = 0
    think = $false
    repeats_per_arm = 1
    mechanical_n = 1
    max_tokens = 16
    warmup_max_tokens = 16
    context = 256
    dynamic_arena_gib = 12
    iq1_s_ram_cache_gib = 1
    expert_cache_n = 320
    route_packed_copy = $false
    compose_prefill_mass_open_router = $true
    compose_prefill_mass_reserve_slots = $promotionSlots
    promotion_all_arms = $true
    receipt_reuse_required = $true
    raw_json_preserved = $true
    performance_claim = "none"
    quality_claim = "none"
    general_sota_claim = "none"
    cross_arm_equality_recorded_not_required = $true
    required_zero_failures_direct_forbidden_cold_to_vram = $true
    required_general_reclaim_positive = $true
    required_promotion_or_gate_suppression_positive = $true
    required_output_sha256 = $true
    required_new_telemetry_config_fields = @(
        "iq1_promotion_requested_config",
        "iq1_promotion_min_touches", "iq1_promotion_min_weight",
        "iq1_promotion_min_mass", "iq1_promotion_request_budget",
        "iq1_promotion_window_calls", "iq1_promotion_window_budget",
        "iq1_promotion_cold_gate_candidates",
        "iq1_promotion_skips_touches", "iq1_promotion_skips_weight",
        "iq1_promotion_skips_mass",
        "iq1_promotion_skips_request_budget",
        "iq1_promotion_skips_window_budget")
    promotion_gate_environment_fields = $promotionGateEnvNames
    arms = @($armPlan | ForEach-Object {
        [pscustomobject]@{
            arm = $_.Arm
            tag = $_.Tag
            description = $_.Description
            config = Get-G100ExpectedGateConfig -Plan $_
        }
    })
    runner_sha256 = $selfSha
}

if ($StaticCheckOnly) {
    Write-Host "[g100] static check OK; no build, GPU, DS4, or benchmark launched."
    $staticChecks | ConvertTo-Json -Depth 8
    return
}

foreach ($path in @($executable, $buildManifest)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "G100 requires existing provenance artifact; no build is launched: $path"
    }
}
$provenance = [pscustomobject]@{
    executable_sha256 = Get-G100SHA256 $executable
    harness_sha256 = Get-G100SHA256 $harness
    runtime_monitor_harness_sha256 = Get-G100SHA256 $runtimeMonitor
    ds4_cuda_sha256 = Get-G100SHA256 (Join-Path $root "ds4_cuda.cu")
    ds4_c_sha256 = Get-G100SHA256 (Join-Path $root "ds4.c")
    ds4_server_c_sha256 = Get-G100SHA256 (Join-Path $root "ds4_server.c")
    build_manifest_sha256 = Get-G100SHA256 $buildManifest
}

$runs = @()
foreach ($plan in $selectedArms) {
    $runs += Invoke-G100Arm -Plan $plan -Provenance $provenance
}

$outputHashes = @($runs | ForEach-Object { [string]$_.output_sha256 })
$crossArmEqual = $null
if ($outputHashes.Count -gt 1) {
    $crossArmEqual = (@($outputHashes | Select-Object -Unique).Count -eq 1)
}

$summary = [pscustomobject]@{
    schema = "g100_iq1_promotion_gate_sweep_v1"
    question = "IQ1 promotion gate lever isolation sweep; n1 mechanical only."
    gate_kind = "structural-safety"
    quality_eligible = $false
    sota_eligible = $false
    quality_claim = "none"
    performance_claim = "none"
    general_sota_claim = "none"
    mechanical_only_n1 = $true
    selected_arm = $Arm
    prompt = $prompt
    temperature = 0
    think = $false
    repeats_per_arm = 1
    warmup_max_tokens = 16
    max_tokens = 16
    context = 256
    dynamic_arena_gib = 12
    iq1_s_ram_cache_gib = 1
    iq1_s_layers = "3..42"
    mixed_cold_one = $true
    gpu_planner = "on in all arms"
    promotion_all_arms = $true
    promotion_slots = $promotionSlots
    compose_prefill_mass_open_router = $true
    compose_prefill_mass_reserve_slots = $promotionSlots
    route_packed_copy = $false
    raw_json_preserved = @($runs | ForEach-Object { $_.raw_outputs_path })
    result_json_preserved = @($runs | ForEach-Object { $_.result_path })
    output_sha256_by_arm = @($runs | ForEach-Object {
        [pscustomobject]@{
            arm = $_.arm
            tag = $_.tag
            output_sha256 = $_.output_sha256
        }
    })
    cross_arm_equal_recorded_not_required = $crossArmEqual
    runner_sha256 = $selfSha
    provenance = $provenance
    checks = [pscustomobject]@{
        no_performance_quality_or_sota_claim = $true
        receipt_reuse_model_and_iq1_sidecar = $true
        raw_json_preserved = $true
        all_promotion_on = $true
        no_route_packed_copy = $true
        zero_promotion_failures_direct_reject = $true
        zero_tier_failures_forbidden_cold_to_vram = $true
        general_backing_reclaims_positive_all_arms =
            (@($runs | Where-Object {
                $_.tier_general_backing_reclaims -le 0
            }).Count -eq 0)
        promotion_ssd_bytes_positive_all_arms =
            (@($runs | Where-Object {
                $_.promotion_ssd_bytes -le 0
            }).Count -eq 0)
        output_sha256_recorded_all_arms =
            (@($runs | Where-Object {
                $_.output_sha256 -notmatch '^[0-9a-fA-F]{64}$'
            }).Count -eq 0)
        new_telemetry_config_fields_validated = $true
        cross_arm_equality_required = $false
    }
    runs = $runs
}

$summary | ConvertTo-Json -Depth 10 |
    Set-Content -LiteralPath $summaryPath -Encoding UTF8
Write-Host ("[g100] gate sweep complete: " + $summaryPath)
