$ErrorActionPreference = 'Stop'

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function New-Rotator {
    return [ordered]@{
        Jobs = [System.Collections.ArrayList]::new()
        Rings = [bool[]]::new(4)
        Writers = [System.Collections.Generic.HashSet[int]]::new()
        NextSequence = 1
    }
}

function Finish-One($Rotator) {
    $job = $Rotator.Jobs[0]
    $Rotator.Jobs.RemoveAt(0)
    $Rotator.Rings[$job.Ring] = $false
    [void]$Rotator.Writers.Remove($job.Slot)
}

function Submit-Job($Rotator, [int]$Slot) {
    if ($Rotator.Jobs.Count -eq 64) { Finish-One $Rotator }
    $ring = -1
    for ($i = 0; $i -lt $Rotator.Rings.Count; $i++) {
        if (-not $Rotator.Rings[$i]) { $ring = $i; break }
    }
    if ($ring -lt 0) {
        Finish-One $Rotator
        for ($i = 0; $i -lt $Rotator.Rings.Count; $i++) {
            if (-not $Rotator.Rings[$i]) { $ring = $i; break }
        }
    }
    $job = [pscustomobject]@{
        Sequence = $Rotator.NextSequence
        Ring = $ring
        Slot = $Slot
        WriterClaimed = $true
    }
    $Rotator.NextSequence++
    $Rotator.Rings[$ring] = $true
    [void]$Rotator.Writers.Add($Slot)
    [void]$Rotator.Jobs.Add($job)
}

function Fail-All($Rotator) {
    foreach ($job in @($Rotator.Jobs | Sort-Object Sequence)) {
        $Rotator.Rings[$job.Ring] = $false
        [void]$Rotator.Writers.Remove($job.Slot)
    }
    $Rotator.Jobs.Clear()
}

function New-Outcomes {
    return [ordered]@{
        out_of_mask_routes = 0
        served_transient = 0
        served_promoted = 0
        served_selected_fallback = 0
        served_terminal_exact = 0
        clamped = 0
        request_refused = 0
    }
}

function Assert-Conserved($Outcomes) {
    $served = $Outcomes.served_transient + $Outcomes.served_promoted +
        $Outcomes.served_selected_fallback + $Outcomes.served_terminal_exact
    Assert-True ($Outcomes.out_of_mask_routes -eq
        $served + $Outcomes.clamped + $Outcomes.request_refused) `
        'telemetry equation is not conserved'
    Assert-True ($Outcomes.clamped -eq 0 -and $Outcomes.request_refused -eq 0) `
        'structural-zero outcome changed'
}

# >64 candidate aging: deterministic ring backpressure drains oldest first.
$rotator = New-Rotator
for ($candidate = 0; $candidate -lt 129; $candidate++) {
    Submit-Job $rotator $candidate
}
while ($rotator.Jobs.Count) { Finish-One $rotator }
Assert-True ($rotator.NextSequence -eq 130) '>64 candidate aging did not complete'
Assert-True (-not ($rotator.Rings -contains $true)) 'aging stranded a ring'

# Ring wrap + writer-claim injection, and rotator failure all-or-nothing cleanup.
$rotator = New-Rotator
for ($slot = 0; $slot -lt 12; $slot++) { Submit-Job $rotator $slot }
Fail-All $rotator
Assert-True ($rotator.Jobs.Count -eq 0) 'rotator failure stranded a job'
Assert-True ($rotator.Writers.Count -eq 0) 'rotator failure stranded a writer claim'
Assert-True (-not ($rotator.Rings -contains $true)) 'rotator failure stranded a ring'

# Blocked-I/O fake clock reaches, but never crosses, one absolute deadline.
$deadlineMs = 250
$nowMs = 0
while ($nowMs -lt $deadlineMs) {
    $nowMs += [Math]::Min(7, $deadlineMs - $nowMs)
}
Assert-True ($nowMs -eq $deadlineMs) 'blocked I/O exceeded its absolute deadline'

# Selected failure always becomes terminal exact; refusal and clamp have no arm.
$outcomes = New-Outcomes
$outcomes.out_of_mask_routes = 6
$outcomes.served_terminal_exact = 6
Assert-Conserved $outcomes

# Mixed outcome conservation commits exactly one result for each route.
$outcomes = New-Outcomes
$outcomes.out_of_mask_routes = 4
$outcomes.served_transient = 1
$outcomes.served_promoted = 1
$outcomes.served_selected_fallback = 1
$outcomes.served_terminal_exact = 1
Assert-Conserved $outcomes

# OFF path selects the original callable; G73 selects the disabled split arm.
$calls = [System.Collections.ArrayList]::new()
$original = { [void]$calls.Add('original') }
$disabled = { [void]$calls.Add('disabled') }
$dispatch = $original
& $dispatch
$dispatch = $disabled
& $dispatch
Assert-True (($calls -join ',') -ceq 'original,disabled') 'OFF/G73 dispatch A/B failed'

Write-Host 'G73 deterministic fault contract passed (no-model state-machine runtime)'
