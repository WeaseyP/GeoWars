#version 450
#define SOKOL_HLSL (1)
layout(binding=1) uniform enemy_fs_params { float tick; };
in vec4 enemy_color_out_fs;                                             
in vec2 enemy_uv_out_fs;    
in vec4 enemy_effect_params_fs; 
in float enemy_visual_scale_fs;  

out vec4 frag_color;

                                                                 
                                        
vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

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
    float death_offset = enemy_effect_params_fs.y;
    float current_part_scale_multiplier = enemy_effect_params_fs.z;
    float dying_alpha_multiplier = enemy_effect_params_fs.w;

    vec2 base_rectangle_half_dims_uv = vec2(0.32, 0.12);
    vec2 actual_rectangle_half_dims_uv = base_rectangle_half_dims_uv;

    if (is_dying > 0.5) {
        actual_rectangle_half_dims_uv = base_rectangle_half_dims_uv * current_part_scale_multiplier;
    }

    float aa = 0.025 / max(0.1, enemy_visual_scale_fs);

    float pi = 3.14159265358979323846;
    float internal_yaw_speed = 1.2;

                                        
    float instance_base_hue = enemy_color_out_fs.r;                                                        

    float hue_cycle_time = fract(tick * 0.05);                                      
    float hue_spatial_offset = fract((enemy_uv_out_fs.x + enemy_uv_out_fs.y) * 0.3);                           

                                                                                 
    float current_hue = fract(instance_base_hue + hue_cycle_time + hue_spatial_offset);

                                                                                                              
    float saturation = 0.9;                      
    float value = 0.95;                                

    vec3 final_enemy_rgb = hsv2rgb(vec3(current_hue, saturation, value));
                                            


                                        
    vec2 uv1_transformed = uv_centered;
    if (is_dying > 0.5) {
        uv1_transformed.y -= death_offset * 0.5;
    }
    float internal_rotation1 = (pi / 4.0) + tick * internal_yaw_speed;
    vec2 uv1_rotated = rotate2d(internal_rotation1) * uv1_transformed;
    float dist1 = sdf_rectangle(uv1_rotated, actual_rectangle_half_dims_uv);
                                  
    vec3 gradient_color1 = final_enemy_rgb;
    float alpha_sdf1 = smoothstep(aa, 0.0, dist1);

                                        
    vec2 uv2_transformed = uv_centered;
     if (is_dying > 0.5) {
        uv2_transformed.y += death_offset * 0.5;
    }
    float internal_rotation2 = (-pi / 4.0) - tick * internal_yaw_speed;
    vec2 uv2_rotated = rotate2d(internal_rotation2) * uv2_transformed;
    float dist2 = sdf_rectangle(uv2_rotated, actual_rectangle_half_dims_uv);
                                  
    vec3 gradient_color2 = final_enemy_rgb;
    float alpha_sdf2 = smoothstep(aa, 0.0, dist2);

                                         
                                                                               
    vec4 frag1_color = vec4(gradient_color1, alpha_sdf1 * enemy_color_out_fs.a);
    vec4 frag2_color = vec4(gradient_color2, alpha_sdf2 * enemy_color_out_fs.a);

    vec3 blended_rgb;
    float blended_alpha;

    if (is_dying > 0.5) {
         blended_rgb = frag1_color.rgb * frag1_color.a + frag2_color.rgb * frag2_color.a;
         blended_alpha = max(frag1_color.a, frag2_color.a);
    } else {
        blended_rgb = frag2_color.rgb * frag2_color.a + frag1_color.rgb * (1.0 - frag2_color.a);
        blended_alpha = frag2_color.a + frag1_color.a * (1.0 - frag2_color.a);
    }

    if (is_dying > 0.5) {
        blended_alpha *= dying_alpha_multiplier;
    }

    frag_color = vec4(blended_rgb, blended_alpha);

    if (frag_color.a < 0.01) {
        discard;
    }
}
