package player

import m "../../vendor/math"
import "core:math"
import "core:fmt"
import ma "../../vendor/miniaudio"
import sapp "../../vendor/sokol/app"
import "base:runtime"
import shared "../../shared"
import particle "../particle"
import projectile "../projectile"


update_player :: proc(dt: f32) {
    if shared.state.player_hp > 0 {

        if shared.state.dash_timer <= 0.0 && shared.state.is_dashing {
            shared.state.is_dashing = false
        }

        if shared.state.key_shift_down && !shared.state.is_dashing && shared.state.dash_cooldown_timer <= 0.0 {
            shared.state.is_dashing = true
            shared.state.dash_timer = shared.PLAYER_DASH_DURATION
            shared.state.dash_cooldown_timer = shared.PLAYER_DASH_COOLDOWN
            shared.state.player_invulnerable_timer = math.max(shared.state.player_invulnerable_timer, shared.PLAYER_DASH_DURATION)
            shared.state.player_dash_trail_count = 0
            shared.state.dash_trail_spawn_timer = 0.0
            fmt.printf("Player DASH!\n")
        }

        if shared.state.current_rmb_ammo_charges < shared.MAX_RMB_AMMO_CHARGES {
            shared.state.rmb_ammo_regen_timer -= dt
            if shared.state.rmb_ammo_regen_timer <= 0.0 {
                particle.spawn_visual_ammo_charge_particles(shared.state.current_rmb_ammo_charges)
                shared.state.current_rmb_ammo_charges += 1
                shared.state.rmb_ammo_regen_timer = shared.RMB_AMMO_REGEN_INTERVAL
                fmt.printf("RMB Ammo Charge Regenerated! Current: %d/%d\n", shared.state.current_rmb_ammo_charges, shared.MAX_RMB_AMMO_CHARGES)
            }
        }
        accel_input_f := m.vec2_zero()
        if shared.state.key_w_down {accel_input_f.y+=1.0}; if shared.state.key_s_down {accel_input_f.y-=1.0}
        if shared.state.key_a_down {accel_input_f.x-=1.0}; if shared.state.key_d_down {accel_input_f.x+=1.0}
        if m.len_sq_vec2(accel_input_f) > 0.001 {accel_input_f=m.norm_vec2(accel_input_f)}
        if shared.state.is_dashing {
            if shared.state.dash_timer <= 0.0 {
                shared.state.is_dashing = false
                shared.state.player_dash_trail_count = 0
            } else {
                shared.state.dash_trail_spawn_timer -= dt
                if shared.state.dash_trail_spawn_timer <= 0.0 {
                    shared.state.dash_trail_spawn_timer = shared.PLAYER_DASH_TRAIL_SPAWN_RATE
                    for i := shared.PLAYER_DASH_TRAIL_LENGTH - 1; i > 0; i -= 1 {
                        shared.state.player_dash_traiL_pos[i] = shared.state.player_dash_traiL_pos[i-1]
                    }
                    shared.state.player_dash_traiL_pos[0] = shared.state.player_pos
                    if shared.state.player_dash_trail_count < shared.PLAYER_DASH_TRAIL_LENGTH {
                        shared.state.player_dash_trail_count += 1
                    }
                }
            }
            dash_direction := accel_input_f
            if m.len_sq_vec2(dash_direction) < 0.1 && m.len_sq_vec2(shared.state.player_vel) > 0.1 {
                dash_direction = m.norm_vec2(shared.state.player_vel)
            } else if m.len_sq_vec2(dash_direction) < 0.1 {
                dash_direction = {0, 1}
            }
            shared.state.player_vel = dash_direction * shared.PLAYER_MAX_SPEED * shared.PLAYER_DASH_SPEED_MULT
        } else {
            final_accel_f := accel_input_f * shared.PLAYER_ACCELERATION
            if shared.state.key_s_down && !shared.state.key_w_down && accel_input_f.y < -0.5 { final_accel_f *= shared.PLAYER_REVERSE_FACTOR }
            shared.state.player_vel += final_accel_f * dt
            damping_factor_f := math.max(0.0, 1.0 - shared.PLAYER_DAMPING*dt)
            shared.state.player_vel *= damping_factor_f
            if m.len_sq_vec2(shared.state.player_vel) > f32(shared.PLAYER_MAX_SPEED * shared.PLAYER_MAX_SPEED) {
                shared.state.player_vel = m.norm_vec2(shared.state.player_vel) * shared.PLAYER_MAX_SPEED
            }
        }


        shared.state.player_pos += shared.state.player_vel * dt

        rmb_pressed_this_frame_f := shared.state.rmb_down && !shared.state.previous_rmb_down
        if rmb_pressed_this_frame_f && shared.state.current_rmb_ammo_charges > 0 {
            particle.remove_visual_ammo_charge_particles(shared.state.current_rmb_ammo_charges - 1)
        }
        if rmb_pressed_this_frame_f && shared.state.rmb_cooldown_timer <= 0.0 {
            if shared.state.current_rmb_ammo_charges > 0 {
                shared.state.current_rmb_ammo_charges -= 1
                particle.spawn_swirling_charge()
                fmt.printf("RMB Fired! Ammo Remaining: %d/%d\n", shared.state.current_rmb_ammo_charges, shared.MAX_RMB_AMMO_CHARGES)
                if shared.BLACKHOLE_COOLDOWN_DURATION > 0.0 { shared.state.rmb_cooldown_timer = shared.BLACKHOLE_COOLDOWN_DURATION }
            } else {
                fmt.printf("RMB - NO AMMO! (Charges: %d/%d)\n", shared.state.current_rmb_ammo_charges, shared.MAX_RMB_AMMO_CHARGES)
            }
        }
        shared.state.previous_rmb_down = shared.state.rmb_down

        if shared.state.lmb_down && shared.state.lmb_cooldown_timer <= 0.0 {
            projectile.spawn_blackhole_projectile_weapon()
            seek_result_f := ma.sound_seek_to_pcm_frame(&shared.state.lmb_sound, 0)
            if seek_result_f != .SUCCESS { fmt.eprintf("WARNING: Failed to seek lmb_sound to beginning. Error: %v\n", seek_result_f) }
            start_result_f := ma.sound_start(&shared.state.lmb_sound)
            if start_result_f != .SUCCESS { fmt.eprintf("WARNING: Failed to start lmb_sound. Error: %v\n", start_result_f) }
            shared.state.lmb_cooldown_timer = shared.PROJECTILE_BLACKHOLE_COOLDOWN
        }
        shared.state.previous_lmb_down = shared.state.lmb_down
    } else {
        shared.state.player_vel = {0,0}
        if !shared.state.player_defeated_message_shown {
            fmt.printf("--- PLAYER DEFEATED ---\n")
            shared.state.player_defeated_message_shown = true
        }
    }
}

handle_player_input :: proc(event: ^sapp.Event) {
    #partial switch event.type {
    case .KEY_DOWN: #partial switch event.key_code {
        case .W: shared.state.key_w_down = true
        case .S: shared.state.key_s_down = true
        case .A: shared.state.key_a_down = true
        case .D: shared.state.key_d_down = true
        case .LEFT_SHIFT: shared.state.key_shift_down = true
        case .ESCAPE: sapp.request_quit()
    }
    case .KEY_UP: #partial switch event.key_code {
        case .W: shared.state.key_w_down = false
        case .S: shared.state.key_s_down = false
        case .A: shared.state.key_a_down = false
        case .D: shared.state.key_d_down = false
        case .LEFT_SHIFT: shared.state.key_shift_down = false
    }
    case .MOUSE_DOWN:
        if event.mouse_button == .RIGHT { shared.state.rmb_down = true }
        if event.mouse_button == .LEFT  { shared.state.lmb_down = true }
    case .MOUSE_UP:
        if event.mouse_button == .RIGHT { shared.state.rmb_down = false }
        if event.mouse_button == .LEFT  { shared.state.lmb_down = false }
    case .MOUSE_MOVE:
        shared.state.mouse_screen_pos = {event.mouse_x, event.mouse_y}
    }
}

check_player_boss_laser_collision :: proc() {
    context = runtime.default_context()
    if shared.state.player_hp <= 0 || shared.state.player_invulnerable_timer > 0.0 { return }

    player_center := shared.state.player_pos
    player_radius : f32 = shared.PLAYER_CORE_WORLD_RADIUS

    for i in 0..<shared.MAX_ENEMIES {
        enemy_laser_coll := &shared.state.enemies[i]
        if !enemy_laser_coll.active || enemy_laser_coll.type != .BOSS_CHROME_ORB || enemy_laser_coll.is_dying || enemy_laser_coll.is_growing {
            continue
        }

        shader_uv_sphere_radius          : f32 = 0.45
        shader_black_circle_orbit_factor : f32 = 0.6

        world_radius_of_main_sphere_visual := enemy_laser_coll.current_size * shader_uv_sphere_radius
        world_orbit_radius_for_black_circle := world_radius_of_main_sphere_visual * shader_black_circle_orbit_factor

        boss_facing_direction := m.norm_vec2(m.vec2{math.cos(enemy_laser_coll.rotation), math.sin(enemy_laser_coll.rotation)})
        black_circle_world_center := enemy_laser_coll.pos + boss_facing_direction * world_orbit_radius_for_black_circle

        laser_origin_world := black_circle_world_center
        laser_direction_vec := boss_facing_direction

        vec_to_player_from_origin := player_center - laser_origin_world

        player_local_y := m.dot_vec2(vec_to_player_from_origin, laser_direction_vec)
        laser_perpendicular_vec := m.vec2{-laser_direction_vec.y, laser_direction_vec.x}
        player_local_x := m.dot_vec2(vec_to_player_from_origin, laser_perpendicular_vec)

        if player_local_y >= -player_radius && player_local_y <= (shared.BOSS_LASER_LENGTH + player_radius) &&
           math.abs(player_local_x) <= (shared.BOSS_LASER_WIDTH / 2.0 + player_radius) {

            if player_local_y > 0 && player_local_y < shared.BOSS_LASER_LENGTH &&
               math.abs(player_local_x) < (shared.BOSS_LASER_WIDTH / 2.0 + player_radius) {
                shared.state.player_hp -= shared.BOSS_LASER_DAMAGE
                shared.state.player_hp = math.max(shared.state.player_hp, 0)
                shared.state.player_invulnerable_timer = shared.PLAYER_INVULNERABILITY_DURATION / 2.0
                fmt.printf("Player hit by BOSS LASER (Body)! HP: %d/%d. Invulnerable for %.2fs\n", shared.state.player_hp, shared.state.player_max_hp, shared.state.player_invulnerable_timer)
                return
            } else {
                cap_radius_for_check_sq := (shared.BOSS_LASER_WIDTH / 2.0 + player_radius) * (shared.BOSS_LASER_WIDTH / 2.0 + player_radius)

                if m.dist_sq_vec2(player_center, laser_origin_world) < cap_radius_for_check_sq {
                    shared.state.player_hp -= shared.BOSS_LASER_DAMAGE
                    shared.state.player_hp = math.max(shared.state.player_hp, 0)
                    shared.state.player_invulnerable_timer = shared.PLAYER_INVULNERABILITY_DURATION / 2.0
                    fmt.printf("Player hit by BOSS LASER (Origin Cap)! HP: %d/%d. Invulnerable for %.2fs\n", shared.state.player_hp, shared.state.player_max_hp, shared.state.player_invulnerable_timer)
                    return
                }

                laser_end_world := laser_origin_world + laser_direction_vec * shared.BOSS_LASER_LENGTH
                if m.dist_sq_vec2(player_center, laser_end_world) < cap_radius_for_check_sq {
                    shared.state.player_hp -= shared.BOSS_LASER_DAMAGE
                    shared.state.player_hp = math.max(shared.state.player_hp, 0)
                    shared.state.player_invulnerable_timer = shared.PLAYER_INVULNERABILITY_DURATION / 2.0
                    fmt.printf("Player hit by BOSS LASER (End Cap)! HP: %d/%d. Invulnerable for %.2fs\n", shared.state.player_hp, shared.state.player_max_hp, shared.state.player_invulnerable_timer)
                    return
                }
            }
        }
    }
}

check_player_enemy_collisions :: proc() {
    context = runtime.default_context()
    if shared.state.player_hp <= 0 || shared.state.player_invulnerable_timer > 0.0 { return }
    player_radius_pe_coll := f32(shared.PLAYER_CORE_WORLD_RADIUS)
    for i in 0..<shared.MAX_ENEMIES {
        enemy_pe_coll := &shared.state.enemies[i]
        if !enemy_pe_coll.active || enemy_pe_coll.is_growing || enemy_pe_coll.is_dying { continue }

        enemy_radius_pe_coll := enemy_pe_coll.current_size * 0.5
        if enemy_radius_pe_coll <= 0.001 { continue }
        dist_sq_pe_coll := m.dist_sq_vec2(shared.state.player_pos, enemy_pe_coll.pos)
        radii_sum_pe_coll := player_radius_pe_coll + enemy_radius_pe_coll
        radii_sum_sq_pe_coll := radii_sum_pe_coll * radii_sum_pe_coll
        if dist_sq_pe_coll < radii_sum_sq_pe_coll {
            if enemy_pe_coll.hp <= 0 { continue }

            damage_to_player := shared.ENEMY_GRUNT_DAMAGE_VALUE
            if enemy_pe_coll.type == .SLOWBOY && enemy_pe_coll.is_charging_attack {
                damage_to_player = shared.SLOWBOY_ATTACK_DAMAGE
                fmt.printf("Player hit by SLOWBOY CHARGE!\n")
                enemy_pe_coll.is_charging_attack = false
                enemy_pe_coll.vel = {0,0}
            } else if enemy_pe_coll.type == .BOSS_CHROME_ORB {
                fmt.printf("Player hit by BOSS BODY!\n")
            }


            shared.state.player_hp -= damage_to_player
            shared.state.player_hp = math.max(shared.state.player_hp, 0)
            shared.state.player_invulnerable_timer = shared.PLAYER_INVULNERABILITY_DURATION
            fmt.printf("Player hit by ENEMY! HP: %d/%d. Invulnerable for %.2fs\n", shared.state.player_hp, shared.state.player_max_hp, shared.state.player_invulnerable_timer)
            break
        }
    }
}
