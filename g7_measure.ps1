# G7 selected-load measurement harness (ASCII only, PS 5.1 safe)
# Usage: powershell -File g7_measure.ps1 -MaxTokens 8 -TimeoutSec 900 -Tag new [-NoSelectedLoad]
param(
    [int]$MaxTokens = 8,
    [int]$TimeoutSec = 900,
    [string]$Tag = "run",
    [switch]$NoSelectedLoad,
    [switch]$Warmup,
    [int]$ReserveMB = 2048,
    [int]$BudgetGB = 28,
    [string]$ModelPath = "D:\ds4-models\ds4-2bit.gguf",
    [int]$Port = 8000
)

$ErrorActionPreference = "Stop"
$exe   = "C:\Users\imanu\AppData\Local\ds4-win-work\build\Release\ds4_server.exe"
$model = $ModelPath
$outdir = "C:\Users\imanu\AppData\Local\ds4-win-work\g7_runs"
New-Item -ItemType Directory -Force -Path $outdir | Out-Null
$stderrLog = Join-Path $outdir ("g7_" + $Tag + "_stderr.log")
$stdoutLog = Join-Path $outdir ("g7_" + $Tag + "_stdout.log")
if (Test-Path $stderrLog) { Remove-Item $stderrLog -Force }
if (Test-Path $stdoutLog) { Remove-Item $stdoutLog -Force }

$env:CUDA_PATH = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.6"
$env:PATH = "$env:CUDA_PATH\bin;" + $env:PATH
$env:DS4_CUDA_STREAM_FROM_RAM_MASKED_BUDGET_GB = "$BudgetGB"
$env:DS4_CUDA_STREAM_RESERVE_MB = "$ReserveMB"
$env:DS4_CUDA_WEIGHT_CACHE_VERBOSE = "1"
if ($NoSelectedLoad) { $env:DS4_CUDA_MOE_NO_SELECTED_LOAD = "1" }
else { Remove-Item Env:\DS4_CUDA_MOE_NO_SELECTED_LOAD -ErrorAction SilentlyContinue }

# Kill any lingering server holding the port/exe
Get-Process ds4_server -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500

$argList = @("-m", $model, "--cuda", "-c", "256", "-n", "$MaxTokens", "--host", "127.0.0.1", "--port", "$Port")
Write-Host ("[g7] launching: " + $exe + " " + ($argList -join " "))
Write-Host ("[g7] NoSelectedLoad=" + $NoSelectedLoad + " MaxTokens=" + $MaxTokens)

$proc = Start-Process -FilePath $exe -ArgumentList $argList -NoNewWindow -PassThru `
    -RedirectStandardError $stderrLog -RedirectStandardOutput $stdoutLog
$launchTime = Get-Date

# Poll TCP for ready (server opens the port only after model load)
$ready = $false
$deadline = (Get-Date).AddSeconds($TimeoutSec)
while ((Get-Date) -lt $deadline) {
    if ($proc.HasExited) { Write-Host ("[g7] server EXITED early, code=" + $proc.ExitCode); break }
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $c.Connect("127.0.0.1", $Port)
        if ($c.Connected) { $ready = $true; $c.Close(); break }
    } catch { Start-Sleep -Milliseconds 500 }
}
$readyTime = Get-Date
$loadSec = ($readyTime - $launchTime).TotalSeconds
if (-not $ready) {
    Write-Host ("[g7] NOT READY within timeout (load " + [int]$loadSec + "s). Aborting.")
    if (-not $proc.HasExited) { $proc.Kill() }
    Write-Host "=== stderr tail ==="; if (Test-Path $stderrLog) { Get-Content $stderrLog -Tail 30 }
    exit 2
}
Write-Host ("[g7] server READY in " + [int]$loadSec + "s")

$body = @{
    model = "deepseek-chat"
    messages = @(@{ role = "user"; content = "Hi" })
    max_tokens = $MaxTokens
    temperature = 0
    think = $false
} | ConvertTo-Json -Depth 5

$content = ""
$genSec = 0.0
$httpOk = $false
$warmSec = 0.0
$uri = "http://127.0.0.1:" + $Port + "/v1/chat/completions"
try {
    if ($Warmup) {
        $tw = Get-Date
        $null = Invoke-RestMethod -Uri $uri -Method Post -ContentType "application/json" -Body $body -TimeoutSec $TimeoutSec
        $warmSec = ((Get-Date) - $tw).TotalSeconds
        Write-Host ("[g7] warmup pass done in " + [math]::Round($warmSec,2) + "s")
    }
    $t0 = Get-Date
    $resp = Invoke-RestMethod -Uri $uri -Method Post -ContentType "application/json" -Body $body -TimeoutSec $TimeoutSec
    $genSec = ((Get-Date) - $t0).TotalSeconds
    $content = $resp.choices[0].message.content
    $httpOk = $true
} catch {
    Write-Host ("[g7] request FAILED: " + $_.Exception.Message)
}

if (-not $proc.HasExited) { $proc.Kill() }
Start-Sleep -Milliseconds 500

# Analyze stderr
$evicts = 0; $selLoads = 0; $lastSel = ""; $streamsExpert = 0; $streamsHot = 0
if (Test-Path $stderrLog) {
    $lines = Get-Content $stderrLog
    $evLine = $lines | Where-Object { $_ -match "evicts=(\d+)" } | Select-Object -Last 1
    if ($evLine -and $evLine -match "evicts=(\d+)") { $evicts = [int]$Matches[1] }
    $selLines = $lines | Where-Object { $_ -match "MoE selected-load" }
    $selLoads = ($selLines | Measure-Object).Count
    if ($selLines) { $lastSel = ($selLines | Select-Object -Last 1) }
    $fd = $lines | Where-Object { $_ -match "fd-cached " }
    $streamsExpert = ($fd | Where-Object { $_ -match "fd-cached moe_" } | Measure-Object).Count
    $streamsHot = ($fd | Measure-Object).Count - $streamsExpert
}

$tokPerSec = 0.0
if ($genSec -gt 0 -and $MaxTokens -gt 0) { $tokPerSec = [math]::Round($MaxTokens / $genSec, 4) }

Write-Host ""
Write-Host "================ G7 RESULT ($Tag) ================"
Write-Host ("http_ok       : " + $httpOk)
Write-Host ("content       : [" + $content + "]")
Write-Host ("load_sec      : " + [math]::Round($loadSec,1))
Write-Host ("warm_sec      : " + [math]::Round($warmSec,2) + "  (warmup pass, discarded)")
Write-Host ("gen_sec       : " + [math]::Round($genSec,2) + "  (for " + $MaxTokens + " tokens)")
Write-Host ("tokens_per_sec: " + $tokPerSec)
Write-Host ("sec_per_token : " + [math]::Round(($(if($tokPerSec -gt 0){1/$tokPerSec}else{0})),2))
Write-Host ("evictions     : " + $evicts)
Write-Host ("streams_expert: " + $streamsExpert)
Write-Host ("streams_hot   : " + $streamsHot)
Write-Host ("selected_loads: " + $selLoads)
Write-Host ("last_sel_line : " + $lastSel)
Write-Host "=================================================="
