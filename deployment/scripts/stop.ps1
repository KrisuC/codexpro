$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'process-utils.ps1')
$runtime=Get-Content -LiteralPath (Join-Path $root 'config\runtime.json') -Raw|ConvertFrom-Json
Stop-ScheduledTask -TaskName $runtime.taskName
# The GUI task host waits for PowerShell. Ensure its own supervisor is stopped
# even on Windows versions that stop only the root scheduled-task process.
$servicePath=Join-Path $PSScriptRoot 'service.ps1'
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'"|Where-Object{
 $_.ProcessId -ne $PID -and $_.CommandLine -and $_.CommandLine.Contains($servicePath) -and $_.CommandLine -match '(?i)-File\s'
}|ForEach-Object{Stop-Process -Id $_.ProcessId -ErrorAction SilentlyContinue}
$result=Invoke-HiddenNative $runtime.client @('runtimes','stop',$runtime.alias,'--json') $root
if($result.ExitCode -ne 0){throw 'Managed runtime stop failed.'}
Write-Output 'CodexPro Local supervisor and runtime stopped.'
