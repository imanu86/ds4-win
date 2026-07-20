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
$vcvars64 = "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"

function ConvertFrom-G7EnvironmentLines {
    param([AllowEmptyCollection()][string[]]$EnvironmentLines)

    $variables = [Collections.Generic.Dictionary[string,string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
    $originalNames = [Collections.Generic.Dictionary[string,string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
    foreach ($line in @($EnvironmentLines)) {
        if ($null -eq $line) { continue }
        $separator = $line.IndexOf('=')
        if ($separator -le 0) { continue }
        $name = $line.Substring(0, $separator)
        $value = $line.Substring($separator + 1)
        if ($variables.ContainsKey($name)) {
            throw "Visual Studio x64 environment emitted duplicate variable names: " +
                "'$($originalNames[$name])' and '$name' (case-insensitive)"
        }
        $variables.Add($name, $value)
        $originalNames.Add($name, $name)
    }
    if (-not $variables.ContainsKey('Path')) {
        throw "Visual Studio x64 environment did not emit PATH"
    }
    $developerPath = $variables['Path']
    if ([string]::IsNullOrWhiteSpace($developerPath)) {
        throw "Visual Studio x64 environment emitted empty PATH"
    }
    return [pscustomobject]@{
        Variables = $variables
        DeveloperPath = $developerPath
    }
}

function Import-G7ProcessEnvironment {
    param([Parameter(Mandatory = $true)][object]$ParsedEnvironment)

    foreach ($entry in $ParsedEnvironment.Variables.GetEnumerator()) {
        if ($entry.Key.Equals('Path', [StringComparison]::OrdinalIgnoreCase)) {
            continue
        }
        [Environment]::SetEnvironmentVariable(
            $entry.Key, $entry.Value, [EnvironmentVariableTarget]::Process)
    }
    [Environment]::SetEnvironmentVariable(
        'PATH', $null, [EnvironmentVariableTarget]::Process)
    [Environment]::SetEnvironmentVariable(
        'Path', $ParsedEnvironment.DeveloperPath,
        [EnvironmentVariableTarget]::Process)
}

function Initialize-G7BuildEnvironment {
    if (-not (Test-Path -LiteralPath $vcvars64 -PathType Leaf)) {
        throw "Visual Studio x64 environment script not found: $vcvars64"
    }
    $commandLine = 'call "' + $vcvars64 + '" >nul && set'
    $environmentLines = @(& $env:ComSpec /d /s /c $commandLine)
    if ($LASTEXITCODE -ne 0 -or $environmentLines.Count -eq 0) {
        throw "Visual Studio x64 environment initialization failed"
    }
    $parsedEnvironment = ConvertFrom-G7EnvironmentLines $environmentLines
    Import-G7ProcessEnvironment $parsedEnvironment
    if (-not (Get-Command cl.exe -ErrorAction SilentlyContinue)) {
        throw "Visual Studio x64 environment did not expose cl.exe"
    }
}

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

function Get-G7CMakeGenerator {
    $cachePath = Join-Path $buildDir "CMakeCache.txt"
    if (-not (Test-Path -LiteralPath $cachePath -PathType Leaf)) {
        throw "CMake cache not found: $cachePath"
    }
    $line = Get-Content -LiteralPath $cachePath | Where-Object {
        $_ -match '^CMAKE_GENERATOR:INTERNAL='
    } | Select-Object -First 1
    if (-not $line) {
        throw "CMAKE_GENERATOR missing from cache: $cachePath"
    }
    return ($line -replace '^CMAKE_GENERATOR:INTERNAL=', '').Trim()
}

if (-not (Test-Path -LiteralPath $CMake -PathType Leaf)) {
    throw "CMake not found: $CMake"
}
if (-not (Test-Path -LiteralPath $buildDir -PathType Container)) {
    throw "Configured build directory not found: $buildDir"
}
Initialize-G7BuildEnvironment

$startedUtc = (Get-Date).ToUniversalTime()
$inputsBefore = @(Get-G7BuildInputs)
$fingerprintBefore = Get-G7InputFingerprint $inputsBefore
$head = (git -C $repo rev-parse HEAD).Trim()
$dirty = [bool](git -C $repo status --porcelain)
$generator = Get-G7CMakeGenerator
$buildArguments = @("--build", $buildDir, "--config", $Configuration, "--parallel")
if ($generator -like "Visual Studio*") {
    $buildArguments += @(
        "--",
        "/p:_LatestWindowsTargetPlatformVersion=$WindowsSdkVersion",
        "/p:WindowsTargetPlatformVersion=$WindowsSdkVersion",
        "/p:TargetPlatformVersion=$WindowsSdkVersion",
        "/p:TargetPlatformSdkPath=$WindowsSdkRootOverride\",
        "/p:TargetPlatformSdkRootOverride=$WindowsSdkRootOverride",
        "/p:TargetPlatformDisplayName=Windows10SDK"
    )
} elseif ($generator -like "Ninja*") {
    # Ninja rejects MSBuild /p: properties after "--"; keep the manifest output stable below.
} else {
    throw "Unsupported CMake generator for g7 build wrapper: $generator"
}
$command = @($CMake) + $buildArguments
Write-Host ("[g7-build] " + ($command -join " "))
& $CMake @buildArguments
if ($LASTEXITCODE -ne 0) { throw "CMake build failed: exit=$LASTEXITCODE" }

$inputsAfter = @(Get-G7BuildInputs)
$fingerprintAfter = Get-G7InputFingerprint $inputsAfter
if ($fingerprintAfter -ne $fingerprintBefore) {
    throw "Build inputs changed while compiling; manifest refused"
}
if ($generator -like "Ninja*") {
    $ninjaExe = Join-Path $buildDir "ds4_server.exe"
    if (-not (Test-Path -LiteralPath $ninjaExe -PathType Leaf)) {
        throw "Ninja built executable not found: $ninjaExe"
    }
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    Copy-Item -LiteralPath $ninjaExe -Destination $exe -Force
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
