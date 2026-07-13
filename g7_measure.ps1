# G7 selected-load measurement harness (ASCII only, PS 5.1 safe)
# Usage: powershell -File g7_measure.ps1 -MaxTokens 8 -TimeoutSec 900 -Tag new [-NoSelectedLoad]
param(
    [int]$MaxTokens = 8,
    [int]$Repeats = 1,
    [int]$TimeoutSec = 900,
    [string]$Tag = "run",
    [string]$Prompt = "Hi",
    [switch]$NoSelectedLoad,
    [switch]$Warmup,
    [switch]$Diagnostics,
    [int]$ReserveMB = 2048,
    [int]$BudgetGB = 28,
    [ValidateSet(1, 2, 4)][int]$IoQD = 1,
    [ValidateRange(0, 512)][int]$ExpertCacheN = 0,
    [ValidateRange(0.0, 6.0)][double]$ExpertCacheReserveGB = 0.5,
    [ValidateSet("lru", "layer-top1")][string]$ExpertCachePolicy = "lru",
    [switch]$ExpertCacheStats,
    [ValidateRange(1, 1000000)][int]$ExpertCacheStatsInterval = 128,
    [switch]$OverlapShared,
    [switch]$OverlapSharedFull,
    [switch]$DisableSharedDownFusion,
    [switch]$SpexDryRun,
    [string]$SpexFile = "",
    [ValidateRange(0, 6)][int]$SpexCap = 0,
    [ValidateSet("resident", "score", "topk", "full")][string]$SpexStage = "full",
    [switch]$SpexFusedTopK,
    [ValidateSet(1, 2, 4, 8)][int]$SpexRingSlots = 1,
    [ValidateRange(1, 1000000)][int]$SpexStatsEvery = 1000000,
    [string]$ExpectedContentSHA256 = "",
    [string]$ModelPath = "D:\ds4-models\ds4-2bit.gguf",
    [int]$Port = 8000
)

$ErrorActionPreference = "Stop"
if ($ExpectedContentSHA256 -and $ExpectedContentSHA256 -notmatch '^[0-9a-fA-F]{64}$') {
    throw "ExpectedContentSHA256 must be a 64-character hexadecimal SHA-256"
}
$exe   = Join-Path $PSScriptRoot "build\Release\ds4_server.exe"
$model = $ModelPath
$outdir = Join-Path $PSScriptRoot "g7_runs"
New-Item -ItemType Directory -Force -Path $outdir | Out-Null
$stderrLog = Join-Path $outdir ("g7_" + $Tag + "_stderr.log")
$stdoutLog = Join-Path $outdir ("g7_" + $Tag + "_stdout.log")
if (Test-Path $stderrLog) { Remove-Item $stderrLog -Force }
if (Test-Path $stdoutLog) { Remove-Item $stdoutLog -Force }

$env:CUDA_PATH = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.6"
$env:PATH = "$env:CUDA_PATH\bin;" + $env:PATH
$env:DS4_CUDA_STREAM_FROM_RAM_MASKED_BUDGET_GB = "$BudgetGB"
$env:DS4_CUDA_STREAM_RESERVE_MB = "$ReserveMB"
if ($Diagnostics) {
    $env:DS4_CUDA_WEIGHT_CACHE_VERBOSE = "1"
    $env:DS4_CUDA_SEL_PROFILE = "1"
} else {
    Remove-Item Env:\DS4_CUDA_WEIGHT_CACHE_VERBOSE -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_CUDA_SEL_PROFILE -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_METAL_DECODE_STAGE_PROFILE -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_CUDA_MOE_PROFILE -ErrorAction SilentlyContinue
}
if ($NoSelectedLoad) { $env:DS4_CUDA_MOE_NO_SELECTED_LOAD = "1" }
else { Remove-Item Env:\DS4_CUDA_MOE_NO_SELECTED_LOAD -ErrorAction SilentlyContinue }
if ($IoQD -gt 1) { $env:DS4_CUDA_MOE_IO_QD = "$IoQD" }
else { Remove-Item Env:\DS4_CUDA_MOE_IO_QD -ErrorAction SilentlyContinue }
if ($ExpertCacheN -gt 0) {
    $env:DS4_CUDA_STREAMING_EXPERT_CACHE_N = "$ExpertCacheN"
    $env:DS4_CUDA_STREAMING_EXPERT_CACHE_RESERVE_GB = $ExpertCacheReserveGB.ToString("0.###", [Globalization.CultureInfo]::InvariantCulture)
    $env:DS4_CUDA_MOE_CACHE_POLICY = $ExpertCachePolicy
} else {
    Remove-Item Env:\DS4_CUDA_STREAMING_EXPERT_CACHE_N -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_CUDA_STREAMING_EXPERT_CACHE_RESERVE_GB -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_CUDA_MOE_CACHE_POLICY -ErrorAction SilentlyContinue
}
if ($ExpertCacheStats) {
    $env:DS4_CUDA_MOE_CACHE_STATS = "1"
    $env:DS4_CUDA_MOE_CACHE_STATS_INTERVAL = "$ExpertCacheStatsInterval"
} else {
    Remove-Item Env:\DS4_CUDA_MOE_CACHE_STATS -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_CUDA_MOE_CACHE_STATS_INTERVAL -ErrorAction SilentlyContinue
}
if ($OverlapShared) { $env:DS4_CUDA_MOE_OVERLAP_SHARED = "1" }
else { Remove-Item Env:\DS4_CUDA_MOE_OVERLAP_SHARED -ErrorAction SilentlyContinue }
if ($OverlapSharedFull) { $env:DS4_CUDA_MOE_OVERLAP_SHARED_FULL = "1" }
else { Remove-Item Env:\DS4_CUDA_MOE_OVERLAP_SHARED_FULL -ErrorAction SilentlyContinue }
if ($DisableSharedDownFusion) { $env:DS4_METAL_DISABLE_SHARED_DOWN_HC_FUSION = "1" }
else { Remove-Item Env:\DS4_METAL_DISABLE_SHARED_DOWN_HC_FUSION -ErrorAction SilentlyContinue }
if ($SpexDryRun) {
    if (-not $SpexFile -or -not (Test-Path -LiteralPath $SpexFile)) {
        throw "SpexDryRun requires an existing SpexFile"
    }
    $env:DS4_SPEX_HIDDEN_GPU_DRY_RUN = "1"
    $env:DS4_SPEX_FILE = $SpexFile
    $env:DS4_SPEX_CAP = "$(if ($SpexCap -gt 0) { $SpexCap } else { 6 })"
    $env:DS4_SPEX_AB_STAGE = $SpexStage
    if ($SpexFusedTopK) { $env:DS4_SPEX_FUSED_TOPK = "1" }
    else { Remove-Item Env:\DS4_SPEX_FUSED_TOPK -ErrorAction SilentlyContinue }
    $env:DS4_SPEX_RING_SLOTS = "$SpexRingSlots"
    $env:DS4_SPEX_DRY_RUN_STATS_EVERY = "$SpexStatsEvery"
} else {
    Remove-Item Env:\DS4_SPEX_HIDDEN_GPU_DRY_RUN -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_SPEX_FILE -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_SPEX_CAP -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_SPEX_AB_STAGE -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_SPEX_FUSED_TOPK -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_SPEX_RING_SLOTS -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_SPEX_DRY_RUN_STATS_EVERY -ErrorAction SilentlyContinue
}

if ($Repeats -lt 1) { throw "Repeats must be >= 1" }
$env:DS4_BENCH_EXIT_AFTER_REQUESTS = "$(if ($Warmup) { $Repeats + 1 } else { $Repeats })"
if ($SpexFusedTopK -and -not $SpexDryRun) { throw "SpexFusedTopK requires SpexDryRun" }
if ($SpexFusedTopK -and $SpexStage -notin @("topk", "full")) { throw "SpexFusedTopK requires the topk or full stage" }
if ($SpexRingSlots -gt 1 -and (-not $SpexDryRun -or $SpexStage -ne "full")) { throw "SpexRingSlots > 1 requires the full SpexDryRun stage" }
if ($OverlapShared -and $OverlapSharedFull) { throw "Select only one overlap policy" }
if (($OverlapShared -or $OverlapSharedFull) -and $NoSelectedLoad) { throw "Overlap is incompatible with NoSelectedLoad" }
if (($OverlapShared -or $OverlapSharedFull) -and $ExpertCacheN -gt 0) { throw "Overlap is incompatible with ExpertCacheN > 0" }
$existing = Get-Process ds4_server -ErrorAction SilentlyContinue
if ($existing) {
    throw "Another ds4_server process is active; refusing to stop a server owned by another task."
}

# Capture provenance before the process starts so a concurrent edit cannot be
# attributed retroactively to a completed measurement.
$headAtStart = git -C $PSScriptRoot rev-parse HEAD
$worktreeDirtyAtStart = [bool](git -C $PSScriptRoot status --porcelain)
$sourceHashAtStart = (Get-FileHash -Algorithm SHA256 (Join-Path $PSScriptRoot "ds4_cuda.cu")).Hash.ToLowerInvariant()
$ds4SourceHashAtStart = (Get-FileHash -Algorithm SHA256 (Join-Path $PSScriptRoot "ds4.c")).Hash.ToLowerInvariant()
$serverSourceHashAtStart = (Get-FileHash -Algorithm SHA256 (Join-Path $PSScriptRoot "ds4_server.c")).Hash.ToLowerInvariant()
$spexSourceHashAtStart = (Get-FileHash -Algorithm SHA256 (Join-Path $PSScriptRoot "ds4_spex_predict.c")).Hash.ToLowerInvariant()
$gpuHeaderHashAtStart = (Get-FileHash -Algorithm SHA256 (Join-Path $PSScriptRoot "ds4_gpu.h")).Hash.ToLowerInvariant()
$cmakeHashAtStart = (Get-FileHash -Algorithm SHA256 (Join-Path $PSScriptRoot "CMakeLists.txt")).Hash.ToLowerInvariant()
$exeHashAtStart = (Get-FileHash -Algorithm SHA256 $exe).Hash.ToLowerInvariant()
$harnessHashAtStart = (Get-FileHash -Algorithm SHA256 $PSCommandPath).Hash.ToLowerInvariant()
$spexHashAtStart = if ($SpexDryRun) { (Get-FileHash -Algorithm SHA256 -LiteralPath $SpexFile).Hash.ToLowerInvariant() } else { "" }
$modelInfoAtStart = Get-Item -LiteralPath $model
$promptBytes = [Text.Encoding]::UTF8.GetBytes($Prompt)
$promptHash = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($promptBytes)).Replace("-", "").ToLowerInvariant()

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
    messages = @(@{ role = "user"; content = $Prompt })
    max_tokens = $MaxTokens
    temperature = 0
    think = $false
} | ConvertTo-Json -Depth 5

$results = @()
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
    for ($i = 1; $i -le $Repeats; $i++) {
        $t0 = Get-Date
        $resp = Invoke-RestMethod -Uri $uri -Method Post -ContentType "application/json" -Body $body -TimeoutSec $TimeoutSec
        $genSec = ((Get-Date) - $t0).TotalSeconds
        $content = [string]$resp.choices[0].message.content
        $completionTokens = [int]$resp.usage.completion_tokens
        if ($completionTokens -le 0) {
            throw "Response $i did not report a positive usage.completion_tokens value"
        }
        $bytes = [Text.Encoding]::UTF8.GetBytes($content)
        $sha = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($bytes)).Replace("-", "").ToLowerInvariant()
        $results += [pscustomobject]@{
            repeat = $i
            seconds = [math]::Round($genSec, 6)
            completion_tokens = $completionTokens
            tokens_per_second = [math]::Round($completionTokens / $genSec, 6)
            content_sha256 = $sha
            content = $content
        }
        Write-Host ("[g7] repeat " + $i + ": " + $completionTokens + " tokens in " + [math]::Round($genSec, 3) + "s")
    }
    $httpOk = $true
} catch {
    Write-Host ("[g7] request FAILED: " + $_.Exception.Message)
}

if (-not $httpOk -and -not $proc.HasExited) { $proc.Kill() }
$stopped = $proc.WaitForExit(120000)
if (-not $stopped) {
    Write-Host "[g7] WARNING: graceful benchmark shutdown timed out; forcing owned server"
    if (-not $proc.HasExited) { $proc.Kill() }
    $stopped = $proc.WaitForExit(60000)
    if (-not $stopped) { throw "Owned ds4_server process did not exit after forced shutdown" }
}
Start-Sleep -Milliseconds 250

# Analyze stderr
$evicts = 0; $selLoads = 0; $lastSel = ""; $streamsExpert = 0; $streamsHot = 0
$observedIoQD = 1; $overlappedIoObserved = $false; $overlappedIoFallbacks = 0
$cacheCalls = 0; $cacheCapacity = 0; $cacheCount = 0; $cacheHits = 0; $cacheMisses = 0
$cacheAdmissions = 0; $cacheEvictions = 0; $cacheDirect = 0
$overlapSharedObserved = $false
$overlapSharedFullObserved = $false
$spexObserved = $false; $spexObservedStage = ""; $spexObservedCap = 0; $spexScheduled = 0; $spexReady = 0; $spexNotReady = 0
$spexLayers = 0; $spexActual = 0; $spexPredicted = 0; $spexHits = 0; $spexRecall = 0.0
$spexPrecision = 0.0; $spexNoActual = 0
$spexDisabled = $false; $spexFusedObserved = $false; $spexRingObserved = 0
$spexLate = 0; $spexRingFull = 0; $spexStale = 0
$serverRunsAll = @()
if (Test-Path $stderrLog) {
    $lines = Get-Content $stderrLog

    # Keep server-reported decode throughput separate from HTTP wall time, which
    # also includes prefill/TTFT. A request block starts at "prompt start" and
    # the last decoding line in that block is the cumulative decode average.
    $serverBlock = $null
    foreach ($line in $lines) {
        if ($line -match "prompt start") {
            if ($null -ne $serverBlock -and $serverBlock.generated_tokens -gt 0) {
                $serverRunsAll += $serverBlock
            }
            $serverBlock = [pscustomobject]@{
                request_index = $serverRunsAll.Count + 1
                generated_tokens = 0
                server_decode_seconds = 0.0
                server_chunk_tokens_per_second = 0.0
                server_avg_tokens_per_second = 0.0
                finish_reason = ""
                server_total_seconds = 0.0
                server_prefill_ttft_seconds = 0.0
            }
            continue
        }
        if ($null -eq $serverBlock) { continue }
        if ($line -match "gen=(\d+) decoding chunk=([0-9.]+) t/s avg=([0-9.]+) t/s ([0-9.]+)s") {
            $serverBlock.generated_tokens = [int]$Matches[1]
            $serverBlock.server_chunk_tokens_per_second = [double]$Matches[2]
            $serverBlock.server_avg_tokens_per_second = [double]$Matches[3]
            $serverBlock.server_decode_seconds = [double]$Matches[4]
        }
        if ($line -match "gen=(\d+) finish=([^ ]+) ([0-9.]+)s") {
            $serverBlock.generated_tokens = [int]$Matches[1]
            $serverBlock.finish_reason = $Matches[2]
            $serverBlock.server_total_seconds = [double]$Matches[3]
            $serverBlock.server_prefill_ttft_seconds = [math]::Max(0.0, $serverBlock.server_total_seconds - $serverBlock.server_decode_seconds)
        }
    }
    if ($null -ne $serverBlock -and $serverBlock.generated_tokens -gt 0) {
        $serverRunsAll += $serverBlock
    }

    $evLine = $lines | Where-Object { $_ -match "evicts=(\d+)" } | Select-Object -Last 1
    if ($evLine -and $evLine -match "evicts=(\d+)") { $evicts = [int]$Matches[1] }
    $selLines = $lines | Where-Object { $_ -match "MoE selected-load" }
    $selLoads = ($selLines | Measure-Object).Count
    if ($selLines) { $lastSel = ($selLines | Select-Object -Last 1) }
    $fd = $lines | Where-Object { $_ -match "fd-cached " }
    $streamsExpert = ($fd | Where-Object { $_ -match "fd-cached moe_" } | Measure-Object).Count
    $streamsHot = ($fd | Measure-Object).Count - $streamsExpert
    $ioLine = $lines | Where-Object { $_ -match "MoE overlapped read succeeded queue depth=(\d+)" } | Select-Object -Last 1
    if ($ioLine -and $ioLine -match "MoE overlapped read succeeded queue depth=(\d+)") {
        $observedIoQD = [int]$Matches[1]
        $overlappedIoObserved = $true
    }
    $overlappedIoFallbacks = ($lines | Where-Object { $_ -match "MoE overlapped read failed; selected-load fallback requested" } | Measure-Object).Count
    $overlapSharedObserved = [bool]($lines | Where-Object { $_ -match "CUDA MoE shared-overlap consumed" } | Select-Object -First 1)
    $overlapSharedFullObserved = [bool]($lines | Where-Object { $_ -match "CUDA MoE full shared-overlap consumed" } | Select-Object -First 1)
    $spexLine = $lines | Where-Object { $_ -match "\[spex-dry\]" } | Select-Object -Last 1
    $spexActiveLine = $lines | Where-Object { $_ -match "SPEX hidden GPU dry-run active" } | Select-Object -Last 1
    if ($spexActiveLine -and $spexActiveLine -match "fused=(\d+)") { $spexFusedObserved = ([int]$Matches[1] -ne 0) }
    if ($spexActiveLine -and $spexActiveLine -match "ring=(\d+)") { $spexRingObserved = [int]$Matches[1] }
    $spexDisabled = [bool]($lines | Where-Object { $_ -match "SPEX hidden dry-run disabled" } | Select-Object -First 1)
    if ($spexLine -and $spexLine -match "stage=([a-z]+) cap=(\d+) scheduled=(\d+) ready=(\d+) not_ready=(\d+) layers=(\d+) actual=(\d+) predicted=(\d+) hits=(\d+) recall=([0-9.]+) precision=([0-9.]+) no_actual=(\d+)") {
        $spexObserved = $true; $spexObservedStage = $Matches[1]; $spexObservedCap = [int]$Matches[2]
        $spexScheduled = [long]$Matches[3]; $spexReady = [long]$Matches[4]; $spexNotReady = [long]$Matches[5]
        $spexLayers = [long]$Matches[6]; $spexActual = [long]$Matches[7]; $spexPredicted = [long]$Matches[8]
        $spexHits = [long]$Matches[9]; $spexRecall = [double]$Matches[10]
        $spexPrecision = [double]$Matches[11]; $spexNoActual = [long]$Matches[12]
    }
    if ($spexLine -and $spexLine -match "ring=(\d+) late=(\d+) ring_full=(\d+) stale=(\d+)") {
        $spexRingObserved = [int]$Matches[1]; $spexLate = [long]$Matches[2]
        $spexRingFull = [long]$Matches[3]; $spexStale = [long]$Matches[4]
    }
    $cacheReadyLine = $lines | Where-Object { $_ -match "resident expert cache ready: (\d+)/(\d+) experts" } | Select-Object -Last 1
    if ($cacheReadyLine -and $cacheReadyLine -match "resident expert cache ready: (\d+)/(\d+) experts") {
        $cacheCapacity = [int]$Matches[1]
    }
    $cacheLine = $lines | Where-Object { $_ -match "\[moecache\]" } | Select-Object -Last 1
    if ($cacheLine -and $cacheLine -match "calls=(\d+) cap=(\d+) count=(\d+) hits=(\d+) misses=(\d+).*admissions=(\d+) evictions=(\d+) direct=(\d+)") {
        $cacheCalls = [long]$Matches[1]; $cacheCapacity = [int]$Matches[2]; $cacheCount = [int]$Matches[3]
        $cacheHits = [long]$Matches[4]; $cacheMisses = [long]$Matches[5]; $cacheAdmissions = [long]$Matches[6]
        $cacheEvictions = [long]$Matches[7]; $cacheDirect = [long]$Matches[8]
    }
}

if (-not $httpOk) { throw "Measurement failed: one or more HTTP requests did not complete" }
if (@($results).Count -ne $Repeats) {
    throw "Measurement failed: expected $Repeats results, observed $(@($results).Count)"
}

if ($SpexDryRun) {
    $expectedSpexCap = if ($SpexCap -gt 0) { $SpexCap } else { 6 }
    if (-not $spexObserved) { throw "SPEX measurement failed: no runtime counters observed" }
    if ($spexDisabled) { throw "SPEX measurement failed: runtime disabled itself" }
    if ($spexObservedStage -ne $SpexStage) { throw "SPEX measurement failed: observed stage mismatch" }
    if ($spexFusedObserved -ne [bool]$SpexFusedTopK) { throw "SPEX measurement failed: fused topK mismatch" }
    if ($spexRingObserved -ne $SpexRingSlots) { throw "SPEX measurement failed: ring slot mismatch" }
    if ($spexObservedCap -ne $expectedSpexCap) { throw "SPEX measurement failed: observed cap mismatch" }
    if ($SpexStage -eq "resident") {
        if ($spexScheduled -ne 0 -or $spexReady -ne 0) { throw "SPEX resident stage unexpectedly scheduled GPU work" }
    } elseif ($SpexStage -eq "full") {
        if ($spexScheduled -le 0 -or $spexReady -le 0 -or $spexReady -gt $spexScheduled) { throw "SPEX measurement failed: scheduled/ready counters are inconsistent" }
        if ($SpexRingSlots -eq 1 -and $spexScheduled -ne $spexReady) { throw "SPEX blocking measurement failed: scheduled/ready mismatch" }
        if ($SpexRingSlots -gt 1) {
            if ($spexRingFull -ne 0) { throw "SPEX ring measurement failed: ring-full events observed" }
            if (($spexReady + $spexLate) -ne $spexScheduled) { throw "SPEX ring measurement failed: predictions are not fully accounted" }
            if ($spexStale -ne $spexLate) { throw "SPEX ring measurement failed: late/stale counters differ" }
            if (($spexReady / [double]$spexScheduled) -lt 0.90) { throw "SPEX ring measurement failed: ready coverage below 90%" }
        }
        if ($spexNoActual -ne 0) { throw "SPEX measurement failed: router truth was unavailable for one or more layers" }
    } else {
        if ($spexScheduled -le 0 -or $spexReady -ne 0) { throw "SPEX intermediate stage counters are inconsistent" }
    }
}

$serverRuns = @($serverRunsAll | Select-Object -Last $Repeats)
$serverDecodeTps = @($serverRuns | ForEach-Object { $_.server_avg_tokens_per_second } | Where-Object { $_ -gt 0 })
$serverDecodeMeanTps = if ($serverDecodeTps.Count) { [math]::Round(($serverDecodeTps | Measure-Object -Average).Average, 6) } else { 0.0 }
$serverDecodeMinTps = if ($serverDecodeTps.Count) { [math]::Round(($serverDecodeTps | Measure-Object -Minimum).Minimum, 6) } else { 0.0 }
$serverDecodeMaxTps = if ($serverDecodeTps.Count) { [math]::Round(($serverDecodeTps | Measure-Object -Maximum).Maximum, 6) } else { 0.0 }
$serverPrefillTtft = @($serverRuns | ForEach-Object { $_.server_prefill_ttft_seconds } | Where-Object { $_ -gt 0 })
$serverPrefillTtftMean = if ($serverPrefillTtft.Count) { [math]::Round(($serverPrefillTtft | Measure-Object -Average).Average, 6) } else { 0.0 }
$spexReadyCoverage = if ($spexScheduled -gt 0) { [math]::Round($spexReady / [double]$spexScheduled, 6) } else { $null }
$spexRecallScope = if ($spexScheduled -gt 0) { "ready_predictions_only" } else { "not_applicable" }
$tps = @($results | ForEach-Object { $_.tokens_per_second })
$meanTps = if ($tps.Count) { [math]::Round(($tps | Measure-Object -Average).Average, 6) } else { 0.0 }
$minTps = if ($tps.Count) { [math]::Round(($tps | Measure-Object -Minimum).Minimum, 6) } else { 0.0 }
$maxTps = if ($tps.Count) { [math]::Round(($tps | Measure-Object -Maximum).Maximum, 6) } else { 0.0 }
$hashes = @($results | Select-Object -ExpandProperty content_sha256 -Unique)
if ($Repeats -gt 1 -and $hashes.Count -ne 1) {
    throw "Measurement failed: repeated outputs were not identical"
}
if ($ExpectedContentSHA256) {
    $unexpected = @($results | Where-Object { $_.content_sha256 -ine $ExpectedContentSHA256 })
    if ($unexpected.Count -ne 0) {
        throw "Measurement failed: output hash differs from expected baseline"
    }
}
$summary = [pscustomobject]@{
    tag = $Tag
    head = $headAtStart
    worktree_dirty = $worktreeDirtyAtStart
    ds4_cuda_sha256 = $sourceHashAtStart
    ds4_c_sha256 = $ds4SourceHashAtStart
    ds4_server_c_sha256 = $serverSourceHashAtStart
    ds4_spex_predict_c_sha256 = $spexSourceHashAtStart
    ds4_gpu_h_sha256 = $gpuHeaderHashAtStart
    cmake_sha256 = $cmakeHashAtStart
    executable_sha256 = $exeHashAtStart
    harness_sha256 = $harnessHashAtStart
    executable = $exe
    model = $model
    model_bytes = [long]$modelInfoAtStart.Length
    model_last_write_utc = $modelInfoAtStart.LastWriteTimeUtc.ToString("o")
    prompt = $Prompt
    prompt_sha256 = $promptHash
    expected_content_sha256 = $ExpectedContentSHA256.ToLowerInvariant()
    requested_max_tokens = $MaxTokens
    repeats = $Repeats
    warmup = [bool]$Warmup
    budget_gb = $BudgetGB
    reserve_mb = $ReserveMB
    no_selected_load = [bool]$NoSelectedLoad
    diagnostics = [bool]$Diagnostics
    moe_io_queue_depth = $IoQD
    moe_io_queue_depth_observed = $observedIoQD
    moe_overlapped_io_observed = $overlappedIoObserved
    moe_overlapped_io_fallbacks = $overlappedIoFallbacks
    expert_cache_requested = $ExpertCacheN
    expert_cache_reserve_gb = $ExpertCacheReserveGB
    expert_cache_policy = $ExpertCachePolicy
    expert_cache_stats_enabled = [bool]$ExpertCacheStats
    expert_cache_stats_interval = $ExpertCacheStatsInterval
    overlap_shared_requested = [bool]$OverlapShared
    overlap_shared_observed = $overlapSharedObserved
    overlap_shared_full_requested = [bool]$OverlapSharedFull
    overlap_shared_full_observed = $overlapSharedFullObserved
    shared_down_fusion_disabled = [bool]$DisableSharedDownFusion
    spex_dry_run_requested = [bool]$SpexDryRun
    spex_file = $SpexFile
    spex_file_sha256 = $spexHashAtStart
    spex_cap_requested = $(if ($SpexDryRun) { if ($SpexCap -gt 0) { $SpexCap } else { 6 } } else { 0 })
    spex_stage_requested = $(if ($SpexDryRun) { $SpexStage } else { "off" })
    spex_fused_topk_requested = [bool]$SpexFusedTopK
    spex_ring_slots_requested = $(if ($SpexDryRun) { $SpexRingSlots } else { 0 })
    spex_observed = $spexObserved
    spex_stage_observed = $spexObservedStage
    spex_fused_topk_observed = $spexFusedObserved
    spex_ring_slots_observed = $spexRingObserved
    spex_disabled = $spexDisabled
    spex_cap_observed = $spexObservedCap
    spex_scheduled = $spexScheduled
    spex_ready = $spexReady
    spex_not_ready = $spexNotReady
    spex_compared_layers = $spexLayers
    spex_actual_experts = $spexActual
    spex_predicted_experts = $spexPredicted
    spex_hits = $spexHits
    spex_recall = $spexRecall
    spex_recall_scope = $spexRecallScope
    spex_ready_coverage = $spexReadyCoverage
    spex_precision = $spexPrecision
    spex_no_actual = $spexNoActual
    spex_late = $spexLate
    spex_ring_full = $spexRingFull
    spex_stale = $spexStale
    expert_cache_calls = $cacheCalls
    expert_cache_capacity = $cacheCapacity
    expert_cache_count = $cacheCount
    expert_cache_hits = $cacheHits
    expert_cache_misses = $cacheMisses
    expert_cache_admissions = $cacheAdmissions
    expert_cache_evictions = $cacheEvictions
    expert_cache_direct_loads = $cacheDirect
    load_seconds = [math]::Round($loadSec, 6)
    warmup_seconds = [math]::Round($warmSec, 6)
    mean_tokens_per_second = $meanTps
    min_tokens_per_second = $minTps
    max_tokens_per_second = $maxTps
    server_decode_mean_tokens_per_second = $serverDecodeMeanTps
    server_decode_min_tokens_per_second = $serverDecodeMinTps
    server_decode_max_tokens_per_second = $serverDecodeMaxTps
    server_prefill_ttft_mean_seconds = $serverPrefillTtftMean
    server_runs = $serverRuns
    outputs_identical = ($hashes.Count -eq 1)
    results = $results
}
$summary | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 (Join-Path $outdir ("g7_" + $Tag + "_result.json"))

Write-Host ""
Write-Host "================ G7 RESULT ($Tag) ================"
Write-Host ("http_ok       : " + $httpOk)
Write-Host ("repeats       : " + $Repeats)
Write-Host ("content       : [" + $(if ($results.Count) { $results[-1].content } else { "" }) + "]")
Write-Host ("load_sec      : " + [math]::Round($loadSec,1))
Write-Host ("warm_sec      : " + [math]::Round($warmSec,2) + "  (warmup pass, discarded)")
Write-Host ("t/s mean/min/max: " + $meanTps + " / " + $minTps + " / " + $maxTps)
Write-Host ("server decode t/s mean/min/max: " + $serverDecodeMeanTps + " / " + $serverDecodeMinTps + " / " + $serverDecodeMaxTps)
Write-Host ("server prefill/TTFT mean sec: " + $serverPrefillTtftMean)
Write-Host ("outputs_identical: " + ($hashes.Count -eq 1))
Write-Host ("evictions     : " + $evicts)
Write-Host ("streams_expert: " + $streamsExpert)
Write-Host ("streams_hot   : " + $streamsHot)
Write-Host ("selected_loads: " + $selLoads)
Write-Host ("moe_io_qd req/observed: " + $IoQD + " / " + $observedIoQD)
Write-Host ("moe_io_fallbacks: " + $overlappedIoFallbacks)
Write-Host ("expert_cache req/cap/count: " + $ExpertCacheN + " / " + $cacheCapacity + " / " + $cacheCount)
Write-Host ("expert_cache hits/misses/evictions/direct: " + $cacheHits + " / " + $cacheMisses + " / " + $cacheEvictions + " / " + $cacheDirect)
Write-Host ("overlap_shared requested/observed: " + [bool]$OverlapShared + " / " + $overlapSharedObserved)
Write-Host ("overlap_shared_full requested/observed: " + [bool]$OverlapSharedFull + " / " + $overlapSharedFullObserved)
Write-Host ("shared_down_fusion_disabled: " + [bool]$DisableSharedDownFusion)
Write-Host ("spex requested/observed stage/cap: " + [bool]$SpexDryRun + " / " + $spexObserved + " / " + $spexObservedStage + " / " + $spexObservedCap)
Write-Host ("spex layers/hits/actual recall: " + $spexLayers + " / " + $spexHits + " / " + $spexActual + " / " + $spexRecall)
Write-Host ("spex recall scope/ready coverage: " + $spexRecallScope + " / " + $(if ($null -eq $spexReadyCoverage) { "n/a" } else { $spexReadyCoverage }))
Write-Host ("spex ring/late/full/stale: " + $spexRingObserved + " / " + $spexLate + " / " + $spexRingFull + " / " + $spexStale)
Write-Host ("last_sel_line : " + $lastSel)
Write-Host "=================================================="
