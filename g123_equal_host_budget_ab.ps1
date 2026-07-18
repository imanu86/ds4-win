# G123 equal-host-budget n=3 A/B orchestrator.
# Six independent G7 processes: 3 control + 3 candidate.
param(
    [ValidatePattern('^[A-Za-z0-9_-]+$')]
    [string]$Tag = "g123_equal_host_budget_ab",
    [ValidatePattern('^$|^[A-Za-z0-9_-]+$')]
    [string]$ResumeBatchTag = "",
    [ValidatePattern('^$|^[A-Za-z0-9_-]+$')]
    [string]$MissingAttemptSuffix = "",
    [ValidateRange(0, 600)][int]$InterChildCooldownSec = 30,
    [ValidateRange(600, 7200)][int]$TimeoutSec = 2400,
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$harness = Join-Path $root "g7_measure.ps1"
$bootstrap = Join-Path $root "g7_harness_bootstrap.ps1"
$runs = Join-Path $root "g7_runs"
$model = "C:\ds4-models\ds4-2bit.gguf"
$modelSHA = "efc7ed607ff27076e3e501fc3fefefa33c0ed8cf1eff483a2b7fdc0c2e616668"
$sidecar = "C:\ds4-models\ds4-nested-residual-layers3-16-29-42.ds4nr"
$sidecarReceipt = "C:\ds4-models\ds4-nested-residual-layers3-16-29-42.receipt.json"
$sidecarBytes = [UInt64]3221226880
$sidecarSHA = "07199bc5503aa6e2dea10f702c1ca9e8f05a5bf466a56cbed031f6a5fca4bdf9"
$payloadSHA = "02c8cb248a8184e365e2e486653484165db39402fd28320ba621fb4fdb3f7bd8"
$expectedContentSHA = "fd6c4522975a71e252b90199d49cfe3236310e2a7285dc0fc4d0e9d0e4885510"
$prompt = "Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document."
$promptSHA = "38f6ec5ee5403f59dd2418eb5d9a5a94a0f0da19df015060383bb1ae46003bb6"
$controlArenaGiB = 30.0
$candidateArenaGiB = 25.828125
$candidateNestedBaseGiB = 3.75
$candidateExactCacheGiB = 0.421875
$equalHostBudgetGiB = 30.0

function Get-G123Sha256Text {
    param([Parameter(Mandatory=$true)][string]$Text)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
        return [BitConverter]::ToString(
            $sha.ComputeHash($bytes)).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function New-G123Suffix {
    $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssfffZ")
    $nonce = [Guid]::NewGuid().ToString("N").Substring(0, 10)
    return ($stamp + "_" + $nonce)
}

function Get-G123Median {
    param([double[]]$Values)

    if ($null -eq $Values -or $Values.Count -eq 0) { return $null }
    $sorted = @($Values | Sort-Object)
    $middle = [int][math]::Floor($sorted.Count / 2)
    if (($sorted.Count % 2) -eq 1) { return [double]$sorted[$middle] }
    return ([double]$sorted[$middle - 1] + [double]$sorted[$middle]) / 2.0
}

function Get-G123Mean {
    param([double[]]$Values)

    if ($null -eq $Values -or $Values.Count -eq 0) { return $null }
    $sum = 0.0
    foreach ($value in $Values) { $sum += [double]$value }
    return $sum / [double]$Values.Count
}

function New-G123CommonHarnessArguments {
    param(
        [Parameter(Mandatory=$true)][string]$ChildTag,
        [Parameter(Mandatory=$true)][double]$DynamicArenaGiB
    )

    return @(
        "-GateKind", "benchmark",
        "-ModelPath", $model,
        "-ExpectedModelSHA256", $modelSHA,
        "-ReuseVerifiedModelReceipt",
        "-AllowBenchmarkVerifiedReceiptReuse",
        "-Prompt", $prompt,
        "-ExpectedContentSHA256", $expectedContentSHA,
        "-MaxTokens", "64",
        "-Repeats", "1",
        "-Context", "256",
        "-BudgetGB", "2",
        "-ReserveMB", "1024",
        "-DynamicArenaGiB", ([string]$DynamicArenaGiB),
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
        "-ForceOpenRouter",
        "-ComposePrefillMassReserveSlots", "32",
        "-ExpertCacheN", "320",
        "-ExpertCacheReserveGB", "0.125",
        "-ExpertCachePolicy", "lru",
        "-GpuResidentRoutes",
        "-RouteNoDefaultSync",
        "-ExpertTiering", "enforce",
        "-ExpertTierPolicy", "mass-lfru",
        "-ExpertTierClockCalls", "430",
        "-ExpertTierReplacementBudget", "32",
        "-ExpertTierMinFrequency", "3",
        "-ExpertTierHysteresis", "1.25",
        "-SplitFused",
        "-RuntimeMinimumAvailableGiB", "1",
        "-RuntimeMaximumDiskQueueLength", "8",
        "-RuntimeContaminationSamples", "3",
        "-QuiescenceCooldownSec", "10",
        "-TimeoutSec", ([string]$TimeoutSec),
        "-Tag", $ChildTag
    )
}

function New-G123ChildPlan {
    param(
        [ValidateSet("control", "candidate")][string]$Arm,
        [int]$RepeatIndex,
        [string]$BatchTag
    )

    $baseChildTag = $BatchTag + "_" + $Arm + "_r" + $RepeatIndex
    $baseResultPath = Join-Path $runs ("g7_" + $baseChildTag + "_result.json")
    $childTag = $baseChildTag
    if ($ResumeBatchTag -and $MissingAttemptSuffix -and
        -not (Test-Path -LiteralPath $baseResultPath -PathType Leaf)) {
        $childTag = $baseChildTag + "_" + $MissingAttemptSuffix
    }
    if ($Arm -eq "control") {
        $args = @(New-G123CommonHarnessArguments `
            -ChildTag $childTag `
            -DynamicArenaGiB $controlArenaGiB)
        $arena = $controlArenaGiB
    } else {
        $args = @(New-G123CommonHarnessArguments `
            -ChildTag $childTag `
            -DynamicArenaGiB $candidateArenaGiB)
        $args += @(
            "-NestedResidualSidecar", $sidecar,
            "-ExpectedNestedResidualSidecarSHA256", $sidecarSHA,
            "-ExpectedNestedResidualSourceSHA256", $modelSHA,
            "-ExpectedNestedResidualPayloadSHA256", $payloadSHA,
            "-NestedResidualCacheExperts", "64",
            "-NestedResidualGpuCache",
            "-AllowNestedResidualBenchmarkSuite",
            "-OuterNestedResidualBenchmarkProcessCount", "3",
            "-NestedResidualVerifyReconstruction"
        )
        $arena = $candidateArenaGiB
    }

    return [pscustomobject]@{
        arm = $Arm
        repeat_index = $RepeatIndex
        tag = $childTag
        dynamic_arena_gib = $arena
        harness_arguments = @($args)
        result_path = (Join-Path $runs ("g7_" + $childTag + "_result.json"))
    }
}

function Invoke-G123Child {
    param([Parameter(Mandatory=$true)][object]$Plan)

    $bootstrapArgs = @{
        HarnessPath = $harness
        RepoRoot = $root
        HarnessArguments = @($Plan.harness_arguments)
    }
    if ($WhatIf) {
        $bootstrapArgs.WhatIf = $true
        Write-Host ("[g123] WHATIF child=" + $Plan.tag +
            " arm=" + $Plan.arm +
            " arena_gib=" + $Plan.dynamic_arena_gib)
        & $bootstrap @bootstrapArgs
        return
    }

    if (Test-Path -LiteralPath $Plan.result_path -PathType Leaf) {
        if ($ResumeBatchTag) {
            Write-Host ("[g123] reuse completed child=" + $Plan.tag)
            return
        }
        throw "G123 child result already exists for immutable tag: $($Plan.result_path)"
    }
    if ($InterChildCooldownSec -gt 0) {
        Write-Host ("[g123] cooldown seconds=" + $InterChildCooldownSec +
            " before child=" + $Plan.tag)
        Start-Sleep -Seconds $InterChildCooldownSec
    }
    Write-Host ("[g123] launch child=" + $Plan.tag + " arm=" + $Plan.arm)
    & $bootstrap @bootstrapArgs
    if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
        throw ("G123 child failed with exit code " + $LASTEXITCODE +
            ": " + $Plan.tag)
    }
    if (-not (Test-Path -LiteralPath $Plan.result_path -PathType Leaf)) {
        throw "G123 child result missing: $($Plan.result_path)"
    }
}

function Read-G123ChildResult {
    param([Parameter(Mandatory=$true)][object]$Plan)

    if (-not (Test-Path -LiteralPath $Plan.result_path -PathType Leaf)) {
        throw "G123 missing child result: $($Plan.result_path)"
    }
    $json = Get-Content -LiteralPath $Plan.result_path -Raw | ConvertFrom-Json
    $samples = @($json.results)
    if ([int]$json.repeats -ne 1 -or $samples.Count -ne 1) {
        throw "G123 child must be exactly one independent process/request: $($Plan.tag)"
    }
    $sample = $samples[0]
    if ([string]$sample.content_sha256 -ne $expectedContentSHA) {
        throw "G123 exact content SHA mismatch for $($Plan.tag)"
    }
    if ([string]$json.expected_content_sha256 -ne $expectedContentSHA) {
        throw "G123 expected content provenance missing for $($Plan.tag)"
    }
    if ([string]$json.gate_kind -ne "benchmark") {
        throw "G123 child must run with GateKind benchmark: $($Plan.tag)"
    }
    if ([string]$json.prompt_sha256 -ne $promptSHA) {
        throw "G123 prompt SHA mismatch for $($Plan.tag)"
    }
    if ([int]$json.requested_max_tokens -ne 64 -or
        [int]$json.context_requested -ne 256 -or
        [double]$json.dynamic_arena_gib_requested -ne
            [double]$Plan.dynamic_arena_gib -or
        [int]$json.expert_cache_requested -ne 320 -or
        -not $json.compose_prefill_mass_open_router_requested -or
        [int]$json.expert_tiering.compose_router_open -ne 1 -or
        -not $json.gpu_resident_routes_requested -or
        -not $json.split_fused_requested -or
        [string]$json.expert_tiering_requested -ne "enforce" -or
        [string]$json.expert_tier_policy_requested -ne "mass-lfru") {
        throw "G123 G73 transport contract mismatch for $($Plan.tag)"
    }

    $preflight = $json.system_quiescence_preflight
    $preflightFailures = @()
    if ($null -ne $preflight -and $null -ne $preflight.failures) {
        $preflightFailures = @($preflight.failures)
    }
    $runtimePeak = 0
    if ($null -ne $json.runtime_telemetry -and
        $null -ne $json.runtime_telemetry.contamination_consecutive_peak) {
        $runtimePeak = [int]$json.runtime_telemetry.contamination_consecutive_peak
    }
    $uncontaminated =
        ($null -ne $preflight) -and
        ([bool]$preflight.ready_to_launch) -and
        (-not [bool]$preflight.skipped) -and
        ($preflightFailures.Count -eq 0) -and
        ($runtimePeak -eq 0)

    if ($Plan.arm -eq "candidate") {
        if (-not $json.nested_residual_runtime_observed -or
            -not $json.nested_residual_vram_runtime_observed -or
            -not $json.allow_nested_residual_benchmark_suite_requested -or
            [int]$json.outer_nested_residual_benchmark_process_count_requested -ne 3 -or
            -not $json.nested_residual_benchmark_member -or
            [UInt64]$json.nested_residual_vram_route_calls -eq 0 -or
            [UInt64]$json.nested_residual_vram_hits -eq 0 -or
            [UInt64]$json.nested_residual_vram_misses -eq 0 -or
            [UInt64]$json.nested_residual_vram_failures -ne 0 -or
            [UInt64]$json.nested_residual_vram_host_fills -ne
                [UInt64]$json.nested_residual_vram_misses -or
            [UInt64]$json.nested_residual_vram_host_bytes -ne
                ([UInt64]$json.nested_residual_vram_misses * [UInt64]7077888) -or
            [UInt64]$json.nested_residual_vram_h2d_bytes -ne
                ([UInt64]$json.nested_residual_vram_misses * [UInt64]7077888)) {
            throw "G123 candidate nested GPU-cache contract mismatch for $($Plan.tag)"
        }
    } else {
        if ($json.nested_residual_runtime_observed -or
            $json.nested_residual_vram_runtime_observed) {
            throw "G123 control unexpectedly observed nested residual runtime"
        }
    }

    return [pscustomobject]@{
        arm = $Plan.arm
        repeat_index = $Plan.repeat_index
        tag = $Plan.tag
        result_path = $Plan.result_path
        exact = $true
        uncontaminated = $uncontaminated
        content_sha256 = [string]$sample.content_sha256
        seconds = [double]$sample.seconds
        tokens_per_second = [double]$sample.tokens_per_second
        completion_tokens = [int]$sample.completion_tokens
        server_decode_mean_tokens_per_second =
            [double]$json.server_decode_mean_tokens_per_second
        server_prefill_ttft_mean_seconds =
            [double]$json.server_prefill_ttft_mean_seconds
        load_seconds = [double]$json.load_seconds
        dynamic_arena_gib = [double]$json.dynamic_arena_gib_requested
        aggregate_disk_read_gib =
            [math]::Round(
                [double]$json.runtime_telemetry.aggregate_disk_read_bytes_estimated /
                    1GB, 6)
        contamination_peak = $runtimePeak
        preflight_failures = $preflightFailures.Count
        nested_route_calls =
            $(if ($Plan.arm -eq "candidate") {
                [UInt64]$json.nested_residual_vram_route_calls
            } else { [UInt64]0 })
        nested_hits =
            $(if ($Plan.arm -eq "candidate") {
                [UInt64]$json.nested_residual_vram_hits
            } else { [UInt64]0 })
        nested_misses =
            $(if ($Plan.arm -eq "candidate") {
                [UInt64]$json.nested_residual_vram_misses
            } else { [UInt64]0 })
        nested_host_fills =
            $(if ($Plan.arm -eq "candidate") {
                [UInt64]$json.nested_residual_vram_host_fills
            } else { [UInt64]0 })
        nested_h2d_bytes =
            $(if ($Plan.arm -eq "candidate") {
                [UInt64]$json.nested_residual_vram_h2d_bytes
            } else { [UInt64]0 })
        nested_failures =
            $(if ($Plan.arm -eq "candidate") {
                [UInt64]$json.nested_residual_vram_failures
            } else { [UInt64]0 })
    }
}

function New-G123ArmSummary {
    param([Parameter(Mandatory=$true)][object[]]$Rows)

    $e2e = [double[]]@($Rows | ForEach-Object { [double]$_.tokens_per_second })
    $decode = [double[]]@(
        $Rows | ForEach-Object { [double]$_.server_decode_mean_tokens_per_second })
    $ttft = [double[]]@(
        $Rows | ForEach-Object { [double]$_.server_prefill_ttft_mean_seconds })
    $seconds = [double[]]@($Rows | ForEach-Object { [double]$_.seconds })
    return [pscustomobject]@{
        count = $Rows.Count
        e2e_tps_mean = Get-G123Mean $e2e
        e2e_tps_median = Get-G123Median $e2e
        server_decode_tps_mean = Get-G123Mean $decode
        server_decode_tps_median = Get-G123Median $decode
        ttft_seconds_mean = Get-G123Mean $ttft
        ttft_seconds_median = Get-G123Median $ttft
        seconds_mean = Get-G123Mean $seconds
        seconds_median = Get-G123Median $seconds
    }
}

foreach ($path in @($harness, $bootstrap)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "G123 required script missing: $path"
    }
}
if (-not $WhatIf) {
    foreach ($path in @($model, "$model.receipt.json", $sidecar, $sidecarReceipt)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "G123 required file missing: $path"
        }
    }
    if ([UInt64](Get-Item -LiteralPath $sidecar).Length -ne $sidecarBytes) {
        throw "G123 sidecar size mismatch"
    }
}
if ((Get-G123Sha256Text -Text $prompt) -ne $promptSHA) {
    throw "G123 prompt SHA-256 mismatch"
}

$modelLock = $null
$sidecarLock = $null
try {
if (-not $WhatIf) {
    $modelLock = [IO.File]::Open(
        $model, [IO.FileMode]::Open,
        [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $sidecarLock = [IO.File]::Open(
        $sidecar, [IO.FileMode]::Open,
        [IO.FileAccess]::Read, [IO.FileShare]::Read)
}

$batchTag = if ($ResumeBatchTag) {
    $ResumeBatchTag
} else {
    $Tag + "_" + (New-G123Suffix)
}
$plans = @()
for ($i = 1; $i -le 3; $i += 1) {
    $plans += New-G123ChildPlan -Arm "control" -RepeatIndex $i -BatchTag $batchTag
    $plans += New-G123ChildPlan -Arm "candidate" -RepeatIndex $i -BatchTag $batchTag
}

if ($WhatIf) {
    [pscustomobject]@{
        schema = "g123_equal_host_budget_ab_plan_v1"
        batch_tag = $batchTag
        resume_batch_tag = $ResumeBatchTag
        missing_attempt_suffix = $MissingAttemptSuffix
        inter_child_cooldown_seconds = $InterChildCooldownSec
        expected_content_sha256 = $expectedContentSHA
        prompt_sha256 = $promptSHA
        child_count = $plans.Count
        children = @($plans | ForEach-Object {
            [pscustomobject]@{
                arm = $_.arm
                repeat_index = $_.repeat_index
                tag = $_.tag
                dynamic_arena_gib = $_.dynamic_arena_gib
                result_path = $_.result_path
                harness_arguments = @($_.harness_arguments)
            }
        })
    } | ConvertTo-Json -Depth 8
    foreach ($plan in $plans) {
        Invoke-G123Child -Plan $plan
    }
    return
}

foreach ($plan in $plans) {
    Invoke-G123Child -Plan $plan
}

$rows = @()
foreach ($plan in $plans) {
    $rows += Read-G123ChildResult -Plan $plan
}

$controlRows = @($rows | Where-Object { $_.arm -eq "control" })
$candidateRows = @($rows | Where-Object { $_.arm -eq "candidate" })
if ($controlRows.Count -ne 3 -or $candidateRows.Count -ne 3) {
    throw "G123 did not collect exactly 3 control and 3 candidate rows"
}
$allValid = (@($rows | Where-Object {
            -not $_.exact -or -not $_.uncontaminated
        }).Count -eq 0)
if (-not $allValid) {
    throw "G123 n>=3 verdict invalid: one or more children failed exactness or contamination gates"
}

$controlSummary = New-G123ArmSummary -Rows $controlRows
$candidateSummary = New-G123ArmSummary -Rows $candidateRows
$deltaE2E =
    ([double]$candidateSummary.e2e_tps_mean /
     [double]$controlSummary.e2e_tps_mean) - 1.0
$deltaDecode =
    ([double]$candidateSummary.server_decode_tps_mean /
     [double]$controlSummary.server_decode_tps_mean) - 1.0

$resultPath = Join-Path $runs ("g7_" + $batchTag + "_result.json")
$result = [ordered]@{
    schema = "g123_equal_host_budget_ab_result_v1"
    batch_tag = $batchTag
    resumed = [bool]$ResumeBatchTag
    missing_attempt_suffix = $MissingAttemptSuffix
    inter_child_cooldown_seconds = $InterChildCooldownSec
    status = "pass"
    claim_scope = "n3_equal_host_budget_ab"
    n3_valid = $true
    expected_content_sha256 = $expectedContentSHA
    prompt = $prompt
    prompt_sha256 = $promptSHA
    model = $model
    model_sha256 = $modelSHA
    sidecar = $sidecar
    sidecar_sha256 = $sidecarSHA
    sidecar_payload_sha256 = $payloadSHA
    host_budget_gib = [ordered]@{
        control = [ordered]@{
            primary_arena = $controlArenaGiB
            nested_base = 0.0
            exact_cache = 0.0
            total = $equalHostBudgetGiB
        }
        candidate = [ordered]@{
            primary_arena = $candidateArenaGiB
            nested_base = $candidateNestedBaseGiB
            exact_cache = $candidateExactCacheGiB
            total = $equalHostBudgetGiB
        }
    }
    control = $controlSummary
    candidate = $candidateSummary
    relative_delta = [ordered]@{
        e2e_tps_mean = $deltaE2E
        server_decode_tps_mean = $deltaDecode
    }
    rows = @($rows)
}
$result | ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath $resultPath -Encoding UTF8
Write-Host ("[g123] PASS result=" + $resultPath +
    " e2e_delta=" + [math]::Round($deltaE2E * 100.0, 3) + "%" +
    " decode_delta=" + [math]::Round($deltaDecode * 100.0, 3) + "%")
} finally {
    if ($null -ne $sidecarLock) { $sidecarLock.Dispose() }
    if ($null -ne $modelLock) { $modelLock.Dispose() }
}
