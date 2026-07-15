# G48 no-default-sync cross-prompt exactness gate (PowerShell 5.1, ASCII).
param([switch]$Resume, [switch]$OutlierRecheck)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$harness = Join-Path $root "g7_measure.ps1"
$outdir = Join-Path $root "g7_runs"
$model = "C:\ds4-models\ds4-2bit.gguf"
$executable = Join-Path $root "build\Release\ds4_server.exe"
$buildManifest = Join-Path $root "build\Release\g7_build_manifest.json"

$cases = @(
    [pscustomobject]@{
        name = "italian_explanation"
        context = 256
        prompt = "Rispondi in italiano con quattro punti numerati: spiega la differenza tra RAM, VRAM e memoria virtuale. Sii conciso."
    },
    [pscustomobject]@{
        name = "c_function_ctx256"
        context = 256
        prompt = "Return only a complete C function bool parse_u64_decimal(const char *s, uint64_t *out) with overflow detection and no heap allocation."
    },
    [pscustomobject]@{
        name = "postgres_query"
        context = 256
        prompt = "Return only one PostgreSQL query that lists each customer with order_count and total_spend for the last 30 days, including customers with zero orders."
    }
)

function Get-G48SHA256 {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "G48 provenance file missing: $Path"
    }
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$currentProvenance = [pscustomobject]@{
    executable_sha256 = Get-G48SHA256 $executable
    harness_sha256 = Get-G48SHA256 $harness
    ds4_cuda_sha256 = Get-G48SHA256 (Join-Path $root "ds4_cuda.cu")
    ds4_c_sha256 = Get-G48SHA256 (Join-Path $root "ds4.c")
    ds4_server_c_sha256 = Get-G48SHA256 (Join-Path $root "ds4_server.c")
    build_manifest_sha256 = Get-G48SHA256 $buildManifest
}

function Invoke-G48Run {
    param(
        [Parameter(Mandatory=$true)][string]$Tag,
        [Parameter(Mandatory=$true)][string]$Prompt,
        [Parameter(Mandatory=$true)][ValidateSet(256, 512)][int]$Context,
        [Parameter(Mandatory=$true)][ValidateSet("default-sync", "no-default-sync")][string]$Arm,
        [string]$ExpectedSHA256 = ""
    )

    $resultPath = Join-Path $outdir ("g7_" + $Tag + "_result.json")
    $noSyncExpected = $Arm -eq "no-default-sync"
    $args = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $harness,
        "-MaxTokens", "64", "-Repeats", "1",
        "-Tag", $Tag, "-Prompt", $Prompt, "-Context", ([string]$Context),
        "-BudgetGB", "2", "-ReserveMB", "1024",
        "-DynamicArenaGiB", "30", "-ArenaWrapTrustWorkerChecksum",
        "-ArenaWrapSourceParts", "-DisableQ8F16Cache", "-EmbedRowStaging",
        "-ReapPrefetchThreads", "8", "-ModelPath", $model,
        "-TimeoutSec", "1200", "-PrefillMassWrap",
        "-ComposePrefillMassTiering", "-ExpertCacheN", "320",
        "-ExpertCacheReserveGB", "0", "-ExpertCachePolicy", "lru",
        "-GpuResidentRoutes", "-ExpertTiering", "enforce",
        "-ExpertTierPolicy", "mass-lfru", "-ExpertTierClockCalls", "430",
        "-ExpertTierReplacementBudget", "16",
        "-ExpertTierMinFrequency", "3",
        "-ExpertTierHysteresis", "1.25"
    )
    if ($noSyncExpected) { $args += "-RouteNoDefaultSync" }
    if ($ExpectedSHA256) {
        $args += @("-ExpectedContentSHA256", $ExpectedSHA256)
    }

    if ($Resume -and (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        Write-Host ("[g48] resume tag=" + $Tag + " arm=" + $Arm)
    } else {
        Write-Host ("[g48] start tag=" + $Tag + " arm=" + $Arm)
        & powershell.exe @args | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) { throw "G48 run failed: $Tag" }
    }

    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        throw "G48 result missing: tag=$Tag"
    }
    $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    $tier = $result.expert_tiering
    if ($result.tag -ne $Tag -or
        $result.prompt -ne $Prompt -or
        $result.model -ne $model -or
        $result.executable_sha256 -ne $currentProvenance.executable_sha256 -or
        $result.harness_sha256 -ne $currentProvenance.harness_sha256 -or
        $result.ds4_cuda_sha256 -ne $currentProvenance.ds4_cuda_sha256 -or
        $result.ds4_c_sha256 -ne $currentProvenance.ds4_c_sha256 -or
        $result.ds4_server_c_sha256 -ne $currentProvenance.ds4_server_c_sha256 -or
        $result.build_manifest_sha256 -ne $currentProvenance.build_manifest_sha256 -or
        -not $result.outputs_identical -or
        $result.results.Count -ne 1 -or
        $result.repeats -ne 1 -or
        $result.warmup -or
        $result.requested_max_tokens -ne 64 -or
        $result.context_requested -ne $Context -or
        $result.reserve_mb -ne 1024 -or
        $result.dynamic_arena_gib_requested -ne 30 -or
        $result.expert_cache_requested -ne 320 -or
        $result.expert_cache_capacity -ne 320 -or
        $result.expert_cache_reserve_gb -ne 0 -or
        -not $result.gpu_resident_routes_requested -or
        -not $result.gpu_resident_routes_observed -or
        [bool]$result.route_no_default_sync_requested -ne $noSyncExpected -or
        $result.split_hit_miss_requested -or
        $result.request_phase_trace_requested -or
        $result.request_phase_trace_observed -or
        $result.request_phase_trace_line_count -ne 0 -or
        -not $result.prefill_mass_wrap_observed -or
        $result.prefill_mass_wrap_result -ne "published" -or
        $result.prefill_mass_wrap_mask -ne "request-scoped-closed" -or
        -not $tier.compose_prefill_mass_tiering_observed -or
        $tier.states_vram -ne 320 -or
        $tier.snapshot_backing_misses -ne 0 -or
        $tier.ssd_bytes -ne 0 -or
        $tier.failures -ne 0 -or
        $result.gpu_resident_routes_errors -ne 0 -or
        ($result.gpu_resident_routes_default_sync_calls +
         $result.gpu_resident_routes_no_default_sync_calls) -ne
            $result.gpu_resident_routes_calls) {
        throw "G48 contract mismatch: tag=$Tag"
    }
    if ($noSyncExpected) {
        if ($result.gpu_resident_routes_default_sync_calls -ne 0 -or
            $result.gpu_resident_routes_no_default_sync_calls -ne
                $result.gpu_resident_routes_calls) {
            throw "G48 no-sync accounting mismatch: tag=$Tag"
        }
    } elseif ($result.gpu_resident_routes_default_sync_calls -ne
                  $result.gpu_resident_routes_calls -or
              $result.gpu_resident_routes_no_default_sync_calls -ne 0) {
        throw "G48 default-sync accounting mismatch: tag=$Tag"
    }
    if ($ExpectedSHA256 -and
        ($result.expected_content_sha256 -ne $ExpectedSHA256 -or
         $result.results[0].content_sha256 -ne $ExpectedSHA256)) {
        throw "G48 expected content mismatch: tag=$Tag"
    }

    [pscustomobject]@{
        tag = $Tag
        arm = $Arm
        result_path = $resultPath
        content_sha256 = $result.results[0].content_sha256
        content = $result.results[0].content
        completion_tokens = [int]$result.results[0].completion_tokens
        decode_tokens_per_second = [double]$result.server_decode_mean_tokens_per_second
        ttft_seconds = [double]$result.server_prefill_ttft_mean_seconds
        wrap_seconds = [double]$result.prefill_mass_wrap_seconds
        route_calls = [uint64]$result.gpu_resident_routes_calls
        vram_hits = [uint64]$tier.vram_hits
        ram_hits = [uint64]$tier.ram_hits
        ram_h2d_gib = [uint64]$tier.ram_h2d_bytes / 1GB
        snapshot_misses = [uint64]$tier.snapshot_backing_misses
        ssd_bytes = [uint64]$tier.ssd_bytes
        failures = [uint64]$tier.failures
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
    }
}

New-Item -ItemType Directory -Force -Path $outdir | Out-Null
if ($OutlierRecheck) {
    $case = $cases[0]
    $resumeMode = $Resume
    $script:Resume = $true
    try {
        $reference = Invoke-G48Run `
            -Tag "g48_italian_explanation_default" `
            -Prompt $case.prompt -Context $case.context -Arm "default-sync"
    } finally {
        $script:Resume = $resumeMode
    }
    $rechecks = @()
    foreach ($suffix in @("a", "b", "c")) {
        $rechecks += Invoke-G48Run `
            -Tag ("g48_italian_default_outlier_recheck_" + $suffix) `
            -Prompt $case.prompt -Context $case.context -Arm "default-sync" `
            -ExpectedSHA256 $reference.content_sha256
    }
    $recheckSummary = [pscustomobject]@{
        schema = "g48_italian_default_wrap_outlier_recheck_v1"
        question = "Does the 332-second Italian default-sync TTFT/WRAP event repeat in three additional identical processes?"
        prompt = $case.prompt
        context = $case.context
        max_tokens = 64
        expected_content_sha256 = $reference.content_sha256
        performance_verdict = "none; three-extra-process outlier rule"
        runner_sha256 = (Get-FileHash -LiteralPath $MyInvocation.MyCommand.Path -Algorithm SHA256).Hash.ToLowerInvariant()
        reference = $reference
        rechecks = $rechecks
    }
    $recheckPath = Join-Path $outdir "g48_italian_default_outlier_recheck_result.json"
    $recheckSummary | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 $recheckPath
    Write-Host ("[g48] outlier recheck complete: " + $recheckPath)
    exit 0
}

$pairs = @()
foreach ($case in $cases) {
    $default = Invoke-G48Run `
        -Tag ("g48_" + $case.name + "_default") `
        -Prompt $case.prompt -Context $case.context -Arm "default-sync"
    $candidate = Invoke-G48Run `
        -Tag ("g48_" + $case.name + "_nosync") `
        -Prompt $case.prompt -Context $case.context -Arm "no-default-sync" `
        -ExpectedSHA256 $default.content_sha256
    if ($candidate.content_sha256 -ne $default.content_sha256 -or
        $candidate.content -cne $default.content -or
        $candidate.completion_tokens -ne $default.completion_tokens) {
        throw "G48 pair mismatch: case=$($case.name)"
    }
    $pairs += [pscustomobject]@{
        name = $case.name
        context = $case.context
        prompt = $case.prompt
        content_sha256 = $default.content_sha256
        completion_tokens = $default.completion_tokens
        exact_match = $true
        default = $default
        no_default_sync = $candidate
    }
}

$provenanceFields = @(
    "head", "executable_sha256", "ds4_cuda_sha256", "ds4_c_sha256",
    "ds4_server_c_sha256", "build_manifest_sha256",
    "build_input_fingerprint_sha256", "harness_sha256", "model",
    "model_bytes", "model_last_write_utc"
)
$allRuns = @($pairs | ForEach-Object { $_.default; $_.no_default_sync })
foreach ($field in $provenanceFields) {
    $values = @($allRuns | ForEach-Object { [string]($_.$field) } | Select-Object -Unique)
    if ($values.Count -ne 1) { throw "G48 mixed provenance: field=$field" }
}

$summary = [pscustomobject]@{
    schema = "g48_no_default_sync_cross_prompt_exactness_v1"
    question = "Does G46 no-default-sync preserve exact output across three prompt shapes?"
    contexts = @($cases | ForEach-Object { $_.context })
    max_tokens = 64
    independent_processes_per_pair = 2
    performance_verdict = "none; exactness-only n=1 per arm per prompt"
    runner_sha256 = (Get-FileHash -LiteralPath $MyInvocation.MyCommand.Path -Algorithm SHA256).Hash.ToLowerInvariant()
    provenance = [pscustomobject]@{
        head = $allRuns[0].head
        executable_sha256 = $allRuns[0].executable_sha256
        ds4_cuda_sha256 = $allRuns[0].ds4_cuda_sha256
        ds4_c_sha256 = $allRuns[0].ds4_c_sha256
        ds4_server_c_sha256 = $allRuns[0].ds4_server_c_sha256
        build_manifest_sha256 = $allRuns[0].build_manifest_sha256
        build_input_fingerprint_sha256 = $allRuns[0].build_input_fingerprint_sha256
        harness_sha256 = $allRuns[0].harness_sha256
        model = $allRuns[0].model
        model_bytes = $allRuns[0].model_bytes
        model_last_write_utc = $allRuns[0].model_last_write_utc
    }
    pairs = $pairs
}

$summaryPath = Join-Path $outdir "g48_no_default_sync_cross_prompt_result.json"
$summary | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 $summaryPath
Write-Host ("[g48] exactness gate complete: " + $summaryPath)
