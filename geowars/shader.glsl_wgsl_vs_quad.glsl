#version 450
#define SOKOL_WGSL (1)
layout(binding=0) uniform quad_vs_params {
    mat4 mvp;
};

in vec4 position;
in vec4 color0;

out vec4 color;

void main() {
    gl_Position = mvp * position;
    color = color0;
}
