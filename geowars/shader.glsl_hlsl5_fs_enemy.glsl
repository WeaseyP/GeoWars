#version 450
#define SOKOL_HLSL (1)
layout(binding=1) uniform enemy_fs_params { float tick; };

in vec4 enemy_color_out_fs; 
in vec2 enemy_uv_out_fs;    
in vec4 enemy_effect_params_fs;                                         
in float enemy_visual_scale_fs_out;                                                           

out vec4 frag_color;

mat2 rotate2d(float angle) {
    float s = sin(angle);
    float c = cos(angle);
    return mat2(c, -s, s, c); 
}

float sdf_rectangle(vec2 p, vec2 half_dims) { 
    vec2 d = abs(p) - half_dims; 
    return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0);
}

void main() {
    vec2 uv_centered = enemy_uv_out_fs - vec2(0.5);

    float is_dying = enemy_effect_params_fs.x;
    float death_offset_world_units = enemy_effect_params_fs.y;
    float current_part_scale_multiplier = enemy_effect_params_fs.z;
    float overall_dying_alpha_multiplier = enemy_effect_params_fs.w;

    vec2 rectangle_half_dims_uv = vec2(0.32, 0.12);                      

                                                                                                  
    float part_effective_world_width_at_full_uv = rectangle_half_dims_uv.x * 2.0 * enemy_visual_scale_fs_out;

    if (is_dying > 0.5) {
        rectangle_half_dims_uv *= current_part_scale_multiplier;                        
                                                                   
                                                                                          
        part_effective_world_width_at_full_uv *= current_part_scale_multiplier;
    }

    float aa_world = 0.005;                     
                                
                                                                                                 
    float aa_uv = aa_world / max(0.01, part_effective_world_width_at_full_uv);
                                                     
                                                                                                                                        
                                                                                                                    
                                                                                                                     
                                                                            
                                                                                                        
                                                                                    
                                                       

                                   
                                                                                                              
                                                                    
                                                                                                         
    float aa_sdf_space = min(rectangle_half_dims_uv.x, rectangle_half_dims_uv.y) * 0.1;                                  
    aa_sdf_space = max(aa_sdf_space, 0.0001);                             

                                                              
    float death_offset_uv = 0.0;
    if (enemy_visual_scale_fs_out > 0.01) {                                                  
        death_offset_uv = death_offset_world_units / enemy_visual_scale_fs_out;
    }

    float pi = 3.14159265358979323846;
    float internal_yaw_speed = 1.2;

                          
    vec2 uv1_transformed = uv_centered;
    if (is_dying > 0.5) {
        uv1_transformed.y -= death_offset_uv * 0.5;
    }
    float internal_rotation1 = (pi / 4.0) + tick * internal_yaw_speed;
    vec2 uv1_rotated = rotate2d(internal_rotation1) * uv1_transformed;
    float dist1 = sdf_rectangle(uv1_rotated, rectangle_half_dims_uv);
    vec3 color1_tip = enemy_color_out_fs.rgb * 1.6 + vec3(0.3, 0.2, 0.3);
    vec3 gradient_color1 = mix(color1_tip, enemy_color_out_fs.rgb, smoothstep(-0.5, 0.5, uv1_rotated.y * 1.5));
    float alpha_sdf1 = smoothstep(aa_sdf_space, 0.0, dist1);              

                          
    vec2 uv2_transformed = uv_centered;
     if (is_dying > 0.5) {
        uv2_transformed.y += death_offset_uv * 0.5;
    }
    float internal_rotation2 = (-pi / 4.0) - tick * internal_yaw_speed;
    vec2 uv2_rotated = rotate2d(internal_rotation2) * uv2_transformed;
    float dist2 = sdf_rectangle(uv2_rotated, rectangle_half_dims_uv);
    vec3 color2_tip = enemy_color_out_fs.rgb * 0.7 - vec3(0.1, 0.0, 0.1);
    vec3 gradient_color2 = mix(color2_tip, enemy_color_out_fs.rgb, smoothstep(-0.5, 0.5, uv2_rotated.x * 1.5));
    float alpha_sdf2 = smoothstep(aa_sdf_space, 0.0, dist2);              

    float base_alpha = enemy_color_out_fs.a;
    if (is_dying > 0.5) {
        base_alpha *= overall_dying_alpha_multiplier;
    }

    vec4 frag1_color = vec4(gradient_color1, alpha_sdf1 * base_alpha);
    vec4 frag2_color = vec4(gradient_color2, alpha_sdf2 * base_alpha);
                                         
    vec3 blended_rgb;
    float blended_alpha;

    if (is_dying > 0.5) {
         blended_rgb = frag1_color.rgb * frag1_color.a + frag2_color.rgb * frag2_color.a;
         blended_alpha = max(frag1_color.a, frag2_color.a);
    } else {
        blended_rgb = frag2_color.rgb * frag2_color.a + frag1_color.rgb * frag1_color.a * (1.0 - frag2_color.a);
        blended_alpha = frag2_color.a + frag1_color.a * (1.0 - frag2_color.a);
    }
    
    frag_color = vec4(blended_rgb, blended_alpha);

    if (frag_color.a < 0.01) {
        discard;
    }
}
