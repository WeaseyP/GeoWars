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
// PLAYER_CLAMP_X/Y removed, using shared.ARENA_WIDTH/HEIGHT
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

        // --- Timers ---
        if p.dash_cooldown_timer > 0 { p.dash_cooldown_timer -= dt }
        if p.lmb_cooldown_timer > 0 { p.lmb_cooldown_timer -= dt }
        if p.rmb_cooldown_timer > 0 { p.rmb_cooldown_timer -= dt }
        if p.invulnerable_timer > 0 { p.invulnerable_timer -= dt }

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
            // physics-based movement (drift)
            // Apply Acceleration
            if m.len_sq_vec2(accel_input) > 0.001 {
               p.vel += accel_input * shared.PLAYER_ACCEL * dt
            }
            
            // Apply Friction (Damping)
            // v = v / (1 + friction * dt) or v *= (1 - f*dt)
            // Let's use proportional damping
            damping := 1.0 / (1.0 + shared.PLAYER_FRICTION * dt)
            p.vel *= damping

            // Cap Speed
            if m.len_sq_vec2(p.vel) > f32(shared.PLAYER_SPEED * shared.PLAYER_SPEED) {
                p.vel = m.norm_vec2(p.vel) * shared.PLAYER_SPEED
            }
            
            // Smooth Rotation towards Mouse
            // Target angle based on mouse
            target_world := get_mouse_world_pos(input_mgr.mouse_screen_pos, &game_state.camera)
            dir_to_mouse := target_world - p.pos
            if m.len_sq_vec2(dir_to_mouse) > 0.001 {
                target_ang := math.atan2(dir_to_mouse.y, dir_to_mouse.x)
                // Lerp angle
                diff := target_ang - p.rotation
                // Wrap diff to -PI, PI
                for diff > m.PI do diff -= m.TAU
                for diff < -m.PI do diff += m.TAU
                
                p.rotation += diff * shared.PLAYER_ROTATION_SPEED * dt
            }
        }

        p.pos += p.vel * dt
        
    // --- Hexagon Collision ---
    // Normals for a Flat-topped Hexagon (point up/down? Or flat up?)
    // User asked for "Hexagon Arena".
    // 6 Normals. 
    // Let's assume Point-Top (normals at 0, 60, 120, 180, 240, 300 deg).
    // Or Flat-Top (30, 90, 150...).
    // Simplest is Flat-Top (Walls at +Y, -Y etc).
    // Let's align with the previous "Box" aspect ratio? No, Hexagon is usually regular regular.
    // Radius R.
    // Normals:
    // 0: (1, 0)
    // 1: (0.5, 0.866)
    // 2: (-0.5, 0.866)
    // 3: (-1, 0)
    // ...
    // Distance from center along normal must be < R.
    // Actually, dot(p, n) < R_dist (distance to wall).
    // For regular hexagon, distance to wall = R * cos(30) = R * 0.866.
    
    // --- SDF Collision (Exact) ---
    // Using Signed Distance Field logic to keep player inside Hexagon.
    // Flat-Top Hexagon logic (matching shader visual).
    // The shader uses a Flat-Top heuristic by swapping X/Y, or rotating by 90.
    // Here we implement `sdHexagon` directly.
    
    // Transform pos to local symmetry
    p_local := p.pos
    // For Flat-Top alignment (walls at Y +/- R), we treat X as the "pointy" axis in standard SDF, 
    // or we just swap X/Y to use the standard Pointy-Top generic formula.
    // Standard Inigo Quilez `sdHexagon` is Pointy-Top (Vertex at Y).
    // Our visual is Flat-Top (Vertex at X, Side at Y).
    // So swapping X/Y works.
    p_local = {p_local.y, p_local.x}
    
    p_local = {math.abs(p_local.x), math.abs(p_local.y)}
    
    // Hexagon Constants
    k := m.vec3{-0.866025404, 0.5, 0.577350269}
    
    // Dot product for symmetry
    dot_k_p := k.x*p_local.x + k.y*p_local.y
    min_dot := math.min(dot_k_p, 0.0)
    p_local -= {2.0 * min_dot * k.x, 2.0 * min_dot * k.y}
    
    // Clamp to box
    clamp_val := math.clamp(p_local.x, -k.z * shared.ARENA_HEX_RADIUS, k.z * shared.ARENA_HEX_RADIUS)
    p_local -= {clamp_val, shared.ARENA_HEX_RADIUS}
    
    dist := math.sqrt(p_local.x*p_local.x + p_local.y*p_local.y) * math.sign(p_local.y)
    
    // Collision Response
    // We want to keep player INSIDE, so distance should be NEGATIVE.
    // If dist > -radius (or > 0 for pure boundary), we preserve.
    // Actually `sdHexagon` returns distance *from edge*. 
    // Negative = Inside, Positive = Outside.
    // We want to keep `dist < -PLAYER_RADIUS` ideally? Or just `dist < 0` (center point).
    // Let's constrain center point to be inside by radius.
    // Effective limit: dist > -shared.PLAYER_CORE_WORLD_RADIUS essentially means touching/penetrating.
    // Real logic: If (dist > -radius), push back.
    
    wall_threshold := -f32(shared.PLAYER_CORE_WORLD_RADIUS)
    
    if dist > wall_threshold {
        // Penetration
        penetration := dist - wall_threshold
        
        // Gradient (Normal) calculation
        // Numerical gradient? Or derive it?
        // Basic approximate normal: exact vector from closest point?
        // For SDF, Gradient = normalize(p - closest_point).
        // Since we modified p_local, recovering true normal is tricky without re-evaluating.
        // But for a simple convex shape, the push direction is roughly -p (if far) or normal.
        
        // Simpler approach: Finite Difference for normal
        eps :: 0.001
        
        // Recalculate SDF for gradient
        sd_hex :: proc(p: m.vec2, r: f32) -> f32 {
             k := m.vec3{-0.866025404, 0.5, 0.577350269}
             p_loc := m.vec2{math.abs(p.y), math.abs(p.x)} // Swap/Abs
             d_k := k.x*p_loc.x + k.y*p_loc.y
             m_d := math.min(d_k, 0.0)
             p_loc -= {2.0*m_d*k.x, 2.0*m_d*k.y}
             c_v := math.clamp(p_loc.x, -k.z*r, k.z*r)
             p_loc -= {c_v, r}
             return math.sqrt(p_loc.x*p_loc.x + p_loc.y*p_loc.y) * math.sign(p_loc.y)
        }
        
        d_x := sd_hex(p.pos + {eps, 0}, shared.ARENA_HEX_RADIUS) - sd_hex(p.pos - {eps, 0}, shared.ARENA_HEX_RADIUS)
        d_y := sd_hex(p.pos + {0, eps}, shared.ARENA_HEX_RADIUS) - sd_hex(p.pos - {0, eps}, shared.ARENA_HEX_RADIUS)
        normal := m.norm_vec2({d_x, d_y})
        
        // Push Back
        p.pos -= normal * penetration
        
        // Velocity Reflection
        v_dot_n := m.dot(p.vel, normal)
        if v_dot_n > 0.0 {
            p.vel -= normal * v_dot_n
        }
    }

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
                
                // RMB Juice
                game_state.camera.shake_duration = 0.3
                game_state.camera.shake_intensity = 0.2
                
                // Muzzle Flash (Omni-directional logic? Or just center burst)
                 particle.spawn_muzzle_flash(game_state, p.pos, {1,0}) 
                 particle.spawn_muzzle_flash(game_state, p.pos, {-1,0}) 
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
            target_world := get_mouse_world_pos(input_mgr.mouse_screen_pos, &game_state.camera)

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
            
            // LMB Juice
            // Recoil
            RECOIL_FORCE :: 1.5 // Reduced from 5.0 to prevent jitter/reverse movement
            p.vel -= direction * RECOIL_FORCE
            
            // Muzzle Flash
            particle.spawn_muzzle_flash(game_state, spawn_pos + direction * 0.2, direction)
            
            // Screen Shake
            game_state.camera.shake_duration = 0.1
            game_state.camera.shake_intensity = 0.05 // Reduced from 0.1

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

get_mouse_world_pos :: proc(screen_pos: m.vec2, camera: ^shared.Camera) -> m.vec2 {
    width := sapp.widthf()
    height := sapp.heightf()
    
    // NDC
    ndc_x := (2.0 * screen_pos.x / width) - 1.0
    ndc_y := 1.0 - (2.0 * screen_pos.y / height)
    
    aspect := width / height
    
    // View dimensions
    ortho_height := f32(shared.ORTHO_HEIGHT)
    ortho_width := ortho_height * aspect
    
    // World pos relative to camera center
    world_x := ndc_x * ortho_width
    world_y := ndc_y * ortho_height
    
    return {world_x + camera.pos.x, world_y + camera.pos.y}
}
