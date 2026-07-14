param(
    [string]$TagPrefix = "g23_crossdomain_caesar_ab_20260714",
    [string]$ModelPath = "C:\ds4-models\ds4-2bit.gguf",
    [ValidateRange(250, 10000)][int]$TelemetryIntervalMs = 1000
)

$ErrorActionPreference = "Stop"
$harness = Join-Path $PSScriptRoot "g7_measure.ps1"
$outdir = Join-Path $PSScriptRoot "g7_runs"
$warmupPrompt = "Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document."
$prompt = "Write a concise but complete historical analysis of Julius Caesar's crossing of the Rubicon, including political context, immediate consequences, and long-term significance. Return plain prose only."
$expectedWarmupHash = "f2677447c1a5e95934469c6c8f07ee943ccd9c079ef9350b07c2d0ce8fc1b576"
$expectedHash = "c5d3147481576ee908f3fa1ffc49cbf6620ad1d1eab1a1c43ffd66ebb7c9c281"
$order = @("drop", "keep", "keep", "drop", "drop", "keep")

$runs = @()
for ($i = 0; $i -lt $order.Count; $i++) {
    $arm = $order[$i]
    $ordinal = $i + 1
    $tag = "${TagPrefix}_${ordinal}_${arm}_n1"
    Write-Host "[g7-crossdomain-ab] $ordinal/$($order.Count) arm=$arm tag=$tag"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $harness `
        -Tag $tag -Prompt $prompt -WarmupPrompt $warmupPrompt `
        -ModelPath $ModelPath -MaxTokens 256 -Repeats 1 -Warmup -TimeoutSec 900 `
        -ExpectedWarmupContentSHA256 $expectedWarmupHash `
        -ExpectedContentSHA256 $expectedHash `
        -BudgetGB 2 -ReserveMB 1024 -Context 256 `
        -DynamicArenaGiB 30 -DynamicArenaObservedWindow 64 `
        -DynamicArenaObservedMinHits 1 -DynamicArenaCarry $arm `
        -ReapPrefetchThreads 8 -IoQD 1 `
        -TelemetryIntervalMs $TelemetryIntervalMs
    if ($LASTEXITCODE -ne 0) {
        throw "G23 cross-domain A/B run failed: tag=$tag exit=$LASTEXITCODE"
    }

    $resultPath = Join-Path $outdir ("g7_" + $tag + "_result.json")
    if (-not (Test-Path -LiteralPath $resultPath)) {
        throw "G23 cross-domain result missing: $resultPath"
    }
    $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    if ($result.results.Count -ne 1 -or
        $result.results[0].content_sha256 -ne $expectedHash -or
        $result.warmup_result.content_sha256 -ne $expectedWarmupHash) {
        throw "G23 cross-domain output mismatch: tag=$tag"
    }
    $carryEvents = @($result.dynamic_arena_carry_events)
    $expectedLookup = if ($arm -eq "keep") { "enabled" } else { "disabled" }
    if ($carryEvents.Count -ne 2 -or
        $carryEvents[0].request -ne 1 -or $carryEvents[0].mode -ne "prime" -or
        $carryEvents[0].snapshot -ne 0 -or $carryEvents[0].resident -ne 0 -or
        $carryEvents[0].lookup -ne "enabled" -or $carryEvents[0].observer -ne "learning" -or
        $carryEvents[1].request -ne 2 -or $carryEvents[1].mode -ne $arm -or
        $carryEvents[1].snapshot -le 0 -or $carryEvents[1].resident -le 0 -or
        $carryEvents[1].lookup -ne $expectedLookup -or $carryEvents[1].observer -ne "frozen") {
        throw "G23 cross-domain carry provenance mismatch: tag=$tag"
    }
    if ($result.dynamic_arena_observer_publication_count -ne 1 -or
        $result.dynamic_arena_wrap_publication_count -ne 1 -or
        $result.dynamic_arena_final_fatal -ne 0) {
        throw "G23 cross-domain fail-closed state mismatch: tag=$tag"
    }

    $runs += [pscustomobject]@{
        ordinal = $ordinal
        arm = $arm
        tag = $tag
        result_path = $resultPath
        head = $result.head
        executable_sha256 = $result.executable_sha256
        source_sha256 = $result.ds4_cuda_sha256
        harness_sha256 = $result.harness_sha256
        warmup_content_sha256 = $result.warmup_result.content_sha256
        content_sha256 = $result.results[0].content_sha256
        decode_tokens_per_second = [double]$result.server_decode_mean_tokens_per_second
        wall_tokens_per_second = [double]$result.mean_tokens_per_second
        ttft_seconds = [double]$result.server_prefill_ttft_mean_seconds
        arena_hit_rate = [double]$result.dynamic_arena_hit_rate
        arena_snapshot = [long]$result.dynamic_arena_carry_snapshot_observed
        arena_resident = [long]$result.dynamic_arena_carry_resident_observed
        process_read_gib = [double]$result.runtime_telemetry.win32_process_read_transfer_delta_bytes / 1GB
    }
}

function Get-G7Median([double[]]$Values) {
    $ordered = @($Values | Sort-Object)
    if ($ordered.Count -eq 0) { return $null }
    $middle = [int][math]::Floor($ordered.Count / 2)
    if (($ordered.Count % 2) -eq 1) { return [double]$ordered[$middle] }
    return ([double]$ordered[$middle - 1] + [double]$ordered[$middle]) / 2.0
}

$drop = @($runs | Where-Object { $_.arm -eq "drop" })
$keep = @($runs | Where-Object { $_.arm -eq "keep" })
if ($drop.Count -ne 3 -or $keep.Count -ne 3) {
    throw "G23 cross-domain A/B requires exactly three valid runs per arm"
}
foreach ($field in @("head", "executable_sha256", "source_sha256", "harness_sha256")) {
    if (@($runs | Select-Object -ExpandProperty $field -Unique).Count -ne 1) {
        throw "G23 cross-domain A/B mixed provenance: field=$field"
    }
}

$dropMedian = Get-G7Median @($drop | ForEach-Object { [double]$_.decode_tokens_per_second })
$keepMedian = Get-G7Median @($keep | ForEach-Object { [double]$_.decode_tokens_per_second })
$keepMinimum = ($keep | Measure-Object decode_tokens_per_second -Minimum).Minimum
$ratio = if ($dropMedian -gt 0) { $keepMedian / $dropMedian } else { 0 }
$promotionPassed = ($keepMinimum -ge 2.4 -and $ratio -ge 1.5)

$aggregate = [pscustomobject]@{
    schema = "g7_dynamic_arena_crossdomain_ab_v1"
    created_utc = (Get-Date).ToUniversalTime().ToString("o")
    protocol = "Six independent processes in DROP,KEEP,KEEP,DROP,DROP,KEEP order; request 1 Cyber HTML prime; request 2 Caesar measured; n=3 per arm"
    warmup_prompt = $warmupPrompt
    prompt = $prompt
    expected_warmup_content_sha256 = $expectedWarmupHash
    expected_content_sha256 = $expectedHash
    common_parameters = [pscustomobject]@{
        max_tokens = 256; context = 256; dynamic_arena_gib = 30
        observed_window = 64; observed_min_hits = 1
        masked_ram_budget_gib = 2; cuda_reserve_mib = 1024
        wrap_workers = 8; moe_io_qd = 1
        expert_cache = 0; spex = "off"; overlap = "off"
    }
    drop_decode_tps_samples = @($drop | ForEach-Object { $_.decode_tokens_per_second })
    keep_decode_tps_samples = @($keep | ForEach-Object { $_.decode_tokens_per_second })
    drop_decode_tps_median = $dropMedian
    keep_decode_tps_median = $keepMedian
    keep_decode_tps_minimum = $keepMinimum
    keep_to_drop_median_ratio = $ratio
    drop_hit_rate_samples = @($drop | ForEach-Object { $_.arena_hit_rate })
    keep_hit_rate_samples = @($keep | ForEach-Object { $_.arena_hit_rate })
    promotion_gate = [pscustomobject]@{
        every_keep_at_least_2_4 = ($keepMinimum -ge 2.4)
        keep_drop_ratio_at_least_1_5 = ($ratio -ge 1.5)
        all_warmup_hashes_exact = $true
        all_measured_hashes_exact = $true
        passed = $promotionPassed
    }
    runs = $runs
}
$aggregatePath = Join-Path $outdir ("g7_" + $TagPrefix + "_aggregate.json")
$aggregate | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $aggregatePath -Encoding UTF8
Write-Host "[g7-crossdomain-ab] aggregate=$aggregatePath"
Write-Host ("[g7-crossdomain-ab] DROP t/s=" + ($aggregate.drop_decode_tps_samples -join ",") + " median=" + $dropMedian)
Write-Host ("[g7-crossdomain-ab] KEEP t/s=" + ($aggregate.keep_decode_tps_samples -join ",") + " median=" + $keepMedian)
Write-Host ("[g7-crossdomain-ab] ratio=" + $ratio + " promotion_passed=" + $promotionPassed)
