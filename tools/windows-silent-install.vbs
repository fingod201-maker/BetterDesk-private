Dim objShell
Set objShell = CreateObject("WScript.Shell")
Dim target
target = WScript.Arguments(0)
If LCase(Right(target, 4)) = ".MSI" Then
    objShell.Run "msiexec /i " & Chr(34) & target & Chr(34) & " /quiet /norestart", 0, True
ElseIf LCase(Right(target, 4)) = ".EXE" Then
    objShell.Run Chr(34) & target & Chr(34) & " /S", 0, True
End If
