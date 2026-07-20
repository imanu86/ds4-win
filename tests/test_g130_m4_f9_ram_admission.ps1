$ErrorActionPreference = "Stop"

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if (-not $Condition) { throw $Message }
}

function Get-FunctionText {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $start = $Source.IndexOf("function $Name")
    Assert-True ($start -ge 0) "missing function $Name"
    $brace = $Source.IndexOf("{", $start)
    Assert-True ($brace -gt $start) "missing body for function $Name"
    $depth = 0
    for ($i = $brace; $i -lt $Source.Length; $i++) {
        if ($Source[$i] -eq "{") { $depth++ }
        if ($Source[$i] -eq "}") { $depth-- }
        if ($depth -eq 0) {
            return $Source.Substring($start, $i - $start + 1)
        }
    }
    throw "unterminated function $Name"
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$source = [IO.File]::ReadAllText((Join-Path $repoRoot "g7_measure.ps1"))
Invoke-Expression (Get-FunctionText -Source $source -Name "Get-G7PreflightRequiredRamGiB")
Invoke-Expression (Get-FunctionText -Source $source -Name "Test-G7PreflightRamAdmission")

$required = Get-G7PreflightRequiredRamGiB `
    -MinimumAvailableGiB 0.0 `
    -DynamicArenaGiB 24.5 `
    -Q1_0ArenaGB 11.875 `
    -Q1_0DualSparseCompanion $false `
    -Q1_0PromotionSsdWrap $true `
    -Q1_0Iq2PinnedGiB 5.5 `
    -NestedResidualAllLayerStorageRequested $false `
    -NestedResidualExpectedHostAllocationGiB 0.0
Assert-True ([math]::Abs($required - 43.875) -lt 0.000001) "required_gib was not derived from configured arenas"

$refusePreflight = [pscustomobject]@{
    after = [pscustomobject]@{ available_bytes = [UInt64](40 * 1GB) }
}
$refuse = Test-G7PreflightRamAdmission `
    -MemoryPreflight $refusePreflight `
    -RequiredGiB $required `
    -DynamicArenaGiB 24.5 `
    -Q1_0ArenaGB 11.875 `
    -Q1_0PromotionSsdWrap $true `
    -Q1_0Iq2PinnedGiB 5.5
Assert-True ($refuse.decision -eq "refuse") "low availability did not refuse"
Assert-True ([math]::Abs($refuse.available_gib - 40.0) -lt 0.000001) "refusal did not report mocked availability"
Assert-True ($refuse.failure_message -match "required_gib=43.875") "refusal did not report required_gib"
Assert-True ($refuse.failure_message -match "dynamic_arena_gib=24.5") "refusal did not name driving parameters"

$passPreflight = [pscustomobject]@{
    after = [pscustomobject]@{ available_bytes = [UInt64](44 * 1GB) }
}
$pass = Test-G7PreflightRamAdmission `
    -MemoryPreflight $passPreflight `
    -RequiredGiB $required `
    -DynamicArenaGiB 24.5 `
    -Q1_0ArenaGB 11.875 `
    -Q1_0PromotionSsdWrap $true `
    -Q1_0Iq2PinnedGiB 5.5
Assert-True ($pass.decision -eq "pass") "sufficient availability did not pass"
Assert-True ([math]::Abs($pass.available_gib - 44.0) -lt 0.000001) "pass did not report mocked availability"

$unknown = Test-G7PreflightRamAdmission `
    -MemoryPreflight ([pscustomobject]@{ after = $null }) `
    -RequiredGiB $required `
    -DynamicArenaGiB 24.5 `
    -Q1_0ArenaGB 11.875 `
    -Q1_0PromotionSsdWrap $true `
    -Q1_0Iq2PinnedGiB 5.5
Assert-True ($unknown.decision -eq "unable-to-verify") "null availability did not fail closed"

$skipped = Test-G7PreflightRamAdmission `
    -MemoryPreflight ([pscustomobject]@{ skipped = $true; after = $null }) `
    -RequiredGiB $required `
    -DynamicArenaGiB 24.5 `
    -Q1_0ArenaGB 11.875 `
    -Q1_0PromotionSsdWrap $true `
    -Q1_0Iq2PinnedGiB 5.5
Assert-True ($skipped.decision -eq "skipped_by_operator") "operator skip did not bypass admission"
Assert-True ($null -eq $skipped.available_gib) "operator skip reported availability"
Assert-True ($null -eq $skipped.failure_message) "operator skip reported a failure"

$wiredTag = "g130_m4_f9_ram_admission_refusal_test"
$wiredRoot = Join-Path ([IO.Path]::GetTempPath()) "g7_ram_admission_test"
if (Test-Path -LiteralPath $wiredRoot) {
    Remove-Item -LiteralPath $wiredRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $wiredRoot -Force | Out-Null
foreach ($name in @(
        "g7_measure.ps1",
        "g7_process_isolation.ps1",
        "g7_system_counters.ps1",
        "g7_memory_preflight.ps1",
        "g7_runtime_monitor.ps1")) {
    Copy-Item -LiteralPath (Join-Path $repoRoot $name) `
        -Destination (Join-Path $wiredRoot $name) -Force
}
$runsDir = Join-Path $wiredRoot "g7_runs"
$wiredFailurePath = Join-Path $runsDir ("g7_" + $wiredTag + "_failure.json")
$wiredPreflightPath = Join-Path $runsDir ("g7_" + $wiredTag + "_memory_preflight.json")
foreach ($path in @($wiredFailurePath, $wiredPreflightPath)) {
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Force
    }
}

$scriptPath = Join-Path $wiredRoot "g7_measure.ps1"
$previousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
try {
    [Environment]::SetEnvironmentVariable("G7_TEST_MOCK_AVAILABLE_GIB", "40", "Process")
    $wiredOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass `
        -File $scriptPath `
        -Tag $wiredTag `
        -GateKind structural-safety `
        -SkipSystemQuiescencePreflight `
        -MinimumAvailableGiB 43.875 2>&1
    $wiredExitCode = $LASTEXITCODE
} finally {
    [Environment]::SetEnvironmentVariable("G7_TEST_MOCK_AVAILABLE_GIB", $null, "Process")
    $ErrorActionPreference = $previousErrorActionPreference
}
Assert-True ($wiredExitCode -ne 0) "wired refusal path returned a zero exit code"
Assert-True (($wiredOutput | Out-String) -match "RAM admission refused launch") `
    "wired refusal path did not throw the admission message"
Assert-True (Test-Path -LiteralPath $wiredFailurePath -PathType Leaf) `
    "wired refusal path did not write the failure artifact"

$wiredFailure = Get-Content -LiteralPath $wiredFailurePath -Raw | ConvertFrom-Json
Assert-True ($wiredFailure.reason -eq "ram-admission-refused") `
    "wired failure artifact used the wrong reason"
Assert-True ($wiredFailure.PSObject.Properties["required_gib"] -ne $null) `
    "wired failure artifact is missing required_gib"
Assert-True ($wiredFailure.PSObject.Properties["available_gib"] -ne $null) `
    "wired failure artifact is missing available_gib"
Assert-True ($wiredFailure.PSObject.Properties["decision"] -ne $null) `
    "wired failure artifact is missing decision"
Assert-True ([math]::Abs([double]$wiredFailure.required_gib - 43.875) -lt 0.000001) `
    "wired failure artifact reported the wrong required_gib"
Assert-True ([math]::Abs([double]$wiredFailure.available_gib - 40.0) -lt 0.000001) `
    "wired failure artifact reported the wrong available_gib"
Assert-True ($wiredFailure.decision -eq "refuse") `
    "wired failure artifact reported the wrong decision"
Assert-True ([math]::Abs([double]$wiredFailure.dynamic_arena_gib - 0.0) -lt 0.000001) `
    "wired failure artifact omitted dynamic_arena_gib"
Assert-True ([math]::Abs([double]$wiredFailure.q1_0_arena_gb - 0.0) -lt 0.000001) `
    "wired failure artifact omitted q1_0_arena_gb"
Assert-True ($wiredFailure.q1_0_promotion_ssd_wrap -eq $false) `
    "wired failure artifact omitted q1_0_promotion_ssd_wrap"
Assert-True ([math]::Abs([double]$wiredFailure.q1_0_iq2_pinned_gib - 1.5) -lt 0.000001) `
    "wired failure artifact omitted q1_0_iq2_pinned_gib"

$skipTag = "g130_m4_f9_ram_admission_skip_test"
$skipFailurePath = Join-Path $runsDir ("g7_" + $skipTag + "_failure.json")
$skipPreflightPath = Join-Path $runsDir ("g7_" + $skipTag + "_memory_preflight.json")
foreach ($path in @($skipFailurePath, $skipPreflightPath)) {
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Force
    }
}

$previousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
try {
    $skipOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass `
        -File $scriptPath `
        -Tag $skipTag `
        -GateKind structural-safety `
        -SkipMemoryPreflight `
        -SkipSystemQuiescencePreflight `
        -MinimumAvailableGiB 43.875 2>&1
    $skipExitCode = $LASTEXITCODE
} finally {
    $ErrorActionPreference = $previousErrorActionPreference
}
Assert-True (($skipOutput | Out-String) -notmatch "RAM admission refused launch") `
    "operator skip was refused by RAM admission"
Assert-True (Test-Path -LiteralPath $skipPreflightPath -PathType Leaf) `
    "operator skip did not write the memory preflight receipt"

$skipPreflight = Get-Content -LiteralPath $skipPreflightPath -Raw | ConvertFrom-Json
Assert-True ($skipPreflight.decision -eq "skipped_by_operator") `
    "operator skip receipt reported the wrong decision"
Assert-True ([math]::Abs([double]$skipPreflight.required_gib - 43.875) -lt 0.000001) `
    "operator skip receipt reported the wrong required_gib"
Assert-True ($null -eq $skipPreflight.available_gib) `
    "operator skip receipt reported availability"
if (Test-Path -LiteralPath $skipFailurePath -PathType Leaf) {
    $skipFailure = Get-Content -LiteralPath $skipFailurePath -Raw | ConvertFrom-Json
    Assert-True ($skipFailure.reason -ne "ram-admission-refused") `
        "operator skip wrote a RAM admission failure"
    Assert-True ($skipFailure.decision -eq "skipped_by_operator") `
        "operator skip failure artifact reported the wrong decision"
}

Write-Host "G130 M4/F9 RAM admission executable tests passed"
