[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('B')]
    [string]$Arm = 'B',
    [ValidatePattern('^[A-Za-z0-9_-]+$')]
    [string]$Tag = '',
    [ValidateRange(60, 14400)]
    [int]$TimeoutSec = 7200,
    [ValidateRange(60, 14400)]
    [int]$StartupAbsoluteCapSec = 2700,
    [switch]$StaticCheckOnly,
    [switch]$LifecycleSelfTest,
    [switch]$MockIntegration,
    [ValidateSet('success', 'exit-before-readiness', 'malformed-turn1')]
    [string]$MockScenario = 'success'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http

if (-not ('G73OwnedLoggedProcess' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.IO;
using System.Text;

public sealed class G73OwnedLoggedProcess : IDisposable
{
    private readonly object stdoutLock = new object();
    private readonly object stderrLock = new object();
    private readonly StreamWriter stdoutWriter;
    private readonly StreamWriter stderrWriter;
    private bool disposed;

    public Process Process { get; private set; }
    public int Id { get { return Process.Id; } }
    public DateTime StartTimeUtc { get { return Process.StartTime.ToUniversalTime(); } }

    private G73OwnedLoggedProcess(Process process, StreamWriter stdout, StreamWriter stderr)
    {
        Process = process;
        stdoutWriter = stdout;
        stderrWriter = stderr;
        Process.OutputDataReceived += OnStdout;
        Process.ErrorDataReceived += OnStderr;
    }

    public static G73OwnedLoggedProcess Start(
        string filePath, string[] arguments, string stdoutPath, string stderrPath)
    {
        StreamWriter stdout = null;
        StreamWriter stderr = null;
        Process process = null;
        try {
            stdout = NewWriter(stdoutPath);
            stderr = NewWriter(stderrPath);
            ProcessStartInfo info = new ProcessStartInfo();
            info.FileName = filePath;
            info.Arguments = JoinArguments(arguments);
            info.UseShellExecute = false;
            info.CreateNoWindow = true;
            info.RedirectStandardOutput = true;
            info.RedirectStandardError = true;
            process = new Process();
            process.StartInfo = info;
            G73OwnedLoggedProcess owned = new G73OwnedLoggedProcess(process, stdout, stderr);
            if (!process.Start()) {
                owned.Dispose();
                throw new InvalidOperationException("Process.Start returned false");
            }
            process.BeginOutputReadLine();
            process.BeginErrorReadLine();
            return owned;
        }
        catch {
            if (process != null) {
                try { if (!process.HasExited) { process.Kill(); process.WaitForExit(); } }
                catch { }
                process.Dispose();
            }
            if (stdout != null) { stdout.Dispose(); }
            if (stderr != null) { stderr.Dispose(); }
            throw;
        }
    }

    private static StreamWriter NewWriter(string path)
    {
        FileStream stream = new FileStream(
            path, FileMode.Create, FileAccess.Write, FileShare.ReadWrite);
        StreamWriter writer = new StreamWriter(stream, new UTF8Encoding(false));
        writer.AutoFlush = true;
        return writer;
    }

    private static string JoinArguments(string[] arguments)
    {
        if (arguments == null || arguments.Length == 0) { return String.Empty; }
        StringBuilder joined = new StringBuilder();
        for (int i = 0; i < arguments.Length; ++i) {
            if (i != 0) { joined.Append(' '); }
            joined.Append(QuoteArgument(arguments[i] ?? String.Empty));
        }
        return joined.ToString();
    }

    private static string QuoteArgument(string value)
    {
        if (value.Length != 0 && value.IndexOfAny(new char[] { ' ', '\t', '\n', '\v', '"' }) < 0) {
            return value;
        }
        StringBuilder quoted = new StringBuilder();
        quoted.Append('"');
        int backslashes = 0;
        foreach (char c in value) {
            if (c == '\\') {
                ++backslashes;
            } else if (c == '"') {
                quoted.Append('\\', backslashes * 2 + 1);
                quoted.Append('"');
                backslashes = 0;
            } else {
                quoted.Append('\\', backslashes);
                backslashes = 0;
                quoted.Append(c);
            }
        }
        quoted.Append('\\', backslashes * 2);
        quoted.Append('"');
        return quoted.ToString();
    }

    private void OnStdout(object sender, DataReceivedEventArgs args)
    {
        if (args.Data == null) { return; }
        lock (stdoutLock) { stdoutWriter.WriteLine(args.Data); }
    }

    private void OnStderr(object sender, DataReceivedEventArgs args)
    {
        if (args.Data == null) { return; }
        lock (stderrLock) { stderrWriter.WriteLine(args.Data); }
    }

    public bool HasExited()
    {
        try { Process.Refresh(); return Process.HasExited; }
        catch { return true; }
    }

    public bool WaitForExit(int timeoutMs)
    {
        return Process.WaitForExit(timeoutMs);
    }

    public int CompleteExitAndDrain()
    {
        Process.WaitForExit();
        lock (stdoutLock) { stdoutWriter.Flush(); }
        lock (stderrLock) { stderrWriter.Flush(); }
        Process.Refresh();
        return Process.ExitCode;
    }

    public void Kill()
    {
        if (!HasExited()) { Process.Kill(); }
    }

    public void Dispose()
    {
        if (disposed) { return; }
        disposed = true;
        Process.OutputDataReceived -= OnStdout;
        Process.ErrorDataReceived -= OnStderr;
        lock (stdoutLock) { stdoutWriter.Dispose(); }
        lock (stderrLock) { stderrWriter.Dispose(); }
        Process.Dispose();
    }
}
'@
}

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$runnerPath = $MyInvocation.MyCommand.Path
$exe = Join-Path $root 'build\Release\ds4_server.exe'
$model = 'C:\ds4-models\ds4-2bit.gguf'
$modelReceipt = "$model.receipt.json"
$liveOutRoot = Join-Path $root 'g7_runs\g73_live_html_b_end_to_end'
$mockOutRoot = Join-Path ([IO.Path]::GetTempPath()) 'g73_live_html_b_mock_integration'
$outRoot = if ($MockIntegration) { $mockOutRoot } else { $liveOutRoot }
$lockPath = Join-Path $outRoot 'g73_live_html_b_end_to_end_v2.lock'
$canonicalRunner = Join-Path $root 'g73_split_fused_ab.ps1'
$runtimeSource = Join-Path $root 'ds4_cuda.cu'
$buildManifestPath = Join-Path $root 'build\Release\g7_build_manifest.json'
$protocolPath = Join-Path $root 'G73_LONG_HTML_AB_SAFETY_PROTOCOL.md'
$contractTestPath = Join-Path $root 'tests\test_g73_long_html_ab_safety_contract.py'
$mockServerPath = Join-Path $root 'tests\g73_live_html_b_mock_server.py'
$mockProtocolPath = Join-Path $root 'G73_LIVE_HTML_B_MOCK_INTEGRATION_PROTOCOL.md'
$mockContractTestPath = Join-Path $root 'tests\test_g73_live_html_b_mock_integration.py'
$expectedBuildFingerprint = 'c8698dc4f5ba0dcd4e29f50c84545704140875d653f122f1a8136d82c5444daa'
$expectedExeSha = 'f703f53246331cd632e81eadba9892b8184645cc0b714ad6005ad87d2899dcfa'
$expectedModelSha = 'efc7ed607ff27076e3e501fc3fefefa33c0ed8cf1eff483a2b7fdc0c2e616668'
$expectedModelBytes = [UInt64]86720111488
$expectedCanonicalRunnerSha = '3b29ebefb0dddda13111ac9d415198f777836c405090a82bd5aa2369a88937e0'
$contextTokens = 8192
$prefillChunk = 256
$maxTokens = 3000
$temperature = 0
$think = $false
$stopSequence = '</html>'
$samplerIntervalMs = 500
$startupProgressStallSec = 300
$decodeNoProgressStallSec = 300
$samplerStallSec = 5
$decodeFloorManifest = [ordered]@{
    schema = 'g73_live_html_b_decode_abort_manifest_v1'
    predicted_decode_tps = 0.205
    abort_floor_derivation = 'predicted_decode_tps * 0.50'
    abort_floor_fraction = 0.50
    abort_floor_tps = 0.1025
    warm_tokens = 16
    consecutive_tokens = 30
    no_progress_stall_seconds = 300
}
$preflightThresholds = [ordered]@{
    gpu_vram_idle_max_mib = 700.0
    gpu_utilization_idle_max_percent = 5.0
    available_ram_floor_gib = 2.0
    c_free_floor_gib = 5.0
}
$samplerPressureThresholds = [ordered]@{
    page_reads_per_sec_max = 1000.0
    pages_per_sec_max = 100000.0
    disk_read_bytes_per_sec_max = 1073741824.0
}
$systemPrompt = 'You are a coding assistant. Follow the user instructions exactly.'
$prompt1 = 'Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document.'
$prompt1Sha = '38f6ec5ee5403f59dd2418eb5d9a5a94a0f0da19df015060383bb1ae46003bb6'
$prompt2 = 'Rendi il sito appena creato completamente dark mantenendo struttura e funzionalit' + [char]0x00E0 + '. Usa uno sfondo quasi nero, contrasto accessibile e accenti neon ciano e magenta; aggiorna coerentemente tutto il CSS e restituisci l''intero documento HTML modificato, senza spiegazioni.'
$prompt2Sha = '44d75b9687aafaca4d1312bb2516e25a44df250a367f094b7d9bea730292dfe1'

function Get-Sha256Text {
    param([AllowNull()][string]$Text)
    if ($null -eq $Text) { $Text = '' }
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return [BitConverter]::ToString(
            $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).
            Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Get-Sha256File {
    param([string]$Path)
    $stream = [IO.File]::Open(
        $Path, [IO.FileMode]::Open, [IO.FileAccess]::Read,
        [IO.FileShare]::ReadWrite)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return [BitConverter]::ToString($sha.ComputeHash($stream)).
            Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
        $stream.Dispose()
    }
}

function Write-JsonUtf8 {
    param([string]$Path, [object]$Value, [int]$Depth = 40)
    $json = $Value | ConvertTo-Json -Depth $Depth
    [IO.File]::WriteAllText($Path, $json, [Text.UTF8Encoding]::new($false))
}

function Get-ArtifactHashRecord {
    param([AllowNull()][string]$Path)
    if ([string]::IsNullOrEmpty($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }
    return [pscustomobject]@{
        path = $Path
        sha256 = Get-Sha256File $Path
        bytes = [UInt64](Get-Item -LiteralPath $Path).Length
    }
}

function Write-RunnerFailureReceipt {
    param(
        [string]$Path,
        [string]$SummaryPath,
        [string]$Stage,
        [string]$Failure,
        [AllowNull()][object]$Lifecycle,
        [string[]]$ArtifactPaths)
    $artifactRecords = @()
    foreach ($artifactPath in @($ArtifactPaths)) {
        $record = Get-ArtifactHashRecord -Path $artifactPath
        if ($record) { $artifactRecords += $record }
    }
    $receipt = [ordered]@{
        schema = 'g73_live_html_b_failure_receipt_v1'
        status = 'failed'
        native = $true
        captured_utc = [DateTime]::UtcNow.ToString('o')
        stage = $Stage
        failure = $Failure
        summary_path = $SummaryPath
        summary = Get-ArtifactHashRecord -Path $SummaryPath
        lifecycle = $Lifecycle
        artifacts = @($artifactRecords)
    }
    Write-JsonUtf8 -Path $Path -Value $receipt
    return $receipt
}

function Get-FreeTcpPort {
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    $listener.Start()
    try { return $listener.LocalEndpoint.Port }
    finally { $listener.Stop() }
}

function Convert-LineKeyValues {
    param([string]$Line)
    $map = @{}
    foreach ($match in [regex]::Matches($Line, '([A-Za-z0-9_]+)=([^ ]+)')) {
        $map[$match.Groups[1].Value] = $match.Groups[2].Value
    }
    return ,$map
}

function Convert-ToUInt64OrZero {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return [UInt64]0 }
    try { return [UInt64]([string]$Value) } catch { return [UInt64]0 }
}

function Convert-ToDoubleOrNull {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return $null }
    try {
        return [double]::Parse([string]$Value, [Globalization.CultureInfo]::InvariantCulture)
    } catch {
        return $null
    }
}

function Convert-ToDoubleInvariant {
    param([AllowNull()][object]$Value, [double]$Default = 0.0)
    $parsed = Convert-ToDoubleOrNull $Value
    if ($null -eq $parsed) { return $Default }
    return [double]$parsed
}

function Get-FileLengthSafe {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return [UInt64]0 }
    return [UInt64](Get-Item -LiteralPath $Path).Length
}

function New-FileTailState {
    param([string]$Path, [switch]$FromEnd)
    return [pscustomobject]@{
        path = $Path
        offset = if ($FromEnd) { Get-FileLengthSafe $Path } else { [UInt64]0 }
        partial = ''
    }
}

function Read-FileTailLines {
    param([object]$State)
    if (-not (Test-Path -LiteralPath $State.path -PathType Leaf)) { return @() }
    $stream = [IO.File]::Open($State.path, [IO.FileMode]::Open,
        [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        if ([UInt64]$stream.Length -lt [UInt64]$State.offset) {
            throw "monitored file truncated: $($State.path)"
        }
        [void]$stream.Seek([Int64]$State.offset, [IO.SeekOrigin]::Begin)
        $reader = [IO.StreamReader]::new($stream, [Text.UTF8Encoding]::new($false, $true),
            $true, 4096, $true)
        try {
            $text = $reader.ReadToEnd()
        } finally {
            $reader.Dispose()
        }
        $State.offset = [UInt64]$stream.Position
    } finally {
        $stream.Dispose()
    }
    if ([string]::IsNullOrEmpty($text)) { return @() }
    $combined = [string]$State.partial + $text
    $parts = $combined -split "`n", -1
    if ($combined.EndsWith("`n")) {
        $State.partial = ''
        $complete = if ($parts.Count -gt 1) { @($parts[0..($parts.Count - 2)]) } else { @() }
    } else {
        $State.partial = [string]$parts[-1]
        $complete = if ($parts.Count -gt 1) { @($parts[0..($parts.Count - 2)]) } else { @() }
    }
    return @($complete | ForEach-Object { ([string]$_).TrimEnd("`r") })
}

function Get-TextFileTail {
    param([string]$Path, [int]$Lines = 80)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    return @(Get-Content -LiteralPath $Path -Tail $Lines -ErrorAction SilentlyContinue)
}

function Invoke-NvidiaSmiSnapshot {
    try {
        $rows = @(& nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total,pstate `
            --format=csv,noheader,nounits 2>&1)
        return [pscustomobject]@{
            ok = ($LASTEXITCODE -eq 0 -and $rows.Count -gt 0)
            exit_code = $LASTEXITCODE
            output = ($rows -join "`n")
        }
    } catch {
        return [pscustomobject]@{
            ok = $false
            exit_code = $null
            output = "nvidia-smi-error:$($_.Exception.Message)"
        }
    }
}

function Write-AbortSnapshot {
    param(
        [string]$Path,
        [string]$Reason,
        [AllowNull()][object]$OwnedProcess,
        [string]$StderrPath,
        [string]$SamplerPath)
    $snapshots = @()
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        try {
            $existing = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
            $snapshots = @($existing.snapshots)
        } catch {}
    }
    $snapshots += [pscustomobject]@{
        captured_utc = [DateTime]::UtcNow.ToString('o')
        reason = $Reason
        pid = if ($OwnedProcess) { [int]$OwnedProcess.Id } else { $null }
        process_alive = if ($OwnedProcess) { Test-OwnedProcessAlive $OwnedProcess } else { $false }
        nvidia_smi = Invoke-NvidiaSmiSnapshot
        stderr_tail = @(Get-TextFileTail -Path $StderrPath -Lines 120)
        sampler_tail = @(Get-TextFileTail -Path $SamplerPath -Lines 20)
    }
    Write-JsonUtf8 -Path $Path -Value ([ordered]@{
        schema = 'g73_live_html_b_abort_snapshot_v1'
        snapshots = @($snapshots)
    }) -Depth 16
}

function Stop-OwnedProcessWithSnapshot {
    param(
        [AllowNull()][object]$OwnedProcess,
        [int]$TimeoutMs = 10000,
        [string]$SnapshotPath,
        [string]$Reason,
        [string]$StderrPath,
        [string]$SamplerPath)
    if ($OwnedProcess -and (Test-OwnedProcessAlive $OwnedProcess)) {
        Write-AbortSnapshot -Path $SnapshotPath -Reason $Reason -OwnedProcess $OwnedProcess `
            -StderrPath $StderrPath -SamplerPath $SamplerPath
    }
    return Stop-OwnedProcess -OwnedProcess $OwnedProcess -TimeoutMs $TimeoutMs
}

function Get-GpuSamplerRowCount {
    param([string]$CsvPath)
    if (-not (Test-Path -LiteralPath $CsvPath -PathType Leaf)) { return 0 }
    $count = 0
    try {
        $stream = [IO.File]::Open($CsvPath, [IO.FileMode]::Open,
            [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        try {
            $reader = [IO.StreamReader]::new($stream)
            try {
                [void]$reader.ReadLine()
                while ($null -ne $reader.ReadLine()) { $count++ }
            } finally {
                $reader.Dispose()
            }
        } finally {
            $stream.Dispose()
        }
    } catch {}
    return [int]$count
}

function Get-GpuSamplerLatestRow {
    param([string]$CsvPath)
    if (-not (Test-Path -LiteralPath $CsvPath -PathType Leaf)) { return $null }
    try {
        $last = @(Get-Content -LiteralPath $CsvPath -Tail 1 -ErrorAction Stop)
        if ($last.Count -eq 0 -or [string]::IsNullOrWhiteSpace($last[-1]) -or
            $last[-1] -match '^timestamp_utc,') { return $null }
        $headers = 'timestamp_utc,name,utilization_gpu_percent,memory_used_mib,memory_total_mib,pstate,pages_per_sec,page_reads_per_sec,disk_read_bytes_per_sec'
        return @(@($headers, $last[-1]) | ConvertFrom-Csv)[0]
    } catch {
        return $null
    }
}

function Test-SamplerPressureAbort {
    param([string]$SamplerPath)
    $row = Get-GpuSamplerLatestRow -CsvPath $SamplerPath
    if (-not $row) { return $null }
    $pages = Convert-ToDoubleInvariant $row.pages_per_sec 0.0
    $reads = Convert-ToDoubleInvariant $row.page_reads_per_sec 0.0
    $disk = Convert-ToDoubleInvariant $row.disk_read_bytes_per_sec 0.0
    if ($reads -gt [double]$samplerPressureThresholds.page_reads_per_sec_max) {
        return "paging pressure: page_reads_per_sec=$reads"
    }
    if ($pages -gt [double]$samplerPressureThresholds.pages_per_sec_max) {
        return "paging pressure: pages_per_sec=$pages"
    }
    if ($disk -gt [double]$samplerPressureThresholds.disk_read_bytes_per_sec_max) {
        return "disk pressure: disk_read_bytes_per_sec=$disk"
    }
    return $null
}

function Get-StartupProgressMetric {
    param([string]$Line)
    if ([string]::IsNullOrWhiteSpace($Line)) { return $null }
    if ($Line -match '([0-9]+(?:\.[0-9]+)?)\s+GiB cached') {
        return [pscustomobject]@{
            kind = 'cached_gib'
            value = [double]$matches[1]
            recognized = $true
        }
    }
    if ($Line -match 'loaded model layer\s+([0-9]+)\s*/\s*([0-9]+)') {
        return [pscustomobject]@{
            kind = 'model_layer'
            value = [double]([int64]$matches[1])
            recognized = $true
        }
    }
    if ($Line -match '([0-9]+)\s*/\s*([0-9]+)\s+tensors\s+loaded' -or
        $Line -match 'loaded\s+([0-9]+)\s*/\s*([0-9]+)\s+tensors') {
        return [pscustomobject]@{
            kind = 'tensors_loaded'
            value = [double]([int64]$matches[1])
            recognized = $true
        }
    }
    if ($Line -match '\b([0-9]+)\s+bytes\b') {
        return [pscustomobject]@{
            kind = 'bytes'
            value = [double]([uint64]$matches[1])
            recognized = $true
        }
    }
    if ($Line -match 'loading model tensors') {
        return [pscustomobject]@{
            kind = 'startup_marker'
            value = $null
            recognized = $true
        }
    }
    return $null
}

function Convert-NvidiaSmiGpuRows {
    param([string]$Text)
    $rows = @()
    foreach ($line in @(([string]$Text) -split "`n")) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line -match '^nvidia-smi-error:') { continue }
        $parts = @($line.Split(',') | ForEach-Object { $_.Trim() })
        if ($parts.Count -lt 5) { continue }
        $rows += [pscustomobject]@{
            name = $parts[0]
            utilization_gpu_percent = Convert-ToDoubleOrNull $parts[1]
            memory_used_mib = Convert-ToDoubleOrNull $parts[2]
            memory_total_mib = Convert-ToDoubleOrNull $parts[3]
            pstate = $parts[4]
        }
    }
    return @($rows)
}

function Test-LivePreflightLaunchGate {
    param([object]$Preflight)
    $failures = [System.Collections.ArrayList]::new()
    if (-not $Preflight) { throw 'Preflight refused launch: unable to verify preflight object' }
    $gpuRows = @(Convert-NvidiaSmiGpuRows -Text ([string]$Preflight.gpu))
    if ($gpuRows.Count -eq 0) {
        [void]$failures.Add('unable to verify gpu baseline')
    } else {
        foreach ($gpu in $gpuRows) {
            if ($null -eq $gpu.memory_used_mib -or $null -eq $gpu.memory_total_mib -or
                $null -eq $gpu.utilization_gpu_percent -or [double]$gpu.memory_total_mib -le 0) {
                [void]$failures.Add('unable to verify gpu baseline')
                continue
            }
            if ([double]$gpu.memory_used_mib -gt [double]$preflightThresholds.gpu_vram_idle_max_mib -or
                [double]$gpu.utilization_gpu_percent -gt [double]$preflightThresholds.gpu_utilization_idle_max_percent) {
                [void]$failures.Add("gpu baseline busy: mem_used_mib=$($gpu.memory_used_mib) util=$($gpu.utilization_gpu_percent)")
            }
        }
    }
    if ($null -eq $Preflight.available_ram_gib -or
        [double]$Preflight.available_ram_gib -le 0) {
        [void]$failures.Add('unable to verify available RAM')
    } elseif ([double]$Preflight.available_ram_gib -lt [double]$preflightThresholds.available_ram_floor_gib) {
        [void]$failures.Add("available RAM below floor: available_gib=$($Preflight.available_ram_gib)")
    }
    if ($null -eq $Preflight.c_free_gib -or [double]$Preflight.c_free_gib -le 0) {
        [void]$failures.Add('unable to verify free disk')
    } elseif ([double]$Preflight.c_free_gib -lt [double]$preflightThresholds.c_free_floor_gib) {
        [void]$failures.Add("free disk below floor: c_free_gib=$($Preflight.c_free_gib)")
    }
    if ($failures.Count -ne 0) {
        throw "Preflight refused launch: $(@($failures) -join '; ')"
    }
}

function Get-TraceEvents {
    param([string[]]$Lines, [string]$Marker)
    $events = @()
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]
        if ($line -notmatch "\[$([regex]::Escape($Marker))\]") { continue }
        $kv = Convert-LineKeyValues $line
        $kv['_line_number'] = $i + 1
        $kv['_line'] = $line
        $events += [pscustomobject]$kv
    }
    return @($events)
}

function Get-PrefillMassComposeEvents {
    param([string[]]$Lines)
    $events = @()
    $epoch = 0
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]
        if ($line -match '\[g73-two-turn-epoch\]\s+request_epoch=([0-9]+)') {
            $epoch = [int]$matches[1]
        }
        if ($line -notmatch '\[prefill-mass-compose\]') { continue }
        $kv = Convert-LineKeyValues $line
        $kv['request_epoch'] = $epoch
        $kv['_line_number'] = $i + 1
        $kv['_line'] = $line
        $events += [pscustomobject]$kv
    }
    return @($events)
}

function Get-LayerSetSummary {
    param(
        [string[]]$Lines,
        [string]$Marker,
        [int]$Epoch,
        [string]$Phase
    )
    $keys = New-Object 'System.Collections.Generic.HashSet[string]'
    $firstLine = $null
    $lastLine = $null
    $layerCount = 0
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]
        if ($line -notmatch "\[$([regex]::Escape($Marker))\]") { continue }
        $kv = Convert-LineKeyValues $line
        if (-not $kv.ContainsKey('request_epoch') -or
            -not $kv.ContainsKey('phase') -or
            -not $kv.ContainsKey('layer')) { continue }
        if ([int]$kv.request_epoch -ne $Epoch -or [string]$kv.phase -ne $Phase) { continue }
        if ($null -eq $firstLine) { $firstLine = $i + 1 }
        $lastLine = $i + 1
        $layerCount++
        $layer = [string]$kv.layer
        $experts = @()
        if ($kv.ContainsKey('experts') -and [string]$kv.experts -ne '') {
            $experts = @(([string]$kv.experts).Split(',') | Where-Object { $_ -ne '' })
        }
        foreach ($expert in $experts) {
            [void]$keys.Add("$layer`:$expert")
        }
    }
    $sorted = @($keys | Sort-Object)
    return [pscustomobject]@{
        marker = $Marker
        request_epoch = $Epoch
        phase = $Phase
        layers = $layerCount
        entries = $sorted.Count
        first_line = $firstLine
        last_line = $lastLine
        sha256 = Get-Sha256Text ($sorted -join "`n")
        keys = $sorted
    }
}

function Compare-LayerSets {
    param([AllowNull()][object]$A, [AllowNull()][object]$B)
    if ($null -eq $A -or $null -eq $B) {
        return [pscustomobject]@{
            comparable = $false; overlap = $null; union = $null
            jaccard = $null; entered = $null; exited = $null
        }
    }
    $setA = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($item in @($A.keys)) { [void]$setA.Add([string]$item) }
    $setB = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($item in @($B.keys)) { [void]$setB.Add([string]$item) }
    $intersection = New-Object 'System.Collections.Generic.HashSet[string]' $setA
    $intersection.IntersectWith($setB)
    $union = New-Object 'System.Collections.Generic.HashSet[string]' $setA
    $union.UnionWith($setB)
    $entered = New-Object 'System.Collections.Generic.HashSet[string]' $setB
    $entered.ExceptWith($setA)
    $exited = New-Object 'System.Collections.Generic.HashSet[string]' $setA
    $exited.ExceptWith($setB)
    $jaccard = if ($union.Count -gt 0) {
        [math]::Round([double]$intersection.Count / [double]$union.Count, 9)
    } else {
        $null
    }
    return [pscustomobject]@{
        comparable = $true
        overlap = $intersection.Count
        union = $union.Count
        jaccard = $jaccard
        entered = $entered.Count
        exited = $exited.Count
    }
}

function Get-FirstEventLine {
    param([AllowNull()][object[]]$Events, [scriptblock]$Predicate)
    $match = @($Events | Where-Object $Predicate | Select-Object -First 1)
    if ($match.Count -eq 0) { return $null }
    return [int]$match[0]._line_number
}

function Test-OwnedProcessAlive {
    param([AllowNull()][object]$OwnedProcess)
    if ($null -eq $OwnedProcess) { return $false }
    try { return -not [bool]$OwnedProcess.HasExited() }
    catch { return $false }
}

function Initialize-OwnedProcessHandle {
    param([AllowNull()][object]$OwnedProcess)
    if ($null -eq $OwnedProcess) { throw 'Owned process object is null' }
    try { [void]$OwnedProcess.Process.Handle }
    catch { throw "Failed to materialize owned process handle: $($_.Exception.Message)" }
}

function Complete-OwnedProcessExit {
    param([AllowNull()][object]$OwnedProcess, [int]$TimeoutMs)
    if ($null -eq $OwnedProcess) {
        return [pscustomobject]@{ exited = $false; exit_code = $null; reason = 'process-object-null' }
    }
    try {
        $timed = $OwnedProcess.WaitForExit($TimeoutMs)
        if (-not $timed) {
            return [pscustomobject]@{ exited = $false; exit_code = $null; reason = "timeout-ms-$TimeoutMs" }
        }
        $code = $OwnedProcess.CompleteExitAndDrain()
        if ($null -eq $code) {
            return [pscustomobject]@{ exited = $true; exit_code = $null; reason = 'exit-code-null-after-drain' }
        }
        return [pscustomobject]@{ exited = $true; exit_code = [int]$code; reason = 'ok' }
    } catch {
        return [pscustomobject]@{ exited = $false; exit_code = $null; reason = "exit-code-error:$($_.Exception.Message)" }
    }
}

function Stop-OwnedProcess {
    param([AllowNull()][object]$OwnedProcess, [int]$TimeoutMs = 10000)
    if ($null -eq $OwnedProcess) { return $true }
    try {
        if (Test-OwnedProcessAlive $OwnedProcess) { $OwnedProcess.Kill() }
        return [bool]$OwnedProcess.WaitForExit($TimeoutMs)
    } catch {
        return -not (Test-OwnedProcessAlive $OwnedProcess)
    }
}

function Start-LoggedOwnedProcess {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$StdoutPath,
        [string]$StderrPath
    )
    $owned = [G73OwnedLoggedProcess]::Start($FilePath, $Arguments, $StdoutPath, $StderrPath)
    Initialize-OwnedProcessHandle $owned
    return $owned
}

function Wait-OwnedProcessReadiness {
    param(
        [object]$OwnedProcess,
        [scriptblock]$Probe,
        [int]$TimeoutMs,
        [int]$PollMs = 100,
        [string]$LogPath = '',
        [int]$ProgressStallMs = 300000,
        [int]$StartupAbsoluteCapMs = 2700000,
        [string]$SamplerPath = '',
        [int]$SamplerStallMs = 5000,
        [switch]$ProgressAware)
    $started = [DateTime]::UtcNow
    $deadline = if ($ProgressAware) { $null } else { (Get-Date).AddMilliseconds($TimeoutMs) }
    $lastProbeError = ''
    $tail = if ($LogPath) { New-FileTailState -Path $LogPath } else { $null }
    $lastProgressUtc = [DateTime]::UtcNow
    $progressCount = 0
    $lastProgressLine = ''
    $lastCachedGib = $null
    $lastProgressMetricKind = ''
    $lastProgressMetricValue = $null
    $lastMetrics = @{}
    $lastSamplerRows = if ($SamplerPath) { Get-GpuSamplerRowCount -CsvPath $SamplerPath } else { 0 }
    $lastSamplerAdvanceUtc = [DateTime]::UtcNow
    while ($true) {
        $now = Get-Date
        if ($deadline -and $now -ge $deadline) { break }
        if (-not (Test-OwnedProcessAlive $OwnedProcess)) {
            $exit = Complete-OwnedProcessExit -OwnedProcess $OwnedProcess -TimeoutMs 5000
            return [pscustomobject]@{
                ready = $false
                status = 'process-exited-before-readiness'
                pid = [int]$OwnedProcess.Id
                elapsed_ms = [int]([DateTime]::UtcNow - $started).TotalMilliseconds
                last_probe_error = $lastProbeError
                exit = $exit
            }
        }
        if ($tail) {
            foreach ($line in @(Read-FileTailLines -State $tail)) {
                $metric = Get-StartupProgressMetric -Line $line
                if ($metric -and $null -ne $metric.value) {
                    $kind = [string]$metric.kind
                    $value = [double]$metric.value
                    if (-not $lastMetrics.ContainsKey($kind) -or
                        $value -gt [double]$lastMetrics[$kind]) {
                        $lastMetrics[$kind] = $value
                        $lastProgressUtc = [DateTime]::UtcNow
                        $progressCount++
                        $lastProgressLine = $line
                        $lastProgressMetricKind = $kind
                        $lastProgressMetricValue = $value
                        if ($kind -eq 'cached_gib') {
                            $lastCachedGib = $value
                        }
                    }
                }
            }
        }
        if ($SamplerPath) {
            $samplerRows = Get-GpuSamplerRowCount -CsvPath $SamplerPath
            if ($samplerRows -gt $lastSamplerRows) {
                $lastSamplerRows = $samplerRows
                $lastSamplerAdvanceUtc = [DateTime]::UtcNow
            } elseif (([DateTime]::UtcNow - $lastSamplerAdvanceUtc).TotalMilliseconds -gt $SamplerStallMs) {
                return [pscustomobject]@{
                    ready = $false
                    status = 'sampler-stalled-before-readiness'
                    pid = [int]$OwnedProcess.Id
                    elapsed_ms = [int]([DateTime]::UtcNow - $started).TotalMilliseconds
                    last_probe_error = $lastProbeError
                    exit = $null
                    startup_progress_count = $progressCount
                    startup_last_progress_line = $lastProgressLine
                    startup_last_cached_gib = $lastCachedGib
                    startup_last_progress_metric_kind = $lastProgressMetricKind
                    startup_last_progress_metric_value = $lastProgressMetricValue
                    sampler_rows = $lastSamplerRows
                }
            }
        }
        try {
            if ([bool](& $Probe)) {
                return [pscustomobject]@{
                    ready = $true
                    status = 'ready'
                    pid = [int]$OwnedProcess.Id
                    elapsed_ms = [int]([DateTime]::UtcNow - $started).TotalMilliseconds
                    last_probe_error = $lastProbeError
                    exit = $null
                    startup_progress_count = $progressCount
                    startup_last_progress_line = $lastProgressLine
                    startup_last_cached_gib = $lastCachedGib
                    startup_last_progress_metric_kind = $lastProgressMetricKind
                    startup_last_progress_metric_value = $lastProgressMetricValue
                    sampler_rows = $lastSamplerRows
                }
            }
        } catch {
            $lastProbeError = $_.Exception.Message
        }
        if ($ProgressAware -and
            ([DateTime]::UtcNow - $lastProgressUtc).TotalMilliseconds -gt $ProgressStallMs) {
            return [pscustomobject]@{
                ready = $false
                status = 'startup-progress-stalled'
                pid = [int]$OwnedProcess.Id
                elapsed_ms = [int]([DateTime]::UtcNow - $started).TotalMilliseconds
                last_probe_error = $lastProbeError
                exit = $null
                startup_progress_count = $progressCount
                startup_last_progress_line = $lastProgressLine
                startup_last_cached_gib = $lastCachedGib
                startup_last_progress_metric_kind = $lastProgressMetricKind
                startup_last_progress_metric_value = $lastProgressMetricValue
                sampler_rows = $lastSamplerRows
            }
        }
        if ($ProgressAware -and
            ([DateTime]::UtcNow - $started).TotalMilliseconds -gt $StartupAbsoluteCapMs) {
            return [pscustomobject]@{
                ready = $false
                status = 'startup-absolute-cap'
                pid = [int]$OwnedProcess.Id
                elapsed_ms = [int]([DateTime]::UtcNow - $started).TotalMilliseconds
                last_probe_error = $lastProbeError
                exit = $null
                startup_progress_count = $progressCount
                startup_last_progress_line = $lastProgressLine
                startup_last_cached_gib = $lastCachedGib
                startup_last_progress_metric_kind = $lastProgressMetricKind
                startup_last_progress_metric_value = $lastProgressMetricValue
                sampler_rows = $lastSamplerRows
            }
        }
        Start-Sleep -Milliseconds $PollMs
    }
    return [pscustomobject]@{
        ready = $false
        status = 'readiness-timeout'
        pid = [int]$OwnedProcess.Id
        elapsed_ms = [int]([DateTime]::UtcNow - $started).TotalMilliseconds
        last_probe_error = $lastProbeError
        exit = $null
        startup_progress_count = $progressCount
        startup_last_progress_line = $lastProgressLine
        startup_last_cached_gib = $lastCachedGib
        startup_last_progress_metric_kind = $lastProgressMetricKind
        startup_last_progress_metric_value = $lastProgressMetricValue
        sampler_rows = $lastSamplerRows
    }
}

function Open-RunLock {
    param([string]$Path, [string]$RunTag)
    try {
        $stream = [IO.File]::Open($Path, [IO.FileMode]::OpenOrCreate,
            [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    } catch [IO.IOException] {
        throw "Run lock is actively held: $Path"
    }
    $stream.SetLength(0)
    $metadata = [ordered]@{
        runner_pid = $PID
        tag = $RunTag
        created_utc = [DateTime]::UtcNow.ToString('o')
    } | ConvertTo-Json -Compress
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($metadata)
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Flush($true)
    return $stream
}

function Close-RunLock {
    param([AllowNull()][object]$LockStream, [string]$Path)
    if (-not $LockStream) { return }
    $LockStream.Dispose()
    if (Test-Path -LiteralPath $Path -PathType Leaf) { [IO.File]::Delete($Path) }
}

function Get-ServerEnvironment {
    param([string]$SelectedArm)
    $staleMaskOnly = if ($SelectedArm -eq 'A') { '1' } else { $null }
    return [ordered]@{
        DS4_BENCH_EXIT_AFTER_REQUESTS = '2'
        DS4_G73_TWO_TURN_TRACE = '1'
        DS4_G73_TWO_TURN_STALE_MASK_ONLY_AFTER_FIRST = $staleMaskOnly
        DS4_G73_TWO_TURN_STALE_EFFECTIVE_AFTER_FIRST = $null
        DS4_G73_TWO_TURN_FREEZE_AFTER_FIRST = $null
        DS4_CUDA_DYNAMIC_ARENA_CARRY_ACROSS_REQUESTS = '1'
        DS4_METAL_PREFILL_CHUNK = [string]$prefillChunk
        DS4_CUDA_STREAM_FROM_RAM_MASKED_BUDGET_GB = '2'
        DS4_CUDA_STREAM_RESERVE_MB = '1024'
        DS4_CUDA_Q8_F16_CACHE_RESERVE_MB = '4096'
        DS4_CUDA_DYNAMIC_ARENA_GB = '30'
        DS4_CUDA_PREFILL_MASS_OBSERVE = '1'
        DS4_CUDA_PREFILL_MASS_WRAP = '1'
        DS4_CUDA_ARENA_WRAP_TRUST_WORKER_CHECKSUM = '1'
        DS4_CUDA_ARENA_WRAP_SCHEDULE = 'source-parts'
        DS4_CUDA_ARENA_WRAP_UNLOCK_SOURCE_RANGES = '1'
        DS4_CUDA_ARENA_WRAP_UNLOCK_WAVE_GIB = '4'
        DS4_CUDA_PREFILL_TIER_COMPOSE = '1'
        DS4_REAP_PREFETCH_THREADS = '8'
        DS4_CUDA_NO_Q8_F16_CACHE = '1'
        DS4_CUDA_EMBED_ROW_STAGING = '1'
        DS4_CUDA_STREAMING_EXPERT_CACHE_N = '320'
        DS4_CUDA_STREAMING_EXPERT_CACHE_RESERVE_GB = '0.125'
        DS4_CUDA_PREFILL_VRAM_SEED_TOTAL = '320'
        DS4_CUDA_MOE_CACHE_POLICY = 'lru'
        DS4_CUDA_MOE_GPU_RESIDENT_ROUTES = '1'
        DS4_CUDA_MOE_ROUTE_NO_DEFAULT_SYNC = '1'
        DS4_CUDA_MOE_SPLIT_FUSED = '1'
        DS4_EXPERT_TIERING = 'enforce'
        DS4_EXPERT_TIER_POLICY = 'mass-lfru'
        DS4_EXPERT_TIER_CLOCK_CALLS = '430'
        DS4_EXPERT_TIER_REPLACEMENT_BUDGET = '32'
        DS4_EXPERT_TIER_MIN_FREQUENCY = '3'
        DS4_EXPERT_TIER_HYSTERESIS = '1.25'
    }
}

function Get-MemorySnapshot {
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        return [pscustomobject]@{
            total_ram_gib = [math]::Round($os.TotalVisibleMemorySize / 1MB, 3)
            available_ram_gib = [math]::Round($os.FreePhysicalMemory / 1MB, 3)
            source = 'cim'
        }
    } catch {}
    try {
        if (-not ('G73NativeMemory' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class G73NativeMemory {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Auto)]
  public class MEMORYSTATUSEX {
    public uint dwLength;
    public uint dwMemoryLoad;
    public ulong ullTotalPhys;
    public ulong ullAvailPhys;
    public ulong ullTotalPageFile;
    public ulong ullAvailPageFile;
    public ulong ullTotalVirtual;
    public ulong ullAvailVirtual;
    public ulong ullAvailExtendedVirtual;
    public MEMORYSTATUSEX() { dwLength = (uint)Marshal.SizeOf(typeof(MEMORYSTATUSEX)); }
  }
  [DllImport("kernel32.dll", CharSet=CharSet.Auto, SetLastError=true)]
  public static extern bool GlobalMemoryStatusEx([In, Out] MEMORYSTATUSEX lpBuffer);
}
'@
        }
        $m = [G73NativeMemory+MEMORYSTATUSEX]::new()
        if ([G73NativeMemory]::GlobalMemoryStatusEx($m)) {
            return [pscustomobject]@{
                total_ram_gib = [math]::Round($m.ullTotalPhys / 1GB, 3)
                available_ram_gib = [math]::Round($m.ullAvailPhys / 1GB, 3)
                source = 'GlobalMemoryStatusEx'
            }
        }
    } catch {}
    return [pscustomobject]@{
        total_ram_gib = $null
        available_ram_gib = $null
        source = 'unavailable'
    }
}

function Get-Preflight {
    $warnings = [System.Collections.ArrayList]::new()
    try {
        $conflicts = @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
            $_.Name -match '^(ds4_server|ds4|rclone|defrag|robocopy)\.exe$'
        } | Where-Object { $_.ProcessId -ne $PID } |
            Select-Object ProcessId, ParentProcessId, Name, CommandLine)
    } catch {
        [void]$warnings.Add("Win32_Process denied; using Get-Process fallback: $($_.Exception.Message)")
        $conflicts = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
            $_.ProcessName -match '^(ds4_server|ds4|rclone|defrag|robocopy)$'
        } | Where-Object { $_.Id -ne $PID } | ForEach-Object {
            [pscustomobject]@{
                ProcessId = $_.Id
                ParentProcessId = $null
                Name = $_.ProcessName + '.exe'
                CommandLine = 'Get-Process fallback; command line unavailable'
            }
        })
    }
    $memSnap = Get-MemorySnapshot
    $mem = $null
    try {
        $mem = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory -ErrorAction Stop
    } catch {
        [void]$warnings.Add("Memory perf counters unavailable: $($_.Exception.Message)")
    }
    $disk = @()
    try {
        $disk = @(Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk -ErrorAction Stop |
        Where-Object { $_.Name -eq '_Total' } |
        Select-Object Name, DiskReadBytesPerSec, DiskWriteBytesPerSec, AvgDiskQueueLength, PercentDiskTime)
    } catch {
        [void]$warnings.Add("Disk perf counters unavailable: $($_.Exception.Message)")
    }
    $gpu = ''
    try {
        $gpu = (& nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total,pstate `
            --format=csv,noheader,nounits) -join "`n"
    } catch {
        $gpu = "nvidia-smi-error:$($_.Exception.Message)"
    }
    $cDrive = Get-PSDrive C -ErrorAction SilentlyContinue
    $dDrive = Get-PSDrive D -ErrorAction SilentlyContinue
    return [pscustomobject]@{
        captured_utc = [DateTime]::UtcNow.ToString('o')
        probe_warnings = @($warnings)
        conflicting_processes = $conflicts
        total_ram_gib = $memSnap.total_ram_gib
        available_ram_gib = $memSnap.available_ram_gib
        ram_source = $memSnap.source
        pages_per_sec = if ($mem) { [UInt64]$mem.PagesPersec } else { $null }
        page_reads_per_sec = if ($mem) { [UInt64]$mem.PageReadsPersec } else { $null }
        disk = $disk
        gpu = $gpu
        gpu_parsed = @(Convert-NvidiaSmiGpuRows -Text $gpu)
        c_free_gib = if ($cDrive) { [math]::Round($cDrive.Free / 1GB, 3) } else { $null }
        d_free_gib = if ($dDrive) { [math]::Round($dDrive.Free / 1GB, 3) } else { $null }
        thresholds = $preflightThresholds
    }
}

function Get-PythonExecutable {
    $bundled = Join-Path $env:USERPROFILE `
        '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
    if (Test-Path -LiteralPath $bundled -PathType Leaf) { return $bundled }
    foreach ($name in @('python.exe', 'python')) {
        $command = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($command) { return [string]$command.Source }
    }
    throw 'Python executable unavailable for CPU mock integration'
}

function Get-MockPreflight {
    $conflicts = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ProcessName -match '^(ds4_server|ds4)$'
    } | ForEach-Object {
        [pscustomobject]@{ ProcessId = $_.Id; Name = $_.ProcessName + '.exe' }
    })
    $memory = Get-MemorySnapshot
    return [pscustomobject]@{
        captured_utc = [DateTime]::UtcNow.ToString('o')
        mode = 'cpu-mock'
        conflicting_processes = $conflicts
        total_ram_gib = $memory.total_ram_gib
        available_ram_gib = $memory.available_ram_gib
        ram_source = $memory.source
        gpu = 'not-probed-mock-cpu-only'
        model_accessed = $false
        native_executable_accessed = $false
    }
}

function Read-Utf8Strict {
    param([string]$Path)
    $encoding = [Text.UTF8Encoding]::new($false, $true)
    return $encoding.GetString([IO.File]::ReadAllBytes($Path))
}

function Get-MockCaptureValidation {
    param(
        [string]$CaptureDir,
        [string]$Scenario,
        [object[]]$HttpResults)
    $request1RawPath = Join-Path $CaptureDir 'request1.raw.json'
    $request2RawPath = Join-Path $CaptureDir 'request2.raw.json'
    $request1CanonicalPath = Join-Path $CaptureDir 'request1.canonical.json'
    $request2CanonicalPath = Join-Path $CaptureDir 'request2.canonical.json'
    $response1Path = Join-Path $CaptureDir 'response1.assistant.txt'
    $request1Present = Test-Path -LiteralPath $request1RawPath -PathType Leaf
    $request2Present = Test-Path -LiteralPath $request2RawPath -PathType Leaf
    $request1 = if ($request1Present) { Read-Utf8Strict $request1RawPath | ConvertFrom-Json } else { $null }
    $request2 = if ($request2Present) { Read-Utf8Strict $request2RawPath | ConvertFrom-Json } else { $null }
    $request1Messages = if ($request1) { @($request1.messages) } else { @() }
    $request2Messages = if ($request2) { @($request2.messages) } else { @() }
    $request1Roles = @($request1Messages | ForEach-Object { [string]$_.role })
    $request2Roles = @($request2Messages | ForEach-Object { [string]$_.role })
    $http1 = @($HttpResults | Where-Object { $_.name -eq 'request1' } | Select-Object -First 1)
    $runnerAssistant1 = if ($http1.Count) { [string]$http1[0].raw_assistant_text } else { $null }
    $mockAssistant1 = if (Test-Path -LiteralPath $response1Path -PathType Leaf) {
        Read-Utf8Strict $response1Path
    } else { $null }
    $request2Assistant = if ($request2Messages.Count -eq 4) {
        [string]$request2Messages[2].content
    } else { $null }
    $assistantExact = ($null -ne $runnerAssistant1 -and $null -ne $mockAssistant1 -and
        $null -ne $request2Assistant -and
        (Get-Sha256Text $runnerAssistant1) -eq (Get-Sha256Text $mockAssistant1) -and
        (Get-Sha256Text $runnerAssistant1) -eq (Get-Sha256Text $request2Assistant) -and
        [Text.Encoding]::UTF8.GetByteCount($runnerAssistant1) -eq
            [Text.Encoding]::UTF8.GetByteCount($request2Assistant))
    $request1RolesExact = (($request1Roles -join ',') -eq 'system,user')
    $request2RolesExact = (($request2Roles -join ',') -eq 'system,user,assistant,user')
    $request1ContentExact = ($request1Messages.Count -eq 2 -and
        [string]$request1Messages[0].content -eq $systemPrompt -and
        [string]$request1Messages[1].content -eq $prompt1)
    $request2ContentExact = ($request2Messages.Count -eq 4 -and
        [string]$request2Messages[0].content -eq $systemPrompt -and
        [string]$request2Messages[1].content -eq $prompt1 -and
        [string]$request2Messages[3].content -eq $prompt2)
    $controlsExact = $true
    foreach ($request in @($request1, $request2)) {
        if (-not $request) { continue }
        $controlsExact = $controlsExact -and [string]$request.stop -eq '</html>' -and
            [double]$request.temperature -eq 0 -and $request.think -eq $false
    }
    $requestCount = @(@($request1Present, $request2Present) | Where-Object { $_ }).Count
    $captureComplete = (-not $request1Present -or
        (Test-Path -LiteralPath $request1CanonicalPath -PathType Leaf)) -and
        (-not $request2Present -or (Test-Path -LiteralPath $request2CanonicalPath -PathType Leaf))
    $pass = switch ($Scenario) {
        'success' {
            $request1Present -and $request2Present -and $requestCount -eq 2 -and
            $request1RolesExact -and $request2RolesExact -and $request1ContentExact -and
            $request2ContentExact -and $assistantExact -and $controlsExact -and $captureComplete
        }
        'malformed-turn1' {
            $request1Present -and (-not $request2Present) -and $requestCount -eq 1 -and
            $request1RolesExact -and $request1ContentExact -and $controlsExact -and $captureComplete
        }
        'exit-before-readiness' {
            (-not $request1Present) -and (-not $request2Present) -and $requestCount -eq 0
        }
    }
    return [pscustomobject]@{
        pass = [bool]$pass
        scenario = $Scenario
        request_count = [int]$requestCount
        request1_present = [bool]$request1Present
        request2_present = [bool]$request2Present
        request1_roles = $request1Roles
        request2_roles = $request2Roles
        request1_roles_exact = [bool]$request1RolesExact
        request2_roles_exact = [bool]$request2RolesExact
        request1_content_exact = [bool]$request1ContentExact
        request2_content_exact = [bool]$request2ContentExact
        assistant1_byte_exact_in_request2 = [bool]$assistantExact
        assistant1_runner_sha256 = if ($null -ne $runnerAssistant1) { Get-Sha256Text $runnerAssistant1 } else { $null }
        assistant1_mock_sha256 = if ($null -ne $mockAssistant1) { Get-Sha256Text $mockAssistant1 } else { $null }
        request2_assistant_sha256 = if ($null -ne $request2Assistant) { Get-Sha256Text $request2Assistant } else { $null }
        controls_exact = [bool]$controlsExact
        capture_complete = [bool]$captureComplete
        request1_raw = Get-ArtifactHashRecord $request1RawPath
        request1_canonical = Get-ArtifactHashRecord $request1CanonicalPath
        request2_raw = Get-ArtifactHashRecord $request2RawPath
        request2_canonical = Get-ArtifactHashRecord $request2CanonicalPath
    }
}

function Write-MockValidationReceipt {
    param([string]$Path, [object]$Validation, [string]$Scenario, [string]$CaptureDir)
    $receipt = [ordered]@{
        schema = 'g73_live_html_b_mock_validation_v1'
        captured_utc = [DateTime]::UtcNow.ToString('o')
        cpu_only = $true
        no_g73_mechanism_quality_performance_claim = $true
        scenario = $Scenario
        pass = [bool]$Validation.pass
        validation = $Validation
        capture = [ordered]@{
            request1 = if ($Validation.request1_raw) {
                [ordered]@{
                    raw_sha256 = $Validation.request1_raw.sha256
                    raw_bytes = $Validation.request1_raw.bytes
                    raw_path = $Validation.request1_raw.path
                    canonical_sha256 = if ($Validation.request1_canonical) { $Validation.request1_canonical.sha256 } else { $null }
                    canonical_bytes = if ($Validation.request1_canonical) { $Validation.request1_canonical.bytes } else { $null }
                    canonical_path = if ($Validation.request1_canonical) { $Validation.request1_canonical.path } else { $null }
                }
            } else { $null }
            request2 = if ($Validation.request2_raw) {
                [ordered]@{
                    raw_sha256 = $Validation.request2_raw.sha256
                    raw_bytes = $Validation.request2_raw.bytes
                    raw_path = $Validation.request2_raw.path
                    canonical_sha256 = if ($Validation.request2_canonical) { $Validation.request2_canonical.sha256 } else { $null }
                    canonical_bytes = if ($Validation.request2_canonical) { $Validation.request2_canonical.bytes } else { $null }
                    canonical_path = if ($Validation.request2_canonical) { $Validation.request2_canonical.path } else { $null }
                }
            } else { $null }
        }
        capture_dir = $CaptureDir
    }
    Write-JsonUtf8 -Path $Path -Value $receipt
    return $receipt
}

function Add-RunnerEvent {
    param([System.Collections.ArrayList]$Events, [string]$Name, [string]$Request = '')
    [void]$Events.Add([pscustomobject]@{
        event = $Name
        request = $Request
        utc = [DateTime]::UtcNow.ToString('o')
    })
}

function Start-GpuSampler {
    param([string]$Path, [int]$IntervalMs)
    $escapedPath = $Path.Replace("'", "''")
    $scriptText = @'
        $CsvPath = '__CSV_PATH__'
        $SleepMs = __SLEEP_MS__
        [IO.File]::WriteAllText(
            $CsvPath,
            "timestamp_utc,name,utilization_gpu_percent,memory_used_mib,memory_total_mib,pstate,pages_per_sec,page_reads_per_sec,disk_read_bytes_per_sec`r`n",
            [Text.UTF8Encoding]::new($false))
        while ($true) {
            $timestamp = [DateTime]::UtcNow.ToString('o')
            $pages = ''
            $pageReads = ''
            $diskRead = ''
            try {
                $mem = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory -ErrorAction SilentlyContinue
                if ($mem) {
                    $pages = [string]$mem.PagesPersec
                    $pageReads = [string]$mem.PageReadsPersec
                }
                $disk = Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -eq '_Total' } | Select-Object -First 1
                if ($disk) { $diskRead = [string]$disk.DiskReadBytesPerSec }
            } catch {}
            try {
                $rows = @(& nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total,pstate --format=csv,noheader,nounits 2>$null)
                foreach ($row in $rows) {
                    if (-not $row) { continue }
                    Add-Content -LiteralPath $CsvPath -Encoding UTF8 -Value "$timestamp,$row,$pages,$pageReads,$diskRead"
                }
            } catch {
                Add-Content -LiteralPath $CsvPath -Encoding UTF8 -Value "$timestamp,nvidia-smi-error,0,0,0,unknown,$pages,$pageReads,$diskRead"
            }
            Start-Sleep -Milliseconds $SleepMs
        }
'@
    $scriptText = $scriptText.Replace('__CSV_PATH__', $escapedPath).
        Replace('__SLEEP_MS__', [string]$IntervalMs)
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($scriptText))
    return Start-LoggedOwnedProcess -FilePath (Join-Path $PSHOME 'powershell.exe') `
        -Arguments @('-NoProfile', '-NonInteractive', '-EncodedCommand', $encoded) `
        -StdoutPath "$Path.worker.stdout.log" -StderrPath "$Path.worker.stderr.log"
}

function Stop-GpuSampler {
    param([AllowNull()][object]$OwnedProcess)
    if ($null -eq $OwnedProcess) { return }
    try {
        if (Test-OwnedProcessAlive $OwnedProcess) {
            [void](Stop-OwnedProcess -OwnedProcess $OwnedProcess -TimeoutMs 5000)
        }
        [void](Complete-OwnedProcessExit -OwnedProcess $OwnedProcess -TimeoutMs 0)
    } finally {
        $OwnedProcess.Dispose()
    }
}

function Get-Percentile {
    param([double[]]$Values, [double]$Percent)
    if (-not $Values -or $Values.Count -eq 0) { return $null }
    $sorted = @($Values | Sort-Object)
    $index = [math]::Ceiling(($Percent / 100.0) * $sorted.Count) - 1
    if ($index -lt 0) { $index = 0 }
    if ($index -ge $sorted.Count) { $index = $sorted.Count - 1 }
    return [math]::Round([double]$sorted[$index], 3)
}

function Get-GpuStatsForWindow {
    param([object[]]$Rows, [AllowNull()][object]$StartUtc, [AllowNull()][object]$EndUtc)
    if ($null -eq $StartUtc -or $null -eq $EndUtc -or $EndUtc -le $StartUtc) {
        return [pscustomobject]@{ samples = 0 }
    }
    $selected = @($Rows | Where-Object { $_.timestamp -ge $StartUtc -and $_.timestamp -le $EndUtc })
    $utils = @($selected | ForEach-Object { [double]$_.utilization_gpu_percent })
    $mems = @($selected | ForEach-Object { [double]$_.memory_used_mib })
    $pages = @($selected | Where-Object { $null -ne $_.pages_per_sec } | ForEach-Object { [double]$_.pages_per_sec })
    $reads = @($selected | Where-Object { $null -ne $_.page_reads_per_sec } | ForEach-Object { [double]$_.page_reads_per_sec })
    $disk = @($selected | Where-Object { $null -ne $_.disk_read_bytes_per_sec } | ForEach-Object { [double]$_.disk_read_bytes_per_sec })
    return [pscustomobject]@{
        samples = $selected.Count
        util_mean = if ($utils.Count) { [math]::Round(($utils | Measure-Object -Average).Average, 3) } else { $null }
        util_median = Get-Percentile -Values $utils -Percent 50
        util_p95 = Get-Percentile -Values $utils -Percent 95
        util_max = if ($utils.Count) { [math]::Round(($utils | Measure-Object -Maximum).Maximum, 3) } else { $null }
        mem_used_mib_max = if ($mems.Count) { [math]::Round(($mems | Measure-Object -Maximum).Maximum, 3) } else { $null }
        pages_per_sec_max = if ($pages.Count) { [math]::Round(($pages | Measure-Object -Maximum).Maximum, 3) } else { $null }
        page_reads_per_sec_max = if ($reads.Count) { [math]::Round(($reads | Measure-Object -Maximum).Maximum, 3) } else { $null }
        disk_read_bytes_per_sec_max = if ($disk.Count) { [math]::Round(($disk | Measure-Object -Maximum).Maximum, 3) } else { $null }
    }
}

function Get-RunnerEventTime {
    param([object[]]$Events, [string]$Name, [string]$Request = '')
    $match = @($Events | Where-Object {
        $_.event -eq $Name -and ((-not $Request) -or $_.request -eq $Request)
    } | Select-Object -First 1)
    if ($match.Count -eq 0) { return $null }
    return [DateTime]::Parse($match[0].utc, [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::AssumeUniversal)
}

function Get-GpuSamplerSummary {
    param([string]$CsvPath, [object[]]$RunnerEvents)
    if (-not (Test-Path -LiteralPath $CsvPath -PathType Leaf)) {
        return [pscustomobject]@{ path = $CsvPath; rows = 0 }
    }
    $rows = @(Import-Csv -LiteralPath $CsvPath | ForEach-Object {
        $util = 0.0; $mem = 0.0; $total = 0.0
        $pages = 0.0; $reads = 0.0; $diskRead = 0.0
        [void][double]::TryParse($_.utilization_gpu_percent, [ref]$util)
        [void][double]::TryParse($_.memory_used_mib, [ref]$mem)
        [void][double]::TryParse($_.memory_total_mib, [ref]$total)
        $hasPages = [double]::TryParse($_.pages_per_sec, [ref]$pages)
        $hasReads = [double]::TryParse($_.page_reads_per_sec, [ref]$reads)
        $hasDisk = [double]::TryParse($_.disk_read_bytes_per_sec, [ref]$diskRead)
        [pscustomobject]@{
            timestamp = [DateTime]::Parse($_.timestamp_utc, [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::AssumeUniversal)
            utilization_gpu_percent = $util
            memory_used_mib = $mem
            memory_total_mib = $total
            pstate = $_.pstate
            pages_per_sec = if ($hasPages) { $pages } else { $null }
            page_reads_per_sec = if ($hasReads) { $reads } else { $null }
            disk_read_bytes_per_sec = if ($hasDisk) { $diskRead } else { $null }
        }
    })
    $serverStart = Get-RunnerEventTime -Events $RunnerEvents -Name 'server_start'
    $req1Start = Get-RunnerEventTime -Events $RunnerEvents -Name 'request_start' -Request 'request1'
    $req1End = Get-RunnerEventTime -Events $RunnerEvents -Name 'request_end' -Request 'request1'
    $req2Start = Get-RunnerEventTime -Events $RunnerEvents -Name 'request_start' -Request 'request2'
    $req2End = Get-RunnerEventTime -Events $RunnerEvents -Name 'request_end' -Request 'request2'
    return [pscustomobject]@{
        path = $CsvPath
        rows = $rows.Count
        interval_ms = $samplerIntervalMs
        startup = Get-GpuStatsForWindow -Rows $rows -StartUtc $serverStart -EndUtc $req1Start
        request1 = Get-GpuStatsForWindow -Rows $rows -StartUtc $req1Start -EndUtc $req1End
        request2 = Get-GpuStatsForWindow -Rows $rows -StartUtc $req2Start -EndUtc $req2End
    }
}

function Get-ConversationSha {
    param([AllowNull()][object[]]$Messages)
    $parts = @()
    foreach ($message in @($Messages)) {
        $parts += ([string]$message.role + "`n" + [string]$message.content)
    }
    return Get-Sha256Text ($parts -join "`n---message---`n")
}

function Get-GitProvenance {
    $branch = ''
    $head = ''
    $dirty = $true
    try { $branch = (& git rev-parse --abbrev-ref HEAD 2>$null) -join '' } catch {}
    try { $head = (& git rev-parse HEAD 2>$null) -join '' } catch {}
    try {
        $status = @(& git status --porcelain 2>$null)
        $dirty = $status.Count -ne 0
    } catch {
        $dirty = $true
    }
    return [pscustomobject]@{
        branch = $branch
        head = $head
        dirty = [bool]$dirty
    }
}

function Get-BuildManifestProvenance {
    if (-not (Test-Path -LiteralPath $buildManifestPath -PathType Leaf)) {
        throw "Build manifest missing: $buildManifestPath"
    }
    $manifest = Get-Content -Raw -LiteralPath $buildManifestPath | ConvertFrom-Json
    return [pscustomobject]@{
        path = $buildManifestPath
        sha256 = Get-Sha256File $buildManifestPath
        input_fingerprint_sha256 = [string]$manifest.input_fingerprint_sha256
        executable_sha256 = [string]$manifest.executable_sha256
        head = [string]$manifest.head
        worktree_dirty_at_build_start = [bool]$manifest.worktree_dirty_at_build_start
        completed_utc = [string]$manifest.completed_utc
    }
}

function Normalize-HtmlDocument {
    param(
        [AllowNull()][string]$Content,
        [AllowNull()][string]$FinishReason
    )
    if ($null -eq $Content) { $Content = '' }
    if ($null -eq $FinishReason) { $FinishReason = '' }
    $raw = [string]$Content
    $trimmed = $raw.Trim()
    $hasFence = $raw -match '```'
    $lowerRaw = $raw.ToLowerInvariant()
    $startDoctype = $lowerRaw.IndexOf('<!doctype')
    $startHtml = $lowerRaw.IndexOf('<html')
    $startCandidates = @($startDoctype, $startHtml) | Where-Object { $_ -ge 0 } | Sort-Object
    $start = if ($startCandidates.Count -gt 0) { [int]$startCandidates[0] } else { -1 }
    $observedEnd = $lowerRaw.LastIndexOf($stopSequence)
    $rawPrefix = if ($start -gt 0) { $raw.Substring(0, $start) } else { '' }
    $rawSuffix = if ($observedEnd -ge 0) {
        $raw.Substring($observedEnd + $stopSequence.Length)
    } else {
        ''
    }
    $rawOnlyHtmlContract = ($start -ge 0) -and (-not $hasFence) -and
        ($rawPrefix.Trim().Length -eq 0) -and
        ($observedEnd -lt 0 -or $rawSuffix.Trim().Length -eq 0)

    $text = $trimmed
    $lower = $text.ToLowerInvariant()
    $start = $lower.IndexOf('<!doctype')
    if ($start -lt 0) { $start = $lower.IndexOf('<html') }
    if ($start -gt 0) { $text = $text.Substring($start) }
    $lower = $text.ToLowerInvariant()
    $end = $lower.LastIndexOf($stopSequence)
    $stopReinjected = $false
    $missingStopSequence = $end -lt 0
    if ($end -ge 0) {
        $text = $text.Substring(0, $end + $stopSequence.Length)
    } elseif ($FinishReason -eq 'stop') {
        $text = $text.TrimEnd() + $stopSequence
        $stopReinjected = $true
    }
    $stopContractValid = ($FinishReason -eq 'stop') -and ((-not $missingStopSequence) -or $stopReinjected)
    return [pscustomobject]@{
        document = $text
        finish_reason = $FinishReason
        finish_reason_is_stop = [bool]($FinishReason -eq 'stop')
        stop_sequence_observed = [bool](-not $missingStopSequence)
        stop_reinjected = $stopReinjected
        stop_contract_valid = [bool]$stopContractValid
        raw_only_html_contract = [bool]$rawOnlyHtmlContract
        raw_has_markdown_fence = [bool]$hasFence
        raw_prefix_non_whitespace = [bool]($rawPrefix.Trim().Length -ne 0)
        raw_suffix_non_whitespace = [bool]($observedEnd -ge 0 -and $rawSuffix.Trim().Length -ne 0)
        raw_sha256 = Get-Sha256Text $raw
        document_sha256 = Get-Sha256Text $text
        raw_length = $raw.Length
        document_length = $text.Length
    }
}

function Test-Turn1ReadyForTurn2 {
    param([AllowNull()][object]$Request, [AllowNull()][object]$Quality)
    $ready = ($Request -and $Quality -and
        [string]$Request.finish_reason -eq 'stop' -and
        [bool]$Request.stop_contract_valid -and
        [bool]$Request.raw_only_html_contract -and
        [bool]$Quality.pass)
    return [pscustomobject]@{
        pass = [bool]$ready
        finish_reason = if ($Request) { [string]$Request.finish_reason } else { $null }
        stop_contract_valid = if ($Request) { [bool]$Request.stop_contract_valid } else { $false }
        raw_only_html_contract = if ($Request) { [bool]$Request.raw_only_html_contract } else { $false }
        quality_pass = if ($Quality) { [bool]$Quality.pass } else { $false }
    }
}

function Write-LiveChatTranscript {
    param(
        [string]$OutDir,
        [AllowNull()][object]$Turn1,
        [AllowNull()][string]$Turn1Raw,
        [AllowNull()][object]$Turn2,
        [AllowNull()][string]$Turn2Raw
    )
    $messages = [System.Collections.ArrayList]::new()
    [void]$messages.Add([pscustomobject]@{
        ordinal = 1
        role = 'USER'
        turn = 'turn1'
        content = $prompt1
        sha256 = Get-Sha256Text $prompt1
        expected_sha256 = $prompt1Sha
        bytes = [Text.Encoding]::UTF8.GetByteCount($prompt1)
        artifact_path = $null
        byte_exact = ((Get-Sha256Text $prompt1) -eq $prompt1Sha)
    })
    if ($Turn1 -and $null -ne $Turn1Raw) {
        [void]$messages.Add([pscustomobject]@{
            ordinal = 2
            role = 'ASSISTANT'
            turn = 'turn1'
            content = $Turn1Raw
            sha256 = Get-Sha256Text $Turn1Raw
            expected_sha256 = $Turn1.raw_assistant_sha256
            bytes = [Text.Encoding]::UTF8.GetByteCount($Turn1Raw)
            artifact_path = $Turn1.raw_assistant_path
            byte_exact = ((Get-Sha256Text $Turn1Raw) -eq [string]$Turn1.raw_assistant_sha256)
        })
    }
    if ($Turn2) {
        [void]$messages.Add([pscustomobject]@{
            ordinal = 3
            role = 'USER'
            turn = 'turn2'
            content = $prompt2
            sha256 = Get-Sha256Text $prompt2
            expected_sha256 = $prompt2Sha
            bytes = [Text.Encoding]::UTF8.GetByteCount($prompt2)
            artifact_path = $null
            byte_exact = ((Get-Sha256Text $prompt2) -eq $prompt2Sha)
        })
    }
    if ($Turn2 -and $null -ne $Turn2Raw) {
        [void]$messages.Add([pscustomobject]@{
            ordinal = 4
            role = 'ASSISTANT'
            turn = 'turn2'
            content = $Turn2Raw
            sha256 = Get-Sha256Text $Turn2Raw
            expected_sha256 = $Turn2.raw_assistant_sha256
            bytes = [Text.Encoding]::UTF8.GetByteCount($Turn2Raw)
            artifact_path = $Turn2.raw_assistant_path
            byte_exact = ((Get-Sha256Text $Turn2Raw) -eq [string]$Turn2.raw_assistant_sha256)
        })
    }
    $jsonPath = Join-Path $OutDir 'chat_transcript.messages.json'
    $mdPath = Join-Path $OutDir 'chat_transcript.md'
    $messages | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# G73 Live HTML B Chat Transcript')
    $lines.Add('')
    $lines.Add('Byte-exact message bodies are between BEGIN MESSAGE and END MESSAGE markers.')
    foreach ($m in @($messages)) {
        $lines.Add('')
        $lines.Add("## $($m.role) $($m.turn)")
        $lines.Add("sha256: $($m.sha256)")
        $lines.Add("bytes_utf8: $($m.bytes)")
        $lines.Add("artifact_path: $($m.artifact_path)")
        $lines.Add("byte_exact: $($m.byte_exact)")
        $lines.Add('BEGIN MESSAGE')
        $lines.Add([string]$m.content)
        $lines.Add('END MESSAGE')
    }
    [IO.File]::WriteAllText($mdPath, ($lines -join [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    return [pscustomobject]@{
        markdown_path = $mdPath
        markdown_sha256 = Get-Sha256File $mdPath
        messages_json_path = $jsonPath
        messages_json_sha256 = Get-Sha256File $jsonPath
        messages = @($messages | ForEach-Object {
            [pscustomobject]@{
                ordinal = $_.ordinal
                role = $_.role
                turn = $_.turn
                sha256 = $_.sha256
                expected_sha256 = $_.expected_sha256
                bytes = $_.bytes
                artifact_path = $_.artifact_path
                byte_exact = $_.byte_exact
            }
        })
    }
}

function Test-HtmlQuality {
    param(
        [string]$Turn,
        [string]$Document,
        [AllowNull()][object]$Turn1Quality
    )
    if ($null -eq $Document) { $Document = '' }
    $lower = $Document.ToLowerInvariant()
    $hasHtmlOpen = $lower -match '<html\b'
    $hasHtmlClose = $lower -match '</html>'
    $hasHead = $lower -match '<head\b'
    $hasBody = $lower -match '<body\b'
    $hasCss = ($lower -match '<style\b') -or ($lower -match 'rel=["'']stylesheet')
    $hasNav = ($lower -match '<nav\b') -or ($lower -match 'role=["'']navigation') -or ($lower -match '\bnav\b')
    $hasHero = ($lower -match 'hero') -or ($lower -match '<h1\b')
    $hasForm = $lower -match '<form\b'
    $hasScript = $lower -match '<script\b'
    $hasPopup = ($lower -match 'alert\s*\(') -or ($lower -match 'confirm\s*\(') -or
        ($lower -match 'dialog') -or ($lower -match 'addEventListener'.ToLowerInvariant())
    $hasFence = $Document -match '```'
    $dark = ($lower -match 'background[^;{]*(#0[0-9a-f]{2,4}|#000|black|rgb\s*\(\s*0\s*,\s*0\s*,\s*0)') -or
        ($lower -match '#050505|#060606|#070707|#080808|#090909|#0a0a0a|#0b0b0b|#0c0c0c|#0d0d0d|#0e0e0e|#0f0f0f')
    $contrast = ($lower -match 'color[^;{]*(#fff|#f[0-9a-f]{2,5}|white|rgb\s*\(\s*2[0-5][0-9]\s*,\s*2[0-5][0-9]\s*,\s*2[0-5][0-9])')
    $cyan = ($lower -match 'cyan|#00ffff|#0ff|#00e5ff|#22d3ee|rgb\s*\(\s*0\s*,\s*(2[0-5][0-9]|1[5-9][0-9])\s*,\s*(2[0-5][0-9]|1[5-9][0-9])')
    $magenta = ($lower -match 'magenta|#ff00ff|#f0f|#ff2bd6|#ec4899|rgb\s*\(\s*(2[0-5][0-9]|1[5-9][0-9])\s*,\s*0\s*,\s*(2[0-5][0-9]|1[5-9][0-9])')
    $parseable = $hasHtmlOpen -and $hasHtmlClose -and $hasHead -and $hasBody -and (-not $hasFence)
    $basePass = $parseable -and $hasCss -and $hasNav -and $hasHero -and $hasForm -and $hasScript -and $hasPopup
    $preserved = $true
    if ($Turn -eq 'turn2' -and $Turn1Quality) {
        $preserved = ((-not $Turn1Quality.has_nav) -or $hasNav) -and
            ((-not $Turn1Quality.has_hero) -or $hasHero) -and
            ((-not $Turn1Quality.has_form) -or $hasForm) -and
            ((-not $Turn1Quality.has_script) -or $hasScript) -and
            ((-not $Turn1Quality.has_popup) -or $hasPopup)
    }
    $pass = if ($Turn -eq 'turn2') {
        $basePass -and $dark -and $contrast -and $cyan -and $magenta -and $preserved
    } else {
        $basePass
    }
    return [pscustomobject]@{
        turn = $Turn
        pass = [bool]$pass
        parseable_html = [bool]$parseable
        has_html_open = [bool]$hasHtmlOpen
        has_html_close = [bool]$hasHtmlClose
        has_head = [bool]$hasHead
        has_body = [bool]$hasBody
        has_css = [bool]$hasCss
        has_nav = [bool]$hasNav
        has_hero = [bool]$hasHero
        has_form = [bool]$hasForm
        has_script = [bool]$hasScript
        has_popup = [bool]$hasPopup
        dark_almost_black = [bool]$dark
        contrast_heuristic = [bool]$contrast
        cyan_accent = [bool]$cyan
        magenta_accent = [bool]$magenta
        preserved_structure_functionality = [bool]$preserved
        has_markdown_fence = [bool]$hasFence
    }
}

function New-RenderManifest {
    param([string]$OutDir, [AllowNull()][object]$Turn1, [AllowNull()][object]$Turn2)
    $manifestPath = Join-Path $OutDir 'render_manifest.json'
    $manifest = [ordered]@{
        schema = 'g73_long_html_render_manifest_v1'
        generated_utc = [DateTime]::UtcNow.ToString('o')
        browser_rendering_authorized = $false
        tests = @(
            [ordered]@{ name = 'render-turn1'; html_path = if ($Turn1) { $Turn1.document_path } else { $null }; check = 'load as local HTML and inspect layout' },
            [ordered]@{ name = 'render-turn2'; html_path = if ($Turn2) { $Turn2.document_path } else { $null }; check = 'load as local HTML and inspect dark transformed layout' },
            [ordered]@{ name = 'popup-form-turn1'; html_path = if ($Turn1) { $Turn1.document_path } else { $null }; check = 'submit first form and observe popup/confirmation' },
            [ordered]@{ name = 'popup-form-turn2'; html_path = if ($Turn2) { $Turn2.document_path } else { $null }; check = 'submit first form and observe preserved popup/confirmation' }
        )
    }
    $manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    return $manifestPath
}

function Get-ModelTensorCacheEvents {
    param([string[]]$Lines)
    $events = @()
    $requestEpoch = 0
    $requestIndex = 0
    $phase = 'startup'
    $chunkStart = $null
    $chunkTotal = $null
    $decodeTokens = $null
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]
        if ($line -match '\[g73-two-turn-epoch\]\s+request_epoch=([0-9]+)') {
            $requestEpoch = [int]$matches[1]
            $phase = 'request-begin'
            $chunkStart = $null
            $chunkTotal = $null
            $decodeTokens = $null
        } elseif ($line -match 'ds4-server: chat .* prompt start') {
            $requestIndex++
            $phase = 'prompt-start'
        } elseif ($line -match 'prefill chunk ([0-9]+)/([0-9]+)') {
            $phase = 'prefill'
            $chunkStart = [int]$matches[1]
            $chunkTotal = [int]$matches[2]
        } elseif ($line -match 'ds4-server: chat .* prompt done') {
            $phase = 'decode'
            $chunkStart = $null
            $chunkTotal = $null
        } elseif ($line -match 'ds4-server: chat .* gen=([0-9]+) decoding') {
            $phase = 'decode'
            $decodeTokens = [int]$matches[1]
        } elseif ($line -match 'ds4-server: chat .* gen=([0-9]+) finish=') {
            $phase = 'finish'
            $decodeTokens = [int]$matches[1]
        }
        if ($line -match 'CUDA loading model tensors into device cache') {
            $events += [pscustomobject]@{
                line_number = $i + 1; kind = 'startup-begin'
                request_epoch = $requestEpoch; request_index = $requestIndex
                phase = $phase; prefill_chunk_start = $chunkStart
                prefill_chunk_total = $chunkTotal; decode_tokens = $decodeTokens
                cached_gib = $null; line = $line
            }
        } elseif ($line -match 'CUDA loading model tensors ([0-9.]+) GiB cached') {
            $events += [pscustomobject]@{
                line_number = $i + 1; kind = 'progress'
                request_epoch = $requestEpoch; request_index = $requestIndex
                phase = $phase; prefill_chunk_start = $chunkStart
                prefill_chunk_total = $chunkTotal; decode_tokens = $decodeTokens
                cached_gib = [double]$matches[1]; line = $line
            }
        }
    }
    return @($events)
}

function Get-RuntimeModelTensorReloadEvents {
    param([string]$LogPath)
    if (-not (Test-Path -LiteralPath $LogPath -PathType Leaf)) { return @() }
    $lines = @(Get-Content -LiteralPath $LogPath)
    return @(Get-ModelTensorCacheEvents $lines |
        Where-Object { $_.kind -eq 'progress' -and [int]$_.request_index -gt 0 })
}

function Get-UnsafeTierEvents {
    param([string]$LogPath)
    if (-not (Test-Path -LiteralPath $LogPath -PathType Leaf)) { return @() }
    $lines = @(Get-Content -LiteralPath $LogPath)
    return @(Get-TraceEvents $lines 'g73-two-turn-tier' |
        Where-Object {
            (Convert-ToUInt64OrZero $_.snapshot_backing_misses) -ne 0 -or
            (Convert-ToUInt64OrZero $_.ssd_bytes) -ne 0 -or
            (Convert-ToUInt64OrZero $_.failures) -ne 0 -or
            (Convert-ToUInt64OrZero $_.forbidden_cold_ssd_to_vram) -ne 0
        })
}

function Invoke-LongHtmlRequest {
    param(
        [string]$Uri,
        [object[]]$Messages,
        [string]$Name,
        [string]$Turn,
        [string]$OutDir,
        [object]$OwnedProcess,
        [string]$LogPath,
        [System.Collections.ArrayList]$RunnerEvents,
        [string]$SamplerPath = '',
        [string]$AbortSnapshotPath = '',
        [AllowNull()][string]$Turn1DocumentSha256Used = $null)
    $body = [ordered]@{
        model = 'deepseek-chat'
        messages = $Messages
        max_tokens = $maxTokens
        temperature = $temperature
        think = $think
        stop = $stopSequence
    }
    $json = $body | ConvertTo-Json -Depth 24
    $messagesJson = $Messages | ConvertTo-Json -Depth 24
    $messagesSha = Get-Sha256Text $messagesJson
    $conversationSha = Get-ConversationSha -Messages $Messages
    $requestPath = Join-Path $OutDir "$Name.request.json"
    $responsePath = Join-Path $OutDir "$Name.response.json"
    $rawPath = Join-Path $OutDir "$Name.raw_assistant.txt"
    $docPath = Join-Path $OutDir "$Name.document.html"
    [IO.File]::WriteAllText($requestPath, $json, [Text.UTF8Encoding]::new($false))
    Add-RunnerEvent -Events $RunnerEvents -Name 'request_start' -Request $Name
    $started = Get-Date
    $requestEpoch = if ($Name -match 'request([0-9]+)') { [int]$matches[1] } else { $null }
    $tail = New-FileTailState -Path $LogPath -FromEnd
    $tokenTimes = [System.Collections.ArrayList]::new()
    $lastDecodeToken = 0
    $lastDecodeProgressUtc = [DateTime]::UtcNow
    $decodeStarted = $false
    $lastSamplerRows = if ($SamplerPath) { Get-GpuSamplerRowCount -CsvPath $SamplerPath } else { 0 }
    $lastSamplerAdvanceUtc = [DateTime]::UtcNow
    $client = [System.Net.Http.HttpClient]::new()
    $content = $null
    $message = $null
    try {
        $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSec)
        $content = [System.Net.Http.ByteArrayContent]::new([Text.Encoding]::UTF8.GetBytes($json))
        $content.Headers.ContentType =
            [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse('application/json; charset=utf-8')
        $task = $client.PostAsync($Uri, $content)
        $deadline = (Get-Date).AddSeconds($TimeoutSec)
        while (-not $task.Wait(250)) {
            if (-not (Test-OwnedProcessAlive $OwnedProcess)) {
                throw "Owned server exited during $Name"
            }
            foreach ($line in @(Read-FileTailLines -State $tail)) {
                if ($line -match 'CUDA loading model tensors ([0-9.]+) GiB cached') {
                    [void](Stop-OwnedProcessWithSnapshot -OwnedProcess $OwnedProcess `
                        -SnapshotPath $AbortSnapshotPath -Reason "model-tensor-cache-reload-$Name" `
                        -StderrPath $LogPath -SamplerPath $SamplerPath)
                    throw "Model tensor cache reload during $Name; line=$line"
                }
                if ($line -match '\[g73-two-turn-tier\]') {
                    $kv = Convert-LineKeyValues $line
                    if ((Convert-ToUInt64OrZero $kv.snapshot_backing_misses) -ne 0 -or
                        (Convert-ToUInt64OrZero $kv.ssd_bytes) -ne 0 -or
                        (Convert-ToUInt64OrZero $kv.failures) -ne 0 -or
                        (Convert-ToUInt64OrZero $kv.forbidden_cold_ssd_to_vram) -ne 0) {
                        [void](Stop-OwnedProcessWithSnapshot -OwnedProcess $OwnedProcess `
                            -SnapshotPath $AbortSnapshotPath -Reason "unsafe-tier-$Name" `
                            -StderrPath $LogPath -SamplerPath $SamplerPath)
                        throw "Unsafe tier/backing event during $Name; line=$line"
                    }
                }
                if ($line -match 'ds4-server: chat .* gen=([0-9]+) decoding chunk=([0-9.]+) t/s avg=([0-9.]+) t/s ([0-9.]+)s') {
                    $decodeStarted = $true
                    $gen = [int]$matches[1]
                    $seconds = [double]$matches[4]
                    if ($gen -gt $lastDecodeToken) {
                        $lastDecodeToken = $gen
                        $lastDecodeProgressUtc = [DateTime]::UtcNow
                        [void]$tokenTimes.Add([pscustomobject]@{ gen = $gen; seconds = $seconds })
                    }
                    $warm = [int]$decodeFloorManifest.warm_tokens
                    $consecutive = [int]$decodeFloorManifest.consecutive_tokens
                    if ($gen -ge ($warm + $consecutive)) {
                        $startGen = $gen - $consecutive
                        $startSample = @($tokenTimes | Where-Object { [int]$_.gen -le $startGen } | Select-Object -Last 1)
                        $endSample = @($tokenTimes | Where-Object { [int]$_.gen -eq $gen } | Select-Object -Last 1)
                        if ($startSample.Count -eq 1 -and $endSample.Count -eq 1) {
                            $delta = [double]$endSample[0].seconds - [double]$startSample[0].seconds
                            if ($delta -le 0) {
                                [void](Stop-OwnedProcessWithSnapshot -OwnedProcess $OwnedProcess `
                                    -SnapshotPath $AbortSnapshotPath -Reason "decode-clock-not-advancing-$Name" `
                                    -StderrPath $LogPath -SamplerPath $SamplerPath)
                                throw "Decode clock did not advance during $Name"
                            }
                            $rolling = [double]$consecutive / $delta
                            if ($rolling -lt [double]$decodeFloorManifest.abort_floor_tps) {
                                [void](Stop-OwnedProcessWithSnapshot -OwnedProcess $OwnedProcess `
                                    -SnapshotPath $AbortSnapshotPath -Reason "decode-floor-$Name" `
                                    -StderrPath $LogPath -SamplerPath $SamplerPath)
                                throw ("Rolling decode throughput below floor during ${Name}: " +
                                    "rolling_tps=$rolling floor=$($decodeFloorManifest.abort_floor_tps)")
                            }
                        }
                    }
                } elseif ($line -match 'ds4-server: chat .* gen=([0-9]+) finish=') {
                    $lastDecodeToken = [int]$matches[1]
                    $lastDecodeProgressUtc = [DateTime]::UtcNow
                }
            }
            if ($decodeStarted -and
                ([DateTime]::UtcNow - $lastDecodeProgressUtc).TotalSeconds -gt [double]$decodeNoProgressStallSec) {
                [void](Stop-OwnedProcessWithSnapshot -OwnedProcess $OwnedProcess `
                    -SnapshotPath $AbortSnapshotPath -Reason "decode-no-progress-$Name" `
                    -StderrPath $LogPath -SamplerPath $SamplerPath)
                throw "Decode made no token progress for $decodeNoProgressStallSec seconds during $Name"
            }
            if ($SamplerPath) {
                $samplerRows = Get-GpuSamplerRowCount -CsvPath $SamplerPath
                if ($samplerRows -gt $lastSamplerRows) {
                    $lastSamplerRows = $samplerRows
                    $lastSamplerAdvanceUtc = [DateTime]::UtcNow
                } elseif (([DateTime]::UtcNow - $lastSamplerAdvanceUtc).TotalSeconds -gt [double]$samplerStallSec) {
                    [void](Stop-OwnedProcessWithSnapshot -OwnedProcess $OwnedProcess `
                        -SnapshotPath $AbortSnapshotPath -Reason "sampler-stalled-$Name" `
                        -StderrPath $LogPath -SamplerPath $SamplerPath)
                    throw "GPU/paging sampler row count stopped advancing during $Name"
                }
                $pressure = Test-SamplerPressureAbort -SamplerPath $SamplerPath
                if ($pressure) {
                    [void](Stop-OwnedProcessWithSnapshot -OwnedProcess $OwnedProcess `
                        -SnapshotPath $AbortSnapshotPath -Reason "sampler-pressure-$Name" `
                        -StderrPath $LogPath -SamplerPath $SamplerPath)
                    throw "Sampler pressure abort during ${Name}: $pressure"
                }
            }
            if ((Get-Date) -ge $deadline) {
                [void](Stop-OwnedProcessWithSnapshot -OwnedProcess $OwnedProcess `
                    -SnapshotPath $AbortSnapshotPath -Reason "http-timeout-$Name" `
                    -StderrPath $LogPath -SamplerPath $SamplerPath)
                throw "HTTP request timeout during $Name"
            }
        }
        if ($task.IsFaulted) { throw $task.Exception.GetBaseException().Message }
        $message = $task.Result
        $responseJson = $message.Content.ReadAsStringAsync().Result
        [IO.File]::WriteAllText($responsePath, $responseJson, [Text.UTF8Encoding]::new($false))
        if (-not $message.IsSuccessStatusCode) {
            throw "HTTP status $([int]$message.StatusCode) during ${Name}: $responseJson"
        }
        $response = $responseJson | ConvertFrom-Json
    } finally {
        Add-RunnerEvent -Events $RunnerEvents -Name 'request_end' -Request $Name
        if ($message) { $message.Dispose() }
        if ($content) { $content.Dispose() }
        $client.Dispose()
    }
    $contentText = [string]$response.choices[0].message.content
    $finishReason = [string]$response.choices[0].finish_reason
    [IO.File]::WriteAllText($rawPath, $contentText, [Text.UTF8Encoding]::new($false))
    $normalized = Normalize-HtmlDocument -Content $contentText -FinishReason $finishReason
    [IO.File]::WriteAllText($docPath, $normalized.document, [Text.UTF8Encoding]::new($false))
    return [pscustomobject]@{
        name = $Name
        turn = $Turn
        request_epoch = $requestEpoch
        http_status = 200
        wall_seconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 6)
        request_path = $requestPath
        request_sha256 = Get-Sha256Text $json
        request_bytes_utf8 = [Text.Encoding]::UTF8.GetByteCount($json)
        messages_sha256 = $messagesSha
        messages_bytes_utf8 = [Text.Encoding]::UTF8.GetByteCount($messagesJson)
        conversation_sha256 = $conversationSha
        turn1_document_sha256_used = $Turn1DocumentSha256Used
        response_path = $responsePath
        response_sha256 = Get-Sha256File $responsePath
        raw_assistant_path = $rawPath
        raw_assistant_sha256 = $normalized.raw_sha256
        raw_assistant_text = $contentText
        raw_assistant_bytes_utf8 = [Text.Encoding]::UTF8.GetByteCount($contentText)
        document_path = $docPath
        document_sha256 = $normalized.document_sha256
        document_length = $normalized.document_length
        stop_sequence_observed = [bool]$normalized.stop_sequence_observed
        stop_reinjected = [bool]$normalized.stop_reinjected
        stop_contract_valid = [bool]$normalized.stop_contract_valid
        raw_only_html_contract = [bool]$normalized.raw_only_html_contract
        raw_has_markdown_fence = [bool]$normalized.raw_has_markdown_fence
        raw_prefix_non_whitespace = [bool]$normalized.raw_prefix_non_whitespace
        raw_suffix_non_whitespace = [bool]$normalized.raw_suffix_non_whitespace
        prompt_tokens = [int]$response.usage.prompt_tokens
        completion_tokens = [int]$response.usage.completion_tokens
        finish_reason = $finishReason
    }
}

function Get-ServerRequestMetrics {
    param([string[]]$Lines)
    $requests = @()
    $current = $null
    $requestEpoch = 0
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]
        if ($line -match '\[g73-two-turn-epoch\]\s+request_epoch=([0-9]+)') {
            $requestEpoch = [int]$matches[1]
        }
        if ($line -match 'ds4-server: chat .* prompt start') {
            if ($current) { $requests += [pscustomobject]$current }
            $current = [ordered]@{
                name = 'request' + ($requests.Count + 1)
                request_epoch = $requestEpoch
                prompt_start_line = $i + 1
                prefill_chunks = @()
                prompt_done_line = $null
                prompt_done_seconds = $null
                first_decode_line = $null
                first_decode_elapsed_seconds = $null
                last_decode_line = $null
                last_decode_elapsed_seconds = $null
                last_decode_tokens = $null
                last_decode_avg_tps = $null
                finish_line = $null
                finish_tokens = $null
                finish_reason_log = $null
                finish_elapsed_seconds = $null
            }
            continue
        }
        if (-not $current) { continue }
        if ($line -match 'prefill chunk ([0-9]+)/([0-9]+).* chunk=([0-9.]+) t/s avg=([0-9.]+) t/s ([0-9.]+)s') {
            $current.prefill_chunks += [pscustomobject]@{
                line = $i + 1
                current = [int]$matches[1]
                total = [int]$matches[2]
                chunk_tps = [double]$matches[3]
                avg_tps = [double]$matches[4]
                elapsed_seconds = [double]$matches[5]
            }
        } elseif ($line -match 'ds4-server: chat .* prompt done ([0-9.]+)s') {
            $current.prompt_done_line = $i + 1
            $current.prompt_done_seconds = [double]$matches[1]
        } elseif ($line -match 'ds4-server: chat .* gen=([0-9]+) decoding chunk=([0-9.]+) t/s avg=([0-9.]+) t/s ([0-9.]+)s') {
            if ($null -eq $current.first_decode_line) {
                $current.first_decode_line = $i + 1
                $current.first_decode_elapsed_seconds = [double]$matches[4]
            }
            $current.last_decode_line = $i + 1
            $current.last_decode_tokens = [int]$matches[1]
            $current.last_decode_avg_tps = [double]$matches[3]
            $current.last_decode_elapsed_seconds = [double]$matches[4]
        } elseif ($line -match 'ds4-server: chat .* gen=([0-9]+) finish=([^ ]+) ([0-9.]+)s') {
            $current.finish_line = $i + 1
            $current.finish_tokens = [int]$matches[1]
            $current.finish_reason_log = $matches[2]
            $current.finish_elapsed_seconds = [double]$matches[3]
        }
    }
    if ($current) { $requests += [pscustomobject]$current }
    return @($requests)
}

function Join-RequestMetrics {
    param([object[]]$HttpResults, [object[]]$LogMetrics)
    $joined = @()
    for ($i = 0; $i -lt $HttpResults.Count; $i++) {
        $http = $HttpResults[$i]
        $logMatches = @()
        if ($null -ne $http.request_epoch) {
            $logMatches = @($LogMetrics | Where-Object {
                $null -ne $_.request_epoch -and [int]$_.request_epoch -eq [int]$http.request_epoch
            })
        }
        $log = if ($logMatches.Count -eq 1) { $logMatches[0] } else { $null }
        $prefillSeconds = if ($log) { Convert-ToDoubleOrNull $log.prompt_done_seconds } else { $null }
        $decodeSeconds = $null
        if ($log -and $null -ne $log.finish_elapsed_seconds -and $null -ne $log.prompt_done_seconds) {
            $decodeSeconds = [math]::Round(([double]$log.finish_elapsed_seconds - [double]$log.prompt_done_seconds), 6)
        }
        $prefillTps = $null
        if ($prefillSeconds -and $prefillSeconds -gt 0) {
            $prefillTps = [math]::Round([double]$http.prompt_tokens / $prefillSeconds, 6)
        }
        $decodeTps = $null
        if ($decodeSeconds -and $decodeSeconds -gt 0) {
            $decodeTps = [math]::Round([double]$http.completion_tokens / $decodeSeconds, 6)
        }
        $joined += [pscustomobject]@{
            name = $http.name
            turn = $http.turn
            request_epoch = $http.request_epoch
            http_status = $http.http_status
            wall_seconds = $http.wall_seconds
            prompt_tokens = $http.prompt_tokens
            completion_tokens = $http.completion_tokens
            finish_reason = $http.finish_reason
            finish_reason_log = if ($log) { $log.finish_reason_log } else { $null }
            stop_sequence_observed = $http.stop_sequence_observed
            stop_reinjected = $http.stop_reinjected
            stop_contract_valid = $http.stop_contract_valid
            raw_only_html_contract = $http.raw_only_html_contract
            raw_has_markdown_fence = $http.raw_has_markdown_fence
            raw_prefix_non_whitespace = $http.raw_prefix_non_whitespace
            raw_suffix_non_whitespace = $http.raw_suffix_non_whitespace
            ttft_server_seconds = if ($log) { $log.first_decode_elapsed_seconds } else { $null }
            prefill_seconds = $prefillSeconds
            prefill_tps = $prefillTps
            decode_seconds = $decodeSeconds
            decode_tps_server = $decodeTps
            decode_tps_log_avg = if ($log) { $log.last_decode_avg_tps } else { $null }
            request_sha256 = $http.request_sha256
            request_bytes_utf8 = $http.request_bytes_utf8
            messages_sha256 = $http.messages_sha256
            messages_bytes_utf8 = $http.messages_bytes_utf8
            conversation_sha256 = $http.conversation_sha256
            turn1_document_sha256_used = $http.turn1_document_sha256_used
            response_sha256 = $http.response_sha256
            raw_assistant_sha256 = $http.raw_assistant_sha256
            raw_assistant_bytes_utf8 = $http.raw_assistant_bytes_utf8
            document_sha256 = $http.document_sha256
            document_length = $http.document_length
            request_path = $http.request_path
            response_path = $http.response_path
            raw_assistant_path = $http.raw_assistant_path
            document_path = $http.document_path
            server_log = $log
            server_log_join = [pscustomobject]@{
                key = 'request_epoch'
                matched = [bool]($null -ne $log)
                matches = $logMatches.Count
                request_epoch = $http.request_epoch
            }
        }
    }
    return @($joined)
}

function Get-LongLogSummary {
    param([string]$LogPath)
    if (-not (Test-Path -LiteralPath $LogPath -PathType Leaf)) {
        return [pscustomobject]@{
            server_request_metrics = @()
            model_tensor_cache_events = @()
            runtime_model_tensor_progress = @()
            sync = @()
            prefill = @()
            workspace = @()
            compose = @()
            arena = @()
            arena_wrap_profile = @()
            prefill_mass_wrap = @()
            effective = @()
            seed = @()
            cache = @()
            cache_ensure = @()
            tier = @()
            unsafe_tier = @()
            gpu_resident_routes = @()
            mask_sets = $null
            seed_sets = $null
            order = $null
        }
    }
    $lines = @(Get-Content -LiteralPath $LogPath)
    $modelEvents = @(Get-ModelTensorCacheEvents $lines)
    $mask1 = Get-LayerSetSummary -Lines $lines -Marker 'g73-two-turn-mask-layer' -Epoch 1 -Phase 'candidate'
    $mask2 = Get-LayerSetSummary -Lines $lines -Marker 'g73-two-turn-mask-layer' -Epoch 2 -Phase 'candidate'
    $seed1 = Get-LayerSetSummary -Lines $lines -Marker 'g73-two-turn-vram-layer' -Epoch 1 -Phase 'seed-ready'
    $seed2 = Get-LayerSetSummary -Lines $lines -Marker 'g73-two-turn-vram-layer' -Epoch 2 -Phase 'seed-ready'
    $prefill = @(Get-TraceEvents $lines 'g73-two-turn-prefill')
    $workspace = @(Get-TraceEvents $lines 'g73-two-turn-workspace')
    $seedEvents = @(Get-TraceEvents $lines 'g73-two-turn-seed')
    $cacheEnsure = @(Get-TraceEvents $lines 'g73-two-turn-cache-ensure')
    $routes = @(Get-TraceEvents $lines 'gpu-resident-routes')
    $order = Test-ExplicitRequestOrder -Prefill $prefill -Workspace $workspace -Seed $seedEvents -CacheEnsure $cacheEnsure -Routes $routes -Epoch 2 -Arm $Arm
    return [pscustomobject]@{
        server_request_metrics = @(Get-ServerRequestMetrics $lines)
        model_tensor_cache_events = $modelEvents
        runtime_model_tensor_progress = @($modelEvents | Where-Object {
            $_.kind -eq 'progress' -and [int]$_.request_index -gt 0
        })
        sync = @(Get-TraceEvents $lines 'g73-two-turn-sync')
        prefill = $prefill
        workspace = $workspace
        compose = @(Get-PrefillMassComposeEvents $lines)
        arena = @(Get-TraceEvents $lines 'arena')
        arena_wrap_profile = @(Get-TraceEvents $lines 'arena-wrap-profile')
        prefill_mass_wrap = @(Get-TraceEvents $lines 'prefill-mass-wrap')
        effective = @(Get-TraceEvents $lines 'g73-two-turn-effective')
        seed = $seedEvents
        cache = @(Get-TraceEvents $lines 'g73-two-turn-cache')
        cache_ensure = $cacheEnsure
        tier = @(Get-TraceEvents $lines 'g73-two-turn-tier')
        unsafe_tier = @(Get-UnsafeTierEvents $LogPath)
        gpu_resident_routes = $routes
        mask_sets = [pscustomobject]@{
            request1_candidate = $mask1
            request2_candidate = $mask2
            overlap = Compare-LayerSets $mask1 $mask2
        }
        seed_sets = [pscustomobject]@{
            request1_seed_ready = $seed1
            request2_seed_ready = $seed2
            overlap = Compare-LayerSets $seed1 $seed2
        }
        order = $order
    }
}

function Test-ExplicitRequestOrder {
    param(
        [object[]]$Prefill,
        [object[]]$Workspace,
        [object[]]$Seed,
        [object[]]$CacheEnsure,
        [object[]]$Routes,
        [int]$Epoch,
        [string]$Arm
    )
    $begin = Get-FirstEventLine $Prefill {
        [string]$_.request_epoch -eq [string]$Epoch -and [string]$_.phase -eq 'begin'
    }
    $end = Get-FirstEventLine $Prefill {
        [string]$_.request_epoch -eq [string]$Epoch -and [string]$_.phase -eq 'end'
    }
    $workspaceLine = Get-FirstEventLine $Workspace {
        [string]$_.request_epoch -eq [string]$Epoch -and [string]$_.phase -eq 'post-prefill-release'
    }
    $deferredLine = Get-FirstEventLine $Seed {
        [string]$_.request_epoch -eq [string]$Epoch -and
        ([string]$_.phase -eq 'dynamic-seed-deferred' -or [string]$_.phase -eq 'stale-reseed-deferred')
    }
    $decodeEnsureLine = Get-FirstEventLine $CacheEnsure {
        [string]$_.request_epoch -eq [string]$Epoch -and
        [string]$_.phase -eq 'prefill-vram-seed-ensure' -and
        ([string]$_.event -eq 'before-alloc' -or [string]$_.event -eq 'after-alloc' -or [string]$_.event -eq 'after-seed')
    }
    $seedReadyLine = Get-FirstEventLine $CacheEnsure {
        [string]$_.request_epoch -eq [string]$Epoch -and
        [string]$_.phase -eq 'prefill-vram-seed-ensure' -and [string]$_.event -eq 'after-seed'
    }
    $routeLine = Get-FirstEventLine $Routes { $true }
    $decodeEnsureBetweenBeginEnd = $false
    if ($null -ne $begin -and $null -ne $end) {
        $decodeEnsureBetweenBeginEnd = @($CacheEnsure | Where-Object {
            [string]$_.request_epoch -eq [string]$Epoch -and
            [string]$_.phase -eq 'prefill-vram-seed-ensure' -and
            [int]$_._line_number -gt $begin -and [int]$_._line_number -lt $end
        }).Count -ne 0
    }
    $skipDuringPrefill = $true
    if ($null -ne $begin -and $null -ne $end) {
        $during = @($CacheEnsure | Where-Object {
            [string]$_.request_epoch -eq [string]$Epoch -and
            [int]$_._line_number -gt $begin -and [int]$_._line_number -lt $end
        })
        if ($during.Count -gt 0) {
            $skipDuringPrefill = @($during | Where-Object {
                [string]$_.event -ne 'skip-explicit-prefill'
            }).Count -eq 0
        }
    }
    $ordered = ($null -ne $begin -and $null -ne $end -and $null -ne $workspaceLine -and
        $null -ne $deferredLine -and $null -ne $decodeEnsureLine -and $null -ne $seedReadyLine -and
        $begin -lt $end -and $end -lt $workspaceLine -and $workspaceLine -lt $deferredLine -and
        $deferredLine -lt $decodeEnsureLine -and $decodeEnsureLine -le $seedReadyLine)
    if ($null -ne $routeLine) { $ordered = $ordered -and ($seedReadyLine -lt $routeLine) }
    return [pscustomobject]@{
        request_epoch = $Epoch
        arm = $Arm
        pass = [bool]($ordered -and (-not $decodeEnsureBetweenBeginEnd) -and $skipDuringPrefill)
        prefill_begin_line = $begin
        prefill_end_line = $end
        workspace_release_line = $workspaceLine
        seed_deferred_line = $deferredLine
        cache_ensure_decode_line = $decodeEnsureLine
        seed_ready_line = $seedReadyLine
        first_route_line = $routeLine
        decode_ensure_between_begin_end = [bool]$decodeEnsureBetweenBeginEnd
        prepare_during_prefill_only_skip_explicit_prefill = [bool]$skipDuringPrefill
    }
}

function Add-Gate {
    param([System.Collections.ArrayList]$Gates, [string]$Name, [bool]$Pass, [string]$Detail = '')
    [void]$Gates.Add([pscustomobject]@{
        name = $Name
        pass = [bool]$Pass
        detail = $Detail
    })
}

function Get-ArraySafeCount {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return 0 }
    return @($Value).Count
}

function New-ExpectedRequestCountGate {
    param([AllowNull()][object]$Requests, [int]$Expected)
    $observed = Get-ArraySafeCount $Requests
    return [pscustomobject]@{
        pass = ($observed -eq $Expected)
        observed = $observed
        expected = $Expected
        detail = "observed=$observed expected=$Expected"
    }
}

function Get-LastEffective {
    param([object[]]$Events, [int]$Epoch)
    $items = @($Events | Where-Object { [string]$_.request_epoch -eq [string]$Epoch })
    if ($items.Count -eq 0) { return $null }
    return $items[-1]
}

function Get-StatusFromGates {
    param([object[]]$Gates, [string]$Failure = '')
    if ($Failure -match 'Model tensor cache reload|Unsafe tier/backing|HTTP request timeout|Rolling decode throughput below floor|Decode made no token progress|sampler row count stopped advancing|Sampler pressure abort|Decode clock did not advance') {
        return 'aborted'
    }
    if (@($Gates | Where-Object { -not $_.pass }).Count -ne 0) { return 'failed' }
    if ($Failure) { return 'failed' }
    return 'pass'
}

function Add-ArmGates {
    param([System.Collections.ArrayList]$Gates, [object]$LogSummary, [string]$SelectedArm)
    $eff1 = Get-LastEffective -Events $LogSummary.effective -Epoch 1
    $eff2 = Get-LastEffective -Events $LogSummary.effective -Epoch 2
    $mask1 = $LogSummary.mask_sets.request1_candidate
    $mask2 = $LogSummary.mask_sets.request2_candidate
    $seed1 = $LogSummary.seed_sets.request1_seed_ready
    $seed2 = $LogSummary.seed_sets.request2_seed_ready
    Add-Gate $Gates 'effective1_4551' ($eff1 -and [int]$eff1.entries -eq 4551) "entries=$(if($eff1){$eff1.entries}else{'null'})"
    Add-Gate $Gates 'effective2_4551' ($eff2 -and [int]$eff2.entries -eq 4551) "entries=$(if($eff2){$eff2.entries}else{'null'})"
    Add-Gate $Gates 'seed1_320' ($seed1 -and [int]$seed1.entries -eq 320) "entries=$(if($seed1){$seed1.entries}else{'null'})"
    Add-Gate $Gates 'seed2_320' ($seed2 -and [int]$seed2.entries -eq 320) "entries=$(if($seed2){$seed2.entries}else{'null'})"
    if ($SelectedArm -eq 'A') {
        $candidate2Compose = @($LogSummary.compose | Where-Object { [string]$_.request_epoch -eq '2' })
        $turnover2 = @($LogSummary.arena | Where-Object {
            [string]$_.mode -eq 'turnover-in-place' -and [int]$_._line_number -gt 0
        })
        $staleSeed2 = @($LogSummary.seed | Where-Object {
            [string]$_.request_epoch -eq '2' -and [string]$_.phase -eq 'stale-reseed-deferred'
        })
        Add-Gate $Gates 'arm_a_no_candidate2' (($candidate2Compose.Count -eq 0) -and [int]$mask2.entries -eq 0) "compose=$($candidate2Compose.Count) mask_entries=$($mask2.entries)"
        Add-Gate $Gates 'arm_a_effective2_equals_effective1' ($eff1 -and $eff2 -and [string]$eff1.fnv1a64 -eq [string]$eff2.fnv1a64) "eff1=$(if($eff1){$eff1.fnv1a64}else{'null'}) eff2=$(if($eff2){$eff2.fnv1a64}else{'null'})"
        Add-Gate $Gates 'arm_a_seed2_equals_seed1' ($seed1 -and $seed2 -and [string]$seed1.sha256 -eq [string]$seed2.sha256) "seed1=$(if($seed1){$seed1.sha256}else{'null'}) seed2=$(if($seed2){$seed2.sha256}else{'null'})"
        Add-Gate $Gates 'arm_a_seed2_provenance_request1' ($staleSeed2.Count -gt 0) "stale_reseed_deferred=$($staleSeed2.Count)"
        Add-Gate $Gates 'arm_a_no_request2_turnover_in_place' ($turnover2.Count -eq 0) "turnover_events=$($turnover2.Count)"
    } else {
        $compose1 = @($LogSummary.compose | Where-Object { [string]$_.request_epoch -eq '1' } | Select-Object -Last 1)
        $compose2 = @($LogSummary.compose | Where-Object { [string]$_.request_epoch -eq '2' } | Select-Object -Last 1)
        $turnover2 = @($LogSummary.arena | Where-Object { [string]$_.mode -eq 'turnover-in-place' } | Select-Object -Last 1)
        $dynamicSeed2 = @($LogSummary.seed | Where-Object {
            [string]$_.request_epoch -eq '2' -and [string]$_.phase -eq 'dynamic-seed-deferred'
        })
        Add-Gate $Gates 'arm_b_candidate1_4551' ($compose1.Count -gt 0 -and [int]$compose1[0].total_candidate -eq 4551) "total=$(if($compose1.Count){$compose1[0].total_candidate}else{'null'})"
        Add-Gate $Gates 'arm_b_candidate2_4551' ($compose2.Count -gt 0 -and [int]$compose2[0].total_candidate -eq 4551) "total=$(if($compose2.Count){$compose2[0].total_candidate}else{'null'})"
        Add-Gate $Gates 'arm_b_candidate2_differs_candidate1' ($compose1.Count -gt 0 -and $compose2.Count -gt 0 -and [string]$compose1[0].candidate_fnv1a64 -ne [string]$compose2[0].candidate_fnv1a64) "c1=$(if($compose1.Count){$compose1[0].candidate_fnv1a64}else{'null'}) c2=$(if($compose2.Count){$compose2[0].candidate_fnv1a64}else{'null'})"
        Add-Gate $Gates 'arm_b_effective2_candidate' ($eff2 -and [string]$eff2.mode -eq 'candidate') "mode=$(if($eff2){$eff2.mode}else{'null'})"
        Add-Gate $Gates 'arm_b_effective2_equals_candidate2' ($eff2 -and $compose2.Count -gt 0 -and [string]$eff2.fnv1a64 -eq [string]$compose2[0].candidate_fnv1a64) "eff2=$(if($eff2){$eff2.fnv1a64}else{'null'}) c2=$(if($compose2.Count){$compose2[0].candidate_fnv1a64}else{'null'})"
        Add-Gate $Gates 'arm_b_turnover_in_place_publish' ($turnover2.Count -gt 0 -and [string]$turnover2[0].mode -eq 'turnover-in-place' -and [string]$turnover2[0]._line -match '\[arena\] publish') "events=$($turnover2.Count)"
        Add-Gate $Gates 'arm_b_seed2_provenance_request2_dynamic' ($dynamicSeed2.Count -gt 0) "dynamic_seed_deferred=$($dynamicSeed2.Count)"
    }
}

function Add-CommonGates {
    param(
        [System.Collections.ArrayList]$Gates,
        [AllowNull()][object]$Preflight,
        [AllowNull()][object]$ServerExit,
        [object[]]$Requests,
        [object[]]$Quality,
        [object]$LogSummary,
        [string]$Failure)
    Add-Gate $Gates 'canonical_runner_sha' ((Get-Sha256File $canonicalRunner) -eq $expectedCanonicalRunnerSha) (Get-Sha256File $canonicalRunner)
    Add-Gate $Gates 'exe_sha' ((Get-Sha256File $exe) -eq $expectedExeSha) (Get-Sha256File $exe)
    $preflightCount = if ($Preflight) { @($Preflight.conflicting_processes).Count } else { -1 }
    Add-Gate $Gates 'preflight_conflicts_zero' ($preflightCount -eq 0) "conflicts=$preflightCount"
    Add-Gate $Gates 'server_exit_code_int32_zero' ($ServerExit -and $ServerExit.reason -eq 'ok' -and $null -ne $ServerExit.exit_code -and [int]$ServerExit.exit_code -eq 0) "exit=$(if($ServerExit){$ServerExit.exit_code}else{'null'}) reason=$(if($ServerExit){$ServerExit.reason}else{'null'})"
    $requestCountGate = New-ExpectedRequestCountGate -Requests $Requests -Expected 2
    Add-Gate $Gates 'expected_request_count' $requestCountGate.pass $requestCountGate.detail
    $requestGateNames = @{
        request1 = @{
            http = 'request1_http200'
            finish = 'request1_finish_reason_stop'
            stop = 'request1_stop_contract_valid'
            raw = 'request1_raw_only_html_contract'
            document = 'request1_document_nonempty'
        }
        request2 = @{
            http = 'request2_http200'
            finish = 'request2_finish_reason_stop'
            stop = 'request2_stop_contract_valid'
            raw = 'request2_raw_only_html_contract'
            document = 'request2_document_nonempty'
        }
    }
    foreach ($requestName in @('request1', 'request2')) {
        $names = $requestGateNames[$requestName]
        $req = @($Requests | Where-Object { $_.name -eq $requestName } | Select-Object -First 1)
        Add-Gate $Gates $names.http ($req.Count -gt 0 -and [int]$req[0].http_status -eq 200) "status=$(if($req.Count){$req[0].http_status}else{'missing'})"
        Add-Gate $Gates $names.finish ($req.Count -gt 0 -and [string]$req[0].finish_reason -eq 'stop') "finish_reason=$(if($req.Count){$req[0].finish_reason}else{'missing'})"
        Add-Gate $Gates $names.stop ($req.Count -gt 0 -and [bool]$req[0].stop_contract_valid) "observed=$(if($req.Count){$req[0].stop_sequence_observed}else{'missing'}) reinjected=$(if($req.Count){$req[0].stop_reinjected}else{'missing'})"
        Add-Gate $Gates $names.raw ($req.Count -gt 0 -and [bool]$req[0].raw_only_html_contract) "fence=$(if($req.Count){$req[0].raw_has_markdown_fence}else{'missing'}) prefix=$(if($req.Count){$req[0].raw_prefix_non_whitespace}else{'missing'}) suffix=$(if($req.Count){$req[0].raw_suffix_non_whitespace}else{'missing'})"
        Add-Gate $Gates $names.document ($req.Count -gt 0 -and [int]$req[0].document_length -gt 0) "bytes=$(if($req.Count){$req[0].document_length}else{'missing'})"
        Add-Gate $Gates "${requestName}_epoch_log_join" ($req.Count -gt 0 -and
            $req[0].server_log_join -and [bool]$req[0].server_log_join.matched) `
            "epoch=$(if($req.Count){$req[0].request_epoch}else{'missing'}) matches=$(if($req.Count -and $req[0].server_log_join){$req[0].server_log_join.matches}else{'missing'})"
        Add-Gate $Gates "${requestName}_server_tps_non_null" ($req.Count -gt 0 -and
            $null -ne $req[0].prefill_tps -and $null -ne $req[0].decode_tps_server) `
            "prefill_tps=$(if($req.Count){$req[0].prefill_tps}else{'missing'}) decode_tps_server=$(if($req.Count){$req[0].decode_tps_server}else{'missing'})"
    }
    foreach ($qual in @($Quality)) {
        Add-Gate $Gates "$($qual.turn)_quality_structural" ([bool]$qual.pass) "parseable=$($qual.parseable_html) css=$($qual.has_css) nav=$($qual.has_nav) hero=$($qual.has_hero) form=$($qual.has_form) script=$($qual.has_script) popup=$($qual.has_popup) dark=$($qual.dark_almost_black) cyan=$($qual.cyan_accent) magenta=$($qual.magenta_accent)"
    }
    $sync1 = @($LogSummary.sync | Where-Object { [string]$_.request -eq '1' -and [string]$_.mode -eq 'full-conversation-reprefill' } | Select-Object -Last 1)
    $sync2 = @($LogSummary.sync | Where-Object { [string]$_.request -eq '2' -and [string]$_.mode -eq 'full-conversation-reprefill' } | Select-Object -Last 1)
    Add-Gate $Gates 'request1_full_conversation_reprefill_kv0' ($sync1.Count -gt 0 -and [string]$sync1[0].kv_reuse -eq '0') "events=$($sync1.Count)"
    Add-Gate $Gates 'request2_full_conversation_reprefill_kv0' ($sync2.Count -gt 0 -and [string]$sync2[0].kv_reuse -eq '0') "events=$($sync2.Count)"
    $req1ForTranscript = @($Requests | Where-Object { $_.name -eq 'request1' } | Select-Object -First 1)
    $req2ForTranscript = @($Requests | Where-Object { $_.name -eq 'request2' } | Select-Object -First 1)
    Add-Gate $Gates 'request2_uses_turn1_raw_assistant_sha' (
        $req1ForTranscript.Count -gt 0 -and $req2ForTranscript.Count -gt 0 -and
        [string]$req2ForTranscript[0].turn1_document_sha256_used -eq [string]$req1ForTranscript[0].raw_assistant_sha256
    ) "turn1_raw=$(if($req1ForTranscript.Count){$req1ForTranscript[0].raw_assistant_sha256}else{'missing'}) used=$(if($req2ForTranscript.Count){$req2ForTranscript[0].turn1_document_sha256_used}else{'missing'})"
    Add-Gate $Gates 'runtime_model_tensor_progress_zero' (@($LogSummary.runtime_model_tensor_progress).Count -eq 0) "events=$(@($LogSummary.runtime_model_tensor_progress).Count)"
    Add-Gate $Gates 'unsafe_tier_zero' (@($LogSummary.unsafe_tier).Count -eq 0) "events=$(@($LogSummary.unsafe_tier).Count)"
    Add-Gate $Gates 'request2_explicit_prefill_order' ($LogSummary.order -and [bool]$LogSummary.order.pass) "order=$(if($LogSummary.order){$LogSummary.order | ConvertTo-Json -Compress}else{'null'})"
    Add-Gate $Gates 'no_runner_failure' ([string]::IsNullOrEmpty($Failure)) $Failure
}

function Add-MockGates {
    param(
        [System.Collections.ArrayList]$Gates,
        [string]$Scenario,
        [AllowNull()][object]$Preflight,
        [AllowNull()][object]$ServerExit,
        [object[]]$Requests,
        [object[]]$Quality,
        [AllowNull()][object]$Turn1Readiness,
        [AllowNull()][object]$Validation,
        [string]$Failure)
    $expectedRequests = switch ($Scenario) {
        'success' { 2 }
        'malformed-turn1' { 1 }
        default { 0 }
    }
    $requestCountGate = New-ExpectedRequestCountGate -Requests $Requests -Expected $expectedRequests
    $preflightCount = if ($Preflight) { @($Preflight.conflicting_processes).Count } else { -1 }
    Add-Gate $Gates 'mock_cpu_only_mode' $MockIntegration "scenario=$Scenario"
    Add-Gate $Gates 'mock_preflight_conflicts_zero' ($preflightCount -eq 0) "conflicts=$preflightCount"
    Add-Gate $Gates 'mock_expected_request_count' $requestCountGate.pass $requestCountGate.detail
    Add-Gate $Gates 'mock_capture_contract' ($Validation -and [bool]$Validation.pass) `
        "pass=$(if($Validation){$Validation.pass}else{'missing'})"
    if ($Scenario -eq 'success') {
        Add-Gate $Gates 'mock_server_exit_zero' ($ServerExit -and $ServerExit.reason -eq 'ok' -and
            $null -ne $ServerExit.exit_code -and [int]$ServerExit.exit_code -eq 0) `
            "exit=$(if($ServerExit){$ServerExit.exit_code}else{'null'})"
        Add-Gate $Gates 'mock_turn1_ready_for_turn2' ($Turn1Readiness -and [bool]$Turn1Readiness.pass) `
            "ready=$(if($Turn1Readiness){$Turn1Readiness.pass}else{'missing'})"
        $q1 = @($Quality | Where-Object { $_.turn -eq 'turn1' } | Select-Object -First 1)
        $q2 = @($Quality | Where-Object { $_.turn -eq 'turn2' } | Select-Object -First 1)
        Add-Gate $Gates 'mock_turn1_synthetic_l2_contract' ($q1.Count -eq 1 -and [bool]$q1[0].pass) `
            "pass=$(if($q1.Count){$q1[0].pass}else{'missing'})"
        Add-Gate $Gates 'mock_turn2_dark_structural_contract' ($q2.Count -eq 1 -and [bool]$q2[0].pass) `
            "pass=$(if($q2.Count){$q2[0].pass}else{'missing'})"
        foreach ($requestName in @('request1', 'request2')) {
            $request = @($Requests | Where-Object { $_.name -eq $requestName } | Select-Object -First 1)
            Add-Gate $Gates "mock_${requestName}_http_stop_raw" ($request.Count -eq 1 -and
                [int]$request[0].http_status -eq 200 -and [string]$request[0].finish_reason -eq 'stop' -and
                [bool]$request[0].stop_contract_valid -and [bool]$request[0].raw_only_html_contract) `
                "present=$($request.Count)"
        }
        Add-Gate $Gates 'mock_no_runner_failure' ([string]::IsNullOrEmpty($Failure)) $Failure
    } elseif ($Scenario -eq 'exit-before-readiness') {
        Add-Gate $Gates 'mock_pre_readiness_exit_23' ($ServerExit -and [int]$ServerExit.exit_code -eq 23) `
            "exit=$(if($ServerExit){$ServerExit.exit_code}else{'null'})"
        Add-Gate $Gates 'mock_expected_failure_observed' (-not [string]::IsNullOrEmpty($Failure)) $Failure
    } else {
        Add-Gate $Gates 'mock_malformed_turn1_blocked_turn2' ($Turn1Readiness -and
            -not [bool]$Turn1Readiness.pass -and $Requests.Count -eq 1) `
            "ready=$(if($Turn1Readiness){$Turn1Readiness.pass}else{'missing'}) requests=$($Requests.Count)"
        Add-Gate $Gates 'mock_expected_failure_observed' (-not [string]::IsNullOrEmpty($Failure)) $Failure
    }
}

function Invoke-LifecycleSelfTest {
    $tmp = Join-Path $env:TEMP ('g73_long_html_lifecycle_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp | Out-Null
    $ownedChildren = [System.Collections.ArrayList]::new()
    $powershellExe = Join-Path $PSHOME 'powershell.exe'
    $startChild = {
        param([string]$Name, [string]$ScriptText)
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($ScriptText))
        $owned = Start-LoggedOwnedProcess -FilePath $powershellExe `
            -Arguments @('-NoProfile', '-NonInteractive', '-EncodedCommand', $encoded) `
            -StdoutPath (Join-Path $tmp "$Name.out") -StderrPath (Join-Path $tmp "$Name.err")
        [void]$ownedChildren.Add($owned)
        return $owned
    }
    try {
        $multi = & $startChild 'multi' @'
Write-Output 'stdout-one'
Write-Output 'stdout-two'
[Console]::Error.WriteLine('stderr-one')
[Console]::Error.WriteLine('stderr-two')
exit 0
'@
        $multiExit = Complete-OwnedProcessExit -OwnedProcess $multi -TimeoutMs 10000
        $multiStdout = Get-Content -LiteralPath (Join-Path $tmp 'multi.out')
        $multiStderr = Get-Content -LiteralPath (Join-Path $tmp 'multi.err')
        $multiStderrText = $multiStderr -join "`n"
        if (-not $multiExit.exited -or $multiExit.reason -ne 'ok' -or
            [int]$multiExit.exit_code -ne 0 -or @($multiStdout).Count -ne 2 -or
            $multiStdout[0] -ne 'stdout-one' -or $multiStdout[1] -ne 'stdout-two' -or
            $multiStderrText -notmatch 'stderr-one' -or $multiStderrText -notmatch 'stderr-two') {
            throw "Direct child/output self-test failed: exit=$($multiExit.exit_code) stdout=$(@($multiStdout).Count) stderr=$(@($multiStderr).Count)"
        }

        $dies = & $startChild 'dies_before_ready' @'
Write-Output 'started-before-death'
[Console]::Error.WriteLine('fatal-before-ready')
exit 17
'@
        $diesReady = Wait-OwnedProcessReadiness -OwnedProcess $dies -TimeoutMs 5000 `
            -PollMs 25 -Probe { return $false }
        if ($diesReady.ready -or $diesReady.status -ne 'process-exited-before-readiness' -or
            -not $diesReady.exit.exited -or [int]$diesReady.exit.exit_code -ne 17) {
            throw "Vanished child self-test failed: $($diesReady | ConvertTo-Json -Compress -Depth 6)"
        }

        $timeoutChild = & $startChild 'timeout' @'
Write-Output 'timeout-child-started'
Start-Sleep -Seconds 5
exit 0
'@
        $timeoutReady = Wait-OwnedProcessReadiness -OwnedProcess $timeoutChild -TimeoutMs 200 `
            -PollMs 25 -Probe { return $false }
        if ($timeoutReady.ready -or $timeoutReady.status -ne 'readiness-timeout' -or
            -not (Test-OwnedProcessAlive $timeoutChild)) {
            throw "Readiness timeout self-test failed: $($timeoutReady | ConvertTo-Json -Compress -Depth 6)"
        }
        if (-not (Stop-OwnedProcess -OwnedProcess $timeoutChild -TimeoutMs 5000)) {
            throw 'Timed-out child cleanup self-test failed'
        }
        $timeoutExit = Complete-OwnedProcessExit -OwnedProcess $timeoutChild -TimeoutMs 0
        if (-not $timeoutExit.exited -or $null -eq $timeoutExit.exit_code) {
            throw "Timed-out child exit capture failed: $($timeoutExit | ConvertTo-Json -Compress)"
        }

        $cachedMetric = Get-StartupProgressMetric -Line 'CUDA loading model tensors 12.500 GiB cached'
        $layerMetric = Get-StartupProgressMetric -Line 'loaded model layer 42/61'
        $tensorMetric = Get-StartupProgressMetric -Line 'loaded 128/256 tensors'
        $bytesMetric = Get-StartupProgressMetric -Line 'cache copy advanced 4096 bytes'
        $markerMetric = Get-StartupProgressMetric -Line 'CUDA loading model tensors into device cache'
        if (-not $cachedMetric -or $cachedMetric.kind -ne 'cached_gib' -or
            [double]$cachedMetric.value -ne 12.5 -or
            -not $layerMetric -or $layerMetric.kind -ne 'model_layer' -or
            [double]$layerMetric.value -ne 42 -or
            -not $tensorMetric -or $tensorMetric.kind -ne 'tensors_loaded' -or
            [double]$tensorMetric.value -ne 128 -or
            -not $bytesMetric -or $bytesMetric.kind -ne 'bytes' -or
            [double]$bytesMetric.value -ne 4096 -or
            -not $markerMetric -or $markerMetric.kind -ne 'startup_marker' -or
            $null -ne $markerMetric.value) {
            throw 'Startup progress metric parser self-test failed'
        }

        $stalledLog = Join-Path $tmp 'startup_stalled.err'
        $stalledMarker = Join-Path $tmp 'startup_stalled.marker'
        $stalledScript = @"
for (`$i = 0; `$i -lt 40; `$i++) {
    [Console]::Error.WriteLine('CUDA loading model tensors 1.000 GiB cached')
    Start-Sleep -Milliseconds 25
}
exit 0
"@
        $stalled = & $startChild 'startup_stalled' $stalledScript
        $stalledReady = Wait-OwnedProcessReadiness -OwnedProcess $stalled -TimeoutMs 5000 `
            -PollMs 25 -Probe { return (Test-Path -LiteralPath $stalledMarker -PathType Leaf) } `
            -LogPath $stalledLog -ProgressStallMs 200 -StartupAbsoluteCapMs 5000 -ProgressAware
        if ($stalledReady.ready -or $stalledReady.status -ne 'startup-progress-stalled' -or
            [int]$stalledReady.startup_progress_count -ne 1 -or
            [string]$stalledReady.startup_last_progress_metric_kind -ne 'cached_gib' -or
            [double]$stalledReady.startup_last_progress_metric_value -ne 1.0) {
            throw "Startup monotonic stall self-test failed: $($stalledReady | ConvertTo-Json -Compress -Depth 6)"
        }
        [void](Stop-OwnedProcess -OwnedProcess $stalled -TimeoutMs 5000)
        [void](Complete-OwnedProcessExit -OwnedProcess $stalled -TimeoutMs 0)

        $absoluteLog = Join-Path $tmp 'startup_absolute.err'
        $absoluteMarker = Join-Path $tmp 'startup_absolute.marker'
        $absoluteScript = @"
for (`$i = 1; `$i -lt 100; `$i++) {
    [Console]::Error.WriteLine("CUDA loading model tensors `$i GiB cached")
    Start-Sleep -Milliseconds 10
}
exit 0
"@
        $absolute = & $startChild 'startup_absolute' $absoluteScript
        $absoluteReady = Wait-OwnedProcessReadiness -OwnedProcess $absolute -TimeoutMs 5000 `
            -PollMs 25 -Probe { return (Test-Path -LiteralPath $absoluteMarker -PathType Leaf) } `
            -LogPath $absoluteLog -ProgressStallMs 5000 -StartupAbsoluteCapMs 1200 -ProgressAware
        if ($absoluteReady.ready -or $absoluteReady.status -ne 'startup-absolute-cap' -or
            [int]$absoluteReady.startup_progress_count -lt 2) {
            throw "Startup absolute cap self-test failed: $($absoluteReady | ConvertTo-Json -Compress -Depth 6)"
        }
        [void](Stop-OwnedProcess -OwnedProcess $absolute -TimeoutMs 5000)
        [void](Complete-OwnedProcessExit -OwnedProcess $absolute -TimeoutMs 0)

        $marker = Join-Path $tmp 'ready.marker'
        $escapedMarker = $marker.Replace("'", "''")
        $successScript = "Write-Output 'success-child-started'`n" +
            "[IO.File]::WriteAllText('$escapedMarker','ready',[Text.UTF8Encoding]::new(`$false))`n" +
            "Start-Sleep -Milliseconds 300`nWrite-Output 'success-child-finished'`nexit 0"
        $success = & $startChild 'success' $successScript
        $successReady = Wait-OwnedProcessReadiness -OwnedProcess $success -TimeoutMs 5000 `
            -PollMs 25 -Probe { return (Test-Path -LiteralPath $marker -PathType Leaf) }
        if (-not $successReady.ready -or $successReady.status -ne 'ready' -or
            [int]$successReady.pid -ne [int]$success.Id) {
            throw "Synthetic readiness success self-test failed: $($successReady | ConvertTo-Json -Compress -Depth 6)"
        }
        $successExit = Complete-OwnedProcessExit -OwnedProcess $success -TimeoutMs 5000
        if (-not $successExit.exited -or [int]$successExit.exit_code -ne 0) {
            throw "Synthetic readiness success exit failed: $($successExit | ConvertTo-Json -Compress)"
        }

        $testLockPath = Join-Path $tmp 'owned.lock'
        $testLock = Open-RunLock -Path $testLockPath -RunTag 'selftest'
        if (-not (Test-Path -LiteralPath $testLockPath -PathType Leaf)) {
            throw 'Owned lock self-test did not materialize lock'
        }
        Close-RunLock -LockStream $testLock -Path $testLockPath
        if (Test-Path -LiteralPath $testLockPath) { throw 'Owned lock cleanup self-test failed' }

        [IO.File]::WriteAllText($testLockPath, '', [Text.UTF8Encoding]::new($false))
        $recoveredLock = Open-RunLock -Path $testLockPath -RunTag 'selftest-stale'
        Close-RunLock -LockStream $recoveredLock -Path $testLockPath
        if (Test-Path -LiteralPath $testLockPath) { throw 'Stale lock recovery self-test failed' }

        $syntheticSummaryPath = Join-Path $tmp 'synthetic.summary.json'
        $syntheticReceiptPath = Join-Path $tmp 'synthetic.failure_receipt.json'
        Write-JsonUtf8 -Path $syntheticSummaryPath -Value ([ordered]@{
            status = 'failed'; failure = 'synthetic'; summary_origin = 'native'
        })
        [void](Write-RunnerFailureReceipt -Path $syntheticReceiptPath `
            -SummaryPath $syntheticSummaryPath -Stage 'selftest' -Failure 'synthetic' `
            -Lifecycle $diesReady -ArtifactPaths @($multi.Process.StartInfo.FileName))
        $syntheticSummary = Get-Content -Raw -LiteralPath $syntheticSummaryPath | ConvertFrom-Json
        $syntheticReceipt = Get-Content -Raw -LiteralPath $syntheticReceiptPath | ConvertFrom-Json
        if ($syntheticSummary.status -ne 'failed' -or $syntheticSummary.summary_origin -ne 'native' -or
            $syntheticReceipt.status -ne 'failed' -or -not $syntheticReceipt.native) {
            throw 'Summary-always/failure-receipt self-test failed'
        }

        $sample1 = Normalize-HtmlDocument -FinishReason 'stop' -Content '<!DOCTYPE html><html><head><style>body{color:#111}</style></head><body><nav>N</nav><main class="hero"><h1>Hero</h1><form id="f"><input name="x"><button>Go</button></form></main><script>document.getElementById("f").addEventListener("submit",function(e){e.preventDefault();alert("ok");});</script></body>'
        if (-not $sample1.stop_reinjected -or -not $sample1.stop_contract_valid -or $sample1.document -notmatch '</html>$') {
            throw 'Stop reinjection self-test failed'
        }
        $lengthNoClose = Normalize-HtmlDocument -FinishReason 'length' -Content '<!DOCTYPE html><html><head></head><body><h1>cut'
        if ($lengthNoClose.stop_reinjected -or $lengthNoClose.stop_contract_valid -or $lengthNoClose.document -match '</html>$') {
            throw 'Length truncation fail-closed self-test failed'
        }
        $fencedText = '```html' + [Environment]::NewLine +
            '<!DOCTYPE html><html><head></head><body></body></html>' +
            [Environment]::NewLine + '```'
        $fenced = Normalize-HtmlDocument -FinishReason 'stop' -Content $fencedText
        $prefixed = Normalize-HtmlDocument -FinishReason 'stop' -Content 'Here is the file: <!DOCTYPE html><html><head></head><body></body></html>'
        if ($fenced.raw_only_html_contract -or $prefixed.raw_only_html_contract) {
            throw 'Raw-only HTML contract self-test failed'
        }
        $sample2Text = '<!DOCTYPE html><html><head><style>body{background:#050505;color:#f8fafc}.a{color:#00ffff}.b{color:#ff00ff}</style></head><body><nav>N</nav><main class="hero"><h1>Hero</h1><form id="f"><input name="x"><button>Go</button></form></main><script>document.getElementById("f").addEventListener("submit",function(e){e.preventDefault();alert("ok");});</script></body></html>'
        $q1 = Test-HtmlQuality -Turn 'turn1' -Document $sample1.document -Turn1Quality $null
        $q2 = Test-HtmlQuality -Turn 'turn2' -Document $sample2Text -Turn1Quality $q1
        if (-not $q1.pass -or -not $q2.pass) {
            throw "Quality self-test failed q1=$($q1.pass) q2=$($q2.pass)"
        }
        $ready = Test-Turn1ReadyForTurn2 -Request ([pscustomobject]@{
            finish_reason = 'stop'
            stop_contract_valid = $true
            raw_only_html_contract = $true
        }) -Quality $q1
        $blocked = Test-Turn1ReadyForTurn2 -Request ([pscustomobject]@{
            finish_reason = 'length'
            stop_contract_valid = $false
            raw_only_html_contract = $true
        }) -Quality $q1
        if (-not $ready.pass -or $blocked.pass) {
            throw 'Turn1 fail-fast readiness self-test failed'
        }
        $requestCheck = New-ExpectedRequestCountGate -Requests @(
            [pscustomobject]@{ name = 'request1' },
            [pscustomobject]@{ name = 'request2' }
        ) -Expected 2
        if (-not $requestCheck.pass -or $requestCheck.detail -ne 'observed=2 expected=2') {
            throw "Request-count self-test failed: $($requestCheck.detail)"
        }
        $turn1 = [pscustomobject]@{ document_path = Join-Path $tmp 'turn1.html' }
        $turn2 = [pscustomobject]@{ document_path = Join-Path $tmp 'turn2.html' }
        $manifest = New-RenderManifest -OutDir $tmp -Turn1 $turn1 -Turn2 $turn2
        $roundTrip = Get-Content -Raw -LiteralPath $manifest | ConvertFrom-Json
        if ($roundTrip.browser_rendering_authorized -ne $false -or @($roundTrip.tests).Count -ne 4) {
            throw 'Render manifest self-test failed'
        }
    } finally {
        foreach ($owned in @($ownedChildren)) {
            try {
                if (Test-OwnedProcessAlive $owned) { [void](Stop-OwnedProcess -OwnedProcess $owned -TimeoutMs 5000) }
                $owned.Dispose()
            } catch {}
        }
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Host '[g73-live-html-b] lifecycle self-test passed: direct-output, vanished, timeout, readiness, lock, summary'
}

function Assert-StaticContract {
    if ($MockIntegration) {
        foreach ($path in @($canonicalRunner, $mockServerPath, $mockProtocolPath,
                $mockContractTestPath)) {
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
                throw "Required CPU mock file missing: $path"
            }
        }
        if ((Get-Sha256Text $prompt1) -ne $prompt1Sha) { throw 'Canonical prompt1 SHA mismatch' }
        if ((Get-Sha256Text $prompt2) -ne $prompt2Sha) { throw 'Canonical prompt2 SHA mismatch' }
        if ([string]::IsNullOrWhiteSpace($systemPrompt)) { throw 'Mock system prompt is empty' }
        if ((Get-Sha256File $canonicalRunner) -ne $expectedCanonicalRunnerSha) {
            throw 'Canonical G73 runner changed'
        }
        [void](Get-PythonExecutable)
        $source = Get-Content -Raw -LiteralPath $runnerPath
        foreach ($token in @('raw_assistant_text', 'Get-MockCaptureValidation',
                'mock_validation_receipt.json', 'system,user,assistant,user')) {
            if ($source -notmatch [regex]::Escape($token)) {
                throw "CPU mock runner contract missing: $token"
            }
        }
        $mockIsolationContract = 'Mock mode must not access the DS4 model or executable'
        if (-not $mockIsolationContract) { throw 'Unreachable mock isolation contract' }
        return
    }
    foreach ($path in @($exe, $model, $modelReceipt, $canonicalRunner, $runtimeSource,
            $buildManifestPath, $protocolPath, $contractTestPath)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Required file missing: $path"
        }
    }
    if ((Get-Sha256Text $prompt1) -ne $prompt1Sha) { throw 'Canonical prompt1 SHA mismatch' }
    if ((Get-Sha256Text $prompt2) -ne $prompt2Sha) { throw 'Canonical prompt2 SHA mismatch' }
    if ((Get-Sha256File $canonicalRunner) -ne $expectedCanonicalRunnerSha) { throw 'Canonical G73 runner changed' }
    if ((Get-Sha256File $exe) -ne $expectedExeSha) { throw 'Executable SHA does not match requested build' }
    $receipt = Get-Content -Raw -LiteralPath $modelReceipt | ConvertFrom-Json
    if ([string]$receipt.sha256 -ne $expectedModelSha -or [UInt64]$receipt.bytes -ne $expectedModelBytes) {
        throw 'Model receipt does not match canonical G73 IQ2'
    }
    if ([UInt64](Get-Item -LiteralPath $model).Length -ne $expectedModelBytes) {
        throw 'Model file size does not match canonical G73 IQ2'
    }
    $buildManifest = Get-BuildManifestProvenance
    if ([string]$buildManifest.input_fingerprint_sha256 -ne $expectedBuildFingerprint) {
        throw "Build manifest fingerprint mismatch: $($buildManifest.input_fingerprint_sha256)"
    }
    if ([string]$buildManifest.executable_sha256 -ne $expectedExeSha) {
        throw "Build manifest executable SHA mismatch: $($buildManifest.executable_sha256)"
    }
    if ($contextTokens -ne 8192 -or $prefillChunk -ne 256 -or $maxTokens -ne 3000) {
        throw 'Long HTML stable profile changed'
    }
    if ($stopSequence -ne '</html>' -or $temperature -ne 0 -or $think -ne $false) {
        throw 'Long HTML generation controls changed'
    }
    $source = Get-Content -Raw -LiteralPath $runtimeSource
    foreach ($token in @('DS4_G73_TWO_TURN_TRACE', 'DS4_G73_TWO_TURN_STALE_MASK_ONLY_AFTER_FIRST',
            '[g73-two-turn-prefill]', '[g73-two-turn-workspace]',
            'stale-reseed-deferred', 'dynamic-seed-deferred', 'turnover-in-place',
            '[g73-two-turn-cache-ensure]', '[g73-two-turn-tier]')) {
        if ($source -notmatch [regex]::Escape($token)) {
            throw "Runtime trace missing for long HTML contract: $token"
        }
    }
    $armEnv = Get-ServerEnvironment $Arm
    if ($Arm -eq 'A' -and [string]$armEnv.DS4_G73_TWO_TURN_STALE_MASK_ONLY_AFTER_FIRST -ne '1') {
        throw 'Arm A stale mask-only env missing'
    }
    if ($Arm -eq 'B' -and $null -ne $armEnv.DS4_G73_TWO_TURN_STALE_MASK_ONLY_AFTER_FIRST) {
        throw 'Arm B must not set stale mask-only env'
    }
    if ($null -ne $armEnv.DS4_G73_TWO_TURN_FREEZE_AFTER_FIRST) {
        throw 'Legacy freeze env must remain unset'
    }
}

Assert-StaticContract
if ($LifecycleSelfTest) {
    Invoke-LifecycleSelfTest
    exit 0
}
if ($StaticCheckOnly) {
    Write-Host "[g73-live-html-b] static contract passed mode=$(if($MockIntegration){'cpu-mock'}else{'live'})"
    exit 0
}
$target = if ($MockIntegration) { "G73 live HTML CPU mock $MockScenario" } else { "G73 long HTML Arm $Arm" }
if (-not $PSCmdlet.ShouldProcess($target, 'Run dedicated live runner')) {
    return
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outRoot) | Out-Null
New-Item -ItemType Directory -Force -Path $outRoot | Out-Null
$stamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')
if (-not $Tag) {
    $Tag = if ($MockIntegration) { "g73_live_mock_$($MockScenario.Replace('-', '_'))_$stamp" } else { "g73_live_html_b_$stamp" }
}
$outDir = Join-Path $outRoot $Tag
if (Test-Path -LiteralPath $outDir) { throw "Output already exists: $outDir" }
New-Item -ItemType Directory -Path $outDir | Out-Null

$summaryPath = Join-Path $outDir 'summary.json'
$failureReceiptPath = Join-Path $outDir 'failure_receipt.json'
$preflightPath = Join-Path $outDir 'preflight.json'
$postflightPath = Join-Path $outDir 'postflight.json'
$stdoutLog = Join-Path $outDir 'server.stdout.log'
$stderrLog = Join-Path $outDir 'server.stderr.log'
$samplerPath = Join-Path $outDir 'gpu_sampler.csv'
$runnerEventsPath = Join-Path $outDir 'runner_events.json'
$environmentPath = Join-Path $outDir 'environment.json'
$abortSnapshotPath = Join-Path $outDir 'abort_snapshot.json'
$mockCaptureDir = Join-Path $outDir 'mock_capture'
$mockValidationReceiptPath = Join-Path $outDir 'mock_validation_receipt.json'

$lockStream = $null
$gpuSamplerJob = $null
$process = $null
$ownedServerPid = $null
$requestResults = @()
$quality = @()
$runnerEvents = [System.Collections.ArrayList]::new()
$runFailure = ''
$serverExit = $null
$postflight = $null
$preflight = $null
$port = $null
$uri = $null
$arguments = @()
$launchFilePath = $exe
$environment = if ($MockIntegration) { [ordered]@{} } else { Get-ServerEnvironment $Arm }
$previousEnvironment = @{}
$renderManifestPath = $null
$turn1Readiness = $null
$chatTranscript = $null
$mockValidation = $null
$mockValidationReceipt = $null
$runStage = 'output-directory-created'
$failureStage = ''
$parserError = ''
$cleanupErrors = [System.Collections.ArrayList]::new()
$readinessResult = $null
$lifecycle = [ordered]@{
    launcher = 'direct-system-diagnostics-process'
    wrapper_used = $false
    process_pid = $null
    process_start_utc = $null
    readiness = $null
    vanished_pid_detected = $false
    vanished_pid_detected_utc = $null
    cleanup_attempted = $false
    cleanup_stopped_process = $false
    stdout_path = $stdoutLog
    stderr_path = $stderrLog
}

try {
    $runStage = 'lock-acquire'
    $lockStream = Open-RunLock -Path $lockPath -RunTag $Tag
    $runStage = 'preflight'
    $preflight = if ($MockIntegration) { Get-MockPreflight } else { Get-Preflight }
    $preflight | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $preflightPath -Encoding UTF8
    if (@($preflight.conflicting_processes).Count -ne 0) {
        throw 'Preflight refused launch: conflicting process exists'
    }
    if (-not $MockIntegration) {
        Test-LivePreflightLaunchGate -Preflight $preflight
    }
    if (-not $MockIntegration) {
        $receipt = Get-Content -Raw -LiteralPath $modelReceipt | ConvertFrom-Json
        if ([string]$receipt.sha256 -ne $expectedModelSha -or
            [UInt64]$receipt.bytes -ne $expectedModelBytes -or
            [UInt64](Get-Item -LiteralPath $model).Length -ne $expectedModelBytes) {
            throw 'Model receipt/size does not match canonical G73 IQ2'
        }
        if ((Get-Sha256File $exe) -ne $expectedExeSha) {
            throw 'Executable SHA does not match requested build'
        }
    }
    foreach ($key in $environment.Keys) {
        $previousEnvironment[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
        if ($null -eq $environment[$key]) {
            [Environment]::SetEnvironmentVariable($key, $null, 'Process')
        } else {
            [Environment]::SetEnvironmentVariable($key, [string]$environment[$key], 'Process')
        }
    }
    $environment | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $environmentPath -Encoding UTF8
    $port = Get-FreeTcpPort
    $uri = "http://127.0.0.1:$port/v1/chat/completions"
    if ($MockIntegration) {
        New-Item -ItemType Directory -Path $mockCaptureDir | Out-Null
        $launchFilePath = Get-PythonExecutable
        $arguments = @($mockServerPath, '--port', [string]$port, '--scenario',
            $MockScenario, '--capture-dir', $mockCaptureDir)
    } else {
        $arguments = @('-m', $model, '--cuda', '-c', [string]$contextTokens,
            '-n', [string]$maxTokens, '--host', '127.0.0.1', '--port', [string]$port)
        $runStage = 'sampler-start'
        $gpuSamplerJob = Start-GpuSampler -Path $samplerPath -IntervalMs $samplerIntervalMs
    }
    Add-RunnerEvent -Events $runnerEvents -Name 'server_start'
    $runStage = 'server-launch'
    $process = Start-LoggedOwnedProcess -FilePath $launchFilePath -Arguments $arguments `
        -StdoutPath $stdoutLog -StderrPath $stderrLog
    $ownedServerPid = [int]$process.Id
    $lifecycle.process_pid = $ownedServerPid
    $lifecycle.process_start_utc = $process.StartTimeUtc.ToString('o')
    Add-RunnerEvent -Events $runnerEvents -Name 'server_process_started'
    $runStage = 'server-readiness'
    if ($MockIntegration) {
        $readinessProbe = {
            $healthClient = [System.Net.Http.HttpClient]::new()
            try {
                $healthClient.Timeout = [TimeSpan]::FromMilliseconds(500)
                $health = $healthClient.GetAsync("http://127.0.0.1:$port/health").Result
                return [bool]$health.IsSuccessStatusCode
            } catch {
                return $false
            } finally {
                $healthClient.Dispose()
            }
        }
    } else {
        $readinessProbe = {
            $healthClient = [System.Net.Http.HttpClient]::new()
            try {
                $healthClient.Timeout = [TimeSpan]::FromMilliseconds(500)
                $health = $healthClient.GetAsync("http://127.0.0.1:$port/health").Result
                return [bool]$health.IsSuccessStatusCode
            } catch {
                return $false
            } finally {
                $healthClient.Dispose()
            }
        }
    }
    $readinessTimeoutMs = if ($MockIntegration) { 10000 } else { $TimeoutSec * 1000 }
    $readinessResult = Wait-OwnedProcessReadiness -OwnedProcess $process `
        -Probe $readinessProbe -TimeoutMs $readinessTimeoutMs -PollMs 100 `
        -LogPath $(if ($MockIntegration) { '' } else { $stderrLog }) `
        -ProgressStallMs ($startupProgressStallSec * 1000) `
        -StartupAbsoluteCapMs ($StartupAbsoluteCapSec * 1000) `
        -SamplerPath $(if ($MockIntegration) { '' } else { $samplerPath }) `
        -SamplerStallMs ($samplerStallSec * 1000) `
        -ProgressAware:([bool](-not $MockIntegration))
    $lifecycle.readiness = $readinessResult
    if (-not $readinessResult.ready) {
        if ($readinessResult.status -eq 'process-exited-before-readiness') {
            $lifecycle.vanished_pid_detected = $true
            $lifecycle.vanished_pid_detected_utc = [DateTime]::UtcNow.ToString('o')
            $serverExit = $readinessResult.exit
        } else {
            [void](Stop-OwnedProcessWithSnapshot -OwnedProcess $process -TimeoutMs 10000 `
                -SnapshotPath $abortSnapshotPath -Reason "readiness-$($readinessResult.status)" `
                -StderrPath $stderrLog -SamplerPath $samplerPath)
            $serverExit = Complete-OwnedProcessExit -OwnedProcess $process -TimeoutMs 0
        }
        throw "Server readiness failed: status=$($readinessResult.status) exit=$($serverExit.exit_code) reason=$($serverExit.reason)"
    }
    Add-RunnerEvent -Events $runnerEvents -Name 'server_ready'
    $runStage = 'request1'
    $turn1 = Invoke-LongHtmlRequest -Uri $uri `
        -Messages @(@{role='system'; content=$systemPrompt}, @{role='user'; content=$prompt1}) `
        -Name 'request1' -Turn 'turn1' `
        -OutDir $outDir -OwnedProcess $process -LogPath $stderrLog -RunnerEvents $runnerEvents `
        -SamplerPath $(if ($MockIntegration) { '' } else { $samplerPath }) `
        -AbortSnapshotPath $abortSnapshotPath
    $requestResults += $turn1
    $turn1Doc = Get-Content -Raw -LiteralPath $turn1.document_path
    $turn1Raw = [string]$turn1.raw_assistant_text
    $q1 = Test-HtmlQuality -Turn 'turn1' -Document $turn1Doc -Turn1Quality $null
    $quality += $q1
    $chatTranscript = Write-LiveChatTranscript -OutDir $outDir -Turn1 $turn1 -Turn1Raw $turn1Raw -Turn2 $null -Turn2Raw $null
    $turn1Readiness = Test-Turn1ReadyForTurn2 -Request $turn1 -Quality $q1
    if (-not $turn1Readiness.pass) {
        $renderManifestPath = New-RenderManifest -OutDir $outDir -Turn1 $turn1 -Turn2 $null
        throw "Turn1 fail-fast before request2: finish=$($turn1Readiness.finish_reason) stop_contract=$($turn1Readiness.stop_contract_valid) raw_only_html=$($turn1Readiness.raw_only_html_contract) quality=$($turn1Readiness.quality_pass)"
    }
    $runStage = 'request2'
    $turn2 = Invoke-LongHtmlRequest -Uri $uri -Messages @(
        @{role='system'; content=$systemPrompt},
        @{role='user'; content=$prompt1},
        @{role='assistant'; content=$turn1Raw},
        @{role='user'; content=$prompt2}
    ) -Name 'request2' -Turn 'turn2' -OutDir $outDir -OwnedProcess $process `
        -LogPath $stderrLog -RunnerEvents $runnerEvents `
        -SamplerPath $(if ($MockIntegration) { '' } else { $samplerPath }) `
        -AbortSnapshotPath $abortSnapshotPath `
        -Turn1DocumentSha256Used $turn1.raw_assistant_sha256
    $requestResults += $turn2
    $turn2Doc = Get-Content -Raw -LiteralPath $turn2.document_path
    $turn2Raw = [string]$turn2.raw_assistant_text
    $chatTranscript = Write-LiveChatTranscript -OutDir $outDir -Turn1 $turn1 -Turn1Raw $turn1Raw -Turn2 $turn2 -Turn2Raw $turn2Raw
    $quality += Test-HtmlQuality -Turn 'turn2' -Document $turn2Doc -Turn1Quality $q1
    $renderManifestPath = New-RenderManifest -OutDir $outDir -Turn1 $turn1 -Turn2 $turn2
    $runStage = 'server-exit'
    $serverExit = Complete-OwnedProcessExit -OwnedProcess $process -TimeoutMs ([math]::Min(120000, $TimeoutSec * 1000))
    Add-RunnerEvent -Events $runnerEvents -Name 'server_exit'
} catch {
    $runFailure = $_.Exception.Message
    $failureStage = $runStage
    $lifecycle.cleanup_attempted = $true
    if ($process) {
        $processWasAlive = Test-OwnedProcessAlive $process
        if (-not $processWasAlive -and -not $lifecycle.vanished_pid_detected -and
            $runStage -ne 'server-exit') {
            $lifecycle.vanished_pid_detected = $true
            $lifecycle.vanished_pid_detected_utc = [DateTime]::UtcNow.ToString('o')
        }
        if ($processWasAlive) {
            $lifecycle.cleanup_stopped_process = [bool](Stop-OwnedProcessWithSnapshot `
                -OwnedProcess $process -TimeoutMs 10000 -SnapshotPath $abortSnapshotPath `
                -Reason "catch-$runStage" -StderrPath $stderrLog -SamplerPath $samplerPath)
        }
    }
    if ($process -and -not $serverExit) {
        $serverExit = Complete-OwnedProcessExit -OwnedProcess $process -TimeoutMs 10000
    }
    Add-RunnerEvent -Events $runnerEvents -Name 'run_failure'
} finally {
    $runStage = 'cleanup'
    try {
        Stop-GpuSampler -OwnedProcess $gpuSamplerJob
    } catch {
        [void]$cleanupErrors.Add("sampler-cleanup:$($_.Exception.Message)")
    }
    try {
        if ($process) {
            $lifecycle.cleanup_attempted = $true
            if (Test-OwnedProcessAlive $process) {
                $lifecycle.cleanup_stopped_process = [bool](Stop-OwnedProcessWithSnapshot `
                    -OwnedProcess $process -TimeoutMs 10000 -SnapshotPath $abortSnapshotPath `
                    -Reason 'finally-cleanup' -StderrPath $stderrLog -SamplerPath $samplerPath)
            }
            if ((-not $serverExit) -or (-not [bool]$serverExit.exited)) {
                $serverExit = Complete-OwnedProcessExit -OwnedProcess $process -TimeoutMs 10000
            }
            $process.Dispose()
        }
    } catch {
        [void]$cleanupErrors.Add("server-cleanup:$($_.Exception.Message)")
    }
    foreach ($key in $environment.Keys) {
        try {
            [Environment]::SetEnvironmentVariable($key, $previousEnvironment[$key], 'Process')
        } catch {
            [void]$cleanupErrors.Add("environment-restore-$key`:$($_.Exception.Message)")
        }
    }
    try {
        Close-RunLock -LockStream $lockStream -Path $lockPath
        $lockStream = $null
    } catch {
        [void]$cleanupErrors.Add("lock-cleanup:$($_.Exception.Message)")
    }
    try {
        Write-JsonUtf8 -Path $runnerEventsPath -Value @($runnerEvents) -Depth 8
    } catch {
        [void]$cleanupErrors.Add("runner-events-write:$($_.Exception.Message)")
    }
    try {
        $postflight = if ($MockIntegration) { Get-MockPreflight } else { Get-Preflight }
        Write-JsonUtf8 -Path $postflightPath -Value $postflight -Depth 12
    } catch {
        [void]$cleanupErrors.Add("postflight:$($_.Exception.Message)")
    }
}

if ($cleanupErrors.Count -ne 0) {
    $cleanupText = @($cleanupErrors) -join '; '
    if ([string]::IsNullOrEmpty($runFailure)) {
        $runFailure = $cleanupText
        $failureStage = 'cleanup'
    } else {
        $runFailure += "; cleanup=$cleanupText"
    }
}

if ($MockIntegration) {
    try {
        $mockValidation = Get-MockCaptureValidation -CaptureDir $mockCaptureDir `
            -Scenario $MockScenario -HttpResults @($requestResults)
    } catch {
        $mockValidation = [pscustomobject]@{
            pass = $false
            scenario = $MockScenario
            request_count = @($requestResults).Count
            validation_error = $_.Exception.Message
        }
        if ([string]::IsNullOrEmpty($runFailure)) {
            $runFailure = "mock-validation:$($_.Exception.Message)"
            $failureStage = 'mock-validation'
        } else {
            $runFailure += "; mock-validation=$($_.Exception.Message)"
        }
    }
    try {
        $mockValidationReceipt = Write-MockValidationReceipt -Path $mockValidationReceiptPath `
            -Validation $mockValidation -Scenario $MockScenario -CaptureDir $mockCaptureDir
    } catch {
        if ([string]::IsNullOrEmpty($runFailure)) {
            $runFailure = "mock-validation-receipt:$($_.Exception.Message)"
            $failureStage = 'mock-validation-receipt'
        } else {
            $runFailure += "; mock-validation-receipt=$($_.Exception.Message)"
        }
    }
}

$summary = $null
$status = 'failed'
$failedGates = @()
$requests = @()
$logSummary = $null
try {
    $runStage = 'summary-parse'
    $logSummary = Get-LongLogSummary -LogPath $stderrLog
    $requests = @(Join-RequestMetrics -HttpResults @($requestResults) -LogMetrics @($logSummary.server_request_metrics))
    $gitProvenance = Get-GitProvenance
    $buildManifestProvenance = if ($MockIntegration) { $null } else { Get-BuildManifestProvenance }
    $gates = [System.Collections.ArrayList]::new()
    if ($MockIntegration) {
        Add-MockGates -Gates $gates -Scenario $MockScenario -Preflight $preflight `
            -ServerExit $serverExit -Requests @($requests) -Quality @($quality) `
            -Turn1Readiness $turn1Readiness -Validation $mockValidation -Failure $runFailure
    } else {
        Add-CommonGates -Gates $gates -Preflight $preflight -ServerExit $serverExit `
            -Requests @($requests) -Quality @($quality) -LogSummary $logSummary -Failure $runFailure
        Add-ArmGates -Gates $gates -LogSummary $logSummary -SelectedArm $Arm
    }
    $status = Get-StatusFromGates -Gates @($gates) -Failure $runFailure
    $failedGates = @($gates | Where-Object { -not $_.pass })
    if ($status -ne 'pass' -and [string]::IsNullOrEmpty($failureStage)) {
        $failureStage = 'summary-gates'
    }

    $summary = [ordered]@{
        schema = if ($MockIntegration) { 'g73_live_html_b_mock_integration_v1' } else { 'g73_live_html_b_end_to_end_v2' }
        status = $status
        failure = $runFailure
        failure_stage = $failureStage
        parser_error = $parserError
        summary_origin = 'native-runner'
        summary_recovered = $false
        tag = $Tag
        arm = $Arm
        output_dir = $outDir
        no_n_ge_3_claim = $true
        no_quality_performance_full_open_claim = $true
        lifecycle = $lifecycle
        provenance = [ordered]@{
            runner_sha256 = Get-Sha256File $runnerPath
            protocol_sha256 = if ($MockIntegration) { Get-Sha256File $mockProtocolPath } else { Get-Sha256File $protocolPath }
            contract_test_sha256 = if ($MockIntegration) { Get-Sha256File $mockContractTestPath } else { Get-Sha256File $contractTestPath }
            mock_server_sha256 = if ($MockIntegration) { Get-Sha256File $mockServerPath } else { $null }
            model_receipt_file_sha256 = if ($MockIntegration) { $null } else { Get-Sha256File $modelReceipt }
            build_manifest = $buildManifestProvenance
            build_fingerprint_expected_sha256 = $expectedBuildFingerprint
            executable_sha256 = if ($MockIntegration) { $null } else { Get-Sha256File $exe }
            executable_expected_sha256 = $expectedExeSha
            canonical_runner_sha256 = Get-Sha256File $canonicalRunner
            canonical_runner_expected_sha256 = $expectedCanonicalRunnerSha
            model = $model
            model_sha256 = $expectedModelSha
            model_bytes = $expectedModelBytes
            model_receipt_path = $modelReceipt
            system_prompt_sha256 = Get-Sha256Text $systemPrompt
            prompt1_sha256 = Get-Sha256Text $prompt1
            prompt1_expected_sha256 = $prompt1Sha
            prompt2_sha256 = Get-Sha256Text $prompt2
            prompt2_expected_sha256 = $prompt2Sha
            git = $gitProvenance
        }
        config = [ordered]@{
            context = $contextTokens
            prefill_chunk = $prefillChunk
            max_tokens = $maxTokens
            temperature = $temperature
            think = $think
            stop_sequence = $stopSequence
            requests = 2
            decode_abort_manifest = $decodeFloorManifest
            startup_progress_stall_seconds = $startupProgressStallSec
            startup_absolute_cap_seconds = $StartupAbsoluteCapSec
            sampler_stall_seconds = $samplerStallSec
            preflight_thresholds = $preflightThresholds
            sampler_pressure_thresholds = $samplerPressureThresholds
        }
        environment = $environment
        launch_file = $launchFilePath
        arguments = $arguments
        server_pid = $ownedServerPid
        server_exit = $serverExit
        requests = @($requests)
        quality_gates = @($quality)
        turn1_readiness_for_turn2 = $turn1Readiness
        chat_transcript = $chatTranscript
        render_manifest = $renderManifestPath
        gpu_sampler = if ($MockIntegration) {
            [pscustomobject]@{ path = $null; rows = 0; disabled = 'cpu-mock' }
        } else {
            Get-GpuSamplerSummary -CsvPath $samplerPath -RunnerEvents @($runnerEvents)
        }
        mock = if ($MockIntegration) {
            [ordered]@{
                enabled = $true
                scenario = $MockScenario
                cpu_only = $true
                synthetic_quality_claim = if ($MockScenario -eq 'success' -and
                    @($quality | Where-Object { $_.turn -eq 'turn1' -and $_.pass }).Count -eq 1) {
                    'L2-contract-only'
                } else { 'none' }
                no_g73_mechanism_quality_performance_claim = $true
                validation = $mockValidation
                validation_receipt_path = $mockValidationReceiptPath
            }
        } else { $null }
        gates = @($gates)
        failed_gates = $failedGates
        log_summary = $logSummary
        cleanup_errors = @($cleanupErrors)
        paths = [ordered]@{
            summary = $summaryPath
            failure_receipt = $failureReceiptPath
            mock_validation_receipt = if ($MockIntegration) { $mockValidationReceiptPath } else { $null }
            mock_capture_dir = if ($MockIntegration) { $mockCaptureDir } else { $null }
            stdout = $stdoutLog
            stderr = $stderrLog
            gpu_sampler = $samplerPath
            gpu_sampler_worker_stdout = "$samplerPath.worker.stdout.log"
            gpu_sampler_worker_stderr = "$samplerPath.worker.stderr.log"
            runner_events = $runnerEventsPath
            abort_snapshot = $abortSnapshotPath
            preflight = $preflightPath
            postflight = $postflightPath
            environment = $environmentPath
            render_manifest = $renderManifestPath
            chat_transcript_markdown = if ($chatTranscript) { $chatTranscript.markdown_path } else { $null }
            chat_transcript_messages_json = if ($chatTranscript) { $chatTranscript.messages_json_path } else { $null }
        }
        preflight = $preflight
        postflight = $postflight
    }
    Write-JsonUtf8 -Path $summaryPath -Value $summary
} catch {
    $parserError = $_.Exception.Message
    if ([string]::IsNullOrEmpty($runFailure)) {
        $runFailure = "summary-parser:$parserError"
    } else {
        $runFailure += "; summary-parser=$parserError"
    }
    $failureStage = 'summary-parser'
    $status = 'failed'
    $failedGates = @([pscustomobject]@{
        name = 'summary_parser'
        pass = $false
        detail = $parserError
    })
    $summary = [ordered]@{
        schema = if ($MockIntegration) { 'g73_live_html_b_mock_integration_v1' } else { 'g73_live_html_b_end_to_end_v2' }
        status = 'failed'
        failure = $runFailure
        failure_stage = $failureStage
        parser_error = $parserError
        summary_origin = 'native-runner-fallback'
        summary_recovered = $false
        tag = $Tag
        arm = $Arm
        output_dir = $outDir
        no_n_ge_3_claim = $true
        no_quality_performance_full_open_claim = $true
        lifecycle = $lifecycle
        mock = if ($MockIntegration) {
            [ordered]@{
                enabled = $true
                scenario = $MockScenario
                cpu_only = $true
                no_g73_mechanism_quality_performance_claim = $true
                validation = $mockValidation
                validation_receipt_path = $mockValidationReceiptPath
            }
        } else { $null }
        server_pid = $ownedServerPid
        server_exit = $serverExit
        requests = @($requestResults)
        quality_gates = @($quality)
        cleanup_errors = @($cleanupErrors)
        failed_gates = $failedGates
        paths = [ordered]@{
            summary = $summaryPath
            failure_receipt = $failureReceiptPath
            mock_validation_receipt = if ($MockIntegration) { $mockValidationReceiptPath } else { $null }
            mock_capture_dir = if ($MockIntegration) { $mockCaptureDir } else { $null }
            stdout = $stdoutLog
            stderr = $stderrLog
            gpu_sampler = $samplerPath
            runner_events = $runnerEventsPath
            abort_snapshot = $abortSnapshotPath
            preflight = $preflightPath
            postflight = $postflightPath
            environment = $environmentPath
        }
        preflight = $preflight
        postflight = $postflight
    }
    Write-JsonUtf8 -Path $summaryPath -Value $summary
}

if ($status -ne 'pass') {
    try {
        [void](Write-RunnerFailureReceipt -Path $failureReceiptPath `
            -SummaryPath $summaryPath -Stage $failureStage -Failure $runFailure `
            -Lifecycle $lifecycle -ArtifactPaths @(
                $preflightPath, $postflightPath, $environmentPath, $runnerEventsPath,
                $stdoutLog, $stderrLog, $samplerPath, $abortSnapshotPath,
                "$samplerPath.worker.stdout.log", "$samplerPath.worker.stderr.log",
                $mockValidationReceiptPath,
                (Join-Path $mockCaptureDir 'request1.raw.json'),
                (Join-Path $mockCaptureDir 'request1.canonical.json'),
                (Join-Path $mockCaptureDir 'request2.raw.json'),
                (Join-Path $mockCaptureDir 'request2.canonical.json')))
    } catch {
        $receiptError = $_.Exception.Message
        $summary['failure_receipt_error'] = $receiptError
        $summary['failure'] = "$runFailure; failure-receipt=$receiptError"
        Write-JsonUtf8 -Path $summaryPath -Value $summary
    }
}

Write-Host "G73_LIVE_HTML_B_SUMMARY=$summaryPath"
if ($status -ne 'pass') {
    throw "G73 live HTML runner failed: mode=$(if($MockIntegration){'cpu-mock'}else{'live'}) status=$status failure=$runFailure failed_gates=$(@($failedGates | ForEach-Object {$_.name}) -join ',')"
}
