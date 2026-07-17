$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$runner = Join-Path $root "g103_iq1_cold_sota_ab.ps1"
$protocol = Join-Path $root "G103_IQ1_COLD_SOTA_PROTOCOL.md"
$harness = Join-Path $root "g7_measure.ps1"
$outdir = Join-Path $root "g7_runs"

function Get-G103Snapshot {
    if (-not (Test-Path -LiteralPath $outdir -PathType Container)) {
        return @()
    }
    @(Get-ChildItem -LiteralPath $outdir -Filter "*g103*" -File |
        Sort-Object FullName | ForEach-Object {
            $_.FullName + "|" + $_.Length + "|" + $_.LastWriteTimeUtc.Ticks
        })
}

foreach ($path in @($runner, $protocol, $harness)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "G103 required file missing: $path"
    }
}

$tokens = $null
$errors = $null
[Management.Automation.Language.Parser]::ParseFile(
    $runner, [ref]$tokens, [ref]$errors) | Out-Null
if ($errors -and $errors.Count -gt 0) {
    throw "G103 runner AST parse failed: $($errors[0].Message)"
}

$runnerText = Get-Content -LiteralPath $runner -Raw
$protocolText = Get-Content -LiteralPath $protocol -Raw
$harnessText = Get-Content -LiteralPath $harness -Raw

foreach ($needle in @(
    'C:\ds4-models\ds4-2bit.gguf',
    'C:\ds4-models\DeepSeek-V4-Flash-IQ1_S-XL.gguf',
    'efc7ed607ff27076e3e501fc3fefefa33c0ed8cf1eff483a2b7fdc0c2e616668',
    'b049d1eb34c068f19ab007b33c22a7d758b578bf2b10d9276e79654f85d35047',
    '61540805344',
    '38f6ec5ee5403f59dd2418eb5d9a5a94a0f0da19df015060383bb1ae46003bb6',
    '31cbc6504dcb57d42aeff9dbceb3aed943bcb32dae19a2edbf552e9fd2f52eb8',
    '-ReuseVerifiedModelReceipt',
    '-ReuseVerifiedIq1SReceipt',
    '-RuntimeMinimumAvailableGiB',
    '-SplitFused',
    '-Iq1SMixedColdOne',
    '-Iq1SMixedGpuPlan',
    '-Iq1SRamCacheGiB',
    'iq1_s_ram_cache_ssd_bytes',
    'tier.ssd_bytes',
    'mixed or missing provenance',
    'contamination_abort_observed',
    'structural-safety-gate-not-quality-eligible',
    'repeats-less-than-3-not-quality-eligible',
    'Measurement failed before runtime invariant parsing',
    'arena_wrap_unlock_source_ranges_summary_phases',
    'split_fused_hits')) {
    if ($runnerText -notmatch [regex]::Escape($needle) -and
        $protocolText -notmatch [regex]::Escape($needle) -and
        $harnessText -notmatch [regex]::Escape($needle)) {
        throw "G103 required contract text missing: $needle"
    }
}

foreach ($forbiddenArg in @(
    '-Iq1Promotion',
    '-ComposePrefillMassOpenRouter',
    '-ComposePrefillMassReserveSlots',
    '-RoutePackedCopy',
    '-Iq1SPackedH2D',
    '-Iq1SVramCachePerLayer')) {
    if ($runnerText -match [regex]::Escape('"' + $forbiddenArg + '"') -or
        $runnerText -match [regex]::Escape("'" + $forbiddenArg + "'")) {
        throw "G103 runner enables forbidden argument: $forbiddenArg"
    }
}

if ($runnerText -match 'D:\\') {
    throw "G103 runner must not reference D:"
}

$candidateArgFunc = [regex]::Match(
    $runnerText,
    'function New-G103MeasureArgs[\s\S]+?function Invoke-G103Arm')
if (-not $candidateArgFunc.Success) {
    throw "G103 could not inspect New-G103MeasureArgs"
}
$candidateBlock = $candidateArgFunc.Value
if ($candidateBlock -notmatch '\$Arm -eq "control"[\s\S]+?-ExpectedContentSHA256' -or
    $candidateBlock -match '\$Arm -eq "candidate"[\s\S]+?-ExpectedContentSHA256') {
    throw "G103 ExpectedContentSHA256 must be control-only"
}

$invokeArmFunc = [regex]::Match(
    $runnerText,
    'function Invoke-G103Arm[\s\S]+?function Assert-G103CommonG73Contract')
if (-not $invokeArmFunc.Success -or
    $invokeArmFunc.Value -notmatch '& powershell\.exe @args \| Out-Host') {
    throw "G103 child stdout must not contaminate the row pipeline"
}

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
    if ($harnessText -notmatch ("\$" + [regex]::Escape($parameter) +
        "(\s|=|,|\))")) {
        throw "G103 harness lacks required parameter: -$parameter"
    }
}

$beforeArtifacts = @(Get-G103Snapshot)
$beforeDs4 = @(Get-Process -Name "ds4_server" -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty Id)

$startInfo = New-Object Diagnostics.ProcessStartInfo
$startInfo.FileName = "powershell.exe"
$startInfo.Arguments = ('-NoLogo -NoProfile -ExecutionPolicy Bypass -File "' +
    $runner + '" -StaticCheckOnly')
$startInfo.UseShellExecute = $false
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
$process = [Diagnostics.Process]::Start($startInfo)
$stdoutTask = $process.StandardOutput.ReadToEndAsync()
$stderrTask = $process.StandardError.ReadToEndAsync()
$process.WaitForExit()
$stdout = $stdoutTask.Result
$stderr = $stderrTask.Result
$exitCode = $process.ExitCode
$process.Dispose()

if ($exitCode -ne 0) {
    throw "G103 StaticCheckOnly failed: stdout=$stdout stderr=$stderr"
}
try {
    $receipt = $stdout.Trim() | ConvertFrom-Json
} catch {
    throw "G103 static receipt is not valid JSON: stdout=$stdout stderr=$stderr"
}

if ($receipt.schema -ne "g103_iq1_cold_sota_ab_static_v1" -or
    [bool]$receipt.static_check_only -ne $true -or
    [bool]$receipt.no_model_presence_required -ne $true -or
    [bool]$receipt.no_build_gpu_or_ds4_launch_in_static_check -ne $true -or
    [bool]$receipt.safety_only_supported -ne $true -or
    [int]$receipt.protocol.independent_processes_per_arm -ne 3 -or
    [string]$receipt.protocol.control_expected_content_sha256 -ne
        "31cbc6504dcb57d42aeff9dbceb3aed943bcb32dae19a2edbf552e9fd2f52eb8" -or
    [string]$receipt.protocol.candidate_expected_content_sha256 -ne "" -or
    [bool]$receipt.protocol.candidate_requires_valid_finished_runtime_clean -ne
        $true -or
    [bool]$receipt.protocol.candidate_requires_intra_arm_determinism_n3 -ne
        $true -or
    [double]$receipt.common_config.runtime_minimum_available_gib -ne 1.0 -or
    [double]$receipt.candidate_config.iq1_s_ram_cache_gib -ne 0.5 -or
    [bool]$receipt.common_config.suite_receipt -ne $true -or
    [string]$receipt.common_config.suite_receipt_path -notmatch
        'g103_model_iq1_suite\.receipt\.json$' -or
    [bool]$receipt.candidate_config.iq1_promotion -ne $false -or
    [bool]$receipt.candidate_config.route_packed_copy -ne $false -or
    [bool]$receipt.candidate_config.iq1_s_packed_h2d -ne $false -or
    [bool]$receipt.candidate_config.iq1_s_vram_cache -ne $false -or
    [bool]$receipt.candidate_config.compose_prefill_mass_open_router -ne
        $false -or
    [int]$receipt.candidate_config.compose_prefill_mass_reserve_slots -ne 0) {
    throw "G103 static receipt contract mismatch"
}

$afterArtifacts = @(Get-G103Snapshot)
$afterDs4 = @(Get-Process -Name "ds4_server" -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty Id)
if (($beforeArtifacts -join "`n") -ne ($afterArtifacts -join "`n")) {
    throw "G103 StaticCheckOnly changed G103 artifacts"
}
if (($beforeDs4 -join ",") -ne ($afterDs4 -join ",")) {
    throw "G103 StaticCheckOnly changed DS4 process state"
}

Write-Host "test_g103_static_contract.ps1: PASS"
