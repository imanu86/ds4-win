# Locale-independent Windows performance counters (ASCII, PS 5.1 safe).

function Initialize-G7PdhEnglishSampler {
    if ("G7PdhEnglishSampler" -as [type]) {
        return
    }

    Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public sealed class G7PdhEnglishSampler : IDisposable {
    [StructLayout(LayoutKind.Explicit)]
    private struct FormattedValue {
        [FieldOffset(0)] public uint status;
        [FieldOffset(8)] public double value;
    }

    [DllImport("pdh.dll", CharSet = CharSet.Unicode)]
    private static extern uint PdhOpenQuery(
        string source, IntPtr userData, out IntPtr query);

    [DllImport("pdh.dll", CharSet = CharSet.Unicode,
        EntryPoint = "PdhAddEnglishCounterW")]
    private static extern uint PdhAddEnglishCounter(
        IntPtr query, string path, IntPtr userData, out IntPtr counter);

    [DllImport("pdh.dll")]
    private static extern uint PdhCollectQueryData(IntPtr query);

    [DllImport("pdh.dll")]
    private static extern uint PdhGetFormattedCounterValue(
        IntPtr counter, uint format, out uint type, out FormattedValue value);

    [DllImport("pdh.dll")]
    private static extern uint PdhCloseQuery(IntPtr query);

    private const uint FormatDouble = 0x00000200;
    private IntPtr query;
    private readonly Dictionary<string, IntPtr> counters =
        new Dictionary<string, IntPtr>(StringComparer.OrdinalIgnoreCase);

    public G7PdhEnglishSampler() {
        uint result = PdhOpenQuery(null, IntPtr.Zero, out query);
        if (result != 0) {
            throw new InvalidOperationException(
                "PdhOpenQuery failed: 0x" + result.ToString("X8"));
        }
    }

    public void Add(string path) {
        if (counters.ContainsKey(path)) return;
        IntPtr counter;
        uint result = PdhAddEnglishCounter(
            query, path, IntPtr.Zero, out counter);
        if (result != 0) {
            throw new InvalidOperationException(
                "PdhAddEnglishCounter failed for " + path + ": 0x" +
                result.ToString("X8"));
        }
        counters.Add(path, counter);
    }

    public void Collect() {
        uint result = PdhCollectQueryData(query);
        if (result != 0) {
            throw new InvalidOperationException(
                "PdhCollectQueryData failed: 0x" + result.ToString("X8"));
        }
    }

    public double Read(string path) {
        IntPtr counter;
        if (!counters.TryGetValue(path, out counter)) {
            throw new InvalidOperationException("PDH counter was not added: " + path);
        }
        uint type;
        FormattedValue value;
        uint result = PdhGetFormattedCounterValue(
            counter, FormatDouble, out type, out value);
        if (result != 0 || value.status != 0) {
            throw new InvalidOperationException(
                "PdhGetFormattedCounterValue failed for " + path +
                ": result=0x" + result.ToString("X8") +
                " status=0x" + value.status.ToString("X8"));
        }
        return value.value;
    }

    public void Dispose() {
        if (query != IntPtr.Zero) {
            PdhCloseQuery(query);
            query = IntPtr.Zero;
        }
    }
}
"@
}

function New-G7PdhEnglishSampler {
    param([Parameter(Mandatory=$true)][string[]]$Paths)
    Initialize-G7PdhEnglishSampler
    $sampler = New-Object G7PdhEnglishSampler
    try {
        foreach ($path in $Paths) {
            $sampler.Add($path)
        }
        $sampler.Collect()
        return $sampler
    } catch {
        $sampler.Dispose()
        throw
    }
}
