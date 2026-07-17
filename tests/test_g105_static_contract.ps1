$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$protocol = Join-Path $root "G105_IQ1_FULL_RESIDENT_PROTOCOL.md"
$harness = Join-Path $root "g7_measure.ps1"
$runner = Join-Path $root "g105_iq1_full_resident.ps1"
$cuda = Join-Path $root "ds4_cuda.cu"

foreach ($path in @($protocol, $harness, $runner, $cuda)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "G105 required file missing: $path"
    }
}

$tokens = $null
$errors = $null
[Management.Automation.Language.Parser]::ParseFile(
    $harness, [ref]$tokens, [ref]$errors) | Out-Null
if ($errors -and $errors.Count -gt 0) {
    throw "G105 harness AST parse failed: $($errors[0].Message)"
}

$protocolText = Get-Content -LiteralPath $protocol -Raw
$harnessText = Get-Content -LiteralPath $harness -Raw
$runnerText = Get-Content -LiteralPath $runner -Raw
$cudaText = Get-Content -LiteralPath $cuda -Raw

$runnerTokens = $null
$runnerErrors = $null
[Management.Automation.Language.Parser]::ParseFile(
    $runner, [ref]$runnerTokens, [ref]$runnerErrors) | Out-Null
if ($runnerErrors -and $runnerErrors.Count -gt 0) {
    throw "G105 runner AST parse failed: $($runnerErrors[0].Message)"
}

foreach ($needle in @(
    'n=1',
    'structural gate',
    'must not be used for throughput, latency, SOTA or quality claims',
    'DS4_IQ1_S_RAM_CACHE_GB=46.875',
    'DS4_IQ1_S_RAM_CACHE_PAGEABLE=1',
    'DS4_IQ1_S_RAM_CACHE_PRELOAD_ALL=1',
    'VirtualAlloc',
    'mapped=0',
    '10240',
    '4915200',
    '50331648000',
    '30720',
    'ssd_bytes=0',
    'misses `0`',
    'evictions `0`',
    'frozen=1',
    'preload_entries=10240',
    'preload_read_calls=30720',
    'preload_ssd_bytes=50331648000',
    'MinimumAvailableGiB 54',
    'RuntimeMinimumAvailableGiB 1',
    'no throughput',
    'no quality',
    'G74',
    '31cbc6504dcb57d42aeff9dbceb3aed943bcb32dae19a2edbf552e9fd2f52eb8',
    '4aaf0f0813f4cb15ac21a88f195f4f7d2c2af797e81524935e22eea60603c6b1')) {
    if ($protocolText -notmatch [regex]::Escape($needle)) {
        throw "G105 protocol contract text missing: $needle"
    }
}

foreach ($parameter in @(
    "Iq1SRamCacheGiB",
    "Iq1SRamCachePageable",
    "Iq1SRamCachePreloadAll",
    "Iq1SLayerFirst",
    "Iq1SLayerLast",
    "Iq1SMixedColdOne",
    "Iq1SMixedGpuPlan",
    "RuntimeMinimumAvailableGiB",
    "GateKind",
    "ExpectedContentSHA256")) {
    if ($harnessText -notmatch ("\$" + [regex]::Escape($parameter) +
        "(\s|=|,|\))")) {
        throw "G105 harness lacks required parameter: -$parameter"
    }
}

foreach ($needle in @(
    '"-GateKind", "structural-safety"',
    '"-MinimumAvailableGiB", "54"',
    '"-RuntimeMinimumAvailableGiB", "1"',
    '"-Iq1SRamCacheGiB", "46.875"',
    '"-Iq1SRamCachePageable"',
    '"-Iq1SRamCachePreloadAll"',
    '"-ExpectedContentSHA256", $expectedContentSHA',
    '$Result.iq1_s_ram_cache_misses -ne 0',
    '$Result.iq1_s_ram_cache_ssd_bytes -ne 0',
    '$Result.iq1_s_ram_cache_preload_entries -ne $expectedSlots',
    'performance_claim_allowed = $false',
    'quality_claim_allowed = $false')) {
    if ($runnerText -notmatch [regex]::Escape($needle)) {
        throw "G105 runner contract missing: $needle"
    }
}

foreach ($needle in @(
    'Iq1SRamCachePageable requires Iq1SRamCacheGiB > 0',
    'Iq1SRamCachePreloadAll requires Iq1SRamCachePageable',
    'Iq1SRamCachePageable currently requires Iq1SRamCachePreloadAll',
    'Iq1SRamCachePreloadAll requires exactly 46.875 GiB (10240 routed experts)',
    '$env:DS4_IQ1_S_RAM_CACHE_PAGEABLE = "1"',
    '$env:DS4_IQ1_S_RAM_CACHE_PRELOAD_ALL = "1"',
    'DS4_IQ1_S_RAM_CACHE_GB',
    'RuntimeMinimumAvailableGiB',
    'contamination_abort_observed',
    'contamination_reason')) {
    if ($harnessText -notmatch [regex]::Escape($needle)) {
        throw "G105 harness guard missing: $needle"
    }
}

foreach ($needle in @(
    'iq1_s_ram_cache_pageable_requested',
    'iq1_s_ram_cache_preload_all_requested',
    'iq1_s_ram_cache_requested_bytes',
    'iq1_s_ram_cache_allocated_bytes',
    'iq1_s_ram_cache_capacity',
    'iq1_s_ram_cache_count',
    'iq1_s_ram_cache_slot_bytes',
    'iq1_s_ram_cache_hits',
    'iq1_s_ram_cache_misses',
    'iq1_s_ram_cache_evictions',
    'iq1_s_ram_cache_ssd_bytes',
    'iq1_s_ram_cache_h2d_bytes',
    'iq1_s_ram_cache_failures',
    'iq1_s_ram_cache_preload_frozen',
    'iq1_s_ram_cache_preload_layers',
    'iq1_s_ram_cache_preload_entries',
    'iq1_s_ram_cache_preload_ssd_bytes',
    'iq1_s_ram_cache_preload_read_calls',
    'iq1_s_ram_cache_preload_ms')) {
    if ($harnessText -notmatch [regex]::Escape($needle)) {
        throw "G105 harness telemetry missing: $needle"
    }
}

foreach ($needle in @(
    'capacity=(\d+) count=(\d+) slot_bytes=(\d+) hits=(\d+) misses=(\d+) evictions=(\d+) ssd_bytes=(\d+) h2d_bytes=(\d+) failures=(\d+) pinned=0 pageable=1 mapped=0 policy=frozen-full preload_all=1 frozen=(\d+) preload_layers=(\d+) preload_entries=(\d+) preload_ssd_bytes=(\d+) preload_read_calls=(\d+) preload_ms=([0-9.]+)',
    '$iq1SRamCacheCapacity -ne 10240',
    '$iq1SRamCacheCount -ne 10240',
    '$iq1SRamCacheMisses -ne 0',
    '$iq1SRamCacheEvictions -ne 0',
    '$iq1SRamCacheSsdBytes -ne 0',
    '-not $iq1SRamCachePreloadFrozen',
    '$iq1SRamCachePreloadLayers -ne 40',
    '$iq1SRamCachePreloadEntries -ne 10240',
    '$iq1SRamCachePreloadReadCalls -ne ([UInt64]10240 * 3)',
    '$iq1SRamCachePreloadMs -le 0.0')) {
    if ($harnessText -notmatch [regex]::Escape($needle)) {
        throw "G105 harness full-resident invariant missing: $needle"
    }
}

foreach ($needle in @(
    'static const uint32_t CUDA_IQ1_S_ROUTED_LAYER_FIRST = 3u;',
    'static const uint32_t CUDA_IQ1_S_ROUTED_LAYER_COUNT = 40u;',
    'static const uint32_t CUDA_IQ1_S_EXPERTS_PER_LAYER = 256u;',
    'cuda_iq1_s_env_flag("DS4_IQ1_S_RAM_CACHE_PAGEABLE")',
    'cuda_iq1_s_env_flag("DS4_IQ1_S_RAM_CACHE_PRELOAD_ALL")',
    '(pageable != preload_all)',
    'const uint64_t preload_entries',
    'CUDA_IQ1_S_ROUTED_LAYER_COUNT *',
    'CUDA_IQ1_S_EXPERTS_PER_LAYER',
    'preload_all && capacity != preload_entries',
    'VirtualAlloc(',
    'MEM_RESERVE | MEM_COMMIT',
    'PAGE_READWRITE',
    'pinned=0 pageable=1 mapped=0 policy=frozen-full',
    'cache.preload_entries++',
    'cache.preload_ssd_bytes += cache.slot_bytes',
    'cache.preload_read_calls += 3u',
    'cache.frozen = 1',
    'cache.misses++',
    'cache.evictions++',
    'cache.ssd_bytes += cache.slot_bytes')) {
    if ($cudaText -notmatch [regex]::Escape($needle)) {
        throw "G105 CUDA contract text missing: $needle"
    }
}

$beforeDs4 = @(Get-Process -Name "ds4_server" -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty Id)

$afterDs4 = @(Get-Process -Name "ds4_server" -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty Id)
if (($beforeDs4 -join ",") -ne ($afterDs4 -join ",")) {
    throw "G105 static check changed DS4 process state"
}

Write-Host "test_g105_static_contract.ps1: PASS"
