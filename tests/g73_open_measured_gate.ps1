param(
    [string]$ModelPath,
    [string]$ExecutablePath,
    [int]$Port = 18073,
    [switch]$StaticOnly
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not $ExecutablePath) {
    $ExecutablePath = Join-Path $root 'build\Release\ds4_server.exe'
}
if (-not (Test-Path -LiteralPath $ExecutablePath -PathType Leaf)) {
    throw "ds4_server not found: $ExecutablePath"
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
    (Join-Path $root 'tests\test_g73_open_static.ps1')
if ($LASTEXITCODE -ne 0) { throw 'G73 static contract failed' }
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
    (Join-Path $root 'tests\test_g73_open_fault_model.ps1')
if ($LASTEXITCODE -ne 0) { throw 'G73 deterministic fault model failed' }
& $ExecutablePath --help | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'ds4_server --help failed' }

if ($StaticOnly) {
    Write-Host 'G73 measured-gate prerequisites passed (static-only).'
    Write-Host 'RUNTIME-PENDING: real-model CUDA I/O, rotator cancellation, and OFF/G73 A/B.'
    exit 0
}
if (-not $ModelPath -or -not (Test-Path -LiteralPath $ModelPath -PathType Leaf)) {
    throw 'Provide -ModelPath for the measured runtime gate, or use -StaticOnly.'
}

$outDir = Join-Path $root 'build\g73_open_measured_gate'
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

function Wait-Server([System.Diagnostics.Process]$Process, [int]$ListenPort) {
    $deadline = [DateTime]::UtcNow.AddMinutes(5)
    while ([DateTime]::UtcNow -lt $deadline) {
        if ($Process.HasExited) { throw "server exited during startup: $($Process.ExitCode)" }
        $client = New-Object System.Net.Sockets.TcpClient
        try {
            $pending = $client.BeginConnect('127.0.0.1', $ListenPort, $null, $null)
            if ($pending.AsyncWaitHandle.WaitOne(200) -and $client.Connected) { return }
        } finally {
            $client.Dispose()
        }
        Start-Sleep -Milliseconds 200
    }
    throw 'server startup deadline exceeded'
}

function Invoke-One([int]$ListenPort, [string]$Prompt) {
    $body = @{
        model = 'deepseek-chat'
        prompt = $Prompt
        max_tokens = 1
        temperature = 0
        stream = $false
    } | ConvertTo-Json -Compress
    return Invoke-RestMethod -Method Post `
        -Uri "http://127.0.0.1:$ListenPort/v1/completions" `
        -ContentType 'application/json' -Body $body -TimeoutSec 120
}

function Start-GateServer([string]$Tag, [int]$ListenPort) {
    $stdout = Join-Path $outDir "$Tag.stdout.log"
    $stderr = Join-Path $outDir "$Tag.stderr.log"
    $args = @('--model', "`"$ModelPath`"", '--cuda', '--host', '127.0.0.1',
        '--port', "$ListenPort", '--ctx', '4096', '--tokens', '1')
    $process = Start-Process -FilePath $ExecutablePath -ArgumentList $args `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr `
        -WindowStyle Hidden -PassThru
    Wait-Server $process $ListenPort
    return $process
}

function Stop-GateServer([System.Diagnostics.Process]$Process) {
    if ($Process -and -not $Process.HasExited) {
        Stop-Process -Id $Process.Id
        $Process.WaitForExit(10000) | Out-Null
    }
}

$offProcess = $null
$g73Process = $null
try {
    Remove-Item Env:\DS4_G73_OPEN -ErrorAction SilentlyContinue
    $offProcess = Start-GateServer 'off' $Port
    $off = Invoke-One $Port 'Return exactly one word: blue'
    Stop-GateServer $offProcess
    $offProcess = $null

    . (Join-Path $root 'tests\g73_open.env.ps1')
    $g73Process = Start-GateServer 'g73' ($Port + 1)
    $g73 = Invoke-One ($Port + 1) 'Return exactly one word: blue'
    if ($off.choices[0].text -cne $g73.choices[0].text) {
        throw 'OFF/G73 deterministic one-token A/B differs'
    }

    # More than 64 request boundaries exercises aging/backpressure without a
    # timing-based oracle; the stderr checks below reject hangs and refusals.
    for ($i = 0; $i -lt 72; $i++) {
        [void](Invoke-One ($Port + 1) "G73 aging probe $i. Reply OK.")
    }
} finally {
    Stop-GateServer $g73Process
    Stop-GateServer $offProcess
}

$g73Log = Get-Content -LiteralPath (Join-Path $outDir 'g73.stderr.log') -Raw
if ($g73Log -match 'request_refused=[1-9]' -or $g73Log -match 'clamped=[1-9]') {
    throw 'G73 emitted a refused or clamped route'
}
if ($g73Log -match 'telemetry conservation failure') {
    throw 'G73 telemetry conservation assertion fired'
}
if ($g73Log -match 'rotator.*failed' -and $g73Log -notmatch 'rotator detached') {
    throw 'rotator failed without bounded detach evidence'
}

Write-Host 'G73 measured runtime gate passed: 72-request aging, no refusal/clamp, telemetry assertion, OFF/G73 one-token A/B.'
Write-Host 'RUNTIME-PENDING: fault-forced blocked OS I/O and mid-claim CUDA rotator failures require the instrumented measured host.'
