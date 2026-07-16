# G77 IQ1_S routed-expert sidecar quality A/B (PowerShell 5.1, ASCII).
param(
    [switch]$StaticCheckOnly,
    [switch]$SkipBuild,
    [switch]$Resume
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
$maxTokens = 4000
$context = 8192
$baselineTag = "g77_main_2bit_quality_n3"
$sidecarTag = "g77_iq1_s_quality_n3"
$summaryPath = Join-Path $outdir "g77_iq1_s_quality_ab_result.json"
$gradingPath = Join-Path $outdir "g77_iq1_s_quality_ab_grading.json"
$g76SummaryPath = Join-Path $outdir "g76_iq1_s_sidecar_safety_result.json"

function Get-G77ResultPath([string]$Tag) {
    Join-Path $outdir ("g7_" + $Tag + "_result.json")
}

function Get-G77RawPath([string]$Tag) {
    Join-Path $outdir ("g7_" + $Tag + "_raw_outputs.json")
}

function Get-G77Sha256([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-G77TextSha256([string]$Text) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Assert-G77StaticContract {
    foreach ($path in @($harness, $buildRunner)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "G77 static check failed: missing $path"
        }
    }
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $runnerPath, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        throw ("G77 runner syntax failed: " +
            (($errors | ForEach-Object { $_.Message }) -join " | "))
    }
    if ((Get-G77TextSha256 $prompt) -ne $promptSha256) {
        throw "G77 prompt provenance mismatch"
    }
    if ($repeatsPerArm -lt 3) {
        throw "G77 requires n>=3 per arm"
    }
    $harnessText = Get-Content -LiteralPath $harness -Raw
    foreach ($needle in @(
            '[ValidateSet("benchmark", "structural-safety", "quality")]',
            '$GateKind = "benchmark"',
            'quality_eligible = $qualityEligible',
            'sota_eligible = $sotaEligible',
            'contamination_reason = $contaminationReason',
            '[switch]$AllowNonIdenticalRepeatOutputs',
            'non_identical_repeat_outputs_allowed = [bool]$AllowNonIdenticalRepeatOutputs',
            'iq1_s_sidecar_sha256 = $iq1SSidecarHashAtStart',
            'temperature = 0',
            'think = $false')) {
        if ($harnessText -notmatch [regex]::Escape($needle)) {
            throw "G77 harness lacks required contract: $needle"
        }
    }
}

function Assert-G77SafetyPrerequisite {
    if (-not (Test-Path -LiteralPath $g76SummaryPath -PathType Leaf)) {
        throw "G77 requires a completed G76 structural safety result"
    }
    $g76 = Get-Content -LiteralPath $g76SummaryPath -Raw | ConvertFrom-Json
    if ([string]$g76.status -ne "structural-safety-pass" -or
        [string]$g76.quality_verdict -ne "not-claimed-n1" -or
        [UInt64]$g76.sidecar_bytes -ne $sidecarBytes -or
        [string]$g76.sidecar_sha256 -ine $sidecarSha256 -or
        [UInt64]$g76.failures -ne 0) {
        throw "G77 rejected the G76 structural safety prerequisite"
    }
}

function Invoke-G77Arm {
    param(
        [Parameter(Mandatory=$true)][ValidateSet("main_2bit", "iq1_s_sidecar")][string]$Arm,
        [Parameter(Mandatory=$true)][string]$Tag
    )

    $resultPath = Get-G77ResultPath $Tag
    $rawPath = Get-G77RawPath $Tag
    if ($Resume) {
        if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf) -or
            -not (Test-Path -LiteralPath $rawPath -PathType Leaf)) {
            throw "G77 resume artifact missing for arm=$Arm"
        }
    } else {
        $measureArgs = @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $harness,
            "-Tag", $Tag,
            "-GateKind", "quality",
            "-ModelPath", $model,
            "-ExpectedModelSHA256", $modelSha256,
            "-Prompt", $prompt,
            "-MaxTokens", "$maxTokens",
            "-Repeats", "$repeatsPerArm",
            "-AllowNonIdenticalRepeatOutputs",
            "-Context", "$context",
            "-BudgetGB", "28",
            "-ReserveMB", "1024",
            "-RuntimeReserveMB", "256",
            "-DisableQ8F16Cache",
            "-EmbedRowStaging",
            "-IoQD", "4",
            "-PrefillWaves",
            "-PrefillWaveForceExperts", "32",
            "-PrefillWaveDoubleBuffer",
            "-OverlapSharedFull",
            "-TimeoutSec", "3600"
        )
        if ($Arm -eq "iq1_s_sidecar") {
            $measureArgs += @(
                "-Iq1SExpertSidecar", $sidecar,
                "-ExpectedIq1SExpertSidecarSHA256", $sidecarSha256,
                "-ExpectedIq1SExpertSidecarBytes", "$sidecarBytes"
            )
        }
        Write-Host ("[g77] start arm=" + $Arm + " tag=" + $Tag)
        & powershell.exe @measureArgs
        if ($LASTEXITCODE -ne 0) {
            throw "G77 harness failed: arm=$Arm exit=$LASTEXITCODE"
        }
    }

    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $rawPath -PathType Leaf)) {
        throw "G77 output artifacts missing: arm=$Arm"
    }
    $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    Assert-G77ArmResult -Arm $Arm -Result $result -ResultPath $resultPath -RawPath $rawPath
}

function Assert-G77ArmResult {
    param(
        [Parameter(Mandatory=$true)][ValidateSet("main_2bit", "iq1_s_sidecar")][string]$Arm,
        [Parameter(Mandatory=$true)][object]$Result,
        [Parameter(Mandatory=$true)][string]$ResultPath,
        [Parameter(Mandatory=$true)][string]$RawPath
    )

    if ([string]$Result.gate_kind -ne "quality" -or
        -not [bool]$Result.quality_eligible -or
        -not [bool]$Result.sota_eligible -or
        [int]$Result.server_exit_code -ne 0 -or
        [string]$Result.model_sha256 -ine $modelSha256 -or
        [string]$Result.model_expected_sha256 -ine $modelSha256 -or
        [string]$Result.prompt_sha256 -ine $promptSha256 -or
        [int]$Result.requested_max_tokens -ne $maxTokens -or
        [int]$Result.context_requested -ne $context -or
        -not [bool]$Result.non_identical_repeat_outputs_allowed -or
        [string]$Result.contamination_reason -ne "" -or
        [int]$Result.budget_gb -ne 28 -or
        [int]$Result.reserve_mb -ne 1024 -or
        -not [bool]$Result.q8_f16_cache_disabled -or
        -not [bool]$Result.embed_row_staging_requested -or
        [int]$Result.moe_io_queue_depth -ne 4 -or
        -not [bool]$Result.prefill_waves_requested -or
        [int]$Result.prefill_wave_force_experts_requested -ne 32 -or
        -not [bool]$Result.prefill_wave_double_buffer_requested -or
        -not [bool]$Result.overlap_shared_full_requested -or
        -not [bool]$Result.process_isolation_preflight.ready_to_launch -or
        -not [bool]$Result.system_quiescence_preflight.ready_to_launch -or
        [bool]$Result.system_quiescence_preflight.skipped -or
        @($Result.results).Count -ne $repeatsPerArm) {
        throw "G77 common quality contract mismatch: arm=$Arm"
    }

    foreach ($sample in @($Result.results)) {
        if ([int]$sample.completion_tokens -le 0 -or
            [string]::IsNullOrWhiteSpace([string]$sample.content) -or
            [string]$sample.content_sha256 -notmatch '^[0-9a-fA-F]{64}$') {
            throw "G77 raw output integrity failure: arm=$Arm repeat=$($sample.repeat)"
        }
    }

    if ($Arm -eq "main_2bit") {
        if ([bool]$Result.iq1_s_sidecar_runtime_observed -or
            [string]$Result.iq1_s_sidecar -or
            [UInt64]$Result.iq1_s_sidecar_route_calls -ne 0 -or
            [UInt64]$Result.iq1_s_sidecar_failures -ne 0) {
            throw "G77 baseline was contaminated by the IQ1_S sidecar"
        }
    } else {
        $calls = [UInt64]$Result.iq1_s_sidecar_route_calls
        $slots = [UInt64]$Result.iq1_s_sidecar_route_slots
        $loads = [UInt64]$Result.iq1_s_sidecar_selected_loads
        if (-not [bool]$Result.iq1_s_sidecar_runtime_observed -or
            [string]$Result.iq1_s_sidecar_sha256 -ine $sidecarSha256 -or
            [UInt64]$Result.iq1_s_sidecar_bytes -ne $sidecarBytes -or
            [string]$Result.iq1_s_sidecar_source -ne $sidecarSource -or
            $calls -eq 0 -or $slots -lt $calls -or $loads -ne $calls -or
            [UInt64]$Result.iq1_s_sidecar_failures -ne 0) {
            throw "G77 IQ1_S runtime/provenance contract mismatch"
        }
    }

    [pscustomobject]@{
        arm = $Arm
        tag = [string]$Result.tag
        result_path = $ResultPath
        result_sha256 = Get-G77Sha256 $ResultPath
        raw_outputs_path = $RawPath
        raw_outputs_sha256 = Get-G77Sha256 $RawPath
        result = $Result
    }
}

function Assert-G77MatchedPair([object]$Baseline, [object]$Candidate) {
    foreach ($field in @(
            "head", "executable_sha256", "ds4_cuda_sha256", "ds4_c_sha256",
            "ds4_server_c_sha256", "ds4_gpu_h_sha256", "cmake_sha256",
            "build_manifest_sha256", "build_manifest_input_fingerprint_sha256",
            "harness_sha256", "model_sha256", "prompt_sha256",
            "requested_max_tokens", "context_requested", "budget_gb", "reserve_mb")) {
        if ([string]$Baseline.$field -ne [string]$Candidate.$field) {
            throw "G77 A/B provenance/settings mismatch: field=$field"
        }
    }
}

function New-G77GradeRows([object[]]$Arms) {
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

New-Item -ItemType Directory -Force -Path $outdir | Out-Null
Assert-G77StaticContract
if ($StaticCheckOnly) {
    Write-Host "G77 static contract PASS"
    exit 0
}

Assert-G77SafetyPrerequisite
if (-not $SkipBuild -and -not $Resume) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $buildRunner
    if ($LASTEXITCODE -ne 0) { throw "G77 provenance build failed" }
}

# Keep the only experimental difference equal to the routed-expert source.
$baseline = Invoke-G77Arm -Arm "main_2bit" -Tag $baselineTag
$candidate = Invoke-G77Arm -Arm "iq1_s_sidecar" -Tag $sidecarTag
Assert-G77MatchedPair -Baseline $baseline.result -Candidate $candidate.result

$gradeRows = @(New-G77GradeRows @($baseline, $candidate))
$grading = [ordered]@{
    schema = "g77_iq1_s_quality_grading_v1"
    generated_utc = [DateTime]::UtcNow.ToString("o")
    status = "awaiting-recorded-human-grades"
    grading_required = $true
    scale = [ordered]@{
        L0 = "Unusable, incoherent, corrupt, or does not address the task."
        L1 = "Partially relevant but materially broken or incomplete."
        L2 = "Mostly correct and usable with meaningful defects."
        L3 = "Complete, coherent, and functionally satisfies the prompt."
    }
    instructions = @(
        "Inspect every preserved raw output and record one L0-L3 grade per row.",
        "Record grader identity, UTC timestamp, and notes for every grade.",
        "Do not infer a grade from output hashes, repetition flags, throughput, or token counts.",
        "Do not issue an arm-level verdict until all rows have recorded grades."
    )
    samples = $gradeRows
}
$grading | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $gradingPath -Encoding UTF8

$summary = [ordered]@{
    schema = "g77_iq1_s_quality_ab_v1"
    measured_utc = [DateTime]::UtcNow.ToString("o")
    status = "measurement-complete-grading-required"
    gate_kind = "quality"
    quality_claim_allowed = $false
    quality_verdict = "pending-recorded-human-l0-l3-grading"
    verdict_source_required = "recorded-human-l0-l3-grades-only"
    automatic_quality_verdict = $false
    repeats_per_arm = $repeatsPerArm
    n_requirement_satisfied = ($repeatsPerArm -ge 3)
    temperature = 0
    think = $false
    prompt = $prompt
    prompt_sha256 = $promptSha256
    max_tokens = $maxTokens
    context = $context
    non_identical_repeat_outputs_allowed = $true
    contamination_reason = ""
    main_model = [ordered]@{
        path = $model
        expected_sha256 = $modelSha256
        observed_sha256 = [string]$baseline.result.model_sha256
    }
    sidecar = [ordered]@{
        path = $sidecar
        bytes = $sidecarBytes
        source = $sidecarSource
        source_repository = $sidecarSourceRepository
        expected_sha256 = $sidecarSha256
        observed_sha256 = [string]$candidate.result.iq1_s_sidecar_sha256
        quantization_layout = [string]$candidate.result.iq1_s_sidecar_quantization_layout
        imatrix_provenance = [string]$candidate.result.iq1_s_sidecar_imatrix_provenance
    }
    common_settings = [ordered]@{
        budget_gb = 28
        reserve_mb = 1024
        runtime_reserve_mb = 256
        q8_f16_cache = "disabled"
        embed_row_staging = $true
        io_qd = 4
        prefill_waves = $true
        prefill_wave_force_experts = 32
        prefill_wave_double_buffer = $true
        overlap_shared_full = $true
        system_quiescence_required = $true
    }
    arms = @(
        [ordered]@{
            arm = $baseline.arm
            tag = $baseline.tag
            raw_outputs_path = $baseline.raw_outputs_path
            raw_outputs_sha256 = $baseline.raw_outputs_sha256
            result_path = $baseline.result_path
            result_sha256 = $baseline.result_sha256
            output_sha256 = @($baseline.result.results | ForEach-Object { $_.content_sha256 })
        },
        [ordered]@{
            arm = $candidate.arm
            tag = $candidate.tag
            raw_outputs_path = $candidate.raw_outputs_path
            raw_outputs_sha256 = $candidate.raw_outputs_sha256
            result_path = $candidate.result_path
            result_sha256 = $candidate.result_sha256
            output_sha256 = @($candidate.result.results | ForEach-Object { $_.content_sha256 })
        }
    )
    grading_path = $gradingPath
    grading_sha256 = Get-G77Sha256 $gradingPath
    repetition_flags_policy = "Integrity/determinism diagnostic only; never a quality grade or verdict."
    performance_policy = "Metrics are preserved descriptively; this runner declares no performance winner."
    claim_scope = "One preregistered cyberpunk HTML prompt; no broad lossless/equivalence claim."
    runner_sha256 = Get-G77Sha256 $runnerPath
}
$summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
Write-Host "G77 measurement PASS; human L0-L3 grading is still required"
Write-Host ("G77 summary: " + $summaryPath)
Write-Host ("G77 grading template: " + $gradingPath)
