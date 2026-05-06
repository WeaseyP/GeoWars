@echo off
REM snap.bat - convenience wrapper around tools\snap.ps1.
REM   snap.bat [WaitSeconds] [OutPath]
REM Defaults: 4 seconds, screenshots\snap.png

setlocal
set "WAIT=%~1"
if "%WAIT%"=="" set "WAIT=4"
set "OUT=%~2"
if "%OUT%"=="" set "OUT=screenshots\snap.png"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\snap.ps1" -WaitSeconds %WAIT% -Out "%OUT%"
endlocal
