#version 450
#define SOKOL_WGSL (1)
in vec2 position;
void main() {
    gl_Position = vec4(position, 0.5, 1.0);
}
