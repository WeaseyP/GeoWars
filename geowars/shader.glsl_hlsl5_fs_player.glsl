#version 450
#define SOKOL_HLSL (1)
layout(binding=1) uniform Player_Fs_Params {
    float tick;
    vec2 resolution;
    float player_hp_uniform;
    float player_max_hp_uniform;
    float player_invulnerable_timer_uniform;
    float player_invulnerability_duration_uniform; 
};
in vec2 v_uv;
out vec4 frag_color;

float sdCircle(vec2 p, float r) { return length(p) - r; }
mat2 rotate2d(float angle) { float c=cos(angle); float s=sin(angle); return mat2(c,-s,s,c); }

void main() {
    vec2 p_orig = v_uv - vec2(0.5);
    float anim_time = tick * 0.05; 
    float color_time = tick * 0.5;
    float direct_tick = tick; 

    float hp = player_hp_uniform;
    float max_hp = player_max_hp_uniform;
    float invul_timer = player_invulnerable_timer_uniform;
    float invul_duration = player_invulnerability_duration_uniform;

                                              
    vec3 color_core_default = vec3(0.5, 1.0, 1.0);                  
    vec3 color_ring1_default = vec3(1.0, 0.3, 0.9);             
    vec3 color_ring2_health_based = vec3(0.2, 0.5, 1.0);                                     
    vec3 color_glow_dynamic = normalize(vec3(0.5+0.5*sin(color_time+0.0), 0.5+0.5*sin(color_time+2.094395), 0.5+0.5*sin(color_time+4.18879))) * 1.1;

                                                           
    if (hp <= 0.01) { 
        color_ring2_health_based = vec3(0.1, 0.1, 0.1);                                                                 
    } else if (max_hp > 1.0) {
        float health_fraction = hp / max_hp;
        if (health_fraction <= 0.25) { 
            color_ring2_health_based = vec3(1.0, 0.2, 0.1);       
        } else if (health_fraction <= 0.5) { 
            color_ring2_health_based = vec3(1.0, 0.8, 0.1);          
        } else if (health_fraction <= 0.75) { 
            color_ring2_health_based = vec3(0.2, 1.0, 0.2);         
        }
                                               
    } else if (hp < max_hp && max_hp == 1.0) {                              
         color_ring2_health_based = vec3(1.0, 0.2, 0.1);       
    }


                                                             
    float core_alpha = 0.0;
    float ring1_alpha = 0.0;
    float ring2_alpha = 0.0;
    float glow_alpha_contrib = 0.0;

           
    float core_rad_anim = 0.04 + 0.005 * sin(anim_time * 25.0);
    float core_dist_sdf = sdCircle(p_orig, core_rad_anim);
    core_alpha = smoothstep(0.005, 0.0, core_dist_sdf); 
    if (hp <= 0.01) core_alpha *= (0.15 + 0.1 * sin(direct_tick * 35.0));

             
    float r1_rot = -anim_time * 1.5; float r1_squash = 0.3 + 0.7 * abs(cos(anim_time * 1.5));
    mat2 r1_invRot = rotate2d(-r1_rot); mat2 r1_invScale = mat2(1.0, 0.0, 0.0, 1.0 / r1_squash);
    vec2 p1_uv = r1_invScale * r1_invRot * p_orig;
    float r1_rad_anim = 0.1 + 0.01 * cos(anim_time * 18.0);
    float r1_thick = 0.015;
    float r1_dist_sdf = abs(sdCircle(p1_uv, r1_rad_anim)) - r1_thick * 0.5;
    ring1_alpha = smoothstep(0.004, 0.0, r1_dist_sdf);
    if (hp <= 0.01) ring1_alpha = 0.0;

             
    float r2_rot = anim_time * 1.1; float r2_squash = 0.4 + 0.6 * abs(sin(anim_time * 1.1 + 0.5));
    mat2 r2_invRot = rotate2d(-r2_rot); mat2 r2_invScale = mat2(1.0, 0.0, 0.0, 1.0 / r2_squash);
    vec2 p2_uv = r2_invScale * r2_invRot * p_orig;
    float r2_rad_anim = 0.18 + 0.01 * sin(anim_time * 12.0);
    float r2_thick = 0.01;
    float r2_dist_sdf = abs(sdCircle(p2_uv, r2_rad_anim)) - r2_thick * 0.5;
    ring2_alpha = smoothstep(0.003, 0.0, r2_dist_sdf);
    if (hp <= 0.01) ring2_alpha = 0.0;

                    
    float dist_glow = length(p_orig);
    float spike_rot_glow = anim_time * 0.8; 
    float base_angle_glow = atan(p_orig.y, p_orig.x);
    float rotated_angle_glow = base_angle_glow + spike_rot_glow;
    float spikes_glow = pow(abs(sin(rotated_angle_glow * 8.0)), 32.0);
    float glow_intensity_val = pow(max(0.0, 1.0 - dist_glow / 0.5), 5.0);
    glow_intensity_val *= (0.7 + 5.0 * spikes_glow);
    glow_intensity_val *= (0.8 + 0.2 * sin(anim_time * 15.0 + dist_glow * 12.0));
    glow_alpha_contrib = glow_intensity_val * 0.6;
    if (hp <= 0.01) glow_alpha_contrib = 0.0;

                                                                
    vec3 combined_color = vec3(0.0);
    combined_color += color_glow_dynamic * glow_alpha_contrib * 2.0;                                      
    combined_color += color_ring2_health_based * ring2_alpha;
    combined_color += color_ring1_default * 1.5 * ring1_alpha;                                    
    combined_color += color_core_default * core_alpha;
    
    float final_alpha = max(max(core_alpha, ring1_alpha), max(ring2_alpha, glow_alpha_contrib));


                                                              
    if (invul_timer > 0.001 && invul_duration > 0.001 && hp > 0.01) {
        float invul_ratio = invul_timer / invul_duration;
        float flash_pulse = 0.5 + 0.5 * sin(direct_tick * 60.0 + invul_ratio * 20.0); 
        float flash_amount = pow(invul_ratio, 1.0) * flash_pulse; 
        flash_amount = clamp(flash_amount * 1.5, 0.0, 1.0);                            

        vec3 flash_overlay_color = vec3(1.0, 1.0, 1.0);                      

                                                    
                                                                     
        combined_color += flash_overlay_color * flash_amount * final_alpha; 
    }
    
    frag_color = vec4(clamp(combined_color, 0.0, 1.0), clamp(final_alpha, 0.0, 1.0));
}
