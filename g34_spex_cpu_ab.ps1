# G34 SPEX CPU observe-only A/B (PowerShell 5.1, ASCII)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$harness = Join-Path $root "g7_measure.ps1"
$spex = "C:\Users\imanu\source\repos\moe-aggressive-commit\runs\spex\spex_model\ds4flash_d2_nextlayer.spex"
$model = "C:\ds4-models\ds4-2bit.gguf"
$expected = "fda564ba3f7a0f028106d468420f674898ed99ac5bf2765ac9586206e39d73c5"
$expectedSpex = "a86288c3a29be97179230a3ed86eebdcd7293ab33987ed7aa57850213325f3c7"

function Invoke-G34Run {
    param(
        [Parameter(Mandatory=$true)][string]$Tag,
        [Parameter(Mandatory=$true)][ValidateSet(1,2)][int]$Cap,
        [Parameter(Mandatory=$true)][ValidateSet(0,1,2)][int]$CpuK
    )
    $args = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $harness,
        "-MaxTokens", "12", "-Repeats", "3", "-Warmup",
        "-Tag", $Tag, "-Prompt", "Hi", "-Context", "256",
        "-BudgetGB", "2", "-ReserveMB", "4096", "-RuntimeReserveMB", "128",
        "-ExpertCacheN", "336", "-ExpertCacheReserveGB", "0.5",
        "-ExpertCachePolicy", "lru", "-DisableQ8F16Cache",
        "-EmbedRowStaging", "-GpuResidentRoutes",
        "-SpexDryRun", "-SpexFile", $spex, "-SpexStage", "full",
        "-ExpectedSpexSHA256", $expectedSpex,
        "-SpexRingSlots", "1", "-SpexCap", "$Cap",
        "-ExpectedContentSHA256", $expected,
        "-ExpectedWarmupContentSHA256", $expected,
        "-ModelPath", $model
    )
    if ($CpuK -gt 0) {
        $args += @("-SpexCpuProbeK", "$CpuK")
    }
    Write-Host ("[g34] start tag=" + $Tag + " cap=" + $Cap + " cpu_k=" + $CpuK)
    & powershell.exe @args
    if ($LASTEXITCODE -ne 0) {
        throw "G34 run failed: $Tag (exit=$LASTEXITCODE)"
    }
}

# Counter-order each isolated pair. Controls keep identical SPEX scoring/topK.
Invoke-G34Run -Tag "g34_cap1_control_primed_n3_a" -Cap 1 -CpuK 0
Invoke-G34Run -Tag "g34_k1_cpu_primed_n3_a" -Cap 1 -CpuK 1
Invoke-G34Run -Tag "g34_k1_cpu_primed_n3_b" -Cap 1 -CpuK 1
Invoke-G34Run -Tag "g34_cap1_control_primed_n3_b" -Cap 1 -CpuK 0

Invoke-G34Run -Tag "g34_cap2_control_primed_n3_a" -Cap 2 -CpuK 0
Invoke-G34Run -Tag "g34_k2_cpu_primed_n3_a" -Cap 2 -CpuK 2
Invoke-G34Run -Tag "g34_k2_cpu_primed_n3_b" -Cap 2 -CpuK 2
Invoke-G34Run -Tag "g34_cap2_control_primed_n3_b" -Cap 2 -CpuK 0

Write-Host "[g34] matrix complete"
