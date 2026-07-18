$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$runnerPath = Join-Path $root 'g126_nested_gpu_join_ab.ps1'
$harnessPath = Join-Path $root 'g7_measure.ps1'
$runtimePath = Join-Path $root 'ds4.c'

foreach ($path in @($runnerPath, $harnessPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "G126 required file missing: $path"
    }
    $tokens = $null
    $errors = $null
    [Management.Automation.Language.Parser]::ParseFile(
        $path, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors -and $errors.Count -gt 0) {
        throw "G126 PowerShell parse failed for $path`: $($errors[0].Message)"
    }
}

$runner = Get-Content -LiteralPath $runnerPath -Raw
$harness = Get-Content -LiteralPath $harnessPath -Raw
$runtime = Get-Content -LiteralPath $runtimePath -Raw

function Require-Text {
    param([string]$Text, [string]$Needle, [string]$Contract)
    if ($Text.IndexOf($Needle, [StringComparison]::Ordinal) -lt 0) {
        throw "G126 contract missing ($Contract): $Needle"
    }
}

foreach ($needle in @(
        '[string]$NestedResidualGpuJoinSafetyReceipt = ""',
        '[string]$ExpectedNestedResidualGpuJoinSafetyReceiptSHA256 = ""',
        'DS4_NESTED_RESIDUAL_BENCHMARK_UNVERIFIED',
        'NestedResidualGpuJoin without runtime reconstruction verification',
        'Nested residual GPU join safety receipt contract mismatch',
        'Nested residual GPU join safety result no longer binds to this benchmark configuration',
        '$bytes[0] -eq 0xEF',
        '$bytes[1] -eq 0xBB',
        '$bytes[2] -eq 0xBF',
        '$bytes, $jsonOffset, $bytes.Length - $jsonOffset',
        '$nestedResidualGpuJoinSafetyReceiptValidated = $true',
        'nested_residual_gpu_join_safety_receipt_validated',
        'nested_residual_gpu_join_safety_receipt_sha256')) {
    Require-Text $harness $needle 'harness receipt gate'
}

foreach ($needle in @(
        'DS4_NESTED_RESIDUAL_BENCHMARK_UNVERIFIED',
        'nested_residual_verification_allowed',
        'explicit unverified benchmark gate')) {
    Require-Text $runtime $needle 'runtime unverified benchmark gate'
}

foreach ($needle in @(
        'g126_nested_gpu_join_ab_result_v1',
        'g7_g125_nested_gpu_join_safety_current_build_clean_20260718T182935501Z_eb824ebedb_receipt.json',
        'ae15a6d3d3bc35e75b46befd8d18d7886f571e47d93561d146ada3ccf20f58fb',
        '-NestedResidualGpuJoinSafetyReceipt',
        '-ExpectedNestedResidualGpuJoinSafetyReceiptSHA256',
        '-NestedResidualGpuJoin',
        '-AllowNestedResidualBenchmarkSuite',
        '-OuterNestedResidualBenchmarkProcessCount',
        '-ComposePrefillMassOpenRouter',
        '-ForceOpenRouter',
        '$json.expert_tiering.compose_router_open -ne 1',
        '$json.prefill_mass_wrap_router -ne ''unbiased''',
        '$json.prefill_mass_wrap_mask -ne ''request-scoped-open''',
        '$json.prefill_mass_compose_mask_semantics -ne',
        '$json.nested_residual_gpu_join_safety_receipt_validated',
        '$json.nested_residual_gpu_join_safety_receipt_sha256',
        '$json.nested_residual_gpu_join_verify_calls -ne 0',
        '$json.nested_residual_gpu_join_verify_bytes -ne 0',
        '$json.nested_residual_gpu_join_verify_seconds -ne 0.0',
        '$json.nested_residual_gpu_join_cpu_reconstruct_calls -ne 0',
        'order_position',
        'n3_nested_residual_cpu_join_vs_gpu_join_ab')) {
    Require-Text $runner $needle 'runner contract'
}

foreach ($forbidden in @(
        '-NestedResidualVerifyReconstruction',
        '-NestedResidualProfile',
        '-ReapMaskFile',
        'Q1_0ExpertSidecar',
        'Iq1SExpertSidecar')) {
    if ($runner.IndexOf($forbidden, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw "G126 forbidden runner marker present: $forbidden"
    }
}

$whatIfOutput = @(& $runnerPath -Tag 'g126_static_probe' `
    -InterChildCooldownSec 0 -WhatIf)
$whatIfText = $whatIfOutput -join "`n"
foreach ($needle in @(
        '"schema":  "g126_nested_gpu_join_ab_plan_v1"',
        '"child_count":  6',
        '"order_position":  1',
        '"order_position":  6',
        '"arm":  "cpu_join"',
        '"arm":  "gpu_join"',
        '"-NestedResidualGpuJoinSafetyReceipt"',
        '"-ExpectedNestedResidualGpuJoinSafetyReceiptSHA256"',
        '"ae15a6d3d3bc35e75b46befd8d18d7886f571e47d93561d146ada3ccf20f58fb"',
        '"-GateKind"',
        '"benchmark"',
        '"-Repeats"',
        '"1"')) {
    if ($whatIfText.IndexOf($needle, [StringComparison]::Ordinal) -lt 0) {
        throw "G126 WhatIf output missing marker: $needle"
    }
}

Write-Output 'test_g126_nested_gpu_join_ab_static.ps1: PASS'
