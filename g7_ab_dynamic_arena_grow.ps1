param(
    [string]$TagPrefix = "g20_grow_ab",
    [string]$ModelPath = "C:\ds4-models\ds4-2bit.gguf",
    [ValidateRange(1, 256)][int]$GrowInterval = 8,
    [ValidateRange(250, 10000)][int]$TelemetryIntervalMs = 1000
)

$ErrorActionPreference = "Stop"
$harness = Join-Path $PSScriptRoot "g7_measure.ps1"
$outdir = Join-Path $PSScriptRoot "g7_runs"
$prompt = "Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document."
$expectedHash = "fd6c4522975a71e252b90199d49cfe3236310e2a7285dc0fc4d0e9d0e4885510"
$order = @(
    [pscustomobject]@{ arm = "off"; grow = 0 },
    [pscustomobject]@{ arm = "on"; grow = $GrowInterval },
    [pscustomobject]@{ arm = "on"; grow = $GrowInterval },
    [pscustomobject]@{ arm = "off"; grow = 0 },
    [pscustomobject]@{ arm = "off"; grow = 0 },
    [pscustomobject]@{ arm = "on"; grow = $GrowInterval }
)

$runs = @()
for ($i = 0; $i -lt $order.Count; $i++) {
    $spec = $order[$i]
    $ordinal = $i + 1
    $tag = "${TagPrefix}_${ordinal}_$($spec.arm)_n1"
    Write-Host "[g7-ab] $ordinal/$($order.Count) arm=$($spec.arm) grow=$($spec.grow) tag=$tag"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $harness `
        -MaxTokens 64 -Repeats 1 -TimeoutSec 900 -Tag $tag `
        -Prompt $prompt -ReserveMB 1024 -BudgetGB 2 `
        -DynamicArenaGiB 12 -DynamicArenaObservedWindow 16 `
        -DynamicArenaObservedMinHits 3 `
        -DynamicArenaGrowInterval $spec.grow -ReapPrefetchThreads 8 `
        -ModelPath $ModelPath -ExpectedContentSHA256 $expectedHash `
        -Context 256 -TelemetryIntervalMs $TelemetryIntervalMs
    if ($LASTEXITCODE -ne 0) {
        throw "A/B run failed: tag=$tag exit=$LASTEXITCODE"
    }
    $resultPath = Join-Path $outdir ("g7_" + $tag + "_result.json")
    if (-not (Test-Path -LiteralPath $resultPath)) {
        throw "A/B result missing: $resultPath"
    }
    $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    if ($result.results[0].content_sha256 -ne $expectedHash) {
        throw "A/B exact output mismatch: tag=$tag"
    }
    $runs += [pscustomobject]@{
        ordinal = $ordinal
        arm = $spec.arm
        grow_interval = $spec.grow
        tag = $tag
        result_path = $resultPath
        executable_sha256 = $result.executable_sha256
        source_sha256 = $result.ds4_cuda_sha256
        harness_sha256 = $result.harness_sha256
        runtime_monitor_sha256 = $result.runtime_monitor_harness_sha256
        content_sha256 = $result.results[0].content_sha256
        decode_tokens_per_second = $result.server_decode_mean_tokens_per_second
        wall_tokens_per_second = $result.mean_tokens_per_second
        ttft_seconds = $result.server_prefill_ttft_mean_seconds
        arena_resident_bytes = $result.dynamic_arena_observer_resident_bytes
        arena_occupancy_ratio = $result.dynamic_arena_occupancy_ratio
        arena_hits = $result.dynamic_arena_final_hits
        arena_misses = $result.dynamic_arena_final_misses
        arena_hit_rate = $result.dynamic_arena_hit_rate
        arena_h2d_uploaded_gib = $result.dynamic_arena_h2d_uploaded_gib
        telemetry = $result.runtime_telemetry
    }
}

function Get-G7Median([double[]]$Values) {
    $ordered = @($Values | Sort-Object)
    if ($ordered.Count -eq 0) { return $null }
    $middle = [int][math]::Floor($ordered.Count / 2)
    if (($ordered.Count % 2) -eq 1) { return [double]$ordered[$middle] }
    return ([double]$ordered[$middle - 1] + [double]$ordered[$middle]) / 2.0
}

$off = @($runs | Where-Object { $_.arm -eq "off" })
$on = @($runs | Where-Object { $_.arm -eq "on" })
$aggregate = [pscustomobject]@{
    schema = "g7_dynamic_arena_grow_ab_v1"
    created_utc = (Get-Date).ToUniversalTime().ToString("o")
    protocol = "Six independent processes in OFF,ON,ON,OFF,OFF,ON order; n=3 per arm; exact greedy output required"
    prompt = $prompt
    expected_content_sha256 = $expectedHash
    grow_interval = $GrowInterval
    off_decode_tps_samples = @($off | ForEach-Object { $_.decode_tokens_per_second })
    on_decode_tps_samples = @($on | ForEach-Object { $_.decode_tokens_per_second })
    off_decode_tps_median = Get-G7Median @($off | ForEach-Object { [double]$_.decode_tokens_per_second })
    on_decode_tps_median = Get-G7Median @($on | ForEach-Object { [double]$_.decode_tokens_per_second })
    off_hit_rate_samples = @($off | ForEach-Object { $_.arena_hit_rate })
    on_hit_rate_samples = @($on | ForEach-Object { $_.arena_hit_rate })
    runs = $runs
}
$aggregatePath = Join-Path $outdir ("g7_" + $TagPrefix + "_aggregate.json")
$aggregate | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $aggregatePath -Encoding UTF8
Write-Host "[g7-ab] aggregate=$aggregatePath"
Write-Host ("[g7-ab] off t/s=" + ($aggregate.off_decode_tps_samples -join ",") + " median=" + $aggregate.off_decode_tps_median)
Write-Host ("[g7-ab] on  t/s=" + ($aggregate.on_decode_tps_samples -join ",") + " median=" + $aggregate.on_decode_tps_median)
