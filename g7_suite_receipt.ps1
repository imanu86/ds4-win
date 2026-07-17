# Model/IQ1 suite receipt helper (PowerShell 5.1, ASCII).
param(
    [Parameter(Mandatory=$true)][string]$ModelPath,
    [Parameter(Mandatory=$true)][string]$Iq1SExpertSidecar,
    [Parameter(Mandatory=$true)][string]$OutPath,
    [string]$ModelReceiptPath,
    [string]$Iq1SReceiptPath,
    [Parameter(Mandatory=$true)][string]$ExpectedModelSHA256,
    [Parameter(Mandatory=$true)][string]$ExpectedIq1SExpertSidecarSHA256,
    [Parameter(Mandatory=$true)][UInt64]$ExpectedIq1SExpertSidecarBytes,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

function Get-G7SuiteFileId([string]$Path) {
    $raw = & fsutil.exe file queryfileid $Path 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Suite receipt file-id query failed: $Path"
    }
    $match = [regex]::Match(($raw -join " "), '0x[0-9a-fA-F]{32}')
    if (-not $match.Success) {
        throw "Suite receipt file-id parse failed: $Path"
    }
    $match.Value.ToLowerInvariant()
}

function Read-G7SuiteReceiptSnapshot([string]$Path, [string]$Kind) {
    $stream = $null
    try {
        $stream = [IO.File]::Open(
            $Path, [IO.FileMode]::Open,
            [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $memory = New-Object IO.MemoryStream
        try {
            $stream.CopyTo($memory)
            $bytes = $memory.ToArray()
        } finally {
            $memory.Dispose()
        }
    } catch {
        throw "$Kind receipt could not be read: $($_.Exception.Message)"
    } finally {
        if ($null -ne $stream) { $stream.Dispose() }
    }
    try {
        $receipt = [Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json
    } catch {
        throw "$Kind receipt is invalid JSON"
    }
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $receiptHash = [BitConverter]::ToString(
            $sha.ComputeHash($bytes)).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
    [pscustomobject]@{
        receipt = $receipt
        sha256 = $receiptHash
    }
}

function Get-G7SuiteIdentity {
    param([Parameter(Mandatory=$true)][IO.FileInfo]$Info)
    [pscustomobject]@{
        path = [IO.Path]::GetFullPath($Info.FullName)
        bytes = [UInt64]$Info.Length
        creation_utc_ticks = [Int64]$Info.CreationTimeUtc.Ticks
        last_write_utc_ticks = [Int64]$Info.LastWriteTimeUtc.Ticks
        file_id = Get-G7SuiteFileId $Info.FullName
        reparse_point =
            (($Info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
    }
}

function Assert-G7SuiteIdentityUnchanged {
    param(
        [Parameter(Mandatory=$true)][object]$Before,
        [Parameter(Mandatory=$true)][object]$After,
        [Parameter(Mandatory=$true)][string]$Kind
    )
    if (-not [string]::Equals(
            [string]$Before.path, [string]$After.path,
            [StringComparison]::OrdinalIgnoreCase) -or
        [UInt64]$Before.bytes -ne [UInt64]$After.bytes -or
        [Int64]$Before.creation_utc_ticks -ne
            [Int64]$After.creation_utc_ticks -or
        [Int64]$Before.last_write_utc_ticks -ne
            [Int64]$After.last_write_utc_ticks -or
        [string]$Before.file_id -ine [string]$After.file_id -or
        [bool]$Before.reparse_point -ne [bool]$After.reparse_point) {
        throw "$Kind identity changed during suite hashing"
    }
    if ([bool]$After.reparse_point) {
        throw "$Kind must not be a reparse point"
    }
}

function Get-G7SuiteStreamSHA256 {
    param(
        [Parameter(Mandatory=$true)][IO.Stream]$Stream,
        [Parameter(Mandatory=$true)][string]$Kind,
        [int]$BufferBytes = 8MB
    )
    if (-not $Stream.CanRead) {
        throw "$Kind locked stream is not readable"
    }
    if ($BufferBytes -lt 1MB) {
        throw "$Kind hash buffer must be at least 1 MiB"
    }
    if ($Stream.CanSeek) {
        $Stream.Position = 0
    }
    $sha = [Security.Cryptography.IncrementalHash]::CreateHash(
        [Security.Cryptography.HashAlgorithmName]::SHA256)
    $buffer = New-Object byte[] $BufferBytes
    try {
        while (($read = $Stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $sha.AppendData($buffer, 0, $read)
        }
        return [BitConverter]::ToString(
            $sha.GetHashAndReset()).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Assert-G7SuiteVerifiedFileReceipt {
    param(
        [Parameter(Mandatory=$true)][object]$Receipt,
        [Parameter(Mandatory=$true)][IO.FileInfo]$Info,
        [Parameter(Mandatory=$true)][string]$ExpectedSHA256,
        [Parameter(Mandatory=$true)][UInt64]$ExpectedBytes,
        [Parameter(Mandatory=$true)][string]$Kind
    )
    $fullPath = [IO.Path]::GetFullPath($Info.FullName)
    $receiptPath = [IO.Path]::GetFullPath([string]$Receipt.path)
    $fileId = Get-G7SuiteFileId $fullPath
    $verifiedAt = [DateTime]::MinValue
    if (-not [DateTime]::TryParse(
            [string]$Receipt.verified_at,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AdjustToUniversal,
            [ref]$verifiedAt)) {
        throw "$Kind verified receipt timestamp is invalid"
    }
    if ([string]$Receipt.schema -ne "g7_verified_file_receipt_v2" -or
        [string]$Receipt.status -ne "verified" -or
        -not [string]::Equals(
            $receiptPath, $fullPath,
            [StringComparison]::OrdinalIgnoreCase) -or
        [UInt64]$Receipt.bytes -ne $ExpectedBytes -or
        [UInt64]$Info.Length -ne $ExpectedBytes -or
        [string]$Receipt.sha256 -ine $ExpectedSHA256 -or
        [Int64]$Receipt.creation_utc_ticks -ne $Info.CreationTimeUtc.Ticks -or
        [Int64]$Receipt.last_write_utc_ticks -ne $Info.LastWriteTimeUtc.Ticks -or
        [string]$Receipt.file_id -ine $fileId -or
        ($Info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
        $verifiedAt.ToUniversalTime() -lt $Info.LastWriteTimeUtc -or
        [string]::IsNullOrWhiteSpace([string]$Receipt.verification_method)) {
        throw "$Kind verified receipt identity mismatch"
    }
}

function New-G7SuiteChild {
    param(
        [Parameter(Mandatory=$true)][object]$Receipt,
        [Parameter(Mandatory=$true)][string]$ReceiptPath,
        [Parameter(Mandatory=$true)][string]$ReceiptSHA256,
        [Parameter(Mandatory=$true)][object]$Identity,
        [Parameter(Mandatory=$true)][string]$LockedStreamSHA256
    )
    [ordered]@{
        receipt_path = [IO.Path]::GetFullPath($ReceiptPath)
        receipt_sha256 = $ReceiptSHA256
        receipt_schema = [string]$Receipt.schema
        receipt_status = [string]$Receipt.status
        path = [string]$Identity.path
        bytes = [UInt64]$Identity.bytes
        sha256 = $LockedStreamSHA256.ToLowerInvariant()
        hash_method = "locked_stream_sha256"
        full_hash_verified = $true
        creation_utc_ticks = [Int64]$Identity.creation_utc_ticks
        last_write_utc_ticks = [Int64]$Identity.last_write_utc_ticks
        file_id = [string]$Identity.file_id
    }
}

function Write-G7SuiteAtomicJson {
    param(
        [Parameter(Mandatory=$true)][object]$Value,
        [Parameter(Mandatory=$true)][string]$Destination,
        [switch]$ReplaceExisting
    )
    $destinationFull = [IO.Path]::GetFullPath($Destination)
    $directory = [IO.Path]::GetDirectoryName($destinationFull)
    if ([string]::IsNullOrWhiteSpace($directory)) {
        $directory = (Get-Location).ProviderPath
        $destinationFull = Join-Path $directory $destinationFull
    }
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    if ((Test-Path -LiteralPath $destinationFull -PathType Leaf) -and
        -not $ReplaceExisting) {
        throw "Suite receipt already exists; pass -Force to replace: $destinationFull"
    }
    $temp = Join-Path $directory (
        [IO.Path]::GetFileName($destinationFull) + "." +
        [Guid]::NewGuid().ToString("n") + ".tmp")
    $json = $Value | ConvertTo-Json -Depth 8
    $utf8NoBom = New-Object Text.UTF8Encoding $false
    [IO.File]::WriteAllText($temp, $json + [Environment]::NewLine,
        $utf8NoBom)
    if (Test-Path -LiteralPath $destinationFull -PathType Leaf) {
        $backup = Join-Path $directory (
            [IO.Path]::GetFileName($destinationFull) + "." +
            [Guid]::NewGuid().ToString("n") + ".bak")
        [IO.File]::Replace($temp, $destinationFull, $backup)
        if (Test-Path -LiteralPath $backup -PathType Leaf) {
            Remove-Item -LiteralPath $backup -Force
        }
    } else {
        [IO.File]::Move($temp, $destinationFull)
    }
    return $destinationFull
}

if ($ExpectedModelSHA256 -notmatch '^[0-9a-fA-F]{64}$') {
    throw "ExpectedModelSHA256 must be a 64-character hexadecimal SHA-256"
}
if ($ExpectedIq1SExpertSidecarSHA256 -notmatch '^[0-9a-fA-F]{64}$') {
    throw "ExpectedIq1SExpertSidecarSHA256 must be a 64-character hexadecimal SHA-256"
}
if ($ExpectedIq1SExpertSidecarBytes -eq 0) {
    throw "ExpectedIq1SExpertSidecarBytes must be greater than zero"
}

$modelInfo = Get-Item -LiteralPath $ModelPath
$sidecarInfo = Get-Item -LiteralPath $Iq1SExpertSidecar
$modelFull = [IO.Path]::GetFullPath($modelInfo.FullName)
$sidecarFull = [IO.Path]::GetFullPath($sidecarInfo.FullName)
$hashBufferBytes = 8MB
$modelLock = [IO.FileStream]::new(
    $modelFull, [IO.FileMode]::Open, [IO.FileAccess]::Read,
    [IO.FileShare]::Read, $hashBufferBytes, [IO.FileOptions]::SequentialScan)
$sidecarLock = $null
try {
$sidecarLock = [IO.FileStream]::new(
    $sidecarFull, [IO.FileMode]::Open, [IO.FileAccess]::Read,
    [IO.FileShare]::Read, $hashBufferBytes, [IO.FileOptions]::SequentialScan)
$modelIdentityBefore = Get-G7SuiteIdentity $modelInfo
$sidecarIdentityBefore = Get-G7SuiteIdentity $sidecarInfo
$modelHash = Get-G7SuiteStreamSHA256 -Stream $modelLock -Kind "Model"
$sidecarHash = Get-G7SuiteStreamSHA256 -Stream $sidecarLock `
    -Kind "IQ1_S sidecar"
if ($modelHash -ine $ExpectedModelSHA256) {
    throw "Model locked-stream SHA-256 mismatch"
}
if ($sidecarHash -ine $ExpectedIq1SExpertSidecarSHA256) {
    throw "IQ1_S sidecar locked-stream SHA-256 mismatch"
}
$modelInfoAfterHash = Get-Item -LiteralPath $modelFull
$sidecarInfoAfterHash = Get-Item -LiteralPath $sidecarFull
$modelIdentityAfter = Get-G7SuiteIdentity $modelInfoAfterHash
$sidecarIdentityAfter = Get-G7SuiteIdentity $sidecarInfoAfterHash
Assert-G7SuiteIdentityUnchanged -Before $modelIdentityBefore `
    -After $modelIdentityAfter -Kind "Model"
Assert-G7SuiteIdentityUnchanged -Before $sidecarIdentityBefore `
    -After $sidecarIdentityAfter -Kind "IQ1_S sidecar"
if (-not $ModelReceiptPath) { $ModelReceiptPath = "$modelFull.receipt.json" }
if (-not $Iq1SReceiptPath) { $Iq1SReceiptPath = "$sidecarFull.receipt.json" }
if (-not (Test-Path -LiteralPath $ModelReceiptPath -PathType Leaf)) {
    throw "Model verified receipt missing: $ModelReceiptPath"
}
if (-not (Test-Path -LiteralPath $Iq1SReceiptPath -PathType Leaf)) {
    throw "IQ1_S sidecar verified receipt missing: $Iq1SReceiptPath"
}

$modelSnapshot = Read-G7SuiteReceiptSnapshot -Path $ModelReceiptPath -Kind "Model"
$sidecarSnapshot = Read-G7SuiteReceiptSnapshot -Path $Iq1SReceiptPath `
    -Kind "IQ1_S sidecar"
Assert-G7SuiteVerifiedFileReceipt -Receipt $modelSnapshot.receipt `
    -Info $modelInfo -ExpectedSHA256 $ExpectedModelSHA256 `
    -ExpectedBytes ([UInt64]$modelIdentityBefore.bytes) -Kind "Model"
Assert-G7SuiteVerifiedFileReceipt -Receipt $sidecarSnapshot.receipt `
    -Info $sidecarInfo -ExpectedSHA256 $ExpectedIq1SExpertSidecarSHA256 `
    -ExpectedBytes $ExpectedIq1SExpertSidecarBytes -Kind "IQ1_S sidecar"
if ([string]::IsNullOrWhiteSpace([string]$sidecarSnapshot.receipt.source) -or
    [string]::IsNullOrWhiteSpace(
        [string]$sidecarSnapshot.receipt.quantization_layout) -or
    [string]::IsNullOrWhiteSpace(
        [string]$sidecarSnapshot.receipt.imatrix_provenance)) {
    throw "IQ1_S sidecar receipt is missing source/quantization/imatrix provenance"
}

$receipt = [ordered]@{
    schema = "g7_model_iq1_suite_receipt_v1"
    status = "verified"
    purpose = "model_iq1_provenance_reuse"
    immutable = $true
    created_at = [DateTime]::UtcNow.ToString("o")
    hash_method = "locked_stream_sha256"
    full_hash_verified = $true
    model = New-G7SuiteChild -Receipt $modelSnapshot.receipt `
        -ReceiptPath $ModelReceiptPath -ReceiptSHA256 $modelSnapshot.sha256 `
        -Identity $modelIdentityBefore -LockedStreamSHA256 $modelHash
    iq1_s_sidecar = New-G7SuiteChild -Receipt $sidecarSnapshot.receipt `
        -ReceiptPath $Iq1SReceiptPath -ReceiptSHA256 $sidecarSnapshot.sha256 `
        -Identity $sidecarIdentityBefore -LockedStreamSHA256 $sidecarHash
}

$writtenPath = Write-G7SuiteAtomicJson -Value $receipt -Destination $OutPath `
    -ReplaceExisting:$Force
$suiteSHA256 = (
    Get-FileHash -Algorithm SHA256 -LiteralPath $writtenPath
).Hash.ToLowerInvariant()
[pscustomobject]@{
    suite_receipt_path = $writtenPath
    suite_receipt_sha256 = $suiteSHA256
    schema = $receipt.schema
    status = $receipt.status
    purpose = $receipt.purpose
} | ConvertTo-Json -Depth 4
} finally {
    if ($null -ne $sidecarLock) { $sidecarLock.Dispose() }
    if ($null -ne $modelLock) { $modelLock.Dispose() }
}
