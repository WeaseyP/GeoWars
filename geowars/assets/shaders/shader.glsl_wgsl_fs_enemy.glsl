#version 450
#define SOKOL_WGSL (1)
layout(binding=1) uniform enemy_fs_params { float tick; };

in vec4 enemy_color_out_fs; 
in vec2 enemy_uv_out_fs;    
in vec4 enemy_effect_params_fs;                                                                                                
in float enemy_visual_scale_fs_out;                                                           
in float v_enemy_type_fs;                                        

out vec4 frag_color;

const float PI = 3.14159265359;

mat2 rotate2d(float angle) {
    float s = sin(angle);
    float c = cos(angle);
    return mat2(c, -s, s, c); 
}

float sdf_rectangle(vec2 p, vec2 half_dims) { 
    vec2 d = abs(p) - half_dims; 
    return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0);
}

                                                 
float sdf_star(vec2 uv, int points, float inner_radius_factor, float outer_radius_param) {
    float angle_step = PI / float(points);
    float angle = atan(uv.y, uv.x);
    float r = length(uv);

                                                           
    float current_angle_segment = mod(angle, 2.0 * angle_step);                       
    
                                                               
    float segment_angle_offset = current_angle_segment - angle_step;

    float inner_radius = outer_radius_param * inner_radius_factor;

    float effective_radius = mix(outer_radius_param, inner_radius, abs(segment_angle_offset) / angle_step);
    
    return r - effective_radius;
}

void main() {
    vec2 uv_centered = enemy_uv_out_fs - vec2(0.5);
    const float enemy_visual_scale_on_quad = 3.0;

                                     
    if (v_enemy_type_fs > 0.5) {                            
        float glow_canvas_scale_factor = enemy_effect_params_fs.z; 

        float star_base_render_radius = 0.45; 
        float effective_sdf_outer_radius = star_base_render_radius / max(1.0, glow_canvas_scale_factor);

        float star_dist = sdf_star(uv_centered * enemy_visual_scale_on_quad, 5, 0.4, effective_sdf_outer_radius);
        
        float star_aa = 0.025;                                   

        float star_alpha_for_core = smoothstep(star_aa, 0.0, star_dist);

                                         
        float glow_spread = 0.18; 
        float glow_intensity_factor = 0.85; 

        float glow_alpha_calc = smoothstep(star_aa + glow_spread, star_aa, star_dist) * glow_intensity_factor;

        vec3 color_yellow = vec3(1.0, 1.0, 0.0);
        vec3 color_red = vec3(1.0, 0.0, 0.0);
        float transition = 0.5 + 0.5 * sin(tick * 0.8); 
        vec3 slowboy_color_animated = mix(color_yellow, color_red, transition);
        vec3 slowboy_color = slowboy_color_animated;                             

                                 
        bool is_winding_up = (enemy_effect_params_fs.y == 1.0);
        if (is_winding_up) {
            float total_windup_duration = enemy_effect_params_fs.w;
            float current_windup_timer = enemy_effect_params_fs.z;
                                                                     
            float windup_progress = clamp((total_windup_duration - current_windup_timer) / total_windup_duration, 0.0, 1.0);
            
            vec3 color_white = vec3(1.0, 1.0, 1.0);
            slowboy_color = mix(slowboy_color_animated, color_white, windup_progress);
        }

        vec3 final_combined_rgb = slowboy_color * star_alpha_for_core + slowboy_color * glow_alpha_calc;
        float final_combined_alpha_shape = clamp(star_alpha_for_core + glow_alpha_calc, 0.0, 1.0);

        float current_final_alpha = final_combined_alpha_shape * enemy_color_out_fs.a;
        
                                                                                         
                                                                                                              
                                                                                          
                                                                                  
                                                                                                         
        float is_dying_effect = enemy_effect_params_fs.x;
        if (is_dying_effect > 0.5) {
            float overall_dying_alpha_mult = enemy_effect_params_fs.w;                                          
            current_final_alpha *= overall_dying_alpha_mult;
                                                                           
                                                                                 
                                                                                              
                                                                                                
                                                                 
        }

        frag_color = vec4(final_combined_rgb, current_final_alpha);

        if (frag_color.a < 0.01) {
            discard;
        }
        return; 
    }

                                                    
    float aa_sdf_space;                             
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
                                                     
                                                                                                                                        
                                                                                                                    
                                                                                                                     
                                                                            
                                                                                                        
                                                                                    
                                                       

                                   
                                                                                                              
                                                                    
                                                                                                         
    aa_sdf_space = min(rectangle_half_dims_uv.x, rectangle_half_dims_uv.y) * 0.1;                                  
    aa_sdf_space = max(aa_sdf_space, 0.0001);                             

                                                              
    float death_offset_uv = 0.0;
    if (enemy_visual_scale_fs_out > 0.01) {                                                  
        death_offset_uv = death_offset_world_units / enemy_visual_scale_fs_out;
    }

    float internal_yaw_speed = 1.2;

                          
    vec2 base_uv1_for_grunt = uv_centered * enemy_visual_scale_on_quad;
    vec2 uv1_transformed = base_uv1_for_grunt;
    if (is_dying > 0.5) {
        uv1_transformed.y -= death_offset_uv * 0.5;
    }
    float internal_rotation1 = (PI / 4.0) + tick * internal_yaw_speed;
    vec2 uv1_rotated = rotate2d(internal_rotation1) * uv1_transformed;
    float dist1 = sdf_rectangle(uv1_rotated, rectangle_half_dims_uv);
    vec3 color1_tip = enemy_color_out_fs.rgb * 1.6 + vec3(0.3, 0.2, 0.3);
    vec3 gradient_color1 = mix(color1_tip, enemy_color_out_fs.rgb, smoothstep(-0.5, 0.5, uv1_rotated.y * 1.5));
    float alpha_sdf1 = smoothstep(aa_sdf_space, 0.0, dist1);              

                          
    vec2 base_uv2_for_grunt = uv_centered * enemy_visual_scale_on_quad;
    vec2 uv2_transformed = base_uv2_for_grunt;
     if (is_dying > 0.5) {
        uv2_transformed.y += death_offset_uv * 0.5;
    }
    float internal_rotation2 = (-PI / 4.0) - tick * internal_yaw_speed;
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
