$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'process-utils.ps1')
$runtime=Get-Content -LiteralPath (Join-Path $root 'config\runtime.json') -Raw|ConvertFrom-Json
$secureKey=(Get-Content -LiteralPath (Join-Path $root 'credentials\control-plane-key.dpapi') -Raw).Trim()|ConvertTo-SecureString
$keyText=([Net.NetworkCredential]::new('', $secureKey)).Password
$oldKey=$env:CONTROL_PLANE_API_KEY
$oldShim=$env:MCP_STDIO_SEND_INITIALIZED_NOTIFICATION
$oldProxy=$env:CONTROL_PLANE_HTTP_PROXY
try{
 $env:CONTROL_PLANE_API_KEY=$keyText
 $env:MCP_STDIO_SEND_INITIALIZED_NOTIFICATION='true'
 $proxy=Resolve-ControlPlaneProxy $runtime
 $env:CONTROL_PLANE_HTTP_PROXY=$proxy.Value
 $command='"'+$runtime.node.Replace('\','/')+'" "'+(Join-Path $root 'bridge\launch-gateway.mjs').Replace('\','/')+'" "'+(Join-Path $root 'config\gateway.json').Replace('\','/')+'"'
 $profileDir=Join-Path $root 'state\profiles'
 $arguments=@('runtimes','connect','--alias',$runtime.alias,'--tunnel-id',$runtime.tunnelId,'--profile',$runtime.alias,'--profile-dir',$profileDir,'--mcp-command',$command,'--runtime-api-key','env:CONTROL_PLANE_API_KEY','--json')
 $result=Invoke-HiddenNative $runtime.client $arguments $root -PreserveHiddenConsole
 $code=$result.ExitCode
 $safe=$result.Output.Replace($keyText,'[REDACTED]')
 if($code-ne0){$safe|Set-Content -LiteralPath (Join-Path $root 'logs\last-startup-error.json') -Encoding UTF8;throw 'Private runtime startup failed; see protected startup log.'}
 $state=$safe|ConvertFrom-Json
 if(-not($state.process_running-and$state.healthy-and$state.ready)){throw 'Private runtime is not ready.'}
 Write-Output ('Connected: '+$runtime.alias+'; proxy source: '+$proxy.Source)
}finally{
 $env:CONTROL_PLANE_API_KEY=$oldKey
 $env:MCP_STDIO_SEND_INITIALIZED_NOTIFICATION=$oldShim
 $env:CONTROL_PLANE_HTTP_PROXY=$oldProxy
 $keyText=$null
}
