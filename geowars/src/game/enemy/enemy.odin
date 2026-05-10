package enemy
import m "../../vendor/math"

import "base:runtime"
import "core:fmt"
import rand "core:math/rand"
import "core:math"
import shared "../../shared"
import sapp "../../vendor/sokol/app"


// --- Enemy System ---
emit_enemy :: proc(enemy_data: shared.Enemy) {
    context = runtime.default_context()
    idx_to_write_en := shared.state.next_enemy_index
    shared.state.enemies[idx_to_write_en] = enemy_data
    shared.state.enemies[idx_to_write_en].active = true
    shared.state.next_enemy_index = (shared.state.next_enemy_index + 1) % shared.MAX_ENEMIES
}

// emit_grunt_at_pos emits a fresh GRUNT skipping the perimeter-spawn search. Used by Splitter
// minis (they inherit position + initial burst velocity from their parent).
emit_grunt_at_pos :: proc(pos: m.vec2, vel: m.vec2) {
    context = runtime.default_context()
    color := m.vec4{0.9, 0.1, 0.7, shared.ENEMY_BASE_ALPHA}
    initial_wander_vec := m.angle_to_vec2(rand.float32() * m.TAU)
    enemy_data := shared.Enemy {
        pos = pos, vel = vel, color = color,
        target_size = shared.ENEMY_GRUNT_SCALE,
        current_size = shared.ENEMY_GRUNT_SCALE * shared.ENEMY_INITIAL_SCALE_FACTOR,
        grow_timer = shared.ENEMY_GROW_DURATION * 0.5,   // mini grunts grow in faster
        is_growing = true,
        rotation = rand.float32() * m.TAU,
        angular_vel = (rand.float32() * 2.0 - 1.0) * shared.ENEMY_MAX_ANGULAR_SPEED,
        hp = shared.ENEMY_GRUNT_MAX_HP,
        type = .GRUNT,
        active = false,
        current_wander_vector = initial_wander_vec,
        wander_timer = rand.float32_range(0.0, shared.ENEMY_WANDER_DIRECTION_CHANGE_INTERVAL),
        is_dying = false, dying_timer = 0.0, death_rect_offset = 0.0,
        death_anim_max_duration = shared.GRUNT_DEATH_ANIM_DURATION,
        boss_move_direction = 1.0,
    }
    emit_enemy(enemy_data)
}

// Helper: pick a random non-disruptor enemy type for "elite" wave directives. Used by wave 10.
random_non_disruptor :: proc() -> shared.EnemyType {
    pool := [4]shared.EnemyType{ .GRUNT, .SLOWBOY, .SPLITTER, .SNIPER }
    idx := int(rand.float32() * 4.0)
    if idx < 0 { idx = 0 }
    if idx > 3 { idx = 3 }
    return pool[idx]
}

// Wrapper for callers that don't care about the elite tier (most spawning paths).
spawn_enemy :: proc(current_ortho_width: f32, current_ortho_height: f32, player_pos: m.vec2, type_to_spawn: shared.EnemyType) {
    spawn_enemy_tiered(current_ortho_width, current_ortho_height, player_pos, type_to_spawn, 0)
}

spawn_enemy_tiered :: proc(current_ortho_width: f32, current_ortho_height: f32, player_pos: m.vec2, type_to_spawn: shared.EnemyType, tier: int) {
    context = runtime.default_context()
    start_pos_en: m.vec2
    valid_spawn_found_en := false

    if type_to_spawn == .BOSS_CHROME_ORB {
        boss_start_angle: f32 = -m.PI / 2.0
        start_pos_en = m.vec2{math.cos(boss_start_angle), math.sin(boss_start_angle)} * shared.ENEMY_BOSS_ORBIT_RADIUS
        valid_spawn_found_en = true
    } else {
        for attempt_en in 0..<shared.ENEMY_MAX_SPAWN_ATTEMPTS {
            angle := rand.float32() * m.TAU
            spawn_radius := shared.ARENA_RADIUS * (0.95 + rand.float32() * 0.05)
            start_pos_en = m.vec2{math.cos(angle), math.sin(angle)} * spawn_radius
            dist_sq_to_player_en := m.len_sq_vec2(start_pos_en - player_pos)
            if dist_sq_to_player_en >= shared.ENEMY_MIN_SPAWN_DIST_FROM_PLAYER_SQ { valid_spawn_found_en = true; break }
        }
        if !valid_spawn_found_en {
            angle := rand.float32() * m.TAU
            start_pos_en = m.vec2{math.cos(angle), math.sin(angle)} * shared.ARENA_RADIUS * 0.95
        }
    }

    start_vel_en: m.vec2 = {0.0, 0.0}
    initial_wander_vec := m.angle_to_vec2(rand.float32() * m.TAU)

    target_world_size: f32
    initial_hp: i32
    death_anim_dur: f32
    enemy_color_val: m.vec4
    enemy_angular_vel: f32 = 0.0

    switch type_to_spawn {
        case .GRUNT:
            enemy_color_val = m.vec4{0.9, 0.1, 0.7, shared.ENEMY_BASE_ALPHA}
            target_world_size = shared.ENEMY_GRUNT_SCALE
            initial_hp = shared.ENEMY_GRUNT_MAX_HP
            death_anim_dur = shared.GRUNT_DEATH_ANIM_DURATION
            enemy_angular_vel = (rand.float32() * 2.0 - 1.0) * shared.ENEMY_MAX_ANGULAR_SPEED
        case .SLOWBOY:
            enemy_color_val = m.vec4{0.3, 0.7, 0.9, shared.ENEMY_BASE_ALPHA}
            target_world_size = shared.ENEMY_SLOWBOY_BASE_SCALE
            initial_hp = shared.ENEMY_SLOWBOY_MAX_HP
            death_anim_dur = shared.SLOWBOY_DEATH_ANIM_DURATION
            enemy_angular_vel = 0.0
        case .BOSS_CHROME_ORB:
            enemy_color_val = m.vec4{0.75, 0.75, 0.8, shared.ENEMY_BASE_ALPHA}
            target_world_size = shared.ENEMY_BOSS_CHROME_ORB_SCALE
            initial_hp = shared.ENEMY_BOSS_CHROME_ORB_MAX_HP
            death_anim_dur = shared.BOSS_DEATH_ANIM_DURATION
            enemy_angular_vel = 0.0
        case .SPLITTER:
            enemy_color_val = m.vec4{0.85, 0.55, 0.25, shared.ENEMY_BASE_ALPHA}
            target_world_size = shared.ENEMY_SPLITTER_SCALE
            initial_hp = shared.ENEMY_SPLITTER_MAX_HP
            death_anim_dur = shared.ENEMY_SPLITTER_DEATH_ANIM
            enemy_angular_vel = (rand.float32() * 2.0 - 1.0) * shared.ENEMY_MAX_ANGULAR_SPEED * 0.6
        case .SNIPER:
            enemy_color_val = m.vec4{0.95, 0.25, 0.30, shared.ENEMY_BASE_ALPHA}
            target_world_size = shared.ENEMY_SNIPER_SCALE
            initial_hp = shared.ENEMY_SNIPER_MAX_HP
            death_anim_dur = shared.ENEMY_SNIPER_DEATH_ANIM
            enemy_angular_vel = 0.0
        case .DISRUPTOR:
            enemy_color_val = m.vec4{0.30, 0.95, 0.95, shared.ENEMY_BASE_ALPHA}
            target_world_size = shared.ENEMY_DISRUPTOR_SCALE
            initial_hp = shared.ENEMY_DISRUPTOR_MAX_HP
            death_anim_dur = shared.ENEMY_DISRUPTOR_DEATH_ANIM
            enemy_angular_vel = 0.0
        case:
            fmt.printf("spawn_enemy: ERROR - Unknown type_to_spawn: %v\n", type_to_spawn)
            return
    }

    initial_rotation: f32 = rand.float32() * m.TAU
    initial_boss_angle: f32 = 0.0
    initial_boss_phase: int = 0
    initial_boss_move_dir: f32 = 1.0
    initial_slot_order: [6]int
    if type_to_spawn == .BOSS_CHROME_ORB {
        initial_boss_angle = -m.PI / 2.0
        initial_rotation = math.atan2(-start_pos_en.y, -start_pos_en.x)
        initial_boss_phase = 1
        initial_boss_move_dir = -1.0

        // Fisher-Yates shuffle all 6 slots so the FIRST laser is also at a random angle.
        // Previously slot 0 was hard-coded to 0, which made the first beam always point in
        // the same direction relative to the boss's rotation — a determinism the player can
        // pattern-match. Now every slot is randomised at spawn.
        initial_slot_order = {0, 1, 2, 3, 4, 5}
        for i := 5; i >= 1; i -= 1 {
            j := int(rand.float32() * f32(i + 1))
            if j > i { j = i }
            tmp := initial_slot_order[i]; initial_slot_order[i] = initial_slot_order[j]; initial_slot_order[j] = tmp
        }
        fmt.printf("[BOSS] laser slot order: %v\n", initial_slot_order)
    }

    // --- Apply elite-tier scaling to base stats. Tiers: 0=normal, 1=silver, 2=gold ---
    speed_mult: f32 = 1.0
    dmg_mult:   f32 = 1.0
    hp_mult:    f32 = 1.0
    size_mult:  f32 = 1.0
    if tier == shared.ELITE_TIER_SILVER {
        speed_mult = shared.ELITE_SPEED_MULT_SILVER
        dmg_mult   = shared.ELITE_DMG_MULT_SILVER
        hp_mult    = shared.ELITE_HP_MULT_SILVER
        size_mult  = shared.ELITE_SIZE_MULT_SILVER
        // Silver tint: lift channels toward white-blue, brighten.
        enemy_color_val.r = math.clamp(enemy_color_val.r * 0.6 + 0.55, 0.0, 1.4)
        enemy_color_val.g = math.clamp(enemy_color_val.g * 0.6 + 0.60, 0.0, 1.4)
        enemy_color_val.b = math.clamp(enemy_color_val.b * 0.6 + 0.65, 0.0, 1.4)
    } else if tier == shared.ELITE_TIER_GOLD {
        speed_mult = shared.ELITE_SPEED_MULT_GOLD
        dmg_mult   = shared.ELITE_DMG_MULT_GOLD
        hp_mult    = shared.ELITE_HP_MULT_GOLD
        size_mult  = shared.ELITE_SIZE_MULT_GOLD
        // Gold tint: warm yellow-orange overlay.
        enemy_color_val.r = math.clamp(enemy_color_val.r * 0.4 + 0.85, 0.0, 1.6)
        enemy_color_val.g = math.clamp(enemy_color_val.g * 0.4 + 0.65, 0.0, 1.6)
        enemy_color_val.b = math.clamp(enemy_color_val.b * 0.4 + 0.20, 0.0, 1.4)
    }
    target_world_size *= size_mult
    initial_hp = i32(math.round(f32(initial_hp) * hp_mult))
    if initial_hp < 1 { initial_hp = 1 }

    // Initial AI state per type. Slowboy enters APPROACH; sniper enters IDLE; others irrelevant.
    initial_ai_state: i32 = 0
    initial_ai_timer: f32 = 0.0
    initial_ai_total: f32 = 0.0
    if type_to_spawn == .SLOWBOY {
        initial_ai_state = i32(shared.SlowboyState.APPROACH)
        initial_ai_timer = shared.SLOWBOY_APPROACH_DURATION
        initial_ai_total = shared.SLOWBOY_APPROACH_DURATION
    } else if type_to_spawn == .SNIPER {
        initial_ai_state = i32(shared.SniperState.IDLE)
        // Sniper "faster" elite bonus = aim/cooldown durations divided by speed_mult.
        idle_dur := shared.ENEMY_SNIPER_IDLE_DURATION / speed_mult
        initial_ai_timer = idle_dur
        initial_ai_total = idle_dur
        // Aim toward player at spawn so the telegraph isn't pointing at nothing.
        dir := player_pos - start_pos_en
        if m.len_sq_vec2(dir) > 0.0001 { initial_rotation = math.atan2(dir.y, dir.x) }
    } else if type_to_spawn == .DISRUPTOR {
        // Face toward arena origin (the button it's about to press).
        dir := -start_pos_en
        if m.len_sq_vec2(dir) > 0.0001 { initial_rotation = math.atan2(dir.y, dir.x) }
    }

    enemy_to_spawn := shared.Enemy {
        pos = start_pos_en, vel = start_vel_en, color = enemy_color_val,
        target_size = target_world_size,
        current_size = target_world_size * shared.ENEMY_INITIAL_SCALE_FACTOR,
        grow_timer = shared.ENEMY_GROW_DURATION, is_growing = true,
        rotation = initial_rotation,
        angular_vel = enemy_angular_vel,
        hp = initial_hp, type = type_to_spawn, active = false,
        current_wander_vector = initial_wander_vec,
        wander_timer = rand.float32_range(0.0, shared.ENEMY_WANDER_DIRECTION_CHANGE_INTERVAL),
        is_dying = false, dying_timer = 0.0, death_rect_offset = 0.0,
        death_anim_max_duration = death_anim_dur,
        enemy_tier = i32(tier),
        speed_mult = speed_mult,
        dmg_mult = dmg_mult,
        boss_move_direction = initial_boss_move_dir,
        boss_phase = initial_boss_phase,
        boss_angle = initial_boss_angle,
        boss_roll_angle = 0.0,
        boss_minion_spawn_timer = shared.ENEMY_BOSS_PHASE1_MINION_SPAWN_INTERVAL * 0.5,
        boss_current_laser_length = shared.ENEMY_BOSS_LASER_LENGTH,
        boss_laser_count = 1,
        boss_laser_slot_order = initial_slot_order,
        boss_laser_fade_in_timer = 0.0,
        boss_detection_print_cooldown = 0.0,
        ai_state = initial_ai_state,
        ai_state_timer = initial_ai_timer,
        ai_state_total = initial_ai_total,
        ai_target_pos = {0, 0},
        ai_origin_pos = start_pos_en,
    }

    emit_enemy(enemy_to_spawn)
}

// --- Per-type alive-update helpers (only called when not dying and not growing) ---

@(private)
update_grunt_alive :: proc(e: ^shared.Enemy, dt: f32, player_pos: m.vec2) {
    e.wander_timer -= dt
    if e.wander_timer <= 0.0 {
        e.current_wander_vector = m.angle_to_vec2(rand.float32() * m.TAU)
        e.wander_timer = shared.ENEMY_WANDER_DIRECTION_CHANGE_INTERVAL + rand.float32_range(-0.2, 0.2)
    }
    dir := player_pos - e.pos
    final_dir := dir
    if m.len_sq_vec2(dir) > 0.001 {
        final_dir = m.norm_vec2(dir) + (e.current_wander_vector * shared.ENEMY_WANDER_INFLUENCE)
    }
    if m.len_sq_vec2(final_dir) > 0.00001 {
        e.vel = m.norm_vec2(final_dir) * shared.ENEMY_GRUNT_SPEED * e.speed_mult
    } else { e.vel = m.vec2_zero() }

    // Spin scales with current speed — base spin always present; fast (elite) grunts spin
    // up to 2.5x harder. Pure visual; doesn't affect the AI.
    speed := m.len_vec2(e.vel)
    speed_norm := math.clamp(speed / (shared.ENEMY_GRUNT_SPEED * shared.ELITE_SPEED_MULT_GOLD), 0.0, 1.0)
    e.rotation += e.angular_vel * (1.0 + speed_norm * 1.5) * dt
}

@(private)
update_splitter_alive :: proc(e: ^shared.Enemy, dt: f32, player_pos: m.vec2) {
    e.rotation += e.angular_vel * dt
    e.wander_timer -= dt
    if e.wander_timer <= 0.0 {
        e.current_wander_vector = m.angle_to_vec2(rand.float32() * m.TAU)
        e.wander_timer = shared.ENEMY_WANDER_DIRECTION_CHANGE_INTERVAL + rand.float32_range(-0.2, 0.2)
    }
    dir := player_pos - e.pos
    final_dir := dir
    if m.len_sq_vec2(dir) > 0.001 {
        final_dir = m.norm_vec2(dir) + (e.current_wander_vector * (shared.ENEMY_WANDER_INFLUENCE * 0.5))
    }
    if m.len_sq_vec2(final_dir) > 0.00001 {
        e.vel = m.norm_vec2(final_dir) * shared.ENEMY_SPLITTER_SPEED * e.speed_mult
    } else { e.vel = m.vec2_zero() }
}

@(private)
update_disruptor_alive :: proc(e: ^shared.Enemy, dt: f32) {
    // Beeline straight to (0,0). Rotation always faces motion direction.
    dir := -e.pos
    if m.len_sq_vec2(dir) > 0.0001 {
        norm := m.norm_vec2(dir)
        e.vel = norm * shared.ENEMY_DISRUPTOR_SPEED
        e.rotation = math.atan2(norm.y, norm.x)
    } else {
        e.vel = m.vec2_zero()
    }
    // Spin a bit to feel "alive" / hostile
    e.rotation += dt * 0.0 // (rotation is dictated by direction)
}

// Slowboy state machine. Returns the visual shake offset (for the instance position) and stuffs
// shader effect_params into the supplied pointers.
@(private)
update_slowboy_alive :: proc(e: ^shared.Enemy, dt: f32, player_pos: m.vec2,
                             out_shake_x: ^f32, out_shake_y: ^f32) {
    state := shared.SlowboyState(e.ai_state)

    // Always tick the state timer first
    e.ai_state_timer = math.max(0.0, e.ai_state_timer - dt)

    switch state {
    case .APPROACH:
        // Slow drift toward player, no rotation tracking.
        dir := player_pos - e.pos
        if m.len_sq_vec2(dir) > 0.0001 {
            e.vel = m.norm_vec2(dir) * shared.ENEMY_SLOWBOY_SPEED * e.speed_mult
        } else { e.vel = m.vec2_zero() }
        e.rotation += 0.6 * dt
        if e.ai_state_timer <= 0.0 {
            // Lock onto player and wind up.
            e.ai_state = i32(shared.SlowboyState.WINDUP)
            e.ai_state_timer = shared.SLOWBOY_WINDUP_DURATION
            e.ai_state_total = shared.SLOWBOY_WINDUP_DURATION
            e.ai_target_pos = player_pos
            e.ai_origin_pos = e.pos
            e.vel = {0, 0}
        }
    case .WINDUP:
        e.vel = {0, 0}
        // Shake amplitude ramps from 0 to MAX over the windup duration.
        progress := 1.0 - (e.ai_state_timer / e.ai_state_total)
        if progress < 0.0 { progress = 0.0 }
        if progress > 1.0 { progress = 1.0 }
        amp := progress * shared.SLOWBOY_SHAKE_MAX_AMPL
        // Fast pseudo-random shake. Use tick-derived hash.
        t := f32(sapp.frame_count()) * 0.25
        out_shake_x^ = math.cos(t * 12.7 + e.pos.x * 17.3) * amp
        out_shake_y^ = math.sin(t * 11.3 + e.pos.y * 19.1) * amp
        // Slowly turn toward locked target so player can read direction
        dir := e.ai_target_pos - e.pos
        if m.len_sq_vec2(dir) > 0.0001 {
            target_rot := math.atan2(dir.y, dir.x)
            e.rotation = m.lerp(e.rotation, target_rot, dt * 6.0)
        }
        if e.ai_state_timer <= 0.0 {
            // Charge toward locked position. Compute velocity so that the slowboy traverses
            // exactly SLOWBOY_CHARGE_DISTANCE over SLOWBOY_CHARGE_DURATION along the locked axis.
            charge_dir := e.ai_target_pos - e.pos
            if m.len_sq_vec2(charge_dir) > 0.0001 {
                charge_dir = m.norm_vec2(charge_dir)
            } else { charge_dir = {0, 1} }
            charge_speed := (shared.SLOWBOY_CHARGE_DISTANCE / shared.SLOWBOY_CHARGE_DURATION) * e.speed_mult
            e.vel = charge_dir * charge_speed
            e.ai_state = i32(shared.SlowboyState.CHARGE)
            e.ai_state_timer = shared.SLOWBOY_CHARGE_DURATION
            e.ai_state_total = shared.SLOWBOY_CHARGE_DURATION
            e.ai_origin_pos = e.pos
        }
    case .CHARGE:
        // Vel was set on entry; keep spinning hard.
        e.rotation += shared.SLOWBOY_SPIN_SPEED * dt
        if e.ai_state_timer <= 0.0 {
            e.vel = {0, 0}
            e.ai_state = i32(shared.SlowboyState.RECOVER)
            e.ai_state_timer = shared.SLOWBOY_RECOVER_DURATION
            e.ai_state_total = shared.SLOWBOY_RECOVER_DURATION
        }
    case .RECOVER:
        e.vel = {0, 0}
        e.rotation += 0.3 * dt
        if e.ai_state_timer <= 0.0 {
            e.ai_state = i32(shared.SlowboyState.APPROACH)
            e.ai_state_timer = shared.SLOWBOY_APPROACH_DURATION
            e.ai_state_total = shared.SLOWBOY_APPROACH_DURATION
        }
    }
}

// Sniper state machine. Returns true if a shot was just fired (so the caller can run the
// hitscan damage check in the same frame).
@(private)
update_sniper_alive :: proc(e: ^shared.Enemy, dt: f32, player_pos: m.vec2) -> bool {
    state := shared.SniperState(e.ai_state)
    e.vel = {0, 0}
    e.ai_state_timer = math.max(0.0, e.ai_state_timer - dt)
    fired_this_frame := false

    // Elite snipers cycle through their state machine faster — durations divided by speed_mult.
    aim_dur     := shared.ENEMY_SNIPER_AIM_DURATION / e.speed_mult
    fire_dur    := shared.ENEMY_SNIPER_FIRE_DURATION
    cooldown_dur := shared.ENEMY_SNIPER_COOLDOWN_DURATION / e.speed_mult
    lock_remain := shared.ENEMY_SNIPER_AIM_LOCK_REMAINING / e.speed_mult

    switch state {
    case .IDLE:
        if e.ai_state_timer <= 0.0 {
            e.ai_state = i32(shared.SniperState.AIMING)
            e.ai_state_timer = aim_dur
            e.ai_state_total = aim_dur
        }
    case .AIMING:
        // Track the player until the lock-on threshold; afterwards the targeting angle is fixed.
        if e.ai_state_timer > lock_remain {
            dir := player_pos - e.pos
            if m.len_sq_vec2(dir) > 0.0001 {
                e.rotation = math.atan2(dir.y, dir.x)
                e.ai_target_pos = player_pos
            }
        }
        if e.ai_state_timer <= 0.0 {
            e.ai_state = i32(shared.SniperState.FIRING)
            e.ai_state_timer = fire_dur
            e.ai_state_total = fire_dur
            fired_this_frame = true
        }
    case .FIRING:
        if e.ai_state_timer <= 0.0 {
            e.ai_state = i32(shared.SniperState.COOLDOWN)
            e.ai_state_timer = cooldown_dur
            e.ai_state_total = cooldown_dur
        }
    case .COOLDOWN:
        if e.ai_state_timer <= 0.0 {
            e.ai_state = i32(shared.SniperState.AIMING)
            e.ai_state_timer = aim_dur
            e.ai_state_total = aim_dur
        }
    }
    return fired_this_frame
}

// Run the hitscan check against the player. Called immediately after a sniper transitions into FIRING.
@(private)
sniper_fire_hitscan :: proc(e: ^shared.Enemy) {
    if shared.state.player_hp <= 0 || shared.state.player_invulnerable_timer > 0.0 { return }
    beam_dir := m.vec2{math.cos(e.rotation), math.sin(e.rotation)}
    if m.len_sq_vec2(beam_dir) < 0.0001 { return }
    perp := m.vec2{-beam_dir.y, beam_dir.x}
    rel := shared.state.player_pos - e.pos
    local_y := m.dot_vec2(rel, beam_dir)
    local_x := m.dot_vec2(rel, perp)
    half_w := shared.ENEMY_SNIPER_BEAM_HALF_WIDTH + shared.PLAYER_CORE_WORLD_RADIUS
    if local_y >= 0.0 && local_y <= shared.ENEMY_SNIPER_BEAM_LENGTH && math.abs(local_x) <= half_w {
        dmg := int(math.round(f32(shared.ENEMY_SNIPER_DAMAGE) * e.dmg_mult))
        if dmg < 1 { dmg = 1 }
        shared.state.player_hp -= dmg
        shared.state.player_hp = math.max(shared.state.player_hp, 0)
        shared.state.player_invulnerable_timer = shared.state.eff_invul_duration / 2.0
        fmt.printf("Player hit by SNIPER (tier %d, dmg %d)! HP: %d/%d.\n", e.enemy_tier, dmg, shared.state.player_hp, shared.state.player_max_hp)
    }
}

// Disruptor reached the wave button. Effect = same as a player F-press: queues the next wave
// and removes a notch from the visible counter. Progression sees the pending counter and
// processes it during update_wave_system. (We don't activate the wave here directly to avoid
// importing progression into enemy.)
@(private)
disruptor_press_button :: proc() {
    shared.state.disruptor_button_presses_pending += 1
    shared.state.wave_system.button_press_flash = 1.0
    fmt.printf("--- DISRUPTOR pressed the button! ---\n")
}

// Boss alive update. Pulled out to keep update_and_instance_enemies readable.
@(private)
update_boss_alive :: proc(e: ^shared.Enemy, dt: f32, player_pos: m.vec2,
                          out_effect: ^m.vec4, out_color_r: ^f32, out_color_g: ^f32,
                          out_color_b: ^f32, out_color_a: ^f32) {
    hp_ratio := f32(e.hp) / f32(shared.ENEMY_BOSS_CHROME_ORB_MAX_HP)
    if hp_ratio < 0.0 { hp_ratio = 0.0 }

    if e.boss_phase == 1 {
        if hp_ratio > 0.75 {
            e.boss_move_direction = -1.0
        } else if hp_ratio > 0.5 {
            e.boss_move_direction = 1.0
        } else {
            e.boss_phase = 2
            e.boss_minion_spawn_timer = 1.0
            fmt.printf("--- BOSS entering Phase 2! ---\n")
        }
    }

    target_laser_count := 1
    if e.boss_phase == 2 {
        if      hp_ratio > 0.4 { target_laser_count = 2 }
        else if hp_ratio > 0.3 { target_laser_count = 3 }
        else if hp_ratio > 0.2 { target_laser_count = 4 }
        else if hp_ratio > 0.1 { target_laser_count = 5 }
        else                   { target_laser_count = 6 }
    }
    e.boss_laser_fade_in_timer = math.max(0.0, e.boss_laser_fade_in_timer - dt)
    if e.boss_laser_count < target_laser_count && e.boss_laser_fade_in_timer <= 0.0 {
        e.boss_laser_count += 1
        e.boss_laser_fade_in_timer = 1.0
    }

    orbit_radius := shared.ENEMY_BOSS_ORBIT_RADIUS
    angular_speed := shared.ENEMY_BOSS_ORBIT_SPEED * e.boss_move_direction
    e.boss_current_laser_length = shared.ENEMY_BOSS_LASER_LENGTH
    sweep_speed := shared.ENEMY_BOSS_LASER_SWEEP_SPEED
    if e.boss_phase == 2 { sweep_speed *= shared.ENEMY_BOSS_PHASE2_SWEEP_BOOST }

    e.boss_angle += angular_speed * dt
    if e.boss_angle >  m.TAU { e.boss_angle -= m.TAU }
    if e.boss_angle < -m.TAU { e.boss_angle += m.TAU }
    next_pos := m.vec2{math.cos(e.boss_angle), math.sin(e.boss_angle)} * orbit_radius
    if dt > 0.0001 { e.vel = (next_pos - e.pos) / dt }
    e.pos = next_pos

    e.rotation += sweep_speed * e.boss_move_direction * dt

    if shared.ENEMY_BOSS_VISUAL_RADIUS > 0.0001 {
        e.boss_roll_angle += angular_speed * (orbit_radius / shared.ENEMY_BOSS_VISUAL_RADIUS) * dt
    }
    if e.boss_roll_angle >  m.TAU { e.boss_roll_angle -= m.TAU }
    if e.boss_roll_angle < -m.TAU { e.boss_roll_angle += m.TAU }

    spawn_interval: f32 = shared.ENEMY_BOSS_PHASE1_MINION_SPAWN_INTERVAL
    if e.boss_phase == 2 { spawn_interval = shared.ENEMY_BOSS_PHASE2_MINION_SPAWN_INTERVAL }
    e.boss_minion_spawn_timer -= dt
    if e.boss_minion_spawn_timer <= 0.0 {
        e.boss_minion_spawn_timer = spawn_interval
        aspect := sapp.widthf() / sapp.heightf()
        width := shared.ORTHO_HEIGHT * aspect
        minion_type := shared.EnemyType.GRUNT
        if e.boss_phase == 2 && rand.float32() < shared.ENEMY_BOSS_PHASE2_SLOWBOY_CHANCE {
            minion_type = shared.EnemyType.SLOWBOY
        }
        spawn_enemy(width, shared.ORTHO_HEIGHT, player_pos, minion_type)
    }

    out_color_r^ = hp_ratio
    encoded_slot_order: f32 = 0.0
    slot_factor: f32 = 1.0
    for k in 0..<6 {
        encoded_slot_order += f32(e.boss_laser_slot_order[k]) * slot_factor
        slot_factor *= 6.0
    }
    out_color_g^ = encoded_slot_order
    out_color_b^ = f32(e.boss_laser_count) / 10.0
    out_color_a^ = e.boss_laser_fade_in_timer

    out_effect^ = {0.0, e.boss_roll_angle, e.boss_current_laser_length, f32(e.boss_phase)}
}

update_and_instance_enemies :: proc(dt: f32) -> int {
    context = runtime.default_context()
    live_enemy_count := 0
    player_pos := shared.state.player_pos

    for i in 0..<shared.MAX_ENEMIES {
        if !shared.state.enemies[i].active { continue }
        e := &shared.state.enemies[i]

        // Defaults — overridden per-state below
        effect: m.vec4 = {0.0, 0.0, 1.0, 1.0}
        // Visual position offset (currently only slowboy windup uses this).
        shake_x: f32 = 0.0
        shake_y: f32 = 0.0
        // Color channel overrides for the boss (others use the spawn-time color verbatim).
        color_override := false
        c_r, c_g, c_b, c_a: f32

        if e.is_dying {
            effect.x = 1.0
            effect.y = e.death_rect_offset
            e.dying_timer -= dt
            e.death_rect_offset += shared.ENEMY_DEATH_RECT_SEPARATION_SPEED * dt
            if e.dying_timer <= 0.0 { e.active = false; continue }

            progress: f32 = 0.0
            if e.death_anim_max_duration > 0.0 {
                progress = 1.0 - math.clamp(e.dying_timer / e.death_anim_max_duration, 0.0, 1.0)
            }
            effect.w = 1.0 - progress
            if e.type == .GRUNT {
                eased := math.pow(progress, 2.5)
                effect.z = m.lerp(f32(1.0), shared.ENEMY_DEATH_RECT_FINAL_SCALE_FACTOR, eased)
            } else {
                effect.z = 1.0
            }
            e.current_size = m.lerp(e.target_size, e.target_size * shared.ENEMY_DEATH_RECT_FINAL_SCALE_FACTOR, progress)
        } else if e.is_growing {
            effect = {0.0, 0.0, 1.0, 1.0}
            if e.type == .SLOWBOY { effect.z = shared.ENEMY_SLOWBOY_GLOW_CANVAS_SF }
            else if e.type == .BOSS_CHROME_ORB { effect = {0.0, 0.0, 0.0, 0.0} }

            e.grow_timer -= dt
            if e.grow_timer <= 0.0 {
                e.current_size = e.target_size
                e.is_growing = false
                e.grow_timer = 0.0
                if e.type == .BOSS_CHROME_ORB { e.vel = {0, 0} }
            } else {
                progress := 1.0 - (e.grow_timer / shared.ENEMY_GROW_DURATION)
                progress = math.clamp(progress, 0.0, 1.0)
                init_size := e.target_size * shared.ENEMY_INITIAL_SCALE_FACTOR
                e.current_size = m.lerp(init_size, e.target_size, progress)
            }

            // While growing, simple drift toward player for melee-types; everything else just sits.
            if e.type == .GRUNT || e.type == .SLOWBOY || e.type == .SPLITTER {
                e.rotation += e.angular_vel * dt
                dir := player_pos - e.pos
                speed: f32 = shared.ENEMY_GRUNT_SPEED
                if e.type == .SLOWBOY { speed = shared.ENEMY_SLOWBOY_SPEED }
                else if e.type == .SPLITTER { speed = shared.ENEMY_SPLITTER_SPEED }
                if m.len_sq_vec2(dir) > 0.0001 {
                    e.vel = m.norm_vec2(dir) * speed
                } else { e.vel = m.vec2_zero() }
            } else {
                e.vel = {0, 0}
            }
        } else {
            // Alive
            e.current_size = e.target_size

            switch e.type {
            case .GRUNT:
                update_grunt_alive(e, dt, player_pos)
                // Pack normalized speed into effect.y so the shader can pulse the grunt's
                // body and inner glow with motion. Fast/elite grunts read more menacing.
                grunt_speed := m.len_vec2(e.vel)
                grunt_speed_norm := math.clamp(grunt_speed / (shared.ENEMY_GRUNT_SPEED * shared.ELITE_SPEED_MULT_GOLD), 0.0, 1.0)
                effect = {0.0, grunt_speed_norm, 1.0, 1.0}
            case .SLOWBOY:
                update_slowboy_alive(e, dt, player_pos, &shake_x, &shake_y)
                progress: f32 = 0.0
                if e.ai_state_total > 0.0001 {
                    progress = 1.0 - (e.ai_state_timer / e.ai_state_total)
                    if progress < 0.0 { progress = 0.0 }
                    if progress > 1.0 { progress = 1.0 }
                }
                effect = {0.0, f32(e.ai_state), progress, shared.ENEMY_SLOWBOY_GLOW_CANVAS_SF}
            case .BOSS_CHROME_ORB:
                update_boss_alive(e, dt, player_pos, &effect, &c_r, &c_g, &c_b, &c_a)
                color_override = true
            case .SPLITTER:
                update_splitter_alive(e, dt, player_pos)
                effect = {0.0, 0.0, 1.0, 1.0}
            case .SNIPER:
                fired := update_sniper_alive(e, dt, player_pos)
                if fired { sniper_fire_hitscan(e) }
                progress: f32 = 0.0
                if e.ai_state_total > 0.0001 {
                    progress = 1.0 - (e.ai_state_timer / e.ai_state_total)
                    if progress < 0.0 { progress = 0.0 }
                    if progress > 1.0 { progress = 1.0 }
                }
                effect = {0.0, f32(e.ai_state), progress, 1.0}
            case .DISRUPTOR:
                update_disruptor_alive(e, dt)
                effect = {0.0, 0.0, 1.0, 1.0}
            }
        }

        // Common: integrate position from velocity (boss already wrote pos directly).
        if e.type != .BOSS_CHROME_ORB { e.pos += e.vel * dt }

        // Wrap rotation
        if e.type != .BOSS_CHROME_ORB {
            if e.rotation > m.TAU { e.rotation -= m.TAU }
            if e.rotation < 0    { e.rotation += m.TAU }
        }

        // Disruptor button-impact: trigger and self-destruct
        if !e.is_dying && !e.is_growing && e.type == .DISRUPTOR {
            if m.len_sq_vec2(e.pos) <= shared.ENEMY_DISRUPTOR_BUTTON_PRESS_RANGE * shared.ENEMY_DISRUPTOR_BUTTON_PRESS_RANGE {
                disruptor_press_button()
                e.is_dying = true
                e.dying_timer = shared.ENEMY_DISRUPTOR_DEATH_ANIM
                e.death_anim_max_duration = shared.ENEMY_DISRUPTOR_DEATH_ANIM
                e.death_rect_offset = 0.0
            }
        }

        // Write to instance buffer
        if live_enemy_count < shared.MAX_ENEMIES {
            inst := &shared.state.enemy_instance_data[live_enemy_count]
            inst.instance_pos = e.pos + m.vec2{shake_x, shake_y}
            inst.instance_main_rotation = e.rotation
            if e.type == .BOSS_CHROME_ORB {
                inst.instance_visual_scale = shared.BOSS_QUAD_WORLD_DIAMETER
            } else if e.type == .SNIPER {
                inst.instance_visual_scale = shared.ENEMY_SNIPER_QUAD_WORLD_DIAMETER
            } else {
                inst.instance_visual_scale = e.current_size * shared.ENEMY_SHADER_VISUAL_SCALE_MULTIPLIER
            }
            if color_override {
                inst.instance_color = {c_r, c_g, c_b, c_a}
            } else {
                inst.instance_color = e.color
            }
            inst.instance_effect_params = effect

            switch e.type {
            case .GRUNT:           inst.instance_enemy_type = 0.0
            case .SLOWBOY:         inst.instance_enemy_type = 1.0
            case .BOSS_CHROME_ORB: inst.instance_enemy_type = 2.0
            case .SPLITTER:        inst.instance_enemy_type = 3.0
            case .SNIPER:          inst.instance_enemy_type = 4.0
            case .DISRUPTOR:       inst.instance_enemy_type = 5.0
            }
            live_enemy_count += 1
        }
    }
    return live_enemy_count
}
