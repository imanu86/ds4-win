# G45 cache256 TTFT outlier recheck (PowerShell 5.1, ASCII).
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$harness = Join-Path $root "g7_measure.ps1"
$outdir = Join-Path $root "g7_runs"
$model = "C:\ds4-models\ds4-2bit.gguf"
$prompt = "Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document."
$expected = "31cbc6504dcb57d42aeff9dbceb3aed943bcb32dae19a2edbf552e9fd2f52eb8"

function Invoke-G45Recheck {
    param([Parameter(Mandatory=$true)][string]$Tag)

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
        "-ExpertCacheN", "256", "-ExpertCacheReserveGB", "0.125",
        "-ExpertCachePolicy", "lru", "-GpuResidentRoutes",
        "-ExpertTiering", "enforce", "-ExpertTierPolicy", "mass-lfru",
        "-ExpertTierClockCalls", "430",
        "-ExpertTierReplacementBudget", "16",
        "-ExpertTierMinFrequency", "3",
        "-ExpertTierHysteresis", "1.25"
    )

    Write-Host ("[g45-recheck] start tag=" + $Tag)
    & powershell.exe @args | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) {
        throw "G45 recheck failed: $Tag"
    }

    $resultPath = Join-Path $outdir ("g7_" + $Tag + "_result.json")
    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        throw "G45 recheck result missing: tag=$Tag"
    }
    $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    $tier = $result.expert_tiering
    if (-not $result.outputs_identical -or
        $result.expected_content_sha256 -ne $expected -or
        $result.results.Count -ne 1 -or
        $result.results[0].content_sha256 -ne $expected -or
        $result.requested_max_tokens -ne 64 -or
        $result.context_requested -ne 256 -or
        $result.reserve_mb -ne 1024 -or
        $result.dynamic_arena_gib_requested -ne 30 -or
        $result.expert_cache_requested -ne 256 -or
        $result.expert_cache_capacity -ne 256 -or
        $result.expert_cache_reserve_gb -ne 0.125 -or
        -not $result.gpu_resident_routes_requested -or
        -not $result.gpu_resident_routes_observed -or
        $result.split_hit_miss_requested -or
        -not $result.prefill_mass_wrap_observed -or
        $result.prefill_mass_wrap_result -ne "published" -or
        $result.prefill_mass_wrap_mask -ne "request-scoped-closed" -or
        -not $tier.compose_prefill_mass_tiering_observed -or
        $tier.states_vram -ne 256 -or
        $tier.snapshot_backing_misses -ne 0 -or
        $tier.ssd_bytes -ne 0 -or
        $tier.failures -ne 0 -or
        $result.gpu_resident_routes_errors -ne 0) {
        throw "G45 recheck contract mismatch: tag=$Tag"
    }

    $ttft = [double]$result.server_prefill_ttft_mean_seconds
    $wrap = [double]$result.prefill_mass_wrap_seconds
    [pscustomobject]@{
        tag = $Tag
        result_path = $resultPath
        head = $result.head
        executable_sha256 = $result.executable_sha256
        ds4_cuda_sha256 = $result.ds4_cuda_sha256
        build_manifest_sha256 = $result.build_manifest_sha256
        build_input_fingerprint_sha256 = $result.build_manifest_input_fingerprint_sha256
        harness_sha256 = $result.harness_sha256
        model = $result.model
        model_bytes = $result.model_bytes
        model_last_write_utc = $result.model_last_write_utc
        ttft_seconds = $ttft
        wrap_seconds = $wrap
        ttft_minus_wrap_seconds = [math]::Round($ttft - $wrap, 6)
        decode_tokens_per_second = [double]$result.server_decode_mean_tokens_per_second
        decode_seconds = [double]$result.server_runs[0].server_decode_seconds
        vram_hits = [uint64]$tier.vram_hits
        ram_hits = [uint64]$tier.ram_hits
        ram_h2d_gib = [uint64]$tier.ram_h2d_bytes / 1GB
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
$runs += Invoke-G45Recheck -Tag "g45_cache256_ttft_recheck_a"
$runs += Invoke-G45Recheck -Tag "g45_cache256_ttft_recheck_b"
$runs += Invoke-G45Recheck -Tag "g45_cache256_ttft_recheck_c"

$provenanceFields = @(
    "head", "executable_sha256", "ds4_cuda_sha256", "build_manifest_sha256",
    "build_input_fingerprint_sha256", "harness_sha256", "model", "model_bytes",
    "model_last_write_utc"
)
foreach ($field in $provenanceFields) {
    $values = @($runs | ForEach-Object { [string]($_.$field) } | Select-Object -Unique)
    if ($values.Count -ne 1) {
        throw "G45 recheck mixed provenance: field=$field"
    }
}

$summary = [pscustomobject]@{
    schema = "g45_ttft_outlier_recheck_v1"
    question = "Does the 377.736 second cache256 TTFT outlier recur in three additional independent processes?"
    original_outlier_tag = "g45_stable_cache256_c"
    original_outlier_ttft_seconds = 377.736
    prompt = $prompt
    context = 256
    max_tokens = 64
    cache_experts = 256
    independent_processes = 3
    expected_content_sha256 = $expected
    runner_sha256 = (Get-FileHash -LiteralPath $MyInvocation.MyCommand.Path -Algorithm SHA256).Hash.ToLowerInvariant()
    provenance = [pscustomobject]@{
        head = $runs[0].head
        executable_sha256 = $runs[0].executable_sha256
        ds4_cuda_sha256 = $runs[0].ds4_cuda_sha256
        build_manifest_sha256 = $runs[0].build_manifest_sha256
        build_input_fingerprint_sha256 = $runs[0].build_input_fingerprint_sha256
        harness_sha256 = $runs[0].harness_sha256
        model = $runs[0].model
        model_bytes = $runs[0].model_bytes
        model_last_write_utc = $runs[0].model_last_write_utc
    }
    runs = $runs
}

$summaryPath = Join-Path $outdir "g45_ttft_outlier_recheck_result.json"
$summary | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 $summaryPath
Write-Host ("[g45-recheck] complete: " + $summaryPath)
