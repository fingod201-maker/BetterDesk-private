@echo off
echo no | "C:\Users\milaz\Android\Sdk\cmdline-tools\latest\bin\avdmanager.bat" create avd -n test_device -k "system-images;android-30;google_apis;x86_64" --force