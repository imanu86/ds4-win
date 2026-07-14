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
    [ValidateRange(0, 8192)][int]$Q8F16CacheMB = 0,
    [ValidateRange(0, 8192)][int]$Q8F16CacheReserveMB = 4096,
    [ValidateRange(0.0, 1024.0)][double]$DynamicArenaGiB = 0.0,
    [ValidateRange(0, 256)][int]$DynamicArenaObservedWindow = 0,
    [ValidateRange(1, 256)][int]$DynamicArenaObservedMinHits = 1,
    [ValidateRange(0, 256)][int]$DynamicArenaGrowInterval = 0,
    [ValidateRange(1, 32)][int]$ReapPrefetchThreads = 8,
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
    [ValidateSet(0, 1)][int]$SpexPrefetchK = 0,
    [ValidateRange(1, 1000000)][int]$SpexStatsEvery = 1000000,
    [string]$ExpectedContentSHA256 = "",
    [string]$ModelPath = "D:\ds4-models\ds4-2bit.gguf",
    [int]$Port = 8000,
    [ValidateRange(64, 131072)][int]$Context = 256,
    [ValidateRange(250, 10000)][int]$TelemetryIntervalMs = 1000,
    [switch]$SkipMemoryPreflight,
    [ValidateRange(0.0, 1024.0)][double]$MinimumAvailableGiB = 0.0
)

$ErrorActionPreference = "Stop"
$memoryPreflightHelper = Join-Path $PSScriptRoot "g7_memory_preflight.ps1"
$runtimeMonitorHelper = Join-Path $PSScriptRoot "g7_runtime_monitor.ps1"
. $memoryPreflightHelper
if (-not (Test-Path -LiteralPath $runtimeMonitorHelper)) {
    throw "Required runtime monitor not found: $runtimeMonitorHelper"
}
if ($ExpectedContentSHA256 -and $ExpectedContentSHA256 -notmatch '^[0-9a-fA-F]{64}$') {
    throw "ExpectedContentSHA256 must be a 64-character hexadecimal SHA-256"
}
$effectiveSpexCap = if ($SpexCap -gt 0) { $SpexCap } else { 6 }
$exe   = Join-Path $PSScriptRoot "build\Release\ds4_server.exe"
$buildManifestPath = Join-Path $PSScriptRoot "build\Release\g7_build_manifest.json"
$model = $ModelPath
$outdir = Join-Path $PSScriptRoot "g7_runs"
New-Item -ItemType Directory -Force -Path $outdir | Out-Null
$stderrLog = Join-Path $outdir ("g7_" + $Tag + "_stderr.log")
$stdoutLog = Join-Path $outdir ("g7_" + $Tag + "_stdout.log")
$memoryPreflightLog = Join-Path $outdir ("g7_" + $Tag + "_memory_preflight.json")
$runtimeTelemetryLog = Join-Path $outdir ("g7_" + $Tag + "_runtime_telemetry.jsonl")
if (Test-Path $stderrLog) { Remove-Item $stderrLog -Force }
if (Test-Path $stdoutLog) { Remove-Item $stdoutLog -Force }
if (Test-Path $memoryPreflightLog) { Remove-Item $memoryPreflightLog -Force }
if (Test-Path $runtimeTelemetryLog) { Remove-Item $runtimeTelemetryLog -Force }

$env:CUDA_PATH = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.6"
$env:PATH = "$env:CUDA_PATH\bin;" + $env:PATH
$inheritedDs4Environment = [ordered]@{}
foreach ($entry in @(Get-ChildItem Env: | Where-Object { $_.Name -like "DS4_*" } | Sort-Object Name)) {
    $inheritedDs4Environment[$entry.Name] = $entry.Value
    Remove-Item -LiteralPath ("Env:\" + $entry.Name) -ErrorAction SilentlyContinue
}
$env:DS4_CUDA_STREAM_FROM_RAM_MASKED_BUDGET_GB = "$BudgetGB"
$env:DS4_CUDA_STREAM_RESERVE_MB = "$ReserveMB"
if ($Q8F16CacheMB -gt 0) {
    $env:DS4_CUDA_Q8_F16_CACHE_MB = "$Q8F16CacheMB"
} else {
    Remove-Item Env:\DS4_CUDA_Q8_F16_CACHE_MB -ErrorAction SilentlyContinue
}
$env:DS4_CUDA_Q8_F16_CACHE_RESERVE_MB = "$Q8F16CacheReserveMB"
if ($DynamicArenaGiB -gt 0.0) {
    $env:DS4_CUDA_DYNAMIC_ARENA_GB = $DynamicArenaGiB.ToString("0.###", [Globalization.CultureInfo]::InvariantCulture)
} else {
    Remove-Item Env:\DS4_CUDA_DYNAMIC_ARENA_GB -ErrorAction SilentlyContinue
}
if ($DynamicArenaObservedWindow -gt 0) {
    $env:DS4_CUDA_DYNAMIC_ARENA_OBSERVED_WINDOW = "$DynamicArenaObservedWindow"
    $env:DS4_CUDA_DYNAMIC_ARENA_OBSERVED_MIN_HITS = "$DynamicArenaObservedMinHits"
} else {
    Remove-Item Env:\DS4_CUDA_DYNAMIC_ARENA_OBSERVED_WINDOW -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_CUDA_DYNAMIC_ARENA_OBSERVED_MIN_HITS -ErrorAction SilentlyContinue
}
if ($DynamicArenaGrowInterval -gt 0) {
    $env:DS4_CUDA_DYNAMIC_ARENA_GROW_INTERVAL = "$DynamicArenaGrowInterval"
} else {
    Remove-Item Env:\DS4_CUDA_DYNAMIC_ARENA_GROW_INTERVAL -ErrorAction SilentlyContinue
}
$env:DS4_REAP_PREFETCH_THREADS = "$ReapPrefetchThreads"
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
    $env:DS4_SPEX_CAP = "$effectiveSpexCap"
    $env:DS4_SPEX_AB_STAGE = $SpexStage
    if ($SpexFusedTopK) { $env:DS4_SPEX_FUSED_TOPK = "1" }
    else { Remove-Item Env:\DS4_SPEX_FUSED_TOPK -ErrorAction SilentlyContinue }
    $env:DS4_SPEX_RING_SLOTS = "$SpexRingSlots"
    $env:DS4_SPEX_DRY_RUN_STATS_EVERY = "$SpexStatsEvery"
    if ($SpexPrefetchK -gt 0) { $env:DS4_SPEX_PREFETCH_K = "$SpexPrefetchK" }
    else { Remove-Item Env:\DS4_SPEX_PREFETCH_K -ErrorAction SilentlyContinue }
} else {
    Remove-Item Env:\DS4_SPEX_HIDDEN_GPU_DRY_RUN -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_SPEX_FILE -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_SPEX_CAP -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_SPEX_AB_STAGE -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_SPEX_FUSED_TOPK -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_SPEX_RING_SLOTS -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_SPEX_DRY_RUN_STATS_EVERY -ErrorAction SilentlyContinue
    Remove-Item Env:\DS4_SPEX_PREFETCH_K -ErrorAction SilentlyContinue
}

if ($Repeats -lt 1) { throw "Repeats must be >= 1" }
$env:DS4_BENCH_EXIT_AFTER_REQUESTS = "$(if ($Warmup) { $Repeats + 1 } else { $Repeats })"
if ($DynamicArenaObservedWindow -gt 0 -and $DynamicArenaGiB -le 0.0) { throw "DynamicArenaObservedWindow requires DynamicArenaGiB > 0" }
if ($DynamicArenaGrowInterval -gt 0 -and $DynamicArenaObservedWindow -le 0) { throw "DynamicArenaGrowInterval requires DynamicArenaObservedWindow > 0" }
if ($SpexFusedTopK -and -not $SpexDryRun) { throw "SpexFusedTopK requires SpexDryRun" }
if ($SpexFusedTopK -and $SpexStage -notin @("topk", "full")) { throw "SpexFusedTopK requires the topk or full stage" }
if ($SpexRingSlots -gt 1 -and (-not $SpexDryRun -or $SpexStage -ne "full")) { throw "SpexRingSlots > 1 requires the full SpexDryRun stage" }
if ($SpexPrefetchK -gt 0 -and (-not $SpexDryRun -or $SpexStage -ne "full" -or $effectiveSpexCap -lt $SpexPrefetchK)) { throw "SpexPrefetchK requires full SpexDryRun with SpexCap >= SpexPrefetchK" }
if ($SpexPrefetchK -gt 0 -and $ExpertCacheN -gt 0) { throw "SpexPrefetchK is incompatible with ExpertCacheN > 0" }
if ($SpexPrefetchK -gt 0 -and $NoSelectedLoad) { throw "SpexPrefetchK is incompatible with NoSelectedLoad" }
if ($OverlapShared -and $OverlapSharedFull) { throw "Select only one overlap policy" }
if (($OverlapShared -or $OverlapSharedFull) -and $NoSelectedLoad) { throw "Overlap is incompatible with NoSelectedLoad" }
if (($OverlapShared -or $OverlapSharedFull) -and $ExpertCacheN -gt 0) { throw "Overlap is incompatible with ExpertCacheN > 0" }
$effectiveDs4Environment = [ordered]@{}
foreach ($entry in @(Get-ChildItem Env: | Where-Object { $_.Name -like "DS4_*" } | Sort-Object Name)) {
    $effectiveDs4Environment[$entry.Name] = $entry.Value
}
$effectiveMinimumAvailableGiB = $MinimumAvailableGiB
if ($effectiveMinimumAvailableGiB -eq 0.0) {
    $effectiveMinimumAvailableGiB = 4.0
    if ($DynamicArenaGiB -gt 0.0) {
        $effectiveMinimumAvailableGiB = [math]::Max(4.0, $DynamicArenaGiB + 2.0)
    }
}
$memoryPreflight = Invoke-G7MemoryPreflight -Skip:$SkipMemoryPreflight `
    -MinimumAvailableGiB $effectiveMinimumAvailableGiB -Label ("g7:" + $Tag)
Write-G7MemoryPreflightTelemetry -Telemetry $memoryPreflight -Path $memoryPreflightLog
if (-not $memoryPreflight.ready_to_launch) {
    throw ("Memory preflight refused launch: " + $memoryPreflight.failure_message)
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
$spexQueueHeaderHashAtStart = (Get-FileHash -Algorithm SHA256 (Join-Path $PSScriptRoot "ds4_spex_queue.h")).Hash.ToLowerInvariant()
$threadHeaderHashAtStart = (Get-FileHash -Algorithm SHA256 (Join-Path $PSScriptRoot "src\platform\os_thread.h")).Hash.ToLowerInvariant()
$cmakeHashAtStart = (Get-FileHash -Algorithm SHA256 (Join-Path $PSScriptRoot "CMakeLists.txt")).Hash.ToLowerInvariant()
$exeHashAtStart = (Get-FileHash -Algorithm SHA256 $exe).Hash.ToLowerInvariant()
$harnessHashAtStart = (Get-FileHash -Algorithm SHA256 $PSCommandPath).Hash.ToLowerInvariant()
$memoryPreflightHashAtStart = (Get-FileHash -Algorithm SHA256 $memoryPreflightHelper).Hash.ToLowerInvariant()
$runtimeMonitorHashAtStart = (Get-FileHash -Algorithm SHA256 $runtimeMonitorHelper).Hash.ToLowerInvariant()
$buildManifestHashAtStart = if (Test-Path -LiteralPath $buildManifestPath) {
    (Get-FileHash -Algorithm SHA256 $buildManifestPath).Hash.ToLowerInvariant()
} else { "" }
$spexHashAtStart = if ($SpexDryRun) { (Get-FileHash -Algorithm SHA256 -LiteralPath $SpexFile).Hash.ToLowerInvariant() } else { "" }
$modelInfoAtStart = Get-Item -LiteralPath $model
$promptBytes = [Text.Encoding]::UTF8.GetBytes($Prompt)
$promptHash = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($promptBytes)).Replace("-", "").ToLowerInvariant()
$buildManifest = $null
if (-not (Test-Path -LiteralPath $buildManifestPath -PathType Leaf)) {
    throw "Build provenance failed closed: run g7_build.ps1 before measuring"
}
try { $buildManifest = Get-Content -LiteralPath $buildManifestPath -Raw | ConvertFrom-Json }
catch { throw "Build provenance failed closed: invalid manifest JSON" }
if ($buildManifest.schema -ne "g7_native_windows_build_manifest_v1") {
    throw "Build provenance failed closed: unsupported manifest schema"
}
if ($buildManifest.executable_sha256 -ne $exeHashAtStart) {
    throw "Build provenance failed closed: executable hash does not match manifest"
}
$currentBuildInputPaths = @(
    @(git -C $PSScriptRoot ls-files) +
    @(git -C $PSScriptRoot ls-files --others --exclude-standard) |
    Where-Object {
        $_ -notmatch '^(build|g7_runs)/' -and
        ($_ -match '\.(c|cc|cpp|cu|h|hpp|cmake)$' -or
         $_ -match '(^|/)CMakeLists\.txt$')
    } | Sort-Object -Unique
)
$manifestInputPaths = @($buildManifest.inputs | ForEach-Object { $_.path } | Sort-Object -Unique)
if ((Compare-Object $manifestInputPaths $currentBuildInputPaths).Count -ne 0) {
    throw "Build provenance failed closed: compile input set changed since build"
}
foreach ($input in @($buildManifest.inputs)) {
    $inputPath = Join-Path $PSScriptRoot ($input.path -replace '/', '\')
    if (-not (Test-Path -LiteralPath $inputPath -PathType Leaf)) {
        throw "Build provenance failed closed: input missing $($input.path)"
    }
    $currentHash = (Get-FileHash -LiteralPath $inputPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($currentHash -ne $input.sha256) {
        throw "Build provenance failed closed: input hash changed $($input.path)"
    }
}
$gpuIdentity = $null
try {
    $gpuRaw = & nvidia-smi --query-gpu=name,driver_version,vbios_version,pci.bus_id --format=csv,noheader,nounits 2>$null
    if ($LASTEXITCODE -eq 0 -and $gpuRaw) {
        $gpuParts = @((@($gpuRaw)[0]).Split(',') | ForEach-Object { $_.Trim() })
        if ($gpuParts.Count -ge 4) {
            $gpuIdentity = [pscustomobject]@{
                name = $gpuParts[0]
                driver_version = $gpuParts[1]
                vbios_version = $gpuParts[2]
                pci_bus_id = $gpuParts[3]
            }
        }
    }
} catch { $gpuIdentity = $null }

$argList = @("-m", $model, "--cuda", "-c", "$Context", "-n", "$MaxTokens", "--host", "127.0.0.1", "--port", "$Port")
Write-Host ("[g7] launching: " + $exe + " " + ($argList -join " "))
Write-Host ("[g7] NoSelectedLoad=" + $NoSelectedLoad + " MaxTokens=" + $MaxTokens)

$proc = Start-Process -FilePath $exe -ArgumentList $argList -NoNewWindow -PassThru `
    -RedirectStandardError $stderrLog -RedirectStandardOutput $stdoutLog
$telemetryProc = Start-Process -FilePath powershell.exe -ArgumentList @(
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $runtimeMonitorHelper,
    "-TargetProcessId", "$($proc.Id)", "-OutputPath", $runtimeTelemetryLog,
    "-IntervalMs", "$TelemetryIntervalMs"
) -WindowStyle Hidden -PassThru
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
if ($telemetryProc -and -not $telemetryProc.HasExited) {
    $telemetryProc.WaitForExit(10000) | Out-Null
}
if ($telemetryProc -and -not $telemetryProc.HasExited) {
    $telemetryProc.Kill()
    $telemetryProc.WaitForExit(10000) | Out-Null
}

$runtimeSamples = @()
if (Test-Path -LiteralPath $runtimeTelemetryLog) {
    foreach ($line in Get-Content -LiteralPath $runtimeTelemetryLog) {
        if (-not $line.Trim()) { continue }
        try { $runtimeSamples += ($line | ConvertFrom-Json) } catch {}
    }
}
if ($runtimeSamples.Count -lt 2) {
    throw "Runtime telemetry failed closed: fewer than two valid samples"
}
function Get-G7Median([object[]]$Values) {
    $ordered = @($Values | Where-Object { $null -ne $_ } | Sort-Object)
    if ($ordered.Count -eq 0) { return $null }
    $middle = [int][math]::Floor($ordered.Count / 2)
    if (($ordered.Count % 2) -eq 1) { return [double]$ordered[$middle] }
    return ([double]$ordered[$middle - 1] + [double]$ordered[$middle]) / 2.0
}
$sharedSamples = @($runtimeSamples | ForEach-Object { $_.gpu_process_shared_bytes } | Where-Object { $null -ne $_ })
$dedicatedSamples = @($runtimeSamples | ForEach-Object { $_.gpu_process_dedicated_bytes } | Where-Object { $null -ne $_ })
$workingSamples = @($runtimeSamples | ForEach-Object { $_.working_set_bytes } | Where-Object { $null -ne $_ })
$privateSamples = @($runtimeSamples | ForEach-Object { $_.private_bytes } | Where-Object { $null -ne $_ })
$availableSamples = @($runtimeSamples | ForEach-Object { $_.windows_available_bytes } | Where-Object { $null -ne $_ })
$gpuUtilSamples = @($runtimeSamples | ForEach-Object { if ($_.nvidia) { $_.nvidia.utilization_percent } } | Where-Object { $null -ne $_ })
$vramSamples = @($runtimeSamples | ForEach-Object { if ($_.nvidia) { $_.nvidia.vram_used_mib } } | Where-Object { $null -ne $_ })
$powerSamples = @($runtimeSamples | ForEach-Object { if ($_.nvidia) { $_.nvidia.power_watts } } | Where-Object { $null -ne $_ })
if ($sharedSamples.Count -eq 0 -or $dedicatedSamples.Count -eq 0 -or
    $gpuUtilSamples.Count -eq 0 -or $vramSamples.Count -eq 0) {
    throw "Runtime telemetry failed closed: required WDDM/NVIDIA counters are missing"
}
$firstRuntimeSample = $runtimeSamples[0]
$lastRuntimeSample = $runtimeSamples[-1]
$runtimeElapsedSeconds = [double]$lastRuntimeSample.elapsed_seconds - [double]$firstRuntimeSample.elapsed_seconds
$runtimeSampleIntervals = @()
for ($sampleIndex = 1; $sampleIndex -lt $runtimeSamples.Count; $sampleIndex++) {
    $runtimeSampleIntervals += [double]$runtimeSamples[$sampleIndex].elapsed_seconds -
        [double]$runtimeSamples[$sampleIndex - 1].elapsed_seconds
}
$runtimeEffectiveIntervalSeconds = if ($runtimeSamples.Count -gt 1) {
    $runtimeElapsedSeconds / ($runtimeSamples.Count - 1)
} else { $null }
$runtimeTelemetry = [pscustomobject]@{
    path = $runtimeTelemetryLog
    requested_interval_ms = $TelemetryIntervalMs
    effective_interval_seconds = $runtimeEffectiveIntervalSeconds
    interval_median_seconds = Get-G7Median $runtimeSampleIntervals
    interval_min_seconds = if ($runtimeSampleIntervals.Count) { [double]($runtimeSampleIntervals | Measure-Object -Minimum).Minimum } else { $null }
    interval_max_seconds = if ($runtimeSampleIntervals.Count) { [double]($runtimeSampleIntervals | Measure-Object -Maximum).Maximum } else { $null }
    samples = $runtimeSamples.Count
    elapsed_seconds = [double]$lastRuntimeSample.elapsed_seconds
    gpu_process_shared_peak_bytes = if ($sharedSamples.Count) { [Int64]($sharedSamples | Measure-Object -Maximum).Maximum } else { $null }
    gpu_process_shared_median_bytes = Get-G7Median $sharedSamples
    gpu_process_dedicated_peak_bytes = if ($dedicatedSamples.Count) { [Int64]($dedicatedSamples | Measure-Object -Maximum).Maximum } else { $null }
    gpu_process_dedicated_median_bytes = Get-G7Median $dedicatedSamples
    process_working_set_peak_bytes = if ($workingSamples.Count) { [Int64]($workingSamples | Measure-Object -Maximum).Maximum } else { $null }
    process_private_peak_bytes = if ($privateSamples.Count) { [Int64]($privateSamples | Measure-Object -Maximum).Maximum } else { $null }
    windows_available_min_bytes = if ($availableSamples.Count) { [Int64]($availableSamples | Measure-Object -Minimum).Minimum } else { $null }
    gpu_utilization_median_percent = Get-G7Median $gpuUtilSamples
    gpu_utilization_peak_percent = if ($gpuUtilSamples.Count) { [double]($gpuUtilSamples | Measure-Object -Maximum).Maximum } else { $null }
    vram_used_peak_mib = if ($vramSamples.Count) { [double]($vramSamples | Measure-Object -Maximum).Maximum } else { $null }
    power_median_watts = Get-G7Median $powerSamples
    win32_process_read_transfer_delta_bytes = if ($null -ne $firstRuntimeSample.read_transfer_bytes -and $null -ne $lastRuntimeSample.read_transfer_bytes) { [Int64]$lastRuntimeSample.read_transfer_bytes - [Int64]$firstRuntimeSample.read_transfer_bytes } else { $null }
    win32_process_write_transfer_delta_bytes = if ($null -ne $firstRuntimeSample.write_transfer_bytes -and $null -ne $lastRuntimeSample.write_transfer_bytes) { [Int64]$lastRuntimeSample.write_transfer_bytes - [Int64]$firstRuntimeSample.write_transfer_bytes } else { $null }
    win32_process_transfer_counters_include_mmap_pageins = $false
    mmap_backed_file_io_measured = $false
    page_fault_delta = if ($null -ne $firstRuntimeSample.page_faults -and $null -ne $lastRuntimeSample.page_faults) { [Int64]$lastRuntimeSample.page_faults - [Int64]$firstRuntimeSample.page_faults } else { $null }
}

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
$spexPrefetchObserved = $false; $spexPrefetchKObserved = 0; $spexPrefetchSlotsObserved = 0
$spexPrefetchFinalObserved = $false; $spexPrefetchSubmitted = 0; $spexPrefetchDropped = 0
$spexPrefetchLoaded = 0; $spexPrefetchMatched = 0; $spexPrefetchHits = 0; $spexPrefetchNoHits = 0
$spexPrefetchLate = 0; $spexPrefetchCanceled = 0; $spexPrefetchPoisoned = 0
$spexPrefetchErrors = 0; $spexPrefetchDisabled = $false
$spexPrefetchBytesRead = 0; $spexPrefetchBytesUsed = 0
$arenaObserverArmed = $false; $arenaObserverWindowObserved = 0
$arenaObserverMinHitsObserved = 0; $arenaObserverGrowIntervalObserved = 0
$arenaObserverFirstLayer = 0; $arenaObserverLastLayer = 0
$arenaObserverTokens = 0; $arenaObserverResident = 0
$arenaWrapObserved = $false; $arenaWrapLoads = 0; $arenaWrapWorkers = 0
$arenaWrapSeconds = 0.0; $arenaWrapGeneration = 0
$arenaWrapPreloaded = 0; $arenaWrapMirrorGiB = 0.0
$arenaVerifyWorkers = 0; $arenaVerifySeconds = 0.0
$arenaObserverResultObserved = $false; $arenaObserverResult = "not_observed"
$arenaGrowthPublications = 0; $arenaGrowthSkips = 0
$arenaGrowthEvents = @()
$contextObserved = 0; $prefillChunkObserved = 0
$rawKvRowsObserved = 0; $compressedKvRowsObserved = 0
$arenaFinalObserved = $false; $arenaFinalHits = 0; $arenaFinalMisses = 0
$arenaFinalFatal = 0; $arenaFinalUploadedGiB = 0.0
$arenaAllocatedBytes = 0; $arenaSlotBytes = 0; $arenaAllocatedSlots = 0
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
    $spexPrefetchActiveLine = $lines | Where-Object { $_ -match "SPEX prefetch active k=(\d+) slots=(\d+)" } | Select-Object -Last 1
    if ($spexPrefetchActiveLine -and $spexPrefetchActiveLine -match "SPEX prefetch active k=(\d+) slots=(\d+)") {
        $spexPrefetchObserved = $true
        $spexPrefetchKObserved = [int]$Matches[1]
        $spexPrefetchSlotsObserved = [int]$Matches[2]
    }
    $spexPrefetchFinalLine = $lines | Where-Object { $_ -match "\[spex-prefetch\] final" } | Select-Object -Last 1
    if ($spexPrefetchFinalLine -and $spexPrefetchFinalLine -match "submitted=(\d+) dropped=(\d+) loaded=(\d+) matched=(\d+) consumed=(\d+) no_hits=(\d+) late=(\d+) canceled=(\d+) poisoned=(\d+) errors=(\d+) disabled=(\d+) bytes_read=(\d+) bytes_used=(\d+)") {
        $spexPrefetchFinalObserved = $true
        $spexPrefetchSubmitted = [long]$Matches[1]; $spexPrefetchDropped = [long]$Matches[2]
        $spexPrefetchLoaded = [long]$Matches[3]; $spexPrefetchMatched = [long]$Matches[4]
        $spexPrefetchHits = [long]$Matches[5]; $spexPrefetchNoHits = [long]$Matches[6]
        $spexPrefetchLate = [long]$Matches[7]; $spexPrefetchCanceled = [long]$Matches[8]
        $spexPrefetchPoisoned = [long]$Matches[9]; $spexPrefetchErrors = [long]$Matches[10]
        $spexPrefetchDisabled = ([int]$Matches[11] -ne 0)
        $spexPrefetchBytesRead = [long]$Matches[12]; $spexPrefetchBytesUsed = [long]$Matches[13]
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
    $contextLine = $lines | Where-Object { $_ -match "context buffers .*ctx=(\d+).*prefill_chunk=(\d+).*raw_kv_rows=(\d+).*compressed_kv_rows=(\d+)" } | Select-Object -Last 1
    if ($contextLine -and $contextLine -match "ctx=(\d+).*prefill_chunk=(\d+).*raw_kv_rows=(\d+).*compressed_kv_rows=(\d+)") {
        $contextObserved = [int]$Matches[1]
        $prefillChunkObserved = [int]$Matches[2]
        $rawKvRowsObserved = [int]$Matches[3]
        $compressedKvRowsObserved = [int]$Matches[4]
    }
    $arenaReadyLine = $lines | Where-Object { $_ -match "CUDA dynamic arena ready" } | Select-Object -Last 1
    if ($arenaReadyLine -and $arenaReadyLine -match "CUDA dynamic arena ready [0-9.]+ GiB, (\d+) slots.*bytes=(\d+) slot_bytes=(\d+)") {
        $arenaAllocatedSlots = [long]$Matches[1]
        $arenaAllocatedBytes = [long]$Matches[2]
        $arenaSlotBytes = [long]$Matches[3]
    }
    $arenaObserverArmedLine = $lines | Where-Object { $_ -match "\[arena-observe\] armed window=(\d+) min_hits=(\d+)(?: grow_interval=(\d+))? layers=(\d+)\.\.(\d+) router=unbiased residency-only" } | Select-Object -Last 1
    if ($arenaObserverArmedLine -and $arenaObserverArmedLine -match "armed window=(\d+) min_hits=(\d+)(?: grow_interval=(\d+))? layers=(\d+)\.\.(\d+) router=unbiased residency-only") {
        $arenaObserverArmed = $true
        $arenaObserverWindowObserved = [int]$Matches[1]
        $arenaObserverMinHitsObserved = [int]$Matches[2]
        $arenaObserverGrowIntervalObserved = if ($Matches[3]) { [int]$Matches[3] } else { 0 }
        $arenaObserverFirstLayer = [int]$Matches[4]
        $arenaObserverLastLayer = [int]$Matches[5]
    }
    $arenaWrapLine = $lines | Where-Object { $_ -match "\[arena-observe\] WRAP (published|aborted)" } | Select-Object -Last 1
    if ($arenaWrapLine -and $arenaWrapLine -match "WRAP published tokens=(\d+) resident=(\d+) loads=(\d+) workers=(\d+) seconds=([0-9.]+) generation=(\d+)") {
        $arenaWrapObserved = $true
        $arenaObserverTokens = [long]$Matches[1]; $arenaObserverResident = [long]$Matches[2]
        $arenaWrapLoads = [long]$Matches[3]; $arenaWrapWorkers = [int]$Matches[4]
        $arenaWrapSeconds = [double]::Parse($Matches[5], [Globalization.CultureInfo]::InvariantCulture)
        $arenaWrapGeneration = [long]$Matches[6]
        if ($arenaWrapLine -match "preloaded=(\d+) mirror=([0-9.]+) GiB") {
            $arenaWrapPreloaded = [long]$Matches[1]
            $arenaWrapMirrorGiB = [double]::Parse($Matches[2], [Globalization.CultureInfo]::InvariantCulture)
        }
        if ($arenaWrapLine -match "verify_workers=(\d+) verify_seconds=([0-9.]+)") {
            $arenaVerifyWorkers = [int]$Matches[1]
            $arenaVerifySeconds = [double]::Parse($Matches[2], [Globalization.CultureInfo]::InvariantCulture)
        }
    } elseif ($arenaWrapLine -and $arenaWrapLine -match "WRAP aborted tokens=(\d+) resident=(\d+) loads=(\d+) seconds=([0-9.]+)") {
        $arenaWrapObserved = $true
        $arenaObserverTokens = [long]$Matches[1]; $arenaObserverResident = [long]$Matches[2]
        $arenaWrapLoads = [long]$Matches[3]
        $arenaWrapSeconds = [double]::Parse($Matches[4], [Globalization.CultureInfo]::InvariantCulture)
    }
    $arenaResultLine = $lines | Where-Object { $_ -match "\[arena-observe\] window complete" } | Select-Object -Last 1
    if ($arenaResultLine -and $arenaResultLine -match "window complete tokens=(\d+) resident=(\d+)(?: growths=\d+)? result=(published|fallback)") {
        $arenaObserverResultObserved = $true
        $arenaObserverTokens = [long]$Matches[1]; $arenaObserverResident = [long]$Matches[2]
        $arenaObserverResult = $Matches[3]
    }
    $arenaGrowthLines = @($lines | Where-Object { $_ -match "\[arena-observe\] grow complete" })
    if ($arenaGrowthLines.Count) {
        foreach ($arenaGrowthLine in $arenaGrowthLines) {
            if ($arenaGrowthLine -match "grow complete tokens=(\d+) resident=(\d+) growths=(\d+) result=(published|fallback)") {
                $arenaObserverTokens = [long]$Matches[1]
                $arenaObserverResident = [long]$Matches[2]
                $arenaGrowthPublications = [long]$Matches[3]
                $arenaGrowthEvents += [pscustomobject]@{
                    tokens = [long]$Matches[1]
                    resident_entries = [long]$Matches[2]
                    resident_bytes = [long]$Matches[2] * [long]$arenaSlotBytes
                    publication = [long]$Matches[3]
                    result = $Matches[4]
                }
            }
        }
    }
    $arenaGrowthSkips = @($lines | Where-Object { $_ -match "\[arena-observe\] grow skipped" }).Count
    $arenaFinalLine = $lines | Where-Object { $_ -match "\[arena\] final" } | Select-Object -Last 1
    if ($arenaFinalLine -and $arenaFinalLine -match "\[arena\] final hits=(\d+) misses=(\d+) fatal=(\d+) uploaded=([0-9.]+) GiB") {
        $arenaFinalObserved = $true
        $arenaFinalHits = [long]$Matches[1]; $arenaFinalMisses = [long]$Matches[2]
        $arenaFinalFatal = [long]$Matches[3]
        $arenaFinalUploadedGiB = [double]::Parse($Matches[4], [Globalization.CultureInfo]::InvariantCulture)
    }
}

if (-not $httpOk) { throw "Measurement failed: one or more HTTP requests did not complete" }
if (@($results).Count -ne $Repeats) {
    throw "Measurement failed: expected $Repeats results, observed $(@($results).Count)"
}
if ($contextObserved -ne $Context) {
    throw "Measurement failed: requested context $Context, observed $contextObserved"
}

if ($SpexDryRun) {
    $expectedSpexCap = $effectiveSpexCap
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
if ($SpexPrefetchK -gt 0) {
    if (-not $spexPrefetchObserved -or $spexPrefetchKObserved -ne $SpexPrefetchK) { throw "SPEX prefetch measurement failed: requested worker was not activated" }
    if (-not $spexPrefetchFinalObserved) { throw "SPEX prefetch measurement failed: final counters were not observed" }
    if ($spexPrefetchSubmitted -le 0) { throw "SPEX prefetch measurement failed: no jobs were submitted" }
    if ($spexPrefetchLoaded -le 0 -or $spexPrefetchHits -le 0) { throw "SPEX prefetch measurement failed: no functional loads were consumed" }
    if ($spexPrefetchErrors -ne 0 -or $spexPrefetchPoisoned -ne 0 -or $spexPrefetchDisabled) { throw "SPEX prefetch measurement failed: worker error/quarantine observed" }
    if ($spexPrefetchDropped -ne 0 -or $spexPrefetchCanceled -ne 0) { throw "SPEX prefetch measurement failed: dropped/canceled jobs observed" }
    if ($spexPrefetchSubmitted -ne ($spexPrefetchLoaded + $spexPrefetchLate)) { throw "SPEX prefetch measurement failed: submitted jobs are not fully accounted" }
    if ($spexPrefetchLoaded -ne ($spexPrefetchMatched + $spexPrefetchNoHits)) { throw "SPEX prefetch measurement failed: loaded jobs are not fully classified" }
    if ($spexPrefetchMatched -ne $spexPrefetchHits) { throw "SPEX prefetch measurement failed: matched jobs did not all reach consumption" }
    if ($spexReady -ne $spexLayers) { throw "SPEX prefetch measurement failed: ready predictions and compared layers differ" }
    if ($spexPrefetchHits -ne $spexHits) { throw "SPEX prefetch measurement failed: consumed jobs differ from predictor hits" }
    if ($spexPrefetchBytesRead -le 0 -or $spexPrefetchBytesUsed -le 0 -or $spexPrefetchBytesUsed -gt $spexPrefetchBytesRead) { throw "SPEX prefetch measurement failed: byte counters are inconsistent" }
    if (($spexPrefetchBytesRead % $spexPrefetchLoaded) -ne 0 -or ($spexPrefetchBytesUsed % $spexPrefetchHits) -ne 0) { throw "SPEX prefetch measurement failed: byte counters are not whole experts" }
    if (($spexPrefetchBytesRead / $spexPrefetchLoaded) -ne ($spexPrefetchBytesUsed / $spexPrefetchHits)) { throw "SPEX prefetch measurement failed: read/consumed expert sizes differ" }
} elseif ($spexPrefetchObserved -or $spexPrefetchFinalObserved) {
    throw "SPEX prefetch measurement failed: worker activated while not requested"
}
if ($DynamicArenaObservedWindow -gt 0) {
    if (-not $arenaObserverArmed) { throw "Dynamic arena measurement failed: observer was not armed" }
    if ($arenaObserverWindowObserved -ne $DynamicArenaObservedWindow -or
        $arenaObserverMinHitsObserved -ne $DynamicArenaObservedMinHits -or
        $arenaObserverGrowIntervalObserved -ne $DynamicArenaGrowInterval) {
        throw "Dynamic arena measurement failed: observed policy differs from requested policy"
    }
    if ($MaxTokens -ge $DynamicArenaObservedWindow -and -not $arenaObserverResultObserved) {
        throw "Dynamic arena measurement failed: initial publication result was not observed"
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
$rawOutputsPath = Join-Path $outdir ("g7_" + $Tag + "_raw_outputs.json")
$rawOutputs = [pscustomobject]@{
    schema = "g7_raw_outputs_v1"
    tag = $Tag
    head = $headAtStart
    executable_sha256 = $exeHashAtStart
    ds4_cuda_sha256 = $sourceHashAtStart
    prompt_sha256 = $promptHash
    expected_content_sha256 = if ($ExpectedContentSHA256) { $ExpectedContentSHA256.ToLowerInvariant() } else { "" }
    output_hashes = $hashes
    outputs_identical = ($hashes.Count -eq 1)
    results = $results
}
$rawOutputs | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 $rawOutputsPath
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
    ds4_spex_queue_h_sha256 = $spexQueueHeaderHashAtStart
    os_thread_h_sha256 = $threadHeaderHashAtStart
    cmake_sha256 = $cmakeHashAtStart
    executable_sha256 = $exeHashAtStart
    harness_sha256 = $harnessHashAtStart
    memory_preflight_harness_sha256 = $memoryPreflightHashAtStart
    runtime_monitor_harness_sha256 = $runtimeMonitorHashAtStart
    build_manifest_path = $buildManifestPath
    build_manifest_sha256 = $buildManifestHashAtStart
    build_manifest_input_fingerprint_sha256 = $buildManifest.input_fingerprint_sha256
    build_manifest_head = $buildManifest.head
    build_manifest_worktree_dirty_at_build_start = [bool]$buildManifest.worktree_dirty_at_build_start
    executable = $exe
    model = $model
    model_bytes = [long]$modelInfoAtStart.Length
    model_last_write_utc = $modelInfoAtStart.LastWriteTimeUtc.ToString("o")
    prompt = $Prompt
    prompt_sha256 = $promptHash
    expected_content_sha256 = $ExpectedContentSHA256.ToLowerInvariant()
    requested_max_tokens = $MaxTokens
    context_requested = $Context
    context_observed = $contextObserved
    prefill_chunk_observed = $prefillChunkObserved
    raw_kv_rows_observed = $rawKvRowsObserved
    compressed_kv_rows_observed = $compressedKvRowsObserved
    server_arguments = $argList
    inherited_ds4_environment = [pscustomobject]$inheritedDs4Environment
    effective_ds4_environment = [pscustomobject]$effectiveDs4Environment
    gpu_identity = $gpuIdentity
    repeats = $Repeats
    warmup = [bool]$Warmup
    budget_gb = $BudgetGB
    reserve_mb = $ReserveMB
    q8_f16_cache_mb_requested = $Q8F16CacheMB
    q8_f16_cache_reserve_mb_requested = $Q8F16CacheReserveMB
    dynamic_arena_gib_requested = $DynamicArenaGiB
    dynamic_arena_observed_window_requested = $DynamicArenaObservedWindow
    dynamic_arena_observed_min_hits_requested = $DynamicArenaObservedMinHits
    dynamic_arena_grow_interval_requested = $DynamicArenaGrowInterval
    reap_prefetch_threads_requested = $ReapPrefetchThreads
    minimum_available_gib_effective = $effectiveMinimumAvailableGiB
    dynamic_arena_allocated_bytes = $arenaAllocatedBytes
    dynamic_arena_allocated_slots = $arenaAllocatedSlots
    dynamic_arena_slot_bytes = $arenaSlotBytes
    dynamic_arena_observer_armed = $arenaObserverArmed
    dynamic_arena_observer_window_observed = $arenaObserverWindowObserved
    dynamic_arena_observer_min_hits_observed = $arenaObserverMinHitsObserved
    dynamic_arena_grow_interval_observed = $arenaObserverGrowIntervalObserved
    dynamic_arena_observer_first_layer = $arenaObserverFirstLayer
    dynamic_arena_observer_last_layer = $arenaObserverLastLayer
    dynamic_arena_observer_tokens = $arenaObserverTokens
    dynamic_arena_observer_resident = $arenaObserverResident
    dynamic_arena_observer_resident_bytes = [long]$arenaObserverResident * [long]$arenaSlotBytes
    dynamic_arena_occupancy_ratio = if ($arenaAllocatedBytes -gt 0) { ([double]$arenaObserverResident * [double]$arenaSlotBytes) / [double]$arenaAllocatedBytes } else { $null }
    dynamic_arena_wrap_observed = $arenaWrapObserved
    dynamic_arena_wrap_loads = $arenaWrapLoads
    dynamic_arena_wrap_workers = $arenaWrapWorkers
    dynamic_arena_wrap_seconds = $arenaWrapSeconds
    dynamic_arena_wrap_generation = $arenaWrapGeneration
    dynamic_arena_wrap_preloaded = $arenaWrapPreloaded
    dynamic_arena_wrap_mirror_gib = $arenaWrapMirrorGiB
    dynamic_arena_verify_workers = $arenaVerifyWorkers
    dynamic_arena_verify_seconds = $arenaVerifySeconds
    dynamic_arena_observer_result_observed = $arenaObserverResultObserved
    dynamic_arena_observer_result = $arenaObserverResult
    dynamic_arena_observer_published = ($arenaObserverResult -eq "published")
    dynamic_arena_observer_fallback = ($arenaObserverResult -eq "fallback")
    dynamic_arena_growth_publications = $arenaGrowthPublications
    dynamic_arena_growth_skips = $arenaGrowthSkips
    dynamic_arena_growth_events = $arenaGrowthEvents
    dynamic_arena_final_observed = $arenaFinalObserved
    dynamic_arena_final_hits = $arenaFinalHits
    dynamic_arena_final_misses = $arenaFinalMisses
    dynamic_arena_final_fatal = $arenaFinalFatal
    dynamic_arena_hit_rate = if (($arenaFinalHits + $arenaFinalMisses) -gt 0) { [double]$arenaFinalHits / [double]($arenaFinalHits + $arenaFinalMisses) } else { $null }
    dynamic_arena_miss_rate = if (($arenaFinalHits + $arenaFinalMisses) -gt 0) { [double]$arenaFinalMisses / [double]($arenaFinalHits + $arenaFinalMisses) } else { $null }
    dynamic_arena_h2d_uploaded_gib = $arenaFinalUploadedGiB
    dynamic_arena_h2d_uploaded_semantics = "Pinned host arena to compact VRAM selected-expert tensors; not SSD or mmap read traffic"
    no_selected_load = [bool]$NoSelectedLoad
    diagnostics = [bool]$Diagnostics
    memory_preflight = $memoryPreflight
    runtime_telemetry = $runtimeTelemetry
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
    spex_cap_requested = $(if ($SpexDryRun) { $effectiveSpexCap } else { 0 })
    spex_stage_requested = $(if ($SpexDryRun) { $SpexStage } else { "off" })
    spex_fused_topk_requested = [bool]$SpexFusedTopK
    spex_ring_slots_requested = $(if ($SpexDryRun) { $SpexRingSlots } else { 0 })
    spex_prefetch_k_requested = $SpexPrefetchK
    spex_prefetch_observed = $spexPrefetchObserved
    spex_prefetch_k_observed = $spexPrefetchKObserved
    spex_prefetch_slots_observed = $spexPrefetchSlotsObserved
    spex_prefetch_final_observed = $spexPrefetchFinalObserved
    spex_prefetch_submitted = $spexPrefetchSubmitted
    spex_prefetch_dropped = $spexPrefetchDropped
    spex_prefetch_loaded = $spexPrefetchLoaded
    spex_prefetch_matched = $spexPrefetchMatched
    spex_prefetch_hits = $spexPrefetchHits
    spex_prefetch_no_hits = $spexPrefetchNoHits
    spex_prefetch_late = $spexPrefetchLate
    spex_prefetch_canceled = $spexPrefetchCanceled
    spex_prefetch_poisoned = $spexPrefetchPoisoned
    spex_prefetch_errors = $spexPrefetchErrors
    spex_prefetch_disabled = $spexPrefetchDisabled
    spex_prefetch_bytes_read = $spexPrefetchBytesRead
    spex_prefetch_bytes_used = $spexPrefetchBytesUsed
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
Write-Host ("ctx requested/observed, prefill chunk, raw/compressed KV rows: " + $Context + " / " + $contextObserved + " / " + $prefillChunkObserved + " / " + $rawKvRowsObserved + " / " + $compressedKvRowsObserved)
Write-Host ("Q8-F16 cap/reserve MiB requested: " + $Q8F16CacheMB + " / " + $Q8F16CacheReserveMB)
Write-Host ("effective DS4 env: " + (($effectiveDs4Environment.GetEnumerator() | ForEach-Object { $_.Key + "=" + $_.Value }) -join "; "))
Write-Host ("arena observer armed/window/minhits/grow/tokens/resident: " + $arenaObserverArmed + " / " + $arenaObserverWindowObserved + " / " + $arenaObserverMinHitsObserved + " / " + $arenaObserverGrowIntervalObserved + " / " + $arenaObserverTokens + " / " + $arenaObserverResident)
Write-Host ("arena growth publications/skips: " + $arenaGrowthPublications + " / " + $arenaGrowthSkips)
Write-Host ("arena WRAP loads/workers/sec/generation/preloaded/mirror GiB: " + $arenaWrapLoads + " / " + $arenaWrapWorkers + " / " + $arenaWrapSeconds + " / " + $arenaWrapGeneration + " / " + $arenaWrapPreloaded + " / " + $arenaWrapMirrorGiB)
Write-Host ("arena verify workers/sec: " + $arenaVerifyWorkers + " / " + $arenaVerifySeconds)
Write-Host ("arena result/final hits/misses/fatal/H2D GiB: " + $arenaObserverResult + " / " + $arenaFinalHits + " / " + $arenaFinalMisses + " / " + $arenaFinalFatal + " / " + $arenaFinalUploadedGiB)
Write-Host ("arena allocated/resident bytes/occupancy: " + $arenaAllocatedBytes + " / " + ([long]$arenaObserverResident * [long]$arenaSlotBytes) + " / " + $summary.dynamic_arena_occupancy_ratio)
Write-Host ("arena hit/miss rate: " + $summary.dynamic_arena_hit_rate + " / " + $summary.dynamic_arena_miss_rate)
Write-Host ("runtime telemetry samples/requested ms/effective sec: " + $runtimeTelemetry.samples + " / " + $runtimeTelemetry.requested_interval_ms + " / " + [math]::Round($runtimeTelemetry.effective_interval_seconds, 3))
Write-Host ("WDDM shared peak/median GiB: " + [math]::Round($runtimeTelemetry.gpu_process_shared_peak_bytes / 1GB, 3) + " / " + [math]::Round($runtimeTelemetry.gpu_process_shared_median_bytes / 1GB, 3))
Write-Host ("WDDM dedicated peak GiB / VRAM peak MiB: " + [math]::Round($runtimeTelemetry.gpu_process_dedicated_peak_bytes / 1GB, 3) + " / " + $runtimeTelemetry.vram_used_peak_mib)
Write-Host ("process working/private peak GiB: " + [math]::Round($runtimeTelemetry.process_working_set_peak_bytes / 1GB, 3) + " / " + [math]::Round($runtimeTelemetry.process_private_peak_bytes / 1GB, 3))
Write-Host ("GPU util median/peak percent: " + $runtimeTelemetry.gpu_utilization_median_percent + " / " + $runtimeTelemetry.gpu_utilization_peak_percent)
Write-Host ("Win32 process read/write delta GiB (excludes mmap page-ins): " + [math]::Round($runtimeTelemetry.win32_process_read_transfer_delta_bytes / 1GB, 3) + " / " + [math]::Round($runtimeTelemetry.win32_process_write_transfer_delta_bytes / 1GB, 3))
Write-Host ("process page-fault delta / mmap I/O measured: " + $runtimeTelemetry.page_fault_delta + " / " + $runtimeTelemetry.mmap_backed_file_io_measured)
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
Write-Host ("spex prefetch req/observed/submitted/matched/consumed/late/errors: " + $SpexPrefetchK + " / " + $spexPrefetchKObserved + " / " + $spexPrefetchSubmitted + " / " + $spexPrefetchMatched + " / " + $spexPrefetchHits + " / " + $spexPrefetchLate + " / " + $spexPrefetchErrors)
Write-Host ("last_sel_line : " + $lastSel)
Write-Host "=================================================="
