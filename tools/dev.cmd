@echo off
set "PZ_MOD=%~1"
if "%PZ_MOD%"=="" set "PZ_MOD=cook-it-for-me"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-forge-live.ps1" -Mod "%PZ_MOD%"
if errorlevel 1 exit /b %errorlevel%
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0dev.ps1" -Mod "%PZ_MOD%"
if errorlevel 1 exit /b %errorlevel%
set PZ_ALLOW_CONTROL=1
for /f "usebackq tokens=1,* delims==" %%A in ("%~dp0..\mods\%PZ_MOD%\42\mod.info") do if /I "%%A"=="id" set "PZ_MOD_ID=%%B"
if "%PZ_MOD_ID%"=="" exit /b 1
node "%~dp0forge-live\cli\forge-live.mjs" --mod "%PZ_MOD_ID%"
