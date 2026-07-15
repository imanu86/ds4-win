# G52 source-parts WRAP mmap versus sequential-file A/B (PowerShell 5.1, ASCII).
param(
    [switch]$Resume,
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
$executable = Join-Path $root "build\Release\ds4_server.exe"
$buildManifest = Join-Path $root "build\Release\g7_build_manifest.json"

function Get-G52SHA256 {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "G52 provenance file missing: $Path"
    }
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-G52Mean {
    param(
        [Parameter(Mandatory=$true)][object[]]$Rows,
        [Parameter(Mandatory=$true)][string]$Property
    )
    $values = @($Rows | ForEach-Object { $_.$Property } |
        Where-Object { $null -ne $_ })
    if ($values.Count -eq 0) { return $null }
    [math]::Round(($values | Measure-Object -Average).Average, 6)
}

function Get-G52Median {
    param(
        [Parameter(Mandatory=$true)][object[]]$Rows,
        [Parameter(Mandatory=$true)][string]$Property
    )
    $values = @($Rows | ForEach-Object { $_.$Property } |
        Where-Object { $null -ne $_ } |
        ForEach-Object { [double]$_ } | Sort-Object)
    if ($values.Count -eq 0) { return $null }
    $middle = [int][math]::Floor($values.Count / 2.0)
    if (($values.Count % 2) -eq 1) {
        return [math]::Round($values[$middle], 6)
    }
    [math]::Round(($values[$middle - 1] + $values[$middle]) / 2.0, 6)
}

function Assert-G52Property {
    param(
        [Parameter(Mandatory=$true)][object]$Object,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Tag
    )
    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) {
        throw "G52 required field missing: tag=$Tag field=$Name"
    }
}

function Get-G52Property {
    param([object]$Object, [string]$Name)
    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) {
        return $null
    }
    $Object.PSObject.Properties[$Name].Value
}

function Convert-G52BytesToGiB {
    param([object]$Value)
    if ($null -eq $Value) { return $null }
    [math]::Round(([double]$Value / 1GB), 6)
}

function Test-G52HarnessParameter {
    param([Parameter(Mandatory=$true)][string]$ParameterName)
    $content = Get-Content -LiteralPath $harness -Raw
    return ($content -match ("\$" + [regex]::Escape($ParameterName) +
        "(\s|=|,|\))"))
}

$provenance = [pscustomobject]@{
    executable_sha256 = Get-G52SHA256 $executable
    harness_sha256 = Get-G52SHA256 $harness
    ds4_cuda_sha256 = Get-G52SHA256 (Join-Path $root "ds4_cuda.cu")
    ds4_c_sha256 = Get-G52SHA256 (Join-Path $root "ds4.c")
    ds4_server_c_sha256 = Get-G52SHA256 (Join-Path $root "ds4_server.c")
    build_manifest_sha256 = Get-G52SHA256 $buildManifest
}

function Invoke-G52Run {
    param(
        [Parameter(Mandatory=$true)][string]$Tag,
        [Parameter(Mandatory=$true)]
        [ValidateSet("mmap", "sequential-file")]
        [string]$Source
    )

    $resultPath = Join-Path $outdir ("g7_" + $Tag + "_result.json")
    $args = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $harness,
        "-MaxTokens", "64", "-Repeats", "1", "-Tag", $Tag,
        "-Prompt", $prompt, "-Context", "256",
        "-BudgetGB", "2", "-ReserveMB", "1024",
        "-DynamicArenaGiB", "30", "-ArenaWrapTrustWorkerChecksum",
        "-ArenaWrapSourceParts", "-DisableQ8F16Cache", "-EmbedRowStaging",
        "-ReapPrefetchThreads", "8", "-ExpectedContentSHA256", $expected,
        "-ModelPath", $model, "-TimeoutSec", "1200",
        "-PrefillMassWrap", "-ComposePrefillMassTiering",
        "-ExpertCacheN", "320", "-ExpertCacheReserveGB", "0.125",
        "-ExpertCachePolicy", "lru", "-GpuResidentRoutes",
        "-RouteNoDefaultSync",
        "-ExpertTiering", "enforce", "-ExpertTierPolicy", "mass-lfru",
        "-ExpertTierClockCalls", "430",
        "-ExpertTierReplacementBudget", "16",
        "-ExpertTierMinFrequency", "3",
        "-ExpertTierHysteresis", "1.25"
    )
    if ($Source -eq "sequential-file") {
        $args += "-ArenaWrapSequentialFile"
    }

    if (($Resume -or $SummarizeExisting) -and
        (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        Write-Host ("[g52] validate existing tag=" + $Tag +
            " source=" + $Source)
    } elseif ($SummarizeExisting) {
        throw "G52 existing result missing: tag=$Tag"
    } else {
        Write-Host ("[g52] start tag=" + $Tag + " source=" + $Source)
        & powershell.exe @args | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) { throw "G52 run failed: $Tag" }
    }

    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        throw "G52 result missing: tag=$Tag"
    }
    $r = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    $tier = $r.expert_tiering
    $mem = $r.memory_preflight
    $proc = $r.process_isolation_preflight
    $sys = $r.system_quiescence_preflight
    $rt = $r.runtime_telemetry
    $wantSequential = ($Source -eq "sequential-file")

    foreach ($name in @(
        "arena_wrap_source_requested",
        "arena_wrap_source_observed")) {
        Assert-G52Property -Object $r -Name $name -Tag $Tag
    }

    if ($r.tag -ne $Tag -or $r.prompt -ne $prompt -or
        $r.model -ne $model -or $r.repeats -ne 1 -or $r.warmup -or
        $r.requested_max_tokens -ne 64 -or $r.context_requested -ne 256 -or
        $r.executable_sha256 -ne $provenance.executable_sha256 -or
        $r.harness_sha256 -ne $provenance.harness_sha256 -or
        $r.ds4_cuda_sha256 -ne $provenance.ds4_cuda_sha256 -or
        $r.ds4_c_sha256 -ne $provenance.ds4_c_sha256 -or
        $r.ds4_server_c_sha256 -ne $provenance.ds4_server_c_sha256 -or
        $r.build_manifest_sha256 -ne $provenance.build_manifest_sha256 -or
        -not $r.outputs_identical -or
        $r.expected_content_sha256 -ne $expected -or
        $r.results.Count -ne 1 -or
        $r.results[0].content_sha256 -ne $expected -or
        $r.budget_gb -ne 2 -or $r.reserve_mb -ne 1024 -or
        $r.dynamic_arena_gib_requested -ne 30 -or
        -not $r.arena_wrap_trust_worker_checksum_requested -or
        $r.arena_wrap_schedule_observed -ne "source-parts" -or
        $r.arena_wrap_checksum_observed -ne "fnv1a64-worker-only" -or
        [bool]$r.arena_wrap_sequential_file_requested -ne $wantSequential -or
        $r.arena_wrap_source_requested -ne $Source -or
        $r.arena_wrap_source_observed -ne $Source -or
        -not $r.prefill_mass_wrap_requested -or
        -not $r.prefill_mass_wrap_observed -or
        $r.prefill_mass_wrap_result -ne "published" -or
        $r.prefill_mass_wrap_reason -ne "ok" -or
        $r.prefill_mass_wrap_mask -ne "request-scoped-closed" -or
        -not $r.compose_prefill_mass_tiering_requested -or
        -not $tier.compose_prefill_mass_tiering_observed -or
        -not $r.gpu_resident_routes_requested -or
        -not $r.gpu_resident_routes_observed -or
        -not $r.route_no_default_sync_requested -or
        $r.gpu_resident_routes_default_sync_calls -ne 0 -or
        $r.gpu_resident_routes_no_default_sync_calls -ne
            $r.gpu_resident_routes_calls -or
        $r.gpu_resident_routes_errors -ne 0 -or
        $r.split_hit_miss_requested -or
        $r.spex_dry_run_requested -or
        $r.spex_observed -or
        $r.q8_f16_cache_disabled -ne $true -or
        $r.diagnostics -or
        $r.arena_wrap_trim_between_phases_requested -or
        $r.arena_wrap_trim_observed -or
        $r.arena_wrap_part_profile_requested -or
        $r.arena_wrap_part_profile_observed -or
        $r.expert_cache_requested -ne 320 -or
        $r.expert_cache_capacity -ne 320 -or
        $r.expert_cache_reserve_gb -ne 0.125 -or
        $r.expert_cache_policy -ne "lru" -or
        $r.expert_tiering_requested -ne "enforce" -or
        $r.expert_tier_policy_requested -ne "mass-lfru" -or
        $r.expert_tier_clock_calls_requested -ne 430 -or
        $r.expert_tier_replacement_budget_requested -ne 16 -or
        $r.expert_tier_min_frequency_requested -ne 3 -or
        $r.expert_tier_hysteresis_requested -ne 1.25 -or
        $tier.mode -ne "enforce" -or
        $tier.policy -ne "mass-lfru" -or
        $tier.clock_calls -ne 430 -or
        $tier.replacement_budget -ne 16 -or
        $tier.min_frequency -ne 3 -or
        $tier.hysteresis -ne 1.25 -or
        $tier.states_vram -ne 320 -or
        $tier.snapshot_backing_misses -ne 0 -or
        $tier.ssd_bytes -ne 0 -or
        $tier.failures -ne 0 -or
        $tier.forbidden_cold_ssd_to_vram -ne 0 -or
        $mem.ready_to_launch -ne $true -or
        $proc.ready_to_launch -ne $true -or
        $sys.ready_to_launch -ne $true) {
        throw "G52 contract mismatch: tag=$Tag"
    }

    $wrapSeconds = if ($null -ne $r.arena_wrap_profile_total_seconds) {
        [double]$r.arena_wrap_profile_total_seconds
    } else {
        [double]$r.prefill_mass_wrap_seconds
    }

    [pscustomobject]@{
        tag = $Tag
        arm = $Source
        result_path = $resultPath
        head = $r.head
        executable_sha256 = $r.executable_sha256
        ds4_cuda_sha256 = $r.ds4_cuda_sha256
        ds4_c_sha256 = $r.ds4_c_sha256
        ds4_server_c_sha256 = $r.ds4_server_c_sha256
        build_manifest_sha256 = $r.build_manifest_sha256
        build_input_fingerprint_sha256 =
            $r.build_manifest_input_fingerprint_sha256
        harness_sha256 = $r.harness_sha256
        model = $r.model
        model_bytes = $r.model_bytes
        model_last_write_utc = $r.model_last_write_utc
        build_worktree_dirty = $r.build_manifest_worktree_dirty_at_build_start
        content_sha256 = $r.results[0].content_sha256
        source_requested = [string]$r.arena_wrap_source_requested
        source_observed = [string]$r.arena_wrap_source_observed
        sequential_file_requested =
            [bool]$r.arena_wrap_sequential_file_requested
        ttft_seconds = [double]$r.server_prefill_ttft_mean_seconds
        wrap_seconds = $wrapSeconds
        wrap_copy_seconds =
            if ($null -ne $r.arena_wrap_source_parts_copy_seconds) {
                [double]$r.arena_wrap_source_parts_copy_seconds
            } else { $null }
        wrap_checksum_seconds =
            if ($null -ne $r.arena_wrap_source_parts_checksum_seconds) {
                [double]$r.arena_wrap_source_parts_checksum_seconds
            } else { $null }
        decode_tokens_per_second =
            [double]$r.server_decode_mean_tokens_per_second
        decode_seconds = [double]$r.server_runs[0].server_decode_seconds
        vram_hits = [uint64]$tier.vram_hits
        ram_hits = [uint64]$tier.ram_hits
        ram_h2d_gib = Convert-G52BytesToGiB $tier.ram_h2d_bytes
        route_calls = [uint64]$r.gpu_resident_routes_calls
        route_all_hit_calls = [uint64]$r.gpu_resident_routes_all_hit
        route_vram_routes = [uint64]$r.gpu_resident_routes_vram_routes
        route_pinned_ram_routes =
            [uint64]$r.gpu_resident_routes_pinned_ram_routes
        route_h2d_gib =
            Convert-G52BytesToGiB $r.gpu_resident_routes_h2d_bytes
        route_worker_jobs = [uint64]$r.gpu_resident_routes_worker_jobs
        route_miss_experts = [uint64]$r.gpu_resident_routes_miss_experts
        route_worker_ms_per_job =
            [double]$r.gpu_resident_routes_worker_ms_per_job
        route_wait_ms_per_call =
            [double]$r.gpu_resident_routes_wait_ms_per_call
        route_resolve_ms_per_call =
            [double]$r.gpu_resident_routes_resolve_ms_per_call
        windows_available_min_gib =
            Convert-G52BytesToGiB $rt.windows_available_min_bytes
        working_set_peak_gib =
            Convert-G52BytesToGiB $rt.process_working_set_peak_bytes
        private_peak_gib =
            Convert-G52BytesToGiB $rt.process_private_peak_bytes
        gpu_shared_peak_gib =
            Convert-G52BytesToGiB $rt.gpu_process_shared_peak_bytes
        gpu_dedicated_peak_gib =
            Convert-G52BytesToGiB $rt.gpu_process_dedicated_peak_bytes
        page_fault_delta = Get-G52Property $rt "page_fault_delta"
        process_read_gib =
            Convert-G52BytesToGiB $rt.win32_process_read_transfer_delta_bytes
        process_write_gib =
            Convert-G52BytesToGiB $rt.win32_process_write_transfer_delta_bytes
        process_read_operation_delta =
            Get-G52Property $rt "win32_process_read_operation_delta"
        process_other_operation_delta =
            Get-G52Property $rt "win32_process_other_operation_delta"
        process_read_throughput_mib_per_second =
            Get-G52Property $rt "process_read_throughput_mib_per_second"
        disk_read_gib =
            Convert-G52BytesToGiB (Get-G52Property $rt "disk_read_bytes")
        disk_read_mib_per_second =
            Get-G52Property $rt "disk_read_mib_per_second"
        disk_read_throughput_mib_per_second =
            Get-G52Property $rt "disk_read_throughput_mib_per_second"
        disk_queue_length = Get-G52Property $rt "disk_queue_length"
        disk_queue_length_peak =
            Get-G52Property $rt "disk_queue_length_peak"
        mmap_backed_file_io_measured =
            Get-G52Property $rt "mmap_backed_file_io_measured"
        snapshot_misses = [uint64]$tier.snapshot_backing_misses
        ssd_bytes = [uint64]$tier.ssd_bytes
        failures = [uint64]$tier.failures
        memory_preflight_ready = [bool]$mem.ready_to_launch
        process_preflight_ready = [bool]$proc.ready_to_launch
        system_preflight_ready = [bool]$sys.ready_to_launch
    }
}

New-Item -ItemType Directory -Force -Path $outdir | Out-Null
if ($SummarizeExisting -and
    $ExecutionRunnerSHA256 -notmatch '^[0-9a-fA-F]{64}$') {
    throw "SummarizeExisting requires -ExecutionRunnerSHA256"
}
if (-not $SummarizeExisting -and
    -not (Test-G52HarnessParameter -ParameterName "ArenaWrapSequentialFile")) {
    throw "Harness does not expose -ArenaWrapSequentialFile; refusing to launch model."
}

$runs = @()
$runPlan = @(
    @{ Tag = "g52_wrap_seq_on_a"; Source = "sequential-file" },
    @{ Tag = "g52_wrap_seq_off_a"; Source = "mmap" },
    @{ Tag = "g52_wrap_seq_off_b"; Source = "mmap" },
    @{ Tag = "g52_wrap_seq_on_b"; Source = "sequential-file" },
    @{ Tag = "g52_wrap_seq_on_c"; Source = "sequential-file" },
    @{ Tag = "g52_wrap_seq_off_c"; Source = "mmap" }
)
foreach ($item in $runPlan) {
    $runs += Invoke-G52Run -Tag $item.Tag -Source $item.Source
}

$provenanceFields = @(
    "head", "executable_sha256", "ds4_cuda_sha256", "ds4_c_sha256",
    "ds4_server_c_sha256", "build_manifest_sha256",
    "build_input_fingerprint_sha256", "harness_sha256", "model",
    "model_bytes", "model_last_write_utc", "build_worktree_dirty"
)
foreach ($field in $provenanceFields) {
    $values = @($runs | ForEach-Object { [string]($_.$field) } |
        Select-Object -Unique)
    if ($values.Count -ne 1) {
        throw "G52 mixed provenance across runs: field=$field"
    }
}

$armSummary = @()
foreach ($arm in @("mmap", "sequential-file")) {
    $rows = @($runs | Where-Object { $_.arm -eq $arm })
    if ($rows.Count -ne 3) { throw "G52 replication mismatch: arm=$arm" }
    $armSummary += [pscustomobject]@{
        arm = $arm
        independent_processes = $rows.Count
        ttft_mean_seconds = Get-G52Mean $rows "ttft_seconds"
        ttft_median_seconds = Get-G52Median $rows "ttft_seconds"
        wrap_seconds_mean = Get-G52Mean $rows "wrap_seconds"
        wrap_seconds_median = Get-G52Median $rows "wrap_seconds"
        decode_tokens_per_second_mean =
            Get-G52Mean $rows "decode_tokens_per_second"
        decode_tokens_per_second_median =
            Get-G52Median $rows "decode_tokens_per_second"
        decode_seconds_mean = Get-G52Mean $rows "decode_seconds"
        windows_available_min_gib_mean =
            Get-G52Mean $rows "windows_available_min_gib"
        working_set_peak_gib_mean =
            Get-G52Mean $rows "working_set_peak_gib"
        private_peak_gib_mean = Get-G52Mean $rows "private_peak_gib"
        gpu_shared_peak_gib_mean =
            Get-G52Mean $rows "gpu_shared_peak_gib"
        process_read_gib_mean = Get-G52Mean $rows "process_read_gib"
        process_write_gib_mean = Get-G52Mean $rows "process_write_gib"
        page_fault_delta_mean = Get-G52Mean $rows "page_fault_delta"
        disk_read_gib_mean = Get-G52Mean $rows "disk_read_gib"
        disk_read_mib_per_second_mean =
            Get-G52Mean $rows "disk_read_mib_per_second"
        disk_read_throughput_mib_per_second_mean =
            Get-G52Mean $rows "disk_read_throughput_mib_per_second"
        disk_queue_length_peak_mean =
            Get-G52Mean $rows "disk_queue_length_peak"
        snapshot_misses_sum =
            ($rows | Measure-Object -Property snapshot_misses -Sum).Sum
        ssd_bytes_sum = ($rows | Measure-Object -Property ssd_bytes -Sum).Sum
        failures_sum = ($rows | Measure-Object -Property failures -Sum).Sum
    }
}

$summary = [pscustomobject]@{
    schema = "g52_wrap_sequential_file_ab_v1"
    question = "Current SOTA mmap source-parts WRAP versus candidate -ArenaWrapSequentialFile on the exact G45 cyberpunk prompt."
    prompt = $prompt
    context = 256
    max_tokens = 64
    arena_gib = 30
    cache_experts = 320
    cache_reserve_gib = 0.125
    expected_content_sha256 = $expected
    independent_processes_per_arm = 3
    within_process_repeats = 1
    system_file_cache_flushed_between_runs = $false
    order_contract = "counterbalanced sequential-file,mmap,mmap,sequential-file,sequential-file,mmap; interpret cold-start TTFT separately from decode and within-process memory telemetry"
    order = @($runs | ForEach-Object { $_.tag })
    control_source = "mmap"
    candidate_source = "sequential-file"
    route_no_default_sync = $true
    q8_f16_cache = "disabled"
    excluded_features = @(
        "split-hit-miss", "SPEX", "static-mask", "trim", "diagnostics",
        "arena-wrap-part-profile")
    summarized_existing_results = [bool]$SummarizeExisting
    execution_runner_sha256 = if ($SummarizeExisting) {
        $ExecutionRunnerSHA256.ToLowerInvariant()
    } else {
        Get-G52SHA256 $MyInvocation.MyCommand.Path
    }
    summary_runner_sha256 = Get-G52SHA256 $MyInvocation.MyCommand.Path
    provenance = [pscustomobject]@{
        head = $runs[0].head
        executable_sha256 = $runs[0].executable_sha256
        ds4_cuda_sha256 = $runs[0].ds4_cuda_sha256
        ds4_c_sha256 = $runs[0].ds4_c_sha256
        ds4_server_c_sha256 = $runs[0].ds4_server_c_sha256
        build_manifest_sha256 = $runs[0].build_manifest_sha256
        build_input_fingerprint_sha256 =
            $runs[0].build_input_fingerprint_sha256
        harness_sha256 = $runs[0].harness_sha256
        model = $runs[0].model
        model_bytes = $runs[0].model_bytes
        model_last_write_utc = $runs[0].model_last_write_utc
        build_worktree_dirty = $runs[0].build_worktree_dirty
    }
    runs = $runs
    arm_summary = $armSummary
}

$summaryPath = Join-Path $outdir "g52_wrap_sequential_file_ab_result.json"
$summary | ConvertTo-Json -Depth 10 |
    Set-Content -LiteralPath $summaryPath -Encoding UTF8
Write-Host ("[g52] matrix complete: " + $summaryPath)
