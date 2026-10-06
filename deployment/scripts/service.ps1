$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'process-utils.ps1')
$runtime=Get-Content -LiteralPath (Join-Path $root 'config\runtime.json') -Raw|ConvertFrom-Json
$healthFile=Join-Path $env:USERPROFILE ('.local\state\tunnel-client\health\'+$runtime.alias+'.url')
$log=Join-Path $root 'logs\supervisor.log'
function Write-SupervisorEvent([string]$Message){
 try{
  if((Test-Path -LiteralPath $log) -and (Get-Item -LiteralPath $log).Length -gt 1MB){[IO.File]::WriteAllText(($log+'.previous'),[IO.File]::ReadAllText($log));[IO.File]::WriteAllText($log,'')}
  ('['+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')+'] '+$Message)|Add-Content -LiteralPath $log -Encoding UTF8
 }catch{}
}
$mutex=[Threading.Mutex]::new($false,('Local\CodexProPrivateTunnel-'+[Security.Principal.WindowsIdentity]::GetCurrent().User.Value))
$locked=$false;$lastRecovery=[DateTimeOffset]::MinValue;$previous='';$failures=0
$consoleVisible=$null
try{
 Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class CodexProOwnConsole {
 [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr window);
}
'@
 $ownConsole=[CodexProOwnConsole]::GetConsoleWindow()
 $consoleVisible=$ownConsole -ne [IntPtr]::Zero -and [CodexProOwnConsole]::IsWindowVisible($ownConsole)
}catch{}
try{
 try{$locked=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$locked=$true}
 if(-not $locked){exit 0}
 while($true){
  $reason='endpoint-unreachable';$status=$null;$starting=$false
  if(Test-Path -LiteralPath $healthFile){
   $base=(Get-Content -LiteralPath $healthFile -Raw).Trim()
   if($base -match '^http://127\.0\.0\.1:\d+$'){
    try{
     $status=Invoke-RestMethod ($base+'/api/status') -TimeoutSec 3
     $ready=$false
     try{$response=Invoke-WebRequest -UseBasicParsing ($base+'/readyz') -TimeoutSec 3;$ready=$response.StatusCode -eq 200}catch{}
     $metrics=(Invoke-WebRequest -UseBasicParsing ($base+'/metrics') -TimeoutSec 3).Content
     $poll=Get-PollFreshness $metrics ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) $status.uptime_seconds
     $starting=$poll.Starting
     $reason=if($ready -and $poll.Fresh){'online'}elseif($starting){'starting-first-poll'}elseif(-not $ready){'runtime-not-ready'}else{'poll-stale'}
    }catch{}
   }
  }
  if($reason -ne $previous){Write-SupervisorEvent ('Health: '+$reason);$previous=$reason}
  try{[pscustomobject]@{state=$reason;checkedAt=[DateTimeOffset]::UtcNow.ToString('o');supervisorConsoleVisible=$consoleVisible}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $root 'logs\service-health.json') -Encoding UTF8}catch{}
  if($reason -eq 'online' -or $starting){$failures=0}else{
   $failures++
   $cooldown=([DateTimeOffset]::UtcNow-$lastRecovery).TotalSeconds -ge 180
   if($cooldown -and ($null -eq $status -or $failures -ge 3)){
    $busy=$null -ne $status -and (Test-GatewayBusy $root $status)
    if($busy){Write-SupervisorEvent 'Recovery deferred: active or uncertain MCP operation.'}else{
     $lastRecovery=[DateTimeOffset]::UtcNow
     try{
      if($null -ne $status -or $failures -ge 3){$stopped=Invoke-HiddenNative $runtime.client @('runtimes','stop',$runtime.alias,'--json') $root}
      $result=& (Join-Path $PSScriptRoot 'connect.ps1')
      Write-SupervisorEvent 'Background recovery completed.';$failures=0
     }catch{Write-SupervisorEvent 'Background recovery failed; waiting before another attempt.'}
    }
   }
  }
  Start-Sleep -Seconds 15
 }
}finally{if($locked){$mutex.ReleaseMutex()};$mutex.Dispose()}
