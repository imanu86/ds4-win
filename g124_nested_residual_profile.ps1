# G124 causal n=1 profile for the exact nested-residual miss path.
param(
    [ValidatePattern('^[A-Za-z0-9_-]+$')]
    [string]$Tag = 'g124_nested_residual_profile',
    [ValidateRange(600, 7200)][int]$TimeoutSec = 2400,
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$harness = Join-Path $root 'g7_measure.ps1'
$bootstrap = Join-Path $root 'g7_harness_bootstrap.ps1'
$runs = Join-Path $root 'g7_runs'
$suffix = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ') +
    '_' + [Guid]::NewGuid().ToString('N').Substring(0, 10)
$childTag = $Tag + '_' + $suffix
$model = 'C:\ds4-models\ds4-2bit.gguf'
$sidecar = 'C:\ds4-models\ds4-nested-residual-layers3-16-29-42.ds4nr'
$expectedContentSHA = 'fd6c4522975a71e252b90199d49cfe3236310e2a7285dc0fc4d0e9d0e4885510'
$prompt = 'Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document.'

$arguments = @(
    '-GateKind', 'structural-safety',
    '-ModelPath', $model,
    '-ExpectedModelSHA256',
        'efc7ed607ff27076e3e501fc3fefefa33c0ed8cf1eff483a2b7fdc0c2e616668',
    '-ReuseVerifiedModelReceipt',
    '-Prompt', $prompt,
    '-ExpectedContentSHA256', $expectedContentSHA,
    '-MaxTokens', '64',
    '-Repeats', '1',
    '-Context', '256',
    '-BudgetGB', '2',
    '-ReserveMB', '1024',
    '-DynamicArenaGiB', '25.828125',
    '-ArenaWrapTrustWorkerChecksum',
    '-ArenaWrapSourceParts',
    '-ArenaWrapUnlockSourceRanges',
    '-ArenaWrapUnlockWaveGiB', '4',
    '-DisableQ8F16Cache',
    '-EmbedRowStaging',
    '-ReapPrefetchThreads', '8',
    '-PrefillMassWrap',
    '-ComposePrefillMassTiering',
    '-ComposePrefillMassOpenRouter',
    '-ForceOpenRouter',
    '-ComposePrefillMassReserveSlots', '32',
    '-ExpertCacheN', '320',
    '-ExpertCacheReserveGB', '0.125',
    '-ExpertCachePolicy', 'lru',
    '-GpuResidentRoutes',
    '-RouteNoDefaultSync',
    '-ExpertTiering', 'enforce',
    '-ExpertTierPolicy', 'mass-lfru',
    '-ExpertTierClockCalls', '430',
    '-ExpertTierReplacementBudget', '32',
    '-ExpertTierMinFrequency', '3',
    '-ExpertTierHysteresis', '1.25',
    '-SplitFused',
    '-NestedResidualSidecar', $sidecar,
    '-ExpectedNestedResidualSidecarSHA256',
        '07199bc5503aa6e2dea10f702c1ca9e8f05a5bf466a56cbed031f6a5fca4bdf9',
    '-ExpectedNestedResidualSourceSHA256',
        'efc7ed607ff27076e3e501fc3fefefa33c0ed8cf1eff483a2b7fdc0c2e616668',
    '-ExpectedNestedResidualPayloadSHA256',
        '02c8cb248a8184e365e2e486653484165db39402fd28320ba621fb4fdb3f7bd8',
    '-NestedResidualCacheExperts', '64',
    '-NestedResidualGpuCache',
    '-NestedResidualStructuralN1',
    '-NestedResidualVerifyReconstruction',
    '-NestedResidualProfile',
    '-RuntimeMinimumAvailableGiB', '1',
    '-RuntimeMaximumDiskQueueLength', '8',
    '-RuntimeContaminationSamples', '3',
    '-QuiescenceCooldownSec', '10',
    '-TimeoutSec', [string]$TimeoutSec,
    '-Tag', $childTag
)

$bootstrapArguments = @{
    HarnessPath = $harness
    RepoRoot = $root
    HarnessArguments = $arguments
}
if ($WhatIf) {
    $bootstrapArguments.WhatIf = $true
    & $bootstrap @bootstrapArguments
    exit 0
}

& $bootstrap @bootstrapArguments
if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
    throw "G124 child failed with exit code $LASTEXITCODE"
}

$resultPath = Join-Path $runs ('g7_' + $childTag + '_result.json')
if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
    throw "G124 result missing: $resultPath"
}
$result = Get-Content -Raw -LiteralPath $resultPath | ConvertFrom-Json
if (-not $result.nested_residual_profile_requested -or
    -not $result.nested_residual_profile_observed -or
    [string]$result.results[0].content_sha256 -ne $expectedContentSHA -or
    -not [bool]$result.nested_residual_verify_reconstruction -or
    [UInt64]$result.nested_residual_failures -ne 0 -or
    [UInt64]$result.nested_residual_mismatches -ne 0) {
    throw 'G124 exactness/profile contract failed'
}

$profile = $result.nested_residual_profile
$attributed =
    [double]$profile.lookup_seconds +
    [double]$profile.pread_seconds +
    [double]$profile.reconstruct_seconds +
    [double]$profile.verify_seconds +
    [double]$profile.reuse_wait_seconds +
    [double]$profile.host_copy_seconds +
    [double]$profile.h2d_enqueue_seconds +
    [double]$profile.h2d_sync_seconds
$readyWait = [double]$profile.route_ready_wait_seconds
$unattributed = [math]::Max(0.0, $readyWait - $attributed)
$receipt = [ordered]@{
    schema = 'ds4_g124_nested_residual_profile_v1'
    status = 'measured_n1_no_performance_verdict'
    tag = $childTag
    result_path = $resultPath
    exact_content_sha256 = $expectedContentSHA
    verification_mode = 'current output SHA plus runtime reconstruction verify enabled and timed separately'
    profile = $profile
    verify_seconds = [double]$profile.verify_seconds
    verify_bytes = [UInt64]$profile.verify_bytes
    route_ready_wait_seconds = $readyWait
    attributed_worker_seconds = $attributed
    unattributed_worker_seconds = $unattributed
    attributed_fraction = $(if ($readyWait -gt 0) { $attributed / $readyWait } else { 0.0 })
    timing_claim_scope = 'causal profile only; n=1; not SOTA and not an A/B verdict'
}
$receiptPath = Join-Path $runs ('g7_' + $childTag + '_receipt.json')
$receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding UTF8
Write-Output ("G124_PROFILE_RECEIPT=" + $receiptPath)
