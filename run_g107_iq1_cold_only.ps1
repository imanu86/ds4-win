param(
    [string]$Tag = "g107_iq1_cold_only_fallback_safety_n1",
    [ValidateSet("structural-safety", "benchmark")]
    [string]$GateKind = "structural-safety",
    [ValidateRange(1, 16)]
    [int]$Repeats = 1,
    [ValidateRange(1, 4096)]
    [int]$MaxTokens = 64
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
& (Join-Path $root "g7_measure.ps1") `
    -Tag $Tag `
    -GateKind $GateKind `
    -ModelPath "C:\ds4-models\ds4-2bit.gguf" `
    -ExpectedModelSHA256 "efc7ed607ff27076e3e501fc3fefefa33c0ed8cf1eff483a2b7fdc0c2e616668" `
    -Prompt "Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document." `
    -MaxTokens $MaxTokens `
    -Repeats $Repeats `
    -Context 256 `
    -BudgetGB 2 `
    -ReserveMB 1024 `
    -DynamicArenaGiB 30 `
    -ArenaWrapTrustWorkerChecksum `
    -ArenaWrapSourceParts `
    -ArenaWrapUnlockSourceRanges `
    -ArenaWrapUnlockWaveGiB 4 `
    -DisableQ8F16Cache `
    -EmbedRowStaging `
    -ReapPrefetchThreads 8 `
    -PrefillMassWrap `
    -ComposePrefillMassTiering `
    -ExpertCacheN 320 `
    -ExpertCacheReserveGB 0.125 `
    -ExpertCachePolicy lru `
    -GpuResidentRoutes `
    -RouteNoDefaultSync `
    -SplitFused `
    -ExpertTiering enforce `
    -ExpertTierPolicy mass-lfru `
    -ExpertTierClockCalls 430 `
    -ExpertTierReplacementBudget 32 `
    -ExpertTierMinFrequency 3 `
    -ExpertTierHysteresis 1.25 `
    -Iq1SExpertSidecar "C:\ds4-models\DeepSeek-V4-Flash-IQ1_S-XL.gguf" `
    -ExpectedIq1SExpertSidecarSHA256 "b049d1eb34c068f19ab007b33c22a7d758b578bf2b10d9276e79654f85d35047" `
    -ExpectedIq1SExpertSidecarBytes 61540805344 `
    -ModelIq1SuiteReceiptPath (Join-Path $root "g7_runs\g103_model_iq1_suite.receipt.json") `
    -ExpectedModelIq1SuiteReceiptSHA256 "dda44866e361a0ee75368f005519c54ca66ae6f91f51ed0dd0a9bd18a5535110" `
    -ReuseVerifiedSuiteReceipt `
    -Iq1SLayerFirst 3 `
    -Iq1SLayerLast 42 `
    -Iq1SMixedColdOne `
    -Iq1SColdOnly `
    -Iq1SRamCacheGiB 6 `
    -MinimumAvailableGiB 50 `
    -QuiescenceCooldownSec 10 `
    -RuntimeMinimumAvailableGiB 1 `
    -RuntimeMaximumDiskQueueLength 8 `
    -RuntimeHardMinimumAvailableGiB 4 `
    -RuntimeMaximumPagesOutputPerSecond 512 `
    -RuntimeMinimumPrivateWorkingSetRatio 0.7 `
    -RuntimePrivateWorkingSetMinimumGiB 40 `
    -RuntimeContaminationSamples 3 `
    -TimeoutSec 1800 `
    -ExpectedContentSHA256 "31cbc6504dcb57d42aeff9dbceb3aed943bcb32dae19a2edbf552e9fd2f52eb8"

exit $LASTEXITCODE
