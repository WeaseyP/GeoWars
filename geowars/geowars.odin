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
LMB_SOUND_AMPLITUDE :: 0.25
lmb_sound_pcm_data: [LMB_SOUND_FRAMES]f32; // Buffer to hold the generated PCM data
lmb_sound_audio_buffer: ma.audio_buffer; // Miniaudio's wrapper for the PCM data

// RMB Particle Sound Definitions
RMB_HUM_FREQUENCY :: 100.0
RMB_HUM_AMPLITUDE :: 0.1  // Quieter hum, reduced further
RMB_PARTICLE_SOUND_DURATION_FRAMES :: LMB_SOUND_SAMPLE_RATE / 2 // 0.5 seconds of audio data for looping segments

RMB_WHOOSH_AMPLITUDE :: 0.25 // Whoosh can be a bit louder, but reduced
MAX_PARTICLE_SPEED_FOR_SOUND_EFFECT :: 5.0 // Adjust this value based on typical particle speeds

// Global PCM data buffers and Miniaudio buffer objects for RMB sounds
rmb_hum_pcm_data: [RMB_PARTICLE_SOUND_DURATION_FRAMES]f32;
rmb_whoosh_pcm_data: [RMB_PARTICLE_SOUND_DURATION_FRAMES]f32;

rmb_hum_audio_buffer: ma.audio_buffer;
rmb_whoosh_audio_buffer: ma.audio_buffer;

// LMB Hit Sound Effects Definitions
LMB_HIT_WHOOSH_DURATION_FRAMES :: LMB_SOUND_SAMPLE_RATE / 10 // 0.1 seconds
LMB_HIT_WHOOSH_AMPLITUDE :: 0.4

LMB_KILL_EXPLOSION_DURATION_FRAMES :: LMB_SOUND_SAMPLE_RATE / 2 // 0.5 seconds
LMB_KILL_EXPLOSION_AMPLITUDE :: 0.5

// Global PCM data buffers and Miniaudio buffer objects for LMB hit sounds
lmb_hit_whoosh_pcm_data: [LMB_HIT_WHOOSH_DURATION_FRAMES]f32;
lmb_hit_whoosh_audio_buffer: ma.audio_buffer;

lmb_kill_explosion_pcm_data: [LMB_KILL_EXPLOSION_DURATION_FRAMES]f32;
lmb_kill_explosion_audio_buffer: ma.audio_buffer;

// Enemy Hit Sound Definitions
ENEMY_HIT_SOUND_DURATION_MS :: 50
ENEMY_HIT_SOUND_FRAMES :: LMB_SOUND_SAMPLE_RATE * ENEMY_HIT_SOUND_DURATION_MS / 1000
ENEMY_HIT_SOUND_START_FREQ :: 800.0
ENEMY_HIT_SOUND_END_FREQ :: 600.0
ENEMY_HIT_SOUND_AMPLITUDE :: 0.35

// Enemy Death Sound Definitions
ENEMY_DEATH_SOUND_DURATION_MS :: 200
ENEMY_DEATH_SOUND_FRAMES :: LMB_SOUND_SAMPLE_RATE * ENEMY_DEATH_SOUND_DURATION_MS / 1000
ENEMY_DEATH_SOUND_NOISE_DURATION_FRAMES :: ENEMY_DEATH_SOUND_FRAMES / 4 // Duration of the initial noise burst
ENEMY_DEATH_SOUND_NOISE_AMPLITUDE :: 0.25 // For a short burst of noise
ENEMY_DEATH_SOUND_SINE_START_FREQ :: 250.0
ENEMY_DEATH_SOUND_SINE_END_FREQ :: 50.0
ENEMY_DEATH_SOUND_SINE_AMPLITUDE :: 0.20

// Drum Track Definitions
DRUM_TRACK_SAMPLE_RATE :: LMB_SOUND_SAMPLE_RATE 
DRUM_TRACK_CHANNELS :: LMB_SOUND_CHANNELS    
DRUM_TRACK_BPM :: 160.0
DRUM_TRACK_BEATS_PER_BAR :: 4
DRUM_TRACK_NUM_BARS :: 2 
DRUM_TRACK_SECONDS_PER_BEAT :: 60.0 / DRUM_TRACK_BPM
DRUM_TRACK_AMPLITUDE :: 0.6 

drum_track_pcm_data: []f32; 
drum_track_audio_buffer: ma.audio_buffer;

// SYNTH TRACK DEFINITIONS (<<< NEW SECTION START >>>)
SYNTH_TRACK_SAMPLE_RATE :: DRUM_TRACK_SAMPLE_RATE
SYNTH_TRACK_CHANNELS    :: DRUM_TRACK_CHANNELS
SYNTH_TRACK_BPM         :: DRUM_TRACK_BPM 
SYNTH_TRACK_BEATS_PER_BAR :: DRUM_TRACK_BEATS_PER_BAR
SYNTH_TRACK_NUM_BARS    :: DRUM_TRACK_NUM_BARS 

SYNTH_TRACK_AMPLITUDE   :: 0.30 // Master amplitude for the synth track

// ADSR for synth notes
SYNTH_NOTE_ATTACK_TIME_S  :: 0.02
SYNTH_NOTE_DECAY_TIME_S   :: 0.1
SYNTH_NOTE_SUSTAIN_LEVEL  :: 0.6
SYNTH_NOTE_RELEASE_TIME_S :: 0.05

synth_track_pcm_data: []f32; 
synth_track_audio_buffer: ma.audio_buffer;
// (<<< NEW SECTION END >>>)

// Global PCM data buffers and Miniaudio buffer objects for enemy sounds
enemy_hit_sound_pcm_data: [ENEMY_HIT_SOUND_FRAMES]f32;
enemy_death_sound_pcm_data: [ENEMY_DEATH_SOUND_FRAMES]f32;

enemy_hit_sound_audio_buffer: ma.audio_buffer;
enemy_death_sound_audio_buffer: ma.audio_buffer;

// =============================================================================
// START: Package-Level Declarations
// =============================================================================

MAX_PARTICLES :: 2048
DEATH_BURST_PARTICLE_COUNT :: 150
MAX_ENEMIES :: 128 
MAX_BLACKHOLES :: 64 

// --- Constants ---
ORTHO_HEIGHT :: 1.5
PLAYER_ACCELERATION       :: 15.0
PLAYER_REVERSE_FACTOR     :: 0.5
PLAYER_DAMPING            :: 2.5
PLAYER_MAX_SPEED          :: 7.0
PLAYER_DASH_SPEED_MULT    :: 1.5  // Multiplier for max speed during dash
PLAYER_DASH_DURATION      :: 0.15 // Duration of the dash in seconds
PLAYER_DASH_COOLDOWN      :: 3.0  // Cooldown time in seconds
PLAYER_DASH_TRAIL_LENGTH      :: 4; // Number of after-images
PLAYER_DASH_TRAIL_SPAWN_RATE  :: 0.035; // Time in seconds between spawning each trail point
PLAYER_SCALE              :: 0.15
PLAYER_BOUNCE_BOUNDARY_OFFSET :: 0.1
PLAYER_CORE_SHADER_RADIUS :: 0.04
PLAYER_UV_SPACE_EXTENT    :: 0.5
PLAYER_CORE_WORLD_RADIUS :: (PLAYER_CORE_SHADER_RADIUS / PLAYER_UV_SPACE_EXTENT) * PLAYER_SCALE
PLAYER_BOUNCE_DAMPING_FACTOR :: 1.05
PLAYER_MAX_HP_VALUE       :: 4 
PLAYER_INVULNERABILITY_DURATION :: 0.75 
PARTICLE_DAMAGE_VALUE     :: 1 
LMB_PROJECTILE_DAMAGE     :: 2 
ENEMY_GRUNT_DAMAGE_VALUE :: 1 

// Black Hole (RMB) Constants
BLACKHOLE_COOLDOWN_DURATION :: 1.0 
MAX_SPIN_SPEED            :: f32(m.PI * 2.0)
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
ENEMY_SLOWBOY_GLOW_CANVAS_SF :: 1.0 // Used in shader, passed via effect_params.z for SlowBoy
ENEMY_SLOWBOY_SPEED :: f32(0.15)
ENEMY_SLOWBOY_MAX_HP :: 16
// --- SlowBoy Attack Constants ---
SLOWBOY_ATTACK_DETECT_RANGE :: ORTHO_HEIGHT * 0.8; 
SLOWBOY_ATTACK_WINDUP_TOTAL_DURATION :: 1.5;
// --- Boss Chrome Orb Constants ---
ENEMY_BOSS_CHROME_ORB_SCALE :: 0.2; // This is the 'current_size' in Odin for the boss entity
ENEMY_BOSS_CHROME_ORB_MAX_HP :: 100;
ENEMY_BOSS_CHROME_ORB_ANGULAR_VEL :: m.PI / 2.0; // Radians per second for black circle rotation (not used for main body)
ENEMY_BOSS_HORIZONTAL_SPEED :: 1.0; // World units per second
ENEMY_BOSS_SPAWN_Y_OFFSET :: ORTHO_HEIGHT * 0.75; // Spawn near the top of the screen
ENEMY_BOSS_SCREEN_PADDING :: 0.2; // Padding from screen edges
ENEMY_BOSS_VISION_ANGLE :: m.PI / 3.0; // 60 degree cone (PI/3 radians) - AI use, not directly shader
ENEMY_BOSS_VISION_RANGE :: ORTHO_HEIGHT * 1.2; // Vision range - passed to shader
ENEMY_BOSS_DETECTION_PRINT_COOLDOWN_TIME :: 1.0; // Seconds between detection prints
ENEMY_BOSS_VISION_RECT_WIDTH :: ORTHO_HEIGHT * 0.4; // Vision rectangle width - passed to shader

// NEW Laser Specifics (can be same as vision rect or different)
BOSS_LASER_LENGTH :: ORTHO_HEIGHT;        // Length of the damaging laser beam
BOSS_LASER_WIDTH  :: ENEMY_BOSS_VISION_RECT_WIDTH * 0.5; // Make laser visually thinner than detection rect
BOSS_LASER_DAMAGE :: 1;                                // Damage dealt by laser on contact (per collision check)
ENEMY_SHADER_VISUAL_SCALE_MULTIPLIER :: 3.0; // Multiplier for regular enemies
BOSS_QUAD_WORLD_DIAMETER :: ORTHO_HEIGHT; // NEW: e.g., 4x screen height, should be plenty


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
ENEMY_MAX_ANGULAR_SPEED :: m.PI / 0.7 // For Grunts/Slowboys
ENEMY_BASE_ALPHA :: 0.65         
ENEMY_WANDER_INFLUENCE :: 0.35 
ENEMY_WANDER_DIRECTION_CHANGE_INTERVAL :: 1.5 
ENEMY_GRUNT_MAX_HP :: 4
ENEMY_DEATH_ANIM_DURATION :: 1.0  // General, can be overridden
GRUNT_DEATH_ANIM_DURATION :: 3.0 
SLOWBOY_DEATH_ANIM_DURATION :: 1.0
BOSS_DEATH_ANIM_DURATION :: 4.0 // Longer for boss
ENEMY_DEATH_RECT_SEPARATION_SPEED :: 0.3 
ENEMY_DEATH_RECT_FINAL_SCALE_FACTOR :: 0.0 

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
    BOSS_CHROME_ORB,
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

// --- Level and Stage System Structs ---

EnemySpawnConfig :: struct {
    enemy_type: EnemyType,
    count: int,
    min_spawn_delay: f32, // Minimum time in seconds before the next enemy of this type spawns
    max_spawn_delay: f32, // Maximum time in seconds before the next enemy of this type spawns
}

StageDefinition :: struct {
    enemy_configs: []EnemySpawnConfig, // Use a dynamic array for flexibility
    // duration: f32, // Optional: could be used for time-based stages
    // trigger_condition: string, // Optional: for more complex stage end conditions
}

LevelDefinition :: struct {
    stages: []StageDefinition, // Use a dynamic array
    boss_config: EnemySpawnConfig, // A single config for the boss of this level
    // Or boss_stage_index: int, if a boss is just a special stage
}

// --- Structs for Tracking Active Stage Progress ---

// State for a single enemy type within an active stage
ActiveStageEnemySpawnState :: struct {
    config_index: int,       // Index into the StageDefinition.enemy_configs
    spawn_timer: f32,        // Current timer counting down to next spawn
    spawned_count: int,      // How many of this enemy type have been spawned for this config
    remaining_to_spawn: int, // How many are left to spawn for this config based on its count
}

// Holds all active enemy spawn states for the current stage
ActiveStageState :: struct {
    enemy_spawn_states: [dynamic]ActiveStageEnemySpawnState, // Dynamic array of states
    all_enemies_for_stage_spawned: bool, // True if all enemies defined in enemy_configs have been spawned
}

GameProgression :: struct {
    current_level_index: int,
    current_stage_index: int,
    
    active_stage: ActiveStageState,
    
    total_enemies_defined_for_current_stage: int, // Total enemies from all configs in the current stage definition
    enemies_defeated_in_current_stage: int,
    
    // Potentially, a pointer to the current LevelDefinition and StageDefinition
    // current_level_def: ^LevelDefinition, // For easier access, manage lifetime carefully
    // current_stage_def: ^StageDefinition, // For easier access, manage lifetime carefully
}

game_levels: []LevelDefinition; // Global variable for level definitions
// rng_state_progression: rand.Rand; // Renamed
random_generator_progression: runtime.Default_Random_State; // This is our seeded RNG state for progression

Enemy :: struct {
    pos: m.vec2,
    vel: m.vec2,
    color: m.vec4,       
    target_size: f32,    // Base world size for this enemy type (e.g., ENEMY_GRUNT_SCALE, ENEMY_BOSS_CHROME_ORB_SCALE)
    current_size: f32,   // Actual current world size (e.g. during grow animation or if dynamically scaled)
    grow_timer: f32,     
    is_growing: bool,    
    rotation: f32,       // For Grunts/Slowboys, their body rotation. For Boss, its aiming direction.
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
    boss_move_direction: f32, // New field for boss horizontal movement
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
        instance_main_rotation: f32,  // For Grunt/Slowboy body rotation, for Boss aiming direction
        instance_visual_scale: f32,   // This will be enemy.current_size * ENEMY_SHADER_VISUAL_SCALE_MULTIPLIER
        instance_color: m.vec4,       
        instance_effect_params: m.vec4, 
        instance_enemy_type: f32,     
        _padding0: m.vec3,            
    },
}


// --- Global State ---
state: struct {
    progression: GameProgression,
    pass_action: sg.Pass_Action, bind: sg.Bindings,
    bg_pip: sg.Pipeline, player_pip: sg.Pipeline, particle_pip: sg.Pipeline, enemy_pip: sg.Pipeline, blackhole_pip: sg.Pipeline,
    bg_fs_params: Bg_Fs_Params, player_vs_params: Player_Vs_Params, player_fs_params: Player_Fs_Params,
    particle_vs_params: Particle_Vs_Params, particle_fs_params: Particle_Fs_Params,
    enemy_vs_params: Enemy_Vs_Params, enemy_fs_params: Enemy_Fs_Params, 
    blackhole_vs_params: Blackhole_Vs_Params, blackhole_fs_params: Blackhole_Fs_Params,

    audio_engine: ma.engine,
    lmb_sound: ma.sound,
    lmb_hit_sound: ma.sound,
    lmb_kill_sound: ma.sound,
    rmb_hit_sound: ma.sound,
    rmb_kill_sound: ma.sound,
    drum_track_sound: ma.sound,
    synth_track_sound: ma.sound, // <<< NEW

    first_grunt_killed: bool, 
    first_slowboy_killed: bool, // <<< NEW
    player_pos: m.vec2, player_vel: m.vec2,
    player_hp: int, player_max_hp: int, 
    player_invulnerable_timer: f32,   
    player_defeated_message_shown: bool, 

    key_w_down: bool, key_s_down: bool, key_a_down: bool, key_d_down: bool, key_shift_down: bool,
    
    rmb_down: bool, previous_rmb_down: bool, rmb_cooldown_timer: f32,
    lmb_down: bool, previous_lmb_down: bool, lmb_cooldown_timer: f32,
    is_dashing: bool, dash_timer: f32, dash_cooldown_timer: f32,

    player_dash_traiL_pos: [PLAYER_DASH_TRAIL_LENGTH]m.vec2, 
    player_dash_trail_count: int, 
    dash_trail_spawn_timer: f32,

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

load_and_initialize_stage_progression :: proc(level_idx: int, stage_idx: int) {
    context = runtime.default_context();
    fmt.printf("--- Attempting to load Stage: Level %d, Stage %d ---\n", level_idx, stage_idx);

    if level_idx >= len(game_levels) {
        fmt.printf("!!! ERROR: Level index %d is out of bounds (game_levels length: %d).\n", level_idx, len(game_levels));
        // Optionally, handle this as game won or error state
        // For now, just prevent further progression logic for this call
        state.progression.active_stage.all_enemies_for_stage_spawned = true; // Stop spawning
        return;
    }
    current_level_def := &game_levels[level_idx];

    if stage_idx >= len(current_level_def.stages) {
        fmt.printf("!!! ERROR: Stage index %d is out of bounds for Level %d (stages length: %d).\n", stage_idx, level_idx, len(current_level_def.stages));
        // This might mean the current level is complete, and we should try to advance to the next level.
        // Handled by the calling logic in frame()
        state.progression.active_stage.all_enemies_for_stage_spawned = true; // Stop spawning
        return;
    }
    current_stage_def := &current_level_def.stages[stage_idx];

    state.progression.current_level_index = level_idx;
    state.progression.current_stage_index = stage_idx;
    state.progression.enemies_defeated_in_current_stage = 0;
    
    clear(&state.progression.active_stage.enemy_spawn_states); // Clear previous states
    
    total_enemies_count_for_stage: int = 0;
    if len(current_stage_def.enemy_configs) > 0 {
        // Reserve if desired, but append will grow it: reserve(&state.progression.active_stage.enemy_spawn_states, len(current_stage_def.enemy_configs));
        for config, config_idx in current_stage_def.enemy_configs {
            spawn_state := ActiveStageEnemySpawnState {
                config_index       = config_idx,
                spawn_timer        = rand.float32_range(config.min_spawn_delay, config.max_spawn_delay, runtime.default_random_generator(&random_generator_progression)),
                spawned_count      = 0,
                remaining_to_spawn = config.count,
            };
            append(&state.progression.active_stage.enemy_spawn_states, spawn_state);
            total_enemies_count_for_stage += config.count;
        }
    }
    
    state.progression.total_enemies_defined_for_current_stage = total_enemies_count_for_stage;
    state.progression.active_stage.all_enemies_for_stage_spawned = (len(current_stage_def.enemy_configs) == 0);
    
    fmt.printf("Loaded Stage: Level %d, Stage %d. Total Enemies: %d. Spawn states: %d. All spawned initially: %t\n", 
        level_idx, stage_idx, 
        state.progression.total_enemies_defined_for_current_stage,
        len(state.progression.active_stage.enemy_spawn_states),
        state.progression.active_stage.all_enemies_for_stage_spawned);
}


init :: proc "c" () {
    context = runtime.default_context()
    sg.setup({ pipeline_pool_size=16, buffer_pool_size=16, shader_pool_size=16, environment=sglue.environment(), logger={func=slog.func} }) // Increased pool sizes slightly
    fmt.printf("--- Init Start ---\n")

    // Calculate Drum Track Frame Counts
    DRUM_TRACK_FRAMES_PER_BEAT_F32 := DRUM_TRACK_SECONDS_PER_BEAT * f32(DRUM_TRACK_SAMPLE_RATE);
    DRUM_TRACK_FRAMES_PER_BEAT := int(math.round_f32(DRUM_TRACK_FRAMES_PER_BEAT_F32));
    DRUM_TRACK_FRAMES_PER_BAR := DRUM_TRACK_FRAMES_PER_BEAT * DRUM_TRACK_BEATS_PER_BAR;
    DRUM_TRACK_TOTAL_FRAMES := DRUM_TRACK_FRAMES_PER_BAR * DRUM_TRACK_NUM_BARS;
    
    drum_track_pcm_data = make([]f32, DRUM_TRACK_TOTAL_FRAMES);
    if drum_track_pcm_data == nil {
        fmt.eprintf("!!! CRITICAL: Failed to allocate drum_track_pcm_data slice! Total Frames: %d", DRUM_TRACK_TOTAL_FRAMES);
        return; 
    }
    fmt.printf("--- Drum track PCM data slice allocated. Total Frames: %d ---", DRUM_TRACK_TOTAL_FRAMES);

    fmt.printf("--- Generating Revised Placeholder Drum Track PCM data (160 BPM)... ---");
    
    KICK_DURATION_FRAMES: int = DRUM_TRACK_FRAMES_PER_BEAT / 3; 
    KICK_START_FREQ :: 120.0; 
    KICK_END_FREQ :: 40.0;
    RELATIVE_KICK_AMPLITUDE  := 0.6; // Made it a normal variable for clarity inside init

    SNARE_DURATION_FRAMES: int = DRUM_TRACK_FRAMES_PER_BEAT / 6;
    SNARE_START_FREQ :: 220.0; 
    RELATIVE_SNARE_AMPLITUDE  := 0.4; // Made it a normal variable

    HIHAT_DURATION_FRAMES: int = DRUM_TRACK_FRAMES_PER_BEAT / 16;
    HIHAT_FREQ :: 6000.0; 
    RELATIVE_HIHAT_AMPLITUDE   := 0.15; // Made it a normal variable

    // Zero out the buffer first
    for i in 0..<DRUM_TRACK_TOTAL_FRAMES { 
        drum_track_pcm_data[i] = 0.0;
    }

    // Generate PCM data bar by bar (Corrected Loop Structure)
    for bar_idx in 0..<DRUM_TRACK_NUM_BARS {
        // --- KICK and SNARE ---
        for beat_num_in_bar in 0..<DRUM_TRACK_BEATS_PER_BAR {
            beat_start_frame_offset := beat_num_in_bar * DRUM_TRACK_FRAMES_PER_BEAT;
            current_beat_global_start_frame := (bar_idx * DRUM_TRACK_FRAMES_PER_BAR) + beat_start_frame_offset;

            // --- KICK DRUM ---
            if beat_num_in_bar == 0 || beat_num_in_bar == 2 {
                current_phase_kick: f64 = 0.0;
                for kick_i in 0..<KICK_DURATION_FRAMES {
                    frame_in_track := current_beat_global_start_frame + kick_i;
                    if frame_in_track >= DRUM_TRACK_TOTAL_FRAMES { break }

                    progress: f64 = f64(kick_i) / f64(KICK_DURATION_FRAMES);
                    amplitude_kick_env: f64 = math.pow_f64(f64(1.0) - progress, 2.5); // Renamed to avoid conflict
                    amplitude_kick_env = math.max(0.0, amplitude_kick_env);
                    current_freq_kick: f64 = f64(KICK_START_FREQ) * math.pow_f64(f64(KICK_END_FREQ) / f64(KICK_START_FREQ), progress);
                    
                    sample_val_kick: f64 = math.sin(current_phase_kick);
                    drum_track_pcm_data[frame_in_track] += f32(sample_val_kick * amplitude_kick_env * f64(RELATIVE_KICK_AMPLITUDE));
                    
                    current_phase_kick += (2.0 * f64(math.PI) * current_freq_kick) / f64(DRUM_TRACK_SAMPLE_RATE);
                    if current_phase_kick >= (2.0 * f64(math.PI)) { current_phase_kick -= (2.0 * f64(math.PI)) }
                }
            }

            // --- SNARE DRUM ---
            if beat_num_in_bar == 1 || beat_num_in_bar == 3 {
                current_phase_snare: f64 = 0.0;
                for snare_i in 0..<SNARE_DURATION_FRAMES {
                    frame_in_track := current_beat_global_start_frame + snare_i;
                    if frame_in_track >= DRUM_TRACK_TOTAL_FRAMES { break }

                    progress: f64 = f64(snare_i) / f64(SNARE_DURATION_FRAMES);
                    amplitude_snare_env: f64 = math.pow_f64(f64(1.0) - progress, 3.5); // Renamed
                    amplitude_snare_env = math.max(0.0, amplitude_snare_env);
                    
                    sample_val_snare: f64 = math.sin(current_phase_snare); // Simple sine for snare, noise would be better
                    drum_track_pcm_data[frame_in_track] += f32(sample_val_snare * amplitude_snare_env * f64(RELATIVE_SNARE_AMPLITUDE));
                    
                    current_phase_snare += (2.0 * f64(math.PI) * f64(SNARE_START_FREQ)) / f64(DRUM_TRACK_SAMPLE_RATE); // Using SNARE_START_FREQ as constant pitch for simplicity
                    if current_phase_snare >= (2.0 * f64(math.PI)) { current_phase_snare -= (2.0 * f64(math.PI)) }
                }
            }
        } // End KICK/SNARE for bar_idx

        // --- HI-HATS (across the entire bar_idx) ---
        for eighth_note_in_bar_idx in 0..<(DRUM_TRACK_BEATS_PER_BAR * 2) {
            eighth_note_offset_from_bar_start := eighth_note_in_bar_idx * (DRUM_TRACK_FRAMES_PER_BEAT / 2);
            hihat_global_start_frame := (bar_idx * DRUM_TRACK_FRAMES_PER_BAR) + eighth_note_offset_from_bar_start;
            
            is_on_kick_pos  := (eighth_note_in_bar_idx == 0 || eighth_note_in_bar_idx == 4); 
            is_on_snare_pos := (eighth_note_in_bar_idx == 2 || eighth_note_in_bar_idx == 6);

            if is_on_kick_pos || is_on_snare_pos { 
                // Skip hi-hat on main kick/snare beats
            } else {
                current_phase_hihat: f64 = 0.0;
                for hihat_i in 0..<HIHAT_DURATION_FRAMES {
                    frame_in_track := hihat_global_start_frame + hihat_i;
                    if frame_in_track >= DRUM_TRACK_TOTAL_FRAMES { break }

                    progress: f64 = f64(hihat_i) / f64(HIHAT_DURATION_FRAMES);
                    amplitude_hihat_env: f64 = math.pow_f64(f64(1.0) - progress, 2.0); // Renamed
                    amplitude_hihat_env = math.max(0.0, amplitude_hihat_env);

                    sample_val_hihat: f64 = math.sin(current_phase_hihat); // Simple sine for hi-hat, noise/filtered noise better
                    drum_track_pcm_data[frame_in_track] += f32(sample_val_hihat * amplitude_hihat_env * f64(RELATIVE_HIHAT_AMPLITUDE));

                    current_phase_hihat += (2.0 * f64(math.PI) * f64(HIHAT_FREQ)) / f64(DRUM_TRACK_SAMPLE_RATE);
                    if current_phase_hihat >= (2.0 * f64(math.PI)) { current_phase_hihat -= (2.0 * f64(math.PI)) }
                }
            }
        } // End HI-HATS for bar_idx
    } // End BAR loop
    
    for i_clamp in 0..<DRUM_TRACK_TOTAL_FRAMES { 
        drum_track_pcm_data[i_clamp] = math.clamp(drum_track_pcm_data[i_clamp], -0.95, 0.95);
    }
    fmt.printf("--- Revised Placeholder Drum Track PCM data generated. ---");

    // Sokol Audio Setup
    sokol_audio_desc := sa.Desc {
        sample_rate = LMB_SOUND_SAMPLE_RATE, 
        num_channels = LMB_SOUND_CHANNELS,   
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
    engine_config.channels = u32(LMB_SOUND_CHANNELS)   
    engine_config.sampleRate = u32(LMB_SOUND_SAMPLE_RATE) 

    init_result := ma.engine_init(&engine_config, &state.audio_engine)
    if init_result != .SUCCESS {
        fmt.eprintf("!!! CRITICAL: Miniaudio engine_init failed! Error: %v\n", init_result)
    } else {
        fmt.printf("--- Miniaudio Engine Initialized ---\n")
    }

    // Generate "Pew" Sound PCM Data
    fmt.printf("--- Generating 'Pew' sound PCM data... ---\n")
    current_phase_lmb: f64 = 0.0 // Renamed to avoid conflict
    
    for i in 0..<LMB_SOUND_FRAMES {
        progress := f64(i) / f64(LMB_SOUND_FRAMES)
        amplitude_lmb: f64 // Renamed
        attack_time_lmb := 0.15 
        if progress < attack_time_lmb {
            amplitude_lmb = progress / attack_time_lmb
        } else {
            amplitude_lmb = 1.0 - (progress - attack_time_lmb) / (1.0 - attack_time_lmb)
        }
        amplitude_lmb = math.max(0.0, amplitude_lmb) 

        ratio_lmb := LMB_SOUND_END_FREQ / LMB_SOUND_START_FREQ // Renamed
        exponent_lmb := progress // Renamed
        current_freq_f64_lmb := f64(LMB_SOUND_START_FREQ) * math.pow(f64(ratio_lmb), exponent_lmb) // Renamed

        sample_val_f64_lmb := math.sin(current_phase_lmb) // Renamed
        
        lmb_sound_pcm_data[i] = f32(sample_val_f64_lmb * amplitude_lmb * f64(LMB_SOUND_AMPLITUDE))

        current_phase_lmb += (2.0 * f64(math.PI) * current_freq_f64_lmb) / f64(LMB_SOUND_SAMPLE_RATE)
        if current_phase_lmb >= (2.0 * f64(math.PI)) {
            current_phase_lmb -= (2.0 * f64(math.PI))
        }
    }
    fmt.printf("--- 'Pew' sound PCM data generated. First sample: %v, Mid sample: %v, Last sample: %v ---\n", lmb_sound_pcm_data[0], lmb_sound_pcm_data[LMB_SOUND_FRAMES/2], lmb_sound_pcm_data[LMB_SOUND_FRAMES-1])

    audio_buffer_config_lmb := ma.audio_buffer_config_init(ma.format.f32, u32(LMB_SOUND_CHANNELS), u64(LMB_SOUND_FRAMES), rawptr(&lmb_sound_pcm_data[0]), nil) // Renamed
    init_ab_result_lmb := ma.audio_buffer_init_copy(&audio_buffer_config_lmb, &lmb_sound_audio_buffer) // Renamed
    if init_ab_result_lmb != .SUCCESS {
        fmt.eprintf("!!! CRITICAL: Miniaudio audio_buffer_init_copy for LMB sound failed! Error: %v\n", init_ab_result_lmb)
    } else {
        fmt.printf("--- Miniaudio audio_buffer initialized for LMB sound ---\n")
        sound_flags_lmb: ma.sound_flags = { .NO_PITCH, .NO_SPATIALIZATION } // Renamed
        p_data_source_for_lmb_sound := (^ma.data_source)(&lmb_sound_audio_buffer) // Renamed

        init_sound_result_lmb := ma.sound_init_from_data_source(&state.audio_engine, p_data_source_for_lmb_sound, sound_flags_lmb, nil, &state.lmb_sound) // Renamed
        if init_sound_result_lmb != .SUCCESS {
            fmt.eprintf("!!! CRITICAL: Miniaudio sound_init_from_data_source for lmb_sound failed! Error: %v\n", init_sound_result_lmb)
            ma.audio_buffer_uninit(&lmb_sound_audio_buffer); 
        } else {
            fmt.printf("--- Miniaudio lmb_sound initialized successfully ---\n")
        }
    }

    fmt.printf("--- Initializing RMB Particle Sounds ---\n")
    hum_waveform_config := ma.waveform_config_init( ma.format.f32, u32(LMB_SOUND_CHANNELS), u32(LMB_SOUND_SAMPLE_RATE), ma.waveform_type.sine, f64(RMB_HUM_AMPLITUDE), f64(RMB_HUM_FREQUENCY))
    hum_sine_wave_gen: ma.waveform
    init_hum_wf_result := ma.waveform_init(&hum_waveform_config, &hum_sine_wave_gen)
    if init_hum_wf_result == .SUCCESS {
        frames_read_hum: u64
        ma.waveform_read_pcm_frames(&hum_sine_wave_gen, rawptr(&rmb_hum_pcm_data[0]), u64(RMB_PARTICLE_SOUND_DURATION_FRAMES), &frames_read_hum)
        ma.waveform_uninit(&hum_sine_wave_gen) 
        fmt.printf("--- RMB Hum PCM data generated (%v frames). ---\n", frames_read_hum)
    } else {
        fmt.eprintf("!!! CRITICAL: Miniaudio waveform_init for RMB Hum failed! Error: %v\n", init_hum_wf_result)
    }

    whoosh_noise_config := ma.noise_config_init(ma.format.f32, u32(LMB_SOUND_CHANNELS), ma.noise_type.pink, 0, f64(RMB_WHOOSH_AMPLITUDE))
    whoosh_noise_gen: ma.noise
    init_whoosh_noise_result := ma.noise_init(&whoosh_noise_config, nil, &whoosh_noise_gen)
    if init_whoosh_noise_result == .SUCCESS {
        frames_read_whoosh: u64
        ma.noise_read_pcm_frames(&whoosh_noise_gen, rawptr(&rmb_whoosh_pcm_data[0]), u64(RMB_PARTICLE_SOUND_DURATION_FRAMES), &frames_read_whoosh)
        ma.noise_uninit(&whoosh_noise_gen, nil) 
        fmt.printf("--- RMB Whoosh PCM data generated (%v frames). ---\n", frames_read_whoosh)
    } else {
        fmt.eprintf("!!! CRITICAL: Miniaudio noise_init for RMB Whoosh failed! Error: %v\n", init_whoosh_noise_result)
    }

    hum_ab_config := ma.audio_buffer_config_init(ma.format.f32, u32(LMB_SOUND_CHANNELS), u64(RMB_PARTICLE_SOUND_DURATION_FRAMES), rawptr(&rmb_hum_pcm_data[0]), nil)
    init_hum_ab_result := ma.audio_buffer_init_copy(&hum_ab_config, &rmb_hum_audio_buffer)
    if init_hum_ab_result == .SUCCESS { fmt.printf("--- RMB Hum audio_buffer initialized. ---\n") } 
    else { fmt.eprintf("!!! CRITICAL: RMB Hum audio_buffer_init_copy failed! Error: %v\n", init_hum_ab_result) }

    whoosh_ab_config := ma.audio_buffer_config_init(ma.format.f32, u32(LMB_SOUND_CHANNELS), u64(RMB_PARTICLE_SOUND_DURATION_FRAMES), rawptr(&rmb_whoosh_pcm_data[0]), nil)
    init_whoosh_ab_result := ma.audio_buffer_init_copy(&whoosh_ab_config, &rmb_whoosh_audio_buffer)
    if init_whoosh_ab_result == .SUCCESS { fmt.printf("--- RMB Whoosh audio_buffer initialized. ---\n") } 
    else { fmt.eprintf("!!! CRITICAL: RMB Whoosh audio_buffer_init_copy failed! Error: %v\n", init_whoosh_ab_result) }
    fmt.printf("--- RMB Particle Sounds Initialized ---\n")

    fmt.printf("--- Generating 'Enemy Hit' sound PCM data... ---\n")
    current_phase_enemy_hit: f64 = 0.0
    for i in 0..<ENEMY_HIT_SOUND_FRAMES {
        progress_eh := f64(i) / f64(ENEMY_HIT_SOUND_FRAMES) // Renamed progress
        amplitude_eh: f64 // Renamed
        attack_time_eh := 0.1 
        if progress_eh < attack_time_eh { amplitude_eh = progress_eh / attack_time_eh } 
        else { amplitude_eh = 1.0 - (progress_eh - attack_time_eh) / (1.0 - attack_time_eh) }
        amplitude_eh = math.max(0.0, amplitude_eh)
        ratio_eh := ENEMY_HIT_SOUND_END_FREQ / ENEMY_HIT_SOUND_START_FREQ // Renamed
        current_freq_f64_eh := f64(ENEMY_HIT_SOUND_START_FREQ) * math.pow(f64(ratio_eh), progress_eh) // Renamed
        sample_val_f64_eh := math.sin(current_phase_enemy_hit) // Renamed
        enemy_hit_sound_pcm_data[i] = f32(sample_val_f64_eh * amplitude_eh * f64(ENEMY_HIT_SOUND_AMPLITUDE))
        current_phase_enemy_hit += (2.0 * f64(math.PI) * current_freq_f64_eh) / f64(LMB_SOUND_SAMPLE_RATE)
        if current_phase_enemy_hit >= (2.0 * f64(math.PI)) { current_phase_enemy_hit -= (2.0 * f64(math.PI)) }
    }
    fmt.printf("--- 'Enemy Hit' sound PCM data generated. ---\n")

    enemy_hit_ab_config := ma.audio_buffer_config_init(ma.format.f32, u32(LMB_SOUND_CHANNELS), u64(ENEMY_HIT_SOUND_FRAMES), rawptr(&enemy_hit_sound_pcm_data[0]), nil)
    init_enemy_hit_ab_result := ma.audio_buffer_init_copy(&enemy_hit_ab_config, &enemy_hit_sound_audio_buffer)
    if init_enemy_hit_ab_result == .SUCCESS {
        fmt.printf("--- Enemy Hit audio_buffer initialized. ---\n")
        sound_flags_rmb_hit: ma.sound_flags = { .NO_PITCH, .NO_SPATIALIZATION };
        p_data_source_rmb_hit := (^ma.data_source)(&enemy_hit_sound_audio_buffer);
        init_rmb_hit_sound_result := ma.sound_init_from_data_source(&state.audio_engine, p_data_source_rmb_hit, sound_flags_rmb_hit, nil, &state.rmb_hit_sound);
        if init_rmb_hit_sound_result == .SUCCESS {
            ma.sound_set_volume(&state.rmb_hit_sound, ENEMY_HIT_SOUND_AMPLITUDE);
            fmt.printf("--- Miniaudio rmb_hit_sound initialized successfully (Volume: %.2f) ---\n", ENEMY_HIT_SOUND_AMPLITUDE);
        } else {
            fmt.eprintf("!!! CRITICAL: Miniaudio sound_init_from_data_source for rmb_hit_sound failed! Error: %v\n", init_rmb_hit_sound_result);
            ma.audio_buffer_uninit(&enemy_hit_sound_audio_buffer); 
        }
    } else {
        fmt.eprintf("!!! CRITICAL: Enemy Hit audio_buffer_init_copy failed! Error: %v\n", init_enemy_hit_ab_result)
    }

    fmt.printf("--- Generating 'Enemy Death' sound PCM data... ---\n")
    current_phase_enemy_death_sine: f64 = 0.0
    rng_seed_ed: u64 = 12345 // Renamed
    death_sound_rng_state := rand.create(rng_seed_ed) 
    death_sound_generator := runtime.default_random_generator(&death_sound_rng_state)
    for i in 0..<ENEMY_DEATH_SOUND_FRAMES {
        if i < ENEMY_DEATH_SOUND_NOISE_DURATION_FRAMES { 
            progress_noise_ed := f32(i) / f32(ENEMY_DEATH_SOUND_NOISE_DURATION_FRAMES) // Renamed
            decay_noise_ed := (1.0 - progress_noise_ed) // Renamed
            decay_noise_ed = math.max(0.0, decay_noise_ed) 
            random_sample_ed := (rand.float32(death_sound_generator) * 2.0 - 1.0) // Renamed
            enemy_death_sound_pcm_data[i] = random_sample_ed * ENEMY_DEATH_SOUND_NOISE_AMPLITUDE * decay_noise_ed
        } else {
            sine_progress_frames_ed := i - ENEMY_DEATH_SOUND_NOISE_DURATION_FRAMES // Renamed
            total_sine_frames_ed := ENEMY_DEATH_SOUND_FRAMES - ENEMY_DEATH_SOUND_NOISE_DURATION_FRAMES // Renamed
            progress_sine_ed := f64(sine_progress_frames_ed) / f64(total_sine_frames_ed) // Renamed
            amplitude_sine_decay_ed := 1.0 - progress_sine_ed // Renamed
            amplitude_sine_decay_ed = math.max(0.0, amplitude_sine_decay_ed) 
            ratio_sine_ed := ENEMY_DEATH_SOUND_SINE_END_FREQ / ENEMY_DEATH_SOUND_SINE_START_FREQ // Renamed
            current_freq_sine_f64_ed := f64(ENEMY_DEATH_SOUND_SINE_START_FREQ) * math.pow(f64(ratio_sine_ed), progress_sine_ed) // Renamed
            sample_val_sine_f64_ed := math.sin(current_phase_enemy_death_sine) // Renamed
            enemy_death_sound_pcm_data[i] = f32(sample_val_sine_f64_ed * amplitude_sine_decay_ed * f64(ENEMY_DEATH_SOUND_SINE_AMPLITUDE))
            current_phase_enemy_death_sine += (2.0 * f64(math.PI) * current_freq_sine_f64_ed) / f64(LMB_SOUND_SAMPLE_RATE)
            if current_phase_enemy_death_sine >= (2.0 * f64(math.PI)) { current_phase_enemy_death_sine -= (2.0 * f64(math.PI)) }
        }
    }
    fmt.printf("--- 'Enemy Death' sound PCM data generated. ---\n")

    enemy_death_ab_config := ma.audio_buffer_config_init(ma.format.f32, u32(LMB_SOUND_CHANNELS), u64(ENEMY_DEATH_SOUND_FRAMES), rawptr(&enemy_death_sound_pcm_data[0]), nil)
    init_enemy_death_ab_result := ma.audio_buffer_init_copy(&enemy_death_ab_config, &enemy_death_sound_audio_buffer)
    if init_enemy_death_ab_result == .SUCCESS {
        fmt.printf("--- Enemy Death audio_buffer initialized. ---\n")
        sound_flags_rmb_kill: ma.sound_flags = { .NO_PITCH, .NO_SPATIALIZATION };
        p_data_source_rmb_kill := (^ma.data_source)(&enemy_death_sound_audio_buffer);
        init_rmb_kill_sound_result := ma.sound_init_from_data_source(&state.audio_engine, p_data_source_rmb_kill, sound_flags_rmb_kill, nil, &state.rmb_kill_sound);
        if init_rmb_kill_sound_result == .SUCCESS {
            ma.sound_set_volume(&state.rmb_kill_sound, ENEMY_DEATH_SOUND_SINE_AMPLITUDE + ENEMY_DEATH_SOUND_NOISE_AMPLITUDE);
            fmt.printf("--- Miniaudio rmb_kill_sound initialized successfully (Volume: %.2f) ---\n", ENEMY_DEATH_SOUND_SINE_AMPLITUDE + ENEMY_DEATH_SOUND_NOISE_AMPLITUDE);
        } else {
            fmt.eprintf("!!! CRITICAL: Miniaudio sound_init_from_data_source for rmb_kill_sound failed! Error: %v\n", init_rmb_kill_sound_result);
            ma.audio_buffer_uninit(&enemy_death_sound_audio_buffer); 
        }
    } else {
        fmt.eprintf("!!! CRITICAL: Enemy Death audio_buffer_init_copy failed! Error: %v\n", init_enemy_death_ab_result)
    }

    fmt.printf("--- Generating 'LMB Hit Whoosh' sound PCM data... ---\n")
    lmb_hit_rng_seed: u64 = 67890 
    lmb_hit_rng_state := rand.create(lmb_hit_rng_seed)
    lmb_hit_generator := runtime.default_random_generator(&lmb_hit_rng_state)
    for i in 0..<LMB_HIT_WHOOSH_DURATION_FRAMES {
        progress_lhw := f32(i) / f32(LMB_HIT_WHOOSH_DURATION_FRAMES) // Renamed
        amplitude_envelope_lhw: f32 // Renamed
        attack_time_whoosh_lhw : f32 = 0.05 // Renamed
        decay_time_whoosh_lhw : f32 = 0.95 // Renamed
        if progress_lhw < attack_time_whoosh_lhw { amplitude_envelope_lhw = progress_lhw / attack_time_whoosh_lhw } 
        else { amplitude_envelope_lhw = 1.0 - (progress_lhw - attack_time_whoosh_lhw) / decay_time_whoosh_lhw }
        amplitude_envelope_lhw = math.max(0.0, amplitude_envelope_lhw) 
        random_sample_lhw := (rand.float32(lmb_hit_generator) * 2.0 - 1.0) // Renamed
        lmb_hit_whoosh_pcm_data[i] = random_sample_lhw * LMB_HIT_WHOOSH_AMPLITUDE * amplitude_envelope_lhw
    }
    fmt.printf("--- 'LMB Hit Whoosh' sound PCM data generated. ---\n")

    lmb_hit_whoosh_ab_config := ma.audio_buffer_config_init(ma.format.f32, u32(LMB_SOUND_CHANNELS), u64(LMB_HIT_WHOOSH_DURATION_FRAMES), rawptr(&lmb_hit_whoosh_pcm_data[0]), nil)
    init_lmb_hit_whoosh_ab_result := ma.audio_buffer_init_copy(&lmb_hit_whoosh_ab_config, &lmb_hit_whoosh_audio_buffer)
    if init_lmb_hit_whoosh_ab_result == .SUCCESS {
        fmt.printf("--- LMB Hit Whoosh audio_buffer initialized. ---\n")
        sound_flags_lmb_hit: ma.sound_flags = { .NO_PITCH, .NO_SPATIALIZATION };
        p_data_source_lmb_hit := (^ma.data_source)(&lmb_hit_whoosh_audio_buffer);
        init_lmb_hit_sound_result := ma.sound_init_from_data_source(&state.audio_engine, p_data_source_lmb_hit, sound_flags_lmb_hit, nil, &state.lmb_hit_sound);
        if init_lmb_hit_sound_result == .SUCCESS {
            ma.sound_set_volume(&state.lmb_hit_sound, LMB_HIT_WHOOSH_AMPLITUDE);
            fmt.printf("--- Miniaudio lmb_hit_sound initialized successfully (Volume: %.2f) ---\n", LMB_HIT_WHOOSH_AMPLITUDE);
        } else {
            fmt.eprintf("!!! CRITICAL: Miniaudio sound_init_from_data_source for lmb_hit_sound failed! Error: %v\n", init_lmb_hit_sound_result);
            ma.audio_buffer_uninit(&lmb_hit_whoosh_audio_buffer); 
        }
    } else {
        fmt.eprintf("!!! CRITICAL: LMB Hit Whoosh audio_buffer_init_copy failed! Error: %v\n", init_lmb_hit_whoosh_ab_result)
    }

    fmt.printf("--- Generating 'LMB Kill Explosion' sound PCM data... ---\n")
    lmb_kill_rng_seed: u64 = 78901 
    lmb_kill_rng_state := rand.create(lmb_kill_rng_seed)
    lmb_kill_generator := runtime.default_random_generator(&lmb_kill_rng_state)
    EXPLOSION_NOISE_FRAMES :: LMB_KILL_EXPLOSION_DURATION_FRAMES / 5 
    EXPLOSION_SINE_START_FREQ_lke :: 150.0 // Renamed
    EXPLOSION_SINE_END_FREQ_lke :: 40.0   // Renamed
    current_phase_lmb_kill_sine: f64 = 0.0
    for i in 0..<LMB_KILL_EXPLOSION_DURATION_FRAMES {
        if i < EXPLOSION_NOISE_FRAMES {
            progress_noise_lke := f32(i) / f32(EXPLOSION_NOISE_FRAMES) // Renamed
            decay_noise_lke := (1.0 - progress_noise_lke) * (1.0 - progress_noise_lke) // Renamed
            decay_noise_lke = math.max(0.0, decay_noise_lke)
            random_sample_lke := (rand.float32(lmb_kill_generator) * 2.0 - 1.0) // Renamed
            lmb_kill_explosion_pcm_data[i] = random_sample_lke * LMB_KILL_EXPLOSION_AMPLITUDE * decay_noise_lke * 0.7 
        } else {
            sine_progress_frames_lke := i - EXPLOSION_NOISE_FRAMES // Renamed
            total_sine_frames_lke := LMB_KILL_EXPLOSION_DURATION_FRAMES - EXPLOSION_NOISE_FRAMES // Renamed
            progress_sine_lke := f64(sine_progress_frames_lke) / f64(total_sine_frames_lke) // Renamed
            amplitude_sine_decay_lke := math.pow(1.0 - progress_sine_lke, 3.0) // Renamed
            amplitude_sine_decay_lke = math.max(0.0, amplitude_sine_decay_lke)
            ratio_sine_lke := EXPLOSION_SINE_END_FREQ_lke / EXPLOSION_SINE_START_FREQ_lke // Renamed
            current_freq_sine_f64_lke := EXPLOSION_SINE_START_FREQ_lke * math.pow(ratio_sine_lke, progress_sine_lke) // Renamed
            sample_val_sine_f64_lke := math.sin(current_phase_lmb_kill_sine) // Renamed
            lmb_kill_explosion_pcm_data[i] = f32(sample_val_sine_f64_lke * amplitude_sine_decay_lke * f64(LMB_KILL_EXPLOSION_AMPLITUDE))
            current_phase_lmb_kill_sine += (2.0 * f64(math.PI) * current_freq_sine_f64_lke) / f64(LMB_SOUND_SAMPLE_RATE)
            if current_phase_lmb_kill_sine >= (2.0 * f64(math.PI)) { current_phase_lmb_kill_sine -= (2.0 * f64(math.PI)) }
        }
    }
    fmt.printf("--- 'LMB Kill Explosion' sound PCM data generated. ---\n")

    lmb_kill_explosion_ab_config := ma.audio_buffer_config_init(ma.format.f32, u32(LMB_SOUND_CHANNELS), u64(LMB_KILL_EXPLOSION_DURATION_FRAMES), rawptr(&lmb_kill_explosion_pcm_data[0]), nil)
    init_lmb_kill_explosion_ab_result := ma.audio_buffer_init_copy(&lmb_kill_explosion_ab_config, &lmb_kill_explosion_audio_buffer)
    if init_lmb_kill_explosion_ab_result == .SUCCESS {
        fmt.printf("--- LMB Kill Explosion audio_buffer initialized. ---\n")
        sound_flags_lmb_kill: ma.sound_flags = { .NO_PITCH, .NO_SPATIALIZATION };
        p_data_source_lmb_kill := (^ma.data_source)(&lmb_kill_explosion_audio_buffer);
        init_lmb_kill_sound_result := ma.sound_init_from_data_source(&state.audio_engine, p_data_source_lmb_kill, sound_flags_lmb_kill, nil, &state.lmb_kill_sound);
        if init_lmb_kill_sound_result == .SUCCESS {
            ma.sound_set_volume(&state.lmb_kill_sound, LMB_KILL_EXPLOSION_AMPLITUDE);
            fmt.printf("--- Miniaudio lmb_kill_sound initialized successfully (Volume: %.2f) ---\n", LMB_KILL_EXPLOSION_AMPLITUDE);
        } else {
            fmt.eprintf("!!! CRITICAL: Miniaudio sound_init_from_data_source for lmb_kill_sound failed! Error: %v\n", init_lmb_kill_sound_result);
            ma.audio_buffer_uninit(&lmb_kill_explosion_audio_buffer); 
        }
    } else {
        fmt.eprintf("!!! CRITICAL: LMB Kill Explosion audio_buffer_init_copy failed! Error: %v\n", init_lmb_kill_explosion_ab_result)
    }

    // Initialize Miniaudio audio_buffer for the drum track (This was the corrected drum generation block)
    drum_track_ab_config := ma.audio_buffer_config_init(ma.format.f32, u32(DRUM_TRACK_CHANNELS), u64(DRUM_TRACK_TOTAL_FRAMES), rawptr(&drum_track_pcm_data[0]), nil)
    init_drum_track_ab_result := ma.audio_buffer_init_copy(&drum_track_ab_config, &drum_track_audio_buffer)
    if init_drum_track_ab_result == .SUCCESS {
        fmt.printf("--- Drum Track audio_buffer initialized. ---\n")
        drum_track_sound_flags: ma.sound_flags = { .NO_PITCH, .NO_SPATIALIZATION }; 
        p_drum_track_data_source := (^ma.data_source)(&drum_track_audio_buffer);
        init_drum_sound_result := ma.sound_init_from_data_source(&state.audio_engine, p_drum_track_data_source, drum_track_sound_flags, nil, &state.drum_track_sound);
        if init_drum_sound_result == .SUCCESS {
            ma.sound_set_looping(&state.drum_track_sound, true); 
            ma.sound_set_volume(&state.drum_track_sound, DRUM_TRACK_AMPLITUDE); 
            fmt.printf("--- Miniaudio drum_track_sound initialized successfully (Looping, Volume: %.2f) ---\n", DRUM_TRACK_AMPLITUDE);
        } else {
            fmt.eprintf("!!! CRITICAL: Miniaudio sound_init_from_data_source for drum_track_sound failed! Error: %v\n", init_drum_sound_result);
            ma.audio_buffer_uninit(&drum_track_audio_buffer); 
        }
    } else {
        fmt.eprintf("!!! CRITICAL: Drum Track audio_buffer_init_copy failed! Error: %v\n", init_drum_track_ab_result)
    }

    // (<<< NEW SYNTH TRACK INITIALIZATION START >>>)
    fmt.printf("--- Generating Heavy Fast Synth Track PCM data (160 BPM)... ---\n");

    SYNTH_TRACK_SECONDS_PER_BEAT_CALC : f32 = 60.0 / SYNTH_TRACK_BPM; // Renamed to avoid conflict if used elsewhere
    SYNTH_TRACK_FRAMES_PER_BEAT_F32_CALC : f32 = SYNTH_TRACK_SECONDS_PER_BEAT_CALC * f32(SYNTH_TRACK_SAMPLE_RATE);
    SYNTH_TRACK_FRAMES_PER_BEAT_CALC := int(math.round_f32(SYNTH_TRACK_FRAMES_PER_BEAT_F32_CALC));
    SYNTH_TRACK_FRAMES_PER_BAR_CALC := SYNTH_TRACK_FRAMES_PER_BEAT_CALC * SYNTH_TRACK_BEATS_PER_BAR;
    SYNTH_TRACK_TOTAL_FRAMES_CALC := SYNTH_TRACK_FRAMES_PER_BAR_CALC * SYNTH_TRACK_NUM_BARS;

    synth_track_pcm_data = make([]f32, SYNTH_TRACK_TOTAL_FRAMES_CALC);
    if synth_track_pcm_data == nil {
        fmt.eprintf("!!! CRITICAL: Failed to allocate synth_track_pcm_data! Total Frames: %d\n", SYNTH_TRACK_TOTAL_FRAMES_CALC);
        return; // Cannot proceed
    } else {
        fmt.printf("--- Synth track PCM data slice allocated. Total Frames: %d ---\n", SYNTH_TRACK_TOTAL_FRAMES_CALC);
    }
    for i in 0..<SYNTH_TRACK_TOTAL_FRAMES_CALC { synth_track_pcm_data[i] = 0.0; }

    synth_attack_frames  := int(SYNTH_NOTE_ATTACK_TIME_S * f32(SYNTH_TRACK_SAMPLE_RATE));
    synth_decay_frames   := int(SYNTH_NOTE_DECAY_TIME_S * f32(SYNTH_TRACK_SAMPLE_RATE));
    synth_release_frames := int(SYNTH_NOTE_RELEASE_TIME_S * f32(SYNTH_TRACK_SAMPLE_RATE));

    NOTE_DURATION_FRAMES_8TH_SYNTH := SYNTH_TRACK_FRAMES_PER_BEAT_CALC / 2; // Renamed

    min_adsr_frames_synth := synth_attack_frames + synth_decay_frames + synth_release_frames; // Renamed
    if NOTE_DURATION_FRAMES_8TH_SYNTH < min_adsr_frames_synth {
        fmt.eprintf("!!! WARNING: Synth note duration (%d frames) is shorter than ADSR phases combined (%d frames). Adjust ADSR times.\n", NOTE_DURATION_FRAMES_8TH_SYNTH, min_adsr_frames_synth);
    }
    synth_sustain_duration_frames := NOTE_DURATION_FRAMES_8TH_SYNTH - synth_attack_frames - synth_decay_frames - synth_release_frames;
    if synth_sustain_duration_frames < 0 { synth_sustain_duration_frames = 0; } 

    note_frequencies_synth := [SYNTH_TRACK_NUM_BARS][SYNTH_TRACK_BEATS_PER_BAR * 2]f32 {}; // Renamed
    for i in 0..<(SYNTH_TRACK_BEATS_PER_BAR * 2) { note_frequencies_synth[0][i] = 110.0; } // A2
    for i in 0..<(SYNTH_TRACK_BEATS_PER_BAR * 2) { note_frequencies_synth[1][i] = 130.81; } // C3

    current_phase_synth_gen: f64 = 0.0; // Renamed

    for bar_s_idx in 0..<SYNTH_TRACK_NUM_BARS { // Renamed
        for eighth_note_s_idx in 0..<(SYNTH_TRACK_BEATS_PER_BAR * 2) { // Renamed
            note_start_frame_in_track_s := (bar_s_idx * SYNTH_TRACK_FRAMES_PER_BAR_CALC) + (eighth_note_s_idx * NOTE_DURATION_FRAMES_8TH_SYNTH); // Renamed
            current_note_freq_s := f64(note_frequencies_synth[bar_s_idx][eighth_note_s_idx]); // Renamed

            for frame_in_note_s in 0..<NOTE_DURATION_FRAMES_8TH_SYNTH { // Renamed
                global_frame_idx_s := note_start_frame_in_track_s + frame_in_note_s; // Renamed
                if global_frame_idx_s >= SYNTH_TRACK_TOTAL_FRAMES_CALC { break; }

                envelope_amp_s: f32 = 0.0; // Renamed
                if frame_in_note_s < synth_attack_frames {
                    envelope_amp_s = f32(frame_in_note_s) / f32(math.max(1,synth_attack_frames)); // max(1,..) to avoid div by zero if attack_frames is 0
                } else if frame_in_note_s < synth_attack_frames + synth_decay_frames {
                    progress_decay_s := f32(frame_in_note_s - synth_attack_frames) / f32(math.max(1,synth_decay_frames));
                    // Cast untyped float consts to f64 for m.lerp, and progress_decay_s to f64. Cast result to f32.
                    envelope_amp_s = f32(m.lerp(f32(1.0), f32(SYNTH_NOTE_SUSTAIN_LEVEL), f32(progress_decay_s)));
                } else if frame_in_note_s < synth_attack_frames + synth_decay_frames + synth_sustain_duration_frames {
                    envelope_amp_s = SYNTH_NOTE_SUSTAIN_LEVEL; // This is f32, ensure SYNTH_NOTE_SUSTAIN_LEVEL is assignable or cast
                                                              // SYNTH_NOTE_SUSTAIN_LEVEL :: 0.6 (untyped float, can assign to f32) - this line is OK
                } else { 
                    if synth_release_frames > 0 {
                        frames_into_release_s := frame_in_note_s - (synth_attack_frames + synth_decay_frames + synth_sustain_duration_frames);
                        progress_release_s := f32(frames_into_release_s) / f32(synth_release_frames);
                        // Cast untyped float consts to f64 for m.lerp, and progress_release_s to f64. Cast result to f32.
                        envelope_amp_s = f32(m.lerp(f32(SYNTH_NOTE_SUSTAIN_LEVEL), f32(0.0), f32(progress_release_s)));
                    } else { envelope_amp_s = 0.0; }
                }
                envelope_amp_s = math.clamp(envelope_amp_s, 0.0, 1.0);

                saw_phase_s := current_phase_synth_gen / (2.0 * f64(math.PI)); // Renamed
                sample_val_f64_s := 2.0 * (saw_phase_s - math.floor(0.5 + saw_phase_s)); // Renamed

                synth_track_pcm_data[global_frame_idx_s] += f32(sample_val_f64_s * f64(envelope_amp_s) * f64(SYNTH_TRACK_AMPLITUDE));
                
                current_phase_synth_gen += (2.0 * f64(math.PI) * current_note_freq_s) / f64(SYNTH_TRACK_SAMPLE_RATE);
                if current_phase_synth_gen >= (2.0 * f64(math.PI)) {
                    current_phase_synth_gen -= (2.0 * f64(math.PI));
                }
            }
            current_phase_synth_gen = 0.0; // Reset phase for next note
        }
    }
    for i_clamp in 0..<SYNTH_TRACK_TOTAL_FRAMES_CALC {
        synth_track_pcm_data[i_clamp] = math.clamp(synth_track_pcm_data[i_clamp], -0.95, 0.95);
    }
    fmt.printf("--- Heavy Fast Synth Track PCM data generated. ---\n");

    synth_track_ab_config := ma.audio_buffer_config_init(ma.format.f32, u32(SYNTH_TRACK_CHANNELS), u64(SYNTH_TRACK_TOTAL_FRAMES_CALC), rawptr(&synth_track_pcm_data[0]), nil);
    init_synth_track_ab_result := ma.audio_buffer_init_copy(&synth_track_ab_config, &synth_track_audio_buffer);
    if init_synth_track_ab_result == .SUCCESS {
        fmt.printf("--- Synth Track audio_buffer initialized. ---\n");
        synth_track_sound_flags: ma.sound_flags = { .NO_PITCH, .NO_SPATIALIZATION };
        p_synth_track_data_source := (^ma.data_source)(&synth_track_audio_buffer);
        init_synth_sound_result := ma.sound_init_from_data_source(&state.audio_engine, p_synth_track_data_source, synth_track_sound_flags, nil, &state.synth_track_sound);
        if init_synth_sound_result == .SUCCESS {
            ma.sound_set_looping(&state.synth_track_sound, true);
            ma.sound_set_volume(&state.synth_track_sound, 1.0); // PCM data already has SYNTH_TRACK_AMPLITUDE baked in, so master volume is 1.0 unless further adjustment needed
            fmt.printf("--- Miniaudio synth_track_sound initialized successfully (Looping, Volume: %.2f) ---\n", 1.0);
        } else {
            fmt.eprintf("!!! CRITICAL: Miniaudio sound_init_from_data_source for synth_track_sound failed! Error: %v\n", init_synth_sound_result);
            ma.audio_buffer_uninit(&synth_track_audio_buffer);
        }
    } else {
        fmt.eprintf("!!! CRITICAL: Synth Track audio_buffer_init_copy failed! Error: %v\n", init_synth_track_ab_result);
    }
    // (<<< NEW SYNTH TRACK INITIALIZATION END >>>)


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

    state.key_shift_down = false;
    state.is_dashing = false;
    state.dash_timer = 0.0;
    state.dash_cooldown_timer = 0.0;
    state.player_dash_trail_count = 0;
    state.dash_trail_spawn_timer = 0.0;

    state.rmb_down=false; state.previous_rmb_down=false; state.rmb_cooldown_timer=0.0;
    state.lmb_down=false; state.previous_lmb_down=false; state.lmb_cooldown_timer=0.0;
    state.mouse_screen_pos = {0,0};

    state.current_rmb_ammo_charges = 0; 
    state.rmb_ammo_regen_timer = RMB_AMMO_REGEN_INTERVAL/10; 

    state.grunt_spawn_timer = 1.0; 
    state.slowboy_spawn_timer = 5.0; 

    state.first_grunt_killed = false;
    state.first_slowboy_killed = false; // <<< NEW

    // --- Initialize Level Definitions ---
    fmt.printf("--- Initializing Level Definitions ---\n");
    game_levels = make([]LevelDefinition, 1);

    // --- Level 1 Definition ---
    game_levels[0] = LevelDefinition{
        // Define boss_config first, as the boss stage will refer to it.
        boss_config = EnemySpawnConfig {
            enemy_type = .BOSS_CHROME_ORB,
            count = 1,
            min_spawn_delay = 1.0, // Boss usually has a fixed or minimal delay once triggered
            max_spawn_delay = 1.0,
        },
        // Initialize stages slice for 2 regular stages + 1 boss stage
        stages = make([]StageDefinition, 3), 
    };

    // --- Level 1, Stage 1 ---
    game_levels[0].stages[0] = StageDefinition{
        enemy_configs = make([]EnemySpawnConfig, 1),
    };
    game_levels[0].stages[0].enemy_configs[0] = EnemySpawnConfig {
        enemy_type = .GRUNT,
        count = 1, // Test with a few grunts
        min_spawn_delay = 0.5,
        max_spawn_delay = 0.8,
    };

    // --- Level 1, Stage 2 ---
    game_levels[0].stages[1] = StageDefinition{
        enemy_configs = make([]EnemySpawnConfig, 2), // Two types of enemies in this stage
    };
    game_levels[0].stages[1].enemy_configs[0] = EnemySpawnConfig {
        enemy_type = .GRUNT,
        count = 1, // More grunts
        min_spawn_delay = 0.8,
        max_spawn_delay = 2.0,
    };
    game_levels[0].stages[1].enemy_configs[1] = EnemySpawnConfig {
        enemy_type = .SLOWBOY,
        count = 1, // A couple of slowboys
        min_spawn_delay = 2.0,
        max_spawn_delay = 4.0,
    };

    // --- Level 1, Stage 3 (Boss Stage) ---
    // This stage uses the boss_config defined in the LevelDefinition.
    game_levels[0].stages[2] = StageDefinition{
        enemy_configs = make([]EnemySpawnConfig, 1),
    };
    // Assign the boss configuration to the enemy config of the boss stage.
    game_levels[0].stages[2].enemy_configs[0] = game_levels[0].boss_config; 

    fmt.printf("--- Level Definitions Initialized: %d levels ---\n", len(game_levels));
    if len(game_levels) > 0 {
        fmt.printf("    Level 0 Stages: %d\n", len(game_levels[0].stages));
        if len(game_levels[0].stages) > 0 {
             fmt.printf("        Stage 0 Enemy Configs: %d (counts: %d)\n", len(game_levels[0].stages[0].enemy_configs), game_levels[0].stages[0].enemy_configs[0].count);
             if len(game_levels[0].stages[1].enemy_configs) > 1 {
                 fmt.printf("        Stage 1 Enemy Configs: %d (counts: %d, %d)\n", len(game_levels[0].stages[1].enemy_configs), game_levels[0].stages[1].enemy_configs[0].count, game_levels[0].stages[1].enemy_configs[1].count);
             }
             fmt.printf("        Stage 2 (Boss) Enemy Configs: %d (counts: %d)\n", len(game_levels[0].stages[2].enemy_configs), game_levels[0].stages[2].enemy_configs[0].count);
        }
    }
    // --- End Level Definitions Initialization ---

    // --- Initialize Game Progression State ---
    random_generator_progression_seed: u64 = u64(sapp.frame_count()) + 12345; // Add some variance
    random_generator_progression = rand.create(random_generator_progression_seed); 
    fmt.printf("Initialized progression RNG (random_generator_progression) with seed: %d\n", random_generator_progression_seed);
    
    load_and_initialize_stage_progression(0, 0); // Load Level 0, Stage 0
    // --- End Game Progression State Initialization ---

    fmt.printf("--- Init Complete ---\n")
}

event :: proc "c" (event: ^sapp.Event) {
    context = runtime.default_context()
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
            p.charge_center_pos.y += p.angular_vel * dt; // Using charge_center_pos.y for individual spin angle of ammo indicators
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
            if p.is_ammo_indicator { inst.instance_rotation = p.charge_center_pos.y;  } // Use .y for self-spin
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
            rotation = current_orbit_angle_va,  // This is the orbit angle around player
            angular_vel = RMB_AMMO_INDICATOR_SELF_SPIN_SPEED, // For charge_center_pos.y update rate
            charge_center_pos= m.vec2{f32(charge_slot_index), rand.float32()*m.TAU}, // Store charge index in .x, initial random spin angle in .y
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
                // fmt.printf("RMB Hit: Enemy %p, HP before sound check: %d\n", enemy_rmb_coll, enemy_rmb_coll.hp);
                
                if enemy_rmb_coll.hp <= 0 {
                    if !enemy_rmb_coll.is_dying {
                        // fmt.printf("RMB Kill branch: Playing death sound for enemy %p. is_dying: %t\n", enemy_rmb_coll, enemy_rmb_coll.is_dying);
                        ma.sound_seek_to_pcm_frame(&state.rmb_kill_sound, 0);
                        ma.sound_start(&state.rmb_kill_sound);
                    }
                } else {
                    // fmt.printf("RMB Hit branch: Playing hit sound for enemy %p. HP: %d\n", enemy_rmb_coll, enemy_rmb_coll.hp);
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
                    state.progression.enemies_defeated_in_current_stage += 1;
                    fmt.printf("RMB Kill: Enemy defeated. Stage progress: %d/%d\n", state.progression.enemies_defeated_in_current_stage, state.progression.total_enemies_defined_for_current_stage);
                    if enemy_rmb_coll.type == .GRUNT {
                        enemy_rmb_coll.dying_timer = GRUNT_DEATH_ANIM_DURATION;
                        enemy_rmb_coll.death_anim_max_duration = GRUNT_DEATH_ANIM_DURATION;
                    } else if enemy_rmb_coll.type == .SLOWBOY {
                        enemy_rmb_coll.dying_timer = SLOWBOY_DEATH_ANIM_DURATION;
                        enemy_rmb_coll.death_anim_max_duration = SLOWBOY_DEATH_ANIM_DURATION;
                    } else if enemy_rmb_coll.type == .BOSS_CHROME_ORB { 
                        enemy_rmb_coll.dying_timer = BOSS_DEATH_ANIM_DURATION; 
                        enemy_rmb_coll.death_anim_max_duration = BOSS_DEATH_ANIM_DURATION;
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
                // fmt.printf("LMB Hit: Enemy %p, HP before sound check: %d\n", enemy_lmb_coll, enemy_lmb_coll.hp);
                if enemy_lmb_coll.hp <= 0 {
                    if !enemy_lmb_coll.is_dying {
                        //  fmt.printf("LMB Kill branch: Playing death sound for enemy %p. is_dying: %t\n", enemy_lmb_coll, enemy_lmb_coll.is_dying);
                         ma.sound_seek_to_pcm_frame(&state.lmb_kill_sound, 0);
                         ma.sound_start(&state.lmb_kill_sound);
                    }
                } else {
                    // fmt.printf("LMB Hit branch: Playing hit sound for enemy %p. HP: %d\n", enemy_lmb_coll, enemy_lmb_coll.hp);
                    ma.sound_seek_to_pcm_frame(&state.lmb_hit_sound, 0);
                    ma.sound_start(&state.lmb_hit_sound);
                }

                if enemy_lmb_coll.hp <= 0 && !enemy_lmb_coll.is_dying { 
                    enemy_lmb_coll.is_dying = true;
                    state.progression.enemies_defeated_in_current_stage += 1;
                    fmt.printf("LMB Kill: Enemy defeated. Stage progress: %d/%d\n", state.progression.enemies_defeated_in_current_stage, state.progression.total_enemies_defined_for_current_stage);
                    if enemy_lmb_coll.type == .GRUNT {
                        enemy_lmb_coll.dying_timer = GRUNT_DEATH_ANIM_DURATION;
                        enemy_lmb_coll.death_anim_max_duration = GRUNT_DEATH_ANIM_DURATION;
                    } else if enemy_lmb_coll.type == .SLOWBOY {
                        enemy_lmb_coll.dying_timer = SLOWBOY_DEATH_ANIM_DURATION;
                        enemy_lmb_coll.death_anim_max_duration = SLOWBOY_DEATH_ANIM_DURATION;
                     } else if enemy_lmb_coll.type == .BOSS_CHROME_ORB { 
                        enemy_lmb_coll.dying_timer = BOSS_DEATH_ANIM_DURATION; 
                        enemy_lmb_coll.death_anim_max_duration = BOSS_DEATH_ANIM_DURATION;
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

    enemy_to_spawn: Enemy
    
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
        case: 
            fmt.printf("spawn_enemy: ERROR - Unknown type_to_spawn: %v\n", type_to_spawn);
            return; 
    }

    enemy_to_spawn = Enemy {
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
                if enemy_uie.type == .SLOWBOY && enemy_uie.is_charging_attack { 
                    has_updated_pos_for_charge_bounce_uie = true; 
                    aspect_ratio_uie := sapp.widthf() / sapp.heightf(); 
                    current_ortho_width_uie := ORTHO_HEIGHT * aspect_ratio_uie; 
                    enemy_half_size_uie := enemy_uie.current_size * 0.5; 
                    min_x_uie := -current_ortho_width_uie + enemy_half_size_uie; max_x_uie :=  current_ortho_width_uie - enemy_half_size_uie; 
                    min_y_uie := -ORTHO_HEIGHT + enemy_half_size_uie; max_y_uie :=  ORTHO_HEIGHT - enemy_half_size_uie; 
                    enemy_uie.pos += enemy_uie.vel * dt; 
                    if enemy_uie.pos.x < min_x_uie { enemy_uie.pos.x = min_x_uie; enemy_uie.vel.x *= -1; } 
                    else if enemy_uie.pos.x > max_x_uie { enemy_uie.pos.x = max_x_uie; enemy_uie.vel.x *= -1; }
                    if enemy_uie.pos.y < min_y_uie { enemy_uie.pos.y = min_y_uie; enemy_uie.vel.y *= -1; } 
                    else if enemy_uie.pos.y > max_y_uie { enemy_uie.pos.y = max_y_uie; enemy_uie.vel.y *= -1; }
                    
                    charge_distance_world_units_uie : f32 = ORTHO_HEIGHT * 2.0 * SLOWBOY_ATTACK_CHARGE_SCREEN_FRACTION; 
                    charge_distance_sq_uie := charge_distance_world_units_uie * charge_distance_world_units_uie; 
                    if m.dist_sq_vec2(enemy_uie.pos, enemy_uie.attack_charge_start_pos) >= charge_distance_sq_uie {
                        enemy_uie.is_charging_attack = false; enemy_uie.vel = {0,0}; 
                    }
                } else { // Grunt moving, or Slowboy idle/moving (not charging, not winding up this frame)
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
    delta_time_f := f32(sapp.frame_duration()); delta_time_f = math.min(delta_time_f, 1.0/15.0); 

    current_ortho_width_for_bounds_f := ORTHO_HEIGHT * aspect_f; 

    state.player_invulnerable_timer = math.max(0.0, state.player_invulnerable_timer - delta_time_f);
    state.rmb_cooldown_timer = math.max(0.0, state.rmb_cooldown_timer - delta_time_f)
    state.lmb_cooldown_timer = math.max(0.0, state.lmb_cooldown_timer - delta_time_f)
    state.dash_timer = math.max(0.0, state.dash_timer - delta_time_f);       // <<< NEW
    state.dash_cooldown_timer = math.max(0.0, state.dash_cooldown_timer - delta_time_f); // <<< NEW

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
             state.rmb_ammo_regen_timer -= delta_time_f;
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
                state.dash_trail_spawn_timer -= delta_time_f;
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
            state.player_vel += final_accel_f*delta_time_f; 
            damping_factor_f := math.max(0.0, 1.0-PLAYER_DAMPING*delta_time_f); // Renamed
            state.player_vel *= damping_factor_f; 
            if m.len_sq_vec2(state.player_vel) > f32(PLAYER_MAX_SPEED*PLAYER_MAX_SPEED) { state.player_vel=m.norm_vec2(state.player_vel)*PLAYER_MAX_SPEED }; 
        }


        state.player_pos += state.player_vel*delta_time_f;

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

    // Define bounce boundary variables using the calculated orthographic width
    bounce_min_x_f : f32 = -current_ortho_width_for_bounds_f + PLAYER_CORE_WORLD_RADIUS;
    bounce_max_x_f : f32 =  current_ortho_width_for_bounds_f - PLAYER_CORE_WORLD_RADIUS;
    bounce_min_y_f : f32 = -ORTHO_HEIGHT + PLAYER_CORE_WORLD_RADIUS;
    bounce_max_y_f : f32 =  ORTHO_HEIGHT - PLAYER_CORE_WORLD_RADIUS;

    if state.player_pos.x < bounce_min_x_f { state.player_pos.x = bounce_min_x_f; if state.player_vel.x < 0 { state.player_vel.x *= -PLAYER_BOUNCE_DAMPING_FACTOR }} 
    else if state.player_pos.x > bounce_max_x_f { state.player_pos.x = bounce_max_x_f; if state.player_vel.x > 0 { state.player_vel.x *= -PLAYER_BOUNCE_DAMPING_FACTOR }}
    if state.player_pos.y < bounce_min_y_f { state.player_pos.y = bounce_min_y_f; if state.player_vel.y < 0 { state.player_vel.y *= -PLAYER_BOUNCE_DAMPING_FACTOR }} 
    else if state.player_pos.y > bounce_max_y_f { state.player_pos.y = bounce_max_y_f; if state.player_vel.y > 0 { state.player_vel.y *= -PLAYER_BOUNCE_DAMPING_FACTOR }}
    
    // --- New Stage-Based Enemy Spawning ---
    if !state.progression.active_stage.all_enemies_for_stage_spawned && state.player_hp > 0 { // Only spawn if player is alive
        current_level_def: ^LevelDefinition;
        current_stage_def: ^StageDefinition;
        
        if state.progression.current_level_index < len(game_levels) {
            current_level_def = &game_levels[state.progression.current_level_index];
            if state.progression.current_stage_index < len(current_level_def.stages) {
                current_stage_def = &current_level_def.stages[state.progression.current_stage_index];

                all_configs_done_spawning_this_frame := true; 

                for &spawn_state, idx in &state.progression.active_stage.enemy_spawn_states { 
                    if spawn_state.remaining_to_spawn == 0 {
                        continue; 
                    }
                    
                    all_configs_done_spawning_this_frame = false; 

                    spawn_state.spawn_timer -= delta_time_f;

                    if spawn_state.spawn_timer <= 0.0 {
                        if spawn_state.config_index < len(current_stage_def.enemy_configs) {
                            config := &current_stage_def.enemy_configs[spawn_state.config_index];
                            current_ortho_width_for_spawn_f := ORTHO_HEIGHT * aspect_f;
    
                            spawn_enemy(current_ortho_width_for_spawn_f, ORTHO_HEIGHT, state.player_pos, config.enemy_type);
                            
                            spawn_state.remaining_to_spawn -= 1;
                            spawn_state.spawned_count += 1;
                            
                            if spawn_state.remaining_to_spawn > 0 {
                                spawn_state.spawn_timer = rand.float32_range(config.min_spawn_delay, config.max_spawn_delay, runtime.default_random_generator(&random_generator_progression));
                            } else {
                                spawn_state.spawn_timer = 0; 
                            }
                        } else {
                            fmt.printf("ERROR: spawn_state.config_index out of bounds!\n");
                        }
                    }
                }
                
                if all_configs_done_spawning_this_frame {
                     state.progression.active_stage.all_enemies_for_stage_spawned = true;
                     fmt.printf("All enemies for Stage %d Level %d have been spawned.\n", state.progression.current_stage_index, state.progression.current_level_index);
                }

            } else {
                state.progression.active_stage.all_enemies_for_stage_spawned = true;
            }
        } else {
            state.progression.active_stage.all_enemies_for_stage_spawned = true;
        }
    }
    // --- End of New Stage-Based Enemy Spawning ---

    state.num_active_particles = update_and_instance_particles(delta_time_f);
    state.num_active_enemies = update_and_instance_enemies(delta_time_f); 
    state.num_active_blackholes = update_and_instance_blackholes(delta_time_f);

    check_LMB_projectile_enemy_collisions();
    check_RMB_particle_enemy_collisions();
    check_player_enemy_collisions(); 
    check_player_boss_laser_collision();

    // --- Stage Advancement Logic ---
    if state.progression.active_stage.all_enemies_for_stage_spawned &&
       state.progression.enemies_defeated_in_current_stage >= state.progression.total_enemies_defined_for_current_stage &&
       state.player_hp > 0 { 

        fmt.printf("Stage %d (Level %d) COMPLETED. Defeated %d / %d enemies.\n", 
                   state.progression.current_stage_index, state.progression.current_level_index, 
                   state.progression.enemies_defeated_in_current_stage, state.progression.total_enemies_defined_for_current_stage);

        current_level_idx_before_advancement := state.progression.current_level_index;
        next_stage_to_load := state.progression.current_stage_index + 1;
        next_level_to_load := state.progression.current_level_index;
        
        game_is_now_won := false;

        if current_level_idx_before_advancement < len(game_levels) {
            current_level_def := &game_levels[current_level_idx_before_advancement];
            if next_stage_to_load >= len(current_level_def.stages) {
                fmt.printf("Level %d COMPLETED.\n", current_level_idx_before_advancement);
                next_level_to_load = current_level_idx_before_advancement + 1;
                next_stage_to_load = 0; 

                if next_level_to_load >= len(game_levels) {
                    game_is_now_won = true;
                }
            }
        } else {
            fmt.printf("ERROR: current_level_index (%d) was already out of bounds of game_levels (%d).\n", current_level_idx_before_advancement, len(game_levels));
            game_is_now_won = true; 
        }

        if game_is_now_won {
            fmt.printf("--- ALL LEVELS COMPLETED! GAME WON! ---\n");
            // To stop further stage loads if game is won:
             state.progression.active_stage.all_enemies_for_stage_spawned = true; // Keep this true
             state.progression.enemies_defeated_in_current_stage = state.progression.total_enemies_defined_for_current_stage + 1; // Ensure condition above doesn't re-trigger
        } else {
            fmt.printf("Advancing to Level %d, Stage %d.\n", next_level_to_load, next_stage_to_load);
            load_and_initialize_stage_progression(next_level_to_load, next_stage_to_load);
        }
    }
    // --- End Stage Advancement Logic ---

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
    
    ma.sound_uninit(&state.lmb_sound); fmt.printf("--- Miniaudio lmb_sound uninitialized ---\n")
    ma.audio_buffer_uninit(&lmb_sound_audio_buffer); fmt.printf("--- Miniaudio lmb_sound_audio_buffer uninitialized ---\n")

    ma.audio_buffer_uninit(&rmb_hum_audio_buffer); fmt.printf("--- RMB Hum global audio_buffer uninitialized ---\n")
    ma.audio_buffer_uninit(&rmb_whoosh_audio_buffer); fmt.printf("--- RMB Whoosh global audio_buffer uninitialized ---\n")

    ma.audio_buffer_uninit(&enemy_hit_sound_audio_buffer); fmt.printf("--- Enemy Hit audio_buffer uninitialized ---\n")
    ma.audio_buffer_uninit(&enemy_death_sound_audio_buffer); fmt.printf("--- Enemy Death audio_buffer uninitialized ---\n")

    ma.audio_buffer_uninit(&lmb_hit_whoosh_audio_buffer); fmt.printf("--- LMB Hit Whoosh audio_buffer uninitialized ---\n")
    ma.audio_buffer_uninit(&lmb_kill_explosion_audio_buffer); fmt.printf("--- LMB Kill Explosion audio_buffer uninitialized ---\n")
    
    delete(drum_track_pcm_data); fmt.printf("--- Drum track PCM data slice deleted ---\n");
    ma.audio_buffer_uninit(&drum_track_audio_buffer); fmt.printf("--- Drum Track audio_buffer uninitialized ---\n");

    // (<<< NEW SYNTH CLEANUP START >>>)
    delete(synth_track_pcm_data); fmt.printf("--- Synth track PCM data slice deleted ---\n");
    ma.audio_buffer_uninit(&synth_track_audio_buffer); fmt.printf("--- Synth Track audio_buffer uninitialized ---\n");
    // (<<< NEW SYNTH CLEANUP END >>>)

    ma.sound_uninit(&state.lmb_hit_sound); fmt.printf("--- Miniaudio lmb_hit_sound uninitialized ---\n");
    ma.sound_uninit(&state.lmb_kill_sound); fmt.printf("--- Miniaudio lmb_kill_sound uninitialized ---\n");
    ma.sound_uninit(&state.rmb_hit_sound); fmt.printf("--- Miniaudio rmb_hit_sound uninitialized ---\n");
    ma.sound_uninit(&state.rmb_kill_sound); fmt.printf("--- Miniaudio rmb_kill_sound uninitialized ---\n");
    ma.sound_uninit(&state.drum_track_sound); fmt.printf("--- Miniaudio drum_track_sound uninitialized ---\n");
    ma.sound_uninit(&state.synth_track_sound); fmt.printf("--- Miniaudio synth_track_sound uninitialized ---\n"); // <<< NEW

    ma.engine_uninit(&state.audio_engine); fmt.printf("--- Miniaudio engine uninitialized ---\n")
    if sa.isvalid() { sa.shutdown(); fmt.printf("--- Sokol Audio shutdown ---\n") }
    sg.shutdown(); 
}
main :: proc () { sapp.run({ init_cb=init, frame_cb=frame, cleanup_cb=cleanup, event_cb=event, width=800, height=600, sample_count=4, window_title="GeoWars Odin - Synth Track", icon={sokol_default=true}, logger={func=slog.func} }) }
