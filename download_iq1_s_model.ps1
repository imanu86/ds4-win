param(
    [string]$DestinationDirectory = 'D:\ds4-models'
)

$ErrorActionPreference = 'Stop'
$name = 'DeepSeek-V4-Flash-IQ1_S-XL.gguf'
$url = 'https://huggingface.co/persadian/DeepSeek-V4-Flash-IQ1_S-XL/resolve/main/DeepSeek-V4-Flash-IQ1_S-XL.gguf'
$expectedBytes = 61540805344L
$expectedSha256 = 'b049d1eb34c068f19ab007b33c22a7d758b578bf2b10d9276e79654f85d35047'
$final = Join-Path $DestinationDirectory $name
$partial = "$final.partial"
$receipt = "$final.receipt.json"
$receiptHelper = Join-Path $PSScriptRoot 'write_verified_file_receipt_v2.ps1'

New-Item -ItemType Directory -Force -Path $DestinationDirectory | Out-Null

if (Test-Path -LiteralPath $final) {
    $item = Get-Item -LiteralPath $final
    if ($item.Length -ne $expectedBytes) {
        throw "Existing final file has $($item.Length) bytes, expected $expectedBytes"
    }
    $sha = (Get-FileHash -LiteralPath $final -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($sha -ne $expectedSha256) {
        throw "Existing final file SHA-256 mismatch: $sha"
    }
} else {
    & curl.exe -L --fail --retry 8 --retry-all-errors --continue-at - `
        --output $partial $url
    if ($LASTEXITCODE -ne 0) {
        throw "curl failed with exit code $LASTEXITCODE"
    }
    $item = Get-Item -LiteralPath $partial
    if ($item.Length -ne $expectedBytes) {
        throw "Partial file has $($item.Length) bytes, expected $expectedBytes"
    }
    $sha = (Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($sha -ne $expectedSha256) {
        throw "Downloaded file SHA-256 mismatch: $sha"
    }
    Move-Item -LiteralPath $partial -Destination $final
}

[ordered]@{
    status = 'verified'
    path = $final
    bytes = $expectedBytes
    sha256 = $expectedSha256
    source = $url
    source_repository = 'https://huggingface.co/persadian/DeepSeek-V4-Flash-IQ1_S-XL'
    quantization_layout = 'routed gate/up IQ1_S all layers; routed down Q2_K layers 0-2 and IQ1_S layers 3-42'
    imatrix_provenance = 'public artifact reports WikiText calibration; not coding-tuned and not evidence of downstream equivalence'
}

if (-not (Test-Path -LiteralPath $receiptHelper -PathType Leaf)) {
    throw "Verified receipt helper missing: $receiptHelper"
}
& $receiptHelper `
    -Path $final `
    -ReceiptPath $receipt `
    -ExpectedSHA256 $expectedSha256 `
    -ExpectedBytes $expectedBytes `
    -Metadata $metadata | Out-Null
Get-Content -LiteralPath $receipt
