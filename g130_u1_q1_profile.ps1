[CmdletBinding(DefaultParameterSetName='Default')]
param(
    [Parameter(ParameterSetName='WhatIf')][switch]$WhatIf,
    [Parameter(ParameterSetName='Live')][switch]$Live,
    [Parameter(ParameterSetName='Live',Mandatory=$true)][string]$ApprovalArtifactPath,
    [Parameter(ParameterSetName='Live')][ValidatePattern('^[A-Za-z0-9_-]*$')][string]$Tag='',
    [Parameter(ParameterSetName='Live')][string]$OutputRoot='',
    [Parameter(ParameterSetName='Parse',Mandatory=$true)][string]$ParseProfilePath,
    [Parameter(ParameterSetName='Parse',Mandatory=$true)][int]$GeneratedTokens,
    [Parameter(ParameterSetName='Preflight',Mandatory=$true)][string]$PreflightFixturePath,
    [Parameter(ParameterSetName='ReplayParent',Mandatory=$true)][string]$SupervisionFixturePath,
    [Parameter(ParameterSetName='Quote',Mandatory=$true)][string]$QuoteFixturePath,
    [Parameter(ParameterSetName='TcpWait',Mandatory=$true)][string]$TcpWaitFixturePath,
    [Parameter(ParameterSetName='WorkerStatus',Mandatory=$true)][string]$WorkerStatusFixturePath,
    [Parameter(ParameterSetName='Approval',Mandatory=$true)][string]$ApprovalFixturePath,
    [Parameter(ParameterSetName='HttpWorker',Mandatory=$true)][switch]$HttpWorker,
    [Parameter(ParameterSetName='HttpWorker',Mandatory=$true)][string]$WorkerManifestPath,
    [Parameter(ParameterSetName='MockLifecycle',Mandatory=$true)]
    [ValidateSet('success','request-failure','parser-failure','forced-kill','cleanup-failure','pre-configuration-failure','ledger-failure','receipt-init-failure','receipt-finalization-failure','a4-abort')]
    [string]$MockLifecycleScenario,
    [Parameter(ParameterSetName='MockLifecycle',Mandatory=$true)][string]$MockOutputRoot,
    [Parameter(ParameterSetName='MockLifecycle')][string]$MockProfilePath=''
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $root 'g130_u1_common.ps1')
$constants=Get-G130U1Constants
$watchdogPath=Join-Path $root 'g130_u1_watchdog.ps1'
$exePath=Join-Path $root 'build\Release\ds4_server.exe'
$manifestPath=Join-Path $root 'build\Release\g7_build_manifest.json'

function Get-G130U1FreePort {
    $listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
    try{$listener.Start();[int]$listener.LocalEndpoint.Port}finally{$listener.Stop()}
}

function New-G130U1ShutdownToken {
    $bytes=New-Object byte[] 32
    $rng=[Security.Cryptography.RandomNumberGenerator]::Create()
    try{$rng.GetBytes($bytes)}finally{$rng.Dispose()}
    ([BitConverter]::ToString($bytes)).Replace('-','').ToLowerInvariant()
}

function Test-G130U1TcpReady {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][int]$Port)
    $client=[Net.Sockets.TcpClient]::new()
    try{$async=$client.BeginConnect('127.0.0.1',$Port,$null,$null);if(-not$async.AsyncWaitHandle.WaitOne(200,$false)){return $false};$client.EndConnect($async);return $true}catch{return $false}finally{$client.Close()}
}

function Get-G130U1ParentSourceSample {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$State,[Parameter(Mandatory=$true)][string]$HeartbeatPath,
        [Parameter(Mandatory=$true)][string]$SamplerPath,[Parameter(Mandatory=$true)][DateTime]$Now,
        [Parameter(Mandatory=$true)][double]$ElapsedSeconds,[Parameter(Mandatory=$true)][bool]$WatchdogAlive)
    $regression=$false;$sourceError=''
    foreach($source in @(@('heartbeat',$HeartbeatPath),@('sampler',$SamplerPath))){
        $kind=[string]$source[0];$path=[string]$source[1]
        if(-not(Test-Path -LiteralPath $path -PathType Leaf)){continue}
        try{$read=Read-G130U1FileBytes $path ([UInt64]$State.($kind+'_offset'));$State.($kind+'_offset')=[UInt64]$read.offset;$newRows=0
            foreach($line in @($State.($kind+'_framer').Push($read.bytes,$read.count))){if([string]::IsNullOrWhiteSpace($line)){throw"$kind JSONL contains blank row"};$row=$line|ConvertFrom-Json
                if($kind-ceq'heartbeat'){Assert-G130U1WatchdogEventRow $row}else{Assert-G130U1WatchdogSamplerRow $row}
                $expected=[UInt64]$State.($kind+'_sequence')+1;if([UInt64]$row.sequence-ne$expected){throw"$kind sequence expected $expected got $($row.sequence)"};$State.($kind+'_sequence')=[UInt64]$row.sequence;$State.($kind+'_rows')=[Int64]$State.($kind+'_rows')+1;$newRows++
            }
            if($newRows-gt0){$State.($kind+'_seen')=$Now}
        }catch{$regression=$true;$sourceError="$kind`:$($_.Exception.Message)"}
    }
    [pscustomobject][ordered]@{
        elapsed_seconds=$ElapsedSeconds;watchdog_alive=$WatchdogAlive
        heartbeat_age_seconds=($Now-[DateTime]$State.heartbeat_seen).TotalSeconds
        sampler_age_seconds=($Now-[DateTime]$State.sampler_seen).TotalSeconds
        heartbeat_rows=[Int64]$State.heartbeat_rows;sampler_rows=[Int64]$State.sampler_rows
        heartbeat_offset=[UInt64]$State.heartbeat_offset;sampler_offset=[UInt64]$State.sampler_offset
        source_regression=$regression;source_error=$sourceError
    }
}

function Add-G130U1JsonLine {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][object]$Value)
    $line=(ConvertTo-G130U1Json $Value -Compress)+"`n";$bytes=[Text.UTF8Encoding]::new($false).GetBytes($line)
    $stream=[IO.File]::Open($Path,[IO.FileMode]::Append,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite)
    try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
}

function Assert-G130U1RequestObject {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Request)
    Assert-G130U1ExactPropertySet $Request @('model','messages','max_tokens','temperature','stream','stream_options','think') 'request'
    if([string]$Request.model-cne'ds4'-or[int]$Request.max_tokens-ne64-or[double]$Request.temperature-ne0-or$Request.stream-ne$true-or$Request.think-ne$false){throw'request scalar contract mismatch'}
    Assert-G130U1ExactPropertySet $Request.stream_options @('include_usage') 'request.stream_options'
    if($Request.stream_options.include_usage-ne$true){throw'request must include usage'}
    $messages=@($Request.messages);if($messages.Count-ne1){throw'request must contain exactly one message'}
    Assert-G130U1ExactPropertySet $messages[0] @('role','content') 'request.message'
    $expected=New-G130U1RequestObject
    if([string]$messages[0].role-cne'user'-or[string]$messages[0].content-cne[string]$expected.messages[0].content){throw'request message contract mismatch'}
}

function Invoke-G130U1SseEvent {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Payload,[Parameter(Mandatory=$true)][hashtable]$State,
        [Parameter(Mandatory=$true)][double]$Elapsed,[Parameter(Mandatory=$true)][string]$TimingPath)
    if($Payload-ceq'[DONE]'){$State.done_count++;if($State.done_count-ne1){$State.post_done_data_count++;throw'SSE_DONE_DUPLICATE'};if($State.terminal_stage-ne2){throw'SSE_DONE_OUT_OF_ORDER'};$State.terminal_stage=3;Add-G130U1JsonLine $TimingPath ([pscustomobject][ordered]@{schema='g130_u1_http_timing_event_v1';event='done';elapsed_seconds=$Elapsed;ordinal=1});return}
    if($State.done_count-gt0){$State.post_done_data_count++;throw'SSE_DATA_AFTER_DONE'}
    $chunk=$Payload|ConvertFrom-Json
    $hasUsage=$null-ne$chunk.PSObject.Properties['usage']-and$null-ne$chunk.usage
    if($hasUsage){$State.usage_count++;if($State.usage_count-ne1){throw'SSE_USAGE_DUPLICATE'};if($State.terminal_stage-ne1){throw'SSE_USAGE_OUT_OF_ORDER'};Assert-G130U1ExactPropertySet $chunk.usage @('prompt_tokens','completion_tokens','total_tokens') 'SSE final usage';$choices=@($chunk.choices);if($choices.Count-ne0){throw'SSE final usage choices must be empty'};foreach($name in @('prompt_tokens','completion_tokens','total_tokens')){Assert-G130U1TypedNumber $chunk.usage.$name "SSE usage.$name" -Integral};$State.usage_completion_tokens=[int]$chunk.usage.completion_tokens;$State.terminal_stage=2;Add-G130U1JsonLine $TimingPath ([pscustomobject][ordered]@{schema='g130_u1_http_timing_event_v1';event='usage';elapsed_seconds=$Elapsed;completion_tokens=$State.usage_completion_tokens;ordinal=1});return}
    if($null-eq$chunk.PSObject.Properties['choices']){throw'SSE JSON event missing choices'}
    $choices=@($chunk.choices);if($choices.Count-ne1){throw'SSE non-usage event must contain exactly one choice'}
    $choice=$choices[0]
    if($null-ne$choice.PSObject.Properties['delta']-and$null-ne$choice.delta-and$null-ne$choice.delta.PSObject.Properties['content']-and$null-ne$choice.delta.content){
        if($State.terminal_stage-ne0){throw'SSE_CONTENT_AFTER_FINISH'};$content=[string]$choice.delta.content;if($content.Length){if($null-eq$State.first_content_seconds){$State.first_content_seconds=$Elapsed};[void]$State.assistant.Append($content);$State.content_events++;Add-G130U1JsonLine $TimingPath ([pscustomobject][ordered]@{schema='g130_u1_http_timing_event_v1';event='content';elapsed_seconds=$Elapsed;chars=$content.Length;content_event=$State.content_events})}
    }
    if($null-ne$choice.PSObject.Properties['finish_reason']-and$null-ne$choice.finish_reason){$State.finish_count++;if($State.finish_count-ne1){throw'SSE_FINISH_DUPLICATE'};if($State.terminal_stage-ne0){throw'SSE_FINISH_OUT_OF_ORDER'};$State.finish_reason=[string]$choice.finish_reason;if($State.finish_reason-cne'length'){throw'SSE_FINISH_REASON_MISMATCH'};$State.terminal_stage=1;Add-G130U1JsonLine $TimingPath ([pscustomobject][ordered]@{schema='g130_u1_http_timing_event_v1';event='finish';elapsed_seconds=$Elapsed;finish_reason=$State.finish_reason;ordinal=1})}
}

function Add-G130U1WorkerSseLine {
    param([Parameter(Mandatory=$true)][AllowEmptyString()][string]$Line,[Parameter(Mandatory=$true)][hashtable]$State,[Parameter(Mandatory=$true)][double]$Elapsed,[Parameter(Mandatory=$true)][string]$TimingPath)
    if($Line.StartsWith('data:',[StringComparison]::Ordinal)){$State.event_data.Add($Line.Substring(5).TrimStart());return}
    if($Line.Length-eq0){if($State.event_data.Count){$payload=($State.event_data.ToArray())-join"`n";$State.event_data.Clear();Invoke-G130U1SseEvent $payload $State $Elapsed $TimingPath};return}
    throw"unsupported SSE field line: $Line"
}

function Invoke-G130U1HttpWorker {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$ManifestPath)
    $exitCode=22;$result=$null;$status=$null;$headersSeconds=$null;$errorText='';$response=$null;$client=$null;$stream=$null;$raw=$null;$manifest=$null;$resultPath='';$requestSha=$null
    $startedUtc=[DateTime]::UtcNow;$clock=[Diagnostics.Stopwatch]::StartNew()
    try{
        $manifest=Get-Content -LiteralPath $ManifestPath -Raw|ConvertFrom-Json
        Assert-G130U1ExactPropertySet $manifest @('schema','uri','request_path','raw_response_path','timing_path','result_path','assistant_path','expected_request_sha256','http_timeout_seconds') 'HTTP worker manifest'
        if([string]$manifest.schema-cne'g130_u1_http_worker_manifest_v1'){throw'HTTP worker manifest schema mismatch'}
        $resultPath=[string]$manifest.result_path
        $requestText=[IO.File]::ReadAllText([string]$manifest.request_path,[Text.UTF8Encoding]::new($false,$true))
        $request=$requestText|ConvertFrom-Json;Assert-G130U1RequestObject $request
        $requestSha=Get-G130U1Sha256File ([string]$manifest.request_path)
        if($requestSha-cne[string]$manifest.expected_request_sha256){throw'HTTP worker request hash mismatch'}
        Write-G130U1Utf8 ([string]$manifest.timing_path) ''
        Initialize-G130U1Utf8FramerType;$framer=[G130U1Utf8LineFramer]::new()
        $state=@{finish_count=0;usage_count=0;done_count=0;post_done_data_count=0;terminal_stage=0;finish_reason='';usage_completion_tokens=$null;first_content_seconds=$null;assistant=[Text.StringBuilder]::new();content_events=0;event_data=[Collections.Generic.List[string]]::new()}
        Add-Type -AssemblyName System.Net.Http;$client=[Net.Http.HttpClient]::new();$client.Timeout=[TimeSpan]::FromSeconds([double]$manifest.http_timeout_seconds)
        $message=[Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Post,[string]$manifest.uri)
        $message.Content=[Net.Http.StringContent]::new($requestText,[Text.Encoding]::UTF8,'application/json')
        Add-G130U1JsonLine ([string]$manifest.timing_path) ([pscustomobject][ordered]@{schema='g130_u1_http_timing_event_v1';event='request_start';utc=$startedUtc.ToString('o');elapsed_seconds=0})
        $response=$client.SendAsync($message,[Net.Http.HttpCompletionOption]::ResponseHeadersRead).Result;$headersSeconds=$clock.Elapsed.TotalSeconds;$status=[int]$response.StatusCode
        Add-G130U1JsonLine ([string]$manifest.timing_path) ([pscustomobject][ordered]@{schema='g130_u1_http_timing_event_v1';event='headers';elapsed_seconds=$headersSeconds;http_status=$status})
        $stream=$response.Content.ReadAsStreamAsync().Result
        $raw=[IO.File]::Open([string]$manifest.raw_response_path,[IO.FileMode]::Create,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite)
        $buffer=New-Object byte[] 4096
        while($true){$read=$stream.ReadAsync($buffer,0,$buffer.Length).Result;if($read-eq0){break};$raw.Write($buffer,0,$read);$raw.Flush();$elapsed=$clock.Elapsed.TotalSeconds
            foreach($line in @($framer.Push($buffer,$read))){Add-G130U1WorkerSseLine $line $state $elapsed ([string]$manifest.timing_path)}
        }
        foreach($line in @($framer.Complete())){Add-G130U1WorkerSseLine $line $state $clock.Elapsed.TotalSeconds ([string]$manifest.timing_path)}
        if($state.event_data.Count){$payload=($state.event_data.ToArray())-join"`n";$state.event_data.Clear();Invoke-G130U1SseEvent $payload $state $clock.Elapsed.TotalSeconds ([string]$manifest.timing_path)}
        $raw.Dispose();$raw=$null
        $assistant=$state.assistant.ToString();Write-G130U1Utf8 ([string]$manifest.assistant_path) $assistant
        $complete=[bool]($response.IsSuccessStatusCode-and$state.finish_count-eq1-and$state.usage_count-eq1-and$state.done_count-eq1-and$state.post_done_data_count-eq0-and$state.terminal_stage-eq3-and$state.finish_reason-ceq'length'-and$state.usage_completion_tokens-eq64)
        $result=[pscustomobject][ordered]@{schema='g130_u1_request_result_v3';request_start_utc=$startedUtc.ToString('o');completed_utc=[DateTime]::UtcNow.ToString('o');http_status=$status;success=[bool]$response.IsSuccessStatusCode;response_complete=$complete;finish_reason=$state.finish_reason;finish_count=[int]$state.finish_count;usage_completion_tokens=$state.usage_completion_tokens;usage_count=[int]$state.usage_count;done_received=[bool]($state.done_count-eq1);done_count=[int]$state.done_count;post_done_data_count=[int]$state.post_done_data_count;terminal_order='finish>usage>done';content_events=[int]$state.content_events;headers_elapsed_seconds=$headersSeconds;ttft_seconds=$state.first_content_seconds;wall_seconds=$clock.Elapsed.TotalSeconds;request_sha256=$requestSha;raw_response_sha256=Get-G130U1Sha256File ([string]$manifest.raw_response_path);assistant_text_sha256=Get-G130U1Sha256File ([string]$manifest.assistant_path);timing_sha256=Get-G130U1Sha256File ([string]$manifest.timing_path);error=''}
        if(-not$complete){throw'HTTP response contract incomplete'};$exitCode=0
    }catch{$errorText=$_.Exception.Message;if($null-eq$result){$finishCount=if($null-ne(Get-Variable state -ErrorAction SilentlyContinue)){[int]$state.finish_count}else{0};$usageCount=if($null-ne(Get-Variable state -ErrorAction SilentlyContinue)){[int]$state.usage_count}else{0};$doneCount=if($null-ne(Get-Variable state -ErrorAction SilentlyContinue)){[int]$state.done_count}else{0};$postDone=if($null-ne(Get-Variable state -ErrorAction SilentlyContinue)){[int]$state.post_done_data_count}else{0};$result=[pscustomobject][ordered]@{schema='g130_u1_request_result_v3';request_start_utc=$startedUtc.ToString('o');completed_utc=[DateTime]::UtcNow.ToString('o');http_status=$status;success=$false;response_complete=$false;finish_reason=$(if($finishCount){[string]$state.finish_reason}else{''});finish_count=$finishCount;usage_completion_tokens=$(if($usageCount){$state.usage_completion_tokens}else{$null});usage_count=$usageCount;done_received=[bool]($doneCount-eq1);done_count=$doneCount;post_done_data_count=$postDone;terminal_order='finish>usage>done';content_events=$(if($null-ne(Get-Variable state -ErrorAction SilentlyContinue)){[int]$state.content_events}else{0});headers_elapsed_seconds=$headersSeconds;ttft_seconds=$(if($null-ne(Get-Variable state -ErrorAction SilentlyContinue)){$state.first_content_seconds}else{$null});wall_seconds=$clock.Elapsed.TotalSeconds;request_sha256=$null;raw_response_sha256=$null;assistant_text_sha256=$null;timing_sha256=$null;error=$errorText}}else{$result.error=$errorText;$result.response_complete=$false}}
    finally{
        if($raw){$raw.Dispose()};if($stream){$stream.Dispose()};if($response){$response.Dispose()};if($client){$client.Dispose()}
        if($result-and$manifest){try{if($null-ne(Get-Variable state -ErrorAction SilentlyContinue)){Write-G130U1Utf8 ([string]$manifest.assistant_path) $state.assistant.ToString()}}catch{};if($requestSha){$result.request_sha256=$requestSha};foreach($pair in @(@('raw_response_sha256','raw_response_path'),@('assistant_text_sha256','assistant_path'),@('timing_sha256','timing_path'))){try{$artifactPath=[string]$manifest.($pair[1]);if(Test-Path -LiteralPath $artifactPath -PathType Leaf){$result.($pair[0])=Get-G130U1Sha256File $artifactPath}}catch{}}}
        if($result -and -not [string]::IsNullOrWhiteSpace($resultPath)){try{Write-G130U1JsonAtomic $resultPath $result}catch{}}
    }
    exit $exitCode
}

function Start-G130U1PowerShellChild {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$ScriptPath,[Parameter(Mandatory=$true)][string[]]$Arguments,
        [Parameter(Mandatory=$true)][string]$StdoutPath,[Parameter(Mandatory=$true)][string]$StderrPath)
    $quoted=@('&',"'"+$ScriptPath.Replace("'","''")+"'")
    foreach($argument in $Arguments){$quoted+="'"+$argument.Replace("'","''")+"'"}
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes(($quoted-join' ')))
    $hostPath=(Get-Process -Id $PID).Path
    Start-Process -FilePath $hostPath -ArgumentList (Join-G130U1WindowsArguments @('-NoProfile','-ExecutionPolicy','Bypass','-EncodedCommand',$encoded)) -PassThru -WindowStyle Hidden -RedirectStandardOutput $StdoutPath -RedirectStandardError $StderrPath
}

function Get-G130U1ReceiptIdentity {
    [CmdletBinding()]
    param([string]$DataPath,[string]$ReceiptPath,[UInt64]$ExpectedBytes,[string]$ExpectedSha256,[string]$Kind)
    if(-not(Test-Path -LiteralPath $DataPath -PathType Leaf)){throw"$Kind file missing: $DataPath"};if(-not(Test-Path -LiteralPath $ReceiptPath -PathType Leaf)){throw"$Kind receipt missing: $ReceiptPath"}
    $info=Get-Item -LiteralPath $DataPath;if([UInt64]$info.Length-ne$ExpectedBytes){throw"$Kind size mismatch"};$receipt=Get-Content -LiteralPath $ReceiptPath -Raw|ConvertFrom-Json
    foreach($name in @('schema','status','path','sha256','verified_at')){Assert-G130U1StringValue $receipt.$name "$Kind receipt.$name"};Assert-G130U1TypedNumber $receipt.bytes "$Kind receipt.bytes" -StrictlyPositive -Integral
    try{[void][DateTime]::Parse([string]$receipt.verified_at)}catch{throw"$Kind receipt verified_at invalid"}
    if([string]$receipt.schema-cne'g7_verified_file_receipt_v2'-or[string]$receipt.status-cne'verified'-or[UInt64]$receipt.bytes-ne$ExpectedBytes-or[string]$receipt.sha256-cnotmatch'^[0-9a-fA-F]{64}$'-or[string]$receipt.sha256-ine$ExpectedSha256){throw"$Kind receipt mismatch"}
    if(-not[string]::Equals([IO.Path]::GetFullPath([string]$receipt.path),[IO.Path]::GetFullPath($DataPath),[StringComparison]::OrdinalIgnoreCase)){throw"$Kind receipt path mismatch"}
    [pscustomobject][ordered]@{path=[IO.Path]::GetFullPath($DataPath);bytes=[UInt64]$info.Length;receipt_path=[IO.Path]::GetFullPath($ReceiptPath);receipt_file_sha256=Get-G130U1Sha256File $ReceiptPath;receipt_sha256=([string]$receipt.sha256).ToLowerInvariant();receipt_verified_at=[string]$receipt.verified_at;model_rehashed=$false}
}

function Get-G130U1BuildIdentity {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$ConfigPath)
    if(-not(Test-Path -LiteralPath $exePath -PathType Leaf)){throw"executable missing: $exePath"};if(-not(Test-Path -LiteralPath $manifestPath -PathType Leaf)){throw"build manifest missing: $manifestPath"}
    $manifest=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json
    Assert-G130U1ExactPropertySet $manifest @('schema','started_utc','completed_utc','head','worktree_dirty_at_build_start','configuration','command','input_fingerprint_sha256','inputs','executable','executable_sha256','executable_length','executable_last_write_utc') 'build manifest'
    if([string]$manifest.schema-cne$constants.expected_build_manifest_schema){throw'build manifest schema/version mismatch'}
    foreach($name in @('started_utc','completed_utc','executable_last_write_utc')){Assert-G130U1StringValue $manifest.$name "build manifest.$name";try{[void][DateTime]::Parse([string]$manifest.$name)}catch{throw"build manifest.$name invalid"}}
    foreach($name in @('head','configuration','input_fingerprint_sha256','executable','executable_sha256')){Assert-G130U1StringValue $manifest.$name "build manifest.$name"}
    if($manifest.worktree_dirty_at_build_start-isnot[bool]-or[string]$manifest.head-cnotmatch'^[0-9a-f]{40}$'-or[string]$manifest.configuration-cne'Release'-or[string]$manifest.input_fingerprint_sha256-cnotmatch'^[0-9a-f]{64}$'-or[string]$manifest.executable_sha256-cnotmatch'^[0-9a-f]{64}$'){throw'build manifest scalar contract invalid'}
    Assert-G130U1TypedNumber $manifest.executable_length 'build manifest.executable_length' -StrictlyPositive -Integral
    if($manifest.command-isnot[Array]-or@($manifest.command).Count-eq0){throw'build manifest command must be a nonempty array'};foreach($argument in @($manifest.command)){Assert-G130U1StringValue $argument 'build manifest command argument'}
    if($manifest.inputs-isnot[Array]-or@($manifest.inputs).Count-eq0){throw'build manifest inputs must be a nonempty array'};$seenInputs=@{}
    foreach($input in @($manifest.inputs)){Assert-G130U1ExactPropertySet $input @('path','sha256') 'build manifest input';Assert-G130U1StringValue $input.path 'build manifest input.path';if([string]$input.sha256-cnotmatch'^[0-9a-f]{64}$'){throw'build manifest input sha256 invalid'};if($seenInputs.ContainsKey([string]$input.path)){throw'build manifest duplicate input path'};$seenInputs[[string]$input.path]=$true}
    $fingerprintText=(@($manifest.inputs|ForEach-Object{[string]$_.path+'='+[string]$_.sha256})-join"`n")+"`n";if((Get-G130U1Sha256Text $fingerprintText)-cne[string]$manifest.input_fingerprint_sha256){throw'build manifest input fingerprint reconstruction mismatch'}
    $head=(&git -C $root rev-parse HEAD 2>$null).Trim().ToLowerInvariant();if($LASTEXITCODE-ne0){throw'git HEAD failed'};$branch=(&git -C $root branch --show-current 2>$null).Trim();$repo=(&git -C $root rev-parse --show-toplevel 2>$null).Trim();$statusText=@(&git -C $root status --porcelain=v1 --untracked-files=all 2>$null);if($LASTEXITCODE-ne0){throw'git status failed'};$status=@($statusText|ForEach-Object{[pscustomobject][ordered]@{porcelain=[string]$_}});&git -C $root merge-base --is-ancestor $constants.expected_git_base $head 2>$null;$ancestor=$LASTEXITCODE-eq0
    if(-not[string]::Equals([IO.Path]::GetFullPath([string]$manifest.executable),[IO.Path]::GetFullPath($exePath),[StringComparison]::OrdinalIgnoreCase)-or[UInt64]$manifest.executable_length-ne[UInt64](Get-Item -LiteralPath $exePath).Length){throw'build manifest executable identity mismatch'}
    [pscustomobject][ordered]@{schema='g130_u1_build_identity_v2';git=[pscustomobject][ordered]@{head=$head;branch=$branch;repository_root=$repo;expected_base=$constants.expected_git_base;base_ancestor=$ancestor;dirty=[bool]($status.Count-ne0);status=$status;status_includes_untracked=$true};build=[pscustomobject][ordered]@{manifest_path=$manifestPath;manifest_sha256=Get-G130U1Sha256File $manifestPath;schema=[string]$manifest.schema;head=([string]$manifest.head).ToLowerInvariant();configuration=[string]$manifest.configuration;worktree_dirty_at_build_start=[bool]$manifest.worktree_dirty_at_build_start;input_fingerprint_sha256=([string]$manifest.input_fingerprint_sha256).ToLowerInvariant();executable_path=[IO.Path]::GetFullPath($exePath);executable_bytes=[UInt64](Get-Item -LiteralPath $exePath).Length;executable_sha256=([string]$manifest.executable_sha256).ToLowerInvariant();observed_executable_sha256=Get-G130U1Sha256File $exePath};model=Get-G130U1ReceiptIdentity $constants.model_path $constants.model_receipt_path $constants.model_bytes $constants.model_sha256 'model';sidecar=Get-G130U1ReceiptIdentity $constants.sidecar_path $constants.sidecar_receipt_path $constants.sidecar_bytes $constants.sidecar_sha256 'sidecar';config_path=$ConfigPath;config_sha256=Get-G130U1Sha256File $ConfigPath}
}

function Get-G130U1ApprovalBinding {
    [CmdletBinding()]
    param()
    $head=(&git -C $root rev-parse HEAD 2>$null).Trim().ToLowerInvariant();if($LASTEXITCODE-ne0-or$head-cnotmatch'^[0-9a-f]{40}$'){throw'approval binding git HEAD unavailable'}
    if(-not(Test-Path -LiteralPath $exePath -PathType Leaf)-or-not(Test-Path -LiteralPath $manifestPath -PathType Leaf)){throw'approval binding build artifacts missing'}
    [pscustomobject][ordered]@{schema='g130_u1_approval_binding_v1';git_head=$head;runner_sha256=Get-G130U1Sha256File (Join-Path $root 'g130_u1_q1_profile.ps1');common_sha256=Get-G130U1Sha256File (Join-Path $root 'g130_u1_common.ps1');watchdog_sha256=Get-G130U1Sha256File (Join-Path $root 'g130_u1_watchdog.ps1');executable_sha256=Get-G130U1Sha256File $exePath;build_manifest_sha256=Get-G130U1Sha256File $manifestPath;worker_mode='parameter_set:HttpWorker@g130_u1_q1_profile.ps1'}
}

function Assert-G130U1ApprovalBindingEqual {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Expected,[Parameter(Mandatory=$true)][object]$Actual,[string]$Context='approval binding')
    $keys=@('schema','git_head','runner_sha256','common_sha256','watchdog_sha256','executable_sha256','build_manifest_sha256','worker_mode');Assert-G130U1ExactPropertySet $Expected $keys "$Context expected";Assert-G130U1ExactPropertySet $Actual $keys "$Context actual"
    foreach($binding in @($Expected,$Actual)){if([string]$binding.schema-cne'g130_u1_approval_binding_v1'-or[string]$binding.git_head-cnotmatch'^[0-9a-f]{40}$'-or[string]$binding.worker_mode-cne'parameter_set:HttpWorker@g130_u1_q1_profile.ps1'){throw"$Context schema/value invalid"};foreach($key in @('runner_sha256','common_sha256','watchdog_sha256','executable_sha256','build_manifest_sha256')){if([string]$binding.$key-cnotmatch'^[0-9a-f]{64}$'){throw"$Context $key invalid"}}}
    foreach($key in $keys){if([string]$Expected.$key-cne[string]$Actual.$key){throw"$Context mismatch: $key"}}
}

function Get-G130U1AppContainerState {
    if(-not('G130U1TokenNative'-as[type])){Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class G130U1TokenNative {
 [DllImport("kernel32.dll")] public static extern IntPtr GetCurrentProcess();
 [DllImport("advapi32.dll", SetLastError=true)] public static extern bool OpenProcessToken(IntPtr p, UInt32 a, out IntPtr t);
 [DllImport("advapi32.dll", SetLastError=true)] public static extern bool GetTokenInformation(IntPtr t,int c,out int v,int l,out int r);
 [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
}
'@}
    $token=[IntPtr]::Zero;if(-not[G130U1TokenNative]::OpenProcessToken([G130U1TokenNative]::GetCurrentProcess(),8,[ref]$token)){throw'OpenProcessToken failed'}
    try{$value=0;$returned=0;if(-not[G130U1TokenNative]::GetTokenInformation($token,29,[ref]$value,4,[ref]$returned)){throw'TokenIsAppContainer failed'};[bool]($value-ne0)}finally{[void][G130U1TokenNative]::CloseHandle($token)}
}

function Get-G130U1CpuTemperature {
    foreach($namespace in @('root/LibreHardwareMonitor','root/OpenHardwareMonitor')){try{$rows=@(Get-CimInstance -Namespace $namespace -ClassName Sensor -ErrorAction Stop|Where-Object{$_.SensorType-eq'Temperature'-and$_.Value-gt0-and(([string]$_.Identifier-match'(?i)/(?:intelcpu|amdcpu|cpu)/')-or(([string]$_.Name+' '+[string]$_.Parent)-match'(?i)\b(?:CPU|processor)\b'-and([string]$_.Name+' '+[string]$_.Parent)-notmatch'(?i)\bGPU\b'))});if($rows.Count){$provider=if($namespace-like'*Libre*'){'LibreHardwareMonitor'}else{'OpenHardwareMonitor'};$chosen=@($rows|Sort-Object {[double]$_.Value} -Descending|Select-Object -First 1)[0];return [pscustomobject][ordered]@{temperature_c=[double]$chosen.Value;provider=$provider;sensor_id=[string]$chosen.Identifier;sensor_name=[string]$chosen.Name}}}catch{}}
    throw'no reliable CPU temperature provider'
}

function Get-G130U1GpuProbe {
    $rows=@(&nvidia-smi --query-gpu=memory.used,power.draw,temperature.gpu,utilization.gpu --format=csv,noheader,nounits 2>&1);if($LASTEXITCODE-ne0-or$rows.Count-ne1){throw'nvidia-smi GPU probe failed'};$v=$rows[0].Split(',')|ForEach-Object{$_.Trim()};if($v.Count-ne4){throw'GPU probe field count'}
    $apps=@(&nvidia-smi --query-compute-apps=pid,process_name --format=csv,noheader,nounits 2>&1);if($LASTEXITCODE-ne0){throw'nvidia-smi process probe failed'}
    $compute=@();foreach($line in @($apps|Where-Object{$_-and$_-notmatch'No running processes'})){$parts=$line.Split(',',2);if($parts.Count-ne2){throw'GPU compute process row malformed'};[UInt64]$pidValue=0;if(-not[UInt64]::TryParse($parts[0].Trim(),[ref]$pidValue)-or$pidValue-eq0){throw'GPU compute process pid invalid'};$compute+=[pscustomobject][ordered]@{pid=$pidValue;process_name=$parts[1].Trim()}}
    [pscustomobject][ordered]@{vram_used_mib=[double]$v[0];power_w=[double]$v[1];temperature_c=[double]$v[2];utilization_percent=[double]$v[3];compute_processes=$compute}
}

function Get-G130U1ProcessConflicts {
    $all=@(Get-CimInstance Win32_Process -ErrorAction Stop);$conflict='(?i)^(ds4_server|ds4-server)(\.exe)?$';$background='(?i)(rclone|robocopy|defrag|backup|usoclient|mousocoreworker|wuauclt|tiworker|trustedinstaller|windowsupdate)'
    function Convert-LocalProcess($p){[pscustomobject][ordered]@{process_id=[UInt64]$p.ProcessId;parent_process_id=[UInt64]$p.ParentProcessId;name=[string]$p.Name;command_line=$(if($null-eq$p.CommandLine){''}else{[string]$p.CommandLine})}}
    [pscustomobject]@{conflicting=@($all|Where-Object{$_.Name-match$conflict}|ForEach-Object{Convert-LocalProcess $_});background=@($all|Where-Object{$_.Name-match$background}|ForEach-Object{Convert-LocalProcess $_});process_count=$all.Count}
}

function Get-G130U1SystemCounters {
    $os=Get-CimInstance Win32_OperatingSystem -ErrorAction Stop;$raw=Get-CimInstance Win32_PerfRawData_PerfOS_Memory -ErrorAction Stop;$formatted=Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory -ErrorAction Stop;$disk=@(Get-CimInstance Win32_PerfFormattedData_PerfDisk_LogicalDisk -ErrorAction Stop|Where-Object{$_.Name-eq'C:'}|Select-Object -First 1);$logical=@(Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction Stop);$cpu=@(Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -ErrorAction Stop|Where-Object{$_.Name-eq'_Total'}|Select-Object -First 1);if($disk.Count-ne1-or$logical.Count-ne1-or$cpu.Count-ne1){throw'system counter cardinality'}
    [pscustomobject][ordered]@{memory=[pscustomobject][ordered]@{available_bytes=[UInt64]$os.FreePhysicalMemory*[UInt64]1024;planned_bytes=(Get-G130U1Constants).planned_ram_bytes};paging=[pscustomobject][ordered]@{pages_output_total=[UInt64]$raw.PagesOutputPerSec;page_faults_total=[UInt64]$raw.PageFaultsPerSec;pages_per_sec=[UInt64]$formatted.PagesPerSec;page_reads_per_sec=[UInt64]$formatted.PageReadsPerSec};disk=[pscustomobject][ordered]@{volume='C:';queue_length=[double]$disk[0].AvgDiskQueueLength;read_bytes_per_sec=[UInt64]$disk[0].DiskReadBytesPerSec;write_bytes_per_sec=[UInt64]$disk[0].DiskWriteBytesPerSec;free_bytes=[UInt64]$logical[0].FreeSpace};cpu_percent=[double]$cpu[0].PercentProcessorTime}
}

function Get-G130U1PreflightProbe {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Identity)
    $errors=[Collections.ArrayList]::new();$statuses=[Collections.ArrayList]::new()
    function Invoke-LocalProbe([string]$Name,[scriptblock]$Body){try{$v=&$Body;[void]$statuses.Add([pscustomobject][ordered]@{name=$Name;status='ok'});$v}catch{[void]$errors.Add([pscustomobject][ordered]@{name=$Name;error=$_.Exception.Message});[void]$statuses.Add([pscustomobject][ordered]@{name=$Name;status='failed'});$null}}
    $app=Invoke-LocalProbe 'app_container' {Get-G130U1AppContainerState};$processes=Invoke-LocalProbe 'processes' {Get-G130U1ProcessConflicts};$counters=Invoke-LocalProbe 'system_counters' {Get-G130U1SystemCounters};$gpu=Invoke-LocalProbe 'gpu' {Get-G130U1GpuProbe};$cpuTemp=Invoke-LocalProbe 'cpu_temperature' {Get-G130U1CpuTemperature};[void](Invoke-LocalProbe 'identity' {if($null-eq$Identity){throw'identity null'};$true});$quiet=@()
    for($i=0;$i-lt3;$i++){if($i){Start-Sleep -Seconds $constants.quiet_window_interval_seconds};$w=Invoke-LocalProbe "quiet_window_$($i+1)" {$wc=Get-G130U1SystemCounters;$wg=Get-G130U1GpuProbe;[pscustomobject][ordered]@{index=$i+1;captured_utc=[DateTime]::UtcNow.ToString('o');cpu_percent=$wc.cpu_percent;disk_queue_length=$wc.disk.queue_length;gpu_percent=$wg.utilization_percent;gpu_power_w=$wg.power_w;gpu_compute_process_count=@($wg.compute_processes).Count}};if($null-ne$w){$quiet+=$w}}
    [void](Invoke-LocalProbe 'probe_completeness' {if($null-eq$processes-or$null-eq$counters-or$null-eq$gpu-or$null-eq$cpuTemp){throw'mandatory probe unavailable'};$true});$runner=Get-Process -Id $PID
    [pscustomobject][ordered]@{schema='g130_u1_preflight_probe_v1';captured_utc=[DateTime]::UtcNow.ToString('o');app_container=$app;conflicting_processes=$(if($processes){$processes.conflicting}else{@('probe-unavailable')});background_activity=$(if($processes){$processes.background}else{@('probe-unavailable')});gpu=$gpu;memory=$(if($counters){$counters.memory}else{$null});paging=$(if($counters){$counters.paging}else{$null});disk=$(if($counters){$counters.disk}else{$null});process_baseline=[pscustomobject][ordered]@{process_count=$(if($processes){$processes.process_count}else{0});working_set_bytes=[UInt64]$runner.WorkingSet64};cpu_temperature=$cpuTemp;quiet_windows=$quiet;identity=$Identity;probe_status=@($statuses);probe_errors=@($errors)}
}

function Test-G130U1Approval {
    [CmdletBinding()]
    param([string]$Path,[string]$PlanSha,[Parameter(Mandatory=$true)][object]$Binding)
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw'live approval artifact missing'};$a=Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json;Assert-G130U1ExactPropertySet $a @('schema','approved','scope','plan_sha256','binding','expires_utc') 'approval'
    foreach($name in @('schema','scope','plan_sha256','expires_utc')){Assert-G130U1StringValue $a.$name "approval.$name"};if($a.approved-isnot[bool]){throw'approval.approved type invalid'}
    if([string]$a.schema-cne'g130_u1_live_approval_v2'-or$a.approved-ne$true-or[string]$a.scope-cne'P0-U1-T1-diagnostic'-or[string]$a.plan_sha256-cne$PlanSha-or[DateTime]::Parse([string]$a.expires_utc).ToUniversalTime()-le[DateTime]::UtcNow){throw'live approval artifact invalid'};Assert-G130U1ApprovalBindingEqual $Binding $a.binding 'approval artifact binding';$a
}

function Test-G130U1WorkerStatusArtifact {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][int]$ExitCode,[Parameter(Mandatory=$true)][string]$ResultPath,
        [Parameter(Mandatory=$true)][string]$ExpectedRequestSha256)
    if(-not(Test-Path -LiteralPath $ResultPath -PathType Leaf)){return [pscustomobject]@{complete=$true;ok=$false;cause='HTTP_WORKER_EXIT_WITHOUT_STATUS';detail="worker_exit=$ExitCode";result=$null}}
    try{
        $r=Get-Content -LiteralPath $ResultPath -Raw|ConvertFrom-Json
        Assert-G130U1ExactPropertySet $r @('schema','request_start_utc','completed_utc','http_status','success','response_complete','finish_reason','finish_count','usage_completion_tokens','usage_count','done_received','done_count','post_done_data_count','terminal_order','content_events','headers_elapsed_seconds','ttft_seconds','wall_seconds','request_sha256','raw_response_sha256','assistant_text_sha256','timing_sha256','error') 'HTTP worker status'
        if([string]$r.schema-cne'g130_u1_request_result_v3'){throw'status schema'}
        foreach($name in @('request_start_utc','completed_utc')){Assert-G130U1StringValue $r.$name "HTTP worker status.$name";try{[void][DateTime]::Parse([string]$r.$name)}catch{throw"HTTP worker status.$name invalid"}}
        if($null-ne$r.http_status){Assert-G130U1TypedNumber $r.http_status 'HTTP worker status.http_status' -StrictlyPositive -Integral}
        foreach($name in @('finish_count','usage_count','done_count','post_done_data_count','content_events')){Assert-G130U1TypedNumber $r.$name "HTTP worker status.$name" -Integral}
        if($null-ne$r.usage_completion_tokens){Assert-G130U1TypedNumber $r.usage_completion_tokens 'HTTP worker status.usage_completion_tokens' -Integral}
        foreach($name in @('headers_elapsed_seconds','ttft_seconds')){if($null-ne$r.$name){Assert-G130U1TypedNumber $r.$name "HTTP worker status.$name"}}
        Assert-G130U1TypedNumber $r.wall_seconds 'HTTP worker status.wall_seconds'
        foreach($name in @('success','response_complete','done_received')){if($r.$name-isnot[bool]){throw"HTTP worker status.$name type"}}
        foreach($name in @('finish_reason','terminal_order','error')){Assert-G130U1StringValue $r.$name "HTTP worker status.$name" -AllowEmpty}
        foreach($name in @('request_sha256','raw_response_sha256','assistant_text_sha256','timing_sha256')){if($null-ne$r.$name-and($r.$name-isnot[string]-or[string]$r.$name-cnotmatch'^[0-9a-f]{64}$')){throw"HTTP worker status.$name invalid"}}
        if([string]$r.terminal_order-cne'finish>usage>done'){throw'HTTP worker terminal order schema'}
    }catch{return [pscustomobject]@{complete=$true;ok=$false;cause='HTTP_WORKER_STATUS_PARTIAL_OR_INVALID';detail=$_.Exception.Message;result=$null}}
    if(($ExitCode-eq0)-ne[bool]$r.response_complete){return [pscustomobject]@{complete=$true;ok=$false;cause='HTTP_WORKER_EXIT_STATUS_MISMATCH';detail="worker_exit=$ExitCode response_complete=$($r.response_complete)";result=$r}}
    if($null-eq$r.http_status-or[int]$r.http_status-lt200-or[int]$r.http_status-ge300){return [pscustomobject]@{complete=$true;ok=$false;cause='HTTP_NON_2XX';detail="http_status=$($r.http_status)";result=$r}}
    if($r.done_received-ne$true){return [pscustomobject]@{complete=$true;ok=$false;cause='SSE_DONE_MISSING';detail='SSE stream ended without [DONE]';result=$r}}
    if([int]$r.finish_count-ne1-or[int]$r.usage_count-ne1-or[int]$r.done_count-ne1-or[int]$r.post_done_data_count-ne0){return [pscustomobject]@{complete=$true;ok=$false;cause='SSE_TERMINAL_CARDINALITY_MISMATCH';detail="finish=$($r.finish_count) usage=$($r.usage_count) done=$($r.done_count) post_done=$($r.post_done_data_count)";result=$r}}
    if([string]$r.finish_reason-cne'length'){return [pscustomobject]@{complete=$true;ok=$false;cause='SSE_FINISH_REASON_MISMATCH';detail="finish=$($r.finish_reason)";result=$r}}
    if([int]$r.usage_completion_tokens-ne64){return [pscustomobject]@{complete=$true;ok=$false;cause='SSE_USAGE_TOKEN_MISMATCH';detail="completion_tokens=$($r.usage_completion_tokens)";result=$r}}
    if([string]$r.request_sha256-cne$ExpectedRequestSha256){return [pscustomobject]@{complete=$true;ok=$false;cause='REQUEST_HASH_MISMATCH';detail='worker request hash differs from prereg';result=$r}}
    if($r.response_complete-ne$true){return [pscustomobject]@{complete=$true;ok=$false;cause='HTTP_RESPONSE_PARTIAL';detail=[string]$r.error;result=$r}}
    [pscustomobject]@{complete=$true;ok=$true;cause='';detail='';result=$r}
}

function Get-G130U1WorkerCompletion {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][Diagnostics.Process]$Process,[Parameter(Mandatory=$true)][string]$ResultPath,
        [Parameter(Mandatory=$true)][string]$ExpectedRequestSha256)
    $Process.Refresh();if(-not$Process.HasExited){return [pscustomobject]@{complete=$false;ok=$false;cause='';detail='';result=$null}}
    Test-G130U1WorkerStatusArtifact ([int]$Process.ExitCode) $ResultPath $ExpectedRequestSha256
}

function Get-G130U1ParentAbortSnapshot {
    [CmdletBinding()]
    param([string]$StdoutPath,[string]$StderrPath,[AllowNull()][Diagnostics.Process]$Server,[AllowNull()][Diagnostics.Process]$Worker)
    $stdoutTail=@();$stderrTail=@();try{$stdoutTail=@(Get-Content -LiteralPath $StdoutPath -Tail 80 -ErrorAction Stop)}catch{};try{$stderrTail=@(Get-Content -LiteralPath $StderrPath -Tail 80 -ErrorAction Stop)}catch{}
    [pscustomobject][ordered]@{captured_utc=[DateTime]::UtcNow.ToString('o');server_alive=$(if($Server){try{$Server.Refresh();-not$Server.HasExited}catch{$false}}else{$false});worker_alive=$(if($Worker){try{$Worker.Refresh();-not$Worker.HasExited}catch{$false}}else{$false});stdout_tail=$stdoutTail;stderr_tail=$stderrTail}
}

function Write-G130U1MinimumReceipt {
    param([string]$Path,[string]$RunId,[string]$LedgerPath,[switch]$InjectFailure)
    if($InjectFailure){throw'injected minimum receipt initialization failure'}
    Write-G130U1JsonAtomic $Path ([pscustomobject][ordered]@{schema='g130_u1_final_receipt_v3';run_id=$RunId;status='INCOMPLETE/RUNNING';outcome='NEGATIVE';intended_result=$null;quotable=$false;cause='INITIALIZING';exit_code=25;completed_utc=$null;measurement_basis='profile-on, existing-fence';existing_base_fences_and_events_expected=$true;claim_of_zero_synchronization=$false;normal_exit_contract='DS4_BENCH_EXIT_AFTER_REQUESTS=1';authenticated_shutdown_endpoint_use='abort-only';ledger=[pscustomobject][ordered]@{destination=$LedgerPath;error=$null};artifact_hashes=@()})
}

function Write-G130U1EmergencyReceipt {
    param([string]$Path,[string]$RunId,[string]$LedgerPath,[string]$Cause,[string]$Detail)
    $intended=[pscustomobject][ordered]@{outcome='NEGATIVE';cause=$Cause;exit_code=25}
    $receipt=[pscustomobject][ordered]@{schema='g130_u1_final_receipt_v3';run_id=$RunId;status='INCOMPLETE';outcome='NEGATIVE';intended_result=$intended;quotable=$false;cause=$Cause;exit_code=25;detail=$Detail;evidence_error=$Detail;completed_utc=[DateTime]::UtcNow.ToString('o');measurement_basis='profile-on, existing-fence';existing_base_fences_and_events_expected=$true;claim_of_zero_synchronization=$false;normal_exit_contract='DS4_BENCH_EXIT_AFTER_REQUESTS=1';authenticated_shutdown_endpoint_use='abort-only';ledger=[pscustomobject][ordered]@{destination=$LedgerPath;error=$null};artifact_hashes=@()}
    try{Write-G130U1JsonAtomic $Path $receipt}catch{try{Write-G130U1Json $Path $receipt}catch{}}
    if(Test-Path -LiteralPath $Path -PathType Leaf){try{
        $runDirectory=Split-Path -Parent $Path;$rowPath=Join-Path $runDirectory 'ledger_row.json'
        $sha=Get-G130U1Sha256File $Path;Write-G130U1Utf8 ($Path+'.sha256') ($sha+"  receipt.json`n")
        $row=[pscustomobject][ordered]@{schema='g130_u1_ledger_row_v1';run_id=$RunId;completed_utc=$receipt.completed_utc;scope='full/open';tier='T1';protocol_tokens=64;outcome='NEGATIVE';cause=$Cause;exit_code=25;intended_result=$intended;receipt_sha256=$sha;state='incomplete_evidence';rendering_method='not_applicable';l_grade='not_applicable';l_grade_final=$false}
        try{Write-G130U1JsonAtomic $rowPath $row;Add-G130U1LedgerRow $LedgerPath $row}catch{
            $ledgerError=$_.Exception.Message;$receipt.cause='LEDGER_APPEND_FAILED';$receipt.ledger.error=$ledgerError
            Write-G130U1JsonAtomic $Path $receipt;$sha=Get-G130U1Sha256File $Path;Write-G130U1Utf8 ($Path+'.sha256') ($sha+"  receipt.json`n")
            $row.cause='LEDGER_APPEND_FAILED';$row.receipt_sha256=$sha;$row.state='ledger_append_failed';try{Write-G130U1JsonAtomic $rowPath $row}catch{}
            return [pscustomobject]@{path=$Path;sha256=$sha;ledger_row=$rowPath;ledger_error=$ledgerError;outcome='NEGATIVE';cause='LEDGER_APPEND_FAILED';exit_code=25}
        }
        return [pscustomobject]@{path=$Path;sha256=$sha;ledger_row=$rowPath;ledger_error=$null;outcome='NEGATIVE';cause=$Cause;exit_code=25}
    }catch{}}
    [pscustomobject]@{path=$Path;sha256=$null;ledger_row=(Join-Path (Split-Path -Parent $Path) 'ledger_row.json');ledger_error='receipt unavailable';outcome='NEGATIVE';cause=$Cause;exit_code=25}
}

function Add-G130U1LedgerRow {
    [CmdletBinding()]
    param([string]$LedgerPath,[object]$Row)
    $directory=Split-Path -Parent $LedgerPath;if(-not(Test-Path -LiteralPath $directory -PathType Container)){throw'ledger parent missing'};$line=(ConvertTo-G130U1Json $Row -Compress)+"`n";$bytes=[Text.UTF8Encoding]::new($false).GetBytes($line);$stream=[IO.File]::Open($LedgerPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None);try{[void]$stream.Seek(0,[IO.SeekOrigin]::End);$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
}

function Complete-G130U1Evidence {
    [CmdletBinding()]
    param([string]$RunId,[string]$RunDirectory,[string]$LedgerPath,[string]$Outcome,[int]$ExitCode,[string]$Cause,[string]$Detail,
        [AllowNull()][object]$Config,[AllowNull()][object]$Prereg,[AllowNull()][object]$Preflight,[AllowNull()][object]$Profile,
        [AllowNull()][object]$Http,[AllowNull()][object]$Lifecycle,[AllowNull()][object]$Cleanup,[AllowNull()][object]$Abort,
        [ValidateSet('none','before_final_write')][string]$FailureMode='none')
    $receiptPath=Join-Path $RunDirectory 'receipt.json';$ledgerError=$null;$rendering='not_applicable';$grade='not_applicable';$gradeFinal=$false
    if($Cause-match'^A4_'){$rendering='unrendered_partial_text_preserved';$grade='UNASSESSED';$gradeFinal=$false}
    $artifactNames=@('approval.json','preregistration.json','config.json','environment.json','build_identity.json','preflight.json','server.stdout.log','server.stderr.log','request.json','raw_response.sse','request_result.json','assistant_text.txt','http_timing.jsonl','watchdog.jsonl','watchdog_sampler.jsonl','watchdog_abort.json','profile_summary.json','ownership.json','ready.marker','request.started','monitor.complete','watchdog_manifest.json','http_worker_manifest.json','watchdog.stdout.log','watchdog.stderr.log','http_worker.stdout.log','http_worker.stderr.log')
    $intended=[pscustomobject][ordered]@{outcome=$Outcome;cause=$Cause;exit_code=$ExitCode}
    $receipt=[pscustomobject][ordered]@{schema='g130_u1_final_receipt_v3';run_id=$RunId;status='complete';completed_utc=[DateTime]::UtcNow.ToString('o');tier='T1';scope='full/open';protocol_tokens=64;outcome=$Outcome;intended_result=$intended;quotable=$false;automatic_retry_count=0;exit_code=$ExitCode;cause=$Cause;detail=$Detail;measurement_basis='profile-on, existing-fence';existing_base_fences_and_events_expected=$true;claim_of_zero_synchronization=$false;normal_exit_contract='DS4_BENCH_EXIT_AFTER_REQUESTS=1';authenticated_shutdown_endpoint_use='abort-only';config_echo=$Config;preregistration=$Prereg;preflight=$Preflight;profile=$Profile;http=$Http;lifecycle=$Lifecycle;cleanup=$Cleanup;abort=$Abort;partial_rendering=[pscustomobject][ordered]@{method=$rendering;l_grade=$grade;final_grade=$gradeFinal};ledger=[pscustomobject][ordered]@{destination=$LedgerPath;error=$null};artifact_hashes=@(Get-G130U1ArtifactRecords ($artifactNames|ForEach-Object{Join-Path $RunDirectory $_}));claim='DIAGNOSTIC/non-quotable or NEGATIVE/CONTAMINATED only'}
    if($FailureMode-ceq'before_final_write'){throw'injected evidence finalization failure'}
    Write-G130U1JsonAtomic $receiptPath $receipt;$receiptSha=Get-G130U1Sha256File $receiptPath;Write-G130U1Utf8 ($receiptPath+'.sha256') ($receiptSha+"  receipt.json`n")
    $row=[pscustomobject][ordered]@{schema='g130_u1_ledger_row_v1';run_id=$RunId;completed_utc=$receipt.completed_utc;scope='full/open';tier='T1';protocol_tokens=64;outcome=$Outcome;cause=$Cause;exit_code=$ExitCode;intended_result=$intended;receipt_sha256=$receiptSha;state='complete';rendering_method=$rendering;l_grade=$grade;l_grade_final=$gradeFinal}
    try{Write-G130U1JsonAtomic (Join-Path $RunDirectory 'ledger_row.json') $row;Add-G130U1LedgerRow $LedgerPath $row}catch{$ledgerError=$_.Exception.Message;$receipt.outcome='NEGATIVE';$receipt.cause='LEDGER_APPEND_FAILED';$receipt.exit_code=25;$receipt.ledger.error=$ledgerError;$receipt.status='complete_with_ledger_failure';Write-G130U1JsonAtomic $receiptPath $receipt;$receiptSha=Get-G130U1Sha256File $receiptPath;Write-G130U1Utf8 ($receiptPath+'.sha256') ($receiptSha+"  receipt.json`n");$row.outcome='NEGATIVE';$row.cause='LEDGER_APPEND_FAILED';$row.exit_code=25;$row.receipt_sha256=$receiptSha;$row.state='ledger_append_failed';try{Write-G130U1JsonAtomic (Join-Path $RunDirectory 'ledger_row.json') $row}catch{}}
    [pscustomobject]@{path=$receiptPath;sha256=$receiptSha;ledger_row=(Join-Path $RunDirectory 'ledger_row.json');ledger_error=$ledgerError;outcome=[string]$receipt.outcome;cause=[string]$receipt.cause;exit_code=[int]$receipt.exit_code}
}

function Invoke-G130U1MockLifecycle {
    param([string]$Scenario,[string]$TargetRoot,[string]$ProfilePath)
    $runId='mock_'+$Scenario.Replace('-','_');$runDir=Join-Path $TargetRoot $runId;New-Item -ItemType Directory -Path $runDir|Out-Null;$ledger=$(if($Scenario-ceq'ledger-failure'){Join-Path $TargetRoot 'missing_ledger_parent\g130_u1_ledger.jsonl'}else{Join-Path $TargetRoot 'g130_u1_ledger.jsonl'});$receipt=Join-Path $runDir 'receipt.json';try{Write-G130U1MinimumReceipt $receipt $runId $ledger -InjectFailure:($Scenario-ceq'receipt-init-failure')}catch{[void](Write-G130U1EmergencyReceipt $receipt $runId $ledger 'RECEIPT_INITIALIZATION_FAILED' $_.Exception.Message)}
    $exit=0;$outcome='DIAGNOSTIC';$cause='MOCK_SUCCESS';$detail='';$profile=$null;$cleanup=[pscustomobject]@{cleanup_sync_ok=$true;forced_kill=$false;child_forced_kill=$false;worker_cleanup_ok=$true;watchdog_cleanup_ok=$true;environment_restored=$true}
    try{if($Scenario-ceq'pre-configuration-failure'){throw'failure before config/prereg'};foreach($name in @('server.stdout.log','server.stderr.log','raw_response.sse','request_result.json','assistant_text.txt','http_timing.jsonl')){Write-G130U1Utf8 (Join-Path $runDir $name) ''};if($Scenario-in@('success','ledger-failure')){if(-not$ProfilePath){throw'mock profile required'};Copy-Item -LiteralPath $ProfilePath -Destination (Join-Path $runDir 'server.stderr.log') -Force;$profile=Read-G130U1Profile (Join-Path $runDir 'server.stderr.log') 64;Write-G130U1Json (Join-Path $runDir 'profile_summary.json') $profile}elseif($Scenario-ceq'request-failure'){$exit=22;$outcome='NEGATIVE';$cause='REQUEST_FAILED'}elseif($Scenario-ceq'parser-failure'){$exit=23;$outcome='NEGATIVE';$cause='PROFILE_PARSER_FAILED';$detail='injected closed-profile parser failure'}elseif($Scenario-ceq'forced-kill'){$exit=24;$outcome='NEGATIVE';$cause='FORCED_KILL';$cleanup.forced_kill=$true}elseif($Scenario-ceq'cleanup-failure'){$exit=24;$outcome='NEGATIVE';$cause='CLEANUP_FAILED';$cleanup.cleanup_sync_ok=$false}elseif($Scenario-ceq'receipt-init-failure'){$exit=25;$outcome='NEGATIVE';$cause='RECEIPT_INITIALIZATION_FAILED'}elseif($Scenario-ceq'a4-abort'){$exit=21;$outcome='NEGATIVE';$cause='A4_REPEATED_BLOCK';$detail='partial text preserved but not rendered'}}
    catch{$exit=25;$outcome='NEGATIVE';$cause='MOCK_INTERNAL_FAILURE';$detail=$_.Exception.Message}
    finally{try{$info=Complete-G130U1Evidence $runId $runDir $ledger $outcome $exit $cause $detail $null $null $null $profile $null $null $cleanup $null $(if($Scenario-ceq'receipt-finalization-failure'){'before_final_write'}else{'none'})}catch{$info=Write-G130U1EmergencyReceipt $receipt $runId $ledger 'EVIDENCE_FINALIZATION_FAILED' $_.Exception.Message}}
    $exit=[int]$info.exit_code;$outcome=[string]$info.outcome;$cause=[string]$info.cause;[pscustomobject]@{exit_code=$exit;outcome=$outcome;cause=$cause;receipt=$info;run_directory=$runDir}|ConvertTo-Json -Depth 10;exit $exit
}

if($WhatIf){Get-G130U1WhatIfPlan $root|ConvertTo-Json -Depth 60;exit 0}
if($HttpWorker){Invoke-G130U1HttpWorker $WorkerManifestPath}
if($ParseProfilePath){try{Read-G130U1Profile $ParseProfilePath $GeneratedTokens|ConvertTo-Json -Depth 60;exit 0}catch{[pscustomobject]@{schema='g130_u1_profile_error_v2';error=$_.Exception.Message}|ConvertTo-Json;exit 23}}
if($PreflightFixturePath){try{$probe=Get-Content -LiteralPath $PreflightFixturePath -Raw|ConvertFrom-Json;$v=Test-G130U1Preflight $probe;$v|ConvertTo-Json -Depth 60;if($v.pass){exit 0}else{exit 20}}catch{[pscustomobject]@{schema='g130_u1_preflight_error_v2';error=$_.Exception.Message}|ConvertTo-Json;exit 20}}
if($SupervisionFixturePath){try{$fixture=Get-Content -LiteralPath $SupervisionFixturePath -Raw|ConvertFrom-Json;Assert-G130U1ExactPropertySet $fixture @('schema','heartbeat_stall_seconds','wall_cap_seconds','samples') 'supervision fixture';if([string]$fixture.schema-cne'g130_u1_parent_supervision_fixture_v1'){throw'supervision fixture schema'};$decision=$null;foreach($s in @($fixture.samples)){$decision=Test-G130U1ParentSupervisionSample $s ([double]$fixture.heartbeat_stall_seconds) ([double]$fixture.wall_cap_seconds);if($decision.abort){break}};$decision|ConvertTo-Json;exit $(if($decision.abort){21}else{0})}catch{[pscustomobject]@{error=$_.Exception.Message}|ConvertTo-Json;exit 21}}
if($QuoteFixturePath){$values=@((Get-Content -LiteralPath $QuoteFixturePath -Raw|ConvertFrom-Json).values);[pscustomobject]@{quoted=@($values|ForEach-Object{ConvertTo-G130U1WindowsArgument ([string]$_)});joined=Join-G130U1WindowsArguments @($values|ForEach-Object{[string]$_})}|ConvertTo-Json -Depth 10;exit 0}
if($TcpWaitFixturePath){try{$f=Get-Content -LiteralPath $TcpWaitFixturePath -Raw|ConvertFrom-Json;Assert-G130U1ExactPropertySet $f @('schema','port','timeout_milliseconds','poll_milliseconds','watchdog_pid','heartbeat_path','sampler_path','heartbeat_stall_seconds','wall_cap_seconds') 'TCP wait fixture';if([string]$f.schema-cne'g130_u1_tcp_wait_fixture_v2'){throw'TCP wait fixture schema'};$mockWatchdog=Get-Process -Id ([int]$f.watchdog_pid) -ErrorAction Stop;Initialize-G130U1Utf8FramerType;$clock=[Diagnostics.Stopwatch]::StartNew();$attempts=0;$now=[DateTime]::UtcNow;$state=[pscustomobject]@{heartbeat_seen=$now;sampler_seen=$now;heartbeat_offset=[UInt64]0;sampler_offset=[UInt64]0;heartbeat_rows=[Int64]0;sampler_rows=[Int64]0;heartbeat_sequence=[UInt64]0;sampler_sequence=[UInt64]0;heartbeat_framer=[G130U1Utf8LineFramer]::new();sampler_framer=[G130U1Utf8LineFramer]::new()};while($clock.ElapsedMilliseconds-lt[int]$f.timeout_milliseconds){$attempts++;if(Test-G130U1TcpReady ([int]$f.port)){[pscustomobject]@{schema='g130_u1_tcp_wait_result_v2';ready=$true;attempts=$attempts;elapsed_milliseconds=$clock.ElapsedMilliseconds;heartbeat_rows=$state.heartbeat_rows;sampler_rows=$state.sampler_rows;offset_mode=$true}|ConvertTo-Json;exit 0};$mockWatchdog.Refresh();$now=[DateTime]::UtcNow;$sample=Get-G130U1ParentSourceSample $state ([string]$f.heartbeat_path) ([string]$f.sampler_path) $now $clock.Elapsed.TotalSeconds (-not$mockWatchdog.HasExited);$decision=Test-G130U1ParentSupervisionSample $sample ([double]$f.heartbeat_stall_seconds) ([double]$f.wall_cap_seconds);if($decision.abort){[pscustomobject]@{schema='g130_u1_tcp_wait_result_v2';ready=$false;attempts=$attempts;cause=$decision.cause;detail=[string]$sample.source_error;offset_mode=$true}|ConvertTo-Json;exit 21};Start-Sleep -Milliseconds ([int]$f.poll_milliseconds)};[pscustomobject]@{schema='g130_u1_tcp_wait_result_v2';ready=$false;attempts=$attempts;elapsed_milliseconds=$clock.ElapsedMilliseconds;cause='TCP_WAIT_FIXTURE_TIMEOUT';offset_mode=$true}|ConvertTo-Json;exit 21}catch{[pscustomobject]@{schema='g130_u1_tcp_wait_result_v2';ready=$false;error=$_.Exception.Message}|ConvertTo-Json;exit 21}}
if($WorkerStatusFixturePath){try{$f=Get-Content -LiteralPath $WorkerStatusFixturePath -Raw|ConvertFrom-Json;Assert-G130U1ExactPropertySet $f @('schema','exit_code','result_path','expected_request_sha256') 'worker status fixture';if([string]$f.schema-cne'g130_u1_worker_status_fixture_v1'){throw'worker status fixture schema'};$r=Test-G130U1WorkerStatusArtifact ([int]$f.exit_code) ([string]$f.result_path) ([string]$f.expected_request_sha256);$r|ConvertTo-Json -Depth 20;exit $(if($r.ok){0}else{22})}catch{[pscustomobject]@{complete=$true;ok=$false;cause='HTTP_WORKER_STATUS_FIXTURE_INVALID';detail=$_.Exception.Message}|ConvertTo-Json;exit 22}}
if($ApprovalFixturePath){try{$f=Get-Content -LiteralPath $ApprovalFixturePath -Raw|ConvertFrom-Json;Assert-G130U1ExactPropertySet $f @('schema','approval_path','plan_sha256','binding') 'approval fixture';if([string]$f.schema-cne'g130_u1_approval_fixture_v1'){throw'approval fixture schema'};$a=Test-G130U1Approval ([string]$f.approval_path) ([string]$f.plan_sha256) $f.binding;[pscustomobject]@{valid=$true;approval=$a}|ConvertTo-Json -Depth 20;exit 0}catch{[pscustomobject]@{valid=$false;error=$_.Exception.Message}|ConvertTo-Json;exit 19}}
if($MockLifecycleScenario){Invoke-G130U1MockLifecycle $MockLifecycleScenario $MockOutputRoot $MockProfilePath}
if(-not$Live){[pscustomobject]@{schema='g130_u1_live_refusal_v1';error='live execution requires explicit -Live and -ApprovalArtifactPath'}|ConvertTo-Json;exit 19}

if([string]::IsNullOrWhiteSpace($OutputRoot)){$OutputRoot=Join-Path $root 'g7_runs\g130_u1_q1_profile'}
Assert-G130U1SafePathText $OutputRoot 'OutputRoot';Assert-G130U1SafePathText $ApprovalArtifactPath 'ApprovalArtifactPath'
$stamp=[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ');if(-not$Tag){$Tag='g130_u1_'+$stamp};$runId=$Tag;$runDirectory=Join-Path $OutputRoot $runId
$ledgerPath=Join-Path $OutputRoot 'g130_u1_ledger.jsonl';$receiptPath=Join-Path $runDirectory 'receipt.json';$paths=[ordered]@{}
try{if(Test-Path -LiteralPath $runDirectory){throw"run directory exists: $runDirectory"};New-Item -ItemType Directory -Path $runDirectory -Force|Out-Null;foreach($name in @('approval.json','preregistration.json','config.json','environment.json','build_identity.json','preflight.json','server.stdout.log','server.stderr.log','request.json','raw_response.sse','request_result.json','assistant_text.txt','http_timing.jsonl','watchdog.jsonl','watchdog_sampler.jsonl','watchdog_abort.json','profile_summary.json','ownership.json','ready.marker','request.started','monitor.complete','watchdog.stdout.log','watchdog.stderr.log','http_worker.stdout.log','http_worker.stderr.log','watchdog_manifest.json','http_worker_manifest.json')){$paths[$name]=Join-Path $runDirectory $name};Write-G130U1MinimumReceipt $receiptPath $runId $ledgerPath}catch{$bootstrap=Write-G130U1EmergencyReceipt $receiptPath $runId $ledgerPath 'RECEIPT_INITIALIZATION_FAILED' $_.Exception.Message;Write-Output('G130_U1_RECEIPT='+$bootstrap.path);exit 25}
$outcome='NEGATIVE';$exitCode=25;$cause='INTERNAL_FAILURE';$detail='';$config=$null;$prereg=$null;$preflight=$null;$profile=$null;$http=$null;$abort=$null;$server=$null;$watchdog=$null;$worker=$null;$serverStart=$null;$envState=$null;$port=0;$baseUri='';$shutdownToken=$null;$receiptInfo=$null
$cleanup=[pscustomobject][ordered]@{attempted=$false;stopped=$false;forced_kill=$false;child_forced_kill=$false;worker_cleanup_ok=$true;watchdog_cleanup_ok=$true;cleanup_sync_ok=$true;environment_restored=$true;shutdown=$null;error=''};$lifecycle=[ordered]@{server_pid=$null;server_start_utc=$null;server_exit_code=$null;watchdog_pid=$null;watchdog_exit_code=$null;http_worker_pid=$null;http_worker_exit_code=$null;readiness='not-started';request_started=$false;request_completed=$false;parent_supervision=$true;forced_kill=$false}
try{
    $shutdownToken=New-G130U1ShutdownToken;$approvalBinding=Get-G130U1ApprovalBinding;$plan=Get-G130U1WhatIfPlan $root $approvalBinding;$planSha=Get-G130U1Sha256Text (ConvertTo-G130U1Json $plan -Compress);$approval=Test-G130U1Approval $ApprovalArtifactPath $planSha $approvalBinding;Write-G130U1Json $paths['approval.json'] $approval
    $request=New-G130U1RequestObject;Assert-G130U1RequestObject $request;Write-G130U1Utf8 $paths['request.json'] (ConvertTo-G130U1Json $request -Compress);$requestSha=Get-G130U1Sha256File $paths['request.json']
    $port=Get-G130U1FreePort;$baseUri="http://127.0.0.1:$port";$serverArgs=@('-m',$constants.model_path,'--cuda','-c',[string]$constants.context,'-n',[string]$constants.max_tokens,'--mtp-draft',[string]$constants.mtp_draft_tokens,'--host','127.0.0.1','--port',[string]$port)
    if($serverArgs-contains'--trace'-or$serverArgs-contains'--trace-file'){throw'trace argument forbidden'}
    $config=[pscustomobject][ordered]@{schema='g130_u1_live_config_v3';run_id=$runId;immutable_plan=$plan;plan_sha256=$planSha;approval_binding=$approvalBinding;request_sha256=$requestSha;server_arguments=$serverArgs;request_uri=$baseUri+'/v1/chat/completions';normal_exit='DS4_BENCH_EXIT_AFTER_REQUESTS=1';shutdown_endpoint_use='abort-only';created_utc=[DateTime]::UtcNow.ToString('o');measurement_basis='profile-on, existing-fence';powershell_role_mapping=$plan.powershell_role_mapping};Write-G130U1Json $paths['config.json'] $config
    $prereg=[pscustomobject][ordered]@{schema='g130_u1_preregistration_v3';run_id=$runId;registered_utc=[DateTime]::UtcNow.ToString('o');tier='T1';n=1;approval_sha256=Get-G130U1Sha256File $paths['approval.json'];approval_binding=$approvalBinding;plan_sha256=$planSha;config_sha256=Get-G130U1Sha256File $paths['config.json'];request_sha256=$requestSha;contract=$plan.preregistration;request_contract=$plan.request_contract;disk=$plan.disk;powershell_role_mapping=$plan.powershell_role_mapping;automatic_retries=0;outcome_scope=$plan.outcome_scope;quotable=$false};Write-G130U1Json $paths['preregistration.json'] $prereg
    $envAllowed=Get-G130U1Environment $shutdownToken;$envEvidence=[ordered]@{};foreach($name in $envAllowed.Keys){if([string]$name-ceq'DS4_G130_U1_SHUTDOWN_TOKEN'){$envEvidence['DS4_G130_U1_SHUTDOWN_TOKEN_SHA256']=Get-G130U1Sha256Text $shutdownToken}else{$envEvidence[[string]$name]=[string]$envAllowed[$name]}};Write-G130U1Json $paths['environment.json'] ([pscustomobject][ordered]@{schema='g130_u1_environment_v2';clear_all_ds4_first=$true;allowlist_names=@($envAllowed.Keys);values=$envEvidence;shutdown_token_redacted=$true;forbidden=$plan.environment_policy.forbidden})
    $build=Get-G130U1BuildIdentity $paths['config.json'];Write-G130U1Json $paths['build_identity.json'] $build;$probe=Get-G130U1PreflightProbe $build;$preflight=Test-G130U1Preflight $probe;Write-G130U1Json $paths['preflight.json'] ([pscustomobject][ordered]@{schema='g130_u1_preflight_v2';preregistration_sha256=Get-G130U1Sha256File $paths['preregistration.json'];probe=$probe;validation=$preflight});if(-not$preflight.pass){$exitCode=20;$cause='PREFLIGHT_NO_GO';throw'preflight rejected launch'}
    $launchBinding=Get-G130U1ApprovalBinding;Assert-G130U1ApprovalBindingEqual $approvalBinding $launchBinding 'immediate pre-launch binding';$launchStatus=@(&git -C $root status --porcelain=v1 --untracked-files=all 2>$null);if($LASTEXITCODE-ne0-or$launchStatus.Count-ne0){throw'immediate pre-launch git status is not clean'};if((Get-G130U1Sha256File $manifestPath)-cne[string]$approvalBinding.build_manifest_sha256){throw'immediate pre-launch manifest hash mismatch'}
    $envState=Enter-G130U1Environment $envAllowed;try{$server=Start-Process -FilePath $exePath -ArgumentList (Join-G130U1WindowsArguments $serverArgs) -PassThru -WindowStyle Hidden -RedirectStandardOutput $paths['server.stdout.log'] -RedirectStandardError $paths['server.stderr.log'];[void]$server.Handle;$serverStart=$server.StartTime.ToUniversalTime()}finally{Exit-G130U1Environment $envState;$envState=$null;$cleanup.environment_restored=$true}
    $lifecycle.server_pid=[int]$server.Id;$lifecycle.server_start_utc=$serverStart.ToString('o');Write-G130U1Json $paths['ownership.json'] ([pscustomobject][ordered]@{schema='g130_u1_process_ownership_v2';run_id=$runId;runner_pid=$PID;server_pid=[int]$server.Id;server_start_utc=$serverStart.ToString('o');executable=[IO.Path]::GetFullPath($exePath);created_utc=[DateTime]::UtcNow.ToString('o')})
    $watchManifest=[pscustomobject][ordered]@{schema='g130_u1_watchdog_manifest_v2';run_id=$runId;owned_pid=[int]$server.Id;owned_start_utc=$serverStart.ToString('o');owned_exe_path=[IO.Path]::GetFullPath($exePath);ownership_path=$paths['ownership.json'];stderr_path=$paths['server.stderr.log'];stream_path=$paths['raw_response.sse'];ready_path=$paths['ready.marker'];request_started_path=$paths['request.started'];request_result_path=$paths['request_result.json'];monitor_complete_path=$paths['monitor.complete'];watchdog_log_path=$paths['watchdog.jsonl'];sampler_path=$paths['watchdog_sampler.jsonl'];abort_path=$paths['watchdog_abort.json'];page_out_baseline=[UInt64]$probe.paging.pages_output_total;thresholds=[pscustomobject][ordered]@{cadence_seconds=$constants.watchdog_cadence_seconds;wall_cap_seconds=$constants.wall_cap_seconds;startup_stall_seconds=$constants.startup_stall_seconds;ttft_cap_seconds=$constants.ttft_cap_seconds;application_data_stall_seconds=$constants.application_data_stall_seconds;page_out_delta_abort_pages=$constants.page_out_delta_abort_pages;throughput_floor_tps=$constants.throughput_floor_tps;throughput_warm_tokens=$constants.throughput_warm_tokens;throughput_consecutive_tokens=$constants.throughput_consecutive_tokens}};Write-G130U1Json $paths['watchdog_manifest.json'] $watchManifest
    $watchdog=Start-G130U1PowerShellChild $watchdogPath @('-ManifestPath',$paths['watchdog_manifest.json']) $paths['watchdog.stdout.log'] $paths['watchdog.stderr.log'];[void]$watchdog.Handle;$lifecycle.watchdog_pid=[int]$watchdog.Id
    Initialize-G130U1Utf8FramerType;$parentClock=[Diagnostics.Stopwatch]::StartNew();$parentSource=[pscustomobject]@{heartbeat_seen=[DateTime]::UtcNow;sampler_seen=[DateTime]::UtcNow;heartbeat_offset=[UInt64]0;sampler_offset=[UInt64]0;heartbeat_rows=[Int64]0;sampler_rows=[Int64]0;heartbeat_sequence=[UInt64]0;sampler_sequence=[UInt64]0;heartbeat_framer=[G130U1Utf8LineFramer]::new();sampler_framer=[G130U1Utf8LineFramer]::new()}
    while(-not(Test-G130U1TcpReady $port)){$server.Refresh();$watchdog.Refresh();$now=[DateTime]::UtcNow;$parentSample=Get-G130U1ParentSourceSample $parentSource $paths['watchdog.jsonl'] $paths['watchdog_sampler.jsonl'] $now $parentClock.Elapsed.TotalSeconds (-not$watchdog.HasExited);$decision=Test-G130U1ParentSupervisionSample $parentSample $constants.watchdog_heartbeat_stall_seconds $constants.wall_cap_seconds;if($decision.abort){$exitCode=21;$cause=$decision.cause;$snapshot=Get-G130U1ParentAbortSnapshot $paths['server.stdout.log'] $paths['server.stderr.log'] $server $null;$a=[pscustomobject][ordered]@{schema='g130_u1_watchdog_abort_v2';run_id=$runId;captured_utc=$now.ToString('o');gate=$decision.gate;cause=$decision.cause;detail='parent startup supervision';source='parent';snapshot=$snapshot;termination='pending_parent'};[void](Write-G130U1AbortAtomic $paths['watchdog_abort.json'] $a);throw$decision.cause};if($server.HasExited){$exitCode=21;$cause='SERVER_EXIT_BEFORE_READINESS';throw'owned server exited before readiness'};if(Test-Path -LiteralPath $paths['watchdog_abort.json']){$exitCode=21;$cause='WATCHDOG_ABORT';throw'watchdog abort during startup'};Start-Sleep -Milliseconds $constants.parent_poll_milliseconds}
    Write-G130U1Utf8 $paths['ready.marker'] ([DateTime]::UtcNow.ToString('o'));$lifecycle.readiness='progress-aware-ready'
    $workerManifest=[pscustomobject][ordered]@{schema='g130_u1_http_worker_manifest_v1';uri=$baseUri+'/v1/chat/completions';request_path=$paths['request.json'];raw_response_path=$paths['raw_response.sse'];timing_path=$paths['http_timing.jsonl'];result_path=$paths['request_result.json'];assistant_path=$paths['assistant_text.txt'];expected_request_sha256=$requestSha;http_timeout_seconds=$constants.http_worker_guard_seconds};Write-G130U1Json $paths['http_worker_manifest.json'] $workerManifest
    Write-G130U1Utf8 $paths['request.started'] ([DateTime]::UtcNow.ToString('o'));$lifecycle.request_started=$true;$worker=Start-G130U1PowerShellChild $MyInvocation.MyCommand.Path @('-HttpWorker','-WorkerManifestPath',$paths['http_worker_manifest.json']) $paths['http_worker.stdout.log'] $paths['http_worker.stderr.log'];[void]$worker.Handle;$lifecycle.http_worker_pid=[int]$worker.Id
    while($true){$server.Refresh();$watchdog.Refresh();$worker.Refresh();$now=[DateTime]::UtcNow
        $parentSample=Get-G130U1ParentSourceSample $parentSource $paths['watchdog.jsonl'] $paths['watchdog_sampler.jsonl'] $now $parentClock.Elapsed.TotalSeconds (-not$watchdog.HasExited)
        $decision=Test-G130U1ParentSupervisionSample $parentSample $constants.watchdog_heartbeat_stall_seconds $constants.wall_cap_seconds
        if($decision.abort){$exitCode=21;$cause=$decision.cause;$snapshot=Get-G130U1ParentAbortSnapshot $paths['server.stdout.log'] $paths['server.stderr.log'] $server $worker;$a=[pscustomobject][ordered]@{schema='g130_u1_watchdog_abort_v2';run_id=$runId;captured_utc=$now.ToString('o');gate=$decision.gate;cause=$decision.cause;detail='parent independent supervision';source='parent';snapshot=$snapshot;termination='pending_parent'};[void](Write-G130U1AbortAtomic $paths['watchdog_abort.json'] $a);throw$decision.cause}
        if(Test-Path -LiteralPath $paths['watchdog_abort.json']){$exitCode=21;$cause='WATCHDOG_ABORT';[void]$watchdog.WaitForExit($constants.watchdog_abort_wait_milliseconds);throw'watchdog requested abort'}
        if($worker.HasExited){$workerState=Get-G130U1WorkerCompletion $worker $paths['request_result.json'] $requestSha;$http=$workerState.result;if(-not$workerState.ok){$exitCode=22;$cause=$workerState.cause;$detail=$workerState.detail;throw$workerState.cause};$lifecycle.request_completed=$true}
        if($server.HasExited){
            if($null-eq$http-and$worker.WaitForExit($constants.server_exit_worker_grace_milliseconds)){$workerState=Get-G130U1WorkerCompletion $worker $paths['request_result.json'] $requestSha;$http=$workerState.result;if(-not$workerState.ok){$exitCode=22;$cause=$workerState.cause;$detail=$workerState.detail;throw$workerState.cause};$lifecycle.request_completed=$true}
            if($null-eq$http){[void]$watchdog.WaitForExit($constants.watchdog_abort_wait_milliseconds);if(Test-Path -LiteralPath $paths['watchdog_abort.json']){$exitCode=21;$cause='WATCHDOG_ABORT';throw'server exit classified by watchdog'};$exitCode=21;$cause='A5_SERVER_EXIT_BEFORE_HTTP_STATUS';throw'server exited before complete HTTP worker status'}
            break
        }
        Start-Sleep -Milliseconds $constants.parent_poll_milliseconds
    }
    $lifecycle.server_exit_code=[int]$server.ExitCode;if($server.ExitCode-ne0){$exitCode=21;$cause='SERVER_EXIT_NONZERO';throw"server exit $($server.ExitCode)"}
    Start-Sleep -Milliseconds $constants.parent_poll_milliseconds;Write-G130U1Utf8 $paths['monitor.complete'] ([DateTime]::UtcNow.ToString('o'));if(-not$watchdog.WaitForExit($constants.postrun_watchdog_wait_milliseconds)){$exitCode=24;$cause='WATCHDOG_CLEANUP_TIMEOUT';throw'watchdog did not finish post-run scan'};$lifecycle.watchdog_exit_code=[int]$watchdog.ExitCode;if($watchdog.ExitCode-ne0-or(Test-Path -LiteralPath $paths['watchdog_abort.json'])){$exitCode=21;$cause='WATCHDOG_ABORT';throw'watchdog rejected run'}
    try{$profile=Read-G130U1Profile $paths['server.stderr.log'] 64}catch{$exitCode=23;$cause='PROFILE_PARSER_FAILED';throw};Write-G130U1Json $paths['profile_summary.json'] $profile
    if($http.http_status-ne200-or[string]$http.finish_reason-cne'length'-or[int]$http.finish_count-ne1-or[int]$http.usage_count-ne1-or$http.done_received-ne$true-or[int]$http.done_count-ne1-or[int]$http.post_done_data_count-ne0-or[int]$http.usage_completion_tokens-ne64-or[string]$http.request_sha256-cne$requestSha){$exitCode=22;$cause='REQUEST_CONTRACT_MISMATCH';throw'request result contract mismatch'}
    $outcome='DIAGNOSTIC';$exitCode=0;$cause=$(if($profile.p2_authorized){'U1_DIAGNOSTIC_P2_AUTHORIZED'}else{'U1_DIAGNOSTIC_REPLAN_REQUIRED'});$detail="decision=$($profile.decision)"
}catch{
    if(-not$detail){$detail=$_.Exception.Message}
    if(Test-Path -LiteralPath $paths['watchdog_abort.json']){
        try{$abort=Get-Content -LiteralPath $paths['watchdog_abort.json'] -Raw|ConvertFrom-Json;$cause=[string]$abort.cause;if($cause-match'^A9_'){$outcome='CONTAMINATED'}else{$outcome='NEGATIVE'}}catch{}
    } elseif($server) {
        $snapshot=Get-G130U1ParentAbortSnapshot $paths['server.stdout.log'] $paths['server.stderr.log'] $server $worker
        $abort=[pscustomobject][ordered]@{schema='g130_u1_watchdog_abort_v2';run_id=$runId;captured_utc=[DateTime]::UtcNow.ToString('o');gate='PARENT';cause=$cause;detail=$detail;source='parent';snapshot=$snapshot;termination='pending_parent'}
        [void](Write-G130U1AbortAtomic $paths['watchdog_abort.json'] $abort)
    }
}
finally{
    if($envState){try{Exit-G130U1Environment $envState;$cleanup.environment_restored=$true}catch{$cleanup.cleanup_sync_ok=$false;$cleanup.error=$_.Exception.Message}}
    if($server){try{$server.Refresh();if(-not$server.HasExited){if(-not(Test-Path -LiteralPath $paths['watchdog_abort.json'])){$snapshot=Get-G130U1ParentAbortSnapshot $paths['server.stdout.log'] $paths['server.stderr.log'] $server $worker;$a=[pscustomobject][ordered]@{schema='g130_u1_watchdog_abort_v2';run_id=$runId;captured_utc=[DateTime]::UtcNow.ToString('o');gate='PARENT';cause=$cause;detail=$detail;source='parent';snapshot=$snapshot;termination='pending_parent'};[void](Write-G130U1AbortAtomic $paths['watchdog_abort.json'] $a)};$cleanup.attempted=$true;$stop=Stop-G130U1OwnedProcessBounded $server $serverStart $exePath $baseUri $shutdownToken;$cleanup.shutdown=$stop;$cleanup.stopped=[bool]($stop.graceful_verified-or$stop.spontaneous_exit-or$stop.forced_kill_succeeded);$cleanup.forced_kill=[bool]$stop.forced_kill_attempted;$cleanup.error=[string]$stop.error;$lifecycle.forced_kill=$cleanup.forced_kill;if($cleanup.forced_kill){$outcome='NEGATIVE';$exitCode=24;if($cause-like'U1_DIAGNOSTIC_*'){$cause='FORCED_KILL'}};if(-not$cleanup.stopped){$cleanup.cleanup_sync_ok=$false;$outcome='NEGATIVE';$exitCode=24;$cause='CLEANUP_FAILED'}}else{$cleanup.stopped=$true}}catch{$cleanup.cleanup_sync_ok=$false;$cleanup.error=$_.Exception.Message;$outcome='NEGATIVE';$exitCode=24;$cause='CLEANUP_FAILED'}}
    if($worker){try{$worker.Refresh();if(-not$worker.HasExited-and-not$worker.WaitForExit($constants.child_cleanup_wait_milliseconds)){$cleanup.child_forced_kill=$true;$worker.Kill();if(-not$worker.WaitForExit($constants.child_cleanup_wait_milliseconds)){throw'HTTP worker did not exit after parent Kill'}};$lifecycle.http_worker_exit_code=$(if($worker.HasExited){[int]$worker.ExitCode}else{$null})}catch{$cleanup.worker_cleanup_ok=$false;$cleanup.cleanup_sync_ok=$false;$cleanup.error=($cleanup.error+'; HTTP worker cleanup: '+$_.Exception.Message).Trim('; ');$outcome='NEGATIVE';$exitCode=24;$cause='CHILD_CLEANUP_FAILED'}}
    if($watchdog){try{$watchdog.Refresh();if(-not$watchdog.HasExited){$cleanup.child_forced_kill=$true;$watchdog.Kill();if(-not$watchdog.WaitForExit($constants.child_cleanup_wait_milliseconds)){throw'watchdog did not exit after parent Kill'}};$lifecycle.watchdog_exit_code=$(if($watchdog.HasExited){[int]$watchdog.ExitCode}else{$null})}catch{$cleanup.watchdog_cleanup_ok=$false;$cleanup.cleanup_sync_ok=$false;$cleanup.error=($cleanup.error+'; watchdog cleanup: '+$_.Exception.Message).Trim('; ');$outcome='NEGATIVE';$exitCode=24;$cause='CHILD_CLEANUP_FAILED'}}
    if(Test-Path -LiteralPath $paths['watchdog_abort.json']){try{$abort=Get-Content -LiteralPath $paths['watchdog_abort.json'] -Raw|ConvertFrom-Json}catch{}}
    try{$receiptInfo=Complete-G130U1Evidence $runId $runDirectory $ledgerPath $outcome $exitCode $cause $detail $config $prereg $preflight $profile $http ([pscustomobject]$lifecycle) $cleanup $abort}catch{$receiptInfo=Write-G130U1EmergencyReceipt $receiptPath $runId $ledgerPath 'EVIDENCE_FINALIZATION_FAILED' $_.Exception.Message}
}
$outcome=[string]$receiptInfo.outcome;$cause=[string]$receiptInfo.cause;$exitCode=[int]$receiptInfo.exit_code;Write-Output('G130_U1_RECEIPT='+$receiptInfo.path);Write-Output('G130_U1_RECEIPT_SHA256='+$receiptInfo.sha256);Write-Output('G130_U1_LEDGER_ROW='+$receiptInfo.ledger_row);Write-Output('G130_U1_OUTCOME='+$outcome);exit $exitCode
