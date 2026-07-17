# G99 IQ1_S promotion quality A/B (PowerShell 5.1, ASCII).
# Scope: isolates incremental quality effect of promotion only.
# This does not replace G95 main-IQ2 versus mixed-IQ1 quality A/B.
param(
    [switch]$StaticCheckOnly,
    [switch]$Resume,
    [switch]$ForceOverwrite,
    [ValidateRange(1.0, 8.0)][double]$Iq1CacheGiB = 4.0,
    [ValidateRange(1, 512)][int]$PromotionSlots = 16
)

$ErrorActionPreference = "Stop"
$runnerPath = $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $runnerPath
$harness = Join-Path $root "g7_measure.ps1"
$runtimeMonitor = Join-Path $root "g7_runtime_monitor.ps1"
$buildRunner = Join-Path $root "g7_build.ps1"
$outdir = Join-Path $root "g7_runs"
$model = "C:\ds4-models\ds4-2bit.gguf"
$modelSha256 = "efc7ed607ff27076e3e501fc3fefefa33c0ed8cf1eff483a2b7fdc0c2e616668"
$sidecar = "D:\ds4-models\DeepSeek-V4-Flash-IQ1_S-XL.gguf"
[UInt64]$sidecarBytes = 61540805344
$sidecarSha256 = "b049d1eb34c068f19ab007b33c22a7d758b578bf2b10d9276e79654f85d35047"
$sidecarSource = "https://huggingface.co/persadian/DeepSeek-V4-Flash-IQ1_S-XL/resolve/main/DeepSeek-V4-Flash-IQ1_S-XL.gguf"
$sidecarSourceRepository = "https://huggingface.co/persadian/DeepSeek-V4-Flash-IQ1_S-XL"
$sentinel = "G99_IQ1_PROMOTION_QUALITY_AB_DONE"
$prompt = "Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the complete HTML document, then append exactly this sentinel on its own line after the closing </html>: $sentinel"
$promptSha256 = "c14268fd7416d64fe8ddf81692a6fd40c1d87e0893d2ae80d7b4dfe1e7a5f5e0"
$repeatsPerArm = 3
$maxTokens = 768
$context = 1024
$warmupMaxTokens = 64
$stopSequence = $sentinel
$quiescenceCooldownSec = 90
$timeoutSec = 7200
$armDeadlineSec = 7800
$buildDeadlineSec = 1800
$globalDeadlineSec = 18000
$cacheLabel = $Iq1CacheGiB.ToString(
    "0.###", [Globalization.CultureInfo]::InvariantCulture).Replace(".", "p")
$cacheArgument = $Iq1CacheGiB.ToString(
    "0.###", [Globalization.CultureInfo]::InvariantCulture)
$controlTag = "g99_control_iq1_promotion_off_cache${cacheLabel}_quality_n3"
$candidateTag = "g99_candidate_iq1_promotion_slots${PromotionSlots}_cache${cacheLabel}_quality_n3"
$summaryPath = Join-Path $outdir "g99_iq1_promotion_quality_ab_result.json"
$gradingPath = Join-Path $outdir "g99_iq1_promotion_quality_ab_grading.json"
$sideBySidePath = Join-Path $outdir "g99_iq1_promotion_quality_ab_side_by_side.html"

function Get-G99ResultPath([string]$Tag) {
    Join-Path $outdir ("g7_" + $Tag + "_result.json")
}

function Get-G99RawPath([string]$Tag) {
    Join-Path $outdir ("g7_" + $Tag + "_raw_outputs.json")
}

function Get-G99FailurePath([string]$Tag) {
    Join-Path $outdir ("g7_" + $Tag + "_failure.json")
}

function Get-G99Sha256([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "G99 provenance file missing: $Path"
    }
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-G99TextSha256([string]$Text) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Test-G99HarnessParameter {
    param([Parameter(Mandatory=$true)][string]$ParameterName)
    $content = Get-Content -LiteralPath $harness -Raw
    return ($content -match ("\$" + [regex]::Escape($ParameterName) +
        "(\s|=|,|\))"))
}

function Assert-G99Property {
    param(
        [Parameter(Mandatory=$true)][object]$Object,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Context
    )
    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) {
        throw "G99 required field missing: context=$Context field=$Name"
    }
}

function Get-G99PropertyValue {
    param([object]$Object, [string]$Name)
    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) {
        return $null
    }
    $Object.PSObject.Properties[$Name].Value
}

function Get-G99SampleText {
    param([Parameter(Mandatory=$true)][object]$Sample)
    foreach ($name in @("content", "output", "text", "completion")) {
        $value = Get-G99PropertyValue -Object $Sample -Name $name
        if ($null -ne $value) { return [string]$value }
    }
    return ""
}

function Convert-G99Html {
    param([string]$Text)
    [Net.WebUtility]::HtmlEncode($Text)
}

function Join-G99ProcessArguments {
    param([Parameter(Mandatory=$true)][string[]]$Arguments)
    $quoted = @()
    foreach ($arg in $Arguments) {
        $quoted += ('"' + (($arg -replace '\\(?=")', '$0\') -replace '"', '\"') + '"')
    }
    $quoted -join " "
}

function Invoke-G99PowerShellWithDeadline {
    param(
        [Parameter(Mandatory=$true)][string[]]$Arguments,
        [Parameter(Mandatory=$true)][int]$DeadlineSec,
        [Parameter(Mandatory=$true)][string]$Context
    )
    $remainingSec = $DeadlineSec
    if ($script:globalDeadlineUtc) {
        $remainingSec = [int][Math]::Floor(
            ($script:globalDeadlineUtc - [DateTime]::UtcNow).TotalSeconds)
        $remainingSec = [Math]::Min($remainingSec, $DeadlineSec)
    }
    if ($remainingSec -le 0) {
        throw "G99 global deadline exceeded before launch: context=$Context"
    }

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = "powershell.exe"
    $startInfo.Arguments = Join-G99ProcessArguments $Arguments
    $startInfo.UseShellExecute = $false
    $process = [System.Diagnostics.Process]::Start($startInfo)
    try {
        if (-not $process.WaitForExit($remainingSec * 1000)) {
            try { $process.Kill() } catch {}
            throw "G99 deadline exceeded: context=$Context seconds=$remainingSec"
        }
        if ($process.ExitCode -ne 0) {
            throw "G99 subprocess failed: context=$Context exit=$($process.ExitCode)"
        }
    } finally {
        if ($process) { $process.Dispose() }
    }
}

function Assert-G99NoOverwrite {
    param(
        [Parameter(Mandatory=$true)][string[]]$Paths,
        [Parameter(Mandatory=$true)][string]$Context
    )
    $existing = @($Paths | Where-Object {
        Test-Path -LiteralPath $_ -PathType Leaf
    })
    if ($existing.Count -eq 0) { return }
    if (-not $ForceOverwrite) {
        throw ("G99 refuses to overwrite existing artifact(s) without " +
            "-Resume or -ForceOverwrite: context=$Context paths=" +
            ($existing -join ", "))
    }
    foreach ($path in $existing) {
        Remove-Item -LiteralPath $path -Force
    }
}

function Assert-G99StaticContract {
    foreach ($path in @($harness, $runtimeMonitor, $buildRunner)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "G99 static check failed: missing $path"
        }
    }

    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $runnerPath, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        throw ("G99 runner syntax failed: " +
            (($errors | ForEach-Object { $_.Message }) -join " | "))
    }
    if ((Get-G99TextSha256 $prompt) -ne $promptSha256) {
        throw "G99 prompt provenance mismatch"
    }
    if ($repeatsPerArm -ne 3 -or $maxTokens -ne 768 -or
        $context -ne 1024 -or $warmupMaxTokens -ne 64 -or
        $stopSequence -ne $sentinel -or $quiescenceCooldownSec -ne 90 -or
        $timeoutSec -ne 7200 -or $armDeadlineSec -lt $timeoutSec -or
        $globalDeadlineSec -lt ($buildDeadlineSec + (2 * $armDeadlineSec))) {
        throw "G99 prompt/token/quiescence contract mismatch"
    }
    if ($PromotionSlots -ne 16) {
        throw "G99 protocol requires candidate promotion slots=16"
    }
    if ($modelSha256 -notmatch '^[0-9a-f]{64}$' -or
        $sidecarSha256 -notmatch '^[0-9a-f]{64}$' -or
        $promptSha256 -notmatch '^[0-9a-f]{64}$' -or
        $sidecarBytes -le 0) {
        throw "G99 provenance constants invalid"
    }

    foreach ($parameter in @(
        "GateKind", "ModelPath", "ExpectedModelSHA256",
        "Prompt",
        "StopSequence", "Warmup", "WarmupPrompt", "WarmupMaxTokens",
        "MaxTokens", "Repeats", "AllowNonIdenticalRepeatOutputs",
        "Context", "BudgetGB", "ReserveMB", "DynamicArenaGiB",
        "ArenaWrapTrustWorkerChecksum", "ArenaWrapSourceParts",
        "ArenaWrapUnlockSourceRanges", "ArenaWrapUnlockWaveGiB",
        "DisableQ8F16Cache", "EmbedRowStaging", "ReapPrefetchThreads",
        "PrefillMassWrap", "ComposePrefillMassTiering", "ExpertCacheN",
        "ComposePrefillMassOpenRouter", "ComposePrefillMassReserveSlots",
        "ExpertCacheReserveGB", "ExpertCachePolicy", "GpuResidentRoutes",
        "RouteNoDefaultSync", "RoutePackedCopy", "SplitFused", "ExpertTiering",
        "ExpertTierPolicy", "ExpertTierClockCalls",
        "ExpertTierReplacementBudget", "ExpertTierMinFrequency",
        "ExpertTierHysteresis", "QuiescenceCooldownSec", "TimeoutSec",
        "Iq1SExpertSidecar", "ExpectedIq1SExpertSidecarSHA256",
        "ExpectedIq1SExpertSidecarBytes", "Iq1SLayerFirst",
        "Iq1SLayerLast", "Iq1SMixedColdOne", "Iq1SMixedGpuPlan",
        "Iq1SRamCacheGiB", "Iq1Promotion",
        "Iq1PromotionProbationSlots")) {
        if (-not (Test-G99HarnessParameter -ParameterName $parameter)) {
            throw "G99 harness lacks required parameter: -$parameter"
        }
    }

    $harnessText = Get-Content -LiteralPath $harness -Raw
    foreach ($needle in @(
        '[ValidateSet("benchmark", "structural-safety", "quality")]',
        '[switch]$AllowNonIdenticalRepeatOutputs',
        '[string]$StopSequence = ""',
        'temperature = 0',
        'think = $false',
        'DS4_IQ1_PROMOTION_PROBATION_SLOTS',
        'DS4_CUDA_PREFILL_TIER_ROUTER',
        'DS4_CUDA_PREFILL_TIER_RESERVE_SLOTS',
        'compose_prefill_mass_open_router_requested',
        'compose_prefill_mass_reserve_slots_requested',
        'iq1_promotion_runtime_observed',
        'iq1_promotion_requests',
        'iq1_promotion_2bit_ssd_seconds',
        'quality_eligible = $qualityEligible',
        'sota_eligible = $sotaEligible')) {
        if ($harnessText -notmatch [regex]::Escape($needle)) {
            throw "G99 harness static marker missing: $needle"
        }
    }
    $baseArgs = New-G99BaseMeasureArgs "static"
    if (@($baseArgs | Where-Object { $_ -eq "-ComposePrefillMassOpenRouter" }).Count -ne 1 -or
        @($baseArgs | Where-Object { $_ -eq "-ComposePrefillMassReserveSlots" }).Count -ne 1 -or
        @($baseArgs | Where-Object { $_ -eq "-Iq1Promotion" }).Count -ne 0) {
        throw "G99 static arm shape mismatch: baseline must be open-router reserve without promotion"
    }
    foreach ($forbiddenArg in @(
        ("-Reuse" + "Verified" + "ModelReceipt"),
        ("-Reuse" + "Verified" + "Iq1SReceipt"))) {
        if (@($baseArgs | Where-Object { $_ -eq $forbiddenArg }).Count -ne 0) {
            throw "G99 static arm shape mismatch: quality uses $forbiddenArg"
        }
    }

    $selfText = Get-Content -LiteralPath $runnerPath -Raw
    foreach ($requiredText in @(
        '[string]$Result.model_hash_method -ne "full_file_sha256"',
        '[string]$Result.model_receipt_path -ne ""',
        '[string]$Result.model_receipt_sha256 -ne ""',
        '[string]$Result.iq1_s_sidecar_hash_method -ne',
        '"full_file_sha256"',
        '[string]::IsNullOrWhiteSpace(',
        '[string]$Result.iq1_s_sidecar_receipt_path)',
        '[string]$Result.iq1_s_sidecar_receipt_sha256 -notmatch',
        "'^[0-9a-fA-F]{64}$'",
        '"model_expected_sha256", "model_hash_method",',
        '"iq1_s_sidecar_sha256",',
        '"iq1_s_sidecar_hash_method",',
        '"iq1_s_sidecar_receipt_path",',
        '"iq1_s_sidecar_receipt_sha256",',
        '$stopSequence = $sentinel',
        '[switch]$ForceOverwrite',
        'Assert-G99NoOverwrite',
        'Invoke-G99PowerShellWithDeadline',
        'G99 refuses to overwrite existing artifact(s)',
        'G99 deadline exceeded',
        'external_stop_sentinel = $sentinel',
        'html_closing_tag_required = $true',
        'stop_sentinel_must_not_be_in_output = $true')) {
        if ($selfText -notmatch [regex]::Escape($requiredText)) {
            throw "G99 static matched-pair receipt marker missing: $requiredText"
        }
    }
}

function New-G99BaseMeasureArgs([string]$Tag) {
    @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $harness,
        "-Tag", $Tag,
        "-GateKind", "quality",
        "-ModelPath", $model,
        "-ExpectedModelSHA256", $modelSha256,
        "-Prompt", $prompt,
        "-StopSequence", $stopSequence,
        "-Warmup",
        "-WarmupPrompt", $prompt,
        "-WarmupMaxTokens", "$warmupMaxTokens",
        "-MaxTokens", "$maxTokens",
        "-Repeats", "$repeatsPerArm",
        "-AllowNonIdenticalRepeatOutputs",
        "-Context", "$context",
        "-BudgetGB", "2",
        "-ReserveMB", "1024",
        "-DynamicArenaGiB", "20",
        "-ArenaWrapTrustWorkerChecksum",
        "-ArenaWrapSourceParts",
        "-ArenaWrapUnlockSourceRanges",
        "-ArenaWrapUnlockWaveGiB", "4",
        "-DisableQ8F16Cache",
        "-EmbedRowStaging",
        "-ReapPrefetchThreads", "8",
        "-PrefillMassWrap",
        "-ComposePrefillMassTiering",
        "-ComposePrefillMassOpenRouter",
        "-ComposePrefillMassReserveSlots", "$PromotionSlots",
        "-ExpertCacheN", "320",
        "-ExpertCacheReserveGB", "0.125",
        "-ExpertCachePolicy", "lru",
        "-GpuResidentRoutes",
        "-RouteNoDefaultSync",
        "-SplitFused",
        "-ExpertTiering", "enforce",
        "-ExpertTierPolicy", "mass-lfru",
        "-ExpertTierClockCalls", "430",
        "-ExpertTierReplacementBudget", "32",
        "-ExpertTierMinFrequency", "3",
        "-ExpertTierHysteresis", "1.25",
        "-Iq1SExpertSidecar", $sidecar,
        "-ExpectedIq1SExpertSidecarSHA256", $sidecarSha256,
        "-ExpectedIq1SExpertSidecarBytes", "$sidecarBytes",
        "-Iq1SLayerFirst", "3",
        "-Iq1SLayerLast", "42",
        "-Iq1SMixedColdOne",
        "-Iq1SMixedGpuPlan",
        "-Iq1SRamCacheGiB", $cacheArgument,
        "-QuiescenceCooldownSec", "$quiescenceCooldownSec",
        "-TimeoutSec", "$timeoutSec"
    )
}

function Invoke-G99Arm {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("control_promotion_off", "candidate_promotion_slots16")]
        [string]$Arm,
        [Parameter(Mandatory=$true)][string]$Tag
    )

    $resultPath = Get-G99ResultPath $Tag
    $rawPath = Get-G99RawPath $Tag
    $failurePath = Get-G99FailurePath $Tag
    if ($Resume) {
        if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf) -or
            -not (Test-Path -LiteralPath $rawPath -PathType Leaf)) {
            throw "G99 resume artifact missing for arm=$Arm"
        }
    } else {
        Assert-G99NoOverwrite -Context $Arm -Paths @(
            $resultPath, $rawPath, $failurePath)
        $measureArgs = New-G99BaseMeasureArgs $Tag
        if ($Arm -eq "candidate_promotion_slots16") {
            $measureArgs += @(
                "-Iq1Promotion",
                "-Iq1PromotionProbationSlots", "$PromotionSlots"
            )
        }
        Write-Host ("[g99] start arm=" + $Arm + " tag=" + $Tag)
        Invoke-G99PowerShellWithDeadline -Arguments $measureArgs `
            -DeadlineSec $armDeadlineSec -Context $Arm
    }

    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $rawPath -PathType Leaf)) {
        throw "G99 output artifacts missing: arm=$Arm"
    }
    if (Test-Path -LiteralPath $failurePath -PathType Leaf) {
        throw "G99 failure artifact present: arm=$Arm path=$failurePath"
    }

    $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    Assert-G99ArmResult -Arm $Arm -Result $result -ResultPath $resultPath `
        -RawPath $rawPath
}

function Assert-G99ArmResult {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("control_promotion_off", "candidate_promotion_slots16")]
        [string]$Arm,
        [Parameter(Mandatory=$true)][object]$Result,
        [Parameter(Mandatory=$true)][string]$ResultPath,
        [Parameter(Mandatory=$true)][string]$RawPath
    )

    foreach ($name in @(
        "server_exit_code", "gate_kind", "quality_eligible",
        "sota_eligible", "contamination_reason", "model_sha256",
        "model_expected_sha256", "prompt_sha256",
        "requested_stop_sequence", "requested_max_tokens",
        "requested_warmup_max_tokens", "context_requested",
        "process_isolation_preflight", "system_quiescence_preflight",
        "iq1_s_sidecar_sha256", "iq1_s_sidecar_bytes",
        "iq1_s_mixed_runtime_observed", "iq1_s_mixed_calls",
        "iq1_s_mixed_hot_main", "iq1_s_mixed_cold_iq1",
        "model_hash_method", "model_receipt_path", "model_receipt_sha256",
        "iq1_s_sidecar_hash_method", "iq1_s_sidecar_receipt_path",
        "iq1_s_sidecar_receipt_sha256",
        "iq1_s_mixed_joins", "iq1_s_mixed_primary_cold_avoided",
        "iq1_s_mixed_failures", "iq1_s_mixed_gpu_plan_requested",
        "iq1_s_mixed_gpu_plan_runtime_observed",
        "iq1_s_mixed_gpu_plan_calls",
        "iq1_s_mixed_gpu_plan_failures", "iq1_promotion_requested",
        "iq1_promotion_probation_slots_requested",
        "iq1_promotion_runtime_observed", "iq1_promotion_requests",
        "iq1_promotion_2bit_ssd_seconds",
        "iq1_promotion_2bit_ssd_bytes_per_second",
        "route_packed_copy_requested",
        "compose_prefill_mass_open_router_requested",
        "compose_prefill_mass_reserve_slots_requested")) {
        Assert-G99Property -Object $Result -Name $name -Context $Arm
    }

    $mixedCalls = [UInt64]$Result.iq1_s_mixed_calls
    $hotMain = [UInt64]$Result.iq1_s_mixed_hot_main
    $coldIq1 = [UInt64]$Result.iq1_s_mixed_cold_iq1
    $plannerCalls = [UInt64]$Result.iq1_s_mixed_gpu_plan_calls

    if ([string]$Result.gate_kind -ne "quality" -or
        -not [bool]$Result.quality_eligible -or
        -not [bool]$Result.sota_eligible -or
        [string]$Result.contamination_reason -ne "" -or
        [int]$Result.server_exit_code -ne 0 -or
        [string]$Result.model_sha256 -ine $modelSha256 -or
        [string]$Result.model_expected_sha256 -ine $modelSha256 -or
        [string]$Result.model_hash_method -ne "full_file_sha256" -or
        [string]$Result.model_receipt_path -ne "" -or
        [string]$Result.model_receipt_sha256 -ne "" -or
        [string]$Result.prompt_sha256 -ine $promptSha256 -or
        [string]$Result.requested_stop_sequence -ne $stopSequence -or
        [int]$Result.requested_max_tokens -ne $maxTokens -or
        [int]$Result.requested_warmup_max_tokens -ne $warmupMaxTokens -or
        [int]$Result.context_requested -ne $context -or
        [int]$Result.budget_gb -ne 2 -or
        [int]$Result.reserve_mb -ne 1024 -or
        [double]$Result.dynamic_arena_gib_requested -ne 20.0 -or
        [string]$Result.arena_wrap_schedule_requested -ne "source-parts" -or
        -not [bool]$Result.arena_wrap_trust_worker_checksum_requested -or
        -not [bool]$Result.arena_wrap_unlock_source_ranges_requested -or
        [double]$Result.arena_wrap_unlock_wave_gib_requested -ne 4.0 -or
        -not [bool]$Result.q8_f16_cache_disabled -or
        -not [bool]$Result.embed_row_staging_requested -or
        [int]$Result.reap_prefetch_threads_requested -ne 8 -or
        [bool]$Result.prefill_mass_observe_requested -or
        -not [bool]$Result.prefill_mass_wrap_requested -or
        -not [bool]$Result.compose_prefill_mass_tiering_requested -or
        -not [bool]$Result.compose_prefill_mass_open_router_requested -or
        [int]$Result.compose_prefill_mass_reserve_slots_requested -ne
            $PromotionSlots -or
        [int]$Result.expert_cache_requested -ne 320 -or
        [double]$Result.expert_cache_reserve_gb -ne 0.125 -or
        [string]$Result.expert_cache_policy -ne "lru" -or
        -not [bool]$Result.gpu_resident_routes_requested -or
        -not [bool]$Result.route_no_default_sync_requested -or
        [bool]$Result.route_packed_copy_requested -or
        -not [bool]$Result.split_fused_requested -or
        [string]$Result.expert_tiering_requested -ne "enforce" -or
        [string]$Result.expert_tier_policy_requested -ne "mass-lfru" -or
        [int]$Result.expert_tier_clock_calls_requested -ne 430 -or
        [int]$Result.expert_tier_replacement_budget_requested -ne 32 -or
        [int]$Result.expert_tier_min_frequency_requested -ne 3 -or
        [double]$Result.expert_tier_hysteresis_requested -ne 1.25 -or
        -not [bool]$Result.non_identical_repeat_outputs_allowed -or
        -not [bool]$Result.process_isolation_preflight.ready_to_launch -or
        -not [bool]$Result.system_quiescence_preflight.ready_to_launch -or
        [bool]$Result.system_quiescence_preflight.skipped -or
        @($Result.results).Count -ne $repeatsPerArm -or
        [string]$Result.iq1_s_sidecar_sha256 -ine $sidecarSha256 -or
        [string]$Result.iq1_s_sidecar_hash_method -ne
            "full_file_sha256" -or
        [string]::IsNullOrWhiteSpace(
            [string]$Result.iq1_s_sidecar_receipt_path) -or
        [string]$Result.iq1_s_sidecar_receipt_sha256 -notmatch
            '^[0-9a-fA-F]{64}$' -or
        [UInt64]$Result.iq1_s_sidecar_bytes -ne $sidecarBytes -or
        -not [bool]$Result.iq1_s_sidecar_runtime_observed -or
        [UInt64]$Result.iq1_s_sidecar_failures -ne 0 -or
        [UInt64]$Result.iq1_s_sidecar_route_calls -eq 0 -or
        [UInt64]$Result.iq1_s_sidecar_route_calls -ne
            [UInt64]$Result.iq1_s_sidecar_selected_loads -or
        [int]$Result.effective_ds4_environment.DS4_IQ1_S_LAYER_FIRST -ne 3 -or
        [int]$Result.effective_ds4_environment.DS4_IQ1_S_LAYER_LAST -ne 42 -or
        [string]$Result.effective_ds4_environment.DS4_CUDA_PREFILL_TIER_ROUTER -ne
            "open" -or
        [string]$Result.effective_ds4_environment.DS4_CUDA_PREFILL_TIER_RESERVE_SLOTS -ne
            ([string]$PromotionSlots) -or
        [double]$Result.iq1_s_ram_cache_requested_gib -ne $Iq1CacheGiB -or
        -not [bool]$Result.iq1_s_ram_cache_runtime_observed -or
        [UInt64]$Result.iq1_s_ram_cache_failures -ne 0 -or
        -not [bool]$Result.iq1_s_mixed_cold_one -or
        -not [bool]$Result.iq1_s_mixed_runtime_observed -or
        $mixedCalls -eq 0 -or
        $coldIq1 -ne $mixedCalls -or
        $hotMain -ne ($mixedCalls * 5) -or
        [UInt64]$Result.iq1_s_mixed_joins -ne $mixedCalls -or
        [UInt64]$Result.iq1_s_mixed_primary_cold_avoided -ne $mixedCalls -or
        [UInt64]$Result.iq1_s_mixed_failures -ne 0 -or
        -not [bool]$Result.iq1_s_mixed_gpu_plan_requested -or
        -not [bool]$Result.iq1_s_mixed_gpu_plan_runtime_observed -or
        $plannerCalls -ne $mixedCalls -or
        [UInt64]$Result.iq1_s_mixed_gpu_plan_failures -ne 0) {
        throw "G99 common mixed-IQ1/G95 quality contract mismatch: arm=$Arm"
    }
    if ($Result.PSObject.Properties["expert_tiering"]) {
        $tier = $Result.expert_tiering
        if ([UInt64]$tier.forbidden_cold_ssd_to_vram -ne 0 -or
            [UInt64]$tier.cold_to_vram -ne 0 -or
            [UInt64]$tier.failures -ne 0 -or
            [UInt64]$tier.snapshot_backing_entries -ne
                [UInt64]$Result.prefill_mass_wrap_candidate_entries) {
            throw "G99 open-router tier contract mismatch: arm=$Arm"
        }
    }

    foreach ($sample in @($Result.results)) {
        $sampleText = Get-G99SampleText $sample
        if ([int]$sample.completion_tokens -le 0 -or
            [string]::IsNullOrWhiteSpace($sampleText) -or
            $sampleText -notmatch '</html>\s*$' -or
            $sampleText -match [regex]::Escape($sentinel) -or
            [string]$sample.content_sha256 -notmatch '^[0-9a-fA-F]{64}$') {
            throw "G99 raw output integrity failure: arm=$Arm repeat=$($sample.repeat)"
        }
    }

    if ($Arm -eq "control_promotion_off") {
        if ([bool]$Result.iq1_promotion_requested -or
            [int]$Result.iq1_promotion_probation_slots_requested -ne 0 -or
            [bool]$Result.iq1_promotion_runtime_observed -or
            @($Result.iq1_promotion_requests).Count -ne 0 -or
            [UInt64]$Result.iq1_promotion_failures -ne 0 -or
            [UInt64]$Result.iq1_promotion_direct_ssd_to_vram_rejected -ne 0) {
            throw "G99 control contaminated by promotion telemetry"
        }
    } else {
        $expectedRequests = [int]$Result.request_count_expected
        if (-not [bool]$Result.iq1_promotion_requested -or
            [int]$Result.iq1_promotion_probation_slots_requested -ne
                $PromotionSlots -or
            -not [bool]$Result.iq1_promotion_runtime_observed -or
            [int]$Result.iq1_promotion_line_count -ne $expectedRequests -or
            @($Result.iq1_promotion_requests).Count -ne $expectedRequests -or
            [UInt64]$Result.iq1_promotion_direct_ssd_to_vram_rejected -ne 0 -or
            [UInt64]$Result.iq1_promotion_failures -ne 0 -or
            [UInt64]$Result.iq1_promotion_cold_observed -le 0 -or
            [UInt64]$Result.iq1_promotion_cold_to_2bit_ram -le 0 -or
            [UInt64]$Result.iq1_promotion_2bit_ssd_bytes -le 0 -or
            [UInt64]$Result.iq1_promotion_snapshot_evictions -ne 0 -or
            [string]$Result.effective_ds4_environment.DS4_IQ1_PROMOTION_PROBATION_SLOTS -ne
                ([string]$PromotionSlots) -or
            [double]::IsNaN([double]$Result.iq1_promotion_2bit_ssd_seconds) -or
            [double]::IsInfinity([double]$Result.iq1_promotion_2bit_ssd_seconds) -or
            [double]$Result.iq1_promotion_2bit_ssd_seconds -le 0.0 -or
            [double]::IsNaN([double]$Result.iq1_promotion_2bit_ssd_bytes_per_second) -or
            [double]::IsInfinity([double]$Result.iq1_promotion_2bit_ssd_bytes_per_second) -or
            [double]$Result.iq1_promotion_2bit_ssd_bytes_per_second -le 0.0) {
            throw "G99 candidate promotion aggregate contract mismatch"
        }
        if ($Result.PSObject.Properties["expert_tiering"]) {
            $tier = $Result.expert_tiering
            if ([UInt64]$tier.forbidden_cold_ssd_to_vram -ne 0 -or
                [UInt64]$tier.cold_to_vram -ne 0 -or
                [UInt64]$tier.failures -ne 0 -or
                [UInt64]$tier.snapshot_backing_entries -ne
                    [UInt64]$Result.prefill_mass_wrap_candidate_entries) {
                throw "G99 candidate promotion tier fail-closed contract mismatch"
            }
        }
        foreach ($row in @($Result.iq1_promotion_requests)) {
            if ([UInt64]$row.requested_slots -ne [UInt64]$PromotionSlots -or
                [UInt64]$row.reserved_slots -ne [UInt64]$PromotionSlots -or
                [UInt64]$row.snapshot_evictions -ne 0 -or
                [UInt64]$row.cold_observed -le 0 -or
                ([UInt64]$row.cold_existing_2bit +
                    [UInt64]$row.cold_to_2bit_ram) -le 0 -or
                [UInt64]$row.direct_ssd_to_vram_rejected -ne 0 -or
                [UInt64]$row.failures -ne 0 -or
                [double]::IsNaN([double]$row.promotion_2bit_ssd_seconds) -or
                [double]::IsInfinity(
                    [double]$row.promotion_2bit_ssd_seconds) -or
                [double]$row.promotion_2bit_ssd_seconds -lt 0.0) {
                throw "G99 candidate promotion request row mismatch"
            }
        }
    }

    [pscustomobject]@{
        arm = $Arm
        tag = [string]$Result.tag
        result_path = $ResultPath
        result_sha256 = Get-G99Sha256 $ResultPath
        raw_outputs_path = $RawPath
        raw_outputs_sha256 = Get-G99Sha256 $RawPath
        result = $Result
    }
}

function Assert-G99MatchedPair([object]$Control, [object]$Candidate) {
    foreach ($field in @(
        "head", "executable_sha256", "ds4_cuda_sha256", "ds4_c_sha256",
        "ds4_server_c_sha256", "ds4_spex_predict_c_sha256",
        "ds4_gpu_h_sha256", "ds4_spex_queue_h_sha256",
        "os_thread_h_sha256", "cmake_sha256", "build_manifest_sha256",
        "build_manifest_input_fingerprint_sha256", "harness_sha256",
        "memory_preflight_harness_sha256",
        "runtime_monitor_harness_sha256", "model_sha256",
        "model_expected_sha256", "model_hash_method",
        "prompt_sha256", "system_prompt_sha256",
        "warmup_prompt_sha256", "requested_max_tokens",
        "requested_stop_sequence", "requested_warmup_max_tokens",
        "context_requested", "budget_gb", "reserve_mb",
        "dynamic_arena_gib_requested",
        "arena_wrap_trust_worker_checksum_requested",
        "arena_wrap_schedule_requested", "arena_wrap_source_requested",
        "arena_wrap_unlock_source_ranges_requested",
        "arena_wrap_unlock_wave_gib_requested", "q8_f16_cache_disabled",
        "embed_row_staging_requested", "reap_prefetch_threads_requested",
        "prefill_mass_observe_requested", "prefill_mass_wrap_requested",
        "compose_prefill_mass_tiering_requested", "expert_cache_requested",
        "expert_cache_reserve_gb", "expert_cache_policy",
        "gpu_resident_routes_requested", "route_no_default_sync_requested",
        "route_packed_copy_requested", "split_fused_requested",
        "expert_tiering_requested",
        "expert_tier_policy_requested", "expert_tier_clock_calls_requested",
        "expert_tier_replacement_budget_requested",
        "expert_tier_min_frequency_requested",
        "expert_tier_hysteresis_requested", "iq1_s_sidecar_sha256",
        "iq1_s_sidecar_hash_method", "iq1_s_sidecar_receipt_path",
        "iq1_s_sidecar_receipt_sha256", "iq1_s_sidecar_bytes",
        "iq1_s_ram_cache_requested_gib",
        "iq1_s_mixed_cold_one", "iq1_s_mixed_gpu_plan_requested")) {
        if ([string]$Control.$field -ne [string]$Candidate.$field) {
            throw "G99 A/B provenance/settings mismatch: field=$field"
        }
    }
}

function New-G99GradeRows([object[]]$Arms) {
    $rows = @()
    foreach ($armResult in $Arms) {
        foreach ($sample in @($armResult.result.results)) {
            $rows += [pscustomobject]@{
                sample_id = ($armResult.arm + "_r" + $sample.repeat)
                arm = $armResult.arm
                repeat = [int]$sample.repeat
                output_sha256 = [string]$sample.content_sha256
                completion_tokens = [int]$sample.completion_tokens
                raw_outputs_path = $armResult.raw_outputs_path
                grade_l0_l3 = $null
                grader = $null
                graded_utc = $null
                notes = $null
            }
        }
    }
    $rows
}

function Merge-G99RecordedGrades([object[]]$ExpectedRows) {
    if (-not (Test-Path -LiteralPath $gradingPath -PathType Leaf)) {
        return @($ExpectedRows)
    }
    $existing = Get-Content -LiteralPath $gradingPath -Raw | ConvertFrom-Json
    $existingRows = @($existing.samples)
    if ($existingRows.Count -ne $ExpectedRows.Count) {
        throw "G99 existing grading row count does not match measured samples"
    }
    $merged = @()
    foreach ($expected in $ExpectedRows) {
        $matches = @($existingRows | Where-Object {
            [string]$_.sample_id -eq [string]$expected.sample_id
        })
        if ($matches.Count -ne 1) {
            throw "G99 existing grading sample identity mismatch: $($expected.sample_id)"
        }
        $recorded = $matches[0]
        if ([string]$recorded.arm -ne [string]$expected.arm -or
            [int]$recorded.repeat -ne [int]$expected.repeat -or
            [string]$recorded.output_sha256 -ine
                [string]$expected.output_sha256 -or
            [int]$recorded.completion_tokens -ne
                [int]$expected.completion_tokens -or
            [string]$recorded.raw_outputs_path -ne
                [string]$expected.raw_outputs_path) {
            throw "G99 existing grading provenance mismatch: $($expected.sample_id)"
        }
        $expected.grade_l0_l3 = $recorded.grade_l0_l3
        $expected.grader = $recorded.grader
        $expected.graded_utc = $recorded.graded_utc
        $expected.notes = $recorded.notes
        $merged += $expected
    }
    return @($merged)
}

function New-G99SideBySideHtml {
    param(
        [Parameter(Mandatory=$true)][object]$Control,
        [Parameter(Mandatory=$true)][object]$Candidate
    )

    $rows = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $repeatsPerArm; $i++) {
        $controlSample = @($Control.result.results)[$i]
        $candidateSample = @($Candidate.result.results)[$i]
        $controlText = Convert-G99Html (Get-G99SampleText $controlSample)
        $candidateText = Convert-G99Html (Get-G99SampleText $candidateSample)
        [void]$rows.AppendLine("<section class=""pair"">")
        [void]$rows.AppendLine("<h2>Repeat $($i + 1)</h2>")
        [void]$rows.AppendLine("<div class=""grid"">")
        [void]$rows.AppendLine("<article><h3>Control: promotion off</h3>")
        [void]$rows.AppendLine("<p>sha256: $($controlSample.content_sha256)</p>")
        [void]$rows.AppendLine("<pre>$controlText</pre></article>")
        [void]$rows.AppendLine("<article><h3>Candidate: promotion slots $PromotionSlots</h3>")
        [void]$rows.AppendLine("<p>sha256: $($candidateSample.content_sha256)</p>")
        [void]$rows.AppendLine("<pre>$candidateText</pre></article>")
        [void]$rows.AppendLine("</div></section>")
    }

    $html = @"
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>G99 IQ1 Promotion Quality A/B Side-by-Side</title>
<style>
body { font-family: Segoe UI, Arial, sans-serif; margin: 24px; color: #111; }
h1 { font-size: 22px; margin-bottom: 4px; }
h2 { font-size: 18px; margin-top: 24px; }
h3 { font-size: 15px; margin: 0 0 8px; }
p { margin: 4px 0 10px; font-size: 12px; overflow-wrap: anywhere; }
.note { max-width: 1100px; line-height: 1.45; }
.grid { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }
article { border: 1px solid #bbb; padding: 12px; background: #fafafa; }
pre { white-space: pre-wrap; overflow-wrap: anywhere; font-size: 12px; }
</style>
</head>
<body>
<h1>G99 IQ1 Promotion Quality A/B</h1>
<p class="note">Both arms are mixed IQ1 5+1 with GPU planner and the G94/G95 configuration. The only intended arm delta is promotion off versus promotion slots $PromotionSlots. This A/B does not replace G95 main-IQ2 versus mixed-IQ1. Timing is recorded elsewhere for provenance only and must not be used as a quality grade.</p>
$($rows.ToString())
</body>
</html>
"@
    $html | Set-Content -LiteralPath $sideBySidePath -Encoding UTF8
}

New-Item -ItemType Directory -Force -Path $outdir | Out-Null
Assert-G99StaticContract

$selfSha = Get-G99Sha256 $runnerPath
$staticChecks = [ordered]@{
    schema = "g99_iq1_promotion_quality_ab_static_v1"
    script_parse_ok = $true
    static_check_only = [bool]$StaticCheckOnly
    no_build_gpu_or_ds4_launch_in_static_check = [bool]$StaticCheckOnly
    harness_present = (Test-Path -LiteralPath $harness -PathType Leaf)
    runtime_monitor_present =
        (Test-Path -LiteralPath $runtimeMonitor -PathType Leaf)
    repeats_per_arm = $repeatsPerArm
    arm_count = 2
    preserved_outputs_required = ($repeatsPerArm * 2)
    control = "mixed IQ1 5+1 GPU planner, promotion off"
    candidate = "mixed IQ1 5+1 GPU planner, promotion slots 16"
    promotion_slots = $PromotionSlots
    prompt_sha256 = $promptSha256
    max_tokens = $maxTokens
    context = $context
    stop_sequence = $stopSequence
    external_stop_sentinel = $sentinel
    html_closing_tag_required = $true
    stop_sentinel_must_not_be_in_output = $true
    force_overwrite = [bool]$ForceOverwrite
    fail_closed_overwrite_protection = $true
    harness_timeout_seconds = $timeoutSec
    build_deadline_seconds = $buildDeadlineSec
    arm_deadline_seconds = $armDeadlineSec
    global_deadline_seconds = $globalDeadlineSec
    temperature = 0
    think = $false
    quiescence_required = $true
    quiescence_cooldown_seconds = $quiescenceCooldownSec
    skip_system_quiescence = $false
    route_packed_copy = $false
    route_packed_copy_policy = "disabled for G99 IQ1 promotion path; G98 observed incompatible gate/down layout bytes"
    model_hash_method_required = "full_file_sha256"
    iq1_s_sidecar_hash_method_required = "full_file_sha256"
    model_receipt_path_and_hash_required_empty = $true
    iq1_s_sidecar_receipt_identity_required = $true
    automatic_quality_verdict = $false
    hash_or_repeat_flag_quality_verdict = "forbidden"
    timing_quality_grade = "forbidden"
    grading_required = "human L0-L3 for all six outputs"
    g95_replacement = $false
    scope_note = "G99 isolates promotion within mixed IQ1; it does not replace G95 main-IQ2 versus mixed-IQ1."
    runner_sha256 = $selfSha
}

if ($StaticCheckOnly) {
    Write-Host "[g99] static check OK; no build, GPU, DS4, or benchmark launched."
    $staticChecks | ConvertTo-Json -Depth 6
    return
}

$script:globalDeadlineUtc = [DateTime]::UtcNow.AddSeconds($globalDeadlineSec)

if (-not $Resume) {
    Assert-G99NoOverwrite -Context "summary" -Paths @(
        $summaryPath, $gradingPath, $sideBySidePath)
    Invoke-G99PowerShellWithDeadline -Arguments @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $buildRunner) `
        -DeadlineSec $buildDeadlineSec -Context "provenance-build"
}

$control = Invoke-G99Arm -Arm "control_promotion_off" -Tag $controlTag
$candidate = Invoke-G99Arm -Arm "candidate_promotion_slots16" `
    -Tag $candidateTag
Assert-G99MatchedPair -Control $control.result -Candidate $candidate.result

$expectedGradeRows = @(New-G99GradeRows @($control, $candidate))
$gradeRows = @(Merge-G99RecordedGrades $expectedGradeRows)
$compiledGrades = @($gradeRows | Where-Object {
    [string]$_.grade_l0_l3 -match '^L[0-3]$' -and
    -not [string]::IsNullOrWhiteSpace([string]$_.grader) -and
    -not [string]::IsNullOrWhiteSpace([string]$_.graded_utc)
}).Count
$qualityClaimAllowed = [bool]($compiledGrades -eq ($repeatsPerArm * 2))
New-G99SideBySideHtml -Control $control -Candidate $candidate

$grading = [ordered]@{
    schema = "g99_iq1_promotion_quality_grading_v1"
    generated_utc = [DateTime]::UtcNow.ToString("o")
    status = $(if ($qualityClaimAllowed) {
        "all-human-grades-recorded"
    } else {
        "awaiting-recorded-human-grades"
    })
    grading_required = $true
    compiled_grade_count = $compiledGrades
    required_grade_count = ($repeatsPerArm * 2)
    quality_claim_allowed = $qualityClaimAllowed
    scale = [ordered]@{
        L0 = "Unusable, incoherent, corrupt, or does not address the task."
        L1 = "Partially relevant but materially broken or incomplete."
        L2 = "Mostly correct and usable with meaningful defects."
        L3 = "Complete, coherent, and functionally satisfies the prompt."
    }
    instructions = @(
        "Inspect every preserved raw output and the side-by-side artifact.",
        "Record exactly one L0-L3 grade per row.",
        "Record grader identity, UTC timestamp, and notes for every grade.",
        "Do not infer a grade from hashes, repeat flags, timing, token counts, or arm telemetry.",
        "Do not issue an arm-level quality claim until all six grades have been recorded."
    )
    side_by_side_path = $sideBySidePath
    samples = $gradeRows
}
$grading | ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath $gradingPath -Encoding UTF8

$summary = [ordered]@{
    schema = "g99_iq1_promotion_quality_ab_v1"
    measured_utc = [DateTime]::UtcNow.ToString("o")
    status = "measurement-complete-grading-required"
    gate_kind = "quality"
    question = "Within mixed IQ1 5+1 with GPU planner, does promotion slots16 change human-rated output quality versus promotion off?"
    not_a_replacement_for = "G95 main-IQ2 versus mixed-IQ1 quality A/B"
    quality_claim_allowed = $qualityClaimAllowed
    quality_verdict = $(if ($qualityClaimAllowed) {
        "requires-human-grade-summary"
    } else {
        "pending-recorded-human-l0-l3-grading"
    })
    automatic_quality_verdict = $false
    verdict_source_required = "recorded-human-l0-l3-grades-only"
    hash_or_repeat_flag_policy = "Integrity/determinism diagnostic only; never a quality grade or verdict."
    timing_policy = "Timing is recorded for provenance and operational diagnosis only; never use it as quality grade."
    repeats_per_arm = $repeatsPerArm
    preserved_output_count = ($repeatsPerArm * 2)
    required_grade_count = ($repeatsPerArm * 2)
    compiled_grade_count = $compiledGrades
    temperature = 0
    think = $false
    prompt = $prompt
    prompt_sha256 = $promptSha256
    max_tokens = $maxTokens
    context = $context
    stop_sequence = $stopSequence
    external_stop_sentinel = $sentinel
    html_closing_tag_required = $true
    stop_sentinel_must_not_be_in_output = $true
    warmup_max_tokens = $warmupMaxTokens
    harness_timeout_seconds = $timeoutSec
    build_deadline_seconds = $buildDeadlineSec
    arm_deadline_seconds = $armDeadlineSec
    global_deadline_seconds = $globalDeadlineSec
    force_overwrite = [bool]$ForceOverwrite
    fail_closed_overwrite_protection = $true
    non_identical_repeat_outputs_allowed = $true
    system_quiescence_required = $true
    quiescence_cooldown_seconds = $quiescenceCooldownSec
    side_by_side_path = $sideBySidePath
    side_by_side_sha256 = Get-G99Sha256 $sideBySidePath
    grading_path = $gradingPath
    grading_sha256 = Get-G99Sha256 $gradingPath
    main_model = [ordered]@{
        path = $model
        expected_sha256 = $modelSha256
        observed_sha256 = [string]$control.result.model_sha256
    }
    sidecar = [ordered]@{
        path = $sidecar
        bytes = $sidecarBytes
        source = $sidecarSource
        source_repository = $sidecarSourceRepository
        expected_sha256 = $sidecarSha256
        observed_sha256 = [string]$candidate.result.iq1_s_sidecar_sha256
        receipt_path = [string]$candidate.result.iq1_s_sidecar_receipt_path
        receipt_sha256 = [string]$candidate.result.iq1_s_sidecar_receipt_sha256
        quantization_layout =
            [string]$candidate.result.iq1_s_sidecar_quantization_layout
        imatrix_provenance =
            [string]$candidate.result.iq1_s_sidecar_imatrix_provenance
    }
    common_settings = [ordered]@{
        mixed_ratio = "5:1 hot-main-to-cold-IQ1"
        iq1_s_layer_first = 3
        iq1_s_layer_last = 42
        iq1_s_ram_cache_gib = $Iq1CacheGiB
        iq1_s_mixed_gpu_plan = $true
        budget_gb = 2
        reserve_mb = 1024
        dynamic_arena_gib = 20
        arena_wrap_schedule = "source-parts"
        arena_wrap_trust_worker_checksum = $true
        arena_wrap_unlock_source_ranges = $true
        arena_wrap_unlock_wave_gib = 4
        q8_f16_cache = "disabled"
        embed_row_staging = $true
        prefill_mass_explicit_observe = $false
        prefill_mass_wrap = $true
        compose_prefill_mass_tiering = $true
        compose_prefill_mass_open_router = $true
        compose_prefill_mass_reserve_slots = $PromotionSlots
        expert_cache_n = 320
        expert_cache_reserve_gb = 0.125
        expert_cache_policy = "lru"
        expert_tiering = "enforce"
        expert_tier_policy = "mass-lfru"
        expert_tier_clock_calls = 430
        expert_tier_replacement_budget = 32
        expert_tier_min_frequency = 3
        expert_tier_hysteresis = 1.25
        gpu_resident_routes = $true
        route_no_default_sync = $true
        route_packed_copy = $false
        route_packed_copy_policy = "disabled for G99 IQ1 promotion path; G98 observed incompatible gate/down layout bytes"
        split_fused = $true
        reap_prefetch_threads = 8
    }
    arms = @(
        [ordered]@{
            arm = $control.arm
            tag = $control.tag
            role = "control: mixed IQ1 5+1 GPU planner, promotion off"
            promotion = "off"
            raw_outputs_path = $control.raw_outputs_path
            raw_outputs_sha256 = $control.raw_outputs_sha256
            result_path = $control.result_path
            result_sha256 = $control.result_sha256
            output_sha256 = @($control.result.results |
                ForEach-Object { $_.content_sha256 })
            timing_recorded = [ordered]@{
                mean_tokens_per_second =
                    [double]$control.result.mean_tokens_per_second
                server_decode_mean_tokens_per_second =
                    [double]$control.result.server_decode_mean_tokens_per_second
                server_prefill_ttft_mean_seconds =
                    [double]$control.result.server_prefill_ttft_mean_seconds
            }
        },
        [ordered]@{
            arm = $candidate.arm
            tag = $candidate.tag
            role = "candidate: mixed IQ1 5+1 GPU planner, promotion slots16"
            promotion = "slots16"
            raw_outputs_path = $candidate.raw_outputs_path
            raw_outputs_sha256 = $candidate.raw_outputs_sha256
            result_path = $candidate.result_path
            result_sha256 = $candidate.result_sha256
            output_sha256 = @($candidate.result.results |
                ForEach-Object { $_.content_sha256 })
            promotion_counters = [ordered]@{
                requested = [bool]$candidate.result.iq1_promotion_requested
                probation_slots_requested =
                    [int]$candidate.result.iq1_promotion_probation_slots_requested
                runtime_observed =
                    [bool]$candidate.result.iq1_promotion_runtime_observed
                line_count =
                    [int]$candidate.result.iq1_promotion_line_count
                cold_observed =
                    [UInt64]$candidate.result.iq1_promotion_cold_observed
                cold_to_2bit_ram =
                    [UInt64]$candidate.result.iq1_promotion_cold_to_2bit_ram
                direct_ssd_to_vram_rejected =
                    [UInt64]$candidate.result.iq1_promotion_direct_ssd_to_vram_rejected
                failures =
                    [UInt64]$candidate.result.iq1_promotion_failures
                promotion_2bit_ssd_seconds =
                    [double]$candidate.result.iq1_promotion_2bit_ssd_seconds
                promotion_2bit_ssd_bytes_per_second =
                    [double]$candidate.result.iq1_promotion_2bit_ssd_bytes_per_second
            }
            timing_recorded = [ordered]@{
                mean_tokens_per_second =
                    [double]$candidate.result.mean_tokens_per_second
                server_decode_mean_tokens_per_second =
                    [double]$candidate.result.server_decode_mean_tokens_per_second
                server_prefill_ttft_mean_seconds =
                    [double]$candidate.result.server_prefill_ttft_mean_seconds
            }
        }
    )
    runner_sha256 = Get-G99Sha256 $runnerPath
}
$summary | ConvertTo-Json -Depth 10 |
    Set-Content -LiteralPath $summaryPath -Encoding UTF8
Write-Host "G99 measurement PASS; human L0-L3 grading is still required"
Write-Host ("G99 summary: " + $summaryPath)
Write-Host ("G99 side-by-side: " + $sideBySidePath)
Write-Host ("G99 grading template: " + $gradingPath)
