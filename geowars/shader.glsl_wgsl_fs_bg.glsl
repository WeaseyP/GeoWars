#version 450
#define SOKOL_WGSL (1)
layout(binding=0) uniform bg_fs_params {
    float tick;
    vec2 resolution;
    int bg_option;
};
out vec4 frag_color;

const float NEBULA_PARALLAX_FACTOR = 0.3; 
const float STARS_PARALLAX_FACTOR = 0.7;  

                                                               
vec3 hash31(float p) { vec3 p3=fract(vec3(p*0.1031,p*0.11369,p*0.13789)); p3+=dot(p3,p3.yzx+19.19); return fract((p3.xxy+p3.yzz)*p3.zyx); }
vec2 hash21(float p) { vec2 p2=fract(vec2(p*0.1031,p*0.11369)); p2+=dot(p2,p2.yx+19.19); return fract((p2.xx+p2.yy)*p2.yx); }
float hash11(float p) { return fract(sin(p*78.233)*43758.5453); }
float noise(vec2 p) { vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f); float v00=hash11(i.x+i.y*57.0); float v10=hash11(i.x+1.0+i.y*57.0); float v01=hash11(i.x+(i.y+1.0)*57.0); float v11=hash11(i.x+1.0+(i.y+1.0)*57.0); return mix(mix(v00,v10,f.x),mix(v01,v11,f.x),f.y); }
float fbm(vec2 p, int o, float per, float lac) { float t=0.0; float f=1.0; float a=0.5; float ma=0.0; for(int i=0;i<o;i++){ t+=noise(p*f)*a; ma+=a; f*=lac; a*=per; } return t/ma; }
float calculate_star_mask(vec2 uv_star, float star_radius, float aa_width) {                        
    float max_star_shape = 0.0;
    for (int j = -1; j <= 1; j++) { for (int i = -1; i <= 1; i++) {                  
            vec2 grid_cell = floor(uv_star) + vec2(float(i), float(j));
            float cell_id = grid_cell.x + grid_cell.y * 137.0;                                
            vec2 star_offset = hash21(cell_id + 0.5);
            vec2 star_pos = grid_cell + star_offset;
            float dist_to_star = length(uv_star - star_pos);
            float star_shape = smoothstep(star_radius + aa_width, star_radius, dist_to_star);
            max_star_shape = max(max_star_shape, star_shape);
        } }
    return max_star_shape;
}

void main() {
    if (bg_option == 0) {
        vec2 xy = fract((gl_FragCoord.xy / 50.0) - vec2(tick / 50.0));
        frag_color = vec4(vec3(xy.x*xy.y), 1.0);
    } else {
        vec2 uv_aspect = gl_FragCoord.xy / resolution.y;
        float time = tick; 

        vec2 nebula_time_drift = vec2(time * 0.8, time * 0.3);          
        vec2 nebula_base_uv = uv_aspect + nebula_time_drift; 
        vec2 nebula_p = nebula_base_uv * 0.8;                                  
        
        float noise_val = fbm(nebula_p, 5, 0.5, 2.1);
        vec3 deep_space_color=vec3(0.01,0.0,0.03); vec3 nc1=vec3(0.5,0.05,0.25);
        vec3 nc2=vec3(0.1,0.15,0.5); vec3 nhl=vec3(0.8,0.7,0.75);
        vec3 nb=mix(deep_space_color,nc1,smoothstep(0.1,0.5,noise_val));
        vec3 nm=mix(nb,nc2,smoothstep(0.35,0.65,noise_val));
        vec3 fnc=mix(nm,nhl,smoothstep(0.6,0.8,noise_val));

        vec2 stars_time_drift = vec2(time * 0.2, time * 0.1); 
        vec2 star_uv_base_for_sampling = uv_aspect + stars_time_drift; 
        vec2 star_uv = star_uv_base_for_sampling * 40.0;                             

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
