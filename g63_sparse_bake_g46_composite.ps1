# G63 sparse-bake K60 G46 composite runner (PowerShell 5.1, ASCII).
# Candidate-only K60 sparse bake + measured G46 composite with frozen G63 exactness.
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
$summaryPath = Join-Path $outdir "g63_sparse_bake_g46_composite_result.json"
$csvPath = Join-Path $outdir "g63_sparse_bake_g46_composite_runs.csv"
$authPath = Join-Path $outdir "g63_sparse_bake_g46_composite_authorization.json"
$prompt = "Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document."
$baselineG58K60ContentSHA256 = "ceced6c1b481bb2c6f68bd116c06e554502017a44b40b4e5e6bc9fc5d710edc7"
$expectedG63K60ContentSHA256 = "4aaf0f0813f4cb15ac21a88f195f4f7d2c2af797e81524935e22eea60603c6b1"
$expertCacheN = 320
$expertCacheReserveGB = 0.125
$expertCachePolicy = "lru"
$dynamicArenaGiB = 30.0
$expertTiering = "enforce"
$expertTierPolicy = "mass-lfru"
$expertTierClockCalls = 430
$expertTierReplacementBudget = 16
$expertTierMinFrequency = 3
$expertTierHysteresis = 1.25
$independentProcessCount = if ($SafetyOnly) { 1 } else { 3 }

function Assert-G63Hex64 {
    param([Parameter(Mandatory=$true)][string]$Name,
          [Parameter(Mandatory=$true)][string]$Value)
    if ($Value -notmatch '^[0-9a-fA-F]{64}$') {
        throw "$Name must be a 64-character hexadecimal SHA-256"
    }
}

function Get-G63SHA256 {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "G63 provenance file missing: $Path"
    }
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-G63BytesSHA256 {
    param([Parameter(Mandatory=$true)][byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Get-G63CRC32 {
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

function Read-G63Exact {
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

function Read-G63UInt32LE {
    param([Parameter(Mandatory=$true)][byte[]]$Bytes,
          [Parameter(Mandatory=$true)][int]$Offset)
    [BitConverter]::ToUInt32($Bytes, $Offset)
}

function Read-G63UInt64LE {
    param([Parameter(Mandatory=$true)][byte[]]$Bytes,
          [Parameter(Mandatory=$true)][int]$Offset)
    [BitConverter]::ToUInt64($Bytes, $Offset)
}

function ConvertTo-G63Extents {
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

function Get-G63SparseBakeManifest {
    param([Parameter(Mandatory=$true)][string]$Path)
    $fs = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        if ($fs.Length -lt 56) { throw "Sparse bake file is too small" }
        $footer = New-Object byte[] 56
        $fs.Seek(-56, [IO.SeekOrigin]::End) | Out-Null
        Read-G63Exact -Stream $fs -Buffer $footer -Count 56
        $magic = [Text.Encoding]::ASCII.GetString($footer, 0, 16).TrimEnd([char]0)
        if ($magic -ne "DS4BAKEFILEv1") {
            throw "ModelPath does not contain a DS4 sparse bake footer"
        }
        $version = Read-G63UInt32LE $footer 16
        $layers = Read-G63UInt32LE $footer 20
        $experts = Read-G63UInt32LE $footer 24
        $maskLen = Read-G63UInt32LE $footer 28
        $sourceSize = Read-G63UInt64LE $footer 32
        $manifestLen = Read-G63UInt64LE $footer 40
        $manifestCrc = Read-G63UInt32LE $footer 48
        $maskCrc = Read-G63UInt32LE $footer 52
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
        Read-G63Exact -Stream $fs -Buffer $manifestBytes -Count ([int]$manifestLen)
        $maskBytes = New-Object byte[] ([int]$maskLen)
        $fs.Seek($maskOffset, [IO.SeekOrigin]::Begin) | Out-Null
        Read-G63Exact -Stream $fs -Buffer $maskBytes -Count ([int]$maskLen)
        $manifest = ([Text.Encoding]::UTF8.GetString($manifestBytes)) | ConvertFrom-Json
        if ($manifest.format -ne "ds4-windows-sparse-bake" -or
            [int]$manifest.version -ne 1 -or
            [uint64]$manifest.source_model_size -ne $sourceSize) {
            throw "Sparse bake manifest identity mismatch"
        }
        if ((Get-G63CRC32 $manifestBytes) -ne $manifestCrc -or
            (Get-G63CRC32 $maskBytes) -ne $maskCrc) {
            throw "Sparse bake footer CRC mismatch"
        }
        [pscustomobject]@{
            manifest = $manifest
            manifest_sha256 = Get-G63BytesSHA256 $manifestBytes
            mask_sha256 = Get-G63BytesSHA256 $maskBytes
            source_size = $sourceSize
            physical_size = [uint64]$fs.Length
            manifest_length = $manifestLen
            mask_length = $maskLen
            manifest_crc32 = $manifestCrc
            mask_crc32 = $maskCrc
            extents = @(ConvertTo-G63Extents -Manifest $manifest)
        }
    } finally {
        $fs.Dispose()
    }
}

function Test-G63HarnessParameter {
    param([Parameter(Mandatory=$true)][string]$ParameterName)
    $content = Get-Content -LiteralPath $harness -Raw
    return ($content -match ("\$" + [regex]::Escape($ParameterName) + "(\s|=|,|\))"))
}

function Get-G63Property {
    param([object]$Object, [string]$Name)
    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) {
        return $null
    }
    $Object.PSObject.Properties[$Name].Value
}

function Convert-G63BytesToGiB {
    param([object]$Value)
    if ($null -eq $Value) { return $null }
    [math]::Round(([double]$Value / 1GB), 6)
}

function Get-G63Mean {
    param([Parameter(Mandatory=$true)][object[]]$Rows,
          [Parameter(Mandatory=$true)][string]$Property)
    $values = @($Rows | ForEach-Object { $_.$Property } |
        Where-Object { $null -ne $_ } | ForEach-Object { [double]$_ })
    if ($values.Count -eq 0) { return $null }
    [math]::Round(($values | Measure-Object -Average).Average, 6)
}

function Get-G63Median {
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

function Assert-G63LogContains {
    param([Parameter(Mandatory=$true)][string[]]$Lines,
          [Parameter(Mandatory=$true)][string]$Pattern,
          [Parameter(Mandatory=$true)][string]$Label,
          [Parameter(Mandatory=$true)][string]$Tag)
    if (-not @($Lines | Where-Object { $_ -match $Pattern } | Select-Object -First 1)) {
        throw "G63 sparse bake log check failed: tag=$Tag check=$Label"
    }
}

function Read-G63SafetyReceipt {
    param([Parameter(Mandatory=$true)][ValidateSet("K60")][string]$BakeId)
    $lower = $BakeId.ToLowerInvariant()
    $tag = "g57_sparse_bake_" + $lower + "_functional_safety_n1"
    $resultPath = Join-Path $outdir ("g7_" + $tag + "_result.json")
    $launchPath = Join-Path $outdir ("g7_" + $tag + "_g57_launch_provenance.json")
    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        throw "G63 requires existing G57 safety result: $resultPath"
    }
    if (-not (Test-Path -LiteralPath $launchPath -PathType Leaf)) {
        throw "G63 requires existing G57 launch provenance: $launchPath"
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
        throw "G63 cannot trust G57 safety receipt: bake=$BakeId"
    }
    foreach ($shaField in @("expected_pack_sha256", "expected_mask_sha256",
            "expected_embedded_mask_sha256", "expected_payload_sha256")) {
        Assert-G63Hex64 $shaField ([string]$l.$shaField)
    }
    [pscustomobject]@{
        bake_id = $BakeId
        safety_tag = $tag
        safety_result_path = $resultPath
        safety_result_sha256 = Get-G63SHA256 $resultPath
        safety_launch_path = $launchPath
        safety_launch_sha256 = Get-G63SHA256 $launchPath
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

function Authorize-G63Bake {
    param([Parameter(Mandatory=$true)][object]$Receipt,
          [Parameter(Mandatory=$true)][object]$Provenance)
    $resolvedModel = (Resolve-Path -LiteralPath $Receipt.model_path).Path
    if ($resolvedModel -like "D:\ds4-models\*") {
        throw "Refusing to read D:\ds4-models per G57 safety handoff"
    }
    $resolvedVerifier = (Resolve-Path -LiteralPath $Receipt.payload_verifier_path).Path
    if ((Get-G63SHA256 $resolvedVerifier) -ne $Receipt.payload_verifier_sha256) {
        throw "G63 payload verifier SHA mismatch: bake=$($Receipt.bake_id)"
    }
    $sparse = Get-G63SparseBakeManifest -Path $resolvedModel
    if ($sparse.mask_sha256 -ne $Receipt.expected_embedded_mask_sha256 -or
        [string]$sparse.manifest.mask_sha256 -ne $Receipt.expected_mask_sha256 -or
        $sparse.manifest_sha256 -ne $Receipt.expected_manifest_sha256 -or
        [uint32]$sparse.manifest_crc32 -ne $Receipt.expected_manifest_crc32 -or
        [uint32]$sparse.mask_crc32 -ne $Receipt.expected_mask_crc32 -or
        [uint64]$sparse.source_size -ne $Receipt.expected_source_size -or
        [uint64]$sparse.physical_size -ne $Receipt.expected_physical_size -or
        [uint64]$sparse.manifest.payload_bytes -ne $Receipt.expected_payload_bytes) {
        throw "G63 sparse bake receipt mismatch: bake=$($Receipt.bake_id)"
    }
    $payloadVerifyOutput = @(& $PythonPath $resolvedVerifier verify-payload --bake $resolvedModel 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw ("G63 payload verifier failed: " + ($payloadVerifyOutput -join [Environment]::NewLine))
    }
    try {
        $payloadVerify = ($payloadVerifyOutput -join [Environment]::NewLine) | ConvertFrom-Json
    } catch {
        throw ("G63 payload verifier returned invalid JSON: " + ($payloadVerifyOutput -join [Environment]::NewLine))
    }
    if (-not [bool]$payloadVerify.verified -or
        [string]$payloadVerify.expected_sha256 -ne $Receipt.expected_payload_sha256 -or
        [string]$payloadVerify.measured_sha256 -ne $Receipt.expected_payload_sha256 -or
        [uint64]$payloadVerify.payload_bytes -ne $Receipt.expected_payload_bytes -or
        [int]$payloadVerify.extent_count -ne $Receipt.expected_extent_count -or
        [int]$payloadVerify.extent_count -ne @($sparse.extents).Count) {
        throw "G63 payload SHA mismatch: bake=$($Receipt.bake_id)"
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

function Invoke-G63Run {
    param([Parameter(Mandatory=$true)][object]$Authorization,
          [Parameter(Mandatory=$true)][string]$Tag,
          [Parameter(Mandatory=$true)][int]$OrderIndex,
          [Parameter(Mandatory=$true)][object]$Provenance,
          [Parameter(Mandatory=$true)][string]$ExecutionRunnerHashForRuns)
    $resultPath = Join-Path $outdir ("g7_" + $Tag + "_result.json")
    $launchPath = Join-Path $outdir ("g7_" + $Tag + "_g63_launch_provenance.json")
    if (($Resume -or $SummarizeExisting) -and
        (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        Write-Host ("[G63] validate existing tag=" + $Tag)
    } elseif ($SummarizeExisting) {
        throw "G63 existing result missing: tag=$Tag"
    } else {
        $launch = [pscustomobject]@{
            schema = "g63_sparse_bake_g46_composite_launch_provenance_v1"
            tag = $Tag
            bake_id = $Authorization.bake_id
            purpose = "candidate-only-g46-composite"
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
            expected_g63_k60_content_sha256 = $expectedG63K60ContentSHA256
            expert_cache_n = $expertCacheN
            expert_cache_reserve_gb = $expertCacheReserveGB
            expert_cache_policy = $expertCachePolicy
            dynamic_arena_gib = $dynamicArenaGiB
            prefill_mass_wrap = $true
            arena_wrap_trust_worker_checksum = $true
            arena_wrap_source_parts = $true
            compose_prefill_mass_tiering = $true
            gpu_resident_routes = $true
            route_no_default_sync = $true
            expert_tiering = $expertTiering
            expert_tier_policy = $expertTierPolicy
            expert_tier_clock_calls = $expertTierClockCalls
            expert_tier_replacement_budget = $expertTierReplacementBudget
            expert_tier_min_frequency = $expertTierMinFrequency
            expert_tier_hysteresis = $expertTierHysteresis
            allowed_flags = @(
                "DynamicArenaGiB=30",
                "ArenaWrapTrustWorkerChecksum",
                "ArenaWrapSourceParts",
                "PrefillMassWrap",
                "ComposePrefillMassTiering",
                "ExpertCacheN=320",
                "ExpertCacheReserveGB=0.125",
                "ExpertCachePolicy=lru",
                "GpuResidentRoutes",
                "RouteNoDefaultSync",
                "ExpertTiering=enforce",
                "ExpertTierPolicy=mass-lfru",
                "ExpertTierClockCalls=430",
                "ExpertTierReplacementBudget=16",
                "ExpertTierMinFrequency=3",
                "ExpertTierHysteresis=1.25",
                "DisableQ8F16Cache",
                "EmbedRowStaging",
                "ReapPrefetchThreads8")
            forbidden_mechanisms = @(
                "SPEX",
                "external mask",
                "external REAP mask",
                "SplitHitMiss",
                "ArenaWrapSequentialFile",
                "ArenaWrapSequentialWorkers",
                "ArenaWrapFileQD",
                "layer stripe",
                "SPEX/tiering variants outside measured G46")
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
            "-DynamicArenaGiB", ($dynamicArenaGiB.ToString("0.###", [Globalization.CultureInfo]::InvariantCulture)),
            "-ArenaWrapTrustWorkerChecksum",
            "-ArenaWrapSourceParts",
            "-DisableQ8F16Cache",
            "-EmbedRowStaging",
            "-PrefillMassWrap",
            "-ComposePrefillMassTiering",
            "-ExpertCacheN", ([string]$expertCacheN),
            "-ExpertCacheReserveGB", ($expertCacheReserveGB.ToString("0.###", [Globalization.CultureInfo]::InvariantCulture)),
            "-ExpertCachePolicy", $expertCachePolicy,
            "-GpuResidentRoutes",
            "-RouteNoDefaultSync",
            "-ExpertTiering", $expertTiering,
            "-ExpertTierPolicy", $expertTierPolicy,
            "-ExpertTierClockCalls", ([string]$expertTierClockCalls),
            "-ExpertTierReplacementBudget", ([string]$expertTierReplacementBudget),
            "-ExpertTierMinFrequency", ([string]$expertTierMinFrequency),
            "-ExpertTierHysteresis", ($expertTierHysteresis.ToString("0.###", [Globalization.CultureInfo]::InvariantCulture)),
            "-AllowEmbeddedBakeMask",
            "-ExpectedEmbeddedBakeMaskSHA256", $Authorization.expected_mask_sha256,
            "-ReapPrefetchThreads", "8",
            "-ExpectedContentSHA256", $expectedG63K60ContentSHA256,
            "-ModelPath", $Authorization.model_path,
            "-TimeoutSec", ([string]$TimeoutSec)
        )
        $argLine = " " + ($args -join " ") + " "
        foreach ($forbiddenArg in @("-PrefillMassObserve", "-SplitHitMiss",
                "-SpexDryRun", "-ReapMaskFile", "-ArenaWrapSequentialFile",
                "-ArenaWrapSequentialWorkers", "-ArenaWrapFileQD",
                "-LayerStripe", "-LayerStripeAB")) {
            if ($argLine -match (" " + [regex]::Escape($forbiddenArg) + "(\s|$)")) {
                throw "G63 forbidden mechanism in launch args: $forbiddenArg"
            }
        }
        if ($argLine -notmatch " -DynamicArenaGiB\s+30(\.0)?(\s|$)" -or
            $argLine -notmatch " -ArenaWrapTrustWorkerChecksum(\s|$)" -or
            $argLine -notmatch " -ArenaWrapSourceParts(\s|$)" -or
            $argLine -notmatch " -PrefillMassWrap(\s|$)" -or
            $argLine -notmatch " -ComposePrefillMassTiering(\s|$)" -or
            $argLine -notmatch " -ExpertTiering\s+enforce(\s|$)" -or
            $argLine -notmatch " -ExpertTierPolicy\s+mass-lfru(\s|$)" -or
            $argLine -notmatch " -ExpertTierClockCalls\s+430(\s|$)" -or
            $argLine -notmatch " -ExpertTierReplacementBudget\s+16(\s|$)" -or
            $argLine -notmatch " -ExpertTierMinFrequency\s+3(\s|$)" -or
            $argLine -notmatch " -ExpertTierHysteresis\s+1\.25(\s|$)" -or
            $argLine -notmatch " -RouteNoDefaultSync(\s|$)" -or
            $argLine -notmatch " -ExpertCacheN\s+320(\s|$)" -or
            $argLine -notmatch " -ExpertCacheReserveGB\s+0\.125(\s|$)" -or
            $argLine -notmatch " -ExpertCachePolicy\s+lru(\s|$)" -or
            $argLine -notmatch " -GpuResidentRoutes(\s|$)") {
            throw "G63 exact G46 composite mechanism missing from launch args"
        }
        Write-Host ("[G63] start tag=" + $Tag + " bake=" + $Authorization.bake_id +
            " n=1 independent temp=0 nothink=true")
        & powershell.exe @args | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) { throw "G63 run failed: $Tag" }
    }

    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        throw "G63 result missing: tag=$Tag"
    }
    if (-not (Test-Path -LiteralPath $launchPath -PathType Leaf)) {
        throw "G63 launch provenance missing: tag=$Tag"
    }
    $launchRead = Get-Content -LiteralPath $launchPath -Raw | ConvertFrom-Json
    if ($launchRead.schema -ne "g63_sparse_bake_g46_composite_launch_provenance_v1" -or
        $launchRead.tag -ne $Tag -or
        $launchRead.bake_id -ne $Authorization.bake_id -or
        $launchRead.purpose -ne "candidate-only-g46-composite" -or
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
        $launchRead.expected_g63_k60_content_sha256 -ne $expectedG63K60ContentSHA256 -or
        [int]$launchRead.expert_cache_n -ne $expertCacheN -or
        [double]$launchRead.expert_cache_reserve_gb -ne $expertCacheReserveGB -or
        $launchRead.expert_cache_policy -ne $expertCachePolicy -or
        [double]$launchRead.dynamic_arena_gib -ne $dynamicArenaGiB -or
        [bool]$launchRead.prefill_mass_wrap -ne $true -or
        [bool]$launchRead.arena_wrap_trust_worker_checksum -ne $true -or
        [bool]$launchRead.arena_wrap_source_parts -ne $true -or
        [bool]$launchRead.compose_prefill_mass_tiering -ne $true -or
        [bool]$launchRead.gpu_resident_routes -ne $true -or
        [bool]$launchRead.route_no_default_sync -ne $true -or
        $launchRead.expert_tiering -ne $expertTiering -or
        $launchRead.expert_tier_policy -ne $expertTierPolicy -or
        [int]$launchRead.expert_tier_clock_calls -ne $expertTierClockCalls -or
        [int]$launchRead.expert_tier_replacement_budget -ne $expertTierReplacementBudget -or
        [int]$launchRead.expert_tier_min_frequency -ne $expertTierMinFrequency -or
        [double]$launchRead.expert_tier_hysteresis -ne $expertTierHysteresis -or
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
        throw "G63 launch provenance mismatch: tag=$Tag"
    }

    $r = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    $rt = $r.runtime_telemetry
    $tier = $r.expert_tiering
    foreach ($gateName in @("memory_preflight", "process_isolation_preflight", "system_quiescence_preflight")) {
        $gate = Get-G63Property -Object $r -Name $gateName
        if ($null -eq $gate -or [bool]$gate.ready_to_launch -ne $true) {
            throw "G63 preflight gate failed: tag=$Tag gate=$gateName"
        }
    }
    if ($null -eq $r.process_isolation_preflight -or
        [int]$r.process_isolation_preflight.conflict_count -ne 0) {
        throw "G63 process isolation gate failed: tag=$Tag"
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
        [string]$r.expected_content_sha256 -ne $expectedG63K60ContentSHA256 -or
        [string]$r.results[0].content_sha256 -ne $expectedG63K60ContentSHA256 -or
        [bool]$r.gpu_resident_routes_requested -ne $true -or
        [bool]$r.gpu_resident_routes_observed -ne $true -or
        [int64]$r.gpu_resident_routes_calls -le 0 -or
        [int64]$r.gpu_resident_routes_worker_jobs -le 0 -or
        [int64]$r.gpu_resident_routes_errors -ne 0 -or
        [bool]$r.route_no_default_sync_requested -ne $true -or
        [int64]$r.gpu_resident_routes_default_sync_calls -ne 0 -or
        [int64]$r.gpu_resident_routes_no_default_sync_calls -ne [int64]$r.gpu_resident_routes_calls -or
        [bool]$r.split_hit_miss_requested -ne $false -or
        [bool]$r.no_selected_load -ne $false -or
        [double]$r.dynamic_arena_gib_requested -ne $dynamicArenaGiB -or
        [bool]$r.prefill_mass_observe_requested -ne $false -or
        [bool]$r.prefill_mass_wrap_requested -ne $true -or
        [bool]$r.compose_prefill_mass_tiering_requested -ne $true -or
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
        $r.expert_tiering_requested -ne $expertTiering -or
        $r.expert_tier_policy_requested -ne $expertTierPolicy -or
        [int]$r.expert_tier_clock_calls_requested -ne $expertTierClockCalls -or
        [int]$r.expert_tier_replacement_budget_requested -ne $expertTierReplacementBudget -or
        [int]$r.expert_tier_min_frequency_requested -ne $expertTierMinFrequency -or
        [double]$r.expert_tier_hysteresis_requested -ne $expertTierHysteresis -or
        [bool]$r.spex_dry_run_requested -ne $false -or
        [string]$r.reap_mask_file_requested -ne "" -or
        [bool]$r.q8_f16_cache_disabled -ne $true -or
        [bool]$r.embed_row_staging_requested -ne $true -or
        [int]$r.reap_prefetch_threads_requested -ne 8 -or
        [bool]$r.embedded_bake_mask_allowed -ne $true -or
        [bool]$r.embedded_bake_mask_observed -ne $true -or
        $r.expected_embedded_bake_mask_sha256 -ne $Authorization.expected_mask_sha256 -or
        $r.reap_mask_path_observed -ne ("embedded-bake:" + $Authorization.expected_mask_sha256) -or
        [bool]$r.prefill_mass_observer_armed -ne $true -or
        [bool]$r.prefill_mass_finalized -ne $true -or
        [bool]$r.prefill_mass_wrap_observed -ne $true -or
        $r.prefill_mass_wrap_result -ne "published" -or
        $r.prefill_mass_wrap_mask -ne "request-scoped-closed" -or
        [int]$r.prefill_mass_wrap_event_count -le 0 -or
        [bool]$r.prefill_mass_compose_observed -ne $true -or
        [int]$r.prefill_mass_compose_event_count -le 0 -or
        [int64]$r.prefill_mass_compose_sparse_skipped_ranked -le 0 -or
        [bool]$r.prefill_mass_compose_mask_observed -ne $true -or
        [int]$r.prefill_mass_compose_mask_failed_count -ne 0 -or
        [string]$r.prefill_mass_compose_mask_base -ne "embedded-sparse-bake" -or
        [int]$r.prefill_mass_compose_mask_existing_layers -ne 40 -or
        [int]$r.prefill_mass_compose_mask_restore_count -le 0 -or
        $null -eq $tier -or
        [bool]$tier.compose_prefill_mass_tiering_observed -ne $true -or
        [int]$tier.compose_prefill_mass_tiering_flag -ne 1 -or
        [int]$tier.states_vram -ne $expertCacheN -or
        [int64]$tier.snapshot_backing_misses -ne 0 -or
        [int64]$tier.forbidden_cold_ssd_to_vram -ne 0 -or
        [int64]$tier.ssd_bytes -ne 0 -or
        [int64]$tier.failures -ne 0 -or
        [uint64]$r.dynamic_arena_allocated_bytes -le 0 -or
        [int]$r.dynamic_arena_allocated_slots -le 0 -or
        [bool]$r.arena_wrap_profile_observed -ne $true -or
        $r.arena_wrap_profile_result -ne "published" -or
        $r.arena_wrap_schedule_requested -ne "source-parts" -or
        $r.arena_wrap_schedule_observed -ne "source-parts" -or
        $r.arena_wrap_checksum_observed -ne "fnv1a64-worker-only" -or
        [int]$r.arena_wrap_file_qd_requested -ne 1 -or
        [int]$r.arena_wrap_profile_loads -le 0 -or
        [int]$r.arena_wrap_profile_workers -le 0 -or
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
        throw "G63 result contract mismatch: tag=$Tag"
    }

    $rawPath = Join-Path $outdir ("g7_" + $Tag + "_raw_outputs.json")
    if (-not (Test-Path -LiteralPath $rawPath -PathType Leaf)) {
        throw "G63 raw output sidecar missing: tag=$Tag"
    }
    $raw = Get-Content -LiteralPath $rawPath -Raw | ConvertFrom-Json
    if ($raw.results.Count -ne 1 -or
        [string]::IsNullOrWhiteSpace([string]$raw.results[0].content)) {
        throw "G63 raw output empty: tag=$Tag"
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
    Assert-G63LogContains -Lines $logLines `
        -Pattern "sparse bake validated:.*mask_sha256=$($Authorization.expected_mask_sha256)" `
        -Label "sparse bake startup validation" -Tag $Tag
    Assert-G63LogContains -Lines $logLines `
        -Pattern "sparse bake mask installed mask_sha256=$($Authorization.expected_mask_sha256)" `
        -Label "embedded sparse bake mask installation" -Tag $Tag
    Assert-G63LogContains -Lines $logLines `
        -Pattern "CUDA startup cache excluded .* routed-expert tensors" `
        -Label "selected-only startup cache exclusion" -Tag $Tag
    Assert-G63LogContains -Lines $logLines `
        -Pattern "\[sparse-bake-runtime\] result=guards-installed .*sparse_layers=[1-9][0-9]*" `
        -Label "CUDA sparse bake guards" -Tag $Tag
    Assert-G63LogContains -Lines $logLines `
        -Pattern "\[sparse-bake-runtime\] result=summary route_calls=[1-9][0-9]* route_slots=[1-9][0-9]* rejected=0" `
        -Label "selected-only route validation" -Tag $Tag
    Assert-G63LogContains -Lines $logLines `
        -Pattern "resident expert cache ready: [1-9][0-9]*/$expertCacheN experts" `
        -Label "resident expert cache ready" -Tag $Tag
    Assert-G63LogContains -Lines $logLines `
        -Pattern "CUDA dynamic arena ready 30\.00 GiB, [1-9][0-9]* slots" `
        -Label "dynamic arena allocation" -Tag $Tag
    Assert-G63LogContains -Lines $logLines `
        -Pattern "\[prefill-mass-compose\] hash_layers=[1-9][0-9]* hash_seed_entries=[1-9][0-9]* ranked_entries=[1-9][0-9]* total_candidate=[1-9][0-9]* capacity=[1-9][0-9]* candidate_fnv1a64=[0-9a-f]{16} sparse_skipped_ranked=[1-9][0-9]* mass_source=full-probability-normalized-per-token" `
        -Label "prefill mass compose" -Tag $Tag
    Assert-G63LogContains -Lines $logLines `
        -Pattern "\[arena\] begin base=0 target=1 resident=[1-9][0-9]* loads=[1-9][0-9]* slots=[1-9][0-9]*" `
        -Label "arena begin publication" -Tag $Tag
    Assert-G63LogContains -Lines $logLines `
        -Pattern "\[arena\] publish generation=1 loads=[1-9][0-9]*" `
        -Label "arena publish" -Tag $Tag
    Assert-G63LogContains -Lines $logLines `
        -Pattern "\[prefill-mass-compose-mask\] result=applied reason=ok layers=40 kept=[1-9][0-9]* pruned=[1-9][0-9]* semantics=request-scoped-closed base=embedded-sparse-bake existing_layers=40" `
        -Label "prefill mass compose mask" -Tag $Tag
    Assert-G63LogContains -Lines $logLines `
        -Pattern "\[prefill-mass-compose-mask\] result=restored reason=ok where=request-end layers=40 kept=6160 pruned=4080 base=embedded-sparse-bake" `
        -Label "prefill mass sparse base restore" -Tag $Tag
    Assert-G63LogContains -Lines $logLines `
        -Pattern "\[prefill-mass-wrap\] result=published reason=ok candidate=[1-9][0-9]* loads=[1-9][0-9]* .* resident_after=[1-9][0-9]*" `
        -Label "prefill mass WRAP publication" -Tag $Tag
    Assert-G63LogContains -Lines $logLines `
        -Pattern "\[gpu-resident-routes\] final calls=[1-9][0-9]* split_calls=0 all_hit=[0-9]+ worker_jobs=[1-9][0-9]* miss_experts=[0-9]+ errors=0.*default_sync=0 no_default_sync=[1-9][0-9]*" `
        -Label "GPU resident route no-default-sync counters" -Tag $Tag
    Assert-G63LogContains -Lines $logLines `
        -Pattern "\[expert-tiering\] final mode=enforce policy=mass-lfru compose_prefill_mass_tiering=1 .*snapshot_backing_misses=0 .*forbidden_cold_ssd_to_vram=0 .*clock_calls=430 replacement_budget=16 min_frequency=3 hysteresis=1\.25 .*failures=0 ssd_bytes=0 .*states_vram=320 " `
        -Label "expert tiering mass-lfru compose final counters" -Tag $Tag
    Assert-G63LogContains -Lines $logLines `
        -Pattern "arena WRAP profile result/schedule/checksum/total/copy/parts/workers: published / source-parts / fnv1a64-worker-only /" `
        -Label "arena wrap source-parts profile" -Tag $Tag
    Assert-G63LogContains -Lines $logLines `
        -Pattern "arena WRAP file QD req/line/obs/submits/completions/failures: 1 / 0 / 0 / 0 / 0 / 0" `
        -Label "no post-G46 ArenaWrapFileQD" -Tag $Tag
    Assert-G63LogContains -Lines $logLines `
        -Pattern "expert tiering requested/policy/observed/compose/failures/ssd GiB/ram_h2d GiB/states_vram: enforce / mass-lfru / True / True / 0 / 0 / .* / 320" `
        -Label "expert tiering summary line" -Tag $Tag
    Assert-G63LogContains -Lines $logLines `
        -Pattern "gpu resident routes requested/no-sync/split/observed/calls/.* True / True / False / True /" `
        -Label "route no-default-sync summary line" -Tag $Tag
    Assert-G63LogContains -Lines $logLines `
        -Pattern "gpu resident routes requested/no-sync/split/observed/calls/.* / 0 / [1-9][0-9]*" `
        -Label "route no-default-sync summary accounting" -Tag $Tag
    Assert-G63LogContains -Lines $logLines `
        -Pattern "gpu resident routes cache count/calls/hits/misses/admissions/evictions/direct_loads: [1-9][0-9]* / [1-9][0-9]* / [0-9]+ / [0-9]+ / [0-9]+ / [0-9]+ / [0-9]+" `
        -Label "direct GPU route cache telemetry" -Tag $Tag
    Assert-G63LogContains -Lines $logLines `
        -Pattern "\[gpu-resident-routes\] final calls=[1-9][0-9]* split_calls=0 all_hit=[0-9]+ worker_jobs=[1-9][0-9]* miss_experts=[0-9]+ errors=0.*cache_count=[1-9][0-9]* cache_calls=[1-9][0-9]* cache_hits=[0-9]+ cache_misses=[0-9]+ cache_admissions=[0-9]+ cache_evictions=[0-9]+ direct_loads=[0-9]+" `
        -Label "GPU resident route final direct cache counters" -Tag $Tag
    if (@($logLines | Where-Object {
            $_ -match "sparse bake rejected|selected load failed closed|outside the active mask|absent expert|zero-filled|SPEX|external REAP mask|full-range copy|PrefillMassObserve|SplitHitMiss|ArenaWrapSequentialFile|ArenaWrapFileQD|layer stripe"
        }).Count -ne 0) {
        throw "G63 sparse bake safety observed forbidden runtime log: tag=$Tag"
    }

    [pscustomobject]@{
        tag = $Tag
        bake_id = $Authorization.bake_id
        order_index = $OrderIndex
        result_path = $resultPath
        result_sha256 = Get-G63SHA256 $resultPath
        raw_outputs_path = $rawPath
        raw_outputs_sha256 = Get-G63SHA256 $rawPath
        launch_provenance_path = $launchPath
        launch_provenance_sha256 = Get-G63SHA256 $launchPath
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
        expected_g63_k60_content_sha256 = $expectedG63K60ContentSHA256
        output_hash_matches_g63_baseline = ([string]$r.results[0].content_sha256 -eq $expectedG63K60ContentSHA256)
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
        windows_available_min_gib = Convert-G63BytesToGiB $rt.windows_available_min_bytes
        working_set_peak_gib = Convert-G63BytesToGiB $rt.process_working_set_peak_bytes
        private_peak_gib = Convert-G63BytesToGiB $rt.process_private_peak_bytes
        gpu_shared_peak_gib = Convert-G63BytesToGiB $rt.gpu_process_shared_peak_bytes
        gpu_dedicated_peak_gib = Convert-G63BytesToGiB $rt.gpu_process_dedicated_peak_bytes
        vram_used_peak_mib = Get-G63Property $rt "vram_used_peak_mib"
        gpu_utilization_median_percent = Get-G63Property $rt "gpu_utilization_median_percent"
        gpu_utilization_peak_percent = Get-G63Property $rt "gpu_utilization_peak_percent"
        power_median_watts = Get-G63Property $rt "power_median_watts"
        aggregate_disk_read_gib = Convert-G63BytesToGiB $rt.aggregate_disk_read_bytes_estimated
        aggregate_disk_read_mib_per_second = Get-G63Property $rt "aggregate_disk_read_mib_per_second"
        aggregate_disk_read_throughput_mib_per_second = Get-G63Property $rt "aggregate_disk_read_throughput_mib_per_second"
        aggregate_disk_queue_length_median = Get-G63Property $rt "aggregate_disk_queue_length_median"
        aggregate_disk_queue_length_peak = Get-G63Property $rt "aggregate_disk_queue_length_peak"
        process_read_gib = Convert-G63BytesToGiB $rt.win32_process_read_transfer_delta_bytes
        process_write_gib = Convert-G63BytesToGiB $rt.win32_process_write_transfer_delta_bytes
        page_fault_delta = Get-G63Property $rt "page_fault_delta"
        mmap_backed_file_io_measured = Get-G63Property $rt "mmap_backed_file_io_measured"
        contamination_abort_observed = [bool]$rt.contamination_abort_observed
        dynamic_arena_gib_requested = [double]$r.dynamic_arena_gib_requested
        dynamic_arena_allocated_bytes = [uint64]$r.dynamic_arena_allocated_bytes
        dynamic_arena_allocated_slots = [int]$r.dynamic_arena_allocated_slots
        arena_wrap_schedule_requested = [string]$r.arena_wrap_schedule_requested
        arena_wrap_schedule_observed = [string]$r.arena_wrap_schedule_observed
        arena_wrap_checksum_observed = [string]$r.arena_wrap_checksum_observed
        arena_wrap_profile_loads = [int]$r.arena_wrap_profile_loads
        arena_wrap_profile_workers = [int]$r.arena_wrap_profile_workers
        arena_wrap_profile_total_seconds = [double]$r.arena_wrap_profile_total_seconds
        arena_wrap_file_qd_requested = [int]$r.arena_wrap_file_qd_requested
        prefill_mass_wrap_candidate_entries = [int]$r.prefill_mass_wrap_candidate_entries
        prefill_mass_wrap_loads = [int]$r.prefill_mass_wrap_loads
        prefill_mass_wrap_resident_after = [int]$r.prefill_mass_wrap_resident_after
        prefill_mass_wrap_seconds = [double]$r.prefill_mass_wrap_seconds
        prefill_mass_wrap_mask = [string]$r.prefill_mass_wrap_mask
        prefill_mass_compose_total_candidate = [int]$r.prefill_mass_compose_total_candidate
        prefill_mass_compose_ranked_entries = [int]$r.prefill_mass_compose_ranked_entries
        prefill_mass_compose_hash_seed_entries = [int]$r.prefill_mass_compose_hash_seed_entries
        prefill_mass_compose_sparse_skipped_ranked = [int64]$r.prefill_mass_compose_sparse_skipped_ranked
        prefill_mass_compose_mask_base = [string]$r.prefill_mass_compose_mask_base
        prefill_mass_compose_mask_existing_layers = [int]$r.prefill_mass_compose_mask_existing_layers
        prefill_mass_compose_mask_restore_count = [int]$r.prefill_mass_compose_mask_restore_count
        prefill_mass_compose_mask_failed_count = [int]$r.prefill_mass_compose_mask_failed_count
        expert_cache_requested = [int]$r.expert_cache_requested
        expert_cache_reserve_gb = [double]$r.expert_cache_reserve_gb
        expert_cache_policy = [string]$r.expert_cache_policy
        expert_tiering_requested = [string]$r.expert_tiering_requested
        expert_tier_policy_requested = [string]$r.expert_tier_policy_requested
        expert_tier_clock_calls_requested = [int]$r.expert_tier_clock_calls_requested
        expert_tier_replacement_budget_requested = [int]$r.expert_tier_replacement_budget_requested
        expert_tier_min_frequency_requested = [int]$r.expert_tier_min_frequency_requested
        expert_tier_hysteresis_requested = [double]$r.expert_tier_hysteresis_requested
        tier_compose_prefill_mass_tiering_observed = [bool]$tier.compose_prefill_mass_tiering_observed
        tier_snapshot_backing_misses = [int64]$tier.snapshot_backing_misses
        tier_forbidden_cold_ssd_to_vram = [int64]$tier.forbidden_cold_ssd_to_vram
        tier_failures = [int64]$tier.failures
        tier_ssd_bytes = [int64]$tier.ssd_bytes
        tier_ram_h2d_gib = Convert-G63BytesToGiB $tier.ram_h2d_bytes
        tier_states_vram = [int]$tier.states_vram
        tier_vram_hits = [int64]$tier.vram_hits
        tier_ram_hits = [int64]$tier.ram_hits
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
        gpu_resident_routes_worker_ms_per_job = Get-G63Property $r "gpu_resident_routes_worker_ms_per_job"
        gpu_resident_routes_resolve_ms_per_call = Get-G63Property $r "gpu_resident_routes_resolve_ms_per_call"
        gpu_resident_routes_wait_ms_per_call = Get-G63Property $r "gpu_resident_routes_wait_ms_per_call"
        gpu_resident_routes_queries = Get-G63Property $r "gpu_resident_routes_queries"
        gpu_resident_routes_default_sync_calls = Get-G63Property $r "gpu_resident_routes_default_sync_calls"
        gpu_resident_routes_no_default_sync_calls = Get-G63Property $r "gpu_resident_routes_no_default_sync_calls"
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
        "ExpectedEmbeddedBakeMaskSHA256", "DynamicArenaGiB",
        "PrefillMassWrap", "ArenaWrapTrustWorkerChecksum",
        "ArenaWrapSourceParts", "ComposePrefillMassTiering", "ExpertCacheN",
        "ExpertCacheReserveGB", "ExpertCachePolicy", "GpuResidentRoutes",
        "RouteNoDefaultSync", "ExpertTiering", "ExpertTierPolicy",
        "ExpertTierClockCalls", "ExpertTierReplacementBudget",
        "ExpertTierMinFrequency", "ExpertTierHysteresis",
        "DisableQ8F16Cache", "EmbedRowStaging",
        "ReapPrefetchThreads", "ExpectedContentSHA256")) {
    if (-not (Test-G63HarnessParameter -ParameterName $parameter)) {
        throw "Harness does not expose -$parameter; refusing to launch model."
    }
}

$provenance = [pscustomobject]@{
    executable_sha256 = Get-G63SHA256 $executable
    harness_sha256 = Get-G63SHA256 $harness
    runtime_monitor_harness_sha256 = Get-G63SHA256 $runtimeMonitor
    ds4_cuda_sha256 = Get-G63SHA256 (Join-Path $root "ds4_cuda.cu")
    ds4_c_sha256 = Get-G63SHA256 (Join-Path $root "ds4.c")
    ds4_server_c_sha256 = Get-G63SHA256 (Join-Path $root "ds4_server.c")
    ds4_bake_c_sha256 = Get-G63SHA256 (Join-Path $root "ds4_bake.c")
    ds4_bake_h_sha256 = Get-G63SHA256 (Join-Path $root "ds4_bake.h")
    build_manifest_sha256 = Get-G63SHA256 $buildManifest
}
$executionRunnerHashAtStart = Get-G63SHA256 $MyInvocation.MyCommand.Path
$executionRunnerHashForRuns = if ($SummarizeExisting) {
    $ExecutionRunnerSHA256.ToLowerInvariant()
} else {
    $executionRunnerHashAtStart
}

$receipts = @(
    (Read-G63SafetyReceipt -BakeId "K60")
)
$authorizations = @()
$reuseAuthorization = ($SummarizeExisting -or $Resume) -and
    (Test-Path -LiteralPath $authPath -PathType Leaf)
if ($reuseAuthorization) {
    if (-not (Test-Path -LiteralPath $authPath -PathType Leaf)) {
        throw "G63 authorization cache missing for summary: $authPath"
    }
    $authCache = Get-Content -LiteralPath $authPath -Raw | ConvertFrom-Json
    if ($authCache.schema -ne "g63_sparse_bake_g46_composite_authorization_v1" -or
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
        throw "G63 authorization cache schema mismatch"
    }
    $authorizations = @($authCache.bakes)
} elseif ($SummarizeExisting) {
    throw "G63 authorization cache missing for summary: $authPath"
} else {
    foreach ($receipt in $receipts) {
        Write-Host ("[G63] authorize bake=" + $receipt.bake_id +
            " using G57 safety receipt and payload verifier")
        $authorizations += Authorize-G63Bake -Receipt $receipt -Provenance $provenance
    }
    $auth = [pscustomobject]@{
        schema = "g63_sparse_bake_g46_composite_authorization_v1"
        created_utc = [DateTime]::UtcNow.ToString("o")
        purpose = "verify K60 payload/hash/manifest/embedded-mask once before G46 composite candidate runs"
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
    throw "G63 authorization requires exactly K60"
}
$authByBake = @{}
foreach ($authBake in $authorizations) {
    $authByBake[[string]$authBake.bake_id] = $authBake
}
foreach ($bakeId in @("K60")) {
    if (-not $authByBake.ContainsKey($bakeId)) {
        throw "G63 authorization missing bake=$bakeId"
    }
}
if ($AuthorizeOnly) {
    Write-Host ("[G63] authorization complete: " + $authPath)
    return
}

$suffixes = if ($independentProcessCount -eq 1) { @("safety") } else { @("a", "b", "c") }
$plan = @($suffixes | ForEach-Object { @{ Bake = "K60"; Suffix = $_ } })
$runs = @()
$index = 0
foreach ($item in $plan) {
    $index += 1
    $tag = "g63_sparse_bake_" + ([string]$item.Bake).ToLowerInvariant() +
        "_g46_composite_" + $item.Suffix
    $runs += Invoke-G63Run -Authorization $authByBake[[string]$item.Bake] `
        -Tag $tag -OrderIndex $index -Provenance $provenance `
        -ExecutionRunnerHashForRuns $executionRunnerHashForRuns
}

foreach ($bakeId in @("K60")) {
    $rows = @($runs | Where-Object { $_.bake_id -eq $bakeId })
    if ($rows.Count -ne $independentProcessCount) { throw "G63 replication mismatch: bake=$bakeId" }
    $hashes = @($rows | ForEach-Object { $_.content_sha256 } | Select-Object -Unique)
    if ($hashes.Count -ne 1) {
        throw "G63 output not deterministic within bake: bake=$bakeId"
    }
    if ($hashes[0] -ne $expectedG63K60ContentSHA256) {
        throw "G63 output hash differs from frozen G63 K60 composite baseline"
    }
}
$order = @($runs | ForEach-Object { $_.bake_id })
if (($order -join ",") -ne (@(1..$independentProcessCount | ForEach-Object { "K60" }) -join ",")) {
    throw "G63 order contract mismatch"
}

$armSummary = @()
foreach ($bakeId in @("K60")) {
    $rows = @($runs | Where-Object { $_.bake_id -eq $bakeId })
    $armSummary += [pscustomobject]@{
        bake_id = $bakeId
        independent_processes = $rows.Count
        content_sha256 = [string]$rows[0].content_sha256
        load_seconds_mean = Get-G63Mean $rows "load_seconds"
        load_seconds_median = Get-G63Median $rows "load_seconds"
        startup_seconds_mean = Get-G63Mean $rows "startup_seconds"
        ttft_seconds_mean = Get-G63Mean $rows "ttft_seconds"
        ttft_seconds_median = Get-G63Median $rows "ttft_seconds"
        decode_tokens_per_second_mean = Get-G63Mean $rows "decode_tokens_per_second"
        decode_tokens_per_second_median = Get-G63Median $rows "decode_tokens_per_second"
        decode_seconds_mean = Get-G63Mean $rows "decode_seconds"
        wall_seconds_mean = Get-G63Mean $rows "wall_seconds"
        windows_available_min_gib_mean = Get-G63Mean $rows "windows_available_min_gib"
        working_set_peak_gib_mean = Get-G63Mean $rows "working_set_peak_gib"
        private_peak_gib_mean = Get-G63Mean $rows "private_peak_gib"
        gpu_shared_peak_gib_mean = Get-G63Mean $rows "gpu_shared_peak_gib"
        gpu_dedicated_peak_gib_mean = Get-G63Mean $rows "gpu_dedicated_peak_gib"
        vram_used_peak_mib_mean = Get-G63Mean $rows "vram_used_peak_mib"
        gpu_utilization_median_percent_mean = Get-G63Mean $rows "gpu_utilization_median_percent"
        gpu_utilization_peak_percent_mean = Get-G63Mean $rows "gpu_utilization_peak_percent"
        aggregate_disk_read_gib_mean = Get-G63Mean $rows "aggregate_disk_read_gib"
        aggregate_disk_read_mib_per_second_mean = Get-G63Mean $rows "aggregate_disk_read_mib_per_second"
        aggregate_disk_queue_length_peak_mean = Get-G63Mean $rows "aggregate_disk_queue_length_peak"
        process_read_gib_mean = Get-G63Mean $rows "process_read_gib"
        page_fault_delta_mean = Get-G63Mean $rows "page_fault_delta"
        dynamic_arena_allocated_slots_mean = Get-G63Mean $rows "dynamic_arena_allocated_slots"
        arena_wrap_profile_total_seconds_mean = Get-G63Mean $rows "arena_wrap_profile_total_seconds"
        prefill_mass_wrap_candidate_entries_mean = Get-G63Mean $rows "prefill_mass_wrap_candidate_entries"
        prefill_mass_wrap_loads_mean = Get-G63Mean $rows "prefill_mass_wrap_loads"
        prefill_mass_wrap_resident_after_mean = Get-G63Mean $rows "prefill_mass_wrap_resident_after"
        prefill_mass_wrap_seconds_mean = Get-G63Mean $rows "prefill_mass_wrap_seconds"
        prefill_mass_compose_sparse_skipped_ranked_mean = Get-G63Mean $rows "prefill_mass_compose_sparse_skipped_ranked"
        prefill_mass_compose_mask_restore_count_mean = Get-G63Mean $rows "prefill_mass_compose_mask_restore_count"
        tier_vram_hits_mean = Get-G63Mean $rows "tier_vram_hits"
        tier_ram_hits_mean = Get-G63Mean $rows "tier_ram_hits"
        tier_ram_h2d_gib_mean = Get-G63Mean $rows "tier_ram_h2d_gib"
        tier_snapshot_backing_misses_sum = ($rows | Measure-Object -Property tier_snapshot_backing_misses -Sum).Sum
        tier_forbidden_cold_ssd_to_vram_sum = ($rows | Measure-Object -Property tier_forbidden_cold_ssd_to_vram -Sum).Sum
        tier_failures_sum = ($rows | Measure-Object -Property tier_failures -Sum).Sum
        tier_ssd_bytes_sum = ($rows | Measure-Object -Property tier_ssd_bytes -Sum).Sum
        expert_cache_hits_mean = Get-G63Mean $rows "gpu_resident_routes_cache_hits"
        expert_cache_misses_mean = Get-G63Mean $rows "gpu_resident_routes_cache_misses"
        expert_cache_evictions_mean = Get-G63Mean $rows "gpu_resident_routes_cache_evictions"
        expert_cache_direct_loads_mean = Get-G63Mean $rows "gpu_resident_routes_cache_direct_loads"
        gpu_resident_routes_worker_jobs_mean = Get-G63Mean $rows "gpu_resident_routes_worker_jobs"
        gpu_resident_routes_miss_experts_mean = Get-G63Mean $rows "gpu_resident_routes_miss_experts"
        gpu_resident_routes_wait_ms_per_call_mean = Get-G63Mean $rows "gpu_resident_routes_wait_ms_per_call"
        contamination_abort_observed_count =
            @($rows | Where-Object { $_.contamination_abort_observed }).Count
    }
}

$summary = [pscustomobject]@{
    schema = "g63_sparse_bake_g46_composite_v1"
    question = "Can K60 run the measured G46 composite deterministically with its request mask composed over the embedded sparse base?"
    safety_only = [bool]$SafetyOnly
    summarized_existing_results = [bool]$SummarizeExisting
    authorization_path = $authPath
    authorization_sha256 = Get-G63SHA256 $authPath
    csv_path = $csvPath
    prompt = $prompt
    context = $Context
    max_tokens = $MaxTokens
    temperature = 0
    think = $false
    quality_claims = "none; do not declare L0-L3 quality from 64-token runs"
    exactness_baseline = [pscustomobject]@{
        source = "G63 structurally valid candidate safety; no quality claim"
        content_sha256 = $expectedG63K60ContentSHA256
    }
    comparison_baseline = [pscustomobject]@{
        source = "frozen G58 K60 static bake"
        content_sha256 = $baselineG58K60ContentSHA256
    }
    candidate = [pscustomobject]@{
        bake_id = "K60"
        dynamic_arena_gib = $dynamicArenaGiB
        prefill_mass_wrap = $true
        arena_wrap_trust_worker_checksum = $true
        arena_wrap_source_parts = $true
        compose_prefill_mass_tiering = $true
        expert_cache_n = $expertCacheN
        expert_cache_reserve_gb = $expertCacheReserveGB
        expert_cache_policy = $expertCachePolicy
        gpu_resident_routes = $true
        route_no_default_sync = $true
        expert_tiering = $expertTiering
        expert_tier_policy = $expertTierPolicy
        expert_tier_clock_calls = $expertTierClockCalls
        expert_tier_replacement_budget = $expertTierReplacementBudget
        expert_tier_min_frequency = $expertTierMinFrequency
        expert_tier_hysteresis = $expertTierHysteresis
        allowed_flags = @(
            "DynamicArenaGiB=30",
            "ArenaWrapTrustWorkerChecksum",
            "ArenaWrapSourceParts",
            "PrefillMassWrap",
            "ComposePrefillMassTiering",
            "ExpertCacheN=320",
            "ExpertCacheReserveGB=0.125",
            "ExpertCachePolicy=lru",
            "GpuResidentRoutes",
            "RouteNoDefaultSync",
            "ExpertTiering=enforce",
            "ExpertTierPolicy=mass-lfru",
            "ExpertTierClockCalls=430",
            "ExpertTierReplacementBudget=16",
            "ExpertTierMinFrequency=3",
            "ExpertTierHysteresis=1.25",
            "DisableQ8F16Cache",
            "EmbedRowStaging",
            "ReapPrefetchThreads8")
    }
    independent_processes_per_bake = $independentProcessCount
    within_process_repeats = 1
    order_contract = "K60 candidate only; safety n=1 or performance n=3; every output must equal frozen G63 composite hash"
    order = @($runs | ForEach-Object { $_.tag })
    order_bake = @($runs | ForEach-Object { $_.bake_id })
    required_guards = @(
        "embedded sparse bake mask",
        "embedded mask observed/path/hash match",
        "selected-only startup cache exclusion",
        "CUDA sparse bake guards installed",
        "route_calls and route_slots positive",
        "rejected=0",
        "DynamicArenaGiB=30 requested and allocated",
        "ArenaWrap source-parts profile published with worker checksum",
        "PrefillMassWrap published with request-scoped-closed mask",
        "ComposePrefillMassTiering observed",
        "sparse compose skipped and replaced non-retained ranked experts",
        "request compose accepted embedded sparse base and restored it without failures",
        "ExpertTiering enforce/mass-lfru observed",
        "tier states_vram=320, failures=0, snapshot_backing_misses=0, forbidden_cold_ssd_to_vram=0",
        "RouteNoDefaultSync requested with default_sync_calls=0",
        "gpu_resident_routes requested and observed",
        "gpu route calls and worker jobs positive",
        "gpu route worker errors=0",
        "expert cache requested/capacity 320",
        "GPU-route cache count positive",
        "direct GPU-route cache hits/misses/direct telemetry coherent",
        "output hash equals frozen G63 K60 composite baseline",
        "process isolation conflict_count=0",
        "VRAM peak metric present for baseline comparison",
        "no absent expert, zero-filled, selected-load fail-closed, or external mask logs")
    excluded_features = @(
        "PrefillMassObserve", "SPEX", "external REAP mask", "SplitHitMiss",
        "ArenaWrapSequentialFile", "ArenaWrapSequentialWorkers",
        "ArenaWrapFileQD>1", "layer stripe", "full model copy",
        "tiering variants outside measured G46")
    comparisons = @(
        [pscustomobject]@{
            source = "G58 K60"
            role = "static-bake comparison baseline"
            declared_metric = "content_sha256"
            value = $baselineG58K60ContentSHA256
        },
        [pscustomobject]@{
            source = "G61"
            role = "prior K60 sparse-bake arena runner"
            declared_metric = "not remeasured by G63"
            value = "summary carries no invented G61 measurements"
        },
        [pscustomobject]@{
            source = "G62"
            role = "prior K60 sparse-bake GPU route cache runner"
            declared_metric = "not remeasured by G63"
            value = "summary carries no invented G62 measurements"
        }
    )
    metric_limitations = @(
        "startup_seconds is load_seconds from g7_measure because no separate startup field exists",
        "mmap-backed file IO is reported only when runtime_telemetry exposes it",
        "SSD bytes are measured and reported, not required to be zero",
        "model SHA is not claimed because G57 receipts record source_model_sha256 as null")
    execution_runner_sha256 = $executionRunnerHashForRuns
    summary_runner_sha256 = Get-G63SHA256 $MyInvocation.MyCommand.Path
    provenance = $provenance
    authorizations = $authorizations
    runs = $runs
    arm_summary = $armSummary
}
$runs | Select-Object tag,bake_id,order_index,content_sha256,output_hash_matches_g63_baseline,
    load_seconds,ttft_seconds,decode_tokens_per_second,wall_seconds,
    aggregate_disk_read_gib,process_read_gib,page_fault_delta,
    dynamic_arena_gib_requested,dynamic_arena_allocated_slots,
    arena_wrap_schedule_requested,arena_wrap_schedule_observed,
    arena_wrap_checksum_observed,arena_wrap_profile_loads,
    arena_wrap_profile_workers,arena_wrap_profile_total_seconds,
    arena_wrap_file_qd_requested,prefill_mass_wrap_candidate_entries,
    prefill_mass_wrap_loads,prefill_mass_wrap_resident_after,
    prefill_mass_wrap_seconds,prefill_mass_wrap_mask,
    prefill_mass_compose_total_candidate,prefill_mass_compose_sparse_skipped_ranked,
    prefill_mass_compose_mask_base,prefill_mass_compose_mask_existing_layers,
    prefill_mass_compose_mask_restore_count,prefill_mass_compose_mask_failed_count,
    expert_cache_requested,expert_cache_capacity,expert_cache_count,
    expert_tiering_requested,expert_tier_policy_requested,
    expert_tier_clock_calls_requested,expert_tier_replacement_budget_requested,
    expert_tier_min_frequency_requested,expert_tier_hysteresis_requested,
    tier_compose_prefill_mass_tiering_observed,tier_states_vram,
    tier_vram_hits,tier_ram_hits,tier_ram_h2d_gib,
    tier_snapshot_backing_misses,tier_forbidden_cold_ssd_to_vram,
    tier_failures,tier_ssd_bytes,
    expert_cache_hits,expert_cache_misses,expert_cache_evictions,
    expert_cache_direct_loads,gpu_resident_routes_calls,
    gpu_resident_routes_worker_jobs,gpu_resident_routes_miss_experts,
    gpu_resident_routes_default_sync_calls,
    gpu_resident_routes_no_default_sync_calls,
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
    Write-Host ("[G63] bake=" + $arm.bake_id +
        " n=" + $arm.independent_processes +
        " load_med=" + $arm.load_seconds_median +
        " ttft_med=" + $arm.ttft_seconds_median +
        " decode_tps_med=" + $arm.decode_tokens_per_second_median +
        " disk_read_gib_mean=" + $arm.aggregate_disk_read_gib_mean +
        " gpu_dedicated_peak_gib_mean=" + $arm.gpu_dedicated_peak_gib_mean)
}
Write-Host ("[G63] matrix complete: " + $summaryPath)
