# G39 exact double-buffered wave overlap and isolated A/B matrix (PS 5.1).
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$harness = Join-Path $root "g7_measure.ps1"
$outdir = Join-Path $root "g7_runs"
$model = "C:\ds4-models\ds4-2bit.gguf"
$prompt = "Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document."
$expected = "921a62bdb39d9d07161326274fcbc0070f3c4b9e75153d27b1b6dc96811f6e88"
$promptTokens = 43
$moeLayers = 42
$requestsPerProcess = 4

function Invoke-G39Run {
    param(
        [Parameter(Mandatory=$true)][string]$Tag,
        [Parameter(Mandatory=$true)][ValidateSet("production", "serial", "overlap")][string]$Arm
    )
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
    if ($Arm -ne "production") {
        $args += @("-GenericSortedMoe", "-PrefillWaves",
                   "-PrefillWaveForceExperts", "31")
    }
    if ($Arm -eq "overlap") {
        $args += "-PrefillWaveDoubleBuffer"
    }

    Write-Host ("[g39] start tag=" + $Tag + " arm=" + $Arm)
    & powershell.exe @args | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) { throw "G39 run failed: $Tag" }

    $resultPath = Join-Path $outdir ("g7_" + $Tag + "_result.json")
    $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    if (-not $result.outputs_identical -or
        $result.expected_content_sha256 -ne $expected -or
        $null -eq $result.warmup_result -or
        $result.warmup_result.content_sha256 -ne $expected) {
        throw "G39 exact output mismatch: tag=$Tag"
    }
    $expectedCalls = [uint64]($moeLayers * $requestsPerProcess)
    $expectedRows = [uint64]($moeLayers * $promptTokens * $requestsPerProcess)
    if ($result.context_requested -ne 256 -or
        $result.prefill_chunk_requested -ne 0 -or
        $result.prefill_chunk_observed -ne 256 -or
        $result.expert_cache_requested -ne 336 -or
        -not $result.gpu_resident_routes_requested -or
        -not $result.q8_f16_cache_disabled -or
        -not $result.prefill_union_stats_observed -or
        $result.prefill_union_calls -ne $expectedCalls -or
        $result.prefill_union_tokens -ne $expectedRows -or
        $result.prefill_union_selected_slots -ne ($expectedRows * 6)) {
        throw "G39 configuration/accounting mismatch: tag=$Tag"
    }

    $isWave = $Arm -ne "production"
    $isOverlap = $Arm -eq "overlap"
    if ([bool]$result.prefill_waves_requested -ne $isWave -or
        [bool]$result.prefill_waves_observed -ne $isWave -or
        [bool]$result.generic_sorted_moe_requested -ne $isWave -or
        [bool]$result.prefill_wave_double_buffer_requested -ne $isOverlap -or
        [bool]$result.prefill_wave_overlap_observed -ne $isOverlap) {
        throw "G39 arm observation mismatch: tag=$Tag"
    }
    if ($isWave) {
        if ($result.prefill_wave_force_experts_requested -ne 31 -or
            $result.prefill_wave_activations -ne $expectedCalls -or
            $result.prefill_wave_layers -ne $expectedCalls -or
            $result.prefill_wave_count -le $expectedCalls -or
            $result.prefill_wave_max_experts -ne 31 -or
            $result.prefill_wave_active_pairs -ne ($expectedRows * 6) -or
            $result.prefill_wave_unique_experts -ne $result.prefill_union_unique_experts -or
            $result.prefill_wave_upload_waits -ne $result.prefill_wave_count -or
            $result.prefill_wave_failures -ne 0) {
            throw "G39 wave accounting mismatch: tag=$Tag"
        }
    }
    if ($isOverlap) {
        if ($result.prefill_wave_overlap_activations -ne $expectedCalls -or
            $result.prefill_wave_overlap_layers -ne $expectedCalls -or
            $result.prefill_wave_overlap_waves -ne $result.prefill_wave_count -or
            $result.prefill_wave_overlap_compute_records -ne $result.prefill_wave_count -or
            $result.prefill_wave_overlap_reuse_waits -le 0 -or
            $result.prefill_wave_overlap_reuse_waits -ge $result.prefill_wave_count -or
            $result.prefill_wave_overlap_failures -ne 0) {
            throw "G39 overlap accounting mismatch: tag=$Tag"
        }
    } elseif ($result.prefill_wave_overlap_activations -ne 0 -or
              $result.prefill_wave_overlap_failures -ne 0) {
        throw "G39 non-overlap arm reported overlap: tag=$Tag"
    }

    [pscustomobject]@{
        tag = $Tag; arm = $Arm; result_path = $resultPath
        head = $result.head
        executable_sha256 = $result.executable_sha256
        ds4_cuda_sha256 = $result.ds4_cuda_sha256
        ds4_c_sha256 = $result.ds4_c_sha256
        build_manifest_sha256 = $result.build_manifest_sha256
        build_input_fingerprint_sha256 = $result.build_manifest_input_fingerprint_sha256
        harness_sha256 = $result.harness_sha256
        model = $result.model; model_bytes = $result.model_bytes
        model_last_write_utc = $result.model_last_write_utc
        mean_tokens_per_second = $result.mean_tokens_per_second
        server_prefill_ttft_mean_seconds = $result.server_prefill_ttft_mean_seconds
        server_decode_tps_mean = $result.server_decode_mean_tokens_per_second
        process_read_bytes = $result.runtime_telemetry.win32_process_read_transfer_delta_bytes
        dedicated_peak_gib = $result.runtime_telemetry.gpu_process_dedicated_peak_bytes / 1GB
        union_unique_experts = $result.prefill_union_unique_experts
        wave_count = $result.prefill_wave_count
        overlap_reuse_waits = $result.prefill_wave_overlap_reuse_waits
        overlap_failures = $result.prefill_wave_overlap_failures
    }
}

$runs = @()
$runs += Invoke-G39Run -Tag "g39_serial_a" -Arm "serial"
$runs += Invoke-G39Run -Tag "g39_overlap_a" -Arm "overlap"
$runs += Invoke-G39Run -Tag "g39_production_a" -Arm "production"
$runs += Invoke-G39Run -Tag "g39_production_b" -Arm "production"
$runs += Invoke-G39Run -Tag "g39_overlap_b" -Arm "overlap"
$runs += Invoke-G39Run -Tag "g39_serial_b" -Arm "serial"

$provenanceFields = @(
    "head", "executable_sha256", "ds4_cuda_sha256", "ds4_c_sha256",
    "build_manifest_sha256", "build_input_fingerprint_sha256", "harness_sha256",
    "model", "model_bytes", "model_last_write_utc"
)
foreach ($field in $provenanceFields) {
    $values = @($runs | ForEach-Object { [string]($_.$field) } | Select-Object -Unique)
    if ($values.Count -ne 1) { throw "G39 mixed provenance: field=$field" }
}

function Get-Mean([object[]]$Rows, [string]$Property) {
    [math]::Round(($Rows | Measure-Object -Property $Property -Average).Average, 6)
}

$summaryRows = @()
foreach ($arm in @("production", "serial", "overlap")) {
    $rows = @($runs | Where-Object { $_.arm -eq $arm })
    if ($rows.Count -ne 2) { throw "G39 arm replication mismatch: $arm" }
    $summaryRows += [pscustomobject]@{
        arm = $arm; replications = $rows.Count
        ttft_mean_seconds = Get-Mean $rows "server_prefill_ttft_mean_seconds"
        client_tps_mean = Get-Mean $rows "mean_tokens_per_second"
        decode_tps_mean = Get-Mean $rows "server_decode_tps_mean"
        process_read_bytes_mean = Get-Mean $rows "process_read_bytes"
        dedicated_peak_gib_mean = Get-Mean $rows "dedicated_peak_gib"
        union_unique_experts_mean = Get-Mean $rows "union_unique_experts"
        wave_count_mean = Get-Mean $rows "wave_count"
        overlap_reuse_waits_mean = Get-Mean $rows "overlap_reuse_waits"
    }
}

$summary = [pscustomobject]@{
    schema = "g39_prefill_wave_overlap_ab_v1"
    prompt = $prompt; prompt_tokens = $promptTokens
    expected_content_sha256 = $expected
    repeats_per_process = 3; discarded_warmup_per_process = 1
    order = @($runs | ForEach-Object { $_.tag })
    provenance = [pscustomobject]@{
        head = $runs[0].head; executable_sha256 = $runs[0].executable_sha256
        ds4_cuda_sha256 = $runs[0].ds4_cuda_sha256
        ds4_c_sha256 = $runs[0].ds4_c_sha256
        build_manifest_sha256 = $runs[0].build_manifest_sha256
        build_input_fingerprint_sha256 = $runs[0].build_input_fingerprint_sha256
        harness_sha256 = $runs[0].harness_sha256
        model = $runs[0].model; model_bytes = $runs[0].model_bytes
        model_last_write_utc = $runs[0].model_last_write_utc
    }
    runs = $runs
    arm_summary = $summaryRows
}
$summaryPath = Join-Path $outdir "g39_prefill_wave_overlap_ab_result.json"
$summary | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 $summaryPath
Write-Host ("[g39] matrix complete: " + $summaryPath)
