$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$runnerPath = Join-Path $root 'g125_nested_gpu_join_safety.ps1'
$harnessPath = Join-Path $root 'g7_measure.ps1'
$docPath = Join-Path $root 'G125_NESTED_GPU_JOIN_PROTOCOL.md'

foreach ($path in @($runnerPath, $harnessPath, $docPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "G125 required file missing: $path"
    }
}

foreach ($path in @($runnerPath, $harnessPath)) {
    $tokens = $null
    $errors = $null
    [Management.Automation.Language.Parser]::ParseFile(
        $path, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors -and $errors.Count -gt 0) {
        throw "G125 PowerShell parse failed for $path`: $($errors[0].Message)"
    }
}

$runner = Get-Content -LiteralPath $runnerPath -Raw
$harness = Get-Content -LiteralPath $harnessPath -Raw
$doc = Get-Content -LiteralPath $docPath -Raw

function Require-Text {
    param([string]$Text, [string]$Needle, [string]$Contract)
    if ($Text.IndexOf($Needle, [StringComparison]::Ordinal) -lt 0) {
        throw "G125 contract missing ($Contract): $Needle"
    }
}

foreach ($needle in @(
        '[switch]$NestedResidualGpuJoin',
        '$env:DS4_NESTED_RESIDUAL_GPU_JOIN = "1"',
        'Remove-Item Env:\DS4_NESTED_RESIDUAL_GPU_JOIN',
        'nested_residual_gpu_join_requested',
        'nested_residual_gpu_join_observed',
        'nested_residual_gpu_join_calls',
        'nested_residual_gpu_join_blocks',
        'nested_residual_gpu_join_base_h2d_bytes',
        'nested_residual_gpu_join_residual_h2d_bytes',
        'nested_residual_gpu_join_native_h2d_bytes',
        'nested_residual_gpu_join_seconds',
        'nested_residual_gpu_join_wait_calls',
        'nested_residual_gpu_join_wait_seconds',
        'nested_residual_gpu_join_verify_seconds',
        'gpu_join_wait_calls',
        'gpu_join_wait_seconds',
        'gpu_join_verify_seconds',
        'nested_residual_gpu_join_verify_calls',
        'nested_residual_gpu_join_verify_bytes',
        'nested_residual_gpu_join_verify_mismatches',
        'nested_residual_gpu_join_failures',
        'nested_residual_gpu_join_cpu_reconstruct_calls',
        'Get-G7NestedResidualGpuJoinValue',
        'gpu_join_$name',
        'nested_residual_$name',
        'nested_residual_gpu_join_$name',
        '$NestedResidualGpuJoin) {',
        '$nestedResidualVramHostFills -ne 0',
        '$nestedResidualVramHostBytes -ne 0',
        '$nestedResidualVramH2DBytes -ne',
        '$nestedResidualVramMisses * [UInt64]7077888',
        'Nested residual GPU-cache GPU-join counters are inconsistent',
        'telemetry appeared while NestedResidualGpuJoin was disabled')) {
    Require-Text $harness $needle 'harness parser/output'
}

foreach ($needle in @(
        'Get-G125ExpectedContentSHA',
        'g123_equal_host_budget_expected_output.json',
        '4a9fa0d8d6dcee288a5b3e63903c3a978ddbce4a6e517aaf28c83f139aad793b',
        'ds4_g123_expected_output_receipt_v1',
        'pass_n3_exact_full_open',
        'expected_output_provenance_only',
        '4af183d77f7f9b31c4808e5129261528bb397c68da4dd58677ad1df5ca4ab8cb',
        '$json.prompt -ne $prompt',
        '$json.prompt_sha256 -ne $promptSHA',
        '$json.model_sha256 -ne $modelSHA',
        '$json.sidecar_sha256 -ne $sidecarSHA',
        '$json.sidecar_payload_sha256 -ne $payloadSHA',
        '$json.router_semantics -ne ''full/open''',
        '$json.control_count -ne 3',
        '$json.candidate_count -ne 3',
        '$json.all_rows_exact',
        '$json.all_rows_uncontaminated',
        '-GateKind', 'structural-safety',
        '-ExpectedContentSHA256', '$expectedContentSHA',
        '-Repeats', '1',
        '-MaxTokens', '64',
        '-Context', '256',
        '-ReuseVerifiedModelReceipt',
        '-NestedResidualVerifyReconstruction',
        '-NestedResidualGpuCache',
        '-NestedResidualGpuJoin',
        '-NestedResidualStructuralN1',
        '-ComposePrefillMassOpenRouter',
        '-ForceOpenRouter',
        '-GpuResidentRoutes',
        '-RouteNoDefaultSync',
        '-SplitFused',
        'Assert-G125SafetyResult',
        'nested_residual_gpu_cache_requested',
        'nested_residual_vram_runtime_observed',
        'nested_residual_vram_misses -eq 0',
        'nested_residual_vram_host_fills -ne 0',
        'nested_residual_vram_host_bytes -ne 0',
        'nested_residual_vram_h2d_bytes -eq 0',
        'nested_residual_vram_misses * [UInt64]7077888',
        'native_h2d_bytes -ne 0',
        'cpu_reconstruct_calls -ne 0',
        'verify_mismatches -ne 0',
        'nested_residual_gpu_join_verify_seconds',
        '$verifySeconds = [double]$result.nested_residual_gpu_join_verify_seconds',
        'verify_seconds = $verifySeconds',
        'wait_seconds = $joinWaitSeconds',
        'gpu_join_wait_seconds = $joinWaitSeconds',
        'timers may overlap and must not be summed into a claim',
        'verification_overhead_seconds',
        'pass_structural_n1_no_performance_or_quality_verdict',
        'schema = ''g125_nested_gpu_join_safety_plan_v1''',
        'schema = ''ds4_g125_nested_gpu_join_safety_v1''')) {
    Require-Text $runner $needle 'runner contract'
}

foreach ($needle in @(
        'n=1',
        'No SOTA verdict',
        'No quality verdict',
        'DS4_NESTED_RESIDUAL_GPU_JOIN=1',
        '-NestedResidualGpuCache',
        'Nested residual GPU cache requested and observed',
        'VRAM route misses are greater than zero',
        'host fills and host bytes are zero',
        'misses * 7077888',
        'native_h2d_bytes == 0',
        'cpu_reconstruct_calls == 0',
        'gpu_join_wait_calls',
        'gpu_join_wait_seconds',
        'gpu_join_verify_seconds',
        'nested_residual_gpu_join_verify_seconds',
        'enqueue-side',
        'scratch/event completion pressure',
        'must not be summed into a performance claim',
        'must not derive verification overhead from',
        'nested_residual_profile.verify_seconds',
        'n >= 3',
        'Exactness and quality are not inferred',
        'verification overhead')) {
    Require-Text $doc $needle 'protocol doc'
}

foreach ($forbidden in @(
        'Start-Process',
        '.\ds4',
        './ds4',
        'ds4.exe',
        '-Repeats'', ''3',
        '-GateKind'', ''benchmark',
        '-AllowNestedResidualBenchmarkSuite',
        '-ReapMaskFile',
        'Q1_0',
        'Iq1S')) {
    if ($runner.IndexOf($forbidden, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw "G125 forbidden runner marker present: $forbidden"
    }
}

if ($runner.IndexOf(
        'fd6c4522975a71e252b90199d49cfe3236310e2a7285dc0fc4d0e9d0e4885510',
        [StringComparison]::OrdinalIgnoreCase) -ge 0) {
    throw 'G125 runner must resolve expected content SHA from G123/G124 artifacts, not hard-code it'
}
if ($runner.IndexOf(
        'nested_residual_profile.verify_seconds',
        [StringComparison]::OrdinalIgnoreCase) -ge 0) {
    throw 'G125 runner must use nested_residual_gpu_join_verify_seconds, not CPU profile verify seconds'
}
if ($runner.IndexOf(
        'Sort-Object LastWriteTime',
        [StringComparison]::OrdinalIgnoreCase) -ge 0) {
    throw 'G125 runner must not select provenance by newest-file timestamp'
}

$whatIfOutput = @(& $runnerPath -Tag 'g125_static_probe' -WhatIf)
$whatIfText = $whatIfOutput -join "`n"
foreach ($needle in @(
        '"schema":  "g125_nested_gpu_join_safety_plan_v1"',
        '"status":  "whatif_no_runtime"',
        '"n":  1',
        '"claim_scope":  "structural_safety_only_no_sota_no_quality_verdict"',
        '"-NestedResidualGpuJoin"',
        '"-NestedResidualVerifyReconstruction"',
        '"-GateKind"',
        '"structural-safety"',
        '"-Repeats"',
        '"1"')) {
    if ($whatIfText.IndexOf($needle, [StringComparison]::Ordinal) -lt 0) {
        throw "G125 WhatIf output missing marker: $needle"
    }
}

Write-Output 'test_g125_nested_gpu_join_static.ps1: PASS'
