package main
import m "../../vendor/math"

import "base:runtime"
import "core:fmt"
import rand "core:math/rand"
import "core:math"
import shared "../../shared"
import sapp "../../vendor/sokol/app"




// --- Enemy System ---
emit_enemy :: proc(enemy_data: shared.Enemy) {
    context = runtime.default_context()
    idx_to_write_en := state.next_enemy_index // Renamed
    state.enemies[idx_to_write_en] = enemy_data       
    state.enemies[idx_to_write_en].active = true       
    state.next_enemy_index = (state.next_enemy_index + 1) % MAX_ENEMIES
}

spawn_enemy :: proc(current_ortho_width: f32, current_ortho_height: f32, player_pos: m.vec2, type_to_spawn: shared.EnemyType) { 
    context = runtime.default_context()
    start_pos_en: m.vec2 // Renamed
    valid_spawn_found_en := false // Renamed

    // Specific handling for BOSS_CHROME_ORB spawn position
    if type_to_spawn == .BOSS_CHROME_ORB {
        start_pos_en.x = 0.0; 
        start_pos_en.y = ENEMY_BOSS_SPAWN_Y_OFFSET; 
        valid_spawn_found_en = true; 
    } else { // Standard border spawning for other enemies
        for attempt_en in 0..<ENEMY_MAX_SPAWN_ATTEMPTS { // Renamed
            side_en := rand.int31() % 4 // Renamed
            random_depth_en := rand.float32() * ENEMY_SPAWN_BORDER_FRACTION // Renamed
            switch side_en {
            case 0: start_pos_en.y = current_ortho_height * (1.0 - random_depth_en); start_pos_en.x = (rand.float32() * 2.0 - 1.0) * current_ortho_width 
            case 1: start_pos_en.y = -current_ortho_height * (1.0 - random_depth_en); start_pos_en.x = (rand.float32() * 2.0 - 1.0) * current_ortho_width
            case 2: start_pos_en.x = -current_ortho_width * (1.0 - random_depth_en); start_pos_en.y = (rand.float32() * 2.0 - 1.0) * current_ortho_height
            case 3: start_pos_en.x = current_ortho_width * (1.0 - random_depth_en); start_pos_en.y = (rand.float32() * 2.0 - 1.0) * current_ortho_height
            }
            dist_sq_to_player_en := m.len_sq_vec2(start_pos_en - player_pos) // Renamed
            if dist_sq_to_player_en >= ENEMY_MIN_SPAWN_DIST_FROM_PLAYER_SQ { valid_spawn_found_en = true; break; }
        }
        if !valid_spawn_found_en {
            fmt.printf("spawn_enemy: WARNING - Could not find a suitable spawn point after %d attempts. Using fallback.\n", ENEMY_MAX_SPAWN_ATTEMPTS)
            start_pos_en.y = current_ortho_height * (1.0 - ENEMY_SPAWN_BORDER_FRACTION * 0.5) 
            start_pos_en.x = -current_ortho_width * (1.0 - ENEMY_SPAWN_BORDER_FRACTION * 0.5) 
        }
    }

    start_vel_en: m.vec2 = {0.0, 0.0} // Renamed
    initial_wander_angle_en := rand.float32() * m.TAU // Renamed
    initial_wander_vector_en := m.angle_to_vec2(initial_wander_angle_en) // Renamed

    enemy_to_spawn: shared.Enemy
    
    target_world_size: f32;
    initial_hp: i32;
    death_anim_dur: f32;
    enemy_color_val: m.vec4; // Renamed
    enemy_angular_vel: f32;

    switch type_to_spawn {
        case .GRUNT:
            base_grunt_rgb_en := m.vec3{0.9, 0.1, 0.7} 
            enemy_color_val = m.vec4{base_grunt_rgb_en.r, base_grunt_rgb_en.g, base_grunt_rgb_en.b, ENEMY_BASE_ALPHA}
            target_world_size = ENEMY_GRUNT_SCALE;
            initial_hp = ENEMY_GRUNT_MAX_HP;
            death_anim_dur = GRUNT_DEATH_ANIM_DURATION;
            enemy_angular_vel = (rand.float32() * 2.0 - 1.0) * ENEMY_MAX_ANGULAR_SPEED;
        case .SLOWBOY:
            enemy_color_val = m.vec4{0.3, 0.7, 0.9, ENEMY_BASE_ALPHA}
            target_world_size = ENEMY_SLOWBOY_BASE_SCALE; 
            initial_hp = ENEMY_SLOWBOY_MAX_HP;
            death_anim_dur = SLOWBOY_DEATH_ANIM_DURATION;
            enemy_angular_vel = (rand.float32() * 2.0 - 1.0) * ENEMY_MAX_ANGULAR_SPEED * 0.5;
        case .BOSS_CHROME_ORB:
            enemy_color_val = m.vec4{0.75, 0.75, 0.8, ENEMY_BASE_ALPHA};
            target_world_size = ENEMY_BOSS_CHROME_ORB_SCALE;
            initial_hp = ENEMY_BOSS_CHROME_ORB_MAX_HP;
            death_anim_dur = BOSS_DEATH_ANIM_DURATION; 
            start_vel_en = {ENEMY_BOSS_HORIZONTAL_SPEED, 0.0}; 
            enemy_angular_vel = 0.0; // Boss aiming is based on player pos, not fixed angular_vel for body
        case .WEAVER:
            enemy_color_val = m.vec4{0.1, 0.9, 0.3, ENEMY_BASE_ALPHA} // Green
            target_world_size = 0.2 // Slightly larger than grunt
            initial_hp = 3
            death_anim_dur = ENEMY_DEATH_ANIM_DURATION
            enemy_angular_vel = 0.0 // Oscillation logic in update, no rotation
        case .GRAVITRON:
             enemy_color_val = m.vec4{0.2, 0.2, 0.9, ENEMY_BASE_ALPHA} // Blue
             target_world_size = 0.4 // Large
             initial_hp = 20 // High HP
             death_anim_dur = ENEMY_DEATH_ANIM_DURATION
             enemy_angular_vel = 0.5 // Slow rotation
        case .TRACER:
            enemy_color_val = m.vec4{0.9, 0.5, 0.1, ENEMY_BASE_ALPHA} // Orange
            target_world_size = 0.15 // Small/Sleek
            initial_hp = 2
            death_anim_dur = ENEMY_DEATH_ANIM_DURATION
            enemy_angular_vel = 0.0 // Steering logic controls rotation
        case: 
            fmt.printf("spawn_enemy: ERROR - Unknown type_to_spawn: %v\n", type_to_spawn);
            return; 
    }

    enemy_to_spawn = shared.Enemy {
        pos = start_pos_en, vel = start_vel_en, color = enemy_color_val, 
        target_size = target_world_size, 
        current_size = target_world_size * ENEMY_INITIAL_SCALE_FACTOR, 
        grow_timer = ENEMY_GROW_DURATION, is_growing = true,                                                 
        rotation = rand.float32() * m.TAU, 
        angular_vel = enemy_angular_vel,
        hp = initial_hp, type = type_to_spawn, active = false, 
        current_wander_vector = initial_wander_vector_en,
        wander_timer = rand.float32_range(0.0, ENEMY_WANDER_DIRECTION_CHANGE_INTERVAL),
        is_dying = false, dying_timer = 0.0, death_rect_offset = 0.0,
        death_anim_max_duration = death_anim_dur,
        boss_move_direction = 1.0, 
        boss_detection_print_cooldown = 0.0,
        is_winding_up_attack = false, attack_windup_timer = 0.0,
        has_locked_attack_trajectory = false, attack_charge_target_pos = {0,0},
        is_charging_attack = false, attack_charge_start_pos = {0,0},
    };
    
    emit_enemy(enemy_to_spawn)
}

update_and_instance_enemies :: proc(dt: f32) -> int {
    context = runtime.default_context()
    live_enemy_count := 0
    player_pos_uie := state.player_pos 

    for i in 0..<MAX_ENEMIES {
        if !state.enemies[i].active { continue }
        enemy_uie := &state.enemies[i] 

        has_updated_pos_for_charge_bounce_uie := false; 
        
        effect_params_x_uie: f32 = 0.0; // is_dying flag
        effect_params_y_uie: f32 = 0.0; // dying_rect_offset OR is_winding_up_attack flag for slowboy
        effect_params_z_uie: f32 = 1.0; // Various: part_scale_mult, glow_canvas_sf, windup_timer, vision_width
        effect_params_w_uie: f32 = 1.0; // Various: dying_alpha, windup_total_duration, vision_range

        if enemy_uie.is_dying {
            effect_params_x_uie = 1.0; 
            effect_params_y_uie = enemy_uie.death_rect_offset;
            enemy_uie.dying_timer -= dt;
            enemy_uie.death_rect_offset += ENEMY_DEATH_RECT_SEPARATION_SPEED * dt;
            
            if enemy_uie.dying_timer <= 0.0 { enemy_uie.active = false; continue; }

            progress_raw_uie: f32 
            if enemy_uie.death_anim_max_duration > 0.0 { 
                progress_raw_uie = 1.0 - math.clamp(enemy_uie.dying_timer / enemy_uie.death_anim_max_duration, 0.0, 1.0);
            } else { progress_raw_uie = 0.0;  }
            
            effect_params_w_uie = 1.0 - progress_raw_uie; // Overall alpha multiplier for dying effect
            
            if enemy_uie.type == .GRUNT {
                 eased_progress_for_scale_uie := math.pow(progress_raw_uie, 2.5); 
                 initial_part_uv_scale_uie : f32 = 1.0; 
                 final_part_uv_scale_uie : f32 = ENEMY_DEATH_RECT_FINAL_SCALE_FACTOR; 
                 effect_params_z_uie = m.lerp(initial_part_uv_scale_uie, final_part_uv_scale_uie, eased_progress_for_scale_uie);
            } else { // Slowboy, Boss don't use effect_params_z for part scaling in dying shader
                 effect_params_z_uie = 1.0; 
            }
            
            enemy_uie.current_size = f32(m.lerp(enemy_uie.target_size, enemy_uie.target_size * ENEMY_DEATH_RECT_FINAL_SCALE_FACTOR, progress_raw_uie)); // Use raw progress for size lerp
            } else if enemy_uie.type == .SLOWBOY && enemy_uie.is_winding_up_attack {
            effect_params_x_uie = 0.0; 
            effect_params_y_uie = 1.0; 
            effect_params_z_uie = enemy_uie.attack_windup_timer; 
            effect_params_w_uie = SLOWBOY_ATTACK_WINDUP_TOTAL_DURATION; 
            
            enemy_uie.attack_windup_timer -= dt;
            if enemy_uie.attack_windup_timer <= SLOWBOY_ATTACK_LOCKON_TIME_REMAINING && !enemy_uie.has_locked_attack_trajectory {
                enemy_uie.attack_charge_target_pos = player_pos_uie; 
                enemy_uie.has_locked_attack_trajectory = true;
            }
            if enemy_uie.attack_windup_timer <= 0.0 {
                enemy_uie.is_winding_up_attack = false;
                enemy_uie.is_charging_attack = true;
                enemy_uie.attack_charge_start_pos = enemy_uie.pos;
                charge_direction_vec_uie := enemy_uie.attack_charge_target_pos - enemy_uie.attack_charge_start_pos; 
                if m.len_sq_vec2(charge_direction_vec_uie) > 0.0001 { 
                    charge_direction_vec_uie = m.norm_vec2(charge_direction_vec_uie);
                } else { charge_direction_vec_uie = m.vec2{0, 1}; }
                enemy_uie.vel = charge_direction_vec_uie * PLAYER_MAX_SPEED * SLOWBOY_ATTACK_CHARGE_SPEED_FACTOR;
                enemy_uie.angular_vel = 0; 
            }
        
        } else if enemy_uie.is_growing {
            effect_params_x_uie = 0.0; 
            effect_params_y_uie = 0.0; 
            if enemy_uie.type == .SLOWBOY { effect_params_z_uie = ENEMY_SLOWBOY_GLOW_CANVAS_SF; } 
            else if enemy_uie.type == .BOSS_CHROME_ORB { 
                effect_params_z_uie = ENEMY_BOSS_VISION_RECT_WIDTH; 
                effect_params_w_uie = ENEMY_BOSS_VISION_RANGE;
            } else { effect_params_z_uie = 1.0; }
            // effect_params_w_uie remains 1.0 unless it's boss (set above)

            enemy_uie.grow_timer -= dt;
            if enemy_uie.grow_timer <= 0.0 {
                enemy_uie.current_size = enemy_uie.target_size;
                enemy_uie.is_growing = false;
                enemy_uie.grow_timer = 0.0;
                if enemy_uie.type == .BOSS_CHROME_ORB { // Start moving once growth is complete
                    enemy_uie.vel.x = ENEMY_BOSS_HORIZONTAL_SPEED * enemy_uie.boss_move_direction;
                    enemy_uie.vel.y = 0;
                }
            } else {
                progress_grow_uie := 1.0 - (enemy_uie.grow_timer / ENEMY_GROW_DURATION); 
                progress_grow_uie = math.clamp(progress_grow_uie, 0.0, 1.0); 
                initial_actual_size_uie := enemy_uie.target_size * ENEMY_INITIAL_SCALE_FACTOR; 
                enemy_uie.current_size = m.lerp(initial_actual_size_uie, enemy_uie.target_size, progress_grow_uie);
            }
            
            if enemy_uie.type != .BOSS_CHROME_ORB { 
                enemy_uie.rotation += enemy_uie.angular_vel * dt;
                enemy_uie.wander_timer -= dt;
                if enemy_uie.wander_timer <= 0.0 {
                    new_wander_angle_uie := rand.float32() * m.TAU; 
                    enemy_uie.current_wander_vector = m.angle_to_vec2(new_wander_angle_uie);
                    enemy_uie.wander_timer = ENEMY_WANDER_DIRECTION_CHANGE_INTERVAL + rand.float32_range(-0.2, 0.2);
                }
                direction_to_player_strict_growing_uie := player_pos_uie - enemy_uie.pos; 
                final_direction_growing_uie := direction_to_player_strict_growing_uie; 
                dist_sq_to_player_growing_uie := m.len_sq_vec2(direction_to_player_strict_growing_uie); 
                if dist_sq_to_player_growing_uie > 0.001 {
                    normalized_strict_direction_growing_uie := m.norm_vec2(direction_to_player_strict_growing_uie); 
                    final_direction_growing_uie = normalized_strict_direction_growing_uie + (enemy_uie.current_wander_vector * ENEMY_WANDER_INFLUENCE);
                }
                current_speed_growing_uie : f32;
                if enemy_uie.type == .GRUNT { current_speed_growing_uie = ENEMY_GRUNT_SPEED; }
                else if enemy_uie.type == .SLOWBOY { current_speed_growing_uie = ENEMY_SLOWBOY_SPEED; }
                else { current_speed_growing_uie = 0.0; } 

                if dist_sq_to_player_growing_uie > 0.00001 && m.len_sq_vec2(final_direction_growing_uie) > 0.00001 {
                    normalized_final_direction_growing_uie := m.norm_vec2(final_direction_growing_uie); 
                    enemy_uie.vel = normalized_final_direction_growing_uie * current_speed_growing_uie;
                } else if m.len_sq_vec2(direction_to_player_strict_growing_uie) > 0.00001 {
                    enemy_uie.vel = m.norm_vec2(direction_to_player_strict_growing_uie) * current_speed_growing_uie;
                } else { enemy_uie.vel = m.vec2_zero(); }
            } else { // BOSS_CHROME_ORB specific logic during growth (aim, but don't move via wander/seek yet)
                 dir_to_player_boss_rot_uie := player_pos_uie - enemy_uie.pos;
                if m.len_sq_vec2(dir_to_player_boss_rot_uie) > 0.0001 {
                    enemy_uie.rotation = -m.PI / 2.0; // Aim straight down
                }
                enemy_uie.vel = {0,0}; 
            }

        } else { // Not dying, Not growing, (and for SlowBoy: not winding up attack)
            enemy_uie.current_size = enemy_uie.target_size;
            
            effect_params_x_uie = 0.0; 
            effect_params_y_uie = 0.0; 
            effect_params_z_uie = 1.0;
            effect_params_w_uie = 1.0;

            if enemy_uie.type == .BOSS_CHROME_ORB {
                effect_params_z_uie = ENEMY_BOSS_VISION_RECT_WIDTH; 
                effect_params_w_uie = ENEMY_BOSS_VISION_RANGE;    
                
                dir_to_player_boss_rot_uie := player_pos_uie - enemy_uie.pos; 
                if m.len_sq_vec2(dir_to_player_boss_rot_uie) > 0.0001 { 
                    enemy_uie.rotation = -m.PI / 2.0; // Aim straight down
                } 
                
                if enemy_uie.boss_detection_print_cooldown > 0 {
                    enemy_uie.boss_detection_print_cooldown -= dt;
                }
                // Boss horizontal movement
                aspect_ratio_uie := sapp.widthf() / sapp.heightf();
                current_ortho_width_uie := ORTHO_HEIGHT * aspect_ratio_uie;
                boss_half_width_uie := enemy_uie.current_size * 0.5;
                left_bound_uie := -current_ortho_width_uie + boss_half_width_uie + ENEMY_BOSS_SCREEN_PADDING;
                right_bound_uie := current_ortho_width_uie - boss_half_width_uie - ENEMY_BOSS_SCREEN_PADDING;

                enemy_uie.vel.y = 0; 
                if enemy_uie.vel.x == 0 { // Could happen if just finished growing
                     enemy_uie.vel.x = ENEMY_BOSS_HORIZONTAL_SPEED * enemy_uie.boss_move_direction;
                }
                if enemy_uie.pos.x >= right_bound_uie && enemy_uie.vel.x > 0 {
                    enemy_uie.pos.x = right_bound_uie; 
                    enemy_uie.vel.x = -ENEMY_BOSS_HORIZONTAL_SPEED;
                    enemy_uie.boss_move_direction = -1.0;
                } else if enemy_uie.pos.x <= left_bound_uie && enemy_uie.vel.x < 0 {
                    enemy_uie.pos.x = left_bound_uie; 
                    enemy_uie.vel.x = ENEMY_BOSS_HORIZONTAL_SPEED;
                    enemy_uie.boss_move_direction = 1.0;
                }
            } else if enemy_uie.type == .WEAVER {
                // Weaver: Maintains distance from player while oscillating perpendicular
                dist_to_player_vec := player_pos_uie - enemy_uie.pos;
                dist_sq := m.len_sq_vec2(dist_to_player_vec);
                target_dist :: 4.0 // "Maintains a specific distance (4.0)"
                target_dist_sq :: target_dist * target_dist;

                // Base movement: move towards or away to maintain distance
                desired_vel: m.vec2 = {0,0}
                if dist_sq > target_dist_sq + 0.1 {
                    desired_vel = m.norm_vec2(dist_to_player_vec) * ENEMY_GRUNT_SPEED // Approach
                } else if dist_sq < target_dist_sq - 0.1 {
                    desired_vel = m.norm_vec2(dist_to_player_vec) * -ENEMY_GRUNT_SPEED // Retreat
                }

                // Oscillation
                time_f := f32(sapp.frame_count()) / 60.0;
                freq :: 2.0
                amp :: 2.0

                // Perpendicular vector
                dir_norm := m.norm_vec2(dist_to_player_vec);
                perp_vec := m.vec2{-dir_norm.y, dir_norm.x};

                oscillation_offset := perp_vec * math.sin(time_f * freq) * amp;

                // Combine
                // Weaver logic in prompt: pos = center_line + perpendicular_vec * sin(time * freq) * amp
                // Since we are setting velocity, we should probably add this oscillation to the velocity or position directly.
                // Let's modify velocity to steer towards that target position.
                // Or simpler: just add the oscillation to the position (ignoring physics collisions for the oscillation part? No, better to do velocity).

                // Alternative interpretation: The Weaver strafes.
                enemy_uie.vel = desired_vel + (perp_vec * math.cos(time_f * freq) * amp); // derivative of sin is cos for velocity?
                // Let's stick to the prompt's position formula idea but adapt for velocity-based update:
                // Actually, the prompt says: "Behavior: Maintains a specific distance (4.0) from player while oscillating perpendicular to the direction vector."
                // "pos = center_line + perpendicular_vec * sin(time * freq) * amp"
                // This implies explicit position calculation.
                // However, we use `pos += vel * dt` later.
                // Let's set velocity to reach a dynamic target point.
                // Dynamic target = (point at distance 4.0 on line to player) + (perp offset)

                // Let's simplify: simple seek/flee for distance + strafe velocity
                strafe_vel := perp_vec * math.sin(time_f * freq) * amp;
                enemy_uie.vel = desired_vel + strafe_vel;

                // Visuals: Green Diamond (handled by instance_enemy_type = 3.0 and shader)
                enemy_uie.rotation += 2.0 * dt; // Spin

            } else if enemy_uie.type == .GRAVITRON {
                 // Gravitron: Slow movement, pulls projectiles
                 dir_to_player := player_pos_uie - enemy_uie.pos;
                 if m.len_sq_vec2(dir_to_player) > 0.001 {
                     enemy_uie.vel = m.norm_vec2(dir_to_player) * 0.5; // Very slow seek
                 }
                 enemy_uie.rotation += enemy_uie.angular_vel * dt;

                 // Projectile Pull Logic (needs access to projectiles, will do in separate loop or call)
                 // See "Implement Gravitron Logic" below or in `update_and_instance_enemies` loop?
                 // Since we are inside the enemy loop, we can't easily iterate projectiles here without passing them.
                 // We will handle the pull logic in a separate pass or outside this loop?
                 // Actually, checking "distance to all active Projectiles" implies iterating projectiles.
                 // Let's add a helper function `apply_gravitron_pull(gravitron_pos)` and call it here.
                 // But wait, `update_and_instance_enemies` doesn't know about projectiles.
                 // We should probably do this interaction in `frame()` or pass projectile list.
                 // For now, let's just do movement here. The pull logic is best done where we have access to both.
                 // (See step 4 of plan: "Add logic to pull Projectiles...").

            } else if enemy_uie.type == .TRACER {
                // Tracer: High speed, boid-like steering
                // Seek player
                dir_to_player := player_pos_uie - enemy_uie.pos;
                dist_sq := m.len_sq_vec2(dir_to_player);
                if dist_sq > 0.001 {
                    desired_dir := m.norm_vec2(dir_to_player);
                    current_dir := m.vec2{0,1}
                    if m.len_sq_vec2(enemy_uie.vel) > 0.001 {
                        current_dir = m.norm_vec2(enemy_uie.vel)
                    }

                    // Steer towards desired
                    steer_strength :: 2.0 * dt // Turn rate
                    new_dir := m.lerp(current_dir, desired_dir, steer_strength); // Rough steering
                    new_dir = m.norm_vec2(new_dir);

                    tracer_speed :: 4.0 // High speed
                    enemy_uie.vel = new_dir * tracer_speed;

                    // Rotate to face velocity
                    enemy_uie.rotation = math.atan2(enemy_uie.vel.y, enemy_uie.vel.x) - m.PI/2.0;
                }

            } else { // Grunt or SlowBoy (idle/moving, not charging/winding)
                enemy_uie.rotation += enemy_uie.angular_vel * dt;
                
                if enemy_uie.type == .SLOWBOY {
                     effect_params_z_uie = ENEMY_SLOWBOY_GLOW_CANVAS_SF; 
                     effect_params_w_uie = 1.0; 
                } else { // GRUNT
                    effect_params_z_uie = 1.0; 
                    effect_params_w_uie = 1.0; 
                }

                player_dist_sq_uie := m.dist_sq_vec2(enemy_uie.pos, player_pos_uie); 
                if enemy_uie.type == .SLOWBOY && player_dist_sq_uie < (SLOWBOY_ATTACK_DETECT_RANGE * SLOWBOY_ATTACK_DETECT_RANGE) {
                    // This SlowBoy is not currently charging, and not winding up, but IS in range to start windup
                    enemy_uie.is_winding_up_attack = true; 
                    enemy_uie.attack_windup_timer = SLOWBOY_ATTACK_WINDUP_TOTAL_DURATION;
                    enemy_uie.has_locked_attack_trajectory = false; 
                    // is_charging_attack remains false
                    enemy_uie.vel = {0,0}; 
                } else { // Standard wander/seek for Grunt or non-triggered/non-charging Slowboy
                    enemy_uie.wander_timer -= dt;
                    if enemy_uie.wander_timer <= 0.0 {
                        new_wander_angle_norm_uie := rand.float32() * m.TAU; 
                        enemy_uie.current_wander_vector = m.angle_to_vec2(new_wander_angle_norm_uie);
                        enemy_uie.wander_timer = ENEMY_WANDER_DIRECTION_CHANGE_INTERVAL + rand.float32_range(-0.2, 0.2);
                    }
                    direction_to_player_strict_normal_uie := player_pos_uie - enemy_uie.pos; 
                    final_direction_normal_uie := direction_to_player_strict_normal_uie; 
                    dist_sq_to_player_normal_uie := m.len_sq_vec2(direction_to_player_strict_normal_uie); 
                    if dist_sq_to_player_normal_uie > 0.001 {
                        normalized_strict_direction_normal_uie := m.norm_vec2(direction_to_player_strict_normal_uie); 
                        final_direction_normal_uie = normalized_strict_direction_normal_uie + (enemy_uie.current_wander_vector * ENEMY_WANDER_INFLUENCE);
                    }
                    
                    current_speed_normal_uie : f32;
                    if enemy_uie.type == .GRUNT { current_speed_normal_uie = ENEMY_GRUNT_SPEED; }
                    else if enemy_uie.type == .SLOWBOY { current_speed_normal_uie = ENEMY_SLOWBOY_SPEED; }
                    else { current_speed_normal_uie = ENEMY_GRUNT_SPEED; } // Should not happen here

                    if dist_sq_to_player_normal_uie > 0.00001 && m.len_sq_vec2(final_direction_normal_uie) > 0.00001 {
                        normalized_final_direction_normal_uie := m.norm_vec2(final_direction_normal_uie); 
                        enemy_uie.vel = normalized_final_direction_normal_uie * current_speed_normal_uie;
                    } else if m.len_sq_vec2(direction_to_player_strict_normal_uie) > 0.00001 {
                         enemy_uie.vel = m.norm_vec2(direction_to_player_strict_normal_uie) * current_speed_normal_uie;
                    } else { enemy_uie.vel = m.vec2_zero(); }
                }
            } 
        } 
        
        if !has_updated_pos_for_charge_bounce_uie { enemy_uie.pos += enemy_uie.vel * dt;  }
        
        if enemy_uie.type != .BOSS_CHROME_ORB { // Boss rotation is purely for aiming
            if enemy_uie.rotation > m.TAU { enemy_uie.rotation -= m.TAU; }
            if enemy_uie.rotation < 0    { enemy_uie.rotation += m.TAU; }
        }

        if live_enemy_count < MAX_ENEMIES {
            inst_uie := &state.enemy_instance_data[live_enemy_count]; 
            inst_uie.instance_pos = enemy_uie.pos;
            inst_uie.instance_main_rotation = enemy_uie.rotation; // For Grunt/Slowbody rotation, Boss aiming
            if enemy_uie.type == .BOSS_CHROME_ORB {
                // For the boss, use the large quad diameter directly.
                // The shader's p_scaled_uv space (where SDFs are defined) is fixed at -1.5 to 1.5.
                // The actual visual size of the boss orb within this giant quad is determined by SDF radii in the shader.
                inst_uie.instance_visual_scale = BOSS_QUAD_WORLD_DIAMETER;
            } else {
                // For other enemies, their visual scale is their current_size (world units)
                // multiplied by a shader-specific multiplier.
                inst_uie.instance_visual_scale = enemy_uie.current_size * ENEMY_SHADER_VISUAL_SCALE_MULTIPLIER; 
            }            inst_uie.instance_color = enemy_uie.color;
            inst_uie.instance_effect_params = {effect_params_x_uie, effect_params_y_uie, effect_params_z_uie, effect_params_w_uie};
            
            if enemy_uie.type == .GRUNT { inst_uie.instance_enemy_type = 0.0; } 
            else if enemy_uie.type == .SLOWBOY { inst_uie.instance_enemy_type = 1.0; } 
            else if enemy_uie.type == .BOSS_CHROME_ORB { inst_uie.instance_enemy_type = 2.0; }
            else if enemy_uie.type == .WEAVER { inst_uie.instance_enemy_type = 3.0; } // New visuals needed in shader (for now 0.0/grunt fallback if shader not updated, but we will pass ID)
            else if enemy_uie.type == .GRAVITRON { inst_uie.instance_enemy_type = 4.0; }
            else if enemy_uie.type == .TRACER { inst_uie.instance_enemy_type = 5.0; }
            else { inst_uie.instance_enemy_type = 0.0; } 
            live_enemy_count += 1;
        }
    } 
    return live_enemy_count
}
