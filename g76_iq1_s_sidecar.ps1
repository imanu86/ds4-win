# G76 IQ1_S routed-expert sidecar safety runner (PowerShell 5.1, ASCII).
param(
    [switch]$StaticCheckOnly,
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$harness = Join-Path $root "g7_measure.ps1"
$buildRunner = Join-Path $root "g7_build.ps1"
$outdir = Join-Path $root "g7_runs"
$model = "C:\ds4-models\ds4-2bit.gguf"
$modelSha256 = "efc7ed607ff27076e3e501fc3fefefa33c0ed8cf1eff483a2b7fdc0c2e616668"
$sidecar = "D:\ds4-models\DeepSeek-V4-Flash-IQ1_S-XL.gguf"
$sidecarBytes = [UInt64]61540805344
$sidecarSha256 = "b049d1eb34c068f19ab007b33c22a7d758b578bf2b10d9276e79654f85d35047"
$tag = "g76_iq1_s_sidecar_safety_n1"
$resultPath = Join-Path $outdir ("g7_" + $tag + "_result.json")
$stderrPath = Join-Path $outdir ("g7_" + $tag + "_stderr.log")
$summaryPath = Join-Path $outdir "g76_iq1_s_sidecar_safety_result.json"

function Assert-G76StaticContract {
    foreach ($path in @($harness, $buildRunner)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "G76 static check failed: missing $path"
        }
    }
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $MyInvocation.ScriptName, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        throw ("G76 runner syntax failed: " +
            (($errors | ForEach-Object { $_.Message }) -join " | "))
    }
    $harnessText = Get-Content -LiteralPath $harness -Raw
    foreach ($needle in @(
            '[string]$Iq1SExpertSidecar',
            'DS4_IQ1_S_EXPERT_SIDECAR',
            'iq1_s_sidecar_expected_sha256')) {
        if ($harnessText -notmatch [regex]::Escape($needle)) {
            throw "G76 harness lacks $needle"
        }
    }
}

Assert-G76StaticContract
if ($StaticCheckOnly) {
    Write-Host "G76 static contract PASS"
    return
}

if (-not (Test-Path -LiteralPath $sidecar -PathType Leaf)) {
    throw "G76 sidecar is not complete yet: $sidecar"
}
$sidecarInfo = Get-Item -LiteralPath $sidecar
if ([UInt64]$sidecarInfo.Length -ne $sidecarBytes) {
    throw "G76 sidecar size mismatch"
}
if (-not $SkipBuild) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $buildRunner
    if ($LASTEXITCODE -ne 0) { throw "G76 provenance build failed" }
}

$prompt = "Say hello in one short sentence."
$args = @(
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $harness,
    "-Tag", $tag,
    "-ModelPath", $model,
    "-ExpectedModelSHA256", $modelSha256,
    "-Iq1SExpertSidecar", $sidecar,
    "-ExpectedIq1SExpertSidecarSHA256", $sidecarSha256,
    "-ExpectedIq1SExpertSidecarBytes", "$sidecarBytes",
    "-Prompt", $prompt,
    "-MaxTokens", "32",
    "-Repeats", "1",
    "-GateKind", "structural-safety",
    "-Context", "256",
    "-BudgetGB", "28",
    "-ReserveMB", "1024",
    "-RuntimeReserveMB", "256",
    "-DisableQ8F16Cache",
    "-EmbedRowStaging",
    "-IoQD", "4",
    "-PrefillWaves",
    "-PrefillWaveForceExperts", "32",
    "-PrefillWaveDoubleBuffer",
    "-OverlapSharedFull",
    "-TimeoutSec", "2400"
)

& powershell.exe @args
if ($LASTEXITCODE -ne 0) { throw "G76 safety harness failed" }
if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $stderrPath -PathType Leaf)) {
    throw "G76 safety artifacts missing"
}

$result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
$stderrText = Get-Content -LiteralPath $stderrPath -Raw
$calls = [UInt64]$result.iq1_s_sidecar_route_calls
$slots = [UInt64]$result.iq1_s_sidecar_route_slots
$selectedLoads = [UInt64]$result.iq1_s_sidecar_selected_loads
$failures = [UInt64]$result.iq1_s_sidecar_failures
$sidecarActualSha256 = [string]$result.iq1_s_sidecar_sha256
$requiredMarkers = @(
    "validated concatenated split GGUF",
    "IQ1_S checkpoint identity validated",
    "IQ1_S routed-expert sidecar validated",
    "CUDA IQ1_S routed-expert sidecar installed"
)
foreach ($marker in $requiredMarkers) {
    if ($stderrText -notmatch [regex]::Escape($marker)) {
        throw "G76 runtime marker missing: $marker"
    }
}
if ($result.server_exit_code -ne 0 -or $result.results.Count -ne 1 -or
    -not $result.iq1_s_sidecar_runtime_observed -or
    $calls -eq 0 -or $slots -lt $calls -or $selectedLoads -ne $calls -or
    $failures -ne 0 -or $result.quality_eligible -or $result.sota_eligible -or
    $sidecarActualSha256 -ne $sidecarSha256) {
    throw "G76 IQ1_S structural safety gate failed"
}
$content = [string]$result.results[0].content
if ([string]::IsNullOrWhiteSpace($content) -or $content.Length -lt 4 -or
    $content -notmatch '[A-Za-z]' -or
    $content -match '(?i)\b(?:nan|inf)\b' -or
    $content -notmatch '(?i)\b(?:hello|hi|greetings|help|assist|today)\b') {
    throw "G76 IQ1_S output health gate failed"
}

$summary = [ordered]@{
    schema = "g76_iq1_s_sidecar_safety_v1"
    measured_utc = [DateTime]::UtcNow.ToString("o")
    status = "structural-safety-pass"
    quality_verdict = "not-claimed-n1"
    model = $model
    sidecar = $sidecar
    sidecar_bytes = $sidecarBytes
    sidecar_sha256 = $sidecarActualSha256
    tag = $tag
    content_sha256 = $result.results[0].content_sha256
    route_calls = $calls
    route_slots = $slots
    selected_loads = $selectedLoads
    failures = $failures
    throughput_tps = $result.results[0].tokens_per_second
    ttft_seconds = $result.server_prefill_ttft_mean_seconds
    note = "n=1 validates transport/kernel/runtime only; no quality or SOTA claim"
}
$summary | ConvertTo-Json -Depth 5 |
    Set-Content -LiteralPath $summaryPath -Encoding UTF8
Write-Host ("G76 IQ1_S safety PASS: calls=" + $calls +
    " slots=" + $slots + " loads=" + $selectedLoads +
    " failures=" + $failures)
