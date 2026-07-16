# G95 IQ1_S mixed 5:1 GPU-plan quality A/B (PowerShell 5.1, ASCII).
param(
    [switch]$StaticCheckOnly,
    [switch]$SkipBuild,
    [switch]$Resume,
    [ValidateRange(1.0, 8.0)][double]$Iq1CacheGiB = 4.0
)

$ErrorActionPreference = "Stop"
$runnerPath = $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $runnerPath
$harness = Join-Path $root "g7_measure.ps1"
$buildRunner = Join-Path $root "g7_build.ps1"
$outdir = Join-Path $root "g7_runs"
$model = "C:\ds4-models\ds4-2bit.gguf"
$modelSha256 = "efc7ed607ff27076e3e501fc3fefefa33c0ed8cf1eff483a2b7fdc0c2e616668"
$sidecar = "D:\ds4-models\DeepSeek-V4-Flash-IQ1_S-XL.gguf"
$sidecarBytes = [UInt64]61540805344
$sidecarSha256 = "b049d1eb34c068f19ab007b33c22a7d758b578bf2b10d9276e79654f85d35047"
$sidecarSource = "https://huggingface.co/persadian/DeepSeek-V4-Flash-IQ1_S-XL/resolve/main/DeepSeek-V4-Flash-IQ1_S-XL.gguf"
$sidecarSourceRepository = "https://huggingface.co/persadian/DeepSeek-V4-Flash-IQ1_S-XL"
$prompt = "Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document."
$promptSha256 = "38f6ec5ee5403f59dd2418eb5d9a5a94a0f0da19df015060383bb1ae46003bb6"
$repeatsPerArm = 3
$maxTokens = 768
$context = 1024
$warmupMaxTokens = 64
$stopSequence = "</html>"
$timeoutSec = 7200
$cacheLabel = $Iq1CacheGiB.ToString(
    "0.###", [Globalization.CultureInfo]::InvariantCulture).Replace(".", "p")
$cacheArgument = $Iq1CacheGiB.ToString(
    "0.###", [Globalization.CultureInfo]::InvariantCulture)
$controlTag = "g95_control_main_iq2_quality_n3"
$candidateTag = "g95_candidate_iq1_cache${cacheLabel}_mixed_gpu_plan_quality_n3"
$summaryPath = Join-Path $outdir "g95_iq1_cache${cacheLabel}_mixed_quality_ab_result.json"
$gradingPath = Join-Path $outdir "g95_iq1_cache${cacheLabel}_mixed_quality_ab_grading.json"

function Get-G95ResultPath([string]$Tag) {
    Join-Path $outdir ("g7_" + $Tag + "_result.json")
}

function Get-G95RawPath([string]$Tag) {
    Join-Path $outdir ("g7_" + $Tag + "_raw_outputs.json")
}

function Get-G95Sha256([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-G95TextSha256([string]$Text) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Assert-G95StaticContract {
    foreach ($path in @($harness, $buildRunner)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "G95 static check failed: missing $path"
        }
    }

    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $runnerPath, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        throw ("G95 runner syntax failed: " +
            (($errors | ForEach-Object { $_.Message }) -join " | "))
    }
    if ((Get-G95TextSha256 $prompt) -ne $promptSha256) {
        throw "G95 prompt provenance mismatch"
    }
    if ($repeatsPerArm -lt 3) {
        throw "G95 requires n>=3 per arm"
    }
    if ($maxTokens -ne 768 -or $context -ne 1024 -or
        $warmupMaxTokens -ne 64 -or $stopSequence -ne "</html>") {
        throw "G95 token/context/warmup contract mismatch"
    }

    $harnessText = Get-Content -LiteralPath $harness -Raw
    foreach ($needle in @(
            '[ValidateSet("benchmark", "structural-safety", "quality")]',
            '[switch]$AllowNonIdenticalRepeatOutputs',
            '[string]$StopSequence = ""',
            '[switch]$PrefillMassObserve',
            '[switch]$PrefillMassWrap',
            '[switch]$ComposePrefillMassTiering',
            '[switch]$ArenaWrapUnlockSourceRanges',
            '[switch]$Iq1SMixedColdOne',
            '[switch]$Iq1SMixedGpuPlan',
            '[ValidateRange(0.0, 48.0)][double]$Iq1SRamCacheGiB',
            'iq1_s_mixed_gpu_plan_calls = $iq1MixedGpuPlanCalls',
            'quality_eligible = $qualityEligible',
            'sota_eligible = $sotaEligible',
            'temperature = 0',
            'think = $false')) {
        if ($harnessText -notmatch [regex]::Escape($needle)) {
            throw "G95 harness lacks required contract: $needle"
        }
    }
}

function New-G95BaseMeasureArgs([string]$Tag) {
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
        "-TimeoutSec", "$timeoutSec"
    )
}

function Invoke-G95Arm {
    param(
        [Parameter(Mandatory=$true)][ValidateSet("control_main_iq2", "candidate_iq1_mixed")][string]$Arm,
        [Parameter(Mandatory=$true)][string]$Tag
    )

    $resultPath = Get-G95ResultPath $Tag
    $rawPath = Get-G95RawPath $Tag
    if ($Resume) {
        if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf) -or
            -not (Test-Path -LiteralPath $rawPath -PathType Leaf)) {
            throw "G95 resume artifact missing for arm=$Arm"
        }
    } else {
        $measureArgs = New-G95BaseMeasureArgs $Tag
        if ($Arm -eq "candidate_iq1_mixed") {
            $measureArgs += @(
                "-Iq1SExpertSidecar", $sidecar,
                "-ExpectedIq1SExpertSidecarSHA256", $sidecarSha256,
                "-ExpectedIq1SExpertSidecarBytes", "$sidecarBytes",
                "-Iq1SLayerFirst", "3",
                "-Iq1SLayerLast", "42",
                "-Iq1SMixedColdOne",
                "-Iq1SMixedGpuPlan",
                "-Iq1SRamCacheGiB", $cacheArgument
            )
        }
        Write-Host ("[g95] start arm=" + $Arm + " tag=" + $Tag)
        & powershell.exe @measureArgs
        if ($LASTEXITCODE -ne 0) {
            throw "G95 harness failed: arm=$Arm exit=$LASTEXITCODE"
        }
    }

    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $rawPath -PathType Leaf)) {
        throw "G95 output artifacts missing: arm=$Arm"
    }
    $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    Assert-G95ArmResult -Arm $Arm -Result $result -ResultPath $resultPath -RawPath $rawPath
}

function Assert-G95ArmResult {
    param(
        [Parameter(Mandatory=$true)][ValidateSet("control_main_iq2", "candidate_iq1_mixed")][string]$Arm,
        [Parameter(Mandatory=$true)][object]$Result,
        [Parameter(Mandatory=$true)][string]$ResultPath,
        [Parameter(Mandatory=$true)][string]$RawPath
    )

    if ([string]$Result.gate_kind -ne "quality" -or
        -not [bool]$Result.quality_eligible -or
        -not [bool]$Result.sota_eligible -or
        [string]$Result.contamination_reason -ne "" -or
        [int]$Result.server_exit_code -ne 0 -or
        [string]$Result.model_sha256 -ine $modelSha256 -or
        [string]$Result.model_expected_sha256 -ine $modelSha256 -or
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
        [int]$Result.expert_cache_requested -ne 320 -or
        [double]$Result.expert_cache_reserve_gb -ne 0.125 -or
        [string]$Result.expert_cache_policy -ne "lru" -or
        -not [bool]$Result.gpu_resident_routes_requested -or
        -not [bool]$Result.route_no_default_sync_requested -or
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
        @($Result.results).Count -ne $repeatsPerArm) {
        throw "G95 common quality/G86-stack contract mismatch: arm=$Arm"
    }

    foreach ($sample in @($Result.results)) {
        if ([int]$sample.completion_tokens -le 0 -or
            [string]::IsNullOrWhiteSpace([string]$sample.content) -or
            [string]$sample.content_sha256 -notmatch '^[0-9a-fA-F]{64}$') {
            throw "G95 raw output integrity failure: arm=$Arm repeat=$($sample.repeat)"
        }
    }

    if ($Arm -eq "control_main_iq2") {
        if ([string]$Result.iq1_s_sidecar -or
            [bool]$Result.iq1_s_sidecar_runtime_observed -or
            [UInt64]$Result.iq1_s_sidecar_route_calls -ne 0 -or
            [UInt64]$Result.iq1_s_sidecar_route_slots -ne 0 -or
            [UInt64]$Result.iq1_s_sidecar_selected_loads -ne 0 -or
            [UInt64]$Result.iq1_s_sidecar_failures -ne 0 -or
            [double]$Result.iq1_s_ram_cache_requested_gib -ne 0.0 -or
            [bool]$Result.iq1_s_ram_cache_runtime_observed -or
            [bool]$Result.iq1_s_mixed_cold_one -or
            [bool]$Result.iq1_s_mixed_runtime_observed -or
            [UInt64]$Result.iq1_s_mixed_calls -ne 0 -or
            [UInt64]$Result.iq1_s_mixed_failures -ne 0 -or
            [bool]$Result.iq1_s_mixed_gpu_plan_requested -or
            [bool]$Result.iq1_s_mixed_gpu_plan_runtime_observed -or
            [UInt64]$Result.iq1_s_mixed_gpu_plan_calls -ne 0 -or
            [UInt64]$Result.iq1_s_mixed_gpu_plan_failures -ne 0) {
            throw "G95 control contaminated by IQ1_S/mixed/planner telemetry"
        }
    } else {
        $mixedCalls = [UInt64]$Result.iq1_s_mixed_calls
        $hotMain = [UInt64]$Result.iq1_s_mixed_hot_main
        $coldIq1 = [UInt64]$Result.iq1_s_mixed_cold_iq1
        $plannerCalls = [UInt64]$Result.iq1_s_mixed_gpu_plan_calls
        if ([string]$Result.iq1_s_sidecar_sha256 -ine $sidecarSha256 -or
            [UInt64]$Result.iq1_s_sidecar_bytes -ne $sidecarBytes -or
            [string]$Result.iq1_s_sidecar_source -ne $sidecarSource -or
            -not [bool]$Result.iq1_s_sidecar_runtime_observed -or
            [UInt64]$Result.iq1_s_sidecar_failures -ne 0 -or
            [UInt64]$Result.iq1_s_sidecar_route_calls -eq 0 -or
            [UInt64]$Result.iq1_s_sidecar_route_calls -ne [UInt64]$Result.iq1_s_sidecar_selected_loads -or
            [int]$Result.effective_ds4_environment.DS4_IQ1_S_LAYER_FIRST -ne 3 -or
            [int]$Result.effective_ds4_environment.DS4_IQ1_S_LAYER_LAST -ne 42 -or
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
            throw "G95 candidate IQ1_S mixed/provenance/planner contract mismatch"
        }
    }

    [pscustomobject]@{
        arm = $Arm
        tag = [string]$Result.tag
        result_path = $ResultPath
        result_sha256 = Get-G95Sha256 $ResultPath
        raw_outputs_path = $RawPath
        raw_outputs_sha256 = Get-G95Sha256 $RawPath
        result = $Result
    }
}

function Assert-G95MatchedPair([object]$Control, [object]$Candidate) {
    foreach ($field in @(
            "head", "executable_sha256", "ds4_cuda_sha256", "ds4_c_sha256",
            "ds4_server_c_sha256", "ds4_spex_predict_c_sha256", "ds4_gpu_h_sha256",
            "ds4_spex_queue_h_sha256", "os_thread_h_sha256", "cmake_sha256",
            "build_manifest_sha256", "build_manifest_input_fingerprint_sha256",
            "harness_sha256", "memory_preflight_harness_sha256",
            "runtime_monitor_harness_sha256", "model_sha256",
            "model_expected_sha256", "prompt_sha256", "system_prompt_sha256",
            "warmup_prompt_sha256", "requested_max_tokens",
            "requested_stop_sequence",
            "requested_warmup_max_tokens", "context_requested", "budget_gb",
            "reserve_mb", "dynamic_arena_gib_requested",
            "arena_wrap_trust_worker_checksum_requested",
            "arena_wrap_schedule_requested", "arena_wrap_source_requested",
            "arena_wrap_unlock_source_ranges_requested",
            "arena_wrap_unlock_wave_gib_requested", "q8_f16_cache_disabled",
            "embed_row_staging_requested", "reap_prefetch_threads_requested",
            "prefill_mass_observe_requested", "prefill_mass_wrap_requested",
            "compose_prefill_mass_tiering_requested", "expert_cache_requested",
            "expert_cache_reserve_gb", "expert_cache_policy",
            "gpu_resident_routes_requested", "route_no_default_sync_requested",
            "split_fused_requested", "expert_tiering_requested",
            "expert_tier_policy_requested", "expert_tier_clock_calls_requested",
            "expert_tier_replacement_budget_requested",
            "expert_tier_min_frequency_requested",
            "expert_tier_hysteresis_requested")) {
        if ([string]$Control.$field -ne [string]$Candidate.$field) {
            throw "G95 A/B provenance/settings mismatch: field=$field"
        }
    }
}

function New-G95GradeRows([object[]]$Arms) {
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

function Merge-G95RecordedGrades([object[]]$ExpectedRows) {
    if (-not (Test-Path -LiteralPath $gradingPath -PathType Leaf)) {
        return @($ExpectedRows)
    }
    $existing = Get-Content -LiteralPath $gradingPath -Raw | ConvertFrom-Json
    $existingRows = @($existing.samples)
    if ($existingRows.Count -ne $ExpectedRows.Count) {
        throw "G95 existing grading row count does not match measured samples"
    }
    $merged = @()
    foreach ($expected in $ExpectedRows) {
        $matches = @($existingRows | Where-Object {
            [string]$_.sample_id -eq [string]$expected.sample_id
        })
        if ($matches.Count -ne 1) {
            throw "G95 existing grading sample identity mismatch: $($expected.sample_id)"
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
            throw "G95 existing grading provenance mismatch: $($expected.sample_id)"
        }
        $expected.grade_l0_l3 = $recorded.grade_l0_l3
        $expected.grader = $recorded.grader
        $expected.graded_utc = $recorded.graded_utc
        $expected.notes = $recorded.notes
        $merged += $expected
    }
    return @($merged)
}

New-Item -ItemType Directory -Force -Path $outdir | Out-Null
Assert-G95StaticContract
if ($StaticCheckOnly) {
    Write-Host "G95 static contract PASS"
    exit 0
}

if (-not $SkipBuild -and -not $Resume) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $buildRunner
    if ($LASTEXITCODE -ne 0) { throw "G95 provenance build failed" }
}

$control = Invoke-G95Arm -Arm "control_main_iq2" -Tag $controlTag
$candidate = Invoke-G95Arm -Arm "candidate_iq1_mixed" -Tag $candidateTag
Assert-G95MatchedPair -Control $control.result -Candidate $candidate.result

$expectedGradeRows = @(New-G95GradeRows @($control, $candidate))
$gradeRows = @(Merge-G95RecordedGrades $expectedGradeRows)
$compiledGrades = @($gradeRows | Where-Object {
        [string]$_.grade_l0_l3 -match '^L[0-3]$' -and
        -not [string]::IsNullOrWhiteSpace([string]$_.grader) -and
        -not [string]::IsNullOrWhiteSpace([string]$_.graded_utc)
    }).Count
$qualityClaimAllowed = [bool]($compiledGrades -eq ($repeatsPerArm * 2))

$grading = [ordered]@{
    schema = "g95_iq1_mixed_quality_grading_v1"
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
        "Inspect every preserved raw output and record one L0-L3 grade per row.",
        "Record grader identity, UTC timestamp, and notes for every grade.",
        "Do not infer a grade from output hashes, repetition flags, throughput, token counts, or arm telemetry.",
        "Do not issue an arm-level quality claim until all six grades have been recorded."
    )
    samples = $gradeRows
    summary = [ordered]@{
        quality_claim_allowed = $qualityClaimAllowed
        verdict = $(if ($qualityClaimAllowed) { "ready-for-human-grade-summary" } else { "pending-six-recorded-l0-l3-grades" })
    }
}
$grading | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $gradingPath -Encoding UTF8

$summary = [ordered]@{
    schema = "g95_iq1_mixed_quality_ab_v1"
    measured_utc = [DateTime]::UtcNow.ToString("o")
    status = "measurement-complete-grading-required"
    gate_kind = "quality"
    quality_claim_allowed = $qualityClaimAllowed
    quality_verdict = $(if ($qualityClaimAllowed) { "requires-human-grade-summary" } else { "pending-recorded-human-l0-l3-grading" })
    verdict_source_required = "recorded-human-l0-l3-grades-only"
    automatic_quality_verdict = $false
    repeats_per_arm = $repeatsPerArm
    required_grade_count = ($repeatsPerArm * 2)
    compiled_grade_count = $compiledGrades
    n_requirement_satisfied = ($repeatsPerArm -ge 3)
    temperature = 0
    think = $false
    prompt = $prompt
    prompt_sha256 = $promptSha256
    max_tokens = $maxTokens
    context = $context
    stop_sequence = $stopSequence
    warmup_max_tokens = $warmupMaxTokens
    warmup_prompt = "same-as-measurement-prompt"
    non_identical_repeat_outputs_allowed = $true
    contamination_reason = ""
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
        quantization_layout = [string]$candidate.result.iq1_s_sidecar_quantization_layout
        imatrix_provenance = [string]$candidate.result.iq1_s_sidecar_imatrix_provenance
    }
    common_settings = [ordered]@{
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
        split_fused = $true
        reap_prefetch_threads = 8
        iq1_s_ram_cache_gib = $Iq1CacheGiB
        system_quiescence_required = $true
    }
    arms = @(
        [ordered]@{
            arm = $control.arm
            tag = $control.tag
            role = "control main IQ2; sidecar/mixed/planner off"
            raw_outputs_path = $control.raw_outputs_path
            raw_outputs_sha256 = $control.raw_outputs_sha256
            result_path = $control.result_path
            result_sha256 = $control.result_sha256
            output_sha256 = @($control.result.results | ForEach-Object { $_.content_sha256 })
        },
        [ordered]@{
            arm = $candidate.arm
            tag = $candidate.tag
            role = "candidate physical mixed 5 IQ2 + 1 IQ1_S with GPU plan"
            raw_outputs_path = $candidate.raw_outputs_path
            raw_outputs_sha256 = $candidate.raw_outputs_sha256
            result_path = $candidate.result_path
            result_sha256 = $candidate.result_sha256
            output_sha256 = @($candidate.result.results | ForEach-Object { $_.content_sha256 })
            iq1_s_layer_first = 3
            iq1_s_layer_last = 42
            iq1_s_ram_cache_gib = $Iq1CacheGiB
            mixed_ratio = "5:1 hot-main-to-cold-IQ1"
            mixed_calls = [UInt64]$candidate.result.iq1_s_mixed_calls
            planner_calls = [UInt64]$candidate.result.iq1_s_mixed_gpu_plan_calls
            failures = [UInt64]$candidate.result.iq1_s_mixed_failures + [UInt64]$candidate.result.iq1_s_mixed_gpu_plan_failures + [UInt64]$candidate.result.iq1_s_sidecar_failures
        }
    )
    grading_path = $gradingPath
    grading_sha256 = Get-G95Sha256 $gradingPath
    repetition_flags_policy = "Integrity/determinism diagnostic only; never a quality grade or verdict."
    performance_policy = "Metrics are preserved descriptively; this runner declares no performance or quality winner."
    claim_scope = "One preregistered cyberpunk HTML prompt, capped at 768 tokens and stopped on </html>; no broad lossless/equivalence claim."
    runner_sha256 = Get-G95Sha256 $runnerPath
}
$summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
Write-Host "G95 measurement PASS; human L0-L3 grading is still required"
Write-Host ("G95 summary: " + $summaryPath)
Write-Host ("G95 grading template: " + $gradingPath)
