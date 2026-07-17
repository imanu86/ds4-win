$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$runner = Join-Path $root "g104_iq1_cold_profile.ps1"
$protocol = Join-Path $root "G104_IQ1_COLD_PROFILE_PROTOCOL.md"

foreach ($path in @($runner, $protocol)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "G104 required file missing: $path"
    }
}
$runnerText = Get-Content -LiteralPath $runner -Raw
$protocolText = Get-Content -LiteralPath $protocol -Raw
foreach ($needle in @(
    'C:\ds4-models\ds4-2bit.gguf',
    'C:\ds4-models\DeepSeek-V4-Flash-IQ1_S-XL.gguf',
    'Iq1SProfile',
    'structural-safety',
    'performance_claim_allowed = $false',
    'quality_claim_allowed = $false',
    'iq1_s_profile_ssd_read_ms',
    'iq1_s_profile_h2d_sync_ms',
    'iq1_s_mixed_profile_main_sync_ms')) {
    if ($runnerText -notmatch [regex]::Escape($needle) -and
        $protocolText -notmatch [regex]::Escape($needle)) {
        throw "G104 contract text missing: $needle"
    }
}
foreach ($forbidden in @(
    '"-Iq1Promotion"', '"-RoutePackedCopy"', '"-Iq1SPackedH2D"',
    '"-Iq1SVramCachePerLayer"', '"-ComposePrefillMassOpenRouter"')) {
    if ($runnerText -match [regex]::Escape($forbidden)) {
        throw "G104 enables forbidden lever: $forbidden"
    }
}
$tokens = $null
$errors = $null
[Management.Automation.Language.Parser]::ParseFile(
    $runner, [ref]$tokens, [ref]$errors) | Out-Null
if ($errors -and $errors.Count -gt 0) {
    throw "G104 runner AST parse failed: $($errors[0].Message)"
}
$before = @(Get-Process -Name ds4_server -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty Id)
$json = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
    -File $runner -StaticCheckOnly
if ($LASTEXITCODE -ne 0) { throw "G104 static check failed" }
$receipt = $json | ConvertFrom-Json
if ([string]$receipt.schema -ne "g104_iq1_cold_profile_static_v1" -or
    -not [bool]$receipt.static_check_only -or
    -not [bool]$receipt.structural_profile_only -or
    -not [bool]$receipt.g103_stack_preserved -or
    -not [bool]$receipt.iq1_profile_only_delta) {
    throw "G104 static receipt mismatch"
}
$after = @(Get-Process -Name ds4_server -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty Id)
if (@($after | Where-Object { $_ -notin $before }).Count -ne 0) {
    throw "G104 static check launched DS4"
}
Write-Output "test_g104_static_contract.ps1: PASS"
