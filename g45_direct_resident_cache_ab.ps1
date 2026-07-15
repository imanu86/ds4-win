# G45 protected direct-resident cache A/B (PowerShell 5.1, ASCII).
param(
    [switch]$SummarizeExisting,
    [string]$ExecutionRunnerSHA256 = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$harness = Join-Path $root "g7_measure.ps1"
$outdir = Join-Path $root "g7_runs"
$model = "C:\ds4-models\ds4-2bit.gguf"
$prompt = "Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document."
$expected = "31cbc6504dcb57d42aeff9dbceb3aed943bcb32dae19a2edbf552e9fd2f52eb8"

function Get-G45Mean {
    param(
        [Parameter(Mandatory=$true)][object[]]$Rows,
        [Parameter(Mandatory=$true)][string]$Property
    )
    [math]::Round(($Rows | Measure-Object -Property $Property -Average).Average, 6)
}

function Get-G45Median {
    param(
        [Parameter(Mandatory=$true)][object[]]$Rows,
        [Parameter(Mandatory=$true)][string]$Property
    )
    $values = @($Rows | ForEach-Object { [double]($_.$Property) } | Sort-Object)
    if (($values.Count % 2) -eq 1) {
        $middle = [int][math]::Floor($values.Count / 2.0)
        return [math]::Round($values[$middle], 6)
    }
    $upper = [int]($values.Count / 2)
    [math]::Round(($values[$upper - 1] + $values[$upper]) / 2, 6)
}

function Invoke-G45Run {
    param(
        [Parameter(Mandatory=$true)][string]$Tag,
        [Parameter(Mandatory=$true)][ValidateSet(256, 320)][int]$CacheExperts,
        [switch]$ReuseExisting
    )

    $args = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $harness,
        "-MaxTokens", "64", "-Repeats", "1",
        "-Tag", $Tag, "-Prompt", $prompt, "-Context", "256",
        "-BudgetGB", "2", "-ReserveMB", "1024",
        "-DynamicArenaGiB", "30", "-ArenaWrapTrustWorkerChecksum",
        "-ArenaWrapSourceParts", "-DisableQ8F16Cache", "-EmbedRowStaging",
        "-ReapPrefetchThreads", "8", "-ExpectedContentSHA256", $expected,
        "-ModelPath", $model, "-TimeoutSec", "1200",
        "-PrefillMassWrap", "-ComposePrefillMassTiering",
        "-ExpertCacheN", ([string]$CacheExperts),
        "-ExpertCacheReserveGB", "0.125",
        "-ExpertCachePolicy", "lru", "-GpuResidentRoutes",
        "-ExpertTiering", "enforce", "-ExpertTierPolicy", "mass-lfru",
        "-ExpertTierClockCalls", "430",
        "-ExpertTierReplacementBudget", "16",
        "-ExpertTierMinFrequency", "3",
        "-ExpertTierHysteresis", "1.25"
    )

    $resultPath = Join-Path $outdir ("g7_" + $Tag + "_result.json")
    if ($ReuseExisting) {
        Write-Host ("[g45] validate existing tag=" + $Tag +
                    " cache=" + $CacheExperts)
    } else {
        Write-Host ("[g45] start tag=" + $Tag + " cache=" + $CacheExperts)
        & powershell.exe @args | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) {
            throw "G45 run failed: $Tag"
        }
    }

    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        throw "G45 result missing: tag=$Tag"
    }
    $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    $tier = $result.expert_tiering

    $requiredTelemetry = @(
        $result.runtime_telemetry.win32_process_read_transfer_delta_bytes,
        $result.runtime_telemetry.gpu_process_dedicated_peak_bytes,
        $result.runtime_telemetry.vram_used_peak_mib,
        $result.runtime_telemetry.windows_available_min_bytes,
        $result.gpu_resident_routes_all_hit,
        $result.gpu_resident_routes_worker_jobs,
        $result.gpu_resident_routes_miss_experts,
        $result.gpu_resident_routes_worker_ms_per_job,
        $result.gpu_resident_routes_resolve_ms_per_call,
        $result.gpu_resident_routes_wait_ms_per_call,
        $tier.ram_h2d_bytes,
        $tier.vram_hits,
        $tier.ram_hits,
        $tier.vram_promotions,
        $tier.vram_demotions
    )
    if (@($requiredTelemetry | Where-Object { $null -eq $_ }).Count -ne 0) {
        throw "G45 required telemetry missing: tag=$Tag"
    }

    if (-not $result.outputs_identical -or
        $result.expected_content_sha256 -ne $expected -or
        $result.results.Count -ne 1 -or
        $result.results[0].content_sha256 -ne $expected) {
        throw "G45 exact output mismatch: tag=$Tag"
    }
    if ($result.prompt -ne $prompt -or
        $result.context_requested -ne 256 -or
        $result.requested_max_tokens -ne 64 -or
        $result.repeats -ne 1 -or
        $result.warmup -or
        $result.reserve_mb -ne 1024 -or
        $result.dynamic_arena_gib_requested -ne 30 -or
        -not $result.arena_wrap_trust_worker_checksum_requested -or
        $result.arena_wrap_schedule_observed -ne "source-parts" -or
        $result.arena_wrap_checksum_observed -ne "fnv1a64-worker-only" -or
        -not $result.prefill_mass_wrap_observed -or
        $result.prefill_mass_wrap_result -ne "published" -or
        $result.prefill_mass_wrap_reason -ne "ok" -or
        $result.prefill_mass_wrap_mask -ne "request-scoped-closed" -or
        -not $result.compose_prefill_mass_tiering_requested -or
        -not $tier.compose_prefill_mass_tiering_observed -or
        -not $result.gpu_resident_routes_requested -or
        -not $result.gpu_resident_routes_observed -or
        $result.split_hit_miss_requested -or
        $result.expert_cache_requested -ne $CacheExperts -or
        $result.expert_cache_capacity -ne $CacheExperts -or
        $result.expert_cache_reserve_gb -ne 0.125 -or
        $result.expert_cache_policy -ne "lru" -or
        $result.expert_tiering_requested -ne "enforce" -or
        $result.expert_tier_policy_requested -ne "mass-lfru" -or
        $result.expert_tier_clock_calls_requested -ne 430 -or
        $result.expert_tier_replacement_budget_requested -ne 16 -or
        $result.expert_tier_min_frequency_requested -ne 3 -or
        $result.expert_tier_hysteresis_requested -ne 1.25 -or
        $tier.mode -ne "enforce" -or
        $tier.policy -ne "mass-lfru" -or
        $tier.clock_calls -ne 430 -or
        $tier.replacement_budget -ne 16 -or
        $tier.min_frequency -ne 3 -or
        $tier.hysteresis -ne 1.25 -or
        $tier.states_vram -ne $CacheExperts -or
        $tier.snapshot_backing_misses -ne 0 -or
        $tier.ssd_bytes -ne 0 -or
        $tier.failures -ne 0 -or
        $tier.forbidden_cold_ssd_to_vram -ne 0 -or
        $result.gpu_resident_routes_errors -ne 0) {
        throw "G45 contract mismatch: tag=$Tag"
    }

    [pscustomobject]@{
        tag = $Tag
        cache_experts = $CacheExperts
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
        decode_tokens_per_second = [double]$result.server_decode_mean_tokens_per_second
        decode_seconds = [double]$result.server_runs[0].server_decode_seconds
        client_tokens_per_second = [double]$result.mean_tokens_per_second
        wrap_seconds = [double]$result.prefill_mass_wrap_seconds
        process_read_gib = [uint64]$result.runtime_telemetry.win32_process_read_transfer_delta_bytes / 1GB
        vram_hits = [uint64]$tier.vram_hits
        ram_hits = [uint64]$tier.ram_hits
        ram_h2d_gib = [uint64]$tier.ram_h2d_bytes / 1GB
        promotions = [uint64]$tier.vram_promotions
        demotions = [uint64]$tier.vram_demotions
        route_all_hit_calls = [uint64]$result.gpu_resident_routes_all_hit
        route_worker_jobs = [uint64]$result.gpu_resident_routes_worker_jobs
        route_miss_experts = [uint64]$result.gpu_resident_routes_miss_experts
        route_worker_ms_per_job = [double]$result.gpu_resident_routes_worker_ms_per_job
        route_resolve_ms_per_call = [double]$result.gpu_resident_routes_resolve_ms_per_call
        route_wait_ms_per_call = [double]$result.gpu_resident_routes_wait_ms_per_call
        dedicated_peak_gib = [uint64]$result.runtime_telemetry.gpu_process_dedicated_peak_bytes / 1GB
        vram_peak_mib = [uint64]$result.runtime_telemetry.vram_used_peak_mib
        available_min_gib = [uint64]$result.runtime_telemetry.windows_available_min_bytes / 1GB
        snapshot_misses = [uint64]$tier.snapshot_backing_misses
        ssd_bytes = [uint64]$tier.ssd_bytes
        failures = [uint64]$tier.failures
    }
}

New-Item -ItemType Directory -Force -Path $outdir | Out-Null
if ($SummarizeExisting -and
    $ExecutionRunnerSHA256 -notmatch '^[0-9a-fA-F]{64}$') {
    throw "SummarizeExisting requires -ExecutionRunnerSHA256"
}

$runs = @()
$runs += Invoke-G45Run -Tag "g45_stable_cache256_a" -CacheExperts 256 -ReuseExisting:$SummarizeExisting
$runs += Invoke-G45Run -Tag "g45_stable_cache320_a" -CacheExperts 320 -ReuseExisting:$SummarizeExisting
$runs += Invoke-G45Run -Tag "g45_stable_cache320_b" -CacheExperts 320 -ReuseExisting:$SummarizeExisting
$runs += Invoke-G45Run -Tag "g45_stable_cache256_b" -CacheExperts 256 -ReuseExisting:$SummarizeExisting
$runs += Invoke-G45Run -Tag "g45_stable_cache256_c" -CacheExperts 256 -ReuseExisting:$SummarizeExisting
$runs += Invoke-G45Run -Tag "g45_stable_cache320_c" -CacheExperts 320 -ReuseExisting:$SummarizeExisting

$provenanceFields = @(
    "head", "executable_sha256", "ds4_cuda_sha256", "ds4_c_sha256",
    "build_manifest_sha256", "build_input_fingerprint_sha256", "harness_sha256",
    "model", "model_bytes", "model_last_write_utc", "build_worktree_dirty"
)
foreach ($field in $provenanceFields) {
    $values = @($runs | ForEach-Object { [string]($_.$field) } | Select-Object -Unique)
    if ($values.Count -ne 1) {
        throw "G45 mixed provenance across runs: field=$field"
    }
}

$armSummary = @()
foreach ($cache in @(256, 320)) {
    $rows = @($runs | Where-Object { $_.cache_experts -eq $cache })
    if ($rows.Count -ne 3) {
        throw "G45 arm replication mismatch: cache=$cache"
    }
    $armSummary += [pscustomobject]@{
        cache_experts = $cache
        independent_processes = $rows.Count
        ttft_mean_seconds = Get-G45Mean $rows "ttft_seconds"
        ttft_median_seconds = Get-G45Median $rows "ttft_seconds"
        decode_tokens_per_second_mean = Get-G45Mean $rows "decode_tokens_per_second"
        decode_tokens_per_second_median = Get-G45Median $rows "decode_tokens_per_second"
        decode_seconds_mean = Get-G45Mean $rows "decode_seconds"
        decode_seconds_median = Get-G45Median $rows "decode_seconds"
        wrap_seconds_mean = Get-G45Mean $rows "wrap_seconds"
        wrap_seconds_median = Get-G45Median $rows "wrap_seconds"
        process_read_gib_mean = Get-G45Mean $rows "process_read_gib"
        vram_hits_mean = Get-G45Mean $rows "vram_hits"
        ram_hits_mean = Get-G45Mean $rows "ram_hits"
        ram_h2d_gib_mean = Get-G45Mean $rows "ram_h2d_gib"
        promotions_mean = Get-G45Mean $rows "promotions"
        demotions_mean = Get-G45Mean $rows "demotions"
        route_all_hit_calls_mean = Get-G45Mean $rows "route_all_hit_calls"
        route_worker_jobs_mean = Get-G45Mean $rows "route_worker_jobs"
        route_miss_experts_mean = Get-G45Mean $rows "route_miss_experts"
        route_worker_ms_per_job_mean = Get-G45Mean $rows "route_worker_ms_per_job"
        route_resolve_ms_per_call_mean = Get-G45Mean $rows "route_resolve_ms_per_call"
        route_wait_ms_per_call_mean = Get-G45Mean $rows "route_wait_ms_per_call"
        dedicated_peak_gib_mean = Get-G45Mean $rows "dedicated_peak_gib"
        vram_peak_mib_mean = Get-G45Mean $rows "vram_peak_mib"
        available_min_gib_mean = Get-G45Mean $rows "available_min_gib"
        snapshot_misses_sum = ($rows | Measure-Object -Property snapshot_misses -Sum).Sum
        ssd_bytes_sum = ($rows | Measure-Object -Property ssd_bytes -Sum).Sum
        failures_sum = ($rows | Measure-Object -Property failures -Sum).Sum
    }
}

$summary = [pscustomobject]@{
    schema = "g45_direct_resident_cache_ab_v1"
    question = "Does increasing protected direct-resident expert coverage from 256 to 320 reduce pinned-RAM H2D and improve 64-token decode without changing output or using SSD?"
    prompt = $prompt
    context = 256
    max_tokens = 64
    arena_gib = 30
    cache_reserve_gib = 0.125
    expected_content_sha256 = $expected
    independent_processes_per_arm = 3
    within_process_repeats = 1
    warmup = $false
    cache_caveat = "Windows standby/file-cache state cannot be reset by the harness; mirrored ordering and per-run values are retained."
    order = @($runs | ForEach-Object { $_.tag })
    execution_runner_sha256 = if ($SummarizeExisting) {
        $ExecutionRunnerSHA256.ToLowerInvariant()
    } else {
        (Get-FileHash -LiteralPath $MyInvocation.MyCommand.Path -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    summary_runner_sha256 = (Get-FileHash -LiteralPath $MyInvocation.MyCommand.Path -Algorithm SHA256).Hash.ToLowerInvariant()
    summarized_existing_results = [bool]$SummarizeExisting
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

$summaryPath = Join-Path $outdir "g45_direct_resident_cache_ab_result.json"
$summary | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 $summaryPath
Write-Host ("[g45] matrix complete: " + $summaryPath)
