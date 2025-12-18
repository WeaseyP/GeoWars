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
        },
        stages = make([]shared.StageDefinition, 8), // 8 waves as per PROG-04
    }

    // Wave 1: Grunts
    game_levels[0].stages[0] = shared.StageDefinition{
        enemy_configs = make([]shared.EnemySpawnConfig, 1),
    }
    game_levels[0].stages[0].enemy_configs[0] = shared.EnemySpawnConfig {
        enemy_type = .GRUNT, count = 10, min_spawn_delay = 0.5, max_spawn_delay = 1.5,
    }

    // Wave 2: Grunts (More)
    game_levels[0].stages[1] = shared.StageDefinition{
        enemy_configs = make([]shared.EnemySpawnConfig, 1),
    }
    game_levels[0].stages[1].enemy_configs[0] = shared.EnemySpawnConfig {
        enemy_type = .GRUNT, count = 20, min_spawn_delay = 0.3, max_spawn_delay = 1.0,
    }

    // Wave 3: Weavers (Intro)
    game_levels[0].stages[2] = shared.StageDefinition{
        enemy_configs = make([]shared.EnemySpawnConfig, 1),
    }
    game_levels[0].stages[2].enemy_configs[0] = shared.EnemySpawnConfig {
        enemy_type = .WEAVER, count = 10, min_spawn_delay = 1.0, max_spawn_delay = 2.0,
    }

    // Wave 4: Weavers + Grunts
    game_levels[0].stages[3] = shared.StageDefinition{
        enemy_configs = make([]shared.EnemySpawnConfig, 2),
    }
    game_levels[0].stages[3].enemy_configs[0] = shared.EnemySpawnConfig {
        enemy_type = .GRUNT, count = 15, min_spawn_delay = 0.5, max_spawn_delay = 1.5,
    }
    game_levels[0].stages[3].enemy_configs[1] = shared.EnemySpawnConfig {
        enemy_type = .WEAVER, count = 10, min_spawn_delay = 1.5, max_spawn_delay = 2.5,
    }

    // Wave 5: Gravitrons
    game_levels[0].stages[4] = shared.StageDefinition{
        enemy_configs = make([]shared.EnemySpawnConfig, 1),
    }
    game_levels[0].stages[4].enemy_configs[0] = shared.EnemySpawnConfig {
        enemy_type = .GRAVITRON, count = 5, min_spawn_delay = 2.0, max_spawn_delay = 4.0,
    }

    // Wave 6: Gravitrons + Weavers + Grunts
    game_levels[0].stages[5] = shared.StageDefinition{
        enemy_configs = make([]shared.EnemySpawnConfig, 3),
    }
    game_levels[0].stages[5].enemy_configs[0] = shared.EnemySpawnConfig {
        enemy_type = .GRUNT, count = 10, min_spawn_delay = 0.5, max_spawn_delay = 1.0,
    }
    game_levels[0].stages[5].enemy_configs[1] = shared.EnemySpawnConfig {
        enemy_type = .WEAVER, count = 5, min_spawn_delay = 1.5, max_spawn_delay = 3.0,
    }
    game_levels[0].stages[5].enemy_configs[2] = shared.EnemySpawnConfig {
        enemy_type = .GRAVITRON, count = 3, min_spawn_delay = 3.0, max_spawn_delay = 5.0,
    }

    // Wave 7: Elite + Tracer? (User said Elite for W7)
    // Note: User prompt W7: Elite.
    game_levels[0].stages[6] = shared.StageDefinition{
        enemy_configs = make([]shared.EnemySpawnConfig, 1),
    }
    game_levels[0].stages[6].enemy_configs[0] = shared.EnemySpawnConfig {
        enemy_type = .ELITE, count = 3, min_spawn_delay = 2.0, max_spawn_delay = 4.0,
    }

    // Wave 8: Boss
    game_levels[0].stages[7] = shared.StageDefinition{
        enemy_configs = make([]shared.EnemySpawnConfig, 1),
    }
    game_levels[0].stages[7].enemy_configs[0] = game_levels[0].boss_config

    fmt.printf("--- Level Definitions Initialized: %d levels ---\n", len(game_levels))
}
