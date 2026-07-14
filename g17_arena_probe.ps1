[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [UInt64[]] $SizesGiB = @(24, 28, 32, 36, 40, 44, 48, 50),

    [ValidateRange(1, 1024)]
    [UInt64] $DeviceBufferMiB = 256,

    [ValidateRange(1, 1000)]
    [UInt64] $Iterations = 1,

    [string] $OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$cudaRoot = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.6"
$nvcc = Join-Path $cudaRoot "bin\nvcc.exe"
$vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
$source = Join-Path $PSScriptRoot "g17_arena_probe.cu"
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$buildDirectory = Join-Path $tempRoot ("g17_arena_probe_" + [Guid]::NewGuid().ToString("N"))
$buildDirectory = [IO.Path]::GetFullPath($buildDirectory)
$tempPrefix = $tempRoot.TrimEnd('\') + '\'
$utf8NoBom = New-Object Text.UTF8Encoding($false)

if (-not $buildDirectory.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to use a build directory outside the system temporary directory."
}
if (-not (Test-Path -LiteralPath $nvcc -PathType Leaf)) {
    throw "CUDA 12.6 nvcc was not found at '$nvcc'."
}
if (-not (Test-Path -LiteralPath $vswhere -PathType Leaf)) {
    throw "Visual Studio Installer's vswhere.exe was not found at '$vswhere'."
}
if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
    throw "Probe source was not found at '$source'."
}
if ($SizesGiB.Count -eq 0 -or $SizesGiB.Where({ $_ -eq 0 }).Count -ne 0) {
    throw "SizesGiB must contain at least one positive integer size."
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $stamp = [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss'Z'",
        [Globalization.CultureInfo]::InvariantCulture)
    $OutputPath = Join-Path $PSScriptRoot ("g7_runs\g17_arena_probe_{0}.jsonl" -f $stamp)
} elseif (-not [IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath = Join-Path $PSScriptRoot $OutputPath
}
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
$outputDirectory = Split-Path -Parent $OutputPath

$previousCudaPath = $env:CUDA_PATH
$previousPath = $env:Path
$failedCount = 0
$completedCount = 0

try {
    New-Item -ItemType Directory -Path $buildDirectory | Out-Null
    if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    }

    $env:CUDA_PATH = $cudaRoot
    $env:Path = (Join-Path $cudaRoot "bin") + ";" + $env:Path

    $executable = Join-Path $buildDirectory "g17_arena_probe.exe"
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

    $compileCommand = 'call "{0}" amd64 >nul && "{1}" -O2 -std=c++17 -arch=sm_86 --machine=64 -Xcompiler=/W4 -o "{2}" "{3}"' -f `
        $vcvars64, $nvcc, $executable, $source

    Write-Host "[g17] Compiling with CUDA 12.6 nvcc for sm_86..."
    & $env:ComSpec /d /s /c $compileCommand
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $executable -PathType Leaf)) {
        throw "nvcc failed with exit code $LASTEXITCODE."
    }

    [IO.File]::WriteAllText($OutputPath, "", $utf8NoBom)
    Write-Host ("[g17] Recording JSONL to {0}" -f $OutputPath)

    $index = 0
    foreach ($sizeGiB in $SizesGiB) {
        ++$index
        $stdoutPath = Join-Path $buildDirectory ("probe_{0:D2}_{1}gib.stdout" -f $index, $sizeGiB)
        $stderrPath = Join-Path $buildDirectory ("probe_{0:D2}_{1}gib.stderr" -f $index, $sizeGiB)
        $childArguments = @(
            $sizeGiB.ToString([Globalization.CultureInfo]::InvariantCulture),
            $DeviceBufferMiB.ToString([Globalization.CultureInfo]::InvariantCulture),
            $Iterations.ToString([Globalization.CultureInfo]::InvariantCulture)
        )

        Write-Host ("[g17] Probing {0} GiB in a fresh process..." -f $sizeGiB)
        $process = Start-Process -FilePath $executable -ArgumentList $childArguments `
            -NoNewWindow -Wait -PassThru -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath

        $stdout = [IO.File]::ReadAllText($stdoutPath).Trim()
        $stderr = [IO.File]::ReadAllText($stderrPath).Trim()
        $record = $null
        $runnerError = $null

        if (-not [string]::IsNullOrWhiteSpace($stdout)) {
            try {
                $record = $stdout | ConvertFrom-Json -ErrorAction Stop
            } catch {
                $runnerError = "Probe stdout was not one valid JSON document: $($_.Exception.Message)"
            }
        } else {
            $runnerError = "Probe produced no JSON on stdout."
        }

        if ($null -eq $record) {
            $record = [pscustomobject][ordered]@{
                schema = "g17_arena_probe_runner_failure_v1"
                timestamp_utc = [DateTime]::UtcNow.ToString("o",
                    [Globalization.CultureInfo]::InvariantCulture)
                success = $false
                failure_kind = "runner"
                failure_stage = "child_process_output"
                failure_message = $runnerError
                requested_arena_gib = $sizeGiB
            }
        }

        $record | Add-Member -NotePropertyName runner_exit_code `
            -NotePropertyValue $process.ExitCode -Force
        $record | Add-Member -NotePropertyName runner_stderr `
            -NotePropertyValue $(if ($stderr.Length -eq 0) { $null } else { $stderr }) -Force
        $record | Add-Member -NotePropertyName nvcc_architecture `
            -NotePropertyValue "sm_86" -Force
        $record | Add-Member -NotePropertyName cuda_toolkit `
            -NotePropertyValue "12.6" -Force

        $line = $record | ConvertTo-Json -Compress -Depth 8
        [IO.File]::AppendAllText($OutputPath, $line + [Environment]::NewLine, $utf8NoBom)

        ++$completedCount
        if (-not [bool]$record.success -or $process.ExitCode -ne 0) {
            ++$failedCount
        }
        Write-Host ("[g17] {0} GiB: success={1}, exit={2}" -f
            $sizeGiB, [bool]$record.success, $process.ExitCode)
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

Write-Host ("[g17] Completed {0} sizes; {1} reported failure. JSONL: {2}" -f
    $completedCount, $failedCount, $OutputPath)
