// File: geowars.odin (Revised for Grunt-Player Collision Damage)
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
MAX_ENEMIES :: 128 
MAX_BLACKHOLES :: 64 

// --- Constants ---
ORTHO_HEIGHT :: 1.5
PLAYER_ACCELERATION      :: 15.0
PLAYER_REVERSE_FACTOR    :: 0.5
PLAYER_DAMPING           :: 2.5
PLAYER_MAX_SPEED         :: 7.0
PLAYER_SCALE             :: 0.1
PLAYER_BOUNCE_BOUNDARY_OFFSET :: 0.1
PLAYER_CORE_SHADER_RADIUS :: 0.04
PLAYER_UV_SPACE_EXTENT   :: 0.5
PLAYER_CORE_WORLD_RADIUS :: (PLAYER_CORE_SHADER_RADIUS / PLAYER_UV_SPACE_EXTENT) * PLAYER_SCALE
PLAYER_BOUNCE_DAMPING_FACTOR :: 1.05
PLAYER_MAX_HP_VALUE      :: 4 // From previous implementation
PLAYER_INVULNERABILITY_DURATION :: 0.75 // From previous implementation for particle hits
PARTICLE_DAMAGE_VALUE    :: 1 // From previous (RMB particle damage)
ENEMY_GRUNT_DAMAGE_VALUE :: 1 // <<< NEW: Damage grunt deals to player

// Black Hole (RMB) Constants
BLACKHOLE_COOLDOWN_DURATION :: 1.0 
MAX_SPIN_SPEED           :: f32(m.PI * 2.0)
SWIRL_CHARGE_DURATION_BASE  : f32 : 1.8
SWIRL_CHARGE_DURATION_RAND  : f32 : 0.5
SWIRL_RADIUS_SPAWN          : f32 : 0.05 
SWIRL_SPEED_ORBITAL_BASE    : f32 : 3.5  
SWIRL_SPEED_INWARD_INITIAL  : f32 : -0.1 
SWIRL_PARTICLE_SIZE_BASE    : f32 : 0.03 
SWIRL_PARTICLE_SIZE_RAND    : f32 : 0.01
SWIRL_CLOUD_TRAVEL_FACTOR   : f32 : 0.0  
SWIRL_CLOUD_BASE_PUSH       : f32 : 0.15 


// *** Explosion Constants (after swirl) ***
EXPLOSION_LIFETIME_BASE : f32 : 1.0
EXPLOSION_LIFETIME_RAND : f32 : 0.8
EXPLOSION_SPEED_BASE    : f32 : 6.0  
EXPLOSION_SPEED_RAND    : f32 : 4.0  
EXPLOSION_PARTICLE_SPIN : f32 : 0.0  

// Black Hole Projectile (LMB) Constants
PROJECTILE_BLACKHOLE_COOLDOWN :: 0.25 
PROJECTILE_BLACKHOLE_INITIAL_SPEED :: 5.0 
PROJECTILE_BLACKHOLE_LIFETIME :: 3.0 
PROJECTILE_BLACKHOLE_SCALE :: 0.12
PROJECTILE_BLACKHOLE_ANGULAR_VELOCITY :: m.PI * 1.5


// --- Enemy Constants ---
ENEMY_GRUNT_SCALE :: 0.2
ENEMY_GRUNT_SPEED :: 0.5 
ENEMY_SPAWN_INTERVAL :: 0.5
ENEMY_SPAWN_BORDER_FRACTION :: 0.5 
ENEMY_MIN_SPAWN_DIST_FROM_PLAYER_SQ :: 0.5 * 0.5 
ENEMY_MAX_SPAWN_ATTEMPTS :: 10
ENEMY_INITIAL_SCALE_FACTOR :: 0.1 
ENEMY_GROW_DURATION :: 1.0     
ENEMY_MAX_ANGULAR_SPEED :: m.PI / 0.7
ENEMY_BASE_ALPHA :: 0.65           
ENEMY_WANDER_INFLUENCE :: 0.35 
ENEMY_WANDER_DIRECTION_CHANGE_INTERVAL :: 1.5 
ENEMY_GRUNT_MAX_HP :: 2
ENEMY_DEATH_ANIM_DURATION :: 1.0  // Duration of the splitting/shrinking animation
ENEMY_DEATH_RECT_SEPARATION_SPEED :: 0.3 // How fast the two parts separate
ENEMY_DEATH_RECT_FINAL_SCALE_FACTOR :: 0.0 // They shrink to nothing
ENEMY_DEATH_QUAD_RENDER_SCALE_MULTIPLIER :: 2.5 // NEW: Quad is 2.5x bigger during death anim

// Enemy Death Particle Constants
LMB_ENEMY_DEATH_PARTICLE_COUNT :: 20
LMB_ENEMY_DEATH_PARTICLE_LIFETIME_BASE :: 0.3
LMB_ENEMY_DEATH_PARTICLE_LIFETIME_RAND :: 0.2
LMB_ENEMY_DEATH_PARTICLE_SPEED_BASE :: 2.5  
LMB_ENEMY_DEATH_PARTICLE_SPEED_RAND :: 1.8
LMB_ENEMY_DEATH_PARTICLE_SIZE_BASE :: 0.025 
LMB_ENEMY_DEATH_PARTICLE_SIZE_RAND :: 0.01
LMB_ENEMY_DEATH_PARTICLE_ANGULAR_VEL_MAX :: m.PI * 0.75

// RMB Enemy Death Particle Constants
RMB_ENEMY_DEATH_PARTICLE_COUNT :: 10 
RMB_ENEMY_DEATH_PARTICLE_LIFETIME_BASE :: 0.25
RMB_ENEMY_DEATH_PARTICLE_LIFETIME_RAND :: 0.15
RMB_ENEMY_DEATH_PARTICLE_SPEED_BASE :: 2.0
RMB_ENEMY_DEATH_PARTICLE_SPEED_RAND :: 1.2
RMB_ENEMY_DEATH_PARTICLE_SIZE_BASE :: 0.015 
RMB_ENEMY_DEATH_PARTICLE_SIZE_RAND :: 0.005
RMB_ENEMY_DEATH_PARTICLE_ANGULAR_VEL_MAX :: m.PI * 0.25
RMB_PARTICLE_COLOR :: m.vec4{0.8, 0.3, 1.0, 0.9} 
RMB_AMMO_REGEN_INTERVAL :: 10.0 // Seconds to regenerate one charge
MAX_RMB_AMMO_CHARGES    :: 2    // Max number of charges player can hold
RMB_AMMO_INDICATOR_PARTICLES_PER_CHARGE :: 16 // Number of visual particles per ammo charge
RMB_AMMO_INDICATOR_ORBIT_RADIUS         :: PLAYER_SCALE * 0.5 // Distance from player center
RMB_AMMO_INDICATOR_ORBIT_SPEED          :: m.PI * 0.8        // Radians per second for the group
RMB_AMMO_INDICATOR_BASE_SIZE            :: 0.018              // Size of each indicator particle
RMB_AMMO_INDICATOR_COLOR                :: m.vec4{0.7, 0.4, 1.0, 0.75} // Distinct bright purple, slightly transparent
RMB_AMMO_INDICATOR_SELF_SPIN_SPEED      :: m.PI * 0.6         // How fast each particle spins on its own axis

    


// Rendering Internals
vertex_stride :: size_of(f32) * 7
particle_quad_stride :: size_of(f32) * 4
enemy_quad_stride :: size_of(f32) * 4 
blackhole_quad_stride :: size_of(f32) * 4

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
	rotation:         f32,         // For ammo indicators, this will be their orbit angle around the player
	angular_vel:      f32,         // For ammo indicators, this will be their self-spin
    charge_center_pos: m.vec2, 
	is_burst_particle: bool,
    is_swirling_charge: bool, 
    is_ammo_indicator: bool, // <<< ADD THIS NEW FLAG
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

Blackhole_Projectile :: struct {
    pos: m.vec2,
    vel: m.vec2,
    size: f32,
    rotation: f32,
    angular_vel: f32,
    life_remaining: f32,
    life_max: f32,
    active: bool,
}

Blackhole_Instance_Data :: struct #align(16) {
    using _: struct #packed {
        instance_pos_size_rot: m.vec4, 
        instance_color: m.vec4,        
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
    hp: i32, 
    active: bool,
    current_wander_vector: m.vec2,
    wander_timer: f32,
    is_dying: bool,
    dying_timer: f32,
    death_rect_offset: f32,
}

Enemy_Instance_Data :: struct #align(16) {
    using _: struct #packed {
        instance_pos: m.vec2,         
        instance_main_rotation: f32,  
        instance_visual_scale: f32,   
        instance_color: m.vec4,       
        instance_effect_params: m.vec4,
    },
}


// --- Global State ---
state: struct {
    pass_action: sg.Pass_Action, bind: sg.Bindings,
    bg_pip: sg.Pipeline, player_pip: sg.Pipeline, particle_pip: sg.Pipeline, enemy_pip: sg.Pipeline, blackhole_pip: sg.Pipeline,
    bg_fs_params: Bg_Fs_Params, player_vs_params: Player_Vs_Params, player_fs_params: Player_Fs_Params,
    particle_vs_params: Particle_Vs_Params, particle_fs_params: Particle_Fs_Params,
    enemy_vs_params: Enemy_Vs_Params, enemy_fs_params: Enemy_Fs_Params, 
    blackhole_vs_params: Blackhole_Vs_Params, blackhole_fs_params: Blackhole_Fs_Params,

    player_pos: m.vec2, player_vel: m.vec2,
    player_hp: int, player_max_hp: int, // Player health
    player_invulnerable_timer: f32,    // Invulnerability timer
    player_defeated_message_shown: bool, // To show defeat message only once

    key_w_down: bool, key_s_down: bool, key_a_down: bool, key_d_down: bool,
    
    rmb_down: bool, previous_rmb_down: bool, rmb_cooldown_timer: f32,
    lmb_down: bool, previous_lmb_down: bool, lmb_cooldown_timer: f32,

    current_rmb_ammo_charges: int,
    rmb_ammo_regen_timer: f32,

    mouse_screen_pos: m.vec2, 

	particles: [MAX_PARTICLES]Particle, particle_instance_data: [MAX_PARTICLES]Particle_Instance_Data,
	particle_quad_vbo: sg.Buffer, particle_instance_vbo: sg.Buffer, particle_bind: sg.Bindings,
	next_particle_index: int, num_active_particles: int,

    blackholes: [MAX_BLACKHOLES]Blackhole_Projectile, blackhole_instance_data: [MAX_BLACKHOLES]Blackhole_Instance_Data,
    blackhole_instance_vbo: sg.Buffer, blackhole_bind: sg.Bindings,
    next_blackhole_index: int, num_active_blackholes: int,

    enemies: [MAX_ENEMIES]Enemy, enemy_instance_data: [MAX_ENEMIES]Enemy_Instance_Data,
    enemy_instance_vbo: sg.Buffer, enemy_bind: sg.Bindings,
    next_enemy_index: int, num_active_enemies: int,
    enemy_spawn_timer: f32, 
    
}

// =============================================================================
// END: Package-Level Declarations
// =============================================================================


init :: proc "c" () {
    context = runtime.default_context()
    sg.setup({ pipeline_pool_size=12, buffer_pool_size=12, shader_pool_size=12, environment=sglue.environment(), logger={func=slog.func} })
    fmt.printf("--- Init Start ---\n")
    state.pass_action = {colors = {0={load_action = .DONTCARE}}}
    vertices := [?]f32 { -1,-1,0,0,0,0,0, 1,-1,0,1,0,0,0, -1,1,0,0,1,0,0, 1,1,0,1,1,0,0 }
    state.bind.vertex_buffers[0] = sg.make_buffer({ label="shared-quad-vertices", data=sg.Range{ptr=&vertices[0], size=size_of(vertices)}})
	
    particle_quad_verts := [?]f32{ -0.5,-0.5,0,0, 0.5,-0.5,1,0, -0.5,0.5,0,1, 0.5,0.5,1,1 }
	state.particle_quad_vbo = sg.make_buffer({ label="particle-quad-base", data=sg.Range{ptr=&particle_quad_verts[0], size=size_of(particle_quad_verts)}})
    state.particle_instance_vbo = sg.make_buffer({ label="particle-inst", size=MAX_PARTICLES*size_of(Particle_Instance_Data), type=.VERTEXBUFFER, usage=.STREAM })
    
    state.enemy_instance_vbo = sg.make_buffer({ label="enemy-inst", size=MAX_ENEMIES*size_of(Enemy_Instance_Data), type=.VERTEXBUFFER, usage=.STREAM })
    state.blackhole_instance_vbo = sg.make_buffer({ label="blackhole-inst", size=MAX_BLACKHOLES*size_of(Blackhole_Instance_Data), type=.VERTEXBUFFER, usage=.STREAM })


    bg_shd := sg.make_shader(bg_shader_desc(sg.query_backend()))
    player_shd := sg.make_shader(player_shader_desc(sg.query_backend()))
    particle_shd := sg.make_shader(particle_shader_desc(sg.query_backend()))
    enemy_shd := sg.make_shader(enemy_shader_desc(sg.query_backend())) 
    blackhole_shd := sg.make_shader(blackhole_shader_desc(sg.query_backend()))

    state.bg_pip = sg.make_pipeline({ label="bg-pip", shader=bg_shd, layout={buffers={0={stride=vertex_stride}},attrs={ATTR_bg_position={format=.FLOAT2}}}, primitive_type=.TRIANGLE_STRIP})
    state.player_pip = sg.make_pipeline({ label="player-pip", shader=player_shd, layout={buffers={0={stride=vertex_stride}},attrs={ATTR_player_position={format=.FLOAT2}}}, primitive_type=.TRIANGLE_STRIP, colors={0={blend={enabled=true, src_factor_rgb=.SRC_ALPHA,dst_factor_rgb=.ONE_MINUS_SRC_ALPHA}}}, depth={write_enabled=false, compare=.ALWAYS} })
    
    state.particle_pip = sg.make_pipeline({ label="particle-pip", shader=particle_shd,
        layout={ buffers={0={stride=particle_quad_stride,step_func=.PER_VERTEX}, 1={stride=size_of(Particle_Instance_Data),step_func=.PER_INSTANCE}}, 
                 attrs={ATTR_particle_quad_pos={buffer_index=0,offset=0,format=.FLOAT2}, ATTR_particle_quad_uv={buffer_index=0,offset=8,format=.FLOAT2}, 
                        ATTR_particle_instance_pos_size_rot={buffer_index=1,offset=0,format=.FLOAT4}, ATTR_particle_instance_color={buffer_index=1,offset=16,format=.FLOAT4}} },
        primitive_type=.TRIANGLE_STRIP, colors={0={blend={enabled=true, src_factor_rgb=.SRC_ALPHA, dst_factor_rgb=.ONE}}}, depth={write_enabled=false, compare=.ALWAYS}
    })
    if sg.query_pipeline_state(state.particle_pip) != .VALID { fmt.eprintf("!!! CRITICAL: Particle pipeline creation failed!\n"); }

    state.blackhole_pip = sg.make_pipeline({ label="blackhole-pip", shader=blackhole_shd,
        layout={ buffers={0={stride=blackhole_quad_stride,step_func=.PER_VERTEX}, 1={stride=size_of(Blackhole_Instance_Data),step_func=.PER_INSTANCE}}, 
                 attrs={ATTR_blackhole_quad_pos={buffer_index=0,offset=0,format=.FLOAT2}, ATTR_blackhole_quad_uv={buffer_index=0,offset=8,format=.FLOAT2}, 
                        ATTR_blackhole_instance_pos_size_rot={buffer_index=1,offset=0,format=.FLOAT4}, ATTR_blackhole_instance_color={buffer_index=1,offset=16,format=.FLOAT4}} },
        primitive_type=.TRIANGLE_STRIP, colors={0={blend={enabled=true, src_factor_rgb=.SRC_ALPHA, dst_factor_rgb=.ONE_MINUS_SRC_ALPHA}}}, depth={write_enabled=false, compare=.ALWAYS} 
    })
    if sg.query_pipeline_state(state.blackhole_pip) != .VALID { fmt.eprintf("!!! CRITICAL: Blackhole pipeline creation failed!\n"); }
    else { fmt.printf("--- Blackhole pipeline created successfully ---\n"); }


    state.enemy_pip = sg.make_pipeline({ 
        label="enemy-pip", 
        shader=enemy_shd,
        layout={ 
            buffers={
                0={stride=enemy_quad_stride, step_func=.PER_VERTEX},
                1={stride=size_of(Enemy_Instance_Data), step_func=.PER_INSTANCE}
            },
            attrs={ 
                ATTR_enemy_quad_pos_in={buffer_index=0,offset=0,format=.FLOAT2}, 
                ATTR_enemy_quad_uv_in={buffer_index=0,offset=8,format=.FLOAT2},
                ATTR_enemy_instance_pos_vs_in={buffer_index=1,offset=0,format=.FLOAT2}, // <<< CORRECTED HERE
                ATTR_enemy_instance_main_rotation_vs_in={buffer_index=1,offset=8,format=.FLOAT},
                ATTR_enemy_instance_visual_scale_vs_in={buffer_index=1,offset=12,format=.FLOAT},
                ATTR_enemy_instance_color_vs_in={buffer_index=1,offset=16,format=.FLOAT4}, 
                ATTR_enemy_instance_effect_params_vs_in={buffer_index=1,offset=32,format=.FLOAT4},
            }
        },
        primitive_type=.TRIANGLE_STRIP, 
        colors={0={blend={enabled=true, src_factor_rgb=.SRC_ALPHA, dst_factor_rgb=.ONE_MINUS_SRC_ALPHA}}}, 
        depth={write_enabled=false, compare=.ALWAYS}
    })
    if sg.query_pipeline_state(state.enemy_pip) != .VALID { fmt.eprintf("!!! CRITICAL: Enemy pipeline creation failed!\n"); }

	state.particle_bind = sg.Bindings{ vertex_buffers = { 0=state.particle_quad_vbo, 1=state.particle_instance_vbo } }
    state.enemy_bind = sg.Bindings{ vertex_buffers = { 0=state.particle_quad_vbo, 1=state.enemy_instance_vbo } } 
    state.blackhole_bind = sg.Bindings{ vertex_buffers = {0=state.particle_quad_vbo, 1=state.blackhole_instance_vbo } }


	state.next_particle_index = 0; state.num_active_particles = 0;
    state.next_enemy_index = 0; state.num_active_enemies = 0;
    state.next_blackhole_index = 0; state.num_active_blackholes = 0;

    state.player_pos = {0,0}; state.player_vel = {0,0};
    state.player_max_hp = PLAYER_MAX_HP_VALUE;
    state.player_hp = state.player_max_hp;
    state.player_invulnerable_timer = 0.0;
    state.player_defeated_message_shown = false;

    state.rmb_down=false; state.previous_rmb_down=false; state.rmb_cooldown_timer=0.0;
    state.lmb_down=false; state.previous_lmb_down=false; state.lmb_cooldown_timer=0.0;
    state.mouse_screen_pos = {0,0};

    state.current_rmb_ammo_charges = 0; // Start with 0 charges, or MAX_RMB_AMMO_CHARGES for full
    state.rmb_ammo_regen_timer = RMB_AMMO_REGEN_INTERVAL/10; // Timer for the first charge


    state.enemy_spawn_timer = rand.float32_range(2.0, 3.0)
    fmt.printf("--- Init Complete ---\n")
}

event :: proc "c" (event: ^sapp.Event) {
    context = runtime.default_context()
    #partial switch event.type {
    case .KEY_DOWN: #partial switch event.key_code { case .W: state.key_w_down=true; case .S: state.key_s_down=true; case .A: state.key_a_down=true; case .D: state.key_d_down=true; case .ESCAPE: sapp.request_quit(); }
    case .KEY_UP: #partial switch event.key_code { case .W: state.key_w_down=false; case .S: state.key_s_down=false; case .A: state.key_a_down=false; case .D: state.key_d_down=false; }
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

// --- Particle System ---
emit_particle :: proc(part: Particle) {
	context = runtime.default_context()
	state.particles[state.next_particle_index] = part
	state.particles[state.next_particle_index].active = true
	state.next_particle_index = (state.next_particle_index + 1) % MAX_PARTICLES
}

spawn_swirling_charge :: proc() { // RMB Ability
	context = runtime.default_context()
    if state.player_hp <= 0 { return; } 
    charge_spawn_center := state.player_pos 
	charge_duration := SWIRL_CHARGE_DURATION_BASE + rand.float32() * SWIRL_CHARGE_DURATION_RAND 
    start_size_val_base := SWIRL_PARTICLE_SIZE_BASE
    start_size_val_rand := SWIRL_PARTICLE_SIZE_RAND
	start_color := m.vec4{0.8, 0.3, 1.0, 1.0}
    cloud_travel_vel: m.vec2 = {0, 0} 
    player_speed_sq := m.len_sq_vec2(state.player_vel)
    player_front_dir := m.vec2{0,1} 
    if m.len_sq_vec2(state.player_vel) > 0.001 { player_front_dir = m.norm_vec2(state.player_vel) }
    cloud_travel_vel = player_front_dir * SWIRL_CLOUD_BASE_PUSH;
    if player_speed_sq > 0.001 && SWIRL_CLOUD_TRAVEL_FACTOR > 0.0 { cloud_travel_vel += state.player_vel * SWIRL_CLOUD_TRAVEL_FACTOR; }
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
            charge_center_pos=charge_spawn_center, is_burst_particle=false, is_swirling_charge=true, is_ammo_indicator=false, active=false, 
		})
	}
}

update_and_instance_particles :: proc(dt: f32) -> int {
    context = runtime.default_context()
    live_particle_count := 0
    
    for i in 0..<MAX_PARTICLES {
        if !state.particles[i].active { continue }
        p := &state.particles[i]

        if p.is_ammo_indicator {
            // --- Update Orbiting Ammo Indicator Particles ---
            // p.rotation stores its current orbit angle around the player.
            // p.angular_vel is its self-spin.
            
            p.rotation += RMB_AMMO_INDICATOR_ORBIT_SPEED * dt; // Update orbit angle
            if p.rotation > m.TAU { p.rotation -= m.TAU; }
            else if p.rotation < 0 { p.rotation += m.TAU; }

            orbit_direction := m.angle_to_vec2(p.rotation);
            p.pos = state.player_pos + orbit_direction * RMB_AMMO_INDICATOR_ORBIT_RADIUS;
            
            // Update self-spin (visual rotation of the particle quad itself)
            p.angular_vel = p.angular_vel; // Keep its assigned self-spin or update if needed
            // The actual rotation for instancing will be p.rotation + its self-spin component if desired
            // For simplicity, let's use a temporary variable for the visual rotation if self-spin is complex.
            // Let's assume p.angular_vel is the self-spin speed, and we accumulate it.
            // We need another field if p.rotation is *only* for orbit. Let's reuse angular_vel for spin and store current self-rotation in charge_center_pos.y for now
            
            p.charge_center_pos.y += p.angular_vel * dt; // Use charge_center_pos.y to accumulate self-rotation
            if p.charge_center_pos.y > m.TAU {p.charge_center_pos.y -= m.TAU;}
            if p.charge_center_pos.y < 0 {p.charge_center_pos.y += m.TAU;}


            // These particles don't expire by time, color/alpha is constant
            p.color = RMB_AMMO_INDICATOR_COLOR;
            p.size = RMB_AMMO_INDICATOR_BASE_SIZE;
            // No life_remaining countdown for these.
            // --- End Update Orbiting Ammo Indicator Particles ---
        } else {
            // --- Regular Particle Update Logic ---
            p.pos += p.vel * dt;
            // Regular particle self-rotation:
            p.rotation += p.angular_vel * dt; 
            if p.rotation > m.TAU { p.rotation -= m.TAU; } else if p.rotation < 0 { p.rotation += m.TAU; }
            
            p.life_remaining -= dt;

            if p.is_swirling_charge && p.life_remaining <= 0.0 {
                p.is_swirling_charge = false;
                new_life := EXPLOSION_LIFETIME_BASE + rand.float32() * EXPLOSION_LIFETIME_RAND;
                p.life_remaining = new_life;
                p.life_max = new_life;    
                explosion_center := p.charge_center_pos + p.cloud_travel_vel * p.swirl_duration;
                relative_pos := p.pos - explosion_center;
                outward_dir : m.vec2 = {rand.float32() * 2.0 - 1.0, rand.float32() * 2.0 - 1.0};
                len_sq := m.len_sq_vec2(relative_pos);
                if len_sq > 0.0001 { outward_dir = m.norm_vec2(relative_pos);
                } else if m.len_sq_vec2(outward_dir) > 0.0001 { outward_dir = m.norm_vec2(outward_dir);
                } else { outward_dir = {0.0, 1.0}; }
                explosion_speed := EXPLOSION_SPEED_BASE + rand.float32() * EXPLOSION_SPEED_RAND;
                p.vel = outward_dir * explosion_speed;
                p.angular_vel = EXPLOSION_PARTICLE_SPIN;
            }

            if !p.is_swirling_charge && p.life_remaining <= 0.0 { 
                p.active = false; 
                continue; 
            }

            life_ratio: f32 = 0.0;
            if p.life_max > 0.0 { life_ratio = math.max(f32(0.0), p.life_remaining / p.life_max); }
            
            if p.is_swirling_charge { 
                p.size = p.start_size; 
                p.color.a = 1.0;      
            } else { // Explosion or burst particles
                p.size = p.start_size * life_ratio * life_ratio; 
                p.color.a = life_ratio * life_ratio; 
            }
            // --- End Regular Particle Update Logic ---
        }
        
        // Instance data common to all active particles
        if live_particle_count < MAX_PARTICLES {
            inst := &state.particle_instance_data[live_particle_count];
            inst.instance_pos=p.pos; 
            inst.instance_size=p.size; 
            // For ammo indicators, use their accumulated self-spin. For others, use their regular rotation.
            if p.is_ammo_indicator {
                inst.instance_rotation = p.charge_center_pos.y; 
            } else {
                inst.instance_rotation = p.rotation;
            }
            inst.instance_color=p.color;
            live_particle_count += 1;
        }
    }
    return live_particle_count
}

spawn_LMB_enemy_death_particles :: proc(pos: m.vec2, base_color: m.vec4) {
	context = runtime.default_context()
	for _ in 0..<LMB_ENEMY_DEATH_PARTICLE_COUNT {
		angle := rand.float32() * m.TAU
		dir := m.angle_to_vec2(angle)
		speed := LMB_ENEMY_DEATH_PARTICLE_SPEED_BASE + rand.float32() * LMB_ENEMY_DEATH_PARTICLE_SPEED_RAND
		life := LMB_ENEMY_DEATH_PARTICLE_LIFETIME_BASE + rand.float32() * LMB_ENEMY_DEATH_PARTICLE_LIFETIME_RAND
		size := LMB_ENEMY_DEATH_PARTICLE_SIZE_BASE + rand.float32() * LMB_ENEMY_DEATH_PARTICLE_SIZE_RAND
		angular_vel := rand.float32_range(-1.0, 1.0) * LMB_ENEMY_DEATH_PARTICLE_ANGULAR_VEL_MAX
		particle_color := base_color;
		particle_color.r = math.min(base_color.r * 1.2 + 0.2, 1.0);
		particle_color.g = math.min(base_color.g * 1.2 + 0.2, 1.0);
		particle_color.b = math.min(base_color.b * 1.2 + 0.2, 1.0);
		particle_color.a = 0.85; 
		emit_particle(Particle{
			pos=pos, vel=dir*speed, cloud_travel_vel={0,0}, color=particle_color, size=size, start_size=size,
            life_remaining=life, life_max=life, swirl_duration=0, rotation=rand.float32()*m.TAU, angular_vel=angular_vel,
            charge_center_pos={0,0}, is_burst_particle=true, is_swirling_charge=false, is_ammo_indicator=false, active=false, 
		})
	}
}

spawn_visual_ammo_charge_particles :: proc(charge_slot_index: int) {
    context = runtime.default_context()
    if charge_slot_index < 0 || charge_slot_index >= MAX_RMB_AMMO_CHARGES {
        return;
    }

    // Calculate a base starting angle for this new charge's group of particles
    // This helps to spread them out if multiple charges are gained over time.
    // A more sophisticated approach might assign fixed angular slots per charge.
    base_orbit_angle_offset := (f32(charge_slot_index) / f32(MAX_RMB_AMMO_CHARGES)) * m.TAU;


    for i in 0..<RMB_AMMO_INDICATOR_PARTICLES_PER_CHARGE {
        // Distribute particles within this charge's visual group
        particle_angle_within_group := (f32(i) / f32(RMB_AMMO_INDICATOR_PARTICLES_PER_CHARGE)) * m.TAU;
        
        // The 'rotation' field will store the particle's current orbit angle relative to player
        // The 'angular_vel' will be its self-spin.
        // The 'vel' will be (0,0) as orbit is handled by recalculating 'pos'.
        
        // Store the base orbit angle (relative to player) in p.rotation.
        // The actual world position will be calculated in update_and_instance_particles.
        current_orbit_angle := base_orbit_angle_offset + particle_angle_within_group + (state.rmb_ammo_regen_timer * RMB_AMMO_INDICATOR_ORBIT_SPEED); // Add current time factor for dynamic placement

        emit_particle(Particle{
            pos              = state.player_pos, // Will be updated to orbit
            vel              = {0,0}, // Orbit is handled by directly setting pos
            cloud_travel_vel = {0,0},
            color            = RMB_AMMO_INDICATOR_COLOR,
            size             = RMB_AMMO_INDICATOR_BASE_SIZE,
            start_size       = RMB_AMMO_INDICATOR_BASE_SIZE,
            life_remaining   = 1.0, // Effectively infinite; not used for despawn
            life_max         = 1.0,
            swirl_duration   = 0,
            rotation         = current_orbit_angle, // Stores its current angle in orbit around player
            angular_vel      = rand.float32_range(-1,1) * RMB_AMMO_INDICATOR_SELF_SPIN_SPEED, // Self-spin
            charge_center_pos= m.vec2{f32(charge_slot_index), f32(i)}, // Store charge and particle index in this charge
            is_burst_particle= false,
            is_swirling_charge= false,
            is_ammo_indicator= true, // Mark as an ammo indicator
            active           = false, // emit_particle sets true
        });
    }
     fmt.printf("Spawned visual ammo for charge slot %d\n", charge_slot_index);
}

remove_visual_ammo_charge_particles :: proc(charge_slot_index_to_remove: int) {
    context = runtime.default_context()
    particles_removed_count := 0
    // Iterate through all particles and remove those matching the charge_slot_index
    // We stored charge_slot_index in particle.charge_center_pos.x
    for i in 0..<MAX_PARTICLES {
        p := &state.particles[i];
        if p.active && p.is_ammo_indicator && int(p.charge_center_pos.x) == charge_slot_index_to_remove {
            p.active = false; 
            // Optional: Add a quick shrink/fade animation here before deactivation
            // For now, they just disappear.
            particles_removed_count += 1;
        }
    }
    if particles_removed_count > 0 {
        fmt.printf("Removed %d visual ammo particles for charge slot %d\n", particles_removed_count, charge_slot_index_to_remove);
    }
}

spawn_RMB_enemy_death_particles :: proc(pos: m.vec2) {
	context = runtime.default_context()
	base_death_color := RMB_PARTICLE_COLOR; 
	for _ in 0..<RMB_ENEMY_DEATH_PARTICLE_COUNT {
		angle := rand.float32() * m.TAU
		dir := m.angle_to_vec2(angle)
		speed := RMB_ENEMY_DEATH_PARTICLE_SPEED_BASE + rand.float32() * RMB_ENEMY_DEATH_PARTICLE_SPEED_RAND
		life := RMB_ENEMY_DEATH_PARTICLE_LIFETIME_BASE + rand.float32() * RMB_ENEMY_DEATH_PARTICLE_LIFETIME_RAND
		size := RMB_ENEMY_DEATH_PARTICLE_SIZE_BASE + rand.float32() * RMB_ENEMY_DEATH_PARTICLE_SIZE_RAND
		angular_vel := rand.float32_range(-1.0, 1.0) * RMB_ENEMY_DEATH_PARTICLE_ANGULAR_VEL_MAX
		particle_color := base_death_color;
		particle_color.r = math.clamp(base_death_color.r + rand.float32_range(-0.1, 0.1), 0.5, 1.0);
		particle_color.g = math.clamp(base_death_color.g + rand.float32_range(-0.1, 0.1), 0.2, 0.8);
		particle_color.b = math.clamp(base_death_color.b + rand.float32_range(-0.1, 0.1), 0.7, 1.0);
		particle_color.a = rand.float32_range(0.6, 0.9); 
		emit_particle(Particle{
			pos=pos, vel=dir*speed, cloud_travel_vel={0,0}, color=particle_color, size=size, start_size=size,
            life_remaining=life, life_max=life, swirl_duration=0, rotation=rand.float32()*m.TAU, angular_vel=angular_vel,
            charge_center_pos={0,0}, is_burst_particle=true, is_swirling_charge=false, is_ammo_indicator=false, active=false, 
		})
	}
}

check_RMB_particle_enemy_collisions :: proc() {
    context = runtime.default_context()
    for i in 0..<MAX_PARTICLES {
        particle := &state.particles[i]
        // Ensure it's a damaging particle, not an ammo indicator or already burst
        if !particle.active || particle.is_burst_particle || particle.is_ammo_indicator || !particle.is_swirling_charge { 
            continue
        }
        particle_radius := particle.size * 0.5 
        if particle_radius <= 0.001 { continue }

        for j in 0..<MAX_ENEMIES {
            enemy := &state.enemies[j]
            if !enemy.active { continue } // Check if enemy is active
            // Add this check: if enemy.is_dying { continue; } // Skip if already dying
            
            enemy_radius := enemy.current_size * 0.5
            if enemy_radius <= 0.001 { continue }

            dist_sq := m.len_sq_vec2(particle.pos - enemy.pos)
            radii_sum := particle_radius + enemy_radius
            radii_sum_sq := radii_sum * radii_sum

            if dist_sq < radii_sum_sq {
                // RMB particles might do more than 1 damage, or enemy HP might be > 1
                // So, damage first, then check HP.
                enemy.hp -= PARTICLE_DAMAGE_VALUE // Assuming PARTICLE_DAMAGE_VALUE is defined (it is, as 1)
                particle.active = false // Particle is consumed

                if enemy.hp <= 0 && !enemy.is_dying { // Check if HP dropped to 0 or below AND not already dying
                    enemy.is_dying = true;
                    enemy.dying_timer = ENEMY_DEATH_ANIM_DURATION;
                    enemy.death_rect_offset = 0.0;
                    // enemy.angular_vel = 0; // Optional

                    // --- ADD PARTICLE SPAWN ---
                    spawn_RMB_enemy_death_particles(enemy.pos); 
                    // --- END ADD ---
                }
                // If particle is consumed, break from inner loop (checking this particle against other enemies)
                break 
            }
        }
    }
}

check_LMB_projectile_enemy_collisions :: proc() {
    context = runtime.default_context()
    for i in 0..<MAX_BLACKHOLES {
        proj := &state.blackholes[i]
        if !proj.active { continue }
        proj_radius := proj.size * 0.5
        for j in 0..<MAX_ENEMIES {
            enemy := &state.enemies[j]
            if !enemy.active { continue } // Check if enemy is active
            // Add this check: if enemy.is_dying { continue; } // Skip if already dying

            enemy_radius := enemy.current_size * 0.5
            dist_sq := m.len_sq_vec2(proj.pos - enemy.pos)
            radii_sum := proj_radius + enemy_radius
            radii_sum_sq := radii_sum * radii_sum

            if dist_sq < radii_sum_sq {
                proj.active = false    // Projectile is consumed
                
                if !enemy.is_dying { // Only start dying if not already
                    enemy.hp = 0; 
                    enemy.is_dying = true;
                    enemy.dying_timer = ENEMY_DEATH_ANIM_DURATION;
                    enemy.death_rect_offset = 0.0;
                    // enemy.angular_vel = 0; // Optional

                    // --- ADD PARTICLE SPAWN ---
                    spawn_LMB_enemy_death_particles(enemy.pos, enemy.color); 
                    // --- END ADD ---
                }
                break 
            }
        }
    }
}

// <<< NEW: Player-Enemy Collision Check >>>
check_player_enemy_collisions :: proc() {
    context = runtime.default_context()

    // If player is already defeated or invulnerable, no need to check further
    if state.player_hp <= 0 || state.player_invulnerable_timer > 0.0 {
        return
    }

    player_radius := f32(PLAYER_CORE_WORLD_RADIUS)

    for i in 0..<MAX_ENEMIES {
        enemy := &state.enemies[i]
        if !enemy.active || enemy.is_growing { // Don't collide if enemy is still growing
            continue
        }

        enemy_radius := enemy.current_size * 0.5
        if enemy_radius <= 0.001 { // Skip if enemy is too small to be a threat
            continue
        }

        dist_sq := m.dist_sq_vec2(state.player_pos, enemy.pos)
        radii_sum := player_radius + enemy_radius
        radii_sum_sq := radii_sum * radii_sum

        if dist_sq < radii_sum_sq {
            state.player_hp -= ENEMY_GRUNT_DAMAGE_VALUE
            state.player_hp = math.max(state.player_hp, 0) // Clamp HP to 0
            state.player_invulnerable_timer = PLAYER_INVULNERABILITY_DURATION
            
            fmt.printf("Player hit by GRUNT! HP: %d/%d. Invulnerable for %.2fs\n", state.player_hp, state.player_max_hp, state.player_invulnerable_timer)
            
            // TODO: Later, implement enemy bounce-off logic here
            // For now, the enemy passes through, but damage is applied and invulnerability starts.
            
            break // Player is hit, apply invulnerability, no need to check other enemies this frame
        }
    }
}


// --- Black Hole Projectile System (LMB Weapon) ---
emit_blackhole_projectile :: proc(proj: Blackhole_Projectile) {
    context = runtime.default_context()
    state.blackholes[state.next_blackhole_index] = proj
    state.blackholes[state.next_blackhole_index].active = true
    state.next_blackhole_index = (state.next_blackhole_index + 1) % MAX_BLACKHOLES
}

get_mouse_world_pos :: proc() -> m.vec2 {
    context = runtime.default_context()
    screen_width := sapp.widthf()
    screen_height := sapp.heightf()
    ndc_x := (2.0 * state.mouse_screen_pos.x / screen_width) - 1.0
    ndc_y := 1.0 - (2.0 * state.mouse_screen_pos.y / screen_height) 
    aspect_ratio := screen_width / screen_height
    ortho_width_vp := ORTHO_HEIGHT * aspect_ratio 
    world_x := ndc_x * ortho_width_vp
    world_y := ndc_y * ORTHO_HEIGHT
    return {world_x, world_y}
}

spawn_blackhole_projectile_weapon :: proc() {
    context = runtime.default_context()
    if state.player_hp <= 0 { return; } // Don't allow actions if player is defeated
    spawn_pos := state.player_pos
    target_world_pos := get_mouse_world_pos()
    direction_to_mouse := target_world_pos - spawn_pos
    direction: m.vec2
    if m.len_sq_vec2(direction_to_mouse) > 0.0001 { 
        direction = m.norm_vec2(direction_to_mouse)
    } else {
        if m.len_sq_vec2(state.player_vel) > 0.001 { direction = m.norm_vec2(state.player_vel)
        } else { direction = {0, 1} }
    }
    vel := direction * PROJECTILE_BLACKHOLE_INITIAL_SPEED
    life := f32(PROJECTILE_BLACKHOLE_LIFETIME)
    rotation_angle := math.atan2(direction.y, direction.x) - m.PI / 2.0 
    new_proj := Blackhole_Projectile {
        pos = spawn_pos, vel = vel, size = PROJECTILE_BLACKHOLE_SCALE, rotation = rotation_angle, 
        angular_vel = 0, life_remaining = life, life_max = life, active = false, 
    }
    emit_blackhole_projectile(new_proj)
}

update_and_instance_blackholes :: proc(dt: f32) -> int {
    context = runtime.default_context()
    live_count := 0
    for i in 0..<MAX_BLACKHOLES {
        if !state.blackholes[i].active { continue }
        p := &state.blackholes[i]
        p.life_remaining -= dt
        if p.life_remaining <= 0.0 { p.active = false; continue }
        p.pos += p.vel * dt
        p.rotation += p.angular_vel * dt
        if p.rotation > m.TAU { p.rotation -= m.TAU }
        if p.rotation < 0    { p.rotation += m.TAU }
        life_ratio := p.life_remaining / p.life_max
        if live_count < MAX_BLACKHOLES {
            inst := &state.blackhole_instance_data[live_count]
            inst.instance_pos_size_rot = {p.pos.x, p.pos.y, p.size, p.rotation}
            inst.instance_color = {1.0, 1.0, 1.0, life_ratio} 
            live_count += 1
        }
    }
    return live_count
}


// --- Enemy System ---
emit_enemy :: proc(enemy_data: Enemy) {
    context = runtime.default_context()
    idx_to_write := state.next_enemy_index
    state.enemies[idx_to_write] = enemy_data        
    state.enemies[idx_to_write].active = true       
    state.next_enemy_index = (state.next_enemy_index + 1) % MAX_ENEMIES
}

spawn_enemy :: proc(current_ortho_width: f32, current_ortho_height: f32, player_pos: m.vec2) {
    context = runtime.default_context()
    start_pos: m.vec2
    valid_spawn_found := false
    for attempt in 0..<ENEMY_MAX_SPAWN_ATTEMPTS {
        side := rand.int31() % 4 
        random_depth := rand.float32() * ENEMY_SPAWN_BORDER_FRACTION 
        switch side {
        case 0: start_pos.y = current_ortho_height * (1.0 - random_depth); start_pos.x = (rand.float32() * 2.0 - 1.0) * current_ortho_width 
        case 1: start_pos.y = -current_ortho_height * (1.0 - random_depth); start_pos.x = (rand.float32() * 2.0 - 1.0) * current_ortho_width
        case 2: start_pos.x = -current_ortho_width * (1.0 - random_depth); start_pos.y = (rand.float32() * 2.0 - 1.0) * current_ortho_height
        case 3: start_pos.x = current_ortho_width * (1.0 - random_depth); start_pos.y = (rand.float32() * 2.0 - 1.0) * current_ortho_height
        }
        dist_sq_to_player := m.len_sq_vec2(start_pos - player_pos)
        if dist_sq_to_player >= ENEMY_MIN_SPAWN_DIST_FROM_PLAYER_SQ { valid_spawn_found = true; break; }
    }
    if !valid_spawn_found {
        fmt.printf("spawn_enemy: WARNING - Could not find a suitable spawn point after %d attempts. Using fallback.\n", ENEMY_MAX_SPAWN_ATTEMPTS)
        start_pos.y = current_ortho_height * (1.0 - ENEMY_SPAWN_BORDER_FRACTION * 0.5) 
        start_pos.x = -current_ortho_width * (1.0 - ENEMY_SPAWN_BORDER_FRACTION * 0.5) 
    }
    start_vel: m.vec2 = {0.0, 0.0} 
    base_grunt_rgb := m.vec3{0.9, 0.1, 0.7} 
    grunt_color := m.vec4{base_grunt_rgb.r, base_grunt_rgb.g, base_grunt_rgb.b, ENEMY_BASE_ALPHA}
    initial_wander_angle := rand.float32() * m.TAU
    initial_wander_vector := m.angle_to_vec2(initial_wander_angle)
grunt := Enemy {
        pos = start_pos, vel = start_vel, color = grunt_color, 
        target_size = ENEMY_GRUNT_SCALE, current_size = ENEMY_GRUNT_SCALE * ENEMY_INITIAL_SCALE_FACTOR, 
        grow_timer = ENEMY_GROW_DURATION, is_growing = true,                                             
        rotation = rand.float32() * m.TAU, 
        angular_vel = (rand.float32() * 2.0 - 1.0) * ENEMY_MAX_ANGULAR_SPEED, // Spin between -MAX and +MAX
        hp = ENEMY_GRUNT_MAX_HP, 
        active = false, current_wander_vector = initial_wander_vector,
        wander_timer = rand.float32_range(0.0, ENEMY_WANDER_DIRECTION_CHANGE_INTERVAL), 
    }
    emit_enemy(grunt)
}
update_and_instance_enemies :: proc(dt: f32) -> int {
    context = runtime.default_context()
    live_enemy_count := 0
    player_pos := state.player_pos

    for i in 0..<MAX_ENEMIES {
        if !state.enemies[i].active { continue }
        enemy := &state.enemies[i]

        current_visual_scale_for_shader: f32
        effect_params_x: f32 = 0.0; // is_dying
        effect_params_y: f32 = 0.0; // death_rect_offset
        effect_params_z: f32 = 1.0; // current_dying_part_scale_multiplier (default to 1.0)
        //effect_params_z = m.lerp(f32(1.0), ENEMY_DEATH_RECT_FINAL_SCALE_FACTOR, eased_progress_for_scale); // This will now correctly lerp from 1.0 to 0.0
        effect_params_w: f32 = 1.0; // overall_dying_alpha_multiplier (default to 1.0)


        if enemy.is_dying {
            effect_params_x = 1.0; // Signal to shader that it's dying

            enemy.dying_timer -= dt;
            enemy.death_rect_offset += ENEMY_DEATH_RECT_SEPARATION_SPEED * dt;
            effect_params_y = enemy.death_rect_offset;

            if enemy.dying_timer <= 0.0 {
                enemy.active = false;
                continue;
            }

            // Progress from 0.0 (start of death) to 1.0 (end of death timer)
            progress_raw := 1.0 - math.clamp(enemy.dying_timer / ENEMY_DEATH_ANIM_DURATION, 0.0, 1.0);
            eased_progress_for_scale := math.pow(progress_raw, 2.5); // For slower shrink at start

            // Scale multiplier for the individual rectangle parts
            effect_params_z = m.lerp(f32(1.0), ENEMY_DEATH_RECT_FINAL_SCALE_FACTOR, eased_progress_for_scale);

            // Alpha multiplier - fade out linearly from 1.0 to 0.0 over the duration
            // You can apply easing here too if desired, e.g., math.pow(progress_raw, N) for fade speed
            effect_params_w = 1.0 - progress_raw;


            // The quad itself remains at the original target size during death
            current_visual_scale_for_shader = enemy.target_size  * ENEMY_DEATH_QUAD_RENDER_SCALE_MULTIPLIER;
            
            // enemy.current_size can still represent the conceptual "bounding" size if needed elsewhere,
            // but it's not directly driving the quad's render scale during death.
            enemy.current_size = enemy.target_size * effect_params_z;


        } else if enemy.is_growing {
            enemy.grow_timer -= dt;
            if enemy.grow_timer <= 0.0 {
                enemy.current_size = enemy.target_size;
                enemy.is_growing = false;
                enemy.grow_timer = 0.0;
            } else {
                progress := 1.0 - (enemy.grow_timer / ENEMY_GROW_DURATION);
                progress = math.clamp(progress, 0.0, 1.0);
                initial_actual_size := enemy.target_size * ENEMY_INITIAL_SCALE_FACTOR;
                enemy.current_size = m.lerp(initial_actual_size, enemy.target_size, progress);
            }
            current_visual_scale_for_shader = enemy.current_size;
            // Movement and rotation for growing
            enemy.rotation += enemy.angular_vel * dt;
            enemy.wander_timer -= dt;
            if enemy.wander_timer <= 0.0 {
                new_wander_angle := rand.float32() * m.TAU;
                enemy.current_wander_vector = m.angle_to_vec2(new_wander_angle);
                enemy.wander_timer = ENEMY_WANDER_DIRECTION_CHANGE_INTERVAL + rand.float32_range(-0.2, 0.2);
            }
            direction_to_player_strict := player_pos - enemy.pos;
            final_direction := direction_to_player_strict;
            dist_sq_to_player := m.len_sq_vec2(direction_to_player_strict);
            if dist_sq_to_player > 0.001 {
                normalized_strict_direction := m.norm_vec2(direction_to_player_strict);
                final_direction = normalized_strict_direction + (enemy.current_wander_vector * ENEMY_WANDER_INFLUENCE);
            }
            if dist_sq_to_player > 0.00001 {
                normalized_final_direction := m.norm_vec2(final_direction);
                enemy.vel = normalized_final_direction * ENEMY_GRUNT_SPEED;
            } else if m.len_sq_vec2(direction_to_player_strict) > 0.00001 {
                enemy.vel = m.norm_vec2(direction_to_player_strict) * ENEMY_GRUNT_SPEED;
            } else { enemy.vel = m.vec2_zero(); }
            enemy.pos += enemy.vel * dt;

        } else { // Alive and not growing (normal behavior)
            enemy.current_size = enemy.target_size;
            current_visual_scale_for_shader = enemy.current_size;
            effect_params_z = 1.0; 
            effect_params_w = 1.0;
            // Movement and rotation for alive
            enemy.rotation += enemy.angular_vel * dt;
            enemy.wander_timer -= dt;
            if enemy.wander_timer <= 0.0 {
                new_wander_angle := rand.float32() * m.TAU;
                enemy.current_wander_vector = m.angle_to_vec2(new_wander_angle);
                enemy.wander_timer = ENEMY_WANDER_DIRECTION_CHANGE_INTERVAL + rand.float32_range(-0.2, 0.2);
            }
            direction_to_player_strict := player_pos - enemy.pos;
            final_direction := direction_to_player_strict;
            dist_sq_to_player := m.len_sq_vec2(direction_to_player_strict);
            if dist_sq_to_player > 0.001 {
                normalized_strict_direction := m.norm_vec2(direction_to_player_strict);
                final_direction = normalized_strict_direction + (enemy.current_wander_vector * ENEMY_WANDER_INFLUENCE);
            }
            if dist_sq_to_player > 0.00001 {
                normalized_final_direction := m.norm_vec2(final_direction);
                enemy.vel = normalized_final_direction * ENEMY_GRUNT_SPEED;
            } else if m.len_sq_vec2(direction_to_player_strict) > 0.00001 {
                enemy.vel = m.norm_vec2(direction_to_player_strict) * ENEMY_GRUNT_SPEED;
            } else { enemy.vel = m.vec2_zero(); }
            enemy.pos += enemy.vel * dt;
        }

        if enemy.rotation > m.TAU { enemy.rotation -= m.TAU; }
        if enemy.rotation < 0    { enemy.rotation += m.TAU; }

        if live_enemy_count < MAX_ENEMIES {
            inst := &state.enemy_instance_data[live_enemy_count];
            inst.instance_pos = enemy.pos;
            inst.instance_main_rotation = enemy.rotation;
            inst.instance_visual_scale = current_visual_scale_for_shader;
            inst.instance_color = enemy.color;
            inst.instance_effect_params = {effect_params_x, effect_params_y, effect_params_z, effect_params_w};
            live_enemy_count += 1;
        }
    }
    return live_enemy_count
}

frame :: proc "c" () {
    context = runtime.default_context()
    width := sapp.widthf(); height := sapp.heightf(); aspect := width / height
    current_time := f32(sapp.frame_count()) / 60.0
    delta_time := f32(sapp.frame_duration()); delta_time = math.min(delta_time, 1.0/15.0);

    // --- Player Update ---
    state.player_invulnerable_timer = math.max(0.0, state.player_invulnerable_timer - delta_time);
    state.rmb_cooldown_timer = math.max(0.0, state.rmb_cooldown_timer - delta_time)
    state.lmb_cooldown_timer = math.max(0.0, state.lmb_cooldown_timer - delta_time)

    if state.player_hp > 0 {
         if state.current_rmb_ammo_charges < MAX_RMB_AMMO_CHARGES {
            state.rmb_ammo_regen_timer -= delta_time;
            if state.rmb_ammo_regen_timer <= 0.0 {
                spawn_visual_ammo_charge_particles(state.current_rmb_ammo_charges);
                state.current_rmb_ammo_charges += 1;
                state.rmb_ammo_regen_timer = RMB_AMMO_REGEN_INTERVAL; // Reset for next charge
                fmt.printf("RMB Ammo Charge Regenerated! Current: %d/%d\n", state.current_rmb_ammo_charges, MAX_RMB_AMMO_CHARGES);
            }
        }
        accel_input := m.vec2_zero(); 
        if state.key_w_down {accel_input.y+=1.0}; if state.key_s_down {accel_input.y-=1.0}; 
        if state.key_a_down {accel_input.x-=1.0}; if state.key_d_down {accel_input.x+=1.0};  
        if m.len_sq_vec2(accel_input) > 0.001 {accel_input=m.norm_vec2(accel_input)}; 
        final_accel := accel_input*PLAYER_ACCELERATION; 
        if state.key_s_down && !state.key_w_down && accel_input.y < -0.5 { final_accel *= PLAYER_REVERSE_FACTOR };
        state.player_vel += final_accel*delta_time; 
        damping_factor := math.max(0.0, 1.0-PLAYER_DAMPING*delta_time); 
        state.player_vel *= damping_factor; 
        if m.len_sq_vec2(state.player_vel) > f32(PLAYER_MAX_SPEED*PLAYER_MAX_SPEED) { state.player_vel=m.norm_vec2(state.player_vel)*PLAYER_MAX_SPEED }; 
        state.player_pos += state.player_vel*delta_time;

        rmb_pressed_this_frame := state.rmb_down && !state.previous_rmb_down; 
         // --- NEW: Remove visual ammo on RMB press, regardless of actual firing ---
            if rmb_pressed_this_frame && state.current_rmb_ammo_charges > 0 {
                // Remove visuals for the charge that WOULD be spent
                // (state.current_rmb_ammo_charges - 1) is the index of the charge at the "top of the stack"
                remove_visual_ammo_charge_particles(state.current_rmb_ammo_charges - 1); 
            }
            // --- END NEW ---

            if rmb_pressed_this_frame && state.rmb_cooldown_timer <= 0.0 { 
                if state.current_rmb_ammo_charges > 0 {
                    // Visuals are already removed above if it was a fresh press
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


    // --- Player Boundary Logic ---
    current_ortho_width_for_bounds := ORTHO_HEIGHT * aspect 
    bounce_min_x : f32 = -current_ortho_width_for_bounds + PLAYER_CORE_WORLD_RADIUS // Adjusted for player radius
    bounce_max_x : f32 =  current_ortho_width_for_bounds - PLAYER_CORE_WORLD_RADIUS // Adjusted for player radius
    bounce_min_y : f32 = -ORTHO_HEIGHT + PLAYER_CORE_WORLD_RADIUS                // Adjusted for player radius
    bounce_max_y : f32 =  ORTHO_HEIGHT - PLAYER_CORE_WORLD_RADIUS                // Adjusted for player radius

    if state.player_pos.x < bounce_min_x { state.player_pos.x = bounce_min_x; if state.player_vel.x < 0 { state.player_vel.x *= -PLAYER_BOUNCE_DAMPING_FACTOR }} 
    else if state.player_pos.x > bounce_max_x { state.player_pos.x = bounce_max_x; if state.player_vel.x > 0 { state.player_vel.x *= -PLAYER_BOUNCE_DAMPING_FACTOR }}
    if state.player_pos.y < bounce_min_y { state.player_pos.y = bounce_min_y; if state.player_vel.y < 0 { state.player_vel.y *= -PLAYER_BOUNCE_DAMPING_FACTOR }} 
    else if state.player_pos.y > bounce_max_y { state.player_pos.y = bounce_max_y; if state.player_vel.y > 0 { state.player_vel.y *= -PLAYER_BOUNCE_DAMPING_FACTOR }}
    
    // --- Enemy Spawning ---
    state.enemy_spawn_timer -= delta_time
    if state.enemy_spawn_timer <= 0.0 {
        current_ortho_width_for_spawn := ORTHO_HEIGHT * aspect 
        spawn_enemy(current_ortho_width_for_spawn, ORTHO_HEIGHT, state.player_pos) 
        state.enemy_spawn_timer = ENEMY_SPAWN_INTERVAL + rand.float32_range(-ENEMY_SPAWN_INTERVAL*0.2, ENEMY_SPAWN_INTERVAL*0.2) 
    }

    // --- Update Systems ---
    state.num_active_particles = update_and_instance_particles(delta_time);
    state.num_active_enemies = update_and_instance_enemies(delta_time); 
    state.num_active_blackholes = update_and_instance_blackholes(delta_time);

    // --- Collision Detection ---
    check_LMB_projectile_enemy_collisions();
    check_RMB_particle_enemy_collisions();
    check_player_enemy_collisions(); // <<< CALL NEW COLLISION FUNCTION

    // --- Setup Uniforms & View Projection ---
    state.bg_fs_params={tick=current_time, resolution={width,height}, bg_option=1}; 
    state.player_fs_params={
        tick=current_time, 
        resolution={width,height},
        player_hp_uniform=f32(state.player_hp), // Pass current HP to shader
        player_max_hp_uniform=f32(state.player_max_hp),
        player_invulnerable_timer_uniform = state.player_invulnerable_timer,
        player_invulnerability_duration_uniform = PLAYER_INVULNERABILITY_DURATION,
    }; 
    state.particle_fs_params={tick=current_time};
    state.enemy_fs_params={tick=current_time}; 
    state.blackhole_fs_params={tick=current_time};

    ortho_width_vp := ORTHO_HEIGHT*aspect; 
    proj := m.ortho(-ortho_width_vp,ortho_width_vp,-ORTHO_HEIGHT,ORTHO_HEIGHT,-1.0,1.0); 
    view := m.identity(); view_proj := m.mul(proj,view); 
    
    scale_mat := m.scale(m.vec3{PLAYER_SCALE,PLAYER_SCALE,1.0}); 
    translate_mat := m.translate(m.vec3{state.player_pos.x,state.player_pos.y,0.0}); 
    model := m.mul(translate_mat,scale_mat); 
    state.player_vs_params.mvp=m.mul(view_proj,model); 
    
    state.particle_vs_params.view_proj=view_proj;
    state.enemy_vs_params.view_proj=view_proj; 
    state.blackhole_vs_params.view_proj=view_proj;


    // --- Drawing ---
    sg.begin_pass({action=state.pass_action, swapchain=sglue.swapchain() });
    
    sg.apply_pipeline(state.bg_pip); sg.apply_bindings(state.bind); sg.apply_uniforms(UB_bg_fs_params, sg.Range{ptr=&state.bg_fs_params, size=size_of(Bg_Fs_Params)}); sg.draw(0,4,1);
    sg.apply_pipeline(state.player_pip); sg.apply_bindings(state.bind); sg.apply_uniforms(UB_Player_Vs_Params, sg.Range{ptr=&state.player_vs_params, size=size_of(Player_Vs_Params)}); sg.apply_uniforms(UB_Player_Fs_Params, sg.Range{ptr=&state.player_fs_params, size=size_of(Player_Fs_Params)}); sg.draw(0,4,1);
	
    if state.num_active_particles > 0 {
		sg.apply_pipeline(state.particle_pip); sg.apply_bindings(state.particle_bind); sg.update_buffer(state.particle_instance_vbo, sg.Range{ptr=rawptr(&state.particle_instance_data[0]), size=uint(state.num_active_particles)*size_of(Particle_Instance_Data)});
		sg.apply_uniforms(UB_particle_vs_params, sg.Range{ptr=&state.particle_vs_params, size=size_of(Particle_Vs_Params)}); sg.apply_uniforms(UB_particle_fs_params, sg.Range{ptr=&state.particle_fs_params, size=size_of(Particle_Fs_Params)});
		sg.draw(0, 4, state.num_active_particles);
	}

    if state.num_active_blackholes > 0 {
        sg.apply_pipeline(state.blackhole_pip); 
        sg.apply_bindings(state.blackhole_bind); 
        sg.update_buffer(state.blackhole_instance_vbo, sg.Range{ptr=rawptr(&state.blackhole_instance_data[0]), size=uint(state.num_active_blackholes)*size_of(Blackhole_Instance_Data)});
		sg.apply_uniforms(UB_blackhole_vs_params, sg.Range{ptr=&state.blackhole_vs_params, size=size_of(Blackhole_Vs_Params)}); 
        sg.apply_uniforms(UB_blackhole_fs_params, sg.Range{ptr=&state.blackhole_fs_params, size=size_of(Blackhole_Fs_Params)});
		sg.draw(0, 4, state.num_active_blackholes);
    }

    if state.num_active_enemies > 0 {
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
main :: proc () { sapp.run({ init_cb=init, frame_cb=frame, cleanup_cb=cleanup, event_cb=event, width=800, height=600, sample_count=4, window_title="GeoWars Odin - Grunt Collision", icon={sokol_default=true}, logger={func=slog.func} }) }