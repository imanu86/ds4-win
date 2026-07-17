$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$monitor = Join-Path $root "g7_runtime_monitor.ps1"
$harness = Join-Path $root "g7_measure.ps1"
$output = Join-Path $env:TEMP ("ds4_runtime_pressure_guard_" + [guid]::NewGuid().ToString("N") + ".jsonl")
$child = $null

try {
    $child = Start-Process -FilePath powershell.exe -ArgumentList @(
        "-NoProfile", "-Command", "Start-Sleep -Seconds 30"
    ) -WindowStyle Hidden -PassThru
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $monitor `
        -TargetProcessId $child.Id -OutputPath $output -IntervalMs 250 `
        -MinimumAvailableGiB 0 -MaximumDiskQueueLength 100000 `
        -HardMinimumAvailableGiB 1024 `
        -MaximumPagesOutputPerSecond 0 `
        -MinimumPrivateWorkingSetRatio 2.0 -PrivateWorkingSetMinimumGiB 0 `
        -ContaminationSamples 1

    $child.Refresh()
    if (-not $child.HasExited) {
        throw "Residency guard did not terminate the target process"
    }
    $samples = @(Get-Content -LiteralPath $output | ForEach-Object { $_ | ConvertFrom-Json })
    if ($samples.Count -lt 1) { throw "Runtime monitor emitted no samples" }
    $abort = @($samples | Where-Object { $_.contamination_abort })[-1]
    if (-not $abort) { throw "Runtime monitor did not emit an abort sample" }
    if (@($abort.contamination_reasons) -notcontains "private-working-set-collapse") {
        throw "Runtime monitor did not identify the residency-collapse reason"
    }
    if (@($abort.contamination_reasons) -notcontains "hard-low-memory") {
        throw "Runtime monitor did not identify the hard-low-memory reason"
    }
    if (-not $abort.system_memory_pressure.seen) {
        throw "Runtime monitor did not expose system memory-pressure counters"
    }
    if ($null -eq $abort.system_memory_pressure.pages_output_per_second) {
        throw "Runtime monitor page-output counter is missing"
    }
    if ((Get-Content -LiteralPath $harness -Raw) -notmatch
        'runtime-monitor-abort reasons=') {
        throw "Measurement harness does not report monitor aborts during HTTP failures"
    }
    Write-Host "runtime pressure guard test: PASS"
} finally {
    if ($child) {
        $child.Refresh()
        if (-not $child.HasExited) {
            Stop-Process -Id $child.Id -Force -ErrorAction SilentlyContinue
        }
        $child.Dispose()
    }
    Remove-Item -LiteralPath $output -Force -ErrorAction SilentlyContinue
}
