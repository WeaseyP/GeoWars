#version 450
#define SOKOL_HLSL (1)
                                      
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
