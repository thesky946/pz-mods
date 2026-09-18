@echo off
setlocal EnableExtensions EnableDelayedExpansion
set "ROOT=%~dp0.."
set "PZ_MOD=%~1"
if defined PZ_MOD goto :validate

set /a COUNT=0
for /d %%D in ("%ROOT%\mods\*") do (
    if exist "%%~fD\42\mod.info" (
        set /a COUNT+=1
        set "MOD_!COUNT!=%%~nxD"
    )
)

if %COUNT% EQU 0 (
    echo No mods found in "%ROOT%\mods".
    exit /b 1
)

echo.
echo Project Zomboid mods:
for /l %%I in (1,1,%COUNT%) do echo   %%I. !MOD_%%I!
echo.
set /p "CHOICE=Choose a mod (or press Enter to cancel): "

for /l %%I in (1,1,%COUNT%) do (
    if "!CHOICE!"=="%%I" set "PZ_MOD=!MOD_%%I!"
)

if not defined PZ_MOD (
    echo Cancelled.
    exit /b 1
)

:validate
if not exist "%ROOT%\mods\%PZ_MOD%\42\mod.info" (
    echo Unknown mod: %PZ_MOD%
    exit /b 1
)

echo Starting watcher for %PZ_MOD%...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-forge-live.ps1" -Mod "%PZ_MOD%"
if errorlevel 1 exit /b %errorlevel%
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0dev.ps1" -Mod "%PZ_MOD%"
if errorlevel 1 exit /b %errorlevel%
set PZ_ALLOW_CONTROL=1
for /f "usebackq tokens=1,* delims==" %%A in ("%~dp0..\mods\%PZ_MOD%\42\mod.info") do if /I "%%A"=="id" set "PZ_MOD_ID=%%B"
if "%PZ_MOD_ID%"=="" exit /b 1
node "%~dp0forge-live\cli\forge-live.mjs" --mod "%PZ_MOD_ID%"
