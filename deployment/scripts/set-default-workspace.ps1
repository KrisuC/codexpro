param([string]$Root)
$ErrorActionPreference='Stop'
$privateRoot=Split-Path $PSScriptRoot -Parent
$configPath=Join-Path $privateRoot 'config\gateway.json'
$config=Get-Content -LiteralPath $configPath -Raw|ConvertFrom-Json
$allowed=@($config.allowedRoots)
$currentArgs=@($config.backends.codexpro.args)
$rootIndex=[Array]::IndexOf($currentArgs,'--root')
$currentRoot=if($rootIndex -ge 0){$currentArgs[$rootIndex+1]}else{$config.backends.codexpro.cwd}
if([string]::IsNullOrWhiteSpace($Root)){
 Write-Host ('Current default: '+$currentRoot)
 for($index=0;$index -lt $allowed.Count;$index++){Write-Host (('{0}. {1}' -f ($index+1),$allowed[$index]))}
 Write-Host '0. Cancel'
 $choice=Read-Host 'Choose the default project number (the service will restart once)'
 $number=0
 if(-not [int]::TryParse($choice,[ref]$number) -or $number -lt 0 -or $number -gt $allowed.Count){throw 'Invalid project number.'}
 if($number -eq 0){exit 0}
 $Root=$allowed[$number-1]
}
$requested=[IO.Path]::GetFullPath($Root).TrimEnd('\','/')
$selected=@($allowed|Where-Object{[IO.Path]::GetFullPath($_).TrimEnd('\','/') -ieq $requested})
if($selected.Count -ne 1 -or -not(Test-Path -LiteralPath $selected[0] -PathType Container)){throw 'Choose an existing project from the approved list. This command does not grant new directory access.'}
$Root=$selected[0]
if($Root -ieq $currentRoot){Write-Output ('Default project is already '+$Root);exit 0}
$nextArgs=[Collections.Generic.List[string]]::new()
for($index=0;$index -lt $currentArgs.Count;$index++){
 if($currentArgs[$index] -in @('--root','--allow-root')){$index++;continue}
 $nextArgs.Add([string]$currentArgs[$index])
}
$nextArgs.Add('--root');$nextArgs.Add($Root)
foreach($project in $allowed){if($project -ine $Root){$nextArgs.Add('--allow-root');$nextArgs.Add($project)}}
$config.backends.codexpro.args=$nextArgs.ToArray()
$config.backends.codexpro.cwd=$Root
$rollbackDir=Join-Path $privateRoot 'rollback'
$null=New-Item -ItemType Directory -Path $rollbackDir -Force
$backup=Join-Path $rollbackDir ('workspace-default-'+(Get-Date -Format 'yyyyMMdd-HHmmssfff')+'.json')
Copy-Item -LiteralPath $configPath -Destination $backup
$temporary=$configPath+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
try{
 [IO.File]::WriteAllText($temporary,($config|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
 # A concrete backup path avoids Windows PowerShell 5.1 coercing null to "".
 [IO.File]::Replace($temporary,$configPath,$backup)
 & (Join-Path $PSScriptRoot 'stop.ps1')
 & (Join-Path $PSScriptRoot 'start.ps1')
 if($LASTEXITCODE -ne 0){throw 'Updated runtime did not become ready.'}
 Write-Output ('Default project: '+$Root)
 Write-Output 'Existing chats must call open_workspace for this project once; old workspace IDs still identify their original projects.'
}catch{
 Copy-Item -LiteralPath $backup -Destination $configPath
 try{& (Join-Path $PSScriptRoot 'stop.ps1');& (Join-Path $PSScriptRoot 'start.ps1')}catch{}
 throw 'Switch failed. The previous configuration was restored; check service readiness.'
}finally{if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary}}
