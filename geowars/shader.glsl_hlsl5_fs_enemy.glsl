#version 450
#define SOKOL_HLSL (1)
layout(binding=1) uniform enemy_fs_params { float tick; };                              

in vec4 enemy_color_out; 
in vec2 enemy_uv_out;    
in float enemy_dist_out;                                                         

out vec4 frag_color;

void main() {
                                    
    vec4 base_color = enemy_color_out;

                           
                                                                                     
                                                                     
                                                                       
    base_color.a *= (0.999 + 0.001 * sin(tick * 0.1f));                       

    frag_color = base_color;
}
