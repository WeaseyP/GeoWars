#version 450
#define SOKOL_HLSL (1)
layout(binding=0) uniform enemy_vs_params { mat4 view_proj; };

                                                     
layout(location=0) in vec2 quad_pos_in;                                              
layout(location=1) in vec2 quad_uv_in;                                               

                                     
layout(location=2) in vec2 instance_pos_vs_in;
layout(location=3) in float instance_main_rotation_vs_in;
layout(location=4) in float instance_visual_scale_vs_in;                                                 
layout(location=5) in vec4 instance_color_vs_in;      
layout(location=6) in vec4 instance_effect_params_vs_in; 

                             
out vec4 enemy_color_out_fs;
out vec2 enemy_uv_out_fs;
out vec4 enemy_effect_params_fs; 
out float enemy_visual_scale_fs_out;

                                 
void main() {
                                                        
    float final_size_for_quad = instance_visual_scale_vs_in;                                                 

    float cr = cos(instance_main_rotation_vs_in);
    float sr = sin(instance_main_rotation_vs_in);
    mat2 main_rot_mat = mat2(cr, -sr, sr, cr);
    
                                  
    vec2 scaled_quad_pos = quad_pos_in * final_size_for_quad; 
    vec2 rotated_quad_pos = main_rot_mat * scaled_quad_pos;
    vec2 final_world_pos = rotated_quad_pos + instance_pos_vs_in;

    gl_Position = view_proj * vec4(final_world_pos, 0.0, 1.0);
    
    enemy_color_out_fs = instance_color_vs_in;
    enemy_uv_out_fs = quad_uv_in; 
    enemy_effect_params_fs = instance_effect_params_vs_in;
    enemy_visual_scale_fs_out = instance_visual_scale_vs_in; 
}
