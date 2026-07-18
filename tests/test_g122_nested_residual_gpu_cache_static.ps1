$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$measurePath = Join-Path $root "g7_measure.ps1"
$runnerPath = Join-Path $root "g122_nested_residual_gpu_cache_safety.ps1"
$measure = Get-Content -LiteralPath $measurePath -Raw
$runner = Get-Content -LiteralPath $runnerPath -Raw

function Require-Text {
    param([string]$Text, [string]$Needle, [string]$Contract)
    if ($Text.IndexOf($Needle, [StringComparison]::Ordinal) -lt 0) {
        throw "G122 contract missing ($Contract): $Needle"
    }
}

foreach ($needle in @(
        '[switch]$NestedResidualGpuCache',
        '[switch]$NestedResidualStructuralN1',
        'DS4_NESTED_RESIDUAL_GPU_CACHE',
        'NestedResidualGpuCache requires NestedResidualSidecar, GpuResidentRoutes, SplitFused, and NestedResidualCacheExperts >= 1',
        '[nested-residual-vram\] result=summary route_calls=(\d+) hits=(\d+) misses=(\d+) host_fills=(\d+) host_bytes=(\d+) h2d_bytes=(\d+) failures=(\d+)',
        'Nested residual GPU-cache requires exactly one VRAM summary',
        '$nestedResidualVramHostFills -ne $nestedResidualVramMisses',
        '$nestedResidualVramMisses * [UInt64]7077888',
        'nested_residual_vram_raw_summary',
        'nested residual gpu-cache requested/observed/route-calls/hits/misses/host-fills/host-bytes/h2d-bytes/failures')) {
    Require-Text $measure $needle "harness gpu-cache parser"
}

foreach ($needle in @(
        'g7_harness_bootstrap.ps1',
        'UniqueTagSuffix = $true',
        '-NestedResidualGpuCache',
        '-NestedResidualStructuralN1',
        '-NestedResidualCacheExperts", "64"',
        '-DynamicArenaGiB", "25.828125"',
        'fd6c4522975a71e252b90199d49cfe3236310e2a7285dc0fc4d0e9d0e4885510',
        'ds4-nested-residual-layers3-16-29-42.ds4nr',
        '-ComposePrefillMassOpenRouter',
        '-ForceOpenRouter',
        '-GpuResidentRoutes',
        '-SplitFused')) {
    Require-Text $runner $needle "runner G122 candidate contract"
}

$pattern =
    '(?m)^(?:ds4: )?\[nested-residual-vram\] result=summary route_calls=(\d+) hits=(\d+) misses=(\d+) host_fills=(\d+) host_bytes=(\d+) h2d_bytes=(\d+) failures=(\d+)\r?$'
$good = "ds4: [nested-residual-vram] result=summary route_calls=12 hits=7 misses=5 host_fills=5 host_bytes=35389440 h2d_bytes=35389440 failures=0"
$matches = [regex]::Matches($good, $pattern)
if ($matches.Count -ne 1) {
    throw "G122 parser sample did not match exactly once"
}
if ([UInt64]$matches[0].Groups[5].Value -ne
    [UInt64]$matches[0].Groups[3].Value * [UInt64]7077888) {
    throw "G122 parser sample host byte accounting failed"
}
if ([UInt64]$matches[0].Groups[6].Value -ne
    [UInt64]$matches[0].Groups[3].Value * [UInt64]7077888) {
    throw "G122 parser sample H2D byte accounting failed"
}
$two = $good + "`n" + $good
if ([regex]::Matches($two, $pattern).Count -ne 2) {
    throw "G122 parser duplicate-line guard sample failed"
}

Write-Output "test_g122_nested_residual_gpu_cache_static.ps1: PASS"
