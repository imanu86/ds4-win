# Lightweight model/IQ1 suite receipt test (PowerShell 5.1, ASCII).
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$fileHelper = Join-Path $root "write_verified_file_receipt_v2.ps1"
$suiteHelper = Join-Path $root "g7_suite_receipt.ps1"
$g7Harness = Join-Path $root "g7_measure.ps1"
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) (
    "ds4_suite_receipt_test_" + [Guid]::NewGuid().ToString("n"))

function Get-TestSHA256([string]$Path) {
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Write-TestJsonNoBom {
    param(
        [Parameter(Mandatory=$true)][object]$Value,
        [Parameter(Mandatory=$true)][string]$Path
    )
    $json = $Value | ConvertTo-Json -Depth 12
    $utf8NoBom = New-Object Text.UTF8Encoding $false
    [IO.File]::WriteAllText($Path, $json + [Environment]::NewLine, $utf8NoBom)
}

function Invoke-TestShouldFail {
    param(
        [Parameter(Mandatory=$true)][object[]]$Args,
        [Parameter(Mandatory=$true)][string]$Pattern,
        [Parameter(Mandatory=$true)][string]$Name
    )
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = & powershell.exe @Args 2>&1 | Out-String
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldPreference
    }
    if ($exitCode -eq 0) {
        throw "$Name unexpectedly succeeded"
    }
    if ($output -notmatch $Pattern) {
        throw "$Name failed with unexpected output: $output"
    }
}

function New-G7NegativeArgs {
    param(
        [Parameter(Mandatory=$true)][string]$Tag,
        [Parameter(Mandatory=$true)][string]$SuitePath,
        [Parameter(Mandatory=$true)][string]$SuiteSHA256,
        [string]$GateKind = "structural-safety"
    )
    @(
        "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", $g7Harness,
        "-Tag", $Tag,
        "-MaxTokens", "1",
        "-TimeoutSec", "1",
        "-Prompt", "suite-test",
        "-ModelPath", $model,
        "-ExpectedModelSHA256", $modelHash,
        "-Iq1SExpertSidecar", $sidecar,
        "-ExpectedIq1SExpertSidecarSHA256", $sidecarHash,
        "-ExpectedIq1SExpertSidecarBytes", ([string]$sidecarBytes),
        "-ModelIq1SuiteReceiptPath", $SuitePath,
        "-ExpectedModelIq1SuiteReceiptSHA256", $SuiteSHA256,
        "-ReuseVerifiedSuiteReceipt",
        "-GateKind", $GateKind,
        "-SkipMemoryPreflight",
        "-SkipSystemQuiescencePreflight",
        "-QuiescenceCooldownSec", "0"
    )
}

try {
    New-Item -ItemType Directory -Path $tempRoot | Out-Null
    $model = Join-Path $tempRoot "model.gguf"
    $sidecar = Join-Path $tempRoot "model.iq1s"
    [IO.File]::WriteAllText($model, "model-test", [Text.Encoding]::ASCII)
    [IO.File]::WriteAllText($sidecar, "sidecar-test", [Text.Encoding]::ASCII)

    $modelHash = Get-TestSHA256 $model
    $sidecarHash = Get-TestSHA256 $sidecar
    $sidecarBytes = [UInt64](Get-Item -LiteralPath $sidecar).Length
    $modelReceipt = "$model.receipt.json"
    $sidecarReceipt = "$sidecar.receipt.json"
    $suiteReceipt = Join-Path $tempRoot "suite.receipt.json"

    & $fileHelper `
        -Path $model -ReceiptPath $modelReceipt `
        -ExpectedSHA256 $modelHash `
        -ExpectedBytes ([UInt64](Get-Item -LiteralPath $model).Length) `
        -Metadata @{ test_marker = "suite-model" } | Out-Null
    & $fileHelper `
        -Path $sidecar -ReceiptPath $sidecarReceipt `
        -ExpectedSHA256 $sidecarHash -ExpectedBytes $sidecarBytes `
        -Metadata @{
            source = "suite-test"
            quantization_layout = "iq1_s-test"
            imatrix_provenance = "suite-test"
        } | Out-Null

    $created = & $suiteHelper -ModelPath $model `
        -Iq1SExpertSidecar $sidecar -OutPath $suiteReceipt `
        -ModelReceiptPath $modelReceipt -Iq1SReceiptPath $sidecarReceipt `
        -ExpectedModelSHA256 $modelHash `
        -ExpectedIq1SExpertSidecarSHA256 $sidecarHash `
        -ExpectedIq1SExpertSidecarBytes $sidecarBytes | ConvertFrom-Json

    if (-not (Test-Path -LiteralPath $suiteReceipt -PathType Leaf)) {
        throw "suite receipt was not written"
    }
    $suiteHash = Get-TestSHA256 $suiteReceipt
    $receipt = Get-Content -LiteralPath $suiteReceipt -Raw | ConvertFrom-Json
    if ([string]$receipt.schema -ne "g7_model_iq1_suite_receipt_v1" -or
        [string]$receipt.status -ne "verified" -or
        [string]$receipt.purpose -ne "model_iq1_provenance_reuse" -or
        -not [bool]$receipt.immutable -or
        [string]$receipt.hash_method -ne "locked_stream_sha256" -or
        -not [bool]$receipt.full_hash_verified -or
        [string]$receipt.model.sha256 -ne $modelHash -or
        [string]$receipt.model.hash_method -ne "locked_stream_sha256" -or
        -not [bool]$receipt.model.full_hash_verified -or
        [string]$receipt.iq1_s_sidecar.sha256 -ne $sidecarHash -or
        [string]$receipt.iq1_s_sidecar.hash_method -ne
            "locked_stream_sha256" -or
        -not [bool]$receipt.iq1_s_sidecar.full_hash_verified -or
        [string]$receipt.model.receipt_sha256 -ne
            (Get-TestSHA256 $modelReceipt) -or
        [string]$receipt.iq1_s_sidecar.receipt_sha256 -ne
            (Get-TestSHA256 $sidecarReceipt) -or
        [string]$created.suite_receipt_sha256 -ne $suiteHash) {
        throw "suite receipt content mismatch"
    }

    Invoke-TestShouldFail -Name "wrong suite SHA" `
        -Args (New-G7NegativeArgs -Tag "suite_wrong_sha" `
            -SuitePath $suiteReceipt `
            -SuiteSHA256 ("f" * 64)) `
        -Pattern "Model/IQ1 suite receipt SHA-256 mismatch"

    $badChildSuite = Join-Path $tempRoot "suite.child-mismatch.json"
    $badChild = Get-Content -LiteralPath $suiteReceipt -Raw | ConvertFrom-Json
    $badChild.model.sha256 = "a" * 64
    Write-TestJsonNoBom -Value $badChild -Path $badChildSuite
    Invoke-TestShouldFail -Name "child mismatch" `
        -Args (New-G7NegativeArgs -Tag "suite_child_mismatch" `
            -SuitePath $badChildSuite `
            -SuiteSHA256 (Get-TestSHA256 $badChildSuite)) `
        -Pattern "Model suite receipt binding mismatch"

    Invoke-TestShouldFail -Name "sidecar bytes mismatch" `
        -Args @(
            "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-File", $suiteHelper,
            "-ModelPath", $model,
            "-Iq1SExpertSidecar", $sidecar,
            "-OutPath", (Join-Path $tempRoot "suite.bytes-mismatch.json"),
            "-ModelReceiptPath", $modelReceipt,
            "-Iq1SReceiptPath", $sidecarReceipt,
            "-ExpectedModelSHA256", $modelHash,
            "-ExpectedIq1SExpertSidecarSHA256", $sidecarHash,
            "-ExpectedIq1SExpertSidecarBytes",
                ([string]([UInt64]$sidecarBytes + [UInt64]1))) `
        -Pattern "IQ1_S sidecar verified receipt identity mismatch"

    Invoke-TestShouldFail -Name "benchmark no external locks" `
        -Args (New-G7NegativeArgs -Tag "suite_no_external_locks" `
            -SuitePath $suiteReceipt -SuiteSHA256 $suiteHash `
            -GateKind "benchmark") `
        -Pattern "Benchmark suite receipt reuse requires active parent-held deny-write/delete locks"

    Invoke-TestShouldFail -Name "overwrite without Force" `
        -Args @(
            "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-File", $suiteHelper,
            "-ModelPath", $model,
            "-Iq1SExpertSidecar", $sidecar,
            "-OutPath", $suiteReceipt,
            "-ModelReceiptPath", $modelReceipt,
            "-Iq1SReceiptPath", $sidecarReceipt,
            "-ExpectedModelSHA256", $modelHash,
            "-ExpectedIq1SExpertSidecarSHA256", $sidecarHash,
            "-ExpectedIq1SExpertSidecarBytes", ([string]$sidecarBytes)) `
        -Pattern "Suite receipt already exists"

    & $suiteHelper `
        -ModelPath $model -Iq1SExpertSidecar $sidecar `
        -OutPath $suiteReceipt -ModelReceiptPath $modelReceipt `
        -Iq1SReceiptPath $sidecarReceipt `
        -ExpectedModelSHA256 $modelHash `
        -ExpectedIq1SExpertSidecarSHA256 $sidecarHash `
        -ExpectedIq1SExpertSidecarBytes $sidecarBytes -Force | Out-Null

    Write-Host "model/IQ1 suite receipt lightweight test PASS"
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
