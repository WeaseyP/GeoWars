package collision

import "base:runtime"
import m "../../vendor/math"
import ma "../../vendor/miniaudio"
import "core:fmt"
import shared "../../shared"
import particle "../particle"


check_RMB_particle_enemy_collisions :: proc() {
    context = runtime.default_context()
    for i in 0..<shared.MAX_PARTICLES {
        particle_rmb_coll := &shared.state.particles[i]
        if !particle_rmb_coll.active || particle_rmb_coll.is_ammo_indicator || particle_rmb_coll.is_burst_particle {
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
                enemy_rmb_coll.hp -= shared.PARTICLE_DAMAGE_VALUE

                if enemy_rmb_coll.hp <= 0 {
                    if !enemy_rmb_coll.is_dying {
                        ma.sound_seek_to_pcm_frame(&shared.state.rmb_kill_sound, 0)
                        ma.sound_start(&shared.state.rmb_kill_sound)
                    }
                } else {
                    ma.sound_seek_to_pcm_frame(&shared.state.rmb_hit_sound, 0)
                    ma.sound_start(&shared.state.rmb_hit_sound)
                }

                if particle_rmb_coll.has_active_sound {
                    ma.sound_uninit(&particle_rmb_coll.sound_hum)
                    ma.sound_uninit(&particle_rmb_coll.sound_whoosh)
                    particle_rmb_coll.has_active_sound = false
                }
                particle_rmb_coll.active = false

                if enemy_rmb_coll.hp <= 0 && !enemy_rmb_coll.is_dying {
                    enemy_rmb_coll.is_dying = true
                    shared.state.progression.enemies_defeated_in_current_stage += 1
                    fmt.printf("RMB Kill: Enemy defeated. Stage progress: %d/%d\n", shared.state.progression.enemies_defeated_in_current_stage, shared.state.progression.total_enemies_defined_for_current_stage)
                    if enemy_rmb_coll.type == .GRUNT {
                        enemy_rmb_coll.dying_timer = shared.GRUNT_DEATH_ANIM_DURATION
                        enemy_rmb_coll.death_anim_max_duration = shared.GRUNT_DEATH_ANIM_DURATION
                    } else if enemy_rmb_coll.type == .SLOWBOY {
                        enemy_rmb_coll.dying_timer = shared.SLOWBOY_DEATH_ANIM_DURATION
                        enemy_rmb_coll.death_anim_max_duration = shared.SLOWBOY_DEATH_ANIM_DURATION
                    } else if enemy_rmb_coll.type == .BOSS_CHROME_ORB {
                        enemy_rmb_coll.dying_timer = shared.BOSS_DEATH_ANIM_DURATION
                        enemy_rmb_coll.death_anim_max_duration = shared.BOSS_DEATH_ANIM_DURATION
                    } else {
                        enemy_rmb_coll.dying_timer = shared.GRUNT_DEATH_ANIM_DURATION
                        enemy_rmb_coll.death_anim_max_duration = shared.GRUNT_DEATH_ANIM_DURATION
                    }
                    enemy_rmb_coll.death_rect_offset = 0.0
                    particle.spawn_RMB_enemy_death_particles(enemy_rmb_coll.pos)
                    if enemy_rmb_coll.type == .GRUNT && !shared.state.first_grunt_killed {
                        shared.state.first_grunt_killed = true
                        start_drum_err_rmb := ma.sound_start(&shared.state.drum_track_sound)
                        if start_drum_err_rmb == .SUCCESS { fmt.printf("--- First GRUNT killed! Starting drum track. ---\n") }
                        else { fmt.eprintf("!!! ERROR: Failed to start drum_track_sound! Error: %v\n", start_drum_err_rmb) }
                    }
                    if enemy_rmb_coll.type == .SLOWBOY && !shared.state.first_slowboy_killed {
                        shared.state.first_slowboy_killed = true
                        start_synth_err := ma.sound_start(&shared.state.synth_track_sound)
                        if start_synth_err == .SUCCESS {
                            fmt.printf("--- First SLOWBOY killed! Starting synth track. ---\n")
                        } else {
                            fmt.eprintf("!!! ERROR: Failed to start synth_track_sound! Error: %v\n", start_synth_err)
                        }
                    }
                }
                break
            }
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
                enemy_lmb_coll.hp -= shared.LMB_PROJECTILE_DAMAGE
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
                    shared.state.progression.enemies_defeated_in_current_stage += 1
                    fmt.printf("LMB Kill: Enemy defeated. Stage progress: %d/%d\n", shared.state.progression.enemies_defeated_in_current_stage, shared.state.progression.total_enemies_defined_for_current_stage)
                    if enemy_lmb_coll.type == .GRUNT {
                        enemy_lmb_coll.dying_timer = shared.GRUNT_DEATH_ANIM_DURATION
                        enemy_lmb_coll.death_anim_max_duration = shared.GRUNT_DEATH_ANIM_DURATION
                    } else if enemy_lmb_coll.type == .SLOWBOY {
                        enemy_lmb_coll.dying_timer = shared.SLOWBOY_DEATH_ANIM_DURATION
                        enemy_lmb_coll.death_anim_max_duration = shared.SLOWBOY_DEATH_ANIM_DURATION
                     } else if enemy_lmb_coll.type == .BOSS_CHROME_ORB {
                        enemy_lmb_coll.dying_timer = shared.BOSS_DEATH_ANIM_DURATION
                        enemy_lmb_coll.death_anim_max_duration = shared.BOSS_DEATH_ANIM_DURATION
                    } else {
                        enemy_lmb_coll.dying_timer = shared.GRUNT_DEATH_ANIM_DURATION
                        enemy_lmb_coll.death_anim_max_duration = shared.GRUNT_DEATH_ANIM_DURATION
                    }
                    enemy_lmb_coll.death_rect_offset = 0.0
                    particle.spawn_LMB_enemy_death_particles(enemy_lmb_coll.pos, enemy_lmb_coll.color)
                    if enemy_lmb_coll.type == .GRUNT && !shared.state.first_grunt_killed {
                        shared.state.first_grunt_killed = true
                        start_drum_err_lmb := ma.sound_start(&shared.state.drum_track_sound)
                        if start_drum_err_lmb == .SUCCESS { fmt.printf("--- First GRUNT killed! Starting drum track. ---\n") }
                        else { fmt.eprintf("!!! ERROR: Failed to start drum_track_sound! Error: %v\n", start_drum_err_lmb) }
                    }
                    if enemy_lmb_coll.type == .SLOWBOY && !shared.state.first_slowboy_killed {
                        shared.state.first_slowboy_killed = true
                        start_synth_err := ma.sound_start(&shared.state.synth_track_sound)
                        if start_synth_err == .SUCCESS {
                            fmt.printf("--- First SLOWBOY killed! Starting synth track. ---\n")
                        } else {
                            fmt.eprintf("!!! ERROR: Failed to start synth_track_sound! Error: %v\n", start_synth_err)
                        }
                    }
                }
                break
            }
        }
    }
}
