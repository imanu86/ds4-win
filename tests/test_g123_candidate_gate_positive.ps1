$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$harness = Join-Path $root "g7_measure.ps1"
$bootstrap = Join-Path $root "g7_harness_bootstrap.ps1"
$model = "C:\ds4-models\ds4-2bit.gguf"
$sidecar = "C:\ds4-models\ds4-nested-residual-layers3-16-29-42.ds4nr"
$tag = "g123_candidate_gate_positive_" +
    [Guid]::NewGuid().ToString("N").Substring(0, 10)

$arguments = @(
    "-GateKind", "benchmark",
    "-Repeats", "1",
    "-Tag", $tag,
    "-ModelPath", $model,
    "-ExpectedModelSHA256",
        "efc7ed607ff27076e3e501fc3fefefa33c0ed8cf1eff483a2b7fdc0c2e616668",
    "-ReuseVerifiedModelReceipt",
    "-AllowBenchmarkVerifiedReceiptReuse",
    "-NestedResidualSidecar", $sidecar,
    "-ExpectedNestedResidualSidecarSHA256",
        "07199bc5503aa6e2dea10f702c1ca9e8f05a5bf466a56cbed031f6a5fca4bdf9",
    "-ExpectedNestedResidualSourceSHA256",
        "efc7ed607ff27076e3e501fc3fefefa33c0ed8cf1eff483a2b7fdc0c2e616668",
    "-ExpectedNestedResidualPayloadSHA256",
        "02c8cb248a8184e365e2e486653484165db39402fd28320ba621fb4fdb3f7bd8",
    "-NestedResidualCacheExperts", "64",
    "-NestedResidualGpuCache",
    "-NestedResidualVerifyReconstruction",
    "-AllowNestedResidualBenchmarkSuite",
    "-OuterNestedResidualBenchmarkProcessCount", "3",
    "-GpuResidentRoutes",
    "-ExpertCacheN", "320",
    "-SplitFused",
    "-QuiescenceProbeOnly",
    "-QuiescenceCooldownSec", "0"
)

$modelLock = $null
$sidecarLock = $null
try {
    $modelLock = [IO.File]::Open(
        $model, [IO.FileMode]::Open,
        [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $sidecarLock = [IO.File]::Open(
        $sidecar, [IO.FileMode]::Open,
        [IO.FileAccess]::Read, [IO.FileShare]::Read)
    & $bootstrap -HarnessPath $harness -RepoRoot $root `
        -HarnessArguments $arguments
    if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
        throw "G123 positive candidate gate probe failed: $LASTEXITCODE"
    }
} finally {
    if ($null -ne $sidecarLock) { $sidecarLock.Dispose() }
    if ($null -ne $modelLock) { $modelLock.Dispose() }
}

Write-Output "test_g123_candidate_gate_positive.ps1: PASS"
