#version 450
#define SOKOL_WGSL (1)
                                       
layout(binding=0) uniform Player_Vs_Params { mat4 mvp; }; 
in vec2 position;
out vec2 v_uv;
void main() {
    gl_Position = mvp * vec4(position.xy, 0.0, 1.0);
    v_uv = position.xy * 0.5 + 0.5;
}
