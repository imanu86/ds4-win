# G41 cyberpunk prefill-mass observe/bulk-WRAP matrix (PowerShell 5.1, ASCII).
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$harness = Join-Path $root "g7_measure.ps1"
$outdir = Join-Path $root "g7_runs"
$model = "C:\ds4-models\ds4-2bit.gguf"
$prompt = "Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document."
$expected = "921a62bdb39d9d07161326274fcbc0070f3c4b9e75153d27b1b6dc96811f6e88"
$arenaGiB = 30

function Get-G41Mean {
    param(
        [Parameter(Mandatory=$true)][object[]]$Rows,
        [Parameter(Mandatory=$true)][string]$Property
    )
    [math]::Round(($Rows | Measure-Object -Property $Property -Average).Average, 6)
}

function Invoke-G41Run {
    param(
        [Parameter(Mandatory=$true)][string]$Tag,
        [Parameter(Mandatory=$true)][ValidateSet("observe", "wrap")][string]$Arm
    )

    $useWrap = ($Arm -eq "wrap")
    $args = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $harness,
        "-MaxTokens", "12", "-Repeats", "1",
        "-Tag", $Tag, "-Prompt", $prompt, "-Context", "256",
        "-BudgetGB", "2", "-ReserveMB", "1024", "-RuntimeReserveMB", "128",
        "-DynamicArenaGiB", "$arenaGiB",
        "-DisableQ8F16Cache", "-EmbedRowStaging", "-PrefillChunk", "0",
        "-ReapPrefetchThreads", "8", "-IoQD", "1",
        "-ExpectedContentSHA256", $expected,
        "-ModelPath", $model, "-TimeoutSec", "1200"
    )
    if ($useWrap) {
        $args += "-PrefillMassWrap"
    } else {
        $args += "-PrefillMassObserve"
    }

    Write-Host ("[g41] start tag=" + $Tag + " arm=" + $Arm)
    & powershell.exe @args | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) {
        throw "G41 run failed: $Tag"
    }

    $resultPath = Join-Path $outdir ("g7_" + $Tag + "_result.json")
    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        throw "G41 result missing: $resultPath"
    }
    $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json

    if (-not $result.outputs_identical -or
        $result.expected_content_sha256 -ne $expected -or
        $result.results.Count -ne 1 -or
        $result.results[0].content_sha256 -ne $expected) {
        throw "G41 exact output mismatch: tag=$Tag"
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
        $result.expert_cache_requested -ne 0 -or
        -not $result.q8_f16_cache_disabled -or
        -not $result.embed_row_staging_requested -or
        $result.moe_io_queue_depth -ne 1 -or
        -not $result.prefill_mass_observer_armed -or
        -not $result.prefill_mass_finalized -or
        $result.prefill_mass_candidate_entries -le 0 -or
        $result.prefill_mass_candidate_entries -gt $result.prefill_mass_capacity_entries -or
        $result.prefill_mass_unique_entries -lt $result.prefill_mass_candidate_entries -or
        $result.prefill_mass_coverage -le 0.0 -or
        $result.prefill_mass_coverage -gt 1.0 -or
        $result.prefill_mass_decode_slots -le 0 -or
        $result.prefill_mass_decode_candidate_hits -gt $result.prefill_mass_decode_slots -or
        $result.dynamic_arena_final_fatal -ne 0) {
        throw "G41 configuration/observer mismatch: tag=$Tag"
    }

    if ($useWrap) {
        if ($result.prefill_mass_observe_requested -or
            -not $result.prefill_mass_wrap_requested -or
            $result.prefill_mass_policy_observed -ne "bulk-wrap" -or
            $result.prefill_mass_residency_observed -ne "prefill-ranked" -or
            -not $result.prefill_mass_wrap_observed -or
            $result.prefill_mass_wrap_event_count -ne 1 -or
            $result.prefill_mass_wrap_result -ne "published" -or
            $result.prefill_mass_wrap_reason -ne "ok" -or
            $result.prefill_mass_wrap_router -ne "unbiased" -or
            $result.prefill_mass_wrap_mask -ne "off" -or
            $result.prefill_mass_wrap_candidate_entries -ne $result.prefill_mass_candidate_entries -or
            $result.prefill_mass_wrap_loads -ne $result.prefill_mass_candidate_entries -or
            $result.prefill_mass_wrap_resident_before -ne 0 -or
            $result.prefill_mass_wrap_resident_after -ne $result.prefill_mass_candidate_entries -or
            $result.prefill_mass_wrap_snapshot_before -ne 0 -or
            $result.prefill_mass_wrap_snapshot_after -ne 1 -or
            $result.prefill_mass_wrap_seconds -le 0.0 -or
            -not $result.dynamic_arena_final_observed -or
            $result.dynamic_arena_final_hits -le 0) {
            throw "G41 bulk publication contract mismatch: tag=$Tag"
        }
    } else {
        if (-not $result.prefill_mass_observe_requested -or
            $result.prefill_mass_wrap_requested -or
            $result.prefill_mass_policy_observed -ne "observe-only" -or
            $result.prefill_mass_residency_observed -ne "unchanged" -or
            $result.prefill_mass_wrap_observed -or
            $result.prefill_mass_wrap_event_count -ne 0 -or
            $result.prefill_mass_wrap_seconds -ne 0.0 -or
            $result.prefill_mass_wrap_resident_after -ne 0 -or
            $result.dynamic_arena_final_observed) {
            throw "G41 observe control contract mismatch: tag=$Tag"
        }
    }

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
        ttft_seconds = $result.server_prefill_ttft_mean_seconds
        client_tokens_per_second = $result.mean_tokens_per_second
        decode_tokens_per_second = $result.server_decode_mean_tokens_per_second
        load_seconds = $result.load_seconds
        process_read_bytes = $result.runtime_telemetry.win32_process_read_transfer_delta_bytes
        dedicated_peak_gib = $result.runtime_telemetry.gpu_process_dedicated_peak_bytes / 1GB
        shared_peak_gib = $result.runtime_telemetry.gpu_process_shared_peak_bytes / 1GB
        available_min_gib = $result.runtime_telemetry.windows_available_min_bytes / 1GB
        candidate_entries = $result.prefill_mass_candidate_entries
        capacity_entries = $result.prefill_mass_capacity_entries
        unique_entries = $result.prefill_mass_unique_entries
        mass_coverage = $result.prefill_mass_coverage
        decode_candidate_hit_rate = $result.prefill_mass_decode_hit_rate
        wrap_seconds = $result.prefill_mass_wrap_seconds
        resident_after = $result.prefill_mass_wrap_resident_after
        arena_hits = $result.dynamic_arena_final_hits
        arena_misses = $result.dynamic_arena_final_misses
        arena_h2d_gib = $result.dynamic_arena_h2d_uploaded_gib
    }
}

New-Item -ItemType Directory -Force -Path $outdir | Out-Null

# Three independent one-request processes per arm. The WRAP harness deliberately
# forbids within-process repeats and warmup because only the first snapshot may
# publish. Counter-order balances filesystem-cache and thermal drift.
$runs = @()
$runs += Invoke-G41Run -Tag "g41_observe_a" -Arm "observe"
$runs += Invoke-G41Run -Tag "g41_wrap_a" -Arm "wrap"
$runs += Invoke-G41Run -Tag "g41_wrap_b" -Arm "wrap"
$runs += Invoke-G41Run -Tag "g41_observe_b" -Arm "observe"
$runs += Invoke-G41Run -Tag "g41_observe_c" -Arm "observe"
$runs += Invoke-G41Run -Tag "g41_wrap_c" -Arm "wrap"

$provenanceFields = @(
    "head", "executable_sha256", "ds4_cuda_sha256", "ds4_c_sha256",
    "build_manifest_sha256", "build_input_fingerprint_sha256", "harness_sha256",
    "model", "model_bytes", "model_last_write_utc", "build_worktree_dirty"
)
foreach ($field in $provenanceFields) {
    $values = @($runs | ForEach-Object { [string]($_.$field) } | Select-Object -Unique)
    if ($values.Count -ne 1) {
        throw "G41 mixed provenance across runs: field=$field"
    }
}

$armSummary = @()
foreach ($arm in @("observe", "wrap")) {
    $rows = @($runs | Where-Object { $_.arm -eq $arm })
    if ($rows.Count -ne 3) {
        throw "G41 arm replication mismatch: $arm"
    }
    $armSummary += [pscustomobject]@{
        arm = $arm
        independent_processes = $rows.Count
        ttft_mean_seconds = Get-G41Mean $rows "ttft_seconds"
        client_tokens_per_second_mean = Get-G41Mean $rows "client_tokens_per_second"
        decode_tokens_per_second_mean = Get-G41Mean $rows "decode_tokens_per_second"
        load_seconds_mean = Get-G41Mean $rows "load_seconds"
        process_read_bytes_mean = Get-G41Mean $rows "process_read_bytes"
        dedicated_peak_gib_mean = Get-G41Mean $rows "dedicated_peak_gib"
        shared_peak_gib_mean = Get-G41Mean $rows "shared_peak_gib"
        available_min_gib_mean = Get-G41Mean $rows "available_min_gib"
        candidate_entries_mean = Get-G41Mean $rows "candidate_entries"
        capacity_entries_mean = Get-G41Mean $rows "capacity_entries"
        unique_entries_mean = Get-G41Mean $rows "unique_entries"
        mass_coverage_mean = Get-G41Mean $rows "mass_coverage"
        decode_candidate_hit_rate_mean = Get-G41Mean $rows "decode_candidate_hit_rate"
        wrap_seconds_mean = Get-G41Mean $rows "wrap_seconds"
        resident_after_mean = Get-G41Mean $rows "resident_after"
        arena_hits_mean = Get-G41Mean $rows "arena_hits"
        arena_misses_mean = Get-G41Mean $rows "arena_misses"
        arena_h2d_gib_mean = Get-G41Mean $rows "arena_h2d_gib"
    }
}

$summary = [pscustomobject]@{
    schema = "g41_prefill_bulk_seed_cyberpunk_ab_v1"
    question = "Does one 30 GiB prefill-mass WRAP reduce cyberpunk decode misses and improve decode enough to justify its charged TTFT?"
    prompt = $prompt
    context = 256
    max_tokens = 12
    arena_gib = $arenaGiB
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

$summaryPath = Join-Path $outdir "g41_prefill_bulk_seed_cyberpunk_ab_result.json"
$summary | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 $summaryPath
Write-Host ("[g41] matrix complete: " + $summaryPath)
