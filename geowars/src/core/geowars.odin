package main

import "base:runtime"
import "core:math"
import "core:fmt"
import slog "../vendor/sokol/log"
import sg "../vendor/sokol/gfx"
import sapp "../vendor/sokol/app"
import sglue "../vendor/sokol/glue"
import sa "../vendor/sokol/audio"
import m "../vendor/math"
import rand "core:math/rand"

import progression "../game/progression"
import player "../game/player"
import enemy "../game/enemy"
import particle "../game/particle"
import projectile "../game/projectile"
import collision "../game/collision"
import audio "../audio"
import graphics "../graphics"
import shared "../shared"


init :: proc "c" () {
    context = runtime.default_context()
    sg.setup({ pipeline_pool_size=16, buffer_pool_size=16, shader_pool_size=16, environment=sglue.environment(), logger={func=slog.func} })
    fmt.printf("--- Init Start ---\n")

    audio.init_audio()
    graphics.init_rendering()

    shared.state.next_particle_index = 0; shared.state.num_active_particles = 0
    shared.state.next_enemy_index = 0; shared.state.num_active_enemies = 0
    shared.state.next_blackhole_index = 0; shared.state.num_active_blackholes = 0

    shared.state.player_pos = {0,0}; shared.state.player_vel = {0,0}
    shared.state.player_max_hp = shared.PLAYER_MAX_HP_VALUE
    shared.state.player_hp = shared.state.player_max_hp
    shared.state.player_invulnerable_timer = 0.0
    shared.state.player_defeated_message_shown = false

    shared.state.key_shift_down = false
    shared.state.is_dashing = false
    shared.state.dash_timer = 0.0
    shared.state.dash_cooldown_timer = 0.0
    shared.state.player_dash_trail_count = 0
    shared.state.dash_trail_spawn_timer = 0.0

    shared.state.rmb_down=false; shared.state.previous_rmb_down=false; shared.state.rmb_cooldown_timer=0.0
    shared.state.lmb_down=false; shared.state.previous_lmb_down=false; shared.state.lmb_cooldown_timer=0.0
    shared.state.mouse_screen_pos = {0,0}

    shared.state.current_rmb_ammo_charges = 0
    shared.state.rmb_ammo_regen_timer = shared.RMB_AMMO_REGEN_INTERVAL/10

    shared.state.grunt_spawn_timer = 1.0
    shared.state.slowboy_spawn_timer = 5.0

    shared.state.first_grunt_killed = false
    shared.state.first_slowboy_killed = false

    fmt.printf("--- Initializing Level Definitions ---\n")
    shared.game_levels = make([]shared.LevelDefinition, 1)

    shared.game_levels[0] = shared.LevelDefinition{
        boss_config = shared.EnemySpawnConfig {
            enemy_type = .BOSS_CHROME_ORB,
            count = 1,
            min_spawn_delay = 1.0,
            max_spawn_delay = 1.0,
        },
        stages = make([]shared.StageDefinition, 3),
    }

    shared.game_levels[0].stages[0] = shared.StageDefinition{
        enemy_configs = make([]shared.EnemySpawnConfig, 1),
    }
    shared.game_levels[0].stages[0].enemy_configs[0] = shared.EnemySpawnConfig {
        enemy_type = .GRUNT,
        count = 5,
        min_spawn_delay = 0.5,
        max_spawn_delay = 1.2,
    }

    shared.game_levels[0].stages[1] = shared.StageDefinition{
        enemy_configs = make([]shared.EnemySpawnConfig, 2),
    }
    shared.game_levels[0].stages[1].enemy_configs[0] = shared.EnemySpawnConfig {
        enemy_type = .GRUNT,
        count = 1,
        min_spawn_delay = 0.8,
        max_spawn_delay = 2.0,
    }
    shared.game_levels[0].stages[1].enemy_configs[1] = shared.EnemySpawnConfig {
        enemy_type = .SLOWBOY,
        count = 1,
        min_spawn_delay = 2.0,
        max_spawn_delay = 4.0,
    }

    shared.game_levels[0].stages[2] = shared.StageDefinition{
        enemy_configs = make([]shared.EnemySpawnConfig, 1),
    }
    shared.game_levels[0].stages[2].enemy_configs[0] = shared.game_levels[0].boss_config

    fmt.printf("--- Level Definitions Initialized: %d levels ---\n", len(shared.game_levels))

    random_generator_progression_seed: u64 = u64(sapp.frame_count()) + 12345
    shared.random_generator_progression = rand.create(random_generator_progression_seed)
    fmt.printf("Initialized progression RNG with seed: %d\n", random_generator_progression_seed)

    progression.load_and_initialize_stage_progression(0, 0)

    fmt.printf("--- Init Complete ---\n")
}

event :: proc "c" (event: ^sapp.Event) {
    context = runtime.default_context()
    player.handle_player_input(event)
}

frame :: proc "c" () {
    context = runtime.default_context()
    width_f := sapp.widthf(); height_f := sapp.heightf(); aspect_f := width_f / height_f
    current_time_f := f32(sapp.frame_count()) / 60.0
    delta_time_f := f32(sapp.frame_duration()); delta_time_f = math.min(delta_time_f, 1.0/15.0)

    shared.state.player_invulnerable_timer = math.max(0.0, shared.state.player_invulnerable_timer - delta_time_f)
    shared.state.rmb_cooldown_timer = math.max(0.0, shared.state.rmb_cooldown_timer - delta_time_f)
    shared.state.lmb_cooldown_timer = math.max(0.0, shared.state.lmb_cooldown_timer - delta_time_f)
    shared.state.dash_timer = math.max(0.0, shared.state.dash_timer - delta_time_f)
    shared.state.dash_cooldown_timer = math.max(0.0, shared.state.dash_cooldown_timer - delta_time_f)

    player.update_player(delta_time_f)

    // Circular arena bounds: clamp player to a disc and bounce velocity off the boundary normal.
    player_radius := f32(shared.PLAYER_CORE_WORLD_RADIUS)
    max_dist := shared.ARENA_RADIUS - player_radius
    dist_from_center := m.len_vec2(shared.state.player_pos)
    if dist_from_center > max_dist {
        normal := m.norm_vec2(shared.state.player_pos)
        shared.state.player_pos = normal * max_dist
        v_dot_n := m.dot_vec2(shared.state.player_vel, normal)
        if v_dot_n > 0.0 {
            shared.state.player_vel -= normal * (v_dot_n * (1.0 + shared.ARENA_BOUNCE_DAMPING))
        }
    }

    progression.handle_enemy_spawning(delta_time_f, aspect_f)

    shared.state.num_active_particles = particle.update_and_instance_particles(delta_time_f)
    shared.state.num_active_enemies = enemy.update_and_instance_enemies(delta_time_f)
    shared.state.num_active_blackholes = projectile.update_and_instance_blackholes(delta_time_f)

    collision.check_LMB_projectile_enemy_collisions()
    collision.check_RMB_particle_enemy_collisions()
    player.check_player_enemy_collisions()
    player.check_player_boss_laser_collision()

    progression.update_progression()

    shared.state.bg_fs_params={tick=current_time_f, resolution={width_f,height_f}, bg_option=1}
    shared.state.player_fs_params={
        tick=current_time_f, resolution={width_f,height_f}, player_hp_uniform=f32(shared.state.player_hp),
        player_max_hp_uniform=f32(shared.state.player_max_hp), player_invulnerable_timer_uniform = shared.state.player_invulnerable_timer,
        player_invulnerability_duration_uniform = shared.PLAYER_INVULNERABILITY_DURATION,
    }
    shared.state.particle_fs_params={tick=current_time_f}
    shared.state.enemy_fs_params={tick=current_time_f}
    shared.state.blackhole_fs_params={tick=current_time_f}

    ortho_width_vp_f := shared.ORTHO_HEIGHT*aspect_f
    proj_f := m.ortho(-ortho_width_vp_f,ortho_width_vp_f,-shared.ORTHO_HEIGHT,shared.ORTHO_HEIGHT,-1.0,1.0)
    view_f := m.identity(); view_proj_f := m.mul(proj_f,view_f)

    scale_mat_f := m.scale(m.vec3{shared.PLAYER_SCALE,shared.PLAYER_SCALE,1.0})
    translate_mat_f := m.translate(m.vec3{shared.state.player_pos.x,shared.state.player_pos.y,0.0})
    model_f := m.mul(translate_mat_f,scale_mat_f)
    shared.state.player_vs_params.mvp=m.mul(view_proj_f,model_f)

    shared.state.particle_vs_params.view_proj=view_proj_f
    shared.state.enemy_vs_params.view_proj=view_proj_f
    shared.state.blackhole_vs_params.view_proj=view_proj_f


    sg.begin_pass({action=shared.state.pass_action, swapchain=sglue.swapchain() })
    // Background pass also renders the arena ring + outside-arena darkening (see fs_bg in shader.glsl).
    sg.apply_pipeline(shared.state.bg_pip); sg.apply_bindings(shared.state.bind); sg.apply_uniforms(shared.UB_bg_fs_params, sg.Range{ptr=&shared.state.bg_fs_params, size=size_of(shared.Bg_Fs_Params)}); sg.draw(0,4,1)

    sg.apply_pipeline(shared.state.player_pip); sg.apply_bindings(shared.state.bind); sg.apply_uniforms(shared.UB_Player_Vs_Params, sg.Range{ptr=&shared.state.player_vs_params, size=size_of(shared.Player_Vs_Params)}); sg.apply_uniforms(shared.UB_Player_Fs_Params, sg.Range{ptr=&shared.state.player_fs_params, size=size_of(shared.Player_Fs_Params)}); sg.draw(0,4,1)

    if shared.state.num_active_particles > 0 {
        sg.apply_pipeline(shared.state.particle_pip); sg.apply_bindings(shared.state.particle_bind); sg.update_buffer(shared.state.particle_instance_vbo, sg.Range{ptr=rawptr(&shared.state.particle_instance_data[0]), size=uint(shared.state.num_active_particles)*size_of(shared.Particle_Instance_Data)})
        sg.apply_uniforms(shared.UB_particle_vs_params, sg.Range{ptr=&shared.state.particle_vs_params, size=size_of(shared.Particle_Vs_Params)}); sg.apply_uniforms(shared.UB_particle_fs_params, sg.Range{ptr=&shared.state.particle_fs_params, size=size_of(shared.Particle_Fs_Params)})
        sg.draw(0, 4, shared.state.num_active_particles)
    }
    if shared.state.num_active_blackholes > 0 {
        sg.apply_pipeline(shared.state.blackhole_pip); sg.apply_bindings(shared.state.blackhole_bind)
        sg.update_buffer(shared.state.blackhole_instance_vbo, sg.Range{ptr=rawptr(&shared.state.blackhole_instance_data[0]), size=uint(shared.state.num_active_blackholes)*size_of(shared.Blackhole_Instance_Data)})
        sg.apply_uniforms(shared.UB_blackhole_vs_params, sg.Range{ptr=&shared.state.blackhole_vs_params, size=size_of(shared.Blackhole_Vs_Params)})
        sg.apply_uniforms(shared.UB_blackhole_fs_params, sg.Range{ptr=&shared.state.blackhole_fs_params, size=size_of(shared.Blackhole_Fs_Params)})
        sg.draw(0, 4, shared.state.num_active_blackholes)
    }
    if shared.state.num_active_enemies > 0 {
        sg.apply_pipeline(shared.state.enemy_pip); sg.apply_bindings(shared.state.enemy_bind)
        sg.update_buffer(shared.state.enemy_instance_vbo, sg.Range{ptr=rawptr(&shared.state.enemy_instance_data[0]), size=uint(shared.state.num_active_enemies)*size_of(shared.Enemy_Instance_Data)})
        sg.apply_uniforms(shared.UB_enemy_vs_params, sg.Range{ptr=&shared.state.enemy_vs_params, size=size_of(shared.Enemy_Vs_Params)})
        sg.apply_uniforms(shared.UB_enemy_fs_params, sg.Range{ptr=&shared.state.enemy_fs_params, size=size_of(shared.Enemy_Fs_Params)})
        sg.draw(0, 4, shared.state.num_active_enemies)
    }
    sg.end_pass(); sg.commit()
}


cleanup :: proc "c" () {
    context = runtime.default_context()
    audio.cleanup_audio()
    if sa.isvalid() { sa.shutdown(); fmt.printf("--- Sokol Audio shutdown ---\n") }
    sg.shutdown()
}

main :: proc () { sapp.run({ init_cb=init, frame_cb=frame, cleanup_cb=cleanup, event_cb=event, width=800, height=600, sample_count=4, window_title="GeoWars Odin", icon={sokol_default=true}, logger={func=slog.func} }) }
