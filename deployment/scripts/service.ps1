$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$runtime=Get-Content -LiteralPath (Join-Path $root 'config\runtime.json') -Raw|ConvertFrom-Json
$healthFile=Join-Path $env:USERPROFILE ('.local\state\tunnel-client\health\'+$runtime.alias+'.url')
$log=Join-Path $root 'logs\supervisor.log'
function Write-SupervisorEvent([string]$Message){
 try{
  if((Test-Path -LiteralPath $log) -and (Get-Item -LiteralPath $log).Length -gt 1MB){
   [IO.File]::WriteAllText(($log+'.previous'),[IO.File]::ReadAllText($log))
   [IO.File]::WriteAllText($log,'')
  }
  ('['+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')+'] '+$Message)|Add-Content -LiteralPath $log -Encoding UTF8
 }catch{} # A logging failure must not stop the recovery loop.
}
$mutex=[Threading.Mutex]::new($false,('Local\CodexProPrivateTunnel-'+[Security.Principal.WindowsIdentity]::GetCurrent().User.Value))
$locked=$false
try{
 try{$locked=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$locked=$true}
 if(-not$locked){exit 0}
 $failures=0
 while($true){
  $ready=$false
  if(Test-Path -LiteralPath $healthFile){
   $base=(Get-Content -LiteralPath $healthFile -Raw).Trim()
   if($base-match'^http://127\.0\.0\.1:\d+$'){
    try{$response=Invoke-WebRequest -UseBasicParsing ($base+'/readyz') -TimeoutSec 3;$ready=$response.StatusCode-eq200}catch{}
   }
  }
  if($ready){$failures=0}else{
   $failures++
   try{
    if($failures-ge3){$null=& $runtime.client runtimes stop $runtime.alias --json 2>&1;$failures=0}
    $result=& (Join-Path $PSScriptRoot 'connect.ps1')
    Write-SupervisorEvent 'Connected; runtime ready.'
   }catch{
    Write-SupervisorEvent 'Not ready; retry in 15 seconds.'
   }
  }
  Start-Sleep -Seconds 15
 }
}finally{if($locked){$mutex.ReleaseMutex()};$mutex.Dispose()}
