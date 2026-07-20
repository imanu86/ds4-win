# G7 selected-load measurement harness (ASCII only, PS 5.1 safe)
# Usage: powershell -File g7_measure.ps1 -MaxTokens 8 -TimeoutSec 900 -Tag new [-NoSelectedLoad]
param(
    [int]$MaxTokens = 8,
    [ValidateRange(0, 131072)][int]$WarmupMaxTokens = 0,
    [int]$Repeats = 1,
    [switch]$AllowNonIdenticalRepeatOutputs,
    [int]$TimeoutSec = 900,
    [string]$Tag = "run",
    [string]$Prompt = "Hi",
    [string]$PromptFile = "",
    [string]$SystemPrompt = "",
    [string]$StopSequence = "",
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
    [ValidateRange(0.0, 64.0)][double]$DynamicArenaMinAvailableGiB = 0.0,
    [switch]$ArenaWrapTrustWorkerChecksum,
    [switch]$ArenaWrapSourceParts,
    [switch]$ArenaWrapSequentialFile,
    [switch]$ArenaWrapRandomFile,
    [ValidateRange(1, 32)][int]$ArenaWrapSequentialWorkers = 1,
    [ValidateRange(1, 64)][int]$ArenaWrapFileQD = 1,
    [switch]$ArenaWrapPartProfile,
    [switch]$ArenaWrapLayoutProfile,
    [ValidateRange(0.001, 600000.0)][double]$ArenaWrapSlowPartMs = 25.0,
    [switch]$ArenaWrapTrimBetweenPhases,
    [switch]$ArenaWrapUnlockSourceRanges,
    [ValidateRange(0.0, 64.0)][double]$ArenaWrapUnlockWaveGiB = 0.0,
    [switch]$PrefillMassObserve,
    [switch]$PrefillMassWrap,
    [switch]$ComposePrefillMassTiering,
    [switch]$ComposePrefillMassOpenRouter,
    [switch]$ForceOpenRouter,
    [ValidateRange(0, 512)][int]$ComposePrefillMassReserveSlots = 0,
    [ValidateRange(0, 40)][int]$PrefillMassLayerFullEvery = 0,
    [ValidateRange(0, 39)][int]$PrefillMassLayerFullPhase = 0,
    [ValidateRange(0, 32)][int]$PrefillVramSeedPerLayer = 0,
    [ValidateRange(0, 512)][int]$PrefillVramSeedTotal = 0,
    [ValidateRange(0, 32)][int]$PrefillVramSeedFloorPerLayer = 0,
    [switch]$ReapMassObserve,
    [switch]$ReapMassWrap,
    [string]$ReapMaskFile = "",
    [switch]$AllowEmbeddedBakeMask,
    [string]$ExpectedEmbeddedBakeMaskSHA256 = "",
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
    [switch]$ExpertTierAdaptiveBudget,
    [ValidateRange(1, 512)][int]$ExpertTierAdaptiveMin = 16,
    [ValidateRange(1, 512)][int]$ExpertTierAdaptiveMax = 32,
    [ValidateRange(1, 512)][int]$ExpertTierAdaptiveStep = 8,
    [ValidateRange(1, 1000000)][int]$ExpertTierAdaptivePressureThreshold = 64,
    [ValidateRange(2, 1000000)][int]$ExpertTierMinFrequency = 3,
    [ValidateRange(1.0, 100.0)][double]$ExpertTierHysteresis = 1.25,
    [switch]$DirectCacheHits,
    [switch]$MixedDirectCache,
    [switch]$GpuResidentRoutes,
    [switch]$RouteNoDefaultSync,
    [switch]$RoutePackedCopy,
    [switch]$SplitHitMiss,
    [switch]$SplitFused,
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
    [string]$ExpectedModelSHA256 = "",
    [switch]$ReuseVerifiedModelReceipt,
    [string]$Q1_0ExpertSidecar = "",
    [string]$ExpectedQ1_0ExpertSidecarSHA256 = "",
    [UInt64]$ExpectedQ1_0ExpertSidecarBytes = 0,
    [switch]$ReuseVerifiedQ1_0Receipt,
    [switch]$AllowBenchmarkVerifiedReceiptReuse,
    [ValidateRange(0, 42)][int]$Q1_0LayerFirst = 3,
    [ValidateRange(0, 42)][int]$Q1_0LayerLast = 42,
    [switch]$Q1_0SelectedLoad,
    [switch]$Q1_0ResidentArena,
    [switch]$Q1_0DualArena,
    [switch]$Q1_0DualSparseCompanion,
    [switch]$Q1_0MixedColdOne,
    [switch]$Q1_0SnapshotBacking,
    [switch]$Q1_0PageableOverflow,
    [ValidateRange(0.0, 64.0)][double]$Q1_0ArenaGB = 0.0,
    [switch]$Q1_0DynamicPromotion,
    [switch]$Q1_0PromotionSsdWrap,
    [ValidateRange(0.125, 5.5)][double]$Q1_0Iq2PinnedGiB = 1.5,
    [switch]$Q1_0SsdWrapParserSelfTest,
    [switch]$Q1_0Profile,
    [switch]$Q1_0ProfileParserSelfTest,
    [switch]$ExpertRecoveryTrace,
    [ValidateRange(0, 42)][int]$ExpertRecoveryTraceLayer = 0,
    [ValidateRange(0, 255)][int]$ExpertRecoveryTraceExpert = 0,
    [ValidateRange(1, 256)][int]$ExpertRecoveryTraceMaxSamples = 256,
    [ValidateRange(4096, 16777216)]
    [UInt64]$ExpertRecoveryTraceByteBudget = 8388608,
    [string]$ExpertRecoveryTraceOutputPath = "",
    [switch]$ExpertRecoveryTraceParserSelfTest,
    [ValidateRange(1, 512)][int]$Q1_0PromotionProbationSlots = 16,
    [ValidateRange(1, 1000000)][int]$Q1_0PromotionMinTouches = 1,
    [ValidateRange(0.0, 1000000.0)][double]$Q1_0PromotionMinWeight = 0.0,
    [ValidateRange(0.0, 1000000.0)][double]$Q1_0PromotionMinMass = 0.0,
    [ValidateRange(0, 1000000)][int]$Q1_0PromotionRequestBudget = 0,
    [ValidateRange(0, 1000000)][int]$Q1_0PromotionWindowCalls = 0,
    [ValidateRange(0, 1000000)][int]$Q1_0PromotionWindowBudget = 0,
    [switch]$Q1_0PureResident,
    [ValidateRange(0, 11008)][int]$ExpectedQ1_0SnapshotEntries = 0,
    [ValidateRange(0, 11008)][int]$ExpectedQ1_0ResidentEntries = 0,
    [switch]$Q1_0MixedTrace,
    [string]$NestedResidualSidecar = "",
    [string]$ExpectedNestedResidualSidecarSHA256 = "",
    [string]$ExpectedNestedResidualSourceSHA256 = "",
    [string]$ExpectedNestedResidualPayloadSHA256 = "",
    [switch]$NestedResidualVerifyReconstruction,
    [switch]$NestedResidualProfile,
    [switch]$NestedResidualPageableBase,
    [ValidateRange(0.0, 30.0)][double]$NestedResidualBasePinnedGiB = 0,
    [switch]$NestedResidualCachePageable,
    [ValidateRange(0, 4096)][int]$NestedResidualCacheExperts = 6,
    [switch]$NestedResidualStructuralN1,
    [switch]$NestedResidualGpuCache,
    [switch]$NestedResidualGpuJoin,
    [switch]$NestedResidualGpuJoinResidualCache,
    [string]$NestedResidualGpuJoinSafetyReceipt = "",
    [string]$ExpectedNestedResidualGpuJoinSafetyReceiptSHA256 = "",
    [switch]$AllowNestedResidualBenchmarkSuite,
    [ValidateRange(0, 64)][int]$OuterNestedResidualBenchmarkProcessCount = 0,
    [string]$Iq1SExpertSidecar = "",
    [string]$ExpectedIq1SExpertSidecarSHA256 = "",
    [UInt64]$ExpectedIq1SExpertSidecarBytes = 0,
    [switch]$ReuseVerifiedIq1SReceipt,
    [string]$ModelIq1SuiteReceiptPath = "",
    [string]$ExpectedModelIq1SuiteReceiptSHA256 = "",
    [switch]$ReuseVerifiedSuiteReceipt,
    [switch]$AllowQualityVerifiedSuiteReceipt,
    [ValidateRange(0, 64)][int]$OuterQualityProcessCount = 0,
    [ValidateRange(0, 42)][int]$Iq1SLayerFirst = 0,
    [ValidateRange(0, 42)][int]$Iq1SLayerLast = 42,
    [switch]$Iq1SMixedColdOne,
    [switch]$Iq1SMixedGpuPlan,
    [switch]$Iq1Promotion,
    [ValidateRange(1, 512)][int]$Iq1PromotionProbationSlots = 16,
    [ValidateRange(1, 1000000)][int]$Iq1PromotionMinTouches = 1,
    [ValidateRange(0.0, 1000000.0)][double]$Iq1PromotionMinWeight = 0.0,
    [ValidateRange(0.0, 1000000.0)][double]$Iq1PromotionMinMass = 0.0,
    [ValidateRange(0, 1000000)][int]$Iq1PromotionRequestBudget = 0,
    [ValidateRange(0, 1000000)][int]$Iq1PromotionWindowCalls = 0,
    [ValidateRange(0, 1000000)][int]$Iq1PromotionWindowBudget = 0,
    [ValidateRange(0.0, 48.0)][double]$Iq1SRamCacheGiB = 0.0,
    [switch]$Iq1SRamCachePageable,
    [switch]$Iq1SRamCachePreloadAll,
    [switch]$Iq1SMixedDebug,
    [switch]$Iq1SProfile,
    [switch]$Iq1SNoMainSync,
    [switch]$Iq1SPackedH2D,
    [ValidateSet(0, 1, 2, 4)][int]$Iq1SVramCachePerLayer = 0,
    [ValidateSet("benchmark", "structural-safety", "quality")][string]$GateKind = "benchmark",
    [int]$Port = 8000,
    [ValidateRange(64, 131072)][int]$Context = 256,
    [ValidateRange(-1, 65536)][int]$PrefillChunk = -1,
    [switch]$PrefillUnionStats,
    [switch]$PrefillWaves,
    [ValidateRange(0, 256)][int]$PrefillWaveForceExperts = 0,
    [switch]$PrefillWaveDoubleBuffer,
    [switch]$GenericSortedMoe,
    [switch]$RequestPhaseTrace,
    [ValidateRange(250, 10000)][int]$TelemetryIntervalMs = 1000,
    [ValidateRange(0.0, 1024.0)][double]$RuntimeMinimumAvailableGiB = 2.0,
    [ValidateRange(0.0, 100000.0)][double]$RuntimeMaximumDiskQueueLength = 8.0,
    [ValidateRange(0.0, 1024.0)][double]$RuntimeHardMinimumAvailableGiB = 0.0,
    [ValidateRange(0.0, 1000000000.0)][double]$RuntimeMaximumPagesOutputPerSecond = 0.0,
    [ValidateRange(0.0, 10.0)][double]$RuntimeMinimumPrivateWorkingSetRatio = 0.0,
    [ValidateRange(0.0, 1024.0)][double]$RuntimePrivateWorkingSetMinimumGiB = 4.0,
    [ValidateRange(1, 60)][int]$RuntimeContaminationSamples = 3,
    [switch]$SkipMemoryPreflight,
    [ValidateRange(0.0, 1024.0)][double]$MinimumAvailableGiB = 0.0,
    [switch]$SkipSystemQuiescencePreflight,
    [switch]$QuiescenceProbeOnly,
    [ValidateRange(3, 60)][int]$QuiescenceSamples = 5,
    [ValidateRange(100, 10000)][int]$QuiescenceIntervalMs = 1000,
    [ValidateRange(0.0, 100.0)][double]$MaximumCpuMedianPercent = 60.0,
    [ValidateRange(0.0, 10000.0)][double]$MaximumDiskMedianPercent = 30.0,
    [ValidateRange(0.0, 1048576.0)][double]$MaximumDiskIoMedianMiBps = 64.0,
    [ValidateRange(0.0, 100.0)][double]$MaximumGpuMedianPercent = 85.0,
    [ValidateRange(0, 600)][int]$QuiescenceCooldownSec = 0
)

$ErrorActionPreference = "Stop"
$effectiveProcessPath = [Environment]::GetEnvironmentVariable(
    "Path", [EnvironmentVariableTarget]::Process)
[Environment]::SetEnvironmentVariable(
    "PATH", $null, [EnvironmentVariableTarget]::Process)
[Environment]::SetEnvironmentVariable(
    "Path", $effectiveProcessPath, [EnvironmentVariableTarget]::Process)
. (Join-Path $PSScriptRoot "g7_process_isolation.ps1")
. (Join-Path $PSScriptRoot "g7_system_counters.ps1")
function Read-G7Q1_0SidecarTelemetry {
    param(
        [AllowEmptyString()][string]$LogText,
        [bool]$SidecarConfigured,
        [bool]$SelectedLoadRequested,
        [bool]$ResidentArenaRequested,
        [bool]$SnapshotBackingRequested,
        [bool]$DualSparseRequested,
        [UInt64]$ExpectedResidentEntries,
        [AllowEmptyString()][string]$SidecarPath
    )

    $summaryMatches = [regex]::Matches(
        $LogText,
        '(?m)^(?:ds4: )?\[q1-0-sidecar\] result=summary calls=(\d+) slots=(\d+) selected_loads=(\d+) failures=(\d+)((?: [A-Za-z0-9_]+=[^ \x0d\x0a]+)*)\x0d?$')
    $runtimeMarkerPattern =
        'Q1_0 (?:routed-expert sidecar validated|expert sidecar source:|routed-expert sidecar installed)|\[q1-0-(?:sidecar|source-unlock)\]'

    if (-not $SidecarConfigured) {
        if ($LogText -match $runtimeMarkerPattern) {
            throw "Q1_0 sidecar runtime telemetry appeared while Q1_0 was disabled"
        }
        return [pscustomobject]@{
            enabled = $false
            selected_load_requested = $false
            runtime_observed = $false
            route_calls = [UInt64]0
            route_slots = [UInt64]0
            selected_loads = [UInt64]0
            failures = [UInt64]0
            resident_arena_requested = $false
            snapshot_backing_requested = $false
            resident_mode = 0
            resident_hits = [UInt64]0
            resident_misses = [UInt64]0
            resident_h2d_bytes = [UInt64]0
            direct_pread_fallbacks = [UInt64]0
            direct_pread_bytes = [UInt64]0
            bootstrap_entries = [UInt64]0
            runtime_contract_valid = $true
            fail_closed_observed = $false
        }
    }

    foreach ($marker in @(
            "Q1_0 routed-expert sidecar validated:",
            "Q1_0 expert sidecar source: $SidecarPath",
            "CUDA Q1_0 routed-expert sidecar installed:")) {
        if ($LogText -notmatch [regex]::Escape($marker)) {
            throw "Q1_0 sidecar runtime marker missing: $marker"
        }
    }
    if ($summaryMatches.Count -ne 1) {
        throw "Q1_0 sidecar requires exactly one runtime summary; observed $($summaryMatches.Count)"
    }

    $summary = $summaryMatches[0]
    $calls = [UInt64]$summary.Groups[1].Value
    $slots = [UInt64]$summary.Groups[2].Value
    $selectedLoads = [UInt64]$summary.Groups[3].Value
    $failures = [UInt64]$summary.Groups[4].Value
    $suffix = [string]$summary.Groups[5].Value
    if ($calls -eq 0 -or $slots -lt $calls) {
        throw "Q1_0 sidecar runtime counters are inconsistent"
    }

    $suffixCounters = @{}
    foreach ($counterMatch in [regex]::Matches(
            $suffix, ' ([A-Za-z0-9_]+)=([^ \x0d\x0a]+)')) {
        $suffixCounters[$counterMatch.Groups[1].Value] =
            $counterMatch.Groups[2].Value
    }
    foreach ($requiredCounter in @(
            "resident_mode", "resident_hits", "resident_misses",
            "resident_h2d_bytes", "direct_pread_fallbacks",
            "direct_pread_bytes")) {
        if (-not $suffixCounters.ContainsKey($requiredCounter)) {
            throw "Q1_0 sidecar summary missing suffix counter: $requiredCounter"
        }
    }
    $bootstrapKey = ""
    foreach ($candidateKey in @("bootstrap_entries", "candidate_entries")) {
        if ($suffixCounters.ContainsKey($candidateKey)) {
            $bootstrapKey = $candidateKey
            break
        }
    }
    if (-not $bootstrapKey) {
        throw "Q1_0 sidecar summary missing suffix counter: bootstrap_entries"
    }
    $residentMode = [int]$suffixCounters["resident_mode"]
    $residentHits = [UInt64]$suffixCounters["resident_hits"]
    $residentMisses = [UInt64]$suffixCounters["resident_misses"]
    $residentH2DBytes = [UInt64]$suffixCounters["resident_h2d_bytes"]
    $directPreadFallbacks = [UInt64]$suffixCounters["direct_pread_fallbacks"]
    $directPreadBytes = [UInt64]$suffixCounters["direct_pread_bytes"]
    $bootstrapEntries = [UInt64]$suffixCounters[$bootstrapKey]

    $failClosedObserved = $false
    if ($SelectedLoadRequested) {
        if ($selectedLoads -ne $calls -or $failures -ne 0) {
            throw "Q1_0 sidecar selected-load counters are inconsistent"
        }
        if ($ResidentArenaRequested) {
            if ($residentMode -ne 1 -or $residentHits -eq 0 -or
                $residentMisses -ne 0 -or $directPreadFallbacks -ne 0 -or
                $directPreadBytes -ne 0 -or
                ($ExpectedResidentEntries -gt 0 -and
                 $bootstrapEntries -ne $ExpectedResidentEntries) -or
                ($ExpectedResidentEntries -eq 0 -and
                 -not $SnapshotBackingRequested -and
                 -not $DualSparseRequested -and
                 $bootstrapEntries -ne 256)) {
                throw "Q1_0 resident arena structural counters are inconsistent"
            }
        } else {
            if ($residentMode -ne 0) {
                throw "Q1_0 direct-file structural counters are inconsistent"
            }
        }
    } else {
        if ($selectedLoads -ne 0 -or $failures -ne $calls) {
            throw "Q1_0 sidecar did not fail closed without selected-load opt-in"
        }
        $failClosedObserved = $true
    }

    [pscustomobject]@{
        enabled = $true
        selected_load_requested = $SelectedLoadRequested
        runtime_observed = $true
        route_calls = $calls
        route_slots = $slots
        selected_loads = $selectedLoads
        failures = $failures
        resident_arena_requested = $ResidentArenaRequested
        snapshot_backing_requested = $SnapshotBackingRequested
        resident_mode = $residentMode
        resident_hits = $residentHits
        resident_misses = $residentMisses
        resident_h2d_bytes = $residentH2DBytes
        direct_pread_fallbacks = $directPreadFallbacks
        direct_pread_bytes = $directPreadBytes
        bootstrap_entries = $bootstrapEntries
        runtime_contract_valid = $true
        fail_closed_observed = $failClosedObserved
    }
}
function Read-G7Q1_0MixedTelemetry {
    param(
        [AllowEmptyString()][string]$LogText,
        [bool]$Required,
        [AllowEmptyString()][string]$ExpectedRouter = ""
    )

    $matches = [regex]::Matches(
        $LogText,
        '(?m)^(?:ds4: )?\[q1-0-mixed\] result=summary calls=(\d+) all_iq2=(\d+) iq2_vram=(\d+) iq2_snapshot_ram=(\d+) iq2_tier_ram=(\d+) q1_resident=(\d+) joins=(\d+) trace_rows=(\d+)(?: tier_route_entries=(\d+))? iq2_ssd_bytes=(\d+) iq2_ssd_violations=(\d+) failures=(\d+)(?: cold_one_calls=(\d+) cold_one_hot_routes=(\d+) cold_one_q1_routes=(\d+) cold_one_invariant_failures=(\d+))? router=([^ \x0d\x0a]+)(?: router_mode=([^ \x0d\x0a]+))? promotion=([^ \x0d\x0a]+)\x0d?$')
    if ($matches.Count -eq 0) {
        if ($Required) {
            throw "Q1_0 mixed resolver summary is required but missing"
        }
        return [pscustomobject]@{
            observed = $false
            calls = [UInt64]0
            all_iq2 = [UInt64]0
            iq2_vram = [UInt64]0
            iq2_snapshot_ram = [UInt64]0
            iq2_tier_ram = [UInt64]0
            q1_resident = [UInt64]0
            joins = [UInt64]0
            trace_rows = [UInt64]0
            tier_route_entries = [UInt64]0
            iq2_ssd_bytes = [UInt64]0
            iq2_ssd_violations = [UInt64]0
            failures = [UInt64]0
            cold_one_calls = [UInt64]0
            cold_one_hot_routes = [UInt64]0
            cold_one_q1_routes = [UInt64]0
            cold_one_invariant_failures = [UInt64]0
            router = "not_observed"
            router_mode = "not_observed"
            promotion = "not_observed"
        }
    }
    if ($matches.Count -ne 1) {
        throw "Q1_0 mixed resolver requires exactly one summary; observed $($matches.Count)"
    }

    $match = $matches[0]
    $telemetry = [pscustomobject]@{
        observed = $true
        calls = [UInt64]$match.Groups[1].Value
        all_iq2 = [UInt64]$match.Groups[2].Value
        iq2_vram = [UInt64]$match.Groups[3].Value
        iq2_snapshot_ram = [UInt64]$match.Groups[4].Value
        iq2_tier_ram = [UInt64]$match.Groups[5].Value
        q1_resident = [UInt64]$match.Groups[6].Value
        joins = [UInt64]$match.Groups[7].Value
        trace_rows = [UInt64]$match.Groups[8].Value
        tier_route_entries = $(if ($match.Groups[9].Success) { [UInt64]$match.Groups[9].Value } else { [UInt64]0 })
        iq2_ssd_bytes = [UInt64]$match.Groups[10].Value
        iq2_ssd_violations = [UInt64]$match.Groups[11].Value
        failures = [UInt64]$match.Groups[12].Value
        cold_one_calls = $(if ($match.Groups[13].Success) { [UInt64]$match.Groups[13].Value } else { [UInt64]0 })
        cold_one_hot_routes = $(if ($match.Groups[14].Success) { [UInt64]$match.Groups[14].Value } else { [UInt64]0 })
        cold_one_q1_routes = $(if ($match.Groups[15].Success) { [UInt64]$match.Groups[15].Value } else { [UInt64]0 })
        cold_one_invariant_failures = $(if ($match.Groups[16].Success) { [UInt64]$match.Groups[16].Value } else { [UInt64]0 })
        router = [string]$match.Groups[17].Value
        router_mode = $(if ($match.Groups[18].Success -and
                            -not [string]::IsNullOrEmpty($match.Groups[18].Value)) {
            [string]$match.Groups[18].Value
        } else {
            [string]$match.Groups[17].Value
        })
        promotion = [string]$match.Groups[19].Value
    }
    if ($Required -and
        ($telemetry.calls -eq 0 -or $telemetry.q1_resident -eq 0 -or
         $telemetry.failures -ne 0 -or $telemetry.iq2_ssd_bytes -ne 0 -or
         $telemetry.iq2_ssd_violations -ne 0 -or
         ($ExpectedRouter -and $telemetry.router_mode -ne $ExpectedRouter) -or
         (-not $ExpectedRouter -and
          ($telemetry.router_mode -ne "unchanged" -and
           $telemetry.router_mode -ne "open")))) {
        throw "Q1_0 mixed resolver counters violate the snapshot contract"
    }
    return $telemetry
}
function Read-G7Q1_0MixedRouteTraceTelemetry {
    param(
        [AllowEmptyString()][string]$LogText,
        [bool]$Required
    )

    $telemetry = [pscustomobject]@{
        observed = $false
        rows = [UInt64]0
        iq2_vram = [UInt64]0
        iq2_snapshot_ram = [UInt64]0
        iq2_tier_ram = [UInt64]0
        q1_resident = [UInt64]0
        iq2_total = [UInt64]0
        accounted_routes = [UInt64]0
        allowed_iq2_representations = @(
            "iq2_vram", "iq2_snapshot_ram", "iq2_tier_ram")
        allowed_q1_representations = @("q1_resident")
    }

    $matches = [regex]::Matches(
        $LogText,
        '(?m)^(?:ds4: )?\[q1-0-mixed-route\] layer=(\d+) route=(\d+) expert=(-?\d+) weight=([^ ]+) representation=([^ ]+) tier=(\d+) has_2bit_ram=(\d+) primary_snapshot=(\d+) q1_snapshot=(\d+)\x0d?$')
    if ($matches.Count -eq 0) {
        if ($Required) {
            throw "Q1_0 mixed route trace is required but missing"
        }
        return $telemetry
    }

    $telemetry.observed = $true
    foreach ($match in $matches) {
        $telemetry.rows++
        switch ([string]$match.Groups[5].Value) {
            "iq2_vram" { $telemetry.iq2_vram++ }
            "iq2_snapshot_ram" { $telemetry.iq2_snapshot_ram++ }
            "iq2_tier_ram" { $telemetry.iq2_tier_ram++ }
            "q1_resident" { $telemetry.q1_resident++ }
            default {
                throw ("Q1_0 mixed route trace used unknown " +
                    "representation: $($match.Groups[5].Value)")
            }
        }
    }
    $telemetry.iq2_total = [UInt64](
        [UInt64]$telemetry.iq2_vram +
        [UInt64]$telemetry.iq2_snapshot_ram +
        [UInt64]$telemetry.iq2_tier_ram)
    $telemetry.accounted_routes = [UInt64](
        [UInt64]$telemetry.iq2_total +
        [UInt64]$telemetry.q1_resident)
    return $telemetry
}
function Convert-G7StrictUInt64 {
    param([Parameter(Mandatory=$true)][string]$Value,
          [Parameter(Mandatory=$true)][string]$Name)

    if ($Value -notmatch '^(0|[1-9][0-9]*)$') {
        throw "Strict UInt64 parse rejected $Name=$Value"
    }
    try {
        return [UInt64]::Parse(
            $Value, [Globalization.CultureInfo]::InvariantCulture)
    } catch {
        throw "Strict UInt64 parse overflow for $Name=$Value"
    }
}
function Convert-G7StrictUInt32 {
    param([Parameter(Mandatory=$true)][string]$Value,
          [Parameter(Mandatory=$true)][string]$Name)

    $parsed = Convert-G7StrictUInt64 $Value $Name
    if ($parsed -gt [UInt64][UInt32]::MaxValue) {
        throw "Strict UInt32 parse overflow for $Name=$Value"
    }
    return [UInt32]$parsed
}
function Convert-G7StrictFlag01 {
    param([Parameter(Mandatory=$true)][string]$Value,
          [Parameter(Mandatory=$true)][string]$Name)

    if ($Value -notmatch '^[01]$') {
        throw "Strict flag parse rejected $Name=$Value"
    }
    return [int]$Value
}
function Convert-G7StrictDouble {
    param([Parameter(Mandatory=$true)][string]$Value,
          [Parameter(Mandatory=$true)][string]$Name)

    if ($Value -notmatch '^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$') {
        throw "Strict double parse rejected $Name=$Value"
    }
    $parsed = [double]::Parse(
        $Value, [Globalization.CultureInfo]::InvariantCulture)
    if ([double]::IsNaN($parsed) -or [double]::IsInfinity($parsed)) {
        throw "Strict double parse rejected non-finite $Name=$Value"
    }
    return $parsed
}
function Convert-G7Q1_0ProfileKeyValues {
    param(
        [Parameter(Mandatory=$true)][string]$Suffix,
        [Parameter(Mandatory=$true)][string[]]$Schema,
        [Parameter(Mandatory=$true)][string]$Kind
    )

    $values = [ordered]@{}
    foreach ($token in @($Suffix -split ' ' | Where-Object { $_ })) {
        $match = [regex]::Match($token, '^([a-z0-9_]+)=([^ ]+)$')
        if (-not $match.Success) {
            throw "Q1_0 profile $Kind contains malformed field: $token"
        }
        $name = [string]$match.Groups[1].Value
        if ($Schema -notcontains $name) {
            throw "Q1_0 profile $Kind contains unknown field: $name"
        }
        if ($values.Contains($name)) {
            throw "Q1_0 profile $Kind contains duplicate field: $name"
        }
        $values[$name] = [string]$match.Groups[2].Value
    }
    foreach ($name in $Schema) {
        if (-not $values.Contains($name)) {
            throw "Q1_0 profile $Kind missing field: $name"
        }
    }
    return $values
}
function Read-G7Q1_0ProfileTelemetry {
    param(
        [AllowEmptyString()][string]$LogText,
        [bool]$Required,
        [bool]$Windows,
        [UInt64]$ExpectedMappingBytes,
        [UInt64]$ExpectedResidentHits,
        [UInt64]$ExpectedResidentH2DBytes,
        [UInt64]$ExpectedMixedJoinCalls
    )

    $profileMatches = [regex]::Matches(
        $LogText,
        '(?m)^(?:ds4: )?\[q1-0-profile\] result=summary ([^\r\n]+)\r?$')
    $workingSetMatches = [regex]::Matches(
        $LogText,
        '(?m)^(?:ds4: )?\[q1-0-source-working-set\] result=([^ ]+) phase=([^ ]+) ([^\r\n]+)\r?$')
    if (-not $Required) {
        if ($profileMatches.Count -ne 0 -or $workingSetMatches.Count -ne 0) {
            throw "Q1_0 profile telemetry appeared while Q1_0Profile was disabled"
        }
        return [pscustomobject]@{
            requested = $false
            observed = $false
            valid = $true
            resident_hits_total = [UInt64]0
            pinned_route_hits = [UInt64]0
            pageable_route_hits = [UInt64]0
            resident_h2d_bytes_total = [UInt64]0
            pinned_h2d_bytes = [UInt64]0
            pageable_h2d_bytes = [UInt64]0
            h2d_enqueue_seconds_total = [double]0
            pinned_h2d_enqueue_seconds = [double]0
            pageable_h2d_enqueue_seconds = [double]0
            upload_sync_calls = [UInt64]0
            upload_sync_seconds_total = [double]0
            pinned_upload_sync_seconds = [double]0
            pageable_upload_sync_seconds = [double]0
            sync_attribution = "not_requested"
            q1_kernel_calls = [UInt64]0
            q1_kernel_seconds = [double]0
            mixed_join_calls = [UInt64]0
            mixed_join_seconds = [double]0
            timer_failures = [UInt64]0
            source_working_set = @()
        }
    }
    if ($profileMatches.Count -ne 1) {
        throw "Q1_0 profile summary required exactly once; observed $($profileMatches.Count)"
    }
    if ($workingSetMatches.Count -ne 3) {
        throw "Q1_0 profile source working-set phases required exactly three times; observed $($workingSetMatches.Count)"
    }
    if ($ExpectedMappingBytes -eq 0) {
        throw "Q1_0 profile requires a nonzero sidecar mapping size"
    }

    $u64Fields = @(
        "resident_hits_total", "pinned_route_hits", "pageable_route_hits",
        "resident_h2d_bytes_total", "pinned_h2d_bytes",
        "pageable_h2d_bytes", "upload_sync_calls", "q1_kernel_calls",
        "mixed_join_calls", "timer_failures")
    $doubleFields = @(
        "h2d_enqueue_seconds_total", "pinned_h2d_enqueue_seconds",
        "pageable_h2d_enqueue_seconds", "upload_sync_seconds_total",
        "pinned_upload_sync_seconds", "pageable_upload_sync_seconds",
        "q1_kernel_seconds", "mixed_join_seconds")
    $profileSchema = @("enabled") + $u64Fields + $doubleFields +
        @("sync_attribution")
    $profileValues = Convert-G7Q1_0ProfileKeyValues `
        -Suffix $profileMatches[0].Groups[1].Value `
        -Schema $profileSchema -Kind "summary"
    if ((Convert-G7StrictFlag01 $profileValues.enabled "q1_profile.enabled") -ne 1 -or
        $profileValues.sync_attribution -ne "bytes") {
        throw "Q1_0 profile summary mode is inconsistent"
    }
    $parsed = [ordered]@{}
    foreach ($name in $u64Fields) {
        $parsed[$name] = Convert-G7StrictUInt64 `
            $profileValues[$name] "q1_profile.$name"
    }
    foreach ($name in $doubleFields) {
        $value = Convert-G7StrictDouble `
            $profileValues[$name] "q1_profile.$name"
        if ($value -lt 0.0) {
            throw "Q1_0 profile summary has negative field: $name"
        }
        $parsed[$name] = [double]$value
    }

    $hitsSum = [decimal]$parsed.pinned_route_hits +
        [decimal]$parsed.pageable_route_hits
    $bytesSum = [decimal]$parsed.pinned_h2d_bytes +
        [decimal]$parsed.pageable_h2d_bytes
    $enqueueSum = [double]$parsed.pinned_h2d_enqueue_seconds +
        [double]$parsed.pageable_h2d_enqueue_seconds
    $syncSum = [double]$parsed.pinned_upload_sync_seconds +
        [double]$parsed.pageable_upload_sync_seconds
    $enqueueTolerance = [math]::Max(
        0.00000001,
        [math]::Abs([double]$parsed.h2d_enqueue_seconds_total) * 0.000001)
    $syncTolerance = [math]::Max(
        0.00000001,
        [math]::Abs([double]$parsed.upload_sync_seconds_total) * 0.000001)
    if ($hitsSum -ne [decimal]$parsed.resident_hits_total -or
        $bytesSum -ne [decimal]$parsed.resident_h2d_bytes_total -or
        [math]::Abs($enqueueSum -
            [double]$parsed.h2d_enqueue_seconds_total) -gt $enqueueTolerance -or
        [math]::Abs($syncSum -
            [double]$parsed.upload_sync_seconds_total) -gt $syncTolerance) {
        throw "Q1_0 profile pinned/pageable accounting is inconsistent"
    }
    if ($parsed.resident_hits_total -ne $ExpectedResidentHits -or
        $parsed.resident_h2d_bytes_total -ne $ExpectedResidentH2DBytes -or
        $parsed.timer_failures -ne 0 -or
        ($parsed.resident_hits_total -gt 0 -and
         ($parsed.upload_sync_calls -eq 0 -or
          $parsed.q1_kernel_calls -eq 0)) -or
        ($ExpectedMixedJoinCalls -gt 0 -and
         $parsed.mixed_join_calls -ne $ExpectedMixedJoinCalls)) {
        throw "Q1_0 profile runtime accounting is inconsistent"
    }

    $workingSetSchema = @(
        "windows", "page_size", "mapping_bytes", "queried_pages",
        "resident_pages", "resident_bytes", "shared_pages", "shared_bytes",
        "not_shared_pages", "not_shared_bytes", "file_backed_pages",
        "file_backed_bytes", "query_calls", "last_error",
        "file_backed_basis")
    $expectedPhases = @("pre-copy", "post-bootstrap", "post-unlock-settle")
    $seenPhases = @{}
    $workingSetRows = @()
    foreach ($match in $workingSetMatches) {
        $result = [string]$match.Groups[1].Value
        $phase = [string]$match.Groups[2].Value
        if ($expectedPhases -notcontains $phase -or
            $seenPhases.ContainsKey($phase)) {
            throw "Q1_0 profile source working-set phase is invalid: $phase"
        }
        $seenPhases[$phase] = $true
        $values = Convert-G7Q1_0ProfileKeyValues `
            -Suffix $match.Groups[3].Value `
            -Schema $workingSetSchema -Kind "source-working-set"
        $row = [ordered]@{ result = $result; phase = $phase }
        foreach ($name in @($workingSetSchema | Where-Object {
                    $_ -ne "file_backed_basis" })) {
            $row[$name] = Convert-G7StrictUInt64 `
                $values[$name] "q1_profile.$phase.$name"
        }
        $row.file_backed_basis = [string]$values.file_backed_basis
        if ($row.mapping_bytes -ne $ExpectedMappingBytes) {
            throw "Q1_0 profile source mapping size is inconsistent"
        }
        if ($Windows) {
            if ($row.page_size -eq 0) {
                throw "Q1_0 profile source working-set page size is invalid"
            }
            $expectedPages = [UInt64]([math]::Ceiling(
                [decimal]$ExpectedMappingBytes / [decimal]$row.page_size))
            if ($result -ne "ok" -or $row.windows -ne 1 -or
                $row.last_error -ne 0 -or
                $row.queried_pages -ne $expectedPages -or
                $row.query_calls -eq 0 -or
                $row.resident_pages -gt $row.queried_pages -or
                ([decimal]$row.shared_pages +
                 [decimal]$row.not_shared_pages) -ne
                    [decimal]$row.resident_pages -or
                $row.file_backed_pages -ne $row.resident_pages -or
                $row.file_backed_basis -ne "sidecar-file-mapping" -or
                [decimal]$row.resident_bytes -ne
                    ([decimal]$row.resident_pages * [decimal]$row.page_size) -or
                [decimal]$row.shared_bytes -ne
                    ([decimal]$row.shared_pages * [decimal]$row.page_size) -or
                [decimal]$row.not_shared_bytes -ne
                    ([decimal]$row.not_shared_pages *
                     [decimal]$row.page_size) -or
                $row.file_backed_bytes -ne $row.resident_bytes) {
                throw "Q1_0 profile source working-set accounting is inconsistent for phase $phase"
            }
        } elseif ($result -ne "unsupported" -or $row.windows -ne 0 -or
                  $row.queried_pages -ne 0 -or $row.query_calls -ne 0 -or
                  $row.file_backed_basis -ne "unavailable") {
            throw "Q1_0 profile non-Windows source working-set contract is inconsistent"
        }
        $workingSetRows += [pscustomobject]$row
    }
    foreach ($phase in $expectedPhases) {
        if (-not $seenPhases.ContainsKey($phase)) {
            throw "Q1_0 profile source working-set phase missing: $phase"
        }
    }

    return [pscustomobject]@{
        requested = $true
        observed = $true
        valid = $true
        resident_hits_total = [UInt64]$parsed.resident_hits_total
        pinned_route_hits = [UInt64]$parsed.pinned_route_hits
        pageable_route_hits = [UInt64]$parsed.pageable_route_hits
        resident_h2d_bytes_total = [UInt64]$parsed.resident_h2d_bytes_total
        pinned_h2d_bytes = [UInt64]$parsed.pinned_h2d_bytes
        pageable_h2d_bytes = [UInt64]$parsed.pageable_h2d_bytes
        h2d_enqueue_seconds_total = [double]$parsed.h2d_enqueue_seconds_total
        pinned_h2d_enqueue_seconds = [double]$parsed.pinned_h2d_enqueue_seconds
        pageable_h2d_enqueue_seconds = [double]$parsed.pageable_h2d_enqueue_seconds
        upload_sync_calls = [UInt64]$parsed.upload_sync_calls
        upload_sync_seconds_total = [double]$parsed.upload_sync_seconds_total
        pinned_upload_sync_seconds = [double]$parsed.pinned_upload_sync_seconds
        pageable_upload_sync_seconds = [double]$parsed.pageable_upload_sync_seconds
        sync_attribution = "bytes"
        q1_kernel_calls = [UInt64]$parsed.q1_kernel_calls
        q1_kernel_seconds = [double]$parsed.q1_kernel_seconds
        mixed_join_calls = [UInt64]$parsed.mixed_join_calls
        mixed_join_seconds = [double]$parsed.mixed_join_seconds
        timer_failures = [UInt64]$parsed.timer_failures
        source_working_set = @($workingSetRows)
    }
}
function Invoke-G7Q1_0ProfileParserSelfTest {
    $off = Read-G7Q1_0ProfileTelemetry `
        -LogText "legacy output without Q1 profile markers" `
        -Required $false -Windows $true -ExpectedMappingBytes 0 `
        -ExpectedResidentHits 0 -ExpectedResidentH2DBytes 0 `
        -ExpectedMixedJoinCalls 0
    if (-not $off.valid -or $off.observed) {
        throw "Q1_0 profile OFF self-test failed"
    }
    $valid = @'
ds4: [q1-0-profile] result=summary enabled=1 resident_hits_total=3 pinned_route_hits=2 pageable_route_hits=1 resident_h2d_bytes_total=300 pinned_h2d_bytes=200 pageable_h2d_bytes=100 upload_sync_calls=2 q1_kernel_calls=2 mixed_join_calls=1 timer_failures=0 h2d_enqueue_seconds_total=0.300000000 pinned_h2d_enqueue_seconds=0.200000000 pageable_h2d_enqueue_seconds=0.100000000 upload_sync_seconds_total=0.600000000 pinned_upload_sync_seconds=0.400000000 pageable_upload_sync_seconds=0.200000000 q1_kernel_seconds=1.000000000 mixed_join_seconds=0.100000000 sync_attribution=bytes
ds4: [q1-0-source-working-set] result=ok phase=pre-copy windows=1 page_size=4096 mapping_bytes=8192 queried_pages=2 resident_pages=1 resident_bytes=4096 shared_pages=1 shared_bytes=4096 not_shared_pages=0 not_shared_bytes=0 file_backed_pages=1 file_backed_bytes=4096 query_calls=1 last_error=0 file_backed_basis=sidecar-file-mapping
ds4: [q1-0-source-working-set] result=ok phase=post-bootstrap windows=1 page_size=4096 mapping_bytes=8192 queried_pages=2 resident_pages=2 resident_bytes=8192 shared_pages=1 shared_bytes=4096 not_shared_pages=1 not_shared_bytes=4096 file_backed_pages=2 file_backed_bytes=8192 query_calls=1 last_error=0 file_backed_basis=sidecar-file-mapping
ds4: [q1-0-source-working-set] result=ok phase=post-unlock-settle windows=1 page_size=4096 mapping_bytes=8192 queried_pages=2 resident_pages=2 resident_bytes=8192 shared_pages=1 shared_bytes=4096 not_shared_pages=1 not_shared_bytes=4096 file_backed_pages=2 file_backed_bytes=8192 query_calls=1 last_error=0 file_backed_basis=sidecar-file-mapping
'@
    $positive = Read-G7Q1_0ProfileTelemetry `
        -LogText $valid -Required $true -Windows $true `
        -ExpectedMappingBytes 8192 -ExpectedResidentHits 3 `
        -ExpectedResidentH2DBytes 300 -ExpectedMixedJoinCalls 1
    if (-not $positive.valid) { throw "Q1_0 profile positive self-test failed" }

    $negativeCases = @()
    try {
        [void](Read-G7Q1_0ProfileTelemetry `
            -LogText $valid.Replace(" pageable_h2d_bytes=100", "") `
            -Required $true -Windows $true -ExpectedMappingBytes 8192 `
            -ExpectedResidentHits 3 -ExpectedResidentH2DBytes 300 `
            -ExpectedMixedJoinCalls 1)
        throw "Q1_0 profile missing-field fixture was accepted"
    } catch {
        if ($_.Exception.Message -notmatch 'missing field: pageable_h2d_bytes') {
            throw
        }
        $negativeCases += "missing field"
    }
    try {
        [void](Read-G7Q1_0ProfileTelemetry `
            -LogText $valid.Replace("resident_h2d_bytes_total=300", `
                                    "resident_h2d_bytes_total=301") `
            -Required $true -Windows $true -ExpectedMappingBytes 8192 `
            -ExpectedResidentHits 3 -ExpectedResidentH2DBytes 301 `
            -ExpectedMixedJoinCalls 1)
        throw "Q1_0 profile incoherent-split fixture was accepted"
    } catch {
        if ($_.Exception.Message -notmatch 'pinned/pageable accounting') {
            throw
        }
        $negativeCases += "incoherent pinned/pageable split"
    }
    [pscustomobject]@{
        status = "pass"
        off_default = "pass"
        positive = "pass"
        negative_cases = @($negativeCases)
    } | ConvertTo-Json -Compress
}

function Read-G7Q1_0SsdWrapTelemetry {
    param(
        [AllowEmptyString()][string]$LogText,
        [bool]$Required,
        [UInt64]$ExpectedHostBudgetBytes,
        [double]$ExpectedPinnedGiB
    )

    $allMarkers = [regex]::Matches(
        $LogText, '(?m)^(?:ds4: )?\[q1-0-ssd-wrap(?:-wave|-working-set)?\] .+$')
    if (-not $Required) {
        if ($allMarkers.Count -ne 0) {
            throw "Q1_0 SSD-WRAP telemetry appeared while disabled"
        }
        return [pscustomobject]@{
            requested = $false; observed = $false; valid = $true
            attempts = [UInt64]0; successes = [UInt64]0
            failures = [UInt64]0; host_budget_bytes = [UInt64]0
            waves = @(); working_set = @()
        }
    }
    $readyMatches = [regex]::Matches(
        $LogText,
        '(?m)^(?:ds4: )?\[q1-0-ssd-wrap\] result=ready ([^\r\n]+)\r?$')
    $finalMatches = [regex]::Matches(
        $LogText,
        '(?m)^(?:ds4: )?\[q1-0-ssd-wrap\] result=([^ ]+) ([^\r\n]+)\r?$')
    $finalMatches = @($finalMatches | Where-Object {
        $_.Groups[1].Value -ne 'ready'
    })
    $waveMatches = [regex]::Matches(
        $LogText,
        '(?m)^(?:ds4: )?\[q1-0-ssd-wrap-wave\] result=([^ ]+) ([^\r\n]+)\r?$')
    $workingSetMatches = [regex]::Matches(
        $LogText,
        '(?m)^(?:ds4: )?\[q1-0-ssd-wrap-working-set\] result=([^ ]+) phase=([^ ]+) ([^\r\n]+)\r?$')
    if ($readyMatches.Count -ne 1 -or $finalMatches.Count -ne 1) {
        throw "Q1_0 SSD-WRAP requires exactly one ready and final record"
    }
    if ($workingSetMatches.Count -lt 3) {
        throw "Q1_0 SSD-WRAP requires working-set samples for lifecycle phases"
    }

    $readySchema = @(
        'enabled', 'queue_capacity', 'prefill_wave_count',
        'prefill_wave_bytes', 'decode_wave_count', 'decode_wave_bytes',
        'max_age_calls', 'pinned_min_touches', 'pinned_min_mass',
        'pinned_min_weight', 'pinned_deadline_calls', 'host_budget_bytes',
        'pinned_resident_slots', 'pageable_resident_slots',
        'ssd_ring_slots', 'h2d_ring_slots', 'slot_bytes', 'ownership')
    $ready = Convert-G7Q1_0ProfileKeyValues `
        -Suffix $readyMatches[0].Groups[1].Value `
        -Schema $readySchema -Kind 'ssd-wrap-ready'
    if ((Convert-G7StrictFlag01 $ready.enabled 'ssd_wrap.enabled') -ne 1 -or
        $ready.ownership -ne 'exclusive-transition-bounded') {
        throw "Q1_0 SSD-WRAP ready mode is invalid"
    }
    $readyU64Names = @($readySchema | Where-Object {
        $_ -notin @('enabled', 'pinned_min_mass', 'pinned_min_weight',
                    'ownership')
    })
    $readyParsed = [ordered]@{}
    foreach ($name in $readyU64Names) {
        $readyParsed[$name] = Convert-G7StrictUInt64 `
            $ready[$name] "ssd_wrap.ready.$name"
    }
    foreach ($name in @('pinned_min_mass', 'pinned_min_weight')) {
        $value = Convert-G7StrictDouble $ready[$name] "ssd_wrap.ready.$name"
        if ($value -lt 0) { throw "Q1_0 SSD-WRAP ready has negative $name" }
        $readyParsed[$name] = $value
    }
    if ($readyParsed.slot_bytes -eq 0 -or
        $readyParsed.ssd_ring_slots -ne 2 -or
        $readyParsed.h2d_ring_slots -ne 2) {
        throw "Q1_0 SSD-WRAP fixed-ring contract is invalid"
    }
    $totalSlots = [decimal]$readyParsed.pinned_resident_slots +
        [decimal]$readyParsed.pageable_resident_slots +
        [decimal]$readyParsed.ssd_ring_slots +
        [decimal]$readyParsed.h2d_ring_slots
    if (($totalSlots * [decimal]$readyParsed.slot_bytes) -ne
            [decimal]$readyParsed.host_budget_bytes -or
        ($ExpectedHostBudgetBytes -ne 0 -and
         $readyParsed.host_budget_bytes -ne $ExpectedHostBudgetBytes)) {
        throw "Q1_0 SSD-WRAP host budget accounting is inconsistent"
    }
    $pinnedAllocationBytes =
        ([decimal]$readyParsed.pinned_resident_slots +
         [decimal]$readyParsed.ssd_ring_slots +
         [decimal]$readyParsed.h2d_ring_slots) *
        [decimal]$readyParsed.slot_bytes
    $requestedPinnedBytes = [decimal]$ExpectedPinnedGiB * [decimal]1GB
    if ($requestedPinnedBytes -gt [decimal]$readyParsed.host_budget_bytes) {
        $requestedPinnedBytes = [decimal]$readyParsed.host_budget_bytes
    }
    if ($pinnedAllocationBytes -gt $requestedPinnedBytes -or
        $requestedPinnedBytes - $pinnedAllocationBytes -ge
            [decimal]$readyParsed.slot_bytes) {
        throw "Q1_0 SSD-WRAP pinned/pageable split is inconsistent"
    }

    $finalResult = [string]$finalMatches[0].Groups[1].Value
    $finalU64 = @(
        'requested', 'deduplicated', 'backpressure', 'attempts',
        'successes', 'failures', 'structural_rejects', 'bytes_requested',
        'bytes_read', 'bytes_useful', 'ranges_requested', 'ranges_read',
        'coalesced_ranges', 'max_queue_depth', 'waves_prefill',
        'waves_decode', 'ram_ready', 'pinned_ready', 'pageable_ready',
        'pinned_hits', 'pageable_hits', 'stale', 'dropped',
        'host_copy_bytes', 'h2d_waits',
        'pageable_paged_out_before_copy', 'first_use', 'wasted')
    $finalDouble = @(
        'host_copy_seconds', 'h2d_wait_seconds', 'service_seconds')
    $finalValues = Convert-G7Q1_0ProfileKeyValues `
        -Suffix $finalMatches[0].Groups[2].Value `
        -Schema @($finalU64 + $finalDouble) -Kind 'ssd-wrap-final'
    $final = [ordered]@{}
    foreach ($name in $finalU64) {
        $final[$name] = Convert-G7StrictUInt64 `
            $finalValues[$name] "ssd_wrap.final.$name"
    }
    foreach ($name in $finalDouble) {
        $value = Convert-G7StrictDouble `
            $finalValues[$name] "ssd_wrap.final.$name"
        if ($value -lt 0) { throw "Q1_0 SSD-WRAP final has negative $name" }
        $final[$name] = $value
    }
    if ($finalResult -ne 'complete' -or $final.failures -ne 0 -or
        $final.structural_rejects -gt 16 -or $final.stale -ne 0 -or
        $final.dropped -ne 0 -or $final.requested -ne $final.attempts -or
        [decimal]$final.attempts -ne
            ([decimal]$final.successes + [decimal]$final.failures) -or
        [decimal]$final.pinned_ready + [decimal]$final.pageable_ready -ne
            [decimal]$final.successes -or
        $final.bytes_read -ne $final.bytes_useful -or
        $final.bytes_read -gt $final.bytes_requested -or
        [decimal]$final.ranges_requested -ne
            ([decimal]$final.attempts * 3) -or
        [decimal]$final.ranges_read + [decimal]$final.coalesced_ranges -ne
            ([decimal]$final.successes * 3)) {
        throw "Q1_0 SSD-WRAP final accounting is inconsistent"
    }

    $waveSchema = @(
        'wave_id', 'regime', 'requests', 'ranges_requested', 'ranges_read',
        'coalesced_ranges', 'bytes_requested', 'bytes_read', 'bytes_useful',
        'queue_depth', 'service_seconds', 'ram_ready', 'failures',
        'coalesce_ratio')
    $waves = @()
    [decimal]$waveRequests = 0
    [decimal]$waveBytesRequested = 0
    foreach ($match in $waveMatches) {
        $values = Convert-G7Q1_0ProfileKeyValues `
            -Suffix $match.Groups[2].Value -Schema $waveSchema `
            -Kind 'ssd-wrap-wave'
        if ($match.Groups[1].Value -ne 'ready' -or
            $values.regime -notin @('prefill-rebuild', 'decode-micro')) {
            throw "Q1_0 SSD-WRAP wave result/regime is invalid"
        }
        $row = [ordered]@{ result = 'ready'; regime = $values.regime }
        foreach ($name in @($waveSchema | Where-Object {
                    $_ -notin @('regime', 'service_seconds', 'coalesce_ratio')
                })) {
            $row[$name] = Convert-G7StrictUInt64 `
                $values[$name] "ssd_wrap.wave.$name"
        }
        foreach ($name in @('service_seconds', 'coalesce_ratio')) {
            $row[$name] = Convert-G7StrictDouble `
                $values[$name] "ssd_wrap.wave.$name"
            if ($row[$name] -lt 0) {
                throw "Q1_0 SSD-WRAP wave has negative $name"
            }
        }
        if ($row.failures -ne 0 -or $row.bytes_read -ne $row.bytes_useful -or
            $row.bytes_read -gt $row.bytes_requested -or
            [decimal]$row.ranges_read + [decimal]$row.coalesced_ranges -ne
                [decimal]$row.ranges_requested) {
            throw "Q1_0 SSD-WRAP wave accounting is inconsistent"
        }
        $waveRequests += [decimal]$row.requests
        $waveBytesRequested += [decimal]$row.bytes_requested
        $waves += [pscustomobject]$row
    }
    if (($final.attempts -gt 0 -and $waves.Count -eq 0) -or
        $waveRequests -ne [decimal]$final.attempts -or
        $waveBytesRequested -ne [decimal]$final.bytes_requested) {
        throw "Q1_0 SSD-WRAP wave totals are inconsistent"
    }

    $workingSetSchema = @(
        'page_size', 'pages', 'queried_pages', 'resident_pages',
        'resident_bytes', 'paged_out_pages', 'paged_out_bytes',
        'shared_pages', 'shared_bytes', 'locked_pages', 'locked_bytes',
        'page_fault_count', 'hard_fault_source')
    $workingSet = @()
    $phases = @{}
    foreach ($match in $workingSetMatches) {
        if ($match.Groups[1].Value -ne 'sample') {
            throw "Q1_0 SSD-WRAP working-set sample failed"
        }
        $values = Convert-G7Q1_0ProfileKeyValues `
            -Suffix $match.Groups[3].Value -Schema $workingSetSchema `
            -Kind 'ssd-wrap-working-set'
        $row = [ordered]@{ phase = [string]$match.Groups[2].Value }
        foreach ($name in @($workingSetSchema | Where-Object {
                    $_ -ne 'hard_fault_source' })) {
            $row[$name] = Convert-G7StrictUInt64 `
                $values[$name] "ssd_wrap.working_set.$name"
        }
        $row.hard_fault_source = [string]$values.hard_fault_source
        if ($row.page_size -eq 0 -or $row.queried_pages -ne $row.pages -or
            [decimal]$row.resident_pages + [decimal]$row.paged_out_pages -ne
                [decimal]$row.pages -or
            [decimal]$row.resident_bytes -ne
                ([decimal]$row.resident_pages * [decimal]$row.page_size) -or
            [decimal]$row.paged_out_bytes -ne
                ([decimal]$row.paged_out_pages * [decimal]$row.page_size) -or
            $row.hard_fault_source -ne 'external-sampler') {
            throw "Q1_0 SSD-WRAP working-set accounting is inconsistent"
        }
        $phases[$row.phase] = $true
        $workingSet += [pscustomobject]$row
    }
    foreach ($phase in @('init', 'flush', 'release')) {
        if (-not $phases.ContainsKey($phase)) {
            throw "Q1_0 SSD-WRAP working-set phase missing: $phase"
        }
    }
    return [pscustomobject]@{
        requested = $true; observed = $true; valid = $true
        attempts = [UInt64]$final.attempts
        successes = [UInt64]$final.successes
        failures = [UInt64]$final.failures
        host_budget_bytes = [UInt64]$readyParsed.host_budget_bytes
        pinned_resident_slots = [UInt64]$readyParsed.pinned_resident_slots
        pageable_resident_slots = [UInt64]$readyParsed.pageable_resident_slots
        slot_bytes = [UInt64]$readyParsed.slot_bytes
        final = [pscustomobject]$final
        waves = @($waves)
        working_set = @($workingSet)
    }
}

function Invoke-G7Q1_0SsdWrapParserSelfTest {
    $off = Read-G7Q1_0SsdWrapTelemetry -LogText 'legacy' `
        -Required $false -ExpectedHostBudgetBytes 0 -ExpectedPinnedGiB 1.5
    if (-not $off.valid -or $off.observed) {
        throw 'Q1_0 SSD-WRAP OFF self-test failed'
    }
    $valid = @'
ds4: [q1-0-ssd-wrap] result=ready enabled=1 queue_capacity=2 prefill_wave_count=2 prefill_wave_bytes=1000 decode_wave_count=1 decode_wave_bytes=1000 max_age_calls=40 pinned_min_touches=3 pinned_min_mass=0.05 pinned_min_weight=0.02 pinned_deadline_calls=1 host_budget_bytes=1000 pinned_resident_slots=6 pageable_resident_slots=0 ssd_ring_slots=2 h2d_ring_slots=2 slot_bytes=100 ownership=exclusive-transition-bounded
ds4: [q1-0-ssd-wrap-wave] result=ready wave_id=1 regime=decode-micro requests=1 ranges_requested=3 ranges_read=3 coalesced_ranges=0 bytes_requested=100 bytes_read=100 bytes_useful=100 queue_depth=1 service_seconds=0.1 ram_ready=1 failures=0 coalesce_ratio=1
ds4: [q1-0-ssd-wrap-working-set] result=sample phase=init page_size=4096 pages=0 queried_pages=0 resident_pages=0 resident_bytes=0 paged_out_pages=0 paged_out_bytes=0 shared_pages=0 shared_bytes=0 locked_pages=0 locked_bytes=0 page_fault_count=1 hard_fault_source=external-sampler
ds4: [q1-0-ssd-wrap-working-set] result=sample phase=flush page_size=4096 pages=0 queried_pages=0 resident_pages=0 resident_bytes=0 paged_out_pages=0 paged_out_bytes=0 shared_pages=0 shared_bytes=0 locked_pages=0 locked_bytes=0 page_fault_count=1 hard_fault_source=external-sampler
ds4: [q1-0-ssd-wrap-working-set] result=sample phase=release page_size=4096 pages=0 queried_pages=0 resident_pages=0 resident_bytes=0 paged_out_pages=0 paged_out_bytes=0 shared_pages=0 shared_bytes=0 locked_pages=0 locked_bytes=0 page_fault_count=1 hard_fault_source=external-sampler
ds4: [q1-0-ssd-wrap] result=complete requested=1 deduplicated=0 backpressure=0 attempts=1 successes=1 failures=0 structural_rejects=0 bytes_requested=100 bytes_read=100 bytes_useful=100 ranges_requested=3 ranges_read=3 coalesced_ranges=0 max_queue_depth=1 waves_prefill=0 waves_decode=1 ram_ready=1 pinned_ready=1 pageable_ready=0 pinned_hits=1 pageable_hits=0 stale=0 dropped=0 host_copy_bytes=0 host_copy_seconds=0 h2d_waits=0 h2d_wait_seconds=0 pageable_paged_out_before_copy=0 first_use=1 wasted=0 service_seconds=0.1
'@
    $positive = Read-G7Q1_0SsdWrapTelemetry -LogText $valid `
        -Required $true -ExpectedHostBudgetBytes 1000 -ExpectedPinnedGiB 0.125
    if (-not $positive.valid -or $positive.attempts -ne 1) {
        throw 'Q1_0 SSD-WRAP positive self-test failed'
    }
    $negative = @()
    try {
        [void](Read-G7Q1_0SsdWrapTelemetry `
            -LogText $valid.Replace(' pageable_ready=0', '') `
            -Required $true -ExpectedHostBudgetBytes 1000 `
            -ExpectedPinnedGiB 0.125)
        throw 'Q1_0 SSD-WRAP missing-field fixture was accepted'
    } catch {
        if ($_.Exception.Message -notmatch 'missing field: pageable_ready') { throw }
        $negative += 'missing-field'
    }
    try {
        [void](Read-G7Q1_0SsdWrapTelemetry `
            -LogText $valid.Replace('pinned_resident_slots=6', `
                                    'pinned_resident_slots=5') `
            -Required $true -ExpectedHostBudgetBytes 1000 `
            -ExpectedPinnedGiB 0.125)
        throw 'Q1_0 SSD-WRAP split fixture was accepted'
    } catch {
        if ($_.Exception.Message -notmatch 'host budget accounting') { throw }
        $negative += 'incoherent-split'
    }
    [pscustomobject]@{
        status = 'pass'; off_default = 'pass'; positive = 'pass'
        negative_cases = $negative
    } | ConvertTo-Json -Compress
}

function Assert-G7ExpertRecoveryExactProperties {
    param(
        [Parameter(Mandatory=$true)][object]$Object,
        [Parameter(Mandatory=$true)][string[]]$Names,
        [Parameter(Mandatory=$true)][string]$Kind
    )
    if ($null -eq $Object -or $Object -is [array]) {
        throw "Expert recovery $Kind must be exactly one JSON object"
    }
    $observed = @($Object.PSObject.Properties | ForEach-Object { $_.Name })
    if ($observed.Count -ne $Names.Count -or
        (Compare-Object $Names $observed).Count -ne 0) {
        throw "Expert recovery $Kind schema has missing or extra fields"
    }
}

function Get-G7ExpertRecoveryConfinedPaths {
    param(
        [Parameter(Mandatory=$true)][string]$RootPath,
        [Parameter(Mandatory=$true)][string]$OutputPrefix
    )
    $root = [IO.Path]::GetFullPath($RootPath).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar)
    $prefix = [IO.Path]::GetFullPath($OutputPrefix)
    $parent = [IO.Path]::GetDirectoryName($prefix).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar)
    $leaf = [IO.Path]::GetFileName($prefix)
    if (-not [string]::Equals(
            $parent, $root, [StringComparison]::OrdinalIgnoreCase) -or
        $leaf -notmatch '^[A-Za-z0-9_.-]+$') {
        throw "Expert recovery output path is outside the canonical root"
    }
    $rootInfo = Get-Item -LiteralPath $root -ErrorAction Stop
    if (-not $rootInfo.PSIsContainer -or
        ($rootInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Expert recovery output root must be a non-reparse directory"
    }
    [pscustomobject]@{
        root = $root
        prefix = $prefix
        leaf = $leaf
        binary = $prefix + ".vectors.f32le"
        jsonl = $prefix + ".samples.jsonl"
        manifest = $prefix + ".manifest.json"
        binary_partial = $prefix + ".vectors.f32le.partial"
        jsonl_partial = $prefix + ".samples.jsonl.partial"
        manifest_partial = $prefix + ".manifest.json.partial"
    }
}

function ConvertTo-G7ExpertRecoveryCanonicalSample {
    param([Parameter(Mandatory=$true)][object]$Record)
    [pscustomobject][ordered]@{
        schema = [string]$Record.schema
        sample_index = [UInt64]$Record.sample_index
        request_epoch = [UInt64]$Record.request_epoch
        call_tick = [UInt64]$Record.call_tick
        token_index = [UInt64]$Record.token_index
        layer = [UInt64]$Record.layer
        expert = [UInt64]$Record.expert
        topk_rank = [UInt64]$Record.topk_rank
        gate_weight_decimal = [string]$Record.gate_weight_decimal
        gate_weight_f32_le_hex = [string]$Record.gate_weight_f32_le_hex
        representation = [string]$Record.representation
        dtype = [string]$Record.dtype
        shape = @([UInt64]$Record.shape[0])
        vector_offset = [UInt64]$Record.vector_offset
        vector_bytes = [UInt64]$Record.vector_bytes
        model_sha256 = [string]$Record.model_sha256
        model_bytes = [UInt64]$Record.model_bytes
        sidecar_sha256 = [string]$Record.sidecar_sha256
        sidecar_bytes = [UInt64]$Record.sidecar_bytes
        build_manifest_sha256 = [string]$Record.build_manifest_sha256
        build_input_fingerprint_sha256 =
            [string]$Record.build_input_fingerprint_sha256
        executable_sha256 = [string]$Record.executable_sha256
    } | ConvertTo-Json -Compress -Depth 5
}

function ConvertTo-G7ExpertRecoveryCanonicalManifest {
    param([Parameter(Mandatory=$true)][object]$Manifest)
    [pscustomobject][ordered]@{
        schema = [string]$Manifest.schema
        status = [string]$Manifest.status
        input_only = [bool]$Manifest.input_only
        teacher_output_captured = [bool]$Manifest.teacher_output_captured
        teacher_output_reconstruction =
            [string]$Manifest.teacher_output_reconstruction
        dtype = [string]$Manifest.dtype
        shape = @([UInt64]$Manifest.shape[0], [UInt64]$Manifest.shape[1])
        header_bytes = [UInt64]$Manifest.header_bytes
        sample_count = [UInt64]$Manifest.sample_count
        max_samples = [UInt64]$Manifest.max_samples
        capped_samples = [UInt64]$Manifest.capped_samples
        vector_dim = [UInt64]$Manifest.vector_dim
        vector_bytes_per_sample = [UInt64]$Manifest.vector_bytes_per_sample
        binary_bytes = [UInt64]$Manifest.binary_bytes
        byte_budget = [UInt64]$Manifest.byte_budget
        layer = [UInt64]$Manifest.layer
        expert = [UInt64]$Manifest.expert
        request_epoch_min = [UInt64]$Manifest.request_epoch_min
        request_epoch_max = [UInt64]$Manifest.request_epoch_max
        call_tick_min = [UInt64]$Manifest.call_tick_min
        call_tick_max = [UInt64]$Manifest.call_tick_max
        binary_file = [string]$Manifest.binary_file
        binary_sha256 = [string]$Manifest.binary_sha256
        jsonl_file = [string]$Manifest.jsonl_file
        jsonl_bytes = [UInt64]$Manifest.jsonl_bytes
        jsonl_sha256 = [string]$Manifest.jsonl_sha256
        model_sha256 = [string]$Manifest.model_sha256
        model_bytes = [UInt64]$Manifest.model_bytes
        sidecar_sha256 = [string]$Manifest.sidecar_sha256
        sidecar_bytes = [UInt64]$Manifest.sidecar_bytes
        build_manifest_sha256 = [string]$Manifest.build_manifest_sha256
        build_input_fingerprint_sha256 =
            [string]$Manifest.build_input_fingerprint_sha256
        executable_sha256 = [string]$Manifest.executable_sha256
    } | ConvertTo-Json -Compress -Depth 5
}

function Read-G7ExpertRecoveryTraceArtifact {
    param(
        [Parameter(Mandatory=$true)][bool]$Required,
        [Parameter(Mandatory=$true)][string]$RootPath,
        [Parameter(Mandatory=$true)][string]$OutputPrefix,
        [Parameter(Mandatory=$true)][UInt64]$ExpectedLayer,
        [Parameter(Mandatory=$true)][UInt64]$ExpectedExpert,
        [Parameter(Mandatory=$true)][UInt64]$ExpectedMaxSamples,
        [Parameter(Mandatory=$true)][UInt64]$ExpectedByteBudget,
        [Parameter(Mandatory=$true)][string]$ExpectedModelSHA256,
        [Parameter(Mandatory=$true)][UInt64]$ExpectedModelBytes,
        [Parameter(Mandatory=$true)][string]$ExpectedSidecarSHA256,
        [Parameter(Mandatory=$true)][UInt64]$ExpectedSidecarBytes,
        [Parameter(Mandatory=$true)][string]$ExpectedBuildManifestSHA256,
        [Parameter(Mandatory=$true)][string]$ExpectedBuildFingerprintSHA256,
        [Parameter(Mandatory=$true)][string]$ExpectedExecutableSHA256
    )
    $paths = Get-G7ExpertRecoveryConfinedPaths `
        -RootPath $RootPath -OutputPrefix $OutputPrefix
    $allPaths = @($paths.binary, $paths.jsonl, $paths.manifest,
                  $paths.binary_partial, $paths.jsonl_partial,
                  $paths.manifest_partial)
    if (-not $Required) {
        if (@($allPaths | Where-Object { Test-Path -LiteralPath $_ }).Count -ne 0) {
            throw "Expert recovery artifacts appeared while tracing was disabled"
        }
        return [pscustomobject]@{ requested = $false; observed = $false; valid = $true }
    }
    if ((Test-Path -LiteralPath $paths.binary_partial) -or
        (Test-Path -LiteralPath $paths.jsonl_partial) -or
        (Test-Path -LiteralPath $paths.manifest_partial)) {
        throw "Expert recovery partial artifact is not acceptable"
    }
    foreach ($requiredPath in @($paths.binary, $paths.jsonl, $paths.manifest)) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
            throw "Expert recovery committed artifact is missing: $requiredPath"
        }
        if (((Get-Item -LiteralPath $requiredPath).Attributes -band
             [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Expert recovery committed artifact cannot be a reparse point"
        }
    }
    $utf8NoBom = [Text.UTF8Encoding]::new($false, $true)
    $manifestRaw = [IO.File]::ReadAllText($paths.manifest, $utf8NoBom)
    $manifestHasBom = ($manifestRaw.Length -gt 0 -and
        [int]$manifestRaw[0] -eq 0xfeff)
    if (-not $manifestRaw.EndsWith("`n") -or $manifestRaw.Contains("`r") -or
        $manifestHasBom) {
        throw ("Expert recovery manifest is not canonical UTF-8 LF JSON " +
            "(ends_lf={0}, has_cr={1}, starts_bom={2}, chars={3})" -f
            $manifestRaw.EndsWith("`n"), $manifestRaw.Contains("`r"),
            $manifestHasBom, $manifestRaw.Length)
    }
    try { $manifest = $manifestRaw | ConvertFrom-Json }
    catch { throw "Expert recovery manifest is invalid JSON" }
    $manifestFields = @(
        "schema", "status", "input_only", "teacher_output_captured",
        "teacher_output_reconstruction", "dtype", "shape", "header_bytes",
        "sample_count", "max_samples", "capped_samples", "vector_dim",
        "vector_bytes_per_sample", "binary_bytes", "byte_budget", "layer",
        "expert", "request_epoch_min", "request_epoch_max", "call_tick_min",
        "call_tick_max", "binary_file", "binary_sha256", "jsonl_file",
        "jsonl_bytes", "jsonl_sha256", "model_sha256", "model_bytes",
        "sidecar_sha256", "sidecar_bytes", "build_manifest_sha256",
        "build_input_fingerprint_sha256", "executable_sha256")
    Assert-G7ExpertRecoveryExactProperties `
        -Object $manifest -Names $manifestFields -Kind "manifest"
    $canonicalManifest = ConvertTo-G7ExpertRecoveryCanonicalManifest $manifest
    if ($manifestRaw -cne ($canonicalManifest + "`n")) {
        throw "Expert recovery manifest failed canonical roundtrip"
    }
    $sampleCount = [UInt64]$manifest.sample_count
    $vectorDim = [UInt64]$manifest.vector_dim
    $vectorBytes = [UInt64]$manifest.vector_bytes_per_sample
    $binaryBytes = [UInt64]$manifest.binary_bytes
    if ($manifest.schema -ne "ds4_expert_recovery_manifest_v1" -or
        $manifest.status -ne "complete" -or
        -not [bool]$manifest.input_only -or
        [bool]$manifest.teacher_output_captured -or
        $manifest.teacher_output_reconstruction -ne
            "offline_exact_iq2_from_captured_input" -or
        $manifest.dtype -ne "float32-le" -or
        @($manifest.shape).Count -ne 2 -or
        [UInt64]$manifest.shape[0] -ne $sampleCount -or
        [UInt64]$manifest.shape[1] -ne $vectorDim -or
        [UInt64]$manifest.header_bytes -ne 64 -or
        $sampleCount -eq 0 -or $sampleCount -gt $ExpectedMaxSamples -or
        [UInt64]$manifest.max_samples -ne $ExpectedMaxSamples -or
        $ExpectedMaxSamples -gt 256 -or $vectorDim -eq 0 -or
        $vectorDim -gt ([UInt64]::MaxValue / 4) -or
        $vectorBytes -ne $vectorDim * 4 -or
        $binaryBytes -ne 64 + $sampleCount * $vectorBytes -or
        [UInt64]$manifest.byte_budget -ne $ExpectedByteBudget -or
        $binaryBytes -gt $ExpectedByteBudget -or
        [UInt64]$manifest.layer -ne $ExpectedLayer -or
        [UInt64]$manifest.expert -ne $ExpectedExpert -or
        [UInt64]$manifest.request_epoch_min -eq 0 -or
        [UInt64]$manifest.request_epoch_min -gt
            [UInt64]$manifest.request_epoch_max -or
        [UInt64]$manifest.call_tick_min -eq 0 -or
        [UInt64]$manifest.call_tick_min -gt [UInt64]$manifest.call_tick_max) {
        throw "Expert recovery manifest contract is inconsistent"
    }
    $expectedBinaryFile = $paths.leaf + ".vectors.f32le"
    $expectedJsonlFile = $paths.leaf + ".samples.jsonl"
    if ($manifest.binary_file -cne $expectedBinaryFile -or
        $manifest.jsonl_file -cne $expectedJsonlFile -or
        [IO.Path]::GetFullPath((Join-Path $paths.root $manifest.binary_file)) -ine
            [IO.Path]::GetFullPath($paths.binary) -or
        [IO.Path]::GetFullPath((Join-Path $paths.root $manifest.jsonl_file)) -ine
            [IO.Path]::GetFullPath($paths.jsonl)) {
        throw "Expert recovery manifest artifact paths are not confined"
    }
    foreach ($shaProperty in @("binary_sha256", "jsonl_sha256",
            "model_sha256", "sidecar_sha256", "build_manifest_sha256",
            "build_input_fingerprint_sha256", "executable_sha256")) {
        if ([string]$manifest.$shaProperty -cnotmatch '^[0-9a-f]{64}$') {
            throw "Expert recovery manifest has invalid SHA-256: $shaProperty"
        }
    }
    $binaryInfo = Get-Item -LiteralPath $paths.binary
    $jsonlInfo = Get-Item -LiteralPath $paths.jsonl
    $manifestInfo = Get-Item -LiteralPath $paths.manifest
    $binarySHA = (Get-FileHash -LiteralPath $paths.binary -Algorithm SHA256).
        Hash.ToLowerInvariant()
    $jsonlSHA = (Get-FileHash -LiteralPath $paths.jsonl -Algorithm SHA256).
        Hash.ToLowerInvariant()
    if ([UInt64]$binaryInfo.Length -ne $binaryBytes -or
        [UInt64]$jsonlInfo.Length -ne [UInt64]$manifest.jsonl_bytes -or
        [UInt64]$binaryInfo.Length -gt $ExpectedByteBudget -or
        [UInt64]$jsonlInfo.Length -gt
            $ExpectedByteBudget - [UInt64]$binaryInfo.Length -or
        [UInt64]$manifestInfo.Length -gt $ExpectedByteBudget -
            [UInt64]$binaryInfo.Length - [UInt64]$jsonlInfo.Length -or
        $binarySHA -cne [string]$manifest.binary_sha256 -or
        $jsonlSHA -cne [string]$manifest.jsonl_sha256 -or
        [string]$manifest.model_sha256 -ine $ExpectedModelSHA256 -or
        [UInt64]$manifest.model_bytes -ne $ExpectedModelBytes -or
        [string]$manifest.sidecar_sha256 -ine $ExpectedSidecarSHA256 -or
        [UInt64]$manifest.sidecar_bytes -ne $ExpectedSidecarBytes -or
        [string]$manifest.build_manifest_sha256 -ine
            $ExpectedBuildManifestSHA256 -or
        [string]$manifest.build_input_fingerprint_sha256 -ine
            $ExpectedBuildFingerprintSHA256 -or
        [string]$manifest.executable_sha256 -ine $ExpectedExecutableSHA256) {
        throw "Expert recovery artifact SHA, size, or provenance mismatch"
    }
    $binary = [IO.File]::ReadAllBytes($paths.binary)
    if ([Text.Encoding]::ASCII.GetString($binary, 0, 8) -cne "DS4ERTR1" -or
        [BitConverter]::ToUInt32($binary, 8) -ne 1 -or
        [BitConverter]::ToUInt32($binary, 12) -ne 64 -or
        [BitConverter]::ToUInt32($binary, 16) -ne 1 -or
        [BitConverter]::ToUInt32($binary, 20) -ne $vectorDim -or
        [BitConverter]::ToUInt32($binary, 24) -ne $ExpectedMaxSamples -or
        [BitConverter]::ToUInt32($binary, 28) -ne $sampleCount -or
        [BitConverter]::ToUInt64($binary, 32) -ne $vectorBytes -or
        [BitConverter]::ToUInt64($binary, 40) -ne $sampleCount * $vectorBytes -or
        [BitConverter]::ToUInt64($binary, 48) -ne $ExpectedByteBudget -or
        @($binary[56..63] | Where-Object { $_ -ne 0 }).Count -ne 0) {
        throw "Expert recovery binary header is inconsistent"
    }
    $jsonlRaw = [IO.File]::ReadAllText($paths.jsonl, $utf8NoBom)
    $jsonlHasBom = ($jsonlRaw.Length -gt 0 -and [int]$jsonlRaw[0] -eq 0xfeff)
    if (-not $jsonlRaw.EndsWith("`n") -or $jsonlRaw.Contains("`r") -or
        $jsonlHasBom) {
        throw "Expert recovery JSONL is not canonical UTF-8 LF"
    }
    $physicalLines = @($jsonlRaw.Substring(0, $jsonlRaw.Length - 1).Split("`n"))
    if ($physicalLines.Count -ne $sampleCount -or
        @($physicalLines | Where-Object { -not $_ }).Count -ne 0) {
        throw "Expert recovery JSONL physical-line count is inconsistent"
    }
    $sampleFields = @(
        "schema", "sample_index", "request_epoch", "call_tick", "token_index",
        "layer", "expert", "topk_rank", "gate_weight_decimal",
        "gate_weight_f32_le_hex", "representation", "dtype", "shape",
        "vector_offset", "vector_bytes", "model_sha256", "model_bytes",
        "sidecar_sha256", "sidecar_bytes", "build_manifest_sha256",
        "build_input_fingerprint_sha256", "executable_sha256")
    $records = @()
    $lastTokenByRequest = @{}
    $lastCallByRequest = @{}
    $requestMin = [UInt64]::MaxValue
    $requestMax = [UInt64]0
    $callMin = [UInt64]::MaxValue
    $callMax = [UInt64]0
    for ($i = 0; $i -lt $physicalLines.Count; $i++) {
        $line = $physicalLines[$i]
        try { $record = $line | ConvertFrom-Json }
        catch { throw "Expert recovery JSONL line $i is invalid JSON" }
        Assert-G7ExpertRecoveryExactProperties `
            -Object $record -Names $sampleFields -Kind "sample"
        if ($line -cne (ConvertTo-G7ExpertRecoveryCanonicalSample $record)) {
            throw "Expert recovery JSONL line $i failed canonical roundtrip"
        }
        $requestEpoch = [UInt64]$record.request_epoch
        $callTick = [UInt64]$record.call_tick
        $tokenIndex = [UInt64]$record.token_index
        $weightText = [string]$record.gate_weight_decimal
        if ($weightText -cnotmatch '^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:e[+-]?[0-9]+)?$') {
            throw "Expert recovery sample gate weight is not canonical"
        }
        try {
            $weight = [Single]::Parse(
                $weightText, [Globalization.NumberStyles]::Float,
                [Globalization.CultureInfo]::InvariantCulture)
        } catch { throw "Expert recovery sample gate weight is invalid" }
        $weightBits = [BitConverter]::ToUInt32(
            [BitConverter]::GetBytes($weight), 0).ToString("x8")
        $requestKey = [string]$requestEpoch
        if ($record.schema -ne "ds4_expert_recovery_sample_v1" -or
            [UInt64]$record.sample_index -ne [UInt64]$i -or
            $requestEpoch -eq 0 -or $requestEpoch -eq [UInt64]::MaxValue -or
            $callTick -eq 0 -or
            $callTick -eq [UInt64]::MaxValue -or
            [UInt64]$record.layer -ne $ExpectedLayer -or
            [UInt64]$record.expert -ne $ExpectedExpert -or
            [UInt64]$record.topk_rank -gt 5 -or
            [string]$record.gate_weight_f32_le_hex -cne $weightBits -or
            [string]$record.representation -notin @(
                "iq2_vram", "iq2_snapshot_ram", "iq2_tier_ram", "q1_resident") -or
            $record.dtype -ne "float32-le" -or
            @($record.shape).Count -ne 1 -or
            [UInt64]$record.shape[0] -ne $vectorDim -or
            [UInt64]$record.vector_offset -ne 64 + [UInt64]$i * $vectorBytes -or
            [UInt64]$record.vector_bytes -ne $vectorBytes -or
            [string]$record.model_sha256 -ine $ExpectedModelSHA256 -or
            [UInt64]$record.model_bytes -ne $ExpectedModelBytes -or
            [string]$record.sidecar_sha256 -ine $ExpectedSidecarSHA256 -or
            [UInt64]$record.sidecar_bytes -ne $ExpectedSidecarBytes -or
            [string]$record.build_manifest_sha256 -ine
                $ExpectedBuildManifestSHA256 -or
            [string]$record.build_input_fingerprint_sha256 -ine
                $ExpectedBuildFingerprintSHA256 -or
            [string]$record.executable_sha256 -ine $ExpectedExecutableSHA256) {
            throw "Expert recovery sample $i contract is inconsistent"
        }
        if ($lastTokenByRequest.ContainsKey($requestKey) -and
            ($tokenIndex -le [UInt64]$lastTokenByRequest[$requestKey] -or
             $callTick -le [UInt64]$lastCallByRequest[$requestKey])) {
            throw "Expert recovery request-local token/call ordering is invalid"
        }
        $lastTokenByRequest[$requestKey] = $tokenIndex
        $lastCallByRequest[$requestKey] = $callTick
        $requestMin = [math]::Min([decimal]$requestMin, [decimal]$requestEpoch)
        $requestMax = [math]::Max([decimal]$requestMax, [decimal]$requestEpoch)
        $callMin = [math]::Min([decimal]$callMin, [decimal]$callTick)
        $callMax = [math]::Max([decimal]$callMax, [decimal]$callTick)
        $records += $record
    }
    if ([UInt64]$requestMin -ne [UInt64]$manifest.request_epoch_min -or
        [UInt64]$requestMax -ne [UInt64]$manifest.request_epoch_max -or
        [UInt64]$callMin -ne [UInt64]$manifest.call_tick_min -or
        [UInt64]$callMax -ne [UInt64]$manifest.call_tick_max) {
        throw "Expert recovery manifest epoch range is inconsistent with JSONL"
    }
    [pscustomobject]@{
        requested = $true
        observed = $true
        valid = $true
        input_only = $true
        teacher_output_reconstruction =
            "offline_exact_iq2_from_captured_input"
        layer = $ExpectedLayer
        expert = $ExpectedExpert
        sample_count = $sampleCount
        max_samples = $ExpectedMaxSamples
        capped_samples = [UInt64]$manifest.capped_samples
        vector_dim = $vectorDim
        vector_bytes_per_sample = $vectorBytes
        binary_bytes = $binaryBytes
        artifact_bytes_total = [UInt64]$binaryInfo.Length +
            [UInt64]$jsonlInfo.Length + [UInt64]$manifestInfo.Length
        byte_budget = $ExpectedByteBudget
        binary_path = $paths.binary
        binary_sha256 = $binarySHA
        jsonl_path = $paths.jsonl
        jsonl_sha256 = $jsonlSHA
        jsonl_physical_lines = [UInt64]$physicalLines.Count
        manifest_path = $paths.manifest
        manifest_sha256 = (Get-FileHash -LiteralPath $paths.manifest `
            -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

function New-G7ExpertRecoverySelfTestFixture {
    param(
        [Parameter(Mandatory=$true)][string]$Root,
        [Parameter(Mandatory=$true)][string]$Prefix,
        [string]$Case = "positive"
    )
    New-Item -ItemType Directory -Path $Root -Force | Out-Null
    $modelSHA = "a" * 64
    $sidecarSHA = "b" * 64
    $buildSHA = "c" * 64
    $fingerprint = "d" * 64
    $exeSHA = "e" * 64
    $binaryPath = $Prefix + ".vectors.f32le"
    $jsonlPath = $Prefix + ".samples.jsonl"
    $manifestPath = $Prefix + ".manifest.json"
    $stream = New-Object IO.MemoryStream
    $writer = New-Object IO.BinaryWriter($stream)
    $writer.Write([Text.Encoding]::ASCII.GetBytes("DS4ERTR1"))
    $writer.Write([UInt32]1); $writer.Write([UInt32]64)
    $writer.Write([UInt32]1); $writer.Write([UInt32]4)
    $writer.Write([UInt32]3); $writer.Write([UInt32]2)
    $writer.Write([UInt64]16); $writer.Write([UInt64]32)
    $writer.Write([UInt64]4096); $writer.Write([UInt64]0)
    foreach ($value in @([Single]1, [Single]2, [Single]3, [Single]4,
                          [Single]5, [Single]6, [Single]7, [Single]8)) {
        $writer.Write($value)
    }
    $writer.Flush()
    [IO.File]::WriteAllBytes($binaryPath, $stream.ToArray())
    $writer.Dispose(); $stream.Dispose()
    $records = @()
    for ($i = 0; $i -lt 2; $i++) {
        $records += [pscustomobject][ordered]@{
            schema = "ds4_expert_recovery_sample_v1"
            sample_index = [UInt64]$i
            request_epoch = [UInt64]1
            call_tick = [UInt64](10 + $i)
            token_index = [UInt64]$i
            layer = [UInt64]3
            expert = [UInt64]0
            topk_rank = [UInt64]$i
            gate_weight_decimal = "0.5"
            gate_weight_f32_le_hex = "3f000000"
            representation = $(if ($i -eq 0) { "q1_resident" } else { "iq2_vram" })
            dtype = "float32-le"
            shape = @([UInt64]4)
            vector_offset = [UInt64](64 + 16 * $i)
            vector_bytes = [UInt64]16
            model_sha256 = $modelSHA
            model_bytes = [UInt64]1000
            sidecar_sha256 = $sidecarSHA
            sidecar_bytes = [UInt64]2000
            build_manifest_sha256 = $buildSHA
            build_input_fingerprint_sha256 = $fingerprint
            executable_sha256 = $exeSHA
        }
    }
    $lines = @($records | ForEach-Object {
        ConvertTo-G7ExpertRecoveryCanonicalSample $_
    })
    switch ($Case) {
        "missing-field" {
            $lines[0] = $lines[0].Replace(',"call_tick":10', '')
        }
        "offset" {
            $lines[0] = $lines[0].Replace('"vector_offset":64',
                                          '"vector_offset":65')
        }
        "duplicate-key" {
            $lines[0] = $lines[0].Replace('"sample_index":0',
                '"sample_index":0,"sample_index":0')
        }
        "array" { $lines[0] = "[" + $lines[0] + "]" }
        "wrong-expert" {
            $lines[0] = $lines[0].Replace('"expert":0', '"expert":1')
        }
    }
    $jsonlText = ($lines -join "`n") + "`n"
    if ($Case -eq "blank-line") { $jsonlText = $lines[0] + "`n`n" + $lines[1] + "`n" }
    $utf8NoBom = [Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText($jsonlPath, $jsonlText, $utf8NoBom)
    $binarySHA = (Get-FileHash $binaryPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $jsonlSHA = (Get-FileHash $jsonlPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $manifest = [pscustomobject][ordered]@{
        schema = "ds4_expert_recovery_manifest_v1"
        status = "complete"
        input_only = $true
        teacher_output_captured = $false
        teacher_output_reconstruction = "offline_exact_iq2_from_captured_input"
        dtype = "float32-le"
        shape = @([UInt64]2, [UInt64]4)
        header_bytes = [UInt64]64
        sample_count = [UInt64]2
        max_samples = [UInt64]$(if ($Case -eq "cap-overflow") { 257 } else { 3 })
        capped_samples = [UInt64]0
        vector_dim = [UInt64]4
        vector_bytes_per_sample = [UInt64]16
        binary_bytes = [UInt64]96
        byte_budget = [UInt64]4096
        layer = [UInt64]3
        expert = [UInt64]0
        request_epoch_min = [UInt64]1
        request_epoch_max = [UInt64]1
        call_tick_min = [UInt64]10
        call_tick_max = [UInt64]11
        binary_file = [IO.Path]::GetFileName($binaryPath)
        binary_sha256 = $binarySHA
        jsonl_file = [IO.Path]::GetFileName($jsonlPath)
        jsonl_bytes = [UInt64](Get-Item $jsonlPath).Length
        jsonl_sha256 = $jsonlSHA
        model_sha256 = $modelSHA
        model_bytes = [UInt64]1000
        sidecar_sha256 = $sidecarSHA
        sidecar_bytes = [UInt64]2000
        build_manifest_sha256 = $buildSHA
        build_input_fingerprint_sha256 = $fingerprint
        executable_sha256 = $exeSHA
    }
    [IO.File]::WriteAllText(
        $manifestPath,
        (ConvertTo-G7ExpertRecoveryCanonicalManifest $manifest) + "`n",
        $utf8NoBom)
    if ($Case -eq "stale-sha") {
        [IO.File]::AppendAllText($jsonlPath, " ", $utf8NoBom)
    } elseif ($Case -eq "partial-only") {
        Move-Item -LiteralPath $manifestPath -Destination ($manifestPath + ".partial")
    }
    [pscustomobject]@{
        model_sha = $modelSHA; sidecar_sha = $sidecarSHA
        build_sha = $buildSHA; fingerprint = $fingerprint; exe_sha = $exeSHA
    }
}

function Invoke-G7ExpertRecoveryTraceParserSelfTest {
    $base = Join-Path ([IO.Path]::GetTempPath()) `
        ("g7_expert_recovery_" + [Guid]::NewGuid().ToString("N"))
    $negativeCases = @("missing-field", "offset", "duplicate-key", "array",
        "wrong-expert", "blank-line", "cap-overflow", "stale-sha",
        "partial-only")
    try {
        $positiveRoot = Join-Path $base "positive"
        $positivePrefix = Join-Path $positiveRoot "trace"
        $ids = New-G7ExpertRecoverySelfTestFixture `
            -Root $positiveRoot -Prefix $positivePrefix
        $positive = Read-G7ExpertRecoveryTraceArtifact -Required $true `
            -RootPath $positiveRoot -OutputPrefix $positivePrefix `
            -ExpectedLayer 3 -ExpectedExpert 0 -ExpectedMaxSamples 3 `
            -ExpectedByteBudget 4096 -ExpectedModelSHA256 $ids.model_sha `
            -ExpectedModelBytes 1000 -ExpectedSidecarSHA256 $ids.sidecar_sha `
            -ExpectedSidecarBytes 2000 `
            -ExpectedBuildManifestSHA256 $ids.build_sha `
            -ExpectedBuildFingerprintSHA256 $ids.fingerprint `
            -ExpectedExecutableSHA256 $ids.exe_sha
        if (-not $positive.valid -or $positive.sample_count -ne 2) {
            throw "Expert recovery positive fixture failed"
        }
        $observedNegatives = @()
        foreach ($case in $negativeCases) {
            $root = Join-Path $base $case
            $prefix = Join-Path $root "trace"
            $caseIds = New-G7ExpertRecoverySelfTestFixture `
                -Root $root -Prefix $prefix -Case $case
            try {
                [void](Read-G7ExpertRecoveryTraceArtifact -Required $true `
                    -RootPath $root -OutputPrefix $prefix `
                    -ExpectedLayer 3 -ExpectedExpert 0 -ExpectedMaxSamples 3 `
                    -ExpectedByteBudget 4096 `
                    -ExpectedModelSHA256 $caseIds.model_sha `
                    -ExpectedModelBytes 1000 `
                    -ExpectedSidecarSHA256 $caseIds.sidecar_sha `
                    -ExpectedSidecarBytes 2000 `
                    -ExpectedBuildManifestSHA256 $caseIds.build_sha `
                    -ExpectedBuildFingerprintSHA256 $caseIds.fingerprint `
                    -ExpectedExecutableSHA256 $caseIds.exe_sha)
                throw "Expert recovery negative fixture was accepted: $case"
            } catch {
                if ($_.Exception.Message -like
                    "Expert recovery negative fixture was accepted:*") { throw }
                $observedNegatives += $case
            }
        }
        $siblingRoot = Join-Path $base "root"
        $sibling = Join-Path $base "root_evil"
        New-Item -ItemType Directory -Path $siblingRoot -Force | Out-Null
        $siblingPrefix = Join-Path $sibling "trace"
        $siblingIds = New-G7ExpertRecoverySelfTestFixture `
            -Root $sibling -Prefix $siblingPrefix
        try {
            [void](Read-G7ExpertRecoveryTraceArtifact -Required $true `
                -RootPath $siblingRoot -OutputPrefix $siblingPrefix `
                -ExpectedLayer 3 -ExpectedExpert 0 -ExpectedMaxSamples 3 `
                -ExpectedByteBudget 4096 `
                -ExpectedModelSHA256 $siblingIds.model_sha `
                -ExpectedModelBytes 1000 `
                -ExpectedSidecarSHA256 $siblingIds.sidecar_sha `
                -ExpectedSidecarBytes 2000 `
                -ExpectedBuildManifestSHA256 $siblingIds.build_sha `
                -ExpectedBuildFingerprintSHA256 $siblingIds.fingerprint `
                -ExpectedExecutableSHA256 $siblingIds.exe_sha)
            throw "Expert recovery sibling path fixture was accepted"
        } catch {
            if ($_.Exception.Message -eq
                "Expert recovery sibling path fixture was accepted") { throw }
            $observedNegatives += "path-sibling"
        }
        [pscustomobject]@{
            schema = "g7_expert_recovery_trace_parser_selftest_v1"
            status = "pass"
            positive_samples = 2
            negative_cases = @($observedNegatives)
        } | ConvertTo-Json -Compress
    } finally {
        if (Test-Path -LiteralPath $base) {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }
}

if ($Q1_0SsdWrapParserSelfTest) {
    Invoke-G7Q1_0SsdWrapParserSelfTest
    exit 0
}
if ($Q1_0ProfileParserSelfTest) {
    Invoke-G7Q1_0ProfileParserSelfTest
    exit 0
}
if ($ExpertRecoveryTraceParserSelfTest) {
    Invoke-G7ExpertRecoveryTraceParserSelfTest
    exit 0
}
function Assert-G7U64Sum3 {
    param([UInt64]$A, [UInt64]$B, [UInt64]$C, [UInt64]$Expected,
          [string]$Label)

    $sum = [decimal]$A + [decimal]$B + [decimal]$C
    if ($sum -gt [decimal][UInt64]::MaxValue -or
        [UInt64]$sum -ne $Expected) {
        throw "Q1_0 promotion $Label byte sum is invalid"
    }
}
function Assert-G7PromotionOffsetFormula {
    param(
        [UInt64]$BaseOffset,
        [UInt64]$Stride,
        [UInt32]$Expert,
        [UInt64]$Bytes,
        [UInt64]$ObservedOffset,
        [UInt64]$ModelSize,
        [string]$Label
    )

    $expected = [decimal]$BaseOffset + ([decimal]$Expert * [decimal]$Stride)
    $end = [decimal]$ObservedOffset + [decimal]$Bytes
    if ($Stride -eq 0 -or $Bytes -eq 0 -or $ModelSize -eq 0 -or
        $expected -gt [decimal][UInt64]::MaxValue -or
        [UInt64]$expected -ne $ObservedOffset -or
        $end -gt [decimal]$ModelSize) {
        throw "Q1_0 promotion $Label offset formula/range is invalid"
    }
}
function Get-G7PromotionRecordKey {
    param([Parameter(Mandatory=$true)][object]$Row)

    return ("{0}:{1}" -f [UInt64]$Row.request_epoch, [UInt64]$Row.record_id)
}
function Get-G7PromotionRecordIdentity {
    param([Parameter(Mandatory=$true)][object]$Row)

    return ("{0}:{1}:{2}:{3}:{4}:{5}" -f
        [UInt64]$Row.request_epoch, [UInt64]$Row.record_id,
        [UInt32]$Row.layer, [UInt32]$Row.expert,
        [UInt64]$Row.observation_call,
        [UInt64]$Row.first_eligible_call)
}
function Get-G7PromotionRecordImmutableIdentity {
    param([Parameter(Mandatory=$true)][object]$Row)

    $mutable = @{
        line_index = $true
        physical_line = $true
        kind = $true
        result = $true
        reason = $true
        destination_kind = $true
        destination_ram_slot = $true
        destination_ram_generation = $true
    }
    $parts = @()
    foreach ($property in @($Row.PSObject.Properties.Name | Sort-Object)) {
        if ($mutable.ContainsKey($property)) { continue }
        $value = $Row.PSObject.Properties[$property].Value
        $parts += ('{0}={1}' -f $property, [Convert]::ToString(
            $value, [Globalization.CultureInfo]::InvariantCulture))
    }
    return ($parts -join "`n")
}
function Get-G7PreflightMedian([double[]]$Values) {
    if ($null -eq $Values -or $Values.Count -eq 0) { return $null }
    $sorted = @($Values | Sort-Object)
    $middle = [int][math]::Floor($sorted.Count / 2)
    if (($sorted.Count % 2) -eq 1) { return [double]$sorted[$middle] }
    return ([double]$sorted[$middle - 1] + [double]$sorted[$middle]) / 2.0
}
function Get-G7FileId([string]$Path) {
    $raw = & fsutil.exe file queryfileid $Path 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Verified receipt file-id query failed: $Path"
    }
    $match = [regex]::Match(($raw -join " "), '0x[0-9a-fA-F]{32}')
    if (-not $match.Success) {
        throw "Verified receipt file-id parse failed: $Path"
    }
    $match.Value.ToLowerInvariant()
}
function Read-G7ReceiptSnapshot([string]$Path, [string]$Kind) {
    $stream = $null
    try {
        $stream = [IO.File]::Open(
            $Path, [IO.FileMode]::Open,
            [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $memory = New-Object IO.MemoryStream
        try {
            $stream.CopyTo($memory)
            $bytes = $memory.ToArray()
        } finally {
            $memory.Dispose()
        }
    } catch {
        throw "$Kind verified receipt could not be read: $($_.Exception.Message)"
    } finally {
        if ($null -ne $stream) { $stream.Dispose() }
    }
    try {
        $jsonOffset = 0
        if ($bytes.Length -ge 3 -and
            $bytes[0] -eq 0xEF -and
            $bytes[1] -eq 0xBB -and
            $bytes[2] -eq 0xBF) {
            $jsonOffset = 3
        }
        $jsonText = [Text.Encoding]::UTF8.GetString(
            $bytes, $jsonOffset, $bytes.Length - $jsonOffset)
        $receipt = $jsonText | ConvertFrom-Json
    } catch {
        throw "$Kind verified receipt is invalid JSON"
    }
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $receiptHash = [BitConverter]::ToString(
            $sha.ComputeHash($bytes)).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
    [pscustomobject]@{
        receipt = $receipt
        sha256 = $receiptHash
    }
}
function Assert-G7VerifiedFileReceipt {
    param(
        [Parameter(Mandatory=$true)][object]$Receipt,
        [Parameter(Mandatory=$true)][IO.FileInfo]$Info,
        [Parameter(Mandatory=$true)][string]$ExpectedSHA256,
        [Parameter(Mandatory=$true)][string]$Kind
    )
    $fullPath = [IO.Path]::GetFullPath($Info.FullName)
    $receiptPath = [IO.Path]::GetFullPath([string]$Receipt.path)
    $fileId = Get-G7FileId $fullPath
    $verifiedAt = [DateTime]::MinValue
    if (-not [DateTime]::TryParse(
            [string]$Receipt.verified_at,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AdjustToUniversal,
            [ref]$verifiedAt)) {
        throw "$Kind verified receipt timestamp is invalid"
    }
    if ([string]$Receipt.schema -ne "g7_verified_file_receipt_v2" -or
        [string]$Receipt.status -ne "verified" -or
        -not [string]::Equals(
            $receiptPath, $fullPath,
            [StringComparison]::OrdinalIgnoreCase) -or
        [UInt64]$Receipt.bytes -ne [UInt64]$Info.Length -or
        [string]$Receipt.sha256 -ine $ExpectedSHA256 -or
        [Int64]$Receipt.creation_utc_ticks -ne $Info.CreationTimeUtc.Ticks -or
        [Int64]$Receipt.last_write_utc_ticks -ne $Info.LastWriteTimeUtc.Ticks -or
        [string]$Receipt.file_id -ine $fileId -or
        ($Info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
        $verifiedAt.ToUniversalTime() -lt $Info.LastWriteTimeUtc -or
        [string]::IsNullOrWhiteSpace([string]$Receipt.verification_method)) {
        throw "$Kind verified receipt identity mismatch"
    }
}
function Assert-G7SuiteChildBinding {
    param(
        [Parameter(Mandatory=$true)][object]$Child,
        [Parameter(Mandatory=$true)][string]$ExpectedReceiptPath,
        [Parameter(Mandatory=$true)][string]$ObservedReceiptSHA256,
        [Parameter(Mandatory=$true)][IO.FileInfo]$Info,
        [Parameter(Mandatory=$true)][string]$ExpectedFileSHA256,
        [Parameter(Mandatory=$true)][UInt64]$ExpectedBytes,
        [Parameter(Mandatory=$true)][string]$Kind
    )
    $livePath = [IO.Path]::GetFullPath($Info.FullName)
    $childReceiptPath = [IO.Path]::GetFullPath([string]$Child.receipt_path)
    $expectedReceiptFull = [IO.Path]::GetFullPath($ExpectedReceiptPath)
    $childPath = [IO.Path]::GetFullPath([string]$Child.path)
    $fileId = Get-G7FileId $livePath
    if (-not [string]::Equals(
            $childReceiptPath, $expectedReceiptFull,
            [StringComparison]::OrdinalIgnoreCase) -or
        [string]$Child.receipt_sha256 -ine $ObservedReceiptSHA256 -or
        -not [string]::Equals(
            $childPath, $livePath,
            [StringComparison]::OrdinalIgnoreCase) -or
        [UInt64]$Child.bytes -ne $ExpectedBytes -or
        [UInt64]$Info.Length -ne $ExpectedBytes -or
        [string]$Child.sha256 -ine $ExpectedFileSHA256 -or
        [string]$Child.hash_method -ne "locked_stream_sha256" -or
        [bool]$Child.full_hash_verified -ne $true -or
        [Int64]$Child.creation_utc_ticks -ne $Info.CreationTimeUtc.Ticks -or
        [Int64]$Child.last_write_utc_ticks -ne $Info.LastWriteTimeUtc.Ticks -or
        [string]$Child.file_id -ine $fileId -or
        ($Info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "$Kind suite receipt binding mismatch"
    }
}
function Get-G7Win32CodeFromException([Exception]$Exception) {
    return ($Exception.HResult -band 0xffff)
}
function Ensure-G7NativeShareProbe {
    if ("G7NativeShareProbe" -as [type]) { return }
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class G7NativeShareProbe {
    [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    public static extern IntPtr CreateFileW(
        string lpFileName, UInt32 dwDesiredAccess, UInt32 dwShareMode,
        IntPtr lpSecurityAttributes, UInt32 dwCreationDisposition,
        UInt32 dwFlagsAndAttributes, IntPtr hTemplateFile);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool CloseHandle(IntPtr hObject);
}
"@
}
function Test-G7SharingViolationProof {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Kind
    )
    $writeObserved = $false
    $writeError = ""
    $writeWin32 = 0
    $deleteObserved = $false
    $deleteError = ""
    $deleteWin32 = 0
    try {
        $writeProbe = [IO.File]::Open(
            $Path, [IO.FileMode]::Open,
            [IO.FileAccess]::Write,
            [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
        $writeProbe.Dispose()
        $writeError = "opened"
    } catch [IO.IOException] {
        $writeWin32 = Get-G7Win32CodeFromException $_.Exception
        if ($writeWin32 -eq 32) {
            $writeObserved = $true
            $writeError = "ERROR_SHARING_VIOLATION"
        } else {
            throw "$Kind deny-write lock proof failed with IO error $writeWin32"
        }
    } catch [UnauthorizedAccessException] {
        throw "$Kind deny-write lock proof hit ACL denial, not sharing violation"
    }
    Ensure-G7NativeShareProbe
    $deleteAccess = [UInt32]0x00010000
    $shareAll = [UInt32]7
    $openExisting = [UInt32]3
    $normal = [UInt32]0x00000080
    $handle = [G7NativeShareProbe]::CreateFileW(
        $Path, $deleteAccess, $shareAll, [IntPtr]::Zero,
        $openExisting, $normal, [IntPtr]::Zero)
    if ($handle -eq [IntPtr]::Zero -or $handle -eq [IntPtr](-1)) {
        $deleteWin32 = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        if ($deleteWin32 -eq 32) {
            $deleteObserved = $true
            $deleteError = "ERROR_SHARING_VIOLATION"
        } elseif ($deleteWin32 -eq 5) {
            throw "$Kind deny-delete lock proof hit ACL denial, not sharing violation"
        } else {
            throw "$Kind deny-delete lock proof failed with Win32 error $deleteWin32"
        }
    } else {
        [G7NativeShareProbe]::CloseHandle($handle) | Out-Null
        $deleteError = "opened"
    }
    [pscustomobject]@{
        path = [IO.Path]::GetFullPath($Path)
        deny_write_observed = $writeObserved
        deny_write_error = $writeError
        deny_write_win32 = $writeWin32
        deny_delete_observed = $deleteObserved
        deny_delete_error = $deleteError
        deny_delete_win32 = $deleteWin32
        acl_denial = $false
        sharing_violation_lock_proof =
            [bool]($writeObserved -and $deleteObserved)
    }
}
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
if ($ExpectedModelSHA256 -and $ExpectedModelSHA256 -notmatch '^[0-9a-fA-F]{64}$') {
    throw "ExpectedModelSHA256 must be a 64-character hexadecimal SHA-256"
}
if ($ExpectedQ1_0ExpertSidecarSHA256 -and
    $ExpectedQ1_0ExpertSidecarSHA256 -notmatch '^[0-9a-fA-F]{64}$') {
    throw "ExpectedQ1_0ExpertSidecarSHA256 must be a 64-character hexadecimal SHA-256"
}
if ($ExpectedNestedResidualSourceSHA256 -and
    $ExpectedNestedResidualSourceSHA256 -notmatch '^[0-9a-fA-F]{64}$') {
    throw "ExpectedNestedResidualSourceSHA256 must be a 64-character hexadecimal SHA-256"
}
if ($ExpectedNestedResidualSidecarSHA256 -and
    $ExpectedNestedResidualSidecarSHA256 -notmatch '^[0-9a-fA-F]{64}$') {
    throw "ExpectedNestedResidualSidecarSHA256 must be a 64-character hexadecimal SHA-256"
}
if ($ExpectedNestedResidualPayloadSHA256 -and
    $ExpectedNestedResidualPayloadSHA256 -notmatch '^[0-9a-fA-F]{64}$') {
    throw "ExpectedNestedResidualPayloadSHA256 must be a 64-character hexadecimal SHA-256"
}
if ($ExpectedNestedResidualGpuJoinSafetyReceiptSHA256 -and
    $ExpectedNestedResidualGpuJoinSafetyReceiptSHA256 -notmatch
        '^[0-9a-fA-F]{64}$') {
    throw "ExpectedNestedResidualGpuJoinSafetyReceiptSHA256 must be a 64-character hexadecimal SHA-256"
}
if ($ExpectedModelIq1SuiteReceiptSHA256 -and
    $ExpectedModelIq1SuiteReceiptSHA256 -notmatch '^[0-9a-fA-F]{64}$') {
    throw "ExpectedModelIq1SuiteReceiptSHA256 must be a 64-character hexadecimal SHA-256"
}
if ($ReuseVerifiedModelReceipt -and -not $ExpectedModelSHA256) {
    throw "ReuseVerifiedModelReceipt requires ExpectedModelSHA256"
}
if ($ReuseVerifiedQ1_0Receipt -and -not $ExpectedQ1_0ExpertSidecarSHA256) {
    throw "ReuseVerifiedQ1_0Receipt requires ExpectedQ1_0ExpertSidecarSHA256"
}
if (($ReuseVerifiedModelReceipt -or $ReuseVerifiedIq1SReceipt -or
     $ReuseVerifiedQ1_0Receipt) -and
    $GateKind -ne "structural-safety" -and
    -not ($AllowBenchmarkVerifiedReceiptReuse -and
          $GateKind -eq "benchmark")) {
    throw "Verified receipt reuse is restricted to structural-safety diagnostics"
}
if ($AllowBenchmarkVerifiedReceiptReuse) {
    if ($GateKind -ne "benchmark") {
        throw "AllowBenchmarkVerifiedReceiptReuse requires GateKind=benchmark"
    }
    if (-not $ReuseVerifiedModelReceipt) {
        throw "Benchmark verified receipt reuse requires the model receipt"
    }
    if ($Q1_0ExpertSidecar -and -not $ReuseVerifiedQ1_0Receipt) {
        throw "Benchmark Q1_0 receipt reuse requires the Q1_0 receipt"
    }
    if ($Iq1SExpertSidecar -and -not $ReuseVerifiedIq1SReceipt) {
        throw "Benchmark IQ1_S receipt reuse requires the IQ1_S receipt"
    }
}
if ($ReuseVerifiedSuiteReceipt) {
    if ($GateKind -eq "quality" -and -not $AllowQualityVerifiedSuiteReceipt) {
        throw "Verified suite receipt reuse is restricted to benchmark and structural-safety gates"
    }
    if ($ReuseVerifiedModelReceipt -or $ReuseVerifiedIq1SReceipt) {
        throw "ReuseVerifiedSuiteReceipt cannot be combined with per-file verified receipt reuse switches"
    }
    if (-not $ModelIq1SuiteReceiptPath -or -not $ExpectedModelIq1SuiteReceiptSHA256) {
        throw "ReuseVerifiedSuiteReceipt requires ModelIq1SuiteReceiptPath and ExpectedModelIq1SuiteReceiptSHA256"
    }
    if (-not $ExpectedModelSHA256) {
        throw "ReuseVerifiedSuiteReceipt requires ExpectedModelSHA256"
    }
    if (-not $Iq1SExpertSidecar -or
        -not $ExpectedIq1SExpertSidecarSHA256 -or
        $ExpectedIq1SExpertSidecarBytes -eq 0) {
        throw "ReuseVerifiedSuiteReceipt requires IQ1_S sidecar path, SHA-256, and byte count"
    }
}
if ($AllowQualityVerifiedSuiteReceipt) {
    if ($GateKind -ne "quality") {
        throw "AllowQualityVerifiedSuiteReceipt requires GateKind=quality"
    }
    if (-not $ReuseVerifiedSuiteReceipt) {
        throw "AllowQualityVerifiedSuiteReceipt requires ReuseVerifiedSuiteReceipt"
    }
    if ($Repeats -ne 1) {
        throw "Outer quality suite members require Repeats=1"
    }
    if ($OuterQualityProcessCount -lt 3) {
        throw "Outer quality suite members require OuterQualityProcessCount >= 3"
    }
    if ($SkipSystemQuiescencePreflight) {
        throw "Outer quality suite members require system quiescence preflight"
    }
} elseif ($OuterQualityProcessCount -ne 0) {
    throw "OuterQualityProcessCount requires AllowQualityVerifiedSuiteReceipt"
}
if ((-not $ReuseVerifiedSuiteReceipt) -and
    ($ModelIq1SuiteReceiptPath -or $ExpectedModelIq1SuiteReceiptSHA256)) {
    throw "ModelIq1SuiteReceiptPath and ExpectedModelIq1SuiteReceiptSHA256 require ReuseVerifiedSuiteReceipt"
}
if ($AllowEmbeddedBakeMask -and
    $ExpectedEmbeddedBakeMaskSHA256 -notmatch '^[0-9a-fA-F]{64}$') {
    throw "AllowEmbeddedBakeMask requires ExpectedEmbeddedBakeMaskSHA256"
}
if (-not $AllowEmbeddedBakeMask -and $ExpectedEmbeddedBakeMaskSHA256) {
    throw "ExpectedEmbeddedBakeMaskSHA256 requires AllowEmbeddedBakeMask"
}
if ($AllowEmbeddedBakeMask -and $ReapMaskFile) {
    throw "AllowEmbeddedBakeMask cannot be combined with ReapMaskFile"
}
if ($ForceOpenRouter -and ($ReapMaskFile -or $AllowEmbeddedBakeMask)) {
    throw "ForceOpenRouter cannot be combined with a static or embedded mask"
}
if ($WarmupPrompt -and -not $Warmup) {
    throw "WarmupPrompt requires -Warmup"
}
if ($WarmupMaxTokens -gt 0 -and -not $Warmup) {
    throw "WarmupMaxTokens requires -Warmup"
}
if ($RequestPhaseTrace -and -not $PrefillMassWrap) {
    throw "RequestPhaseTrace currently requires -PrefillMassWrap"
}
if ($ArenaWrapTrimBetweenPhases -and
    (-not $ArenaWrapSourceParts -or -not $ArenaWrapTrustWorkerChecksum)) {
    throw "ArenaWrapTrimBetweenPhases requires -ArenaWrapSourceParts and -ArenaWrapTrustWorkerChecksum"
}
if ($ArenaWrapUnlockSourceRanges -and
    (-not $ArenaWrapSourceParts -or -not $ArenaWrapTrustWorkerChecksum)) {
    throw "ArenaWrapUnlockSourceRanges requires -ArenaWrapSourceParts and -ArenaWrapTrustWorkerChecksum"
}
if ($ArenaWrapUnlockWaveGiB -gt 0.0 -and -not $ArenaWrapUnlockSourceRanges) {
    throw "ArenaWrapUnlockWaveGiB greater than 0 requires -ArenaWrapUnlockSourceRanges"
}
if ($ArenaWrapUnlockSourceRanges -and $ArenaWrapTrimBetweenPhases) {
    throw "ArenaWrapUnlockSourceRanges is incompatible with -ArenaWrapTrimBetweenPhases"
}
if ($ArenaWrapUnlockSourceRanges -and ($ArenaWrapSequentialFile -or $ArenaWrapRandomFile)) {
    throw "ArenaWrapUnlockSourceRanges is incompatible with ArenaWrap file source modes"
}
if ($ArenaWrapSequentialFile -and -not $ArenaWrapSourceParts) {
    throw "ArenaWrapSequentialFile requires -ArenaWrapSourceParts"
}
if ($ArenaWrapRandomFile -and -not $ArenaWrapSourceParts) {
    throw "ArenaWrapRandomFile requires -ArenaWrapSourceParts"
}
if ($ArenaWrapRandomFile -and $ArenaWrapSequentialFile) {
    throw "Select only one ArenaWrap file source"
}
if ($ArenaWrapLayoutProfile -and -not $ArenaWrapSourceParts) {
    throw "ArenaWrapLayoutProfile requires -ArenaWrapSourceParts"
}
if ($ArenaWrapSequentialWorkers -ne 1 -and -not $ArenaWrapSequentialFile) {
    throw "ArenaWrapSequentialWorkers other than 1 requires -ArenaWrapSequentialFile"
}
if ($ArenaWrapFileQD -gt 1) {
    if (-not $ArenaWrapSourceParts -or -not $ArenaWrapSequentialFile -or
        -not $ArenaWrapTrustWorkerChecksum -or
        $ArenaWrapSequentialWorkers -ne 1) {
        throw "ArenaWrapFileQD greater than 1 requires -ArenaWrapSourceParts, -ArenaWrapSequentialFile, -ArenaWrapTrustWorkerChecksum, and -ArenaWrapSequentialWorkers 1"
    }
    if ($ArenaWrapPartProfile) {
        throw "ArenaWrapFileQD greater than 1 cannot be combined with -ArenaWrapPartProfile"
    }
}
if ($QuiescenceProbeOnly -and $SkipSystemQuiescencePreflight) {
    throw "QuiescenceProbeOnly cannot be combined with SkipSystemQuiescencePreflight"
}
if ($RequestPhaseTrace -and ($Warmup -or $Repeats -ne 1 -or $MaxTokens -le 0)) {
    throw "RequestPhaseTrace requires one non-warmup request with MaxTokens greater than zero"
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
if ($SplitFused -and -not $GpuResidentRoutes) {
    throw "SplitFused requires -GpuResidentRoutes"
}
if ($RouteNoDefaultSync -and -not $GpuResidentRoutes) {
    throw "RouteNoDefaultSync requires -GpuResidentRoutes"
}
if ($RoutePackedCopy -and -not $GpuResidentRoutes) {
    throw "RoutePackedCopy requires -GpuResidentRoutes"
}
if ($RouteNoDefaultSync -and $SplitHitMiss) {
    throw "RouteNoDefaultSync must be isolated from SplitHitMiss"
}
if ($SplitHitMiss -and $SplitFused) {
    throw "SplitHitMiss and SplitFused are mutually exclusive"
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
$modelReceiptAtStart = $null
$modelReceiptPath = ""
$modelReceiptHashAtStart = ""
$modelLockStream = $null
$q1_0SidecarInfoAtStart = $null
$q1_0SidecarReceiptAtStart = $null
$q1_0SidecarReceiptPath = ""
$q1_0SidecarReceiptHashAtStart = ""
$q1_0SidecarLockStream = $null
$iq1SSidecarInfoAtStart = $null
$iq1SSidecarReceiptAtStart = $null
$iq1SSidecarReceiptPath = ""
$iq1SSidecarReceiptHashAtStart = ""
$iq1SSidecarLockStream = $null
$nestedResidualLockStream = $null
$nestedResidualInfoAtStart = $null
$nestedResidualHashAtStart = ""
$nestedResidualGpuJoinSafetyReceiptLockStream = $null
$nestedResidualGpuJoinSafetyResultLockStream = $null
$nestedResidualGpuJoinSafetyReceiptAtStart = $null
$nestedResidualGpuJoinSafetyReceiptPathAtStart = ""
$nestedResidualGpuJoinSafetyReceiptHashAtStart = ""
$nestedResidualGpuJoinSafetyResultAtStart = $null
$nestedResidualGpuJoinSafetyResultPathAtStart = ""
$nestedResidualGpuJoinSafetyResultHashAtStart = ""
$nestedResidualGpuJoinSafetyReceiptValidated = $false
$modelIq1SuiteReceiptAtStart = $null
$modelIq1SuiteReceiptPathAtStart = ""
$modelIq1SuiteReceiptHashAtStart = ""
$modelIq1SuiteReceiptSchemaAtStart = ""
$modelIq1SuiteFullHashVerified = $false
$modelIq1SuiteLockProofRequired = $false
$modelIq1SuiteLockProofObserved = $false
$modelIq1SuiteLockProof = $null
$benchmarkVerifiedReceiptLockProofRequired = $false
$benchmarkVerifiedReceiptLockProofObserved = $false
$benchmarkVerifiedReceiptLockProof = $null
$nestedResidualBenchmarkMember = $false
$nestedResidualStructuralMember = $false
$nestedResidualAllLayerStorageRequested = [bool](
    $NestedResidualPageableBase -or $NestedResidualCachePageable -or
    $NestedResidualBasePinnedGiB -ne 0.0)
$nestedResidualExpectedBaseHostGiB = 0.0
$nestedResidualExpectedResidualCacheHostGiB = 0.0
$nestedResidualExpectedHostAllocationGiB = 0.0
if ($nestedResidualAllLayerStorageRequested) {
    # DS4 routed layers 3..42 contain 10,240 exact nested base entries at
    # 3.75 MiB each. Residual-cache slots are 3 MiB each.
    $nestedResidualExpectedBaseHostGiB = 37.5
    $nestedResidualExpectedResidualCacheHostGiB =
        ([double]$NestedResidualCacheExperts * 3.0) / 1024.0
    $nestedResidualExpectedHostAllocationGiB =
        $nestedResidualExpectedBaseHostGiB +
        $nestedResidualExpectedResidualCacheHostGiB + $DynamicArenaGiB
}
if ($AllowNestedResidualBenchmarkSuite) {
    if (-not $NestedResidualSidecar) {
        throw "AllowNestedResidualBenchmarkSuite requires NestedResidualSidecar"
    }
    if ($GateKind -ne "benchmark" -or $Repeats -ne 1 -or $Warmup) {
        throw "Nested residual outer benchmark members require GateKind=benchmark, Repeats=1, and no warmup"
    }
    if ($OuterNestedResidualBenchmarkProcessCount -lt 3) {
        throw "Nested residual outer benchmark suite requires at least 3 processes"
    }
    if (-not $NestedResidualGpuCache) {
        throw "Nested residual outer benchmark suite requires NestedResidualGpuCache"
    }
    $nestedResidualBenchmarkMember = $true
} elseif ($OuterNestedResidualBenchmarkProcessCount -ne 0) {
    throw "OuterNestedResidualBenchmarkProcessCount requires AllowNestedResidualBenchmarkSuite"
}
if (-not $Q1_0ExpertSidecar -and
    ($Q1_0SelectedLoad -or $ExpectedQ1_0ExpertSidecarSHA256 -or
     $ExpectedQ1_0ExpertSidecarBytes -ne 0 -or $Q1_0ResidentArena -or
      $Q1_0DualArena -or $Q1_0DualSparseCompanion -or
      $Q1_0MixedColdOne -or $Q1_0SnapshotBacking -or
      $Q1_0PageableOverflow -or
      $Q1_0PureResident -or $Q1_0Profile -or $ExpertRecoveryTrace -or
       $ExpectedQ1_0SnapshotEntries -ne 0 -or
       $ExpectedQ1_0ResidentEntries -ne 0 -or
      $ReuseVerifiedQ1_0Receipt)) {
    throw "Q1_0 selected-load and provenance options require Q1_0ExpertSidecar"
}
if ($NestedResidualSidecar) {
    if (-not (Test-Path -LiteralPath $NestedResidualSidecar -PathType Leaf)) {
        throw "Nested residual sidecar missing: $NestedResidualSidecar"
    }
    if (-not $ExpectedNestedResidualSidecarSHA256 -or
        -not $ExpectedNestedResidualSourceSHA256 -or
        -not $ExpectedNestedResidualPayloadSHA256) {
        throw "NestedResidualSidecar requires sidecar, source, and payload SHA-256"
    }
    $nestedResidualStructuralMember = [bool](
        $GateKind -eq "structural-safety" -and $Repeats -eq 1 -and
        -not $Warmup)
    if (-not $nestedResidualStructuralMember -and
        -not $nestedResidualBenchmarkMember) {
        throw "NestedResidualSidecar requires one structural-safety run or an explicit outer benchmark n>=3 member"
    }
    if ($Q1_0ExpertSidecar -or $Iq1SExpertSidecar -or $ReapMaskFile -or
        $SpexDryRun -or $SpexPrefetchK -gt 0 -or $SpexCpuProbeK -gt 0) {
        throw "NestedResidualSidecar must be isolated from Q1_0, IQ1_S, REAP masks, and SPEX"
    }
    if (-not $ExpectedModelSHA256 -or
        $ExpectedNestedResidualSourceSHA256 -ine $ExpectedModelSHA256) {
        throw "Nested residual source SHA-256 must equal the verified primary model SHA-256"
    }
    $NestedResidualSidecar =
        (Resolve-Path -LiteralPath $NestedResidualSidecar).Path
    $nestedResidualLockStream = [IO.File]::Open(
        $NestedResidualSidecar, [IO.FileMode]::Open,
        [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $nestedResidualInfoAtStart = Get-Item -LiteralPath $NestedResidualSidecar
    $nestedResidualHashAtStart = (Get-FileHash -LiteralPath `
        $NestedResidualSidecar -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($nestedResidualHashAtStart -ine
        $ExpectedNestedResidualSidecarSHA256) {
        throw "Nested residual full sidecar SHA-256 mismatch"
    }
} elseif ($ExpectedNestedResidualSidecarSHA256 -or
          $ExpectedNestedResidualSourceSHA256 -or
          $ExpectedNestedResidualPayloadSHA256 -or
          $NestedResidualVerifyReconstruction -or
          $NestedResidualProfile -or
          $NestedResidualPageableBase -or
          $NestedResidualBasePinnedGiB -ne 0.0 -or
          $NestedResidualCachePageable -or
          $NestedResidualStructuralN1 -or
          $NestedResidualGpuCache -or
          $NestedResidualGpuJoin -or
          $NestedResidualGpuJoinResidualCache -or
          $NestedResidualGpuJoinSafetyReceipt -or
          $ExpectedNestedResidualGpuJoinSafetyReceiptSHA256 -or
          $AllowNestedResidualBenchmarkSuite -or
          $OuterNestedResidualBenchmarkProcessCount -ne 0) {
    throw "Nested residual provenance and verification options require NestedResidualSidecar"
}
if ($NestedResidualStructuralN1 -and
    ($GateKind -ne "structural-safety" -or $Repeats -ne 1 -or $Warmup)) {
    throw "NestedResidualStructuralN1 requires GateKind=structural-safety, Repeats=1, and no warmup"
}
if ($nestedResidualStructuralMember -and
    $nestedResidualAllLayerStorageRequested -and
    -not $NestedResidualVerifyReconstruction) {
    throw "Nested residual all-layer storage requires exact reconstruction verification for safety"
}
if ($NestedResidualCacheExperts -gt 64 -and -not $NestedResidualCachePageable) {
    throw "Nested residual cache experts must fail closed above 64 unless NestedResidualCachePageable is enabled"
}
if ($NestedResidualPageableBase) {
    if (-not $NestedResidualGpuCache -or -not $NestedResidualGpuJoin) {
        throw "Nested residual pageable base requires NestedResidualGpuCache and NestedResidualGpuJoin"
    }
    if ($NestedResidualBasePinnedGiB -le 0.0) {
        throw "Nested residual base pinned GiB budget must be provided when pageable base is enabled"
    }
    if (-not $ForceOpenRouter -or $ReapMaskFile -or $AllowEmbeddedBakeMask) {
        throw "Nested residual all-layer storage requires full/open router and no mask"
    }
}
if ($nestedResidualAllLayerStorageRequested -and
    (-not $NestedResidualPageableBase -or
     -not $NestedResidualCachePageable)) {
    throw "G128 all-layer storage requires both pageable base and pageable residual cache"
}
if ($nestedResidualAllLayerStorageRequested -and
    $NestedResidualCacheExperts -lt 40) {
    throw "G128 all-layer storage requires at least one residual-cache slot per routed layer"
}
if ($nestedResidualAllLayerStorageRequested -and
    ($NestedResidualBasePinnedGiB + $DynamicArenaGiB) -gt 30.0) {
    throw "G128 all-layer storage requires nested base pinned GiB plus dynamic arena GiB <= 30"
}
if ($NestedResidualBasePinnedGiB -gt 0.0 -and -not $NestedResidualPageableBase) {
    throw "NestedResidualBasePinnedGiB requires NestedResidualPageableBase"
}
if ($NestedResidualCachePageable) {
    if (-not $NestedResidualGpuJoinResidualCache) {
        throw "NestedResidualCachePageable requires NestedResidualGpuJoinResidualCache"
    }
    if (-not $ForceOpenRouter -or $ReapMaskFile -or $AllowEmbeddedBakeMask) {
        throw "Nested residual all-layer storage requires full/open router and no mask"
    }
}
if ($NestedResidualGpuCache) {
    if (-not $NestedResidualSidecar -or -not $GpuResidentRoutes -or
        -not $SplitFused -or
        ($NestedResidualCacheExperts -lt 1 -and -not $NestedResidualCachePageable)) {
        throw "NestedResidualGpuCache requires NestedResidualSidecar, GpuResidentRoutes, SplitFused, and NestedResidualCacheExperts >= 1"
    }
}
if ($NestedResidualGpuJoin) {
    if (-not $NestedResidualSidecar -or -not $GpuResidentRoutes -or
        -not $SplitFused) {
        throw "NestedResidualGpuJoin requires NestedResidualSidecar, GpuResidentRoutes, and SplitFused"
    }
    if (-not $NestedResidualVerifyReconstruction) {
        if (-not $NestedResidualGpuJoinSafetyReceipt -or
            -not $ExpectedNestedResidualGpuJoinSafetyReceiptSHA256 -or
            -not $AllowNestedResidualBenchmarkSuite -or
            $GateKind -ne "benchmark") {
            throw "NestedResidualGpuJoin without runtime reconstruction verification requires a compatible hash-pinned safety receipt and an explicit outer benchmark suite"
        }
    }
}
if ($NestedResidualGpuJoinResidualCache) {
    if (-not $NestedResidualGpuJoin -or -not $NestedResidualGpuCache) {
        throw "NestedResidualGpuJoinResidualCache requires NestedResidualGpuJoin and NestedResidualGpuCache"
    }
}
if ($NestedResidualGpuJoinSafetyReceipt) {
    if (-not $NestedResidualGpuJoin -or $NestedResidualVerifyReconstruction -or
        -not $AllowNestedResidualBenchmarkSuite -or
        $GateKind -ne "benchmark") {
        throw "NestedResidualGpuJoinSafetyReceipt is only valid for an unverified GPU-join outer benchmark member"
    }
    if (-not (Test-Path -LiteralPath $NestedResidualGpuJoinSafetyReceipt `
            -PathType Leaf)) {
        throw "Nested residual GPU join safety receipt missing: $NestedResidualGpuJoinSafetyReceipt"
    }
    $NestedResidualGpuJoinSafetyReceipt =
        (Resolve-Path -LiteralPath $NestedResidualGpuJoinSafetyReceipt).Path
    $nestedResidualGpuJoinSafetyReceiptPathAtStart =
        $NestedResidualGpuJoinSafetyReceipt
} elseif ($ExpectedNestedResidualGpuJoinSafetyReceiptSHA256) {
    throw "ExpectedNestedResidualGpuJoinSafetyReceiptSHA256 requires NestedResidualGpuJoinSafetyReceipt"
}
if ($Q1_0ExpertSidecar) {
    if ($Q1_0LayerFirst -gt $Q1_0LayerLast) {
        throw "Q1_0LayerFirst must be less than or equal to Q1_0LayerLast"
    }
    if (-not $Q1_0SnapshotBacking -and
        ($GateKind -ne "structural-safety" -or $Repeats -ne 1 -or $Warmup)) {
        throw "Q1_0 runtime step3 requires GateKind=structural-safety, Repeats=1, and no warmup"
    }
    if ($Iq1SExpertSidecar) {
        throw "Q1_0 and IQ1_S expert sidecars must be measured separately"
    }
    if ($Q1_0SelectedLoad -and $NoSelectedLoad) {
        throw "Q1_0SelectedLoad is incompatible with NoSelectedLoad"
    }
    if ($Q1_0ResidentArena -and
        (-not $Q1_0SelectedLoad -or $DynamicArenaGiB -le 0.0)) {
        throw "Q1_0ResidentArena requires Q1_0ExpertSidecar, Q1_0SelectedLoad, structural-safety, Repeats=1, no warmup, and DynamicArenaGiB > 0"
    }
    if ($Q1_0Profile -and
        (-not $Q1_0SelectedLoad -or -not $Q1_0ResidentArena)) {
        throw "Q1_0Profile requires Q1_0SelectedLoad and Q1_0ResidentArena"
    }
    if ($ExpertRecoveryTrace) {
        if (-not $Q1_0SelectedLoad -or -not $Q1_0ResidentArena -or
            -not $Q1_0DualArena -or $Q1_0DualSparseCompanion -or
            -not $Q1_0MixedTrace) {
            throw "ExpertRecoveryTrace requires the G129 resident dual-arena mixed resolver and Q1_0MixedTrace"
        }
        if ($GateKind -ne "structural-safety" -or $Repeats -ne 1 -or $Warmup) {
            throw "ExpertRecoveryTrace requires one structural-safety request and no warmup"
        }
        if (-not $ForceOpenRouter -or -not $ComposePrefillMassOpenRouter -or
            $ReapMaskFile -or $AllowEmbeddedBakeMask) {
            throw "ExpertRecoveryTrace requires authoritative full/open routing with no static or embedded mask"
        }
        if ($ExpertRecoveryTraceLayer -lt $Q1_0LayerFirst -or
            $ExpertRecoveryTraceLayer -gt $Q1_0LayerLast) {
            throw "ExpertRecoveryTrace target layer is outside the verified Q1_0 sidecar range"
        }
        if (-not $ExpectedModelSHA256 -or
            -not $ExpectedQ1_0ExpertSidecarSHA256 -or
            $ExpectedQ1_0ExpertSidecarBytes -eq 0) {
            throw "ExpertRecoveryTrace requires exact model and Q1_0 sidecar provenance"
        }
    }
    if ($Q1_0DualArena -and -not $Q1_0ResidentArena) {
        throw "Q1_0DualArena requires Q1_0ResidentArena"
    }
    if ($Q1_0DualSparseCompanion -and
        (-not $Q1_0ResidentArena -or -not $Q1_0DualArena -or
         -not $Q1_0MixedColdOne -or -not $PrefillMassWrap -or
         -not $ComposePrefillMassTiering -or
         $Q1_0LayerFirst -ne 0 -or $Q1_0LayerLast -ne 42)) {
        throw "Q1_0DualSparseCompanion requires resident+dual+cold-one, PrefillMassWrap, ComposePrefillMassTiering, and Q1 layers 0..42 so the companion matches the complete prefill candidate mask"
    }
    if ($Q1_0MixedColdOne -and -not $Q1_0DualSparseCompanion) {
        throw "Q1_0MixedColdOne requires Q1_0DualSparseCompanion"
    }
    if ($Q1_0SnapshotBacking -and
        ($Q1_0ResidentArena -or $Q1_0DualArena -or
         -not $Q1_0SelectedLoad -or $DynamicArenaGiB -le 0.0 -or
         -not $PrefillMassWrap -or
         (-not $ComposePrefillMassTiering -and -not $Q1_0PureResident) -or
         $Q1_0LayerFirst -ne 0 -or $Q1_0LayerLast -ne 42 -or
         $ExpectedQ1_0SnapshotEntries -le 0 -or
         $ExpectedQ1_0ResidentEntries -ne 0 -or
         -not $ReuseVerifiedQ1_0Receipt -or
         -not $ExpectedModelSHA256)) {
        throw "Q1_0SnapshotBacking is exclusive and requires selected load, DynamicArenaGiB > 0, PrefillMassWrap, ComposePrefillMass or Q1_0PureResident, layers 0..42, ExpectedQ1_0SnapshotEntries > 0, and verified model/Q1 receipts"
    }
    if ($Q1_0PureResident -and
        (-not $Q1_0SnapshotBacking -or -not $Q1_0PageableOverflow -or
         $ComposePrefillMassTiering -or $PrefillVramSeedPerLayer -ne 0 -or
         $PrefillVramSeedTotal -ne 0 -or
         $PrefillVramSeedFloorPerLayer -ne 0 -or
         $ExpertCacheN -ne 0 -or $GpuResidentRoutes -or
         $ExpertTiering -ne "off")) {
        throw "Q1_0PureResident requires snapshot backing with pageable overflow and forbids composed tiering, VRAM seed, expert cache, GPU-resident IQ2 routes, and expert tiering"
    }
    if ($Q1_0PageableOverflow -and
        -not ($Q1_0SnapshotBacking -or
              ($Q1_0ResidentArena -and $Q1_0DualArena))) {
        throw "Q1_0PageableOverflow requires snapshot backing or resident dual-arena mode"
    }
    if (-not $Q1_0SnapshotBacking -and $ExpectedQ1_0SnapshotEntries -ne 0) {
        throw "ExpectedQ1_0SnapshotEntries requires Q1_0SnapshotBacking"
    }
    if ($ExpectedQ1_0ResidentEntries -ne 0 -and
        (-not $Q1_0ResidentArena -or $Q1_0SnapshotBacking)) {
        throw "ExpectedQ1_0ResidentEntries requires non-snapshot Q1_0ResidentArena"
    }
    if (-not (Test-Path -LiteralPath $Q1_0ExpertSidecar -PathType Leaf)) {
        throw "Q1_0 sidecar missing: $Q1_0ExpertSidecar"
    }
    if (-not $AllowBenchmarkVerifiedReceiptReuse) {
        $q1_0SidecarLockStream = [IO.File]::Open(
            $Q1_0ExpertSidecar, [IO.FileMode]::Open,
            [IO.FileAccess]::Read, [IO.FileShare]::Read)
    }
    $q1_0SidecarInfoAtStart = Get-Item -LiteralPath $Q1_0ExpertSidecar
    if ($ExpectedQ1_0ExpertSidecarBytes -ne 0 -and
        [UInt64]$q1_0SidecarInfoAtStart.Length -ne
            $ExpectedQ1_0ExpertSidecarBytes) {
        throw "Q1_0 sidecar byte count differs from expected provenance"
    }
    $Q1_0ExpertSidecar = $q1_0SidecarInfoAtStart.FullName
    if ($ReuseVerifiedQ1_0Receipt) {
        $q1_0SidecarReceiptPath = "$Q1_0ExpertSidecar.receipt.json"
        if (-not (Test-Path -LiteralPath $q1_0SidecarReceiptPath -PathType Leaf)) {
            throw "Q1_0 sidecar verified receipt missing: $q1_0SidecarReceiptPath"
        }
        $q1_0SidecarReceiptSnapshot = Read-G7ReceiptSnapshot `
            -Path $q1_0SidecarReceiptPath -Kind "Q1_0 sidecar"
        $q1_0SidecarReceiptAtStart = $q1_0SidecarReceiptSnapshot.receipt
        $q1_0SidecarReceiptHashAtStart = $q1_0SidecarReceiptSnapshot.sha256
        Assert-G7VerifiedFileReceipt -Receipt $q1_0SidecarReceiptAtStart `
            -Info $q1_0SidecarInfoAtStart `
            -ExpectedSHA256 $ExpectedQ1_0ExpertSidecarSHA256 `
            -Kind "Q1_0 sidecar"
        if ($Q1_0SnapshotBacking) {
            foreach ($requiredProperty in @(
                    "source_model_sha256", "layer_first", "layer_last",
                    "tensor_type", "derived_from_iq2", "conversion_source",
                    "manifest_path", "manifest_sha256")) {
                if ($null -eq $q1_0SidecarReceiptAtStart.PSObject.Properties[$requiredProperty]) {
                    throw "Q1_0 snapshot receipt missing provenance field: $requiredProperty"
                }
            }
            if ([string]$q1_0SidecarReceiptAtStart.source_model_sha256 -ine
                    $ExpectedModelSHA256 -or
                [int]$q1_0SidecarReceiptAtStart.layer_first -ne 0 -or
                [int]$q1_0SidecarReceiptAtStart.layer_last -ne 42 -or
                [string]$q1_0SidecarReceiptAtStart.tensor_type -ne "Q1_0" -or
                -not [bool]$q1_0SidecarReceiptAtStart.derived_from_iq2 -or
                [string]::IsNullOrWhiteSpace(
                    [string]$q1_0SidecarReceiptAtStart.conversion_source) -or
                [string]$q1_0SidecarReceiptAtStart.manifest_sha256 -notmatch
                    '^[0-9a-fA-F]{64}$') {
                throw "Q1_0 snapshot receipt provenance does not match the authoritative model/layer/type contract"
            }
            $snapshotManifestPath = [string]$q1_0SidecarReceiptAtStart.manifest_path
            if (-not (Test-Path -LiteralPath $snapshotManifestPath -PathType Leaf)) {
                throw "Q1_0 snapshot manifest from verified receipt is missing"
            }
            $observedManifestSHA256 = (Get-FileHash -LiteralPath $snapshotManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($observedManifestSHA256 -ine
                    [string]$q1_0SidecarReceiptAtStart.manifest_sha256) {
                throw "Q1_0 snapshot manifest hash differs from verified receipt"
            }
        }
    }
}
if ($Iq1SExpertSidecar) {
    if ($Iq1SLayerFirst -gt $Iq1SLayerLast) {
        throw "Iq1SLayerFirst must be less than or equal to Iq1SLayerLast"
    }
    if (-not (Test-Path -LiteralPath $Iq1SExpertSidecar -PathType Leaf)) {
        throw "IQ1_S sidecar missing: $Iq1SExpertSidecar"
    }
    if (-not $ExpectedIq1SExpertSidecarSHA256 -or
        $ExpectedIq1SExpertSidecarSHA256 -notmatch '^[0-9a-fA-F]{64}$' -or
        $ExpectedIq1SExpertSidecarBytes -eq 0) {
        throw "IQ1_S sidecar requires expected SHA256 and byte count provenance"
    }
    if (-not $ReuseVerifiedSuiteReceipt) {
        $iq1SSidecarLockStream = [IO.File]::Open(
            $Iq1SExpertSidecar, [IO.FileMode]::Open,
            [IO.FileAccess]::Read, [IO.FileShare]::Read)
    }
    $iq1SSidecarInfoAtStart = Get-Item -LiteralPath $Iq1SExpertSidecar
    if ([UInt64]$iq1SSidecarInfoAtStart.Length -ne $ExpectedIq1SExpertSidecarBytes) {
        throw "IQ1_S sidecar byte count differs from verified provenance"
    }
    $Iq1SExpertSidecar = $iq1SSidecarInfoAtStart.FullName
    $iq1SSidecarReceiptPath = "$Iq1SExpertSidecar.receipt.json"
    if (-not (Test-Path -LiteralPath $iq1SSidecarReceiptPath -PathType Leaf)) {
        throw "IQ1_S sidecar verified receipt missing: $iq1SSidecarReceiptPath"
    }
    $iq1SSidecarReceiptSnapshot = Read-G7ReceiptSnapshot `
        -Path $iq1SSidecarReceiptPath -Kind "IQ1_S sidecar"
    $iq1SSidecarReceiptAtStart = $iq1SSidecarReceiptSnapshot.receipt
    $iq1SSidecarReceiptHashAtStart = $iq1SSidecarReceiptSnapshot.sha256
    if ($iq1SSidecarReceiptAtStart.status -ne "verified" -or
        [IO.Path]::GetFullPath([string]$iq1SSidecarReceiptAtStart.path) -ne $Iq1SExpertSidecar -or
        [UInt64]$iq1SSidecarReceiptAtStart.bytes -ne $ExpectedIq1SExpertSidecarBytes -or
        [string]$iq1SSidecarReceiptAtStart.sha256 -ine $ExpectedIq1SExpertSidecarSHA256 -or
        [string]::IsNullOrWhiteSpace([string]$iq1SSidecarReceiptAtStart.source) -or
        [string]::IsNullOrWhiteSpace([string]$iq1SSidecarReceiptAtStart.quantization_layout) -or
        [string]::IsNullOrWhiteSpace([string]$iq1SSidecarReceiptAtStart.imatrix_provenance)) {
        throw "IQ1_S sidecar receipt does not match requested path/bytes/SHA-256"
    }
    if ($ReuseVerifiedIq1SReceipt -or $ReuseVerifiedSuiteReceipt) {
        Assert-G7VerifiedFileReceipt -Receipt $iq1SSidecarReceiptAtStart `
            -Info $iq1SSidecarInfoAtStart `
            -ExpectedSHA256 $ExpectedIq1SExpertSidecarSHA256 `
            -Kind "IQ1_S sidecar"
    }
}
if (($ReuseVerifiedIq1SReceipt -or $ReuseVerifiedSuiteReceipt) -and
    -not $Iq1SExpertSidecar) {
    throw "ReuseVerifiedIq1SReceipt requires Iq1SExpertSidecar"
}
if ($Iq1SMixedColdOne -and -not $Iq1SExpertSidecar) {
    throw "Iq1SMixedColdOne requires Iq1SExpertSidecar"
}
if ($Iq1SMixedGpuPlan -and -not $Iq1SMixedColdOne) {
    throw "Iq1SMixedGpuPlan requires Iq1SMixedColdOne"
}
if ($Iq1Promotion) {
    if (-not $Iq1SExpertSidecar) { throw "Iq1Promotion requires Iq1SExpertSidecar" }
    if (-not $Iq1SMixedColdOne) { throw "Iq1Promotion requires Iq1SMixedColdOne" }
    if (-not $Iq1SMixedGpuPlan) { throw "Iq1Promotion requires Iq1SMixedGpuPlan" }
    if (-not $ComposePrefillMassTiering) { throw "Iq1Promotion requires ComposePrefillMassTiering" }
    if ($ExpertTiering -ne "enforce") { throw "Iq1Promotion requires ExpertTiering enforce" }
}
if ($Q1_0ArenaGB -gt 0.0 -and -not $Q1_0ExpertSidecar) {
    throw "Q1_0ArenaGB requires Q1_0ExpertSidecar"
}
if ($Q1_0DynamicPromotion) {
    if (-not $Q1_0ExpertSidecar) { throw "Q1_0DynamicPromotion requires Q1_0ExpertSidecar" }
    if (-not $Q1_0DualArena) { throw "Q1_0DynamicPromotion requires Q1_0DualArena" }
    if ($Q1_0SnapshotBacking) { throw "Q1_0DynamicPromotion forbids Q1_0SnapshotBacking" }
    if (-not $Q1_0PageableOverflow) { throw "Q1_0DynamicPromotion requires Q1_0PageableOverflow" }
    if ($Iq1Promotion) { throw "Q1_0DynamicPromotion is isolated from legacy Iq1Promotion" }
    if ($Q1_0ArenaGB -le 0.0) { throw "Q1_0DynamicPromotion requires Q1_0ArenaGB > 0" }
    if (-not $ComposePrefillMassTiering) { throw "Q1_0DynamicPromotion requires ComposePrefillMassTiering" }
    if ($ExpertTiering -ne "enforce") { throw "Q1_0DynamicPromotion requires ExpertTiering enforce" }
}
if ($Q1_0PromotionSsdWrap) {
    if (-not $Q1_0DynamicPromotion) {
        throw "Q1_0PromotionSsdWrap requires Q1_0DynamicPromotion"
    }
    if ([math]::Abs($DynamicArenaGiB - 5.5) -gt 0.000000001) {
        throw "Q1_0PromotionSsdWrap requires the unchanged 5.5 GiB exact-IQ2 host budget"
    }
    if (-not $Q1_0DualArena -or $Q1_0SnapshotBacking) {
        throw "Q1_0PromotionSsdWrap requires full/open dual arena without snapshot backing"
    }
} elseif ([math]::Abs($Q1_0Iq2PinnedGiB - 1.5) -gt 0.000000001) {
    throw "Q1_0Iq2PinnedGiB is configurable only with Q1_0PromotionSsdWrap"
}
$quantPromotionRequested = [bool]($Iq1Promotion -or $Q1_0DynamicPromotion)
if (($Q1_0PromotionWindowCalls -eq 0) -ne ($Q1_0PromotionWindowBudget -eq 0)) {
    throw "Q1_0PromotionWindowCalls and Q1_0PromotionWindowBudget must both be zero or both be greater than zero"
}
if (-not $Q1_0DynamicPromotion -and
    ($Q1_0PromotionMinTouches -ne 1 -or
     $Q1_0PromotionMinWeight -ne 0.0 -or
     $Q1_0PromotionMinMass -ne 0.0 -or
     $Q1_0PromotionRequestBudget -ne 0 -or
     $Q1_0PromotionWindowCalls -ne 0 -or
     $Q1_0PromotionWindowBudget -ne 0 -or
     $Q1_0PromotionProbationSlots -ne 16)) {
    throw "Non-default Q1_0 promotion knobs require -Q1_0DynamicPromotion"
}
if (($Iq1PromotionWindowCalls -eq 0) -ne ($Iq1PromotionWindowBudget -eq 0)) {
    throw "Iq1PromotionWindowCalls and Iq1PromotionWindowBudget must both be zero or both be greater than zero"
}
if (-not $Iq1Promotion -and
    ($Iq1PromotionMinTouches -ne 1 -or
     $Iq1PromotionMinWeight -ne 0.0 -or
     $Iq1PromotionMinMass -ne 0.0 -or
     $Iq1PromotionRequestBudget -ne 0 -or
     $Iq1PromotionWindowCalls -ne 0 -or
     $Iq1PromotionWindowBudget -ne 0)) {
    throw "Non-default IQ1 promotion knobs require -Iq1Promotion"
}
if ($AllowBenchmarkVerifiedReceiptReuse) {
    $benchmarkVerifiedReceiptLockProofRequired = $true
    $modelLockProof = Test-G7SharingViolationProof -Path $model `
        -Kind "Model"
    $q1LockProof = if ($Q1_0ExpertSidecar) {
        Test-G7SharingViolationProof -Path $Q1_0ExpertSidecar `
            -Kind "Q1_0 sidecar"
    } else { $null }
    $iq1LockProof = if ($Iq1SExpertSidecar) {
        Test-G7SharingViolationProof -Path $Iq1SExpertSidecar `
            -Kind "IQ1_S sidecar"
    } else { $null }
    $benchmarkVerifiedReceiptLockProofObserved = [bool](
        [bool]$modelLockProof.sharing_violation_lock_proof -and
        ($null -eq $q1LockProof -or
         [bool]$q1LockProof.sharing_violation_lock_proof) -and
        ($null -eq $iq1LockProof -or
         [bool]$iq1LockProof.sharing_violation_lock_proof))
    $benchmarkVerifiedReceiptLockProof = [pscustomobject]@{
        required = $true
        observed = $benchmarkVerifiedReceiptLockProofObserved
        model = $modelLockProof
        q1_0_sidecar = $q1LockProof
        iq1_s_sidecar = $iq1LockProof
    }
    if (-not $benchmarkVerifiedReceiptLockProofObserved) {
        throw "Benchmark verified receipt reuse requires active parent-held deny-write/delete locks"
    }
}
if ($ReuseVerifiedSuiteReceipt -and
    ($GateKind -eq "benchmark" -or $AllowQualityVerifiedSuiteReceipt)) {
    $modelIq1SuiteLockProofRequired = $true
    $modelLockProof = Test-G7SharingViolationProof -Path $model `
        -Kind "Model"
    $sidecarLockProof = Test-G7SharingViolationProof `
        -Path $Iq1SExpertSidecar -Kind "IQ1_S sidecar"
    $modelIq1SuiteLockProofObserved = [bool](
        [bool]$modelLockProof.sharing_violation_lock_proof -and
        [bool]$sidecarLockProof.sharing_violation_lock_proof)
    $modelIq1SuiteLockProof = [pscustomobject]@{
        required = $true
        observed = $modelIq1SuiteLockProofObserved
        model = $modelLockProof
        iq1_s_sidecar = $sidecarLockProof
    }
    if (-not $modelIq1SuiteLockProofObserved) {
        if ($GateKind -eq "benchmark") {
            throw "Benchmark suite receipt reuse requires active parent-held deny-write/delete locks"
        }
        throw "Quality suite receipt reuse requires active parent-held deny-write/delete locks"
    }
}
if ($ComposePrefillMassOpenRouter) {
    if (-not $ComposePrefillMassTiering) { throw "ComposePrefillMassOpenRouter requires ComposePrefillMassTiering" }
    if (-not $PrefillMassWrap) { throw "ComposePrefillMassOpenRouter requires PrefillMassWrap" }
    if (-not $quantPromotionRequested -and $ComposePrefillMassReserveSlots -le 0) { throw "ComposePrefillMassOpenRouter requires quant promotion or ComposePrefillMassReserveSlots > 0" }
}
if ($ComposePrefillMassReserveSlots -gt 0 -and -not $ComposePrefillMassOpenRouter) {
    throw "ComposePrefillMassReserveSlots requires ComposePrefillMassOpenRouter"
}
$promotionProbationSlotsExpected = if ($Q1_0DynamicPromotion) {
    $Q1_0PromotionProbationSlots
} else {
    $Iq1PromotionProbationSlots
}
$promotionMinTouchesExpected = if ($Q1_0DynamicPromotion) {
    $Q1_0PromotionMinTouches
} else {
    $Iq1PromotionMinTouches
}
$promotionMinWeightExpected = if ($Q1_0DynamicPromotion) {
    $Q1_0PromotionMinWeight
} else {
    $Iq1PromotionMinWeight
}
$promotionMinMassExpected = if ($Q1_0DynamicPromotion) {
    $Q1_0PromotionMinMass
} else {
    $Iq1PromotionMinMass
}
$promotionRequestBudgetExpected = if ($Q1_0DynamicPromotion) {
    $Q1_0PromotionRequestBudget
} else {
    $Iq1PromotionRequestBudget
}
$promotionWindowCallsExpected = if ($Q1_0DynamicPromotion) {
    $Q1_0PromotionWindowCalls
} else {
    $Iq1PromotionWindowCalls
}
$promotionWindowBudgetExpected = if ($Q1_0DynamicPromotion) {
    $Q1_0PromotionWindowBudget
} else {
    $Iq1PromotionWindowBudget
}
if ($Iq1SRamCacheGiB -gt 0.0 -and -not $Iq1SExpertSidecar) {
    throw "Iq1SRamCacheGiB requires Iq1SExpertSidecar"
}
if ($Iq1SRamCachePageable -and $Iq1SRamCacheGiB -le 0.0) {
    throw "Iq1SRamCachePageable requires Iq1SRamCacheGiB > 0"
}
if ($Iq1SRamCachePreloadAll -and -not $Iq1SRamCachePageable) {
    throw "Iq1SRamCachePreloadAll requires Iq1SRamCachePageable"
}
if ($Iq1SRamCachePageable -and -not $Iq1SRamCachePreloadAll) {
    throw "Iq1SRamCachePageable currently requires Iq1SRamCachePreloadAll"
}
if ($Iq1SRamCachePreloadAll -and
    [math]::Abs($Iq1SRamCacheGiB - 46.875) -gt 0.0005) {
    throw "Iq1SRamCachePreloadAll requires exactly 46.875 GiB (10240 routed experts)"
}
if ($Iq1SProfile -and -not $Iq1SExpertSidecar) {
    throw "Iq1SProfile requires Iq1SExpertSidecar"
}
if ($Iq1SNoMainSync -and -not $Iq1SMixedColdOne) {
    throw "Iq1SNoMainSync requires Iq1SMixedColdOne"
}
if ($Iq1SPackedH2D -and -not $Iq1SMixedColdOne) {
    throw "Iq1SPackedH2D requires Iq1SMixedColdOne"
}
if ($Iq1SVramCachePerLayer -gt 0 -and
    (-not $Iq1SMixedColdOne -or $Iq1SRamCacheGiB -le 0.0)) {
    throw "Iq1SVramCachePerLayer requires Iq1SMixedColdOne and Iq1SRamCacheGiB > 0"
}
if ($Iq1SVramCachePerLayer -gt 0 -and $Iq1SPackedH2D) {
    throw "Iq1SVramCachePerLayer and Iq1SPackedH2D are mutually exclusive"
}
if (-not $ExpertRecoveryTrace -and $ExpertRecoveryTraceOutputPath) {
    throw "ExpertRecoveryTraceOutputPath requires ExpertRecoveryTrace"
}
$outdir = Join-Path $PSScriptRoot "g7_runs"
New-Item -ItemType Directory -Force -Path $outdir | Out-Null
$expertRecoveryTraceRoot = [IO.Path]::GetFullPath($outdir)
$expertRecoveryTracePrefix = if ($ExpertRecoveryTraceOutputPath) {
    [IO.Path]::GetFullPath($ExpertRecoveryTraceOutputPath)
} else {
    Join-Path $expertRecoveryTraceRoot (
        "g7_" + $Tag + "_expert_recovery")
}
$expertRecoveryTracePaths = Get-G7ExpertRecoveryConfinedPaths `
    -RootPath $expertRecoveryTraceRoot `
    -OutputPrefix $expertRecoveryTracePrefix
if ($ExpertRecoveryTrace) {
    foreach ($tracePath in @(
            $expertRecoveryTracePaths.binary,
            $expertRecoveryTracePaths.jsonl,
            $expertRecoveryTracePaths.manifest,
            $expertRecoveryTracePaths.binary_partial,
            $expertRecoveryTracePaths.jsonl_partial,
            $expertRecoveryTracePaths.manifest_partial)) {
        if (Test-Path -LiteralPath $tracePath) {
            throw "Expert recovery output already exists: $tracePath"
        }
    }
}
$processIsolationLog = Join-Path $outdir ("g7_" + $Tag + "_process_isolation_preflight.json")
$systemQuiescenceLog = Join-Path $outdir ("g7_" + $Tag + "_system_quiescence_preflight.json")
$measurementMutexName = "Local\DS4_G7_MEASUREMENT_LOCK"
$measurementMutex = New-Object System.Threading.Mutex($false, $measurementMutexName)
$measurementLockAcquired = $false
try {
    $measurementLockAcquired = $measurementMutex.WaitOne(0)
} catch [System.Threading.AbandonedMutexException] {
    $measurementLockAcquired = $true
}
if (-not $measurementLockAcquired) {
    [pscustomobject]@{
        schema = "g7_process_isolation_preflight_v2"
        checked_utc = (Get-Date).ToUniversalTime().ToString("o")
        mutex_name = $measurementMutexName
        mutex_acquired = $false
        current_harness_pid = $PID
        gate_kind = $GateKind
        conflict_count = $null
        conflicts = @()
        blocked_maintenance_process_names = @("Defrag.exe")
        maintenance_conflict_count = $null
        maintenance_conflicts = @()
        ready_to_launch = $false
        refusal_reason = "measurement-lock-owned"
    } | ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath $processIsolationLog -Encoding UTF8
    $measurementMutex.Dispose()
    throw "Process isolation preflight refused launch: another G7 harness owns the measurement lock"
}
try {
$stderrLog = Join-Path $outdir ("g7_" + $Tag + "_stderr.log")
$stdoutLog = Join-Path $outdir ("g7_" + $Tag + "_stdout.log")
$memoryPreflightLog = Join-Path $outdir ("g7_" + $Tag + "_memory_preflight.json")
$runtimeTelemetryLog = Join-Path $outdir ("g7_" + $Tag + "_runtime_telemetry.jsonl")
$failurePath = Join-Path $outdir ("g7_" + $Tag + "_failure.json")
$rawOutputsPath = Join-Path $outdir ("g7_" + $Tag + "_raw_outputs.json")
$resultPath = Join-Path $outdir ("g7_" + $Tag + "_result.json")
function Write-G7MeasurementFailure {
    param(
        [Parameter(Mandatory=$true)][string]$Reason,
        [object]$Exception = $null,
        [object]$AbortSample = $null,
        [object[]]$Evidence = @()
    )

    if ([string]::IsNullOrWhiteSpace($failurePath)) { return }
    if (Test-Path -LiteralPath $failurePath -PathType Leaf) { return }
    $message = if ($Exception) { [string]$Exception } else { "" }
    [pscustomobject]@{
        schema = "g7_measurement_failure_v1"
        tag = $Tag
        reason = $Reason
        message = $message
        head = $headAtStart
        executable_sha256 = $exeHashAtStart
        harness_sha256 = $harnessHashAtStart
        runtime_monitor_harness_sha256 = $runtimeMonitorHashAtStart
        stderr_path = $stderrLog
        stdout_path = $stdoutLog
        raw_outputs_path = $rawOutputsPath
        result_path = $resultPath
        runtime_telemetry_path = $runtimeTelemetryLog
        expert_recovery_trace_requested = [bool]$ExpertRecoveryTrace
        expert_recovery_trace_output_prefix = $expertRecoveryTracePrefix
        expert_recovery_trace_manifest_path =
            $expertRecoveryTracePaths.manifest
        http_ok = $httpOk
        completed_results = @($results).Count
        expected_results = $Repeats
        server_exit_code = $serverExitCode
        runtime_failure_evidence = @($Evidence)
        contamination_abort_sample = $AbortSample
    } | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath $failurePath -Encoding UTF8
}
if (Test-Path $stderrLog) { Remove-Item $stderrLog -Force }
if (Test-Path $stdoutLog) { Remove-Item $stdoutLog -Force }
if (Test-Path $memoryPreflightLog) { Remove-Item $memoryPreflightLog -Force }
if (Test-Path $processIsolationLog) { Remove-Item $processIsolationLog -Force }
if (Test-Path $systemQuiescenceLog) { Remove-Item $systemQuiescenceLog -Force }
if (Test-Path $runtimeTelemetryLog) { Remove-Item $runtimeTelemetryLog -Force }
if (Test-Path $failurePath) { Remove-Item $failurePath -Force }
if (Test-Path $rawOutputsPath) { Remove-Item $rawOutputsPath -Force }
if (Test-Path $resultPath) { Remove-Item $resultPath -Force }

try {
    $processSnapshot = Get-G7ProcessSnapshot
    $processesAtPreflight = @($processSnapshot.processes)
} catch {
    throw ("Process isolation preflight could not enumerate processes: " + $_.Exception.Message)
}
$processById = @{}
foreach ($candidateProcess in $processesAtPreflight) {
    $processById[[int]$candidateProcess.ProcessId] = $candidateProcess
}
$ancestorProcessIds = @()
$seenAncestorIds = @{}
$cursorPid = $PID
while ($processById.ContainsKey([int]$cursorPid)) {
    $parentPid = [int]$processById[[int]$cursorPid].ParentProcessId
    if ($parentPid -le 0 -or $seenAncestorIds.ContainsKey($parentPid)) { break }
    $ancestorProcessIds += $parentPid
    $seenAncestorIds[$parentPid] = $true
    $cursorPid = $parentPid
}
$processConflicts = @($processesAtPreflight | Where-Object {
    $_.ProcessId -ne $PID -and
    $ancestorProcessIds -notcontains [int]$_.ProcessId -and
    ($_.Name -ieq "ds4_server.exe" -or
     ($_.Name -match "^(powershell|pwsh)(\.exe)?$" -and
      $_.CommandLine -match "g7_(measure|runtime_monitor)\.ps1"))
} | ForEach-Object {
    [pscustomobject]@{
        pid = [int]$_.ProcessId
        parent_pid = [int]$_.ParentProcessId
        name = [string]$_.Name
        executable_path = [string]$_.ExecutablePath
        command_line = [string]$_.CommandLine
        created_utc = ""
        conflict_type = "ds4-or-harness"
        refusal_reason = "conflicting-ds4-or-g7-process"
    }
})
$maintenanceProcessConflicts = @(Get-G7MaintenanceProcessConflicts `
    -Processes $processesAtPreflight -GateKind $GateKind)
$allProcessConflicts = @($processConflicts) + @($maintenanceProcessConflicts)
$processIsolationPreflight = [pscustomobject]@{
    schema = "g7_process_isolation_preflight_v2"
    checked_utc = (Get-Date).ToUniversalTime().ToString("o")
    mutex_name = $measurementMutexName
    mutex_acquired = $measurementLockAcquired
    current_harness_pid = $PID
    gate_kind = $GateKind
    process_enumeration_method = [string]$processSnapshot.method
    process_command_line_available =
        [bool]$processSnapshot.command_line_available
    ancestor_process_ids = $ancestorProcessIds
    conflict_count = $allProcessConflicts.Count
    conflicts = $allProcessConflicts
    blocked_maintenance_process_names = @("Defrag.exe")
    maintenance_conflict_count = $maintenanceProcessConflicts.Count
    maintenance_conflicts = $maintenanceProcessConflicts
    ready_to_launch = ($allProcessConflicts.Count -eq 0)
}
$processIsolationPreflight | ConvertTo-Json -Depth 5 |
    Set-Content -LiteralPath $processIsolationLog -Encoding UTF8
if ($allProcessConflicts.Count -ne 0) {
    $conflictText = @($allProcessConflicts | ForEach-Object {
        $_.name + " pid=" + $_.pid
    }) -join ", "
    throw ("Process isolation preflight refused launch: " + $conflictText)
}

$env:CUDA_PATH = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.6"
$env:PATH = "$env:CUDA_PATH\bin;" + $env:PATH
$inheritedDs4Environment = [ordered]@{}
$_processEnvironment = [System.Environment]::GetEnvironmentVariables()
foreach ($name in @($_processEnvironment.Keys | ForEach-Object { [string]$_ } | Where-Object { $_ -like "DS4_*" } | Sort-Object)) {
    $inheritedDs4Environment[$name] = [string]$_processEnvironment[$name]
    [System.Environment]::SetEnvironmentVariable($name, $null, [System.EnvironmentVariableTarget]::Process)
}
if ($ExpectedModelSHA256) {
    $env:DS4_MODEL_SHA256 = $ExpectedModelSHA256.ToLowerInvariant()
    if (Test-Path -LiteralPath $model -PathType Leaf) {
        $env:DS4_MODEL_BYTES = [string][UInt64](Get-Item -LiteralPath $model).Length
    } else {
        Remove-Item Env:\DS4_MODEL_BYTES -ErrorAction SilentlyContinue
    }
} else {
    Remove-Item Env:\DS4_MODEL_SHA256 -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_MODEL_BYTES -ErrorAction SilentlyContinue
}
$env:DS4_CUDA_STREAM_FROM_RAM_MASKED_BUDGET_GB = "$BudgetGB"
$env:DS4_CUDA_STREAM_RESERVE_MB = "$ReserveMB"
if ($Q1_0ExpertSidecar) {
    $env:DS4_Q1_0_EXPERT_SIDECAR = $Q1_0ExpertSidecar
    $env:DS4_Q1_0_EXPERT_SIDECAR_SHA256 =
        $ExpectedQ1_0ExpertSidecarSHA256.ToLowerInvariant()
    $env:DS4_Q1_0_EXPERT_SIDECAR_BYTES =
        [string]$ExpectedQ1_0ExpertSidecarBytes
    $env:DS4_Q1_0_LAYER_FIRST = [string]$Q1_0LayerFirst
    $env:DS4_Q1_0_LAYER_LAST = [string]$Q1_0LayerLast
    if ($Q1_0SelectedLoad) {
        $env:DS4_Q1_0_SELECTED_LOAD = "1"
    } else {
        Remove-Item Env:\DS4_Q1_0_SELECTED_LOAD -ErrorAction SilentlyContinue
    }
    if ($Q1_0ResidentArena) {
        $env:DS4_Q1_0_RESIDENT_ARENA = "1"
    } else {
        Remove-Item Env:\DS4_Q1_0_RESIDENT_ARENA -ErrorAction SilentlyContinue
    }
    if ($Q1_0DualArena) {
        $env:DS4_Q1_0_DUAL_ARENA = "1"
    } else {
        Remove-Item Env:\DS4_Q1_0_DUAL_ARENA -ErrorAction SilentlyContinue
    }
    if ($Q1_0DualSparseCompanion) {
        $env:DS4_Q1_0_DUAL_SPARSE_COMPANION = "1"
    } else {
        Remove-Item Env:\DS4_Q1_0_DUAL_SPARSE_COMPANION -ErrorAction SilentlyContinue
    }
    if ($Q1_0MixedColdOne) {
        $env:DS4_Q1_0_MIXED_COLD_ONE = "1"
    } else {
        Remove-Item Env:\DS4_Q1_0_MIXED_COLD_ONE -ErrorAction SilentlyContinue
    }
    if ($Q1_0SnapshotBacking) {
        $env:DS4_Q1_0_SNAPSHOT_BACKING = "1"
    } else {
        Remove-Item Env:\DS4_Q1_0_SNAPSHOT_BACKING -ErrorAction SilentlyContinue
    }
    if ($Q1_0PageableOverflow) {
        $env:DS4_Q1_0_PAGEABLE_OVERFLOW = "1"
    } else {
        Remove-Item Env:\DS4_Q1_0_PAGEABLE_OVERFLOW -ErrorAction SilentlyContinue
    }
    if ($Q1_0ArenaGB -gt 0.0) {
        $env:DS4_Q1_0_DYNAMIC_ARENA_GB = $Q1_0ArenaGB.ToString(
            "0.###", [Globalization.CultureInfo]::InvariantCulture)
    } else {
        Remove-Item Env:\DS4_Q1_0_DYNAMIC_ARENA_GB -ErrorAction SilentlyContinue
    }
    if ($Q1_0DynamicPromotion) {
        $env:DS4_Q1_0_DYNAMIC_PROMOTION = "1"
    } else {
        Remove-Item Env:\DS4_Q1_0_DYNAMIC_PROMOTION -ErrorAction SilentlyContinue
    }
    if ($Q1_0Profile) {
        $env:DS4_Q1_0_PROFILE = "1"
    } else {
        Remove-Item Env:\DS4_Q1_0_PROFILE -ErrorAction SilentlyContinue
    }
    if ($Q1_0MixedTrace) {
        $env:DS4_Q1_0_MIXED_TRACE = "1"
    } else {
        Remove-Item Env:\DS4_Q1_0_MIXED_TRACE -ErrorAction SilentlyContinue
    }
} else {
    Remove-Item Env:\DS4_Q1_0_EXPERT_SIDECAR -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_Q1_0_EXPERT_SIDECAR_SHA256 -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_Q1_0_EXPERT_SIDECAR_BYTES -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_Q1_0_SELECTED_LOAD -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_Q1_0_RESIDENT_ARENA -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_Q1_0_DUAL_ARENA -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_Q1_0_DUAL_SPARSE_COMPANION -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_Q1_0_MIXED_COLD_ONE -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_Q1_0_SNAPSHOT_BACKING -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_Q1_0_PAGEABLE_OVERFLOW -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_Q1_0_DYNAMIC_ARENA_GB -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_Q1_0_DYNAMIC_PROMOTION -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_Q1_0_PROFILE -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_Q1_0_MIXED_TRACE -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_Q1_0_LAYER_FIRST -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_Q1_0_LAYER_LAST -ErrorAction SilentlyContinue
}
if ($NestedResidualSidecar) {
    $env:DS4_NESTED_RESIDUAL_SIDECAR = $NestedResidualSidecar
    $env:DS4_NESTED_RESIDUAL_EXACT = "1"
    $env:DS4_NESTED_RESIDUAL_EXPECTED_SOURCE_SHA256 =
        $ExpectedNestedResidualSourceSHA256.ToLowerInvariant()
    $env:DS4_NESTED_RESIDUAL_EXPECTED_PAYLOAD_SHA256 =
        $ExpectedNestedResidualPayloadSHA256.ToLowerInvariant()
    $env:DS4_CUDA_PREFILL_TIER_ROUTER = "open"
    if ($NestedResidualVerifyReconstruction) {
        $env:DS4_NESTED_RESIDUAL_VERIFY_RECONSTRUCTION = "1"
    } else {
        Remove-Item Env:\DS4_NESTED_RESIDUAL_VERIFY_RECONSTRUCTION -ErrorAction SilentlyContinue
    }
    if ($AllowNestedResidualBenchmarkSuite -and
        -not $NestedResidualVerifyReconstruction) {
        $env:DS4_NESTED_RESIDUAL_BENCHMARK_UNVERIFIED = "1"
    } else {
        Remove-Item Env:\DS4_NESTED_RESIDUAL_BENCHMARK_UNVERIFIED -ErrorAction SilentlyContinue
    }
    if ($NestedResidualProfile) {
        $env:DS4_NESTED_RESIDUAL_PROFILE = "1"
    } else {
        Remove-Item Env:\DS4_NESTED_RESIDUAL_PROFILE -ErrorAction SilentlyContinue
    }
    $env:DS4_NESTED_RESIDUAL_CACHE_EXPERTS =
        [string]$NestedResidualCacheExperts
    if ($NestedResidualPageableBase) {
        $env:DS4_NESTED_RESIDUAL_PAGEABLE_BASE = "1"
        $env:DS4_NESTED_RESIDUAL_BASE_PINNED_GIB =
            $NestedResidualBasePinnedGiB.ToString(
                [Globalization.CultureInfo]::InvariantCulture)
    } else {
        Remove-Item Env:\DS4_NESTED_RESIDUAL_PAGEABLE_BASE -ErrorAction SilentlyContinue
        Remove-Item Env:\DS4_NESTED_RESIDUAL_BASE_PINNED_GIB -ErrorAction SilentlyContinue
    }
    if ($NestedResidualCachePageable) {
        $env:DS4_NESTED_RESIDUAL_CACHE_PAGEABLE = "1"
    } else {
        Remove-Item Env:\DS4_NESTED_RESIDUAL_CACHE_PAGEABLE -ErrorAction SilentlyContinue
    }
    if ($NestedResidualGpuCache) {
        $env:DS4_NESTED_RESIDUAL_GPU_CACHE = "1"
    } else {
        Remove-Item Env:\DS4_NESTED_RESIDUAL_GPU_CACHE -ErrorAction SilentlyContinue
    }
    if ($NestedResidualGpuJoin) {
        $env:DS4_NESTED_RESIDUAL_GPU_JOIN = "1"
    } else {
        Remove-Item Env:\DS4_NESTED_RESIDUAL_GPU_JOIN -ErrorAction SilentlyContinue
    }
    if ($NestedResidualGpuJoinResidualCache) {
        $env:DS4_NESTED_RESIDUAL_GPU_JOIN_RESIDUAL_CACHE = "1"
    } else {
        Remove-Item Env:\DS4_NESTED_RESIDUAL_GPU_JOIN_RESIDUAL_CACHE -ErrorAction SilentlyContinue
    }
} else {
    Remove-Item Env:\DS4_NESTED_RESIDUAL_SIDECAR -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_NESTED_RESIDUAL_EXACT -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_NESTED_RESIDUAL_EXPECTED_SOURCE_SHA256 -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_NESTED_RESIDUAL_EXPECTED_PAYLOAD_SHA256 -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_NESTED_RESIDUAL_VERIFY_RECONSTRUCTION -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_NESTED_RESIDUAL_BENCHMARK_UNVERIFIED -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_NESTED_RESIDUAL_PROFILE -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_NESTED_RESIDUAL_CACHE_EXPERTS -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_NESTED_RESIDUAL_PAGEABLE_BASE -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_NESTED_RESIDUAL_BASE_PINNED_GIB -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_NESTED_RESIDUAL_CACHE_PAGEABLE -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_NESTED_RESIDUAL_GPU_CACHE -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_NESTED_RESIDUAL_GPU_JOIN -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_NESTED_RESIDUAL_GPU_JOIN_RESIDUAL_CACHE -ErrorAction SilentlyContinue
}
if ($Iq1SExpertSidecar) {
    $env:DS4_IQ1_S_EXPERT_SIDECAR = $Iq1SExpertSidecar
    $env:DS4_IQ1_S_LAYER_FIRST = [string]$Iq1SLayerFirst
    $env:DS4_IQ1_S_LAYER_LAST = [string]$Iq1SLayerLast
} else {
    Remove-Item Env:\DS4_IQ1_S_EXPERT_SIDECAR -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_IQ1_S_LAYER_FIRST -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_IQ1_S_LAYER_LAST -ErrorAction SilentlyContinue
}
if ($Iq1SMixedColdOne) {
    $env:DS4_IQ1_S_MIXED_COLD_K = "1"
} else {
    Remove-Item Env:\DS4_IQ1_S_MIXED_COLD_K -ErrorAction SilentlyContinue
}
if ($Iq1SMixedGpuPlan) {
    $env:DS4_IQ1_MIXED_GPU_PLAN = "1"
} else {
    Remove-Item Env:\DS4_IQ1_MIXED_GPU_PLAN -ErrorAction SilentlyContinue
}
if ($Q1_0DynamicPromotion) {
    $env:DS4_Q1_0_PROMOTION_PROBATION_SLOTS = "$Q1_0PromotionProbationSlots"
    $env:DS4_Q1_0_PROMOTION_MIN_TOUCHES = "$Q1_0PromotionMinTouches"
    $env:DS4_Q1_0_PROMOTION_MIN_WEIGHT =
        $Q1_0PromotionMinWeight.ToString("R", [Globalization.CultureInfo]::InvariantCulture)
    $env:DS4_Q1_0_PROMOTION_MIN_MASS =
        $Q1_0PromotionMinMass.ToString("R", [Globalization.CultureInfo]::InvariantCulture)
    $env:DS4_Q1_0_PROMOTION_REQUEST_BUDGET = "$Q1_0PromotionRequestBudget"
    $env:DS4_Q1_0_PROMOTION_WINDOW_CALLS = "$Q1_0PromotionWindowCalls"
    $env:DS4_Q1_0_PROMOTION_WINDOW_BUDGET = "$Q1_0PromotionWindowBudget"
} else {
    Remove-Item Env:\DS4_Q1_0_PROMOTION_PROBATION_SLOTS -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_Q1_0_PROMOTION_MIN_TOUCHES -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_Q1_0_PROMOTION_MIN_WEIGHT -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_Q1_0_PROMOTION_MIN_MASS -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_Q1_0_PROMOTION_REQUEST_BUDGET -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_Q1_0_PROMOTION_WINDOW_CALLS -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_Q1_0_PROMOTION_WINDOW_BUDGET -ErrorAction SilentlyContinue
}
if ($Q1_0PromotionSsdWrap) {
    $env:DS4_Q1_0_PROMOTION_SSD_WRAP = '1'
    $env:DS4_Q1_0_IQ2_PINNED_GIB = $Q1_0Iq2PinnedGiB.ToString(
        'R', [Globalization.CultureInfo]::InvariantCulture)
} else {
    Remove-Item Env:\DS4_Q1_0_PROMOTION_SSD_WRAP -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_Q1_0_IQ2_PINNED_GIB -ErrorAction SilentlyContinue
}
if ($Iq1Promotion -and -not $Q1_0DynamicPromotion) {
    $env:DS4_IQ1_PROMOTION_PROBATION_SLOTS = "$Iq1PromotionProbationSlots"
    $env:DS4_IQ1_PROMOTION_MIN_TOUCHES = "$Iq1PromotionMinTouches"
    $env:DS4_IQ1_PROMOTION_MIN_WEIGHT =
        $Iq1PromotionMinWeight.ToString("R", [Globalization.CultureInfo]::InvariantCulture)
    $env:DS4_IQ1_PROMOTION_MIN_MASS =
        $Iq1PromotionMinMass.ToString("R", [Globalization.CultureInfo]::InvariantCulture)
    $env:DS4_IQ1_PROMOTION_REQUEST_BUDGET = "$Iq1PromotionRequestBudget"
    $env:DS4_IQ1_PROMOTION_WINDOW_CALLS = "$Iq1PromotionWindowCalls"
    $env:DS4_IQ1_PROMOTION_WINDOW_BUDGET = "$Iq1PromotionWindowBudget"
} else {
    Remove-Item Env:\DS4_IQ1_PROMOTION_PROBATION_SLOTS -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_IQ1_PROMOTION_MIN_TOUCHES -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_IQ1_PROMOTION_MIN_WEIGHT -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_IQ1_PROMOTION_MIN_MASS -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_IQ1_PROMOTION_REQUEST_BUDGET -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_IQ1_PROMOTION_WINDOW_CALLS -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_IQ1_PROMOTION_WINDOW_BUDGET -ErrorAction SilentlyContinue
}
if ($Iq1SRamCacheGiB -gt 0.0) {
    $env:DS4_IQ1_S_RAM_CACHE_GB = $Iq1SRamCacheGiB.ToString(
        "0.###", [Globalization.CultureInfo]::InvariantCulture)
} else {
    Remove-Item Env:\DS4_IQ1_S_RAM_CACHE_GB -ErrorAction SilentlyContinue
}
if ($Iq1SRamCachePageable) {
    $env:DS4_IQ1_S_RAM_CACHE_PAGEABLE = "1"
} else {
    Remove-Item Env:\DS4_IQ1_S_RAM_CACHE_PAGEABLE -ErrorAction SilentlyContinue
}
if ($Iq1SRamCachePreloadAll) {
    $env:DS4_IQ1_S_RAM_CACHE_PRELOAD_ALL = "1"
} else {
    Remove-Item Env:\DS4_IQ1_S_RAM_CACHE_PRELOAD_ALL -ErrorAction SilentlyContinue
}
if ($Iq1SMixedDebug) {
    $env:DS4_IQ1_MIXED_DEBUG = "1"
} else {
    Remove-Item Env:\DS4_IQ1_MIXED_DEBUG -ErrorAction SilentlyContinue
}
if ($Iq1SProfile) {
    $env:DS4_IQ1_S_PROFILE = "1"
} else {
    Remove-Item Env:\DS4_IQ1_S_PROFILE -ErrorAction SilentlyContinue
}
if ($Iq1SNoMainSync) {
    $env:DS4_IQ1_MIXED_NO_MAIN_SYNC = "1"
} else {
    Remove-Item Env:\DS4_IQ1_MIXED_NO_MAIN_SYNC -ErrorAction SilentlyContinue
}
if ($Iq1SPackedH2D) {
    $env:DS4_IQ1_S_PACKED_H2D = "1"
} else {
    Remove-Item Env:\DS4_IQ1_S_PACKED_H2D -ErrorAction SilentlyContinue
}
if ($Iq1SVramCachePerLayer -gt 0) {
    $env:DS4_IQ1_S_VRAM_CACHE_PER_LAYER = "$Iq1SVramCachePerLayer"
} else {
    Remove-Item Env:\DS4_IQ1_S_VRAM_CACHE_PER_LAYER -ErrorAction SilentlyContinue
}
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
if ($DynamicArenaMinAvailableGiB -gt 0.0) {
    $env:DS4_CUDA_DYNAMIC_ARENA_MIN_AVAILABLE_GIB =
        $DynamicArenaMinAvailableGiB.ToString("0.###", [Globalization.CultureInfo]::InvariantCulture)
} else {
    Remove-Item Env:\DS4_CUDA_DYNAMIC_ARENA_MIN_AVAILABLE_GIB -ErrorAction SilentlyContinue
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
if ($ArenaWrapTrustWorkerChecksum) {
    $env:DS4_CUDA_ARENA_WRAP_TRUST_WORKER_CHECKSUM = "1"
} else {
    Remove-Item Env:\DS4_CUDA_ARENA_WRAP_TRUST_WORKER_CHECKSUM -ErrorAction SilentlyContinue
}
if ($ArenaWrapSourceParts) {
    $env:DS4_CUDA_ARENA_WRAP_SCHEDULE = "source-parts"
} else {
    Remove-Item Env:\DS4_CUDA_ARENA_WRAP_SCHEDULE -ErrorAction SilentlyContinue
}
if ($ArenaWrapSequentialFile) {
    $env:DS4_CUDA_ARENA_WRAP_SEQUENTIAL_FILE = "1"
    $env:DS4_CUDA_ARENA_WRAP_SEQUENTIAL_WORKERS = "$ArenaWrapSequentialWorkers"
} else {
    Remove-Item Env:\DS4_CUDA_ARENA_WRAP_SEQUENTIAL_FILE -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_CUDA_ARENA_WRAP_SEQUENTIAL_WORKERS -ErrorAction SilentlyContinue
}
if ($ArenaWrapFileQD -gt 1) {
    $env:DS4_CUDA_ARENA_WRAP_FILE_QD = "$ArenaWrapFileQD"
} else {
    Remove-Item Env:\DS4_CUDA_ARENA_WRAP_FILE_QD -ErrorAction SilentlyContinue
}
if ($ArenaWrapRandomFile) {
    $env:DS4_CUDA_ARENA_WRAP_RANDOM_FILE = "1"
} else {
    Remove-Item Env:\DS4_CUDA_ARENA_WRAP_RANDOM_FILE -ErrorAction SilentlyContinue
}
if ($ArenaWrapPartProfile) {
    $env:DS4_CUDA_ARENA_WRAP_PART_PROFILE = "1"
    $env:DS4_CUDA_ARENA_WRAP_SLOW_PART_MS =
        $ArenaWrapSlowPartMs.ToString("0.###", [Globalization.CultureInfo]::InvariantCulture)
} else {
    Remove-Item Env:\DS4_CUDA_ARENA_WRAP_PART_PROFILE -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_CUDA_ARENA_WRAP_SLOW_PART_MS -ErrorAction SilentlyContinue
}
if ($ArenaWrapLayoutProfile) {
    $env:DS4_CUDA_ARENA_WRAP_LAYOUT_PROFILE = "1"
} else {
    Remove-Item Env:\DS4_CUDA_ARENA_WRAP_LAYOUT_PROFILE -ErrorAction SilentlyContinue
}
if ($ArenaWrapTrimBetweenPhases) {
    $env:DS4_CUDA_ARENA_WRAP_TRIM_BETWEEN_PHASES = "1"
} else {
    Remove-Item Env:\DS4_CUDA_ARENA_WRAP_TRIM_BETWEEN_PHASES -ErrorAction SilentlyContinue
}
if ($ArenaWrapUnlockSourceRanges) {
    $env:DS4_CUDA_ARENA_WRAP_UNLOCK_SOURCE_RANGES = "1"
} else {
    Remove-Item Env:\DS4_CUDA_ARENA_WRAP_UNLOCK_SOURCE_RANGES -ErrorAction SilentlyContinue
}
if ($ArenaWrapUnlockWaveGiB -gt 0.0) {
    $env:DS4_CUDA_ARENA_WRAP_UNLOCK_WAVE_GIB =
        $ArenaWrapUnlockWaveGiB.ToString("0.######", [Globalization.CultureInfo]::InvariantCulture)
} else {
    Remove-Item Env:\DS4_CUDA_ARENA_WRAP_UNLOCK_WAVE_GIB -ErrorAction SilentlyContinue
}
if ($ComposePrefillMassTiering) {
    $env:DS4_CUDA_PREFILL_TIER_COMPOSE = "1"
} else {
    Remove-Item Env:\DS4_CUDA_PREFILL_TIER_COMPOSE -ErrorAction SilentlyContinue
}
if ($ComposePrefillMassOpenRouter -or $ForceOpenRouter -or
    $NestedResidualSidecar) {
    $env:DS4_CUDA_PREFILL_TIER_ROUTER = "open"
} else {
    Remove-Item Env:\DS4_CUDA_PREFILL_TIER_ROUTER -ErrorAction SilentlyContinue
}
if ($ComposePrefillMassReserveSlots -gt 0) {
    $env:DS4_CUDA_PREFILL_TIER_RESERVE_SLOTS = "$ComposePrefillMassReserveSlots"
} else {
    Remove-Item Env:\DS4_CUDA_PREFILL_TIER_RESERVE_SLOTS -ErrorAction SilentlyContinue
}
if ($PrefillMassLayerFullEvery -gt 0) {
    $env:DS4_CUDA_PREFILL_MASS_LAYER_FULL_EVERY = "$PrefillMassLayerFullEvery"
    $env:DS4_CUDA_PREFILL_MASS_LAYER_FULL_PHASE = "$PrefillMassLayerFullPhase"
} else {
    Remove-Item Env:\DS4_CUDA_PREFILL_MASS_LAYER_FULL_EVERY -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_CUDA_PREFILL_MASS_LAYER_FULL_PHASE -ErrorAction SilentlyContinue
}
if ($PrefillVramSeedPerLayer -gt 0) {
    $env:DS4_CUDA_PREFILL_VRAM_SEED_PER_LAYER = "$PrefillVramSeedPerLayer"
} else {
    Remove-Item Env:\DS4_CUDA_PREFILL_VRAM_SEED_PER_LAYER -ErrorAction SilentlyContinue
}
if ($PrefillVramSeedTotal -gt 0) {
    $env:DS4_CUDA_PREFILL_VRAM_SEED_TOTAL = "$PrefillVramSeedTotal"
} else {
    Remove-Item Env:\DS4_CUDA_PREFILL_VRAM_SEED_TOTAL -ErrorAction SilentlyContinue
}
if ($PrefillVramSeedFloorPerLayer -gt 0) {
    $env:DS4_CUDA_PREFILL_VRAM_SEED_FLOOR_PER_LAYER =
        "$PrefillVramSeedFloorPerLayer"
} else {
    Remove-Item Env:\DS4_CUDA_PREFILL_VRAM_SEED_FLOOR_PER_LAYER -ErrorAction SilentlyContinue
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
    Remove-Item Env:\DS4_EXPERT_TIER_ADAPTIVE_BUDGET -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_EXPERT_TIER_ADAPTIVE_BUDGET_MIN -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_EXPERT_TIER_ADAPTIVE_BUDGET_MAX -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_EXPERT_TIER_ADAPTIVE_BUDGET_STEP -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_EXPERT_TIER_ADAPTIVE_PRESSURE_THRESHOLD -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_EXPERT_TIER_MIN_FREQUENCY -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_EXPERT_TIER_HYSTERESIS -ErrorAction SilentlyContinue
} else {
    $env:DS4_EXPERT_TIERING = $ExpertTiering
    $env:DS4_EXPERT_TIER_POLICY = $ExpertTierPolicy
    $env:DS4_EXPERT_TIER_CLOCK_CALLS = "$ExpertTierClockCalls"
    $env:DS4_EXPERT_TIER_REPLACEMENT_BUDGET = "$ExpertTierReplacementBudget"
    if ($ExpertTierAdaptiveBudget) {
        $env:DS4_EXPERT_TIER_ADAPTIVE_BUDGET = "1"
        $env:DS4_EXPERT_TIER_ADAPTIVE_BUDGET_MIN = "$ExpertTierAdaptiveMin"
        $env:DS4_EXPERT_TIER_ADAPTIVE_BUDGET_MAX = "$ExpertTierAdaptiveMax"
        $env:DS4_EXPERT_TIER_ADAPTIVE_BUDGET_STEP = "$ExpertTierAdaptiveStep"
        $env:DS4_EXPERT_TIER_ADAPTIVE_PRESSURE_THRESHOLD = "$ExpertTierAdaptivePressureThreshold"
    } else {
        Remove-Item Env:\DS4_EXPERT_TIER_ADAPTIVE_BUDGET -ErrorAction SilentlyContinue
        Remove-Item Env:\DS4_EXPERT_TIER_ADAPTIVE_BUDGET_MIN -ErrorAction SilentlyContinue
        Remove-Item Env:\DS4_EXPERT_TIER_ADAPTIVE_BUDGET_MAX -ErrorAction SilentlyContinue
        Remove-Item Env:\DS4_EXPERT_TIER_ADAPTIVE_BUDGET_STEP -ErrorAction SilentlyContinue
        Remove-Item Env:\DS4_EXPERT_TIER_ADAPTIVE_PRESSURE_THRESHOLD -ErrorAction SilentlyContinue
    }
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
if ($RouteNoDefaultSync) {
    $env:DS4_CUDA_MOE_ROUTE_NO_DEFAULT_SYNC = "1"
} else {
    Remove-Item Env:\DS4_CUDA_MOE_ROUTE_NO_DEFAULT_SYNC -ErrorAction SilentlyContinue
}
if ($RoutePackedCopy) {
    $env:DS4_CUDA_MOE_ROUTE_PACKED_COPY = "1"
} else {
    Remove-Item Env:\DS4_CUDA_MOE_ROUTE_PACKED_COPY -ErrorAction SilentlyContinue
}
if ($RequestPhaseTrace) {
    $env:DS4_REQUEST_PHASE_TRACE = "1"
} else {
    Remove-Item Env:\DS4_REQUEST_PHASE_TRACE -ErrorAction SilentlyContinue
}
if ($SplitHitMiss) {
    $env:DS4_CUDA_MOE_SPLIT_HIT_MISS = "1"
} else {
    Remove-Item Env:\DS4_CUDA_MOE_SPLIT_HIT_MISS -ErrorAction SilentlyContinue
}
if ($SplitFused) {
    $env:DS4_CUDA_MOE_SPLIT_FUSED = "1"
} else {
    Remove-Item Env:\DS4_CUDA_MOE_SPLIT_FUSED -ErrorAction SilentlyContinue
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
$requestCountExpected = if ($Warmup) { $Repeats + 1 } else { $Repeats }
$env:DS4_BENCH_EXIT_AFTER_REQUESTS = "$requestCountExpected"
if ($ComposePrefillMassTiering) {
    if (-not $PrefillMassWrap) { throw "ComposePrefillMassTiering requires PrefillMassWrap" }
    if ($DynamicArenaGiB -le 0.0) { throw "ComposePrefillMassTiering requires DynamicArenaGiB > 0" }
    if ($ExpertTiering -ne "enforce") { throw "ComposePrefillMassTiering requires ExpertTiering enforce" }
    if ($ExpertTierPolicy -ne "mass-lfru") { throw "ComposePrefillMassTiering requires ExpertTierPolicy mass-lfru" }
    if ($ExpertCacheN -le 0) { throw "ComposePrefillMassTiering requires ExpertCacheN > 0" }
    if (-not $GpuResidentRoutes) { throw "ComposePrefillMassTiering requires GpuResidentRoutes" }
    if (-not $DisableQ8F16Cache -or $Q8F16CacheMB -ne 0) { throw "ComposePrefillMassTiering requires Q8-F16 cache disabled" }
    if ($PrefillMassObserve -or $ReapMassObserve -or $ReapMassWrap) { throw "ComposePrefillMassTiering must be isolated from observe-only prefill and REAP mass" }
    if ($DynamicArenaObservedWindow -gt 0 -or $DynamicArenaGrowInterval -gt 0 -or $DynamicArenaCarry -ne "default") { throw "ComposePrefillMassTiering must be isolated from dynamic arena observer/grow/carry" }
}
if ($PrefillMassLayerFullEvery -gt 0) {
    if (-not $ComposePrefillMassTiering -or -not $PrefillMassWrap) {
        throw "PrefillMassLayerFullEvery requires ComposePrefillMassTiering and PrefillMassWrap"
    }
    if ($PrefillMassLayerFullPhase -ge $PrefillMassLayerFullEvery) {
        throw "PrefillMassLayerFullPhase must be lower than PrefillMassLayerFullEvery"
    }
} elseif ($PrefillMassLayerFullPhase -ne 0) {
    throw "PrefillMassLayerFullPhase requires PrefillMassLayerFullEvery > 0"
}
if ($PrefillVramSeedPerLayer -gt 0) {
    if (-not $ComposePrefillMassTiering) { throw "PrefillVramSeedPerLayer requires ComposePrefillMassTiering" }
    if (-not $PrefillMassWrap) { throw "PrefillVramSeedPerLayer requires PrefillMassWrap" }
    if ($ExpertTiering -ne "enforce" -or $ExpertTierPolicy -ne "mass-lfru") { throw "PrefillVramSeedPerLayer requires enforce mass-lfru tiering" }
    if (-not $GpuResidentRoutes) { throw "PrefillVramSeedPerLayer requires GpuResidentRoutes" }
    $prefillVramSeedSlots = 40 * $PrefillVramSeedPerLayer
    if ($prefillVramSeedSlots -gt $ExpertCacheN) {
        throw "PrefillVramSeedPerLayer requires at least $prefillVramSeedSlots expert-cache slots"
    }
}
if ($PrefillVramSeedTotal -gt 0) {
    if ($PrefillVramSeedPerLayer -gt 0) {
        throw "PrefillVramSeedTotal is mutually exclusive with PrefillVramSeedPerLayer"
    }
    if (-not $ComposePrefillMassTiering) { throw "PrefillVramSeedTotal requires ComposePrefillMassTiering" }
    if (-not $PrefillMassWrap) { throw "PrefillVramSeedTotal requires PrefillMassWrap" }
    if ($ExpertTiering -ne "enforce" -or $ExpertTierPolicy -ne "mass-lfru") { throw "PrefillVramSeedTotal requires enforce mass-lfru tiering" }
    if (-not $GpuResidentRoutes) { throw "PrefillVramSeedTotal requires GpuResidentRoutes" }
    if ($PrefillVramSeedFloorPerLayer * 40 -gt $PrefillVramSeedTotal) {
        throw "PrefillVramSeedFloorPerLayer exceeds the global seed budget"
    }
    if ($PrefillVramSeedTotal -gt $ExpertCacheN) {
        throw "PrefillVramSeedTotal requires at least $PrefillVramSeedTotal expert-cache slots"
    }
} elseif ($PrefillVramSeedFloorPerLayer -ne 0) {
    throw "PrefillVramSeedFloorPerLayer requires PrefillVramSeedTotal"
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
    if ($ExpertTierAdaptiveBudget) {
        if ($ExpertTierPolicy -ne "mass-lfru") { throw "ExpertTierAdaptiveBudget requires ExpertTierPolicy mass-lfru" }
        if ($ExpertTierAdaptiveMin -gt $ExpertTierAdaptiveMax) { throw "ExpertTierAdaptiveMin must be <= ExpertTierAdaptiveMax" }
        if ($ExpertTierReplacementBudget -lt $ExpertTierAdaptiveMin -or
            $ExpertTierReplacementBudget -gt $ExpertTierAdaptiveMax) {
            throw "ExpertTierReplacementBudget must be within adaptive min/max"
        }
        if ($ExpertTierAdaptiveStep -gt ($ExpertTierAdaptiveMax - $ExpertTierAdaptiveMin + 1)) {
            throw "ExpertTierAdaptiveStep must fit within adaptive min/max"
        }
    }
} elseif ($ExpertTierAdaptiveBudget) {
    throw "ExpertTierAdaptiveBudget requires ExpertTiering"
}
if ($DynamicArenaObservedWindow -gt 0 -and $DynamicArenaGiB -le 0.0) { throw "DynamicArenaObservedWindow requires DynamicArenaGiB > 0" }
if ($DynamicArenaMinAvailableGiB -gt 0.0 -and $DynamicArenaGiB -le 0.0) { throw "DynamicArenaMinAvailableGiB requires DynamicArenaGiB > 0" }
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
if ($PrefillMassWrap -and -not $ComposePrefillMassTiering -and
    ($Warmup -or $Repeats -ne 1)) {
    throw "PrefillMassWrap without composed request-scoped masks requires one request and no warmup"
}
if ($ArenaWrapPartProfile -and -not $ArenaWrapSourceParts) { throw "ArenaWrapPartProfile requires ArenaWrapSourceParts" }
if ($ArenaWrapUnlockSourceRanges -and (-not $ArenaWrapSourceParts -or -not $ArenaWrapTrustWorkerChecksum)) { throw "ArenaWrapUnlockSourceRanges requires ArenaWrapSourceParts and ArenaWrapTrustWorkerChecksum" }
if ($ArenaWrapUnlockSourceRanges -and ($ArenaWrapTrimBetweenPhases -or $ArenaWrapSequentialFile -or $ArenaWrapRandomFile)) { throw "ArenaWrapUnlockSourceRanges must be isolated from ArenaWrapTrimBetweenPhases and file source modes" }
if ($ArenaWrapUnlockWaveGiB -gt 0.0 -and -not $ArenaWrapUnlockSourceRanges) { throw "ArenaWrapUnlockWaveGiB requires ArenaWrapUnlockSourceRanges" }
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
if ($Iq1SExpertSidecar -and
    ($NoSelectedLoad -or $SplitHitMiss -or
     $DirectCacheHits -or $MixedDirectCache -or $SpexPrefetchK -gt 0 -or
     (-not $Iq1SMixedColdOne -and
      ($ExpertCacheN -gt 0 -or $ExpertTiering -ne "off" -or
       $DynamicArenaGiB -gt 0.0 -or $GpuResidentRoutes)))) {
    throw "IQ1_S sidecar composition is unsupported; standalone requires cache/tiering/arena/resident routes off, while mixed 5+1 still excludes selected-load bypass, split-hit-miss/direct-cache, and SPEX prefetch"
}
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
    if ($Q1_0DualSparseCompanion) {
        # Q1_0 is exactly half the routed-expert bytes of the IQ2 primary
        # snapshot. Reserve both snapshots plus 2 GiB before committing RAM.
        $effectiveMinimumAvailableGiB = [math]::Max(
            $effectiveMinimumAvailableGiB,
            ($DynamicArenaGiB * 1.5) + 2.0)
    }
    if ($nestedResidualAllLayerStorageRequested) {
        $effectiveMinimumAvailableGiB = [math]::Max(
            $effectiveMinimumAvailableGiB,
            $nestedResidualExpectedHostAllocationGiB + 4.0)
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
if ($nestedResidualGpuJoinSafetyReceiptPathAtStart) {
    $nestedResidualGpuJoinSafetyReceiptLockStream = [IO.File]::Open(
        $nestedResidualGpuJoinSafetyReceiptPathAtStart,
        [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $safetyReceiptSnapshot = Read-G7ReceiptSnapshot `
        -Path $nestedResidualGpuJoinSafetyReceiptPathAtStart `
        -Kind "Nested residual GPU join safety"
    $nestedResidualGpuJoinSafetyReceiptAtStart =
        $safetyReceiptSnapshot.receipt
    $nestedResidualGpuJoinSafetyReceiptHashAtStart =
        $safetyReceiptSnapshot.sha256
    if ($nestedResidualGpuJoinSafetyReceiptHashAtStart -ine
        $ExpectedNestedResidualGpuJoinSafetyReceiptSHA256) {
        throw "Nested residual GPU join safety receipt SHA-256 mismatch"
    }
    $nestedResidualGpuJoinSafetyResultPathAtStart =
        [IO.Path]::GetFullPath(
            [string]$nestedResidualGpuJoinSafetyReceiptAtStart.result_path)
    if (-not (Test-Path -LiteralPath `
            $nestedResidualGpuJoinSafetyResultPathAtStart -PathType Leaf)) {
        throw "Nested residual GPU join safety result is missing"
    }
    $nestedResidualGpuJoinSafetyResultLockStream = [IO.File]::Open(
        $nestedResidualGpuJoinSafetyResultPathAtStart,
        [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $safetyResultSnapshot = Read-G7ReceiptSnapshot `
        -Path $nestedResidualGpuJoinSafetyResultPathAtStart `
        -Kind "Nested residual GPU join safety result"
    $nestedResidualGpuJoinSafetyResultAtStart = $safetyResultSnapshot.receipt
    $nestedResidualGpuJoinSafetyResultHashAtStart =
        $safetyResultSnapshot.sha256
}
$spexHashAtStart = if ($SpexDryRun) { (Get-FileHash -Algorithm SHA256 -LiteralPath $SpexFile).Hash.ToLowerInvariant() } else { "" }
if ($ExpectedSpexSHA256 -and $spexHashAtStart -ine $ExpectedSpexSHA256) {
    throw "SPEX provenance failed: expected $($ExpectedSpexSHA256.ToLowerInvariant()), observed $spexHashAtStart"
}
$modelLockStream = if ($ExpectedModelSHA256 -and
    -not $ReuseVerifiedSuiteReceipt -and
    -not $AllowBenchmarkVerifiedReceiptReuse) {
    [IO.File]::Open(
        $model, [IO.FileMode]::Open,
        [IO.FileAccess]::Read, [IO.FileShare]::Read)
} else { $null }
$modelInfoAtStart = Get-Item -LiteralPath $model
$model = $modelInfoAtStart.FullName
if ($ReuseVerifiedModelReceipt -or $ReuseVerifiedSuiteReceipt) {
    $modelReceiptPath = "$model.receipt.json"
    if (-not (Test-Path -LiteralPath $modelReceiptPath -PathType Leaf)) {
        throw "Model verified receipt missing: $modelReceiptPath"
    }
    $modelReceiptSnapshot = Read-G7ReceiptSnapshot `
        -Path $modelReceiptPath -Kind "Model"
    $modelReceiptAtStart = $modelReceiptSnapshot.receipt
    $modelReceiptHashAtStart = $modelReceiptSnapshot.sha256
    Assert-G7VerifiedFileReceipt -Receipt $modelReceiptAtStart `
        -Info $modelInfoAtStart -ExpectedSHA256 $ExpectedModelSHA256 `
        -Kind "Model"
}
if ($ReuseVerifiedSuiteReceipt) {
    $modelIq1SuiteReceiptPathAtStart =
        [IO.Path]::GetFullPath($ModelIq1SuiteReceiptPath)
    if (-not (Test-Path -LiteralPath $modelIq1SuiteReceiptPathAtStart `
            -PathType Leaf)) {
        throw "Model/IQ1 suite receipt missing: $modelIq1SuiteReceiptPathAtStart"
    }
    $suiteReceiptSnapshot = Read-G7ReceiptSnapshot `
        -Path $modelIq1SuiteReceiptPathAtStart -Kind "Model/IQ1 suite"
    $modelIq1SuiteReceiptAtStart = $suiteReceiptSnapshot.receipt
    $modelIq1SuiteReceiptHashAtStart = $suiteReceiptSnapshot.sha256
    $modelIq1SuiteReceiptSchemaAtStart =
        [string]$modelIq1SuiteReceiptAtStart.schema
    if ($modelIq1SuiteReceiptHashAtStart -ine
        $ExpectedModelIq1SuiteReceiptSHA256) {
        throw "Model/IQ1 suite receipt SHA-256 mismatch"
    }
    if ([string]$modelIq1SuiteReceiptAtStart.schema -ne
            "g7_model_iq1_suite_receipt_v1" -or
        [string]$modelIq1SuiteReceiptAtStart.status -ne "verified" -or
        [string]$modelIq1SuiteReceiptAtStart.purpose -ne
            "model_iq1_provenance_reuse" -or
        [string]$modelIq1SuiteReceiptAtStart.hash_method -ne
            "locked_stream_sha256" -or
        [bool]$modelIq1SuiteReceiptAtStart.full_hash_verified -ne $true) {
        throw "Model/IQ1 suite receipt schema/status/purpose mismatch"
    }
    $modelIq1SuiteFullHashVerified = $true
    Assert-G7SuiteChildBinding -Child $modelIq1SuiteReceiptAtStart.model `
        -ExpectedReceiptPath $modelReceiptPath `
        -ObservedReceiptSHA256 $modelReceiptHashAtStart `
        -Info $modelInfoAtStart `
        -ExpectedFileSHA256 $ExpectedModelSHA256 `
        -ExpectedBytes ([UInt64]$modelInfoAtStart.Length) `
        -Kind "Model"
    Assert-G7SuiteChildBinding `
        -Child $modelIq1SuiteReceiptAtStart.iq1_s_sidecar `
        -ExpectedReceiptPath $iq1SSidecarReceiptPath `
        -ObservedReceiptSHA256 $iq1SSidecarReceiptHashAtStart `
        -Info $iq1SSidecarInfoAtStart `
        -ExpectedFileSHA256 $ExpectedIq1SExpertSidecarSHA256 `
        -ExpectedBytes $ExpectedIq1SExpertSidecarBytes `
        -Kind "IQ1_S sidecar"
    $modelIq1SuiteLockProofRequired = [bool](
        $GateKind -eq "benchmark" -or $AllowQualityVerifiedSuiteReceipt)
    if ($modelIq1SuiteLockProofRequired -and
        $null -eq $modelIq1SuiteLockProof) {
        $modelLockProof = Test-G7SharingViolationProof -Path $model `
            -Kind "Model"
        $sidecarLockProof = Test-G7SharingViolationProof `
            -Path $Iq1SExpertSidecar -Kind "IQ1_S sidecar"
        $modelIq1SuiteLockProofObserved = [bool](
            [bool]$modelLockProof.sharing_violation_lock_proof -and
            [bool]$sidecarLockProof.sharing_violation_lock_proof)
        $modelIq1SuiteLockProof = [pscustomobject]@{
            required = $true
            observed = $modelIq1SuiteLockProofObserved
            model = $modelLockProof
            iq1_s_sidecar = $sidecarLockProof
        }
        if (-not $modelIq1SuiteLockProofObserved) {
            if ($GateKind -eq "benchmark") {
                throw "Benchmark suite receipt reuse requires active parent-held deny-write/delete locks"
            }
            throw "Quality suite receipt reuse requires active parent-held deny-write/delete locks"
        }
    } elseif (-not $modelIq1SuiteLockProofRequired) {
        $modelIq1SuiteLockProof = [pscustomobject]@{
            required = $false
            observed = $false
            model = $null
            iq1_s_sidecar = $null
        }
    }
    $modelLockStream = [IO.File]::Open(
        $model, [IO.FileMode]::Open,
        [IO.FileAccess]::Read, [IO.FileShare]::Read)
    if ($null -eq $iq1SSidecarLockStream) {
        $iq1SSidecarLockStream = [IO.File]::Open(
            $Iq1SExpertSidecar, [IO.FileMode]::Open,
            [IO.FileAccess]::Read, [IO.FileShare]::Read)
    }
}
$modelHashMethod = if (-not $ExpectedModelSHA256) {
    "not_requested"
} elseif ($ReuseVerifiedSuiteReceipt) {
    "verified_suite_receipt_reuse"
} elseif ($ReuseVerifiedModelReceipt) {
    "verified_receipt_reuse"
} else {
    "full_file_sha256"
}
$modelHashAtStart = if (-not $ExpectedModelSHA256) {
    ""
} elseif ($ReuseVerifiedModelReceipt -or $ReuseVerifiedSuiteReceipt) {
    $ExpectedModelSHA256.ToLowerInvariant()
} else {
    (Get-FileHash -Algorithm SHA256 -LiteralPath $model).Hash.ToLowerInvariant()
}
if ($ExpectedModelSHA256 -and $modelHashAtStart -ine $ExpectedModelSHA256) {
    throw "Model provenance failed: expected $($ExpectedModelSHA256.ToLowerInvariant()), observed $modelHashAtStart"
}
$iq1SSidecarHashMethod = if (-not $iq1SSidecarInfoAtStart) {
    "not_applicable"
} elseif ($ReuseVerifiedSuiteReceipt) {
    "verified_suite_receipt_reuse"
} elseif ($ReuseVerifiedIq1SReceipt) {
    "verified_receipt_reuse"
} else {
    "full_file_sha256"
}
$iq1SSidecarHashAtStart = if (-not $iq1SSidecarInfoAtStart) {
    ""
} elseif ($ReuseVerifiedIq1SReceipt -or $ReuseVerifiedSuiteReceipt) {
    $ExpectedIq1SExpertSidecarSHA256.ToLowerInvariant()
} else {
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Iq1SExpertSidecar).Hash.ToLowerInvariant()
}
if ($iq1SSidecarInfoAtStart -and
    $iq1SSidecarHashAtStart -ine $ExpectedIq1SExpertSidecarSHA256) {
    throw "IQ1_S sidecar provenance failed: expected $($ExpectedIq1SExpertSidecarSHA256.ToLowerInvariant()), observed $iq1SSidecarHashAtStart"
}
$q1_0SidecarHashMethod = if (-not $q1_0SidecarInfoAtStart) {
    "not_applicable"
} elseif (-not $ExpectedQ1_0ExpertSidecarSHA256) {
    "not_requested"
} elseif ($ReuseVerifiedQ1_0Receipt) {
    "verified_receipt_reuse"
} else {
    "full_file_sha256"
}
$q1_0SidecarHashAtStart = if (-not $q1_0SidecarInfoAtStart -or
    -not $ExpectedQ1_0ExpertSidecarSHA256) {
    ""
} elseif ($ReuseVerifiedQ1_0Receipt) {
    $ExpectedQ1_0ExpertSidecarSHA256.ToLowerInvariant()
} else {
    (Get-FileHash -Algorithm SHA256 `
        -LiteralPath $Q1_0ExpertSidecar).Hash.ToLowerInvariant()
}
if ($ExpectedQ1_0ExpertSidecarSHA256 -and
    $q1_0SidecarHashAtStart -ine $ExpectedQ1_0ExpertSidecarSHA256) {
    throw "Q1_0 sidecar provenance failed: expected $($ExpectedQ1_0ExpertSidecarSHA256.ToLowerInvariant()), observed $q1_0SidecarHashAtStart"
}
$q1_0SidecarProvenanceVerified = [bool](
    $q1_0SidecarInfoAtStart -and $ExpectedQ1_0ExpertSidecarSHA256 -and
    $q1_0SidecarHashAtStart -ieq $ExpectedQ1_0ExpertSidecarSHA256 -and
    ($ExpectedQ1_0ExpertSidecarBytes -eq 0 -or
     [UInt64]$q1_0SidecarInfoAtStart.Length -eq
        $ExpectedQ1_0ExpertSidecarBytes) -and
    (-not $ReuseVerifiedQ1_0Receipt -or
     ($q1_0SidecarReceiptPath -and $q1_0SidecarReceiptHashAtStart)))
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
        $_ -notmatch '^(build[^/]*|g7_runs)/' -and
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
$expertRecoveryTraceEnvironmentNames = @(
    "DS4_EXPERT_RECOVERY_TRACE",
    "DS4_EXPERT_RECOVERY_TRACE_LAYER",
    "DS4_EXPERT_RECOVERY_TRACE_EXPERT",
    "DS4_EXPERT_RECOVERY_TRACE_MAX_SAMPLES",
    "DS4_EXPERT_RECOVERY_TRACE_MAX_BYTES",
    "DS4_EXPERT_RECOVERY_TRACE_ROOT",
    "DS4_EXPERT_RECOVERY_TRACE_OUTPUT_PREFIX",
    "DS4_EXPERT_RECOVERY_BUILD_MANIFEST_SHA256",
    "DS4_EXPERT_RECOVERY_BUILD_INPUT_FINGERPRINT_SHA256",
    "DS4_EXPERT_RECOVERY_EXECUTABLE_SHA256")
if ($ExpertRecoveryTrace) {
    if ($buildManifestHashAtStart -cnotmatch '^[0-9a-f]{64}$' -or
        [string]$buildManifest.input_fingerprint_sha256 -cnotmatch
            '^[0-9a-f]{64}$' -or
        $exeHashAtStart -cnotmatch '^[0-9a-f]{64}$') {
        throw "ExpertRecoveryTrace build provenance is incomplete"
    }
    $env:DS4_EXPERT_RECOVERY_TRACE = "1"
    $env:DS4_EXPERT_RECOVERY_TRACE_LAYER = [string]$ExpertRecoveryTraceLayer
    $env:DS4_EXPERT_RECOVERY_TRACE_EXPERT = [string]$ExpertRecoveryTraceExpert
    $env:DS4_EXPERT_RECOVERY_TRACE_MAX_SAMPLES =
        [string]$ExpertRecoveryTraceMaxSamples
    $env:DS4_EXPERT_RECOVERY_TRACE_MAX_BYTES =
        [string]$ExpertRecoveryTraceByteBudget
    $env:DS4_EXPERT_RECOVERY_TRACE_ROOT = $expertRecoveryTraceRoot
    $env:DS4_EXPERT_RECOVERY_TRACE_OUTPUT_PREFIX =
        $expertRecoveryTracePrefix
    $env:DS4_EXPERT_RECOVERY_BUILD_MANIFEST_SHA256 =
        $buildManifestHashAtStart
    $env:DS4_EXPERT_RECOVERY_BUILD_INPUT_FINGERPRINT_SHA256 =
        [string]$buildManifest.input_fingerprint_sha256
    $env:DS4_EXPERT_RECOVERY_EXECUTABLE_SHA256 = $exeHashAtStart
} else {
    foreach ($traceEnvironmentName in $expertRecoveryTraceEnvironmentNames) {
        [Environment]::SetEnvironmentVariable(
            $traceEnvironmentName, $null,
            [EnvironmentVariableTarget]::Process)
    }
}
if ($nestedResidualGpuJoinSafetyReceiptAtStart) {
    $safetyReceipt = $nestedResidualGpuJoinSafetyReceiptAtStart
    $safetyResult = $nestedResidualGpuJoinSafetyResultAtStart
    $safetyReceiptSchema = [string]$safetyReceipt.schema
    $safetyReceiptIsG125 = $safetyReceiptSchema -eq
        "ds4_g125_nested_gpu_join_safety_v1"
    $safetyReceiptIsG127 = $safetyReceiptSchema -eq
        "ds4_g127_nested_gpu_join_residual_cache_safety_v1"
    $safetyReceiptIsG128 = $safetyReceiptSchema -eq
        "ds4_g128_all_layer_nested_storage_safety_v1"
    $safetyReceiptHasResidualCache =
        $safetyReceiptIsG127 -or $safetyReceiptIsG128
    if ((-not $safetyReceiptIsG125 -and -not $safetyReceiptIsG127 -and
         -not $safetyReceiptIsG128) -or
        [string]$safetyReceipt.status -ne
            "pass_structural_n1_no_performance_or_quality_verdict" -or
        [string]$safetyReceipt.routing_contract -ne
            "full/open routing preserved; no REAP/static/closed masks" -or
        [string]$safetyReceipt.tag -ne [string]$safetyResult.tag -or
        [string]$safetyReceipt.exact_content_sha256 -ine
            $ExpectedContentSHA256 -or
        [string]$safetyReceipt.prompt_sha256 -ine $promptHash -or
        -not [bool]$safetyReceipt.gpu_join.requested -or
        -not [bool]$safetyReceipt.gpu_join.observed -or
        [UInt64]$safetyReceipt.gpu_join.calls -eq 0 -or
        [UInt64]$safetyReceipt.gpu_join.blocks -eq 0 -or
        [UInt64]$safetyReceipt.gpu_join.base_h2d_bytes -eq 0 -or
        [UInt64]$safetyReceipt.gpu_join.residual_h2d_bytes -eq 0 -or
        [UInt64]$safetyReceipt.gpu_join.native_h2d_bytes -ne 0 -or
        [UInt64]$safetyReceipt.gpu_join.verify_calls -eq 0 -or
        [UInt64]$safetyReceipt.gpu_join.verify_bytes -eq 0 -or
        [UInt64]$safetyReceipt.gpu_join.verify_mismatches -ne 0 -or
        [UInt64]$safetyReceipt.gpu_join.failures -ne 0 -or
        [UInt64]$safetyReceipt.gpu_join.cpu_reconstruct_calls -ne 0 -or
        -not [bool]$safetyReceipt.gpu_cache.requested -or
        -not [bool]$safetyReceipt.gpu_cache.observed -or
        [UInt64]$safetyReceipt.gpu_cache.route_calls -eq 0 -or
        [UInt64]$safetyReceipt.gpu_cache.hits -eq 0 -or
        [UInt64]$safetyReceipt.gpu_cache.misses -eq 0 -or
        [UInt64]$safetyReceipt.gpu_cache.host_fills -ne 0 -or
        [UInt64]$safetyReceipt.gpu_cache.host_bytes -ne 0 -or
        [UInt64]$safetyReceipt.gpu_cache.h2d_bytes -eq 0 -or
        [UInt64]$safetyReceipt.gpu_cache.failures -ne 0) {
        throw "Nested residual GPU join safety receipt contract mismatch"
    }
    if ($NestedResidualGpuJoinResidualCache -and
        -not $safetyReceiptHasResidualCache) {
        throw "Nested residual GPU join residual cache requires a G127 safety receipt or compatible G128 safety receipt"
    }
    if ($safetyReceiptHasResidualCache -and
        ([string]$safetyReceipt.result_sha256 -ine
            $nestedResidualGpuJoinSafetyResultHashAtStart -or
         [string]$safetyReceipt.claim_scope -ne
            "structural_safety_only_no_sota_no_quality_verdict" -or
         [int]$safetyReceipt.residual_cache.enabled -ne 1 -or
         [UInt64]$safetyReceipt.residual_cache.hits -eq 0 -or
         [UInt64]$safetyReceipt.residual_cache.misses -eq 0 -or
         [UInt64]$safetyReceipt.residual_cache.capacity -eq 0 -or
         [UInt64]$safetyReceipt.residual_cache.entries -gt
            [UInt64]$safetyReceipt.residual_cache.capacity -or
         [UInt64]$safetyReceipt.residual_cache.pread_bytes_avoided -eq 0 -or
         [UInt64]$safetyReceipt.residual_cache.cached_join_calls -eq 0 -or
         [UInt64]$safetyReceipt.residual_cache.invariant_failures -ne 0 -or
         -not [bool]$safetyReceipt.exactness.reconstruction_verify -or
         [UInt64]$safetyReceipt.exactness.verify_mismatches -ne 0 -or
         [UInt64]$safetyReceipt.exactness.nested_mismatches -ne 0 -or
         [UInt64]$safetyReceipt.exactness.nested_failures -ne 0 -or
         [UInt64]$safetyReceipt.exactness.gpu_join_failures -ne 0 -or
         [UInt64]$safetyReceipt.exactness.cpu_reconstruct_calls -ne 0 -or
         [UInt64]$safetyReceipt.exactness.native_h2d_bytes -ne 0 -or
         [UInt64]$safetyReceipt.exactness.selected_load_fallbacks -ne 0 -or
         [UInt64]$safetyReceipt.exactness.fallback_markers -ne 0 -or
         -not [bool]$safetyReceipt.machine_quiescence.ready_to_launch -or
         [bool]$safetyReceipt.machine_quiescence.skipped -or
         [int]$safetyReceipt.machine_quiescence.preflight_failures -ne 0 -or
         [int]$safetyReceipt.machine_quiescence.runtime_contamination_consecutive_peak -ne 0)) {
        if ($safetyReceiptIsG127) {
            throw "Nested residual GPU join G127 safety receipt contract mismatch"
        }
        throw "Nested residual GPU join G128 safety receipt contract mismatch"
    }
    if ($safetyReceiptIsG128) {
        $receiptSidecarPath = [IO.Path]::GetFullPath(
            [string]$safetyReceipt.sidecar.path)
        if ([string]$safetyReceipt.claim_scope -ne
                "structural_safety_only_no_sota_no_quality_verdict" -or
            $receiptSidecarPath -ine $nestedResidualInfoAtStart.FullName -or
            [UInt64]$safetyReceipt.sidecar.bytes -ne
                [UInt64]$nestedResidualInfoAtStart.Length -or
            [string]$safetyReceipt.sidecar.sha256 -ine
                $nestedResidualHashAtStart -or
            [string]$safetyReceipt.sidecar.source_sha256 -ine
                $ExpectedNestedResidualSourceSHA256 -or
            [string]$safetyReceipt.sidecar.payload_sha256 -ine
                $ExpectedNestedResidualPayloadSHA256 -or
            [int]$safetyReceipt.all_layer.first -ne 3 -or
            [int]$safetyReceipt.all_layer.last -ne 42 -or
            [int]$safetyReceipt.all_layer.count -ne 40 -or
            -not [bool]$safetyReceipt.base_storage.pageable_enabled -or
            [double]$safetyReceipt.base_storage.pinned_gib_requested -ne
                $NestedResidualBasePinnedGiB -or
            [double]$safetyReceipt.base_storage.dynamic_arena_gib -ne
                $DynamicArenaGiB -or
            [double]$safetyReceipt.base_storage.expected_base_host_gib -ne
                $nestedResidualExpectedBaseHostGiB -or
            [double]$safetyReceipt.base_storage.expected_residual_cache_host_gib -ne
                $nestedResidualExpectedResidualCacheHostGiB -or
            [double]$safetyReceipt.base_storage.expected_total_host_allocation_gib -ne
                $nestedResidualExpectedHostAllocationGiB -or
            [UInt64]$safetyReceipt.base_storage.pinned_entries -eq 0 -or
            [UInt64]$safetyReceipt.base_storage.pinned_bytes -eq 0 -or
            [UInt64]$safetyReceipt.base_storage.pinned_hits -eq 0 -or
            [UInt64]$safetyReceipt.base_storage.pinned_h2d_bytes -eq 0 -or
            [UInt64]$safetyReceipt.base_storage.pageable_entries -eq 0 -or
            [UInt64]$safetyReceipt.base_storage.pageable_bytes -eq 0 -or
            [UInt64]$safetyReceipt.base_storage.pageable_hits -eq 0 -or
            [UInt64]$safetyReceipt.base_storage.pageable_h2d_bytes -eq 0 -or
            [UInt64]$safetyReceipt.base_storage.invariant_failures -ne 0 -or
            -not [bool]$safetyReceipt.residual_cache.pageable_enabled -or
            [UInt64]$safetyReceipt.residual_cache.capacity -ne
                [UInt64]$NestedResidualCacheExperts -or
            [UInt64]$safetyReceipt.residual_cache.pinned_entries -ne 0 -or
            [UInt64]$safetyReceipt.residual_cache.pinned_bytes -ne 0 -or
            [UInt64]$safetyReceipt.residual_cache.pinned_hits -ne 0 -or
            [UInt64]$safetyReceipt.residual_cache.pinned_h2d_bytes -ne 0 -or
            [UInt64]$safetyReceipt.residual_cache.pageable_entries -eq 0 -or
            [UInt64]$safetyReceipt.residual_cache.pageable_bytes -eq 0 -or
            [UInt64]$safetyReceipt.residual_cache.pageable_hits -eq 0 -or
            [UInt64]$safetyReceipt.residual_cache.pageable_h2d_bytes -eq 0 -or
            [UInt64]$safetyReceipt.residual_cache.pageable_invariant_failures -ne 0 -or
            [UInt64]$safetyReceipt.residual_cache.partitioned -ne 1 -or
            [UInt64]$safetyReceipt.residual_cache.layer_slots_min -eq 0 -or
            [UInt64]$safetyReceipt.residual_cache.layer_slots_max -lt
                [UInt64]$safetyReceipt.residual_cache.layer_slots_min -or
            [UInt64]$safetyReceipt.residual_cache.layer_slots_max -gt
                [UInt64]$safetyReceipt.residual_cache.layer_slots_min +
                    [UInt64]1) {
            throw "Nested residual G128 all-layer safety receipt contract mismatch"
        }
    }
    $safetyActualHashes = @($safetyResult.results | ForEach-Object {
        [string]$_.content_sha256
    } | Sort-Object -Unique)
    if ([string]$safetyResult.gate_kind -ne "structural-safety" -or
        [bool]$safetyResult.quality_eligible -or
        [bool]$safetyResult.sota_eligible -or
        [int]$safetyResult.repeats -ne 1 -or
        [bool]$safetyResult.warmup -or
        [int]$safetyResult.server_exit_code -ne 0 -or
        -not [bool]$safetyResult.outputs_identical -or
        [string]$safetyResult.executable_sha256 -ine $exeHashAtStart -or
        [string]$safetyResult.build_manifest_sha256 -ine
            $buildManifestHashAtStart -or
        [string]$safetyResult.build_manifest_input_fingerprint_sha256 -ine
            [string]$buildManifest.input_fingerprint_sha256 -or
        [string]$safetyResult.model_sha256 -ine $modelHashAtStart -or
        [string]$safetyResult.prompt_sha256 -ine $promptHash -or
        [string]$safetyResult.expected_content_sha256 -ine
            $ExpectedContentSHA256 -or
        $safetyActualHashes.Count -ne 1 -or
        $safetyActualHashes[0] -ine $ExpectedContentSHA256 -or
        [string]$safetyResult.nested_residual_sidecar_sha256 -ine
            $nestedResidualHashAtStart -or
        [string]$safetyResult.nested_residual_expected_source_sha256 -ine
            $ExpectedNestedResidualSourceSHA256 -or
        [string]$safetyResult.nested_residual_expected_payload_sha256 -ine
            $ExpectedNestedResidualPayloadSHA256 -or
        -not [bool]$safetyResult.nested_residual_enabled -or
        -not [bool]$safetyResult.nested_residual_verify_reconstruction -or
        -not [bool]$safetyResult.nested_residual_gpu_cache_requested -or
        -not [bool]$safetyResult.nested_residual_gpu_join_requested -or
        -not [bool]$safetyResult.nested_residual_runtime_observed -or
        [UInt64]$safetyResult.nested_residual_mismatches -ne 0 -or
        [UInt64]$safetyResult.nested_residual_failures -ne 0 -or
        -not [bool]$safetyResult.nested_residual_vram_runtime_observed -or
        [UInt64]$safetyResult.nested_residual_vram_failures -ne 0 -or
        -not [bool]$safetyResult.nested_residual_gpu_join_observed -or
        [int]$safetyResult.nested_residual_gpu_join_requested_runtime -ne 1 -or
        [int]$safetyResult.nested_residual_gpu_join_observed_runtime -ne 1 -or
        [UInt64]$safetyResult.nested_residual_gpu_join_calls -eq 0 -or
        [UInt64]$safetyResult.nested_residual_gpu_join_native_h2d_bytes -ne 0 -or
        [UInt64]$safetyResult.nested_residual_gpu_join_verify_calls -eq 0 -or
        [UInt64]$safetyResult.nested_residual_gpu_join_verify_mismatches -ne 0 -or
        [UInt64]$safetyResult.nested_residual_gpu_join_failures -ne 0 -or
        [UInt64]$safetyResult.nested_residual_gpu_join_cpu_reconstruct_calls -ne 0 -or
        -not [bool]$safetyResult.compose_prefill_mass_open_router_requested -or
        [string]$safetyResult.reap_mask_file_requested -or
        [bool]$safetyResult.embedded_bake_mask_observed -or
        [bool]$safetyResult.spex_dry_run_requested -or
        [bool]$safetyResult.q1_0_sidecar_enabled -or
        [string]$safetyResult.iq1_s_sidecar -or
        [int]$safetyResult.context_requested -ne $Context -or
        [int]$safetyResult.requested_max_tokens -ne $MaxTokens -or
        [int]$safetyResult.nested_residual_cache_experts_requested -ne
            $NestedResidualCacheExperts -or
        [double]$safetyResult.dynamic_arena_gib_requested -ne
            $DynamicArenaGiB -or
        [int]$safetyResult.expert_cache_requested -ne $ExpertCacheN -or
        [double]$safetyResult.expert_cache_reserve_gb -ne
            $ExpertCacheReserveGB -or
        [int]$safetyResult.budget_gb -ne $BudgetGB -or
        [int]$safetyResult.reserve_mb -ne $ReserveMB -or
        -not [bool]$safetyResult.gpu_resident_routes_requested -or
        -not [bool]$safetyResult.split_fused_requested -or
        -not [bool]$safetyResult.route_no_default_sync_requested) {
        throw "Nested residual GPU join safety result no longer binds to this benchmark configuration"
    }
    if ($safetyReceiptHasResidualCache -and
        (-not [bool]$safetyResult.nested_residual_gpu_join_residual_cache_requested -or
         -not [bool]$safetyResult.nested_residual_gpu_join_residual_cache_observed -or
         [int]$safetyResult.nested_residual_gpu_join_residual_cache_enabled_runtime -ne 1 -or
         [UInt64]$safetyResult.nested_residual_gpu_join_residual_cache_hits -eq 0 -or
         [UInt64]$safetyResult.nested_residual_gpu_join_residual_cache_misses -eq 0 -or
         [UInt64]$safetyResult.nested_residual_gpu_join_residual_cache_capacity -eq 0 -or
         [UInt64]$safetyResult.nested_residual_gpu_join_residual_cache_entries -gt
            [UInt64]$safetyResult.nested_residual_gpu_join_residual_cache_capacity -or
         [UInt64]$safetyResult.nested_residual_gpu_join_residual_cache_pread_bytes_avoided -eq 0 -or
         [UInt64]$safetyResult.nested_residual_gpu_join_residual_cache_cached_join_calls -eq 0 -or
         [UInt64]$safetyResult.nested_residual_gpu_join_residual_cache_invariant_failures -ne 0 -or
         [UInt64]$safetyResult.moe_overlapped_io_fallbacks -ne 0)) {
        if ($safetyReceiptIsG127) {
            throw "Nested residual GPU join G127 safety result no longer binds to this benchmark"
        }
        throw "Nested residual GPU join G128 safety result no longer binds to this benchmark"
    }
    if ($safetyReceiptIsG128 -and
        (-not [bool]$safetyResult.nested_residual_pageable_base_requested -or
         -not [bool]$safetyResult.nested_residual_cache_pageable_requested -or
         [double]$safetyResult.nested_residual_base_pinned_gib_requested -ne
            $NestedResidualBasePinnedGiB -or
         [int]$safetyResult.nested_residual_all_layer_first_layer -ne 3 -or
         [int]$safetyResult.nested_residual_all_layer_last_layer -ne 42 -or
         [int]$safetyResult.nested_residual_all_layer_count -ne 40 -or
         [UInt64]$safetyResult.nested_residual_base_pinned_entries -eq 0 -or
         [UInt64]$safetyResult.nested_residual_base_pinned_bytes -eq 0 -or
         [UInt64]$safetyResult.nested_residual_base_pinned_hits -eq 0 -or
         [UInt64]$safetyResult.nested_residual_base_pinned_h2d_bytes -eq 0 -or
         [UInt64]$safetyResult.nested_residual_base_pageable_entries -eq 0 -or
         [UInt64]$safetyResult.nested_residual_base_pageable_bytes -eq 0 -or
         [UInt64]$safetyResult.nested_residual_base_pageable_hits -eq 0 -or
         [UInt64]$safetyResult.nested_residual_base_pageable_h2d_bytes -eq 0 -or
         [UInt64]$safetyResult.nested_residual_storage_invariant_failures -ne 0 -or
         [UInt64]$safetyResult.nested_residual_cache_pinned_entries -ne 0 -or
         [UInt64]$safetyResult.nested_residual_cache_pinned_bytes -ne 0 -or
         [UInt64]$safetyResult.nested_residual_cache_pinned_hits -ne 0 -or
         [UInt64]$safetyResult.nested_residual_cache_pinned_h2d_bytes -ne 0 -or
         [UInt64]$safetyResult.nested_residual_cache_pageable_entries -eq 0 -or
         [UInt64]$safetyResult.nested_residual_cache_pageable_bytes -eq 0 -or
         [UInt64]$safetyResult.nested_residual_cache_pageable_hits -eq 0 -or
         [UInt64]$safetyResult.nested_residual_cache_pageable_h2d_bytes -eq 0 -or
         [UInt64]$safetyResult.nested_residual_cache_pageable_invariant_failures -ne 0 -or
         [UInt64]$safetyResult.nested_residual_cache_layer_partitioned -ne 1 -or
         [UInt64]$safetyResult.nested_residual_cache_layer_slots_min -eq 0 -or
         [UInt64]$safetyResult.nested_residual_cache_layer_slots_max -lt
            [UInt64]$safetyResult.nested_residual_cache_layer_slots_min -or
         [UInt64]$safetyResult.nested_residual_cache_layer_slots_max -gt
            [UInt64]$safetyResult.nested_residual_cache_layer_slots_min +
                [UInt64]1)) {
        throw "Nested residual G128 all-layer safety result no longer binds to this benchmark"
    }
    $nestedResidualGpuJoinSafetyReceiptValidated = $true
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

$quiescenceCooldownStartedUtc = [DateTime]::UtcNow
$quiescenceCooldownStopwatch = [Diagnostics.Stopwatch]::StartNew()
if (-not $SkipSystemQuiescencePreflight -and $QuiescenceCooldownSec -gt 0) {
    Start-Sleep -Seconds $QuiescenceCooldownSec
}
$quiescenceCooldownStopwatch.Stop()

# Full-file provenance hashing can leave storage busy. Cool down before the
# quiescence probe, then fail closed if either model changed during the wait.
$modelInfoAfterCooldown = Get-Item -LiteralPath $model
if ($modelInfoAfterCooldown.Length -ne $modelInfoAtStart.Length -or
    $modelInfoAfterCooldown.LastWriteTimeUtc -ne $modelInfoAtStart.LastWriteTimeUtc) {
    throw "Model provenance changed during quiescence cooldown"
}
if ($iq1SSidecarInfoAtStart) {
    $iq1SSidecarInfoAfterCooldown = Get-Item -LiteralPath $Iq1SExpertSidecar
    if ($iq1SSidecarInfoAfterCooldown.Length -ne $iq1SSidecarInfoAtStart.Length -or
        $iq1SSidecarInfoAfterCooldown.LastWriteTimeUtc -ne
            $iq1SSidecarInfoAtStart.LastWriteTimeUtc) {
        throw "IQ1_S sidecar provenance changed during quiescence cooldown"
    }
}
if ($q1_0SidecarInfoAtStart) {
    $q1_0SidecarInfoAfterCooldown = Get-Item -LiteralPath $Q1_0ExpertSidecar
    if ($q1_0SidecarInfoAfterCooldown.Length -ne
            $q1_0SidecarInfoAtStart.Length -or
        $q1_0SidecarInfoAfterCooldown.LastWriteTimeUtc -ne
            $q1_0SidecarInfoAtStart.LastWriteTimeUtc) {
        throw "Q1_0 sidecar provenance changed during quiescence cooldown"
    }
}

$quiescenceThresholds = [pscustomobject][ordered]@{
    maximum_cpu_median_percent = $MaximumCpuMedianPercent
    maximum_disk_median_percent = $MaximumDiskMedianPercent
    maximum_disk_io_median_mib_per_second = $MaximumDiskIoMedianMiBps
    maximum_gpu_median_percent = $MaximumGpuMedianPercent
}
$quiescenceRows = @()
$quiescenceFailures = @()
$quiescenceStartedUtc = [DateTime]::UtcNow
$quiescenceStopwatch = [Diagnostics.Stopwatch]::StartNew()
$quiescenceCounterSource = "pdh-english"
$quiescenceCounterPaths = @(
    "\Processor(_Total)\% Processor Time",
    "\PhysicalDisk(_Total)\% Disk Time",
    "\PhysicalDisk(_Total)\Disk Read Bytes/sec",
    "\PhysicalDisk(_Total)\Disk Write Bytes/sec"
)
$quiescenceSampler = $null
$quiescencePdhInvalidDataRetries = 0
if (-not $SkipSystemQuiescencePreflight) {
    try {
        $quiescenceSampler = New-G7PdhEnglishSampler -Paths $quiescenceCounterPaths
        Start-Sleep -Milliseconds 250
        for ($sampleIndex = 0; $sampleIndex -lt $QuiescenceSamples; $sampleIndex++) {
            try {
                $quiescenceSampler.Collect()
                $cpuPercent = $quiescenceSampler.Read(
                    "\Processor(_Total)\% Processor Time")
                $diskPercent = $quiescenceSampler.Read(
                    "\PhysicalDisk(_Total)\% Disk Time")
                $diskReadBytesPerSec = $quiescenceSampler.Read(
                    "\PhysicalDisk(_Total)\Disk Read Bytes/sec")
                $diskWriteBytesPerSec = $quiescenceSampler.Read(
                    "\PhysicalDisk(_Total)\Disk Write Bytes/sec")
            $gpuRaw = @(& nvidia-smi --query-gpu=index,utilization.gpu `
                --format=csv,noheader,nounits 2>$null)
            if ($LASTEXITCODE -ne 0 -or $gpuRaw.Count -eq 0) {
                throw "nvidia-smi did not return GPU utilization"
            }
            $gpuRows = @()
            foreach ($gpuLine in $gpuRaw) {
                $gpuParts = @(([string]$gpuLine).Split(',') | ForEach-Object { $_.Trim() })
                if ($gpuParts.Count -ne 2) {
                    throw "nvidia-smi returned an unexpected GPU utilization row"
                }
                $gpuRows += [pscustomobject][ordered]@{
                    index = [Convert]::ToInt32(
                        $gpuParts[0], [Globalization.CultureInfo]::InvariantCulture)
                    utilization_percent = [Convert]::ToDouble(
                        $gpuParts[1], [Globalization.CultureInfo]::InvariantCulture)
                }
            }
            $gpuPercent = [double](($gpuRows | Measure-Object `
                -Property utilization_percent -Maximum).Maximum)
                $diskIoMiBps = ($diskReadBytesPerSec +
                    $diskWriteBytesPerSec) / 1MB
            $quiescenceRows += [pscustomobject][ordered]@{
                sample = $sampleIndex + 1
                timestamp_utc = [DateTime]::UtcNow.ToString(
                    "o", [Globalization.CultureInfo]::InvariantCulture)
                elapsed_ms = [math]::Round($quiescenceStopwatch.Elapsed.TotalMilliseconds, 3)
                    cpu_percent = [double]$cpuPercent
                    disk_percent = [double]$diskPercent
                    disk_read_mib_per_second = $diskReadBytesPerSec / 1MB
                    disk_write_mib_per_second = $diskWriteBytesPerSec / 1MB
                disk_io_mib_per_second = $diskIoMiBps
                gpu_percent = $gpuPercent
                gpu_utilization_percent_by_index = $gpuRows
            }
            } catch {
                if ($_.Exception.Message -match "0x800007D6" -and
                    $quiescencePdhInvalidDataRetries -lt 3) {
                    $quiescencePdhInvalidDataRetries++
                    Start-Sleep -Milliseconds 250
                    $sampleIndex--
                    continue
                }
                $quiescenceFailures += "sample-error: " + $_.Exception.Message
                break
            }
            if ($sampleIndex + 1 -lt $QuiescenceSamples) {
                Start-Sleep -Milliseconds $QuiescenceIntervalMs
            }
        }
    } catch {
        $quiescenceFailures += "counter-init-error: " + $_.Exception.Message
    } finally {
        if ($null -ne $quiescenceSampler) {
            $quiescenceSampler.Dispose()
        }
    }
}
$quiescenceStopwatch.Stop()
$cpuMedian = Get-G7PreflightMedian @($quiescenceRows | ForEach-Object { [double]$_.cpu_percent })
$diskMedian = Get-G7PreflightMedian @($quiescenceRows | ForEach-Object { [double]$_.disk_percent })
$diskIoMedian = Get-G7PreflightMedian @($quiescenceRows | ForEach-Object { [double]$_.disk_io_mib_per_second })
$gpuMedian = Get-G7PreflightMedian @($quiescenceRows | ForEach-Object { [double]$_.gpu_percent })
$observedIntervalsMs = @()
for ($sampleIndex = 1; $sampleIndex -lt $quiescenceRows.Count; $sampleIndex++) {
    $observedIntervalsMs += [double]$quiescenceRows[$sampleIndex].elapsed_ms -
        [double]$quiescenceRows[$sampleIndex - 1].elapsed_ms
}
$observedIntervalMedianMs = Get-G7PreflightMedian $observedIntervalsMs
if (-not $SkipSystemQuiescencePreflight -and $quiescenceRows.Count -ne $QuiescenceSamples) {
    $quiescenceFailures += "incomplete-sample-window"
}
if (-not $SkipSystemQuiescencePreflight -and $quiescenceRows.Count -eq $QuiescenceSamples) {
    if ($cpuMedian -gt $MaximumCpuMedianPercent) {
        $quiescenceFailures += "cpu-median-above-threshold"
    }
    if ($diskMedian -gt $MaximumDiskMedianPercent) {
        $quiescenceFailures += "disk-median-above-threshold"
    }
    if ($diskIoMedian -gt $MaximumDiskIoMedianMiBps) {
        $quiescenceFailures += "disk-io-median-above-threshold"
    }
    if ($gpuMedian -gt $MaximumGpuMedianPercent) {
        $quiescenceFailures += "gpu-median-above-threshold"
    }
}
$systemQuiescencePreflight = [pscustomobject][ordered]@{
    schema = "g7_system_quiescence_preflight_v1"
    checked_utc = [DateTime]::UtcNow.ToString(
        "o", [Globalization.CultureInfo]::InvariantCulture)
    sample_window_started_utc = $quiescenceStartedUtc.ToString(
        "o", [Globalization.CultureInfo]::InvariantCulture)
    tag = $Tag
    command_line = [Environment]::CommandLine
    harness_sha256 = $harnessHashAtStart
    git_head = ([string]$headAtStart).Trim()
    worktree_dirty = $worktreeDirtyAtStart
    executable_sha256 = $exeHashAtStart
    build_manifest_sha256 = $buildManifestHashAtStart
    model_path = $modelInfoAtStart.FullName
    model_size_bytes = [Int64]$modelInfoAtStart.Length
    q1_0_sidecar_path = $(if ($q1_0SidecarInfoAtStart) { $q1_0SidecarInfoAtStart.FullName } else { "" })
    q1_0_sidecar_size_bytes = $(if ($q1_0SidecarInfoAtStart) { [UInt64]$q1_0SidecarInfoAtStart.Length } else { [UInt64]0 })
    q1_0_sidecar_expected_sha256 = $(if ($ExpectedQ1_0ExpertSidecarSHA256) { $ExpectedQ1_0ExpertSidecarSHA256.ToLowerInvariant() } else { "" })
    q1_0_sidecar_receipt_path = $q1_0SidecarReceiptPath
    q1_0_sidecar_receipt_sha256 = $q1_0SidecarReceiptHashAtStart
    q1_0_sidecar_provenance_verified = $q1_0SidecarProvenanceVerified
    iq1_s_sidecar_path = $(if ($iq1SSidecarInfoAtStart) { $iq1SSidecarInfoAtStart.FullName } else { "" })
    iq1_s_sidecar_size_bytes = $(if ($iq1SSidecarInfoAtStart) { [UInt64]$iq1SSidecarInfoAtStart.Length } else { [UInt64]0 })
    iq1_s_sidecar_expected_sha256 = $ExpectedIq1SExpertSidecarSHA256.ToLowerInvariant()
    prompt_sha256 = $promptHash
    context = $Context
    max_tokens = $MaxTokens
    probe_only = [bool]$QuiescenceProbeOnly
    skipped = [bool]$SkipSystemQuiescencePreflight
    pdh_invalid_data_retries = $quiescencePdhInvalidDataRetries
    requested_samples = $QuiescenceSamples
    completed_samples = $quiescenceRows.Count
    requested_sleep_interval_ms = $QuiescenceIntervalMs
    requested_cooldown_seconds = $QuiescenceCooldownSec
    cooldown_started_utc = $quiescenceCooldownStartedUtc.ToString(
        "o", [Globalization.CultureInfo]::InvariantCulture)
    cooldown_observed_ms = [math]::Round(
        $quiescenceCooldownStopwatch.Elapsed.TotalMilliseconds, 3)
    provenance_metadata_rechecked_after_cooldown = $true
    observed_interval_median_ms = $observedIntervalMedianMs
    observed_window_ms = [math]::Round($quiescenceStopwatch.Elapsed.TotalMilliseconds, 3)
    gpu_scope = "maximum-utilization-across-visible-gpus"
    system_counter_source = $quiescenceCounterSource
    thresholds = $quiescenceThresholds
    cpu_median_percent = $cpuMedian
    disk_median_percent = $diskMedian
    disk_io_median_mib_per_second = $diskIoMedian
    gpu_median_percent = $gpuMedian
    failures = $quiescenceFailures
    samples = $quiescenceRows
    ready_to_launch = [bool]($SkipSystemQuiescencePreflight -or $quiescenceFailures.Count -eq 0)
}
$systemQuiescenceJson = $systemQuiescencePreflight | ConvertTo-Json -Depth 8
if (-not $systemQuiescencePreflight.ready_to_launch) {
    $systemQuiescenceJson |
        Set-Content -LiteralPath $systemQuiescenceLog -Encoding UTF8
    throw ("System quiescence preflight refused launch: " + ($quiescenceFailures -join ", "))
}
if ($QuiescenceProbeOnly) {
    $systemQuiescenceJson |
        Set-Content -LiteralPath $systemQuiescenceLog -Encoding UTF8
    Write-Host "[g7] system quiescence probe completed; model launch intentionally skipped"
    return
}

$serverMaxTokens = [math]::Max($MaxTokens, $effectiveWarmupMaxTokens)
$argList = @("-m", $model, "--cuda", "-c", "$Context", "-n", "$serverMaxTokens", "--host", "127.0.0.1", "--port", "$Port")
Write-Host ("[g7] launching: " + $exe + " " + ($argList -join " "))
Write-Host ("[g7] NoSelectedLoad=" + $NoSelectedLoad + " MaxTokens=" + $MaxTokens)

$proc = Start-Process -FilePath $exe -ArgumentList $argList -NoNewWindow -PassThru `
    -RedirectStandardError $stderrLog -RedirectStandardOutput $stdoutLog
$telemetryProc = Start-Process -FilePath powershell.exe -ArgumentList @(
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $runtimeMonitorHelper,
    "-TargetProcessId", "$($proc.Id)", "-OutputPath", $runtimeTelemetryLog,
    "-IntervalMs", "$TelemetryIntervalMs",
    "-MinimumAvailableGiB", $RuntimeMinimumAvailableGiB.ToString([Globalization.CultureInfo]::InvariantCulture),
    "-MaximumDiskQueueLength", $RuntimeMaximumDiskQueueLength.ToString([Globalization.CultureInfo]::InvariantCulture),
    "-HardMinimumAvailableGiB", $RuntimeHardMinimumAvailableGiB.ToString([Globalization.CultureInfo]::InvariantCulture),
    "-MaximumPagesOutputPerSecond", $RuntimeMaximumPagesOutputPerSecond.ToString([Globalization.CultureInfo]::InvariantCulture),
    "-MinimumPrivateWorkingSetRatio", $RuntimeMinimumPrivateWorkingSetRatio.ToString([Globalization.CultureInfo]::InvariantCulture),
    "-PrivateWorkingSetMinimumGiB", $RuntimePrivateWorkingSetMinimumGiB.ToString([Globalization.CultureInfo]::InvariantCulture),
    "-ContaminationSamples", "$RuntimeContaminationSamples"
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
    $proc.WaitForExit(30000) | Out-Null
    if ($telemetryProc -and -not $telemetryProc.HasExited) {
        $telemetryProc.WaitForExit(10000) | Out-Null
    }
    if ($telemetryProc -and -not $telemetryProc.HasExited) {
        $telemetryProc.Kill()
        $telemetryProc.WaitForExit(10000) | Out-Null
    }
    $abortSample = $null
    if (Test-Path -LiteralPath $runtimeTelemetryLog) {
        foreach ($line in Get-Content -LiteralPath $runtimeTelemetryLog) {
            if (-not $line.Trim()) { continue }
            try {
                $candidate = $line | ConvertFrom-Json
                if ($candidate.contamination_abort) { $abortSample = $candidate }
            } catch {}
        }
    }
    $failureReason = if ($abortSample) {
        "runtime-contamination-abort"
    } else {
        "server-not-ready"
    }
    [pscustomobject]@{
        schema = "g7_measurement_failure_v1"
        tag = $Tag
        reason = $failureReason
        head = $headAtStart
        executable_sha256 = $exeHashAtStart
        harness_sha256 = $harnessHashAtStart
        runtime_monitor_harness_sha256 = $runtimeMonitorHashAtStart
        runtime_telemetry_path = $runtimeTelemetryLog
        contamination_abort_sample = $abortSample
    } | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath $failurePath -Encoding UTF8
    Write-Host "=== stderr tail ==="; if (Test-Path $stderrLog) { Get-Content $stderrLog -Tail 30 }
    throw "Measurement failed before server readiness: $failureReason"
}
Write-Host ("[g7] server READY in " + [int]$loadSec + "s")

$messages = @()
if ($SystemPrompt) { $messages += @{ role = "system"; content = $SystemPrompt } }
$messages += @{ role = "user"; content = $Prompt }
$warmupMessages = @()
if ($SystemPrompt) { $warmupMessages += @{ role = "system"; content = $SystemPrompt } }
$warmupMessages += @{ role = "user"; content = $effectiveWarmupPrompt }
$bodySpec = @{
    model = "deepseek-chat"
    messages = $messages
    max_tokens = $MaxTokens
    temperature = 0
    think = $false
}
$warmupBodySpec = @{
    model = "deepseek-chat"
    messages = $warmupMessages
    max_tokens = $effectiveWarmupMaxTokens
    temperature = 0
    think = $false
}
if (-not [string]::IsNullOrEmpty($StopSequence)) {
    $bodySpec.stop = $StopSequence
    $warmupBodySpec.stop = $StopSequence
}
$body = $bodySpec | ConvertTo-Json -Depth 5
$warmupBody = $warmupBodySpec | ConvertTo-Json -Depth 5
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
        [pscustomobject][ordered]@{
            schema = "g7_raw_response_checkpoint_v1"
            tag = $Tag
            gate_kind = $GateKind
            captured_utc = [DateTime]::UtcNow.ToString("o")
            complete = $false
            warmup_result = $warmupResult
            results = $results
        } | ConvertTo-Json -Depth 8 |
            Set-Content -LiteralPath $rawOutputsPath -Encoding UTF8
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
$serverExitCode = [int]$proc.ExitCode
Start-Sleep -Milliseconds 250
if ($telemetryProc -and -not $telemetryProc.HasExited) {
    $telemetryProc.WaitForExit(10000) | Out-Null
}
if ($telemetryProc -and -not $telemetryProc.HasExited) {
    $telemetryProc.Kill()
    $telemetryProc.WaitForExit(10000) | Out-Null
}

$expertRecoveryTraceArtifact = [pscustomobject]@{
    requested = [bool]$ExpertRecoveryTrace
    observed = $false
    valid = (-not [bool]$ExpertRecoveryTrace)
}
if ($ExpertRecoveryTrace) {
    $expertRecoveryLogText = if (Test-Path -LiteralPath $stderrLog) {
        Get-Content -LiteralPath $stderrLog -Raw
    } else { "" }
    $traceFailureMarkers = [regex]::Matches(
        $expertRecoveryLogText,
        '(?m)^ds4: \[expert-recovery-trace\] result=failed reason=[^\r\n]+\r?$')
    if ($traceFailureMarkers.Count -ne 0) {
        throw "Expert recovery runtime reported a fail-closed artifact failure"
    }
    $expertRecoveryTraceArtifact = Read-G7ExpertRecoveryTraceArtifact `
        -Required $true -RootPath $expertRecoveryTraceRoot `
        -OutputPrefix $expertRecoveryTracePrefix `
        -ExpectedLayer $ExpertRecoveryTraceLayer `
        -ExpectedExpert $ExpertRecoveryTraceExpert `
        -ExpectedMaxSamples $ExpertRecoveryTraceMaxSamples `
        -ExpectedByteBudget $ExpertRecoveryTraceByteBudget `
        -ExpectedModelSHA256 $modelHashAtStart `
        -ExpectedModelBytes ([UInt64]$modelInfoAtStart.Length) `
        -ExpectedSidecarSHA256 $q1_0SidecarHashAtStart `
        -ExpectedSidecarBytes ([UInt64]$q1_0SidecarInfoAtStart.Length) `
        -ExpectedBuildManifestSHA256 $buildManifestHashAtStart `
        -ExpectedBuildFingerprintSHA256 `
            ([string]$buildManifest.input_fingerprint_sha256) `
        -ExpectedExecutableSHA256 $exeHashAtStart
    $traceCompletePattern =
        '(?m)^ds4: \[expert-recovery-trace\] result=complete ' +
        'samples=(?<samples>[0-9]+) max_samples=(?<max>[0-9]+) ' +
        'capped=(?<capped>[0-9]+) vector_dim=(?<dim>[0-9]+) ' +
        'vector_bytes=(?<vector_bytes>[0-9]+) ' +
        'binary_bytes=(?<binary_bytes>[0-9]+) ' +
        'jsonl_bytes=(?<jsonl_bytes>[0-9]+) ' +
        'manifest_bytes=(?<manifest_bytes>[0-9]+) ' +
        'byte_budget=(?<budget>[0-9]+) layer=(?<layer>[0-9]+) ' +
        'expert=(?<expert>[0-9]+) ' +
        'binary_sha256=(?<binary_sha>[0-9a-f]{64}) ' +
        'jsonl_sha256=(?<jsonl_sha>[0-9a-f]{64}) ' +
        'manifest_sha256=(?<manifest_sha>[0-9a-f]{64}) ' +
        'input_only=1 teacher_output=offline_exact_iq2\r?$'
    $traceCompleteMatches = [regex]::Matches(
        $expertRecoveryLogText, $traceCompletePattern)
    if ($traceCompleteMatches.Count -ne 1) {
        throw "Expert recovery runtime completion summary is missing or duplicated"
    }
    $traceComplete = $traceCompleteMatches[0]
    if ([UInt64]$traceComplete.Groups['samples'].Value -ne
            [UInt64]$expertRecoveryTraceArtifact.sample_count -or
        [UInt64]$traceComplete.Groups['max'].Value -ne
            [UInt64]$expertRecoveryTraceArtifact.max_samples -or
        [UInt64]$traceComplete.Groups['capped'].Value -ne
            [UInt64]$expertRecoveryTraceArtifact.capped_samples -or
        [UInt64]$traceComplete.Groups['dim'].Value -ne
            [UInt64]$expertRecoveryTraceArtifact.vector_dim -or
        [UInt64]$traceComplete.Groups['vector_bytes'].Value -ne
            [UInt64]$expertRecoveryTraceArtifact.vector_bytes_per_sample -or
        [UInt64]$traceComplete.Groups['binary_bytes'].Value -ne
            [UInt64]$expertRecoveryTraceArtifact.binary_bytes -or
        [UInt64]$traceComplete.Groups['jsonl_bytes'].Value -ne
            [UInt64](Get-Item $expertRecoveryTraceArtifact.jsonl_path).Length -or
        [UInt64]$traceComplete.Groups['manifest_bytes'].Value -ne
            [UInt64](Get-Item $expertRecoveryTraceArtifact.manifest_path).Length -or
        [UInt64]$traceComplete.Groups['budget'].Value -ne
            [UInt64]$expertRecoveryTraceArtifact.byte_budget -or
        [UInt64]$traceComplete.Groups['layer'].Value -ne
            [UInt64]$expertRecoveryTraceArtifact.layer -or
        [UInt64]$traceComplete.Groups['expert'].Value -ne
            [UInt64]$expertRecoveryTraceArtifact.expert -or
        $traceComplete.Groups['binary_sha'].Value -cne
            [string]$expertRecoveryTraceArtifact.binary_sha256 -or
        $traceComplete.Groups['jsonl_sha'].Value -cne
            [string]$expertRecoveryTraceArtifact.jsonl_sha256 -or
        $traceComplete.Groups['manifest_sha'].Value -cne
            [string]$expertRecoveryTraceArtifact.manifest_sha256) {
        throw "Expert recovery runtime summary does not match the committed artifact"
    }
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
$diskPercentSamples = @($runtimeSamples | ForEach-Object { if ($_.disk -and $_.disk.seen) { $_.disk.percent_time } } | Where-Object { $null -ne $_ })
$diskBytesSamples = @($runtimeSamples | ForEach-Object { if ($_.disk -and $_.disk.seen) { $_.disk.bytes_per_second } } | Where-Object { $null -ne $_ })
$diskReadSamples = @($runtimeSamples | ForEach-Object { if ($_.disk -and $_.disk.seen) { $_.disk.read_bytes_per_second } } | Where-Object { $null -ne $_ })
$diskWriteSamples = @($runtimeSamples | ForEach-Object { if ($_.disk -and $_.disk.seen) { $_.disk.write_bytes_per_second } } | Where-Object { $null -ne $_ })
$diskQueueSamples = @($runtimeSamples | ForEach-Object { if ($_.disk -and $_.disk.seen) { $_.disk.queue_length } } | Where-Object { $null -ne $_ })
$pagesInputSamples = @($runtimeSamples | ForEach-Object { if ($_.system_memory_pressure -and $_.system_memory_pressure.seen) { $_.system_memory_pressure.pages_input_per_second } } | Where-Object { $null -ne $_ })
$pagesOutputSamples = @($runtimeSamples | ForEach-Object { if ($_.system_memory_pressure -and $_.system_memory_pressure.seen) { $_.system_memory_pressure.pages_output_per_second } } | Where-Object { $null -ne $_ })
$privateWorkingSetRatioSamples = @($runtimeSamples | ForEach-Object { $_.private_working_set_ratio } | Where-Object { $null -ne $_ })
$contaminationSamplesObserved = @($runtimeSamples | ForEach-Object { $_.contamination_consecutive_samples } | Where-Object { $null -ne $_ })
$contaminationAbortObserved = @($runtimeSamples | Where-Object { $_.contamination_abort }).Count -gt 0
if ($sharedSamples.Count -eq 0 -or $dedicatedSamples.Count -eq 0 -or
    $gpuUtilSamples.Count -eq 0 -or $vramSamples.Count -eq 0 -or
    $diskQueueSamples.Count -eq 0 -or $diskReadSamples.Count -eq 0) {
    throw "Runtime telemetry failed closed: required WDDM/NVIDIA/disk counters are missing"
}
if ($RuntimeMaximumPagesOutputPerSecond -gt 0.0 -and $pagesOutputSamples.Count -eq 0) {
    throw "Runtime telemetry failed closed: requested system page-output counters are missing"
}
if ($RuntimeMinimumPrivateWorkingSetRatio -gt 0.0 -and $privateWorkingSetRatioSamples.Count -eq 0) {
    throw "Runtime telemetry failed closed: requested private working-set residency counters are missing"
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
$diskReadBytesEstimated = 0.0
for ($sampleIndex = 1; $sampleIndex -lt $runtimeSamples.Count; $sampleIndex++) {
    $previous = $runtimeSamples[$sampleIndex - 1]
    $current = $runtimeSamples[$sampleIndex]
    if ($previous.disk -and $previous.disk.seen -and
        $null -ne $previous.disk.read_bytes_per_second) {
        $dt = [double]$current.elapsed_seconds - [double]$previous.elapsed_seconds
        $diskReadBytesEstimated += [double]$previous.disk.read_bytes_per_second * $dt
    }
}
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
    aggregate_disk_percent_time_median = Get-G7Median $diskPercentSamples
    aggregate_disk_percent_time_peak = if ($diskPercentSamples.Count) { [double]($diskPercentSamples | Measure-Object -Maximum).Maximum } else { $null }
    aggregate_disk_bytes_per_second_median = Get-G7Median $diskBytesSamples
    aggregate_disk_bytes_per_second_peak = if ($diskBytesSamples.Count) { [double]($diskBytesSamples | Measure-Object -Maximum).Maximum } else { $null }
    aggregate_disk_read_bytes_estimated = [Int64][math]::Round($diskReadBytesEstimated)
    aggregate_disk_read_mib_per_second = if ($diskReadSamples.Count) { [double](($diskReadSamples | Measure-Object -Average).Average / 1MB) } else { $null }
    aggregate_disk_read_throughput_mib_per_second = if ($runtimeElapsedSeconds -gt 0) { [double]($diskReadBytesEstimated / 1MB / $runtimeElapsedSeconds) } else { $null }
    aggregate_disk_write_mib_per_second = if ($diskWriteSamples.Count) { [double](($diskWriteSamples | Measure-Object -Average).Average / 1MB) } else { $null }
    aggregate_disk_queue_length_median = Get-G7Median $diskQueueSamples
    aggregate_disk_queue_length_peak = if ($diskQueueSamples.Count) { [double]($diskQueueSamples | Measure-Object -Maximum).Maximum } else { $null }
    system_pages_input_per_second_peak = if ($pagesInputSamples.Count) { [double]($pagesInputSamples | Measure-Object -Maximum).Maximum } else { $null }
    system_pages_output_per_second_peak = if ($pagesOutputSamples.Count) { [double]($pagesOutputSamples | Measure-Object -Maximum).Maximum } else { $null }
    private_working_set_ratio_minimum = if ($privateWorkingSetRatioSamples.Count) { [double]($privateWorkingSetRatioSamples | Measure-Object -Minimum).Minimum } else { $null }
    contamination_consecutive_peak = if ($contaminationSamplesObserved.Count) { [int]($contaminationSamplesObserved | Measure-Object -Maximum).Maximum } else { 0 }
    contamination_abort_observed = [bool]$contaminationAbortObserved
    contamination_runtime_minimum_available_gib = $RuntimeMinimumAvailableGiB
    contamination_runtime_maximum_disk_queue_length = $RuntimeMaximumDiskQueueLength
    contamination_runtime_hard_minimum_available_gib = $RuntimeHardMinimumAvailableGiB
    contamination_runtime_maximum_pages_output_per_second = $RuntimeMaximumPagesOutputPerSecond
    contamination_runtime_minimum_private_working_set_ratio = $RuntimeMinimumPrivateWorkingSetRatio
    contamination_runtime_private_working_set_minimum_gib = $RuntimePrivateWorkingSetMinimumGiB
    contamination_runtime_consecutive_samples = $RuntimeContaminationSamples
    contamination_contract = "abort after $RuntimeContaminationSamples consecutive samples matching legacy low-RAM+queue, hard-low-RAM, page-output, residency-collapse, or required-counter-missing gates"
    win32_process_read_transfer_delta_bytes = if ($null -ne $firstRuntimeSample.read_transfer_bytes -and $null -ne $lastRuntimeSample.read_transfer_bytes) { [Int64]$lastRuntimeSample.read_transfer_bytes - [Int64]$firstRuntimeSample.read_transfer_bytes } else { $null }
    win32_process_read_operation_delta = if ($null -ne $firstRuntimeSample.read_operation_count -and $null -ne $lastRuntimeSample.read_operation_count) { [Int64]$lastRuntimeSample.read_operation_count - [Int64]$firstRuntimeSample.read_operation_count } else { $null }
    win32_process_other_operation_delta = if ($null -ne $firstRuntimeSample.other_operation_count -and $null -ne $lastRuntimeSample.other_operation_count) { [Int64]$lastRuntimeSample.other_operation_count - [Int64]$firstRuntimeSample.other_operation_count } else { $null }
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
$expertTieringReplacementBudgetBase = 0
$expertTieringMinFrequency = 0; $expertTieringHysteresis = 0.0
$expertTieringAdaptiveEnabled = $false; $expertTieringAdaptiveCurrent = 0
$expertTieringAdaptiveMin = 0; $expertTieringAdaptiveMax = 0
$expertTieringAdaptiveStep = 0; $expertTieringAdaptivePressureThreshold = 0
$expertTieringAdaptiveUps = 0; $expertTieringAdaptiveDowns = 0
$expertTieringAdaptivePressureEpochs = 0; $expertTieringAdaptiveQuietEpochs = 0
$expertTieringAdaptiveLastSkipDelta = 0; $expertTieringAdaptiveLastReplacementDelta = 0
$expertTieringCold = 0; $expertTieringRamHits = 0; $expertTieringVramHits = 0
$expertTieringColdToRam = 0; $expertTieringColdToVram = 0; $expertTieringRamToWarm = 0
$expertTieringVramPromotions = 0; $expertTieringVramDemotions = 0; $expertTieringRamEvictions = 0
$expertTieringRamAdmitSkips = 0; $expertTieringGeneralBackingReclaims = 0; $expertTieringTransient = 0; $expertTieringFailures = 0
$expertTieringSsdBytes = 0; $expertTieringRamH2DBytes = 0
$expertTieringStatesSsd = 0; $expertTieringStatesProbation = 0
$expertTieringStatesWarm = 0; $expertTieringStatesVram = 0
$expertTieringMassSum = 0.0; $expertTieringLfruTop = 0.0
$expertTieringComposeObserved = $false; $expertTieringComposeFlag = 0
$expertTieringComposeRouterOpen = 0
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
$gpuRoutesQueries = 0; $gpuRoutesDefaultSyncCalls = 0; $gpuRoutesNoDefaultSyncCalls = 0
$gpuRoutesPackedCopyRequested = 0; $gpuRoutesPackedCopyExperts = 0
$gpuRoutesPackedCopySubmissions = 0; $gpuRoutesPackedCopyBytes = 0
$gpuRoutesLegacyCopySubmissions = 0
$splitFusedObserved = $false; $splitFusedCalls = 0; $splitFusedHits = 0
$splitFusedMisses = 0; $splitFusedMissScratchBytesAvoided = 0
$splitFusedSumReadBytesAvoided = 0
$gpuRoutesCacheCount = 0; $gpuRoutesCacheCalls = 0; $gpuRoutesCacheHits = 0
$gpuRoutesCacheMisses = 0; $gpuRoutesCacheAdmissions = 0; $gpuRoutesCacheEvictions = 0
$gpuRoutesCacheDirectLoads = 0
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
$prefillMassArmed = $false; $prefillMassArmedEventCount = 0
$prefillMassFinalized = $false; $prefillMassFinalizeEventCount = 0
$prefillMassLayers = 0; $prefillMassRowsMin = 0; $prefillMassRowsMax = 0
$prefillMassRoutedSlots = 0; $prefillMassUnique = 0
$prefillMassCandidate = 0; $prefillMassCapacity = 0
$prefillMassTotal = 0.0; $prefillMassCandidateMass = 0.0
$prefillMassCoverage = 0.0; $prefillMassCutoff = 0.0
$prefillMassPolicy = "not_observed"; $prefillMassResidency = "not_observed"
$prefillMassDecodeTokens = 0; $prefillMassDecodeSlots = 0; $prefillMassDecodeHits = 0; $prefillMassDecodeHitRate = 0.0
$prefillMassDecodeEventCount = 0
$prefillMassWrapObserved = $false; $prefillMassWrapEventCount = 0
$prefillMassWrapResult = "not_observed"; $prefillMassWrapReason = "not_observed"
$prefillMassWrapCandidate = 0; $prefillMassWrapLoads = 0; $prefillMassWrapWorkers = 0
$prefillMassWrapSeconds = 0.0; $prefillMassWrapSnapshotBefore = 0; $prefillMassWrapSnapshotAfter = 0
$prefillMassWrapResidentBefore = 0; $prefillMassWrapResidentAfter = 0
$prefillMassWrapGeneration = 0; $prefillMassWrapPreloaded = -1
$prefillMassWrapRouter = "not_observed"; $prefillMassWrapMask = "not_observed"
$prefillMassWrapParsedEvents = @()
$prefillMassComposeObserved = $false; $prefillMassComposeEventCount = 0
$prefillMassComposeParsedCount = 0; $prefillMassComposeFingerprints = @()
$prefillMassComposeHashLayers = 0; $prefillMassComposeHashSeedEntries = 0
$prefillMassComposeRankedEntries = 0; $prefillMassComposeTotalCandidate = 0
$prefillMassComposeCapacity = 0; $prefillMassComposeCandidateFNV1A64 = "not_observed"
$prefillMassComposeSparseSkippedRanked = 0
$prefillMassComposeMaskObserved = $false; $prefillMassComposeMaskEventCount = 0
$prefillMassComposeMaskFailedCount = 0; $prefillMassComposeMaskBase = "not_observed"
$prefillMassComposeMaskExistingLayers = 0; $prefillMassComposeMaskAppliedCount = 0
$prefillMassComposeMaskRestoreCount = 0; $prefillMassComposeMaskSemantics = "not_observed"
$prefillMassLayerStripeObserved = $false; $prefillMassLayerStripeEventCount = 0
$prefillMassLayerStripeFailedCount = 0; $prefillMassLayerStripeResult = "not_observed"
$prefillMassLayerStripeReason = "not_observed"; $prefillMassLayerStripeStride = 0
$prefillMassLayerStripePhase = 0; $prefillMassLayerStripeRoutedLayers = 0
$prefillMassLayerStripeFullLayers = 0; $prefillMassLayerStripePartialLayers = 0
$prefillMassLayerStripeFullKeep = 0; $prefillMassLayerStripePartialKeepMin = 0
$prefillMassLayerStripePartialKeepMax = 0; $prefillMassLayerStripeRoutedCandidate = 0
$prefillMassLayerStripeTotalCandidate = 0; $prefillMassLayerStripeCapacity = 0
$prefillMassLayerStripeSemantics = "not_observed"
$prefillVramSeedObserved = $false; $prefillVramSeedLineCount = 0
$prefillVramSeedResult = "not_observed"; $prefillVramSeedReason = "not_observed"
$prefillVramSeedRequestedObserved = 0; $prefillVramSeedLayers = 0
$prefillVramSeedEntries = 0; $prefillVramSeedBytes = 0
$prefillVramSeedSeconds = 0.0; $prefillVramSeedFailures = 0
$prefillVramSeedPriorMass = 0.0; $prefillVramSeedSemantics = "not_observed"
$prefillVramSeedGlobalObserved = $false; $prefillVramSeedGlobalLineCount = 0
$prefillVramSeedGlobalRequestedObserved = 0
$prefillVramSeedGlobalFloorObserved = 0
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
$arenaWrapProfileObserved = $false; $arenaWrapProfileResult = "not_observed"
$arenaWrapScheduleObserved = "not_observed"; $arenaWrapSourceObserved = "not_observed"
$arenaWrapChecksumObserved = "not_observed"
$arenaWrapProfileLoads = 0; $arenaWrapProfileWorkers = 0
$arenaWrapProfileBeginSeconds = 0.0; $arenaWrapProfileCopyChecksumSeconds = 0.0
$arenaWrapProfileFinishSeconds = 0.0; $arenaWrapProfilePublishSeconds = 0.0
$arenaWrapProfileTotalSeconds = 0.0; $arenaWrapSourcePartsCopySeconds = 0.0
$arenaWrapSourcePartsChecksumSeconds = 0.0; $arenaWrapPartCount = 0
$arenaWrapCopyWorkers = 0; $arenaWrapChecksumWorkers = 0
$arenaWrapFileQDRequestedObserved = 1; $arenaWrapFileQDObserved = 1; $arenaWrapFileSubmits = 0
$arenaWrapFileCompletions = 0; $arenaWrapFileFailures = 0
$arenaWrapPartProfileObserved = $false; $arenaWrapPartProfileResult = "not_observed"
$arenaWrapPartProfilePhases = 0; $arenaWrapPartProfileWorkers = 0
$arenaWrapPartProfileParts = 0; $arenaWrapPartProfileBytes = 0
$arenaWrapPartProfileMemcpySumSeconds = 0.0
$arenaWrapPartProfileMainWorkerSeconds = 0.0; $arenaWrapPartProfileJoinSeconds = 0.0
$arenaWrapPartProfileWorkerActiveMinSeconds = 0.0; $arenaWrapPartProfileWorkerActiveMaxSeconds = 0.0
$arenaWrapPartProfileWorkerPartsMin = 0; $arenaWrapPartProfileWorkerPartsMax = 0
$arenaWrapPartProfileSlowThresholdMs = 0.0; $arenaWrapPartProfileSlowParts = 0
$arenaWrapPartProfileMaxPartMs = 0.0; $arenaWrapPartProfileMaxPartBytes = 0
$arenaWrapPartProfileMaxPartLoad = 0; $arenaWrapPartProfileMaxPartCursor = 0
$arenaWrapPartProfileMaxPartKind = "not_observed"; $arenaWrapPartProfileMaxPartSource = 0
$arenaWrapLayoutProfileObserved = $false; $arenaWrapLayoutProfileRows = @()
$arenaWrapTrimObserved = $false; $arenaWrapTrimResult = "not_observed"
$arenaWrapTrimCalls = 0; $arenaWrapTrimSucceeded = 0; $arenaWrapTrimFailed = 0
$arenaWrapTrimSeconds = 0.0; $arenaWrapTrimLastError = 0
$arenaWrapUnlockObserved = $false; $arenaWrapUnlockRows = @()
$arenaWrapUnlockSummaryObserved = $false
$arenaWrapUnlockSummaryResult = "not_observed"
$arenaWrapUnlockSummaryPhases = 0; $arenaWrapUnlockSummaryWaves = 0
$arenaWrapUnlockSummaryWaveGiB = 0.0; $arenaWrapUnlockSummaryMaxWaveBytes = 0
$arenaWrapUnlockSummaryParts = 0
$arenaWrapUnlockSummaryRanges = 0; $arenaWrapUnlockSummaryBytesRequested = 0
$arenaWrapUnlockSummaryCalls = 0; $arenaWrapUnlockSummaryTrue = 0
$arenaWrapUnlockSummaryErrorNotLocked = 0; $arenaWrapUnlockSummaryFailed = 0
$arenaWrapUnlockSummarySeconds = 0.0
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
$arenaFinalPinnedHits = 0; $arenaFinalPageableHits = 0
$arenaFinalPinnedUploadedGiB = 0.0; $arenaFinalPageableUploadedGiB = 0.0
$arenaAllocatedBytes = 0; $arenaAllocatedPageableBytes = 0
$arenaAllocatedTotalBytes = 0; $arenaSlotBytes = 0; $arenaAllocatedSlots = 0
$arenaAllocatedPinnedSlots = 0; $arenaAllocatedPageableSlots = 0
$arenaCapObserved = $false; $arenaCapRequestedGiB = 0.0
$arenaCapMinAvailableGiB = 0.0; $arenaCapAvailableBeforeGiB = 0.0
$arenaCapRequestedBytes = 0; $arenaCapRequestedSlots = 0
$arenaCapChosenBytes = 0; $arenaCapChosenSlots = 0
$arenaCapPageableBytes = 0; $arenaCapPageableSlots = 0
$arenaCapTotalSlots = 0
$arenaCapRingSlots = 0; $arenaCapHostBudgetBytes = 0
$arenaCapSsdWrap = $false; $arenaReadyRingSlots = 0
$arenaCapCapped = $false; $arenaCapResult = "not_observed"
$arenaCapReason = "not_observed"
$requestPhaseObserved = $false; $requestPhaseLineCount = 0
$requestPhaseEvents = @{}
$requestPhasePrefillComputeSeconds = 0.0; $requestPhaseWrapSeconds = 0.0
$requestPhaseWrapCopySeconds = 0.0; $requestPhasePostWrapSeconds = 0.0
$requestPhaseSyncTailSeconds = 0.0; $requestPhaseDecodeGapSeconds = 0.0
$requestPhaseFirstSampleSeconds = 0.0; $requestPhaseFirstEvalSeconds = 0.0
$requestPhaseDecodeToFirstSeconds = 0.0; $requestPhasePromptToFirstSeconds = 0.0
$serverRunsAll = @()
if (Test-Path $stderrLog) {
    $lines = Get-Content $stderrLog

    if (-not $httpOk -or $results.Count -ne $Repeats) {
        $runtimeFailureEvidence = @($lines | Where-Object {
            $_ -match 'allocation failed|failed closed|finish=error|cuda decode failed'
        } | Select-Object -Last 4)
        if (Test-Path -LiteralPath $runtimeTelemetryLog) {
            $runtimeAbortSample = $null
            foreach ($runtimeLine in Get-Content -LiteralPath $runtimeTelemetryLog) {
                if (-not $runtimeLine.Trim()) { continue }
                try {
                    $runtimeCandidate = $runtimeLine | ConvertFrom-Json
                    if ($runtimeCandidate.contamination_abort) {
                        $runtimeAbortSample = $runtimeCandidate
                    }
                } catch {}
            }
            if ($runtimeAbortSample) {
                $runtimeAbortReasons = @($runtimeAbortSample.contamination_reasons) -join ","
                $runtimeFailureEvidence +=
                    "runtime-monitor-abort reasons=$runtimeAbortReasons"
            }
        }
        $runtimeFailureSuffix = if ($runtimeFailureEvidence.Count -gt 0) {
            "; runtime=" + ($runtimeFailureEvidence -join " | ")
        } else { "" }
        $runtimeFailureReason = if ($runtimeAbortSample) {
            "runtime-contamination-abort"
        } elseif (-not $httpOk) {
            "http-request-failed"
        } else {
            "runtime-invariant-preparse"
        }
        Write-G7MeasurementFailure `
            -Reason $runtimeFailureReason `
            -AbortSample $runtimeAbortSample `
            -Evidence $runtimeFailureEvidence
        throw ("Measurement failed before runtime invariant parsing: " +
            "http_ok=$httpOk completed=$($results.Count) expected=$Repeats" +
            $runtimeFailureSuffix)
    }

    $requestPhaseLines = @($lines | Where-Object { $_ -match '^ds4: \[request-phase\] ' })
    $requestPhaseLineCount = $requestPhaseLines.Count
    foreach ($phaseLine in $requestPhaseLines) {
        if ($phaseLine -notmatch '^ds4: \[request-phase\] event=([a-z-]+) mono=([0-9.]+)') {
            throw "Request phase trace line format mismatch: $phaseLine"
        }
        $phaseEvent = $Matches[1]
        $phaseMono = [double]::Parse($Matches[2], [Globalization.CultureInfo]::InvariantCulture)
        if ($requestPhaseEvents.ContainsKey($phaseEvent)) {
            throw "Request phase trace event repeated: $phaseEvent"
        }
        $requestPhaseEvents[$phaseEvent] = $phaseMono
    }
    if ($RequestPhaseTrace) {
        $requiredPhaseEvents = @(
            'prompt-start', 'session-sync-enter', 'prefill-finalize-enter',
            'wrap-enter', 'wrap-copy-enter', 'wrap-copy-return',
            'wrap-terminal', 'prefill-finalize-return', 'session-sync-return',
            'decode-enter', 'first-sample-enter', 'first-sample-return',
            'first-eval-enter', 'first-eval-return', 'first-token-ready',
            'request-end'
        )
        foreach ($phaseEvent in $requiredPhaseEvents) {
            if (-not $requestPhaseEvents.ContainsKey($phaseEvent)) {
                throw "Request phase trace event missing: $phaseEvent"
            }
        }
        for ($phaseIndex = 1; $phaseIndex -lt $requiredPhaseEvents.Count; $phaseIndex++) {
            $phasePrev = $requiredPhaseEvents[$phaseIndex - 1]
            $phaseCurrent = $requiredPhaseEvents[$phaseIndex]
            if ($requestPhaseEvents[$phaseCurrent] -lt $requestPhaseEvents[$phasePrev]) {
                throw "Request phase trace order mismatch: $phasePrev -> $phaseCurrent"
            }
        }
        if ($requestPhaseLineCount -ne $requiredPhaseEvents.Count) {
            throw "Request phase trace emitted unexpected extra events"
        }
        $requestPhaseObserved = $true
        $requestPhasePrefillComputeSeconds = $requestPhaseEvents['prefill-finalize-enter'] - $requestPhaseEvents['session-sync-enter']
        $requestPhaseWrapSeconds = $requestPhaseEvents['wrap-terminal'] - $requestPhaseEvents['wrap-enter']
        $requestPhaseWrapCopySeconds = $requestPhaseEvents['wrap-copy-return'] - $requestPhaseEvents['wrap-copy-enter']
        $requestPhasePostWrapSeconds = $requestPhaseEvents['prefill-finalize-return'] - $requestPhaseEvents['wrap-terminal']
        $requestPhaseSyncTailSeconds = $requestPhaseEvents['session-sync-return'] - $requestPhaseEvents['prefill-finalize-return']
        $requestPhaseDecodeGapSeconds = $requestPhaseEvents['decode-enter'] - $requestPhaseEvents['session-sync-return']
        $requestPhaseFirstSampleSeconds = $requestPhaseEvents['first-sample-return'] - $requestPhaseEvents['first-sample-enter']
        $requestPhaseFirstEvalSeconds = $requestPhaseEvents['first-eval-return'] - $requestPhaseEvents['first-eval-enter']
        $requestPhaseDecodeToFirstSeconds = $requestPhaseEvents['first-token-ready'] - $requestPhaseEvents['decode-enter']
        $requestPhasePromptToFirstSeconds = $requestPhaseEvents['first-token-ready'] - $requestPhaseEvents['prompt-start']
    } elseif ($requestPhaseLineCount -ne 0) {
        throw "Request phase trace activated while not requested"
    }

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
        $expertTieringFinalPattern = "^ds4: \[expert-tiering\] final mode=(off|observe|enforce) policy=(second-touch|mass-lfru) clock_calls=(\d+) replacement_budget=(\d+) min_frequency=(\d+) hysteresis=" + $numberPattern + " calls=(\d+) selected=(\d+) cold=(\d+) ram_hits=(\d+) vram_hits=(\d+) cold_to_ram=(\d+) cold_to_vram=(\d+) ram_to_warm=(\d+) vram_promotions=(\d+) vram_demotions=(\d+) ram_evictions=(\d+) ram_admit_skips=(\d+) general_backing_reclaims=(\d+) transient=(\d+) failures=(\d+) ssd_bytes=(\d+) ram_h2d_bytes=(\d+) policy_epochs=(\d+) policy_free_promotions=(\d+) policy_replacements=(\d+) policy_min_frequency_skips=(\d+) policy_budget_skips=(\d+) policy_score_skips=(\d+) states_ssd=(\d+) states_probation=(\d+) states_warm=(\d+) states_vram=(\d+) mass_sum=" + $numberPattern + " lfru_top=" + $numberPattern + "$"
        $expertTieringComposeFinalPattern = "^ds4: \[expert-tiering\] final mode=(off|observe|enforce) policy=(second-touch|mass-lfru) compose_prefill_mass_tiering=(\d+) compose_router_open=(\d+) snapshot_generation=(\d+) snapshot_backing_entries=(\d+) snapshot_backing_hits=(\d+) snapshot_backing_misses=(\d+) snapshot_to_vram_bytes=(\d+) forbidden_cold_ssd_to_vram=(\d+) general_backing_reclaims=(\d+) clock_calls=(\d+) replacement_budget=(\d+) min_frequency=(\d+) hysteresis=" + $numberPattern + " calls=(\d+) selected=(\d+) cold=(\d+) ram_hits=(\d+) vram_hits=(\d+) cold_to_ram=(\d+) cold_to_vram=(\d+) ram_to_warm=(\d+) vram_promotions=(\d+) vram_demotions=(\d+) ram_evictions=(\d+) ram_admit_skips=(\d+) transient=(\d+) failures=(\d+) ssd_bytes=(\d+) ram_h2d_bytes=(\d+) policy_epochs=(\d+) policy_free_promotions=(\d+) policy_replacements=(\d+) policy_min_frequency_skips=(\d+) policy_budget_skips=(\d+) policy_score_skips=(\d+) states_ssd=(\d+) states_probation=(\d+) states_warm=(\d+) states_vram=(\d+) mass_sum=" + $numberPattern + " lfru_top=" + $numberPattern + "$"
        if ($expertTieringFinalLine -match " adaptive_budget=") {
            $expertTieringFields = @{}
            foreach ($fieldMatch in [regex]::Matches($expertTieringFinalLine, " ([a-z0-9_]+)=([^ ]+)")) {
                $expertTieringFields[$fieldMatch.Groups[1].Value] = $fieldMatch.Groups[2].Value
            }
            $requiredExpertTieringFields = @(
                "mode", "policy", "clock_calls", "replacement_budget",
                "replacement_budget_base", "adaptive_budget", "adaptive_current_budget", "adaptive_min",
                "adaptive_max", "adaptive_step", "adaptive_pressure_threshold",
                "adaptive_ups", "adaptive_downs", "adaptive_pressure_epochs",
                "adaptive_quiet_epochs", "adaptive_last_budget_skips_delta",
                "adaptive_last_replacements_delta", "min_frequency", "hysteresis",
                "calls", "selected", "cold", "ram_hits", "vram_hits",
                "cold_to_ram", "cold_to_vram", "ram_to_warm", "vram_promotions",
                "vram_demotions", "ram_evictions", "ram_admit_skips",
                "general_backing_reclaims",
                "transient", "failures", "ssd_bytes", "ram_h2d_bytes",
                "policy_epochs", "policy_free_promotions", "policy_replacements",
                "policy_min_frequency_skips", "policy_budget_skips",
                "policy_score_skips", "states_ssd", "states_probation",
                "states_warm", "states_vram", "mass_sum", "lfru_top"
            )
            foreach ($requiredExpertTieringField in $requiredExpertTieringFields) {
                if (-not $expertTieringFields.ContainsKey($requiredExpertTieringField)) {
                    throw "Expert tiering measurement failed: adaptive final line missing $requiredExpertTieringField"
                }
            }
            if ($expertTieringFields.ContainsKey("compose_prefill_mass_tiering")) {
                foreach ($requiredExpertTieringField in @(
                    "compose_router_open", "snapshot_generation", "snapshot_backing_entries",
                    "snapshot_backing_hits", "snapshot_backing_misses",
                    "snapshot_to_vram_bytes", "forbidden_cold_ssd_to_vram"
                )) {
                    if (-not $expertTieringFields.ContainsKey($requiredExpertTieringField)) {
                        throw "Expert tiering measurement failed: adaptive compose final line missing $requiredExpertTieringField"
                    }
                }
                $expertTieringComposeObserved = $true
                $expertTieringComposeFlag = [uint32]$expertTieringFields["compose_prefill_mass_tiering"]
                $expertTieringComposeRouterOpen = [uint32]$expertTieringFields["compose_router_open"]
                $expertTieringSnapshotGeneration = [uint64]$expertTieringFields["snapshot_generation"]
                $expertTieringSnapshotBackingEntries = [uint32]$expertTieringFields["snapshot_backing_entries"]
                $expertTieringSnapshotBackingHits = [uint64]$expertTieringFields["snapshot_backing_hits"]
                $expertTieringSnapshotBackingMisses = [uint64]$expertTieringFields["snapshot_backing_misses"]
                $expertTieringSnapshotToVramBytes = [uint64]$expertTieringFields["snapshot_to_vram_bytes"]
                $expertTieringForbiddenColdSsdToVram = [uint64]$expertTieringFields["forbidden_cold_ssd_to_vram"]
            }
            $expertTieringFinalObserved = $true
            $expertTieringModeObserved = $expertTieringFields["mode"]
            $expertTieringPolicyObserved = $expertTieringFields["policy"]
            $expertTieringClockCalls = [uint32]$expertTieringFields["clock_calls"]
            $expertTieringReplacementBudget = [uint32]$expertTieringFields["replacement_budget"]
            $expertTieringReplacementBudgetBase = [uint32]$expertTieringFields["replacement_budget_base"]
            $expertTieringAdaptiveEnabled = ([uint32]$expertTieringFields["adaptive_budget"] -ne 0)
            $expertTieringAdaptiveCurrent = [uint32]$expertTieringFields["adaptive_current_budget"]
            $expertTieringAdaptiveMin = [uint32]$expertTieringFields["adaptive_min"]
            $expertTieringAdaptiveMax = [uint32]$expertTieringFields["adaptive_max"]
            $expertTieringAdaptiveStep = [uint32]$expertTieringFields["adaptive_step"]
            $expertTieringAdaptivePressureThreshold = [uint32]$expertTieringFields["adaptive_pressure_threshold"]
            $expertTieringAdaptiveUps = [uint64]$expertTieringFields["adaptive_ups"]
            $expertTieringAdaptiveDowns = [uint64]$expertTieringFields["adaptive_downs"]
            $expertTieringAdaptivePressureEpochs = [uint64]$expertTieringFields["adaptive_pressure_epochs"]
            $expertTieringAdaptiveQuietEpochs = [uint64]$expertTieringFields["adaptive_quiet_epochs"]
            $expertTieringAdaptiveLastSkipDelta = [uint64]$expertTieringFields["adaptive_last_budget_skips_delta"]
            $expertTieringAdaptiveLastReplacementDelta = [uint64]$expertTieringFields["adaptive_last_replacements_delta"]
            $expertTieringMinFrequency = [uint32]$expertTieringFields["min_frequency"]
            $expertTieringHysteresis = [double]::Parse($expertTieringFields["hysteresis"], [Globalization.CultureInfo]::InvariantCulture)
            $expertTieringCalls = [uint64]$expertTieringFields["calls"]; $expertTieringSelected = [uint64]$expertTieringFields["selected"]
            $expertTieringCold = [uint64]$expertTieringFields["cold"]; $expertTieringRamHits = [uint64]$expertTieringFields["ram_hits"]
            $expertTieringVramHits = [uint64]$expertTieringFields["vram_hits"]; $expertTieringColdToRam = [uint64]$expertTieringFields["cold_to_ram"]
            $expertTieringColdToVram = [uint64]$expertTieringFields["cold_to_vram"]; $expertTieringRamToWarm = [uint64]$expertTieringFields["ram_to_warm"]
            $expertTieringVramPromotions = [uint64]$expertTieringFields["vram_promotions"]; $expertTieringVramDemotions = [uint64]$expertTieringFields["vram_demotions"]
            $expertTieringRamEvictions = [uint64]$expertTieringFields["ram_evictions"]; $expertTieringRamAdmitSkips = [uint64]$expertTieringFields["ram_admit_skips"]
            $expertTieringGeneralBackingReclaims = [uint64]$expertTieringFields["general_backing_reclaims"]
            $expertTieringTransient = [uint64]$expertTieringFields["transient"]; $expertTieringFailures = [uint64]$expertTieringFields["failures"]
            $expertTieringSsdBytes = [uint64]$expertTieringFields["ssd_bytes"]; $expertTieringRamH2DBytes = [uint64]$expertTieringFields["ram_h2d_bytes"]
            $expertTieringPolicyEpochs = [uint64]$expertTieringFields["policy_epochs"]
            $expertTieringPolicyFreePromotions = [uint64]$expertTieringFields["policy_free_promotions"]
            $expertTieringPolicyReplacements = [uint64]$expertTieringFields["policy_replacements"]
            $expertTieringPolicyMinFrequencySkips = [uint64]$expertTieringFields["policy_min_frequency_skips"]
            $expertTieringPolicyBudgetSkips = [uint64]$expertTieringFields["policy_budget_skips"]
            $expertTieringPolicyScoreSkips = [uint64]$expertTieringFields["policy_score_skips"]
            $expertTieringStatesSsd = [uint32]$expertTieringFields["states_ssd"]; $expertTieringStatesProbation = [uint32]$expertTieringFields["states_probation"]
            $expertTieringStatesWarm = [uint32]$expertTieringFields["states_warm"]; $expertTieringStatesVram = [uint32]$expertTieringFields["states_vram"]
            $expertTieringMassSum = [double]::Parse($expertTieringFields["mass_sum"], [Globalization.CultureInfo]::InvariantCulture)
            $expertTieringLfruTop = [double]::Parse($expertTieringFields["lfru_top"], [Globalization.CultureInfo]::InvariantCulture)
        } elseif ($expertTieringFinalLine -match $expertTieringComposeFinalPattern) {
            $expertTieringFinalObserved = $true
            $expertTieringComposeObserved = $true
            $expertTieringModeObserved = $Matches[1]
            $expertTieringPolicyObserved = $Matches[2]
            $expertTieringComposeFlag = [uint32]$Matches[3]
            $expertTieringComposeRouterOpen = [uint32]$Matches[4]
            $expertTieringSnapshotGeneration = [uint64]$Matches[5]
            $expertTieringSnapshotBackingEntries = [uint32]$Matches[6]
            $expertTieringSnapshotBackingHits = [uint64]$Matches[7]
            $expertTieringSnapshotBackingMisses = [uint64]$Matches[8]
            $expertTieringSnapshotToVramBytes = [uint64]$Matches[9]
            $expertTieringForbiddenColdSsdToVram = [uint64]$Matches[10]
            $expertTieringGeneralBackingReclaims = [uint64]$Matches[11]
            $expertTieringClockCalls = [uint32]$Matches[12]; $expertTieringReplacementBudget = [uint32]$Matches[13]
            $expertTieringMinFrequency = [uint32]$Matches[14]
            $expertTieringHysteresis = [double]::Parse($Matches[15], [Globalization.CultureInfo]::InvariantCulture)
            $expertTieringCalls = [uint64]$Matches[16]; $expertTieringSelected = [uint64]$Matches[17]
            $expertTieringCold = [uint64]$Matches[18]; $expertTieringRamHits = [uint64]$Matches[19]
            $expertTieringVramHits = [uint64]$Matches[20]; $expertTieringColdToRam = [uint64]$Matches[21]
            $expertTieringColdToVram = [uint64]$Matches[22]; $expertTieringRamToWarm = [uint64]$Matches[23]
            $expertTieringVramPromotions = [uint64]$Matches[24]; $expertTieringVramDemotions = [uint64]$Matches[25]
            $expertTieringRamEvictions = [uint64]$Matches[26]; $expertTieringRamAdmitSkips = [uint64]$Matches[27]
            $expertTieringTransient = [uint64]$Matches[28]; $expertTieringFailures = [uint64]$Matches[29]
            $expertTieringSsdBytes = [uint64]$Matches[30]; $expertTieringRamH2DBytes = [uint64]$Matches[31]
            $expertTieringPolicyEpochs = [uint64]$Matches[32]
            $expertTieringPolicyFreePromotions = [uint64]$Matches[33]
            $expertTieringPolicyReplacements = [uint64]$Matches[34]
            $expertTieringPolicyMinFrequencySkips = [uint64]$Matches[35]
            $expertTieringPolicyBudgetSkips = [uint64]$Matches[36]
            $expertTieringPolicyScoreSkips = [uint64]$Matches[37]
            $expertTieringStatesSsd = [uint32]$Matches[38]; $expertTieringStatesProbation = [uint32]$Matches[39]
            $expertTieringStatesWarm = [uint32]$Matches[40]; $expertTieringStatesVram = [uint32]$Matches[41]
            $expertTieringMassSum = [double]::Parse($Matches[42], [Globalization.CultureInfo]::InvariantCulture)
            $expertTieringLfruTop = [double]::Parse($Matches[43], [Globalization.CultureInfo]::InvariantCulture)
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
            $expertTieringGeneralBackingReclaims = [uint64]$Matches[19]
            $expertTieringTransient = [uint64]$Matches[20]; $expertTieringFailures = [uint64]$Matches[21]
            $expertTieringSsdBytes = [uint64]$Matches[22]; $expertTieringRamH2DBytes = [uint64]$Matches[23]
            $expertTieringPolicyEpochs = [uint64]$Matches[24]
            $expertTieringPolicyFreePromotions = [uint64]$Matches[25]
            $expertTieringPolicyReplacements = [uint64]$Matches[26]
            $expertTieringPolicyMinFrequencySkips = [uint64]$Matches[27]
            $expertTieringPolicyBudgetSkips = [uint64]$Matches[28]
            $expertTieringPolicyScoreSkips = [uint64]$Matches[29]
            $expertTieringStatesSsd = [uint32]$Matches[30]; $expertTieringStatesProbation = [uint32]$Matches[31]
            $expertTieringStatesWarm = [uint32]$Matches[32]; $expertTieringStatesVram = [uint32]$Matches[33]
            $expertTieringMassSum = [double]::Parse($Matches[34], [Globalization.CultureInfo]::InvariantCulture)
            $expertTieringLfruTop = [double]::Parse($Matches[35], [Globalization.CultureInfo]::InvariantCulture)
        }
    }
    $prefillVramSeedLines = @($lines | Where-Object { $_ -match "^\s*ds4: \[prefill-vram-seed\] " })
    $prefillVramSeedGlobalLines = @($lines | Where-Object { $_ -match "^\s*ds4: \[prefill-vram-seed-global\] " })
    $prefillVramSeedLineCount = $prefillVramSeedLines.Count
    $prefillVramSeedGlobalLineCount = $prefillVramSeedGlobalLines.Count
    if ($prefillVramSeedLineCount -gt 0 -and $prefillVramSeedGlobalLineCount -gt 0) {
        throw "Prefill VRAM seed measurement failed: per-layer and global telemetry both observed"
    }
    if ($prefillVramSeedLineCount -gt 0) {
        if ($prefillVramSeedLineCount -ne 1) {
            throw "Prefill VRAM seed measurement failed: expected exactly one telemetry line"
        }
        $prefillVramSeedPattern = "^ds4: \[prefill-vram-seed\] result=(ok|failed) reason=([a-z0-9_-]+) requested_per_layer=(\d+) layers=(\d+) entries=(\d+) bytes=(\d+) seconds=([0-9.]+) failures=(\d+) prior_mass=([0-9.eE+-]+) semantics=([a-z0-9_-]+)$"
        $prefillVramSeedLine = $prefillVramSeedLines[0].Trim()
        if ($prefillVramSeedLine -notmatch $prefillVramSeedPattern) {
            throw "Prefill VRAM seed measurement failed: telemetry format mismatch"
        }
        $prefillVramSeedObserved = $true
        $prefillVramSeedResult = $Matches[1]
        $prefillVramSeedReason = $Matches[2]
        $prefillVramSeedRequestedObserved = [uint32]$Matches[3]
        $prefillVramSeedLayers = [uint32]$Matches[4]
        $prefillVramSeedEntries = [uint32]$Matches[5]
        $prefillVramSeedBytes = [uint64]$Matches[6]
        $prefillVramSeedSeconds = [double]::Parse($Matches[7], [Globalization.CultureInfo]::InvariantCulture)
        $prefillVramSeedFailures = [uint32]$Matches[8]
        $prefillVramSeedPriorMass = [double]::Parse($Matches[9], [Globalization.CultureInfo]::InvariantCulture)
        $prefillVramSeedSemantics = $Matches[10]
    }
    if ($prefillVramSeedGlobalLineCount -gt 0) {
        if ($prefillVramSeedGlobalLineCount -ne 1) {
            throw "Prefill global VRAM seed measurement failed: expected exactly one telemetry line"
        }
        $prefillVramSeedGlobalPattern = "^ds4: \[prefill-vram-seed-global\] result=(ok|failed) reason=([a-z0-9_-]+) requested_total=(\d+) floor_per_layer=(\d+) layers=(\d+) entries=(\d+) bytes=(\d+) seconds=([0-9.]+) failures=(\d+) prior_mass=([0-9.eE+-]+) semantics=([a-z0-9_-]+)$"
        $prefillVramSeedGlobalLine = $prefillVramSeedGlobalLines[0].Trim()
        if ($prefillVramSeedGlobalLine -notmatch $prefillVramSeedGlobalPattern) {
            throw "Prefill global VRAM seed measurement failed: telemetry format mismatch"
        }
        $prefillVramSeedObserved = $true
        $prefillVramSeedGlobalObserved = $true
        $prefillVramSeedResult = $Matches[1]
        $prefillVramSeedReason = $Matches[2]
        $prefillVramSeedGlobalRequestedObserved = [uint32]$Matches[3]
        $prefillVramSeedGlobalFloorObserved = [uint32]$Matches[4]
        $prefillVramSeedLayers = [uint32]$Matches[5]
        $prefillVramSeedEntries = [uint32]$Matches[6]
        $prefillVramSeedBytes = [uint64]$Matches[7]
        $prefillVramSeedSeconds = [double]::Parse($Matches[8], [Globalization.CultureInfo]::InvariantCulture)
        $prefillVramSeedFailures = [uint32]$Matches[9]
        $prefillVramSeedPriorMass = [double]::Parse($Matches[10], [Globalization.CultureInfo]::InvariantCulture)
        $prefillVramSeedSemantics = $Matches[11]
    }
    if ($PrefillVramSeedPerLayer -gt 0) {
        $expectedPrefillVramSeedEntries = 40 * $PrefillVramSeedPerLayer
        if (-not $prefillVramSeedObserved -or $prefillVramSeedResult -ne "ok" -or
            $prefillVramSeedReason -ne "ok" -or
            $prefillVramSeedRequestedObserved -ne $PrefillVramSeedPerLayer -or
            $prefillVramSeedLayers -ne 40 -or
            $prefillVramSeedEntries -ne $expectedPrefillVramSeedEntries -or
            $prefillVramSeedBytes -le 0 -or $prefillVramSeedFailures -ne 0 -or
            $prefillVramSeedPriorMass -le 0.0 -or
            $prefillVramSeedSemantics -ne "request-scoped-top-per-layer") {
            throw "PrefillVramSeedPerLayer was requested but successful exact seed telemetry was not observed"
        }
    } elseif ($PrefillVramSeedTotal -gt 0) {
        if (-not $prefillVramSeedGlobalObserved -or
            $prefillVramSeedResult -ne "ok" -or
            $prefillVramSeedReason -ne "ok" -or
            $prefillVramSeedGlobalRequestedObserved -ne $PrefillVramSeedTotal -or
            $prefillVramSeedGlobalFloorObserved -ne $PrefillVramSeedFloorPerLayer -or
            $prefillVramSeedLayers -ne 40 -or
            $prefillVramSeedEntries -ne $PrefillVramSeedTotal -or
            $prefillVramSeedBytes -le 0 -or $prefillVramSeedFailures -ne 0 -or
            $prefillVramSeedPriorMass -le 0.0 -or
            $prefillVramSeedSemantics -ne "request-scoped-global-mass") {
            throw "PrefillVramSeedTotal was requested but successful global seed telemetry was not observed"
        }
    } elseif ($prefillVramSeedLineCount -ne 0 -or
              $prefillVramSeedGlobalLineCount -ne 0) {
        throw "Prefill VRAM seed activated while not requested"
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
    $gpuRoutesLines = @($lines | Where-Object { $_ -match "\[gpu-resident-routes\] final" })
    $gpuRoutesLine = $gpuRoutesLines | Select-Object -Last 1
    $gpuRoutesWorkerMsWeighted = 0.0
    $gpuRoutesResolveMsWeighted = 0.0
    $gpuRoutesWaitMsWeighted = 0.0
    foreach ($currentGpuRoutesLine in $gpuRoutesLines) {
        if ($currentGpuRoutesLine -notmatch "calls=(\d+) split_calls=(\d+) all_hit=(\d+) worker_jobs=(\d+) miss_experts=(\d+) errors=(\d+) worker=([0-9.]+)ms/job resolve=([0-9.]+)ms/call wait=([0-9.]+)ms/call queries=(\d+) default_sync=(\d+) no_default_sync=(\d+)") {
            throw "GPU-resident route summary format mismatch: $currentGpuRoutesLine"
        }
        $gpuRoutesObserved = $true
        $currentCalls = [long]$Matches[1]
        $currentWorkerJobs = [long]$Matches[4]
        $gpuRoutesCalls += $currentCalls
        $gpuRoutesSplitCalls += [long]$Matches[2]
        $gpuRoutesAllHit += [long]$Matches[3]
        $gpuRoutesWorkerJobs += $currentWorkerJobs
        $gpuRoutesMissExperts += [long]$Matches[5]
        $gpuRoutesErrors += [long]$Matches[6]
        $gpuRoutesWorkerMsWeighted += [double]$Matches[7] * $currentWorkerJobs
        $gpuRoutesResolveMsWeighted += [double]$Matches[8] * $currentCalls
        $gpuRoutesWaitMsWeighted += [double]$Matches[9] * $currentCalls
        $gpuRoutesQueries += [long]$Matches[10]
        $gpuRoutesDefaultSyncCalls += [long]$Matches[11]
        $gpuRoutesNoDefaultSyncCalls += [long]$Matches[12]

        if ($currentGpuRoutesLine -match "cache_count=(\d+) cache_calls=(\d+) cache_hits=(\d+) cache_misses=(\d+) cache_admissions=(\d+) cache_evictions=(\d+) direct_loads=(\d+)") {
            $gpuRoutesCacheCount = [long]$Matches[1]
            $gpuRoutesCacheCalls += [long]$Matches[2]
            $gpuRoutesCacheHits += [long]$Matches[3]
            $gpuRoutesCacheMisses += [long]$Matches[4]
            $gpuRoutesCacheAdmissions += [long]$Matches[5]
            $gpuRoutesCacheEvictions += [long]$Matches[6]
            $gpuRoutesCacheDirectLoads += [long]$Matches[7]
        }
        foreach ($packedCopyField in @(
            "packed_copy_requested",
            "packed_copy_experts",
            "packed_copy_submissions",
            "packed_copy_bytes",
            "legacy_copy_submissions")) {
            if ($currentGpuRoutesLine -match ($packedCopyField + "=(\d+)")) {
                switch ($packedCopyField) {
                    "packed_copy_requested" {
                        $currentPackedRequested = [long]$Matches[1]
                        if ($currentPackedRequested -ne $(if ($RoutePackedCopy) { 1 } else { 0 })) {
                            throw "RoutePackedCopy runtime state changed across requests"
                        }
                        $gpuRoutesPackedCopyRequested = $currentPackedRequested
                    }
                    "packed_copy_experts" { $gpuRoutesPackedCopyExperts += [long]$Matches[1] }
                    "packed_copy_submissions" { $gpuRoutesPackedCopySubmissions += [long]$Matches[1] }
                    "packed_copy_bytes" { $gpuRoutesPackedCopyBytes += [long]$Matches[1] }
                    "legacy_copy_submissions" { $gpuRoutesLegacyCopySubmissions += [long]$Matches[1] }
                }
            }
        }
        foreach ($splitFusedField in @(
            "split_fused_calls",
            "split_fused_hits",
            "split_fused_misses",
            "split_fused_miss_scratch_bytes_avoided",
            "split_fused_sum_read_bytes_avoided")) {
            if ($currentGpuRoutesLine -match ($splitFusedField + "=(\d+)")) {
                switch ($splitFusedField) {
                    "split_fused_calls" { $splitFusedCalls += [long]$Matches[1] }
                    "split_fused_hits" { $splitFusedHits += [long]$Matches[1] }
                    "split_fused_misses" { $splitFusedMisses += [long]$Matches[1] }
                    "split_fused_miss_scratch_bytes_avoided" { $splitFusedMissScratchBytesAvoided += [long]$Matches[1] }
                    "split_fused_sum_read_bytes_avoided" { $splitFusedSumReadBytesAvoided += [long]$Matches[1] }
                }
            }
        }
    }
    if ($gpuRoutesWorkerJobs -gt 0) {
        $gpuRoutesWorkerMs = $gpuRoutesWorkerMsWeighted / $gpuRoutesWorkerJobs
    }
    if ($gpuRoutesCalls -gt 0) {
        $gpuRoutesResolveMs = $gpuRoutesResolveMsWeighted / $gpuRoutesCalls
        $gpuRoutesWaitMs = $gpuRoutesWaitMsWeighted / $gpuRoutesCalls
    }
    if ($ComposePrefillMassTiering -and -not $Q1_0SnapshotBacking -and
        $gpuRoutesLines.Count -ne $requestCountExpected) {
        throw "GPU-resident route summary count differs from request count"
    }
    $splitFusedObserved = ($splitFusedCalls -gt 0)
    if ($SplitHitMiss -and (-not $gpuRoutesObserved -or $gpuRoutesSplitCalls -le 0)) {
        throw "SplitHitMiss was requested but the runtime did not report any split calls"
    }
    if ($gpuRoutesObserved -and
        ($gpuRoutesDefaultSyncCalls + $gpuRoutesNoDefaultSyncCalls) -ne $gpuRoutesCalls) {
        throw "GPU-resident route sync accounting does not match route calls"
    }
    if ($RouteNoDefaultSync) {
        if (-not $gpuRoutesObserved -or $gpuRoutesCalls -le 0 -or
            $gpuRoutesDefaultSyncCalls -ne 0 -or
            $gpuRoutesNoDefaultSyncCalls -ne $gpuRoutesCalls) {
            throw "RouteNoDefaultSync was requested but not observed on every route call"
        }
    } elseif ($gpuRoutesNoDefaultSyncCalls -ne 0) {
        throw "RouteNoDefaultSync activated while not requested"
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
    $arenaCapLine = $lines | Where-Object { $_ -match "^\s*ds4: \[arena-cap\] " } | Select-Object -Last 1
    if ($arenaCapLine) {
        $arenaCapSsdPattern = "^ds4: \[arena-cap\] requested_gib=([0-9.]+) min_available_gib=([0-9.]+) available_before_gib=(-?[0-9.]+) requested_bytes=(\d+) requested_slots=(\d+) chosen_bytes=(\d+) chosen_slots=(\d+) pageable_bytes=(\d+) pageable_slots=(\d+) total_slots=(\d+) ring_slots=(\d+) host_budget_bytes=(\d+) ssd_wrap=1 capped=(0|1) result=(ready|disabled) reason=([a-z-]+)$"
        $arenaCapPattern = "^ds4: \[arena-cap\] requested_gib=([0-9.]+) min_available_gib=([0-9.]+) available_before_gib=(-?[0-9.]+) requested_bytes=(\d+) requested_slots=(\d+) chosen_bytes=(\d+) chosen_slots=(\d+) pageable_bytes=(\d+) pageable_slots=(\d+) total_slots=(\d+) capped=(0|1) result=(ready|disabled) reason=([a-z-]+)$"
        if ($arenaCapLine -match $arenaCapSsdPattern) {
            $arenaCapSsdWrap = $true
            $arenaCapObserved = $true
            $arenaCapRequestedGiB = [double]::Parse($Matches[1], [Globalization.CultureInfo]::InvariantCulture)
            $arenaCapMinAvailableGiB = [double]::Parse($Matches[2], [Globalization.CultureInfo]::InvariantCulture)
            $arenaCapAvailableBeforeGiB = [double]::Parse($Matches[3], [Globalization.CultureInfo]::InvariantCulture)
            $arenaCapRequestedBytes = [long]$Matches[4]
            $arenaCapRequestedSlots = [long]$Matches[5]
            $arenaCapChosenBytes = [long]$Matches[6]
            $arenaCapChosenSlots = [long]$Matches[7]
            $arenaCapPageableBytes = [long]$Matches[8]
            $arenaCapPageableSlots = [long]$Matches[9]
            $arenaCapTotalSlots = [long]$Matches[10]
            $arenaCapRingSlots = [long]$Matches[11]
            $arenaCapHostBudgetBytes = [long]$Matches[12]
            $arenaCapCapped = ($Matches[13] -eq "1")
            $arenaCapResult = $Matches[14]
            $arenaCapReason = $Matches[15]
        } elseif ($arenaCapLine -notmatch $arenaCapPattern) {
            throw "Dynamic arena cap line format mismatch: $arenaCapLine"
        } else {
            $arenaCapObserved = $true
            $arenaCapRequestedGiB = [double]::Parse($Matches[1], [Globalization.CultureInfo]::InvariantCulture)
            $arenaCapMinAvailableGiB = [double]::Parse($Matches[2], [Globalization.CultureInfo]::InvariantCulture)
            $arenaCapAvailableBeforeGiB = [double]::Parse($Matches[3], [Globalization.CultureInfo]::InvariantCulture)
            $arenaCapRequestedBytes = [long]$Matches[4]
            $arenaCapRequestedSlots = [long]$Matches[5]
            $arenaCapChosenBytes = [long]$Matches[6]
            $arenaCapChosenSlots = [long]$Matches[7]
            $arenaCapPageableBytes = [long]$Matches[8]
            $arenaCapPageableSlots = [long]$Matches[9]
            $arenaCapTotalSlots = [long]$Matches[10]
            $arenaCapCapped = ($Matches[11] -eq "1")
            $arenaCapResult = $Matches[12]
            $arenaCapReason = $Matches[13]
        }
    }
    $arenaReadyLine = $lines | Where-Object { $_ -match "CUDA dynamic arena ready" } | Select-Object -Last 1
    if ($arenaReadyLine -and $arenaReadyLine -match "CUDA dynamic arena ready pinned=([0-9.]+) GiB pageable=([0-9.]+) GiB total_slots=(\d+) pinned_slots=(\d+) pageable_slots=(\d+) ring_slots=(\d+).*bytes=(\d+) host_budget_bytes=(\d+) slot_bytes=(\d+)") {
        $arenaAllocatedSlots = [long]$Matches[3]
        $arenaAllocatedPinnedSlots = [long]$Matches[4]
        $arenaAllocatedPageableSlots = [long]$Matches[5]
        $arenaReadyRingSlots = [long]$Matches[6]
        $arenaAllocatedBytes = [long]$Matches[7]
        $arenaAllocatedTotalBytes = [long]$Matches[8]
        $arenaSlotBytes = [long]$Matches[9]
        $arenaAllocatedPageableBytes =
            $arenaAllocatedPageableSlots * $arenaSlotBytes
    } elseif ($arenaReadyLine -and $arenaReadyLine -match "CUDA dynamic arena ready pinned=([0-9.]+) GiB pageable=([0-9.]+) GiB total_slots=(\d+) pinned_slots=(\d+) pageable_slots=(\d+).*bytes=(\d+) slot_bytes=(\d+)") {
        $arenaAllocatedSlots = [long]$Matches[3]
        $arenaAllocatedPinnedSlots = [long]$Matches[4]
        $arenaAllocatedPageableSlots = [long]$Matches[5]
        $arenaAllocatedBytes = [long]$Matches[6]
        $arenaSlotBytes = [long]$Matches[7]
        $arenaAllocatedPageableBytes =
            $arenaAllocatedPageableSlots * $arenaSlotBytes
        $arenaAllocatedTotalBytes =
            $arenaAllocatedBytes + $arenaAllocatedPageableBytes
    } elseif ($arenaReadyLine -and $arenaReadyLine -match "CUDA dynamic arena ready [0-9.]+ GiB, (\d+) slots.*bytes=(\d+) slot_bytes=(\d+)") {
        $arenaAllocatedSlots = [long]$Matches[1]
        $arenaAllocatedPinnedSlots = $arenaAllocatedSlots
        $arenaAllocatedBytes = [long]$Matches[2]
        $arenaAllocatedTotalBytes = $arenaAllocatedBytes
        $arenaSlotBytes = [long]$Matches[3]
    }
    $prefillMassArmedLines = @($lines | Where-Object { $_ -match "\[prefill-mass\] armed" })
    $prefillMassArmedEventCount = $prefillMassArmedLines.Count
    $prefillMassArmedLine = $prefillMassArmedLines | Select-Object -Last 1
    if ($prefillMassArmedLine -and $prefillMassArmedLine -match "armed slots=(\d+) layers=(\d+)\.\.(\d+).*residency=([a-z-]+) policy=([a-z-]+)") {
        $prefillMassArmed = $true
        $prefillMassResidency = $Matches[4]; $prefillMassPolicy = $Matches[5]
    }
    $prefillMassFinalizeLines = @($lines | Where-Object { $_ -match "\[prefill-mass\] finalize layers=" })
    $prefillMassFinalizeEventCount = $prefillMassFinalizeLines.Count
    $prefillMassFinalizeLine = $prefillMassFinalizeLines | Select-Object -Last 1
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
    foreach ($prefillMassComposeLine in $prefillMassComposeLines) {
        if ($prefillMassComposeLine -match "hash_layers=(\d+) hash_seed_entries=(\d+) ranked_entries=(\d+) total_candidate=(\d+) capacity=(\d+) candidate_fnv1a64=([0-9a-f]{16})") {
            $prefillMassComposeObserved = $true
            $prefillMassComposeParsedCount++
            $prefillMassComposeHashLayers = [int]$Matches[1]
            $prefillMassComposeHashSeedEntries = [long]$Matches[2]
            $prefillMassComposeRankedEntries = [long]$Matches[3]
            $prefillMassComposeTotalCandidate = [long]$Matches[4]
            $prefillMassComposeCapacity = [long]$Matches[5]
            $prefillMassComposeCandidateFNV1A64 = $Matches[6]
            $prefillMassComposeFingerprints += $prefillMassComposeCandidateFNV1A64
        }
        if ($prefillMassComposeLine -match "sparse_skipped_ranked=(\d+)") {
            $prefillMassComposeSparseSkippedRanked = [long]$Matches[1]
        }
    }
    $prefillMassComposeMaskLines = @($lines | Where-Object { $_ -match "\[prefill-mass-compose-mask\] result=" })
    $prefillMassComposeMaskEventCount = $prefillMassComposeMaskLines.Count
    $prefillMassComposeMaskFailedCount = @($prefillMassComposeMaskLines | Where-Object { $_ -match "result=(failed|restore-failed)" }).Count
    $prefillMassComposeMaskAppliedLines = @($prefillMassComposeMaskLines | Where-Object { $_ -match "result=applied" })
    $prefillMassComposeMaskAppliedCount = $prefillMassComposeMaskAppliedLines.Count
    $prefillMassComposeMaskAppliedLine = $prefillMassComposeMaskAppliedLines | Select-Object -Last 1
    if ($prefillMassComposeMaskAppliedLine) {
        $hasMaskBase = $prefillMassComposeMaskAppliedLine -match "base=([a-z-]+)"
        if ($hasMaskBase) { $prefillMassComposeMaskBase = $Matches[1] }
        $hasExistingLayers = $prefillMassComposeMaskAppliedLine -match "existing_layers=(\d+)"
        if ($hasExistingLayers) {
            $prefillMassComposeMaskExistingLayers = [int]$Matches[1]
        }
        if ($prefillMassComposeMaskAppliedLine -match "semantics=([a-z-]+)") {
            $prefillMassComposeMaskSemantics = $Matches[1]
        } else {
            $prefillMassComposeMaskSemantics = "request-scoped-closed"
        }
        $prefillMassComposeMaskObserved = $hasMaskBase -and $hasExistingLayers
    }
    $prefillMassComposeMaskRestoreCount = @($prefillMassComposeMaskLines | Where-Object { $_ -match "result=restored" }).Count
    $prefillMassLayerStripeLines = @($lines | Where-Object { $_ -match "\[prefill-mass-layer-stripe\] result=" })
    $prefillMassLayerStripeEventCount = $prefillMassLayerStripeLines.Count
    $prefillMassLayerStripeFailedCount = @($prefillMassLayerStripeLines | Where-Object { $_ -match "result=failed" }).Count
    $prefillMassLayerStripeAppliedLine = $prefillMassLayerStripeLines | Where-Object { $_ -match "result=applied" } | Select-Object -Last 1
    if ($prefillMassLayerStripeAppliedLine -and $prefillMassLayerStripeAppliedLine -match "result=applied stride=(\d+) phase=(\d+) routed_layers=(\d+) full_layers=(\d+) partial_layers=(\d+) full_keep=(\d+) partial_keep_min=(\d+) partial_keep_max=(\d+) routed_candidate=(\d+) total_candidate=(\d+) capacity=(\d+) semantics=([a-z-]+)") {
        $prefillMassLayerStripeObserved = $true
        $prefillMassLayerStripeResult = "applied"
        $prefillMassLayerStripeStride = [int]$Matches[1]
        $prefillMassLayerStripePhase = [int]$Matches[2]
        $prefillMassLayerStripeRoutedLayers = [int]$Matches[3]
        $prefillMassLayerStripeFullLayers = [int]$Matches[4]
        $prefillMassLayerStripePartialLayers = [int]$Matches[5]
        $prefillMassLayerStripeFullKeep = [int]$Matches[6]
        $prefillMassLayerStripePartialKeepMin = [int]$Matches[7]
        $prefillMassLayerStripePartialKeepMax = [int]$Matches[8]
        $prefillMassLayerStripeRoutedCandidate = [long]$Matches[9]
        $prefillMassLayerStripeTotalCandidate = [long]$Matches[10]
        $prefillMassLayerStripeCapacity = [long]$Matches[11]
        $prefillMassLayerStripeSemantics = $Matches[12]
    } elseif ($prefillMassLayerStripeFailedCount -gt 0) {
        $prefillMassLayerStripeResult = "failed"
        $prefillMassLayerStripeFailedLine = $prefillMassLayerStripeLines | Where-Object { $_ -match "result=failed" } | Select-Object -Last 1
        if ($prefillMassLayerStripeFailedLine -match "reason=([a-z-]+)") {
            $prefillMassLayerStripeReason = $Matches[1]
        }
    }
    $prefillMassDecodeLines = @($lines | Where-Object { $_ -match "\[prefill-mass\] decode reason=request-end" })
    $prefillMassDecodeEventCount = $prefillMassDecodeLines.Count
    $prefillMassDecodeLine = $prefillMassDecodeLines | Select-Object -Last 1
    if ($prefillMassDecodeLine -and $prefillMassDecodeLine -match "tokens=(\d+) slots=(\d+) candidate_hits=(\d+) hit_rate=([0-9.]+) policy=([a-z-]+)") {
        $prefillMassDecodeTokens = [long]$Matches[1]
        $prefillMassDecodeSlots = [long]$Matches[2]
        $prefillMassDecodeHits = [long]$Matches[3]
        $prefillMassDecodeHitRate = [double]::Parse($Matches[4], [Globalization.CultureInfo]::InvariantCulture)
    }
    $prefillMassWrapLines = @($lines | Where-Object { $_ -match "\[prefill-mass-wrap\] result=" })
    $prefillMassWrapEventCount = $prefillMassWrapLines.Count
    foreach ($prefillMassWrapLine in $prefillMassWrapLines) {
        if ($prefillMassWrapLine -match "result=([a-z-]+) reason=([a-z-]+) candidate=(\d+) loads=(\d+) workers=(\d+) seconds=([0-9.]+) snapshot_before=(\d+) snapshot_after=(\d+) resident_before=(\d+) resident_after=(\d+) generation=(\d+) preloaded=(\d+) router=([a-z-]+) mask=([a-z-]+)") {
            $prefillMassWrapObserved = $true
            $prefillMassWrapResult = $Matches[1]; $prefillMassWrapReason = $Matches[2]
            $prefillMassWrapCandidate = [long]$Matches[3]; $prefillMassWrapLoads = [long]$Matches[4]
            $prefillMassWrapWorkers = [int]$Matches[5]
            $prefillMassWrapSeconds = [double]::Parse($Matches[6], [Globalization.CultureInfo]::InvariantCulture)
            $prefillMassWrapSnapshotBefore = [long]$Matches[7]; $prefillMassWrapSnapshotAfter = [long]$Matches[8]
            $prefillMassWrapResidentBefore = [long]$Matches[9]; $prefillMassWrapResidentAfter = [long]$Matches[10]
            $prefillMassWrapGeneration = [long]$Matches[11]; $prefillMassWrapPreloaded = [int]$Matches[12]
            $prefillMassWrapRouter = $Matches[13]; $prefillMassWrapMask = $Matches[14]
            $prefillMassWrapParsedEvents += [pscustomobject]@{
                result = $prefillMassWrapResult; reason = $prefillMassWrapReason
                candidate = $prefillMassWrapCandidate; loads = $prefillMassWrapLoads
                snapshot_before = $prefillMassWrapSnapshotBefore
                snapshot_after = $prefillMassWrapSnapshotAfter
                resident_before = $prefillMassWrapResidentBefore
                resident_after = $prefillMassWrapResidentAfter
                generation = $prefillMassWrapGeneration
                preloaded = $prefillMassWrapPreloaded
                router = $prefillMassWrapRouter; mask = $prefillMassWrapMask
            }
        }
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
    $arenaWrapProfileLines = @($lines | Where-Object { $_ -match "\[arena-wrap-profile\] result=" })
    $arenaWrapProfileLine = $arenaWrapProfileLines | Select-Object -Last 1
    foreach ($currentArenaWrapProfileLine in $arenaWrapProfileLines) {
        if ($currentArenaWrapProfileLine -notmatch "result=(published|failed) schedule=([^ ]+) source=([^ ]+) checksum=([^ ]+) loads=(\d+) workers=(\d+) begin=([0-9.]+) copy_checksum=([0-9.]+) finish=([0-9.]+) publish=([0-9.]+) total=([0-9.]+)") {
            throw "Arena WRAP profile format mismatch: $currentArenaWrapProfileLine"
        }
        $arenaWrapProfileObserved = $true
        $currentWrapResult = $Matches[1]
        $currentWrapSchedule = $Matches[2]
        $currentWrapSource = $Matches[3]
        $currentWrapChecksum = $Matches[4]
        if ($arenaWrapScheduleObserved -ne "not_observed" -and
            ($arenaWrapScheduleObserved -ne $currentWrapSchedule -or
             $arenaWrapSourceObserved -ne $currentWrapSource -or
             $arenaWrapChecksumObserved -ne $currentWrapChecksum)) {
            throw "Arena WRAP profile configuration changed across requests"
        }
        $arenaWrapProfileResult = $currentWrapResult
        $arenaWrapScheduleObserved = $currentWrapSchedule
        $arenaWrapSourceObserved = $currentWrapSource
        $arenaWrapChecksumObserved = $currentWrapChecksum
        $arenaWrapProfileLoads += [long]$Matches[5]
        $arenaWrapProfileWorkers = [math]::Max($arenaWrapProfileWorkers, [int]$Matches[6])
        $arenaWrapProfileBeginSeconds += [double]::Parse($Matches[7], [Globalization.CultureInfo]::InvariantCulture)
        $arenaWrapProfileCopyChecksumSeconds += [double]::Parse($Matches[8], [Globalization.CultureInfo]::InvariantCulture)
        $arenaWrapProfileFinishSeconds += [double]::Parse($Matches[9], [Globalization.CultureInfo]::InvariantCulture)
        $arenaWrapProfilePublishSeconds += [double]::Parse($Matches[10], [Globalization.CultureInfo]::InvariantCulture)
        $arenaWrapProfileTotalSeconds += [double]::Parse($Matches[11], [Globalization.CultureInfo]::InvariantCulture)
        if ($currentArenaWrapProfileLine -match "source_parts_copy=([0-9.]+) source_parts_checksum=([0-9.]+) parts=(\d+) copy_workers=(\d+) checksum_workers=(\d+)") {
            $arenaWrapSourcePartsCopySeconds += [double]::Parse($Matches[1], [Globalization.CultureInfo]::InvariantCulture)
            $arenaWrapSourcePartsChecksumSeconds += [double]::Parse($Matches[2], [Globalization.CultureInfo]::InvariantCulture)
            $arenaWrapPartCount += [long]$Matches[3]
            $arenaWrapCopyWorkers = [math]::Max($arenaWrapCopyWorkers, [int]$Matches[4])
            $arenaWrapChecksumWorkers += [int]$Matches[5]
        }
        if ($currentArenaWrapProfileLine -match "file_qd=(\d+) file_qd_observed=(\d+) file_submits=(\d+) file_completions=(\d+) file_failures=(\d+)") {
            $arenaWrapFileQDRequestedObserved = [int]$Matches[1]
            $arenaWrapFileQDObserved = [int]$Matches[2]
            $arenaWrapFileSubmits += [uint64]$Matches[3]
            $arenaWrapFileCompletions += [uint64]$Matches[4]
            $arenaWrapFileFailures += [uint32]$Matches[5]
        }
    }
    $arenaWrapPartProfileLine = $lines | Where-Object { $_ -match "\[arena-wrap-part-profile\] result=" } | Select-Object -Last 1
    if ($arenaWrapPartProfileLine -and $arenaWrapPartProfileLine -match "result=([^ ]+) phases=(\d+) workers=(\d+) parts=(\d+) bytes=(\d+) memcpy_sum=([0-9.]+) main_worker=([0-9.]+) join=([0-9.]+) phase_worker_active_min=([0-9.]+) phase_worker_active_max=([0-9.]+) phase_worker_parts_min=(\d+) phase_worker_parts_max=(\d+) slow_threshold_ms=([0-9.]+) slow_parts=(\d+) max_part_ms=([0-9.]+) max_part_bytes=(\d+) max_part_load=(\d+) max_part_cursor=(\d+) max_part_kind=([^ ]+) max_part_source=(\d+)") {
        $arenaWrapPartProfileObserved = $true
        $arenaWrapPartProfileResult = $Matches[1]
        $arenaWrapPartProfilePhases = [int]$Matches[2]
        $arenaWrapPartProfileWorkers = [int]$Matches[3]
        $arenaWrapPartProfileParts = [long]$Matches[4]
        $arenaWrapPartProfileBytes = [long]$Matches[5]
        $arenaWrapPartProfileMemcpySumSeconds = [double]::Parse($Matches[6], [Globalization.CultureInfo]::InvariantCulture)
        $arenaWrapPartProfileMainWorkerSeconds = [double]::Parse($Matches[7], [Globalization.CultureInfo]::InvariantCulture)
        $arenaWrapPartProfileJoinSeconds = [double]::Parse($Matches[8], [Globalization.CultureInfo]::InvariantCulture)
        $arenaWrapPartProfileWorkerActiveMinSeconds = [double]::Parse($Matches[9], [Globalization.CultureInfo]::InvariantCulture)
        $arenaWrapPartProfileWorkerActiveMaxSeconds = [double]::Parse($Matches[10], [Globalization.CultureInfo]::InvariantCulture)
        $arenaWrapPartProfileWorkerPartsMin = [long]$Matches[11]
        $arenaWrapPartProfileWorkerPartsMax = [long]$Matches[12]
        $arenaWrapPartProfileSlowThresholdMs = [double]::Parse($Matches[13], [Globalization.CultureInfo]::InvariantCulture)
        $arenaWrapPartProfileSlowParts = [long]$Matches[14]
        $arenaWrapPartProfileMaxPartMs = [double]::Parse($Matches[15], [Globalization.CultureInfo]::InvariantCulture)
        $arenaWrapPartProfileMaxPartBytes = [long]$Matches[16]
        $arenaWrapPartProfileMaxPartLoad = [long]$Matches[17]
        $arenaWrapPartProfileMaxPartCursor = [long]$Matches[18]
        $arenaWrapPartProfileMaxPartKind = $Matches[19]
        $arenaWrapPartProfileMaxPartSource = [long]$Matches[20]
    }
    $arenaWrapLayoutProfileLines = @($lines | Where-Object {
        $_ -match "^\s*ds4: \[arena-wrap-layout-profile\] "
    })
    $arenaWrapLayoutProfilePattern = "^ds4: \[arena-wrap-layout-profile\] result=ok phase=(gate|up|down) parts=(\d+) payload=(\d+) gaps=(\d+) overlaps=(\d+) gap_eq0=(\d+) gap_1_4k=(\d+) gap_4k_64k=(\d+) gap_64k_1m=(\d+) gap_gt1m=(\d+) t0_reads=(\d+) t0_bytes=(\d+) t4096_reads=(\d+) t4096_bytes=(\d+) t65536_reads=(\d+) t65536_bytes=(\d+) t1048576_reads=(\d+) t1048576_bytes=(\d+) page_size=(\d+) source_aligned=(\d+) bytes_aligned=(\d+) destination_aligned=(\d+)$"
    foreach ($arenaWrapLayoutProfileLine in $arenaWrapLayoutProfileLines) {
        if ($arenaWrapLayoutProfileLine -notmatch $arenaWrapLayoutProfilePattern) {
            throw "Arena WRAP layout profile line format mismatch: $arenaWrapLayoutProfileLine"
        }
        $arenaWrapLayoutProfileRows += [pscustomobject]@{
            result = "ok"
            phase = $Matches[1]
            parts = [uint64]$Matches[2]
            payload = [uint64]$Matches[3]
            gaps = [uint64]$Matches[4]
            overlaps = [uint64]$Matches[5]
            gap_eq0 = [uint64]$Matches[6]
            gap_1_4k = [uint64]$Matches[7]
            gap_4k_64k = [uint64]$Matches[8]
            gap_64k_1m = [uint64]$Matches[9]
            gap_gt1m = [uint64]$Matches[10]
            t0_reads = [uint64]$Matches[11]
            t0_bytes = [uint64]$Matches[12]
            t4096_reads = [uint64]$Matches[13]
            t4096_bytes = [uint64]$Matches[14]
            t65536_reads = [uint64]$Matches[15]
            t65536_bytes = [uint64]$Matches[16]
            t1048576_reads = [uint64]$Matches[17]
            t1048576_bytes = [uint64]$Matches[18]
            page_size = [uint32]$Matches[19]
            source_aligned = [uint64]$Matches[20]
            bytes_aligned = [uint64]$Matches[21]
            destination_aligned = [uint64]$Matches[22]
        }
    }
    $arenaWrapLayoutProfileObserved = ($arenaWrapLayoutProfileRows.Count -gt 0)
    $arenaWrapTrimLine = $lines | Where-Object { $_ -match "\[arena-wrap-trim\] result=" } | Select-Object -Last 1
    if ($arenaWrapTrimLine -and $arenaWrapTrimLine -match "result=([^ ]+) calls=(\d+) succeeded=(\d+) failed=(\d+) seconds=([0-9.]+) last_error=(\d+)") {
        $arenaWrapTrimObserved = $true
        $arenaWrapTrimResult = $Matches[1]
        $arenaWrapTrimCalls = [int]$Matches[2]
        $arenaWrapTrimSucceeded = [int]$Matches[3]
        $arenaWrapTrimFailed = [int]$Matches[4]
        $arenaWrapTrimSeconds = [double]::Parse($Matches[5], [Globalization.CultureInfo]::InvariantCulture)
        $arenaWrapTrimLastError = [long]$Matches[6]
    }
    $arenaWrapUnlockLines = @($lines | Where-Object {
        $_ -match "^\s*ds4: \[arena-wrap-source-unlock\] "
    })
    $arenaWrapUnlockPattern = "^ds4: \[arena-wrap-source-unlock\] result=([^ ]+) phase=([^ ]+)(?: waves=(\d+)(?: max_wave_bytes=(\d+))?)? parts=(\d+) ranges=(\d+) bytes_requested=(\d+) calls=(\d+) true=(\d+) error_not_locked=(\d+) failed=(\d+) seconds=([0-9.]+) available_before=(\d+) available_after=(\d+) working_set_before=(\d+) working_set_after=(\d+) page_fault_before=(\d+) page_fault_after=(\d+) read_transfer_before=(\d+) read_transfer_after=(\d+) last_error=(\d+)$"
    foreach ($arenaWrapUnlockLine in $arenaWrapUnlockLines) {
        if ($arenaWrapUnlockLine -notmatch $arenaWrapUnlockPattern) {
            throw "Arena WRAP source unlock line format mismatch: $arenaWrapUnlockLine"
        }
        $arenaWrapUnlockRows += [pscustomobject]@{
            result = $Matches[1]
            phase = $Matches[2]
            waves = if ($Matches[3]) { [uint32]$Matches[3] } else { [uint32]0 }
            max_wave_bytes = if ($Matches[4]) { [uint64]$Matches[4] } else { [uint64]0 }
            parts = [uint64]$Matches[5]
            ranges = [uint64]$Matches[6]
            bytes_requested = [uint64]$Matches[7]
            calls = [uint32]$Matches[8]
            true_count = [uint32]$Matches[9]
            error_not_locked = [uint32]$Matches[10]
            failed = [uint32]$Matches[11]
            seconds = [double]::Parse($Matches[12], [Globalization.CultureInfo]::InvariantCulture)
            available_before = [uint64]$Matches[13]
            available_after = [uint64]$Matches[14]
            working_set_before = [uint64]$Matches[15]
            working_set_after = [uint64]$Matches[16]
            page_fault_before = [uint64]$Matches[17]
            page_fault_after = [uint64]$Matches[18]
            read_transfer_before = [uint64]$Matches[19]
            read_transfer_after = [uint64]$Matches[20]
            last_error = [uint32]$Matches[21]
        }
    }
    $arenaWrapUnlockObserved = ($arenaWrapUnlockRows.Count -gt 0)
    $arenaWrapUnlockSummaryLine = $lines | Where-Object {
        $_ -match "\[arena-wrap-source-unlock-summary\] result="
    } | Select-Object -Last 1
    if ($arenaWrapUnlockSummaryLine -and
        $arenaWrapUnlockSummaryLine -match "result=([^ ]+) phases=(\d+) waves=(\d+) wave_gib=([0-9.]+) max_wave_bytes=(\d+) parts=(\d+) ranges=(\d+) bytes_requested=(\d+) calls=(\d+) true=(\d+) error_not_locked=(\d+) failed=(\d+) seconds=([0-9.]+)") {
        $arenaWrapUnlockSummaryObserved = $true
        $arenaWrapUnlockSummaryResult = $Matches[1]
        $arenaWrapUnlockSummaryPhases = [uint32]$Matches[2]
        $arenaWrapUnlockSummaryWaves = [uint32]$Matches[3]
        $arenaWrapUnlockSummaryWaveGiB = [double]::Parse($Matches[4], [Globalization.CultureInfo]::InvariantCulture)
        $arenaWrapUnlockSummaryMaxWaveBytes = [uint64]$Matches[5]
        $arenaWrapUnlockSummaryParts = [uint64]$Matches[6]
        $arenaWrapUnlockSummaryRanges = [uint64]$Matches[7]
        $arenaWrapUnlockSummaryBytesRequested = [uint64]$Matches[8]
        $arenaWrapUnlockSummaryCalls = [uint32]$Matches[9]
        $arenaWrapUnlockSummaryTrue = [uint32]$Matches[10]
        $arenaWrapUnlockSummaryErrorNotLocked = [uint32]$Matches[11]
        $arenaWrapUnlockSummaryFailed = [uint32]$Matches[12]
        $arenaWrapUnlockSummarySeconds = [double]::Parse($Matches[13], [Globalization.CultureInfo]::InvariantCulture)
    } elseif ($arenaWrapUnlockSummaryLine -and
        $arenaWrapUnlockSummaryLine -match "result=([^ ]+) phases=(\d+) parts=(\d+) ranges=(\d+) bytes_requested=(\d+) calls=(\d+) true=(\d+) error_not_locked=(\d+) failed=(\d+) seconds=([0-9.]+)") {
        $arenaWrapUnlockSummaryObserved = $true
        $arenaWrapUnlockSummaryResult = $Matches[1]
        $arenaWrapUnlockSummaryPhases = [uint32]$Matches[2]
        $arenaWrapUnlockSummaryWaves = 0
        $arenaWrapUnlockSummaryWaveGiB = 0.0
        $arenaWrapUnlockSummaryMaxWaveBytes = 0
        $arenaWrapUnlockSummaryParts = [uint64]$Matches[3]
        $arenaWrapUnlockSummaryRanges = [uint64]$Matches[4]
        $arenaWrapUnlockSummaryBytesRequested = [uint64]$Matches[5]
        $arenaWrapUnlockSummaryCalls = [uint32]$Matches[6]
        $arenaWrapUnlockSummaryTrue = [uint32]$Matches[7]
        $arenaWrapUnlockSummaryErrorNotLocked = [uint32]$Matches[8]
        $arenaWrapUnlockSummaryFailed = [uint32]$Matches[9]
        $arenaWrapUnlockSummarySeconds = [double]::Parse($Matches[10], [Globalization.CultureInfo]::InvariantCulture)
    } elseif ($arenaWrapUnlockSummaryLine) {
        throw "Arena WRAP source unlock summary format mismatch: $arenaWrapUnlockSummaryLine"
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
    if ($arenaFinalLine -and $arenaFinalLine -match "\[arena\] final hits=(\d+) pinned_hits=(\d+) pageable_hits=(\d+) misses=(\d+) fatal=(\d+) uploaded=([0-9.]+) GiB pinned_uploaded=([0-9.]+) GiB pageable_uploaded=([0-9.]+) GiB backing=q1_0") {
        $arenaFinalObserved = $true
        $arenaFinalHits = [long]$Matches[1]
        $arenaFinalPinnedHits = [long]$Matches[2]
        $arenaFinalPageableHits = [long]$Matches[3]
        $arenaFinalMisses = [long]$Matches[4]
        $arenaFinalFatal = [long]$Matches[5]
        $arenaFinalUploadedGiB = [double]::Parse($Matches[6], [Globalization.CultureInfo]::InvariantCulture)
        $arenaFinalPinnedUploadedGiB = [double]::Parse($Matches[7], [Globalization.CultureInfo]::InvariantCulture)
        $arenaFinalPageableUploadedGiB = [double]::Parse($Matches[8], [Globalization.CultureInfo]::InvariantCulture)
    } elseif ($arenaFinalLine -and $arenaFinalLine -match "\[arena\] final hits=(\d+) misses=(\d+) fatal=(\d+) uploaded=([0-9.]+) GiB") {
        $arenaFinalObserved = $true
        $arenaFinalHits = [long]$Matches[1]; $arenaFinalMisses = [long]$Matches[2]
        $arenaFinalFatal = [long]$Matches[3]
        $arenaFinalUploadedGiB = [double]::Parse($Matches[4], [Globalization.CultureInfo]::InvariantCulture)
    }
}
if ($RoutePackedCopy) {
    if (-not $gpuRoutesObserved -or
        $gpuRoutesPackedCopyRequested -ne 1 -or
        $gpuRoutesPackedCopyExperts -le 0 -or
        $gpuRoutesPackedCopySubmissions -ne
            (2 * $gpuRoutesPackedCopyExperts) -or
        $gpuRoutesPackedCopyBytes -le 0 -or
        $gpuRoutesLegacyCopySubmissions -ne 0) {
        throw "RoutePackedCopy was requested but heterogeneous packed route accounting did not prove exactly two submissions per expert with no legacy copies"
    }
} elseif ($gpuRoutesPackedCopyRequested -ne 0 -or
    $gpuRoutesPackedCopyExperts -ne 0 -or
    $gpuRoutesPackedCopySubmissions -ne 0 -or
    $gpuRoutesPackedCopyBytes -ne 0) {
    throw "RoutePackedCopy activated while not requested"
}
if ($runtimeTelemetry.contamination_abort_observed) {
    throw "Runtime telemetry aborted a contaminated measurement (memory, paging, residency, or disk-pressure gate)"
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

$q1_0SidecarLogText = ""
if (Test-Path -LiteralPath $stderrLog) {
    $q1_0SidecarLogText += (Get-Content -LiteralPath $stderrLog -Raw)
}
if (Test-Path -LiteralPath $stdoutLog) {
    $q1_0SidecarLogText += "`n" + (Get-Content -LiteralPath $stdoutLog -Raw)
}
$nestedResidualRuntimeObserved = $false
$nestedResidualRouterCalls = [UInt64]0
$nestedResidualCacheHits = [UInt64]0
$nestedResidualCacheMisses = [UInt64]0
$nestedResidualPreads = [UInt64]0
$nestedResidualBytes = [UInt64]0
$nestedResidualReconstructed = [UInt64]0
$nestedResidualMismatches = [UInt64]0
$nestedResidualH2DBytes = [UInt64]0
$nestedResidualFailures = [UInt64]0
$nestedResidualVramRuntimeObserved = $false
$nestedResidualVramRawSummary = ""
$nestedResidualVramRouteCalls = [UInt64]0
$nestedResidualVramHits = [UInt64]0
$nestedResidualVramMisses = [UInt64]0
$nestedResidualVramHostFills = [UInt64]0
$nestedResidualVramHostBytes = [UInt64]0
$nestedResidualVramH2DBytes = [UInt64]0
$nestedResidualVramFailures = [UInt64]0
$nestedResidualAllLayerFirstLayer = 0
$nestedResidualAllLayerLastLayer = 0
$nestedResidualAllLayerCount = 0
$nestedResidualBaseStorageRawSummary = ""
$nestedResidualBasePinnedEntries = [UInt64]0
$nestedResidualBasePinnedBytes = [UInt64]0
$nestedResidualBasePinnedHits = [UInt64]0
$nestedResidualBasePinnedH2DBytes = [UInt64]0
$nestedResidualBasePageableEntries = [UInt64]0
$nestedResidualBasePageableBytes = [UInt64]0
$nestedResidualBasePageableHits = [UInt64]0
$nestedResidualBasePageableH2DBytes = [UInt64]0
$nestedResidualStorageInvariantFailures = [UInt64]0
$nestedResidualCachePageableRawSummary = ""
$nestedResidualCachePinnedEntries = [UInt64]0
$nestedResidualCachePinnedBytes = [UInt64]0
$nestedResidualCachePinnedHits = [UInt64]0
$nestedResidualCachePinnedH2DBytes = [UInt64]0
$nestedResidualCachePageableEntries = [UInt64]0
$nestedResidualCachePageableBytes = [UInt64]0
$nestedResidualCachePageableHits = [UInt64]0
$nestedResidualCachePageableH2DBytes = [UInt64]0
$nestedResidualCachePageableCachedJoinCalls = [UInt64]0
$nestedResidualCacheLayerPartitioned = [UInt64]0
$nestedResidualCacheLayerSlotsMin = [UInt64]0
$nestedResidualCacheLayerSlotsMax = [UInt64]0
$nestedResidualCachePageableInvariantFailures = [UInt64]0
$nestedResidualGpuJoinObserved = $false
$nestedResidualGpuJoinRawSummary = ""
$nestedResidualGpuJoinRequestedRuntime = 0
$nestedResidualGpuJoinObservedRuntime = 0
$nestedResidualGpuJoinCalls = [UInt64]0
$nestedResidualGpuJoinBlocks = [UInt64]0
$nestedResidualGpuJoinBaseH2DBytes = [UInt64]0
$nestedResidualGpuJoinResidualH2DBytes = [UInt64]0
$nestedResidualGpuJoinNativeH2DBytes = [UInt64]0
$nestedResidualGpuJoinSeconds = [double]0
$nestedResidualGpuJoinWaitCalls = [UInt64]0
$nestedResidualGpuJoinWaitSeconds = [double]0
$nestedResidualGpuJoinVerifyCalls = [UInt64]0
$nestedResidualGpuJoinVerifyBytes = [UInt64]0
$nestedResidualGpuJoinVerifySeconds = [double]0
$nestedResidualGpuJoinVerifyMismatches = [UInt64]0
$nestedResidualGpuJoinFailures = [UInt64]0
$nestedResidualGpuJoinCpuReconstructCalls = [UInt64]0
$nestedResidualGpuJoinResidualCacheObserved = $false
$nestedResidualGpuJoinResidualCacheRawSummary = ""
$nestedResidualGpuJoinResidualCacheEnabledRuntime = 0
$nestedResidualGpuJoinResidualCacheHits = [UInt64]0
$nestedResidualGpuJoinResidualCacheMisses = [UInt64]0
$nestedResidualGpuJoinResidualCacheEvictions = [UInt64]0
$nestedResidualGpuJoinResidualCacheEntries = [UInt64]0
$nestedResidualGpuJoinResidualCacheCapacity = [UInt64]0
$nestedResidualGpuJoinResidualCachePreadBytes = [UInt64]0
$nestedResidualGpuJoinResidualCachePreadBytesAvoided = [UInt64]0
$nestedResidualGpuJoinResidualCacheH2DBytes = [UInt64]0
$nestedResidualGpuJoinResidualCacheCachedJoinCalls = [UInt64]0
$nestedResidualGpuJoinResidualCacheInvariantFailures = [UInt64]0
$nestedResidualProfileObserved = $false
$nestedResidualProfileRawSummary = ""
$nestedResidualProfileLookupCalls = [UInt64]0
$nestedResidualProfileLookupSeconds = [double]0
$nestedResidualProfilePreadCalls = [UInt64]0
$nestedResidualProfilePreadSeconds = [double]0
$nestedResidualProfileReconstructCalls = [UInt64]0
$nestedResidualProfileReconstructBlocks = [UInt64]0
$nestedResidualProfileReconstructSeconds = [double]0
$nestedResidualProfileVerifyCalls = [UInt64]0
$nestedResidualProfileVerifyBytes = [UInt64]0
$nestedResidualProfileVerifySeconds = [double]0
$nestedResidualProfileReuseWaitCalls = [UInt64]0
$nestedResidualProfileReuseWaitSeconds = [double]0
$nestedResidualProfileHostCopyCalls = [UInt64]0
$nestedResidualProfileHostCopySeconds = [double]0
$nestedResidualProfileH2DEnqueueCalls = [UInt64]0
$nestedResidualProfileH2DEnqueueSeconds = [double]0
$nestedResidualProfileH2DSyncCalls = [UInt64]0
$nestedResidualProfileH2DSyncSeconds = [double]0
$nestedResidualProfileRouteBeginCalls = [UInt64]0
$nestedResidualProfileRouteBeginSeconds = [double]0
$nestedResidualProfileRouteResolveSyncCalls = [UInt64]0
$nestedResidualProfileRouteResolveSyncSeconds = [double]0
$nestedResidualProfileRouteReadyWaitCalls = [UInt64]0
$nestedResidualProfileRouteReadyWaitSeconds = [double]0
$nestedResidualProfilePackedCopy = 0
$nestedResidualProfileSplitFused = 0
$nestedResidualProfileVerify = 0
$nestedResidualSummaryMatches = [regex]::Matches(
    $q1_0SidecarLogText,
    '(?m)^(?:ds4: )?\[nested-residual\] result=summary router=open router_calls=(\d+) cache_hits=(\d+) cache_misses=(\d+) residual_preads=(\d+) residual_bytes=(\d+) reconstructed=(\d+) mismatches=(\d+) h2d_bytes=(\d+) failures=(\d+)\r?$')
$nestedResidualVramSummaryMatches = [regex]::Matches(
    $q1_0SidecarLogText,
    '(?m)^(?:ds4: )?\[nested-residual-vram\] result=summary route_calls=(\d+) hits=(\d+) misses=(\d+) host_fills=(\d+) host_bytes=(\d+) h2d_bytes=(\d+) failures=(\d+)\r?$')
$nestedResidualBootstrapMatches = [regex]::Matches(
    $q1_0SidecarLogText,
    '(?m)^(?:ds4: )?\[nested-residual\] bootstrap-ready[^\r\n]*\ball_layer_first=(\d+)\s+all_layer_last=(\d+)\s+all_layer_count=(\d+)[^\r\n]*\r?$')
$nestedResidualBaseStorageSummaryMatches = [regex]::Matches(
    $q1_0SidecarLogText,
    '(?m)^(?:ds4: )?\[nested-residual-base-storage\] result=summary([^\r\n]*)\r?$')
$nestedResidualCachePageableSummaryMatches = [regex]::Matches(
    $q1_0SidecarLogText,
    '(?m)^(?:ds4: )?\[nested-residual-cache-pageable\] result=summary([^\r\n]*)\r?$')
$nestedResidualGpuJoinSummaryMatches = [regex]::Matches(
    $q1_0SidecarLogText,
    '(?m)^(?:ds4: )?\[(?:nested-residual-gpu-join|nested-residual)\] result=(?:summary|gpu_join_summary)(?=[^\r\n]*(?:gpu_join|cpu_reconstruct|base_h2d_bytes|residual_h2d_bytes))([^\r\n]*)\r?$')
$nestedResidualGpuJoinResidualCacheSummaryMatches = [regex]::Matches(
    $q1_0SidecarLogText,
    '(?m)^(?:ds4: )?\[nested-residual-residual-cache\] result=summary enabled=(\d+) hits=(\d+) misses=(\d+) evictions=(\d+) entries=(\d+) capacity=(\d+) pread_bytes=(\d+) pread_bytes_avoided=(\d+) h2d_bytes=(\d+) cached_join_calls=(\d+) invariant_failures=(\d+)\r?$')
$nestedResidualProfileSummaryMatches = [regex]::Matches(
    $q1_0SidecarLogText,
    '(?m)^(?:ds4: )?\[nested-residual-profile\] result=summary enabled=1 lookup_calls=(\d+) lookup_s=([0-9.]+) pread_calls=(\d+) pread_s=([0-9.]+) reconstruct_calls=(\d+) reconstruct_blocks=(\d+) reconstruct_s=([0-9.]+) verify_calls=(\d+) verify_bytes=(\d+) verify_s=([0-9.]+) reuse_wait_calls=(\d+) reuse_wait_s=([0-9.]+) host_copy_calls=(\d+) host_copy_s=([0-9.]+) h2d_enqueue_calls=(\d+) h2d_enqueue_s=([0-9.]+) h2d_sync_calls=(\d+) h2d_sync_s=([0-9.]+) route_begin_calls=(\d+) route_begin_s=([0-9.]+) route_resolve_sync_calls=(\d+) route_resolve_sync_s=([0-9.]+) route_ready_wait_calls=(\d+) route_ready_wait_s=([0-9.]+) packed_copy=(\d+) split_fused=(\d+) verify=(\d+)\r?$')
function Get-G7NestedResidualGpuJoinValue {
    param(
        [Parameter(Mandatory=$true)][hashtable]$Map,
        [Parameter(Mandatory=$true)][string[]]$Names,
        [Parameter(Mandatory=$true)][string]$Kind
    )

    foreach ($name in $Names) {
        foreach ($candidate in @(
                $name,
                "gpu_join_$name",
                "nested_residual_$name",
                "nested_residual_gpu_join_$name")) {
            if ($Map.ContainsKey($candidate)) {
                return [string]$Map[$candidate]
            }
        }
    }
    throw "Nested residual GPU join summary missing counter: $Kind"
}
function Get-G7KeyValueSummaryMap {
    param([Parameter(Mandatory=$true)][string]$Text)

    $map = @{}
    foreach ($counterMatch in [regex]::Matches(
            $Text, '([A-Za-z0-9_]+)=([^\s\r\n]+)')) {
        $map[$counterMatch.Groups[1].Value] =
            $counterMatch.Groups[2].Value
    }
    return $map
}
function Get-G7RequiredUInt64Counter {
    param(
        [Parameter(Mandatory=$true)][hashtable]$Map,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$SummaryName
    )

    if (-not $Map.ContainsKey($Name)) {
        throw "$SummaryName summary missing counter: $Name"
    }
    return [UInt64]$Map[$Name]
}
if ($NestedResidualSidecar) {
    if ($nestedResidualSummaryMatches.Count -ne 1) {
        throw "Nested residual runtime requires exactly one summary; observed $($nestedResidualSummaryMatches.Count)"
    }
    $nestedResidualSummary = $nestedResidualSummaryMatches[0]
    $nestedResidualRouterCalls = [UInt64]$nestedResidualSummary.Groups[1].Value
    $nestedResidualCacheHits = [UInt64]$nestedResidualSummary.Groups[2].Value
    $nestedResidualCacheMisses = [UInt64]$nestedResidualSummary.Groups[3].Value
    $nestedResidualPreads = [UInt64]$nestedResidualSummary.Groups[4].Value
    $nestedResidualBytes = [UInt64]$nestedResidualSummary.Groups[5].Value
    $nestedResidualReconstructed = [UInt64]$nestedResidualSummary.Groups[6].Value
    $nestedResidualMismatches = [UInt64]$nestedResidualSummary.Groups[7].Value
    $nestedResidualH2DBytes = [UInt64]$nestedResidualSummary.Groups[8].Value
    $nestedResidualFailures = [UInt64]$nestedResidualSummary.Groups[9].Value
    $nestedResidualExpectedReconstructed = $nestedResidualCacheMisses
    if ($NestedResidualGpuJoinResidualCache) {
        $nestedResidualExpectedReconstructed =
            $nestedResidualCacheHits + $nestedResidualCacheMisses
    }
    if ($nestedResidualRouterCalls -eq 0 -or
        $nestedResidualCacheMisses -eq 0 -or
        $nestedResidualPreads -ne $nestedResidualCacheMisses -or
        $nestedResidualReconstructed -ne
            $nestedResidualExpectedReconstructed -or
        $nestedResidualBytes -ne
            $nestedResidualPreads * [UInt64]3145728 -or
        $nestedResidualH2DBytes -ne
            ($nestedResidualCacheHits + $nestedResidualCacheMisses) *
                [UInt64]7077888 -or
        $nestedResidualMismatches -ne 0 -or
        $nestedResidualFailures -ne 0) {
        throw "Nested residual runtime counters are inconsistent"
    }
    $nestedResidualRuntimeObserved = $true
    if ($nestedResidualBootstrapMatches.Count -gt 1) {
        throw "Nested residual bootstrap runtime requires at most one ready marker; observed $($nestedResidualBootstrapMatches.Count)"
    }
    if ($nestedResidualBootstrapMatches.Count -eq 1) {
        $nestedResidualBootstrap = $nestedResidualBootstrapMatches[0]
        $nestedResidualAllLayerFirstLayer =
            [int]$nestedResidualBootstrap.Groups[1].Value
        $nestedResidualAllLayerLastLayer =
            [int]$nestedResidualBootstrap.Groups[2].Value
        $nestedResidualAllLayerCount =
            [int]$nestedResidualBootstrap.Groups[3].Value
    }
    if ($nestedResidualAllLayerStorageRequested -and
        ($nestedResidualBootstrapMatches.Count -ne 1 -or
         $nestedResidualAllLayerFirstLayer -ne 3 -or
         $nestedResidualAllLayerLastLayer -ne 42 -or
         $nestedResidualAllLayerCount -ne 40)) {
        throw "Nested residual all-layer runtime coverage must be exactly layers 3..42"
    }
    if ($NestedResidualPageableBase) {
        if ($nestedResidualBaseStorageSummaryMatches.Count -ne 1) {
            throw "Nested residual base storage telemetry requires exactly one summary; observed $($nestedResidualBaseStorageSummaryMatches.Count)"
        }
        $baseStorageSummary = $nestedResidualBaseStorageSummaryMatches[0]
        $nestedResidualBaseStorageRawSummary = $baseStorageSummary.Value
        $baseStorageCounters = Get-G7KeyValueSummaryMap `
            -Text $baseStorageSummary.Groups[1].Value
        if ([string]$baseStorageCounters['mapped'] -ne '0' -or
            [string]$baseStorageCounters['router'] -ne 'open' -or
            [string]$baseStorageCounters['exact'] -ne '1') {
            throw "Nested residual base storage semantic markers are inconsistent"
        }
        $nestedResidualBasePinnedEntries = Get-G7RequiredUInt64Counter `
            -Map $baseStorageCounters -Name "pinned_entries" `
            -SummaryName "Nested residual base storage"
        $nestedResidualBasePinnedBytes = Get-G7RequiredUInt64Counter `
            -Map $baseStorageCounters -Name "pinned_bytes" `
            -SummaryName "Nested residual base storage"
        $nestedResidualBasePinnedHits = Get-G7RequiredUInt64Counter `
            -Map $baseStorageCounters -Name "pinned_hits" `
            -SummaryName "Nested residual base storage"
        $nestedResidualBasePinnedH2DBytes = Get-G7RequiredUInt64Counter `
            -Map $baseStorageCounters -Name "pinned_h2d_bytes" `
            -SummaryName "Nested residual base storage"
        $nestedResidualBasePageableEntries = Get-G7RequiredUInt64Counter `
            -Map $baseStorageCounters -Name "pageable_entries" `
            -SummaryName "Nested residual base storage"
        $nestedResidualBasePageableBytes = Get-G7RequiredUInt64Counter `
            -Map $baseStorageCounters -Name "pageable_bytes" `
            -SummaryName "Nested residual base storage"
        $nestedResidualBasePageableHits = Get-G7RequiredUInt64Counter `
            -Map $baseStorageCounters -Name "pageable_hits" `
            -SummaryName "Nested residual base storage"
        $nestedResidualBasePageableH2DBytes = Get-G7RequiredUInt64Counter `
            -Map $baseStorageCounters -Name "pageable_h2d_bytes" `
            -SummaryName "Nested residual base storage"
        $nestedResidualStorageInvariantFailures =
            Get-G7RequiredUInt64Counter `
                -Map $baseStorageCounters -Name "invariant_failures" `
                -SummaryName "Nested residual base storage"
        if ($nestedResidualBasePageableEntries -eq 0 -or
            $nestedResidualBasePageableBytes -eq 0 -or
            $nestedResidualStorageInvariantFailures -ne 0) {
            throw "Nested residual base storage counters are inconsistent"
        }
    } elseif ($nestedResidualBaseStorageSummaryMatches.Count -ne 0 -or
              $q1_0SidecarLogText -match '\[nested-residual-base-storage\]') {
        throw "Nested residual pageable-base telemetry appeared while feature was disabled"
    }
    if ($NestedResidualCachePageable) {
        if ($nestedResidualCachePageableSummaryMatches.Count -ne 1) {
            throw "Nested residual residual-cache pageable telemetry requires exactly one summary; observed $($nestedResidualCachePageableSummaryMatches.Count)"
        }
        $cachePageableSummary = $nestedResidualCachePageableSummaryMatches[0]
        $nestedResidualCachePageableRawSummary = $cachePageableSummary.Value
        $cachePageableCounters = Get-G7KeyValueSummaryMap `
            -Text $cachePageableSummary.Groups[1].Value
        if ([string]$cachePageableCounters['mapped'] -ne '0' -or
            [string]$cachePageableCounters['router'] -ne 'open' -or
            [string]$cachePageableCounters['exact'] -ne '1') {
            throw "Nested residual cache pageable semantic markers are inconsistent"
        }
        $nestedResidualCachePinnedEntries = Get-G7RequiredUInt64Counter `
            -Map $cachePageableCounters -Name "pinned_entries" `
            -SummaryName "Nested residual cache pageable"
        $nestedResidualCachePinnedBytes = Get-G7RequiredUInt64Counter `
            -Map $cachePageableCounters -Name "pinned_bytes" `
            -SummaryName "Nested residual cache pageable"
        $nestedResidualCachePinnedHits = Get-G7RequiredUInt64Counter `
            -Map $cachePageableCounters -Name "pinned_hits" `
            -SummaryName "Nested residual cache pageable"
        $nestedResidualCachePinnedH2DBytes = Get-G7RequiredUInt64Counter `
            -Map $cachePageableCounters -Name "pinned_h2d_bytes" `
            -SummaryName "Nested residual cache pageable"
        $nestedResidualCachePageableEntries = Get-G7RequiredUInt64Counter `
            -Map $cachePageableCounters -Name "pageable_entries" `
            -SummaryName "Nested residual cache pageable"
        $nestedResidualCachePageableBytes = Get-G7RequiredUInt64Counter `
            -Map $cachePageableCounters -Name "pageable_bytes" `
            -SummaryName "Nested residual cache pageable"
        $nestedResidualCachePageableHits = Get-G7RequiredUInt64Counter `
            -Map $cachePageableCounters -Name "pageable_hits" `
            -SummaryName "Nested residual cache pageable"
        $nestedResidualCachePageableH2DBytes = Get-G7RequiredUInt64Counter `
            -Map $cachePageableCounters -Name "pageable_h2d_bytes" `
            -SummaryName "Nested residual cache pageable"
        $nestedResidualCachePageableCachedJoinCalls =
            Get-G7RequiredUInt64Counter `
                -Map $cachePageableCounters -Name "cached_join_calls" `
                -SummaryName "Nested residual cache pageable"
        $nestedResidualCacheLayerPartitioned =
            Get-G7RequiredUInt64Counter `
                -Map $cachePageableCounters -Name "partitioned" `
                -SummaryName "Nested residual cache pageable"
        $nestedResidualCacheLayerSlotsMin =
            Get-G7RequiredUInt64Counter `
                -Map $cachePageableCounters -Name "layer_slots_min" `
                -SummaryName "Nested residual cache pageable"
        $nestedResidualCacheLayerSlotsMax =
            Get-G7RequiredUInt64Counter `
                -Map $cachePageableCounters -Name "layer_slots_max" `
                -SummaryName "Nested residual cache pageable"
        $nestedResidualCachePageableInvariantFailures =
            Get-G7RequiredUInt64Counter `
                -Map $cachePageableCounters -Name "invariant_failures" `
                -SummaryName "Nested residual cache pageable"
        if ($nestedResidualCachePageableEntries -eq 0 -or
            $nestedResidualCachePageableBytes -eq 0 -or
            $nestedResidualCachePageableCachedJoinCalls -eq 0 -or
            $nestedResidualCacheLayerPartitioned -ne 1 -or
            $nestedResidualCacheLayerSlotsMin -eq 0 -or
            $nestedResidualCacheLayerSlotsMax -lt
                $nestedResidualCacheLayerSlotsMin -or
            $nestedResidualCacheLayerSlotsMax -gt
                ($nestedResidualCacheLayerSlotsMin + 1) -or
            $nestedResidualCachePageableInvariantFailures -ne 0) {
            throw "Nested residual cache pageable counters are inconsistent"
        }
    } elseif ($nestedResidualCachePageableSummaryMatches.Count -ne 0 -or
              $q1_0SidecarLogText -match '\[nested-residual-cache-pageable\]') {
        throw "Nested residual cache pageable telemetry appeared while feature was disabled"
    }
    if ($NestedResidualGpuCache) {
        if ($nestedResidualVramSummaryMatches.Count -ne 1) {
            throw "Nested residual GPU-cache requires exactly one VRAM summary; observed $($nestedResidualVramSummaryMatches.Count)"
        }
        $nestedResidualVramSummary = $nestedResidualVramSummaryMatches[0]
        $nestedResidualVramRawSummary = $nestedResidualVramSummary.Value
        $nestedResidualVramRouteCalls =
            [UInt64]$nestedResidualVramSummary.Groups[1].Value
        $nestedResidualVramHits =
            [UInt64]$nestedResidualVramSummary.Groups[2].Value
        $nestedResidualVramMisses =
            [UInt64]$nestedResidualVramSummary.Groups[3].Value
        $nestedResidualVramHostFills =
            [UInt64]$nestedResidualVramSummary.Groups[4].Value
        $nestedResidualVramHostBytes =
            [UInt64]$nestedResidualVramSummary.Groups[5].Value
        $nestedResidualVramH2DBytes =
            [UInt64]$nestedResidualVramSummary.Groups[6].Value
        $nestedResidualVramFailures =
            [UInt64]$nestedResidualVramSummary.Groups[7].Value
        if ($nestedResidualVramRouteCalls -eq 0 -or
            $nestedResidualVramHits -eq 0 -or
            $nestedResidualVramMisses -eq 0 -or
            $nestedResidualVramFailures -ne 0) {
            throw "Nested residual GPU-cache runtime counters are inconsistent"
        }
        if ($NestedResidualGpuJoin) {
            if ($nestedResidualVramHostFills -ne 0 -or
                $nestedResidualVramHostBytes -ne 0 -or
                $nestedResidualVramH2DBytes -ne
                    $nestedResidualVramMisses * [UInt64]7077888) {
                throw "Nested residual GPU-cache GPU-join counters are inconsistent"
            }
        } elseif ($nestedResidualVramHostFills -ne $nestedResidualVramMisses -or
                  $nestedResidualVramHostBytes -ne
                    $nestedResidualVramMisses * [UInt64]7077888 -or
                  $nestedResidualVramH2DBytes -ne
                    $nestedResidualVramMisses * [UInt64]7077888) {
            throw "Nested residual GPU-cache runtime counters are inconsistent"
        }
        $nestedResidualVramRuntimeObserved = $true
    } elseif ($nestedResidualVramSummaryMatches.Count -ne 0 -or
              $q1_0SidecarLogText -match '\[nested-residual-vram\]') {
        throw "Nested residual GPU-cache telemetry appeared while NestedResidualGpuCache was disabled"
    }
    if ($NestedResidualGpuJoin) {
        if ($nestedResidualGpuJoinSummaryMatches.Count -ne 1) {
            throw "Nested residual GPU join requires exactly one summary; observed $($nestedResidualGpuJoinSummaryMatches.Count)"
        }
        $gpuJoinSummary = $nestedResidualGpuJoinSummaryMatches[0]
        $nestedResidualGpuJoinRawSummary = $gpuJoinSummary.Value
        $gpuJoinCounters = @{}
        foreach ($counterMatch in [regex]::Matches(
                $gpuJoinSummary.Groups[1].Value,
                '([A-Za-z0-9_]+)=([^\s\r\n]+)')) {
            $gpuJoinCounters[$counterMatch.Groups[1].Value] =
                $counterMatch.Groups[2].Value
        }
        $nestedResidualGpuJoinRequestedRuntime = [int](Get-G7NestedResidualGpuJoinValue `
            -Map $gpuJoinCounters -Names @("requested") -Kind "requested")
        $nestedResidualGpuJoinObservedRuntime = [int](Get-G7NestedResidualGpuJoinValue `
            -Map $gpuJoinCounters -Names @("observed") -Kind "observed")
        $nestedResidualGpuJoinCalls = [UInt64](Get-G7NestedResidualGpuJoinValue `
            -Map $gpuJoinCounters -Names @("calls") -Kind "calls")
        $nestedResidualGpuJoinBlocks = [UInt64](Get-G7NestedResidualGpuJoinValue `
            -Map $gpuJoinCounters -Names @("blocks") -Kind "blocks")
        $nestedResidualGpuJoinBaseH2DBytes = [UInt64](Get-G7NestedResidualGpuJoinValue `
            -Map $gpuJoinCounters -Names @("base_h2d_bytes") -Kind "base_h2d_bytes")
        $nestedResidualGpuJoinResidualH2DBytes = [UInt64](Get-G7NestedResidualGpuJoinValue `
            -Map $gpuJoinCounters -Names @("residual_h2d_bytes") -Kind "residual_h2d_bytes")
        $nestedResidualGpuJoinNativeH2DBytes = [UInt64](Get-G7NestedResidualGpuJoinValue `
            -Map $gpuJoinCounters -Names @("native_h2d_bytes") -Kind "native_h2d_bytes")
        $nestedResidualGpuJoinSeconds = [double]::Parse(
            (Get-G7NestedResidualGpuJoinValue `
                -Map $gpuJoinCounters -Names @("seconds", "s") -Kind "seconds"),
            [Globalization.CultureInfo]::InvariantCulture)
        $nestedResidualGpuJoinWaitCalls = [UInt64](Get-G7NestedResidualGpuJoinValue `
            -Map $gpuJoinCounters -Names @("wait_calls", "gpu_join_wait_calls") -Kind "gpu_join_wait_calls")
        $nestedResidualGpuJoinWaitSeconds = [double]::Parse(
            (Get-G7NestedResidualGpuJoinValue `
                -Map $gpuJoinCounters -Names @("wait_seconds", "wait_s", "gpu_join_wait_seconds") -Kind "gpu_join_wait_seconds"),
            [Globalization.CultureInfo]::InvariantCulture)
        $nestedResidualGpuJoinVerifyCalls = [UInt64](Get-G7NestedResidualGpuJoinValue `
            -Map $gpuJoinCounters -Names @("verify_calls") -Kind "verify_calls")
        $nestedResidualGpuJoinVerifyBytes = [UInt64](Get-G7NestedResidualGpuJoinValue `
            -Map $gpuJoinCounters -Names @("verify_bytes") -Kind "verify_bytes")
        $nestedResidualGpuJoinVerifySeconds = [double]::Parse(
            (Get-G7NestedResidualGpuJoinValue `
                -Map $gpuJoinCounters -Names @("verify_seconds", "verify_s", "gpu_join_verify_seconds") -Kind "gpu_join_verify_seconds"),
            [Globalization.CultureInfo]::InvariantCulture)
        $nestedResidualGpuJoinVerifyMismatches = [UInt64](Get-G7NestedResidualGpuJoinValue `
            -Map $gpuJoinCounters -Names @("verify_mismatches", "mismatches") -Kind "verify_mismatches")
        $nestedResidualGpuJoinFailures = [UInt64](Get-G7NestedResidualGpuJoinValue `
            -Map $gpuJoinCounters -Names @("failures") -Kind "failures")
        $nestedResidualGpuJoinCpuReconstructCalls = [UInt64](Get-G7NestedResidualGpuJoinValue `
            -Map $gpuJoinCounters -Names @("cpu_reconstruct_calls") -Kind "cpu_reconstruct_calls")
        if ($nestedResidualGpuJoinRequestedRuntime -ne 1 -or
            $nestedResidualGpuJoinObservedRuntime -ne 1 -or
            $nestedResidualGpuJoinCalls -eq 0 -or
            $nestedResidualGpuJoinBlocks -eq 0 -or
            $nestedResidualGpuJoinBaseH2DBytes -eq 0 -or
            $nestedResidualGpuJoinResidualH2DBytes -eq 0 -or
            $nestedResidualGpuJoinNativeH2DBytes -ne 0 -or
            $nestedResidualGpuJoinSeconds -lt 0.0 -or
            $nestedResidualGpuJoinWaitSeconds -lt 0.0 -or
            $nestedResidualGpuJoinVerifySeconds -lt 0.0 -or
            $nestedResidualGpuJoinVerifyMismatches -ne 0 -or
            $nestedResidualGpuJoinFailures -ne 0 -or
            $nestedResidualGpuJoinCpuReconstructCalls -ne 0 -or
            ($NestedResidualVerifyReconstruction -and
             ($nestedResidualGpuJoinVerifyCalls -ne
                $nestedResidualGpuJoinCalls * [UInt64]3 -or
              $nestedResidualGpuJoinVerifyBytes -ne
                $nestedResidualGpuJoinCalls * [UInt64]7077888)) -or
            ((-not $NestedResidualVerifyReconstruction) -and
             ($nestedResidualGpuJoinVerifyCalls -ne 0 -or
              $nestedResidualGpuJoinVerifyBytes -ne 0 -or
              $nestedResidualGpuJoinVerifySeconds -ne 0.0))) {
            throw "Nested residual GPU join counters are inconsistent"
        }
        $nestedResidualGpuJoinObserved = $true
        if ($NestedResidualGpuJoinResidualCache) {
            if ($nestedResidualGpuJoinResidualCacheSummaryMatches.Count -ne 1) {
                throw "Nested residual GPU join residual cache requires exactly one summary; observed $($nestedResidualGpuJoinResidualCacheSummaryMatches.Count)"
            }
            $residualCacheSummary =
                $nestedResidualGpuJoinResidualCacheSummaryMatches[0]
            $nestedResidualGpuJoinResidualCacheRawSummary =
                $residualCacheSummary.Value
            $nestedResidualGpuJoinResidualCacheEnabledRuntime =
                [int]$residualCacheSummary.Groups[1].Value
            $nestedResidualGpuJoinResidualCacheHits =
                [UInt64]$residualCacheSummary.Groups[2].Value
            $nestedResidualGpuJoinResidualCacheMisses =
                [UInt64]$residualCacheSummary.Groups[3].Value
            $nestedResidualGpuJoinResidualCacheEvictions =
                [UInt64]$residualCacheSummary.Groups[4].Value
            $nestedResidualGpuJoinResidualCacheEntries =
                [UInt64]$residualCacheSummary.Groups[5].Value
            $nestedResidualGpuJoinResidualCacheCapacity =
                [UInt64]$residualCacheSummary.Groups[6].Value
            $nestedResidualGpuJoinResidualCachePreadBytes =
                [UInt64]$residualCacheSummary.Groups[7].Value
            $nestedResidualGpuJoinResidualCachePreadBytesAvoided =
                [UInt64]$residualCacheSummary.Groups[8].Value
            $nestedResidualGpuJoinResidualCacheH2DBytes =
                [UInt64]$residualCacheSummary.Groups[9].Value
            $nestedResidualGpuJoinResidualCacheCachedJoinCalls =
                [UInt64]$residualCacheSummary.Groups[10].Value
            $nestedResidualGpuJoinResidualCacheInvariantFailures =
                [UInt64]$residualCacheSummary.Groups[11].Value
            if ($nestedResidualGpuJoinResidualCacheEnabledRuntime -ne 1 -or
                $nestedResidualGpuJoinResidualCacheHits -eq 0 -or
                $nestedResidualGpuJoinResidualCacheMisses -eq 0 -or
                $nestedResidualGpuJoinResidualCacheCapacity -eq 0 -or
                $nestedResidualGpuJoinResidualCacheEntries -gt
                    $nestedResidualGpuJoinResidualCacheCapacity -or
                $nestedResidualGpuJoinResidualCachePreadBytesAvoided -eq 0 -or
                $nestedResidualGpuJoinResidualCacheCachedJoinCalls -eq 0 -or
                $nestedResidualGpuJoinResidualCacheInvariantFailures -ne 0) {
                throw "Nested residual GPU join residual cache counters are inconsistent"
            }
            $nestedResidualGpuJoinResidualCacheObserved = $true
        } elseif ($nestedResidualGpuJoinResidualCacheSummaryMatches.Count -ne 0 -or
                  $q1_0SidecarLogText -match '\[nested-residual-residual-cache\]') {
            throw "Nested residual GPU join residual cache telemetry appeared while NestedResidualGpuJoinResidualCache was disabled"
        }
    } elseif ($nestedResidualGpuJoinSummaryMatches.Count -ne 0 -or
              $nestedResidualGpuJoinResidualCacheSummaryMatches.Count -ne 0 -or
              $q1_0SidecarLogText -match '\[(?:nested-residual-gpu-join|nested-residual)\] result=(?:summary|gpu_join_summary)[^\r\n]*(?:gpu_join|cpu_reconstruct|base_h2d_bytes|residual_h2d_bytes)' -or
              $q1_0SidecarLogText -match '\[nested-residual-residual-cache\]') {
        throw "Nested residual GPU join telemetry appeared while NestedResidualGpuJoin was disabled"
    }
    if ($NestedResidualProfile) {
        if ($nestedResidualProfileSummaryMatches.Count -ne 1) {
            throw "Nested residual profile requires exactly one summary; observed $($nestedResidualProfileSummaryMatches.Count)"
        }
        $profileSummary = $nestedResidualProfileSummaryMatches[0]
        $nestedResidualProfileRawSummary = $profileSummary.Value
        $nestedResidualProfileLookupCalls = [UInt64]$profileSummary.Groups[1].Value
        $nestedResidualProfileLookupSeconds = [double]::Parse($profileSummary.Groups[2].Value, [Globalization.CultureInfo]::InvariantCulture)
        $nestedResidualProfilePreadCalls = [UInt64]$profileSummary.Groups[3].Value
        $nestedResidualProfilePreadSeconds = [double]::Parse($profileSummary.Groups[4].Value, [Globalization.CultureInfo]::InvariantCulture)
        $nestedResidualProfileReconstructCalls = [UInt64]$profileSummary.Groups[5].Value
        $nestedResidualProfileReconstructBlocks = [UInt64]$profileSummary.Groups[6].Value
        $nestedResidualProfileReconstructSeconds = [double]::Parse($profileSummary.Groups[7].Value, [Globalization.CultureInfo]::InvariantCulture)
        $nestedResidualProfileVerifyCalls = [UInt64]$profileSummary.Groups[8].Value
        $nestedResidualProfileVerifyBytes = [UInt64]$profileSummary.Groups[9].Value
        $nestedResidualProfileVerifySeconds = [double]::Parse($profileSummary.Groups[10].Value, [Globalization.CultureInfo]::InvariantCulture)
        $nestedResidualProfileReuseWaitCalls = [UInt64]$profileSummary.Groups[11].Value
        $nestedResidualProfileReuseWaitSeconds = [double]::Parse($profileSummary.Groups[12].Value, [Globalization.CultureInfo]::InvariantCulture)
        $nestedResidualProfileHostCopyCalls = [UInt64]$profileSummary.Groups[13].Value
        $nestedResidualProfileHostCopySeconds = [double]::Parse($profileSummary.Groups[14].Value, [Globalization.CultureInfo]::InvariantCulture)
        $nestedResidualProfileH2DEnqueueCalls = [UInt64]$profileSummary.Groups[15].Value
        $nestedResidualProfileH2DEnqueueSeconds = [double]::Parse($profileSummary.Groups[16].Value, [Globalization.CultureInfo]::InvariantCulture)
        $nestedResidualProfileH2DSyncCalls = [UInt64]$profileSummary.Groups[17].Value
        $nestedResidualProfileH2DSyncSeconds = [double]::Parse($profileSummary.Groups[18].Value, [Globalization.CultureInfo]::InvariantCulture)
        $nestedResidualProfileRouteBeginCalls = [UInt64]$profileSummary.Groups[19].Value
        $nestedResidualProfileRouteBeginSeconds = [double]::Parse($profileSummary.Groups[20].Value, [Globalization.CultureInfo]::InvariantCulture)
        $nestedResidualProfileRouteResolveSyncCalls = [UInt64]$profileSummary.Groups[21].Value
        $nestedResidualProfileRouteResolveSyncSeconds = [double]::Parse($profileSummary.Groups[22].Value, [Globalization.CultureInfo]::InvariantCulture)
        $nestedResidualProfileRouteReadyWaitCalls = [UInt64]$profileSummary.Groups[23].Value
        $nestedResidualProfileRouteReadyWaitSeconds = [double]::Parse($profileSummary.Groups[24].Value, [Globalization.CultureInfo]::InvariantCulture)
        $nestedResidualProfilePackedCopy = [int]$profileSummary.Groups[25].Value
        $nestedResidualProfileSplitFused = [int]$profileSummary.Groups[26].Value
        $nestedResidualProfileVerify = [int]$profileSummary.Groups[27].Value
        if ($nestedResidualProfileLookupCalls -ne
                $nestedResidualCacheHits + $nestedResidualCacheMisses -or
            $nestedResidualProfilePreadCalls -ne $nestedResidualPreads -or
            $nestedResidualProfileReconstructCalls -ne
                $nestedResidualReconstructed -or
            $nestedResidualProfileReconstructBlocks -eq 0 -or
            $nestedResidualProfileVerify -ne
                [int][bool]$NestedResidualVerifyReconstruction -or
            ($NestedResidualVerifyReconstruction -and
                ($nestedResidualProfileVerifyCalls -ne
                    $nestedResidualReconstructed * [UInt64]3 -or
                 $nestedResidualProfileVerifyBytes -ne
                    $nestedResidualReconstructed * [UInt64]7077888 -or
                 $nestedResidualProfileVerifySeconds -lt 0.0)) -or
            ((-not $NestedResidualVerifyReconstruction) -and
                ($nestedResidualProfileVerifyCalls -ne 0 -or
                 $nestedResidualProfileVerifyBytes -ne 0 -or
                 $nestedResidualProfileVerifySeconds -ne 0.0)) -or
            $nestedResidualProfileHostCopyCalls -ne
                $nestedResidualVramHostFills -or
            $nestedResidualProfileH2DEnqueueCalls -ne
                $nestedResidualVramHostFills -or
            $nestedResidualProfileH2DSyncCalls -eq 0 -or
            $nestedResidualProfileRouteBeginCalls -ne
                $nestedResidualVramRouteCalls -or
            $nestedResidualProfileRouteReadyWaitCalls -ne
                $nestedResidualVramRouteCalls -or
            $nestedResidualProfilePackedCopy -ne [int][bool]$RoutePackedCopy -or
            $nestedResidualProfileSplitFused -ne [int][bool]$SplitFused) {
            throw "Nested residual profile counters are inconsistent"
        }
        $nestedResidualProfileObserved = $true
    } elseif ($nestedResidualProfileSummaryMatches.Count -ne 0 -or
              $q1_0SidecarLogText -match '\[nested-residual-profile\]') {
        throw "Nested residual profile telemetry appeared while NestedResidualProfile was disabled"
    }
} elseif ($nestedResidualSummaryMatches.Count -ne 0 -or
          $nestedResidualVramSummaryMatches.Count -ne 0 -or
          $nestedResidualBaseStorageSummaryMatches.Count -ne 0 -or
          $nestedResidualCachePageableSummaryMatches.Count -ne 0 -or
          $nestedResidualGpuJoinSummaryMatches.Count -ne 0 -or
          $nestedResidualProfileSummaryMatches.Count -ne 0 -or
          $q1_0SidecarLogText -match '\[nested-residual(?:-vram|-gpu-join|-profile|-base-storage|-cache-pageable)?\]') {
    throw "Nested residual runtime telemetry appeared while nested residual was disabled"
}
$q1_0Telemetry = Read-G7Q1_0SidecarTelemetry `
    -LogText $q1_0SidecarLogText `
    -SidecarConfigured ([bool]$Q1_0ExpertSidecar) `
    -SelectedLoadRequested ([bool]$Q1_0SelectedLoad) `
    -ResidentArenaRequested ([bool]($Q1_0ResidentArena -or $Q1_0SnapshotBacking)) `
    -SnapshotBackingRequested ([bool]$Q1_0SnapshotBacking) `
    -DualSparseRequested ([bool]$Q1_0DualSparseCompanion) `
    -ExpectedResidentEntries ([UInt64]$(if ($Q1_0SnapshotBacking) {
        $ExpectedQ1_0SnapshotEntries
    } else {
        $ExpectedQ1_0ResidentEntries
    })) `
    -SidecarPath $Q1_0ExpertSidecar
$q1_0MixedResolverRequired = [bool](
    $Q1_0SnapshotBacking -or $Q1_0MixedColdOne -or
    $Q1_0DynamicPromotion -or
    ($Q1_0ExpertSidecar -and $Q1_0ResidentArena -and
     $Q1_0DualArena -and -not $Q1_0DualSparseCompanion))
$q1_0MixedExpectedRouter = ""
if ($q1_0MixedResolverRequired -and $Q1_0ResidentArena -and
    $Q1_0DualArena -and -not $Q1_0DualSparseCompanion) {
    $q1_0MixedExpectedRouter = if ($ComposePrefillMassOpenRouter) {
        "open"
    } else {
        "unchanged"
    }
}
$q1_0MixedTelemetry = Read-G7Q1_0MixedTelemetry `
    -LogText $q1_0SidecarLogText `
    -Required $q1_0MixedResolverRequired `
    -ExpectedRouter $q1_0MixedExpectedRouter
$q1_0MixedRouteTraceRequired = [bool](
    $q1_0MixedResolverRequired -and $Q1_0MixedTrace)
$q1_0MixedRouteTraceTelemetry = Read-G7Q1_0MixedRouteTraceTelemetry `
    -LogText $q1_0SidecarLogText `
    -Required $q1_0MixedRouteTraceRequired
$q1_0MixedIq2Routes = [UInt64]$q1_0MixedTelemetry.iq2_vram
$q1_0MixedIq2Routes += [UInt64]$q1_0MixedTelemetry.iq2_snapshot_ram
$q1_0MixedIq2Routes += [UInt64]$q1_0MixedTelemetry.iq2_tier_ram
$q1_0MixedAccountedRoutes = [UInt64]$q1_0MixedIq2Routes
$q1_0MixedAccountedRoutes += [UInt64]$q1_0MixedTelemetry.q1_resident
$q1_0SidecarRuntimeObserved = [bool]$q1_0Telemetry.runtime_observed
$q1_0SidecarCalls = [UInt64]$q1_0Telemetry.route_calls
$q1_0SidecarSlots = [UInt64]$q1_0Telemetry.route_slots
$q1_0SidecarSelectedLoads = [UInt64]$q1_0Telemetry.selected_loads
$q1_0SidecarFailures = [UInt64]$q1_0Telemetry.failures
$q1_0ResidentMode = [int]$q1_0Telemetry.resident_mode
$q1_0ResidentHits = [UInt64]$q1_0Telemetry.resident_hits
$q1_0ResidentMisses = [UInt64]$q1_0Telemetry.resident_misses
$q1_0ResidentH2DBytes = [UInt64]$q1_0Telemetry.resident_h2d_bytes
$q1_0DirectPreadFallbacks = [UInt64]$q1_0Telemetry.direct_pread_fallbacks
$q1_0DirectPreadBytes = [UInt64]$q1_0Telemetry.direct_pread_bytes
$q1_0BootstrapEntries = [UInt64]$q1_0Telemetry.bootstrap_entries
$q1_0ProfileExpectedMappingBytes = [UInt64]$(
    if ($ExpectedQ1_0ExpertSidecarBytes -ne 0) {
        $ExpectedQ1_0ExpertSidecarBytes
    } elseif ($q1_0SidecarInfoAtStart) {
        [UInt64]$q1_0SidecarInfoAtStart.Length
    } else {
        [UInt64]0
    })
$q1_0ProfileTelemetry = Read-G7Q1_0ProfileTelemetry `
    -LogText $q1_0SidecarLogText -Required ([bool]$Q1_0Profile) `
    -Windows ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) `
    -ExpectedMappingBytes $q1_0ProfileExpectedMappingBytes `
    -ExpectedResidentHits $q1_0ResidentHits `
    -ExpectedResidentH2DBytes $q1_0ResidentH2DBytes `
    -ExpectedMixedJoinCalls ([UInt64]$q1_0MixedTelemetry.joins)
$q1_0SsdWrapTelemetry = Read-G7Q1_0SsdWrapTelemetry `
    -LogText $q1_0SidecarLogText `
    -Required ([bool]$Q1_0PromotionSsdWrap) `
    -ExpectedHostBudgetBytes ([UInt64]$arenaCapHostBudgetBytes) `
    -ExpectedPinnedGiB $Q1_0Iq2PinnedGiB
$q1_0RuntimeContractValid = [bool](
    $q1_0Telemetry.runtime_contract_valid -and $q1_0ProfileTelemetry.valid -and
    $q1_0SsdWrapTelemetry.valid)
$q1_0FailClosedObserved = [bool]$q1_0Telemetry.fail_closed_observed
$q1_0BootstrapPinnedBytes = [UInt64]0
$q1_0BootstrapPageableBytes = [UInt64]0
$q1_0BootstrapPinnedSlots = [UInt64]0
$q1_0BootstrapPageableSlots = [UInt64]0
$q1_0BootstrapTotalSlots = [UInt64]0
$q1_0BootstrapTotalBytes = [UInt64]0
$q1_0BootstrapLayerFirst = [UInt64]0
$q1_0BootstrapLayerLast = [UInt64]0
$q1_0SourceUnlockObserved = $false
$q1_0SourceUnlockResult = ""
$q1_0SourceUnlockWindows = 0
$q1_0SourceUnlockPageSize = [UInt64]0
$q1_0SourceUnlockPageAligned = 0
$q1_0SourceUnlockDestinationUnchanged = 0
$q1_0SourceUnlockLayers = [UInt64]0
$q1_0SourceUnlockRangesAttempted = [UInt64]0
$q1_0SourceUnlockBytesAttempted = [UInt64]0
$q1_0SourceUnlockCalls = [UInt64]0
$q1_0SourceUnlockSuccess = [UInt64]0
$q1_0SourceUnlockTrue = [UInt64]0
$q1_0SourceUnlockNotLocked = [UInt64]0
$q1_0SourceUnlockErrorNotLocked = [UInt64]0
$q1_0SourceUnlockFailed = [UInt64]0
$q1_0SourceUnlockSeconds = [double]0.0
$q1_0SourceUnlockAvailableBefore = [UInt64]0
$q1_0SourceUnlockAvailableAfter = [UInt64]0
$q1_0SourceUnlockWorkingSetBefore = [UInt64]0
$q1_0SourceUnlockWorkingSetAfter = [UInt64]0
$q1_0SourceUnlockPageFaultBefore = [UInt64]0
$q1_0SourceUnlockPageFaultAfter = [UInt64]0
$q1_0SourceUnlockReadTransferBefore = [UInt64]0
$q1_0SourceUnlockReadTransferAfter = [UInt64]0
$q1_0SourceUnlockLastError = [UInt64]0
$q1_0SourceUnlockExpectedEntries = [UInt64]0
$q1_0SourceUnlockTotalBytes = [UInt64]0
$q1_0SourceUnlockClassification = ''
$q1_0BootstrapMatches = [regex]::Matches(
    $q1_0SidecarLogText,
    '(?m)^(?:ds4: )?\[q1-0-resident-arena\] result=bootstrapped entries=(\d+) layers=(\d+)\.\.(\d+) generation=(\d+) source=sidecar-mmap route_pread=disabled iq2_host_arena=([^ \r\n]+) mixed_host_backing=([^ \r\n]+) pinned=(\d+) pageable=(\d+) pinned_slots=(\d+) pageable_slots=(\d+) total_slots=(\d+) total_bytes=(\d+)\r?$')
if ($q1_0BootstrapMatches.Count -gt 0) {
    if ($q1_0BootstrapMatches.Count -ne 1) {
        throw "Q1_0 resident arena requires exactly one bootstrap marker; observed $($q1_0BootstrapMatches.Count)"
    }
    $q1_0BootstrapMatch = $q1_0BootstrapMatches[0]
    $q1_0BootstrapLayerFirst = [UInt64]$q1_0BootstrapMatch.Groups[2].Value
    $q1_0BootstrapLayerLast = [UInt64]$q1_0BootstrapMatch.Groups[3].Value
    $q1_0BootstrapPinnedBytes =
        [UInt64]$q1_0BootstrapMatch.Groups[7].Value
    $q1_0BootstrapPageableBytes =
        [UInt64]$q1_0BootstrapMatch.Groups[8].Value
    $q1_0BootstrapPinnedSlots =
        [UInt64]$q1_0BootstrapMatch.Groups[9].Value
    $q1_0BootstrapPageableSlots =
        [UInt64]$q1_0BootstrapMatch.Groups[10].Value
    $q1_0BootstrapTotalSlots =
        [UInt64]$q1_0BootstrapMatch.Groups[11].Value
    $q1_0BootstrapTotalBytes =
        [UInt64]$q1_0BootstrapMatch.Groups[12].Value
}
$q1_0SourceUnlockPattern =
    '(?m)^(?:ds4: )?\[q1-0-source-unlock\] result=([^ \r\n]+) ' +
    'phase=bootstrap source=sidecar-mmap windows=(\d+) page_size=(\d+) ' +
    'page_aligned=(\d+) destination_unchanged=(\d+) layers=(\d+) ' +
    'ranges_attempted=(\d+) bytes_attempted=(\d+) calls=(\d+) ' +
    'success=(\d+) true=(\d+) not_locked=(\d+) error_not_locked=(\d+) ' +
    'failed=(\d+) seconds=([0-9]+(?:\.[0-9]+)?) ' +
    'available_before=(\d+) available_after=(\d+) ' +
    'working_set_before=(\d+) working_set_after=(\d+) ' +
    'page_fault_before=(\d+) page_fault_after=(\d+) ' +
    'read_transfer_before=(\d+) read_transfer_after=(\d+) ' +
    'last_error=(\d+) expected_entries=(\d+) total_bytes=(\d+)\r?$'
$q1_0SourceUnlockMatches = [regex]::Matches(
    $q1_0SidecarLogText, $q1_0SourceUnlockPattern)
$q1_0SourceUnlockRequired =
    [bool]($Q1_0ResidentArena -and -not $Q1_0SnapshotBacking -and
           $q1_0BootstrapMatches.Count -gt 0 -and
           [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT)
if ($q1_0SourceUnlockMatches.Count -gt 1) {
    throw "Q1_0 source unlock telemetry must be emitted at most once; observed $($q1_0SourceUnlockMatches.Count)"
}
if ($q1_0SourceUnlockRequired -and
    $q1_0SourceUnlockMatches.Count -ne 1) {
    throw "Q1_0 source unlock telemetry missing for Windows resident sidecar bootstrap"
}
if ($q1_0SourceUnlockMatches.Count -eq 1) {
    $q1_0SourceUnlockObserved = $true
    $q1_0SourceUnlockMatch = $q1_0SourceUnlockMatches[0]
    $q1_0SourceUnlockResult = [string]$q1_0SourceUnlockMatch.Groups[1].Value
    $q1_0SourceUnlockWindows =
        [int]$q1_0SourceUnlockMatch.Groups[2].Value
    $q1_0SourceUnlockPageSize =
        [UInt64]$q1_0SourceUnlockMatch.Groups[3].Value
    $q1_0SourceUnlockPageAligned =
        [int]$q1_0SourceUnlockMatch.Groups[4].Value
    $q1_0SourceUnlockDestinationUnchanged =
        [int]$q1_0SourceUnlockMatch.Groups[5].Value
    $q1_0SourceUnlockLayers =
        [UInt64]$q1_0SourceUnlockMatch.Groups[6].Value
    $q1_0SourceUnlockRangesAttempted =
        [UInt64]$q1_0SourceUnlockMatch.Groups[7].Value
    $q1_0SourceUnlockBytesAttempted =
        [UInt64]$q1_0SourceUnlockMatch.Groups[8].Value
    $q1_0SourceUnlockCalls =
        [UInt64]$q1_0SourceUnlockMatch.Groups[9].Value
    $q1_0SourceUnlockSuccess =
        [UInt64]$q1_0SourceUnlockMatch.Groups[10].Value
    $q1_0SourceUnlockTrue =
        [UInt64]$q1_0SourceUnlockMatch.Groups[11].Value
    $q1_0SourceUnlockNotLocked =
        [UInt64]$q1_0SourceUnlockMatch.Groups[12].Value
    $q1_0SourceUnlockErrorNotLocked =
        [UInt64]$q1_0SourceUnlockMatch.Groups[13].Value
    $q1_0SourceUnlockFailed =
        [UInt64]$q1_0SourceUnlockMatch.Groups[14].Value
    $q1_0SourceUnlockSeconds =
        [double]$q1_0SourceUnlockMatch.Groups[15].Value
    $q1_0SourceUnlockAvailableBefore =
        [UInt64]$q1_0SourceUnlockMatch.Groups[16].Value
    $q1_0SourceUnlockAvailableAfter =
        [UInt64]$q1_0SourceUnlockMatch.Groups[17].Value
    $q1_0SourceUnlockWorkingSetBefore =
        [UInt64]$q1_0SourceUnlockMatch.Groups[18].Value
    $q1_0SourceUnlockWorkingSetAfter =
        [UInt64]$q1_0SourceUnlockMatch.Groups[19].Value
    $q1_0SourceUnlockPageFaultBefore =
        [UInt64]$q1_0SourceUnlockMatch.Groups[20].Value
    $q1_0SourceUnlockPageFaultAfter =
        [UInt64]$q1_0SourceUnlockMatch.Groups[21].Value
    $q1_0SourceUnlockReadTransferBefore =
        [UInt64]$q1_0SourceUnlockMatch.Groups[22].Value
    $q1_0SourceUnlockReadTransferAfter =
        [UInt64]$q1_0SourceUnlockMatch.Groups[23].Value
    $q1_0SourceUnlockLastError =
        [UInt64]$q1_0SourceUnlockMatch.Groups[24].Value
    $q1_0SourceUnlockExpectedEntries =
        [UInt64]$q1_0SourceUnlockMatch.Groups[25].Value
    $q1_0SourceUnlockTotalBytes =
        [UInt64]$q1_0SourceUnlockMatch.Groups[26].Value
    if ($q1_0SourceUnlockFailed -ne 0) {
        $q1_0SourceUnlockClassification = 'failed'
    } elseif ($q1_0SourceUnlockCalls -eq 0) {
        $q1_0SourceUnlockClassification = 'no-unlock-activity'
    } elseif (($q1_0SourceUnlockNotLocked -eq $q1_0SourceUnlockCalls) -and
        ($q1_0SourceUnlockFailed -eq 0)) {
        $q1_0SourceUnlockClassification = 'intentional-ws-trim-idiom'
    }
    if ($q1_0SourceUnlockFailed -eq 0 -and
        ($q1_0SourceUnlockResult -ne "complete" -or
        $q1_0SourceUnlockWindows -ne 1 -or
        $q1_0SourceUnlockPageAligned -ne 1 -or
        $q1_0SourceUnlockDestinationUnchanged -ne 1 -or
        $q1_0SourceUnlockPageSize -eq 0 -or
        (($q1_0SourceUnlockPageSize -band
          ($q1_0SourceUnlockPageSize - 1)) -ne 0) -or
        $q1_0SourceUnlockSuccess -ne $q1_0SourceUnlockTrue -or
        $q1_0SourceUnlockNotLocked -ne
            $q1_0SourceUnlockErrorNotLocked -or
        $q1_0SourceUnlockCalls -ne
            ($q1_0SourceUnlockSuccess + $q1_0SourceUnlockNotLocked +
             $q1_0SourceUnlockFailed) -or
        ($q1_0SourceUnlockCalls -ne 0 -and
         ($q1_0SourceUnlockExpectedEntries -ne $q1_0BootstrapEntries -or
          $q1_0SourceUnlockTotalBytes -ne $q1_0BootstrapTotalBytes)))) {
        throw "Q1_0 source unlock telemetry counters are inconsistent"
    }
    if ($q1_0BootstrapMatches.Count -gt 0 -and
        $q1_0SourceUnlockCalls -ne 0 -and
        $q1_0SourceUnlockFailed -eq 0) {
        $expectedQ1_0UnlockLayers =
            $q1_0BootstrapLayerLast - $q1_0BootstrapLayerFirst + 1
        if ($q1_0SourceUnlockLayers -ne $expectedQ1_0UnlockLayers -or
            $q1_0SourceUnlockRangesAttempted -ne
                ($expectedQ1_0UnlockLayers * 3) -or
            $q1_0SourceUnlockCalls -ne
                $q1_0SourceUnlockRangesAttempted -or
            $q1_0SourceUnlockBytesAttempted -eq 0) {
            throw "Q1_0 source unlock range accounting is inconsistent"
        }
    }
}
if ($Q1_0PureResident -and
    ([UInt64]$q1_0MixedTelemetry.all_iq2 -ne 0 -or
     [UInt64]$q1_0MixedTelemetry.iq2_vram -ne 0 -or
     [UInt64]$q1_0MixedTelemetry.iq2_snapshot_ram -ne 0 -or
     [UInt64]$q1_0MixedTelemetry.iq2_tier_ram -ne 0 -or
     [UInt64]$q1_0MixedTelemetry.q1_resident -eq 0 -or
     [UInt64]$q1_0MixedTelemetry.q1_resident -ne
        ([UInt64]$q1_0MixedTelemetry.calls * 6) -or
     [UInt64]$q1_0MixedTelemetry.joins -ne
        [UInt64]$q1_0MixedTelemetry.calls -or
     [UInt64]$q1_0MixedTelemetry.iq2_ssd_bytes -ne 0 -or
     [UInt64]$q1_0MixedTelemetry.iq2_ssd_violations -ne 0 -or
     [UInt64]$q1_0MixedTelemetry.failures -ne 0)) {
    throw "Q1_0 pure-resident counters show IQ2 routing, incomplete Q1 coverage, SSD access, or a runtime failure"
}
if ($q1_0MixedResolverRequired -and $Q1_0DualArena -and
    -not $Q1_0DualSparseCompanion -and $Q1_0MixedTrace -and
    ([UInt64]$q1_0MixedTelemetry.trace_rows -eq 0 -or
     [UInt64]$q1_0MixedTelemetry.tier_route_entries -ne
        [UInt64]$q1_0MixedTelemetry.trace_rows)) {
    throw "Q1_0 mixed resolver route-entry counters do not cover every traced route"
}
if ($q1_0MixedResolverRequired -and $Q1_0DualArena -and
    -not $Q1_0DualSparseCompanion -and $Q1_0MixedTrace) {
    if ([UInt64]$q1_0MixedAccountedRoutes -ne
        [UInt64]$q1_0MixedTelemetry.trace_rows) {
        throw "Q1_0 mixed summary route categories do not cover every traced route"
    }
    if (-not [bool]$q1_0MixedRouteTraceTelemetry.observed -or
        [UInt64]$q1_0MixedRouteTraceTelemetry.rows -ne
            [UInt64]$q1_0MixedTelemetry.trace_rows -or
        [UInt64]$q1_0MixedRouteTraceTelemetry.iq2_vram -ne
            [UInt64]$q1_0MixedTelemetry.iq2_vram -or
        [UInt64]$q1_0MixedRouteTraceTelemetry.iq2_snapshot_ram -ne
            [UInt64]$q1_0MixedTelemetry.iq2_snapshot_ram -or
        [UInt64]$q1_0MixedRouteTraceTelemetry.iq2_tier_ram -ne
            [UInt64]$q1_0MixedTelemetry.iq2_tier_ram -or
        [UInt64]$q1_0MixedRouteTraceTelemetry.q1_resident -ne
            [UInt64]$q1_0MixedTelemetry.q1_resident -or
        [UInt64]$q1_0MixedRouteTraceTelemetry.iq2_total -ne
            [UInt64]$q1_0MixedIq2Routes) {
        throw "Q1_0 mixed route trace accounting does not match the summary"
    }
}
$q1_0DualSparseRuntimeObserved = $false
$q1_0DualSparseEntries = [UInt64]0
$q1_0DualSparseBytes = [UInt64]0
$q1_0DualSparseStageSeconds = [double]0
$q1_0DualSparsePublications = [UInt64]0
$q1_0DualSparseFailures = [UInt64]0
$q1_0DualSparseSummaryMatches = [regex]::Matches(
    $q1_0SidecarLogText,
    '(?m)^(?:ds4: )?\[q1-0-dual-sparse\] result=summary entries=(\d+) bytes=(\d+) stage_seconds=([0-9.]+) publications=(\d+) failures=(\d+) ready=(\d+) candidate_fnv1a64=([0-9a-fA-F]+) primary_generation=(\d+) q1_generation=(\d+)\x0d?$')
if ($q1_0DualSparseSummaryMatches.Count -eq 1) {
    $m = $q1_0DualSparseSummaryMatches[0]
    $q1_0DualSparseEntries = [UInt64]$m.Groups[1].Value
    $q1_0DualSparseBytes = [UInt64]$m.Groups[2].Value
    $q1_0DualSparseStageSeconds = [double]::Parse(
        $m.Groups[3].Value, [Globalization.CultureInfo]::InvariantCulture)
    $q1_0DualSparsePublications = [UInt64]$m.Groups[4].Value
    $q1_0DualSparseFailures = [UInt64]$m.Groups[5].Value
    $q1_0DualSparseRuntimeObserved = [bool](
        [int]$m.Groups[6].Value -eq 1 -and
        $m.Groups[7].Value -ne '0000000000000000' -and
        [UInt64]$m.Groups[8].Value -ne 0 -and
        [UInt64]$m.Groups[8].Value -eq [UInt64]$m.Groups[9].Value)
}
if ($Q1_0DualSparseCompanion -and
    ($q1_0DualSparseSummaryMatches.Count -ne 1 -or
     -not $q1_0DualSparseRuntimeObserved -or
     $q1_0DualSparseEntries -eq 0 -or
     $q1_0DualSparseBytes -eq 0 -or
     $q1_0DualSparsePublications -ne 1 -or
     $q1_0DualSparseFailures -ne 0)) {
    throw "Q1_0 dual sparse companion did not prove one ready, generation-matched, failure-free publication"
}
if ($Q1_0MixedColdOne -and
    ([UInt64]$q1_0MixedTelemetry.calls -eq 0 -or
     [UInt64]$q1_0MixedTelemetry.cold_one_calls -ne
        [UInt64]$q1_0MixedTelemetry.calls -or
     [UInt64]$q1_0MixedTelemetry.cold_one_hot_routes -ne
        ([UInt64]$q1_0MixedTelemetry.calls * 5) -or
     [UInt64]$q1_0MixedTelemetry.cold_one_q1_routes -ne
        [UInt64]$q1_0MixedTelemetry.calls -or
     [UInt64]$q1_0MixedTelemetry.q1_resident -ne
        [UInt64]$q1_0MixedTelemetry.calls -or
     [UInt64]$q1_0MixedTelemetry.joins -ne
        [UInt64]$q1_0MixedTelemetry.calls -or
     [UInt64]$q1_0MixedTelemetry.cold_one_invariant_failures -ne 0 -or
     [UInt64]$q1_0MixedTelemetry.iq2_ssd_bytes -ne 0 -or
     [UInt64]$q1_0MixedTelemetry.iq2_ssd_violations -ne 0 -or
     [UInt64]$q1_0MixedTelemetry.failures -ne 0)) {
    throw "Q1_0 5+1 counters did not prove exactly five resident IQ2 plus one resident Q1 route per call with zero SSD"
}
$q1_0DualArenaRuntimeObserved = [bool](
    $q1_0SidecarLogText -match 'mixed_host_backing=dual-arena' -and
    $q1_0SidecarLogText -match 'CUDA dynamic arena ready .* backing=primary' -and
    (($Q1_0DualSparseCompanion -and $q1_0DualSparseRuntimeObserved) -or
     (-not $Q1_0DualSparseCompanion -and
      $q1_0SidecarLogText -match '\[q1-0-resident-arena\] result=bootstrapped')))
if ($Q1_0DualArena -and -not $q1_0DualArenaRuntimeObserved) {
    throw "Q1_0DualArena was requested but separate primary/Q1 arena markers were not observed"
}
if (-not $Q1_0DualArena -and
    $q1_0SidecarLogText -match 'mixed_host_backing=dual-arena') {
    throw "Q1_0 dual arena activated while not requested"
}
$q1_0StructuralSmokeEligible = [bool](
    $Q1_0ExpertSidecar -and $Q1_0SelectedLoad -and
    $GateKind -eq "structural-safety" -and $Repeats -eq 1 -and
    -not $Warmup -and $q1_0SidecarRuntimeObserved -and
    $q1_0RuntimeContractValid -and $q1_0SidecarProvenanceVerified)

$iq1SSidecarCalls = [UInt64]0
$iq1SSidecarSlots = [UInt64]0
$iq1SSidecarSelectedLoads = [UInt64]0
$iq1SSidecarFailures = [UInt64]0
$iq1SSidecarRuntimeObserved = $false
$iq1SSidecarLogText = ""
if (Test-Path -LiteralPath $stderrLog) {
    $iq1SSidecarLogText += (Get-Content -LiteralPath $stderrLog -Raw)
}
if (Test-Path -LiteralPath $stdoutLog) {
    $iq1SSidecarLogText += "`n" + (Get-Content -LiteralPath $stdoutLog -Raw)
}
$iq1SSidecarSummaryMatches = [regex]::Matches(
    $iq1SSidecarLogText,
    '\[iq1-s-sidecar\] result=summary calls=(\d+) slots=(\d+) selected_loads=(\d+) failures=(\d+)')
if ($Iq1SExpertSidecar) {
    foreach ($marker in @(
            "validated concatenated split GGUF",
            "IQ1_S checkpoint identity validated",
            "IQ1_S routed-expert sidecar validated",
            "CUDA IQ1_S routed-expert sidecar installed")) {
        if ($iq1SSidecarLogText -notmatch [regex]::Escape($marker)) {
            throw "IQ1_S sidecar runtime marker missing: $marker"
        }
    }
    if ($iq1SSidecarSummaryMatches.Count -ne 1) {
        throw "IQ1_S sidecar requires exactly one runtime summary; observed $($iq1SSidecarSummaryMatches.Count)"
    }
    $iq1SSidecarSummary = $iq1SSidecarSummaryMatches[0]
    $iq1SSidecarCalls = [UInt64]$iq1SSidecarSummary.Groups[1].Value
    $iq1SSidecarSlots = [UInt64]$iq1SSidecarSummary.Groups[2].Value
    $iq1SSidecarSelectedLoads = [UInt64]$iq1SSidecarSummary.Groups[3].Value
    $iq1SSidecarFailures = [UInt64]$iq1SSidecarSummary.Groups[4].Value
    if ($iq1SSidecarCalls -eq 0 -or
        $iq1SSidecarSlots -lt $iq1SSidecarCalls -or
        $iq1SSidecarSelectedLoads -ne $iq1SSidecarCalls -or
        $iq1SSidecarFailures -ne 0) {
        throw "IQ1_S sidecar runtime counters are inconsistent"
    }
    $iq1SSidecarRuntimeObserved = $true
} elseif ($iq1SSidecarSummaryMatches.Count -ne 0) {
    throw "IQ1_S sidecar runtime summary appeared while sidecar was disabled"
}

$iq1SRamCacheRequestedBytes = [UInt64]0
$iq1SRamCacheAllocatedBytes = [UInt64]0
$iq1SRamCacheCapacity = [UInt32]0
$iq1SRamCacheCount = [UInt32]0
$iq1SRamCacheSlotBytes = [UInt64]0
$iq1SRamCacheHits = [UInt64]0
$iq1SRamCacheMisses = [UInt64]0
$iq1SRamCacheEvictions = [UInt64]0
$iq1SRamCacheSsdBytes = [UInt64]0
$iq1SRamCacheH2dBytes = [UInt64]0
$iq1SRamCacheFailures = [UInt64]0
$iq1SRamCacheHitRate = 0.0
$iq1SRamCacheSsdAvoidedBytes = [UInt64]0
$iq1SRamCacheRuntimeObserved = $false
$iq1SRamCachePreloadFrozen = $false
$iq1SRamCachePreloadLayers = [UInt32]0
$iq1SRamCachePreloadEntries = [UInt64]0
$iq1SRamCachePreloadSsdBytes = [UInt64]0
$iq1SRamCachePreloadReadCalls = [UInt64]0
$iq1SRamCachePreloadMs = 0.0
$iq1SRamCacheReadyPattern = if ($Iq1SRamCachePreloadAll) {
    '\[iq1-s-ram-cache\] result=ready requested_gib=([0-9.]+) allocated_gib=([0-9.]+) capacity=(\d+) slot_bytes=(\d+) pinned=0 pageable=1 mapped=0 policy=frozen-full preload_all=1'
} else {
    '\[iq1-s-ram-cache\] result=ready requested_gib=([0-9.]+) allocated_gib=([0-9.]+) capacity=(\d+) slot_bytes=(\d+) pinned=1 mapped=0 policy=lru'
}
$iq1SRamCacheSummaryPattern = if ($Iq1SRamCachePreloadAll) {
    '\[iq1-s-ram-cache\] result=summary requested_bytes=(\d+) allocated_bytes=(\d+) capacity=(\d+) count=(\d+) slot_bytes=(\d+) hits=(\d+) misses=(\d+) evictions=(\d+) ssd_bytes=(\d+) h2d_bytes=(\d+) failures=(\d+) pinned=0 pageable=1 mapped=0 policy=frozen-full preload_all=1 frozen=(\d+) preload_layers=(\d+) preload_entries=(\d+) preload_ssd_bytes=(\d+) preload_read_calls=(\d+) preload_ms=([0-9.]+)'
} else {
    '\[iq1-s-ram-cache\] result=summary requested_bytes=(\d+) allocated_bytes=(\d+) capacity=(\d+) count=(\d+) slot_bytes=(\d+) hits=(\d+) misses=(\d+) evictions=(\d+) ssd_bytes=(\d+) h2d_bytes=(\d+) failures=(\d+) pinned=1 mapped=0'
}
$iq1SRamCacheReadyMatches = [regex]::Matches(
    $iq1SSidecarLogText, $iq1SRamCacheReadyPattern)
$iq1SRamCacheSummaryMatches = [regex]::Matches(
    $iq1SSidecarLogText, $iq1SRamCacheSummaryPattern)
if ($Iq1SRamCacheGiB -gt 0.0) {
    if ($iq1SRamCacheReadyMatches.Count -ne 1 -or
        $iq1SRamCacheSummaryMatches.Count -ne 1) {
        throw "IQ1_S RAM cache requires exactly one ready marker and one summary; observed ready=$($iq1SRamCacheReadyMatches.Count) summary=$($iq1SRamCacheSummaryMatches.Count)"
    }
    $iq1SRamCacheSummary = $iq1SRamCacheSummaryMatches[0]
    $iq1SRamCacheRequestedBytes = [UInt64]$iq1SRamCacheSummary.Groups[1].Value
    $iq1SRamCacheAllocatedBytes = [UInt64]$iq1SRamCacheSummary.Groups[2].Value
    $iq1SRamCacheCapacity = [UInt32]$iq1SRamCacheSummary.Groups[3].Value
    $iq1SRamCacheCount = [UInt32]$iq1SRamCacheSummary.Groups[4].Value
    $iq1SRamCacheSlotBytes = [UInt64]$iq1SRamCacheSummary.Groups[5].Value
    $iq1SRamCacheHits = [UInt64]$iq1SRamCacheSummary.Groups[6].Value
    $iq1SRamCacheMisses = [UInt64]$iq1SRamCacheSummary.Groups[7].Value
    $iq1SRamCacheEvictions = [UInt64]$iq1SRamCacheSummary.Groups[8].Value
    $iq1SRamCacheSsdBytes = [UInt64]$iq1SRamCacheSummary.Groups[9].Value
    $iq1SRamCacheH2dBytes = [UInt64]$iq1SRamCacheSummary.Groups[10].Value
    $iq1SRamCacheFailures = [UInt64]$iq1SRamCacheSummary.Groups[11].Value
    if ($Iq1SRamCachePreloadAll) {
        $iq1SRamCachePreloadFrozen =
            [UInt32]$iq1SRamCacheSummary.Groups[12].Value -eq 1
        $iq1SRamCachePreloadLayers =
            [UInt32]$iq1SRamCacheSummary.Groups[13].Value
        $iq1SRamCachePreloadEntries =
            [UInt64]$iq1SRamCacheSummary.Groups[14].Value
        $iq1SRamCachePreloadSsdBytes =
            [UInt64]$iq1SRamCacheSummary.Groups[15].Value
        $iq1SRamCachePreloadReadCalls =
            [UInt64]$iq1SRamCacheSummary.Groups[16].Value
        $iq1SRamCachePreloadMs = [double]::Parse(
            $iq1SRamCacheSummary.Groups[17].Value,
            [Globalization.CultureInfo]::InvariantCulture)
    }
    $iq1SRamCacheExpectedSsdBytes = [UInt64]($iq1SRamCacheMisses * $iq1SRamCacheSlotBytes)
    $iq1SRamCacheExpectedH2dBytes = [UInt64](
        ($iq1SRamCacheHits + $iq1SRamCacheMisses) * $iq1SRamCacheSlotBytes)
    $iq1SRamCacheCommonInvalid =
        $iq1SRamCacheRequestedBytes -eq 0 -or
        $iq1SRamCacheAllocatedBytes -eq 0 -or
        $iq1SRamCacheCapacity -eq 0 -or
        $iq1SRamCacheCount -gt $iq1SRamCacheCapacity -or
        $iq1SRamCacheSlotBytes -eq 0 -or
        ($iq1SRamCacheHits + $iq1SRamCacheMisses) -eq 0 -or
        $iq1SRamCacheH2dBytes -ne $iq1SRamCacheExpectedH2dBytes -or
        $iq1SRamCacheFailures -ne 0
    $iq1SRamCachePolicyInvalid = if ($Iq1SRamCachePreloadAll) {
        $iq1SRamCacheCapacity -ne 10240 -or
        $iq1SRamCacheCount -ne 10240 -or
        $iq1SRamCacheMisses -ne 0 -or
        $iq1SRamCacheEvictions -ne 0 -or
        $iq1SRamCacheSsdBytes -ne 0 -or
        -not $iq1SRamCachePreloadFrozen -or
        $iq1SRamCachePreloadLayers -ne 40 -or
        $iq1SRamCachePreloadEntries -ne 10240 -or
        $iq1SRamCachePreloadSsdBytes -ne
            ([UInt64]10240 * $iq1SRamCacheSlotBytes) -or
        $iq1SRamCachePreloadReadCalls -ne ([UInt64]10240 * 3) -or
        $iq1SRamCachePreloadMs -le 0.0
    } else {
        ($iq1SRamCacheCount + $iq1SRamCacheEvictions) -ne
            $iq1SRamCacheMisses -or
        $iq1SRamCacheSsdBytes -ne $iq1SRamCacheExpectedSsdBytes
    }
    if ($iq1SRamCacheCommonInvalid -or $iq1SRamCachePolicyInvalid) {
        throw "IQ1_S RAM cache runtime counters are inconsistent"
    }
    $iq1SRamCacheAccesses = [UInt64]($iq1SRamCacheHits + $iq1SRamCacheMisses)
    $iq1SRamCacheHitRate = [double]$iq1SRamCacheHits / [double]$iq1SRamCacheAccesses
    $iq1SRamCacheSsdAvoidedBytes = [UInt64]($iq1SRamCacheHits * $iq1SRamCacheSlotBytes)
    $iq1SRamCacheRuntimeObserved = $true
} elseif ($iq1SRamCacheReadyMatches.Count -ne 0 -or
          $iq1SRamCacheSummaryMatches.Count -ne 0) {
    throw "IQ1_S RAM cache telemetry appeared while the cache was disabled"
}

$iq1SVramCacheRuntimeObserved = $false
$iq1SVramCacheCapacity = [UInt32]0
$iq1SVramCacheCount = [UInt32]0
$iq1SVramCacheSlotBytes = [UInt64]0
$iq1SVramCacheHits = [UInt64]0
$iq1SVramCacheMisses = [UInt64]0
$iq1SVramCacheEvictions = [UInt64]0
$iq1SVramCacheH2dBytes = [UInt64]0
$iq1SVramCacheFailures = [UInt64]0
$iq1SVramCacheReadyMatches = [regex]::Matches(
    $iq1SSidecarLogText,
    '\[iq1-s-vram-cache\] result=ready per_layer=(\d+) capacity=(\d+) allocated_bytes=(\d+) slot_bytes=(\d+) policy=layer-lru')
$iq1SVramCacheSummaryMatches = [regex]::Matches(
    $iq1SSidecarLogText,
    '\[iq1-s-vram-cache\] result=summary per_layer=(\d+) capacity=(\d+) count=(\d+) slot_bytes=(\d+) hits=(\d+) misses=(\d+) evictions=(\d+) h2d_bytes=(\d+) failures=(\d+)')
if ($Iq1SVramCachePerLayer -gt 0) {
    if ($iq1SVramCacheReadyMatches.Count -ne 1 -or
        $iq1SVramCacheSummaryMatches.Count -ne 1) {
        throw "IQ1_S VRAM cache requires exactly one ready marker and summary; observed ready=$($iq1SVramCacheReadyMatches.Count) summary=$($iq1SVramCacheSummaryMatches.Count)"
    }
    $iq1SVramReady = $iq1SVramCacheReadyMatches[0]
    $iq1SVramSummary = $iq1SVramCacheSummaryMatches[0]
    $iq1SVramReadyPerLayer = [UInt32]$iq1SVramReady.Groups[1].Value
    $iq1SVramReadyCapacity = [UInt32]$iq1SVramReady.Groups[2].Value
    $iq1SVramReadyAllocatedBytes = [UInt64]$iq1SVramReady.Groups[3].Value
    $iq1SVramReadySlotBytes = [UInt64]$iq1SVramReady.Groups[4].Value
    $iq1SVramSummaryPerLayer = [UInt32]$iq1SVramSummary.Groups[1].Value
    $iq1SVramCacheCapacity = [UInt32]$iq1SVramSummary.Groups[2].Value
    $iq1SVramCacheCount = [UInt32]$iq1SVramSummary.Groups[3].Value
    $iq1SVramCacheSlotBytes = [UInt64]$iq1SVramSummary.Groups[4].Value
    $iq1SVramCacheHits = [UInt64]$iq1SVramSummary.Groups[5].Value
    $iq1SVramCacheMisses = [UInt64]$iq1SVramSummary.Groups[6].Value
    $iq1SVramCacheEvictions = [UInt64]$iq1SVramSummary.Groups[7].Value
    $iq1SVramCacheH2dBytes = [UInt64]$iq1SVramSummary.Groups[8].Value
    $iq1SVramCacheFailures = [UInt64]$iq1SVramSummary.Groups[9].Value
    $iq1SVramExpectedCapacity = [UInt32](43 * $Iq1SVramCachePerLayer)
    $iq1SVramExpectedH2dBytes = [UInt64]($iq1SVramCacheMisses * $iq1SVramCacheSlotBytes)
    if ($iq1SVramReadyPerLayer -ne $Iq1SVramCachePerLayer -or
        $iq1SVramSummaryPerLayer -ne $Iq1SVramCachePerLayer -or
        $iq1SVramReadyCapacity -ne $iq1SVramExpectedCapacity -or
        $iq1SVramCacheCapacity -ne $iq1SVramExpectedCapacity -or
        $iq1SVramReadySlotBytes -ne $iq1SVramCacheSlotBytes -or
        $iq1SVramReadyAllocatedBytes -ne
            ([UInt64]$iq1SVramCacheCapacity * $iq1SVramCacheSlotBytes) -or
        $iq1SVramCacheCount -gt $iq1SVramCacheCapacity -or
        ($iq1SVramCacheCount + $iq1SVramCacheEvictions) -ne
            $iq1SVramCacheMisses -or
        ($iq1SVramCacheHits + $iq1SVramCacheMisses) -ne
            $iq1SSidecarCalls -or
        $iq1SVramCacheH2dBytes -ne $iq1SVramExpectedH2dBytes -or
        $iq1SVramCacheFailures -ne 0) {
        throw "IQ1_S VRAM cache runtime counters are inconsistent"
    }
    $iq1SVramCacheRuntimeObserved = $true
} elseif ($iq1SVramCacheReadyMatches.Count -ne 0 -or
          $iq1SVramCacheSummaryMatches.Count -ne 0) {
    throw "IQ1_S VRAM cache telemetry appeared while the cache was disabled"
}

$iq1MixedCalls = [UInt64]0
$iq1MixedHotMain = [UInt64]0
$iq1MixedColdIq1 = [UInt64]0
$iq1MixedPrimaryColdAvoided = [UInt64]0
$iq1MixedJoins = [UInt64]0
$iq1MixedFailures = [UInt64]0
$iq1MixedLastLayer = [UInt32]::MaxValue
$iq1MixedLastSlot = [UInt32]::MaxValue
$iq1MixedLastExpert = -1
$iq1MixedRuntimeObserved = $false
$iq1MixedGpuPlanRuntimeObserved = $false
$iq1MixedGpuPlanCalls = [UInt64]0
$iq1MixedGpuPlanWaitMs = 0.0
$iq1MixedGpuPlanFailures = [UInt64]0
$iq1PromotionRuntimeObserved = $false
$iq1PromotionLineCount = 0
$iq1PromotionRows = @()
$iq1PromotionRequestedSlots = [UInt64]0
$iq1PromotionReservedSlots = [UInt64]0
$iq1PromotionSnapshotEvictions = [UInt64]0
$iq1PromotionReserveStrategies = @()
$iq1PromotionObservedMinTouches = 0
$iq1PromotionObservedMinWeight = 0.0
$iq1PromotionObservedMinMass = 0.0
$iq1PromotionObservedRequestBudget = 0
$iq1PromotionObservedWindowCalls = 0
$iq1PromotionObservedWindowBudget = 0
$iq1PromotionColdObserved = [UInt64]0
$iq1PromotionColdExisting2Bit = [UInt64]0
$iq1PromotionColdTo2BitRam = [UInt64]0
$iq1PromotionColdGateCandidates = [UInt64]0
$iq1PromotionWeightGe001 = [UInt64]0
$iq1PromotionWeightGe002 = [UInt64]0
$iq1PromotionWeightGe005 = [UInt64]0
$iq1PromotionWeightGe010 = [UInt64]0
$iq1PromotionSkipsTouches = [UInt64]0
$iq1PromotionSkipsWeight = [UInt64]0
$iq1PromotionSkipsMass = [UInt64]0
$iq1PromotionSkipsRequestBudget = [UInt64]0
$iq1PromotionSkipsWindowBudget = [UInt64]0
$iq1PromotionProbationRamHits = [UInt64]0
$iq1PromotionNextTokenWaits = [UInt64]0
$iq1Promotion2BitSsdBytes = [UInt64]0
$iq1Promotion2BitSsdSeconds = 0.0
$iq1Promotion2BitSsdBytesPerSecond = 0.0
$iq1PromotionDirectSsdToVramRejected = [UInt64]0
$iq1PromotionProbationBackingReclaims = [UInt64]0
$iq1PromotionQ1_0Observed = [UInt64]0
$iq1PromotionQ1_0StageAttempts = [UInt64]0
$iq1PromotionQ1_0StageSuccesses = [UInt64]0
$iq1PromotionQ1_0NextCallGuards = [UInt64]0
$iq1PromotionQ1_0RecordRejects = [UInt64]0
$iq1PromotionQ1_0RecordAttempts = [UInt64]0
$iq1PromotionQ1_0RecordSuccesses = [UInt64]0
$iq1PromotionQ1_0RecordFailures = [UInt64]0
$iq1PromotionFailures = [UInt64]0
$q1_0PromotionRecords = @()
$q1_0PromotionRecordArtifactPath = ""
$q1_0PromotionRecordArtifactSHA256 = ""
$q1_0PromotionRecordCount = [UInt64]0
$q1_0PromotionRecordPhysicalLineCount = [UInt64]0
$q1_0PromotionRecordAttemptCount = [UInt64]0
$q1_0PromotionRecordSuccessCount = [UInt64]0
$q1_0PromotionRecordRejectCount = [UInt64]0
$q1_0PromotionRecordFailureCount = [UInt64]0
$q1_0PromotionRecordBoundedExceptionLimit = [UInt64]16
$q1_0PromotionTelemetryRecordLimit = [UInt64]0
$iq1MixedSummaryMatches = [regex]::Matches(
    $iq1SSidecarLogText,
    '\[iq1-mixed\] result=summary calls=(\d+) hot_main=(\d+) cold_iq1=(\d+) primary_cold_avoided=(\d+) joins=(\d+) failures=(\d+) last_layer=(\d+) last_slot=(\d+) last_expert=(-?\d+)')
$iq1MixedGpuPlanReadyMatches = [regex]::Matches(
    $iq1SSidecarLogText,
    '\[iq1-mixed-gpu-plan\] result=ready mode=cold-one-upload-overlap')
$iq1MixedGpuPlanSummaryMatches = [regex]::Matches(
    $iq1SSidecarLogText,
    '\[iq1-mixed-gpu-plan\] result=summary calls=(\d+) wait_ms=([0-9.]+) failures=(\d+)')
if ($Iq1SMixedColdOne) {
    if ($iq1MixedSummaryMatches.Count -ne 1) {
        throw "IQ1_S mixed decode requires exactly one runtime summary; observed $($iq1MixedSummaryMatches.Count)"
    }
    $iq1MixedSummary = $iq1MixedSummaryMatches[0]
    $iq1MixedCalls = [UInt64]$iq1MixedSummary.Groups[1].Value
    $iq1MixedHotMain = [UInt64]$iq1MixedSummary.Groups[2].Value
    $iq1MixedColdIq1 = [UInt64]$iq1MixedSummary.Groups[3].Value
    $iq1MixedPrimaryColdAvoided = [UInt64]$iq1MixedSummary.Groups[4].Value
    $iq1MixedJoins = [UInt64]$iq1MixedSummary.Groups[5].Value
    $iq1MixedFailures = [UInt64]$iq1MixedSummary.Groups[6].Value
    $iq1MixedLastLayer = [UInt32]$iq1MixedSummary.Groups[7].Value
    $iq1MixedLastSlot = [UInt32]$iq1MixedSummary.Groups[8].Value
    $iq1MixedLastExpert = [int]$iq1MixedSummary.Groups[9].Value
    if ($iq1MixedCalls -eq 0 -or
        $iq1MixedHotMain -ne (5 * $iq1MixedCalls) -or
        $iq1MixedColdIq1 -ne $iq1MixedCalls -or
        $iq1MixedPrimaryColdAvoided -ne $iq1MixedCalls -or
        $iq1MixedJoins -ne $iq1MixedCalls -or
        $iq1MixedFailures -ne 0 -or
        $iq1MixedLastSlot -ge 6 -or
        $iq1MixedLastExpert -lt 0) {
        throw "IQ1_S mixed decode runtime counters are inconsistent"
    }
    $iq1MixedRuntimeObserved = $true
} elseif ($iq1MixedSummaryMatches.Count -ne 0) {
    throw "IQ1_S mixed decode summary appeared while mixed mode was disabled"
}
if ($Iq1SMixedGpuPlan) {
    if ($iq1MixedGpuPlanReadyMatches.Count -ne 1 -or
        $iq1MixedGpuPlanSummaryMatches.Count -ne 1) {
        throw "IQ1_S mixed GPU plan requires exactly one ready marker and one summary; observed ready=$($iq1MixedGpuPlanReadyMatches.Count) summary=$($iq1MixedGpuPlanSummaryMatches.Count)"
    }
    $iq1MixedGpuPlanSummary = $iq1MixedGpuPlanSummaryMatches[0]
    $iq1MixedGpuPlanCalls = [UInt64]$iq1MixedGpuPlanSummary.Groups[1].Value
    $iq1MixedGpuPlanWaitMs = [double]::Parse($iq1MixedGpuPlanSummary.Groups[2].Value, [Globalization.CultureInfo]::InvariantCulture)
    $iq1MixedGpuPlanFailures = [UInt64]$iq1MixedGpuPlanSummary.Groups[3].Value
    if ($iq1MixedGpuPlanCalls -ne $iq1MixedCalls -or
        $iq1MixedGpuPlanFailures -ne 0) {
        throw "IQ1_S mixed GPU plan runtime counters are inconsistent"
    }
    $iq1MixedGpuPlanRuntimeObserved = $true
} elseif ($iq1MixedGpuPlanReadyMatches.Count -ne 0 -or
          $iq1MixedGpuPlanSummaryMatches.Count -ne 0) {
    throw "IQ1_S mixed GPU plan telemetry appeared while GPU plan was disabled"
}

$iq1PromotionMatches = [regex]::Matches(
    $iq1SSidecarLogText,
    '(?m)^(?:ds4: )?\[iq1-promotion\] final (?<kv>.+?)\r?$')
$iq1PromotionLineCount = $iq1PromotionMatches.Count
if ($quantPromotionRequested) {
    if ($iq1PromotionLineCount -ne $requestCountExpected) {
        throw "IQ1 promotion requires one final line per request; expected $requestCountExpected observed $iq1PromotionLineCount"
    }
    $iq1PromotionRequiredFields = @(
        "requested_slots", "reserved_slots", "snapshot_evictions",
        "min_touches", "min_weight", "min_mass", "request_budget",
        "window_calls", "window_budget", "cold_gate_candidates",
        "weight_ge_001", "weight_ge_002", "weight_ge_005",
        "weight_ge_010", "skips_touches", "skips_weight",
        "skips_mass", "skips_request_budget", "skips_window_budget",
        "cold_observed", "cold_existing_2bit", "cold_to_2bit_ram",
        "probation_ram_hits", "next_token_waits",
        "promotion_2bit_ssd_bytes", "promotion_2bit_ssd_seconds",
        "direct_ssd_to_vram_rejected", "probation_backing_reclaims",
        "q1_0_observed", "q1_0_stage_attempts",
        "q1_0_stage_successes", "q1_0_next_call_guards",
        "q1_0_record_rejects", "q1_0_record_attempts",
        "q1_0_record_successes", "q1_0_record_failures",
        "failures")
    for ($iq1PromotionIndex = 0; $iq1PromotionIndex -lt $iq1PromotionMatches.Count; $iq1PromotionIndex++) {
        $iq1PromotionMatch = $iq1PromotionMatches[$iq1PromotionIndex]
        $iq1PromotionFields = @{}
        foreach ($iq1PromotionPart in @($iq1PromotionMatch.Groups["kv"].Value -split " ")) {
            if ([string]::IsNullOrWhiteSpace($iq1PromotionPart)) { continue }
            $iq1PromotionSeparator = $iq1PromotionPart.IndexOf("=")
            if ($iq1PromotionSeparator -le 0) {
                throw "IQ1 promotion malformed key/value token at request $($iq1PromotionIndex + 1): $iq1PromotionPart"
            }
            $iq1PromotionKey = $iq1PromotionPart.Substring(0, $iq1PromotionSeparator)
            $iq1PromotionValue = $iq1PromotionPart.Substring($iq1PromotionSeparator + 1)
            if ($iq1PromotionFields.ContainsKey($iq1PromotionKey)) {
                throw "IQ1 promotion duplicate telemetry key at request $($iq1PromotionIndex + 1): $iq1PromotionKey"
            }
            $iq1PromotionFields[$iq1PromotionKey] = $iq1PromotionValue
        }
        foreach ($iq1PromotionKey in @($iq1PromotionFields.Keys)) {
            if ($iq1PromotionKey -ne "strategy" -and
                $iq1PromotionRequiredFields -notcontains $iq1PromotionKey) {
                throw "IQ1 promotion unexpected telemetry key at request $($iq1PromotionIndex + 1): $iq1PromotionKey"
            }
        }
        foreach ($iq1PromotionRequiredField in $iq1PromotionRequiredFields) {
            if (-not $iq1PromotionFields.ContainsKey($iq1PromotionRequiredField)) {
                throw "IQ1 promotion final telemetry omitted $iq1PromotionRequiredField at request $($iq1PromotionIndex + 1)"
            }
        }
        $iq1PromotionRow = [pscustomobject]@{
            request_index = ($iq1PromotionIndex + 1)
            repeat = $(if ($Warmup -and $iq1PromotionIndex -eq 0) { 0 } else { $iq1PromotionIndex + $(if ($Warmup) { 0 } else { 1 }) })
            warmup = [bool]($Warmup -and $iq1PromotionIndex -eq 0)
            requested_slots = [UInt64]$iq1PromotionFields["requested_slots"]
            reserved_slots = [UInt64]$iq1PromotionFields["reserved_slots"]
            reserve_strategy = $(if ($iq1PromotionFields.ContainsKey("strategy")) { $iq1PromotionFields["strategy"] } else { "snapshot-evict" })
            snapshot_evictions = [UInt64]$iq1PromotionFields["snapshot_evictions"]
            min_touches = [int]$iq1PromotionFields["min_touches"]
            min_weight = [double]::Parse($iq1PromotionFields["min_weight"], [Globalization.CultureInfo]::InvariantCulture)
            min_mass = [double]::Parse($iq1PromotionFields["min_mass"], [Globalization.CultureInfo]::InvariantCulture)
            request_budget = [int]$iq1PromotionFields["request_budget"]
            window_calls = [int]$iq1PromotionFields["window_calls"]
            window_budget = [int]$iq1PromotionFields["window_budget"]
            cold_gate_candidates = [UInt64]$iq1PromotionFields["cold_gate_candidates"]
            weight_ge_001 = [UInt64]$iq1PromotionFields["weight_ge_001"]
            weight_ge_002 = [UInt64]$iq1PromotionFields["weight_ge_002"]
            weight_ge_005 = [UInt64]$iq1PromotionFields["weight_ge_005"]
            weight_ge_010 = [UInt64]$iq1PromotionFields["weight_ge_010"]
            skips_touches = [UInt64]$iq1PromotionFields["skips_touches"]
            skips_weight = [UInt64]$iq1PromotionFields["skips_weight"]
            skips_mass = [UInt64]$iq1PromotionFields["skips_mass"]
            skips_request_budget = [UInt64]$iq1PromotionFields["skips_request_budget"]
            skips_window_budget = [UInt64]$iq1PromotionFields["skips_window_budget"]
            cold_observed = [UInt64]$iq1PromotionFields["cold_observed"]
            cold_existing_2bit = [UInt64]$iq1PromotionFields["cold_existing_2bit"]
            cold_to_2bit_ram = [UInt64]$iq1PromotionFields["cold_to_2bit_ram"]
            probation_ram_hits = [UInt64]$iq1PromotionFields["probation_ram_hits"]
            next_token_waits = [UInt64]$iq1PromotionFields["next_token_waits"]
            promotion_2bit_ssd_bytes = [UInt64]$iq1PromotionFields["promotion_2bit_ssd_bytes"]
            promotion_2bit_ssd_seconds = [double]::Parse(
                $iq1PromotionFields["promotion_2bit_ssd_seconds"],
                [Globalization.CultureInfo]::InvariantCulture)
            direct_ssd_to_vram_rejected = [UInt64]$iq1PromotionFields["direct_ssd_to_vram_rejected"]
            probation_backing_reclaims = [UInt64]$iq1PromotionFields["probation_backing_reclaims"]
            q1_0_observed = [UInt64]$iq1PromotionFields["q1_0_observed"]
            q1_0_stage_attempts = [UInt64]$iq1PromotionFields["q1_0_stage_attempts"]
            q1_0_stage_successes = [UInt64]$iq1PromotionFields["q1_0_stage_successes"]
            q1_0_next_call_guards = [UInt64]$iq1PromotionFields["q1_0_next_call_guards"]
            q1_0_record_rejects = [UInt64]$iq1PromotionFields["q1_0_record_rejects"]
            q1_0_record_attempts = [UInt64]$iq1PromotionFields["q1_0_record_attempts"]
            q1_0_record_successes = [UInt64]$iq1PromotionFields["q1_0_record_successes"]
            q1_0_record_failures = [UInt64]$iq1PromotionFields["q1_0_record_failures"]
            failures = [UInt64]$iq1PromotionFields["failures"]
        }
        if ([double]::IsNaN($iq1PromotionRow.min_weight) -or
            [double]::IsInfinity($iq1PromotionRow.min_weight) -or
            $iq1PromotionRow.min_weight -lt 0.0 -or
            [double]::IsNaN($iq1PromotionRow.min_mass) -or
            [double]::IsInfinity($iq1PromotionRow.min_mass) -or
            $iq1PromotionRow.min_mass -lt 0.0 -or
            [double]::IsNaN($iq1PromotionRow.promotion_2bit_ssd_seconds) -or
            [double]::IsInfinity($iq1PromotionRow.promotion_2bit_ssd_seconds) -or
            $iq1PromotionRow.promotion_2bit_ssd_seconds -lt 0.0) {
            throw "IQ1 promotion numeric telemetry is invalid at request $($iq1PromotionIndex + 1)"
        }
        $expectedPromotionSnapshotEvictions = if ($ComposePrefillMassOpenRouter) { [UInt64]0 } else { [UInt64]$promotionProbationSlotsExpected }
        [UInt64]$iq1PromotionSuppressed =
            $iq1PromotionRow.skips_touches +
            $iq1PromotionRow.skips_weight +
            $iq1PromotionRow.skips_mass +
            $iq1PromotionRow.skips_request_budget +
            $iq1PromotionRow.skips_window_budget
        if ($iq1PromotionRow.requested_slots -ne [UInt64]$promotionProbationSlotsExpected -or
            $iq1PromotionRow.reserved_slots -ne [UInt64]$promotionProbationSlotsExpected -or
            $iq1PromotionRow.min_touches -ne $promotionMinTouchesExpected -or
            [math]::Abs($iq1PromotionRow.min_weight - $promotionMinWeightExpected) -gt 0.000000000001 -or
            [math]::Abs($iq1PromotionRow.min_mass - $promotionMinMassExpected) -gt 0.000000000001 -or
            $iq1PromotionRow.request_budget -ne $promotionRequestBudgetExpected -or
            $iq1PromotionRow.window_calls -ne $promotionWindowCallsExpected -or
            $iq1PromotionRow.window_budget -ne $promotionWindowBudgetExpected -or
            ($ComposePrefillMassOpenRouter -and $iq1PromotionRow.reserve_strategy -ne "pre-reserved-open-router") -or
            $iq1PromotionRow.snapshot_evictions -ne $expectedPromotionSnapshotEvictions -or
            $iq1PromotionRow.cold_observed -le 0 -or
            ($iq1PromotionRow.cold_existing_2bit +
                $iq1PromotionRow.cold_gate_candidates) -le 0 -or
            $iq1PromotionRow.cold_gate_candidates -ne
                ($iq1PromotionRow.cold_to_2bit_ram +
                 $iq1PromotionSuppressed) -or
            $iq1PromotionRow.direct_ssd_to_vram_rejected -ne 0 -or
            ($Q1_0DynamicPromotion -and
             ($iq1PromotionRow.q1_0_observed -eq 0 -or
              $iq1PromotionRow.q1_0_stage_attempts -eq 0 -or
              $iq1PromotionRow.q1_0_stage_successes -eq 0 -or
              $iq1PromotionRow.q1_0_stage_successes -gt
                $iq1PromotionRow.q1_0_stage_attempts -or
              $iq1PromotionRow.q1_0_next_call_guards -ne
                $iq1PromotionRow.q1_0_stage_successes -or
              $iq1PromotionRow.q1_0_record_attempts -ne
                $iq1PromotionRow.q1_0_stage_attempts -or
              $iq1PromotionRow.q1_0_record_successes -ne
                $iq1PromotionRow.q1_0_stage_successes -or
              $iq1PromotionRow.q1_0_record_failures -ne
                $iq1PromotionRow.failures)) -or
            (-not $Q1_0DynamicPromotion -and
             ($iq1PromotionRow.q1_0_observed -ne 0 -or
              $iq1PromotionRow.q1_0_stage_attempts -ne 0 -or
              $iq1PromotionRow.q1_0_stage_successes -ne 0 -or
              $iq1PromotionRow.q1_0_next_call_guards -ne 0 -or
              $iq1PromotionRow.q1_0_record_rejects -ne 0 -or
              $iq1PromotionRow.q1_0_record_attempts -ne 0 -or
              $iq1PromotionRow.q1_0_record_successes -ne 0 -or
              $iq1PromotionRow.q1_0_record_failures -ne 0)) -or
            $iq1PromotionRow.failures -ne 0) {
            throw "IQ1 promotion final counters are inconsistent at request $($iq1PromotionIndex + 1)"
        }
        $iq1PromotionRows += $iq1PromotionRow
        $iq1PromotionRequestedSlots += $iq1PromotionRow.requested_slots
        $iq1PromotionReservedSlots += $iq1PromotionRow.reserved_slots
        $iq1PromotionSnapshotEvictions += $iq1PromotionRow.snapshot_evictions
        $iq1PromotionReserveStrategies += $iq1PromotionRow.reserve_strategy
        $iq1PromotionObservedMinTouches = $iq1PromotionRow.min_touches
        $iq1PromotionObservedMinWeight = $iq1PromotionRow.min_weight
        $iq1PromotionObservedMinMass = $iq1PromotionRow.min_mass
        $iq1PromotionObservedRequestBudget = $iq1PromotionRow.request_budget
        $iq1PromotionObservedWindowCalls = $iq1PromotionRow.window_calls
        $iq1PromotionObservedWindowBudget = $iq1PromotionRow.window_budget
        $iq1PromotionColdObserved += $iq1PromotionRow.cold_observed
        $iq1PromotionColdExisting2Bit += $iq1PromotionRow.cold_existing_2bit
        $iq1PromotionColdTo2BitRam += $iq1PromotionRow.cold_to_2bit_ram
        $iq1PromotionColdGateCandidates += $iq1PromotionRow.cold_gate_candidates
        $iq1PromotionWeightGe001 += $iq1PromotionRow.weight_ge_001
        $iq1PromotionWeightGe002 += $iq1PromotionRow.weight_ge_002
        $iq1PromotionWeightGe005 += $iq1PromotionRow.weight_ge_005
        $iq1PromotionWeightGe010 += $iq1PromotionRow.weight_ge_010
        $iq1PromotionSkipsTouches += $iq1PromotionRow.skips_touches
        $iq1PromotionSkipsWeight += $iq1PromotionRow.skips_weight
        $iq1PromotionSkipsMass += $iq1PromotionRow.skips_mass
        $iq1PromotionSkipsRequestBudget += $iq1PromotionRow.skips_request_budget
        $iq1PromotionSkipsWindowBudget += $iq1PromotionRow.skips_window_budget
        $iq1PromotionProbationRamHits += $iq1PromotionRow.probation_ram_hits
        $iq1PromotionNextTokenWaits += $iq1PromotionRow.next_token_waits
        $iq1Promotion2BitSsdBytes += $iq1PromotionRow.promotion_2bit_ssd_bytes
        $iq1Promotion2BitSsdSeconds += $iq1PromotionRow.promotion_2bit_ssd_seconds
        $iq1PromotionDirectSsdToVramRejected += $iq1PromotionRow.direct_ssd_to_vram_rejected
        $iq1PromotionProbationBackingReclaims += $iq1PromotionRow.probation_backing_reclaims
        $iq1PromotionQ1_0Observed += $iq1PromotionRow.q1_0_observed
        $iq1PromotionQ1_0StageAttempts += $iq1PromotionRow.q1_0_stage_attempts
        $iq1PromotionQ1_0StageSuccesses += $iq1PromotionRow.q1_0_stage_successes
        $iq1PromotionQ1_0NextCallGuards += $iq1PromotionRow.q1_0_next_call_guards
        $iq1PromotionQ1_0RecordRejects += $iq1PromotionRow.q1_0_record_rejects
        $iq1PromotionQ1_0RecordAttempts += $iq1PromotionRow.q1_0_record_attempts
        $iq1PromotionQ1_0RecordSuccesses += $iq1PromotionRow.q1_0_record_successes
        $iq1PromotionQ1_0RecordFailures += $iq1PromotionRow.q1_0_record_failures
        $iq1PromotionFailures += $iq1PromotionRow.failures
    }
    if ($iq1Promotion2BitSsdSeconds -gt 0.0) {
        $iq1Promotion2BitSsdBytesPerSecond =
            [double]$iq1Promotion2BitSsdBytes / $iq1Promotion2BitSsdSeconds
    }
    if ($iq1PromotionColdTo2BitRam -le 0 -or
        $iq1Promotion2BitSsdBytes -le 0 -or
        $iq1Promotion2BitSsdSeconds -le 0.0 -or
        $iq1Promotion2BitSsdBytesPerSecond -le 0.0) {
        throw "IQ1 promotion did not exercise a timed IQ2 SSD-to-probation-RAM stage"
    }
    $iq1PromotionRuntimeObserved = $true
} elseif ($iq1PromotionLineCount -ne 0) {
    throw "IQ1 promotion telemetry appeared while promotion was disabled"
}

$q1_0PromotionRecordMatches = @()
if (-not [string]::IsNullOrEmpty($iq1SSidecarLogText)) {
    $q1_0PromotionRecordPhysicalLines = @($iq1SSidecarLogText -split '\r?\n')
    for ($q1_0PromotionRecordPhysicalIndex = 0;
         $q1_0PromotionRecordPhysicalIndex -lt $q1_0PromotionRecordPhysicalLines.Count;
         $q1_0PromotionRecordPhysicalIndex++) {
        $q1_0PromotionRecordPhysicalLine =
            [string]$q1_0PromotionRecordPhysicalLines[$q1_0PromotionRecordPhysicalIndex]
        if ($q1_0PromotionRecordPhysicalLine.Contains(
                '[q1-0-promotion-record]')) {
            $q1_0PromotionRecordMatches += [pscustomobject]@{
                physical_line = $q1_0PromotionRecordPhysicalIndex + 1
                text = $q1_0PromotionRecordPhysicalLine
            }
        }
    }
}
if ($Q1_0DynamicPromotion) {
    if ($q1_0PromotionRecordMatches.Count -eq 0) {
        throw "Q1_0 dynamic promotion requires per-expert promotion records"
    }
    $q1_0PromotionRecordRequiredFields = @(
        "kind", "result", "reason", "record_id", "request_epoch",
        "promotion_window_epoch", "current_call", "observation_call",
        "first_eligible_call",
        "layer", "expert", "touch_count", "weight", "mass",
        "gate_min_touches", "gate_min_weight", "gate_min_mass",
        "gate_request_budget", "gate_request_used", "gate_window_calls",
        "gate_window_budget", "gate_window_used", "source_kind",
        "source_sidecar_sha256", "source_sidecar_size",
        "source_q1_snapshot", "source_gate_base_offset",
        "source_up_base_offset", "source_down_base_offset",
        "source_gate_stride", "source_up_stride", "source_down_stride",
        "source_gate_offset", "source_up_offset",
        "source_down_offset", "source_gate_bytes", "source_up_bytes",
        "source_down_bytes", "source_bytes", "destination_kind",
        "destination_model_sha256", "destination_model_size",
        "destination_gate_base_offset", "destination_up_base_offset",
        "destination_down_base_offset", "destination_gate_stride",
        "destination_up_stride", "destination_down_stride",
        "destination_gate_offset", "destination_up_offset",
        "destination_down_offset", "destination_gate_bytes",
        "destination_up_bytes", "destination_down_bytes",
        "destination_bytes", "destination_ram_slot",
        "destination_ram_generation", "direct_ssd_to_vram_current_token",
        "same_call_eligible")
    $q1_0PromotionRecordAllowed = @{}
    foreach ($field in $q1_0PromotionRecordRequiredFields) {
        $q1_0PromotionRecordAllowed[$field] = $true
    }
    $q1_0PromotionRecordAttemptByKey = @{}
    $q1_0PromotionRecordAttemptIdentities = @{}
    $q1_0PromotionRecordTerminalByKey = @{}
    $q1_0PromotionRecordRejectKeys = @{}
    $q1_0PromotionRecordTerminalFailures = @{}
    $q1_0PromotionRequestBudgetNextByEpoch = @{}
    $q1_0PromotionWindowBudgetNextByEpoch = @{}
    for ($q1_0PromotionRecordIndex = 0;
         $q1_0PromotionRecordIndex -lt $q1_0PromotionRecordMatches.Count;
         $q1_0PromotionRecordIndex++) {
        $match = $q1_0PromotionRecordMatches[$q1_0PromotionRecordIndex]
        $lineMatch = [regex]::Match(
            [string]$match.text,
            '^(?:ds4: )?\[q1-0-promotion-record\] (?<kv>(?:[A-Za-z0-9_]+=[^ \r\n]+)(?: [A-Za-z0-9_]+=[^ \r\n]+)*)$')
        if (-not $lineMatch.Success) {
            throw "Q1_0 promotion malformed marker at physical line $($match.physical_line)"
        }
        $fields = @{}
        foreach ($part in @($lineMatch.Groups["kv"].Value -split " ")) {
            if ($part -notmatch '^([A-Za-z0-9_]+)=([^ \r\n]+)$') {
                throw "Q1_0 promotion record malformed key/value token at physical line $($match.physical_line): $part"
            }
            $key = $Matches[1]
            $value = $Matches[2]
            if (-not $q1_0PromotionRecordAllowed.ContainsKey($key)) {
                throw "Q1_0 promotion record unexpected telemetry key at physical line $($match.physical_line): $key"
            }
            if ($fields.ContainsKey($key)) {
                throw "Q1_0 promotion record duplicate telemetry key at physical line $($match.physical_line): $key"
            }
            $fields[$key] = $value
        }
        foreach ($requiredField in $q1_0PromotionRecordRequiredFields) {
            if (-not $fields.ContainsKey($requiredField)) {
                throw "Q1_0 promotion record omitted $requiredField at physical line $($match.physical_line)"
            }
        }
        $row = [pscustomobject][ordered]@{
            line_index = ($q1_0PromotionRecordIndex + 1)
            physical_line = [int]$match.physical_line
            kind = [string]$fields["kind"]
            result = [string]$fields["result"]
            reason = [string]$fields["reason"]
            record_id = Convert-G7StrictUInt64 $fields["record_id"] "record_id"
            request_epoch = Convert-G7StrictUInt64 $fields["request_epoch"] "request_epoch"
            promotion_window_epoch = Convert-G7StrictUInt64 $fields["promotion_window_epoch"] "promotion_window_epoch"
            current_call = Convert-G7StrictUInt64 $fields["current_call"] "current_call"
            observation_call = Convert-G7StrictUInt64 $fields["observation_call"] "observation_call"
            first_eligible_call = Convert-G7StrictUInt64 $fields["first_eligible_call"] "first_eligible_call"
            layer = Convert-G7StrictUInt32 $fields["layer"] "layer"
            expert = Convert-G7StrictUInt32 $fields["expert"] "expert"
            touch_count = Convert-G7StrictUInt64 $fields["touch_count"] "touch_count"
            weight = Convert-G7StrictDouble $fields["weight"] "weight"
            mass = Convert-G7StrictDouble $fields["mass"] "mass"
            gate_min_touches = Convert-G7StrictUInt64 $fields["gate_min_touches"] "gate_min_touches"
            gate_min_weight = Convert-G7StrictDouble $fields["gate_min_weight"] "gate_min_weight"
            gate_min_mass = Convert-G7StrictDouble $fields["gate_min_mass"] "gate_min_mass"
            gate_request_budget = Convert-G7StrictUInt64 $fields["gate_request_budget"] "gate_request_budget"
            gate_request_used = Convert-G7StrictUInt64 $fields["gate_request_used"] "gate_request_used"
            gate_window_calls = Convert-G7StrictUInt64 $fields["gate_window_calls"] "gate_window_calls"
            gate_window_budget = Convert-G7StrictUInt64 $fields["gate_window_budget"] "gate_window_budget"
            gate_window_used = Convert-G7StrictUInt64 $fields["gate_window_used"] "gate_window_used"
            source_kind = [string]$fields["source_kind"]
            source_sidecar_sha256 = ([string]$fields["source_sidecar_sha256"]).ToLowerInvariant()
            source_sidecar_size = Convert-G7StrictUInt64 $fields["source_sidecar_size"] "source_sidecar_size"
            source_q1_snapshot = Convert-G7StrictFlag01 $fields["source_q1_snapshot"] "source_q1_snapshot"
            source_gate_base_offset = Convert-G7StrictUInt64 $fields["source_gate_base_offset"] "source_gate_base_offset"
            source_up_base_offset = Convert-G7StrictUInt64 $fields["source_up_base_offset"] "source_up_base_offset"
            source_down_base_offset = Convert-G7StrictUInt64 $fields["source_down_base_offset"] "source_down_base_offset"
            source_gate_stride = Convert-G7StrictUInt64 $fields["source_gate_stride"] "source_gate_stride"
            source_up_stride = Convert-G7StrictUInt64 $fields["source_up_stride"] "source_up_stride"
            source_down_stride = Convert-G7StrictUInt64 $fields["source_down_stride"] "source_down_stride"
            source_gate_offset = Convert-G7StrictUInt64 $fields["source_gate_offset"] "source_gate_offset"
            source_up_offset = Convert-G7StrictUInt64 $fields["source_up_offset"] "source_up_offset"
            source_down_offset = Convert-G7StrictUInt64 $fields["source_down_offset"] "source_down_offset"
            source_gate_bytes = Convert-G7StrictUInt64 $fields["source_gate_bytes"] "source_gate_bytes"
            source_up_bytes = Convert-G7StrictUInt64 $fields["source_up_bytes"] "source_up_bytes"
            source_down_bytes = Convert-G7StrictUInt64 $fields["source_down_bytes"] "source_down_bytes"
            source_bytes = Convert-G7StrictUInt64 $fields["source_bytes"] "source_bytes"
            destination_kind = [string]$fields["destination_kind"]
            destination_model_sha256 = ([string]$fields["destination_model_sha256"]).ToLowerInvariant()
            destination_model_size = Convert-G7StrictUInt64 $fields["destination_model_size"] "destination_model_size"
            destination_gate_base_offset = Convert-G7StrictUInt64 $fields["destination_gate_base_offset"] "destination_gate_base_offset"
            destination_up_base_offset = Convert-G7StrictUInt64 $fields["destination_up_base_offset"] "destination_up_base_offset"
            destination_down_base_offset = Convert-G7StrictUInt64 $fields["destination_down_base_offset"] "destination_down_base_offset"
            destination_gate_stride = Convert-G7StrictUInt64 $fields["destination_gate_stride"] "destination_gate_stride"
            destination_up_stride = Convert-G7StrictUInt64 $fields["destination_up_stride"] "destination_up_stride"
            destination_down_stride = Convert-G7StrictUInt64 $fields["destination_down_stride"] "destination_down_stride"
            destination_gate_offset = Convert-G7StrictUInt64 $fields["destination_gate_offset"] "destination_gate_offset"
            destination_up_offset = Convert-G7StrictUInt64 $fields["destination_up_offset"] "destination_up_offset"
            destination_down_offset = Convert-G7StrictUInt64 $fields["destination_down_offset"] "destination_down_offset"
            destination_gate_bytes = Convert-G7StrictUInt64 $fields["destination_gate_bytes"] "destination_gate_bytes"
            destination_up_bytes = Convert-G7StrictUInt64 $fields["destination_up_bytes"] "destination_up_bytes"
            destination_down_bytes = Convert-G7StrictUInt64 $fields["destination_down_bytes"] "destination_down_bytes"
            destination_bytes = Convert-G7StrictUInt64 $fields["destination_bytes"] "destination_bytes"
            destination_ram_slot = Convert-G7StrictUInt64 $fields["destination_ram_slot"] "destination_ram_slot"
            destination_ram_generation = Convert-G7StrictUInt64 $fields["destination_ram_generation"] "destination_ram_generation"
            direct_ssd_to_vram_current_token = Convert-G7StrictFlag01 $fields["direct_ssd_to_vram_current_token"] "direct_ssd_to_vram_current_token"
            same_call_eligible = Convert-G7StrictFlag01 $fields["same_call_eligible"] "same_call_eligible"
        }
        Assert-G7U64Sum3 `
            $row.source_gate_bytes $row.source_up_bytes `
            $row.source_down_bytes $row.source_bytes "source"
        Assert-G7U64Sum3 `
            $row.destination_gate_bytes $row.destination_up_bytes `
            $row.destination_down_bytes $row.destination_bytes "destination"
        Assert-G7PromotionOffsetFormula `
            $row.source_gate_base_offset $row.source_gate_stride `
            $row.expert $row.source_gate_bytes $row.source_gate_offset `
            $row.source_sidecar_size "source_gate"
        Assert-G7PromotionOffsetFormula `
            $row.source_up_base_offset $row.source_up_stride `
            $row.expert $row.source_up_bytes $row.source_up_offset `
            $row.source_sidecar_size "source_up"
        Assert-G7PromotionOffsetFormula `
            $row.source_down_base_offset $row.source_down_stride `
            $row.expert $row.source_down_bytes $row.source_down_offset `
            $row.source_sidecar_size "source_down"
        Assert-G7PromotionOffsetFormula `
            $row.destination_gate_base_offset $row.destination_gate_stride `
            $row.expert $row.destination_gate_bytes `
            $row.destination_gate_offset $row.destination_model_size `
            "destination_gate"
        Assert-G7PromotionOffsetFormula `
            $row.destination_up_base_offset $row.destination_up_stride `
            $row.expert $row.destination_up_bytes `
            $row.destination_up_offset $row.destination_model_size `
            "destination_up"
        Assert-G7PromotionOffsetFormula `
            $row.destination_down_base_offset $row.destination_down_stride `
            $row.expert $row.destination_down_bytes `
            $row.destination_down_offset $row.destination_model_size `
            "destination_down"
        $expectedWindowEpoch = [UInt64]0
        if ($row.gate_window_calls -ne [UInt64]0) {
            $tickForWindow = $(if ($row.current_call -eq [UInt64]0) {
                [UInt64]1
            } else {
                $row.current_call
            })
            $expectedWindowEpoch = [UInt64]([decimal]::Floor(
                ([decimal]$tickForWindow - [decimal]1) /
                [decimal]$row.gate_window_calls))
        }
        if ($row.kind -notin @("reject", "attempt", "success", "failure") -or
            $row.layer -gt 42 -or
            $row.expert -ge 256 -or
            $row.request_epoch -eq 0 -or
            $row.current_call -ne $row.observation_call -or
            ($row.current_call -eq [UInt64]::MaxValue -and
             $row.reason -ne "call_tick_overflow") -or
            $row.promotion_window_epoch -ne $expectedWindowEpoch -or
            $row.same_call_eligible -ne 0 -or
            $row.direct_ssd_to_vram_current_token -ne 0 -or
            $row.source_kind -ne "q1_resident" -or
            $row.source_q1_snapshot -ne 0 -or
            $row.source_sidecar_sha256 -ine $ExpectedQ1_0ExpertSidecarSHA256 -or
            $row.source_sidecar_size -ne $ExpectedQ1_0ExpertSidecarBytes -or
            $row.destination_model_sha256 -ine $ExpectedModelSHA256 -or
            $row.destination_model_size -ne [UInt64]$modelInfoAtStart.Length -or
            $row.gate_min_touches -ne [UInt64]$promotionMinTouchesExpected -or
            [math]::Abs($row.gate_min_weight - $promotionMinWeightExpected) -gt 0.000000000001 -or
            [math]::Abs($row.gate_min_mass - $promotionMinMassExpected) -gt 0.000000000001 -or
            $row.gate_request_budget -ne [UInt64]$promotionRequestBudgetExpected -or
            $row.gate_window_calls -ne [UInt64]$promotionWindowCallsExpected -or
            $row.gate_window_budget -ne [UInt64]$promotionWindowBudgetExpected) {
            throw "Q1_0 promotion record invariant failed at line $($row.line_index)"
        }
        $key = Get-G7PromotionRecordKey $row
        $identity = Get-G7PromotionRecordImmutableIdentity $row
        if ($row.kind -eq "attempt") {
            if ($row.result -ne "attempt" -or
                $row.reason -ne "admitted" -or
                $row.first_eligible_call -le $row.observation_call -or
                $row.touch_count -lt $row.gate_min_touches -or
                [math]::Abs($row.weight) -lt $row.gate_min_weight -or
                $row.mass -lt $row.gate_min_mass -or
                ($row.gate_request_budget -ne [UInt64]0 -and
                 $row.gate_request_used -ge $row.gate_request_budget) -or
                ($row.gate_window_budget -ne [UInt64]0 -and
                 $row.gate_window_used -ge $row.gate_window_budget) -or
                $row.destination_kind -ne "exact_iq2_ram_pending" -or
                $q1_0PromotionRecordAttemptByKey.ContainsKey($key) -or
                $q1_0PromotionRecordAttemptIdentities.ContainsKey($identity)) {
                throw "Q1_0 promotion attempt record failed admission proof at line $($row.line_index)"
            }
            if ($row.gate_request_budget -ne [UInt64]0) {
                $requestScope = [string]$row.request_epoch
                $expectedRequestUsed =
                    if ($q1_0PromotionRequestBudgetNextByEpoch.ContainsKey(
                            $requestScope)) {
                        [UInt64]$q1_0PromotionRequestBudgetNextByEpoch[
                            $requestScope]
                    } else {
                        [UInt64]0
                    }
                if ($row.gate_request_used -ne $expectedRequestUsed -or
                    $expectedRequestUsed -ge $row.gate_request_budget) {
                    throw "Q1_0 promotion request budget sequence failed at line $($row.line_index)"
                }
                $q1_0PromotionRequestBudgetNextByEpoch[$requestScope] =
                    [UInt64]($expectedRequestUsed + [UInt64]1)
            }
            if ($row.gate_window_budget -ne [UInt64]0) {
                $windowScope = ('{0}:{1}' -f
                    $row.request_epoch, $row.promotion_window_epoch)
                $expectedWindowUsed =
                    if ($q1_0PromotionWindowBudgetNextByEpoch.ContainsKey(
                            $windowScope)) {
                        [UInt64]$q1_0PromotionWindowBudgetNextByEpoch[
                            $windowScope]
                    } else {
                        [UInt64]0
                    }
                if ($row.gate_window_used -ne $expectedWindowUsed -or
                    $expectedWindowUsed -ge $row.gate_window_budget) {
                    throw "Q1_0 promotion window budget sequence failed at line $($row.line_index)"
                }
                $q1_0PromotionWindowBudgetNextByEpoch[$windowScope] =
                    [UInt64]($expectedWindowUsed + [UInt64]1)
            }
            $q1_0PromotionRecordAttemptByKey[$key] = $identity
            $q1_0PromotionRecordAttemptIdentities[$identity] = $true
        } elseif ($row.kind -eq "success") {
            if ($row.result -ne "success" -or
                $row.reason -ne "staged" -or
                $row.first_eligible_call -le $row.observation_call -or
                $row.destination_kind -ne "exact_iq2_ram" -or
                $row.destination_ram_slot -eq [UInt64]4294967295 -or
                $row.destination_ram_generation -eq 0 -or
                -not $q1_0PromotionRecordAttemptByKey.ContainsKey($key) -or
                [string]$q1_0PromotionRecordAttemptByKey[$key] -ne $identity -or
                $q1_0PromotionRecordTerminalByKey.ContainsKey($key)) {
                throw "Q1_0 promotion success record failed provenance proof at line $($row.line_index)"
            }
            $q1_0PromotionRecordTerminalByKey[$key] = "success"
        } elseif ($row.kind -eq "reject") {
            if ($row.result -ne "rejected" -or
                $row.reason -notin @(
                    "request_epoch_missing", "call_tick_overflow",
                    "offset_overflow", "ram_admit_alloc", "entry_contract",
                    "destination_offset_overflow",
                    "destination_offset_mismatch") -or
                $row.destination_kind -notin @(
                    "none")) {
                throw "Q1_0 promotion reject record failed reason proof at line $($row.line_index)"
            }
            if (($row.reason -eq "call_tick_overflow" -and
                 ($row.current_call -ne [UInt64]::MaxValue -or
                  $row.first_eligible_call -ne [UInt64]0))) {
                throw "Q1_0 promotion reject predicate failed at line $($row.line_index)"
            }
            $rejectKey = "${identity}:$($row.reason):$($row.destination_kind)"
            if ($q1_0PromotionRecordRejectKeys.ContainsKey($rejectKey)) {
                throw "Q1_0 promotion duplicate reject record at line $($row.line_index)"
            }
            $q1_0PromotionRecordRejectKeys[$rejectKey] = $true
        } else {
            if ($row.result -ne "failed" -or
                $row.reason -notin @("pread_failed", "victim_contract") -or
                $row.first_eligible_call -le $row.observation_call -or
                $row.destination_kind -ne "exact_iq2_ram_failed" -or
                -not $q1_0PromotionRecordAttemptByKey.ContainsKey($key) -or
                [string]$q1_0PromotionRecordAttemptByKey[$key] -ne $identity -or
                $q1_0PromotionRecordTerminalByKey.ContainsKey($key)) {
                throw "Q1_0 promotion failure record failed reason proof at line $($row.line_index)"
            }
            $q1_0PromotionRecordTerminalByKey[$key] = "failure"
            $q1_0PromotionRecordTerminalFailures[$key] = $true
        }
        $q1_0PromotionRecords += $row
    }
    foreach ($attemptKey in @($q1_0PromotionRecordAttemptByKey.Keys)) {
        if (-not $q1_0PromotionRecordTerminalByKey.ContainsKey($attemptKey)) {
            throw "Q1_0 promotion attempt missing terminal record: $attemptKey"
        }
    }
    $q1_0PromotionRecordCount = [UInt64]$q1_0PromotionRecords.Count
    $q1_0PromotionRecordAttemptCount = [UInt64](
        @($q1_0PromotionRecords | Where-Object { $_.kind -eq "attempt" }).Count)
    $q1_0PromotionRecordSuccessCount = [UInt64](
        @($q1_0PromotionRecords | Where-Object { $_.kind -eq "success" }).Count)
    $q1_0PromotionRecordRejectCount = [UInt64](
        @($q1_0PromotionRecords | Where-Object { $_.kind -eq "reject" }).Count)
    $q1_0PromotionRecordFailureCount = [UInt64](
        @($q1_0PromotionRecords | Where-Object { $_.kind -eq "failure" }).Count)
    $q1_0PromotionTelemetryRecordLimitDecimal =
        ([decimal]$q1_0PromotionRecordAttemptCount * [decimal]2) +
        [decimal]$q1_0PromotionRecordBoundedExceptionLimit
    if ($q1_0PromotionTelemetryRecordLimitDecimal -gt
            [decimal][UInt64]::MaxValue) {
        throw "Q1_0 promotion telemetry record limit overflow"
    }
    $q1_0PromotionTelemetryRecordLimit =
        [UInt64]$q1_0PromotionTelemetryRecordLimitDecimal
    if ($q1_0PromotionRecordCount -gt
            $q1_0PromotionTelemetryRecordLimit) {
        throw "Q1_0 promotion telemetry record flood: count=$q1_0PromotionRecordCount limit=$q1_0PromotionTelemetryRecordLimit"
    }
    if ($q1_0PromotionRecordAttemptCount -ne $iq1PromotionQ1_0StageAttempts -or
        $q1_0PromotionRecordSuccessCount -ne $iq1PromotionQ1_0StageSuccesses -or
        $q1_0PromotionRecordSuccessCount -ne $iq1PromotionQ1_0NextCallGuards -or
        $q1_0PromotionRecordRejectCount -ne $iq1PromotionQ1_0RecordRejects -or
        $q1_0PromotionRecordFailureCount -ne $iq1PromotionQ1_0RecordFailures -or
        $q1_0PromotionRecordAttemptCount -eq 0 -or
        $q1_0PromotionRecordSuccessCount -eq 0 -or
        ([decimal]$q1_0PromotionRecordFailureCount +
         [decimal]$q1_0PromotionRecordRejectCount) -ne
            [decimal]$iq1PromotionFailures) {
        throw "Q1_0 promotion record counts do not match final promotion counters"
    }
    if ($Q1_0PromotionSsdWrap -and
        ($q1_0SsdWrapTelemetry.attempts -ne
             $q1_0PromotionRecordAttemptCount -or
         $q1_0SsdWrapTelemetry.successes -ne
             $q1_0PromotionRecordSuccessCount -or
         $q1_0SsdWrapTelemetry.failures -ne
             $q1_0PromotionRecordFailureCount)) {
        throw "Q1_0 SSD-WRAP counters do not match promotion records"
    }
    $q1_0PromotionRecordArtifactPath = Join-Path $outdir (
        "g7_" + $Tag + "_q1_0_promotion_records.jsonl")
    if (Test-Path -LiteralPath $q1_0PromotionRecordArtifactPath) {
        throw "Q1_0 promotion record artifact already exists: $q1_0PromotionRecordArtifactPath"
    }
    $q1_0PromotionRecordPhysicalLineCount =
        [UInt64]$q1_0PromotionRecords.Count
    @($q1_0PromotionRecords | ForEach-Object {
        $_ | ConvertTo-Json -Compress -Depth 8
    }) | Set-Content -LiteralPath $q1_0PromotionRecordArtifactPath -Encoding UTF8
    $q1_0PromotionRecordArtifactSHA256 =
        (Get-FileHash -LiteralPath $q1_0PromotionRecordArtifactPath -Algorithm SHA256).
            Hash.ToLowerInvariant()
} elseif ($q1_0PromotionRecordMatches.Count -ne 0) {
    throw "Q1_0 promotion per-expert records appeared while dynamic promotion was disabled"
}

$iq1ProfileSsdReadCalls = [UInt64]0
$iq1ProfileSsdReadMs = 0.0
$iq1ProfileH2dBatches = [UInt64]0
$iq1ProfileH2dCopies = [UInt64]0
$iq1ProfileH2dEnqueueMs = 0.0
$iq1ProfileH2dSyncs = [UInt64]0
$iq1ProfileH2dSyncMs = 0.0
$iq1MixedProfileCalls = [UInt64]0
$iq1MixedProfileRouterD2hMs = 0.0
$iq1MixedProfileMetadataH2dMs = 0.0
$iq1MixedProfileMainSubmitMs = 0.0
$iq1MixedProfileMainSyncMs = 0.0
$iq1MixedProfileColdSubmitMs = 0.0
$iq1MixedProfileJoinSubmitMs = 0.0
$iq1TransportProfileMatches = [regex]::Matches(
    $iq1SSidecarLogText,
    '\[iq1-s-profile\] result=summary ssd_read_calls=(\d+) ssd_read_ms=([0-9.]+) h2d_batches=(\d+) h2d_copies=(\d+) h2d_enqueue_ms=([0-9.]+) h2d_syncs=(\d+) h2d_sync_ms=([0-9.]+) h2d_bytes=(\d+)')
$iq1MixedProfileMatches = [regex]::Matches(
    $iq1SSidecarLogText,
    '\[iq1-mixed-profile\] result=summary calls=(\d+) router_d2h_ms=([0-9.]+) metadata_h2d_ms=([0-9.]+) main_submit_ms=([0-9.]+) main_sync_ms=([0-9.]+) cold_submit_ms=([0-9.]+) join_submit_ms=([0-9.]+)')
if ($Iq1SProfile) {
    if ($iq1TransportProfileMatches.Count -ne 1 -or
        $iq1MixedProfileMatches.Count -ne 1) {
        throw "IQ1_S profile requires exactly one transport and mixed summary; observed transport=$($iq1TransportProfileMatches.Count) mixed=$($iq1MixedProfileMatches.Count)"
    }
    $iq1TransportProfile = $iq1TransportProfileMatches[0]
    $iq1ProfileSsdReadCalls = [UInt64]$iq1TransportProfile.Groups[1].Value
    $iq1ProfileSsdReadMs = [double]::Parse($iq1TransportProfile.Groups[2].Value, [Globalization.CultureInfo]::InvariantCulture)
    $iq1ProfileH2dBatches = [UInt64]$iq1TransportProfile.Groups[3].Value
    $iq1ProfileH2dCopies = [UInt64]$iq1TransportProfile.Groups[4].Value
    $iq1ProfileH2dEnqueueMs = [double]::Parse($iq1TransportProfile.Groups[5].Value, [Globalization.CultureInfo]::InvariantCulture)
    $iq1ProfileH2dSyncs = [UInt64]$iq1TransportProfile.Groups[6].Value
    $iq1ProfileH2dSyncMs = [double]::Parse($iq1TransportProfile.Groups[7].Value, [Globalization.CultureInfo]::InvariantCulture)
    $iq1ProfileH2dBytes = [UInt64]$iq1TransportProfile.Groups[8].Value
    $iq1MixedProfile = $iq1MixedProfileMatches[0]
    $iq1MixedProfileCalls = [UInt64]$iq1MixedProfile.Groups[1].Value
    $iq1MixedProfileRouterD2hMs = [double]::Parse($iq1MixedProfile.Groups[2].Value, [Globalization.CultureInfo]::InvariantCulture)
    $iq1MixedProfileMetadataH2dMs = [double]::Parse($iq1MixedProfile.Groups[3].Value, [Globalization.CultureInfo]::InvariantCulture)
    $iq1MixedProfileMainSubmitMs = [double]::Parse($iq1MixedProfile.Groups[4].Value, [Globalization.CultureInfo]::InvariantCulture)
    $iq1MixedProfileMainSyncMs = [double]::Parse($iq1MixedProfile.Groups[5].Value, [Globalization.CultureInfo]::InvariantCulture)
    $iq1MixedProfileColdSubmitMs = [double]::Parse($iq1MixedProfile.Groups[6].Value, [Globalization.CultureInfo]::InvariantCulture)
    $iq1MixedProfileJoinSubmitMs = [double]::Parse($iq1MixedProfile.Groups[7].Value, [Globalization.CultureInfo]::InvariantCulture)
    $iq1ProfileExpectedH2dBatches = if ($Iq1SVramCachePerLayer -gt 0) {
        $iq1SVramCacheMisses
    } else {
        $iq1SSidecarCalls
    }
    if ($iq1ProfileSsdReadCalls -ne $iq1SRamCacheMisses -or
        $iq1ProfileH2dBatches -ne $iq1ProfileExpectedH2dBatches -or
        $iq1ProfileH2dSyncs -ne $iq1ProfileH2dBatches -or
        ($iq1ProfileH2dCopies -ne $iq1ProfileH2dBatches -and
         $iq1ProfileH2dCopies -ne (3 * $iq1ProfileH2dBatches)) -or
        $iq1ProfileH2dBytes -ne $iq1SRamCacheH2dBytes -or
        $iq1MixedProfileCalls -ne $iq1MixedCalls) {
        throw "IQ1_S profile counters are inconsistent with runtime telemetry"
    }
} elseif ($iq1TransportProfileMatches.Count -ne 0 -or
          $iq1MixedProfileMatches.Count -ne 0) {
    throw "IQ1_S profile telemetry appeared while profiling was disabled"
}

$q1_0MixedPrimaryColdAvoided = if ($Q1_0MixedColdOne) {
    [UInt64]$q1_0MixedTelemetry.cold_one_q1_routes
} else {
    [UInt64]0
}
$mixedPrimaryColdAvoided = [UInt64](
    $iq1MixedPrimaryColdAvoided + $q1_0MixedPrimaryColdAvoided)
$gpuRoutesExpectedPrimarySelected = [UInt64](6 * $gpuRoutesCalls)
if ($mixedPrimaryColdAvoided -gt $gpuRoutesExpectedPrimarySelected) {
    throw "Mixed decode excluded more primary routes than the GPU resolver observed"
}
$gpuRoutesExpectedPrimarySelected -= $mixedPrimaryColdAvoided
$splitFusedPrimaryRouteBasis = "gpu-resident-route-population"
$splitFusedExpectedPrimaryRoutes = [UInt64]$gpuRoutesExpectedPrimarySelected
$splitFusedQ1ResidentRoutesExcluded = [UInt64]0
$splitFusedObservedPrimaryRoutes = [UInt64](
    [UInt64]$splitFusedHits + [UInt64]$splitFusedMisses)
$q1_0MixedSplitFusedPrimaryTransport = [bool](
    $q1_0MixedRouteTraceRequired -and
    [bool]$q1_0MixedRouteTraceTelemetry.observed -and
    $Q1_0ResidentArena -and
    $Q1_0DualArena -and -not $Q1_0DualSparseCompanion -and
    [bool]$q1_0MixedTelemetry.observed)
if ($q1_0MixedSplitFusedPrimaryTransport) {
    $splitFusedPrimaryRouteBasis = "q1-0-mixed-iq2-routes"
    $splitFusedExpectedPrimaryRoutes = [UInt64]$q1_0MixedIq2Routes
    $splitFusedQ1ResidentRoutesExcluded =
        [UInt64]$q1_0MixedTelemetry.q1_resident
}
if ($SplitFused) {
    if (-not $gpuRoutesObserved -or $gpuRoutesCalls -le 0 -or
        -not $splitFusedObserved -or $splitFusedCalls -ne $gpuRoutesCalls) {
        throw "SplitFused was requested but fused calls were not observed on every GPU route call"
    }
    if ($splitFusedObservedPrimaryRoutes -ne $splitFusedExpectedPrimaryRoutes) {
        throw "SplitFused route accounting does not match the primary-model route population"
    }
    if ($splitFusedMissScratchBytesAvoided -le 0 -or
        $splitFusedSumReadBytesAvoided -le 0) {
        throw "SplitFused was requested but avoided byte counters were not positive"
    }
}

if (-not $httpOk) { throw "Measurement failed: one or more HTTP requests did not complete" }
if ($serverExitCode -ne 0) {
    throw "Measurement failed: ds4_server exited with code $serverExitCode"
}
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
    $expectedExpertTieringFinalLines = if ($ComposePrefillMassTiering) { $requestCountExpected } else { 1 }
    if ($expertTieringFinalLineCount -ne $expectedExpertTieringFinalLines -or -not $expertTieringFinalObserved) {
        throw "Expert tiering measurement failed: expected $expectedExpertTieringFinalLines final counter lines, observed $expertTieringFinalLineCount"
    }
    if ($ComposePrefillMassTiering) {
        if ($prefillMassWrapParsedEvents.Count -ne $requestCountExpected) {
            throw "Expert tiering compose failed: WRAP event count is unavailable for per-request validation"
        }
        $tierAggregate = @{}
        foreach ($aggregateField in @(
                "snapshot_backing_hits", "snapshot_backing_misses",
                "snapshot_to_vram_bytes", "forbidden_cold_ssd_to_vram",
                "general_backing_reclaims",
                "calls", "selected", "cold", "ram_hits", "vram_hits",
                "cold_to_ram", "cold_to_vram", "ram_to_warm",
                "vram_promotions", "vram_demotions", "ram_evictions",
                "ram_admit_skips", "transient", "failures", "ssd_bytes",
                "ram_h2d_bytes", "policy_epochs", "policy_free_promotions",
                "policy_replacements", "policy_min_frequency_skips",
                "policy_budget_skips", "policy_score_skips")) {
            $tierAggregate[$aggregateField] = [uint64]0
        }
        $tierMassSumAggregate = 0.0
        $tierLfruTopMaximum = 0.0
        for ($tierLineIndex = 0; $tierLineIndex -lt $expertTieringFinalLines.Count; $tierLineIndex++) {
            $tierFields = @{}
            foreach ($fieldMatch in [regex]::Matches($expertTieringFinalLines[$tierLineIndex], " ([a-z0-9_]+)=([^ ]+)")) {
                $tierFields[$fieldMatch.Groups[1].Value] = $fieldMatch.Groups[2].Value
            }
            foreach ($requiredTierField in @(
                    "compose_prefill_mass_tiering", "snapshot_generation",
                    "compose_router_open",
                    "snapshot_backing_entries", "snapshot_backing_hits",
                    "snapshot_backing_misses", "snapshot_to_vram_bytes",
                    "forbidden_cold_ssd_to_vram", "general_backing_reclaims", "cold_to_vram",
                    "failures", "ssd_bytes")) {
                if (-not $tierFields.ContainsKey($requiredTierField)) {
                    throw "Expert tiering compose failed: final line $tierLineIndex missing $requiredTierField"
                }
            }
            $matchingWrap = $prefillMassWrapParsedEvents[$tierLineIndex]
            $matchingPromotion = if ($quantPromotionRequested) { $iq1PromotionRows[$tierLineIndex] } else { $null }
            $expectedSnapshotBackingEntries = [uint32]$matchingWrap.candidate
            if ($quantPromotionRequested -and -not $ComposePrefillMassOpenRouter) {
                if ([UInt64]$matchingPromotion.reserved_slots -gt [UInt64]$matchingWrap.candidate) {
                    throw "Expert tiering compose failed: IQ1 promotion reserved more slots than the candidate snapshot at request $($tierLineIndex + 1)"
                }
                $expectedSnapshotBackingEntries =
                    [uint32]([UInt64]$matchingWrap.candidate - [UInt64]$matchingPromotion.reserved_slots)
            }
            if ([uint32]$tierFields["compose_prefill_mass_tiering"] -ne 1 -or
                [uint32]$tierFields["compose_router_open"] -ne $(if ($ComposePrefillMassOpenRouter) { 1 } else { 0 }) -or
                [uint64]$tierFields["snapshot_generation"] -ne [uint64]$matchingWrap.generation -or
                [uint32]$tierFields["snapshot_backing_entries"] -ne $expectedSnapshotBackingEntries -or
                [uint64]$tierFields["snapshot_backing_hits"] -le 0 -or
                (-not $ComposePrefillMassOpenRouter -and [uint64]$tierFields["snapshot_backing_misses"] -ne 0) -or
                [uint64]$tierFields["snapshot_to_vram_bytes"] -le 0 -or
                [uint64]$tierFields["forbidden_cold_ssd_to_vram"] -ne 0 -or
                [uint64]$tierFields["cold_to_vram"] -ne 0 -or
                [uint64]$tierFields["failures"] -ne 0 -or
                (-not $ComposePrefillMassOpenRouter -and [uint64]$tierFields["ssd_bytes"] -ne 0)) {
                throw "Expert tiering compose failed: per-request final counters are inconsistent at request $($tierLineIndex + 1)"
            }
            foreach ($aggregateField in @($tierAggregate.Keys)) {
                if (-not $tierFields.ContainsKey($aggregateField)) {
                    throw "Expert tiering compose failed: final line $tierLineIndex missing aggregate field $aggregateField"
                }
                $tierAggregate[$aggregateField] =
                    [uint64]$tierAggregate[$aggregateField] +
                    [uint64]$tierFields[$aggregateField]
            }
            if (-not $tierFields.ContainsKey("mass_sum") -or
                -not $tierFields.ContainsKey("lfru_top")) {
                throw "Expert tiering compose failed: final line $tierLineIndex missing score fields"
            }
            $tierMassSumAggregate += [double]::Parse(
                $tierFields["mass_sum"],
                [Globalization.CultureInfo]::InvariantCulture)
            $tierLfruTopMaximum = [math]::Max(
                $tierLfruTopMaximum,
                [double]::Parse(
                    $tierFields["lfru_top"],
                    [Globalization.CultureInfo]::InvariantCulture))
        }
        $expertTieringSnapshotBackingHits = $tierAggregate["snapshot_backing_hits"]
        $expertTieringSnapshotBackingMisses = $tierAggregate["snapshot_backing_misses"]
        $expertTieringSnapshotToVramBytes = $tierAggregate["snapshot_to_vram_bytes"]
        $expertTieringForbiddenColdSsdToVram = $tierAggregate["forbidden_cold_ssd_to_vram"]
        $expertTieringGeneralBackingReclaims = $tierAggregate["general_backing_reclaims"]
        $expertTieringCalls = $tierAggregate["calls"]
        $expertTieringSelected = $tierAggregate["selected"]
        $expertTieringCold = $tierAggregate["cold"]
        $expertTieringRamHits = $tierAggregate["ram_hits"]
        $expertTieringVramHits = $tierAggregate["vram_hits"]
        $expertTieringColdToRam = $tierAggregate["cold_to_ram"]
        $expertTieringColdToVram = $tierAggregate["cold_to_vram"]
        $expertTieringRamToWarm = $tierAggregate["ram_to_warm"]
        $expertTieringVramPromotions = $tierAggregate["vram_promotions"]
        $expertTieringVramDemotions = $tierAggregate["vram_demotions"]
        $expertTieringRamEvictions = $tierAggregate["ram_evictions"]
        $expertTieringRamAdmitSkips = $tierAggregate["ram_admit_skips"]
        $expertTieringTransient = $tierAggregate["transient"]
        $expertTieringFailures = $tierAggregate["failures"]
        $expertTieringSsdBytes = $tierAggregate["ssd_bytes"]
        $expertTieringRamH2DBytes = $tierAggregate["ram_h2d_bytes"]
        $expertTieringPolicyEpochs = $tierAggregate["policy_epochs"]
        $expertTieringPolicyFreePromotions = $tierAggregate["policy_free_promotions"]
        $expertTieringPolicyReplacements = $tierAggregate["policy_replacements"]
        $expertTieringPolicyMinFrequencySkips = $tierAggregate["policy_min_frequency_skips"]
        $expertTieringPolicyBudgetSkips = $tierAggregate["policy_budget_skips"]
        $expertTieringPolicyScoreSkips = $tierAggregate["policy_score_skips"]
        $expertTieringMassSum = $tierMassSumAggregate
        $expertTieringLfruTop = $tierLfruTopMaximum
        if (-not $expertTieringComposeObserved -or $expertTieringComposeFlag -ne 1) { throw "Expert tiering compose failed: final compose flag was not observed" }
        if ($expertTieringComposeRouterOpen -ne $(if ($ComposePrefillMassOpenRouter) { 1 } else { 0 })) { throw "Expert tiering compose failed: compose_router_open flag mismatch" }
        if ($expertTieringSnapshotGeneration -le 0 -or $expertTieringSnapshotBackingEntries -le 0) { throw "Expert tiering compose failed: snapshot backing was empty" }
        if ($expertTieringSnapshotBackingHits -le 0) { throw "Expert tiering compose failed: snapshot backing was not used" }
        if (-not $ComposePrefillMassOpenRouter -and $expertTieringSnapshotBackingMisses -ne 0) { throw "Expert tiering compose failed: decode requested an expert outside the closed snapshot" }
        if ($expertTieringSnapshotToVramBytes -le 0) { throw "Expert tiering compose failed: snapshot backing produced no H2D traffic" }
        if ($expertTieringForbiddenColdSsdToVram -ne 0) { throw "Expert tiering compose failed: cold SSD to VRAM violation observed" }
        if (-not $ComposePrefillMassOpenRouter -and ($expertTieringColdToRam -ne 0 -or $expertTieringSsdBytes -ne 0)) { throw "Expert tiering compose failed: decode touched cold SSD backing" }
        if ($expertTieringColdToVram -ne 0) { throw "Expert tiering compose failed: cold_to_vram must remain zero" }
        if ($expertTieringFailures -ne 0) { throw "Expert tiering compose failed: runtime failures observed" }
        if ($prefillMassWrapGeneration -le 0 -or $expertTieringSnapshotGeneration -ne $prefillMassWrapGeneration) { throw "Expert tiering compose failed: snapshot generation differs from prefill publish" }
        if ($ComposePrefillMassOpenRouter) {
            if ($expertTieringSnapshotBackingEntries -ne $prefillMassWrapResidentAfter -or
                $expertTieringSnapshotBackingEntries -ne $prefillMassWrapCandidate) {
                throw "Expert tiering compose failed: open snapshot backing differs from prefill publication"
            }
        } elseif ($quantPromotionRequested) {
            if ([UInt64]$iq1PromotionReservedSlots -gt
                [UInt64]$prefillMassWrapCandidate) {
                throw "Expert tiering compose failed: aggregate IQ1 promotion slots exceed published candidates"
            }
            $expectedFinalSnapshotBackingEntries =
                [uint32]([UInt64]$prefillMassWrapCandidate -
                    [UInt64]$iq1PromotionReservedSlots)
            if ($expertTieringSnapshotBackingEntries -ne $expectedFinalSnapshotBackingEntries) {
                throw "Expert tiering compose failed: snapshot backing does not account for IQ1 promotion probation slots"
            }
        } elseif ($expertTieringSnapshotBackingEntries -ne $prefillMassWrapResidentAfter -or
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
            $expertTieringMinFrequency -ne $ExpertTierMinFrequency -or
            [math]::Abs($expertTieringHysteresis - $ExpertTierHysteresis) -gt 1.0e-9) {
            throw "Expert tiering measurement failed: mass-lfru policy parameters mismatch"
        }
        if ($ExpertTierAdaptiveBudget) {
            if (-not $expertTieringAdaptiveEnabled -or
                $expertTieringReplacementBudgetBase -ne $ExpertTierReplacementBudget -or
                $expertTieringReplacementBudget -ne $expertTieringAdaptiveCurrent -or
                $expertTieringAdaptiveCurrent -lt $ExpertTierAdaptiveMin -or
                $expertTieringAdaptiveCurrent -gt $ExpertTierAdaptiveMax -or
                $expertTieringAdaptiveMin -ne $ExpertTierAdaptiveMin -or
                $expertTieringAdaptiveMax -ne $ExpertTierAdaptiveMax -or
                $expertTieringAdaptiveStep -ne $ExpertTierAdaptiveStep -or
                $expertTieringAdaptivePressureThreshold -ne $ExpertTierAdaptivePressureThreshold) {
                throw "Expert tiering measurement failed: adaptive observed config differs from requested"
            }
        } elseif ($expertTieringAdaptiveEnabled -or
                  $expertTieringReplacementBudget -ne $ExpertTierReplacementBudget -or
                  $expertTieringReplacementBudgetBase -ne $ExpertTierReplacementBudget) {
            throw "Expert tiering measurement failed: fixed replacement budget mismatch"
        }
    } elseif ($expertTieringClockCalls -ne 0 -or
              $expertTieringReplacementBudget -ne 0 -or
              $expertTieringMinFrequency -ne 2 -or
              [math]::Abs($expertTieringHysteresis - 1.0) -gt 1.0e-9) {
        throw "Expert tiering measurement failed: second-touch effective parameters mismatch"
    }
    if ($expertTieringCalls -le 0 -or $expertTieringSelected -le 0) { throw "Expert tiering measurement failed: no routed calls were observed" }
    if ($expertTieringFailures -ne 0) { throw "Expert tiering measurement failed: runtime failures observed" }
    $expertTieringExpectedSelected = [UInt64](6 * $expertTieringCalls)
    if ($iq1MixedPrimaryColdAvoided -gt $expertTieringExpectedSelected) {
        throw "Expert tiering measurement failed: IQ1_S exclusions exceed routed population"
    }
    # Without promotion, the IQ1 cold lane bypasses primary-model tiering.
    # Promotion observes that lane while staging its exact IQ2 backing, so it
    # is already present in expertTieringSelected and must not be subtracted.
    if (-not $quantPromotionRequested) {
        $expertTieringExpectedSelected -= $iq1MixedPrimaryColdAvoided
    }
    if ($expertTieringSelected -ne $expertTieringExpectedSelected) {
        throw "Expert tiering measurement failed: selected count does not match primary-model routes"
    }
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
            -not $ExpertTierAdaptiveBudget -and
            $expertTieringPolicyReplacements -gt
                ($expertTieringPolicyEpochs * $ExpertTierReplacementBudget)) {
            throw "Expert tiering measurement failed: mass-lfru replacement budget exceeded"
        }
        if ($ExpertTierPolicy -eq "mass-lfru" -and
            $ExpertTierAdaptiveBudget -and
            $expertTieringPolicyReplacements -gt
                ($expertTieringPolicyEpochs * $ExpertTierAdaptiveMax)) {
            throw "Expert tiering measurement failed: adaptive mass-lfru replacement budget exceeded"
        }
    }
    if ($expertTieringStatesVram -gt $ExpertCacheN) {
        throw "Expert tiering measurement failed: VRAM state count exceeds ExpertCacheN"
    }
    if ($ExpertTiering -eq "enforce" -and -not $ComposePrefillMassTiering) {
        if ($expertTieringColdToVram -ne 0 -or
            $expertTieringColdToRam -le 0 -or
            $expertTieringTransient -le 0) {
            throw "Expert tiering measurement failed: enforce transition contract was violated"
        }
        if ($GateKind -ne "structural-safety" -and
            $expertTieringVramPromotions -le 0) {
            throw "Expert tiering measurement failed: no VRAM promotion was observed"
        }
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
    if (-not $prefillMassArmed -or -not $prefillMassFinalized -or
        $prefillMassArmedEventCount -ne $requestCountExpected -or
        $prefillMassFinalizeEventCount -ne $requestCountExpected -or
        (($ComposePrefillMassTiering -or $Q1_0PureResident) -and
         $prefillMassDecodeEventCount -notin @(0, $requestCountExpected)) -or
        (-not $ComposePrefillMassTiering -and -not $Q1_0PureResident -and
         $prefillMassDecodeEventCount -ne $requestCountExpected)) {
        throw "Prefill mass measurement failed: expected $requestCountExpected complete observer lifecycles; armed=$prefillMassArmedEventCount finalized=$prefillMassFinalizeEventCount decode=$prefillMassDecodeEventCount"
    }
    if ($prefillMassCandidate -le 0 -or $prefillMassCandidate -gt $prefillMassCapacity) { throw "Prefill mass measurement failed: invalid candidate size" }
    if ($prefillMassCoverage -le 0.0 -or $prefillMassCoverage -gt 1.0) { throw "Prefill mass measurement failed: invalid mass coverage" }
    if (-not $ComposePrefillMassTiering -and
        ($prefillMassDecodeSlots -le 0 -or $prefillMassDecodeHits -gt $prefillMassDecodeSlots)) {
        throw "Prefill mass measurement failed: invalid decode coverage"
    }
    $expectedPrefillMassPolicy = if ($PrefillMassWrap) { "bulk-wrap" } else { "observe-only" }
    if ($prefillMassPolicy -ne $expectedPrefillMassPolicy) { throw "Prefill mass measurement failed: runtime policy mismatch" }
}
if ($PrefillMassWrap) {
    if ($prefillMassWrapEventCount -ne $requestCountExpected -or
        $prefillMassWrapParsedEvents.Count -ne $requestCountExpected -or
        -not $prefillMassWrapObserved) {
        throw "Prefill mass WRAP failed: expected $requestCountExpected well-formed terminal events, observed $prefillMassWrapEventCount/$($prefillMassWrapParsedEvents.Count)"
    }
    $previousWrap = $null
    for ($wrapIndex = 0; $wrapIndex -lt $prefillMassWrapParsedEvents.Count; $wrapIndex++) {
        $wrapEvent = $prefillMassWrapParsedEvents[$wrapIndex]
        if ($wrapEvent.result -ne "published" -or $wrapEvent.reason -ne "ok" -or
            $wrapEvent.candidate -le 0 -or
            $wrapEvent.loads -gt $wrapEvent.candidate -or
            $wrapEvent.resident_after -ne $wrapEvent.candidate -or
            $wrapEvent.snapshot_after -le $wrapEvent.snapshot_before -or
            $wrapEvent.generation -ne $wrapEvent.snapshot_after -or
            $wrapEvent.preloaded -ne 0 -or $wrapEvent.router -ne "unbiased" -or
            $wrapEvent.mask -ne $(if ($ComposePrefillMassOpenRouter) { "request-scoped-open" } elseif ($ComposePrefillMassTiering) { "request-scoped-closed" } else { "off" })) {
            throw "Prefill mass WRAP failed: malformed publication at request $($wrapIndex + 1)"
        }
        if ($null -eq $previousWrap) {
            if ($wrapEvent.snapshot_before -ne 0 -or
                $wrapEvent.resident_before -ne 0 -or
                $wrapEvent.loads -ne $wrapEvent.candidate) {
                throw "Prefill mass WRAP failed: first-snapshot invariants differ"
            }
        } elseif ($wrapEvent.snapshot_before -ne $previousWrap.snapshot_after -or
                  $wrapEvent.resident_before -ne $previousWrap.resident_after) {
            throw "Prefill mass WRAP failed: snapshot sequence broke at request $($wrapIndex + 1)"
        } elseif ($prefillMassComposeFingerprints[$wrapIndex] -eq
                      $prefillMassComposeFingerprints[$wrapIndex - 1] -and
                  ($wrapEvent.candidate -ne $previousWrap.candidate -or
                   $wrapEvent.loads -ne 0)) {
            throw "Prefill mass WRAP failed: identical candidate was not reused without loads at request $($wrapIndex + 1)"
        }
        $previousWrap = $wrapEvent
    }
    if ($prefillMassWrapResult -ne "published" -or $prefillMassWrapReason -ne "ok") { throw "Prefill mass WRAP failed: publication missing or unsuccessful" }
    if ($prefillMassWrapCandidate -ne $prefillMassCandidate -or
        $prefillMassWrapLoads -gt $prefillMassCandidate -or
        $prefillMassWrapResidentAfter -ne $prefillMassCandidate) {
        throw "Prefill mass WRAP failed: candidate/load/resident counts differ"
    }
    $expectedPrefillMassMask = if ($ComposePrefillMassOpenRouter) { "request-scoped-open" } elseif ($ComposePrefillMassTiering) { "request-scoped-closed" } else { "off" }
    if ($prefillMassWrapPreloaded -ne 0 -or $prefillMassWrapRouter -ne "unbiased" -or $prefillMassWrapMask -ne $expectedPrefillMassMask) {
        throw "Prefill mass WRAP failed: isolation telemetry differs"
    }
    if ($ComposePrefillMassTiering) {
        if ($prefillMassComposeEventCount -ne $requestCountExpected -or
            $prefillMassComposeParsedCount -ne $requestCountExpected -or
            -not $prefillMassComposeObserved) {
            throw "Prefill mass compose failed: expected $requestCountExpected hash seed events, observed $prefillMassComposeEventCount/$prefillMassComposeParsedCount"
        }
        $expectedComposeMaskRestoreCount = if ($ComposePrefillMassOpenRouter) { 0 } else { $requestCountExpected }
        $expectedComposeMaskEventCount = if ($ComposePrefillMassOpenRouter) { $requestCountExpected } else { (2 * $requestCountExpected) }
        $expectedComposeMaskSemantics = if ($ComposePrefillMassOpenRouter) { "request-scoped-open" } else { "request-scoped-closed" }
        if ($prefillMassComposeMaskFailedCount -ne 0 -or
            $prefillMassComposeMaskAppliedCount -ne $requestCountExpected -or
            $prefillMassComposeMaskRestoreCount -ne $expectedComposeMaskRestoreCount -or
            $prefillMassComposeMaskEventCount -ne $expectedComposeMaskEventCount -or
            $prefillMassComposeMaskSemantics -ne $expectedComposeMaskSemantics) {
            throw "Prefill mass compose failed: mask lifecycle mismatch applied=$prefillMassComposeMaskAppliedCount restored=$prefillMassComposeMaskRestoreCount failed=$prefillMassComposeMaskFailedCount events=$prefillMassComposeMaskEventCount"
        }
        if ($prefillMassComposeHashLayers -ne 3 -or $prefillMassComposeHashSeedEntries -ne (3 * 256)) { throw "Prefill mass compose failed: hash-routed layer seed differs" }
        $expectedComposeCapacity = $prefillMassCapacity
        if ($ComposePrefillMassOpenRouter) {
            if ($prefillMassCapacity -lt $ComposePrefillMassReserveSlots) {
                throw "Prefill mass compose failed: reserved slots exceed arena capacity"
            }
            $expectedComposeCapacity =
                $prefillMassCapacity - $ComposePrefillMassReserveSlots
        }
        if ($prefillMassComposeTotalCandidate -ne $prefillMassCandidate -or
            $prefillMassComposeCapacity -ne $expectedComposeCapacity) {
            throw "Prefill mass compose failed: candidate/capacity telemetry differs"
        }
        if ($prefillMassComposeRankedEntries + $prefillMassComposeHashSeedEntries -ne $prefillMassComposeTotalCandidate) { throw "Prefill mass compose failed: ranked/hash candidate accounting differs" }
        if ($prefillMassComposeCandidateFNV1A64 -notmatch '^[0-9a-f]{16}$') { throw "Prefill mass compose failed: candidate fingerprint missing" }
    } elseif ($prefillMassComposeEventCount -ne 0 -or $prefillMassComposeObserved) {
        throw "Prefill mass compose telemetry appeared while not requested"
    }
} elseif ($prefillMassWrapEventCount -ne 0 -or $prefillMassWrapObserved) {
    throw "Prefill mass WRAP activated while not requested"
}
if ($PrefillMassLayerFullEvery -gt 0) {
    if ($prefillMassLayerStripeEventCount -ne 1 -or
        $prefillMassLayerStripeFailedCount -ne 0 -or
        -not $prefillMassLayerStripeObserved -or
        $prefillMassLayerStripeResult -ne "applied") {
        throw "Prefill mass layer stripe failed: expected exactly one applied event and no failures"
    }
    if ($prefillMassLayerStripeStride -ne $PrefillMassLayerFullEvery -or
        $prefillMassLayerStripePhase -ne $PrefillMassLayerFullPhase) {
        throw "Prefill mass layer stripe failed: observed stride/phase differ from request"
    }
    $expectedStripeFullLayers = 0
    for ($relativeLayer = 0; $relativeLayer -lt $prefillMassLayerStripeRoutedLayers; $relativeLayer++) {
        if (($relativeLayer % $PrefillMassLayerFullEvery) -eq $PrefillMassLayerFullPhase) {
            $expectedStripeFullLayers++
        }
    }
    if ($prefillMassLayerStripeRoutedLayers -ne 40 -or
        $prefillMassLayerStripeFullLayers -ne $expectedStripeFullLayers -or
        $prefillMassLayerStripeFullLayers + $prefillMassLayerStripePartialLayers -ne $prefillMassLayerStripeRoutedLayers) {
        throw "Prefill mass layer stripe failed: layer accounting differs"
    }
    if ($prefillMassLayerStripeFullKeep -ne 256 -or
        $prefillMassLayerStripePartialKeepMin -lt 6 -or
        $prefillMassLayerStripePartialKeepMax -lt $prefillMassLayerStripePartialKeepMin -or
        ($prefillMassLayerStripePartialKeepMax - $prefillMassLayerStripePartialKeepMin) -gt 1) {
        throw "Prefill mass layer stripe failed: full/partial quotas differ"
    }
    if ($prefillMassLayerStripeRoutedCandidate -ne $prefillMassComposeRankedEntries -or
        $prefillMassLayerStripeRoutedCandidate + $prefillMassComposeHashSeedEntries -ne $prefillMassLayerStripeTotalCandidate -or
        $prefillMassLayerStripeTotalCandidate -ne $prefillMassCandidate -or
        $prefillMassLayerStripeCapacity -ne $prefillMassCapacity -or
        $prefillMassLayerStripeSemantics -ne "budget-preserving") {
        throw "Prefill mass layer stripe failed: capacity/accounting telemetry differs"
    }
} elseif ($prefillMassLayerStripeEventCount -ne 0 -or $prefillMassLayerStripeObserved) {
    throw "Prefill mass layer stripe activated while not requested"
}
$embeddedBakeMaskObserved = $reapMaskAppliedObserved -and
    $reapMaskPathObserved -like "embedded-bake:*"
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
} elseif ($AllowEmbeddedBakeMask) {
    $expectedEmbeddedBakePath = "embedded-bake:" +
        $ExpectedEmbeddedBakeMaskSHA256.ToLowerInvariant()
    if ($reapMaskReloadObserved -or -not $embeddedBakeMaskObserved -or
        $reapMaskPathObserved -ne $expectedEmbeddedBakePath) {
        throw "Embedded bake mask measurement failed: provenance mismatch"
    }
    if ($reapMaskAppliedPruned -le 0 -or $reapMaskAppliedLayers -le 0 -or
        $reapMaskBiasLayers -le 0) {
        throw "Embedded bake mask measurement failed: invalid counters"
    }
    if ($reapMaskRangesFailed -ne 0 -or
        ($reapMaskRangesUpdated + $reapMaskRangesCreated) -ne
            $reapMaskBiasLayers) {
        throw "Embedded bake mask measurement failed: range upload incomplete"
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
if ($DynamicArenaGiB -gt 0.0) {
    if (-not $arenaCapObserved) { throw "Dynamic arena cap telemetry was not observed" }
    if ($arenaCapSsdWrap -ne [bool]$Q1_0PromotionSsdWrap) {
        throw "Dynamic arena SSD-WRAP mode differs from the request"
    }
    if ([math]::Abs($arenaCapMinAvailableGiB - $DynamicArenaMinAvailableGiB) -gt 0.0015) {
        throw "Dynamic arena cap measurement failed: observed min-available differs from requested value"
    }
    if ($Q1_0PromotionSsdWrap) {
        if ($arenaCapRingSlots -ne 4 -or $arenaReadyRingSlots -ne 4 -or
            $arenaCapHostBudgetBytes -gt $arenaCapRequestedBytes -or
            [decimal]$arenaCapChosenBytes +
                [decimal]$arenaCapPageableBytes -ne
                [decimal]$arenaCapHostBudgetBytes -or
            $arenaAllocatedTotalBytes -ne $arenaCapHostBudgetBytes) {
            throw "Dynamic arena SSD-WRAP fixed-budget accounting failed"
        }
        if (-not $arenaCapCapped -and
            $arenaCapHostBudgetBytes -ne $arenaCapRequestedBytes) {
            throw "Dynamic arena SSD-WRAP changed the uncapped host budget"
        }
    } else {
        if ($arenaCapChosenBytes -gt $arenaCapRequestedBytes -or
            $arenaCapChosenSlots -gt $arenaCapRequestedSlots) {
            throw "Dynamic arena cap measurement failed: chosen arena exceeds requested arena"
        }
        if (-not $arenaCapCapped -and
            ($arenaCapChosenBytes -ne $arenaCapRequestedBytes -or
             $arenaCapChosenSlots -ne $arenaCapRequestedSlots)) {
            throw "Dynamic arena cap measurement failed: uncapped telemetry changed the requested arena"
        }
    }
    if ($arenaCapChosenSlots -lt 1) {
        if ($arenaCapResult -ne "disabled" -or $arenaAllocatedBytes -ne 0 -or
            $arenaAllocatedSlots -ne 0) {
            throw "Dynamic arena cap measurement failed: zero-slot arena was not disabled"
        }
    } else {
        if ($arenaCapResult -ne "ready" -or
            $arenaAllocatedBytes -ne $arenaCapChosenBytes -or
            $arenaAllocatedPinnedSlots -ne $arenaCapChosenSlots -or
            $arenaAllocatedPageableBytes -ne $arenaCapPageableBytes -or
            $arenaAllocatedPageableSlots -ne $arenaCapPageableSlots -or
            $arenaAllocatedSlots -ne $arenaCapTotalSlots) {
            throw "Dynamic arena cap measurement failed: ready allocation differs from chosen cap"
        }
    }
    $arenaCapacityBytesForGate = if ($Q1_0PromotionSsdWrap) {
        $arenaCapHostBudgetBytes
    } else {
        $arenaCapChosenBytes
    }
    if ($DynamicArenaMinAvailableGiB -gt 0.0 -and
        $arenaCapAvailableBeforeGiB -ge 0.0 -and
        $arenaCapacityBytesForGate -gt 0) {
        $arenaCapChosenGiB = [double]$arenaCapacityBytesForGate / 1GB
        if (($arenaCapAvailableBeforeGiB - $arenaCapChosenGiB + 0.000001) -lt
            $DynamicArenaMinAvailableGiB) {
            throw "Dynamic arena cap measurement failed: chosen arena violates min-available request"
        }
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
if ($ArenaWrapSourceParts) {
    if (-not $arenaWrapProfileObserved) {
        throw "Arena WRAP source-parts measurement failed: profile telemetry was not observed"
    }
    if ($arenaWrapProfileResult -ne "published" -or
        $arenaWrapScheduleObserved -ne "source-parts") {
        throw "Arena WRAP source-parts measurement failed: observed result/schedule differs"
    }
    $expectedArenaWrapSource = if ($ArenaWrapSequentialFile) {
        "sequential-file"
    } elseif ($ArenaWrapRandomFile) {
        "random-file"
    } else {
        "mmap"
    }
    if ($arenaWrapSourceObserved -ne $expectedArenaWrapSource) {
        throw "Arena WRAP source-parts measurement failed: observed source differs"
    }
    if ($ArenaWrapSequentialFile -and
        $arenaWrapCopyWorkers -ne $ArenaWrapSequentialWorkers) {
        throw "Arena WRAP sequential-file measurement failed: observed worker count differs"
    }
    if ($ArenaWrapRandomFile -and $arenaWrapCopyWorkers -ne 1) {
        throw "Arena WRAP random-file measurement failed: observed worker count differs"
    }
    if ($ArenaWrapTrustWorkerChecksum -and
        $arenaWrapChecksumObserved -ne "fnv1a64-worker-only") {
        throw "Arena WRAP source-parts measurement failed: observed checksum mode differs"
    }
    if (-not $ArenaWrapTrustWorkerChecksum -and
        $arenaWrapChecksumObserved -ne "fnv1a64-worker-plus-finish") {
        throw "Arena WRAP source-parts measurement failed: observed verified checksum mode differs"
    }
    if ($arenaWrapProfileLoads -le 0 -or
        $arenaWrapPartCount -ne (3 * $arenaWrapProfileLoads) -or
        $arenaWrapCopyWorkers -le 0) {
        throw "Arena WRAP source-parts measurement failed: part/worker accounting differs"
    }
    if ($ArenaWrapTrustWorkerChecksum -and $arenaWrapChecksumWorkers -ne 0) {
        throw "Arena WRAP source-parts measurement failed: unexpected cold checksum pass observed"
    }
    if ($ArenaWrapFileQD -gt 1 -and
        ($arenaWrapFileQDRequestedObserved -ne $ArenaWrapFileQD -or
         $arenaWrapFileQDObserved -ne $ArenaWrapFileQD -or
         $arenaWrapFileSubmits -ne $arenaWrapPartCount -or
         $arenaWrapFileCompletions -ne $arenaWrapPartCount -or
         $arenaWrapFileFailures -ne 0)) {
        throw "Arena WRAP file QD measurement failed: observed queue depth or file counters differ"
    }
}
if ($ArenaWrapPartProfile) {
    if (-not $arenaWrapPartProfileObserved -or
        $arenaWrapPartProfileResult -ne "copy-complete") {
        throw "Arena WRAP part profile measurement failed: telemetry was not observed"
    }
    $expectedPartProfilePhases = if ($ArenaWrapTrustWorkerChecksum) { 3 } else { 1 }
    if ($arenaWrapPartProfilePhases -ne $expectedPartProfilePhases -or
        $arenaWrapPartProfileWorkers -ne $arenaWrapCopyWorkers -or
        $arenaWrapPartProfileParts -ne $arenaWrapPartCount -or
        $arenaWrapPartProfileBytes -le 0 -or
        $arenaWrapPartProfileMaxPartBytes -le 0 -or
        $arenaWrapPartProfileWorkerActiveMaxSeconds -le 0) {
        throw "Arena WRAP part profile measurement failed: worker/part accounting differs"
    }
    if ([math]::Abs($arenaWrapPartProfileSlowThresholdMs - $ArenaWrapSlowPartMs) -gt 0.001) {
        throw "Arena WRAP part profile measurement failed: slow-part threshold differs"
    }
}
if ($ArenaWrapLayoutProfile) {
    if (-not $arenaWrapLayoutProfileObserved -or
        $arenaWrapLayoutProfileRows.Count -ne 3) {
        throw "Arena WRAP layout profile measurement failed: expected exactly three phase lines"
    }
    $requiredLayoutPhases = @("gate", "up", "down")
    foreach ($phase in $requiredLayoutPhases) {
        $phaseRows = @($arenaWrapLayoutProfileRows |
            Where-Object { $_.phase -eq $phase })
        if ($phaseRows.Count -ne 1) {
            throw "Arena WRAP layout profile measurement failed: phase count differs for $phase"
        }
    }
    $arenaWrapLayoutProfilePartsSum = [uint64]0
    foreach ($layoutRow in $arenaWrapLayoutProfileRows) {
        $arenaWrapLayoutProfilePartsSum += [uint64]$layoutRow.parts
        if ($layoutRow.result -ne "ok" -or
            [uint64]$layoutRow.parts -eq 0 -or
            [uint64]$layoutRow.overlaps -ne 0 -or
            [uint64]$layoutRow.gaps -ne ([uint64]$layoutRow.parts - 1) -or
            ([uint64]$layoutRow.gap_eq0 +
             [uint64]$layoutRow.gap_1_4k +
             [uint64]$layoutRow.gap_4k_64k +
             [uint64]$layoutRow.gap_64k_1m +
             [uint64]$layoutRow.gap_gt1m) -ne [uint64]$layoutRow.gaps -or
            [uint64]$layoutRow.t0_reads -gt [uint64]$layoutRow.parts -or
            [uint64]$layoutRow.t0_reads -lt [uint64]$layoutRow.t4096_reads -or
            [uint64]$layoutRow.t4096_reads -lt [uint64]$layoutRow.t65536_reads -or
            [uint64]$layoutRow.t65536_reads -lt [uint64]$layoutRow.t1048576_reads -or
            [uint64]$layoutRow.t1048576_reads -eq 0 -or
            [uint64]$layoutRow.t4096_reads -gt [uint64]$layoutRow.parts -or
            [uint64]$layoutRow.t65536_reads -gt [uint64]$layoutRow.parts -or
            [uint64]$layoutRow.t1048576_reads -gt [uint64]$layoutRow.parts -or
            [uint64]$layoutRow.t0_bytes -ne [uint64]$layoutRow.payload -or
            [uint64]$layoutRow.t0_bytes -gt [uint64]$layoutRow.t4096_bytes -or
            [uint64]$layoutRow.t4096_bytes -gt [uint64]$layoutRow.t65536_bytes -or
            [uint64]$layoutRow.t65536_bytes -gt [uint64]$layoutRow.t1048576_bytes -or
            [uint64]$layoutRow.t4096_bytes -lt [uint64]$layoutRow.payload -or
            [uint64]$layoutRow.t65536_bytes -lt [uint64]$layoutRow.payload -or
            [uint64]$layoutRow.t1048576_bytes -lt [uint64]$layoutRow.payload -or
            [uint64]$layoutRow.source_aligned -gt [uint64]$layoutRow.parts -or
            [uint64]$layoutRow.bytes_aligned -gt [uint64]$layoutRow.parts -or
            [uint64]$layoutRow.destination_aligned -gt [uint64]$layoutRow.parts -or
            [uint32]$layoutRow.page_size -eq 0) {
            throw "Arena WRAP layout profile measurement failed: numeric accounting differs"
        }
    }
    if ($arenaWrapLayoutProfilePartsSum -ne [uint64]$arenaWrapPartCount) {
        throw "Arena WRAP layout profile measurement failed: phase parts do not sum to arena_wrap_part_count"
    }
} elseif ($arenaWrapLayoutProfileObserved) {
    throw "Arena WRAP layout profile measurement failed: unexpected layout telemetry while disabled"
}
if ($ArenaWrapTrimBetweenPhases) {
    if (-not $arenaWrapTrimObserved -or
        $arenaWrapTrimResult -ne "complete" -or
        $arenaWrapTrimCalls -ne 2 -or
        $arenaWrapTrimSucceeded -ne 2 -or
        $arenaWrapTrimFailed -ne 0 -or
        $arenaWrapTrimLastError -ne 0) {
        throw "Arena WRAP trim measurement failed: telemetry/contract differs"
    }
} elseif ($arenaWrapTrimObserved) {
    throw "Arena WRAP trim measurement failed: unexpected trim telemetry while disabled"
}
if ($ArenaWrapUnlockSourceRanges) {
    $arenaWrapUnlockWaveMode = ($ArenaWrapUnlockWaveGiB -gt 0.0)
    $expectedUnlockPhases = if ($arenaWrapUnlockWaveMode) { 3 } else { 2 }
    if (-not $arenaWrapUnlockObserved -or
        -not $arenaWrapUnlockSummaryObserved -or
        $arenaWrapUnlockSummaryResult -ne "complete" -or
        $arenaWrapUnlockSummaryPhases -ne $expectedUnlockPhases -or
        $arenaWrapUnlockRows.Count -ne $expectedUnlockPhases -or
        $arenaWrapUnlockSummaryFailed -ne 0) {
        throw "Arena WRAP source unlock measurement failed: telemetry/contract differs"
    }
    if ($arenaWrapUnlockWaveMode) {
        $arenaWrapUnlockWaveTargetBytes =
            [uint64][math]::Floor($arenaWrapUnlockSummaryWaveGiB * 1GB)
        if ($arenaWrapUnlockSummaryWaves -lt 3 -or
            [math]::Abs($arenaWrapUnlockSummaryWaveGiB - $ArenaWrapUnlockWaveGiB) -gt 0.000001 -or
            [uint64]$arenaWrapUnlockSummaryMaxWaveBytes -eq 0 -or
            [uint64]$arenaWrapUnlockSummaryMaxWaveBytes -gt $arenaWrapUnlockWaveTargetBytes) {
            throw "Arena WRAP source unlock wave measurement failed: observed wave request differs"
        }
    } elseif ($arenaWrapUnlockSummaryWaves -ne 0 -or
              [math]::Abs($arenaWrapUnlockSummaryWaveGiB) -gt 0.000001 -or
              [uint64]$arenaWrapUnlockSummaryMaxWaveBytes -ne 0) {
        throw "Arena WRAP source unlock measurement failed: unexpected wave telemetry in mode 0"
    }
    $requiredUnlockPhases = if ($arenaWrapUnlockWaveMode) {
        @("gate", "up", "down")
    } else {
        @("gate", "up")
    }
    foreach ($requiredUnlockPhase in $requiredUnlockPhases) {
        $phaseRows = @($arenaWrapUnlockRows |
            Where-Object { $_.phase -eq $requiredUnlockPhase })
        if ($phaseRows.Count -ne 1) {
            throw "Arena WRAP source unlock measurement failed: phase count differs for $requiredUnlockPhase"
        }
        $phaseRow = $phaseRows[0]
        if ($phaseRow.result -ne "ok" -or
            ($arenaWrapUnlockWaveMode -and [uint32]$phaseRow.waves -le 0) -or
            ($arenaWrapUnlockWaveMode -and [uint64]$phaseRow.max_wave_bytes -le 0) -or
            ($arenaWrapUnlockWaveMode -and [uint64]$phaseRow.max_wave_bytes -gt $arenaWrapUnlockWaveTargetBytes) -or
            ((-not $arenaWrapUnlockWaveMode) -and [uint32]$phaseRow.waves -ne 0) -or
            ((-not $arenaWrapUnlockWaveMode) -and [uint64]$phaseRow.max_wave_bytes -ne 0) -or
            [uint64]$phaseRow.parts -le 0 -or
            [uint64]$phaseRow.ranges -le 0 -or
            [uint64]$phaseRow.bytes_requested -le 0 -or
            [uint32]$phaseRow.calls -ne [uint32]$phaseRow.ranges -or
            ([uint32]$phaseRow.true_count + [uint32]$phaseRow.error_not_locked) -ne [uint32]$phaseRow.calls -or
            [uint32]$phaseRow.failed -ne 0 -or
            [uint32]$phaseRow.last_error -ne 0) {
            throw "Arena WRAP source unlock measurement failed: phase accounting differs"
        }
    }
    $arenaWrapUnlockRowsParts = [uint64]0
    $arenaWrapUnlockRowsRanges = [uint64]0
    $arenaWrapUnlockRowsBytes = [uint64]0
    $arenaWrapUnlockRowsCalls = [uint32]0
    $arenaWrapUnlockRowsTrue = [uint32]0
    $arenaWrapUnlockRowsErrorNotLocked = [uint32]0
    $arenaWrapUnlockRowsFailed = [uint32]0
    $arenaWrapUnlockRowsWaves = [uint32]0
    $arenaWrapUnlockRowsMaxWaveBytes = [uint64]0
    foreach ($unlockRow in $arenaWrapUnlockRows) {
        $arenaWrapUnlockRowsWaves += [uint32]$unlockRow.waves
        if ([uint64]$unlockRow.max_wave_bytes -gt $arenaWrapUnlockRowsMaxWaveBytes) {
            $arenaWrapUnlockRowsMaxWaveBytes = [uint64]$unlockRow.max_wave_bytes
        }
        $arenaWrapUnlockRowsParts += [uint64]$unlockRow.parts
        $arenaWrapUnlockRowsRanges += [uint64]$unlockRow.ranges
        $arenaWrapUnlockRowsBytes += [uint64]$unlockRow.bytes_requested
        $arenaWrapUnlockRowsCalls += [uint32]$unlockRow.calls
        $arenaWrapUnlockRowsTrue += [uint32]$unlockRow.true_count
        $arenaWrapUnlockRowsErrorNotLocked += [uint32]$unlockRow.error_not_locked
        $arenaWrapUnlockRowsFailed += [uint32]$unlockRow.failed
    }
    if ($arenaWrapUnlockSummaryWaves -ne $arenaWrapUnlockRowsWaves -or
        $arenaWrapUnlockSummaryMaxWaveBytes -ne $arenaWrapUnlockRowsMaxWaveBytes -or
        $arenaWrapUnlockSummaryParts -ne $arenaWrapUnlockRowsParts -or
        $arenaWrapUnlockSummaryRanges -ne $arenaWrapUnlockRowsRanges -or
        $arenaWrapUnlockSummaryBytesRequested -ne $arenaWrapUnlockRowsBytes -or
        $arenaWrapUnlockSummaryCalls -ne $arenaWrapUnlockRowsCalls -or
        $arenaWrapUnlockSummaryTrue -ne $arenaWrapUnlockRowsTrue -or
        $arenaWrapUnlockSummaryErrorNotLocked -ne $arenaWrapUnlockRowsErrorNotLocked -or
        $arenaWrapUnlockSummaryFailed -ne $arenaWrapUnlockRowsFailed) {
        throw "Arena WRAP source unlock measurement failed: summary does not match phase rows"
    }
} elseif ($arenaWrapUnlockObserved -or $arenaWrapUnlockSummaryObserved) {
    throw "Arena WRAP source unlock measurement failed: unexpected source unlock telemetry while disabled"
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
    compose_prefill_mass_open_router_requested = [bool]$ComposePrefillMassOpenRouter
    compose_prefill_mass_reserve_slots_requested = $ComposePrefillMassReserveSlots
    prefill_vram_seed_requested_per_layer = $PrefillVramSeedPerLayer
    prefill_vram_seed_requested_total = $PrefillVramSeedTotal
    prefill_vram_seed_floor_per_layer_requested = $PrefillVramSeedFloorPerLayer
    prefill_vram_seed_global_observed = $prefillVramSeedGlobalObserved
    prefill_vram_seed_global_requested_observed = $prefillVramSeedGlobalRequestedObserved
    prefill_vram_seed_global_floor_observed = $prefillVramSeedGlobalFloorObserved
    prefill_vram_seed_observed = $prefillVramSeedObserved
    prefill_vram_seed_line_count = $prefillVramSeedLineCount
    prefill_vram_seed_result = $prefillVramSeedResult
    prefill_vram_seed_reason = $prefillVramSeedReason
    prefill_vram_seed_requested_per_layer_observed = $prefillVramSeedRequestedObserved
    prefill_vram_seed_layers = $prefillVramSeedLayers
    prefill_vram_seed_entries = $prefillVramSeedEntries
    prefill_vram_seed_bytes = $prefillVramSeedBytes
    prefill_vram_seed_seconds = $prefillVramSeedSeconds
    prefill_vram_seed_failures = $prefillVramSeedFailures
    prefill_vram_seed_prior_mass = $prefillVramSeedPriorMass
    prefill_vram_seed_semantics = $prefillVramSeedSemantics
    iq1_promotion_requested = [bool]$quantPromotionRequested
    iq1_promotion_kind = $(if ($Q1_0DynamicPromotion) { "q1_0" } elseif ($Iq1Promotion) { "iq1_s" } else { "off" })
    iq1_promotion_probation_slots_requested = $promotionProbationSlotsExpected
    iq1_promotion_min_touches_requested = $promotionMinTouchesExpected
    iq1_promotion_min_weight_requested = $promotionMinWeightExpected
    iq1_promotion_min_mass_requested = $promotionMinMassExpected
    iq1_promotion_request_budget_requested = $promotionRequestBudgetExpected
    iq1_promotion_window_calls_requested = $promotionWindowCallsExpected
    iq1_promotion_window_budget_requested = $promotionWindowBudgetExpected
    iq1_promotion_runtime_observed = $iq1PromotionRuntimeObserved
    iq1_promotion_line_count = $iq1PromotionLineCount
    iq1_promotion_reserved_slots = $iq1PromotionReservedSlots
    iq1_promotion_snapshot_evictions = $iq1PromotionSnapshotEvictions
    iq1_promotion_reserve_strategies = $iq1PromotionReserveStrategies
    iq1_promotion_min_touches = $iq1PromotionObservedMinTouches
    iq1_promotion_min_weight = $iq1PromotionObservedMinWeight
    iq1_promotion_min_mass = $iq1PromotionObservedMinMass
    iq1_promotion_request_budget = $iq1PromotionObservedRequestBudget
    iq1_promotion_window_calls = $iq1PromotionObservedWindowCalls
    iq1_promotion_window_budget = $iq1PromotionObservedWindowBudget
    iq1_promotion_cold_gate_candidates = $iq1PromotionColdGateCandidates
    iq1_promotion_weight_ge_001 = $iq1PromotionWeightGe001
    iq1_promotion_weight_ge_002 = $iq1PromotionWeightGe002
    iq1_promotion_weight_ge_005 = $iq1PromotionWeightGe005
    iq1_promotion_weight_ge_010 = $iq1PromotionWeightGe010
    iq1_promotion_skips_touches = $iq1PromotionSkipsTouches
    iq1_promotion_skips_weight = $iq1PromotionSkipsWeight
    iq1_promotion_skips_mass = $iq1PromotionSkipsMass
    iq1_promotion_skips_request_budget = $iq1PromotionSkipsRequestBudget
    iq1_promotion_skips_window_budget = $iq1PromotionSkipsWindowBudget
    iq1_promotion_2bit_ssd_bytes = $iq1Promotion2BitSsdBytes
    iq1_promotion_2bit_ssd_seconds = $iq1Promotion2BitSsdSeconds
    iq1_promotion_2bit_ssd_bytes_per_second = $iq1Promotion2BitSsdBytesPerSecond
    compose_prefill_mass_tiering_observed = $expertTieringComposeObserved
    compose_prefill_mass_tiering_flag = $expertTieringComposeFlag
    compose_router_open = $expertTieringComposeRouterOpen
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
    replacement_budget_base = $expertTieringReplacementBudgetBase
    adaptive_requested = [bool]$ExpertTierAdaptiveBudget
    adaptive_enabled = $expertTieringAdaptiveEnabled
    adaptive_current = $expertTieringAdaptiveCurrent
    adaptive_min_requested = $ExpertTierAdaptiveMin
    adaptive_min = $expertTieringAdaptiveMin
    adaptive_max_requested = $ExpertTierAdaptiveMax
    adaptive_max = $expertTieringAdaptiveMax
    adaptive_step_requested = $ExpertTierAdaptiveStep
    adaptive_step = $expertTieringAdaptiveStep
    adaptive_pressure_threshold_requested = $ExpertTierAdaptivePressureThreshold
    adaptive_pressure_threshold = $expertTieringAdaptivePressureThreshold
    adaptive_ups = $expertTieringAdaptiveUps
    adaptive_downs = $expertTieringAdaptiveDowns
    adaptive_pressure_epochs = $expertTieringAdaptivePressureEpochs
    adaptive_quiet_epochs = $expertTieringAdaptiveQuietEpochs
    adaptive_last_skip_delta = $expertTieringAdaptiveLastSkipDelta
    adaptive_last_replacement_delta = $expertTieringAdaptiveLastReplacementDelta
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
    general_backing_reclaims = $expertTieringGeneralBackingReclaims
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
$outerQualitySuiteMember = [bool](
    $GateKind -eq "quality" -and
    $AllowQualityVerifiedSuiteReceipt -and
    $OuterQualityProcessCount -ge 3 -and
    $Repeats -eq 1)
$qualityEligible = [bool](
    $GateKind -ne "structural-safety" -and
    $Repeats -ge 3 -and
    -not $outerQualitySuiteMember -and
    -not $ExpertRecoveryTrace)
$sotaEligible = [bool]($qualityEligible -and -not $SkipSystemQuiescencePreflight)
$contaminationReason = ""
if ($ExpertRecoveryTrace) {
    $contaminationReason = "expert-recovery-trace-diagnostic-only"
} elseif (-not $qualityEligible) {
    if ($GateKind -eq "structural-safety") {
        $contaminationReason = "structural-safety-gate-not-quality-eligible"
    } elseif ($outerQualitySuiteMember) {
        $contaminationReason = "outer-quality-suite-member-pending-aggregate"
    } elseif ($Repeats -lt 3) {
        $contaminationReason = "repeats-less-than-3-not-quality-eligible"
    } else {
        $contaminationReason = "not-quality-eligible"
    }
} elseif (-not $sotaEligible) {
    $contaminationReason = "system-quiescence-preflight-skipped-not-sota-eligible"
}
$rawOutputs = [pscustomobject]@{
    schema = "g7_raw_outputs_v1"
    tag = $Tag
    gate_kind = $GateKind
    force_open_router_requested = [bool]$ForceOpenRouter
    quality_eligible = $qualityEligible
    sota_eligible = $sotaEligible
    contamination_reason = $contaminationReason
    allow_quality_verified_suite_receipt_requested =
        [bool]$AllowQualityVerifiedSuiteReceipt
    outer_quality_process_count_requested = $OuterQualityProcessCount
    outer_quality_suite_member = $outerQualitySuiteMember
    outer_quality_member_contract_valid = $outerQualitySuiteMember
    outer_quality_aggregate_required = $outerQualitySuiteMember
    head = $headAtStart
    executable_sha256 = $exeHashAtStart
    ds4_cuda_sha256 = $sourceHashAtStart
    model_path = $modelInfoAtStart.FullName
    model_size_bytes = [UInt64]$modelInfoAtStart.Length
    model_expected_sha256 = $ExpectedModelSHA256.ToLowerInvariant()
    model_sha256 = $modelHashAtStart
    model_hash_method = $modelHashMethod
    model_receipt_path = $modelReceiptPath
    model_receipt_sha256 = $modelReceiptHashAtStart
    model_iq1_suite_receipt_path = $modelIq1SuiteReceiptPathAtStart
    model_iq1_suite_receipt_sha256 = $modelIq1SuiteReceiptHashAtStart
    model_iq1_suite_receipt_schema = $modelIq1SuiteReceiptSchemaAtStart
    model_iq1_suite_full_hash_verified = $modelIq1SuiteFullHashVerified
    model_iq1_suite_lock_proof_required =
        $modelIq1SuiteLockProofRequired
    model_iq1_suite_lock_proof_observed =
        $modelIq1SuiteLockProofObserved
    model_iq1_suite_lock_proof = $modelIq1SuiteLockProof
    benchmark_verified_receipt_reuse_allowed =
        [bool]$AllowBenchmarkVerifiedReceiptReuse
    benchmark_verified_receipt_lock_proof_required =
        $benchmarkVerifiedReceiptLockProofRequired
    benchmark_verified_receipt_lock_proof_observed =
        $benchmarkVerifiedReceiptLockProofObserved
    benchmark_verified_receipt_lock_proof =
        $benchmarkVerifiedReceiptLockProof
    prompt_sha256 = $promptHash
    system_prompt = $SystemPrompt
    system_prompt_sha256 = $systemPromptHash
    warmup_prompt_sha256 = $(if ($Warmup) { $warmupPromptHash } else { "" })
    expected_content_sha256 = if ($ExpectedContentSHA256) { $ExpectedContentSHA256.ToLowerInvariant() } else { "" }
    expected_warmup_content_sha256 = if ($ExpectedWarmupContentSHA256) { $ExpectedWarmupContentSHA256.ToLowerInvariant() } else { "" }
    nested_residual_enabled = [bool]$NestedResidualSidecar
    nested_residual_sidecar_path = $(if ($nestedResidualInfoAtStart) { $nestedResidualInfoAtStart.FullName } else { "" })
    nested_residual_sidecar_bytes = $(if ($nestedResidualInfoAtStart) { [UInt64]$nestedResidualInfoAtStart.Length } else { [UInt64]0 })
    nested_residual_sidecar_sha256 = $nestedResidualHashAtStart
    nested_residual_expected_source_sha256 = $(if ($ExpectedNestedResidualSourceSHA256) { $ExpectedNestedResidualSourceSHA256.ToLowerInvariant() } else { "" })
    nested_residual_expected_payload_sha256 = $(if ($ExpectedNestedResidualPayloadSHA256) { $ExpectedNestedResidualPayloadSHA256.ToLowerInvariant() } else { "" })
    nested_residual_verify_reconstruction = [bool]$NestedResidualVerifyReconstruction
    nested_residual_cache_experts_requested = $NestedResidualCacheExperts
    nested_residual_pageable_base_requested = [bool]$NestedResidualPageableBase
    nested_residual_base_pinned_gib_requested = $NestedResidualBasePinnedGiB
    nested_residual_cache_pageable_requested = [bool]$NestedResidualCachePageable
    nested_residual_expected_base_host_gib =
        $nestedResidualExpectedBaseHostGiB
    nested_residual_expected_residual_cache_host_gib =
        $nestedResidualExpectedResidualCacheHostGiB
    nested_residual_expected_host_allocation_gib =
        $nestedResidualExpectedHostAllocationGiB
    nested_residual_all_layer_first_layer = $nestedResidualAllLayerFirstLayer
    nested_residual_all_layer_last_layer = $nestedResidualAllLayerLastLayer
    nested_residual_all_layer_count = $nestedResidualAllLayerCount
    nested_residual_structural_n1_requested = [bool]$NestedResidualStructuralN1
    nested_residual_gpu_cache_requested = [bool]$NestedResidualGpuCache
    nested_residual_gpu_join_requested = [bool]$NestedResidualGpuJoin
    nested_residual_gpu_join_safety_receipt_path =
        $nestedResidualGpuJoinSafetyReceiptPathAtStart
    nested_residual_gpu_join_safety_receipt_sha256 =
        $nestedResidualGpuJoinSafetyReceiptHashAtStart
    nested_residual_gpu_join_safety_result_path =
        $nestedResidualGpuJoinSafetyResultPathAtStart
    nested_residual_gpu_join_safety_result_sha256 =
        $nestedResidualGpuJoinSafetyResultHashAtStart
    nested_residual_gpu_join_safety_receipt_validated =
        $nestedResidualGpuJoinSafetyReceiptValidated
    allow_nested_residual_benchmark_suite_requested =
        [bool]$AllowNestedResidualBenchmarkSuite
    outer_nested_residual_benchmark_process_count_requested =
        $OuterNestedResidualBenchmarkProcessCount
    nested_residual_benchmark_member = $nestedResidualBenchmarkMember
    nested_residual_runtime_observed = $nestedResidualRuntimeObserved
    nested_residual_router_calls = $nestedResidualRouterCalls
    nested_residual_cache_hits = $nestedResidualCacheHits
    nested_residual_cache_misses = $nestedResidualCacheMisses
    nested_residual_preads = $nestedResidualPreads
    nested_residual_bytes = $nestedResidualBytes
    nested_residual_reconstructed = $nestedResidualReconstructed
    nested_residual_mismatches = $nestedResidualMismatches
    nested_residual_h2d_bytes = $nestedResidualH2DBytes
    nested_residual_failures = $nestedResidualFailures
    nested_residual_vram_runtime_observed = $nestedResidualVramRuntimeObserved
    nested_residual_vram_raw_summary = $nestedResidualVramRawSummary
    nested_residual_vram_route_calls = $nestedResidualVramRouteCalls
    nested_residual_vram_hits = $nestedResidualVramHits
    nested_residual_vram_misses = $nestedResidualVramMisses
    nested_residual_vram_host_fills = $nestedResidualVramHostFills
    nested_residual_vram_host_bytes = $nestedResidualVramHostBytes
    nested_residual_vram_h2d_bytes = $nestedResidualVramH2DBytes
    nested_residual_vram_failures = $nestedResidualVramFailures
    nested_residual_base_storage_raw_summary =
        $nestedResidualBaseStorageRawSummary
    nested_residual_base_pinned_entries = $nestedResidualBasePinnedEntries
    nested_residual_base_pinned_bytes = $nestedResidualBasePinnedBytes
    nested_residual_base_pinned_hits = $nestedResidualBasePinnedHits
    nested_residual_base_pinned_h2d_bytes =
        $nestedResidualBasePinnedH2DBytes
    nested_residual_base_pageable_entries =
        $nestedResidualBasePageableEntries
    nested_residual_base_pageable_bytes = $nestedResidualBasePageableBytes
    nested_residual_base_pageable_hits = $nestedResidualBasePageableHits
    nested_residual_base_pageable_h2d_bytes =
        $nestedResidualBasePageableH2DBytes
    nested_residual_storage_invariant_failures =
        $nestedResidualStorageInvariantFailures
    nested_residual_cache_pageable_raw_summary =
        $nestedResidualCachePageableRawSummary
    nested_residual_cache_pinned_entries = $nestedResidualCachePinnedEntries
    nested_residual_cache_pinned_bytes = $nestedResidualCachePinnedBytes
    nested_residual_cache_pinned_hits = $nestedResidualCachePinnedHits
    nested_residual_cache_pinned_h2d_bytes =
        $nestedResidualCachePinnedH2DBytes
    nested_residual_cache_pageable_entries =
        $nestedResidualCachePageableEntries
    nested_residual_cache_pageable_bytes = $nestedResidualCachePageableBytes
    nested_residual_cache_pageable_hits = $nestedResidualCachePageableHits
    nested_residual_cache_pageable_h2d_bytes =
        $nestedResidualCachePageableH2DBytes
    nested_residual_cache_pageable_cached_join_calls =
        $nestedResidualCachePageableCachedJoinCalls
    nested_residual_cache_layer_partitioned =
        $nestedResidualCacheLayerPartitioned
    nested_residual_cache_layer_slots_min =
        $nestedResidualCacheLayerSlotsMin
    nested_residual_cache_layer_slots_max =
        $nestedResidualCacheLayerSlotsMax
    nested_residual_cache_pageable_invariant_failures =
        $nestedResidualCachePageableInvariantFailures
    nested_residual_gpu_join_observed = $nestedResidualGpuJoinObserved
    nested_residual_gpu_join_raw_summary = $nestedResidualGpuJoinRawSummary
    nested_residual_gpu_join_requested_runtime =
        $nestedResidualGpuJoinRequestedRuntime
    nested_residual_gpu_join_observed_runtime =
        $nestedResidualGpuJoinObservedRuntime
    nested_residual_gpu_join_calls = $nestedResidualGpuJoinCalls
    nested_residual_gpu_join_blocks = $nestedResidualGpuJoinBlocks
    nested_residual_gpu_join_base_h2d_bytes =
        $nestedResidualGpuJoinBaseH2DBytes
    nested_residual_gpu_join_residual_h2d_bytes =
        $nestedResidualGpuJoinResidualH2DBytes
    nested_residual_gpu_join_native_h2d_bytes =
        $nestedResidualGpuJoinNativeH2DBytes
    nested_residual_gpu_join_seconds = $nestedResidualGpuJoinSeconds
    nested_residual_gpu_join_wait_calls =
        $nestedResidualGpuJoinWaitCalls
    nested_residual_gpu_join_wait_seconds =
        $nestedResidualGpuJoinWaitSeconds
    nested_residual_gpu_join_verify_calls =
        $nestedResidualGpuJoinVerifyCalls
    nested_residual_gpu_join_verify_bytes =
        $nestedResidualGpuJoinVerifyBytes
    nested_residual_gpu_join_verify_seconds =
        $nestedResidualGpuJoinVerifySeconds
    nested_residual_gpu_join_verify_mismatches =
        $nestedResidualGpuJoinVerifyMismatches
    nested_residual_gpu_join_failures = $nestedResidualGpuJoinFailures
    nested_residual_gpu_join_cpu_reconstruct_calls =
        $nestedResidualGpuJoinCpuReconstructCalls
    nested_residual_gpu_join_residual_cache_requested =
        [bool]$NestedResidualGpuJoinResidualCache
    nested_residual_gpu_join_residual_cache_observed =
        $nestedResidualGpuJoinResidualCacheObserved
    nested_residual_gpu_join_residual_cache_raw_summary =
        $nestedResidualGpuJoinResidualCacheRawSummary
    nested_residual_gpu_join_residual_cache_enabled_runtime =
        $nestedResidualGpuJoinResidualCacheEnabledRuntime
    nested_residual_gpu_join_residual_cache_hits =
        $nestedResidualGpuJoinResidualCacheHits
    nested_residual_gpu_join_residual_cache_misses =
        $nestedResidualGpuJoinResidualCacheMisses
    nested_residual_gpu_join_residual_cache_evictions =
        $nestedResidualGpuJoinResidualCacheEvictions
    nested_residual_gpu_join_residual_cache_entries =
        $nestedResidualGpuJoinResidualCacheEntries
    nested_residual_gpu_join_residual_cache_capacity =
        $nestedResidualGpuJoinResidualCacheCapacity
    nested_residual_gpu_join_residual_cache_pread_bytes =
        $nestedResidualGpuJoinResidualCachePreadBytes
    nested_residual_gpu_join_residual_cache_pread_bytes_avoided =
        $nestedResidualGpuJoinResidualCachePreadBytesAvoided
    nested_residual_gpu_join_residual_cache_h2d_bytes =
        $nestedResidualGpuJoinResidualCacheH2DBytes
    nested_residual_gpu_join_residual_cache_cached_join_calls =
        $nestedResidualGpuJoinResidualCacheCachedJoinCalls
    nested_residual_gpu_join_residual_cache_invariant_failures =
        $nestedResidualGpuJoinResidualCacheInvariantFailures
    nested_residual_profile_requested = [bool]$NestedResidualProfile
    nested_residual_profile_observed = $nestedResidualProfileObserved
    nested_residual_profile = [ordered]@{
        raw_summary = $nestedResidualProfileRawSummary
        lookup_calls = $nestedResidualProfileLookupCalls
        lookup_seconds = $nestedResidualProfileLookupSeconds
        pread_calls = $nestedResidualProfilePreadCalls
        pread_seconds = $nestedResidualProfilePreadSeconds
        reconstruct_calls = $nestedResidualProfileReconstructCalls
        reconstruct_blocks = $nestedResidualProfileReconstructBlocks
        reconstruct_seconds = $nestedResidualProfileReconstructSeconds
        verify_calls = $nestedResidualProfileVerifyCalls
        verify_bytes = $nestedResidualProfileVerifyBytes
        verify_seconds = $nestedResidualProfileVerifySeconds
        reuse_wait_calls = $nestedResidualProfileReuseWaitCalls
        reuse_wait_seconds = $nestedResidualProfileReuseWaitSeconds
        host_copy_calls = $nestedResidualProfileHostCopyCalls
        host_copy_seconds = $nestedResidualProfileHostCopySeconds
        h2d_enqueue_calls = $nestedResidualProfileH2DEnqueueCalls
        h2d_enqueue_seconds = $nestedResidualProfileH2DEnqueueSeconds
        h2d_sync_calls = $nestedResidualProfileH2DSyncCalls
        h2d_sync_seconds = $nestedResidualProfileH2DSyncSeconds
        route_begin_calls = $nestedResidualProfileRouteBeginCalls
        route_begin_seconds = $nestedResidualProfileRouteBeginSeconds
        route_submit_launch_calls = $nestedResidualProfileRouteBeginCalls
        route_submit_launch_seconds = $nestedResidualProfileRouteBeginSeconds
        route_resolve_sync_calls =
            $nestedResidualProfileRouteResolveSyncCalls
        route_resolve_sync_seconds =
            $nestedResidualProfileRouteResolveSyncSeconds
        route_ready_wait_calls = $nestedResidualProfileRouteReadyWaitCalls
        route_ready_wait_seconds = $nestedResidualProfileRouteReadyWaitSeconds
        packed_copy = $nestedResidualProfilePackedCopy
        split_fused = $nestedResidualProfileSplitFused
        verify = $nestedResidualProfileVerify
    }
    ds4_q1_0_expert_sidecar = $(if ($q1_0SidecarInfoAtStart) { $q1_0SidecarInfoAtStart.FullName } else { "" })
    ds4_q1_0_selected_load = $(if ($Q1_0ExpertSidecar -and $Q1_0SelectedLoad) { "1" } else { "" })
    ds4_q1_0_resident_arena = $(if ($Q1_0ExpertSidecar -and $Q1_0ResidentArena) { "1" } else { "" })
    ds4_q1_0_dual_arena = $(if ($Q1_0ExpertSidecar -and $Q1_0DualArena) { "1" } else { "" })
    ds4_q1_0_dual_sparse_companion = $(if ($Q1_0ExpertSidecar -and $Q1_0DualSparseCompanion) { "1" } else { "" })
    ds4_q1_0_mixed_cold_one = $(if ($Q1_0ExpertSidecar -and $Q1_0MixedColdOne) { "1" } else { "" })
    ds4_q1_0_pageable_overflow = $(if ($Q1_0ExpertSidecar -and $Q1_0PageableOverflow) { "1" } else { "" })
    ds4_q1_0_dynamic_arena_gb = $(if ($Q1_0ExpertSidecar -and $Q1_0ArenaGB -gt 0.0) { $Q1_0ArenaGB.ToString("0.###", [Globalization.CultureInfo]::InvariantCulture) } else { "" })
    ds4_q1_0_dynamic_promotion = $(if ($Q1_0ExpertSidecar -and $Q1_0DynamicPromotion) { "1" } else { "" })
    ds4_q1_0_promotion_ssd_wrap = $(if ($Q1_0PromotionSsdWrap) { "1" } else { "" })
    ds4_q1_0_iq2_pinned_gib = $(if ($Q1_0PromotionSsdWrap) { $Q1_0Iq2PinnedGiB.ToString("R", [Globalization.CultureInfo]::InvariantCulture) } else { "" })
    ds4_q1_0_profile = $(if ($Q1_0ExpertSidecar -and $Q1_0Profile) { "1" } else { "" })
    ds4_expert_recovery_trace = $(if ($ExpertRecoveryTrace) { "1" } else { "" })
    ds4_expert_recovery_trace_layer = $(if ($ExpertRecoveryTrace) { [string]$ExpertRecoveryTraceLayer } else { "" })
    ds4_expert_recovery_trace_expert = $(if ($ExpertRecoveryTrace) { [string]$ExpertRecoveryTraceExpert } else { "" })
    ds4_expert_recovery_trace_max_samples = $(if ($ExpertRecoveryTrace) { [string]$ExpertRecoveryTraceMaxSamples } else { "" })
    ds4_expert_recovery_trace_max_bytes = $(if ($ExpertRecoveryTrace) { [string]$ExpertRecoveryTraceByteBudget } else { "" })
    ds4_expert_recovery_trace_output_prefix = $(if ($ExpertRecoveryTrace) { $expertRecoveryTracePrefix } else { "" })
    ds4_q1_0_promotion_probation_slots = $(if ($Q1_0ExpertSidecar -and $Q1_0DynamicPromotion) { [string]$Q1_0PromotionProbationSlots } else { "" })
    ds4_q1_0_promotion_min_touches = $(if ($Q1_0ExpertSidecar -and $Q1_0DynamicPromotion) { [string]$Q1_0PromotionMinTouches } else { "" })
    ds4_q1_0_promotion_min_weight = $(if ($Q1_0ExpertSidecar -and $Q1_0DynamicPromotion) { $Q1_0PromotionMinWeight.ToString("R", [Globalization.CultureInfo]::InvariantCulture) } else { "" })
    ds4_q1_0_promotion_min_mass = $(if ($Q1_0ExpertSidecar -and $Q1_0DynamicPromotion) { $Q1_0PromotionMinMass.ToString("R", [Globalization.CultureInfo]::InvariantCulture) } else { "" })
    ds4_q1_0_promotion_request_budget = $(if ($Q1_0ExpertSidecar -and $Q1_0DynamicPromotion) { [string]$Q1_0PromotionRequestBudget } else { "" })
    ds4_q1_0_promotion_window_calls = $(if ($Q1_0ExpertSidecar -and $Q1_0DynamicPromotion) { [string]$Q1_0PromotionWindowCalls } else { "" })
    ds4_q1_0_promotion_window_budget = $(if ($Q1_0ExpertSidecar -and $Q1_0DynamicPromotion) { [string]$Q1_0PromotionWindowBudget } else { "" })
    ds4_q1_0_mixed_trace = $(if ($Q1_0ExpertSidecar -and $Q1_0MixedTrace) { "1" } else { "" })
    ds4_q1_0_layer_first = $(if ($Q1_0ExpertSidecar) { [string]$Q1_0LayerFirst } else { "" })
    ds4_q1_0_layer_last = $(if ($Q1_0ExpertSidecar) { [string]$Q1_0LayerLast } else { "" })
    q1_0_sidecar_enabled = [bool]$Q1_0ExpertSidecar
    q1_0_selected_load_requested = [bool]$Q1_0SelectedLoad
    q1_0_resident_arena_requested = [bool]$Q1_0ResidentArena
    q1_0_dual_arena_requested = [bool]$Q1_0DualArena
    q1_0_dual_sparse_companion_requested = [bool]$Q1_0DualSparseCompanion
    q1_0_mixed_cold_one_requested = [bool]$Q1_0MixedColdOne
    q1_0_snapshot_backing_requested = [bool]$Q1_0SnapshotBacking
    q1_0_pageable_overflow_requested = [bool]$Q1_0PageableOverflow
    q1_0_dynamic_arena_gb_requested = $Q1_0ArenaGB
    q1_0_dynamic_promotion_requested = [bool]$Q1_0DynamicPromotion
    q1_0_promotion_requested_config = [pscustomobject]@{
        probation_slots = $Q1_0PromotionProbationSlots
        min_touches = $Q1_0PromotionMinTouches
        min_weight = $Q1_0PromotionMinWeight
        min_mass = $Q1_0PromotionMinMass
        request_budget = $Q1_0PromotionRequestBudget
        window_calls = $Q1_0PromotionWindowCalls
        window_budget = $Q1_0PromotionWindowBudget
    }
    q1_0_promotion_probation_slots_requested = $Q1_0PromotionProbationSlots
    q1_0_promotion_min_touches_requested = $Q1_0PromotionMinTouches
    q1_0_promotion_min_weight_requested = $Q1_0PromotionMinWeight
    q1_0_promotion_min_mass_requested = $Q1_0PromotionMinMass
    q1_0_promotion_request_budget_requested = $Q1_0PromotionRequestBudget
    q1_0_promotion_window_calls_requested = $Q1_0PromotionWindowCalls
    q1_0_promotion_window_budget_requested = $Q1_0PromotionWindowBudget
    q1_0_pure_resident_requested = [bool]$Q1_0PureResident
    q1_0_snapshot_entries_expected = $ExpectedQ1_0SnapshotEntries
    q1_0_resident_entries_expected = $ExpectedQ1_0ResidentEntries
    q1_0_mixed_trace_requested = [bool]$Q1_0MixedTrace
    q1_0_mixed_resolver_required = $q1_0MixedResolverRequired
    q1_0_mixed_expected_router = $q1_0MixedExpectedRouter
    q1_0_dual_arena_runtime_observed = $q1_0DualArenaRuntimeObserved
    q1_0_dual_sparse_runtime_observed = $q1_0DualSparseRuntimeObserved
    q1_0_dual_sparse_entries = $q1_0DualSparseEntries
    q1_0_dual_sparse_bytes = $q1_0DualSparseBytes
    q1_0_dual_sparse_stage_seconds = $q1_0DualSparseStageSeconds
    q1_0_dual_sparse_publications = $q1_0DualSparsePublications
    q1_0_dual_sparse_failures = $q1_0DualSparseFailures
    q1_0_layer_first_requested = $(if ($Q1_0ExpertSidecar) { $Q1_0LayerFirst } else { 0 })
    q1_0_layer_last_requested = $(if ($Q1_0ExpertSidecar) { $Q1_0LayerLast } else { 0 })
    q1_0_sidecar_path = $(if ($q1_0SidecarInfoAtStart) { $q1_0SidecarInfoAtStart.FullName } else { "" })
    q1_0_sidecar_size_bytes = $(if ($q1_0SidecarInfoAtStart) { [UInt64]$q1_0SidecarInfoAtStart.Length } else { [UInt64]0 })
    q1_0_sidecar_expected_size_bytes = $ExpectedQ1_0ExpertSidecarBytes
    q1_0_sidecar_expected_sha256 = $(if ($ExpectedQ1_0ExpertSidecarSHA256) { $ExpectedQ1_0ExpertSidecarSHA256.ToLowerInvariant() } else { "" })
    q1_0_sidecar_sha256 = $q1_0SidecarHashAtStart
    q1_0_sidecar_hash_method = $q1_0SidecarHashMethod
    q1_0_sidecar_receipt_path = $q1_0SidecarReceiptPath
    q1_0_sidecar_receipt_sha256 = $q1_0SidecarReceiptHashAtStart
    q1_0_sidecar_provenance_verified = $q1_0SidecarProvenanceVerified
    q1_0_sidecar_receipt_reuse_requested = [bool]$ReuseVerifiedQ1_0Receipt
    q1_0_sidecar_runtime_observed = $q1_0SidecarRuntimeObserved
    q1_0_sidecar_route_calls = $q1_0SidecarCalls
    q1_0_sidecar_route_slots = $q1_0SidecarSlots
    q1_0_sidecar_selected_loads = $q1_0SidecarSelectedLoads
    q1_0_sidecar_failures = $q1_0SidecarFailures
    q1_0_resident_mode = $q1_0ResidentMode
    q1_0_resident_hits = $q1_0ResidentHits
    q1_0_resident_misses = $q1_0ResidentMisses
    q1_0_resident_h2d_bytes = $q1_0ResidentH2DBytes
    q1_0_direct_pread_fallbacks = $q1_0DirectPreadFallbacks
    q1_0_direct_pread_bytes = $q1_0DirectPreadBytes
    q1_0_bootstrap_entries = $q1_0BootstrapEntries
    q1_0_bootstrap_pinned_bytes = $q1_0BootstrapPinnedBytes
    q1_0_bootstrap_pageable_bytes = $q1_0BootstrapPageableBytes
    q1_0_bootstrap_pinned_slots = $q1_0BootstrapPinnedSlots
    q1_0_bootstrap_pageable_slots = $q1_0BootstrapPageableSlots
    q1_0_bootstrap_total_slots = $q1_0BootstrapTotalSlots
    q1_0_bootstrap_total_bytes = $q1_0BootstrapTotalBytes
    q1_0_bootstrap_layer_first = $q1_0BootstrapLayerFirst
    q1_0_bootstrap_layer_last = $q1_0BootstrapLayerLast
    q1_0_source_unlock_observed = $q1_0SourceUnlockObserved
    q1_0_source_unlock_result = $q1_0SourceUnlockResult
    q1_0_source_unlock_windows = $q1_0SourceUnlockWindows
    q1_0_source_unlock_page_size = $q1_0SourceUnlockPageSize
    q1_0_source_unlock_page_aligned = $q1_0SourceUnlockPageAligned
    q1_0_source_unlock_destination_unchanged =
        $q1_0SourceUnlockDestinationUnchanged
    q1_0_source_unlock_layers = $q1_0SourceUnlockLayers
    q1_0_source_unlock_ranges_attempted =
        $q1_0SourceUnlockRangesAttempted
    q1_0_source_unlock_bytes_attempted = $q1_0SourceUnlockBytesAttempted
    q1_0_source_unlock_calls = $q1_0SourceUnlockCalls
    q1_0_source_unlock_success = $q1_0SourceUnlockSuccess
    q1_0_source_unlock_not_locked = $q1_0SourceUnlockNotLocked
    q1_0_source_unlock_failed = $q1_0SourceUnlockFailed
    q1_0_source_unlock_classification = $q1_0SourceUnlockClassification
    q1_0_source_unlock_seconds = $q1_0SourceUnlockSeconds
    q1_0_source_unlock_available_before =
        $q1_0SourceUnlockAvailableBefore
    q1_0_source_unlock_available_after = $q1_0SourceUnlockAvailableAfter
    q1_0_source_unlock_working_set_before =
        $q1_0SourceUnlockWorkingSetBefore
    q1_0_source_unlock_working_set_after =
        $q1_0SourceUnlockWorkingSetAfter
    q1_0_source_unlock_page_fault_before =
        $q1_0SourceUnlockPageFaultBefore
    q1_0_source_unlock_page_fault_after =
        $q1_0SourceUnlockPageFaultAfter
    q1_0_source_unlock_read_transfer_before =
        $q1_0SourceUnlockReadTransferBefore
    q1_0_source_unlock_read_transfer_after =
        $q1_0SourceUnlockReadTransferAfter
    q1_0_source_unlock_last_error = $q1_0SourceUnlockLastError
    q1_0_mixed = $q1_0MixedTelemetry
    q1_0_mixed_route_trace = $q1_0MixedRouteTraceTelemetry
    q1_0_mixed_iq2_routes = $q1_0MixedIq2Routes
    q1_0_mixed_accounted_routes = $q1_0MixedAccountedRoutes
    q1_0_profile_requested = [bool]$Q1_0Profile
    q1_0_profile = $q1_0ProfileTelemetry
    q1_0_promotion_ssd_wrap_requested = [bool]$Q1_0PromotionSsdWrap
    q1_0_iq2_pinned_gib_requested = $Q1_0Iq2PinnedGiB
    q1_0_ssd_wrap = $q1_0SsdWrapTelemetry
    expert_recovery_trace_requested = [bool]$ExpertRecoveryTrace
    expert_recovery_trace = $expertRecoveryTraceArtifact
    expert_recovery_trace_performance_eligible = $false
    expert_recovery_trace_quality_eligible = $false
    q1_0_runtime_contract_valid = $q1_0RuntimeContractValid
    q1_0_fail_closed_checks_passed = $q1_0RuntimeContractValid
    q1_0_fail_closed_observed = $q1_0FailClosedObserved
    q1_0_structural_smoke_eligible = $q1_0StructuralSmokeEligible
    q1_0_performance_eligible = $false
    q1_0_quality_eligible = $false
    iq1_s_sidecar_path = $(if ($iq1SSidecarInfoAtStart) { $iq1SSidecarInfoAtStart.FullName } else { "" })
    iq1_s_sidecar_size_bytes = $(if ($iq1SSidecarInfoAtStart) { [UInt64]$iq1SSidecarInfoAtStart.Length } else { [UInt64]0 })
    iq1_s_sidecar_expected_sha256 = $ExpectedIq1SExpertSidecarSHA256.ToLowerInvariant()
    iq1_s_sidecar_sha256 = $iq1SSidecarHashAtStart
    iq1_s_sidecar_hash_method = $iq1SSidecarHashMethod
    iq1_s_sidecar_receipt_path = $iq1SSidecarReceiptPath
    iq1_s_sidecar_receipt_sha256 = $iq1SSidecarReceiptHashAtStart
    iq1_s_sidecar_runtime_observed = $iq1SSidecarRuntimeObserved
    iq1_s_sidecar_route_calls = $iq1SSidecarCalls
    iq1_s_sidecar_route_slots = $iq1SSidecarSlots
    iq1_s_sidecar_selected_loads = $iq1SSidecarSelectedLoads
    iq1_s_sidecar_failures = $iq1SSidecarFailures
    iq1_s_ram_cache_requested_gib = $Iq1SRamCacheGiB
    iq1_s_ram_cache_pageable_requested = [bool]$Iq1SRamCachePageable
    iq1_s_ram_cache_preload_all_requested = [bool]$Iq1SRamCachePreloadAll
    iq1_s_ram_cache_runtime_observed = $iq1SRamCacheRuntimeObserved
    iq1_s_ram_cache_requested_bytes = $iq1SRamCacheRequestedBytes
    iq1_s_ram_cache_allocated_bytes = $iq1SRamCacheAllocatedBytes
    iq1_s_ram_cache_capacity = $iq1SRamCacheCapacity
    iq1_s_ram_cache_count = $iq1SRamCacheCount
    iq1_s_ram_cache_slot_bytes = $iq1SRamCacheSlotBytes
    iq1_s_ram_cache_hits = $iq1SRamCacheHits
    iq1_s_ram_cache_misses = $iq1SRamCacheMisses
    iq1_s_ram_cache_evictions = $iq1SRamCacheEvictions
    iq1_s_ram_cache_ssd_bytes = $iq1SRamCacheSsdBytes
    iq1_s_ram_cache_h2d_bytes = $iq1SRamCacheH2dBytes
    iq1_s_ram_cache_failures = $iq1SRamCacheFailures
    iq1_s_ram_cache_hit_rate = $iq1SRamCacheHitRate
    iq1_s_ram_cache_ssd_avoided_bytes = $iq1SRamCacheSsdAvoidedBytes
    iq1_s_ram_cache_preload_frozen = $iq1SRamCachePreloadFrozen
    iq1_s_ram_cache_preload_layers = $iq1SRamCachePreloadLayers
    iq1_s_ram_cache_preload_entries = $iq1SRamCachePreloadEntries
    iq1_s_ram_cache_preload_ssd_bytes = $iq1SRamCachePreloadSsdBytes
    iq1_s_ram_cache_preload_read_calls = $iq1SRamCachePreloadReadCalls
    iq1_s_ram_cache_preload_ms = $iq1SRamCachePreloadMs
    iq1_s_vram_cache_per_layer_requested = $Iq1SVramCachePerLayer
    iq1_s_vram_cache_runtime_observed = $iq1SVramCacheRuntimeObserved
    iq1_s_vram_cache_capacity = $iq1SVramCacheCapacity
    iq1_s_vram_cache_count = $iq1SVramCacheCount
    iq1_s_vram_cache_slot_bytes = $iq1SVramCacheSlotBytes
    iq1_s_vram_cache_hits = $iq1SVramCacheHits
    iq1_s_vram_cache_misses = $iq1SVramCacheMisses
    iq1_s_vram_cache_evictions = $iq1SVramCacheEvictions
    iq1_s_vram_cache_h2d_bytes = $iq1SVramCacheH2dBytes
    iq1_s_vram_cache_failures = $iq1SVramCacheFailures
    iq1_s_mixed_cold_one = [bool]$Iq1SMixedColdOne
    iq1_s_mixed_runtime_observed = $iq1MixedRuntimeObserved
    iq1_s_mixed_calls = $iq1MixedCalls
    iq1_s_mixed_hot_main = $iq1MixedHotMain
    iq1_s_mixed_cold_iq1 = $iq1MixedColdIq1
    iq1_s_mixed_primary_cold_avoided = $iq1MixedPrimaryColdAvoided
    iq1_s_mixed_joins = $iq1MixedJoins
    iq1_s_mixed_failures = $iq1MixedFailures
    iq1_s_mixed_last_layer = $iq1MixedLastLayer
    iq1_s_mixed_last_slot = $iq1MixedLastSlot
    iq1_s_mixed_last_expert = $iq1MixedLastExpert
    iq1_s_mixed_gpu_plan_requested = [bool]$Iq1SMixedGpuPlan
    iq1_s_mixed_gpu_plan_runtime_observed = $iq1MixedGpuPlanRuntimeObserved
    iq1_s_mixed_gpu_plan_calls = $iq1MixedGpuPlanCalls
    iq1_s_mixed_gpu_plan_wait_ms = $iq1MixedGpuPlanWaitMs
    iq1_s_mixed_gpu_plan_failures = $iq1MixedGpuPlanFailures
    iq1_promotion_requested = [bool]$quantPromotionRequested
    iq1_promotion_kind = $(if ($Q1_0DynamicPromotion) { "q1_0" } elseif ($Iq1Promotion) { "iq1_s" } else { "off" })
    iq1_promotion_probation_slots_requested = $promotionProbationSlotsExpected
    iq1_promotion_min_touches_requested = $promotionMinTouchesExpected
    iq1_promotion_min_weight_requested = $promotionMinWeightExpected
    iq1_promotion_min_mass_requested = $promotionMinMassExpected
    iq1_promotion_request_budget_requested = $promotionRequestBudgetExpected
    iq1_promotion_window_calls_requested = $promotionWindowCallsExpected
    iq1_promotion_window_budget_requested = $promotionWindowBudgetExpected
    iq1_promotion_runtime_observed = $iq1PromotionRuntimeObserved
    iq1_promotion_line_count = $iq1PromotionLineCount
    iq1_promotion_requested_slots = $iq1PromotionRequestedSlots
    iq1_promotion_reserved_slots = $iq1PromotionReservedSlots
    iq1_promotion_snapshot_evictions = $iq1PromotionSnapshotEvictions
    iq1_promotion_reserve_strategies = $iq1PromotionReserveStrategies
    iq1_promotion_min_touches = $iq1PromotionObservedMinTouches
    iq1_promotion_min_weight = $iq1PromotionObservedMinWeight
    iq1_promotion_min_mass = $iq1PromotionObservedMinMass
    iq1_promotion_request_budget = $iq1PromotionObservedRequestBudget
    iq1_promotion_window_calls = $iq1PromotionObservedWindowCalls
    iq1_promotion_window_budget = $iq1PromotionObservedWindowBudget
    iq1_promotion_cold_observed = $iq1PromotionColdObserved
    iq1_promotion_cold_existing_2bit = $iq1PromotionColdExisting2Bit
    iq1_promotion_cold_to_2bit_ram = $iq1PromotionColdTo2BitRam
    iq1_promotion_cold_gate_candidates = $iq1PromotionColdGateCandidates
    iq1_promotion_weight_ge_001 = $iq1PromotionWeightGe001
    iq1_promotion_weight_ge_002 = $iq1PromotionWeightGe002
    iq1_promotion_weight_ge_005 = $iq1PromotionWeightGe005
    iq1_promotion_weight_ge_010 = $iq1PromotionWeightGe010
    iq1_promotion_skips_touches = $iq1PromotionSkipsTouches
    iq1_promotion_skips_weight = $iq1PromotionSkipsWeight
    iq1_promotion_skips_mass = $iq1PromotionSkipsMass
    iq1_promotion_skips_request_budget = $iq1PromotionSkipsRequestBudget
    iq1_promotion_skips_window_budget = $iq1PromotionSkipsWindowBudget
    iq1_promotion_probation_ram_hits = $iq1PromotionProbationRamHits
    iq1_promotion_next_token_waits = $iq1PromotionNextTokenWaits
    iq1_promotion_2bit_ssd_bytes = $iq1Promotion2BitSsdBytes
    iq1_promotion_2bit_ssd_seconds = $iq1Promotion2BitSsdSeconds
    iq1_promotion_2bit_ssd_bytes_per_second = $iq1Promotion2BitSsdBytesPerSecond
    iq1_promotion_direct_ssd_to_vram_rejected = $iq1PromotionDirectSsdToVramRejected
    iq1_promotion_probation_backing_reclaims = $iq1PromotionProbationBackingReclaims
    iq1_promotion_q1_0_observed = $iq1PromotionQ1_0Observed
    iq1_promotion_q1_0_stage_attempts = $iq1PromotionQ1_0StageAttempts
    iq1_promotion_q1_0_stage_successes = $iq1PromotionQ1_0StageSuccesses
    iq1_promotion_q1_0_next_call_guards = $iq1PromotionQ1_0NextCallGuards
    iq1_promotion_q1_0_record_rejects = $iq1PromotionQ1_0RecordRejects
    iq1_promotion_q1_0_record_attempts = $iq1PromotionQ1_0RecordAttempts
    iq1_promotion_q1_0_record_successes = $iq1PromotionQ1_0RecordSuccesses
    iq1_promotion_q1_0_record_failures = $iq1PromotionQ1_0RecordFailures
    q1_0_promotion_records_observed = [bool]($q1_0PromotionRecordCount -gt 0)
    q1_0_promotion_records_path = $q1_0PromotionRecordArtifactPath
    q1_0_promotion_records_sha256 = $q1_0PromotionRecordArtifactSHA256
    q1_0_promotion_records_count = $q1_0PromotionRecordCount
    q1_0_promotion_records_physical_line_count =
        $q1_0PromotionRecordPhysicalLineCount
    q1_0_promotion_record_attempt_count = $q1_0PromotionRecordAttemptCount
    q1_0_promotion_record_success_count = $q1_0PromotionRecordSuccessCount
    q1_0_promotion_record_reject_count = $q1_0PromotionRecordRejectCount
    q1_0_promotion_record_failure_count = $q1_0PromotionRecordFailureCount
    q1_0_promotion_record_bounded_exception_limit =
        $q1_0PromotionRecordBoundedExceptionLimit
    q1_0_promotion_telemetry_record_limit =
        $q1_0PromotionTelemetryRecordLimit
    iq1_promotion_failures = $iq1PromotionFailures
    iq1_promotion_requests = $iq1PromotionRows
    iq1_s_profile_requested = [bool]$Iq1SProfile
    iq1_s_no_main_sync_requested = [bool]$Iq1SNoMainSync
    iq1_s_packed_h2d_requested = [bool]$Iq1SPackedH2D
    iq1_s_profile_ssd_read_calls = $iq1ProfileSsdReadCalls
    iq1_s_profile_ssd_read_ms = $iq1ProfileSsdReadMs
    iq1_s_profile_h2d_batches = $iq1ProfileH2dBatches
    iq1_s_profile_h2d_copies = $iq1ProfileH2dCopies
    iq1_s_profile_h2d_enqueue_ms = $iq1ProfileH2dEnqueueMs
    iq1_s_profile_h2d_syncs = $iq1ProfileH2dSyncs
    iq1_s_profile_h2d_sync_ms = $iq1ProfileH2dSyncMs
    iq1_s_mixed_profile_calls = $iq1MixedProfileCalls
    iq1_s_mixed_profile_router_d2h_ms = $iq1MixedProfileRouterD2hMs
    iq1_s_mixed_profile_metadata_h2d_ms = $iq1MixedProfileMetadataH2dMs
    iq1_s_mixed_profile_main_submit_ms = $iq1MixedProfileMainSubmitMs
    iq1_s_mixed_profile_main_sync_ms = $iq1MixedProfileMainSyncMs
    iq1_s_mixed_profile_cold_submit_ms = $iq1MixedProfileColdSubmitMs
    iq1_s_mixed_profile_join_submit_ms = $iq1MixedProfileJoinSubmitMs
    warmup_result = $warmupResult
    output_hashes = $hashes
    outputs_identical = ($hashes.Count -eq 1)
    non_identical_repeat_outputs_allowed = [bool]$AllowNonIdenticalRepeatOutputs
    expert_tiering = $expertTieringResult
    results = $results
}
$rawOutputs | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 $rawOutputsPath
if ($q1_0SourceUnlockFailed -ne 0) {
    throw "Q1_0 source unlock telemetry counters are inconsistent"
}
if ($Repeats -gt 1 -and $hashes.Count -ne 1 -and -not $AllowNonIdenticalRepeatOutputs) {
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
    gate_kind = $GateKind
    force_open_router_requested = [bool]$ForceOpenRouter
    quality_eligible = $qualityEligible
    sota_eligible = $sotaEligible
    contamination_reason = $contaminationReason
    allow_quality_verified_suite_receipt_requested =
        [bool]$AllowQualityVerifiedSuiteReceipt
    outer_quality_process_count_requested = $OuterQualityProcessCount
    outer_quality_suite_member = $outerQualitySuiteMember
    outer_quality_member_contract_valid = $outerQualitySuiteMember
    outer_quality_aggregate_required = $outerQualitySuiteMember
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
    server_exit_code = $serverExitCode
    model = $model
    model_bytes = [long]$modelInfoAtStart.Length
    model_last_write_utc = $modelInfoAtStart.LastWriteTimeUtc.ToString("o")
    model_expected_sha256 = $ExpectedModelSHA256.ToLowerInvariant()
    model_sha256 = $modelHashAtStart
    model_hash_method = $modelHashMethod
    model_receipt_path = $modelReceiptPath
    model_receipt_sha256 = $modelReceiptHashAtStart
    model_iq1_suite_receipt_path = $modelIq1SuiteReceiptPathAtStart
    model_iq1_suite_receipt_sha256 = $modelIq1SuiteReceiptHashAtStart
    model_iq1_suite_receipt_schema = $modelIq1SuiteReceiptSchemaAtStart
    model_iq1_suite_full_hash_verified = $modelIq1SuiteFullHashVerified
    model_iq1_suite_lock_proof_required =
        $modelIq1SuiteLockProofRequired
    model_iq1_suite_lock_proof_observed =
        $modelIq1SuiteLockProofObserved
    model_iq1_suite_lock_proof = $modelIq1SuiteLockProof
    benchmark_verified_receipt_reuse_allowed =
        [bool]$AllowBenchmarkVerifiedReceiptReuse
    benchmark_verified_receipt_lock_proof_required =
        $benchmarkVerifiedReceiptLockProofRequired
    benchmark_verified_receipt_lock_proof_observed =
        $benchmarkVerifiedReceiptLockProofObserved
    benchmark_verified_receipt_lock_proof =
        $benchmarkVerifiedReceiptLockProof
    nested_residual_enabled = [bool]$NestedResidualSidecar
    nested_residual_sidecar = $(if ($nestedResidualInfoAtStart) { $nestedResidualInfoAtStart.FullName } else { "" })
    nested_residual_sidecar_bytes = $(if ($nestedResidualInfoAtStart) { [UInt64]$nestedResidualInfoAtStart.Length } else { [UInt64]0 })
    nested_residual_sidecar_sha256 = $nestedResidualHashAtStart
    nested_residual_expected_source_sha256 = $(if ($ExpectedNestedResidualSourceSHA256) { $ExpectedNestedResidualSourceSHA256.ToLowerInvariant() } else { "" })
    nested_residual_expected_payload_sha256 = $(if ($ExpectedNestedResidualPayloadSHA256) { $ExpectedNestedResidualPayloadSHA256.ToLowerInvariant() } else { "" })
    nested_residual_verify_reconstruction = [bool]$NestedResidualVerifyReconstruction
    nested_residual_cache_experts_requested = $NestedResidualCacheExperts
    nested_residual_pageable_base_requested = [bool]$NestedResidualPageableBase
    nested_residual_base_pinned_gib_requested = $NestedResidualBasePinnedGiB
    nested_residual_cache_pageable_requested = [bool]$NestedResidualCachePageable
    nested_residual_expected_base_host_gib =
        $nestedResidualExpectedBaseHostGiB
    nested_residual_expected_residual_cache_host_gib =
        $nestedResidualExpectedResidualCacheHostGiB
    nested_residual_expected_host_allocation_gib =
        $nestedResidualExpectedHostAllocationGiB
    nested_residual_all_layer_first_layer = $nestedResidualAllLayerFirstLayer
    nested_residual_all_layer_last_layer = $nestedResidualAllLayerLastLayer
    nested_residual_all_layer_count = $nestedResidualAllLayerCount
    nested_residual_structural_n1_requested = [bool]$NestedResidualStructuralN1
    nested_residual_gpu_cache_requested = [bool]$NestedResidualGpuCache
    nested_residual_gpu_join_requested = [bool]$NestedResidualGpuJoin
    nested_residual_gpu_join_safety_receipt_path =
        $nestedResidualGpuJoinSafetyReceiptPathAtStart
    nested_residual_gpu_join_safety_receipt_sha256 =
        $nestedResidualGpuJoinSafetyReceiptHashAtStart
    nested_residual_gpu_join_safety_result_path =
        $nestedResidualGpuJoinSafetyResultPathAtStart
    nested_residual_gpu_join_safety_result_sha256 =
        $nestedResidualGpuJoinSafetyResultHashAtStart
    nested_residual_gpu_join_safety_receipt_validated =
        $nestedResidualGpuJoinSafetyReceiptValidated
    allow_nested_residual_benchmark_suite_requested =
        [bool]$AllowNestedResidualBenchmarkSuite
    outer_nested_residual_benchmark_process_count_requested =
        $OuterNestedResidualBenchmarkProcessCount
    nested_residual_benchmark_member = $nestedResidualBenchmarkMember
    nested_residual_runtime_observed = $nestedResidualRuntimeObserved
    nested_residual_router_calls = $nestedResidualRouterCalls
    nested_residual_cache_hits = $nestedResidualCacheHits
    nested_residual_cache_misses = $nestedResidualCacheMisses
    nested_residual_preads = $nestedResidualPreads
    nested_residual_bytes = $nestedResidualBytes
    nested_residual_reconstructed = $nestedResidualReconstructed
    nested_residual_mismatches = $nestedResidualMismatches
    nested_residual_h2d_bytes = $nestedResidualH2DBytes
    nested_residual_failures = $nestedResidualFailures
    nested_residual_vram_runtime_observed = $nestedResidualVramRuntimeObserved
    nested_residual_vram_raw_summary = $nestedResidualVramRawSummary
    nested_residual_vram_route_calls = $nestedResidualVramRouteCalls
    nested_residual_vram_hits = $nestedResidualVramHits
    nested_residual_vram_misses = $nestedResidualVramMisses
    nested_residual_vram_host_fills = $nestedResidualVramHostFills
    nested_residual_vram_host_bytes = $nestedResidualVramHostBytes
    nested_residual_vram_h2d_bytes = $nestedResidualVramH2DBytes
    nested_residual_vram_failures = $nestedResidualVramFailures
    nested_residual_base_storage_raw_summary =
        $nestedResidualBaseStorageRawSummary
    nested_residual_base_pinned_entries = $nestedResidualBasePinnedEntries
    nested_residual_base_pinned_bytes = $nestedResidualBasePinnedBytes
    nested_residual_base_pinned_hits = $nestedResidualBasePinnedHits
    nested_residual_base_pinned_h2d_bytes =
        $nestedResidualBasePinnedH2DBytes
    nested_residual_base_pageable_entries =
        $nestedResidualBasePageableEntries
    nested_residual_base_pageable_bytes = $nestedResidualBasePageableBytes
    nested_residual_base_pageable_hits = $nestedResidualBasePageableHits
    nested_residual_base_pageable_h2d_bytes =
        $nestedResidualBasePageableH2DBytes
    nested_residual_storage_invariant_failures =
        $nestedResidualStorageInvariantFailures
    nested_residual_cache_pageable_raw_summary =
        $nestedResidualCachePageableRawSummary
    nested_residual_cache_pinned_entries = $nestedResidualCachePinnedEntries
    nested_residual_cache_pinned_bytes = $nestedResidualCachePinnedBytes
    nested_residual_cache_pinned_hits = $nestedResidualCachePinnedHits
    nested_residual_cache_pinned_h2d_bytes =
        $nestedResidualCachePinnedH2DBytes
    nested_residual_cache_pageable_entries =
        $nestedResidualCachePageableEntries
    nested_residual_cache_pageable_bytes = $nestedResidualCachePageableBytes
    nested_residual_cache_pageable_hits = $nestedResidualCachePageableHits
    nested_residual_cache_pageable_h2d_bytes =
        $nestedResidualCachePageableH2DBytes
    nested_residual_cache_pageable_cached_join_calls =
        $nestedResidualCachePageableCachedJoinCalls
    nested_residual_cache_layer_partitioned =
        $nestedResidualCacheLayerPartitioned
    nested_residual_cache_layer_slots_min =
        $nestedResidualCacheLayerSlotsMin
    nested_residual_cache_layer_slots_max =
        $nestedResidualCacheLayerSlotsMax
    nested_residual_cache_pageable_invariant_failures =
        $nestedResidualCachePageableInvariantFailures
    nested_residual_gpu_join_observed = $nestedResidualGpuJoinObserved
    nested_residual_gpu_join_raw_summary = $nestedResidualGpuJoinRawSummary
    nested_residual_gpu_join_requested_runtime =
        $nestedResidualGpuJoinRequestedRuntime
    nested_residual_gpu_join_observed_runtime =
        $nestedResidualGpuJoinObservedRuntime
    nested_residual_gpu_join_calls = $nestedResidualGpuJoinCalls
    nested_residual_gpu_join_blocks = $nestedResidualGpuJoinBlocks
    nested_residual_gpu_join_base_h2d_bytes =
        $nestedResidualGpuJoinBaseH2DBytes
    nested_residual_gpu_join_residual_h2d_bytes =
        $nestedResidualGpuJoinResidualH2DBytes
    nested_residual_gpu_join_native_h2d_bytes =
        $nestedResidualGpuJoinNativeH2DBytes
    nested_residual_gpu_join_seconds = $nestedResidualGpuJoinSeconds
    nested_residual_gpu_join_wait_calls =
        $nestedResidualGpuJoinWaitCalls
    nested_residual_gpu_join_wait_seconds =
        $nestedResidualGpuJoinWaitSeconds
    nested_residual_gpu_join_verify_calls =
        $nestedResidualGpuJoinVerifyCalls
    nested_residual_gpu_join_verify_bytes =
        $nestedResidualGpuJoinVerifyBytes
    nested_residual_gpu_join_verify_seconds =
        $nestedResidualGpuJoinVerifySeconds
    nested_residual_gpu_join_verify_mismatches =
        $nestedResidualGpuJoinVerifyMismatches
    nested_residual_gpu_join_failures = $nestedResidualGpuJoinFailures
    nested_residual_gpu_join_cpu_reconstruct_calls =
        $nestedResidualGpuJoinCpuReconstructCalls
    nested_residual_gpu_join_residual_cache_requested =
        [bool]$NestedResidualGpuJoinResidualCache
    nested_residual_gpu_join_residual_cache_observed =
        $nestedResidualGpuJoinResidualCacheObserved
    nested_residual_gpu_join_residual_cache_raw_summary =
        $nestedResidualGpuJoinResidualCacheRawSummary
    nested_residual_gpu_join_residual_cache_enabled_runtime =
        $nestedResidualGpuJoinResidualCacheEnabledRuntime
    nested_residual_gpu_join_residual_cache_hits =
        $nestedResidualGpuJoinResidualCacheHits
    nested_residual_gpu_join_residual_cache_misses =
        $nestedResidualGpuJoinResidualCacheMisses
    nested_residual_gpu_join_residual_cache_evictions =
        $nestedResidualGpuJoinResidualCacheEvictions
    nested_residual_gpu_join_residual_cache_entries =
        $nestedResidualGpuJoinResidualCacheEntries
    nested_residual_gpu_join_residual_cache_capacity =
        $nestedResidualGpuJoinResidualCacheCapacity
    nested_residual_gpu_join_residual_cache_pread_bytes =
        $nestedResidualGpuJoinResidualCachePreadBytes
    nested_residual_gpu_join_residual_cache_pread_bytes_avoided =
        $nestedResidualGpuJoinResidualCachePreadBytesAvoided
    nested_residual_gpu_join_residual_cache_h2d_bytes =
        $nestedResidualGpuJoinResidualCacheH2DBytes
    nested_residual_gpu_join_residual_cache_cached_join_calls =
        $nestedResidualGpuJoinResidualCacheCachedJoinCalls
    nested_residual_gpu_join_residual_cache_invariant_failures =
        $nestedResidualGpuJoinResidualCacheInvariantFailures
    nested_residual_profile_requested = [bool]$NestedResidualProfile
    nested_residual_profile_observed = $nestedResidualProfileObserved
    nested_residual_profile = [ordered]@{
        raw_summary = $nestedResidualProfileRawSummary
        lookup_calls = $nestedResidualProfileLookupCalls
        lookup_seconds = $nestedResidualProfileLookupSeconds
        pread_calls = $nestedResidualProfilePreadCalls
        pread_seconds = $nestedResidualProfilePreadSeconds
        reconstruct_calls = $nestedResidualProfileReconstructCalls
        reconstruct_blocks = $nestedResidualProfileReconstructBlocks
        reconstruct_seconds = $nestedResidualProfileReconstructSeconds
        verify_calls = $nestedResidualProfileVerifyCalls
        verify_bytes = $nestedResidualProfileVerifyBytes
        verify_seconds = $nestedResidualProfileVerifySeconds
        reuse_wait_calls = $nestedResidualProfileReuseWaitCalls
        reuse_wait_seconds = $nestedResidualProfileReuseWaitSeconds
        host_copy_calls = $nestedResidualProfileHostCopyCalls
        host_copy_seconds = $nestedResidualProfileHostCopySeconds
        h2d_enqueue_calls = $nestedResidualProfileH2DEnqueueCalls
        h2d_enqueue_seconds = $nestedResidualProfileH2DEnqueueSeconds
        h2d_sync_calls = $nestedResidualProfileH2DSyncCalls
        h2d_sync_seconds = $nestedResidualProfileH2DSyncSeconds
        route_begin_calls = $nestedResidualProfileRouteBeginCalls
        route_begin_seconds = $nestedResidualProfileRouteBeginSeconds
        route_submit_launch_calls = $nestedResidualProfileRouteBeginCalls
        route_submit_launch_seconds = $nestedResidualProfileRouteBeginSeconds
        route_resolve_sync_calls =
            $nestedResidualProfileRouteResolveSyncCalls
        route_resolve_sync_seconds =
            $nestedResidualProfileRouteResolveSyncSeconds
        route_ready_wait_calls = $nestedResidualProfileRouteReadyWaitCalls
        route_ready_wait_seconds = $nestedResidualProfileRouteReadyWaitSeconds
        packed_copy = $nestedResidualProfilePackedCopy
        split_fused = $nestedResidualProfileSplitFused
        verify = $nestedResidualProfileVerify
    }
    ds4_q1_0_expert_sidecar = $(if ($q1_0SidecarInfoAtStart) { $q1_0SidecarInfoAtStart.FullName } else { "" })
    ds4_q1_0_selected_load = $(if ($Q1_0ExpertSidecar -and $Q1_0SelectedLoad) { "1" } else { "" })
    ds4_q1_0_resident_arena = $(if ($Q1_0ExpertSidecar -and $Q1_0ResidentArena) { "1" } else { "" })
    ds4_q1_0_dual_arena = $(if ($Q1_0ExpertSidecar -and $Q1_0DualArena) { "1" } else { "" })
    ds4_q1_0_dual_sparse_companion = $(if ($Q1_0ExpertSidecar -and $Q1_0DualSparseCompanion) { "1" } else { "" })
    ds4_q1_0_mixed_cold_one = $(if ($Q1_0ExpertSidecar -and $Q1_0MixedColdOne) { "1" } else { "" })
    ds4_q1_0_pageable_overflow = $(if ($Q1_0ExpertSidecar -and $Q1_0PageableOverflow) { "1" } else { "" })
    ds4_q1_0_dynamic_arena_gb = $(if ($Q1_0ExpertSidecar -and $Q1_0ArenaGB -gt 0.0) { $Q1_0ArenaGB.ToString("0.###", [Globalization.CultureInfo]::InvariantCulture) } else { "" })
    ds4_q1_0_dynamic_promotion = $(if ($Q1_0ExpertSidecar -and $Q1_0DynamicPromotion) { "1" } else { "" })
    ds4_q1_0_promotion_ssd_wrap = $(if ($Q1_0PromotionSsdWrap) { "1" } else { "" })
    ds4_q1_0_iq2_pinned_gib = $(if ($Q1_0PromotionSsdWrap) { $Q1_0Iq2PinnedGiB.ToString("R", [Globalization.CultureInfo]::InvariantCulture) } else { "" })
    ds4_q1_0_profile = $(if ($Q1_0ExpertSidecar -and $Q1_0Profile) { "1" } else { "" })
    ds4_expert_recovery_trace = $(if ($ExpertRecoveryTrace) { "1" } else { "" })
    ds4_expert_recovery_trace_layer = $(if ($ExpertRecoveryTrace) { [string]$ExpertRecoveryTraceLayer } else { "" })
    ds4_expert_recovery_trace_expert = $(if ($ExpertRecoveryTrace) { [string]$ExpertRecoveryTraceExpert } else { "" })
    ds4_expert_recovery_trace_max_samples = $(if ($ExpertRecoveryTrace) { [string]$ExpertRecoveryTraceMaxSamples } else { "" })
    ds4_expert_recovery_trace_max_bytes = $(if ($ExpertRecoveryTrace) { [string]$ExpertRecoveryTraceByteBudget } else { "" })
    ds4_expert_recovery_trace_output_prefix = $(if ($ExpertRecoveryTrace) { $expertRecoveryTracePrefix } else { "" })
    ds4_q1_0_promotion_probation_slots = $(if ($Q1_0ExpertSidecar -and $Q1_0DynamicPromotion) { [string]$Q1_0PromotionProbationSlots } else { "" })
    ds4_q1_0_promotion_min_touches = $(if ($Q1_0ExpertSidecar -and $Q1_0DynamicPromotion) { [string]$Q1_0PromotionMinTouches } else { "" })
    ds4_q1_0_promotion_min_weight = $(if ($Q1_0ExpertSidecar -and $Q1_0DynamicPromotion) { $Q1_0PromotionMinWeight.ToString("R", [Globalization.CultureInfo]::InvariantCulture) } else { "" })
    ds4_q1_0_promotion_min_mass = $(if ($Q1_0ExpertSidecar -and $Q1_0DynamicPromotion) { $Q1_0PromotionMinMass.ToString("R", [Globalization.CultureInfo]::InvariantCulture) } else { "" })
    ds4_q1_0_promotion_request_budget = $(if ($Q1_0ExpertSidecar -and $Q1_0DynamicPromotion) { [string]$Q1_0PromotionRequestBudget } else { "" })
    ds4_q1_0_promotion_window_calls = $(if ($Q1_0ExpertSidecar -and $Q1_0DynamicPromotion) { [string]$Q1_0PromotionWindowCalls } else { "" })
    ds4_q1_0_promotion_window_budget = $(if ($Q1_0ExpertSidecar -and $Q1_0DynamicPromotion) { [string]$Q1_0PromotionWindowBudget } else { "" })
    ds4_q1_0_mixed_trace = $(if ($Q1_0ExpertSidecar -and $Q1_0MixedTrace) { "1" } else { "" })
    ds4_q1_0_layer_first = $(if ($Q1_0ExpertSidecar) { [string]$Q1_0LayerFirst } else { "" })
    ds4_q1_0_layer_last = $(if ($Q1_0ExpertSidecar) { [string]$Q1_0LayerLast } else { "" })
    q1_0_sidecar_enabled = [bool]$Q1_0ExpertSidecar
    q1_0_selected_load_requested = [bool]$Q1_0SelectedLoad
    q1_0_resident_arena_requested = [bool]$Q1_0ResidentArena
    q1_0_dual_arena_requested = [bool]$Q1_0DualArena
    q1_0_dual_sparse_companion_requested = [bool]$Q1_0DualSparseCompanion
    q1_0_mixed_cold_one_requested = [bool]$Q1_0MixedColdOne
    q1_0_snapshot_backing_requested = [bool]$Q1_0SnapshotBacking
    q1_0_pageable_overflow_requested = [bool]$Q1_0PageableOverflow
    q1_0_dynamic_arena_gb_requested = $Q1_0ArenaGB
    q1_0_dynamic_promotion_requested = [bool]$Q1_0DynamicPromotion
    q1_0_promotion_requested_config = [pscustomobject]@{
        probation_slots = $Q1_0PromotionProbationSlots
        min_touches = $Q1_0PromotionMinTouches
        min_weight = $Q1_0PromotionMinWeight
        min_mass = $Q1_0PromotionMinMass
        request_budget = $Q1_0PromotionRequestBudget
        window_calls = $Q1_0PromotionWindowCalls
        window_budget = $Q1_0PromotionWindowBudget
    }
    q1_0_promotion_probation_slots_requested = $Q1_0PromotionProbationSlots
    q1_0_promotion_min_touches_requested = $Q1_0PromotionMinTouches
    q1_0_promotion_min_weight_requested = $Q1_0PromotionMinWeight
    q1_0_promotion_min_mass_requested = $Q1_0PromotionMinMass
    q1_0_promotion_request_budget_requested = $Q1_0PromotionRequestBudget
    q1_0_promotion_window_calls_requested = $Q1_0PromotionWindowCalls
    q1_0_promotion_window_budget_requested = $Q1_0PromotionWindowBudget
    q1_0_pure_resident_requested = [bool]$Q1_0PureResident
    q1_0_snapshot_entries_expected = $ExpectedQ1_0SnapshotEntries
    q1_0_resident_entries_expected = $ExpectedQ1_0ResidentEntries
    q1_0_mixed_trace_requested = [bool]$Q1_0MixedTrace
    q1_0_mixed_resolver_required = $q1_0MixedResolverRequired
    q1_0_mixed_expected_router = $q1_0MixedExpectedRouter
    q1_0_dual_arena_runtime_observed = $q1_0DualArenaRuntimeObserved
    q1_0_dual_sparse_runtime_observed = $q1_0DualSparseRuntimeObserved
    q1_0_dual_sparse_entries = $q1_0DualSparseEntries
    q1_0_dual_sparse_bytes = $q1_0DualSparseBytes
    q1_0_dual_sparse_stage_seconds = $q1_0DualSparseStageSeconds
    q1_0_dual_sparse_publications = $q1_0DualSparsePublications
    q1_0_dual_sparse_failures = $q1_0DualSparseFailures
    q1_0_layer_first_requested = $(if ($Q1_0ExpertSidecar) { $Q1_0LayerFirst } else { 0 })
    q1_0_layer_last_requested = $(if ($Q1_0ExpertSidecar) { $Q1_0LayerLast } else { 0 })
    q1_0_sidecar = $(if ($q1_0SidecarInfoAtStart) { $q1_0SidecarInfoAtStart.FullName } else { "" })
    q1_0_sidecar_bytes = $(if ($q1_0SidecarInfoAtStart) { [UInt64]$q1_0SidecarInfoAtStart.Length } else { [UInt64]0 })
    q1_0_sidecar_last_write_utc = $(if ($q1_0SidecarInfoAtStart) { $q1_0SidecarInfoAtStart.LastWriteTimeUtc.ToString("o") } else { "" })
    q1_0_sidecar_expected_size_bytes = $ExpectedQ1_0ExpertSidecarBytes
    q1_0_sidecar_expected_sha256 = $(if ($ExpectedQ1_0ExpertSidecarSHA256) { $ExpectedQ1_0ExpertSidecarSHA256.ToLowerInvariant() } else { "" })
    q1_0_sidecar_sha256 = $q1_0SidecarHashAtStart
    q1_0_sidecar_hash_method = $q1_0SidecarHashMethod
    q1_0_sidecar_receipt_path = $q1_0SidecarReceiptPath
    q1_0_sidecar_receipt_sha256 = $q1_0SidecarReceiptHashAtStart
    q1_0_sidecar_provenance_verified = $q1_0SidecarProvenanceVerified
    q1_0_sidecar_receipt_reuse_requested = [bool]$ReuseVerifiedQ1_0Receipt
    q1_0_sidecar_runtime_observed = $q1_0SidecarRuntimeObserved
    q1_0_sidecar_route_calls = $q1_0SidecarCalls
    q1_0_sidecar_route_slots = $q1_0SidecarSlots
    q1_0_sidecar_selected_loads = $q1_0SidecarSelectedLoads
    q1_0_sidecar_failures = $q1_0SidecarFailures
    q1_0_resident_mode = $q1_0ResidentMode
    q1_0_resident_hits = $q1_0ResidentHits
    q1_0_resident_misses = $q1_0ResidentMisses
    q1_0_resident_h2d_bytes = $q1_0ResidentH2DBytes
    q1_0_direct_pread_fallbacks = $q1_0DirectPreadFallbacks
    q1_0_direct_pread_bytes = $q1_0DirectPreadBytes
    q1_0_bootstrap_entries = $q1_0BootstrapEntries
    q1_0_bootstrap_pinned_bytes = $q1_0BootstrapPinnedBytes
    q1_0_bootstrap_pageable_bytes = $q1_0BootstrapPageableBytes
    q1_0_bootstrap_pinned_slots = $q1_0BootstrapPinnedSlots
    q1_0_bootstrap_pageable_slots = $q1_0BootstrapPageableSlots
    q1_0_bootstrap_total_slots = $q1_0BootstrapTotalSlots
    q1_0_bootstrap_total_bytes = $q1_0BootstrapTotalBytes
    q1_0_bootstrap_layer_first = $q1_0BootstrapLayerFirst
    q1_0_bootstrap_layer_last = $q1_0BootstrapLayerLast
    q1_0_source_unlock_observed = $q1_0SourceUnlockObserved
    q1_0_source_unlock_result = $q1_0SourceUnlockResult
    q1_0_source_unlock_windows = $q1_0SourceUnlockWindows
    q1_0_source_unlock_page_size = $q1_0SourceUnlockPageSize
    q1_0_source_unlock_page_aligned = $q1_0SourceUnlockPageAligned
    q1_0_source_unlock_destination_unchanged =
        $q1_0SourceUnlockDestinationUnchanged
    q1_0_source_unlock_layers = $q1_0SourceUnlockLayers
    q1_0_source_unlock_ranges_attempted =
        $q1_0SourceUnlockRangesAttempted
    q1_0_source_unlock_bytes_attempted = $q1_0SourceUnlockBytesAttempted
    q1_0_source_unlock_calls = $q1_0SourceUnlockCalls
    q1_0_source_unlock_success = $q1_0SourceUnlockSuccess
    q1_0_source_unlock_not_locked = $q1_0SourceUnlockNotLocked
    q1_0_source_unlock_failed = $q1_0SourceUnlockFailed
    q1_0_source_unlock_classification = $q1_0SourceUnlockClassification
    q1_0_source_unlock_seconds = $q1_0SourceUnlockSeconds
    q1_0_source_unlock_available_before =
        $q1_0SourceUnlockAvailableBefore
    q1_0_source_unlock_available_after = $q1_0SourceUnlockAvailableAfter
    q1_0_source_unlock_working_set_before =
        $q1_0SourceUnlockWorkingSetBefore
    q1_0_source_unlock_working_set_after =
        $q1_0SourceUnlockWorkingSetAfter
    q1_0_source_unlock_page_fault_before =
        $q1_0SourceUnlockPageFaultBefore
    q1_0_source_unlock_page_fault_after =
        $q1_0SourceUnlockPageFaultAfter
    q1_0_source_unlock_read_transfer_before =
        $q1_0SourceUnlockReadTransferBefore
    q1_0_source_unlock_read_transfer_after =
        $q1_0SourceUnlockReadTransferAfter
    q1_0_source_unlock_last_error = $q1_0SourceUnlockLastError
    q1_0_mixed = $q1_0MixedTelemetry
    q1_0_mixed_route_trace = $q1_0MixedRouteTraceTelemetry
    q1_0_mixed_iq2_routes = $q1_0MixedIq2Routes
    q1_0_mixed_accounted_routes = $q1_0MixedAccountedRoutes
    q1_0_profile_requested = [bool]$Q1_0Profile
    q1_0_profile = $q1_0ProfileTelemetry
    q1_0_promotion_ssd_wrap_requested = [bool]$Q1_0PromotionSsdWrap
    q1_0_iq2_pinned_gib_requested = $Q1_0Iq2PinnedGiB
    q1_0_ssd_wrap = $q1_0SsdWrapTelemetry
    expert_recovery_trace_requested = [bool]$ExpertRecoveryTrace
    expert_recovery_trace = $expertRecoveryTraceArtifact
    expert_recovery_trace_performance_eligible = $false
    expert_recovery_trace_quality_eligible = $false
    q1_0_runtime_contract_valid = $q1_0RuntimeContractValid
    q1_0_fail_closed_checks_passed = $q1_0RuntimeContractValid
    q1_0_fail_closed_observed = $q1_0FailClosedObserved
    q1_0_structural_smoke_eligible = $q1_0StructuralSmokeEligible
    q1_0_performance_eligible = $false
    q1_0_quality_eligible = $false
    iq1_s_sidecar = $(if ($iq1SSidecarInfoAtStart) { $iq1SSidecarInfoAtStart.FullName } else { "" })
    iq1_s_sidecar_bytes = $(if ($iq1SSidecarInfoAtStart) { [UInt64]$iq1SSidecarInfoAtStart.Length } else { [UInt64]0 })
    iq1_s_sidecar_last_write_utc = $(if ($iq1SSidecarInfoAtStart) { $iq1SSidecarInfoAtStart.LastWriteTimeUtc.ToString("o") } else { "" })
    iq1_s_sidecar_expected_sha256 = $ExpectedIq1SExpertSidecarSHA256.ToLowerInvariant()
    iq1_s_sidecar_sha256 = $iq1SSidecarHashAtStart
    iq1_s_sidecar_hash_method = $iq1SSidecarHashMethod
    iq1_s_sidecar_receipt_path = $iq1SSidecarReceiptPath
    iq1_s_sidecar_receipt_sha256 = $iq1SSidecarReceiptHashAtStart
    iq1_s_sidecar_source = $(if ($iq1SSidecarReceiptAtStart) { [string]$iq1SSidecarReceiptAtStart.source } else { "" })
    iq1_s_sidecar_quantization_layout = $(if ($iq1SSidecarReceiptAtStart) { [string]$iq1SSidecarReceiptAtStart.quantization_layout } else { "" })
    iq1_s_sidecar_imatrix_provenance = $(if ($iq1SSidecarReceiptAtStart) { [string]$iq1SSidecarReceiptAtStart.imatrix_provenance } else { "" })
    iq1_s_sidecar_runtime_observed = $iq1SSidecarRuntimeObserved
    iq1_s_sidecar_route_calls = $iq1SSidecarCalls
    iq1_s_sidecar_route_slots = $iq1SSidecarSlots
    iq1_s_sidecar_selected_loads = $iq1SSidecarSelectedLoads
    iq1_s_sidecar_failures = $iq1SSidecarFailures
    iq1_s_ram_cache_requested_gib = $Iq1SRamCacheGiB
    iq1_s_ram_cache_pageable_requested = [bool]$Iq1SRamCachePageable
    iq1_s_ram_cache_preload_all_requested = [bool]$Iq1SRamCachePreloadAll
    iq1_s_ram_cache_runtime_observed = $iq1SRamCacheRuntimeObserved
    iq1_s_ram_cache_requested_bytes = $iq1SRamCacheRequestedBytes
    iq1_s_ram_cache_allocated_bytes = $iq1SRamCacheAllocatedBytes
    iq1_s_ram_cache_capacity = $iq1SRamCacheCapacity
    iq1_s_ram_cache_count = $iq1SRamCacheCount
    iq1_s_ram_cache_slot_bytes = $iq1SRamCacheSlotBytes
    iq1_s_ram_cache_hits = $iq1SRamCacheHits
    iq1_s_ram_cache_misses = $iq1SRamCacheMisses
    iq1_s_ram_cache_evictions = $iq1SRamCacheEvictions
    iq1_s_ram_cache_ssd_bytes = $iq1SRamCacheSsdBytes
    iq1_s_ram_cache_h2d_bytes = $iq1SRamCacheH2dBytes
    iq1_s_ram_cache_failures = $iq1SRamCacheFailures
    iq1_s_ram_cache_hit_rate = $iq1SRamCacheHitRate
    iq1_s_ram_cache_ssd_avoided_bytes = $iq1SRamCacheSsdAvoidedBytes
    iq1_s_ram_cache_preload_frozen = $iq1SRamCachePreloadFrozen
    iq1_s_ram_cache_preload_layers = $iq1SRamCachePreloadLayers
    iq1_s_ram_cache_preload_entries = $iq1SRamCachePreloadEntries
    iq1_s_ram_cache_preload_ssd_bytes = $iq1SRamCachePreloadSsdBytes
    iq1_s_ram_cache_preload_read_calls = $iq1SRamCachePreloadReadCalls
    iq1_s_ram_cache_preload_ms = $iq1SRamCachePreloadMs
    iq1_s_vram_cache_per_layer_requested = $Iq1SVramCachePerLayer
    iq1_s_vram_cache_runtime_observed = $iq1SVramCacheRuntimeObserved
    iq1_s_vram_cache_capacity = $iq1SVramCacheCapacity
    iq1_s_vram_cache_count = $iq1SVramCacheCount
    iq1_s_vram_cache_slot_bytes = $iq1SVramCacheSlotBytes
    iq1_s_vram_cache_hits = $iq1SVramCacheHits
    iq1_s_vram_cache_misses = $iq1SVramCacheMisses
    iq1_s_vram_cache_evictions = $iq1SVramCacheEvictions
    iq1_s_vram_cache_h2d_bytes = $iq1SVramCacheH2dBytes
    iq1_s_vram_cache_failures = $iq1SVramCacheFailures
    iq1_s_mixed_cold_one = [bool]$Iq1SMixedColdOne
    iq1_s_mixed_runtime_observed = $iq1MixedRuntimeObserved
    iq1_s_mixed_calls = $iq1MixedCalls
    iq1_s_mixed_hot_main = $iq1MixedHotMain
    iq1_s_mixed_cold_iq1 = $iq1MixedColdIq1
    iq1_s_mixed_primary_cold_avoided = $iq1MixedPrimaryColdAvoided
    iq1_s_mixed_joins = $iq1MixedJoins
    iq1_s_mixed_failures = $iq1MixedFailures
    iq1_s_mixed_last_layer = $iq1MixedLastLayer
    iq1_s_mixed_last_slot = $iq1MixedLastSlot
    iq1_s_mixed_last_expert = $iq1MixedLastExpert
    iq1_s_mixed_gpu_plan_requested = [bool]$Iq1SMixedGpuPlan
    iq1_s_mixed_gpu_plan_runtime_observed = $iq1MixedGpuPlanRuntimeObserved
    iq1_s_mixed_gpu_plan_calls = $iq1MixedGpuPlanCalls
    iq1_s_mixed_gpu_plan_wait_ms = $iq1MixedGpuPlanWaitMs
    iq1_s_mixed_gpu_plan_failures = $iq1MixedGpuPlanFailures
    iq1_promotion_requested = [bool]$quantPromotionRequested
    iq1_promotion_kind = $(if ($Q1_0DynamicPromotion) { "q1_0" } elseif ($Iq1Promotion) { "iq1_s" } else { "off" })
    iq1_promotion_probation_slots_requested = $promotionProbationSlotsExpected
    iq1_promotion_requested_config = [pscustomobject]@{
        probation_slots = $promotionProbationSlotsExpected
        min_touches = $promotionMinTouchesExpected
        min_weight = $promotionMinWeightExpected
        min_mass = $promotionMinMassExpected
        request_budget = $promotionRequestBudgetExpected
        window_calls = $promotionWindowCallsExpected
        window_budget = $promotionWindowBudgetExpected
    }
    iq1_promotion_min_touches_requested = $promotionMinTouchesExpected
    iq1_promotion_min_weight_requested = $promotionMinWeightExpected
    iq1_promotion_min_mass_requested = $promotionMinMassExpected
    iq1_promotion_request_budget_requested = $promotionRequestBudgetExpected
    iq1_promotion_window_calls_requested = $promotionWindowCallsExpected
    iq1_promotion_window_budget_requested = $promotionWindowBudgetExpected
    iq1_promotion_runtime_observed = $iq1PromotionRuntimeObserved
    iq1_promotion_line_count = $iq1PromotionLineCount
    iq1_promotion_requested_slots = $iq1PromotionRequestedSlots
    iq1_promotion_reserved_slots = $iq1PromotionReservedSlots
    iq1_promotion_snapshot_evictions = $iq1PromotionSnapshotEvictions
    iq1_promotion_min_touches = $iq1PromotionObservedMinTouches
    iq1_promotion_min_weight = $iq1PromotionObservedMinWeight
    iq1_promotion_min_mass = $iq1PromotionObservedMinMass
    iq1_promotion_request_budget = $iq1PromotionObservedRequestBudget
    iq1_promotion_window_calls = $iq1PromotionObservedWindowCalls
    iq1_promotion_window_budget = $iq1PromotionObservedWindowBudget
    iq1_promotion_cold_observed = $iq1PromotionColdObserved
    iq1_promotion_cold_existing_2bit = $iq1PromotionColdExisting2Bit
    iq1_promotion_cold_to_2bit_ram = $iq1PromotionColdTo2BitRam
    iq1_promotion_cold_gate_candidates = $iq1PromotionColdGateCandidates
    iq1_promotion_weight_ge_001 = $iq1PromotionWeightGe001
    iq1_promotion_weight_ge_002 = $iq1PromotionWeightGe002
    iq1_promotion_weight_ge_005 = $iq1PromotionWeightGe005
    iq1_promotion_weight_ge_010 = $iq1PromotionWeightGe010
    iq1_promotion_skips_touches = $iq1PromotionSkipsTouches
    iq1_promotion_skips_weight = $iq1PromotionSkipsWeight
    iq1_promotion_skips_mass = $iq1PromotionSkipsMass
    iq1_promotion_skips_request_budget = $iq1PromotionSkipsRequestBudget
    iq1_promotion_skips_window_budget = $iq1PromotionSkipsWindowBudget
    iq1_promotion_probation_ram_hits = $iq1PromotionProbationRamHits
    iq1_promotion_next_token_waits = $iq1PromotionNextTokenWaits
    iq1_promotion_2bit_ssd_bytes = $iq1Promotion2BitSsdBytes
    iq1_promotion_2bit_ssd_seconds = $iq1Promotion2BitSsdSeconds
    iq1_promotion_2bit_ssd_bytes_per_second = $iq1Promotion2BitSsdBytesPerSecond
    iq1_promotion_direct_ssd_to_vram_rejected = $iq1PromotionDirectSsdToVramRejected
    iq1_promotion_probation_backing_reclaims = $iq1PromotionProbationBackingReclaims
    iq1_promotion_q1_0_observed = $iq1PromotionQ1_0Observed
    iq1_promotion_q1_0_stage_attempts = $iq1PromotionQ1_0StageAttempts
    iq1_promotion_q1_0_stage_successes = $iq1PromotionQ1_0StageSuccesses
    iq1_promotion_q1_0_next_call_guards = $iq1PromotionQ1_0NextCallGuards
    iq1_promotion_q1_0_record_rejects = $iq1PromotionQ1_0RecordRejects
    iq1_promotion_q1_0_record_attempts = $iq1PromotionQ1_0RecordAttempts
    iq1_promotion_q1_0_record_successes = $iq1PromotionQ1_0RecordSuccesses
    iq1_promotion_q1_0_record_failures = $iq1PromotionQ1_0RecordFailures
    q1_0_promotion_records_observed = [bool]($q1_0PromotionRecordCount -gt 0)
    q1_0_promotion_records_path = $q1_0PromotionRecordArtifactPath
    q1_0_promotion_records_sha256 = $q1_0PromotionRecordArtifactSHA256
    q1_0_promotion_records_count = $q1_0PromotionRecordCount
    q1_0_promotion_records_physical_line_count =
        $q1_0PromotionRecordPhysicalLineCount
    q1_0_promotion_record_attempt_count = $q1_0PromotionRecordAttemptCount
    q1_0_promotion_record_success_count = $q1_0PromotionRecordSuccessCount
    q1_0_promotion_record_reject_count = $q1_0PromotionRecordRejectCount
    q1_0_promotion_record_failure_count = $q1_0PromotionRecordFailureCount
    q1_0_promotion_record_bounded_exception_limit =
        $q1_0PromotionRecordBoundedExceptionLimit
    q1_0_promotion_telemetry_record_limit =
        $q1_0PromotionTelemetryRecordLimit
    iq1_promotion_failures = $iq1PromotionFailures
    iq1_promotion_requests = $iq1PromotionRows
    iq1_s_profile_requested = [bool]$Iq1SProfile
    iq1_s_no_main_sync_requested = [bool]$Iq1SNoMainSync
    iq1_s_packed_h2d_requested = [bool]$Iq1SPackedH2D
    iq1_s_profile_ssd_read_calls = $iq1ProfileSsdReadCalls
    iq1_s_profile_ssd_read_ms = $iq1ProfileSsdReadMs
    iq1_s_profile_h2d_batches = $iq1ProfileH2dBatches
    iq1_s_profile_h2d_copies = $iq1ProfileH2dCopies
    iq1_s_profile_h2d_enqueue_ms = $iq1ProfileH2dEnqueueMs
    iq1_s_profile_h2d_syncs = $iq1ProfileH2dSyncs
    iq1_s_profile_h2d_sync_ms = $iq1ProfileH2dSyncMs
    iq1_s_mixed_profile_calls = $iq1MixedProfileCalls
    iq1_s_mixed_profile_router_d2h_ms = $iq1MixedProfileRouterD2hMs
    iq1_s_mixed_profile_metadata_h2d_ms = $iq1MixedProfileMetadataH2dMs
    iq1_s_mixed_profile_main_submit_ms = $iq1MixedProfileMainSubmitMs
    iq1_s_mixed_profile_main_sync_ms = $iq1MixedProfileMainSyncMs
    iq1_s_mixed_profile_cold_submit_ms = $iq1MixedProfileColdSubmitMs
    iq1_s_mixed_profile_join_submit_ms = $iq1MixedProfileJoinSubmitMs
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
    non_identical_repeat_outputs_allowed = [bool]$AllowNonIdenticalRepeatOutputs
    requested_stop_sequence = $StopSequence
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
    arena_wrap_trust_worker_checksum_requested = [bool]$ArenaWrapTrustWorkerChecksum
    arena_wrap_schedule_requested = if ($ArenaWrapSourceParts) { "source-parts" } else { "expert-major" }
    arena_wrap_source_requested = if ($ArenaWrapSequentialFile) { "sequential-file" } elseif ($ArenaWrapRandomFile) { "random-file" } else { "mmap" }
    arena_wrap_sequential_file_requested = [bool]$ArenaWrapSequentialFile
    arena_wrap_random_file_requested = [bool]$ArenaWrapRandomFile
    arena_wrap_sequential_workers_requested = $ArenaWrapSequentialWorkers
    arena_wrap_file_qd_requested = $ArenaWrapFileQD
    arena_wrap_part_profile_requested = [bool]$ArenaWrapPartProfile
    arena_wrap_slow_part_ms_requested = $ArenaWrapSlowPartMs
    arena_wrap_trim_between_phases_requested = [bool]$ArenaWrapTrimBetweenPhases
    arena_wrap_profile_observed = $arenaWrapProfileObserved
    arena_wrap_profile_result = $arenaWrapProfileResult
    arena_wrap_schedule_observed = $arenaWrapScheduleObserved
    arena_wrap_source_observed = $arenaWrapSourceObserved
    arena_wrap_checksum_observed = $arenaWrapChecksumObserved
    arena_wrap_profile_loads = $arenaWrapProfileLoads
    arena_wrap_profile_workers = $arenaWrapProfileWorkers
    arena_wrap_profile_begin_seconds = $arenaWrapProfileBeginSeconds
    arena_wrap_profile_copy_checksum_seconds = $arenaWrapProfileCopyChecksumSeconds
    arena_wrap_profile_finish_seconds = $arenaWrapProfileFinishSeconds
    arena_wrap_profile_publish_seconds = $arenaWrapProfilePublishSeconds
    arena_wrap_profile_total_seconds = $arenaWrapProfileTotalSeconds
    arena_wrap_source_parts_copy_seconds = $arenaWrapSourcePartsCopySeconds
    arena_wrap_source_parts_checksum_seconds = $arenaWrapSourcePartsChecksumSeconds
    arena_wrap_part_count = $arenaWrapPartCount
    arena_wrap_copy_workers = $arenaWrapCopyWorkers
    arena_wrap_checksum_workers = $arenaWrapChecksumWorkers
    arena_wrap_file_qd_requested_observed = $arenaWrapFileQDRequestedObserved
    arena_wrap_file_qd_observed = $arenaWrapFileQDObserved
    arena_wrap_file_submits = $arenaWrapFileSubmits
    arena_wrap_file_completions = $arenaWrapFileCompletions
    arena_wrap_file_failures = $arenaWrapFileFailures
    arena_wrap_part_profile_observed = $arenaWrapPartProfileObserved
    arena_wrap_part_profile_result = $arenaWrapPartProfileResult
    arena_wrap_layout_profile_requested = [bool]$ArenaWrapLayoutProfile
    arena_wrap_layout_profile_observed = $arenaWrapLayoutProfileObserved
    arena_wrap_layout_profile = $arenaWrapLayoutProfileRows
    arena_wrap_part_profile_phases = $arenaWrapPartProfilePhases
    arena_wrap_part_profile_workers = $arenaWrapPartProfileWorkers
    arena_wrap_part_profile_parts = $arenaWrapPartProfileParts
    arena_wrap_part_profile_bytes = $arenaWrapPartProfileBytes
    arena_wrap_part_profile_memcpy_sum_seconds = $arenaWrapPartProfileMemcpySumSeconds
    arena_wrap_part_profile_main_worker_seconds = $arenaWrapPartProfileMainWorkerSeconds
    arena_wrap_part_profile_join_seconds = $arenaWrapPartProfileJoinSeconds
    arena_wrap_part_profile_phase_worker_active_min_seconds = $arenaWrapPartProfileWorkerActiveMinSeconds
    arena_wrap_part_profile_phase_worker_active_max_seconds = $arenaWrapPartProfileWorkerActiveMaxSeconds
    arena_wrap_part_profile_phase_worker_parts_min = $arenaWrapPartProfileWorkerPartsMin
    arena_wrap_part_profile_phase_worker_parts_max = $arenaWrapPartProfileWorkerPartsMax
    arena_wrap_part_profile_slow_threshold_ms = $arenaWrapPartProfileSlowThresholdMs
    arena_wrap_part_profile_slow_parts = $arenaWrapPartProfileSlowParts
    arena_wrap_part_profile_max_part_ms = $arenaWrapPartProfileMaxPartMs
    arena_wrap_part_profile_max_part_bytes = $arenaWrapPartProfileMaxPartBytes
    arena_wrap_part_profile_max_part_load = $arenaWrapPartProfileMaxPartLoad
    arena_wrap_part_profile_max_part_cursor = $arenaWrapPartProfileMaxPartCursor
    arena_wrap_part_profile_max_part_kind = $arenaWrapPartProfileMaxPartKind
    arena_wrap_part_profile_max_part_source = $arenaWrapPartProfileMaxPartSource
    arena_wrap_trim_observed = $arenaWrapTrimObserved
    arena_wrap_trim_result = $arenaWrapTrimResult
    arena_wrap_trim_calls = $arenaWrapTrimCalls
    arena_wrap_trim_succeeded = $arenaWrapTrimSucceeded
    arena_wrap_trim_failed = $arenaWrapTrimFailed
    arena_wrap_trim_seconds = $arenaWrapTrimSeconds
    arena_wrap_trim_last_error = $arenaWrapTrimLastError
    arena_wrap_unlock_source_ranges_requested = [bool]$ArenaWrapUnlockSourceRanges
    arena_wrap_unlock_wave_gib_requested = $ArenaWrapUnlockWaveGiB
    arena_wrap_unlock_source_ranges_observed = $arenaWrapUnlockObserved
    arena_wrap_unlock_source_ranges = $arenaWrapUnlockRows
    arena_wrap_unlock_source_ranges_summary_observed = $arenaWrapUnlockSummaryObserved
    arena_wrap_unlock_source_ranges_summary_result = $arenaWrapUnlockSummaryResult
    arena_wrap_unlock_source_ranges_summary_phases = $arenaWrapUnlockSummaryPhases
    arena_wrap_unlock_source_ranges_summary_waves = $arenaWrapUnlockSummaryWaves
    arena_wrap_unlock_wave_gib_observed = $arenaWrapUnlockSummaryWaveGiB
    arena_wrap_unlock_source_ranges_summary_max_wave_bytes = $arenaWrapUnlockSummaryMaxWaveBytes
    arena_wrap_unlock_source_ranges_summary_parts = $arenaWrapUnlockSummaryParts
    arena_wrap_unlock_source_ranges_summary_ranges = $arenaWrapUnlockSummaryRanges
    arena_wrap_unlock_source_ranges_summary_bytes_requested = $arenaWrapUnlockSummaryBytesRequested
    arena_wrap_unlock_source_ranges_summary_calls = $arenaWrapUnlockSummaryCalls
    arena_wrap_unlock_source_ranges_summary_true = $arenaWrapUnlockSummaryTrue
    arena_wrap_unlock_source_ranges_summary_error_not_locked = $arenaWrapUnlockSummaryErrorNotLocked
    arena_wrap_unlock_source_ranges_summary_failed = $arenaWrapUnlockSummaryFailed
    arena_wrap_unlock_source_ranges_summary_seconds = $arenaWrapUnlockSummarySeconds
    prefill_mass_observe_requested = [bool]$PrefillMassObserve
    prefill_mass_wrap_requested = [bool]$PrefillMassWrap
    request_count_expected = $requestCountExpected
    prefill_mass_armed_event_count = $prefillMassArmedEventCount
    prefill_mass_finalize_event_count = $prefillMassFinalizeEventCount
    prefill_mass_decode_event_count = $prefillMassDecodeEventCount
    compose_prefill_mass_tiering_requested = [bool]$ComposePrefillMassTiering
    compose_prefill_mass_open_router_requested = [bool]$ComposePrefillMassOpenRouter
    compose_prefill_mass_reserve_slots_requested = $ComposePrefillMassReserveSlots
    prefill_mass_layer_full_every_requested = $PrefillMassLayerFullEvery
    prefill_mass_layer_full_phase_requested = $PrefillMassLayerFullPhase
    prefill_vram_seed_requested_per_layer = $PrefillVramSeedPerLayer
    prefill_vram_seed_requested_total = $PrefillVramSeedTotal
    prefill_vram_seed_floor_per_layer_requested = $PrefillVramSeedFloorPerLayer
    prefill_vram_seed_global_observed = $prefillVramSeedGlobalObserved
    prefill_vram_seed_global_requested_observed = $prefillVramSeedGlobalRequestedObserved
    prefill_vram_seed_global_floor_observed = $prefillVramSeedGlobalFloorObserved
    prefill_vram_seed_observed = $prefillVramSeedObserved
    prefill_vram_seed_line_count = $prefillVramSeedLineCount
    prefill_vram_seed_result = $prefillVramSeedResult
    prefill_vram_seed_reason = $prefillVramSeedReason
    prefill_vram_seed_requested_per_layer_observed = $prefillVramSeedRequestedObserved
    prefill_vram_seed_layers = $prefillVramSeedLayers
    prefill_vram_seed_entries = $prefillVramSeedEntries
    prefill_vram_seed_bytes = $prefillVramSeedBytes
    prefill_vram_seed_seconds = $prefillVramSeedSeconds
    prefill_vram_seed_failures = $prefillVramSeedFailures
    prefill_vram_seed_prior_mass = $prefillVramSeedPriorMass
    prefill_vram_seed_semantics = $prefillVramSeedSemantics
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
    embedded_bake_mask_allowed = [bool]$AllowEmbeddedBakeMask
    expected_embedded_bake_mask_sha256 = $(if ($ExpectedEmbeddedBakeMaskSHA256) { $ExpectedEmbeddedBakeMaskSHA256.ToLowerInvariant() } else { "" })
    embedded_bake_mask_observed = [bool]$embeddedBakeMaskObserved
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
    prefill_mass_compose_candidate_fnv1a64 = $prefillMassComposeCandidateFNV1A64
    prefill_mass_compose_sparse_skipped_ranked = $prefillMassComposeSparseSkippedRanked
    prefill_mass_compose_mask_observed = $prefillMassComposeMaskObserved
    prefill_mass_compose_mask_event_count = $prefillMassComposeMaskEventCount
    prefill_mass_compose_mask_failed_count = $prefillMassComposeMaskFailedCount
    prefill_mass_compose_mask_base = $prefillMassComposeMaskBase
    prefill_mass_compose_mask_existing_layers = $prefillMassComposeMaskExistingLayers
    prefill_mass_compose_mask_semantics = $prefillMassComposeMaskSemantics
    prefill_mass_compose_mask_applied_count = $prefillMassComposeMaskAppliedCount
    prefill_mass_compose_mask_restore_count = $prefillMassComposeMaskRestoreCount
    prefill_mass_layer_stripe_observed = $prefillMassLayerStripeObserved
    prefill_mass_layer_stripe_event_count = $prefillMassLayerStripeEventCount
    prefill_mass_layer_stripe_failed_count = $prefillMassLayerStripeFailedCount
    prefill_mass_layer_stripe_result = $prefillMassLayerStripeResult
    prefill_mass_layer_stripe_reason = $prefillMassLayerStripeReason
    prefill_mass_layer_stripe_stride = $prefillMassLayerStripeStride
    prefill_mass_layer_stripe_phase = $prefillMassLayerStripePhase
    prefill_mass_layer_stripe_routed_layers = $prefillMassLayerStripeRoutedLayers
    prefill_mass_layer_stripe_full_layers = $prefillMassLayerStripeFullLayers
    prefill_mass_layer_stripe_partial_layers = $prefillMassLayerStripePartialLayers
    prefill_mass_layer_stripe_full_keep = $prefillMassLayerStripeFullKeep
    prefill_mass_layer_stripe_partial_keep_min = $prefillMassLayerStripePartialKeepMin
    prefill_mass_layer_stripe_partial_keep_max = $prefillMassLayerStripePartialKeepMax
    prefill_mass_layer_stripe_routed_candidate = $prefillMassLayerStripeRoutedCandidate
    prefill_mass_layer_stripe_total_candidate = $prefillMassLayerStripeTotalCandidate
    prefill_mass_layer_stripe_capacity = $prefillMassLayerStripeCapacity
    prefill_mass_layer_stripe_semantics = $prefillMassLayerStripeSemantics
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
    prefill_mass_residency_semantics = $(if ($ComposePrefillMassOpenRouter) { "ranked prefill candidate published transactionally into pinned RAM; router unbiased; request-scoped open mask" } elseif ($PrefillMassLayerFullEvery -gt 0) { "budget-preserving per-layer mass profile published transactionally into pinned RAM; periodic routed layers remain full; router unbiased; request-scoped closed mask" } elseif ($PrefillMassWrap) { "ranked prefill candidate published transactionally into pinned RAM; router and mask unchanged" } else { "observe-only; no router, mask, arena publication, or residency changes" })
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
    dynamic_arena_min_available_gib_requested = $DynamicArenaMinAvailableGiB
    dynamic_arena_cap_observed = $arenaCapObserved
    dynamic_arena_cap_requested_gib = $arenaCapRequestedGiB
    dynamic_arena_cap_min_available_gib = $arenaCapMinAvailableGiB
    dynamic_arena_cap_available_before_gib = $arenaCapAvailableBeforeGiB
    dynamic_arena_cap_requested_bytes = $arenaCapRequestedBytes
    dynamic_arena_cap_requested_slots = $arenaCapRequestedSlots
    dynamic_arena_cap_chosen_bytes = $arenaCapChosenBytes
    dynamic_arena_cap_chosen_slots = $arenaCapChosenSlots
    dynamic_arena_cap_pageable_bytes = $arenaCapPageableBytes
    dynamic_arena_cap_pageable_slots = $arenaCapPageableSlots
    dynamic_arena_cap_total_slots = $arenaCapTotalSlots
    dynamic_arena_cap_capped = $arenaCapCapped
    dynamic_arena_cap_result = $arenaCapResult
    dynamic_arena_cap_reason = $arenaCapReason
    dynamic_arena_allocated_bytes = $arenaAllocatedBytes
    dynamic_arena_allocated_pageable_bytes = $arenaAllocatedPageableBytes
    dynamic_arena_allocated_total_bytes = $arenaAllocatedTotalBytes
    dynamic_arena_allocated_slots = $arenaAllocatedSlots
    dynamic_arena_allocated_pinned_slots = $arenaAllocatedPinnedSlots
    dynamic_arena_allocated_pageable_slots = $arenaAllocatedPageableSlots
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
    dynamic_arena_occupancy_ratio = if ($arenaAllocatedTotalBytes -gt 0) { ([double]$arenaReportedResident * [double]$arenaSlotBytes) / [double]$arenaAllocatedTotalBytes } else { $null }
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
    dynamic_arena_final_pinned_hits = $arenaFinalPinnedHits
    dynamic_arena_final_pageable_hits = $arenaFinalPageableHits
    dynamic_arena_final_misses = $arenaFinalMisses
    dynamic_arena_final_fatal = $arenaFinalFatal
    dynamic_arena_hit_rate = if (($arenaFinalHits + $arenaFinalMisses) -gt 0) { [double]$arenaFinalHits / [double]($arenaFinalHits + $arenaFinalMisses) } else { $null }
    dynamic_arena_miss_rate = if (($arenaFinalHits + $arenaFinalMisses) -gt 0) { [double]$arenaFinalMisses / [double]($arenaFinalHits + $arenaFinalMisses) } else { $null }
    dynamic_arena_h2d_uploaded_gib = $arenaFinalUploadedGiB
    dynamic_arena_pinned_h2d_uploaded_gib = $arenaFinalPinnedUploadedGiB
    dynamic_arena_pageable_h2d_uploaded_gib = $arenaFinalPageableUploadedGiB
    dynamic_arena_h2d_uploaded_semantics = "Pinned/pageable host snapshot to compact VRAM selected-expert tensors; not SSD or mmap read traffic"
    no_selected_load = [bool]$NoSelectedLoad
    diagnostics = [bool]$Diagnostics
    memory_preflight = $memoryPreflight
    process_isolation_preflight = $processIsolationPreflight
    system_quiescence_preflight = $systemQuiescencePreflight
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
    expert_tier_adaptive_budget_requested = [bool]$ExpertTierAdaptiveBudget
    expert_tier_adaptive_min_requested = $ExpertTierAdaptiveMin
    expert_tier_adaptive_max_requested = $ExpertTierAdaptiveMax
    expert_tier_adaptive_step_requested = $ExpertTierAdaptiveStep
    expert_tier_adaptive_pressure_threshold_requested = $ExpertTierAdaptivePressureThreshold
    expert_tier_adaptive_enabled = $expertTieringAdaptiveEnabled
    expert_tier_adaptive_current = $expertTieringAdaptiveCurrent
    expert_tier_adaptive_min = $expertTieringAdaptiveMin
    expert_tier_adaptive_max = $expertTieringAdaptiveMax
    expert_tier_adaptive_step = $expertTieringAdaptiveStep
    expert_tier_adaptive_pressure_threshold = $expertTieringAdaptivePressureThreshold
    expert_tier_adaptive_ups = $expertTieringAdaptiveUps
    expert_tier_adaptive_downs = $expertTieringAdaptiveDowns
    expert_tier_adaptive_pressure_epochs = $expertTieringAdaptivePressureEpochs
    expert_tier_adaptive_quiet_epochs = $expertTieringAdaptiveQuietEpochs
    expert_tier_adaptive_last_skip_delta = $expertTieringAdaptiveLastSkipDelta
    expert_tier_adaptive_last_replacement_delta = $expertTieringAdaptiveLastReplacementDelta
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
    route_no_default_sync_requested = [bool]$RouteNoDefaultSync
    route_packed_copy_requested = [bool]$RoutePackedCopy
    route_packed_copy_observed = ($gpuRoutesPackedCopyRequested -eq 1)
    route_packed_copy_runtime_requested = $gpuRoutesPackedCopyRequested
    route_packed_copy_experts = $gpuRoutesPackedCopyExperts
    route_packed_copy_submissions = $gpuRoutesPackedCopySubmissions
    route_packed_copy_bytes = $gpuRoutesPackedCopyBytes
    route_packed_copy_legacy_submissions = $gpuRoutesLegacyCopySubmissions
    split_hit_miss_requested = [bool]$SplitHitMiss
    split_fused_requested = [bool]$SplitFused
    split_fused_observed = $splitFusedObserved
    split_fused_calls = $splitFusedCalls
    split_fused_hits = $splitFusedHits
    split_fused_misses = $splitFusedMisses
    split_fused_primary_route_basis = $splitFusedPrimaryRouteBasis
    split_fused_primary_routes_expected = $splitFusedExpectedPrimaryRoutes
    split_fused_primary_routes_observed = $splitFusedObservedPrimaryRoutes
    split_fused_q1_resident_routes_excluded =
        $splitFusedQ1ResidentRoutesExcluded
    split_fused_miss_scratch_bytes_avoided = $splitFusedMissScratchBytesAvoided
    split_fused_sum_read_bytes_avoided = $splitFusedSumReadBytesAvoided
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
    gpu_resident_routes_queries = $gpuRoutesQueries
    gpu_resident_routes_default_sync_calls = $gpuRoutesDefaultSyncCalls
    gpu_resident_routes_no_default_sync_calls = $gpuRoutesNoDefaultSyncCalls
    gpu_resident_routes_cache_count = $gpuRoutesCacheCount
    gpu_resident_routes_cache_calls = $gpuRoutesCacheCalls
    gpu_resident_routes_cache_hits = $gpuRoutesCacheHits
    gpu_resident_routes_cache_misses = $gpuRoutesCacheMisses
    gpu_resident_routes_cache_admissions = $gpuRoutesCacheAdmissions
    gpu_resident_routes_cache_evictions = $gpuRoutesCacheEvictions
    gpu_resident_routes_cache_direct_loads = $gpuRoutesCacheDirectLoads
    request_phase_trace_requested = [bool]$RequestPhaseTrace
    request_phase_trace_observed = $requestPhaseObserved
    request_phase_trace_line_count = $requestPhaseLineCount
    request_phase_trace_prefill_compute_seconds = $requestPhasePrefillComputeSeconds
    request_phase_trace_wrap_seconds = $requestPhaseWrapSeconds
    request_phase_trace_wrap_copy_seconds = $requestPhaseWrapCopySeconds
    request_phase_trace_post_wrap_seconds = $requestPhasePostWrapSeconds
    request_phase_trace_sync_tail_seconds = $requestPhaseSyncTailSeconds
    request_phase_trace_decode_gap_seconds = $requestPhaseDecodeGapSeconds
    request_phase_trace_first_sample_seconds = $requestPhaseFirstSampleSeconds
    request_phase_trace_first_eval_seconds = $requestPhaseFirstEvalSeconds
    request_phase_trace_decode_to_first_seconds = $requestPhaseDecodeToFirstSeconds
    request_phase_trace_prompt_to_first_seconds = $requestPhasePromptToFirstSeconds
    request_phase_trace_events = $requestPhaseEvents
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
$systemQuiescenceJson |
    Set-Content -LiteralPath $systemQuiescenceLog -Encoding UTF8

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
Write-Host ("prefill layer stripe req every/phase, result, layers full/partial, keep full/min/max, candidate/capacity: " + $PrefillMassLayerFullEvery + " / " + $PrefillMassLayerFullPhase + " / " + $prefillMassLayerStripeResult + " / " + $prefillMassLayerStripeFullLayers + " / " + $prefillMassLayerStripePartialLayers + " / " + $prefillMassLayerStripeFullKeep + " / " + $prefillMassLayerStripePartialKeepMin + " / " + $prefillMassLayerStripePartialKeepMax + " / " + $prefillMassLayerStripeTotalCandidate + " / " + $prefillMassLayerStripeCapacity)
Write-Host ("prefill VRAM seed per-layer/total/floor/obs/result/layers/entries/GiB/sec/failures: " + $PrefillVramSeedPerLayer + " / " + $PrefillVramSeedTotal + " / " + $PrefillVramSeedFloorPerLayer + " / " + $prefillVramSeedObserved + " / " + $prefillVramSeedResult + " / " + $prefillVramSeedLayers + " / " + $prefillVramSeedEntries + " / " + [math]::Round($prefillVramSeedBytes / 1GB, 3) + " / " + $prefillVramSeedSeconds + " / " + $prefillVramSeedFailures)
Write-Host ("REAP mass requested/armed/window/top/transport/tokens/slots/unique/top mass/touched: " + [bool]($ReapMassObserve -or $ReapMassWrap) + " / " + $reapMassArmed + " / " + $reapMassWindowObserved + " / " + $reapMassTopObserved + " / " + $reapMassTransport + " / " + $reapMassTokens + " / " + $reapMassObservedSlots + " / " + $reapMassUnique + " / " + $reapMassTopMass + " / " + $reapMassTouched)
Write-Host ("REAP mass WRAP requested/armed/grow/hysteresis/capacity/router/mask/policy: " + [bool]$ReapMassWrap + " / " + $reapMassWrapArmed + " / " + $reapMassWrapGrowIntervalObserved + " / " + $reapMassWrapHysteresisObserved + " / " + $reapMassWrapCapacity + " / " + $reapMassWrapRouterArmed + " / " + $reapMassWrapMaskArmed + " / " + $reapMassWrapPolicyArmed)
Write-Host ("REAP mass WRAP events/published/skipped/failed/entrants/victims/loads/sec: " + $reapMassWrapEventCount + " / " + $reapMassWrapPublicationCount + " / " + $reapMassWrapSkippedCount + " / " + $reapMassWrapFailureCount + " / " + $reapMassWrapEntrants + " / " + $reapMassWrapVictims + " / " + $reapMassWrapLoads + " / " + $reapMassWrapSeconds)
Write-Host ("REAP mass WRAP last result/reason/resident before/after/generation: " + $reapMassWrapLastResult + " / " + $reapMassWrapLastReason + " / " + $reapMassWrapLastResidentBefore + " / " + $reapMassWrapLastResidentAfter + " / " + $reapMassWrapLastGeneration)
Write-Host ("arena observer armed/window/minhits/grow/tokens/resident: " + $arenaObserverArmed + " / " + $arenaObserverWindowObserved + " / " + $arenaObserverMinHitsObserved + " / " + $arenaObserverGrowIntervalObserved + " / " + $arenaObserverTokens + " / " + $arenaObserverResident)
Write-Host ("arena cap req/min/available-before/chosen slots/bytes/capped/result/reason: " + $summary.dynamic_arena_cap_requested_gib + " / " + $summary.dynamic_arena_cap_min_available_gib + " / " + $summary.dynamic_arena_cap_available_before_gib + " / " + $summary.dynamic_arena_cap_chosen_slots + " / " + $summary.dynamic_arena_cap_chosen_bytes + " / " + $summary.dynamic_arena_cap_capped + " / " + $summary.dynamic_arena_cap_result + " / " + $summary.dynamic_arena_cap_reason)
Write-Host ("arena carry requested: " + $DynamicArenaCarry)
Write-Host ("arena carry observed/request/mode/snapshot/resident/lookup/observer: " + $arenaCarryObserved + " / " + $arenaCarryRequest + " / " + $arenaCarryModeObserved + " / " + $arenaCarrySnapshot + " / " + $arenaCarryResident + " / " + $arenaCarryLookupObserved + " / " + $arenaCarryObserverObserved)
Write-Host ("arena publication/window+WRAP counts: " + $arenaObserverPublicationCount + " / " + $arenaWrapPublicationCount)
Write-Host ("arena growth publications/skips: " + $arenaGrowthPublications + " / " + $arenaGrowthSkips)
Write-Host ("arena WRAP loads/workers/sec/generation/preloaded/mirror GiB: " + $arenaWrapLoads + " / " + $arenaWrapWorkers + " / " + $arenaWrapSeconds + " / " + $arenaWrapGeneration + " / " + $arenaWrapPreloaded + " / " + $arenaWrapMirrorGiB)
Write-Host ("arena WRAP profile result/schedule/source/checksum/total/copy/parts/workers: " + $arenaWrapProfileResult + " / " + $arenaWrapScheduleObserved + " / " + $arenaWrapSourceObserved + " / " + $arenaWrapChecksumObserved + " / " + $arenaWrapProfileTotalSeconds + " / " + $arenaWrapSourcePartsCopySeconds + " / " + $arenaWrapPartCount + " / " + $arenaWrapCopyWorkers)
Write-Host ("arena WRAP file QD req/line/obs/submits/completions/failures: " + $ArenaWrapFileQD + " / " + $arenaWrapFileQDRequestedObserved + " / " + $arenaWrapFileQDObserved + " / " + $arenaWrapFileSubmits + " / " + $arenaWrapFileCompletions + " / " + $arenaWrapFileFailures)
Write-Host ("arena WRAP part profile req/obs/workers/parts/memcpy/main/join/max-part-ms/slow: " + [bool]$ArenaWrapPartProfile + " / " + $arenaWrapPartProfileObserved + " / " + $arenaWrapPartProfileWorkers + " / " + $arenaWrapPartProfileParts + " / " + $arenaWrapPartProfileMemcpySumSeconds + " / " + $arenaWrapPartProfileMainWorkerSeconds + " / " + $arenaWrapPartProfileJoinSeconds + " / " + $arenaWrapPartProfileMaxPartMs + " / " + $arenaWrapPartProfileSlowParts)
Write-Host ("arena WRAP layout profile req/obs/lines: " + [bool]$ArenaWrapLayoutProfile + " / " + $arenaWrapLayoutProfileObserved + " / " + $arenaWrapLayoutProfileRows.Count)
Write-Host ("arena WRAP trim req/obs/result/calls/ok/fail/sec/error: " + [bool]$ArenaWrapTrimBetweenPhases + " / " + $arenaWrapTrimObserved + " / " + $arenaWrapTrimResult + " / " + $arenaWrapTrimCalls + " / " + $arenaWrapTrimSucceeded + " / " + $arenaWrapTrimFailed + " / " + $arenaWrapTrimSeconds + " / " + $arenaWrapTrimLastError)
Write-Host ("arena WRAP source unlock req/obs/result/phases/waves/waveGiB req/obs/max-wave/ranges/bytes/calls/true/not_locked/fail/sec: " + [bool]$ArenaWrapUnlockSourceRanges + " / " + $arenaWrapUnlockObserved + " / " + $arenaWrapUnlockSummaryResult + " / " + $arenaWrapUnlockSummaryPhases + " / " + $arenaWrapUnlockSummaryWaves + " / " + $ArenaWrapUnlockWaveGiB + " / " + $arenaWrapUnlockSummaryWaveGiB + " / " + $arenaWrapUnlockSummaryMaxWaveBytes + " / " + $arenaWrapUnlockSummaryRanges + " / " + $arenaWrapUnlockSummaryBytesRequested + " / " + $arenaWrapUnlockSummaryCalls + " / " + $arenaWrapUnlockSummaryTrue + " / " + $arenaWrapUnlockSummaryErrorNotLocked + " / " + $arenaWrapUnlockSummaryFailed + " / " + $arenaWrapUnlockSummarySeconds)
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
Write-Host ("aggregate disk read GiB / read MiBps / queue median/peak / contamination peak: " + [math]::Round($runtimeTelemetry.aggregate_disk_read_bytes_estimated / 1GB, 3) + " / " + [math]::Round($runtimeTelemetry.aggregate_disk_read_mib_per_second, 3) + " / " + $runtimeTelemetry.aggregate_disk_queue_length_median + " / " + $runtimeTelemetry.aggregate_disk_queue_length_peak + " / " + $runtimeTelemetry.contamination_consecutive_peak)
Write-Host ("evictions     : " + $evicts)
Write-Host ("streams_expert: " + $streamsExpert)
Write-Host ("streams_hot   : " + $streamsHot)
Write-Host ("selected_loads: " + $selLoads)
Write-Host ("moe_io_qd req/observed: " + $IoQD + " / " + $observedIoQD)
Write-Host ("moe_io_fallbacks: " + $overlappedIoFallbacks)
Write-Host ("expert_cache req/cap/count: " + $ExpertCacheN + " / " + $cacheCapacity + " / " + $cacheCount)
Write-Host ("expert_cache hits/misses/evictions/direct: " + $cacheHits + " / " + $cacheMisses + " / " + $cacheEvictions + " / " + $cacheDirect)
Write-Host ("expert_tiering requested/observed/calls/selected/failures/states vram/mass/lfru: " + $ExpertTiering + " / " + $expertTieringModeObserved + " / " + $expertTieringCalls + " / " + $expertTieringSelected + " / " + $expertTieringFailures + " / " + $expertTieringStatesVram + " / " + $expertTieringMassSum + " / " + $expertTieringLfruTop)
Write-Host ("expert_tiering adaptive req/enabled/current/min/max/step/threshold ups/downs pressure/quiet last skip/repl: " + [bool]$ExpertTierAdaptiveBudget + " / " + $expertTieringAdaptiveEnabled + " / " + $expertTieringAdaptiveCurrent + " / " + $expertTieringAdaptiveMin + " / " + $expertTieringAdaptiveMax + " / " + $expertTieringAdaptiveStep + " / " + $expertTieringAdaptivePressureThreshold + " / " + $expertTieringAdaptiveUps + " / " + $expertTieringAdaptiveDowns + " / " + $expertTieringAdaptivePressureEpochs + " / " + $expertTieringAdaptiveQuietEpochs + " / " + $expertTieringAdaptiveLastSkipDelta + " / " + $expertTieringAdaptiveLastReplacementDelta)
Write-Host ("mixed direct requested/observed/calls/cache routes/compact routes: " + [bool]$MixedDirectCache + " / " + $mixedDirectObserved + " / " + $mixedDirectCalls + " / " + $mixedDirectCacheRoutes + " / " + $mixedDirectCompactRoutes)
Write-Host ("route profile requested/observed/calls d2h/observe/map/transport/publish ms: " + [bool]$RouteProfile + " / " + $routeProfileObserved + " / " + $routeProfileCalls + " / " + $routeProfileD2HMs + " / " + $routeProfileObserveMs + " / " + $routeProfileMapMs + " / " + $routeProfileTransportMs + " / " + $routeProfilePublishMs)
Write-Host ("gpu resident routes requested/no-sync/packed/split/observed/calls/split-calls/all-hit/jobs/miss-experts/errors/worker-ms/resolve-ms/wait-ms/queries/default-sync/no-sync-calls: " + [bool]$GpuResidentRoutes + " / " + [bool]$RouteNoDefaultSync + " / " + [bool]$RoutePackedCopy + " / " + [bool]$SplitHitMiss + " / " + $gpuRoutesObserved + " / " + $gpuRoutesCalls + " / " + $gpuRoutesSplitCalls + " / " + $gpuRoutesAllHit + " / " + $gpuRoutesWorkerJobs + " / " + $gpuRoutesMissExperts + " / " + $gpuRoutesErrors + " / " + $gpuRoutesWorkerMs + " / " + $gpuRoutesResolveMs + " / " + $gpuRoutesWaitMs + " / " + $gpuRoutesQueries + " / " + $gpuRoutesDefaultSyncCalls + " / " + $gpuRoutesNoDefaultSyncCalls)
Write-Host ("route packed copy requested/observed/runtime-requested/experts/submissions/bytes/legacy-submissions: " + [bool]$RoutePackedCopy + " / " + ($gpuRoutesPackedCopyRequested -eq 1) + " / " + $gpuRoutesPackedCopyRequested + " / " + $gpuRoutesPackedCopyExperts + " / " + $gpuRoutesPackedCopySubmissions + " / " + $gpuRoutesPackedCopyBytes + " / " + $gpuRoutesLegacyCopySubmissions)
Write-Host ("split fused requested/observed/calls/hits/misses/miss-scratch-avoided/sum-read-avoided: " + [bool]$SplitFused + " / " + $splitFusedObserved + " / " + $splitFusedCalls + " / " + $splitFusedHits + " / " + $splitFusedMisses + " / " + $splitFusedMissScratchBytesAvoided + " / " + $splitFusedSumReadBytesAvoided)
Write-Host ("gpu resident route cache count/calls/hits/misses/admissions/evictions/direct: " + $gpuRoutesCacheCount + " / " + $gpuRoutesCacheCalls + " / " + $gpuRoutesCacheHits + " / " + $gpuRoutesCacheMisses + " / " + $gpuRoutesCacheAdmissions + " / " + $gpuRoutesCacheEvictions + " / " + $gpuRoutesCacheDirectLoads)
Write-Host ("request phase trace requested/observed/lines prefill/wrap/copy/post-wrap/sync-tail/decode-gap/sample/eval/decode-first/prompt-first sec: " + [bool]$RequestPhaseTrace + " / " + $requestPhaseObserved + " / " + $requestPhaseLineCount + " / " + $requestPhasePrefillComputeSeconds + " / " + $requestPhaseWrapSeconds + " / " + $requestPhaseWrapCopySeconds + " / " + $requestPhasePostWrapSeconds + " / " + $requestPhaseSyncTailSeconds + " / " + $requestPhaseDecodeGapSeconds + " / " + $requestPhaseFirstSampleSeconds + " / " + $requestPhaseFirstEvalSeconds + " / " + $requestPhaseDecodeToFirstSeconds + " / " + $requestPhasePromptToFirstSeconds)
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
Write-Host ("nested residual enabled/observed/router-calls/hits/misses/preads/reconstructed/mismatches/failures: " + [bool]$NestedResidualSidecar + " / " + $nestedResidualRuntimeObserved + " / " + $nestedResidualRouterCalls + " / " + $nestedResidualCacheHits + " / " + $nestedResidualCacheMisses + " / " + $nestedResidualPreads + " / " + $nestedResidualReconstructed + " / " + $nestedResidualMismatches + " / " + $nestedResidualFailures)
Write-Host ("nested residual exact-cache requested experts: " + $NestedResidualCacheExperts)
Write-Host ("nested residual gpu-cache requested/observed/route-calls/hits/misses/host-fills/host-bytes/h2d-bytes/failures: " + [bool]$NestedResidualGpuCache + " / " + $nestedResidualVramRuntimeObserved + " / " + $nestedResidualVramRouteCalls + " / " + $nestedResidualVramHits + " / " + $nestedResidualVramMisses + " / " + $nestedResidualVramHostFills + " / " + $nestedResidualVramHostBytes + " / " + $nestedResidualVramH2DBytes + " / " + $nestedResidualVramFailures)
Write-Host ("nested residual gpu-join safety receipt validated/path/hash: " + $nestedResidualGpuJoinSafetyReceiptValidated + " / " + $nestedResidualGpuJoinSafetyReceiptPathAtStart + " / " + $nestedResidualGpuJoinSafetyReceiptHashAtStart)
Write-Host ("nested residual gpu-join requested/observed/runtime-requested/runtime-observed/calls/blocks/base-H2D/residual-H2D/native-H2D/sec/wait-calls/wait-sec/verify-calls/verify-bytes/verify-sec/mismatches/failures/cpu-reconstruct-calls: " + [bool]$NestedResidualGpuJoin + " / " + $nestedResidualGpuJoinObserved + " / " + $nestedResidualGpuJoinRequestedRuntime + " / " + $nestedResidualGpuJoinObservedRuntime + " / " + $nestedResidualGpuJoinCalls + " / " + $nestedResidualGpuJoinBlocks + " / " + $nestedResidualGpuJoinBaseH2DBytes + " / " + $nestedResidualGpuJoinResidualH2DBytes + " / " + $nestedResidualGpuJoinNativeH2DBytes + " / " + $nestedResidualGpuJoinSeconds + " / " + $nestedResidualGpuJoinWaitCalls + " / " + $nestedResidualGpuJoinWaitSeconds + " / " + $nestedResidualGpuJoinVerifyCalls + " / " + $nestedResidualGpuJoinVerifyBytes + " / " + $nestedResidualGpuJoinVerifySeconds + " / " + $nestedResidualGpuJoinVerifyMismatches + " / " + $nestedResidualGpuJoinFailures + " / " + $nestedResidualGpuJoinCpuReconstructCalls)
Write-Host ("nested residual gpu-join residual-cache requested/observed/enabled/hits/misses/evictions/entries/capacity/pread-bytes/pread-avoided/H2D/cached-join-calls/invariant-failures: " + [bool]$NestedResidualGpuJoinResidualCache + " / " + $nestedResidualGpuJoinResidualCacheObserved + " / " + $nestedResidualGpuJoinResidualCacheEnabledRuntime + " / " + $nestedResidualGpuJoinResidualCacheHits + " / " + $nestedResidualGpuJoinResidualCacheMisses + " / " + $nestedResidualGpuJoinResidualCacheEvictions + " / " + $nestedResidualGpuJoinResidualCacheEntries + " / " + $nestedResidualGpuJoinResidualCacheCapacity + " / " + $nestedResidualGpuJoinResidualCachePreadBytes + " / " + $nestedResidualGpuJoinResidualCachePreadBytesAvoided + " / " + $nestedResidualGpuJoinResidualCacheH2DBytes + " / " + $nestedResidualGpuJoinResidualCacheCachedJoinCalls + " / " + $nestedResidualGpuJoinResidualCacheInvariantFailures)
Write-Host ("nested residual profile requested/observed lookup/pread/reconstruct/verify/host-copy/H2D-enqueue/H2D-sync/submit-launch/ready-wait sec: " + [bool]$NestedResidualProfile + " / " + $nestedResidualProfileObserved + " / " + $nestedResidualProfileLookupSeconds + " / " + $nestedResidualProfilePreadSeconds + " / " + $nestedResidualProfileReconstructSeconds + " / " + $nestedResidualProfileVerifySeconds + " / " + $nestedResidualProfileHostCopySeconds + " / " + $nestedResidualProfileH2DEnqueueSeconds + " / " + $nestedResidualProfileH2DSyncSeconds + " / " + $nestedResidualProfileRouteBeginSeconds + " / " + $nestedResidualProfileRouteReadyWaitSeconds)
Write-Host ("Q1_0 sidecar enabled/selected-load/resident/dual-requested/dual-observed/observed/calls/slots/loads/failures: " + [bool]$Q1_0ExpertSidecar + " / " + [bool]$Q1_0SelectedLoad + " / " + [bool]$Q1_0ResidentArena + " / " + [bool]$Q1_0DualArena + " / " + $q1_0DualArenaRuntimeObserved + " / " + $q1_0SidecarRuntimeObserved + " / " + $q1_0SidecarCalls + " / " + $q1_0SidecarSlots + " / " + $q1_0SidecarSelectedLoads + " / " + $q1_0SidecarFailures)
Write-Host ("Q1_0 resident mode/hits/misses/H2D bytes/direct-fallbacks/direct-bytes/bootstrap: " + $q1_0ResidentMode + " / " + $q1_0ResidentHits + " / " + $q1_0ResidentMisses + " / " + $q1_0ResidentH2DBytes + " / " + $q1_0DirectPreadFallbacks + " / " + $q1_0DirectPreadBytes + " / " + $q1_0BootstrapEntries)
Write-Host ("Q1_0 profile requested/observed/pinned-hits/pageable-hits/pinned-H2D/pageable-H2D/enqueue-sec/sync-sec/kernel-sec/join-sec: " + [bool]$Q1_0Profile + " / " + $q1_0ProfileTelemetry.observed + " / " + $q1_0ProfileTelemetry.pinned_route_hits + " / " + $q1_0ProfileTelemetry.pageable_route_hits + " / " + $q1_0ProfileTelemetry.pinned_h2d_bytes + " / " + $q1_0ProfileTelemetry.pageable_h2d_bytes + " / " + $q1_0ProfileTelemetry.h2d_enqueue_seconds_total + " / " + $q1_0ProfileTelemetry.upload_sync_seconds_total + " / " + $q1_0ProfileTelemetry.q1_kernel_seconds + " / " + $q1_0ProfileTelemetry.mixed_join_seconds)
Write-Host ("Q1_0 SSD-WRAP requested/observed/attempts/successes/failures/host-budget-GiB: " + [bool]$Q1_0PromotionSsdWrap + " / " + $q1_0SsdWrapTelemetry.observed + " / " + $q1_0SsdWrapTelemetry.attempts + " / " + $q1_0SsdWrapTelemetry.successes + " / " + $q1_0SsdWrapTelemetry.failures + " / " + [math]::Round($q1_0SsdWrapTelemetry.host_budget_bytes / 1GB, 3))
Write-Host ("Expert recovery trace requested/observed/valid/layer/expert/samples/capped/binary/jsonl/manifest SHA: " + [bool]$ExpertRecoveryTrace + " / " + $expertRecoveryTraceArtifact.observed + " / " + $expertRecoveryTraceArtifact.valid + " / " + $expertRecoveryTraceArtifact.layer + " / " + $expertRecoveryTraceArtifact.expert + " / " + $expertRecoveryTraceArtifact.sample_count + " / " + $expertRecoveryTraceArtifact.capped_samples + " / " + $expertRecoveryTraceArtifact.binary_sha256 + " / " + $expertRecoveryTraceArtifact.jsonl_sha256 + " / " + $expertRecoveryTraceArtifact.manifest_sha256)
Write-Host ("Q1_0 runtime-contract/fail-closed/structural-eligible/performance-eligible: " + $q1_0RuntimeContractValid + " / " + $q1_0FailClosedObserved + " / " + $q1_0StructuralSmokeEligible + " / False")
Write-Host ("IQ1_S RAM cache req/observed/capacity/count/hits/misses/evictions/failures: " + $Iq1SRamCacheGiB + " / " + $iq1SRamCacheRuntimeObserved + " / " + $iq1SRamCacheCapacity + " / " + $iq1SRamCacheCount + " / " + $iq1SRamCacheHits + " / " + $iq1SRamCacheMisses + " / " + $iq1SRamCacheEvictions + " / " + $iq1SRamCacheFailures)
Write-Host ("IQ1_S RAM cache hit-rate/SSD GiB/H2D GiB/SSD avoided GiB: " + [math]::Round($iq1SRamCacheHitRate, 4) + " / " + [math]::Round($iq1SRamCacheSsdBytes / 1GB, 3) + " / " + [math]::Round($iq1SRamCacheH2dBytes / 1GB, 3) + " / " + [math]::Round($iq1SRamCacheSsdAvoidedBytes / 1GB, 3))
Write-Host ("IQ1_S full preload pageable/frozen/layers/entries/SSD GiB/read-calls/ms: " + [bool]$Iq1SRamCachePageable + " / " + $iq1SRamCachePreloadFrozen + " / " + $iq1SRamCachePreloadLayers + " / " + $iq1SRamCachePreloadEntries + " / " + [math]::Round($iq1SRamCachePreloadSsdBytes / 1GB, 3) + " / " + $iq1SRamCachePreloadReadCalls + " / " + $iq1SRamCachePreloadMs)
Write-Host ("IQ1_S VRAM cache req/observed/capacity/count/hits/misses/evictions/failures: " + $Iq1SVramCachePerLayer + " / " + $iq1SVramCacheRuntimeObserved + " / " + $iq1SVramCacheCapacity + " / " + $iq1SVramCacheCount + " / " + $iq1SVramCacheHits + " / " + $iq1SVramCacheMisses + " / " + $iq1SVramCacheEvictions + " / " + $iq1SVramCacheFailures)
Write-Host ("IQ1_S VRAM cache hit-rate/H2D GiB: " + $(if (($iq1SVramCacheHits + $iq1SVramCacheMisses) -gt 0) { [math]::Round([double]$iq1SVramCacheHits / [double]($iq1SVramCacheHits + $iq1SVramCacheMisses), 4) } else { 0 }) + " / " + [math]::Round($iq1SVramCacheH2dBytes / 1GB, 3))
Write-Host ("IQ1_S mixed calls/hot-main/cold-IQ1/primary-avoided/joins/failures: " + $iq1MixedCalls + " / " + $iq1MixedHotMain + " / " + $iq1MixedColdIq1 + " / " + $iq1MixedPrimaryColdAvoided + " / " + $iq1MixedJoins + " / " + $iq1MixedFailures)
Write-Host ("IQ1_S mixed GPU plan requested/observed/calls/wait-ms/failures: " + [bool]$Iq1SMixedGpuPlan + " / " + $iq1MixedGpuPlanRuntimeObserved + " / " + $iq1MixedGpuPlanCalls + " / " + $iq1MixedGpuPlanWaitMs + " / " + $iq1MixedGpuPlanFailures)
Write-Host ("IQ1 promotion gate config min-touches/min-weight/min-mass/request-budget/window-calls/window-budget: " + $iq1PromotionObservedMinTouches + " / " + $iq1PromotionObservedMinWeight + " / " + $iq1PromotionObservedMinMass + " / " + $iq1PromotionObservedRequestBudget + " / " + $iq1PromotionObservedWindowCalls + " / " + $iq1PromotionObservedWindowBudget)
Write-Host ("IQ1 promotion gate candidates weight>=.001/.002/.005/.010 skips touches/weight/mass/request/window: " + $iq1PromotionColdGateCandidates + " / " + $iq1PromotionWeightGe001 + " / " + $iq1PromotionWeightGe002 + " / " + $iq1PromotionWeightGe005 + " / " + $iq1PromotionWeightGe010 + " / " + $iq1PromotionSkipsTouches + " / " + $iq1PromotionSkipsWeight + " / " + $iq1PromotionSkipsMass + " / " + $iq1PromotionSkipsRequestBudget + " / " + $iq1PromotionSkipsWindowBudget)
Write-Host ("Quant promotion kind/requested/observed/lines/slots/cold/existing2bit/to2bitram/ssd-GiB/ssd-sec/ssd-Bps/direct-rejected/backing-reclaims/failures: " + $(if ($Q1_0DynamicPromotion) { "q1_0" } elseif ($Iq1Promotion) { "iq1_s" } else { "off" }) + " / " + [bool]$quantPromotionRequested + " / " + $iq1PromotionRuntimeObserved + " / " + $iq1PromotionLineCount + " / " + $promotionProbationSlotsExpected + " / " + $iq1PromotionColdObserved + " / " + $iq1PromotionColdExisting2Bit + " / " + $iq1PromotionColdTo2BitRam + " / " + [math]::Round($iq1Promotion2BitSsdBytes / 1GB, 3) + " / " + $iq1Promotion2BitSsdSeconds + " / " + [math]::Round($iq1Promotion2BitSsdBytesPerSecond, 3) + " / " + $iq1PromotionDirectSsdToVramRejected + " / " + $iq1PromotionProbationBackingReclaims + " / " + $iq1PromotionFailures)
Write-Host ("Q1_0 promotion records observed/count/lines/attempt/success/reject/failure/path/sha: " + [bool]($q1_0PromotionRecordCount -gt 0) + " / " + $q1_0PromotionRecordCount + " / " + $q1_0PromotionRecordPhysicalLineCount + " / " + $q1_0PromotionRecordAttemptCount + " / " + $q1_0PromotionRecordSuccessCount + " / " + $q1_0PromotionRecordRejectCount + " / " + $q1_0PromotionRecordFailureCount + " / " + $q1_0PromotionRecordArtifactPath + " / " + $q1_0PromotionRecordArtifactSHA256)
Write-Host ("IQ1_S profile/no-main-sync/packed-H2D: " + [bool]$Iq1SProfile + " / " + [bool]$Iq1SNoMainSync + " / " + [bool]$Iq1SPackedH2D)
Write-Host ("IQ1_S profile SSD reads/ms H2D batches/copies/enqueue-ms/syncs/sync-ms: " + $iq1ProfileSsdReadCalls + " / " + $iq1ProfileSsdReadMs + " / " + $iq1ProfileH2dBatches + " / " + $iq1ProfileH2dCopies + " / " + $iq1ProfileH2dEnqueueMs + " / " + $iq1ProfileH2dSyncs + " / " + $iq1ProfileH2dSyncMs)
Write-Host ("IQ1_S mixed profile calls/router-D2H/meta-H2D/main-submit/main-sync/cold-submit/join ms: " + $iq1MixedProfileCalls + " / " + $iq1MixedProfileRouterD2hMs + " / " + $iq1MixedProfileMetadataH2dMs + " / " + $iq1MixedProfileMainSubmitMs + " / " + $iq1MixedProfileMainSyncMs + " / " + $iq1MixedProfileColdSubmitMs + " / " + $iq1MixedProfileJoinSubmitMs)
Write-Host ("last_sel_line : " + $lastSel)
Write-Host "=================================================="
} catch {
    $failureReason = "runtime-failure"
    if (Get-Variable -Name runtimeAbortSample -Scope Local -ErrorAction SilentlyContinue) {
        if ($runtimeAbortSample) { $failureReason = "runtime-contamination-abort" }
    }
    Write-G7MeasurementFailure `
        -Reason $failureReason `
        -Exception $_.Exception.Message `
        -AbortSample $(if (Get-Variable -Name runtimeAbortSample -Scope Local -ErrorAction SilentlyContinue) { $runtimeAbortSample } else { $null }) `
        -Evidence $(if (Get-Variable -Name runtimeFailureEvidence -Scope Local -ErrorAction SilentlyContinue) { @($runtimeFailureEvidence) } else { @() })
    throw
} finally {
    if ($null -ne $modelLockStream) {
        try { $modelLockStream.Dispose() } catch {}
    }
    if ($null -ne $iq1SSidecarLockStream) {
        try { $iq1SSidecarLockStream.Dispose() } catch {}
    }
    if ($null -ne $q1_0SidecarLockStream) {
        try { $q1_0SidecarLockStream.Dispose() } catch {}
    }
    if ($null -ne $nestedResidualLockStream) {
        try { $nestedResidualLockStream.Dispose() } catch {}
    }
    if ($null -ne $nestedResidualGpuJoinSafetyResultLockStream) {
        try { $nestedResidualGpuJoinSafetyResultLockStream.Dispose() } catch {}
    }
    if ($null -ne $nestedResidualGpuJoinSafetyReceiptLockStream) {
        try { $nestedResidualGpuJoinSafetyReceiptLockStream.Dispose() } catch {}
    }
    if ($measurementLockAcquired) {
        try { $measurementMutex.ReleaseMutex() } catch {}
    }
    $measurementMutex.Dispose()
}
