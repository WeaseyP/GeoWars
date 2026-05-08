@echo off
echo Building Shaders...
REM Use the local sokol-shdc.exe in the project root (matches how the repo ships it).
"%~dp0sokol-shdc.exe" -i geowars/assets/shaders/shader.glsl -o geowars/src/shared/shader.odin -l hlsl5:wgsl -f sokol_odin
if errorlevel 1 goto :error

REM Patch the auto-generated shader.odin so it lives in the `shared` package.
REM sokol-shdc emits `package main` by default; we need it to match the rest of shared/.
powershell -NoProfile -Command "(Get-Content 'geowars/src/shared/shader.odin' -Raw) -replace '^package main', 'package shared' | Set-Content -NoNewline 'geowars/src/shared/shader.odin'"
if errorlevel 1 goto :error

echo Building GeoWars for Windows (Release)...
odin build geowars/src/core -o:speed -out:geowars_windows.exe
if errorlevel 1 goto :error

echo Done! Find geowars_windows.exe in this directory.
exit /b 0

:error
echo BUILD FAILED.
exit /b 1
