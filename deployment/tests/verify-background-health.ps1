param([Parameter(Mandatory=$true)][string]$Helpers)
$ErrorActionPreference='Stop'
. $Helpers
$fresh=Get-PollFreshness "commands_poll_last_successful_timestamp_seconds{scope=`"test`"} 1000`n" 1050 200
if(-not $fresh.Fresh){throw 'Fresh successful polling was not recognized'}
$stale=Get-PollFreshness "commands_poll_last_successful_timestamp_seconds{} 1000`n" 1250 200
if($stale.Fresh){throw 'A stale tunnel was falsely reported online'}
$starting=Get-PollFreshness '' 1250 30
if(-not $starting.Starting){throw 'First-poll startup grace missing'}
$directory=Join-Path $env:TEMP ('codexpro-health-'+[Guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path (Join-Path $directory 'logs')
$log=Join-Path $directory 'logs\gateway-12345.jsonl'
$status=[pscustomobject]@{channels=@([pscustomobject]@{name='main';details=@([pscustomobject]@{key='pid';value='12345'})})}
try{
 [IO.File]::WriteAllText($log,"{`"event`":`"call_start`",`"id`":`"one`"}`n")
 if(-not(Test-GatewayBusy $directory $status)){throw 'Recovery would interrupt an active call'}
 [IO.File]::AppendAllText($log,"{`"event`":`"call_end`",`"requestId`":`"one`"}`n")
 if(Test-GatewayBusy $directory $status){throw 'Completed work was incorrectly left busy'}
 $entry=@{event='call_error';requestId='one';retry=$false;kind='timeout';time=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Compress
 [IO.File]::AppendAllText($log,$entry+"`n")
 if(-not(Test-GatewayBusy $directory $status)){throw 'An unknown timed-out operation could be interrupted'}
 $node=Join-Path (Split-Path (Split-Path $Helpers -Parent) -Parent) 'bin\node.exe'
 if(-not(Test-Path -LiteralPath $node)){$node='C:\CodexPro\runtime\bin\node.exe'}
 $result=Invoke-HiddenNative $node @('--version') $directory
 if($result.ExitCode -ne 0 -or $result.Output -notmatch '^v\d+'){throw 'Hidden process invocation failed'}
 Write-Output 'Fresh/stale polling, active-call protection and hidden process execution verified.'
}finally{Remove-Item -LiteralPath $log;Remove-Item -LiteralPath (Join-Path $directory 'logs');Remove-Item -LiteralPath $directory}
