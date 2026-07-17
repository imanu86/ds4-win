$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$runner = Join-Path $root "g102_iq1_combined_quality.ps1"
$harness = Join-Path $root "g7_measure.ps1"
$outdir = Join-Path $root "g7_runs"

function Get-G102TestSnapshot {
    if (-not (Test-Path -LiteralPath $outdir -PathType Container)) {
        return @()
    }
    @(Get-ChildItem -LiteralPath $outdir -Filter "*g102*" -File |
        Sort-Object FullName | ForEach-Object {
            $_.FullName + "|" + $_.Length + "|" + $_.LastWriteTimeUtc.Ticks
        })
}

if (-not (Test-Path -LiteralPath $runner -PathType Leaf)) {
    throw "G102 runner missing: $runner"
}
$tokens = $null
$errors = $null
[Management.Automation.Language.Parser]::ParseFile(
    $runner, [ref]$tokens, [ref]$errors) | Out-Null
if ($errors -and $errors.Count -gt 0) {
    throw "G102 runner AST parse failed: $($errors[0].Message)"
}

$beforeArtifacts = @(Get-G102TestSnapshot)
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

try {
    $receipt = $stdout.Trim() | ConvertFrom-Json
} catch {
    throw "G102 static receipt is not valid JSON: stdout=$stdout stderr=$stderr"
}
if ($receipt.schema -ne "g102_iq1_combined_quality_static_v1" -or
    [bool]$receipt.static_check_only -ne $true -or
    [bool]$receipt.no_build_gpu_or_ds4_launch_in_static_check -ne $true -or
    [int]$receipt.protocol.independent_processes -ne 3 -or
    [int]$receipt.protocol.repeats_per_process -ne 1 -or
    [int]$receipt.protocol.context -ne 8192 -or
    [int]$receipt.protocol.max_tokens -ne 4000 -or
    [int]$receipt.protocol.warmup_max_tokens -ne 64 -or
    [string]$receipt.protocol.stop_sequence -ne "</html>" -or
    [bool]$receipt.protocol.stop_delimiter_preserved -ne $false -or
    [bool]$receipt.protocol.grading_restores_confirmed_stop_delimiter -ne $true -or
    [bool]$receipt.protocol.output_hash_equality_required -ne $false -or
    [int]$receipt.combined_gate.probation_slots -ne 16 -or
    [int]$receipt.combined_gate.min_touches -ne 2 -or
    [math]::Abs([double]$receipt.combined_gate.min_weight - 0.02) -gt 0.000001 -or
    [int]$receipt.combined_gate.request_budget -ne 16 -or
    [int]$receipt.combined_gate.window_calls -ne 40 -or
    [int]$receipt.combined_gate.window_budget -ne 1) {
    throw "G102 static protocol contract mismatch"
}

$harnessText = Get-Content -LiteralPath $harness -Raw
$hasQualityReceipt = $harnessText -match
    '\$AllowQualityVerifiedSuiteReceipt(\s|=|,|\))' -and
    $harnessText -match 'allow_quality_verified_suite_receipt_requested'
$hasOuterCount = $harnessText -match
    '\$OuterQualityProcessCount(\s|=|,|\))' -and
    $harnessText -match 'outer_quality_process_count_requested' -and
    $harnessText -match 'outer-quality-suite-member-pending-aggregate' -and
    $harnessText -match 'outer_quality_member_contract_valid'
if ($hasQualityReceipt -and $hasOuterCount) {
    if ($exitCode -ne 0 -or [bool]$receipt.runnable -ne $true -or
        @($receipt.missing_prerequisites).Count -ne 0) {
        throw "G102 should be statically runnable after both G7 contracts exist"
    }
} else {
    $parameters = @($receipt.missing_prerequisites |
        ForEach-Object { [string]$_.parameter })
    if ($exitCode -eq 0 -or [bool]$receipt.runnable -ne $false -or
        -not ($parameters -contains "-AllowQualityVerifiedSuiteReceipt") -or
        -not ($parameters -contains "-OuterQualityProcessCount 3")) {
        throw "G102 did not fail closed on the two missing G7 contracts"
    }
}

$afterArtifacts = @(Get-G102TestSnapshot)
$afterDs4 = @(Get-Process -Name "ds4_server" -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty Id)
if (($beforeArtifacts -join "`n") -ne ($afterArtifacts -join "`n")) {
    throw "G102 StaticCheckOnly changed G102 artifacts"
}
if (($beforeDs4 -join ",") -ne ($afterDs4 -join ",")) {
    throw "G102 StaticCheckOnly changed DS4 process state"
}

Write-Host "test_g102_static_contract.ps1: PASS"
