' Starts statusline-helper.ps1 hidden, in its own console, detached from the
' caller. Launched by statusline-sys.sh whenever the helper's heartbeat is stale.
' The helper holds a mutex, so extra launches exit immediately.
Set fso = CreateObject("Scripting.FileSystemObject")
helper = fso.BuildPath(fso.GetParentFolderName(WScript.ScriptFullName), "statusline-helper.ps1")
CreateObject("WScript.Shell").Run "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & helper & """", 0, False
