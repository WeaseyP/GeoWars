package shared

import m "../vendor/math"
import ma "../vendor/miniaudio"
import "base:runtime"



// --- Enemy Type Enum ---
EnemyType :: enum {
    GRUNT,
    SLOWBOY,
    BOSS_CHROME_ORB,
    SPLITTER,
    SNIPER,
    DISRUPTOR,
}

// Top-level game mode. Shop pauses everything except input + render.
// TEST is a debug mode used by the screenshot harness — wave/progression is disabled,
// the player can spawn enemies and reset the arena via debug keys.
GameMode :: enum { PLAYING, SHOP, TEST }

// Upgrade catalog. Each entry maps to a UpgradeDef in the shop module that knows how to apply
// itself to the effective-value mirrors on shared.state.
UpgradeID :: enum {
    NONE,
    MAX_HP_PLUS_1,
    MAX_HP_PLUS_2_FULL_HEAL,
    LMB_DAMAGE_PLUS_1,
    LMB_DAMAGE_PLUS_2,
    LMB_RAPID_FIRE,
    RMB_EXTRA_CHARGE,
    RMB_FAST_REGEN,
    RMB_INSTANT_REFILL,
    RMB_OVERCHARGE,
    MAX_SPEED_PLUS,
    FAST_DASH,
    TOUGH_SKIN,
}

// Runtime state of an open shop. populated when game_mode flips to SHOP.
ShopState :: struct {
    options:     [3]UpgradeID,
    hovered:     int,  // -1 = none, 0..2 = which card the mouse is over
    is_pre_boss: bool, // last shop before the boss — better odds of higher-tier picks
}

// AI sub-state for type-specific state machines (slowboy, sniper). Each type interprets
// the integer through its own enum-cast.
SlowboyState :: enum i32 { APPROACH, WINDUP, CHARGE, RECOVER }
SniperState  :: enum i32 { IDLE, AIMING, FIRING, COOLDOWN }

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

// --- Wave System ---
// A "wave" is one player-pressed batch of enemies. Each wave can have multiple spawn directives
// (drip-feed grunts, single sniper at start, splitter mid-way, etc.). Player presses F at the
// arena-centre button to enqueue the next wave; pressing 10x rapidly queues all 10 at once.

WaveSpawnDirective :: struct {
    enemy_type:           EnemyType,
    count:                int,
    initial_delay:        f32, // seconds after wave activation before the first spawn
    interval_min:         f32, // seconds between successive spawns of this directive
    interval_max:         f32,
    tier:                 int,  // 0 = normal, 1 = silver, 2 = gold (elite stats + visuals)
    randomize_non_disruptor: bool, // if true, enemy_type is chosen at spawn time from {GRUNT, SLOWBOY, SPLITTER, SNIPER}
    wait_for_arena_clear: bool, // directive is gated until no live (non-boss) enemy remains. Used to chain silver→gold.
}

WaveDefinition :: struct {
    directives: []WaveSpawnDirective,
}

// Runtime state for one directive inside an active wave.
ActiveWaveDirective :: struct {
    directive_index: int,
    timer:           f32,  // counts down to the next spawn
    remaining:       int,
    waiting_initial: bool, // true while we're still respecting initial_delay
    started:         bool, // false until any wait_for_arena_clear gate has been satisfied
}

ActiveWave :: struct {
    wave_index:       int,
    directive_states: [dynamic]ActiveWaveDirective,
    all_spawned:      bool,
}

LevelDefinition :: struct {
    waves:       [10]WaveDefinition,
    boss_config: WaveSpawnDirective,
}

WaveSystem :: struct {
    active_waves:         [dynamic]ActiveWave,
    next_wave_to_press:   int, // 0..10 — index of the next wave that an F press will trigger
    boss_triggered:       bool,
    button_press_cooldown: f32, // small debounce so a key-repeat doesn't fire twice

    // Visual feedback
    button_press_flash:   f32, // 0..1, briefly spikes to 1 on each press, decays

    // Shop integration: how many shops have already been resolved (0..3). The next shop opens
    // when next_wave_to_press >= (shops_offered+1)*3 AND the arena is empty.
    shops_offered:        int,
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
    // --- Boss state ---
    boss_move_direction: f32,        // +1 / -1 sign for orbital direction (CCW / CW)
    boss_phase: int,                 // 1 = perimeter circle, 2 = centre orbit + sweeping laser + minions
    boss_angle: f32,                 // current angle on the orbital path around arena centre
    boss_roll_angle: f32,            // accumulated visual roll angle (for "rolling" surface)
    boss_minion_spawn_timer: f32,    // phase 2 minion spawn countdown
    boss_current_laser_length: f32,  // dynamic laser length so collision can match the visual
    boss_laser_count: int,           // 1 in phase 1; 2-6 in phase 2 (scales with HP loss)

    // Elite-tier scaling. Tier 0 = normal; 1 = silver (~2x base); 2 = gold (~4x base).
    // speed_mult and dmg_mult are derived from tier at spawn so per-frame logic doesn't have
    // to branch.
    enemy_tier:    i32,
    speed_mult:    f32,
    dmg_mult:      f32,
    boss_laser_slot_order: [6]int,   // permutation of 0..5; lasers fill these slots in order
    boss_laser_fade_in_timer: f32,   // counts down from 1.0 to 0.0 while the most recent laser materialises
    boss_detection_print_cooldown: f32,

    // --- AI sub-state (used by slowboy + sniper; type-specific interpretation) ---
    ai_state:         i32,
    ai_state_timer:   f32, // remaining seconds in current state
    ai_state_total:   f32, // total duration of the current state (for normalised progress)
    ai_target_pos:    m.vec2, // lock-on snapshot (slowboy) or aim target (sniper)
    ai_origin_pos:    m.vec2, // anchor at the moment the current state started (slowboy charge)
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
