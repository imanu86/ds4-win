# G7 selected-load measurement harness (ASCII only, PS 5.1 safe)
# Usage: powershell -File g7_measure.ps1 -MaxTokens 8 -TimeoutSec 900 -Tag new [-NoSelectedLoad]
param(
    [int]$MaxTokens = 8,
    [ValidateRange(0, 131072)][int]$WarmupMaxTokens = 0,
    [int]$Repeats = 1,
    [int]$TimeoutSec = 900,
    [string]$Tag = "run",
    [string]$Prompt = "Hi",
    [string]$PromptFile = "",
    [string]$SystemPrompt = "",
    [string]$WarmupPrompt = "",
    [switch]$NoSelectedLoad,
    [switch]$Warmup,
    [switch]$Diagnostics,
    [int]$ReserveMB = 2048,
    [ValidateRange(0, 65536)][int]$RuntimeReserveMB = 0,
    [int]$BudgetGB = 28,
    [ValidateRange(0, 8192)][int]$Q8F16CacheMB = 0,
    [ValidateRange(0, 8192)][int]$Q8F16CacheReserveMB = 4096,
    [switch]$DisableQ8F16Cache,
    [switch]$EmbedRowStaging,
    [ValidateRange(0.0, 1024.0)][double]$DynamicArenaGiB = 0.0,
    [switch]$PrefillMassObserve,
    [switch]$PrefillMassWrap,
    [switch]$ComposePrefillMassTiering,
    [switch]$ReapMassObserve,
    [switch]$ReapMassWrap,
    [string]$ReapMaskFile = "",
    [ValidateRange(1, 256)][int]$ReapMassWindow = 16,
    [ValidateRange(1, 256)][int]$ReapMassGrowInterval = 4,
    [ValidateRange(1.0, 100.0)][double]$ReapMassHysteresis = 1.25,
    [ValidateRange(0, 256)][int]$DynamicArenaObservedWindow = 0,
    [ValidateRange(1, 256)][int]$DynamicArenaObservedMinHits = 1,
    [ValidateRange(0, 256)][int]$DynamicArenaGrowInterval = 0,
    [ValidateSet("default", "keep", "drop")][string]$DynamicArenaCarry = "default",
    [ValidateRange(1, 32)][int]$ReapPrefetchThreads = 8,
    [ValidateSet(1, 2, 4)][int]$IoQD = 1,
    [ValidateRange(0, 512)][int]$ExpertCacheN = 0,
    [ValidateRange(0.0, 6.0)][double]$ExpertCacheReserveGB = 0.5,
    [ValidateSet("lru", "layer-top1")][string]$ExpertCachePolicy = "lru",
    [ValidateSet("off", "observe", "enforce")][string]$ExpertTiering = "off",
    [ValidateSet("second-touch", "mass-lfru")][string]$ExpertTierPolicy = "second-touch",
    [ValidateRange(1, 1000000)][int]$ExpertTierClockCalls = 430,
    [ValidateRange(1, 512)][int]$ExpertTierReplacementBudget = 16,
    [ValidateRange(2, 1000000)][int]$ExpertTierMinFrequency = 3,
    [ValidateRange(1.0, 100.0)][double]$ExpertTierHysteresis = 1.25,
    [switch]$DirectCacheHits,
    [switch]$MixedDirectCache,
    [switch]$GpuResidentRoutes,
    [switch]$SplitHitMiss,
    [switch]$RouteProfile,
    [switch]$ExpertCacheStats,
    [ValidateRange(1, 1000000)][int]$ExpertCacheStatsInterval = 128,
    [switch]$OverlapShared,
    [switch]$OverlapSharedFull,
    [switch]$DisableSharedDownFusion,
    [switch]$SpexDryRun,
    [string]$SpexFile = "",
    [string]$ExpectedSpexSHA256 = "",
    [ValidateRange(0, 6)][int]$SpexCap = 0,
    [ValidateSet("resident", "score", "topk", "full")][string]$SpexStage = "full",
    [switch]$SpexFusedTopK,
    [ValidateSet(1, 2, 4, 8)][int]$SpexRingSlots = 1,
    [ValidateSet(0, 1)][int]$SpexPrefetchK = 0,
    [ValidateSet(0, 1, 2)][int]$SpexCpuProbeK = 0,
    [ValidateRange(1, 1000000)][int]$SpexStatsEvery = 1000000,
    [string]$ExpectedContentSHA256 = "",
    [string]$ExpectedWarmupContentSHA256 = "",
    [string]$ModelPath = "D:\ds4-models\ds4-2bit.gguf",
    [int]$Port = 8000,
    [ValidateRange(64, 131072)][int]$Context = 256,
    [ValidateRange(-1, 65536)][int]$PrefillChunk = -1,
    [switch]$PrefillUnionStats,
    [switch]$PrefillWaves,
    [ValidateRange(0, 256)][int]$PrefillWaveForceExperts = 0,
    [switch]$PrefillWaveDoubleBuffer,
    [switch]$GenericSortedMoe,
    [ValidateRange(250, 10000)][int]$TelemetryIntervalMs = 1000,
    [switch]$SkipMemoryPreflight,
    [ValidateRange(0.0, 1024.0)][double]$MinimumAvailableGiB = 0.0
)

$ErrorActionPreference = "Stop"
if ($PromptFile) {
    $PromptFile = (Resolve-Path -LiteralPath $PromptFile).Path
    $Prompt = [IO.File]::ReadAllText($PromptFile, [Text.Encoding]::UTF8)
}
$Prompt = [string]::Concat($Prompt)
$SystemPrompt = [string]::Concat($SystemPrompt)
$WarmupPrompt = [string]::Concat($WarmupPrompt)
$memoryPreflightHelper = Join-Path $PSScriptRoot "g7_memory_preflight.ps1"
$runtimeMonitorHelper = Join-Path $PSScriptRoot "g7_runtime_monitor.ps1"
. $memoryPreflightHelper
if (-not (Test-Path -LiteralPath $runtimeMonitorHelper)) {
    throw "Required runtime monitor not found: $runtimeMonitorHelper"
}
if ($ExpectedContentSHA256 -and $ExpectedContentSHA256 -notmatch '^[0-9a-fA-F]{64}$') {
    throw "ExpectedContentSHA256 must be a 64-character hexadecimal SHA-256"
}
if ($ExpectedSpexSHA256 -and $ExpectedSpexSHA256 -notmatch '^[0-9a-fA-F]{64}$') {
    throw "ExpectedSpexSHA256 must be a 64-character hexadecimal SHA-256"
}
if ($ExpectedWarmupContentSHA256 -and $ExpectedWarmupContentSHA256 -notmatch '^[0-9a-fA-F]{64}$') {
    throw "ExpectedWarmupContentSHA256 must be a 64-character hexadecimal SHA-256"
}
if ($WarmupPrompt -and -not $Warmup) {
    throw "WarmupPrompt requires -Warmup"
}
if ($WarmupMaxTokens -gt 0 -and -not $Warmup) {
    throw "WarmupMaxTokens requires -Warmup"
}
if ($ExpectedWarmupContentSHA256 -and -not $Warmup) {
    throw "ExpectedWarmupContentSHA256 requires -Warmup"
}
if ($GpuResidentRoutes -and $ExpertCacheN -le 0) {
    throw "GpuResidentRoutes requires -ExpertCacheN greater than zero"
}
if ($SplitHitMiss -and -not $GpuResidentRoutes) {
    throw "SplitHitMiss requires -GpuResidentRoutes"
}
if ($PrefillWaveForceExperts -gt 0 -and -not $PrefillWaves) {
    throw "PrefillWaveForceExperts requires -PrefillWaves"
}
if ($PrefillWaveDoubleBuffer -and -not $PrefillWaves) {
    throw "PrefillWaveDoubleBuffer requires -PrefillWaves"
}
$effectiveWarmupPrompt = if ($WarmupPrompt) { $WarmupPrompt } else { $Prompt }
$effectiveWarmupMaxTokens = if ($WarmupMaxTokens -gt 0) { $WarmupMaxTokens } else { $MaxTokens }
$effectiveSpexCap = if ($SpexCap -gt 0) { $SpexCap } else { 6 }
$exe   = Join-Path $PSScriptRoot "build\Release\ds4_server.exe"
$buildManifestPath = Join-Path $PSScriptRoot "build\Release\g7_build_manifest.json"
$model = $ModelPath
$outdir = Join-Path $PSScriptRoot "g7_runs"
New-Item -ItemType Directory -Force -Path $outdir | Out-Null
$stderrLog = Join-Path $outdir ("g7_" + $Tag + "_stderr.log")
$stdoutLog = Join-Path $outdir ("g7_" + $Tag + "_stdout.log")
$memoryPreflightLog = Join-Path $outdir ("g7_" + $Tag + "_memory_preflight.json")
$runtimeTelemetryLog = Join-Path $outdir ("g7_" + $Tag + "_runtime_telemetry.jsonl")
$rawOutputsPath = Join-Path $outdir ("g7_" + $Tag + "_raw_outputs.json")
$resultPath = Join-Path $outdir ("g7_" + $Tag + "_result.json")
if (Test-Path $stderrLog) { Remove-Item $stderrLog -Force }
if (Test-Path $stdoutLog) { Remove-Item $stdoutLog -Force }
if (Test-Path $memoryPreflightLog) { Remove-Item $memoryPreflightLog -Force }
if (Test-Path $runtimeTelemetryLog) { Remove-Item $runtimeTelemetryLog -Force }
if (Test-Path $rawOutputsPath) { Remove-Item $rawOutputsPath -Force }
if (Test-Path $resultPath) { Remove-Item $resultPath -Force }

$env:CUDA_PATH = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.6"
$env:PATH = "$env:CUDA_PATH\bin;" + $env:PATH
$inheritedDs4Environment = [ordered]@{}
$_processEnvironment = [System.Environment]::GetEnvironmentVariables()
foreach ($name in @($_processEnvironment.Keys | ForEach-Object { [string]$_ } | Where-Object { $_ -like "DS4_*" } | Sort-Object)) {
    $inheritedDs4Environment[$name] = [string]$_processEnvironment[$name]
    [System.Environment]::SetEnvironmentVariable($name, $null, [System.EnvironmentVariableTarget]::Process)
}
$env:DS4_CUDA_STREAM_FROM_RAM_MASKED_BUDGET_GB = "$BudgetGB"
$env:DS4_CUDA_STREAM_RESERVE_MB = "$ReserveMB"
if ($RuntimeReserveMB -gt 0) {
    $env:DS4_CUDA_STREAM_RUNTIME_RESERVE_MB = "$RuntimeReserveMB"
} else {
    Remove-Item Env:\DS4_CUDA_STREAM_RUNTIME_RESERVE_MB -ErrorAction SilentlyContinue
}
if ($Q8F16CacheMB -gt 0) {
    $env:DS4_CUDA_Q8_F16_CACHE_MB = "$Q8F16CacheMB"
} else {
    Remove-Item Env:\DS4_CUDA_Q8_F16_CACHE_MB -ErrorAction SilentlyContinue
}
$env:DS4_CUDA_Q8_F16_CACHE_RESERVE_MB = "$Q8F16CacheReserveMB"
if ($DisableQ8F16Cache) {
    $env:DS4_CUDA_NO_Q8_F16_CACHE = "1"
} else {
    Remove-Item Env:\DS4_CUDA_NO_Q8_F16_CACHE -ErrorAction SilentlyContinue
}
if ($EmbedRowStaging) {
    $env:DS4_CUDA_EMBED_ROW_STAGING = "1"
} else {
    Remove-Item Env:\DS4_CUDA_EMBED_ROW_STAGING -ErrorAction SilentlyContinue
}
if ($DynamicArenaGiB -gt 0.0) {
    $env:DS4_CUDA_DYNAMIC_ARENA_GB = $DynamicArenaGiB.ToString("0.###", [Globalization.CultureInfo]::InvariantCulture)
} else {
    Remove-Item Env:\DS4_CUDA_DYNAMIC_ARENA_GB -ErrorAction SilentlyContinue
}
if ($PrefillMassObserve -or $PrefillMassWrap) {
    $env:DS4_CUDA_PREFILL_MASS_OBSERVE = "1"
} else {
    Remove-Item Env:\DS4_CUDA_PREFILL_MASS_OBSERVE -ErrorAction SilentlyContinue
}
if ($PrefillMassWrap) {
    $env:DS4_CUDA_PREFILL_MASS_WRAP = "1"
} else {
    Remove-Item Env:\DS4_CUDA_PREFILL_MASS_WRAP -ErrorAction SilentlyContinue
}
if ($ComposePrefillMassTiering) {
    $env:DS4_CUDA_PREFILL_TIER_COMPOSE = "1"
} else {
    Remove-Item Env:\DS4_CUDA_PREFILL_TIER_COMPOSE -ErrorAction SilentlyContinue
}
if ($ReapMassObserve -or $ReapMassWrap) {
    $env:DS4_CUDA_REAP_MASS_OBSERVE = "1"
    $env:DS4_CUDA_REAP_MASS_WINDOW = "$ReapMassWindow"
} else {
    Remove-Item Env:\DS4_CUDA_REAP_MASS_OBSERVE -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_CUDA_REAP_MASS_WINDOW -ErrorAction SilentlyContinue
}
if ($ReapMassWrap) {
    $env:DS4_CUDA_REAP_MASS_WRAP = "1"
    $env:DS4_CUDA_REAP_MASS_GROW_INTERVAL = "$ReapMassGrowInterval"
    $env:DS4_CUDA_REAP_MASS_HYSTERESIS = $ReapMassHysteresis.ToString("R", [Globalization.CultureInfo]::InvariantCulture)
} else {
    Remove-Item Env:\DS4_CUDA_REAP_MASS_WRAP -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_CUDA_REAP_MASS_GROW_INTERVAL -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_CUDA_REAP_MASS_HYSTERESIS -ErrorAction SilentlyContinue
}
if ($ReapMaskFile) {
    if (-not (Test-Path -LiteralPath $ReapMaskFile -PathType Leaf)) {
        throw "ReapMaskFile does not exist: $ReapMaskFile"
    }
    $env:DS4_REAP_MASK_FILE = (Resolve-Path -LiteralPath $ReapMaskFile).Path
} else {
    Remove-Item Env:\DS4_REAP_MASK_FILE -ErrorAction SilentlyContinue
}
if ($DynamicArenaObservedWindow -gt 0) {
    $env:DS4_CUDA_DYNAMIC_ARENA_OBSERVED_WINDOW = "$DynamicArenaObservedWindow"
    $env:DS4_CUDA_DYNAMIC_ARENA_OBSERVED_MIN_HITS = "$DynamicArenaObservedMinHits"
} else {
    Remove-Item Env:\DS4_CUDA_DYNAMIC_ARENA_OBSERVED_WINDOW -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_CUDA_DYNAMIC_ARENA_OBSERVED_MIN_HITS -ErrorAction SilentlyContinue
}
if ($DynamicArenaGrowInterval -gt 0) {
    $env:DS4_CUDA_DYNAMIC_ARENA_GROW_INTERVAL = "$DynamicArenaGrowInterval"
} else {
    Remove-Item Env:\DS4_CUDA_DYNAMIC_ARENA_GROW_INTERVAL -ErrorAction SilentlyContinue
}
if ($DynamicArenaCarry -eq "keep") {
    $env:DS4_CUDA_DYNAMIC_ARENA_CARRY_ACROSS_REQUESTS = "1"
} elseif ($DynamicArenaCarry -eq "drop") {
    $env:DS4_CUDA_DYNAMIC_ARENA_CARRY_ACROSS_REQUESTS = "0"
} else {
    Remove-Item Env:\DS4_CUDA_DYNAMIC_ARENA_CARRY_ACROSS_REQUESTS -ErrorAction SilentlyContinue
}
$env:DS4_REAP_PREFETCH_THREADS = "$ReapPrefetchThreads"
if ($Diagnostics) {
    $env:DS4_CUDA_WEIGHT_CACHE_VERBOSE = "1"
    $env:DS4_CUDA_SEL_PROFILE = "1"
} else {
    Remove-Item Env:\DS4_CUDA_WEIGHT_CACHE_VERBOSE -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_CUDA_SEL_PROFILE -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_METAL_DECODE_STAGE_PROFILE -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_CUDA_MOE_PROFILE -ErrorAction SilentlyContinue
}
if ($NoSelectedLoad) { $env:DS4_CUDA_MOE_NO_SELECTED_LOAD = "1" }
else { Remove-Item Env:\DS4_CUDA_MOE_NO_SELECTED_LOAD -ErrorAction SilentlyContinue }
if ($PrefillChunk -ge 0) { $env:DS4_METAL_PREFILL_CHUNK = "$PrefillChunk" }
else { Remove-Item Env:\DS4_METAL_PREFILL_CHUNK -ErrorAction SilentlyContinue }
if ($PrefillUnionStats) { $env:DS4_CUDA_PREFILL_UNION_STATS = "1" }
else { Remove-Item Env:\DS4_CUDA_PREFILL_UNION_STATS -ErrorAction SilentlyContinue }
if ($PrefillWaves) { $env:DS4_CUDA_PREFILL_WAVES = "1" }
else { Remove-Item Env:\DS4_CUDA_PREFILL_WAVES -ErrorAction SilentlyContinue }
if ($PrefillWaveForceExperts -gt 0) {
    $env:DS4_CUDA_PREFILL_WAVE_FORCE_EXPERTS = "$PrefillWaveForceExperts"
} else {
    Remove-Item Env:\DS4_CUDA_PREFILL_WAVE_FORCE_EXPERTS -ErrorAction SilentlyContinue
}
if ($PrefillWaveDoubleBuffer) {
    $env:DS4_CUDA_PREFILL_WAVE_DOUBLE_BUFFER = "1"
} else {
    Remove-Item Env:\DS4_CUDA_PREFILL_WAVE_DOUBLE_BUFFER -ErrorAction SilentlyContinue
}
if ($GenericSortedMoe) {
    $env:DS4_CUDA_MOE_NO_EXPERT_TILES = "1"
    $env:DS4_CUDA_MOE_NO_P2 = "1"
} else {
    Remove-Item Env:\DS4_CUDA_MOE_NO_EXPERT_TILES -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_CUDA_MOE_NO_P2 -ErrorAction SilentlyContinue
}
if ($IoQD -gt 1) { $env:DS4_CUDA_MOE_IO_QD = "$IoQD" }
else { Remove-Item Env:\DS4_CUDA_MOE_IO_QD -ErrorAction SilentlyContinue }
if ($ExpertCacheN -gt 0) {
    $env:DS4_CUDA_STREAMING_EXPERT_CACHE_N = "$ExpertCacheN"
    $env:DS4_CUDA_STREAMING_EXPERT_CACHE_RESERVE_GB = $ExpertCacheReserveGB.ToString("0.###", [Globalization.CultureInfo]::InvariantCulture)
    $env:DS4_CUDA_MOE_CACHE_POLICY = $ExpertCachePolicy
} else {
    Remove-Item Env:\DS4_CUDA_STREAMING_EXPERT_CACHE_N -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_CUDA_STREAMING_EXPERT_CACHE_RESERVE_GB -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_CUDA_MOE_CACHE_POLICY -ErrorAction SilentlyContinue
}
if ($ExpertTiering -eq "off") {
    Remove-Item Env:\DS4_EXPERT_TIERING -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_EXPERT_TIER_POLICY -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_EXPERT_TIER_CLOCK_CALLS -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_EXPERT_TIER_REPLACEMENT_BUDGET -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_EXPERT_TIER_MIN_FREQUENCY -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_EXPERT_TIER_HYSTERESIS -ErrorAction SilentlyContinue
} else {
    $env:DS4_EXPERT_TIERING = $ExpertTiering
    $env:DS4_EXPERT_TIER_POLICY = $ExpertTierPolicy
    $env:DS4_EXPERT_TIER_CLOCK_CALLS = "$ExpertTierClockCalls"
    $env:DS4_EXPERT_TIER_REPLACEMENT_BUDGET = "$ExpertTierReplacementBudget"
    $env:DS4_EXPERT_TIER_MIN_FREQUENCY = "$ExpertTierMinFrequency"
    $env:DS4_EXPERT_TIER_HYSTERESIS = $ExpertTierHysteresis.ToString("R", [Globalization.CultureInfo]::InvariantCulture)
}
if ($DirectCacheHits) {
    $env:DS4_CUDA_MOE_DIRECT_CACHE_HITS = "1"
    if ($Diagnostics) {
        $env:DS4_CUDA_MOE_DIRECT_CACHE_STATS = "1"
    } else {
        Remove-Item Env:\DS4_CUDA_MOE_DIRECT_CACHE_STATS -ErrorAction SilentlyContinue
    }
} else {
    Remove-Item Env:\DS4_CUDA_MOE_DIRECT_CACHE_HITS -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_CUDA_MOE_DIRECT_CACHE_STATS -ErrorAction SilentlyContinue
}
if ($MixedDirectCache) {
    $env:DS4_CUDA_MOE_MIXED_DIRECT = "1"
    if ($Diagnostics) {
        $env:DS4_CUDA_MOE_MIXED_DIRECT_STATS = "1"
    } else {
        Remove-Item Env:\DS4_CUDA_MOE_MIXED_DIRECT_STATS -ErrorAction SilentlyContinue
    }
} else {
    Remove-Item Env:\DS4_CUDA_MOE_MIXED_DIRECT -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_CUDA_MOE_MIXED_DIRECT_STATS -ErrorAction SilentlyContinue
}
if ($GpuResidentRoutes) {
    $env:DS4_CUDA_MOE_GPU_RESIDENT_ROUTES = "1"
} else {
    Remove-Item Env:\DS4_CUDA_MOE_GPU_RESIDENT_ROUTES -ErrorAction SilentlyContinue
}
if ($SplitHitMiss) {
    $env:DS4_CUDA_MOE_SPLIT_HIT_MISS = "1"
} else {
    Remove-Item Env:\DS4_CUDA_MOE_SPLIT_HIT_MISS -ErrorAction SilentlyContinue
}
if ($RouteProfile) { $env:DS4_CUDA_MOE_ROUTE_PROFILE = "1" }
else { Remove-Item Env:\DS4_CUDA_MOE_ROUTE_PROFILE -ErrorAction SilentlyContinue }
if ($ExpertCacheStats) {
    $env:DS4_CUDA_MOE_CACHE_STATS = "1"
    $env:DS4_CUDA_MOE_CACHE_STATS_INTERVAL = "$ExpertCacheStatsInterval"
} else {
    Remove-Item Env:\DS4_CUDA_MOE_CACHE_STATS -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_CUDA_MOE_CACHE_STATS_INTERVAL -ErrorAction SilentlyContinue
}
if ($OverlapShared) { $env:DS4_CUDA_MOE_OVERLAP_SHARED = "1" }
else { Remove-Item Env:\DS4_CUDA_MOE_OVERLAP_SHARED -ErrorAction SilentlyContinue }
if ($OverlapSharedFull) { $env:DS4_CUDA_MOE_OVERLAP_SHARED_FULL = "1" }
else { Remove-Item Env:\DS4_CUDA_MOE_OVERLAP_SHARED_FULL -ErrorAction SilentlyContinue }
if ($DisableSharedDownFusion) { $env:DS4_METAL_DISABLE_SHARED_DOWN_HC_FUSION = "1" }
else { Remove-Item Env:\DS4_METAL_DISABLE_SHARED_DOWN_HC_FUSION -ErrorAction SilentlyContinue }
if ($SpexDryRun) {
    if (-not $SpexFile -or -not (Test-Path -LiteralPath $SpexFile)) {
        throw "SpexDryRun requires an existing SpexFile"
    }
    $env:DS4_SPEX_HIDDEN_GPU_DRY_RUN = "1"
    $env:DS4_SPEX_FILE = $SpexFile
    $env:DS4_SPEX_CAP = "$effectiveSpexCap"
    $env:DS4_SPEX_AB_STAGE = $SpexStage
    if ($SpexFusedTopK) { $env:DS4_SPEX_FUSED_TOPK = "1" }
    else { Remove-Item Env:\DS4_SPEX_FUSED_TOPK -ErrorAction SilentlyContinue }
    $env:DS4_SPEX_RING_SLOTS = "$SpexRingSlots"
    $env:DS4_SPEX_DRY_RUN_STATS_EVERY = "$SpexStatsEvery"
    if ($SpexPrefetchK -gt 0) { $env:DS4_SPEX_PREFETCH_K = "$SpexPrefetchK" }
    else { Remove-Item Env:\DS4_SPEX_PREFETCH_K -ErrorAction SilentlyContinue }
    if ($SpexCpuProbeK -gt 0) { $env:DS4_SPEX_CPU_PROBE_K = "$SpexCpuProbeK" }
    else { Remove-Item Env:\DS4_SPEX_CPU_PROBE_K -ErrorAction SilentlyContinue }
} else {
    Remove-Item Env:\DS4_SPEX_HIDDEN_GPU_DRY_RUN -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_SPEX_FILE -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_SPEX_CAP -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_SPEX_AB_STAGE -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_SPEX_FUSED_TOPK -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_SPEX_RING_SLOTS -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_SPEX_DRY_RUN_STATS_EVERY -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_SPEX_PREFETCH_K -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_SPEX_CPU_PROBE_K -ErrorAction SilentlyContinue
}

if ($Repeats -lt 1) { throw "Repeats must be >= 1" }
$env:DS4_BENCH_EXIT_AFTER_REQUESTS = "$(if ($Warmup) { $Repeats + 1 } else { $Repeats })"
if ($ComposePrefillMassTiering) {
    if (-not $PrefillMassWrap) { throw "ComposePrefillMassTiering requires PrefillMassWrap" }
    if ($DynamicArenaGiB -le 0.0) { throw "ComposePrefillMassTiering requires DynamicArenaGiB > 0" }
    if ($ExpertTiering -ne "enforce") { throw "ComposePrefillMassTiering requires ExpertTiering enforce" }
    if ($ExpertTierPolicy -ne "mass-lfru") { throw "ComposePrefillMassTiering requires ExpertTierPolicy mass-lfru" }
    if ($ExpertCacheN -le 0) { throw "ComposePrefillMassTiering requires ExpertCacheN > 0" }
    if (-not $GpuResidentRoutes) { throw "ComposePrefillMassTiering requires GpuResidentRoutes" }
    if (-not $DisableQ8F16Cache -or $Q8F16CacheMB -ne 0) { throw "ComposePrefillMassTiering requires Q8-F16 cache disabled" }
    if ($Warmup -or $Repeats -ne 1) { throw "ComposePrefillMassTiering requires one request and no warmup" }
    if ($PrefillMassObserve -or $ReapMassObserve -or $ReapMassWrap) { throw "ComposePrefillMassTiering must be isolated from observe-only prefill and REAP mass" }
    if ($DynamicArenaObservedWindow -gt 0 -or $DynamicArenaGrowInterval -gt 0 -or $DynamicArenaCarry -ne "default") { throw "ComposePrefillMassTiering must be isolated from dynamic arena observer/grow/carry" }
}
if ($ExpertTiering -ne "off") {
    if (-not $GpuResidentRoutes) { throw "ExpertTiering requires GpuResidentRoutes" }
    if ($ExpertCacheN -le 0) { throw "ExpertTiering requires ExpertCacheN > 0" }
    if (-not $DisableQ8F16Cache -or $Q8F16CacheMB -ne 0) { throw "ExpertTiering requires Q8-F16 cache disabled" }
    if ($SplitHitMiss) { throw "ExpertTiering must be isolated from SplitHitMiss" }
    if ($SpexDryRun -or $SpexPrefetchK -gt 0 -or $SpexCpuProbeK -gt 0) { throw "ExpertTiering must be isolated from SPEX" }
    if (-not $ComposePrefillMassTiering -and ($PrefillMassObserve -or $PrefillMassWrap -or $ReapMassObserve -or $ReapMassWrap)) { throw "ExpertTiering must be isolated from prefill/REAP mass observe/wrap" }
    if ($ComposePrefillMassTiering -and ($PrefillMassObserve -or $ReapMassObserve -or $ReapMassWrap)) { throw "ExpertTiering compose must be isolated from observe-only prefill and REAP mass" }
    if ($DynamicArenaObservedWindow -gt 0 -or $DynamicArenaGrowInterval -gt 0 -or $DynamicArenaCarry -ne "default") { throw "ExpertTiering must be isolated from dynamic arena observer/grow/carry" }
    if ($ReapMaskFile) { throw "ExpertTiering must be isolated from ReapMaskFile" }
    if ($OverlapShared -or $OverlapSharedFull) { throw "ExpertTiering must be isolated from overlap" }
    if ($ExpertTiering -eq "enforce" -and $DynamicArenaGiB -le 0.0) { throw "ExpertTiering enforce requires DynamicArenaGiB > 0" }
}
if ($DynamicArenaObservedWindow -gt 0 -and $DynamicArenaGiB -le 0.0) { throw "DynamicArenaObservedWindow requires DynamicArenaGiB > 0" }
if ($PrefillMassObserve -and $DynamicArenaGiB -le 0.0) { throw "PrefillMassObserve requires DynamicArenaGiB > 0" }
if ($PrefillMassWrap -and $DynamicArenaGiB -le 0.0) { throw "PrefillMassWrap requires DynamicArenaGiB > 0" }
if ($ReapMassObserve -and $DynamicArenaGiB -le 0.0) { throw "ReapMassObserve requires DynamicArenaGiB > 0" }
if ($ReapMassWrap -and $DynamicArenaGiB -le 0.0) { throw "ReapMassWrap requires DynamicArenaGiB > 0" }
if ($ReapMaskFile -and ($PrefillMassObserve -or $PrefillMassWrap -or
        $ReapMassObserve -or $ReapMassWrap -or
        $DynamicArenaGiB -gt 0.0 -or $DynamicArenaObservedWindow -gt 0 -or
        $DynamicArenaGrowInterval -gt 0 -or $DynamicArenaCarry -ne "default" -or
        $SpexDryRun -or $SpexPrefetchK -gt 0 -or $SpexCpuProbeK -gt 0)) {
    throw "ReapMaskFile static bake must be isolated from adaptive arena, REAP mass, prefill mass, and SPEX"
}
if ($PrefillMassWrap -and $DynamicArenaObservedWindow -gt 0) { throw "PrefillMassWrap must be isolated from the decode observer" }
if ($PrefillMassWrap -and $DynamicArenaGrowInterval -gt 0) { throw "PrefillMassWrap must be isolated from arena growth" }
if ($PrefillMassWrap -and $DynamicArenaCarry -ne "default") { throw "PrefillMassWrap must be isolated from arena carry" }
if ($PrefillMassWrap -and -not $ComposePrefillMassTiering -and ($ExpertCacheN -gt 0 -or $ExpertCacheStats)) { throw "PrefillMassWrap must be isolated from the expert cache" }
if ($PrefillMassWrap -and ($SpexDryRun -or $SpexPrefetchK -gt 0 -or $SpexCpuProbeK -gt 0)) { throw "PrefillMassWrap must be isolated from SPEX" }
if ($PrefillMassWrap -and ($Warmup -or $Repeats -ne 1)) { throw "PrefillMassWrap first-snapshot measurements require one request and no warmup" }
if ($DynamicArenaGrowInterval -gt 0 -and $DynamicArenaObservedWindow -le 0) { throw "DynamicArenaGrowInterval requires DynamicArenaObservedWindow > 0" }
if ($DynamicArenaCarry -ne "default" -and (-not $Warmup -or $DynamicArenaObservedWindow -le 0)) { throw "DynamicArenaCarry requires Warmup and DynamicArenaObservedWindow > 0" }
if ($SpexFusedTopK -and -not $SpexDryRun) { throw "SpexFusedTopK requires SpexDryRun" }
if ($SpexFusedTopK -and $SpexStage -notin @("topk", "full")) { throw "SpexFusedTopK requires the topk or full stage" }
if ($SpexRingSlots -gt 1 -and (-not $SpexDryRun -or $SpexStage -ne "full")) { throw "SpexRingSlots > 1 requires the full SpexDryRun stage" }
if ($SpexPrefetchK -gt 0 -and (-not $SpexDryRun -or $SpexStage -ne "full" -or $effectiveSpexCap -lt $SpexPrefetchK)) { throw "SpexPrefetchK requires full SpexDryRun with SpexCap >= SpexPrefetchK" }
if ($SpexPrefetchK -gt 0 -and $ExpertCacheN -gt 0) { throw "SpexPrefetchK is incompatible with ExpertCacheN > 0" }
if ($SpexPrefetchK -gt 0 -and $NoSelectedLoad) { throw "SpexPrefetchK is incompatible with NoSelectedLoad" }
if ($SpexCpuProbeK -gt 0 -and (-not $SpexDryRun -or $SpexStage -ne "full" -or $effectiveSpexCap -lt $SpexCpuProbeK -or $SpexPrefetchK -ne 0)) { throw "SpexCpuProbeK requires full SpexDryRun with SpexCap >= SpexCpuProbeK and SpexPrefetchK=0" }
if ($OverlapShared -and $OverlapSharedFull) { throw "Select only one overlap policy" }
if (($OverlapShared -or $OverlapSharedFull) -and $NoSelectedLoad) { throw "Overlap is incompatible with NoSelectedLoad" }
if (($OverlapShared -or $OverlapSharedFull) -and $ExpertCacheN -gt 0) { throw "Overlap is incompatible with ExpertCacheN > 0" }
$effectiveDs4Environment = [ordered]@{}
$_processEnvironment = [System.Environment]::GetEnvironmentVariables()
foreach ($name in @($_processEnvironment.Keys | ForEach-Object { [string]$_ } | Where-Object { $_ -like "DS4_*" } | Sort-Object)) {
    $effectiveDs4Environment[$name] = [string]$_processEnvironment[$name]
}
$effectiveMinimumAvailableGiB = $MinimumAvailableGiB
if ($effectiveMinimumAvailableGiB -eq 0.0) {
    $effectiveMinimumAvailableGiB = 4.0
    if ($DynamicArenaGiB -gt 0.0) {
        $effectiveMinimumAvailableGiB = [math]::Max(4.0, $DynamicArenaGiB + 2.0)
    }
}
$memoryPreflight = Invoke-G7MemoryPreflight -Skip:$SkipMemoryPreflight `
    -MinimumAvailableGiB $effectiveMinimumAvailableGiB -Label ("g7:" + $Tag)
Write-G7MemoryPreflightTelemetry -Telemetry $memoryPreflight -Path $memoryPreflightLog
if (-not $memoryPreflight.ready_to_launch) {
    throw ("Memory preflight refused launch: " + $memoryPreflight.failure_message)
}

# Capture provenance before the process starts so a concurrent edit cannot be
# attributed retroactively to a completed measurement.
$headAtStart = git -C $PSScriptRoot rev-parse HEAD
$worktreeDirtyAtStart = [bool](git -C $PSScriptRoot status --porcelain)
$sourceHashAtStart = (Get-FileHash -Algorithm SHA256 (Join-Path $PSScriptRoot "ds4_cuda.cu")).Hash.ToLowerInvariant()
$ds4SourceHashAtStart = (Get-FileHash -Algorithm SHA256 (Join-Path $PSScriptRoot "ds4.c")).Hash.ToLowerInvariant()
$serverSourceHashAtStart = (Get-FileHash -Algorithm SHA256 (Join-Path $PSScriptRoot "ds4_server.c")).Hash.ToLowerInvariant()
$spexSourceHashAtStart = (Get-FileHash -Algorithm SHA256 (Join-Path $PSScriptRoot "ds4_spex_predict.c")).Hash.ToLowerInvariant()
$gpuHeaderHashAtStart = (Get-FileHash -Algorithm SHA256 (Join-Path $PSScriptRoot "ds4_gpu.h")).Hash.ToLowerInvariant()
$spexQueueHeaderHashAtStart = (Get-FileHash -Algorithm SHA256 (Join-Path $PSScriptRoot "ds4_spex_queue.h")).Hash.ToLowerInvariant()
$threadHeaderHashAtStart = (Get-FileHash -Algorithm SHA256 (Join-Path $PSScriptRoot "src\platform\os_thread.h")).Hash.ToLowerInvariant()
$cmakeHashAtStart = (Get-FileHash -Algorithm SHA256 (Join-Path $PSScriptRoot "CMakeLists.txt")).Hash.ToLowerInvariant()
$exeHashAtStart = (Get-FileHash -Algorithm SHA256 $exe).Hash.ToLowerInvariant()
$harnessHashAtStart = (Get-FileHash -Algorithm SHA256 $PSCommandPath).Hash.ToLowerInvariant()
$memoryPreflightHashAtStart = (Get-FileHash -Algorithm SHA256 $memoryPreflightHelper).Hash.ToLowerInvariant()
$runtimeMonitorHashAtStart = (Get-FileHash -Algorithm SHA256 $runtimeMonitorHelper).Hash.ToLowerInvariant()
$buildManifestHashAtStart = if (Test-Path -LiteralPath $buildManifestPath) {
    (Get-FileHash -Algorithm SHA256 $buildManifestPath).Hash.ToLowerInvariant()
} else { "" }
$spexHashAtStart = if ($SpexDryRun) { (Get-FileHash -Algorithm SHA256 -LiteralPath $SpexFile).Hash.ToLowerInvariant() } else { "" }
if ($ExpectedSpexSHA256 -and $spexHashAtStart -ine $ExpectedSpexSHA256) {
    throw "SPEX provenance failed: expected $($ExpectedSpexSHA256.ToLowerInvariant()), observed $spexHashAtStart"
}
$modelInfoAtStart = Get-Item -LiteralPath $model
$promptBytes = [Text.Encoding]::UTF8.GetBytes($Prompt)
$promptHash = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($promptBytes)).Replace("-", "").ToLowerInvariant()
$systemPromptBytes = [Text.Encoding]::UTF8.GetBytes($SystemPrompt)
$systemPromptHash = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($systemPromptBytes)).Replace("-", "").ToLowerInvariant()
$warmupPromptBytes = [Text.Encoding]::UTF8.GetBytes($effectiveWarmupPrompt)
$warmupPromptHash = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($warmupPromptBytes)).Replace("-", "").ToLowerInvariant()
$buildManifest = $null
if (-not (Test-Path -LiteralPath $buildManifestPath -PathType Leaf)) {
    throw "Build provenance failed closed: run g7_build.ps1 before measuring"
}
try { $buildManifest = Get-Content -LiteralPath $buildManifestPath -Raw | ConvertFrom-Json }
catch { throw "Build provenance failed closed: invalid manifest JSON" }
if ($buildManifest.schema -ne "g7_native_windows_build_manifest_v1") {
    throw "Build provenance failed closed: unsupported manifest schema"
}
if ($buildManifest.executable_sha256 -ne $exeHashAtStart) {
    throw "Build provenance failed closed: executable hash does not match manifest"
}
$currentBuildInputPaths = @(
    @(git -C $PSScriptRoot ls-files) +
    @(git -C $PSScriptRoot ls-files --others --exclude-standard) |
    Where-Object {
        $_ -notmatch '^(build|g7_runs)/' -and
        ($_ -match '\.(c|cc|cpp|cu|h|hpp|cmake)$' -or
         $_ -match '(^|/)CMakeLists\.txt$')
    } | Sort-Object -Unique
)
$manifestInputPaths = @($buildManifest.inputs | ForEach-Object { $_.path } | Sort-Object -Unique)
if ((Compare-Object $manifestInputPaths $currentBuildInputPaths).Count -ne 0) {
    throw "Build provenance failed closed: compile input set changed since build"
}
foreach ($input in @($buildManifest.inputs)) {
    $inputPath = Join-Path $PSScriptRoot ($input.path -replace '/', '\')
    if (-not (Test-Path -LiteralPath $inputPath -PathType Leaf)) {
        throw "Build provenance failed closed: input missing $($input.path)"
    }
    $currentHash = (Get-FileHash -LiteralPath $inputPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($currentHash -ne $input.sha256) {
        throw "Build provenance failed closed: input hash changed $($input.path)"
    }
}
$gpuIdentity = $null
try {
    $gpuRaw = & nvidia-smi --query-gpu=name,driver_version,vbios_version,pci.bus_id --format=csv,noheader,nounits 2>$null
    if ($LASTEXITCODE -eq 0 -and $gpuRaw) {
        $gpuParts = @((@($gpuRaw)[0]).Split(',') | ForEach-Object { $_.Trim() })
        if ($gpuParts.Count -ge 4) {
            $gpuIdentity = [pscustomobject]@{
                name = $gpuParts[0]
                driver_version = $gpuParts[1]
                vbios_version = $gpuParts[2]
                pci_bus_id = $gpuParts[3]
            }
        }
    }
} catch { $gpuIdentity = $null }

$serverMaxTokens = [math]::Max($MaxTokens, $effectiveWarmupMaxTokens)
$argList = @("-m", $model, "--cuda", "-c", "$Context", "-n", "$serverMaxTokens", "--host", "127.0.0.1", "--port", "$Port")
Write-Host ("[g7] launching: " + $exe + " " + ($argList -join " "))
Write-Host ("[g7] NoSelectedLoad=" + $NoSelectedLoad + " MaxTokens=" + $MaxTokens)

$proc = Start-Process -FilePath $exe -ArgumentList $argList -NoNewWindow -PassThru `
    -RedirectStandardError $stderrLog -RedirectStandardOutput $stdoutLog
$telemetryProc = Start-Process -FilePath powershell.exe -ArgumentList @(
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $runtimeMonitorHelper,
    "-TargetProcessId", "$($proc.Id)", "-OutputPath", $runtimeTelemetryLog,
    "-IntervalMs", "$TelemetryIntervalMs"
) -WindowStyle Hidden -PassThru
$launchTime = Get-Date

# Poll TCP for ready (server opens the port only after model load)
$ready = $false
$deadline = (Get-Date).AddSeconds($TimeoutSec)
while ((Get-Date) -lt $deadline) {
    if ($proc.HasExited) { Write-Host ("[g7] server EXITED early, code=" + $proc.ExitCode); break }
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $c.Connect("127.0.0.1", $Port)
        if ($c.Connected) { $ready = $true; $c.Close(); break }
    } catch { Start-Sleep -Milliseconds 500 }
}
$readyTime = Get-Date
$loadSec = ($readyTime - $launchTime).TotalSeconds
if (-not $ready) {
    Write-Host ("[g7] NOT READY within timeout (load " + [int]$loadSec + "s). Aborting.")
    if (-not $proc.HasExited) { $proc.Kill() }
    Write-Host "=== stderr tail ==="; if (Test-Path $stderrLog) { Get-Content $stderrLog -Tail 30 }
    exit 2
}
Write-Host ("[g7] server READY in " + [int]$loadSec + "s")

$messages = @()
if ($SystemPrompt) { $messages += @{ role = "system"; content = $SystemPrompt } }
$messages += @{ role = "user"; content = $Prompt }
$warmupMessages = @()
if ($SystemPrompt) { $warmupMessages += @{ role = "system"; content = $SystemPrompt } }
$warmupMessages += @{ role = "user"; content = $effectiveWarmupPrompt }
$body = @{
    model = "deepseek-chat"
    messages = $messages
    max_tokens = $MaxTokens
    temperature = 0
    think = $false
} | ConvertTo-Json -Depth 5
$warmupBody = @{
    model = "deepseek-chat"
    messages = $warmupMessages
    max_tokens = $effectiveWarmupMaxTokens
    temperature = 0
    think = $false
} | ConvertTo-Json -Depth 5
$bodyBytes = [Text.Encoding]::UTF8.GetBytes($body)
$warmupBodyBytes = [Text.Encoding]::UTF8.GetBytes($warmupBody)

$results = @()
$warmupResult = $null
$httpOk = $false
$warmSec = 0.0
$uri = "http://127.0.0.1:" + $Port + "/v1/chat/completions"
try {
    if ($Warmup) {
        $tw = Get-Date
        $warmResp = Invoke-RestMethod -Uri $uri -Method Post -ContentType "application/json; charset=utf-8" -Body $warmupBodyBytes -TimeoutSec $TimeoutSec
        $warmSec = ((Get-Date) - $tw).TotalSeconds
        $warmContent = [string]$warmResp.choices[0].message.content
        $warmCompletionTokens = [int]$warmResp.usage.completion_tokens
        if ($warmCompletionTokens -le 0) {
            throw "Warmup response did not report a positive usage.completion_tokens value"
        }
        $warmBytes = [Text.Encoding]::UTF8.GetBytes($warmContent)
        $warmContentHash = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($warmBytes)).Replace("-", "").ToLowerInvariant()
        $warmupResult = [pscustomobject]@{
            seconds = [math]::Round($warmSec, 6)
            completion_tokens = $warmCompletionTokens
            content_sha256 = $warmContentHash
            content = $warmContent
        }
        if ($ExpectedWarmupContentSHA256 -and $warmContentHash -ine $ExpectedWarmupContentSHA256) {
            throw "Measurement failed: warmup output hash differs from expected baseline"
        }
        Write-Host ("[g7] warmup pass done in " + [math]::Round($warmSec,2) + "s")
    }
    for ($i = 1; $i -le $Repeats; $i++) {
        $t0 = Get-Date
        $resp = Invoke-RestMethod -Uri $uri -Method Post -ContentType "application/json; charset=utf-8" -Body $bodyBytes -TimeoutSec $TimeoutSec
        $genSec = ((Get-Date) - $t0).TotalSeconds
        $content = [string]$resp.choices[0].message.content
        $completionTokens = [int]$resp.usage.completion_tokens
        if ($completionTokens -le 0) {
            throw "Response $i did not report a positive usage.completion_tokens value"
        }
        $bytes = [Text.Encoding]::UTF8.GetBytes($content)
        $sha = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($bytes)).Replace("-", "").ToLowerInvariant()
        $results += [pscustomobject]@{
            repeat = $i
            seconds = [math]::Round($genSec, 6)
            completion_tokens = $completionTokens
            tokens_per_second = [math]::Round($completionTokens / $genSec, 6)
            content_sha256 = $sha
            content = $content
        }
        Write-Host ("[g7] repeat " + $i + ": " + $completionTokens + " tokens in " + [math]::Round($genSec, 3) + "s")
    }
    $httpOk = $true
} catch {
    $responseBody = ""
    if ($_.Exception.Response) {
        try {
            $responseStream = $_.Exception.Response.GetResponseStream()
            if ($responseStream) {
                $responseReader = New-Object System.IO.StreamReader($responseStream)
                $responseBody = $responseReader.ReadToEnd()
                $responseReader.Dispose()
            }
        } catch {}
    }
    Write-Host ("[g7] request FAILED: " + $_.Exception.Message + $(if ($responseBody) { " body=" + $responseBody } else { "" }))
}

if (-not $httpOk -and -not $proc.HasExited) { $proc.Kill() }
$stopped = $proc.WaitForExit(120000)
if (-not $stopped) {
    Write-Host "[g7] WARNING: graceful benchmark shutdown timed out; forcing owned server"
    if (-not $proc.HasExited) { $proc.Kill() }
    $stopped = $proc.WaitForExit(60000)
    if (-not $stopped) { throw "Owned ds4_server process did not exit after forced shutdown" }
}
Start-Sleep -Milliseconds 250
if ($telemetryProc -and -not $telemetryProc.HasExited) {
    $telemetryProc.WaitForExit(10000) | Out-Null
}
if ($telemetryProc -and -not $telemetryProc.HasExited) {
    $telemetryProc.Kill()
    $telemetryProc.WaitForExit(10000) | Out-Null
}

$runtimeSamples = @()
if (Test-Path -LiteralPath $runtimeTelemetryLog) {
    foreach ($line in Get-Content -LiteralPath $runtimeTelemetryLog) {
        if (-not $line.Trim()) { continue }
        try { $runtimeSamples += ($line | ConvertFrom-Json) } catch {}
    }
}
if ($runtimeSamples.Count -lt 2) {
    throw "Runtime telemetry failed closed: fewer than two valid samples"
}
function Get-G7Median([object[]]$Values) {
    $ordered = @($Values | Where-Object { $null -ne $_ } | Sort-Object)
    if ($ordered.Count -eq 0) { return $null }
    $middle = [int][math]::Floor($ordered.Count / 2)
    if (($ordered.Count % 2) -eq 1) { return [double]$ordered[$middle] }
    return ([double]$ordered[$middle - 1] + [double]$ordered[$middle]) / 2.0
}
$sharedSamples = @($runtimeSamples | ForEach-Object { $_.gpu_process_shared_bytes } | Where-Object { $null -ne $_ })
$dedicatedSamples = @($runtimeSamples | ForEach-Object { $_.gpu_process_dedicated_bytes } | Where-Object { $null -ne $_ })
$workingSamples = @($runtimeSamples | ForEach-Object { $_.working_set_bytes } | Where-Object { $null -ne $_ })
$privateSamples = @($runtimeSamples | ForEach-Object { $_.private_bytes } | Where-Object { $null -ne $_ })
$availableSamples = @($runtimeSamples | ForEach-Object { $_.windows_available_bytes } | Where-Object { $null -ne $_ })
$gpuUtilSamples = @($runtimeSamples | ForEach-Object { if ($_.nvidia) { $_.nvidia.utilization_percent } } | Where-Object { $null -ne $_ })
$vramSamples = @($runtimeSamples | ForEach-Object { if ($_.nvidia) { $_.nvidia.vram_used_mib } } | Where-Object { $null -ne $_ })
$powerSamples = @($runtimeSamples | ForEach-Object { if ($_.nvidia) { $_.nvidia.power_watts } } | Where-Object { $null -ne $_ })
if ($sharedSamples.Count -eq 0 -or $dedicatedSamples.Count -eq 0 -or
    $gpuUtilSamples.Count -eq 0 -or $vramSamples.Count -eq 0) {
    throw "Runtime telemetry failed closed: required WDDM/NVIDIA counters are missing"
}
$firstRuntimeSample = $runtimeSamples[0]
$lastRuntimeSample = $runtimeSamples[-1]
$runtimeElapsedSeconds = [double]$lastRuntimeSample.elapsed_seconds - [double]$firstRuntimeSample.elapsed_seconds
$runtimeSampleIntervals = @()
for ($sampleIndex = 1; $sampleIndex -lt $runtimeSamples.Count; $sampleIndex++) {
    $runtimeSampleIntervals += [double]$runtimeSamples[$sampleIndex].elapsed_seconds -
        [double]$runtimeSamples[$sampleIndex - 1].elapsed_seconds
}
$runtimeEffectiveIntervalSeconds = if ($runtimeSamples.Count -gt 1) {
    $runtimeElapsedSeconds / ($runtimeSamples.Count - 1)
} else { $null }
$runtimeTelemetry = [pscustomobject]@{
    path = $runtimeTelemetryLog
    requested_interval_ms = $TelemetryIntervalMs
    effective_interval_seconds = $runtimeEffectiveIntervalSeconds
    interval_median_seconds = Get-G7Median $runtimeSampleIntervals
    interval_min_seconds = if ($runtimeSampleIntervals.Count) { [double]($runtimeSampleIntervals | Measure-Object -Minimum).Minimum } else { $null }
    interval_max_seconds = if ($runtimeSampleIntervals.Count) { [double]($runtimeSampleIntervals | Measure-Object -Maximum).Maximum } else { $null }
    samples = $runtimeSamples.Count
    elapsed_seconds = [double]$lastRuntimeSample.elapsed_seconds
    gpu_process_shared_peak_bytes = if ($sharedSamples.Count) { [Int64]($sharedSamples | Measure-Object -Maximum).Maximum } else { $null }
    gpu_process_shared_median_bytes = Get-G7Median $sharedSamples
    gpu_process_dedicated_peak_bytes = if ($dedicatedSamples.Count) { [Int64]($dedicatedSamples | Measure-Object -Maximum).Maximum } else { $null }
    gpu_process_dedicated_median_bytes = Get-G7Median $dedicatedSamples
    process_working_set_peak_bytes = if ($workingSamples.Count) { [Int64]($workingSamples | Measure-Object -Maximum).Maximum } else { $null }
    process_private_peak_bytes = if ($privateSamples.Count) { [Int64]($privateSamples | Measure-Object -Maximum).Maximum } else { $null }
    windows_available_min_bytes = if ($availableSamples.Count) { [Int64]($availableSamples | Measure-Object -Minimum).Minimum } else { $null }
    gpu_utilization_median_percent = Get-G7Median $gpuUtilSamples
    gpu_utilization_peak_percent = if ($gpuUtilSamples.Count) { [double]($gpuUtilSamples | Measure-Object -Maximum).Maximum } else { $null }
    vram_used_peak_mib = if ($vramSamples.Count) { [double]($vramSamples | Measure-Object -Maximum).Maximum } else { $null }
    power_median_watts = Get-G7Median $powerSamples
    win32_process_read_transfer_delta_bytes = if ($null -ne $firstRuntimeSample.read_transfer_bytes -and $null -ne $lastRuntimeSample.read_transfer_bytes) { [Int64]$lastRuntimeSample.read_transfer_bytes - [Int64]$firstRuntimeSample.read_transfer_bytes } else { $null }
    win32_process_write_transfer_delta_bytes = if ($null -ne $firstRuntimeSample.write_transfer_bytes -and $null -ne $lastRuntimeSample.write_transfer_bytes) { [Int64]$lastRuntimeSample.write_transfer_bytes - [Int64]$firstRuntimeSample.write_transfer_bytes } else { $null }
    win32_process_transfer_counters_include_mmap_pageins = $false
    mmap_backed_file_io_measured = $false
    page_fault_delta = if ($null -ne $firstRuntimeSample.page_faults -and $null -ne $lastRuntimeSample.page_faults) { [Int64]$lastRuntimeSample.page_faults - [Int64]$firstRuntimeSample.page_faults } else { $null }
}

# Analyze stderr
$evicts = 0; $selLoads = 0; $lastSel = ""; $streamsExpert = 0; $streamsHot = 0
$observedIoQD = 1; $overlappedIoObserved = $false; $overlappedIoFallbacks = 0
$cacheCalls = 0; $cacheLastLayer = -1; $cacheLastCompact = 0
$cacheCapacity = 0; $cacheCount = 0; $cacheHits = 0; $cacheMisses = 0
$cacheAdmissions = 0; $cacheEvictions = 0; $cacheDirect = 0
$expertTieringFinalObserved = $false; $expertTieringFinalLineCount = 0; $expertTieringControlLineCount = 0
$expertTieringModeObserved = ""; $expertTieringCalls = 0; $expertTieringSelected = 0
$expertTieringPolicyObserved = ""; $expertTieringClockCalls = 0; $expertTieringReplacementBudget = 0
$expertTieringMinFrequency = 0; $expertTieringHysteresis = 0.0
$expertTieringCold = 0; $expertTieringRamHits = 0; $expertTieringVramHits = 0
$expertTieringColdToRam = 0; $expertTieringColdToVram = 0; $expertTieringRamToWarm = 0
$expertTieringVramPromotions = 0; $expertTieringVramDemotions = 0; $expertTieringRamEvictions = 0
$expertTieringRamAdmitSkips = 0; $expertTieringTransient = 0; $expertTieringFailures = 0
$expertTieringSsdBytes = 0; $expertTieringRamH2DBytes = 0
$expertTieringStatesSsd = 0; $expertTieringStatesProbation = 0
$expertTieringStatesWarm = 0; $expertTieringStatesVram = 0
$expertTieringMassSum = 0.0; $expertTieringLfruTop = 0.0
$expertTieringComposeObserved = $false; $expertTieringComposeFlag = 0
$expertTieringSnapshotGeneration = 0; $expertTieringSnapshotBackingEntries = 0
$expertTieringSnapshotBackingHits = 0; $expertTieringSnapshotBackingMisses = 0
$expertTieringSnapshotToVramBytes = 0; $expertTieringForbiddenColdSsdToVram = 0
$expertTieringPolicyEpochs = 0; $expertTieringPolicyFreePromotions = 0
$expertTieringPolicyReplacements = 0; $expertTieringPolicyMinFrequencySkips = 0
$expertTieringPolicyBudgetSkips = 0; $expertTieringPolicyScoreSkips = 0
$mixedDirectObserved = $false; $mixedDirectCalls = 0
$mixedDirectCacheRoutes = 0; $mixedDirectCompactRoutes = 0
$routeProfileObserved = $false; $routeProfileCalls = 0
$routeProfileD2HMs = 0.0; $routeProfileObserveMs = 0.0
$routeProfileMapMs = 0.0; $routeProfileTransportMs = 0.0
$routeProfilePublishMs = 0.0
$gpuRoutesObserved = $false; $gpuRoutesCalls = 0; $gpuRoutesSplitCalls = 0; $gpuRoutesAllHit = 0
$gpuRoutesWorkerJobs = 0; $gpuRoutesMissExperts = 0; $gpuRoutesErrors = 0
$gpuRoutesWorkerMs = 0.0; $gpuRoutesResolveMs = 0.0; $gpuRoutesWaitMs = 0.0
$overlapSharedObserved = $false
$overlapSharedFullObserved = $false
$spexObserved = $false; $spexObservedStage = ""; $spexObservedCap = 0; $spexScheduled = 0; $spexReady = 0; $spexNotReady = 0
$spexLayers = 0; $spexActual = 0; $spexPredicted = 0; $spexHits = 0; $spexRecall = 0.0
$spexPrecision = 0.0; $spexNoActual = 0
$spexDisabled = $false; $spexFusedObserved = $false; $spexRingObserved = 0
$spexLate = 0; $spexRingFull = 0; $spexStale = 0
$spexPrefetchObserved = $false; $spexPrefetchKObserved = 0; $spexPrefetchSlotsObserved = 0
$spexPrefetchFinalObserved = $false; $spexPrefetchSubmitted = 0; $spexPrefetchDropped = 0
$spexPrefetchLoaded = 0; $spexPrefetchMatched = 0; $spexPrefetchHits = 0; $spexPrefetchNoHits = 0
$spexPrefetchLate = 0; $spexPrefetchCanceled = 0; $spexPrefetchPoisoned = 0
$spexPrefetchErrors = 0; $spexPrefetchDisabled = $false
$spexPrefetchBytesRead = 0; $spexPrefetchBytesUsed = 0
$spexCpuProbeFinalObserved = $false; $spexCpuProbeLineCount = 0; $spexCpuProbeKObserved = 0
$spexCpuProbeSubmitted = 0; $spexCpuProbeDropped = 0; $spexCpuProbeCompleted = 0
$spexCpuProbePredicted = 0; $spexCpuProbeMatched = 0
$spexCpuProbeReadyAtTransport = 0; $spexCpuProbeUsefulReady = 0; $spexCpuProbeFailures = 0
$spexCpuProbeD2HWaitMs = 0.0; $spexCpuProbeCpuMs = 0.0; $spexCpuProbeQueueMs = 0.0
$spexCpuProbeChecksum = 0.0
$arenaObserverArmed = $false; $arenaObserverWindowObserved = 0
$arenaObserverMinHitsObserved = 0; $arenaObserverGrowIntervalObserved = 0
$prefillMassArmed = $false; $prefillMassFinalized = $false
$prefillMassLayers = 0; $prefillMassRowsMin = 0; $prefillMassRowsMax = 0
$prefillMassRoutedSlots = 0; $prefillMassUnique = 0
$prefillMassCandidate = 0; $prefillMassCapacity = 0
$prefillMassTotal = 0.0; $prefillMassCandidateMass = 0.0
$prefillMassCoverage = 0.0; $prefillMassCutoff = 0.0
$prefillMassPolicy = "not_observed"; $prefillMassResidency = "not_observed"
$prefillMassDecodeTokens = 0; $prefillMassDecodeSlots = 0; $prefillMassDecodeHits = 0; $prefillMassDecodeHitRate = 0.0
$prefillMassWrapObserved = $false; $prefillMassWrapEventCount = 0
$prefillMassWrapResult = "not_observed"; $prefillMassWrapReason = "not_observed"
$prefillMassWrapCandidate = 0; $prefillMassWrapLoads = 0; $prefillMassWrapWorkers = 0
$prefillMassWrapSeconds = 0.0; $prefillMassWrapSnapshotBefore = 0; $prefillMassWrapSnapshotAfter = 0
$prefillMassWrapResidentBefore = 0; $prefillMassWrapResidentAfter = 0
$prefillMassWrapGeneration = 0; $prefillMassWrapPreloaded = -1
$prefillMassWrapRouter = "not_observed"; $prefillMassWrapMask = "not_observed"
$prefillMassComposeObserved = $false; $prefillMassComposeEventCount = 0
$prefillMassComposeHashLayers = 0; $prefillMassComposeHashSeedEntries = 0
$prefillMassComposeRankedEntries = 0; $prefillMassComposeTotalCandidate = 0
$prefillMassComposeCapacity = 0
$reapMassArmed = $false; $reapMassResultObserved = $false
$reapMassWindowObserved = 0; $reapMassTopObserved = 0
$reapMassFirstLayer = 0; $reapMassLastLayer = 0
$reapMassTransport = "not_observed"
$reapMassTokens = 0; $reapMassObservedSlots = 0; $reapMassUnique = 0
$reapMassTopMass = 0.0; $reapMassTouched = 0
$reapMassWrapArmed = $false; $reapMassWrapGrowIntervalObserved = 0
$reapMassWrapHysteresisObserved = 0.0; $reapMassWrapCapacity = 0
$reapMassWrapRouterArmed = "not_observed"; $reapMassWrapMaskArmed = "not_observed"
$reapMassWrapPolicyArmed = "not_observed"
$reapMassWrapObserved = $false; $reapMassWrapEventCount = 0
$reapMassWrapPublicationCount = 0; $reapMassWrapSkippedCount = 0
$reapMassWrapFailureCount = 0
$reapMassWrapEntrants = 0; $reapMassWrapVictims = 0; $reapMassWrapLoads = 0
$reapMassWrapSeconds = 0.0; $reapMassWrapLastResult = "not_observed"
$reapMassWrapLastReason = "not_observed"; $reapMassWrapLastResidentBefore = 0
$reapMassWrapLastResidentAfter = 0; $reapMassWrapLastGeneration = 0
$reapMassWrapLastTokens = 0; $reapMassWrapLastFreeBefore = 0
$reapMassWrapLastSnapshotBefore = 0; $reapMassWrapLastSnapshotAfter = 0
$reapMassWrapLastWorkers = 0; $reapMassWrapLastRouter = "not_observed"
$reapMassWrapLastMask = "not_observed"
$reapMaskReloadObserved = $false; $reapMaskAppliedObserved = $false
$reapMaskPathObserved = ""; $reapMaskReloadPruned = 0; $reapMaskReloadLayers = 0
$reapMaskAppliedPruned = 0; $reapMaskAppliedLayers = 0; $reapMaskBiasLayers = 0
$reapMaskRangesUpdated = 0; $reapMaskRangesCreated = 0; $reapMaskRangesFailed = 0
$arenaObserverFirstLayer = 0; $arenaObserverLastLayer = 0
$arenaObserverTokens = 0; $arenaObserverResident = 0
$arenaWrapObserved = $false; $arenaWrapLoads = 0; $arenaWrapWorkers = 0
$arenaWrapSeconds = 0.0; $arenaWrapGeneration = 0
$arenaWrapPreloaded = 0; $arenaWrapMirrorGiB = 0.0
$arenaVerifyWorkers = 0; $arenaVerifySeconds = 0.0
$arenaObserverResultObserved = $false; $arenaObserverResult = "not_observed"
$arenaObserverPublicationCount = 0; $arenaWrapPublicationCount = 0
$arenaCarryObserved = $false; $arenaCarryLineCount = 0; $arenaCarryRequest = 0
$arenaCarryModeObserved = "not_observed"; $arenaCarrySnapshot = 0
$arenaCarryResident = 0; $arenaCarryLookupObserved = "not_observed"
$arenaCarryObserverObserved = "not_observed"
$arenaCarryEvents = @()
$arenaGrowthPublications = 0; $arenaGrowthSkips = 0
$arenaGrowthEvents = @()
$contextObserved = 0; $prefillChunkObserved = 0
$rawKvRowsObserved = 0; $compressedKvRowsObserved = 0
$prefillUnionObserved = $false; $prefillUnionCalls = 0; $prefillUnionTokens = 0
$prefillUnionSelectedSlots = 0; $prefillUnionUniqueExperts = 0; $prefillUnionDedupRatio = 0.0
$prefillUnionMaxTokens = 0; $prefillUnionMaxUnion = 0; $prefillUnionArenaExperts = 0
$prefillUnionCacheHits = 0; $prefillUnionCacheAdmissions = 0; $prefillUnionDirectExperts = 0
$prefillUnionSpexExperts = 0; $prefillUnionNonresidentExperts = 0
$prefillUnionSourceSpanBytes = 0; $prefillUnionArenaH2DBytes = 0
$prefillUnionCacheD2DBytes = 0; $prefillUnionUploadSyncs = 0
$prefillWavesObserved = $false; $prefillWaveActivations = 0; $prefillWaveLayers = 0
$prefillWaveCount = 0; $prefillWaveMaxExperts = 0; $prefillWaveActivePairs = 0
$prefillWaveUniqueExperts = 0; $prefillWaveUploadWaits = 0; $prefillWaveFailures = 0
$prefillWaveOverlapObserved = $false; $prefillWaveOverlapActivations = 0
$prefillWaveOverlapLayers = 0; $prefillWaveOverlapWaves = 0
$prefillWaveOverlapReuseWaits = 0; $prefillWaveOverlapComputeRecords = 0
$prefillWaveOverlapFailures = 0
$arenaFinalObserved = $false; $arenaFinalHits = 0; $arenaFinalMisses = 0
$arenaFinalFatal = 0; $arenaFinalUploadedGiB = 0.0
$arenaAllocatedBytes = 0; $arenaSlotBytes = 0; $arenaAllocatedSlots = 0
$serverRunsAll = @()
if (Test-Path $stderrLog) {
    $lines = Get-Content $stderrLog

    # Keep server-reported decode throughput separate from HTTP wall time, which
    # also includes prefill/TTFT. A request block starts at "prompt start" and
    # the last decoding line in that block is the cumulative decode average.
    $serverBlock = $null
    foreach ($line in $lines) {
        if ($line -match "prompt start") {
            if ($null -ne $serverBlock -and $serverBlock.generated_tokens -gt 0) {
                $serverRunsAll += $serverBlock
            }
            $serverBlock = [pscustomobject]@{
                request_index = $serverRunsAll.Count + 1
                generated_tokens = 0
                server_decode_seconds = 0.0
                server_chunk_tokens_per_second = 0.0
                server_avg_tokens_per_second = 0.0
                finish_reason = ""
                server_total_seconds = 0.0
                server_prefill_ttft_seconds = 0.0
            }
            continue
        }
        if ($null -eq $serverBlock) { continue }
        if ($line -match "gen=(\d+) decoding chunk=([0-9.]+) t/s avg=([0-9.]+) t/s ([0-9.]+)s") {
            $serverBlock.generated_tokens = [int]$Matches[1]
            $serverBlock.server_chunk_tokens_per_second = [double]$Matches[2]
            $serverBlock.server_avg_tokens_per_second = [double]$Matches[3]
            $serverBlock.server_decode_seconds = [double]$Matches[4]
        }
        if ($line -match "gen=(\d+) finish=([^ ]+) ([0-9.]+)s") {
            $serverBlock.generated_tokens = [int]$Matches[1]
            $serverBlock.finish_reason = $Matches[2]
            $serverBlock.server_total_seconds = [double]$Matches[3]
            $serverBlock.server_prefill_ttft_seconds = [math]::Max(0.0, $serverBlock.server_total_seconds - $serverBlock.server_decode_seconds)
        }
    }
    if ($null -ne $serverBlock -and $serverBlock.generated_tokens -gt 0) {
        $serverRunsAll += $serverBlock
    }

    $evLine = $lines | Where-Object { $_ -match "evicts=(\d+)" } | Select-Object -Last 1
    if ($evLine -and $evLine -match "evicts=(\d+)") { $evicts = [int]$Matches[1] }
    $selLines = $lines | Where-Object { $_ -match "MoE selected-load" }
    $selLoads = ($selLines | Measure-Object).Count
    if ($selLines) { $lastSel = ($selLines | Select-Object -Last 1) }
    $fd = $lines | Where-Object { $_ -match "fd-cached " }
    $streamsExpert = ($fd | Where-Object { $_ -match "fd-cached moe_" } | Measure-Object).Count
    $streamsHot = ($fd | Measure-Object).Count - $streamsExpert
    $ioLine = $lines | Where-Object { $_ -match "MoE overlapped read succeeded queue depth=(\d+)" } | Select-Object -Last 1
    if ($ioLine -and $ioLine -match "MoE overlapped read succeeded queue depth=(\d+)") {
        $observedIoQD = [int]$Matches[1]
        $overlappedIoObserved = $true
    }
    $overlappedIoFallbacks = ($lines | Where-Object { $_ -match "MoE overlapped read failed; selected-load fallback requested" } | Measure-Object).Count
    $prefillUnionLines = @($lines | Where-Object { $_ -match "^\s*ds4: \[prefill-union\] final " })
    if ($prefillUnionLines.Count -gt 0) {
        $prefillUnionPattern = "^ds4: \[prefill-union\] final calls=(\d+) tokens=(\d+) selected_slots=(\d+) unique_experts=(\d+) dedup_ratio=([0-9.eE+-]+) max_tokens=(\d+) max_union=(\d+) arena_experts=(\d+) cache_hits=(\d+) cache_admissions=(\d+) direct_experts=(\d+) spex_experts=(\d+) nonresident_experts=(\d+) source_span_bytes=(\d+) arena_h2d_bytes=(\d+) cache_d2d_bytes=(\d+) upload_syncs=(\d+)$"
        foreach ($prefillUnionLine in $prefillUnionLines) {
            if ($prefillUnionLine -notmatch $prefillUnionPattern) {
                throw "Prefill union measurement failed: final line format mismatch"
            }
            $prefillUnionCalls += [uint64]$Matches[1]; $prefillUnionTokens += [uint64]$Matches[2]
            $prefillUnionSelectedSlots += [uint64]$Matches[3]; $prefillUnionUniqueExperts += [uint64]$Matches[4]
            $prefillUnionMaxTokens = [math]::Max($prefillUnionMaxTokens, [uint32]$Matches[6])
            $prefillUnionMaxUnion = [math]::Max($prefillUnionMaxUnion, [uint32]$Matches[7])
            $prefillUnionArenaExperts += [uint64]$Matches[8]; $prefillUnionCacheHits += [uint64]$Matches[9]
            $prefillUnionCacheAdmissions += [uint64]$Matches[10]; $prefillUnionDirectExperts += [uint64]$Matches[11]
            $prefillUnionSpexExperts += [uint64]$Matches[12]; $prefillUnionNonresidentExperts += [uint64]$Matches[13]
            $prefillUnionSourceSpanBytes += [uint64]$Matches[14]; $prefillUnionArenaH2DBytes += [uint64]$Matches[15]
            $prefillUnionCacheD2DBytes += [uint64]$Matches[16]; $prefillUnionUploadSyncs += [uint64]$Matches[17]
        }
        $prefillUnionObserved = $true
        if ($prefillUnionUniqueExperts -gt 0) {
            $prefillUnionDedupRatio = $prefillUnionSelectedSlots / [double]$prefillUnionUniqueExperts
        }
    }
    if ($PrefillUnionStats -and -not $prefillUnionObserved) {
        throw "Prefill union stats were requested but no successful batched prefill call was reported"
    }
    $prefillWaveLines = @($lines | Where-Object { $_ -match "^\s*ds4: \[prefill-waves\] final " })
    if ($prefillWaveLines.Count -gt 0) {
        $prefillWavePattern = "^ds4: \[prefill-waves\] final activations=(\d+) layers=(\d+) waves=(\d+) max_wave=(\d+) active_pairs=(\d+) unique_experts=(\d+) upload_waits=(\d+) failures=(\d+)$"
        foreach ($prefillWaveLine in $prefillWaveLines) {
            if ($prefillWaveLine -notmatch $prefillWavePattern) {
                throw "Prefill wave measurement failed: final line format mismatch"
            }
            $prefillWaveActivations += [uint64]$Matches[1]
            $prefillWaveLayers += [uint64]$Matches[2]
            $prefillWaveCount += [uint64]$Matches[3]
            $prefillWaveMaxExperts = [math]::Max($prefillWaveMaxExperts, [uint32]$Matches[4])
            $prefillWaveActivePairs += [uint64]$Matches[5]
            $prefillWaveUniqueExperts += [uint64]$Matches[6]
            $prefillWaveUploadWaits += [uint64]$Matches[7]
            $prefillWaveFailures += [uint64]$Matches[8]
        }
        $prefillWavesObserved = $true
    }
    if ($PrefillWaves -and $PrefillWaveForceExperts -gt 0 -and
        -not $prefillWavesObserved) {
        throw "Prefill waves were forced but no successful wave activation was reported"
    }
    $prefillWaveOverlapLines = @($lines | Where-Object { $_ -match "^\s*ds4: \[prefill-wave-overlap\] final " })
    if ($prefillWaveOverlapLines.Count -gt 0) {
        $prefillWaveOverlapPattern = "^ds4: \[prefill-wave-overlap\] final activations=(\d+) layers=(\d+) waves=(\d+) reuse_waits=(\d+) compute_records=(\d+) failures=(\d+)$"
        foreach ($prefillWaveOverlapLine in $prefillWaveOverlapLines) {
            if ($prefillWaveOverlapLine -notmatch $prefillWaveOverlapPattern) {
                throw "Prefill wave overlap measurement failed: final line format mismatch"
            }
            $prefillWaveOverlapActivations += [uint64]$Matches[1]
            $prefillWaveOverlapLayers += [uint64]$Matches[2]
            $prefillWaveOverlapWaves += [uint64]$Matches[3]
            $prefillWaveOverlapReuseWaits += [uint64]$Matches[4]
            $prefillWaveOverlapComputeRecords += [uint64]$Matches[5]
            $prefillWaveOverlapFailures += [uint64]$Matches[6]
        }
        $prefillWaveOverlapObserved = $true
    }
    if ($PrefillWaveDoubleBuffer -and -not $prefillWaveOverlapObserved) {
        throw "Prefill wave double buffering was requested but no successful overlap activation was reported"
    }
    $overlapSharedObserved = [bool]($lines | Where-Object { $_ -match "CUDA MoE shared-overlap consumed" } | Select-Object -First 1)
    $overlapSharedFullObserved = [bool]($lines | Where-Object { $_ -match "CUDA MoE full shared-overlap consumed" } | Select-Object -First 1)
    $spexLine = $lines | Where-Object { $_ -match "\[spex-dry\]" } | Select-Object -Last 1
    $spexActiveLine = $lines | Where-Object { $_ -match "SPEX hidden GPU dry-run active" } | Select-Object -Last 1
    if ($spexActiveLine -and $spexActiveLine -match "fused=(\d+)") { $spexFusedObserved = ([int]$Matches[1] -ne 0) }
    if ($spexActiveLine -and $spexActiveLine -match "ring=(\d+)") { $spexRingObserved = [int]$Matches[1] }
    $spexDisabled = [bool]($lines | Where-Object { $_ -match "SPEX hidden dry-run disabled" } | Select-Object -First 1)
    if ($spexLine -and $spexLine -match "stage=([a-z]+) cap=(\d+) scheduled=(\d+) ready=(\d+) not_ready=(\d+) layers=(\d+) actual=(\d+) predicted=(\d+) hits=(\d+) recall=([0-9.]+) precision=([0-9.]+) no_actual=(\d+)") {
        $spexObserved = $true; $spexObservedStage = $Matches[1]; $spexObservedCap = [int]$Matches[2]
        $spexScheduled = [long]$Matches[3]; $spexReady = [long]$Matches[4]; $spexNotReady = [long]$Matches[5]
        $spexLayers = [long]$Matches[6]; $spexActual = [long]$Matches[7]; $spexPredicted = [long]$Matches[8]
        $spexHits = [long]$Matches[9]; $spexRecall = [double]$Matches[10]
        $spexPrecision = [double]$Matches[11]; $spexNoActual = [long]$Matches[12]
    }
    if ($spexLine -and $spexLine -match "ring=(\d+) late=(\d+) ring_full=(\d+) stale=(\d+)") {
        $spexRingObserved = [int]$Matches[1]; $spexLate = [long]$Matches[2]
        $spexRingFull = [long]$Matches[3]; $spexStale = [long]$Matches[4]
    }
    $spexPrefetchActiveLine = $lines | Where-Object { $_ -match "SPEX prefetch active k=(\d+) slots=(\d+)" } | Select-Object -Last 1
    if ($spexPrefetchActiveLine -and $spexPrefetchActiveLine -match "SPEX prefetch active k=(\d+) slots=(\d+)") {
        $spexPrefetchObserved = $true
        $spexPrefetchKObserved = [int]$Matches[1]
        $spexPrefetchSlotsObserved = [int]$Matches[2]
    }
    $spexPrefetchFinalLine = $lines | Where-Object { $_ -match "\[spex-prefetch\] final" } | Select-Object -Last 1
    if ($spexPrefetchFinalLine -and $spexPrefetchFinalLine -match "submitted=(\d+) dropped=(\d+) loaded=(\d+) matched=(\d+) consumed=(\d+) no_hits=(\d+) late=(\d+) canceled=(\d+) poisoned=(\d+) errors=(\d+) disabled=(\d+) bytes_read=(\d+) bytes_used=(\d+)") {
        $spexPrefetchFinalObserved = $true
        $spexPrefetchSubmitted = [long]$Matches[1]; $spexPrefetchDropped = [long]$Matches[2]
        $spexPrefetchLoaded = [long]$Matches[3]; $spexPrefetchMatched = [long]$Matches[4]
        $spexPrefetchHits = [long]$Matches[5]; $spexPrefetchNoHits = [long]$Matches[6]
        $spexPrefetchLate = [long]$Matches[7]; $spexPrefetchCanceled = [long]$Matches[8]
        $spexPrefetchPoisoned = [long]$Matches[9]; $spexPrefetchErrors = [long]$Matches[10]
        $spexPrefetchDisabled = ([int]$Matches[11] -ne 0)
        $spexPrefetchBytesRead = [long]$Matches[12]; $spexPrefetchBytesUsed = [long]$Matches[13]
    }
    $cacheReadyLine = $lines | Where-Object { $_ -match "resident expert cache ready: (\d+)/(\d+) experts" } | Select-Object -Last 1
    if ($cacheReadyLine -and $cacheReadyLine -match "resident expert cache ready: (\d+)/(\d+) experts") {
        $cacheCapacity = [int]$Matches[1]
    }
    $cacheLine = $lines | Where-Object { $_ -match "\[moecache\]" } | Select-Object -Last 1
    if ($cacheLine -and $cacheLine -match "calls=(\d+)(?: layer=(\d+) compact=(\d+))? cap=(\d+) count=(\d+) hits=(\d+) misses=(\d+).*admissions=(\d+) evictions=(\d+) direct=(\d+)") {
        $cacheCalls = [long]$Matches[1]
        if ($Matches[2]) { $cacheLastLayer = [int]$Matches[2]; $cacheLastCompact = [int]$Matches[3] }
        $cacheCapacity = [int]$Matches[4]; $cacheCount = [int]$Matches[5]
        $cacheHits = [long]$Matches[6]; $cacheMisses = [long]$Matches[7]; $cacheAdmissions = [long]$Matches[8]
        $cacheEvictions = [long]$Matches[9]; $cacheDirect = [long]$Matches[10]
    }
    $expertTieringControlLineCount = @($lines | Where-Object { $_ -match "\[expert-tiering\] control" }).Count
    $expertTieringFinalLines = @($lines | Where-Object { $_ -match "^\s*ds4: \[expert-tiering\] final " })
    $expertTieringFinalLineCount = $expertTieringFinalLines.Count
    if ($expertTieringFinalLineCount -gt 0) {
        $expertTieringFinalLine = $expertTieringFinalLines | Select-Object -Last 1
        $numberPattern = "([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)"
        $expertTieringFinalPattern = "^ds4: \[expert-tiering\] final mode=(off|observe|enforce) policy=(second-touch|mass-lfru) clock_calls=(\d+) replacement_budget=(\d+) min_frequency=(\d+) hysteresis=" + $numberPattern + " calls=(\d+) selected=(\d+) cold=(\d+) ram_hits=(\d+) vram_hits=(\d+) cold_to_ram=(\d+) cold_to_vram=(\d+) ram_to_warm=(\d+) vram_promotions=(\d+) vram_demotions=(\d+) ram_evictions=(\d+) ram_admit_skips=(\d+) transient=(\d+) failures=(\d+) ssd_bytes=(\d+) ram_h2d_bytes=(\d+) policy_epochs=(\d+) policy_free_promotions=(\d+) policy_replacements=(\d+) policy_min_frequency_skips=(\d+) policy_budget_skips=(\d+) policy_score_skips=(\d+) states_ssd=(\d+) states_probation=(\d+) states_warm=(\d+) states_vram=(\d+) mass_sum=" + $numberPattern + " lfru_top=" + $numberPattern + "$"
        $expertTieringComposeFinalPattern = "^ds4: \[expert-tiering\] final mode=(off|observe|enforce) policy=(second-touch|mass-lfru) compose_prefill_mass_tiering=(\d+) snapshot_generation=(\d+) snapshot_backing_entries=(\d+) snapshot_backing_hits=(\d+) snapshot_backing_misses=(\d+) snapshot_to_vram_bytes=(\d+) forbidden_cold_ssd_to_vram=(\d+) clock_calls=(\d+) replacement_budget=(\d+) min_frequency=(\d+) hysteresis=" + $numberPattern + " calls=(\d+) selected=(\d+) cold=(\d+) ram_hits=(\d+) vram_hits=(\d+) cold_to_ram=(\d+) cold_to_vram=(\d+) ram_to_warm=(\d+) vram_promotions=(\d+) vram_demotions=(\d+) ram_evictions=(\d+) ram_admit_skips=(\d+) transient=(\d+) failures=(\d+) ssd_bytes=(\d+) ram_h2d_bytes=(\d+) policy_epochs=(\d+) policy_free_promotions=(\d+) policy_replacements=(\d+) policy_min_frequency_skips=(\d+) policy_budget_skips=(\d+) policy_score_skips=(\d+) states_ssd=(\d+) states_probation=(\d+) states_warm=(\d+) states_vram=(\d+) mass_sum=" + $numberPattern + " lfru_top=" + $numberPattern + "$"
        if ($expertTieringFinalLine -match $expertTieringComposeFinalPattern) {
            $expertTieringFinalObserved = $true
            $expertTieringComposeObserved = $true
            $expertTieringModeObserved = $Matches[1]
            $expertTieringPolicyObserved = $Matches[2]
            $expertTieringComposeFlag = [uint32]$Matches[3]
            $expertTieringSnapshotGeneration = [uint64]$Matches[4]
            $expertTieringSnapshotBackingEntries = [uint32]$Matches[5]
            $expertTieringSnapshotBackingHits = [uint64]$Matches[6]
            $expertTieringSnapshotBackingMisses = [uint64]$Matches[7]
            $expertTieringSnapshotToVramBytes = [uint64]$Matches[8]
            $expertTieringForbiddenColdSsdToVram = [uint64]$Matches[9]
            $expertTieringClockCalls = [uint32]$Matches[10]; $expertTieringReplacementBudget = [uint32]$Matches[11]
            $expertTieringMinFrequency = [uint32]$Matches[12]
            $expertTieringHysteresis = [double]::Parse($Matches[13], [Globalization.CultureInfo]::InvariantCulture)
            $expertTieringCalls = [uint64]$Matches[14]; $expertTieringSelected = [uint64]$Matches[15]
            $expertTieringCold = [uint64]$Matches[16]; $expertTieringRamHits = [uint64]$Matches[17]
            $expertTieringVramHits = [uint64]$Matches[18]; $expertTieringColdToRam = [uint64]$Matches[19]
            $expertTieringColdToVram = [uint64]$Matches[20]; $expertTieringRamToWarm = [uint64]$Matches[21]
            $expertTieringVramPromotions = [uint64]$Matches[22]; $expertTieringVramDemotions = [uint64]$Matches[23]
            $expertTieringRamEvictions = [uint64]$Matches[24]; $expertTieringRamAdmitSkips = [uint64]$Matches[25]
            $expertTieringTransient = [uint64]$Matches[26]; $expertTieringFailures = [uint64]$Matches[27]
            $expertTieringSsdBytes = [uint64]$Matches[28]; $expertTieringRamH2DBytes = [uint64]$Matches[29]
            $expertTieringPolicyEpochs = [uint64]$Matches[30]
            $expertTieringPolicyFreePromotions = [uint64]$Matches[31]
            $expertTieringPolicyReplacements = [uint64]$Matches[32]
            $expertTieringPolicyMinFrequencySkips = [uint64]$Matches[33]
            $expertTieringPolicyBudgetSkips = [uint64]$Matches[34]
            $expertTieringPolicyScoreSkips = [uint64]$Matches[35]
            $expertTieringStatesSsd = [uint32]$Matches[36]; $expertTieringStatesProbation = [uint32]$Matches[37]
            $expertTieringStatesWarm = [uint32]$Matches[38]; $expertTieringStatesVram = [uint32]$Matches[39]
            $expertTieringMassSum = [double]::Parse($Matches[40], [Globalization.CultureInfo]::InvariantCulture)
            $expertTieringLfruTop = [double]::Parse($Matches[41], [Globalization.CultureInfo]::InvariantCulture)
        } elseif ($expertTieringFinalLine -notmatch $expertTieringFinalPattern) {
            throw "Expert tiering measurement failed: final line format mismatch"
        } else {
            $expertTieringFinalObserved = $true
            $expertTieringModeObserved = $Matches[1]
            $expertTieringPolicyObserved = $Matches[2]
            $expertTieringClockCalls = [uint32]$Matches[3]; $expertTieringReplacementBudget = [uint32]$Matches[4]
            $expertTieringMinFrequency = [uint32]$Matches[5]
            $expertTieringHysteresis = [double]::Parse($Matches[6], [Globalization.CultureInfo]::InvariantCulture)
            $expertTieringCalls = [uint64]$Matches[7]; $expertTieringSelected = [uint64]$Matches[8]
            $expertTieringCold = [uint64]$Matches[9]; $expertTieringRamHits = [uint64]$Matches[10]
            $expertTieringVramHits = [uint64]$Matches[11]; $expertTieringColdToRam = [uint64]$Matches[12]
            $expertTieringColdToVram = [uint64]$Matches[13]; $expertTieringRamToWarm = [uint64]$Matches[14]
            $expertTieringVramPromotions = [uint64]$Matches[15]; $expertTieringVramDemotions = [uint64]$Matches[16]
            $expertTieringRamEvictions = [uint64]$Matches[17]; $expertTieringRamAdmitSkips = [uint64]$Matches[18]
            $expertTieringTransient = [uint64]$Matches[19]; $expertTieringFailures = [uint64]$Matches[20]
            $expertTieringSsdBytes = [uint64]$Matches[21]; $expertTieringRamH2DBytes = [uint64]$Matches[22]
            $expertTieringPolicyEpochs = [uint64]$Matches[23]
            $expertTieringPolicyFreePromotions = [uint64]$Matches[24]
            $expertTieringPolicyReplacements = [uint64]$Matches[25]
            $expertTieringPolicyMinFrequencySkips = [uint64]$Matches[26]
            $expertTieringPolicyBudgetSkips = [uint64]$Matches[27]
            $expertTieringPolicyScoreSkips = [uint64]$Matches[28]
            $expertTieringStatesSsd = [uint32]$Matches[29]; $expertTieringStatesProbation = [uint32]$Matches[30]
            $expertTieringStatesWarm = [uint32]$Matches[31]; $expertTieringStatesVram = [uint32]$Matches[32]
            $expertTieringMassSum = [double]::Parse($Matches[33], [Globalization.CultureInfo]::InvariantCulture)
            $expertTieringLfruTop = [double]::Parse($Matches[34], [Globalization.CultureInfo]::InvariantCulture)
        }
    }
    $mixedDirectLines = $lines | Where-Object { $_ -match "CUDA MoE mixed direct layer=(\d+) cache_routes=(\d+) compact_routes=(\d+)" }
    foreach ($mixedDirectLine in $mixedDirectLines) {
        if ($mixedDirectLine -match "CUDA MoE mixed direct layer=(\d+) cache_routes=(\d+) compact_routes=(\d+)") {
            $mixedDirectObserved = $true
            $mixedDirectCalls++
            $mixedDirectCacheRoutes += [long]$Matches[2]
            $mixedDirectCompactRoutes += [long]$Matches[3]
        }
    }
    $routeProfileLine = $lines | Where-Object { $_ -match "\[routeprof\]" } | Select-Object -Last 1
    if ($routeProfileLine -and $routeProfileLine -match "calls=(\d+) d2h=([0-9.]+)ms observe=([0-9.]+)ms map=([0-9.]+)ms transport=([0-9.]+)ms publish=([0-9.]+)ms") {
        $routeProfileObserved = $true
        $routeProfileCalls = [long]$Matches[1]
        $routeProfileD2HMs = [double]$Matches[2]
        $routeProfileObserveMs = [double]$Matches[3]
        $routeProfileMapMs = [double]$Matches[4]
        $routeProfileTransportMs = [double]$Matches[5]
        $routeProfilePublishMs = [double]$Matches[6]
    }
    $gpuRoutesLine = $lines | Where-Object { $_ -match "\[gpu-resident-routes\] final" } | Select-Object -Last 1
    if ($gpuRoutesLine -and $gpuRoutesLine -match "calls=(\d+) split_calls=(\d+) all_hit=(\d+) worker_jobs=(\d+) miss_experts=(\d+) errors=(\d+) worker=([0-9.]+)ms/job resolve=([0-9.]+)ms/call wait=([0-9.]+)ms/call") {
        $gpuRoutesObserved = $true
        $gpuRoutesCalls = [long]$Matches[1]
        $gpuRoutesSplitCalls = [long]$Matches[2]
        $gpuRoutesAllHit = [long]$Matches[3]
        $gpuRoutesWorkerJobs = [long]$Matches[4]
        $gpuRoutesMissExperts = [long]$Matches[5]
        $gpuRoutesErrors = [long]$Matches[6]
        $gpuRoutesWorkerMs = [double]$Matches[7]
        $gpuRoutesResolveMs = [double]$Matches[8]
        $gpuRoutesWaitMs = [double]$Matches[9]
    }
    if ($SplitHitMiss -and (-not $gpuRoutesObserved -or $gpuRoutesSplitCalls -le 0)) {
        throw "SplitHitMiss was requested but the runtime did not report any split calls"
    }
    $contextLine = $lines | Where-Object { $_ -match "context buffers .*ctx=(\d+).*prefill_chunk=(\d+).*raw_kv_rows=(\d+).*compressed_kv_rows=(\d+)" } | Select-Object -Last 1
    if ($contextLine -and $contextLine -match "ctx=(\d+).*prefill_chunk=(\d+).*raw_kv_rows=(\d+).*compressed_kv_rows=(\d+)") {
        $contextObserved = [int]$Matches[1]
        $prefillChunkObserved = [int]$Matches[2]
        $rawKvRowsObserved = [int]$Matches[3]
        $compressedKvRowsObserved = [int]$Matches[4]
    }
    $reapMaskReloadLine = $lines | Where-Object { $_ -match "REAP mask reload" } | Select-Object -Last 1
    if ($reapMaskReloadLine -and $reapMaskReloadLine -match '^ds4: REAP mask reload path="([^"]*)" pruned=(\d+) layers=(\d+) mtime=(\d+) size=(\d+)$') {
        $reapMaskReloadObserved = $true
        $reapMaskPathObserved = $Matches[1]
        $reapMaskReloadPruned = [int]$Matches[2]
        $reapMaskReloadLayers = [int]$Matches[3]
    }
    $reapMaskAppliedLine = $lines | Where-Object { $_ -match "REAP mask applied" } | Select-Object -Last 1
    if ($reapMaskAppliedLine -and $reapMaskAppliedLine -match '^ds4: REAP mask applied path="([^"]*)" pruned=(\d+) layers=(\d+) bias_layers=(\d+) ranges_updated=(\d+) ranges_created=(\d+) ranges_failed=(\d+)$') {
        $reapMaskAppliedObserved = $true
        if (-not $reapMaskPathObserved) { $reapMaskPathObserved = $Matches[1] }
        $reapMaskAppliedPruned = [int]$Matches[2]
        $reapMaskAppliedLayers = [int]$Matches[3]
        $reapMaskBiasLayers = [int]$Matches[4]
        $reapMaskRangesUpdated = [int]$Matches[5]
        $reapMaskRangesCreated = [int]$Matches[6]
        $reapMaskRangesFailed = [int]$Matches[7]
    }
    $arenaReadyLine = $lines | Where-Object { $_ -match "CUDA dynamic arena ready" } | Select-Object -Last 1
    if ($arenaReadyLine -and $arenaReadyLine -match "CUDA dynamic arena ready [0-9.]+ GiB, (\d+) slots.*bytes=(\d+) slot_bytes=(\d+)") {
        $arenaAllocatedSlots = [long]$Matches[1]
        $arenaAllocatedBytes = [long]$Matches[2]
        $arenaSlotBytes = [long]$Matches[3]
    }
    $prefillMassArmedLine = $lines | Where-Object { $_ -match "\[prefill-mass\] armed" } | Select-Object -Last 1
    if ($prefillMassArmedLine -and $prefillMassArmedLine -match "armed slots=(\d+) layers=(\d+)\.\.(\d+).*residency=([a-z-]+) policy=([a-z-]+)") {
        $prefillMassArmed = $true
        $prefillMassResidency = $Matches[4]; $prefillMassPolicy = $Matches[5]
    }
    $prefillMassFinalizeLine = $lines | Where-Object { $_ -match "\[prefill-mass\] finalize layers=" } | Select-Object -Last 1
    if ($prefillMassFinalizeLine -and $prefillMassFinalizeLine -match "finalize layers=(\d+) rows_min=(\d+) rows_max=(\d+) routed_slots=(\d+) unique=(\d+) candidate=(\d+) capacity=(\d+) mass_total=([0-9.]+) mass_candidate=([0-9.]+) mass_coverage=([0-9.]+) cutoff=([0-9.]+).*residency=([a-z-]+) policy=([a-z-]+)") {
        $prefillMassFinalized = $true
        $prefillMassLayers = [int]$Matches[1]; $prefillMassRowsMin = [int]$Matches[2]
        $prefillMassRowsMax = [int]$Matches[3]; $prefillMassRoutedSlots = [long]$Matches[4]
        $prefillMassUnique = [long]$Matches[5]; $prefillMassCandidate = [long]$Matches[6]
        $prefillMassCapacity = [long]$Matches[7]
        $prefillMassTotal = [double]::Parse($Matches[8], [Globalization.CultureInfo]::InvariantCulture)
        $prefillMassCandidateMass = [double]::Parse($Matches[9], [Globalization.CultureInfo]::InvariantCulture)
        $prefillMassCoverage = [double]::Parse($Matches[10], [Globalization.CultureInfo]::InvariantCulture)
        $prefillMassCutoff = [double]::Parse($Matches[11], [Globalization.CultureInfo]::InvariantCulture)
        $prefillMassResidency = $Matches[12]; $prefillMassPolicy = $Matches[13]
    }
    $prefillMassComposeLines = @($lines | Where-Object { $_ -match "\[prefill-mass-compose\]" })
    $prefillMassComposeEventCount = $prefillMassComposeLines.Count
    $prefillMassComposeLine = $prefillMassComposeLines | Select-Object -Last 1
    if ($prefillMassComposeLine -and $prefillMassComposeLine -match "hash_layers=(\d+) hash_seed_entries=(\d+) ranked_entries=(\d+) total_candidate=(\d+) capacity=(\d+)") {
        $prefillMassComposeObserved = $true
        $prefillMassComposeHashLayers = [int]$Matches[1]
        $prefillMassComposeHashSeedEntries = [long]$Matches[2]
        $prefillMassComposeRankedEntries = [long]$Matches[3]
        $prefillMassComposeTotalCandidate = [long]$Matches[4]
        $prefillMassComposeCapacity = [long]$Matches[5]
    }
    $prefillMassDecodeLine = $lines | Where-Object { $_ -match "\[prefill-mass\] decode reason=request-end" } | Select-Object -Last 1
    if ($prefillMassDecodeLine -and $prefillMassDecodeLine -match "tokens=(\d+) slots=(\d+) candidate_hits=(\d+) hit_rate=([0-9.]+) policy=([a-z-]+)") {
        $prefillMassDecodeTokens = [long]$Matches[1]
        $prefillMassDecodeSlots = [long]$Matches[2]
        $prefillMassDecodeHits = [long]$Matches[3]
        $prefillMassDecodeHitRate = [double]::Parse($Matches[4], [Globalization.CultureInfo]::InvariantCulture)
    }
    $prefillMassWrapLines = @($lines | Where-Object { $_ -match "\[prefill-mass-wrap\] result=" })
    $prefillMassWrapEventCount = $prefillMassWrapLines.Count
    $prefillMassWrapLine = $prefillMassWrapLines | Select-Object -Last 1
    if ($prefillMassWrapLine -and $prefillMassWrapLine -match "result=([a-z-]+) reason=([a-z-]+) candidate=(\d+) loads=(\d+) workers=(\d+) seconds=([0-9.]+) snapshot_before=(\d+) snapshot_after=(\d+) resident_before=(\d+) resident_after=(\d+) generation=(\d+) preloaded=(\d+) router=([a-z-]+) mask=([a-z-]+)") {
        $prefillMassWrapObserved = $true
        $prefillMassWrapResult = $Matches[1]; $prefillMassWrapReason = $Matches[2]
        $prefillMassWrapCandidate = [long]$Matches[3]; $prefillMassWrapLoads = [long]$Matches[4]
        $prefillMassWrapWorkers = [int]$Matches[5]
        $prefillMassWrapSeconds = [double]::Parse($Matches[6], [Globalization.CultureInfo]::InvariantCulture)
        $prefillMassWrapSnapshotBefore = [long]$Matches[7]; $prefillMassWrapSnapshotAfter = [long]$Matches[8]
        $prefillMassWrapResidentBefore = [long]$Matches[9]; $prefillMassWrapResidentAfter = [long]$Matches[10]
        $prefillMassWrapGeneration = [long]$Matches[11]; $prefillMassWrapPreloaded = [int]$Matches[12]
        $prefillMassWrapRouter = $Matches[13]; $prefillMassWrapMask = $Matches[14]
    }
    $reapMassArmedLine = $lines | Where-Object { $_ -match "\[reap-mass\] armed" } | Select-Object -Last 1
    if ($reapMassArmedLine -and $reapMassArmedLine -match "armed window=(\d+) top=(\d+) layers=(\d+)\.\.(\d+) semantics=selected_weight_normalized_per_token sliding_ring_observe_only transport=([a-z0-9-]+)") {
        $reapMassArmed = $true
        $reapMassWindowObserved = [int]$Matches[1]; $reapMassTopObserved = [int]$Matches[2]
        $reapMassFirstLayer = [int]$Matches[3]; $reapMassLastLayer = [int]$Matches[4]
        $reapMassTransport = $Matches[5]
    }
    $reapMassResultLine = $lines | Where-Object { $_ -match "\[reap-mass\] request-end" } | Select-Object -Last 1
    if ($reapMassResultLine -and $reapMassResultLine -match "request-end tokens=(\d+) observed_slots=(\d+) unique=(\d+) top_mass=([0-9.]+) touched=(\d+)") {
        $reapMassResultObserved = $true
        $reapMassTokens = [long]$Matches[1]; $reapMassObservedSlots = [long]$Matches[2]
        $reapMassUnique = [long]$Matches[3]
        $reapMassTopMass = [double]::Parse($Matches[4], [Globalization.CultureInfo]::InvariantCulture)
        $reapMassTouched = [long]$Matches[5]
    }
    $reapMassWrapArmedLine = $lines | Where-Object { $_ -match "\[reap-mass-wrap\] armed" } | Select-Object -Last 1
    if ($reapMassWrapArmedLine -and $reapMassWrapArmedLine -match "^ds4: \[reap-mass-wrap\] armed grow_interval=(\d+) hysteresis=([0-9]+(?:\.[0-9]+)?) capacity=(\d+) router=unbiased mask=off policy=free-then-mass-victim$") {
        $reapMassWrapArmed = $true
        $reapMassWrapGrowIntervalObserved = [int]$Matches[1]
        $reapMassWrapHysteresisObserved = [double]::Parse($Matches[2], [Globalization.CultureInfo]::InvariantCulture)
        $reapMassWrapCapacity = [long]$Matches[3]
        $reapMassWrapRouterArmed = "unbiased"
        $reapMassWrapMaskArmed = "off"
        $reapMassWrapPolicyArmed = "free-then-mass-victim"
    }
    $reapMassWrapEventLines = @($lines | Where-Object { $_ -match "\[reap-mass-wrap\] result=" })
    foreach ($reapMassWrapEventLine in $reapMassWrapEventLines) {
        if ($reapMassWrapEventLine -match "^ds4: \[reap-mass-wrap\] result=([a-z-]+) reason=([a-z-]+) tokens=(\d+) entrants=(\d+) victims=(\d+) free_before=(\d+) resident_before=(\d+) resident_after=(\d+) loads=(\d+) workers=(\d+) seconds=([0-9]+(?:\.[0-9]+)?) snapshot_before=(\d+) snapshot_after=(\d+) generation=(\d+) router=unbiased mask=off$") {
            $reapMassWrapObserved = $true
            $reapMassWrapEventCount += 1
            $reapMassWrapLastResult = $Matches[1]
            $reapMassWrapLastReason = $Matches[2]
            $reapMassWrapLastTokens = [long]$Matches[3]
            $reapMassWrapEntrants += [long]$Matches[4]
            $reapMassWrapVictims += [long]$Matches[5]
            $reapMassWrapLastFreeBefore = [long]$Matches[6]
            $reapMassWrapLastResidentBefore = [long]$Matches[7]
            $reapMassWrapLastResidentAfter = [long]$Matches[8]
            $reapMassWrapLoads += [long]$Matches[9]
            $reapMassWrapLastWorkers = [int]$Matches[10]
            $reapMassWrapSeconds += [double]::Parse($Matches[11], [Globalization.CultureInfo]::InvariantCulture)
            $reapMassWrapLastSnapshotBefore = [long]$Matches[12]
            $reapMassWrapLastSnapshotAfter = [long]$Matches[13]
            $reapMassWrapLastGeneration = [long]$Matches[14]
            $reapMassWrapLastRouter = "unbiased"
            $reapMassWrapLastMask = "off"
            if ($reapMassWrapLastResult -eq "published") {
                $reapMassWrapPublicationCount += 1
            } elseif ($reapMassWrapLastResult -eq "skipped") {
                $reapMassWrapSkippedCount += 1
            } else {
                $reapMassWrapFailureCount += 1
            }
        } else {
            $reapMassWrapFailureCount += 1
        }
    }
    $arenaObserverArmedLine = $lines | Where-Object { $_ -match "\[arena-observe\] armed window=(\d+) min_hits=(\d+)(?: grow_interval=(\d+))? layers=(\d+)\.\.(\d+) router=unbiased residency-only" } | Select-Object -Last 1
    if ($arenaObserverArmedLine -and $arenaObserverArmedLine -match "armed window=(\d+) min_hits=(\d+)(?: grow_interval=(\d+))? layers=(\d+)\.\.(\d+) router=unbiased residency-only") {
        $arenaObserverArmed = $true
        $arenaObserverWindowObserved = [int]$Matches[1]
        $arenaObserverMinHitsObserved = [int]$Matches[2]
        $arenaObserverGrowIntervalObserved = if ($Matches[3]) { [int]$Matches[3] } else { 0 }
        $arenaObserverFirstLayer = [int]$Matches[4]
        $arenaObserverLastLayer = [int]$Matches[5]
    }
    $arenaWrapLines = @($lines | Where-Object { $_ -match "\[arena-observe\] WRAP (published|aborted)" })
    $arenaWrapPublicationCount = @($arenaWrapLines | Where-Object { $_ -match "\[arena-observe\] WRAP published" }).Count
    $arenaWrapLine = $arenaWrapLines | Select-Object -Last 1
    if ($arenaWrapLine -and $arenaWrapLine -match "WRAP published tokens=(\d+) resident=(\d+) loads=(\d+) workers=(\d+) seconds=([0-9.]+) generation=(\d+)") {
        $arenaWrapObserved = $true
        $arenaObserverTokens = [long]$Matches[1]; $arenaObserverResident = [long]$Matches[2]
        $arenaWrapLoads = [long]$Matches[3]; $arenaWrapWorkers = [int]$Matches[4]
        $arenaWrapSeconds = [double]::Parse($Matches[5], [Globalization.CultureInfo]::InvariantCulture)
        $arenaWrapGeneration = [long]$Matches[6]
        if ($arenaWrapLine -match "preloaded=(\d+) mirror=([0-9.]+) GiB") {
            $arenaWrapPreloaded = [long]$Matches[1]
            $arenaWrapMirrorGiB = [double]::Parse($Matches[2], [Globalization.CultureInfo]::InvariantCulture)
        }
        if ($arenaWrapLine -match "verify_workers=(\d+) verify_seconds=([0-9.]+)") {
            $arenaVerifyWorkers = [int]$Matches[1]
            $arenaVerifySeconds = [double]::Parse($Matches[2], [Globalization.CultureInfo]::InvariantCulture)
        }
    } elseif ($arenaWrapLine -and $arenaWrapLine -match "WRAP aborted tokens=(\d+) resident=(\d+) loads=(\d+) seconds=([0-9.]+)") {
        $arenaWrapObserved = $true
        $arenaObserverTokens = [long]$Matches[1]; $arenaObserverResident = [long]$Matches[2]
        $arenaWrapLoads = [long]$Matches[3]
        $arenaWrapSeconds = [double]::Parse($Matches[4], [Globalization.CultureInfo]::InvariantCulture)
    }
    $arenaResultLines = @($lines | Where-Object { $_ -match "\[arena-observe\] window complete" })
    $arenaObserverPublicationCount = $arenaResultLines.Count
    $arenaResultLine = $arenaResultLines | Select-Object -Last 1
    if ($arenaResultLine -and $arenaResultLine -match "window complete tokens=(\d+) resident=(\d+)(?: growths=\d+)? result=(published|fallback)") {
        $arenaObserverResultObserved = $true
        $arenaObserverTokens = [long]$Matches[1]; $arenaObserverResident = [long]$Matches[2]
        $arenaObserverResult = $Matches[3]
    }
    $arenaGrowthLines = @($lines | Where-Object { $_ -match "\[arena-observe\] grow complete" })
    if ($arenaGrowthLines.Count) {
        foreach ($arenaGrowthLine in $arenaGrowthLines) {
            if ($arenaGrowthLine -match "grow complete tokens=(\d+) resident=(\d+) growths=(\d+) result=(published|fallback)") {
                $arenaObserverTokens = [long]$Matches[1]
                $arenaObserverResident = [long]$Matches[2]
                $arenaGrowthPublications = [long]$Matches[3]
                $arenaGrowthEvents += [pscustomobject]@{
                    tokens = [long]$Matches[1]
                    resident_entries = [long]$Matches[2]
                    resident_bytes = [long]$Matches[2] * [long]$arenaSlotBytes
                    publication = [long]$Matches[3]
                    result = $Matches[4]
                }
            }
        }
    }
    $arenaGrowthSkips = @($lines | Where-Object { $_ -match "\[arena-observe\] grow skipped" }).Count
    $arenaCarryLines = @($lines | Where-Object { $_ -match "\[arena-carry\]" })
    $arenaCarryLineCount = $arenaCarryLines.Count
    foreach ($arenaCarryLine in $arenaCarryLines) {
        if ($arenaCarryLine -match "\[arena-carry\] request=(\d+) mode=(prime|keep|drop) snapshot=(\d+) resident=(\d+) lookup=(enabled|disabled) observer=(learning|frozen)") {
            $arenaCarryEvents += [pscustomobject]@{
                request = [int]$Matches[1]
                mode = $Matches[2]
                snapshot = [long]$Matches[3]
                resident = [long]$Matches[4]
                lookup = $Matches[5]
                observer = $Matches[6]
            }
        }
    }
    $lastArenaCarryEvent = $arenaCarryEvents | Select-Object -Last 1
    if ($lastArenaCarryEvent) {
        $arenaCarryObserved = $true
        $arenaCarryRequest = $lastArenaCarryEvent.request
        $arenaCarryModeObserved = $lastArenaCarryEvent.mode
        $arenaCarrySnapshot = $lastArenaCarryEvent.snapshot
        $arenaCarryResident = $lastArenaCarryEvent.resident
        $arenaCarryLookupObserved = $lastArenaCarryEvent.lookup
        $arenaCarryObserverObserved = $lastArenaCarryEvent.observer
    }
    $arenaFinalLine = $lines | Where-Object { $_ -match "\[arena\] final" } | Select-Object -Last 1
    if ($arenaFinalLine -and $arenaFinalLine -match "\[arena\] final hits=(\d+) misses=(\d+) fatal=(\d+) uploaded=([0-9.]+) GiB") {
        $arenaFinalObserved = $true
        $arenaFinalHits = [long]$Matches[1]; $arenaFinalMisses = [long]$Matches[2]
        $arenaFinalFatal = [long]$Matches[3]
        $arenaFinalUploadedGiB = [double]::Parse($Matches[4], [Globalization.CultureInfo]::InvariantCulture)
    }
}

$spexCpuProbeLines = @()
if (Test-Path $stderrLog) {
    $spexCpuProbeLines += @(Get-Content -LiteralPath $stderrLog | Where-Object { $_ -match "\[spex-cpu\] final" })
}
if (Test-Path $stdoutLog) {
    $spexCpuProbeLines += @(Get-Content -LiteralPath $stdoutLog | Where-Object { $_ -match "\[spex-cpu\] final" })
}
$spexCpuProbeLineCount = @($spexCpuProbeLines).Count
if ($spexCpuProbeLineCount -gt 0) {
    $spexCpuProbeFinalLine = @($spexCpuProbeLines)[-1]
    if ($spexCpuProbeFinalLine -match "final k=(\d+) submitted=(\d+) dropped=(\d+) completed=(\d+) predicted=(\d+) matched=(\d+) ready_at_transport=(\d+) useful_ready=(\d+) failures=(\d+) d2h_wait_ms=([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?) cpu_ms=([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?) queue_ms=([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?) checksum=([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)") {
        $spexCpuProbeFinalObserved = $true
        $spexCpuProbeKObserved = [int]$Matches[1]
        $spexCpuProbeSubmitted = [long]$Matches[2]; $spexCpuProbeDropped = [long]$Matches[3]
        $spexCpuProbeCompleted = [long]$Matches[4]; $spexCpuProbePredicted = [long]$Matches[5]
        $spexCpuProbeMatched = [long]$Matches[6]; $spexCpuProbeReadyAtTransport = [long]$Matches[7]
        $spexCpuProbeUsefulReady = [long]$Matches[8]; $spexCpuProbeFailures = [long]$Matches[9]
        $spexCpuProbeD2HWaitMs = [double]::Parse($Matches[10], [Globalization.CultureInfo]::InvariantCulture)
        $spexCpuProbeCpuMs = [double]::Parse($Matches[11], [Globalization.CultureInfo]::InvariantCulture)
        $spexCpuProbeQueueMs = [double]::Parse($Matches[12], [Globalization.CultureInfo]::InvariantCulture)
        $spexCpuProbeChecksum = [double]::Parse($Matches[13], [Globalization.CultureInfo]::InvariantCulture)
    }
}

if (-not $httpOk) { throw "Measurement failed: one or more HTTP requests did not complete" }
if (@($results).Count -ne $Repeats) {
    throw "Measurement failed: expected $Repeats results, observed $(@($results).Count)"
}
if ($contextObserved -ne $Context) {
    throw "Measurement failed: requested context $Context, observed $contextObserved"
}

if ($ExpertTiering -eq "off") {
    if ($expertTieringFinalLineCount -ne 0 -or $expertTieringControlLineCount -ne 0) {
        throw "Expert tiering measurement failed: telemetry appeared while off"
    }
} else {
    if ($expertTieringControlLineCount -ne 0) { throw "Expert tiering measurement failed: control telemetry was observed" }
    if ($expertTieringFinalLineCount -ne 1 -or -not $expertTieringFinalObserved) { throw "Expert tiering measurement failed: final counters were not observed exactly once" }
    if ($ComposePrefillMassTiering) {
        if (-not $expertTieringComposeObserved -or $expertTieringComposeFlag -ne 1) { throw "Expert tiering compose failed: final compose flag was not observed" }
        if ($expertTieringSnapshotGeneration -le 0 -or $expertTieringSnapshotBackingEntries -le 0) { throw "Expert tiering compose failed: snapshot backing was empty" }
        if ($expertTieringSnapshotBackingHits -le 0) { throw "Expert tiering compose failed: snapshot backing was not used" }
        if ($expertTieringSnapshotBackingMisses -ne 0) { throw "Expert tiering compose failed: decode requested an expert outside the closed snapshot" }
        if ($expertTieringSnapshotToVramBytes -le 0) { throw "Expert tiering compose failed: snapshot backing produced no H2D traffic" }
        if ($expertTieringForbiddenColdSsdToVram -ne 0) { throw "Expert tiering compose failed: cold SSD to VRAM violation observed" }
        if ($expertTieringColdToRam -ne 0 -or $expertTieringSsdBytes -ne 0) { throw "Expert tiering compose failed: decode touched cold SSD backing" }
        if ($expertTieringColdToVram -ne 0) { throw "Expert tiering compose failed: cold_to_vram must remain zero" }
        if ($expertTieringFailures -ne 0) { throw "Expert tiering compose failed: runtime failures observed" }
        if ($prefillMassWrapGeneration -le 0 -or $expertTieringSnapshotGeneration -ne $prefillMassWrapGeneration) { throw "Expert tiering compose failed: snapshot generation differs from prefill publish" }
        if ($expertTieringSnapshotBackingEntries -ne $prefillMassWrapResidentAfter -or
            $expertTieringSnapshotBackingEntries -ne $prefillMassWrapCandidate) {
            throw "Expert tiering compose failed: snapshot backing differs from prefill publication"
        }
    } elseif ($expertTieringComposeObserved) {
        throw "Expert tiering measurement failed: compose telemetry appeared while not requested"
    }
    if ($expertTieringModeObserved -ne $ExpertTiering) { throw "Expert tiering measurement failed: observed mode mismatch" }
    if ($expertTieringPolicyObserved -ne $ExpertTierPolicy) { throw "Expert tiering measurement failed: observed policy mismatch" }
    if ($ExpertTierPolicy -eq "mass-lfru") {
        if ($expertTieringClockCalls -ne $ExpertTierClockCalls -or
            $expertTieringReplacementBudget -ne $ExpertTierReplacementBudget -or
            $expertTieringMinFrequency -ne $ExpertTierMinFrequency -or
            [math]::Abs($expertTieringHysteresis - $ExpertTierHysteresis) -gt 1.0e-9) {
            throw "Expert tiering measurement failed: mass-lfru policy parameters mismatch"
        }
    } elseif ($expertTieringClockCalls -ne 0 -or
              $expertTieringReplacementBudget -ne 0 -or
              $expertTieringMinFrequency -ne 2 -or
              [math]::Abs($expertTieringHysteresis - 1.0) -gt 1.0e-9) {
        throw "Expert tiering measurement failed: second-touch effective parameters mismatch"
    }
    if ($expertTieringCalls -le 0 -or $expertTieringSelected -le 0) { throw "Expert tiering measurement failed: no routed calls were observed" }
    if ($expertTieringFailures -ne 0) { throw "Expert tiering measurement failed: runtime failures observed" }
    if ($expertTieringSelected -ne ($expertTieringCalls * 6)) { throw "Expert tiering measurement failed: selected count does not equal calls*6" }
    if ($expertTieringCold -gt $expertTieringSelected -or
        $expertTieringRamHits -gt $expertTieringSelected -or
        $expertTieringVramHits -gt $expertTieringSelected -or
        $expertTieringTransient -gt $expertTieringSelected) {
        throw "Expert tiering measurement failed: hit counters exceed selected count"
    }
    if (($expertTieringCold + $expertTieringRamHits + $expertTieringVramHits) -gt $expertTieringSelected) {
        throw "Expert tiering measurement failed: hit accounting exceeds selected count"
    }
    if ($expertTieringColdToRam -gt $expertTieringCold -or $expertTieringColdToVram -gt $expertTieringCold) {
        throw "Expert tiering measurement failed: cold transition counters exceed cold count"
    }
    if ($expertTieringVramDemotions -gt ($expertTieringVramPromotions + $expertTieringColdToVram)) {
        throw "Expert tiering measurement failed: VRAM demotions exceed admissions"
    }
    if ($ExpertTiering -eq "enforce") {
        if (($expertTieringPolicyFreePromotions + $expertTieringPolicyReplacements) -ne
            $expertTieringVramPromotions) {
            throw "Expert tiering measurement failed: policy promotion accounting mismatch"
        }
        if ($expertTieringPolicyReplacements -ne $expertTieringVramDemotions) {
            throw "Expert tiering measurement failed: policy replacement accounting mismatch"
        }
        if ($ExpertTierPolicy -eq "mass-lfru" -and
            $expertTieringPolicyReplacements -gt
                ($expertTieringPolicyEpochs * $ExpertTierReplacementBudget)) {
            throw "Expert tiering measurement failed: mass-lfru replacement budget exceeded"
        }
    }
    if ($expertTieringStatesVram -gt $ExpertCacheN) {
        throw "Expert tiering measurement failed: VRAM state count exceeds ExpertCacheN"
    }
    if ($ExpertTiering -eq "enforce" -and -not $ComposePrefillMassTiering -and
        ($expertTieringColdToVram -ne 0 -or
         $expertTieringColdToRam -le 0 -or
         $expertTieringTransient -le 0 -or
         $expertTieringVramPromotions -le 0)) {
        throw "Expert tiering measurement failed: enforce transition contract was violated"
    }
    $expertTieringStateTotal = [uint64]$expertTieringStatesSsd + [uint64]$expertTieringStatesProbation + [uint64]$expertTieringStatesWarm + [uint64]$expertTieringStatesVram
    if ($expertTieringStateTotal -le 0 -or $expertTieringStateTotal -gt 1000000) {
        throw "Expert tiering measurement failed: state counters are unreasonable"
    }
    if ([double]::IsNaN($expertTieringMassSum) -or [double]::IsInfinity($expertTieringMassSum) -or $expertTieringMassSum -lt 0.0 -or $expertTieringMassSum -gt [double]$expertTieringSelected) {
        throw "Expert tiering measurement failed: mass_sum is unreasonable"
    }
    if ([double]::IsNaN($expertTieringLfruTop) -or [double]::IsInfinity($expertTieringLfruTop) -or $expertTieringLfruTop -lt 0.0) {
        throw "Expert tiering measurement failed: lfru_top is unreasonable"
    }
}

if ($SpexDryRun) {
    $expectedSpexCap = $effectiveSpexCap
    if (-not $spexObserved) { throw "SPEX measurement failed: no runtime counters observed" }
    if ($spexDisabled) { throw "SPEX measurement failed: runtime disabled itself" }
    if ($spexObservedStage -ne $SpexStage) { throw "SPEX measurement failed: observed stage mismatch" }
    if ($spexFusedObserved -ne [bool]$SpexFusedTopK) { throw "SPEX measurement failed: fused topK mismatch" }
    if ($spexRingObserved -ne $SpexRingSlots) { throw "SPEX measurement failed: ring slot mismatch" }
    if ($spexObservedCap -ne $expectedSpexCap) { throw "SPEX measurement failed: observed cap mismatch" }
    if ($SpexStage -eq "resident") {
        if ($spexScheduled -ne 0 -or $spexReady -ne 0) { throw "SPEX resident stage unexpectedly scheduled GPU work" }
    } elseif ($SpexStage -eq "full") {
        if ($spexScheduled -le 0 -or $spexReady -le 0 -or $spexReady -gt $spexScheduled) { throw "SPEX measurement failed: scheduled/ready counters are inconsistent" }
        if ($SpexRingSlots -eq 1 -and $spexScheduled -ne $spexReady) { throw "SPEX blocking measurement failed: scheduled/ready mismatch" }
        if ($SpexRingSlots -gt 1) {
            if ($spexRingFull -ne 0) { throw "SPEX ring measurement failed: ring-full events observed" }
            if (($spexReady + $spexLate) -ne $spexScheduled) { throw "SPEX ring measurement failed: predictions are not fully accounted" }
            if ($spexStale -ne $spexLate) { throw "SPEX ring measurement failed: late/stale counters differ" }
            if (($spexReady / [double]$spexScheduled) -lt 0.90) { throw "SPEX ring measurement failed: ready coverage below 90%" }
        }
        if ($spexNoActual -ne 0) { throw "SPEX measurement failed: router truth was unavailable for one or more layers" }
    } else {
        if ($spexScheduled -le 0 -or $spexReady -ne 0) { throw "SPEX intermediate stage counters are inconsistent" }
    }
}
if ($SpexPrefetchK -gt 0) {
    if (-not $spexPrefetchObserved -or $spexPrefetchKObserved -ne $SpexPrefetchK) { throw "SPEX prefetch measurement failed: requested worker was not activated" }
    if (-not $spexPrefetchFinalObserved) { throw "SPEX prefetch measurement failed: final counters were not observed" }
    if ($spexPrefetchSubmitted -le 0) { throw "SPEX prefetch measurement failed: no jobs were submitted" }
    if ($spexPrefetchLoaded -le 0 -or $spexPrefetchHits -le 0) { throw "SPEX prefetch measurement failed: no functional loads were consumed" }
    if ($spexPrefetchErrors -ne 0 -or $spexPrefetchPoisoned -ne 0 -or $spexPrefetchDisabled) { throw "SPEX prefetch measurement failed: worker error/quarantine observed" }
    if ($spexPrefetchDropped -ne 0 -or $spexPrefetchCanceled -ne 0) { throw "SPEX prefetch measurement failed: dropped/canceled jobs observed" }
    if ($spexPrefetchSubmitted -ne ($spexPrefetchLoaded + $spexPrefetchLate)) { throw "SPEX prefetch measurement failed: submitted jobs are not fully accounted" }
    if ($spexPrefetchLoaded -ne ($spexPrefetchMatched + $spexPrefetchNoHits)) { throw "SPEX prefetch measurement failed: loaded jobs are not fully classified" }
    if ($spexPrefetchMatched -ne $spexPrefetchHits) { throw "SPEX prefetch measurement failed: matched jobs did not all reach consumption" }
    if ($spexReady -ne $spexLayers) { throw "SPEX prefetch measurement failed: ready predictions and compared layers differ" }
    if ($spexPrefetchHits -ne $spexHits) { throw "SPEX prefetch measurement failed: consumed jobs differ from predictor hits" }
    if ($spexPrefetchBytesRead -le 0 -or $spexPrefetchBytesUsed -le 0 -or $spexPrefetchBytesUsed -gt $spexPrefetchBytesRead) { throw "SPEX prefetch measurement failed: byte counters are inconsistent" }
    if (($spexPrefetchBytesRead % $spexPrefetchLoaded) -ne 0 -or ($spexPrefetchBytesUsed % $spexPrefetchHits) -ne 0) { throw "SPEX prefetch measurement failed: byte counters are not whole experts" }
    if (($spexPrefetchBytesRead / $spexPrefetchLoaded) -ne ($spexPrefetchBytesUsed / $spexPrefetchHits)) { throw "SPEX prefetch measurement failed: read/consumed expert sizes differ" }
} elseif ($spexPrefetchObserved -or $spexPrefetchFinalObserved) {
    throw "SPEX prefetch measurement failed: worker activated while not requested"
}
if ($SpexCpuProbeK -gt 0) {
    if ($spexCpuProbeLineCount -ne 1 -or -not $spexCpuProbeFinalObserved) { throw "SPEX CPU probe measurement failed: final counters were not observed exactly once" }
    if ($spexCpuProbeKObserved -ne $SpexCpuProbeK) { throw "SPEX CPU probe measurement failed: observed K mismatch" }
    if ($spexCpuProbeSubmitted -le 0 -or $spexCpuProbeCompleted -le 0) { throw "SPEX CPU probe measurement failed: no jobs completed" }
    if ($spexCpuProbeFailures -ne 0) { throw "SPEX CPU probe measurement failed: runtime failures observed" }
    if ($spexCpuProbeCompleted -ne $spexCpuProbeSubmitted) { throw "SPEX CPU probe measurement failed: final submitted/completed accounting does not balance" }
    if ($spexCpuProbePredicted -ne ($spexCpuProbeKObserved * $spexCpuProbeSubmitted)) { throw "SPEX CPU probe measurement failed: predicted width does not match K*submitted" }
    if ($spexCpuProbeMatched -gt $spexCpuProbePredicted) { throw "SPEX CPU probe measurement failed: matched predictions exceed predicted count" }
    if ($spexCpuProbeReadyAtTransport -gt $spexCpuProbeCompleted) { throw "SPEX CPU probe measurement failed: ready jobs exceed completed jobs" }
    if ($spexCpuProbeUsefulReady -gt $spexCpuProbeMatched) { throw "SPEX CPU probe measurement failed: useful-ready count exceeds matched count" }
} elseif ($spexCpuProbeLineCount -gt 0) {
    throw "SPEX CPU probe measurement failed: final counters appeared while not requested"
}
if ($PrefillMassObserve -or $PrefillMassWrap) {
    if (-not $prefillMassArmed -or -not $prefillMassFinalized) { throw "Prefill mass measurement failed: observer did not arm/finalize" }
    if ($prefillMassCandidate -le 0 -or $prefillMassCandidate -gt $prefillMassCapacity) { throw "Prefill mass measurement failed: invalid candidate size" }
    if ($prefillMassCoverage -le 0.0 -or $prefillMassCoverage -gt 1.0) { throw "Prefill mass measurement failed: invalid mass coverage" }
    if ($prefillMassDecodeSlots -le 0 -or $prefillMassDecodeHits -gt $prefillMassDecodeSlots) { throw "Prefill mass measurement failed: invalid decode coverage" }
    $expectedPrefillMassPolicy = if ($PrefillMassWrap) { "bulk-wrap" } else { "observe-only" }
    if ($prefillMassPolicy -ne $expectedPrefillMassPolicy) { throw "Prefill mass measurement failed: runtime policy mismatch" }
}
if ($PrefillMassWrap) {
    if ($prefillMassWrapEventCount -ne 1 -or -not $prefillMassWrapObserved) { throw "Prefill mass WRAP failed: expected exactly one well-formed terminal event" }
    if ($prefillMassWrapResult -ne "published" -or $prefillMassWrapReason -ne "ok") { throw "Prefill mass WRAP failed: publication missing or unsuccessful" }
    if ($prefillMassWrapCandidate -ne $prefillMassCandidate -or
        $prefillMassWrapLoads -ne $prefillMassCandidate -or
        $prefillMassWrapResidentAfter -ne $prefillMassCandidate) {
        throw "Prefill mass WRAP failed: candidate/load/resident counts differ"
    }
    if ($prefillMassWrapSnapshotBefore -ne 0 -or $prefillMassWrapResidentBefore -ne 0 -or
        $prefillMassWrapSnapshotAfter -le 0 -or $prefillMassWrapGeneration -le 0) {
        throw "Prefill mass WRAP failed: first-snapshot invariants differ"
    }
    $expectedPrefillMassMask = if ($ComposePrefillMassTiering) { "request-scoped-closed" } else { "off" }
    if ($prefillMassWrapPreloaded -ne 0 -or $prefillMassWrapRouter -ne "unbiased" -or $prefillMassWrapMask -ne $expectedPrefillMassMask) {
        throw "Prefill mass WRAP failed: isolation telemetry differs"
    }
    if ($ComposePrefillMassTiering) {
        if ($prefillMassComposeEventCount -ne 1 -or -not $prefillMassComposeObserved) { throw "Prefill mass compose failed: hash seed telemetry missing" }
        if ($prefillMassComposeHashLayers -ne 3 -or $prefillMassComposeHashSeedEntries -ne (3 * 256)) { throw "Prefill mass compose failed: hash-routed layer seed differs" }
        if ($prefillMassComposeTotalCandidate -ne $prefillMassCandidate -or $prefillMassComposeCapacity -ne $prefillMassCapacity) { throw "Prefill mass compose failed: candidate/capacity telemetry differs" }
        if ($prefillMassComposeRankedEntries + $prefillMassComposeHashSeedEntries -ne $prefillMassComposeTotalCandidate) { throw "Prefill mass compose failed: ranked/hash candidate accounting differs" }
    } elseif ($prefillMassComposeEventCount -ne 0 -or $prefillMassComposeObserved) {
        throw "Prefill mass compose telemetry appeared while not requested"
    }
} elseif ($prefillMassWrapEventCount -ne 0 -or $prefillMassWrapObserved) {
    throw "Prefill mass WRAP activated while not requested"
}
if ($ReapMaskFile) {
    $resolvedReapMaskFile = (Resolve-Path -LiteralPath $ReapMaskFile).Path
    if (-not $reapMaskReloadObserved -or -not $reapMaskAppliedObserved) {
        throw "REAP mask measurement failed: exact reload/applied telemetry was not observed"
    }
    if ($reapMaskPathObserved -ne $resolvedReapMaskFile) {
        throw "REAP mask measurement failed: observed mask path differs from requested path"
    }
    if ($reapMaskReloadPruned -le 0 -or $reapMaskReloadLayers -le 0) {
        throw "REAP mask measurement failed: invalid reload counters"
    }
    if ($reapMaskAppliedPruned -ne $reapMaskReloadPruned -or
        $reapMaskAppliedLayers -ne $reapMaskReloadLayers -or
        $reapMaskBiasLayers -le 0) {
        throw "REAP mask measurement failed: applied counters differ from reload counters"
    }
    if ($reapMaskRangesFailed -ne 0 -or
        ($reapMaskRangesUpdated + $reapMaskRangesCreated) -ne $reapMaskBiasLayers) {
        throw "REAP mask measurement failed: device bias range upload was incomplete"
    }
} elseif ($reapMaskReloadObserved -or $reapMaskAppliedObserved) {
    throw "REAP mask activated while not requested"
}
if ($ReapMassObserve -or $ReapMassWrap) {
    if (-not $reapMassArmed -or -not $reapMassResultObserved) { throw "REAP mass measurement failed: observer did not arm/report" }
    if ($reapMassWindowObserved -ne $ReapMassWindow -or $reapMassTopObserved -le 0 -or $reapMassTransport -ne "packed-router-d2h") { throw "REAP mass measurement failed: observed policy/transport differs from requested policy" }
    if ($reapMassTokens -le 0 -or $reapMassObservedSlots -le 0 -or $reapMassUnique -le 0 -or $reapMassTopMass -le 0.0) { throw "REAP mass measurement failed: invalid terminal counters" }
} elseif ($reapMassArmed -or $reapMassResultObserved) {
    throw "REAP mass observer activated while not requested"
}
if ($ReapMassWrap) {
    if (-not $reapMassWrapArmed -or -not $reapMassWrapArmedLine) { throw "REAP mass WRAP failed: observer/wrap did not arm" }
    if ($reapMassWrapGrowIntervalObserved -ne $ReapMassGrowInterval -or
        [math]::Abs($reapMassWrapHysteresisObserved - $ReapMassHysteresis) -gt 1e-9 -or
        $reapMassWrapCapacity -le 0 -or
        $reapMassWrapRouterArmed -ne "unbiased" -or
        $reapMassWrapMaskArmed -ne "off" -or
        $reapMassWrapPolicyArmed -ne "free-then-mass-victim") {
        throw "REAP mass WRAP failed: observed config differs from requested policy"
    }
    if ($reapMassWrapEventCount -le 0 -or $reapMassWrapPublicationCount -le 0) { throw "REAP mass WRAP failed: no published event observed" }
    if ($reapMassWrapFailureCount -ne 0) { throw "REAP mass WRAP failed: malformed or unsuccessful event observed" }
    if ($reapMassWrapLastRouter -ne "unbiased" -or $reapMassWrapLastMask -ne "off") { throw "REAP mass WRAP failed: router/mask telemetry differs" }
} elseif ($reapMassWrapArmedLine -or $reapMassWrapEventLines.Count -ne 0 -or $reapMassWrapObserved) {
    throw "REAP mass WRAP activated while not requested"
}
if ($DynamicArenaObservedWindow -gt 0) {
    if (-not $arenaObserverArmed) { throw "Dynamic arena measurement failed: observer was not armed" }
    if ($arenaObserverWindowObserved -ne $DynamicArenaObservedWindow -or
        $arenaObserverMinHitsObserved -ne $DynamicArenaObservedMinHits -or
        $arenaObserverGrowIntervalObserved -ne $DynamicArenaGrowInterval) {
        throw "Dynamic arena measurement failed: observed policy differs from requested policy"
    }
    if ($MaxTokens -ge $DynamicArenaObservedWindow -and -not $arenaObserverResultObserved) {
        throw "Dynamic arena measurement failed: initial publication result was not observed"
    }
}
if ($DynamicArenaCarry -ne "default") {
    $expectedCarryLookup = if ($DynamicArenaCarry -eq "keep") { "enabled" } else { "disabled" }
    if (-not $arenaCarryObserved) { throw "Dynamic arena carry measurement failed: telemetry was not observed" }
    if ($arenaCarryLineCount -ne ($Repeats + 1)) { throw "Dynamic arena carry measurement failed: expected $($Repeats + 1) request markers, observed $arenaCarryLineCount" }
    if ($arenaCarryEvents.Count -ne ($Repeats + 1)) { throw "Dynamic arena carry measurement failed: one or more request markers were malformed" }
    $prime = $arenaCarryEvents[0]
    if ($prime.request -ne 1 -or $prime.mode -ne "prime" -or $prime.snapshot -ne 0 -or
        $prime.resident -ne 0 -or $prime.lookup -ne "enabled" -or $prime.observer -ne "learning") {
        throw "Dynamic arena carry measurement failed: request 1 was not a clean prime"
    }
    for ($carryIndex = 1; $carryIndex -lt $arenaCarryEvents.Count; $carryIndex++) {
        $event = $arenaCarryEvents[$carryIndex]
        if ($event.request -ne ($carryIndex + 1) -or $event.mode -ne $DynamicArenaCarry) {
            throw "Dynamic arena carry measurement failed: request sequence/mode mismatch"
        }
        if ($event.snapshot -le 0 -or $event.resident -le 0) {
            throw "Dynamic arena carry measurement failed: learned snapshot was empty"
        }
        if ($event.lookup -ne $expectedCarryLookup -or $event.observer -ne "frozen") {
            throw "Dynamic arena carry measurement failed: lookup/observer state mismatch"
        }
    }
    if ($arenaObserverPublicationCount -ne 1 -or $arenaWrapPublicationCount -ne 1) { throw "Dynamic arena carry measurement failed: learned arena was republished during measured requests" }
}

$serverRuns = @($serverRunsAll | Select-Object -Last $Repeats)
$serverDecodeTps = @($serverRuns | ForEach-Object { $_.server_avg_tokens_per_second } | Where-Object { $_ -gt 0 })
$serverDecodeMeanTps = if ($serverDecodeTps.Count) { [math]::Round(($serverDecodeTps | Measure-Object -Average).Average, 6) } else { 0.0 }
$serverDecodeMinTps = if ($serverDecodeTps.Count) { [math]::Round(($serverDecodeTps | Measure-Object -Minimum).Minimum, 6) } else { 0.0 }
$serverDecodeMaxTps = if ($serverDecodeTps.Count) { [math]::Round(($serverDecodeTps | Measure-Object -Maximum).Maximum, 6) } else { 0.0 }
$serverPrefillTtft = @($serverRuns | ForEach-Object { $_.server_prefill_ttft_seconds } | Where-Object { $_ -gt 0 })
$serverPrefillTtftMean = if ($serverPrefillTtft.Count) { [math]::Round(($serverPrefillTtft | Measure-Object -Average).Average, 6) } else { 0.0 }
$spexReadyCoverage = if ($spexScheduled -gt 0) { [math]::Round($spexReady / [double]$spexScheduled, 6) } else { $null }
$spexRecallScope = if ($spexScheduled -gt 0) { "ready_predictions_only" } else { "not_applicable" }
$tps = @($results | ForEach-Object { $_.tokens_per_second })
$meanTps = if ($tps.Count) { [math]::Round(($tps | Measure-Object -Average).Average, 6) } else { 0.0 }
$minTps = if ($tps.Count) { [math]::Round(($tps | Measure-Object -Minimum).Minimum, 6) } else { 0.0 }
$maxTps = if ($tps.Count) { [math]::Round(($tps | Measure-Object -Maximum).Maximum, 6) } else { 0.0 }
$hashes = @($results | Select-Object -ExpandProperty content_sha256 -Unique)
$expertTieringResult = [pscustomobject]@{
    requested_mode = $ExpertTiering
    requested_policy = $ExpertTierPolicy
    compose_prefill_mass_tiering_requested = [bool]$ComposePrefillMassTiering
    compose_prefill_mass_tiering_observed = $expertTieringComposeObserved
    compose_prefill_mass_tiering_flag = $expertTieringComposeFlag
    snapshot_generation = $expertTieringSnapshotGeneration
    snapshot_backing_entries = $expertTieringSnapshotBackingEntries
    snapshot_backing_hits = $expertTieringSnapshotBackingHits
    snapshot_backing_misses = $expertTieringSnapshotBackingMisses
    snapshot_to_vram_bytes = $expertTieringSnapshotToVramBytes
    forbidden_cold_ssd_to_vram = $expertTieringForbiddenColdSsdToVram
    final_observed = $expertTieringFinalObserved
    final_line_count = $expertTieringFinalLineCount
    control_line_count = $expertTieringControlLineCount
    mode = $expertTieringModeObserved
    policy = $expertTieringPolicyObserved
    clock_calls = $expertTieringClockCalls
    replacement_budget = $expertTieringReplacementBudget
    min_frequency = $expertTieringMinFrequency
    hysteresis = $expertTieringHysteresis
    calls = $expertTieringCalls
    selected = $expertTieringSelected
    cold = $expertTieringCold
    ram_hits = $expertTieringRamHits
    vram_hits = $expertTieringVramHits
    cold_to_ram = $expertTieringColdToRam
    cold_to_vram = $expertTieringColdToVram
    ram_to_warm = $expertTieringRamToWarm
    vram_promotions = $expertTieringVramPromotions
    vram_demotions = $expertTieringVramDemotions
    ram_evictions = $expertTieringRamEvictions
    ram_admit_skips = $expertTieringRamAdmitSkips
    transient = $expertTieringTransient
    failures = $expertTieringFailures
    ssd_bytes = $expertTieringSsdBytes
    ram_h2d_bytes = $expertTieringRamH2DBytes
    policy_epochs = $expertTieringPolicyEpochs
    policy_free_promotions = $expertTieringPolicyFreePromotions
    policy_replacements = $expertTieringPolicyReplacements
    policy_min_frequency_skips = $expertTieringPolicyMinFrequencySkips
    policy_budget_skips = $expertTieringPolicyBudgetSkips
    policy_score_skips = $expertTieringPolicyScoreSkips
    states_ssd = $expertTieringStatesSsd
    states_probation = $expertTieringStatesProbation
    states_warm = $expertTieringStatesWarm
    states_vram = $expertTieringStatesVram
    mass_sum = $expertTieringMassSum
    lfru_top = $expertTieringLfruTop
}
$rawOutputs = [pscustomobject]@{
    schema = "g7_raw_outputs_v1"
    tag = $Tag
    head = $headAtStart
    executable_sha256 = $exeHashAtStart
    ds4_cuda_sha256 = $sourceHashAtStart
    prompt_sha256 = $promptHash
    system_prompt = $SystemPrompt
    system_prompt_sha256 = $systemPromptHash
    warmup_prompt_sha256 = $(if ($Warmup) { $warmupPromptHash } else { "" })
    expected_content_sha256 = if ($ExpectedContentSHA256) { $ExpectedContentSHA256.ToLowerInvariant() } else { "" }
    expected_warmup_content_sha256 = if ($ExpectedWarmupContentSHA256) { $ExpectedWarmupContentSHA256.ToLowerInvariant() } else { "" }
    warmup_result = $warmupResult
    output_hashes = $hashes
    outputs_identical = ($hashes.Count -eq 1)
    expert_tiering = $expertTieringResult
    results = $results
}
$rawOutputs | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 $rawOutputsPath
if ($Repeats -gt 1 -and $hashes.Count -ne 1) {
    throw "Measurement failed: repeated outputs were not identical"
}
if ($ExpectedContentSHA256) {
    $unexpected = @($results | Where-Object { $_.content_sha256 -ine $ExpectedContentSHA256 })
    if ($unexpected.Count -ne 0) {
        throw "Measurement failed: output hash differs from expected baseline"
    }
}
$arenaReportedResident = if ($PrefillMassWrap -and $prefillMassWrapResult -eq "published") {
    $prefillMassWrapResidentAfter
} else {
    $arenaObserverResident
}
$summary = [pscustomobject]@{
    tag = $Tag
    head = $headAtStart
    worktree_dirty = $worktreeDirtyAtStart
    ds4_cuda_sha256 = $sourceHashAtStart
    ds4_c_sha256 = $ds4SourceHashAtStart
    ds4_server_c_sha256 = $serverSourceHashAtStart
    ds4_spex_predict_c_sha256 = $spexSourceHashAtStart
    ds4_gpu_h_sha256 = $gpuHeaderHashAtStart
    ds4_spex_queue_h_sha256 = $spexQueueHeaderHashAtStart
    os_thread_h_sha256 = $threadHeaderHashAtStart
    cmake_sha256 = $cmakeHashAtStart
    executable_sha256 = $exeHashAtStart
    harness_sha256 = $harnessHashAtStart
    memory_preflight_harness_sha256 = $memoryPreflightHashAtStart
    runtime_monitor_harness_sha256 = $runtimeMonitorHashAtStart
    build_manifest_path = $buildManifestPath
    build_manifest_sha256 = $buildManifestHashAtStart
    build_manifest_input_fingerprint_sha256 = $buildManifest.input_fingerprint_sha256
    build_manifest_head = $buildManifest.head
    build_manifest_worktree_dirty_at_build_start = [bool]$buildManifest.worktree_dirty_at_build_start
    executable = $exe
    model = $model
    model_bytes = [long]$modelInfoAtStart.Length
    model_last_write_utc = $modelInfoAtStart.LastWriteTimeUtc.ToString("o")
    prompt = $Prompt
    prompt_file = $PromptFile
    prompt_sha256 = $promptHash
    system_prompt = $SystemPrompt
    system_prompt_sha256 = $systemPromptHash
    warmup_prompt = $(if ($Warmup) { $effectiveWarmupPrompt } else { "" })
    warmup_prompt_sha256 = $(if ($Warmup) { $warmupPromptHash } else { "" })
    warmup_prompt_distinct = [bool]($Warmup -and $effectiveWarmupPrompt -ne $Prompt)
    expected_content_sha256 = $ExpectedContentSHA256.ToLowerInvariant()
    expected_warmup_content_sha256 = $ExpectedWarmupContentSHA256.ToLowerInvariant()
    warmup_result = $warmupResult
    requested_max_tokens = $MaxTokens
    requested_warmup_max_tokens = $(if ($Warmup) { $effectiveWarmupMaxTokens } else { 0 })
    context_requested = $Context
    context_observed = $contextObserved
    prefill_chunk_requested = $PrefillChunk
    prefill_chunk_observed = $prefillChunkObserved
    prefill_union_stats_requested = [bool]$PrefillUnionStats
    prefill_waves_requested = [bool]$PrefillWaves
    prefill_wave_force_experts_requested = $PrefillWaveForceExperts
    prefill_wave_double_buffer_requested = [bool]$PrefillWaveDoubleBuffer
    generic_sorted_moe_requested = [bool]$GenericSortedMoe
    prefill_waves_observed = $prefillWavesObserved
    prefill_wave_activations = $prefillWaveActivations
    prefill_wave_layers = $prefillWaveLayers
    prefill_wave_count = $prefillWaveCount
    prefill_wave_max_experts = $prefillWaveMaxExperts
    prefill_wave_active_pairs = $prefillWaveActivePairs
    prefill_wave_unique_experts = $prefillWaveUniqueExperts
    prefill_wave_upload_waits = $prefillWaveUploadWaits
    prefill_wave_failures = $prefillWaveFailures
    prefill_wave_overlap_observed = $prefillWaveOverlapObserved
    prefill_wave_overlap_activations = $prefillWaveOverlapActivations
    prefill_wave_overlap_layers = $prefillWaveOverlapLayers
    prefill_wave_overlap_waves = $prefillWaveOverlapWaves
    prefill_wave_overlap_reuse_waits = $prefillWaveOverlapReuseWaits
    prefill_wave_overlap_compute_records = $prefillWaveOverlapComputeRecords
    prefill_wave_overlap_failures = $prefillWaveOverlapFailures
    prefill_union_stats_observed = $prefillUnionObserved
    prefill_union_calls = $prefillUnionCalls
    prefill_union_tokens = $prefillUnionTokens
    prefill_union_selected_slots = $prefillUnionSelectedSlots
    prefill_union_unique_experts = $prefillUnionUniqueExperts
    prefill_union_dedup_ratio = $prefillUnionDedupRatio
    prefill_union_max_tokens = $prefillUnionMaxTokens
    prefill_union_max_union = $prefillUnionMaxUnion
    prefill_union_arena_experts = $prefillUnionArenaExperts
    prefill_union_cache_hits = $prefillUnionCacheHits
    prefill_union_cache_admissions = $prefillUnionCacheAdmissions
    prefill_union_direct_experts = $prefillUnionDirectExperts
    prefill_union_spex_experts = $prefillUnionSpexExperts
    prefill_union_nonresident_experts = $prefillUnionNonresidentExperts
    prefill_union_source_span_bytes = $prefillUnionSourceSpanBytes
    prefill_union_arena_h2d_bytes = $prefillUnionArenaH2DBytes
    prefill_union_cache_d2d_bytes = $prefillUnionCacheD2DBytes
    prefill_union_upload_syncs = $prefillUnionUploadSyncs
    raw_kv_rows_observed = $rawKvRowsObserved
    compressed_kv_rows_observed = $compressedKvRowsObserved
    server_arguments = $argList
    inherited_ds4_environment = [pscustomobject]$inheritedDs4Environment
    effective_ds4_environment = [pscustomobject]$effectiveDs4Environment
    gpu_identity = $gpuIdentity
    repeats = $Repeats
    warmup = [bool]$Warmup
    budget_gb = $BudgetGB
    reserve_mb = $ReserveMB
    q8_f16_cache_mb_requested = $Q8F16CacheMB
    q8_f16_cache_reserve_mb_requested = $Q8F16CacheReserveMB
    q8_f16_cache_disabled = [bool]$DisableQ8F16Cache
    embed_row_staging_requested = [bool]$EmbedRowStaging
    dynamic_arena_gib_requested = $DynamicArenaGiB
    prefill_mass_observe_requested = [bool]$PrefillMassObserve
    prefill_mass_wrap_requested = [bool]$PrefillMassWrap
    compose_prefill_mass_tiering_requested = [bool]$ComposePrefillMassTiering
    reap_mass_observe_requested = [bool]($ReapMassObserve -or $ReapMassWrap)
    reap_mass_wrap_requested = [bool]$ReapMassWrap
    reap_mass_window_requested = $ReapMassWindow
    reap_mass_wrap_grow_interval_requested = $ReapMassGrowInterval
    reap_mass_wrap_hysteresis_requested = $ReapMassHysteresis
    reap_mass_observer_armed = $reapMassArmed
    reap_mass_result_observed = $reapMassResultObserved
    reap_mass_window_observed = $reapMassWindowObserved
    reap_mass_top_observed = $reapMassTopObserved
    reap_mass_armed_first_layer = $reapMassFirstLayer
    reap_mass_armed_last_layer = $reapMassLastLayer
    reap_mass_transport_observed = $reapMassTransport
    reap_mass_tokens = $reapMassTokens
    reap_mass_observed_slots = $reapMassObservedSlots
    reap_mass_unique_entries = $reapMassUnique
    reap_mass_top_mass = $reapMassTopMass
    reap_mass_touched_entries = $reapMassTouched
    reap_mass_semantics = $(if ($ReapMassWrap) { "decode-only selected gate weight normalized per token and layer; exact sliding window; fail-closed wrap publication" } else { "decode-only selected gate weight normalized per token and layer; exact sliding window; observe-only" })
    reap_mass_wrap_armed = $reapMassWrapArmed
    reap_mass_wrap_grow_interval_observed = $reapMassWrapGrowIntervalObserved
    reap_mass_wrap_hysteresis_observed = $reapMassWrapHysteresisObserved
    reap_mass_wrap_capacity_entries = $reapMassWrapCapacity
    reap_mass_wrap_armed_router = $reapMassWrapRouterArmed
    reap_mass_wrap_armed_mask = $reapMassWrapMaskArmed
    reap_mass_wrap_armed_policy = $reapMassWrapPolicyArmed
    reap_mass_wrap_observed = $reapMassWrapObserved
    reap_mass_wrap_event_count = $reapMassWrapEventCount
    reap_mass_wrap_publication_count = $reapMassWrapPublicationCount
    reap_mass_wrap_skipped_count = $reapMassWrapSkippedCount
    reap_mass_wrap_failure_count = $reapMassWrapFailureCount
    reap_mass_wrap_sum_entrants = $reapMassWrapEntrants
    reap_mass_wrap_sum_victims = $reapMassWrapVictims
    reap_mass_wrap_sum_loads = $reapMassWrapLoads
    reap_mass_wrap_sum_seconds = $reapMassWrapSeconds
    reap_mass_wrap_last_result = $reapMassWrapLastResult
    reap_mass_wrap_last_reason = $reapMassWrapLastReason
    reap_mass_wrap_last_tokens = $reapMassWrapLastTokens
    reap_mass_wrap_last_free_before = $reapMassWrapLastFreeBefore
    reap_mass_wrap_last_resident_before = $reapMassWrapLastResidentBefore
    reap_mass_wrap_last_resident_after = $reapMassWrapLastResidentAfter
    reap_mass_wrap_last_snapshot_before = $reapMassWrapLastSnapshotBefore
    reap_mass_wrap_last_snapshot_after = $reapMassWrapLastSnapshotAfter
    reap_mass_wrap_last_generation = $reapMassWrapLastGeneration
    reap_mass_wrap_last_workers = $reapMassWrapLastWorkers
    reap_mass_wrap_last_router = $reapMassWrapLastRouter
    reap_mass_wrap_last_mask = $reapMassWrapLastMask
    reap_mask_file_requested = $(if ($ReapMaskFile) { (Resolve-Path -LiteralPath $ReapMaskFile).Path } else { "" })
    reap_mask_reload_observed = $reapMaskReloadObserved
    reap_mask_applied_observed = $reapMaskAppliedObserved
    reap_mask_path_observed = $reapMaskPathObserved
    reap_mask_pruned_entries = $reapMaskAppliedPruned
    reap_mask_layers = $reapMaskAppliedLayers
    reap_mask_bias_layers = $reapMaskBiasLayers
    reap_mask_ranges_updated = $reapMaskRangesUpdated
    reap_mask_ranges_created = $reapMaskRangesCreated
    reap_mask_ranges_failed = $reapMaskRangesFailed
    reap_mask_ranges_applied = ($reapMaskRangesUpdated + $reapMaskRangesCreated)
    prefill_mass_observer_armed = $prefillMassArmed
    prefill_mass_finalized = $prefillMassFinalized
    prefill_mass_policy_observed = $prefillMassPolicy
    prefill_mass_residency_observed = $prefillMassResidency
    prefill_mass_wrap_observed = $prefillMassWrapObserved
    prefill_mass_wrap_event_count = $prefillMassWrapEventCount
    prefill_mass_wrap_result = $prefillMassWrapResult
    prefill_mass_wrap_reason = $prefillMassWrapReason
    prefill_mass_wrap_candidate_entries = $prefillMassWrapCandidate
    prefill_mass_wrap_loads = $prefillMassWrapLoads
    prefill_mass_wrap_workers = $prefillMassWrapWorkers
    prefill_mass_wrap_seconds = $prefillMassWrapSeconds
    prefill_mass_wrap_snapshot_before = $prefillMassWrapSnapshotBefore
    prefill_mass_wrap_snapshot_after = $prefillMassWrapSnapshotAfter
    prefill_mass_wrap_resident_before = $prefillMassWrapResidentBefore
    prefill_mass_wrap_resident_after = $prefillMassWrapResidentAfter
    prefill_mass_wrap_generation = $prefillMassWrapGeneration
    prefill_mass_wrap_preloaded = $prefillMassWrapPreloaded
    prefill_mass_wrap_router = $prefillMassWrapRouter
    prefill_mass_wrap_mask = $prefillMassWrapMask
    prefill_mass_compose_observed = $prefillMassComposeObserved
    prefill_mass_compose_event_count = $prefillMassComposeEventCount
    prefill_mass_compose_hash_layers = $prefillMassComposeHashLayers
    prefill_mass_compose_hash_seed_entries = $prefillMassComposeHashSeedEntries
    prefill_mass_compose_ranked_entries = $prefillMassComposeRankedEntries
    prefill_mass_compose_total_candidate = $prefillMassComposeTotalCandidate
    prefill_mass_compose_capacity = $prefillMassComposeCapacity
    prefill_mass_layers = $prefillMassLayers
    prefill_mass_rows_min = $prefillMassRowsMin
    prefill_mass_rows_max = $prefillMassRowsMax
    prefill_mass_routed_slots = $prefillMassRoutedSlots
    prefill_mass_unique_entries = $prefillMassUnique
    prefill_mass_candidate_entries = $prefillMassCandidate
    prefill_mass_capacity_entries = $prefillMassCapacity
    prefill_mass_total = $prefillMassTotal
    prefill_mass_candidate_mass = $prefillMassCandidateMass
    prefill_mass_coverage = $prefillMassCoverage
    prefill_mass_cutoff = $prefillMassCutoff
    prefill_mass_decode_tokens = $prefillMassDecodeTokens
    prefill_mass_decode_slots = $prefillMassDecodeSlots
    prefill_mass_decode_candidate_hits = $prefillMassDecodeHits
    prefill_mass_decode_hit_rate = $prefillMassDecodeHitRate
    prefill_mass_residency_semantics = $(if ($PrefillMassWrap) { "ranked prefill candidate published transactionally into pinned RAM; router and mask unchanged" } else { "observe-only; no router, mask, arena publication, or residency changes" })
    dynamic_arena_observed_window_requested = $DynamicArenaObservedWindow
    dynamic_arena_observed_min_hits_requested = $DynamicArenaObservedMinHits
    dynamic_arena_grow_interval_requested = $DynamicArenaGrowInterval
    dynamic_arena_carry_requested = $DynamicArenaCarry
    dynamic_arena_carry_observed = $arenaCarryObserved
    dynamic_arena_carry_line_count = $arenaCarryLineCount
    dynamic_arena_carry_request_observed = $arenaCarryRequest
    dynamic_arena_carry_mode_observed = $arenaCarryModeObserved
    dynamic_arena_carry_snapshot_observed = $arenaCarrySnapshot
    dynamic_arena_carry_resident_observed = $arenaCarryResident
    dynamic_arena_carry_lookup_observed = $arenaCarryLookupObserved
    dynamic_arena_carry_observer_observed = $arenaCarryObserverObserved
    dynamic_arena_carry_events = $arenaCarryEvents
    dynamic_arena_observer_publication_count = $arenaObserverPublicationCount
    dynamic_arena_wrap_publication_count = $arenaWrapPublicationCount
    reap_prefetch_threads_requested = $ReapPrefetchThreads
    minimum_available_gib_effective = $effectiveMinimumAvailableGiB
    dynamic_arena_allocated_bytes = $arenaAllocatedBytes
    dynamic_arena_allocated_slots = $arenaAllocatedSlots
    dynamic_arena_slot_bytes = $arenaSlotBytes
    dynamic_arena_observer_armed = $arenaObserverArmed
    dynamic_arena_observer_window_observed = $arenaObserverWindowObserved
    dynamic_arena_observer_min_hits_observed = $arenaObserverMinHitsObserved
    dynamic_arena_grow_interval_observed = $arenaObserverGrowIntervalObserved
    dynamic_arena_observer_first_layer = $arenaObserverFirstLayer
    dynamic_arena_observer_last_layer = $arenaObserverLastLayer
    dynamic_arena_observer_tokens = $arenaObserverTokens
    dynamic_arena_observer_resident = $arenaObserverResident
    dynamic_arena_observer_resident_bytes = [long]$arenaObserverResident * [long]$arenaSlotBytes
    dynamic_arena_resident_entries_reported = $arenaReportedResident
    dynamic_arena_resident_bytes_reported = [long]$arenaReportedResident * [long]$arenaSlotBytes
    dynamic_arena_occupancy_ratio = if ($arenaAllocatedBytes -gt 0) { ([double]$arenaReportedResident * [double]$arenaSlotBytes) / [double]$arenaAllocatedBytes } else { $null }
    dynamic_arena_wrap_observed = $arenaWrapObserved
    dynamic_arena_wrap_loads = $arenaWrapLoads
    dynamic_arena_wrap_workers = $arenaWrapWorkers
    dynamic_arena_wrap_seconds = $arenaWrapSeconds
    dynamic_arena_wrap_generation = $arenaWrapGeneration
    dynamic_arena_wrap_preloaded = $arenaWrapPreloaded
    dynamic_arena_wrap_mirror_gib = $arenaWrapMirrorGiB
    dynamic_arena_verify_workers = $arenaVerifyWorkers
    dynamic_arena_verify_seconds = $arenaVerifySeconds
    dynamic_arena_observer_result_observed = $arenaObserverResultObserved
    dynamic_arena_observer_result = $arenaObserverResult
    dynamic_arena_observer_published = ($arenaObserverResult -eq "published")
    dynamic_arena_observer_fallback = ($arenaObserverResult -eq "fallback")
    dynamic_arena_growth_publications = $arenaGrowthPublications
    dynamic_arena_growth_skips = $arenaGrowthSkips
    dynamic_arena_growth_events = $arenaGrowthEvents
    dynamic_arena_final_observed = $arenaFinalObserved
    dynamic_arena_final_hits = $arenaFinalHits
    dynamic_arena_final_misses = $arenaFinalMisses
    dynamic_arena_final_fatal = $arenaFinalFatal
    dynamic_arena_hit_rate = if (($arenaFinalHits + $arenaFinalMisses) -gt 0) { [double]$arenaFinalHits / [double]($arenaFinalHits + $arenaFinalMisses) } else { $null }
    dynamic_arena_miss_rate = if (($arenaFinalHits + $arenaFinalMisses) -gt 0) { [double]$arenaFinalMisses / [double]($arenaFinalHits + $arenaFinalMisses) } else { $null }
    dynamic_arena_h2d_uploaded_gib = $arenaFinalUploadedGiB
    dynamic_arena_h2d_uploaded_semantics = "Pinned host arena to compact VRAM selected-expert tensors; not SSD or mmap read traffic"
    no_selected_load = [bool]$NoSelectedLoad
    diagnostics = [bool]$Diagnostics
    memory_preflight = $memoryPreflight
    runtime_telemetry = $runtimeTelemetry
    moe_io_queue_depth = $IoQD
    moe_io_queue_depth_observed = $observedIoQD
    moe_overlapped_io_observed = $overlappedIoObserved
    moe_overlapped_io_fallbacks = $overlappedIoFallbacks
    expert_cache_requested = $ExpertCacheN
    expert_cache_reserve_gb = $ExpertCacheReserveGB
    expert_cache_policy = $ExpertCachePolicy
    expert_tiering_requested = $ExpertTiering
    expert_tier_policy_requested = $ExpertTierPolicy
    expert_tier_clock_calls_requested = $ExpertTierClockCalls
    expert_tier_replacement_budget_requested = $ExpertTierReplacementBudget
    expert_tier_min_frequency_requested = $ExpertTierMinFrequency
    expert_tier_hysteresis_requested = $ExpertTierHysteresis
    expert_tiering = $expertTieringResult
    direct_cache_hits_requested = [bool]$DirectCacheHits
    mixed_direct_cache_requested = [bool]$MixedDirectCache
    mixed_direct_cache_observed = $mixedDirectObserved
    mixed_direct_calls = $mixedDirectCalls
    mixed_direct_cache_routes = $mixedDirectCacheRoutes
    mixed_direct_compact_routes = $mixedDirectCompactRoutes
    route_profile_requested = [bool]$RouteProfile
    route_profile_observed = $routeProfileObserved
    route_profile_calls = $routeProfileCalls
    route_profile_d2h_ms_per_call = $routeProfileD2HMs
    route_profile_observe_ms_per_call = $routeProfileObserveMs
    route_profile_map_ms_per_call = $routeProfileMapMs
    route_profile_transport_ms_per_call = $routeProfileTransportMs
    route_profile_publish_ms_per_call = $routeProfilePublishMs
    gpu_resident_routes_requested = [bool]$GpuResidentRoutes
    split_hit_miss_requested = [bool]$SplitHitMiss
    gpu_resident_routes_observed = $gpuRoutesObserved
    gpu_resident_routes_calls = $gpuRoutesCalls
    gpu_resident_routes_split_calls = $gpuRoutesSplitCalls
    gpu_resident_routes_all_hit = $gpuRoutesAllHit
    gpu_resident_routes_worker_jobs = $gpuRoutesWorkerJobs
    gpu_resident_routes_miss_experts = $gpuRoutesMissExperts
    gpu_resident_routes_errors = $gpuRoutesErrors
    gpu_resident_routes_worker_ms_per_job = $gpuRoutesWorkerMs
    gpu_resident_routes_resolve_ms_per_call = $gpuRoutesResolveMs
    gpu_resident_routes_wait_ms_per_call = $gpuRoutesWaitMs
    expert_cache_stats_enabled = [bool]$ExpertCacheStats
    expert_cache_stats_interval = $ExpertCacheStatsInterval
    overlap_shared_requested = [bool]$OverlapShared
    overlap_shared_observed = $overlapSharedObserved
    overlap_shared_full_requested = [bool]$OverlapSharedFull
    overlap_shared_full_observed = $overlapSharedFullObserved
    shared_down_fusion_disabled = [bool]$DisableSharedDownFusion
    spex_dry_run_requested = [bool]$SpexDryRun
    spex_file = $SpexFile
    spex_file_sha256 = $spexHashAtStart
    expected_spex_file_sha256 = if ($ExpectedSpexSHA256) { $ExpectedSpexSHA256.ToLowerInvariant() } else { "" }
    spex_cap_requested = $(if ($SpexDryRun) { $effectiveSpexCap } else { 0 })
    spex_stage_requested = $(if ($SpexDryRun) { $SpexStage } else { "off" })
    spex_fused_topk_requested = [bool]$SpexFusedTopK
    spex_ring_slots_requested = $(if ($SpexDryRun) { $SpexRingSlots } else { 0 })
    spex_prefetch_k_requested = $SpexPrefetchK
    spex_cpu_probe_k_requested = $SpexCpuProbeK
    spex_cpu_probe_final_observed = $spexCpuProbeFinalObserved
    spex_cpu_probe_line_count = $spexCpuProbeLineCount
    spex_cpu_probe_k_observed = $spexCpuProbeKObserved
    spex_cpu_probe_submitted = $spexCpuProbeSubmitted
    spex_cpu_probe_dropped = $spexCpuProbeDropped
    spex_cpu_probe_completed = $spexCpuProbeCompleted
    spex_cpu_probe_predicted = $spexCpuProbePredicted
    spex_cpu_probe_matched = $spexCpuProbeMatched
    spex_cpu_probe_ready_at_transport = $spexCpuProbeReadyAtTransport
    spex_cpu_probe_useful_ready = $spexCpuProbeUsefulReady
    spex_cpu_probe_failures = $spexCpuProbeFailures
    spex_cpu_probe_d2h_wait_ms = $spexCpuProbeD2HWaitMs
    spex_cpu_probe_cpu_ms = $spexCpuProbeCpuMs
    spex_cpu_probe_queue_ms = $spexCpuProbeQueueMs
    spex_cpu_probe_checksum = $spexCpuProbeChecksum
    spex_prefetch_observed = $spexPrefetchObserved
    spex_prefetch_k_observed = $spexPrefetchKObserved
    spex_prefetch_slots_observed = $spexPrefetchSlotsObserved
    spex_prefetch_final_observed = $spexPrefetchFinalObserved
    spex_prefetch_submitted = $spexPrefetchSubmitted
    spex_prefetch_dropped = $spexPrefetchDropped
    spex_prefetch_loaded = $spexPrefetchLoaded
    spex_prefetch_matched = $spexPrefetchMatched
    spex_prefetch_hits = $spexPrefetchHits
    spex_prefetch_no_hits = $spexPrefetchNoHits
    spex_prefetch_late = $spexPrefetchLate
    spex_prefetch_canceled = $spexPrefetchCanceled
    spex_prefetch_poisoned = $spexPrefetchPoisoned
    spex_prefetch_errors = $spexPrefetchErrors
    spex_prefetch_disabled = $spexPrefetchDisabled
    spex_prefetch_bytes_read = $spexPrefetchBytesRead
    spex_prefetch_bytes_used = $spexPrefetchBytesUsed
    spex_observed = $spexObserved
    spex_stage_observed = $spexObservedStage
    spex_fused_topk_observed = $spexFusedObserved
    spex_ring_slots_observed = $spexRingObserved
    spex_disabled = $spexDisabled
    spex_cap_observed = $spexObservedCap
    spex_scheduled = $spexScheduled
    spex_ready = $spexReady
    spex_not_ready = $spexNotReady
    spex_compared_layers = $spexLayers
    spex_actual_experts = $spexActual
    spex_predicted_experts = $spexPredicted
    spex_hits = $spexHits
    spex_recall = $spexRecall
    spex_recall_scope = $spexRecallScope
    spex_ready_coverage = $spexReadyCoverage
    spex_precision = $spexPrecision
    spex_no_actual = $spexNoActual
    spex_late = $spexLate
    spex_ring_full = $spexRingFull
    spex_stale = $spexStale
    expert_cache_calls = $cacheCalls
    expert_cache_last_layer = $cacheLastLayer
    expert_cache_last_compact = $cacheLastCompact
    expert_cache_capacity = $cacheCapacity
    expert_cache_count = $cacheCount
    expert_cache_hits = $cacheHits
    expert_cache_misses = $cacheMisses
    expert_cache_admissions = $cacheAdmissions
    expert_cache_evictions = $cacheEvictions
    expert_cache_direct_loads = $cacheDirect
    load_seconds = [math]::Round($loadSec, 6)
    warmup_seconds = [math]::Round($warmSec, 6)
    mean_tokens_per_second = $meanTps
    min_tokens_per_second = $minTps
    max_tokens_per_second = $maxTps
    server_decode_mean_tokens_per_second = $serverDecodeMeanTps
    server_decode_min_tokens_per_second = $serverDecodeMinTps
    server_decode_max_tokens_per_second = $serverDecodeMaxTps
    server_prefill_ttft_mean_seconds = $serverPrefillTtftMean
    server_runs = $serverRuns
    outputs_identical = ($hashes.Count -eq 1)
    results = $results
}
$summary | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 $resultPath

Write-Host ""
Write-Host "================ G7 RESULT ($Tag) ================"
Write-Host ("http_ok       : " + $httpOk)
Write-Host ("repeats       : " + $Repeats)
Write-Host ("content       : [" + $(if ($results.Count) { $results[-1].content } else { "" }) + "]")
Write-Host ("load_sec      : " + [math]::Round($loadSec,1))
Write-Host ("warm_sec      : " + [math]::Round($warmSec,2) + "  (warmup pass, discarded)")
Write-Host ("t/s mean/min/max: " + $meanTps + " / " + $minTps + " / " + $maxTps)
Write-Host ("server decode t/s mean/min/max: " + $serverDecodeMeanTps + " / " + $serverDecodeMinTps + " / " + $serverDecodeMaxTps)
Write-Host ("server prefill/TTFT mean sec: " + $serverPrefillTtftMean)
Write-Host ("outputs_identical: " + ($hashes.Count -eq 1))
Write-Host ("ctx requested/observed, prefill chunk, raw/compressed KV rows: " + $Context + " / " + $contextObserved + " / " + $prefillChunkObserved + " / " + $rawKvRowsObserved + " / " + $compressedKvRowsObserved)
Write-Host ("prefill union requested/observed calls/tokens/slots/unique/dedup/max-union: " + [bool]$PrefillUnionStats + " / " + $prefillUnionObserved + " / " + $prefillUnionCalls + " / " + $prefillUnionTokens + " / " + $prefillUnionSelectedSlots + " / " + $prefillUnionUniqueExperts + " / " + $prefillUnionDedupRatio + " / " + $prefillUnionMaxUnion)
Write-Host ("prefill union source/arena-H2D/cache-D2D GiB, syncs: " + [math]::Round($prefillUnionSourceSpanBytes / 1GB, 3) + " / " + [math]::Round($prefillUnionArenaH2DBytes / 1GB, 3) + " / " + [math]::Round($prefillUnionCacheD2DBytes / 1GB, 3) + " / " + $prefillUnionUploadSyncs)
Write-Host ("prefill waves requested/observed/force/activations/layers/waves/max/active-pairs/unique/waits/failures: " + [bool]$PrefillWaves + " / " + $prefillWavesObserved + " / " + $PrefillWaveForceExperts + " / " + $prefillWaveActivations + " / " + $prefillWaveLayers + " / " + $prefillWaveCount + " / " + $prefillWaveMaxExperts + " / " + $prefillWaveActivePairs + " / " + $prefillWaveUniqueExperts + " / " + $prefillWaveUploadWaits + " / " + $prefillWaveFailures)
Write-Host ("prefill wave overlap requested/observed/activations/layers/waves/reuse-waits/compute-records/failures: " + [bool]$PrefillWaveDoubleBuffer + " / " + $prefillWaveOverlapObserved + " / " + $prefillWaveOverlapActivations + " / " + $prefillWaveOverlapLayers + " / " + $prefillWaveOverlapWaves + " / " + $prefillWaveOverlapReuseWaits + " / " + $prefillWaveOverlapComputeRecords + " / " + $prefillWaveOverlapFailures)
Write-Host ("Q8-F16 cap/reserve MiB requested: " + $Q8F16CacheMB + " / " + $Q8F16CacheReserveMB)
Write-Host ("effective DS4 env: " + (($effectiveDs4Environment.GetEnumerator() | ForEach-Object { $_.Key + "=" + $_.Value }) -join "; "))
Write-Host ("prefill mass observe/wrap requested, policy, armed/finalized: " + [bool]$PrefillMassObserve + " / " + [bool]$PrefillMassWrap + " / " + $prefillMassPolicy + " / " + $prefillMassArmed + " / " + $prefillMassFinalized)
Write-Host ("prefill mass unique/candidate/capacity/mass coverage/decode hit rate: " + $prefillMassUnique + " / " + $prefillMassCandidate + " / " + $prefillMassCapacity + " / " + $prefillMassCoverage + " / " + $prefillMassDecodeHitRate)
Write-Host ("prefill mass WRAP events/result/reason/candidate/loads/workers/sec: " + $prefillMassWrapEventCount + " / " + $prefillMassWrapResult + " / " + $prefillMassWrapReason + " / " + $prefillMassWrapCandidate + " / " + $prefillMassWrapLoads + " / " + $prefillMassWrapWorkers + " / " + $prefillMassWrapSeconds)
Write-Host ("prefill mass WRAP snapshot before/after, resident before/after, generation: " + $prefillMassWrapSnapshotBefore + " / " + $prefillMassWrapSnapshotAfter + " / " + $prefillMassWrapResidentBefore + " / " + $prefillMassWrapResidentAfter + " / " + $prefillMassWrapGeneration)
Write-Host ("REAP mass requested/armed/window/top/transport/tokens/slots/unique/top mass/touched: " + [bool]($ReapMassObserve -or $ReapMassWrap) + " / " + $reapMassArmed + " / " + $reapMassWindowObserved + " / " + $reapMassTopObserved + " / " + $reapMassTransport + " / " + $reapMassTokens + " / " + $reapMassObservedSlots + " / " + $reapMassUnique + " / " + $reapMassTopMass + " / " + $reapMassTouched)
Write-Host ("REAP mass WRAP requested/armed/grow/hysteresis/capacity/router/mask/policy: " + [bool]$ReapMassWrap + " / " + $reapMassWrapArmed + " / " + $reapMassWrapGrowIntervalObserved + " / " + $reapMassWrapHysteresisObserved + " / " + $reapMassWrapCapacity + " / " + $reapMassWrapRouterArmed + " / " + $reapMassWrapMaskArmed + " / " + $reapMassWrapPolicyArmed)
Write-Host ("REAP mass WRAP events/published/skipped/failed/entrants/victims/loads/sec: " + $reapMassWrapEventCount + " / " + $reapMassWrapPublicationCount + " / " + $reapMassWrapSkippedCount + " / " + $reapMassWrapFailureCount + " / " + $reapMassWrapEntrants + " / " + $reapMassWrapVictims + " / " + $reapMassWrapLoads + " / " + $reapMassWrapSeconds)
Write-Host ("REAP mass WRAP last result/reason/resident before/after/generation: " + $reapMassWrapLastResult + " / " + $reapMassWrapLastReason + " / " + $reapMassWrapLastResidentBefore + " / " + $reapMassWrapLastResidentAfter + " / " + $reapMassWrapLastGeneration)
Write-Host ("arena observer armed/window/minhits/grow/tokens/resident: " + $arenaObserverArmed + " / " + $arenaObserverWindowObserved + " / " + $arenaObserverMinHitsObserved + " / " + $arenaObserverGrowIntervalObserved + " / " + $arenaObserverTokens + " / " + $arenaObserverResident)
Write-Host ("arena carry requested: " + $DynamicArenaCarry)
Write-Host ("arena carry observed/request/mode/snapshot/resident/lookup/observer: " + $arenaCarryObserved + " / " + $arenaCarryRequest + " / " + $arenaCarryModeObserved + " / " + $arenaCarrySnapshot + " / " + $arenaCarryResident + " / " + $arenaCarryLookupObserved + " / " + $arenaCarryObserverObserved)
Write-Host ("arena publication/window+WRAP counts: " + $arenaObserverPublicationCount + " / " + $arenaWrapPublicationCount)
Write-Host ("arena growth publications/skips: " + $arenaGrowthPublications + " / " + $arenaGrowthSkips)
Write-Host ("arena WRAP loads/workers/sec/generation/preloaded/mirror GiB: " + $arenaWrapLoads + " / " + $arenaWrapWorkers + " / " + $arenaWrapSeconds + " / " + $arenaWrapGeneration + " / " + $arenaWrapPreloaded + " / " + $arenaWrapMirrorGiB)
Write-Host ("arena verify workers/sec: " + $arenaVerifyWorkers + " / " + $arenaVerifySeconds)
Write-Host ("arena result/final hits/misses/fatal/H2D GiB: " + $arenaObserverResult + " / " + $arenaFinalHits + " / " + $arenaFinalMisses + " / " + $arenaFinalFatal + " / " + $arenaFinalUploadedGiB)
Write-Host ("arena allocated/resident bytes/occupancy: " + $arenaAllocatedBytes + " / " + ([long]$arenaReportedResident * [long]$arenaSlotBytes) + " / " + $summary.dynamic_arena_occupancy_ratio)
Write-Host ("arena hit/miss rate: " + $summary.dynamic_arena_hit_rate + " / " + $summary.dynamic_arena_miss_rate)
Write-Host ("runtime telemetry samples/requested ms/effective sec: " + $runtimeTelemetry.samples + " / " + $runtimeTelemetry.requested_interval_ms + " / " + [math]::Round($runtimeTelemetry.effective_interval_seconds, 3))
Write-Host ("WDDM shared peak/median GiB: " + [math]::Round($runtimeTelemetry.gpu_process_shared_peak_bytes / 1GB, 3) + " / " + [math]::Round($runtimeTelemetry.gpu_process_shared_median_bytes / 1GB, 3))
Write-Host ("WDDM dedicated peak GiB / VRAM peak MiB: " + [math]::Round($runtimeTelemetry.gpu_process_dedicated_peak_bytes / 1GB, 3) + " / " + $runtimeTelemetry.vram_used_peak_mib)
Write-Host ("process working/private peak GiB: " + [math]::Round($runtimeTelemetry.process_working_set_peak_bytes / 1GB, 3) + " / " + [math]::Round($runtimeTelemetry.process_private_peak_bytes / 1GB, 3))
Write-Host ("GPU util median/peak percent: " + $runtimeTelemetry.gpu_utilization_median_percent + " / " + $runtimeTelemetry.gpu_utilization_peak_percent)
Write-Host ("Win32 process read/write delta GiB (excludes mmap page-ins): " + [math]::Round($runtimeTelemetry.win32_process_read_transfer_delta_bytes / 1GB, 3) + " / " + [math]::Round($runtimeTelemetry.win32_process_write_transfer_delta_bytes / 1GB, 3))
Write-Host ("process page-fault delta / mmap I/O measured: " + $runtimeTelemetry.page_fault_delta + " / " + $runtimeTelemetry.mmap_backed_file_io_measured)
Write-Host ("evictions     : " + $evicts)
Write-Host ("streams_expert: " + $streamsExpert)
Write-Host ("streams_hot   : " + $streamsHot)
Write-Host ("selected_loads: " + $selLoads)
Write-Host ("moe_io_qd req/observed: " + $IoQD + " / " + $observedIoQD)
Write-Host ("moe_io_fallbacks: " + $overlappedIoFallbacks)
Write-Host ("expert_cache req/cap/count: " + $ExpertCacheN + " / " + $cacheCapacity + " / " + $cacheCount)
Write-Host ("expert_cache hits/misses/evictions/direct: " + $cacheHits + " / " + $cacheMisses + " / " + $cacheEvictions + " / " + $cacheDirect)
Write-Host ("expert_tiering requested/observed/calls/selected/failures/states vram/mass/lfru: " + $ExpertTiering + " / " + $expertTieringModeObserved + " / " + $expertTieringCalls + " / " + $expertTieringSelected + " / " + $expertTieringFailures + " / " + $expertTieringStatesVram + " / " + $expertTieringMassSum + " / " + $expertTieringLfruTop)
Write-Host ("mixed direct requested/observed/calls/cache routes/compact routes: " + [bool]$MixedDirectCache + " / " + $mixedDirectObserved + " / " + $mixedDirectCalls + " / " + $mixedDirectCacheRoutes + " / " + $mixedDirectCompactRoutes)
Write-Host ("route profile requested/observed/calls d2h/observe/map/transport/publish ms: " + [bool]$RouteProfile + " / " + $routeProfileObserved + " / " + $routeProfileCalls + " / " + $routeProfileD2HMs + " / " + $routeProfileObserveMs + " / " + $routeProfileMapMs + " / " + $routeProfileTransportMs + " / " + $routeProfilePublishMs)
Write-Host ("gpu resident routes requested/split/observed/calls/split-calls/all-hit/jobs/miss-experts/errors/worker-ms/resolve-ms/wait-ms: " + [bool]$GpuResidentRoutes + " / " + [bool]$SplitHitMiss + " / " + $gpuRoutesObserved + " / " + $gpuRoutesCalls + " / " + $gpuRoutesSplitCalls + " / " + $gpuRoutesAllHit + " / " + $gpuRoutesWorkerJobs + " / " + $gpuRoutesMissExperts + " / " + $gpuRoutesErrors + " / " + $gpuRoutesWorkerMs + " / " + $gpuRoutesResolveMs + " / " + $gpuRoutesWaitMs)
Write-Host ("overlap_shared requested/observed: " + [bool]$OverlapShared + " / " + $overlapSharedObserved)
Write-Host ("overlap_shared_full requested/observed: " + [bool]$OverlapSharedFull + " / " + $overlapSharedFullObserved)
Write-Host ("shared_down_fusion_disabled: " + [bool]$DisableSharedDownFusion)
Write-Host ("spex requested/observed stage/cap: " + [bool]$SpexDryRun + " / " + $spexObserved + " / " + $spexObservedStage + " / " + $spexObservedCap)
Write-Host ("spex layers/hits/actual recall: " + $spexLayers + " / " + $spexHits + " / " + $spexActual + " / " + $spexRecall)
Write-Host ("spex recall scope/ready coverage: " + $spexRecallScope + " / " + $(if ($null -eq $spexReadyCoverage) { "n/a" } else { $spexReadyCoverage }))
Write-Host ("spex ring/late/full/stale: " + $spexRingObserved + " / " + $spexLate + " / " + $spexRingFull + " / " + $spexStale)
Write-Host ("spex cpu probe req/observed/submitted/dropped/completed/predicted/matched/ready/useful/failures: " + $SpexCpuProbeK + " / " + $spexCpuProbeKObserved + " / " + $spexCpuProbeSubmitted + " / " + $spexCpuProbeDropped + " / " + $spexCpuProbeCompleted + " / " + $spexCpuProbePredicted + " / " + $spexCpuProbeMatched + " / " + $spexCpuProbeReadyAtTransport + " / " + $spexCpuProbeUsefulReady + " / " + $spexCpuProbeFailures)
Write-Host ("spex cpu probe d2h/cpu/queue ms checksum: " + $spexCpuProbeD2HWaitMs + " / " + $spexCpuProbeCpuMs + " / " + $spexCpuProbeQueueMs + " / " + $spexCpuProbeChecksum)
Write-Host ("spex prefetch req/observed/submitted/matched/consumed/late/errors: " + $SpexPrefetchK + " / " + $spexPrefetchKObserved + " / " + $spexPrefetchSubmitted + " / " + $spexPrefetchMatched + " / " + $spexPrefetchHits + " / " + $spexPrefetchLate + " / " + $spexPrefetchErrors)
Write-Host ("last_sel_line : " + $lastSel)
Write-Host "=================================================="
