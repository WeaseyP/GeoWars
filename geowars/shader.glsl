// File: shader.glsl (Merged Version)
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

// --- Player Shaders (Keep existing from older version) ---

@vs vs_player
layout(binding=0) uniform Player_Vs_Params { mat4 mvp; }; // Compact uniform block definition
in vec2 position;
out vec2 v_uv;
void main() {
    gl_Position = mvp * vec4(position.xy, 0.0, 1.0);
    v_uv = position.xy * 0.5 + 0.5;
}
@end

@fs fs_player
layout(binding=1) uniform Player_Fs_Params { float tick; vec2 resolution; }; // Compact
in vec2 v_uv;
out vec4 frag_color;
float sdCircle(vec2 p, float r) { return length(p) - r; }
mat2 rotate2d(float angle) { float c=cos(angle); float s=sin(angle); return mat2(c,-s,s,c); }
void main() {
    vec2 p_orig = v_uv - vec2(0.5);
    float time = tick * 0.05; float color_time = tick * 0.5;
    float base_angle = atan(p_orig.y, p_orig.x); float dist = length(p_orig);
    vec3 color = vec3(0.0); float alpha = 0.0;
    float core_rad = 0.04 + 0.005 * sin(time * 25.0);
    float core_d = sdCircle(p_orig, core_rad);
    float core_aa = smoothstep(0.0, 0.005, -core_d);
    color += vec3(0.5, 1.0, 1.0) * core_aa; alpha = max(alpha, core_aa);
    float ring1_rot_angle = -time * 1.5; float ring1_squash = 0.3 + 0.7 * abs(cos(time * 1.5));
    mat2 ring1_invRot = rotate2d(-ring1_rot_angle); mat2 ring1_invScale = mat2(1.0, 0.0, 0.0, 1.0 / ring1_squash);
    vec2 p1 = ring1_invScale * ring1_invRot * p_orig;
    float ring1_rad = 0.1 + 0.01 * cos(time * 18.0); float ring1_d = abs(sdCircle(p1, ring1_rad)) - 0.015 * 0.5;
    float ring1_aa = smoothstep(0.0, 0.004, -ring1_d);
    color += vec3(1.0, 0.3, 0.9) * ring1_aa * 1.5; alpha = max(alpha, ring1_aa);
    float ring2_rot_angle = time * 1.1; float ring2_squash = 0.4 + 0.6 * abs(sin(time * 1.1 + 0.5));
    mat2 ring2_invRot = rotate2d(-ring2_rot_angle); mat2 ring2_invScale = mat2(1.0, 0.0, 0.0, 1.0 / ring2_squash);
    vec2 p2 = ring2_invScale * ring2_invRot * p_orig;
    float ring2_rad = 0.18 + 0.01 * sin(time * 12.0); float ring2_d = abs(sdCircle(p2, ring2_rad)) - 0.01 * 0.5;
    float ring2_aa = smoothstep(0.0, 0.003, -ring2_d);
    color += vec3(0.2, 0.9, 0.9) * ring2_aa; alpha = max(alpha, ring2_aa);
    float spike_rotation_angle = time * 0.8; float rotated_angle = base_angle + spike_rotation_angle;
    float spikes = pow(abs(sin(rotated_angle * 16.0 * 0.5)), 32.0);
    float glow_intensity = pow(max(0.0, 1.0 - dist / 0.5), 5.0);
    glow_intensity *= (0.7 + 5.0 * spikes);
    glow_intensity *= (0.8 + 0.2 * sin(time * 15.0 + dist * 12.0));
    vec3 dynamic_glow_col = normalize(vec3(0.5+0.5*sin(color_time+0.0), 0.5+0.5*sin(color_time+2.094395), 0.5+0.5*sin(color_time+4.18879))) * 1.1;
    color += dynamic_glow_col * glow_intensity * 2.0; alpha = max(alpha, glow_intensity * 0.6);
    frag_color = vec4(clamp(color, 0.0, 1.0), clamp(alpha, 0.0, 1.0));
}
@end
@program player vs_player fs_player


// --- Particle Shaders (Copied from newer code) ---

@vs vs_particle
layout(binding=0) uniform particle_vs_params { mat4 view_proj; }; // Compact

// Per-vertex attributes for the base quad (drawn MAX_PARTICLES times)
layout(location=0) in vec2 quad_pos; // -0.5 to 0.5
layout(location=1) in vec2 quad_uv;  // 0.0 to 1.0

// Per-instance attributes (one set per active particle)
layout(location=2) in vec4 instance_pos_size_rot; // .xy=pos, .z=size, .w=rotation
layout(location=3) in vec4 instance_color;        // .rgba color (alpha includes lifetime)

// Outputs to fragment shader
out vec4 particle_color;
out vec2 particle_uv;
out float particle_dist; // Distance from center of quad (0.0 to ~0.7)

void main() {
    vec2 inst_pos = instance_pos_size_rot.xy;
    float inst_size = instance_pos_size_rot.z;
    float inst_rot = instance_pos_size_rot.w;

    // Apply instance rotation and scale to base quad vertex position
    float cr = cos(inst_rot); float sr = sin(inst_rot);
    mat2 rot_mat = mat2(cr, -sr, sr, cr);
    vec2 final_local_pos = rot_mat * (quad_pos * inst_size);

    // Add instance world position
    vec2 final_world_pos = final_local_pos + inst_pos;

    // Project to screen
    gl_Position  = view_proj * vec4(final_world_pos, 0.0, 1.0);

    // Pass through data to fragment shader
    particle_color = instance_color; // Pass color (including lifetime alpha)
    particle_uv = quad_uv;
    particle_dist = length(quad_pos); // Precalculate distance from center
}
@end

// File: shader.glsl (fs_particle part) - Angular Swirl + Black Core + Lifetime Alpha Only
@fs fs_particle
layout(binding=1) uniform particle_fs_params { float tick; };

in vec4 particle_color;
in vec2 particle_uv;
in float particle_dist; // Keep this input if your VS still provides it

out vec4 frag_color;

void main() {
    vec2 uv_centered = particle_uv - vec2(0.5);
    float angle = atan(uv_centered.y, uv_centered.x);
    // Use either passed-in particle_dist or recalculate locally
    float dist_from_center = particle_dist; // Or length(uv_centered) * (0.707/0.5) approx.

    float core_radius = 0.1;
    float swirl_start_radius = 0.15;
    float swirl_speed = -4.5;
    float swirl_freq = 6.0;
    float radial_speed_factor = 2.0; // Add this back in for more dynamic swirl

    vec3 color_dark_purple = vec3(0.3, 0.0, 0.5);
    vec3 color_bright_purple = vec3(0.8, 0.3, 1.0);
    vec3 color_black = vec3(0.0, 0.0, 0.0);

    // Swirl Calculation (with distance component)
    float swirl_value = sin(angle * swirl_freq + dist_from_center * radial_speed_factor + tick * swirl_speed);
    swirl_value = swirl_value * 0.5 + 0.5;
    swirl_value = smoothstep(0.4, 0.6, swirl_value);

    vec3 swirl_color = mix(color_dark_purple, color_bright_purple, swirl_value);

    float core_mix_factor = smoothstep(core_radius, swirl_start_radius, dist_from_center);
    vec3 final_rgb = mix(color_black, swirl_color, core_mix_factor);

    float final_alpha = particle_color.a; // Alpha purely from lifetime

    frag_color = vec4(final_rgb, final_alpha);
}
@end
@program particle vs_particle fs_particle