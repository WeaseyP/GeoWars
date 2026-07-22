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
import collision "../collision"


update_player :: proc(dt: f32) {
    if shared.state.player_hp > 0 {

        if shared.state.dash_timer <= 0.0 && shared.state.is_dashing {
            shared.state.is_dashing = false
        }

        // dash_flash decays toward zero independently of is_dashing so the visual lingers a
        // beat after the actual dash ends — afterimages get to fade in place.
        if shared.state.dash_flash > 0.0 {
            shared.state.dash_flash = math.max(0.0,
                shared.state.dash_flash - dt / shared.PLAYER_DASH_FLASH_DURATION)
            // When the flash is fully gone, dispose of the stored trail too. Until then, leave
            // it intact so the renderer can keep drawing fading echoes.
            if shared.state.dash_flash <= 0.0 {
                shared.state.player_dash_trail_count = 0
            }
        }

        if shared.state.key_shift_down && !shared.state.is_dashing && shared.state.dash_cooldown_timer <= 0.0 {
            shared.state.is_dashing = true
            shared.state.dash_timer = shared.PLAYER_DASH_DURATION
            shared.state.dash_cooldown_timer = shared.state.eff_dash_cooldown
            shared.state.player_invulnerable_timer = math.max(shared.state.player_invulnerable_timer, shared.PLAYER_DASH_DURATION)
            shared.state.player_dash_trail_count = 0
            shared.state.dash_trail_spawn_timer = 0.0
            shared.state.dash_flash = 1.0
            fmt.printf("Player DASH!\n")
        }

        // RMB charge passively fills toward the soft cap (eff_rmb_max_charge, default 2.0).
        // Player can fire at any fraction; droplet count scales with charge. >=100% also triggers
        // a screen-pulse on release. Overcharge (>1.0) keeps stacking droplets.
        if shared.state.rmb_charge < shared.state.eff_rmb_max_charge {
            shared.state.rmb_charge = math.min(
                shared.state.rmb_charge + shared.state.eff_rmb_charge_rate * dt,
                shared.state.eff_rmb_max_charge,
            )
        }
        accel_input_f := m.vec2_zero()
        if shared.state.key_w_down {accel_input_f.y+=1.0}; if shared.state.key_s_down {accel_input_f.y-=1.0}
        if shared.state.key_a_down {accel_input_f.x-=1.0}; if shared.state.key_d_down {accel_input_f.x+=1.0}
        if m.len_sq_vec2(accel_input_f) > 0.001 {accel_input_f=m.norm_vec2(accel_input_f)}
        if shared.state.is_dashing {
            if shared.state.dash_timer <= 0.0 {
                shared.state.is_dashing = false
                // Don't clear the trail here — let dash_flash's decay finish the afterimage anim.
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
            shared.state.player_vel = dash_direction * shared.state.eff_player_max_speed * shared.PLAYER_DASH_SPEED_MULT
            // Cache the dash axis so the post-dash stretch/echo visuals stay aligned to the
            // launch vector even after player_vel rotates back to whatever WASD is held now.
            shared.state.dash_direction = dash_direction
        } else {
            final_accel_f := accel_input_f * shared.PLAYER_ACCELERATION
            if shared.state.key_s_down && !shared.state.key_w_down && accel_input_f.y < -0.5 { final_accel_f *= shared.PLAYER_REVERSE_FACTOR }
            shared.state.player_vel += final_accel_f * dt
            damping_factor_f := math.max(0.0, 1.0 - shared.PLAYER_DAMPING*dt)
            shared.state.player_vel *= damping_factor_f
            max_speed := shared.state.eff_player_max_speed
            if m.len_sq_vec2(shared.state.player_vel) > max_speed * max_speed {
                shared.state.player_vel = m.norm_vec2(shared.state.player_vel) * max_speed
            }
        }


        shared.state.player_pos += shared.state.player_vel * dt

        // Tick the beam visual; the timer is set on full-charge fire below.
        if shared.state.rmb_beam_timer > 0.0 {
            shared.state.rmb_beam_timer = math.max(0.0, shared.state.rmb_beam_timer - dt)
        }

        rmb_pressed_this_frame_f := shared.state.rmb_down && !shared.state.previous_rmb_down
        if rmb_pressed_this_frame_f && shared.state.rmb_charge >= shared.RMB_MIN_FIRE_CHARGE {
            charge := shared.state.rmb_charge
            // Droplet swirl scaled to charge fraction. At 200% you get 2× the droplets.
            particle.spawn_swirling_charge_scaled(charge)
            // Beam + pulse only at fully-charged or overcharged release. The beam is the
            // headline directional weapon; the pulse remains the omnidirectional flash so
            // enemies behind the player still get hit.
            if charge >= shared.RMB_BEAM_THRESHOLD {
                particle.spawn_rmb_pulse(charge)
                aim := shared.state.player_aim_dir
                if m.len_sq_vec2(aim) < 0.0001 { aim = {0, 1} }
                shared.state.rmb_beam_origin = shared.state.player_pos
                shared.state.rmb_beam_dir    = m.norm_vec2(aim)
                shared.state.rmb_beam_total  = shared.RMB_BEAM_DURATION
                shared.state.rmb_beam_timer  = shared.RMB_BEAM_DURATION
                collision.apply_rmb_beam_damage(shared.state.rmb_beam_origin, shared.state.rmb_beam_dir)
            }
            shared.state.rmb_fire_flash = 1.0
            fmt.printf("RMB Fired at %.0f%% charge%s\n", charge * 100.0, charge >= shared.RMB_BEAM_THRESHOLD ? " (BEAM)" : "")
            shared.state.rmb_charge = 0.0
        }
        shared.state.previous_rmb_down = shared.state.rmb_down

        if shared.state.lmb_down && shared.state.lmb_cooldown_timer <= 0.0 {
            projectile.spawn_blackhole_projectile_weapon()
            shared.state.lmb_fire_flash = 1.0
            seek_result_f := ma.sound_seek_to_pcm_frame(&shared.state.lmb_sound, 0)
            if seek_result_f != .SUCCESS { fmt.eprintf("WARNING: Failed to seek lmb_sound to beginning. Error: %v\n", seek_result_f) }
            start_result_f := ma.sound_start(&shared.state.lmb_sound)
            if start_result_f != .SUCCESS { fmt.eprintf("WARNING: Failed to start lmb_sound. Error: %v\n", start_result_f) }
            shared.state.lmb_cooldown_timer = shared.state.eff_lmb_cooldown
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
        case .F: shared.state.key_f_down = true
        case ._1: if shared.state.game_mode == .SHOP { shared.state.shop_pick_1 = true }
        case ._2: if shared.state.game_mode == .SHOP { shared.state.shop_pick_2 = true }
        case ._3: if shared.state.game_mode == .SHOP { shared.state.shop_pick_3 = true }
        case .LEFT_SHIFT: shared.state.key_shift_down = true
        case .LEFT_CONTROL: shared.state.key_ctrl_down = true
        case .ESCAPE: sapp.request_quit()
    }
    case .KEY_UP: #partial switch event.key_code {
        case .W: shared.state.key_w_down = false
        case .S: shared.state.key_s_down = false
        case .A: shared.state.key_a_down = false
        case .D: shared.state.key_d_down = false
        case .F: shared.state.key_f_down = false
        case .LEFT_SHIFT: shared.state.key_shift_down = false
        case .LEFT_CONTROL: shared.state.key_ctrl_down = false
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

    half_width := shared.BOSS_LASER_WIDTH * 0.5 + player_radius
    cap_sq := half_width * half_width

    for i in 0..<shared.MAX_ENEMIES {
        enemy_laser_coll := &shared.state.enemies[i]
        if !enemy_laser_coll.active || enemy_laser_coll.type != .BOSS_CHROME_ORB || enemy_laser_coll.is_dying || enemy_laser_coll.is_growing {
            continue
        }

        laser_length := enemy_laser_coll.boss_current_laser_length
        if laser_length <= 0.0 { continue }
        laser_count := enemy_laser_coll.boss_laser_count
        if laser_count <= 0 { continue }

        // Each beam shares the orb's pivot, but its angular slot comes from the random permutation
        // computed at boss spawn. Slot s lives at angle (rotation + s * TAU/6).
        for k in 0..<laser_count {
            // Skip damage during the first half of fade-in (visual warning before the beam can hit).
            if k == laser_count - 1 && enemy_laser_coll.boss_laser_fade_in_timer > 0.5 { continue }

            slot := enemy_laser_coll.boss_laser_slot_order[k]
            beam_angle := enemy_laser_coll.rotation + f32(slot) * (m.TAU / 6.0)
            laser_direction_vec := m.vec2{math.cos(beam_angle), math.sin(beam_angle)}
            laser_origin_world := enemy_laser_coll.pos + laser_direction_vec * shared.ENEMY_BOSS_VISUAL_RADIUS

            rel := player_center - laser_origin_world
            local_y := m.dot_vec2(rel, laser_direction_vec)
            perp := m.vec2{-laser_direction_vec.y, laser_direction_vec.x}
            local_x := m.dot_vec2(rel, perp)

            hit := false
            if local_y >= 0.0 && local_y <= laser_length && math.abs(local_x) <= half_width {
                hit = true
            } else if m.dist_sq_vec2(player_center, laser_origin_world) < cap_sq {
                hit = true
            } else {
                end_world := laser_origin_world + laser_direction_vec * laser_length
                if m.dist_sq_vec2(player_center, end_world) < cap_sq { hit = true }
            }

            if hit {
                shared.state.player_hp -= shared.BOSS_LASER_DAMAGE
                shared.state.player_hp = math.max(shared.state.player_hp, 0)
                shared.state.player_invulnerable_timer = shared.state.eff_invul_duration / 2.0
                fmt.printf("Player hit by BOSS LASER (beam %d/%d, slot %d)! HP: %d/%d.\n", k+1, laser_count, slot, shared.state.player_hp, shared.state.player_max_hp)
                return
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

            base_dmg := shared.ENEMY_GRUNT_DAMAGE_VALUE
            if enemy_pe_coll.type == .SLOWBOY && shared.SlowboyState(enemy_pe_coll.ai_state) == .CHARGE {
                base_dmg = shared.SLOWBOY_ATTACK_DAMAGE
                fmt.printf("Player hit by SLOWBOY CHARGE!\n")
                enemy_pe_coll.vel = {0, 0}
                // End the charge early — counts as recover so it doesn't keep tracking through the player.
                enemy_pe_coll.ai_state = i32(shared.SlowboyState.RECOVER)
                enemy_pe_coll.ai_state_timer = shared.SLOWBOY_RECOVER_DURATION
                enemy_pe_coll.ai_state_total = shared.SLOWBOY_RECOVER_DURATION
            } else if enemy_pe_coll.type == .BOSS_CHROME_ORB {
                fmt.printf("Player hit by BOSS BODY!\n")
            }

            // Elite scaling: silver/gold deal more damage on contact.
            scaled := int(math.round(f32(base_dmg) * enemy_pe_coll.dmg_mult))
            if scaled < 1 { scaled = 1 }
            shared.state.player_hp -= scaled
            shared.state.player_hp = math.max(shared.state.player_hp, 0)
            shared.state.player_invulnerable_timer = shared.state.eff_invul_duration
            fmt.printf("Player hit by %v (tier %d, dmg %d)! HP: %d/%d. Invul %.2fs\n", enemy_pe_coll.type, enemy_pe_coll.enemy_tier, scaled, shared.state.player_hp, shared.state.player_max_hp, shared.state.player_invulnerable_timer)
            break
        }
    }
}
