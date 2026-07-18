$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$runner = Join-Path $root "g111_q1_sparse_snapshot_ab.ps1"
$harness = Join-Path $root "g7_measure.ps1"
$resultPath = Join-Path $root "g7_runs\g111_q1_sparse_snapshot_ab_result.json"
$safetyPath = Join-Path $root "g7_runs\g111_q1_sparse_snapshot_safety_result.json"
$longResultPath = Join-Path $root "g7_runs\g111_q1_sparse_snapshot_long_cyberpunk_result.json"
$longSafetyPath = Join-Path $root "g7_runs\g111_q1_sparse_snapshot_long_cyberpunk_safety_result.json"

foreach ($path in @($runner, $harness)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "G111 static test missing file: $path"
    }
}
$tokens = $null
$errors = $null
[Management.Automation.Language.Parser]::ParseFile($runner, [ref]$tokens, [ref]$errors) | Out-Null
if ($errors -and $errors.Count -gt 0) {
    throw "G111 runner parse failed: $($errors[0].Message)"
}
$text = Get-Content -LiteralPath $runner -Raw
foreach ($needle in @(
    '[string]$ModelPath', '[string]$Q1SidecarPath',
    '[string]$ExpectedQ1SidecarSHA256', '[UInt64]$ExpectedQ1SidecarBytes',
    '[switch]$StaticCheckOnly', '$candidateArenaGiB = if ($LongCyberpunk) { 30.0 } else { 15.0 }',
    '$controlArenaGiB = 30.0', '"-Q1_0SnapshotBacking"', '"-Q1_0PageableOverflow"',
    '"-Q1_0LayerFirst", "0"', '"-Q1_0LayerLast", "42"',
    '"-PrefillMassWrap"', '"-ComposePrefillMassTiering"',
    '"-PrefillVramSeedPerLayer", ([string]$seedPerLayer)',
    'exact_iq2_vram_seed_required',
    'zero_iq2_vram_cache_miss_required',
    'gpu_resident_routes_cache_hits',
    'gpu_resident_routes_cache_misses',
    '"-AllowBenchmarkVerifiedReceiptReuse"',
    'benchmark_verified_receipt_lock_proof_observed',
    '"${tagPrefix}_control_iq2_${seedTag}_x2"',
    '"current-build IQ2 snapshot $seedTag (G73-derived)"',
    'control_is_canonical_g73 = $false',
    'historical_g73_decode_tps = 4.986667',
    '"${tagPrefix}_candidate_q1_sparse_snapshot_safety_n1"',
    '"control,candidate,candidate,control,control,candidate"',
    'q1_0_resident_misses', 'q1_0_direct_pread_fallbacks',
    'q1_0_direct_pread_bytes', 'snapshot_backing_misses',
    'ssd_bytes', 'quality_claim_allowed = $false',
    'sota_claim_allowed = $false')) {
    if ($text -notmatch [regex]::Escape($needle)) {
        throw "G111 runner static marker missing: $needle"
    }
}
if ($text -match 'ds4_server\.exe' -or $text -match 'Start-Process\s+.*ds4') {
    throw "G111 runner must delegate launches only through g7_measure.ps1"
}

$beforeProcesses = @(Get-Process -Name "ds4_server", "ds4-server", "ds4" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
$beforeArtifacts = @{}
foreach ($path in @($resultPath, $safetyPath, $longResultPath, $longSafetyPath)) {
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $beforeArtifacts[$path] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    } else {
        $beforeArtifacts[$path] = ""
    }
}
$stdout = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $runner -StaticCheckOnly -ModelPath "C:\g111-static-model.gguf" -ExpectedModelSHA256 ("a" * 64) -Q1SidecarPath "C:\g111-static-q1.gguf" -ExpectedQ1SidecarSHA256 ("b" * 64) -ExpectedQ1SidecarBytes 1 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "G111 StaticCheckOnly failed: $($stdout -join ' | ')"
}
$receipt = ($stdout -join [Environment]::NewLine) | ConvertFrom-Json
if ([string]$receipt.schema -ne "g111_q1_sparse_snapshot_ab_static_v1" -or
    -not [bool]$receipt.static_check_only -or
    -not [bool]$receipt.no_build_gpu_or_ds4_launch -or
    [string]$receipt.protocol.matrix_order -ne "control,candidate,candidate,control,control,candidate" -or
    [double]$receipt.control.dynamic_arena_gib -ne 30.0 -or
    [int]$receipt.control.prefill_vram_seed_per_layer -ne 8 -or
    [bool]$receipt.control.historical_g73_reference_only -ne $true -or
    [bool]$receipt.control.historical_g73_direct_comparison_eligible -ne $false -or
    [double]$receipt.candidate.dynamic_arena_gib -ne 15.0 -or
    [int]$receipt.candidate.prefill_vram_seed_per_layer -ne 8 -or
    -not [bool]$receipt.candidate.exact_iq2_vram_seed_required -or
    -not [bool]$receipt.candidate.zero_iq2_vram_cache_miss_required -or
    -not [bool]$receipt.candidate.q1_0_snapshot_backing -or
    [string]$receipt.candidate.layers -ne "0..42" -or
    -not [bool]$receipt.candidate.zero_q1_miss_required -or
    -not [bool]$receipt.candidate.zero_direct_pread_required -or
    -not [bool]$receipt.candidate.zero_ssd_required) {
    throw "G111 static receipt contract mismatch"
}
$longStdout = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $runner -StaticCheckOnly -LongCyberpunk -ModelPath "C:\g111-static-model.gguf" -ExpectedModelSHA256 ("a" * 64) -Q1SidecarPath "C:\g111-static-q1.gguf" -ExpectedQ1SidecarSHA256 ("b" * 64) -ExpectedQ1SidecarBytes 1 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "G111 LongCyberpunk StaticCheckOnly failed: $($longStdout -join ' | ')"
}
$longReceipt = ($longStdout -join [Environment]::NewLine) | ConvertFrom-Json
if ([string]$longReceipt.schema -ne "g111_q1_sparse_snapshot_long_cyberpunk_static_v1" -or
    [string]$longReceipt.mode -ne "long_cyberpunk_full_q1" -or
    [int]$longReceipt.context_requested -ne 8192 -or
    [int]$longReceipt.prefill_chunk_requested -ne 256 -or
    [int]$longReceipt.max_tokens_requested -ne 4000 -or
    [string]$longReceipt.stop_sequence -ne "</html>" -or
    [int]$longReceipt.control.prefill_vram_seed_per_layer -ne 7 -or
    [int]$longReceipt.candidate.prefill_vram_seed_per_layer -ne 7 -or
    [int]$longReceipt.candidate.expected_snapshot_entries -ne 11008 -or
    -not [bool]$longReceipt.candidate.full_q1_routed_residency -or
    [double]$longReceipt.candidate.dynamic_arena_gib -ne 30.0 -or
    -not [bool]$longReceipt.candidate.q1_0_pageable_overflow -or
    [double]$longReceipt.temperature -ne 0 -or
    [bool]$longReceipt.think -ne $false -or
    [string]$longReceipt.protocol.matrix_order -ne "candidate,candidate,candidate" -or
    [bool]$longReceipt.protocol.control_hash_frozen_from_safety -or
    -not [bool]$longReceipt.protocol.candidate_hash_frozen_from_safety) {
    throw "G111 long Cyberpunk static receipt contract mismatch"
}
foreach ($path in @($resultPath, $safetyPath, $longResultPath, $longSafetyPath)) {
    $after = if (Test-Path -LiteralPath $path -PathType Leaf) {
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    } else { "" }
    if ($after -ne $beforeArtifacts[$path]) {
        throw "G111 StaticCheckOnly changed runtime artifact: $path"
    }
}
$afterProcesses = @(Get-Process -Name "ds4_server", "ds4-server", "ds4" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
if ((Compare-Object $beforeProcesses $afterProcesses | Measure-Object).Count -ne 0) {
    throw "G111 StaticCheckOnly changed DS4 process state"
}
Write-Host "G111 sparse snapshot runner static contract PASS"
