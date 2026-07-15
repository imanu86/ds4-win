# G44 source-ordered WRAP A/B (PowerShell 5.1, ASCII).
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$harness = Join-Path $root "g7_measure.ps1"
$outdir = Join-Path $root "g7_runs"
$model = "C:\ds4-models\ds4-2bit.gguf"
$prompt = "Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document."
$expected = "921a62bdb39d9d07161326274fcbc0070f3c4b9e75153d27b1b6dc96811f6e88"

function Get-G44Mean {
    param(
        [Parameter(Mandatory=$true)][object[]]$Rows,
        [Parameter(Mandatory=$true)][string]$Property
    )
    [math]::Round(($Rows | Measure-Object -Property $Property -Average).Average, 6)
}

function Invoke-G44Run {
    param(
        [Parameter(Mandatory=$true)][string]$Tag,
        [Parameter(Mandatory=$true)][ValidateSet("expert-major", "source-parts")][string]$Arm
    )

    $args = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $harness,
        "-MaxTokens", "12", "-Repeats", "1",
        "-Tag", $Tag, "-Prompt", $prompt, "-Context", "256",
        "-BudgetGB", "2", "-ReserveMB", "1024", "-RuntimeReserveMB", "0",
        "-DynamicArenaGiB", "30", "-ArenaWrapTrustWorkerChecksum",
        "-DisableQ8F16Cache", "-EmbedRowStaging", "-PrefillChunk", "0",
        "-ReapPrefetchThreads", "8", "-IoQD", "1",
        "-ExpectedContentSHA256", $expected,
        "-ModelPath", $model, "-TimeoutSec", "1200",
        "-PrefillMassWrap", "-ComposePrefillMassTiering",
        "-ExpertCacheN", "256", "-ExpertCacheReserveGB", "0.5",
        "-ExpertCachePolicy", "lru", "-GpuResidentRoutes",
        "-ExpertTiering", "enforce", "-ExpertTierPolicy", "mass-lfru",
        "-ExpertTierClockCalls", "430",
        "-ExpertTierReplacementBudget", "16",
        "-ExpertTierMinFrequency", "3",
        "-ExpertTierHysteresis", "1.25"
    )
    if ($Arm -eq "source-parts") {
        $args += "-ArenaWrapSourceParts"
    }

    Write-Host ("[g44] start tag=" + $Tag + " arm=" + $Arm)
    & powershell.exe @args | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) {
        throw "G44 run failed: $Tag"
    }

    $resultPath = Join-Path $outdir ("g7_" + $Tag + "_result.json")
    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        throw "G44 result missing: tag=$Tag"
    }
    $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json

    if (-not $result.outputs_identical -or
        $result.expected_content_sha256 -ne $expected -or
        $result.results.Count -ne 1 -or
        $result.results[0].content_sha256 -ne $expected) {
        throw "G44 exact output mismatch: tag=$Tag"
    }
    if ($result.prompt -ne $prompt -or
        $result.context_requested -ne 256 -or
        $result.requested_max_tokens -ne 12 -or
        $result.repeats -ne 1 -or
        $result.warmup -or
        $result.reserve_mb -ne 1024 -or
        $result.dynamic_arena_gib_requested -ne 30 -or
        -not $result.arena_wrap_trust_worker_checksum_requested -or
        $result.arena_wrap_schedule_requested -ne $Arm -or
        -not $result.arena_wrap_profile_observed -or
        $result.arena_wrap_profile_result -ne "published" -or
        $result.arena_wrap_schedule_observed -ne $Arm -or
        $result.arena_wrap_checksum_observed -ne "fnv1a64-worker-only" -or
        -not $result.prefill_mass_wrap_observed -or
        $result.prefill_mass_wrap_result -ne "published" -or
        $result.prefill_mass_wrap_reason -ne "ok" -or
        $result.prefill_mass_wrap_mask -ne "request-scoped-closed" -or
        -not $result.compose_prefill_mass_tiering_requested -or
        -not $result.expert_tiering.compose_prefill_mass_tiering_observed -or
        $result.expert_tiering.snapshot_backing_misses -ne 0 -or
        $result.expert_tiering.ssd_bytes -ne 0 -or
        $result.expert_tiering.failures -ne 0 -or
        $result.dynamic_arena_final_fatal -ne 0) {
        throw "G44 contract mismatch: tag=$Tag"
    }
    if ($Arm -eq "source-parts") {
        if ($result.arena_wrap_part_count -ne
                (3 * $result.arena_wrap_profile_loads) -or
            $result.arena_wrap_copy_workers -le 0 -or
            $result.arena_wrap_checksum_workers -ne 0 -or
            $result.arena_wrap_source_parts_checksum_seconds -ne 0) {
            throw "G44 source-parts accounting mismatch: tag=$Tag"
        }
    } elseif ($result.arena_wrap_part_count -ne 0) {
        throw "G44 expert-major unexpectedly reported source parts: tag=$Tag"
    }

    $tier = $result.expert_tiering
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
        decode_tokens_per_second = [double]$result.server_decode_mean_tokens_per_second
        client_tokens_per_second = [double]$result.mean_tokens_per_second
        process_read_gib = [uint64]$result.runtime_telemetry.win32_process_read_transfer_delta_bytes / 1GB
        wrap_seconds = [double]$result.prefill_mass_wrap_seconds
        profile_begin_seconds = [double]$result.arena_wrap_profile_begin_seconds
        profile_copy_checksum_seconds = [double]$result.arena_wrap_profile_copy_checksum_seconds
        profile_finish_seconds = [double]$result.arena_wrap_profile_finish_seconds
        profile_publish_seconds = [double]$result.arena_wrap_profile_publish_seconds
        profile_total_seconds = [double]$result.arena_wrap_profile_total_seconds
        source_parts_copy_seconds = [double]$result.arena_wrap_source_parts_copy_seconds
        source_parts_checksum_seconds = [double]$result.arena_wrap_source_parts_checksum_seconds
        part_count = [uint64]$result.arena_wrap_part_count
        copy_workers = [uint32]$result.arena_wrap_copy_workers
        checksum_workers = [uint32]$result.arena_wrap_checksum_workers
        snapshot_misses = [uint64]$tier.snapshot_backing_misses
        ssd_bytes = [uint64]$tier.ssd_bytes
        vram_hits = [uint64]$tier.vram_hits
        ram_hits = [uint64]$tier.ram_hits
        dedicated_peak_gib = [uint64]$result.runtime_telemetry.gpu_process_dedicated_peak_bytes / 1GB
        available_min_gib = [uint64]$result.runtime_telemetry.windows_available_min_bytes / 1GB
        standby_before_gib = [uint64]$result.memory_preflight.before.standby_cache_bytes / 1GB
    }
}

New-Item -ItemType Directory -Force -Path $outdir | Out-Null

# Independent processes. The mirrored order balances later warm-cache runs;
# per-run values remain in the result so the first cold-cache outlier is visible.
$runs = @()
$runs += Invoke-G44Run -Tag "g44_expert_a" -Arm "expert-major"
$runs += Invoke-G44Run -Tag "g44_source_a" -Arm "source-parts"
$runs += Invoke-G44Run -Tag "g44_source_b" -Arm "source-parts"
$runs += Invoke-G44Run -Tag "g44_expert_b" -Arm "expert-major"
$runs += Invoke-G44Run -Tag "g44_expert_c" -Arm "expert-major"
$runs += Invoke-G44Run -Tag "g44_source_c" -Arm "source-parts"

$provenanceFields = @(
    "head", "executable_sha256", "ds4_cuda_sha256", "ds4_c_sha256",
    "build_manifest_sha256", "build_input_fingerprint_sha256", "harness_sha256",
    "model", "model_bytes", "model_last_write_utc", "build_worktree_dirty"
)
foreach ($field in $provenanceFields) {
    $values = @($runs | ForEach-Object { [string]($_.$field) } | Select-Object -Unique)
    if ($values.Count -ne 1) {
        throw "G44 mixed provenance across runs: field=$field"
    }
}

$armSummary = @()
foreach ($arm in @("expert-major", "source-parts")) {
    $rows = @($runs | Where-Object { $_.arm -eq $arm })
    if ($rows.Count -ne 3) {
        throw "G44 arm replication mismatch: $arm"
    }
    $armSummary += [pscustomobject]@{
        arm = $arm
        independent_processes = $rows.Count
        ttft_mean_seconds = Get-G44Mean $rows "ttft_seconds"
        decode_tokens_per_second_mean = Get-G44Mean $rows "decode_tokens_per_second"
        client_tokens_per_second_mean = Get-G44Mean $rows "client_tokens_per_second"
        process_read_gib_mean = Get-G44Mean $rows "process_read_gib"
        wrap_seconds_mean = Get-G44Mean $rows "wrap_seconds"
        profile_begin_seconds_mean = Get-G44Mean $rows "profile_begin_seconds"
        profile_copy_checksum_seconds_mean = Get-G44Mean $rows "profile_copy_checksum_seconds"
        profile_finish_seconds_mean = Get-G44Mean $rows "profile_finish_seconds"
        profile_publish_seconds_mean = Get-G44Mean $rows "profile_publish_seconds"
        profile_total_seconds_mean = Get-G44Mean $rows "profile_total_seconds"
        snapshot_misses_sum = ($rows | Measure-Object -Property snapshot_misses -Sum).Sum
        ssd_bytes_sum = ($rows | Measure-Object -Property ssd_bytes -Sum).Sum
        vram_hits_mean = Get-G44Mean $rows "vram_hits"
        ram_hits_mean = Get-G44Mean $rows "ram_hits"
        dedicated_peak_gib_mean = Get-G44Mean $rows "dedicated_peak_gib"
        available_min_gib_mean = Get-G44Mean $rows "available_min_gib"
        standby_before_gib_mean = Get-G44Mean $rows "standby_before_gib"
    }
}

$summary = [pscustomobject]@{
    schema = "g44_source_parts_ab_v1"
    question = "Does source-offset ordering reduce the request-scoped 30 GiB WRAP cost while preserving the exact full-slot FNV, output, and closed-snapshot tiering?"
    prompt = $prompt
    context = 256
    max_tokens = 12
    arena_gib = 30
    cache_experts = 256
    expected_content_sha256 = $expected
    independent_processes_per_arm = 3
    within_process_repeats = 1
    warmup = $false
    cache_caveat = "Windows standby/file-cache state cannot be reset by the harness; inspect each run as well as arm means."
    order = @($runs | ForEach-Object { $_.tag })
    runner_sha256 = (Get-FileHash -LiteralPath $MyInvocation.MyCommand.Path -Algorithm SHA256).Hash.ToLowerInvariant()
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

$summaryPath = Join-Path $outdir "g44_source_parts_ab_result.json"
$summary | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 $summaryPath
Write-Host ("[g44] matrix complete: " + $summaryPath)
