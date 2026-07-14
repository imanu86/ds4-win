[CmdletBinding(DefaultParameterSetName = "SegmentGiB")]
param(
    [ValidateRange(1, 1024)]
    [UInt64] $TotalGiB = 50,

    [Parameter(ParameterSetName = "SegmentGiB")]
    [ValidateRange(1, 1024)]
    [UInt64] $SegmentGiB = 25,

    [Parameter(Mandatory = $true, ParameterSetName = "SegmentCount")]
    [ValidateRange(1, 65536)]
    [UInt64] $SegmentCount,

    [string] $OutputPath,

    [switch] $BuildOnly,

    [switch] $ParserTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$memoryPreflightHelper = Join-Path $PSScriptRoot "g7_memory_preflight.ps1"
. $memoryPreflightHelper

$cudaRoot = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.6"
$nvcc = Join-Path $cudaRoot "bin\nvcc.exe"
$vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
$source = Join-Path $PSScriptRoot "g17_segmented_arena_probe.cu"
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$buildDirectory = [IO.Path]::GetFullPath((Join-Path $tempRoot `
    ("g17_segmented_arena_probe_" + [Guid]::NewGuid().ToString("N"))))
$tempPrefix = $tempRoot.TrimEnd('\') + '\'
$previousCudaPath = $env:CUDA_PATH
$previousPath = $env:Path

if (-not $buildDirectory.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to build outside the system temporary directory."
}
if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
    throw "Probe source was not found at '$source'."
}
if (-not (Test-Path -LiteralPath $nvcc -PathType Leaf)) {
    throw "CUDA 12.6 nvcc was not found at '$nvcc'."
}
if (-not (Test-Path -LiteralPath $vswhere -PathType Leaf)) {
    throw "Visual Studio Installer's vswhere.exe was not found at '$vswhere'."
}
if ($BuildOnly -and $ParserTest) {
    throw "BuildOnly and ParserTest are mutually exclusive."
}

$modeArgument = $null
$modeValue = [UInt64]0
if ($PSCmdlet.ParameterSetName -eq "SegmentCount") {
    $modeArgument = "--segment-count"
    $modeValue = $SegmentCount
    if ($SegmentCount -gt $TotalGiB -or ($TotalGiB % $SegmentCount) -ne 0) {
        throw "SegmentCount must exactly divide TotalGiB into whole-GiB segments."
    }
} else {
    $modeArgument = "--segment-gib"
    $modeValue = $SegmentGiB
    if ($SegmentGiB -gt $TotalGiB -or ($TotalGiB % $SegmentGiB) -ne 0) {
        throw "TotalGiB must be exactly divisible by SegmentGiB."
    }
}

try {
    New-Item -ItemType Directory -Path $buildDirectory | Out-Null
    $env:CUDA_PATH = $cudaRoot
    $env:Path = (Join-Path $cudaRoot "bin") + ";" + $env:Path

    $visualStudioInstallations = @(& $vswhere -latest -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath)
    if ($LASTEXITCODE -ne 0 -or $visualStudioInstallations.Count -eq 0) {
        throw "A Visual Studio installation with the x64 C++ toolchain was not found."
    }
    $vcvars64 = Join-Path $visualStudioInstallations[0] "VC\Auxiliary\Build\vcvars64.bat"
    if (-not (Test-Path -LiteralPath $vcvars64 -PathType Leaf)) {
        throw "The Visual C++ environment script was not found at '$vcvars64'."
    }

    $executable = Join-Path $buildDirectory "g17_segmented_arena_probe.exe"
    $compileCommand = 'call "{0}" amd64 >nul && "{1}" -O2 -std=c++17 -arch=sm_86 --machine=64 -Xcompiler=/W4 -o "{2}" "{3}"' -f `
        $vcvars64, $nvcc, $executable, $source
    Write-Host "[g17-segmented] Compiling CUDA 12.6 sm_86 probe..."
    & $env:ComSpec /d /s /c $compileCommand
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $executable -PathType Leaf)) {
        throw "nvcc failed with exit code $LASTEXITCODE."
    }

    if ($BuildOnly) {
        Write-Host "[g17-segmented] Build-only test passed."
        return
    }

    if ($ParserTest) {
        $parserStdout = Join-Path $buildDirectory "parser.stdout"
        $parserStderr = Join-Path $buildDirectory "parser.stderr"
        $process = Start-Process -FilePath $executable -ArgumentList @("invalid") `
            -NoNewWindow -Wait -PassThru -RedirectStandardOutput $parserStdout `
            -RedirectStandardError $parserStderr
        $text = [IO.File]::ReadAllText($parserStdout).Trim()
        $lines = @($text -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($process.ExitCode -ne 2 -or $lines.Count -ne 1) {
            throw "Non-allocating parser test returned unexpected process output."
        }
        $record = $lines[0] | ConvertFrom-Json -ErrorAction Stop
        if ($record.schema -ne "g17_segmented_arena_probe_v1" -or
            $record.failure_kind -ne "argument" -or
            -not [bool]$record.cuda_device_reset.attempted) {
            throw "Non-allocating parser test returned an unexpected JSON record."
        }
        Write-Host "[g17-segmented] Non-allocating JSON parser test passed."
        return
    }

    $memoryPreflight = Invoke-G7MemoryPreflight `
        -MinimumAvailableGiB ([double]$TotalGiB + 2.0) `
        -Label ("g17-segmented:{0}GiB" -f $TotalGiB)
    if (-not $memoryPreflight.ready_to_launch) {
        throw ("Memory preflight refused launch: {0}" -f $memoryPreflight.failure_message)
    }

    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $stamp = [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss'Z'",
            [Globalization.CultureInfo]::InvariantCulture)
        $OutputPath = Join-Path $PSScriptRoot `
            ("g7_runs\g17_segmented_arena_probe_{0}.json" -f $stamp)
    } elseif (-not [IO.Path]::IsPathRooted($OutputPath)) {
        $OutputPath = Join-Path $PSScriptRoot $OutputPath
    }
    $OutputPath = [IO.Path]::GetFullPath($OutputPath)
    $outputDirectory = Split-Path -Parent $OutputPath
    if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    }

    $stdoutPath = Join-Path $buildDirectory "probe.stdout"
    $stderrPath = Join-Path $buildDirectory "probe.stderr"
    $childArguments = @(
        $TotalGiB.ToString([Globalization.CultureInfo]::InvariantCulture),
        $modeArgument,
        $modeValue.ToString([Globalization.CultureInfo]::InvariantCulture)
    )
    Write-Host ("[g17-segmented] Launching fresh {0} GiB process..." -f $TotalGiB)
    $process = Start-Process -FilePath $executable -ArgumentList $childArguments `
        -NoNewWindow -Wait -PassThru -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath
    $stdout = [IO.File]::ReadAllText($stdoutPath).Trim()
    $stderr = [IO.File]::ReadAllText($stderrPath).Trim()
    $lines = @($stdout -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($lines.Count -ne 1) {
        throw "Probe stdout was not exactly one JSON document."
    }
    $record = $lines[0] | ConvertFrom-Json -ErrorAction Stop
    $record | Add-Member runner_exit_code $process.ExitCode -Force
    $record | Add-Member runner_stderr $(if ($stderr.Length -eq 0) { $null } else { $stderr }) -Force
    $record | Add-Member cuda_toolkit "12.6" -Force
    $record | Add-Member nvcc_architecture "sm_86" -Force
    $record | Add-Member memory_preflight $memoryPreflight -Force

    $utf8NoBom = New-Object Text.UTF8Encoding($false)
    $json = $record | ConvertTo-Json -Compress -Depth 12
    [IO.File]::WriteAllText($OutputPath, $json + [Environment]::NewLine, $utf8NoBom)
    Write-Host ("[g17-segmented] success={0}, exit={1}, JSON={2}" -f `
        [bool]$record.success, $process.ExitCode, $OutputPath)
    if ($process.ExitCode -ne 0 -or -not [bool]$record.success) {
        throw "Segmented arena probe reported failure."
    }
} finally {
    $env:CUDA_PATH = $previousCudaPath
    $env:Path = $previousPath
    if (Test-Path -LiteralPath $buildDirectory) {
        if (-not $buildDirectory.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove a build directory outside the system temporary directory."
        }
        Remove-Item -LiteralPath $buildDirectory -Recurse -Force
    }
}
