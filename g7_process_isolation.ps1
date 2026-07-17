# G7 process-isolation helpers (ASCII only, PS 5.1 safe)

function Get-G7MaintenanceProcessConflicts {
    param(
        [Parameter(Mandatory=$true)][object[]]$Processes,
        [Parameter(Mandatory=$true)]
        [ValidateSet("benchmark", "structural-safety", "quality")]
        [string]$GateKind
    )

    if ($GateKind -eq "structural-safety") {
        return @()
    }

    $blockedNames = @("defrag.exe")
    @($Processes | Where-Object {
        $blockedNames -contains ([string]$_.Name).ToLowerInvariant()
    } | ForEach-Object {
        $createdUtc = ""
        try {
            if ($null -ne $_.CreationDate) {
                $createdUtc = ([DateTime]$_.CreationDate).ToUniversalTime().ToString("o")
            }
        } catch {
            $createdUtc = ""
        }
        [pscustomobject]@{
            pid = [int]$_.ProcessId
            parent_pid = [int]$_.ParentProcessId
            name = [string]$_.Name
            executable_path = [string]$_.ExecutablePath
            command_line = [string]$_.CommandLine
            created_utc = $createdUtc
            conflict_type = "storage-maintenance"
            refusal_reason = "storage-maintenance-active"
        }
    })
}
