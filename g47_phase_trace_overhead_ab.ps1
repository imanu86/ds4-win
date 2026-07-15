# G47 request-phase trace overhead A/B (PowerShell 5.1, ASCII).
param([switch]$Resume, [switch]$OutlierRecheck)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$harness = Join-Path $root "g7_measure.ps1"
$outdir = Join-Path $root "g7_runs"
$model = "C:\ds4-models\ds4-2bit.gguf"
$prompt = "Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document."
$expected = "31cbc6504dcb57d42aeff9dbceb3aed943bcb32dae19a2edbf552e9fd2f52eb8"
$executable = Join-Path $root "build\Release\ds4_server.exe"
$buildManifest = Join-Path $root "build\Release\g7_build_manifest.json"

function Get-G47SHA256 {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "G47 provenance file missing: $Path"
    }
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$currentProvenance = [pscustomobject]@{
    executable_sha256 = Get-G47SHA256 $executable
    harness_sha256 = Get-G47SHA256 $harness
    ds4_cuda_sha256 = Get-G47SHA256 (Join-Path $root "ds4_cuda.cu")
    ds4_c_sha256 = Get-G47SHA256 (Join-Path $root "ds4.c")
    ds4_server_c_sha256 = Get-G47SHA256 (Join-Path $root "ds4_server.c")
    build_manifest_sha256 = Get-G47SHA256 $buildManifest
}

function Get-G47Mean {
    param([object[]]$Rows, [string]$Property)
    [math]::Round(($Rows | Measure-Object -Property $Property -Average).Average, 6)
}

function Get-G47Median {
    param([object[]]$Rows, [string]$Property)
    $values = @($Rows | ForEach-Object { [double]($_.$Property) } | Sort-Object)
    $middle = [int][math]::Floor($values.Count / 2.0)
    if (($values.Count % 2) -eq 1) {
        return [math]::Round($values[$middle], 6)
    }
    [math]::Round(($values[$middle - 1] + $values[$middle]) / 2.0, 6)
}

function Invoke-G47Run {
    param(
        [Parameter(Mandatory=$true)][string]$Tag,
        [Parameter(Mandatory=$true)][ValidateSet("trace-off", "trace-on")][string]$Arm
    )

    $resultPath = Join-Path $outdir ("g7_" + $Tag + "_result.json")
    $traceExpected = $Arm -eq "trace-on"
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
        "-ExpertCacheN", "320", "-ExpertCacheReserveGB", "0",
        "-ExpertCachePolicy", "lru", "-GpuResidentRoutes",
        "-RouteNoDefaultSync",
        "-ExpertTiering", "enforce", "-ExpertTierPolicy", "mass-lfru",
        "-ExpertTierClockCalls", "430",
        "-ExpertTierReplacementBudget", "16",
        "-ExpertTierMinFrequency", "3",
        "-ExpertTierHysteresis", "1.25"
    )
    if ($traceExpected) {
        $args += "-RequestPhaseTrace"
    }

    if ($Resume -and (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        Write-Host ("[g47] resume tag=" + $Tag + " arm=" + $Arm)
    } else {
        Write-Host ("[g47] start tag=" + $Tag + " arm=" + $Arm)
        & powershell.exe @args | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) { throw "G47 run failed: $Tag" }
    }

    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        throw "G47 result missing: tag=$Tag"
    }
    $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    $tier = $result.expert_tiering

    if ($result.tag -ne $Tag -or
        $result.prompt -ne $prompt -or
        $result.model -ne $model -or
        $result.executable_sha256 -ne $currentProvenance.executable_sha256 -or
        $result.harness_sha256 -ne $currentProvenance.harness_sha256 -or
        $result.ds4_cuda_sha256 -ne $currentProvenance.ds4_cuda_sha256 -or
        $result.ds4_c_sha256 -ne $currentProvenance.ds4_c_sha256 -or
        $result.ds4_server_c_sha256 -ne $currentProvenance.ds4_server_c_sha256 -or
        $result.build_manifest_sha256 -ne $currentProvenance.build_manifest_sha256 -or
        -not $result.outputs_identical -or
        $result.expected_content_sha256 -ne $expected -or
        $result.results.Count -ne 1 -or
        $result.results[0].content_sha256 -ne $expected -or
        $result.requested_max_tokens -ne 64 -or
        $result.context_requested -ne 256 -or
        $result.reserve_mb -ne 1024 -or
        $result.dynamic_arena_gib_requested -ne 30 -or
        $result.expert_cache_requested -ne 320 -or
        $result.expert_cache_capacity -ne 320 -or
        $result.expert_cache_reserve_gb -ne 0 -or
        -not $result.gpu_resident_routes_requested -or
        -not $result.gpu_resident_routes_observed -or
        -not $result.route_no_default_sync_requested -or
        $result.split_hit_miss_requested -or
        -not $result.prefill_mass_wrap_observed -or
        $result.prefill_mass_wrap_result -ne "published" -or
        $result.prefill_mass_wrap_mask -ne "request-scoped-closed" -or
        -not $tier.compose_prefill_mass_tiering_observed -or
        $tier.states_vram -ne 320 -or
        $tier.snapshot_backing_misses -ne 0 -or
        $tier.ssd_bytes -ne 0 -or
        $tier.failures -ne 0 -or
        $result.gpu_resident_routes_errors -ne 0 -or
        $result.gpu_resident_routes_default_sync_calls -ne 0 -or
        $result.gpu_resident_routes_no_default_sync_calls -ne
            $result.gpu_resident_routes_calls -or
        [bool]$result.request_phase_trace_requested -ne $traceExpected -or
        [bool]$result.request_phase_trace_observed -ne $traceExpected) {
        throw "G47 contract mismatch: tag=$Tag"
    }
    if ($traceExpected) {
        if ($result.request_phase_trace_line_count -ne 16 -or
            $result.request_phase_trace_prefill_compute_seconds -le 0 -or
            $result.request_phase_trace_wrap_seconds -le 0 -or
            $result.request_phase_trace_wrap_copy_seconds -le 0 -or
            $result.request_phase_trace_post_wrap_seconds -lt 0 -or
            $result.request_phase_trace_sync_tail_seconds -lt 0 -or
            $result.request_phase_trace_decode_gap_seconds -lt 0 -or
            $result.request_phase_trace_first_sample_seconds -lt 0 -or
            $result.request_phase_trace_first_eval_seconds -le 0 -or
            $result.request_phase_trace_decode_to_first_seconds -le 0 -or
            $result.request_phase_trace_prompt_to_first_seconds -le 0) {
            throw "G47 trace accounting mismatch: tag=$Tag"
        }
    } elseif ($result.request_phase_trace_line_count -ne 0) {
        throw "G47 trace-off emitted phase events: tag=$Tag"
    }

    [pscustomobject]@{
        tag = $Tag
        arm = $Arm
        result_path = $resultPath
        head = $result.head
        executable_sha256 = $result.executable_sha256
        ds4_cuda_sha256 = $result.ds4_cuda_sha256
        ds4_c_sha256 = $result.ds4_c_sha256
        ds4_server_c_sha256 = $result.ds4_server_c_sha256
        build_manifest_sha256 = $result.build_manifest_sha256
        build_input_fingerprint_sha256 = $result.build_manifest_input_fingerprint_sha256
        harness_sha256 = $result.harness_sha256
        model = $result.model
        model_bytes = $result.model_bytes
        model_last_write_utc = $result.model_last_write_utc
        client_wall_seconds = [double]$result.results[0].seconds
        ttft_seconds = [double]$result.server_prefill_ttft_mean_seconds
        wrap_seconds = [double]$result.prefill_mass_wrap_seconds
        decode_tokens_per_second = [double]$result.server_decode_mean_tokens_per_second
        decode_seconds = [double]$result.server_runs[0].server_decode_seconds
        trace_requested = [bool]$result.request_phase_trace_requested
        trace_observed = [bool]$result.request_phase_trace_observed
        trace_line_count = [int]$result.request_phase_trace_line_count
        phase_prefill_compute_seconds = [double]$result.request_phase_trace_prefill_compute_seconds
        phase_wrap_seconds = [double]$result.request_phase_trace_wrap_seconds
        phase_wrap_copy_seconds = [double]$result.request_phase_trace_wrap_copy_seconds
        phase_post_wrap_seconds = [double]$result.request_phase_trace_post_wrap_seconds
        phase_sync_tail_seconds = [double]$result.request_phase_trace_sync_tail_seconds
        phase_decode_gap_seconds = [double]$result.request_phase_trace_decode_gap_seconds
        phase_first_sample_seconds = [double]$result.request_phase_trace_first_sample_seconds
        phase_first_eval_seconds = [double]$result.request_phase_trace_first_eval_seconds
        phase_decode_to_first_seconds = [double]$result.request_phase_trace_decode_to_first_seconds
        phase_prompt_to_first_seconds = [double]$result.request_phase_trace_prompt_to_first_seconds
        vram_hits = [uint64]$tier.vram_hits
        ram_hits = [uint64]$tier.ram_hits
        ram_h2d_gib = [uint64]$tier.ram_h2d_bytes / 1GB
        route_calls = [uint64]$result.gpu_resident_routes_calls
        route_worker_ms_per_job = [double]$result.gpu_resident_routes_worker_ms_per_job
        route_resolve_ms_per_call = [double]$result.gpu_resident_routes_resolve_ms_per_call
        route_wait_ms_per_call = [double]$result.gpu_resident_routes_wait_ms_per_call
        vram_peak_mib = [uint64]$result.runtime_telemetry.vram_used_peak_mib
        available_min_gib = [uint64]$result.runtime_telemetry.windows_available_min_bytes / 1GB
        snapshot_misses = [uint64]$tier.snapshot_backing_misses
        ssd_bytes = [uint64]$tier.ssd_bytes
        failures = [uint64]$tier.failures
    }
}

New-Item -ItemType Directory -Force -Path $outdir | Out-Null
$runs = @()
if ($OutlierRecheck) {
    $runs += Invoke-G47Run -Tag "g47_trace_off_d" -Arm "trace-off"
    $runs += Invoke-G47Run -Tag "g47_trace_on_d" -Arm "trace-on"
    $runs += Invoke-G47Run -Tag "g47_trace_on_e" -Arm "trace-on"
    $runs += Invoke-G47Run -Tag "g47_trace_off_e" -Arm "trace-off"
    $runs += Invoke-G47Run -Tag "g47_trace_off_f" -Arm "trace-off"
    $runs += Invoke-G47Run -Tag "g47_trace_on_f" -Arm "trace-on"
} else {
    $runs += Invoke-G47Run -Tag "g47_trace_off_a" -Arm "trace-off"
    $runs += Invoke-G47Run -Tag "g47_trace_on_a" -Arm "trace-on"
    $runs += Invoke-G47Run -Tag "g47_trace_on_b" -Arm "trace-on"
    $runs += Invoke-G47Run -Tag "g47_trace_off_b" -Arm "trace-off"
    $runs += Invoke-G47Run -Tag "g47_trace_off_c" -Arm "trace-off"
    $runs += Invoke-G47Run -Tag "g47_trace_on_c" -Arm "trace-on"
}

$provenanceFields = @(
    "head", "executable_sha256", "ds4_cuda_sha256", "ds4_c_sha256",
    "ds4_server_c_sha256", "build_manifest_sha256",
    "build_input_fingerprint_sha256", "harness_sha256", "model",
    "model_bytes", "model_last_write_utc"
)
foreach ($field in $provenanceFields) {
    $values = @($runs | ForEach-Object { [string]($_.$field) } | Select-Object -Unique)
    if ($values.Count -ne 1) { throw "G47 mixed provenance: field=$field" }
}

$armSummary = @()
foreach ($arm in @("trace-off", "trace-on")) {
    $rows = @($runs | Where-Object { $_.arm -eq $arm })
    if ($rows.Count -ne 3) { throw "G47 replication mismatch: arm=$arm" }
    $armSummary += [pscustomobject]@{
        arm = $arm
        independent_processes = $rows.Count
        client_wall_seconds_mean = Get-G47Mean $rows "client_wall_seconds"
        client_wall_seconds_median = Get-G47Median $rows "client_wall_seconds"
        decode_tokens_per_second_mean = Get-G47Mean $rows "decode_tokens_per_second"
        decode_tokens_per_second_median = Get-G47Median $rows "decode_tokens_per_second"
        decode_seconds_mean = Get-G47Mean $rows "decode_seconds"
        decode_seconds_median = Get-G47Median $rows "decode_seconds"
        ttft_mean_seconds = Get-G47Mean $rows "ttft_seconds"
        ttft_median_seconds = Get-G47Median $rows "ttft_seconds"
        wrap_mean_seconds = Get-G47Mean $rows "wrap_seconds"
        wrap_median_seconds = Get-G47Median $rows "wrap_seconds"
        vram_hits_mean = Get-G47Mean $rows "vram_hits"
        ram_hits_mean = Get-G47Mean $rows "ram_hits"
        ram_h2d_gib_mean = Get-G47Mean $rows "ram_h2d_gib"
        route_worker_ms_per_job_mean = Get-G47Mean $rows "route_worker_ms_per_job"
        route_resolve_ms_per_call_mean = Get-G47Mean $rows "route_resolve_ms_per_call"
        route_wait_ms_per_call_mean = Get-G47Mean $rows "route_wait_ms_per_call"
        vram_peak_mib_mean = Get-G47Mean $rows "vram_peak_mib"
        snapshot_misses_sum = ($rows | Measure-Object -Property snapshot_misses -Sum).Sum
        ssd_bytes_sum = ($rows | Measure-Object -Property ssd_bytes -Sum).Sum
        failures_sum = ($rows | Measure-Object -Property failures -Sum).Sum
    }
}

$summary = [pscustomobject]@{
    schema = if ($OutlierRecheck) {
        "g47_request_phase_trace_outlier_recheck_v1"
    } else {
        "g47_request_phase_trace_overhead_ab_v1"
    }
    question = if ($OutlierRecheck) {
        "Do three additional processes per arm confirm or reject the low first-sample measurements in the primary G47 matrix?"
    } else {
        "Does CPU-only request-phase telemetry preserve exact output and add negligible overhead to the G46 SOTA path?"
    }
    prompt = $prompt
    context = 256
    max_tokens = 64
    cache_experts = 320
    expected_content_sha256 = $expected
    independent_processes_per_arm = 3
    order = @($runs | ForEach-Object { $_.tag })
    runner_sha256 = (Get-FileHash -LiteralPath $MyInvocation.MyCommand.Path -Algorithm SHA256).Hash.ToLowerInvariant()
    provenance = [pscustomobject]@{
        head = $runs[0].head
        executable_sha256 = $runs[0].executable_sha256
        ds4_cuda_sha256 = $runs[0].ds4_cuda_sha256
        ds4_c_sha256 = $runs[0].ds4_c_sha256
        ds4_server_c_sha256 = $runs[0].ds4_server_c_sha256
        build_manifest_sha256 = $runs[0].build_manifest_sha256
        build_input_fingerprint_sha256 = $runs[0].build_input_fingerprint_sha256
        harness_sha256 = $runs[0].harness_sha256
        model = $runs[0].model
        model_bytes = $runs[0].model_bytes
        model_last_write_utc = $runs[0].model_last_write_utc
    }
    runs = $runs
    arm_summary = $armSummary
}

$summaryName = if ($OutlierRecheck) {
    "g47_phase_trace_outlier_recheck_result.json"
} else {
    "g47_phase_trace_overhead_ab_result.json"
}
$summaryPath = Join-Path $outdir $summaryName
$summary | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 $summaryPath
Write-Host ("[g47] matrix complete: " + $summaryPath)
