# G102 IQ1_S combined-gate long quality protocol (PowerShell 5.1, ASCII).
param(
    [switch]$StaticCheckOnly,
    [string]$PythonPath = "python",
    [ValidateRange(1, 20)][int]$QuiescenceRetryLimit = 10,
    [ValidateRange(0, 300)][int]$QuiescenceRetryCooldownSec = 30,
    [ValidateRange(600, 86400)][int]$PerProcessTimeoutSec = 14400
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$harness = Join-Path $root "g7_measure.ps1"
$suiteReceiptHelper = Join-Path $root "g7_suite_receipt.ps1"
$runtimeMonitor = Join-Path $root "g7_runtime_monitor.ps1"
$grader = "C:\Users\imanu\source\repos\reap-loop\scripts\functional_grade.py"
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

$stopSequence = "</html>"
$processCount = 3
$repeatsPerProcess = 1
$context = 8192
$maxTokens = 4000
$warmupMaxTokens = 64
$promotionSlots = 16
$futureQualityReceiptFlag = "AllowQualityVerifiedSuiteReceipt"
$futureOuterCountParameter = "OuterQualityProcessCount"

$summaryPath = Join-Path $outdir "g102_iq1_combined_quality_result.json"
$protocolReceiptPath = Join-Path $outdir `
    "g102_iq1_combined_quality_protocol.receipt.json"
$suiteReceiptPath = Join-Path $outdir `
    "g102_model_iq1_suite.receipt.json"

$script:g102SuiteReceiptPath = $suiteReceiptPath
$script:g102SuiteReceiptSHA256 = ""
$script:harnessText = ""

function Get-G102SHA256 {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "G102 provenance file missing: $Path"
    }
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-G102StringSHA256 {
    param([Parameter(Mandatory=$true)][string]$Value)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
        ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace "-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Get-G102Property {
    param([object]$Object, [string]$Name)
    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) {
        return $null
    }
    $Object.PSObject.Properties[$Name].Value
}

function Assert-G102Property {
    param(
        [Parameter(Mandatory=$true)][object]$Object,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Context
    )
    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) {
        throw "G102 required field missing: context=$Context field=$Name"
    }
}

function Test-G102HarnessParameter {
    param([Parameter(Mandatory=$true)][string]$ParameterName)
    return ($script:harnessText -match (
        "\$" + [regex]::Escape($ParameterName) + "(\s|=|,|\))"))
}

function Get-G102MissingPrerequisites {
    $missing = @()
    foreach ($required in @(
        "MaxTokens", "WarmupMaxTokens", "Repeats",
        "AllowNonIdenticalRepeatOutputs", "TimeoutSec", "Prompt",
        "StopSequence", "Context", "BudgetGB", "ReserveMB",
        "DynamicArenaGiB", "ArenaWrapTrustWorkerChecksum",
        "ArenaWrapSourceParts", "ArenaWrapUnlockSourceRanges",
        "ArenaWrapUnlockWaveGiB", "DisableQ8F16Cache",
        "EmbedRowStaging", "PrefillMassWrap",
        "ComposePrefillMassTiering", "ComposePrefillMassOpenRouter",
        "ComposePrefillMassReserveSlots", "ExpertCacheN",
        "ExpertCacheReserveGB", "ExpertCachePolicy", "ExpertTiering",
        "ExpertTierPolicy", "ExpertTierClockCalls",
        "ExpertTierReplacementBudget", "ExpertTierMinFrequency",
        "ExpertTierHysteresis", "GpuResidentRoutes",
        "RouteNoDefaultSync", "SplitFused", "ReapPrefetchThreads",
        "ModelPath", "ExpectedModelSHA256", "Iq1SExpertSidecar",
        "ExpectedIq1SExpertSidecarSHA256",
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
        if (-not (Test-G102HarnessParameter $required)) {
            $missing += [pscustomobject]@{
                id = "g7_existing_parameter_missing"
                parameter = "-$required"
                reason = "G102 requires this existing G7 parameter."
            }
        }
    }

    if (-not (Test-G102HarnessParameter $futureQualityReceiptFlag) -or
        $script:harnessText -notmatch
            [regex]::Escape("allow_quality_verified_suite_receipt_requested")) {
        $missing += [pscustomobject]@{
            id = "g7_quality_verified_suite_receipt_contract"
            parameter = "-$futureQualityReceiptFlag"
            reason = (
                "Must explicitly authorize ReuseVerifiedSuiteReceipt for " +
                "GateKind=quality and require parent-held deny-write/delete " +
                "lock proof; current G7 rejects this combination.")
        }
    }
    if (-not (Test-G102HarnessParameter $futureOuterCountParameter) -or
        $script:harnessText -notmatch
            [regex]::Escape("outer_quality_process_count_requested") -or
        $script:harnessText -notmatch
            [regex]::Escape("outer_quality_member_contract_valid")) {
        $missing += [pscustomobject]@{
            id = "g7_outer_independent_quality_n_contract"
            parameter = "-$futureOuterCountParameter 3"
            reason = (
                "Must declare an outer n=3 independent-process quality suite " +
                "so each Repeats=1 child is marked pending-aggregate without " +
                "pretending to be independently quality-eligible.")
        }
    }
    return @($missing)
}

function New-G102StaticReceipt {
    param(
        [Parameter(Mandatory=$true)]
        [AllowEmptyCollection()]
        [object[]]$MissingPrerequisites
    )
    [pscustomobject]@{
        schema = "g102_iq1_combined_quality_static_v1"
        runnable = [bool]($MissingPrerequisites.Count -eq 0)
        static_check_only = [bool]$StaticCheckOnly
        no_build_gpu_or_ds4_launch_in_static_check = [bool]$StaticCheckOnly
        missing_prerequisites = @($MissingPrerequisites)
        protocol = [pscustomobject]@{
            independent_processes = $processCount
            repeats_per_process = $repeatsPerProcess
            prompt = $prompt
            prompt_sha256 = $expectedPromptSHA256
            context = $context
            max_tokens = $maxTokens
            warmup = $true
            warmup_max_tokens = $warmupMaxTokens
            temperature = 0
            think = $false
            stop_sequence = $stopSequence
            stop_implementation = "server_stop_sequence"
            stop_delimiter_preserved = $false
            grading_restores_confirmed_stop_delimiter = $true
            stop_note = (
                "Current server stop handling trims the matched </html> " +
                "delimiter from returned content. The grader restores it only " +
                "when server telemetry reports finish_reason=stop.")
            output_hash_equality_required = $false
            grader = "functional_grade.py frontpage <content.html> --json"
            aggregate = "median L0-L3 across n=3 independent processes"
        }
        combined_gate = [pscustomobject]@{
            probation_slots = 16
            min_touches = 2
            min_weight = 0.02
            min_mass = 0.0
            request_budget = 16
            window_calls = 40
            window_budget = 1
        }
        future_g7_contract = [pscustomobject]@{
            quality_verified_suite_receipt_switch =
                "-$futureQualityReceiptFlag"
            outer_quality_process_count_parameter =
                "-$futureOuterCountParameter 3"
            expected_result_field =
                @(
                    "allow_quality_verified_suite_receipt_requested=true",
                    "outer_quality_process_count_requested=3",
                    "outer_quality_suite_member=true",
                    "outer_quality_member_contract_valid=true",
                    "quality_eligible=false",
                    "sota_eligible=false",
                    "contamination_reason=outer-quality-suite-member-pending-aggregate"
                )
        }
    }
}

function Open-G102ReadDenyWriteDeleteLock {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Kind
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "G102 $Kind missing before suite lock: $Path"
    }
    [IO.File]::Open($Path, [IO.FileMode]::Open,
        [IO.FileAccess]::Read, [IO.FileShare]::Read)
}

function New-G102LockedSuiteReceipt {
    if (Test-Path -LiteralPath $suiteReceiptPath) {
        throw "G102 refuses to overwrite suite receipt: $suiteReceiptPath"
    }
    $created = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
        -File $suiteReceiptHelper `
        -ModelPath $model `
        -Iq1SExpertSidecar $iq1Sidecar `
        -OutPath $suiteReceiptPath `
        -ExpectedModelSHA256 $expectedModelSHA256 `
        -ExpectedIq1SExpertSidecarSHA256 $expectedIq1SidecarSHA256 `
        -ExpectedIq1SExpertSidecarBytes $expectedIq1SidecarBytes `
        -Force | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or
        [string]$created.suite_receipt_sha256 -notmatch '^[0-9a-fA-F]{64}$') {
        throw "G102 suite receipt helper failed"
    }
    $script:g102SuiteReceiptPath =
        [IO.Path]::GetFullPath([string]$created.suite_receipt_path)
    $script:g102SuiteReceiptSHA256 =
        ([string]$created.suite_receipt_sha256).ToLowerInvariant()
    [pscustomobject]@{
        path = $script:g102SuiteReceiptPath
        sha256 = $script:g102SuiteReceiptSHA256
        schema = [string]$created.schema
        status = [string]$created.status
        purpose = [string]$created.purpose
    }
}

function New-G102MeasureArgs {
    param([Parameter(Mandatory=$true)][string]$Tag)
    @(
        "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", $harness,
        "-Tag", $Tag,
        "-GateKind", "quality",
        "-$futureQualityReceiptFlag",
        "-$futureOuterCountParameter", ([string]$processCount),
        "-MaxTokens", ([string]$maxTokens),
        "-Warmup", "-WarmupPrompt", $prompt,
        "-WarmupMaxTokens", ([string]$warmupMaxTokens),
        "-Repeats", "1", "-AllowNonIdenticalRepeatOutputs",
        "-TimeoutSec", ([string]$PerProcessTimeoutSec),
        "-Prompt", $prompt,
        "-StopSequence", $stopSequence,
        "-Context", ([string]$context),
        "-BudgetGB", "2", "-ReserveMB", "1024",
        "-DynamicArenaGiB", "12",
        "-ArenaWrapTrustWorkerChecksum", "-ArenaWrapSourceParts",
        "-ArenaWrapUnlockSourceRanges",
        "-ArenaWrapUnlockWaveGiB", "4",
        "-DisableQ8F16Cache", "-EmbedRowStaging",
        "-PrefillMassWrap", "-ComposePrefillMassTiering",
        "-ComposePrefillMassOpenRouter",
        "-ComposePrefillMassReserveSlots", "16",
        "-ExpertCacheN", "320", "-ExpertCacheReserveGB", "0.125",
        "-ExpertCachePolicy", "lru",
        "-ExpertTiering", "enforce",
        "-ExpertTierPolicy", "mass-lfru",
        "-ExpertTierClockCalls", "430",
        "-ExpertTierReplacementBudget", "32",
        "-ExpertTierMinFrequency", "3",
        "-ExpertTierHysteresis", "1.25",
        "-GpuResidentRoutes", "-RouteNoDefaultSync", "-SplitFused",
        "-ReapPrefetchThreads", "8",
        "-ModelPath", $model,
        "-ExpectedModelSHA256", $expectedModelSHA256,
        "-Iq1SExpertSidecar", $iq1Sidecar,
        "-ExpectedIq1SExpertSidecarSHA256", $expectedIq1SidecarSHA256,
        "-ExpectedIq1SExpertSidecarBytes", ([string]$expectedIq1SidecarBytes),
        "-ModelIq1SuiteReceiptPath", $script:g102SuiteReceiptPath,
        "-ExpectedModelIq1SuiteReceiptSHA256",
            $script:g102SuiteReceiptSHA256,
        "-ReuseVerifiedSuiteReceipt",
        "-Iq1SLayerFirst", "3", "-Iq1SLayerLast", "42",
        "-Iq1SMixedColdOne", "-Iq1SMixedGpuPlan",
        "-Iq1Promotion", "-Iq1PromotionProbationSlots", "16",
        "-Iq1PromotionMinTouches", "2",
        "-Iq1PromotionMinWeight", "0.02",
        "-Iq1PromotionMinMass", "0",
        "-Iq1PromotionRequestBudget", "16",
        "-Iq1PromotionWindowCalls", "40",
        "-Iq1PromotionWindowBudget", "1",
        "-Iq1SRamCacheGiB", "1",
        "-QuiescenceCooldownSec", "90",
        "-RuntimeMinimumAvailableGiB", "4",
        "-RuntimeMaximumDiskQueueLength", "8",
        "-RuntimeContaminationSamples", "3"
    )
}

function Join-G102ProcessArguments {
    param([Parameter(Mandatory=$true)][string[]]$Arguments)
    $quoted = foreach ($arg in $Arguments) {
        '"' + (($arg -replace '\\(?=")', '$0\') -replace '"', '\"') + '"'
    }
    $quoted -join " "
}

function Assert-G102NoDs4Process {
    $active = @(Get-Process -Name "ds4_server" -ErrorAction SilentlyContinue)
    if ($active.Count -gt 0) {
        throw "G102 requires no active DS4 process: pid=$($active.Id -join ',')"
    }
}

function Stop-G102ProcessTree {
    param([Parameter(Mandatory=$true)][Diagnostics.Process]$Process)
    if ($Process.HasExited) { return }
    & taskkill.exe /PID $Process.Id /T /F 2>$null | Out-Null
    try { $Process.WaitForExit(30000) | Out-Null } catch {}
    if (-not $Process.HasExited) {
        try { $Process.Kill() } catch {}
        try { $Process.WaitForExit(10000) | Out-Null } catch {}
    }
    if (-not $Process.HasExited) {
        throw "G102 could not terminate timed-out subprocess tree: pid=$($Process.Id)"
    }
}

function Invoke-G102PowerShellWithDeadline {
    param(
        [Parameter(Mandatory=$true)][string[]]$Arguments,
        [Parameter(Mandatory=$true)][string]$Context
    )
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = "powershell.exe"
    $startInfo.Arguments = Join-G102ProcessArguments $Arguments
    $startInfo.UseShellExecute = $false
    $process = [Diagnostics.Process]::Start($startInfo)
    try {
        if (-not $process.WaitForExit($PerProcessTimeoutSec * 1000)) {
            Stop-G102ProcessTree $process
            throw "G102 subprocess deadline exceeded: context=$Context"
        }
        return [int]$process.ExitCode
    } finally {
        if ($process) { $process.Dispose() }
    }
}

function Test-G102RetryableQuiescenceFailure {
    param([Parameter(Mandatory=$true)][string]$Tag)
    $preflightPath = Join-Path $outdir `
        ("g7_" + $Tag + "_system_quiescence_preflight.json")
    $resultPath = Join-Path $outdir ("g7_" + $Tag + "_result.json")
    $rawPath = Join-Path $outdir ("g7_" + $Tag + "_raw_outputs.json")
    if ((Test-Path -LiteralPath $resultPath) -or
        (Test-Path -LiteralPath $rawPath) -or
        -not (Test-Path -LiteralPath $preflightPath -PathType Leaf)) {
        return $false
    }
    try {
        $preflight = Get-Content -LiteralPath $preflightPath -Raw |
            ConvertFrom-Json
        return [bool](
            [string]$preflight.schema -eq "g7_system_quiescence_preflight_v1" -and
            [bool]$preflight.skipped -eq $false -and
            [bool]$preflight.ready_to_launch -eq $false -and
            @($preflight.failures).Count -gt 0)
    } catch {
        return $false
    }
}

function Assert-G102NoArtifacts {
    param([Parameter(Mandatory=$true)][string[]]$Paths)
    $existing = @($Paths | Where-Object { Test-Path -LiteralPath $_ })
    if ($existing.Count -gt 0) {
        throw "G102 refuses to overwrite artifact(s): $($existing -join ', ')"
    }
}

function Assert-G102GateConfig {
    param([Parameter(Mandatory=$true)][object]$Config,
          [Parameter(Mandatory=$true)][string]$Tag)
    $expected = [ordered]@{
        min_touches = 2
        min_weight = 0.02
        min_mass = 0.0
        request_budget = 16
        window_calls = 40
        window_budget = 1
    }
    foreach ($name in $expected.Keys) {
        Assert-G102Property $Config $name $Tag
        $observed = [double](Get-G102Property $Config $name)
        if ([math]::Abs($observed - [double]$expected[$name]) -gt 0.000001) {
            throw "G102 combined gate mismatch: tag=$Tag field=$name"
        }
    }
}

function Assert-G102RawResultBinding {
    param(
        [Parameter(Mandatory=$true)][object]$Raw,
        [Parameter(Mandatory=$true)][object]$Result,
        [Parameter(Mandatory=$true)][string]$Tag
    )
    foreach ($name in @(
        "schema", "tag", "gate_kind", "quality_eligible", "sota_eligible",
        "contamination_reason", "allow_quality_verified_suite_receipt_requested",
        "outer_quality_process_count_requested", "outer_quality_suite_member",
        "outer_quality_member_contract_valid",
        "outer_quality_aggregate_required",
        "head", "executable_sha256",
        "ds4_cuda_sha256", "model_sha256", "iq1_s_sidecar_sha256",
        "prompt_sha256", "system_prompt_sha256",
        "model_iq1_suite_receipt_path",
        "model_iq1_suite_receipt_sha256",
        "model_iq1_suite_full_hash_verified", "output_hashes", "results")) {
        Assert-G102Property $Raw $name $Tag
    }
    if ([string]$Raw.schema -ne "g7_raw_outputs_v1" -or
        [string]$Raw.tag -ne [string]$Result.tag -or
        [string]$Raw.gate_kind -ne [string]$Result.gate_kind -or
        [bool]$Raw.quality_eligible -ne [bool]$Result.quality_eligible -or
        [bool]$Raw.sota_eligible -ne [bool]$Result.sota_eligible -or
        [string]$Raw.contamination_reason -ne
            [string]$Result.contamination_reason -or
        [bool]$Raw.allow_quality_verified_suite_receipt_requested -ne
            [bool]$Result.allow_quality_verified_suite_receipt_requested -or
        [int]$Raw.outer_quality_process_count_requested -ne
            [int]$Result.outer_quality_process_count_requested -or
        [bool]$Raw.outer_quality_suite_member -ne
            [bool]$Result.outer_quality_suite_member -or
        [bool]$Raw.outer_quality_member_contract_valid -ne
            [bool]$Result.outer_quality_member_contract_valid -or
        [bool]$Raw.outer_quality_aggregate_required -ne
            [bool]$Result.outer_quality_aggregate_required -or
        [string]$Raw.head -ne [string]$Result.head -or
        [string]$Raw.executable_sha256 -ne [string]$Result.executable_sha256 -or
        [string]$Raw.ds4_cuda_sha256 -ne [string]$Result.ds4_cuda_sha256 -or
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
        [bool]$Raw.model_iq1_suite_full_hash_verified -ne $true) {
        throw "G102 raw/result provenance mismatch: tag=$Tag"
    }
    $rawHashes = @($Raw.results | ForEach-Object { [string]$_.content_sha256 })
    $resultHashes = @($Result.results | ForEach-Object {
        [string]$_.content_sha256
    })
    if ($rawHashes.Count -ne 1 -or $resultHashes.Count -ne 1 -or
        $rawHashes[0] -ne $resultHashes[0] -or
        @($Raw.output_hashes).Count -ne 1 -or
        [string]$Raw.output_hashes[0] -ne $resultHashes[0]) {
        throw "G102 raw/result content hash mismatch: tag=$Tag"
    }
}

function Assert-G102RunContract {
    param(
        [Parameter(Mandatory=$true)][object]$Result,
        [Parameter(Mandatory=$true)][object]$Raw,
        [Parameter(Mandatory=$true)][string]$Tag
    )
    foreach ($name in @(
        "tag", "server_exit_code", "gate_kind", "quality_eligible", "sota_eligible",
        "contamination_reason", "prompt", "prompt_sha256",
        "warmup_prompt_sha256", "requested_stop_sequence",
        "requested_max_tokens", "requested_warmup_max_tokens",
        "context_requested", "context_observed", "repeats", "warmup",
        "model", "model_sha256", "model_hash_method",
        "model_iq1_suite_receipt_path", "model_iq1_suite_receipt_sha256",
        "model_iq1_suite_full_hash_verified",
        "model_iq1_suite_lock_proof_required",
        "model_iq1_suite_lock_proof_observed",
        "model_iq1_suite_lock_proof", "iq1_s_sidecar",
        "iq1_s_sidecar_sha256", "iq1_s_sidecar_bytes",
        "iq1_s_sidecar_hash_method", "iq1_s_mixed_runtime_observed",
        "iq1_s_mixed_gpu_plan_runtime_observed", "iq1_promotion_requested",
        "iq1_promotion_requested_config", "iq1_promotion_runtime_observed",
        "iq1_promotion_probation_slots_requested",
        "iq1_promotion_direct_ssd_to_vram_rejected",
        "iq1_promotion_failures", "compose_prefill_mass_open_router_requested",
        "compose_prefill_mass_reserve_slots_requested",
        "route_packed_copy_requested", "expert_tiering",
        "runtime_telemetry", "system_quiescence_preflight",
        "allow_quality_verified_suite_receipt_requested",
        "outer_quality_process_count_requested", "outer_quality_suite_member",
        "outer_quality_member_contract_valid",
        "outer_quality_aggregate_required",
        "server_runs", "results")) {
        Assert-G102Property $Result $name $Tag
    }

    Assert-G102GateConfig $Result.iq1_promotion_requested_config $Tag
    $tier = $Result.expert_tiering
    $rt = $Result.runtime_telemetry
    $sys = $Result.system_quiescence_preflight
    foreach ($name in @("failures", "forbidden_cold_ssd_to_vram",
        "cold_to_vram", "general_backing_reclaims")) {
        Assert-G102Property $tier $name $Tag
    }

    if ([string]$Result.tag -ne $Tag -or
        [int]$Result.server_exit_code -ne 0 -or
        [string]$Result.gate_kind -ne "quality" -or
        [bool]$Result.quality_eligible -ne $false -or
        [bool]$Result.sota_eligible -ne $false -or
        [string]$Result.contamination_reason -ne
            "outer-quality-suite-member-pending-aggregate" -or
        [string]$Result.prompt -ne $prompt -or
        [string]$Result.prompt_sha256 -ne $expectedPromptSHA256 -or
        [string]$Result.warmup_prompt_sha256 -ne $expectedPromptSHA256 -or
        [string]$Result.requested_stop_sequence -ne $stopSequence -or
        [int]$Result.requested_max_tokens -ne $maxTokens -or
        [int]$Result.requested_warmup_max_tokens -ne $warmupMaxTokens -or
        [int]$Result.context_requested -ne $context -or
        [int]$Result.context_observed -ne $context -or
        [int]$Result.repeats -ne 1 -or [bool]$Result.warmup -ne $true -or
        [bool]$Result.allow_quality_verified_suite_receipt_requested -ne
            $true -or
        [int]$Result.outer_quality_process_count_requested -ne $processCount -or
        [bool]$Result.outer_quality_suite_member -ne $true -or
        [bool]$Result.outer_quality_member_contract_valid -ne $true -or
        [bool]$Result.outer_quality_aggregate_required -ne $true -or
        [string]$Result.model -ne $model -or
        [string]$Result.model_sha256 -ne $expectedModelSHA256 -or
        [string]$Result.model_hash_method -ne "verified_suite_receipt_reuse" -or
        [string]$Result.model_iq1_suite_receipt_path -ne
            $script:g102SuiteReceiptPath -or
        [string]$Result.model_iq1_suite_receipt_sha256 -ne
            $script:g102SuiteReceiptSHA256 -or
        [bool]$Result.model_iq1_suite_full_hash_verified -ne $true -or
        [bool]$Result.model_iq1_suite_lock_proof_required -ne $true -or
        [bool]$Result.model_iq1_suite_lock_proof_observed -ne $true -or
        [string]$Result.iq1_s_sidecar -ne $iq1Sidecar -or
        [string]$Result.iq1_s_sidecar_sha256 -ne $expectedIq1SidecarSHA256 -or
        [UInt64]$Result.iq1_s_sidecar_bytes -ne $expectedIq1SidecarBytes -or
        [string]$Result.iq1_s_sidecar_hash_method -ne
            "verified_suite_receipt_reuse" -or
        [bool]$Result.iq1_s_mixed_runtime_observed -ne $true -or
        [bool]$Result.iq1_s_mixed_gpu_plan_runtime_observed -ne $true -or
        [bool]$Result.iq1_promotion_requested -ne $true -or
        [bool]$Result.iq1_promotion_runtime_observed -ne $true -or
        [int]$Result.iq1_promotion_probation_slots_requested -ne 16 -or
        [UInt64]$Result.iq1_promotion_direct_ssd_to_vram_rejected -ne 0 -or
        [UInt64]$Result.iq1_promotion_failures -ne 0 -or
        [bool]$Result.compose_prefill_mass_open_router_requested -ne $true -or
        [int]$Result.compose_prefill_mass_reserve_slots_requested -ne 16 -or
        [bool]$Result.route_packed_copy_requested -ne $false -or
        [UInt64]$tier.failures -ne 0 -or
        [UInt64]$tier.forbidden_cold_ssd_to_vram -ne 0 -or
        [UInt64]$tier.cold_to_vram -ne 0 -or
        [UInt64]$tier.general_backing_reclaims -le 0 -or
        [bool]$sys.skipped -ne $false -or
        [bool]$sys.ready_to_launch -ne $true -or
        [bool]$rt.contamination_abort_observed -ne $false -or
        @($Result.server_runs).Count -ne 1 -or
        @($Result.results).Count -ne 1) {
        throw "G102 run contract mismatch: tag=$Tag"
    }
    Assert-G102RawResultBinding $Raw $Result $Tag
}

function Invoke-G102Grade {
    param(
        [Parameter(Mandatory=$true)][string]$Tag,
        [Parameter(Mandatory=$true)][string]$Content
    )
    $contentPath = Join-Path $outdir ("g7_" + $Tag + "_content.html")
    if (Test-Path -LiteralPath $contentPath) {
        throw "G102 refuses to overwrite content: $contentPath"
    }
    [IO.File]::WriteAllText($contentPath, $Content,
        (New-Object Text.UTF8Encoding($false)))
    $gradeOutput = @(& $PythonPath $grader frontpage $contentPath --json 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "G102 grader failed: tag=$Tag output=$($gradeOutput -join ' ')"
    }
    try {
        $grade = ($gradeOutput -join [Environment]::NewLine) |
            ConvertFrom-Json
    } catch {
        throw "G102 grader returned invalid JSON: tag=$Tag"
    }
    if ($null -eq $grade.PSObject.Properties["level"] -or
        [int]$grade.level -lt 0 -or [int]$grade.level -gt 3) {
        throw "G102 grader level outside L0-L3: tag=$Tag"
    }
    [pscustomobject]@{
        level = [int]$grade.level
        detail = $grade.detail
        content_path = $contentPath
        content_sha256 = Get-G102SHA256 $contentPath
    }
}

function Invoke-G102Sample {
    param([Parameter(Mandatory=$true)][int]$SampleIndex)
    for ($attempt = 1; $attempt -le $QuiescenceRetryLimit; $attempt++) {
        Assert-G102NoDs4Process
        $tag = "g102_iq1_combined_quality_p$($SampleIndex)_a$attempt"
        $resultPath = Join-Path $outdir ("g7_" + $tag + "_result.json")
        $rawPath = Join-Path $outdir ("g7_" + $tag + "_raw_outputs.json")
        $failurePath = Join-Path $outdir ("g7_" + $tag + "_failure.json")
        $attemptArtifacts = @(
            $resultPath,
            $rawPath,
            $failurePath,
            (Join-Path $outdir ("g7_" + $tag + "_stdout.log")),
            (Join-Path $outdir ("g7_" + $tag + "_stderr.log")),
            (Join-Path $outdir ("g7_" + $tag + "_memory_preflight.json")),
            (Join-Path $outdir ("g7_" + $tag + "_process_isolation_preflight.json")),
            (Join-Path $outdir ("g7_" + $tag + "_system_quiescence_preflight.json")),
            (Join-Path $outdir ("g7_" + $tag + "_runtime_telemetry.jsonl")),
            (Join-Path $outdir ("g7_" + $tag + "_content.html"))
        )
        Assert-G102NoArtifacts $attemptArtifacts
        Write-Host "[g102] sample=$SampleIndex attempt=$attempt tag=$tag"
        $exitCode = Invoke-G102PowerShellWithDeadline `
            -Arguments @(New-G102MeasureArgs $tag) -Context $tag
        if ($exitCode -ne 0) {
            if ((Test-G102RetryableQuiescenceFailure $tag) -and
                $attempt -lt $QuiescenceRetryLimit) {
                Write-Host "[g102] prelaunch quiescence refusal; retrying"
                Start-Sleep -Seconds $QuiescenceRetryCooldownSec
                continue
            }
            Assert-G102NoDs4Process
            throw "G102 child failed and is not retryable: tag=$tag exit=$exitCode"
        }
        Assert-G102NoDs4Process
        if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf) -or
            -not (Test-Path -LiteralPath $rawPath -PathType Leaf) -or
            (Test-Path -LiteralPath $failurePath -PathType Leaf)) {
            throw "G102 child artifacts invalid: tag=$tag"
        }
        $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
        $raw = Get-Content -LiteralPath $rawPath -Raw | ConvertFrom-Json
        Assert-G102RunContract $result $raw $tag
        $content = [string]$raw.results[0].content
        if ([string]::IsNullOrWhiteSpace($content)) {
            throw "G102 empty output: tag=$tag"
        }
        $contentHash = Get-G102StringSHA256 $content
        if ($contentHash -ne [string]$raw.results[0].content_sha256) {
            throw "G102 content bytes/hash mismatch: tag=$tag"
        }
        $finishReason = [string]$result.server_runs[0].finish_reason
        $gradeContent = $content
        $stopDelimiterRestored = $false
        if ($finishReason -eq "stop" -and
            -not $gradeContent.TrimEnd().EndsWith($stopSequence,
                [StringComparison]::OrdinalIgnoreCase)) {
            $gradeContent += $stopSequence
            $stopDelimiterRestored = $true
        }
        $grade = Invoke-G102Grade -Tag $tag -Content $gradeContent
        return [pscustomobject]@{
            sample_index = $SampleIndex
            attempt = $attempt
            tag = $tag
            result_path = $resultPath
            result_sha256 = Get-G102SHA256 $resultPath
            raw_outputs_path = $rawPath
            raw_outputs_sha256 = Get-G102SHA256 $rawPath
            output_content_sha256 = $contentHash
            finish_reason = $finishReason
            stop_delimiter_restored_for_grading = $stopDelimiterRestored
            grade_level = $grade.level
            grade_detail = $grade.detail
            content_path = $grade.content_path
            content_file_sha256 = $grade.content_sha256
            child_quality_eligible = [bool]$result.quality_eligible
            child_sota_eligible = [bool]$result.sota_eligible
            child_contamination_reason = [string]$result.contamination_reason
            outer_quality_suite_member =
                [bool]$result.outer_quality_suite_member
            outer_quality_member_contract_valid =
                [bool]$result.outer_quality_member_contract_valid
            system_quiescence_ready =
                [bool]$result.system_quiescence_preflight.ready_to_launch
            runtime_contamination_abort_observed =
                [bool]$result.runtime_telemetry.contamination_abort_observed
            timings = $result.results[0]
        }
    }
    throw "G102 exhausted quiescence retries: sample=$SampleIndex"
}

if (-not (Test-Path -LiteralPath $harness -PathType Leaf)) {
    throw "G102 harness missing: $harness"
}
$script:harnessText = Get-Content -LiteralPath $harness -Raw
if ((Get-G102StringSHA256 $prompt) -ne $expectedPromptSHA256) {
    throw "G102 prompt SHA-256 constant mismatch"
}
$tokens = $null
$parseErrors = $null
[Management.Automation.Language.Parser]::ParseFile(
    $PSCommandPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
if ($parseErrors -and $parseErrors.Count -gt 0) {
    throw "G102 AST parse failed: $($parseErrors[0].Message)"
}

$missingPrerequisites = @(Get-G102MissingPrerequisites)
$staticReceipt = New-G102StaticReceipt $missingPrerequisites
if ($StaticCheckOnly) {
    Write-Output ($staticReceipt | ConvertTo-Json -Depth 10 -Compress)
    if ($missingPrerequisites.Count -gt 0) {
        throw "G102 static prerequisites missing: $($missingPrerequisites.parameter -join ', ')"
    }
    return
}
if ($missingPrerequisites.Count -gt 0) {
    Write-Output ($staticReceipt | ConvertTo-Json -Depth 10 -Compress)
    throw "G102 refuses to run with missing G7 prerequisites"
}

foreach ($path in @($suiteReceiptHelper, $runtimeMonitor, $grader,
    $executable, $buildManifest)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "G102 required file missing: $path"
    }
}
New-Item -ItemType Directory -Force -Path $outdir | Out-Null
Assert-G102NoArtifacts @($summaryPath, $protocolReceiptPath, $suiteReceiptPath)

$provenance = [pscustomobject]@{
    runner_sha256 = Get-G102SHA256 $PSCommandPath
    harness_sha256 = Get-G102SHA256 $harness
    runtime_monitor_sha256 = Get-G102SHA256 $runtimeMonitor
    suite_receipt_helper_sha256 = Get-G102SHA256 $suiteReceiptHelper
    grader_sha256 = Get-G102SHA256 $grader
    executable_sha256 = Get-G102SHA256 $executable
    build_manifest_sha256 = Get-G102SHA256 $buildManifest
    ds4_cuda_sha256 = Get-G102SHA256 (Join-Path $root "ds4_cuda.cu")
    ds4_c_sha256 = Get-G102SHA256 (Join-Path $root "ds4.c")
    ds4_server_c_sha256 = Get-G102SHA256 (Join-Path $root "ds4_server.c")
}

$modelLock = $null
$sidecarLock = $null
try {
    $modelLock = Open-G102ReadDenyWriteDeleteLock $model "model"
    $sidecarLock = Open-G102ReadDenyWriteDeleteLock $iq1Sidecar "IQ1_S sidecar"
    $suiteReceipt = New-G102LockedSuiteReceipt
    $protocolReceipt = [pscustomobject]@{
        schema = "g102_iq1_combined_quality_protocol_receipt_v1"
        created_utc = [DateTime]::UtcNow.ToString("o")
        protocol = $staticReceipt.protocol
        combined_gate = $staticReceipt.combined_gate
        future_g7_contract = $staticReceipt.future_g7_contract
        model_iq1_suite_receipt_path = $suiteReceipt.path
        model_iq1_suite_receipt_sha256 = $suiteReceipt.sha256
        parent_held_deny_write_delete_locks = $true
        provenance = $provenance
    }
    $protocolReceipt | ConvertTo-Json -Depth 10 |
        Set-Content -LiteralPath $protocolReceiptPath -Encoding UTF8
    $protocolReceiptSHA256 = Get-G102SHA256 $protocolReceiptPath

    $runs = @()
    for ($sample = 1; $sample -le $processCount; $sample++) {
        $runs += Invoke-G102Sample $sample
    }

    $levels = @($runs | ForEach-Object { [int]$_.grade_level } | Sort-Object)
    $uniqueOutputHashes = @($runs | ForEach-Object {
        [string]$_.output_content_sha256
    } | Select-Object -Unique)
    $medianGradeLevel = [int]$levels[1]
    $aggregateMemberContractValid = [bool](
        $runs.Count -ge 3 -and
        @($runs | Where-Object {
            -not $_.outer_quality_member_contract_valid -or
            $_.child_quality_eligible -or
            $_.child_sota_eligible
        }).Count -eq 0)
    $aggregateRuntimeClean = [bool](
        $aggregateMemberContractValid -and
        @($runs | Where-Object {
            -not $_.system_quiescence_ready -or
            $_.runtime_contamination_abort_observed
        }).Count -eq 0)
    $aggregateQualityEligible = [bool](
        $aggregateRuntimeClean -and $medianGradeLevel -ge 2)
    $aggregateSotaEligible = [bool](
        $aggregateRuntimeClean -and $medianGradeLevel -eq 3)
    $qualityStatus = if ($medianGradeLevel -eq 3) {
        "L3-clean-pass"
    } elseif ($medianGradeLevel -eq 2) {
        "L2-functional-pass-with-defects"
    } else {
        "L0-L1-quality-fail"
    }
    $summary = [pscustomobject]@{
        schema = "g102_iq1_combined_quality_v1"
        created_utc = [DateTime]::UtcNow.ToString("o")
        status = "complete"
        gate_kind = "quality"
        quality_eligible = $aggregateQualityEligible
        sota_eligible = $aggregateSotaEligible
        contamination_reason = $(if ($aggregateRuntimeClean) { "" } else {
            "outer-quality-suite-aggregate-not-eligible"
        })
        aggregate_member_contract_valid = $aggregateMemberContractValid
        aggregate_runtime_clean = $aggregateRuntimeClean
        quality_status = $qualityStatus
        sota_withheld_reason = $(if ($aggregateSotaEligible) { "" } elseif (
            $aggregateRuntimeClean) { "median-grade-below-L3" } else {
            "aggregate-runtime-not-clean"
        })
        child_claims_withheld_pending_aggregate = $true
        verdict_source = "functional_grade.py L0-L3 only"
        repeat_flag_used_as_verdict = $false
        independent_processes = $processCount
        within_process_repeats = $repeatsPerProcess
        output_hash_equality_required = $false
        outputs_identical_observed = [bool]($uniqueOutputHashes.Count -eq 1)
        unique_output_hash_count = $uniqueOutputHashes.Count
        grade_levels = $levels
        median_grade_level = $medianGradeLevel
        protocol_receipt_path = $protocolReceiptPath
        protocol_receipt_sha256 = $protocolReceiptSHA256
        model_iq1_suite_receipt_path = $suiteReceipt.path
        model_iq1_suite_receipt_sha256 = $suiteReceipt.sha256
        parent_held_deny_write_delete_locks = $true
        stop_contract = $staticReceipt.protocol
        combined_gate = $staticReceipt.combined_gate
        provenance = $provenance
        runs = $runs
    }
    $summary | ConvertTo-Json -Depth 14 |
        Set-Content -LiteralPath $summaryPath -Encoding UTF8
    Write-Host "[g102] complete median=L$($levels[1]) summary=$summaryPath"
} finally {
    if ($null -ne $sidecarLock) { try { $sidecarLock.Dispose() } catch {} }
    if ($null -ne $modelLock) { try { $modelLock.Dispose() } catch {} }
}
