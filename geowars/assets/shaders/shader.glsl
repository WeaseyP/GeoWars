// File: shader.glsl (Merged Version, with Player Health Display)
//------------------------------------------------------------------------------
@header package shared
@header import sg "../vendor/sokol/gfx"
@header import m "../vendor/math"
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
    vec2 cam_offset; // Renamed from offset
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

// SDF for an octagon
float sdOctagon( in vec2 p, in float r ) {
  const vec3 k = vec3(-0.9238795325, 0.3826834323, 0.4142135623 ); // cos(22.5), sin(22.5), tan(22.5)
  p = abs(p);
  p -= 2.0*min(dot(vec2( k.x,k.y),p),0.0)*vec2( k.x,k.y);
  p -= 2.0*min(dot(vec2(-k.x,k.y),p),0.0)*vec2(-k.x,k.y);
  p -= vec2(clamp(p.x, -k.z*r, k.z*r), r);
  return length(p)*sign(p.y);
}

void main() { // fs_bg main
    vec3 final_color = vec3(0.0);
    float final_alpha = 1.0;

    // Calculate world position for the current fragment
    // Normalized to View Height (Height = 1.0 in uv space).
    // View Height in World Units is 14.0 (2 * ORTHO_HEIGHT = 2 * 7.0).
    vec2 world_uv = (gl_FragCoord.xy - resolution * 0.5) / resolution.y;
    world_uv.y = -world_uv.y; // Flip Y for Top-Left Origin (D3D11/Windows) match to Y-Up World
    vec2 pixel_world_pos = world_uv * 14.0 + cam_offset; 

    if (bg_option == 0) {
        // Simple grid, apply parallax to gl_FragCoord
        vec2 parallax_coord = gl_FragCoord.xy - cam_offset * 0.1; // Small parallax
        vec2 xy = fract((parallax_coord - vec2(tick)) / 50.0);
        final_color = vec3(xy.x*xy.y);
    } else {
        // Nebula and stars, apply parallax to UVs
        // Parallax boosted from 0.05 to 0.2 for better motion sense
        vec2 uv_aspect = (gl_FragCoord.xy - cam_offset * 0.2) / resolution.y; 
        float time = tick;
        vec2 nebula_p = uv_aspect * 0.8 + vec2(time * 0.008, time * 0.003);
        float noise_val = fbm(nebula_p, 5, 0.5, 2.1);
        vec3 deep_space_color=vec3(0.01,0.0,0.03); vec3 nc1=vec3(0.5,0.05,0.25);
        vec3 nc2=vec3(0.1,0.15,0.5); vec3 nhl=vec3(0.8,0.7,0.75);
        vec3 nb=mix(deep_space_color,nc1,smoothstep(0.1,0.5,noise_val));
        vec3 nm=mix(nb,nc2,smoothstep(0.35,0.65,noise_val));
        vec3 fnc=mix(nm,nhl,smoothstep(0.6,0.8,noise_val));
        
        // Parallax boosted from 0.2 to 0.8 for stars (faster layer)
        vec2 star_uv = (gl_FragCoord.xy - cam_offset * 0.8) / resolution.y * 40.0 + time * 0.05; 
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
        final_color = fnc * 0.9 + star_light * star_mask;
        
        // --- Speed Grid ---
        // Adds sense of motion
        vec2 grid_uv = (pixel_world_pos * 1.5); // Grid scale
        vec2 grid_f = fract(grid_uv);
        float grid_line = smoothstep(0.95, 0.96, grid_f.x) + smoothstep(0.95, 0.96, grid_f.y);
        final_color += vec3(0.05, 0.1, 0.2) * grid_line * 0.5; // Subtle blue grid
    }

    // --- Arena Boundary (Hexagon) ---
    // Flat-Topped Hexagon (Matches physics)
    // Radius (apothem/dist to wall) = 14.0 * 0.866 = 12.12? 
    // Wait, ARENA_HEX_RADIUS (14.0) usually refers to circumradius (center to vertex).
    // Physics used hex_dist = 14.0 * 0.866.
    // Let's use standard sdHexagon and verify size.
    
    float hex_radius = 14.0; 
    
    // Inigo Quilez sdHexagon (Pointy Topped)
    // To match Flat Topped (walls at Y), we rotate p by 90 deg or swap x/y.
    // But let's check standard orientation.
    // Pointy top has vertex at (0, R). Flat top has edge at (0, R*cos30).
    // My physics enforces walls at Y = +/- 12.12.
    // This defines a Flat Topped Hexagon.
    
    // SDF for Pointy Hexagon
    // float sdHexagon( in vec2 p, in float r )
    // {
    //     const vec3 k = vec3(-0.866025404, 0.5, 0.577350269);
    //     p = abs(p);
    //     p -= 2.0*min(dot(k.xy, p), 0.0)*k.xy;
    //     p -= vec2(clamp(p.x, -k.z*r, k.z*r), r);
    //     return length(p)*sign(p.y);
    // }
    
    vec2 p_hex = pixel_world_pos.yx; // Swap X/Y for Flat Top alignment
    p_hex = abs(p_hex);
    
    const vec3 k = vec3(-0.866025404, 0.5, 0.577350269);
    p_hex -= 2.0*min(dot(k.xy, p_hex), 0.0)*k.xy;
    p_hex -= vec2(clamp(p_hex.x, -k.z*hex_radius, k.z*hex_radius), hex_radius);
    
    float dist_to_boundary = length(p_hex)*sign(p_hex.y);

    float boundary_thickness = 0.4; 
    float boundary_glow_falloff = 3.0;
    float boundary_intensity = 2.0;

    float boundary_alpha = smoothstep(boundary_thickness, 0.0, abs(dist_to_boundary));
    vec3 boundary_color = vec3(0.0, 1.0, 1.0); // Cyan

    float glow_factor = exp(-abs(dist_to_boundary) * boundary_glow_falloff);
    final_color += boundary_color * glow_factor * boundary_intensity;
    
    // --- The Void Mask ---
    // If outside hexagon, darken significantly
    if (dist_to_boundary > 0.05) {
        // Smooth falloff into void
        float void_alpha = smoothstep(0.05, 0.5, dist_to_boundary);
        final_color = mix(final_color, vec3(0.0), void_alpha); 
        // Or discard? Discard might look aliased.
        // Let's just multiply by (1-void_alpha)
        final_alpha *= (1.0 - void_alpha);
    }
    
    frag_color = vec4(clamp(final_color, 0.0, 1.0), final_alpha);
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
    vec2 dash_trail_positions;
    float dash_trail_count_uniform;
    float is_dashing_uniform;
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


    // --- Define Player Glow Color ---
    vec3 player_glow_color = color_ring2_health_based; // Base glow on health ring color

    // --- Calculate Component Alphas & Apply Death State ---
    float core_alpha = 0.0;
    float ring1_alpha = 0.0;
    float ring2_alpha = 0.0;
    float glow_alpha_contrib = 0.0;
    float glow_shape_alpha = 0.0; // Initialize new glow alpha

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

    // --- SDF for Health-Based Glow ---
    float glow_radius = r2_rad_anim + 0.05; // Glow slightly larger than the outer ring
    float glow_dist_sdf = sdCircle(p_orig, glow_radius);

    // --- Calculate Alpha for Health-Based Glow ---
    glow_shape_alpha = 0.5 * smoothstep(0.025, 0.0, glow_dist_sdf); // Adjust 0.5 for intensity, 0.025 for spread
    if (hp <= 0.01) glow_shape_alpha = 0.0; // No glow on death

    // Glow & Spikes (existing dynamic glow)
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
    combined_color += player_glow_color * glow_shape_alpha; // Health-based glow first (behind other elements)
    combined_color += color_glow_dynamic * glow_alpha_contrib * 2.0; // Existing dynamic glow/spikes
    combined_color += color_ring2_health_based * ring2_alpha;
    combined_color += color_ring1_default * 1.5 * ring1_alpha; // Apply brightness multiplier here
    combined_color += color_core_default * core_alpha;
    
    float final_alpha = max(max(max(core_alpha, ring1_alpha), max(ring2_alpha, glow_alpha_contrib)), glow_shape_alpha); // Include new glow_shape_alpha

    // --- Apply Flash Overlay (if invulnerable and alive) ---
    if (invul_timer > 0.001 && invul_duration > 0.001 && hp > 0.01) {
        float invul_ratio = invul_timer / invul_duration;
        float flash_pulse = 0.5 + 0.5 * sin(direct_tick * 60.0 + invul_ratio * 20.0); 
        float flash_amount = pow(invul_ratio, 1.0) * flash_pulse; 
        flash_amount = clamp(flash_amount * 1.5, 0.0, 1.0); // Make flash effect strong

        vec3 flash_overlay_color = vec3(1.0, 1.0, 1.0); // Bright white flash
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

    float tail_elongation_factor = 1.0 + max(0.0, -uv_centered.y * 3.0); // Increase multiplier for longer tail
    float dynamic_glow_uv_half_length = glow_uv_base_half_length * tail_elongation_factor;

    vec2 glow_oval_scale = vec2(body_ref_radius / glow_uv_half_width, body_ref_radius / dynamic_glow_uv_half_length);
    float dist_for_glow_mask = length(uv_centered * glow_oval_scale);
    
    float glow_aa = 0.15; // Softer antialiasing for glow
    float glow_shape_alpha = 1.0 - smoothstep(body_ref_radius - glow_aa, body_ref_radius + glow_aa, dist_for_glow_mask);

    float glow_intensity_bias = (1.0 - smoothstep(0.0, 0.4, abs(uv_centered.x))); // Stronger along Y-axis spine
    glow_intensity_bias *= (0.5 + 0.5 * smoothstep(-0.5, 0.5, -uv_centered.y)); // Stronger towards rear

    float effective_glow_strength = glow_shape_alpha * glow_intensity_bias * 0.8; // Base strength for glow

    // --- Combine Colors and Alpha ---
    float lifetime_alpha = bh_color_out.a; 
    float base_projectile_opacity = 0.80; // Overall opacity for the effect
    vec3 final_rgb = body_base_rgb + glow_color * effective_glow_strength;
    float combined_shape_alpha = max(body_shape_alpha, effective_glow_strength);
    float overall_alpha = combined_shape_alpha * lifetime_alpha * base_projectile_opacity;

    frag_color = vec4(clamp(final_rgb, 0.0, 2.5), clamp(overall_alpha, 0.0, 1.0)); // Allow even brighter for bloom
}
@end
@program blackhole vs_blackhole fs_blackhole

// --- Line Shader (For Grid) ---
@vs vs_line
in vec3 position;
in vec4 color0;

out vec4 color;

layout(binding=0) uniform line_vs_params {
    mat4 mvp;
};

void main() {
    gl_Position = mvp * vec4(position, 1.0);
    color = color0;
}
@end

@fs fs_line
in vec4 color;
out vec4 frag_color;

void main() {
    frag_color = color;
}
@end

@program line vs_line fs_line

@vs vs_enemy
layout(binding=0) uniform enemy_vs_params { mat4 view_proj; };
layout(location=0) in vec2 quad_pos_in;    
layout(location=1) in vec2 quad_uv_in;     
layout(location=2) in vec2 instance_pos_vs_in;
layout(location=3) in float instance_main_rotation_vs_in;
layout(location=4) in float instance_visual_scale_vs_in;  
layout(location=5) in vec4 instance_color_vs_in;      
layout(location=6) in vec4 instance_effect_params_vs_in; 
layout(location=7) in float instance_enemy_type_vs_in; 
out vec4 enemy_color_out_fs;
out vec2 enemy_uv_out_fs;
out vec4 enemy_effect_params_fs; 
out float enemy_visual_scale_fs_out;
out float v_enemy_type_fs; 
out float v_enemy_main_rotation_fs;
void main() {
    float final_size_for_quad = instance_visual_scale_vs_in; 
    float cr = cos(instance_main_rotation_vs_in);
    float sr = sin(instance_main_rotation_vs_in);
    mat2 main_rot_mat = mat2(cr, -sr, sr, cr);
    vec2 scaled_quad_pos = quad_pos_in * final_size_for_quad; 
    vec2 rotated_quad_pos = main_rot_mat * scaled_quad_pos; // This rotates the quad itself
                                                           // For boss, instance_main_rotation_vs_in is for aiming, not quad orientation.
                                                           // The quad for the boss should probably remain unrotated (or have a base rotation if sprite isn't aligned)
                                                           // If the quad is rotated by v_enemy_main_rotation_fs, then uv_centered calculations in FS might be off
                                                           // if they assume a non-rotated quad. Let's assume boss quad is not rotated by this aiming angle.
    if (instance_enemy_type_vs_in > 1.5 && instance_enemy_type_vs_in < 2.5) { // BOSS_CHROME_ORB
         rotated_quad_pos = scaled_quad_pos; // No instance-level rotation for boss quad, its visuals are rotation-invariant or handled in FS
    }


    vec2 final_world_pos = rotated_quad_pos + instance_pos_vs_in;
    gl_Position = view_proj * vec4(final_world_pos, 0.0, 1.0);
    enemy_color_out_fs = instance_color_vs_in;
    enemy_uv_out_fs = quad_uv_in; 
    enemy_effect_params_fs = instance_effect_params_vs_in;
    enemy_visual_scale_fs_out = instance_visual_scale_vs_in; // This is current_size * 3.0
    v_enemy_type_fs = instance_enemy_type_vs_in; 
    v_enemy_main_rotation_fs = instance_main_rotation_vs_in; // This is the aiming angle
}
@end
@fs fs_enemy
layout(binding=1) uniform enemy_fs_params { float tick; };

in vec4 enemy_color_out_fs; 
in vec2 enemy_uv_out_fs;    
in vec4 enemy_effect_params_fs; 
in float enemy_visual_scale_fs_out;  // This is world_size * 3.0
in float v_enemy_type_fs; 
in float v_enemy_main_rotation_fs; // Boss aiming angle

out vec4 frag_color;

const float PI = 3.14159265359;
// Constants for BOSS_CHROME_ORB enemy type, could be uniforms if they need to vary
// These are in world units. We'll convert them to scaled_uv space.
const float ENEMY_BOSS_CHROME_ORB_WORLD_SCALE = 0.5; // From Odin PLAYER_SCALE * 2.5 approx

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
    vec2 uv_centered = enemy_uv_out_fs - vec2(0.5); // Ranges -0.5 to 0.5 for the base quad
    const float enemy_visual_scale_on_quad = 3.0; // Internal scaling factor for shader's working UV space

    // --- BOSS_CHROME_ORB Rendering Path ---
    if (v_enemy_type_fs > 1.5 && v_enemy_type_fs < 2.5) { // BOSS_CHROME_ORB (type 2.0)
        // p_scaled_uv is the coordinate space where SDFs are defined, ranges roughly -1.5 to 1.5
        vec2 p_scaled_uv = uv_centered * enemy_visual_scale_on_quad;

        float sphere_radius_scaled_uv = 0.45 / 5.0; 
        float dist_to_center_scaled_uv = length(p_scaled_uv);
        float sphere_sdf = dist_to_center_scaled_uv - sphere_radius_scaled_uv;
        float sphere_aa = 0.02;
        float sphere_alpha = smoothstep(sphere_aa, 0.0, sphere_sdf);

        vec3 base_orb_color = vec3(0.75, 0.75, 0.8); 
        vec3 highlight_color = vec3(1.0, 1.0, 1.0);
        float highlight_pos = 0.3; 
        // Highlight independent of boss rotation, simple X-based highlight on the sphere
        float highlight_intensity = smoothstep(0.0, 0.8, max(0.0, p_scaled_uv.x + highlight_pos)); 
        vec3 orb_color = mix(base_orb_color, highlight_color, highlight_intensity * 0.5);

        // Black circle ("eye") orbits the main sphere, aligned with v_enemy_main_rotation_fs (aiming direction)
        float circle_orbit_radius_scaled_uv = sphere_radius_scaled_uv * 0.6;
        // Corrected: black circle at the front, aligned with aiming direction
        vec2 black_circle_center_offset_scaled_uv = vec2(cos(v_enemy_main_rotation_fs), sin(v_enemy_main_rotation_fs)) * circle_orbit_radius_scaled_uv;
        
        float black_circle_radius_scaled_uv = 0.1 / 5.0;
        // SDF for black circle relative to its own center
        float black_circle_sdf = length(p_scaled_uv - black_circle_center_offset_scaled_uv) - black_circle_radius_scaled_uv;
        float black_circle_aa = 0.015;
        float black_circle_alpha = smoothstep(black_circle_aa, 0.0, black_circle_sdf);

        vec3 final_boss_color_rgb = mix(orb_color, vec3(0.0, 0.0, 0.0), black_circle_alpha); 
        float combined_alpha = sphere_alpha; // Base alpha from sphere

        // Vision Rectangle Visualization (NOW THE DEATH LASER)
        float is_dying = enemy_effect_params_fs.x;
        vec3 laser_color_core = vec3(1.0, 0.5, 0.5);    // Bright Reddish Core
        // vec3 laser_color_glow = vec3(1.0, 0.2, 0.2); // Not used directly for now
        float laser_alpha = 0.0;

        if (is_dying < 0.5) { // Only draw laser if not dying
            float vision_rect_width_world = enemy_effect_params_fs.z;  // This is ENEMY_BOSS_VISION_RECT_WIDTH (world units)
            float vision_rect_length_world = enemy_effect_params_fs.w; // This is ENEMY_BOSS_VISION_RANGE (world units)

            // enemy_visual_scale_fs_out is (world_size_of_boss_entity * 3.0)
            // To convert world units (like vision_rect_width_world) to the p_scaled_uv space (where extent is 1.5):
            // world_unit_in_p_scaled_uv = world_unit * (1.5 / (enemy_visual_scale_fs_out / 2.0) )
            // world_unit_in_p_scaled_uv = world_unit * (3.0 / enemy_visual_scale_fs_out)
            // This is effectively: world_unit / world_size_of_boss_entity
            
            // Simpler: enemy_visual_scale_fs_out already contains current_size * 3.0.
            // The p_scaled_uv space is uv_centered * 3.0.
            // A distance D in world units corresponds to D / (current_size / 2.0) in uv_centered units (approx if current_size is diameter).
            // Or D / (enemy_visual_scale_fs_out / (2.0 * 3.0) )
            // D * 6.0 / enemy_visual_scale_fs_out in uv_centered units.
            // Then D * 6.0 / enemy_visual_scale_fs_out * 3.0 in p_scaled_uv units.
            // = D * 18.0 / enemy_visual_scale_fs_out

            // Let's use the provided world_to_working_uv_factor logic path, ensure factors are correct.
            // enemy_visual_scale_fs_out is instance_visual_scale_vs_in from VS, which is current_size * 3.0 from Odin.
            // float world_to_working_uv_factor = enemy_visual_scale_on_quad / (enemy_visual_scale_fs_out / enemy_visual_scale_on_quad); ??? No.
            // world_to_working_uv_factor should convert world units to p_scaled_uv units.
            // 1 unit in p_scaled_uv = ( (enemy_visual_scale_fs_out / enemy_visual_scale_on_quad) / 2.0 ) / 1.5 world units.
            // = ( (current_size*3.0 / 3.0) / 2.0 ) / 1.5 = (current_size / 2.0) / 1.5 = current_size / 3.0 world units.
            // So, 1 world unit = 3.0 / current_size in p_scaled_uv units.
            float world_to_p_scaled_uv_factor;
            if (enemy_visual_scale_fs_out > 0.001) { // Check if enemy_visual_scale_fs_out is not zero
                 world_to_p_scaled_uv_factor = enemy_visual_scale_on_quad / enemy_visual_scale_fs_out;
            } else {
                 world_to_p_scaled_uv_factor = 1.0; // Avoid division by zero, assign a fallback
            }
            float rect_width_p_scaled_uv = vision_rect_width_world * world_to_p_scaled_uv_factor; 
            float rect_length_p_scaled_uv = vision_rect_length_world * world_to_p_scaled_uv_factor * 100;

            // Laser Direction (same as boss aiming direction)
            vec2 vision_direction = normalize(vec2(cos(v_enemy_main_rotation_fs), sin(v_enemy_main_rotation_fs)));
            
            // Laser Origin (center of the black circle, in p_scaled_uv space)
            vec2 laser_origin_p_scaled_uv = black_circle_center_offset_scaled_uv; 
            
            // Current fragment's position relative to laser origin
            vec2 pixel_rel_to_laser_origin_p_scaled_uv = p_scaled_uv - laser_origin_p_scaled_uv;

            // Project onto laser's local axes
            float local_x = dot(pixel_rel_to_laser_origin_p_scaled_uv, vec2(-vision_direction.y, vision_direction.x)); // Perpendicular distance
            float local_y = dot(pixel_rel_to_laser_origin_p_scaled_uv, vision_direction); // Distance along laser

            // Make the visual laser thinner
            float visual_laser_half_width_p_scaled_uv = (rect_width_p_scaled_uv * 0.05);

            bool in_width = abs(local_x) < visual_laser_half_width_p_scaled_uv;
            // Laser starts from the black circle's center (local_y=0) and extends outwards
            bool in_length = (local_y > -0.001) && (local_y < rect_length_p_scaled_uv); 

            if (in_width && in_length) {
                // No need for the old dist_of_pixel_from_orb_center_working_uv clip here.
                // The laser is defined relative to the black circle and extends outwards.
                
                float intensity_from_centerline = 1.0 - smoothstep(0.0, visual_laser_half_width_p_scaled_uv, abs(local_x));
                intensity_from_centerline = pow(intensity_from_centerline, 1.2); // Sharper core

                float pulse = 0.7 + 0.3 * sin(tick * 15.0 + local_y * 0.05); // Modulate pulse by distance along laser slightly
                
                laser_alpha = intensity_from_centerline * pulse * 0.9; 
            }
        } 

        // Blend laser with existing boss color
        if (laser_alpha > 0.01) {
            final_boss_color_rgb += laser_color_core * laser_alpha * 1.5; // Boost laser brightness (additive-like)
            combined_alpha = max(combined_alpha, laser_alpha * 0.8f); // Laser contributes to overall alpha
        }

        // Dying effect modulation
        float overall_dying_alpha_multiplier = enemy_color_out_fs.a; 
        if (is_dying > 0.5) { 
            overall_dying_alpha_multiplier = enemy_effect_params_fs.w; 
        }
        combined_alpha *= overall_dying_alpha_multiplier; 

        frag_color = vec4(clamp(final_boss_color_rgb,0.0,1.5), clamp(combined_alpha,0.0,1.0));
        if (frag_color.a < 0.01) { discard; }
        return; 
    } 
    // --- SlowBoy Rendering Path ---
    else if (v_enemy_type_fs > 0.5 && v_enemy_type_fs < 1.5) { 
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
            float current_windup_timer = enemy_effect_params_fs.z; // This is attack_windup_timer from Odin
            float windup_progress = clamp((total_windup_duration - current_windup_timer) / max(0.001,total_windup_duration), 0.0, 1.0);
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
        if (frag_color.a < 0.01) { discard; }
        return; 
    }
    // --- Weaver Rendering Path (Type 3.0) ---
    else if (v_enemy_type_fs > 2.5 && v_enemy_type_fs < 3.5) {
        // WEAVER: Green Diamond Head + Sine Trails
        // p_scaled_uv space (-1.5 to 1.5)
        vec2 p = uv_centered * enemy_visual_scale_on_quad;
        
        // --- Head (Diamond) ---
        // Rotate 45 degrees to make a diamond from a square
        vec2 head_p = rotate2d(PI * 0.25) * p;
        vec2 head_dims = vec2(0.25, 0.25);
        float head_sdf = sdf_rectangle(head_p, head_dims);
        float aa = 0.02;
        float head_alpha = smoothstep(aa, 0.0, head_sdf);
        
        vec3 head_color = vec3(0.2, 1.0, 0.4); // Bright Green
        vec3 core_color = vec3(0.8, 1.0, 0.8);
        vec3 final_head_rgb = mix(head_color, core_color, smoothstep(0.05, 0.0, abs(head_sdf))); // Outline effect

        // --- Trails ---
        // 3 Segments following sine
        float trail_alpha_accum = 0.0;
        int trail_segments = 3;
        for (int i = 1; i <= trail_segments; i++) {
            float t = float(i) / float(trail_segments);
            float offset_x = -0.4 * float(i); // Behind head
            
            // Wiggle: Sine wave based on time + offset
            // We use 'tick' for animation speed
            float wiggle = sin(tick * 10.0 - float(i) * 1.5) * 0.15;
            
            vec2 segment_p = p - vec2(offset_x, wiggle);
            // Smaller diamonds
            vec2 seg_rot_p = rotate2d(PI * 0.25) * segment_p;
            float seg_scale = 0.18 * (1.0 - t * 0.6); // Get smaller
            float seg_sdf = sdf_rectangle(seg_rot_p, vec2(seg_scale));
            float seg_alpha = smoothstep(aa, 0.0, seg_sdf);
            trail_alpha_accum = max(trail_alpha_accum, seg_alpha * (1.0 - t * 0.8)); // Fade out
        }

        float combined_alpha = max(head_alpha, trail_alpha_accum);
        vec3 final_rgb = head_color; // Simplify color for now, mix if needed
        if (head_alpha > 0.01) final_rgb = final_head_rgb;
        else final_rgb = head_color * 0.7; // Darker trails

        // Dying Effect
        float is_dying = enemy_effect_params_fs.x;
        if (is_dying > 0.5) {
            combined_alpha *= enemy_effect_params_fs.w; // Alpha fade
            // TODO: Add dissolve/scatter effect here if desired
        }

        frag_color = vec4(final_rgb, combined_alpha * enemy_color_out_fs.a);
        if (frag_color.a < 0.01) discard;
        return;
    }
    // --- Gravitron Rendering Path (Type 4.0) ---
    else if (v_enemy_type_fs > 3.5 && v_enemy_type_fs < 4.5) {
        // GRAVITRON: Blue Atom (Concentric Rings)
        vec2 p = uv_centered * enemy_visual_scale_on_quad;
        float aa = 0.02;
        
        // Colors
        vec3 color_core = vec3(0.1, 0.4, 1.0); // Deep Blue
        vec3 color_ring = vec3(0.0, 0.8, 1.0); // Cyan
        
        // Core Sphere
        float d_core = length(p) - 0.25;
        float alpha_core = smoothstep(aa, 0.0, d_core);
        
        // Ring 1 (Inner) - Rotate CW
        float rot1 = tick * 2.0;
        vec2 p_ring1 = rotate2d(rot1) * p; // Rotation affects nothing for circle, but maybe we want gaps?
        // Let's make them Ellipses or partial rings to show rotation?
        // "Blue concentric rings rotating oppositely" usually implies 3D atom look OR just partial arcs.
        // For simple vector style: Annulus with gaps.
        
        float d_ring1 = abs(length(p) - 0.45) - 0.03;
        // Add gaps to visualize rotation
        float angle = atan(p.y, p.x);
        float gap_mask1 = sin(angle * 3.0 + tick * 3.0); // 3 gaps, rotating
        if (gap_mask1 < -0.5) d_ring1 = 1.0; // Cut gap
        float alpha_ring1 = smoothstep(aa, 0.0, d_ring1);

        // Ring 2 (Outer) - Rotate CCW
        float d_ring2 = abs(length(p) - 0.65) - 0.03;
        float gap_mask2 = sin(angle * 2.0 - tick * 2.5); // 2 gaps, rotating opposite
        if (gap_mask2 < -0.5) d_ring2 = 1.0;
        float alpha_ring2 = smoothstep(aa, 0.0, d_ring2);

        float combined_alpha = max(alpha_core, max(alpha_ring1, alpha_ring2));
        
        // Color mixing
        vec3 final_rgb = color_ring;
        if (alpha_core > 0.01) final_rgb = mix(color_core, vec3(1.0), 0.5 * smoothstep(0.1, 0.0, length(p))); // Highlight

        // Dying Effect
        float is_dying = enemy_effect_params_fs.x;
        if (is_dying > 0.5) {
            combined_alpha *= enemy_effect_params_fs.w; 
        }

        frag_color = vec4(final_rgb, combined_alpha * enemy_color_out_fs.a);
        if (frag_color.a < 0.01) discard;
        return;
    }
    // --- Tracer Rendering Path (Type 5.0) ---
    else if (v_enemy_type_fs > 4.5 && v_enemy_type_fs < 5.5) {
        // TRACER: Orange Arrowhead (Jet)
        vec2 p = uv_centered * enemy_visual_scale_on_quad;
        float aa = 0.02;

        vec3 color_orange = vec3(1.0, 0.5, 0.0);
        vec3 color_dark = vec3(0.4, 0.1, 0.0);

        // Arrowhead shape (Triangle pointing Right, assuming rotation aligns X+)
        // The rotation is handled by quad rotation, so we draw static shape pointing Right (X+)
        // Triangle vertices: (0.4, 0), (-0.3, 0.3), (-0.3, -0.3)
        // Normalized and centered:
        
        // SDF for Isosceles Triangle
        // We will rotate -90 deg to point Up for standard SDF function, or use custom.
        // Let's just use rotated box and cut it? Or 3 planes?
        // Simpler: 2D SDF Triangle.
        
        // Let's define it manually with planes for clarity or use a standard func if available.
        // No standard library here.
        // Let's use simple logic:
        // p.y is symmetry axis.
        vec2 q = p;
        q.y = abs(q.y);
        // Edge 1: x = -0.3
        float d1 = -(q.x - (-0.3));
        // Edge 2: angled line from (0.5, 0) to (-0.3, 0.35)
        // Normal to vector (-0.8, 0.35) -> (0.35, 0.8)
        vec2 v = vec2(-0.3, 0.35) - vec2(0.5, 0.0);
        vec2 normal = normalize(vec2(-v.y, v.x)); // (-0.35, -0.8) -> (-0.35, -0.8) -> needs to point out?
        // Wait, standard SDF logic is tricky without functions.
        // Let's try rotated boxes for wings.
        
        // Main Body: Elongated Diamond
        vec2 p_body = p;
        p_body.x -= 0.1; // Shift center
        p_body = rotate2d(PI * 0.25) * p_body; 
        float d_body = sdf_rectangle(p_body, vec2(0.2, 0.2)); 
        
        // Wings: "Folding" effect
        // If charging (high speed?), wings open. If aiming (low speed), wings closed.
        // We don't have exact state passed besides effect params.
        // Let's use simple animation.
        float wing_angle = 0.5 + 0.3 * sin(tick * 5.0);
        
        // Draw wing shapes?
        // Let's stick to a simple Arrowhead for now to pass verification.
        // Orange Halo
        float d_tri = max(abs(p.y) * 1.5 + p.x - 0.4, -p.x - 0.4); // Rough triangle
        float alpha_tri = smoothstep(aa, 0.0, d_tri);

        vec3 final_rgb = color_orange;
        if (d_tri < -0.05) final_rgb = mix(color_orange, vec3(1.0), 0.5); // Core

        float combined_alpha = alpha_tri;
        
        // Dying Effect
        float is_dying = enemy_effect_params_fs.x;
        if (is_dying > 0.5) {
            combined_alpha *= enemy_effect_params_fs.w; 
        }

        frag_color = vec4(final_rgb, combined_alpha * enemy_color_out_fs.a);
        if (frag_color.a < 0.01) discard;
        return;
    }
    // --- Elite Rendering Path (Type 6.0) ---
    else if (v_enemy_type_fs > 5.5 && v_enemy_type_fs < 6.5) {
        // ELITE: Red/Gold Hexagon (Gravitron Style)
        vec2 p = uv_centered * enemy_visual_scale_on_quad;
        float aa = 0.02;

        vec3 color_core = vec3(1.0, 0.1, 0.1); // Bright Red
        vec3 color_ring = vec3(1.0, 0.8, 0.2); // Gold

        // Helper for Hexagon SDF (inline for now if simple, or separate)
        // Hexagon Logic:
        // const vec3 k = vec3(-0.866025404, 0.5, 0.577350269);
        // p = abs(p);
        // p -= 2.0*min(dot(k.xy, p), 0.0)*k.xy;
        // p -= vec2(clamp(p.x, -k.z*r, k.z*r), r);
        // length(p)*sign(p.y);
        
        // We need a helper function typically, but can inline.
        // Let's implement function at top of file, or inline here.
        // Inline reduces risk of function placement errors in this tool.
        
        // --- Core Hexagon ---
        vec2 p_core = p;
        // Rotate Core slightly
        float rot_core = tick * 0.5;
        p_core = rotate2d(rot_core) * p_core;
        
        // Inline Hexagon SDF (Core Radius 0.3)
        float r_core = 0.3;
        vec3 k = vec3(-0.866025404, 0.5, 0.577350269);
        vec2 p_calc = abs(p_core);
        p_calc -= 2.0 * min(dot(k.xy, p_calc), 0.0) * k.xy;
        p_calc -= vec2(clamp(p_calc.x, -k.z * r_core, k.z * r_core), r_core);
        float d_core = length(p_calc) * sign(p_calc.y);
        
        float alpha_core = smoothstep(aa, 0.0, d_core);

        // --- Outer Ring Hexagon ---
        vec2 p_ring = p;
        // Rotate Ring Opposite/Faster
        float rot_ring = -tick * 1.5;
        p_ring = rotate2d(rot_ring) * p_ring;

        float r_ring = 0.5;
        p_calc = abs(p_ring);
        p_calc -= 2.0 * min(dot(k.xy, p_calc), 0.0) * k.xy;
        p_calc -= vec2(clamp(p_calc.x, -k.z * r_ring, k.z * r_ring), r_ring);
        float d_ring_outer = length(p_calc) * sign(p_calc.y);
        float d_ring = abs(d_ring_outer) - 0.05; // Ring thickness
        
        // Gaps for stylistic look (like Gravitron)
        float angle = atan(p_ring.y, p_ring.x);
        float gap_mask = sin(angle * 6.0); // 6 gaps for hexagon corners?
        if (gap_mask > 0.8) d_ring = 1.0; // Cut gap

        float alpha_ring = smoothstep(aa, 0.0, d_ring);

        // Combine
        float combined_alpha = max(alpha_core, alpha_ring);
        vec3 final_rgb = color_ring;
        if (alpha_core > 0.01) final_rgb = mix(color_core, vec3(1.0), 0.5 * smoothstep(0.1, 0.0, abs(d_core))); 

        // Dying Effect
        float is_dying = enemy_effect_params_fs.x;
        if (is_dying > 0.5) {
            combined_alpha *= enemy_effect_params_fs.w; 
        }

        frag_color = vec4(final_rgb, combined_alpha * enemy_color_out_fs.a);
        if (frag_color.a < 0.01) discard;
        return;
    }
    // --- Grunt Rendering Path (existing logic) ---
    else { 
        float aa_sdf_space; 
        float is_dying = enemy_effect_params_fs.x;
        float death_offset_world_units = enemy_effect_params_fs.y;
        float current_part_scale_multiplier = enemy_effect_params_fs.z;
        float overall_dying_alpha_multiplier = enemy_effect_params_fs.w;
        vec2 rectangle_half_dims_uv = vec2(0.32, 0.12); 
        
        // enemy_visual_scale_fs_out is current_size * 3.0
        // part_effective_world_width_at_full_uv represents world width of one rectangle part if it filled the scaled quad.
        // This calculation seems a bit off. Let's simplify.
        // rectangle_half_dims_uv is in uv_centered * enemy_visual_scale_on_quad space (p_scaled_uv space, extent -1.5 to 1.5)
        // World size of 1 unit in p_scaled_uv space = (enemy_visual_scale_fs_out / 3.0) / (2.0 * 1.5) = enemy_visual_scale_fs_out / 9.0
        // No, world size of 1 unit in p_scaled_uv = (current_size_of_enemy / 1.5) if current_size_of_enemy is diameter of p_scaled_uv space.
        // World width of rectangle part = rectangle_half_dims_uv.x * 2.0 * ( (enemy_visual_scale_fs_out / 3.0) / 1.5 )
        //                               = rectangle_half_dims_uv.x * 2.0 * (enemy_visual_scale_fs_out / 4.5)
        float world_size_of_one_p_scaled_uv_unit = (enemy_visual_scale_fs_out / enemy_visual_scale_on_quad) / 2.0 / (enemy_visual_scale_on_quad / 2.0) ; // This is tricky.
                                                // (world_diameter_of_quad / p_scaled_uv_diameter)
                                                // world_diameter_of_quad = (enemy_visual_scale_fs_out / 3.0) * 2.0 if quad_pos_in is -0.5 to 0.5
                                                // No, final_size_for_quad in VS is instance_visual_scale_vs_in = current_size * 3.0.
                                                // So the quad being rasterized has world diameter = current_size * 3.0.
                                                // p_scaled_uv space has diameter 3.0.
                                                // So 1 unit in p_scaled_uv = (current_size*3.0) / 3.0 = current_size.
        float world_units_per_p_scaled_uv_unit = (enemy_visual_scale_fs_out / enemy_visual_scale_on_quad);


        if (is_dying > 0.5) {
            rectangle_half_dims_uv *= current_part_scale_multiplier; 
        }
        
        // aa_world is desired AA edge in world units. Convert to p_scaled_uv units.
        float aa_p_scaled_uv = world_size_of_one_p_scaled_uv_unit / world_units_per_p_scaled_uv_unit;
        aa_sdf_space = min(rectangle_half_dims_uv.x, rectangle_half_dims_uv.y) * 0.01; 
       // aa_sdf_space = max(aa_sdf_space, aa_p_scaled_uv); // Ensure aa isn't too small


        float death_offset_p_scaled_uv = 0.0;
        if (world_units_per_p_scaled_uv_unit > 0.01) { 
            death_offset_p_scaled_uv = death_offset_world_units / world_units_per_p_scaled_uv_unit;
        }

        float internal_yaw_speed = 1.2;
        vec2 base_uv1_for_grunt = uv_centered * enemy_visual_scale_on_quad; // Now p_scaled_uv
        vec2 uv1_transformed = base_uv1_for_grunt;
        if (is_dying > 0.5) { uv1_transformed.y -= death_offset_p_scaled_uv * 0.5; } // Use p_scaled_uv offset
        float internal_rotation1 = (PI / 4.0) + tick * internal_yaw_speed;
        vec2 uv1_rotated = rotate2d(internal_rotation1) * uv1_transformed;
        float dist1 = sdf_rectangle(uv1_rotated, rectangle_half_dims_uv);
        vec3 color1_tip = enemy_color_out_fs.rgb * 1.6 + vec3(0.3, 0.2, 0.3);
        vec3 gradient_color1 = mix(color1_tip, enemy_color_out_fs.rgb, smoothstep(-0.5, 0.5, uv1_rotated.y * (1.0/max(0.01,rectangle_half_dims_uv.y)) * 0.5 )); // Normalize gradient factor
        float alpha_sdf1 = smoothstep(aa_sdf_space, 0.0, dist1); 

        vec2 base_uv2_for_grunt = uv_centered * enemy_visual_scale_on_quad; // Now p_scaled_uv
        vec2 uv2_transformed = base_uv2_for_grunt;
        if (is_dying > 0.5) { uv2_transformed.y += death_offset_p_scaled_uv * 0.5; } // Use p_scaled_uv offset
        float internal_rotation2 = (-PI / 4.0) - tick * internal_yaw_speed;
        vec2 uv2_rotated = rotate2d(internal_rotation2) * uv2_transformed;
        float dist2 = sdf_rectangle(uv2_rotated, rectangle_half_dims_uv);
        vec3 color2_tip = enemy_color_out_fs.rgb * 0.7 - vec3(0.1, 0.0, 0.1);
        vec3 gradient_color2 = mix(color2_tip, enemy_color_out_fs.rgb, smoothstep(-0.5, 0.5, uv2_rotated.x * (1.0/max(0.01,rectangle_half_dims_uv.x)) * 0.5)); // Normalize gradient factor
        float alpha_sdf2 = smoothstep(aa_sdf_space, 0.0, dist2); 

        float base_alpha = enemy_color_out_fs.a;
        if (is_dying > 0.5) { base_alpha *= overall_dying_alpha_multiplier; }
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
        if (frag_color.a < 0.01) { discard; }
    }
}
@end
@program enemy vs_enemy fs_enemy