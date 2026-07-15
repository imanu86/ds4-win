# G43 WRAP checksum A/B (PowerShell 5.1, ASCII).
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$harness = Join-Path $root "g7_measure.ps1"
$outdir = Join-Path $root "g7_runs"
$model = "C:\ds4-models\ds4-2bit.gguf"
$prompt = "Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document."
$expected = "921a62bdb39d9d07161326274fcbc0070f3c4b9e75153d27b1b6dc96811f6e88"

function Get-G43Mean {
    param(
        [Parameter(Mandatory=$true)][object[]]$Rows,
        [Parameter(Mandatory=$true)][string]$Property
    )
    [math]::Round(($Rows | Measure-Object -Property $Property -Average).Average, 6)
}

function Invoke-G43Run {
    param(
        [Parameter(Mandatory=$true)][string]$Tag,
        [Parameter(Mandatory=$true)][ValidateSet("finish-verify", "worker-checksum")][string]$Arm
    )

    $trustWorker = ($Arm -eq "worker-checksum")
    $args = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $harness,
        "-MaxTokens", "12", "-Repeats", "1",
        "-Tag", $Tag, "-Prompt", $prompt, "-Context", "256",
        "-BudgetGB", "2", "-ReserveMB", "1024", "-RuntimeReserveMB", "0",
        "-DynamicArenaGiB", "30",
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
    if ($trustWorker) {
        $args += "-ArenaWrapTrustWorkerChecksum"
    }

    Write-Host ("[g43] start tag=" + $Tag + " arm=" + $Arm)
    & powershell.exe @args | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) {
        throw "G43 run failed: $Tag"
    }

    $resultPath = Join-Path $outdir ("g7_" + $Tag + "_result.json")
    $stderrPath = Join-Path $outdir ("g7_" + $Tag + "_stderr.log")
    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $stderrPath -PathType Leaf)) {
        throw "G43 result or stderr missing: tag=$Tag"
    }
    $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    $stderr = Get-Content -LiteralPath $stderrPath -Raw

    if (-not $result.outputs_identical -or
        $result.expected_content_sha256 -ne $expected -or
        $result.results.Count -ne 1 -or
        $result.results[0].content_sha256 -ne $expected) {
        throw "G43 exact output mismatch: tag=$Tag"
    }
    if ($result.prompt -ne $prompt -or
        $result.context_requested -ne 256 -or
        $result.requested_max_tokens -ne 12 -or
        $result.repeats -ne 1 -or
        $result.warmup -or
        $result.reserve_mb -ne 1024 -or
        $result.dynamic_arena_gib_requested -ne 30 -or
        -not $result.prefill_mass_wrap_observed -or
        $result.prefill_mass_wrap_result -ne "published" -or
        $result.prefill_mass_wrap_reason -ne "ok" -or
        $result.prefill_mass_wrap_mask -ne "request-scoped-closed" -or
        -not $result.compose_prefill_mass_tiering_requested -or
        -not $result.expert_tiering.compose_prefill_mass_tiering_observed -or
        $result.expert_tiering.snapshot_backing_misses -ne 0 -or
        $result.expert_tiering.ssd_bytes -ne 0 -or
        $result.expert_tiering.failures -ne 0 -or
        $result.dynamic_arena_final_fatal -ne 0 -or
        [bool]$result.arena_wrap_trust_worker_checksum_requested -ne $trustWorker) {
        throw "G43 contract mismatch: tag=$Tag"
    }

    $profilePattern = '\[arena-wrap-profile\] result=(\S+) schedule=(\S+) source=(\S+) checksum=(\S+) loads=(\d+) workers=(\d+) begin=([0-9.]+) copy_checksum=([0-9.]+) finish=([0-9.]+) publish=([0-9.]+) total=([0-9.]+)'
    $profileMatches = [regex]::Matches($stderr, $profilePattern)
    if ($profileMatches.Count -ne 1) {
        throw "G43 profile line count mismatch: tag=$Tag count=$($profileMatches.Count)"
    }
    $profile = $profileMatches[0]
    $expectedChecksumMode = if ($trustWorker) {
        "fnv1a64-worker-only"
    } else {
        "fnv1a64-worker-plus-finish"
    }
    if ($profile.Groups[1].Value -ne "published" -or
        $profile.Groups[2].Value -ne "expert-major" -or
        $profile.Groups[3].Value -ne "mmap" -or
        $profile.Groups[4].Value -ne $expectedChecksumMode) {
        throw "G43 profile contract mismatch: tag=$Tag"
    }

    $tier = $result.expert_tiering
    $processRead = [uint64]$result.runtime_telemetry.win32_process_read_transfer_delta_bytes
    [pscustomobject]@{
        tag = $Tag
        arm = $Arm
        result_path = $resultPath
        stderr_path = $stderrPath
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
        process_read_gib = $processRead / 1GB
        wrap_seconds = [double]$result.prefill_mass_wrap_seconds
        profile_begin_seconds = [double]$profile.Groups[7].Value
        profile_copy_checksum_seconds = [double]$profile.Groups[8].Value
        profile_finish_seconds = [double]$profile.Groups[9].Value
        profile_publish_seconds = [double]$profile.Groups[10].Value
        profile_total_seconds = [double]$profile.Groups[11].Value
        profile_checksum_mode = $profile.Groups[4].Value
        snapshot_misses = [uint64]$tier.snapshot_backing_misses
        ssd_bytes = [uint64]$tier.ssd_bytes
        vram_hits = [uint64]$tier.vram_hits
        ram_hits = [uint64]$tier.ram_hits
        dedicated_peak_gib = [uint64]$result.runtime_telemetry.gpu_process_dedicated_peak_bytes / 1GB
        available_min_gib = [uint64]$result.runtime_telemetry.windows_available_min_bytes / 1GB
    }
}

New-Item -ItemType Directory -Force -Path $outdir | Out-Null

# Independent one-request processes; order balances cache and thermal drift.
$runs = @()
$runs += Invoke-G43Run -Tag "g43_verify_a" -Arm "finish-verify"
$runs += Invoke-G43Run -Tag "g43_worker_a" -Arm "worker-checksum"
$runs += Invoke-G43Run -Tag "g43_worker_b" -Arm "worker-checksum"
$runs += Invoke-G43Run -Tag "g43_verify_b" -Arm "finish-verify"
$runs += Invoke-G43Run -Tag "g43_verify_c" -Arm "finish-verify"
$runs += Invoke-G43Run -Tag "g43_worker_c" -Arm "worker-checksum"

$provenanceFields = @(
    "head", "executable_sha256", "ds4_cuda_sha256", "ds4_c_sha256",
    "build_manifest_sha256", "build_input_fingerprint_sha256", "harness_sha256",
    "model", "model_bytes", "model_last_write_utc", "build_worktree_dirty"
)
foreach ($field in $provenanceFields) {
    $values = @($runs | ForEach-Object { [string]($_.$field) } | Select-Object -Unique)
    if ($values.Count -ne 1) {
        throw "G43 mixed provenance across runs: field=$field"
    }
}

$armSummary = @()
foreach ($arm in @("finish-verify", "worker-checksum")) {
    $rows = @($runs | Where-Object { $_.arm -eq $arm })
    if ($rows.Count -ne 3) {
        throw "G43 arm replication mismatch: $arm"
    }
    $armSummary += [pscustomobject]@{
        arm = $arm
        independent_processes = $rows.Count
        ttft_mean_seconds = Get-G43Mean $rows "ttft_seconds"
        decode_tokens_per_second_mean = Get-G43Mean $rows "decode_tokens_per_second"
        client_tokens_per_second_mean = Get-G43Mean $rows "client_tokens_per_second"
        process_read_gib_mean = Get-G43Mean $rows "process_read_gib"
        wrap_seconds_mean = Get-G43Mean $rows "wrap_seconds"
        profile_begin_seconds_mean = Get-G43Mean $rows "profile_begin_seconds"
        profile_copy_checksum_seconds_mean = Get-G43Mean $rows "profile_copy_checksum_seconds"
        profile_finish_seconds_mean = Get-G43Mean $rows "profile_finish_seconds"
        profile_publish_seconds_mean = Get-G43Mean $rows "profile_publish_seconds"
        profile_total_seconds_mean = Get-G43Mean $rows "profile_total_seconds"
        snapshot_misses_sum = ($rows | Measure-Object -Property snapshot_misses -Sum).Sum
        ssd_bytes_sum = ($rows | Measure-Object -Property ssd_bytes -Sum).Sum
        vram_hits_mean = Get-G43Mean $rows "vram_hits"
        ram_hits_mean = Get-G43Mean $rows "ram_hits"
        dedicated_peak_gib_mean = Get-G43Mean $rows "dedicated_peak_gib"
        available_min_gib_mean = Get-G43Mean $rows "available_min_gib"
    }
}

$summary = [pscustomobject]@{
    schema = "g43_wrap_checksum_ab_v1"
    question = "Can WRAP trust the checksum computed by joined copy workers and remove the redundant serial full-arena checksum without changing exact output or closed-snapshot tiering?"
    prompt = $prompt
    context = 256
    max_tokens = 12
    arena_gib = 30
    cache_experts = 256
    expected_content_sha256 = $expected
    independent_processes_per_arm = 3
    within_process_repeats = 1
    warmup = $false
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

$summaryPath = Join-Path $outdir "g43_wrap_checksum_ab_result.json"
$summary | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 $summaryPath
Write-Host ("[g43] matrix complete: " + $summaryPath)
