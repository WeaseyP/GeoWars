// File: shader.glsl (Merged Version, with Player Health Display)
//------------------------------------------------------------------------------
@header package main
@header import sg "../vendor/sokol/gfx"
@header import m "../vendor/math"
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
    float player_hp_ratio;   // 1.0 = full HP, 0.0 = dead. Drives arena-ring colour shift.
    vec2 camera_pos;         // World position the camera is centred on (player_pos for follow camera).
    vec4 wave_button_state;  // x=next_wave_idx (0..10), y=remaining (10-x), z=player_in_range, w=press_flash
    vec4 shop_state;         // x=active (0/1), y=hovered_idx (-1..2), z=is_pre_boss, w=time_in_shop
    vec4 shop_tiers;         // tier of card 0/1/2 (1.0/2.0/3.0); .w unused
    vec4 rmb_beam_origin_dir;// xy=origin in world units, zw=unit beam dir (length-1 when active, zero when inactive)
    vec4 rmb_beam_params;    // x=fade_progress (1=just-fired, 0=ended), y=length(world), z=half_width(world); w unused
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
        // Background: screen-anchored nebula + stars (do NOT move with the camera, so they read
        // as a separate visual layer from the world-space enemies). Only the arena ring lives in
        // world space, computed via world_uv below.
        const float ORTHO_H = 1.5;
        // sokol-shdc's HLSL output has the FS gl_FragCoord with y=0 at the TOP of the screen,
        // which is the opposite of vertex-stage NDC. Flip y here so world_uv matches the same
        // world-space coordinates the vertex shader uses for player/enemy positions.
        vec2 ndc_pre = (gl_FragCoord.xy / resolution) * 2.0 - 1.0;
        vec2 cam_local_pre = vec2(ndc_pre.x * (resolution.x / resolution.y) * ORTHO_H, -ndc_pre.y * ORTHO_H);
        vec2 world_uv = camera_pos + cam_local_pre;
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

        // --- Arena Ring overlay ---
        // world_uv was already computed at the top of this branch.
        const float ARENA_R = ORTHO_H * 2.4;        // matches shared.ARENA_RADIUS
        const float RING_HALF_W = 0.022;            // half-thickness of the visible ring
        float dist_from_center = length(world_uv);

        // Anti-aliased ring: peak intensity at ARENA_R, falls off over RING_HALF_W on each side.
        float ring_d = abs(dist_from_center - ARENA_R);
        float ring_alpha = 1.0 - smoothstep(0.0, RING_HALF_W, ring_d);

        // Subtle outside-arena darkening so the play area visually "pops".
        float outside_factor = smoothstep(ARENA_R, ARENA_R + 0.15, dist_from_center);
        final_color *= mix(1.0, 0.55, outside_factor);

        // Ring colour: cyan when healthy, ramps to red as HP drops; pulse rate also speeds up at low HP.
        float danger = clamp(1.0 - player_hp_ratio, 0.0, 1.0);
        float pulse_rate = mix(1.5, 6.0, danger);
        vec3 healthy_ring = vec3(0.55, 0.85, 1.0);
        vec3 danger_ring  = vec3(1.0, 0.25, 0.30);
        vec3 ring_base = mix(healthy_ring, danger_ring, danger);
        vec3 ring_color = ring_base * (0.85 + 0.15 * sin(time * pulse_rate));
        final_color = mix(final_color, ring_color, ring_alpha * 0.95);

        // --- RMB full-charge beam (directional purple lance with screen warp) ---
        // Drawn in world_uv so it lives in the world, scrolls with the camera, and reads as
        // "the player just fired the right-click weapon down their aim line".
        float beam_fade = clamp(rmb_beam_params.x, 0.0, 1.0);
        if (beam_fade > 0.001 && length(rmb_beam_origin_dir.zw) > 0.001) {
            vec2  beam_origin    = rmb_beam_origin_dir.xy;
            vec2  beam_dir       = normalize(rmb_beam_origin_dir.zw);
            vec2  beam_perp      = vec2(-beam_dir.y, beam_dir.x);
            float beam_length    = rmb_beam_params.y;
            float beam_half_w    = rmb_beam_params.z;

            // Project the fragment's world position onto the beam axis. `t` is distance along
            // the beam from origin; `s` is signed offset perpendicular to the axis.
            vec2  rel_w          = world_uv - beam_origin;
            float t              = dot(rel_w, beam_dir);
            float s              = dot(rel_w, beam_perp);

            if (t > -0.05 && t < beam_length + 0.05) {
                // Capsule SDF along the beam axis (rounded ends).
                float clamped_t = clamp(t, 0.0, beam_length);
                vec2  closest   = beam_origin + beam_dir * clamped_t;
                float d_capsule = length(world_uv - closest);

                // Bright core + soft outer glow, both fading with `beam_fade` (1=just-fired, 0=ended).
                float core_t  = smoothstep(beam_half_w * 0.55, 0.0, d_capsule);
                float glow_t  = smoothstep(beam_half_w * 2.5, 0.0, d_capsule);
                float energy  = pow(beam_fade, 0.5);

                // Forward-fade so the beam reads as travelling outward: stronger near the tip
                // early, retreats back toward the player as it dies.
                float front   = clamp(t / beam_length, 0.0, 1.0);
                float head    = smoothstep(beam_fade - 0.15, beam_fade + 0.05, 1.0 - front);
                float tail_atten = mix(1.0, head, 0.6);

                vec3  core_col = vec3(1.0, 0.85, 1.0);
                vec3  glow_col = vec3(0.85, 0.40, 1.0);
                final_color = mix(final_color, glow_col, glow_t * energy * 0.55 * tail_atten);
                final_color = mix(final_color, core_col, core_t * energy * tail_atten);

                // Screen-space warp: pinch the background slightly toward the beam axis,
                // animated with a moving ripple along its length. Cheap re-sample-free version:
                // we just recolour with a noise-jittered shift in `final_color`.
                float warp_band = exp(-(s * s) / (beam_half_w * beam_half_w * 9.0));
                float ripple    = sin(t * 14.0 - tick * 18.0) * 0.5 + 0.5;
                float warp_amt  = warp_band * energy * 0.18 * (0.6 + 0.4 * ripple);
                final_color += glow_col * warp_amt;
            }
        }

        // --- Wave Button (interactable at world origin) ---
        // wave_button_state: x=next_idx, y=remaining_to_press, z=in_range, w=press_flash
        float btn_remaining   = wave_button_state.y;          // 10..0
        float btn_in_range    = wave_button_state.z;
        float btn_flash       = wave_button_state.w;
        const float BTN_R     = 0.16;                         // matches WAVE_BUTTON_VISUAL_RADIUS
        float btn_dist        = length(world_uv);
        if (btn_remaining > 0.5 && btn_dist < BTN_R * 4.0) {
            // Outer halo grows when player in range
            float halo_outer  = BTN_R * mix(1.6, 2.6, btn_in_range) + btn_flash * 0.6;
            float halo_alpha  = (1.0 - smoothstep(BTN_R * 0.95, halo_outer, btn_dist)) * 0.45;
            float halo_pulse  = 0.7 + 0.3 * sin(time * mix(2.0, 5.5, btn_in_range));
            vec3  halo_col    = mix(vec3(0.55, 0.9, 1.0), vec3(1.0, 0.85, 0.4), btn_in_range);
            final_color += halo_col * halo_alpha * halo_pulse * mix(0.5, 1.2, btn_in_range);

            // Outer ring of the button itself
            float outer_ring  = abs(btn_dist - BTN_R);
            float ring_alpha2 = 1.0 - smoothstep(0.0, 0.018, outer_ring);
            final_color = mix(final_color, vec3(0.85, 0.95, 1.0) + halo_col * 0.4, ring_alpha2);

            // Inner core (a faceted hexagonal feel via 6-arm sin modulation)
            float btn_angle = atan(world_uv.y, world_uv.x);
            float arm = 0.5 + 0.5 * cos(btn_angle * 6.0 + time * 0.8);
            float inner_r = BTN_R * (0.55 + 0.05 * arm);
            float inner_alpha = 1.0 - smoothstep(inner_r - 0.012, inner_r + 0.012, btn_dist);
            vec3 core_col = mix(vec3(0.30, 0.55, 0.95), vec3(1.0, 0.95, 0.4), btn_flash);
            core_col *= 0.7 + 0.5 * (0.5 + 0.5 * sin(time * 3.0));
            final_color = mix(final_color, core_col, inner_alpha * (0.55 + 0.45 * btn_in_range));

            // Pip indicators around the ring: one filled pip per remaining wave to press.
            int remaining_int = int(btn_remaining + 0.5);
            const int MAX_PIPS = 10;
            const float PIP_R = 0.025;
            float pip_orbit = BTN_R + 0.06;
            for (int p = 0; p < MAX_PIPS; ++p) {
                if (p >= remaining_int) break;
                float pip_angle = float(p) * (6.28318530718 / float(MAX_PIPS)) - 1.5707963 + time * 0.12;
                vec2 pip_pos = vec2(cos(pip_angle), sin(pip_angle)) * pip_orbit;
                float d = length(world_uv - pip_pos);
                float pip_alpha = 1.0 - smoothstep(PIP_R - 0.006, PIP_R, d);
                vec3 pip_col = vec3(0.85, 0.95, 1.0) * (0.6 + 0.4 * sin(time * 3.0 + float(p)));
                final_color = mix(final_color, pip_col, pip_alpha);
            }
        }

        // --- SHOP overlay ---
        // Drawn last on top of everything else in the bg pass: a dim overlay + 3 rounded cards
        // at fixed screen-NDC positions. Card-rect geometry duplicated in game/shop/shop.odin
        // for hover detection.
        if (shop_state.x > 0.5) {
            // Rebuild NDC from gl_FragCoord (y already flipped earlier above).
            vec2 ndc = (gl_FragCoord.xy / resolution) * 2.0 - 1.0;
            ndc.y = -ndc.y; // flip back to "y up = top"
            // Dim the world.
            final_color = mix(final_color, vec3(0.02, 0.02, 0.04), 0.78);

            const float CARD_HALF_W = 0.20;
            const float CARD_HALF_H = 0.30;
            const float CARD_Y      = -0.05;
            const float CARD_R      = 0.04; // corner-radius approximation via inset SDF
            float centres[3];
            centres[0] = -0.55; centres[1] = 0.0; centres[2] = 0.55;
            float tiers[3];
            tiers[0] = shop_tiers.x; tiers[1] = shop_tiers.y; tiers[2] = shop_tiers.z;
            int hovered = int(shop_state.y);

            for (int i = 0; i < 3; ++i) {
                float cx = centres[i];
                vec2 d = abs(vec2(ndc.x - cx, ndc.y - CARD_Y)) - vec2(CARD_HALF_W - CARD_R, CARD_HALF_H - CARD_R);
                float card_sdf = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - CARD_R;
                if (card_sdf > 0.012) continue;

                int t = int(tiers[i] + 0.5);
                vec3 fill = vec3(0.10, 0.12, 0.18);
                vec3 accent;
                if (t == 1) accent = vec3(0.45, 0.85, 1.00); // common — cyan
                else if (t == 2) accent = vec3(0.85, 0.55, 1.00); // uncommon — purple
                else accent = vec3(1.00, 0.80, 0.30); // rare — gold

                bool is_hovered = (i == hovered);
                if (is_hovered) {
                    fill   *= 1.6;
                    accent *= 1.25;
                }

                // Rounded rect fill (alpha falls off at the edge).
                float fill_alpha  = smoothstep(0.0, -0.005, card_sdf);
                float border_d    = abs(card_sdf + 0.012);
                float border_alpha = smoothstep(0.012, 0.0, border_d);

                // Inner glow accent at the top edge as a "tier banner".
                float top_edge = abs((ndc.y - (CARD_Y + CARD_HALF_H * 0.78))) - 0.014;
                float banner = 1.0 - smoothstep(0.0, 0.020, top_edge);
                banner *= step(card_sdf, -0.003); // only inside card

                vec3 card_color = mix(fill, accent * 1.8, border_alpha);
                card_color = mix(card_color, accent, banner * 0.85);

                final_color = mix(final_color, card_color, fill_alpha);
            }
        }

        // --- Low-HP screen feedback ---
        // Vignette darkening + red tint that intensifies as HP drops, with a heartbeat pulse
        // whose rate climbs near death. Lives in fs_bg so it covers everything not painted by
        // the foreground passes (players/enemies stay at full brightness, but the surrounding
        // arena reads as panicked).
        float low_hp_t = pow(clamp(1.0 - player_hp_ratio, 0.0, 1.0), 1.3);
        if (low_hp_t > 0.001) {
            float pulse_rate_lo = mix(1.5, 6.0, low_hp_t);
            float heartbeat = 0.7 + 0.3 * pow(0.5 + 0.5 * sin(time * pulse_rate_lo), 4.0);
            vec2 screen_uv = gl_FragCoord.xy / resolution;
            vec2 from_centre = screen_uv - 0.5;
            from_centre.x *= resolution.x / resolution.y;
            float vignette_dist = length(from_centre);
            float vignette = smoothstep(0.25, 0.75, vignette_dist);
            final_color *= mix(1.0, 0.45, vignette * low_hp_t * heartbeat);
            vec3 red_tint = vec3(1.0, 0.15, 0.18);
            float red_amount = low_hp_t * (vignette * 0.85 + 0.15) * heartbeat * 0.55;
            final_color = mix(final_color, red_tint, red_amount);
        }

        frag_color = vec4(clamp(final_color, 0.0, 1.0), 1.0);
    }
}
@end
@program bg vs_bg fs_bg

// --- Player Shaders (With Health Display) ---

@vs vs_player
layout(binding=0) uniform Player_Vs_Params { mat4 mvp; };
in vec2 position;
out vec2 v_uv;
void main() {
    gl_Position = mvp * vec4(position.xy, 0.0, 1.0);
    v_uv = position.xy * 0.5 + 0.5;
}
@end

@fs fs_player
layout(binding=1) uniform Player_Fs_Params {
    float tick;
    vec2 resolution;
    float player_hp_uniform;
    float player_max_hp_uniform;
    float player_invulnerable_timer_uniform;
    float player_invulnerability_duration_uniform;
    vec2 player_aim_dir;            // unit vector from player toward mouse (world space)
    float lmb_fire_flash;            // 0..1, set to 1 on LMB fire and decayed each frame
    float rmb_fire_flash;            // 0..1, set to 1 on RMB fire and decayed each frame
    float rmb_charge_ratio;          // current rmb_charge / RMB_BEAM_THRESHOLD; 0..1 = filling, >=1 = beam-ready, can exceed for overcharge
    float rmb_max_charge_ratio;      // soft cap (eff_rmb_max_charge / RMB_BEAM_THRESHOLD), used to scale the ring's "overcharge" portion
    float dash_flash;                // 0..1; 1 at dash start, decays over PLAYER_DASH_FLASH_DURATION. Drives stretch + cyan tint + glow.
    vec2  dash_direction;            // unit vector along the dash launch axis (stable post-dash)
    float echo_alpha;                // 1.0 for the live player draw; <1.0 for afterimage echoes (multiplies final alpha + tints cyan)
};
in vec2 v_uv;
out vec4 frag_color;

float sdCircle(vec2 p, float r) { return length(p) - r; }
mat2 rotate2d(float angle) { float c=cos(angle); float s=sin(angle); return mat2(c,-s,s,c); }

void main() {
    vec2 p_orig = v_uv - vec2(0.5);
    // --- Dash stretch ---
    // While dashing (or during the post-dash flash decay) we squash the player's local space
    // perpendicular to the dash axis and stretch it along the dash axis, so the ship reads as
    // a smear of motion. We do this BEFORE every other SDF computation so all the rings, blade,
    // glow, etc. inherit the deformation. The transform uses the inverse of the visual stretch
    // so that "outside" the deformed ship the body actually grows in screen-space.
    if (dash_flash > 0.001 && length(dash_direction) > 0.01) {
        vec2  axis    = normalize(dash_direction);
        vec2  perp    = vec2(-axis.y, axis.x);
        float along   = dot(p_orig, axis);
        float across  = dot(p_orig, perp);
        float stretch = 1.0 + dash_flash * 0.55;     // along-axis grows
        float squash  = 1.0 - dash_flash * 0.20;     // perp-axis shrinks
        // We're inverse-mapping the fragment's local position back to the un-deformed ship.
        along  /= stretch;
        across /= max(squash, 0.05);
        p_orig = axis * along + perp * across;
    }
    float anim_time = tick * 0.05;
    float color_time = tick * 0.5;
    float direct_tick = tick;

    float hp = player_hp_uniform;
    float max_hp = player_max_hp_uniform;
    float invul_timer = player_invulnerable_timer_uniform;
    float invul_duration = player_invulnerability_duration_uniform;

    // --- Define Default Component Colors ---
    vec3 color_core_default = vec3(0.5, 1.0, 1.0);    // Bright Cyan
    vec3 color_ring1_default = vec3(1.0, 0.3, 0.9);   // Magenta
    vec3 color_ring2_health_based = vec3(0.2, 0.5, 1.0); // Default Blue for Ring 2 (full HP)
    vec3 color_glow_dynamic = normalize(vec3(0.5+0.5*sin(color_time+0.0), 0.5+0.5*sin(color_time+2.094395), 0.5+0.5*sin(color_time+4.18879))) * 1.1;

    // --- Determine Persistent Health Color for Ring 2 ---
    if (hp <= 0.01) { 
        color_ring2_health_based = vec3(0.1, 0.1, 0.1); // Very dark for Ring 2 on death (it will be alpha'd out anyway)
    } else if (max_hp > 1.0) {
        float health_fraction = hp / max_hp;
        if (health_fraction <= 0.25) { 
            color_ring2_health_based = vec3(1.0, 0.2, 0.1); // Red
        } else if (health_fraction <= 0.5) { 
            color_ring2_health_based = vec3(1.0, 0.8, 0.1); // Yellow
        } else if (health_fraction <= 0.75) { 
            color_ring2_health_based = vec3(0.2, 1.0, 0.2); // Green
        }
        // Else it remains Blue (initial value)
    } else if (hp < max_hp && max_hp == 1.0) { // Max HP is 1 and took a hit
         color_ring2_health_based = vec3(1.0, 0.2, 0.1); // Red
    }


    // --- Define Player Glow Color ---
    vec3 player_glow_color = color_ring2_health_based; // Base glow on health ring color

    // --- Calculate Component Alphas & Apply Death State ---
    float core_alpha = 0.0;
    float ring1_alpha = 0.0;
    float ring2_alpha = 0.0;
    float glow_alpha_contrib = 0.0;
    float glow_shape_alpha = 0.0; // Initialize new glow alpha

    // Core
    float core_rad_anim = 0.04 + 0.005 * sin(anim_time * 25.0);
    float core_dist_sdf = sdCircle(p_orig, core_rad_anim);
    core_alpha = smoothstep(0.005, 0.0, core_dist_sdf); 
    if (hp <= 0.01) core_alpha *= (0.15 + 0.1 * sin(direct_tick * 35.0));

    // Ring 1
    float r1_rot = -anim_time * 1.5; float r1_squash = 0.3 + 0.7 * abs(cos(anim_time * 1.5));
    mat2 r1_invRot = rotate2d(-r1_rot); mat2 r1_invScale = mat2(1.0, 0.0, 0.0, 1.0 / r1_squash);
    vec2 p1_uv = r1_invScale * r1_invRot * p_orig;
    float r1_rad_anim = 0.1 + 0.01 * cos(anim_time * 18.0);
    float r1_thick = 0.015;
    float r1_dist_sdf = abs(sdCircle(p1_uv, r1_rad_anim)) - r1_thick * 0.5;
    ring1_alpha = smoothstep(0.004, 0.0, r1_dist_sdf);
    if (hp <= 0.01) ring1_alpha = 0.0;

    // Ring 2 — segmented HP indicator. N = max_hp arc segments around the player; lit segment
    // means "1 HP point remaining". Lost slots dim out and pulse with a heartbeat that speeds
    // up as more HP is missing, so the player both *counts* lit segments and *feels* damage.
    float r2_rot = anim_time * 1.1; float r2_squash = 0.4 + 0.6 * abs(sin(anim_time * 1.1 + 0.5));
    mat2 r2_invRot = rotate2d(-r2_rot); mat2 r2_invScale = mat2(1.0, 0.0, 0.0, 1.0 / r2_squash);
    vec2 p2_uv = r2_invScale * r2_invRot * p_orig;
    float r2_rad_anim = 0.18 + 0.01 * sin(anim_time * 12.0);
    float r2_thick = 0.012;            // slightly thicker so segments read at small max_hp
    float r2_dist_sdf = abs(sdCircle(p2_uv, r2_rad_anim)) - r2_thick * 0.5;
    float r2_band_alpha = smoothstep(0.003, 0.0, r2_dist_sdf);

    float seg_alpha_mul = 1.0;
    float seg_brightness = 1.0;
    if (max_hp > 0.5) {
        // Segment angle in [0,1) measured from +X axis, counter-clockwise. Use the ring's local
        // (rotated, squashed) frame so segments don't wobble with the existing ring animation.
        float seg_angle = atan(p2_uv.y, p2_uv.x);
        float frac = mod(seg_angle / 6.28318530718 + 1.0, 1.0);
        float per_seg = 1.0 / max_hp;
        float seg_local = fract(frac * max_hp);          // 0..1 within the current segment
        float seg_idx_f = floor(frac * max_hp);
        // Tiny dark slivers at segment boundaries make the count visually distinct.
        float gap = smoothstep(0.0, 0.04, seg_local) * smoothstep(1.0, 0.96, seg_local);
        bool lit = seg_idx_f < hp - 0.5;
        if (lit) {
            seg_alpha_mul = gap;
        } else {
            // Dim + heartbeat for lost slots. Pulse rate climbs with damage.
            float damage_t = clamp(1.0 - hp / max_hp, 0.0, 1.0);
            float pulse_rate_hp = mix(2.0, 6.0, damage_t);
            float heartbeat_lo = 0.5 + 0.5 * sin(direct_tick * pulse_rate_hp);
            seg_alpha_mul = (0.16 + 0.10 * heartbeat_lo * damage_t) * gap;
            seg_brightness = 0.55;     // lost slots are also colour-darkened
        }
    }
    ring2_alpha = r2_band_alpha * seg_alpha_mul;
    if (hp <= 0.01) ring2_alpha = 0.0;

    // --- SDF for Health-Based Glow ---
    float glow_radius = r2_rad_anim + 0.05; // Glow slightly larger than the outer ring
    float glow_dist_sdf = sdCircle(p_orig, glow_radius);

    // --- Calculate Alpha for Health-Based Glow ---
    glow_shape_alpha = 0.5 * smoothstep(0.025, 0.0, glow_dist_sdf); // Adjust 0.5 for intensity, 0.025 for spread
    if (hp <= 0.01) glow_shape_alpha = 0.0; // No glow on death

    // Glow & Spikes (existing dynamic glow)
    float dist_glow = length(p_orig);
    float spike_rot_glow = anim_time * 0.8; 
    float base_angle_glow = atan(p_orig.y, p_orig.x);
    float rotated_angle_glow = base_angle_glow + spike_rot_glow;
    float spikes_glow = pow(abs(sin(rotated_angle_glow * 8.0)), 32.0);
    float glow_intensity_val = pow(max(0.0, 1.0 - dist_glow / 0.5), 5.0);
    glow_intensity_val *= (0.7 + 5.0 * spikes_glow);
    glow_intensity_val *= (0.8 + 0.2 * sin(anim_time * 15.0 + dist_glow * 12.0));
    glow_alpha_contrib = glow_intensity_val * 0.6;
    if (hp <= 0.01) glow_alpha_contrib = 0.0;

    // --- Aim Indicator Blade ---
    // A bright triangular blade sits on the outer ring pointing toward the cursor, plus a thin
    // shaft extending back into the body. Together they form an unmistakable arrow so the player
    // always reads where they're aiming without looking at the cursor.
    float blade_alpha = 0.0;
    float shaft_alpha = 0.0;
    vec3  blade_color = vec3(1.0, 1.0, 0.75);
    if (length(player_aim_dir) > 0.01 && hp > 0.01) {
        vec2 aim_n  = normalize(player_aim_dir);
        vec2 perp_n = vec2(-aim_n.y, aim_n.x);
        float along  = dot(p_orig, aim_n);
        float across = dot(p_orig, perp_n);
        float blade_centre   = 0.30;             // pushed outward so it sits clear of the rings
        float blade_half_len = 0.10;             // longer tip
        float blade_half_wid = 0.062;            // wider base
        float along_local = along - (blade_centre - blade_half_len);
        if (along_local >= 0.0 && along_local <= 2.0 * blade_half_len) {
            float taper = 1.0 - (along_local / (2.0 * blade_half_len));
            float wid   = blade_half_wid * taper;
            float aa    = 0.005;
            float side  = abs(across) - wid;
            blade_alpha = smoothstep(aa, -aa, side);
        }
        // Thin shaft from outer ring (along ~ 0.13) up to the blade base (along ~ 0.20).
        float shaft_start = 0.13;
        float shaft_end   = blade_centre - blade_half_len;
        if (along >= shaft_start && along <= shaft_end) {
            float shaft_aa = 0.004;
            float shaft_side = abs(across) - 0.012;
            shaft_alpha = smoothstep(shaft_aa, -shaft_aa, shaft_side) * 0.7;
        }
        // Subtle idle pulse so the arrow reads as "active". No on-character LMB-fire boost —
        // the shot's "click" lives entirely on the projectile, so the player itself doesn't flash.
        float pulse = 0.85 + 0.15 * sin(direct_tick * 8.0);
        blade_alpha *= pulse;
        shaft_alpha *= pulse;
    }

    // --- RMB Charge Ring ---
    // Continuous arc around the player that fills with rmb_charge_ratio. 0..1 fills clockwise
    // from the top; at 1.0 the ring is closed. Overcharge (>1) thickens & brightens the ring.
    float charge_alpha = 0.0;
    vec3  charge_color = vec3(0.85, 0.5, 1.0);
    if (hp > 0.01 && rmb_charge_ratio > 0.001) {
        float r_play = length(p_orig);
        // Place the ring just outside the outer health ring, inside the aim blade region.
        float ring_r = 0.255;
        float ring_thick = 0.012 + 0.008 * clamp(rmb_charge_ratio - 1.0, 0.0, 1.0);
        float ring_dist = abs(r_play - ring_r);
        if (ring_dist < ring_thick + 0.006) {
            // Sweep angle: fill clockwise from -90° (top of player) by 2π * fraction (cap at full circle).
            float angle = atan(p_orig.y, p_orig.x);              // -PI..PI
            // Convert to a 0..1 fraction starting at the top (-PI/2), going clockwise.
            const float TAU = 6.28318530718;
            float swept = mod(1.5707963 - angle, TAU) / TAU;
            float fill_frac = clamp(rmb_charge_ratio, 0.0, 1.0);
            // Once charge >= 100% the entire ring is on. Overcharge keeps it brightened.
            float in_arc = (rmb_charge_ratio >= 1.0) ? 1.0 : step(swept, fill_frac);
            float ring_smooth = smoothstep(ring_thick, ring_thick - 0.006, ring_dist);
            charge_alpha = ring_smooth * in_arc * (0.65 + 0.35 * clamp(rmb_charge_ratio, 0.0, 1.5));
            // Beam-ready pulse: when at-or-over 100%, throb the ring so player notices.
            if (rmb_charge_ratio >= 1.0) {
                float throb = 0.7 + 0.3 * sin(direct_tick * 7.0);
                charge_alpha *= throb;
                charge_color = mix(vec3(0.85, 0.5, 1.0), vec3(1.0, 0.95, 1.0), 0.6);
            }
        }
    }

    // --- RMB Inward Suck ---
    // Just before the swirling charge spawns, drag a few faint rings inward toward the core so
    // the player feels the "absorb" beat before the visual explosion outward.
    float suck_alpha = 0.0;
    if (rmb_fire_flash > 0.001 && hp > 0.01) {
        float r2          = length(p_orig);
        float suck_phase  = 1.0 - rmb_fire_flash;             // 0..1 as flash decays
        // Two concentric inward-collapsing rings.
        float ring_a = smoothstep(0.025, 0.0, abs(r2 - mix(0.32, 0.06, suck_phase)));
        float ring_b = smoothstep(0.025, 0.0, abs(r2 - mix(0.40, 0.14, suck_phase)));
        suck_alpha   = (ring_a + ring_b * 0.6) * rmb_fire_flash;
    }

    // --- Dash glow ---
    // A bright cyan/white energy halo behind the ship along the dash axis. Strongest right at
    // launch, fades with `dash_flash`. Sits inside the player quad (small footprint) — the
    // afterimage echoes drawn in earlier passes provide the long streak.
    float dash_alpha = 0.0;
    vec3  dash_color = vec3(0.55, 0.95, 1.0);
    if (dash_flash > 0.001 && hp > 0.01 && length(dash_direction) > 0.01) {
        vec2  axis_d  = normalize(dash_direction);
        vec2  perp_d  = vec2(-axis_d.y, axis_d.x);
        float along_d = dot(p_orig, axis_d);
        float across_d = dot(p_orig, perp_d);
        // Capsule-ish glow that extends from just behind the ship toward the launch direction.
        // Negative `along_d` is "behind" the player relative to dash forward.
        float glow_band  = exp(-(across_d * across_d) / 0.012);
        float along_falloff = smoothstep(0.30, -0.10, along_d); // bright behind, dim in front
        dash_alpha = glow_band * along_falloff * dash_flash * 0.85;
    }

    // --- Combine Colors Additively & Determine Final Alpha ---
    vec3 combined_color = vec3(0.0);
    combined_color += player_glow_color * glow_shape_alpha; // Health-based glow first (behind other elements)
    combined_color += color_glow_dynamic * glow_alpha_contrib * 2.0; // Existing dynamic glow/spikes
    combined_color += color_ring2_health_based * ring2_alpha * seg_brightness;
    combined_color += color_ring1_default * 1.5 * ring1_alpha; // Apply brightness multiplier here
    combined_color += color_core_default * core_alpha;
    combined_color += blade_color * blade_alpha * 1.4;
    combined_color += blade_color * shaft_alpha;
    combined_color += vec3(0.85, 0.5, 1.0) * suck_alpha * 1.8;
    combined_color += charge_color * charge_alpha * 1.2;
    combined_color += dash_color * dash_alpha * 1.5;

    float final_alpha = max(max(max(core_alpha, ring1_alpha), max(ring2_alpha, glow_alpha_contrib)), glow_shape_alpha);
    final_alpha = max(final_alpha, max(blade_alpha, shaft_alpha));
    final_alpha = max(final_alpha, suck_alpha);
    final_alpha = max(final_alpha, charge_alpha);
    final_alpha = max(final_alpha, dash_alpha);

    // --- Afterimage echo modulation ---
    // The renderer draws the player multiple times per frame during a dash: the live draw
    // passes echo_alpha=1.0; ghost echoes pass echo_alpha<1.0 with a position translated to a
    // stored trail point. For ghosts we dim everything and shift colour toward cyan so the
    // streak reads as "motion blur" rather than a stack of solid ships.
    if (echo_alpha < 0.999) {
        float ghost = clamp(echo_alpha, 0.0, 1.0);
        combined_color = mix(combined_color, dash_color * 0.9, 0.55) * ghost;
        final_alpha *= ghost;
    }

    // --- Apply Flash Overlay (if invulnerable and alive) ---
    if (invul_timer > 0.001 && invul_duration > 0.001 && hp > 0.01) {
        float invul_ratio = invul_timer / invul_duration;
        float flash_pulse = 0.5 + 0.5 * sin(direct_tick * 60.0 + invul_ratio * 20.0); 
        float flash_amount = pow(invul_ratio, 1.0) * flash_pulse; 
        flash_amount = clamp(flash_amount * 1.5, 0.0, 1.0); // Make flash effect strong

        vec3 flash_overlay_color = vec3(1.0, 1.0, 1.0); // Bright white flash
        combined_color += flash_overlay_color * flash_amount * final_alpha; 
    }
    
    frag_color = vec4(clamp(combined_color, 0.0, 1.0), clamp(final_alpha, 0.0, 1.0));
}
@end
@program player vs_player fs_player


// --- Particle Shaders (Copied from newer code) ---

@vs vs_particle
layout(binding=0) uniform particle_vs_params { mat4 view_proj; };

layout(location=0) in vec2 quad_pos; 
layout(location=1) in vec2 quad_uv;  

layout(location=2) in vec4 instance_pos_size_rot; 
layout(location=3) in vec4 instance_color;        

out vec4 particle_color;
out vec2 particle_uv;
out float particle_dist; 

void main() {
    vec2 inst_pos = instance_pos_size_rot.xy;
    float inst_size = instance_pos_size_rot.z;
    float inst_rot = instance_pos_size_rot.w;

    float cr = cos(inst_rot); float sr = sin(inst_rot);
    mat2 rot_mat = mat2(cr, -sr, sr, cr);
    vec2 final_local_pos = rot_mat * (quad_pos * inst_size);
    vec2 final_world_pos = final_local_pos + inst_pos;
    gl_Position  = view_proj * vec4(final_world_pos, 0.0, 1.0);

    particle_color = instance_color; 
    particle_uv = quad_uv;
    particle_dist = length(quad_pos); 
}
@end

@fs fs_particle
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
@end
@program particle vs_particle fs_particle


// --- Blackhole Projectile Shaders ---
@vs vs_blackhole
// ... (vs_blackhole remains the same) ...
layout(binding=0) uniform blackhole_vs_params { mat4 view_proj; };
layout(location=0) in vec2 quad_pos; 
layout(location=1) in vec2 quad_uv;  
layout(location=2) in vec4 instance_pos_size_rot; 
layout(location=3) in vec4 instance_color;        
out vec4 bh_color_out;
out vec2 bh_uv_out;
void main() {
    vec2 inst_pos = instance_pos_size_rot.xy;
    float inst_size = instance_pos_size_rot.z;
    float inst_rot = instance_pos_size_rot.w;
    float cr = cos(inst_rot); float sr = sin(inst_rot);
    mat2 rot_mat = mat2(cr, -sr, sr, cr);
    vec2 final_local_pos = rot_mat * (quad_pos * inst_size);
    vec2 final_world_pos = final_local_pos + inst_pos;
    gl_Position  = view_proj * vec4(final_world_pos, 0.0, 1.0);
    bh_color_out = instance_color; 
    bh_uv_out = quad_uv;
}
@end

@fs fs_blackhole
layout(binding=1) uniform blackhole_fs_params { float tick; };

in vec4 bh_color_out; // .a is life_ratio
in vec2 bh_uv_out;

out vec4 frag_color;

void main() {
    vec2 uv_centered = bh_uv_out - vec2(0.5); 

    // --- Main Body Shape ---
    float body_uv_half_width = 0.15; 
    float body_uv_half_length = 0.40; // Slightly shorter than before to make tail more distinct
    float body_ref_radius = 1.0;
    vec2 body_oval_scale = vec2(body_ref_radius / body_uv_half_width, body_ref_radius / body_uv_half_length);
    float dist_for_body_mask = length(uv_centered * body_oval_scale);
    float body_aa = 0.1; 
    float body_shape_alpha = 1.0 - smoothstep(body_ref_radius - body_aa, body_ref_radius + body_aa, dist_for_body_mask);

    if (body_shape_alpha < 0.01 && bh_color_out.a < 0.01) { // Discard if fully transparent from shape and lifetime
        discard;
    }

    // --- Swirl Calculation (for body color) ---
    float dist_from_center_for_swirl = length(uv_centered); // Swirl based on circular distance
    float angle = atan(uv_centered.y, uv_centered.x);
    float swirl_speed = -7.0; // Slightly faster swirl       
    float swirl_angular_freq = 8.0;  
    float swirl_radial_freq = 5.0;   
    float swirl_time_offset_factor = 0.25; 
    float swirl_value = sin(
        dist_from_center_for_swirl * swirl_radial_freq * (1.0 + 0.5 * sin(tick * swirl_time_offset_factor)) + 
        tick * swirl_speed
    );
    swirl_value = swirl_value * 0.5 + 0.5; 
    swirl_value = smoothstep(0.3, 0.7, swirl_value); // Adjusted smoothstep for potentially more contrast

    vec3 color_core_black = vec3(0.0, 0.0, 0.0);
    vec3 color_swirl_dark = vec3(0.1, 0.0, 0.2); // Slightly darker base swirl
    vec3 color_swirl_bright = vec3(0.7, 0.3, 0.9); // Brighter swirl highlight

    vec3 body_swirl_color = mix(color_swirl_dark, color_swirl_bright, swirl_value);
    float core_radius_effect = 0.18; // Slightly smaller core for more swirl visibility
    float core_influence = 1.0 - smoothstep(0.0, core_radius_effect, dist_from_center_for_swirl);
    vec3 body_base_rgb = mix(body_swirl_color, color_core_black, core_influence);

    // --- Glow and Tail Calculation ---
    // The 5.8x boost was meant for HDR + bloom; with the current LDR target it saturates every
    // channel so the bullet read as a flat white oval. Tone the glow down to LDR-safe values so
    // the purple swirl underneath actually shows through.
    vec3 glow_color = vec3(0.95, 0.55, 1.0) * 1.1;

    // Glow shape: wider and significantly longer than the body, especially at the tail
    float glow_uv_half_width = body_uv_half_width * 1.8; // Glow is wider
    float glow_uv_base_half_length = body_uv_half_length * 1.5; // Base length for the glow head

    float tail_elongation_factor = 1.0 + max(0.0, -uv_centered.y * 3.0); // Increase multiplier for longer tail
    float dynamic_glow_uv_half_length = glow_uv_base_half_length * tail_elongation_factor;

    vec2 glow_oval_scale = vec2(body_ref_radius / glow_uv_half_width, body_ref_radius / dynamic_glow_uv_half_length);
    float dist_for_glow_mask = length(uv_centered * glow_oval_scale);
    
    float glow_aa = 0.15; // Softer antialiasing for glow
    float glow_shape_alpha = 1.0 - smoothstep(body_ref_radius - glow_aa, body_ref_radius + glow_aa, dist_for_glow_mask);

    float glow_intensity_bias = (1.0 - smoothstep(0.0, 0.4, abs(uv_centered.x))); // Stronger along Y-axis spine
    glow_intensity_bias *= (0.5 + 0.5 * smoothstep(-0.5, 0.5, -uv_centered.y)); // Stronger towards rear

    float effective_glow_strength = glow_shape_alpha * glow_intensity_bias * 0.8; // Base strength for glow

    // --- Combine Colors and Alpha ---
    float lifetime_alpha = bh_color_out.a; 
    float base_projectile_opacity = 0.80; // Overall opacity for the effect
    vec3 final_rgb = body_base_rgb + glow_color * effective_glow_strength;
    float combined_shape_alpha = max(body_shape_alpha, effective_glow_strength);
    float overall_alpha = combined_shape_alpha * lifetime_alpha * base_projectile_opacity;

    frag_color = vec4(clamp(final_rgb, 0.0, 2.5), clamp(overall_alpha, 0.0, 1.0)); // Allow even brighter for bloom
}
@end
@program blackhole vs_blackhole fs_blackhole

@vs vs_enemy
layout(binding=0) uniform enemy_vs_params { mat4 view_proj; };
layout(location=0) in vec2 quad_pos_in;    
layout(location=1) in vec2 quad_uv_in;     
layout(location=2) in vec2 instance_pos_vs_in;
layout(location=3) in float instance_main_rotation_vs_in;
layout(location=4) in float instance_visual_scale_vs_in;  
layout(location=5) in vec4 instance_color_vs_in;      
layout(location=6) in vec4 instance_effect_params_vs_in; 
layout(location=7) in float instance_enemy_type_vs_in; 
out vec4 enemy_color_out_fs;
out vec2 enemy_uv_out_fs;
out vec4 enemy_effect_params_fs; 
out float enemy_visual_scale_fs_out;
out float v_enemy_type_fs; 
out float v_enemy_main_rotation_fs;
void main() {
    float final_size_for_quad = instance_visual_scale_vs_in; 
    float cr = cos(instance_main_rotation_vs_in);
    float sr = sin(instance_main_rotation_vs_in);
    mat2 main_rot_mat = mat2(cr, -sr, sr, cr);
    vec2 scaled_quad_pos = quad_pos_in * final_size_for_quad; 
    vec2 rotated_quad_pos = main_rot_mat * scaled_quad_pos; // This rotates the quad itself
                                                           // For boss, instance_main_rotation_vs_in is for aiming, not quad orientation.
                                                           // The quad for the boss should probably remain unrotated (or have a base rotation if sprite isn't aligned)
                                                           // If the quad is rotated by v_enemy_main_rotation_fs, then uv_centered calculations in FS might be off
                                                           // if they assume a non-rotated quad. Let's assume boss quad is not rotated by this aiming angle.
    if (instance_enemy_type_vs_in > 1.5 && instance_enemy_type_vs_in < 2.5) { // BOSS_CHROME_ORB
         rotated_quad_pos = scaled_quad_pos; // No instance-level rotation for boss quad
    }
    if (instance_enemy_type_vs_in > 3.5 && instance_enemy_type_vs_in < 4.5) { // SNIPER (telegraph in FS)
         rotated_quad_pos = scaled_quad_pos;
    }


    vec2 final_world_pos = rotated_quad_pos + instance_pos_vs_in;
    gl_Position = view_proj * vec4(final_world_pos, 0.0, 1.0);
    enemy_color_out_fs = instance_color_vs_in;
    enemy_uv_out_fs = quad_uv_in; 
    enemy_effect_params_fs = instance_effect_params_vs_in;
    enemy_visual_scale_fs_out = instance_visual_scale_vs_in; // This is current_size * 3.0
    v_enemy_type_fs = instance_enemy_type_vs_in; 
    v_enemy_main_rotation_fs = instance_main_rotation_vs_in; // This is the aiming angle
}
@end
@fs fs_enemy
layout(binding=1) uniform enemy_fs_params { float tick; };

in vec4 enemy_color_out_fs; 
in vec2 enemy_uv_out_fs;    
in vec4 enemy_effect_params_fs; 
in float enemy_visual_scale_fs_out;  // This is world_size * 3.0
in float v_enemy_type_fs; 
in float v_enemy_main_rotation_fs; // Boss aiming angle

out vec4 frag_color;

const float PI = 3.14159265359;

mat2 rotate2d(float angle) {
    float s = sin(angle);
    float c = cos(angle);
    return mat2(c, -s, s, c); 
}

float sdf_rectangle(vec2 p, vec2 half_dims) { 
    vec2 d = abs(p) - half_dims; 
    return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0);
}

float sdf_star(vec2 uv, int points, float inner_radius_factor, float outer_radius_param) {
    float angle_step = PI / float(points);
    float angle = atan(uv.y, uv.x);
    float r = length(uv);
    float current_angle_segment = mod(angle, 2.0 * angle_step); 
    float segment_angle_offset = current_angle_segment - angle_step;
    float inner_radius = outer_radius_param * inner_radius_factor;
    float effective_radius = mix(outer_radius_param, inner_radius, abs(segment_angle_offset) / angle_step);
    return r - effective_radius;
}

void main() {
    vec2 uv_centered = enemy_uv_out_fs - vec2(0.5); // Ranges -0.5 to 0.5 for the base quad
    const float enemy_visual_scale_on_quad = 3.0; // Internal scaling factor for shader's working UV space

    // --- BOSS_CHROME_ORB Rendering Path ---
    if (v_enemy_type_fs > 1.5 && v_enemy_type_fs < 2.5) { // BOSS_CHROME_ORB (type 2.0)
        // p_scaled_uv ranges -1.5..1.5. enemy_visual_scale_fs_out is BOSS_QUAD_WORLD_DIAMETER, so the
        // world<->p_scaled_uv conversion factor is enemy_visual_scale_on_quad / quad_world_diameter.
        vec2 p = uv_centered * enemy_visual_scale_on_quad;
        float w2u = (enemy_visual_scale_fs_out > 0.001) ? (enemy_visual_scale_on_quad / enemy_visual_scale_fs_out) : 1.0;

        // Effect params (alive):  x=is_dying, y=roll_angle, z=laser_length_world, w=phase
        // Effect params (dying):  x=1,        y=death_off,  z=part_scale,         w=dying_alpha_mult
        float is_dying       = enemy_effect_params_fs.x;
        float roll_angle     = (is_dying > 0.5) ? 0.0 : enemy_effect_params_fs.y;
        float laser_length_w = (is_dying > 0.5) ? 0.0 : enemy_effect_params_fs.z;
        float w_param        = enemy_effect_params_fs.w;
        float dying_alpha    = (is_dying > 0.5) ? w_param : 1.0;
        float boss_phase     = (is_dying > 0.5) ? 1.0    : w_param;
        float aim_angle      = v_enemy_main_rotation_fs;

        // hp_ratio comes from color.r; laser count from color.b * 10; fade-in timer from color.a.
        float hp_ratio       = clamp(enemy_color_out_fs.r, 0.0, 1.0);
        int   laser_count    = int(enemy_color_out_fs.b * 10.0 + 0.5);
        float fade_in_timer  = clamp(enemy_color_out_fs.a, 0.0, 1.0);
        if (laser_count < 1) laser_count = 1;
        if (laser_count > 6) laser_count = 6;

        // Decode the 6-element slot permutation packed as base-6 in color.g (max 46655).
        // Use uints to avoid HLSL5 X3556 ("integer divides may be much slower") on this
        // fixed-arity decoder.
        int slot_order[6];
        {
            uint e = uint(enemy_color_out_fs.g + 0.5);
            slot_order[0] = int(e % 6u); e /= 6u;
            slot_order[1] = int(e % 6u); e /= 6u;
            slot_order[2] = int(e % 6u); e /= 6u;
            slot_order[3] = int(e % 6u); e /= 6u;
            slot_order[4] = int(e % 6u); e /= 6u;
            slot_order[5] = int(e % 6u);
        }

        // World-unit constants for the orb body and the laser beam.
        const float ORB_RADIUS_W   = 0.18;  // matches ENEMY_BOSS_VISUAL_RADIUS
        const float LASER_WIDTH_W  = 0.07;  // matches BOSS_LASER_WIDTH
        const float TWO_PI         = 6.28318530718;
        const float SLOT_STEP      = TWO_PI / 6.0;

        float orb_r  = ORB_RADIUS_W * w2u;
        float dist_p = length(p);
        // Phase 2 chaos factor (0 at HP=50%, 1 at HP=0%) drives pulsing/sparks intensity.
        float chaos  = (boss_phase > 1.5) ? clamp((0.5 - hp_ratio) * 2.0, 0.0, 1.0) : 0.0;

        // ---------- Multi-laser fan (capsule SDF, looped) ----------
        float laser_length_p = laser_length_w * w2u;
        float laser_half_p   = (LASER_WIDTH_W * 0.5) * w2u;
        float beam_core_acc  = 0.0;
        float beam_glow_acc  = 0.0;

        // Bound the loop so the compiler can unroll; break early when we exceed laser_count.
        const int MAX_LASERS = 6;
        for (int k = 0; k < MAX_LASERS; ++k) {
            if (k >= laser_count) break;
            int   slot       = slot_order[k];
            float beam_angle = aim_angle + float(slot) * SLOT_STEP;

            // Fade factor: only the most recently added laser fades in (1 - timer); earlier beams full.
            float fade = 1.0;
            if (k == laser_count - 1 && fade_in_timer > 0.0) {
                fade = clamp(1.0 - fade_in_timer, 0.0, 1.0);
            }

            vec2 aim_k  = vec2(cos(beam_angle), sin(beam_angle));
            vec2 perp_k = vec2(-aim_k.y, aim_k.x);
            vec2 origin_k = aim_k * orb_r;
            vec2 rel_k    = p - origin_k;
            float along   = dot(rel_k, aim_k);
            float across  = dot(rel_k, perp_k);

            float capsule_sdf;
            if (along < 0.0) {
                capsule_sdf = length(rel_k) - laser_half_p;
            } else if (along > laser_length_p) {
                capsule_sdf = length(rel_k - aim_k * laser_length_p) - laser_half_p;
            } else {
                capsule_sdf = abs(across) - laser_half_p;
            }

            float laser_aa  = laser_half_p * 0.4 + 0.001;
            float beam_pulse = 0.75 + 0.25 * sin(tick * 14.0 - along * 18.0 + float(slot) * 1.7);
            float core_k     = smoothstep(laser_aa, -laser_aa, capsule_sdf) * beam_pulse;
            float glow_k     = smoothstep(laser_half_p * 5.0, 0.0, max(0.0, capsule_sdf));
            // Striations
            float strands_k  = 0.5 + 0.5 * sin(across * 90.0 + tick * 24.0 + along * 8.0);
            core_k          *= 0.85 + 0.15 * strands_k;

            // While fading in, the new beam shimmers more (extra strand modulation).
            if (fade < 1.0) {
                float charge_flicker = 0.5 + 0.5 * sin(tick * 40.0 + along * 12.0);
                core_k *= mix(charge_flicker, 1.0, fade);
                glow_k *= mix(0.6, 1.0, fade);
            }

            beam_core_acc += core_k * fade;
            beam_glow_acc += glow_k * fade;
        }

        // Phase-driven beam colours: phase 1 stays magenta-ish; phase 2 goes hot red.
        vec3 laser_core_rgb = (boss_phase > 1.5) ? vec3(1.0, 0.85, 0.55) : vec3(1.0, 0.95, 0.65);
        vec3 laser_glow_rgb = (boss_phase > 1.5) ? vec3(1.0, 0.30, 0.35) : vec3(1.0, 0.50, 0.85);
        vec3 laser_rgb      = laser_core_rgb * beam_core_acc + laser_glow_rgb * beam_glow_acc * 0.95;
        float laser_alpha   = clamp(beam_core_acc + beam_glow_acc * 0.55, 0.0, 1.0);
        if (laser_length_w <= 0.001) { laser_alpha = 0.0; laser_rgb = vec3(0.0); }

        // ---------- Orb body (chrome, with rolling treads) ----------
        float orb_aa     = max(orb_r * 0.06, 0.001);
        float orb_alpha  = smoothstep(orb_aa, -orb_aa, dist_p - orb_r);
        float ndist      = clamp(dist_p / max(orb_r, 0.0001), 0.0, 1.0);
        float foreshort  = sqrt(max(0.0, 1.0 - ndist * ndist));

        // Rotate uv into surface space so the bands move with the rolling motion.
        float cr = cos(roll_angle); float sr = sin(roll_angle);
        vec2 surf = vec2(cr * p.x + sr * p.y, -sr * p.x + cr * p.y);
        float band_freq = 14.0 / max(orb_r, 0.0001);
        float band      = 0.5 + 0.5 * sin(surf.x * band_freq);
        float tread     = smoothstep(0.5, 0.85, band) * foreshort;

        // Chrome shading
        vec2 light_dir = vec2(-0.55, 0.7);
        float lit      = clamp(0.55 + 0.55 * dot(p / max(orb_r, 0.0001), light_dir), 0.0, 1.0);
        vec3 base_chrome  = mix(vec3(0.45, 0.5, 0.62), vec3(0.95, 0.96, 1.0), lit);
        // Phase 1 keeps a cool tint; phase 2 ramps progressively hotter as HP drops.
        vec3 phase_tint;
        if (boss_phase > 1.5) {
            // Mid-phase-2 → orange, late phase 2 → blistering red.
            phase_tint = mix(vec3(1.20, 0.65, 0.55), vec3(1.40, 0.30, 0.30), chaos);
        } else {
            phase_tint = vec3(1.0);
        }
        vec3 orb_rgb      = base_chrome * phase_tint;
        orb_rgb           = mix(orb_rgb, orb_rgb * 0.30, tread * 0.75);

        vec2 spec_centre  = vec2(-orb_r * 0.40, orb_r * 0.45);
        float spec_d      = length(p - spec_centre);
        float spec        = smoothstep(orb_r * 0.30, 0.0, spec_d);
        orb_rgb          += vec3(1.0) * spec * 0.55;

        // Forward-facing eye aligned with the primary aim direction
        vec2 aim_primary  = vec2(cos(aim_angle), sin(aim_angle));
        vec2 eye_centre   = aim_primary * (orb_r * 0.55);
        float eye_d       = length(p - eye_centre);
        float eye_r       = orb_r * 0.28;
        float eye_alpha   = smoothstep(eye_r + orb_aa, eye_r - orb_aa, eye_d);
        float eye_inner   = smoothstep(eye_r * 0.4, 0.0, eye_d);
        vec3 eye_rgb      = mix(vec3(0.04, 0.0, 0.06), vec3(1.0, 0.35, 0.45), eye_inner);
        // Eye flicker scales with chaos in phase 2.
        float eye_flicker = 0.6 + 0.4 * sin(tick * (12.0 + 16.0 * chaos));
        eye_rgb          += vec3(1.0, 0.85, 0.3) * eye_inner * eye_flicker;
        orb_rgb           = mix(orb_rgb, eye_rgb, eye_alpha);

        // Rim glow
        float rim         = smoothstep(orb_r, orb_r - orb_r * 0.18, dist_p) - smoothstep(orb_r - orb_r * 0.18, orb_r - orb_r * 0.32, dist_p);
        rim               = clamp(rim, 0.0, 1.0);
        vec3 rim_col      = (boss_phase > 1.5) ? vec3(1.0, 0.35, 0.45) : vec3(0.55, 0.85, 1.0);
        orb_rgb          += rim_col * rim * (0.6 + 0.6 * chaos);

        // Aura — bigger and pulsier in phase 2 as HP drops.
        float aura_outer = orb_r * ((boss_phase > 1.5) ? (1.7 + 0.6 * chaos) : 1.35);
        float aura       = smoothstep(aura_outer, orb_r, dist_p) * 0.55;
        float aura_rate  = 5.0 + 12.0 * chaos;
        float aura_pulse = (boss_phase > 1.5) ? (0.55 + 0.45 * sin(tick * aura_rate)) : 1.0;
        vec3 aura_col    = (boss_phase > 1.5) ? vec3(1.0, 0.4, 0.45) : vec3(0.55, 0.85, 1.0);
        vec3 aura_rgb    = aura_col * aura * aura_pulse;

        // Phase-2 sparks: short bright lines around the orb that flicker with chaos.
        float spark_rgb_mix = 0.0;
        if (boss_phase > 1.5 && chaos > 0.05 && dist_p > orb_r && dist_p < orb_r * 2.2) {
            float spark_angle  = atan(p.y, p.x);
            float n_sparks     = 6.0 + 6.0 * chaos;
            float spark_phase  = sin(spark_angle * n_sparks + tick * 6.0);
            float spark_radial = smoothstep(orb_r * 1.3, orb_r * 1.0, dist_p) * smoothstep(orb_r * 1.3, orb_r * 2.2, dist_p);
            float spark_lit    = smoothstep(0.7, 0.99, spark_phase) * spark_radial * chaos;
            spark_rgb_mix      = spark_lit;
        }
        vec3 spark_rgb = vec3(1.0, 0.7, 0.4) * spark_rgb_mix * 1.4;

        // Composite: aura+sparks behind, beam in middle, orb on top.
        vec3 total_rgb    = aura_rgb + spark_rgb + laser_rgb;
        float total_alpha = max(max(aura * 0.5, spark_rgb_mix * 0.7), laser_alpha);
        total_rgb         = mix(total_rgb, orb_rgb, orb_alpha);
        total_alpha       = max(total_alpha, orb_alpha);

        total_alpha      *= dying_alpha;
        frag_color = vec4(clamp(total_rgb, 0.0, 1.9), clamp(total_alpha, 0.0, 1.0));
        if (frag_color.a < 0.01) { discard; }
        return;
    }
    // --- SLOWBOY (type 1) — state-machine star ---
    else if (v_enemy_type_fs > 0.5 && v_enemy_type_fs < 1.5) {
        // effect_params (alive): x=0, y=ai_state(0..3), z=progress(0..1), w=ENEMY_SLOWBOY_GLOW_CANVAS_SF
        // effect_params (dying): x=1, y=death_off, z=part_scale, w=dying_alpha
        float is_dying    = enemy_effect_params_fs.x;
        int   state       = int(enemy_effect_params_fs.y + 0.5);
        float progress    = clamp(enemy_effect_params_fs.z, 0.0, 1.0);
        float dying_alpha = (is_dying > 0.5) ? enemy_effect_params_fs.w : 1.0;

        vec2 p = uv_centered * enemy_visual_scale_on_quad;
        // Charge-state motion blur — stretch the body along motion direction.
        if (is_dying < 0.5 && state == 2) {
            // Use rotation as motion direction (slowboy.rotation tracks aim during charge spin).
            float ang = v_enemy_main_rotation_fs;
            vec2 motion = vec2(cos(ang), sin(ang));
            // Project p, compress perpendicular to motion (squashes orthogonal axis = "stretch" along motion)
            float along = dot(p, motion);
            vec2  perp  = vec2(-motion.y, motion.x);
            float across = dot(p, perp);
            // Compress across to fake a motion-blur stretch
            p = motion * along + perp * across * 0.45;
        }

        float star_dist = sdf_star(p, 5, 0.4, 0.45);
        float star_aa   = 0.025;
        float star_core = smoothstep(star_aa, 0.0, star_dist);
        float glow_alpha = smoothstep(star_aa + 0.18, star_aa, star_dist) * 0.85;

        vec3 col_yellow = vec3(1.0, 1.0, 0.0);
        vec3 col_red    = vec3(1.0, 0.0, 0.0);
        vec3 anim       = mix(col_yellow, col_red, 0.5 + 0.5 * sin(tick * 0.8));
        vec3 body_color = anim;

        // State-specific tinting + extras.
        if (is_dying < 0.5) {
            if (state == 1) {
                // WINDUP: shifts toward white; lightning flickers between star points.
                body_color = mix(anim, vec3(1.0), progress);
            } else if (state == 2) {
                // CHARGE: pure white-hot core
                body_color = vec3(1.0, 0.95, 0.85);
            } else if (state == 3) {
                // RECOVER: dim
                body_color *= mix(0.45, 0.85, progress);
            }
        }

        vec3 rgb = body_color * (star_core + glow_alpha);
        float alpha = clamp(star_core + glow_alpha, 0.0, 1.0) * enemy_color_out_fs.a;
        if (is_dying > 0.5) { alpha *= dying_alpha; }
        frag_color = vec4(rgb, alpha);
        if (frag_color.a < 0.01) { discard; }
        return;
    }

    // --- SPLITTER (type 3) — orange asteroid hex ---
    else if (v_enemy_type_fs > 2.5 && v_enemy_type_fs < 3.5) {
        float is_dying    = enemy_effect_params_fs.x;
        float dying_alpha = (is_dying > 0.5) ? enemy_effect_params_fs.w : 1.0;

        vec2 p = uv_centered * enemy_visual_scale_on_quad;
        float r = length(p);
        // Hexagonal-ish silhouette: clamp polar radius via a 6-arm modulator
        float ang = atan(p.y, p.x);
        float hex_modulator = 0.92 + 0.08 * cos(6.0 * ang);   // 0.84..1.0
        float silhouette_r = 0.42 * hex_modulator;
        float aa = 0.02;
        float body_alpha = smoothstep(aa, -aa, r - silhouette_r);

        // Cracks: dark stripes via low-frequency sin lattice rotated by the rocky tumble.
        float crack_a = sin(p.x * 18.0 + p.y * 7.0);
        float crack_b = sin(p.x * 5.0 - p.y * 14.0 + 1.7);
        float cracks = smoothstep(0.7, 0.95, max(crack_a, crack_b)) * 0.6;
        // Highlights — spherical shading from upper-left
        float lit = clamp(0.5 + 0.5 * dot(normalize(p + vec2(0.001)), vec2(-0.7, 0.6)), 0.0, 1.0);

        vec3 base   = enemy_color_out_fs.rgb * (0.55 + 0.6 * lit);
        vec3 shadow = base * 0.35;
        vec3 col    = mix(base, shadow, cracks);
        // Subtle inner dark core for depth
        col *= mix(1.0, 0.8, smoothstep(silhouette_r * 0.0, silhouette_r * 0.7, r));

        float alpha = body_alpha * enemy_color_out_fs.a;
        if (is_dying > 0.5) { alpha *= dying_alpha; }
        frag_color = vec4(col, alpha);
        if (frag_color.a < 0.01) { discard; }
        return;
    }

    // --- SNIPER (type 4) — sentinel + telegraph beam ---
    else if (v_enemy_type_fs > 3.5 && v_enemy_type_fs < 4.5) {
        // effect_params (alive): x=0, y=ai_state(0=IDLE,1=AIM,2=FIRE,3=COOL), z=progress, w=1
        // effect_params (dying): x=1, y=death_off, z=part_scale, w=dying_alpha
        float is_dying    = enemy_effect_params_fs.x;
        int   state       = int(enemy_effect_params_fs.y + 0.5);
        float progress    = clamp(enemy_effect_params_fs.z, 0.0, 1.0);
        float dying_alpha = (is_dying > 0.5) ? enemy_effect_params_fs.w : 1.0;

        vec2 p = uv_centered * enemy_visual_scale_on_quad;
        // World-to-p_scaled conversion (sniper has its own quad size).
        float w2u = (enemy_visual_scale_fs_out > 0.001) ? (enemy_visual_scale_on_quad / enemy_visual_scale_fs_out) : 1.0;

        const float SNIPER_BODY_R_W   = 0.10;
        const float SNIPER_BEAM_LEN_W = 9.2;   // matches ENEMY_SNIPER_BEAM_LENGTH world units (~ARENA_RADIUS * 3.6)
        const float SNIPER_BEAM_HALF_W = 0.05;

        float body_r  = SNIPER_BODY_R_W * w2u;
        float beam_len = SNIPER_BEAM_LEN_W * w2u;
        float beam_hw = SNIPER_BEAM_HALF_W * w2u;

        vec2 aim  = vec2(cos(v_enemy_main_rotation_fs), sin(v_enemy_main_rotation_fs));
        vec2 perp = vec2(-aim.y, aim.x);

        // Body — angular triangular sentinel pointing along aim, with a glowing eye core.
        // Scalene triangle: tip in aim direction, base behind.
        float along  = dot(p, aim);
        float across = dot(p, perp);
        // Body extents: along [-body_r, body_r * 1.4], across [-body_r * 0.85, body_r * 0.85] tapering to 0 at tip.
        float t = (along + body_r) / (body_r * 2.4); // 0 at base, 1 at tip
        float body_alpha = 0.0;
        if (t >= 0.0 && t <= 1.0) {
            float taper = mix(1.0, 0.05, t);
            float side  = abs(across) - body_r * 0.85 * taper;
            body_alpha = smoothstep(0.005 * w2u, -0.005 * w2u, side);
        }

        // Eye/scope — circular glowing dot near the rear of the body
        vec2 eye_centre = -aim * (body_r * 0.30);
        float eye_d = length(p - eye_centre);
        float eye_r = body_r * 0.32;
        float eye_alpha = smoothstep(eye_r + 0.005 * w2u, eye_r - 0.005 * w2u, eye_d);
        float eye_inner = smoothstep(eye_r * 0.55, 0.0, eye_d);

        // Eye colour reacts to state: dim red idle, bright pulsing red while aiming, white-hot on fire.
        vec3 eye_col = vec3(0.6, 0.0, 0.0);
        if (is_dying < 0.5) {
            if (state == 0) {
                eye_col = vec3(0.3, 0.0, 0.0);
            } else if (state == 1) {
                float pulse = 0.6 + 0.4 * sin(tick * (12.0 + 20.0 * progress));
                eye_col = mix(vec3(0.4, 0.05, 0.05), vec3(1.0, 0.45, 0.45), progress) * pulse;
            } else if (state == 2) {
                eye_col = mix(vec3(1.0, 1.0, 0.85), vec3(1.0, 0.4, 0.4), progress);
            } else {
                eye_col = vec3(0.25, 0.05, 0.05);
            }
        }

        vec3 body_col = mix(enemy_color_out_fs.rgb * 0.7, enemy_color_out_fs.rgb * 1.3, smoothstep(-1.0, 1.0, dot(normalize(p + vec2(0.001)), vec2(-0.7, 0.6))));
        body_col = mix(body_col, eye_col + vec3(0.4) * eye_inner, eye_alpha);

        // Telegraph beam — only visible during AIMING/FIRING.
        float beam_alpha = 0.0;
        vec3  beam_rgb = vec3(0.0);
        if (is_dying < 0.5 && state >= 1 && state <= 2) {
            // Capsule SDF starting at the body tip, extending along aim.
            vec2 origin = aim * (body_r * 1.2);
            vec2 rel = p - origin;
            float along_b = dot(rel, aim);
            float across_b = dot(rel, perp);
            float capsule_sdf;
            if (along_b < 0.0) capsule_sdf = length(rel) - beam_hw;
            else if (along_b > beam_len) capsule_sdf = length(rel - aim * beam_len) - beam_hw;
            else capsule_sdf = abs(across_b) - beam_hw;

            float aa = beam_hw * 0.5;
            float core = smoothstep(aa, -aa, capsule_sdf);
            float halo = smoothstep(beam_hw * 4.0, 0.0, max(0.0, capsule_sdf));

            if (state == 1) {
                // AIMING: thin sweet line, gets brighter as lock-on completes.
                float intensity = mix(0.15, 0.85, progress);
                // After lock-on, no more tracking — flicker
                if (progress > 0.78) {
                    intensity *= 0.85 + 0.15 * sin(tick * 30.0);
                }
                beam_rgb   = vec3(1.0, 0.25, 0.25) * intensity;
                beam_alpha = (core * 0.85 + halo * 0.4) * intensity;
            } else {
                // FIRING: blistering flash that dims through the firing window.
                float k = 1.6 * (1.0 - progress);
                beam_rgb   = (vec3(1.0, 0.95, 0.85) * core + vec3(1.0, 0.4, 0.4) * halo) * k;
                beam_alpha = clamp(core + halo * 0.6, 0.0, 1.0) * k;
            }
        }

        // Composite
        vec3 total = body_col * body_alpha + beam_rgb;
        float total_alpha = max(body_alpha, beam_alpha) * enemy_color_out_fs.a;
        if (is_dying > 0.5) { total_alpha *= dying_alpha; }
        frag_color = vec4(clamp(total, 0.0, 1.6), clamp(total_alpha, 0.0, 1.0));
        if (frag_color.a < 0.01) { discard; }
        return;
    }

    // --- DISRUPTOR (type 5) — fast cyan triangle pointed at the button ---
    else if (v_enemy_type_fs > 4.5 && v_enemy_type_fs < 5.5) {
        float is_dying    = enemy_effect_params_fs.x;
        float dying_alpha = (is_dying > 0.5) ? enemy_effect_params_fs.w : 1.0;

        vec2 p = uv_centered * enemy_visual_scale_on_quad;
        // Triangle pointing in the +x direction in p_scaled space (rotation handled by quad rot in VS).
        // Tip at (0.6, 0), base at x=-0.4.
        float along  = p.x;
        float across = p.y;
        float t = (along + 0.4) / 1.0; // 0 at base, 1 at tip
        float body_alpha = 0.0;
        if (t >= 0.0 && t <= 1.0) {
            float taper = mix(1.0, 0.05, t);
            float side  = abs(across) - 0.30 * taper;
            body_alpha = smoothstep(0.012, -0.012, side);
        }

        // Hostile inner glow (pulses)
        float pulse = 0.65 + 0.35 * sin(tick * 8.0);
        vec3 base = enemy_color_out_fs.rgb;
        vec3 col  = mix(base * 0.5, base * 1.4, smoothstep(-0.4, 0.6, p.x));
        col += vec3(0.5, 1.0, 1.0) * pulse * body_alpha * 0.4;

        // Trailing tether-streak behind the base (dark cyan strands)
        float trail = 0.0;
        if (p.x < -0.4 && p.x > -1.0) {
            float trail_t = (-0.4 - p.x) / 0.6;
            float trail_w = 0.18 * (1.0 - trail_t);
            trail = smoothstep(trail_w + 0.03, 0.0, abs(across)) * (1.0 - trail_t) * 0.4;
            trail *= 0.5 + 0.5 * sin(tick * 18.0 + p.x * 28.0);
        }

        vec3 total = col * body_alpha + base * trail;
        float total_alpha = max(body_alpha, trail) * enemy_color_out_fs.a;
        if (is_dying > 0.5) { total_alpha *= dying_alpha; }
        frag_color = vec4(total, total_alpha);
        if (frag_color.a < 0.01) { discard; }
        return;
    }

    // --- GRUNT (type 0) — spinning triangular shard ---
    // effect_params (alive): x=0, y=speed_norm[0..1], z=1, w=1
    // effect_params (dying): x=1, y=death_off,        z=part_scale, w=dying_alpha
    else {
        float is_dying    = enemy_effect_params_fs.x;
        float part_scale  = enemy_effect_params_fs.z;
        float dying_alpha = (is_dying > 0.5) ? enemy_effect_params_fs.w : 1.0;
        float speed_norm  = (is_dying > 0.5) ? 0.0 : enemy_effect_params_fs.y;
        float pulse       = 0.5 + 0.5 * sin(tick * 9.0);                // 0..1 oscillator
        float pulse_mod   = mix(1.0, 1.0 + 0.10 * pulse, speed_norm);   // body squash with speed

        // p is already rotated by the quad rotation (vs_enemy applies it to non-boss/non-sniper).
        vec2 p = uv_centered * enemy_visual_scale_on_quad;
        // Equilateral triangle SDF, pointing +y.
        // Use folded coords: take abs(x), rotate to lift onto a "side".
        float k = sqrt(3.0);
        float scale = 0.5 * (is_dying > 0.5 ? part_scale : pulse_mod);
        vec2 q = p / max(scale, 0.0001);
        q.x = abs(q.x) - 1.0;
        q.y = q.y + 1.0 / k;
        if (q.x + k * q.y > 0.0) { q = vec2(q.x - k * q.y, -k * q.x - q.y) / 2.0; }
        q.x -= clamp(q.x, -2.0, 0.0);
        float tri_sdf = -length(q) * sign(q.y) * scale;

        float aa = 0.025;
        float body = smoothstep(aa, -aa, tri_sdf);
        // Halo thickens with speed so chasing grunts drag a hot wake.
        float halo_thickness = 0.12 + 0.08 * speed_norm;
        float halo = smoothstep(aa + halo_thickness, aa, tri_sdf) * (0.55 + 0.30 * speed_norm * pulse);

        // Hot core toward center, darker rim near edges. Speed brightens the core.
        float r = length(p);
        vec3 hot  = enemy_color_out_fs.rgb * (1.7 + 0.6 * speed_norm) + vec3(0.25, 0.0, 0.25);
        vec3 rim  = enemy_color_out_fs.rgb * 0.7;
        vec3 col  = mix(hot, rim, smoothstep(0.0, 0.5, r));

        // Inner spin ring; brightness pulses with motion.
        float ring = smoothstep(0.18, 0.16, r) - smoothstep(0.16, 0.13, r);
        col += vec3(1.0, 0.6, 0.95) * ring * (0.6 + 0.8 * speed_norm * pulse);

        vec3 total = col * body + col * halo;
        float total_alpha = clamp(body + halo * 0.65, 0.0, 1.0) * enemy_color_out_fs.a;
        if (is_dying > 0.5) { total_alpha *= dying_alpha; }
        frag_color = vec4(total, total_alpha);
        if (frag_color.a < 0.01) { discard; }
    }
}
@end
@program enemy vs_enemy fs_enemy