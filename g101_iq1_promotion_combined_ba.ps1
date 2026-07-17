# G101 IQ1_S promotion combined-gate performance B/A (PowerShell 5.1, ASCII).
param(
    [switch]$StaticCheckOnly,
    [switch]$Resume
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$harness = Join-Path $root "g7_measure.ps1"
$suiteReceiptHelper = Join-Path $root "g7_suite_receipt.ps1"
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

$summaryPath = Join-Path $outdir "g101_iq1_promotion_combined_ba_result.json"
$suiteReceiptPath = Join-Path $outdir "g101_model_iq1_suite.receipt.json"
$script:g101SuiteReceiptPath = $suiteReceiptPath
$script:g101SuiteReceiptSHA256 =
    "0000000000000000000000000000000000000000000000000000000000000000"
$promotionSlots = 16
$armPlan = @(
    [pscustomobject]@{
        Order = 1
        Arm = "candidate-combined-gate"
        Tag = "g101_iq1_promotion_combined_gate_n3"
        MinTouches = 2
        MinWeight = 0.02
        MinMass = 0.0
        RequestBudget = 16
        WindowCalls = 40
        WindowBudget = 1
        Description = "combined: touch2 minWeight.02 request-budget16 window40 budget1"
    },
    [pscustomobject]@{
        Order = 2
        Arm = "control-legacy-gate"
        Tag = "g101_iq1_promotion_legacy_gate_n3"
        MinTouches = 1
        MinWeight = 0.0
        MinMass = 0.0
        RequestBudget = 0
        WindowCalls = 0
        WindowBudget = 0
        Description = "legacy: touch1 no thresholds unlimited"
    }
)

function Get-G101SHA256 {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "G101 provenance file missing: $Path"
    }
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Open-G101ReadDenyWriteDeleteLock {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Kind
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "G101 $Kind missing before suite lock: $Path"
    }
    [IO.File]::Open(
        $Path, [IO.FileMode]::Open,
        [IO.FileAccess]::Read, [IO.FileShare]::Read)
}

function New-G101LockedSuiteReceipt {
    if (-not (Test-Path -LiteralPath $suiteReceiptHelper -PathType Leaf)) {
        throw "G101 suite receipt helper missing: $suiteReceiptHelper"
    }
    Write-Host "[g101] verifying one locked model/IQ1 suite receipt"
    $created = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
        -File $suiteReceiptHelper `
        -ModelPath $model `
        -Iq1SExpertSidecar $iq1Sidecar `
        -OutPath $suiteReceiptPath `
        -ExpectedModelSHA256 $expectedModelSHA256 `
        -ExpectedIq1SExpertSidecarSHA256 $expectedIq1SidecarSHA256 `
        -ExpectedIq1SExpertSidecarBytes $expectedIq1SidecarBytes `
        -Force | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) {
        throw "G101 suite receipt helper failed"
    }
    if ([string]$created.suite_receipt_sha256 -notmatch
        '^[0-9a-fA-F]{64}$') {
        throw "G101 suite receipt helper returned invalid SHA-256"
    }
    $script:g101SuiteReceiptPath =
        [IO.Path]::GetFullPath([string]$created.suite_receipt_path)
    $script:g101SuiteReceiptSHA256 =
        ([string]$created.suite_receipt_sha256).ToLowerInvariant()
    [pscustomobject]@{
        path = $script:g101SuiteReceiptPath
        sha256 = $script:g101SuiteReceiptSHA256
        schema = [string]$created.schema
        status = [string]$created.status
        purpose = [string]$created.purpose
    }
}

function Get-G101Property {
    param([object]$Object, [string]$Name)
    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) {
        return $null
    }
    $Object.PSObject.Properties[$Name].Value
}

function Assert-G101Property {
    param(
        [Parameter(Mandatory=$true)][object]$Object,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Tag
    )
    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) {
        throw "G101 required field missing: tag=$Tag field=$Name"
    }
}

function Convert-G101NullableString {
    param([object]$Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [double]) {
        return ([double]$Value).ToString(
            "0.################", [Globalization.CultureInfo]::InvariantCulture)
    }
    return [string]$Value
}

function Convert-G101BytesToGiB {
    param([object]$Value)
    if ($null -eq $Value) { return $null }
    [math]::Round(([double]$Value / 1GB), 6)
}

function Test-G101HarnessParameter {
    param([Parameter(Mandatory=$true)][string]$ParameterName)
    $content = Get-Content -LiteralPath $harness -Raw
    return ($content -match ("\$" + [regex]::Escape($ParameterName) +
        "(\s|=|,|\))"))
}

function Get-G101ExpectedGateConfig {
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

function Assert-G101GateConfig {
    param(
        [Parameter(Mandatory=$true)][object]$Observed,
        [Parameter(Mandatory=$true)][object]$Plan,
        [Parameter(Mandatory=$true)][string]$Tag
    )
    if ($null -eq $Observed) {
        throw "G101 promotion gate config missing: tag=$Tag"
    }
    $expected = Get-G101ExpectedGateConfig -Plan $Plan
    foreach ($name in @("min_touches", "min_weight", "min_mass",
        "request_budget", "window_calls", "window_budget")) {
        Assert-G101Property -Object $Observed -Name $name -Tag $Tag
    }
    foreach ($name in @("min_touches", "request_budget", "window_calls",
        "window_budget")) {
        if ([int](Get-G101Property $Observed $name) -ne
            [int](Get-G101Property $expected $name)) {
            throw "G101 gate integer mismatch: tag=$Tag field=$name"
        }
    }
    foreach ($name in @("min_weight", "min_mass")) {
        if ([math]::Abs([double](Get-G101Property $Observed $name) -
            [double](Get-G101Property $expected $name)) -gt 0.000001) {
            throw "G101 gate float mismatch: tag=$Tag field=$name"
        }
    }
}

function Get-G101ComparableArgs {
    param([Parameter(Mandatory=$true)][object[]]$Args)
    $normalized = @()
    $gateValueArgs = @(
        "-Iq1PromotionMinTouches", "-Iq1PromotionMinWeight",
        "-Iq1PromotionMinMass", "-Iq1PromotionRequestBudget",
        "-Iq1PromotionWindowCalls", "-Iq1PromotionWindowBudget")
    for ($i = 0; $i -lt $Args.Count; $i++) {
        $value = [string]$Args[$i]
        if ($value -eq "-Tag" -or $gateValueArgs -contains $value) {
            $i++
            continue
        }
        $normalized += $value
    }
    return $normalized
}

function New-G101Args {
    param([Parameter(Mandatory=$true)][object]$Plan)
    @(
        "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", $harness,
        "-Tag", $Plan.Tag,
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
        "-Iq1SExpertSidecar", $iq1Sidecar,
        "-ExpectedIq1SExpertSidecarSHA256", $expectedIq1SidecarSHA256,
        "-ExpectedIq1SExpertSidecarBytes", ([string]$expectedIq1SidecarBytes),
        "-ModelIq1SuiteReceiptPath", $script:g101SuiteReceiptPath,
        "-ExpectedModelIq1SuiteReceiptSHA256",
            $script:g101SuiteReceiptSHA256,
        "-ReuseVerifiedSuiteReceipt",
        "-Iq1SLayerFirst", "3",
        "-Iq1SLayerLast", "42",
        "-Iq1SMixedColdOne",
        "-Iq1SMixedGpuPlan",
        "-Iq1Promotion",
        "-Iq1PromotionProbationSlots", ([string]$promotionSlots),
        "-Iq1PromotionMinTouches", ([string]$Plan.MinTouches),
        "-Iq1PromotionMinWeight", (Convert-G101NullableString $Plan.MinWeight),
        "-Iq1PromotionMinMass", (Convert-G101NullableString $Plan.MinMass),
        "-Iq1PromotionRequestBudget", ([string]$Plan.RequestBudget),
        "-Iq1PromotionWindowCalls", ([string]$Plan.WindowCalls),
        "-Iq1PromotionWindowBudget", ([string]$Plan.WindowBudget),
        "-Iq1SRamCacheGiB", "1",
        "-GateKind", "benchmark",
        "-QuiescenceCooldownSec", "90",
        "-RuntimeMinimumAvailableGiB", "4",
        "-RuntimeMaximumDiskQueueLength", "8",
        "-RuntimeContaminationSamples", "3"
    )
}

function Assert-G101StaticContract {
    if (-not (Test-Path -LiteralPath $harness -PathType Leaf)) {
        throw "G101 harness missing: $harness"
    }
    if (-not (Test-Path -LiteralPath $runtimeMonitor -PathType Leaf)) {
        throw "G101 runtime monitor missing: $runtimeMonitor"
    }
    if (-not (Test-Path -LiteralPath $suiteReceiptHelper -PathType Leaf)) {
        throw "G101 suite receipt helper missing: $suiteReceiptHelper"
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
        "Iq1SExpertSidecar", "ExpectedIq1SExpertSidecarSHA256",
        "ExpectedIq1SExpertSidecarBytes", "ModelIq1SuiteReceiptPath",
        "ExpectedModelIq1SuiteReceiptSHA256",
        "ReuseVerifiedSuiteReceipt", "Iq1SLayerFirst",
        "Iq1SLayerLast", "Iq1SMixedColdOne", "Iq1SMixedGpuPlan",
        "Iq1Promotion", "Iq1PromotionProbationSlots",
        "Iq1PromotionMinTouches", "Iq1PromotionMinWeight",
        "Iq1PromotionMinMass", "Iq1PromotionRequestBudget",
        "Iq1PromotionWindowCalls", "Iq1PromotionWindowBudget",
        "Iq1SRamCacheGiB", "GateKind", "QuiescenceCooldownSec",
        "RuntimeMinimumAvailableGiB", "RuntimeMaximumDiskQueueLength",
        "RuntimeContaminationSamples")) {
        if (-not (Test-G101HarnessParameter -ParameterName $parameter)) {
            throw "G101 harness does not expose -$parameter; refusing to run."
        }
    }

    $harnessText = Get-Content -LiteralPath $harness -Raw
    foreach ($requiredText in @(
        "temperature = 0",
        "think = `$false",
        "runtime-contamination-abort",
        "DS4_IQ1_PROMOTION_PROBATION_SLOTS",
        "DS4_IQ1_PROMOTION_MIN_TOUCHES",
        "DS4_IQ1_PROMOTION_MIN_WEIGHT",
        "DS4_IQ1_PROMOTION_REQUEST_BUDGET",
        "DS4_IQ1_PROMOTION_WINDOW_CALLS",
        "DS4_IQ1_PROMOTION_WINDOW_BUDGET",
        "iq1_promotion_requested_config",
        "promotion_2bit_ssd_seconds",
        "iq1_promotion_runtime_observed",
        "general_backing_reclaims",
        "route_packed_copy_requested")) {
        if ($harnessText -notmatch [regex]::Escape($requiredText)) {
            throw "G101 harness static marker missing: $requiredText"
        }
    }
    foreach ($requiredText in @(
        "model_iq1_suite_full_hash_verified",
        "model_iq1_suite_lock_proof_required",
        "model_iq1_suite_lock_proof_observed",
        "ERROR_SHARING_VIOLATION")) {
        if ($harnessText -notmatch [regex]::Escape($requiredText)) {
            throw "G101 suite provenance marker missing: $requiredText"
        }
    }

    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $PSCommandPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
    if ($parseErrors -and $parseErrors.Count -gt 0) {
        throw "G101 AST parse failed: $($parseErrors[0].Message)"
    }

    $firstArgs = @(New-G101Args -Plan $armPlan[0])
    $secondArgs = @(New-G101Args -Plan $armPlan[1])
    $firstComparable = @(Get-G101ComparableArgs -Args $firstArgs)
    $secondComparable = @(Get-G101ComparableArgs -Args $secondArgs)
    if (($firstComparable -join "`n") -ne ($secondComparable -join "`n")) {
        throw "G101 static diff failed: arms differ outside tag/gate values."
    }
    foreach ($args in @($firstArgs, $secondArgs)) {
        foreach ($requiredArg in @(
            "-Iq1Promotion", "-Iq1PromotionProbationSlots",
            "-Iq1PromotionMinTouches", "-Iq1PromotionMinWeight",
            "-Iq1PromotionMinMass", "-Iq1PromotionRequestBudget",
            "-Iq1PromotionWindowCalls", "-Iq1PromotionWindowBudget",
            "-ComposePrefillMassOpenRouter",
            "-ComposePrefillMassReserveSlots",
            "-ModelIq1SuiteReceiptPath",
            "-ExpectedModelIq1SuiteReceiptSHA256",
            "-ReuseVerifiedSuiteReceipt")) {
            if (@($args | Where-Object { $_ -eq $requiredArg }).Count -ne 1) {
                throw "G101 required arg missing or duplicated: $requiredArg"
            }
        }
        foreach ($forbiddenArg in @(
            "-RoutePackedCopy",
            ("-Reuse" + "Verified" + "ModelReceipt"),
            ("-Reuse" + "Verified" + "Iq1SReceipt"))) {
            if (@($args | Where-Object { $_ -eq $forbiddenArg }).Count -ne 0) {
                throw "G101 benchmark must not use $forbiddenArg."
            }
        }
    }

    if ($expectedModelSHA256 -notmatch '^[0-9a-f]{64}$' -or
        $expectedIq1SidecarSHA256 -notmatch '^[0-9a-f]{64}$' -or
        $expectedPromptSHA256 -notmatch '^[0-9a-f]{64}$' -or
        $expectedIq1SidecarBytes -le 0) {
        throw "G101 provenance constants are invalid."
    }
}

function Assert-G101RunContract {
    param(
        [Parameter(Mandatory=$true)][object]$Result,
        [Parameter(Mandatory=$true)][object]$Plan,
        [Parameter(Mandatory=$true)][object]$Provenance
    )

    $tag = [string]$Plan.Tag
    foreach ($name in @(
        "server_exit_code", "prompt_sha256", "warmup_prompt_sha256",
        "model_sha256", "model_hash_method", "model_receipt_path",
        "model_receipt_sha256", "model_iq1_suite_receipt_path",
        "model_iq1_suite_receipt_sha256",
        "model_iq1_suite_full_hash_verified",
        "model_iq1_suite_lock_proof_required",
        "model_iq1_suite_lock_proof_observed",
        "model_iq1_suite_lock_proof", "iq1_s_sidecar_sha256",
        "iq1_s_sidecar_hash_method", "iq1_s_sidecar_receipt_path",
        "iq1_s_sidecar_receipt_sha256", "iq1_s_mixed_runtime_observed",
        "iq1_s_mixed_gpu_plan_requested",
        "iq1_s_mixed_gpu_plan_runtime_observed",
        "iq1_promotion_requested", "iq1_promotion_requested_config",
        "iq1_promotion_probation_slots_requested",
        "iq1_promotion_runtime_observed", "iq1_promotion_line_count",
        "iq1_promotion_min_touches", "iq1_promotion_min_weight",
        "iq1_promotion_min_mass", "iq1_promotion_request_budget",
        "iq1_promotion_window_calls", "iq1_promotion_window_budget",
        "iq1_promotion_cold_gate_candidates",
        "iq1_promotion_skips_touches", "iq1_promotion_skips_weight",
        "iq1_promotion_skips_mass",
        "iq1_promotion_skips_request_budget",
        "iq1_promotion_skips_window_budget",
        "iq1_promotion_2bit_ssd_bytes",
        "iq1_promotion_2bit_ssd_seconds",
        "iq1_promotion_2bit_ssd_bytes_per_second",
        "iq1_promotion_direct_ssd_to_vram_rejected",
        "iq1_promotion_failures", "effective_ds4_environment",
        "compose_prefill_mass_open_router_requested",
        "compose_prefill_mass_reserve_slots_requested",
        "route_packed_copy_requested", "route_packed_copy_observed",
        "expert_tiering", "runtime_telemetry",
        "system_quiescence_preflight")) {
        Assert-G101Property -Object $Result -Name $name -Tag $tag
    }

    Assert-G101GateConfig -Observed $Result.iq1_promotion_requested_config `
        -Plan $Plan -Tag $tag
    $tier = $Result.expert_tiering
    $rt = $Result.runtime_telemetry
    $sys = $Result.system_quiescence_preflight
    foreach ($name in @("failures", "forbidden_cold_ssd_to_vram",
        "cold_to_vram", "general_backing_reclaims")) {
        Assert-G101Property -Object $tier -Name $name -Tag $tag
    }

    $contentHashes = @($Result.results | ForEach-Object {
        [string]$_.content_sha256
    })
    if ($contentHashes.Count -ne 3) {
        throw "G101 repeat count mismatch: tag=$tag"
    }
    $uniqueContentHashes = @($contentHashes | Select-Object -Unique)
    if ($uniqueContentHashes.Count -ne 1) {
        throw "G101 intra-arm determinism failed: tag=$tag"
    }
    foreach ($hash in $contentHashes) {
        if ($hash -notmatch '^[0-9a-fA-F]{64}$') {
            throw "G101 invalid content hash: tag=$tag"
        }
    }

    if ($Result.tag -ne $tag -or
        $Result.prompt -ne $prompt -or
        $Result.prompt_sha256 -ne $expectedPromptSHA256 -or
        $Result.warmup_prompt_sha256 -ne $expectedPromptSHA256 -or
        $Result.model -ne $model -or
        $Result.model_sha256 -ne $expectedModelSHA256 -or
        [string]$Result.model_hash_method -ne
            "verified_suite_receipt_reuse" -or
        [string]::IsNullOrWhiteSpace(
            [string]$Result.model_receipt_path) -or
        [string]$Result.model_receipt_sha256 -notmatch
            '^[0-9a-fA-F]{64}$' -or
        [string]$Result.model_iq1_suite_receipt_path -ne
            $script:g101SuiteReceiptPath -or
        [string]$Result.model_iq1_suite_receipt_sha256 -ne
            $script:g101SuiteReceiptSHA256 -or
        [bool]$Result.model_iq1_suite_full_hash_verified -ne $true -or
        [bool]$Result.model_iq1_suite_lock_proof_required -ne $true -or
        [bool]$Result.model_iq1_suite_lock_proof_observed -ne $true -or
        [UInt64]$Result.model_bytes -le 0 -or
        $Result.iq1_s_sidecar -ne $iq1Sidecar -or
        $Result.iq1_s_sidecar_sha256 -ne $expectedIq1SidecarSHA256 -or
        [string]$Result.iq1_s_sidecar_hash_method -ne
            "verified_suite_receipt_reuse" -or
        [string]::IsNullOrWhiteSpace(
            [string]$Result.iq1_s_sidecar_receipt_path) -or
        [string]$Result.iq1_s_sidecar_receipt_sha256 -notmatch
            '^[0-9a-fA-F]{64}$' -or
        [UInt64]$Result.iq1_s_sidecar_bytes -ne $expectedIq1SidecarBytes -or
        [int]$Result.server_exit_code -ne 0 -or
        [string]$Result.gate_kind -ne "benchmark" -or
        [int]$Result.repeats -ne 3 -or
        [bool]$Result.warmup -ne $true -or
        [int]$Result.requested_max_tokens -ne 64 -or
        [int]$Result.requested_warmup_max_tokens -ne 64 -or
        [int]$Result.context_requested -ne 256 -or
        [int]$Result.context_observed -ne 256 -or
        [double]$Result.dynamic_arena_gib_requested -ne 12.0 -or
        [bool]$Result.outputs_identical -ne $true -or
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
        [string]$Result.effective_ds4_environment.DS4_IQ1_PROMOTION_MIN_TOUCHES -ne
            ([string]$Plan.MinTouches) -or
        [bool]$sys.skipped -ne $false -or
        [int]$sys.requested_cooldown_seconds -ne 90 -or
        [bool]$sys.ready_to_launch -ne $true -or
        [bool]$rt.contamination_abort_observed -ne $false -or
        [string]$Result.contamination_reason -ne "" -or
        $Result.executable_sha256 -ne $Provenance.executable_sha256 -or
        $Result.harness_sha256 -ne $Provenance.harness_sha256 -or
        $Result.runtime_monitor_harness_sha256 -ne
            $Provenance.runtime_monitor_harness_sha256 -or
        $Result.ds4_cuda_sha256 -ne $Provenance.ds4_cuda_sha256 -or
        $Result.ds4_c_sha256 -ne $Provenance.ds4_c_sha256 -or
        $Result.ds4_server_c_sha256 -ne $Provenance.ds4_server_c_sha256 -or
        $Result.build_manifest_sha256 -ne $Provenance.build_manifest_sha256) {
        throw "G101 contract mismatch: tag=$tag arm=$($Plan.Arm)"
    }

    foreach ($pair in @(
        @("iq1_promotion_min_touches", $Plan.MinTouches),
        @("iq1_promotion_request_budget", $Plan.RequestBudget),
        @("iq1_promotion_window_calls", $Plan.WindowCalls),
        @("iq1_promotion_window_budget", $Plan.WindowBudget))) {
        if ([int](Get-G101Property $Result ([string]$pair[0])) -ne
            [int]$pair[1]) {
            throw "G101 promotion integer telemetry mismatch: tag=$tag field=$($pair[0])"
        }
    }
    foreach ($pair in @(
        @("iq1_promotion_min_weight", $Plan.MinWeight),
        @("iq1_promotion_min_mass", $Plan.MinMass))) {
        if ([math]::Abs([double](Get-G101Property $Result ([string]$pair[0])) -
            [double]$pair[1]) -gt 0.000001) {
            throw "G101 promotion float telemetry mismatch: tag=$tag field=$($pair[0])"
        }
    }

    $lockProof = $Result.model_iq1_suite_lock_proof
    if ($null -eq $lockProof -or
        [bool]$lockProof.required -ne $true -or
        [bool]$lockProof.observed -ne $true -or
        [bool]$lockProof.model.sharing_violation_lock_proof -ne $true -or
        [bool]$lockProof.iq1_s_sidecar.sharing_violation_lock_proof -ne
            $true -or
        [string]$lockProof.model.deny_write_error -ne
            "ERROR_SHARING_VIOLATION" -or
        [string]$lockProof.model.deny_delete_error -ne
            "ERROR_SHARING_VIOLATION" -or
        [string]$lockProof.iq1_s_sidecar.deny_write_error -ne
            "ERROR_SHARING_VIOLATION" -or
        [string]$lockProof.iq1_s_sidecar.deny_delete_error -ne
            "ERROR_SHARING_VIOLATION") {
        throw "G101 suite lock proof mismatch: tag=$tag"
    }

    $expectedRequests = [int]$Result.request_count_expected
    if ($expectedRequests -le 0 -or
        [int]$Result.iq1_promotion_line_count -ne $expectedRequests -or
        @($Result.iq1_promotion_requests).Count -ne $expectedRequests) {
        throw "G101 promotion request coverage mismatch: tag=$tag"
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
        throw "G101 promotion candidate accounting mismatch: tag=$tag"
    }
    if ($Plan.Arm -eq "control-legacy-gate" -and $suppressed -ne 0) {
        throw "G101 legacy gate unexpectedly suppressed promotions: tag=$tag"
    }
    if ($Plan.Arm -eq "candidate-combined-gate" -and $suppressed -le 0) {
        throw "G101 combined gate did not suppress any promotion candidates: tag=$tag"
    }
}

function Assert-G101RawBinding {
    param(
        [Parameter(Mandatory=$true)][object]$Raw,
        [Parameter(Mandatory=$true)][object]$Result,
        [Parameter(Mandatory=$true)][object]$Plan
    )
    $tag = [string]$Plan.Tag
    foreach ($name in @(
        "schema", "tag", "gate_kind", "contamination_reason", "head",
        "executable_sha256", "ds4_cuda_sha256", "model_sha256",
        "iq1_s_sidecar_sha256", "prompt_sha256", "system_prompt_sha256",
        "model_iq1_suite_receipt_path",
        "model_iq1_suite_receipt_sha256",
        "model_iq1_suite_receipt_schema",
        "model_iq1_suite_full_hash_verified",
        "model_iq1_suite_lock_proof",
        "output_hashes", "results")) {
        Assert-G101Property -Object $Raw -Name $name -Tag $tag
    }
    if ([string]$Raw.schema -ne "g7_raw_outputs_v1" -or
        [string]$Raw.tag -ne [string]$Result.tag -or
        [string]$Raw.gate_kind -ne [string]$Result.gate_kind -or
        [string]$Raw.contamination_reason -ne
            [string]$Result.contamination_reason -or
        [string]$Raw.head -ne [string]$Result.head -or
        [string]$Raw.executable_sha256 -ne
            [string]$Result.executable_sha256 -or
        [string]$Raw.ds4_cuda_sha256 -ne
            [string]$Result.ds4_cuda_sha256 -or
        [string]$Raw.model_sha256 -ne [string]$Result.model_sha256 -or
        [string]$Raw.iq1_s_sidecar_sha256 -ne
            [string]$Result.iq1_s_sidecar_sha256 -or
        [string]$Raw.prompt_sha256 -ne [string]$Result.prompt_sha256 -or
        [string]$Raw.system_prompt_sha256 -ne
            [string]$Result.system_prompt_sha256 -or
        [string]$Raw.model_iq1_suite_receipt_path -ne
            [string]$Result.model_iq1_suite_receipt_path -or
        [string]$Raw.model_iq1_suite_receipt_sha256 -ne
            [string]$Result.model_iq1_suite_receipt_sha256 -or
        [string]$Raw.model_iq1_suite_receipt_schema -ne
            [string]$Result.model_iq1_suite_receipt_schema -or
        [bool]$Raw.model_iq1_suite_full_hash_verified -ne
            [bool]$Result.model_iq1_suite_full_hash_verified -or
        ($Raw.model_iq1_suite_lock_proof | ConvertTo-Json -Depth 8 -Compress) -ne
            ($Result.model_iq1_suite_lock_proof |
                ConvertTo-Json -Depth 8 -Compress)) {
        throw "G101 raw/result provenance mismatch: tag=$tag"
    }
    $rawHashes = @($Raw.output_hashes | ForEach-Object { [string]$_ })
    $rawResultHashes = @($Raw.results | ForEach-Object {
        [string]$_.content_sha256
    })
    $resultHashes = @($Result.results | ForEach-Object {
        [string]$_.content_sha256
    })
    if ($rawHashes.Count -ne $resultHashes.Count -or
        $rawResultHashes.Count -ne $resultHashes.Count -or
        ($rawHashes -join "`n") -ne ($resultHashes -join "`n") -or
        ($rawResultHashes -join "`n") -ne ($resultHashes -join "`n")) {
        throw "G101 raw/result output hash mismatch: tag=$tag"
    }
}

function Invoke-G101Arm {
    param(
        [Parameter(Mandatory=$true)][object]$Plan,
        [Parameter(Mandatory=$true)][object]$Provenance
    )

    $resultPath = Join-Path $outdir ("g7_" + $Plan.Tag + "_result.json")
    $rawPath = Join-Path $outdir ("g7_" + $Plan.Tag + "_raw_outputs.json")
    $failurePath = Join-Path $outdir ("g7_" + $Plan.Tag + "_failure.json")
    $args = New-G101Args -Plan $Plan

    Write-Host ("[g101] start tag=" + $Plan.Tag +
        " arm=" + $Plan.Arm + " gate=" + $Plan.Description)
    & powershell.exe @args | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) {
        throw "G101 arm failed: $($Plan.Tag)"
    }

    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        throw "G101 result missing: tag=$($Plan.Tag)"
    }
    if (-not (Test-Path -LiteralPath $rawPath -PathType Leaf)) {
        throw "G101 raw outputs missing: tag=$($Plan.Tag)"
    }
    if (Test-Path -LiteralPath $failurePath -PathType Leaf) {
        throw "G101 failure artifact present: tag=$($Plan.Tag) path=$failurePath"
    }

    $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    Assert-G101RunContract -Result $result -Plan $Plan -Provenance $Provenance
    $raw = Get-Content -LiteralPath $rawPath -Raw | ConvertFrom-Json
    Assert-G101RawBinding -Raw $raw -Result $result -Plan $Plan
    $tier = $result.expert_tiering
    $rt = $result.runtime_telemetry
    $sys = $result.system_quiescence_preflight
    $clean = [bool](
        [bool]$sys.skipped -eq $false -and
        [bool]$sys.ready_to_launch -eq $true -and
        [bool]$rt.contamination_abort_observed -eq $false -and
        [string]$result.contamination_reason -eq "")

    [pscustomobject]@{
        order = [int]$Plan.Order
        tag = [string]$Plan.Tag
        arm = [string]$Plan.Arm
        gate_description = [string]$Plan.Description
        gate_config = $result.iq1_promotion_requested_config
        result_path = $resultPath
        result_sha256 = Get-G101SHA256 $resultPath
        raw_outputs_path = $rawPath
        raw_outputs_sha256 = Get-G101SHA256 $rawPath
        effective_ds4_environment = $result.effective_ds4_environment
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
        model_hash_method = $result.model_hash_method
        model_receipt_path = $result.model_receipt_path
        model_receipt_sha256 = $result.model_receipt_sha256
        model_iq1_suite_receipt_path =
            $result.model_iq1_suite_receipt_path
        model_iq1_suite_receipt_sha256 =
            $result.model_iq1_suite_receipt_sha256
        model_iq1_suite_full_hash_verified =
            [bool]$result.model_iq1_suite_full_hash_verified
        model_iq1_suite_lock_proof_required =
            [bool]$result.model_iq1_suite_lock_proof_required
        model_iq1_suite_lock_proof_observed =
            [bool]$result.model_iq1_suite_lock_proof_observed
        model_iq1_suite_lock_proof = $result.model_iq1_suite_lock_proof
        iq1_s_sidecar = $result.iq1_s_sidecar
        iq1_s_sidecar_bytes = [UInt64]$result.iq1_s_sidecar_bytes
        iq1_s_sidecar_sha256 = $result.iq1_s_sidecar_sha256
        iq1_s_sidecar_hash_method = $result.iq1_s_sidecar_hash_method
        iq1_s_sidecar_receipt_path = $result.iq1_s_sidecar_receipt_path
        iq1_s_sidecar_receipt_sha256 =
            $result.iq1_s_sidecar_receipt_sha256
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
        tier_general_backing_reclaims =
            [UInt64]$tier.general_backing_reclaims
        tier_ram_h2d_gib = Convert-G101BytesToGiB $tier.ram_h2d_bytes
        promotion_line_count = [int]$result.iq1_promotion_line_count
        promotion_cold_gate_candidates =
            [UInt64]$result.iq1_promotion_cold_gate_candidates
        promotion_cold_to_2bit_ram =
            [UInt64]$result.iq1_promotion_cold_to_2bit_ram
        promotion_skips_touches =
            [UInt64]$result.iq1_promotion_skips_touches
        promotion_skips_weight =
            [UInt64]$result.iq1_promotion_skips_weight
        promotion_skips_mass =
            [UInt64]$result.iq1_promotion_skips_mass
        promotion_skips_request_budget =
            [UInt64]$result.iq1_promotion_skips_request_budget
        promotion_skips_window_budget =
            [UInt64]$result.iq1_promotion_skips_window_budget
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
            Convert-G101BytesToGiB $rt.win32_process_read_transfer_delta_bytes
        aggregate_disk_read_gib =
            Convert-G101BytesToGiB $rt.aggregate_disk_read_bytes_estimated
        contamination_abort_observed =
            [bool]$rt.contamination_abort_observed
        clean = $clean
    }
}

New-Item -ItemType Directory -Force -Path $outdir | Out-Null
Assert-G101StaticContract

if ($Resume -and -not $StaticCheckOnly) {
    throw "G101 -Resume is intentionally unsupported for the immutable one-hash BA suite; rerun the complete suite."
}

$selfSha = Get-G101SHA256 $MyInvocation.MyCommand.Path
$staticChecks = [pscustomobject]@{
    schema = "g101_iq1_promotion_combined_ba_static_v1"
    script_parse_ok = $true
    ast_parse_ok = $true
    static_diff_ok = $true
    harness_present = (Test-Path -LiteralPath $harness -PathType Leaf)
    runtime_monitor_present =
        (Test-Path -LiteralPath $runtimeMonitor -PathType Leaf)
    suite_receipt_helper_present =
        (Test-Path -LiteralPath $suiteReceiptHelper -PathType Leaf)
    static_check_only = [bool]$StaticCheckOnly
    resume_supported = $false
    no_build_gpu_or_ds4_launch_in_static_check = [bool]$StaticCheckOnly
    prompt_sha256 = $expectedPromptSHA256
    temperature_zero_and_nothink_harness_static_marker = $true
    repeats_per_arm = 3
    minimum_n_per_arm = 3
    warmup_max_tokens = 64
    max_tokens = 64
    context = 256
    dynamic_arena_gib = 12
    iq1_s_ram_cache_gib = 1
    expert_cache_n = 320
    open_router_slots = $promotionSlots
    route_packed_copy = $false
    packed_copy_policy = "disabled"
    iq1_sidecar = $iq1Sidecar
    iq1_sidecar_cache_gib = 1
    promotion_enabled_both_arms = $true
    arm_order = "combined-then-legacy-fixed-BA"
    opposite_order_to_g98 = $true
    order_counterbalanced = $false
    fixed_ba_order_limitation_recorded = $true
    final_performance_verdict = "withheld_fixed_BA_order_limitation"
    performance_claim_label =
        "clean n=3 timing may be recorded, but final claim withheld due fixed BA order"
    quality_claim = "none"
    long_form_l0_l3_claim = "none"
    quiescence_required = $true
    quiescence_cooldown_seconds = 90
    contamination_abort_fail_closed = $true
    model_hash_method_required = "verified_suite_receipt_reuse"
    iq1_s_sidecar_hash_method_required = "verified_suite_receipt_reuse"
    one_suite_hash_per_ba_suite_required = $true
    parent_held_deny_write_delete_locks_required = $true
    metadata_only_receipt_reuse_for_benchmark_forbidden = $true
    raw_json_preserved = $true
    exact_hashes_required = $true
    arms = @($armPlan | ForEach-Object {
        [pscustomobject]@{
            order = $_.Order
            arm = $_.Arm
            tag = $_.Tag
            description = $_.Description
            config = Get-G101ExpectedGateConfig -Plan $_
        }
    })
    runner_sha256 = $selfSha
}

if ($StaticCheckOnly) {
    Write-Host "[g101] static check OK; no build, GPU, DS4, or benchmark launched."
    $staticChecks | ConvertTo-Json -Depth 8
    return
}

foreach ($path in @($executable, $buildManifest)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "G101 requires existing provenance artifact; no build is launched: $path"
    }
}
$provenance = [pscustomobject]@{
    executable_sha256 = Get-G101SHA256 $executable
    harness_sha256 = Get-G101SHA256 $harness
    runtime_monitor_harness_sha256 = Get-G101SHA256 $runtimeMonitor
    ds4_cuda_sha256 = Get-G101SHA256 (Join-Path $root "ds4_cuda.cu")
    ds4_c_sha256 = Get-G101SHA256 (Join-Path $root "ds4.c")
    ds4_server_c_sha256 = Get-G101SHA256 (Join-Path $root "ds4_server.c")
    build_manifest_sha256 = Get-G101SHA256 $buildManifest
}

$runs = @()
$suiteReceipt = $null
$modelSuiteLock = $null
$iq1SuiteLock = $null
try {
    $modelSuiteLock = Open-G101ReadDenyWriteDeleteLock -Path $model `
        -Kind "model"
    $iq1SuiteLock = Open-G101ReadDenyWriteDeleteLock -Path $iq1Sidecar `
        -Kind "IQ1_S sidecar"
    $suiteReceipt = New-G101LockedSuiteReceipt
    foreach ($plan in $armPlan) {
        $runs += Invoke-G101Arm -Plan $plan -Provenance $provenance
    }
} finally {
    if ($null -ne $iq1SuiteLock) {
        try { $iq1SuiteLock.Dispose() } catch {}
    }
    if ($null -ne $modelSuiteLock) {
        try { $modelSuiteLock.Dispose() } catch {}
    }
}

foreach ($field in @(
    "head", "executable_sha256", "ds4_cuda_sha256", "ds4_c_sha256",
    "ds4_server_c_sha256", "build_manifest_sha256",
    "build_input_fingerprint_sha256", "harness_sha256",
    "runtime_monitor_harness_sha256", "model", "model_bytes",
    "model_sha256", "model_hash_method", "model_receipt_path",
    "model_receipt_sha256", "model_iq1_suite_receipt_path",
    "model_iq1_suite_receipt_sha256",
    "model_iq1_suite_full_hash_verified",
    "model_iq1_suite_lock_proof_required",
    "model_iq1_suite_lock_proof_observed", "iq1_s_sidecar",
    "iq1_s_sidecar_bytes", "iq1_s_sidecar_sha256",
    "iq1_s_sidecar_hash_method", "iq1_s_sidecar_receipt_path",
    "iq1_s_sidecar_receipt_sha256", "repeat_count",
    "outputs_identical")) {
    $values = @($runs | ForEach-Object { [string]($_.$field) } |
        Select-Object -Unique)
    if ($values.Count -ne 1) {
        throw "G101 mixed provenance/settings across arms: field=$field"
    }
}

$combined = @($runs | Where-Object {
    $_.arm -eq "candidate-combined-gate"
})[0]
$legacy = @($runs | Where-Object {
    $_.arm -eq "control-legacy-gate"
})[0]
if ($combined.repeat_count -lt 3 -or $legacy.repeat_count -lt 3) {
    throw "G101 n>=3 requirement not met."
}
$bothClean = @($runs | Where-Object { -not $_.clean }).Count -eq 0
$timingValid = [bool]($bothClean -and
    $combined.repeat_count -ge 3 -and $legacy.repeat_count -ge 3 -and
    [double]$combined.server_decode_mean_tokens_per_second -gt 0.0 -and
    [double]$legacy.server_decode_mean_tokens_per_second -gt 0.0)
$decodeDeltaPercent = if ($timingValid) {
    [math]::Round(
        100.0 * ([double]$combined.server_decode_mean_tokens_per_second -
        [double]$legacy.server_decode_mean_tokens_per_second) /
        [double]$legacy.server_decode_mean_tokens_per_second, 6)
} else { $null }
$harnessDeltaPercent = if ($timingValid -and
    [double]$legacy.mean_tokens_per_second -gt 0.0) {
    [math]::Round(
        100.0 * ([double]$combined.mean_tokens_per_second -
        [double]$legacy.mean_tokens_per_second) /
        [double]$legacy.mean_tokens_per_second, 6)
} else { $null }
$crossArmEqual = ([string]$combined.deterministic_content_sha256 -eq
    [string]$legacy.deterministic_content_sha256)

$summary = [pscustomobject]@{
    schema = "g101_iq1_promotion_combined_ba_v1"
    question = "Combined IQ1 promotion gate versus legacy gate, promotion enabled in both arms, fixed B/A order."
    gate_kind = "benchmark"
    quality_claim = "none"
    general_sota_claim = "none"
    long_form_l0_l3_claim = "none"
    performance_claim =
        "withheld: fixed combined-then-legacy BA order is exploratory only"
    final_performance_verdict = "withheld_fixed_BA_order_limitation"
    fixed_ba_order_limitation =
        "Combined gate always runs before legacy gate; order is not counterbalanced."
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
    promotion_enabled_both_arms = $true
    promotion_slots = $promotionSlots
    compose_prefill_mass_open_router = $true
    compose_prefill_mass_reserve_slots = $promotionSlots
    arm_order = "combined-then-legacy-fixed-BA"
    order_counterbalanced = $false
    opposite_order_to_g98 = $true
    quiescence = [pscustomobject]@{
        skipped = $false
        cooldown_seconds = 90
        abort_fail_closed_on_contamination = $true
    }
    route = [pscustomobject]@{
        gpu_resident_routes = $true
        route_no_default_sync = $true
        route_packed_copy = $false
        split_fused = $true
        reap_prefetch_threads = 8
    }
    hashing = [pscustomobject]@{
        model_hash_method_required = "verified_suite_receipt_reuse"
        iq1_s_sidecar_hash_method_required = "verified_suite_receipt_reuse"
        suite_receipt_reuse = $true
        suite_receipt_path = $suiteReceipt.path
        suite_receipt_sha256 = $suiteReceipt.sha256
        one_suite_hash_per_ba_suite = $true
        parent_held_deny_write_delete_locks =
            ($combined.model_iq1_suite_lock_proof_observed -and
            $legacy.model_iq1_suite_lock_proof_observed)
        metadata_only_receipt_reuse_for_benchmark = $false
        exact_hashes_recorded = $true
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
        same_provenance_binary_harness_config_except_gate_values = $true
        clean_quiescence = $bothClean
        n_ge_3_each_arm = $true
        intra_arm_determinism = $true
        cross_arm_equal_recorded_not_required = $crossArmEqual
        promotion_enabled_both_arms = $true
        combined_gate_first = $true
        legacy_gate_second = $true
        fixed_ba_order_limitation_recorded = $true
        suite_receipt_reuse_for_benchmark = $true
        metadata_only_receipt_reuse_for_benchmark_forbidden = $true
        one_suite_hash_reused_by_both_arms =
            ([string]$combined.model_iq1_suite_receipt_sha256 -eq
            [string]$legacy.model_iq1_suite_receipt_sha256)
        parent_held_locks_observed_both_arms =
            ($combined.model_iq1_suite_lock_proof_observed -and
            $legacy.model_iq1_suite_lock_proof_observed)
        raw_json_preserved = $true
        exact_hashes_recorded = $true
        no_route_packed_copy = $true
        gpu_planner_on_both_arms = $true
        direct_reject_failures_forbidden_cold_to_vram_zero = $true
        general_backing_reclaims_positive_both_arms =
            ($combined.tier_general_backing_reclaims -gt 0 -and
            $legacy.tier_general_backing_reclaims -gt 0)
        timing_contract_satisfied = $timingValid
        performance_claim_allowed = $false
        long_form_l0_l3_claim_allowed = $false
        performance_verdict_blocked_reason =
            "fixed combined-then-legacy BA order; no counterbalanced AB/BA pair"
    }
    runs = $runs
    deltas = [pscustomobject]@{
        combined_minus_legacy_decode_tps =
            [math]::Round([double]$combined.server_decode_mean_tokens_per_second -
            [double]$legacy.server_decode_mean_tokens_per_second, 6)
        combined_minus_legacy_decode_tps_percent = $decodeDeltaPercent
        combined_minus_legacy_harness_tps =
            [math]::Round([double]$combined.mean_tokens_per_second -
            [double]$legacy.mean_tokens_per_second, 6)
        combined_minus_legacy_harness_tps_percent = $harnessDeltaPercent
        combined_minus_legacy_ttft_seconds =
            [math]::Round([double]$combined.server_prefill_ttft_mean_seconds -
            [double]$legacy.server_prefill_ttft_mean_seconds, 6)
    }
}

$summary | ConvertTo-Json -Depth 10 |
    Set-Content -LiteralPath $summaryPath -Encoding UTF8
Write-Host ("[g101] B/A complete: " + $summaryPath)
