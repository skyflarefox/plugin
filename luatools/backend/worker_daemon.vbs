Option Explicit

Dim shell, fso, pluginRoot, tempDir, queueDir, heartbeatPath
Dim idleLoops, fileItem, foundPath, runningPath, command, fileHandle

Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

Function UnixNow()
  Dim bias
  bias = 0
  On Error Resume Next
  bias = CLng(shell.RegRead("HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation\ActiveTimeBias"))
  If Err.Number <> 0 Then
    Err.Clear
    bias = 0
  End If
  On Error GoTo 0
  UnixNow = DateDiff("s", #1/1/1970#, Now()) + (bias * 60)
End Function

If WScript.Arguments.Count < 1 Then
  WScript.Quit 1
End If

pluginRoot = WScript.Arguments(0)
tempDir = fso.BuildPath(fso.BuildPath(pluginRoot, "backend"), "temp_dl")
queueDir = fso.BuildPath(tempDir, "queue")
heartbeatPath = fso.BuildPath(tempDir, "worker_daemon.heartbeat")

If Not fso.FolderExists(tempDir) Then
  fso.CreateFolder tempDir
End If
If Not fso.FolderExists(queueDir) Then
  fso.CreateFolder queueDir
End If

idleLoops = 0

Do
  On Error Resume Next
  Set fileHandle = fso.OpenTextFile(heartbeatPath, 2, True)
  fileHandle.Write CStr(UnixNow())
  fileHandle.Close
  On Error GoTo 0

  foundPath = ""
  On Error Resume Next
  For Each fileItem In fso.GetFolder(queueDir).Files
    If LCase(fso.GetExtensionName(fileItem.Name)) = "job" Then
      foundPath = fileItem.Path
      Exit For
    End If
  Next
  On Error GoTo 0

  If Len(foundPath) > 0 Then
    idleLoops = 0
    runningPath = fso.BuildPath(queueDir, fso.GetBaseName(foundPath) & ".running")

    On Error Resume Next
    fso.MoveFile foundPath, runningPath
    If Err.Number <> 0 Then
      Err.Clear
      WScript.Sleep 200
    Else
      Set fileHandle = fso.OpenTextFile(runningPath, 1, False)
      command = fileHandle.ReadAll
      fileHandle.Close

      If Len(Trim(command)) > 0 Then
        shell.Run command, 0, False
      End If

      fso.DeleteFile runningPath, True
    End If
    On Error GoTo 0
  Else
    idleLoops = idleLoops + 1
    If idleLoops > 300 Then Exit Do
    WScript.Sleep 200
  End If
Loop

WScript.Quit 0
