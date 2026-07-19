$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$protocolPath = Join-Path $root 'G128_ALL_LAYER_NESTED_STORAGE_PROTOCOL.md'
$harnessPath = Join-Path $root 'g7_measure.ps1'
$cudaPath = Join-Path $root 'ds4_cuda.cu'

foreach ($path in @($protocolPath, $harnessPath, $cudaPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "G128 required file missing: $path"
    }
}

$tokens = $null
$errors = $null
[Management.Automation.Language.Parser]::ParseFile(
    $harnessPath, [ref]$tokens, [ref]$errors) | Out-Null
if ($errors -and $errors.Count -gt 0) {
    throw "G128 PowerShell parse failed for $harnessPath`: $($errors[0].Message)"
}

$protocol = Get-Content -LiteralPath $protocolPath -Raw
$harness = Get-Content -LiteralPath $harnessPath -Raw
$cuda = Get-Content -LiteralPath $cudaPath -Raw
$runtime = $cuda
$allSource = $protocol + "`n" + $harness + "`n" + $runtime

function Require-Text {
    param([string]$Text, [string]$Needle, [string]$Contract)
    if ($Text.IndexOf($Needle, [StringComparison]::Ordinal) -lt 0) {
        throw "G128 contract missing ($Contract): $Needle"
    }
}

function Require-Regex {
    param([string]$Text, [string]$Pattern, [string]$Contract)
    if (-not [regex]::IsMatch($Text, $Pattern)) {
        throw "G128 contract missing ($Contract regex): $Pattern"
    }
}

foreach ($needle in @(
        'G128 All-Layer Nested Storage Protocol',
        'router is full/open',
        'no REAP mask, no static mask, no closed candidate set',
        'layers `3..42`',
        'DS4_NESTED_RESIDUAL_PAGEABLE_BASE=1',
        'DS4_NESTED_RESIDUAL_BASE_PINNED_GIB=<0..30>',
        'DS4_NESTED_RESIDUAL_CACHE_PAGEABLE=1',
        'DS4_NESTED_RESIDUAL_CACHE_EXPERTS=<1..4096>',
        'every covered selected route must reconstruct the authoritative native expert',
        'G128 must not use a base-only approximation',
        '[nested-residual-base-storage]',
        '[nested-residual-cache-pageable]',
        'nested_residual_base_pinned_h2d_bytes',
        'nested_residual_base_pageable_h2d_bytes',
        'nested_residual_cache_pinned_h2d_bytes',
        'nested_residual_cache_pageable_h2d_bytes',
        'structural `n=1` safety run',
        'before any `n>=3` benchmark',
        'No SOTA, TTFT, t/s or quality verdict may be taken',
        'This protocol file does not create a benchmark')) {
    Require-Text $protocol $needle 'protocol text'
}

$n1Index = $protocol.IndexOf('structural `n=1` safety run',
    [StringComparison]::Ordinal)
$n3Index = $protocol.IndexOf('before any `n>=3` benchmark',
    [StringComparison]::Ordinal)
if ($n1Index -lt 0 -or $n3Index -lt 0 -or $n1Index -gt $n3Index) {
    throw 'G128 protocol must impose n=1 safety before any n>=3 benchmark'
}

foreach ($needle in @(
        '[switch]$NestedResidualPageableBase',
        '[double]$NestedResidualBasePinnedGiB',
        '[switch]$NestedResidualCachePageable',
        '[int]$NestedResidualCacheExperts',
        'DS4_NESTED_RESIDUAL_PAGEABLE_BASE',
        'DS4_NESTED_RESIDUAL_BASE_PINNED_GIB',
        'DS4_NESTED_RESIDUAL_CACHE_PAGEABLE',
        'DS4_NESTED_RESIDUAL_CACHE_EXPERTS',
        'Nested residual pageable base requires NestedResidualGpuCache and NestedResidualGpuJoin',
        'Nested residual base pinned GiB budget must be provided when pageable base is enabled',
        '[ValidateRange(0, 4096)][int]$NestedResidualCacheExperts',
        'Nested residual cache experts must fail closed above 64 unless NestedResidualCachePageable is enabled',
        'NestedResidualCachePageable requires NestedResidualGpuJoinResidualCache',
        'Nested residual all-layer storage requires full/open router and no mask',
        'Nested residual all-layer storage requires exact reconstruction verification for safety',
        'Nested residual base storage telemetry requires exactly one summary',
        'Nested residual residual-cache pageable telemetry requires exactly one summary',
        'Nested residual base storage semantic markers are inconsistent',
        'Nested residual cache pageable semantic markers are inconsistent',
        'Nested residual pageable-base telemetry appeared while feature was disabled',
        'Nested residual cache pageable telemetry appeared while feature was disabled',
        'nested_residual_base_pinned_entries',
        'nested_residual_base_pinned_bytes',
        'nested_residual_base_pinned_hits',
        'nested_residual_base_pinned_h2d_bytes',
        'nested_residual_base_pageable_entries',
        'nested_residual_base_pageable_bytes',
        'nested_residual_base_pageable_hits',
        'nested_residual_base_pageable_h2d_bytes',
        'nested_residual_cache_pinned_entries',
        'nested_residual_cache_pinned_bytes',
        'nested_residual_cache_pinned_hits',
        'nested_residual_cache_pinned_h2d_bytes',
        'nested_residual_cache_pageable_entries',
        'nested_residual_cache_pageable_bytes',
        'nested_residual_cache_pageable_hits',
        'nested_residual_cache_pageable_h2d_bytes',
        'nested_residual_storage_invariant_failures',
        'nested_residual_cache_pageable_invariant_failures',
        'structural_safety_only_no_sota_no_quality_verdict')) {
    Require-Text $harness $needle 'future harness parser/diagnostics/receipt'
}

foreach ($needle in @(
        'DS4_NESTED_RESIDUAL_PAGEABLE_BASE',
        'DS4_NESTED_RESIDUAL_BASE_PINNED_GIB',
        'DS4_NESTED_RESIDUAL_CACHE_PAGEABLE',
        'DS4_NESTED_RESIDUAL_CACHE_EXPERTS',
        'nested_residual_base_pinned_entries',
        'nested_residual_base_pageable_entries',
        'nested_residual_cache_pinned_entries',
        'nested_residual_cache_pageable_entries',
        'nested_residual_all_layer_first_layer',
        'nested_residual_all_layer_last_layer',
        'nested_residual_all_layer_count',
        'all-layer nested sidecar coverage must be exactly',
        'layers 3..42 observed_first=%u observed_last=%u',
        'cache_pageable ? 4096u : 64u',
        'invalid DS4_NESTED_RESIDUAL_CACHE_EXPERTS',
        'nested residual base storage contract invalid')) {
    Require-Text $runtime $needle 'future runtime symbols/diagnostics'
}

Require-Regex $runtime `
    '(?s)\[nested-residual-base-storage\].*pinned_entries=.*pinned_bytes=.*pinned_hits=.*pinned_h2d_bytes=.*pageable_entries=.*pageable_bytes=.*pageable_hits=.*pageable_h2d_bytes=.*invariant_failures=' `
    'base pinned/pageable telemetry'
Require-Regex $runtime `
    '(?s)\[nested-residual-cache-pageable\].*pinned_entries=.*pinned_bytes=.*pinned_hits=.*pinned_h2d_bytes=.*pageable_entries=.*pageable_bytes=.*pageable_hits=.*pageable_h2d_bytes=.*cached_join_calls=.*invariant_failures=.*mapped=0 router=open exact=1' `
    'residual-cache pageable telemetry'

Write-Output 'test_g128_all_layer_nested_storage_static.ps1: PASS'
