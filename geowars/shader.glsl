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
    vec2 uv_aspect = gl_FragCoord.xy/resolution.y; vec2 np = uv_aspect*2.0+vec2(tick*0.01,tick*0.005);
    float nv=fbm(np,5,0.5,2.0); vec3 dsc=vec3(0.0,0.0,0.05); vec3 nc1=vec3(0.8,0.1,0.4);
    vec3 nc2=vec3(0.2,0.3,0.9); vec3 nhl=vec3(1.0,0.8,0.8); vec3 nb=mix(dsc,nc1,smoothstep(0.2,0.5,nv));
    vec3 nm=mix(nb,nc2,smoothstep(0.4,0.65,nv)); vec3 fnc=mix(nm,nhl,smoothstep(0.6,0.75,nv));
    vec2 sp=gl_FragCoord.xy*0.5+vec2(tick*-2.0,tick*-1.0); float sb=stars(sp,0.993,15.0);
    vec3 fc=fnc+vec3(sb); frag_color=vec4(clamp(fc,0.0,1.0),1.0);
}
@end

@program bg vs_bg fs_bg // Defines bg program


// --- Player Shaders ---



// Uniform block for Vertex Shader
@vs vs_player
layout(binding=0) uniform Player_Vs_Params { // Block Name: Player_Vs_Params
    mat4 mvp;
};
in vec2 position; // Location 0
out vec2 v_uv; // Pass UV to fragment shader
void main() {
    gl_Position = mvp * vec4(position.xy, 0.0, 1.0);
    v_uv = position.xy * 0.5 + 0.5; // Convert quad vertex pos (-1..1) to UV (0..1)
}
@end // <<< END OF vs_player BLOCK



@fs fs_player
// Check generated shader.odin for binding slot (likely 1 if bg uses 0)
layout(binding=1) uniform Player_Fs_Params {
    float tick;
    vec2 resolution;
};

in vec2 v_uv; // Input UV from vertex shader
out vec4 frag_color; // Output color

// --- Utility Functions (SDF/Hash) ---
float sdCircle(vec2 p, float r) { return length(p) - r; }
// --- End Utility Functions ---

// --- Helper to build 2x2 rotation matrix ---
mat2 rotate2d(float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return mat2(c, -s, s, c); // Column-major: col1=(c,s), col2=(-s,c)
}

// --- Main Player Shader Logic (With 2D transformations for rings) ---
void main() {
    vec2 p_orig = v_uv - vec2(0.5); // Original centered coords
    float time = tick * 0.05;
    float base_angle = atan(p_orig.y, p_orig.x);
    float dist = length(p_orig);

    vec3 color = vec3(0.0);
    float alpha = 0.0;

    // --- Core (stationary circle) ---
    float core_rad = 0.04 + 0.005 * sin(time * 25.0);
    // Use original coordinates 'p_orig' for the core
    float core_d = sdCircle(p_orig, core_rad);
    vec3 core_col = vec3(0.5, 1.0, 1.0);
    float core_aa = smoothstep(0.0, 0.005, -core_d);
    color += core_col * core_aa;
    alpha = max(alpha, core_aa);

    // --- Ring 1 (Simulated 3D Rotate Clockwise) ---
    float ring1_rot_angle = -time * 1.5; // Rotation angle
    // Squash factor simulates tilting (value between ~0.3 and 1.0)
    float ring1_squash = 0.3 + 0.7 * abs(cos(time * 1.5));
    mat2 ring1_scale = mat2(1.0, 0.0, 0.0, ring1_squash); // Scale Y axis
    mat2 ring1_rot = rotate2d(ring1_rot_angle);
    // Combined transform: Scale first, then Rotate
    // We need the inverse to transform 'p_orig' back to the circle's space
    // Inverse(R*S*p) => Inverse(S) * Inverse(R) * p
    mat2 ring1_invRot = rotate2d(-ring1_rot_angle); // Inverse rotation
    mat2 ring1_invScale = mat2(1.0, 0.0, 0.0, 1.0 / ring1_squash); // Inverse scale
    vec2 p1 = ring1_invScale * ring1_invRot * p_orig; // Apply inverse transform to coords

    // Now calculate distance using the transformed coordinates p1
    float ring1_rad = 0.1 + 0.01 * cos(time * 18.0); // Base radius still pulses
    float ring1_thick = 0.015;
    float ring1_d = abs(sdCircle(p1, ring1_rad)) - ring1_thick * 0.5; // Use p1
    float ring1_aa = smoothstep(0.0, 0.004, -ring1_d);
    vec3 ring1_col = vec3(1.0, 0.3, 0.9); // Magenta
    color += ring1_col * ring1_aa * 1.5;
    alpha = max(alpha, ring1_aa);

    // --- Ring 2 (Simulated 3D Rotate Counter-Clockwise) ---
    float ring2_rot_angle = time * 1.1; // Rotation angle
    // Different squash factor variation
    float ring2_squash = 0.4 + 0.6 * abs(sin(time * 1.1 + 0.5)); // Offset phase
    mat2 ring2_scale = mat2(1.0, 0.0, 0.0, ring2_squash);
    mat2 ring2_rot = rotate2d(ring2_rot_angle);
    mat2 ring2_invRot = rotate2d(-ring2_rot_angle);
    mat2 ring2_invScale = mat2(1.0, 0.0, 0.0, 1.0 / ring2_squash);
    vec2 p2 = ring2_invScale * ring2_invRot * p_orig; // Apply inverse transform

    // Calculate distance using transformed coordinates p2
    float ring2_rad = 0.15 + 0.02 * sin(time * 12.0);
    float ring2_thick = 0.01;
    float ring2_d = abs(sdCircle(p2, ring2_rad)) - ring2_thick * 0.5; // Use p2
    float ring2_aa = smoothstep(0.0, 0.003, -ring2_d);
    vec3 ring2_col = vec3(0.2, 0.9, 0.9); // Cyan
    color += ring2_col * ring2_aa;
    alpha = max(alpha, ring2_aa);


    // --- Spikes (Rotating independently using base angle) ---
    // Spikes are drawn in the original coordinate space 'p_orig'
    float spike_rotation_angle = time * 0.8;
    float rotated_angle = base_angle + spike_rotation_angle;
    float num_spikes = 9.0;
    float spike_sharpness = 80.0;
    float spikes = pow(abs(sin(rotated_angle * num_spikes * 0.5)), spike_sharpness);
    // Glow uses original distance 'dist'
    float glow_intensity = pow(max(0.0, 1.0 - dist / 0.35), 3.0);
    glow_intensity *= (0.4 + 1.6 * spikes);
    glow_intensity *= (0.8 + 0.2 * sin(time * 15.0 + dist * 12.0));
    vec3 glow_col = vec3(1.0, 1.0, 0.7);
    color += glow_col * glow_intensity * 0.9;
    alpha = max(alpha, glow_intensity * 0.6);

    // Final Output
    frag_color = vec4(clamp(color, 0.0, 1.0), clamp(alpha, 0.0, 1.0));
}
@end // <<< END OF fs_player BLOCK

@program player vs_player fs_player // Defines player program