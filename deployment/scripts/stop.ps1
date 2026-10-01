$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$runtime=Get-Content -LiteralPath (Join-Path $root 'config\runtime.json') -Raw|ConvertFrom-Json
Stop-ScheduledTask -TaskName $runtime.taskName
$null=& $runtime.client runtimes stop $runtime.alias --json 2>&1
if($LASTEXITCODE-ne0){throw 'Managed runtime stop failed.'}
Write-Output 'CodexPro Local supervisor and runtime stopped.'
