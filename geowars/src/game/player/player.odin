package player

import "core:math"
import "core:fmt"
import m "../../vendor/math"
import ma "../../vendor/miniaudio"
import shared "../../shared"
import input "../../core/input"
import projectile "../../game/projectile"
import particle "../../game/particle"

// Constants needed for update logic
PLAYER_MAX_SPEED          :: 7.0
PLAYER_ACCELERATION       :: 15.0
PLAYER_DAMPING            :: 2.5
PLAYER_REVERSE_FACTOR     :: 0.5
PLAYER_DASH_SPEED_MULT    :: 1.5
PLAYER_DASH_DURATION      :: 0.15
PLAYER_DASH_COOLDOWN      :: 3.0
PLAYER_DASH_TRAIL_SPAWN_RATE :: 0.035
MAX_RMB_AMMO_CHARGES      :: 2
RMB_AMMO_REGEN_INTERVAL   :: 10.0
BLACKHOLE_COOLDOWN_DURATION :: 1.0
PROJECTILE_BLACKHOLE_COOLDOWN :: 0.25

update_player :: proc(game_state: ^shared.GameState, dt: f32, input_mgr: ^input.InputManager, proj_mgr: ^projectile.ProjectileManager) {
    p := &game_state.player

    if p.hp > 0 {
        // --- Dash Logic ---
        if p.dash_timer <= 0.0 && p.is_dashing {
            p.is_dashing = false
        }

        if input_mgr.key_shift_down && !p.is_dashing && p.dash_cooldown_timer <= 0.0 {
            p.is_dashing = true
            p.dash_timer = PLAYER_DASH_DURATION
            p.dash_cooldown_timer = PLAYER_DASH_COOLDOWN
            p.invulnerable_timer = math.max(p.invulnerable_timer, PLAYER_DASH_DURATION)
            p.dash_trail_count = 0
            p.dash_trail_spawn_timer = 0.0
            fmt.printf("Player DASH!\n")
        }

        // --- Ammo Regen ---
        if p.current_rmb_ammo_charges < MAX_RMB_AMMO_CHARGES {
            p.rmb_ammo_regen_timer -= dt
            if p.rmb_ammo_regen_timer <= 0.0 {
                particle.spawn_visual_ammo_charge_particles(game_state, p.current_rmb_ammo_charges)
                p.current_rmb_ammo_charges += 1
                p.rmb_ammo_regen_timer = RMB_AMMO_REGEN_INTERVAL
                fmt.printf("RMB Ammo Charge Regenerated! Current: %d/%d\n", p.current_rmb_ammo_charges, MAX_RMB_AMMO_CHARGES)
            }
        }

        // --- Movement ---
        accel_input := input.get_movement_vector(input_mgr)

        if p.is_dashing {
            if p.dash_timer <= 0.0 {
                p.is_dashing = false
                p.dash_trail_count = 0
            } else {
                p.dash_trail_spawn_timer -= dt
                if p.dash_trail_spawn_timer <= 0.0 {
                    p.dash_trail_spawn_timer = PLAYER_DASH_TRAIL_SPAWN_RATE
                    // Shift trail
                    for i := shared.PLAYER_DASH_TRAIL_LENGTH - 1; i > 0; i -= 1 {
                        p.dash_trail_pos[i] = p.dash_trail_pos[i-1]
                    }
                    p.dash_trail_pos[0] = p.pos
                    if p.dash_trail_count < shared.PLAYER_DASH_TRAIL_LENGTH {
                        p.dash_trail_count += 1
                    }
                }
            }

            dash_direction := accel_input
            if m.len_sq_vec2(dash_direction) < 0.1 && m.len_sq_vec2(p.vel) > 0.1 {
                dash_direction = m.norm_vec2(p.vel)
            } else if m.len_sq_vec2(dash_direction) < 0.1 {
                dash_direction = {0, 1}
            }
            p.vel = dash_direction * PLAYER_MAX_SPEED * PLAYER_DASH_SPEED_MULT
        } else {
            // Normal movement
            final_accel := accel_input * PLAYER_ACCELERATION
            // Reverse dampening if moving opposite to input
            if input_mgr.key_s_down && !input_mgr.key_w_down && accel_input.y < -0.5 {
                final_accel *= PLAYER_REVERSE_FACTOR
            }

            p.vel += final_accel * dt
            damping_factor := math.max(0.0, 1.0 - PLAYER_DAMPING * dt)
            p.vel *= damping_factor

            if m.len_sq_vec2(p.vel) > f32(PLAYER_MAX_SPEED * PLAYER_MAX_SPEED) {
                p.vel = m.norm_vec2(p.vel) * PLAYER_MAX_SPEED
            }
        }

        p.pos += p.vel * dt

        // --- Shooting (RMB) ---
        rmb_pressed := input.rmb_pressed(input_mgr)
        if rmb_pressed && p.current_rmb_ammo_charges > 0 {
            particle.remove_visual_ammo_charge_particles(game_state, p.current_rmb_ammo_charges - 1)
        }

        if rmb_pressed && p.rmb_cooldown_timer <= 0.0 {
            if p.current_rmb_ammo_charges > 0 {
                p.current_rmb_ammo_charges -= 1
                particle.spawn_swirling_charge(game_state)
                fmt.printf("RMB Fired! Ammo Remaining: %d/%d\n", p.current_rmb_ammo_charges, MAX_RMB_AMMO_CHARGES)
                if BLACKHOLE_COOLDOWN_DURATION > 0.0 {
                    p.rmb_cooldown_timer = BLACKHOLE_COOLDOWN_DURATION
                }
            } else {
                fmt.printf("RMB - NO AMMO! (Charges: %d/%d)\n", p.current_rmb_ammo_charges, MAX_RMB_AMMO_CHARGES)
            }
        }

        // --- Shooting (LMB) ---
        if input_mgr.lmb_down && p.lmb_cooldown_timer <= 0.0 {
            // Calculate direction
            target_pos := input_mgr.mouse_screen_pos // This is screen pos, need world pos.
            // Wait, get_mouse_world_pos logic was in geowars.odin.
            // We need to convert screen to world. We can use input_mgr.mouse_screen_pos
            // but we need resolution and ortho height.
            // Assuming we pass those or calculate them.
            // For now, let's assume we can get it or pass it.
            // Actually, spawn_blackhole in projectile_manager takes pos and vel.
            // We calculate vel here.
            
            // We need to calculate world pos of mouse.
            // Let's defer that calculation to a helper or just do it if we have access to sapp/constants.
            // ORTHO_HEIGHT is in shared? No, it was in constants.odin.
            // I should have moved constants to shared. I did not move ORTHO_HEIGHT to shared yet.
            // I'll assume 1.5 for now or move it.

            // Re-implementing mouse world pos logic here requires sapp imports.
            // I will implement a helper here.

            spawn_pos := p.pos
            target_world := get_mouse_world_pos(input_mgr.mouse_screen_pos)

            direction := target_world - spawn_pos
            if m.len_sq_vec2(direction) > 0.0001 {
                direction = m.norm_vec2(direction)
            } else {
                if m.len_sq_vec2(p.vel) > 0.001 {
                    direction = m.norm_vec2(p.vel)
                } else {
                    direction = {0, 1}
                }
            }

            vel := direction * projectile.PROJECTILE_BLACKHOLE_INITIAL_SPEED
            projectile.spawn_blackhole(proj_mgr, spawn_pos, vel)

            ma.sound_seek_to_pcm_frame(&game_state.lmb_sound, 0)
            ma.sound_start(&game_state.lmb_sound)

            p.lmb_cooldown_timer = PROJECTILE_BLACKHOLE_COOLDOWN
        }

    } else {
        p.vel = {0,0}
        if !p.defeated_message_shown {
            fmt.printf("--- PLAYER DEFEATED ---\n")
            p.defeated_message_shown = true
        }
    }
}

// Helper
import sapp "../../vendor/sokol/app"
ORTHO_HEIGHT :: 1.5 // Duplicate for now until shared constants

get_mouse_world_pos :: proc(screen_pos: m.vec2) -> m.vec2 {
    width := sapp.widthf()
    height := sapp.heightf()
    ndc_x := (2.0 * screen_pos.x / width) - 1.0
    ndc_y := 1.0 - (2.0 * screen_pos.y / height)
    aspect := width / height
    ortho_width := ORTHO_HEIGHT * aspect
    return {ndc_x * ortho_width, ndc_y * ORTHO_HEIGHT}
}
