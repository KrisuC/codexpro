function Quote-NativeArgument([string]$Value){
 if($Value.Length-eq0){return '""'}
 if($Value-notmatch'[\s"]'){return $Value}
 $escaped=[regex]::Replace($Value,'(\\*)"','$1$1\"')
 $escaped=[regex]::Replace($escaped,'(\\+)$','$1$1')
 return '"'+$escaped+'"'
}
function Invoke-HiddenNative([string]$Executable,[string[]]$Arguments,[string]$WorkingDirectory,[int]$TimeoutMs=45000,[switch]$PreserveHiddenConsole){
 $info=[Diagnostics.ProcessStartInfo]::new()
 $info.FileName=$Executable
 $info.Arguments=($Arguments|ForEach-Object{Quote-NativeArgument $_})-join' '
 $info.WorkingDirectory=$WorkingDirectory
 $info.UseShellExecute=$false
 $info.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
 # Managed tunnel-client spawns its daemon without Windows creation flags.
 # Keep the supervisor's hidden console available for that grandchild to inherit.
 $info.CreateNoWindow=-not $PreserveHiddenConsole
 $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
 $process=[Diagnostics.Process]::new();$process.StartInfo=$info
 try{
  $null=$process.Start()
  $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
  if(-not $process.WaitForExit($TimeoutMs)){$process.Kill();throw 'Background management command timed out.'}
  return [pscustomobject]@{ExitCode=$process.ExitCode;Output=$stdout.GetAwaiter().GetResult()+$stderr.GetAwaiter().GetResult()}
 }finally{$process.Dispose()}
}
function Resolve-ControlPlaneProxy($Runtime){
 if($Runtime.controlPlaneProxy){return [pscustomobject]@{Value=[string]$Runtime.controlPlaneProxy;Source='configured'}}
 if($env:CONTROL_PLANE_HTTP_PROXY){return [pscustomobject]@{Value=$env:CONTROL_PLANE_HTTP_PROXY;Source='environment'}}
 try{
  $settings=Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
  if($settings.ProxyEnable -eq 1 -and $settings.ProxyServer){
   $parts=[string]$settings.ProxyServer -split ';'
   $chosen=($parts|Where-Object{$_ -match '^https='}|Select-Object -First 1)
   if(-not $chosen){$chosen=($parts|Where-Object{$_ -match '^http='}|Select-Object -First 1)}
   if(-not $chosen){$chosen=($parts|Where-Object{$_ -notmatch '='}|Select-Object -First 1)}
   if($chosen){
    $value=($chosen -replace '^https?=','').Trim()
    if($value -notmatch '^https?://'){$value='http://'+$value}
    $uri=[Uri]$value
    if($uri.IsAbsoluteUri -and $uri.Scheme -in @('http','https')){return [pscustomobject]@{Value=$value;Source='windows-system'}}
   }
  }
 }catch{}
 return [pscustomobject]@{Value='';Source='direct'}
}
function Get-PollFreshness([string]$Metrics,[double]$NowEpoch,[double]$Uptime){
 $match=[regex]::Match($Metrics,'(?m)^commands_poll_last_successful_timestamp_seconds(?:\{[^\r\n]*\})?\s+([0-9.eE+\-]+)\s*$')
 if(-not $match.Success -or [double]$match.Groups[1].Value -le 0){return [pscustomobject]@{Fresh=$false;AgeSeconds=$null;Starting=$Uptime -lt 120}}
 $age=[Math]::Max(0,$NowEpoch-[double]::Parse($match.Groups[1].Value,[Globalization.CultureInfo]::InvariantCulture))
 return [pscustomobject]@{Fresh=$age -le 120;AgeSeconds=[Math]::Round($age);Starting=$false}
}
function Test-GatewayBusy([string]$Root,$Status){
 try{
  $channel=@($Status.channels|Where-Object{$_.name -eq 'main'})[0]
  $pidText=($channel.details|Where-Object{$_.key -eq 'pid'}|Select-Object -First 1).value
  if($pidText -notmatch '^\d+$'){return $true}
  $log=Join-Path $Root ('logs\gateway-'+$pidText+'.jsonl')
  if(-not(Test-Path -LiteralPath $log)){return $true}
  $active=@{};$uncertain=$false
  foreach($file in @(($log+'.previous'),$log)){
   if(-not(Test-Path -LiteralPath $file)){continue}
   foreach($line in Get-Content -LiteralPath $file -ErrorAction Stop){
    $entry=$line|ConvertFrom-Json
    if($entry.event -eq 'call_start'){$active[$entry.id]=$true}
    if($entry.event -eq 'call_end'){$active.Remove($entry.requestId)}
    if($entry.event -eq 'call_error' -and -not $entry.retry){
     $active.Remove($entry.requestId)
     if($entry.kind -in @('timeout','cancelled') -and ([DateTimeOffset]::UtcNow-[DateTimeOffset]::Parse($entry.time)).TotalSeconds -lt 930){$uncertain=$true}
    }
   }
  }
  return $active.Count -gt 0 -or $uncertain
 }catch{return $true}
}
