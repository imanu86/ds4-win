param(
    [string]$TagPrefix = "g22_carry_ab_20260714",
    [string]$ModelPath = "C:\ds4-models\ds4-2bit.gguf",
    [ValidateRange(250, 10000)][int]$TelemetryIntervalMs = 1000
)

$ErrorActionPreference = "Stop"
$harness = Join-Path $PSScriptRoot "g7_measure.ps1"
$outdir = Join-Path $PSScriptRoot "g7_runs"
$prompt = "Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document."
$expectedHash = "f2677447c1a5e95934469c6c8f07ee943ccd9c079ef9350b07c2d0ce8fc1b576"
$order = @("drop", "keep", "keep", "drop", "drop", "keep")

$runs = @()
for ($i = 0; $i -lt $order.Count; $i++) {
    $arm = $order[$i]
    $ordinal = $i + 1
    $tag = "${TagPrefix}_${ordinal}_${arm}_n1"
    Write-Host "[g7-carry-ab] $ordinal/$($order.Count) arm=$arm tag=$tag"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $harness `
        -Tag $tag -Prompt $prompt -ModelPath $ModelPath `
        -MaxTokens 256 -Repeats 1 -Warmup -TimeoutSec 900 `
        -BudgetGB 2 -ReserveMB 1024 -Context 256 `
        -DynamicArenaGiB 30 -DynamicArenaObservedWindow 64 `
        -DynamicArenaObservedMinHits 1 -DynamicArenaCarry $arm `
        -ReapPrefetchThreads 8 -IoQD 1 `
        -ExpectedContentSHA256 $expectedHash `
        -TelemetryIntervalMs $TelemetryIntervalMs
    if ($LASTEXITCODE -ne 0) {
        throw "G22 carry A/B run failed: tag=$tag exit=$LASTEXITCODE"
    }

    $resultPath = Join-Path $outdir ("g7_" + $tag + "_result.json")
    if (-not (Test-Path -LiteralPath $resultPath)) {
        throw "G22 carry A/B result missing: $resultPath"
    }
    $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    if ($result.results.Count -ne 1 -or $result.results[0].content_sha256 -ne $expectedHash) {
        throw "G22 carry A/B exact output mismatch: tag=$tag"
    }
    if (-not $result.dynamic_arena_carry_observed -or
        $result.dynamic_arena_carry_mode_observed -ne $arm -or
        $result.dynamic_arena_carry_request_observed -ne 2 -or
        $result.dynamic_arena_carry_snapshot_observed -le 0 -or
        $result.dynamic_arena_carry_resident_observed -le 0 -or
        $result.dynamic_arena_carry_observer_observed -ne "frozen") {
        throw "G22 carry A/B telemetry mismatch: tag=$tag"
    }
    $expectedLookup = if ($arm -eq "keep") { "enabled" } else { "disabled" }
    if ($result.dynamic_arena_carry_lookup_observed -ne $expectedLookup -or
        $result.dynamic_arena_observer_publication_count -ne 1 -or
        $result.dynamic_arena_wrap_publication_count -ne 1 -or
        $result.dynamic_arena_final_fatal -ne 0) {
        throw "G22 carry A/B fail-closed state mismatch: tag=$tag"
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
        content_sha256 = $result.results[0].content_sha256
        decode_tokens_per_second = [double]$result.server_decode_mean_tokens_per_second
        wall_tokens_per_second = [double]$result.mean_tokens_per_second
        ttft_seconds = [double]$result.server_prefill_ttft_mean_seconds
        arena_snapshot = [long]$result.dynamic_arena_carry_snapshot_observed
        arena_resident = [long]$result.dynamic_arena_carry_resident_observed
        lookup = $result.dynamic_arena_carry_lookup_observed
        observer = $result.dynamic_arena_carry_observer_observed
        standby_before_gib = [double]$result.memory_preflight.before.standby_bytes / 1GB
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
    throw "G22 carry A/B requires exactly three valid runs per arm"
}
$identityFields = @("head", "executable_sha256", "source_sha256", "harness_sha256")
foreach ($field in $identityFields) {
    if (@($runs | Select-Object -ExpandProperty $field -Unique).Count -ne 1) {
        throw "G22 carry A/B mixed provenance: field=$field"
    }
}

$dropMedian = Get-G7Median @($drop | ForEach-Object { [double]$_.decode_tokens_per_second })
$keepMedian = Get-G7Median @($keep | ForEach-Object { [double]$_.decode_tokens_per_second })
$keepMinimum = ($keep | Measure-Object decode_tokens_per_second -Minimum).Minimum
$ratio = if ($dropMedian -gt 0) { $keepMedian / $dropMedian } else { 0 }
$promotionPassed = ($keepMedian -ge 4.0 -and $keepMinimum -ge 3.8 -and $ratio -ge 2.0)

$aggregate = [pscustomobject]@{
    schema = "g7_dynamic_arena_carry_ab_v1"
    created_utc = (Get-Date).ToUniversalTime().ToString("o")
    protocol = "Six independent processes in DROP,KEEP,KEEP,DROP,DROP,KEEP order; request 1 primes; request 2 measured; n=3 per arm"
    prompt = $prompt
    expected_content_sha256 = $expectedHash
    common_parameters = [pscustomobject]@{
        max_tokens = 256
        context = 256
        dynamic_arena_gib = 30
        observed_window = 64
        observed_min_hits = 1
        masked_ram_budget_gib = 2
        cuda_reserve_mib = 1024
        wrap_workers = 8
        moe_io_qd = 1
        expert_cache = 0
        spex = "off"
        overlap = "off"
    }
    drop_decode_tps_samples = @($drop | ForEach-Object { $_.decode_tokens_per_second })
    keep_decode_tps_samples = @($keep | ForEach-Object { $_.decode_tokens_per_second })
    drop_decode_tps_median = $dropMedian
    keep_decode_tps_median = $keepMedian
    keep_decode_tps_minimum = $keepMinimum
    keep_to_drop_median_ratio = $ratio
    promotion_gate = [pscustomobject]@{
        keep_median_at_least_4_0 = ($keepMedian -ge 4.0)
        every_keep_at_least_3_8 = ($keepMinimum -ge 3.8)
        keep_drop_ratio_at_least_2_0 = ($ratio -ge 2.0)
        all_hashes_exact = $true
        passed = $promotionPassed
    }
    runs = $runs
}
$aggregatePath = Join-Path $outdir ("g7_" + $TagPrefix + "_aggregate.json")
$aggregate | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $aggregatePath -Encoding UTF8
Write-Host "[g7-carry-ab] aggregate=$aggregatePath"
Write-Host ("[g7-carry-ab] DROP t/s=" + ($aggregate.drop_decode_tps_samples -join ",") + " median=" + $dropMedian)
Write-Host ("[g7-carry-ab] KEEP t/s=" + ($aggregate.keep_decode_tps_samples -join ",") + " median=" + $keepMedian)
Write-Host ("[g7-carry-ab] ratio=" + $ratio + " promotion_passed=" + $promotionPassed)
