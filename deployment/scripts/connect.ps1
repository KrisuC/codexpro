$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$runtime=Get-Content -LiteralPath (Join-Path $root 'config\runtime.json') -Raw|ConvertFrom-Json
$secureKey=(Get-Content -LiteralPath (Join-Path $root 'credentials\control-plane-key.dpapi') -Raw).Trim()|ConvertTo-SecureString
$keyText=([Net.NetworkCredential]::new('', $secureKey)).Password
$oldKey=$env:CONTROL_PLANE_API_KEY
$oldShim=$env:MCP_STDIO_SEND_INITIALIZED_NOTIFICATION
function Quote-NativeArgument([string]$Value){
 if($Value.Length-eq0){return '""'}
 if($Value-notmatch'[\s"]'){return $Value}
 $escaped=[regex]::Replace($Value,'(\\*)"','$1$1\"')
 $escaped=[regex]::Replace($escaped,'(\\+)$','$1$1')
 return '"'+$escaped+'"'
}
try{
 $env:CONTROL_PLANE_API_KEY=$keyText
 $env:MCP_STDIO_SEND_INITIALIZED_NOTIFICATION='true'
 $command='"'+$runtime.node.Replace('\','/')+'" "'+(Join-Path $root 'bridge\launch-gateway.mjs').Replace('\','/')+'" "'+(Join-Path $root 'config\gateway.json').Replace('\','/')+'"'
 $profileDir=Join-Path $root 'state\profiles'
 $arguments=@('runtimes','connect','--alias',$runtime.alias,'--tunnel-id',$runtime.tunnelId,'--profile',$runtime.alias,'--profile-dir',$profileDir,'--mcp-command',$command,'--runtime-api-key','env:CONTROL_PLANE_API_KEY','--json')
 $info=[Diagnostics.ProcessStartInfo]::new()
 $info.FileName=$runtime.client
 $info.Arguments=($arguments|ForEach-Object {Quote-NativeArgument $_})-join' '
 $info.WorkingDirectory=$root
 $info.UseShellExecute=$false;$info.CreateNoWindow=$true
 $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
 $process=[Diagnostics.Process]::new();$process.StartInfo=$info
 $null=$process.Start()
 $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
 if(-not$process.WaitForExit(45000)){$process.Kill();throw 'Private runtime startup timed out.'}
 $code=$process.ExitCode
 $safe=($stdout.GetAwaiter().GetResult()+$stderr.GetAwaiter().GetResult()).Replace($keyText,'[REDACTED]')
 $process.Dispose()
 if($code-ne0){$safe|Set-Content -LiteralPath (Join-Path $root 'logs\last-startup-error.json') -Encoding UTF8;throw 'Private runtime startup failed; see protected startup log.'}
 $state=$safe|ConvertFrom-Json
 if(-not($state.process_running-and$state.healthy-and$state.ready)){throw 'Private runtime is not ready.'}
 Write-Output ('Connected: '+$runtime.alias)
}finally{
 $env:CONTROL_PLANE_API_KEY=$oldKey
 $env:MCP_STDIO_SEND_INITIALIZED_NOTIFICATION=$oldShim
 $keyText=$null
}
