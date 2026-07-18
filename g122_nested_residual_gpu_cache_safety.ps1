# G122 nested-residual GPU-cache structural safety.
# Candidate-only runner; n=1 exactness, no benchmark claim.
param(
    [ValidatePattern('^[A-Za-z0-9_-]+$')]
    [string]$Tag = "g122_nested_residual_gpu_cache_safety",
    [ValidateRange(600, 7200)][int]$TimeoutSec = 2400,
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$harness = Join-Path $root "g7_measure.ps1"
$bootstrap = Join-Path $root "g7_harness_bootstrap.ps1"
$model = "C:\ds4-models\ds4-2bit.gguf"
$modelSHA = "efc7ed607ff27076e3e501fc3fefefa33c0ed8cf1eff483a2b7fdc0c2e616668"
$sidecar = "C:\ds4-models\ds4-nested-residual-layers3-16-29-42.ds4nr"
$sidecarReceipt = "C:\ds4-models\ds4-nested-residual-layers3-16-29-42.receipt.json"
$sidecarBytes = [UInt64]3221226880
$sidecarSHA = "07199bc5503aa6e2dea10f702c1ca9e8f05a5bf466a56cbed031f6a5fca4bdf9"
$payloadSHA = "02c8cb248a8184e365e2e486653484165db39402fd28320ba621fb4fdb3f7bd8"
$expectedContentSHA = "fd6c4522975a71e252b90199d49cfe3236310e2a7285dc0fc4d0e9d0e4885510"
$prompt = "Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document."
$promptSHA = "38f6ec5ee5403f59dd2418eb5d9a5a94a0f0da19df015060383bb1ae46003bb6"

foreach ($path in @($harness, $bootstrap, $model, "$model.receipt.json",
                     $sidecar, $sidecarReceipt)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "G122 required file missing: $path"
    }
}
if ([UInt64](Get-Item -LiteralPath $sidecar).Length -ne $sidecarBytes) {
    throw "G122 sidecar size mismatch"
}
$sha = [Security.Cryptography.SHA256]::Create()
try {
    $promptBytes = [Text.Encoding]::UTF8.GetBytes($prompt)
    $observedPromptSHA = [BitConverter]::ToString(
        $sha.ComputeHash($promptBytes)).Replace("-", "").ToLowerInvariant()
} finally {
    $sha.Dispose()
}
if ($observedPromptSHA -ne $promptSHA) {
    throw "G122 prompt SHA-256 mismatch"
}

$sidecarLock = [IO.File]::Open(
    $sidecar, [IO.FileMode]::Open, [IO.FileAccess]::Read,
    [IO.FileShare]::Read)
try {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $observedSidecarSHA = [BitConverter]::ToString(
            $sha.ComputeHash($sidecarLock)).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
    if ($observedSidecarSHA -ne $sidecarSHA) {
        throw "G122 sidecar SHA-256 mismatch"
    }

    $harnessArgs = @(
        "-GateKind", "structural-safety",
        "-ModelPath", $model, "-ExpectedModelSHA256", $modelSHA,
        "-ReuseVerifiedModelReceipt", "-Prompt", $prompt,
        "-ExpectedContentSHA256", $expectedContentSHA,
        "-MaxTokens", "64", "-Repeats", "1", "-Context", "256",
        "-BudgetGB", "2", "-ReserveMB", "1024",
        "-DynamicArenaGiB", "25.828125",
        "-ArenaWrapTrustWorkerChecksum", "-ArenaWrapSourceParts",
        "-ArenaWrapUnlockSourceRanges", "-ArenaWrapUnlockWaveGiB", "4",
        "-DisableQ8F16Cache", "-EmbedRowStaging",
        "-ReapPrefetchThreads", "8", "-PrefillMassWrap",
        "-ComposePrefillMassTiering", "-ComposePrefillMassOpenRouter",
        "-ForceOpenRouter", "-ComposePrefillMassReserveSlots", "32",
        "-ExpertCacheN", "320", "-ExpertCacheReserveGB", "0.125",
        "-ExpertCachePolicy", "lru", "-GpuResidentRoutes",
        "-RouteNoDefaultSync", "-ExpertTiering", "enforce",
        "-ExpertTierPolicy", "mass-lfru", "-ExpertTierClockCalls", "430",
        "-ExpertTierReplacementBudget", "32",
        "-ExpertTierMinFrequency", "3", "-ExpertTierHysteresis", "1.25",
        "-SplitFused", "-RuntimeMinimumAvailableGiB", "1",
        "-RuntimeMaximumDiskQueueLength", "8",
        "-RuntimeContaminationSamples", "3", "-QuiescenceCooldownSec", "10",
        "-TimeoutSec", ([string]$TimeoutSec), "-Tag", $Tag,
        "-NestedResidualSidecar", $sidecar,
        "-ExpectedNestedResidualSidecarSHA256", $sidecarSHA,
        "-ExpectedNestedResidualSourceSHA256", $modelSHA,
        "-ExpectedNestedResidualPayloadSHA256", $payloadSHA,
        "-NestedResidualCacheExperts", "64",
        "-NestedResidualStructuralN1", "-NestedResidualGpuCache",
        "-NestedResidualVerifyReconstruction"
    )

    $bootstrapArgs = @{
        HarnessPath = $harness
        RepoRoot = $root
        UniqueTagSuffix = $true
        HarnessArguments = $harnessArgs
    }
    if ($WhatIf) {
        $bootstrapArgs.WhatIf = $true
    }

    Write-Host "[g122] phase=candidate representation=nested-base-plus-exact-residual route-cache=gpu-resident"
    & $bootstrap @bootstrapArgs
} finally {
    $sidecarLock.Dispose()
}
