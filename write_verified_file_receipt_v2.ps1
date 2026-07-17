# Verified file receipt v2 helper (PowerShell 5.1, ASCII).
param(
    [Parameter(Mandatory=$true)][string]$Path,
    [string]$ReceiptPath,
    [string]$ExpectedSHA256,
    [UInt64]$ExpectedBytes = 0,
    [hashtable]$Metadata = @{}
)

$ErrorActionPreference = "Stop"

if (-not ("DS4VerifiedReceiptNative" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

[StructLayout(LayoutKind.Sequential)]
public struct DS4ByHandleFileInformation {
    public uint FileAttributes;
    public System.Runtime.InteropServices.ComTypes.FILETIME CreationTime;
    public System.Runtime.InteropServices.ComTypes.FILETIME LastAccessTime;
    public System.Runtime.InteropServices.ComTypes.FILETIME LastWriteTime;
    public uint VolumeSerialNumber;
    public uint FileSizeHigh;
    public uint FileSizeLow;
    public uint NumberOfLinks;
    public uint FileIndexHigh;
    public uint FileIndexLow;
}

public static class DS4VerifiedReceiptNative {
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool GetFileInformationByHandle(
        SafeFileHandle hFile,
        out DS4ByHandleFileInformation lpFileInformation);
}
"@ -Language CSharp
}

function Get-DS4ReceiptFileId {
    param([Parameter(Mandatory=$true)][string]$FilePath)
    $raw = & fsutil.exe file queryfileid $FilePath 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Verified receipt file-id query failed: $FilePath"
    }
    $match = [regex]::Match(($raw -join " "), '0x[0-9a-fA-F]{32}')
    if (-not $match.Success) {
        throw "Verified receipt file-id parse failed: $FilePath"
    }
    return $match.Value.ToLowerInvariant()
}

function Write-DS4AtomicJson {
    param(
        [Parameter(Mandatory=$true)][object]$Value,
        [Parameter(Mandatory=$true)][string]$Destination
    )

    $destinationFull = [IO.Path]::GetFullPath($Destination)
    $directory = [IO.Path]::GetDirectoryName($destinationFull)
    if ([string]::IsNullOrWhiteSpace($directory)) {
        $directory = (Get-Location).ProviderPath
        $destinationFull = Join-Path $directory $destinationFull
    }
    New-Item -ItemType Directory -Force -Path $directory | Out-Null

    $temp = Join-Path $directory (
        [IO.Path]::GetFileName($destinationFull) + "." +
        [Guid]::NewGuid().ToString("n") + ".tmp")
    $json = $Value | ConvertTo-Json -Depth 8
    $utf8NoBom = New-Object Text.UTF8Encoding $false
    [IO.File]::WriteAllText($temp, $json + [Environment]::NewLine,
        $utf8NoBom)
    if (Test-Path -LiteralPath $destinationFull -PathType Leaf) {
        [IO.File]::Replace($temp, $destinationFull, $null)
    } else {
        [IO.File]::Move($temp, $destinationFull)
    }
}

function New-DS4VerifiedFileReceiptV2 {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter(Mandatory=$true)][string]$OutPath,
        [string]$ExpectedHash,
        [UInt64]$ExpectedLength = 0,
        [hashtable]$ExtraMetadata = @{}
    )

    $fullPath = [IO.Path]::GetFullPath($FilePath)
    $receiptFull = [IO.Path]::GetFullPath($OutPath)
    $receiptDir = [IO.Path]::GetDirectoryName($receiptFull)
    if ([string]::IsNullOrWhiteSpace($receiptDir)) {
        $receiptDir = (Get-Location).ProviderPath
    }
    New-Item -ItemType Directory -Force -Path $receiptDir | Out-Null
    $lockPath = $receiptFull + ".lock"

    $lock = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate,
        [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        $stream = [IO.File]::Open($fullPath, [IO.FileMode]::Open,
            [IO.FileAccess]::Read, [IO.FileShare]::Read)
        try {
            $nativeInfo = New-Object DS4ByHandleFileInformation
            if (-not [DS4VerifiedReceiptNative]::GetFileInformationByHandle(
                    $stream.SafeFileHandle, [ref]$nativeInfo)) {
                $code = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
                throw "Verified receipt file-id query failed: $fullPath (Win32 $code)"
            }
            $fileId = Get-DS4ReceiptFileId -FilePath $fullPath

            $sha = [Security.Cryptography.SHA256]::Create()
            try {
                $observedHash = ([BitConverter]::ToString(
                        $sha.ComputeHash($stream))).Replace("-", "").ToLowerInvariant()
            } finally {
                $sha.Dispose()
            }

            $info = Get-Item -LiteralPath $fullPath
            $observedLength = [UInt64]$stream.Length
            if ($ExpectedLength -gt 0 -and $observedLength -ne $ExpectedLength) {
                throw "Verified receipt size mismatch: $observedLength != $ExpectedLength"
            }
            if ($ExpectedHash -and $observedHash -ine $ExpectedHash) {
                throw "Verified receipt SHA-256 mismatch: $observedHash"
            }
            if (($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Verified receipt refuses reparse point: $fullPath"
            }

            $method = "sha256_stream_locked_file_handle_v2"
            $receipt = [ordered]@{
                schema = "g7_verified_file_receipt_v2"
                status = "verified"
                path = $fullPath
                bytes = $observedLength
                sha256 = $observedHash
                creation_utc_ticks = [Int64]$info.CreationTimeUtc.Ticks
                last_write_utc_ticks = [Int64]$info.LastWriteTimeUtc.Ticks
                file_id = $fileId
                verified_at = [DateTime]::UtcNow.ToString("o")
                method = $method
                verification_method = $method
            }
            foreach ($key in @($ExtraMetadata.Keys)) {
                if ($receipt.Contains($key)) {
                    throw "Verified receipt metadata key collides with schema: $key"
                }
                $receipt[$key] = $ExtraMetadata[$key]
            }

            Write-DS4AtomicJson -Value $receipt -Destination $receiptFull
            return $receipt
        } finally {
            if ($stream) { $stream.Dispose() }
        }
    } finally {
        $lock.Dispose()
    }
}

if (-not $ReceiptPath) {
    $ReceiptPath = ([IO.Path]::GetFullPath($Path)) + ".receipt.json"
}

$receipt = New-DS4VerifiedFileReceiptV2 -FilePath $Path -OutPath $ReceiptPath `
    -ExpectedHash $ExpectedSHA256 -ExpectedLength $ExpectedBytes `
    -ExtraMetadata $Metadata
$receipt | ConvertTo-Json -Depth 8
