# Windows benchmark memory preflight helpers (ASCII only, PS 5.1 safe)

function Assert-G7NoActiveServer {
    [CmdletBinding()]
    param()

    if (Get-Process -Name ds4_server -ErrorAction SilentlyContinue) {
        throw "Another ds4_server process is active; refusing to alter memory state or launch a benchmark."
    }
}

function Get-G7MemoryCounterValue {
    param(
        [Parameter(Mandatory = $true)] $InputObject,
        [Parameter(Mandatory = $true)] [string] $Name
    )

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) {
        throw "Windows memory counter '$Name' is unavailable."
    }
    return [UInt64]$property.Value
}

function Initialize-G7NativeMemoryApi {
    if ("G7NativeMemory" -as [type]) {
        return
    }

    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class G7NativeMemory {
    [StructLayout(LayoutKind.Sequential)]
    public struct MEMORYSTATUSEX {
        public uint dwLength;
        public uint dwMemoryLoad;
        public ulong ullTotalPhys;
        public ulong ullAvailPhys;
        public ulong ullTotalPageFile;
        public ulong ullAvailPageFile;
        public ulong ullTotalVirtual;
        public ulong ullAvailVirtual;
        public ulong ullAvailExtendedVirtual;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct PERFORMANCE_INFORMATION {
        public uint cb;
        public UIntPtr CommitTotal;
        public UIntPtr CommitLimit;
        public UIntPtr CommitPeak;
        public UIntPtr PhysicalTotal;
        public UIntPtr PhysicalAvailable;
        public UIntPtr SystemCache;
        public UIntPtr KernelTotal;
        public UIntPtr KernelPaged;
        public UIntPtr KernelNonpaged;
        public UIntPtr PageSize;
        public uint HandleCount;
        public uint ProcessCount;
        public uint ThreadCount;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX status);

    [DllImport("psapi.dll", SetLastError = true)]
    public static extern bool GetPerformanceInfo(
        out PERFORMANCE_INFORMATION info, uint size);

    [DllImport("kernel32.dll")]
    public static extern ulong GetTickCount64();
}
"@
}

function Get-G7NativeMemoryCounters {
    Initialize-G7NativeMemoryApi

    $status = New-Object G7NativeMemory+MEMORYSTATUSEX
    $status.dwLength = [Runtime.InteropServices.Marshal]::SizeOf($status)
    if (-not [G7NativeMemory]::GlobalMemoryStatusEx([ref]$status)) {
        throw "GlobalMemoryStatusEx failed with Win32 error $([Runtime.InteropServices.Marshal]::GetLastWin32Error())."
    }

    $performance = New-Object G7NativeMemory+PERFORMANCE_INFORMATION
    $performance.cb = [Runtime.InteropServices.Marshal]::SizeOf($performance)
    if (-not [G7NativeMemory]::GetPerformanceInfo(
            [ref]$performance, [uint32]$performance.cb)) {
        throw "GetPerformanceInfo failed with Win32 error $([Runtime.InteropServices.Marshal]::GetLastWin32Error())."
    }

    $pageSize = [UInt64]$performance.PageSize.ToUInt64()
    $bootTime = [DateTime]::UtcNow.AddMilliseconds(
        -[double][G7NativeMemory]::GetTickCount64())
    return [pscustomobject][ordered]@{
        source = "win32-globalmemorystatusex-getperformanceinfo"
        boot_time_utc = $bootTime
        total_bytes = [UInt64]$status.ullTotalPhys
        available_bytes = [UInt64]$status.ullAvailPhys
        committed_bytes = [UInt64]$performance.CommitTotal.ToUInt64() * $pageSize
        commit_limit_bytes = [UInt64]$performance.CommitLimit.ToUInt64() * $pageSize
        free_and_zero_bytes = [UInt64]0
        standby_bytes = [UInt64]0
        modified_bytes = [UInt64]0
        paged_pool_bytes = [UInt64]$performance.KernelPaged.ToUInt64() * $pageSize
        paged_pool_resident_bytes = [UInt64]0
        nonpaged_pool_bytes = [UInt64]$performance.KernelNonpaged.ToUInt64() * $pageSize
        system_cache_bytes = [UInt64]$performance.SystemCache.ToUInt64() * $pageSize
        unavailable_counters = @(
            "FreeAndZeroPageListBytes",
            "StandbyCacheBytes",
            "ModifiedPageListBytes",
            "PoolPagedResidentBytes"
        )
    }
}

function Get-G7MemorySnapshot {
    [CmdletBinding()]
    param(
        [ValidateRange(1, 100)]
        [int] $TopProcessCount = 10
    )

    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $memory = Get-CimInstance -ClassName Win32_PerfFormattedData_PerfOS_Memory -ErrorAction Stop
        $standbyBytes = (Get-G7MemoryCounterValue $memory "StandbyCacheCoreBytes") +
            (Get-G7MemoryCounterValue $memory "StandbyCacheNormalPriorityBytes") +
            (Get-G7MemoryCounterValue $memory "StandbyCacheReserveBytes")
        $bootTime = $os.LastBootUpTime.ToUniversalTime()
        $counterSource = "cim-win32-memory"
        $counterError = $null
        $unavailableCounters = @()
        $totalBytes = [UInt64]$os.TotalVisibleMemorySize * 1KB
        $availableBytes = Get-G7MemoryCounterValue $memory "AvailableBytes"
        $committedBytes = Get-G7MemoryCounterValue $memory "CommittedBytes"
        $commitLimitBytes = Get-G7MemoryCounterValue $memory "CommitLimit"
        $freeAndZeroBytes = Get-G7MemoryCounterValue $memory "FreeAndZeroPageListBytes"
        $modifiedBytes = Get-G7MemoryCounterValue $memory "ModifiedPageListBytes"
        $pagedPoolBytes = Get-G7MemoryCounterValue $memory "PoolPagedBytes"
        $pagedPoolResidentBytes = Get-G7MemoryCounterValue $memory "PoolPagedResidentBytes"
        $nonpagedPoolBytes = Get-G7MemoryCounterValue $memory "PoolNonpagedBytes"
        $systemCacheBytes = Get-G7MemoryCounterValue $memory "SystemCacheResidentBytes"
    } catch {
        $counterError = $_.Exception.Message
        $native = Get-G7NativeMemoryCounters
        $bootTime = [DateTime]$native.boot_time_utc
        $counterSource = [string]$native.source
        $unavailableCounters = @($native.unavailable_counters)
        $totalBytes = [UInt64]$native.total_bytes
        $availableBytes = [UInt64]$native.available_bytes
        $committedBytes = [UInt64]$native.committed_bytes
        $commitLimitBytes = [UInt64]$native.commit_limit_bytes
        $freeAndZeroBytes = [UInt64]$native.free_and_zero_bytes
        $standbyBytes = [UInt64]$native.standby_bytes
        $modifiedBytes = [UInt64]$native.modified_bytes
        $pagedPoolBytes = [UInt64]$native.paged_pool_bytes
        $pagedPoolResidentBytes = [UInt64]$native.paged_pool_resident_bytes
        $nonpagedPoolBytes = [UInt64]$native.nonpaged_pool_bytes
        $systemCacheBytes = [UInt64]$native.system_cache_bytes
    }

    $mockAvailableGiB = [Environment]::GetEnvironmentVariable("G7_TEST_MOCK_AVAILABLE_GIB")
    if (-not [string]::IsNullOrWhiteSpace($mockAvailableGiB)) {
        $availableBytes = [UInt64]([double]::Parse(
                $mockAvailableGiB,
                [Globalization.CultureInfo]::InvariantCulture) * 1GB)
    }

    $workingSets = @()
    foreach ($process in @(Get-Process -ErrorAction SilentlyContinue)) {
        try {
            $workingSets += [pscustomobject][ordered]@{
                name = $process.ProcessName
                pid = [int]$process.Id
                working_set_bytes = [Int64]$process.WorkingSet64
                private_memory_bytes = [Int64]$process.PrivateMemorySize64
            }
        } catch {
            # A process can exit or become inaccessible while the list is sampled.
        }
    }

    return [pscustomobject][ordered]@{
        timestamp_utc = [DateTime]::UtcNow.ToString("o", [Globalization.CultureInfo]::InvariantCulture)
        counter_source = $counterSource
        counter_fallback_reason = $counterError
        unavailable_counters = $unavailableCounters
        boot_time_utc = $bootTime.ToUniversalTime().ToString(
            "o", [Globalization.CultureInfo]::InvariantCulture)
        uptime_seconds = [UInt64][math]::Max(0,
            ([DateTime]::UtcNow - $bootTime.ToUniversalTime()).TotalSeconds)
        total_bytes = $totalBytes
        available_bytes = $availableBytes
        committed_bytes = $committedBytes
        commit_limit_bytes = $commitLimitBytes
        free_and_zero_bytes = $freeAndZeroBytes
        standby_bytes = [UInt64]$standbyBytes
        modified_bytes = $modifiedBytes
        paged_pool_bytes = $pagedPoolBytes
        paged_pool_resident_bytes = $pagedPoolResidentBytes
        nonpaged_pool_bytes = $nonpagedPoolBytes
        system_cache_bytes = $systemCacheBytes
        process_working_set_bytes = [UInt64](($workingSets |
            Measure-Object -Property working_set_bytes -Sum).Sum)
        process_private_memory_bytes = [UInt64](($workingSets |
            Measure-Object -Property private_memory_bytes -Sum).Sum)
        top_process_working_sets = @($workingSets |
            Sort-Object -Property working_set_bytes -Descending |
            Select-Object -First $TopProcessCount)
    }
}

function Resolve-G7ApplicationPath {
    param(
        [Parameter(Mandatory = $true)] [string[]] $Names,
        [string[]] $KnownPaths = @()
    )

    foreach ($name in $Names) {
        $command = Get-Command -Name $name -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($null -ne $command) {
            return $command.Path
        }
    }
    foreach ($path in $KnownPaths) {
        if (-not [string]::IsNullOrWhiteSpace($path) -and
            (Test-Path -LiteralPath $path -PathType Leaf)) {
            return [IO.Path]::GetFullPath($path)
        }
    }
    return $null
}

function Get-G7StandbyPurgeTool {
    $programFiles = [Environment]::GetFolderPath("ProgramFiles")
    $emptyStandbyPaths = @(
        $(if ($programFiles) { Join-Path $programFiles "EmptyStandbyList\EmptyStandbyList.exe" }),
        "C:\Tools\EmptyStandbyList.exe"
    )
    $emptyStandby = Resolve-G7ApplicationPath -Names @("EmptyStandbyList.exe") `
        -KnownPaths $emptyStandbyPaths
    if ($emptyStandby) {
        return [pscustomobject]@{ name = "EmptyStandbyList"; path = $emptyStandby; arguments = @("standbylist") }
    }

    $ramMapPaths = @(
        $(if ($programFiles) { Join-Path $programFiles "Sysinternals Suite\RAMMap64.exe" }),
        $(if ($programFiles) { Join-Path $programFiles "Sysinternals Suite\RAMMap.exe" }),
        "C:\Sysinternals\RAMMap64.exe",
        "C:\Sysinternals\RAMMap.exe"
    )
    $ramMap = Resolve-G7ApplicationPath -Names @("RAMMap64.exe", "RAMMap.exe") `
        -KnownPaths $ramMapPaths
    if (-not $ramMap) {
        return $null
    }

    $eula = Get-ItemProperty -LiteralPath "HKCU:\Software\Sysinternals\RAMMap" `
        -Name EulaAccepted -ErrorAction SilentlyContinue
    if ($null -eq $eula -or $null -eq $eula.PSObject.Properties["EulaAccepted"] -or
        [int]$eula.EulaAccepted -ne 1) {
        return [pscustomobject]@{ name = "RAMMap"; path = $ramMap; arguments = @("-Et"); eula_accepted = $false }
    }
    return [pscustomobject]@{ name = "RAMMap"; path = $ramMap; arguments = @("-Et"); eula_accepted = $true }
}

function Test-G7Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-G7StandbyPurge {
    $result = [pscustomobject][ordered]@{
        attempted = $false
        status = "unavailable_not_installed"
        tool = $null
        path = $null
        exit_code = $null
        scope = "standby_list_only"
        note = "Does not trim user working sets, modified pages, or kernel pools."
    }
    $tool = Get-G7StandbyPurgeTool
    if ($null -eq $tool) {
        return $result
    }

    $result.tool = $tool.name
    $result.path = $tool.path
    if (-not (Test-G7Administrator)) {
        $result.status = "unavailable_not_elevated"
        return $result
    }
    if ($tool.name -eq "RAMMap" -and -not [bool]$tool.eula_accepted) {
        $result.status = "unavailable_eula_not_accepted"
        return $result
    }

    $result.attempted = $true
    $process = $null
    try {
        $process = Start-Process -FilePath $tool.path -ArgumentList $tool.arguments `
            -WindowStyle Hidden -PassThru -ErrorAction Stop
        if (-not $process.WaitForExit(15000)) {
            $process.Kill()
            $null = $process.WaitForExit(5000)
            $result.status = "attempt_timed_out"
            return $result
        }
        $result.exit_code = $process.ExitCode
        $result.status = $(if ($process.ExitCode -eq 0) { "completed" } else { "attempt_failed" })
    } catch {
        $result.status = "attempt_failed"
    } finally {
        if ($null -ne $process) {
            $process.Dispose()
        }
    }
    return $result
}

function Format-G7GiB {
    param([UInt64] $Bytes)
    return ($Bytes / 1GB).ToString("0.00", [Globalization.CultureInfo]::InvariantCulture)
}

function Invoke-G7MemoryPreflight {
    [CmdletBinding()]
    param(
        [switch] $Skip,
        [ValidateRange(0.0, 1024.0)]
        [double] $MinimumAvailableGiB = 0.0,
        [ValidateRange(1, 100)]
        [int] $TopProcessCount = 10,
        [string] $Label = "benchmark"
    )

    Assert-G7NoActiveServer
    $started = [DateTime]::UtcNow
    if ($Skip) {
        Write-Host "[memory] preflight skipped"
        return [pscustomobject][ordered]@{
            schema = "g7_windows_memory_preflight_v1"
            label = $Label
            started_utc = $started.ToString("o", [Globalization.CultureInfo]::InvariantCulture)
            completed_utc = [DateTime]::UtcNow.ToString("o", [Globalization.CultureInfo]::InvariantCulture)
            skipped = $true
            ready_to_launch = $true
            failure_message = $null
            minimum_available_gib = $MinimumAvailableGiB
            guard_passed = $null
            wsl_shutdown = [pscustomobject]@{ attempted = $false; status = "skipped"; exit_code = $null }
            standby_purge = [pscustomobject]@{
                attempted = $false
                status = "skipped"
                tool = $null
                path = $null
                exit_code = $null
                scope = "standby_list_only"
                note = "Does not trim user working sets, modified pages, or kernel pools."
            }
            before = $null
            after = $null
        }
    }

    $before = Get-G7MemorySnapshot -TopProcessCount $TopProcessCount
    Write-Host ("[memory] before available={0} GiB standby={1} GiB paged_pool={2} GiB" -f `
        (Format-G7GiB $before.available_bytes), (Format-G7GiB $before.standby_bytes),
        (Format-G7GiB $before.paged_pool_bytes))

    $failureMessage = $null
    $wsl = [pscustomobject][ordered]@{ attempted = $false; status = "unavailable"; exit_code = $null }
    $wslCommand = Get-Command -Name wsl.exe -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -eq $wslCommand) {
        $failureMessage = "wsl.exe is unavailable; the required WSL shutdown was not performed."
    } else {
        $wsl.attempted = $true
        $wslOutput = @(& $wslCommand.Path --shutdown 2>&1)
        $wsl.exit_code = $LASTEXITCODE
        if ($LASTEXITCODE -eq 0) {
            $wsl.status = "completed"
        } else {
            $wsl.status = "failed"
            $detail = ($wslOutput | ForEach-Object { $_.ToString() }) -join " "
            $failureMessage = "wsl.exe --shutdown failed with exit code $LASTEXITCODE. $detail".Trim()
        }
    }

    $standbyPurge = if ($null -eq $failureMessage) {
        Invoke-G7StandbyPurge
    } else {
        [pscustomobject][ordered]@{
            attempted = $false
            status = "not_attempted_wsl_failed"
            tool = $null
            path = $null
            exit_code = $null
            scope = "standby_list_only"
            note = "Does not trim user working sets, modified pages, or kernel pools."
        }
    }

    Start-Sleep -Milliseconds 500
    $after = Get-G7MemorySnapshot -TopProcessCount $TopProcessCount
    $availableGiB = $after.available_bytes / 1GB
    $guardPassed = ($availableGiB -ge $MinimumAvailableGiB)
    if (-not $guardPassed -and $null -eq $failureMessage) {
        $failureMessage = "Available memory is below the required minimum of $MinimumAvailableGiB GiB."
    }
    $ready = ($null -eq $failureMessage)

    Write-Host ("[memory] after  available={0} GiB standby={1} GiB paged_pool={2} GiB; wsl={3}; standby={4}" -f `
        (Format-G7GiB $after.available_bytes), (Format-G7GiB $after.standby_bytes),
        (Format-G7GiB $after.paged_pool_bytes), $wsl.status, $standbyPurge.status)

    return [pscustomobject][ordered]@{
        schema = "g7_windows_memory_preflight_v1"
        label = $Label
        started_utc = $started.ToString("o", [Globalization.CultureInfo]::InvariantCulture)
        completed_utc = [DateTime]::UtcNow.ToString("o", [Globalization.CultureInfo]::InvariantCulture)
        skipped = $false
        ready_to_launch = $ready
        failure_message = $failureMessage
        minimum_available_gib = $MinimumAvailableGiB
        guard_passed = $guardPassed
        wsl_shutdown = $wsl
        standby_purge = $standbyPurge
        before = $before
        after = $after
    }
}

function Write-G7MemoryPreflightTelemetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] $Telemetry,
        [Parameter(Mandatory = $true)] [string] $Path,
        [switch] $Append
    )

    $fullPath = [IO.Path]::GetFullPath($Path)
    $directory = Split-Path -Parent $fullPath
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $json = $Telemetry | ConvertTo-Json -Depth 8 -Compress
    $encoding = New-Object Text.UTF8Encoding($false)
    if ($Append) {
        [IO.File]::AppendAllText($fullPath, $json + [Environment]::NewLine, $encoding)
    } else {
        [IO.File]::WriteAllText($fullPath, $json + [Environment]::NewLine, $encoding)
    }
}
