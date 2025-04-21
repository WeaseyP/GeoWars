#version 450
#define SOKOL_WGSL (1)
layout(binding=0) uniform bg_fs_params {
    float tick;
};

out vec4 frag_color;

void main() {
    vec2 xy = fract((gl_FragCoord.xy-vec2(tick)) / 50.0);
    frag_color = vec4(vec3(xy.x*xy.y), 1.0);
}
