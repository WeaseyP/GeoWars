#version 450
#define SOKOL_HLSL (1)
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
