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
    [ValidateRange(0, 512)][int]$ComposePrefillMassReserveSlots = 0,
    [ValidateRange(0, 40)][int]$PrefillMassLayerFullEvery = 0,
    [ValidateRange(0, 39)][int]$PrefillMassLayerFullPhase = 0,
    [ValidateRange(0, 32)][int]$PrefillVramSeedPerLayer = 0,
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
    [switch]$Iq1SColdOnly,
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
. (Join-Path $PSScriptRoot "g7_process_isolation.ps1")
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
        $receipt = [Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json
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
if ($ExpectedModelIq1SuiteReceiptSHA256 -and
    $ExpectedModelIq1SuiteReceiptSHA256 -notmatch '^[0-9a-fA-F]{64}$') {
    throw "ExpectedModelIq1SuiteReceiptSHA256 must be a 64-character hexadecimal SHA-256"
}
if ($ReuseVerifiedModelReceipt -and -not $ExpectedModelSHA256) {
    throw "ReuseVerifiedModelReceipt requires ExpectedModelSHA256"
}
if (($ReuseVerifiedModelReceipt -or $ReuseVerifiedIq1SReceipt) -and
    $GateKind -ne "structural-safety") {
    throw "Verified receipt reuse is restricted to structural-safety diagnostics"
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
$iq1SSidecarInfoAtStart = $null
$iq1SSidecarReceiptAtStart = $null
$iq1SSidecarReceiptPath = ""
$iq1SSidecarReceiptHashAtStart = ""
$iq1SSidecarLockStream = $null
$modelIq1SuiteReceiptAtStart = $null
$modelIq1SuiteReceiptPathAtStart = ""
$modelIq1SuiteReceiptHashAtStart = ""
$modelIq1SuiteReceiptSchemaAtStart = ""
$modelIq1SuiteFullHashVerified = $false
$modelIq1SuiteLockProofRequired = $false
$modelIq1SuiteLockProofObserved = $false
$modelIq1SuiteLockProof = $null
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
if ($Iq1SMixedColdOne -and -not $Iq1SExpertSidecar -and -not $Iq1SColdOnly) {
    throw "Iq1SMixedColdOne requires Iq1SExpertSidecar"
}
if ($Iq1SMixedGpuPlan -and -not $Iq1SMixedColdOne) {
    throw "Iq1SMixedGpuPlan requires Iq1SMixedColdOne"
}
if ($Iq1SColdOnly) {
    if (-not $Iq1SMixedColdOne) { throw "Iq1SColdOnly requires Iq1SMixedColdOne" }
    if (-not $Iq1SExpertSidecar) { throw "Iq1SColdOnly requires Iq1SExpertSidecar" }
    if ($ExpertTiering -ne "enforce") { throw "Iq1SColdOnly requires ExpertTiering enforce" }
    if ($Iq1SMixedGpuPlan) { throw "Iq1SColdOnly is incompatible with Iq1SMixedGpuPlan" }
}
if ($Iq1Promotion) {
    if (-not $Iq1SExpertSidecar) { throw "Iq1Promotion requires Iq1SExpertSidecar" }
    if (-not $Iq1SMixedColdOne) { throw "Iq1Promotion requires Iq1SMixedColdOne" }
    if (-not $Iq1SMixedGpuPlan) { throw "Iq1Promotion requires Iq1SMixedGpuPlan" }
    if (-not $ComposePrefillMassTiering) { throw "Iq1Promotion requires ComposePrefillMassTiering" }
    if ($ExpertTiering -ne "enforce") { throw "Iq1Promotion requires ExpertTiering enforce" }
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
    if (-not $Iq1Promotion -and $ComposePrefillMassReserveSlots -le 0) { throw "ComposePrefillMassOpenRouter requires Iq1Promotion or ComposePrefillMassReserveSlots > 0" }
}
if ($ComposePrefillMassReserveSlots -gt 0 -and -not $ComposePrefillMassOpenRouter) {
    throw "ComposePrefillMassReserveSlots requires ComposePrefillMassOpenRouter"
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
$outdir = Join-Path $PSScriptRoot "g7_runs"
New-Item -ItemType Directory -Force -Path $outdir | Out-Null
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
$rawHttpCheckpointPath = Join-Path $outdir ("g7_" + $Tag + "_raw_http_checkpoint.json")
$resultPath = Join-Path $outdir ("g7_" + $Tag + "_result.json")
if (Test-Path $stderrLog) { Remove-Item $stderrLog -Force }
if (Test-Path $stdoutLog) { Remove-Item $stdoutLog -Force }
if (Test-Path $memoryPreflightLog) { Remove-Item $memoryPreflightLog -Force }
if (Test-Path $processIsolationLog) { Remove-Item $processIsolationLog -Force }
if (Test-Path $systemQuiescenceLog) { Remove-Item $systemQuiescenceLog -Force }
if (Test-Path $runtimeTelemetryLog) { Remove-Item $runtimeTelemetryLog -Force }
if (Test-Path $failurePath) { Remove-Item $failurePath -Force }
if (Test-Path $rawOutputsPath) { Remove-Item $rawOutputsPath -Force }
if (Test-Path $rawHttpCheckpointPath) { Remove-Item $rawHttpCheckpointPath -Force }
if (Test-Path $resultPath) { Remove-Item $resultPath -Force }

try {
    $processesAtPreflight = @(Get-CimInstance Win32_Process -ErrorAction Stop)
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
$env:DS4_CUDA_STREAM_FROM_RAM_MASKED_BUDGET_GB = "$BudgetGB"
$env:DS4_CUDA_STREAM_RESERVE_MB = "$ReserveMB"
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
if ($Iq1SColdOnly) {
    $env:DS4_IQ1_S_COLD_ONLY = "1"
} else {
    Remove-Item Env:\DS4_IQ1_S_COLD_ONLY -ErrorAction SilentlyContinue
}
if ($Iq1SMixedGpuPlan) {
    $env:DS4_IQ1_MIXED_GPU_PLAN = "1"
} else {
    Remove-Item Env:\DS4_IQ1_MIXED_GPU_PLAN -ErrorAction SilentlyContinue
}
if ($Iq1Promotion) {
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
if ($ComposePrefillMassOpenRouter) {
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
$modelLockStream = if ($ExpectedModelSHA256 -and -not $ReuseVerifiedSuiteReceipt) {
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
if (-not $SkipSystemQuiescencePreflight) {
    for ($sampleIndex = 0; $sampleIndex -lt $QuiescenceSamples; $sampleIndex++) {
        try {
            $cpuSample = Get-CimInstance -ClassName Win32_PerfFormattedData_PerfOS_Processor `
                -Filter "Name='_Total'" -ErrorAction Stop
            $diskSample = Get-CimInstance -ClassName Win32_PerfFormattedData_PerfDisk_PhysicalDisk `
                -Filter "Name='_Total'" -ErrorAction Stop
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
            $diskIoMiBps = ([double]$diskSample.DiskReadBytesPerSec +
                [double]$diskSample.DiskWriteBytesPerSec) / 1MB
            $quiescenceRows += [pscustomobject][ordered]@{
                sample = $sampleIndex + 1
                timestamp_utc = [DateTime]::UtcNow.ToString(
                    "o", [Globalization.CultureInfo]::InvariantCulture)
                elapsed_ms = [math]::Round($quiescenceStopwatch.Elapsed.TotalMilliseconds, 3)
                cpu_percent = [double]$cpuSample.PercentProcessorTime
                disk_percent = [double]$diskSample.PercentDiskTime
                disk_read_mib_per_second = [double]$diskSample.DiskReadBytesPerSec / 1MB
                disk_write_mib_per_second = [double]$diskSample.DiskWriteBytesPerSec / 1MB
                disk_io_mib_per_second = $diskIoMiBps
                gpu_percent = $gpuPercent
                gpu_utilization_percent_by_index = $gpuRows
            }
        } catch {
            $quiescenceFailures += "sample-error: " + $_.Exception.Message
            break
        }
        if ($sampleIndex + 1 -lt $QuiescenceSamples) {
            Start-Sleep -Milliseconds $QuiescenceIntervalMs
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
    iq1_s_sidecar_path = $(if ($iq1SSidecarInfoAtStart) { $iq1SSidecarInfoAtStart.FullName } else { "" })
    iq1_s_sidecar_size_bytes = $(if ($iq1SSidecarInfoAtStart) { [UInt64]$iq1SSidecarInfoAtStart.Length } else { [UInt64]0 })
    iq1_s_sidecar_expected_sha256 = $ExpectedIq1SExpertSidecarSHA256.ToLowerInvariant()
    prompt_sha256 = $promptHash
    context = $Context
    max_tokens = $MaxTokens
    probe_only = [bool]$QuiescenceProbeOnly
    skipped = [bool]$SkipSystemQuiescencePreflight
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

# Preserve response bytes and hashes before runtime-log validation. A later
# telemetry/parser failure must not erase the exactness evidence from the run.
[pscustomobject]@{
    schema = "g7_raw_http_checkpoint_v1"
    tag = $Tag
    http_ok = $httpOk
    warmup = $warmupResult
    results = @($results)
} | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 $rawHttpCheckpointPath

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
$arenaAllocatedBytes = 0; $arenaSlotBytes = 0; $arenaAllocatedSlots = 0
$arenaCapObserved = $false; $arenaCapRequestedGiB = 0.0
$arenaCapMinAvailableGiB = 0.0; $arenaCapAvailableBeforeGiB = 0.0
$arenaCapRequestedBytes = 0; $arenaCapRequestedSlots = 0
$arenaCapChosenBytes = 0; $arenaCapChosenSlots = 0
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
    $prefillVramSeedLineCount = $prefillVramSeedLines.Count
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
    } elseif ($prefillVramSeedLineCount -ne 0) {
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
    if ($ComposePrefillMassTiering -and
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
        $arenaCapPattern = "^ds4: \[arena-cap\] requested_gib=([0-9.]+) min_available_gib=([0-9.]+) available_before_gib=(-?[0-9.]+) requested_bytes=(\d+) requested_slots=(\d+) chosen_bytes=(\d+) chosen_slots=(\d+) capped=(0|1) result=(ready|disabled) reason=([a-z-]+)$"
        if ($arenaCapLine -notmatch $arenaCapPattern) {
            throw "Dynamic arena cap line format mismatch: $arenaCapLine"
        }
        $arenaCapObserved = $true
        $arenaCapRequestedGiB = [double]::Parse($Matches[1], [Globalization.CultureInfo]::InvariantCulture)
        $arenaCapMinAvailableGiB = [double]::Parse($Matches[2], [Globalization.CultureInfo]::InvariantCulture)
        $arenaCapAvailableBeforeGiB = [double]::Parse($Matches[3], [Globalization.CultureInfo]::InvariantCulture)
        $arenaCapRequestedBytes = [long]$Matches[4]
        $arenaCapRequestedSlots = [long]$Matches[5]
        $arenaCapChosenBytes = [long]$Matches[6]
        $arenaCapChosenSlots = [long]$Matches[7]
        $arenaCapCapped = ($Matches[8] -eq "1")
        $arenaCapResult = $Matches[9]
        $arenaCapReason = $Matches[10]
    }
    $arenaReadyLine = $lines | Where-Object { $_ -match "CUDA dynamic arena ready" } | Select-Object -Last 1
    if ($arenaReadyLine -and $arenaReadyLine -match "CUDA dynamic arena ready [0-9.]+ GiB, (\d+) slots.*bytes=(\d+) slot_bytes=(\d+)") {
        $arenaAllocatedSlots = [long]$Matches[1]
        $arenaAllocatedBytes = [long]$Matches[2]
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
    if ($arenaFinalLine -and $arenaFinalLine -match "\[arena\] final hits=(\d+) misses=(\d+) fatal=(\d+) uploaded=([0-9.]+) GiB") {
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
        $gpuRoutesPackedCopySubmissions -ne $gpuRoutesPackedCopyExperts -or
        $gpuRoutesPackedCopyBytes -le 0 -or
        $gpuRoutesLegacyCopySubmissions -ne 0) {
        throw "RoutePackedCopy was requested but packed route copy accounting did not prove exclusive packed copies"
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
$iq1ColdOnlySummaryPattern =
    '\[iq1-cold-only\] result=summary calls=(\d+) routes=(\d+) main_vram=(\d+) main_snapshot_ram=(\d+) main_tier_ram=(\d+) main_ssd_cold=(\d+) iq1_ram_hits=(\d+) eligible=(\d+) substitutions=(\d+) fallback_all_main=(\d+) skipped_iq1_miss=(\d+) uncertain=(\d+) failures=(\d+)'
$iq1ColdOnlyEarlyMatches = [regex]::Matches(
    $iq1SSidecarLogText, $iq1ColdOnlySummaryPattern)
$iq1ColdOnlyZeroUse = $false
if ($Iq1SColdOnly -and $iq1ColdOnlyEarlyMatches.Count -eq 1) {
    $iq1ColdOnlyZeroUse =
        [UInt64]$iq1ColdOnlyEarlyMatches[0].Groups[9].Value -eq 0
}
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
    $iq1SSidecarZeroUse =
        $iq1SSidecarCalls -eq 0 -and
        $iq1SSidecarSlots -eq 0 -and
        $iq1SSidecarSelectedLoads -eq 0
    if ((-not ($iq1ColdOnlyZeroUse -and $iq1SSidecarZeroUse) -and
            ($iq1SSidecarCalls -eq 0 -or
             $iq1SSidecarSlots -lt $iq1SSidecarCalls -or
             $iq1SSidecarSelectedLoads -ne $iq1SSidecarCalls)) -or
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
$iq1SRamCacheDeferredUnused = $false
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
    if ($iq1ColdOnlyZeroUse -and
        $iq1SRamCacheReadyMatches.Count -eq 0 -and
        $iq1SRamCacheSummaryMatches.Count -eq 0) {
        $iq1SRamCacheDeferredUnused = $true
    } elseif ($iq1SRamCacheReadyMatches.Count -ne 1 -or
        $iq1SRamCacheSummaryMatches.Count -ne 1) {
        throw "IQ1_S RAM cache requires exactly one ready marker and one summary; observed ready=$($iq1SRamCacheReadyMatches.Count) summary=$($iq1SRamCacheSummaryMatches.Count)"
    }
    if (-not $iq1SRamCacheDeferredUnused) {
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
    }
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
$iq1ColdOnlyRuntimeObserved = $false
$iq1ColdOnlyCalls = [UInt64]0
$iq1ColdOnlyRoutes = [UInt64]0
$iq1ColdOnlyMainVram = [UInt64]0
$iq1ColdOnlyMainSnapshotRam = [UInt64]0
$iq1ColdOnlyMainTierRam = [UInt64]0
$iq1ColdOnlyMainSsdCold = [UInt64]0
$iq1ColdOnlyRamHits = [UInt64]0
$iq1ColdOnlyEligible = [UInt64]0
$iq1ColdOnlySubstitutions = [UInt64]0
$iq1ColdOnlyFallbackAllMain = [UInt64]0
$iq1ColdOnlySkippedIq1Miss = [UInt64]0
$iq1ColdOnlyUncertain = [UInt64]0
$iq1ColdOnlyFailures = [UInt64]0
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
$iq1PromotionFailures = [UInt64]0
$iq1MixedSummaryMatches = [regex]::Matches(
    $iq1SSidecarLogText,
    '\[iq1-mixed\] result=summary calls=(\d+) hot_main=(\d+) cold_iq1=(\d+) primary_cold_avoided=(\d+) joins=(\d+) failures=(\d+) last_layer=(\d+) last_slot=(\d+) last_expert=(-?\d+)')
$iq1MixedGpuPlanReadyMatches = [regex]::Matches(
    $iq1SSidecarLogText,
    '\[iq1-mixed-gpu-plan\] result=ready mode=cold-one-upload-overlap')
$iq1MixedGpuPlanSummaryMatches = [regex]::Matches(
    $iq1SSidecarLogText,
    '\[iq1-mixed-gpu-plan\] result=summary calls=(\d+) wait_ms=([0-9.]+) failures=(\d+)')
$iq1ColdOnlySummaryMatches = [regex]::Matches(
    $iq1SSidecarLogText,
    $iq1ColdOnlySummaryPattern)
if ($Iq1SColdOnly) {
    if ($iq1ColdOnlySummaryMatches.Count -ne 1) {
        throw "IQ1_S cold-only requires exactly one runtime summary; observed $($iq1ColdOnlySummaryMatches.Count)"
    }
    $iq1ColdOnlySummary = $iq1ColdOnlySummaryMatches[0]
    $iq1ColdOnlyCalls = [UInt64]$iq1ColdOnlySummary.Groups[1].Value
    $iq1ColdOnlyRoutes = [UInt64]$iq1ColdOnlySummary.Groups[2].Value
    $iq1ColdOnlyMainVram = [UInt64]$iq1ColdOnlySummary.Groups[3].Value
    $iq1ColdOnlyMainSnapshotRam = [UInt64]$iq1ColdOnlySummary.Groups[4].Value
    $iq1ColdOnlyMainTierRam = [UInt64]$iq1ColdOnlySummary.Groups[5].Value
    $iq1ColdOnlyMainSsdCold = [UInt64]$iq1ColdOnlySummary.Groups[6].Value
    $iq1ColdOnlyRamHits = [UInt64]$iq1ColdOnlySummary.Groups[7].Value
    $iq1ColdOnlyEligible = [UInt64]$iq1ColdOnlySummary.Groups[8].Value
    $iq1ColdOnlySubstitutions = [UInt64]$iq1ColdOnlySummary.Groups[9].Value
    $iq1ColdOnlyFallbackAllMain = [UInt64]$iq1ColdOnlySummary.Groups[10].Value
    $iq1ColdOnlySkippedIq1Miss = [UInt64]$iq1ColdOnlySummary.Groups[11].Value
    $iq1ColdOnlyUncertain = [UInt64]$iq1ColdOnlySummary.Groups[12].Value
    $iq1ColdOnlyFailures = [UInt64]$iq1ColdOnlySummary.Groups[13].Value
    if ($iq1ColdOnlyCalls -eq 0 -or
        $iq1ColdOnlyRoutes -gt (6 * $iq1ColdOnlyCalls) -or
        $iq1ColdOnlyEligible -lt $iq1ColdOnlySubstitutions -or
        ($iq1ColdOnlySubstitutions + $iq1ColdOnlyFallbackAllMain) -ne $iq1ColdOnlyCalls -or
        $iq1ColdOnlyFailures -ne 0) {
        throw "IQ1_S cold-only runtime invariants failed"
    }
    $iq1ColdOnlyRuntimeObserved = $true
} elseif ($iq1ColdOnlySummaryMatches.Count -ne 0) {
    throw "IQ1_S cold-only telemetry appeared while cold-only was disabled"
}
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
    $iq1MixedShapeInvalid = if ($Iq1SColdOnly) {
        $iq1MixedHotMain + $iq1MixedColdIq1 -ne (6 * $iq1MixedCalls) -or
        $iq1MixedColdIq1 -ne $iq1ColdOnlySubstitutions -or
        $iq1MixedPrimaryColdAvoided -ne $iq1ColdOnlySubstitutions -or
        $iq1MixedJoins -ne $iq1ColdOnlySubstitutions
    } else {
        $iq1MixedHotMain -ne (5 * $iq1MixedCalls) -or
        $iq1MixedColdIq1 -ne $iq1MixedCalls -or
        $iq1MixedPrimaryColdAvoided -ne $iq1MixedCalls -or
        $iq1MixedJoins -ne $iq1MixedCalls
    }
    $iq1MixedLastSelectionInvalid = if ($Iq1SColdOnly -and
        $iq1MixedColdIq1 -eq 0) {
        $iq1MixedLastLayer -ne [UInt32]::MaxValue -or
        $iq1MixedLastSlot -ne [UInt32]::MaxValue -or
        $iq1MixedLastExpert -ne -1
    } else {
        $iq1MixedLastSlot -ge 6 -or $iq1MixedLastExpert -lt 0
    }
    if ($iq1MixedCalls -eq 0 -or $iq1MixedShapeInvalid -or
        $iq1MixedFailures -ne 0 -or
        $iq1MixedLastSelectionInvalid) {
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
if ($Iq1Promotion) {
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
        $expectedPromotionSnapshotEvictions = if ($ComposePrefillMassOpenRouter) { [UInt64]0 } else { [UInt64]$Iq1PromotionProbationSlots }
        [UInt64]$iq1PromotionSuppressed =
            $iq1PromotionRow.skips_touches +
            $iq1PromotionRow.skips_weight +
            $iq1PromotionRow.skips_mass +
            $iq1PromotionRow.skips_request_budget +
            $iq1PromotionRow.skips_window_budget
        if ($iq1PromotionRow.requested_slots -ne [UInt64]$Iq1PromotionProbationSlots -or
            $iq1PromotionRow.reserved_slots -ne [UInt64]$Iq1PromotionProbationSlots -or
            $iq1PromotionRow.min_touches -ne $Iq1PromotionMinTouches -or
            [math]::Abs($iq1PromotionRow.min_weight - $Iq1PromotionMinWeight) -gt 0.000000000001 -or
            [math]::Abs($iq1PromotionRow.min_mass - $Iq1PromotionMinMass) -gt 0.000000000001 -or
            $iq1PromotionRow.request_budget -ne $Iq1PromotionRequestBudget -or
            $iq1PromotionRow.window_calls -ne $Iq1PromotionWindowCalls -or
            $iq1PromotionRow.window_budget -ne $Iq1PromotionWindowBudget -or
            ($ComposePrefillMassOpenRouter -and $iq1PromotionRow.reserve_strategy -ne "pre-reserved-open-router") -or
            $iq1PromotionRow.snapshot_evictions -ne $expectedPromotionSnapshotEvictions -or
            $iq1PromotionRow.cold_observed -le 0 -or
            ($iq1PromotionRow.cold_existing_2bit +
                $iq1PromotionRow.cold_gate_candidates) -le 0 -or
            $iq1PromotionRow.cold_gate_candidates -ne
                ($iq1PromotionRow.cold_to_2bit_ram +
                 $iq1PromotionSuppressed) -or
            $iq1PromotionRow.direct_ssd_to_vram_rejected -ne 0 -or
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

$gpuRoutesExpectedPrimarySelected = [UInt64](6 * $gpuRoutesCalls)
if ($iq1MixedPrimaryColdAvoided -gt $gpuRoutesExpectedPrimarySelected) {
    throw "IQ1_S mixed decode excluded more primary routes than the GPU resolver observed"
}
$gpuRoutesExpectedPrimarySelected -= $iq1MixedPrimaryColdAvoided
if ($SplitFused) {
    if (-not $gpuRoutesObserved -or $gpuRoutesCalls -le 0 -or
        -not $splitFusedObserved -or $splitFusedCalls -ne $gpuRoutesCalls) {
        throw "SplitFused was requested but fused calls were not observed on every GPU route call"
    }
    if (($splitFusedHits + $splitFusedMisses) -ne $gpuRoutesExpectedPrimarySelected) {
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
            $matchingPromotion = if ($Iq1Promotion) { $iq1PromotionRows[$tierLineIndex] } else { $null }
            $expectedSnapshotBackingEntries = [uint32]$matchingWrap.candidate
            if ($Iq1Promotion -and -not $ComposePrefillMassOpenRouter) {
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
        } elseif ($Iq1Promotion) {
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
    if (-not $Iq1Promotion) {
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
        ($ComposePrefillMassTiering -and
         $prefillMassDecodeEventCount -notin @(0, $requestCountExpected)) -or
        (-not $ComposePrefillMassTiering -and
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
    if ([math]::Abs($arenaCapMinAvailableGiB - $DynamicArenaMinAvailableGiB) -gt 0.0015) {
        throw "Dynamic arena cap measurement failed: observed min-available differs from requested value"
    }
    if ($arenaCapChosenBytes -gt $arenaCapRequestedBytes -or
        $arenaCapChosenSlots -gt $arenaCapRequestedSlots) {
        throw "Dynamic arena cap measurement failed: chosen arena exceeds requested arena"
    }
    if (-not $arenaCapCapped -and
        ($arenaCapChosenBytes -ne $arenaCapRequestedBytes -or
         $arenaCapChosenSlots -ne $arenaCapRequestedSlots)) {
        throw "Dynamic arena cap measurement failed: uncapped telemetry changed the requested arena"
    }
    if ($arenaCapChosenSlots -lt 1) {
        if ($arenaCapResult -ne "disabled" -or $arenaAllocatedBytes -ne 0 -or
            $arenaAllocatedSlots -ne 0) {
            throw "Dynamic arena cap measurement failed: zero-slot arena was not disabled"
        }
    } else {
        if ($arenaCapResult -ne "ready" -or
            $arenaAllocatedBytes -ne $arenaCapChosenBytes -or
            $arenaAllocatedSlots -ne $arenaCapChosenSlots) {
            throw "Dynamic arena cap measurement failed: ready allocation differs from chosen cap"
        }
    }
    if ($DynamicArenaMinAvailableGiB -gt 0.0 -and
        $arenaCapAvailableBeforeGiB -ge 0.0 -and
        $arenaCapChosenBytes -gt 0) {
        $arenaCapChosenGiB = [double]$arenaCapChosenBytes / 1GB
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
    iq1_promotion_requested = [bool]$Iq1Promotion
    iq1_promotion_probation_slots_requested = $Iq1PromotionProbationSlots
    iq1_promotion_min_touches_requested = $Iq1PromotionMinTouches
    iq1_promotion_min_weight_requested = $Iq1PromotionMinWeight
    iq1_promotion_min_mass_requested = $Iq1PromotionMinMass
    iq1_promotion_request_budget_requested = $Iq1PromotionRequestBudget
    iq1_promotion_window_calls_requested = $Iq1PromotionWindowCalls
    iq1_promotion_window_budget_requested = $Iq1PromotionWindowBudget
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
    -not $outerQualitySuiteMember)
$sotaEligible = [bool]($qualityEligible -and -not $SkipSystemQuiescencePreflight)
$contaminationReason = ""
if (-not $qualityEligible) {
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
    prompt_sha256 = $promptHash
    system_prompt = $SystemPrompt
    system_prompt_sha256 = $systemPromptHash
    warmup_prompt_sha256 = $(if ($Warmup) { $warmupPromptHash } else { "" })
    expected_content_sha256 = if ($ExpectedContentSHA256) { $ExpectedContentSHA256.ToLowerInvariant() } else { "" }
    expected_warmup_content_sha256 = if ($ExpectedWarmupContentSHA256) { $ExpectedWarmupContentSHA256.ToLowerInvariant() } else { "" }
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
    iq1_s_ram_cache_deferred_unused = $iq1SRamCacheDeferredUnused
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
    iq1_s_cold_only_requested = [bool]$Iq1SColdOnly
    iq1_s_cold_only_runtime_observed = $iq1ColdOnlyRuntimeObserved
    iq1_s_cold_only_calls = $iq1ColdOnlyCalls
    iq1_s_cold_only_routes = $iq1ColdOnlyRoutes
    iq1_s_cold_only_main_vram = $iq1ColdOnlyMainVram
    iq1_s_cold_only_main_snapshot_ram = $iq1ColdOnlyMainSnapshotRam
    iq1_s_cold_only_main_tier_ram = $iq1ColdOnlyMainTierRam
    iq1_s_cold_only_main_ssd_cold = $iq1ColdOnlyMainSsdCold
    iq1_s_cold_only_ram_hits = $iq1ColdOnlyRamHits
    iq1_s_cold_only_eligible = $iq1ColdOnlyEligible
    iq1_s_cold_only_substitutions = $iq1ColdOnlySubstitutions
    iq1_s_cold_only_fallback_all_main = $iq1ColdOnlyFallbackAllMain
    iq1_s_cold_only_skipped_iq1_miss = $iq1ColdOnlySkippedIq1Miss
    iq1_s_cold_only_uncertain = $iq1ColdOnlyUncertain
    iq1_s_cold_only_failures = $iq1ColdOnlyFailures
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
    iq1_promotion_requested = [bool]$Iq1Promotion
    iq1_promotion_probation_slots_requested = $Iq1PromotionProbationSlots
    iq1_promotion_min_touches_requested = $Iq1PromotionMinTouches
    iq1_promotion_min_weight_requested = $Iq1PromotionMinWeight
    iq1_promotion_min_mass_requested = $Iq1PromotionMinMass
    iq1_promotion_request_budget_requested = $Iq1PromotionRequestBudget
    iq1_promotion_window_calls_requested = $Iq1PromotionWindowCalls
    iq1_promotion_window_budget_requested = $Iq1PromotionWindowBudget
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
    iq1_s_ram_cache_deferred_unused = $iq1SRamCacheDeferredUnused
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
    iq1_s_cold_only_requested = [bool]$Iq1SColdOnly
    iq1_s_cold_only_runtime_observed = $iq1ColdOnlyRuntimeObserved
    iq1_s_cold_only_calls = $iq1ColdOnlyCalls
    iq1_s_cold_only_routes = $iq1ColdOnlyRoutes
    iq1_s_cold_only_main_vram = $iq1ColdOnlyMainVram
    iq1_s_cold_only_main_snapshot_ram = $iq1ColdOnlyMainSnapshotRam
    iq1_s_cold_only_main_tier_ram = $iq1ColdOnlyMainTierRam
    iq1_s_cold_only_main_ssd_cold = $iq1ColdOnlyMainSsdCold
    iq1_s_cold_only_ram_hits = $iq1ColdOnlyRamHits
    iq1_s_cold_only_eligible = $iq1ColdOnlyEligible
    iq1_s_cold_only_substitutions = $iq1ColdOnlySubstitutions
    iq1_s_cold_only_fallback_all_main = $iq1ColdOnlyFallbackAllMain
    iq1_s_cold_only_skipped_iq1_miss = $iq1ColdOnlySkippedIq1Miss
    iq1_s_cold_only_uncertain = $iq1ColdOnlyUncertain
    iq1_s_cold_only_failures = $iq1ColdOnlyFailures
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
    iq1_promotion_requested = [bool]$Iq1Promotion
    iq1_promotion_probation_slots_requested = $Iq1PromotionProbationSlots
    iq1_promotion_requested_config = [pscustomobject]@{
        probation_slots = $Iq1PromotionProbationSlots
        min_touches = $Iq1PromotionMinTouches
        min_weight = $Iq1PromotionMinWeight
        min_mass = $Iq1PromotionMinMass
        request_budget = $Iq1PromotionRequestBudget
        window_calls = $Iq1PromotionWindowCalls
        window_budget = $Iq1PromotionWindowBudget
    }
    iq1_promotion_min_touches_requested = $Iq1PromotionMinTouches
    iq1_promotion_min_weight_requested = $Iq1PromotionMinWeight
    iq1_promotion_min_mass_requested = $Iq1PromotionMinMass
    iq1_promotion_request_budget_requested = $Iq1PromotionRequestBudget
    iq1_promotion_window_calls_requested = $Iq1PromotionWindowCalls
    iq1_promotion_window_budget_requested = $Iq1PromotionWindowBudget
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
    dynamic_arena_cap_capped = $arenaCapCapped
    dynamic_arena_cap_result = $arenaCapResult
    dynamic_arena_cap_reason = $arenaCapReason
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
Write-Host ("prefill VRAM seed req/obs/result/layers/entries/GiB/sec/failures: " + $PrefillVramSeedPerLayer + " / " + $prefillVramSeedObserved + " / " + $prefillVramSeedResult + " / " + $prefillVramSeedLayers + " / " + $prefillVramSeedEntries + " / " + [math]::Round($prefillVramSeedBytes / 1GB, 3) + " / " + $prefillVramSeedSeconds + " / " + $prefillVramSeedFailures)
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
Write-Host ("IQ1_S RAM cache req/observed/deferred-unused/capacity/count/hits/misses/evictions/failures: " + $Iq1SRamCacheGiB + " / " + $iq1SRamCacheRuntimeObserved + " / " + $iq1SRamCacheDeferredUnused + " / " + $iq1SRamCacheCapacity + " / " + $iq1SRamCacheCount + " / " + $iq1SRamCacheHits + " / " + $iq1SRamCacheMisses + " / " + $iq1SRamCacheEvictions + " / " + $iq1SRamCacheFailures)
Write-Host ("IQ1_S RAM cache hit-rate/SSD GiB/H2D GiB/SSD avoided GiB: " + [math]::Round($iq1SRamCacheHitRate, 4) + " / " + [math]::Round($iq1SRamCacheSsdBytes / 1GB, 3) + " / " + [math]::Round($iq1SRamCacheH2dBytes / 1GB, 3) + " / " + [math]::Round($iq1SRamCacheSsdAvoidedBytes / 1GB, 3))
Write-Host ("IQ1_S full preload pageable/frozen/layers/entries/SSD GiB/read-calls/ms: " + [bool]$Iq1SRamCachePageable + " / " + $iq1SRamCachePreloadFrozen + " / " + $iq1SRamCachePreloadLayers + " / " + $iq1SRamCachePreloadEntries + " / " + [math]::Round($iq1SRamCachePreloadSsdBytes / 1GB, 3) + " / " + $iq1SRamCachePreloadReadCalls + " / " + $iq1SRamCachePreloadMs)
Write-Host ("IQ1_S VRAM cache req/observed/capacity/count/hits/misses/evictions/failures: " + $Iq1SVramCachePerLayer + " / " + $iq1SVramCacheRuntimeObserved + " / " + $iq1SVramCacheCapacity + " / " + $iq1SVramCacheCount + " / " + $iq1SVramCacheHits + " / " + $iq1SVramCacheMisses + " / " + $iq1SVramCacheEvictions + " / " + $iq1SVramCacheFailures)
Write-Host ("IQ1_S VRAM cache hit-rate/H2D GiB: " + $(if (($iq1SVramCacheHits + $iq1SVramCacheMisses) -gt 0) { [math]::Round([double]$iq1SVramCacheHits / [double]($iq1SVramCacheHits + $iq1SVramCacheMisses), 4) } else { 0 }) + " / " + [math]::Round($iq1SVramCacheH2dBytes / 1GB, 3))
Write-Host ("IQ1_S mixed calls/hot-main/cold-IQ1/primary-avoided/joins/failures: " + $iq1MixedCalls + " / " + $iq1MixedHotMain + " / " + $iq1MixedColdIq1 + " / " + $iq1MixedPrimaryColdAvoided + " / " + $iq1MixedJoins + " / " + $iq1MixedFailures)
Write-Host ("IQ1_S mixed GPU plan requested/observed/calls/wait-ms/failures: " + [bool]$Iq1SMixedGpuPlan + " / " + $iq1MixedGpuPlanRuntimeObserved + " / " + $iq1MixedGpuPlanCalls + " / " + $iq1MixedGpuPlanWaitMs + " / " + $iq1MixedGpuPlanFailures)
Write-Host ("IQ1 promotion gate config min-touches/min-weight/min-mass/request-budget/window-calls/window-budget: " + $iq1PromotionObservedMinTouches + " / " + $iq1PromotionObservedMinWeight + " / " + $iq1PromotionObservedMinMass + " / " + $iq1PromotionObservedRequestBudget + " / " + $iq1PromotionObservedWindowCalls + " / " + $iq1PromotionObservedWindowBudget)
Write-Host ("IQ1 promotion gate candidates weight>=.001/.002/.005/.010 skips touches/weight/mass/request/window: " + $iq1PromotionColdGateCandidates + " / " + $iq1PromotionWeightGe001 + " / " + $iq1PromotionWeightGe002 + " / " + $iq1PromotionWeightGe005 + " / " + $iq1PromotionWeightGe010 + " / " + $iq1PromotionSkipsTouches + " / " + $iq1PromotionSkipsWeight + " / " + $iq1PromotionSkipsMass + " / " + $iq1PromotionSkipsRequestBudget + " / " + $iq1PromotionSkipsWindowBudget)
Write-Host ("IQ1 promotion requested/observed/lines/slots/cold/existing2bit/to2bitram/ssd-GiB/ssd-sec/ssd-Bps/direct-rejected/backing-reclaims/failures: " + [bool]$Iq1Promotion + " / " + $iq1PromotionRuntimeObserved + " / " + $iq1PromotionLineCount + " / " + $Iq1PromotionProbationSlots + " / " + $iq1PromotionColdObserved + " / " + $iq1PromotionColdExisting2Bit + " / " + $iq1PromotionColdTo2BitRam + " / " + [math]::Round($iq1Promotion2BitSsdBytes / 1GB, 3) + " / " + $iq1Promotion2BitSsdSeconds + " / " + [math]::Round($iq1Promotion2BitSsdBytesPerSecond, 3) + " / " + $iq1PromotionDirectSsdToVramRejected + " / " + $iq1PromotionProbationBackingReclaims + " / " + $iq1PromotionFailures)
Write-Host ("IQ1_S profile/no-main-sync/packed-H2D: " + [bool]$Iq1SProfile + " / " + [bool]$Iq1SNoMainSync + " / " + [bool]$Iq1SPackedH2D)
Write-Host ("IQ1_S profile SSD reads/ms H2D batches/copies/enqueue-ms/syncs/sync-ms: " + $iq1ProfileSsdReadCalls + " / " + $iq1ProfileSsdReadMs + " / " + $iq1ProfileH2dBatches + " / " + $iq1ProfileH2dCopies + " / " + $iq1ProfileH2dEnqueueMs + " / " + $iq1ProfileH2dSyncs + " / " + $iq1ProfileH2dSyncMs)
Write-Host ("IQ1_S mixed profile calls/router-D2H/meta-H2D/main-submit/main-sync/cold-submit/join ms: " + $iq1MixedProfileCalls + " / " + $iq1MixedProfileRouterD2hMs + " / " + $iq1MixedProfileMetadataH2dMs + " / " + $iq1MixedProfileMainSubmitMs + " / " + $iq1MixedProfileMainSyncMs + " / " + $iq1MixedProfileColdSubmitMs + " / " + $iq1MixedProfileJoinSubmitMs)
Write-Host ("last_sel_line : " + $lastSel)
Write-Host "=================================================="
} finally {
    if ($null -ne $modelLockStream) {
        try { $modelLockStream.Dispose() } catch {}
    }
    if ($null -ne $iq1SSidecarLockStream) {
        try { $iq1SSidecarLockStream.Dispose() } catch {}
    }
    if ($measurementLockAcquired) {
        try { $measurementMutex.ReleaseMutex() } catch {}
    }
    $measurementMutex.Dispose()
}
