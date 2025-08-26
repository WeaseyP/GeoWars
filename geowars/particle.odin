package main
import "base:runtime"
import ma "../miniaudio"
import "core:fmt"
import rand "core:math/rand"
import m "../math"
import sapp "../sokol/app"
import "core:math"



// --- Particle System ---
emit_particle :: proc(part: Particle) {
    context = runtime.default_context()
    p_to_init_sound := &state.particles[state.next_particle_index]
    p_to_init_sound^ = part 
    p_to_init_sound.has_active_sound = false 

    if p_to_init_sound.is_ammo_indicator || p_to_init_sound.is_swirling_charge {
        p_to_init_sound.has_active_sound = true
        sound_flags_particle: ma.sound_flags = { .NO_PITCH, .NO_SPATIALIZATION } // Renamed
        hum_init_res := ma.sound_init_from_data_source(&state.audio_engine, (^ma.data_source)(&rmb_hum_audio_buffer), sound_flags_particle, nil, &p_to_init_sound.sound_hum)
        if hum_init_res == .SUCCESS {
            ma.sound_set_looping(&p_to_init_sound.sound_hum, true)
            ma.sound_set_volume(&p_to_init_sound.sound_hum, RMB_HUM_AMPLITUDE) 
            ma.sound_start(&p_to_init_sound.sound_hum)
        } else {
            fmt.eprintf("!!! ERROR: Failed to init hum sound for particle. Code: %v\n", hum_init_res)
            p_to_init_sound.has_active_sound = false 
        }

        if p_to_init_sound.has_active_sound { 
            whoosh_init_res := ma.sound_init_from_data_source(&state.audio_engine, (^ma.data_source)(&rmb_whoosh_audio_buffer), sound_flags_particle, nil, &p_to_init_sound.sound_whoosh)
            if whoosh_init_res == .SUCCESS {
                ma.sound_set_looping(&p_to_init_sound.sound_whoosh, true)
                ma.sound_set_volume(&p_to_init_sound.sound_whoosh, 0.0) 
                ma.sound_start(&p_to_init_sound.sound_whoosh)
            } else {
                fmt.eprintf("!!! ERROR: Failed to init whoosh sound for particle. Code: %v\n", whoosh_init_res)
                ma.sound_uninit(&p_to_init_sound.sound_hum) 
                p_to_init_sound.has_active_sound = false 
            }
        }
    }
    p_to_init_sound.active = true 
    state.next_particle_index = (state.next_particle_index + 1) % MAX_PARTICLES
}

spawn_swirling_charge :: proc() { 
    context = runtime.default_context()
    if state.player_hp <= 0 { return; } 
    charge_spawn_center := state.player_pos 
    charge_duration := SWIRL_CHARGE_DURATION_BASE + rand.float32() * SWIRL_CHARGE_DURATION_RAND 
    start_size_val_base := SWIRL_PARTICLE_SIZE_BASE
    start_size_val_rand := SWIRL_PARTICLE_SIZE_RAND
    start_color := m.vec4{0.8, 0.3, 1.0, 1.0}
    cloud_travel_vel: m.vec2 = {0, 0} 
    player_speed_sq := m.len_sq_vec2(state.player_vel)
    player_front_dir := m.vec2{0,1} 
    if m.len_sq_vec2(state.player_vel) > 0.001 { player_front_dir = m.norm_vec2(state.player_vel) }
    cloud_travel_vel = player_front_dir * SWIRL_CLOUD_BASE_PUSH;
    if player_speed_sq > 0.001 && SWIRL_CLOUD_TRAVEL_FACTOR > 0.0 { cloud_travel_vel += state.player_vel * SWIRL_CLOUD_TRAVEL_FACTOR; }
    for _ in 0..<DEATH_BURST_PARTICLE_COUNT {
        start_size_val := start_size_val_base + rand.float32() * start_size_val_rand
        spawn_angle := rand.float32() * f32(m.TAU)
        spawn_dist := rand.float32() * SWIRL_RADIUS_SPAWN
        relative_pos := m.angle_to_vec2(spawn_angle) * spawn_dist
        start_pos := charge_spawn_center + relative_pos 
        tangent_dir := m.vec2{-relative_pos.y, relative_pos.x}
        if m.len_sq_vec2(tangent_dir) > 0.001 { tangent_dir = m.norm_vec2(tangent_dir) }
        orbital_vel := tangent_dir * SWIRL_SPEED_ORBITAL_BASE * (0.8 + rand.float32() * 0.4)
        inward_vel_dir: m.vec2 = {0,0}
        if m.len_sq_vec2(relative_pos) > 0.001 { inward_vel_dir = m.norm_vec2(-relative_pos) }
        inward_vel := inward_vel_dir * SWIRL_SPEED_INWARD_INITIAL
        start_vel := cloud_travel_vel + orbital_vel + inward_vel
        start_angular_vel := (rand.float32() * 2.0 - 1.0) * MAX_SPIN_SPEED * 2.5
        emit_particle(Particle{
            pos=start_pos, vel=start_vel, cloud_travel_vel=cloud_travel_vel, color=start_color,
            size=start_size_val, start_size=start_size_val, life_remaining=charge_duration, life_max=charge_duration,
            swirl_duration=charge_duration, rotation=rand.float32()*f32(m.TAU), angular_vel=start_angular_vel,
            charge_center_pos=charge_spawn_center, is_burst_particle=false, is_swirling_charge=true, is_ammo_indicator=false, active=false, 
        })
    }
}

update_and_instance_particles :: proc(dt: f32) -> int {
    context = runtime.default_context()
    live_particle_count := 0
    
    for i in 0..<MAX_PARTICLES {
        if !state.particles[i].active { continue }
        p := &state.particles[i]

        if p.is_ammo_indicator {
            p.rotation += RMB_AMMO_INDICATOR_ORBIT_SPEED * dt; 
            if p.rotation > m.TAU { p.rotation -= m.TAU; }
            else if p.rotation < 0 { p.rotation += m.TAU; }
            orbit_direction := m.angle_to_vec2(p.rotation);
            p.pos = state.player_pos + orbit_direction * RMB_AMMO_INDICATOR_ORBIT_RADIUS;
            p.charge_center_pos.y += p.angular_vel * dt; // Using charge_center_pos.y for individual spin angle of ammo indicators
            if p.charge_center_pos.y > m.TAU {p.charge_center_pos.y -= m.TAU;}
            if p.charge_center_pos.y < 0 {p.charge_center_pos.y += m.TAU;}
            p.color = RMB_AMMO_INDICATOR_COLOR;
            p.size = RMB_AMMO_INDICATOR_BASE_SIZE;
        } else {
            p.pos += p.vel * dt;
            screen_aspect_ratio_part: f32 = sapp.widthf() / sapp.heightf() // Renamed
            world_half_width_part: f32 = ORTHO_HEIGHT * screen_aspect_ratio_part // Renamed
            world_half_height_part: f32 = ORTHO_HEIGHT // Renamed
            off_screen_margin_part: f32 = 0.1 // Renamed

            is_off_screen := false
            if p.pos.x < -world_half_width_part - off_screen_margin_part ||
               p.pos.x >  world_half_width_part + off_screen_margin_part ||
               p.pos.y < -world_half_height_part - off_screen_margin_part ||
               p.pos.y >  world_half_height_part + off_screen_margin_part {
                is_off_screen = true
            }

            if is_off_screen {
                if p.has_active_sound {
                    ma.sound_uninit(&p.sound_hum)
                    ma.sound_uninit(&p.sound_whoosh)
                    p.has_active_sound = false
                }
                p.active = false
                continue 
            }

            if p.has_active_sound {
                current_speed_part := m.len_vec2(p.vel) // Renamed
                speed_factor_part: f32 // Renamed
                if MAX_PARTICLE_SPEED_FOR_SOUND_EFFECT > 0.001 { 
                    speed_factor_part = math.clamp(current_speed_part / MAX_PARTICLE_SPEED_FOR_SOUND_EFFECT, 0.0, 1.0)
                } else { speed_factor_part = 0.0 }
                hum_target_volume_part := (1.0 - speed_factor_part) * RMB_HUM_AMPLITUDE // Renamed
                whoosh_target_volume_part := speed_factor_part * RMB_WHOOSH_AMPLITUDE // Renamed
                ma.sound_set_volume(&p.sound_hum, hum_target_volume_part)
                ma.sound_set_volume(&p.sound_whoosh, whoosh_target_volume_part)
            }
            p.rotation += p.angular_vel * dt; 
            if p.rotation > m.TAU { p.rotation -= m.TAU; } else if p.rotation < 0 { p.rotation += m.TAU; }
            p.life_remaining -= dt;

            if p.is_swirling_charge && p.life_remaining <= 0.0 {
                p.is_swirling_charge = false;
                new_life_part := EXPLOSION_LIFETIME_BASE + rand.float32() * EXPLOSION_LIFETIME_RAND; // Renamed
                p.life_remaining = new_life_part;
                p.life_max = new_life_part;   
                explosion_center_part := p.charge_center_pos + p.cloud_travel_vel * p.swirl_duration; // Renamed
                relative_pos_part := p.pos - explosion_center_part; // Renamed
                outward_dir_part : m.vec2 = {rand.float32() * 2.0 - 1.0, rand.float32() * 2.0 - 1.0}; // Renamed
                len_sq_part := m.len_sq_vec2(relative_pos_part); // Renamed
                if len_sq_part > 0.0001 { outward_dir_part = m.norm_vec2(relative_pos_part);
                } else if m.len_sq_vec2(outward_dir_part) > 0.0001 { outward_dir_part = m.norm_vec2(outward_dir_part);
                } else { outward_dir_part = {0.0, 1.0}; }
                explosion_speed_part := EXPLOSION_SPEED_BASE + rand.float32() * EXPLOSION_SPEED_RAND; // Renamed
                p.vel = outward_dir_part * explosion_speed_part;
                p.angular_vel = EXPLOSION_PARTICLE_SPIN;
            }

            if !p.is_swirling_charge && p.life_remaining <= 0.0 { 
                if p.has_active_sound {
                    ma.sound_uninit(&p.sound_hum)
                    ma.sound_uninit(&p.sound_whoosh)
                    p.has_active_sound = false
                }
                p.active = false; 
                continue; 
            }

            life_ratio_part: f32 = 0.0; // Renamed
            if p.life_max > 0.0 { life_ratio_part = math.max(f32(0.0), p.life_remaining / p.life_max); }
            
            if p.is_swirling_charge { 
                p.size = p.start_size; 
                p.color.a = 1.0;    
            } else { 
                p.size = p.start_size * life_ratio_part * life_ratio_part; 
                p.color.a = life_ratio_part * life_ratio_part; 
            }
        }
        
        if live_particle_count < MAX_PARTICLES {
            inst := &state.particle_instance_data[live_particle_count];
            inst.instance_pos=p.pos; 
            inst.instance_size=p.size; 
            if p.is_ammo_indicator { inst.instance_rotation = p.charge_center_pos.y;  } // Use .y for self-spin
            else { inst.instance_rotation = p.rotation; }
            inst.instance_color=p.color;
            live_particle_count += 1;
        }
    }
    return live_particle_count
}

spawn_LMB_enemy_death_particles :: proc(pos: m.vec2, base_color: m.vec4) {
    context = runtime.default_context()
    for _ in 0..<LMB_ENEMY_DEATH_PARTICLE_COUNT {
        angle_lmb_d := rand.float32() * m.TAU // Renamed
        dir_lmb_d := m.angle_to_vec2(angle_lmb_d) // Renamed
        speed_lmb_d := LMB_ENEMY_DEATH_PARTICLE_SPEED_BASE + rand.float32() * LMB_ENEMY_DEATH_PARTICLE_SPEED_RAND // Renamed
        life_lmb_d := LMB_ENEMY_DEATH_PARTICLE_LIFETIME_BASE + rand.float32() * LMB_ENEMY_DEATH_PARTICLE_LIFETIME_RAND // Renamed
        size_lmb_d := LMB_ENEMY_DEATH_PARTICLE_SIZE_BASE + rand.float32() * LMB_ENEMY_DEATH_PARTICLE_SIZE_RAND // Renamed
        angular_vel_lmb_d := rand.float32_range(-1.0, 1.0) * LMB_ENEMY_DEATH_PARTICLE_ANGULAR_VEL_MAX // Renamed
        particle_color_lmb_d := base_color; // Renamed
        particle_color_lmb_d.r = math.min(base_color.r * 1.2 + 0.2, 1.0);
        particle_color_lmb_d.g = math.min(base_color.g * 1.2 + 0.2, 1.0);
        particle_color_lmb_d.b = math.min(base_color.b * 1.2 + 0.2, 1.0);
        particle_color_lmb_d.a = 0.85; 
        emit_particle(Particle{
            pos=pos, vel=dir_lmb_d*speed_lmb_d, cloud_travel_vel={0,0}, color=particle_color_lmb_d, size=size_lmb_d, start_size=size_lmb_d,
            life_remaining=life_lmb_d, life_max=life_lmb_d, swirl_duration=0, rotation=rand.float32()*m.TAU, angular_vel=angular_vel_lmb_d,
            charge_center_pos={0,0}, is_burst_particle=true, is_swirling_charge=false, is_ammo_indicator=false, active=false, 
        })
    }
}

spawn_visual_ammo_charge_particles :: proc(charge_slot_index: int) {
    context = runtime.default_context()
    if charge_slot_index < 0 || charge_slot_index >= MAX_RMB_AMMO_CHARGES { return; }
    base_orbit_angle_offset_va := (f32(charge_slot_index) / f32(MAX_RMB_AMMO_CHARGES)) * m.TAU; // Renamed
    for i in 0..<RMB_AMMO_INDICATOR_PARTICLES_PER_CHARGE {
        particle_angle_within_group_va := (f32(i) / f32(RMB_AMMO_INDICATOR_PARTICLES_PER_CHARGE)) * m.TAU; // Renamed
        current_orbit_angle_va := base_orbit_angle_offset_va + particle_angle_within_group_va + (state.rmb_ammo_regen_timer * RMB_AMMO_INDICATOR_ORBIT_SPEED); // Renamed
        emit_particle(Particle{
            pos = state.player_pos, vel = {0,0}, cloud_travel_vel = {0,0}, color = RMB_AMMO_INDICATOR_COLOR,
            size = RMB_AMMO_INDICATOR_BASE_SIZE, start_size = RMB_AMMO_INDICATOR_BASE_SIZE,
            life_remaining = 1.0, life_max = 1.0, swirl_duration = 0,
            rotation = current_orbit_angle_va,  // This is the orbit angle around player
            angular_vel = RMB_AMMO_INDICATOR_SELF_SPIN_SPEED, // For charge_center_pos.y update rate
            charge_center_pos= m.vec2{f32(charge_slot_index), rand.float32()*m.TAU}, // Store charge index in .x, initial random spin angle in .y
            is_burst_particle= false, is_swirling_charge= false, is_ammo_indicator= true, active = false,
        });
    }
     fmt.printf("Spawned visual ammo for charge slot %d\n", charge_slot_index);
}

remove_visual_ammo_charge_particles :: proc(charge_slot_index_to_remove: int) {
    context = runtime.default_context()
    particles_removed_count := 0
    for i in 0..<MAX_PARTICLES {
        p_va_rem := &state.particles[i]; // Renamed
        if p_va_rem.active && p_va_rem.is_ammo_indicator && int(p_va_rem.charge_center_pos.x) == charge_slot_index_to_remove {
            if p_va_rem.has_active_sound {
                ma.sound_uninit(&p_va_rem.sound_hum)
                ma.sound_uninit(&p_va_rem.sound_whoosh)
                p_va_rem.has_active_sound = false
            }
            p_va_rem.active = false; 
            particles_removed_count += 1;
        }
    }
    if particles_removed_count > 0 {
        fmt.printf("Removed %d visual ammo particles for charge slot %d\n", particles_removed_count, charge_slot_index_to_remove);
    }
}

spawn_RMB_enemy_death_particles :: proc(pos: m.vec2) {
    context = runtime.default_context()
    base_death_color_rmb := RMB_PARTICLE_COLOR;
    for _ in 0..<RMB_ENEMY_DEATH_PARTICLE_COUNT {
        angle_rmb_d := rand.float32() * m.TAU
        dir_rmb_d := m.angle_to_vec2(angle_rmb_d)
        speed_rmb_d := RMB_ENEMY_DEATH_PARTICLE_SPEED_BASE + rand.float32() * RMB_ENEMY_DEATH_PARTICLE_SPEED_RAND
        life_rmb_d := RMB_ENEMY_DEATH_PARTICLE_LIFETIME_BASE + rand.float32() * RMB_ENEMY_DEATH_PARTICLE_LIFETIME_RAND
        size_rmb_d := RMB_ENEMY_DEATH_PARTICLE_SIZE_BASE + rand.float32() * RMB_ENEMY_DEATH_PARTICLE_SIZE_RAND
        angular_vel_rmb_d := rand.float32_range(-1.0, 1.0) * RMB_ENEMY_DEATH_PARTICLE_ANGULAR_VEL_MAX
        particle_color_rmb_d := base_death_color_rmb;
        particle_color_rmb_d.r = math.clamp(base_death_color_rmb.r + rand.float32_range(-0.1, 0.1), 0.5, 1.0);
        particle_color_rmb_d.g = math.clamp(base_death_color_rmb.g + rand.float32_range(-0.1, 0.1), 0.2, 0.8);
        particle_color_rmb_d.b = math.clamp(base_death_color_rmb.b + rand.float32_range(-0.1, 0.1), 0.7, 1.0);
        particle_color_rmb_d.a = rand.float32_range(0.6, 0.9);
        emit_particle(Particle{
            pos=pos, vel=dir_rmb_d*speed_rmb_d, cloud_travel_vel={0,0}, color=particle_color_rmb_d, size=size_rmb_d, start_size=size_rmb_d,
            life_remaining=life_rmb_d, life_max=life_rmb_d, // Corrected line
            swirl_duration=0, rotation=rand.float32()*m.TAU, angular_vel=angular_vel_rmb_d,
            charge_center_pos={0,0}, is_burst_particle=true, is_swirling_charge=false, is_ammo_indicator=false, active=false, 
        })
    }
}