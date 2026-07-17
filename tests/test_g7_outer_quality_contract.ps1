$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$harness = Join-Path $root "g7_measure.ps1"

function Invoke-G7ExpectedValidationFailure {
    param(
        [Parameter(Mandatory=$true)][string]$Arguments,
        [Parameter(Mandatory=$true)][string]$ExpectedText
    )
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = "powershell.exe"
    $startInfo.Arguments = ('-NoLogo -NoProfile -ExecutionPolicy Bypass -File "' +
        $harness + '" ' + $Arguments)
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
    $combined = $stdout + "`n" + $stderr
    if ($exitCode -eq 0 -or $combined -notmatch [regex]::Escape($ExpectedText)) {
        throw "Expected validation failure missing: text=$ExpectedText output=$combined"
    }
}

$zeroHash = "0" * 64
$receiptArgs = (
    '-ReuseVerifiedSuiteReceipt ' +
    '-ModelIq1SuiteReceiptPath X:\missing-suite.json ' +
    '-ExpectedModelIq1SuiteReceiptSHA256 ' + $zeroHash + ' ' +
    '-ExpectedModelSHA256 ' + $zeroHash + ' ' +
    '-Iq1SExpertSidecar X:\missing-sidecar.gguf ' +
    '-ExpectedIq1SExpertSidecarSHA256 ' + $zeroHash + ' ' +
    '-ExpectedIq1SExpertSidecarBytes 1')

$beforeDs4 = @(Get-Process -Name "ds4_server" -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty Id)

Invoke-G7ExpectedValidationFailure `
    '-GateKind quality -AllowQualityVerifiedSuiteReceipt -OuterQualityProcessCount 3' `
    'AllowQualityVerifiedSuiteReceipt requires ReuseVerifiedSuiteReceipt'
Invoke-G7ExpectedValidationFailure `
    '-GateKind quality -OuterQualityProcessCount 3' `
    'OuterQualityProcessCount requires AllowQualityVerifiedSuiteReceipt'
Invoke-G7ExpectedValidationFailure `
    (('-GateKind quality -AllowQualityVerifiedSuiteReceipt ' +
      '-OuterQualityProcessCount 3 -Repeats 2 ') + $receiptArgs) `
    'Outer quality suite members require Repeats=1'
Invoke-G7ExpectedValidationFailure `
    (('-GateKind quality -AllowQualityVerifiedSuiteReceipt ' +
      '-OuterQualityProcessCount 2 -Repeats 1 ') + $receiptArgs) `
    'Outer quality suite members require OuterQualityProcessCount >= 3'
Invoke-G7ExpectedValidationFailure `
    (('-GateKind quality -AllowQualityVerifiedSuiteReceipt ' +
      '-OuterQualityProcessCount 3 -Repeats 1 ' +
      '-SkipSystemQuiescencePreflight ') + $receiptArgs) `
    'Outer quality suite members require system quiescence preflight'
Invoke-G7ExpectedValidationFailure `
    (('-GateKind quality -OuterQualityProcessCount 0 -Repeats 1 ') +
        $receiptArgs) `
    'Verified suite receipt reuse is restricted to benchmark and structural-safety gates'

$afterDs4 = @(Get-Process -Name "ds4_server" -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty Id)
if (($beforeDs4 -join ',') -ne ($afterDs4 -join ',')) {
    throw "Outer quality validation test changed DS4 process state"
}

$source = Get-Content -LiteralPath $harness -Raw
foreach ($marker in @(
    'outer-quality-suite-member-pending-aggregate',
    'outer_quality_suite_member',
    'outer_quality_member_contract_valid',
    'outer_quality_aggregate_required')) {
    if ($source -notmatch [regex]::Escape($marker)) {
        throw "Outer quality result marker missing: $marker"
    }
}

Write-Host "test_g7_outer_quality_contract.ps1: PASS"
