# G49 source-parts worker-profile overhead and long-tail diagnostic.
param([switch]$Resume)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$harness = Join-Path $root "g7_measure.ps1"
$outdir = Join-Path $root "g7_runs"
$model = "C:\ds4-models\ds4-2bit.gguf"
$prompt = "Rispondi in italiano con quattro punti numerati: spiega la differenza tra RAM, VRAM e memoria virtuale. Sii conciso."
$executable = Join-Path $root "build\Release\ds4_server.exe"
$buildManifest = Join-Path $root "build\Release\g7_build_manifest.json"

function Get-G49SHA256([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "G49 provenance file missing: $Path"
    }
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$provenance = [pscustomobject]@{
    executable_sha256 = Get-G49SHA256 $executable
    harness_sha256 = Get-G49SHA256 $harness
    ds4_cuda_sha256 = Get-G49SHA256 (Join-Path $root "ds4_cuda.cu")
    ds4_c_sha256 = Get-G49SHA256 (Join-Path $root "ds4.c")
    ds4_server_c_sha256 = Get-G49SHA256 (Join-Path $root "ds4_server.c")
    build_manifest_sha256 = Get-G49SHA256 $buildManifest
}

function Get-G49Median([double[]]$Values) {
    $ordered = @($Values | Sort-Object)
    if (-not $ordered.Count) { return 0.0 }
    $middle = [int][math]::Floor($ordered.Count / 2)
    if (($ordered.Count % 2) -eq 1) { return [double]$ordered[$middle] }
    return ([double]$ordered[$middle - 1] + [double]$ordered[$middle]) / 2.0
}

function Invoke-G49Run {
    param(
        [Parameter(Mandatory=$true)][string]$Tag,
        [Parameter(Mandatory=$true)][bool]$Profile,
        [string]$ExpectedSHA256 = ""
    )
    $resultPath = Join-Path $outdir ("g7_" + $Tag + "_result.json")
    $args = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $harness,
        "-MaxTokens", "8", "-Repeats", "1", "-Tag", $Tag,
        "-Prompt", $prompt, "-Context", "256",
        "-BudgetGB", "2", "-ReserveMB", "1024",
        "-DynamicArenaGiB", "30", "-ArenaWrapTrustWorkerChecksum",
        "-ArenaWrapSourceParts", "-DisableQ8F16Cache", "-EmbedRowStaging",
        "-ReapPrefetchThreads", "8", "-ModelPath", $model,
        "-TimeoutSec", "1200", "-PrefillMassWrap",
        "-ComposePrefillMassTiering", "-ExpertCacheN", "320",
        "-ExpertCacheReserveGB", "0", "-ExpertCachePolicy", "lru",
        "-GpuResidentRoutes", "-RouteNoDefaultSync",
        "-ExpertTiering", "enforce", "-ExpertTierPolicy", "mass-lfru",
        "-ExpertTierClockCalls", "430", "-ExpertTierReplacementBudget", "16",
        "-ExpertTierMinFrequency", "3", "-ExpertTierHysteresis", "1.25",
        "-RequestPhaseTrace"
    )
    if ($Profile) {
        $args += @("-ArenaWrapPartProfile", "-ArenaWrapSlowPartMs", "25")
    }
    if ($ExpectedSHA256) {
        $args += @("-ExpectedContentSHA256", $ExpectedSHA256)
    }

    if ($Resume -and (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        Write-Host ("[g49] resume tag=" + $Tag)
    } else {
        Write-Host ("[g49] start tag=" + $Tag + " profile=" + $Profile)
        & powershell.exe @args | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) { throw "G49 run failed: $Tag" }
    }

    $r = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    $tier = $r.expert_tiering
    if ($r.tag -ne $Tag -or $r.prompt -ne $prompt -or
        $r.model -ne $model -or $r.repeats -ne 1 -or $r.warmup -or
        $r.requested_max_tokens -ne 8 -or $r.context_requested -ne 256 -or
        $r.executable_sha256 -ne $provenance.executable_sha256 -or
        $r.harness_sha256 -ne $provenance.harness_sha256 -or
        $r.ds4_cuda_sha256 -ne $provenance.ds4_cuda_sha256 -or
        $r.ds4_c_sha256 -ne $provenance.ds4_c_sha256 -or
        $r.ds4_server_c_sha256 -ne $provenance.ds4_server_c_sha256 -or
        $r.build_manifest_sha256 -ne $provenance.build_manifest_sha256 -or
        -not $r.outputs_identical -or -not $r.request_phase_trace_observed -or
        -not $r.prefill_mass_wrap_observed -or
        $r.prefill_mass_wrap_result -ne "published" -or
        $r.arena_wrap_schedule_observed -ne "source-parts" -or
        $r.arena_wrap_checksum_observed -ne "fnv1a64-worker-only" -or
        [bool]$r.arena_wrap_part_profile_requested -ne $Profile -or
        [bool]$r.arena_wrap_part_profile_observed -ne $Profile -or
        $r.expert_cache_capacity -ne 320 -or
        $tier.states_vram -le 0 -or $tier.states_vram -gt 320 -or
        $tier.snapshot_backing_misses -ne 0 -or
        $tier.ssd_bytes -ne 0 -or $tier.failures -ne 0 -or
        $r.gpu_resident_routes_errors -ne 0 -or
        $r.gpu_resident_routes_default_sync_calls -ne 0 -or
        $r.gpu_resident_routes_no_default_sync_calls -ne
            $r.gpu_resident_routes_calls) {
        throw "G49 contract mismatch: tag=$Tag"
    }
    if ($Profile -and
        ($r.arena_wrap_part_profile_result -ne "copy-complete" -or
         $r.arena_wrap_part_profile_phases -ne 3 -or
         $r.arena_wrap_part_profile_parts -ne $r.arena_wrap_part_count -or
         $r.arena_wrap_part_profile_workers -ne $r.arena_wrap_copy_workers)) {
        throw "G49 part-profile accounting mismatch: tag=$Tag"
    }
    if ($ExpectedSHA256 -and
        ($r.expected_content_sha256 -ne $ExpectedSHA256 -or
         $r.results[0].content_sha256 -ne $ExpectedSHA256)) {
        throw "G49 exact-output mismatch: tag=$Tag"
    }

    [pscustomobject]@{
        tag = $Tag
        arm = if ($Profile) { "profile-on" } else { "profile-off" }
        content_sha256 = $r.results[0].content_sha256
        content = $r.results[0].content
        ttft_seconds = [double]$r.server_prefill_ttft_mean_seconds
        wrap_seconds = [double]$r.arena_wrap_profile_total_seconds
        wrap_copy_seconds = [double]$r.arena_wrap_source_parts_copy_seconds
        decode_tokens_per_second = [double]$r.server_decode_mean_tokens_per_second
        profile_observed = [bool]$r.arena_wrap_part_profile_observed
        profile_phases = [int]$r.arena_wrap_part_profile_phases
        profile_workers = [int]$r.arena_wrap_part_profile_workers
        profile_parts = [long]$r.arena_wrap_part_profile_parts
        profile_bytes = [long]$r.arena_wrap_part_profile_bytes
        profile_slow_threshold_ms = [double]$r.arena_wrap_part_profile_slow_threshold_ms
        profile_memcpy_sum_seconds = [double]$r.arena_wrap_part_profile_memcpy_sum_seconds
        profile_main_worker_seconds = [double]$r.arena_wrap_part_profile_main_worker_seconds
        profile_join_seconds = [double]$r.arena_wrap_part_profile_join_seconds
        profile_phase_worker_active_min_seconds = [double]$r.arena_wrap_part_profile_phase_worker_active_min_seconds
        profile_phase_worker_active_max_seconds = [double]$r.arena_wrap_part_profile_phase_worker_active_max_seconds
        profile_phase_worker_parts_min = [long]$r.arena_wrap_part_profile_phase_worker_parts_min
        profile_phase_worker_parts_max = [long]$r.arena_wrap_part_profile_phase_worker_parts_max
        profile_slow_parts = [long]$r.arena_wrap_part_profile_slow_parts
        profile_max_part_ms = [double]$r.arena_wrap_part_profile_max_part_ms
        profile_max_part_bytes = [long]$r.arena_wrap_part_profile_max_part_bytes
        profile_max_part_kind = [string]$r.arena_wrap_part_profile_max_part_kind
        profile_max_part_load = [long]$r.arena_wrap_part_profile_max_part_load
        profile_max_part_cursor = [long]$r.arena_wrap_part_profile_max_part_cursor
        profile_max_part_source = [long]$r.arena_wrap_part_profile_max_part_source
        runtime_available_min_bytes = [long]$r.runtime_telemetry.windows_available_min_bytes
        runtime_working_set_peak_bytes = [long]$r.runtime_telemetry.process_working_set_peak_bytes
        runtime_page_fault_delta = [long]$r.runtime_telemetry.page_fault_delta
        tier_states_vram = [long]$tier.states_vram
        result_path = $resultPath
    }
}

New-Item -ItemType Directory -Force -Path $outdir | Out-Null
$runs = @()
$expected = ""
foreach ($suffix in @("a", "b", "c")) {
    $off = Invoke-G49Run -Tag ("g49_profile_off_" + $suffix) `
        -Profile:$false -ExpectedSHA256 $expected
    if (-not $expected) { $expected = $off.content_sha256 }
    $on = Invoke-G49Run -Tag ("g49_profile_on_" + $suffix) `
        -Profile:$true -ExpectedSHA256 $expected
    $runs += $off
    $runs += $on
}

$offRuns = @($runs | Where-Object { $_.arm -eq "profile-off" })
$onRuns = @($runs | Where-Object { $_.arm -eq "profile-on" })
$offWrap = @($offRuns | ForEach-Object { [double]$_.wrap_seconds })
$onWrap = @($onRuns | ForEach-Object { [double]$_.wrap_seconds })
$allWrap = @($runs | ForEach-Object { [double]$_.wrap_seconds })
$allMedian = Get-G49Median $allWrap
$summary = [pscustomobject]@{
    schema = "g49_wrap_part_profile_ab_v1"
    question = "Does the opt-in per-worker part profiler preserve exact output at acceptable overhead, and what explains WRAP long tails?"
    performance_verdict_scope = "profile overhead only; n=3 per arm"
    long_tail_verdict_scope = "diagnostic observations only"
    prompt = $prompt
    context = 256
    max_tokens = 8
    expected_content_sha256 = $expected
    order = "off-a,on-a,off-b,on-b,off-c,on-c"
    profile_slow_part_ms = 25.0
    off_wrap_mean_seconds = [math]::Round(($offWrap | Measure-Object -Average).Average, 6)
    on_wrap_mean_seconds = [math]::Round(($onWrap | Measure-Object -Average).Average, 6)
    off_wrap_median_seconds = [math]::Round((Get-G49Median $offWrap), 6)
    on_wrap_median_seconds = [math]::Round((Get-G49Median $onWrap), 6)
    combined_wrap_median_seconds = [math]::Round($allMedian, 6)
    outlier_rule_triggered = [bool](($allWrap | Measure-Object -Maximum).Maximum -gt (2.0 * $allMedian))
    provenance = $provenance
    runner_sha256 = Get-G49SHA256 $MyInvocation.MyCommand.Path
    runs = $runs
}
$summaryPath = Join-Path $outdir "g49_wrap_part_profile_ab_result.json"
$summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
Write-Host ("[g49] complete: " + $summaryPath)
Write-Host ("[g49] wrap off mean/median=" + $summary.off_wrap_mean_seconds + "/" + $summary.off_wrap_median_seconds)
Write-Host ("[g49] wrap on  mean/median=" + $summary.on_wrap_mean_seconds + "/" + $summary.on_wrap_median_seconds)
Write-Host ("[g49] outlier rule triggered=" + $summary.outlier_rule_triggered)
