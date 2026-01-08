package progression

import "core:fmt"
import "base:runtime"
import rand "core:math/rand"
import shared "../../shared"

// Global level definition
game_levels: []shared.LevelDefinition

init_levels :: proc() {
    // --- Initialize Level Definitions ---
    fmt.printf("--- Initializing Level Definitions ---\n")
    game_levels = make([]shared.LevelDefinition, 1)

    // --- Level 1 Definition ---
    game_levels[0] = shared.LevelDefinition{
        boss_config = shared.EnemySpawnConfig {
            enemy_type = .BOSS_CHROME_ORB,
            count = 1,
            min_spawn_delay = 1.0,
            max_spawn_delay = 1.0,
            start_delay = 0.0,
        },
        stages = make([]shared.StageDefinition, 8), // 8 waves as per PROG-04
    }

    // --- Level 0 (Testing Range) ---
    // User Request: 2 of each enemy type, spawning slowly over 30 seconds.
    // Timeline:
    // 0s: Grunt (2)
    // 5s: Slowboy (2)
    // 10s: Weaver (2)
    // 15s: Gravitron (2)
    // 20s: Tracer (2)
    // 25s: Elite (2)
    
    // REWRITE Level 0 Stage 0 to be this Testing Range
    game_levels[0].stages = make([]shared.StageDefinition, 1) // Just 1 stage for testing now, or keep 8 but replace 1st?
    // User said "make the first level a testing range". I will replace Stage 0.
    
    game_levels[0].stages[0] = shared.StageDefinition{
        enemy_configs = make([]shared.EnemySpawnConfig, 6),
    }

    // Grunt starts at 0s
    game_levels[0].stages[0].enemy_configs[0] = shared.EnemySpawnConfig {
        enemy_type = .GRUNT, count = 2, min_spawn_delay = 0.5, max_spawn_delay = 1.0, start_delay = 0.0,
    }
    // Slowboy starts at 5s
    game_levels[0].stages[0].enemy_configs[1] = shared.EnemySpawnConfig {
        enemy_type = .SLOWBOY, count = 2, min_spawn_delay = 0.5, max_spawn_delay = 1.0, start_delay = 5.0,
    }
    // Weaver starts at 10s
    game_levels[0].stages[0].enemy_configs[2] = shared.EnemySpawnConfig {
        enemy_type = .WEAVER, count = 2, min_spawn_delay = 0.5, max_spawn_delay = 1.0, start_delay = 10.0,
    }
    // Gravitron starts at 15s
    game_levels[0].stages[0].enemy_configs[3] = shared.EnemySpawnConfig {
        enemy_type = .GRAVITRON, count = 2, min_spawn_delay = 1.0, max_spawn_delay = 1.5, start_delay = 15.0,
    }
    // Tracer starts at 20s
    game_levels[0].stages[0].enemy_configs[4] = shared.EnemySpawnConfig {
        enemy_type = .TRACER, count = 2, min_spawn_delay = 0.5, max_spawn_delay = 1.0, start_delay = 20.0,
    }
    // Elite starts at 25s
    game_levels[0].stages[0].enemy_configs[5] = shared.EnemySpawnConfig {
        enemy_type = .ELITE, count = 2, min_spawn_delay = 0.5, max_spawn_delay = 1.0, start_delay = 25.0,
    }

    fmt.printf("--- Level Definitions Initialized: %d levels ---\n", len(game_levels))
}
