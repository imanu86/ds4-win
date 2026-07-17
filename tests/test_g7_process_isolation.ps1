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

Write-Host "PASS: G7 maintenance process isolation"
