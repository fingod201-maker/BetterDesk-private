@echo off
setlocal
set "VBS=%APPDATA%\betterdesk\agent\start-agent.vbs"
if not exist "%VBS%" (
    echo Zoom-Private agent is not installed.
    echo Run Install-ZoomPrivate.cmd first.
    pause
    exit /b 1
)
wscript.exe //B "%VBS%"
echo Zoom-Private agent start requested. Log:
echo   %APPDATA%\betterdesk\agent\agent.log
