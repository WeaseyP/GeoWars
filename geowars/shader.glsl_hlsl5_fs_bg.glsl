#version 450
#define SOKOL_HLSL (1)
layout(binding=0) uniform bg_fs_params {                            
    float tick;
    vec2 resolution;
};
out vec4 frag_color;

                                                                
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
                                

void main() {              
    vec2 uv_aspect = gl_FragCoord.xy/resolution.y; vec2 np = uv_aspect*2.0+vec2(tick*0.01,tick*0.005);
    float nv=fbm(np,5,0.5,2.0); vec3 dsc=vec3(0.0,0.0,0.05); vec3 nc1=vec3(0.8,0.1,0.4);
    vec3 nc2=vec3(0.2,0.3,0.9); vec3 nhl=vec3(1.0,0.8,0.8); vec3 nb=mix(dsc,nc1,smoothstep(0.2,0.5,nv));
    vec3 nm=mix(nb,nc2,smoothstep(0.4,0.65,nv)); vec3 fnc=mix(nm,nhl,smoothstep(0.6,0.75,nv));
    vec2 sp=gl_FragCoord.xy*0.5+vec2(tick*-2.0,tick*-1.0); float sb=stars(sp,0.993,15.0);
    vec3 fc=fnc+vec3(sb); frag_color=vec4(clamp(fc,0.0,1.0),1.0);
}
