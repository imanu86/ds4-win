# G57 sparse-bake K60/K75 functional safety runner (PowerShell 5.1, ASCII).
# This runner performs no performance comparison and declares n=1 functional only.
param(
    [Parameter(Mandatory=$true)][string]$ModelPath,
    [Parameter(Mandatory=$true)][ValidateSet("K60", "K75")][string]$BakeId,
    [Parameter(Mandatory=$true)][string]$ExpectedPackSHA256,
    [Parameter(Mandatory=$true)][string]$ExpectedMaskSHA256,
    [Parameter(Mandatory=$true)][string]$ExpectedPayloadSHA256,
    [string]$PackPath = "",
    [ValidateRange(1, 131072)][int]$MaxTokens = 64,
    [string]$ExpectedContentSHA256 = "",
    [string]$Prompt = "Reply with exactly: sparse bake functional safety ok",
    [ValidateRange(64, 131072)][int]$Context = 256,
    [ValidateRange(1, 86400)][int]$TimeoutSec = 1800,
    [string]$Tag = "",
    [switch]$Resume,
    [switch]$SummarizeExisting,
    [string]$ExecutionRunnerSHA256 = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$harness = Join-Path $root "g7_measure.ps1"
$runtimeMonitor = Join-Path $root "g7_runtime_monitor.ps1"
$outdir = Join-Path $root "g7_runs"
$executable = Join-Path $root "build\Release\ds4_server.exe"
$buildManifest = Join-Path $root "build\Release\g7_build_manifest.json"

function Assert-G57Hex64 {
    param([Parameter(Mandatory=$true)][string]$Name,
          [Parameter(Mandatory=$true)][string]$Value)
    if ($Value -notmatch '^[0-9a-fA-F]{64}$') {
        throw "$Name must be a 64-character hexadecimal SHA-256"
    }
}

function Get-G57SHA256 {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "G57 provenance file missing: $Path"
    }
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-G57BytesSHA256 {
    param([Parameter(Mandatory=$true)][byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Get-G57CRC32 {
    param([Parameter(Mandatory=$true)][byte[]]$Bytes)
    [uint64]$crc = 4294967295
    foreach ($value in $Bytes) {
        $crc = $crc -bxor [uint64]$value
        for ($bit = 0; $bit -lt 8; $bit++) {
            if (($crc -band 1) -ne 0) {
                $crc = (($crc -shr 1) -bxor [uint64]3988292384) -band
                    [uint64]4294967295
            } else {
                $crc = $crc -shr 1
            }
        }
    }
    [uint32](($crc -bxor [uint64]4294967295) -band [uint64]4294967295)
}

function Read-G57Exact {
    param([Parameter(Mandatory=$true)][IO.FileStream]$Stream,
          [Parameter(Mandatory=$true)][byte[]]$Buffer,
          [Parameter(Mandatory=$true)][int]$Count)
    $offset = 0
    while ($offset -lt $Count) {
        $n = $Stream.Read($Buffer, $offset, $Count - $offset)
        if ($n -le 0) { throw "Unexpected EOF while reading sparse bake" }
        $offset += $n
    }
}

function Read-G57UInt32LE {
    param([Parameter(Mandatory=$true)][byte[]]$Bytes,
          [Parameter(Mandatory=$true)][int]$Offset)
    [BitConverter]::ToUInt32($Bytes, $Offset)
}

function Read-G57UInt64LE {
    param([Parameter(Mandatory=$true)][byte[]]$Bytes,
          [Parameter(Mandatory=$true)][int]$Offset)
    [BitConverter]::ToUInt64($Bytes, $Offset)
}

function ConvertTo-G57Extents {
    param([Parameter(Mandatory=$true)][object]$Manifest)
    $rows = @()
    foreach ($extent in @($Manifest.extents)) {
        if ($null -eq $extent) { continue }
        if ($extent -is [System.Array]) {
            if ($extent.Count -ne 2) { throw "Invalid sparse bake extent pair" }
            $rows += [pscustomobject]@{
                offset = [uint64]$extent[0]
                bytes = [uint64]$extent[1]
            }
            continue
        }
        $offset = $null
        $bytes = $null
        foreach ($offsetName in @("offset", "file_offset", "source_offset", "start")) {
            if ($extent.PSObject.Properties[$offsetName]) {
                $offset = [uint64]$extent.$offsetName
                break
            }
        }
        foreach ($bytesName in @("bytes", "length", "size")) {
            if ($extent.PSObject.Properties[$bytesName]) {
                $bytes = [uint64]$extent.$bytesName
                break
            }
        }
        if ($null -eq $bytes -and $extent.PSObject.Properties["end"]) {
            $end = [uint64]$extent.end
            if ($null -eq $offset -or $end -lt $offset) {
                throw "Invalid sparse bake extent end/offset"
            }
            $bytes = $end - $offset
        }
        if ($null -eq $offset -or $null -eq $bytes -or $bytes -eq 0) {
            throw "Invalid sparse bake extent entry"
        }
        $rows += [pscustomobject]@{ offset = $offset; bytes = $bytes }
    }
    if ($rows.Count -eq 0) { throw "Sparse bake manifest has no extents" }
    $rows
}

function Get-G57PayloadSHA256 {
    param([Parameter(Mandatory=$true)][string]$Path,
          [Parameter(Mandatory=$true)][object[]]$Extents)
    $sha = [Security.Cryptography.SHA256]::Create()
    $fs = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read,
        [IO.FileShare]::Read)
    try {
        $buffer = New-Object byte[] (4MB)
        foreach ($extent in $Extents) {
            $fs.Seek([int64]$extent.offset, [IO.SeekOrigin]::Begin) | Out-Null
            $remaining = [uint64]$extent.bytes
            while ($remaining -gt 0) {
                $want = [int][Math]::Min([uint64]$buffer.Length, $remaining)
                Read-G57Exact -Stream $fs -Buffer $buffer -Count $want
                $remaining -= [uint64]$want
                $null = $sha.TransformBlock($buffer, 0, $want, $null, 0)
            }
        }
        $null = $sha.TransformFinalBlock((New-Object byte[] 0), 0, 0)
        [BitConverter]::ToString($sha.Hash).Replace("-", "").ToLowerInvariant()
    } finally {
        $fs.Dispose()
        $sha.Dispose()
    }
}

function Get-G57SparseBakeManifest {
    param([Parameter(Mandatory=$true)][string]$Path)
    $fs = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read,
        [IO.FileShare]::Read)
    try {
        if ($fs.Length -lt 56) { throw "Sparse bake file is too small" }
        $footer = New-Object byte[] 56
        $fs.Seek(-56, [IO.SeekOrigin]::End) | Out-Null
        Read-G57Exact -Stream $fs -Buffer $footer -Count 56
        $magic = [Text.Encoding]::ASCII.GetString($footer, 0, 16).TrimEnd([char]0)
        if ($magic -ne "DS4BAKEFILEv1") {
            throw "ModelPath does not contain a DS4 sparse bake footer"
        }
        $version = Read-G57UInt32LE $footer 16
        $layers = Read-G57UInt32LE $footer 20
        $experts = Read-G57UInt32LE $footer 24
        $maskLen = Read-G57UInt32LE $footer 28
        $sourceSize = Read-G57UInt64LE $footer 32
        $manifestLen = Read-G57UInt64LE $footer 40
        $manifestCrc = Read-G57UInt32LE $footer 48
        $maskCrc = Read-G57UInt32LE $footer 52
        if ($version -ne 1 -or $layers -ne 43 -or $experts -ne 256 -or
            $maskLen -ne (43 * 32) -or $manifestLen -le 0) {
            throw "Sparse bake footer geometry/version is not the DS4 K60/K75 contract"
        }
        $manifestOffset = [int64]$sourceSize
        $maskOffset = [int64]($sourceSize + $manifestLen)
        $expectedFileBytes = [int64]($sourceSize + $manifestLen + $maskLen + 56)
        if ($fs.Length -ne $expectedFileBytes) {
            throw "Sparse bake physical size does not match footer arithmetic"
        }
        $manifestBytes = New-Object byte[] ([int]$manifestLen)
        $fs.Seek($manifestOffset, [IO.SeekOrigin]::Begin) | Out-Null
        Read-G57Exact -Stream $fs -Buffer $manifestBytes -Count ([int]$manifestLen)
        $maskBytes = New-Object byte[] ([int]$maskLen)
        $fs.Seek($maskOffset, [IO.SeekOrigin]::Begin) | Out-Null
        Read-G57Exact -Stream $fs -Buffer $maskBytes -Count ([int]$maskLen)
        $manifestText = [Text.Encoding]::UTF8.GetString($manifestBytes)
        $manifest = $manifestText | ConvertFrom-Json
        if ($manifest.format -ne "ds4-windows-sparse-bake" -or
            [int]$manifest.version -ne 1 -or
            [uint64]$manifest.source_model_size -ne $sourceSize) {
            throw "Sparse bake manifest identity mismatch"
        }
        if ((Get-G57CRC32 $manifestBytes) -ne $manifestCrc -or
            (Get-G57CRC32 $maskBytes) -ne $maskCrc) {
            throw "Sparse bake footer CRC mismatch"
        }
        [pscustomobject]@{
            manifest = $manifest
            manifest_sha256 = Get-G57BytesSHA256 $manifestBytes
            mask_sha256 = Get-G57BytesSHA256 $maskBytes
            source_size = $sourceSize
            physical_size = [uint64]$fs.Length
            manifest_length = $manifestLen
            mask_length = $maskLen
            manifest_crc32 = $manifestCrc
            mask_crc32 = $maskCrc
            extents = @(ConvertTo-G57Extents -Manifest $manifest)
        }
    } finally {
        $fs.Dispose()
    }
}

function Test-G57HarnessParameter {
    param([Parameter(Mandatory=$true)][string]$ParameterName)
    $content = Get-Content -LiteralPath $harness -Raw
    return ($content -match ("\$" + [regex]::Escape($ParameterName) +
        "(\s|=|,|\))"))
}

function Assert-G57LogContains {
    param([Parameter(Mandatory=$true)][string[]]$Lines,
          [Parameter(Mandatory=$true)][string]$Pattern,
          [Parameter(Mandatory=$true)][string]$Label)
    if (-not @($Lines | Where-Object { $_ -match $Pattern } | Select-Object -First 1)) {
        throw "G57 sparse bake safety log check failed: $Label"
    }
}

function Get-G57Property {
    param([object]$Object, [string]$Name)
    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) {
        return $null
    }
    $Object.PSObject.Properties[$Name].Value
}

Assert-G57Hex64 "ExpectedPackSHA256" $ExpectedPackSHA256
Assert-G57Hex64 "ExpectedMaskSHA256" $ExpectedMaskSHA256
Assert-G57Hex64 "ExpectedPayloadSHA256" $ExpectedPayloadSHA256
if ($ExpectedContentSHA256) {
    Assert-G57Hex64 "ExpectedContentSHA256" $ExpectedContentSHA256
}
if (-not (Test-Path -LiteralPath $harness -PathType Leaf)) {
    throw "g7_measure.ps1 missing"
}
foreach ($parameter in @("ModelPath", "MaxTokens", "ExpectedContentSHA256",
        "SkipMemoryPreflight", "SkipSystemQuiescencePreflight")) {
    if (-not (Test-G57HarnessParameter -ParameterName $parameter)) {
        throw "Harness does not expose -$parameter; refusing to launch model."
    }
}

$resolvedModel = (Resolve-Path -LiteralPath $ModelPath).Path
if ($resolvedModel -like "D:\ds4-models\*") {
    throw "Refusing to read D:\ds4-models per G57 safety handoff"
}
$resolvedPack = ""
if ($PackPath) {
    $resolvedPack = (Resolve-Path -LiteralPath $PackPath).Path
    if ($resolvedPack -like "D:\ds4-models\*") {
        throw "Refusing to read D:\ds4-models per G57 safety handoff"
    }
}

New-Item -ItemType Directory -Force -Path $outdir | Out-Null
$effectiveTag = if ($Tag) {
    $Tag
} else {
    "g57_sparse_bake_" + $BakeId.ToLowerInvariant() + "_functional_safety_n1"
}
$resultPath = Join-Path $outdir ("g7_" + $effectiveTag + "_result.json")
$launchProvenancePath = Join-Path $outdir `
    ("g7_" + $effectiveTag + "_g57_launch_provenance.json")

if ($SummarizeExisting -and
    $ExecutionRunnerSHA256 -notmatch '^[0-9a-fA-F]{64}$') {
    throw "SummarizeExisting requires -ExecutionRunnerSHA256"
}

$provenance = [pscustomobject]@{
    executable_sha256 = Get-G57SHA256 $executable
    harness_sha256 = Get-G57SHA256 $harness
    runtime_monitor_harness_sha256 = Get-G57SHA256 $runtimeMonitor
    ds4_cuda_sha256 = Get-G57SHA256 (Join-Path $root "ds4_cuda.cu")
    ds4_c_sha256 = Get-G57SHA256 (Join-Path $root "ds4.c")
    ds4_server_c_sha256 = Get-G57SHA256 (Join-Path $root "ds4_server.c")
    ds4_bake_c_sha256 = Get-G57SHA256 (Join-Path $root "ds4_bake.c")
    ds4_bake_h_sha256 = Get-G57SHA256 (Join-Path $root "ds4_bake.h")
    build_manifest_sha256 = Get-G57SHA256 $buildManifest
}
$executionRunnerHashAtStart = Get-G57SHA256 $MyInvocation.MyCommand.Path
$executionRunnerHashForRuns = if ($SummarizeExisting) {
    $ExecutionRunnerSHA256.ToLowerInvariant()
} else {
    $executionRunnerHashAtStart
}

if (($Resume -or $SummarizeExisting) -and
    (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
    Write-Host ("[g57] validate existing sparse bake safety tag=" + $effectiveTag)
} elseif ($SummarizeExisting) {
    throw "G57 existing result missing: tag=$effectiveTag"
} else {
    Write-Host ("[g57] validate sparse bake artifact tag=" + $effectiveTag)
    $sparse = Get-G57SparseBakeManifest -Path $resolvedModel
    if ($sparse.mask_sha256 -ne $ExpectedMaskSHA256.ToLowerInvariant()) {
        throw "G57 mask SHA mismatch"
    }
    if ([string]$sparse.manifest.mask_sha256 -ne
        $ExpectedMaskSHA256.ToLowerInvariant()) {
        throw "G57 manifest mask_sha256 mismatch"
    }
    $payloadSha = Get-G57PayloadSHA256 -Path $resolvedModel -Extents $sparse.extents
    if ($payloadSha -ne $ExpectedPayloadSHA256.ToLowerInvariant()) {
        throw "G57 payload SHA mismatch"
    }
    $packSha = ""
    $packVerified = $false
    if ($resolvedPack) {
        $packSha = Get-G57SHA256 $resolvedPack
        if ($packSha -ne $ExpectedPackSHA256.ToLowerInvariant()) {
            throw "G57 pack SHA mismatch"
        }
        $packVerified = $true
    }
    $launchProvenance = [pscustomobject]@{
        schema = "g57_sparse_bake_launch_provenance_v1"
        tag = $effectiveTag
        bake_id = $BakeId
        purpose = "functional-safety-only"
        repeats = 1
        performance_claims = "none"
        temperature = 0
        think = $false
        model_path = $resolvedModel
        pack_path = $resolvedPack
        expected_pack_sha256 = $ExpectedPackSHA256.ToLowerInvariant()
        observed_pack_sha256 = $packSha
        pack_sha256_verified = $packVerified
        expected_mask_sha256 = $ExpectedMaskSHA256.ToLowerInvariant()
        observed_mask_sha256 = $sparse.mask_sha256
        expected_payload_sha256 = $ExpectedPayloadSHA256.ToLowerInvariant()
        observed_payload_sha256 = $payloadSha
        sparse_manifest_sha256 = $sparse.manifest_sha256
        sparse_manifest_crc32 = $sparse.manifest_crc32
        sparse_mask_crc32 = $sparse.mask_crc32
        sparse_source_size = $sparse.source_size
        sparse_physical_size = $sparse.physical_size
        sparse_payload_bytes = [uint64]$sparse.manifest.payload_bytes
        retained_layers =
            @($sparse.manifest.selected_experts_by_layer.PSObject.Properties).Count
        execution_runner_sha256 = $executionRunnerHashAtStart
        executable_sha256 = $provenance.executable_sha256
        harness_sha256 = $provenance.harness_sha256
        runtime_monitor_harness_sha256 =
            $provenance.runtime_monitor_harness_sha256
        ds4_cuda_sha256 = $provenance.ds4_cuda_sha256
        ds4_c_sha256 = $provenance.ds4_c_sha256
        ds4_server_c_sha256 = $provenance.ds4_server_c_sha256
        ds4_bake_c_sha256 = $provenance.ds4_bake_c_sha256
        ds4_bake_h_sha256 = $provenance.ds4_bake_h_sha256
        build_manifest_sha256 = $provenance.build_manifest_sha256
        prompt = $Prompt
        max_tokens = $MaxTokens
        expected_content_sha256 = $ExpectedContentSHA256.ToLowerInvariant()
        created_utc = [DateTime]::UtcNow.ToString("o")
    }
    $launchProvenance | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath $launchProvenancePath -Encoding UTF8

    $args = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $harness,
        "-MaxTokens", ([string]$MaxTokens),
        "-Repeats", "1",
        "-Tag", $effectiveTag,
        "-Prompt", $Prompt,
        "-Context", ([string]$Context),
        "-BudgetGB", "2",
        "-ReserveMB", "1024",
        "-DisableQ8F16Cache",
        "-EmbedRowStaging",
        "-ReapPrefetchThreads", "8",
        "-ModelPath", $resolvedModel,
        "-TimeoutSec", ([string]$TimeoutSec)
    )
    if ($ExpectedContentSHA256) {
        $args += @("-ExpectedContentSHA256", $ExpectedContentSHA256)
    }
    Write-Host ("[g57] start sparse bake functional safety run tag=" +
        $effectiveTag + " n=1 temp=0 nothink=true no-performance-claims")
    & powershell.exe @args | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) {
        throw "G57 sparse bake safety run failed: $effectiveTag"
    }
}

if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
    throw "G57 result missing: tag=$effectiveTag"
}
if (-not (Test-Path -LiteralPath $launchProvenancePath -PathType Leaf)) {
    throw "G57 launch provenance missing: tag=$effectiveTag"
}
$launch = Get-Content -LiteralPath $launchProvenancePath -Raw |
    ConvertFrom-Json
if ($launch.schema -ne "g57_sparse_bake_launch_provenance_v1" -or
    $launch.tag -ne $effectiveTag -or
    $launch.bake_id -ne $BakeId -or
    $launch.purpose -ne "functional-safety-only" -or
    [int]$launch.repeats -ne 1 -or
    $launch.performance_claims -ne "none" -or
    [int]$launch.temperature -ne 0 -or
    [bool]$launch.think -ne $false -or
    $launch.model_path -ne $resolvedModel -or
    $launch.expected_pack_sha256 -ne $ExpectedPackSHA256.ToLowerInvariant() -or
    $launch.expected_mask_sha256 -ne $ExpectedMaskSHA256.ToLowerInvariant() -or
    $launch.observed_mask_sha256 -ne $ExpectedMaskSHA256.ToLowerInvariant() -or
    $launch.expected_payload_sha256 -ne $ExpectedPayloadSHA256.ToLowerInvariant() -or
    $launch.observed_payload_sha256 -ne $ExpectedPayloadSHA256.ToLowerInvariant() -or
    $launch.execution_runner_sha256 -ne $executionRunnerHashForRuns -or
    $launch.executable_sha256 -ne $provenance.executable_sha256 -or
    $launch.harness_sha256 -ne $provenance.harness_sha256 -or
    $launch.runtime_monitor_harness_sha256 -ne
        $provenance.runtime_monitor_harness_sha256) {
    throw "G57 launch provenance mismatch: tag=$effectiveTag"
}
if ($launch.pack_path -and
    ([bool]$launch.pack_sha256_verified -ne $true -or
     $launch.observed_pack_sha256 -ne $ExpectedPackSHA256.ToLowerInvariant())) {
    throw "G57 pack provenance mismatch: tag=$effectiveTag"
}

$r = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
if ($r.tag -ne $effectiveTag -or
    $r.model -ne $resolvedModel -or
    [int]$r.repeats -ne 1 -or
    [bool]$r.warmup -ne $false -or
    [int]$r.requested_max_tokens -ne $MaxTokens -or
    [int]$r.context_requested -ne $Context -or
    [int]$r.server_exit_code -ne 0 -or
    -not $r.outputs_identical -or
    $r.executable_sha256 -ne $provenance.executable_sha256 -or
    $r.harness_sha256 -ne $provenance.harness_sha256 -or
    $r.runtime_monitor_harness_sha256 -ne
        $provenance.runtime_monitor_harness_sha256 -or
    [bool]$r.gpu_resident_routes_requested -ne $false -or
    [bool]$r.no_selected_load -ne $false) {
    throw "G57 result contract mismatch: tag=$effectiveTag"
}
if ($ExpectedContentSHA256 -and
    ($r.expected_content_sha256 -ne $ExpectedContentSHA256.ToLowerInvariant() -or
     $r.results[0].content_sha256 -ne $ExpectedContentSHA256.ToLowerInvariant())) {
    throw "G57 expected output SHA mismatch: tag=$effectiveTag"
}
foreach ($gate in @(
        @("memory_preflight", "memory"),
        @("process_isolation_preflight", "process isolation"),
        @("system_quiescence_preflight", "system quiescence"))) {
    $obj = Get-G57Property -Object $r -Name $gate[0]
    if ($null -eq $obj -or [bool]$obj.ready_to_launch -ne $true) {
        throw ("G57 " + $gate[1] + " gate was not ready_to_launch")
    }
}

$stderrPath = Join-Path $outdir ("g7_" + $effectiveTag + "_stderr.log")
$stdoutPath = Join-Path $outdir ("g7_" + $effectiveTag + "_stdout.log")
$logLines = @()
if (Test-Path -LiteralPath $stderrPath -PathType Leaf) {
    $logLines += Get-Content -LiteralPath $stderrPath
}
if (Test-Path -LiteralPath $stdoutPath -PathType Leaf) {
    $logLines += Get-Content -LiteralPath $stdoutPath
}
Assert-G57LogContains -Lines $logLines `
    -Pattern "sparse bake validated:.*mask_sha256=$($ExpectedMaskSHA256.ToLowerInvariant())" `
    -Label "sparse bake startup validation"
Assert-G57LogContains -Lines $logLines `
    -Pattern "sparse bake mask installed mask_sha256=$($ExpectedMaskSHA256.ToLowerInvariant())" `
    -Label "embedded sparse bake mask installation"
Assert-G57LogContains -Lines $logLines `
    -Pattern "CUDA startup cache excluded .* routed-expert tensors" `
    -Label "selected-only startup cache exclusion"
Assert-G57LogContains -Lines $logLines `
    -Pattern "\[sparse-bake-runtime\] result=guards-installed .*sparse_layers=[1-9][0-9]*" `
    -Label "CUDA sparse bake guards"
Assert-G57LogContains -Lines $logLines `
    -Pattern "\[sparse-bake-runtime\] result=summary route_calls=[1-9][0-9]* route_slots=[1-9][0-9]* rejected=0" `
    -Label "selected-only routed expert validation"
if (@($logLines | Where-Object {
        $_ -match "sparse bake rejected|selected load failed closed|outside the active mask|absent expert|zero-filled"
    }).Count -ne 0) {
    throw "G57 sparse bake safety observed absent-read/fail-closed error log"
}

$rawPath = Join-Path $outdir ("g7_" + $effectiveTag + "_raw_outputs.json")
if (-not (Test-Path -LiteralPath $rawPath -PathType Leaf)) {
    throw "G57 raw output sidecar missing: tag=$effectiveTag"
}
$raw = Get-Content -LiteralPath $rawPath -Raw | ConvertFrom-Json
if ($raw.results.Count -ne 1 -or
    [string]::IsNullOrWhiteSpace([string]$raw.results[0].content) -or
    (-not $ExpectedContentSHA256 -and
     [string]$raw.results[0].content -notmatch
        "(?i)sparse bake functional safety ok")) {
    throw "G57 functional output is empty or incoherent: tag=$effectiveTag"
}

Write-Host ("[g57] PASS functional safety only; no performance claims; tag=" +
    $effectiveTag)
