#version 450
#define SOKOL_WGSL (1)
layout(binding=1) uniform Player_Fs_Params {
    float tick;
    vec2 resolution;
    float player_hp_uniform;
    float player_max_hp_uniform;
};
in vec2 v_uv;
out vec4 frag_color;

float sdCircle(vec2 p, float r) { return length(p) - r; }
mat2 rotate2d(float angle) { float c=cos(angle); float s=sin(angle); return mat2(c,-s,s,c); }

void main() {
    vec2 p_orig = v_uv - vec2(0.5);
    float anim_time = tick * 0.05;                                            
    float color_time = tick * 0.5;
    float flicker_tick = tick;                                               

    float hp = player_hp_uniform;
    float max_hp = player_max_hp_uniform;

    vec3 color = vec3(0.0); float alpha = 0.0;

                                 
    float core_mod = 1.0;
    float ring1_mod = 1.0;
    float ring2_mod = 1.0;
    float glow_mod = 1.0;

    if (max_hp > 0.0) {                          
        float lost_hp = max_hp - hp;

        if (hp <= 0.0) {               
            core_mod = 0.05 + 0.05 * sin(flicker_tick * 35.0);                              
            ring1_mod = 0.0;                     
            ring2_mod = 0.0;                     
            glow_mod = 0.0;                          
        } else {
                                                                 
            if (lost_hp >= 0.9) {                                                    
                glow_mod = 0.7 + 0.15 * sin(flicker_tick * (8.0 + lost_hp * 1.5));
            }

                                                                         
            if (lost_hp >= 1.9) {
                ring2_mod = 0.5 + 0.25 * sin(flicker_tick * (12.0 + lost_hp * 2.0) + 1.0);
                glow_mod = 0.4 + 0.1 * sin(flicker_tick * (10.0 + lost_hp * 2.0));                       
            }

                                                                         
                                                                                                                                   
            if (lost_hp >= 2.9) {
                ring1_mod = 0.3 + 0.25 * sin(flicker_tick * (15.0 + lost_hp * 2.5) + 2.0);
                ring2_mod = 0.2 + 0.1 * sin(flicker_tick * (14.0 + lost_hp * 2.5) + 1.0);                   
                glow_mod = 0.2 + 0.05 * sin(flicker_tick * (12.0 + lost_hp * 2.5));                         
            }
            
                                                     
            if (hp <= 1.0 && hp > 0.01) {                                                                             
                 core_mod = 0.65 + 0.35 * sin(flicker_tick * 10.0);
            }
        }
    }

                                               

           
    float core_rad = 0.04 + 0.005 * sin(anim_time * 25.0);
    float core_d = sdCircle(p_orig, core_rad);
    float core_aa = smoothstep(0.0, 0.005, -core_d);
    color += vec3(0.5, 1.0, 1.0) * core_aa * core_mod;
    alpha = max(alpha, core_aa * core_mod);

                             
    float ring1_rot_angle = -anim_time * 1.5; float ring1_squash = 0.3 + 0.7 * abs(cos(anim_time * 1.5));
    mat2 ring1_invRot = rotate2d(-ring1_rot_angle); mat2 ring1_invScale = mat2(1.0, 0.0, 0.0, 1.0 / ring1_squash);
    vec2 p1 = ring1_invScale * ring1_invRot * p_orig;
    float ring1_rad = 0.1 + 0.01 * cos(anim_time * 18.0); float ring1_d = abs(sdCircle(p1, ring1_rad)) - 0.015 * 0.5;
    float ring1_aa = smoothstep(0.0, 0.004, -ring1_d);
    color += vec3(1.0, 0.3, 0.9) * ring1_aa * 1.5 * ring1_mod;
    alpha = max(alpha, ring1_aa * ring1_mod);

                          
    float ring2_rot_angle = anim_time * 1.1; float ring2_squash = 0.4 + 0.6 * abs(sin(anim_time * 1.1 + 0.5));
    mat2 ring2_invRot = rotate2d(-ring2_rot_angle); mat2 ring2_invScale = mat2(1.0, 0.0, 0.0, 1.0 / ring2_squash);
    vec2 p2 = ring2_invScale * ring2_invRot * p_orig;
    float ring2_rad = 0.18 + 0.01 * sin(anim_time * 12.0); float ring2_d = abs(sdCircle(p2, ring2_rad)) - 0.01 * 0.5;
    float ring2_aa = smoothstep(0.0, 0.003, -ring2_d);
    color += vec3(0.2, 0.9, 0.9) * ring2_aa * ring2_mod;
    alpha = max(alpha, ring2_aa * ring2_mod);

                    
    float base_angle = atan(p_orig.y, p_orig.x); float dist = length(p_orig);
    float spike_rotation_angle = anim_time * 0.8; float rotated_angle = base_angle + spike_rotation_angle;
    float spikes = pow(abs(sin(rotated_angle * 16.0 * 0.5)), 32.0);
    float glow_intensity = pow(max(0.0, 1.0 - dist / 0.5), 5.0);
    glow_intensity *= (0.7 + 5.0 * spikes);
    glow_intensity *= (0.8 + 0.2 * sin(anim_time * 15.0 + dist * 12.0));                               
    glow_intensity *= glow_mod;                           

    vec3 dynamic_glow_col = normalize(vec3(0.5+0.5*sin(color_time+0.0), 0.5+0.5*sin(color_time+2.094395), 0.5+0.5*sin(color_time+4.18879))) * 1.1;
    color += dynamic_glow_col * glow_intensity * 2.0;
    alpha = max(alpha, glow_intensity * 0.6);

    frag_color = vec4(clamp(color, 0.0, 1.0), clamp(alpha, 0.0, 1.0));
}
