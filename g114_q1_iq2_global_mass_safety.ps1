# G114 Q1 base plus global-mass exact IQ2 VRAM seed safety (PowerShell 5.1, ASCII).
param(
    [ValidateRange(1, 4000)][int]$MaxTokens = 256,
    [ValidateRange(40, 512)][int]$SeedTotal = 320,
    [ValidateRange(0, 12)][int]$FloorPerLayer = 4,
    [ValidateRange(0.0, 1.0)][double]$CacheReserveGB = 0.0,
    [ValidatePattern('^[A-Za-z0-9_-]+$')][string]$Tag = "g114_q1_iq2_global_mass_safety_n1",
    [ValidateRange(600, 86400)][int]$TimeoutSec = 1800,
    [ValidateRange(0, 3600)][int]$QuiescenceCooldownSec = 30
)

$ErrorActionPreference = "Stop"
if ($FloorPerLayer * 40 -gt $SeedTotal) {
    throw "FloorPerLayer exceeds SeedTotal"
}
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$harness = Join-Path $root "g7_measure.ps1"
$resultPath = Join-Path $root ("g7_runs\g7_" + $Tag + "_result.json")
$rawPath = Join-Path $root ("g7_runs\g7_" + $Tag + "_raw_outputs.json")
$model = "C:\ds4-models\ds4-2bit.gguf"
$modelSHA = "efc7ed607ff27076e3e501fc3fefefa33c0ed8cf1eff483a2b7fdc0c2e616668"
$q1 = "C:\ds4-models\ds4-q1-layers0-42-derived.gguf"
$q1SHA = "05040393f5e94bf054a593e4d2d021ff44a6f446f2328a75e4f833a1fbe20207"
$q1Bytes = [UInt64]39048344416
$prompt = "Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document."

$arguments = @(
    "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $harness,
    "-Tag", $Tag, "-GateKind", "structural-safety",
    "-ModelPath", $model, "-ExpectedModelSHA256", $modelSHA,
    "-ReuseVerifiedModelReceipt", "-Prompt", $prompt,
    "-MaxTokens", ([string]$MaxTokens), "-Repeats", "1",
    "-Context", "8192", "-PrefillChunk", "256",
    "-BudgetGB", "2", "-ReserveMB", "1024",
    "-DynamicArenaGiB", "30", "-ArenaWrapTrustWorkerChecksum",
    "-ArenaWrapSourceParts", "-ArenaWrapUnlockSourceRanges",
    "-ArenaWrapUnlockWaveGiB", "4", "-DisableQ8F16Cache",
    "-EmbedRowStaging", "-ReapPrefetchThreads", "8",
    "-PrefillMassWrap", "-ComposePrefillMassTiering",
    "-PrefillVramSeedTotal", ([string]$SeedTotal),
    "-PrefillVramSeedFloorPerLayer", ([string]$FloorPerLayer),
    "-ExpertCacheN", ([string]$SeedTotal),
    "-ExpertCacheReserveGB",
    $CacheReserveGB.ToString("0.###", [Globalization.CultureInfo]::InvariantCulture),
    "-ExpertCachePolicy", "lru",
    "-GpuResidentRoutes", "-ExpertTiering", "enforce",
    "-ExpertTierPolicy", "mass-lfru", "-ExpertTierClockCalls", "430",
    "-ExpertTierReplacementBudget", "32", "-ExpertTierMinFrequency", "3",
    "-ExpertTierHysteresis", "1.25", "-RuntimeMinimumAvailableGiB", "1",
    "-RuntimeMaximumDiskQueueLength", "8",
    "-RuntimeContaminationSamples", "3",
    "-QuiescenceCooldownSec", ([string]$QuiescenceCooldownSec),
    "-TimeoutSec", ([string]$TimeoutSec),
    "-Q1_0ExpertSidecar", $q1,
    "-ExpectedQ1_0ExpertSidecarSHA256", $q1SHA,
    "-ExpectedQ1_0ExpertSidecarBytes", ([string]$q1Bytes),
    "-ReuseVerifiedQ1_0Receipt", "-Q1_0LayerFirst", "0",
    "-Q1_0LayerLast", "42", "-Q1_0SelectedLoad",
    "-Q1_0SnapshotBacking", "-Q1_0PageableOverflow",
    "-ExpectedQ1_0SnapshotEntries", "11008"
)

Write-Host "[g114] Q1+IQ2 global-mass safety start tag=$Tag max_tokens=$MaxTokens seed_total=$SeedTotal floor_per_layer=$FloorPerLayer"
& powershell.exe @arguments
$exitCode = $LASTEXITCODE
if ($exitCode -ne 0) {
    Write-Host "[g114] harness failed exit=$exitCode raw=$rawPath"
    exit $exitCode
}
if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
    throw "G114 result missing: $resultPath"
}

$result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
$mixed = $result.q1_0_mixed
if (-not [bool]$result.prefill_vram_seed_global_observed -or
    [int]$result.prefill_vram_seed_requested_total -ne $SeedTotal -or
    [int]$result.prefill_vram_seed_floor_per_layer_requested -ne $FloorPerLayer -or
    [int]$result.prefill_vram_seed_entries -ne $SeedTotal -or
    [bool]$result.q1_0_pure_resident_requested -or
    -not [bool]$result.gpu_resident_routes_requested -or
    [int]$result.expert_cache_requested -ne $SeedTotal -or
    [string]$result.expert_tiering_requested -ne "enforce" -or
    [UInt64]$mixed.iq2_vram -eq 0 -or
    [UInt64]$mixed.q1_resident -eq 0 -or
    ([UInt64]$mixed.iq2_vram + [UInt64]$mixed.q1_resident) -ne
        ([UInt64]$mixed.calls * 6) -or
    [UInt64]$mixed.iq2_snapshot_ram -ne 0 -or
    [UInt64]$mixed.iq2_tier_ram -ne 0 -or
    [UInt64]$mixed.iq2_ssd_bytes -ne 0 -or
    [UInt64]$mixed.failures -ne 0 -or
    [UInt64]$result.q1_0_resident_misses -ne 0 -or
    [UInt64]$result.q1_0_direct_pread_bytes -ne 0) {
    throw "G114 Q1+IQ2 global-mass transport contract mismatch"
}

$sample = @($result.results)[0]
Write-Host ("[g114] PASS e2e_tps=" + $sample.tokens_per_second +
    " tokens=" + $sample.completion_tokens +
    " iq2_vram_routes=" + $mixed.iq2_vram +
    " q1_routes=" + $mixed.q1_resident +
    " content_sha=" + $sample.content_sha256)
