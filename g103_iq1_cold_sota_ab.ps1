# G103 IQ1_S cold SOTA A/B preregistered runner (PowerShell 5.1, ASCII).
param(
    [switch]$StaticCheckOnly,
    [switch]$SafetyOnly,
    [switch]$Resume,
    [ValidateRange(600, 86400)][int]$TimeoutSec = 7200
)

$ErrorActionPreference = "Stop"

$runnerPath = $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $runnerPath
$harness = Join-Path $root "g7_measure.ps1"
$outdir = Join-Path $root "g7_runs"
$summaryPath = Join-Path $outdir "g103_iq1_cold_sota_ab_result.json"
$safetySummaryPath = Join-Path $outdir "g103_iq1_cold_sota_safety_result.json"

$model = "C:\ds4-models\ds4-2bit.gguf"
$expectedModelSHA256 =
    "efc7ed607ff27076e3e501fc3fefefa33c0ed8cf1eff483a2b7fdc0c2e616668"
$sidecar = "C:\ds4-models\DeepSeek-V4-Flash-IQ1_S-XL.gguf"
$expectedIq1SidecarSHA256 =
    "b049d1eb34c068f19ab007b33c22a7d758b578bf2b10d9276e79654f85d35047"
[UInt64]$expectedIq1SidecarBytes = 61540805344
$prompt = "Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document."
$expectedPromptSHA256 =
    "38f6ec5ee5403f59dd2418eb5d9a5a94a0f0da19df015060383bb1ae46003bb6"
$expectedControlContentSHA256 =
    "31cbc6504dcb57d42aeff9dbceb3aed943bcb32dae19a2edbf552e9fd2f52eb8"

$context = 256
$maxTokens = 64
$processesPerArm = 3
$extraProcessesPerArm = 3
$outlierRatio = 1.20
$arenaGiB = 30.0
$expectedArenaSlots = 4551
$expectedCacheCapacity = 320
$runtimeMinimumAvailableGiB = 1.0
$quiescenceCooldownSec = 90

function Get-G103StringSHA256 {
    param([Parameter(Mandatory=$true)][string]$Value)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
        ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace "-", "").
            ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Get-G103Property {
    param([object]$Object, [string]$Name, $Default = $null)
    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) {
        return $Default
    }
    $Object.PSObject.Properties[$Name].Value
}

function Get-G103ResultPath {
    param([Parameter(Mandatory=$true)][string]$Tag)
    Join-Path $outdir ("g7_" + $Tag + "_result.json")
}

function Get-G103RawPath {
    param([Parameter(Mandatory=$true)][string]$Tag)
    Join-Path $outdir ("g7_" + $Tag + "_raw_outputs.json")
}

function Get-G103FileSHA256 {
    param([Parameter(Mandatory=$true)][string]$Path)
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Test-G103HarnessParameter {
    param([Parameter(Mandatory=$true)][string]$Name)
    $script:harnessText -match ("\$" + [regex]::Escape($Name) + "(\s|=|,|\))")
}

function Assert-G103StaticContract {
    if (-not (Test-Path -LiteralPath $harness -PathType Leaf)) {
        throw "G103 harness missing: $harness"
    }
    $tokens = $null
    $errors = $null
    [Management.Automation.Language.Parser]::ParseFile(
        $runnerPath, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors -and $errors.Count -gt 0) {
        throw "G103 runner AST parse failed: $($errors[0].Message)"
    }
    if ((Get-G103StringSHA256 $prompt) -ne $expectedPromptSHA256) {
        throw "G103 prompt hash mismatch"
    }
    if ($sidecar -like (([char]68) + ":\*")) {
        throw "G103 sidecar must not use D:"
    }

    $script:harnessText = Get-Content -LiteralPath $harness -Raw
    foreach ($parameter in @(
        "ExpectedContentSHA256", "ExpectedModelSHA256",
        "ReuseVerifiedModelReceipt", "Iq1SExpertSidecar",
        "ExpectedIq1SExpertSidecarSHA256",
        "ExpectedIq1SExpertSidecarBytes", "ReuseVerifiedIq1SReceipt",
        "Iq1SLayerFirst", "Iq1SLayerLast", "Iq1SMixedColdOne",
        "Iq1SMixedGpuPlan", "Iq1SRamCacheGiB", "Iq1Promotion",
        "Iq1SPackedH2D", "Iq1SVramCachePerLayer", "RoutePackedCopy",
        "ComposePrefillMassOpenRouter", "ComposePrefillMassReserveSlots",
        "RuntimeMinimumAvailableGiB", "QuiescenceCooldownSec",
        "GateKind", "SplitFused")) {
        if (-not (Test-G103HarnessParameter $parameter)) {
            throw "G103 harness lacks -$parameter"
        }
    }
    foreach ($marker in @(
        "iq1_s_ram_cache_ssd_bytes",
        "forbidden_cold_ssd_to_vram",
        "route_packed_copy_requested",
        "iq1_s_packed_h2d_requested",
        "iq1_s_vram_cache_per_layer_requested",
        "iq1_s_mixed_gpu_plan_runtime_observed",
        "expected_content_sha256 =")) {
        if ($script:harnessText -notmatch [regex]::Escape($marker)) {
            throw "G103 harness marker missing: $marker"
        }
    }
}

function New-G103StaticReceipt {
    [pscustomobject]@{
        schema = "g103_iq1_cold_sota_ab_static_v1"
        static_check_only = [bool]$StaticCheckOnly
        no_model_presence_required = [bool]$StaticCheckOnly
        no_build_gpu_or_ds4_launch_in_static_check = [bool]$StaticCheckOnly
        safety_only_supported = $true
        runnable = $true
        protocol = [ordered]@{
            preregistered = $true
            safety_candidate_n1_structural_only = $true
            independent_processes_per_arm = $processesPerArm
            interleaved_order = "safety-candidate, then control/candidate pairs"
            outlier_rule = "if any arm has max/min > 1.20 on primary timing metrics after n3, run n3 extra per arm"
            control_expected_content_sha256 = $expectedControlContentSHA256
            candidate_expected_content_sha256 = ""
            candidate_records_observed_hash = $true
            candidate_requires_valid_finished_runtime_clean = $true
            candidate_requires_intra_arm_determinism_n3 = $true
        }
        common_config = [ordered]@{
            prompt_sha256 = $expectedPromptSHA256
            context = $context
            max_tokens = $maxTokens
            dynamic_arena_gib = $arenaGiB
            expected_arena_slots = $expectedArenaSlots
            expert_cache_n = $expectedCacheCapacity
            split_fused = $true
            runtime_minimum_available_gib = $runtimeMinimumAvailableGiB
            quiescence_required = $true
            receipt_mode = "ReuseVerifiedModelReceipt for control; ReuseVerifiedModelReceipt+ReuseVerifiedIq1SReceipt for candidate"
            suite_receipt = $false
        }
        candidate_config = [ordered]@{
            iq1_s_sidecar = $sidecar
            iq1_s_sidecar_sha256 = $expectedIq1SidecarSHA256
            iq1_s_sidecar_bytes = $expectedIq1SidecarBytes
            layers = "3..42"
            iq1_s_mixed_cold_one = $true
            iq1_s_mixed_gpu_plan = $true
            iq1_s_ram_cache_gib = 0.5
            iq1_promotion = $false
            route_packed_copy = $false
            iq1_s_packed_h2d = $false
            iq1_s_vram_cache = $false
            compose_prefill_mass_open_router = $false
            compose_prefill_mass_reserve_slots = 0
        }
    }
}

function New-G103BaseArgs {
    param(
        [Parameter(Mandatory=$true)][string]$Tag,
        [Parameter(Mandatory=$true)]
        [ValidateSet("benchmark", "structural-safety")][string]$GateKind
    )
    @(
        "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", $harness,
        "-Tag", $Tag,
        "-GateKind", $GateKind,
        "-ModelPath", $model,
        "-ExpectedModelSHA256", $expectedModelSHA256,
        "-ReuseVerifiedModelReceipt",
        "-Prompt", $prompt,
        "-MaxTokens", ([string]$maxTokens),
        "-Repeats", "1",
        "-Context", ([string]$context),
        "-BudgetGB", "2",
        "-ReserveMB", "1024",
        "-DynamicArenaGiB", "30",
        "-ArenaWrapTrustWorkerChecksum",
        "-ArenaWrapSourceParts",
        "-ArenaWrapUnlockSourceRanges",
        "-ArenaWrapUnlockWaveGiB", "4",
        "-DisableQ8F16Cache",
        "-EmbedRowStaging",
        "-ReapPrefetchThreads", "8",
        "-PrefillMassWrap",
        "-ComposePrefillMassTiering",
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
        "-QuiescenceCooldownSec", ([string]$quiescenceCooldownSec),
        "-RuntimeMinimumAvailableGiB",
            $runtimeMinimumAvailableGiB.ToString(
                [Globalization.CultureInfo]::InvariantCulture),
        "-RuntimeMaximumDiskQueueLength", "8",
        "-RuntimeContaminationSamples", "3",
        "-TimeoutSec", ([string]$TimeoutSec)
    )
}

function New-G103MeasureArgs {
    param(
        [Parameter(Mandatory=$true)][ValidateSet("control", "candidate")][string]$Arm,
        [Parameter(Mandatory=$true)][string]$Tag,
        [Parameter(Mandatory=$true)]
        [ValidateSet("benchmark", "structural-safety")][string]$GateKind
    )
    $args = @(New-G103BaseArgs -Tag $Tag -GateKind $GateKind)
    if ($Arm -eq "control") {
        $args += @("-ExpectedContentSHA256", $expectedControlContentSHA256)
    } else {
        $args += @(
            "-Iq1SExpertSidecar", $sidecar,
            "-ExpectedIq1SExpertSidecarSHA256", $expectedIq1SidecarSHA256,
            "-ExpectedIq1SExpertSidecarBytes",
                ([string]$expectedIq1SidecarBytes),
            "-ReuseVerifiedIq1SReceipt",
            "-Iq1SLayerFirst", "3",
            "-Iq1SLayerLast", "42",
            "-Iq1SMixedColdOne",
            "-Iq1SMixedGpuPlan",
            "-Iq1SRamCacheGiB", "0.5"
        )
    }
    $args
}

function Invoke-G103Arm {
    param(
        [Parameter(Mandatory=$true)][ValidateSet("control", "candidate")][string]$Arm,
        [Parameter(Mandatory=$true)][string]$Tag,
        [Parameter(Mandatory=$true)]
        [ValidateSet("benchmark", "structural-safety")][string]$GateKind,
        [Parameter(Mandatory=$true)][bool]$Safety
    )

    $resultPath = Get-G103ResultPath $Tag
    $rawPath = Get-G103RawPath $Tag
    if ($Resume -and (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        Write-Host ("[g103] resume arm=" + $Arm + " tag=" + $Tag)
    } else {
        $args = @(New-G103MeasureArgs -Arm $Arm -Tag $Tag -GateKind $GateKind)
        Write-Host ("[g103] start arm=" + $Arm + " tag=" + $Tag)
        & powershell.exe @args
        if ($LASTEXITCODE -ne 0) {
            throw "G103 harness failed: arm=$Arm tag=$Tag exit=$LASTEXITCODE"
        }
    }
    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        throw "G103 result missing: $resultPath"
    }
    $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    Assert-G103Result -Arm $Arm -Result $result -Safety $Safety
    [pscustomobject]@{
        arm = $Arm
        tag = $Tag
        safety = $Safety
        result_path = $resultPath
        result_sha256 = Get-G103FileSHA256 $resultPath
        raw_outputs_path = $rawPath
        raw_outputs_sha256 = $(if (Test-Path -LiteralPath $rawPath -PathType Leaf) {
            Get-G103FileSHA256 $rawPath
        } else { "" })
        content_sha256 = [string]$result.results[0].content_sha256
        decode_tokens_per_second =
            [double]$result.server_decode_mean_tokens_per_second
        ttft_seconds = [double]$result.server_prefill_ttft_mean_seconds
        wrap_seconds = [double]$result.prefill_mass_wrap_seconds
        mixed_calls = [UInt64](Get-G103Property $result "iq1_s_mixed_calls" 0)
        iq1_s_ram_cache_ssd_bytes =
            [UInt64](Get-G103Property $result "iq1_s_ram_cache_ssd_bytes" 0)
        tier_ssd_bytes = [UInt64]$result.expert_tiering.ssd_bytes
        available_min_gib = [math]::Round(
            [UInt64]$result.runtime_telemetry.windows_available_min_bytes /
            1GB, 6)
        result = $result
    }
}

function Assert-G103CommonG73Contract {
    param([Parameter(Mandatory=$true)][object]$Result)
    $tier = $Result.expert_tiering
    if ([int]$Result.server_exit_code -ne 0 -or
        [string]$Result.model -ne $model -or
        [string]$Result.model_sha256 -ine $expectedModelSHA256 -or
        [string]$Result.model_hash_method -ne "verified_receipt_reuse" -or
        [string]$Result.prompt_sha256 -ine $expectedPromptSHA256 -or
        [int]$Result.requested_max_tokens -ne $maxTokens -or
        [int]$Result.context_requested -ne $context -or
        [int]$Result.reserve_mb -ne 1024 -or
        [math]::Abs([double]$Result.dynamic_arena_gib_requested - $arenaGiB) -gt 0.001 -or
        [int]$Result.dynamic_arena_allocated_slots -ne $expectedArenaSlots -or
        [bool](Get-G103Property $Result "dynamic_arena_cap_capped" $false) -or
        [int]$Result.expert_cache_requested -ne $expectedCacheCapacity -or
        [int]$Result.expert_cache_capacity -ne $expectedCacheCapacity -or
        [double]$Result.expert_cache_reserve_gb -ne 0.125 -or
        [string]$Result.expert_cache_policy -ne "lru" -or
        -not [bool]$Result.arena_wrap_trust_worker_checksum_requested -or
        [string]$Result.arena_wrap_schedule_requested -ne "source-parts" -or
        [string]$Result.arena_wrap_schedule_observed -ne "source-parts" -or
        -not [bool]$Result.arena_wrap_unlock_source_ranges_requested -or
        -not [bool]$Result.prefill_mass_wrap_observed -or
        [string]$Result.prefill_mass_wrap_result -ne "published" -or
        -not [bool]$Result.compose_prefill_mass_tiering_requested -or
        -not [bool]$tier.compose_prefill_mass_tiering_observed -or
        [string]$tier.requested_mode -ne "enforce" -or
        [string]$tier.requested_policy -ne "mass-lfru" -or
        [int]$tier.clock_calls -ne 430 -or
        [int]$tier.replacement_budget -ne 32 -or
        [int]$tier.min_frequency -ne 3 -or
        [math]::Abs([double]$tier.hysteresis - 1.25) -gt 0.000001 -or
        [int]$tier.states_vram -ne $expectedCacheCapacity -or
        [UInt64]$tier.failures -ne 0 -or
        [UInt64]$tier.ssd_bytes -ne 0 -or
        [UInt64]$tier.forbidden_cold_ssd_to_vram -ne 0 -or
        -not [bool]$Result.gpu_resident_routes_requested -or
        -not [bool]$Result.route_no_default_sync_requested -or
        [UInt64]$Result.gpu_resident_routes_default_sync_calls -ne 0 -or
        [UInt64]$Result.gpu_resident_routes_no_default_sync_calls -ne
            [UInt64]$Result.gpu_resident_routes_calls -or
        [UInt64]$Result.gpu_resident_routes_errors -ne 0 -or
        -not [bool]$Result.split_fused_requested -or
        -not [bool](Get-G103Property $Result "split_fused_observed" $false) -or
        [UInt64](Get-G103Property $Result "split_fused_calls" 0) -ne
            [UInt64]$Result.gpu_resident_routes_calls -or
        ([UInt64](Get-G103Property $Result "split_fused_hits" 0) +
         [UInt64](Get-G103Property $Result "split_fused_misses" 0)) -ne
            [UInt64]$tier.selected -or
        [UInt64](Get-G103Property -Object $Result `
            -Name "split_fused_miss_scratch_bytes_avoided" -Default 0) -le 0 -or
        [UInt64](Get-G103Property -Object $Result `
            -Name "split_fused_sum_read_bytes_avoided" -Default 0) -le 0 -or
        [bool]$Result.route_packed_copy_requested -or
        [bool]$Result.route_packed_copy_observed -or
        [UInt64]$Result.route_packed_copy_bytes -ne 0 -or
        -not [bool]$Result.memory_preflight.ready_to_launch -or
        -not [bool]$Result.process_isolation_preflight.ready_to_launch -or
        -not [bool]$Result.system_quiescence_preflight.ready_to_launch -or
        [bool]$Result.system_quiescence_preflight.skipped -or
        [bool]$Result.runtime_telemetry.contamination_abort_observed -or
        [string]$Result.contamination_reason -ne "" -or
        [int]$Result.arena_wrap_unlock_source_ranges_summary_phases -ne 3 -or
        [int]$Result.arena_wrap_unlock_source_ranges_summary_waves -ne 9 -or
        [UInt64]$Result.arena_wrap_unlock_source_ranges_summary_max_wave_bytes -gt
            [UInt64](4GB) -or
        [UInt64]$Result.arena_wrap_unlock_source_ranges_summary_failed -ne 0 -or
        [double]$Result.contamination_runtime_minimum_available_gib -ne
            $runtimeMinimumAvailableGiB) {
        throw "G103 common G73 static32_split_fused contract mismatch: tag=$($Result.tag)"
    }
}

function Assert-G103Result {
    param(
        [Parameter(Mandatory=$true)][ValidateSet("control", "candidate")][string]$Arm,
        [Parameter(Mandatory=$true)][object]$Result,
        [Parameter(Mandatory=$true)][bool]$Safety
    )
    Assert-G103CommonG73Contract -Result $Result
    if (@($Result.results).Count -ne 1) {
        throw "G103 requires one repeat per independent process"
    }
    $sample = $Result.results[0]
    if ([string]::IsNullOrWhiteSpace([string]$sample.content) -or
        [string]$sample.content_sha256 -notmatch '^[0-9a-fA-F]{64}$' -or
        [int]$sample.completion_tokens -le 0) {
        throw "G103 invalid output sample: tag=$($Result.tag)"
    }
    $server = @($Result.server_runs)[0]
    if ([string]$server.finish_reason -notin @("stop", "length")) {
        throw "G103 output did not finish cleanly: tag=$($Result.tag)"
    }
    if ($Arm -eq "control") {
        if ([string]$Result.expected_content_sha256 -ine
            $expectedControlContentSHA256 -or
            [string]$sample.content_sha256 -ine $expectedControlContentSHA256 -or
            -not [bool]$Result.outputs_identical -or
            [string]$Result.iq1_s_sidecar -ne "" -or
            [bool]$Result.iq1_s_mixed_cold_one -or
            [bool]$Result.iq1_s_mixed_runtime_observed -or
            [bool]$Result.iq1_s_mixed_gpu_plan_requested -or
            [bool]$Result.iq1_promotion_requested) {
            throw "G103 control exact-hash/IQ1 absence contract mismatch"
        }
    } else {
        if ([string]$Result.expected_content_sha256 -ne "" -or
            [string]$Result.iq1_s_sidecar -ne $sidecar -or
            [string]$Result.iq1_s_sidecar_sha256 -ine
                $expectedIq1SidecarSHA256 -or
            [UInt64]$Result.iq1_s_sidecar_bytes -ne
                $expectedIq1SidecarBytes -or
            [string]$Result.iq1_s_sidecar_hash_method -ne
                "verified_receipt_reuse" -or
            -not [bool]$Result.iq1_s_sidecar_runtime_observed -or
            [UInt64]$Result.iq1_s_sidecar_failures -ne 0 -or
            [int]$Result.effective_ds4_environment.DS4_IQ1_S_LAYER_FIRST -ne 3 -or
            [int]$Result.effective_ds4_environment.DS4_IQ1_S_LAYER_LAST -ne 42 -or
            [double]$Result.iq1_s_ram_cache_requested_gib -ne 0.5 -or
            -not [bool]$Result.iq1_s_ram_cache_runtime_observed -or
            [UInt64]$Result.iq1_s_ram_cache_failures -ne 0 -or
            [int]$Result.iq1_s_vram_cache_per_layer_requested -ne 0 -or
            [bool]$Result.iq1_s_vram_cache_runtime_observed -or
            [UInt64]$Result.iq1_s_vram_cache_h2d_bytes -ne 0 -or
            [UInt64]$Result.iq1_s_vram_cache_failures -ne 0 -or
            -not [bool]$Result.iq1_s_mixed_cold_one -or
            -not [bool]$Result.iq1_s_mixed_runtime_observed -or
            [UInt64]$Result.iq1_s_mixed_calls -le 0 -or
            [UInt64]$Result.iq1_s_mixed_cold_iq1 -le 0 -or
            [UInt64]$Result.iq1_s_mixed_joins -le 0 -or
            [UInt64]$Result.iq1_s_mixed_failures -ne 0 -or
            -not [bool]$Result.iq1_s_mixed_gpu_plan_requested -or
            -not [bool]$Result.iq1_s_mixed_gpu_plan_runtime_observed -or
            [UInt64]$Result.iq1_s_mixed_gpu_plan_calls -le 0 -or
            [UInt64]$Result.iq1_s_mixed_gpu_plan_failures -ne 0 -or
            [bool]$Result.iq1_promotion_requested -or
            [bool]$Result.iq1_promotion_runtime_observed -or
            [UInt64]$Result.iq1_promotion_direct_ssd_to_vram_rejected -ne 0 -or
            [UInt64]$Result.iq1_promotion_failures -ne 0 -or
            [bool]$Result.iq1_s_packed_h2d_requested) {
            throw "G103 candidate IQ1 cold/planner/no-promotion contract mismatch"
        }
        if ([UInt64]$Result.expert_tiering.ssd_bytes -ne 0) {
            throw "G103 tier.ssd_bytes is IQ2 backing and must stay zero"
        }
        [void][UInt64]$Result.iq1_s_ram_cache_ssd_bytes
    }
}

function Test-G103Outlier {
    param([object[]]$Rows, [string]$Arm)
    $armRows = @($Rows | Where-Object { $_.arm -eq $Arm -and -not $_.safety })
    if ($armRows.Count -lt 3) { return $false }
    foreach ($field in @("decode_tokens_per_second", "ttft_seconds", "wrap_seconds")) {
        $values = @($armRows | ForEach-Object { [double]$_.$field } |
            Where-Object { $_ -gt 0.0 } | Sort-Object)
        if ($values.Count -lt 3) { continue }
        if (($values[-1] / $values[0]) -gt $outlierRatio) {
            return $true
        }
    }
    return $false
}

function Assert-G103Aggregate {
    param([object[]]$Rows)
    $controlRows = @($Rows | Where-Object { $_.arm -eq "control" -and -not $_.safety })
    $candidateRows = @($Rows | Where-Object { $_.arm -eq "candidate" -and -not $_.safety })
    if ($controlRows.Count -lt 3 -or $candidateRows.Count -lt 3) {
        throw "G103 aggregate requires n>=3 per arm"
    }
    $controlHashes = @($controlRows | ForEach-Object { $_.content_sha256 } |
        Select-Object -Unique)
    $candidateHashes = @($candidateRows | ForEach-Object { $_.content_sha256 } |
        Select-Object -Unique)
    if ($controlHashes.Count -ne 1 -or
        [string]$controlHashes[0] -ine $expectedControlContentSHA256) {
        throw "G103 control aggregate hash contract mismatch"
    }
    if ($candidateHashes.Count -ne 1) {
        throw "G103 candidate determinism failed across independent n>=3"
    }

    $matrixRows = @($controlRows + $candidateRows)
    foreach ($field in @(
        "head", "executable_sha256", "ds4_cuda_sha256", "ds4_c_sha256",
        "build_manifest_sha256", "build_input_fingerprint_sha256",
        "harness_sha256", "model_sha256", "prompt_sha256")) {
        $values = @($matrixRows | ForEach-Object {
            [string](Get-G103Property $_.result $field "")
        } | Select-Object -Unique)
        if ($values.Count -ne 1 -or [string]::IsNullOrWhiteSpace($values[0])) {
            throw "G103 mixed or missing provenance: field=$field"
        }
    }
    foreach ($field in @(
        "iq1_s_sidecar_sha256", "iq1_s_sidecar_receipt_sha256")) {
        $values = @($candidateRows | ForEach-Object {
            [string](Get-G103Property $_.result $field "")
        } | Select-Object -Unique)
        if ($values.Count -ne 1 -or $values[0] -notmatch '^[0-9a-fA-F]{64}$') {
            throw "G103 mixed or missing IQ1 provenance: field=$field"
        }
    }
}

Assert-G103StaticContract
if ($StaticCheckOnly) {
    New-G103StaticReceipt | ConvertTo-Json -Depth 8
    exit 0
}

New-Item -ItemType Directory -Force -Path $outdir | Out-Null

foreach ($receipt in @("$model.receipt.json", "$sidecar.receipt.json")) {
    if (-not (Test-Path -LiteralPath $receipt -PathType Leaf)) {
        throw "G103 required verified receipt missing: $receipt"
    }
}

$rows = @()
$rows += Invoke-G103Arm -Arm "candidate" `
    -Tag "g103_safety_candidate_iq1_cold_n1" `
    -GateKind "structural-safety" -Safety $true

if ($SafetyOnly) {
    $safetySummary = [ordered]@{
        schema = "g103_iq1_cold_sota_safety_v1"
        measured_utc = [DateTime]::UtcNow.ToString("o")
        structural_only = $true
        performance_claim_allowed = $false
        quality_claim_allowed = $false
        matrix_started = $false
        result = $rows[0]
    }
    $safetySummary | ConvertTo-Json -Depth 10 |
        Set-Content -LiteralPath $safetySummaryPath -Encoding UTF8
    $safetySummary | ConvertTo-Json -Depth 10
    exit 0
}

for ($i = 1; $i -le $processesPerArm; $i++) {
    $rows += Invoke-G103Arm -Arm "control" `
        -Tag ("g103_control_g73_static32_split_fused_p" + $i) `
        -GateKind "benchmark" -Safety $false
    $rows += Invoke-G103Arm -Arm "candidate" `
        -Tag ("g103_candidate_iq1_cold_sota_p" + $i) `
        -GateKind "benchmark" -Safety $false
}

$outlierAfterN3 = [bool](
    (Test-G103Outlier -Rows $rows -Arm "control") -or
    (Test-G103Outlier -Rows $rows -Arm "candidate"))
if ($outlierAfterN3) {
    for ($i = ($processesPerArm + 1);
         $i -le ($processesPerArm + $extraProcessesPerArm); $i++) {
        $rows += Invoke-G103Arm -Arm "control" `
            -Tag ("g103_control_g73_static32_split_fused_p" + $i) `
            -GateKind "benchmark" -Safety $false
        $rows += Invoke-G103Arm -Arm "candidate" `
            -Tag ("g103_candidate_iq1_cold_sota_p" + $i) `
            -GateKind "benchmark" -Safety $false
    }
}

Assert-G103Aggregate -Rows $rows

$controlRows = @($rows | Where-Object { $_.arm -eq "control" -and -not $_.safety })
$candidateRows = @($rows | Where-Object { $_.arm -eq "candidate" -and -not $_.safety })
$candidateHash = @($candidateRows | Select-Object -First 1).content_sha256
$summary = [ordered]@{
    schema = "g103_iq1_cold_sota_ab_v1"
    measured_utc = [DateTime]::UtcNow.ToString("o")
    preregistered = $true
    safety_candidate_structural_only = $true
    safety_claim_allowed = $false
    control_expected_content_sha256 = $expectedControlContentSHA256
    candidate_expected_content_sha256 = ""
    candidate_observed_content_sha256 = $candidateHash
    candidate_quality_claim_allowed = $false
    candidate_valid_finished_runtime_clean = $true
    candidate_deterministic_intra_arm = $true
    zero_failures = $true
    outlier_after_n3 = $outlierAfterN3
    independent_processes = [ordered]@{
        control = $controlRows.Count
        candidate = $candidateRows.Count
    }
    gates = [ordered]@{
        arena_4551_not_capped = $true
        cache320 = $true
        split_fused_accounting = $true
        iq1_mixed_runtime_gpu_planner_observed = $true
        promotion_requested_false = $true
        route_packed_copy_false = $true
        no_forbidden_direct_cold_ssd_to_vram = $true
        tier_ssd_bytes_iq2_zero = $true
        iq1_s_ram_cache_ssd_bytes_allowed_and_measured = $true
    }
    rows = @($rows | ForEach-Object {
        [ordered]@{
            arm = $_.arm
            tag = $_.tag
            safety = $_.safety
            result_path = $_.result_path
            result_sha256 = $_.result_sha256
            raw_outputs_path = $_.raw_outputs_path
            raw_outputs_sha256 = $_.raw_outputs_sha256
            content_sha256 = $_.content_sha256
            decode_tokens_per_second = $_.decode_tokens_per_second
            ttft_seconds = $_.ttft_seconds
            wrap_seconds = $_.wrap_seconds
            mixed_calls = $_.mixed_calls
            tier_ssd_bytes = $_.tier_ssd_bytes
            iq1_s_ram_cache_ssd_bytes = $_.iq1_s_ram_cache_ssd_bytes
            available_min_gib = $_.available_min_gib
        }
    })
}
$summary | ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath $summaryPath -Encoding UTF8
$summary | ConvertTo-Json -Depth 8
