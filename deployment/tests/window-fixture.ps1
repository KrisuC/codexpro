param([Parameter(Mandatory=$true)][string]$StateFile,[string]$Title='CodexPro MCP Acceptance Test',[string]$InitialText='',[ValidateRange(0,30000)][int]$AutoCloseMilliseconds=0)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class FixtureNative {
 [StructLayout(LayoutKind.Sequential)] public struct RECT {public int Left,Top,Right,Bottom;}
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd,out RECT rect);
 [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr context);
}
'@
$null=[FixtureNative]::SetProcessDpiAwarenessContext([IntPtr](-4))
$form=[Windows.Forms.Form]::new()
$form.Text=$Title
$form.Size=[Drawing.Size]::new(640,380)
$form.StartPosition='Manual';$form.Location=[Drawing.Point]::new(160,160)
$form.AutoScaleMode='None';$form.TopMost=$true
$label=[Windows.Forms.Label]::new();$label.Text='Dedicated synthetic MCP test window';$label.AutoSize=$true;$label.Location=[Drawing.Point]::new(24,24)
$testTextBox=[Windows.Forms.TextBox]::new();$testTextBox.Name='AcceptanceInput';$testTextBox.AccessibleName='Acceptance input';$testTextBox.Size=[Drawing.Size]::new(520,32);$testTextBox.Location=[Drawing.Point]::new(24,72)
$testTextBox.Text=$InitialText
$apply=[Windows.Forms.Button]::new();$apply.Text='Apply test';$apply.AccessibleName='Apply test';$apply.Size=[Drawing.Size]::new(160,42);$apply.Location=[Drawing.Point]::new(24,128)
$result=[Windows.Forms.Label]::new();$result.Text='Waiting for MCP input';$result.AutoSize=$true;$result.Location=[Drawing.Point]::new(24,200)
$close=[Windows.Forms.Button]::new();$close.Text='Close test';$close.AccessibleName='Close test';$close.Size=[Drawing.Size]::new(160,42);$close.Location=[Drawing.Point]::new(380,260)
$form.Controls.AddRange(@($label,$testTextBox,$apply,$result,$close))
function Save-FixtureState([bool]$Closed=$false){
 $rect=[FixtureNative+RECT]::new();$null=[FixtureNative]::GetWindowRect($form.Handle,[ref]$rect)
 $testTextBoxPoint=$testTextBox.PointToScreen([Drawing.Point]::new(12,12))
 $applyPoint=$apply.PointToScreen([Drawing.Point]::new(80,20))
 $closePoint=$close.PointToScreen([Drawing.Point]::new(80,20))
 @{pid=$PID;title=$form.Text;region=@($rect.Left,$rect.Top,$rect.Right,$rect.Bottom);input=@($testTextBoxPoint.X,$testTextBoxPoint.Y);apply=@($applyPoint.X,$applyPoint.Y);close=@($closePoint.X,$closePoint.Y);value=$testTextBox.Text;result=$result.Text;closed=$Closed}|ConvertTo-Json|Set-Content -LiteralPath $StateFile -Encoding UTF8
}
$apply.Add_Click({$result.Text='PASS: '+$testTextBox.Text;Save-FixtureState})
$close.Add_Click({$form.Close()})
$closeTimer=[Windows.Forms.Timer]::new()
if($AutoCloseMilliseconds -gt 0){
 $closeTimer.Interval=$AutoCloseMilliseconds
 $closeTimer.Add_Tick({$closeTimer.Stop();$form.Close()})
}
$form.Add_Shown({Save-FixtureState;if($AutoCloseMilliseconds -gt 0){$closeTimer.Start()}})
$form.Add_FormClosing({
 # This fixture never owns the clipboard. Do not republish a stale OLE data
 # object or overwrite anything the user copied while the test was running.
 # Record coordinates before the handle is disposed; cleanup must not throw.
 try{Save-FixtureState $true}catch{Write-Warning 'Unable to record fixture close state.'}
})
[Windows.Forms.Application]::Run($form)
$closeTimer.Dispose()
$form.Dispose()
