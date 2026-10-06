Option Explicit
Dim shell, files, script, command, result
Set shell = CreateObject("WScript.Shell")
Set files = CreateObject("Scripting.FileSystemObject")
script = files.BuildPath(files.GetParentFolderName(WScript.ScriptFullName), "service.ps1")
command = Chr(34) & shell.ExpandEnvironmentStrings("%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe") & Chr(34) & _
          " -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File " & Chr(34) & script & Chr(34)
' WScript is a GUI process; zero hides the child's console at creation.
' Wait so the scheduled task stays Running while its supervisor runs.
result = shell.Run(command, 0, True)
WScript.Quit result
