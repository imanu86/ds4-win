$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$safetyRunnerPath =
    Join-Path $root 'g127_nested_gpu_join_residual_cache_safety.ps1'
$abRunnerPath = Join-Path $root 'g127_nested_gpu_join_residual_cache_ab.ps1'
$protocolPath = Join-Path $root `
    'G127_NESTED_GPU_JOIN_RESIDUAL_CACHE_PROTOCOL.md'
$harnessPath = Join-Path $root 'g7_measure.ps1'

foreach ($path in @($safetyRunnerPath, $abRunnerPath, $protocolPath,
        $harnessPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "G127 required file missing: $path"
    }
}

foreach ($path in @($safetyRunnerPath, $abRunnerPath, $harnessPath)) {
    $tokens = $null
    $errors = $null
    [Management.Automation.Language.Parser]::ParseFile(
        $path, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors -and $errors.Count -gt 0) {
        throw "G127 PowerShell parse failed for $path`: $($errors[0].Message)"
    }
}

$safety = Get-Content -LiteralPath $safetyRunnerPath -Raw
$runner = Get-Content -LiteralPath $abRunnerPath -Raw
$protocol = Get-Content -LiteralPath $protocolPath -Raw
$harness = Get-Content -LiteralPath $harnessPath -Raw

function Require-Text {
    param([string]$Text, [string]$Needle, [string]$Contract)
    if ($Text.IndexOf($Needle, [StringComparison]::Ordinal) -lt 0) {
        throw "G127 contract missing ($Contract): $Needle"
    }
}

foreach ($needle in @(
        '[switch]$NestedResidualGpuJoinResidualCache',
        'DS4_NESTED_RESIDUAL_GPU_JOIN_RESIDUAL_CACHE',
        'NestedResidualGpuJoinResidualCache requires NestedResidualGpuJoin and NestedResidualGpuCache',
        '[nested-residual-residual-cache\] result=summary enabled=(\d+) hits=(\d+) misses=(\d+) evictions=(\d+) entries=(\d+) capacity=(\d+) pread_bytes=(\d+) pread_bytes_avoided=(\d+) h2d_bytes=(\d+) cached_join_calls=(\d+) invariant_failures=(\d+)',
        'Nested residual GPU join residual cache requires exactly one summary',
        'Nested residual GPU join residual cache counters are inconsistent',
        'Nested residual GPU join residual cache telemetry appeared while NestedResidualGpuJoinResidualCache was disabled',
        'ds4_g127_nested_gpu_join_residual_cache_safety_v1',
        'Nested residual GPU join residual cache requires a G127 safety receipt',
        'Nested residual GPU join G127 safety receipt contract mismatch',
        'Nested residual GPU join G127 safety result no longer binds to this benchmark',
        'nested_residual_gpu_join_residual_cache_requested',
        'nested_residual_gpu_join_residual_cache_pread_bytes_avoided',
        'nested_residual_gpu_join_residual_cache_cached_join_calls',
        'nested_residual_gpu_join_residual_cache_invariant_failures')) {
    Require-Text $harness $needle 'harness switch/parser/G127 receipt'
}

foreach ($needle in @(
        'g127_nested_gpu_join_residual_cache_safety_plan_v1',
        'ds4_g127_nested_gpu_join_residual_cache_safety_v1',
        'structural_safety_only_no_sota_no_quality_verdict',
        '-GateKind',
        'structural-safety',
        '-NestedResidualStructuralN1',
        '-NestedResidualVerifyReconstruction',
        '-NestedResidualGpuCache',
        '-NestedResidualGpuJoin',
        '-NestedResidualGpuJoinResidualCache',
        '-ComposePrefillMassOpenRouter',
        '-ForceOpenRouter',
        '-DynamicArenaGiB',
        '25.828125',
        '-NestedResidualCacheExperts',
        '64',
        'g7_g125_nested_gpu_join_safety_current_build_clean_20260718T182935501Z_eb824ebedb_receipt.json',
        'ae15a6d3d3bc35e75b46befd8d18d7886f571e47d93561d146ada3ccf20f58fb',
        'nested_residual_gpu_join_residual_cache_entries -gt',
        'nested_residual_gpu_join_residual_cache_capacity',
        'nested_residual_gpu_join_residual_cache_pread_bytes_avoided -eq 0',
        'nested_residual_gpu_join_residual_cache_cached_join_calls -eq 0',
        'nested_residual_gpu_join_residual_cache_invariant_failures -ne 0',
        'nested_residual_gpu_join_cpu_reconstruct_calls -ne 0',
        'nested_residual_gpu_join_native_h2d_bytes -ne 0',
        'moe_overlapped_io_fallbacks -ne 0',
        'fallback marker observed',
        'G127 safety machine-quiescence gate failed',
        'result_sha256',
        'configuration_sha256',
        'executable_sha256',
        'build_manifest_sha256',
        'build_manifest_input_fingerprint_sha256',
        'harness_sha256',
        'bootstrap_sha256',
        'G127_SAFETY_RECEIPT=',
        'G127_SAFETY_RECEIPT_SHA256=')) {
    Require-Text $safety $needle 'current-build structural safety'
}

foreach ($needle in @(
        '[Parameter(Mandatory=$true)]',
        '[string]$G127SafetyReceipt',
        '[string]$ExpectedG127SafetyReceiptSHA256',
        'Assert-G127SafetyReceipt',
        'Get-G127CurrentBuildContract',
        'G127 safety receipt is not from the current build/harness',
        'G127 safety result SHA-256 mismatch',
        'G127 safety/build contract changed before A/B planning',
        'resultPreflight.ready_to_launch',
        'resultContaminationPeak -ne 0',
        'G127 safety result cross-check failed',
        'g127_nested_gpu_join_residual_cache_ab_result_v1',
        'g127_nested_gpu_join_residual_cache_ab_plan_v1',
        'n3_nested_residual_gpu_join_residual_cache_ab',
        '-NestedResidualGpuJoin',
        '-NestedResidualGpuJoinResidualCache',
        '-NestedResidualGpuJoinSafetyReceipt',
        '-ExpectedNestedResidualGpuJoinSafetyReceiptSHA256',
        '$g127SafetyReceiptForChildren',
        '$g127SafetyReceiptSHAForChildren',
        '-NestedResidualGpuCache',
        '-AllowNestedResidualBenchmarkSuite',
        '-OuterNestedResidualBenchmarkProcessCount',
        'nested_residual_gpu_join_residual_cache_entries -gt',
        'nested_residual_gpu_join_residual_cache_capacity',
        'moe_overlapped_io_fallbacks -ne 0',
        'G127 candidate residual-cache contract mismatch',
        'G127 control residual-cache contract mismatch',
        'G127 residual-cache candidate failed transport-reduction gate',
        'candidate_residual_preads',
        'control_residual_preads',
        'candidate_pread_bytes_avoided',
        'g127_safety_result_sha256',
        'g127_safety_configuration_sha256')) {
    Require-Text $runner $needle 'A/B receipt and benchmark contract'
}

foreach ($needle in @(
        'mandatory order',
        'g127_nested_gpu_join_residual_cache_safety.ps1',
        'ds4_g127_nested_gpu_join_residual_cache_safety_v1',
        'G125 remains a hash-pinned historical prerequisite',
        'current executable, build manifest, harness, bootstrap',
        '-NestedResidualVerifyReconstruction',
        'hits > 0',
        'misses > 0',
        'entries <= capacity',
        'pread_bytes_avoided > 0',
        'cached_join_calls > 0',
        'invariant_failures == 0',
        'fallback log markers are zero',
        'machine-quiescence preflight',
        '-G127SafetyReceipt',
        '-ExpectedG127SafetyReceiptSHA256',
        'before constructing or launching',
        'full/open',
        'no REAP/static/closed mask')) {
    Require-Text $protocol $needle 'protocol safety-before-A/B contract'
}

foreach ($forbidden in @(
        '-NestedResidualProfile',
        '-ReapMaskFile',
        'Q1_0ExpertSidecar',
        'Iq1SExpertSidecar')) {
    if ($safety.IndexOf($forbidden, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        $runner.IndexOf($forbidden, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw "G127 forbidden runner marker present: $forbidden"
    }
}
if ($runner.IndexOf('-NestedResidualVerifyReconstruction',
        [StringComparison]::OrdinalIgnoreCase) -ge 0) {
    throw 'G127 A/B must not pay reconstruction verification overhead'
}
if ($safety.IndexOf('-AllowNestedResidualBenchmarkSuite',
        [StringComparison]::OrdinalIgnoreCase) -ge 0) {
    throw 'G127 structural safety must not identify as a benchmark member'
}

$safetyWhatIfOutput = @(& $safetyRunnerPath -Tag 'g127_safety_static_probe' `
    -WhatIf)
$safetyWhatIfText = $safetyWhatIfOutput -join "`n"
foreach ($needle in @(
        '"schema":  "g127_nested_gpu_join_residual_cache_safety_plan_v1"',
        '"n":  1',
        '"-GateKind"',
        '"structural-safety"',
        '"-NestedResidualStructuralN1"',
        '"-NestedResidualVerifyReconstruction"',
        '"-NestedResidualGpuCache"',
        '"-NestedResidualGpuJoin"',
        '"-NestedResidualGpuJoinResidualCache"')) {
    if ($safetyWhatIfText.IndexOf($needle, [StringComparison]::Ordinal) -lt 0) {
        throw "G127 safety WhatIf output missing marker: $needle"
    }
}

$dummyReceipt = 'C:\g127-static\immutable-receipt.json'
$dummyReceiptSHA = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
$abWhatIfOutput = @(& $abRunnerPath -Tag 'g127_ab_static_probe' `
    -G127SafetyReceipt $dummyReceipt `
    -ExpectedG127SafetyReceiptSHA256 $dummyReceiptSHA `
    -InterChildCooldownSec 0 -WhatIf)
$abWhatIfText = $abWhatIfOutput -join "`n"
foreach ($needle in @(
        '"schema":  "g127_nested_gpu_join_residual_cache_ab_plan_v1"',
        '"child_count":  6',
        '"g127_safety_receipt":  "C:\\g127-static\\immutable-receipt.json"',
        '"g127_safety_receipt_sha256":  "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"',
        '"arm":  "control"',
        '"arm":  "candidate"',
        '"order_position":  1',
        '"order_position":  6',
        '"-NestedResidualGpuJoin"',
        '"-NestedResidualGpuJoinResidualCache"',
        '"-NestedResidualGpuJoinSafetyReceipt"',
        '"-ExpectedNestedResidualGpuJoinSafetyReceiptSHA256"',
        '"-NestedResidualGpuCache"',
        '"benchmark"',
        '"64"')) {
    if ($abWhatIfText.IndexOf($needle, [StringComparison]::Ordinal) -lt 0) {
        throw "G127 A/B WhatIf output missing marker: $needle"
    }
}

Write-Output 'test_g127_nested_gpu_join_residual_cache_static.ps1: PASS'
