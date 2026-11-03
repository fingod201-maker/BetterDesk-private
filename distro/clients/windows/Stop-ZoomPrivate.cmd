@echo off
setlocal
schtasks /End /TN "betterdesk-agent Support Agent" >nul 2>&1
taskkill /IM betterdesk-agent.exe /F >nul 2>&1
echo Zoom-Private agent stopped (it will start again at the next logon).
