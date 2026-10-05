param(
 [ValidateSet('Menu','List','Add','Remove')][string]$Action='Menu',
 [string]$Root,
 [string]$DefaultRoot
)
$ErrorActionPreference='Stop'
$runtimeRoot=Split-Path $PSScriptRoot -Parent
$configPath=Join-Path $runtimeRoot 'config\gateway.json'
$node=Join-Path $runtimeRoot 'bin\node.exe'
function Read-Configuration{Get-Content -LiteralPath $configPath -Raw|ConvertFrom-Json}
function Get-Default($Config){
 $arguments=@($Config.backends.codexpro.args)
 $index=[Array]::IndexOf($arguments,'--root')
 if($index -lt 0){throw '配置缺少默认项目，请检查服务配置。'}
 return [string]$arguments[$index+1]
}
function Normalize-Root([string]$Value){
 $Value=$Value.Trim().Trim('"')
 if(-not [IO.Path]::IsPathRooted($Value) -or -not(Test-Path -LiteralPath $Value -PathType Container)){throw '请输入已存在的文件夹绝对路径。'}
 $resolved=& $node -e "console.log(require('node:fs').realpathSync.native(process.argv[1]))" $Value
 if($LASTEXITCODE -ne 0){throw '无法解析这个目录。'}
 return ([string]$resolved).Trim()
}
function Show-Directories($Config){
 $current=Get-Default $Config
 Write-Host "`nCodexPro 可访问目录：" -ForegroundColor Cyan
 $items=@($Config.allowedRoots)
 for($i=0;$i -lt $items.Count;$i++){
  $mark=if($items[$i] -ieq $current){'  [默认项目]'}else{''}
  Write-Host ('{0}. {1}{2}' -f ($i+1),$items[$i],$mark)
 }
 Write-Host '此列表约束项目文件工具；完整 Shell 和桌面工具仍按 Windows 用户权限运行。'
}
function Save-DirectoryChange([string]$Operation,[string]$Directory,[string]$Replacement){
 $configuration=Read-Configuration
 $items=@($configuration.allowedRoots)
 $current=Get-Default $configuration
 if($Operation -eq 'Add'){
  $Directory=Normalize-Root $Directory
  if($Directory.TrimEnd('\','/') -ieq [IO.Path]::GetPathRoot($Directory).TrimEnd('\','/')){throw '请添加具体项目目录，不接受整个磁盘或网络共享的根目录。'}
  if($items -icontains $Directory){Write-Host '这个目录已经在列表里，无需修改。';return}
  $items+=@($Directory)
 }else{
  $full=[IO.Path]::GetFullPath($Directory.Trim().Trim('"'))
  $matched=@($items|Where-Object{$_ -ieq $full -or $_.TrimEnd('\','/') -ieq $full.TrimEnd('\','/')})
  if($matched.Count -ne 1){throw '这个目录不在当前授权列表中。'}
  $Directory=$matched[0]
  if($items.Count -le 1){throw '必须至少保留一个项目目录；请先添加另一个目录。'}
  $items=@($items|Where-Object{$_ -ine $Directory})
  if($current -ieq $Directory){
   if([string]::IsNullOrWhiteSpace($Replacement)){
    Write-Host '移除的是默认项目，请选择新的默认项目：'
    for($i=0;$i -lt $items.Count;$i++){Write-Host ('{0}. {1}' -f ($i+1),$items[$i])}
    $choice=Read-Host '输入编号（0 取消）'
    $number=0
    if(-not [int]::TryParse($choice,[ref]$number) -or $number -lt 0 -or $number -gt $items.Count){throw '项目编号无效。'}
    if($number -eq 0){Write-Host '已取消。';return}
    $Replacement=$items[$number-1]
   }
   $replacementFull=[IO.Path]::GetFullPath($Replacement)
   $valid=@($items|Where-Object{$_ -ieq $replacementFull -or $_.TrimEnd('\','/') -ieq $replacementFull.TrimEnd('\','/')})
   if($valid.Count -ne 1 -or -not(Test-Path -LiteralPath $valid[0] -PathType Container)){throw '新的默认项目必须是剩余列表中的现有目录。'}
   $current=$valid[0]
  }
 }
 $arguments=@($configuration.backends.codexpro.args)
 $next=[Collections.Generic.List[string]]::new()
 for($i=0;$i -lt $arguments.Count;$i++){
  if($arguments[$i] -in @('--root','--allow-root')){$i++;continue}
  $next.Add([string]$arguments[$i])
 }
 $next.Add('--root');$next.Add($current)
 foreach($item in $items){if($item -ine $current){$next.Add('--allow-root');$next.Add([string]$item)}}
 $configuration.allowedRoots=@($items)
 $configuration.backends.codexpro.args=$next.ToArray()
 $configuration.backends.codexpro.cwd=$current
 $rollback=Join-Path $runtimeRoot 'rollback'
 $null=New-Item -ItemType Directory -Path $rollback -Force
 $backup=Join-Path $rollback ('allowed-directories-'+(Get-Date -Format 'yyyyMMdd-HHmmssfff')+'.json')
 Copy-Item -LiteralPath $configPath -Destination $backup
 $temporary=$configPath+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
 try{
  [IO.File]::WriteAllText($temporary,($configuration|ConvertTo-Json -Depth 30),[Text.UTF8Encoding]::new($false))
  [IO.File]::Replace($temporary,$configPath,$backup)
  Write-Host '正在重启 CodexPro，使目录权限生效……'
  & (Join-Path $PSScriptRoot 'stop.ps1')
  & (Join-Path $PSScriptRoot 'start.ps1')
  if($LASTEXITCODE -ne 0){throw '服务启动验证失败。'}
  Write-Host ('已{0}：{1}' -f $(if($Operation -eq 'Add'){'添加'}else{'移除'}),$Directory) -ForegroundColor Green
  Show-Directories $configuration
 }catch{
  Copy-Item -LiteralPath $backup -Destination $configPath
  try{& (Join-Path $PSScriptRoot 'stop.ps1');& (Join-Path $PSScriptRoot 'start.ps1')}catch{}
  throw '保存或重启失败，已恢复修改前的配置。'
 }finally{if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary}}
}
if($Action -eq 'List'){Show-Directories (Read-Configuration);exit 0}
if($Action -ne 'Menu'){
 if([string]::IsNullOrWhiteSpace($Root)){throw '需要提供 -Root 目录参数。'}
 Save-DirectoryChange $Action $Root $DefaultRoot
 exit 0
}
while($true){
 $configuration=Read-Configuration
 Show-Directories $configuration
 Write-Host "`n1. 添加可访问目录`n2. 移除可访问目录`n0. 退出"
 $choice=Read-Host '请选择'
 if($choice -eq '0'){break}
 try{
  if($choice -eq '1'){
   $value=Read-Host '粘贴要添加的文件夹完整路径（空白取消）'
   if(-not [string]::IsNullOrWhiteSpace($value)){Save-DirectoryChange 'Add' $value ''}
  }elseif($choice -eq '2'){
   $number=0;$value=Read-Host '输入要移除的目录编号（0 取消）'
   $items=@($configuration.allowedRoots)
   if(-not [int]::TryParse($value,[ref]$number) -or $number -lt 0 -or $number -gt $items.Count){throw '目录编号无效。'}
   if($number -gt 0){Save-DirectoryChange 'Remove' $items[$number-1] ''}
  }else{Write-Host '请选择 0、1 或 2。'}
 }catch{Write-Host $_.Exception.Message -ForegroundColor Red}
}
