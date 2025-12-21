package progression

import "core:fmt"
import "base:runtime"
import rand "core:math/rand"
import sapp "../../vendor/sokol/app"
import shared "../../shared"
import enemy "../../game/enemy"

update_progression :: proc(game_state: ^shared.GameState) {
    if game_state.progression.active_stage.all_enemies_for_stage_spawned &&
       game_state.progression.enemies_defeated_in_current_stage >= game_state.progression.total_enemies_defined_for_current_stage &&
       game_state.player.hp > 0 {

        fmt.printf("Stage %d (Level %d) COMPLETED.\n",
                   game_state.progression.current_stage_index, game_state.progression.current_level_index)

        current_level_idx := game_state.progression.current_level_index
        next_stage := game_state.progression.current_stage_index + 1
        next_level := current_level_idx
        
        game_won := false

        if current_level_idx < len(game_levels) {
            current_def := &game_levels[current_level_idx]
            if next_stage >= len(current_def.stages) {
                fmt.printf("Level %d COMPLETED.\n", current_level_idx)
                next_level = current_level_idx + 1
                next_stage = 0
                if next_level >= len(game_levels) {
                    game_won = true
                }
            }
        } else {
            game_won = true
        }

        if game_won {
            fmt.printf("--- GAME WON! ---\n")
            // Handle win state
            game_state.progression.enemies_defeated_in_current_stage += 1 // Hack to stop re-trigger
        } else {
            load_stage(game_state, next_level, next_stage)
        }
    }
}

handle_enemy_spawning :: proc(game_state: ^shared.GameState, dt: f32) {
    if !game_state.progression.active_stage.all_enemies_for_stage_spawned && game_state.player.hp > 0 {
        current_level_def: ^shared.LevelDefinition
        current_stage_def: ^shared.StageDefinition
        
        if game_state.progression.current_level_index < len(game_levels) {
            current_level_def = &game_levels[game_state.progression.current_level_index]
            if game_state.progression.current_stage_index < len(current_level_def.stages) {
                current_stage_def = &current_level_def.stages[game_state.progression.current_stage_index]

                all_done := true

                // Need to access active_stage.enemy_spawn_states as reference to modify
                // But iterating a dynamic array by reference in Odin is fine
                for i := 0; i < len(game_state.progression.active_stage.enemy_spawn_states); i += 1 {
                    spawn_state := &game_state.progression.active_stage.enemy_spawn_states[i]

                    if spawn_state.remaining_to_spawn == 0 { continue }

                    all_done = false
                    spawn_state.spawn_timer -= dt
                    
                    if spawn_state.spawn_timer <= 0.0 {
                        config := &current_stage_def.enemy_configs[spawn_state.config_index]

                        width := f32(shared.ARENA_WIDTH)
                        height := f32(shared.ARENA_HEIGHT)
                        enemy.spawn_enemy(game_state, width, height, game_state.player.pos, config.enemy_type)

                        spawn_state.remaining_to_spawn -= 1
                        spawn_state.spawned_count += 1

                        if spawn_state.remaining_to_spawn > 0 {
                            // rng needs state
                            spawn_state.spawn_timer = rand.float32_range(config.min_spawn_delay, config.max_spawn_delay)
                        }
                    }
                }
                
                if all_done {
                    game_state.progression.active_stage.all_enemies_for_stage_spawned = true
                    fmt.printf("All enemies spawned.\n")
                }
            }
        }
    }
}

load_stage :: proc(game_state: ^shared.GameState, level_idx: int, stage_idx: int) {
    if level_idx >= len(game_levels) { return }
    level_def := &game_levels[level_idx]
    if stage_idx >= len(level_def.stages) { return }
    stage_def := &level_def.stages[stage_idx]
    
    game_state.progression.current_level_index = level_idx
    game_state.progression.current_stage_index = stage_idx
    game_state.progression.enemies_defeated_in_current_stage = 0
    
    clear(&game_state.progression.active_stage.enemy_spawn_states)

    total_enemies := 0
    for config, idx in stage_def.enemy_configs {
        append(&game_state.progression.active_stage.enemy_spawn_states, shared.ActiveStageEnemySpawnState{
            config_index = idx,
            spawn_timer = config.start_delay + rand.float32_range(config.min_spawn_delay, config.max_spawn_delay),
            remaining_to_spawn = config.count,
        })
        total_enemies += config.count
    }
    
    game_state.progression.total_enemies_defined_for_current_stage = total_enemies
    game_state.progression.active_stage.all_enemies_for_stage_spawned = (total_enemies == 0)
    
    fmt.printf("Loaded Level %d Stage %d\n", level_idx, stage_idx)
}
