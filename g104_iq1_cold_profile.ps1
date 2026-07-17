# G104 IQ1_S cold-path structural profile (PowerShell 5.1, ASCII).
param(
    [switch]$StaticCheckOnly,
    [switch]$Resume,
    [ValidateRange(600, 86400)][int]$TimeoutSec = 7200
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$harness = Join-Path $root "g7_measure.ps1"
$outdir = Join-Path $root "g7_runs"
$tag = "g104_iq1_cold_profile_n1"
$resultPath = Join-Path $outdir ("g7_" + $tag + "_result.json")
$summaryPath = Join-Path $outdir "g104_iq1_cold_profile_result.json"
$model = "C:\ds4-models\ds4-2bit.gguf"
$modelSHA = "efc7ed607ff27076e3e501fc3fefefa33c0ed8cf1eff483a2b7fdc0c2e616668"
$sidecar = "C:\ds4-models\DeepSeek-V4-Flash-IQ1_S-XL.gguf"
$sidecarSHA = "b049d1eb34c068f19ab007b33c22a7d758b578bf2b10d9276e79654f85d35047"
[UInt64]$sidecarBytes = 61540805344
$prompt = "Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document."
$promptSHA = "38f6ec5ee5403f59dd2418eb5d9a5a94a0f0da19df015060383bb1ae46003bb6"

function Get-G104StringSHA256([string]$Value) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
        ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace "-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Get-G104Property([object]$Object, [string]$Name, $Default = $null) {
    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) {
        return $Default
    }
    $Object.PSObject.Properties[$Name].Value
}

function Assert-G104StaticContract {
    if (-not (Test-Path -LiteralPath $harness -PathType Leaf)) {
        throw "G104 harness missing"
    }
    if ((Get-G104StringSHA256 $prompt) -ne $promptSHA) {
        throw "G104 prompt hash mismatch"
    }
    if ($model -like (([char]68) + ":\*") -or
        $sidecar -like (([char]68) + ":\*")) {
        throw "G104 benchmark inputs must stay on C:"
    }
    $harnessText = Get-Content -LiteralPath $harness -Raw
    foreach ($parameter in @(
        "GateKind", "ReuseVerifiedModelReceipt", "Iq1SExpertSidecar",
        "ExpectedIq1SExpertSidecarSHA256", "ExpectedIq1SExpertSidecarBytes",
        "ReuseVerifiedIq1SReceipt", "Iq1SMixedColdOne",
        "Iq1SMixedGpuPlan", "Iq1SRamCacheGiB", "Iq1SProfile",
        "SplitFused", "RuntimeMinimumAvailableGiB")) {
        if ($harnessText -notmatch ("\$" + [regex]::Escape($parameter) +
            "(\s|=|,|\))")) {
            throw "G104 harness lacks -$parameter"
        }
    }
}

function New-G104Args {
    @(
        "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", $harness,
        "-Tag", $tag,
        "-GateKind", "structural-safety",
        "-ModelPath", $model,
        "-ExpectedModelSHA256", $modelSHA,
        "-ReuseVerifiedModelReceipt",
        "-Prompt", $prompt,
        "-MaxTokens", "64",
        "-Repeats", "1",
        "-Context", "256",
        "-BudgetGB", "2",
        "-ReserveMB", "1024",
        "-DynamicArenaGiB", "30",
        "-ArenaWrapTrustWorkerChecksum",
        "-ArenaWrapSourceParts",
        "-ArenaWrapUnlockSourceRanges",
        "-ArenaWrapUnlockWaveGiB", "4",
        "-DisableQ8F16Cache",
        "-EmbedRowStaging",
        "-ReapPrefetchThreads", "8",
        "-PrefillMassWrap",
        "-ComposePrefillMassTiering",
        "-ExpertCacheN", "320",
        "-ExpertCacheReserveGB", "0.125",
        "-ExpertCachePolicy", "lru",
        "-GpuResidentRoutes",
        "-RouteNoDefaultSync",
        "-SplitFused",
        "-ExpertTiering", "enforce",
        "-ExpertTierPolicy", "mass-lfru",
        "-ExpertTierClockCalls", "430",
        "-ExpertTierReplacementBudget", "32",
        "-ExpertTierMinFrequency", "3",
        "-ExpertTierHysteresis", "1.25",
        "-QuiescenceCooldownSec", "90",
        "-RuntimeMinimumAvailableGiB", "1",
        "-RuntimeMaximumDiskQueueLength", "8",
        "-RuntimeContaminationSamples", "3",
        "-TimeoutSec", ([string]$TimeoutSec),
        "-Iq1SExpertSidecar", $sidecar,
        "-ExpectedIq1SExpertSidecarSHA256", $sidecarSHA,
        "-ExpectedIq1SExpertSidecarBytes", ([string]$sidecarBytes),
        "-ReuseVerifiedIq1SReceipt",
        "-Iq1SLayerFirst", "3",
        "-Iq1SLayerLast", "42",
        "-Iq1SMixedColdOne",
        "-Iq1SMixedGpuPlan",
        "-Iq1SRamCacheGiB", "0.5",
        "-Iq1SProfile"
    )
}

function Assert-G104Result([object]$Result) {
    if ([string]$Result.tag -ne $tag -or
        [int]$Result.server_exit_code -ne 0 -or
        [string]$Result.model_sha256 -ine $modelSHA -or
        [string]$Result.iq1_s_sidecar_sha256 -ine $sidecarSHA -or
        -not [bool]$Result.iq1_s_profile_requested -or
        -not [bool]$Result.iq1_s_mixed_runtime_observed -or
        -not [bool]$Result.iq1_s_mixed_gpu_plan_runtime_observed -or
        [UInt64]$Result.iq1_s_mixed_calls -eq 0 -or
        [UInt64]$Result.iq1_s_mixed_failures -ne 0 -or
        [UInt64]$Result.iq1_s_ram_cache_failures -ne 0 -or
        [UInt64]$Result.iq1_s_mixed_gpu_plan_failures -ne 0 -or
        [UInt64]$Result.expert_tiering.ssd_bytes -ne 0 -or
        [bool]$Result.iq1_promotion_requested -or
        [bool]$Result.route_packed_copy_requested -or
        [bool]$Result.iq1_s_packed_h2d_requested) {
        throw "G104 runtime contract mismatch"
    }
    if ([UInt64]$Result.iq1_s_profile_ssd_read_calls -eq 0 -or
        [double]$Result.iq1_s_profile_ssd_read_ms -le 0.0 -or
        [UInt64]$Result.iq1_s_profile_h2d_batches -eq 0 -or
        [UInt64]$Result.iq1_s_profile_h2d_copies -eq 0 -or
        [double]$Result.iq1_s_profile_h2d_enqueue_ms -le 0.0 -or
        [UInt64]$Result.iq1_s_profile_h2d_syncs -eq 0 -or
        [double]$Result.iq1_s_profile_h2d_sync_ms -le 0.0 -or
        [UInt64]$Result.iq1_s_mixed_profile_calls -ne
            [UInt64]$Result.iq1_s_mixed_calls) {
        throw "G104 profile counters are missing or inconsistent"
    }
    if ([bool](Get-G104Property $Result "quality_eligible" $true) -or
        [string](Get-G104Property $Result "contamination_reason" "") -ne
            "structural-safety-gate-not-quality-eligible") {
        throw "G104 structural-only eligibility contract mismatch"
    }
}

Assert-G104StaticContract
if ($StaticCheckOnly) {
    [ordered]@{
        schema = "g104_iq1_cold_profile_static_v1"
        static_check_only = $true
        structural_profile_only = $true
        g103_stack_preserved = $true
        iq1_profile_only_delta = $true
    } | ConvertTo-Json
    exit 0
}

New-Item -ItemType Directory -Force -Path $outdir | Out-Null
if (-not ($Resume -and (Test-Path -LiteralPath $resultPath -PathType Leaf))) {
    $args = @(New-G104Args)
    & powershell.exe @args | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "G104 profile harness failed"
    }
}
$result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
Assert-G104Result $result

$summary = [ordered]@{
    schema = "g104_iq1_cold_profile_v1"
    measured_utc = [DateTime]::UtcNow.ToString("o")
    structural_only = $true
    performance_claim_allowed = $false
    quality_claim_allowed = $false
    result_path = $resultPath
    result_sha256 = (Get-FileHash -LiteralPath $resultPath -Algorithm SHA256).Hash.ToLowerInvariant()
    mixed_calls = [UInt64]$result.iq1_s_mixed_calls
    cache_hits = [UInt64]$result.iq1_s_ram_cache_hits
    cache_misses = [UInt64]$result.iq1_s_ram_cache_misses
    iq1_ssd_bytes = [UInt64]$result.iq1_s_ram_cache_ssd_bytes
    profile = [ordered]@{
        ssd_read_calls = [UInt64]$result.iq1_s_profile_ssd_read_calls
        ssd_read_ms = [double]$result.iq1_s_profile_ssd_read_ms
        h2d_batches = [UInt64]$result.iq1_s_profile_h2d_batches
        h2d_copies = [UInt64]$result.iq1_s_profile_h2d_copies
        h2d_enqueue_ms = [double]$result.iq1_s_profile_h2d_enqueue_ms
        h2d_syncs = [UInt64]$result.iq1_s_profile_h2d_syncs
        h2d_sync_ms = [double]$result.iq1_s_profile_h2d_sync_ms
        router_d2h_ms = [double]$result.iq1_s_mixed_profile_router_d2h_ms
        metadata_h2d_ms = [double]$result.iq1_s_mixed_profile_metadata_h2d_ms
        main_submit_ms = [double]$result.iq1_s_mixed_profile_main_submit_ms
        main_sync_ms = [double]$result.iq1_s_mixed_profile_main_sync_ms
        cold_submit_ms = [double]$result.iq1_s_mixed_profile_cold_submit_ms
        join_submit_ms = [double]$result.iq1_s_mixed_profile_join_submit_ms
    }
}
$summary | ConvertTo-Json -Depth 6 |
    Set-Content -LiteralPath $summaryPath -Encoding UTF8
$summary | ConvertTo-Json -Depth 6
