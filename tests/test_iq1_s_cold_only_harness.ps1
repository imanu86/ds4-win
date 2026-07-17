$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$harness = Join-Path $root "g7_measure.ps1"
$receiptHelper = Join-Path $root "write_verified_file_receipt_v2.ps1"

foreach ($path in @($harness, $receiptHelper)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "IQ1_S cold-only required file missing: $path"
    }
}

$tokens = $null
$errors = $null
[Management.Automation.Language.Parser]::ParseFile(
    $harness, [ref]$tokens, [ref]$errors) | Out-Null
if ($errors -and $errors.Count -gt 0) {
    throw "IQ1_S cold-only harness AST parse failed: $($errors[0].Message)"
}

$harnessText = Get-Content -LiteralPath $harness -Raw
foreach ($needle in @(
    '[switch]$Iq1SColdOnly',
    'DS4_IQ1_S_COLD_ONLY',
    '$env:DS4_IQ1_S_COLD_ONLY = "1"',
    'Remove-Item Env:\DS4_IQ1_S_COLD_ONLY',
    'Iq1SColdOnly requires Iq1SMixedColdOne',
    'Iq1SColdOnly requires Iq1SExpertSidecar',
    'Iq1SColdOnly requires ExpertTiering enforce',
    'Iq1SColdOnly is incompatible with Iq1SMixedGpuPlan',
    'iq1_s_cold_only_requested',
    'iq1_s_cold_only_substitutions',
    'iq1_s_cold_only_fallback_all_main',
    'IQ1_S cold-only runtime invariants failed')) {
    if ($harnessText -notmatch [regex]::Escape($needle)) {
        throw "IQ1_S cold-only harness contract missing: $needle"
    }
}

$cudaText = Get-Content -LiteralPath (Join-Path $root "ds4_cuda.cu") -Raw
foreach ($needle in @(
    'cuda_iq1_s_ram_cache_probe',
    'cuda_iq1_classify_main_residency',
    'CUDA_IQ1_MAIN_SSD_COLD',
    'fallback_all_main',
    '[iq1-cold-only] result=summary',
    'DS4_IQ1_S_COLD_ONLY')) {
    if ($cudaText -notmatch [regex]::Escape($needle)) {
        throw "IQ1_S cold-only CUDA contract missing: $needle"
    }
}

function ConvertTo-CommandLineArgument {
    param([string]$Value)

    '"' + ($Value -replace '(\\*)"', '$1$1\"') + '"'
}

function Invoke-HarnessShouldFail {
    param(
        [string]$Name,
        [string[]]$ExtraArgs,
        [string]$Pattern
    )

    $argList = @(
        "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", $harness
    ) + $ExtraArgs
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = "powershell.exe"
    $startInfo.Arguments = ($argList | ForEach-Object {
        ConvertTo-CommandLineArgument ([string]$_)
    }) -join " "
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($startInfo)
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    $output = $stdoutTask.Result + "`n" + $stderrTask.Result
    if ($process.ExitCode -eq 0) {
        throw "$Name unexpectedly succeeded"
    }
    if ($output -notmatch [regex]::Escape($Pattern)) {
        throw "$Name failed with unexpected output: $output"
    }
}

Invoke-HarnessShouldFail `
    -Name "cold-only without mixed cold" `
    -ExtraArgs @("-Iq1SColdOnly") `
    -Pattern "Iq1SColdOnly requires Iq1SMixedColdOne"

Invoke-HarnessShouldFail `
    -Name "cold-only without sidecar" `
    -ExtraArgs @("-Iq1SColdOnly", "-Iq1SMixedColdOne") `
    -Pattern "Iq1SColdOnly requires Iq1SExpertSidecar"

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) (
    "ds4_iq1_s_cold_only_test_" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
try {
    $sidecar = Join-Path $tempRoot "sidecar.iq1s"
    [IO.File]::WriteAllText($sidecar, "sidecar-test", [Text.Encoding]::ASCII)
    $sidecarHash = (Get-FileHash -LiteralPath $sidecar -Algorithm SHA256).Hash.ToLowerInvariant()
    $sidecarBytes = [UInt64](Get-Item -LiteralPath $sidecar).Length
    & $receiptHelper `
        -Path $sidecar `
        -ReceiptPath "$sidecar.receipt.json" `
        -ExpectedSHA256 $sidecarHash `
        -ExpectedBytes $sidecarBytes `
        -Metadata @{
            source = "synthetic-iq1-s-cold-only-test"
            quantization_layout = "synthetic"
            imatrix_provenance = "synthetic"
        } | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "IQ1_S cold-only synthetic sidecar receipt creation failed"
    }

    $sidecarArgs = @(
        "-Iq1SExpertSidecar", $sidecar,
        "-ExpectedIq1SExpertSidecarSHA256", $sidecarHash,
        "-ExpectedIq1SExpertSidecarBytes", ([string]$sidecarBytes)
    )

    Invoke-HarnessShouldFail `
        -Name "cold-only without enforce" `
        -ExtraArgs ($sidecarArgs + @("-Iq1SColdOnly", "-Iq1SMixedColdOne")) `
        -Pattern "Iq1SColdOnly requires ExpertTiering enforce"

    Invoke-HarnessShouldFail `
        -Name "cold-only with gpu plan" `
        -ExtraArgs ($sidecarArgs + @(
            "-Iq1SColdOnly", "-Iq1SMixedColdOne", "-Iq1SMixedGpuPlan",
            "-ExpertTiering", "enforce")) `
        -Pattern "Iq1SColdOnly is incompatible with Iq1SMixedGpuPlan"
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "test_iq1_s_cold_only_harness.ps1: PASS"
