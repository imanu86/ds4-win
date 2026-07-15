# G40 cyberpunk production/arena/mass-lfru A/B matrix (PowerShell 5.1, ASCII).
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$harness = Join-Path $root "g7_measure.ps1"
$outdir = Join-Path $root "g7_runs"
$model = "C:\ds4-models\ds4-2bit.gguf"
$prompt = "Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document."
$expected = "921a62bdb39d9d07161326274fcbc0070f3c4b9e75153d27b1b6dc96811f6e88"
$promptTokens = 43
$moeLayers = 42
$arenaMoeLayers = 43
$requestsPerProcess = 4
$clockCalls = 430
$replacementBudget = 16
$minFrequency = 3
$hysteresis = 1.25

function Get-G40Mean {
    param(
        [Parameter(Mandatory=$true)][object[]]$Rows,
        [Parameter(Mandatory=$true)][string]$Property
    )
    [math]::Round(($Rows | Measure-Object -Property $Property -Average).Average, 6)
}

function Assert-G40Equal {
    param(
        [Parameter(Mandatory=$true)][object]$Actual,
        [Parameter(Mandatory=$true)][object]$Expected,
        [Parameter(Mandatory=$true)][string]$Message
    )
    if ($Actual -ne $Expected) {
        throw ($Message + " actual=" + $Actual + " expected=" + $Expected)
    }
}

function Invoke-G40Run {
    param(
        [Parameter(Mandatory=$true)][string]$Tag,
        [Parameter(Mandatory=$true)][ValidateSet("production", "arena_control", "mass_lfru")][string]$Arm
    )

    $useArena = ($Arm -ne "production")
    $useTiering = ($Arm -eq "mass_lfru")

    $args = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $harness,
        "-MaxTokens", "12", "-Repeats", "3", "-Warmup",
        "-Tag", $Tag, "-Prompt", $prompt, "-Context", "256",
        "-BudgetGB", "2", "-ReserveMB", "4096", "-RuntimeReserveMB", "128",
        "-ExpertCacheN", "336", "-ExpertCacheReserveGB", "0.5",
        "-ExpertCachePolicy", "lru", "-DisableQ8F16Cache",
        "-EmbedRowStaging", "-GpuResidentRoutes",
        "-PrefillChunk", "0", "-PrefillUnionStats",
        "-ExpectedContentSHA256", $expected,
        "-ExpectedWarmupContentSHA256", $expected,
        "-ModelPath", $model, "-TimeoutSec", "900"
    )
    if ($useArena) {
        $args += @("-DynamicArenaGiB", "8")
    }
    if ($useTiering) {
        $args += @(
            "-ExpertTiering", "enforce",
            "-ExpertTierPolicy", "mass-lfru",
            "-ExpertTierClockCalls", "$clockCalls",
            "-ExpertTierReplacementBudget", "$replacementBudget",
            "-ExpertTierMinFrequency", "$minFrequency",
            "-ExpertTierHysteresis", $hysteresis.ToString("R", [Globalization.CultureInfo]::InvariantCulture)
        )
    }

    Write-Host ("[g40] start tag=" + $Tag + " arm=" + $Arm)
    & powershell.exe @args | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) {
        throw "G40 run failed: $Tag"
    }

    $resultPath = Join-Path $outdir ("g7_" + $Tag + "_result.json")
    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        throw "G40 result missing: $resultPath"
    }
    $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json

    if (-not $result.outputs_identical -or
        $result.expected_content_sha256 -ne $expected -or
        $null -eq $result.warmup_result -or
        $result.warmup_result.content_sha256 -ne $expected) {
        throw "G40 exact output mismatch: tag=$Tag"
    }

    # Enabling the pinned arena makes one additional routed layer observable in
    # both the prefill-union and decode-route telemetry. Keep this measured
    # behavior explicit instead of forcing production's 42-layer accounting.
    $observedMoeLayers = $(if ($useArena) { $arenaMoeLayers } else { $moeLayers })
    $expectedCalls = [uint64]($observedMoeLayers * $requestsPerProcess)
    $expectedRows = [uint64]($observedMoeLayers * $promptTokens * $requestsPerProcess)
    if ($result.prompt -ne $prompt -or
        $result.context_requested -ne 256 -or
        $result.requested_max_tokens -ne 12 -or
        $result.repeats -ne 3 -or
        -not $result.warmup -or
        $result.budget_gb -ne 2.0 -or
        $result.reserve_mb -ne 4096 -or
        $result.prefill_chunk_requested -ne 0 -or
        $result.prefill_chunk_observed -ne 256 -or
        $result.expert_cache_requested -ne 336 -or
        $result.expert_cache_policy -ne "lru" -or
        -not $result.gpu_resident_routes_requested -or
        -not $result.gpu_resident_routes_observed -or
        $result.gpu_resident_routes_errors -ne 0 -or
        -not $result.q8_f16_cache_disabled -or
        -not $result.embed_row_staging_requested -or
        -not $result.prefill_union_stats_observed -or
        $result.prefill_union_calls -ne $expectedCalls -or
        $result.prefill_union_tokens -ne $expectedRows -or
        $result.prefill_union_selected_slots -ne ($expectedRows * 6)) {
        throw "G40 configuration/accounting mismatch: tag=$Tag"
    }

    if ($useArena) {
        Assert-G40Equal $result.dynamic_arena_gib_requested 8.0 ("G40 arena request mismatch: tag=" + $Tag)
    } else {
        Assert-G40Equal $result.dynamic_arena_gib_requested 0.0 ("G40 production arena must be off: tag=" + $Tag)
    }

    if ($useTiering) {
        $tier = $result.expert_tiering
        if ($result.expert_tiering_requested -ne "enforce" -or
            $result.expert_tier_policy_requested -ne "mass-lfru" -or
            $result.expert_tier_clock_calls_requested -ne $clockCalls -or
            $result.expert_tier_replacement_budget_requested -ne $replacementBudget -or
            $result.expert_tier_min_frequency_requested -ne $minFrequency -or
            [math]::Abs($result.expert_tier_hysteresis_requested - $hysteresis) -gt 1.0e-9 -or
            -not $tier.final_observed -or
            $tier.final_line_count -ne 1 -or
            $tier.mode -ne "enforce" -or
            $tier.policy -ne "mass-lfru" -or
            $tier.clock_calls -ne $clockCalls -or
            $tier.replacement_budget -ne $replacementBudget -or
            $tier.min_frequency -ne $minFrequency -or
            [math]::Abs($tier.hysteresis - $hysteresis) -gt 1.0e-9 -or
            $tier.calls -le 0 -or
            $tier.selected -ne ($tier.calls * 6) -or
            $tier.failures -ne 0 -or
            $tier.cold_to_vram -ne 0 -or
            $tier.cold_to_ram -le 0 -or
            $tier.transient -le 0 -or
            $tier.ram_h2d_bytes -le 0 -or
            $tier.states_vram -le 0 -or
            $tier.policy_epochs -le 0 -or
            ($tier.policy_free_promotions + $tier.policy_replacements) -le 0 -or
            $tier.mass_sum -le 0.0 -or
            $tier.lfru_top -le 0.0) {
            throw "G40 mass-lfru tier contract mismatch: tag=$Tag"
        }
    } else {
        if ($result.expert_tiering_requested -ne "off") {
            throw "G40 non-tier arm requested tiering: tag=$Tag"
        }
    }

    [pscustomobject]@{
        tag = $Tag
        arm = $Arm
        observed_moe_layers = $observedMoeLayers
        result_path = $resultPath
        arm_config = [pscustomobject]@{
            dynamic_arena_gib = $(if ($useArena) { 8.0 } else { 0.0 })
            expert_tiering = $(if ($useTiering) { "enforce" } else { "off" })
            expert_tier_policy = $(if ($useTiering) { "mass-lfru" } else { "off" })
            expert_cache_n = 336
            expert_cache_policy = "lru"
            q8_f16_cache = "disabled"
            embed_row_staging = $true
            gpu_resident_routes = $true
            budget_gb = 2
            reserve_mb = 4096
            runtime_reserve_mb = 128
        }
        head = $result.head
        executable_sha256 = $result.executable_sha256
        ds4_cuda_sha256 = $result.ds4_cuda_sha256
        ds4_c_sha256 = $result.ds4_c_sha256
        build_manifest_sha256 = $result.build_manifest_sha256
        build_input_fingerprint_sha256 = $result.build_manifest_input_fingerprint_sha256
        harness_sha256 = $result.harness_sha256
        model = $result.model
        model_bytes = $result.model_bytes
        model_last_write_utc = $result.model_last_write_utc
        build_worktree_dirty = $result.build_manifest_worktree_dirty_at_build_start
        ttft_seconds = $result.server_prefill_ttft_mean_seconds
        client_tokens_per_second = $result.mean_tokens_per_second
        decode_tokens_per_second = $result.server_decode_mean_tokens_per_second
        process_read_bytes = $result.runtime_telemetry.win32_process_read_transfer_delta_bytes
        dedicated_peak_gib = $result.runtime_telemetry.gpu_process_dedicated_peak_bytes / 1GB
        shared_peak_gib = $result.runtime_telemetry.gpu_process_shared_peak_bytes / 1GB
        dedicated_median_gib = $result.runtime_telemetry.gpu_process_dedicated_median_bytes / 1GB
        shared_median_gib = $result.runtime_telemetry.gpu_process_shared_median_bytes / 1GB
        vram_used_peak_mib = $result.runtime_telemetry.vram_used_peak_mib
        route_calls = $result.gpu_resident_routes_calls
        route_all_hit = $result.gpu_resident_routes_all_hit
        route_worker_jobs = $result.gpu_resident_routes_worker_jobs
        route_miss_experts = $result.gpu_resident_routes_miss_experts
        route_errors = $result.gpu_resident_routes_errors
        route_worker_ms_per_job = $result.gpu_resident_routes_worker_ms_per_job
        route_resolve_ms_per_call = $result.gpu_resident_routes_resolve_ms_per_call
        route_wait_ms_per_call = $result.gpu_resident_routes_wait_ms_per_call
        tier_promotions = $(if ($useTiering) { $tier.vram_promotions } else { 0 })
        tier_replacements = $(if ($useTiering) { $tier.policy_replacements } else { 0 })
        tier_transient = $(if ($useTiering) { $tier.transient } else { 0 })
        tier_ram_h2d_bytes = $(if ($useTiering) { $tier.ram_h2d_bytes } else { 0 })
        tier_states_vram = $(if ($useTiering) { $tier.states_vram } else { 0 })
        tier_cold_to_ram = $(if ($useTiering) { $tier.cold_to_ram } else { 0 })
        tier_vram_hits = $(if ($useTiering) { $tier.vram_hits } else { 0 })
        tier_policy_epochs = $(if ($useTiering) { $tier.policy_epochs } else { 0 })
        tier_policy_free_promotions = $(if ($useTiering) { $tier.policy_free_promotions } else { 0 })
        tier_policy_min_frequency_skips = $(if ($useTiering) { $tier.policy_min_frequency_skips } else { 0 })
        tier_policy_budget_skips = $(if ($useTiering) { $tier.policy_budget_skips } else { 0 })
        tier_policy_score_skips = $(if ($useTiering) { $tier.policy_score_skips } else { 0 })
        tier_mass_sum = $(if ($useTiering) { $tier.mass_sum } else { 0.0 })
        tier_lfru_top = $(if ($useTiering) { $tier.lfru_top } else { 0.0 })
    }
}

New-Item -ItemType Directory -Force -Path $outdir | Out-Null

$runs = @()
$runs += Invoke-G40Run -Tag "g40_production_a" -Arm "production"
$runs += Invoke-G40Run -Tag "g40_arena_control_a" -Arm "arena_control"
$runs += Invoke-G40Run -Tag "g40_mass_lfru_a" -Arm "mass_lfru"
$runs += Invoke-G40Run -Tag "g40_mass_lfru_b" -Arm "mass_lfru"
$runs += Invoke-G40Run -Tag "g40_arena_control_b" -Arm "arena_control"
$runs += Invoke-G40Run -Tag "g40_production_b" -Arm "production"

$provenanceFields = @(
    "head", "executable_sha256", "ds4_cuda_sha256", "ds4_c_sha256",
    "build_manifest_sha256", "build_input_fingerprint_sha256", "harness_sha256",
    "model", "model_bytes", "model_last_write_utc", "build_worktree_dirty"
)
foreach ($field in $provenanceFields) {
    $values = @($runs | ForEach-Object { [string]($_.$field) } | Select-Object -Unique)
    if ($values.Count -ne 1) {
        throw "G40 mixed provenance across runs: field=$field"
    }
}

$armSummary = @()
foreach ($arm in @("production", "arena_control", "mass_lfru")) {
    $rows = @($runs | Where-Object { $_.arm -eq $arm })
    if ($rows.Count -ne 2) {
        throw "G40 arm replication mismatch: $arm"
    }
    $armSummary += [pscustomobject]@{
        arm = $arm
        replications = $rows.Count
        ttft_mean_seconds = Get-G40Mean $rows "ttft_seconds"
        client_tokens_per_second_mean = Get-G40Mean $rows "client_tokens_per_second"
        decode_tokens_per_second_mean = Get-G40Mean $rows "decode_tokens_per_second"
        process_read_bytes_mean = Get-G40Mean $rows "process_read_bytes"
        dedicated_peak_gib_mean = Get-G40Mean $rows "dedicated_peak_gib"
        shared_peak_gib_mean = Get-G40Mean $rows "shared_peak_gib"
        dedicated_median_gib_mean = Get-G40Mean $rows "dedicated_median_gib"
        shared_median_gib_mean = Get-G40Mean $rows "shared_median_gib"
        vram_used_peak_mib_mean = Get-G40Mean $rows "vram_used_peak_mib"
        route_all_hit_mean = Get-G40Mean $rows "route_all_hit"
        route_worker_jobs_mean = Get-G40Mean $rows "route_worker_jobs"
        route_miss_experts_mean = Get-G40Mean $rows "route_miss_experts"
        tier_promotions_mean = Get-G40Mean $rows "tier_promotions"
        tier_replacements_mean = Get-G40Mean $rows "tier_replacements"
        tier_transient_mean = Get-G40Mean $rows "tier_transient"
        tier_ram_h2d_bytes_mean = Get-G40Mean $rows "tier_ram_h2d_bytes"
        tier_states_vram_mean = Get-G40Mean $rows "tier_states_vram"
    }
}

$summary = [pscustomobject]@{
    schema = "g40_mass_lfru_cyberpunk_ab_v1"
    prompt = $prompt
    prompt_tokens = $promptTokens
    production_moe_layers = $moeLayers
    arena_moe_layers = $arenaMoeLayers
    context = 256
    max_tokens = 12
    cache_n = 336
    cache_policy = "lru"
    expected_content_sha256 = $expected
    repeats_per_process = 3
    discarded_warmup_per_process = 1
    order = @($runs | ForEach-Object { $_.tag })
    arm_order = @($runs | ForEach-Object { $_.arm })
    policy = [pscustomobject]@{
        clock_calls = $clockCalls
        replacement_budget = $replacementBudget
        min_frequency = $minFrequency
        hysteresis = $hysteresis
    }
    provenance = [pscustomobject]@{
        head = $runs[0].head
        executable_sha256 = $runs[0].executable_sha256
        ds4_cuda_sha256 = $runs[0].ds4_cuda_sha256
        ds4_c_sha256 = $runs[0].ds4_c_sha256
        build_manifest_sha256 = $runs[0].build_manifest_sha256
        build_input_fingerprint_sha256 = $runs[0].build_input_fingerprint_sha256
        harness_sha256 = $runs[0].harness_sha256
        model = $runs[0].model
        model_bytes = $runs[0].model_bytes
        model_last_write_utc = $runs[0].model_last_write_utc
        build_worktree_dirty = $runs[0].build_worktree_dirty
    }
    runs = $runs
    arm_summary = $armSummary
}

$summaryPath = Join-Path $outdir "g40_mass_lfru_cyberpunk_ab_result.json"
$summary | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 $summaryPath
Write-Host ("[g40] matrix complete: " + $summaryPath)
