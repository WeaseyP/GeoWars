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


// =============================================================================
// START: Package-Level Declarations
// =============================================================================

// =============================================================================
// END: Package-Level Declarations
// =============================================================================


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



init :: proc "c" () {
    context = runtime.default_context()
    sg.setup({ pipeline_pool_size=16, buffer_pool_size=16, shader_pool_size=16, environment=sglue.environment(), logger={func=slog.func} }) // Increased pool sizes slightly
    fmt.printf("--- Init Start ---\n")

    init_audio()


    init_rendering()


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
    handle_player_input(event)
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

    update_player(delta_time_f)

    // Define bounce boundary variables using the calculated orthographic width
    bounce_min_x_f : f32 = -current_ortho_width_for_bounds_f + PLAYER_CORE_WORLD_RADIUS;
    bounce_max_x_f : f32 =  current_ortho_width_for_bounds_f - PLAYER_CORE_WORLD_RADIUS;
    bounce_min_y_f : f32 = -ORTHO_HEIGHT + PLAYER_CORE_WORLD_RADIUS;
    bounce_max_y_f : f32 =  ORTHO_HEIGHT - PLAYER_CORE_WORLD_RADIUS;

    if state.player_pos.x < bounce_min_x_f { state.player_pos.x = bounce_min_x_f; if state.player_vel.x < 0 { state.player_vel.x *= -PLAYER_BOUNCE_DAMPING_FACTOR }} 
    else if state.player_pos.x > bounce_max_x_f { state.player_pos.x = bounce_max_x_f; if state.player_vel.x > 0 { state.player_vel.x *= -PLAYER_BOUNCE_DAMPING_FACTOR }}
    if state.player_pos.y < bounce_min_y_f { state.player_pos.y = bounce_min_y_f; if state.player_vel.y < 0 { state.player_vel.y *= -PLAYER_BOUNCE_DAMPING_FACTOR }} 
    else if state.player_pos.y > bounce_max_y_f { state.player_pos.y = bounce_max_y_f; if state.player_vel.y > 0 { state.player_vel.y *= -PLAYER_BOUNCE_DAMPING_FACTOR }}
    
    handle_enemy_spawning(delta_time_f, aspect_f)

    state.num_active_particles = update_and_instance_particles(delta_time_f);
    state.num_active_enemies = update_and_instance_enemies(delta_time_f); 
    state.num_active_blackholes = update_and_instance_blackholes(delta_time_f);

    check_LMB_projectile_enemy_collisions();
    check_RMB_particle_enemy_collisions();
    check_player_enemy_collisions(); 
    check_player_boss_laser_collision();

    update_progression()

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
