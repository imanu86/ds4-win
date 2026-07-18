param(
    [Parameter(Mandatory=$true)]
    [string]$HarnessPath,

    [string]$RepoRoot = $PSScriptRoot,

    [switch]$UniqueTagSuffix,

    [string]$UniqueTagArgumentName = "-Tag",

    [string]$UniqueTagBase = "",

    [switch]$WhatIf,

    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$HarnessArguments = @()
)

$ErrorActionPreference = "Stop"

function Resolve-G7BootstrapPath {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [string]$BasePath = ""
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return (Convert-Path -LiteralPath $Path)
    }
    if ([string]::IsNullOrWhiteSpace($BasePath)) {
        $BasePath = (Get-Location).Path
    }
    return (Convert-Path -LiteralPath (Join-Path $BasePath $Path))
}

function New-G7ImmutableTagSuffix {
    $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssfffZ")
    $nonce = [Guid]::NewGuid().ToString("N").Substring(0, 12)
    return ($stamp + "_" + $nonce)
}

function Add-G7ProcessLocalGitConfig {
    param(
        [Parameter(Mandatory=$true)][string]$Key,
        [Parameter(Mandatory=$true)][string]$Value
    )

    $rawCount = [Environment]::GetEnvironmentVariable(
        "GIT_CONFIG_COUNT",
        [EnvironmentVariableTarget]::Process)
    $count = 0
    if (-not [string]::IsNullOrWhiteSpace($rawCount)) {
        if (-not [int]::TryParse($rawCount, [ref]$count) -or $count -lt 0) {
            throw "Invalid process-local GIT_CONFIG_COUNT: $rawCount"
        }
    }

    [Environment]::SetEnvironmentVariable(
        ("GIT_CONFIG_KEY_" + $count),
        $Key,
        [EnvironmentVariableTarget]::Process)
    [Environment]::SetEnvironmentVariable(
        ("GIT_CONFIG_VALUE_" + $count),
        $Value,
        [EnvironmentVariableTarget]::Process)
    [Environment]::SetEnvironmentVariable(
        "GIT_CONFIG_COUNT",
        [string]($count + 1),
        [EnvironmentVariableTarget]::Process)
}

function Get-G7BootstrapProcessSnapshot {
    try {
        return @(Get-CimInstance Win32_Process -ErrorAction Stop)
    } catch {
        return @(Get-Process -ErrorAction Stop | ForEach-Object {
            $path = ""
            try { $path = [string]$_.Path } catch { $path = "" }
            [pscustomobject]@{
                ProcessId = [int]$_.Id
                ParentProcessId = 0
                Name = ([string]$_.ProcessName + ".exe")
                ExecutablePath = $path
                CommandLine = ""
            }
        })
    }
}

function Get-G7BootstrapAncestorProcessIds {
    param([Parameter(Mandatory=$true)][object[]]$Processes)

    $byPid = @{}
    foreach ($process in $Processes) {
        $byPid[[int]$process.ProcessId] = $process
    }

    $ancestors = @()
    $seen = @{}
    $cursorPid = [int]$PID
    while ($byPid.ContainsKey($cursorPid)) {
        $parentPid = [int]$byPid[$cursorPid].ParentProcessId
        if ($parentPid -le 0 -or $seen.ContainsKey($parentPid)) { break }
        $ancestors += $parentPid
        $seen[$parentPid] = $true
        $cursorPid = $parentPid
    }
    return @($ancestors)
}

function Get-G7BootstrapDs4Conflicts {
    param([Parameter(Mandatory=$true)][object[]]$Processes)

    $ancestorProcessIds = @(Get-G7BootstrapAncestorProcessIds -Processes $Processes)
    return @($Processes | Where-Object {
        $_.ProcessId -ne $PID -and
        $ancestorProcessIds -notcontains [int]$_.ProcessId -and
        ($_.Name -ieq "ds4_server.exe" -or
         ($_.Name -match "^(powershell|pwsh)(\.exe)?$" -and
          [string]$_.CommandLine -match "g7_(measure|runtime_monitor|harness_bootstrap)\.ps1"))
    } | ForEach-Object {
        [pscustomobject]@{
            pid = [int]$_.ProcessId
            parent_pid = [int]$_.ParentProcessId
            name = [string]$_.Name
            executable_path = [string]$_.ExecutablePath
            command_line = [string]$_.CommandLine
            conflict_type = "ds4-or-harness"
            refusal_reason = "conflicting-ds4-or-g7-process"
        }
    })
}

function Add-G7UniqueTagArgument {
    param(
        [string[]]$Arguments,
        [Parameter(Mandatory=$true)][string]$ArgumentName,
        [string]$Base,
        [Parameter(Mandatory=$true)][string]$Suffix
    )

    $effectiveArguments = @($Arguments)
    for ($i = 0; $i -lt $effectiveArguments.Count; $i += 1) {
        if ($effectiveArguments[$i] -eq $ArgumentName) {
            if ($i + 1 -ge $effectiveArguments.Count) {
                throw "$ArgumentName requires a value before a unique suffix can be appended"
            }
            $effectiveArguments[$i + 1] = ([string]$effectiveArguments[$i + 1] + "_" + $Suffix)
            return @($effectiveArguments)
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($Base)) {
        return @($effectiveArguments + @($ArgumentName, ($Base + "_" + $Suffix)))
    }
    return @($effectiveArguments)
}

$repo = Resolve-G7BootstrapPath -Path $RepoRoot
$harness = Resolve-G7BootstrapPath -Path $HarnessPath -BasePath $repo

$tagSuffix = ""
$effectiveHarnessArguments = @($HarnessArguments)
if ($effectiveHarnessArguments.Count -gt 0 -and $effectiveHarnessArguments[0] -eq "--") {
    $effectiveHarnessArguments = @($effectiveHarnessArguments | Select-Object -Skip 1)
}
if ($UniqueTagSuffix) {
    $tagSuffix = New-G7ImmutableTagSuffix
    [Environment]::SetEnvironmentVariable(
        "G7_HARNESS_IMMUTABLE_TAG_SUFFIX",
        $tagSuffix,
        [EnvironmentVariableTarget]::Process)
    $effectiveHarnessArguments = @(Add-G7UniqueTagArgument `
        -Arguments $effectiveHarnessArguments `
        -ArgumentName $UniqueTagArgumentName `
        -Base $UniqueTagBase `
        -Suffix $tagSuffix)
}

Add-G7ProcessLocalGitConfig -Key "safe.directory" -Value $repo
Add-G7ProcessLocalGitConfig `
    -Key "core.excludesFile" `
    -Value (Join-Path $repo ".gitignore")

$conflicts = @(Get-G7BootstrapDs4Conflicts -Processes (Get-G7BootstrapProcessSnapshot))
if ($conflicts.Count -ne 0) {
    $conflictText = @($conflicts | ForEach-Object {
        $_.name + " pid=" + $_.pid
    }) -join ", "
    throw ("G7 bootstrap refused launch: " + $conflictText)
}

if ($WhatIf) {
    [pscustomobject]@{
        repo_root = $repo
        harness_path = $harness
        harness_arguments = @($effectiveHarnessArguments)
        unique_tag_suffix = $tagSuffix
        git_config_count = [Environment]::GetEnvironmentVariable(
            "GIT_CONFIG_COUNT",
            [EnvironmentVariableTarget]::Process)
    } | ConvertTo-Json -Depth 4
    return
}

$powershellHost = Join-Path $PSHOME "powershell.exe"
if (-not (Test-Path -LiteralPath $powershellHost -PathType Leaf)) {
    $powershellHost = Join-Path $PSHOME "pwsh.exe"
}
if (-not (Test-Path -LiteralPath $powershellHost -PathType Leaf)) {
    throw "PowerShell host executable not found under PSHOME: $PSHOME"
}
& $powershellHost -NoLogo -NoProfile -ExecutionPolicy Bypass `
    -File $harness @effectiveHarnessArguments
if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
