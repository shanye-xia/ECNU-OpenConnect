Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
baseDir = fso.GetParentFolderName(WScript.ScriptFullName)
scriptPath = fso.BuildPath(baseDir, "internal\ECNU-OpenConnect-GUI.ps1")
cmd = "powershell.exe -STA -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File " & Chr(34) & scriptPath & Chr(34) & " Gui"
shell.Run cmd, 0, False
