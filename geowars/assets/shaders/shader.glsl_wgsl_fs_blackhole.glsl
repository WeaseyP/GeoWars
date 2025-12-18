#version 450
#define SOKOL_WGSL (1)
layout(binding=1) uniform blackhole_fs_params { float tick; };

in vec4 bh_color_out;                    
in vec2 bh_uv_out;

out vec4 frag_color;

void main() {
    vec2 uv_centered = bh_uv_out - vec2(0.5); 

                              
    float body_uv_half_width = 0.15; 
    float body_uv_half_length = 0.40;                                                           
    float body_ref_radius = 1.0;
    vec2 body_oval_scale = vec2(body_ref_radius / body_uv_half_width, body_ref_radius / body_uv_half_length);
    float dist_for_body_mask = length(uv_centered * body_oval_scale);
    float body_aa = 0.1; 
    float body_shape_alpha = 1.0 - smoothstep(body_ref_radius - body_aa, body_ref_radius + body_aa, dist_for_body_mask);

    if (body_shape_alpha < 0.01 && bh_color_out.a < 0.01) {                                                        
        discard;
    }

                                                 
    float dist_from_center_for_swirl = length(uv_centered);                                    
    float angle = atan(uv_centered.y, uv_centered.x);
    float swirl_speed = -7.0;                                
    float swirl_angular_freq = 8.0;  
    float swirl_radial_freq = 5.0;   
    float swirl_time_offset_factor = 0.25; 
    float swirl_value = sin(
        dist_from_center_for_swirl * swirl_radial_freq * (1.0 + 0.5 * sin(tick * swirl_time_offset_factor)) + 
        tick * swirl_speed
    );
    swirl_value = swirl_value * 0.5 + 0.5; 
    swirl_value = smoothstep(0.3, 0.7, swirl_value);                                                     

    vec3 color_core_black = vec3(0.0, 0.0, 0.0);
    vec3 color_swirl_dark = vec3(0.1, 0.0, 0.2);                              
    vec3 color_swirl_bright = vec3(0.7, 0.3, 0.9);                            

    vec3 body_swirl_color = mix(color_swirl_dark, color_swirl_bright, swirl_value);
    float core_radius_effect = 0.18;                                                   
    float core_influence = 1.0 - smoothstep(0.0, core_radius_effect, dist_from_center_for_swirl);
    vec3 body_base_rgb = mix(body_swirl_color, color_core_black, core_influence);

                                        
    vec3 glow_color = vec3(1.0, 0.7, 1.0) * 5.8;                                                      

                                                                                       
    float glow_uv_half_width = body_uv_half_width * 1.8;                 
    float glow_uv_base_half_length = body_uv_half_length * 1.5;                                 

                                                                                  
                                                                                    
                                                                                    
    float tail_elongation_factor = 1.0 + max(0.0, -uv_centered.y * 3.0);                                       
    float dynamic_glow_uv_half_length = glow_uv_base_half_length * tail_elongation_factor;

    vec2 glow_oval_scale = vec2(body_ref_radius / glow_uv_half_width, body_ref_radius / dynamic_glow_uv_half_length);
    float dist_for_glow_mask = length(uv_centered * glow_oval_scale);
    
    float glow_aa = 0.15;                                
    float glow_shape_alpha = 1.0 - smoothstep(body_ref_radius - glow_aa, body_ref_radius + glow_aa, dist_for_glow_mask);

                                                                                                   
    float glow_intensity_bias = (1.0 - smoothstep(0.0, 0.4, abs(uv_centered.x)));                               
    glow_intensity_bias *= (0.5 + 0.5 * smoothstep(-0.5, 0.5, -uv_centered.y));                         

    float effective_glow_strength = glow_shape_alpha * glow_intensity_bias * 0.8;                          

                                       
    float lifetime_alpha = bh_color_out.a; 
    float base_projectile_opacity = 0.80;                                  

                             
    vec3 final_rgb = body_base_rgb + glow_color * effective_glow_strength;
    
                                                                                              
    float combined_shape_alpha = max(body_shape_alpha, effective_glow_strength);
    float overall_alpha = combined_shape_alpha * lifetime_alpha * base_projectile_opacity;

    frag_color = vec4(clamp(final_rgb, 0.0, 2.5), clamp(overall_alpha, 0.0, 1.0));                                 
}
