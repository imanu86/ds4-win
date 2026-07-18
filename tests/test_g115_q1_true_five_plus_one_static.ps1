$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
$cudaText = Get-Content -LiteralPath (Join-Path $repo 'ds4_cuda.cu') -Raw
$coreText = Get-Content -LiteralPath (Join-Path $repo 'ds4.c') -Raw
$measureText = Get-Content -LiteralPath (Join-Path $repo 'g7_measure.ps1') -Raw

function Require-Text([string]$Text, [string]$Needle, [string]$Contract) {
    if (-not $Text.Contains($Needle)) {
        throw "G115 contract missing ($Contract): $Needle"
    }
}

foreach ($needle in @(
    'DS4_Q1_0_DUAL_SPARSE_COMPANION',
    'DS4_Q1_0_MIXED_COLD_ONE',
    'cuda_q1_0_dual_sparse_stage(',
    '&g_q1_0_sidecar_file, destination,',
    'cuda_q1_0_dual_sparse_commit(',
    'candidate_hash != g_q1_0_dual_sparse_snapshot.candidate_fnv1a64',
    'g_q1_0_dual_sparse_snapshot.primary_generation !=',
    'g_q1_0_dual_sparse_snapshot.q1_generation !=',
    'cuda_q1_0_dual_sparse_pair_contains(',
    '!cuda_q1_0_dual_sparse_companion_requested() &&',
    'cold_slot = 0u;',
    'weights_host[route] < weights_host[cold_slot]',
    'hot_count != CUDA_MOE_ROUTE_COUNT - 1u || cold_count != 1u',
    'g_q1_0_mixed_cold_one_invariant_failures++')) {
    Require-Text $cudaText $needle 'resident 5+1 runtime'
}

foreach ($needle in @(
    'q1_0_dual_sparse_companion_requested()',
    'q1_0_mixed_cold_one_requested()',
    'q1_0_mixed_cold_one > 0 && q1_0_dual_sparse_companion <= 0')) {
    Require-Text $coreText $needle 'session fail-closed gating'
}

foreach ($needle in @(
    '[switch]$Q1_0DualSparseCompanion',
    '[switch]$Q1_0MixedColdOne',
    'DS4_Q1_0_DUAL_SPARSE_COMPANION',
    'DS4_Q1_0_MIXED_COLD_ONE',
    'Q1 layers 0..42 so the companion matches the complete prefill candidate mask',
    '($DynamicArenaGiB * 1.5) + 2.0',
    '-DualSparseRequested ([bool]$Q1_0DualSparseCompanion)',
    '$q1_0MixedTelemetry.cold_one_hot_routes -ne',
    '$q1_0MixedTelemetry.cold_one_q1_routes -ne',
    '$mixedPrimaryColdAvoided = [UInt64](',
    '$q1_0DualSparseFailures -ne 0')) {
    Require-Text $measureText $needle 'measurement gate'
}

Write-Host 'test_g115_q1_true_five_plus_one_static.ps1: PASS'
