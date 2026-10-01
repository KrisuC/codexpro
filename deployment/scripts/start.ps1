$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$runtime=Get-Content -LiteralPath (Join-Path $root 'config\runtime.json') -Raw|ConvertFrom-Json
$task=Get-ScheduledTask -TaskName $runtime.taskName
if($task.State-ne'Running'){Start-ScheduledTask -TaskName $runtime.taskName}
$healthFile=Join-Path $env:USERPROFILE ('.local\state\tunnel-client\health\'+$runtime.alias+'.url')
for($attempt=0;$attempt-lt40;$attempt++){
 if((Get-ScheduledTask -TaskName $runtime.taskName).State-eq'Running' -and (Test-Path -LiteralPath $healthFile)){
  $base=(Get-Content -LiteralPath $healthFile -Raw).Trim()
  if($base-match'^http://127\.0\.0\.1:\d+$'){
   try{$response=Invoke-WebRequest -UseBasicParsing ($base+'/readyz') -TimeoutSec 2;if($response.StatusCode-eq200){Write-Output 'CodexPro Local is ready. This window can be closed.';exit 0}}catch{}
  }
 }
 Start-Sleep -Seconds 1
}
Write-Output 'Background service is retrying. See its protected logs for diagnostics.'
exit 1
