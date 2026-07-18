# G112 pure-Q1 resident control (PowerShell 5.1, ASCII).
param(
    [ValidateRange(1, 4000)][int]$MaxTokens = 256,
    [ValidatePattern('^[A-Za-z0-9_-]+$')][string]$Tag = "g112_q1_pure_resident_safety_n1",
    [ValidateRange(600, 86400)][int]$TimeoutSec = 1800,
    [ValidateRange(0, 3600)][int]$QuiescenceCooldownSec = 30
)

$ErrorActionPreference = "Stop"
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
    "-PrefillMassWrap", "-RuntimeMinimumAvailableGiB", "1",
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
    "-Q1_0PureResident", "-ExpectedQ1_0SnapshotEntries", "11008"
)

Write-Host "[g112] pure Q1 safety start tag=$Tag max_tokens=$MaxTokens"
& powershell.exe @arguments
$exitCode = $LASTEXITCODE
if ($exitCode -ne 0) {
    Write-Host "[g112] harness failed exit=$exitCode raw=$rawPath"
    exit $exitCode
}
if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
    throw "G112 result missing: $resultPath"
}

$result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
$mixed = $result.q1_0_mixed
if (-not [bool]$result.q1_0_pure_resident_requested -or
    [bool]$result.gpu_resident_routes_requested -or
    [int]$result.expert_cache_requested -ne 0 -or
    [string]$result.expert_tiering_requested -ne "off" -or
    [UInt64]$mixed.all_iq2 -ne 0 -or
    [UInt64]$mixed.iq2_vram -ne 0 -or
    [UInt64]$mixed.iq2_snapshot_ram -ne 0 -or
    [UInt64]$mixed.iq2_tier_ram -ne 0 -or
    [UInt64]$mixed.q1_resident -ne ([UInt64]$mixed.calls * 6) -or
    [UInt64]$mixed.joins -ne [UInt64]$mixed.calls -or
    [UInt64]$mixed.iq2_ssd_bytes -ne 0 -or
    [UInt64]$mixed.failures -ne 0 -or
    [UInt64]$result.q1_0_resident_misses -ne 0 -or
    [UInt64]$result.q1_0_direct_pread_bytes -ne 0 -or
    [UInt64]$result.dynamic_arena_allocated_slots -ne 11008 -or
    [UInt64]$result.dynamic_arena_allocated_pinned_slots -ne 9102 -or
    [UInt64]$result.dynamic_arena_allocated_pageable_slots -ne 1906) {
    throw "G112 pure-Q1 transport contract mismatch"
}

$sample = @($result.results)[0]
Write-Host ("[g112] PASS decode_tps=" + $sample.server_tps +
    " e2e_tps=" + $sample.tokens_per_second +
    " tokens=" + $sample.completion_tokens +
    " content_sha=" + $sample.content_sha256)
