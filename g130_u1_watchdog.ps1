[CmdletBinding(DefaultParameterSetName='Live')]
param(
    [Parameter(ParameterSetName='Live',Mandatory=$true)][string]$ManifestPath,
    [Parameter(ParameterSetName='Replay',Mandatory=$true)][string]$ReplayPath,
    [Parameter(ParameterSetName='Ownership',Mandatory=$true)][switch]$OwnershipSelfTest
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $root 'g130_u1_common.ps1')

function Add-G130U1WatchdogJsonLine {
    param([string]$Path,[object]$Value)
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-G130U1Json $Value -Compress)+"`n")
    $stream=[IO.File]::Open($Path,[IO.FileMode]::Append,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite)
    try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
}

function New-G130U1WatchdogState {
    [pscustomobject]@{
        initialized=$false;maximum_working_set_bytes=[UInt64]0;request_working_set_initialized=$false;request_start_seconds=$null
        first_token_observed_seconds=$null;last_application_progress_seconds=0.0
        last_startup_progress_seconds=0.0;maximum_startup_cached_gib=-1.0
        maximum_startup_loaded_layer=-1;startup_phase_rank=0;startup_phase='none'
        token_times=[Collections.ArrayList]::new();last_token=0;stream_text=''
    }
}

function New-G130U1WatchdogDecision {
    param([bool]$Abort=$false,[string]$Gate='',[string]$Cause='',[string]$Detail='',[AllowNull()][object]$RollingTps=$null)
    [pscustomobject][ordered]@{abort=$Abort;gate=$Gate;cause=$Cause;detail=$Detail;rolling_decode_tps=$RollingTps}
}

function Test-G130U1EarlyTextFailure {
    param([AllowNull()][string]$Text)
    if([string]::IsNullOrEmpty($Text)){return [pscustomobject]@{failed=$false;cause='';detail=''}}
    $length=$Text.Length
    for($block=20;$block-le[math]::Floor($length/3);$block++){
        for($start=0;$start+3*$block-le$length;$start++){
            if([string]::CompareOrdinal($Text,$start,$Text,$start+$block,$block)-eq0-and
               [string]::CompareOrdinal($Text,$start,$Text,$start+2*$block,$block)-eq0){
                return [pscustomobject]@{failed=$true;cause='A4_REPEATED_BLOCK';detail="three consecutive ordinal repeats block_chars=$block offset=$start"}
            }
        }
    }
    if($length-ge500){for($offset=0;$offset-le$length-500;$offset+=50){$window=$Text.Substring($offset,500);$bad=0;foreach($ch in $window.ToCharArray()){$code=[int][char]$ch;if(($code-lt32-and$ch-notin@("`r","`n","`t"))-or$code-eq0xFFFD-or$ch-in@([char]0x00C2,[char]0x00C3,[char]0x00E2)){$bad++}};if(($bad/500.0)-gt0.30){return [pscustomobject]@{failed=$true;cause='A4_MOJIBAKE_OR_NONPRINTABLE';detail="bad_fraction=$($bad/500.0) offset=$offset"}}}}
    [pscustomobject]@{failed=$false;cause='';detail=''}
}

function Add-G130U1TokenTelemetry {
    param([string]$Text,[object]$State)
    foreach($line in @($Text-split"`r?`n")){
        if($line-notmatch'\[q1-0-profile-token\]'){continue}
        $canonical=ConvertTo-G130U1CanonicalTaggedLine $line 'q1-0-profile-token'
        if($null-eq$canonical){throw'profile token runtime prefix/timestamp malformed'}
        $fields=ConvertFrom-G130U1KeyValueLine $canonical 'q1-0-profile-token'
        if([string]$fields.schema-cne'g130_u1_profile_token_v1'-or[string]$fields.result-cne'progress'-or[string]$fields.final-cne'0'){continue}
        $gen=[int](ConvertTo-G130U1UInt64 $fields.gen 'watchdog token.gen');$seconds=ConvertTo-G130U1FiniteDouble $fields.decode_elapsed_seconds 'watchdog token.seconds'
        if($gen-le$State.last_token){continue};if($gen-ne$State.last_token+1){throw"token telemetry gap previous=$($State.last_token) current=$gen"}
        if($State.token_times.Count-and$seconds-le[double]$State.token_times[$State.token_times.Count-1].seconds){throw'token telemetry clock non-monotonic'}
        [void]$State.token_times.Add([pscustomobject]@{gen=$gen;seconds=$seconds});$State.last_token=$gen
    }
}

function Find-G130U1RuntimeMarker {
    param([string]$Text)
    $a5=[regex]::Match($Text,'(?im)(\bCUDA\b[^\r\n]*(?:failed|failure|error)|\bcudaError[A-Za-z0-9_]*\b|\bCUBLAS_STATUS_[A-Z_]+\b|illegal memory access|device-side assert|unspecified launch failure|device\s+reset|NVRM:\s*Xid\s*[0-9]+)')
    if($a5.Success){return New-G130U1WatchdogDecision $true 'A-5' 'A5_CUDA_OR_DEVICE_ERROR' $a5.Value}
    $a6=[regex]::Match($Text,'(?im)(state\.failed=1|\[q1-0-ssd-wrap\]|ssd_wrap|dynamic[-_ ]promotion)')
    if($a6.Success){return New-G130U1WatchdogDecision $true 'A-6' 'A6_PROMOTION_OR_SSD_WRAP_MARKER' $a6.Value}
    foreach($m in [regex]::Matches($Text,'(?im)\b(forbidden_cold_ssd_to_vram|direct_ssd_to_vram_rejected|direct_ssd_to_vram_current_token)=([0-9]+)')){if([UInt64]$m.Groups[2].Value-gt0){return New-G130U1WatchdogDecision $true 'A-7' 'A7_SAME_TOKEN_SSD_TO_VRAM' $m.Value}}
    New-G130U1WatchdogDecision
}

function Test-G130U1WatchdogSample {
    [CmdletBinding()]
    param([object]$Sample,[object]$State,[UInt64]$BaselinePageOut,[int]$WallCap,[int]$StartupStall,[int]$TtftCap,[int]$DataStall,[double]$FloorTps,[int]$WarmTokens,[int]$ConsecutiveTokens)
    Assert-G130U1WatchdogSampleObject $Sample
    $elapsed=[double]$Sample.elapsed_seconds;$working=[UInt64]$Sample.working_set_bytes;$available=[UInt64]$Sample.available_ram_bytes;$pageout=[UInt64]$Sample.pages_output_total;$requestStarted=[bool]$Sample.request_started;$requestComplete=[bool]$Sample.request_complete;$serverAlive=[bool]$Sample.server_alive;$stderr=[string]$Sample.stderr_delta;$streamText=[string]$Sample.stream_text;$ready=[bool]$Sample.ready;$startupCached=[double]$Sample.startup_cached_gib;$startupLayer=[int]$Sample.startup_loaded_layer;$startupPhase=[string]$Sample.startup_phase
    if(-not$State.initialized){$State.initialized=$true;$State.last_application_progress_seconds=$elapsed;$State.last_startup_progress_seconds=$elapsed}
    if(-not$requestStarted){if($working-gt$State.maximum_working_set_bytes){$State.maximum_working_set_bytes=$working}}
    if($requestStarted-and$null-eq$State.request_start_seconds){$State.request_start_seconds=$elapsed;$State.last_application_progress_seconds=$elapsed;$State.maximum_working_set_bytes=$working;$State.request_working_set_initialized=$true}
    if($requestStarted-and$working-gt$State.maximum_working_set_bytes){$State.maximum_working_set_bytes=$working}
    $phaseRanks=@{none=0;loading_model_tensors=1;model_load_progress=2;loaded_model_layer=3;listener_bound=4}
    $startupAdvanced=$false
    if($startupCached-gt$State.maximum_startup_cached_gib){$State.maximum_startup_cached_gib=$startupCached;$startupAdvanced=$true}
    if($startupLayer-gt$State.maximum_startup_loaded_layer){$State.maximum_startup_loaded_layer=$startupLayer;$startupAdvanced=$true}
    $phaseRank=[int]$phaseRanks[$startupPhase];if($phaseRank-gt$State.startup_phase_rank){$State.startup_phase_rank=$phaseRank;$State.startup_phase=$startupPhase;$startupAdvanced=$true}
    if($startupAdvanced){$State.last_startup_progress_seconds=$elapsed}
    $previousToken=$State.last_token
    try{Add-G130U1TokenTelemetry $stderr $State}catch{return New-G130U1WatchdogDecision $true 'A-9' 'A9_TOKEN_TELEMETRY_SOURCE_INVALID' $_.Exception.Message}
    if($State.last_token-gt0-and$null-eq$State.first_token_observed_seconds){$State.first_token_observed_seconds=$elapsed}
    if($State.last_token-gt$previousToken-or$streamText.Length-gt$State.stream_text.Length){$State.last_application_progress_seconds=$elapsed};$State.stream_text=$streamText
    if($elapsed-ge$WallCap){return New-G130U1WatchdogDecision $true 'A-8' 'A8_WALL_CAP' "elapsed=$elapsed cap=$WallCap"}
    if(-not$serverAlive-and-not$requestComplete){return New-G130U1WatchdogDecision $true 'A-5' 'A5_SERVER_EXIT' 'owned server exited before complete HTTP status'}
    $marker=Find-G130U1RuntimeMarker $stderr;if($marker.abort){return $marker}
    if($pageout-lt$BaselinePageOut){return New-G130U1WatchdogDecision $true 'A-9' 'A9_PAGEOUT_COUNTER_REGRESSED' "baseline=$BaselinePageOut current=$pageout"};if($pageout-$BaselinePageOut-gt100000){return New-G130U1WatchdogDecision $true 'A-1' 'A1_PAGE_OUT_DELTA' "delta=$($pageout-$BaselinePageOut)"}
    if($requestStarted-and$State.request_working_set_initialized-and$State.maximum_working_set_bytes-gt$working-and$State.maximum_working_set_bytes-$working-gt[UInt64](2*1GB)){return New-G130U1WatchdogDecision $true 'A-1' 'A1_WORKING_SET_DROP' "request_maximum=$($State.maximum_working_set_bytes) current=$working"};if($available-lt[UInt64](2*1GB)){return New-G130U1WatchdogDecision $true 'A-1' 'A1_RAM_FLOOR' "available=$available"}
    $rolling=$null;if($State.last_token-ge$WarmTokens+$ConsecutiveTokens){$end=$State.last_token;$start=$end-$ConsecutiveTokens;$a=@($State.token_times|Where-Object{$_.gen-eq$start}|Select-Object -First 1);$b=@($State.token_times|Where-Object{$_.gen-eq$end}|Select-Object -First 1);if($a.Count-ne1-or$b.Count-ne1){return New-G130U1WatchdogDecision $true 'A-9' 'A9_A2_WINDOW_INCOMPLETE' "start=$start end=$end"};$delta=[double]$b[0].seconds-[double]$a[0].seconds;if($delta-le0){return New-G130U1WatchdogDecision $true 'A-9' 'A9_DECODE_CLOCK_NOT_ADVANCING' "delta=$delta"};$rolling=[double]$ConsecutiveTokens/$delta;if($rolling-lt$FloorTps){return New-G130U1WatchdogDecision $true 'A-2' 'A2_ROLLING_DECODE_FLOOR' "tokens=$ConsecutiveTokens seconds=$delta floor=$FloorTps" $rolling}}
    if($requestStarted-and$null-eq$State.first_token_observed_seconds-and$elapsed-[double]$State.request_start_seconds-gt$TtftCap){return New-G130U1WatchdogDecision $true 'A-3' 'A3_TTFT_CAP' "seconds=$($elapsed-[double]$State.request_start_seconds)"}
    $textFailure=Test-G130U1EarlyTextFailure $streamText;if($textFailure.failed){return New-G130U1WatchdogDecision $true 'A-4' $textFailure.cause $textFailure.detail}
    if($requestStarted-and-not$requestComplete-and$null-ne$State.first_token_observed_seconds-and$elapsed-[double]$State.last_application_progress_seconds-gt$DataStall){return New-G130U1WatchdogDecision $true 'A-3' 'A3_APPLICATION_DATA_STALL' "seconds=$($elapsed-[double]$State.last_application_progress_seconds)"}
    if(-not$ready-and-not$requestStarted-and$elapsed-[double]$State.last_startup_progress_seconds-gt$StartupStall){return New-G130U1WatchdogDecision $true 'A-10' 'A10_STARTUP_PROGRESS_STALL' "seconds=$($elapsed-[double]$State.last_startup_progress_seconds) cached_gib=$($State.maximum_startup_cached_gib) loaded_layer=$($State.maximum_startup_loaded_layer) phase=$($State.startup_phase)"}
    New-G130U1WatchdogDecision $false '' '' '' $rolling
}

function Invoke-G130U1WatchdogReplay {
    param([string]$Path)
    $f=Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json;Assert-G130U1ExactPropertySet $f @('schema','baseline_page_out','thresholds','samples') 'watchdog replay';if([string]$f.schema-cne'g130_u1_watchdog_replay_fixture_v2'){throw'watchdog replay schema'};Assert-G130U1ExactPropertySet $f.thresholds @('wall_cap_seconds','startup_stall_seconds','ttft_cap_seconds','application_data_stall_seconds','throughput_floor_tps','throughput_warm_tokens','throughput_consecutive_tokens') 'watchdog replay thresholds'
    Assert-G130U1TypedNumber $f.baseline_page_out 'watchdog baseline_page_out' -StrictlyPositive -Integral
    $state=New-G130U1WatchdogState;$decision=New-G130U1WatchdogDecision;$count=0;foreach($s in @($f.samples)){$count++;$decision=Test-G130U1WatchdogSample $s $state ([UInt64]$f.baseline_page_out) ([int]$f.thresholds.wall_cap_seconds) ([int]$f.thresholds.startup_stall_seconds) ([int]$f.thresholds.ttft_cap_seconds) ([int]$f.thresholds.application_data_stall_seconds) ([double]$f.thresholds.throughput_floor_tps) ([int]$f.thresholds.throughput_warm_tokens) ([int]$f.thresholds.throughput_consecutive_tokens);if($decision.abort){break}}
    [pscustomobject][ordered]@{schema='g130_u1_watchdog_replay_result_v2';abort=$decision.abort;gate=$decision.gate;cause=$decision.cause;detail=$decision.detail;rolling_decode_tps=$decision.rolling_decode_tps;samples_consumed=$count;tokens_observed=$state.last_token;startup_snapshot=[pscustomobject][ordered]@{cached_gib=$state.maximum_startup_cached_gib;loaded_layer=$state.maximum_startup_loaded_layer;phase=$state.startup_phase}}
}

function Get-G130U1StartupProgress {
    param([string]$Text)
    $cached=-1.0;$layer=-1;$phase='none'
    foreach($m in [regex]::Matches($Text,'(?i)([0-9]+(?:\.[0-9]+)?)\s*GiB\s+cached')){$v=[double]::Parse($m.Groups[1].Value,[Globalization.CultureInfo]::InvariantCulture);if($v-gt$cached){$cached=$v}}
    foreach($m in [regex]::Matches($Text,'(?i)loaded (?:model )?layer[ =:]*(\d+)')){$v=[int]$m.Groups[1].Value;if($v-gt$layer){$layer=$v}}
    if($Text-match'(?i)loading model tensors'){$phase='loading_model_tensors'}
    if($Text-match'(?i)model load progress'){$phase='model_load_progress'}
    if($layer-ge0){$phase='loaded_model_layer'}
    if($Text-match'(?i)ds4-server: listening on'){$phase='listener_bound'}
    [pscustomobject][ordered]@{cached_gib=$cached;loaded_layer=$layer;phase=$phase}
}

function Add-G130U1SseLines {
    param([string[]]$Lines,[object]$State)
    foreach($line in $Lines){if($line.StartsWith('data:',[StringComparison]::Ordinal)){$State.sse_event.Add($line.Substring(5).TrimStart())}elseif($line.Length-eq0-and$State.sse_event.Count){$payload=($State.sse_event.ToArray())-join"`n";$State.sse_event.Clear();if($payload-ceq'[DONE]'){$State.sse_done=$true;continue};try{$json=$payload|ConvertFrom-Json;$choices=@($json.choices);if($choices.Count-and$null-ne$choices[0].PSObject.Properties['delta']-and$null-ne$choices[0].delta-and$null-ne$choices[0].delta.PSObject.Properties['content']-and$null-ne$choices[0].delta.content){$State.stream_text+=[string]$choices[0].delta.content}}catch{throw"invalid SSE JSON: $($_.Exception.Message)"}}}
}

function Get-G130U1WatchdogSnapshot {
    param([string]$LogPath,[AllowNull()][object]$Sample)
    $tail=@();try{$tail=@(Get-Content -LiteralPath $LogPath -Tail 80)}catch{};[pscustomobject][ordered]@{captured_utc=[DateTime]::UtcNow.ToString('o');sample=$Sample;stderr_tail=$tail;termination='parent_required'}
}

if($OwnershipSelfTest){$p=Get-Process -Id $PID;$start=$p.StartTime.ToUniversalTime();$path=$p.Path;[pscustomobject]@{schema='g130_u1_watchdog_ownership_selftest_v2';valid_identity_accepted=(Test-G130U1OwnedProcessObject $p $start $path);wrong_start_rejected=(-not(Test-G130U1OwnedProcessObject $p $start.AddHours(-1) $path));wrong_path_rejected=(-not(Test-G130U1OwnedProcessObject $p $start ($path+'.wrong')));decision_only=$true}|ConvertTo-Json;exit 0}
if($ReplayPath){try{$r=Invoke-G130U1WatchdogReplay $ReplayPath;$r|ConvertTo-Json -Depth 30;exit $(if($r.abort){21}else{0})}catch{[pscustomobject]@{schema='g130_u1_watchdog_replay_error_v2';error=$_.Exception.Message}|ConvertTo-Json;exit 21}}

$manifest=Get-Content -LiteralPath $ManifestPath -Raw|ConvertFrom-Json
Assert-G130U1ExactPropertySet $manifest @('schema','run_id','owned_pid','owned_start_utc','owned_exe_path','ownership_path','stderr_path','stream_path','ready_path','request_started_path','request_result_path','monitor_complete_path','watchdog_log_path','sampler_path','abort_path','page_out_baseline','thresholds') 'watchdog manifest'
if([string]$manifest.schema-cne'g130_u1_watchdog_manifest_v2'){throw'watchdog manifest schema'}
Assert-G130U1ExactPropertySet $manifest.thresholds @('cadence_seconds','wall_cap_seconds','startup_stall_seconds','ttft_cap_seconds','application_data_stall_seconds','throughput_floor_tps','throughput_warm_tokens','throughput_consecutive_tokens') 'watchdog thresholds'
foreach($name in @('run_id','owned_start_utc','owned_exe_path','ownership_path','stderr_path','stream_path','ready_path','request_started_path','request_result_path','monitor_complete_path','watchdog_log_path','sampler_path','abort_path')){Assert-G130U1StringValue $manifest.$name "watchdog manifest.$name"}
Assert-G130U1TypedNumber $manifest.owned_pid 'watchdog manifest.owned_pid' -StrictlyPositive -Integral;Assert-G130U1TypedNumber $manifest.page_out_baseline 'watchdog manifest.page_out_baseline' -StrictlyPositive -Integral
try{[void][DateTime]::Parse([string]$manifest.owned_start_utc)}catch{throw'watchdog manifest.owned_start_utc invalid'}
foreach($name in @('cadence_seconds','wall_cap_seconds','startup_stall_seconds','ttft_cap_seconds','application_data_stall_seconds','throughput_floor_tps','throughput_warm_tokens','throughput_consecutive_tokens')){Assert-G130U1TypedNumber $manifest.thresholds.$name "watchdog thresholds.$name" -StrictlyPositive -Integral:($name-ne'throughput_floor_tps')}
$ownership=Get-Content -LiteralPath $manifest.ownership_path -Raw|ConvertFrom-Json
Assert-G130U1ExactPropertySet $ownership @('schema','run_id','runner_pid','server_pid','server_start_utc','executable','created_utc') 'watchdog ownership receipt'
if([string]$ownership.schema-cne'g130_u1_process_ownership_v2'){throw'watchdog ownership receipt schema'};foreach($name in @('run_id','server_start_utc','executable','created_utc')){Assert-G130U1StringValue $ownership.$name "watchdog ownership.$name"};foreach($name in @('runner_pid','server_pid')){Assert-G130U1TypedNumber $ownership.$name "watchdog ownership.$name" -StrictlyPositive -Integral};foreach($name in @('server_start_utc','created_utc')){try{[void][DateTime]::Parse([string]$ownership.$name)}catch{throw"watchdog ownership.$name invalid"}}
if([string]$ownership.run_id-cne[string]$manifest.run_id-or[int]$ownership.server_pid-ne[int]$manifest.owned_pid-or[string]$ownership.server_start_utc-cne[string]$manifest.owned_start_utc-or-not[string]::Equals([string]$ownership.executable,[string]$manifest.owned_exe_path,[StringComparison]::OrdinalIgnoreCase)){throw'watchdog ownership receipt mismatch'}
$owned=Get-Process -Id ([int]$manifest.owned_pid) -ErrorAction Stop
$ownedStart=[DateTime]::Parse([string]$manifest.owned_start_utc).ToUniversalTime()
if(-not (Test-G130U1OwnedProcessObject $owned $ownedStart ([string]$manifest.owned_exe_path))){
    throw 'watchdog initial ownership invalid'
}
Initialize-G130U1Utf8FramerType;$stderrFramer=[G130U1Utf8LineFramer]::new();$sseFramer=[G130U1Utf8LineFramer]::new();$live=[pscustomobject]@{sse_event=[Collections.Generic.List[string]]::new();sse_done=$false;stream_text=''};$state=New-G130U1WatchdogState;$clock=[Diagnostics.Stopwatch]::StartNew();$stderrOffset=[UInt64]0;$streamOffset=[UInt64]0;$sequence=[UInt64]0;$lastSample=$null
Write-G130U1Utf8 ([string]$manifest.watchdog_log_path) '';Write-G130U1Utf8 ([string]$manifest.sampler_path) ''
while($true){$sequence++;$elapsed=$clock.Elapsed.TotalSeconds;$probeOk=$true;$probeError='';try{$os=Get-CimInstance Win32_OperatingSystem -ErrorAction Stop;$raw=Get-CimInstance Win32_PerfRawData_PerfOS_Memory -ErrorAction Stop;$available=[UInt64]$os.FreePhysicalMemory*[UInt64]1024;$pageout=[UInt64]$raw.PagesOutputPerSec}catch{$probeOk=$false;$probeError=$_.Exception.Message;$available=[UInt64]0;$pageout=[UInt64]0}
    try{$owned.Refresh();$serverAlive=-not$owned.HasExited;$working=$(if($serverAlive){[UInt64]$owned.WorkingSet64}else{[UInt64]0})}catch{$serverAlive=$false;$working=[UInt64]0}
    $stderrText='';$streamLines=@();try{$read=Read-G130U1FileBytes ([string]$manifest.stderr_path) $stderrOffset;$stderrOffset=$read.offset;$stderrLines=@($stderrFramer.Push($read.bytes,$read.count));$stderrText=$stderrLines-join"`n";$sread=Read-G130U1FileBytes ([string]$manifest.stream_path) $streamOffset;$streamOffset=$sread.offset;$streamLines=@($sseFramer.Push($sread.bytes,$sread.count));Add-G130U1SseLines $streamLines $live}catch{$probeOk=$false;$probeError=$_.Exception.Message}
    $startup=Get-G130U1StartupProgress $stderrText;$requestStarted=Test-Path -LiteralPath ([string]$manifest.request_started_path) -PathType Leaf;$requestComplete=(Test-Path -LiteralPath ([string]$manifest.request_result_path) -PathType Leaf)-or$live.sse_done;$ready=Test-Path -LiteralPath ([string]$manifest.ready_path) -PathType Leaf
    $sample=[pscustomobject][ordered]@{elapsed_seconds=$elapsed;working_set_bytes=$working;available_ram_bytes=$available;pages_output_total=$pageout;ready=$ready;request_started=$requestStarted;request_complete=$requestComplete;server_alive=$serverAlive;stderr_delta=$stderrText;stream_text=$live.stream_text;startup_cached_gib=[double]$startup.cached_gib;startup_loaded_layer=[int]$startup.loaded_layer;startup_phase=[string]$startup.phase};$lastSample=$sample
    Add-G130U1WatchdogJsonLine ([string]$manifest.sampler_path) ([pscustomobject][ordered]@{schema='g130_u1_watchdog_sampler_v2';sequence=$sequence;captured_utc=[DateTime]::UtcNow.ToString('o');probe_ok=$probeOk;probe_error=$probeError;available_ram_bytes=$available;pages_output_total=$pageout;working_set_bytes=$working;stderr_offset=$stderrOffset;stream_offset=$streamOffset})
    if(-not$probeOk){$decision=New-G130U1WatchdogDecision $true 'A-9' 'A9_MONITOR_SOURCE_FAILURE' $probeError}else{$t=$manifest.thresholds;$decision=Test-G130U1WatchdogSample $sample $state ([UInt64]$manifest.page_out_baseline) ([int]$t.wall_cap_seconds) ([int]$t.startup_stall_seconds) ([int]$t.ttft_cap_seconds) ([int]$t.application_data_stall_seconds) ([double]$t.throughput_floor_tps) ([int]$t.throughput_warm_tokens) ([int]$t.throughput_consecutive_tokens)}
    Add-G130U1WatchdogJsonLine ([string]$manifest.watchdog_log_path) ([pscustomobject][ordered]@{schema='g130_u1_watchdog_event_v2';event='heartbeat';run_id=[string]$manifest.run_id;sequence=$sequence;captured_utc=[DateTime]::UtcNow.ToString('o');sample=$sample;decision=$decision})
    if($decision.abort){$snapshot=Get-G130U1WatchdogSnapshot ([string]$manifest.stderr_path) $sample;$abort=[pscustomobject][ordered]@{schema='g130_u1_watchdog_abort_v2';run_id=[string]$manifest.run_id;captured_utc=[DateTime]::UtcNow.ToString('o');gate=$decision.gate;cause=$decision.cause;detail=$decision.detail;source='watchdog';partial_text=$live.stream_text;rendering_method='not_rendered';l_grade='UNASSESSED';snapshot=$snapshot;termination='parent_required'};[void](Write-G130U1AbortAtomic ([string]$manifest.abort_path) $abort);exit 21}
    if(Test-Path -LiteralPath ([string]$manifest.monitor_complete_path) -PathType Leaf){
        try {
            $stderrResidual=@($stderrFramer.Complete())
            if($stderrResidual.Count){
                $residualText=$stderrResidual -join "`n"
                $residualSample=[pscustomobject][ordered]@{
                    elapsed_seconds=$elapsed;working_set_bytes=$working;available_ram_bytes=$available
                    pages_output_total=$pageout;ready=$ready;request_started=$requestStarted
                    request_complete=$requestComplete;server_alive=$serverAlive
                    stderr_delta=$residualText;stream_text=$live.stream_text
                    startup_cached_gib=[double]$startup.cached_gib
                    startup_loaded_layer=[int]$startup.loaded_layer;startup_phase='none'
                }
                $t=$manifest.thresholds
                $residualDecision=Test-G130U1WatchdogSample $residualSample $state ([UInt64]$manifest.page_out_baseline) ([int]$t.wall_cap_seconds) ([int]$t.startup_stall_seconds) ([int]$t.ttft_cap_seconds) ([int]$t.application_data_stall_seconds) ([double]$t.throughput_floor_tps) ([int]$t.throughput_warm_tokens) ([int]$t.throughput_consecutive_tokens)
                if($residualDecision.abort){throw "post-run stderr rejected: $($residualDecision.cause) $($residualDecision.detail)"}
            }
            $sseResidual=@($sseFramer.Complete())
            Add-G130U1SseLines $sseResidual $live
            if($live.sse_event.Count){throw 'incomplete residual SSE event at monitor completion'}
        } catch {
            $snapshot=Get-G130U1WatchdogSnapshot ([string]$manifest.stderr_path) $lastSample
            $abort=[pscustomobject][ordered]@{
                schema='g130_u1_watchdog_abort_v2';run_id=[string]$manifest.run_id
                captured_utc=[DateTime]::UtcNow.ToString('o');gate='A-9'
                cause='A9_FINAL_MONITOR_DATA_INVALID';detail=$_.Exception.Message
                source='watchdog';partial_text=$live.stream_text;snapshot=$snapshot
                termination='parent_required'
            }
            [void](Write-G130U1AbortAtomic ([string]$manifest.abort_path) $abort)
            exit 21
        }
        Add-G130U1WatchdogJsonLine ([string]$manifest.watchdog_log_path) ([pscustomobject][ordered]@{schema='g130_u1_watchdog_event_v2';event='completed';run_id=[string]$manifest.run_id;sequence=$sequence;captured_utc=[DateTime]::UtcNow.ToString('o')})
        exit 0
    }
    Start-Sleep -Seconds ([int]$manifest.thresholds.cadence_seconds)
}
