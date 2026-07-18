param(
    [ValidateSet("Release", "RelWithDebInfo", "Debug")][string]$Configuration = "Release",
    [string]$CMake = "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe",
    [string]$WindowsSdkVersion = "10.0.26100.0",
    [string]$WindowsSdkRootOverride = "C:\PROGRA~2\WI3CF2~1\10"
)

$ErrorActionPreference = "Stop"
$repo = $PSScriptRoot
$buildDir = Join-Path $repo "build"
$outputDir = Join-Path $buildDir $Configuration
$exe = Join-Path $outputDir "ds4_server.exe"
$manifestPath = Join-Path $outputDir "g7_build_manifest.json"

function Get-G7BuildInputPaths {
    $tracked = @(git -C $repo ls-files)
    $untracked = @(git -C $repo ls-files --others --exclude-standard)
    return @($tracked + $untracked | Where-Object {
        $_ -notmatch '^(build[^/]*|g7_runs)/' -and
        ($_ -match '\.(c|cc|cpp|cu|h|hpp|cmake)$' -or
         $_ -match '(^|/)CMakeLists\.txt$')
    } | Sort-Object -Unique)
}

function Get-G7BuildInputs {
    $inputs = @()
    foreach ($relative in @(Get-G7BuildInputPaths)) {
        $full = Join-Path $repo ($relative -replace '/', '\')
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
            throw "Build input disappeared: $relative"
        }
        $inputs += [pscustomobject]@{
            path = $relative
            sha256 = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
    return $inputs
}

function Get-G7InputFingerprint([object[]]$Inputs) {
    $text = (@($Inputs | ForEach-Object { $_.path + "=" + $_.sha256 }) -join "`n") + "`n"
    $bytes = [Text.Encoding]::UTF8.GetBytes($text)
    return [BitConverter]::ToString(
        [Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
    ).Replace("-", "").ToLowerInvariant()
}

if (-not (Test-Path -LiteralPath $CMake -PathType Leaf)) {
    throw "CMake not found: $CMake"
}
if (-not (Test-Path -LiteralPath $buildDir -PathType Container)) {
    throw "Configured build directory not found: $buildDir"
}

$startedUtc = (Get-Date).ToUniversalTime()
$inputsBefore = @(Get-G7BuildInputs)
$fingerprintBefore = Get-G7InputFingerprint $inputsBefore
$head = (git -C $repo rev-parse HEAD).Trim()
$dirty = [bool](git -C $repo status --porcelain)
$buildArguments = @(
    "--build", $buildDir, "--config", $Configuration, "--parallel", "--",
    "/p:_LatestWindowsTargetPlatformVersion=$WindowsSdkVersion",
    "/p:WindowsTargetPlatformVersion=$WindowsSdkVersion",
    "/p:TargetPlatformVersion=$WindowsSdkVersion",
    "/p:TargetPlatformSdkPath=$WindowsSdkRootOverride\",
    "/p:TargetPlatformSdkRootOverride=$WindowsSdkRootOverride",
    "/p:TargetPlatformDisplayName=Windows10SDK"
)
$command = @($CMake) + $buildArguments
Write-Host ("[g7-build] " + ($command -join " "))
& $CMake @buildArguments
if ($LASTEXITCODE -ne 0) { throw "CMake build failed: exit=$LASTEXITCODE" }

$inputsAfter = @(Get-G7BuildInputs)
$fingerprintAfter = Get-G7InputFingerprint $inputsAfter
if ($fingerprintAfter -ne $fingerprintBefore) {
    throw "Build inputs changed while compiling; manifest refused"
}
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
    throw "Built executable not found: $exe"
}

$cudaBin = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.6\bin"
foreach ($dll in @("cudart64_12.dll", "cublas64_12.dll", "cublasLt64_12.dll")) {
    $source = Join-Path $cudaBin $dll
    $destination = Join-Path $outputDir $dll
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Required CUDA runtime missing: $source"
    }
    Copy-Item -LiteralPath $source -Destination $destination -Force
}

$manifest = [pscustomobject]@{
    schema = "g7_native_windows_build_manifest_v1"
    started_utc = $startedUtc.ToString("o")
    completed_utc = (Get-Date).ToUniversalTime().ToString("o")
    head = $head
    worktree_dirty_at_build_start = $dirty
    configuration = $Configuration
    command = $command
    input_fingerprint_sha256 = $fingerprintAfter
    inputs = $inputsAfter
    executable = $exe
    executable_sha256 = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant()
    executable_length = (Get-Item -LiteralPath $exe).Length
    executable_last_write_utc = (Get-Item -LiteralPath $exe).LastWriteTimeUtc.ToString("o")
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
Write-Host "[g7-build] manifest=$manifestPath"
Write-Host "[g7-build] input_fingerprint=$fingerprintAfter"
Write-Host "[g7-build] executable_sha256=$($manifest.executable_sha256)"
