$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $root 'ds4_cuda.cu'
$source = Get-Content -Raw $sourcePath
$harness = Get-Content -Raw (Join-Path $root 'g7_measure.ps1')
$runner = Get-Content -Raw (Join-Path $root 'g124_nested_residual_profile.ps1')

$required = @(
    'DS4_NESTED_RESIDUAL_PROFILE'
    '[nested-residual-profile] result=summary enabled=1'
    'profile_lookup_seconds'
    'profile_pread_seconds'
    'profile_reconstruct_seconds'
    'profile_verify_calls'
    'profile_verify_bytes'
    'profile_verify_seconds'
    'profile_reuse_wait_seconds'
    'profile_host_copy_seconds'
    'profile_h2d_enqueue_seconds'
    'profile_h2d_sync_seconds'
    'profile_route_begin_seconds'
    'profile_route_resolve_sync_seconds'
    'profile_route_ready_wait_seconds'
    'profile_h2d_enqueue_calls++'
    'profile_h2d_sync_calls++'
    'profile_verify_calls++'
)

foreach ($needle in $required) {
    if (-not $source.Contains($needle)) {
        throw "G124 static gate missing: $needle"
    }
}

if ([regex]::Matches($source, '\[nested-residual-profile\]').Count -ne 1) {
    throw 'G124 profile must emit one aggregate summary, not per-route logs'
}

$harnessRequired = @(
    '[switch]$NestedResidualProfile'
    '$env:DS4_NESTED_RESIDUAL_PROFILE = "1"'
    'nested_residual_profile_requested'
    'nested_residual_profile_observed'
    'nested_residual_profile = [ordered]@{'
    'verify_calls'
    'verify_bytes'
    'verify_seconds'
    'route_submit_launch_seconds'
    'submit-launch'
)
foreach ($needle in $harnessRequired) {
    if (-not $harness.Contains($needle)) {
        throw "G124 harness gate missing: $needle"
    }
}

$runnerRequired = @(
    "'-NestedResidualVerifyReconstruction'"
    '-not [bool]$result.nested_residual_verify_reconstruction'
    'current output SHA plus runtime reconstruction verify enabled and timed separately'
    '[double]$profile.verify_seconds'
    'verify_bytes'
)
foreach ($needle in $runnerRequired) {
    if (-not $runner.Contains($needle)) {
        throw "G124 runner gate missing: $needle"
    }
}

Write-Output 'G124_NESTED_RESIDUAL_PROFILE_STATIC=PASS'
