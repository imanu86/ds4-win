# G105 IQ1_S full-resident structural gate (PowerShell 5.1, ASCII).
param(
    [switch]$StaticCheckOnly,
    [switch]$Resume,
    [ValidateRange(600, 86400)][int]$TimeoutSec = 7200
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$harness = Join-Path $root "g7_measure.ps1"
$staticTest = Join-Path $root "tests\test_g105_static_contract.ps1"
$outdir = Join-Path $root "g7_runs"
$tag = "g105_iq1_full_resident_n1"
$resultPath = Join-Path $outdir ("g7_" + $tag + "_result.json")
$summaryPath = Join-Path $outdir "g105_iq1_full_resident_result.json"
$model = "C:\ds4-models\ds4-2bit.gguf"
$modelSHA = "efc7ed607ff27076e3e501fc3fefefa33c0ed8cf1eff483a2b7fdc0c2e616668"
$sidecar = "C:\ds4-models\DeepSeek-V4-Flash-IQ1_S-XL.gguf"
$sidecarSHA = "b049d1eb34c068f19ab007b33c22a7d758b578bf2b10d9276e79654f85d35047"
[UInt64]$sidecarBytes = 61540805344
$prompt = "Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document."
$expectedContentSHA = "4aaf0f0813f4cb15ac21a88f195f4f7d2c2af797e81524935e22eea60603c6b1"
[UInt64]$expectedSlots = 10240
[UInt64]$expectedSlotBytes = 4915200
[UInt64]$expectedResidentBytes = 50331648000
[UInt64]$expectedReadCalls = 30720

function Get-G105Property([object]$Object, [string]$Name, $Default = $null) {
    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) {
        return $Default
    }
    $Object.PSObject.Properties[$Name].Value
}

function Assert-G105StaticContract {
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
        -File $staticTest | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "G105 static contract failed" }
}

function Assert-G105HostPreflight {
    $os = Get-CimInstance Win32_OperatingSystem
    $freeGiB = [double]$os.FreePhysicalMemory / 1MB
    if ($freeGiB -lt 54.0) {
        throw ("G105 requires at least 54 GiB free before launch; observed " +
            [math]::Round($freeGiB, 3))
    }
    $ds4 = @(Get-Process -Name ds4_server -ErrorAction SilentlyContinue)
    if ($ds4.Count -ne 0) { throw "G105 refuses to overlap an existing DS4" }
}

function New-G105Args {
    @(
        "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", $harness,
        "-Tag", $tag,
        "-GateKind", "structural-safety",
        "-ModelPath", $model,
        "-ExpectedModelSHA256", $modelSHA,
        "-ReuseVerifiedModelReceipt",
        "-Prompt", $prompt,
        "-ExpectedContentSHA256", $expectedContentSHA,
        "-MaxTokens", "64",
        "-Repeats", "1",
        "-Context", "256",
        "-BudgetGB", "2",
        "-ReserveMB", "1024",
        "-DisableQ8F16Cache",
        "-EmbedRowStaging",
        "-ExpertCacheN", "320",
        "-ExpertCacheReserveGB", "0.125",
        "-ExpertCachePolicy", "lru",
        "-GpuResidentRoutes",
        "-RouteNoDefaultSync",
        "-SplitFused",
        "-MinimumAvailableGiB", "54",
        "-RuntimeMinimumAvailableGiB", "1",
        "-RuntimeMaximumDiskQueueLength", "8",
        "-RuntimeContaminationSamples", "3",
        "-QuiescenceCooldownSec", "10",
        "-TimeoutSec", ([string]$TimeoutSec),
        "-Iq1SExpertSidecar", $sidecar,
        "-ExpectedIq1SExpertSidecarSHA256", $sidecarSHA,
        "-ExpectedIq1SExpertSidecarBytes", ([string]$sidecarBytes),
        "-ReuseVerifiedIq1SReceipt",
        "-Iq1SLayerFirst", "3",
        "-Iq1SLayerLast", "42",
        "-Iq1SMixedColdOne",
        "-Iq1SMixedGpuPlan",
        "-Iq1SRamCacheGiB", "46.875",
        "-Iq1SRamCachePageable",
        "-Iq1SRamCachePreloadAll",
        "-Iq1SProfile"
    )
}

function Assert-G105Result([object]$Result) {
    $content = @($Result.results)[0]
    if ([string]$Result.tag -ne $tag -or
        [int]$Result.server_exit_code -ne 0 -or
        [string]$Result.model_sha256 -ine $modelSHA -or
        [string]$Result.iq1_s_sidecar_sha256 -ine $sidecarSHA -or
        [string]$content.content_sha256 -ine $expectedContentSHA -or
        -not [bool]$Result.outputs_identical -or
        -not [bool]$Result.iq1_s_mixed_runtime_observed -or
        -not [bool]$Result.iq1_s_mixed_gpu_plan_runtime_observed -or
        -not [bool]$Result.iq1_s_ram_cache_pageable_requested -or
        -not [bool]$Result.iq1_s_ram_cache_preload_all_requested -or
        -not [bool]$Result.iq1_s_ram_cache_preload_frozen -or
        [UInt64]$Result.iq1_s_ram_cache_allocated_bytes -ne
            $expectedResidentBytes -or
        [UInt64]$Result.iq1_s_ram_cache_capacity -ne $expectedSlots -or
        [UInt64]$Result.iq1_s_ram_cache_count -ne $expectedSlots -or
        [UInt64]$Result.iq1_s_ram_cache_slot_bytes -ne $expectedSlotBytes -or
        [UInt64]$Result.iq1_s_ram_cache_hits -eq 0 -or
        [UInt64]$Result.iq1_s_ram_cache_misses -ne 0 -or
        [UInt64]$Result.iq1_s_ram_cache_evictions -ne 0 -or
        [UInt64]$Result.iq1_s_ram_cache_ssd_bytes -ne 0 -or
        [UInt64]$Result.iq1_s_ram_cache_failures -ne 0 -or
        [UInt64]$Result.iq1_s_ram_cache_preload_layers -ne 40 -or
        [UInt64]$Result.iq1_s_ram_cache_preload_entries -ne $expectedSlots -or
        [UInt64]$Result.iq1_s_ram_cache_preload_ssd_bytes -ne
            $expectedResidentBytes -or
        [UInt64]$Result.iq1_s_ram_cache_preload_read_calls -ne
            $expectedReadCalls -or
        [double]$Result.iq1_s_ram_cache_preload_ms -le 0.0 -or
        [bool](Get-G105Property $Result "contamination_abort_observed" $true)) {
        throw "G105 full-resident runtime contract mismatch"
    }
    if ([bool](Get-G105Property $Result "quality_eligible" $true) -or
        [string](Get-G105Property $Result "contamination_reason" "") -ne
            "structural-safety-gate-not-quality-eligible") {
        throw "G105 structural-only eligibility contract mismatch"
    }
}

Assert-G105StaticContract
if ($StaticCheckOnly) {
    [ordered]@{
        schema = "g105_iq1_full_resident_static_v1"
        static_check_only = $true
        structural_only = $true
        expected_resident_bytes = $expectedResidentBytes
        expected_slots = $expectedSlots
    } | ConvertTo-Json
    exit 0
}

Assert-G105HostPreflight
New-Item -ItemType Directory -Force -Path $outdir | Out-Null
if (-not ($Resume -and (Test-Path -LiteralPath $resultPath -PathType Leaf))) {
    $args = @(New-G105Args)
    & powershell.exe @args | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "G105 harness failed" }
}
$result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
Assert-G105Result $result

$summary = [ordered]@{
    schema = "g105_iq1_full_resident_v1"
    measured_utc = [DateTime]::UtcNow.ToString("o")
    structural_only = $true
    performance_claim_allowed = $false
    quality_claim_allowed = $false
    result_path = $resultPath
    result_sha256 = (Get-FileHash -LiteralPath $resultPath -Algorithm SHA256).Hash.ToLowerInvariant()
    exact_content_sha256 = [string]@($result.results)[0].content_sha256
    cache = [ordered]@{
        allocated_bytes = [UInt64]$result.iq1_s_ram_cache_allocated_bytes
        slots = [UInt64]$result.iq1_s_ram_cache_count
        hits = [UInt64]$result.iq1_s_ram_cache_hits
        decode_misses = [UInt64]$result.iq1_s_ram_cache_misses
        decode_ssd_bytes = [UInt64]$result.iq1_s_ram_cache_ssd_bytes
        preload_ssd_bytes = [UInt64]$result.iq1_s_ram_cache_preload_ssd_bytes
        preload_read_calls = [UInt64]$result.iq1_s_ram_cache_preload_read_calls
        preload_ms = [double]$result.iq1_s_ram_cache_preload_ms
        h2d_bytes = [UInt64]$result.iq1_s_ram_cache_h2d_bytes
        failures = [UInt64]$result.iq1_s_ram_cache_failures
    }
}
$summary | ConvertTo-Json -Depth 6 |
    Set-Content -LiteralPath $summaryPath -Encoding UTF8
$summary | ConvertTo-Json -Depth 6
