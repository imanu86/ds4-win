# G7 process-isolation helpers (ASCII only, PS 5.1 safe)

function Initialize-G7NativeProcessIsolation {
    if ("G7NativeProcessIsolation" -as [type]) {
        return
    }

    $source = @"
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

public static class G7NativeProcessIsolation {
    private const uint TH32CS_SNAPPROCESS = 0x00000002;
    private const int PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
    private const int PROCESS_VM_READ = 0x0010;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct PROCESSENTRY32 {
        public uint dwSize;
        public uint cntUsage;
        public uint th32ProcessID;
        public IntPtr th32DefaultHeapID;
        public uint th32ModuleID;
        public uint cntThreads;
        public uint th32ParentProcessID;
        public int pcPriClassBase;
        public uint dwFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)]
        public string szExeFile;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct PROCESS_BASIC_INFORMATION {
        public IntPtr Reserved1;
        public IntPtr PebBaseAddress;
        public IntPtr Reserved2_0;
        public IntPtr Reserved2_1;
        public IntPtr UniqueProcessId;
        public IntPtr Reserved3;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr CreateToolhelp32Snapshot(uint dwFlags, uint th32ProcessID);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool Process32First(IntPtr hSnapshot, ref PROCESSENTRY32 lppe);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool Process32Next(IntPtr hSnapshot, ref PROCESSENTRY32 lppe);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr hObject);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr OpenProcess(int dwDesiredAccess, bool bInheritHandle, int dwProcessId);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool ReadProcessMemory(
        IntPtr hProcess,
        IntPtr lpBaseAddress,
        byte[] lpBuffer,
        int dwSize,
        out IntPtr lpNumberOfBytesRead);

    [DllImport("ntdll.dll")]
    private static extern int NtQueryInformationProcess(
        IntPtr ProcessHandle,
        int ProcessInformationClass,
        ref PROCESS_BASIC_INFORMATION ProcessInformation,
        int ProcessInformationLength,
        out int ReturnLength);

    public static Dictionary<int, int> ParentProcessIds() {
        Dictionary<int, int> result = new Dictionary<int, int>();
        IntPtr snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
        if (snapshot == IntPtr.Zero || snapshot.ToInt64() == -1) {
            throw new Win32Exception(Marshal.GetLastWin32Error());
        }
        try {
            PROCESSENTRY32 entry = new PROCESSENTRY32();
            entry.dwSize = (uint)Marshal.SizeOf(typeof(PROCESSENTRY32));
            if (!Process32First(snapshot, ref entry)) {
                return result;
            }
            do {
                result[(int)entry.th32ProcessID] = (int)entry.th32ParentProcessID;
                entry.dwSize = (uint)Marshal.SizeOf(typeof(PROCESSENTRY32));
            } while (Process32Next(snapshot, ref entry));
            return result;
        } finally {
            CloseHandle(snapshot);
        }
    }

    private static byte[] ReadBytes(IntPtr process, IntPtr address, int length) {
        if (address == IntPtr.Zero || length <= 0) {
            return null;
        }
        byte[] buffer = new byte[length];
        IntPtr read;
        if (!ReadProcessMemory(process, address, buffer, length, out read)) {
            return null;
        }
        if (read.ToInt64() != length) {
            return null;
        }
        return buffer;
    }

    private static IntPtr ReadPointer(IntPtr process, IntPtr address) {
        byte[] bytes = ReadBytes(process, address, IntPtr.Size);
        if (bytes == null) {
            return IntPtr.Zero;
        }
        if (IntPtr.Size == 8) {
            return new IntPtr(BitConverter.ToInt64(bytes, 0));
        }
        return new IntPtr(BitConverter.ToInt32(bytes, 0));
    }

    public static string CommandLine(int pid) {
        IntPtr process = OpenProcess(
            PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_VM_READ,
            false,
            pid);
        if (process == IntPtr.Zero) {
            return null;
        }
        try {
            PROCESS_BASIC_INFORMATION pbi = new PROCESS_BASIC_INFORMATION();
            int returnLength;
            int status = NtQueryInformationProcess(
                process,
                0,
                ref pbi,
                Marshal.SizeOf(typeof(PROCESS_BASIC_INFORMATION)),
                out returnLength);
            if (status != 0 || pbi.PebBaseAddress == IntPtr.Zero) {
                return null;
            }

            int processParametersOffset = (IntPtr.Size == 8) ? 0x20 : 0x10;
            int commandLineOffset = (IntPtr.Size == 8) ? 0x70 : 0x40;
            IntPtr processParameters = ReadPointer(
                process,
                IntPtr.Add(pbi.PebBaseAddress, processParametersOffset));
            if (processParameters == IntPtr.Zero) {
                return null;
            }

            int unicodeStringSize = (IntPtr.Size == 8) ? 16 : 8;
            byte[] unicodeString = ReadBytes(
                process,
                IntPtr.Add(processParameters, commandLineOffset),
                unicodeStringSize);
            if (unicodeString == null) {
                return null;
            }

            int length = BitConverter.ToUInt16(unicodeString, 0);
            if (length <= 0 || length > 65534 || (length % 2) != 0) {
                return null;
            }
            IntPtr buffer = (IntPtr.Size == 8)
                ? new IntPtr(BitConverter.ToInt64(unicodeString, 8))
                : new IntPtr(BitConverter.ToInt32(unicodeString, 4));
            byte[] commandLineBytes = ReadBytes(process, buffer, length);
            if (commandLineBytes == null) {
                return null;
            }
            return Encoding.Unicode.GetString(commandLineBytes);
        } finally {
            CloseHandle(process);
        }
    }
}
"@
    Add-Type -TypeDefinition $source -Language CSharp -ErrorAction Stop
}

function Test-G7PowerShellProcessName {
    param([string]$Name)
    return ([string]$Name) -match "^(powershell|pwsh)(\.exe)?$"
}

function Get-G7ObjectPropertyValue {
    param(
        [Parameter(Mandatory=$true)][object]$InputObject,
        [Parameter(Mandatory=$true)][string]$Name
    )
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }
    return $property.Value
}

function Get-G7NativeParentProcessMap {
    try {
        Initialize-G7NativeProcessIsolation
        return [G7NativeProcessIsolation]::ParentProcessIds()
    } catch {
        return @{}
    }
}

function Get-G7NativeCommandLine {
    param([Parameter(Mandatory=$true)][int]$ProcessId)
    try {
        Initialize-G7NativeProcessIsolation
        return [G7NativeProcessIsolation]::CommandLine($ProcessId)
    } catch {
        return $null
    }
}

function Get-G7ProcessSnapshot {
    try {
        return [pscustomobject]@{
            method = "cim-win32-process"
            command_line_available = $true
            processes = @(Get-CimInstance Win32_Process -ErrorAction Stop)
        }
    } catch {
        $cimError = $_.Exception.Message
    }

    try {
        $parentByPid = Get-G7NativeParentProcessMap
        $opaquePowerShellCount = 0
        $rows = @(Get-Process -ErrorAction Stop | ForEach-Object {
            $path = ""
            $created = $null
            $parentPid = 0
            $commandLine = ""
            $commandLineStatus = "not-requested"
            try { $path = [string]$_.Path } catch { $path = "" }
            try { $created = $_.StartTime } catch { $created = $null }
            if ($parentByPid.ContainsKey([int]$_.Id)) {
                $parentPid = [int]$parentByPid[[int]$_.Id]
            }
            $name = ([string]$_.ProcessName + ".exe")
            if (Test-G7PowerShellProcessName -Name $name) {
                $commandLine = Get-G7NativeCommandLine -ProcessId ([int]$_.Id)
                if ([string]::IsNullOrWhiteSpace($commandLine)) {
                    $commandLine = ""
                    $commandLineStatus = "unavailable"
                    $opaquePowerShellCount += 1
                } else {
                    $commandLineStatus = "native-peb"
                }
            }
            [pscustomobject]@{
                ProcessId = [int]$_.Id
                ParentProcessId = $parentPid
                Name = $name
                ExecutablePath = $path
                CommandLine = $commandLine
                CommandLineStatus = $commandLineStatus
                CreationDate = $created
            }
        })
        return [pscustomobject]@{
            method = "get-process-native-fallback"
            command_line_available = ($opaquePowerShellCount -eq 0)
            cim_error = $cimError
            opaque_powershell_count = $opaquePowerShellCount
            processes = $rows
        }
    } catch {
        throw ("CIM failed: " + $cimError +
            "; Get-Process failed: " + $_.Exception.Message)
    }
}

function Get-G7MaintenanceProcessConflicts {
    param(
        [Parameter(Mandatory=$true)][object[]]$Processes,
        [Parameter(Mandatory=$true)]
        [ValidateSet("benchmark", "structural-safety", "quality")]
        [string]$GateKind
    )

    $conflicts = @()
    $blockedNames = @("defrag.exe")

    if ($GateKind -ne "structural-safety") {
        $conflicts += @($Processes | Where-Object {
            $blockedNames -contains ([string]$_.Name).ToLowerInvariant()
        } | ForEach-Object {
            $createdUtc = ""
            try {
                if ($null -ne $_.CreationDate) {
                    $createdUtc = ([DateTime]$_.CreationDate).ToUniversalTime().ToString("o")
                }
            } catch {
                $createdUtc = ""
            }
            [pscustomobject]@{
                pid = [int]$_.ProcessId
                parent_pid = [int]$_.ParentProcessId
                name = [string]$_.Name
                executable_path = [string]$_.ExecutablePath
                command_line = [string]$_.CommandLine
                created_utc = $createdUtc
                conflict_type = "storage-maintenance"
                refusal_reason = "storage-maintenance-active"
            }
        })

        $conflicts += @($Processes | Where-Object {
            $status = Get-G7ObjectPropertyValue -InputObject $_ -Name "CommandLineStatus"
            $commandLine = [string](Get-G7ObjectPropertyValue -InputObject $_ -Name "CommandLine")
            (Test-G7PowerShellProcessName -Name ([string]$_.Name)) -and
                [string]::IsNullOrWhiteSpace($commandLine) -and
                ($null -eq $status -or [string]$status -ne "native-peb")
        } | ForEach-Object {
            $createdUtc = ""
            try {
                if ($null -ne $_.CreationDate) {
                    $createdUtc = ([DateTime]$_.CreationDate).ToUniversalTime().ToString("o")
                }
            } catch {
                $createdUtc = ""
            }
            [pscustomobject]@{
                pid = [int]$_.ProcessId
                parent_pid = [int]$_.ParentProcessId
                name = [string]$_.Name
                executable_path = [string]$_.ExecutablePath
                command_line = [string]$_.CommandLine
                created_utc = $createdUtc
                conflict_type = "opaque-powershell"
                refusal_reason = "powershell-command-line-unavailable"
            }
        })
    }

    return @($conflicts)
}
