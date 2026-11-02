Set sh = CreateObject("WScript.Shell")
cmd = sh.ExpandEnvironmentStrings("%APPDATA%\betterdesk\agent\agent-launch.cmd")
sh.Run "cmd.exe /c """ & cmd & """", 0, False
