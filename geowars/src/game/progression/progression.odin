package progression
import "core:fmt"
import "base:runtime"
import rand "core:math/rand"
import shared "../../shared"
import enemy "../enemy"


update_progression :: proc() {
    if shared.state.progression.active_stage.all_enemies_for_stage_spawned &&
       shared.state.progression.enemies_defeated_in_current_stage >= shared.state.progression.total_enemies_defined_for_current_stage &&
       shared.state.player_hp > 0 {

        fmt.printf("Stage %d (Level %d) COMPLETED. Defeated %d / %d enemies.\n",
                   shared.state.progression.current_stage_index, shared.state.progression.current_level_index,
                   shared.state.progression.enemies_defeated_in_current_stage, shared.state.progression.total_enemies_defined_for_current_stage)

        current_level_idx_before_advancement := shared.state.progression.current_level_index
        next_stage_to_load := shared.state.progression.current_stage_index + 1
        next_level_to_load := shared.state.progression.current_level_index

        game_is_now_won := false

        if current_level_idx_before_advancement < len(shared.game_levels) {
            current_level_def := &shared.game_levels[current_level_idx_before_advancement]
            if next_stage_to_load >= len(current_level_def.stages) {
                fmt.printf("Level %d COMPLETED.\n", current_level_idx_before_advancement)
                next_level_to_load = current_level_idx_before_advancement + 1
                next_stage_to_load = 0

                if next_level_to_load >= len(shared.game_levels) {
                    game_is_now_won = true
                }
            }
        } else {
            fmt.printf("ERROR: current_level_index (%d) was already out of bounds of shared.game_levels (%d).\n", current_level_idx_before_advancement, len(shared.game_levels))
            game_is_now_won = true
        }

        if game_is_now_won {
            fmt.printf("--- ALL LEVELS COMPLETED! GAME WON! ---\n")
            shared.state.progression.active_stage.all_enemies_for_stage_spawned = true
            shared.state.progression.enemies_defeated_in_current_stage = shared.state.progression.total_enemies_defined_for_current_stage + 1
        } else {
            fmt.printf("Advancing to Level %d, Stage %d.\n", next_level_to_load, next_stage_to_load)
            load_and_initialize_stage_progression(next_level_to_load, next_stage_to_load)
        }
    }
}

handle_enemy_spawning :: proc(dt: f32, aspect_f: f32) {
    if !shared.state.progression.active_stage.all_enemies_for_stage_spawned && shared.state.player_hp > 0 {
        current_level_def: ^shared.LevelDefinition
        current_stage_def: ^shared.StageDefinition

        if shared.state.progression.current_level_index < len(shared.game_levels) {
            current_level_def = &shared.game_levels[shared.state.progression.current_level_index]
            if shared.state.progression.current_stage_index < len(current_level_def.stages) {
                current_stage_def = &current_level_def.stages[shared.state.progression.current_stage_index]

                all_configs_done_spawning_this_frame := true

                for &spawn_state, idx in &shared.state.progression.active_stage.enemy_spawn_states {
                    if spawn_state.remaining_to_spawn == 0 {
                        continue
                    }

                    all_configs_done_spawning_this_frame = false

                    spawn_state.spawn_timer -= dt

                    if spawn_state.spawn_timer <= 0.0 {
                        if spawn_state.config_index < len(current_stage_def.enemy_configs) {
                            config := &current_stage_def.enemy_configs[spawn_state.config_index]
                            current_ortho_width_for_spawn_f := shared.ORTHO_HEIGHT * aspect_f

                            enemy.spawn_enemy(current_ortho_width_for_spawn_f, shared.ORTHO_HEIGHT, shared.state.player_pos, config.enemy_type)

                            spawn_state.remaining_to_spawn -= 1
                            spawn_state.spawned_count += 1

                            if spawn_state.remaining_to_spawn > 0 {
                                spawn_state.spawn_timer = rand.float32_range(config.min_spawn_delay, config.max_spawn_delay, runtime.default_random_generator(&shared.random_generator_progression))
                            } else {
                                spawn_state.spawn_timer = 0
                            }
                        } else {
                            fmt.printf("ERROR: spawn_state.config_index out of bounds!\n")
                        }
                    }
                }

                if all_configs_done_spawning_this_frame {
                    shared.state.progression.active_stage.all_enemies_for_stage_spawned = true
                    fmt.printf("All enemies for Stage %d Level %d have been spawned.\n", shared.state.progression.current_stage_index, shared.state.progression.current_level_index)
                }

            } else {
                shared.state.progression.active_stage.all_enemies_for_stage_spawned = true
            }
        } else {
            shared.state.progression.active_stage.all_enemies_for_stage_spawned = true
        }
    }
}

load_and_initialize_stage_progression :: proc(level_idx: int, stage_idx: int) {
    context = runtime.default_context()
    fmt.printf("--- Attempting to load Stage: Level %d, Stage %d ---\n", level_idx, stage_idx)

    if level_idx >= len(shared.game_levels) {
        fmt.printf("!!! ERROR: Level index %d is out of bounds (game_levels length: %d).\n", level_idx, len(shared.game_levels))
        shared.state.progression.active_stage.all_enemies_for_stage_spawned = true
        return
    }
    current_level_def := &shared.game_levels[level_idx]

    if stage_idx >= len(current_level_def.stages) {
        fmt.printf("!!! ERROR: Stage index %d is out of bounds for Level %d (stages length: %d).\n", stage_idx, level_idx, len(current_level_def.stages))
        shared.state.progression.active_stage.all_enemies_for_stage_spawned = true
        return
    }
    current_stage_def := &current_level_def.stages[stage_idx]

    shared.state.progression.current_level_index = level_idx
    shared.state.progression.current_stage_index = stage_idx
    shared.state.progression.enemies_defeated_in_current_stage = 0

    clear(&shared.state.progression.active_stage.enemy_spawn_states)

    total_enemies_count_for_stage: int = 0
    if len(current_stage_def.enemy_configs) > 0 {
        for config, config_idx in current_stage_def.enemy_configs {
            spawn_state := shared.ActiveStageEnemySpawnState {
                config_index       = config_idx,
                spawn_timer        = rand.float32_range(config.min_spawn_delay, config.max_spawn_delay, runtime.default_random_generator(&shared.random_generator_progression)),
                spawned_count      = 0,
                remaining_to_spawn = config.count,
            }
            append(&shared.state.progression.active_stage.enemy_spawn_states, spawn_state)
            total_enemies_count_for_stage += config.count
        }
    }

    shared.state.progression.total_enemies_defined_for_current_stage = total_enemies_count_for_stage
    shared.state.progression.active_stage.all_enemies_for_stage_spawned = (len(current_stage_def.enemy_configs) == 0)

    fmt.printf("Loaded Stage: Level %d, Stage %d. Total Enemies: %d. Spawn states: %d. All spawned initially: %t\n",
        level_idx, stage_idx,
        shared.state.progression.total_enemies_defined_for_current_stage,
        len(shared.state.progression.active_stage.enemy_spawn_states),
        shared.state.progression.active_stage.all_enemies_for_stage_spawned)
}
