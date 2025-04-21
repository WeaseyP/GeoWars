#version 450
#define SOKOL_WGSL (1)
layout(binding=1) uniform Player_Fs_Params {                                
    float tick;
    vec2 resolution;
};
in vec2 v_uv;
out vec4 frag_color;

                                               
float sdCircle(vec2 p, float r) { return length(p) - r; }
vec3 hash31(float p) { vec3 p3 = fract(vec3(p * 0.1031, p * 0.11369, p * 0.13789)); p3 += dot(p3, p3.yzx + 19.19); return fract((p3.xxy + p3.yzz)*p3.zyx); }
                         

void main() {                  
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
