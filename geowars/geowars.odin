// File: geowars.odin (Revised for Grunt-Player Collision Damage & Synth Track)
//------------------------------------------------------------------------------
package main

import "base:runtime"
import "core:math"
import "core:mem"
import "core:fmt"
import "core:c"
import slog "../sokol/log"
import sg "../sokol/gfx"
import sapp "../sokol/app"
import sglue "../sokol/glue"
import sa "../sokol/audio"
import ma "../miniaudio"
import m "../math"
import rand "core:math/rand"

LMB_SOUND_SAMPLE_RATE :: 44100
LMB_SOUND_CHANNELS :: 1
LMB_SOUND_DURATION_MS :: 100
LMB_SOUND_FRAMES :: LMB_SOUND_SAMPLE_RATE * LMB_SOUND_DURATION_MS / 1000
LMB_SOUND_START_FREQ :: 1200.0
LMB_SOUND_END_FREQ :: 400.0

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
PLAYER_SCALE             :: 0.15
PLAYER_BOUNCE_BOUNDARY_OFFSET :: 0.1
PLAYER_CORE_SHADER_RADIUS :: 0.04
PLAYER_UV_SPACE_EXTENT   :: 0.5
PLAYER_CORE_WORLD_RADIUS :: (PLAYER_CORE_SHADER_RADIUS / PLAYER_UV_SPACE_EXTENT) * PLAYER_SCALE
PLAYER_BOUNCE_DAMPING_FACTOR :: 1.05
PLAYER_MAX_HP_VALUE      :: 4 
PLAYER_INVULNERABILITY_DURATION :: 0.75 
PARTICLE_DAMAGE_VALUE    :: 1 
LMB_PROJECTILE_DAMAGE    :: 2 
ENEMY_GRUNT_DAMAGE_VALUE :: 1 

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
ENEMY_GRUNT_SPEED :: f32(0.5)
// --- SlowBoy Constants ---
ENEMY_SLOWBOY_BASE_SCALE :: 0.25
ENEMY_SLOWBOY_GLOW_CANVAS_SF :: 1.0
ENEMY_SLOWBOY_SPEED :: f32(0.15)
ENEMY_SLOWBOY_MAX_HP :: 16
// --- SlowBoy Attack Constants ---
SLOWBOY_ATTACK_DETECT_RANGE :: ORTHO_HEIGHT * 0.8; 
SLOWBOY_ATTACK_WINDUP_TOTAL_DURATION :: 1.5;
SLOWBOY_ATTACK_LOCKON_TIME_REMAINING :: 0.2; 
SLOWBOY_ATTACK_CHARGE_SCREEN_FRACTION :: 0.5; 
SLOWBOY_ATTACK_CHARGE_SPEED_FACTOR :: 3.0; 
SLOWBOY_ATTACK_DAMAGE :: 1;
// --- Common Enemy Constants ---
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
ENEMY_GRUNT_MAX_HP :: 4
ENEMY_DEATH_ANIM_DURATION :: 1.0  
GRUNT_DEATH_ANIM_DURATION :: 3.0 
SLOWBOY_DEATH_ANIM_DURATION :: 1.0
ENEMY_DEATH_RECT_SEPARATION_SPEED :: 0.3 
ENEMY_DEATH_RECT_FINAL_SCALE_FACTOR :: 0.0 
ENEMY_DEATH_QUAD_RENDER_SCALE_MULTIPLIER :: 2.5 

// Enemy Death Particle Constants
LMB_ENEMY_DEATH_PARTICLE_COUNT :: 20
LMB_ENEMY_DEATH_PARTICLE_LIFETIME_BASE :: 0.3
LMB_ENEMY_DEATH_PARTICLE_LIFETIME_RAND :: 0.2
LMB_ENEMY_DEATH_PARTICLE_SPEED_BASE :: 2.5  
LMB_ENEMY_DEATH_PARTICLE_SPEED_RAND :: 1.8
LMB_ENEMY_DEATH_PARTICLE_SIZE_BASE :: 0.025 
LMB_ENEMY_DEATH_PARTICLE_SIZE_RAND :: 0.01
LMB_ENEMY_DEATH_PARTICLE_ANGULAR_VEL_MAX :: m.PI * 0.4

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
RMB_AMMO_REGEN_INTERVAL :: 10.0 
MAX_RMB_AMMO_CHARGES    :: 2    
RMB_AMMO_INDICATOR_PARTICLES_PER_CHARGE :: 16 
RMB_AMMO_INDICATOR_ORBIT_RADIUS         :: PLAYER_SCALE * 0.5 
RMB_AMMO_INDICATOR_ORBIT_SPEED          :: m.PI * 0.8        
RMB_AMMO_INDICATOR_BASE_SIZE            :: 0.018              
RMB_AMMO_INDICATOR_COLOR                :: m.vec4{0.7, 0.4, 1.0, 0.75} 
RMB_AMMO_INDICATOR_SELF_SPIN_SPEED      :: m.PI * 0.6         

// Rendering Internals
vertex_stride :: size_of(f32) * 7

// --- Enemy Type Enum ---
EnemyType :: enum {
    GRUNT,
    SLOWBOY,
}

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
	rotation:         f32,         
	angular_vel:      f32,         
    charge_center_pos: m.vec2, 
	is_burst_particle: bool,
    is_swirling_charge: bool, 
    is_ammo_indicator: bool, 
	active:           bool,
    sound_hum: ma.sound,
    sound_whoosh: ma.sound,
    has_active_sound: bool,
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
    type: EnemyType, 
    active: bool,
    current_wander_vector: m.vec2,
    wander_timer: f32,
    is_dying: bool,
    dying_timer: f32,
    death_rect_offset: f32,
    death_anim_max_duration: f32,

    // --- SlowBoy Attack State ---
    is_winding_up_attack: bool,
    attack_windup_timer: f32,
    has_locked_attack_trajectory: bool,
    attack_charge_target_pos: m.vec2,
    is_charging_attack: bool,
    attack_charge_start_pos: m.vec2,
}

Enemy_Instance_Data :: struct #align(16) {
    using _: struct #packed {
        instance_pos: m.vec2,         
        instance_main_rotation: f32,  
        instance_visual_scale: f32,   
        instance_color: m.vec4,       
        instance_effect_params: m.vec4, 
        instance_enemy_type: f32,     
        _padding0: m.vec3,            
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

    audio_engine: ma.engine,
    lmb_sound: ma.sound,

    player_pos: m.vec2, player_vel: m.vec2,
    player_hp: int, player_max_hp: int, 
    player_invulnerable_timer: f32,    
    player_defeated_message_shown: bool, 

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
    grunt_spawn_timer: f32, 
    slowboy_spawn_timer: f32, 
    
}

// =============================================================================
// END: Package-Level Declarations
// =============================================================================


init :: proc "c" () {
    context = runtime.default_context()
    sg.setup({ pipeline_pool_size=16, buffer_pool_size=16, shader_pool_size=16, environment=sglue.environment(), logger={func=slog.func} }) // Increased pool sizes slightly
    fmt.printf("--- Init Start ---\n")

        buffer_frames = 1024, 
        packet_frames = 0,    
        num_packets = 0,      
        stream_userdata_cb = geowars_audio_stream_callback,
        user_data = nil, 
    }
    sa.setup(sokol_audio_desc)
    if !sa.isvalid() {
        fmt.eprintf("!!! CRITICAL: Sokol Audio setup failed!\n")
    } else {
        fmt.printf("--- Sokol Audio Initialized (Sample Rate: %v, Channels: %v) ---\n", sa.sample_rate(), sa.channels())
    }

    // Miniaudio Engine Setup
    engine_config := ma.engine_config_init()
    engine_config.noDevice = true 


    init_result := ma.engine_init(&engine_config, &state.audio_engine)
    if init_result != .SUCCESS {
        fmt.eprintf("!!! CRITICAL: Miniaudio engine_init failed! Error: %v\n", init_result)
    } else {
        fmt.printf("--- Miniaudio Engine Initialized ---\n")
    }

    // Generate "Pew" Sound PCM Data
    fmt.printf("--- Generating 'Pew' sound PCM data... ---\n")

        }
    }
    fmt.printf("--- 'Pew' sound PCM data generated. First sample: %v, Mid sample: %v, Last sample: %v ---\n", lmb_sound_pcm_data[0], lmb_sound_pcm_data[LMB_SOUND_FRAMES/2], lmb_sound_pcm_data[LMB_SOUND_FRAMES-1])


            ma.audio_buffer_uninit(&lmb_sound_audio_buffer); 
        } else {
            fmt.printf("--- Miniaudio lmb_sound initialized successfully ---\n")
        }
    }

<
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
                ATTR_enemy_instance_pos_vs_in={buffer_index=1,offset=0,format=.FLOAT2}, 
                ATTR_enemy_instance_main_rotation_vs_in={buffer_index=1,offset=8,format=.FLOAT},
                ATTR_enemy_instance_visual_scale_vs_in={buffer_index=1,offset=12,format=.FLOAT},
                ATTR_enemy_instance_color_vs_in={buffer_index=1,offset=16,format=.FLOAT4}, 
                ATTR_enemy_instance_effect_params_vs_in={buffer_index=1,offset=32,format=.FLOAT4},
                ATTR_enemy_instance_enemy_type_vs_in={buffer_index=1,offset=48,format=.FLOAT},
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

    state.current_rmb_ammo_charges = 0; 
    state.rmb_ammo_regen_timer = RMB_AMMO_REGEN_INTERVAL/10; 

    state.grunt_spawn_timer = 1.0; 
    state.slowboy_spawn_timer = 5.0; 

    state.first_grunt_killed = false;
    state.first_slowboy_killed = false; // <<< NEW
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

geowars_audio_stream_callback :: proc "c" (buffer: ^f32, num_frames: c.int, num_channels: c.int, user_data: rawptr) {
    ma.engine_read_pcm_frames(&state.audio_engine, buffer, u64(num_frames), nil)
}

// --- Particle System ---
emit_particle :: proc(part: Particle) {
	context = runtime.default_context()
    p_to_init_sound := &state.particles[state.next_particle_index]
    p_to_init_sound^ = part 
    p_to_init_sound.has_active_sound = false 

    if p_to_init_sound.is_ammo_indicator || p_to_init_sound.is_swirling_charge {
        p_to_init_sound.has_active_sound = true
        sound_flags_particle: ma.sound_flags = { .NO_PITCH, .NO_SPATIALIZATION } // Renamed
        hum_init_res := ma.sound_init_from_data_source(&state.audio_engine, (^ma.data_source)(&rmb_hum_audio_buffer), sound_flags_particle, nil, &p_to_init_sound.sound_hum)
        if hum_init_res == .SUCCESS {
            ma.sound_set_looping(&p_to_init_sound.sound_hum, true)
            ma.sound_set_volume(&p_to_init_sound.sound_hum, RMB_HUM_AMPLITUDE) 
            ma.sound_start(&p_to_init_sound.sound_hum)
        } else {
            fmt.eprintf("!!! ERROR: Failed to init hum sound for particle. Code: %v\n", hum_init_res)
            p_to_init_sound.has_active_sound = false 
        }

        if p_to_init_sound.has_active_sound { 
            whoosh_init_res := ma.sound_init_from_data_source(&state.audio_engine, (^ma.data_source)(&rmb_whoosh_audio_buffer), sound_flags_particle, nil, &p_to_init_sound.sound_whoosh)
            if whoosh_init_res == .SUCCESS {
                ma.sound_set_looping(&p_to_init_sound.sound_whoosh, true)
                ma.sound_set_volume(&p_to_init_sound.sound_whoosh, 0.0) 
                ma.sound_start(&p_to_init_sound.sound_whoosh)
            } else {
                fmt.eprintf("!!! ERROR: Failed to init whoosh sound for particle. Code: %v\n", whoosh_init_res)
                ma.sound_uninit(&p_to_init_sound.sound_hum) 
                p_to_init_sound.has_active_sound = false 
            }
        }
    }
    p_to_init_sound.active = true 
	state.next_particle_index = (state.next_particle_index + 1) % MAX_PARTICLES
}

spawn_swirling_charge :: proc() { 
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
            p.rotation += RMB_AMMO_INDICATOR_ORBIT_SPEED * dt; 
            if p.rotation > m.TAU { p.rotation -= m.TAU; }
            else if p.rotation < 0 { p.rotation += m.TAU; }
            orbit_direction := m.angle_to_vec2(p.rotation);
            p.pos = state.player_pos + orbit_direction * RMB_AMMO_INDICATOR_ORBIT_RADIUS;
            p.charge_center_pos.y += p.angular_vel * dt; 
            if p.charge_center_pos.y > m.TAU {p.charge_center_pos.y -= m.TAU;}
            if p.charge_center_pos.y < 0 {p.charge_center_pos.y += m.TAU;}
            p.color = RMB_AMMO_INDICATOR_COLOR;
            p.size = RMB_AMMO_INDICATOR_BASE_SIZE;
        } else {
            p.pos += p.vel * dt;
            screen_aspect_ratio_part: f32 = sapp.widthf() / sapp.heightf() // Renamed
            world_half_width_part: f32 = ORTHO_HEIGHT * screen_aspect_ratio_part // Renamed
            world_half_height_part: f32 = ORTHO_HEIGHT // Renamed
            off_screen_margin_part: f32 = 0.1 // Renamed

            is_off_screen := false
            if p.pos.x < -world_half_width_part - off_screen_margin_part ||
               p.pos.x >  world_half_width_part + off_screen_margin_part ||
               p.pos.y < -world_half_height_part - off_screen_margin_part ||
               p.pos.y >  world_half_height_part + off_screen_margin_part {
                is_off_screen = true
            }

            if is_off_screen {
                if p.has_active_sound {
                    ma.sound_uninit(&p.sound_hum)
                    ma.sound_uninit(&p.sound_whoosh)
                    p.has_active_sound = false
                }
                p.active = false
                continue 
            }

            if p.has_active_sound {
                current_speed_part := m.len_vec2(p.vel) // Renamed
                speed_factor_part: f32 // Renamed
                if MAX_PARTICLE_SPEED_FOR_SOUND_EFFECT > 0.001 { 
                    speed_factor_part = math.clamp(current_speed_part / MAX_PARTICLE_SPEED_FOR_SOUND_EFFECT, 0.0, 1.0)
                } else { speed_factor_part = 0.0 }
                hum_target_volume_part := (1.0 - speed_factor_part) * RMB_HUM_AMPLITUDE // Renamed
                whoosh_target_volume_part := speed_factor_part * RMB_WHOOSH_AMPLITUDE // Renamed
                ma.sound_set_volume(&p.sound_hum, hum_target_volume_part)
                ma.sound_set_volume(&p.sound_whoosh, whoosh_target_volume_part)
            }
            p.rotation += p.angular_vel * dt; 
            if p.rotation > m.TAU { p.rotation -= m.TAU; } else if p.rotation < 0 { p.rotation += m.TAU; }
            p.life_remaining -= dt;

            if p.is_swirling_charge && p.life_remaining <= 0.0 {
                p.is_swirling_charge = false;
                new_life_part := EXPLOSION_LIFETIME_BASE + rand.float32() * EXPLOSION_LIFETIME_RAND; // Renamed
                p.life_remaining = new_life_part;
                p.life_max = new_life_part;    
                explosion_center_part := p.charge_center_pos + p.cloud_travel_vel * p.swirl_duration; // Renamed
                relative_pos_part := p.pos - explosion_center_part; // Renamed
                outward_dir_part : m.vec2 = {rand.float32() * 2.0 - 1.0, rand.float32() * 2.0 - 1.0}; // Renamed
                len_sq_part := m.len_sq_vec2(relative_pos_part); // Renamed
                if len_sq_part > 0.0001 { outward_dir_part = m.norm_vec2(relative_pos_part);
                } else if m.len_sq_vec2(outward_dir_part) > 0.0001 { outward_dir_part = m.norm_vec2(outward_dir_part);
                } else { outward_dir_part = {0.0, 1.0}; }
                explosion_speed_part := EXPLOSION_SPEED_BASE + rand.float32() * EXPLOSION_SPEED_RAND; // Renamed
                p.vel = outward_dir_part * explosion_speed_part;
                p.angular_vel = EXPLOSION_PARTICLE_SPIN;
            }

            if !p.is_swirling_charge && p.life_remaining <= 0.0 { 
                if p.has_active_sound {
                    ma.sound_uninit(&p.sound_hum)
                    ma.sound_uninit(&p.sound_whoosh)
                    p.has_active_sound = false
                }
                p.active = false; 
                continue; 
            }

            life_ratio_part: f32 = 0.0; // Renamed
            if p.life_max > 0.0 { life_ratio_part = math.max(f32(0.0), p.life_remaining / p.life_max); }
            
            if p.is_swirling_charge { 
                p.size = p.start_size; 
                p.color.a = 1.0;      
            } else { 
                p.size = p.start_size * life_ratio_part * life_ratio_part; 
                p.color.a = life_ratio_part * life_ratio_part; 
            }
        }
        
        if live_particle_count < MAX_PARTICLES {
            inst := &state.particle_instance_data[live_particle_count];
            inst.instance_pos=p.pos; 
            inst.instance_size=p.size; 
            if p.is_ammo_indicator { inst.instance_rotation = p.charge_center_pos.y;  } 
            else { inst.instance_rotation = p.rotation; }
            inst.instance_color=p.color;
            live_particle_count += 1;
        }
    }
    return live_particle_count
}

spawn_LMB_enemy_death_particles :: proc(pos: m.vec2, base_color: m.vec4) {
	context = runtime.default_context()
	for _ in 0..<LMB_ENEMY_DEATH_PARTICLE_COUNT {
		angle_lmb_d := rand.float32() * m.TAU // Renamed
		dir_lmb_d := m.angle_to_vec2(angle_lmb_d) // Renamed
		speed_lmb_d := LMB_ENEMY_DEATH_PARTICLE_SPEED_BASE + rand.float32() * LMB_ENEMY_DEATH_PARTICLE_SPEED_RAND // Renamed
		life_lmb_d := LMB_ENEMY_DEATH_PARTICLE_LIFETIME_BASE + rand.float32() * LMB_ENEMY_DEATH_PARTICLE_LIFETIME_RAND // Renamed
		size_lmb_d := LMB_ENEMY_DEATH_PARTICLE_SIZE_BASE + rand.float32() * LMB_ENEMY_DEATH_PARTICLE_SIZE_RAND // Renamed
		angular_vel_lmb_d := rand.float32_range(-1.0, 1.0) * LMB_ENEMY_DEATH_PARTICLE_ANGULAR_VEL_MAX // Renamed
		particle_color_lmb_d := base_color; // Renamed
		particle_color_lmb_d.r = math.min(base_color.r * 1.2 + 0.2, 1.0);
		particle_color_lmb_d.g = math.min(base_color.g * 1.2 + 0.2, 1.0);
		particle_color_lmb_d.b = math.min(base_color.b * 1.2 + 0.2, 1.0);
		particle_color_lmb_d.a = 0.85; 
		emit_particle(Particle{
			pos=pos, vel=dir_lmb_d*speed_lmb_d, cloud_travel_vel={0,0}, color=particle_color_lmb_d, size=size_lmb_d, start_size=size_lmb_d,
            life_remaining=life_lmb_d, life_max=life_lmb_d, swirl_duration=0, rotation=rand.float32()*m.TAU, angular_vel=angular_vel_lmb_d,
            charge_center_pos={0,0}, is_burst_particle=true, is_swirling_charge=false, is_ammo_indicator=false, active=false, 
		})
	}
}

spawn_visual_ammo_charge_particles :: proc(charge_slot_index: int) {
    context = runtime.default_context()
    if charge_slot_index < 0 || charge_slot_index >= MAX_RMB_AMMO_CHARGES { return; }
    base_orbit_angle_offset_va := (f32(charge_slot_index) / f32(MAX_RMB_AMMO_CHARGES)) * m.TAU; // Renamed
    for i in 0..<RMB_AMMO_INDICATOR_PARTICLES_PER_CHARGE {
        particle_angle_within_group_va := (f32(i) / f32(RMB_AMMO_INDICATOR_PARTICLES_PER_CHARGE)) * m.TAU; // Renamed
        current_orbit_angle_va := base_orbit_angle_offset_va + particle_angle_within_group_va + (state.rmb_ammo_regen_timer * RMB_AMMO_INDICATOR_ORBIT_SPEED); // Renamed
        emit_particle(Particle{
            pos = state.player_pos, vel = {0,0}, cloud_travel_vel = {0,0}, color = RMB_AMMO_INDICATOR_COLOR,
            size = RMB_AMMO_INDICATOR_BASE_SIZE, start_size = RMB_AMMO_INDICATOR_BASE_SIZE,
            life_remaining = 1.0, life_max = 1.0, swirl_duration = 0,
            rotation = current_orbit_angle_va, 
            angular_vel = rand.float32_range(-1,1) * RMB_AMMO_INDICATOR_SELF_SPIN_SPEED, 
            charge_center_pos= m.vec2{f32(charge_slot_index), f32(i)}, 
            is_burst_particle= false, is_swirling_charge= false, is_ammo_indicator= true, active = false,
        });
    }
     fmt.printf("Spawned visual ammo for charge slot %d\n", charge_slot_index);
}

remove_visual_ammo_charge_particles :: proc(charge_slot_index_to_remove: int) {
    context = runtime.default_context()
    particles_removed_count := 0
    for i in 0..<MAX_PARTICLES {
        p_va_rem := &state.particles[i]; // Renamed
        if p_va_rem.active && p_va_rem.is_ammo_indicator && int(p_va_rem.charge_center_pos.x) == charge_slot_index_to_remove {
            if p_va_rem.has_active_sound {
                ma.sound_uninit(&p_va_rem.sound_hum)
                ma.sound_uninit(&p_va_rem.sound_whoosh)
                p_va_rem.has_active_sound = false
            }
            p_va_rem.active = false; 
            particles_removed_count += 1;
        }
    }
    if particles_removed_count > 0 {
        fmt.printf("Removed %d visual ammo particles for charge slot %d\n", particles_removed_count, charge_slot_index_to_remove);
    }
}

spawn_RMB_enemy_death_particles :: proc(pos: m.vec2) {
	context = runtime.default_context()
	base_death_color_rmb := RMB_PARTICLE_COLOR; // Renamed
	for _ in 0..<RMB_ENEMY_DEATH_PARTICLE_COUNT {
		angle_rmb_d := rand.float32() * m.TAU // Renamed
		dir_rmb_d := m.angle_to_vec2(angle_rmb_d) // Renamed
		speed_rmb_d := RMB_ENEMY_DEATH_PARTICLE_SPEED_BASE + rand.float32() * RMB_ENEMY_DEATH_PARTICLE_SPEED_RAND // Renamed
		life_rmb_d := RMB_ENEMY_DEATH_PARTICLE_LIFETIME_BASE + rand.float32() * RMB_ENEMY_DEATH_PARTICLE_LIFETIME_RAND // Renamed
		size_rmb_d := RMB_ENEMY_DEATH_PARTICLE_SIZE_BASE + rand.float32() * RMB_ENEMY_DEATH_PARTICLE_SIZE_RAND // Renamed
		angular_vel_rmb_d := rand.float32_range(-1.0, 1.0) * RMB_ENEMY_DEATH_PARTICLE_ANGULAR_VEL_MAX // Renamed
		particle_color_rmb_d := base_death_color_rmb; // Renamed
		particle_color_rmb_d.r = math.clamp(base_death_color_rmb.r + rand.float32_range(-0.1, 0.1), 0.5, 1.0);
		particle_color_rmb_d.g = math.clamp(base_death_color_rmb.g + rand.float32_range(-0.1, 0.1), 0.2, 0.8);
		particle_color_rmb_d.b = math.clamp(base_death_color_rmb.b + rand.float32_range(-0.1, 0.1), 0.7, 1.0);
		particle_color_rmb_d.a = rand.float32_range(0.6, 0.9); 
		emit_particle(Particle{
			pos=pos, vel=dir_rmb_d*speed_rmb_d, cloud_travel_vel={0,0}, color=particle_color_rmb_d, size=size_rmb_d, start_size=size_rmb_d,
            life_remaining=life_rmb_d, life_max=life_rmb_d, swirl_duration=0, rotation=rand.float32()*m.TAU, angular_vel=angular_vel_rmb_d,
            charge_center_pos={0,0}, is_burst_particle=true, is_swirling_charge=false, is_ammo_indicator=false, active=false, 
		})
	}
}

check_RMB_particle_enemy_collisions :: proc() {
    context = runtime.default_context()
    for i in 0..<MAX_PARTICLES {
        particle_rmb_coll := &state.particles[i] // Renamed
        if !particle_rmb_coll.active || particle_rmb_coll.is_ammo_indicator || particle_rmb_coll.is_burst_particle {
            continue;
        }
        particle_radius_rmb_coll := particle_rmb_coll.size * 0.5 // Renamed
        if particle_radius_rmb_coll <= 0.001 { continue }

        for j in 0..<MAX_ENEMIES {
            enemy_rmb_coll := &state.enemies[j] // Renamed
            if !enemy_rmb_coll.active || enemy_rmb_coll.is_dying { continue } 
            
            enemy_radius_rmb_coll := enemy_rmb_coll.current_size * 0.5 // Renamed
            if enemy_radius_rmb_coll <= 0.001 { continue }

            dist_sq_rmb_coll := m.len_sq_vec2(particle_rmb_coll.pos - enemy_rmb_coll.pos) // Renamed
            radii_sum_rmb_coll := particle_radius_rmb_coll + enemy_radius_rmb_coll // Renamed
            radii_sum_sq_rmb_coll := radii_sum_rmb_coll * radii_sum_rmb_coll // Renamed

            if dist_sq_rmb_coll < radii_sum_sq_rmb_coll {
                enemy_rmb_coll.hp -= PARTICLE_DAMAGE_VALUE 
                fmt.printf("RMB Hit: Enemy %p, HP before sound check: %d\n", enemy_rmb_coll, enemy_rmb_coll.hp);
                
                if enemy_rmb_coll.hp <= 0 {
                    if !enemy_rmb_coll.is_dying {
                        fmt.printf("RMB Kill branch: Playing death sound for enemy %p. is_dying: %t\n", enemy_rmb_coll, enemy_rmb_coll.is_dying);
                        ma.sound_seek_to_pcm_frame(&state.rmb_kill_sound, 0);
                        ma.sound_start(&state.rmb_kill_sound);
                    }
                } else {
                    fmt.printf("RMB Hit branch: Playing hit sound for enemy %p. HP: %d\n", enemy_rmb_coll, enemy_rmb_coll.hp);
                    ma.sound_seek_to_pcm_frame(&state.rmb_hit_sound, 0);
                    ma.sound_start(&state.rmb_hit_sound);
                }

                if particle_rmb_coll.has_active_sound {
                    ma.sound_uninit(&particle_rmb_coll.sound_hum)
                    ma.sound_uninit(&particle_rmb_coll.sound_whoosh)
                    particle_rmb_coll.has_active_sound = false
                }
                particle_rmb_coll.active = false 

                if enemy_rmb_coll.hp <= 0 && !enemy_rmb_coll.is_dying { 
                    enemy_rmb_coll.is_dying = true;
                    if enemy_rmb_coll.type == .GRUNT {
                        enemy_rmb_coll.dying_timer = GRUNT_DEATH_ANIM_DURATION;
                        enemy_rmb_coll.death_anim_max_duration = GRUNT_DEATH_ANIM_DURATION;
                    } else if enemy_rmb_coll.type == .SLOWBOY {
                        enemy_rmb_coll.dying_timer = SLOWBOY_DEATH_ANIM_DURATION;
                        enemy_rmb_coll.death_anim_max_duration = SLOWBOY_DEATH_ANIM_DURATION;
                    } else { 
                        enemy_rmb_coll.dying_timer = GRUNT_DEATH_ANIM_DURATION; 
                        enemy_rmb_coll.death_anim_max_duration = GRUNT_DEATH_ANIM_DURATION;
                    }
                    enemy_rmb_coll.death_rect_offset = 0.0;
                    spawn_RMB_enemy_death_particles(enemy_rmb_coll.pos); 
                    if enemy_rmb_coll.type == .GRUNT && !state.first_grunt_killed {
                        state.first_grunt_killed = true;
                        start_drum_err_rmb := ma.sound_start(&state.drum_track_sound); // Renamed
                        if start_drum_err_rmb == .SUCCESS { fmt.printf("--- First GRUNT killed! Starting drum track. ---\n"); } 
                        else { fmt.eprintf("!!! ERROR: Failed to start drum_track_sound! Error: %v\n", start_drum_err_rmb); }
                    }
                    // (<<< NEW SYNTH TRIGGER START >>>)
                    if enemy_rmb_coll.type == .SLOWBOY && !state.first_slowboy_killed {
                        state.first_slowboy_killed = true;
                        start_synth_err := ma.sound_start(&state.synth_track_sound);
                        if start_synth_err == .SUCCESS {
                            fmt.printf("--- First SLOWBOY killed! Starting synth track. ---\n");
                        } else {
                            fmt.eprintf("!!! ERROR: Failed to start synth_track_sound! Error: %v\n", start_synth_err);
                        }
                    }
                    // (<<< NEW SYNTH TRIGGER END >>>)
                }
                break 
            }
        }
    }
}

check_LMB_projectile_enemy_collisions :: proc() {
    context = runtime.default_context()
    for i in 0..<MAX_BLACKHOLES {
        proj_lmb_coll := &state.blackholes[i] // Renamed
        if !proj_lmb_coll.active { continue }
        proj_radius_lmb_coll := proj_lmb_coll.size * 0.5 // Renamed
        for j in 0..<MAX_ENEMIES {
            enemy_lmb_coll := &state.enemies[j] // Renamed
            if !enemy_lmb_coll.active || enemy_lmb_coll.is_dying { continue; } 

            enemy_radius_lmb_coll := enemy_lmb_coll.current_size * 0.5 // Renamed
            dist_sq_lmb_coll := m.len_sq_vec2(proj_lmb_coll.pos - enemy_lmb_coll.pos) // Renamed
            radii_sum_lmb_coll := proj_radius_lmb_coll + enemy_radius_lmb_coll // Renamed
            radii_sum_sq_lmb_coll := radii_sum_lmb_coll * radii_sum_lmb_coll // Renamed

            if dist_sq_lmb_coll < radii_sum_sq_lmb_coll {
                proj_lmb_coll.active = false    
                enemy_lmb_coll.hp -= LMB_PROJECTILE_DAMAGE; 
                fmt.printf("LMB Hit: Enemy %p, HP before sound check: %d\n", enemy_lmb_coll, enemy_lmb_coll.hp);
                if enemy_lmb_coll.hp <= 0 {
                    if !enemy_lmb_coll.is_dying {
                         fmt.printf("LMB Kill branch: Playing death sound for enemy %p. is_dying: %t\n", enemy_lmb_coll, enemy_lmb_coll.is_dying);
                         ma.sound_seek_to_pcm_frame(&state.lmb_kill_sound, 0);
                         ma.sound_start(&state.lmb_kill_sound);
                    }
                } else {
                    fmt.printf("LMB Hit branch: Playing hit sound for enemy %p. HP: %d\n", enemy_lmb_coll, enemy_lmb_coll.hp);
                    ma.sound_seek_to_pcm_frame(&state.lmb_hit_sound, 0);
                    ma.sound_start(&state.lmb_hit_sound);
                }

                if enemy_lmb_coll.hp <= 0 && !enemy_lmb_coll.is_dying { 
                    enemy_lmb_coll.is_dying = true;
                    if enemy_lmb_coll.type == .GRUNT {
                        enemy_lmb_coll.dying_timer = GRUNT_DEATH_ANIM_DURATION;
                        enemy_lmb_coll.death_anim_max_duration = GRUNT_DEATH_ANIM_DURATION;
                    } else if enemy_lmb_coll.type == .SLOWBOY {
                        enemy_lmb_coll.dying_timer = SLOWBOY_DEATH_ANIM_DURATION;
                        enemy_lmb_coll.death_anim_max_duration = SLOWBOY_DEATH_ANIM_DURATION;
                    } else { 
                        enemy_lmb_coll.dying_timer = GRUNT_DEATH_ANIM_DURATION;
                        enemy_lmb_coll.death_anim_max_duration = GRUNT_DEATH_ANIM_DURATION;
                    }
                    enemy_lmb_coll.death_rect_offset = 0.0;
                    spawn_LMB_enemy_death_particles(enemy_lmb_coll.pos, enemy_lmb_coll.color); 
                    if enemy_lmb_coll.type == .GRUNT && !state.first_grunt_killed {
                        state.first_grunt_killed = true;
                        start_drum_err_lmb := ma.sound_start(&state.drum_track_sound); // Renamed
                        if start_drum_err_lmb == .SUCCESS { fmt.printf("--- First GRUNT killed! Starting drum track. ---\n");} 
                        else { fmt.eprintf("!!! ERROR: Failed to start drum_track_sound! Error: %v\n", start_drum_err_lmb); }
                    }
                    // (<<< NEW SYNTH TRIGGER START >>>)
                     if enemy_lmb_coll.type == .SLOWBOY && !state.first_slowboy_killed {
                        state.first_slowboy_killed = true;
                        start_synth_err := ma.sound_start(&state.synth_track_sound);
                        if start_synth_err == .SUCCESS {
                            fmt.printf("--- First SLOWBOY killed! Starting synth track. ---\n");
                        } else {
                            fmt.eprintf("!!! ERROR: Failed to start synth_track_sound! Error: %v\n", start_synth_err);
                        }
                    }
                    // (<<< NEW SYNTH TRIGGER END >>>)
                }
                break 
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
        if !enemy_pe_coll.active || enemy_pe_coll.is_growing { continue }
        enemy_radius_pe_coll := enemy_pe_coll.current_size * 0.5 // Renamed
        if enemy_radius_pe_coll <= 0.001 { continue }
        dist_sq_pe_coll := m.dist_sq_vec2(state.player_pos, enemy_pe_coll.pos) // Renamed
        radii_sum_pe_coll := player_radius_pe_coll + enemy_radius_pe_coll // Renamed
        radii_sum_sq_pe_coll := radii_sum_pe_coll * radii_sum_pe_coll // Renamed
        if dist_sq_pe_coll < radii_sum_sq_pe_coll {
            state.player_hp -= ENEMY_GRUNT_DAMAGE_VALUE // Assuming grunt damage for now
            state.player_hp = math.max(state.player_hp, 0) 
            state.player_invulnerable_timer = PLAYER_INVULNERABILITY_DURATION
            fmt.printf("Player hit by ENEMY! HP: %d/%d. Invulnerable for %.2fs\n", state.player_hp, state.player_max_hp, state.player_invulnerable_timer)
            // TODO: Specific sound for player getting hit
            break 
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
    screen_width_mouse := sapp.widthf() // Renamed
    screen_height_mouse := sapp.heightf() // Renamed
    ndc_x_mouse := (2.0 * state.mouse_screen_pos.x / screen_width_mouse) - 1.0 // Renamed
    ndc_y_mouse := 1.0 - (2.0 * state.mouse_screen_pos.y / screen_height_mouse) // Renamed
    aspect_ratio_mouse := screen_width_mouse / screen_height_mouse // Renamed
    ortho_width_vp_mouse := ORTHO_HEIGHT * aspect_ratio_mouse // Renamed
    world_x_mouse := ndc_x_mouse * ortho_width_vp_mouse // Renamed
    world_y_mouse := ndc_y_mouse * ORTHO_HEIGHT // Renamed
    return {world_x_mouse, world_y_mouse}
}

spawn_blackhole_projectile_weapon :: proc() {
    context = runtime.default_context()
    if state.player_hp <= 0 { return; } 
    spawn_pos_bhpw := state.player_pos // Renamed
    target_world_pos_bhpw := get_mouse_world_pos() // Renamed
    direction_to_mouse_bhpw := target_world_pos_bhpw - spawn_pos_bhpw // Renamed
    direction_bhpw: m.vec2 // Renamed
    if m.len_sq_vec2(direction_to_mouse_bhpw) > 0.0001 { 
        direction_bhpw = m.norm_vec2(direction_to_mouse_bhpw)
    } else {
        if m.len_sq_vec2(state.player_vel) > 0.001 { direction_bhpw = m.norm_vec2(state.player_vel)
        } else { direction_bhpw = {0, 1} }
    }
    vel_bhpw := direction_bhpw * PROJECTILE_BLACKHOLE_INITIAL_SPEED // Renamed
    life_bhpw := f32(PROJECTILE_BLACKHOLE_LIFETIME) // Renamed
    rotation_angle_bhpw := math.atan2(direction_bhpw.y, direction_bhpw.x) - m.PI / 2.0 // Renamed
    new_proj_bhpw := Blackhole_Projectile { // Renamed
        pos = spawn_pos_bhpw, vel = vel_bhpw, size = PROJECTILE_BLACKHOLE_SCALE, rotation = rotation_angle_bhpw, 
        angular_vel = 0, life_remaining = life_bhpw, life_max = life_bhpw, active = false, 
    }
    emit_blackhole_projectile(new_proj_bhpw)
}

update_and_instance_blackholes :: proc(dt: f32) -> int {
    context = runtime.default_context()
    live_count_bh := 0 // Renamed
    for i in 0..<MAX_BLACKHOLES {
        if !state.blackholes[i].active { continue }
        p_bh := &state.blackholes[i] // Renamed
        p_bh.life_remaining -= dt
        if p_bh.life_remaining <= 0.0 { p_bh.active = false; continue }
        p_bh.pos += p_bh.vel * dt
        p_bh.rotation += p_bh.angular_vel * dt // This was 0 from spawn, but could be used
        if p_bh.rotation > m.TAU { p_bh.rotation -= m.TAU }
        if p_bh.rotation < 0    { p_bh.rotation += m.TAU }
        life_ratio_bh := p_bh.life_remaining / p_bh.life_max // Renamed
        if live_count_bh < MAX_BLACKHOLES {
            inst_bh := &state.blackhole_instance_data[live_count_bh] // Renamed
            inst_bh.instance_pos_size_rot = {p_bh.pos.x, p_bh.pos.y, p_bh.size, p_bh.rotation}
            inst_bh.instance_color = {1.0, 1.0, 1.0, life_ratio_bh} 
            live_count_bh += 1
        }
    }
    return live_count_bh
}


// --- Enemy System ---
emit_enemy :: proc(enemy_data: Enemy) {
    context = runtime.default_context()
    idx_to_write_en := state.next_enemy_index // Renamed
    state.enemies[idx_to_write_en] = enemy_data        
    state.enemies[idx_to_write_en].active = true       
    state.next_enemy_index = (state.next_enemy_index + 1) % MAX_ENEMIES
}

spawn_enemy :: proc(current_ortho_width: f32, current_ortho_height: f32, player_pos: m.vec2, type_to_spawn: EnemyType) { 
    context = runtime.default_context()
    start_pos_en: m.vec2 // Renamed
    valid_spawn_found_en := false // Renamed
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
    start_vel_en: m.vec2 = {0.0, 0.0} // Renamed
    initial_wander_angle_en := rand.float32() * m.TAU // Renamed
    initial_wander_vector_en := m.angle_to_vec2(initial_wander_angle_en) // Renamed

    enemy_to_spawn: Enemy
    if type_to_spawn == .GRUNT {
        base_grunt_rgb_en := m.vec3{0.9, 0.1, 0.7} // Renamed
        grunt_color_en := m.vec4{base_grunt_rgb_en.r, base_grunt_rgb_en.g, base_grunt_rgb_en.b, ENEMY_BASE_ALPHA} // Renamed
        enemy_to_spawn = Enemy {
            pos = start_pos_en, vel = start_vel_en, color = grunt_color_en, 
            target_size = ENEMY_GRUNT_SCALE, current_size = ENEMY_GRUNT_SCALE * ENEMY_INITIAL_SCALE_FACTOR, 
            grow_timer = ENEMY_GROW_DURATION, is_growing = true,                                             
            rotation = rand.float32() * m.TAU, angular_vel = (rand.float32() * 2.0 - 1.0) * ENEMY_MAX_ANGULAR_SPEED,
            hp = ENEMY_GRUNT_MAX_HP, type = .GRUNT, active = false, 
            current_wander_vector = initial_wander_vector_en,
            wander_timer = rand.float32_range(0.0, ENEMY_WANDER_DIRECTION_CHANGE_INTERVAL),
            is_dying = false, dying_timer = 0.0, death_rect_offset = 0.0,
            death_anim_max_duration = GRUNT_DEATH_ANIM_DURATION,
        }
    } else if type_to_spawn == .SLOWBOY {
        slowboy_color_initial_en := m.vec4{0.3, 0.7, 0.9, ENEMY_BASE_ALPHA} // Renamed
        enemy_to_spawn = Enemy {
            pos = start_pos_en, vel = start_vel_en, color = slowboy_color_initial_en, 
            target_size = ENEMY_SLOWBOY_BASE_SCALE * ENEMY_SLOWBOY_GLOW_CANVAS_SF, 
            current_size = ENEMY_SLOWBOY_BASE_SCALE * ENEMY_INITIAL_SCALE_FACTOR, 
            grow_timer = ENEMY_GROW_DURATION, is_growing = true,                                             
            rotation = rand.float32() * m.TAU, angular_vel = (rand.float32() * 2.0 - 1.0) * ENEMY_MAX_ANGULAR_SPEED * 0.5,
            hp = ENEMY_SLOWBOY_MAX_HP, type = .SLOWBOY, active = false, 
            current_wander_vector = initial_wander_vector_en,
            wander_timer = rand.float32_range(0.0, ENEMY_WANDER_DIRECTION_CHANGE_INTERVAL),
            is_dying = false, dying_timer = 0.0, death_rect_offset = 0.0,
            death_anim_max_duration = SLOWBOY_DEATH_ANIM_DURATION,
            is_winding_up_attack = false, attack_windup_timer = 0.0,
            has_locked_attack_trajectory = false, attack_charge_target_pos = {0,0},
            is_charging_attack = false, attack_charge_start_pos = {0,0},
        }
    } else {
        fmt.printf("spawn_enemy: WARNING - Unknown type_to_spawn: %v\n", type_to_spawn);
        return; 
    }
    emit_enemy(enemy_to_spawn)
}
update_and_instance_enemies :: proc(dt: f32) -> int {
    context = runtime.default_context()
    live_enemy_count := 0
    player_pos_uie := state.player_pos // Renamed

    for i in 0..<MAX_ENEMIES {
        if !state.enemies[i].active { continue }
        enemy_uie := &state.enemies[i] // Renamed

        has_updated_pos_for_charge_bounce_uie := false; // Renamed

        current_visual_scale_for_shader_uie: f32 // Renamed
        effect_params_x_uie: f32 = 0.0; // Renamed
        effect_params_y_uie: f32 = 0.0; // Renamed
        effect_params_z_uie: f32 = 1.0; // Renamed
        effect_params_w_uie: f32 = 1.0; // Renamed

        if enemy_uie.is_dying {
            effect_params_x_uie = 1.0; 
            effect_params_y_uie = enemy_uie.death_rect_offset;
            enemy_uie.dying_timer -= dt;
            enemy_uie.death_rect_offset += ENEMY_DEATH_RECT_SEPARATION_SPEED * dt;
            
            if enemy_uie.dying_timer <= 0.0 { enemy_uie.active = false; continue; }

            progress_raw_uie: f32 // Renamed
            if enemy_uie.death_anim_max_duration > 0.0 { 
                progress_raw_uie = 1.0 - math.clamp(enemy_uie.dying_timer / enemy_uie.death_anim_max_duration, 0.0, 1.0);
            } else { progress_raw_uie = 0.0;  }
            eased_progress_for_scale_uie := math.pow(progress_raw_uie, 2.5); // Renamed
            effect_params_w_uie = 1.0 - progress_raw_uie; 
            initial_part_uv_scale_uie : f32 = 1.0 / ENEMY_DEATH_QUAD_RENDER_SCALE_MULTIPLIER; // Renamed
            final_part_uv_scale_uie : f32 = ENEMY_DEATH_RECT_FINAL_SCALE_FACTOR / ENEMY_DEATH_QUAD_RENDER_SCALE_MULTIPLIER; // Renamed
            effect_params_z_uie = m.lerp(initial_part_uv_scale_uie, final_part_uv_scale_uie, eased_progress_for_scale_uie); 
            current_visual_scale_for_shader_uie = enemy_uie.target_size;
            enemy_uie.current_size = f32(m.lerp(enemy_uie.target_size, enemy_uie.target_size * ENEMY_DEATH_RECT_FINAL_SCALE_FACTOR, eased_progress_for_scale_uie)); 
        
        } else if enemy_uie.type == .SLOWBOY && enemy_uie.is_winding_up_attack {
            effect_params_x_uie = 0.0; 
            effect_params_y_uie = 1.0; 
            effect_params_z_uie = enemy_uie.attack_windup_timer; 
            effect_params_w_uie = SLOWBOY_ATTACK_WINDUP_TOTAL_DURATION; 
            current_visual_scale_for_shader_uie = enemy_uie.current_size; 
            enemy_uie.attack_windup_timer -= dt;
            if enemy_uie.attack_windup_timer <= SLOWBOY_ATTACK_LOCKON_TIME_REMAINING && !enemy_uie.has_locked_attack_trajectory {
                enemy_uie.attack_charge_target_pos = player_pos_uie; 
                enemy_uie.has_locked_attack_trajectory = true;
            }
            if enemy_uie.attack_windup_timer <= 0.0 {
                enemy_uie.is_winding_up_attack = false;
                enemy_uie.is_charging_attack = true;
                enemy_uie.attack_charge_start_pos = enemy_uie.pos;
                charge_direction_vec_uie := enemy_uie.attack_charge_target_pos - enemy_uie.attack_charge_start_pos; // Renamed
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
            else { effect_params_z_uie = 1.0; }
            effect_params_w_uie = 1.0; 

            enemy_uie.grow_timer -= dt;
            if enemy_uie.grow_timer <= 0.0 {
                enemy_uie.current_size = enemy_uie.target_size;
                enemy_uie.is_growing = false;
                enemy_uie.grow_timer = 0.0;
            } else {
                progress_grow_uie := 1.0 - (enemy_uie.grow_timer / ENEMY_GROW_DURATION); // Renamed
                progress_grow_uie = math.clamp(progress_grow_uie, 0.0, 1.0); 
                initial_actual_size_uie := enemy_uie.target_size * ENEMY_INITIAL_SCALE_FACTOR; // Renamed
                enemy_uie.current_size = m.lerp(initial_actual_size_uie, enemy_uie.target_size, progress_grow_uie);
            }
            current_visual_scale_for_shader_uie = enemy_uie.current_size;
            enemy_uie.rotation += enemy_uie.angular_vel * dt;
            enemy_uie.wander_timer -= dt;
            if enemy_uie.wander_timer <= 0.0 {
                new_wander_angle_uie := rand.float32() * m.TAU; // Renamed
                enemy_uie.current_wander_vector = m.angle_to_vec2(new_wander_angle_uie);
                enemy_uie.wander_timer = ENEMY_WANDER_DIRECTION_CHANGE_INTERVAL + rand.float32_range(-0.2, 0.2);
            }
            direction_to_player_strict_growing_uie := player_pos_uie - enemy_uie.pos; // Renamed
            final_direction_growing_uie := direction_to_player_strict_growing_uie; // Renamed
            dist_sq_to_player_growing_uie := m.len_sq_vec2(direction_to_player_strict_growing_uie); // Renamed
            if dist_sq_to_player_growing_uie > 0.001 {
                normalized_strict_direction_growing_uie := m.norm_vec2(direction_to_player_strict_growing_uie); // Renamed
                final_direction_growing_uie = normalized_strict_direction_growing_uie + (enemy_uie.current_wander_vector * ENEMY_WANDER_INFLUENCE);
            }
            current_speed_growing_uie : f32 = enemy_uie.type == .GRUNT ? ENEMY_GRUNT_SPEED : ENEMY_SLOWBOY_SPEED; // Renamed
            if dist_sq_to_player_growing_uie > 0.00001 {
                normalized_final_direction_growing_uie := m.norm_vec2(final_direction_growing_uie); // Renamed
                enemy_uie.vel = normalized_final_direction_growing_uie * current_speed_growing_uie;
            } else if m.len_sq_vec2(direction_to_player_strict_growing_uie) > 0.00001 {
                enemy_uie.vel = m.norm_vec2(direction_to_player_strict_growing_uie) * current_speed_growing_uie;
            } else { enemy_uie.vel = m.vec2_zero(); }
        } else { 
            enemy_uie.current_size = enemy_uie.target_size;
            current_visual_scale_for_shader_uie = enemy_uie.current_size; 
            enemy_uie.rotation += enemy_uie.angular_vel * dt;
            effect_params_x_uie = 0.0;
            effect_params_y_uie = 0.0;
            effect_params_w_uie = 1.0;
            if enemy_uie.type == .SLOWBOY { effect_params_z_uie = ENEMY_SLOWBOY_GLOW_CANVAS_SF; } 
            else { effect_params_z_uie = 1.0; }
            
            if enemy_uie.type == .SLOWBOY {
                player_dist_sq_uie := m.dist_sq_vec2(enemy_uie.pos, player_pos_uie); // Renamed
                if enemy_uie.is_charging_attack {
                    has_updated_pos_for_charge_bounce_uie = true; 
                    aspect_ratio_uie := sapp.widthf() / sapp.heightf(); // Renamed
                    current_ortho_width_uie := ORTHO_HEIGHT * aspect_ratio_uie; // Renamed
                    enemy_half_size_uie := enemy_uie.current_size * 0.5; // Renamed
                    min_x_uie := -current_ortho_width_uie + enemy_half_size_uie; max_x_uie :=  current_ortho_width_uie - enemy_half_size_uie; // Renamed
                    min_y_uie := -ORTHO_HEIGHT + enemy_half_size_uie; max_y_uie :=  ORTHO_HEIGHT - enemy_half_size_uie; // Renamed
                    enemy_uie.pos += enemy_uie.vel * dt;
                    if enemy_uie.pos.x < min_x_uie { enemy_uie.pos.x = min_x_uie; enemy_uie.vel.x *= -1; } 
                    else if enemy_uie.pos.x > max_x_uie { enemy_uie.pos.x = max_x_uie; enemy_uie.vel.x *= -1; }
                    if enemy_uie.pos.y < min_y_uie { enemy_uie.pos.y = min_y_uie; enemy_uie.vel.y *= -1; } 
                    else if enemy_uie.pos.y > max_y_uie { enemy_uie.pos.y = max_y_uie; enemy_uie.vel.y *= -1; }
                    charge_distance_world_units_uie : f32 = ORTHO_HEIGHT * 2.0 * SLOWBOY_ATTACK_CHARGE_SCREEN_FRACTION; // Renamed
                    charge_distance_sq_uie := charge_distance_world_units_uie * charge_distance_world_units_uie; // Renamed
                    if m.dist_sq_vec2(enemy_uie.pos, enemy_uie.attack_charge_start_pos) >= charge_distance_sq_uie {
                        enemy_uie.is_charging_attack = false; enemy_uie.vel = {0,0}; 
                    }
                } else { 
                    if player_dist_sq_uie < (SLOWBOY_ATTACK_DETECT_RANGE * SLOWBOY_ATTACK_DETECT_RANGE) && !enemy_uie.is_winding_up_attack && !enemy_uie.is_charging_attack {
                        enemy_uie.is_winding_up_attack = true; enemy_uie.attack_windup_timer = SLOWBOY_ATTACK_WINDUP_TOTAL_DURATION;
                        enemy_uie.has_locked_attack_trajectory = false; enemy_uie.is_charging_attack = false;
                        enemy_uie.vel = {0,0}; 
                    } else {
                        enemy_uie.wander_timer -= dt;
                        if enemy_uie.wander_timer <= 0.0 {
                            new_wander_angle_norm_uie := rand.float32() * m.TAU; // Renamed
                            enemy_uie.current_wander_vector = m.angle_to_vec2(new_wander_angle_norm_uie);
                            enemy_uie.wander_timer = ENEMY_WANDER_DIRECTION_CHANGE_INTERVAL + rand.float32_range(-0.2, 0.2);
                        }
                        direction_to_player_strict_normal_uie := player_pos_uie - enemy_uie.pos; // Renamed
                        final_direction_normal_uie := direction_to_player_strict_normal_uie; // Renamed
                        dist_sq_to_player_normal_uie := m.len_sq_vec2(direction_to_player_strict_normal_uie); // Renamed
                        if dist_sq_to_player_normal_uie > 0.001 {
                            normalized_strict_direction_normal_uie := m.norm_vec2(direction_to_player_strict_normal_uie); // Renamed
                            final_direction_normal_uie = normalized_strict_direction_normal_uie + (enemy_uie.current_wander_vector * ENEMY_WANDER_INFLUENCE);
                        }
                        if dist_sq_to_player_normal_uie > 0.00001 {
                            normalized_final_direction_normal_uie := m.norm_vec2(final_direction_normal_uie); // Renamed
                            enemy_uie.vel = normalized_final_direction_normal_uie * ENEMY_SLOWBOY_SPEED;
                        } else if m.len_sq_vec2(direction_to_player_strict_normal_uie) > 0.00001 {
                             enemy_uie.vel = m.norm_vec2(direction_to_player_strict_normal_uie) * ENEMY_SLOWBOY_SPEED;
                        } else { enemy_uie.vel = m.vec2_zero(); }
                    }
                }
            } else if enemy_uie.type == .GRUNT {
                enemy_uie.wander_timer -= dt;
                if enemy_uie.wander_timer <= 0.0 {
                    new_wander_angle_grunt_uie := rand.float32() * m.TAU; // Renamed
                    enemy_uie.current_wander_vector = m.angle_to_vec2(new_wander_angle_grunt_uie);
                    enemy_uie.wander_timer = ENEMY_WANDER_DIRECTION_CHANGE_INTERVAL + rand.float32_range(-0.2, 0.2);
                }
                direction_to_player_strict_grunt_uie := player_pos_uie - enemy_uie.pos; // Renamed
                final_direction_grunt_uie := direction_to_player_strict_grunt_uie; // Renamed
                dist_sq_to_player_grunt_uie := m.len_sq_vec2(direction_to_player_strict_grunt_uie); // Renamed
                if dist_sq_to_player_grunt_uie > 0.001 {
                    normalized_strict_direction_grunt_uie := m.norm_vec2(direction_to_player_strict_grunt_uie); // Renamed
                    final_direction_grunt_uie = normalized_strict_direction_grunt_uie + (enemy_uie.current_wander_vector * ENEMY_WANDER_INFLUENCE);
                }
                if dist_sq_to_player_grunt_uie > 0.00001 {
                    normalized_final_direction_grunt_uie := m.norm_vec2(final_direction_grunt_uie); // Renamed
                    enemy_uie.vel = normalized_final_direction_grunt_uie * ENEMY_GRUNT_SPEED;
                } else if m.len_sq_vec2(direction_to_player_strict_grunt_uie) > 0.00001 {
                     enemy_uie.vel = m.norm_vec2(direction_to_player_strict_grunt_uie) * ENEMY_GRUNT_SPEED;
                } else { enemy_uie.vel = m.vec2_zero(); }
            }
        }
        
        if !has_updated_pos_for_charge_bounce_uie { enemy_uie.pos += enemy_uie.vel * dt;  }
        if enemy_uie.rotation > m.TAU { enemy_uie.rotation -= m.TAU; }
        if enemy_uie.rotation < 0    { enemy_uie.rotation += m.TAU; }

        if live_enemy_count < MAX_ENEMIES {
            inst_uie := &state.enemy_instance_data[live_enemy_count]; // Renamed
            inst_uie.instance_pos = enemy_uie.pos;
            inst_uie.instance_main_rotation = enemy_uie.rotation;
            inst_uie.instance_visual_scale = current_visual_scale_for_shader_uie * 3.0; // This 3.0 might be related to the quad size used (particle_quad_vbo). If base quad is -0.5 to 0.5 (size 1), then scale is direct.
            inst_uie.instance_color = enemy_uie.color;
            inst_uie.instance_effect_params = {effect_params_x_uie, effect_params_y_uie, effect_params_z_uie, effect_params_w_uie};
            if enemy_uie.type == .GRUNT { inst_uie.instance_enemy_type = 0.0; } 
            else if enemy_uie.type == .SLOWBOY { inst_uie.instance_enemy_type = 1.0; } 
            else { inst_uie.instance_enemy_type = 0.0; }
            live_enemy_count += 1;
        }
    }
    return live_enemy_count
}

frame :: proc "c" () {
    context = runtime.default_context()
    width_f := sapp.widthf(); height_f := sapp.heightf(); aspect_f := width_f / height_f; // Renamed
    current_time_f := f32(sapp.frame_count()) / 60.0; // Renamed
    delta_time_f := f32(sapp.frame_duration()); delta_time_f = math.min(delta_time_f, 1.0/15.0); // Renamed

    state.player_invulnerable_timer = math.max(0.0, state.player_invulnerable_timer - delta_time_f);
    state.rmb_cooldown_timer = math.max(0.0, state.rmb_cooldown_timer - delta_time_f)
    state.lmb_cooldown_timer = math.max(0.0, state.lmb_cooldown_timer - delta_time_f)

    if state.player_hp > 0 {
         if state.current_rmb_ammo_charges < MAX_RMB_AMMO_CHARGES {
            state.rmb_ammo_regen_timer -= delta_time_f;
            if state.rmb_ammo_regen_timer <= 0.0 {
                spawn_visual_ammo_charge_particles(state.current_rmb_ammo_charges);
                state.current_rmb_ammo_charges += 1;
                state.rmb_ammo_regen_timer = RMB_AMMO_REGEN_INTERVAL; 
                fmt.printf("RMB Ammo Charge Regenerated! Current: %d/%d\n", state.current_rmb_ammo_charges, MAX_RMB_AMMO_CHARGES);
            }
        }
        accel_input_f := m.vec2_zero(); // Renamed
        if state.key_w_down {accel_input_f.y+=1.0}; if state.key_s_down {accel_input_f.y-=1.0}; 
        if state.key_a_down {accel_input_f.x-=1.0}; if state.key_d_down {accel_input_f.x+=1.0};  
        if m.len_sq_vec2(accel_input_f) > 0.001 {accel_input_f=m.norm_vec2(accel_input_f)}; 
        final_accel_f := accel_input_f*PLAYER_ACCELERATION; // Renamed
        if state.key_s_down && !state.key_w_down && accel_input_f.y < -0.5 { final_accel_f *= PLAYER_REVERSE_FACTOR };
        state.player_vel += final_accel_f*delta_time_f; 
        damping_factor_f := math.max(0.0, 1.0-PLAYER_DAMPING*delta_time_f); // Renamed
        state.player_vel *= damping_factor_f; 
        if m.len_sq_vec2(state.player_vel) > f32(PLAYER_MAX_SPEED*PLAYER_MAX_SPEED) { state.player_vel=m.norm_vec2(state.player_vel)*PLAYER_MAX_SPEED }; 
        state.player_pos += state.player_vel*delta_time_f;

        rmb_pressed_this_frame_f := state.rmb_down && !state.previous_rmb_down; // Renamed
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

    current_ortho_width_for_bounds_f := ORTHO_HEIGHT * aspect_f // Renamed
    bounce_min_x_f : f32 = -current_ortho_width_for_bounds_f + PLAYER_CORE_WORLD_RADIUS // Renamed
    bounce_max_x_f : f32 =  current_ortho_width_for_bounds_f - PLAYER_CORE_WORLD_RADIUS // Renamed
    bounce_min_y_f : f32 = -ORTHO_HEIGHT + PLAYER_CORE_WORLD_RADIUS // Renamed
    bounce_max_y_f : f32 =  ORTHO_HEIGHT - PLAYER_CORE_WORLD_RADIUS // Renamed
    if state.player_pos.x < bounce_min_x_f { state.player_pos.x = bounce_min_x_f; if state.player_vel.x < 0 { state.player_vel.x *= -PLAYER_BOUNCE_DAMPING_FACTOR }} 
    else if state.player_pos.x > bounce_max_x_f { state.player_pos.x = bounce_max_x_f; if state.player_vel.x > 0 { state.player_vel.x *= -PLAYER_BOUNCE_DAMPING_FACTOR }}
    if state.player_pos.y < bounce_min_y_f { state.player_pos.y = bounce_min_y_f; if state.player_vel.y < 0 { state.player_vel.y *= -PLAYER_BOUNCE_DAMPING_FACTOR }} 
    else if state.player_pos.y > bounce_max_y_f { state.player_pos.y = bounce_max_y_f; if state.player_vel.y > 0 { state.player_vel.y *= -PLAYER_BOUNCE_DAMPING_FACTOR }}
    
    state.grunt_spawn_timer -= delta_time_f;
    if state.grunt_spawn_timer <= 0.0 {
        current_ortho_width_for_spawn_f := ORTHO_HEIGHT * aspect_f; // Renamed
        spawn_enemy(current_ortho_width_for_spawn_f, ORTHO_HEIGHT, state.player_pos, .GRUNT);
        state.grunt_spawn_timer = 1.0; 
    }
    state.slowboy_spawn_timer -= delta_time_f;
    if state.slowboy_spawn_timer <= 0.0 {
        current_ortho_width_for_spawn_f_sb := ORTHO_HEIGHT * aspect_f; // Renamed
        spawn_enemy(current_ortho_width_for_spawn_f_sb, ORTHO_HEIGHT, state.player_pos, .SLOWBOY);
        state.slowboy_spawn_timer = 5.0; 
    }

    state.num_active_particles = update_and_instance_particles(delta_time_f);
    state.num_active_enemies = update_and_instance_enemies(delta_time_f); 
    state.num_active_blackholes = update_and_instance_blackholes(delta_time_f);

    check_LMB_projectile_enemy_collisions();
    check_RMB_particle_enemy_collisions();
    check_player_enemy_collisions(); 

    state.bg_fs_params={tick=current_time_f, resolution={width_f,height_f}, bg_option=1}; 
    state.player_fs_params={
        tick=current_time_f, resolution={width_f,height_f}, player_hp_uniform=f32(state.player_hp), 
        player_max_hp_uniform=f32(state.player_max_hp), player_invulnerable_timer_uniform = state.player_invulnerable_timer,
        player_invulnerability_duration_uniform = PLAYER_INVULNERABILITY_DURATION,
    }; 
    state.particle_fs_params={tick=current_time_f};
    state.enemy_fs_params={tick=current_time_f}; 
    state.blackhole_fs_params={tick=current_time_f};

    ortho_width_vp_f := ORTHO_HEIGHT*aspect_f; // Renamed
    proj_f := m.ortho(-ortho_width_vp_f,ortho_width_vp_f,-ORTHO_HEIGHT,ORTHO_HEIGHT,-1.0,1.0); // Renamed
    view_f := m.identity(); view_proj_f := m.mul(proj_f,view_f); // Renamed
    
    scale_mat_f := m.scale(m.vec3{PLAYER_SCALE,PLAYER_SCALE,1.0}); // Renamed
    translate_mat_f := m.translate(m.vec3{state.player_pos.x,state.player_pos.y,0.0}); // Renamed
    model_f := m.mul(translate_mat_f,scale_mat_f); // Renamed
    state.player_vs_params.mvp=m.mul(view_proj_f,model_f); 
    
    state.particle_vs_params.view_proj=view_proj_f;
    state.enemy_vs_params.view_proj=view_proj_f; 
    state.blackhole_vs_params.view_proj=view_proj_f;


    sg.begin_pass({action=state.pass_action, swapchain=sglue.swapchain() });
    sg.apply_pipeline(state.bg_pip); sg.apply_bindings(state.bind); sg.apply_uniforms(UB_bg_fs_params, sg.Range{ptr=&state.bg_fs_params, size=size_of(Bg_Fs_Params)}); sg.draw(0,4,1);
    sg.apply_pipeline(state.player_pip); sg.apply_bindings(state.bind); sg.apply_uniforms(UB_Player_Vs_Params, sg.Range{ptr=&state.player_vs_params, size=size_of(Player_Vs_Params)}); sg.apply_uniforms(UB_Player_Fs_Params, sg.Range{ptr=&state.player_fs_params, size=size_of(Player_Fs_Params)}); sg.draw(0,4,1);
	
    if state.num_active_particles > 0 {
		sg.apply_pipeline(state.particle_pip); sg.apply_bindings(state.particle_bind); sg.update_buffer(state.particle_instance_vbo, sg.Range{ptr=rawptr(&state.particle_instance_data[0]), size=uint(state.num_active_particles)*size_of(Particle_Instance_Data)});
		sg.apply_uniforms(UB_particle_vs_params, sg.Range{ptr=&state.particle_vs_params, size=size_of(Particle_Vs_Params)}); sg.apply_uniforms(UB_particle_fs_params, sg.Range{ptr=&state.particle_fs_params, size=size_of(Particle_Fs_Params)});
		sg.draw(0, 4, state.num_active_particles);
	}
    if state.num_active_blackholes > 0 {
        sg.apply_pipeline(state.blackhole_pip); sg.apply_bindings(state.blackhole_bind); 
        sg.update_buffer(state.blackhole_instance_vbo, sg.Range{ptr=rawptr(&state.blackhole_instance_data[0]), size=uint(state.num_active_blackholes)*size_of(Blackhole_Instance_Data)});
		sg.apply_uniforms(UB_blackhole_vs_params, sg.Range{ptr=&state.blackhole_vs_params, size=size_of(Blackhole_Vs_Params)}); 
        sg.apply_uniforms(UB_blackhole_fs_params, sg.Range{ptr=&state.blackhole_fs_params, size=size_of(Blackhole_Fs_Params)});
		sg.draw(0, 4, state.num_active_blackholes);
    }
    if state.num_active_enemies > 0 {
        sg.apply_pipeline(state.enemy_pip); sg.apply_bindings(state.enemy_bind); 
        sg.update_buffer(state.enemy_instance_vbo, sg.Range{ptr=rawptr(&state.enemy_instance_data[0]), size=uint(state.num_active_enemies)*size_of(Enemy_Instance_Data)})
        sg.apply_uniforms(UB_enemy_vs_params, sg.Range{ptr=&state.enemy_vs_params, size=size_of(Enemy_Vs_Params)}) 
        sg.apply_uniforms(UB_enemy_fs_params, sg.Range{ptr=&state.enemy_fs_params, size=size_of(Enemy_Fs_Params)}) 
        sg.draw(0, 4, state.num_active_enemies)
    }
    sg.end_pass(); sg.commit();
}


cleanup :: proc "c" () { 
    context=runtime.default_context(); 

