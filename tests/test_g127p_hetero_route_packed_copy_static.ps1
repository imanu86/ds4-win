$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$runnerPath = Join-Path $root 'g127p_hetero_route_packed_copy_ab.ps1'
$protocolPath = Join-Path $root 'G127P_HETERO_ROUTE_PACKED_COPY_PROTOCOL.md'
$g127RunnerPath = Join-Path $root 'g127_nested_gpu_join_residual_cache_ab.ps1'
$harnessPath = Join-Path $root 'g7_measure.ps1'
$cudaPath = Join-Path $root 'ds4_cuda.cu'

foreach ($path in @($runnerPath, $protocolPath, $g127RunnerPath,
        $harnessPath, $cudaPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "G127P required file missing: $path"
    }
}

foreach ($path in @($runnerPath, $g127RunnerPath, $harnessPath)) {
    $tokens = $null
    $errors = $null
    [Management.Automation.Language.Parser]::ParseFile(
        $path, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors -and $errors.Count -gt 0) {
        throw "G127P PowerShell parse failed for $path`: $($errors[0].Message)"
    }
}

$runner = Get-Content -LiteralPath $runnerPath -Raw
$protocol = Get-Content -LiteralPath $protocolPath -Raw
$harness = Get-Content -LiteralPath $harnessPath -Raw
$cuda = Get-Content -LiteralPath $cudaPath -Raw

function Require-Text {
    param([string]$Text, [string]$Needle, [string]$Contract)
    if ($Text.IndexOf($Needle, [StringComparison]::Ordinal) -lt 0) {
        throw "G127P contract missing ($Contract): $Needle"
    }
}

foreach ($needle in @(
        '[switch]$RoutePackedCopy',
        'route_packed_copy_requested',
        'route_packed_copy_observed',
        'route_packed_copy_runtime_requested',
        'route_packed_copy_experts',
        'route_packed_copy_submissions',
        'route_packed_copy_bytes',
        'route_packed_copy_legacy_submissions',
        'gpu_resident_routes_miss_experts')) {
    Require-Text $harness $needle 'harness exposed counters'
}

foreach ($needle in @(
        '$gpuRoutesPackedCopySubmissions -ne',
        '(2 * $gpuRoutesPackedCopyExperts)',
        '$gpuRoutesLegacyCopySubmissions -ne 0',
        'heterogeneous packed route accounting did not prove exactly two submissions per expert with no legacy copies')) {
    Require-Text $harness $needle 'harness hetero packed-copy accounting'
}

foreach ($forbidden in @(
        'packed route copy accounting did not prove exclusive packed copies',
        'gate_expert_bytes != down_expert_bytes',
        'down_expert_bytes != gate_expert_bytes',
        'gate_bytes != down_bytes',
        'gate/down layout')) {
    if ($harness.IndexOf($forbidden, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        $cuda.IndexOf($forbidden, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw "G127P stale gate/down equality refusal present: $forbidden"
    }
}

foreach ($needle in @(
        'const uint64_t gate_plane_bytes =',
        'const uint64_t down_plane_bytes =',
        'gate_plane_bytes * 2ull + down_plane_bytes',
        'err = cudaMalloc(&packed_base, (size_t)packed_bytes)',
        'err = cudaHostAlloc((void **)&host_packed_base',
        'err = cudaMalloc((void **)&transient_packed_base',
        'cudaMemcpy2DAsync(dst_gate',
        '(size_t)cache->gate_expert_bytes, 2u',
        'cudaMemcpyAsync(dst_down, host_down',
        'cache->packed_copy_submissions += 2ull;')) {
    Require-Text $cuda $needle 'runtime hetero packed-copy implementation'
}

foreach ($needle in @(
        'g127p_hetero_route_packed_copy_ab_plan_v1',
        'g127p_hetero_route_packed_copy_ab_result_v1',
        'Assert-G127PSafetyReceipt',
        'Get-G127PCurrentBuildContract',
        'base G127 safety receipt is not current-build bound',
        'ds4_g127_nested_gpu_join_residual_cache_safety_v1',
        'full/open routing preserved; no REAP/static/closed masks',
        '-NestedResidualGpuJoinResidualCache',
        '-NestedResidualGpuJoinSafetyReceipt',
        '-ExpectedNestedResidualGpuJoinSafetyReceiptSHA256',
        '-RoutePackedCopy',
        '$submissions -ne (2 * $experts)',
        '$nestedMisses = [UInt64]$Json.nested_residual_vram_misses',
        '$missExperts -lt $nestedMisses',
        '$expectedPackedExperts = $missExperts - $nestedMisses',
        '$expectedPackedExperts -ne $experts',
        'nested_residual_vram_misses',
        'route_packed_copy_legacy_submissions -ne 0',
        'route_packed_copy_legacy_submissions -eq 0',
        '$rows += Read-G127PChildResult -Plan $safetyPlan',
        'foreach ($plan in $benchmarkPlans)',
        'candidate_safety',
        'needs_outlier_extension',
        'threshold_ratio = 1.20',
        'G127P candidate hetero packed-copy gate failed',
        'G127P control packed-copy gate failed')) {
    Require-Text $runner $needle 'runner protocol'
}

foreach ($needle in @(
        'control: G127 residual-cache path',
        'candidate: the same G127 residual-cache path plus `-RoutePackedCopy`',
        'not the older closed/static G74 path',
        'candidate safety n=1',
        'control r1',
        'candidate r1',
        'candidate r2',
        'control r2',
        'control r3',
        'candidate r3',
        'route_packed_copy_submissions == 2 * route_packed_copy_experts',
        'must not receive',
        'the current-build G127 receipt only',
        'Candidate safety is executed and validated',
        'immediately before any benchmark child',
        'validated immediately after it finishes',
        'gpu_resident_routes_miss_experts >= nested_residual_vram_misses',
        'gpu_resident_routes_miss_experts - nested_residual_vram_misses',
        '11373 - 995 = 10378',
        'route_packed_copy_legacy_submissions > 0',
        'No hardcoded expert counts are allowed',
        'Nested residual GPU-join routes are expected to',
        'bypass packed',
        'three exact, uncontaminated benchmark processes per arm',
        'No verdict',
        'is allowed from the safety run or from n=1')) {
    Require-Text $protocol $needle 'protocol doc'
}

foreach ($forbidden in @(
        '-ReapMaskFile',
        'G74',
        'static32',
        'Q1_0ExpertSidecar',
        'Iq1SExpertSidecar')) {
    if ($runner.IndexOf($forbidden, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw "G127P forbidden runner marker present: $forbidden"
    }
}

$dummyReceipt = 'C:\g127p-static\g127-receipt.json'
$dummyReceiptSHA = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
$whatIfOutput = @(& $runnerPath -Tag 'g127p_static_probe' `
    -G127SafetyReceipt $dummyReceipt `
    -ExpectedG127SafetyReceiptSHA256 $dummyReceiptSHA `
    -InterChildCooldownSec 0 -WhatIf)
$whatIfText = $whatIfOutput -join "`n"
foreach ($needle in @(
        '"schema":  "g127p_hetero_route_packed_copy_ab_plan_v1"',
        '"child_count":  7',
        '"arm":  "safety"',
        '"arm":  "control"',
        '"arm":  "candidate"',
        '"gate_kind":  "structural-safety"',
        '"gate_kind":  "benchmark"',
        '"order_position":  1',
        '"order_position":  7',
        '"-NestedResidualGpuJoinResidualCache"',
        '"-NestedResidualGpuJoinSafetyReceipt"',
        '"-ExpectedNestedResidualGpuJoinSafetyReceiptSHA256"',
        '"-RoutePackedCopy"',
        '"-GpuResidentRoutes"',
        '"-RouteNoDefaultSync"',
        '"-ForceOpenRouter"',
        '"64"',
        '"256"')) {
    if ($whatIfText.IndexOf($needle, [StringComparison]::Ordinal) -lt 0) {
        throw "G127P WhatIf output missing marker: $needle"
    }
}

$routePackedCount =
    ([regex]::Matches($whatIfText, [regex]::Escape('"-RoutePackedCopy"'))).Count
if ($routePackedCount -lt 4 -or ($routePackedCount % 4) -ne 0) {
    throw "G127P expected RoutePackedCopy in safety + 3 candidates, got $routePackedCount"
}

$safetyMatch = [regex]::Match(
    $whatIfText,
    '"arm":\s+"safety".*?"arm":\s+"control"',
    [Text.RegularExpressions.RegexOptions]::Singleline)
if (-not $safetyMatch.Success) {
    throw 'G127P WhatIf output missing safety block'
}
$safetyBlock = $safetyMatch.Value
foreach ($needle in @(
        '"-RoutePackedCopy"',
        '"-NestedResidualStructuralN1"',
        '"-NestedResidualVerifyReconstruction"')) {
    if ($safetyBlock.IndexOf($needle, [StringComparison]::Ordinal) -lt 0) {
        throw "G127P safety WhatIf missing marker: $needle"
    }
}
foreach ($forbidden in @(
        '"-NestedResidualGpuJoinSafetyReceipt"',
        '"-ExpectedNestedResidualGpuJoinSafetyReceiptSHA256"',
        '"-AllowNestedResidualBenchmarkSuite"')) {
    if ($safetyBlock.IndexOf($forbidden, [StringComparison]::Ordinal) -ge 0) {
        throw "G127P safety WhatIf unexpectedly has benchmark receipt marker: $forbidden"
    }
}

Write-Output 'test_g127p_hetero_route_packed_copy_static.ps1: PASS'
