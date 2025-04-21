@echo off

sokol-shdc -i geowars/shader.glsl -o geowars/shader.odin -l hlsl5:wgsl -f sokol_odin --save-intermediate-spirv

odin build geowars -debug