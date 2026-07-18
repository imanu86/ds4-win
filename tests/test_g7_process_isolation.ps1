$ErrorActionPreference = "Stop"

$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $repo "g7_process_isolation.ps1")

function Assert-Equal($Expected, $Actual, [string]$Message) {
    if ($Expected -ne $Actual) {
        throw "$Message (expected=$Expected actual=$Actual)"
    }
}

$processes = @(
    [pscustomobject]@{
        ProcessId = 101
        ParentProcessId = 10
        Name = "Defrag.exe"
        ExecutablePath = "C:\Windows\System32\Defrag.exe"
        CommandLine = $null
        CreationDate = [DateTime]::UtcNow
    },
    [pscustomobject]@{
        ProcessId = 102
        ParentProcessId = 10
        Name = "notepad.exe"
        ExecutablePath = "C:\Windows\System32\notepad.exe"
        CommandLine = "notepad.exe"
        CreationDate = [DateTime]::UtcNow
    }
)

$benchmark = @(Get-G7MaintenanceProcessConflicts -Processes $processes -GateKind benchmark)
Assert-Equal 1 $benchmark.Count "benchmark must reject active storage maintenance"
Assert-Equal "storage-maintenance-active" $benchmark[0].refusal_reason "wrong refusal reason"
Assert-Equal 101 $benchmark[0].pid "wrong conflict pid"

$quality = @(Get-G7MaintenanceProcessConflicts -Processes $processes -GateKind quality)
Assert-Equal 1 $quality.Count "quality must reject active storage maintenance"

$structural = @(Get-G7MaintenanceProcessConflicts -Processes $processes -GateKind structural-safety)
Assert-Equal 0 $structural.Count "structural safety must remain available"

$unrelated = @(Get-G7MaintenanceProcessConflicts -Processes @($processes[1]) -GateKind benchmark)
Assert-Equal 0 $unrelated.Count "unrelated process must not block launch"

$opaquePowerShell = [pscustomobject]@{
    ProcessId = 201
    ParentProcessId = 20
    Name = "powershell.exe"
    ExecutablePath = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
    CommandLine = ""
    CommandLineStatus = "unavailable"
    CreationDate = [DateTime]::UtcNow
}

$opaqueBenchmark = @(Get-G7MaintenanceProcessConflicts -Processes @($opaquePowerShell) -GateKind benchmark)
Assert-Equal 1 $opaqueBenchmark.Count "benchmark must reject opaque powershell fallback rows"
Assert-Equal "opaque-powershell" $opaqueBenchmark[0].conflict_type "wrong opaque conflict type"
Assert-Equal "powershell-command-line-unavailable" $opaqueBenchmark[0].refusal_reason "wrong opaque refusal reason"

$opaqueQuality = @(Get-G7MaintenanceProcessConflicts -Processes @($opaquePowerShell) -GateKind quality)
Assert-Equal 1 $opaqueQuality.Count "quality must reject opaque powershell fallback rows"

$opaqueStructural = @(Get-G7MaintenanceProcessConflicts -Processes @($opaquePowerShell) -GateKind structural-safety)
Assert-Equal 0 $opaqueStructural.Count "structural safety must not be blocked by opaque powershell alone"

$visiblePowerShell = [pscustomobject]@{
    ProcessId = 202
    ParentProcessId = 20
    Name = "pwsh.exe"
    ExecutablePath = "C:\Program Files\PowerShell\7\pwsh.exe"
    CommandLine = "pwsh.exe -File g7_measure.ps1"
    CommandLineStatus = "native-peb"
    CreationDate = [DateTime]::UtcNow
}

$visibleMaintenance = @(Get-G7MaintenanceProcessConflicts -Processes @($visiblePowerShell) -GateKind benchmark)
Assert-Equal 0 $visibleMaintenance.Count "visible powershell must be left to ds4-or-harness regex conflict checks"

$nativeParents = Get-G7NativeParentProcessMap
if ($nativeParents.Count -le 0) {
    throw "native Toolhelp fallback did not enumerate process parents"
}
if (-not $nativeParents.ContainsKey([int]$PID)) {
    throw "native Toolhelp fallback did not include current process"
}

$currentCommandLine = Get-G7NativeCommandLine -ProcessId ([int]$PID)
if ([string]::IsNullOrWhiteSpace($currentCommandLine)) {
    throw "native command-line fallback did not read current powershell command line"
}

Write-Host "PASS: G7 maintenance process isolation"
