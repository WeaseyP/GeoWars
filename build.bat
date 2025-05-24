@echo off
echo Building Shaders...
sokol-shdc -i geowars/shader.glsl -o geowars/shader.odin -l hlsl5:wgsl -f sokol_odin

echo Building GeoWars for Windows (Release)...
odin build geowars -o:speed -out:geowars_windows.exe
REM Using -out: to give it a platform-specific name, good practice

echo Done! Find geowars_windows.exe in this directory.