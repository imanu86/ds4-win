# G110 per-expert IQ2-hot/Q1-cold structural runner (PowerShell 5.1, ASCII).
param(
    [switch]$StaticCheckOnly,
    [switch]$SummarizeExisting,
    [string]$Tag = "g110_q1_mixed_targeted_cold_n1"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$harness = Join-Path $root "g7_measure.ps1"
$outdir = Join-Path $root "g7_runs"
$model = "C:\ds4-models\ds4-2bit.gguf"
$modelSha = "efc7ed607ff27076e3e501fc3fefefa33c0ed8cf1eff483a2b7fdc0c2e616668"
$sidecar = "C:\ds4-models\ds4-q1-layer42-derived-routerbound.gguf"
$sidecarSha = "62413e40a6f9baf321726bcb6d7a4cb239838e7ee30c912515763d2c42caf2f6"
$sidecarBytes = [UInt64]909526048
$expectedContentSha = "185f8db32271fe25f561a6fc938b2e264306ec304eda518007d1764826381969"
$core = Join-Path $root "ds4.c"
$cuda = Join-Path $root "ds4_cuda.cu"
$gpuHeader = Join-Path $root "ds4_gpu.h"
$exe = Join-Path $root "build\Release\ds4_server.exe"
$resultPath = Join-Path $outdir ("g7_" + $Tag + "_result.json")
$stderrPath = Join-Path $outdir ("g7_" + $Tag + "_stderr.log")

foreach ($path in @($harness, $model, $sidecar, $core, $cuda, $gpuHeader, $exe)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "G110 required file missing: $path"
    }
}
foreach ($receipt in @("$model.receipt.json", "$sidecar.receipt.json")) {
    if (-not (Test-Path -LiteralPath $receipt -PathType Leaf)) {
        throw "G110 verified receipt missing: $receipt"
    }
}

$source = Get-Content -LiteralPath $MyInvocation.MyCommand.Path -Raw
foreach ($needle in @(
    '"-ComposePrefillMassOpenRouter"',
    '"-ComposePrefillMassReserveSlots", "32"',
    '"-Q1_0DualArena"',
    '"-Q1_0MixedTrace"',
    '"-ExpectedContentSHA256", $expectedContentSha',
    '"-SplitFused"',
    '"-RouteNoDefaultSync"',
    '"-ExpertTierReplacementBudget", "32"')) {
    if ($source.IndexOf($needle, [StringComparison]::Ordinal) -lt 0) {
        throw "G110 frozen runner contract missing: $needle"
    }
}
$args = @(
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $harness,
    "-GateKind", "structural-safety",
    "-MaxTokens", "1", "-Repeats", "1",
    "-Tag", $Tag, "-Prompt", "Hi", "-Context", "256",
    "-ExpectedContentSHA256", $expectedContentSha,
    "-BudgetGB", "2", "-ReserveMB", "1024",
    "-DynamicArenaGiB", "6",
    "-ArenaWrapTrustWorkerChecksum", "-ArenaWrapSourceParts",
    "-ArenaWrapUnlockSourceRanges", "-ArenaWrapUnlockWaveGiB", "4",
    "-DisableQ8F16Cache", "-EmbedRowStaging",
    "-ReapPrefetchThreads", "8",
    "-ModelPath", $model, "-ExpectedModelSHA256", $modelSha,
    "-ReuseVerifiedModelReceipt",
    "-Q1_0ExpertSidecar", $sidecar,
    "-ExpectedQ1_0ExpertSidecarSHA256", $sidecarSha,
    "-ExpectedQ1_0ExpertSidecarBytes", ([string]$sidecarBytes),
    "-ReuseVerifiedQ1_0Receipt",
    "-Q1_0LayerFirst", "42", "-Q1_0LayerLast", "42",
    "-Q1_0SelectedLoad", "-Q1_0ResidentArena", "-Q1_0DualArena",
    "-Q1_0MixedTrace",
    "-PrefillMassWrap", "-ComposePrefillMassTiering",
    "-ComposePrefillMassOpenRouter",
    "-ComposePrefillMassReserveSlots", "32",
    "-ExpertCacheN", "320", "-ExpertCacheReserveGB", "0.125",
    "-ExpertCachePolicy", "lru", "-GpuResidentRoutes",
    "-RouteNoDefaultSync", "-SplitFused",
    "-ExpertTiering", "enforce", "-ExpertTierPolicy", "mass-lfru",
    "-ExpertTierClockCalls", "430",
    "-ExpertTierReplacementBudget", "32",
    "-ExpertTierMinFrequency", "3", "-ExpertTierHysteresis", "1.25",
    "-TimeoutSec", "1800", "-QuiescenceSamples", "3",
    "-QuiescenceIntervalMs", "500"
)

$argsText = [string]::Join(" ", $args)
foreach ($forbidden in @("-Iq1Promotion", "-Iq1SMixedColdOne")) {
    if ($argsText.IndexOf($forbidden, [StringComparison]::Ordinal) -ge 0) {
        throw "G110 synchronous/legacy promotion path is forbidden: $forbidden"
    }
}
if ($StaticCheckOnly) {
    Write-Host "g110_q1_mixed_structural.ps1: STATIC PASS"
    exit 0
}

if (-not $SummarizeExisting) {
    & powershell.exe @args
    if ($LASTEXITCODE -ne 0) {
        throw "G110 harness failed with exit code $LASTEXITCODE"
    }
}
if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $stderrPath -PathType Leaf)) {
    throw "G110 harness did not produce result and stderr artifacts"
}

$result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
$log = Get-Content -LiteralPath $stderrPath -Raw
if ($log -notmatch [regex]::Escape("Q1_0 router identity validated: layers=42..42")) {
    throw "G110 Q1 sidecar was not bound to the primary router identity"
}

$artifactBindings = @(
    @("ds4_c_sha256", $core),
    @("ds4_cuda_sha256", $cuda),
    @("ds4_gpu_h_sha256", $gpuHeader),
    @("harness_sha256", $harness),
    @("executable_sha256", $exe)
)
foreach ($binding in $artifactBindings) {
    $field = [string]$binding[0]
    $path = [string]$binding[1]
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    $recorded = [string]$result.$field
    if (-not $recorded -or $recorded.ToLowerInvariant() -ne $actual) {
        throw "G110 stale artifact binding: $field"
    }
}
if ($result.tag -ne $Tag -or
    $result.expected_content_sha256 -ne $expectedContentSha -or
    -not $result.q1_0_mixed_trace_requested) {
    throw "G110 result is not bound to the frozen tag/content/trace contract"
}

$matches = [regex]::Matches(
    $log,
    '(?m)^(?:ds4: )?\[q1-0-mixed\] result=summary calls=(\d+) all_iq2=(\d+) iq2_vram=(\d+) iq2_snapshot_ram=(\d+) iq2_tier_ram=(\d+) q1_resident=(\d+) joins=(\d+) trace_rows=(\d+) iq2_ssd_bytes=(\d+) iq2_ssd_violations=(\d+) failures=(\d+) router=unchanged promotion=off\x0d?$')
if ($matches.Count -ne 1) {
    throw "G110 requires exactly one mixed resolver summary; observed $($matches.Count)"
}
$m = $matches[0]
$calls = [UInt64]$m.Groups[1].Value
$q1Resident = [UInt64]$m.Groups[6].Value
$joins = [UInt64]$m.Groups[7].Value
$traceRows = [UInt64]$m.Groups[8].Value
$iq2SsdBytes = [UInt64]$m.Groups[9].Value
$iq2SsdViolations = [UInt64]$m.Groups[10].Value
$failures = [UInt64]$m.Groups[11].Value
if ($calls -ne 1 -or $q1Resident -ne 6 -or $joins -ne 1 -or
    $traceRows -ne 6 -or $iq2SsdBytes -ne 0 -or
    $iq2SsdViolations -ne 0 -or $failures -ne 0) {
    throw "G110 mixed resolver counters failed: calls=$calls q1=$q1Resident joins=$joins trace=$traceRows iq2_ssd=$iq2SsdBytes violations=$iq2SsdViolations failures=$failures"
}
$routeMatches = [regex]::Matches(
    $log,
    '(?m)^(?:ds4: )?\[q1-0-mixed-route\] layer=(\d+) route=(\d+) expert=(\d+) weight=([-+0-9.eE]+) representation=([a-z0-9_]+) tier=(\d+) has_2bit_ram=(\d+) primary_snapshot=(\d+) q1_snapshot=(\d+)\x0d?$')
if ($routeMatches.Count -ne 6) {
    throw "G110 requires six per-route provenance rows; observed $($routeMatches.Count)"
}
$seenRoutes = @{}
$seenExperts = @{}
foreach ($routeMatch in $routeMatches) {
    $layer = [UInt32]$routeMatch.Groups[1].Value
    $route = [UInt32]$routeMatch.Groups[2].Value
    $expert = [UInt32]$routeMatch.Groups[3].Value
    $representation = $routeMatch.Groups[5].Value
    $tier = [UInt32]$routeMatch.Groups[6].Value
    $has2BitRam = [UInt32]$routeMatch.Groups[7].Value
    $primarySnapshot = [UInt64]$routeMatch.Groups[8].Value
    $q1Snapshot = [UInt64]$routeMatch.Groups[9].Value
    if ($layer -ne 42 -or $route -ge 6 -or $seenRoutes.ContainsKey($route) -or
        $expert -ge 256 -or $seenExperts.ContainsKey($expert) -or
        $representation -ne "q1_resident" -or $tier -ne 0 -or
        $has2BitRam -ne 0 -or $primarySnapshot -eq 0 -or $q1Snapshot -eq 0) {
        throw "G110 invalid per-route provenance row: $($routeMatch.Value)"
    }
    $seenRoutes[$route] = $true
    $seenExperts[$expert] = $true
}
if ($log -match '\[q1-0-mixed\] result=failed reason=unresolved') {
    throw "G110 resolver produced an unresolved route"
}
if ($result.server_exit_code -ne 0 -or
    -not $result.q1_0_dual_arena_runtime_observed -or
    -not $result.q1_0_structural_smoke_eligible -or
    $result.q1_0_resident_misses -ne 0 -or
    $result.q1_0_direct_pread_fallbacks -ne 0 -or
    $result.q1_0_direct_pread_bytes -ne 0 -or
    $result.prefill_mass_compose_mask_semantics -ne "request-scoped-open" -or
    $result.prefill_mass_wrap_result -ne "published") {
    throw "G110 structural result contract failed"
}

Write-Host (("G110 STRUCTURAL PASS calls={0} q1_resident={1} joins={2} " +
    "direct_pread_bytes={3}") -f $calls, $q1Resident, $joins,
    ([UInt64]$result.q1_0_direct_pread_bytes))
