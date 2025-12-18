#!/bin/bash

echo "Building Shaders..."
sokol-shdc -i geowars/assets/shaders/shader.glsl -o geowars/src/shared/shader.odin -l hlsl5:wgsl -f sokol_odin

echo "Building GeoWars for Windows (Release)..."
odin build geowars/src/core -o:speed -out:geowars_windows.exe
echo "Done! Find geowars_windows.exe in this directory."
