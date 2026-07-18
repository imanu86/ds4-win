$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$cuda = Get-Content -LiteralPath (Join-Path $root "ds4_cuda.cu") -Raw
$measure = Get-Content -LiteralPath (Join-Path $root "g7_measure.ps1") -Raw

function Require-Text {
    param([string]$Text, [string]$Needle, [string]$Contract)
    if ($Text.IndexOf($Needle, [StringComparison]::Ordinal) -lt 0) {
        throw "G119 contract missing ($Contract): $Needle"
    }
}

foreach ($needle in @(
        'cudaStreamSynchronize(g_model_upload_stream)',
        'spex_queue != NULL',
        'reason=nested-residual-requires-open-router',
        'nested_skipped_ranked=%u',
        'reason=duplicate layer=%u expert=%u',
        'nested residual refused source fallback',
        'nested residual refused whole-tensor fallback')) {
    Require-Text $cuda $needle "runtime fail-closed"
}

foreach ($needle in @(
        '[string]$ExpectedNestedResidualSidecarSHA256',
        'Nested residual full sidecar SHA-256 mismatch',
        'NestedResidualSidecar must be isolated from Q1_0, IQ1_S, REAP masks, and SPEX',
        '$nestedResidualPreads * [UInt64]3145728',
        '[UInt64]7077888',
        'Nested residual runtime counters are inconsistent')) {
    Require-Text $measure $needle "measurement provenance and accounting"
}

Write-Output "test_g119_nested_residual_static.ps1: PASS"
