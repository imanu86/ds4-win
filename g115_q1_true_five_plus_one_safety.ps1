# G115 resident true 5+1 safety: five IQ2 routes plus lowest-weight Q1 route.
param(
    [ValidateRange(1, 4000)][int]$MaxTokens = 256,
    [ValidateRange(1.0, 64.0)][double]$ArenaGiB = 30.0,
    [ValidatePattern('^[A-Za-z0-9_-]+$')][string]$Tag = 'g115_q1_true_five_plus_one_safety_n1',
    [ValidateRange(600, 86400)][int]$TimeoutSec = 2400,
    [ValidateRange(0, 3600)][int]$QuiescenceCooldownSec = 30
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$harness = Join-Path $root 'g7_measure.ps1'
$resultPath = Join-Path $root ('g7_runs\g7_' + $Tag + '_result.json')
$model = 'C:\ds4-models\ds4-2bit.gguf'
$modelSHA = 'efc7ed607ff27076e3e501fc3fefefa33c0ed8cf1eff483a2b7fdc0c2e616668'
$q1 = 'C:\ds4-models\ds4-q1-layers0-42-derived.gguf'
$q1SHA = '05040393f5e94bf054a593e4d2d021ff44a6f446f2328a75e4f833a1fbe20207'
$q1Bytes = [UInt64]39048344416
$slotBytes = [UInt64]7077888
$expectedCandidateEntries = [UInt64][math]::Floor(($ArenaGiB * 1GB) / $slotBytes)
$prompt = 'Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document.'

$arguments = @(
    '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $harness,
    '-Tag', $Tag, '-GateKind', 'structural-safety',
    '-ModelPath', $model, '-ExpectedModelSHA256', $modelSHA,
    '-ReuseVerifiedModelReceipt', '-Prompt', $prompt,
    '-MaxTokens', ([string]$MaxTokens), '-Repeats', '1',
    '-Context', '8192', '-PrefillChunk', '256',
    '-BudgetGB', '2', '-ReserveMB', '1024',
    '-DynamicArenaGiB', $ArenaGiB.ToString('0.###', [Globalization.CultureInfo]::InvariantCulture),
    '-ArenaWrapTrustWorkerChecksum',
    '-ArenaWrapSourceParts', '-ArenaWrapUnlockSourceRanges',
    '-ArenaWrapUnlockWaveGiB', '4', '-DisableQ8F16Cache',
    '-EmbedRowStaging', '-ReapPrefetchThreads', '8',
    '-PrefillMassWrap', '-ComposePrefillMassTiering',
    '-ExpertCacheN', '320', '-ExpertCacheReserveGB', '0.125',
    '-ExpertCachePolicy', 'lru', '-GpuResidentRoutes',
    '-RouteNoDefaultSync', '-SplitFused',
    '-ExpertTiering', 'enforce', '-ExpertTierPolicy', 'mass-lfru',
    '-ExpertTierClockCalls', '430', '-ExpertTierReplacementBudget', '32',
    '-ExpertTierMinFrequency', '3', '-ExpertTierHysteresis', '1.25',
    '-RuntimeMinimumAvailableGiB', '1',
    '-RuntimeMaximumDiskQueueLength', '8',
    '-RuntimeContaminationSamples', '3',
    '-QuiescenceCooldownSec', ([string]$QuiescenceCooldownSec),
    '-TimeoutSec', ([string]$TimeoutSec),
    '-Q1_0ExpertSidecar', $q1,
    '-ExpectedQ1_0ExpertSidecarSHA256', $q1SHA,
    '-ExpectedQ1_0ExpertSidecarBytes', ([string]$q1Bytes),
    '-ReuseVerifiedQ1_0Receipt', '-Q1_0LayerFirst', '0',
    '-Q1_0LayerLast', '42', '-Q1_0SelectedLoad',
    '-Q1_0ResidentArena', '-Q1_0DualArena',
    '-Q1_0DualSparseCompanion', '-Q1_0MixedColdOne'
)

Write-Host "[g115] resident true 5+1 safety start tag=$Tag max_tokens=$MaxTokens arena_gib=$ArenaGiB expected_entries=$expectedCandidateEntries"
& powershell.exe @arguments
$exitCode = $LASTEXITCODE
if ($exitCode -ne 0) {
    Write-Host "[g115] harness failed exit=$exitCode"
    exit $exitCode
}
if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
    throw "G115 result missing: $resultPath"
}

$result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
$mixed = $result.q1_0_mixed
if (-not [bool]$result.q1_0_dual_sparse_runtime_observed -or
    [UInt64]$result.q1_0_dual_sparse_entries -ne $expectedCandidateEntries -or
    [UInt64]$result.q1_0_dual_sparse_publications -ne 1 -or
    [UInt64]$result.q1_0_dual_sparse_failures -ne 0 -or
    -not [bool]$result.q1_0_mixed_cold_one_requested -or
    [int]$result.expert_cache_requested -ne 320 -or
    [string]$result.expert_tiering_requested -ne 'enforce' -or
    [UInt64]$mixed.cold_one_calls -ne [UInt64]$mixed.calls -or
    [UInt64]$mixed.cold_one_hot_routes -ne ([UInt64]$mixed.calls * 5) -or
    [UInt64]$mixed.cold_one_q1_routes -ne [UInt64]$mixed.calls -or
    [UInt64]$mixed.q1_resident -ne [UInt64]$mixed.calls -or
    [UInt64]$mixed.iq2_ssd_bytes -ne 0 -or
    [UInt64]$mixed.failures -ne 0 -or
    [UInt64]$result.q1_0_resident_misses -ne 0 -or
    [UInt64]$result.q1_0_direct_pread_bytes -ne 0) {
    throw 'G115 true 5+1 resident transport contract mismatch'
}

$sample = @($result.results)[0]
Write-Host ('[g115] PASS server_tps=' + $result.server_decode_mean_tokens_per_second +
    ' e2e_tps=' + $sample.tokens_per_second +
    ' arena_gib=' + $ArenaGiB +
    ' candidate_entries=' + $expectedCandidateEntries +
    ' calls=' + $mixed.calls +
    ' iq2_routes=' + $mixed.cold_one_hot_routes +
    ' q1_routes=' + $mixed.cold_one_q1_routes +
    ' content_sha=' + $sample.content_sha256)
