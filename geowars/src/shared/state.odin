package shared

import sg "../vendor/sokol/gfx"
import ma "../vendor/miniaudio"
import m "../vendor/math"


// Global state. Lives in `shared` so every package can reach it as `shared.state`.
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
    synth_track_sound: ma.sound,

    first_grunt_killed: bool,
    first_slowboy_killed: bool,
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
