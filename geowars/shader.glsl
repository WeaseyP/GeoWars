// File: shader.glsl (Merged Version, with Player Health Display)
//------------------------------------------------------------------------------
@header package main
@header import sg "../sokol/gfx"
@header import m "../math"
@ctype mat4 m.mat4
@ctype vec2 m.vec2
@ctype vec4 m.vec4 // Added for particle color instance data

// --- Background Shaders (Keep existing from older version) ---

@vs vs_bg
in vec2 position; // Location 0
void main() { gl_Position = vec4(position, 0.5, 1.0); }
@end

@fs fs_bg
layout(binding=0) uniform bg_fs_params {
    float tick;
    vec2 resolution;
    int bg_option;
};
out vec4 frag_color;

// --- Utility / Noise Functions (Defined INSIDE fs_bg now) ---
vec3 hash31(float p) { vec3 p3=fract(vec3(p*0.1031,p*0.11369,p*0.13789)); p3+=dot(p3,p3.yzx+19.19); return fract((p3.xxy+p3.yzz)*p3.zyx); }
vec2 hash21(float p) { vec2 p2=fract(vec2(p*0.1031,p*0.11369)); p2+=dot(p2,p2.yx+19.19); return fract((p2.xx+p2.yy)*p2.yx); }
float hash11(float p) { return fract(sin(p*78.233)*43758.5453); }
float noise(vec2 p) { vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f); float v00=hash11(i.x+i.y*57.0); float v10=hash11(i.x+1.0+i.y*57.0); float v01=hash11(i.x+(i.y+1.0)*57.0); float v11=hash11(i.x+1.0+(i.y+1.0)*57.0); return mix(mix(v00,v10,f.x),mix(v01,v11,f.x),f.y); }
float fbm(vec2 p, int o, float per, float lac) { float t=0.0; float f=1.0; float a=0.5; float ma=0.0; for(int i=0;i<o;i++){ t+=noise(p*f)*a; ma+=a; f*=lac; a*=per; } return t/ma; }
float calculate_star_mask(vec2 uv_star, float star_radius, float aa_width) { // Renamed & Simplified
    float max_star_shape = 0.0;
    for (int j = -1; j <= 1; j++) { for (int i = -1; i <= 1; i++) { // Check 3x3 grid
            vec2 grid_cell = floor(uv_star) + vec2(float(i), float(j));
            float cell_id = grid_cell.x + grid_cell.y * 137.0; // Need cell_id for offset hash
            vec2 star_offset = hash21(cell_id + 0.5);
            vec2 star_pos = grid_cell + star_offset;
            float dist_to_star = length(uv_star - star_pos);
            float star_shape = smoothstep(star_radius + aa_width, star_radius, dist_to_star);
            max_star_shape = max(max_star_shape, star_shape);
        } }
    return max_star_shape;
}

void main() { // fs_bg main
    if (bg_option == 0) {
        vec2 xy = fract((gl_FragCoord.xy-vec2(tick)) / 50.0);
        frag_color = vec4(vec3(xy.x*xy.y), 1.0);
    } else {
        vec2 uv_aspect = gl_FragCoord.xy / resolution.y;
        float time = tick;
        vec2 nebula_p = uv_aspect * 0.8 + vec2(time * 0.008, time * 0.003);
        float noise_val = fbm(nebula_p, 5, 0.5, 2.1);
        vec3 deep_space_color=vec3(0.01,0.0,0.03); vec3 nc1=vec3(0.5,0.05,0.25);
        vec3 nc2=vec3(0.1,0.15,0.5); vec3 nhl=vec3(0.8,0.7,0.75);
        vec3 nb=mix(deep_space_color,nc1,smoothstep(0.1,0.5,noise_val));
        vec3 nm=mix(nb,nc2,smoothstep(0.35,0.65,noise_val));
        vec3 fnc=mix(nm,nhl,smoothstep(0.6,0.8,noise_val));
        vec2 star_uv = uv_aspect * 40.0 + time * 0.05;
        float density_thresh = 0.80; float bright_power = 15.0;
        float star_rad = 0.03; float star_aa = 0.06;
        float min_twinkle_bright = 0.6; float overall_star_brightness_multiplier = 1.8;
        float color_shift_speed = 0.2;
        float star_mask = calculate_star_mask(star_uv, star_rad, star_aa);
        vec3 star_light = vec3(0.0);
        if (star_mask > 0.001) {
            vec2 grid_cell = floor(star_uv);
            float cell_id = grid_cell.x + grid_cell.y * 137.0;
            float star_exists_val = hash11(cell_id);
            if (star_exists_val > density_thresh) {
                float base = max(0.0, (star_exists_val - density_thresh) / (1.0 - density_thresh));
                float inherent_brightness = pow(base, bright_power);
                float twinkle_speed_variance = 1.5; float twinkle_base_speed = 0.5;
                float twinkle_speed = twinkle_base_speed + hash11(cell_id + 1.0) * twinkle_speed_variance;
                float sin_wave = 0.5 + 0.5 * sin(time * twinkle_speed + star_exists_val * 6.28318);
                float twinkle = min_twinkle_bright + (1.0 - min_twinkle_bright) * sin_wave;
                float star_color_phase_offset = hash11(cell_id + 1.23) * 6.28318;
                vec3 final_star_color = vec3(
                    0.5 + 0.5 * sin(time * color_shift_speed + star_color_phase_offset + 0.0),
                    0.5 + 0.5 * sin(time * color_shift_speed + star_color_phase_offset + 2.094395),
                    0.5 + 0.5 * sin(time * color_shift_speed + star_color_phase_offset + 4.18879)
                );
                star_light = final_star_color * inherent_brightness * twinkle * overall_star_brightness_multiplier;
            }
        }
        vec3 final_color = fnc * 0.9 + star_light * star_mask;
        frag_color = vec4(clamp(final_color, 0.0, 1.0), 1.0);
    }
}
@end
@program bg vs_bg fs_bg

// --- Player Shaders (With Health Display) ---

@vs vs_player
layout(binding=0) uniform Player_Vs_Params { mat4 mvp; };
in vec2 position;
out vec2 v_uv;
void main() {
    gl_Position = mvp * vec4(position.xy, 0.0, 1.0);
    v_uv = position.xy * 0.5 + 0.5;
}
@end

@fs fs_player
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

    // --- Define Default Component Colors ---
    vec3 color_core_default = vec3(0.5, 1.0, 1.0);    // Bright Cyan
    vec3 color_ring1_default = vec3(1.0, 0.3, 0.9);   // Magenta
    vec3 color_ring2_health_based = vec3(0.2, 0.5, 1.0); // Default Blue for Ring 2 (full HP)
    vec3 color_glow_dynamic = normalize(vec3(0.5+0.5*sin(color_time+0.0), 0.5+0.5*sin(color_time+2.094395), 0.5+0.5*sin(color_time+4.18879))) * 1.1;

    // --- Determine Persistent Health Color for Ring 2 ---
    if (hp <= 0.01) { 
        color_ring2_health_based = vec3(0.1, 0.1, 0.1); // Very dark for Ring 2 on death (it will be alpha'd out anyway)
    } else if (max_hp > 1.0) {
        float health_fraction = hp / max_hp;
        if (health_fraction <= 0.25) { 
            color_ring2_health_based = vec3(1.0, 0.2, 0.1); // Red
        } else if (health_fraction <= 0.5) { 
            color_ring2_health_based = vec3(1.0, 0.8, 0.1); // Yellow
        } else if (health_fraction <= 0.75) { 
            color_ring2_health_based = vec3(0.2, 1.0, 0.2); // Green
        }
        // Else it remains Blue (initial value)
    } else if (hp < max_hp && max_hp == 1.0) { // Max HP is 1 and took a hit
         color_ring2_health_based = vec3(1.0, 0.2, 0.1); // Red
    }


    // --- Calculate Component Alphas & Apply Death State ---
    float core_alpha = 0.0;
    float ring1_alpha = 0.0;
    float ring2_alpha = 0.0;
    float glow_alpha_contrib = 0.0;

    // Core
    float core_rad_anim = 0.04 + 0.005 * sin(anim_time * 25.0);
    float core_dist_sdf = sdCircle(p_orig, core_rad_anim);
    core_alpha = smoothstep(0.005, 0.0, core_dist_sdf); 
    if (hp <= 0.01) core_alpha *= (0.15 + 0.1 * sin(direct_tick * 35.0));

    // Ring 1
    float r1_rot = -anim_time * 1.5; float r1_squash = 0.3 + 0.7 * abs(cos(anim_time * 1.5));
    mat2 r1_invRot = rotate2d(-r1_rot); mat2 r1_invScale = mat2(1.0, 0.0, 0.0, 1.0 / r1_squash);
    vec2 p1_uv = r1_invScale * r1_invRot * p_orig;
    float r1_rad_anim = 0.1 + 0.01 * cos(anim_time * 18.0);
    float r1_thick = 0.015;
    float r1_dist_sdf = abs(sdCircle(p1_uv, r1_rad_anim)) - r1_thick * 0.5;
    ring1_alpha = smoothstep(0.004, 0.0, r1_dist_sdf);
    if (hp <= 0.01) ring1_alpha = 0.0;

    // Ring 2
    float r2_rot = anim_time * 1.1; float r2_squash = 0.4 + 0.6 * abs(sin(anim_time * 1.1 + 0.5));
    mat2 r2_invRot = rotate2d(-r2_rot); mat2 r2_invScale = mat2(1.0, 0.0, 0.0, 1.0 / r2_squash);
    vec2 p2_uv = r2_invScale * r2_invRot * p_orig;
    float r2_rad_anim = 0.18 + 0.01 * sin(anim_time * 12.0);
    float r2_thick = 0.01;
    float r2_dist_sdf = abs(sdCircle(p2_uv, r2_rad_anim)) - r2_thick * 0.5;
    ring2_alpha = smoothstep(0.003, 0.0, r2_dist_sdf);
    if (hp <= 0.01) ring2_alpha = 0.0;

    // Glow & Spikes
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

    // --- Combine Colors Additively & Determine Final Alpha ---
    vec3 combined_color = vec3(0.0);
    combined_color += color_glow_dynamic * glow_alpha_contrib * 2.0; // Glow is more of an additive effect
    combined_color += color_ring2_health_based * ring2_alpha;
    combined_color += color_ring1_default * 1.5 * ring1_alpha; // Apply brightness multiplier here
    combined_color += color_core_default * core_alpha;
    
    float final_alpha = max(max(core_alpha, ring1_alpha), max(ring2_alpha, glow_alpha_contrib));


    // --- Apply Flash Overlay (if invulnerable and alive) ---
    if (invul_timer > 0.001 && invul_duration > 0.001 && hp > 0.01) {
        float invul_ratio = invul_timer / invul_duration;
        float flash_pulse = 0.5 + 0.5 * sin(direct_tick * 60.0 + invul_ratio * 20.0); 
        float flash_amount = pow(invul_ratio, 1.0) * flash_pulse; 
        flash_amount = clamp(flash_amount * 1.5, 0.0, 1.0); // Make flash effect strong

        vec3 flash_overlay_color = vec3(1.0, 1.0, 1.0); // Bright white flash

        // Add the flash color to the combined_color
        // The flash will make all visible parts brighter and whiter.
        combined_color += flash_overlay_color * flash_amount * final_alpha; 
    }
    
    frag_color = vec4(clamp(combined_color, 0.0, 1.0), clamp(final_alpha, 0.0, 1.0));
}
@end
@program player vs_player fs_player


// --- Particle Shaders (Copied from newer code) ---

@vs vs_particle
layout(binding=0) uniform particle_vs_params { mat4 view_proj; };

layout(location=0) in vec2 quad_pos; 
layout(location=1) in vec2 quad_uv;  

layout(location=2) in vec4 instance_pos_size_rot; 
layout(location=3) in vec4 instance_color;        

out vec4 particle_color;
out vec2 particle_uv;
out float particle_dist; 

void main() {
    vec2 inst_pos = instance_pos_size_rot.xy;
    float inst_size = instance_pos_size_rot.z;
    float inst_rot = instance_pos_size_rot.w;

    float cr = cos(inst_rot); float sr = sin(inst_rot);
    mat2 rot_mat = mat2(cr, -sr, sr, cr);
    vec2 final_local_pos = rot_mat * (quad_pos * inst_size);
    vec2 final_world_pos = final_local_pos + inst_pos;
    gl_Position  = view_proj * vec4(final_world_pos, 0.0, 1.0);

    particle_color = instance_color; 
    particle_uv = quad_uv;
    particle_dist = length(quad_pos); 
}
@end

@fs fs_particle
layout(binding=1) uniform particle_fs_params { float tick; };

in vec4 particle_color;
in vec2 particle_uv;
in float particle_dist; 

out vec4 frag_color;

void main() {
    vec2 uv_centered = particle_uv - vec2(0.5);
    float angle = atan(uv_centered.y, uv_centered.x);
    float dist_from_center = particle_dist; 

    float core_radius = 0.1;
    float swirl_start_radius = 0.15;
    float swirl_speed = -4.5;
    float swirl_freq = 6.0;
    float radial_speed_factor = 2.0; 

    vec3 color_dark_purple = vec3(0.3, 0.0, 0.5);
    vec3 color_bright_purple = vec3(0.8, 0.3, 1.0);
    vec3 color_black = vec3(0.0, 0.0, 0.0);

    float swirl_value = sin(angle * swirl_freq + dist_from_center * radial_speed_factor + tick * swirl_speed);
    swirl_value = swirl_value * 0.5 + 0.5;
    swirl_value = smoothstep(0.4, 0.6, swirl_value);

    vec3 swirl_color = mix(color_dark_purple, color_bright_purple, swirl_value);

    float core_mix_factor = smoothstep(core_radius, swirl_start_radius, dist_from_center);
    vec3 final_rgb = mix(color_black, swirl_color, core_mix_factor);

    float final_alpha = particle_color.a; 

    frag_color = vec4(final_rgb, final_alpha);
}
@end
@program particle vs_particle fs_particle


// --- Blackhole Projectile Shaders ---
@vs vs_blackhole
// ... (vs_blackhole remains the same) ...
layout(binding=0) uniform blackhole_vs_params { mat4 view_proj; };
layout(location=0) in vec2 quad_pos; 
layout(location=1) in vec2 quad_uv;  
layout(location=2) in vec4 instance_pos_size_rot; 
layout(location=3) in vec4 instance_color;        
out vec4 bh_color_out;
out vec2 bh_uv_out;
void main() {
    vec2 inst_pos = instance_pos_size_rot.xy;
    float inst_size = instance_pos_size_rot.z;
    float inst_rot = instance_pos_size_rot.w;
    float cr = cos(inst_rot); float sr = sin(inst_rot);
    mat2 rot_mat = mat2(cr, -sr, sr, cr);
    vec2 final_local_pos = rot_mat * (quad_pos * inst_size);
    vec2 final_world_pos = final_local_pos + inst_pos;
    gl_Position  = view_proj * vec4(final_world_pos, 0.0, 1.0);
    bh_color_out = instance_color; 
    bh_uv_out = quad_uv;
}
@end

@fs fs_blackhole
layout(binding=1) uniform blackhole_fs_params { float tick; };

in vec4 bh_color_out; // .a is life_ratio
in vec2 bh_uv_out;

out vec4 frag_color;

void main() {
    vec2 uv_centered = bh_uv_out - vec2(0.5); 

    // --- Main Body Shape ---
    float body_uv_half_width = 0.15; 
    float body_uv_half_length = 0.40; // Slightly shorter than before to make tail more distinct
    float body_ref_radius = 1.0;
    vec2 body_oval_scale = vec2(body_ref_radius / body_uv_half_width, body_ref_radius / body_uv_half_length);
    float dist_for_body_mask = length(uv_centered * body_oval_scale);
    float body_aa = 0.1; 
    float body_shape_alpha = 1.0 - smoothstep(body_ref_radius - body_aa, body_ref_radius + body_aa, dist_for_body_mask);

    if (body_shape_alpha < 0.01 && bh_color_out.a < 0.01) { // Discard if fully transparent from shape and lifetime
        discard;
    }

    // --- Swirl Calculation (for body color) ---
    float dist_from_center_for_swirl = length(uv_centered); // Swirl based on circular distance
    float angle = atan(uv_centered.y, uv_centered.x);
    float swirl_speed = -7.0; // Slightly faster swirl       
    float swirl_angular_freq = 8.0;  
    float swirl_radial_freq = 5.0;   
    float swirl_time_offset_factor = 0.25; 
    float swirl_value = sin(
        dist_from_center_for_swirl * swirl_radial_freq * (1.0 + 0.5 * sin(tick * swirl_time_offset_factor)) + 
        tick * swirl_speed
    );
    swirl_value = swirl_value * 0.5 + 0.5; 
    swirl_value = smoothstep(0.3, 0.7, swirl_value); // Adjusted smoothstep for potentially more contrast

    vec3 color_core_black = vec3(0.0, 0.0, 0.0);
    vec3 color_swirl_dark = vec3(0.1, 0.0, 0.2); // Slightly darker base swirl
    vec3 color_swirl_bright = vec3(0.7, 0.3, 0.9); // Brighter swirl highlight

    vec3 body_swirl_color = mix(color_swirl_dark, color_swirl_bright, swirl_value);
    float core_radius_effect = 0.18; // Slightly smaller core for more swirl visibility
    float core_influence = 1.0 - smoothstep(0.0, core_radius_effect, dist_from_center_for_swirl);
    vec3 body_base_rgb = mix(body_swirl_color, color_core_black, core_influence);

    // --- Glow and Tail Calculation ---
    vec3 glow_color = vec3(1.0, 0.7, 1.0) * 5.8; // Very bright, slightly pinkish-purple glow, boosted

    // Glow shape: wider and significantly longer than the body, especially at the tail
    float glow_uv_half_width = body_uv_half_width * 1.8; // Glow is wider
    float glow_uv_base_half_length = body_uv_half_length * 1.5; // Base length for the glow head

    // Tailing effect: elongate the glow towards the rear (negative uv_centered.y)
    // -uv_centered.y: positive at rear, negative at front. Ranges from 0.5 to -0.5.
    // tail_elongation_factor: 1.0 (no elongation) at front, up to ~2.5-3.0 at rear.
    float tail_elongation_factor = 1.0 + max(0.0, -uv_centered.y * 3.0); // Increase multiplier for longer tail
    float dynamic_glow_uv_half_length = glow_uv_base_half_length * tail_elongation_factor;

    vec2 glow_oval_scale = vec2(body_ref_radius / glow_uv_half_width, body_ref_radius / dynamic_glow_uv_half_length);
    float dist_for_glow_mask = length(uv_centered * glow_oval_scale);
    
    float glow_aa = 0.15; // Softer antialiasing for glow
    float glow_shape_alpha = 1.0 - smoothstep(body_ref_radius - glow_aa, body_ref_radius + glow_aa, dist_for_glow_mask);

    // Modulate glow intensity: strongest at the "core" of the glow area and along the tail's spine
    float glow_intensity_bias = (1.0 - smoothstep(0.0, 0.4, abs(uv_centered.x))); // Stronger along Y-axis spine
    glow_intensity_bias *= (0.5 + 0.5 * smoothstep(-0.5, 0.5, -uv_centered.y)); // Stronger towards rear

    float effective_glow_strength = glow_shape_alpha * glow_intensity_bias * 0.8; // Base strength for glow

    // --- Combine Colors and Alpha ---
    float lifetime_alpha = bh_color_out.a; 
    float base_projectile_opacity = 0.80; // Overall opacity for the effect

    // Add glow to body color
    vec3 final_rgb = body_base_rgb + glow_color * effective_glow_strength;
    
    // Final alpha is the max of body or glow shape, then modulated by lifetime & base opacity
    float combined_shape_alpha = max(body_shape_alpha, effective_glow_strength);
    float overall_alpha = combined_shape_alpha * lifetime_alpha * base_projectile_opacity;

    frag_color = vec4(clamp(final_rgb, 0.0, 2.5), clamp(overall_alpha, 0.0, 1.0)); // Allow even brighter for bloom
}
@end
@program blackhole vs_blackhole fs_blackhole


// --- Enemy Shaders ---
@vs vs_enemy
// ... (vs_enemy remains the same) ...
layout(binding=0) uniform enemy_vs_params { mat4 view_proj; };
layout(location=0) in vec2 quad_pos; 
layout(location=1) in vec2 quad_uv;  
layout(location=2) in vec4 instance_pos_size_rot; 
layout(location=3) in vec4 instance_color_in;     
out vec4 enemy_color_out;
out vec2 enemy_uv_out;
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
}
@end

@fs fs_enemy
// ... (fs_enemy remains the same) ...
layout(binding=1) uniform enemy_fs_params { float tick; };
in vec4 enemy_color_out; 
in vec2 enemy_uv_out;    
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
    vec2 uv_centered = enemy_uv_out - vec2(0.5);
    vec2 rectangle_half_dims = vec2(0.32, 0.12); 
    float aa = 0.025;
    float pi = 3.14159265358979323846;
    float internal_yaw_speed = 1.2; 
    float internal_rotation1 = (pi / 4.0) + tick * internal_yaw_speed; 
    vec2 uv1_rotated = rotate2d(internal_rotation1) * uv_centered; 
    float dist1 = sdf_rectangle(uv1_rotated, rectangle_half_dims);
    vec3 color1_tip = enemy_color_out.rgb * 1.6 + vec3(0.3, 0.2, 0.3); 
    vec3 gradient_color1 = mix(color1_tip, enemy_color_out.rgb, smoothstep(-0.5, 0.5, uv1_rotated.y * 1.5)); 
    float alpha_sdf1 = smoothstep(aa, 0.0, dist1); 
    float internal_rotation2 = (-pi / 4.0) - tick * internal_yaw_speed; 
    vec2 uv2_rotated = rotate2d(internal_rotation2) * uv_centered;
    float dist2 = sdf_rectangle(uv2_rotated, rectangle_half_dims);
    vec3 color2_tip = enemy_color_out.rgb * 0.7 - vec3(0.1, 0.0, 0.1); 
    vec3 gradient_color2 = mix(color2_tip, enemy_color_out.rgb, smoothstep(-0.5, 0.5, uv2_rotated.x * 1.5));
    float alpha_sdf2 = smoothstep(aa, 0.0, dist2); 
    vec4 frag1 = vec4(gradient_color1, alpha_sdf1 * enemy_color_out.a);
    vec4 frag2 = vec4(gradient_color2, alpha_sdf2 * enemy_color_out.a);
    vec3 blended_rgb = frag2.rgb * frag2.a + frag1.rgb * (1.0 - frag2.a);
    float blended_alpha = frag2.a + frag1.a * (1.0 - frag2.a);
    frag_color = vec4(blended_rgb, blended_alpha);
    if (frag_color.a < 0.01) {
        discard;
    }
}
@end
@program enemy vs_enemy fs_enemy