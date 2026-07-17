# G98 open-router reclaim structural smoke (PowerShell 5.1, ASCII).
param(
    [switch]$StaticCheckOnly,
    [switch]$Resume,
    [ValidateRange(1, 512)][int]$ReserveSlots = 16
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$harness = Join-Path $root "g7_measure.ps1"
$runtimeMonitor = Join-Path $root "g7_runtime_monitor.ps1"
$outdir = Join-Path $root "g7_runs"
$executable = Join-Path $root "build\Release\ds4_server.exe"
$buildManifest = Join-Path $root "build\Release\g7_build_manifest.json"
$ds4Cuda = Join-Path $root "ds4_cuda.cu"

$model = "C:\ds4-models\ds4-2bit.gguf"
$expectedModelSHA256 =
    "efc7ed607ff27076e3e501fc3fefefa33c0ed8cf1eff483a2b7fdc0c2e616668"
$iq1Sidecar = "D:\ds4-models\DeepSeek-V4-Flash-IQ1_S-XL.gguf"
$expectedIq1SidecarSHA256 =
    "b049d1eb34c068f19ab007b33c22a7d758b578bf2b10d9276e79654f85d35047"
[UInt64]$expectedIq1SidecarBytes = 61540805344
$prompt = "Hi"
$tag = "g98_open_router_reclaim_structural_n1"
$summaryPath = Join-Path $outdir "g98_open_router_reclaim_structural_result.json"

function Get-G98ORSHA256 {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "G98 open-router reclaim provenance file missing: $Path"
    }
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Test-G98ORHarnessParameter {
    param([Parameter(Mandatory=$true)][string]$ParameterName)
    $content = Get-Content -LiteralPath $harness -Raw
    return ($content -match ("\$" + [regex]::Escape($ParameterName) +
        "(\s|=|,|\))"))
}

function Assert-G98ORProperty {
    param(
        [Parameter(Mandatory=$true)][object]$Object,
        [Parameter(Mandatory=$true)][string]$Name
    )
    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) {
        throw "G98 open-router reclaim required field missing: $Name"
    }
}

function Assert-G98ORStaticContract {
    if (-not (Test-Path -LiteralPath $harness -PathType Leaf)) {
        throw "G98 open-router reclaim harness missing: $harness"
    }
    if (-not (Test-Path -LiteralPath $runtimeMonitor -PathType Leaf)) {
        throw "G98 open-router reclaim runtime monitor missing: $runtimeMonitor"
    }
    if (-not (Test-Path -LiteralPath $ds4Cuda -PathType Leaf)) {
        throw "G98 open-router reclaim CUDA source missing: $ds4Cuda"
    }
    foreach ($parameter in @(
        "WarmupMaxTokens", "Repeats", "BudgetGB", "ReserveMB",
        "DynamicArenaGiB", "ArenaWrapTrustWorkerChecksum",
        "ArenaWrapSourceParts", "ArenaWrapUnlockSourceRanges",
        "ArenaWrapUnlockWaveGiB", "PrefillMassWrap",
        "ComposePrefillMassTiering", "ComposePrefillMassOpenRouter",
        "ComposePrefillMassReserveSlots", "DisableQ8F16Cache",
        "EmbedRowStaging", "ExpertCacheN", "ExpertCacheReserveGB",
        "ExpertCachePolicy", "ExpertTiering", "ExpertTierPolicy",
        "ExpertTierClockCalls", "ExpertTierReplacementBudget",
        "ExpertTierMinFrequency", "ExpertTierHysteresis",
        "GpuResidentRoutes", "RouteNoDefaultSync", "SplitFused",
        "ReapPrefetchThreads", "ExpectedModelSHA256",
        "ReuseVerifiedModelReceipt", "Iq1SExpertSidecar",
        "ExpectedIq1SExpertSidecarSHA256",
        "ExpectedIq1SExpertSidecarBytes", "ReuseVerifiedIq1SReceipt",
        "Iq1SLayerFirst", "Iq1SLayerLast", "Iq1SMixedColdOne",
        "Iq1SMixedGpuPlan", "Iq1Promotion", "Iq1PromotionProbationSlots",
        "Iq1SRamCacheGiB", "GateKind", "SkipSystemQuiescencePreflight",
        "QuiescenceCooldownSec")) {
        if (-not (Test-G98ORHarnessParameter -ParameterName $parameter)) {
            throw "Harness does not expose -$parameter; refusing to run."
        }
    }

    $harnessText = Get-Content -LiteralPath $harness -Raw
    foreach ($requiredText in @(
        "temperature = 0",
        "think = `$false",
        "DS4_CUDA_PREFILL_TIER_ROUTER",
        "DS4_CUDA_PREFILL_TIER_RESERVE_SLOTS",
        "compose_prefill_mass_open_router_requested",
        "compose_prefill_mass_reserve_slots_requested",
        "iq1_promotion_runtime_observed",
        "route_packed_copy_requested",
        "quality_eligible",
        "sota_eligible")) {
        if ($harnessText -notmatch [regex]::Escape($requiredText)) {
            throw "G98 open-router reclaim harness marker missing: $requiredText"
        }
    }
    $cudaText = Get-Content -LiteralPath $ds4Cuda -Raw
    foreach ($requiredText in @(
        "general_backing_reclaims",
        "g_moe_tiering.general_backing_reclaims++")) {
        if ($cudaText -notmatch [regex]::Escape($requiredText)) {
            throw "G98 open-router reclaim CUDA marker missing: $requiredText"
        }
    }
    if ($expectedModelSHA256 -notmatch '^[0-9a-f]{64}$' -or
        $expectedIq1SidecarSHA256 -notmatch '^[0-9a-f]{64}$' -or
        $expectedIq1SidecarBytes -le 0) {
        throw "G98 open-router reclaim provenance constants are invalid."
    }

    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $PSCommandPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
    if ($parseErrors -and $parseErrors.Count -gt 0) {
        throw "G98 open-router reclaim AST parse failed: $($parseErrors[0].Message)"
    }

    $args = New-G98ORArgs
    foreach ($requiredArg in @(
        "-ReuseVerifiedModelReceipt", "-ReuseVerifiedIq1SReceipt",
        "-ComposePrefillMassOpenRouter", "-ComposePrefillMassReserveSlots",
        "-ArenaWrapUnlockSourceRanges", "-ArenaWrapUnlockWaveGiB")) {
        if (@($args | Where-Object { $_ -eq $requiredArg }).Count -ne 1) {
            throw "G98 open-router reclaim static arg missing: $requiredArg"
        }
    }
    foreach ($forbiddenArg in @("-Iq1Promotion", "-Iq1PromotionProbationSlots",
        "-RoutePackedCopy")) {
        if (@($args | Where-Object { $_ -eq $forbiddenArg }).Count -ne 0) {
            throw "G98 open-router reclaim forbidden arg present: $forbiddenArg"
        }
    }
}

function New-G98ORArgs {
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
        "-ArenaWrapUnlockSourceRanges",
        "-ArenaWrapUnlockWaveGiB", "4",
        "-DisableQ8F16Cache",
        "-EmbedRowStaging",
        "-PrefillMassWrap",
        "-ComposePrefillMassTiering",
        "-ComposePrefillMassOpenRouter",
        "-ComposePrefillMassReserveSlots", ([string]$ReserveSlots),
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
        "-ReapPrefetchThreads", "8",
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
        "-Iq1SRamCacheGiB", "1",
        "-GateKind", "structural-safety",
        "-SkipSystemQuiescencePreflight",
        "-QuiescenceCooldownSec", "90"
    )
}

function Assert-G98ORRunContract {
    param([Parameter(Mandatory=$true)][object]$Result,
          [Parameter(Mandatory=$true)][object]$Provenance)

    foreach ($name in @(
        "server_exit_code", "results", "model_sha256", "model_hash_method",
        "model_receipt_path", "model_receipt_sha256",
        "iq1_s_sidecar_sha256", "iq1_s_sidecar_hash_method",
        "iq1_s_sidecar_receipt_path", "iq1_s_sidecar_receipt_sha256",
        "iq1_s_mixed_runtime_observed",
        "iq1_s_mixed_gpu_plan_runtime_observed",
        "iq1_promotion_requested", "iq1_promotion_runtime_observed",
        "iq1_promotion_line_count", "iq1_promotion_cold_to_2bit_ram",
        "iq1_promotion_2bit_ssd_bytes",
        "iq1_promotion_direct_ssd_to_vram_rejected",
        "iq1_promotion_failures",
        "compose_prefill_mass_open_router_requested",
        "compose_prefill_mass_reserve_slots_requested",
        "route_packed_copy_requested", "route_packed_copy_observed",
        "route_packed_copy_bytes", "expert_tiering",
        "system_quiescence_preflight", "quality_eligible",
        "sota_eligible", "contamination_reason")) {
        Assert-G98ORProperty -Object $Result -Name $name
    }

    $tier = $Result.expert_tiering
    foreach ($name in @(
        "forbidden_cold_ssd_to_vram", "cold_to_vram", "failures",
        "general_backing_reclaims")) {
        Assert-G98ORProperty -Object $tier -Name $name
    }

    $contentHashes = @($Result.results | ForEach-Object {
        [string]$_.content_sha256
    })
    if ($contentHashes.Count -ne 1 -or
        $contentHashes[0] -notmatch '^[0-9a-fA-F]{64}$') {
        throw "G98 open-router reclaim output success contract failed"
    }

    if ($Result.tag -ne $tag -or
        $Result.prompt -ne $prompt -or
        $Result.model -ne $model -or
        $Result.model_sha256 -ne $expectedModelSHA256 -or
        [string]$Result.model_hash_method -ne "verified_receipt_reuse" -or
        [string]::IsNullOrWhiteSpace([string]$Result.model_receipt_path) -or
        [string]$Result.model_receipt_sha256 -notmatch '^[0-9a-fA-F]{64}$' -or
        $Result.iq1_s_sidecar -ne $iq1Sidecar -or
        $Result.iq1_s_sidecar_sha256 -ne $expectedIq1SidecarSHA256 -or
        [string]$Result.iq1_s_sidecar_hash_method -ne
            "verified_receipt_reuse" -or
        [string]::IsNullOrWhiteSpace(
            [string]$Result.iq1_s_sidecar_receipt_path) -or
        [string]$Result.iq1_s_sidecar_receipt_sha256 -notmatch
            '^[0-9a-fA-F]{64}$' -or
        [int]$Result.server_exit_code -ne 0 -or
        [string]$Result.gate_kind -ne "structural-safety" -or
        [int]$Result.repeats -ne 1 -or
        [bool]$Result.warmup -ne $true -or
        [int]$Result.requested_max_tokens -ne 8 -or
        [int]$Result.requested_warmup_max_tokens -ne 4 -or
        [int]$Result.context_requested -ne 128 -or
        [double]$Result.dynamic_arena_gib_requested -ne 12.0 -or
        [bool]$Result.arena_wrap_trust_worker_checksum_requested -ne $true -or
        [string]$Result.arena_wrap_schedule_requested -ne "source-parts" -or
        [string]$Result.arena_wrap_source_requested -ne "mmap" -or
        [bool]$Result.arena_wrap_unlock_source_ranges_requested -ne $true -or
        [double]$Result.arena_wrap_unlock_wave_gib_requested -ne 4.0 -or
        [bool]$Result.prefill_mass_wrap_requested -ne $true -or
        [bool]$Result.compose_prefill_mass_tiering_requested -ne $true -or
        [bool]$Result.compose_prefill_mass_open_router_requested -ne $true -or
        [int]$Result.compose_prefill_mass_reserve_slots_requested -ne
            $ReserveSlots -or
        [int]$Result.expert_cache_requested -ne 320 -or
        [double]$Result.expert_cache_reserve_gb -ne 0.125 -or
        [string]$Result.expert_cache_policy -ne "lru" -or
        [string]$Result.expert_tiering_requested -ne "enforce" -or
        [string]$Result.expert_tier_policy_requested -ne "mass-lfru" -or
        [int]$Result.expert_tier_clock_calls_requested -ne 430 -or
        [int]$Result.expert_tier_replacement_budget_requested -ne 32 -or
        [int]$Result.expert_tier_min_frequency_requested -ne 3 -or
        [double]$Result.expert_tier_hysteresis_requested -ne 1.25 -or
        [string]$tier.mode -ne "enforce" -or
        [string]$tier.policy -ne "mass-lfru" -or
        [UInt64]$tier.failures -ne 0 -or
        [UInt64]$tier.forbidden_cold_ssd_to_vram -ne 0 -or
        [UInt64]$tier.cold_to_vram -ne 0 -or
        [UInt64]$tier.general_backing_reclaims -le 0 -or
        [bool]$Result.gpu_resident_routes_requested -ne $true -or
        [bool]$Result.route_no_default_sync_requested -ne $true -or
        [bool]$Result.route_packed_copy_requested -ne $false -or
        [bool]$Result.route_packed_copy_observed -ne $false -or
        [UInt64]$Result.route_packed_copy_bytes -ne 0 -or
        [bool]$Result.split_fused_requested -ne $true -or
        [int]$Result.reap_prefetch_threads_requested -ne 8 -or
        [bool]$Result.iq1_s_mixed_cold_one -ne $true -or
        [bool]$Result.iq1_s_mixed_runtime_observed -ne $true -or
        [bool]$Result.iq1_s_mixed_gpu_plan_requested -ne $true -or
        [bool]$Result.iq1_s_mixed_gpu_plan_runtime_observed -ne $true -or
        [double]$Result.iq1_s_ram_cache_requested_gib -ne 1.0 -or
        [bool]$Result.iq1_promotion_requested -ne $false -or
        [bool]$Result.iq1_promotion_runtime_observed -ne $false -or
        [int]$Result.iq1_promotion_line_count -ne 0 -or
        [UInt64]$Result.iq1_promotion_cold_to_2bit_ram -ne 0 -or
        [UInt64]$Result.iq1_promotion_2bit_ssd_bytes -ne 0 -or
        [UInt64]$Result.iq1_promotion_direct_ssd_to_vram_rejected -ne 0 -or
        [UInt64]$Result.iq1_promotion_failures -ne 0 -or
        [string]$Result.effective_ds4_environment.DS4_CUDA_PREFILL_TIER_ROUTER -ne
            "open" -or
        [string]$Result.effective_ds4_environment.DS4_CUDA_PREFILL_TIER_RESERVE_SLOTS -ne
            ([string]$ReserveSlots) -or
        [bool]$Result.system_quiescence_preflight.skipped -ne $true -or
        [bool]$Result.quality_eligible -ne $false -or
        [bool]$Result.sota_eligible -ne $false -or
        [string]$Result.contamination_reason -ne
            "structural-safety-gate-not-quality-eligible" -or
        $Result.executable_sha256 -ne $Provenance.executable_sha256 -or
        $Result.harness_sha256 -ne $Provenance.harness_sha256 -or
        $Result.runtime_monitor_harness_sha256 -ne
            $Provenance.runtime_monitor_harness_sha256 -or
        $Result.ds4_cuda_sha256 -ne $Provenance.ds4_cuda_sha256 -or
        $Result.ds4_c_sha256 -ne $Provenance.ds4_c_sha256 -or
        $Result.ds4_server_c_sha256 -ne $Provenance.ds4_server_c_sha256 -or
        $Result.build_manifest_sha256 -ne $Provenance.build_manifest_sha256) {
        throw "G98 open-router reclaim structural contract mismatch"
    }
}

New-Item -ItemType Directory -Force -Path $outdir | Out-Null
Assert-G98ORStaticContract

$selfSha = Get-G98ORSHA256 $MyInvocation.MyCommand.Path
$staticChecks = [pscustomobject]@{
    schema = "g98_open_router_reclaim_structural_v1"
    script_parse_ok = $true
    ast_parse_ok = $true
    harness_present = (Test-Path -LiteralPath $harness -PathType Leaf)
    runtime_monitor_present =
        (Test-Path -LiteralPath $runtimeMonitor -PathType Leaf)
    static_check_only = [bool]$StaticCheckOnly
    no_build_gpu_or_ds4_launch_in_static_check = [bool]$StaticCheckOnly
    prompt = $prompt
    repeats = 1
    warmup_max_tokens = 4
    max_tokens = 8
    context = 128
    dynamic_arena_gib = 12
    iq1_s_ram_cache_gib = 1
    expert_cache_n = 320
    control_promotion = "off"
    compose_prefill_mass_open_router = $true
    compose_prefill_mass_reserve_slots = $ReserveSlots
    route_packed_copy = $false
    arena_wrap_source = "mmap"
    arena_wrap_schedule = "source-parts"
    arena_wrap_unlock_source_ranges = $true
    arena_wrap_unlock_wave_gib = 4
    model_hash_method_required = "verified_receipt_reuse"
    iq1_s_sidecar_hash_method_required = "verified_receipt_reuse"
    quality_eligible = $false
    sota_eligible = $false
    required_runtime_general_backing_reclaims_positive = $true
    required_iq1_promotion_telemetry_absent = $true
    runner_sha256 = $selfSha
}

if ($StaticCheckOnly) {
    Write-Host "[g98-open-router-reclaim] static check OK; no build, GPU, DS4, or benchmark launched."
    $staticChecks | ConvertTo-Json -Depth 5
    return
}

foreach ($path in @($executable, $buildManifest)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "G98 open-router reclaim requires existing provenance artifact; no build is launched: $path"
    }
}
$provenance = [pscustomobject]@{
    executable_sha256 = Get-G98ORSHA256 $executable
    harness_sha256 = Get-G98ORSHA256 $harness
    runtime_monitor_harness_sha256 = Get-G98ORSHA256 $runtimeMonitor
    ds4_cuda_sha256 = Get-G98ORSHA256 (Join-Path $root "ds4_cuda.cu")
    ds4_c_sha256 = Get-G98ORSHA256 (Join-Path $root "ds4.c")
    ds4_server_c_sha256 = Get-G98ORSHA256 (Join-Path $root "ds4_server.c")
    build_manifest_sha256 = Get-G98ORSHA256 $buildManifest
}

$resultPath = Join-Path $outdir ("g7_" + $tag + "_result.json")
$rawPath = Join-Path $outdir ("g7_" + $tag + "_raw_outputs.json")
$failurePath = Join-Path $outdir ("g7_" + $tag + "_failure.json")

if ($Resume -and (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
    Write-Host "[g98-open-router-reclaim] resume validate"
} else {
    $args = New-G98ORArgs
    & powershell.exe @args | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) {
        throw "G98 open-router reclaim structural smoke failed"
    }
}

if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
    throw "G98 open-router reclaim result missing: $resultPath"
}
if (-not (Test-Path -LiteralPath $rawPath -PathType Leaf)) {
    throw "G98 open-router reclaim raw output missing: $rawPath"
}
if (Test-Path -LiteralPath $failurePath -PathType Leaf) {
    throw "G98 open-router reclaim failure artifact present: $failurePath"
}

$result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
Assert-G98ORRunContract -Result $result -Provenance $provenance
$tier = $result.expert_tiering

$summary = [pscustomobject]@{
    schema = "g98_open_router_reclaim_structural_v1"
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
    iq1_s_sidecar_receipt_path =
        [string]$result.iq1_s_sidecar_receipt_path
    iq1_s_sidecar_receipt_sha256 =
        [string]$result.iq1_s_sidecar_receipt_sha256
    prompt = $prompt
    repeats = 1
    warmup_max_tokens = 4
    max_tokens = 8
    context = 128
    dynamic_arena_gib = 12
    iq1_s_ram_cache_gib = 1
    expert_cache_n = 320
    promotion = "off"
    compose_prefill_mass_open_router = $true
    compose_prefill_mass_reserve_slots = $ReserveSlots
    route_packed_copy = $false
    general_backing_reclaims = [UInt64]$tier.general_backing_reclaims
    checks = [pscustomobject]@{
        process_success = $true
        output_success = $true
        iq1_promotion_telemetry_absent = $true
        expert_tiering_forbidden_cold_ssd_to_vram_zero = $true
        expert_tiering_failures_zero = $true
        expert_tiering_cold_to_vram_zero = $true
        general_backing_reclaims_positive = $true
        receipt_reuse_model_and_iq1_sidecar = $true
        quality_eligible_false = $true
        sota_eligible_false = $true
    }
}

$summary | ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath $summaryPath -Encoding UTF8
Write-Host ("[g98-open-router-reclaim] structural smoke complete: " + $summaryPath)
