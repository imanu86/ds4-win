$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$safetyRunnerPath = Join-Path $root 'g128_all_layer_nested_storage_safety.ps1'
$abRunnerPath = Join-Path $root 'g128_all_layer_nested_storage_ab.ps1'

foreach ($path in @($safetyRunnerPath, $abRunnerPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "G128 required file missing: $path"
    }
    $tokens = $null
    $errors = $null
    [Management.Automation.Language.Parser]::ParseFile(
        $path, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors -and $errors.Count -gt 0) {
        throw "G128 PowerShell parse failed for $path`: $($errors[0].Message)"
    }
}

$safety = Get-Content -LiteralPath $safetyRunnerPath -Raw
$runner = Get-Content -LiteralPath $abRunnerPath -Raw
$dummySidecar = 'C:\g128-static\all-layer-sidecar.ds4nr'
$dummySidecarSHA = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
$dummySidecarPayloadSHA = 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc'
$dummySidecarBytes = [UInt64]123456789

function Require-Text {
    param([string]$Text, [string]$Needle, [string]$Contract)
    if ($Text.IndexOf($Needle, [StringComparison]::Ordinal) -lt 0) {
        throw "G128 contract missing ($Contract): $Needle"
    }
}

foreach ($needle in @(
        'ds4_g128_all_layer_nested_storage_safety_v1',
        'g128_all_layer_nested_storage_safety_plan_v1',
        'structural_safety_only_no_sota_no_quality_verdict',
        '-GateKind',
        'structural-safety',
        '-NestedResidualStructuralN1',
        '-NestedResidualVerifyReconstruction',
        '-NestedResidualGpuCache',
        '-NestedResidualGpuJoin',
        '-NestedResidualGpuJoinResidualCache',
        '-NestedResidualPageableBase',
        '-NestedResidualBasePinnedGiB',
        '[ValidateRange(0.25, 30.0)]',
        '-NestedResidualCachePageable',
        '-NestedResidualCacheExperts',
        '[ValidateRange(40, 4096)][int]$NestedResidualCacheExperts = 320',
        '-ForceOpenRouter',
        'all_layer = [ordered]@{ first = 3; last = 42; count = 40 }',
        'base_storage = [ordered]@',
        'pageable_enabled = $true',
        'pinned_gib_requested',
        'pinned_entries',
        'pinned_bytes',
        'pinned_hits',
        'pinned_h2d_bytes',
        'pageable_entries',
        'pageable_bytes',
        'pageable_hits',
        'pageable_h2d_bytes',
        'invariant_failures',
        'residual_cache = [ordered]@',
        'partitioned = 1',
        'layer_slots_min',
        'layer_slots_max',
        'result_sha256',
        'gpu_join = [ordered]@',
        'gpu_cache = [ordered]@',
        'exactness = [ordered]@',
        'reconstruction_verify = $true',
        'verify_mismatches -ne 0',
        'nested_residual_mismatches -ne 0',
        'gpu_join_failures -ne 0',
        'cpu_reconstruct_calls -ne 0',
        'native_h2d_bytes -ne 0',
        'moe_overlapped_io_fallbacks -ne 0',
        'machine_quiescence',
        'exact_content_sha256',
        '-BudgetGB',
        '-ReserveMB',
        '-PrefillMassWrap',
        '-ComposePrefillMassTiering',
        '-ComposePrefillMassOpenRouter',
        '-ComposePrefillMassReserveSlots',
        '-ArenaWrapTrustWorkerChecksum',
        '-ArenaWrapSourceParts',
        '-ArenaWrapUnlockSourceRanges',
        '-ArenaWrapUnlockWaveGiB',
        '-DisableQ8F16Cache',
        '-EmbedRowStaging',
        '-ReapPrefetchThreads',
        '-ExpertCacheN',
        '-ExpertCacheReserveGB',
        '-ExpertCachePolicy',
        '-GpuResidentRoutes',
        '-RouteNoDefaultSync',
        '-ExpertTiering',
        '-ExpertTierPolicy',
        '-ExpertTierClockCalls',
        '-ExpertTierReplacementBudget',
        '-ExpertTierMinFrequency',
        '-ExpertTierHysteresis',
        '-SplitFused',
        '[string]$Result.nested_residual_sidecar',
        'G128_SAFETY_RECEIPT=',
        'G128_SAFETY_RECEIPT_SHA256=')) {
    Require-Text $safety $needle 'safety receipt and structural gate'
}

foreach ($needle in @(
        '[string]$G128SafetyReceipt',
        '[string]$ExpectedG128SafetyReceiptSHA256',
        '[string]$NestedResidualSidecar',
        '[string]$ExpectedNestedResidualSidecarSHA256',
        '[UInt64]$ExpectedNestedResidualSidecarBytes',
        '[string]$ExpectedNestedResidualPayloadSHA256',
        '[ValidateRange(3, 20)][int]$Repeats = 3',
        'Assert-G128SafetyReceipt',
        'Get-G128CurrentBuildContract',
        'G128 sidecar SHA-256 mismatch',
        'G128 safety receipt sidecar provenance mismatch',
        'G128 safety result sidecar provenance mismatch',
        'G128 safety receipt is not from the current build/harness',
        'G128 safety result SHA-256 mismatch',
        'G128 safety/build contract changed before A/B planning',
        'G128 control unexpectedly enabled nested-residual runtime',
        'G128 candidate storage/runtime contract failed',
        'schema = ''g128_all_layer_nested_storage_ab_result_v1''',
        'schema = ''g128_all_layer_nested_storage_ab_plan_v1''',
        'claim_scope = ''n_ge_3_ab_only_no_claim_from_n1''',
        'n1_claims_forbidden = $true',
        'Start-Process',
        '-WindowStyle Hidden',
        '-NoWarmup',
        '-ForceOpenRouter',
        '-NestedResidualGpuCache',
        '-NestedResidualGpuJoin',
        '-NestedResidualGpuJoinResidualCache',
        '-NestedResidualPageableBase',
        '-NestedResidualBasePinnedGiB',
        '-NestedResidualCachePageable',
        '-NestedResidualCacheExperts',
        '-NestedResidualGpuJoinSafetyReceipt',
        '-ExpectedNestedResidualGpuJoinSafetyReceiptSHA256',
        '-ArenaWrapSourceParts',
        '-PrefillMassWrap',
        '-ComposePrefillMassOpenRouter',
        '-GpuResidentRoutes',
        '-RouteNoDefaultSync',
        '-SplitFused',
        'nested_residual_cache_layer_partitioned',
        'nested_residual_cache_layer_slots_min',
        'nested_residual_cache_layer_slots_max',
        'e2e_tps_mean',
        'e2e_tps_median',
        'server_decode_tps_mean',
        'server_decode_tps_median',
        'ttft_seconds_mean',
        'ttft_seconds_median',
        'prefill_seconds_mean',
        'prefill_seconds_median',
        'exactness = [ordered]@',
        'all_rows_exact = $true',
        'contamination = [ordered]@',
        'all_rows_uncontaminated = $true')) {
    Require-Text $runner $needle 'A/B receipt validation and aggregate'
}
Require-Text $runner `
    '$exact = ([string]$sample.content_sha256 -ieq $expectedContentSHA)' `
    'A/B exactness uses equality'
Require-Text $runner `
    'if (-not $exact)' `
    'A/B exactness fails on mismatch'
Require-Text $runner `
    '[string]$json.nested_residual_sidecar' `
    'A/B candidate uses result sidecar field'
Require-Text $runner `
    '[string]$safetyResult.nested_residual_sidecar' `
    'A/B safety-result uses result sidecar field'
foreach ($badNeedle in @(
        '$exact = ([string]$sample.content_sha256 -ine $expectedContentSHA)',
        'nested_residual_sidecar_path')) {
    if ($runner.IndexOf($badNeedle, [StringComparison]::Ordinal) -ge 0 -or
        $safety.IndexOf($badNeedle, [StringComparison]::Ordinal) -ge 0) {
        throw "G128 regression marker present after fix: $badNeedle"
    }
}

foreach ($needle in @(
        '"schema":  "g128_all_layer_nested_storage_safety_plan_v1"',
        '"receipt_schema":  "ds4_g128_all_layer_nested_storage_safety_v1"',
        '"n":  1',
        '"first":  3',
        '"last":  42',
        '"count":  40',
        '"pinned_gib_requested":  28',
        '"experts":  320',
        '"partitioned":  1',
        '"-NestedResidualVerifyReconstruction"',
        '"-NestedResidualPageableBase"',
        '"-NestedResidualBasePinnedGiB"',
        '"-NestedResidualCachePageable"',
        '"-NestedResidualCacheExperts"',
        '"-ForceOpenRouter"',
        '"-PrefillMassWrap"',
        '"-ComposePrefillMassTiering"',
        '"-ComposePrefillMassOpenRouter"',
        '"-ComposePrefillMassReserveSlots"',
        '"-GpuResidentRoutes"',
        '"-SplitFused"')) {
    $whatIf = @(& $safetyRunnerPath -Tag 'g128_safety_static_probe' `
        -NestedResidualSidecar $dummySidecar `
        -ExpectedNestedResidualSidecarSHA256 $dummySidecarSHA `
        -ExpectedNestedResidualSidecarBytes $dummySidecarBytes `
        -ExpectedNestedResidualPayloadSHA256 $dummySidecarPayloadSHA `
        -WhatIf) -join "`n"
    if ($whatIf.IndexOf($needle, [StringComparison]::Ordinal) -lt 0) {
        throw "G128 safety WhatIf output missing marker: $needle"
    }
}

$dummyReceipt = 'C:\g128-static\immutable-receipt.json'
$dummyReceiptSHA = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
$abWhatIf = @(& $abRunnerPath -Tag 'g128_ab_static_probe' `
    -G128SafetyReceipt $dummyReceipt `
    -ExpectedG128SafetyReceiptSHA256 $dummyReceiptSHA `
    -NestedResidualSidecar $dummySidecar `
    -ExpectedNestedResidualSidecarSHA256 $dummySidecarSHA `
    -ExpectedNestedResidualSidecarBytes $dummySidecarBytes `
    -ExpectedNestedResidualPayloadSHA256 $dummySidecarPayloadSHA `
    -InterChildCooldownSec 0 -WhatIf) -join "`n"
foreach ($needle in @(
        '"schema":  "g128_all_layer_nested_storage_ab_plan_v1"',
        '"repeats_per_arm":  3',
        '"child_count":  6',
        '"no_warmup":  true',
        '"independent_processes":  true',
        '"g128_safety_receipt":  "C:\\g128-static\\immutable-receipt.json"',
        '"g128_safety_receipt_sha256":  "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"',
        '"nested_residual_sidecar":  "C:\\g128-static\\all-layer-sidecar.ds4nr"',
        '"nested_residual_sidecar_bytes":  123456789',
        '"nested_residual_sidecar_sha256":  "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"',
        '"nested_residual_payload_sha256":  "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"',
        '"control_dynamic_arena_gib":  30',
        '"candidate_dynamic_arena_gib":  2',
        '"nested_residual_base_pinned_gib":  28',
        '"arm":  "control"',
        '"arm":  "candidate"',
        '"order_position":  1',
        '"order_position":  6',
        '"-NoWarmup"',
        '"-NestedResidualGpuJoinSafetyReceipt"',
        '"-ExpectedNestedResidualGpuJoinSafetyReceiptSHA256"')) {
    if ($abWhatIf.IndexOf($needle, [StringComparison]::Ordinal) -lt 0) {
        throw "G128 A/B WhatIf output missing marker: $needle"
    }
}

$abPlan = $abWhatIf | ConvertFrom-Json
$controlChildren = @($abPlan.children | Where-Object { $_.arm -eq 'control' })
$candidateChildren = @($abPlan.children | Where-Object { $_.arm -eq 'candidate' })
if ($controlChildren.Count -ne 3 -or $candidateChildren.Count -ne 3) {
    throw 'G128 A/B WhatIf must plan n>=3 independent control/candidate children'
}
foreach ($child in @($controlChildren + $candidateChildren)) {
    $args = @($child.harness_arguments)
    foreach ($requiredCommonFlag in @(
            '-ArenaWrapSourceParts',
            '-ArenaWrapUnlockSourceRanges',
            '-PrefillMassWrap',
            '-ComposePrefillMassOpenRouter',
            '-ComposePrefillMassTiering',
            '-ComposePrefillMassReserveSlots',
            '-ForceOpenRouter',
            '-GpuResidentRoutes',
            '-RouteNoDefaultSync',
            '-SplitFused')) {
        if (-not ($args -contains $requiredCommonFlag)) {
            throw "G128 child missing common full/open SOTA flag: $requiredCommonFlag"
        }
    }
}
foreach ($child in $controlChildren) {
    $args = @($child.harness_arguments)
    foreach ($forbiddenControlFlag in @(
            '-NestedResidualSidecar',
            '-NestedResidualPageableBase',
            '-NestedResidualCachePageable',
            '-NestedResidualGpuJoinSafetyReceipt',
            '-ExpectedNestedResidualGpuJoinSafetyReceiptSHA256',
            '-AllowNestedResidualBenchmarkSuite',
            '-OuterNestedResidualBenchmarkProcessCount')) {
        if ($args -contains $forbiddenControlFlag) {
            throw "G128 control child contains candidate-only flag: $forbiddenControlFlag"
        }
    }
}
foreach ($child in $candidateChildren) {
    $args = @($child.harness_arguments)
    foreach ($requiredCandidateFlag in @(
            '-NestedResidualSidecar',
            '-ExpectedNestedResidualSidecarSHA256',
            '-ExpectedNestedResidualPayloadSHA256',
            '-NestedResidualPageableBase',
            '-NestedResidualBasePinnedGiB',
            '-NestedResidualCachePageable',
            '-NestedResidualCacheExperts',
            '-AllowNestedResidualBenchmarkSuite',
            '-OuterNestedResidualBenchmarkProcessCount',
            '-NestedResidualGpuJoinSafetyReceipt',
            '-ExpectedNestedResidualGpuJoinSafetyReceiptSHA256')) {
        if (-not ($args -contains $requiredCandidateFlag)) {
            throw "G128 candidate child missing required flag: $requiredCandidateFlag"
        }
    }
}

foreach ($forbidden in @(
        '-ReapMaskFile',
        '-StaticMask',
        '-ClosedRouter',
        '-Bake',
        '-Spex',
        'Q1_0ExpertSidecar',
        'Iq1SExpertSidecar',
        'layers3-16-29-42')) {
    if ($safety.IndexOf($forbidden, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        $runner.IndexOf($forbidden, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw "G128 forbidden runner marker present: $forbidden"
    }
}
if ($runner.IndexOf('-NestedResidualVerifyReconstruction',
        [StringComparison]::OrdinalIgnoreCase) -ge 0) {
    throw 'G128 A/B candidate/control must not pay reconstruction verification overhead'
}

Write-Output 'test_g128_all_layer_nested_storage_runner_static.ps1: PASS'
