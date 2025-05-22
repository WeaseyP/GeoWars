// File: geowars.odin (Revised for Slow Travel & Strong Radial Explosion)
//------------------------------------------------------------------------------
package main

import "base:runtime"
import "core:math"
import "core:mem"
import "core:fmt"
import slog "../sokol/log"
import sg "../sokol/gfx"
import sapp "../sokol/app"
import sglue "../sokol/glue"
import m "../math"
import rand "core:math/rand"

// =============================================================================
// START: Package-Level Declarations
// =============================================================================

MAX_PARTICLES :: 2048
DEATH_BURST_PARTICLE_COUNT :: 150
MAX_ENEMIES :: 128 // Max number of enemies

// --- Constants ---
ORTHO_HEIGHT :: 1.5
PLAYER_ACCELERATION      :: 15.0
PLAYER_REVERSE_FACTOR    :: 0.5
PLAYER_DAMPING           :: 2.5
PLAYER_MAX_SPEED         :: 7.0
PLAYER_SCALE             :: 0.25
PLAYER_CORE_SHADER_RADIUS :: 0.04
PLAYER_UV_SPACE_EXTENT   :: 0.5
PLAYER_CORE_WORLD_RADIUS :: (PLAYER_CORE_SHADER_RADIUS / PLAYER_UV_SPACE_EXTENT) * PLAYER_SCALE
BLACKHOLE_COOLDOWN_DURATION :: 1.0
MAX_SPIN_SPEED           :: f32(m.PI * 2.0)
// *** Swirl Charge Constants ***
SWIRL_CHARGE_DURATION_BASE  : f32 : 1.8
SWIRL_CHARGE_DURATION_RAND  : f32 : 0.5
SWIRL_RADIUS_SPAWN          : f32 : 0.05 // Tighter spawn
SWIRL_SPEED_ORBITAL_BASE    : f32 : 3.5  // Keep orbital speed
SWIRL_SPEED_INWARD_INITIAL  : f32 : -0.1 // Keep slight inward drift
SWIRL_PARTICLE_SIZE_BASE    : f32 : 0.03 // Smaller particles
SWIRL_PARTICLE_SIZE_RAND    : f32 : 0.01
// *** Cloud Travel Speed Constants ***
SWIRL_CLOUD_TRAVEL_FACTOR   : f32 : 0.0  // SET TO 0: Ignore player velocity entirely
SWIRL_CLOUD_BASE_PUSH       : f32 : 0.15 // Reduced FURTHER: Very slow drift away from player front
// *** Explosion Constants (after swirl) ***
EXPLOSION_LIFETIME_BASE : f32 : 1.0
EXPLOSION_LIFETIME_RAND : f32 : 0.8
EXPLOSION_SPEED_BASE    : f32 : 6.0  // Increased explosion speed SIGNIFICANTLY
EXPLOSION_SPEED_RAND    : f32 : 4.0  // Increased explosion speed variance SIGNIFICANTLY
EXPLOSION_PARTICLE_SPIN : f32 : 0.0  // No individual spin during explosion

// --- Enemy Constants ---
ENEMY_GRUNT_SCALE :: 0.15
ENEMY_GRUNT_SPEED :: 1.0 
ENEMY_SPAWN_INTERVAL :: 10.0
ENEMY_SPAWN_BORDER_FRACTION :: 0.5 
ENEMY_MIN_SPAWN_DIST_FROM_PLAYER_SQ :: 0.5 * 0.5 
ENEMY_MAX_SPAWN_ATTEMPTS :: 10
ENEMY_INITIAL_SCALE_FACTOR :: 0.1 
ENEMY_GROW_DURATION :: 1.0     
ENEMY_MAX_ANGULAR_SPEED :: m.PI / 1.5 // Radians per second (e.g., 120 degrees/sec)
ENEMY_BASE_ALPHA :: 0.65           // Base translucency for the enemy
ENEMY_WANDER_INFLUENCE :: 0.35 // How much wander affects the main direction (0.0 = no wander, 1.0 = potentially strong deviation)
ENEMY_WANDER_DIRECTION_CHANGE_INTERVAL :: 1.5 // Seconds between wander direction changes

// Rendering Internals
vertex_stride :: size_of(f32) * 7
particle_quad_stride :: size_of(f32) * 4
enemy_quad_stride :: size_of(f32) * 4 // Same as particle for now if reusing VBO

// --- Struct Definitions ---
Particle :: struct {
	pos:              m.vec2,
	vel:              m.vec2,
	cloud_travel_vel: m.vec2, 
	color:            m.vec4,
	size:             f32,
	start_size:       f32,
	life_remaining:   f32,
	life_max:         f32,      
    swirl_duration:   f32,      
	rotation:         f32,
	angular_vel:      f32,
    charge_center_pos: m.vec2, 
	is_burst_particle: bool,
    is_swirling_charge: bool, 
	active:           bool,
}
Particle_Instance_Data :: struct #align(16) {
	using _: struct #packed {
		instance_pos:      m.vec2,
		instance_size:     f32,
		instance_rotation: f32,
		instance_color:    m.vec4,
	},
}


Enemy :: struct {
    pos: m.vec2,
    vel: m.vec2,
    color: m.vec4,        
    target_size: f32,      
    current_size: f32,     
    grow_timer: f32,       
    is_growing: bool,      
    rotation: f32,         
    angular_vel: f32,    
    active: bool,

    // MODIFIED: New fields for wandering
    current_wander_vector: m.vec2,
    wander_timer: f32,
}

Enemy_Instance_Data :: struct #align(16) {
    using _: struct #packed {
        instance_pos: m.vec2,
        instance_size: f32,
        instance_rotation: f32,
        instance_color: m.vec4, 
    },
}


// --- Global State ---
state: struct {
    pass_action: sg.Pass_Action, bind: sg.Bindings,
    bg_pip: sg.Pipeline, player_pip: sg.Pipeline, particle_pip: sg.Pipeline, enemy_pip: sg.Pipeline,
    bg_fs_params: Bg_Fs_Params, player_vs_params: Player_Vs_Params, player_fs_params: Player_Fs_Params,
    particle_vs_params: Particle_Vs_Params, particle_fs_params: Particle_Fs_Params,
    enemy_vs_params: Enemy_Vs_Params, enemy_fs_params: Enemy_Fs_Params, 
    player_pos: m.vec2, player_vel: m.vec2,
    key_w_down: bool, key_s_down: bool, key_a_down: bool, key_d_down: bool,
    rmb_down: bool, previous_rmb_down: bool, rmb_cooldown_timer: f32,
	particles: [MAX_PARTICLES]Particle, particle_instance_data: [MAX_PARTICLES]Particle_Instance_Data,
	particle_quad_vbo: sg.Buffer, particle_instance_vbo: sg.Buffer, particle_bind: sg.Bindings,
	next_particle_index: int, num_active_particles: int,


    enemies: [MAX_ENEMIES]Enemy, enemy_instance_data: [MAX_ENEMIES]Enemy_Instance_Data,
    enemy_instance_vbo: sg.Buffer, enemy_bind: sg.Bindings,
    next_enemy_index: int, num_active_enemies: int,
    enemy_spawn_timer: f32, // MODIFIED: Added spawn timer
    
}


// =============================================================================
// END: Package-Level Declarations
// =============================================================================


init :: proc "c" () {
    context = runtime.default_context()
    sg.setup({ pipeline_pool_size=10, buffer_pool_size=10, shader_pool_size=10, environment=sglue.environment(), logger={func=slog.func} })
    fmt.printf("--- Init Start ---\n")
    state.pass_action = {colors = {0={load_action = .DONTCARE}}}
    vertices := [?]f32 { -1,-1,0,0,0,0,0, 1,-1,0,1,0,0,0, -1,1,0,0,1,0,0, 1,1,0,1,1,0,0 }
    state.bind.vertex_buffers[0] = sg.make_buffer({ label="shared-quad", data=sg.Range{ptr=&vertices[0], size=size_of(vertices)}})
	
    particle_quad_verts := [?]f32{ -0.5,-0.5,0,0, 0.5,-0.5,1,0, -0.5,0.5,0,1, 0.5,0.5,1,1 }
	state.particle_quad_vbo = sg.make_buffer({ label="particle-quad", data=sg.Range{ptr=&particle_quad_verts[0], size=size_of(particle_quad_verts)}})
    state.particle_instance_vbo = sg.make_buffer({ label="particle-inst", size=MAX_PARTICLES*size_of(Particle_Instance_Data), type=.VERTEXBUFFER, usage=.STREAM })
    
    state.enemy_instance_vbo = sg.make_buffer({ label="enemy-inst", size=MAX_ENEMIES*size_of(Enemy_Instance_Data), type=.VERTEXBUFFER, usage=.STREAM })

    bg_shd := sg.make_shader(bg_shader_desc(sg.query_backend()))
    player_shd := sg.make_shader(player_shader_desc(sg.query_backend()))
    particle_shd := sg.make_shader(particle_shader_desc(sg.query_backend()))
    enemy_shd := sg.make_shader(enemy_shader_desc(sg.query_backend())) 

    state.bg_pip = sg.make_pipeline({ label="bg-pip", shader=bg_shd, layout={buffers={0={stride=vertex_stride}},attrs={ATTR_bg_position={format=.FLOAT2}}}, primitive_type=.TRIANGLE_STRIP})
    state.player_pip = sg.make_pipeline({ label="player-pip", shader=player_shd, layout={buffers={0={stride=vertex_stride}},attrs={ATTR_player_position={format=.FLOAT2}}}, primitive_type=.TRIANGLE_STRIP, colors={0={blend={enabled=true, src_factor_rgb=.SRC_ALPHA,dst_factor_rgb=.ONE_MINUS_SRC_ALPHA}}}, depth={write_enabled=false, compare=.ALWAYS} })
    state.particle_pip = sg.make_pipeline({ label="particle-pip", shader=particle_shd,
        layout={ buffers={0={stride=particle_quad_stride,step_func=.PER_VERTEX}, 1={stride=size_of(Particle_Instance_Data),step_func=.PER_INSTANCE}}, attrs={ATTR_particle_quad_pos={buffer_index=0,offset=0,format=.FLOAT2}, ATTR_particle_quad_uv={buffer_index=0,offset=8,format=.FLOAT2}, ATTR_particle_instance_pos_size_rot={buffer_index=1,offset=0,format=.FLOAT4}, ATTR_particle_instance_color={buffer_index=1,offset=16,format=.FLOAT4}} },
        primitive_type=.TRIANGLE_STRIP, colors={0={blend={enabled=true, src_factor_rgb=.SRC_ALPHA, dst_factor_rgb=.ONE}}}, depth={write_enabled=false, compare=.ALWAYS}
    })
    pip_state := sg.query_pipeline_state(state.particle_pip);
    if pip_state != .VALID { fmt.eprintf("!!! CRITICAL: Particle pipeline creation failed! State: %v\n", pip_state); }
    else { fmt.printf("--- Particle pipeline created successfully ---\n"); }

    state.enemy_pip = sg.make_pipeline({ label="enemy-pip", shader=enemy_shd,
        layout={ buffers={0={stride=enemy_quad_stride, step_func=.PER_VERTEX}, 1={stride=size_of(Enemy_Instance_Data), step_func=.PER_INSTANCE}},
                 attrs={ 
                     ATTR_enemy_quad_pos={buffer_index=0,offset=0,format=.FLOAT2},
                     ATTR_enemy_quad_uv={buffer_index=0,offset=8,format=.FLOAT2},
                     ATTR_enemy_instance_pos_size_rot={buffer_index=1,offset=0,format=.FLOAT4},
                     ATTR_enemy_instance_color_in={buffer_index=1,offset=16,format=.FLOAT4} 
                 }},
        primitive_type=.TRIANGLE_STRIP,
        colors={0={blend={enabled=true, src_factor_rgb=.SRC_ALPHA, dst_factor_rgb=.ONE_MINUS_SRC_ALPHA}}}, 
        depth={write_enabled=false, compare=.ALWAYS}
    })
    pip_state_enemy := sg.query_pipeline_state(state.enemy_pip);
    if pip_state_enemy != .VALID { fmt.eprintf("!!! CRITICAL: Enemy pipeline creation failed! State: %v\n", pip_state_enemy); }
    else { fmt.printf("--- Enemy pipeline created successfully ---\n"); }

	state.particle_bind = sg.Bindings{
        vertex_buffers = { 0=state.particle_quad_vbo, 1=state.particle_instance_vbo },
    }
    state.enemy_bind = sg.Bindings{
        vertex_buffers = { 0=state.particle_quad_vbo, 1=state.enemy_instance_vbo }, 
    }

	state.next_particle_index = 0; state.num_active_particles = 0;
    state.next_enemy_index = 0; state.num_active_enemies = 0;
    state.player_pos = {0,0}; state.player_vel = {0,0};
    state.rmb_down=false; state.previous_rmb_down=false; state.rmb_cooldown_timer=0.0;


    state.enemy_spawn_timer = rand.float32_range(1.0, 3.0)

    fmt.printf("--- Init Complete ---\n")
}

event :: proc "c" (event: ^sapp.Event) {
    context = runtime.default_context()
    #partial switch event.type {
    case .KEY_DOWN: #partial switch event.key_code { case .W: state.key_w_down=true; case .S: state.key_s_down=true; case .A: state.key_a_down=true; case .D: state.key_d_down=true; case .ESCAPE: sapp.request_quit(); }
    case .KEY_UP: #partial switch event.key_code { case .W: state.key_w_down=false; case .S: state.key_s_down=false; case .A: state.key_a_down=false; case .D: state.key_d_down=false; }
    case .MOUSE_DOWN: if event.mouse_button == .RIGHT { state.rmb_down = true }
	case .MOUSE_UP: if event.mouse_button == .RIGHT { state.rmb_down = false }
    }
}

emit_particle :: proc(part: Particle) {
	context = runtime.default_context()
	start_index := state.next_particle_index
    state.particles[state.next_particle_index] = part
	state.particles[state.next_particle_index].active = true
	state.next_particle_index = (state.next_particle_index + 1) % MAX_PARTICLES
}

spawn_swirling_charge :: proc() {
	context = runtime.default_context()
    charge_spawn_center := state.player_pos 
	charge_duration := SWIRL_CHARGE_DURATION_BASE + rand.float32() * SWIRL_CHARGE_DURATION_RAND 
    start_size_val_base := SWIRL_PARTICLE_SIZE_BASE
    start_size_val_rand := SWIRL_PARTICLE_SIZE_RAND
	start_color := m.vec4{0.8, 0.3, 1.0, 1.0}
    cloud_travel_vel: m.vec2 = {0, 0} 
    player_speed_sq := m.len_sq_vec2(state.player_vel)
    player_front_dir := m.vec2{0,1} 
    if m.len_sq_vec2(state.player_vel) > 0.001 {
        player_front_dir = m.norm_vec2(state.player_vel)
    }
    cloud_travel_vel = player_front_dir * SWIRL_CLOUD_BASE_PUSH;
    if player_speed_sq > 0.001 && SWIRL_CLOUD_TRAVEL_FACTOR > 0.0 {
         cloud_travel_vel += state.player_vel * SWIRL_CLOUD_TRAVEL_FACTOR;
    }
	for _ in 0..<DEATH_BURST_PARTICLE_COUNT {
        start_size_val := start_size_val_base + rand.float32() * start_size_val_rand
        spawn_angle := rand.float32() * f32(m.TAU)
        spawn_dist := rand.float32() * SWIRL_RADIUS_SPAWN
        relative_pos := m.angle_to_vec2(spawn_angle) * spawn_dist
        start_pos := charge_spawn_center + relative_pos 
        tangent_dir := m.vec2{-relative_pos.y, relative_pos.x}
        if m.len_sq_vec2(tangent_dir) > 0.001 { tangent_dir = m.norm_vec2(tangent_dir) }
        orbital_vel := tangent_dir * SWIRL_SPEED_ORBITAL_BASE * (0.8 + rand.float32() * 0.4)
        inward_vel_dir: m.vec2 = {0,0}
        if m.len_sq_vec2(relative_pos) > 0.001 { inward_vel_dir = m.norm_vec2(-relative_pos) }
        inward_vel := inward_vel_dir * SWIRL_SPEED_INWARD_INITIAL
        start_vel := cloud_travel_vel + orbital_vel + inward_vel
        start_angular_vel := (rand.float32() * 2.0 - 1.0) * MAX_SPIN_SPEED * 2.5
		emit_particle(Particle{
			pos=start_pos, vel=start_vel, cloud_travel_vel=cloud_travel_vel, color=start_color,
            size=start_size_val, start_size=start_size_val, life_remaining=charge_duration, life_max=charge_duration,
            swirl_duration=charge_duration, rotation=rand.float32()*f32(m.TAU), angular_vel=start_angular_vel,
            charge_center_pos=charge_spawn_center, is_burst_particle=false, is_swirling_charge=true, active=false, 
		})
	}
}

update_and_instance_particles :: proc(dt: f32) -> int {
	context = runtime.default_context()
	live_particle_count := 0
	for i in 0..<MAX_PARTICLES {
		if !state.particles[i].active { continue }
		p := &state.particles[i]
        p.pos += p.vel * dt
		p.rotation += p.angular_vel * dt
        p.life_remaining -= dt
        if p.is_swirling_charge && p.life_remaining <= 0.0 {
            p.is_swirling_charge = false 
            new_life := EXPLOSION_LIFETIME_BASE + rand.float32() * EXPLOSION_LIFETIME_RAND
            p.life_remaining = new_life 
            p.life_max = new_life     
            explosion_center := p.charge_center_pos + p.cloud_travel_vel * p.swirl_duration
            relative_pos := p.pos - explosion_center
            outward_dir : m.vec2 = {rand.float32() * 2.0 - 1.0, rand.float32() * 2.0 - 1.0} 
            len_sq := m.len_sq_vec2(relative_pos)
            if len_sq > 0.0001 { outward_dir = m.norm_vec2(relative_pos) 
            } else if m.len_sq_vec2(outward_dir) > 0.0001 { outward_dir = m.norm_vec2(outward_dir)
            } else { outward_dir = {0.0, 1.0} }
            explosion_speed := EXPLOSION_SPEED_BASE + rand.float32() * EXPLOSION_SPEED_RAND
            p.vel = outward_dir * explosion_speed
            p.angular_vel = EXPLOSION_PARTICLE_SPIN 
        }
        if !p.is_swirling_charge && p.life_remaining <= 0.0 { p.active = false; continue }
        life_ratio: f32 = 0.0
        if p.life_max > 0.0 { life_ratio = math.max(f32(0.0), p.life_remaining / p.life_max) }
		if p.is_swirling_charge { p.size = p.start_size; p.color.a = 1.0;      
        } else { p.size = p.start_size * life_ratio * life_ratio; p.color.a = life_ratio * life_ratio; }
		if live_particle_count < MAX_PARTICLES {
			inst := &state.particle_instance_data[live_particle_count];
			inst.instance_pos=p.pos; inst.instance_size=p.size; inst.instance_rotation=p.rotation; inst.instance_color=p.color;
			live_particle_count += 1;
		}
	}
	return live_particle_count
}

emit_enemy :: proc(enemy_data: Enemy) {
    context = runtime.default_context()
    // Ensure we don't go out of bounds and that we can actually add an enemy
    // A more robust system might check num_active_enemies, but for now, this relies on next_enemy_index cycling.
    // The main check for whether we *can* add more is effectively done by update_and_instance_enemies
    // which only populates up to MAX_ENEMIES into the instance buffer.
    
    // fmt.printf("emit_enemy: Attempting to place enemy at index %d. Current next_enemy_index: %d\n", state.next_enemy_index, state.next_enemy_index)
    
    idx_to_write := state.next_enemy_index
    state.enemies[idx_to_write] = enemy_data        // Copy the data
    state.enemies[idx_to_write].active = true       // Explicitly set active
    
    // fmt.printf("emit_enemy: Enemy at index %d set active. Pos: {%f, %f}, Size: %f, Color: {%f,%f,%f,%f}\n", 
    //    idx_to_write, 
    //    state.enemies[idx_to_write].pos.x, state.enemies[idx_to_write].pos.y, 
    //    state.enemies[idx_to_write].size,
    //    state.enemies[idx_to_write].color.r, state.enemies[idx_to_write].color.g,
    //    state.enemies[idx_to_write].color.b, state.enemies[idx_to_write].color.a)

    state.next_enemy_index = (state.next_enemy_index + 1) % MAX_ENEMIES
}

spawn_enemy :: proc(current_ortho_width: f32, current_ortho_height: f32, player_pos: m.vec2) {
    context = runtime.default_context()
    
    start_pos: m.vec2
    valid_spawn_found := false

    for attempt in 0..<ENEMY_MAX_SPAWN_ATTEMPTS {
        // 1. Choose a side to spawn near (0: top, 1: bottom, 2: left, 3: right)
        side := rand.int31() % 4 

        // 2. Calculate a random position within the border region of that side
        random_depth := rand.float32() * ENEMY_SPAWN_BORDER_FRACTION // 0.0 to BORDER_FRACTION

        switch side {
        case 0: // Top border
            start_pos.y = current_ortho_height * (1.0 - random_depth) // From edge inwards
            start_pos.x = (rand.float32() * 2.0 - 1.0) * current_ortho_width 
        case 1: // Bottom border
            start_pos.y = -current_ortho_height * (1.0 - random_depth)
            start_pos.x = (rand.float32() * 2.0 - 1.0) * current_ortho_width
        case 2: // Left border
            start_pos.x = -current_ortho_width * (1.0 - random_depth)
            start_pos.y = (rand.float32() * 2.0 - 1.0) * current_ortho_height
        case 3: // Right border
            start_pos.x = current_ortho_width * (1.0 - random_depth)
            start_pos.y = (rand.float32() * 2.0 - 1.0) * current_ortho_height
        }

        // 3. Ensure the position is not too close to the player
        dist_sq_to_player := m.len_sq_vec2(start_pos - player_pos)
        if dist_sq_to_player >= ENEMY_MIN_SPAWN_DIST_FROM_PLAYER_SQ {
            valid_spawn_found = true
            break // Found a good spot
        }
    }

    if !valid_spawn_found {
        // Fallback: If too many attempts, just spawn at a default "safe" corner or edge
        // This prevents freezing if conditions are too restrictive.
        // For simplicity, let's pick top-left of the spawnable border.
        // A more robust game might have other fallback strategies.
        fmt.printf("spawn_enemy: WARNING - Could not find a suitable spawn point after %d attempts. Using fallback.\n", ENEMY_MAX_SPAWN_ATTEMPTS)
        start_pos.y = current_ortho_height * (1.0 - ENEMY_SPAWN_BORDER_FRACTION * 0.5) // Mid-border top
        start_pos.x = -current_ortho_width * (1.0 - ENEMY_SPAWN_BORDER_FRACTION * 0.5) // Mid-border left
        // Or, you could even decide not to spawn an enemy this cycle.
    }
    
    start_vel: m.vec2 = {0.0, 0.0} 
    base_grunt_rgb := m.vec3{0.9, 0.1, 0.7} 
    grunt_color := m.vec4{base_grunt_rgb.r, base_grunt_rgb.g, base_grunt_rgb.b, ENEMY_BASE_ALPHA}
    initial_wander_angle := rand.float32() * m.TAU
    initial_wander_vector := m.angle_to_vec2(initial_wander_angle)

 grunt := Enemy {
        pos = start_pos,
        vel = start_vel,
        color = grunt_color, 
        target_size = ENEMY_GRUNT_SCALE,                               
        current_size = ENEMY_GRUNT_SCALE * ENEMY_INITIAL_SCALE_FACTOR, 
        grow_timer = ENEMY_GROW_DURATION,                              
        is_growing = true,                                             
        rotation = rand.float32() * m.TAU, 
        angular_vel = (rand.float32_range(-1.0, 1.0)) * ENEMY_MAX_ANGULAR_SPEED, 
        active = false,
        // MODIFIED: Initialize wander fields
        current_wander_vector = initial_wander_vector,
        wander_timer = rand.float32_range(0.0, ENEMY_WANDER_DIRECTION_CHANGE_INTERVAL), // Stagger initial changes
    }


    emit_enemy(grunt)
    fmt.printf("spawn_enemy: Spawning enemy -> Pos: %v, InitialSize: %f, TargetSize: %f, Color: %v\n", 
        grunt.pos, grunt.current_size, grunt.target_size, grunt.color)
}

update_and_instance_enemies :: proc(dt: f32) -> int {
    context = runtime.default_context()
    live_enemy_count := 0
    player_pos := state.player_pos // Get player's current position

    for i in 0..<MAX_ENEMIES {
        if !state.enemies[i].active {
            continue
        }

        enemy := &state.enemies[i]
        if enemy.is_growing {
            enemy.grow_timer -= dt
            if enemy.grow_timer <= 0.0 {
                enemy.current_size = enemy.target_size
                enemy.is_growing = false
                enemy.grow_timer = 0.0 // Clamp timer
            } else {
                // Calculate growth progress (0.0 at start, 1.0 at end of growth)
                progress := 1.0 - (enemy.grow_timer / ENEMY_GROW_DURATION)
                progress = math.clamp(progress, 0.0, 1.0) // Ensure progress is [0,1]
                
                initial_actual_size := enemy.target_size * ENEMY_INITIAL_SCALE_FACTOR
                enemy.current_size = m.lerp(initial_actual_size, enemy.target_size, progress)
            }
        }
        // --- ROTATION LOGIC (NEW) ---
        enemy.rotation += enemy.angular_vel * dt;
        // Optional: Keep rotation within 0 to TAU (2*PI) range
        if enemy.rotation > m.TAU { enemy.rotation -= m.TAU }
        if enemy.rotation < 0    { enemy.rotation += m.TAU }        
        // --- MOVEMENT LOGIC START ---
        enemy.wander_timer -= dt
        if enemy.wander_timer <= 0.0 {
            new_wander_angle := rand.float32() * m.TAU
            enemy.current_wander_vector = m.angle_to_vec2(new_wander_angle)
            enemy.wander_timer = ENEMY_WANDER_DIRECTION_CHANGE_INTERVAL + rand.float32_range(-0.2, 0.2) // Add some slight variance to interval
        }
        direction_to_player_strict := player_pos - enemy.pos

        final_direction := direction_to_player_strict // Start with direct path to player
        // Check if the enemy is already at the player (or very close) to avoid NaN/Inf from normalization
        // and to prevent division by zero if using len_vec2 directly for normalization.
        // m.len_sq_vec2 is good here as it avoids a sqrt.
        dist_sq_to_player := m.len_sq_vec2(direction_to_player_strict)

        if dist_sq_to_player > 0.001 { // Threshold to prevent issues if enemy is on top of player
            // Normalize the direction vector
            // m.norm_vec2 should handle zero-length vectors gracefully by returning a zero vector,
            // but the check above is a good practice.
            normalized_strict_direction := m.norm_vec2(direction_to_player_strict)
            final_direction = normalized_strict_direction + (enemy.current_wander_vector * ENEMY_WANDER_INFLUENCE)
        } 
        // Normalize the combined direction to maintain consistent speed influence
        // (unless final_direction became a zero vector, e.g. if player_pos == enemy.pos and wander is zero)
        if dist_sq_to_player > 0.00001 { // Check if final_direction is not zero
            normalized_final_direction := m.norm_vec2(final_direction)
            enemy.vel = normalized_final_direction * ENEMY_GRUNT_SPEED
        } else if m.len_sq_vec2(direction_to_player_strict) > 0.00001 {
            // Fallback if final_direction was zero (e.g. wander perfectly opposed strict direction)
            // but enemy is not yet at player. Just move directly to player.
            enemy.vel = m.norm_vec2(direction_to_player_strict) * ENEMY_GRUNT_SPEED
        } else {
            enemy.vel = m.vec2_zero() // Stop if at or very close to the player and no clear direction
        }
        // --- MOVEMENT LOGIC END ---
        
        enemy.pos += enemy.vel * dt 
        
        if live_enemy_count < MAX_ENEMIES {
            inst := &state.enemy_instance_data[live_enemy_count]
            inst.instance_pos = enemy.pos
            inst.instance_size = enemy.current_size // MODIFIED: Use current_size for rendering
            inst.instance_rotation = enemy.rotation // Still passing rotation, even if not visually used by simple square
            inst.instance_color = enemy.color 
            live_enemy_count += 1
        }
    }
    return live_enemy_count
}

frame :: proc "c" () {
   context = runtime.default_context()
    width := sapp.widthf(); height := sapp.heightf(); aspect := width / height
    current_time := f32(sapp.frame_count()) / 60.0
    delta_time := f32(sapp.frame_duration()); delta_time = math.min(delta_time, 1.0/15.0);

  // --- Player Update (existing code) ---
    state.rmb_cooldown_timer = math.max(0.0, state.rmb_cooldown_timer - delta_time)
    accel_input := m.vec2_zero(); if state.key_w_down {accel_input.y+=1.0}; if state.key_s_down {accel_input.y-=1.0}; if state.key_a_down {accel_input.x-=1.0}; if state.key_d_down {accel_input.x+=1.0};
    if m.len_sq_vec2(accel_input) > 0.001 {accel_input=m.norm_vec2(accel_input)}; final_accel := accel_input*PLAYER_ACCELERATION; if state.key_s_down && !state.key_w_down && accel_input.y < -0.5 { final_accel *= PLAYER_REVERSE_FACTOR };
    state.player_vel += final_accel*delta_time; damping_factor := math.max(0.0, 1.0-PLAYER_DAMPING*delta_time); state.player_vel *= damping_factor; if m.len_sq_vec2(state.player_vel) > f32(PLAYER_MAX_SPEED*PLAYER_MAX_SPEED) {state.player_vel=m.norm_vec2(state.player_vel)*PLAYER_MAX_SPEED}; state.player_pos += state.player_vel*delta_time;
	can_fire_rmb := state.rmb_cooldown_timer <= 0.0; rmb_pressed_this_frame := state.rmb_down && !state.previous_rmb_down; if rmb_pressed_this_frame && can_fire_rmb { spawn_swirling_charge(); if BLACKHOLE_COOLDOWN_DURATION > 0.0 { state.rmb_cooldown_timer=BLACKHOLE_COOLDOWN_DURATION } }; state.previous_rmb_down=state.rmb_down;
    
    // --- Enemy Spawning Logic (MODIFIED) ---
    state.enemy_spawn_timer -= delta_time
    if state.enemy_spawn_timer <= 0.0 {
        current_ortho_width := ORTHO_HEIGHT * aspect // Calculate current ortho width
        spawn_enemy(current_ortho_width, ORTHO_HEIGHT, state.player_pos) 
        state.enemy_spawn_timer = ENEMY_SPAWN_INTERVAL  // Reset timer
    }
    // --- End Enemy Spawning Logic ---

    state.bg_fs_params={tick=current_time, resolution={width,height}, bg_option=1}; 
    state.player_fs_params={tick=current_time, resolution={width,height}}; 
    state.particle_fs_params={tick=current_time};
    state.enemy_fs_params={tick=current_time}; 

    ortho_width_vp := ORTHO_HEIGHT*aspect; // Renamed to avoid conflict if spawn_enemy was called elsewhere
    proj := m.ortho(-ortho_width_vp,ortho_width_vp,-ORTHO_HEIGHT,ORTHO_HEIGHT,-1.0,1.0); 
    view := m.identity(); view_proj := m.mul(proj,view); 
    
    scale_mat := m.scale(m.vec3{PLAYER_SCALE,PLAYER_SCALE,1.0}); translate_mat := m.translate(m.vec3{state.player_pos.x,state.player_pos.y,0.0}); model := m.mul(translate_mat,scale_mat); 
    state.player_vs_params.mvp=m.mul(view_proj,model); 
    
    state.particle_vs_params.view_proj=view_proj;
    state.enemy_vs_params.view_proj=view_proj; 

    state.num_active_particles = update_and_instance_particles(delta_time);
    state.num_active_enemies = update_and_instance_enemies(delta_time); 
    
    if sapp.frame_count() > 0 && sapp.frame_count() % 300 == 0 { // Print every 5 seconds approx, skip frame 0
       fmt.printf("Frame %d: Active Enemies for Drawing: %d\n", sapp.frame_count(), state.num_active_enemies)
    }

    sg.begin_pass({action=state.pass_action, swapchain=sglue.swapchain() });
    
    sg.apply_pipeline(state.bg_pip); sg.apply_bindings(state.bind); sg.apply_uniforms(UB_bg_fs_params, sg.Range{ptr=&state.bg_fs_params, size=size_of(Bg_Fs_Params)}); sg.draw(0,4,1);
    
    sg.apply_pipeline(state.player_pip); sg.apply_bindings(state.bind); sg.apply_uniforms(UB_Player_Vs_Params, sg.Range{ptr=&state.player_vs_params, size=size_of(Player_Vs_Params)}); sg.apply_uniforms(UB_Player_Fs_Params, sg.Range{ptr=&state.player_fs_params, size=size_of(Player_Fs_Params)}); sg.draw(0,4,1);
	
    if state.num_active_particles > 0 {
		sg.apply_pipeline(state.particle_pip); sg.apply_bindings(state.particle_bind); sg.update_buffer(state.particle_instance_vbo, sg.Range{ptr=rawptr(&state.particle_instance_data[0]), size=uint(state.num_active_particles)*size_of(Particle_Instance_Data)});
		sg.apply_uniforms(UB_particle_vs_params, sg.Range{ptr=&state.particle_vs_params, size=size_of(Particle_Vs_Params)}); sg.apply_uniforms(UB_particle_fs_params, sg.Range{ptr=&state.particle_fs_params, size=size_of(Particle_Fs_Params)});
		sg.draw(0, 4, state.num_active_particles);
	}

    if state.num_active_enemies > 0 {
        if sapp.frame_count() > 0 && sapp.frame_count() % 60 == 1 { // Print once a second, skip frame 0
           fmt.printf("Frame %d: Attempting to draw %d enemies.\n", sapp.frame_count(), state.num_active_enemies);
           fmt.printf("Enemy 0 instance data: pos={%f,%f}, size=%f, rot=%f, color={%.1f,%.1f,%.1f,%.1f}\n", 
               state.enemy_instance_data[0].instance_pos.x, state.enemy_instance_data[0].instance_pos.y,
               state.enemy_instance_data[0].instance_size,
               state.enemy_instance_data[0].instance_rotation, // Added rotation
               state.enemy_instance_data[0].instance_color.r, state.enemy_instance_data[0].instance_color.g,
               state.enemy_instance_data[0].instance_color.b, state.enemy_instance_data[0].instance_color.a);
        }
        sg.apply_pipeline(state.enemy_pip)
        sg.apply_bindings(state.enemy_bind) 
        sg.update_buffer(state.enemy_instance_vbo, sg.Range{ptr=rawptr(&state.enemy_instance_data[0]), size=uint(state.num_active_enemies)*size_of(Enemy_Instance_Data)})
        sg.apply_uniforms(UB_enemy_vs_params, sg.Range{ptr=&state.enemy_vs_params, size=size_of(Enemy_Vs_Params)}) 
        sg.apply_uniforms(UB_enemy_fs_params, sg.Range{ptr=&state.enemy_fs_params, size=size_of(Enemy_Fs_Params)}) 
        sg.draw(0, 4, state.num_active_enemies)
    }

    sg.end_pass(); sg.commit();
}

cleanup :: proc "c" () { context=runtime.default_context(); sg.shutdown(); }
main :: proc () { sapp.run({ init_cb=init, frame_cb=frame, cleanup_cb=cleanup, event_cb=event, width=800, height=600, sample_count=4, window_title="GeoWars Odin - Enemies Debug Spawn", icon={sokol_default=true}, logger={func=slog.func} }) }