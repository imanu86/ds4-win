param(
    [Parameter(Mandatory = $true)][int]$TargetProcessId,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [ValidateRange(250, 10000)][int]$IntervalMs = 1000,
    [ValidateRange(0.0, 1024.0)][double]$MinimumAvailableGiB = 2.0,
    [ValidateRange(0.0, 100000.0)][double]$MaximumDiskQueueLength = 8.0,
    [ValidateRange(1, 60)][int]$ContaminationSamples = 3
)

$ErrorActionPreference = "Stop"
$nativeSource = @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public static class NativeTelemetry {
    public const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
    public const uint SYNCHRONIZE = 0x00100000;
    public const uint WAIT_TIMEOUT = 0x102;

    [StructLayout(LayoutKind.Sequential)]
    public struct IO_COUNTERS {
        public ulong ReadOperationCount, WriteOperationCount, OtherOperationCount;
        public ulong ReadTransferCount, WriteTransferCount, OtherTransferCount;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_MEMORY_COUNTERS_EX {
        public uint cb, PageFaultCount;
        public UIntPtr PeakWorkingSetSize, WorkingSetSize;
        public UIntPtr QuotaPeakPagedPoolUsage, QuotaPagedPoolUsage;
        public UIntPtr QuotaPeakNonPagedPoolUsage, QuotaNonPagedPoolUsage;
        public UIntPtr PagefileUsage, PeakPagefileUsage, PrivateUsage;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MEMORYSTATUSEX {
        public uint dwLength, dwMemoryLoad;
        public ulong ullTotalPhys, ullAvailPhys, ullTotalPageFile;
        public ulong ullAvailPageFile, ullTotalVirtual, ullAvailVirtual;
        public ulong ullAvailExtendedVirtual;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct FILETIME {
        public uint dwLowDateTime, dwHighDateTime;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern SafeProcessHandle OpenProcess(
        uint access, [MarshalAs(UnmanagedType.Bool)] bool inherit, uint pid);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GetProcessIoCounters(
        SafeProcessHandle process, out IO_COUNTERS counters);

    [DllImport("psapi.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GetProcessMemoryInfo(
        SafeProcessHandle process, ref PROCESS_MEMORY_COUNTERS_EX counters, uint cb);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX status);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GetProcessTimes(
        SafeProcessHandle process, out FILETIME creation, out FILETIME exit,
        out FILETIME kernel, out FILETIME user);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern uint WaitForSingleObject(
        SafeProcessHandle process, uint milliseconds);
}
'@
Add-Type -TypeDefinition $nativeSource -Language CSharp

$ioSize = [Runtime.InteropServices.Marshal]::SizeOf([type][NativeTelemetry+IO_COUNTERS])
$processMemorySize = [Runtime.InteropServices.Marshal]::SizeOf([type][NativeTelemetry+PROCESS_MEMORY_COUNTERS_EX])
$memoryStatusSize = [Runtime.InteropServices.Marshal]::SizeOf([type][NativeTelemetry+MEMORYSTATUSEX])
$fileTimeSize = [Runtime.InteropServices.Marshal]::SizeOf([type][NativeTelemetry+FILETIME])
if ($ioSize -ne 48 -or $processMemorySize -ne 80 -or
    $memoryStatusSize -ne 64 -or $fileTimeSize -ne 8) {
    throw "Unexpected native telemetry ABI sizes: io=$ioSize process=$processMemorySize memory=$memoryStatusSize filetime=$fileTimeSize"
}

$handle = [NativeTelemetry]::OpenProcess(
    ([NativeTelemetry]::PROCESS_QUERY_LIMITED_INFORMATION -bor [NativeTelemetry]::SYNCHRONIZE),
    $false, [uint32]$TargetProcessId)
if (-not $handle -or $handle.IsInvalid) {
    throw "OpenProcess failed for PID $TargetProcessId"
}

$startedUtc = (Get-Date).ToUniversalTime()
$clock = [Diagnostics.Stopwatch]::StartNew()
$nextSampleMs = 0.0
$utf8 = New-Object System.Text.UTF8Encoding($false)
$writer = New-Object System.IO.StreamWriter($OutputPath, $false, $utf8)
$writer.AutoFlush = $true

function Get-GpuProcessMemory {
    param([int]$TargetPid)
    $shared = [Int64]0
    $dedicated = [Int64]0
    $seen = $false
    try {
        $paths = @(
            "\GPU Process Memory(pid_${TargetPid}_*)\Shared Usage",
            "\GPU Process Memory(pid_${TargetPid}_*)\Dedicated Usage"
        )
        $sample = Get-Counter -Counter $paths -ErrorAction Stop
        foreach ($counter in $sample.CounterSamples) {
            $seen = $true
            if ($counter.Path -match "Shared Usage$") {
                $shared += [Int64]$counter.CookedValue
            } elseif ($counter.Path -match "Dedicated Usage$") {
                $dedicated += [Int64]$counter.CookedValue
            }
        }
    } catch { $seen = $false }
    return [pscustomobject]@{
        seen = $seen
        shared_bytes = if ($seen) { $shared } else { $null }
        dedicated_bytes = if ($seen) { $dedicated } else { $null }
    }
}

function Get-PhysicalDiskSample {
    try {
        $row = Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk `
            -ErrorAction Stop | Where-Object { $_.Name -eq "_Total" } |
            Select-Object -First 1
        if (-not $row) { throw "PhysicalDisk _Total was not found" }
        return [pscustomobject]@{
            seen = $true
            percent_time = [double]$row.PercentDiskTime
            bytes_per_second = [double]$row.DiskBytesPersec
            read_bytes_per_second = [double]$row.DiskReadBytesPersec
            write_bytes_per_second = [double]$row.DiskWriteBytesPersec
            queue_length = [double]$row.CurrentDiskQueueLength
        }
    } catch {
        return [pscustomobject]@{
            seen = $false
            percent_time = $null
            bytes_per_second = $null
            read_bytes_per_second = $null
            write_bytes_per_second = $null
            queue_length = $null
        }
    }
}

function Start-NvidiaSample {
    try {
        $info = New-Object Diagnostics.ProcessStartInfo
        $info.FileName = "nvidia-smi.exe"
        $info.Arguments = "--query-gpu=utilization.gpu,memory.used,memory.total,power.draw,clocks.sm,clocks.mem --format=csv,noheader,nounits"
        $info.UseShellExecute = $false
        $info.CreateNoWindow = $true
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true
        $process = New-Object Diagnostics.Process
        $process.StartInfo = $info
        if (-not $process.Start()) { return $null }
        return $process
    } catch { return $null }
}

function Complete-NvidiaSample {
    param([Diagnostics.Process]$Process)
    if (-not $Process) { return $null }
    try {
        if (-not $Process.WaitForExit(750)) {
            $Process.Kill()
            $Process.WaitForExit()
            return $null
        }
        $raw = $Process.StandardOutput.ReadToEnd()
        if ($Process.ExitCode -ne 0 -or -not $raw) { return $null }
        $parts = @(($raw.Trim().Split("`n")[0]).Split(',') | ForEach-Object { $_.Trim() })
        if ($parts.Count -lt 6 -or $parts -contains "N/A") { return $null }
        $culture = [Globalization.CultureInfo]::InvariantCulture
        return [pscustomobject]@{
            utilization_percent = [double]::Parse($parts[0], $culture)
            vram_used_mib = [double]::Parse($parts[1], $culture)
            vram_total_mib = [double]::Parse($parts[2], $culture)
            power_watts = [double]::Parse($parts[3], $culture)
            sm_clock_mhz = [double]::Parse($parts[4], $culture)
            memory_clock_mhz = [double]::Parse($parts[5], $culture)
        }
    } catch { return $null }
    finally { $Process.Dispose() }
}

function Convert-FileTimeToSeconds {
    param([NativeTelemetry+FILETIME]$Value)
    $ticks = ([uint64]$Value.dwHighDateTime * [uint64]4294967296) + [uint64]$Value.dwLowDateTime
    return [double]$ticks / 10000000.0
}

$contaminationCount = 0
try {
    while ([NativeTelemetry]::WaitForSingleObject($handle, 0) -eq [NativeTelemetry]::WAIT_TIMEOUT) {
        $remainingMs = [int][math]::Ceiling($nextSampleMs - $clock.Elapsed.TotalMilliseconds)
        if ($remainingMs -gt 0) { Start-Sleep -Milliseconds $remainingMs }
        if ([NativeTelemetry]::WaitForSingleObject($handle, 0) -ne [NativeTelemetry]::WAIT_TIMEOUT) { break }

        $nvidiaProcess = Start-NvidiaSample
        $gpuMemory = Get-GpuProcessMemory -TargetPid $TargetProcessId
        $disk = Get-PhysicalDiskSample

        $io = New-Object NativeTelemetry+IO_COUNTERS
        $processMemory = New-Object NativeTelemetry+PROCESS_MEMORY_COUNTERS_EX
        $processMemory.cb = [uint32]$processMemorySize
        $memory = New-Object NativeTelemetry+MEMORYSTATUSEX
        $memory.dwLength = [uint32]$memoryStatusSize
        $creation = New-Object NativeTelemetry+FILETIME
        $exit = New-Object NativeTelemetry+FILETIME
        $kernel = New-Object NativeTelemetry+FILETIME
        $user = New-Object NativeTelemetry+FILETIME
        $haveIo = [NativeTelemetry]::GetProcessIoCounters($handle, [ref]$io)
        $haveProcessMemory = [NativeTelemetry]::GetProcessMemoryInfo(
            $handle, [ref]$processMemory, [uint32]$processMemorySize)
        $haveMemory = [NativeTelemetry]::GlobalMemoryStatusEx([ref]$memory)
        $haveTimes = [NativeTelemetry]::GetProcessTimes(
            $handle, [ref]$creation, [ref]$exit, [ref]$kernel, [ref]$user)
        $gpu = Complete-NvidiaSample -Process $nvidiaProcess
        $lowMemory = $haveMemory -and
            ([double]$memory.ullAvailPhys -le $MinimumAvailableGiB * 1GB)
        $highQueue = $disk.seen -and
            ([double]$disk.queue_length -ge $MaximumDiskQueueLength)
        if ($lowMemory -and $highQueue) {
            $contaminationCount++
        } else {
            $contaminationCount = 0
        }
        $contaminationAbort = $contaminationCount -ge $ContaminationSamples

        $sample = [ordered]@{
            timestamp_utc = $startedUtc.AddMilliseconds($clock.Elapsed.TotalMilliseconds).ToString("o")
            elapsed_seconds = [math]::Round($clock.Elapsed.TotalSeconds, 3)
            pid = $TargetProcessId
            cpu_seconds = if ($haveTimes) { (Convert-FileTimeToSeconds $kernel) + (Convert-FileTimeToSeconds $user) } else { $null }
            working_set_bytes = if ($haveProcessMemory) { [Int64]$processMemory.WorkingSetSize.ToUInt64() } else { $null }
            private_bytes = if ($haveProcessMemory) { [Int64]$processMemory.PrivateUsage.ToUInt64() } else { $null }
            paged_bytes = if ($haveProcessMemory) { [Int64]$processMemory.PagefileUsage.ToUInt64() } else { $null }
            read_transfer_bytes = if ($haveIo) { [Int64]$io.ReadTransferCount } else { $null }
            write_transfer_bytes = if ($haveIo) { [Int64]$io.WriteTransferCount } else { $null }
            read_operation_count = if ($haveIo) { [Int64]$io.ReadOperationCount } else { $null }
            other_operation_count = if ($haveIo) { [Int64]$io.OtherOperationCount } else { $null }
            page_faults = if ($haveProcessMemory) { [Int64]$processMemory.PageFaultCount } else { $null }
            windows_available_bytes = if ($haveMemory) { [Int64]$memory.ullAvailPhys } else { $null }
            gpu_process_shared_bytes = $gpuMemory.shared_bytes
            gpu_process_dedicated_bytes = $gpuMemory.dedicated_bytes
            disk = $disk
            contamination_consecutive_samples = $contaminationCount
            contamination_abort = $contaminationAbort
            nvidia = $gpu
        }
        $writer.WriteLine(($sample | ConvertTo-Json -Compress -Depth 4))
        if ($contaminationAbort) {
            Stop-Process -Id $TargetProcessId -Force -ErrorAction SilentlyContinue
            break
        }
        $nextSampleMs += $IntervalMs
    }
} finally {
    $writer.Dispose()
    $handle.Dispose()
}
