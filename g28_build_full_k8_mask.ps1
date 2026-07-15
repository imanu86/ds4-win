param(
    [Parameter(Mandatory = $true)][string]$BaseMask,
    [Parameter(Mandatory = $true)][string]$OutputPath
)

$ErrorActionPreference = "Stop"
$extraKeep = @{
    1 = @(32, 81, 117, 182, 104, 96, 34, 155)
    2 = @(84, 219, 39, 74, 34, 210, 159, 44)
}

$rows = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($line in [IO.File]::ReadAllLines((Resolve-Path -LiteralPath $BaseMask))) {
    $trimmed = $line.Trim()
    if ($trimmed -and -not $trimmed.StartsWith("#")) {
        [void]$rows.Add($trimmed)
    }
}
foreach ($layer in $extraKeep.Keys) {
    $kept = [Collections.Generic.HashSet[int]]::new()
    foreach ($expert in $extraKeep[$layer]) { [void]$kept.Add($expert) }
    if ($kept.Count -ne 8) { throw "Layer $layer does not contain exactly eight unique experts" }
    foreach ($expert in 0..255) {
        if (-not $kept.Contains($expert)) { [void]$rows.Add("$layer $expert") }
    }
}

$ordered = $rows | ForEach-Object {
    $parts = $_ -split '\s+'
    [pscustomobject]@{ Layer = [int]$parts[0]; Expert = [int]$parts[1] }
} | Sort-Object Layer, Expert

$counts = $ordered | Group-Object Layer
if ($counts.Count -ne 42 -or @($counts | Where-Object Count -ne 248).Count -ne 0) {
    throw "Full K8 mask must contain 42 layers with 248 pruned experts per layer"
}
$parent = Split-Path -Parent $OutputPath
if ($parent) { [IO.Directory]::CreateDirectory($parent) | Out-Null }
$content = ($ordered | ForEach-Object { "$($_.Layer) $($_.Expert)" }) -join "`n"
[IO.File]::WriteAllText($OutputPath, $content + "`n", [Text.Encoding]::ASCII)
$hash = (Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host "full_k8_mask=$OutputPath rows=$($ordered.Count) layers=$($counts.Count) sha256=$hash"
