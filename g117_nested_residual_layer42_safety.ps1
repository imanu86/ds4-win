# G117 full-router nested-residual exactness safety (PowerShell 5.1, ASCII).
param(
    [ValidateRange(1, 64)][int]$MaxTokens = 8,
    [ValidateRange(1, 60)][int]$BudgetGB = 28,
    [ValidatePattern('^[A-Za-z0-9_-]+$')][string]$Tag = "g117_layer42_exact",
    [ValidateRange(600, 7200)][int]$TimeoutSec = 1800,
    [string]$SidecarPath = "C:\ds4-models\ds4-nested-residual-layer42.ds4nr",
    [UInt64]$ExpectedSidecarBytes = 805306804,
    [ValidatePattern('^[0-9a-fA-F]{64}$')]
    [string]$ExpectedSidecarSHA256 = "f0d18fcc7491a12ef2a8d75f56472ee88f723aee4f095bdabc5a2f6d133d8799",
    [ValidatePattern('^[0-9a-fA-F]{64}$')]
    [string]$ExpectedPayloadSHA256 = "854eb847319c279562cf67113724d510e5365a4f41dbbad8cd4a412b3f71b2e1",
    [string]$SidecarReceiptPath = "C:\ds4-models\ds4-nested-residual-layer42.receipt.json"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$harness = Join-Path $root "g7_measure.ps1"
$runs = Join-Path $root "g7_runs"
$model = "C:\ds4-models\ds4-2bit.gguf"
$modelSHA = "efc7ed607ff27076e3e501fc3fefefa33c0ed8cf1eff483a2b7fdc0c2e616668"
$sidecar = [IO.Path]::GetFullPath($SidecarPath)
$sidecarBytes = $ExpectedSidecarBytes
$sidecarSHA = $ExpectedSidecarSHA256.ToLowerInvariant()
$payloadSHA = $ExpectedPayloadSHA256.ToLowerInvariant()
$prompt = "Hi"
$controlTag = $Tag + "_control"
$candidateTag = $Tag + "_candidate"
$receiptPath = Join-Path $runs ("g7_" + $Tag + "_receipt.json")
$sidecarReceipt = [IO.Path]::GetFullPath($SidecarReceiptPath)

foreach ($path in @($harness, $model, "$model.receipt.json", $sidecar,
                     $sidecarReceipt)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "G117 required file missing: $path"
    }
}

$sidecarInfo = Get-Item -LiteralPath $sidecar
if ([UInt64]$sidecarInfo.Length -ne $sidecarBytes) {
    throw "G117 sidecar size mismatch"
}
$sidecarLock = [IO.File]::Open(
    $sidecar, [IO.FileMode]::Open, [IO.FileAccess]::Read,
    [IO.FileShare]::Read)
try {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $observedSidecarSHA = [BitConverter]::ToString(
            $sha.ComputeHash($sidecarLock)).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
    if ($observedSidecarSHA -ne $sidecarSHA) {
        throw "G117 full sidecar SHA-256 mismatch"
    }
    $sidecarLock.Position = 0

    $common = @(
        "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", $harness, "-GateKind", "structural-safety",
        "-ModelPath", $model, "-ExpectedModelSHA256", $modelSHA,
        "-ReuseVerifiedModelReceipt", "-Prompt", $prompt,
        "-MaxTokens", ([string]$MaxTokens), "-Repeats", "1",
        "-Context", "256", "-PrefillChunk", "256",
        "-ForceOpenRouter",
        "-BudgetGB", ([string]$BudgetGB), "-ReserveMB", "1024",
        "-DisableQ8F16Cache", "-EmbedRowStaging",
        "-RuntimeMinimumAvailableGiB", "1",
        "-RuntimeMaximumDiskQueueLength", "8",
        "-RuntimeContaminationSamples", "3",
        "-QuiescenceCooldownSec", "10",
        "-TimeoutSec", ([string]$TimeoutSec)
    )

    Write-Host "[g117] phase=control router=open representation=primary-iq2"
    & powershell.exe @common -Tag $controlTag
    if ($LASTEXITCODE -ne 0) { throw "G117 control failed" }
    $controlPath = Join-Path $runs ("g7_" + $controlTag + "_result.json")
    $control = Get-Content -LiteralPath $controlPath -Raw | ConvertFrom-Json
    $controlSample = @($control.results)[0]
    if (-not $controlSample.content_sha256) {
        throw "G117 control content hash missing"
    }

    Write-Host "[g117] phase=candidate router=open representation=base-plus-exact-residual"
    & powershell.exe @common -Tag $candidateTag `
        -ExpectedContentSHA256 ([string]$controlSample.content_sha256) `
        -NestedResidualSidecar $sidecar `
        -ExpectedNestedResidualSidecarSHA256 $sidecarSHA `
        -ExpectedNestedResidualSourceSHA256 $modelSHA `
        -ExpectedNestedResidualPayloadSHA256 $payloadSHA `
        -NestedResidualVerifyReconstruction
    if ($LASTEXITCODE -ne 0) { throw "G117 candidate failed" }

    $candidatePath = Join-Path $runs ("g7_" + $candidateTag + "_result.json")
    $stderrPath = Join-Path $runs ("g7_" + $candidateTag + "_stderr.log")
    $candidate = Get-Content -LiteralPath $candidatePath -Raw | ConvertFrom-Json
    $candidateSample = @($candidate.results)[0]
    $stderr = Get-Content -LiteralPath $stderrPath -Raw
    $summary = [regex]::Match($stderr,
        '\[nested-residual\] result=summary router=open router_calls=(\d+) cache_hits=(\d+) cache_misses=(\d+) residual_preads=(\d+) residual_bytes=(\d+) reconstructed=(\d+) mismatches=(\d+) h2d_bytes=(\d+) failures=(\d+)')
    if (-not $summary.Success) {
        throw "G117 nested residual summary missing"
    }
    $routerCalls = [UInt64]$summary.Groups[1].Value
    $cacheMisses = [UInt64]$summary.Groups[3].Value
    $preads = [UInt64]$summary.Groups[4].Value
    $residualBytes = [UInt64]$summary.Groups[5].Value
    $reconstructed = [UInt64]$summary.Groups[6].Value
    $mismatches = [UInt64]$summary.Groups[7].Value
    $failures = [UInt64]$summary.Groups[9].Value
    if ($routerCalls -eq 0 -or $cacheMisses -eq 0 -or
        $preads -ne $cacheMisses -or $reconstructed -ne $cacheMisses -or
        $residualBytes -ne $preads * [UInt64]3145728 -or
        $mismatches -ne 0 -or $failures -ne 0 -or
        [string]$candidateSample.content_sha256 -ne
            [string]$controlSample.content_sha256) {
        throw "G117 exact transport contract mismatch"
    }
    foreach ($forbidden in @(
            "REAP mask applied", "[q1-0-sidecar]", "[iq1-s-sidecar]",
            "refused source fallback", "refused whole-tensor fallback")) {
        if ($stderr -match [regex]::Escape($forbidden)) {
            throw "G117 forbidden runtime marker observed: $forbidden"
        }
    }

    $receipt = [ordered]@{
        schema = "g117_nested_residual_safety_v1"
        status = "pass"
        claim_scope = "n1_structural_exactness_only"
        router = "open"
        mask = "off"
        source_model_sha256 = $modelSHA
        sidecar_sha256 = $sidecarSHA
        sidecar = $sidecar
        payload_sha256 = $payloadSHA
        host_window_budget_gib = $BudgetGB
        max_tokens = $MaxTokens
        output_sha256 = [string]$candidateSample.content_sha256
        control_result = $controlPath
        candidate_result = $candidatePath
        router_calls = $routerCalls
        cache_misses = $cacheMisses
        residual_preads = $preads
        residual_bytes = $residualBytes
        reconstruction_mismatches = $mismatches
        failures = $failures
        timing_claim_valid = $false
    }
    $receipt | ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath $receiptPath -Encoding UTF8
    Write-Host ("[g117] PASS exact output_sha=" +
        $candidateSample.content_sha256 + " residual_preads=" + $preads)
} finally {
    $sidecarLock.Dispose()
}
