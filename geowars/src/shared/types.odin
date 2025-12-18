package main

import m "../vendor/math"
import ma "../vendor/miniaudio"
import "base:runtime"



// --- Enemy Type Enum ---
EnemyType :: enum {
    GRUNT,
    SLOWBOY,
    WEAVER,
    GRAVITRON,
    TRACER,
    BOSS_CHROME_ORB,
}

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

game_levels: []LevelDefinition; // Global variable for level definitions
random_generator_progression: runtime.Default_Random_State; // This is our seeded RNG state for progression
