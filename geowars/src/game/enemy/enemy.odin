package enemy

import "core:math"
import "core:fmt"
import m "../../vendor/math"
import rand "core:math/rand"
import shared "../../shared"
import sapp "../../vendor/sokol/app"
import "base:runtime"

// Constants
ENEMY_SPAWN_BORDER_FRACTION :: 0.5
ENEMY_MIN_SPAWN_DIST_FROM_PLAYER_SQ :: 0.25
ENEMY_MAX_SPAWN_ATTEMPTS :: 10
ENEMY_INITIAL_SCALE_FACTOR :: 0.1
ENEMY_GROW_DURATION :: 1.0
ENEMY_WANDER_DIRECTION_CHANGE_INTERVAL :: 1.5
ENEMY_WANDER_INFLUENCE :: 0.35
ENEMY_BOSS_SPAWN_Y_OFFSET :: 1.125 // 1.5 * 0.75

// Stats
ENEMY_GRUNT_SPEED :: 0.75
ENEMY_SLOWBOY_SPEED :: 0.22
ENEMY_WEAVER_SPEED :: 1.8
ENEMY_GRAVITRON_SPEED :: 0.3
ENEMY_TRACER_SPEED :: 3.75
ENEMY_ELITE_SPEED :: 1.05

ENEMY_GRUNT_HP :: 4
ENEMY_SLOWBOY_HP :: 16
ENEMY_WEAVER_HP :: 6
ENEMY_GRAVITRON_HP :: 40
ENEMY_TRACER_HP :: 3
ENEMY_ELITE_HP :: 25
ENEMY_BOSS_HP :: 100

emit_enemy :: proc(game_state: ^shared.GameState, enemy_data: shared.Enemy) {
    idx := game_state.next_enemy_index
    game_state.enemies[idx] = enemy_data
    game_state.enemies[idx].active = true
    game_state.next_enemy_index = (game_state.next_enemy_index + 1) % shared.MAX_ENEMIES
}

spawn_enemy :: proc(game_state: ^shared.GameState, width: f32, height: f32, player_pos: m.vec2, type: shared.EnemyType) {
    start_pos := m.vec2{0,0}
    valid := false

    if type == .BOSS_CHROME_ORB {
        start_pos.x = 0.0
        start_pos.y = ENEMY_BOSS_SPAWN_Y_OFFSET
        valid = true
    } else {
        for _ in 0..<ENEMY_MAX_SPAWN_ATTEMPTS {
            side := rand.int31() % 4
            depth := rand.float32() * ENEMY_SPAWN_BORDER_FRACTION

            switch side {
                case 0: start_pos = { (rand.float32()*2-1)*width, height*(1-depth) }
                case 1: start_pos = { (rand.float32()*2-1)*width, -height*(1-depth) }
                case 2: start_pos = { -width*(1-depth), (rand.float32()*2-1)*height }
                case 3: start_pos = { width*(1-depth), (rand.float32()*2-1)*height }
            }

            if m.len_sq_vec2(start_pos - player_pos) >= ENEMY_MIN_SPAWN_DIST_FROM_PLAYER_SQ {
                valid = true
                break
            }
        }
        if !valid {
            start_pos = { -width*0.8, height*0.8 } // Fallback
        }
    }
    
    target_size : f32
    hp : i32
    color : m.vec4
    ang_vel : f32

    switch type {
        case .GRUNT:
            target_size = 0.3
            hp = ENEMY_GRUNT_HP
            color = {0.9, 0.1, 0.7, 0.65}
            ang_vel = 2.0
        case .SLOWBOY:
            target_size = 0.38
            hp = ENEMY_SLOWBOY_HP
            color = {0.3, 0.7, 0.9, 0.65}
            ang_vel = 1.0
        case .WEAVER:
            target_size = 0.27
            hp = ENEMY_WEAVER_HP
            color = {0.1, 0.9, 0.3, 0.8}
            ang_vel = 0.0 // Aligned to movement
        case .GRAVITRON:
            target_size = 0.45
            hp = ENEMY_GRAVITRON_HP
            color = {0.2, 0.2, 0.8, 0.9}
            ang_vel = 0.5
        case .TRACER:
            target_size = 0.3
            hp = ENEMY_TRACER_HP
            color = {0.9, 0.7, 0.1, 0.8}
            ang_vel = 0.0
        case .ELITE:
            target_size = 0.45
            hp = ENEMY_ELITE_HP
            color = {0.9, 0.1, 0.1, 0.9}
            ang_vel = 0.8
        case .BOSS_CHROME_ORB:
            target_size = 0.2 // Boss scaling handled in shader or special Logic
            hp = ENEMY_BOSS_HP
            color = {0.75, 0.75, 0.8, 1.0}
            ang_vel = 0.0
    }
    
    emit_enemy(game_state, shared.Enemy{
        pos=start_pos, color=color, target_size=target_size, current_size=target_size*ENEMY_INITIAL_SCALE_FACTOR,
        hp=hp, type=type, active=false, is_growing=true, grow_timer=ENEMY_GROW_DURATION,
        angular_vel=ang_vel, wander_timer=rand.float32_range(0, 2.0),
        boss_move_direction=1.0,
    })
}

update_and_instance_enemies :: proc(game_state: ^shared.GameState, dt: f32) -> int {
    live_count := 0
    player_pos := game_state.player.pos

    for i in 0..<shared.MAX_ENEMIES {
        if !game_state.enemies[i].active { continue }
        e := &game_state.enemies[i]
        
        // --- Logic ---
        if e.is_dying {
            e.dying_timer -= dt
            e.death_rect_offset += 0.3 * dt
            if e.dying_timer <= 0.0 { e.active = false; continue }
            // Scale down effect
            progress : f32 = 1.0
            if e.death_anim_max_duration > 0.001 {
                progress = e.dying_timer / e.death_anim_max_duration
            }
            e.current_size = m.lerp(f32(0.0), e.target_size, progress)
        } else if e.is_growing {
            e.grow_timer -= dt
            if e.grow_timer <= 0.0 {
                e.is_growing = false
                e.current_size = e.target_size
            } else {
                progress := 1.0 - (e.grow_timer / ENEMY_GROW_DURATION)
                e.current_size = m.lerp(e.target_size * ENEMY_INITIAL_SCALE_FACTOR, e.target_size, progress)
            }
        } else {
            // AI Behavior
            dist_sq := m.len_sq_vec2(player_pos - e.pos)
            dir_to_player := m.vec2{0,0}
            if dist_sq > 0.0001 { dir_to_player = m.norm_vec2(player_pos - e.pos) }
            
            switch e.type {
                case .GRUNT, .ELITE:
                    // Simple Seek with wander
                    e.wander_timer -= dt
                    if e.wander_timer <= 0.0 {
                        angle := rand.float32() * f32(m.TAU)
                        e.current_wander_vector = m.angle_to_vec2(angle)
                        e.wander_timer = ENEMY_WANDER_DIRECTION_CHANGE_INTERVAL
                    }
                    move_dir := m.norm_vec2(dir_to_player + e.current_wander_vector * ENEMY_WANDER_INFLUENCE)
                    speed : f32 = (e.type == .GRUNT ? ENEMY_GRUNT_SPEED : ENEMY_ELITE_SPEED)
                    e.vel = move_dir * speed
                    e.rotation += e.angular_vel * dt

                case .SLOWBOY:
                    // Seek until range, then charge
                    if dist_sq < 0.64 && !e.is_winding_up_attack && !e.is_charging_attack { // 0.8^2
                        e.is_winding_up_attack = true
                        e.attack_windup_timer = 1.5
                        e.vel = {0,0}
                    } else if e.is_winding_up_attack {
                        e.attack_windup_timer -= dt
                        if e.attack_windup_timer <= 0.0 {
                            e.is_winding_up_attack = false
                            e.is_charging_attack = true
                            e.attack_charge_start_pos = e.pos
                            e.attack_charge_target_pos = player_pos
                            charge_dir := m.norm_vec2(player_pos - e.pos)
                            e.vel = charge_dir * ENEMY_SLOWBOY_SPEED * 3.0
                        }
                    } else if e.is_charging_attack {
                        // Move linear (handled by vel)
                        if m.dist_sq_vec2(e.pos, e.attack_charge_start_pos) > 2.0 {
                            e.is_charging_attack = false
                            e.vel = {0,0}
                        }
                    } else {
                        e.vel = dir_to_player * ENEMY_SLOWBOY_SPEED
                    }
                    e.rotation += e.angular_vel * dt
                    
                case .WEAVER:
                    // Sine wave movement
                    // Orthogonal vector
                    ortho := m.vec2{-dir_to_player.y, dir_to_player.x}
                    sine_val := math.sin(f32(sapp.frame_count()) * 0.2)
                    e.vel = (dir_to_player * 0.5 + ortho * sine_val * 4.5) * ENEMY_WEAVER_SPEED
                    e.rotation = math.atan2(e.vel.y, e.vel.x) // Face movement

                case .GRAVITRON:
                    // Pull player logic moved to "Single Closest Lock"
                    e.vel = dir_to_player * ENEMY_GRAVITRON_SPEED
                    e.rotation -= e.angular_vel * dt
                    
                    // Check logic for closest
                    GRAVITRON_RANGE_SQ :: 100.0 // Half map (approx 10 units) squared
                    if dist_sq < GRAVITRON_RANGE_SQ {
                         if dist_sq < game_state.closest_gravitron_dist_sq {
                             game_state.closest_gravitron_dist_sq = dist_sq
                             game_state.closest_gravitron_pos = e.pos
                         }
                    }

                case .TRACER:
                    // Dash-Stop-Dash
                    e.wander_timer -= dt // Use as state timer
                    if e.wander_timer <= 0.0 {
                        // Switch state
                        if e.is_charging_attack { // Was dashing
                            e.is_charging_attack = false
                            e.vel = {0,0}
                            e.wander_timer = 1.0 // Pause time
                        } else { // Was pausing
                            e.is_charging_attack = true
                            e.vel = dir_to_player * ENEMY_TRACER_SPEED
                            e.wander_timer = 0.5 // Dash time
                            e.rotation = math.atan2(e.vel.y, e.vel.x)
                        }
                    }
                    if !e.is_charging_attack {
                        // Face player while aiming
                        e.rotation = math.atan2(dir_to_player.y, dir_to_player.x)
                    }

                case .BOSS_CHROME_ORB:
                    // Boss logic (Horizontal strafe)
                    // ... (implement simple boss logic)
                    e.vel.y = 0
                    if e.vel.x == 0 { e.vel.x = 1.0 }
                    // Bounce checks should be here or rely on update
                    // Use boss_move_direction
                    if e.pos.x > 2.0 { e.boss_move_direction = -1.0; e.vel.x = -1.0 }
                    if e.pos.x < -2.0 { e.boss_move_direction = 1.0; e.vel.x = 1.0 }
            }

            e.pos += e.vel * dt
        }

        // --- Instance Data ---
        if live_count < shared.MAX_ENEMIES {
            inst := &game_state.enemy_instance_data[live_count]
            inst.instance_pos = e.pos
            inst.instance_main_rotation = e.rotation
            inst.instance_visual_scale = e.current_size * 3.0 // Shader mult
            inst.instance_color = e.color

            // Map types to shader IDs
            type_id : f32 = 0.0
            switch e.type {
                case .GRUNT: type_id = 0.0
                case .SLOWBOY: type_id = 1.0
                case .BOSS_CHROME_ORB: type_id = 2.0
                // Add mapping for new types (reuse grunt or new IDs if shader updated)
                case .WEAVER: type_id = 3.0
                case .GRAVITRON: type_id = 4.0
                case .TRACER: type_id = 5.0
                case .ELITE: type_id = 6.0
            }
            inst.instance_enemy_type = type_id
            
            // Effect params
            inst.instance_effect_params = {
                e.is_dying ? 1.0 : 0.0,
                e.death_rect_offset,
                1.0, // Scale/Glow factor
                1.0  // Alpha
            }

            live_count += 1
        }
    }
    return live_count
}
