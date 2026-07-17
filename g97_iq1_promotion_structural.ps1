# G97 IQ1_S promotion probation structural smoke (PowerShell 5.1, ASCII).
param(
    [switch]$StaticCheckOnly,
    [switch]$Resume,
    [ValidateRange(1, 512)][int]$PromotionSlots = 16
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$harness = Join-Path $root "g7_measure.ps1"
$buildRunner = Join-Path $root "g7_build.ps1"
$runtimeMonitor = Join-Path $root "g7_runtime_monitor.ps1"
$outdir = Join-Path $root "g7_runs"
$executable = Join-Path $root "build\Release\ds4_server.exe"
$buildManifest = Join-Path $root "build\Release\g7_build_manifest.json"

$model = "C:\ds4-models\ds4-2bit.gguf"
$expectedModelSHA256 =
    "efc7ed607ff27076e3e501fc3fefefa33c0ed8cf1eff483a2b7fdc0c2e616668"
$iq1Sidecar = "D:\ds4-models\DeepSeek-V4-Flash-IQ1_S-XL.gguf"
$expectedIq1SidecarSHA256 =
    "b049d1eb34c068f19ab007b33c22a7d758b578bf2b10d9276e79654f85d35047"
[UInt64]$expectedIq1SidecarBytes = 61540805344
$prompt = "Hi"
$tag = "g97_iq1_promotion_structural_n1"
$summaryPath = Join-Path $outdir "g97_iq1_promotion_structural_result.json"

function Get-G97SHA256 {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "G97 provenance file missing: $Path"
    }
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Test-G97HarnessParameter {
    param([Parameter(Mandatory=$true)][string]$ParameterName)
    $content = Get-Content -LiteralPath $harness -Raw
    return ($content -match ("\$" + [regex]::Escape($ParameterName) +
        "(\s|=|,|\))"))
}

function Assert-G97Property {
    param(
        [Parameter(Mandatory=$true)][object]$Object,
        [Parameter(Mandatory=$true)][string]$Name
    )
    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) {
        throw "G97 required field missing: $Name"
    }
}

function Assert-G97StaticContract {
    if (-not (Test-Path -LiteralPath $harness -PathType Leaf)) {
        throw "G97 harness missing: $harness"
    }
    if (-not (Test-Path -LiteralPath $runtimeMonitor -PathType Leaf)) {
        throw "G97 runtime monitor missing: $runtimeMonitor"
    }
    if (-not (Test-Path -LiteralPath $buildRunner -PathType Leaf)) {
        throw "G97 build runner missing: $buildRunner"
    }
    foreach ($parameter in @(
        "WarmupMaxTokens", "Repeats", "BudgetGB", "ReserveMB",
        "DynamicArenaGiB", "ArenaWrapTrustWorkerChecksum",
        "ArenaWrapSourceParts", "PrefillMassWrap",
        "ComposePrefillMassTiering", "ComposePrefillMassOpenRouter",
        "ComposePrefillMassReserveSlots",
        "DisableQ8F16Cache",
        "EmbedRowStaging", "ExpertCacheN", "ExpertCacheReserveGB",
        "ExpertCachePolicy", "ExpertTiering", "ExpertTierPolicy",
        "ExpertTierClockCalls", "ExpertTierReplacementBudget",
        "ExpertTierMinFrequency", "ExpertTierHysteresis",
        "GpuResidentRoutes", "RouteNoDefaultSync", "SplitFused",
        "ExpectedModelSHA256", "ReuseVerifiedModelReceipt",
        "Iq1SExpertSidecar",
        "ExpectedIq1SExpertSidecarSHA256",
        "ExpectedIq1SExpertSidecarBytes", "ReuseVerifiedIq1SReceipt",
        "Iq1SLayerFirst",
        "Iq1SLayerLast", "Iq1SMixedColdOne", "Iq1SMixedGpuPlan",
        "Iq1Promotion", "Iq1PromotionProbationSlots",
        "Iq1SRamCacheGiB", "GateKind", "SkipSystemQuiescencePreflight",
        "QuiescenceCooldownSec")) {
        if (-not (Test-G97HarnessParameter -ParameterName $parameter)) {
            throw "Harness does not expose -$parameter; refusing to run."
        }
    }
    $harnessText = Get-Content -LiteralPath $harness -Raw
    foreach ($requiredText in @(
        "DS4_IQ1_PROMOTION_PROBATION_SLOTS",
        "DS4_CUDA_PREFILL_TIER_ROUTER",
        "DS4_CUDA_PREFILL_TIER_RESERVE_SLOTS",
        "compose_prefill_mass_open_router_requested",
        "compose_prefill_mass_reserve_slots_requested",
        "iq1-promotion",
        "requested_slots=(\d+) reserved_slots=",
        "promotion_2bit_ssd_seconds",
        "iq1_promotion_probation_backing_reclaims",
        "iq1_promotion_runtime_observed",
        "iq1_promotion_requests")) {
        if ($harnessText -notmatch [regex]::Escape($requiredText)) {
            throw "G97 harness static marker missing: $requiredText"
        }
    }
    if ($expectedModelSHA256 -notmatch '^[0-9a-f]{64}$' -or
        $expectedIq1SidecarSHA256 -notmatch '^[0-9a-f]{64}$' -or
        $expectedIq1SidecarBytes -le 0) {
        throw "G97 provenance constants are invalid."
    }
}

function Invoke-G97BuildOnce {
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
        -File $buildRunner
    if ($LASTEXITCODE -ne 0) { throw "G97 build failed" }
    if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
        throw "G97 executable missing after build"
    }
}

function New-G97Args {
    @(
        "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", $harness,
        "-Tag", $tag,
        "-MaxTokens", "8",
        "-Warmup", "-WarmupMaxTokens", "4",
        "-Repeats", "1",
        "-TimeoutSec", "1800",
        "-Prompt", $prompt,
        "-Context", "128",
        "-BudgetGB", "2", "-ReserveMB", "1024",
        "-DynamicArenaGiB", "12",
        "-ArenaWrapTrustWorkerChecksum",
        "-ArenaWrapSourceParts",
        "-DisableQ8F16Cache",
        "-EmbedRowStaging",
        "-PrefillMassWrap",
        "-ComposePrefillMassTiering",
        "-ComposePrefillMassOpenRouter",
        "-ComposePrefillMassReserveSlots", ([string]$PromotionSlots),
        "-ExpertCacheN", "320",
        "-ExpertCacheReserveGB", "0.125",
        "-ExpertCachePolicy", "lru",
        "-ExpertTiering", "enforce",
        "-ExpertTierPolicy", "mass-lfru",
        "-ExpertTierClockCalls", "430",
        "-ExpertTierReplacementBudget", "32",
        "-ExpertTierMinFrequency", "3",
        "-ExpertTierHysteresis", "1.25",
        "-GpuResidentRoutes",
        "-RouteNoDefaultSync",
        "-SplitFused",
        "-ModelPath", $model,
        "-ExpectedModelSHA256", $expectedModelSHA256,
        "-ReuseVerifiedModelReceipt",
        "-Iq1SExpertSidecar", $iq1Sidecar,
        "-ExpectedIq1SExpertSidecarSHA256", $expectedIq1SidecarSHA256,
        "-ExpectedIq1SExpertSidecarBytes", ([string]$expectedIq1SidecarBytes),
        "-ReuseVerifiedIq1SReceipt",
        "-Iq1SLayerFirst", "3",
        "-Iq1SLayerLast", "42",
        "-Iq1SMixedColdOne",
        "-Iq1SMixedGpuPlan",
        "-Iq1Promotion",
        "-Iq1PromotionProbationSlots", ([string]$PromotionSlots),
        "-Iq1SRamCacheGiB", "1",
        "-GateKind", "structural-safety",
        "-SkipSystemQuiescencePreflight",
        "-QuiescenceCooldownSec", "90"
    )
}

function Assert-G97RunContract {
    param([Parameter(Mandatory=$true)][object]$Result,
          [Parameter(Mandatory=$true)][object]$Provenance)

    foreach ($name in @(
        "server_exit_code", "model_sha256", "model_hash_method",
        "model_receipt_path", "model_receipt_sha256",
        "iq1_s_sidecar_sha256",
        "iq1_s_sidecar_hash_method",
        "iq1_s_sidecar_receipt_path",
        "iq1_s_sidecar_receipt_sha256",
        "iq1_s_mixed_runtime_observed",
        "iq1_s_mixed_gpu_plan_runtime_observed",
        "iq1_promotion_requested",
        "iq1_promotion_probation_slots_requested",
        "iq1_promotion_runtime_observed",
        "iq1_promotion_line_count",
        "iq1_promotion_requests",
        "iq1_promotion_probation_backing_reclaims",
        "iq1_promotion_2bit_ssd_seconds",
        "iq1_promotion_2bit_ssd_bytes_per_second",
        "compose_prefill_mass_open_router_requested",
        "compose_prefill_mass_reserve_slots_requested",
        "prefill_mass_wrap_candidate_entries",
        "system_quiescence_preflight", "quality_eligible",
        "sota_eligible", "contamination_reason",
        "expert_tiering")) {
        Assert-G97Property -Object $Result -Name $name
    }

    $tier = $Result.expert_tiering
    $expectedRequests = [int]$Result.request_count_expected
    if ([int]$Result.server_exit_code -ne 0 -or
        [string]$Result.gate_kind -ne "structural-safety" -or
        [int]$Result.repeats -ne 1 -or
        [int]$Result.requested_max_tokens -ne 8 -or
        [int]$Result.requested_warmup_max_tokens -ne 4 -or
        [int]$Result.context_requested -ne 128 -or
        [double]$Result.dynamic_arena_gib_requested -ne 12.0 -or
        [int]$Result.expert_cache_requested -ne 320 -or
        [bool]$Result.compose_prefill_mass_tiering_requested -ne $true -or
        [bool]$Result.compose_prefill_mass_open_router_requested -ne $true -or
        [int]$Result.compose_prefill_mass_reserve_slots_requested -ne $PromotionSlots -or
        [bool]$Result.system_quiescence_preflight.skipped -ne $true -or
        [bool]$Result.quality_eligible -ne $false -or
        [bool]$Result.sota_eligible -ne $false -or
        [string]$Result.contamination_reason -ne
            "structural-safety-gate-not-quality-eligible" -or
        [string]$Result.expert_tiering_requested -ne "enforce" -or
        [bool]$Result.iq1_s_mixed_cold_one -ne $true -or
        [bool]$Result.iq1_s_mixed_gpu_plan_requested -ne $true -or
        [bool]$Result.iq1_promotion_requested -ne $true -or
        [string]$Result.model_hash_method -ne "verified_receipt_reuse" -or
        [string]::IsNullOrWhiteSpace([string]$Result.model_receipt_path) -or
        [string]$Result.model_receipt_sha256 -notmatch '^[0-9a-fA-F]{64}$' -or
        [string]$Result.iq1_s_sidecar_hash_method -ne
            "verified_receipt_reuse" -or
        [string]::IsNullOrWhiteSpace(
            [string]$Result.iq1_s_sidecar_receipt_path) -or
        [string]$Result.iq1_s_sidecar_receipt_sha256 -notmatch
            '^[0-9a-fA-F]{64}$' -or
        [int]$Result.iq1_promotion_probation_slots_requested -ne
            $PromotionSlots -or
        [bool]$Result.iq1_promotion_runtime_observed -ne $true -or
        [int]$Result.iq1_promotion_line_count -ne $expectedRequests -or
        [UInt64]$Result.iq1_promotion_direct_ssd_to_vram_rejected -ne 0 -or
        [UInt64]$Result.iq1_promotion_failures -ne 0 -or
        [double]::IsNaN([double]$Result.iq1_promotion_2bit_ssd_seconds) -or
        [double]::IsInfinity([double]$Result.iq1_promotion_2bit_ssd_seconds) -or
        [double]$Result.iq1_promotion_2bit_ssd_seconds -lt 0.0 -or
        [double]::IsNaN([double]$Result.iq1_promotion_2bit_ssd_bytes_per_second) -or
        [double]::IsInfinity([double]$Result.iq1_promotion_2bit_ssd_bytes_per_second) -or
        [double]$Result.iq1_promotion_2bit_ssd_bytes_per_second -lt 0.0 -or
        [UInt64]$Result.iq1_promotion_cold_observed -le 0 -or
        [UInt64]$Result.iq1_promotion_cold_to_2bit_ram -le 0 -or
        [UInt64]$Result.iq1_promotion_probation_backing_reclaims -le 0 -or
        [UInt64]$Result.iq1_promotion_2bit_ssd_bytes -le 0 -or
        [double]$Result.iq1_promotion_2bit_ssd_seconds -le 0.0 -or
        [double]$Result.iq1_promotion_2bit_ssd_bytes_per_second -le 0.0 -or
        [UInt64]$tier.forbidden_cold_ssd_to_vram -ne 0 -or
        [UInt64]$tier.cold_to_vram -ne 0 -or
        [UInt64]$tier.failures -ne 0 -or
        [UInt64]$tier.snapshot_backing_entries -ne
            [UInt64]$Result.prefill_mass_wrap_candidate_entries -or
        [string]$Result.effective_ds4_environment.DS4_IQ1_PROMOTION_PROBATION_SLOTS -ne
            ([string]$PromotionSlots) -or
        [string]$Result.effective_ds4_environment.DS4_CUDA_PREFILL_TIER_ROUTER -ne
            "open" -or
        [string]$Result.effective_ds4_environment.DS4_CUDA_PREFILL_TIER_RESERVE_SLOTS -ne
            ([string]$PromotionSlots) -or
        $Result.executable_sha256 -ne $Provenance.executable_sha256 -or
        $Result.harness_sha256 -ne $Provenance.harness_sha256 -or
        $Result.runtime_monitor_harness_sha256 -ne
            $Provenance.runtime_monitor_harness_sha256) {
        throw "G97 structural contract mismatch"
    }

    if (@($Result.iq1_promotion_requests).Count -ne $expectedRequests) {
        throw "G97 promotion request row count mismatch"
    }
    [UInt64]$probationBackingReclaimsTotal = 0
    for ($i = 0; $i -lt $expectedRequests; $i++) {
        $row = $Result.iq1_promotion_requests[$i]
        Assert-G97Property -Object $row -Name "probation_backing_reclaims"
        Assert-G97Property -Object $row -Name "reserve_strategy"
        $probationBackingReclaimsTotal += [UInt64]$row.probation_backing_reclaims
        if ([UInt64]$row.requested_slots -ne [UInt64]$PromotionSlots -or
            [UInt64]$row.reserved_slots -ne [UInt64]$PromotionSlots -or
            [string]$row.reserve_strategy -ne "pre-reserved-open-router" -or
            [UInt64]$row.snapshot_evictions -ne 0 -or
            [UInt64]$row.cold_observed -le 0 -or
            [UInt64]$row.cold_to_2bit_ram -le 0 -or
            [UInt64]$row.promotion_2bit_ssd_bytes -le 0 -or
            [double]::IsNaN([double]$row.promotion_2bit_ssd_seconds) -or
            [double]::IsInfinity([double]$row.promotion_2bit_ssd_seconds) -or
            [double]$row.promotion_2bit_ssd_seconds -le 0.0 -or
            [UInt64]$row.direct_ssd_to_vram_rejected -ne 0 -or
            [UInt64]$row.failures -ne 0) {
            throw "G97 promotion row contract mismatch at request $($i + 1)"
        }
    }
    if ($probationBackingReclaimsTotal -ne
        [UInt64]$Result.iq1_promotion_probation_backing_reclaims) {
        throw "G97 promotion probation backing reclaim total mismatch"
    }
}

New-Item -ItemType Directory -Force -Path $outdir | Out-Null
Assert-G97StaticContract

$selfSha = Get-G97SHA256 $MyInvocation.MyCommand.Path
$staticChecks = [pscustomobject]@{
    schema = "g97_iq1_promotion_structural_v1"
    script_parse_ok = $true
    harness_present = (Test-Path -LiteralPath $harness -PathType Leaf)
    runtime_monitor_present =
        (Test-Path -LiteralPath $runtimeMonitor -PathType Leaf)
    static_check_only = [bool]$StaticCheckOnly
    no_gpu_or_ds4_launch_in_static_check = [bool]$StaticCheckOnly
    repeats = 1
    warmup_max_tokens = 4
    max_tokens = 8
    context = 128
    dynamic_arena_gib = 12
    iq1_s_ram_cache_gib = 1
    expert_cache_n = 320
    promotion_slots = $PromotionSlots
    compose_prefill_mass_open_router = $true
    compose_prefill_mass_reserve_slots = $PromotionSlots
    model_hash_method_required = "verified_receipt_reuse"
    model_receipt_path_required = $true
    model_receipt_sha256_required = $true
    iq1_s_sidecar_hash_method_required = "verified_receipt_reuse"
    iq1_s_sidecar_receipt_path_required = $true
    iq1_s_sidecar_receipt_sha256_required = $true
    quality_eligible = $false
    sota_eligible = $false
    system_quiescence_preflight_skipped = $true
    reason = "structural-safety-gate-not-quality-eligible"
    quality_claim = "none"
    performance_claim = "none"
    runner_sha256 = $selfSha
}

if ($StaticCheckOnly) {
    Write-Host "[g97] static check OK; no build, GPU, DS4, or benchmark launched."
    $staticChecks | ConvertTo-Json -Depth 5
    return
}

Invoke-G97BuildOnce
$provenance = [pscustomobject]@{
    executable_sha256 = Get-G97SHA256 $executable
    harness_sha256 = Get-G97SHA256 $harness
    runtime_monitor_harness_sha256 = Get-G97SHA256 $runtimeMonitor
    build_manifest_sha256 = Get-G97SHA256 $buildManifest
}

$resultPath = Join-Path $outdir ("g7_" + $tag + "_result.json")
$rawPath = Join-Path $outdir ("g7_" + $tag + "_raw_outputs.json")
$failurePath = Join-Path $outdir ("g7_" + $tag + "_failure.json")

if ($Resume -and (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
    Write-Host "[g97] resume validate"
} else {
    $args = New-G97Args
    & powershell.exe @args | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) { throw "G97 structural smoke failed" }
}

if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
    throw "G97 result missing: $resultPath"
}
if (-not (Test-Path -LiteralPath $rawPath -PathType Leaf)) {
    throw "G97 raw output missing: $rawPath"
}
if (Test-Path -LiteralPath $failurePath -PathType Leaf) {
    throw "G97 failure artifact present: $failurePath"
}

$result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
Assert-G97RunContract -Result $result -Provenance $provenance

$summary = [pscustomobject]@{
    schema = "g97_iq1_promotion_structural_v1"
    gate_kind = "structural-safety"
    quality_eligible = $false
    sota_eligible = $false
    system_quiescence_preflight_skipped = $true
    reason = "structural-safety-gate-not-quality-eligible"
    quality_claim = "none"
    performance_claim = "none"
    tag = $tag
    result_path = $resultPath
    raw_outputs_path = $rawPath
    runner_sha256 = $selfSha
    harness_sha256 = $result.harness_sha256
    executable_sha256 = $result.executable_sha256
    build_manifest_sha256 = $result.build_manifest_sha256
    model_hash_method = [string]$result.model_hash_method
    model_receipt_path = [string]$result.model_receipt_path
    model_receipt_sha256 = [string]$result.model_receipt_sha256
    iq1_s_sidecar_hash_method = [string]$result.iq1_s_sidecar_hash_method
    iq1_s_sidecar_receipt_path = [string]$result.iq1_s_sidecar_receipt_path
    iq1_s_sidecar_receipt_sha256 =
        [string]$result.iq1_s_sidecar_receipt_sha256
    repeats = 1
    warmup_max_tokens = 4
    max_tokens = 8
    context = 128
    dynamic_arena_gib = 12
    iq1_s_ram_cache_gib = 1
    expert_cache_n = 320
    promotion_slots = $PromotionSlots
    promotion_lines = [int]$result.iq1_promotion_line_count
    promotion_probation_backing_reclaims =
        [UInt64]$result.iq1_promotion_probation_backing_reclaims
    promotion_2bit_ssd_seconds = [double]$result.iq1_promotion_2bit_ssd_seconds
    promotion_2bit_ssd_bytes_per_second =
        [double]$result.iq1_promotion_2bit_ssd_bytes_per_second
    checks = [pscustomobject]@{
        promotion_lines_for_all_requests = $true
        requested_reserved_equal_slots_no_snapshot_evictions = $true
        cold_observed_positive = $true
        iq2_ssd_to_probation_ram_stage_observed = $true
        probation_backing_reclaims_total_positive = $true
        iq2_stage_bytes_seconds_bandwidth_positive = $true
        direct_ssd_to_vram_rejected_zero = $true
        promotion_failures_zero = $true
        promotion_2bit_ssd_seconds_finite_nonnegative = $true
        snapshot_backing_entries_equal_prefill_candidate = $true
        forbidden_cold_ssd_to_vram_zero = $true
        cold_to_vram_zero = $true
    }
}

$summary | ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath $summaryPath -Encoding UTF8
Write-Host ("[g97] structural smoke complete: " + $summaryPath)
