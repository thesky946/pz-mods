@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-forge-live.ps1"
if errorlevel 1 exit /b %errorlevel%
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0dev.ps1"
if errorlevel 1 exit /b %errorlevel%
set PZ_ALLOW_CONTROL=1
node "%~dp0forge-live\cli\forge-live.mjs" --mod CookItForMe
