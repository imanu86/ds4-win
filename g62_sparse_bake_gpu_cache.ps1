# G62 sparse-bake K60 GPU cache runner (PowerShell 5.1, ASCII).
# Candidate-only K60 resident expert cache + GPU route cache against frozen G58 K60.
param(
    [switch]$SafetyOnly,
    [switch]$Resume,
    [switch]$SummarizeExisting,
    [switch]$AuthorizeOnly,
    [string]$PythonPath = "python",
    [ValidateRange(64, 131072)][int]$MaxTokens = 64,
    [ValidateRange(64, 131072)][int]$Context = 256,
    [ValidateRange(1, 86400)][int]$TimeoutSec = 1800,
    [string]$ExecutionRunnerSHA256 = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$harness = Join-Path $root "g7_measure.ps1"
$runtimeMonitor = Join-Path $root "g7_runtime_monitor.ps1"
$outdir = Join-Path $root "g7_runs"
$executable = Join-Path $root "build\Release\ds4_server.exe"
$buildManifest = Join-Path $root "build\Release\g7_build_manifest.json"
$summaryPath = Join-Path $outdir "g62_sparse_bake_gpu_cache_result.json"
$csvPath = Join-Path $outdir "g62_sparse_bake_gpu_cache_runs.csv"
$authPath = Join-Path $outdir "g62_sparse_bake_gpu_cache_authorization.json"
$prompt = "Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document."
$baselineG58K60ContentSHA256 = "ceced6c1b481bb2c6f68bd116c06e554502017a44b40b4e5e6bc9fc5d710edc7"
$expertCacheN = 320
$expertCacheReserveGB = 0.125
$expertCachePolicy = "lru"
$independentProcessCount = if ($SafetyOnly) { 1 } else { 3 }

function Assert-G62Hex64 {
    param([Parameter(Mandatory=$true)][string]$Name,
          [Parameter(Mandatory=$true)][string]$Value)
    if ($Value -notmatch '^[0-9a-fA-F]{64}$') {
        throw "$Name must be a 64-character hexadecimal SHA-256"
    }
}

function Get-G62SHA256 {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "G62 provenance file missing: $Path"
    }
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-G62BytesSHA256 {
    param([Parameter(Mandatory=$true)][byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Get-G62CRC32 {
    param([Parameter(Mandatory=$true)][byte[]]$Bytes)
    [uint64]$crc = 4294967295
    foreach ($value in $Bytes) {
        $crc = $crc -bxor [uint64]$value
        for ($bit = 0; $bit -lt 8; $bit++) {
            if (($crc -band 1) -ne 0) {
                $crc = (($crc -shr 1) -bxor [uint64]3988292384) -band [uint64]4294967295
            } else {
                $crc = $crc -shr 1
            }
        }
    }
    [uint32](($crc -bxor [uint64]4294967295) -band [uint64]4294967295)
}

function Read-G62Exact {
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

function Read-G62UInt32LE {
    param([Parameter(Mandatory=$true)][byte[]]$Bytes,
          [Parameter(Mandatory=$true)][int]$Offset)
    [BitConverter]::ToUInt32($Bytes, $Offset)
}

function Read-G62UInt64LE {
    param([Parameter(Mandatory=$true)][byte[]]$Bytes,
          [Parameter(Mandatory=$true)][int]$Offset)
    [BitConverter]::ToUInt64($Bytes, $Offset)
}

function ConvertTo-G62Extents {
    param([Parameter(Mandatory=$true)][object]$Manifest)
    $rows = @()
    foreach ($extent in @($Manifest.extents)) {
        if ($null -eq $extent) { continue }
        if ($extent -is [System.Array]) {
            if ($extent.Count -ne 2) { throw "Invalid sparse bake extent pair" }
            $rows += [pscustomobject]@{ offset = [uint64]$extent[0]; bytes = [uint64]$extent[1] }
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

function Get-G62SparseBakeManifest {
    param([Parameter(Mandatory=$true)][string]$Path)
    $fs = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        if ($fs.Length -lt 56) { throw "Sparse bake file is too small" }
        $footer = New-Object byte[] 56
        $fs.Seek(-56, [IO.SeekOrigin]::End) | Out-Null
        Read-G62Exact -Stream $fs -Buffer $footer -Count 56
        $magic = [Text.Encoding]::ASCII.GetString($footer, 0, 16).TrimEnd([char]0)
        if ($magic -ne "DS4BAKEFILEv1") {
            throw "ModelPath does not contain a DS4 sparse bake footer"
        }
        $version = Read-G62UInt32LE $footer 16
        $layers = Read-G62UInt32LE $footer 20
        $experts = Read-G62UInt32LE $footer 24
        $maskLen = Read-G62UInt32LE $footer 28
        $sourceSize = Read-G62UInt64LE $footer 32
        $manifestLen = Read-G62UInt64LE $footer 40
        $manifestCrc = Read-G62UInt32LE $footer 48
        $maskCrc = Read-G62UInt32LE $footer 52
        if ($version -ne 1 -or $layers -ne 43 -or $experts -ne 256 -or
            $maskLen -ne (43 * 32) -or $manifestLen -le 0) {
            throw "Sparse bake footer geometry/version is not the DS4 K60 contract"
        }
        $manifestOffset = [int64]$sourceSize
        $maskOffset = [int64]($sourceSize + $manifestLen)
        $expectedFileBytes = [int64]($sourceSize + $manifestLen + $maskLen + 56)
        if ($fs.Length -ne $expectedFileBytes) {
            throw "Sparse bake physical size does not match footer arithmetic"
        }
        $manifestBytes = New-Object byte[] ([int]$manifestLen)
        $fs.Seek($manifestOffset, [IO.SeekOrigin]::Begin) | Out-Null
        Read-G62Exact -Stream $fs -Buffer $manifestBytes -Count ([int]$manifestLen)
        $maskBytes = New-Object byte[] ([int]$maskLen)
        $fs.Seek($maskOffset, [IO.SeekOrigin]::Begin) | Out-Null
        Read-G62Exact -Stream $fs -Buffer $maskBytes -Count ([int]$maskLen)
        $manifest = ([Text.Encoding]::UTF8.GetString($manifestBytes)) | ConvertFrom-Json
        if ($manifest.format -ne "ds4-windows-sparse-bake" -or
            [int]$manifest.version -ne 1 -or
            [uint64]$manifest.source_model_size -ne $sourceSize) {
            throw "Sparse bake manifest identity mismatch"
        }
        if ((Get-G62CRC32 $manifestBytes) -ne $manifestCrc -or
            (Get-G62CRC32 $maskBytes) -ne $maskCrc) {
            throw "Sparse bake footer CRC mismatch"
        }
        [pscustomobject]@{
            manifest = $manifest
            manifest_sha256 = Get-G62BytesSHA256 $manifestBytes
            mask_sha256 = Get-G62BytesSHA256 $maskBytes
            source_size = $sourceSize
            physical_size = [uint64]$fs.Length
            manifest_length = $manifestLen
            mask_length = $maskLen
            manifest_crc32 = $manifestCrc
            mask_crc32 = $maskCrc
            extents = @(ConvertTo-G62Extents -Manifest $manifest)
        }
    } finally {
        $fs.Dispose()
    }
}

function Test-G62HarnessParameter {
    param([Parameter(Mandatory=$true)][string]$ParameterName)
    $content = Get-Content -LiteralPath $harness -Raw
    return ($content -match ("\$" + [regex]::Escape($ParameterName) + "(\s|=|,|\))"))
}

function Get-G62Property {
    param([object]$Object, [string]$Name)
    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) {
        return $null
    }
    $Object.PSObject.Properties[$Name].Value
}

function Convert-G62BytesToGiB {
    param([object]$Value)
    if ($null -eq $Value) { return $null }
    [math]::Round(([double]$Value / 1GB), 6)
}

function Get-G62Mean {
    param([Parameter(Mandatory=$true)][object[]]$Rows,
          [Parameter(Mandatory=$true)][string]$Property)
    $values = @($Rows | ForEach-Object { $_.$Property } |
        Where-Object { $null -ne $_ } | ForEach-Object { [double]$_ })
    if ($values.Count -eq 0) { return $null }
    [math]::Round(($values | Measure-Object -Average).Average, 6)
}

function Get-G62Median {
    param([Parameter(Mandatory=$true)][object[]]$Rows,
          [Parameter(Mandatory=$true)][string]$Property)
    $values = @($Rows | ForEach-Object { $_.$Property } |
        Where-Object { $null -ne $_ } |
        ForEach-Object { [double]$_ } | Sort-Object)
    if ($values.Count -eq 0) { return $null }
    $middle = [int][math]::Floor($values.Count / 2.0)
    if (($values.Count % 2) -eq 1) {
        return [math]::Round($values[$middle], 6)
    }
    [math]::Round(($values[$middle - 1] + $values[$middle]) / 2.0, 6)
}

function Assert-G62LogContains {
    param([Parameter(Mandatory=$true)][string[]]$Lines,
          [Parameter(Mandatory=$true)][string]$Pattern,
          [Parameter(Mandatory=$true)][string]$Label,
          [Parameter(Mandatory=$true)][string]$Tag)
    if (-not @($Lines | Where-Object { $_ -match $Pattern } | Select-Object -First 1)) {
        throw "G62 sparse bake log check failed: tag=$Tag check=$Label"
    }
}

function Read-G62SafetyReceipt {
    param([Parameter(Mandatory=$true)][ValidateSet("K60")][string]$BakeId)
    $lower = $BakeId.ToLowerInvariant()
    $tag = "g57_sparse_bake_" + $lower + "_functional_safety_n1"
    $resultPath = Join-Path $outdir ("g7_" + $tag + "_result.json")
    $launchPath = Join-Path $outdir ("g7_" + $tag + "_g57_launch_provenance.json")
    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        throw "G62 requires existing G57 safety result: $resultPath"
    }
    if (-not (Test-Path -LiteralPath $launchPath -PathType Leaf)) {
        throw "G62 requires existing G57 launch provenance: $launchPath"
    }
    $r = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    $l = Get-Content -LiteralPath $launchPath -Raw | ConvertFrom-Json
    if ($l.schema -ne "g57_sparse_bake_launch_provenance_v3" -or
        $l.bake_id -ne $BakeId -or
        $l.purpose -ne "functional-safety-only" -or
        $l.performance_claims -ne "none" -or
        [int]$l.temperature -ne 0 -or [bool]$l.think -ne $false -or
        [int]$r.server_exit_code -ne 0 -or
        [bool]$r.embedded_bake_mask_allowed -ne $true -or
        [bool]$r.embedded_bake_mask_observed -ne $true -or
        $r.reap_mask_path_observed -ne ("embedded-bake:" + $l.expected_mask_sha256) -or
        [double]$r.dynamic_arena_gib_requested -ne 0.0 -or
        [bool]$r.prefill_mass_wrap_requested -ne $false -or
        [bool]$r.compose_prefill_mass_tiering_requested -ne $false -or
        [int]$r.expert_cache_requested -ne 0 -or
        $r.expert_tiering_requested -ne "off" -or
        [bool]$r.spex_dry_run_requested -ne $false -or
        [string]$r.reap_mask_file_requested -ne "") {
        throw "G62 cannot trust G57 safety receipt: bake=$BakeId"
    }
    foreach ($shaField in @("expected_pack_sha256", "expected_mask_sha256",
            "expected_embedded_mask_sha256", "expected_payload_sha256")) {
        Assert-G62Hex64 $shaField ([string]$l.$shaField)
    }
    [pscustomobject]@{
        bake_id = $BakeId
        safety_tag = $tag
        safety_result_path = $resultPath
        safety_result_sha256 = Get-G62SHA256 $resultPath
        safety_launch_path = $launchPath
        safety_launch_sha256 = Get-G62SHA256 $launchPath
        model_path = [string]$l.model_path
        payload_verifier_path = [string]$l.payload_verifier_path
        payload_verifier_sha256 = [string]$l.payload_verifier_sha256
        expected_pack_sha256 = ([string]$l.expected_pack_sha256).ToLowerInvariant()
        expected_mask_sha256 = ([string]$l.expected_mask_sha256).ToLowerInvariant()
        expected_embedded_mask_sha256 = ([string]$l.expected_embedded_mask_sha256).ToLowerInvariant()
        expected_payload_sha256 = ([string]$l.expected_payload_sha256).ToLowerInvariant()
        expected_manifest_sha256 = ([string]$l.sparse_manifest_sha256).ToLowerInvariant()
        expected_manifest_crc32 = [uint32]$l.sparse_manifest_crc32
        expected_mask_crc32 = [uint32]$l.sparse_mask_crc32
        expected_source_size = [uint64]$l.sparse_source_size
        expected_physical_size = [uint64]$l.sparse_physical_size
        expected_payload_bytes = [uint64]$l.sparse_payload_bytes
        expected_extent_count = [int]$l.payload_verify_extent_count
    }
}

function Authorize-G62Bake {
    param([Parameter(Mandatory=$true)][object]$Receipt,
          [Parameter(Mandatory=$true)][object]$Provenance)
    $resolvedModel = (Resolve-Path -LiteralPath $Receipt.model_path).Path
    if ($resolvedModel -like "D:\ds4-models\*") {
        throw "Refusing to read D:\ds4-models per G57 safety handoff"
    }
    $resolvedVerifier = (Resolve-Path -LiteralPath $Receipt.payload_verifier_path).Path
    if ((Get-G62SHA256 $resolvedVerifier) -ne $Receipt.payload_verifier_sha256) {
        throw "G62 payload verifier SHA mismatch: bake=$($Receipt.bake_id)"
    }
    $sparse = Get-G62SparseBakeManifest -Path $resolvedModel
    if ($sparse.mask_sha256 -ne $Receipt.expected_embedded_mask_sha256 -or
        [string]$sparse.manifest.mask_sha256 -ne $Receipt.expected_mask_sha256 -or
        $sparse.manifest_sha256 -ne $Receipt.expected_manifest_sha256 -or
        [uint32]$sparse.manifest_crc32 -ne $Receipt.expected_manifest_crc32 -or
        [uint32]$sparse.mask_crc32 -ne $Receipt.expected_mask_crc32 -or
        [uint64]$sparse.source_size -ne $Receipt.expected_source_size -or
        [uint64]$sparse.physical_size -ne $Receipt.expected_physical_size -or
        [uint64]$sparse.manifest.payload_bytes -ne $Receipt.expected_payload_bytes) {
        throw "G62 sparse bake receipt mismatch: bake=$($Receipt.bake_id)"
    }
    $payloadVerifyOutput = @(& $PythonPath $resolvedVerifier verify-payload --bake $resolvedModel 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw ("G62 payload verifier failed: " + ($payloadVerifyOutput -join [Environment]::NewLine))
    }
    try {
        $payloadVerify = ($payloadVerifyOutput -join [Environment]::NewLine) | ConvertFrom-Json
    } catch {
        throw ("G62 payload verifier returned invalid JSON: " + ($payloadVerifyOutput -join [Environment]::NewLine))
    }
    if (-not [bool]$payloadVerify.verified -or
        [string]$payloadVerify.expected_sha256 -ne $Receipt.expected_payload_sha256 -or
        [string]$payloadVerify.measured_sha256 -ne $Receipt.expected_payload_sha256 -or
        [uint64]$payloadVerify.payload_bytes -ne $Receipt.expected_payload_bytes -or
        [int]$payloadVerify.extent_count -ne $Receipt.expected_extent_count -or
        [int]$payloadVerify.extent_count -ne @($sparse.extents).Count) {
        throw "G62 payload SHA mismatch: bake=$($Receipt.bake_id)"
    }
    [pscustomobject]@{
        bake_id = $Receipt.bake_id
        authorized_utc = [DateTime]::UtcNow.ToString("o")
        model_path = $resolvedModel
        model_sha256_not_verified = $true
        expected_pack_sha256 = $Receipt.expected_pack_sha256
        expected_mask_sha256 = $Receipt.expected_mask_sha256
        observed_mask_sha256 = [string]$sparse.manifest.mask_sha256
        expected_embedded_mask_sha256 = $Receipt.expected_embedded_mask_sha256
        observed_embedded_mask_sha256 = $sparse.mask_sha256
        expected_payload_sha256 = $Receipt.expected_payload_sha256
        observed_payload_sha256 = [string]$payloadVerify.measured_sha256
        payload_verify_method = "python-hashlib-extents"
        payload_verify_elapsed_seconds = [double]$payloadVerify.elapsed_seconds
        payload_verify_extent_count = [int]$payloadVerify.extent_count
        payload_verifier_path = $resolvedVerifier
        payload_verifier_sha256 = $Receipt.payload_verifier_sha256
        sparse_manifest_sha256 = $sparse.manifest_sha256
        sparse_manifest_crc32 = $sparse.manifest_crc32
        sparse_mask_crc32 = $sparse.mask_crc32
        sparse_source_size = $sparse.source_size
        sparse_physical_size = $sparse.physical_size
        sparse_payload_bytes = [uint64]$sparse.manifest.payload_bytes
        retained_layers = @($sparse.manifest.selected_experts_by_layer.PSObject.Properties).Count
        safety_result_sha256 = $Receipt.safety_result_sha256
        safety_launch_sha256 = $Receipt.safety_launch_sha256
        executable_sha256 = $Provenance.executable_sha256
        harness_sha256 = $Provenance.harness_sha256
        runtime_monitor_harness_sha256 = $Provenance.runtime_monitor_harness_sha256
        ds4_cuda_sha256 = $Provenance.ds4_cuda_sha256
        ds4_c_sha256 = $Provenance.ds4_c_sha256
        ds4_server_c_sha256 = $Provenance.ds4_server_c_sha256
        ds4_bake_c_sha256 = $Provenance.ds4_bake_c_sha256
        ds4_bake_h_sha256 = $Provenance.ds4_bake_h_sha256
        build_manifest_sha256 = $Provenance.build_manifest_sha256
    }
}

function Invoke-G62Run {
    param([Parameter(Mandatory=$true)][object]$Authorization,
          [Parameter(Mandatory=$true)][string]$Tag,
          [Parameter(Mandatory=$true)][int]$OrderIndex,
          [Parameter(Mandatory=$true)][object]$Provenance,
          [Parameter(Mandatory=$true)][string]$ExecutionRunnerHashForRuns)
    $resultPath = Join-Path $outdir ("g7_" + $Tag + "_result.json")
    $launchPath = Join-Path $outdir ("g7_" + $Tag + "_g62_launch_provenance.json")
    if (($Resume -or $SummarizeExisting) -and
        (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        Write-Host ("[G62] validate existing tag=" + $Tag)
    } elseif ($SummarizeExisting) {
        throw "G62 existing result missing: tag=$Tag"
    } else {
        $launch = [pscustomobject]@{
            schema = "g62_sparse_bake_gpu_cache_launch_provenance_v1"
            tag = $Tag
            bake_id = $Authorization.bake_id
            purpose = "candidate-only-gpu-cache"
            order_index = $OrderIndex
            repeats = 1
            independent_process = $true
            prompt = $prompt
            max_tokens = $MaxTokens
            context = $Context
            temperature = 0
            think = $false
            quality_claims = "none"
            baseline_g58_k60_content_sha256 = $baselineG58K60ContentSHA256
            expert_cache_n = $expertCacheN
            expert_cache_reserve_gb = $expertCacheReserveGB
            expert_cache_policy = $expertCachePolicy
            gpu_resident_routes = $true
            allowed_flags = @(
                "ExpertCacheN=320",
                "ExpertCacheReserveGB=0.125",
                "ExpertCachePolicy=lru",
                "GpuResidentRoutes",
                "DisableQ8F16Cache",
                "EmbedRowStaging",
                "ReapPrefetchThreads8")
            forbidden_mechanisms = @(
                "DynamicArena",
                "PrefillMassObserve",
                "PrefillMassWrap",
                "ComposePrefillMassTiering",
                "ExpertTiering",
                "SPEX",
                "external mask",
                "RouteNoDefaultSync",
                "SplitHitMiss")
            model_path = $Authorization.model_path
            expected_pack_sha256 = $Authorization.expected_pack_sha256
            expected_mask_sha256 = $Authorization.expected_mask_sha256
            expected_embedded_mask_sha256 = $Authorization.expected_embedded_mask_sha256
            expected_payload_sha256 = $Authorization.expected_payload_sha256
            authorization = $Authorization
            execution_runner_sha256 = $executionRunnerHashAtStart
            executable_sha256 = $Provenance.executable_sha256
            harness_sha256 = $Provenance.harness_sha256
            runtime_monitor_harness_sha256 = $Provenance.runtime_monitor_harness_sha256
            ds4_cuda_sha256 = $Provenance.ds4_cuda_sha256
            ds4_c_sha256 = $Provenance.ds4_c_sha256
            ds4_server_c_sha256 = $Provenance.ds4_server_c_sha256
            ds4_bake_c_sha256 = $Provenance.ds4_bake_c_sha256
            ds4_bake_h_sha256 = $Provenance.ds4_bake_h_sha256
            build_manifest_sha256 = $Provenance.build_manifest_sha256
            created_utc = [DateTime]::UtcNow.ToString("o")
        }
        $launch | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath $launchPath -Encoding UTF8
        $args = @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $harness,
            "-MaxTokens", ([string]$MaxTokens),
            "-Repeats", "1",
            "-Tag", $Tag,
            "-Prompt", $prompt,
            "-Context", ([string]$Context),
            "-BudgetGB", "2",
            "-ReserveMB", "1024",
            "-DisableQ8F16Cache",
            "-EmbedRowStaging",
            "-ExpertCacheN", ([string]$expertCacheN),
            "-ExpertCacheReserveGB", ($expertCacheReserveGB.ToString("0.###", [Globalization.CultureInfo]::InvariantCulture)),
            "-ExpertCachePolicy", $expertCachePolicy,
            "-GpuResidentRoutes",
            "-AllowEmbeddedBakeMask",
            "-ExpectedEmbeddedBakeMaskSHA256", $Authorization.expected_mask_sha256,
            "-ReapPrefetchThreads", "8",
            "-ExpectedContentSHA256", $baselineG58K60ContentSHA256,
            "-ModelPath", $Authorization.model_path,
            "-TimeoutSec", ([string]$TimeoutSec)
        )
        $argLine = " " + ($args -join " ") + " "
        foreach ($forbiddenArg in @("-DynamicArenaGiB", "-PrefillMassObserve",
                "-PrefillMassWrap", "-ComposePrefillMassTiering",
                "-ExpertTiering", "-RouteNoDefaultSync", "-SplitHitMiss",
                "-SpexDryRun", "-ReapMaskFile")) {
            if ($argLine -match (" " + [regex]::Escape($forbiddenArg) + "(\s|$)")) {
                throw "G62 forbidden mechanism in launch args: $forbiddenArg"
            }
        }
        if ($argLine -notmatch " -ExpertCacheN\s+320(\s|$)" -or
            $argLine -notmatch " -ExpertCacheReserveGB\s+0\.125(\s|$)" -or
            $argLine -notmatch " -ExpertCachePolicy\s+lru(\s|$)" -or
            $argLine -notmatch " -GpuResidentRoutes(\s|$)") {
            throw "G62 required resident GPU cache mechanism missing from launch args"
        }
        Write-Host ("[G62] start tag=" + $Tag + " bake=" + $Authorization.bake_id +
            " n=1 independent temp=0 nothink=true")
        & powershell.exe @args | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) { throw "G62 run failed: $Tag" }
    }

    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        throw "G62 result missing: tag=$Tag"
    }
    if (-not (Test-Path -LiteralPath $launchPath -PathType Leaf)) {
        throw "G62 launch provenance missing: tag=$Tag"
    }
    $launchRead = Get-Content -LiteralPath $launchPath -Raw | ConvertFrom-Json
    if ($launchRead.schema -ne "g62_sparse_bake_gpu_cache_launch_provenance_v1" -or
        $launchRead.tag -ne $Tag -or
        $launchRead.bake_id -ne $Authorization.bake_id -or
        $launchRead.purpose -ne "candidate-only-gpu-cache" -or
        [int]$launchRead.order_index -ne $OrderIndex -or
        [int]$launchRead.repeats -ne 1 -or
        [bool]$launchRead.independent_process -ne $true -or
        $launchRead.prompt -ne $prompt -or
        [int]$launchRead.max_tokens -ne $MaxTokens -or
        [int]$launchRead.context -ne $Context -or
        [int]$launchRead.temperature -ne 0 -or
        [bool]$launchRead.think -ne $false -or
        $launchRead.quality_claims -ne "none" -or
        $launchRead.baseline_g58_k60_content_sha256 -ne $baselineG58K60ContentSHA256 -or
        [int]$launchRead.expert_cache_n -ne $expertCacheN -or
        [double]$launchRead.expert_cache_reserve_gb -ne $expertCacheReserveGB -or
        $launchRead.expert_cache_policy -ne $expertCachePolicy -or
        [bool]$launchRead.gpu_resident_routes -ne $true -or
        $launchRead.model_path -ne $Authorization.model_path -or
        $launchRead.expected_pack_sha256 -ne $Authorization.expected_pack_sha256 -or
        $launchRead.expected_mask_sha256 -ne $Authorization.expected_mask_sha256 -or
        $launchRead.expected_embedded_mask_sha256 -ne $Authorization.expected_embedded_mask_sha256 -or
        $launchRead.expected_payload_sha256 -ne $Authorization.expected_payload_sha256 -or
        $launchRead.execution_runner_sha256 -ne $ExecutionRunnerHashForRuns -or
        $launchRead.executable_sha256 -ne $Provenance.executable_sha256 -or
        $launchRead.harness_sha256 -ne $Provenance.harness_sha256 -or
        $launchRead.runtime_monitor_harness_sha256 -ne $Provenance.runtime_monitor_harness_sha256 -or
        $launchRead.ds4_cuda_sha256 -ne $Provenance.ds4_cuda_sha256 -or
        $launchRead.ds4_c_sha256 -ne $Provenance.ds4_c_sha256 -or
        $launchRead.ds4_server_c_sha256 -ne $Provenance.ds4_server_c_sha256 -or
        $launchRead.ds4_bake_c_sha256 -ne $Provenance.ds4_bake_c_sha256 -or
        $launchRead.ds4_bake_h_sha256 -ne $Provenance.ds4_bake_h_sha256 -or
        $launchRead.build_manifest_sha256 -ne $Provenance.build_manifest_sha256) {
        throw "G62 launch provenance mismatch: tag=$Tag"
    }

    $r = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    $rt = $r.runtime_telemetry
    foreach ($gateName in @("memory_preflight", "process_isolation_preflight", "system_quiescence_preflight")) {
        $gate = Get-G62Property -Object $r -Name $gateName
        if ($null -eq $gate -or [bool]$gate.ready_to_launch -ne $true) {
            throw "G62 preflight gate failed: tag=$Tag gate=$gateName"
        }
    }
    if ($null -eq $r.process_isolation_preflight -or
        [int]$r.process_isolation_preflight.conflict_count -ne 0) {
        throw "G62 process isolation gate failed: tag=$Tag"
    }
    if ($r.tag -ne $Tag -or
        $r.model -ne $Authorization.model_path -or
        $r.prompt -ne $prompt -or
        [int]$r.repeats -ne 1 -or
        [bool]$r.warmup -ne $false -or
        [int]$r.requested_max_tokens -ne $MaxTokens -or
        [int]$r.context_requested -ne $Context -or
        [int]$r.server_exit_code -ne 0 -or
        [bool]$r.outputs_identical -ne $true -or
        $r.executable_sha256 -ne $Provenance.executable_sha256 -or
        $r.harness_sha256 -ne $Provenance.harness_sha256 -or
        $r.runtime_monitor_harness_sha256 -ne $Provenance.runtime_monitor_harness_sha256 -or
        $r.ds4_cuda_sha256 -ne $Provenance.ds4_cuda_sha256 -or
        $r.ds4_c_sha256 -ne $Provenance.ds4_c_sha256 -or
        $r.ds4_server_c_sha256 -ne $Provenance.ds4_server_c_sha256 -or
        $r.build_manifest_sha256 -ne $Provenance.build_manifest_sha256 -or
        [string]$r.expected_content_sha256 -ne $baselineG58K60ContentSHA256 -or
        [string]$r.results[0].content_sha256 -ne $baselineG58K60ContentSHA256 -or
        [bool]$r.gpu_resident_routes_requested -ne $true -or
        [bool]$r.gpu_resident_routes_observed -ne $true -or
        [int64]$r.gpu_resident_routes_calls -le 0 -or
        [int64]$r.gpu_resident_routes_worker_jobs -le 0 -or
        [int64]$r.gpu_resident_routes_errors -ne 0 -or
        [bool]$r.route_no_default_sync_requested -ne $false -or
        [bool]$r.split_hit_miss_requested -ne $false -or
        [bool]$r.no_selected_load -ne $false -or
        [double]$r.dynamic_arena_gib_requested -ne 0.0 -or
        [bool]$r.prefill_mass_observe_requested -ne $false -or
        [bool]$r.prefill_mass_wrap_requested -ne $false -or
        [bool]$r.compose_prefill_mass_tiering_requested -ne $false -or
        [int]$r.expert_cache_requested -ne $expertCacheN -or
        [double]$r.expert_cache_reserve_gb -ne $expertCacheReserveGB -or
        $r.expert_cache_policy -ne $expertCachePolicy -or
        [int]$r.expert_cache_capacity -ne $expertCacheN -or
        [int]$r.gpu_resident_routes_cache_count -le 0 -or
        [int64]$r.gpu_resident_routes_cache_calls -le 0 -or
        ([int64]$r.gpu_resident_routes_cache_hits + [int64]$r.gpu_resident_routes_cache_misses) -le 0 -or
        [int64]$r.gpu_resident_routes_cache_direct_loads -lt 0 -or
        [int64]$r.gpu_resident_routes_cache_evictions -lt 0 -or
        [int64]$r.gpu_resident_routes_cache_admissions -lt 0 -or
        $r.expert_tiering_requested -ne "off" -or
        [bool]$r.spex_dry_run_requested -ne $false -or
        [string]$r.reap_mask_file_requested -ne "" -or
        [bool]$r.q8_f16_cache_disabled -ne $true -or
        [bool]$r.embed_row_staging_requested -ne $true -or
        [int]$r.reap_prefetch_threads_requested -ne 8 -or
        [bool]$r.embedded_bake_mask_allowed -ne $true -or
        [bool]$r.embedded_bake_mask_observed -ne $true -or
        $r.expected_embedded_bake_mask_sha256 -ne $Authorization.expected_mask_sha256 -or
        $r.reap_mask_path_observed -ne ("embedded-bake:" + $Authorization.expected_mask_sha256) -or
        [bool]$r.prefill_mass_observer_armed -ne $false -or
        [bool]$r.prefill_mass_finalized -ne $false -or
        [bool]$r.prefill_mass_wrap_observed -ne $false -or
        [int]$r.prefill_mass_wrap_event_count -ne 0 -or
        [bool]$r.prefill_mass_compose_observed -ne $false -or
        [int]$r.prefill_mass_compose_event_count -ne 0 -or
        [bool]$r.dynamic_arena_final_observed -ne $false -or
        [int64]$r.dynamic_arena_final_hits -ne 0 -or
        [int64]$r.dynamic_arena_final_misses -ne 0 -or
        [int64]$r.dynamic_arena_final_fatal -ne 0 -or
        $r.results.Count -ne 1 -or
        [string]::IsNullOrWhiteSpace([string]$r.results[0].content) -or
        [double]$r.server_decode_mean_tokens_per_second -le 0.0 -or
        [double]$r.server_prefill_ttft_mean_seconds -le 0.0 -or
        [double]$r.load_seconds -le 0.0 -or
        $null -eq $rt -or
        [bool]$rt.contamination_abort_observed -ne $false -or
        $null -eq $rt.aggregate_disk_read_bytes_estimated -or
        $null -eq $rt.process_working_set_peak_bytes -or
        $null -eq $rt.gpu_process_dedicated_peak_bytes -or
        $null -eq $rt.vram_used_peak_mib) {
        throw "G62 result contract mismatch: tag=$Tag"
    }

    $rawPath = Join-Path $outdir ("g7_" + $Tag + "_raw_outputs.json")
    if (-not (Test-Path -LiteralPath $rawPath -PathType Leaf)) {
        throw "G62 raw output sidecar missing: tag=$Tag"
    }
    $raw = Get-Content -LiteralPath $rawPath -Raw | ConvertFrom-Json
    if ($raw.results.Count -ne 1 -or
        [string]::IsNullOrWhiteSpace([string]$raw.results[0].content)) {
        throw "G62 raw output empty: tag=$Tag"
    }

    $stderrPath = Join-Path $outdir ("g7_" + $Tag + "_stderr.log")
    $stdoutPath = Join-Path $outdir ("g7_" + $Tag + "_stdout.log")
    $logLines = @()
    if (Test-Path -LiteralPath $stderrPath -PathType Leaf) {
        $logLines += Get-Content -LiteralPath $stderrPath
    }
    if (Test-Path -LiteralPath $stdoutPath -PathType Leaf) {
        $logLines += Get-Content -LiteralPath $stdoutPath
    }
    Assert-G62LogContains -Lines $logLines `
        -Pattern "sparse bake validated:.*mask_sha256=$($Authorization.expected_mask_sha256)" `
        -Label "sparse bake startup validation" -Tag $Tag
    Assert-G62LogContains -Lines $logLines `
        -Pattern "sparse bake mask installed mask_sha256=$($Authorization.expected_mask_sha256)" `
        -Label "embedded sparse bake mask installation" -Tag $Tag
    Assert-G62LogContains -Lines $logLines `
        -Pattern "CUDA startup cache excluded .* routed-expert tensors" `
        -Label "selected-only startup cache exclusion" -Tag $Tag
    Assert-G62LogContains -Lines $logLines `
        -Pattern "\[sparse-bake-runtime\] result=guards-installed .*sparse_layers=[1-9][0-9]*" `
        -Label "CUDA sparse bake guards" -Tag $Tag
    Assert-G62LogContains -Lines $logLines `
        -Pattern "\[sparse-bake-runtime\] result=summary route_calls=[1-9][0-9]* route_slots=[1-9][0-9]* rejected=0" `
        -Label "selected-only route validation" -Tag $Tag
    Assert-G62LogContains -Lines $logLines `
        -Pattern "resident expert cache ready: [1-9][0-9]*/$expertCacheN experts" `
        -Label "resident expert cache ready" -Tag $Tag
    Assert-G62LogContains -Lines $logLines `
        -Pattern "\[gpu-resident-routes\] final calls=[1-9][0-9]* split_calls=0 all_hit=[0-9]+ worker_jobs=[1-9][0-9]* miss_experts=[0-9]+ errors=0.*cache_count=[1-9][0-9]* cache_calls=[1-9][0-9]* cache_hits=[0-9]+ cache_misses=[0-9]+ cache_admissions=[0-9]+ cache_evictions=[0-9]+ direct_loads=[0-9]+" `
        -Label "GPU resident route final counters" -Tag $Tag
    if (@($logLines | Where-Object {
            $_ -match "sparse bake rejected|selected load failed closed|outside the active mask|absent expert|zero-filled|SPEX|external REAP mask|full-range copy|DynamicArena|PrefillMassObserve|PrefillMassWrap|ComposePrefillMassTiering|RouteNoDefaultSync|SplitHitMiss|ExpertTiering"
        }).Count -ne 0) {
        throw "G62 sparse bake safety observed forbidden runtime log: tag=$Tag"
    }

    [pscustomobject]@{
        tag = $Tag
        bake_id = $Authorization.bake_id
        order_index = $OrderIndex
        result_path = $resultPath
        result_sha256 = Get-G62SHA256 $resultPath
        raw_outputs_path = $rawPath
        raw_outputs_sha256 = Get-G62SHA256 $rawPath
        launch_provenance_path = $launchPath
        launch_provenance_sha256 = Get-G62SHA256 $launchPath
        execution_runner_sha256 = $launchRead.execution_runner_sha256
        model = $r.model
        model_bytes = $r.model_bytes
        model_last_write_utc = $r.model_last_write_utc
        head = $r.head
        build_worktree_dirty = $r.build_manifest_worktree_dirty_at_build_start
        executable_sha256 = $r.executable_sha256
        harness_sha256 = $r.harness_sha256
        runtime_monitor_harness_sha256 = $r.runtime_monitor_harness_sha256
        ds4_cuda_sha256 = $r.ds4_cuda_sha256
        ds4_c_sha256 = $r.ds4_c_sha256
        ds4_server_c_sha256 = $r.ds4_server_c_sha256
        build_manifest_sha256 = $r.build_manifest_sha256
        build_input_fingerprint_sha256 = $r.build_manifest_input_fingerprint_sha256
        server_exit_code = [int]$r.server_exit_code
        content_sha256 = [string]$r.results[0].content_sha256
        baseline_g58_k60_content_sha256 = $baselineG58K60ContentSHA256
        output_hash_matches_baseline = ([string]$r.results[0].content_sha256 -eq $baselineG58K60ContentSHA256)
        completion_tokens = [int]$r.results[0].completion_tokens
        wall_seconds = [double]$r.results[0].seconds
        load_seconds = [double]$r.load_seconds
        startup_seconds = [double]$r.load_seconds
        ttft_seconds = [double]$r.server_prefill_ttft_mean_seconds
        decode_tokens_per_second = [double]$r.server_decode_mean_tokens_per_second
        decode_seconds = [double]$r.server_runs[0].server_decode_seconds
        server_total_seconds = [double]$r.server_runs[0].server_total_seconds
        finish_reason = [string]$r.server_runs[0].finish_reason
        runtime_samples = [int]$rt.samples
        runtime_elapsed_seconds = [double]$rt.elapsed_seconds
        process_isolation_conflict_count = [int]$r.process_isolation_preflight.conflict_count
        windows_available_min_gib = Convert-G62BytesToGiB $rt.windows_available_min_bytes
        working_set_peak_gib = Convert-G62BytesToGiB $rt.process_working_set_peak_bytes
        private_peak_gib = Convert-G62BytesToGiB $rt.process_private_peak_bytes
        gpu_shared_peak_gib = Convert-G62BytesToGiB $rt.gpu_process_shared_peak_bytes
        gpu_dedicated_peak_gib = Convert-G62BytesToGiB $rt.gpu_process_dedicated_peak_bytes
        vram_used_peak_mib = Get-G62Property $rt "vram_used_peak_mib"
        gpu_utilization_median_percent = Get-G62Property $rt "gpu_utilization_median_percent"
        gpu_utilization_peak_percent = Get-G62Property $rt "gpu_utilization_peak_percent"
        power_median_watts = Get-G62Property $rt "power_median_watts"
        aggregate_disk_read_gib = Convert-G62BytesToGiB $rt.aggregate_disk_read_bytes_estimated
        aggregate_disk_read_mib_per_second = Get-G62Property $rt "aggregate_disk_read_mib_per_second"
        aggregate_disk_read_throughput_mib_per_second = Get-G62Property $rt "aggregate_disk_read_throughput_mib_per_second"
        aggregate_disk_queue_length_median = Get-G62Property $rt "aggregate_disk_queue_length_median"
        aggregate_disk_queue_length_peak = Get-G62Property $rt "aggregate_disk_queue_length_peak"
        process_read_gib = Convert-G62BytesToGiB $rt.win32_process_read_transfer_delta_bytes
        process_write_gib = Convert-G62BytesToGiB $rt.win32_process_write_transfer_delta_bytes
        page_fault_delta = Get-G62Property $rt "page_fault_delta"
        mmap_backed_file_io_measured = Get-G62Property $rt "mmap_backed_file_io_measured"
        contamination_abort_observed = [bool]$rt.contamination_abort_observed
        expert_cache_requested = [int]$r.expert_cache_requested
        expert_cache_reserve_gb = [double]$r.expert_cache_reserve_gb
        expert_cache_policy = [string]$r.expert_cache_policy
        expert_cache_calls = [int64]$r.expert_cache_calls
        expert_cache_capacity = [int]$r.expert_cache_capacity
        expert_cache_count = [int]$r.expert_cache_count
        expert_cache_hits = [int64]$r.expert_cache_hits
        expert_cache_misses = [int64]$r.expert_cache_misses
        expert_cache_admissions = [int64]$r.expert_cache_admissions
        expert_cache_evictions = [int64]$r.expert_cache_evictions
        expert_cache_direct_loads = [int64]$r.expert_cache_direct_loads
        gpu_resident_routes_requested = [bool]$r.gpu_resident_routes_requested
        gpu_resident_routes_observed = [bool]$r.gpu_resident_routes_observed
        gpu_resident_routes_calls = [int64]$r.gpu_resident_routes_calls
        gpu_resident_routes_worker_jobs = [int64]$r.gpu_resident_routes_worker_jobs
        gpu_resident_routes_miss_experts = [int64]$r.gpu_resident_routes_miss_experts
        gpu_resident_routes_errors = [int64]$r.gpu_resident_routes_errors
        gpu_resident_routes_worker_ms_per_job = Get-G62Property $r "gpu_resident_routes_worker_ms_per_job"
        gpu_resident_routes_resolve_ms_per_call = Get-G62Property $r "gpu_resident_routes_resolve_ms_per_call"
        gpu_resident_routes_wait_ms_per_call = Get-G62Property $r "gpu_resident_routes_wait_ms_per_call"
        gpu_resident_routes_queries = Get-G62Property $r "gpu_resident_routes_queries"
        gpu_resident_routes_default_sync_calls = Get-G62Property $r "gpu_resident_routes_default_sync_calls"
        gpu_resident_routes_no_default_sync_calls = Get-G62Property $r "gpu_resident_routes_no_default_sync_calls"
        gpu_resident_routes_cache_count = [int]$r.gpu_resident_routes_cache_count
        gpu_resident_routes_cache_calls = [int64]$r.gpu_resident_routes_cache_calls
        gpu_resident_routes_cache_hits = [int64]$r.gpu_resident_routes_cache_hits
        gpu_resident_routes_cache_misses = [int64]$r.gpu_resident_routes_cache_misses
        gpu_resident_routes_cache_admissions = [int64]$r.gpu_resident_routes_cache_admissions
        gpu_resident_routes_cache_evictions = [int64]$r.gpu_resident_routes_cache_evictions
        gpu_resident_routes_cache_direct_loads = [int64]$r.gpu_resident_routes_cache_direct_loads
        expected_mask_sha256 = $Authorization.expected_mask_sha256
        expected_embedded_mask_sha256 = $Authorization.expected_embedded_mask_sha256
        expected_payload_sha256 = $Authorization.expected_payload_sha256
        sparse_manifest_sha256 = $Authorization.sparse_manifest_sha256
        sparse_manifest_crc32 = $Authorization.sparse_manifest_crc32
        sparse_mask_crc32 = $Authorization.sparse_mask_crc32
    }
}

New-Item -ItemType Directory -Force -Path $outdir | Out-Null
if ($SummarizeExisting -and $ExecutionRunnerSHA256 -notmatch '^[0-9a-fA-F]{64}$') {
    throw "SummarizeExisting requires -ExecutionRunnerSHA256"
}
if ($AuthorizeOnly -and $SummarizeExisting) {
    throw "AuthorizeOnly cannot be combined with SummarizeExisting"
}
foreach ($parameter in @("ModelPath", "MaxTokens", "SkipMemoryPreflight",
        "SkipSystemQuiescencePreflight", "AllowEmbeddedBakeMask",
        "ExpectedEmbeddedBakeMaskSHA256", "ExpertCacheN",
        "ExpertCacheReserveGB", "ExpertCachePolicy", "GpuResidentRoutes",
        "DisableQ8F16Cache", "EmbedRowStaging",
        "ReapPrefetchThreads", "ExpectedContentSHA256")) {
    if (-not (Test-G62HarnessParameter -ParameterName $parameter)) {
        throw "Harness does not expose -$parameter; refusing to launch model."
    }
}

$provenance = [pscustomobject]@{
    executable_sha256 = Get-G62SHA256 $executable
    harness_sha256 = Get-G62SHA256 $harness
    runtime_monitor_harness_sha256 = Get-G62SHA256 $runtimeMonitor
    ds4_cuda_sha256 = Get-G62SHA256 (Join-Path $root "ds4_cuda.cu")
    ds4_c_sha256 = Get-G62SHA256 (Join-Path $root "ds4.c")
    ds4_server_c_sha256 = Get-G62SHA256 (Join-Path $root "ds4_server.c")
    ds4_bake_c_sha256 = Get-G62SHA256 (Join-Path $root "ds4_bake.c")
    ds4_bake_h_sha256 = Get-G62SHA256 (Join-Path $root "ds4_bake.h")
    build_manifest_sha256 = Get-G62SHA256 $buildManifest
}
$executionRunnerHashAtStart = Get-G62SHA256 $MyInvocation.MyCommand.Path
$executionRunnerHashForRuns = if ($SummarizeExisting) {
    $ExecutionRunnerSHA256.ToLowerInvariant()
} else {
    $executionRunnerHashAtStart
}

$receipts = @(
    (Read-G62SafetyReceipt -BakeId "K60")
)
$authorizations = @()
$reuseAuthorization = ($SummarizeExisting -or $Resume) -and
    (Test-Path -LiteralPath $authPath -PathType Leaf)
if ($reuseAuthorization) {
    if (-not (Test-Path -LiteralPath $authPath -PathType Leaf)) {
        throw "G62 authorization cache missing for summary: $authPath"
    }
    $authCache = Get-Content -LiteralPath $authPath -Raw | ConvertFrom-Json
    if ($authCache.schema -ne "g62_sparse_bake_gpu_cache_authorization_v1" -or
        $authCache.prompt -ne $prompt -or
        [int]$authCache.max_tokens -ne $MaxTokens -or
        [int]$authCache.context -ne $Context -or
        [int]$authCache.temperature -ne 0 -or
        [bool]$authCache.think -ne $false -or
        $authCache.execution_runner_sha256 -ne $executionRunnerHashForRuns -or
        $authCache.provenance.executable_sha256 -ne $provenance.executable_sha256 -or
        $authCache.provenance.harness_sha256 -ne $provenance.harness_sha256 -or
        $authCache.provenance.runtime_monitor_harness_sha256 -ne $provenance.runtime_monitor_harness_sha256 -or
        $authCache.provenance.ds4_cuda_sha256 -ne $provenance.ds4_cuda_sha256 -or
        $authCache.provenance.ds4_c_sha256 -ne $provenance.ds4_c_sha256 -or
        $authCache.provenance.ds4_server_c_sha256 -ne $provenance.ds4_server_c_sha256 -or
        $authCache.provenance.ds4_bake_c_sha256 -ne $provenance.ds4_bake_c_sha256 -or
        $authCache.provenance.ds4_bake_h_sha256 -ne $provenance.ds4_bake_h_sha256 -or
        $authCache.provenance.build_manifest_sha256 -ne $provenance.build_manifest_sha256) {
        throw "G62 authorization cache schema mismatch"
    }
    $authorizations = @($authCache.bakes)
} elseif ($SummarizeExisting) {
    throw "G62 authorization cache missing for summary: $authPath"
} else {
    foreach ($receipt in $receipts) {
        Write-Host ("[G62] authorize bake=" + $receipt.bake_id +
            " using G57 safety receipt and payload verifier")
        $authorizations += Authorize-G62Bake -Receipt $receipt -Provenance $provenance
    }
    $auth = [pscustomobject]@{
        schema = "g62_sparse_bake_gpu_cache_authorization_v1"
        created_utc = [DateTime]::UtcNow.ToString("o")
        purpose = "verify K60 payload/hash/manifest/embedded-mask once before GPU cache candidate runs"
        prompt = $prompt
        max_tokens = $MaxTokens
        context = $Context
        temperature = 0
        think = $false
        quality_claims = "none"
        execution_runner_sha256 = $executionRunnerHashAtStart
        provenance = $provenance
        bakes = $authorizations
    }
    $auth | ConvertTo-Json -Depth 10 |
        Set-Content -LiteralPath $authPath -Encoding UTF8
}
if ($authorizations.Count -ne 1) {
    throw "G62 authorization requires exactly K60"
}
$authByBake = @{}
foreach ($authBake in $authorizations) {
    $authByBake[[string]$authBake.bake_id] = $authBake
}
foreach ($bakeId in @("K60")) {
    if (-not $authByBake.ContainsKey($bakeId)) {
        throw "G62 authorization missing bake=$bakeId"
    }
}
if ($AuthorizeOnly) {
    Write-Host ("[G62] authorization complete: " + $authPath)
    return
}

$suffixes = if ($independentProcessCount -eq 1) { @("safety") } else { @("a", "b", "c") }
$plan = @($suffixes | ForEach-Object { @{ Bake = "K60"; Suffix = $_ } })
$runs = @()
$index = 0
foreach ($item in $plan) {
    $index += 1
    $tag = "g62_sparse_bake_" + ([string]$item.Bake).ToLowerInvariant() +
        "_gpu_cache_" + $item.Suffix
    $runs += Invoke-G62Run -Authorization $authByBake[[string]$item.Bake] `
        -Tag $tag -OrderIndex $index -Provenance $provenance `
        -ExecutionRunnerHashForRuns $executionRunnerHashForRuns
}

foreach ($bakeId in @("K60")) {
    $rows = @($runs | Where-Object { $_.bake_id -eq $bakeId })
    if ($rows.Count -ne $independentProcessCount) { throw "G62 replication mismatch: bake=$bakeId" }
    $hashes = @($rows | ForEach-Object { $_.content_sha256 } | Select-Object -Unique)
    if ($hashes.Count -ne 1) {
        throw "G62 output not deterministic within bake: bake=$bakeId"
    }
    if ($hashes[0] -ne $baselineG58K60ContentSHA256) {
        throw "G62 output hash differs from frozen G58 K60 baseline"
    }
}
$order = @($runs | ForEach-Object { $_.bake_id })
if (($order -join ",") -ne (@(1..$independentProcessCount | ForEach-Object { "K60" }) -join ",")) {
    throw "G62 order contract mismatch"
}

$armSummary = @()
foreach ($bakeId in @("K60")) {
    $rows = @($runs | Where-Object { $_.bake_id -eq $bakeId })
    $armSummary += [pscustomobject]@{
        bake_id = $bakeId
        independent_processes = $rows.Count
        content_sha256 = [string]$rows[0].content_sha256
        load_seconds_mean = Get-G62Mean $rows "load_seconds"
        load_seconds_median = Get-G62Median $rows "load_seconds"
        startup_seconds_mean = Get-G62Mean $rows "startup_seconds"
        ttft_seconds_mean = Get-G62Mean $rows "ttft_seconds"
        ttft_seconds_median = Get-G62Median $rows "ttft_seconds"
        decode_tokens_per_second_mean = Get-G62Mean $rows "decode_tokens_per_second"
        decode_tokens_per_second_median = Get-G62Median $rows "decode_tokens_per_second"
        decode_seconds_mean = Get-G62Mean $rows "decode_seconds"
        wall_seconds_mean = Get-G62Mean $rows "wall_seconds"
        windows_available_min_gib_mean = Get-G62Mean $rows "windows_available_min_gib"
        working_set_peak_gib_mean = Get-G62Mean $rows "working_set_peak_gib"
        private_peak_gib_mean = Get-G62Mean $rows "private_peak_gib"
        gpu_shared_peak_gib_mean = Get-G62Mean $rows "gpu_shared_peak_gib"
        gpu_dedicated_peak_gib_mean = Get-G62Mean $rows "gpu_dedicated_peak_gib"
        vram_used_peak_mib_mean = Get-G62Mean $rows "vram_used_peak_mib"
        gpu_utilization_median_percent_mean = Get-G62Mean $rows "gpu_utilization_median_percent"
        gpu_utilization_peak_percent_mean = Get-G62Mean $rows "gpu_utilization_peak_percent"
        aggregate_disk_read_gib_mean = Get-G62Mean $rows "aggregate_disk_read_gib"
        aggregate_disk_read_mib_per_second_mean = Get-G62Mean $rows "aggregate_disk_read_mib_per_second"
        aggregate_disk_queue_length_peak_mean = Get-G62Mean $rows "aggregate_disk_queue_length_peak"
        process_read_gib_mean = Get-G62Mean $rows "process_read_gib"
        page_fault_delta_mean = Get-G62Mean $rows "page_fault_delta"
        expert_cache_hits_mean = Get-G62Mean $rows "gpu_resident_routes_cache_hits"
        expert_cache_misses_mean = Get-G62Mean $rows "gpu_resident_routes_cache_misses"
        expert_cache_evictions_mean = Get-G62Mean $rows "gpu_resident_routes_cache_evictions"
        expert_cache_direct_loads_mean = Get-G62Mean $rows "gpu_resident_routes_cache_direct_loads"
        gpu_resident_routes_worker_jobs_mean = Get-G62Mean $rows "gpu_resident_routes_worker_jobs"
        gpu_resident_routes_miss_experts_mean = Get-G62Mean $rows "gpu_resident_routes_miss_experts"
        gpu_resident_routes_wait_ms_per_call_mean = Get-G62Mean $rows "gpu_resident_routes_wait_ms_per_call"
        contamination_abort_observed_count =
            @($rows | Where-Object { $_.contamination_abort_observed }).Count
    }
}

$summary = [pscustomobject]@{
    schema = "g62_sparse_bake_gpu_cache_v1"
    question = "K60 sparse-bake candidate-only resident expert cache + GPU route cache versus frozen G58 K60 hash."
    safety_only = [bool]$SafetyOnly
    summarized_existing_results = [bool]$SummarizeExisting
    authorization_path = $authPath
    authorization_sha256 = Get-G62SHA256 $authPath
    csv_path = $csvPath
    prompt = $prompt
    context = $Context
    max_tokens = $MaxTokens
    temperature = 0
    think = $false
    quality_claims = "none; do not declare L0-L3 quality from 64-token runs"
    baseline = [pscustomobject]@{
        source = "frozen G58 K60"
        content_sha256 = $baselineG58K60ContentSHA256
    }
    candidate = [pscustomobject]@{
        bake_id = "K60"
        expert_cache_n = $expertCacheN
        expert_cache_reserve_gb = $expertCacheReserveGB
        expert_cache_policy = $expertCachePolicy
        gpu_resident_routes = $true
        allowed_flags = @(
            "ExpertCacheN=320",
            "ExpertCacheReserveGB=0.125",
            "ExpertCachePolicy=lru",
            "GpuResidentRoutes",
            "DisableQ8F16Cache",
            "EmbedRowStaging",
            "ReapPrefetchThreads8")
    }
    independent_processes_per_bake = $independentProcessCount
    within_process_repeats = 1
    order_contract = "K60 candidate only; safety n=1 or performance n=3; every output must equal frozen G58 K60"
    order = @($runs | ForEach-Object { $_.tag })
    order_bake = @($runs | ForEach-Object { $_.bake_id })
    required_guards = @(
        "embedded sparse bake mask",
        "embedded mask observed/path/hash match",
        "selected-only startup cache exclusion",
        "CUDA sparse bake guards installed",
        "route_calls and route_slots positive",
        "rejected=0",
        "gpu_resident_routes requested and observed",
        "gpu route calls and worker jobs positive",
        "gpu route worker errors=0",
        "expert cache requested/capacity 320",
        "GPU-route cache count positive",
        "direct GPU-route cache hits/misses/direct telemetry coherent",
        "output hash equals frozen G58 K60",
        "process isolation conflict_count=0",
        "VRAM peak metric present for baseline comparison",
        "no absent expert, zero-filled, selected-load fail-closed, or external mask logs")
    excluded_features = @(
        "DynamicArena", "PrefillMassObserve", "PrefillMassWrap",
        "ComposePrefillMassTiering", "ExpertTiering", "SPEX",
        "external REAP mask", "RouteNoDefaultSync", "SplitHitMiss",
        "full model copy", "tiering cache")
    metric_limitations = @(
        "startup_seconds is load_seconds from g7_measure because no separate startup field exists",
        "mmap-backed file IO is reported only when runtime_telemetry exposes it",
        "SSD bytes are measured and reported, not required to be zero",
        "model SHA is not claimed because G57 receipts record source_model_sha256 as null")
    execution_runner_sha256 = $executionRunnerHashForRuns
    summary_runner_sha256 = Get-G62SHA256 $MyInvocation.MyCommand.Path
    provenance = $provenance
    authorizations = $authorizations
    runs = $runs
    arm_summary = $armSummary
}
$runs | Select-Object tag,bake_id,order_index,content_sha256,output_hash_matches_baseline,
    load_seconds,ttft_seconds,decode_tokens_per_second,wall_seconds,
    aggregate_disk_read_gib,process_read_gib,page_fault_delta,
    expert_cache_requested,expert_cache_capacity,expert_cache_count,
    expert_cache_hits,expert_cache_misses,expert_cache_evictions,
    expert_cache_direct_loads,gpu_resident_routes_calls,
    gpu_resident_routes_worker_jobs,gpu_resident_routes_miss_experts,
    gpu_resident_routes_wait_ms_per_call,gpu_resident_routes_cache_count,
    gpu_resident_routes_cache_calls,gpu_resident_routes_cache_hits,
    gpu_resident_routes_cache_misses,gpu_resident_routes_cache_admissions,
    gpu_resident_routes_cache_evictions,gpu_resident_routes_cache_direct_loads,
    gpu_dedicated_peak_gib,vram_used_peak_mib,
    process_isolation_conflict_count,contamination_abort_observed |
    Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding ASCII
$summary | ConvertTo-Json -Depth 10 |
    Set-Content -LiteralPath $summaryPath -Encoding UTF8
foreach ($arm in $armSummary) {
    Write-Host ("[G62] bake=" + $arm.bake_id +
        " n=" + $arm.independent_processes +
        " load_med=" + $arm.load_seconds_median +
        " ttft_med=" + $arm.ttft_seconds_median +
        " decode_tps_med=" + $arm.decode_tokens_per_second_median +
        " disk_read_gib_mean=" + $arm.aggregate_disk_read_gib_mean +
        " gpu_dedicated_peak_gib_mean=" + $arm.gpu_dedicated_peak_gib_mean)
}
Write-Host ("[G62] matrix complete: " + $summaryPath)
