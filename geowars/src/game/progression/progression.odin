package progression
import "core:fmt"
import "core:math"
import "base:runtime"
import rand "core:math/rand"
import shared "../../shared"
import enemy "../enemy"
import shop "../shop"
import m "../../vendor/math"


// --- Wave System ---
// Player presses F at the arena-centre button to enqueue the next wave. Multiple waves can be
// active at once; each wave's directives spawn enemies on staggered timers. Boss spawns when
// all 10 waves are spawned AND no non-boss enemies remain alive.

handle_wave_button_input :: proc(dt: f32) {
    context = runtime.default_context()
    ws := &shared.state.wave_system

    if ws.button_press_cooldown > 0.0 { ws.button_press_cooldown -= dt }
    ws.button_press_flash = math.max(ws.button_press_flash - shared.WAVE_BUTTON_FLASH_DECAY * dt, f32(0.0))

    edge_press := shared.state.key_f_down && !shared.state.key_f_was_down
    shared.state.key_f_was_down = shared.state.key_f_down

    if !edge_press { return }
    if ws.button_press_cooldown > 0.0 { return }
    if ws.next_wave_to_press >= shared.WAVE_BUTTON_TOTAL_WAVES { return }
    if shared.state.player_hp <= 0 { return }

    if m.len_sq_vec2(shared.state.player_pos) > shared.WAVE_BUTTON_PRESS_RANGE * shared.WAVE_BUTTON_PRESS_RANGE {
        return
    }

    activate_wave(ws.next_wave_to_press)
    ws.next_wave_to_press += 1
    ws.button_press_cooldown = shared.WAVE_BUTTON_PRESS_COOLDOWN
    ws.button_press_flash = 1.0
    fmt.printf("--- Player pressed wave button. Wave %d/%d activated. ---\n",
               ws.next_wave_to_press, shared.WAVE_BUTTON_TOTAL_WAVES)
}

activate_wave :: proc(wave_index: int) {
    context = runtime.default_context()
    if wave_index < 0 || wave_index >= shared.WAVE_BUTTON_TOTAL_WAVES { return }
    if len(shared.game_levels) == 0 { return }

    level := &shared.game_levels[0]
    wave_def := &level.waves[wave_index]

    aw := shared.ActiveWave { wave_index = wave_index, all_spawned = len(wave_def.directives) == 0 }
    for d, idx in wave_def.directives {
        state := shared.ActiveWaveDirective {
            directive_index = idx,
            timer           = d.initial_delay,
            remaining       = d.count,
            waiting_initial = d.initial_delay > 0.0,
            // Directives without a wait-gate start ticking immediately. A gated directive parks
            // until advance_active_waves sees the arena go quiet.
            started         = !d.wait_for_arena_clear,
        }
        append(&aw.directive_states, state)
    }
    append(&shared.state.wave_system.active_waves, aw)
}

advance_active_waves :: proc(dt: f32) {
    context = runtime.default_context()
    ws := &shared.state.wave_system
    if len(shared.game_levels) == 0 { return }
    level := &shared.game_levels[0]

    // Used by wait_for_arena_clear directives below. We compute it once per frame.
    arena_quiet := true
    for i in 0..<shared.MAX_ENEMIES {
        e := &shared.state.enemies[i]
        if !e.active || e.is_dying { continue }
        if e.type == .BOSS_CHROME_ORB { continue }
        arena_quiet = false; break
    }

    for &aw in &ws.active_waves {
        if aw.all_spawned { continue }
        wave_def := &level.waves[aw.wave_index]

        all_done := true
        for &dstate in &aw.directive_states {
            if dstate.remaining <= 0 { continue }
            all_done = false

            // Directive may be parked behind a wait_for_arena_clear gate (e.g. the gold spawn
            // in wave 10 only triggers once the silver is dead).
            if !dstate.started {
                if !arena_quiet { continue }
                dstate.started = true
            }

            dstate.timer -= dt
            if dstate.timer > 0.0 { continue }

            d := &wave_def.directives[dstate.directive_index]
            type_to_spawn := d.enemy_type
            if d.randomize_non_disruptor {
                type_to_spawn = enemy.random_non_disruptor()
            }
            enemy.spawn_enemy_tiered(0, 0, shared.state.player_pos, type_to_spawn, d.tier)
            dstate.remaining -= 1
            dstate.waiting_initial = false
            if dstate.remaining > 0 {
                dstate.timer = rand.float32_range(d.interval_min, d.interval_max)
            } else {
                dstate.timer = 0.0
            }
        }
        if all_done { aw.all_spawned = true }
    }

    // Compact: drop fully-spawned waves so boss-trigger logic stays simple.
    write := 0
    for read in 0..<len(ws.active_waves) {
        if !ws.active_waves[read].all_spawned {
            if write != read { ws.active_waves[write] = ws.active_waves[read] }
            write += 1
        } else {
            delete(ws.active_waves[read].directive_states)
        }
    }
    resize(&ws.active_waves, write)
}

maybe_trigger_boss :: proc() {
    context = runtime.default_context()
    ws := &shared.state.wave_system
    if ws.boss_triggered { return }
    if shared.state.player_hp <= 0 { return }
    if ws.next_wave_to_press < shared.WAVE_BUTTON_TOTAL_WAVES { return }
    if len(ws.active_waves) > 0 { return }

    live_count := 0
    for i in 0..<shared.MAX_ENEMIES {
        e := &shared.state.enemies[i]
        if !e.active || e.is_dying { continue }
        if e.type == .BOSS_CHROME_ORB { continue }
        live_count += 1
    }
    if live_count > 0 { return }

    if len(shared.game_levels) == 0 { return }
    enemy.spawn_enemy(0, 0, shared.state.player_pos, .BOSS_CHROME_ORB)
    ws.boss_triggered = true
    fmt.printf("--- All %d waves cleared. BOSS spawning! ---\n", shared.WAVE_BUTTON_TOTAL_WAVES)
}

// Open a shop after each multiple of 3 waves cleared — but not while a wave is still spawning
// or any non-boss enemy is alive. The third shop is the pre-boss tier.
maybe_open_shop :: proc() {
    if shared.state.game_mode != .PLAYING { return }
    if shared.state.player_hp <= 0 { return }
    ws := &shared.state.wave_system
    if ws.boss_triggered { return }
    if ws.shops_offered >= 3 { return }

    threshold := (ws.shops_offered + 1) * 3
    if ws.next_wave_to_press < threshold { return }
    if len(ws.active_waves) > 0 { return }

    // No live (non-dying, non-boss) enemy may be on the field.
    for i in 0..<shared.MAX_ENEMIES {
        e := &shared.state.enemies[i]
        if !e.active || e.is_dying { continue }
        if e.type == .BOSS_CHROME_ORB { continue }
        return
    }

    is_pre_boss := ws.shops_offered == 2
    shop.open_shop(is_pre_boss)
}

// Drain disruptor → button presses queued by enemy.disruptor_press_button. Each one acts as
// if the player tapped F: activates the next pending wave and removes a pip from the counter.
process_disruptor_button_presses :: proc() {
    ws := &shared.state.wave_system
    for shared.state.disruptor_button_presses_pending > 0 {
        if ws.next_wave_to_press >= shared.WAVE_BUTTON_TOTAL_WAVES { break }
        activate_wave(ws.next_wave_to_press)
        ws.next_wave_to_press += 1
        ws.button_press_flash = 1.0
        fmt.printf("--- Disruptor advanced wave counter: %d/%d ---\n",
                   ws.next_wave_to_press, shared.WAVE_BUTTON_TOTAL_WAVES)
        shared.state.disruptor_button_presses_pending -= 1
    }
    // If no waves left, drop pending count rather than letting it accumulate.
    shared.state.disruptor_button_presses_pending = 0
}

update_wave_system :: proc(dt: f32) {
    // While a shop is open the world is paused; we skip wave processing entirely so timers
    // and spawn intervals don't tick while the player ponders.
    if shared.state.game_mode == .SHOP { return }
    // TEST mode is the debug spawn arena — no automated waves, no boss, no shop trigger.
    if shared.state.game_mode == .TEST { return }
    handle_wave_button_input(dt)
    process_disruptor_button_presses()
    advance_active_waves(dt)
    maybe_open_shop()
    if shared.state.game_mode == .SHOP { return } // shop just opened — defer boss check
    maybe_trigger_boss()
}

// --- Wave content for level 1 ---
// Difficulty ramp:
//   W1:   boss-first opener (keeps the new score immediately testable from the first press)
//   W2:   grunt intro
//   W3-4: introduce sniper
//   W5-6: introduce splitter + first slowboy
//   W7-8: introduce disruptor (button under threat)
//   W9:   slowboys arrive in force
//   W10:  finale — every enemy type stacked
init_level_1_waves :: proc(level: ^shared.LevelDefinition) {
    // Use named-field literals so optional WaveSpawnDirective fields (tier, randomize_*, etc.)
    // default to their zero values without us having to spell each one out per call.
    grunt :: proc(count: int, initial_delay: f32, interval_min, interval_max: f32) -> shared.WaveSpawnDirective {
        return {enemy_type=.GRUNT, count=count, initial_delay=initial_delay, interval_min=interval_min, interval_max=interval_max}
    }
    slowboy :: proc(count: int, initial_delay: f32, interval_min, interval_max: f32) -> shared.WaveSpawnDirective {
        return {enemy_type=.SLOWBOY, count=count, initial_delay=initial_delay, interval_min=interval_min, interval_max=interval_max}
    }
    splitter :: proc(count: int, initial_delay: f32, interval_min, interval_max: f32) -> shared.WaveSpawnDirective {
        return {enemy_type=.SPLITTER, count=count, initial_delay=initial_delay, interval_min=interval_min, interval_max=interval_max}
    }
    sniper :: proc(count: int, initial_delay: f32, interval_min, interval_max: f32) -> shared.WaveSpawnDirective {
        return {enemy_type=.SNIPER, count=count, initial_delay=initial_delay, interval_min=interval_min, interval_max=interval_max}
    }
    disruptor :: proc(count: int, initial_delay: f32, interval_min, interval_max: f32) -> shared.WaveSpawnDirective {
        return {enemy_type=.DISRUPTOR, count=count, initial_delay=initial_delay, interval_min=interval_min, interval_max=interval_max}
    }
    boss :: proc() -> shared.WaveSpawnDirective {
        return {enemy_type=.BOSS_CHROME_ORB, count=1, initial_delay=0.0, interval_min=0.0, interval_max=0.0}
    }

    // Slice literals in Odin live only as long as the enclosing function's scope, so we must
    // explicitly heap-allocate each wave's directive list.
    level.waves[0].directives = make([]shared.WaveSpawnDirective, 1)
    level.waves[0].directives[0] = boss()

    level.waves[1].directives = make([]shared.WaveSpawnDirective, 1)
    level.waves[1].directives[0] = grunt(7, 0.0, 0.4, 0.7)

    level.waves[2].directives = make([]shared.WaveSpawnDirective, 2)
    level.waves[2].directives[0] = sniper(1, 0.0, 0.0, 0.0)
    level.waves[2].directives[1] = grunt(5, 1.0, 0.6, 1.0)

    level.waves[3].directives = make([]shared.WaveSpawnDirective, 2)
    level.waves[3].directives[0] = sniper(2, 0.0, 0.4, 0.4)
    level.waves[3].directives[1] = grunt(8, 1.0, 0.4, 0.7)

    level.waves[4].directives = make([]shared.WaveSpawnDirective, 3)
    level.waves[4].directives[0] = splitter(1, 0.0, 0.0, 0.0)
    level.waves[4].directives[1] = grunt(5, 1.5, 0.5, 0.9)
    level.waves[4].directives[2] = slowboy(1, 0.0, 0.0, 0.0)

    level.waves[5].directives = make([]shared.WaveSpawnDirective, 3)
    level.waves[5].directives[0] = splitter(2, 0.0, 1.5, 1.5)
    level.waves[5].directives[1] = sniper(1, 1.0, 0.0, 0.0)
    level.waves[5].directives[2] = grunt(7, 0.5, 0.4, 0.7)

    level.waves[6].directives = make([]shared.WaveSpawnDirective, 3)
    level.waves[6].directives[0] = disruptor(2, 0.0, 0.7, 0.7)
    level.waves[6].directives[1] = grunt(6, 0.5, 0.5, 0.8)
    level.waves[6].directives[2] = sniper(1, 1.5, 0.0, 0.0)

    level.waves[7].directives = make([]shared.WaveSpawnDirective, 4)
    level.waves[7].directives[0] = disruptor(3, 0.0, 0.5, 0.5)
    level.waves[7].directives[1] = splitter(2, 1.0, 1.0, 1.5)
    level.waves[7].directives[2] = slowboy(2, 0.5, 1.5, 1.5)
    level.waves[7].directives[3] = grunt(6, 0.0, 0.4, 0.6)

    level.waves[8].directives = make([]shared.WaveSpawnDirective, 4)
    level.waves[8].directives[0] = slowboy(3, 0.0, 0.8, 0.8)
    level.waves[8].directives[1] = sniper(2, 0.5, 0.6, 0.6)
    level.waves[8].directives[2] = splitter(2, 1.0, 1.2, 1.2)
    level.waves[8].directives[3] = grunt(8, 0.0, 0.3, 0.5)

    // Wave 10: elite duel. A silver-tier random enemy spawns first; once it dies, a gold-tier
    // random enemy follows. No disruptors. After the gold dies the boss is triggered.
    level.waves[9].directives = make([]shared.WaveSpawnDirective, 2)
    level.waves[9].directives[0] = shared.WaveSpawnDirective {
        enemy_type = .GRUNT, // overridden by randomize_non_disruptor at spawn time
        count = 1,
        initial_delay = 0.4,
        interval_min  = 0.0,
        interval_max  = 0.0,
        tier = shared.ELITE_TIER_SILVER,
        randomize_non_disruptor = true,
        wait_for_arena_clear    = false,
    }
    level.waves[9].directives[1] = shared.WaveSpawnDirective {
        enemy_type = .GRUNT,
        count = 1,
        initial_delay = 0.6, // small breather between silver dying and gold appearing
        interval_min  = 0.0,
        interval_max  = 0.0,
        tier = shared.ELITE_TIER_GOLD,
        randomize_non_disruptor = true,
        wait_for_arena_clear    = true, // gold gates on silver's death
    }
}

init_progression :: proc() {
    context = runtime.default_context()
    fmt.printf("--- Initialising wave-based progression ---\n")

    if shared.game_levels == nil {
        shared.game_levels = make([]shared.LevelDefinition, 1)
    }
    init_level_1_waves(&shared.game_levels[0])

    shared.state.wave_system.active_waves = make([dynamic]shared.ActiveWave)
    shared.state.wave_system.next_wave_to_press = 0
    shared.state.wave_system.boss_triggered = false
    shared.state.wave_system.button_press_cooldown = 0.0
    shared.state.wave_system.button_press_flash = 0.0
}
