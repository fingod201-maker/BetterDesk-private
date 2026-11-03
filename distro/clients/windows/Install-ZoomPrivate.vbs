' Zoom-Private BetterDesk support agent - friendly installer wrapper.
' No NSSM/service: installs into the interactive user session and starts
' %APPDATA%\betterdesk\agent\start-agent.vbs hidden at logon.
Option Explicit
Dim fso, sh, here, setup, rc
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")
here = fso.GetParentFolderName(WScript.ScriptFullName)
setup = here & "\Setup-BetterDesk.vbs"
If Not fso.FileExists(setup) Then
    MsgBox "Setup-BetterDesk.vbs was not found next to this installer.", 16, "Zoom-Private"
    WScript.Quit 1
End If
rc = sh.Run("wscript.exe """ & setup & """ /silent", 1, True)
If rc = 0 Then
    MsgBox "Zoom-Private support agent installed." & vbCrLf & vbCrLf & _
        "Start now: " & here & "\Start-ZoomPrivate.cmd" & vbCrLf & _
        "Config/log: %APPDATA%\betterdesk\agent", 64, "Zoom-Private"
Else
    MsgBox "Installation failed (exit " & rc & ")." & vbCrLf & _
        "Run Setup-BetterDesk.vbs interactively to see the error.", 16, "Zoom-Private"
End If
