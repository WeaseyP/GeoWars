package collision

import "base:runtime"
import m "../../vendor/math"
import ma "../../vendor/miniaudio"
import "core:fmt"
import "core:math"
import rand "core:math/rand"
import shared "../../shared"
import game_audio "../../audio"
import particle "../particle"
import enemy "../enemy"


// Splitter mini-spawn: when a splitter dies to LMB or contact (NOT RMB), spawn 3 mini grunts
// with outward burst velocities. RMB-clean kills bypass this. Each mini coasts on its burst
// velocity for ~1.0–1.5s (randomised so they don't all start homing on the same frame) before
// reverting to normal grunt homing — otherwise the homing-on-frame-1 stacks all three minis
// into one moving pile heading at the player.
@(private)
splitter_spawn_minis :: proc(pos: m.vec2) {
    base_angle := rand.float32() * m.TAU
    for k in 0..<shared.ENEMY_SPLITTER_MINI_COUNT {
        angle := base_angle + f32(k) * (m.TAU / f32(shared.ENEMY_SPLITTER_MINI_COUNT))
        burst_dir := m.vec2{math.cos(angle), math.sin(angle)}
        mini_pos := pos + burst_dir * 0.05
        mini_vel := burst_dir * shared.ENEMY_SPLITTER_MINI_BURST_SPEED
        burst_duration := rand.float32_range(shared.ENEMY_SPLITTER_MINI_BURST_DURATION_MIN,
                                             shared.ENEMY_SPLITTER_MINI_BURST_DURATION_MAX)
        enemy.emit_grunt_at_pos(mini_pos, mini_vel, burst_duration)
    }
}

// On-death dispatch. by_rmb=true means the kill came from an RMB particle (clean kill,
// suppresses splitter mini-spawn). Other paths (LMB projectile, body contact) split.
// Also unlocks per-type music tracks that should persist for the rest of the run.
@(private)
on_enemy_death :: proc(e: ^shared.Enemy, by_rmb: bool) {
    if e.type == .SPLITTER && !by_rmb {
        splitter_spawn_minis(e.pos)
    }
    switch e.type {
    case .GRUNT:           shared.state.first_grunt_killed = true
    case .SLOWBOY:         shared.state.first_slowboy_killed = true
    case .SPLITTER:        shared.state.first_splitter_killed = true
    case .SNIPER:          shared.state.first_sniper_killed = true
    case .DISRUPTOR:       // disruptor track is alive-gated, no flag
    case .BOSS_CHROME_ORB: // boss track is alive-gated
    }
}

@(private)
notify_boss_music_hit :: proc(e: ^shared.Enemy, damage: i32) {
    if e.type != .BOSS_CHROME_ORB { return }
    hp_ratio := math.clamp(f32(e.hp) / f32(shared.ENEMY_BOSS_CHROME_ORB_MAX_HP), 0.0, 1.0)
    game_audio.notify_boss_hit(damage, hp_ratio)
}


check_RMB_particle_enemy_collisions :: proc() {
    context = runtime.default_context()
    for i in 0..<shared.MAX_PARTICLES {
        particle_rmb_coll := &shared.state.particles[i]
        if !particle_rmb_coll.active || particle_rmb_coll.is_burst_particle {
            continue
        }
        particle_radius_rmb_coll := particle_rmb_coll.size * 0.5
        if particle_radius_rmb_coll <= 0.001 { continue }

        for j in 0..<shared.MAX_ENEMIES {
            enemy_rmb_coll := &shared.state.enemies[j]
            if !enemy_rmb_coll.active || enemy_rmb_coll.is_dying { continue }

            enemy_radius_rmb_coll := enemy_rmb_coll.current_size * 0.5
            if enemy_radius_rmb_coll <= 0.001 { continue }

            dist_sq_rmb_coll := m.len_sq_vec2(particle_rmb_coll.pos - enemy_rmb_coll.pos)
            radii_sum_rmb_coll := particle_radius_rmb_coll + enemy_radius_rmb_coll
            radii_sum_sq_rmb_coll := radii_sum_rmb_coll * radii_sum_rmb_coll

            if dist_sq_rmb_coll < radii_sum_sq_rmb_coll {
                rmb_dmg := i32(math.round(f32(shared.PARTICLE_DAMAGE_VALUE) * shared.state.eff_rmb_damage_mult))
                if rmb_dmg < 1 { rmb_dmg = 1 }
                enemy_rmb_coll.hp -= rmb_dmg
                notify_boss_music_hit(enemy_rmb_coll, rmb_dmg)

                if enemy_rmb_coll.hp <= 0 {
                    if !enemy_rmb_coll.is_dying {
                        ma.sound_seek_to_pcm_frame(&shared.state.rmb_kill_sound, 0)
                        ma.sound_start(&shared.state.rmb_kill_sound)
                    }
                } else {
                    ma.sound_seek_to_pcm_frame(&shared.state.rmb_hit_sound, 0)
                    ma.sound_start(&shared.state.rmb_hit_sound)
                }

                particle_rmb_coll.has_active_sound = false
                particle_rmb_coll.active = false

                if enemy_rmb_coll.hp <= 0 && !enemy_rmb_coll.is_dying {
                    enemy_rmb_coll.is_dying = true
                    fmt.printf("RMB Kill: %v defeated.\n", enemy_rmb_coll.type)
                    death_dur: f32 = shared.GRUNT_DEATH_ANIM_DURATION
                    switch enemy_rmb_coll.type {
                    case .GRUNT:           death_dur = shared.GRUNT_DEATH_ANIM_DURATION
                    case .SLOWBOY:         death_dur = shared.SLOWBOY_DEATH_ANIM_DURATION
                    case .BOSS_CHROME_ORB: death_dur = shared.BOSS_DEATH_ANIM_DURATION
                    case .SPLITTER:        death_dur = shared.ENEMY_SPLITTER_DEATH_ANIM
                    case .SNIPER:          death_dur = shared.ENEMY_SNIPER_DEATH_ANIM
                    case .DISRUPTOR:       death_dur = shared.ENEMY_DISRUPTOR_DEATH_ANIM
                    }
                    enemy_rmb_coll.dying_timer = death_dur
                    enemy_rmb_coll.death_anim_max_duration = death_dur
                    enemy_rmb_coll.death_rect_offset = 0.0
                    on_enemy_death(enemy_rmb_coll, true) // RMB-clean kill — splitter doesn't split
                    particle.spawn_RMB_enemy_death_particles(enemy_rmb_coll.pos)
                }
                break
            }
        }
    }
}

// One-shot line-vs-enemy hit applied when the RMB beam is fired. The beam is a thin
// rectangle from `origin` along unit vector `dir` with length RMB_BEAM_LENGTH and half-width
// RMB_BEAM_HALF_WIDTH (plus enemy radius). Any enemy whose body the rectangle clips takes
// (PARTICLE_DAMAGE_VALUE * eff_rmb_damage_mult * RMB_BEAM_DAMAGE_MULT) damage. RMB-clean kills
// (no splitter mini-spawn). Beam collision is intentionally one frame only — the visual lasts
// RMB_BEAM_DURATION but the hit lands on release.
apply_rmb_beam_damage :: proc(origin: m.vec2, dir: m.vec2) {
    context = runtime.default_context()
    if m.len_sq_vec2(dir) < 0.0001 { return }
    // Perpendicular for the half-width check.
    perp := m.vec2{-dir.y, dir.x}
    base_dmg := f32(shared.PARTICLE_DAMAGE_VALUE) * shared.state.eff_rmb_damage_mult * shared.RMB_BEAM_DAMAGE_MULT
    beam_dmg := i32(math.round(base_dmg))
    if beam_dmg < 1 { beam_dmg = 1 }

    for j in 0..<shared.MAX_ENEMIES {
        e := &shared.state.enemies[j]
        if !e.active || e.is_dying { continue }
        enemy_radius := e.current_size * 0.5
        if enemy_radius <= 0.001 { continue }

        // Project enemy centre onto the beam axis.
        rel := e.pos - origin
        along := rel.x * dir.x + rel.y * dir.y
        side  := rel.x * perp.x + rel.y * perp.y
        if along < -enemy_radius { continue }
        if along > shared.RMB_BEAM_LENGTH + enemy_radius { continue }
        if math.abs(side) > shared.RMB_BEAM_HALF_WIDTH + enemy_radius { continue }

        e.hp -= beam_dmg
        notify_boss_music_hit(e, beam_dmg)
        if e.hp <= 0 {
            if !e.is_dying {
                ma.sound_seek_to_pcm_frame(&shared.state.rmb_kill_sound, 0)
                ma.sound_start(&shared.state.rmb_kill_sound)

                e.is_dying = true
                fmt.printf("RMB-Beam Kill: %v defeated.\n", e.type)
                death_dur: f32 = shared.GRUNT_DEATH_ANIM_DURATION
                switch e.type {
                case .GRUNT:           death_dur = shared.GRUNT_DEATH_ANIM_DURATION
                case .SLOWBOY:         death_dur = shared.SLOWBOY_DEATH_ANIM_DURATION
                case .BOSS_CHROME_ORB: death_dur = shared.BOSS_DEATH_ANIM_DURATION
                case .SPLITTER:        death_dur = shared.ENEMY_SPLITTER_DEATH_ANIM
                case .SNIPER:          death_dur = shared.ENEMY_SNIPER_DEATH_ANIM
                case .DISRUPTOR:       death_dur = shared.ENEMY_DISRUPTOR_DEATH_ANIM
                }
                e.dying_timer = death_dur
                e.death_anim_max_duration = death_dur
                e.death_rect_offset = 0.0
                on_enemy_death(e, true) // beam counts as a clean RMB kill
                particle.spawn_RMB_enemy_death_particles(e.pos)
            }
        } else {
            ma.sound_seek_to_pcm_frame(&shared.state.rmb_hit_sound, 0)
            ma.sound_start(&shared.state.rmb_hit_sound)
        }
    }
}

check_LMB_projectile_enemy_collisions :: proc() {
    context = runtime.default_context()
    for i in 0..<shared.MAX_BLACKHOLES {
        proj_lmb_coll := &shared.state.blackholes[i]
        if !proj_lmb_coll.active { continue }
        proj_radius_lmb_coll := proj_lmb_coll.size * 0.5
        for j in 0..<shared.MAX_ENEMIES {
            enemy_lmb_coll := &shared.state.enemies[j]
            if !enemy_lmb_coll.active || enemy_lmb_coll.is_dying { continue }

            enemy_radius_lmb_coll := enemy_lmb_coll.current_size * 0.5
            dist_sq_lmb_coll := m.len_sq_vec2(proj_lmb_coll.pos - enemy_lmb_coll.pos)
            radii_sum_lmb_coll := proj_radius_lmb_coll + enemy_radius_lmb_coll
            radii_sum_sq_lmb_coll := radii_sum_lmb_coll * radii_sum_lmb_coll

            if dist_sq_lmb_coll < radii_sum_sq_lmb_coll {
                proj_lmb_coll.active = false
                enemy_lmb_coll.hp -= shared.state.eff_lmb_damage
                notify_boss_music_hit(enemy_lmb_coll, shared.state.eff_lmb_damage)
                // Always pop a tiny flash at the impact site so the hit reads instantly,
                // even if the projectile didn't kill. The death-particle burst (further down)
                // only fires on the killing blow.
                particle.spawn_LMB_hit_flash(proj_lmb_coll.pos, enemy_lmb_coll.color)
                if enemy_lmb_coll.hp <= 0 {
                    if !enemy_lmb_coll.is_dying {
                         ma.sound_seek_to_pcm_frame(&shared.state.lmb_kill_sound, 0)
                         ma.sound_start(&shared.state.lmb_kill_sound)
                    }
                } else {
                    ma.sound_seek_to_pcm_frame(&shared.state.lmb_hit_sound, 0)
                    ma.sound_start(&shared.state.lmb_hit_sound)
                }

                if enemy_lmb_coll.hp <= 0 && !enemy_lmb_coll.is_dying {
                    enemy_lmb_coll.is_dying = true
                    fmt.printf("LMB Kill: %v defeated.\n", enemy_lmb_coll.type)
                    death_dur: f32 = shared.GRUNT_DEATH_ANIM_DURATION
                    switch enemy_lmb_coll.type {
                    case .GRUNT:           death_dur = shared.GRUNT_DEATH_ANIM_DURATION
                    case .SLOWBOY:         death_dur = shared.SLOWBOY_DEATH_ANIM_DURATION
                    case .BOSS_CHROME_ORB: death_dur = shared.BOSS_DEATH_ANIM_DURATION
                    case .SPLITTER:        death_dur = shared.ENEMY_SPLITTER_DEATH_ANIM
                    case .SNIPER:          death_dur = shared.ENEMY_SNIPER_DEATH_ANIM
                    case .DISRUPTOR:       death_dur = shared.ENEMY_DISRUPTOR_DEATH_ANIM
                    }
                    enemy_lmb_coll.dying_timer = death_dur
                    enemy_lmb_coll.death_anim_max_duration = death_dur
                    enemy_lmb_coll.death_rect_offset = 0.0
                    on_enemy_death(enemy_lmb_coll, false) // LMB kill — splitter splits
                    particle.spawn_LMB_enemy_death_particles(enemy_lmb_coll.pos, enemy_lmb_coll.color)
                }
                break
            }
        }
    }
}
