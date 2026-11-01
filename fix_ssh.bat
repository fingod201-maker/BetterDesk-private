@echo off
set KEY=C:\Users\milaz\.ssh\betterdesk_oci
set HOST=147.224.213.55
set USER=betterdesk-oci

rem Remove old known hosts
if exist "%USERPROFILE%\.ssh\known_hosts" del "%USERPROFILE%\.ssh\known_hosts"

rem Try SSH connection
ssh -i %KEY% -o StrictHostKeyChecking=no %USER%@%HOST% "echo SSH_CONNECTED & ls -la /home/"