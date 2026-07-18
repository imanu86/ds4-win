$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$bootstrap = Join-Path $root "g7_harness_bootstrap.ps1"
if (-not (Test-Path -LiteralPath $bootstrap -PathType Leaf)) {
    throw "G7 harness bootstrap missing: $bootstrap"
}

$tokens = $null
$errors = $null
[Management.Automation.Language.Parser]::ParseFile(
    $bootstrap, [ref]$tokens, [ref]$errors) | Out-Null
if ($errors -and $errors.Count -gt 0) {
    throw "G7 harness bootstrap AST parse failed: $($errors[0].Message)"
}

$text = Get-Content -LiteralPath $bootstrap -Raw
foreach ($needle in @(
    'GIT_CONFIG_COUNT',
    'GIT_CONFIG_KEY_',
    'GIT_CONFIG_VALUE_',
    'safe.directory',
    'core.excludesFile',
    'New-G7ImmutableTagSuffix',
    'G7_HARNESS_IMMUTABLE_TAG_SUFFIX',
    'Get-G7BootstrapDs4Conflicts',
    'ds4_server.exe',
    'g7_(measure|runtime_monitor|harness_bootstrap)\.ps1',
    'conflicting-ds4-or-g7-process',
    '-File $harness @effectiveHarnessArguments')) {
    if ($text.IndexOf($needle, [StringComparison]::Ordinal) -lt 0) {
        throw "G7 harness bootstrap marker missing: $needle"
    }
}

foreach ($forbidden in @(
    'git config --global',
    'git config --system',
    'safe.directory *')) {
    if ($text.IndexOf($forbidden, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw "G7 harness bootstrap forbidden global git config marker present: $forbidden"
    }
}

$probe = Join-Path ([IO.Path]::GetTempPath()) `
    ("g7_bootstrap_arg_probe_" + [Guid]::NewGuid().ToString("N") + ".ps1")
try {
    @'
param([string]$GateKind, [int]$MaxTokens)
[pscustomobject]@{ gate_kind = $GateKind; max_tokens = $MaxTokens } |
    ConvertTo-Json -Compress
'@ | Set-Content -LiteralPath $probe -Encoding ASCII
    $probeOutput = @(& $bootstrap `
        -HarnessPath $probe `
        -RepoRoot $root `
        -HarnessArguments @("-GateKind", "structural-safety",
                            "-MaxTokens", "64"))
    $probeResult = ($probeOutput -join "`n") | ConvertFrom-Json
    if ($probeResult.gate_kind -ne "structural-safety" -or
        [int]$probeResult.max_tokens -ne 64) {
        throw "G7 bootstrap named-argument forwarding probe failed"
    }
} finally {
    Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
}

Write-Host "test_g7_harness_bootstrap_static.ps1: PASS"
