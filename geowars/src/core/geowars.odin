package main

import "base:runtime"
import "core:math"
import "core:mem"
import "core:fmt"
import "core:c"
import slog "../vendor/sokol/log"
import sg "../vendor/sokol/gfx"
import sapp "../vendor/sokol/app"
import sglue "../vendor/sokol/glue"
import sa "../vendor/sokol/audio"
import sdtx "../vendor/sokol/debugtext"
import ma "../vendor/miniaudio"
import m "../vendor/math"
import rand "core:math/rand"

import "core:os"
import progression "../game/progression"
import player "../game/player"
import enemy "../game/enemy"
import particle "../game/particle"
import projectile "../game/projectile"
import collision "../game/collision"
import audio "../audio"
import graphics "../graphics"
import shared "../shared"


// =============================================================================
// START: Package-Level Declarations
// =============================================================================

// =============================================================================
// END: Package-Level Declarations
// =============================================================================


init :: proc "c" () {
    context = runtime.default_context()
    sg.setup({ pipeline_pool_size=16, buffer_pool_size=16, shader_pool_size=16, environment=sglue.environment(), logger={func=slog.func} }) // Increased pool sizes slightly
    sdtx.setup({ fonts = { 0 = sdtx.font_kc854() }, logger = { func = slog.func } })
    fmt.printf("--- Init Start ---\n")

    audio.init_audio()


    graphics.init_rendering()


    shared.state.next_particle_index = 0; shared.state.num_active_particles = 0;
    shared.state.next_enemy_index = 0; shared.state.num_active_enemies = 0;
    shared.state.next_blackhole_index = 0; shared.state.num_active_blackholes = 0;

    shared.state.player_pos = {0,0}; shared.state.player_vel = {0,0};
    shared.state.player_max_hp = PLAYER_MAX_HP_VALUE;
    shared.state.player_hp = shared.state.player_max_hp;
    shared.state.player_invulnerable_timer = 0.0;
    shared.state.player_defeated_message_shown = false;

    shared.state.key_shift_down = false;
    shared.state.is_dashing = false;
    shared.state.dash_timer = 0.0;
    shared.state.dash_cooldown_timer = 0.0;
    shared.state.player_dash_trail_count = 0;
    shared.state.dash_trail_spawn_timer = 0.0;

    shared.state.rmb_down=false; shared.state.previous_rmb_down=false; shared.state.rmb_cooldown_timer=0.0;
    shared.state.lmb_down=false; shared.state.previous_lmb_down=false; shared.state.lmb_cooldown_timer=0.0;
    shared.state.mouse_screen_pos = {0,0};

    shared.state.current_rmb_ammo_charges = 0;
    shared.state.rmb_ammo_regen_timer = RMB_AMMO_REGEN_INTERVAL/10;

    shared.state.grunt_spawn_timer = 1.0;
    shared.state.slowboy_spawn_timer = 5.0;

    shared.state.first_grunt_killed = false;
    shared.state.first_slowboy_killed = false; // <<< NEW

    shared.state.game_state = .Playing // Start playing immediately for now
    shared.state.surge_node = shared.SurgeNode{ active = false }
    shared.state.wave_transition_timer = 0.0

    // --- Initialize Level Definitions ---
    fmt.printf("--- Initializing Level Definitions ---\n");
    shared.game_levels = make([]shared.LevelDefinition, 1);

    // --- Level 1 Definition (8 Waves) ---
    shared.game_levels[0] = shared.LevelDefinition{
        boss_config = shared.EnemySpawnConfig {
            enemy_type = .BOSS_CHROME_ORB,
            count = 1,
            min_spawn_delay = 1.0,
            max_spawn_delay = 1.0,
        },
        stages = make([]shared.StageDefinition, 8),
    };

    // Wave 1: Grunts (Tutorial)
    shared.game_levels[0].stages[0] = shared.StageDefinition{ enemy_configs = make([]shared.EnemySpawnConfig, 1) }
    shared.game_levels[0].stages[0].enemy_configs[0] = { enemy_type = .GRUNT, count = 3, min_spawn_delay = 1.0, max_spawn_delay = 2.0 }

    // Wave 2: Grunts (Tutorial)
    shared.game_levels[0].stages[1] = shared.StageDefinition{ enemy_configs = make([]shared.EnemySpawnConfig, 1) }
    shared.game_levels[0].stages[1].enemy_configs[0] = { enemy_type = .GRUNT, count = 5, min_spawn_delay = 0.8, max_spawn_delay = 1.5 }

    // Wave 3: Grunts + Weavers
    shared.game_levels[0].stages[2] = shared.StageDefinition{ enemy_configs = make([]shared.EnemySpawnConfig, 2) }
    shared.game_levels[0].stages[2].enemy_configs[0] = { enemy_type = .GRUNT, count = 5, min_spawn_delay = 1.0, max_spawn_delay = 2.0 }
    shared.game_levels[0].stages[2].enemy_configs[1] = { enemy_type = .WEAVER, count = 2, min_spawn_delay = 2.0, max_spawn_delay = 4.0 }

    // Wave 4: Grunts + Weavers
    shared.game_levels[0].stages[3] = shared.StageDefinition{ enemy_configs = make([]shared.EnemySpawnConfig, 2) }
    shared.game_levels[0].stages[3].enemy_configs[0] = { enemy_type = .GRUNT, count = 6, min_spawn_delay = 0.8, max_spawn_delay = 1.5 }
    shared.game_levels[0].stages[3].enemy_configs[1] = { enemy_type = .WEAVER, count = 4, min_spawn_delay = 1.5, max_spawn_delay = 3.0 }

    // Wave 5: Gravitron + Mix
    shared.game_levels[0].stages[4] = shared.StageDefinition{ enemy_configs = make([]shared.EnemySpawnConfig, 2) }
    shared.game_levels[0].stages[4].enemy_configs[0] = { enemy_type = .GRAVITRON, count = 1, min_spawn_delay = 1.0, max_spawn_delay = 1.0 }
    shared.game_levels[0].stages[4].enemy_configs[1] = { enemy_type = .GRUNT, count = 8, min_spawn_delay = 0.5, max_spawn_delay = 1.2 }

    // Wave 6: Gravitron + Mix
    shared.game_levels[0].stages[5] = shared.StageDefinition{ enemy_configs = make([]shared.EnemySpawnConfig, 3) }
    shared.game_levels[0].stages[5].enemy_configs[0] = { enemy_type = .GRAVITRON, count = 2, min_spawn_delay = 2.0, max_spawn_delay = 5.0 }
    shared.game_levels[0].stages[5].enemy_configs[1] = { enemy_type = .WEAVER, count = 4, min_spawn_delay = 1.0, max_spawn_delay = 3.0 }
    shared.game_levels[0].stages[5].enemy_configs[2] = { enemy_type = .SLOWBOY, count = 2, min_spawn_delay = 3.0, max_spawn_delay = 6.0 }

    // Wave 7: Tracer Swarm (Elite)
    shared.game_levels[0].stages[6] = shared.StageDefinition{ enemy_configs = make([]shared.EnemySpawnConfig, 1) }
    shared.game_levels[0].stages[6].enemy_configs[0] = { enemy_type = .TRACER, count = 15, min_spawn_delay = 0.2, max_spawn_delay = 0.6 }

    // Wave 8: Boss Chrome Orb
    shared.game_levels[0].stages[7] = shared.StageDefinition{ enemy_configs = make([]shared.EnemySpawnConfig, 1) }
    shared.game_levels[0].stages[7].enemy_configs[0] = shared.game_levels[0].boss_config;

    fmt.printf("--- Level Definitions Initialized: %d levels ---\n", len(shared.game_levels));
    if len(shared.game_levels) > 0 {
        fmt.printf("    Level 0 Stages: %d\n", len(shared.game_levels[0].stages));
        if len(shared.game_levels[0].stages) > 0 {
             fmt.printf("        Stage 0 Enemy Configs: %d (counts: %d)\n", len(shared.game_levels[0].stages[0].enemy_configs), shared.game_levels[0].stages[0].enemy_configs[0].count);
             if len(shared.game_levels[0].stages[1].enemy_configs) > 1 {
                 fmt.printf("        Stage 1 Enemy Configs: %d (counts: %d, %d)\n", len(shared.game_levels[0].stages[1].enemy_configs), shared.game_levels[0].stages[1].enemy_configs[0].count, shared.game_levels[0].stages[1].enemy_configs[1].count);
             }
             fmt.printf("        Stage 2 (Boss) Enemy Configs: %d (counts: %d)\n", len(shared.game_levels[0].stages[2].enemy_configs), shared.game_levels[0].stages[2].enemy_configs[0].count);
        }
    }
    // --- End Level Definitions Initialization ---

    // --- Initialize Game Progression State ---
    shared.random_generator_progression_seed = u64(sapp.frame_count()) + 12345; // Add some variance
    shared.random_generator_progression = rand.create(shared.random_generator_progression_seed);
    fmt.printf("Initialized progression RNG (random_generator_progression) with seed: %d\n", shared.random_generator_progression_seed);
    
    projectile.load_and_initialize_stage_progression(0, 0); // Load Level 0, Stage 0
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

    shared.state.player_invulnerable_timer = math.max(0.0, shared.state.player_invulnerable_timer - delta_time_f);
    shared.state.rmb_cooldown_timer = math.max(0.0, shared.state.rmb_cooldown_timer - delta_time_f)
    shared.state.lmb_cooldown_timer = math.max(0.0, shared.state.lmb_cooldown_timer - delta_time_f)
    shared.state.dash_timer = math.max(0.0, shared.state.dash_timer - delta_time_f);       // <<< NEW
    shared.state.dash_cooldown_timer = math.max(0.0, shared.state.dash_cooldown_timer - delta_time_f); // <<< NEW

    // --- WAVE DIRECTOR LOGIC START ---
    if shared.state.game_state == .Playing {
        // Check if level is complete (basic check for now, can be expanded)
        all_enemies_spawned_wd := shared.state.progression.active_stage.all_enemies_for_stage_spawned
        all_enemies_dead_wd := (shared.state.num_active_enemies == 0)

        if all_enemies_spawned_wd && all_enemies_dead_wd {
            shared.state.wave_transition_timer += delta_time_f
            if shared.state.wave_transition_timer >= 3.0 {
                // Wave Complete
                shared.state.wave_transition_timer = 0.0
                shared.state.surge_node.active = true // Spawn SurgeNode visual
                shared.state.surge_node.pos = {0,0} // Center screen
                shared.state.game_state = .LevelUp // Pause spawning, wait for interaction
            }
        }
    } else if shared.state.game_state == .LevelUp {
        // Wait for player interaction (using SPACE for now) to advance
        if shared.state.key_shift_down { // Using SHIFT as generic "Interact" for now since space isn't tracked in global struct explicitly named space
             // Advance Stage
             // Check if there are more stages in this level
             current_lvl_idx := shared.state.progression.current_level_index
             if current_lvl_idx < len(shared.game_levels) {
                next_stage_idx := shared.state.progression.current_stage_index + 1
                if next_stage_idx < len(shared.game_levels[current_lvl_idx].stages) {
                    projectile.load_and_initialize_stage_progression(current_lvl_idx, next_stage_idx)
                    shared.state.game_state = .Playing // Resume playing
                    shared.state.surge_node.active = false // Hide node
                } else {
                    // Level Complete! (Loop back to 0 or End Game)
                    fmt.printf("LEVEL COMPLETE! Looping to start.\n")
                    projectile.load_and_initialize_stage_progression(0, 0)
                    shared.state.game_state = .Playing
                    shared.state.surge_node.active = false
                }
             }
        }
    } else if shared.state.game_state == .GameOver {
        if shared.state.key_w_down { // Pressing 'W' (or any key really, but let's say R is better, using existing key state for now)
             // Reset Game
             // We need to implement a reset_game() proc, but for now just basic reset variables
             shared.state.player_hp = shared.state.player_max_hp
             shared.state.num_active_enemies = 0
             shared.state.num_active_particles = 0
             shared.state.num_active_blackholes = 0
             shared.state.player_pos = {0,0}
             shared.state.player_vel = {0,0}
             projectile.load_and_initialize_stage_progression(0, 0)
             shared.state.game_state = .Playing
             shared.state.player_defeated_message_shown = false
        }
    }
    // --- WAVE DIRECTOR LOGIC END ---

    if shared.state.player_hp <= 0 {
        shared.state.game_state = .GameOver
        if !shared.state.player_defeated_message_shown {
            fmt.printf("!!! GAME OVER !!! PRESS R (mapped to W for now in code) TO RESTART\n")
            shared.state.player_defeated_message_shown = true
        }
    }

    player.update_player(delta_time_f)

    // Define bounce boundary variables using the calculated orthographic width
    bounce_min_x_f : f32 = -current_ortho_width_for_bounds_f + PLAYER_CORE_WORLD_RADIUS;
    bounce_max_x_f : f32 =  current_ortho_width_for_bounds_f - PLAYER_CORE_WORLD_RADIUS;
    bounce_min_y_f : f32 = -ORTHO_HEIGHT + PLAYER_CORE_WORLD_RADIUS;
    bounce_max_y_f : f32 =  ORTHO_HEIGHT - PLAYER_CORE_WORLD_RADIUS;

    if shared.state.player_pos.x < bounce_min_x_f { shared.state.player_pos.x = bounce_min_x_f; if shared.state.player_vel.x < 0 { shared.state.player_vel.x *= -PLAYER_BOUNCE_DAMPING_FACTOR }}
    else if shared.state.player_pos.x > bounce_max_x_f { shared.state.player_pos.x = bounce_max_x_f; if shared.state.player_vel.x > 0 { shared.state.player_vel.x *= -PLAYER_BOUNCE_DAMPING_FACTOR }}
    if shared.state.player_pos.y < bounce_min_y_f { shared.state.player_pos.y = bounce_min_y_f; if shared.state.player_vel.y < 0 { shared.state.player_vel.y *= -PLAYER_BOUNCE_DAMPING_FACTOR }}
    else if shared.state.player_pos.y > bounce_max_y_f { shared.state.player_pos.y = bounce_max_y_f; if shared.state.player_vel.y > 0 { shared.state.player_vel.y *= -PLAYER_BOUNCE_DAMPING_FACTOR }}
    
    projectile.handle_enemy_spawning(delta_time_f, aspect_f)

    shared.state.num_active_particles = particle.update_and_instance_particles(delta_time_f);
    shared.state.num_active_enemies = enemy.update_and_instance_enemies(delta_time_f);
    shared.state.num_active_blackholes = particle.update_and_instance_blackholes(delta_time_f); // Assuming particle module handles this or blackhole module

    collision.check_LMB_projectile_enemy_collisions();
    collision.check_RMB_particle_enemy_collisions();
    player.check_player_enemy_collisions();
    // collision.check_player_boss_laser_collision(); // Assuming this was in collision module or similar

    projectile.update_progression()

    shared.state.bg_fs_params={tick=current_time_f, resolution={width_f,height_f}, bg_option=1};
    shared.state.player_fs_params={
        tick=current_time_f, resolution={width_f,height_f}, player_hp_uniform=f32(shared.state.player_hp),
        player_max_hp_uniform=f32(shared.state.player_max_hp), player_invulnerable_timer_uniform = shared.state.player_invulnerable_timer,
        player_invulnerability_duration_uniform = PLAYER_INVULNERABILITY_DURATION,
    }; 
    shared.state.particle_fs_params={tick=current_time_f};
    shared.state.enemy_fs_params={tick=current_time_f};
    shared.state.blackhole_fs_params={tick=current_time_f};

    ortho_width_vp_f := ORTHO_HEIGHT*aspect_f; // Renamed
    proj_f := m.ortho(-ortho_width_vp_f,ortho_width_vp_f,-ORTHO_HEIGHT,ORTHO_HEIGHT,-1.0,1.0); // Renamed
    view_f := m.identity(); view_proj_f := m.mul(proj_f,view_f); // Renamed
    
    scale_mat_f := m.scale(m.vec3{PLAYER_SCALE,PLAYER_SCALE,1.0}); // Renamed
    translate_mat_f := m.translate(m.vec3{shared.state.player_pos.x,shared.state.player_pos.y,0.0}); // Renamed
    model_f := m.mul(translate_mat_f,scale_mat_f); // Renamed
    shared.state.player_vs_params.mvp=m.mul(view_proj_f,model_f);
    
    shared.state.particle_vs_params.view_proj=view_proj_f;
    shared.state.enemy_vs_params.view_proj=view_proj_f;
    shared.state.blackhole_vs_params.view_proj=view_proj_f;


    sg.begin_pass({action=shared.state.pass_action, swapchain=sglue.swapchain() });
    sg.apply_pipeline(shared.state.bg_pip); sg.apply_bindings(shared.state.bind); sg.apply_uniforms(UB_bg_fs_params, sg.Range{ptr=&shared.state.bg_fs_params, size=size_of(shared.Bg_Fs_Params)}); sg.draw(0,4,1);
    sg.apply_pipeline(shared.state.player_pip); sg.apply_bindings(shared.state.bind); sg.apply_uniforms(UB_Player_Vs_Params, sg.Range{ptr=&shared.state.player_vs_params, size=size_of(shared.Player_Vs_Params)}); sg.apply_uniforms(UB_Player_Fs_Params, sg.Range{ptr=&shared.state.player_fs_params, size=size_of(shared.Player_Fs_Params)}); sg.draw(0,4,1);
    
    if shared.state.num_active_particles > 0 {
        sg.apply_pipeline(shared.state.particle_pip); sg.apply_bindings(shared.state.particle_bind); sg.update_buffer(shared.state.particle_instance_vbo, sg.Range{ptr=rawptr(&shared.state.particle_instance_data[0]), size=uint(shared.state.num_active_particles)*size_of(shared.Particle_Instance_Data)});
        sg.apply_uniforms(UB_particle_vs_params, sg.Range{ptr=&shared.state.particle_vs_params, size=size_of(shared.Particle_Vs_Params)}); sg.apply_uniforms(UB_particle_fs_params, sg.Range{ptr=&shared.state.particle_fs_params, size=size_of(shared.Particle_Fs_Params)});
        sg.draw(0, 4, shared.state.num_active_particles);
    }
    if shared.state.num_active_blackholes > 0 {
        sg.apply_pipeline(shared.state.blackhole_pip); sg.apply_bindings(shared.state.blackhole_bind);
        sg.update_buffer(shared.state.blackhole_instance_vbo, sg.Range{ptr=rawptr(&shared.state.blackhole_instance_data[0]), size=uint(shared.state.num_active_blackholes)*size_of(shared.Blackhole_Instance_Data)});
        sg.apply_uniforms(UB_blackhole_vs_params, sg.Range{ptr=&shared.state.blackhole_vs_params, size=size_of(shared.Blackhole_Vs_Params)});
        sg.apply_uniforms(UB_blackhole_fs_params, sg.Range{ptr=&shared.state.blackhole_fs_params, size=size_of(shared.Blackhole_Fs_Params)});
        sg.draw(0, 4, shared.state.num_active_blackholes);
    }
    if shared.state.num_active_enemies > 0 {
        sg.apply_pipeline(shared.state.enemy_pip); sg.apply_bindings(shared.state.enemy_bind);
        sg.update_buffer(shared.state.enemy_instance_vbo, sg.Range{ptr=rawptr(&shared.state.enemy_instance_data[0]), size=uint(shared.state.num_active_enemies)*size_of(shared.Enemy_Instance_Data)})
        sg.apply_uniforms(UB_enemy_vs_params, sg.Range{ptr=&shared.state.enemy_vs_params, size=size_of(shared.Enemy_Vs_Params)})
        sg.apply_uniforms(UB_enemy_fs_params, sg.Range{ptr=&shared.state.enemy_fs_params, size=size_of(shared.Enemy_Fs_Params)})
        sg.draw(0, 4, shared.state.num_active_enemies)
    }

    // --- UI Pass (DebugText) ---
    if shared.state.game_state == .GameOver {
        sdtx.canvas(width_f, height_f)
        sdtx.origin(width_f * 0.5 - 100, height_f * 0.5) // Roughly center
        sdtx.color3b(255, 50, 50)
        sdtx.puts("GAME OVER\nPRESS R TO RESTART") // Using R in text, though code listens to W/Shift for now
        sdtx.draw()
    } else if shared.state.game_state == .LevelUp {
        sdtx.canvas(width_f, height_f)
        sdtx.origin(width_f * 0.5 - 120, height_f * 0.5)
        sdtx.color3b(50, 255, 50)
        sdtx.puts("WAVE COMPLETE\nPRESS SHIFT TO CONTINUE")
        sdtx.draw()
    }

    sg.end_pass(); sg.commit();
}


cleanup :: proc "c" () { 
    context=runtime.default_context(); 
    
    ma.sound_uninit(&shared.state.lmb_sound); fmt.printf("--- Miniaudio lmb_sound uninitialized ---\n")
    ma.audio_buffer_uninit(&audio.lmb_sound_audio_buffer); fmt.printf("--- Miniaudio lmb_sound_audio_buffer uninitialized ---\n")

    ma.audio_buffer_uninit(&audio.rmb_hum_audio_buffer); fmt.printf("--- RMB Hum global audio_buffer uninitialized ---\n")
    ma.audio_buffer_uninit(&audio.rmb_whoosh_audio_buffer); fmt.printf("--- RMB Whoosh global audio_buffer uninitialized ---\n")

    ma.audio_buffer_uninit(&audio.enemy_hit_sound_audio_buffer); fmt.printf("--- Enemy Hit audio_buffer uninitialized ---\n")
    ma.audio_buffer_uninit(&audio.enemy_death_sound_audio_buffer); fmt.printf("--- Enemy Death audio_buffer uninitialized ---\n")

    ma.audio_buffer_uninit(&audio.lmb_hit_whoosh_audio_buffer); fmt.printf("--- LMB Hit Whoosh audio_buffer uninitialized ---\n")
    ma.audio_buffer_uninit(&audio.lmb_kill_explosion_audio_buffer); fmt.printf("--- LMB Kill Explosion audio_buffer uninitialized ---\n")
    
    delete(audio.drum_track_pcm_data); fmt.printf("--- Drum track PCM data slice deleted ---\n");
    ma.audio_buffer_uninit(&audio.drum_track_audio_buffer); fmt.printf("--- Drum Track audio_buffer uninitialized ---\n");

    // (<<< NEW SYNTH CLEANUP START >>>)
    delete(audio.synth_track_pcm_data); fmt.printf("--- Synth track PCM data slice deleted ---\n");
    ma.audio_buffer_uninit(&audio.synth_track_audio_buffer); fmt.printf("--- Synth Track audio_buffer uninitialized ---\n");
    // (<<< NEW SYNTH CLEANUP END >>>)

    ma.sound_uninit(&shared.state.lmb_hit_sound); fmt.printf("--- Miniaudio lmb_hit_sound uninitialized ---\n");
    ma.sound_uninit(&shared.state.lmb_kill_sound); fmt.printf("--- Miniaudio lmb_kill_sound uninitialized ---\n");
    ma.sound_uninit(&shared.state.rmb_hit_sound); fmt.printf("--- Miniaudio rmb_hit_sound uninitialized ---\n");
    ma.sound_uninit(&shared.state.rmb_kill_sound); fmt.printf("--- Miniaudio rmb_kill_sound uninitialized ---\n");
    ma.sound_uninit(&shared.state.drum_track_sound); fmt.printf("--- Miniaudio drum_track_sound uninitialized ---\n");
    ma.sound_uninit(&shared.state.synth_track_sound); fmt.printf("--- Miniaudio synth_track_sound uninitialized ---\n"); // <<< NEW

    ma.engine_uninit(&shared.state.audio_engine); fmt.printf("--- Miniaudio engine uninitialized ---\n")
    if sa.isvalid() { sa.shutdown(); fmt.printf("--- Sokol Audio shutdown ---\n") }
    sg.shutdown(); 
}
main :: proc () { sapp.run({ init_cb=init, frame_cb=frame, cleanup_cb=cleanup, event_cb=event, width=800, height=600, sample_count=4, window_title="GeoWars Odin - Synth Track", icon={sokol_default=true}, logger={func=slog.func} }) }
