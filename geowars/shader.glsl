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
void main() {
    gl_Position = vec4(position, 0.5, 1.0);
}
@end

@fs fs_bg
layout(binding=0) uniform bg_fs_params { // Block Name: bg_fs_params
    float tick;
    vec2 resolution;
};
out vec4 frag_color;

// --- Utility / Noise Functions (hash11, noise, fbm, stars) ---
float hash11(float p) { return fract(sin(p * 78.233) * 43758.5453); }
float noise(vec2 p) {
    vec2 i = floor(p); vec2 f = fract(p); f = f*f*(3.0-2.0*f);
    float v00 = hash11(i.x + i.y * 57.0); float v10 = hash11(i.x + 1.0 + i.y * 57.0);
    float v01 = hash11(i.x + (i.y + 1.0) * 57.0); float v11 = hash11(i.x + 1.0 + (i.y + 1.0) * 57.0);
    return mix(mix(v00, v10, f.x), mix(v01, v11, f.x), f.y);
}
float fbm(vec2 p, int octaves, float persistence, float lacunarity) {
    float total = 0.0; float frequency = 1.0; float amplitude = 0.5; float max_amp = 0.0;
    for (int i = 0; i < octaves; i++) {
        total += noise(p * frequency) * amplitude; max_amp += amplitude;
        frequency *= lacunarity; amplitude *= persistence;
    } return total / max_amp;
}
float stars(vec2 uv_star, float density_threshold, float brightness_pow) {
    vec2 grid_uv = floor(uv_star); float star_val = hash11(grid_uv.x + grid_uv.y * 137.0);
    float star_brightness = 0.0; if (star_val > density_threshold) {
        star_brightness = pow((star_val - density_threshold) / (1.0 - density_threshold), brightness_pow);
        float twinkle_speed = 3.0 + hash11(star_val + 1.0) * 5.0;
        float twinkle = 0.5 + 0.5 * sin(tick * twinkle_speed + star_val * 6.28318);
        star_brightness *= twinkle;
    } return star_brightness;
}
// --- End Utility Functions ---

void main() { // fs_bg main
    vec2 uv_aspect = gl_FragCoord.xy / resolution.y;
    vec2 nebula_p = uv_aspect * 2.0 + vec2(tick * 0.01, tick * 0.005);
    float noise_val = fbm(nebula_p, 5, 0.5, 2.0);
    vec3 deep_space_color = vec3(0.0, 0.0, 0.05); vec3 nebula_color1 = vec3(0.8, 0.1, 0.4);
    vec3 nebula_color2 = vec3(0.2, 0.3, 0.9); vec3 nebula_highlight = vec3(1.0, 0.8, 0.8);
    vec3 nebula_base = mix(deep_space_color, nebula_color1, smoothstep(0.2, 0.5, noise_val));
    vec3 nebula_mix = mix(nebula_base, nebula_color2, smoothstep(0.4, 0.65, noise_val));
    vec3 final_nebula_color = mix(nebula_mix, nebula_highlight, smoothstep(0.6, 0.75, noise_val));
    vec2 star_p = gl_FragCoord.xy * 0.5 + vec2(tick * -2.0, tick * -1.0);
    float star_brightness = stars(star_p, 0.993, 15.0);
    vec3 final_color = final_nebula_color + vec3(star_brightness);
    frag_color = vec4(clamp(final_color, 0.0, 1.0), 1.0);
}
@end

@program bg vs_bg fs_bg // Defines bg program


// --- Player Shaders ---

@vs vs_player
layout(binding=0) uniform Player_Vs_Params { // Block Name: Player_Vs_Params
    mat4 mvp;
};
in vec2 position; // Location 0
out vec2 v_uv;
void main() {
    gl_Position = mvp * vec4(position.xy, 0.0, 1.0);
    v_uv = position.xy * 0.5 + 0.5;
}
@end

@fs fs_player
layout(binding=1) uniform Player_Fs_Params { // Block Name: Player_Fs_Params
    float tick;
    vec2 resolution;
};
in vec2 v_uv;
out vec4 frag_color;

// --- SDF / Hash (reuse hash11 from above) ---
float sdCircle(vec2 p, float r) { return length(p) - r; }
vec3 hash31(float p) { vec3 p3 = fract(vec3(p * 0.1031, p * 0.11369, p * 0.13789)); p3 += dot(p3, p3.yzx + 19.19); return fract((p3.xxy + p3.yzz)*p3.zyx); }
// --- End SDF / Hash ---

void main() { // fs_player main
    vec2 p = v_uv - vec2(0.5); p.x *= resolution.x / resolution.y;
    float time = tick * 0.05;
    float core_radius = 0.05 + 0.01 * sin(time * 20.0); float d = sdCircle(p, core_radius);
    vec3 base_col = vec3(0.1, 0.8, 1.0); float core_aa = smoothstep(0.0, 0.01, -d);
    vec3 color = base_col * core_aa; float alpha = core_aa;
    float ring1_radius = 0.1 + 0.015 * cos(time * 15.0); float ring1_thickness = 0.02;
    float ring1_d = abs(sdCircle(p, ring1_radius)) - ring1_thickness * 0.5;
    float ring1_aa = smoothstep(0.0, 0.005, -ring1_d); vec3 ring1_col = vec3(1.0, 0.5, 0.8);
    color += ring1_col * ring1_aa * 2.0; alpha = max(alpha, ring1_aa);
    float glow_dist = length(p); float glow_intensity = pow(max(0.0, 1.0 - glow_dist / 0.4), 2.0);
    vec3 glow_col = vec3(1.0, 0.9, 0.5); glow_intensity *= (0.7 + 0.3 * sin(time * 10.0 + glow_dist * 10.0));
    float angle = atan(p.y, p.x); float num_spikes = 8.0; float spike_sharpness = 50.0;
    float spikes = pow(abs(sin(angle * num_spikes * 0.5)), spike_sharpness);
    glow_intensity *= (0.5 + 1.5 * spikes); color += glow_col * glow_intensity * 0.8;
    alpha = max(alpha, glow_intensity * 0.5); frag_color = vec4(color, alpha);
}
@end

@program player vs_player fs_player // Defines player program