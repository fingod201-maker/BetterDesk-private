@echo off
setlocal
set "AGENT=%ProgramFiles%\BetterDesk\Agent\betterdesk-agent.exe"
set "CFG=%APPDATA%\betterdesk\agent\agent-config.json"
set "LOG=%APPDATA%\betterdesk\agent\agent.log"

for %%A in ("%LOG%") do if %%~zA GTR 5242880 move /Y "%LOG%" "%LOG%.1" >nul 2>&1

echo.>>"%LOG%"
echo [%DATE% %TIME%] agent starting>>"%LOG%"
"%AGENT%" --config "%CFG%" >>"%LOG%" 2>&1
echo [%DATE% %TIME%] agent exited code %ERRORLEVEL%>>"%LOG%"
