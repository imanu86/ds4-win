# G50 Windows working-set trim between source-parts WRAP phases.
param(
    [switch]$Resume,
    [switch]$FinalizeInterrupted
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$harness = Join-Path $root "g7_measure.ps1"
$outdir = Join-Path $root "g7_runs"
$model = "C:\ds4-models\ds4-2bit.gguf"
$prompt = "Rispondi in italiano con quattro punti numerati: spiega la differenza tra RAM, VRAM e memoria virtuale. Sii conciso."
$expected = "b78be49a2b62f691ee8a8b5b486b2735275cc85bbbc98ee3102c06116487a5e8"
$executable = Join-Path $root "build\Release\ds4_server.exe"
$buildManifest = Join-Path $root "build\Release\g7_build_manifest.json"

function Get-G50SHA256([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "G50 provenance file missing: $Path"
    }
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$provenance = [pscustomobject]@{
    executable_sha256 = Get-G50SHA256 $executable
    harness_sha256 = Get-G50SHA256 $harness
    ds4_cuda_sha256 = Get-G50SHA256 (Join-Path $root "ds4_cuda.cu")
    ds4_c_sha256 = Get-G50SHA256 (Join-Path $root "ds4.c")
    ds4_server_c_sha256 = Get-G50SHA256 (Join-Path $root "ds4_server.c")
    build_manifest_sha256 = Get-G50SHA256 $buildManifest
}

function Get-G50Median([double[]]$Values) {
    $ordered = @($Values | Sort-Object)
    if (-not $ordered.Count) { return 0.0 }
    $middle = [int][math]::Floor($ordered.Count / 2)
    if (($ordered.Count % 2) -eq 1) { return [double]$ordered[$middle] }
    return ([double]$ordered[$middle - 1] + [double]$ordered[$middle]) / 2.0
}

function Invoke-G50Run {
    param(
        [Parameter(Mandatory=$true)][string]$Tag,
        [Parameter(Mandatory=$true)][bool]$Trim,
        [Parameter(Mandatory=$true)][bool]$Extension
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
        "-RequestPhaseTrace", "-ExpectedContentSHA256", $expected
    )
    if ($Trim) { $args += "-ArenaWrapTrimBetweenPhases" }

    if ($Resume -and (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        Write-Host ("[g50] resume tag=" + $Tag)
    } else {
        Write-Host ("[g50] start tag=" + $Tag + " trim=" + $Trim)
        & powershell.exe @args | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) { throw "G50 run failed: $Tag" }
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
        -not $r.outputs_identical -or
        $r.results[0].content_sha256 -ne $expected -or
        $r.expected_content_sha256 -ne $expected -or
        -not $r.request_phase_trace_observed -or
        -not $r.prefill_mass_wrap_observed -or
        $r.prefill_mass_wrap_result -ne "published" -or
        $r.arena_wrap_schedule_observed -ne "source-parts" -or
        $r.arena_wrap_checksum_observed -ne "fnv1a64-worker-only" -or
        [bool]$r.arena_wrap_trim_between_phases_requested -ne $Trim -or
        [bool]$r.arena_wrap_trim_observed -ne $Trim -or
        [bool]$r.arena_wrap_part_profile_requested -or
        [bool]$r.arena_wrap_part_profile_observed -or
        $r.expert_cache_capacity -ne 320 -or
        $tier.states_vram -le 0 -or $tier.states_vram -gt 320 -or
        $tier.snapshot_backing_misses -ne 0 -or
        $tier.ssd_bytes -ne 0 -or $tier.failures -ne 0 -or
        $r.gpu_resident_routes_errors -ne 0 -or
        $r.gpu_resident_routes_default_sync_calls -ne 0 -or
        $r.gpu_resident_routes_no_default_sync_calls -ne
            $r.gpu_resident_routes_calls) {
        throw "G50 contract mismatch: tag=$Tag"
    }
    if ($Trim -and
        ($r.arena_wrap_trim_result -ne "complete" -or
         $r.arena_wrap_trim_calls -ne 2 -or
         $r.arena_wrap_trim_succeeded -ne 2 -or
         $r.arena_wrap_trim_failed -ne 0 -or
         $r.arena_wrap_trim_last_error -ne 0)) {
        throw "G50 trim accounting mismatch: tag=$Tag"
    }

    [pscustomobject]@{
        tag = $Tag
        arm = if ($Trim) { "trim-on" } else { "trim-off" }
        extension = $Extension
        content_sha256 = $r.results[0].content_sha256
        content = $r.results[0].content
        ttft_seconds = [double]$r.server_prefill_ttft_mean_seconds
        wrap_seconds = [double]$r.arena_wrap_profile_total_seconds
        wrap_copy_seconds = [double]$r.arena_wrap_source_parts_copy_seconds
        decode_tokens_per_second = [double]$r.server_decode_mean_tokens_per_second
        trim_observed = [bool]$r.arena_wrap_trim_observed
        trim_result = [string]$r.arena_wrap_trim_result
        trim_calls = [int]$r.arena_wrap_trim_calls
        trim_seconds = [double]$r.arena_wrap_trim_seconds
        runtime_available_min_bytes = [long]$r.runtime_telemetry.windows_available_min_bytes
        runtime_working_set_peak_bytes = [long]$r.runtime_telemetry.process_working_set_peak_bytes
        runtime_page_fault_delta = [long]$r.runtime_telemetry.page_fault_delta
        tier_states_vram = [long]$tier.states_vram
        tier_states_pinned_ram = [long]$tier.states_pinned_ram
        gpu_route_calls = [long]$r.gpu_resident_routes_calls
        gpu_route_vram_routes = [long]$r.gpu_resident_routes_vram_routes
        gpu_route_pinned_ram_routes = [long]$r.gpu_resident_routes_pinned_ram_routes
        gpu_route_h2d_bytes = [long]$r.gpu_resident_routes_h2d_bytes
        result_path = $resultPath
    }
}

New-Item -ItemType Directory -Force -Path $outdir | Out-Null
$baseRuns = @()
foreach ($suffix in @("a", "b", "c")) {
    $baseRuns += Invoke-G50Run -Tag ("g50_trim_off_" + $suffix) -Trim:$false -Extension:$false
    $baseRuns += Invoke-G50Run -Tag ("g50_trim_on_" + $suffix) -Trim:$true -Extension:$false
}

$baseWrap = @($baseRuns | ForEach-Object { [double]$_.wrap_seconds })
$combinedMedian = Get-G50Median $baseWrap
$outlierArms = @($baseRuns | Where-Object {
    [double]$_.wrap_seconds -gt 2.0 * $combinedMedian
} | Select-Object -ExpandProperty arm -Unique)
$extensionRuns = @()
$interruptedRuns = @()
foreach ($arm in $outlierArms) {
    $trim = $arm -eq "trim-on"
    foreach ($suffix in @("x1", "x2", "x3")) {
        $tagArm = if ($trim) { "on" } else { "off" }
        $extensionTag = "g50_trim_" + $tagArm + "_" + $suffix
        $extensionResult = Join-Path $outdir ("g7_" + $extensionTag + "_result.json")
        if ($FinalizeInterrupted -and
            -not (Test-Path -LiteralPath $extensionResult -PathType Leaf)) {
            $interruptedRuns += [pscustomobject]@{
                tag = $extensionTag
                arm = $arm
                extension = $true
                status = "interrupted"
                reason = "operator-stopped-after-sustained-100-percent-disk-and-unusable-Windows"
                partial_stderr_path = Join-Path $outdir ("g7_" + $extensionTag + "_stderr.log")
                partial_runtime_telemetry_path = Join-Path $outdir ("g7_" + $extensionTag + "_runtime_telemetry.jsonl")
            }
        } else {
            $extensionRuns += Invoke-G50Run `
                -Tag $extensionTag -Trim:$trim -Extension:$true
        }
    }
}

$allRuns = @($baseRuns) + @($extensionRuns)
$baseOffRuns = @($baseRuns | Where-Object { $_.arm -eq "trim-off" })
$baseOnRuns = @($baseRuns | Where-Object { $_.arm -eq "trim-on" })
$expandedOffRuns = @($allRuns | Where-Object { $_.arm -eq "trim-off" })
$expandedOnRuns = @($allRuns | Where-Object { $_.arm -eq "trim-on" })
$baseOffWrap = @($baseOffRuns | ForEach-Object { [double]$_.wrap_seconds })
$baseOnWrap = @($baseOnRuns | ForEach-Object { [double]$_.wrap_seconds })
$expandedOffWrap = @($expandedOffRuns | ForEach-Object { [double]$_.wrap_seconds })
$expandedOnWrap = @($expandedOnRuns | ForEach-Object { [double]$_.wrap_seconds })
$baseOffTtft = @($baseOffRuns | ForEach-Object { [double]$_.ttft_seconds })
$baseOnTtft = @($baseOnRuns | ForEach-Object { [double]$_.ttft_seconds })
$summary = [pscustomobject]@{
    schema = "g50_wrap_trim_ab_v1"
    question = "Does trimming the Windows pageable working set between gate/up/down WRAP phases reduce source-copy stalls without changing output or decode behavior?"
    verdict_scope = "n=3 interleaved per arm; exact output; outlier arm receives three fresh-process extensions"
    prompt = $prompt
    context = 256
    max_tokens = 8
    expected_content_sha256 = $expected
    order = "off-a,on-a,off-b,on-b,off-c,on-c"
    base_off_n = $baseOffRuns.Count
    base_on_n = $baseOnRuns.Count
    base_off_wrap_mean_seconds = [math]::Round(($baseOffWrap | Measure-Object -Average).Average, 6)
    base_on_wrap_mean_seconds = [math]::Round(($baseOnWrap | Measure-Object -Average).Average, 6)
    base_off_wrap_median_seconds = [math]::Round((Get-G50Median $baseOffWrap), 6)
    base_on_wrap_median_seconds = [math]::Round((Get-G50Median $baseOnWrap), 6)
    base_off_ttft_mean_seconds = [math]::Round(($baseOffTtft | Measure-Object -Average).Average, 6)
    base_on_ttft_mean_seconds = [math]::Round(($baseOnTtft | Measure-Object -Average).Average, 6)
    expanded_off_n = $expandedOffRuns.Count
    expanded_on_n = $expandedOnRuns.Count
    expanded_off_wrap_mean_seconds = [math]::Round(($expandedOffWrap | Measure-Object -Average).Average, 6)
    expanded_on_wrap_mean_seconds = [math]::Round(($expandedOnWrap | Measure-Object -Average).Average, 6)
    expanded_off_wrap_median_seconds = [math]::Round((Get-G50Median $expandedOffWrap), 6)
    expanded_on_wrap_median_seconds = [math]::Round((Get-G50Median $expandedOnWrap), 6)
    combined_wrap_median_seconds = [math]::Round($combinedMedian, 6)
    outlier_rule_triggered = [bool]$outlierArms.Count
    outlier_arms = $outlierArms
    extension_count = $extensionRuns.Count
    extension_planned_count = 3 * $outlierArms.Count
    extension_completed_count = $extensionRuns.Count
    extension_interrupted_count = $interruptedRuns.Count
    protocol_status = if ($interruptedRuns.Count) {
        "finalized-incomplete-system-impact"
    } else {
        "complete"
    }
    provenance = $provenance
    runner_sha256 = Get-G50SHA256 $MyInvocation.MyCommand.Path
    base_runs = $baseRuns
    extension_runs = $extensionRuns
    interrupted_runs = $interruptedRuns
}
$summaryPath = Join-Path $outdir "g50_wrap_trim_ab_result.json"
$summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
Write-Host ("[g50] complete: " + $summaryPath)
Write-Host ("[g50] base WRAP off mean/median=" + $summary.base_off_wrap_mean_seconds + "/" + $summary.base_off_wrap_median_seconds)
Write-Host ("[g50] base WRAP on  mean/median=" + $summary.base_on_wrap_mean_seconds + "/" + $summary.base_on_wrap_median_seconds)
Write-Host ("[g50] expanded WRAP off n/mean/median=" + $summary.expanded_off_n + "/" + $summary.expanded_off_wrap_mean_seconds + "/" + $summary.expanded_off_wrap_median_seconds)
Write-Host ("[g50] expanded WRAP on  n/mean/median=" + $summary.expanded_on_n + "/" + $summary.expanded_on_wrap_mean_seconds + "/" + $summary.expanded_on_wrap_median_seconds)
Write-Host ("[g50] outlier arms=" + ($outlierArms -join ",") + " extensions=" + $extensionRuns.Count)
