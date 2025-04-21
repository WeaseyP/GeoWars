//------------------------------------------------------------------------------
//  shaders for geowars/shader.glsl
//------------------------------------------------------------------------------
@header package main
@header import sg "../sokol/gfx"
@header import m "../math"
@ctype mat4 m.mat4
@ctype vec2 m.vec2

// --- Background Shaders ---

@vs vs_bg
in vec2 position; // Location 0
void main() { gl_Position = vec4(position, 0.5, 1.0); }
@end

@fs fs_bg
layout(binding=0) uniform bg_fs_params {
    float tick; // tick is available here
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
            // Calculate the potential star's exact center coordinate in this cell
            float cell_id = grid_cell.x + grid_cell.y * 137.0; // Need cell_id for offset hash
            vec2 star_offset = hash21(cell_id + 0.5);
            vec2 star_pos = grid_cell + star_offset;

            // Calculate distance from current pixel (uv_star) to potential star center
            float dist_to_star = length(uv_star - star_pos);

            // Calculate the shape mask contribution from this potential star
            float star_shape = smoothstep(star_radius + aa_width, star_radius, dist_to_star);

            // Keep the maximum shape value found (handles overlapping edges)
            max_star_shape = max(max_star_shape, star_shape);
        } }
    return max_star_shape;
}
// --- Star Calculation (Uses 'tick' uniform directly) ---
float stars(vec2 uv_star, float density_threshold, float brightness_pow, float star_radius, float aa_width) {
    float final_star_brightness = 0.0;
    for (int j = -1; j <= 1; j++) { for (int i = -1; i <= 1; i++) {
            vec2 grid_cell = floor(uv_star) + vec2(float(i), float(j));
            float cell_id = grid_cell.x + grid_cell.y * 137.0;
            float star_exists_val = hash11(cell_id);
            if (star_exists_val > density_threshold) {
                vec2 star_offset = hash21(cell_id + 0.5);
                vec2 star_pos = grid_cell + star_offset;
                float dist_to_star = length(uv_star - star_pos);
                float star_shape = smoothstep(star_radius + aa_width, star_radius, dist_to_star);
                float base = max(0.0, (star_exists_val - density_threshold) / (1.0 - density_threshold));
                float inherent_brightness = pow(base, brightness_pow);
                float twinkle_speed = 3.0 + hash11(cell_id + 1.0) * 5.0;
                float twinkle = 0.5 + 0.5 * sin(tick * twinkle_speed + star_exists_val * 6.28318);
                float min_twinkle_bright = 0.35;
                twinkle = min_twinkle_bright + (1.0 - min_twinkle_bright) * twinkle; // Remap sin_wave
                final_star_brightness = max(final_star_brightness, star_shape * inherent_brightness * twinkle);
            } } }
    return final_star_brightness;
}
// --- End Utility Functions defined inside fs_bg ---

// --- Main Function defined AFTER helper functions inside the block ---
void main() { // fs_bg main
    if (bg_option == 0) {
        // --- Option 0: Original Tiling Background ---
        vec2 xy = fract((gl_FragCoord.xy-vec2(tick)) / 50.0);
        frag_color = vec4(vec3(xy.x*xy.y), 1.0);
    } else {
        // --- Option 1: Procedural Space Nebula & Stars ---
        vec2 uv_aspect = gl_FragCoord.xy / resolution.y;
        float time = tick; // Use raw tick or a scaled version like tick * 0.1

        // --- Nebula Calculation ---
        vec2 nebula_p = uv_aspect * 0.8 + vec2(time * 0.008, time * 0.003);
        float noise_val = fbm(nebula_p, 5, 0.5, 2.1);
        vec3 deep_space_color=vec3(0.01,0.0,0.03); vec3 nc1=vec3(0.5,0.05,0.25);
        vec3 nc2=vec3(0.1,0.15,0.5); vec3 nhl=vec3(0.8,0.7,0.75);
        vec3 nb=mix(deep_space_color,nc1,smoothstep(0.1,0.5,noise_val));
        vec3 nm=mix(nb,nc2,smoothstep(0.35,0.65,noise_val));
        vec3 fnc=mix(nm,nhl,smoothstep(0.6,0.8,noise_val));

        // --- Star Calculation ---
        vec2 star_uv = uv_aspect * 40.0;
        star_uv += time * 0.05;

        // Star Appearance Parameters
        float density_thresh = 0.80;
        float bright_power   = 15.0;
        float star_rad       = 0.03;
        float star_aa        = 0.06;
        float min_twinkle_bright = 0.6; // Higher minimum brightness flicker
        float overall_star_brightness_multiplier = 1.8; // Moderate brightness

        // Color Shift Parameters
        float color_shift_speed = 0.2; // How fast the star color cycles <<< TWEAK
        // float desaturation_factor = 0.6; // How much color variation vs white <<< TWEAK
        // vec3 target_star_color = vec3(1.0, 0.95, 0.9); // Target color for desat

        // 1. Calculate the shape mask
        float star_mask = calculate_star_mask(star_uv, star_rad, star_aa);

        // 2. Calculate color/brightness if mask > 0
        vec3 star_light = vec3(0.0);
        if (star_mask > 0.001) {
            vec2 grid_cell = floor(star_uv);
            float cell_id = grid_cell.x + grid_cell.y * 137.0;
            float star_exists_val = hash11(cell_id);

            if (star_exists_val > density_thresh) {
                // Calculate inherent brightness
                float base = max(0.0, (star_exists_val - density_thresh) / (1.0 - density_thresh));
                float inherent_brightness = pow(base, bright_power);

                // Calculate SLOWER, LESS INTENSE twinkle
                float twinkle_speed_variance = 1.5; // Keep some variance
                float twinkle_base_speed = 0.5;     // Base speed
                float twinkle_speed = twinkle_base_speed + hash11(cell_id + 1.0) * twinkle_speed_variance;
                float sin_wave = 0.5 + 0.5 * sin(time * twinkle_speed + star_exists_val * 6.28318);
                float twinkle = min_twinkle_bright + (1.0 - min_twinkle_bright) * sin_wave; // Remapped range [min_bright, 1.0]

                // --- Calculate SHIFTING color for this star ---
                // Get a unique phase offset for this star based on its ID
                // Multiply by 2*PI (6.283) to distribute phases around the sin cycle
                float star_color_phase_offset = hash11(cell_id + 1.23) * 6.28318; // Unique start phase

                // Calculate the base shifting color using time and the unique phase offset
                vec3 shifting_color = vec3(
                    0.5 + 0.5 * sin(time * color_shift_speed + star_color_phase_offset + 0.0),       // Red
                    0.5 + 0.5 * sin(time * color_shift_speed + star_color_phase_offset + 2.094395), // Green (+120 deg)
                    0.5 + 0.5 * sin(time * color_shift_speed + star_color_phase_offset + 4.18879)  // Blue (+240 deg)
                );

                // (Optional) Desaturate towards white/target color if desired
                //vec3 final_star_color = mix(shifting_color, target_star_color, desaturation_factor);

                // Use the shifting color directly for now (full saturation)
                vec3 final_star_color = shifting_color;

                // Combine: Color * Brightness * Twinkle * Multiplier
                star_light = final_star_color * inherent_brightness * twinkle * overall_star_brightness_multiplier;
            }
        }

        // --- Combine ---
        vec3 final_color = fnc * 0.9 + star_light * star_mask;

        // Output final color
        frag_color = vec4(clamp(final_color, 0.0, 1.0), 1.0);
    }
}
@end // <<< END @fs fs_bg


@program bg vs_bg fs_bg // Defines bg program


// --- Player Shaders ---

@vs vs_player
layout(binding=0) uniform Player_Vs_Params {
    mat4 mvp;
};
in vec2 position;
out vec2 v_uv;
void main() {
    gl_Position = mvp * vec4(position.xy, 0.0, 1.0);
    v_uv = position.xy * 0.5 + 0.5;
}
@end // <<< END OF vs_player BLOCK

@fs fs_player
layout(binding=1) uniform Player_Fs_Params {
    float tick;
    vec2 resolution;
};
in vec2 v_uv;
out vec4 frag_color;

// --- Player Utility Functions ---
float sdCircle(vec2 p, float r) { return length(p) - r; }
mat2 rotate2d(float angle) { float c=cos(angle); float s=sin(angle); return mat2(c,-s,s,c); }
// --- End Player Utility ---

void main() { // fs_player main
    vec2 p_orig = v_uv - vec2(0.5);
    // Remove aspect ratio correction for player shader to keep it circular
    // p_orig.x *= resolution.x / resolution.y; // REMOVED
    float time = tick * 0.05;
    float color_time = tick * 0.5;
    float base_angle = atan(p_orig.y, p_orig.x);
    float dist = length(p_orig);

    vec3 color = vec3(0.0);
    float alpha = 0.0;

    // Core
    float core_rad = 0.04 + 0.005 * sin(time * 25.0);
    float core_d = sdCircle(p_orig, core_rad);
    vec3 core_col = vec3(0.5, 1.0, 1.0);
    float core_aa = smoothstep(0.0, 0.005, -core_d);
    color += core_col * core_aa;
    alpha = max(alpha, core_aa);

    // Ring 1
    float ring1_rot_angle = -time * 1.5;
    float ring1_squash = 0.3 + 0.7 * abs(cos(time * 1.5));
    mat2 ring1_invRot = rotate2d(-ring1_rot_angle);
    mat2 ring1_invScale = mat2(1.0, 0.0, 0.0, 1.0 / ring1_squash);
    vec2 p1 = ring1_invScale * ring1_invRot * p_orig;
    float ring1_rad = 0.1 + 0.01 * cos(time * 18.0);
    float ring1_thick = 0.015;
    float ring1_d = abs(sdCircle(p1, ring1_rad)) - ring1_thick * 0.5;
    float ring1_aa = smoothstep(0.0, 0.004, -ring1_d);
    vec3 ring1_col = vec3(1.0, 0.3, 0.9);
    color += ring1_col * ring1_aa * 1.5;
    alpha = max(alpha, ring1_aa);

    // Ring 2
    float ring2_rot_angle = time * 1.1;
    float ring2_squash = 0.4 + 0.6 * abs(sin(time * 1.1 + 0.5));
    mat2 ring2_invRot = rotate2d(-ring2_rot_angle);
    mat2 ring2_invScale = mat2(1.0, 0.0, 0.0, 1.0 / ring2_squash);
    vec2 p2 = ring2_invScale * ring2_invRot * p_orig;
    float ring2_rad = 0.18 + 0.01 * sin(time * 12.0);
    float ring2_thick = 0.01;
    float ring2_d = abs(sdCircle(p2, ring2_rad)) - ring2_thick * 0.5;
    float ring2_aa = smoothstep(0.0, 0.003, -ring2_d);
    vec3 ring2_col = vec3(0.2, 0.9, 0.9);
    color += ring2_col * ring2_aa;
    alpha = max(alpha, ring2_aa);

    // Spikes
    float spike_rotation_angle = time * 0.8;
    float rotated_angle = base_angle + spike_rotation_angle;
    float num_spikes = 16.0;
    float spike_sharpness = 32.0;
    float spikes = pow(abs(sin(rotated_angle * num_spikes * 0.5)), spike_sharpness);
    float base_glow = 0.7;
    float glow_radius = 0.5;
    float glow_falloff = 5.0;
    float glow_intensity = pow(max(0.0, 1.0 - dist / glow_radius), glow_falloff);
    float spike_boost = 5;
    glow_intensity *= (base_glow + spike_boost * spikes);
    float pulse_base = 0.8;
    float pulse_amplitude = 0.2;
    glow_intensity *= (pulse_base + pulse_amplitude * sin(time * 15.0 + dist * 12.0));
    vec3 dynamic_glow_col = vec3(
        0.5+0.5*sin(color_time+0.0), 0.5+0.5*sin(color_time+2.094395), 0.5+0.5*sin(color_time+4.18879)
    );
    dynamic_glow_col = normalize(dynamic_glow_col) * 1.1;
    float overall_brightness = 2;
    color += dynamic_glow_col * glow_intensity * overall_brightness;
    alpha = max(alpha, glow_intensity * 0.6);

    // Final Output
    frag_color = vec4(clamp(color, 0.0, 1.0), clamp(alpha, 0.0, 1.0));
}
@end // <<< END OF fs_player BLOCK

// Define the CTYPE mapping AFTER the block

@program player vs_player fs_player // Defines player program