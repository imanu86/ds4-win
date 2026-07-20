# G7 measurement metric aggregation helpers (ASCII only, PS 5.1 safe).

function Get-G7MeanMinMax {
    param(
        [Parameter(Mandatory=$true)][object[]]$Values
    )

    $numbers = @($Values | Where-Object { $null -ne $_ } | ForEach-Object { [double]$_ })
    if ($numbers.Count -eq 0) {
        return [pscustomobject]@{ mean = 0.0; min = 0.0; max = 0.0 }
    }
    return [pscustomobject]@{
        mean = [math]::Round(($numbers | Measure-Object -Average).Average, 6)
        min = [math]::Round(($numbers | Measure-Object -Minimum).Minimum, 6)
        max = [math]::Round(($numbers | Measure-Object -Maximum).Maximum, 6)
    }
}

function ConvertFrom-G7ServerStderrLines {
    param(
        [Parameter(Mandatory=$true)][object[]]$Lines
    )

    $serverRunsAll = @()
    $serverBlock = $null
    foreach ($line in @($Lines)) {
        if ($line -match "prompt start") {
            if ($null -ne $serverBlock -and $serverBlock.generated_tokens -gt 0) {
                $serverRunsAll += $serverBlock
            }
            $serverBlock = [pscustomobject]@{
                request_index = $serverRunsAll.Count + 1
                generated_tokens = 0
                server_decode_seconds = 0.0
                server_decode_raw_generated_tokens = 0
                server_decode_raw_seconds = 0.0
                server_chunk_tokens_per_second = 0.0
                server_avg_tokens_per_second = 0.0
                server_rounded_generated_tokens = 0
                server_rounded_decode_seconds = 0.0
                finish_reason = ""
                server_total_seconds = 0.0
                server_prefill_ttft_seconds = 0.0
            }
            continue
        }
        if ($null -eq $serverBlock) { continue }

        if ($line -match "result=progress final=0 gen=(\d+) decode_elapsed_seconds=([0-9.eE+-]+)") {
            $serverBlock.server_decode_raw_generated_tokens = [int]$Matches[1]
            $serverBlock.server_decode_raw_seconds = [double]::Parse(
                $Matches[2], [Globalization.CultureInfo]::InvariantCulture)
            $serverBlock.generated_tokens = $serverBlock.server_decode_raw_generated_tokens
            $serverBlock.server_decode_seconds = $serverBlock.server_decode_raw_seconds
            continue
        }
        if ($line -match "result=summary final=1 generated_tokens=(\d+) decode_elapsed_seconds=([0-9.eE+-]+) finish=([^ ]+)") {
            $serverBlock.server_decode_raw_generated_tokens = [int]$Matches[1]
            $serverBlock.server_decode_raw_seconds = [double]::Parse(
                $Matches[2], [Globalization.CultureInfo]::InvariantCulture)
            $serverBlock.generated_tokens = $serverBlock.server_decode_raw_generated_tokens
            $serverBlock.server_decode_seconds = $serverBlock.server_decode_raw_seconds
            $serverBlock.finish_reason = $Matches[3]
            continue
        }
        if ($line -match "gen=(\d+) decoding chunk=([0-9.]+) t/s avg=([0-9.]+) t/s ([0-9.]+)s") {
            $serverBlock.server_rounded_generated_tokens = [int]$Matches[1]
            $serverBlock.server_chunk_tokens_per_second = [double]$Matches[2]
            $serverBlock.server_avg_tokens_per_second = [double]$Matches[3]
            $serverBlock.server_rounded_decode_seconds = [double]$Matches[4]
            if ($serverBlock.server_decode_raw_generated_tokens -le 0) {
                $serverBlock.generated_tokens = $serverBlock.server_rounded_generated_tokens
                $serverBlock.server_decode_seconds = $serverBlock.server_rounded_decode_seconds
            }
        }
        if ($line -match "gen=(\d+) finish=([^ ]+) ([0-9.]+)s") {
            if ($serverBlock.server_decode_raw_generated_tokens -le 0) {
                $serverBlock.generated_tokens = [int]$Matches[1]
            }
            $serverBlock.finish_reason = $Matches[2]
            $serverBlock.server_total_seconds = [double]$Matches[3]
            $serverBlock.server_prefill_ttft_seconds =
                [math]::Max(0.0, $serverBlock.server_total_seconds - $serverBlock.server_decode_seconds)
        }
    }
    if ($null -ne $serverBlock -and $serverBlock.generated_tokens -gt 0) {
        $serverRunsAll += $serverBlock
    }
    return @($serverRunsAll)
}

function Invoke-G7MeasurementAggregation {
    param(
        [Parameter(Mandatory=$true)][object[]]$Results,
        [Parameter(Mandatory=$true)][object[]]$ServerRunsAll,
        [Parameter(Mandatory=$true)][int]$Repeats,
        [Parameter(Mandatory=$true)][bool]$Warmup,
        [double]$ParsedTpsRelativeTolerance = 0.025
    )

    $clientWallTps = @()
    foreach ($result in @($Results)) {
        $seconds = [double]$result.seconds
        $tokens = [double]$result.completion_tokens
        if ($seconds -gt 0.0 -and $tokens -gt 0.0) {
            $clientWallTps += [math]::Round($tokens / $seconds, 6)
        }
    }
    $clientStats = Get-G7MeanMinMax -Values $clientWallTps

    $nonWarmupRuns = @($ServerRunsAll)
    if ($Warmup -and $nonWarmupRuns.Count -gt 0) {
        $nonWarmupRuns = @($nonWarmupRuns | Select-Object -Skip 1)
    }
    $serverRuns = @($nonWarmupRuns)
    $samplesUsed = $serverRuns.Count
    $valid = $true
    $invalidReason = ""
    if ($samplesUsed -ne $Repeats) {
        $valid = $false
        $invalidReason = "server decode samples_used=$samplesUsed expected_repeats=$Repeats excluding_declared_warmup=$Warmup"
    }

    $decodeTps = @()
    $parsedTps = @()
    $maxRelativeDelta = 0.0
    foreach ($run in $serverRuns) {
        $tokens = [double]$run.generated_tokens
        $seconds = [double]$run.server_decode_seconds
        if ($run.PSObject.Properties.Name -contains "server_decode_raw_generated_tokens" -and
            [double]$run.server_decode_raw_generated_tokens -gt 0.0) {
            $tokens = [double]$run.server_decode_raw_generated_tokens
        }
        if ($run.PSObject.Properties.Name -contains "server_decode_raw_seconds" -and
            [double]$run.server_decode_raw_seconds -gt 0.0) {
            $seconds = [double]$run.server_decode_raw_seconds
        }
        if ($tokens -gt 0.0 -and $seconds -gt 0.0) {
            $computed = $tokens / $seconds
            $run | Add-Member -NotePropertyName "server_decode_tokens_per_second" `
                -NotePropertyValue ([math]::Round($computed, 6)) -Force
            $decodeTps += $computed
            $parsed = [double]$run.server_avg_tokens_per_second
            if ($parsed -gt 0.0) {
                $parsedTps += $parsed
                $denom = [math]::Max([math]::Abs($computed), 0.000001)
                $relativeDelta = [math]::Abs($computed - $parsed) / $denom
                if ($relativeDelta -gt $maxRelativeDelta) {
                    $maxRelativeDelta = $relativeDelta
                }
            }
        }
    }
    if ($valid -and $decodeTps.Count -ne $Repeats) {
        $valid = $false
        $invalidReason = "server decode usable_samples=$($decodeTps.Count) expected_repeats=$Repeats"
    }
    $parsedCrossCheckOk = ($maxRelativeDelta -le $ParsedTpsRelativeTolerance)
    if ($valid -and -not $parsedCrossCheckOk) {
        $valid = $false
        $invalidReason = "server parsed decode t/s cross-check exceeded tolerance max_relative_delta=$([math]::Round($maxRelativeDelta, 6)) tolerance=$ParsedTpsRelativeTolerance"
    }

    $decodeStats = Get-G7MeanMinMax -Values $decodeTps
    $parsedStats = Get-G7MeanMinMax -Values $parsedTps
    $prefillTtft = @($serverRuns | ForEach-Object { [double]$_.server_prefill_ttft_seconds } | Where-Object { $_ -gt 0.0 })
    $prefillStats = Get-G7MeanMinMax -Values $prefillTtft

    return [pscustomobject]@{
        valid = $valid
        status = $(if ($valid) { "VALID" } else { "INVALID" })
        invalid_reason = $invalidReason
        samples_used = $samplesUsed
        expected_samples = $Repeats
        warmup_excluded = $Warmup
        server_runs = $serverRuns
        decode_tps = $decodeStats.mean
        server_decode_mean_tokens_per_second = $decodeStats.mean
        server_decode_min_tokens_per_second = $decodeStats.min
        server_decode_max_tokens_per_second = $decodeStats.max
        server_parsed_decode_mean_tokens_per_second = $parsedStats.mean
        server_parsed_decode_tps_cross_check_ok = $parsedCrossCheckOk
        server_parsed_decode_tps_max_relative_delta = [math]::Round($maxRelativeDelta, 6)
        server_parsed_decode_tps_relative_tolerance = $ParsedTpsRelativeTolerance
        server_prefill_ttft_mean_seconds = $prefillStats.mean
        client_wall_tps = $clientStats.mean
        client_wall_min_tokens_per_second = $clientStats.min
        client_wall_max_tokens_per_second = $clientStats.max
    }
}
