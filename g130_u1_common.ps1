Set-StrictMode -Version 2.0

function Get-G130U1Constants {
    [CmdletBinding()]
    param()

    $q1Bytes = [UInt64]11008 * [UInt64]3538944
    $iq2Bytes = [UInt64](5.5 * 1GB)
    $floorBytes = [UInt64](2 * 1GB)
    [pscustomobject][ordered]@{
        schema = 'g130_u1_constants_v3'
        model_path = 'C:\ds4-models\ds4-2bit.gguf'
        model_receipt_path = 'C:\ds4-models\ds4-2bit.gguf.receipt.json'
        model_bytes = [UInt64]86720111488
        model_sha256 = 'efc7ed607ff27076e3e501fc3fefefa33c0ed8cf1eff483a2b7fdc0c2e616668'
        sidecar_path = 'C:\ds4-models\ds4-q1-layers0-42-derived.gguf'
        sidecar_receipt_path = 'C:\ds4-models\ds4-q1-layers0-42-derived.gguf.receipt.json'
        sidecar_bytes = [UInt64]39048344416
        sidecar_sha256 = '05040393f5e94bf054a593e4d2d021ff44a6f446f2328a75e4f833a1fbe20207'
        q1_resident_entries = [UInt64]11008
        q1_entry_bytes = [UInt64]3538944
        q1_total_bytes = $q1Bytes
        q1_pinned_max_bytes = [UInt64](24.5 * 1GB)
        iq2_arena_bytes = $iq2Bytes
        ram_floor_bytes = $floorBytes
        planned_ram_bytes = [UInt64]($q1Bytes + $iq2Bytes + $floorBytes)
        disk_free_floor_bytes = [UInt64](5 * 1GB)
        expected_git_base = '63de9b23f71993a3d9965355c9e445830c12f81c'
        expected_build_manifest_schema = 'g7_native_windows_build_manifest_v1'
        max_tokens = 64
        repeats = 1
        context = 256
        temperature = 0
        wall_cap_seconds = 900
        ttft_cap_seconds = 180
        startup_stall_seconds = 180
        application_data_stall_seconds = 60
        page_out_delta_abort_pages = 100000
        watchdog_heartbeat_stall_seconds = 5
        watchdog_cadence_seconds = 1
        quiet_window_interval_seconds = 2
        mtp_draft_tokens = 1
        http_worker_guard_seconds = 930
        parent_poll_milliseconds = 250
        watchdog_abort_wait_milliseconds = 3000
        server_exit_worker_grace_milliseconds = 3000
        postrun_watchdog_wait_milliseconds = 10000
        graceful_http_timeout_seconds = 2
        graceful_exit_wait_milliseconds = 5000
        forced_exit_wait_milliseconds = 10000
        child_cleanup_wait_milliseconds = 5000
        disk_queue_max_exclusive = 1.0
        gpu_vram_idle_max_mib = 700.0
        gpu_power_plausible_max_w = 1000.0
        gpu_temperature_plausible_max_c = 125.0
        gpu_utilization_idle_max_percent = 5.0
        quiet_cpu_max_percent = 15.0
        gpu_temperature_idle_max_c = 60.0
        cpu_temperature_plausible_max_c = 115.0
        predicted_decode_tps = 0.205
        throughput_floor_fraction = 0.50
        throughput_floor_tps = 0.1025
        throughput_warm_tokens = 16
        throughput_consecutive_tokens = 30
        p2_host_seconds_per_token_minimum = 3.44
        p2_completed_call_coverage_minimum = 0.99
    }
}

function Get-G130U1Environment {
    [CmdletBinding()]
    param([string]$ShutdownToken = '')

    $c = Get-G130U1Constants
    $result = [ordered]@{
        DS4_MODEL_SHA256 = $c.model_sha256
        DS4_MODEL_BYTES = [string]$c.model_bytes
        DS4_Q1_0_EXPERT_SIDECAR = $c.sidecar_path
        DS4_Q1_0_EXPERT_SIDECAR_SHA256 = $c.sidecar_sha256
        DS4_Q1_0_EXPERT_SIDECAR_BYTES = [string]$c.sidecar_bytes
        DS4_Q1_0_LAYER_FIRST = '0'
        DS4_Q1_0_LAYER_LAST = '42'
        DS4_Q1_0_SELECTED_LOAD = '1'
        DS4_Q1_0_RESIDENT_ARENA = '1'
        DS4_Q1_0_DUAL_ARENA = '1'
        DS4_Q1_0_PAGEABLE_OVERFLOW = '1'
        DS4_Q1_0_DYNAMIC_ARENA_GB = '24.5'
        DS4_Q1_0_PROFILE = '1'
        DS4_CUDA_STREAM_FROM_RAM_MASKED_BUDGET_GB = '2'
        DS4_CUDA_STREAM_RESERVE_MB = '1024'
        DS4_CUDA_Q8_F16_CACHE_RESERVE_MB = '4096'
        DS4_CUDA_NO_Q8_F16_CACHE = '1'
        DS4_CUDA_EMBED_ROW_STAGING = '1'
        DS4_CUDA_DYNAMIC_ARENA_GB = '5.5'
        DS4_CUDA_PREFILL_MASS_OBSERVE = '1'
        DS4_CUDA_PREFILL_MASS_WRAP = '1'
        DS4_CUDA_PREFILL_TIER_COMPOSE = '1'
        DS4_CUDA_PREFILL_TIER_ROUTER = 'open'
        DS4_CUDA_PREFILL_TIER_RESERVE_SLOTS = '64'
        DS4_CUDA_PREFILL_VRAM_SEED_TOTAL = '320'
        DS4_CUDA_PREFILL_VRAM_SEED_FLOOR_PER_LAYER = '4'
        DS4_REAP_PREFETCH_THREADS = '8'
        DS4_CUDA_STREAMING_EXPERT_CACHE_N = '320'
        DS4_CUDA_STREAMING_EXPERT_CACHE_RESERVE_GB = '0.125'
        DS4_CUDA_MOE_CACHE_POLICY = 'lru'
        DS4_CUDA_MOE_GPU_RESIDENT_ROUTES = '1'
        DS4_CUDA_MOE_ROUTE_NO_DEFAULT_SYNC = '1'
        DS4_CUDA_MOE_SPLIT_FUSED = '1'
        DS4_EXPERT_TIERING = 'enforce'
        DS4_EXPERT_TIER_POLICY = 'mass-lfru'
        DS4_EXPERT_TIER_CLOCK_CALLS = '430'
        DS4_EXPERT_TIER_REPLACEMENT_BUDGET = '32'
        DS4_EXPERT_TIER_MIN_FREQUENCY = '3'
        DS4_EXPERT_TIER_HYSTERESIS = '1.25'
        DS4_BENCH_EXIT_AFTER_REQUESTS = '1'
    }
    if (-not [string]::IsNullOrWhiteSpace($ShutdownToken)) {
        $result['DS4_G130_U1_SHUTDOWN_TOKEN'] = $ShutdownToken
    }
    $result
}

function New-G130U1RequestObject {
    [CmdletBinding()]
    param()
    [pscustomobject][ordered]@{
        model = 'ds4'
        messages = @([pscustomobject][ordered]@{
            role = 'user'
            content = 'Explain in one concise paragraph why profiling must precede optimization.'
        })
        max_tokens = 64
        temperature = 0
        stream = $true
        stream_options = [pscustomobject][ordered]@{ include_usage = $true }
        think = $false
    }
}

function Get-G130U1WhatIfPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$RepositoryRoot,[AllowNull()][object]$ApprovalBinding=$null)

    $c = Get-G130U1Constants
    $environment = Get-G130U1Environment
    $request = New-G130U1RequestObject
    [pscustomobject][ordered]@{
        schema = 'g130_u1_q1_profile_whatif_v3'
        mode = 'whatif_no_side_effects'
        live_requires_switch = '-Live'
        live_requires_approval_schema = 'g130_u1_live_approval_v2'
        tier = 'T1'
        outcome_scope = @('DIAGNOSTIC','NEGATIVE','CONTAMINATED')
        quotable = $false
        retries = 0
        repository_root = $RepositoryRoot
        executable = (Join-Path $RepositoryRoot 'build\Release\ds4_server.exe')
        runner = (Join-Path $RepositoryRoot 'g130_u1_q1_profile.ps1')
        watchdog = (Join-Path $RepositoryRoot 'g130_u1_watchdog.ps1')
        powershell_role_mapping = [pscustomobject][ordered]@{
            schema='g130_u1_four_role_three_file_waiver_v1';role_count=4;file_count=3
            waiver='The supervised HTTP worker is a closed parameter set in the runner; a fourth script would widen quoting and identity surface without adding process isolation.'
            roles=@(
                [pscustomobject][ordered]@{role='parent_runner';file='g130_u1_q1_profile.ps1';mode='default_or_live'},
                [pscustomobject][ordered]@{role='http_sse_worker';file='g130_u1_q1_profile.ps1';mode='parameter_set:HttpWorker'},
                [pscustomobject][ordered]@{role='decision_only_watchdog_sampler';file='g130_u1_watchdog.ps1';mode='ManifestPath'},
                [pscustomobject][ordered]@{role='shared_closed_schema_library';file='g130_u1_common.ps1';mode='dot_sourced'}
            )
        }
        approval_binding=$(if($null-ne$ApprovalBinding){$ApprovalBinding}else{[pscustomobject][ordered]@{
            schema='g130_u1_approval_binding_contract_v1';state='WHATIF_UNBOUND';required=@('git_head','runner_sha256','common_sha256','watchdog_sha256','executable_sha256','build_manifest_sha256','worker_mode')
        }})
        model = [pscustomobject][ordered]@{
            path=$c.model_path; receipt_path=$c.model_receipt_path; expected_bytes=$c.model_bytes
            expected_sha256_from_receipt=$c.model_sha256; full_rehash_allowed=$false
        }
        sidecar = [pscustomobject][ordered]@{
            path=$c.sidecar_path; receipt_path=$c.sidecar_receipt_path; expected_bytes=$c.sidecar_bytes
            expected_sha256_from_receipt=$c.sidecar_sha256; full_rehash_allowed=$false
        }
        request = $request
        request_contract = [pscustomobject][ordered]@{
            count=1; generated_tokens=64; finish_reason='length'; finish_count=1
            usage_completion_tokens=64; usage_count=1; done_count=1
            terminal_order=@('finish','usage','done');data_after_done_allowed=$false
            complete_response_required=$true
        }
        routing = [pscustomobject][ordered]@{
            regime='full/open'; q1_resident_entries=$c.q1_resident_entries
            q1_entry_bytes=$c.q1_entry_bytes; iq2_arena_gib=5.5; q1_pinned_gib=24.5
            q1_overflow='pageable'; dynamic_promotion=$false; ssd_wrap=$false
            mixed_trace=$false; general_trace=$false; mtp_draft_tokens=$c.mtp_draft_tokens
        }
        planned_ram = [pscustomobject][ordered]@{
            q1_total_formula='11008 * 3538944'; q1_total_bytes=$c.q1_total_bytes
            iq2_arena_bytes=$c.iq2_arena_bytes; floor_bytes=$c.ram_floor_bytes
            required_available_bytes=$c.planned_ram_bytes
        }
        disk = [pscustomobject][ordered]@{
            volume='C:'; minimum_free_bytes=$c.disk_free_floor_bytes
        }
        environment_policy = [pscustomobject][ordered]@{
            inherited_ds4_variables='clear_then_restore'; enabled=$environment
            profile_variables_enabled=@('DS4_Q1_0_PROFILE'); auto_exit_requests=1
            shutdown_auth_variable='DS4_G130_U1_SHUTDOWN_TOKEN'
            forbidden=@('DS4_Q1_0_DYNAMIC_PROMOTION','DS4_Q1_0_PROMOTION_SSD_WRAP',
                'DS4_Q1_0_MIXED_TRACE','DS4_CUDA_MOE_ROUTE_PROFILE','DS4_REQUEST_PHASE_TRACE',
                'DS4_EXPERT_RECOVERY_TRACE','DS4_EXPERT_RECOVERY_TRACE_LAYER',
                'DS4_EXPERT_RECOVERY_TRACE_EXPERT','DS4_EXPERT_RECOVERY_TRACE_MAX_SAMPLES',
                'DS4_EXPERT_RECOVERY_TRACE_MAX_BYTES','DS4_EXPERT_RECOVERY_TRACE_ROOT',
                'DS4_EXPERT_RECOVERY_TRACE_OUTPUT_PREFIX','DS4_MTP_PROBE','DS4_MTP_SPEC_LOG',
                'DS4_MTP_CONF_LOG','DS4_MTP_TIMING','DS4_MTP_FORCE_SNAPSHOT',
                'DS4_IQ1_MIXED_DEBUG','DS4_TRACE_TOP')
        }
        server_arguments = @('-m',$c.model_path,'--cuda','-c','256','-n','64','--mtp-draft','1',
            '--host','127.0.0.1','--port','<dynamic-loopback-port>')
        preregistration = [pscustomobject][ordered]@{
            schema='g130_u1_preregistration_v2'
            question='In which U1 host profile buckets does the previously unattributed decode residual occur?'
            predicted_profile_component_seconds_per_token=[pscustomobject][ordered]@{minimum=0.20;maximum=0.50;basis='observed prior full/open diagnostic range'}
            predicted_decode_tps=$c.predicted_decode_tps
            abort_floor_derivation='predicted_decode_tps * 0.50'
            abort_floor_fraction=$c.throughput_floor_fraction
            abort_floor_tps=$c.throughput_floor_tps
            warm_tokens=$c.throughput_warm_tokens
            consecutive_tokens=$c.throughput_consecutive_tokens
            application_data_stall_seconds=$c.application_data_stall_seconds
            page_out_delta_abort_pages=$c.page_out_delta_abort_pages
            watchdog_heartbeat_stall_seconds=$c.watchdog_heartbeat_stall_seconds
            watchdog_cadence_seconds=$c.watchdog_cadence_seconds
            quiet_window_interval_seconds=$c.quiet_window_interval_seconds
            wall_cap_seconds=$c.wall_cap_seconds
            ttft_cap_seconds=$c.ttft_cap_seconds
            startup_stall_seconds=$c.startup_stall_seconds
            p2_authorization=[pscustomobject][ordered]@{
                clock='host_monotonic'; source='q1-0-profile-route.call_seconds'
                host_seconds_per_token_minimum=$c.p2_host_seconds_per_token_minimum
                completed_call_coverage_minimum=$c.p2_completed_call_coverage_minimum
                device_timers_included=$false; otherwise='STOP_AND_REPLAN'
            }
            normative_telemetry_substitution=[pscustomobject][ordered]@{
                tracing_remains_off=$true
                replaced=@('routeprof','selprof')
                required=@('q1-0-profile-route','q1-0-profile-selection')
            }
        }
        lifecycle_thresholds = [pscustomobject][ordered]@{
            parent_poll_milliseconds=$c.parent_poll_milliseconds
            http_worker_guard_seconds=$c.http_worker_guard_seconds
            watchdog_abort_wait_milliseconds=$c.watchdog_abort_wait_milliseconds
            server_exit_worker_grace_milliseconds=$c.server_exit_worker_grace_milliseconds
            postrun_watchdog_wait_milliseconds=$c.postrun_watchdog_wait_milliseconds
            graceful_http_timeout_seconds=$c.graceful_http_timeout_seconds
            graceful_exit_wait_milliseconds=$c.graceful_exit_wait_milliseconds
            forced_exit_wait_milliseconds=$c.forced_exit_wait_milliseconds
            child_cleanup_wait_milliseconds=$c.child_cleanup_wait_milliseconds
            normal_exit='DS4_BENCH_EXIT_AFTER_REQUESTS=1'
            authenticated_shutdown_endpoint_use='abort-only'
        }
        preflight_thresholds = [pscustomobject][ordered]@{
            disk_queue_max_exclusive=$c.disk_queue_max_exclusive
            gpu_vram_idle_max_mib=$c.gpu_vram_idle_max_mib
            gpu_power_plausible_max_w=$c.gpu_power_plausible_max_w
            gpu_temperature_plausible_max_c=$c.gpu_temperature_plausible_max_c
            gpu_utilization_idle_max_percent=$c.gpu_utilization_idle_max_percent
            quiet_cpu_max_percent=$c.quiet_cpu_max_percent
            gpu_temperature_idle_max_c=$c.gpu_temperature_idle_max_c
            cpu_temperature_plausible_max_c=$c.cpu_temperature_plausible_max_c
        }
        preflight_gates=@('P-1','P-2','P-3','P-4','P-5','P-6','P-7','P-8')
        abort_gates=@('A-1','A-2','A-3','A-4','A-5','A-6','A-7','A-8','A-9','A-10')
        parser_contract=[pscustomobject][ordered]@{
            closed_schema=$true; legacy_profile_lines=1; u3_required=$true
            measurement_basis='profile-on, existing-fence'
            existing_base_fences_and_events_expected=$true
            claim_of_zero_synchronization=$false
            mtp_draft_tokens=1
            token_progress_schema='g130_u1_profile_token_v1'; token_progress_count=64
            source_working_set_lines=3
            working_set_phases=@('pre-copy','post-bootstrap','post-unlock-settle')
            route_final_lines=1; selection_final_lines=1; final_path='mixed_q1'
            host_device_addition_allowed=$false
        }
        artifacts=@('approval.json','preregistration.json','config.json','environment.json',
            'build_identity.json','preflight.json','server.stdout.log','server.stderr.log',
            'request.json','raw_response.sse','request_result.json','assistant_text.txt',
            'http_timing.jsonl','watchdog.jsonl','watchdog_sampler.jsonl','watchdog_abort.json',
            'profile_summary.json','receipt.json','receipt.json.sha256','ledger_row.json')
        exit_codes=[pscustomobject][ordered]@{
            diagnostic=0; live_not_approved=19; preflight_no_go=20; watchdog_abort=21
            request_failed=22; parser_failed=23; cleanup_failed=24; internal_failure=25
        }
    }
}

function ConvertTo-G130U1Json {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][AllowNull()][object]$Value,[switch]$Compress)
    $Value | ConvertTo-Json -Depth 60 -Compress:$Compress
}

function Write-G130U1Utf8 {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][AllowEmptyString()][string]$Text)
    [IO.File]::WriteAllText($Path,$Text,[Text.UTF8Encoding]::new($false))
}

function Write-G130U1Json {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][AllowNull()][object]$Value)
    Write-G130U1Utf8 $Path ((ConvertTo-G130U1Json $Value) + "`n")
}

function Write-G130U1JsonAtomic {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][AllowNull()][object]$Value)
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { throw "atomic JSON parent missing: $directory" }
    $temporary = Join-Path $directory ('.g130-u1-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    $backup = Join-Path $directory ('.g130-u1-' + [Guid]::NewGuid().ToString('N') + '.bak')
    try {
        Write-G130U1Json $temporary $Value
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            [IO.File]::Replace($temporary,$Path,$backup,$true)
        } else {
            [IO.File]::Move($temporary,$Path)
        }
    } finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force }
        if (Test-Path -LiteralPath $backup -PathType Leaf) { Remove-Item -LiteralPath $backup -Force }
    }
}

function Write-G130U1AbortAtomic {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][object]$Value)
    $directory=Split-Path -Parent $Path
    if(-not(Test-Path -LiteralPath $directory -PathType Container)){throw "abort parent missing: $directory"}
    $temporary=Join-Path $directory ('.g130-u1-abort-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-G130U1Json $Value) + "`n")
    try {
        $stream=[IO.File]::Open($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
        try{[IO.File]::Move($temporary,$Path);return $true}catch [IO.IOException]{return $false}
    } finally {
        if(Test-Path -LiteralPath $temporary -PathType Leaf){Remove-Item -LiteralPath $temporary -Force}
    }
}

function Get-G130U1Sha256File {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path)
    $sha = [Security.Cryptography.SHA256]::Create()
    $stream = [IO.File]::OpenRead($Path)
    try { ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant() }
    finally { $stream.Dispose(); $sha.Dispose() }
}

function Get-G130U1Sha256Text {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][AllowEmptyString()][string]$Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($sha.ComputeHash([Text.UTF8Encoding]::new($false).GetBytes($Text)))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Enter-G130U1Environment {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][Collections.IDictionary]$Desired)
    $saved = [ordered]@{}
    foreach ($item in [Environment]::GetEnvironmentVariables('Process').GetEnumerator()) {
        if ([string]$item.Key -like 'DS4_*') { $saved[[string]$item.Key]=[string]$item.Value }
    }
    foreach ($name in @([Environment]::GetEnvironmentVariables('Process').Keys)) {
        if ([string]$name -like 'DS4_*') { [Environment]::SetEnvironmentVariable([string]$name,$null,'Process') }
    }
    foreach ($name in $Desired.Keys) { [Environment]::SetEnvironmentVariable([string]$name,[string]$Desired[$name],'Process') }
    [pscustomobject]@{ saved=$saved }
}

function Exit-G130U1Environment {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$State)
    foreach ($name in @([Environment]::GetEnvironmentVariables('Process').Keys)) {
        if ([string]$name -like 'DS4_*') { [Environment]::SetEnvironmentVariable([string]$name,$null,'Process') }
    }
    foreach ($name in $State.saved.Keys) { [Environment]::SetEnvironmentVariable([string]$name,[string]$State.saved[$name],'Process') }
}

function Assert-G130U1ExactPropertySet {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Object,[Parameter(Mandatory=$true)][string[]]$Expected,
        [Parameter(Mandatory=$true)][string]$Context)
    if ($null -eq $Object) { throw "$Context is null" }
    $actual = @($Object.PSObject.Properties.Name)
    $missing = @($Expected | Where-Object { $_ -notin $actual })
    $unknown = @($actual | Where-Object { $_ -notin $Expected })
    if ($missing.Count -ne 0 -or $unknown.Count -ne 0) {
        throw "$Context schema mismatch missing=$($missing -join ',') unknown=$($unknown -join ',')"
    }
}

function Get-G130U1Property {
    [CmdletBinding()]
    param([AllowNull()][object]$Object,[Parameter(Mandatory=$true)][string]$Name)
    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) { return $null }
    $Object.$Name
}

function Test-G130U1PresentNumber {
    [CmdletBinding()]
    param([AllowNull()][object]$Value,[switch]$StrictlyPositive)
    if ($null -eq $Value -or $Value -is [bool]) { return $false }
    [double]$number=0
    if (-not [double]::TryParse([string]$Value,[Globalization.NumberStyles]::Float,
            [Globalization.CultureInfo]::InvariantCulture,[ref]$number)) { return $false }
    if ([double]::IsNaN($number) -or [double]::IsInfinity($number)) { return $false }
    if ($StrictlyPositive) { return $number -gt 0 }
    return $number -ge 0
}

function Assert-G130U1TypedNumber {
    [CmdletBinding()]
    param([AllowNull()][object]$Value,[Parameter(Mandatory=$true)][string]$Context,
        [switch]$StrictlyPositive,[switch]$Integral,[switch]$AllowNegative)
    if($null-eq$Value-or$Value-is[bool]-or$Value-is[string]){throw"$Context must be a JSON number"}
    $numericTypes=@([byte],[sbyte],[Int16],[UInt16],[Int32],[UInt32],[Int64],[UInt64],[single],[double],[decimal])
    $typed=$false;foreach($type in $numericTypes){if($Value-is$type){$typed=$true;break}}
    if(-not$typed){throw"$Context has unsupported numeric type $($Value.GetType().FullName)"}
    $number=[double]$Value
    if([double]::IsNaN($number)-or[double]::IsInfinity($number)-or(-not$AllowNegative-and$number-lt0)){throw"$Context must be finite and nonnegative"}
    if($StrictlyPositive-and$number-le0){throw"$Context must be strictly positive"}
    if($Integral-and[math]::Floor($number)-ne$number){throw"$Context must be integral"}
}

function Assert-G130U1StringValue {
    [CmdletBinding()]
    param([AllowNull()][object]$Value,[Parameter(Mandatory=$true)][string]$Context,[switch]$AllowEmpty)
    if($null-eq$Value-or$Value-isnot[string]){throw"$Context must be a string"}
    if(-not$AllowEmpty-and[string]::IsNullOrWhiteSpace([string]$Value)){throw"$Context must not be empty"}
}

function ConvertTo-G130U1UInt64 {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Value,[Parameter(Mandatory=$true)][string]$Name)
    [UInt64]$result=0
    if (-not [UInt64]::TryParse($Value,[Globalization.NumberStyles]::None,
            [Globalization.CultureInfo]::InvariantCulture,[ref]$result)) { throw "$Name is not UInt64: $Value" }
    $result
}

function ConvertTo-G130U1FiniteDouble {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Value,[Parameter(Mandatory=$true)][string]$Name,[switch]$AllowNegative)
    [double]$result=0
    if (-not [double]::TryParse($Value,[Globalization.NumberStyles]::Float,
            [Globalization.CultureInfo]::InvariantCulture,[ref]$result) -or
        [double]::IsNaN($result) -or [double]::IsInfinity($result) -or (-not $AllowNegative -and $result -lt 0)) {
        throw "$Name is not a permitted finite number: $Value"
    }
    $result
}

function ConvertFrom-G130U1KeyValueLine {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Line,[Parameter(Mandatory=$true)][string]$Tag)
    $prefix="ds4: [$Tag] "
    if (-not $Line.StartsWith($prefix,[StringComparison]::Ordinal)) { throw "$Tag prefix mismatch" }
    $result=[ordered]@{}
    foreach ($token in $Line.Substring($prefix.Length).Split(@(' '),[StringSplitOptions]::RemoveEmptyEntries)) {
        $index=$token.IndexOf('=')
        if ($index -le 0 -or $index -eq $token.Length-1) { throw "$Tag malformed token: $token" }
        $name=$token.Substring(0,$index); $value=$token.Substring($index+1)
        if ($result.Contains($name)) { throw "$Tag duplicate field: $name" }
        $result[$name]=$value
    }
    $result
}

function ConvertTo-G130U1CanonicalTaggedLine {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Line,[Parameter(Mandatory=$true)][string]$Tag)
    $escaped=[regex]::Escape($Tag)
    $direct=[regex]::Match($Line,"^ds4: \[$escaped\] (?<payload>[^\r\n]+)$",[Text.RegularExpressions.RegexOptions]::CultureInvariant)
    if($direct.Success){return "ds4: [$Tag] $($direct.Groups['payload'].Value)"}
    $logged=[regex]::Match($Line,"^(?<stamp>(?:0[1-9]|1[0-2])(?:0[1-9]|[12][0-9]|3[01]) (?:[01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]) ds4-server: \[$escaped\] (?<payload>[^\r\n]+)$",[Text.RegularExpressions.RegexOptions]::CultureInvariant)
    if($logged.Success){return "ds4: [$Tag] $($logged.Groups['payload'].Value)"}
    return $null
}

function ConvertTo-G130U1CanonicalServerLogLine {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Line)
    if($Line-match'^ds4-server: [^\r\n]+$'){return $Line}
    $logged=[regex]::Match($Line,'^(?:0[1-9]|1[0-2])(?:0[1-9]|[12][0-9]|3[01]) (?:[01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9] (?<message>ds4-server: [^\r\n]+)$',[Text.RegularExpressions.RegexOptions]::CultureInvariant)
    if($logged.Success){return $logged.Groups['message'].Value}
    return $null
}

function Assert-G130U1KeySet {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][Collections.IDictionary]$Fields,[Parameter(Mandatory=$true)][string[]]$Expected,
        [Parameter(Mandatory=$true)][string]$Context)
    $actual=@($Fields.Keys)
    $missing=@($Expected|Where-Object{$_ -notin $actual}); $unknown=@($actual|Where-Object{$_ -notin $Expected})
    if($missing.Count -or $unknown.Count){throw "$Context closed schema mismatch missing=$($missing -join ',') unknown=$($unknown -join ',')"}
}

function Assert-G130U1ExactValue {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][Collections.IDictionary]$Fields,[string]$Name,[string]$Expected,[string]$Context)
    if(-not $Fields.Contains($Name)-or[string]$Fields[$Name]-cne$Expected){throw "$Context.$Name expected '$Expected', got '$($Fields[$Name])'"}
}

function Get-G130U1TaggedLines {
    [CmdletBinding()]
    param([string[]]$Lines,[string]$Tag)
    @($Lines|ForEach-Object{$canonical=ConvertTo-G130U1CanonicalTaggedLine $_ $Tag;if($null-ne$canonical){$canonical}})
}

function Read-G130U1Profile {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][int]$GeneratedTokens)
    if($GeneratedTokens-ne64){throw "U1 requires exactly 64 generated tokens, got $GeneratedTokens"}
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "profile log missing: $Path"}
    $lines=@([IO.File]::ReadAllLines($Path,[Text.UTF8Encoding]::new($false,$true)))
    $whole=$lines -join "`n"
    if($whole-match'(?i)(state\.failed=1|\[q1-0-ssd-wrap\]|ssd_wrap|dynamic[-_ ]promotion)'){throw'promotion/SSD-wrap marker observed while promotion is OFF'}
    if($whole-match'(?i)(\[q1-0-mixed-route\]|\[routeprof\]|\[selprof\]|\[expert-recovery-trace\]|\[request-phase\]|\[(?:mtp|debug)[^\]]*trace[^\]]*\])'){throw'forbidden trace marker observed while tracing is OFF'}

    $allowedTags=@('q1-0-profile','q1-0-source-working-set','q1-0-profile-route','q1-0-profile-selection','q1-0-resident-arena','q1-0-profile-token')
    foreach($line in $lines){
        $tagMatch=[regex]::Match($line,'\[(?<tag>q1-0-(?:profile[^\]]*|source-working-set|resident-arena))\]')
        if(-not$tagMatch.Success){continue}
        $tag=$tagMatch.Groups['tag'].Value
        if($tag-notin$allowedTags){throw"unknown U1 profile tag: $tag"}
        if($null-eq(ConvertTo-G130U1CanonicalTaggedLine $line $tag)){throw"$tag runtime prefix/timestamp malformed"}
    }

    $legacyLines=@(Get-G130U1TaggedLines $lines 'q1-0-profile')
    $workingLines=@(Get-G130U1TaggedLines $lines 'q1-0-source-working-set')
    $routeLines=@(Get-G130U1TaggedLines $lines 'q1-0-profile-route')
    $selectionLines=@(Get-G130U1TaggedLines $lines 'q1-0-profile-selection')
    $residentLines=@(Get-G130U1TaggedLines $lines 'q1-0-resident-arena')
    $tokenLines=@(Get-G130U1TaggedLines $lines 'q1-0-profile-token')
    if($legacyLines.Count-ne1-or$workingLines.Count-ne3-or$routeLines.Count-ne1-or$selectionLines.Count-ne1-or$residentLines.Count-ne1){
        throw "profile cardinality mismatch legacy=$($legacyLines.Count) working=$($workingLines.Count) route=$($routeLines.Count) selection=$($selectionLines.Count) resident=$($residentLines.Count)"
    }
    if($tokenLines.Count-ne65){throw "profile token telemetry requires 64 progress rows plus one final row, got $($tokenLines.Count)"}

    $resident=ConvertFrom-G130U1KeyValueLine $residentLines[0] 'q1-0-resident-arena'
    $residentKeys=@('result','entries','layers','generation','source','route_pread','iq2_host_arena','mixed_host_backing','pinned','pageable','pinned_slots','pageable_slots','total_slots','total_bytes')
    Assert-G130U1KeySet $resident $residentKeys 'resident'
    foreach($pair in @(@('result','bootstrapped'),@('layers','0..42'),@('generation','1'),@('source','sidecar-mmap'),@('route_pread','disabled'),@('iq2_host_arena','enabled'),@('mixed_host_backing','dual-arena'))){Assert-G130U1ExactValue $resident $pair[0] $pair[1] 'resident'}
    $c=Get-G130U1Constants
    $entries=ConvertTo-G130U1UInt64 $resident.entries 'resident.entries';$pinned=ConvertTo-G130U1UInt64 $resident.pinned 'resident.pinned';$pageable=ConvertTo-G130U1UInt64 $resident.pageable 'resident.pageable'
    $pinnedSlots=ConvertTo-G130U1UInt64 $resident.pinned_slots 'resident.pinned_slots';$pageableSlots=ConvertTo-G130U1UInt64 $resident.pageable_slots 'resident.pageable_slots'
    $totalSlots=ConvertTo-G130U1UInt64 $resident.total_slots 'resident.total_slots';$totalBytes=ConvertTo-G130U1UInt64 $resident.total_bytes 'resident.total_bytes'
    $expectedPinnedSlots=[UInt64][math]::Floor([double]$c.q1_pinned_max_bytes/[double]$c.q1_entry_bytes);$expectedPageableSlots=[UInt64]($c.q1_resident_entries-$expectedPinnedSlots)
    if($entries-ne$c.q1_resident_entries-or$totalSlots-ne$c.q1_resident_entries-or$totalBytes-ne$c.q1_total_bytes-or$pinned+$pageable-ne$totalBytes-or$pinnedSlots+$pageableSlots-ne$totalSlots-or$pinned-ne$pinnedSlots*$c.q1_entry_bytes-or$pageable-ne$pageableSlots*$c.q1_entry_bytes-or$pinnedSlots-ne$expectedPinnedSlots-or$pageableSlots-ne$expectedPageableSlots-or$pinned-eq0-or$pageable-eq0-or$pinned-gt$c.q1_pinned_max_bytes){throw'resident arena balance mismatch'}

    $workingKeys=@('result','phase','windows','page_size','mapping_bytes','queried_pages','resident_pages','resident_bytes','shared_pages','shared_bytes','not_shared_pages','not_shared_bytes','file_backed_pages','file_backed_bytes','query_calls','last_error','file_backed_basis')
    $working=@()
    foreach($phase in @('pre-copy','post-bootstrap','post-unlock-settle')){
        $matches=@($workingLines|Where-Object{$_-match"(?:^| )phase=$([regex]::Escape($phase))(?: |$)"});if($matches.Count-ne1){throw"working phase $phase cardinality"}
        $f=ConvertFrom-G130U1KeyValueLine $matches[0] 'q1-0-source-working-set';Assert-G130U1KeySet $f $workingKeys "working.$phase"
        foreach($pair in @(@('result','ok'),@('phase',$phase),@('windows','1'),@('last_error','0'),@('file_backed_basis','sidecar-file-mapping'))){Assert-G130U1ExactValue $f $pair[0] $pair[1] "working.$phase"}
        foreach($name in $workingKeys|Where-Object{$_-notin@('result','phase','file_backed_basis')}){[void](ConvertTo-G130U1UInt64 $f[$name] "working.$phase.$name")}
        $pageSize=ConvertTo-G130U1UInt64 $f.page_size "working.$phase.page_size";$mapping=ConvertTo-G130U1UInt64 $f.mapping_bytes "working.$phase.mapping_bytes";$queried=ConvertTo-G130U1UInt64 $f.queried_pages "working.$phase.queried_pages";$residentPages=ConvertTo-G130U1UInt64 $f.resident_pages "working.$phase.resident_pages";$residentBytes=ConvertTo-G130U1UInt64 $f.resident_bytes "working.$phase.resident_bytes";$sharedPages=ConvertTo-G130U1UInt64 $f.shared_pages "working.$phase.shared_pages";$sharedBytes=ConvertTo-G130U1UInt64 $f.shared_bytes "working.$phase.shared_bytes";$notSharedPages=ConvertTo-G130U1UInt64 $f.not_shared_pages "working.$phase.not_shared_pages";$notSharedBytes=ConvertTo-G130U1UInt64 $f.not_shared_bytes "working.$phase.not_shared_bytes";$filePages=ConvertTo-G130U1UInt64 $f.file_backed_pages "working.$phase.file_backed_pages";$fileBytes=ConvertTo-G130U1UInt64 $f.file_backed_bytes "working.$phase.file_backed_bytes"
        if($mapping-ne$c.sidecar_bytes-or$pageSize-eq0-or$queried-ne[UInt64][math]::Ceiling([double]$mapping/[double]$pageSize)-or$residentPages-gt$queried-or$residentBytes-ne$residentPages*$pageSize-or$sharedPages+$notSharedPages-ne$residentPages-or$sharedBytes+$notSharedBytes-ne$residentBytes-or$filePages-gt$residentPages-or$fileBytes-ne$filePages*$pageSize-or(ConvertTo-G130U1UInt64 $f.query_calls "working.$phase.query_calls")-eq0){throw"working.$phase coverage/balance mismatch"}
        $working+=[pscustomobject]$f
    }

    $legacy=ConvertFrom-G130U1KeyValueLine $legacyLines[0] 'q1-0-profile'
    $legacyKeys=@('result','enabled','resident_hits_total','pinned_route_hits','pageable_route_hits','resident_h2d_bytes_total','pinned_h2d_bytes','pageable_h2d_bytes','h2d_enqueue_seconds_total','pinned_h2d_enqueue_seconds','pageable_h2d_enqueue_seconds','upload_sync_calls','upload_sync_seconds_total','pinned_upload_sync_seconds','pageable_upload_sync_seconds','sync_attribution','q1_kernel_calls','q1_kernel_seconds','mixed_join_calls','mixed_join_seconds','timer_failures')
    Assert-G130U1KeySet $legacy $legacyKeys 'legacy';Assert-G130U1ExactValue $legacy 'result' 'summary' 'legacy';Assert-G130U1ExactValue $legacy 'enabled' '1' 'legacy';Assert-G130U1ExactValue $legacy 'sync_attribution' 'bytes' 'legacy'
    foreach($name in @('resident_hits_total','pinned_route_hits','pageable_route_hits','resident_h2d_bytes_total','pinned_h2d_bytes','pageable_h2d_bytes','upload_sync_calls','q1_kernel_calls','mixed_join_calls','timer_failures')){[void](ConvertTo-G130U1UInt64 $legacy[$name] "legacy.$name")}
    foreach($name in $legacyKeys|Where-Object{$_-like'*seconds*'}){[void](ConvertTo-G130U1FiniteDouble $legacy[$name] "legacy.$name")}
    if((ConvertTo-G130U1UInt64 $legacy.timer_failures 'legacy.timer_failures')-ne0){throw'legacy timer failure'}
    $hits=ConvertTo-G130U1UInt64 $legacy.resident_hits_total 'legacy.hits';$pHits=ConvertTo-G130U1UInt64 $legacy.pinned_route_hits 'legacy.pinned_hits';$pgHits=ConvertTo-G130U1UInt64 $legacy.pageable_route_hits 'legacy.pageable_hits'
    $bytes=ConvertTo-G130U1UInt64 $legacy.resident_h2d_bytes_total 'legacy.bytes';$pBytes=ConvertTo-G130U1UInt64 $legacy.pinned_h2d_bytes 'legacy.pinned_bytes';$pgBytes=ConvertTo-G130U1UInt64 $legacy.pageable_h2d_bytes 'legacy.pageable_bytes'
    if($hits-ne$pHits+$pgHits-or$bytes-ne$pBytes+$pgBytes){throw'legacy hit/byte balance mismatch'}
    $enqueue=ConvertTo-G130U1FiniteDouble $legacy.h2d_enqueue_seconds_total 'legacy.enqueue';$pEnqueue=ConvertTo-G130U1FiniteDouble $legacy.pinned_h2d_enqueue_seconds 'legacy.pinned_enqueue';$pgEnqueue=ConvertTo-G130U1FiniteDouble $legacy.pageable_h2d_enqueue_seconds 'legacy.pageable_enqueue'
    $sync=ConvertTo-G130U1FiniteDouble $legacy.upload_sync_seconds_total 'legacy.sync';$pSync=ConvertTo-G130U1FiniteDouble $legacy.pinned_upload_sync_seconds 'legacy.pinned_sync';$pgSync=ConvertTo-G130U1FiniteDouble $legacy.pageable_upload_sync_seconds 'legacy.pageable_sync'
    if([math]::Abs($enqueue-$pEnqueue-$pgEnqueue)-gt1e-6-or[math]::Abs($sync-$pSync-$pgSync)-gt1e-6){throw'legacy timing split balance mismatch'}
    if($pgHits-gt0-and($pgEnqueue-le0-or$pgBytes-eq0)){throw'U3 pageable H2D telemetry missing'}
    $u3Bandwidth=if($pgEnqueue-gt0){[double]$pgBytes/$pgEnqueue}else{$null}

    $route=ConvertFrom-G130U1KeyValueLine $routeLines[0] 'q1-0-profile-route'
    $routeKeys=@('result','final','path','enabled','unit','clock','bucket_scope','phase_model','denominator','limitation_hot_device','limitation_failed_calls','cleanup_required','missing_cleanup_policy','host_device_additive','summary_valid','cleanup_sync_ok','cleanup_sync_error','timer_failures','timing_values_ok','bucket_gap_ok','bucket_gap_tolerance_seconds','calls','completed_calls','failed_calls','call_seconds','bucket_seconds','bucket_gap_seconds','entry_contract_calls','entry_contract_seconds','selection_d2h_calls','selection_d2h_seconds','classify_map_calls','classify_map_seconds','scratch_prepare_calls','scratch_prepare_seconds','metadata_h2d_calls','metadata_h2d_seconds','hot_branch_calls','hot_branch_seconds','tier_observe_calls','tier_observe_seconds','q1_dispatch_prepare_calls','q1_dispatch_prepare_seconds','q1_entry_calls','q1_entry_seconds','q1_selected_load_calls','q1_selected_load_seconds','q1_prepare_calls','q1_prepare_seconds','q1_kernel_calls','q1_kernel_seconds','q1_kernel_device_calls','q1_kernel_device_seconds','q1_kernel_device_missing_calls','q1_kernel_device_in_bucket','q1_kernel_fenced_calls','q1_kernel_unfenced_calls','join_publish_calls','join_publish_seconds')
    Assert-G130U1KeySet $route $routeKeys 'route'
    foreach($pair in @(@('result','summary'),@('final','1'),@('path','mixed_q1'),@('enabled','1'),@('unit','seconds'),@('clock','host_monotonic'),@('bucket_scope','completed'),@('phase_model','disjoint'),@('denominator','per_bucket_calls'),@('limitation_hot_device','unmeasured_no_new_sync'),@('limitation_failed_calls','counts_only'),@('cleanup_required','1'),@('missing_cleanup_policy','incomplete_negative'),@('host_device_additive','0'),@('summary_valid','1'),@('cleanup_sync_ok','1'),@('timing_values_ok','1'),@('bucket_gap_ok','1'),@('q1_kernel_device_in_bucket','0'))){Assert-G130U1ExactValue $route $pair[0] $pair[1] 'route'}
    foreach($name in $routeKeys|Where-Object{$_-like'*_seconds'}){if($name-eq'bucket_gap_seconds'){[void](ConvertTo-G130U1FiniteDouble $route[$name] "route.$name" -AllowNegative)}else{[void](ConvertTo-G130U1FiniteDouble $route[$name] "route.$name")}}
    $routeCountNames=@('cleanup_sync_error','timer_failures','calls','completed_calls','failed_calls','entry_contract_calls','selection_d2h_calls','classify_map_calls','scratch_prepare_calls','metadata_h2d_calls','hot_branch_calls','tier_observe_calls','q1_dispatch_prepare_calls','q1_entry_calls','q1_selected_load_calls','q1_prepare_calls','q1_kernel_calls','q1_kernel_device_calls','q1_kernel_device_missing_calls','q1_kernel_fenced_calls','q1_kernel_unfenced_calls','join_publish_calls')
    foreach($name in $routeCountNames){[void](ConvertTo-G130U1UInt64 $route[$name] "route.$name")}
    if([UInt64]$route.cleanup_sync_error-ne0-or[UInt64]$route.timer_failures-ne0-or[UInt64]$route.failed_calls-ne0-or[UInt64]$route.q1_kernel_unfenced_calls-ne0-or[UInt64]$route.q1_kernel_device_missing_calls-ne0){throw'route failure counter nonzero'}
    $calls=[UInt64]$route.calls;$completed=[UInt64]$route.completed_calls;if($completed-eq0-or$calls-ne$completed){throw'route call balance failed'}
    foreach($name in @('entry_contract_calls','selection_d2h_calls','classify_map_calls','hot_branch_calls','join_publish_calls')){if([UInt64]$route[$name]-ne$completed){throw"route completed coverage failed: $name"}}

    $selection=ConvertFrom-G130U1KeyValueLine $selectionLines[0] 'q1-0-profile-selection'
    $selectionKeys=@('result','final','path','enabled','unit','coverage_scope','denominator','calls','completed_calls','failed_calls','requested_routes','completed_routes','hot_routes','q1_routes','all_iq2_calls','mixed_hot_q1_calls','q1_only_calls','join_kernel_calls','timer_failures','cleanup_sync_ok','call_balance_ok','route_balance_ok','host_coverage_ok','device_coverage_ok','coverage_ok','summary_valid')
    Assert-G130U1KeySet $selection $selectionKeys 'selection'
    foreach($pair in @(@('result','summary'),@('final','1'),@('path','mixed_q1'),@('enabled','1'),@('unit','count'),@('coverage_scope','completed'),@('denominator','completed_routes'),@('cleanup_sync_ok','1'),@('call_balance_ok','1'),@('route_balance_ok','1'),@('host_coverage_ok','1'),@('device_coverage_ok','1'),@('coverage_ok','1'),@('summary_valid','1'))){Assert-G130U1ExactValue $selection $pair[0] $pair[1] 'selection'}
    foreach($name in $selectionKeys|Where-Object{$_-notin@('result','final','path','enabled','unit','coverage_scope','denominator','cleanup_sync_ok','call_balance_ok','route_balance_ok','host_coverage_ok','device_coverage_ok','coverage_ok','summary_valid')}){[void](ConvertTo-G130U1UInt64 $selection[$name] "selection.$name")}
    if([UInt64]$selection.failed_calls-ne0-or[UInt64]$selection.timer_failures-ne0-or[UInt64]$selection.calls-ne[UInt64]$selection.completed_calls){throw'selection call balance failed'}
    $completedRoutes=[UInt64]$selection.completed_routes;$hotRoutes=[UInt64]$selection.hot_routes;$q1Routes=[UInt64]$selection.q1_routes
    $expectedCalls=[UInt64](43*64);$expectedRoutes=[UInt64]($expectedCalls*6)
    if($calls-ne$expectedCalls-or$completed-ne$expectedCalls){throw"U1 absolute call cardinality expected $expectedCalls"}
    if([UInt64]$selection.calls-ne$expectedCalls-or[UInt64]$selection.completed_calls-ne$expectedCalls){throw"selection absolute call cardinality expected $expectedCalls"}
    if([UInt64]$selection.requested_routes-ne$expectedRoutes-or$completedRoutes-ne$expectedRoutes-or$completedRoutes-ne($hotRoutes+$q1Routes)){throw"selection absolute route cardinality expected $expectedRoutes"}
    if([UInt64]$selection.all_iq2_calls+[UInt64]$selection.mixed_hot_q1_calls+[UInt64]$selection.q1_only_calls-ne$expectedCalls){throw'selection path call partition failed'}
    $q1Path=[UInt64]$selection.mixed_hot_q1_calls+[UInt64]$selection.q1_only_calls
    foreach($name in @('scratch_prepare_calls','metadata_h2d_calls','tier_observe_calls','q1_dispatch_prepare_calls','q1_entry_calls','q1_selected_load_calls','q1_prepare_calls','q1_kernel_calls')){if([UInt64]$route[$name]-ne$q1Path){throw"route Q1 coverage failed: $name"}}
    if([UInt64]$selection.join_kernel_calls-ne$q1Path-or[UInt64]$route.q1_kernel_fenced_calls-ne[UInt64]$route.q1_kernel_calls-or[UInt64]$route.q1_kernel_device_calls-ne[UInt64]$route.q1_kernel_calls){throw'route device/fence/join coverage failed'}
    if([UInt64]$legacy.q1_kernel_calls-ne[UInt64]$route.q1_kernel_calls-or[UInt64]$legacy.mixed_join_calls-ne$q1Path){throw'legacy/route semantic call balance failed'}
    $hostBucketNames=@('entry_contract_seconds','selection_d2h_seconds','classify_map_seconds','scratch_prepare_seconds','metadata_h2d_seconds','hot_branch_seconds','tier_observe_seconds','q1_dispatch_prepare_seconds','q1_entry_seconds','q1_selected_load_seconds','q1_prepare_seconds','q1_kernel_seconds','join_publish_seconds')
    $reconstructed=0.0;foreach($name in $hostBucketNames){$reconstructed+=ConvertTo-G130U1FiniteDouble $route[$name] "route.$name"}
    $bucket=ConvertTo-G130U1FiniteDouble $route.bucket_seconds 'route.bucket_seconds';$callSeconds=ConvertTo-G130U1FiniteDouble $route.call_seconds 'route.call_seconds';$gap=ConvertTo-G130U1FiniteDouble $route.bucket_gap_seconds 'route.bucket_gap_seconds' -AllowNegative;$tolerance=ConvertTo-G130U1FiniteDouble $route.bucket_gap_tolerance_seconds 'route.bucket_gap_tolerance_seconds'
    if([math]::Abs($reconstructed-$bucket)-gt$tolerance-or[math]::Abs(($callSeconds-$bucket)-$gap)-gt$tolerance-or$gap-lt-1e-6){throw'route host bucket reconstruction failed'}

    $tokenKeysProgress=@('schema','result','final','gen','decode_elapsed_seconds')
    $tokenKeysFinal=@('schema','result','final','generated_tokens','decode_elapsed_seconds','finish')
    $tokenTimes=[Collections.ArrayList]::new();$expectedGen=1;$finalToken=$null
    foreach($line in $tokenLines){$f=ConvertFrom-G130U1KeyValueLine $line 'q1-0-profile-token';Assert-G130U1ExactValue $f 'schema' 'g130_u1_profile_token_v1' 'token'
        if($f.result-ceq'progress'){if($null-ne$finalToken){throw'token progress observed after final summary'};Assert-G130U1KeySet $f $tokenKeysProgress 'token.progress';Assert-G130U1ExactValue $f 'final' '0' 'token.progress';$gen=ConvertTo-G130U1UInt64 $f.gen 'token.gen';$elapsed=ConvertTo-G130U1FiniteDouble $f.decode_elapsed_seconds 'token.elapsed';if($gen-ne$expectedGen){throw"token progress sequence expected $expectedGen got $gen"};if($tokenTimes.Count-and$elapsed-le[double]$tokenTimes[$tokenTimes.Count-1].seconds){throw'token decode clock did not advance'};[void]$tokenTimes.Add([pscustomobject]@{gen=$gen;seconds=$elapsed});$expectedGen++}
        elseif($f.result-ceq'summary'){if($null-ne$finalToken){throw'duplicate token final'};if($expectedGen-ne65){throw'token final summary preceded complete progress 1..64'};Assert-G130U1KeySet $f $tokenKeysFinal 'token.final';Assert-G130U1ExactValue $f 'final' '1' 'token.final';Assert-G130U1ExactValue $f 'finish' 'length' 'token.final';$finalToken=$f}else{throw'unknown token telemetry result'}
    }
    if($expectedGen-ne65-or$null-eq$finalToken-or(ConvertTo-G130U1UInt64 $finalToken.generated_tokens 'token.final.generated')-ne64){throw'token telemetry completeness failed'}
    $decodeElapsed=ConvertTo-G130U1FiniteDouble $finalToken.decode_elapsed_seconds 'token.final.elapsed';$lastProgress=[double]$tokenTimes[63].seconds
    if($decodeElapsed-lt$lastProgress-or($decodeElapsed-$lastProgress)-gt30.0){throw'token final elapsed is not a plausible monotonic decode wall'}
    $runtimeLines=@($lines|ForEach-Object{$message=ConvertTo-G130U1CanonicalServerLogLine $_;if($null-ne$message){$message}})
    $finishLines=@($runtimeLines|Where-Object{$_-match'^ds4-server: (?:chat|completion) .*\bgen=64\b(?: [A-Z_]+)*\s+finish=length\s+[0-9]+(?:\.[0-9]+)?s$'})
    if($finishLines.Count-ne1){throw"exact gen=64 finish=length line required, got $($finishLines.Count)"}
    $progress50=@($runtimeLines|Where-Object{$_-match'^ds4-server: (?:chat|completion) .*\bgen=50\b(?: [A-Z_]+)*\s+decoding\b'})
    $progress64=@($runtimeLines|Where-Object{$_-match'^ds4-server: (?:chat|completion) .*\bgen=64\b(?: [A-Z_]+)*\s+decoding\b'})
    if($progress50.Count-ne1-or$progress64.Count-ne1){throw'runtime decode cadence must contain gen=50 and final gen=64 progress'}

    $coverage=[double]$completed/[double]$calls;$hostPerToken=$callSeconds/64.0;$decodeTps=64.0/$decodeElapsed;$decodePerToken=$decodeElapsed/64.0;$residual=$decodePerToken-$hostPerToken
    if($residual-lt-0.000001){throw'host attribution exceeds decode elapsed'}
    $p2=[bool]($hostPerToken-ge$c.p2_host_seconds_per_token_minimum-and$coverage-ge$c.p2_completed_call_coverage_minimum)
    [pscustomobject][ordered]@{
        schema='g130_u1_profile_summary_v2';valid=$true;measurement_basis='profile-on, existing-fence'
        existing_base_fences_and_events_expected=$true;claim_of_zero_synchronization=$false
        generated_tokens=64;finish_reason='length'
        legacy=[pscustomobject]$legacy;resident_arena=[pscustomobject]$resident;source_working_set=$working
        route=[pscustomobject]$route;selection=[pscustomobject]$selection
        u3=[pscustomobject][ordered]@{pageable_h2d_bytes=$pgBytes;pageable_h2d_enqueue_seconds=$pgEnqueue;effective_pageable_h2d_bytes_per_second=$u3Bandwidth}
        route_count_expected=$completedRoutes;route_count_observed=[UInt64]($hotRoutes+$q1Routes)
        q1_path_call_count_expected=$q1Path;q1_path_call_count_observed=[UInt64]$route.q1_kernel_calls
        completed_call_coverage=$coverage;host_bucket_seconds=$callSeconds
        host_bucket_seconds_per_token=$hostPerToken;device_kernel_seconds_diagnostic=[double]$route.q1_kernel_device_seconds
        decode_elapsed_seconds=$decodeElapsed;decode_tokens_per_second=$decodeTps;decode_seconds_per_token=$decodePerToken
        unattributed_residual_seconds_per_token=$residual;host_device_times_summed=$false
        p2_authorized=$p2;decision=$(if($p2){'P2_AUTHORIZED_DIAGNOSTIC_ONLY'}else{'STOP_AND_REPLAN'})
    }
}

function Assert-G130U1PreflightProbeV1 {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Probe)
    $c=Get-G130U1Constants
    $top=@('schema','captured_utc','app_container','conflicting_processes','background_activity','gpu','memory','paging','disk','process_baseline','cpu_temperature','quiet_windows','identity','probe_status','probe_errors')
    Assert-G130U1ExactPropertySet $Probe $top 'preflight probe'
    if([string]$Probe.schema-cne'g130_u1_preflight_probe_v1'){throw'preflight probe schema/version mismatch'}
    if($null-eq$Probe.app_container-or$Probe.app_container-isnot[bool]){throw'preflight app_container type invalid'}
    foreach($name in @('conflicting_processes','background_activity','quiet_windows','probe_status','probe_errors')){if($null-eq$Probe.$name){throw"preflight $name is null"}}
    Assert-G130U1ExactPropertySet $Probe.gpu @('vram_used_mib','power_w','temperature_c','utilization_percent','compute_processes') 'preflight gpu'
    Assert-G130U1ExactPropertySet $Probe.memory @('available_bytes','planned_bytes') 'preflight memory'
    Assert-G130U1ExactPropertySet $Probe.paging @('pages_output_total','page_faults_total','pages_per_sec','page_reads_per_sec') 'preflight paging'
    Assert-G130U1ExactPropertySet $Probe.disk @('volume','queue_length','read_bytes_per_sec','write_bytes_per_sec','free_bytes') 'preflight disk'
    Assert-G130U1ExactPropertySet $Probe.process_baseline @('process_count','working_set_bytes') 'preflight process baseline'
    Assert-G130U1ExactPropertySet $Probe.cpu_temperature @('temperature_c','provider','sensor_id','sensor_name') 'preflight CPU temperature'
    Assert-G130U1ExactPropertySet $Probe.identity @('schema','git','build','model','sidecar','config_path','config_sha256') 'preflight identity'
    if([string]$Probe.identity.schema-cne'g130_u1_build_identity_v2'){throw'preflight identity schema/version mismatch'}
    Assert-G130U1ExactPropertySet $Probe.identity.git @('head','branch','repository_root','expected_base','base_ancestor','dirty','status','status_includes_untracked') 'preflight identity.git'
    Assert-G130U1ExactPropertySet $Probe.identity.build @('manifest_path','manifest_sha256','schema','head','configuration','worktree_dirty_at_build_start','input_fingerprint_sha256','executable_path','executable_bytes','executable_sha256','observed_executable_sha256') 'preflight identity.build'
    $fileIdentityKeys=@('path','bytes','receipt_path','receipt_file_sha256','receipt_sha256','receipt_verified_at','model_rehashed')
    Assert-G130U1ExactPropertySet $Probe.identity.model $fileIdentityKeys 'preflight identity.model'
    Assert-G130U1ExactPropertySet $Probe.identity.sidecar $fileIdentityKeys 'preflight identity.sidecar'
    foreach($name in @('head','branch','repository_root','expected_base')){Assert-G130U1StringValue $Probe.identity.git.$name "preflight identity.git.$name"}
    foreach($name in @('base_ancestor','dirty','status_includes_untracked')){if($Probe.identity.git.$name-isnot[bool]){throw"preflight identity.git.$name type invalid"}}
    foreach($name in @('manifest_path','schema','head','configuration','input_fingerprint_sha256','executable_path','executable_sha256','observed_executable_sha256')){Assert-G130U1StringValue $Probe.identity.build.$name "preflight identity.build.$name"}
    if($Probe.identity.build.worktree_dirty_at_build_start-isnot[bool]){throw'preflight build worktree_dirty_at_build_start type invalid'}
    Assert-G130U1TypedNumber $Probe.identity.build.executable_bytes 'preflight identity.build.executable_bytes' -StrictlyPositive -Integral
    foreach($kind in @('model','sidecar')){foreach($name in @('path','receipt_path','receipt_verified_at')){Assert-G130U1StringValue $Probe.identity.$kind.$name "preflight identity.$kind.$name"};Assert-G130U1TypedNumber $Probe.identity.$kind.bytes "preflight identity.$kind.bytes" -StrictlyPositive -Integral;if($Probe.identity.$kind.model_rehashed-isnot[bool]){throw"preflight identity.$kind.model_rehashed type invalid"};foreach($name in @('receipt_file_sha256','receipt_sha256')){if($Probe.identity.$kind.$name-isnot[string]-or[string]$Probe.identity.$kind.$name-cnotmatch'^[0-9a-f]{64}$'){throw"preflight identity.$kind.$name invalid"}}}
    Assert-G130U1StringValue $Probe.identity.config_path 'preflight identity.config_path'
    if($Probe.identity.config_sha256-isnot[string]-or[string]$Probe.identity.config_sha256-cnotmatch'^[0-9a-f]{64}$'){throw'preflight identity.config_sha256 invalid'}
    if($Probe.identity.git.status_includes_untracked-ne$true-or$null-eq$Probe.identity.git.status){throw'preflight git status evidence incomplete'}
    foreach($row in @($Probe.identity.git.status)){Assert-G130U1ExactPropertySet $row @('porcelain') 'preflight git.status row';Assert-G130U1StringValue $row.porcelain 'preflight git.status.porcelain'}
    foreach($collectionName in @('conflicting_processes','background_activity')){foreach($row in @($Probe.$collectionName)){Assert-G130U1ExactPropertySet $row @('process_id','parent_process_id','name','command_line') "preflight $collectionName row";Assert-G130U1TypedNumber $row.process_id "$collectionName.process_id" -StrictlyPositive -Integral;Assert-G130U1TypedNumber $row.parent_process_id "$collectionName.parent_process_id" -Integral;Assert-G130U1StringValue $row.name "$collectionName.name";Assert-G130U1StringValue $row.command_line "$collectionName.command_line" -AllowEmpty}}
    foreach($row in @($Probe.gpu.compute_processes)){Assert-G130U1ExactPropertySet $row @('pid','process_name') 'preflight gpu.compute_process row';Assert-G130U1TypedNumber $row.pid 'gpu.compute_process.pid' -StrictlyPositive -Integral;Assert-G130U1StringValue $row.process_name 'gpu.compute_process.process_name'}
    foreach($row in @($Probe.probe_errors)){Assert-G130U1ExactPropertySet $row @('name','error') 'preflight probe error';Assert-G130U1StringValue $row.name 'probe_error.name';Assert-G130U1StringValue $row.error 'probe_error.error'}
    if($Probe.identity.model.model_rehashed-ne$false-or$Probe.identity.sidecar.model_rehashed-ne$false){throw'preflight model hashing policy violated'}
    try{[void][DateTime]::Parse([string]$Probe.captured_utc)}catch{throw'preflight captured_utc invalid'}
    foreach($item in @(
        @($Probe.gpu.vram_used_mib,'gpu.vram_used_mib',$true,$false),@($Probe.gpu.power_w,'gpu.power_w',$true,$false),@($Probe.gpu.temperature_c,'gpu.temperature_c',$true,$false),@($Probe.gpu.utilization_percent,'gpu.utilization_percent',$false,$false),
        @($Probe.memory.available_bytes,'memory.available_bytes',$true,$true),@($Probe.memory.planned_bytes,'memory.planned_bytes',$true,$true),
        @($Probe.paging.pages_output_total,'paging.pages_output_total',$true,$true),@($Probe.paging.page_faults_total,'paging.page_faults_total',$true,$true),@($Probe.paging.pages_per_sec,'paging.pages_per_sec',$false,$true),@($Probe.paging.page_reads_per_sec,'paging.page_reads_per_sec',$false,$true),
        @($Probe.disk.queue_length,'disk.queue_length',$false,$false),@($Probe.disk.read_bytes_per_sec,'disk.read_bytes_per_sec',$false,$true),@($Probe.disk.write_bytes_per_sec,'disk.write_bytes_per_sec',$false,$true),@($Probe.disk.free_bytes,'disk.free_bytes',$true,$true),
        @($Probe.process_baseline.process_count,'process_baseline.process_count',$true,$true),@($Probe.process_baseline.working_set_bytes,'process_baseline.working_set_bytes',$true,$true),@($Probe.cpu_temperature.temperature_c,'cpu_temperature.temperature_c',$true,$false)
    )){Assert-G130U1TypedNumber $item[0] $item[1] -StrictlyPositive:([bool]$item[2]) -Integral:([bool]$item[3])}
    Assert-G130U1StringValue $Probe.disk.volume 'disk.volume';Assert-G130U1StringValue $Probe.cpu_temperature.provider 'cpu_temperature.provider';Assert-G130U1StringValue $Probe.cpu_temperature.sensor_id 'cpu_temperature.sensor_id';Assert-G130U1StringValue $Probe.cpu_temperature.sensor_name 'cpu_temperature.sensor_name'
    $quiet=@($Probe.quiet_windows);if($quiet.Count-ne3){throw'preflight quiet window count must be exactly three'}
    for($i=0;$i-lt3;$i++){Assert-G130U1ExactPropertySet $quiet[$i] @('index','captured_utc','cpu_percent','disk_queue_length','gpu_percent','gpu_power_w','gpu_compute_process_count') "quiet[$i]";Assert-G130U1TypedNumber $quiet[$i].index "quiet[$i].index" -StrictlyPositive -Integral;Assert-G130U1TypedNumber $quiet[$i].cpu_percent "quiet[$i].cpu_percent";Assert-G130U1TypedNumber $quiet[$i].disk_queue_length "quiet[$i].disk_queue_length";Assert-G130U1TypedNumber $quiet[$i].gpu_percent "quiet[$i].gpu_percent";Assert-G130U1TypedNumber $quiet[$i].gpu_power_w "quiet[$i].gpu_power_w" -StrictlyPositive;Assert-G130U1TypedNumber $quiet[$i].gpu_compute_process_count "quiet[$i].gpu_compute_process_count" -Integral;if([int]$quiet[$i].index-ne$i+1){throw'quiet window index mismatch'};try{[void][DateTime]::Parse([string]$quiet[$i].captured_utc)}catch{throw"quiet[$i] captured_utc invalid"}}
    foreach($kind in @('model','sidecar')){try{[void][DateTime]::Parse([string]$Probe.identity.$kind.receipt_verified_at)}catch{throw"preflight identity.$kind receipt_verified_at invalid"}}
    $expected=@('app_container','processes','system_counters','gpu','cpu_temperature','identity','quiet_window_1','quiet_window_2','quiet_window_3','probe_completeness')
    $seen=@{};foreach($status in @($Probe.probe_status)){Assert-G130U1ExactPropertySet $status @('name','status') 'probe status';Assert-G130U1StringValue $status.name 'probe_status.name';Assert-G130U1StringValue $status.status 'probe_status.status';$name=[string]$status.name;if($name-notin$expected){throw"unknown probe status: $name"};if($seen.ContainsKey($name)){throw"duplicate probe status: $name"};$seen[$name]=$true;if([string]$status.status-cne'ok'){throw"probe status not ok: $name"}}
    if($seen.Count-ne$expected.Count){throw'probe status set incomplete'}
    if(@($Probe.probe_errors).Count-ne0){throw'probe_errors must be empty'}
    if([string]$Probe.identity.build.schema-cne$c.expected_build_manifest_schema){throw'preflight build manifest schema/version mismatch'}
}

function Test-G130U1Preflight {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Probe)
    Assert-G130U1PreflightProbeV1 $Probe
    $c=Get-G130U1Constants;$gates=[Collections.ArrayList]::new()
    function Add-LocalGate([string]$Id,[bool]$Pass,[string]$Detail){[void]$gates.Add([pscustomobject][ordered]@{id=$Id;pass=$Pass;detail=$Detail})}
    $conflicts=@($Probe.conflicting_processes);$background=@($Probe.background_activity);$gpuCompute=@($Probe.gpu.compute_processes);$diskQueue=$Probe.disk.queue_length
    Add-LocalGate 'P-1' ([bool]($conflicts.Count-eq0-and$background.Count-eq0-and$gpuCompute.Count-eq0-and(Test-G130U1PresentNumber $diskQueue)-and[double]$diskQueue-lt$c.disk_queue_max_exclusive)) "conflicts=$($conflicts.Count) background=$($background.Count) gpu_compute=$($gpuCompute.Count) disk_queue=$diskQueue"
    $vram=$Probe.gpu.vram_used_mib;$power=$Probe.gpu.power_w;$gpuTemp=$Probe.gpu.temperature_c;$gpuUtil=$Probe.gpu.utilization_percent
    Add-LocalGate 'P-2' ([bool]((Test-G130U1PresentNumber $vram)-and[double]$vram-le$c.gpu_vram_idle_max_mib-and(Test-G130U1PresentNumber $power -StrictlyPositive)-and[double]$power-le$c.gpu_power_plausible_max_w-and(Test-G130U1PresentNumber $gpuTemp -StrictlyPositive)-and[double]$gpuTemp-lt$c.gpu_temperature_plausible_max_c-and(Test-G130U1PresentNumber $gpuUtil)-and[double]$gpuUtil-le$c.gpu_utilization_idle_max_percent)) "vram=$vram power=$power gpu_temp=$gpuTemp util=$gpuUtil"
    $available=$Probe.memory.available_bytes;$planned=$Probe.memory.planned_bytes
    Add-LocalGate 'P-3' ([bool]((Test-G130U1PresentNumber $available -StrictlyPositive)-and(Test-G130U1PresentNumber $planned -StrictlyPositive)-and[UInt64]$planned-eq$c.planned_ram_bytes-and[UInt64]$available-ge$c.planned_ram_bytes)) "available=$available required=$($c.planned_ram_bytes)"
    $p4=(Test-G130U1PresentNumber $Probe.paging.pages_output_total -StrictlyPositive)-and(Test-G130U1PresentNumber $Probe.paging.page_faults_total -StrictlyPositive)-and(Test-G130U1PresentNumber $Probe.paging.pages_per_sec)-and(Test-G130U1PresentNumber $Probe.paging.page_reads_per_sec)-and(Test-G130U1PresentNumber $Probe.process_baseline.working_set_bytes -StrictlyPositive)-and(Test-G130U1PresentNumber $Probe.process_baseline.process_count -StrictlyPositive)-and(Test-G130U1PresentNumber $Probe.disk.read_bytes_per_sec)-and(Test-G130U1PresentNumber $Probe.disk.write_bytes_per_sec)
    Add-LocalGate 'P-4' ([bool]$p4) 'paging/process/disk baselines numeric'
    $p5=$true;foreach($w in @($Probe.quiet_windows)){$p5=$p5-and(Test-G130U1PresentNumber $w.cpu_percent -StrictlyPositive)-and[double]$w.cpu_percent-le$c.quiet_cpu_max_percent-and(Test-G130U1PresentNumber $w.disk_queue_length)-and[double]$w.disk_queue_length-lt$c.disk_queue_max_exclusive-and(Test-G130U1PresentNumber $w.gpu_percent)-and[double]$w.gpu_percent-le$c.gpu_utilization_idle_max_percent-and(Test-G130U1PresentNumber $w.gpu_power_w -StrictlyPositive)-and(Test-G130U1PresentNumber $w.gpu_compute_process_count)-and[UInt64]$w.gpu_compute_process_count-eq0};Add-LocalGate 'P-5' ([bool]$p5) 'three quiet windows verified'
    $identity=$Probe.identity;$git=$identity.git;$build=$identity.build;$head=[string]$git.head
    $p6=$head-match'^[0-9a-f]{40}$'-and[string]$build.head-ceq$head-and[string]$git.branch-ceq'g130/u1-harness'-and[string]$git.expected_base-ceq$c.expected_git_base-and-not[string]::IsNullOrWhiteSpace([string]$git.repository_root)-and$git.base_ancestor-eq$true-and$git.dirty-eq$false-and@($git.status).Count-eq0-and[string]$build.configuration-ceq'Release'-and$build.worktree_dirty_at_build_start-eq$false-and[string]$build.schema-ceq$c.expected_build_manifest_schema-and[string]$build.manifest_sha256-match'^[0-9a-f]{64}$'-and[string]$build.input_fingerprint_sha256-match'^[0-9a-f]{64}$'-and[UInt64]$build.executable_bytes-gt0-and[string]$build.executable_sha256-match'^[0-9a-f]{64}$'-and[string]$build.executable_sha256-ceq[string]$build.observed_executable_sha256-and[UInt64]$identity.model.bytes-eq$c.model_bytes-and[string]$identity.model.receipt_file_sha256-match'^[0-9a-f]{64}$'-and[string]$identity.model.receipt_sha256-ceq$c.model_sha256-and[UInt64]$identity.sidecar.bytes-eq$c.sidecar_bytes-and[string]$identity.sidecar.receipt_file_sha256-match'^[0-9a-f]{64}$'-and[string]$identity.sidecar.receipt_sha256-ceq$c.sidecar_sha256-and-not[string]::IsNullOrWhiteSpace([string]$identity.config_path)-and[string]$identity.config_sha256-match'^[0-9a-f]{64}$'
    Add-LocalGate 'P-6' ([bool]$p6) "git_head=$head status_rows=$(@($git.status).Count)"
    $cpuTemp=$Probe.cpu_temperature.temperature_c;$provider=[string]$Probe.cpu_temperature.provider;$sensorId=[string]$Probe.cpu_temperature.sensor_id
    Add-LocalGate 'P-7' ([bool]((Test-G130U1PresentNumber $gpuTemp -StrictlyPositive)-and[double]$gpuTemp-le$c.gpu_temperature_idle_max_c-and(Test-G130U1PresentNumber $cpuTemp -StrictlyPositive)-and[double]$cpuTemp-lt$c.cpu_temperature_plausible_max_c-and$provider-match'^(LibreHardwareMonitor|OpenHardwareMonitor)$'-and$sensorId-match'(?i)/(?:intelcpu|amdcpu|cpu)/')) "gpu_temp=$gpuTemp cpu_temp=$cpuTemp provider=$provider sensor_id=$sensorId"
    $free=$Probe.disk.free_bytes;$p8=$Probe.app_container-eq$false-and[string]$Probe.disk.volume-ceq'C:'-and(Test-G130U1PresentNumber $free -StrictlyPositive)-and[UInt64]$free-ge$c.disk_free_floor_bytes
    Add-LocalGate 'P-8' ([bool]$p8) "schema/probes/appcontainer valid; disk_free=$free minimum=$($c.disk_free_floor_bytes)"
    [pscustomobject][ordered]@{schema='g130_u1_preflight_validation_v2';pass=(@($gates|Where-Object{-not$_.pass}).Count-eq0);planned_ram_bytes=$c.planned_ram_bytes;disk_free_floor_bytes=$c.disk_free_floor_bytes;gates=@($gates)}
}

function Get-G130U1ArtifactRecords {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string[]]$Paths)
    @($Paths|ForEach-Object{$exists=Test-Path -LiteralPath $_ -PathType Leaf;[pscustomobject][ordered]@{path=$_;exists=$exists;bytes=$(if($exists){[UInt64](Get-Item -LiteralPath $_).Length}else{[UInt64]0});sha256=$(if($exists){Get-G130U1Sha256File $_}else{$null})}})
}

function ConvertTo-G130U1WindowsArgument {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][AllowEmptyString()][string]$Value)
    if($Value.Length-gt0-and$Value-notmatch'[\s"]'){return $Value}
    $b=[Text.StringBuilder]::new();[void]$b.Append('"');$slashes=0
    foreach($ch in $Value.ToCharArray()){
        if($ch-eq'\'){$slashes++;continue}
        if($ch-eq'"'){[void]$b.Append(('\' * (2*$slashes+1)));[void]$b.Append('"');$slashes=0;continue}
        if($slashes){[void]$b.Append(('\'*$slashes));$slashes=0};[void]$b.Append($ch)
    }
    if($slashes){[void]$b.Append(('\'*(2*$slashes)))};[void]$b.Append('"');$b.ToString()
}

function Join-G130U1WindowsArguments {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Values)
    (($Values|ForEach-Object{ConvertTo-G130U1WindowsArgument $_})-join' ')
}

function Assert-G130U1SafePathText {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Value,[Parameter(Mandatory=$true)][string]$Context)
    if([string]::IsNullOrWhiteSpace($Value)-or$Value-match'["\r\n]'){throw"$Context contains a forbidden quote/newline or is empty"}
}

function Initialize-G130U1Utf8FramerType {
    if('G130U1Utf8LineFramer'-as[type]){return}
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Text;
public sealed class G130U1Utf8LineFramer {
    private readonly Decoder decoder = new UTF8Encoding(false, true).GetDecoder();
    private readonly StringBuilder residual = new StringBuilder();
    public string[] Push(byte[] bytes, int count) {
        int charsNeeded = decoder.GetCharCount(bytes, 0, count, false);
        char[] chars = new char[charsNeeded];
        decoder.GetChars(bytes, 0, count, chars, 0, false);
        residual.Append(chars);
        return Drain(false);
    }
    public string[] Complete() {
        char[] chars = new char[decoder.GetCharCount(new byte[0], 0, 0, true)];
        decoder.GetChars(new byte[0], 0, 0, chars, 0, true);
        residual.Append(chars);
        return Drain(true);
    }
    private string[] Drain(bool final) {
        List<string> lines = new List<string>();
        int start = 0;
        for (int i = 0; i < residual.Length; i++) {
            if (residual[i] != '\n') continue;
            int length = i - start;
            if (length > 0 && residual[i - 1] == '\r') length--;
            lines.Add(residual.ToString(start, length));
            start = i + 1;
        }
        if (start > 0) residual.Remove(0, start);
        if (final && residual.Length > 0) { lines.Add(residual.ToString()); residual.Clear(); }
        return lines.ToArray();
    }
}
'@
}

function Read-G130U1FileBytes {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][UInt64]$Offset)
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return [pscustomobject]@{bytes=(New-Object byte[] 0);count=0;offset=$Offset}}
    $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    try{
        if([UInt64]$stream.Length-lt$Offset){throw"monitored file truncated: $Path"}
        [void]$stream.Seek([Int64]$Offset,[IO.SeekOrigin]::Begin)
        $count=[int]($stream.Length-[Int64]$Offset);$bytes=New-Object byte[] $count
        if($count){$actual=$stream.Read($bytes,0,$count)}else{$actual=0}
        [pscustomobject]@{bytes=$bytes;count=$actual;offset=[UInt64]($Offset+$actual)}
    }finally{$stream.Dispose()}
}

function Test-G130U1OwnedProcessObject {
    [CmdletBinding()]
    param([AllowNull()][Diagnostics.Process]$Process,[Parameter(Mandatory=$true)][DateTime]$ExpectedStartUtc,[Parameter(Mandatory=$true)][string]$ExpectedPath)
    if($null-eq$Process){return $false}
    try{$Process.Refresh();if($Process.HasExited){return $false};$startOk=[math]::Abs(($Process.StartTime.ToUniversalTime()-$ExpectedStartUtc).TotalSeconds)-lt1;$pathOk=[string]::Equals([IO.Path]::GetFullPath($Process.Path),[IO.Path]::GetFullPath($ExpectedPath),[StringComparison]::OrdinalIgnoreCase);return [bool]($startOk-and$pathOk)}catch{return $false}
}

function Stop-G130U1OwnedProcessBounded {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][Diagnostics.Process]$Process,[Parameter(Mandatory=$true)][DateTime]$ExpectedStartUtc,
        [Parameter(Mandatory=$true)][string]$ExpectedPath,[string]$BaseUri='',[string]$ShutdownToken='')
    $c=Get-G130U1Constants
    $r=[ordered]@{ownership_verified=$false;graceful_method='authenticated_loopback_http';graceful_attempted=$false;shutdown_http_status=$null;shutdown_request_accepted=$false;shutdown_cause='NOT_ATTEMPTED';graceful_verified=$false;graceful_succeeded=$false;spontaneous_exit=$false;forced_kill_attempted=$false;forced_kill_succeeded=$false;final_exit_code=$null;error=''}
    if(-not(Test-G130U1OwnedProcessObject $Process $ExpectedStartUtc $ExpectedPath)){$r.error='owned Process object validation failed';return [pscustomobject]$r};$r.ownership_verified=$true
    if($BaseUri-and$ShutdownToken){$r.graceful_attempted=$true;$client=$null;$content=$null;$response=$null
        try{Add-Type -AssemblyName System.Net.Http;$client=[Net.Http.HttpClient]::new();$client.Timeout=[TimeSpan]::FromSeconds($c.graceful_http_timeout_seconds);$body=ConvertTo-G130U1Json ([pscustomobject][ordered]@{token=$ShutdownToken}) -Compress;$content=[Net.Http.StringContent]::new($body,[Text.Encoding]::UTF8,'application/json');$response=$client.PostAsync(($BaseUri.TrimEnd('/')+'/__g130_u1_shutdown'),$content).Result;$r.shutdown_http_status=[int]$response.StatusCode;$r.shutdown_request_accepted=[bool]$response.IsSuccessStatusCode;$r.shutdown_cause=$(if($r.shutdown_request_accepted){'HTTP_2XX_ACCEPTED'}else{'HTTP_NON_2XX'})}catch{$r.shutdown_cause='HTTP_TRANSPORT_FAILURE';$r.error=$_.Exception.Message}finally{if($response){$response.Dispose()};if($content){$content.Dispose()};if($client){$client.Dispose()}}
        try{if($Process.WaitForExit($c.graceful_exit_wait_milliseconds)){$r.final_exit_code=[int]$Process.ExitCode;if($r.shutdown_request_accepted){$r.graceful_verified=$true;$r.graceful_succeeded=$true;$r.shutdown_cause='HTTP_2XX_AND_OWNED_EXIT'}else{$r.spontaneous_exit=$true;$r.shutdown_cause=$r.shutdown_cause+'_SPONTANEOUS_EXIT'};return [pscustomobject]$r}}catch{$r.error=$_.Exception.Message}}
    try{$Process.Refresh();if($Process.HasExited){$r.spontaneous_exit=$true;$r.final_exit_code=[int]$Process.ExitCode;$r.shutdown_cause='OWNED_PROCESS_ALREADY_EXITED';return [pscustomobject]$r}}catch{}
    if(-not(Test-G130U1OwnedProcessObject $Process $ExpectedStartUtc $ExpectedPath)){$r.error='owned Process object changed before force';return [pscustomobject]$r}
    $r.forced_kill_attempted=$true;try{$Process.Kill();if($Process.WaitForExit($c.forced_exit_wait_milliseconds)){$r.forced_kill_succeeded=$true;$r.final_exit_code=[int]$Process.ExitCode}else{$r.error='owned process did not exit after Kill'}}catch{$r.error=$_.Exception.Message};[pscustomobject]$r
}

function Assert-G130U1WatchdogSampleObject {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Sample)
    Assert-G130U1ExactPropertySet $Sample @('elapsed_seconds','working_set_bytes','available_ram_bytes','pages_output_total','ready','request_started','request_complete','server_alive','stderr_delta','stream_text','startup_cached_gib','startup_loaded_layer','startup_phase') 'watchdog sample'
    foreach($name in @('elapsed_seconds','working_set_bytes','available_ram_bytes','pages_output_total')){Assert-G130U1TypedNumber $Sample.$name "watchdog sample.$name" -Integral:($name-ne'elapsed_seconds')}
    Assert-G130U1TypedNumber $Sample.startup_cached_gib 'watchdog sample.startup_cached_gib' -AllowNegative
    Assert-G130U1TypedNumber $Sample.startup_loaded_layer 'watchdog sample.startup_loaded_layer' -Integral -AllowNegative
    foreach($name in @('ready','request_started','request_complete','server_alive')){if($Sample.$name-isnot[bool]){throw"watchdog sample.$name must be boolean"}}
    if([UInt64]$Sample.available_ram_bytes-eq0-or[UInt64]$Sample.pages_output_total-eq0-or([bool]$Sample.server_alive-and[UInt64]$Sample.working_set_bytes-eq0)){throw'watchdog sample contains an implausible zero probe'}
    foreach($name in @('stderr_delta','stream_text','startup_phase')){Assert-G130U1StringValue $Sample.$name "watchdog sample.$name" -AllowEmpty}
    if([string]$Sample.startup_phase-notin@('none','loading_model_tensors','model_load_progress','loaded_model_layer','listener_bound')){throw'watchdog sample.startup_phase unknown'}
    if([double]$Sample.startup_cached_gib-lt-1-or[int]$Sample.startup_loaded_layer-lt-1){throw'watchdog startup sentinel below -1'}
}

function Assert-G130U1WatchdogEventRow {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Row)
    if([string]$Row.event-ceq'heartbeat'){
        Assert-G130U1ExactPropertySet $Row @('schema','event','run_id','sequence','captured_utc','sample','decision') 'watchdog heartbeat row'
        if([string]$Row.schema-cne'g130_u1_watchdog_event_v2'){throw'watchdog heartbeat schema'};Assert-G130U1WatchdogSampleObject $Row.sample
        Assert-G130U1ExactPropertySet $Row.decision @('abort','gate','cause','detail','rolling_decode_tps') 'watchdog decision';if($Row.decision.abort-isnot[bool]){throw'watchdog decision.abort type'};foreach($name in @('gate','cause','detail')){Assert-G130U1StringValue $Row.decision.$name "watchdog decision.$name" -AllowEmpty};if($null-ne$Row.decision.rolling_decode_tps){Assert-G130U1TypedNumber $Row.decision.rolling_decode_tps 'watchdog decision.rolling_decode_tps'}
    }elseif([string]$Row.event-ceq'completed'){
        Assert-G130U1ExactPropertySet $Row @('schema','event','run_id','sequence','captured_utc') 'watchdog completed row';if([string]$Row.schema-cne'g130_u1_watchdog_event_v2'){throw'watchdog completed schema'}
    }else{throw'unknown watchdog event row'}
    Assert-G130U1TypedNumber $Row.sequence 'watchdog event.sequence' -StrictlyPositive -Integral;Assert-G130U1StringValue $Row.run_id 'watchdog event.run_id';try{[void][DateTime]::Parse([string]$Row.captured_utc)}catch{throw'watchdog event captured_utc invalid'}
}

function Assert-G130U1WatchdogSamplerRow {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Row)
    Assert-G130U1ExactPropertySet $Row @('schema','sequence','captured_utc','probe_ok','probe_error','available_ram_bytes','pages_output_total','working_set_bytes','stderr_offset','stream_offset') 'watchdog sampler row'
    if([string]$Row.schema-cne'g130_u1_watchdog_sampler_v2'-or$Row.probe_ok-isnot[bool]){throw'watchdog sampler schema/type'}
    foreach($name in @('sequence','available_ram_bytes','pages_output_total','working_set_bytes','stderr_offset','stream_offset')){Assert-G130U1TypedNumber $Row.$name "watchdog sampler.$name" -Integral -StrictlyPositive:($name-in@('sequence','available_ram_bytes','pages_output_total'))}
    Assert-G130U1StringValue $Row.probe_error 'watchdog sampler.probe_error' -AllowEmpty;try{[void][DateTime]::Parse([string]$Row.captured_utc)}catch{throw'watchdog sampler captured_utc invalid'}
}

function Test-G130U1ParentSupervisionSample {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Sample,[Parameter(Mandatory=$true)][double]$HeartbeatStallSeconds,[Parameter(Mandatory=$true)][double]$WallCapSeconds)
    Assert-G130U1ExactPropertySet $Sample @('elapsed_seconds','watchdog_alive','heartbeat_age_seconds','sampler_age_seconds','heartbeat_rows','sampler_rows','heartbeat_offset','sampler_offset','source_regression','source_error') 'parent supervision sample'
    foreach($name in @('elapsed_seconds','heartbeat_age_seconds','sampler_age_seconds','heartbeat_rows','sampler_rows','heartbeat_offset','sampler_offset')){Assert-G130U1TypedNumber $Sample.$name "parent supervision sample.$name" -Integral:($name-in@('heartbeat_rows','sampler_rows','heartbeat_offset','sampler_offset'))}
    foreach($name in @('watchdog_alive','source_regression')){if($Sample.$name-isnot[bool]){throw"parent supervision sample.$name type"}};Assert-G130U1StringValue $Sample.source_error 'parent supervision sample.source_error' -AllowEmpty
    if([double]$Sample.elapsed_seconds-ge$WallCapSeconds){return [pscustomobject]@{abort=$true;gate='A-8';cause='A8_PARENT_WALL_CAP'}}
    if(-not[bool]$Sample.watchdog_alive){return [pscustomobject]@{abort=$true;gate='A-9';cause='A9_WATCHDOG_EXIT'}}
    if([bool]$Sample.source_regression){return [pscustomobject]@{abort=$true;gate='A-9';cause='A9_PARENT_SOURCE_COUNTER_REGRESSION'}}
    if([double]$Sample.heartbeat_age_seconds-gt$HeartbeatStallSeconds){return [pscustomobject]@{abort=$true;gate='A-9';cause='A9_WATCHDOG_HEARTBEAT_STALL'}}
    if([double]$Sample.sampler_age_seconds-gt$HeartbeatStallSeconds){return [pscustomobject]@{abort=$true;gate='A-9';cause='A9_SAMPLER_PERSIST_STALL'}}
    [pscustomobject]@{abort=$false;gate='';cause=''}
}
