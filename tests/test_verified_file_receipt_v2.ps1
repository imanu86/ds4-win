# Lightweight verified receipt v2 test (PowerShell 5.1, ASCII).
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$helper = Join-Path $root "write_verified_file_receipt_v2.ps1"
if (-not (Test-Path -LiteralPath $helper -PathType Leaf)) {
    throw "Missing helper: $helper"
}

$dir = Join-Path ([IO.Path]::GetTempPath()) (
    "ds4_receipt_v2_test_" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Force -Path $dir | Out-Null
try {
    $file = Join-Path $dir "sample.bin"
    $receiptPath = "$file.receipt.json"
    [IO.File]::WriteAllBytes($file, [byte[]](0, 1, 2, 3, 4, 250, 255))
    $expectedHash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).
        Hash.ToLowerInvariant()
    & $helper `
        -Path $file `
        -ReceiptPath $receiptPath `
        -ExpectedSHA256 $expectedHash `
        -ExpectedBytes 7 `
        -Metadata @{ test_marker = "receipt-v2-lightweight" } | Out-Null

    if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) {
        throw "Receipt was not written"
    }
    $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
    $info = Get-Item -LiteralPath $file
    foreach ($field in @(
            "status", "path", "bytes", "sha256", "creation_utc_ticks",
            "last_write_utc_ticks", "file_id", "verified_at", "method",
            "verification_method")) {
        if (-not $receipt.PSObject.Properties[$field]) {
            throw "Receipt missing $field"
        }
    }
    if ([string]$receipt.schema -ne "g7_verified_file_receipt_v2" -or
        [string]$receipt.status -ne "verified" -or
        [UInt64]$receipt.bytes -ne [UInt64]7 -or
        [string]$receipt.sha256 -ne $expectedHash -or
        [Int64]$receipt.creation_utc_ticks -ne $info.CreationTimeUtc.Ticks -or
        [Int64]$receipt.last_write_utc_ticks -ne $info.LastWriteTimeUtc.Ticks -or
        [string]$receipt.file_id -notmatch '^0x[0-9a-f]{32}$' -or
        [string]$receipt.method -ne "sha256_stream_locked_file_handle_v2" -or
        [string]$receipt.verification_method -ne
            "sha256_stream_locked_file_handle_v2" -or
        [string]$receipt.test_marker -ne "receipt-v2-lightweight") {
        throw "Receipt content check failed"
    }
    $parsed = [DateTime]::MinValue
    if (-not [DateTime]::TryParse(
            [string]$receipt.verified_at,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AdjustToUniversal,
            [ref]$parsed)) {
        throw "verified_at is not parseable"
    }
    Write-Host "verified receipt v2 lightweight test PASS"
} finally {
    if (Test-Path -LiteralPath $dir) {
        Remove-Item -LiteralPath $dir -Recurse -Force
    }
}
