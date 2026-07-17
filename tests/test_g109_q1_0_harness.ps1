# Q1_0 step3 harness parser/static regression test (PowerShell 5.1, ASCII).
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$harness = Join-Path $root "g7_measure.ps1"
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile(
    $harness, [ref]$tokens, [ref]$errors)
if ($errors -and $errors.Count -gt 0) {
    throw "G109 harness AST parse failed: $($errors[0].Message)"
}

$parserAst = $ast.Find({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq "Read-G7Q1_0SidecarTelemetry"
}, $true)
if ($null -eq $parserAst) {
    throw "G109 Q1_0 telemetry parser function is missing"
}
. ([scriptblock]::Create($parserAst.Extent.Text))

$beforeDs4 = @(Get-Process -Name "ds4_server" -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty Id)
$sidecarPath = "C:\fixtures\q1_0-step3.gguf"
$positiveLog = @"
ds4: Q1_0 routed-expert sidecar validated: layers=43 active=12..12
ds4: Q1_0 expert sidecar source: $sidecarPath
ds4: CUDA Q1_0 routed-expert sidecar installed: 1.00 GiB
ds4: timing calls=999 slots=999 selected_loads=999 failures=999
ds4: [q1-0-sidecar] result=summary calls=7 slots=42 selected_loads=7 failures=0 resident_mode=1 resident_hits=7 resident_misses=0
"@
$positive = Read-G7Q1_0SidecarTelemetry -LogText $positiveLog `
    -SidecarConfigured $true -SelectedLoadRequested $true `
    -SidecarPath $sidecarPath
if (-not [bool]$positive.runtime_observed -or
    [UInt64]$positive.route_calls -ne 7 -or
    [UInt64]$positive.route_slots -ne 42 -or
    [UInt64]$positive.selected_loads -ne 7 -or
    [UInt64]$positive.failures -ne 0 -or
    -not [bool]$positive.runtime_contract_valid -or
    [bool]$positive.fail_closed_observed) {
    throw "G109 positive Q1_0 summary parse mismatch"
}

$envOffLog = @"
ds4: CUDA split-fused hit/miss execution enabled
ds4: [iq1-s-sidecar] result=summary calls=3 slots=18 selected_loads=3 failures=0
"@
$envOff = Read-G7Q1_0SidecarTelemetry -LogText $envOffLog `
    -SidecarConfigured $false -SelectedLoadRequested $false `
    -SidecarPath ""
if ([bool]$envOff.enabled -or [bool]$envOff.runtime_observed -or
    [UInt64]$envOff.route_calls -ne 0 -or
    [UInt64]$envOff.route_slots -ne 0 -or
    [UInt64]$envOff.selected_loads -ne 0 -or
    [UInt64]$envOff.failures -ne 0 -or
    -not [bool]$envOff.runtime_contract_valid) {
    throw "G109 env-off Q1_0 state was not disabled/unobserved"
}

$negativeLog = @"
ds4: Q1_0 routed-expert sidecar validated: layers=43 active=12..12
ds4: Q1_0 expert sidecar source: $sidecarPath
ds4: CUDA Q1_0 routed-expert sidecar installed: 1.00 GiB
ds4: [q1-0-sidecar] result=summary calls=1 slots=6 selected_loads=0 failures=1
"@
$negative = Read-G7Q1_0SidecarTelemetry -LogText $negativeLog `
    -SidecarConfigured $true -SelectedLoadRequested $false `
    -SidecarPath $sidecarPath
if (-not [bool]$negative.runtime_observed -or
    -not [bool]$negative.fail_closed_observed -or
    [UInt64]$negative.route_calls -ne 1 -or
    [UInt64]$negative.selected_loads -ne 0 -or
    [UInt64]$negative.failures -ne 1) {
    throw "G109 negative opt-in fail-closed parse mismatch"
}

function Assert-G109ParserRejects([string]$LogText, [bool]$Configured,
        [bool]$SelectedLoad, [string]$ExpectedMessage) {
    $rejected = $false
    try {
        Read-G7Q1_0SidecarTelemetry -LogText $LogText `
            -SidecarConfigured $Configured `
            -SelectedLoadRequested $SelectedLoad `
            -SidecarPath $sidecarPath | Out-Null
    } catch {
        if ($_.Exception.Message -notmatch [regex]::Escape($ExpectedMessage)) {
            throw
        }
        $rejected = $true
    }
    if (-not $rejected) {
        throw "G109 parser accepted invalid telemetry: $ExpectedMessage"
    }
}

Assert-G109ParserRejects `
    -LogText ($positiveLog + "`n" +
        "ds4: [q1-0-sidecar] result=summary calls=7 slots=42 selected_loads=7 failures=0") `
    -Configured $true -SelectedLoad $true `
    -ExpectedMessage "requires exactly one runtime summary"
Assert-G109ParserRejects `
    -LogText ($positiveLog -replace 'selected_loads=7 failures=0',
        'selected_loads=6 failures=0') `
    -Configured $true -SelectedLoad $true `
    -ExpectedMessage "selected-load counters are inconsistent"
Assert-G109ParserRejects `
    -LogText ($positiveLog -replace 'resident_hits=7',
        'resident hits=7') `
    -Configured $true -SelectedLoad $true `
    -ExpectedMessage "requires exactly one runtime summary"
Assert-G109ParserRejects `
    -LogText "ds4: Q1_0 routed-expert sidecar validated:" `
    -Configured $false -SelectedLoad $false `
    -ExpectedMessage "appeared while Q1_0 was disabled"

$harnessText = Get-Content -LiteralPath $harness -Raw
foreach ($needle in @(
    'DS4_Q1_0_EXPERT_SIDECAR',
    'DS4_Q1_0_SELECTED_LOAD',
    'DS4_Q1_0_LAYER_FIRST',
    'DS4_Q1_0_LAYER_LAST',
    '[q1-0-sidecar\] result=summary calls=(\d+) slots=(\d+) selected_loads=(\d+) failures=(\d+)',
    'Q1_0 runtime step3 requires GateKind=structural-safety, Repeats=1, and no warmup',
    'q1_0_sidecar_runtime_observed',
    'q1_0_sidecar_route_calls',
    'q1_0_sidecar_route_slots',
    'q1_0_sidecar_selected_loads',
    'q1_0_sidecar_failures',
    'q1_0_sidecar_provenance_verified',
    'q1_0_structural_smoke_eligible',
    'q1_0_performance_eligible = $false',
    'q1_0_quality_eligible = $false',
    '"not_requested"',
    '$ReuseVerifiedQ1_0Receipt')) {
    if ($harnessText -notmatch [regex]::Escape($needle)) {
        throw "G109 harness contract text missing: $needle"
    }
}

$afterDs4 = @(Get-Process -Name "ds4_server" -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty Id)
if (($beforeDs4 -join ",") -ne ($afterDs4 -join ",")) {
    throw "G109 static/parser test changed DS4 process state"
}

Write-Host "test_g109_q1_0_harness.ps1: PASS"
