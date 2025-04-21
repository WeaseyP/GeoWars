#version 450
#define SOKOL_WGSL (1)
                                                                       
layout(binding=1) uniform Player_Fs_Params {
    float tick;
    vec2 resolution;
};

in vec2 v_uv;                               
out vec4 frag_color;                

                                       
float sdCircle(vec2 p, float r) { return length(p) - r; }
                                

                                              
mat2 rotate2d(float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return mat2(c, -s, s, c);                                         
}

                                                                       
void main() {
    vec2 p_orig = v_uv - vec2(0.5);                            
    float time = tick * 0.05;
    float base_angle = atan(p_orig.y, p_orig.x);
    float dist = length(p_orig);

    vec3 color = vec3(0.0);
    float alpha = 0.0;

                                       
    float core_rad = 0.04 + 0.005 * sin(time * 25.0);
                                                     
    float core_d = sdCircle(p_orig, core_rad);
    vec3 core_col = vec3(0.5, 1.0, 1.0);
    float core_aa = smoothstep(0.0, 0.005, -core_d);
    color += core_col * core_aa;
    alpha = max(alpha, core_aa);

                                                     
    float ring1_rot_angle = -time * 1.5;                  
                                                                   
    float ring1_squash = 0.3 + 0.7 * abs(cos(time * 1.5));
    mat2 ring1_scale = mat2(1.0, 0.0, 0.0, ring1_squash);                
    mat2 ring1_rot = rotate2d(ring1_rot_angle);
                                                   
                                                                           
                                                    
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

                                                             
    float ring2_rot_angle = time * 1.1;                  
                                        
    float ring2_squash = 0.4 + 0.6 * abs(sin(time * 1.1 + 0.5));                
    mat2 ring2_scale = mat2(1.0, 0.0, 0.0, ring2_squash);
    mat2 ring2_rot = rotate2d(ring2_rot_angle);
    mat2 ring2_invRot = rotate2d(-ring2_rot_angle);
    mat2 ring2_invScale = mat2(1.0, 0.0, 0.0, 1.0 / ring2_squash);
    vec2 p2 = ring2_invScale * ring2_invRot * p_orig;                           

                                                          
    float ring2_rad = 0.15 + 0.02 * sin(time * 12.0);
    float ring2_thick = 0.01;
    float ring2_d = abs(sdCircle(p2, ring2_rad)) - ring2_thick * 0.5;          
    float ring2_aa = smoothstep(0.0, 0.003, -ring2_d);
    vec3 ring2_col = vec3(0.2, 0.9, 0.9);        
    color += ring2_col * ring2_aa;
    alpha = max(alpha, ring2_aa);


                                                               
                                                                 
    float spike_rotation_angle = time * 0.8;
    float rotated_angle = base_angle + spike_rotation_angle;
    float num_spikes = 9.0;
    float spike_sharpness = 80.0;
    float spikes = pow(abs(sin(rotated_angle * num_spikes * 0.5)), spike_sharpness);
                                         
    float glow_intensity = pow(max(0.0, 1.0 - dist / 0.35), 3.0);
    glow_intensity *= (0.4 + 1.6 * spikes);
    glow_intensity *= (0.8 + 0.2 * sin(time * 15.0 + dist * 12.0));
    vec3 glow_col = vec3(1.0, 1.0, 0.7);
    color += glow_col * glow_intensity * 0.9;
    alpha = max(alpha, glow_intensity * 0.6);

                   
    frag_color = vec4(clamp(color, 0.0, 1.0), clamp(alpha, 0.0, 1.0));
}
