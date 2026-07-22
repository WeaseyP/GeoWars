package shared
import m "../vendor/math"


MAX_PARTICLES :: 2048
DEATH_BURST_PARTICLE_COUNT :: 150
MAX_ENEMIES :: 128
MAX_BLACKHOLES :: 64

// --- Constants ---
ORTHO_HEIGHT :: 1.5                    // half-height of the camera view in world units (left unchanged so the player and enemies keep their on-screen size)
ARENA_RADIUS :: ORTHO_HEIGHT * 2.4     // 3.6 — significantly bigger than the camera so the deadzone-follow camera scrolls as the player explores. Off-screen sniper shots feel meaningful at this scale.
ARENA_BOUNCE_DAMPING :: 0.6
ARENA_RING_THICKNESS :: 0.025

PLAYER_ACCELERATION       :: 24.0
PLAYER_REVERSE_FACTOR     :: 0.5
PLAYER_DAMPING            :: 4.0
PLAYER_MAX_SPEED          :: 7.0
PLAYER_DASH_SPEED_MULT    :: 1.8
PLAYER_DASH_DURATION      :: 0.12
PLAYER_DASH_COOLDOWN      :: 3.0
// Number of stored afterimage positions and how often a new one is captured during a dash.
// Smaller spacing + more entries reads as a denser motion-blur streak.
PLAYER_DASH_TRAIL_LENGTH      :: 6
PLAYER_DASH_TRAIL_SPAWN_RATE  :: 0.018
// `dash_flash` lives slightly beyond the dash itself so the afterimages have time to fade in
// place rather than disappearing the instant the dash ends.
PLAYER_DASH_FLASH_DURATION    :: f32(0.30)
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

// Explosion Constants (after swirl)
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
// Launch ramp + travel-wake polish.
PROJECTILE_BLACKHOLE_LAUNCH_RAMP    :: f32(0.08)  // size scales 0->1 over this many seconds at spawn
PROJECTILE_BLACKHOLE_TRAIL_INTERVAL :: f32(0.030) // spacing between wake particles
PROJECTILE_BLACKHOLE_TRAIL_LIFETIME :: f32(0.28)
PROJECTILE_BLACKHOLE_TRAIL_SIZE     :: f32(0.05)
PROJECTILE_BLACKHOLE_TRAIL_DRIFT    :: f32(0.18)  // fraction of bullet velocity inherited by wake
// Hit flash (non-kill impacts also get a small particle burst now).
LMB_HIT_FLASH_COUNT          :: 8
LMB_HIT_FLASH_SPEED_BASE     :: f32(2.0)
LMB_HIT_FLASH_SPEED_RAND     :: f32(1.5)
LMB_HIT_FLASH_LIFETIME_BASE  :: f32(0.18)
LMB_HIT_FLASH_LIFETIME_RAND  :: f32(0.12)
LMB_HIT_FLASH_SIZE_BASE      :: f32(0.022)
LMB_HIT_FLASH_SIZE_RAND      :: f32(0.012)


// --- Enemy Constants ---
ENEMY_GRUNT_SCALE :: 0.2
ENEMY_GRUNT_SPEED :: f32(0.5)
// --- SlowBoy Constants ---
ENEMY_SLOWBOY_BASE_SCALE :: 0.25
ENEMY_SLOWBOY_GLOW_CANVAS_SF :: 1.0
ENEMY_SLOWBOY_SPEED :: f32(0.15)
ENEMY_SLOWBOY_MAX_HP :: 16
// --- SlowBoy Attack Constants (state machine) ---
// Tightened: less prep, faster recover. Charge now spans a much larger arena fraction so the
// slowboy is a real positional threat instead of a polite mascot.
SLOWBOY_APPROACH_DURATION :: f32(2.0)
SLOWBOY_WINDUP_DURATION   :: f32(1.3)
SLOWBOY_CHARGE_DURATION   :: f32(0.30)
SLOWBOY_RECOVER_DURATION  :: f32(0.6)
SLOWBOY_CHARGE_DISTANCE   :: f32(ARENA_RADIUS * 0.7) // travels well over half the arena diameter
SLOWBOY_SHAKE_MAX_AMPL    :: f32(0.07)
SLOWBOY_SPIN_SPEED        :: f32(m.PI * 11.0)        // rad/s during charge — faster spin reads as nastier
// --- Boss Chrome Orb Constants ---
// Visual + collision radius of the orb body. They're tied so the hitbox matches what the player sees.
ENEMY_BOSS_VISUAL_RADIUS :: f32(0.18)
ENEMY_BOSS_CHROME_ORB_SCALE :: ENEMY_BOSS_VISUAL_RADIUS * 2.0   // diameter — used as `current_size` for collision
ENEMY_BOSS_CHROME_ORB_MAX_HP :: 200
// Quad covers orb + worst-case laser length so the laser fits inside one instanced quad. Sized
// to fit the longer phase-2 laser at the current ARENA_RADIUS.
BOSS_QUAD_WORLD_DIAMETER :: 8.5

// --- Boss orbit/laser geometry (shared by both phases) ---
ENEMY_BOSS_ORBIT_RADIUS :: f32(ARENA_RADIUS * 0.25)     // boss circles a small inner ring
ENEMY_BOSS_ORBIT_SPEED  :: f32(0.55)                    // rad/s; sign comes from boss_move_direction
ENEMY_BOSS_LASER_LENGTH :: f32(ARENA_RADIUS * 1.05)     // long enough to cross the arena
ENEMY_BOSS_LASER_SWEEP_SPEED :: f32(m.PI * 0.28)        // base sweep rate

// --- Boss Phase 1 (single sweeping laser, slow grunt drip) ---
// HP > 75% : clockwise. 75% > HP > 50% : counter-clockwise. Triggers phase 2 below 50%.
ENEMY_BOSS_PHASE1_MINION_SPAWN_INTERVAL :: f32(4.5)     // grunt only, slow trickle

// --- Boss Phase 2 (multi-laser fan, faster mixed minion mix, red colour) ---
ENEMY_BOSS_PHASE2_SWEEP_BOOST :: f32(1.3)               // sweep is 30% faster in phase 2
ENEMY_BOSS_PHASE2_MINION_SPAWN_INTERVAL :: f32(3.0)     // 1 minion every 3 seconds
ENEMY_BOSS_PHASE2_SLOWBOY_CHANCE :: f32(0.25)           // 25% slowboy, 75% grunt
ENEMY_BOSS_MAX_LASERS :: 6                              // shader/collision loop bound

BOSS_LASER_WIDTH  :: f32(0.07)                          // visible beam width in world units
BOSS_LASER_DAMAGE :: 1
ENEMY_SHADER_VISUAL_SCALE_MULTIPLIER :: 3.0


SLOWBOY_ATTACK_DAMAGE :: 1

// --- Elite Tiers ---
// 0 = normal, 1 = silver (2× base), 2 = gold (2× silver = 4× base). Tier multiplies HP, speed,
// damage; size and color also shift. Used by wave 10's mini-boss directives.
ELITE_TIER_SILVER     :: 1
ELITE_TIER_GOLD       :: 2
ELITE_HP_MULT_SILVER  :: f32(2.0)
ELITE_HP_MULT_GOLD    :: f32(4.0)
ELITE_SPEED_MULT_SILVER :: f32(1.6)  // capped below the strict 2x so the player can still kite
ELITE_SPEED_MULT_GOLD   :: f32(2.4)
ELITE_DMG_MULT_SILVER :: f32(2.0)
ELITE_DMG_MULT_GOLD   :: f32(4.0)
ELITE_SIZE_MULT_SILVER :: f32(1.25)
ELITE_SIZE_MULT_GOLD   :: f32(1.55)

// --- Splitter (asteroid-style) ---
ENEMY_SPLITTER_SCALE       :: f32(0.30)
ENEMY_SPLITTER_MAX_HP      :: i32(6)
ENEMY_SPLITTER_SPEED       :: f32(0.30)
ENEMY_SPLITTER_DEATH_ANIM  :: f32(1.0)
ENEMY_SPLITTER_MINI_COUNT  :: 3
ENEMY_SPLITTER_MINI_BURST_SPEED :: f32(1.2)
// How long each mini coasts on its burst velocity before homing. Randomised per-mini so the
// three siblings don't all transition on the same frame and immediately re-stack.
ENEMY_SPLITTER_MINI_BURST_DURATION_MIN :: f32(1.0)
ENEMY_SPLITTER_MINI_BURST_DURATION_MAX :: f32(1.5)

// --- Sniper (telegraphed hitscan) ---
ENEMY_SNIPER_SCALE         :: f32(0.22)
ENEMY_SNIPER_MAX_HP        :: i32(3)
ENEMY_SNIPER_DEATH_ANIM    :: f32(0.8)
ENEMY_SNIPER_IDLE_DURATION    :: f32(0.5)
ENEMY_SNIPER_AIM_DURATION     :: f32(1.5)
ENEMY_SNIPER_AIM_LOCK_REMAINING :: f32(0.35) // lock target this many seconds before fire
ENEMY_SNIPER_FIRE_DURATION    :: f32(0.18)
ENEMY_SNIPER_COOLDOWN_DURATION :: f32(1.5)
// Beam reaches well past the arena so the player can never hide off-screen from a sniper shot.
ENEMY_SNIPER_BEAM_LENGTH      :: f32(ARENA_RADIUS * 3.6)
ENEMY_SNIPER_QUAD_WORLD_DIAMETER :: f32(20.0)              // ≥ 2 * (BEAM_LENGTH + body) so beam fits
ENEMY_SNIPER_BEAM_HALF_WIDTH  :: f32(0.04)
ENEMY_SNIPER_DAMAGE           :: 1

// --- Disruptor (button rusher) ---
ENEMY_DISRUPTOR_SCALE      :: f32(0.16)
ENEMY_DISRUPTOR_MAX_HP     :: i32(2)
ENEMY_DISRUPTOR_SPEED      :: f32(0.7)
ENEMY_DISRUPTOR_DEATH_ANIM :: f32(0.6)
ENEMY_DISRUPTOR_BUTTON_PRESS_RANGE :: f32(0.30) // when this close to origin, presses the button
ENEMY_DISRUPTOR_PUNISH_GRUNTS  :: 5             // grunts spawned around the perimeter on a successful press

// --- Wave Button (interactable at arena origin) ---
WAVE_BUTTON_PRESS_RANGE    :: f32(0.45)         // player must be within this radius of origin
WAVE_BUTTON_PRESS_COOLDOWN :: f32(0.15)         // small debounce so a held key doesn't autofire
WAVE_BUTTON_TOTAL_WAVES    :: 10
WAVE_BUTTON_VISUAL_RADIUS  :: f32(0.16)
WAVE_BUTTON_FLASH_DECAY    :: f32(2.5)          // press_flash decays at this rate per second
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
GRUNT_DEATH_ANIM_DURATION :: 3.0
SLOWBOY_DEATH_ANIM_DURATION :: 1.0
BOSS_DEATH_ANIM_DURATION :: 4.0
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
// --- RMB charge meter (continuous charge replaces the old discrete pip system) ---
// Charge passively fills at RMB_CHARGE_RATE per second up to RMB_MAX_CHARGE_DEFAULT (200%).
// RMB-press fires droplets scaled to current charge fraction; >=100% also emits a screen pulse.
// Overcharge (charge > 1.0) keeps stacking droplets until the soft cap.
RMB_MAX_CHARGE_DEFAULT     :: f32(2.0)
RMB_CHARGE_RATE_DEFAULT    :: f32(0.10) // 10%/s — full charge in 10 s, max in 20 s
RMB_BEAM_THRESHOLD         :: f32(1.0)  // pulse unlocks at 100% charge
RMB_MIN_FIRE_CHARGE        :: f32(0.05) // ignore presses with essentially-empty charge
// Pulse-on-overcharge geometry: how many ring-particles, how fast they expand, lifetime, size.
RMB_PULSE_PARTICLE_COUNT   :: 32
RMB_PULSE_PARTICLE_SPEED   :: f32(7.0)
RMB_PULSE_PARTICLE_LIFETIME :: f32(0.45)
RMB_PULSE_PARTICLE_SIZE    :: f32(0.06)
RMB_PULSE_PARTICLE_COLOR   :: m.vec4{1.0, 0.45, 1.0, 0.95}

// --- RMB full-charge beam ---
// The directional purple lance fired alongside the pulse on a >=100% charge release. The beam
// is rendered in fs_bg (so it can warp the background) and applies a one-shot line-vs-enemy
// damage tick on release. Cosmetic timer is a brief flash; collision is one frame only.
RMB_BEAM_DURATION   :: f32(0.40)  // total visible time (s)
RMB_BEAM_LENGTH     :: f32(3.0)   // world units along player_aim_dir
RMB_BEAM_HALF_WIDTH :: f32(0.10)  // collision/visual half-width in world units
RMB_BEAM_DAMAGE_MULT :: f32(2.0)  // multiplier on PARTICLE_DAMAGE_VALUE * eff_rmb_damage_mult

// Rendering Internals
vertex_stride :: size_of(f32) * 7

particle_quad_stride :: size_of(f32) * 4
enemy_quad_stride :: size_of(f32) * 4
blackhole_quad_stride :: size_of(f32) * 4
