# G56 sequential-file QD1 WRAP layout functional/profile run (PowerShell 5.1, ASCII).
param(
    [switch]$Resume,
    [switch]$SummarizeExisting,
    [switch]$SkipSystemQuiescencePreflight,
    [string]$ExecutionRunnerSHA256 = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$harness = Join-Path $root "g7_measure.ps1"
$runtimeMonitor = Join-Path $root "g7_runtime_monitor.ps1"
$outdir = Join-Path $root "g7_runs"
$model = "C:\ds4-models\ds4-2bit.gguf"
$prompt = "Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document."
$expected = "31cbc6504dcb57d42aeff9dbceb3aed943bcb32dae19a2edbf552e9fd2f52eb8"
$tag = "g56_wrap_layout_profile_functional"
$executable = Join-Path $root "build\Release\ds4_server.exe"
$buildManifest = Join-Path $root "build\Release\g7_build_manifest.json"

function Get-G56SHA256 {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "G56 provenance file missing: $Path"
    }
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-G56Property {
    param(
        [Parameter(Mandatory=$true)][object]$Object,
        [Parameter(Mandatory=$true)][string]$Name
    )
    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) {
        throw "G56 required field missing: $Name"
    }
}

function Get-G56Property {
    param([object]$Object, [string]$Name)
    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) {
        return $null
    }
    $Object.PSObject.Properties[$Name].Value
}

function Test-G56HarnessParameter {
    param([Parameter(Mandatory=$true)][string]$ParameterName)
    $content = Get-Content -LiteralPath $harness -Raw
    return ($content -match ("\$" + [regex]::Escape($ParameterName) +
        "(\s|=|,|\))"))
}

function New-G56ThresholdProjection {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][uint64]$Reads,
        [Parameter(Mandatory=$true)][uint64]$Bytes,
        [Parameter(Mandatory=$true)][uint64]$Parts,
        [Parameter(Mandatory=$true)][uint64]$Payload
    )
    [pscustomobject]@{
        threshold = $Name
        reads = $Reads
        bytes = $Bytes
        reads_per_part = if ($Parts -gt 0) {
            [math]::Round($Reads / [double]$Parts, 6)
        } else { $null }
        bytes_per_payload = if ($Payload -gt 0) {
            [math]::Round($Bytes / [double]$Payload, 6)
        } else { $null }
    }
}

function Convert-G56LayoutPhase {
    param([Parameter(Mandatory=$true)][object]$Row)
    $parts = [uint64]$Row.parts
    $payload = [uint64]$Row.payload
    [pscustomobject]@{
        phase = [string]$Row.phase
        result = [string]$Row.result
        parts = $parts
        payload = $payload
        gaps = [uint64]$Row.gaps
        overlaps = [uint64]$Row.overlaps
        gap_buckets = [pscustomobject]@{
            eq0 = [uint64]$Row.gap_eq0
            gap_1_4k = [uint64]$Row.gap_1_4k
            gap_4k_64k = [uint64]$Row.gap_4k_64k
            gap_64k_1m = [uint64]$Row.gap_64k_1m
            gap_gt1m = [uint64]$Row.gap_gt1m
        }
        page_size = [uint32]$Row.page_size
        alignment = [pscustomobject]@{
            source_aligned = [uint64]$Row.source_aligned
            bytes_aligned = [uint64]$Row.bytes_aligned
            destination_aligned = [uint64]$Row.destination_aligned
            source_aligned_ratio = if ($parts -gt 0) {
                [math]::Round(([uint64]$Row.source_aligned) / [double]$parts, 6)
            } else { $null }
            bytes_aligned_ratio = if ($parts -gt 0) {
                [math]::Round(([uint64]$Row.bytes_aligned) / [double]$parts, 6)
            } else { $null }
            destination_aligned_ratio = if ($parts -gt 0) {
                [math]::Round(([uint64]$Row.destination_aligned) / [double]$parts, 6)
            } else { $null }
        }
        threshold_projections = @(
            New-G56ThresholdProjection "t0" ([uint64]$Row.t0_reads) ([uint64]$Row.t0_bytes) $parts $payload
            New-G56ThresholdProjection "t4096" ([uint64]$Row.t4096_reads) ([uint64]$Row.t4096_bytes) $parts $payload
            New-G56ThresholdProjection "t65536" ([uint64]$Row.t65536_reads) ([uint64]$Row.t65536_bytes) $parts $payload
            New-G56ThresholdProjection "t1048576" ([uint64]$Row.t1048576_reads) ([uint64]$Row.t1048576_bytes) $parts $payload
        )
    }
}

function New-G56AggregateProjection {
    param([Parameter(Mandatory=$true)][object[]]$Rows)
    $parts = [uint64]0; $payload = [uint64]0; $gaps = [uint64]0
    $overlaps = [uint64]0; $sourceAligned = [uint64]0
    $bytesAligned = [uint64]0; $destinationAligned = [uint64]0
    $gapEq0 = [uint64]0; $gap1_4k = [uint64]0; $gap4k_64k = [uint64]0
    $gap64k_1m = [uint64]0; $gapGt1m = [uint64]0
    $t0Reads = [uint64]0; $t0Bytes = [uint64]0
    $t4096Reads = [uint64]0; $t4096Bytes = [uint64]0
    $t65536Reads = [uint64]0; $t65536Bytes = [uint64]0
    $t1048576Reads = [uint64]0; $t1048576Bytes = [uint64]0
    foreach ($row in $Rows) {
        $parts += [uint64]$row.parts
        $payload += [uint64]$row.payload
        $gaps += [uint64]$row.gaps
        $overlaps += [uint64]$row.overlaps
        $gapEq0 += [uint64]$row.gap_eq0
        $gap1_4k += [uint64]$row.gap_1_4k
        $gap4k_64k += [uint64]$row.gap_4k_64k
        $gap64k_1m += [uint64]$row.gap_64k_1m
        $gapGt1m += [uint64]$row.gap_gt1m
        $sourceAligned += [uint64]$row.source_aligned
        $bytesAligned += [uint64]$row.bytes_aligned
        $destinationAligned += [uint64]$row.destination_aligned
        $t0Reads += [uint64]$row.t0_reads; $t0Bytes += [uint64]$row.t0_bytes
        $t4096Reads += [uint64]$row.t4096_reads; $t4096Bytes += [uint64]$row.t4096_bytes
        $t65536Reads += [uint64]$row.t65536_reads; $t65536Bytes += [uint64]$row.t65536_bytes
        $t1048576Reads += [uint64]$row.t1048576_reads; $t1048576Bytes += [uint64]$row.t1048576_bytes
    }
    [pscustomobject]@{
        phases = @($Rows | ForEach-Object { $_.phase })
        parts = $parts
        payload = $payload
        gaps = $gaps
        overlaps = $overlaps
        gap_buckets = [pscustomobject]@{
            eq0 = $gapEq0
            gap_1_4k = $gap1_4k
            gap_4k_64k = $gap4k_64k
            gap_64k_1m = $gap64k_1m
            gap_gt1m = $gapGt1m
        }
        alignment = [pscustomobject]@{
            source_aligned = $sourceAligned
            bytes_aligned = $bytesAligned
            destination_aligned = $destinationAligned
            source_aligned_ratio = if ($parts -gt 0) {
                [math]::Round($sourceAligned / [double]$parts, 6)
            } else { $null }
            bytes_aligned_ratio = if ($parts -gt 0) {
                [math]::Round($bytesAligned / [double]$parts, 6)
            } else { $null }
            destination_aligned_ratio = if ($parts -gt 0) {
                [math]::Round($destinationAligned / [double]$parts, 6)
            } else { $null }
        }
        threshold_projections = @(
            New-G56ThresholdProjection "t0" $t0Reads $t0Bytes $parts $payload
            New-G56ThresholdProjection "t4096" $t4096Reads $t4096Bytes $parts $payload
            New-G56ThresholdProjection "t65536" $t65536Reads $t65536Bytes $parts $payload
            New-G56ThresholdProjection "t1048576" $t1048576Reads $t1048576Bytes $parts $payload
        )
    }
}

New-Item -ItemType Directory -Force -Path $outdir | Out-Null
if ($SummarizeExisting -and
    $ExecutionRunnerSHA256 -notmatch '^[0-9a-fA-F]{64}$') {
    throw "SummarizeExisting requires -ExecutionRunnerSHA256"
}
foreach ($parameter in @(
    "ArenaWrapLayoutProfile",
    "ArenaWrapSourceParts",
    "ArenaWrapSequentialFile",
    "ArenaWrapFileQD")) {
    if (-not $SummarizeExisting -and
        -not (Test-G56HarnessParameter -ParameterName $parameter)) {
        throw "Harness does not expose -$parameter; refusing to launch model."
    }
}

$provenance = [pscustomobject]@{
    executable_sha256 = Get-G56SHA256 $executable
    harness_sha256 = Get-G56SHA256 $harness
    runtime_monitor_harness_sha256 = Get-G56SHA256 $runtimeMonitor
    ds4_cuda_sha256 = Get-G56SHA256 (Join-Path $root "ds4_cuda.cu")
    ds4_c_sha256 = Get-G56SHA256 (Join-Path $root "ds4.c")
    ds4_server_c_sha256 = Get-G56SHA256 (Join-Path $root "ds4_server.c")
    build_manifest_sha256 = Get-G56SHA256 $buildManifest
}
$executionRunnerHashAtStart = Get-G56SHA256 $MyInvocation.MyCommand.Path
$executionRunnerHashForRuns = if ($SummarizeExisting) {
    $ExecutionRunnerSHA256.ToLowerInvariant()
} else {
    $executionRunnerHashAtStart
}

$resultPath = Join-Path $outdir ("g7_" + $tag + "_result.json")
$launchProvenancePath = Join-Path $outdir `
    ("g7_" + $tag + "_g56_launch_provenance.json")
$args = @(
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $harness,
    "-MaxTokens", "64", "-Repeats", "1", "-Tag", $tag,
    "-Prompt", $prompt, "-Context", "256",
    "-BudgetGB", "2", "-ReserveMB", "1024",
    "-DynamicArenaGiB", "30", "-ArenaWrapTrustWorkerChecksum",
    "-ArenaWrapSourceParts", "-ArenaWrapSequentialFile",
    "-ArenaWrapSequentialWorkers", "1", "-ArenaWrapFileQD", "1",
    "-ArenaWrapLayoutProfile",
    "-DisableQ8F16Cache", "-EmbedRowStaging",
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
if ($SkipSystemQuiescencePreflight) {
    $args += "-SkipSystemQuiescencePreflight"
}

if (($Resume -or $SummarizeExisting) -and
    (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
    Write-Host ("[g56] validate existing tag=" + $tag)
} elseif ($SummarizeExisting) {
    throw "G56 existing result missing: tag=$tag"
} else {
    Write-Host ("[g56] start single functional/profile run tag=" + $tag)
    $launchProvenance = [pscustomobject]@{
        schema = "g56_launch_provenance_v1"
        tag = $tag
        source = "sequential-file"
        copy_workers = 1
        file_qd = 1
        layout_profile = $true
        system_quiescence_skipped = [bool]$SkipSystemQuiescencePreflight
        execution_runner_sha256 = $executionRunnerHashAtStart
        executable_sha256 = $provenance.executable_sha256
        harness_sha256 = $provenance.harness_sha256
        runtime_monitor_harness_sha256 =
            $provenance.runtime_monitor_harness_sha256
        ds4_cuda_sha256 = $provenance.ds4_cuda_sha256
        ds4_c_sha256 = $provenance.ds4_c_sha256
        ds4_server_c_sha256 = $provenance.ds4_server_c_sha256
        build_manifest_sha256 = $provenance.build_manifest_sha256
        prompt = $prompt
        expected_content_sha256 = $expected
        created_utc = [DateTime]::UtcNow.ToString("o")
    }
    $launchProvenance | ConvertTo-Json -Depth 6 |
        Set-Content -LiteralPath $launchProvenancePath -Encoding UTF8
    & powershell.exe @args | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) { throw "G56 run failed: $tag" }
}

if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
    throw "G56 result missing: $resultPath"
}
if (-not (Test-Path -LiteralPath $launchProvenancePath -PathType Leaf)) {
    throw "G56 launch provenance missing: $launchProvenancePath"
}
$launch = Get-Content -LiteralPath $launchProvenancePath -Raw |
    ConvertFrom-Json
if ($launch.schema -ne "g56_launch_provenance_v1" -or
    $launch.tag -ne $tag -or
    $launch.source -ne "sequential-file" -or
    [int]$launch.copy_workers -ne 1 -or
    [int]$launch.file_qd -ne 1 -or
    [bool]$launch.layout_profile -ne $true -or
    [bool]$launch.system_quiescence_skipped -ne
        [bool]$SkipSystemQuiescencePreflight -or
    $launch.execution_runner_sha256 -ne $executionRunnerHashForRuns -or
    $launch.executable_sha256 -ne $provenance.executable_sha256 -or
    $launch.harness_sha256 -ne $provenance.harness_sha256 -or
    $launch.runtime_monitor_harness_sha256 -ne
        $provenance.runtime_monitor_harness_sha256 -or
    $launch.ds4_cuda_sha256 -ne $provenance.ds4_cuda_sha256 -or
    $launch.ds4_c_sha256 -ne $provenance.ds4_c_sha256 -or
    $launch.ds4_server_c_sha256 -ne $provenance.ds4_server_c_sha256 -or
    $launch.build_manifest_sha256 -ne $provenance.build_manifest_sha256 -or
    $launch.prompt -ne $prompt -or
    $launch.expected_content_sha256 -ne $expected) {
    throw "G56 launch provenance mismatch"
}

$r = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
$tier = $r.expert_tiering
$mem = $r.memory_preflight
$proc = $r.process_isolation_preflight
$sys = $r.system_quiescence_preflight
$rt = $r.runtime_telemetry
$systemQuiescenceSkippedObserved =
    [bool](Get-G56Property $sys "skipped")
foreach ($name in @(
    "server_exit_code",
    "arena_wrap_layout_profile_requested",
    "arena_wrap_layout_profile_observed",
    "arena_wrap_layout_profile",
    "arena_wrap_part_count",
    "arena_wrap_file_failures")) {
    Assert-G56Property -Object $r -Name $name
}

if ($r.tag -ne $tag -or $r.prompt -ne $prompt -or
    $r.model -ne $model -or $r.repeats -ne 1 -or $r.warmup -or
    $r.requested_max_tokens -ne 64 -or $r.context_requested -ne 256 -or
    $r.executable_sha256 -ne $provenance.executable_sha256 -or
    $r.harness_sha256 -ne $provenance.harness_sha256 -or
    $r.runtime_monitor_harness_sha256 -ne
        $provenance.runtime_monitor_harness_sha256 -or
    $r.ds4_cuda_sha256 -ne $provenance.ds4_cuda_sha256 -or
    $r.ds4_c_sha256 -ne $provenance.ds4_c_sha256 -or
    $r.ds4_server_c_sha256 -ne $provenance.ds4_server_c_sha256 -or
    $r.build_manifest_sha256 -ne $provenance.build_manifest_sha256 -or
    [int]$r.server_exit_code -ne 0 -or
    -not $r.outputs_identical -or
    $r.expected_content_sha256 -ne $expected -or
    $r.results.Count -ne 1 -or
    $r.results[0].content_sha256 -ne $expected -or
    $r.budget_gb -ne 2 -or $r.reserve_mb -ne 1024 -or
    $r.dynamic_arena_gib_requested -ne 30 -or
    -not $r.arena_wrap_trust_worker_checksum_requested -or
    $r.arena_wrap_schedule_observed -ne "source-parts" -or
    $r.arena_wrap_source_requested -ne "sequential-file" -or
    $r.arena_wrap_source_observed -ne "sequential-file" -or
    -not $r.arena_wrap_sequential_file_requested -or
    $r.arena_wrap_random_file_requested -or
    [int]$r.arena_wrap_sequential_workers_requested -ne 1 -or
    [int]$r.arena_wrap_copy_workers -ne 1 -or
    [int]$r.arena_wrap_file_qd_requested -ne 1 -or
    [int]$r.arena_wrap_file_qd_observed -ne 1 -or
    [uint64]$r.arena_wrap_file_submits -ne 0 -or
    [uint64]$r.arena_wrap_file_completions -ne 0 -or
    [uint64]$r.arena_wrap_file_failures -ne 0 -or
    -not $r.arena_wrap_layout_profile_requested -or
    -not $r.arena_wrap_layout_profile_observed -or
    $r.arena_wrap_layout_profile.Count -ne 3 -or
    $r.arena_wrap_part_profile_requested -or
    $r.arena_wrap_part_profile_observed -or
    $r.q8_f16_cache_disabled -ne $true -or
    -not $r.embed_row_staging_requested -or
    -not $r.prefill_mass_wrap_requested -or
    -not $r.prefill_mass_wrap_observed -or
    $r.prefill_mass_wrap_result -ne "published" -or
    $r.prefill_mass_wrap_reason -ne "ok" -or
    -not $r.compose_prefill_mass_tiering_requested -or
    -not $tier.compose_prefill_mass_tiering_observed -or
    -not $r.gpu_resident_routes_requested -or
    -not $r.gpu_resident_routes_observed -or
    -not $r.route_no_default_sync_requested -or
    $r.gpu_resident_routes_default_sync_calls -ne 0 -or
    $r.gpu_resident_routes_errors -ne 0 -or
    $r.expert_cache_requested -ne 320 -or
    $r.expert_cache_capacity -lt 300 -or
    $r.expert_cache_capacity -gt 320 -or
    $r.expert_cache_policy -ne "lru" -or
    $r.expert_tiering_requested -ne "enforce" -or
    $r.expert_tier_policy_requested -ne "mass-lfru" -or
    $tier.snapshot_backing_misses -ne 0 -or
    $tier.ssd_bytes -ne 0 -or
    $tier.failures -ne 0 -or
    $mem.ready_to_launch -ne $true -or
    $proc.ready_to_launch -ne $true -or
    $systemQuiescenceSkippedObserved -ne
        [bool]$SkipSystemQuiescencePreflight -or
    ($SkipSystemQuiescencePreflight -eq $false -and
        $sys.ready_to_launch -ne $true) -or
    $rt.contamination_abort_observed -ne $false) {
    throw "G56 contract mismatch"
}

$phaseRows = @($r.arena_wrap_layout_profile |
    Sort-Object @{ Expression = {
        switch ($_.phase) {
            "gate" { 0 }
            "up" { 1 }
            "down" { 2 }
            default { 99 }
        }
    }})
$phaseProjections = @($phaseRows | ForEach-Object {
    Convert-G56LayoutPhase $_
})
$aggregateProjection = New-G56AggregateProjection $phaseRows
$timingValid = -not $systemQuiescenceSkippedObserved

$summary = [pscustomobject]@{
    schema = "g56_wrap_layout_profile_v1"
    question = "Single functional/profile run for arena WRAP layout on the exact G45/G54 sequential-file QD1 configuration."
    prompt = $prompt
    context = 256
    max_tokens = 64
    expected_content_sha256 = $expected
    tag = $tag
    functional_profile_run = $true
    benchmark = $false
    independent_processes = 1
    within_process_repeats = 1
    no_n3_claim = $true
    timing_valid = $timingValid
    timing_valid_reason = if ($timingValid) {
        "system quiescence preflight was not skipped"
    } else {
        "system quiescence preflight was explicitly skipped"
    }
    system_quiescence_skipped = $systemQuiescenceSkippedObserved
    execution_runner_sha256 = $executionRunnerHashForRuns
    summary_runner_sha256 = Get-G56SHA256 $MyInvocation.MyCommand.Path
    launch_provenance_path = $launchProvenancePath
    launch_provenance_sha256 = Get-G56SHA256 $launchProvenancePath
    result_path = $resultPath
    result_sha256 = Get-G56SHA256 $resultPath
    provenance = [pscustomobject]@{
        head = $r.head
        executable_sha256 = $r.executable_sha256
        ds4_cuda_sha256 = $r.ds4_cuda_sha256
        ds4_c_sha256 = $r.ds4_c_sha256
        ds4_server_c_sha256 = $r.ds4_server_c_sha256
        build_manifest_sha256 = $r.build_manifest_sha256
        build_input_fingerprint_sha256 =
            $r.build_manifest_input_fingerprint_sha256
        harness_sha256 = $r.harness_sha256
        runtime_monitor_harness_sha256 = $r.runtime_monitor_harness_sha256
        model = $r.model
        model_bytes = $r.model_bytes
        model_last_write_utc = $r.model_last_write_utc
        build_worktree_dirty = $r.build_manifest_worktree_dirty_at_build_start
    }
    validation = [pscustomobject]@{
        server_exit_code = [int]$r.server_exit_code
        content_sha256 = $r.results[0].content_sha256
        outputs_identical = [bool]$r.outputs_identical
        snapshot_backing_misses = [uint64]$tier.snapshot_backing_misses
        ssd_bytes = [uint64]$tier.ssd_bytes
        tier_failures = [uint64]$tier.failures
        arena_wrap_file_failures = [uint64]$r.arena_wrap_file_failures
        memory_preflight_ready = [bool]$mem.ready_to_launch
        process_preflight_ready = [bool]$proc.ready_to_launch
        system_preflight_ready = if ($SkipSystemQuiescencePreflight) {
            $false
        } else {
            [bool]$sys.ready_to_launch
        }
        contamination_abort_observed =
            [bool]$rt.contamination_abort_observed
    }
    config = [pscustomobject]@{
        source = "sequential-file"
        file_qd = 1
        copy_workers = 1
        arena_gib = 30
        cache_experts = 320
        cache_reserve_gib = 0.125
        route_no_default_sync = $true
        trusted_worker_checksum = $true
    }
    raw_layout_profile = $phaseRows
    layout_phase_projections = $phaseProjections
    layout_aggregate_projection = $aggregateProjection
}

$summaryPath = Join-Path $outdir "g56_wrap_layout_profile_result.json"
$summary | ConvertTo-Json -Depth 12 |
    Set-Content -LiteralPath $summaryPath -Encoding UTF8
Write-Host ("[g56] functional/profile summary complete: " + $summaryPath)
