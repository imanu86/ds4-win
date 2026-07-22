$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$source = Get-Content -LiteralPath (Join-Path $root 'ds4_cuda.cu') -Raw
$presetPath = Join-Path $root 'tests\g73_open.env.ps1'
$preset = Get-Content -LiteralPath $presetPath -Raw

function Assert-Contains([string]$Text, [string]$Needle, [string]$Message) {
    if (-not $Text.Contains($Needle)) { throw $Message }
}

$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
    $presetPath, [ref]$tokens, [ref]$errors)
if ($errors -and $errors.Count) { throw 'G73-OPEN preset has PowerShell syntax errors' }

Assert-Contains $source 'getenv("DS4_G73_OPEN")' 'missing OFF-default G73-OPEN gate'
Assert-Contains $source '!cuda_g73_open_requested()) {' 'cold admission must be bypassed only in G73-OPEN'
Assert-Contains $source 'cuda_moe_transient_pread_chunked(' 'missing bounded exact transient read'
Assert-Contains $source 'cuda_g73_open_maybe_schedule_rotation(' 'missing G133-to-SSD-wrap rotator seam'
Assert-Contains $source 'g73_open_rotation' 'SSD-wrap jobs must distinguish exact G73 rotation from Q1 promotion'
Assert-Contains $source 'falling back to exact selected-load' 'missing request fail-open fallback'
foreach ($counter in @('out_of_mask_routes', 'served_transient', 'served_lane_a',
        'served_promoted', 'clamped', 'rotation_promotions', 'rotation_reaps')) {
    Assert-Contains $source $counter "missing G73 attribution counter: $counter"
}

foreach ($setting in @(
        '$env:DS4_G73_OPEN = ''1''',
        '$env:DS4_CUDA_DYNAMIC_ARENA_GB = ''30''',
        '$env:DS4_CUDA_STREAMING_EXPERT_CACHE_N = ''320''',
        '$env:DS4_CUDA_PREFILL_TIER_ROUTER = ''open''',
        '$env:DS4_EXPERT_TIERING = ''enforce''',
        '$env:DS4_G133_TIER = ''1''',
        '$env:DS4_G130_U1_ATTRIBUTION = ''1''',
        '$env:DS4_CUDA_MOE_SPLIT_FUSED = ''0''')) {
    Assert-Contains $preset $setting "preset missing: $setting"
}
foreach ($q1 in @('DS4_Q1_0_MIXED_COLD_ONE', 'DS4_IQ1_S_MIXED_COLD_K',
        'DS4_Q1_0_SELECTED_LOAD', 'DS4_Q1_0_EXPERT_SIDECAR')) {
    Assert-Contains $preset "Remove-Item Env:\$q1" "preset does not disable $q1"
}

Write-Host 'G73-OPEN static contract passed'
