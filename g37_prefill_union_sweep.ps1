# G37 existing batch-union telemetry and chunk amplification sweep (PS 5.1).
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$harness = Join-Path $root "g7_measure.ps1"
$outdir = Join-Path $root "g7_runs"
$model = "C:\ds4-models\ds4-2bit.gguf"
$prompt = "Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document."
$expected = "aa3b17600d88d3161605db8389b5bf03d4e94debcc8eeb74dca27aed95a154ab"
$promptTokens = 43
$moeLayers = 42
$requestsPerProcess = 4 # one discarded warmup plus n=3 measured requests

function Invoke-G37Run {
    param(
        [Parameter(Mandatory=$true)][string]$Tag,
        [Parameter(Mandatory=$true)][ValidateSet(-1, 0, 8, 16)][int]$Chunk,
        [Parameter(Mandatory=$true)][bool]$UnionStats,
        [Parameter(Mandatory=$true)][ValidateSet("overhead", "chunk")][string]$Phase
    )

    $args = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $harness,
        "-MaxTokens", "1", "-Repeats", "3", "-Warmup",
        "-Tag", $Tag, "-Prompt", $prompt, "-Context", "256",
        "-BudgetGB", "2", "-ReserveMB", "4096", "-RuntimeReserveMB", "128",
        "-ExpertCacheN", "336", "-ExpertCacheReserveGB", "0.5",
        "-ExpertCachePolicy", "lru", "-DisableQ8F16Cache",
        "-EmbedRowStaging", "-GpuResidentRoutes",
        "-PrefillChunk", "$Chunk",
        "-ExpectedContentSHA256", $expected,
        "-ExpectedWarmupContentSHA256", $expected,
        "-ModelPath", $model, "-TimeoutSec", "900"
    )
    if ($UnionStats) { $args += "-PrefillUnionStats" }

    Write-Host ("[g37] start tag=" + $Tag + " phase=" + $Phase +
        " chunk=" + $Chunk + " stats=" + $UnionStats)
    & powershell.exe @args | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) {
        throw "G37 run failed: $Tag (exit=$LASTEXITCODE)"
    }

    $resultPath = Join-Path $outdir ("g7_" + $Tag + "_result.json")
    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        throw "G37 result missing: $resultPath"
    }
    $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    $expectedObservedChunk = if ($Chunk -le 0) { 256 } else { $Chunk }
    if (-not $result.outputs_identical -or
        $result.expected_content_sha256 -ne $expected -or
        $null -eq $result.warmup_result -or
        $result.warmup_result.content_sha256 -ne $expected) {
        throw "G37 exact output mismatch: tag=$Tag"
    }
    if ($result.context_requested -ne 256 -or
        $result.expert_cache_requested -ne 336 -or
        $result.expert_cache_policy -ne "lru" -or
        -not $result.gpu_resident_routes_requested -or
        -not $result.q8_f16_cache_disabled -or
        $result.prefill_chunk_requested -ne $Chunk -or
        $result.prefill_chunk_observed -ne $expectedObservedChunk) {
        throw "G37 run configuration mismatch: tag=$Tag"
    }
    if ([bool]$result.prefill_union_stats_requested -ne $UnionStats -or
        [bool]$result.prefill_union_stats_observed -ne $UnionStats) {
        throw "G37 union telemetry mismatch: tag=$Tag"
    }
    if ($UnionStats) {
        $chunksPerRequest = [math]::Ceiling($promptTokens / [double]$(if ($Chunk -le 0) { $promptTokens } else { $Chunk }))
        $expectedCalls = [uint64]($moeLayers * $chunksPerRequest * $requestsPerProcess)
        $expectedTokenRows = [uint64]($moeLayers * $promptTokens * $requestsPerProcess)
        if ($result.prefill_union_calls -ne $expectedCalls -or
            $result.prefill_union_tokens -ne $expectedTokenRows -or
            $result.prefill_union_selected_slots -ne ($expectedTokenRows * 6) -or
            $result.prefill_union_unique_experts -le 0 -or
            $result.prefill_union_source_span_bytes -le 0 -or
            $result.prefill_union_upload_syncs -ne $expectedCalls) {
            throw "G37 union accounting mismatch: tag=$Tag"
        }
        $expectedMaxTokens = if ($Chunk -le 0) { $promptTokens } else { $Chunk }
        if ($result.prefill_union_max_tokens -ne $expectedMaxTokens -or
            $result.prefill_union_max_union -le 0 -or
            $result.prefill_union_max_union -gt 256) {
            throw "G37 union bound mismatch: tag=$Tag"
        }
    }

    [pscustomobject]@{
        tag = $Tag
        phase = $Phase
        chunk = $Chunk
        union_stats = $UnionStats
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
        mean_tokens_per_second = $result.mean_tokens_per_second
        server_prefill_ttft_mean_seconds = $result.server_prefill_ttft_mean_seconds
        warmup_seconds = $result.warmup_seconds
        process_read_bytes = $result.runtime_telemetry.win32_process_read_transfer_delta_bytes
        page_fault_delta = $result.runtime_telemetry.page_fault_delta
        union_calls = $result.prefill_union_calls
        union_token_rows = $result.prefill_union_tokens
        selected_slots = $result.prefill_union_selected_slots
        unique_experts = $result.prefill_union_unique_experts
        dedup_ratio = $result.prefill_union_dedup_ratio
        max_union = $result.prefill_union_max_union
        source_span_bytes = $result.prefill_union_source_span_bytes
        arena_h2d_bytes = $result.prefill_union_arena_h2d_bytes
        cache_d2d_bytes = $result.prefill_union_cache_d2d_bytes
        upload_syncs = $result.prefill_union_upload_syncs
    }
}

$runs = @()
$runs += Invoke-G37Run -Tag "g37_stats_off_a" -Chunk 0 -UnionStats $false -Phase "overhead"
$runs += Invoke-G37Run -Tag "g37_stats_on_a"  -Chunk 0 -UnionStats $true  -Phase "overhead"
$runs += Invoke-G37Run -Tag "g37_stats_on_b"  -Chunk 0 -UnionStats $true  -Phase "overhead"
$runs += Invoke-G37Run -Tag "g37_stats_off_b" -Chunk 0 -UnionStats $false -Phase "overhead"

$runs += Invoke-G37Run -Tag "g37_chunk_full_a" -Chunk 0  -UnionStats $true -Phase "chunk"
$runs += Invoke-G37Run -Tag "g37_chunk_16_a"   -Chunk 16 -UnionStats $true -Phase "chunk"
$runs += Invoke-G37Run -Tag "g37_chunk_8"      -Chunk 8  -UnionStats $true -Phase "chunk"
$runs += Invoke-G37Run -Tag "g37_chunk_16_b"   -Chunk 16 -UnionStats $true -Phase "chunk"
$runs += Invoke-G37Run -Tag "g37_chunk_full_b" -Chunk 0  -UnionStats $true -Phase "chunk"

$provenanceFields = @(
    "head", "executable_sha256", "ds4_cuda_sha256", "ds4_c_sha256",
    "build_manifest_sha256", "build_input_fingerprint_sha256", "harness_sha256",
    "model", "model_bytes", "model_last_write_utc", "build_worktree_dirty"
)
foreach ($field in $provenanceFields) {
    $values = @($runs | ForEach-Object { [string]($_.$field) } | Select-Object -Unique)
    if ($values.Count -ne 1) {
        throw "G37 mixed provenance across runs: field=$field"
    }
}

$statsOff = @($runs | Where-Object { $_.phase -eq "overhead" -and -not $_.union_stats })
$statsOn = @($runs | Where-Object { $_.phase -eq "overhead" -and $_.union_stats })
$chunkFull = @($runs | Where-Object { $_.phase -eq "chunk" -and $_.chunk -eq 0 })
$chunk16 = @($runs | Where-Object { $_.phase -eq "chunk" -and $_.chunk -eq 16 })
$chunk8 = @($runs | Where-Object { $_.phase -eq "chunk" -and $_.chunk -eq 8 })
if ($statsOff.Count -ne 2 -or $statsOn.Count -ne 2 -or
    $chunkFull.Count -ne 2 -or $chunk16.Count -ne 2 -or $chunk8.Count -ne 1) {
    throw "G37 matrix shape mismatch"
}

function Get-Mean([object[]]$Rows, [string]$Property) {
    return [math]::Round(($Rows | Measure-Object -Property $Property -Average).Average, 6)
}

$summary = [pscustomobject]@{
    schema = "g37_prefill_union_sweep_v1"
    model = $model
    prompt = $prompt
    prompt_tokens = $promptTokens
    expected_content_sha256 = $expected
    repeats_per_process = 3
    discarded_warmup_per_process = 1
    order = @($runs | ForEach-Object { $_.tag })
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
    telemetry_overhead = [pscustomobject]@{
        off_ttft_mean_seconds = Get-Mean $statsOff "server_prefill_ttft_mean_seconds"
        on_ttft_mean_seconds = Get-Mean $statsOn "server_prefill_ttft_mean_seconds"
        off_client_tps_mean = Get-Mean $statsOff "mean_tokens_per_second"
        on_client_tps_mean = Get-Mean $statsOn "mean_tokens_per_second"
    }
    chunk_summary = @(
        [pscustomobject]@{ chunk = 0; replications = 2; ttft_mean_seconds = Get-Mean $chunkFull "server_prefill_ttft_mean_seconds"; unique_experts_mean = Get-Mean $chunkFull "unique_experts"; source_span_bytes_mean = Get-Mean $chunkFull "source_span_bytes"; process_read_bytes_mean = Get-Mean $chunkFull "process_read_bytes" },
        [pscustomobject]@{ chunk = 16; replications = 2; ttft_mean_seconds = Get-Mean $chunk16 "server_prefill_ttft_mean_seconds"; unique_experts_mean = Get-Mean $chunk16 "unique_experts"; source_span_bytes_mean = Get-Mean $chunk16 "source_span_bytes"; process_read_bytes_mean = Get-Mean $chunk16 "process_read_bytes" },
        [pscustomobject]@{ chunk = 8; replications = 1; ttft_mean_seconds = Get-Mean $chunk8 "server_prefill_ttft_mean_seconds"; unique_experts_mean = Get-Mean $chunk8 "unique_experts"; source_span_bytes_mean = Get-Mean $chunk8 "source_span_bytes"; process_read_bytes_mean = Get-Mean $chunk8 "process_read_bytes" }
    )
}

New-Item -ItemType Directory -Force -Path $outdir | Out-Null
$summaryPath = Join-Path $outdir "g37_prefill_union_sweep_result.json"
$summary | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 $summaryPath
Write-Host ("[g37] matrix complete: " + $summaryPath)
