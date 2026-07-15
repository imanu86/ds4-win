# G35 expert tiering enforce A/B (PowerShell 5.1, ASCII)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$harness = Join-Path $root "g7_measure.ps1"
$outdir = Join-Path $root "g7_runs"
$model = "C:\ds4-models\ds4-2bit.gguf"
$expected = "fda564ba3f7a0f028106d468420f674898ed99ac5bf2765ac9586206e39d73c5"

function Invoke-G35Run {
    param(
        [Parameter(Mandatory=$true)][string]$Tag,
        [Parameter(Mandatory=$true)][ValidateSet("off", "enforce")][string]$ExpertTiering
    )

    $args = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $harness,
        "-MaxTokens", "12", "-Repeats", "3", "-Warmup",
        "-Tag", $Tag, "-Prompt", "Hi", "-Context", "256",
        "-BudgetGB", "2", "-ReserveMB", "4096", "-RuntimeReserveMB", "128",
        "-DynamicArenaGiB", "8",
        "-ExpertCacheN", "336", "-ExpertCacheReserveGB", "0.5",
        "-ExpertCachePolicy", "lru", "-DisableQ8F16Cache",
        "-EmbedRowStaging", "-GpuResidentRoutes",
        "-ExpertTiering", $ExpertTiering,
        "-ExpectedContentSHA256", $expected,
        "-ExpectedWarmupContentSHA256", $expected,
        "-ModelPath", $model
    )

    Write-Host ("[g35] start tag=" + $Tag + " expert_tiering=" + $ExpertTiering)
    & powershell.exe @args | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) {
        throw "G35 run failed: $Tag (exit=$LASTEXITCODE)"
    }

    $resultPath = Join-Path $outdir ("g7_" + $Tag + "_result.json")
    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        throw "G35 result missing: $resultPath"
    }
    $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    if (-not $result.outputs_identical -or $result.expected_content_sha256 -ne $expected) {
        throw "G35 exact output mismatch: tag=$Tag"
    }
    if ($null -eq $result.warmup_result -or $result.warmup_result.content_sha256 -ne $expected) {
        throw "G35 exact warmup mismatch: tag=$Tag"
    }
    if ($result.dynamic_arena_gib_requested -ne 8.0 -or
        $result.expert_cache_requested -ne 336 -or
        $result.expert_cache_policy -ne "lru" -or
        -not $result.gpu_resident_routes_requested -or
        -not $result.q8_f16_cache_disabled) {
        throw "G35 run configuration mismatch: tag=$Tag"
    }

    $envNames = @($result.effective_ds4_environment.PSObject.Properties | ForEach-Object { $_.Name })
    if ($ExpertTiering -eq "off") {
        if ($envNames -contains "DS4_EXPERT_TIERING") {
            throw "G35 control leaked DS4_EXPERT_TIERING: tag=$Tag"
        }
        if ($result.expert_tiering.final_line_count -ne 0 -or
            $result.expert_tiering.control_line_count -ne 0) {
            throw "G35 control emitted expert tiering telemetry: tag=$Tag"
        }
    } else {
        if (-not ($envNames -contains "DS4_EXPERT_TIERING") -or
            $result.effective_ds4_environment.DS4_EXPERT_TIERING -ne "enforce") {
            throw "G35 enforce did not set DS4_EXPERT_TIERING: tag=$Tag"
        }
        if (-not $result.expert_tiering.final_observed -or
            $result.expert_tiering.final_line_count -ne 1 -or
            $result.expert_tiering.control_line_count -ne 0 -or
            $result.expert_tiering.mode -ne "enforce" -or
            $result.expert_tiering.calls -le 0 -or
            $result.expert_tiering.selected -ne ($result.expert_tiering.calls * 6) -or
            $result.expert_tiering.failures -ne 0 -or
            $result.expert_tiering.cold_to_vram -ne 0 -or
            $result.expert_tiering.cold_to_ram -le 0 -or
            $result.expert_tiering.transient -le 0 -or
            $result.expert_tiering.vram_promotions -le 0) {
            throw "G35 enforce expert tiering telemetry mismatch: tag=$Tag"
        }
    }

    [pscustomobject]@{
        tag = $Tag
        expert_tiering = $ExpertTiering
        result_path = $resultPath
        mean_tokens_per_second = $result.mean_tokens_per_second
        server_decode_mean_tokens_per_second = $result.server_decode_mean_tokens_per_second
        warmup_seconds = $result.warmup_seconds
        load_seconds = $result.load_seconds
        calls = $result.expert_tiering.calls
        selected = $result.expert_tiering.selected
        ram_hits = $result.expert_tiering.ram_hits
        vram_hits = $result.expert_tiering.vram_hits
        cold = $result.expert_tiering.cold
        ssd_bytes = $result.expert_tiering.ssd_bytes
        ram_h2d_bytes = $result.expert_tiering.ram_h2d_bytes
        states_vram = $result.expert_tiering.states_vram
        mass_sum = $result.expert_tiering.mass_sum
        lfru_top = $result.expert_tiering.lfru_top
    }
}

$runs = @()
$runs += Invoke-G35Run -Tag "g35_control_off_a" -ExpertTiering "off"
$runs += Invoke-G35Run -Tag "g35_enforce_a" -ExpertTiering "enforce"
$runs += Invoke-G35Run -Tag "g35_enforce_b" -ExpertTiering "enforce"
$runs += Invoke-G35Run -Tag "g35_control_off_b" -ExpertTiering "off"

$controlRuns = @($runs | Where-Object { $_.expert_tiering -eq "off" })
$enforceRuns = @($runs | Where-Object { $_.expert_tiering -eq "enforce" })
if ($controlRuns.Count -ne 2 -or $enforceRuns.Count -ne 2) {
    throw "G35 A/B requires exactly two valid runs per arm"
}

$summary = [pscustomobject]@{
    schema = "g35_tiering_ab_v1"
    model = $model
    expected_content_sha256 = $expected
    expected_warmup_content_sha256 = $expected
    order = @("off", "enforce", "enforce", "off")
    runs = $runs
    control_mean_tokens_per_second = [math]::Round(($controlRuns | Measure-Object -Property mean_tokens_per_second -Average).Average, 6)
    enforce_mean_tokens_per_second = [math]::Round(($enforceRuns | Measure-Object -Property mean_tokens_per_second -Average).Average, 6)
    control_server_decode_mean_tokens_per_second = [math]::Round(($controlRuns | Measure-Object -Property server_decode_mean_tokens_per_second -Average).Average, 6)
    enforce_server_decode_mean_tokens_per_second = [math]::Round(($enforceRuns | Measure-Object -Property server_decode_mean_tokens_per_second -Average).Average, 6)
}

New-Item -ItemType Directory -Force -Path $outdir | Out-Null
$summaryPath = Join-Path $outdir "g35_tiering_ab_result.json"
$summary | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 $summaryPath
Write-Host ("[g35] matrix complete: " + $summaryPath)
