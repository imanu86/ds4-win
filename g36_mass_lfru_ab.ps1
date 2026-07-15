# G36 mass/LFRU slow-clock tier policy A/B (PowerShell 5.1, ASCII)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$harness = Join-Path $root "g7_measure.ps1"
$outdir = Join-Path $root "g7_runs"
$model = "C:\ds4-models\ds4-2bit.gguf"
$expected = "fda564ba3f7a0f028106d468420f674898ed99ac5bf2765ac9586206e39d73c5"
$clockCalls = 430
$replacementBudget = 16
$minFrequency = 3
$hysteresis = 1.25

function Invoke-G36Run {
    param(
        [Parameter(Mandatory=$true)][string]$Tag,
        [Parameter(Mandatory=$true)][ValidateSet("second-touch", "mass-lfru")][string]$Policy
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
        "-ExpertTiering", "enforce", "-ExpertTierPolicy", $Policy,
        "-ExpertTierClockCalls", "$clockCalls",
        "-ExpertTierReplacementBudget", "$replacementBudget",
        "-ExpertTierMinFrequency", "$minFrequency",
        "-ExpertTierHysteresis", $hysteresis.ToString("R", [Globalization.CultureInfo]::InvariantCulture),
        "-ExpectedContentSHA256", $expected,
        "-ExpectedWarmupContentSHA256", $expected,
        "-ModelPath", $model
    )

    Write-Host ("[g36] start tag=" + $Tag + " policy=" + $Policy)
    & powershell.exe @args | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) {
        throw "G36 run failed: $Tag (exit=$LASTEXITCODE)"
    }

    $resultPath = Join-Path $outdir ("g7_" + $Tag + "_result.json")
    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        throw "G36 result missing: $resultPath"
    }
    $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    if (-not $result.outputs_identical -or $result.expected_content_sha256 -ne $expected) {
        throw "G36 exact output mismatch: tag=$Tag"
    }
    if ($null -eq $result.warmup_result -or
        $result.warmup_result.content_sha256 -ne $expected) {
        throw "G36 exact warmup mismatch: tag=$Tag"
    }
    if ($result.dynamic_arena_gib_requested -ne 8.0 -or
        $result.expert_cache_requested -ne 336 -or
        $result.expert_cache_policy -ne "lru" -or
        -not $result.gpu_resident_routes_requested -or
        -not $result.q8_f16_cache_disabled) {
        throw "G36 run configuration mismatch: tag=$Tag"
    }
    $tier = $result.expert_tiering
    if (-not $tier.final_observed -or $tier.final_line_count -ne 1 -or
        $tier.mode -ne "enforce" -or $tier.policy -ne $Policy -or
        $tier.calls -le 0 -or $tier.selected -ne ($tier.calls * 6) -or
        $tier.failures -ne 0 -or $tier.cold_to_vram -ne 0 -or
        $tier.cold_to_ram -le 0 -or $tier.transient -le 0 -or
        $tier.vram_promotions -le 0) {
        throw "G36 tier contract mismatch: tag=$Tag"
    }
    if ($Policy -eq "mass-lfru") {
        if ($tier.clock_calls -ne $clockCalls -or
            $tier.replacement_budget -ne $replacementBudget -or
            $tier.min_frequency -ne $minFrequency -or
            [math]::Abs($tier.hysteresis - $hysteresis) -gt 1.0e-9 -or
            $tier.policy_epochs -le 0) {
            throw "G36 mass-lfru policy telemetry mismatch: tag=$Tag"
        }
    }

    [pscustomobject]@{
        tag = $Tag
        policy = $Policy
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
        build_worktree_dirty = $result.build_manifest_worktree_dirty_at_build_start
        mean_tokens_per_second = $result.mean_tokens_per_second
        server_decode_mean_tokens_per_second = $result.server_decode_mean_tokens_per_second
        warmup_seconds = $result.warmup_seconds
        process_read_bytes = $result.runtime_telemetry.win32_process_read_transfer_delta_bytes
        page_fault_delta = $result.runtime_telemetry.page_fault_delta
        calls = $tier.calls
        cold_to_ram = $tier.cold_to_ram
        vram_hits = $tier.vram_hits
        vram_promotions = $tier.vram_promotions
        vram_demotions = $tier.vram_demotions
        transient = $tier.transient
        ram_h2d_bytes = $tier.ram_h2d_bytes
        states_vram = $tier.states_vram
        policy_epochs = $tier.policy_epochs
        policy_free_promotions = $tier.policy_free_promotions
        policy_replacements = $tier.policy_replacements
        policy_min_frequency_skips = $tier.policy_min_frequency_skips
        policy_budget_skips = $tier.policy_budget_skips
        policy_score_skips = $tier.policy_score_skips
    }
}

$runs = @()
$runs += Invoke-G36Run -Tag "g36_second_touch_a" -Policy "second-touch"
$runs += Invoke-G36Run -Tag "g36_mass_lfru_a" -Policy "mass-lfru"
$runs += Invoke-G36Run -Tag "g36_mass_lfru_b" -Policy "mass-lfru"
$runs += Invoke-G36Run -Tag "g36_second_touch_b" -Policy "second-touch"

$control = @($runs | Where-Object { $_.policy -eq "second-touch" })
$candidate = @($runs | Where-Object { $_.policy -eq "mass-lfru" })
if ($control.Count -ne 2 -or $candidate.Count -ne 2) {
    throw "G36 A/B requires exactly two valid runs per arm"
}
$provenanceFields = @(
    "head", "executable_sha256", "ds4_cuda_sha256", "build_manifest_sha256",
    "build_input_fingerprint_sha256", "harness_sha256", "model",
    "model_bytes", "model_last_write_utc", "build_worktree_dirty"
)
foreach ($field in $provenanceFields) {
    $values = @($runs | ForEach-Object { [string]($_.$field) } | Select-Object -Unique)
    if ($values.Count -ne 1) {
        throw "G36 mixed provenance across runs: field=$field"
    }
}
$controlReplacements = ($control | Measure-Object -Property policy_replacements -Average).Average
$candidateReplacements = ($candidate | Measure-Object -Property policy_replacements -Average).Average
if ($candidateReplacements -ge $controlReplacements) {
    throw "G36 mass-lfru did not reduce physical replacements"
}

$summary = [pscustomobject]@{
    schema = "g36_mass_lfru_ab_v1"
    model = $model
    expected_content_sha256 = $expected
    order = @("second-touch", "mass-lfru", "mass-lfru", "second-touch")
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
        build_worktree_dirty = $runs[0].build_worktree_dirty
    }
    policy = [pscustomobject]@{
        clock_calls = $clockCalls
        replacement_budget = $replacementBudget
        min_frequency = $minFrequency
        hysteresis = $hysteresis
    }
    runs = $runs
    control_mean_tokens_per_second = [math]::Round(($control | Measure-Object -Property mean_tokens_per_second -Average).Average, 6)
    candidate_mean_tokens_per_second = [math]::Round(($candidate | Measure-Object -Property mean_tokens_per_second -Average).Average, 6)
    control_server_decode_mean_tokens_per_second = [math]::Round(($control | Measure-Object -Property server_decode_mean_tokens_per_second -Average).Average, 6)
    candidate_server_decode_mean_tokens_per_second = [math]::Round(($candidate | Measure-Object -Property server_decode_mean_tokens_per_second -Average).Average, 6)
    control_replacements_mean = [math]::Round($controlReplacements, 3)
    candidate_replacements_mean = [math]::Round($candidateReplacements, 3)
}

New-Item -ItemType Directory -Force -Path $outdir | Out-Null
$summaryPath = Join-Path $outdir "g36_mass_lfru_ab_result.json"
$summary | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 $summaryPath
Write-Host ("[g36] matrix complete: " + $summaryPath)
