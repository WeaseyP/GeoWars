package collision

import "base:runtime"
import m "../../vendor/math"
import ma "../../vendor/miniaudio"
import shared "../../shared"
import projectile "../../game/projectile"
import "core:fmt"
import "core:math"

// Constants
PARTICLE_DAMAGE_VALUE :: 5
LMB_PROJECTILE_DAMAGE :: 2
ENEMY_GRUNT_DAMAGE_VALUE :: 1
SLOWBOY_ATTACK_DAMAGE :: 1
BOSS_LASER_DAMAGE :: 1
PLAYER_INVULNERABILITY_DURATION :: 0.75

// Death Durations
GRUNT_DEATH_ANIM_DURATION :: 3.0
SLOWBOY_DEATH_ANIM_DURATION :: 1.0
BOSS_DEATH_ANIM_DURATION :: 4.0

check_player_boss_laser_collision :: proc(state: ^shared.GameState) {
    if state.player.hp <= 0 || state.player.invulnerable_timer > 0.0 { return }

    player_center := state.player.pos
    player_radius : f32 = shared.PLAYER_CORE_WORLD_RADIUS

    for i in 0..<shared.MAX_ENEMIES {
        e := &state.enemies[i]
        if !e.active || e.type != .BOSS_CHROME_ORB || e.is_dying || e.is_growing { continue }

        // Logic from original code
        world_rad := e.current_size * 0.45 // Shader radius approx
        orbit_rad := world_rad * 0.6

        dir := m.norm_vec2({math.cos(e.rotation), math.sin(e.rotation)})
        origin := e.pos + dir * orbit_rad

        vec_to_p := player_center - origin
        local_y := m.dot_vec2(vec_to_p, dir)
        perp := m.vec2{-dir.y, dir.x}
        local_x := m.dot_vec2(vec_to_p, perp)

        BOSS_LASER_LENGTH :: 1.5
        BOSS_LASER_WIDTH :: 0.2

        if local_y > 0 && local_y < BOSS_LASER_LENGTH && math.abs(local_x) < (BOSS_LASER_WIDTH/2 + player_radius) {
            state.player.hp -= BOSS_LASER_DAMAGE
            state.player.invulnerable_timer = PLAYER_INVULNERABILITY_DURATION / 2.0
            fmt.printf("Player hit by LASER!\n")
        }
    }
}

check_RMB_particle_enemy_collisions :: proc(state: ^shared.GameState) {
    for i in 0..<shared.MAX_PARTICLES {
        p := &state.particles[i]
        if !p.active || p.is_ammo_indicator || p.is_burst_particle { continue }

        p_rad := p.size * 0.5

        for j in 0..<shared.MAX_ENEMIES {
            e := &state.enemies[j]
            if !e.active || e.is_dying { continue }

            e_rad := e.current_size * 0.5
            dist_sq := m.len_sq_vec2(p.pos - e.pos)
            rad_sum := p_rad + e_rad

            if dist_sq < rad_sum * rad_sum {
                e.hp -= PARTICLE_DAMAGE_VALUE
                
                // Sound logic (using state sounds)
                if e.hp <= 0 {
                    ma.sound_seek_to_pcm_frame(&state.rmb_kill_sound, 0)
                    ma.sound_start(&state.rmb_kill_sound)
                } else {
                    ma.sound_seek_to_pcm_frame(&state.rmb_hit_sound, 0)
                    ma.sound_start(&state.rmb_hit_sound)
                }

                p.active = false // consume particle

                if e.hp <= 0 {
                    handle_enemy_death(state, e)
                }
                break
            }
        }
    }
}

check_LMB_projectile_enemy_collisions :: proc(state: ^shared.GameState, proj_mgr: ^projectile.ProjectileManager) {
    for i in 0..<shared.MAX_BLACKHOLES {
        p := &proj_mgr.blackholes[i]
        if !p.active { continue }

        p_rad := p.size * 0.5

        for j in 0..<shared.MAX_ENEMIES {
            e := &state.enemies[j]
            if !e.active || e.is_dying { continue }

            e_rad := e.current_size * 0.5
            dist_sq := m.len_sq_vec2(p.pos - e.pos)
            rad_sum := p_rad + e_rad

            if dist_sq < rad_sum * rad_sum {
                p.active = false // consume projectile
                e.hp -= LMB_PROJECTILE_DAMAGE

                if e.hp <= 0 {
                    ma.sound_seek_to_pcm_frame(&state.lmb_kill_sound, 0)
                    ma.sound_start(&state.lmb_kill_sound)
                } else {
                    ma.sound_seek_to_pcm_frame(&state.lmb_hit_sound, 0)
                    ma.sound_start(&state.lmb_hit_sound)
                }

                if e.hp <= 0 {
                    handle_enemy_death(state, e)
                }
                break
            }
        }
    }
}

check_player_enemy_collisions :: proc(state: ^shared.GameState) {
    if state.player.hp <= 0 || state.player.invulnerable_timer > 0.0 { return }

    p_rad : f32 = shared.PLAYER_CORE_WORLD_RADIUS

    for i in 0..<shared.MAX_ENEMIES {
        e := &state.enemies[i]
        if !e.active || e.is_dying || e.is_growing { continue }

        e_rad := e.current_size * 0.5
        dist_sq := m.len_sq_vec2(state.player.pos - e.pos)
        rad_sum := p_rad + e_rad

        if dist_sq < rad_sum * rad_sum {
            damage := ENEMY_GRUNT_DAMAGE_VALUE
            if e.type == .SLOWBOY && e.is_charging_attack {
                damage = SLOWBOY_ATTACK_DAMAGE
            }

            state.player.hp -= damage
            state.player.hp = math.max(state.player.hp, 0)
            state.player.invulnerable_timer = PLAYER_INVULNERABILITY_DURATION
            fmt.printf("Player hit by ENEMY!\n")
            break
        }
    }
}

handle_enemy_death :: proc(state: ^shared.GameState, e: ^shared.Enemy) {
    e.is_dying = true
    state.progression.enemies_defeated_in_current_stage += 1
    
    // Score
    score_val := 0
    switch e.type {
        case .GRUNT: score_val = 100
        case .SLOWBOY: score_val = 300
        case .WEAVER: score_val = 500
        case .GRAVITRON: score_val = 800
        case .TRACER: score_val = 600
        case .ELITE: score_val = 1500
        case .BOSS_CHROME_ORB: score_val = 10000
    }
    state.score += score_val

    if e.type == .GRUNT { e.dying_timer = GRUNT_DEATH_ANIM_DURATION; e.death_anim_max_duration = GRUNT_DEATH_ANIM_DURATION }
    else if e.type == .BOSS_CHROME_ORB { e.dying_timer = BOSS_DEATH_ANIM_DURATION; e.death_anim_max_duration = BOSS_DEATH_ANIM_DURATION }
    else { e.dying_timer = SLOWBOY_DEATH_ANIM_DURATION; e.death_anim_max_duration = SLOWBOY_DEATH_ANIM_DURATION }

    e.death_rect_offset = 0.0

    // Spawn particles? Need particle package access or callback.
    // Collision package cannot import particle package if particle imports collision (unlikely).
    // Particle imports shared. Collision imports shared.
    // If we call particle.spawn, collision imports particle. Safe.
    // But duplicate logic: `spawn_LMB_enemy_death_particles`.
    // I should expose `spawn_death_particles` in `particle` package and call it here.

    if e.type == .GRUNT && !state.first_grunt_killed {
        state.first_grunt_killed = true
        ma.sound_start(&state.drum_track_sound)
    }
}
