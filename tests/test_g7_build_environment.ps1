param(
    [string]$BuildScript = (Join-Path (
        Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
    ) "g7_build.ps1")
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $BuildScript -PathType Leaf)) {
    throw "G7 build script missing: $BuildScript"
}

$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile(
    $BuildScript, [ref]$tokens, [ref]$errors)
if ($errors -and $errors.Count -gt 0) {
    throw "G7 build AST parse failed: $($errors[0].Message)"
}

$functionAsts = @($ast.FindAll({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst]
}, $true))
$convertAst = @($functionAsts | Where-Object {
    $_.Name -eq "ConvertFrom-G7EnvironmentLines"
} | Select-Object -First 1)
$importAst = @($functionAsts | Where-Object {
    $_.Name -eq "Import-G7ProcessEnvironment"
} | Select-Object -First 1)

if ($convertAst.Count -ne 1 -or $importAst.Count -ne 1) {
    $text = Get-Content -LiteralPath $BuildScript -Raw
    $legacyNeedle = "`$_.StartsWith('PATH=', [StringComparison]::Ordinal)"
    if ($text.IndexOf($legacyNeedle, [StringComparison]::Ordinal) -ge 0) {
        $legacyMatches = @(@("Path=C:\mock-vs\bin") | Where-Object {
            $_.StartsWith('PATH=', [StringComparison]::Ordinal)
        })
        if ($legacyMatches.Count -ne 1) {
            throw "BASELINE REPRODUCED: production Ordinal PATH parser rejected Path fixture"
        }
    }
    throw "G7 build environment parser/import functions missing"
}

Invoke-Expression $convertAst[0].Extent.Text
Invoke-Expression $importAst[0].Extent.Text

function Assert-Equal([object]$Actual, [object]$Expected, [string]$Label) {
    if (-not [object]::Equals($Actual, $Expected)) {
        throw "$Label mismatch: expected='$Expected' actual='$Actual'"
    }
}

function Assert-Throws([scriptblock]$Action, [string]$MessagePattern,
                       [string]$Label) {
    $threw = $false
    $message = $null
    try {
        & $Action
    } catch {
        $threw = $true
        $message = $_.Exception.Message
    }
    if (-not $threw) {
        throw "$Label did not throw"
    }
    if ($message -notlike $MessagePattern) {
        throw "$Label threw unexpected message: $message"
    }
}

$acceptedCases = @(
    @{ name = "Path"; line = "Path=C:\mock-vs\bin" },
    @{ name = "PATH"; line = "PATH=C:\mock-vs\bin" },
    @{ name = "mixed-case"; line = "pAtH=C:\mock-vs\bin" }
)
foreach ($case in $acceptedCases) {
    $parsed = ConvertFrom-G7EnvironmentLines @($case.line, "TEMP=C:\temp")
    Assert-Equal $parsed.DeveloperPath "C:\mock-vs\bin" $case.name
    Assert-Equal $parsed.Variables["path"] "C:\mock-vs\bin" `
        "$($case.name) case-insensitive lookup"
}

$malformed = ConvertFrom-G7EnvironmentLines @(
    "BROKEN",
    "=C:=C:\repo",
    "VALID=value=with=equals",
    "EMPTY=",
    "Path=C:\mock-vs\bin"
)
Assert-Equal $malformed.Variables.Count 3 "malformed-line filtering"
Assert-Equal $malformed.Variables["VALID"] "value=with=equals" `
    "first-separator parsing"
Assert-Equal $malformed.Variables["EMPTY"] "" "empty non-PATH value"

Assert-Throws {
    ConvertFrom-G7EnvironmentLines @("TEMP=C:\temp", "BROKEN") | Out-Null
} "*did not emit PATH*" "missing PATH"
Assert-Throws {
    ConvertFrom-G7EnvironmentLines @("PATH=") | Out-Null
} "*emitted empty PATH*" "empty PATH"
Assert-Throws {
    ConvertFrom-G7EnvironmentLines @(
        "Path=C:\first", "PATH=C:\second") | Out-Null
} "*duplicate*Path*PATH*" "case-only duplicate PATH"

$testVariable = "G7_BUILD_ENV_TEST_" + [Guid]::NewGuid().ToString("N")
$originalPath = [Environment]::GetEnvironmentVariable(
    "Path", [EnvironmentVariableTarget]::Process)
try {
    $parsed = ConvertFrom-G7EnvironmentLines @(
        "$testVariable=process-only",
        "Path=C:\mock-vs\bin;C:\mock-sdk\bin"
    )
    Import-G7ProcessEnvironment $parsed
    Assert-Equal ([Environment]::GetEnvironmentVariable(
        $testVariable, [EnvironmentVariableTarget]::Process)) `
        "process-only" "process environment import"
    Assert-Equal ([Environment]::GetEnvironmentVariable(
        "Path", [EnvironmentVariableTarget]::Process)) `
        "C:\mock-vs\bin;C:\mock-sdk\bin" "process PATH import"
} finally {
    [Environment]::SetEnvironmentVariable(
        $testVariable, $null, [EnvironmentVariableTarget]::Process)
    [Environment]::SetEnvironmentVariable(
        "Path", $originalPath, [EnvironmentVariableTarget]::Process)
}

$importText = $importAst[0].Extent.Text
if ($importText.IndexOf("[EnvironmentVariableTarget]::Process",
        [StringComparison]::Ordinal) -lt 0 -or
    $importText.IndexOf("[EnvironmentVariableTarget]::User",
        [StringComparison]::Ordinal) -ge 0 -or
    $importText.IndexOf("[EnvironmentVariableTarget]::Machine",
        [StringComparison]::Ordinal) -ge 0) {
    throw "Environment import is not confined to the build process"
}

Write-Host "test_g7_build_environment.ps1: PASS"
