' BetterDesk Windows complete setup (double-click to run)
'
' Installs the support agent in the logged-in user session and starts it
' hidden at logon via a scheduled task. No NSSM/service is used, so screen
' capture and input injection target the real desktop.
'
' Usage:
'   wscript.exe Setup-BetterDesk.vbs
'   wscript.exe Setup-BetterDesk.vbs /uninstall
'   wscript.exe Setup-BetterDesk.vbs /silent
'
Option Explicit

Dim fso, sh, shellApp
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")
Set shellApp = CreateObject("Shell.Application")

Dim args, silent, uninstall, elevated, syntaxCheck, noTask
silent = False
uninstall = False
elevated = False
syntaxCheck = False
noTask = False
For Each args In WScript.Arguments
    Select Case LCase(args)
        Case "/uninstall", "-uninstall", "--uninstall"
            uninstall = True
        Case "/silent", "-silent", "--silent"
            silent = True
        Case "/elevated"
            elevated = True
        Case "/check", "--check"
            syntaxCheck = True
    End Select
Next

If syntaxCheck Then WScript.Quit 0

If Not elevated And Not IsAdmin() Then
    Dim argLine
    argLine = """" & WScript.ScriptFullName & """"
    If uninstall Then argLine = argLine & " /uninstall"
    If silent Then argLine = argLine & " /silent"
    argLine = argLine & " /elevated"
    shellApp.ShellExecute "wscript.exe", argLine, "", "runas", IIf(silent, 0, 1)
    WScript.Quit 0
End If

Main

Sub Main()
    Dim sourceDir, appPath, appName, installDir, agentDir
    sourceDir = fso.GetParentFolderName(WScript.ScriptFullName)
    installDir = sh.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\BetterDesk\SupportAgent"
    agentDir = sh.ExpandEnvironmentStrings("%APPDATA%") & "\betterdesk\agent"

    If uninstall Then
        DoUninstall installDir, agentDir
        Exit Sub
    End If

    appPath = FindApp(sourceDir)
    If appPath = "" Then
        Msg "BetterDesk executable was not found next to Setup-BetterDesk.vbs." & vbCrLf & _
            "Expected one of: betterdesk.exe, rustdesk.exe, betterdesk-agent.exe", 16
        WScript.Quit 1
    End If
    appName = fso.GetBaseName(appPath)

    Log agentDir, "setup start source=" & sourceDir & " app=" & appPath
    EnsureFolder installDir
    EnsureFolder agentDir
    If LCase(sourceDir) <> LCase(installDir) Then CopyPayload sourceDir, installDir

    Dim installedApp, configFile, launchCmd, startVbs, taskName
    installedApp = installDir & "\" & fso.GetFileName(appPath)
    If Not fso.FileExists(installedApp) Then installedApp = appPath
    configFile = agentDir & "\agent-config.json"
    launchCmd = agentDir & "\agent-launch.cmd"
    startVbs = agentDir & "\start-agent.vbs"
    taskName = appName & " Support Agent"

    If fso.FileExists(sourceDir & "\agent-config.json") And Not fso.FileExists(configFile) Then
        fso.CopyFile sourceDir & "\agent-config.json", configFile, True
    End If

    WriteLaunchCmd launchCmd, installedApp, configFile, agentDir & "\agent.log", (InStr(LCase(appName), "agent") > 0)
    WriteStartVbs startVbs

    Dim taskPs1
    taskPs1 = agentDir & "\install-task.ps1"
    WriteTaskPs1 taskPs1, taskName, startVbs, installDir

    RunHidden "schtasks.exe /Delete /TN """ & taskName & """ /F"
    If Not RunHidden("powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & taskPs1 & """") Then
        Log agentDir, "scheduled task create failed via install-task.ps1"
        Msg "Could not create the logon task. Run this file as your own user (not SYSTEM).", 16
        WScript.Quit 1
    End If

    Log agentDir, "setup complete task=" & taskName
    If Not silent Then
        Msg "BetterDesk Support Agent installed." & vbCrLf & vbCrLf & _
            "Binary : " & installedApp & vbCrLf & _
            "Config : " & configFile & vbCrLf & _
            "Log    : " & agentDir & "\agent.log" & vbCrLf & _
            "Task   : " & taskName, 64
    End If
End Sub

Sub DoUninstall(installDir, agentDir)
    Dim appName, appPath
    appPath = FindApp(installDir)
    appName = "BetterDesk Support Agent"
    If appPath <> "" Then appName = fso.GetBaseName(appPath) & " Support Agent"
    RunHidden "schtasks.exe /Delete /TN """ & appName & """ /F"
    RunHidden "schtasks.exe /Delete /TN ""BetterDesk Support Agent"" /F"
    RunHidden "taskkill.exe /IM betterdesk-agent.exe /F"
    RunHidden "taskkill.exe /IM betterdesk.exe /F"
    If fso.FolderExists(installDir) Then fso.DeleteFolder installDir, True
    If fso.FolderExists(agentDir) Then fso.DeleteFolder agentDir, True
    If Not silent Then Msg "BetterDesk Support Agent removed.", 64
End Sub

Function FindApp(dir)
    Dim names, i, p
    names = Array("betterdesk-agent.exe", "betterdesk.exe", "rustdesk.exe")
    For i = 0 To UBound(names)
        p = dir & "\" & names(i)
        If fso.FileExists(p) Then
            FindApp = p
            Exit Function
        End If
    Next
    If fso.FolderExists(dir) Then
        Dim f
        For Each f In fso.GetFolder(dir).Files
            If LCase(fso.GetExtensionName(f.Name)) = "exe" Then
                FindApp = f.Path
                Exit Function
            End If
        Next
    End If
    FindApp = ""
End Function

Sub CopyPayload(src, dst)
    Dim f, sf
    For Each f In fso.GetFolder(src).Files
        Select Case LCase(f.Name)
            Case "setup-betterdesk.vbs", "install-betterdesk.ps1", "uninstall-betterdesk.ps1"
                ' skip installer entry points
            Case Else
                fso.CopyFile f.Path, dst & "\" & f.Name, True
        End Select
    Next
    For Each sf In fso.GetFolder(src).SubFolders
        If Not fso.FolderExists(dst & "\" & sf.Name) Then fso.CreateFolder dst & "\" & sf.Name
        CopyPayload sf.Path, dst & "\" & sf.Name
    Next
End Sub

Sub WriteLaunchCmd(path, app, cfg, logFile, isAgent)
    Dim runLine, body
    If isAgent Then
        runLine = "if exist ""%CFG%"" ( ""%AGENT%"" --config ""%CFG%"" >>""%LOG%"" 2>&1 ) else ( ""%AGENT%"" >>""%LOG%"" 2>&1 )"
    Else
        runLine = """%AGENT%"" --tray >>""%LOG%"" 2>&1"
    End If
    body = "@echo off" & vbCrLf & _
        "setlocal" & vbCrLf & _
        "set ""AGENT=" & app & """" & vbCrLf & _
        "set ""CFG=" & cfg & """" & vbCrLf & _
        "set ""LOG=" & logFile & """" & vbCrLf & vbCrLf & _
        "for %%A in (""%LOG%"") do if %%~zA GTR 5242880 move /Y ""%LOG%"" ""%LOG%.1"" >nul 2>&1" & vbCrLf & vbCrLf & _
        "echo.>>""%LOG%""" & vbCrLf & _
        "echo [%DATE% %TIME%] agent starting>>""%LOG%""" & vbCrLf & _
        runLine & vbCrLf & _
        "echo [%DATE% %TIME%] agent exited code %ERRORLEVEL%>>""%LOG%"""
    WriteAscii path, body
End Sub

Sub WriteStartVbs(path)
    Dim body, q
    q = Chr(34)
    body = "Set sh = CreateObject(" & q & "WScript.Shell" & q & ")" & vbCrLf & _
        "cmd = sh.ExpandEnvironmentStrings(" & q & "%APPDATA%\betterdesk\agent\agent-launch.cmd" & q & ")" & vbCrLf & _
        "sh.Run " & q & "cmd.exe /c " & q & q & q & " & cmd & " & q & q & q & q & ", 0, False"
    WriteAscii path, body
End Sub

Sub WriteTaskPs1(path, taskName, startVbs, workDir)
    Dim body
    body = "$ErrorActionPreference = 'Stop'" & vbCrLf & _
        "$taskName = '" & PsQuote(taskName) & "'" & vbCrLf & _
        "$vbs = '" & PsQuote(startVbs) & "'" & vbCrLf & _
        "$workDir = '" & PsQuote(workDir) & "'" & vbCrLf & _
        "$action = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument ('//B ""{0}""' -f $vbs) -WorkingDirectory $workDir" & vbCrLf & _
        "$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME" & vbCrLf & _
        "$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive" & vbCrLf & _
        "$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)" & vbCrLf & _
        "Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null" & vbCrLf & _
        "Start-ScheduledTask -TaskName $taskName" & vbCrLf
    WriteAscii path, body
End Sub

Function PsQuote(value)
    PsQuote = Replace(value, "'", "''")
End Function

Sub WriteAscii(path, text)
    Dim stream
    Set stream = fso.CreateTextFile(path, True, False)
    stream.Write text
    stream.Close
End Sub

Sub EnsureFolder(path)
    If fso.FolderExists(path) Then Exit Sub
    Dim parts, i, cur
    parts = Split(path, "\")
    cur = ""
    For i = 0 To UBound(parts)
        If parts(i) = "" Then
            If i = 0 Then cur = "\"
        Else
            If cur = "" Then
                cur = parts(i)
            ElseIf Right(cur, 1) = "\" Then
                cur = cur & parts(i)
            Else
                cur = cur & "\" & parts(i)
            End If
            If Not fso.FolderExists(cur) Then fso.CreateFolder cur
        End If
    Next
End Sub

Function IsAdmin()
    On Error Resume Next
    Dim rc
    rc = sh.Run("cmd.exe /c net session >nul 2>&1", 0, True)
    IsAdmin = (Err.Number = 0 And rc = 0)
    Err.Clear
    On Error GoTo 0
End Function

Function RunHidden(cmd)
    On Error Resume Next
    Dim rc
    rc = sh.Run(cmd, 0, True)
    RunHidden = (Err.Number = 0 And rc = 0)
    Err.Clear
    On Error GoTo 0
End Function

Sub Log(agentDir, text)
    On Error Resume Next
    EnsureFolder agentDir
    Dim stream
    Set stream = fso.OpenTextFile(agentDir & "\setup.log", 8, True)
    stream.WriteLine "[" & Now & "] " & text
    stream.Close
    On Error GoTo 0
End Sub

Sub Msg(text, icon)
    If Not silent Then MsgBox text, icon, "BetterDesk Setup"
End Sub

Function IIf(cond, a, b)
    If cond Then IIf = a Else IIf = b
End Function
