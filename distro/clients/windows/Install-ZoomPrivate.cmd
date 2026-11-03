@echo off
setlocal
set "HERE=%~dp0"
if not exist "%HERE%Setup-BetterDesk.vbs" (
    echo Setup-BetterDesk.vbs was not found next to this script.
    pause
    exit /b 1
)
echo Installing Zoom-Private BetterDesk support agent in the current user session...
wscript.exe "%HERE%Setup-BetterDesk.vbs" /silent
if errorlevel 1 (
    echo Installation failed. Run Setup-BetterDesk.vbs interactively for details.
    pause
    exit /b 1
)
echo.
echo Installed.
echo   Binary : %LOCALAPPDATA%\BetterDesk\SupportAgent\betterdesk-agent.exe
echo   Config : %APPDATA%\betterdesk\agent\agent-config.json
echo   Log    : %APPDATA%\betterdesk\agent\agent.log
echo   Task   : betterdesk-agent Support Agent (interactive user session, hidden)
echo.
echo The agent starts automatically at logon. Use Start-ZoomPrivate.cmd to start it now.
pause
