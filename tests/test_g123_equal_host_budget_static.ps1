$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$runnerPath = Join-Path $root "g123_equal_host_budget_ab.ps1"
if (-not (Test-Path -LiteralPath $runnerPath -PathType Leaf)) {
    throw "G123 runner missing: $runnerPath"
}

$tokens = $null
$errors = $null
[Management.Automation.Language.Parser]::ParseFile(
    $runnerPath, [ref]$tokens, [ref]$errors) | Out-Null
if ($errors -and $errors.Count -gt 0) {
    throw "G123 runner AST parse failed: $($errors[0].Message)"
}

$runner = Get-Content -LiteralPath $runnerPath -Raw

function Require-Text {
    param([string]$Text, [string]$Needle, [string]$Contract)
    if ($Text.IndexOf($Needle, [StringComparison]::Ordinal) -lt 0) {
        throw "G123 contract missing ($Contract): $Needle"
    }
}

foreach ($needle in @(
        'g7_harness_bootstrap.ps1',
        'HarnessArguments = @($Plan.harness_arguments)',
        '& $bootstrap @bootstrapArgs',
        '-GateKind", "benchmark"',
        '-AllowBenchmarkVerifiedReceiptReuse',
        '$modelLock = [IO.File]::Open(',
        '$sidecarLock = [IO.File]::Open(',
        '[IO.FileAccess]::Read, [IO.FileShare]::Read)',
        '$sidecarLock.Dispose()',
        '$modelLock.Dispose()',
        '-Repeats", "1"',
        '-MaxTokens", "64"',
        '-Context", "256"',
        '-ExpectedContentSHA256", $expectedContentSHA',
        'fd6c4522975a71e252b90199d49cfe3236310e2a7285dc0fc4d0e9d0e4885510',
        '$controlArenaGiB = 30.0',
        '$candidateArenaGiB = 25.828125',
        '$candidateNestedBaseGiB = 3.75',
        '$candidateExactCacheGiB = 0.421875',
        '[bool]$preflight.ready_to_launch',
        'host_budget_gib = [ordered]@{',
        '-NestedResidualCacheExperts", "64"',
        '-NestedResidualGpuCache',
        '-AllowNestedResidualBenchmarkSuite',
        '-OuterNestedResidualBenchmarkProcessCount", "3"',
        '-NestedResidualVerifyReconstruction',
        '-ExpertCacheN", "320"',
        '-ExpertTiering", "enforce"',
        '-ExpertTierPolicy", "mass-lfru"',
        '[int]$json.expert_tiering.compose_router_open -ne 1',
        '-SplitFused',
        'G123 child result missing',
        '[string]$ResumeBatchTag = ""',
        '[string]$MissingAttemptSuffix = ""',
        '$baseChildTag + "_" + $MissingAttemptSuffix',
        '[ValidateRange(0, 600)][int]$InterChildCooldownSec = 30',
        '[g123] reuse completed child=',
        'Start-Sleep -Seconds $InterChildCooldownSec',
        'G123 child must be exactly one independent process/request',
        'G123 child must run with GateKind benchmark',
        'G123 candidate nested GPU-cache contract mismatch',
        'G123 n>=3 verdict invalid')) {
    Require-Text $runner $needle "runner contract"
}

foreach ($forbidden in @(
        '-Repeats", "3"',
        '-GateKind", "structural-safety"',
        '-NestedResidualStructuralN1',
        'UniqueTagSuffix = $true',
        ' -- ',
        '"--"',
        "'--'",
        'g7_measure.ps1 @',
        '-NestedResidualSidecar", $sidecar, "-NestedResidualGpuCache"')) {
    if ($runner.IndexOf($forbidden, [StringComparison]::Ordinal) -ge 0) {
        throw "G123 forbidden marker present: $forbidden"
    }
}

$whatIfOutput = @(& $runnerPath -Tag "g123_static_probe" -WhatIf)
$whatIfText = $whatIfOutput -join "`n"
foreach ($needle in @(
        '"schema":  "g123_equal_host_budget_ab_plan_v1"',
        '"child_count":  6',
        '"arm":  "control"',
        '"arm":  "candidate"',
        '"dynamic_arena_gib":  30',
        '"dynamic_arena_gib":  25.828125')) {
    if ($whatIfText.IndexOf($needle, [StringComparison]::Ordinal) -lt 0) {
        throw "G123 WhatIf output missing marker: $needle"
    }
}

$repeatOneCount = ([regex]::Matches(
        $whatIfText, '"-Repeats",\s+"1"')).Count
if ($repeatOneCount -lt 6 -or ($repeatOneCount % 6) -ne 0) {
    throw "G123 WhatIf should expose six independent Repeats=1 children; observed $repeatOneCount markers"
}
if ([regex]::Matches($whatIfText, '"-Repeats",\s+"3"').Count -ne 0) {
    throw "G123 WhatIf planned a same-process Repeats=3 child"
}

Write-Output "test_g123_equal_host_budget_static.ps1: PASS"
