#!/bin/bash

echo "Building Shaders..."
./sokol-shdc.exe -i geowars/assets/shaders/shader.glsl -o geowars/src/graphics/shader.odin -l hlsl5:wgsl -f sokol_odin

echo "Building GeoWars for Windows (Release)..."
odin build geowars/src/core geowars/src/graphics geowars/src/audio geowars/src/game/player geowars/src/game/enemy geowars/src/game/particle geowars/src/game/projectile geowars/src/game/progression geowars/src/game/collision -o:speed -out:geowars_windows.exe

echo "Done! Find geowars_windows.exe in this directory."
