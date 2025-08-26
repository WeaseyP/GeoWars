package main

import m "../math"
import "core:math"
import "core:fmt"
import ma "../miniaudio"
import sapp "../sokol/app"
import "base:runtime"



update_player :: proc(dt: f32) {
    if state.player_hp > 0 {
        
        if state.dash_timer <= 0.0 && state.is_dashing {
            state.is_dashing = false;
        }

        if state.key_shift_down && !state.is_dashing && state.dash_cooldown_timer <= 0.0 {
            state.is_dashing = true;
            state.dash_timer = PLAYER_DASH_DURATION;
            state.dash_cooldown_timer = PLAYER_DASH_COOLDOWN;
            state.player_invulnerable_timer = math.max(state.player_invulnerable_timer, PLAYER_DASH_DURATION);
            state.player_dash_trail_count = 0; // Reset on new dash
            state.dash_trail_spawn_timer = 0.0;
            fmt.printf("Player DASH!\n");
        }


         if state.current_rmb_ammo_charges < MAX_RMB_AMMO_CHARGES {
             state.rmb_ammo_regen_timer -= dt;
             if state.rmb_ammo_regen_timer <= 0.0 {
                 spawn_visual_ammo_charge_particles(state.current_rmb_ammo_charges);
                 state.current_rmb_ammo_charges += 1;
                 state.rmb_ammo_regen_timer = RMB_AMMO_REGEN_INTERVAL; 
                 fmt.printf("RMB Ammo Charge Regenerated! Current: %d/%d\n", state.current_rmb_ammo_charges, MAX_RMB_AMMO_CHARGES);
             }
         }
        accel_input_f := m.vec2_zero(); 
        if state.key_w_down {accel_input_f.y+=1.0}; if state.key_s_down {accel_input_f.y-=1.0}; 
        if state.key_a_down {accel_input_f.x-=1.0}; if state.key_d_down {accel_input_f.x+=1.0};  
        if m.len_sq_vec2(accel_input_f) > 0.001 {accel_input_f=m.norm_vec2(accel_input_f)}; 
        if state.is_dashing {
            if state.dash_timer <= 0.0 {
                state.is_dashing = false;
                state.player_dash_trail_count = 0; // Clear trails when dash ends
            } else {
                // Spawn trail points periodically during the dash
                state.dash_trail_spawn_timer -= dt;
                if state.dash_trail_spawn_timer <= 0.0 {
                    state.dash_trail_spawn_timer = PLAYER_DASH_TRAIL_SPAWN_RATE;

                    // --- START FIX ---
                    // Shift existing trail positions
                    for i := PLAYER_DASH_TRAIL_LENGTH - 1; i > 0; i -= 1 {
                        state.player_dash_traiL_pos[i] = state.player_dash_traiL_pos[i-1];
                    }
                    // Add new position at the front
                    state.player_dash_traiL_pos[0] = state.player_pos;
                    // --- END FIX ---
                    
                    // Increment count, but don't exceed max length
                    if state.player_dash_trail_count < PLAYER_DASH_TRAIL_LENGTH {
                        state.player_dash_trail_count += 1;
                    }
                }
            }
            dash_direction := accel_input_f;
            if m.len_sq_vec2(dash_direction) < 0.1 && m.len_sq_vec2(state.player_vel) > 0.1 {
                dash_direction = m.norm_vec2(state.player_vel);
            } else if m.len_sq_vec2(dash_direction) < 0.1 {
                dash_direction = {0, 1}; // Default dash forward if stationary with no input
            }
            state.player_vel = dash_direction * PLAYER_MAX_SPEED * PLAYER_DASH_SPEED_MULT;
        } else {
            // Normal movement logic
            final_accel_f := accel_input_f*PLAYER_ACCELERATION; // Renamed
            if state.key_s_down && !state.key_w_down && accel_input_f.y < -0.5 { final_accel_f *= PLAYER_REVERSE_FACTOR };
            state.player_vel += final_accel_f*dt; 
            damping_factor_f := math.max(0.0, 1.0-PLAYER_DAMPING*dt); // Renamed
            state.player_vel *= damping_factor_f; 
            if m.len_sq_vec2(state.player_vel) > f32(PLAYER_MAX_SPEED*PLAYER_MAX_SPEED) { state.player_vel=m.norm_vec2(state.player_vel)*PLAYER_MAX_SPEED }; 
        }


        state.player_pos += state.player_vel*dt;

        rmb_pressed_this_frame_f := state.rmb_down && !state.previous_rmb_down;
        if rmb_pressed_this_frame_f && state.current_rmb_ammo_charges > 0 {
            remove_visual_ammo_charge_particles(state.current_rmb_ammo_charges - 1); 
        }
        if rmb_pressed_this_frame_f && state.rmb_cooldown_timer <= 0.0 { 
            if state.current_rmb_ammo_charges > 0 {
                state.current_rmb_ammo_charges -= 1;
                spawn_swirling_charge(); 
                fmt.printf("RMB Fired! Ammo Remaining: %d/%d\n", state.current_rmb_ammo_charges, MAX_RMB_AMMO_CHARGES);
                if BLACKHOLE_COOLDOWN_DURATION > 0.0 { state.rmb_cooldown_timer=BLACKHOLE_COOLDOWN_DURATION; } 
            } else {
                fmt.printf("RMB - NO AMMO! (Charges: %d/%d)\n", state.current_rmb_ammo_charges, MAX_RMB_AMMO_CHARGES);
            }
        }; 
        state.previous_rmb_down=state.rmb_down;

        if state.lmb_down && state.lmb_cooldown_timer <= 0.0 { 
            spawn_blackhole_projectile_weapon();
            seek_result_f := ma.sound_seek_to_pcm_frame(&state.lmb_sound, 0) // Renamed
            if seek_result_f != .SUCCESS { fmt.eprintf("WARNING: Failed to seek lmb_sound to beginning. Error: %v\n", seek_result_f) }
            start_result_f := ma.sound_start(&state.lmb_sound) // Renamed
            if start_result_f != .SUCCESS { fmt.eprintf("WARNING: Failed to start lmb_sound. Error: %v\n", start_result_f) }
            state.lmb_cooldown_timer = PROJECTILE_BLACKHOLE_COOLDOWN;
        }
        state.previous_lmb_down = state.lmb_down;
    } else {
        state.player_vel = {0,0}; 
        if !state.player_defeated_message_shown {
            fmt.printf("--- PLAYER DEFEATED ---\n");
            state.player_defeated_message_shown = true;
        }
    }
}

handle_player_input :: proc(event: ^sapp.Event) {
    #partial switch event.type {
    case .KEY_DOWN: #partial switch event.key_code { 
        case .W: state.key_w_down=true; 
        case .S: state.key_s_down=true; 
        case .A: state.key_a_down=true; 
        case .D: state.key_d_down=true; 
        case .LEFT_SHIFT: state.key_shift_down = true; // <<< NEW
        case .ESCAPE: sapp.request_quit(); 
    }
    case .KEY_UP: #partial switch event.key_code { 
        case .W: state.key_w_down=false; 
        case .S: state.key_s_down=false; 
        case .A: state.key_a_down=false; 
        case .D: state.key_d_down=false; 
        case .LEFT_SHIFT: state.key_shift_down = false; // <<< NEW
    }
    case .MOUSE_DOWN: 
        if event.mouse_button == .RIGHT { state.rmb_down = true }
        if event.mouse_button == .LEFT  { state.lmb_down = true }
    case .MOUSE_UP: 
        if event.mouse_button == .RIGHT { state.rmb_down = false }
        if event.mouse_button == .LEFT  { state.lmb_down = false }
    case .MOUSE_MOVE: 
        state.mouse_screen_pos = {event.mouse_x, event.mouse_y}
    }
}

check_player_boss_laser_collision :: proc() {
    context = runtime.default_context()
    if state.player_hp <= 0 || state.player_invulnerable_timer > 0.0 { return }

    player_center := state.player_pos
    player_radius : f32 = PLAYER_CORE_WORLD_RADIUS

    for i in 0..<MAX_ENEMIES {
        enemy_laser_coll := &state.enemies[i] 
        if !enemy_laser_coll.active || enemy_laser_coll.type != .BOSS_CHROME_ORB || enemy_laser_coll.is_dying || enemy_laser_coll.is_growing {
            continue 
        }

        // Constants from shader for coordinate space understanding
        shader_uv_sphere_radius          : f32 = 0.45; // Radius of main sphere in shader's p_scaled_uv space
        shader_black_circle_orbit_factor : f32 = 0.6;  // Black circle orbits at 0.6 * main sphere's p_scaled_uv radius

        // enemy_laser_coll.current_size is the base world size of the boss entity (e.g., ENEMY_BOSS_CHROME_ORB_SCALE)
        // In the shader, 1 unit in p_scaled_uv space corresponds to 'enemy_laser_coll.current_size' world units.
        world_radius_of_main_sphere_visual := enemy_laser_coll.current_size * shader_uv_sphere_radius;
        world_orbit_radius_for_black_circle := world_radius_of_main_sphere_visual * shader_black_circle_orbit_factor;

        boss_facing_direction := m.norm_vec2(m.vec2{math.cos(enemy_laser_coll.rotation), math.sin(enemy_laser_coll.rotation)});
        black_circle_world_center := enemy_laser_coll.pos + boss_facing_direction * world_orbit_radius_for_black_circle;

        laser_origin_world := black_circle_world_center; // Laser originates from the black circle's center
        laser_direction_vec := boss_facing_direction;    // Laser fires in the boss's facing direction

        vec_to_player_from_origin := player_center - laser_origin_world;
            
        player_local_y := m.dot_vec2(vec_to_player_from_origin, laser_direction_vec); // Distance along laser axis
        laser_perpendicular_vec := m.vec2{-laser_direction_vec.y, laser_direction_vec.x};
        player_local_x := m.dot_vec2(vec_to_player_from_origin, laser_perpendicular_vec); // Perpendicular distance from laser axis


        // Check collision with the laser beam segment (approximated as a rectangle + end caps)
        // BOSS_LASER_LENGTH and BOSS_LASER_WIDTH are world units
        if player_local_y >= -player_radius && player_local_y <= (BOSS_LASER_LENGTH + player_radius) && 
           math.abs(player_local_x) <= (BOSS_LASER_WIDTH / 2.0 + player_radius) {            

            // More precise check for rectangle body of the laser
            if player_local_y > 0 && player_local_y < BOSS_LASER_LENGTH && 
               math.abs(player_local_x) < (BOSS_LASER_WIDTH / 2.0 + player_radius) {
                // Collision with laser body
                state.player_hp -= BOSS_LASER_DAMAGE
                state.player_hp = math.max(state.player_hp, 0)
                state.player_invulnerable_timer = PLAYER_INVULNERABILITY_DURATION / 2.0 
                fmt.printf("Player hit by BOSS LASER (Body)! HP: %d/%d. Invulnerable for %.2fs\n", state.player_hp, state.player_max_hp, state.player_invulnerable_timer)
                // TODO: Specific sound for player getting hit by laser
                return 
            } else { // Check end caps (circles at laser_origin_world and laser_origin_world + direction * length)
                cap_radius_for_check_sq := (BOSS_LASER_WIDTH / 2.0 + player_radius) * (BOSS_LASER_WIDTH / 2.0 + player_radius);
                
                // Check cap at laser origin
                if m.dist_sq_vec2(player_center, laser_origin_world) < cap_radius_for_check_sq {
                    state.player_hp -= BOSS_LASER_DAMAGE
                    state.player_hp = math.max(state.player_hp, 0)
                    state.player_invulnerable_timer = PLAYER_INVULNERABILITY_DURATION / 2.0
                    fmt.printf("Player hit by BOSS LASER (Origin Cap)! HP: %d/%d. Invulnerable for %.2fs\n", state.player_hp, state.player_max_hp, state.player_invulnerable_timer)
                    return
                }
                
                // Check cap at laser end
                laser_end_world := laser_origin_world + laser_direction_vec * BOSS_LASER_LENGTH;
                if m.dist_sq_vec2(player_center, laser_end_world) < cap_radius_for_check_sq {
                     state.player_hp -= BOSS_LASER_DAMAGE
                    state.player_hp = math.max(state.player_hp, 0)
                    state.player_invulnerable_timer = PLAYER_INVULNERABILITY_DURATION / 2.0
                    fmt.printf("Player hit by BOSS LASER (End Cap)! HP: %d/%d. Invulnerable for %.2fs\n", state.player_hp, state.player_max_hp, state.player_invulnerable_timer)
                    return
                }
            }
        }
    }
}

check_player_enemy_collisions :: proc() {
    context = runtime.default_context()
    if state.player_hp <= 0 || state.player_invulnerable_timer > 0.0 { return }
    player_radius_pe_coll := f32(PLAYER_CORE_WORLD_RADIUS) // Renamed
    for i in 0..<MAX_ENEMIES {
        enemy_pe_coll := &state.enemies[i] // Renamed
        if !enemy_pe_coll.active || enemy_pe_coll.is_growing || enemy_pe_coll.is_dying { continue } // Ignore dying enemies too
        
        enemy_radius_pe_coll := enemy_pe_coll.current_size * 0.5 // Renamed
        if enemy_radius_pe_coll <= 0.001 { continue }
        dist_sq_pe_coll := m.dist_sq_vec2(state.player_pos, enemy_pe_coll.pos) // Renamed
        radii_sum_pe_coll := player_radius_pe_coll + enemy_radius_pe_coll // Renamed
        radii_sum_sq_pe_coll := radii_sum_pe_coll * radii_sum_pe_coll // Renamed
        if dist_sq_pe_coll < radii_sum_sq_pe_coll {
            if enemy_pe_coll.hp <= 0 { continue } 
            
            damage_to_player := ENEMY_GRUNT_DAMAGE_VALUE; // Default
            if enemy_pe_coll.type == .SLOWBOY && enemy_pe_coll.is_charging_attack {
                damage_to_player = SLOWBOY_ATTACK_DAMAGE;
                 fmt.printf("Player hit by SLOWBOY CHARGE!\n");
                 // Optionally, end charge state for slowboy
                 enemy_pe_coll.is_charging_attack = false;
                 enemy_pe_coll.vel = {0,0}; // Stop it
            } else if enemy_pe_coll.type == .BOSS_CHROME_ORB {
                 // Boss collision damage could be different, or rely only on laser
                 // For now, let boss body collision also do grunt damage.
                 fmt.printf("Player hit by BOSS BODY!\n");
            }


            state.player_hp -= damage_to_player 
            state.player_hp = math.max(state.player_hp, 0) 
            state.player_invulnerable_timer = PLAYER_INVULNERABILITY_DURATION
            fmt.printf("Player hit by ENEMY! HP: %d/%d. Invulnerable for %.2fs\n", state.player_hp, state.player_max_hp, state.player_invulnerable_timer)
            // TODO: Specific sound for player getting hit
            break 
        }
    }
}
