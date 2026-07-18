# G120 G73-composite open-router vs four-layer nested residual safety.
# PowerShell 5.1 compatible; n=1 structural exactness only.
param(
    [ValidatePattern('^[A-Za-z0-9_-]+$')]
    [string]$Tag = "g120_g73_open_nested4_safety",
    [ValidateRange(600, 7200)][int]$TimeoutSec = 2400
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$env:GIT_CONFIG_COUNT = "1"
$env:GIT_CONFIG_KEY_0 = "safe.directory"
$env:GIT_CONFIG_VALUE_0 = ($root -replace '\\', '/')
$harness = Join-Path $root "g7_measure.ps1"
$runs = Join-Path $root "g7_runs"
$model = "C:\ds4-models\ds4-2bit.gguf"
$modelSHA = "efc7ed607ff27076e3e501fc3fefefa33c0ed8cf1eff483a2b7fdc0c2e616668"
$sidecar = "C:\ds4-models\ds4-nested-residual-layers3-16-29-42.ds4nr"
$sidecarReceipt = "C:\ds4-models\ds4-nested-residual-layers3-16-29-42.receipt.json"
$sidecarBytes = [UInt64]3221226880
$sidecarSHA = "07199bc5503aa6e2dea10f702c1ca9e8f05a5bf466a56cbed031f6a5fca4bdf9"
$payloadSHA = "02c8cb248a8184e365e2e486653484165db39402fd28320ba621fb4fdb3f7bd8"
$historicalG73ContentSHA = "31cbc6504dcb57d42aeff9dbceb3aed943bcb32dae19a2edbf552e9fd2f52eb8"
$prompt = "Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document."
$promptSHA = "38f6ec5ee5403f59dd2418eb5d9a5a94a0f0da19df015060383bb1ae46003bb6"
$controlTag = $Tag + "_control"
$candidateTag = $Tag + "_candidate"
$receiptPath = Join-Path $runs ("g7_" + $Tag + "_receipt.json")

foreach ($path in @($harness, $model, "$model.receipt.json", $sidecar,
                     $sidecarReceipt)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "G120 required file missing: $path"
    }
}
if ([UInt64](Get-Item -LiteralPath $sidecar).Length -ne $sidecarBytes) {
    throw "G120 sidecar size mismatch"
}
$sha = [Security.Cryptography.SHA256]::Create()
try {
    $promptBytes = [Text.Encoding]::UTF8.GetBytes($prompt)
    $observedPromptSHA = [BitConverter]::ToString(
        $sha.ComputeHash($promptBytes)).Replace("-", "").ToLowerInvariant()
} finally {
    $sha.Dispose()
}
if ($observedPromptSHA -ne $promptSHA) {
    throw "G120 prompt SHA-256 mismatch"
}

$sidecarLock = [IO.File]::Open(
    $sidecar, [IO.FileMode]::Open, [IO.FileAccess]::Read,
    [IO.FileShare]::Read)
try {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $observedSidecarSHA = [BitConverter]::ToString(
            $sha.ComputeHash($sidecarLock)).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
    if ($observedSidecarSHA -ne $sidecarSHA) {
        throw "G120 sidecar SHA-256 mismatch"
    }
    $sidecarLock.Position = 0

    $common = @(
        "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", $harness, "-GateKind", "structural-safety",
        "-ModelPath", $model, "-ExpectedModelSHA256", $modelSHA,
        "-ReuseVerifiedModelReceipt", "-Prompt", $prompt,
        "-MaxTokens", "64", "-Repeats", "1", "-Context", "256",
        "-BudgetGB", "2", "-ReserveMB", "1024",
        "-DynamicArenaGiB", "26.25", "-ArenaWrapTrustWorkerChecksum",
        "-ArenaWrapSourceParts", "-ArenaWrapUnlockSourceRanges",
        "-ArenaWrapUnlockWaveGiB", "4", "-DisableQ8F16Cache",
        "-EmbedRowStaging", "-ReapPrefetchThreads", "8",
        "-PrefillMassWrap", "-ComposePrefillMassTiering",
        "-ComposePrefillMassOpenRouter", "-ForceOpenRouter",
        "-ComposePrefillMassReserveSlots", "32",
        "-ExpertCacheN", "320", "-ExpertCacheReserveGB", "0.125",
        "-ExpertCachePolicy", "lru", "-GpuResidentRoutes",
        "-RouteNoDefaultSync", "-ExpertTiering", "enforce",
        "-ExpertTierPolicy", "mass-lfru", "-ExpertTierClockCalls", "430",
        "-ExpertTierReplacementBudget", "32",
        "-ExpertTierMinFrequency", "3", "-ExpertTierHysteresis", "1.25",
        "-SplitFused", "-RuntimeMinimumAvailableGiB", "1",
        "-RuntimeMaximumDiskQueueLength", "8",
        "-RuntimeContaminationSamples", "3", "-QuiescenceCooldownSec", "10",
        "-TimeoutSec", ([string]$TimeoutSec)
    )

    Write-Host "[g120] phase=control representation=primary-iq2 router=request-scoped-open"
    & powershell.exe @common -Tag $controlTag
    if ($LASTEXITCODE -ne 0) { throw "G120 control failed" }
    $controlPath = Join-Path $runs ("g7_" + $controlTag + "_result.json")
    $control = Get-Content -LiteralPath $controlPath -Raw | ConvertFrom-Json
    $controlSample = @($control.results)[0]
    if (-not $controlSample.content_sha256) {
        throw "G120 control output hash missing"
    }

    Write-Host "[g120] phase=candidate representation=nested-base-plus-exact-residual router=request-scoped-open"
    & powershell.exe @common -Tag $candidateTag `
        -ExpectedContentSHA256 ([string]$controlSample.content_sha256) `
        -NestedResidualSidecar $sidecar `
        -ExpectedNestedResidualSidecarSHA256 $sidecarSHA `
        -ExpectedNestedResidualSourceSHA256 $modelSHA `
        -ExpectedNestedResidualPayloadSHA256 $payloadSHA `
        -NestedResidualCacheExperts 64 `
        -NestedResidualVerifyReconstruction
    if ($LASTEXITCODE -ne 0) { throw "G120 candidate failed" }

    $candidatePath = Join-Path $runs ("g7_" + $candidateTag + "_result.json")
    $candidateStderrPath = Join-Path $runs ("g7_" + $candidateTag + "_stderr.log")
    $candidate = Get-Content -LiteralPath $candidatePath -Raw | ConvertFrom-Json
    $candidateStderr = Get-Content -LiteralPath $candidateStderrPath -Raw
    $candidateSample = @($candidate.results)[0]

    if ($candidateSample.content_sha256 -ne $controlSample.content_sha256) {
        throw "G120 output exactness mismatch"
    }
    foreach ($result in @($control, $candidate)) {
        if (-not $result.compose_prefill_mass_open_router_requested -or
            $result.prefill_mass_compose_mask_semantics -ne "request-scoped-open" -or
            [int]$result.compose_prefill_mass_reserve_slots_requested -ne 32 -or
            [double]$result.dynamic_arena_gib_requested -ne 26.25 -or
            -not $result.split_fused_requested) {
            throw "G120 common open-router/G73 contract mismatch"
        }
    }
    if (-not $candidate.nested_residual_runtime_observed -or
        [UInt64]$candidate.nested_residual_router_calls -eq 0 -or
        [UInt64]$candidate.nested_residual_cache_misses -eq 0 -or
        [UInt64]$candidate.nested_residual_preads -ne
            [UInt64]$candidate.nested_residual_cache_misses -or
        [UInt64]$candidate.nested_residual_reconstructed -ne
            [UInt64]$candidate.nested_residual_cache_misses -or
        [UInt64]$candidate.nested_residual_mismatches -ne 0 -or
        [UInt64]$candidate.nested_residual_failures -ne 0) {
        throw "G120 nested exact transport contract mismatch"
    }
    $compose = [regex]::Match(
        $candidateStderr,
        '\[prefill-mass-compose\].*nested_skipped_ranked=(\d+)')
    if (-not $compose.Success -or [UInt64]$compose.Groups[1].Value -eq 0) {
        throw "G120 did not observe covered-layer exclusion from the primary arena"
    }
    if ($candidateStderr -match
        '\[nested-residual\] primary-arena-filter result=failed') {
        throw "G120 observed duplicate nested entries in the primary arena"
    }
    $bootstrap = [regex]::Match(
        $candidateStderr,
        '\[nested-residual\] bootstrap-ready base_bytes=(\d+) cache_entries=(\d+)')
    if (-not $bootstrap.Success -or
        [UInt64]$bootstrap.Groups[1].Value -ne [UInt64]4026531840 -or
        [UInt64]$bootstrap.Groups[2].Value -ne [UInt64]64) {
        throw "G120 nested resident-base bootstrap mismatch"
    }

    $receipt = [ordered]@{
        schema = "g120_nested_residual_g73_open_safety_v1"
        status = "pass"
        claim_scope = "n1_structural_exactness_only"
        timing_claim_valid = $false
        prompt_sha256 = $promptSHA
        control_content_sha256 = [string]$controlSample.content_sha256
        historical_g73_content_sha256 = $historicalG73ContentSHA
        control_matches_historical_g73 =
            ([string]$controlSample.content_sha256 -eq $historicalG73ContentSHA)
        router = "request-scoped-open"
        static_mask = "off"
        primary_dynamic_arena_gib = 26.25
        nested_resident_base_bytes = [UInt64]$bootstrap.Groups[1].Value
        nested_exact_cache_experts = [UInt64]$bootstrap.Groups[2].Value
        aggregate_host_resident_budget_gib = 30.0
        compose_reserve_slots = 32
        nested_layers = @(3, 16, 29, 42)
        nested_skipped_ranked = [UInt64]$compose.Groups[1].Value
        source_model_sha256 = $modelSHA
        sidecar_sha256 = $sidecarSHA
        payload_sha256 = $payloadSHA
        control_result = $controlPath
        candidate_result = $candidatePath
        control_output_sha256 = [string]$controlSample.content_sha256
        candidate_output_sha256 = [string]$candidateSample.content_sha256
        nested_router_calls = [UInt64]$candidate.nested_residual_router_calls
        nested_cache_hits = [UInt64]$candidate.nested_residual_cache_hits
        nested_cache_misses = [UInt64]$candidate.nested_residual_cache_misses
        nested_residual_preads = [UInt64]$candidate.nested_residual_preads
        nested_reconstructed = [UInt64]$candidate.nested_residual_reconstructed
        nested_mismatches = [UInt64]$candidate.nested_residual_mismatches
        nested_failures = [UInt64]$candidate.nested_residual_failures
    }
    $receipt | ConvertTo-Json -Depth 6 |
        Set-Content -LiteralPath $receiptPath -Encoding UTF8
    Write-Host ("[g120] PASS output_sha=" + $controlSample.content_sha256 +
        " nested_skipped_ranked=" + $compose.Groups[1].Value +
        " nested_misses=" + $candidate.nested_residual_cache_misses)
} finally {
    $sidecarLock.Dispose()
}
