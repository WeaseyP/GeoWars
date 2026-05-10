package particle
import "base:runtime"
import ma "../../vendor/miniaudio"
import "core:fmt"
import rand "core:math/rand"
import m "../../vendor/math"
import sapp "../../vendor/sokol/app"
import "core:math"
import shared "../../shared"
import audio "../../audio"


// --- Particle System ---
emit_particle :: proc(part: shared.Particle) {
    context = runtime.default_context()
    p_to_init_sound := &shared.state.particles[shared.state.next_particle_index]
    p_to_init_sound^ = part
    p_to_init_sound.has_active_sound = false

    if p_to_init_sound.is_swirling_charge {
        p_to_init_sound.has_active_sound = true
        sound_flags_particle: ma.sound_flags = { .NO_PITCH, .NO_SPATIALIZATION }
        hum_init_res := ma.sound_init_from_data_source(&shared.state.audio_engine, (^ma.data_source)(&audio.rmb_hum_audio_buffer), sound_flags_particle, nil, &p_to_init_sound.sound_hum)
        if hum_init_res == .SUCCESS {
            ma.sound_set_looping(&p_to_init_sound.sound_hum, true)
            ma.sound_set_volume(&p_to_init_sound.sound_hum, audio.RMB_HUM_AMPLITUDE)
            ma.sound_start(&p_to_init_sound.sound_hum)
        } else {
            fmt.eprintf("!!! ERROR: Failed to init hum sound for particle. Code: %v\n", hum_init_res)
            p_to_init_sound.has_active_sound = false
        }

        if p_to_init_sound.has_active_sound {
            whoosh_init_res := ma.sound_init_from_data_source(&shared.state.audio_engine, (^ma.data_source)(&audio.rmb_whoosh_audio_buffer), sound_flags_particle, nil, &p_to_init_sound.sound_whoosh)
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
    shared.state.next_particle_index = (shared.state.next_particle_index + 1) % shared.MAX_PARTICLES
}

// Spawn the RMB swirl with a particle count scaled to the player's current charge fraction.
// charge_fraction == 1.0 emits the full DEATH_BURST_PARTICLE_COUNT; 0.5 emits half; 2.0 doubles
// it (overcharge). Caller is responsible for clamping to a sane range.
spawn_swirling_charge_scaled :: proc(charge_fraction: f32) {
    context = runtime.default_context()
    if shared.state.player_hp <= 0 { return }
    if charge_fraction <= 0.001 { return }
    count := int(math.round(f32(shared.DEATH_BURST_PARTICLE_COUNT) * charge_fraction))
    if count < 1 { count = 1 }

    charge_spawn_center := shared.state.player_pos
    charge_duration := shared.SWIRL_CHARGE_DURATION_BASE + rand.float32() * shared.SWIRL_CHARGE_DURATION_RAND
    start_size_val_base := shared.SWIRL_PARTICLE_SIZE_BASE
    start_size_val_rand := shared.SWIRL_PARTICLE_SIZE_RAND
    start_color := m.vec4{0.8, 0.3, 1.0, 1.0}
    cloud_travel_vel: m.vec2 = {0, 0}
    player_speed_sq := m.len_sq_vec2(shared.state.player_vel)
    player_front_dir := m.vec2{0,1}
    if m.len_sq_vec2(shared.state.player_vel) > 0.001 { player_front_dir = m.norm_vec2(shared.state.player_vel) }
    cloud_travel_vel = player_front_dir * shared.SWIRL_CLOUD_BASE_PUSH
    if player_speed_sq > 0.001 && shared.SWIRL_CLOUD_TRAVEL_FACTOR > 0.0 { cloud_travel_vel += shared.state.player_vel * shared.SWIRL_CLOUD_TRAVEL_FACTOR }
    for _ in 0..<count {
        start_size_val := start_size_val_base + rand.float32() * start_size_val_rand
        spawn_angle := rand.float32() * f32(m.TAU)
        spawn_dist := rand.float32() * shared.SWIRL_RADIUS_SPAWN
        relative_pos := m.angle_to_vec2(spawn_angle) * spawn_dist
        start_pos := charge_spawn_center + relative_pos
        tangent_dir := m.vec2{-relative_pos.y, relative_pos.x}
        if m.len_sq_vec2(tangent_dir) > 0.001 { tangent_dir = m.norm_vec2(tangent_dir) }
        orbital_vel := tangent_dir * shared.SWIRL_SPEED_ORBITAL_BASE * (0.8 + rand.float32() * 0.4)
        inward_vel_dir: m.vec2 = {0,0}
        if m.len_sq_vec2(relative_pos) > 0.001 { inward_vel_dir = m.norm_vec2(-relative_pos) }
        inward_vel := inward_vel_dir * shared.SWIRL_SPEED_INWARD_INITIAL
        start_vel := cloud_travel_vel + orbital_vel + inward_vel
        start_angular_vel := (rand.float32() * 2.0 - 1.0) * shared.MAX_SPIN_SPEED * 2.5
        emit_particle(shared.Particle{
            pos=start_pos, vel=start_vel, cloud_travel_vel=cloud_travel_vel, color=start_color,
            size=start_size_val, start_size=start_size_val, life_remaining=charge_duration, life_max=charge_duration,
            swirl_duration=charge_duration, rotation=rand.float32()*f32(m.TAU), angular_vel=start_angular_vel,
            charge_center_pos=charge_spawn_center, is_burst_particle=false, is_swirling_charge=true, active=false,
        })
    }
}

// Screen-wide pulse — spawned in addition to the swirl when RMB releases at >=100% charge.
// Particles fly outward in a perfect ring, pass through the standard RMB collision check, and
// fade. charge >1 stacks more particles and a slight radius boost.
spawn_rmb_pulse :: proc(charge: f32) {
    context = runtime.default_context()
    if shared.state.player_hp <= 0 { return }
    overcharge := math.max(charge - shared.RMB_BEAM_THRESHOLD, 0.0)
    count := shared.RMB_PULSE_PARTICLE_COUNT + int(math.round(overcharge * f32(shared.RMB_PULSE_PARTICLE_COUNT) * 0.5))
    speed := shared.RMB_PULSE_PARTICLE_SPEED * (1.0 + overcharge * 0.25)
    life  := shared.RMB_PULSE_PARTICLE_LIFETIME
    size  := shared.RMB_PULSE_PARTICLE_SIZE * (1.0 + overcharge * 0.20)
    centre := shared.state.player_pos
    for i in 0..<count {
        angle := (f32(i) / f32(count)) * m.TAU
        dir := m.angle_to_vec2(angle)
        emit_particle(shared.Particle{
            pos=centre, vel=dir*speed, cloud_travel_vel={0,0}, color=shared.RMB_PULSE_PARTICLE_COLOR,
            size=size, start_size=size, life_remaining=life, life_max=life, swirl_duration=0,
            rotation=angle, angular_vel=0,
            charge_center_pos={0,0}, is_burst_particle=false, is_swirling_charge=false, active=false,
        })
    }
}

update_and_instance_particles :: proc(dt: f32) -> int {
    context = runtime.default_context()
    live_particle_count := 0

    for i in 0..<shared.MAX_PARTICLES {
        if !shared.state.particles[i].active { continue }
        p := &shared.state.particles[i]

        {
            p.pos += p.vel * dt
            screen_aspect_ratio_part: f32 = sapp.widthf() / sapp.heightf()
            world_half_width_part: f32 = shared.ORTHO_HEIGHT * screen_aspect_ratio_part
            world_half_height_part: f32 = shared.ORTHO_HEIGHT
            off_screen_margin_part: f32 = 0.1

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
                current_speed_part := m.len_vec2(p.vel)
                speed_factor_part: f32
                if audio.MAX_PARTICLE_SPEED_FOR_SOUND_EFFECT > 0.001 {
                    speed_factor_part = math.clamp(current_speed_part / audio.MAX_PARTICLE_SPEED_FOR_SOUND_EFFECT, 0.0, 1.0)
                } else { speed_factor_part = 0.0 }
                hum_target_volume_part := (1.0 - speed_factor_part) * audio.RMB_HUM_AMPLITUDE
                whoosh_target_volume_part := speed_factor_part * audio.RMB_WHOOSH_AMPLITUDE
                ma.sound_set_volume(&p.sound_hum, hum_target_volume_part)
                ma.sound_set_volume(&p.sound_whoosh, whoosh_target_volume_part)
            }
            p.rotation += p.angular_vel * dt
            if p.rotation > m.TAU { p.rotation -= m.TAU } else if p.rotation < 0 { p.rotation += m.TAU }
            p.life_remaining -= dt

            if p.is_swirling_charge && p.life_remaining <= 0.0 {
                p.is_swirling_charge = false
                new_life_part := shared.EXPLOSION_LIFETIME_BASE + rand.float32() * shared.EXPLOSION_LIFETIME_RAND
                p.life_remaining = new_life_part
                p.life_max = new_life_part
                explosion_center_part := p.charge_center_pos + p.cloud_travel_vel * p.swirl_duration
                relative_pos_part := p.pos - explosion_center_part
                outward_dir_part : m.vec2 = {rand.float32() * 2.0 - 1.0, rand.float32() * 2.0 - 1.0}
                len_sq_part := m.len_sq_vec2(relative_pos_part)
                if len_sq_part > 0.0001 { outward_dir_part = m.norm_vec2(relative_pos_part)
                } else if m.len_sq_vec2(outward_dir_part) > 0.0001 { outward_dir_part = m.norm_vec2(outward_dir_part)
                } else { outward_dir_part = {0.0, 1.0} }
                explosion_speed_part := shared.EXPLOSION_SPEED_BASE + rand.float32() * shared.EXPLOSION_SPEED_RAND
                p.vel = outward_dir_part * explosion_speed_part
                p.angular_vel = shared.EXPLOSION_PARTICLE_SPIN
            }

            if !p.is_swirling_charge && p.life_remaining <= 0.0 {
                if p.has_active_sound {
                    ma.sound_uninit(&p.sound_hum)
                    ma.sound_uninit(&p.sound_whoosh)
                    p.has_active_sound = false
                }
                p.active = false
                continue
            }

            life_ratio_part: f32 = 0.0
            if p.life_max > 0.0 { life_ratio_part = math.max(f32(0.0), p.life_remaining / p.life_max) }

            if p.is_swirling_charge {
                p.size = p.start_size
                p.color.a = 1.0
            } else {
                p.size = p.start_size * life_ratio_part * life_ratio_part
                p.color.a = life_ratio_part * life_ratio_part
            }
        }

        if live_particle_count < shared.MAX_PARTICLES {
            inst := &shared.state.particle_instance_data[live_particle_count]
            inst.instance_pos=p.pos
            inst.instance_size=p.size
            inst.instance_rotation = p.rotation
            inst.instance_color=p.color
            live_particle_count += 1
        }
    }
    return live_particle_count
}

// Small bright burst on every LMB-projectile impact, kill or no kill — gives the shot a
// visible "click" so the player reads the connection without waiting for a kill animation.
spawn_LMB_hit_flash :: proc(pos: m.vec2, base_color: m.vec4) {
    context = runtime.default_context()
    for _ in 0..<shared.LMB_HIT_FLASH_COUNT {
        angle := rand.float32() * m.TAU
        dir := m.angle_to_vec2(angle)
        speed := shared.LMB_HIT_FLASH_SPEED_BASE + rand.float32() * shared.LMB_HIT_FLASH_SPEED_RAND
        life  := shared.LMB_HIT_FLASH_LIFETIME_BASE + rand.float32() * shared.LMB_HIT_FLASH_LIFETIME_RAND
        size  := shared.LMB_HIT_FLASH_SIZE_BASE + rand.float32() * shared.LMB_HIT_FLASH_SIZE_RAND
        // Mix the enemy's tint with the LMB purple so the flash feels like the bullet bursting,
        // not a generic explosion.
        color := m.vec4{
            math.clamp(base_color.r * 0.4 + 0.7, 0.0, 1.0),
            math.clamp(base_color.g * 0.4 + 0.4, 0.0, 1.0),
            math.clamp(base_color.b * 0.4 + 0.9, 0.0, 1.0),
            0.95,
        }
        emit_particle(shared.Particle{
            pos=pos, vel=dir*speed, cloud_travel_vel={0,0}, color=color, size=size, start_size=size,
            life_remaining=life, life_max=life, swirl_duration=0,
            rotation=rand.float32()*m.TAU, angular_vel=0,
            charge_center_pos={0,0}, is_burst_particle=true, is_swirling_charge=false, active=false,
        })
    }
}

spawn_LMB_enemy_death_particles :: proc(pos: m.vec2, base_color: m.vec4) {
    context = runtime.default_context()
    for _ in 0..<shared.LMB_ENEMY_DEATH_PARTICLE_COUNT {
        angle_lmb_d := rand.float32() * m.TAU
        dir_lmb_d := m.angle_to_vec2(angle_lmb_d)
        speed_lmb_d := shared.LMB_ENEMY_DEATH_PARTICLE_SPEED_BASE + rand.float32() * shared.LMB_ENEMY_DEATH_PARTICLE_SPEED_RAND
        life_lmb_d := shared.LMB_ENEMY_DEATH_PARTICLE_LIFETIME_BASE + rand.float32() * shared.LMB_ENEMY_DEATH_PARTICLE_LIFETIME_RAND
        size_lmb_d := shared.LMB_ENEMY_DEATH_PARTICLE_SIZE_BASE + rand.float32() * shared.LMB_ENEMY_DEATH_PARTICLE_SIZE_RAND
        angular_vel_lmb_d := rand.float32_range(-1.0, 1.0) * shared.LMB_ENEMY_DEATH_PARTICLE_ANGULAR_VEL_MAX
        particle_color_lmb_d := base_color
        particle_color_lmb_d.r = math.min(base_color.r * 1.2 + 0.2, 1.0)
        particle_color_lmb_d.g = math.min(base_color.g * 1.2 + 0.2, 1.0)
        particle_color_lmb_d.b = math.min(base_color.b * 1.2 + 0.2, 1.0)
        particle_color_lmb_d.a = 0.85
        emit_particle(shared.Particle{
            pos=pos, vel=dir_lmb_d*speed_lmb_d, cloud_travel_vel={0,0}, color=particle_color_lmb_d, size=size_lmb_d, start_size=size_lmb_d,
            life_remaining=life_lmb_d, life_max=life_lmb_d, swirl_duration=0, rotation=rand.float32()*m.TAU, angular_vel=angular_vel_lmb_d,
            charge_center_pos={0,0}, is_burst_particle=true, is_swirling_charge=false, active=false,
        })
    }
}

spawn_RMB_enemy_death_particles :: proc(pos: m.vec2) {
    context = runtime.default_context()
    base_death_color_rmb := shared.RMB_PARTICLE_COLOR
    for _ in 0..<shared.RMB_ENEMY_DEATH_PARTICLE_COUNT {
        angle_rmb_d := rand.float32() * m.TAU
        dir_rmb_d := m.angle_to_vec2(angle_rmb_d)
        speed_rmb_d := shared.RMB_ENEMY_DEATH_PARTICLE_SPEED_BASE + rand.float32() * shared.RMB_ENEMY_DEATH_PARTICLE_SPEED_RAND
        life_rmb_d := shared.RMB_ENEMY_DEATH_PARTICLE_LIFETIME_BASE + rand.float32() * shared.RMB_ENEMY_DEATH_PARTICLE_LIFETIME_RAND
        size_rmb_d := shared.RMB_ENEMY_DEATH_PARTICLE_SIZE_BASE + rand.float32() * shared.RMB_ENEMY_DEATH_PARTICLE_SIZE_RAND
        angular_vel_rmb_d := rand.float32_range(-1.0, 1.0) * shared.RMB_ENEMY_DEATH_PARTICLE_ANGULAR_VEL_MAX
        particle_color_rmb_d := base_death_color_rmb
        particle_color_rmb_d.r = math.clamp(base_death_color_rmb.r + rand.float32_range(-0.1, 0.1), 0.5, 1.0)
        particle_color_rmb_d.g = math.clamp(base_death_color_rmb.g + rand.float32_range(-0.1, 0.1), 0.2, 0.8)
        particle_color_rmb_d.b = math.clamp(base_death_color_rmb.b + rand.float32_range(-0.1, 0.1), 0.7, 1.0)
        particle_color_rmb_d.a = rand.float32_range(0.6, 0.9)
        emit_particle(shared.Particle{
            pos=pos, vel=dir_rmb_d*speed_rmb_d, cloud_travel_vel={0,0}, color=particle_color_rmb_d, size=size_rmb_d, start_size=size_rmb_d,
            life_remaining=life_rmb_d, life_max=life_rmb_d,
            swirl_duration=0, rotation=rand.float32()*m.TAU, angular_vel=angular_vel_rmb_d,
            charge_center_pos={0,0}, is_burst_particle=true, is_swirling_charge=false, active=false,
        })
    }
}
