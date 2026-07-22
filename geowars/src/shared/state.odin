package shared

import sg "../vendor/sokol/gfx"
import ma "../vendor/miniaudio"
import m "../vendor/math"


// Global state. Lives in `shared` so every package can reach it as `shared.state`.
state: struct {
    wave_system: WaveSystem,
    game_mode:   GameMode,
    shop:        ShopState,

    // --- Effective stat mirrors. Constants are baselines; these are the live values that the
    // shop's upgrades can modify. Initialised in core.init() to the constant defaults.
    eff_lmb_damage:        i32,
    eff_lmb_cooldown:      f32,
    eff_rmb_max_charge:    f32, // soft cap on the charge meter (default 2.0 = 200%)
    eff_rmb_charge_rate:   f32, // charge gained per second (default 0.10)
    eff_rmb_damage_mult:   f32, // RMB_OVERCHARGE upgrade scales particle damage
    eff_player_max_speed:  f32,
    eff_dash_cooldown:     f32,
    eff_invul_duration:    f32,

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
    synth_track_sound: ma.sound,
    splitter_track_sound: ma.sound,
    sniper_track_sound: ma.sound,
    disruptor_track_sound: ma.sound,
    boss_track_sound: ma.sound,
    boss_intensity_track_sound: ma.sound,
    boss_sax_track_sound: ma.sound,
    boss_tuba_track_sound: ma.sound,
    boss_hit_stinger_sound: ma.sound,

    // Once any enemy of these types is killed, its track unlocks and keeps playing for the rest
    // of the run (the music "builds" as new types get introduced). Disruptor is intentionally
    // not on this list — its track is gated on live disruptors only.
    first_grunt_killed: bool,
    first_slowboy_killed: bool,
    first_splitter_killed: bool,
    first_sniper_killed: bool,
    player_pos: m.vec2, player_vel: m.vec2,
    player_hp: int, player_max_hp: int,
    player_invulnerable_timer: f32,
    player_defeated_message_shown: bool,

    key_w_down: bool, key_s_down: bool, key_a_down: bool, key_d_down: bool, key_shift_down: bool, key_ctrl_down: bool,
    key_f_down: bool, key_f_was_down: bool,
    // One-shot edge flags consumed by the shop on the frame after the corresponding key down.
    shop_pick_1: bool, shop_pick_2: bool, shop_pick_3: bool,
    // Counter of disruptor → button collisions still to be processed by the wave system.
    // Each pending press drops a notch and activates the next wave (as if the player hit F).
    disruptor_button_presses_pending: int,
    player_aim_dir: m.vec2, // unit vector from player toward mouse cursor in world space

    rmb_down: bool, previous_rmb_down: bool, rmb_cooldown_timer: f32,
    lmb_down: bool, previous_lmb_down: bool, lmb_cooldown_timer: f32,
    // Fire-flash timers (0..1). Set to 1 the frame an attack actually fires; decayed each frame
    // and read by the player shader to draw a muzzle pulse / inward-suck animation.
    lmb_fire_flash: f32, rmb_fire_flash: f32,
    is_dashing: bool, dash_timer: f32, dash_cooldown_timer: f32,
    // dash_flash is set to 1.0 on dash start and decays over PLAYER_DASH_FLASH_DURATION; drives
    // the player FS shader's stretch/tint and the afterimage echo opacity in the renderer.
    dash_flash: f32,
    // Direction the dash launched along, captured at start so the stretch axis stays stable
    // even after the dash is over and player_vel has rotated to fresh input.
    dash_direction: m.vec2,

    player_dash_traiL_pos: [PLAYER_DASH_TRAIL_LENGTH]m.vec2,
    player_dash_trail_count: int,
    dash_trail_spawn_timer: f32,

    rmb_charge: f32, // current charge meter [0..eff_rmb_max_charge]; consumed on RMB press

    // Full-charge RMB beam. Set on release at >=RMB_BEAM_THRESHOLD; ticks down each frame.
    // Read by fs_bg to draw a directional purple lance + screen warp originating at rmb_beam_origin.
    rmb_beam_origin: m.vec2,
    rmb_beam_dir:    m.vec2, // unit vector along the beam axis
    rmb_beam_timer:  f32,    // remaining seconds; 0 means no beam visible
    rmb_beam_total:  f32,    // duration the beam was launched with (so the shader can fade it)

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

    // Deadzone-follow camera: camera_pos lags player_pos. Only moves when the player
    // pushes past the deadzone rectangle around the current camera centre.
    camera_pos: m.vec2,
}
