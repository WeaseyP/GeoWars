@echo off
echo Building Shaders...
sokol-shdc -i geowars/assets/shaders/shader.glsl -o geowars/src/shared/shader.odin -l hlsl5:wgsl -f sokol_odin
if %errorlevel% neq 0 (
    echo Shader build failed!
    exit /b %errorlevel%
)

echo Building GeoWars for Windows (Release)...
odin build geowars/src/core -o:speed -out:geowars_windows.exe
if %errorlevel% neq 0 (
    echo Build failed!
    exit /b %errorlevel%
)

echo Done! Find geowars_windows.exe in this directory.
