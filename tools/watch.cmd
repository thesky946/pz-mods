@echo off
setlocal EnableExtensions EnableDelayedExpansion
set "ROOT=%~dp0.."
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

if not "%~1"=="" (
    set "SELECTED=%~1"
    if not exist "%ROOT%\mods\%SELECTED%\42\mod.info" (
        echo Unknown mod: %SELECTED%
        exit /b 1
    )
    goto :run
)

echo.
echo Project Zomboid mods:
for /l %%I in (1,1,%COUNT%) do echo   %%I. !MOD_%%I!
echo.
set /p "CHOICE=Choose a mod (or press Enter to cancel): "

for /l %%I in (1,1,%COUNT%) do (
    if "!CHOICE!"=="%%I" set "SELECTED=!MOD_%%I!"
)

if not defined SELECTED (
    echo Cancelled.
    exit /b 1
)

:run
echo Starting watcher for %SELECTED%...
call "%~dp0dev.cmd" "%SELECTED%"
exit /b %errorlevel%
