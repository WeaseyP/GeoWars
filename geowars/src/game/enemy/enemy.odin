package enemy
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
    idx_to_write_en := shared.state.next_enemy_index
    shared.state.enemies[idx_to_write_en] = enemy_data
    shared.state.enemies[idx_to_write_en].active = true
    shared.state.next_enemy_index = (shared.state.next_enemy_index + 1) % shared.MAX_ENEMIES
}

spawn_enemy :: proc(current_ortho_width: f32, current_ortho_height: f32, player_pos: m.vec2, type_to_spawn: shared.EnemyType) {
    context = runtime.default_context()
    start_pos_en: m.vec2
    valid_spawn_found_en := false

    if type_to_spawn == .BOSS_CHROME_ORB {
        start_pos_en.x = 0.0
        start_pos_en.y = shared.ENEMY_BOSS_SPAWN_Y_OFFSET
        valid_spawn_found_en = true
    } else {
        // Spawn on the circular arena perimeter at a random angle so enemies arrive from all directions.
        for attempt_en in 0..<shared.ENEMY_MAX_SPAWN_ATTEMPTS {
            angle := rand.float32() * m.TAU
            spawn_radius := shared.ARENA_RADIUS * (0.95 + rand.float32() * 0.05) // just inside the boundary
            start_pos_en = m.vec2{math.cos(angle), math.sin(angle)} * spawn_radius
            dist_sq_to_player_en := m.len_sq_vec2(start_pos_en - player_pos)
            if dist_sq_to_player_en >= shared.ENEMY_MIN_SPAWN_DIST_FROM_PLAYER_SQ { valid_spawn_found_en = true; break }
        }
        if !valid_spawn_found_en {
            angle := rand.float32() * m.TAU
            start_pos_en = m.vec2{math.cos(angle), math.sin(angle)} * shared.ARENA_RADIUS * 0.95
        }
    }

    start_vel_en: m.vec2 = {0.0, 0.0}
    initial_wander_angle_en := rand.float32() * m.TAU
    initial_wander_vector_en := m.angle_to_vec2(initial_wander_angle_en)

    enemy_to_spawn: shared.Enemy

    target_world_size: f32
    initial_hp: i32
    death_anim_dur: f32
    enemy_color_val: m.vec4
    enemy_angular_vel: f32

    switch type_to_spawn {
        case .GRUNT:
            base_grunt_rgb_en := m.vec3{0.9, 0.1, 0.7}
            enemy_color_val = m.vec4{base_grunt_rgb_en.r, base_grunt_rgb_en.g, base_grunt_rgb_en.b, shared.ENEMY_BASE_ALPHA}
            target_world_size = shared.ENEMY_GRUNT_SCALE
            initial_hp = shared.ENEMY_GRUNT_MAX_HP
            death_anim_dur = shared.GRUNT_DEATH_ANIM_DURATION
            enemy_angular_vel = (rand.float32() * 2.0 - 1.0) * shared.ENEMY_MAX_ANGULAR_SPEED
        case .SLOWBOY:
            enemy_color_val = m.vec4{0.3, 0.7, 0.9, shared.ENEMY_BASE_ALPHA}
            target_world_size = shared.ENEMY_SLOWBOY_BASE_SCALE
            initial_hp = shared.ENEMY_SLOWBOY_MAX_HP
            death_anim_dur = shared.SLOWBOY_DEATH_ANIM_DURATION
            enemy_angular_vel = (rand.float32() * 2.0 - 1.0) * shared.ENEMY_MAX_ANGULAR_SPEED * 0.5
        case .BOSS_CHROME_ORB:
            enemy_color_val = m.vec4{0.75, 0.75, 0.8, shared.ENEMY_BASE_ALPHA}
            target_world_size = shared.ENEMY_BOSS_CHROME_ORB_SCALE
            initial_hp = shared.ENEMY_BOSS_CHROME_ORB_MAX_HP
            death_anim_dur = shared.BOSS_DEATH_ANIM_DURATION
            start_vel_en = {shared.ENEMY_BOSS_HORIZONTAL_SPEED, 0.0}
            enemy_angular_vel = 0.0
        case:
            fmt.printf("spawn_enemy: ERROR - Unknown type_to_spawn: %v\n", type_to_spawn)
            return
    }

    enemy_to_spawn = shared.Enemy {
        pos = start_pos_en, vel = start_vel_en, color = enemy_color_val,
        target_size = target_world_size,
        current_size = target_world_size * shared.ENEMY_INITIAL_SCALE_FACTOR,
        grow_timer = shared.ENEMY_GROW_DURATION, is_growing = true,
        rotation = rand.float32() * m.TAU,
        angular_vel = enemy_angular_vel,
        hp = initial_hp, type = type_to_spawn, active = false,
        current_wander_vector = initial_wander_vector_en,
        wander_timer = rand.float32_range(0.0, shared.ENEMY_WANDER_DIRECTION_CHANGE_INTERVAL),
        is_dying = false, dying_timer = 0.0, death_rect_offset = 0.0,
        death_anim_max_duration = death_anim_dur,
        boss_move_direction = 1.0,
        boss_detection_print_cooldown = 0.0,
        is_winding_up_attack = false, attack_windup_timer = 0.0,
        has_locked_attack_trajectory = false, attack_charge_target_pos = {0,0},
        is_charging_attack = false, attack_charge_start_pos = {0,0},
    }

    emit_enemy(enemy_to_spawn)
}

update_and_instance_enemies :: proc(dt: f32) -> int {
    context = runtime.default_context()
    live_enemy_count := 0
    player_pos_uie := shared.state.player_pos

    for i in 0..<shared.MAX_ENEMIES {
        if !shared.state.enemies[i].active { continue }
        enemy_uie := &shared.state.enemies[i]

        has_updated_pos_for_charge_bounce_uie := false

        effect_params_x_uie: f32 = 0.0
        effect_params_y_uie: f32 = 0.0
        effect_params_z_uie: f32 = 1.0
        effect_params_w_uie: f32 = 1.0

        if enemy_uie.is_dying {
            effect_params_x_uie = 1.0
            effect_params_y_uie = enemy_uie.death_rect_offset
            enemy_uie.dying_timer -= dt
            enemy_uie.death_rect_offset += shared.ENEMY_DEATH_RECT_SEPARATION_SPEED * dt

            if enemy_uie.dying_timer <= 0.0 { enemy_uie.active = false; continue }

            progress_raw_uie: f32
            if enemy_uie.death_anim_max_duration > 0.0 {
                progress_raw_uie = 1.0 - math.clamp(enemy_uie.dying_timer / enemy_uie.death_anim_max_duration, 0.0, 1.0)
            } else { progress_raw_uie = 0.0 }

            effect_params_w_uie = 1.0 - progress_raw_uie

            if enemy_uie.type == .GRUNT {
                eased_progress_for_scale_uie := math.pow(progress_raw_uie, 2.5)
                initial_part_uv_scale_uie : f32 = 1.0
                final_part_uv_scale_uie : f32 = shared.ENEMY_DEATH_RECT_FINAL_SCALE_FACTOR
                effect_params_z_uie = m.lerp(initial_part_uv_scale_uie, final_part_uv_scale_uie, eased_progress_for_scale_uie)
            } else {
                effect_params_z_uie = 1.0
            }

            enemy_uie.current_size = f32(m.lerp(enemy_uie.target_size, enemy_uie.target_size * shared.ENEMY_DEATH_RECT_FINAL_SCALE_FACTOR, progress_raw_uie))
        } else if enemy_uie.type == .SLOWBOY && enemy_uie.is_winding_up_attack {
            effect_params_x_uie = 0.0
            effect_params_y_uie = 1.0
            effect_params_z_uie = enemy_uie.attack_windup_timer
            effect_params_w_uie = shared.SLOWBOY_ATTACK_WINDUP_TOTAL_DURATION

            enemy_uie.attack_windup_timer -= dt
            if enemy_uie.attack_windup_timer <= shared.SLOWBOY_ATTACK_LOCKON_TIME_REMAINING && !enemy_uie.has_locked_attack_trajectory {
                enemy_uie.attack_charge_target_pos = player_pos_uie
                enemy_uie.has_locked_attack_trajectory = true
            }
            if enemy_uie.attack_windup_timer <= 0.0 {
                enemy_uie.is_winding_up_attack = false
                enemy_uie.is_charging_attack = true
                enemy_uie.attack_charge_start_pos = enemy_uie.pos
                charge_direction_vec_uie := enemy_uie.attack_charge_target_pos - enemy_uie.attack_charge_start_pos
                if m.len_sq_vec2(charge_direction_vec_uie) > 0.0001 {
                    charge_direction_vec_uie = m.norm_vec2(charge_direction_vec_uie)
                } else { charge_direction_vec_uie = m.vec2{0, 1} }
                enemy_uie.vel = charge_direction_vec_uie * shared.PLAYER_MAX_SPEED * shared.SLOWBOY_ATTACK_CHARGE_SPEED_FACTOR
                enemy_uie.angular_vel = 0
            }

        } else if enemy_uie.is_growing {
            effect_params_x_uie = 0.0
            effect_params_y_uie = 0.0
            if enemy_uie.type == .SLOWBOY { effect_params_z_uie = shared.ENEMY_SLOWBOY_GLOW_CANVAS_SF }
            else if enemy_uie.type == .BOSS_CHROME_ORB {
                effect_params_z_uie = shared.ENEMY_BOSS_VISION_RECT_WIDTH
                effect_params_w_uie = shared.ENEMY_BOSS_VISION_RANGE
            } else { effect_params_z_uie = 1.0 }

            enemy_uie.grow_timer -= dt
            if enemy_uie.grow_timer <= 0.0 {
                enemy_uie.current_size = enemy_uie.target_size
                enemy_uie.is_growing = false
                enemy_uie.grow_timer = 0.0
                if enemy_uie.type == .BOSS_CHROME_ORB {
                    enemy_uie.vel.x = shared.ENEMY_BOSS_HORIZONTAL_SPEED * enemy_uie.boss_move_direction
                    enemy_uie.vel.y = 0
                }
            } else {
                progress_grow_uie := 1.0 - (enemy_uie.grow_timer / shared.ENEMY_GROW_DURATION)
                progress_grow_uie = math.clamp(progress_grow_uie, 0.0, 1.0)
                initial_actual_size_uie := enemy_uie.target_size * shared.ENEMY_INITIAL_SCALE_FACTOR
                enemy_uie.current_size = m.lerp(initial_actual_size_uie, enemy_uie.target_size, progress_grow_uie)
            }

            if enemy_uie.type != .BOSS_CHROME_ORB {
                enemy_uie.rotation += enemy_uie.angular_vel * dt
                enemy_uie.wander_timer -= dt
                if enemy_uie.wander_timer <= 0.0 {
                    new_wander_angle_uie := rand.float32() * m.TAU
                    enemy_uie.current_wander_vector = m.angle_to_vec2(new_wander_angle_uie)
                    enemy_uie.wander_timer = shared.ENEMY_WANDER_DIRECTION_CHANGE_INTERVAL + rand.float32_range(-0.2, 0.2)
                }
                direction_to_player_strict_growing_uie := player_pos_uie - enemy_uie.pos
                final_direction_growing_uie := direction_to_player_strict_growing_uie
                dist_sq_to_player_growing_uie := m.len_sq_vec2(direction_to_player_strict_growing_uie)
                if dist_sq_to_player_growing_uie > 0.001 {
                    normalized_strict_direction_growing_uie := m.norm_vec2(direction_to_player_strict_growing_uie)
                    final_direction_growing_uie = normalized_strict_direction_growing_uie + (enemy_uie.current_wander_vector * shared.ENEMY_WANDER_INFLUENCE)
                }
                current_speed_growing_uie : f32
                if enemy_uie.type == .GRUNT { current_speed_growing_uie = shared.ENEMY_GRUNT_SPEED }
                else if enemy_uie.type == .SLOWBOY { current_speed_growing_uie = shared.ENEMY_SLOWBOY_SPEED }
                else { current_speed_growing_uie = 0.0 }

                if dist_sq_to_player_growing_uie > 0.00001 && m.len_sq_vec2(final_direction_growing_uie) > 0.00001 {
                    normalized_final_direction_growing_uie := m.norm_vec2(final_direction_growing_uie)
                    enemy_uie.vel = normalized_final_direction_growing_uie * current_speed_growing_uie
                } else if m.len_sq_vec2(direction_to_player_strict_growing_uie) > 0.00001 {
                    enemy_uie.vel = m.norm_vec2(direction_to_player_strict_growing_uie) * current_speed_growing_uie
                } else { enemy_uie.vel = m.vec2_zero() }
            } else {
                dir_to_player_boss_rot_uie := player_pos_uie - enemy_uie.pos
                if m.len_sq_vec2(dir_to_player_boss_rot_uie) > 0.0001 {
                    enemy_uie.rotation = -m.PI / 2.0
                }
                enemy_uie.vel = {0,0}
            }

        } else {
            enemy_uie.current_size = enemy_uie.target_size

            effect_params_x_uie = 0.0
            effect_params_y_uie = 0.0

            if enemy_uie.type == .BOSS_CHROME_ORB {
                effect_params_z_uie = shared.ENEMY_BOSS_VISION_RECT_WIDTH
                effect_params_w_uie = shared.ENEMY_BOSS_VISION_RANGE

                dir_to_player_boss_rot_uie := player_pos_uie - enemy_uie.pos
                if m.len_sq_vec2(dir_to_player_boss_rot_uie) > 0.0001 {
                    enemy_uie.rotation = -m.PI / 2.0
                }

                if enemy_uie.boss_detection_print_cooldown > 0 {
                    enemy_uie.boss_detection_print_cooldown -= dt
                }
                aspect_ratio_uie := sapp.widthf() / sapp.heightf()
                current_ortho_width_uie := shared.ORTHO_HEIGHT * aspect_ratio_uie
                boss_half_width_uie := enemy_uie.current_size * 0.5
                left_bound_uie := -current_ortho_width_uie + boss_half_width_uie + shared.ENEMY_BOSS_SCREEN_PADDING
                right_bound_uie := current_ortho_width_uie - boss_half_width_uie - shared.ENEMY_BOSS_SCREEN_PADDING

                enemy_uie.vel.y = 0
                if enemy_uie.vel.x == 0 {
                    enemy_uie.vel.x = shared.ENEMY_BOSS_HORIZONTAL_SPEED * enemy_uie.boss_move_direction
                }
                if enemy_uie.pos.x >= right_bound_uie && enemy_uie.vel.x > 0 {
                    enemy_uie.pos.x = right_bound_uie
                    enemy_uie.vel.x = -shared.ENEMY_BOSS_HORIZONTAL_SPEED
                    enemy_uie.boss_move_direction = -1.0
                } else if enemy_uie.pos.x <= left_bound_uie && enemy_uie.vel.x < 0 {
                    enemy_uie.pos.x = left_bound_uie
                    enemy_uie.vel.x = shared.ENEMY_BOSS_HORIZONTAL_SPEED
                    enemy_uie.boss_move_direction = 1.0
                }
            } else {
                enemy_uie.rotation += enemy_uie.angular_vel * dt

                if enemy_uie.type == .SLOWBOY {
                    effect_params_z_uie = shared.ENEMY_SLOWBOY_GLOW_CANVAS_SF
                    effect_params_w_uie = 1.0
                } else {
                    effect_params_z_uie = 1.0
                    effect_params_w_uie = 1.0
                }

                player_dist_sq_uie := m.dist_sq_vec2(enemy_uie.pos, player_pos_uie)
                if enemy_uie.type == .SLOWBOY && player_dist_sq_uie < (shared.SLOWBOY_ATTACK_DETECT_RANGE * shared.SLOWBOY_ATTACK_DETECT_RANGE) {
                    enemy_uie.is_winding_up_attack = true
                    enemy_uie.attack_windup_timer = shared.SLOWBOY_ATTACK_WINDUP_TOTAL_DURATION
                    enemy_uie.has_locked_attack_trajectory = false
                    enemy_uie.vel = {0,0}
                } else {
                    enemy_uie.wander_timer -= dt
                    if enemy_uie.wander_timer <= 0.0 {
                        new_wander_angle_norm_uie := rand.float32() * m.TAU
                        enemy_uie.current_wander_vector = m.angle_to_vec2(new_wander_angle_norm_uie)
                        enemy_uie.wander_timer = shared.ENEMY_WANDER_DIRECTION_CHANGE_INTERVAL + rand.float32_range(-0.2, 0.2)
                    }
                    direction_to_player_strict_normal_uie := player_pos_uie - enemy_uie.pos
                    final_direction_normal_uie := direction_to_player_strict_normal_uie
                    dist_sq_to_player_normal_uie := m.len_sq_vec2(direction_to_player_strict_normal_uie)
                    if dist_sq_to_player_normal_uie > 0.001 {
                        normalized_strict_direction_normal_uie := m.norm_vec2(direction_to_player_strict_normal_uie)
                        final_direction_normal_uie = normalized_strict_direction_normal_uie + (enemy_uie.current_wander_vector * shared.ENEMY_WANDER_INFLUENCE)
                    }

                    current_speed_normal_uie : f32
                    if enemy_uie.type == .GRUNT { current_speed_normal_uie = shared.ENEMY_GRUNT_SPEED }
                    else if enemy_uie.type == .SLOWBOY { current_speed_normal_uie = shared.ENEMY_SLOWBOY_SPEED }
                    else { current_speed_normal_uie = shared.ENEMY_GRUNT_SPEED }

                    if dist_sq_to_player_normal_uie > 0.00001 && m.len_sq_vec2(final_direction_normal_uie) > 0.00001 {
                        normalized_final_direction_normal_uie := m.norm_vec2(final_direction_normal_uie)
                        enemy_uie.vel = normalized_final_direction_normal_uie * current_speed_normal_uie
                    } else if m.len_sq_vec2(direction_to_player_strict_normal_uie) > 0.00001 {
                        enemy_uie.vel = m.norm_vec2(direction_to_player_strict_normal_uie) * current_speed_normal_uie
                    } else { enemy_uie.vel = m.vec2_zero() }
                }
            }
        }

        if !has_updated_pos_for_charge_bounce_uie { enemy_uie.pos += enemy_uie.vel * dt }

        if enemy_uie.type != .BOSS_CHROME_ORB {
            if enemy_uie.rotation > m.TAU { enemy_uie.rotation -= m.TAU }
            if enemy_uie.rotation < 0    { enemy_uie.rotation += m.TAU }
        }

        if live_enemy_count < shared.MAX_ENEMIES {
            inst_uie := &shared.state.enemy_instance_data[live_enemy_count]
            inst_uie.instance_pos = enemy_uie.pos
            inst_uie.instance_main_rotation = enemy_uie.rotation
            if enemy_uie.type == .BOSS_CHROME_ORB {
                inst_uie.instance_visual_scale = shared.BOSS_QUAD_WORLD_DIAMETER
            } else {
                inst_uie.instance_visual_scale = enemy_uie.current_size * shared.ENEMY_SHADER_VISUAL_SCALE_MULTIPLIER
            }
            inst_uie.instance_color = enemy_uie.color
            inst_uie.instance_effect_params = {effect_params_x_uie, effect_params_y_uie, effect_params_z_uie, effect_params_w_uie}

            if enemy_uie.type == .GRUNT { inst_uie.instance_enemy_type = 0.0 }
            else if enemy_uie.type == .SLOWBOY { inst_uie.instance_enemy_type = 1.0 }
            else if enemy_uie.type == .BOSS_CHROME_ORB { inst_uie.instance_enemy_type = 2.0 }
            else { inst_uie.instance_enemy_type = 0.0 }
            live_enemy_count += 1
        }
    }
    return live_enemy_count
}
