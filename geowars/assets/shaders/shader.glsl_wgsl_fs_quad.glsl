#version 450
#define SOKOL_WGSL (1)
in vec4 color;
out vec4 frag_color;
void main() {
    frag_color = color;
}
