$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$core = Get-Content -LiteralPath (Join-Path $root "ds4.c") -Raw
$cuda = Get-Content -LiteralPath (Join-Path $root "ds4_cuda.cu") -Raw
$header = Get-Content -LiteralPath (Join-Path $root "ds4_gpu.h") -Raw
$harness = Get-Content -LiteralPath (Join-Path $root "g7_measure.ps1") -Raw

function Require-Text {
    param([string]$Text, [string]$Needle, [string]$Contract)
    if ($Text.IndexOf($Needle, [StringComparison]::Ordinal) -lt 0) {
        throw "G111 contract missing ($Contract): $Needle"
    }
}

foreach ($needle in @(
    'getenv("DS4_Q1_0_SNAPSHOT_BACKING")',
    'getenv("DS4_Q1_0_PAGEABLE_OVERFLOW")',
    '(q1_0_snapshot_backing > 0 &&',
    '(q1_0_resident_arena > 0 || q1_0_dual_arena > 0)',
    'ds4_gpu_dynamic_arena_bind_q1_0_snapshot(',
    'Q1_0 sparse snapshot arena ready slots=%u',
    'publication=prefill-mass-wrap')) {
    Require-Text $core $needle "exclusive sparse Q1 snapshot startup"
}

foreach ($needle in @(
    'int ds4_gpu_dynamic_arena_bind_q1_0_snapshot(',
    'static int cuda_q1_0_snapshot_backing_requested(void)',
    'static int cuda_q1_0_pageable_overflow_requested(void)',
    'static cuda_dynamic_arena *cuda_q1_0_route_arena(uint32_t layer)',
    'CUDA_DYNAMIC_ARENA_BACKING_Q1_0',
    'policy=sparse-prefill-ranked iq2_host_snapshot=disabled',
    'sparse_snapshot &&',
    'target_entries > g_dynamic_arena.slots.size()',
    'replaced-by-q1-snapshot',
    'q1-sparse-snapshot',
    'pageable_slots=%llu total_slots=%llu',
    'VirtualAlloc(',
    'slot.pageable = 1')) {
    Require-Text ($header + $cuda) $needle "typed sparse Q1 backing"
}

$snapshotResolver = [regex]::Match(
    $cuda,
    '(?s)static cuda_q1_0_mixed_representation cuda_q1_0_mixed_resolve\(.*?\n\}')
if (-not $snapshotResolver.Success) {
    throw "G111 mixed resolver block missing"
}
$resolver = $snapshotResolver.Value
$vram = $resolver.IndexOf(
    'cuda_moe_tiering_has_exact_vram(layer, expert)',
    [StringComparison]::Ordinal)
$q1 = $resolver.IndexOf(
    'cuda_q1_0_resident_ram_ptrs(',
    [StringComparison]::Ordinal)
if ($vram -lt 0 -or $q1 -lt 0 -or $vram -gt $q1) {
    throw "G111 resolver must prefer exact IQ2 VRAM before Q1 snapshot RAM"
}

foreach ($needle in @(
    '[switch]$Q1_0SnapshotBacking',
    '[switch]$Q1_0PageableOverflow',
    '$env:DS4_Q1_0_SNAPSHOT_BACKING = "1"',
    '$env:DS4_Q1_0_PAGEABLE_OVERFLOW = "1"',
    '(-not $ComposePrefillMassTiering -and -not $Q1_0PureResident)',
    '$Q1_0LayerFirst -ne 0 -or $Q1_0LayerLast -ne 42',
    '-SnapshotBackingRequested ([bool]$Q1_0SnapshotBacking)')) {
    Require-Text $harness $needle "fail-closed runner wiring"
}

Write-Output "test_g111_q1_sparse_snapshot_static.ps1: PASS"
