# G116 control for G115: same learned mask and transport, six IQ2 routes, Q1 disabled.
param(
    [ValidateRange(1, 4000)][int]$MaxTokens = 256,
    [ValidateRange(1.0, 64.0)][double]$ArenaGiB = 28.0,
    [ValidatePattern('^[A-Za-z0-9_-]+$')][string]$Tag = 'g116_iq2_mask_control_28g_safety_n1',
    [ValidateRange(600, 86400)][int]$TimeoutSec = 2400,
    [ValidateRange(0, 3600)][int]$QuiescenceCooldownSec = 30
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$env:GIT_CONFIG_COUNT = '1'
$env:GIT_CONFIG_KEY_0 = 'safe.directory'
$env:GIT_CONFIG_VALUE_0 = $root.Replace('\', '/')
$harness = Join-Path $root 'g7_measure.ps1'
$resultPath = Join-Path $root ('g7_runs\g7_' + $Tag + '_result.json')
$model = 'C:\ds4-models\ds4-2bit.gguf'
$modelSHA = 'efc7ed607ff27076e3e501fc3fefefa33c0ed8cf1eff483a2b7fdc0c2e616668'
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
    '-TimeoutSec', ([string]$TimeoutSec)
)

Write-Host "[g116] IQ2 mask control start tag=$Tag max_tokens=$MaxTokens arena_gib=$ArenaGiB expected_entries=$expectedCandidateEntries"
& powershell.exe @arguments
$exitCode = $LASTEXITCODE
if ($exitCode -ne 0) {
    Write-Host "[g116] harness failed exit=$exitCode"
    exit $exitCode
}
if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
    throw "G116 result missing: $resultPath"
}

$result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
if ([bool]$result.q1_0_sidecar_enabled -or
    [bool]$result.q1_0_dual_sparse_runtime_observed -or
    [bool]$result.q1_0_mixed_cold_one_requested -or
    [UInt64]$result.q1_0_sidecar_route_calls -ne 0 -or
    [UInt64]$result.q1_0_resident_hits -ne 0 -or
    [UInt64]$result.prefill_mass_candidate_entries -ne $expectedCandidateEntries -or
    [int]$result.expert_cache_requested -ne 320 -or
    [string]$result.expert_tiering_requested -ne 'enforce' -or
    -not [bool]$result.split_fused_observed) {
    throw 'G116 IQ2 control contract mismatch'
}

$sample = @($result.results)[0]
Write-Host ('[g116] PASS server_tps=' + $result.server_decode_mean_tokens_per_second +
    ' e2e_tps=' + $sample.tokens_per_second +
    ' mass_coverage=' + $result.prefill_mass_coverage +
    ' candidate_entries=' + $expectedCandidateEntries +
    ' content_sha=' + $sample.content_sha256)
