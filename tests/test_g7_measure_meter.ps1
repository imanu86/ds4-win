$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$helper = Join-Path $root "g7_measure_meter.ps1"
if (-not (Test-Path -LiteralPath $helper -PathType Leaf)) {
    throw "G7 measurement meter helper missing: $helper"
}
. $helper

function Assert-Close {
    param(
        [Parameter(Mandatory=$true)][double]$Actual,
        [Parameter(Mandatory=$true)][double]$Expected,
        [double]$Tolerance = 0.000001,
        [Parameter(Mandatory=$true)][string]$Name
    )
    if ([math]::Abs($Actual - $Expected) -gt $Tolerance) {
        throw "$Name mismatch: actual=$Actual expected=$Expected"
    }
}

function New-ClientRun {
    param([int]$Tokens, [double]$Seconds)
    [pscustomobject]@{
        completion_tokens = $Tokens
        seconds = $Seconds
        tokens_per_second = [math]::Round($Tokens / $Seconds, 6)
    }
}

function New-ServerRun {
    param(
        [int]$Tokens,
        [double]$DecodeSeconds,
        [double]$ParsedAvg,
        [double]$TotalSeconds
    )
    [pscustomobject]@{
        generated_tokens = $Tokens
        server_decode_seconds = $DecodeSeconds
        server_avg_tokens_per_second = $ParsedAvg
        server_total_seconds = $TotalSeconds
        server_prefill_ttft_seconds = [math]::Max(0.0, $TotalSeconds - $DecodeSeconds)
    }
}

$m1 = Invoke-G7MeasurementAggregation `
    -Results @((New-ClientRun -Tokens 100 -Seconds 10.0)) `
    -ServerRunsAll @((New-ServerRun -Tokens 100 -DecodeSeconds 5.0 -ParsedAvg 20.0 -TotalSeconds 10.0)) `
    -Repeats 1 `
    -Warmup $false
if (-not $m1.valid -or $m1.status -ne "VALID") {
    throw "M1 valid aggregation unexpectedly failed: $($m1.invalid_reason)"
}
Assert-Close -Actual $m1.decode_tps -Expected 20.0 -Name "M1 decode_tps"
Assert-Close -Actual $m1.client_wall_tps -Expected 10.0 -Name "M1 client_wall_tps"
if ($m1.decode_tps -eq $m1.client_wall_tps) {
    throw "M1 decode headline was not separated from client wall throughput"
}

$m2Warmup = Invoke-G7MeasurementAggregation `
    -Results @((New-ClientRun -Tokens 10 -Seconds 1.0), (New-ClientRun -Tokens 10 -Seconds 1.0)) `
    -ServerRunsAll @(
        (New-ServerRun -Tokens 1 -DecodeSeconds 1.0 -ParsedAvg 1.0 -TotalSeconds 2.0),
        (New-ServerRun -Tokens 10 -DecodeSeconds 1.0 -ParsedAvg 10.0 -TotalSeconds 1.5),
        (New-ServerRun -Tokens 10 -DecodeSeconds 1.0 -ParsedAvg 10.0 -TotalSeconds 1.5)) `
    -Repeats 2 `
    -Warmup $true
if (-not $m2Warmup.valid -or $m2Warmup.samples_used -ne 2) {
    throw "M2 warmup exclusion failed"
}
Assert-Close -Actual $m2Warmup.decode_tps -Expected 10.0 -Name "M2 warmup-excluded decode_tps"

$m2Invalid = Invoke-G7MeasurementAggregation `
    -Results @((New-ClientRun -Tokens 10 -Seconds 1.0), (New-ClientRun -Tokens 10 -Seconds 1.0)) `
    -ServerRunsAll @((New-ServerRun -Tokens 10 -DecodeSeconds 1.0 -ParsedAvg 10.0 -TotalSeconds 1.5)) `
    -Repeats 2 `
    -Warmup $false
if ($m2Invalid.valid -or $m2Invalid.status -ne "INVALID" -or
    $m2Invalid.invalid_reason -notmatch "samples_used=1 expected_repeats=2") {
    throw "M2 missing-sample invalidation failed"
}

$rawDecodeSeconds = 1.234567890
$rawTps = 123.0 / $rawDecodeSeconds
$m3ServerRuns = @(ConvertFrom-G7ServerStderrLines -Lines @(
    "ds4-server: chat prompt start",
    "ds4-server: [q1-0-profile-token] schema=g130_u1_profile_token_v1 result=progress final=0 gen=123 decode_elapsed_seconds=1.234567890",
    "ds4-server: chat ctx=0..1:1 gen=123 decoding chunk=99.63 t/s avg=100.00 t/s 1.235s",
    "ds4-server: chat gen=123 finish=length 3.000s"))
if ($m3ServerRuns.Count -ne 1) {
    throw "M3 parser did not emit exactly one server run"
}
Assert-Close -Actual $m3ServerRuns[0].server_decode_seconds -Expected $rawDecodeSeconds -Name "M3 parser raw decode seconds"
Assert-Close -Actual $m3ServerRuns[0].server_rounded_decode_seconds -Expected 1.235 -Name "M3 parser rounded echo seconds"
$m3 = Invoke-G7MeasurementAggregation `
    -Results @((New-ClientRun -Tokens 123 -Seconds 3.0)) `
    -ServerRunsAll $m3ServerRuns `
    -Repeats 1 `
    -Warmup $false
Assert-Close -Actual $m3.decode_tps -Expected ([math]::Round($rawTps, 6)) -Name "M3 raw recomputed decode_tps"
if ($m3.decode_tps -eq $m3.server_parsed_decode_mean_tokens_per_second) {
    throw "M3 decode_tps incorrectly used parsed rounded value"
}
if (-not $m3.server_parsed_decode_tps_cross_check_ok) {
    throw "M3 parsed cross-check should tolerate rounded echo"
}

$m3Invalid = Invoke-G7MeasurementAggregation `
    -Results @((New-ClientRun -Tokens 100 -Seconds 2.0)) `
    -ServerRunsAll @((New-ServerRun -Tokens 100 -DecodeSeconds 1.0 -ParsedAvg 50.0 -TotalSeconds 2.0)) `
    -Repeats 1 `
    -Warmup $false
if ($m3Invalid.valid -or $m3Invalid.status -ne "INVALID" -or
    $m3Invalid.invalid_reason -notmatch "cross-check exceeded tolerance") {
    throw "M3 parsed cross-check invalidation failed"
}

Write-Host "test_g7_measure_meter.ps1: PASS"
