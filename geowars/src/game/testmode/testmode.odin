package testmode

// TEST-mode debug input + arena reset. Only active when shared.state.game_mode == .TEST,
// entered via the `--test-stage` CLI flag. Used by the screenshot harness in tools/.
//
// Spawn keys (held modifiers select tier):
//   1 → grunt        (Shift+1 silver, Ctrl+1 gold)
//   2 → slowboy      (Shift+2 silver, Ctrl+2 gold)
//   3 → splitter     (Shift+3 silver, Ctrl+3 gold)
//   4 → sniper       (Shift+4 silver, Ctrl+4 gold)
//   5 → disruptor
//   6 → boss (chrome orb)
//   R → clear arena and refill HP

import "base:runtime"
import "core:fmt"
import sapp "../../vendor/sokol/app"
import shared "../../shared"
import enemy "../enemy"

handle_test_input :: proc(event: ^sapp.Event) {
    if shared.state.game_mode != .TEST { return }
    if event.type != .KEY_DOWN { return }

    tier := 0
    if shared.state.key_shift_down { tier = shared.ELITE_TIER_SILVER }
    if shared.state.key_ctrl_down  { tier = shared.ELITE_TIER_GOLD }

    #partial switch event.key_code {
    case ._1: spawn_test(.GRUNT,    tier)
    case ._2: spawn_test(.SLOWBOY,  tier)
    case ._3: spawn_test(.SPLITTER, tier)
    case ._4: spawn_test(.SNIPER,   tier)
    case ._5: spawn_test(.DISRUPTOR, 0) // disruptor doesn't use elite tiers
    case ._6: spawn_test(.BOSS_CHROME_ORB, 0)
    case .R:  reset_arena()
    case ._7: set_hp(3)
    case ._8: set_hp(2)
    case ._9: set_hp(1)
    case ._0: set_hp(shared.state.player_max_hp) // refill
    }
}

@(private)
set_hp :: proc(hp: int) {
    context = runtime.default_context()
    shared.state.player_hp = hp
    shared.state.player_invulnerable_timer = 0.0
    fmt.printf("[TEST] player_hp = %d\n", hp)
}

spawn_test :: proc(t: shared.EnemyType, tier: int) {
    context = runtime.default_context()
    enemy.spawn_enemy_tiered(0, 0, shared.state.player_pos, t, tier)

    // The production spawner always picks a perimeter point, which lands the enemy off-camera
    // in test mode and forces the harness to wait several seconds for the approach. Teleport
    // non-boss spawns into the player's right-hand neighbourhood so they're visible from t=0.
    if t != .BOSS_CHROME_ORB {
        last_idx := (shared.state.next_enemy_index - 1 + shared.MAX_ENEMIES) % shared.MAX_ENEMIES
        e := &shared.state.enemies[last_idx]
        if e.active {
            e.pos = shared.state.player_pos + {0.9, 0.0}
        }
    }

    tier_label := "normal"
    if tier == shared.ELITE_TIER_SILVER { tier_label = "silver" }
    if tier == shared.ELITE_TIER_GOLD   { tier_label = "gold"   }
    fmt.printf("[TEST] spawned %v (%s)\n", t, tier_label)
}

// Despawn every entity and refill the player so the next test scenario starts from a known state.
reset_arena :: proc() {
    context = runtime.default_context()
    for i in 0..<shared.MAX_ENEMIES    { shared.state.enemies[i].active   = false }
    for i in 0..<shared.MAX_BLACKHOLES { shared.state.blackholes[i].active = false }
    for i in 0..<shared.MAX_PARTICLES  { shared.state.particles[i].active  = false }
    shared.state.player_hp = shared.state.player_max_hp
    shared.state.player_invulnerable_timer = 0.0
    shared.state.player_defeated_message_shown = false
    shared.state.player_pos = {0, 0}
    shared.state.player_vel = {0, 0}
    shared.state.camera_pos = {0, 0}
    fmt.printf("[TEST] arena reset\n")
}
