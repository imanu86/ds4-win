# G64 long quality comparison: G46 full vs G63 K60 (PowerShell 5.1, ASCII).
# Builds on the G63 sparse-bake authorization contract and the G46 full composite flags.
param(
    [switch]$SafetyOnly,
    [ValidateSet("both", "g46_full", "g63_k60")][string]$SafetyArm = "both",
    [switch]$Resume,
    [switch]$AuthorizeOnly,
    [string]$PythonPath = "python",
    [ValidateRange(64, 131072)][int]$MaxTokens = 4000,
    [ValidateRange(64, 131072)][int]$Context = 8192,
    [ValidateRange(1, 86400)][int]$TimeoutSec = 7200
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$harness = Join-Path $root "g7_measure.ps1"
$runtimeMonitor = Join-Path $root "g7_runtime_monitor.ps1"
$outdir = Join-Path $root "g7_runs"
$executable = Join-Path $root "build\Release\ds4_server.exe"
$buildManifest = Join-Path $root "build\Release\g7_build_manifest.json"
$summaryPath = Join-Path $outdir "g64_long_g46_full_vs_g63_k60_result.json"
$csvPath = Join-Path $outdir "g64_long_g46_full_vs_g63_k60_runs.csv"
$authPath = Join-Path $outdir "g64_long_g46_full_vs_g63_k60_authorization.json"
$fullModel = "C:\ds4-models\ds4-2bit.gguf"
$grader = "C:\Users\imanu\source\repos\reap-loop\scripts\functional_grade.py"
$prompt = "Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document."
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
$summaryArms = if ($SafetyOnly -and $SafetyArm -ne "both") {
    @($SafetyArm)
} else {
    @("g46_full", "g63_k60")
}

function Assert-G64Hex64 {
    param([Parameter(Mandatory=$true)][string]$Name,
          [Parameter(Mandatory=$true)][string]$Value)
    if ($Value -notmatch '^[0-9a-fA-F]{64}$') {
        throw "$Name must be a 64-character hexadecimal SHA-256"
    }
}

function Get-G64SHA256 {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "G64 provenance file missing: $Path"
    }
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-G64BytesSHA256 {
    param([Parameter(Mandatory=$true)][byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Get-G64CRC32 {
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

function Read-G64Exact {
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

function Read-G64UInt32LE {
    param([Parameter(Mandatory=$true)][byte[]]$Bytes,
          [Parameter(Mandatory=$true)][int]$Offset)
    [BitConverter]::ToUInt32($Bytes, $Offset)
}

function Read-G64UInt64LE {
    param([Parameter(Mandatory=$true)][byte[]]$Bytes,
          [Parameter(Mandatory=$true)][int]$Offset)
    [BitConverter]::ToUInt64($Bytes, $Offset)
}

function ConvertTo-G64Extents {
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

function Get-G64SparseBakeManifest {
    param([Parameter(Mandatory=$true)][string]$Path)
    $fs = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        if ($fs.Length -lt 56) { throw "Sparse bake file is too small" }
        $footer = New-Object byte[] 56
        $fs.Seek(-56, [IO.SeekOrigin]::End) | Out-Null
        Read-G64Exact -Stream $fs -Buffer $footer -Count 56
        $magic = [Text.Encoding]::ASCII.GetString($footer, 0, 16).TrimEnd([char]0)
        if ($magic -ne "DS4BAKEFILEv1") {
            throw "ModelPath does not contain a DS4 sparse bake footer"
        }
        $version = Read-G64UInt32LE $footer 16
        $layers = Read-G64UInt32LE $footer 20
        $experts = Read-G64UInt32LE $footer 24
        $maskLen = Read-G64UInt32LE $footer 28
        $sourceSize = Read-G64UInt64LE $footer 32
        $manifestLen = Read-G64UInt64LE $footer 40
        $manifestCrc = Read-G64UInt32LE $footer 48
        $maskCrc = Read-G64UInt32LE $footer 52
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
        Read-G64Exact -Stream $fs -Buffer $manifestBytes -Count ([int]$manifestLen)
        $maskBytes = New-Object byte[] ([int]$maskLen)
        $fs.Seek($maskOffset, [IO.SeekOrigin]::Begin) | Out-Null
        Read-G64Exact -Stream $fs -Buffer $maskBytes -Count ([int]$maskLen)
        $manifest = ([Text.Encoding]::UTF8.GetString($manifestBytes)) | ConvertFrom-Json
        if ($manifest.format -ne "ds4-windows-sparse-bake" -or
            [int]$manifest.version -ne 1 -or
            [uint64]$manifest.source_model_size -ne $sourceSize) {
            throw "Sparse bake manifest identity mismatch"
        }
        if ((Get-G64CRC32 $manifestBytes) -ne $manifestCrc -or
            (Get-G64CRC32 $maskBytes) -ne $maskCrc) {
            throw "Sparse bake footer CRC mismatch"
        }
        [pscustomobject]@{
            manifest = $manifest
            manifest_sha256 = Get-G64BytesSHA256 $manifestBytes
            mask_sha256 = Get-G64BytesSHA256 $maskBytes
            source_size = $sourceSize
            physical_size = [uint64]$fs.Length
            manifest_crc32 = $manifestCrc
            mask_crc32 = $maskCrc
            extents = @(ConvertTo-G64Extents -Manifest $manifest)
        }
    } finally {
        $fs.Dispose()
    }
}

function Test-G64HarnessParameter {
    param([Parameter(Mandatory=$true)][string]$ParameterName)
    $content = Get-Content -LiteralPath $harness -Raw
    return ($content -match ("\$" + [regex]::Escape($ParameterName) + "(\s|=|,|\))"))
}

function Get-G64Property {
    param([object]$Object, [string]$Name)
    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) {
        return $null
    }
    $Object.PSObject.Properties[$Name].Value
}

function Convert-G64BytesToGiB {
    param([object]$Value)
    if ($null -eq $Value) { return $null }
    [math]::Round(([double]$Value / 1GB), 6)
}

function Get-G64Mean {
    param([Parameter(Mandatory=$true)][object[]]$Rows,
          [Parameter(Mandatory=$true)][string]$Property)
    $values = @($Rows | ForEach-Object { $_.$Property } |
        Where-Object { $null -ne $_ } | ForEach-Object { [double]$_ })
    if ($values.Count -eq 0) { return $null }
    [math]::Round(($values | Measure-Object -Average).Average, 6)
}

function Get-G64Median {
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

function Assert-G64LogContains {
    param([Parameter(Mandatory=$true)][string[]]$Lines,
          [Parameter(Mandatory=$true)][string]$Pattern,
          [Parameter(Mandatory=$true)][string]$Label,
          [Parameter(Mandatory=$true)][string]$Tag)
    if (-not @($Lines | Where-Object { $_ -match $Pattern } | Select-Object -First 1)) {
        throw "G64 runtime log check failed: tag=$Tag check=$Label"
    }
}

function Read-G64SafetyReceipt {
    $tag = "g57_sparse_bake_k60_functional_safety_n1"
    $resultPath = Join-Path $outdir ("g7_" + $tag + "_result.json")
    $launchPath = Join-Path $outdir ("g7_" + $tag + "_g57_launch_provenance.json")
    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        throw "G64 requires existing G57 K60 safety result: $resultPath"
    }
    if (-not (Test-Path -LiteralPath $launchPath -PathType Leaf)) {
        throw "G64 requires existing G57 K60 launch provenance: $launchPath"
    }
    $r = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    $l = Get-Content -LiteralPath $launchPath -Raw | ConvertFrom-Json
    if ($l.schema -ne "g57_sparse_bake_launch_provenance_v3" -or
        $l.bake_id -ne "K60" -or
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
        throw "G64 cannot trust G57 K60 safety receipt"
    }
    foreach ($shaField in @("expected_pack_sha256", "expected_mask_sha256",
            "expected_embedded_mask_sha256", "expected_payload_sha256")) {
        Assert-G64Hex64 $shaField ([string]$l.$shaField)
    }
    [pscustomobject]@{
        bake_id = "K60"
        safety_tag = $tag
        safety_result_path = $resultPath
        safety_result_sha256 = Get-G64SHA256 $resultPath
        safety_launch_path = $launchPath
        safety_launch_sha256 = Get-G64SHA256 $launchPath
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

function Authorize-G64K60Bake {
    param([Parameter(Mandatory=$true)][object]$Receipt,
          [Parameter(Mandatory=$true)][object]$Provenance)
    $resolvedModel = (Resolve-Path -LiteralPath $Receipt.model_path).Path
    if ($resolvedModel -like "D:\ds4-models\*") {
        throw "Refusing to read D:\ds4-models per G57 safety handoff"
    }
    $resolvedVerifier = (Resolve-Path -LiteralPath $Receipt.payload_verifier_path).Path
    if ((Get-G64SHA256 $resolvedVerifier) -ne $Receipt.payload_verifier_sha256) {
        throw "G64 payload verifier SHA mismatch"
    }
    $sparse = Get-G64SparseBakeManifest -Path $resolvedModel
    if ($sparse.mask_sha256 -ne $Receipt.expected_embedded_mask_sha256 -or
        [string]$sparse.manifest.mask_sha256 -ne $Receipt.expected_mask_sha256 -or
        $sparse.manifest_sha256 -ne $Receipt.expected_manifest_sha256 -or
        [uint32]$sparse.manifest_crc32 -ne $Receipt.expected_manifest_crc32 -or
        [uint32]$sparse.mask_crc32 -ne $Receipt.expected_mask_crc32 -or
        [uint64]$sparse.source_size -ne $Receipt.expected_source_size -or
        [uint64]$sparse.physical_size -ne $Receipt.expected_physical_size -or
        [uint64]$sparse.manifest.payload_bytes -ne $Receipt.expected_payload_bytes) {
        throw "G64 sparse bake receipt mismatch"
    }
    $payloadVerifyOutput = @(& $PythonPath $resolvedVerifier verify-payload --bake $resolvedModel 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw ("G64 payload verifier failed: " + ($payloadVerifyOutput -join [Environment]::NewLine))
    }
    try {
        $payloadVerify = ($payloadVerifyOutput -join [Environment]::NewLine) | ConvertFrom-Json
    } catch {
        throw ("G64 payload verifier returned invalid JSON: " + ($payloadVerifyOutput -join [Environment]::NewLine))
    }
    if (-not [bool]$payloadVerify.verified -or
        [string]$payloadVerify.expected_sha256 -ne $Receipt.expected_payload_sha256 -or
        [string]$payloadVerify.measured_sha256 -ne $Receipt.expected_payload_sha256 -or
        [uint64]$payloadVerify.payload_bytes -ne $Receipt.expected_payload_bytes -or
        [int]$payloadVerify.extent_count -ne $Receipt.expected_extent_count -or
        [int]$payloadVerify.extent_count -ne @($sparse.extents).Count) {
        throw "G64 payload SHA mismatch"
    }
    [pscustomobject]@{
        bake_id = "K60"
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

function Invoke-G64Grade {
    param([Parameter(Mandatory=$true)][string]$Tag,
          [Parameter(Mandatory=$true)][string]$Content)
    if (-not (Test-Path -LiteralPath $grader -PathType Leaf)) {
        throw "G64 grader missing: $grader"
    }
    $contentPath = Join-Path $outdir ("g7_" + $Tag + "_content.html")
    $Content | Set-Content -LiteralPath $contentPath -Encoding UTF8
    $gradeOutput = @(& $PythonPath $grader frontpage $contentPath --json 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw ("G64 functional grader failed: tag=$Tag " + ($gradeOutput -join [Environment]::NewLine))
    }
    try {
        $grade = ($gradeOutput -join [Environment]::NewLine) | ConvertFrom-Json
    } catch {
        throw ("G64 functional grader returned invalid JSON: tag=$Tag " + ($gradeOutput -join [Environment]::NewLine))
    }
    [pscustomobject]@{
        content_path = $contentPath
        content_file_sha256 = Get-G64SHA256 $contentPath
        level = [int]$grade.level
        detail = $grade.detail
    }
}

function New-G64CommonHarnessArgs {
    param([Parameter(Mandatory=$true)][string]$Tag,
          [Parameter(Mandatory=$true)][string]$ModelPath)
    @(
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
        "-ReapPrefetchThreads", "8",
        "-ModelPath", $ModelPath,
        "-TimeoutSec", ([string]$TimeoutSec)
    )
}

function Assert-G64ArgContract {
    param([Parameter(Mandatory=$true)][string[]]$Args,
          [Parameter(Mandatory=$true)][ValidateSet("g46_full", "g63_k60")][string]$Arm)
    $argLine = " " + ($Args -join " ") + " "
    foreach ($forbiddenArg in @("-PrefillMassObserve", "-SplitHitMiss",
            "-SpexDryRun", "-ReapMaskFile",
            "-ArenaWrapSequentialFile", "-ArenaWrapSequentialWorkers",
            "-ArenaWrapFileQD", "-LayerStripe", "-LayerStripeAB")) {
        if ($argLine -match (" " + [regex]::Escape($forbiddenArg) + "(\s|$)")) {
            throw "G64 forbidden mechanism in launch args: arm=$Arm arg=$forbiddenArg"
        }
    }
    if ($argLine -notmatch " -DynamicArenaGiB\s+30(\.0)?(\s|$)" -or
        $argLine -notmatch " -ArenaWrapTrustWorkerChecksum(\s|$)" -or
        $argLine -notmatch " -ArenaWrapSourceParts(\s|$)" -or
        $argLine -notmatch " -PrefillMassWrap(\s|$)" -or
        $argLine -notmatch " -ComposePrefillMassTiering(\s|$)" -or
        $argLine -notmatch " -ExpertCacheN\s+320(\s|$)" -or
        $argLine -notmatch " -ExpertCacheReserveGB\s+0\.125(\s|$)" -or
        $argLine -notmatch " -ExpertCachePolicy\s+lru(\s|$)" -or
        $argLine -notmatch " -GpuResidentRoutes(\s|$)" -or
        $argLine -notmatch " -RouteNoDefaultSync(\s|$)" -or
        $argLine -notmatch " -ExpertTiering\s+enforce(\s|$)" -or
        $argLine -notmatch " -ExpertTierPolicy\s+mass-lfru(\s|$)" -or
        $argLine -notmatch " -ExpertTierClockCalls\s+430(\s|$)" -or
        $argLine -notmatch " -ExpertTierReplacementBudget\s+16(\s|$)" -or
        $argLine -notmatch " -ExpertTierMinFrequency\s+3(\s|$)" -or
        $argLine -notmatch " -ExpertTierHysteresis\s+1\.25(\s|$)" -or
        $argLine -notmatch " -DisableQ8F16Cache(\s|$)" -or
        $argLine -notmatch " -EmbedRowStaging(\s|$)" -or
        $argLine -notmatch " -ReapPrefetchThreads\s+8(\s|$)") {
        throw "G64 exact G46 full mechanism missing from launch args: arm=$Arm"
    }
    $hasEmbeddedFlags = ($argLine -match " -AllowEmbeddedBakeMask(\s|$)" -or
        $argLine -match " -ExpectedEmbeddedBakeMaskSHA256\s+[0-9a-fA-F]{64}(\s|$)")
    if ($Arm -eq "g46_full" -and $hasEmbeddedFlags) {
        throw "G64 G46 full arm has K60-only embedded bake flags"
    }
    if ($Arm -eq "g63_k60" -and -not $hasEmbeddedFlags) {
        throw "G64 K60 arm missing embedded bake authorization flags"
    }
}

function Assert-G64ResultContract {
    param([Parameter(Mandatory=$true)][object]$Result,
          [Parameter(Mandatory=$true)][object]$Runtime,
          [Parameter(Mandatory=$true)][object]$Tier,
          [Parameter(Mandatory=$true)][string]$Tag,
          [Parameter(Mandatory=$true)][ValidateSet("g46_full", "g63_k60")][string]$Arm,
          [Parameter(Mandatory=$true)][string]$ModelPath,
          [object]$Authorization)
    foreach ($gateName in @("memory_preflight", "process_isolation_preflight", "system_quiescence_preflight")) {
        $gate = Get-G64Property -Object $Result -Name $gateName
        if ($null -eq $gate -or [bool]$gate.ready_to_launch -ne $true) {
            throw "G64 preflight gate failed: tag=$Tag gate=$gateName"
        }
    }
    if ($null -eq $Result.process_isolation_preflight -or
        [int]$Result.process_isolation_preflight.conflict_count -ne 0) {
        throw "G64 process isolation gate failed: tag=$Tag"
    }
    if ($Result.tag -ne $Tag -or
        $Result.model -ne $ModelPath -or
        $Result.prompt -ne $prompt -or
        [int]$Result.repeats -ne 1 -or
        [bool]$Result.warmup -ne $false -or
        [int]$Result.requested_max_tokens -ne $MaxTokens -or
        [int]$Result.context_requested -ne $Context -or
        [int]$Result.server_exit_code -ne 0 -or
        [bool]$Result.outputs_identical -ne $true -or
        [string]$Result.expected_content_sha256 -ne "" -or
        [bool]$Result.gpu_resident_routes_requested -ne $true -or
        [bool]$Result.gpu_resident_routes_observed -ne $true -or
        [int64]$Result.gpu_resident_routes_calls -le 0 -or
        [int64]$Result.gpu_resident_routes_worker_jobs -le 0 -or
        [int64]$Result.gpu_resident_routes_errors -ne 0 -or
        [bool]$Result.route_no_default_sync_requested -ne $true -or
        [int64]$Result.gpu_resident_routes_default_sync_calls -ne 0 -or
        [int64]$Result.gpu_resident_routes_no_default_sync_calls -ne [int64]$Result.gpu_resident_routes_calls -or
        [bool]$Result.split_hit_miss_requested -ne $false -or
        [bool]$Result.no_selected_load -ne $false -or
        [double]$Result.dynamic_arena_gib_requested -ne $dynamicArenaGiB -or
        [bool]$Result.prefill_mass_observe_requested -ne $false -or
        [bool]$Result.prefill_mass_wrap_requested -ne $true -or
        [bool]$Result.compose_prefill_mass_tiering_requested -ne $true -or
        [int]$Result.expert_cache_requested -ne $expertCacheN -or
        [double]$Result.expert_cache_reserve_gb -ne $expertCacheReserveGB -or
        $Result.expert_cache_policy -ne $expertCachePolicy -or
        [int]$Result.expert_cache_capacity -ne $expertCacheN -or
        [int]$Result.gpu_resident_routes_cache_count -le 0 -or
        [int64]$Result.gpu_resident_routes_cache_calls -le 0 -or
        ([int64]$Result.gpu_resident_routes_cache_hits + [int64]$Result.gpu_resident_routes_cache_misses) -le 0 -or
        [int64]$Result.gpu_resident_routes_cache_direct_loads -lt 0 -or
        [int64]$Result.gpu_resident_routes_cache_evictions -lt 0 -or
        [int64]$Result.gpu_resident_routes_cache_admissions -lt 0 -or
        $Result.expert_tiering_requested -ne $expertTiering -or
        $Result.expert_tier_policy_requested -ne $expertTierPolicy -or
        [int]$Result.expert_tier_clock_calls_requested -ne $expertTierClockCalls -or
        [int]$Result.expert_tier_replacement_budget_requested -ne $expertTierReplacementBudget -or
        [int]$Result.expert_tier_min_frequency_requested -ne $expertTierMinFrequency -or
        [double]$Result.expert_tier_hysteresis_requested -ne $expertTierHysteresis -or
        [bool]$Result.spex_dry_run_requested -ne $false -or
        [string]$Result.reap_mask_file_requested -ne "" -or
        [bool]$Result.q8_f16_cache_disabled -ne $true -or
        [bool]$Result.embed_row_staging_requested -ne $true -or
        [int]$Result.reap_prefetch_threads_requested -ne 8 -or
        [bool]$Result.prefill_mass_observer_armed -ne $true -or
        [bool]$Result.prefill_mass_finalized -ne $true -or
        [bool]$Result.prefill_mass_wrap_observed -ne $true -or
        $Result.prefill_mass_wrap_result -ne "published" -or
        $Result.prefill_mass_wrap_mask -ne "request-scoped-closed" -or
        [int]$Result.prefill_mass_wrap_event_count -le 0 -or
        [bool]$Result.prefill_mass_compose_observed -ne $true -or
        [int]$Result.prefill_mass_compose_event_count -le 0 -or
        [int64]$Result.prefill_mass_compose_sparse_skipped_ranked -lt 0 -or
        [int]$Result.prefill_mass_compose_mask_failed_count -ne 0 -or
        $null -eq $Tier -or
        [bool]$Tier.compose_prefill_mass_tiering_observed -ne $true -or
        [int]$Tier.compose_prefill_mass_tiering_flag -ne 1 -or
        [int]$Tier.states_vram -ne $expertCacheN -or
        [int64]$Tier.snapshot_backing_misses -ne 0 -or
        [int64]$Tier.forbidden_cold_ssd_to_vram -ne 0 -or
        [int64]$Tier.ssd_bytes -ne 0 -or
        [int64]$Tier.failures -ne 0 -or
        [uint64]$Result.dynamic_arena_allocated_bytes -le 0 -or
        [int]$Result.dynamic_arena_allocated_slots -le 0 -or
        [bool]$Result.arena_wrap_profile_observed -ne $true -or
        $Result.arena_wrap_profile_result -ne "published" -or
        $Result.arena_wrap_schedule_requested -ne "source-parts" -or
        $Result.arena_wrap_schedule_observed -ne "source-parts" -or
        $Result.arena_wrap_checksum_observed -ne "fnv1a64-worker-only" -or
        [int]$Result.arena_wrap_file_qd_requested -ne 1 -or
        [int]$Result.arena_wrap_profile_loads -le 0 -or
        [int]$Result.arena_wrap_profile_workers -le 0 -or
        $Result.results.Count -ne 1 -or
        [string]::IsNullOrWhiteSpace([string]$Result.results[0].content) -or
        [string]$Result.results[0].content_sha256 -notmatch '^[0-9a-fA-F]{64}$' -or
        [double]$Result.server_decode_mean_tokens_per_second -le 0.0 -or
        [double]$Result.server_prefill_ttft_mean_seconds -le 0.0 -or
        [double]$Result.load_seconds -le 0.0 -or
        $null -eq $Runtime -or
        [bool]$Runtime.contamination_abort_observed -ne $false -or
        $null -eq $Runtime.aggregate_disk_read_bytes_estimated -or
        $null -eq $Runtime.process_working_set_peak_bytes -or
        $null -eq $Runtime.gpu_process_dedicated_peak_bytes -or
        $null -eq $Runtime.vram_used_peak_mib) {
        throw "G64 result contract mismatch: tag=$Tag"
    }
    if ($Arm -eq "g46_full") {
        if ([bool]$Result.embedded_bake_mask_allowed -ne $false -or
            [bool]$Result.embedded_bake_mask_observed -ne $false -or
            [string]$Result.reap_mask_file_requested -ne "") {
            throw "G64 G46 full sparse-mask contamination: tag=$Tag"
        }
    } else {
        if ([bool]$Result.embedded_bake_mask_allowed -ne $true -or
            [bool]$Result.embedded_bake_mask_observed -ne $true -or
            $Result.expected_embedded_bake_mask_sha256 -ne $Authorization.expected_mask_sha256 -or
            $Result.reap_mask_path_observed -ne ("embedded-bake:" + $Authorization.expected_mask_sha256) -or
            [bool]$Result.prefill_mass_compose_mask_observed -ne $true -or
            [string]$Result.prefill_mass_compose_mask_base -ne "embedded-sparse-bake" -or
            [int]$Result.prefill_mass_compose_mask_existing_layers -ne 40 -or
            [int]$Result.prefill_mass_compose_mask_restore_count -le 0 -or
            [int64]$Result.prefill_mass_compose_sparse_skipped_ranked -le 0) {
            throw "G64 K60 sparse mask/restore contract mismatch: tag=$Tag"
        }
    }
}

function Assert-G64RuntimeLogs {
    param([Parameter(Mandatory=$true)][string]$Tag,
          [Parameter(Mandatory=$true)][ValidateSet("g46_full", "g63_k60")][string]$Arm,
          [object]$Authorization)
    $stderrPath = Join-Path $outdir ("g7_" + $Tag + "_stderr.log")
    $stdoutPath = Join-Path $outdir ("g7_" + $Tag + "_stdout.log")
    $logLines = @()
    if (Test-Path -LiteralPath $stderrPath -PathType Leaf) {
        $logLines += Get-Content -LiteralPath $stderrPath
    }
    if (Test-Path -LiteralPath $stdoutPath -PathType Leaf) {
        $logLines += Get-Content -LiteralPath $stdoutPath
    }
    Assert-G64LogContains -Lines $logLines `
        -Pattern "resident expert cache ready: [1-9][0-9]*/$expertCacheN experts" `
        -Label "resident expert cache ready" -Tag $Tag
    Assert-G64LogContains -Lines $logLines `
        -Pattern "CUDA dynamic arena ready 30\.00 GiB, [1-9][0-9]* slots" `
        -Label "dynamic arena allocation" -Tag $Tag
    Assert-G64LogContains -Lines $logLines `
        -Pattern "\[prefill-mass-compose\] hash_layers=[1-9][0-9]* hash_seed_entries=[1-9][0-9]* ranked_entries=[1-9][0-9]* total_candidate=[1-9][0-9]* capacity=[1-9][0-9]* candidate_fnv1a64=[0-9a-f]{16} sparse_skipped_ranked=[0-9]+ mass_source=full-probability-normalized-per-token" `
        -Label "prefill mass compose" -Tag $Tag
    Assert-G64LogContains -Lines $logLines `
        -Pattern "\[arena-wrap-profile\] result=published schedule=source-parts source=mmap checksum=fnv1a64-worker-only .*file_qd=1 file_qd_observed=1 file_submits=0 file_completions=0 file_failures=0" `
        -Label "arena wrap source-parts profile" -Tag $Tag
    Assert-G64LogContains -Lines $logLines `
        -Pattern "\[gpu-resident-routes\] final calls=[1-9][0-9]* split_calls=0 all_hit=[0-9]+ worker_jobs=[1-9][0-9]* miss_experts=[0-9]+ errors=0.*default_sync=0 no_default_sync=[1-9][0-9]*" `
        -Label "GPU resident route no-default-sync counters" -Tag $Tag
    Assert-G64LogContains -Lines $logLines `
        -Pattern "\[expert-tiering\] final mode=enforce policy=mass-lfru compose_prefill_mass_tiering=1 .*snapshot_backing_misses=0 .*forbidden_cold_ssd_to_vram=0 .*clock_calls=430 replacement_budget=16 min_frequency=3 hysteresis=1\.25 .*failures=0 ssd_bytes=0 .*states_vram=320 " `
        -Label "expert tiering mass-lfru compose final counters" -Tag $Tag
    if ($Arm -eq "g63_k60") {
        Assert-G64LogContains -Lines $logLines `
            -Pattern "sparse bake validated:.*mask_sha256=$($Authorization.expected_mask_sha256)" `
            -Label "sparse bake startup validation" -Tag $Tag
        Assert-G64LogContains -Lines $logLines `
            -Pattern "sparse bake mask installed mask_sha256=$($Authorization.expected_mask_sha256)" `
            -Label "embedded sparse bake mask installation" -Tag $Tag
        Assert-G64LogContains -Lines $logLines `
            -Pattern "\[sparse-bake-runtime\] result=guards-installed .*sparse_layers=[1-9][0-9]*" `
            -Label "CUDA sparse bake guards" -Tag $Tag
        Assert-G64LogContains -Lines $logLines `
            -Pattern "\[sparse-bake-runtime\] result=summary route_calls=[1-9][0-9]* route_slots=[1-9][0-9]* rejected=0" `
            -Label "selected-only route validation" -Tag $Tag
        Assert-G64LogContains -Lines $logLines `
            -Pattern "\[prefill-mass-compose-mask\] result=applied reason=ok layers=40 kept=[1-9][0-9]* pruned=[1-9][0-9]* semantics=request-scoped-closed base=embedded-sparse-bake existing_layers=40" `
            -Label "prefill mass compose mask" -Tag $Tag
        Assert-G64LogContains -Lines $logLines `
            -Pattern "\[prefill-mass-compose-mask\] result=restored reason=ok where=request-end layers=40 kept=6160 pruned=4080 base=embedded-sparse-bake" `
            -Label "prefill mass sparse base restore" -Tag $Tag
    }
    if (@($logLines | Where-Object {
            $_ -match "sparse bake rejected|selected load failed closed|outside the active mask|absent expert|zero-filled|SPEX|external REAP mask|PrefillMassObserve|SplitHitMiss|ArenaWrapSequentialFile|ArenaWrapFileQD|layer stripe"
        }).Count -ne 0) {
        throw "G64 forbidden runtime log observed: tag=$Tag"
    }
}

function Invoke-G64Run {
    param([Parameter(Mandatory=$true)][ValidateSet("g46_full", "g63_k60")][string]$Arm,
          [Parameter(Mandatory=$true)][string]$Suffix,
          [Parameter(Mandatory=$true)][int]$OrderIndex,
          [Parameter(Mandatory=$true)][object]$Provenance,
          [object]$Authorization,
          [Parameter(Mandatory=$true)][string]$ExecutionRunnerHash)
    $tagStem = if ($Arm -eq "g46_full") { "g46" } else { "k60" }
    $tag = "g64_long_" + $tagStem + $Suffix
    $resultPath = Join-Path $outdir ("g7_" + $tag + "_result.json")
    $launchPath = Join-Path $outdir ("g7_" + $tag + "_g64_launch_provenance.json")
    $modelPath = if ($Arm -eq "g46_full") { $fullModel } else { $Authorization.model_path }
    $args = New-G64CommonHarnessArgs -Tag $tag -ModelPath $modelPath
    if ($Arm -eq "g63_k60") {
        $args += @(
            "-AllowEmbeddedBakeMask",
            "-ExpectedEmbeddedBakeMaskSHA256", $Authorization.expected_mask_sha256
        )
    }
    Assert-G64ArgContract -Args $args -Arm $Arm

    if ($Resume -and (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        Write-Host ("[G64] validate existing tag=" + $tag + " arm=" + $Arm)
    } else {
        $launch = [pscustomobject]@{
            schema = "g64_long_g46_full_vs_g63_k60_launch_provenance_v1"
            tag = $tag
            arm = $Arm
            order_index = $OrderIndex
            repeats = 1
            independent_process = $true
            prompt = $prompt
            max_tokens = $MaxTokens
            context = $Context
            temperature = 0
            think = $false
            quality_claims = "none"
            expected_content_sha256 = ""
            model_path = $modelPath
            g46_full_flags = @(
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
            k60_extra_flags = if ($Arm -eq "g63_k60") {
                @("AllowEmbeddedBakeMask", "ExpectedEmbeddedBakeMaskSHA256")
            } else { @() }
            forbidden_mechanisms = @(
                "SPEX", "external mask", "external REAP mask", "SplitHitMiss",
                "ArenaWrapSequentialFile", "ArenaWrapSequentialWorkers",
                "ArenaWrapFileQD>1", "layer stripe", "expected content hash")
            authorization = if ($Arm -eq "g63_k60") { $Authorization } else { $null }
            execution_runner_sha256 = $ExecutionRunnerHash
            provenance = $Provenance
            created_utc = [DateTime]::UtcNow.ToString("o")
        }
        $launch | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath $launchPath -Encoding UTF8
        Write-Host ("[G64] start tag=" + $tag + " arm=" + $Arm +
            " max_tokens=" + $MaxTokens + " context=" + $Context)
        & powershell.exe @args | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) { throw "G64 run failed: $tag" }
    }

    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        throw "G64 result missing: tag=$tag"
    }
    if (-not (Test-Path -LiteralPath $launchPath -PathType Leaf)) {
        throw "G64 launch provenance missing: tag=$tag"
    }
    $launchRead = Get-Content -LiteralPath $launchPath -Raw | ConvertFrom-Json
    if ($launchRead.schema -ne "g64_long_g46_full_vs_g63_k60_launch_provenance_v1" -or
        $launchRead.tag -ne $tag -or
        $launchRead.arm -ne $Arm -or
        [int]$launchRead.order_index -ne $OrderIndex -or
        [int]$launchRead.repeats -ne 1 -or
        [bool]$launchRead.independent_process -ne $true -or
        $launchRead.prompt -ne $prompt -or
        [int]$launchRead.max_tokens -ne $MaxTokens -or
        [int]$launchRead.context -ne $Context -or
        [int]$launchRead.temperature -ne 0 -or
        [bool]$launchRead.think -ne $false -or
        $launchRead.quality_claims -ne "none" -or
        [string]$launchRead.expected_content_sha256 -ne "" -or
        $launchRead.model_path -ne $modelPath -or
        $launchRead.execution_runner_sha256 -ne $ExecutionRunnerHash -or
        $launchRead.provenance.executable_sha256 -ne $Provenance.executable_sha256 -or
        $launchRead.provenance.harness_sha256 -ne $Provenance.harness_sha256 -or
        $launchRead.provenance.runtime_monitor_harness_sha256 -ne $Provenance.runtime_monitor_harness_sha256 -or
        $launchRead.provenance.ds4_cuda_sha256 -ne $Provenance.ds4_cuda_sha256 -or
        $launchRead.provenance.ds4_c_sha256 -ne $Provenance.ds4_c_sha256 -or
        $launchRead.provenance.ds4_server_c_sha256 -ne $Provenance.ds4_server_c_sha256 -or
        $launchRead.provenance.ds4_bake_c_sha256 -ne $Provenance.ds4_bake_c_sha256 -or
        $launchRead.provenance.ds4_bake_h_sha256 -ne $Provenance.ds4_bake_h_sha256 -or
        $launchRead.provenance.build_manifest_sha256 -ne $Provenance.build_manifest_sha256) {
        throw "G64 launch provenance mismatch: tag=$tag"
    }

    $r = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    $rt = $r.runtime_telemetry
    $tier = $r.expert_tiering
    Assert-G64ResultContract -Result $r -Runtime $rt -Tier $tier -Tag $tag `
        -Arm $Arm -ModelPath $modelPath -Authorization $Authorization

    $rawPath = Join-Path $outdir ("g7_" + $tag + "_raw_outputs.json")
    if (-not (Test-Path -LiteralPath $rawPath -PathType Leaf)) {
        throw "G64 raw output sidecar missing: tag=$tag"
    }
    $raw = Get-Content -LiteralPath $rawPath -Raw | ConvertFrom-Json
    if ($raw.results.Count -ne 1 -or
        [string]::IsNullOrWhiteSpace([string]$raw.results[0].content)) {
        throw "G64 raw output empty: tag=$tag"
    }
    Assert-G64RuntimeLogs -Tag $tag -Arm $Arm -Authorization $Authorization
    $grade = Invoke-G64Grade -Tag $tag -Content ([string]$raw.results[0].content)
    $gradeDetailJson = ($grade.detail | ConvertTo-Json -Depth 10 -Compress)

    [pscustomobject]@{
        tag = $tag
        arm = $Arm
        order_index = $OrderIndex
        result_path = $resultPath
        result_sha256 = Get-G64SHA256 $resultPath
        raw_outputs_path = $rawPath
        raw_outputs_sha256 = Get-G64SHA256 $rawPath
        content_path = $grade.content_path
        content_file_sha256 = $grade.content_file_sha256
        launch_provenance_path = $launchPath
        launch_provenance_sha256 = Get-G64SHA256 $launchPath
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
        completion_tokens = [int]$r.results[0].completion_tokens
        finish_reason = [string]$r.server_runs[0].finish_reason
        grade_level = [int]$grade.level
        grade_detail = $grade.detail
        grade_detail_json = $gradeDetailJson
        repeat_flag_not_used_as_verdict = $true
        wall_seconds = [double]$r.results[0].seconds
        load_seconds = [double]$r.load_seconds
        startup_seconds = [double]$r.load_seconds
        ttft_seconds = [double]$r.server_prefill_ttft_mean_seconds
        decode_tokens_per_second = [double]$r.server_decode_mean_tokens_per_second
        decode_seconds = [double]$r.server_runs[0].server_decode_seconds
        server_total_seconds = [double]$r.server_runs[0].server_total_seconds
        runtime_samples = [int]$rt.samples
        runtime_elapsed_seconds = [double]$rt.elapsed_seconds
        process_isolation_conflict_count = [int]$r.process_isolation_preflight.conflict_count
        windows_available_min_gib = Convert-G64BytesToGiB $rt.windows_available_min_bytes
        working_set_peak_gib = Convert-G64BytesToGiB $rt.process_working_set_peak_bytes
        private_peak_gib = Convert-G64BytesToGiB $rt.process_private_peak_bytes
        gpu_shared_peak_gib = Convert-G64BytesToGiB $rt.gpu_process_shared_peak_bytes
        gpu_dedicated_peak_gib = Convert-G64BytesToGiB $rt.gpu_process_dedicated_peak_bytes
        vram_used_peak_mib = Get-G64Property $rt "vram_used_peak_mib"
        gpu_utilization_median_percent = Get-G64Property $rt "gpu_utilization_median_percent"
        gpu_utilization_peak_percent = Get-G64Property $rt "gpu_utilization_peak_percent"
        aggregate_disk_read_gib = Convert-G64BytesToGiB $rt.aggregate_disk_read_bytes_estimated
        aggregate_disk_read_mib_per_second = Get-G64Property $rt "aggregate_disk_read_mib_per_second"
        aggregate_disk_queue_length_peak = Get-G64Property $rt "aggregate_disk_queue_length_peak"
        process_read_gib = Convert-G64BytesToGiB $rt.win32_process_read_transfer_delta_bytes
        page_fault_delta = Get-G64Property $rt "page_fault_delta"
        contamination_abort_observed = [bool]$rt.contamination_abort_observed
        dynamic_arena_gib_requested = [double]$r.dynamic_arena_gib_requested
        dynamic_arena_allocated_bytes = [uint64]$r.dynamic_arena_allocated_bytes
        dynamic_arena_allocated_slots = [int]$r.dynamic_arena_allocated_slots
        arena_wrap_schedule_requested = [string]$r.arena_wrap_schedule_requested
        arena_wrap_schedule_observed = [string]$r.arena_wrap_schedule_observed
        arena_wrap_checksum_observed = [string]$r.arena_wrap_checksum_observed
        arena_wrap_file_qd_requested = [int]$r.arena_wrap_file_qd_requested
        arena_wrap_profile_loads = [int]$r.arena_wrap_profile_loads
        arena_wrap_profile_workers = [int]$r.arena_wrap_profile_workers
        arena_wrap_profile_total_seconds = [double]$r.arena_wrap_profile_total_seconds
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
        prefill_mass_compose_mask_existing_layers = Get-G64Property $r "prefill_mass_compose_mask_existing_layers"
        prefill_mass_compose_mask_restore_count = Get-G64Property $r "prefill_mass_compose_mask_restore_count"
        prefill_mass_compose_mask_failed_count = [int]$r.prefill_mass_compose_mask_failed_count
        embedded_bake_mask_allowed = [bool]$r.embedded_bake_mask_allowed
        embedded_bake_mask_observed = [bool]$r.embedded_bake_mask_observed
        reap_mask_path_observed = [string]$r.reap_mask_path_observed
        expert_cache_requested = [int]$r.expert_cache_requested
        expert_cache_reserve_gb = [double]$r.expert_cache_reserve_gb
        expert_cache_policy = [string]$r.expert_cache_policy
        expert_cache_capacity = [int]$r.expert_cache_capacity
        expert_cache_count = [int]$r.expert_cache_count
        expert_cache_hits = [int64]$r.expert_cache_hits
        expert_cache_misses = [int64]$r.expert_cache_misses
        expert_cache_admissions = [int64]$r.expert_cache_admissions
        expert_cache_evictions = [int64]$r.expert_cache_evictions
        expert_cache_direct_loads = [int64]$r.expert_cache_direct_loads
        expert_tiering_requested = [string]$r.expert_tiering_requested
        expert_tier_policy_requested = [string]$r.expert_tier_policy_requested
        tier_compose_prefill_mass_tiering_observed = [bool]$tier.compose_prefill_mass_tiering_observed
        tier_states_vram = [int]$tier.states_vram
        tier_vram_hits = [int64]$tier.vram_hits
        tier_ram_hits = [int64]$tier.ram_hits
        tier_ram_h2d_gib = Convert-G64BytesToGiB $tier.ram_h2d_bytes
        tier_snapshot_backing_misses = [int64]$tier.snapshot_backing_misses
        tier_forbidden_cold_ssd_to_vram = [int64]$tier.forbidden_cold_ssd_to_vram
        tier_failures = [int64]$tier.failures
        tier_ssd_bytes = [int64]$tier.ssd_bytes
        gpu_resident_routes_calls = [int64]$r.gpu_resident_routes_calls
        gpu_resident_routes_worker_jobs = [int64]$r.gpu_resident_routes_worker_jobs
        gpu_resident_routes_miss_experts = [int64]$r.gpu_resident_routes_miss_experts
        gpu_resident_routes_errors = [int64]$r.gpu_resident_routes_errors
        gpu_resident_routes_default_sync_calls = [int64]$r.gpu_resident_routes_default_sync_calls
        gpu_resident_routes_no_default_sync_calls = [int64]$r.gpu_resident_routes_no_default_sync_calls
        gpu_resident_routes_cache_count = [int]$r.gpu_resident_routes_cache_count
        gpu_resident_routes_cache_calls = [int64]$r.gpu_resident_routes_cache_calls
        gpu_resident_routes_cache_hits = [int64]$r.gpu_resident_routes_cache_hits
        gpu_resident_routes_cache_misses = [int64]$r.gpu_resident_routes_cache_misses
        gpu_resident_routes_cache_admissions = [int64]$r.gpu_resident_routes_cache_admissions
        gpu_resident_routes_cache_evictions = [int64]$r.gpu_resident_routes_cache_evictions
        gpu_resident_routes_cache_direct_loads = [int64]$r.gpu_resident_routes_cache_direct_loads
        expected_k60_mask_sha256 = if ($Arm -eq "g63_k60") { $Authorization.expected_mask_sha256 } else { "" }
        expected_k60_embedded_mask_sha256 = if ($Arm -eq "g63_k60") { $Authorization.expected_embedded_mask_sha256 } else { "" }
        expected_k60_payload_sha256 = if ($Arm -eq "g63_k60") { $Authorization.expected_payload_sha256 } else { "" }
        sparse_manifest_sha256 = if ($Arm -eq "g63_k60") { $Authorization.sparse_manifest_sha256 } else { "" }
    }
}

New-Item -ItemType Directory -Force -Path $outdir | Out-Null
foreach ($parameter in @("ModelPath", "MaxTokens", "AllowEmbeddedBakeMask",
        "ExpectedEmbeddedBakeMaskSHA256", "DynamicArenaGiB",
        "PrefillMassWrap", "ArenaWrapTrustWorkerChecksum",
        "ArenaWrapSourceParts", "ComposePrefillMassTiering", "ExpertCacheN",
        "ExpertCacheReserveGB", "ExpertCachePolicy", "GpuResidentRoutes",
        "RouteNoDefaultSync", "ExpertTiering", "ExpertTierPolicy",
        "ExpertTierClockCalls", "ExpertTierReplacementBudget",
        "ExpertTierMinFrequency", "ExpertTierHysteresis",
        "DisableQ8F16Cache", "EmbedRowStaging", "ReapPrefetchThreads")) {
    if (-not (Test-G64HarnessParameter -ParameterName $parameter)) {
        throw "Harness does not expose -$parameter; refusing to launch model."
    }
}
if (-not (Test-Path -LiteralPath $fullModel -PathType Leaf)) {
    throw "G64 G46 full model missing: $fullModel"
}
if (-not (Test-Path -LiteralPath $grader -PathType Leaf)) {
    throw "G64 functional grader missing: $grader"
}

$provenance = [pscustomobject]@{
    executable_sha256 = Get-G64SHA256 $executable
    harness_sha256 = Get-G64SHA256 $harness
    runtime_monitor_harness_sha256 = Get-G64SHA256 $runtimeMonitor
    ds4_cuda_sha256 = Get-G64SHA256 (Join-Path $root "ds4_cuda.cu")
    ds4_c_sha256 = Get-G64SHA256 (Join-Path $root "ds4.c")
    ds4_server_c_sha256 = Get-G64SHA256 (Join-Path $root "ds4_server.c")
    ds4_bake_c_sha256 = Get-G64SHA256 (Join-Path $root "ds4_bake.c")
    ds4_bake_h_sha256 = Get-G64SHA256 (Join-Path $root "ds4_bake.h")
    build_manifest_sha256 = Get-G64SHA256 $buildManifest
    functional_grade_py_sha256 = Get-G64SHA256 $grader
}
$executionRunnerHash = Get-G64SHA256 $MyInvocation.MyCommand.Path

$authorization = $null
if ($Resume -and (Test-Path -LiteralPath $authPath -PathType Leaf)) {
    $authCache = Get-Content -LiteralPath $authPath -Raw | ConvertFrom-Json
    if ($authCache.schema -ne "g64_long_g46_full_vs_g63_k60_authorization_v1" -or
        $authCache.prompt -ne $prompt -or
        [int]$authCache.max_tokens -ne $MaxTokens -or
        [int]$authCache.context -ne $Context -or
        [int]$authCache.temperature -ne 0 -or
        [bool]$authCache.think -ne $false -or
        $authCache.quality_claims -ne "none" -or
        $authCache.execution_runner_sha256 -ne $executionRunnerHash -or
        $authCache.provenance.executable_sha256 -ne $provenance.executable_sha256 -or
        $authCache.provenance.harness_sha256 -ne $provenance.harness_sha256 -or
        $authCache.provenance.runtime_monitor_harness_sha256 -ne $provenance.runtime_monitor_harness_sha256 -or
        $authCache.provenance.ds4_cuda_sha256 -ne $provenance.ds4_cuda_sha256 -or
        $authCache.provenance.ds4_c_sha256 -ne $provenance.ds4_c_sha256 -or
        $authCache.provenance.ds4_server_c_sha256 -ne $provenance.ds4_server_c_sha256 -or
        $authCache.provenance.ds4_bake_c_sha256 -ne $provenance.ds4_bake_c_sha256 -or
        $authCache.provenance.ds4_bake_h_sha256 -ne $provenance.ds4_bake_h_sha256 -or
        $authCache.provenance.build_manifest_sha256 -ne $provenance.build_manifest_sha256 -or
        $authCache.provenance.functional_grade_py_sha256 -ne $provenance.functional_grade_py_sha256) {
        throw "G64 authorization cache schema/provenance mismatch"
    }
    $authorization = $authCache.k60_authorization
} else {
    Write-Host "[G64] authorize K60 using G57 safety receipt and payload verifier"
    $receipt = Read-G64SafetyReceipt
    $authorization = Authorize-G64K60Bake -Receipt $receipt -Provenance $provenance
    $auth = [pscustomobject]@{
        schema = "g64_long_g46_full_vs_g63_k60_authorization_v1"
        created_utc = [DateTime]::UtcNow.ToString("o")
        purpose = "verify K60 payload/hash/manifest/embedded-mask before G64 long quality comparison"
        prompt = $prompt
        max_tokens = $MaxTokens
        context = $Context
        temperature = 0
        think = $false
        quality_claims = "none"
        execution_runner_sha256 = $executionRunnerHash
        provenance = $provenance
        k60_authorization = $authorization
    }
    $auth | ConvertTo-Json -Depth 10 |
        Set-Content -LiteralPath $authPath -Encoding UTF8
}
if ($AuthorizeOnly) {
    Write-Host ("[G64] authorization complete: " + $authPath)
    return
}

$plan = if ($SafetyOnly) {
    if ($SafetyArm -eq "g46_full") {
        @(@{ Arm = "g46_full"; Suffix = "safety" })
    } elseif ($SafetyArm -eq "g63_k60") {
        @(@{ Arm = "g63_k60"; Suffix = "safety" })
    } else {
        @(
            @{ Arm = "g46_full"; Suffix = "safety" },
            @{ Arm = "g63_k60"; Suffix = "safety" }
        )
    }
} else {
    @(
        @{ Arm = "g46_full"; Suffix = "a" },
        @{ Arm = "g63_k60"; Suffix = "a" },
        @{ Arm = "g63_k60"; Suffix = "b" },
        @{ Arm = "g46_full"; Suffix = "b" },
        @{ Arm = "g46_full"; Suffix = "c" },
        @{ Arm = "g63_k60"; Suffix = "c" }
    )
}

$runs = @()
$index = 0
foreach ($item in $plan) {
    $index += 1
    $runs += Invoke-G64Run -Arm $item.Arm -Suffix $item.Suffix -OrderIndex $index `
        -Provenance $provenance -Authorization $authorization `
        -ExecutionRunnerHash $executionRunnerHash
}

$expectedOrder = if ($SafetyOnly) {
    @($plan | ForEach-Object { $_.Arm })
} else {
    @("g46_full", "g63_k60", "g63_k60", "g46_full", "g46_full", "g63_k60")
}
$observedOrder = @($runs | ForEach-Object { $_.arm })
if (($observedOrder -join ",") -ne ($expectedOrder -join ",")) {
    throw "G64 order contract mismatch"
}
foreach ($arm in $summaryArms) {
    $rows = @($runs | Where-Object { $_.arm -eq $arm })
    if ($rows.Count -ne $independentProcessCount) {
        throw "G64 replication mismatch: arm=$arm"
    }
}

$armSummary = @()
foreach ($arm in $summaryArms) {
    $rows = @($runs | Where-Object { $_.arm -eq $arm })
    $armSummary += [pscustomobject]@{
        arm = $arm
        independent_processes = $rows.Count
        content_sha256_values = @($rows | ForEach-Object { $_.content_sha256 })
        grade_level_mean = Get-G64Mean $rows "grade_level"
        grade_level_median = Get-G64Median $rows "grade_level"
        load_seconds_mean = Get-G64Mean $rows "load_seconds"
        load_seconds_median = Get-G64Median $rows "load_seconds"
        ttft_seconds_mean = Get-G64Mean $rows "ttft_seconds"
        ttft_seconds_median = Get-G64Median $rows "ttft_seconds"
        decode_tokens_per_second_mean = Get-G64Mean $rows "decode_tokens_per_second"
        decode_tokens_per_second_median = Get-G64Median $rows "decode_tokens_per_second"
        decode_seconds_mean = Get-G64Mean $rows "decode_seconds"
        wall_seconds_mean = Get-G64Mean $rows "wall_seconds"
        completion_tokens_mean = Get-G64Mean $rows "completion_tokens"
        gpu_dedicated_peak_gib_mean = Get-G64Mean $rows "gpu_dedicated_peak_gib"
        vram_used_peak_mib_mean = Get-G64Mean $rows "vram_used_peak_mib"
        aggregate_disk_read_gib_mean = Get-G64Mean $rows "aggregate_disk_read_gib"
        process_read_gib_mean = Get-G64Mean $rows "process_read_gib"
        dynamic_arena_allocated_slots_mean = Get-G64Mean $rows "dynamic_arena_allocated_slots"
        prefill_mass_compose_sparse_skipped_ranked_mean = Get-G64Mean $rows "prefill_mass_compose_sparse_skipped_ranked"
        prefill_mass_compose_mask_restore_count_mean = Get-G64Mean $rows "prefill_mass_compose_mask_restore_count"
        tier_snapshot_backing_misses_sum = ($rows | Measure-Object -Property tier_snapshot_backing_misses -Sum).Sum
        tier_forbidden_cold_ssd_to_vram_sum = ($rows | Measure-Object -Property tier_forbidden_cold_ssd_to_vram -Sum).Sum
        tier_failures_sum = ($rows | Measure-Object -Property tier_failures -Sum).Sum
        tier_ssd_bytes_sum = ($rows | Measure-Object -Property tier_ssd_bytes -Sum).Sum
        gpu_resident_routes_default_sync_calls_sum = ($rows | Measure-Object -Property gpu_resident_routes_default_sync_calls -Sum).Sum
        contamination_abort_observed_count =
            @($rows | Where-Object { $_.contamination_abort_observed }).Count
    }
}

$summary = [pscustomobject]@{
    schema = "g64_long_g46_full_vs_g63_k60_v1"
    question = "Long quality comparison of G46 full model versus G63 K60 using identical G46 full flags, with K60 adding only embedded-bake authorization flags."
    safety_only = [bool]$SafetyOnly
    safety_arm = if ($SafetyOnly) { $SafetyArm } else { "not_applicable" }
    authorization_path = $authPath
    authorization_sha256 = Get-G64SHA256 $authPath
    csv_path = $csvPath
    prompt = $prompt
    context = $Context
    max_tokens = $MaxTokens
    timeout_sec = $TimeoutSec
    temperature = 0
    think = $false
    quality_claims = "none"
    expected_content_sha256 = ""
    no_hash_equality_required = $true
    hash_policy = "content_sha256 is saved as data only; no expected content hash and no intra-arm or inter-arm equality requirement"
    grading = [pscustomobject]@{
        command = ($PythonPath + " " + $grader + " frontpage <content file> --json")
        verdict_source = "functional_grade.py level/detail"
        repeat_flag_used_as_verdict = $false
        grader_sha256 = $provenance.functional_grade_py_sha256
    }
    independent_processes_per_arm = $independentProcessCount
    within_process_repeats = 1
    order_contract = if ($SafetyOnly) {
        "SafetyOnly: one process for selected arm(s): " + ($expectedOrder -join ",")
    } else {
        "Performance/quality: n=3 per arm interleaved g46a,k60a,k60b,g46b,g46c,k60c"
    }
    order = @($runs | ForEach-Object { $_.tag })
    order_arm = @($runs | ForEach-Object { $_.arm })
    g46_full_model = $fullModel
    k60_authorization = $authorization
    common_g46_full_flags = @(
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
    k60_only_extra_flags = @(
        "AllowEmbeddedBakeMask",
        "ExpectedEmbeddedBakeMaskSHA256")
    required_guards = @(
        "provenance launch/result consistency",
        "memory/process-isolation/system-quiescence preflight ready",
        "output content non-empty",
        "no expected content hash",
        "RouteNoDefaultSync requested and default_sync_calls=0",
        "gpu resident routes requested/observed with zero errors",
        "expert cache/tiering requested and observed",
        "tier snapshot_backing_misses=0, forbidden_cold_ssd_to_vram=0, ssd_bytes=0, failures=0",
        "K60 embedded sparse bake mask/path/hash observed",
        "K60 sparse compose mask applied/restored without failures",
        "forbidden SPEX/external mask/stripe/FileQD>1/runtime failures absent")
    excluded_features = @(
        "SPEX", "external REAP mask", "expected content hash",
        "SplitHitMiss", "ArenaWrapSequentialFile",
        "ArenaWrapSequentialWorkers", "ArenaWrapFileQD>1", "layer stripe")
    execution_runner_sha256 = $executionRunnerHash
    summary_runner_sha256 = Get-G64SHA256 $MyInvocation.MyCommand.Path
    provenance = $provenance
    runs = $runs
    arm_summary = $armSummary
}

$runs | Select-Object tag,arm,order_index,content_sha256,content_path,
    grade_level,grade_detail_json,repeat_flag_not_used_as_verdict,
    completion_tokens,finish_reason,load_seconds,ttft_seconds,
    decode_tokens_per_second,decode_seconds,wall_seconds,
    aggregate_disk_read_gib,process_read_gib,page_fault_delta,
    dynamic_arena_gib_requested,dynamic_arena_allocated_slots,
    arena_wrap_schedule_requested,arena_wrap_schedule_observed,
    arena_wrap_checksum_observed,arena_wrap_file_qd_requested,
    prefill_mass_wrap_candidate_entries,prefill_mass_wrap_loads,
    prefill_mass_wrap_resident_after,prefill_mass_wrap_seconds,
    prefill_mass_wrap_mask,prefill_mass_compose_total_candidate,
    prefill_mass_compose_sparse_skipped_ranked,
    prefill_mass_compose_mask_base,prefill_mass_compose_mask_existing_layers,
    prefill_mass_compose_mask_restore_count,
    prefill_mass_compose_mask_failed_count,embedded_bake_mask_allowed,
    embedded_bake_mask_observed,reap_mask_path_observed,
    expert_cache_requested,expert_cache_capacity,expert_cache_count,
    expert_tiering_requested,expert_tier_policy_requested,
    tier_compose_prefill_mass_tiering_observed,tier_states_vram,
    tier_vram_hits,tier_ram_hits,tier_ram_h2d_gib,
    tier_snapshot_backing_misses,tier_forbidden_cold_ssd_to_vram,
    tier_failures,tier_ssd_bytes,gpu_resident_routes_calls,
    gpu_resident_routes_worker_jobs,gpu_resident_routes_miss_experts,
    gpu_resident_routes_errors,gpu_resident_routes_default_sync_calls,
    gpu_resident_routes_no_default_sync_calls,gpu_resident_routes_cache_count,
    gpu_resident_routes_cache_calls,gpu_resident_routes_cache_hits,
    gpu_resident_routes_cache_misses,gpu_resident_routes_cache_admissions,
    gpu_resident_routes_cache_evictions,gpu_resident_routes_cache_direct_loads,
    gpu_dedicated_peak_gib,vram_used_peak_mib,
    process_isolation_conflict_count,contamination_abort_observed |
    Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding ASCII
$summary | ConvertTo-Json -Depth 12 |
    Set-Content -LiteralPath $summaryPath -Encoding UTF8
foreach ($arm in $armSummary) {
    Write-Host ("[G64] arm=" + $arm.arm +
        " n=" + $arm.independent_processes +
        " grade_med=" + $arm.grade_level_median +
        " ttft_med=" + $arm.ttft_seconds_median +
        " decode_tps_med=" + $arm.decode_tokens_per_second_median)
}
Write-Host ("[G64] matrix complete: " + $summaryPath)
