$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$cudaPath = Join-Path $root 'ds4_cuda.cu'

if (-not (Test-Path -LiteralPath $cudaPath -PathType Leaf)) {
    throw "G128 cache partition required file missing: $cudaPath"
}

$cuda = Get-Content -LiteralPath $cudaPath -Raw

function Require-Text {
    param([string]$Text, [string]$Needle, [string]$Contract)
    if ($Text.IndexOf($Needle, [StringComparison]::Ordinal) -lt 0) {
        throw "G128 cache partition contract missing ($Contract): $Needle"
    }
}

function Require-Regex {
    param([string]$Text, [string]$Pattern, [string]$Contract)
    if (-not [regex]::IsMatch($Text, $Pattern)) {
        throw "G128 cache partition contract missing ($Contract regex): $Pattern"
    }
}

function Get-RegexGroup {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Contract
    )
    $match = [regex]::Match($Text, $Pattern)
    if (-not $match.Success) {
        throw "G128 cache partition block missing ($Contract regex): $Pattern"
    }
    return $match.Groups[1].Value
}

foreach ($needle in @(
        'uint32_t cache_layer_begin[CUDA_NESTED_RESIDUAL_LAYER_COUNT]',
        'uint32_t cache_layer_capacity[CUDA_NESTED_RESIDUAL_LAYER_COUNT]',
        'uint8_t cache_layer_partitioned',
        'state.cache_layer_begin[layer] = slot_cursor',
        'state.cache_layer_capacity[layer] = layer_capacity',
        'state.cache_layer_partitioned = 1u')) {
    Require-Text $cuda $needle 'partition state fields and writes'
}

Require-Regex $cuda `
    '(?s)if\s*\(\s*state\.cache_pageable\s*&&\s*state\.all_layer_storage\s*\)\s*\{.*?if\s*\(\s*cache_capacity\s*<\s*nested_residual_all_layer_count\s*\).*?one slot per ready layer.*?return 0;' `
    'pageable all-layer capacity guard'

Require-Regex $cuda `
    '(?s)const uint32_t slots_per_layer\s*=\s*cache_capacity\s*/\s*nested_residual_all_layer_count\s*;.*?const uint32_t extra_slots\s*=\s*cache_capacity\s*%\s*nested_residual_all_layer_count\s*;.*?const uint32_t layer_capacity\s*=\s*slots_per_layer\s*\+\s*\(\s*ready_cursor\s*<\s*extra_slots\s*\?\s*1u\s*:\s*0u\s*\).*?slot_cursor\s*\+=\s*layer_capacity\s*;.*?ready_cursor\+\+;.*?if\s*\(\s*slot_cursor\s*!=\s*cache_capacity\s*\|\|\s*ready_cursor\s*!=\s*nested_residual_all_layer_count\s*\).*?partition invariant failed' `
    'quotient remainder partition covers cache capacity and ready layers'

$scanRangeBody = Get-RegexGroup $cuda `
    '(?s)static int cuda_nested_residual_cache_scan_range\([^)]*\)\s*\{(.*?)\n\}' `
    'cache scan range helper'
foreach ($needle in @(
        'uint32_t begin = 0',
        'uint32_t count = state.cache_capacity',
        'if (state.cache_layer_partitioned)',
        'begin = state.cache_layer_begin[layer_index]',
        'count = state.cache_layer_capacity[layer_index]',
        'count == 0 || begin > state.cache_capacity',
        'count > state.cache_capacity - begin',
        '*begin_out = begin',
        '*count_out = count')) {
    Require-Text $scanRangeBody $needle 'cache scan range helper'
}

$resolverBody = Get-RegexGroup $cuda `
    '(?s)static int cuda_nested_residual_resolve_residual_slot_locked\([^)]*\)\s*\{(.*?)\n\}\s*\nstatic int cuda_nested_residual_join_to_device_exact' `
    'residual-cache resolver'

foreach ($needle in @(
        'uint32_t scan_begin = 0',
        'uint32_t scan_count = 0',
        'state, layer_index, &scan_begin, &scan_count',
        '(uint32_t)cached < scan_begin',
        '(uint32_t)cached >= scan_begin + scan_count',
        'for (uint32_t offset = 0; offset < scan_count; offset++)',
        'const uint32_t i = scan_begin + offset',
        'victim = i',
        'if (state.cache_layer_partitioned && slot.layer != layer_index)',
        'state.cache_by_layer_expert[map_index] = (int32_t)victim')) {
    Require-Text $resolverBody $needle 'residual-cache partition confinement'
}

if ([regex]::IsMatch(
        $resolverBody,
        'for\s*\(\s*uint32_t\s+i\s*=\s*0\s*;\s*i\s*<\s*state\.cache_capacity\s*;')) {
    throw 'G128 residual-cache resolver must not scan the global cache capacity'
}

Require-Regex $cuda `
    '(?s)static void cuda_nested_residual_note_cache_invariant_failure\(\s*cuda_nested_residual_state &state\s*\)\s*\{.*?state\.residual_cache_invariant_failures\+\+;.*?if\s*\(\s*state\.cache_pageable\s*\)\s*state\.cache_pageable_invariant_failures\+\+;' `
    'pageable invariant failures increment through helper'

Require-Regex $cuda `
    '(?s)\[nested-residual-cache-pageable\].*?partitioned=%u layer_slots_min=%u layer_slots_max=%u.*?\(unsigned\)state\.cache_layer_partitioned.*?nested_residual_cache_layer_slots_min.*?nested_residual_cache_layer_slots_max' `
    'pageable cache summary exposes partitioned and min/max'

function Test-PartitionSimulation {
    param(
        [uint32]$Capacity,
        [uint32]$Layers,
        [uint32]$ExpectedMin,
        [uint32]$ExpectedMax
    )
    $slotsPerLayer = [uint32][Math]::Floor($Capacity / $Layers)
    $extraSlots = [uint32]($Capacity % $Layers)
    $sum = [uint32]0
    $min = [uint32]::MaxValue
    $max = [uint32]0
    for ($layer = 0; $layer -lt $Layers; $layer++) {
        $layerCapacity = [uint32]($slotsPerLayer + $(if ($layer -lt $extraSlots) { 1 } else { 0 }))
        if ($layerCapacity -eq 0) {
            throw "G128 partition simulation produced zero slot: capacity=$Capacity layer=$layer"
        }
        $sum += $layerCapacity
        if ($layerCapacity -lt $min) { $min = $layerCapacity }
        if ($layerCapacity -gt $max) { $max = $layerCapacity }
    }
    if ($sum -ne $Capacity) {
        throw "G128 partition simulation sum mismatch: capacity=$Capacity sum=$sum"
    }
    if ($min -ne $ExpectedMin -or $max -ne $ExpectedMax) {
        throw "G128 partition simulation min/max mismatch: capacity=$Capacity min=$min max=$max expected=$ExpectedMin/$ExpectedMax"
    }
}

Test-PartitionSimulation -Capacity 40 -Layers 40 -ExpectedMin 1 -ExpectedMax 1
Test-PartitionSimulation -Capacity 320 -Layers 40 -ExpectedMin 8 -ExpectedMax 8
Test-PartitionSimulation -Capacity 4096 -Layers 40 -ExpectedMin 102 -ExpectedMax 103

$tokens = $null
$errors = $null
[Management.Automation.Language.Parser]::ParseFile(
    $PSCommandPath, [ref]$tokens, [ref]$errors) | Out-Null
if ($errors -and $errors.Count -gt 0) {
    throw "G128 cache partition PowerShell parse failed: $($errors[0].Message)"
}

Write-Output 'test_g128_cache_partition_static.ps1: PASS'
