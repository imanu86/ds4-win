# G41 long cyberpunk observe/bulk-WRAP matrix (PowerShell 5.1, ASCII).
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$harness = Join-Path $root "g7_measure.ps1"
$outdir = Join-Path $root "g7_runs"
$model = "C:\ds4-models\ds4-2bit.gguf"
$prompt = "Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document."
$expected = "84e295af09e93a34a4ba2bc70c69f2b6f8ee0f129070e6c07d3ba31ea6f97bb1"

function Get-G41LMean {
    param([object[]]$Rows, [string]$Property)
    [math]::Round(($Rows | Measure-Object -Property $Property -Average).Average, 6)
}

function Invoke-G41LRun {
    param(
        [Parameter(Mandatory=$true)][string]$Tag,
        [Parameter(Mandatory=$true)][ValidateSet("observe", "wrap")][string]$Arm
    )
    $wrap = $Arm -eq "wrap"
    $args = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $harness,
        "-Tag", $Tag, "-Prompt", $prompt,
        "-MaxTokens", "128", "-Repeats", "1", "-Context", "512",
        "-BudgetGB", "2", "-ReserveMB", "1024", "-RuntimeReserveMB", "128",
        "-DynamicArenaGiB", "30", "-DisableQ8F16Cache", "-EmbedRowStaging",
        "-PrefillChunk", "0", "-ReapPrefetchThreads", "8", "-IoQD", "1",
        "-ExpectedContentSHA256", $expected,
        "-ModelPath", $model, "-TimeoutSec", "1200"
    )
    $args += $(if ($wrap) { "-PrefillMassWrap" } else { "-PrefillMassObserve" })
    Write-Host ("[g41-long] start tag=" + $Tag + " arm=" + $Arm)
    & powershell.exe @args | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) { throw "G41 long run failed: $Tag" }

    $path = Join-Path $outdir ("g7_" + $Tag + "_result.json")
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "G41 long result missing: $path"
    }
    $j = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    if (-not $j.outputs_identical -or
        $j.results.Count -ne 1 -or
        $j.results[0].content_sha256 -ne $expected -or
        $j.results[0].completion_tokens -ne 128 -or
        $j.server_runs[0].finish_reason -ne "length" -or
        $j.context_requested -ne 512 -or
        $j.requested_max_tokens -ne 128 -or
        $j.repeats -ne 1 -or $j.warmup -or
        $j.dynamic_arena_gib_requested -ne 30 -or
        $j.expert_cache_requested -ne 0 -or
        -not $j.q8_f16_cache_disabled -or
        -not $j.embed_row_staging_requested -or
        -not $j.prefill_mass_observer_armed -or
        -not $j.prefill_mass_finalized -or
        $j.prefill_mass_candidate_entries -le 0 -or
        $j.prefill_mass_candidate_entries -gt $j.prefill_mass_capacity_entries -or
        $j.prefill_mass_decode_slots -le 0 -or
        $j.prefill_mass_decode_hit_rate -le 0.0 -or
        $j.dynamic_arena_final_fatal -ne 0) {
        throw "G41 long common contract mismatch: $Tag"
    }
    if ($wrap) {
        if (-not $j.prefill_mass_wrap_requested -or
            $j.prefill_mass_observe_requested -or
            $j.prefill_mass_policy_observed -ne "bulk-wrap" -or
            $j.prefill_mass_wrap_event_count -ne 1 -or
            $j.prefill_mass_wrap_result -ne "published" -or
            $j.prefill_mass_wrap_reason -ne "ok" -or
            $j.prefill_mass_wrap_router -ne "unbiased" -or
            $j.prefill_mass_wrap_mask -ne "off" -or
            $j.prefill_mass_wrap_loads -ne $j.prefill_mass_candidate_entries -or
            $j.prefill_mass_wrap_resident_after -ne $j.prefill_mass_candidate_entries -or
            $j.prefill_mass_wrap_snapshot_before -ne 0 -or
            $j.prefill_mass_wrap_snapshot_after -ne 1 -or
            $j.prefill_mass_wrap_seconds -le 0.0 -or
            -not $j.dynamic_arena_final_observed -or
            $j.dynamic_arena_final_hits -le 0) {
            throw "G41 long WRAP contract mismatch: $Tag"
        }
    } else {
        if (-not $j.prefill_mass_observe_requested -or
            $j.prefill_mass_wrap_requested -or
            $j.prefill_mass_policy_observed -ne "observe-only" -or
            $j.prefill_mass_wrap_event_count -ne 0 -or
            $j.prefill_mass_wrap_seconds -ne 0.0 -or
            $j.dynamic_arena_final_observed) {
            throw "G41 long observe contract mismatch: $Tag"
        }
    }
    [pscustomobject]@{
        tag = $Tag
        arm = $Arm
        path = $path
        head = $j.head
        executable_sha256 = $j.executable_sha256
        ds4_cuda_sha256 = $j.ds4_cuda_sha256
        ds4_c_sha256 = $j.ds4_c_sha256
        manifest_sha256 = $j.build_manifest_sha256
        fingerprint_sha256 = $j.build_manifest_input_fingerprint_sha256
        harness_sha256 = $j.harness_sha256
        model = $j.model
        model_bytes = $j.model_bytes
        model_last_write_utc = $j.model_last_write_utc
        build_dirty = $j.build_manifest_worktree_dirty_at_build_start
        ttft = $j.server_prefill_ttft_mean_seconds
        decode_tps = $j.server_decode_mean_tokens_per_second
        client_tps = $j.mean_tokens_per_second
        elapsed = $j.results[0].seconds
        reads = $j.runtime_telemetry.win32_process_read_transfer_delta_bytes
        shared_peak_gib = $j.runtime_telemetry.gpu_process_shared_peak_bytes / 1GB
        dedicated_peak_gib = $j.runtime_telemetry.gpu_process_dedicated_peak_bytes / 1GB
        available_min_gib = $j.runtime_telemetry.windows_available_min_bytes / 1GB
        candidate = $j.prefill_mass_candidate_entries
        decode_hit_rate = $j.prefill_mass_decode_hit_rate
        wrap_seconds = $j.prefill_mass_wrap_seconds
        arena_hits = $j.dynamic_arena_final_hits
        arena_misses = $j.dynamic_arena_final_misses
        arena_h2d_gib = $j.dynamic_arena_h2d_uploaded_gib
    }
}

New-Item -ItemType Directory -Force -Path $outdir | Out-Null
$runs = @()
$runs += Invoke-G41LRun "g41_long128_observe_a" "observe"
$runs += Invoke-G41LRun "g41_long128_wrap_a" "wrap"
$runs += Invoke-G41LRun "g41_long128_wrap_b" "wrap"
$runs += Invoke-G41LRun "g41_long128_observe_b" "observe"
$runs += Invoke-G41LRun "g41_long128_observe_c" "observe"
$runs += Invoke-G41LRun "g41_long128_wrap_c" "wrap"

foreach ($field in @("head", "executable_sha256", "ds4_cuda_sha256", "ds4_c_sha256",
        "manifest_sha256", "fingerprint_sha256", "harness_sha256", "model",
        "model_bytes", "model_last_write_utc", "build_dirty")) {
    $values = @($runs | ForEach-Object { [string]($_.$field) } | Select-Object -Unique)
    if ($values.Count -ne 1) { throw "G41 long mixed provenance: $field" }
}

$arms = @()
foreach ($arm in @("observe", "wrap")) {
    $rows = @($runs | Where-Object arm -eq $arm)
    if ($rows.Count -ne 3) { throw "G41 long replication mismatch: $arm" }
    $arms += [pscustomobject]@{
        arm = $arm
        independent_processes = 3
        ttft_mean_seconds = Get-G41LMean $rows "ttft"
        decode_tokens_per_second_mean = Get-G41LMean $rows "decode_tps"
        client_tokens_per_second_mean = Get-G41LMean $rows "client_tps"
        elapsed_mean_seconds = Get-G41LMean $rows "elapsed"
        process_read_bytes_mean = Get-G41LMean $rows "reads"
        shared_peak_gib_mean = Get-G41LMean $rows "shared_peak_gib"
        dedicated_peak_gib_mean = Get-G41LMean $rows "dedicated_peak_gib"
        available_min_gib_mean = Get-G41LMean $rows "available_min_gib"
        candidate_entries_mean = Get-G41LMean $rows "candidate"
        decode_candidate_hit_rate_mean = Get-G41LMean $rows "decode_hit_rate"
        wrap_seconds_mean = Get-G41LMean $rows "wrap_seconds"
        arena_hits_mean = Get-G41LMean $rows "arena_hits"
        arena_misses_mean = Get-G41LMean $rows "arena_misses"
        arena_h2d_gib_mean = Get-G41LMean $rows "arena_h2d_gib"
    }
}

$summary = [pscustomobject]@{
    schema = "g41_long128_prefill_bulk_seed_ab_v1"
    prompt = $prompt
    context = 512
    max_tokens = 128
    expected_content_sha256 = $expected
    arena_gib = 30
    independent_processes_per_arm = 3
    order = @($runs | ForEach-Object tag)
    reference_result = "g7_runs/g7_g41_long128_observe_reference_n1_result.json"
    provenance = [pscustomobject]@{
        head = $runs[0].head
        executable_sha256 = $runs[0].executable_sha256
        ds4_cuda_sha256 = $runs[0].ds4_cuda_sha256
        ds4_c_sha256 = $runs[0].ds4_c_sha256
        build_manifest_sha256 = $runs[0].manifest_sha256
        build_input_fingerprint_sha256 = $runs[0].fingerprint_sha256
        harness_sha256 = $runs[0].harness_sha256
    }
    runs = $runs
    arm_summary = $arms
}
$summaryPath = Join-Path $outdir "g41_long128_prefill_bulk_seed_ab_result.json"
$summary | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 $summaryPath
Write-Host ("[g41-long] matrix complete: " + $summaryPath)
