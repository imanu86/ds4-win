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
$priorSelftest = $env:DS4_G73_OPEN_SELFTEST
try {
    $env:DS4_G73_OPEN_SELFTEST = '1'
    & $ExecutablePath
    if ($LASTEXITCODE -ne 0) { throw 'G73 in-process production self-test failed' }
} finally {
    if ($null -eq $priorSelftest) {
        Remove-Item Env:\DS4_G73_OPEN_SELFTEST -ErrorAction SilentlyContinue
    } else {
        $env:DS4_G73_OPEN_SELFTEST = $priorSelftest
    }
}
& $ExecutablePath --help | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'ds4_server --help failed' }

if ($StaticOnly) {
    Write-Host 'G73 measured-gate prerequisites passed (static-only).'
    Write-Host 'RUNTIME-PENDING: real-model exact-H2D timing, sustained >64-candidate rotation pressure, and OFF/G73 A/B.'
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

function Invoke-Gate([int]$ListenPort, [string]$Prompt, [int]$MaxTokens = 1) {
    $body = @{
        model = 'deepseek-chat'
        prompt = $Prompt
        max_tokens = $MaxTokens
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
    $off = Invoke-Gate $Port 'Return exactly one word: blue'
    Stop-GateServer $offProcess
    $offProcess = $null

    . (Join-Path $root 'tests\g73_open.env.ps1')
    $g73Process = Start-GateServer 'g73' ($Port + 1)
    $g73 = Invoke-Gate ($Port + 1) 'Return exactly one word: blue'
    if ($off.choices[0].text -cne $g73.choices[0].text) {
        throw 'OFF/G73 deterministic one-token A/B differs'
    }

    # One sustained decode creates >64 route candidates inside a single live
    # rotation window (6 routes/token), instead of resetting pressure through
    # singleton requests. The stderr checks below require real rotator evidence.
    $sustained = Invoke-Gate ($Port + 1) `
        'Write a numbered list from 1 through 128, one short item per number.' 128
    if ($sustained.usage.completion_tokens -ne 128) {
        throw "sustained gate generated $($sustained.usage.completion_tokens) tokens; expected 128"
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
if ($g73Log -notmatch 'out_of_mask_routes=' -or
    $g73Log -notmatch 'q1-0-ssd-wrap-wave') {
    throw 'sustained request produced no G73 attribution/rotator evidence'
}
if ($g73Log -match 'rotator.*failed' -and $g73Log -notmatch 'rotator detached') {
    throw 'rotator failed without bounded detach evidence'
}

Write-Host 'G73 measured runtime gate passed: sustained >64-candidate pressure, real rotator evidence, no refusal/clamp, telemetry assertion, OFF/G73 one-token A/B.'
Write-Host 'RUNTIME-PENDING: instrumented exact-H2D timing and genuine CUDA device-loss injection.'
