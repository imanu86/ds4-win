$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$harness = Join-Path $root "g7_measure.ps1"
if (-not (Test-Path -LiteralPath $harness -PathType Leaf)) {
    throw "G7 benchmark receipt lock harness missing: $harness"
}

$tokens = $null
$errors = $null
[Management.Automation.Language.Parser]::ParseFile(
    $harness, [ref]$tokens, [ref]$errors) | Out-Null
if ($errors -and $errors.Count -gt 0) {
    throw "G7 benchmark receipt lock AST parse failed: $($errors[0].Message)"
}

$text = Get-Content -LiteralPath $harness -Raw
foreach ($needle in @(
    '[switch]$AllowBenchmarkVerifiedReceiptReuse',
    'AllowBenchmarkVerifiedReceiptReuse requires GateKind=benchmark',
    'Benchmark verified receipt reuse requires the model receipt',
    'Test-G7SharingViolationProof -Path $model',
    'Test-G7SharingViolationProof -Path $Q1_0ExpertSidecar',
    'Benchmark verified receipt reuse requires active parent-held deny-write/delete locks',
    'benchmark_verified_receipt_lock_proof_required',
    'benchmark_verified_receipt_lock_proof_observed')) {
    if ($text.IndexOf($needle, [StringComparison]::Ordinal) -lt 0) {
        throw "G7 benchmark receipt lock marker missing: $needle"
    }
}

Write-Host "test_g7_benchmark_receipt_lock_static.ps1: PASS"
