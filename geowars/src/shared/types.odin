package shared

import sg "../vendor/sokol/gfx"
import m "../vendor/math"
import ma "../vendor/miniaudio"
import rand "core:math/rand"
import "base:runtime"

// --- Constants ---
MAX_PARTICLES :: 2048
MAX_ENEMIES :: 128
MAX_BLACKHOLES :: 64
PLAYER_DASH_TRAIL_LENGTH :: 4

// World Constants
ORTHO_HEIGHT :: 7.0 // Zoomed in from 10.0 to make entities bigger and speed feel faster
// Arena Size (World Space)
ARENA_WIDTH  :: 30.0 
ARENA_HEIGHT :: 20.0
ARENA_CORNER_CUT :: 8.0 // Matches shader logic
ARENA_RADIUS :: 18.0 // For Octagon logic closer to edges

PLAYER_SCALE :: 0.6
PLAYER_SPEED :: 12.0 // Cap max speed
PLAYER_ACCEL :: 45.0 // Acceleration force
PLAYER_FRICTION :: 4.0 // Damping factor
PLAYER_ROTATION_SPEED :: 15.0 // Lerp speed for rotation
PLAYER_CORE_WORLD_RADIUS :: 0.22 

// Arena
ARENA_HEX_RADIUS :: 13.0 // Size of Hexagon



// --- Camera Struct ---
Camera :: struct {
    pos: m.vec2,
    target_pos: m.vec2,
    zoom: f32,
    target_zoom: f32,
    shake_offset: m.vec2,
    shake_duration: f32,
    shake_intensity: f32,
}

// --- Enemy Type Enum ---
EnemyType :: enum {
    GRUNT,
    SLOWBOY,
    WEAVER,
    GRAVITRON,
    TRACER,
    ELITE,
    BOSS_CHROME_ORB,
}

// --- Player Struct ---
Player :: struct {
    pos: m.vec2,
    vel: m.vec2,
    rotation: f32,
    hp: int,
    max_hp: int,
    invulnerable_timer: f32,
    defeated_message_shown: bool,

    is_dashing: bool,
    dash_timer: f32,
    dash_cooldown_timer: f32,

    dash_trail_pos: [PLAYER_DASH_TRAIL_LENGTH]m.vec2,
    dash_trail_count: int,
    dash_trail_spawn_timer: f32,

    current_rmb_ammo_charges: int,
    rmb_ammo_regen_timer: f32,
    lmb_cooldown_timer: f32,
    rmb_cooldown_timer: f32,
}

Particle :: struct {
    pos:              m.vec2,
    vel:              m.vec2,
    cloud_travel_vel: m.vec2, 
    color:            m.vec4,
    size:             f32,
    start_size:       f32,
    drag:             f32,
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

// --- Level and Stage System Structs ---

EnemySpawnConfig :: struct {
    enemy_type: EnemyType,
    count: int,
    min_spawn_delay: f32,
    max_spawn_delay: f32,
    start_delay: f32,
}

StageDefinition :: struct {
    enemy_configs: []EnemySpawnConfig,
}

LevelDefinition :: struct {
    stages: []StageDefinition,
    boss_config: EnemySpawnConfig,
}

// --- Structs for Tracking Active Stage Progress ---

ActiveStageEnemySpawnState :: struct {
    config_index: int,
    spawn_timer: f32,
    spawned_count: int,
    remaining_to_spawn: int,
}

ActiveStageState :: struct {
    enemy_spawn_states: [dynamic]ActiveStageEnemySpawnState,
    all_enemies_for_stage_spawned: bool,
}

GameProgression :: struct {
    current_level_index: int,
    current_stage_index: int,
    active_stage: ActiveStageState,
    total_enemies_defined_for_current_stage: int,
    enemies_defeated_in_current_stage: int,
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
    boss_move_direction: f32,
    boss_detection_print_cooldown: f32,

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

// --- Shader Uniform Structs (Inferred from usage) ---
// These match what sokol-shdc would generate (or manually defined if not using tool in this env)
// Assuming they are defined in shader.odin, but if we need them here for GameState:
// We can just rely on `shader.odin` if it is in package shared.
// Does `shader.odin` package declaration match?
// I need to check `shader.odin`.

// For now, I will assume GameState fields will use types available in this package or imported.

GameState :: struct {
    progression: GameProgression,
    pass_action: sg.Pass_Action,
    bind: sg.Bindings,

    // Pipelines
    bg_pip: sg.Pipeline,
    player_pip: sg.Pipeline,
    particle_pip: sg.Pipeline,
    line_pip: sg.Pipeline, // For Grid
    enemy_pip: sg.Pipeline,
    blackhole_pip: sg.Pipeline,

    // Bindings
    line_bind: sg.Bindings, // For Grid VBO

    // Shader Params - assuming defined in shader.odin in package shared
    bg_fs_params: Bg_Fs_Params,
    player_vs_params: Player_Vs_Params,
    player_fs_params: Player_Fs_Params,
    particle_vs_params: Particle_Vs_Params,
    particle_fs_params: Particle_Fs_Params,
    enemy_vs_params: Enemy_Vs_Params,
    enemy_fs_params: Enemy_Fs_Params,
    blackhole_vs_params: Blackhole_Vs_Params,
    blackhole_fs_params: Blackhole_Fs_Params,

    audio_engine: ma.engine,
    lmb_sound: ma.sound,
    lmb_hit_sound: ma.sound,
    lmb_kill_sound: ma.sound,
    rmb_hit_sound: ma.sound,
    rmb_kill_sound: ma.sound,
    drum_track_sound: ma.sound,
    synth_track_sound: ma.sound,

    first_grunt_killed: bool,
    first_slowboy_killed: bool,

    player: Player,

    mouse_screen_pos: m.vec2,

    particles: [MAX_PARTICLES]Particle,
    particle_instance_data: [MAX_PARTICLES]Particle_Instance_Data,
    particle_quad_vbo: sg.Buffer,
    particle_instance_vbo: sg.Buffer,
    particle_bind: sg.Bindings,
    next_particle_index: int,
    num_active_particles: int,

    // Blackholes moved to ProjectileManager, but we might still have render resources here if not fully decoupled?
    // ProjectileManager handles its own VBOs now.

    enemies: [MAX_ENEMIES]Enemy,
    enemy_instance_data: [MAX_ENEMIES]Enemy_Instance_Data,
    enemy_instance_vbo: sg.Buffer,
    enemy_bind: sg.Bindings,
    next_enemy_index: int,
    num_active_enemies: int,

    grunt_spawn_timer: f32,
    slowboy_spawn_timer: f32,

    // Gravitron Logic State
    closest_gravitron_dist_sq: f32,
    closest_gravitron_pos: m.vec2,
    
    score: int,

    // Camera
    camera: Camera,
}

Vertex :: struct {
    pos: m.vec3,
    color: m.vec4,
}

// Camera definition removed (duplicate)
