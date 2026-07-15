# G42 request-closed snapshot A/B (PowerShell 5.1, ASCII).
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$harness = Join-Path $root "g7_measure.ps1"
$outdir = Join-Path $root "g7_runs"
$model = "C:\ds4-models\ds4-2bit.gguf"
$prompt = "Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document."
$expected = "921a62bdb39d9d07161326274fcbc0070f3c4b9e75153d27b1b6dc96811f6e88"
$arenaGiB = 30
$cacheExperts = 256

function Get-G42Mean {
    param(
        [Parameter(Mandatory=$true)][object[]]$Rows,
        [Parameter(Mandatory=$true)][string]$Property
    )
    [math]::Round(($Rows | Measure-Object -Property $Property -Average).Average, 6)
}

function Invoke-G42Run {
    param(
        [Parameter(Mandatory=$true)][string]$Tag,
        [Parameter(Mandatory=$true)][ValidateSet("control", "closed")][string]$Arm
    )

    $useClosed = ($Arm -eq "closed")
    $args = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $harness,
        "-MaxTokens", "12", "-Repeats", "1",
        "-Tag", $Tag, "-Prompt", $prompt, "-Context", "256",
        "-BudgetGB", "2", "-ReserveMB", "1024", "-RuntimeReserveMB", "0",
        "-DynamicArenaGiB", "$arenaGiB",
        "-DisableQ8F16Cache", "-EmbedRowStaging", "-PrefillChunk", "0",
        "-ReapPrefetchThreads", "8", "-IoQD", "1",
        "-ExpectedContentSHA256", $expected,
        "-ModelPath", $model, "-TimeoutSec", "1200",
        "-PrefillMassWrap"
    )
    if ($useClosed) {
        $args += @(
            "-ComposePrefillMassTiering",
            "-ExpertCacheN", "$cacheExperts",
            "-ExpertCacheReserveGB", "0.5",
            "-ExpertCachePolicy", "lru",
            "-GpuResidentRoutes",
            "-ExpertTiering", "enforce",
            "-ExpertTierPolicy", "mass-lfru",
            "-ExpertTierClockCalls", "430",
            "-ExpertTierReplacementBudget", "16",
            "-ExpertTierMinFrequency", "3",
            "-ExpertTierHysteresis", "1.25"
        )
    }

    Write-Host ("[g42] start tag=" + $Tag + " arm=" + $Arm)
    & powershell.exe @args | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) {
        throw "G42 run failed: $Tag"
    }

    $resultPath = Join-Path $outdir ("g7_" + $Tag + "_result.json")
    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        throw "G42 result missing: $resultPath"
    }
    $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json

    if (-not $result.outputs_identical -or
        $result.expected_content_sha256 -ne $expected -or
        $result.results.Count -ne 1 -or
        $result.results[0].content_sha256 -ne $expected) {
        throw "G42 exact output mismatch: tag=$Tag"
    }
    if ($result.prompt -ne $prompt -or
        $result.context_requested -ne 256 -or
        $result.requested_max_tokens -ne 12 -or
        $result.repeats -ne 1 -or
        $result.warmup -or
        $result.budget_gb -ne 2.0 -or
        $result.reserve_mb -ne 1024 -or
        $result.prefill_chunk_requested -ne 0 -or
        $result.prefill_chunk_observed -ne 256 -or
        $result.dynamic_arena_gib_requested -ne $arenaGiB -or
        -not $result.q8_f16_cache_disabled -or
        -not $result.embed_row_staging_requested -or
        $result.moe_io_queue_depth -ne 1 -or
        -not $result.prefill_mass_observer_armed -or
        -not $result.prefill_mass_finalized -or
        -not $result.prefill_mass_wrap_requested -or
        -not $result.prefill_mass_wrap_observed -or
        $result.prefill_mass_wrap_result -ne "published" -or
        $result.prefill_mass_wrap_reason -ne "ok" -or
        $result.prefill_mass_wrap_router -ne "unbiased" -or
        $result.prefill_mass_wrap_event_count -ne 1 -or
        $result.dynamic_arena_final_fatal -ne 0) {
        throw "G42 common contract mismatch: tag=$Tag"
    }

    $tier = $result.expert_tiering
    if ($useClosed) {
        if (-not $result.compose_prefill_mass_tiering_requested -or
            -not $tier.compose_prefill_mass_tiering_observed -or
            $result.prefill_mass_wrap_mask -ne "request-scoped-closed" -or
            $result.prefill_mass_compose_event_count -ne 1 -or
            $result.prefill_mass_compose_hash_seed_entries -ne 768 -or
            $result.expert_cache_requested -ne $cacheExperts -or
            -not $result.gpu_resident_routes_requested -or
            $tier.mode -ne "enforce" -or
            $tier.policy -ne "mass-lfru" -or
            $tier.snapshot_backing_entries -ne $result.prefill_mass_candidate_entries -or
            $tier.snapshot_backing_hits -le 0 -or
            $tier.snapshot_backing_misses -ne 0 -or
            $tier.forbidden_cold_ssd_to_vram -ne 0 -or
            $tier.cold_to_ram -ne 0 -or
            $tier.cold_to_vram -ne 0 -or
            $tier.ssd_bytes -ne 0 -or
            $tier.failures -ne 0) {
            throw "G42 closed-snapshot contract mismatch: tag=$Tag"
        }
    } else {
        if ($result.compose_prefill_mass_tiering_requested -or
            $result.compose_prefill_mass_tiering_observed -or
            $result.prefill_mass_wrap_mask -ne "off" -or
            $result.prefill_mass_compose_event_count -ne 0 -or
            $result.expert_cache_requested -ne 0 -or
            $result.gpu_resident_routes_requested -or
            $result.expert_tiering_requested -ne "off") {
            throw "G42 control isolation mismatch: tag=$Tag"
        }
    }

    $processRead = [uint64]$result.runtime_telemetry.win32_process_read_transfer_delta_bytes
    $tierCalls = if ($useClosed) { [uint64]$tier.calls } else { 0 }
    $tierSelected = if ($useClosed) { [uint64]$tier.selected } else { 0 }
    $vramHits = if ($useClosed) { [uint64]$tier.vram_hits } else { 0 }
    $ramHits = if ($useClosed) { [uint64]$tier.ram_hits } else { 0 }
    $snapshotMisses = if ($useClosed) { [uint64]$tier.snapshot_backing_misses } else { 0 }
    $ssdBytes = if ($useClosed) { [uint64]$tier.ssd_bytes } else { 0 }
    $ramH2D = if ($useClosed) { [uint64]$tier.ram_h2d_bytes } else { 0 }
    $transient = if ($useClosed) { [uint64]$tier.transient } else { 0 }
    $promotions = if ($useClosed) { [uint64]$tier.vram_promotions } else { 0 }
    $demotions = if ($useClosed) { [uint64]$tier.vram_demotions } else { 0 }

    [pscustomobject]@{
        tag = $Tag
        arm = $Arm
        result_path = $resultPath
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
        ttft_seconds = [double]$result.server_prefill_ttft_mean_seconds
        client_tokens_per_second = [double]$result.mean_tokens_per_second
        decode_tokens_per_second = [double]$result.server_decode_mean_tokens_per_second
        load_seconds = [double]$result.load_seconds
        process_read_gib = $processRead / 1GB
        dedicated_peak_gib = [uint64]$result.runtime_telemetry.gpu_process_dedicated_peak_bytes / 1GB
        shared_peak_gib = [uint64]$result.runtime_telemetry.gpu_process_shared_peak_bytes / 1GB
        available_min_gib = [uint64]$result.runtime_telemetry.windows_available_min_bytes / 1GB
        candidate_entries = [uint64]$result.prefill_mass_candidate_entries
        mass_coverage = [double]$result.prefill_mass_coverage
        wrap_seconds = [double]$result.prefill_mass_wrap_seconds
        tier_calls = $tierCalls
        tier_selected = $tierSelected
        vram_hits = $vramHits
        ram_hits = $ramHits
        vram_hit_rate = if ($tierSelected -gt 0) { $vramHits / [double]$tierSelected } else { 0.0 }
        ram_hits_per_call = if ($tierCalls -gt 0) { $ramHits / [double]$tierCalls } else { 0.0 }
        snapshot_misses = $snapshotMisses
        ssd_bytes = $ssdBytes
        ram_h2d_gib = $ramH2D / 1GB
        transient = $transient
        vram_promotions = $promotions
        vram_demotions = $demotions
    }
}

New-Item -ItemType Directory -Force -Path $outdir | Out-Null

# Three independent one-request processes per arm. First-snapshot publication
# forbids warmup and within-process repeats. Order balances cache and thermal drift.
$runs = @()
$runs += Invoke-G42Run -Tag "g42_control_a" -Arm "control"
$runs += Invoke-G42Run -Tag "g42_closed256_a" -Arm "closed"
$runs += Invoke-G42Run -Tag "g42_closed256_b" -Arm "closed"
$runs += Invoke-G42Run -Tag "g42_control_b" -Arm "control"
$runs += Invoke-G42Run -Tag "g42_control_c" -Arm "control"
$runs += Invoke-G42Run -Tag "g42_closed256_c" -Arm "closed"

$provenanceFields = @(
    "head", "executable_sha256", "ds4_cuda_sha256", "ds4_c_sha256",
    "build_manifest_sha256", "build_input_fingerprint_sha256", "harness_sha256",
    "model", "model_bytes", "model_last_write_utc", "build_worktree_dirty"
)
foreach ($field in $provenanceFields) {
    $values = @($runs | ForEach-Object { [string]($_.$field) } | Select-Object -Unique)
    if ($values.Count -ne 1) {
        throw "G42 mixed provenance across runs: field=$field"
    }
}

$armSummary = @()
foreach ($arm in @("control", "closed")) {
    $rows = @($runs | Where-Object { $_.arm -eq $arm })
    if ($rows.Count -ne 3) {
        throw "G42 arm replication mismatch: $arm"
    }
    $armSummary += [pscustomobject]@{
        arm = $arm
        independent_processes = $rows.Count
        ttft_mean_seconds = Get-G42Mean $rows "ttft_seconds"
        client_tokens_per_second_mean = Get-G42Mean $rows "client_tokens_per_second"
        decode_tokens_per_second_mean = Get-G42Mean $rows "decode_tokens_per_second"
        load_seconds_mean = Get-G42Mean $rows "load_seconds"
        process_read_gib_mean = Get-G42Mean $rows "process_read_gib"
        dedicated_peak_gib_mean = Get-G42Mean $rows "dedicated_peak_gib"
        shared_peak_gib_mean = Get-G42Mean $rows "shared_peak_gib"
        available_min_gib_mean = Get-G42Mean $rows "available_min_gib"
        candidate_entries_mean = Get-G42Mean $rows "candidate_entries"
        mass_coverage_mean = Get-G42Mean $rows "mass_coverage"
        wrap_seconds_mean = Get-G42Mean $rows "wrap_seconds"
        tier_calls_mean = Get-G42Mean $rows "tier_calls"
        tier_selected_mean = Get-G42Mean $rows "tier_selected"
        vram_hits_mean = Get-G42Mean $rows "vram_hits"
        ram_hits_mean = Get-G42Mean $rows "ram_hits"
        vram_hit_rate_mean = Get-G42Mean $rows "vram_hit_rate"
        ram_hits_per_call_mean = Get-G42Mean $rows "ram_hits_per_call"
        snapshot_misses_sum = ($rows | Measure-Object -Property snapshot_misses -Sum).Sum
        ssd_bytes_sum = ($rows | Measure-Object -Property ssd_bytes -Sum).Sum
        ram_h2d_gib_mean = Get-G42Mean $rows "ram_h2d_gib"
        transient_mean = Get-G42Mean $rows "transient"
        vram_promotions_mean = Get-G42Mean $rows "vram_promotions"
        vram_demotions_mean = Get-G42Mean $rows "vram_demotions"
    }
}

$summary = [pscustomobject]@{
    schema = "g42_closed_snapshot_cache256_ab_v1"
    question = "Does a request-scoped closed prefill snapshot with 256 protected VRAM experts eliminate SSD misses and improve steady decode versus bulk-WRAP alone?"
    prompt = $prompt
    context = 256
    max_tokens = 12
    arena_gib = $arenaGiB
    cache_experts = $cacheExperts
    expected_content_sha256 = $expected
    independent_processes_per_arm = 3
    within_process_repeats = 1
    warmup = $false
    order = @($runs | ForEach-Object { $_.tag })
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

$summaryPath = Join-Path $outdir "g42_closed_snapshot_cache256_ab_result.json"
$summary | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 $summaryPath
Write-Host ("[g42] matrix complete: " + $summaryPath)
