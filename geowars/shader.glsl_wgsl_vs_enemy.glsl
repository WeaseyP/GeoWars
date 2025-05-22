#version 450
#define SOKOL_WGSL (1)
layout(binding=0) uniform enemy_vs_params { mat4 view_proj; };

                                          
layout(location=0) in vec2 quad_pos;                                             
layout(location=1) in vec2 quad_uv;                                             

                                      
layout(location=2) in vec4 instance_pos_size_rot;                                                           
layout(location=3) in vec4 instance_color_in;                                          

                             
out vec4 enemy_color_out;
out vec2 enemy_uv_out;
out float enemy_dist_out;                                

void main() {
    vec2 inst_pos = instance_pos_size_rot.xy;
    float inst_size = instance_pos_size_rot.z;
    float inst_rot = instance_pos_size_rot.w;                                              

                                                                     
    float cr = cos(inst_rot);
    float sr = sin(inst_rot);
    mat2 rot_mat = mat2(cr, -sr, sr, cr);
    vec2 final_local_pos = rot_mat * (quad_pos * inst_size);

                                  
    vec2 final_world_pos = final_local_pos + inst_pos;

                        
    gl_Position = view_proj * vec4(final_world_pos, 0.0, 1.0);

                                           
    enemy_color_out = instance_color_in;
    enemy_uv_out = quad_uv;
    enemy_dist_out = length(quad_pos);                                                   
}
