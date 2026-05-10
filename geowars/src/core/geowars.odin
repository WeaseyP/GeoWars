package main

import "base:runtime"
import "core:math"
import "core:fmt"
import "core:os"
import "core:time"
import slog "../vendor/sokol/log"
import sg "../vendor/sokol/gfx"
import sapp "../vendor/sokol/app"
import sglue "../vendor/sokol/glue"
import sdtx "../vendor/sokol/debugtext"
import sa "../vendor/sokol/audio"
import m "../vendor/math"
import rand "core:math/rand"

import progression "../game/progression"
import player "../game/player"
import enemy "../game/enemy"
import particle "../game/particle"
import projectile "../game/projectile"
import collision "../game/collision"
import shop "../game/shop"
import testmode "../game/testmode"
import audio "../audio"
import graphics "../graphics"
import shared "../shared"


init :: proc "c" () {
    context = runtime.default_context()
    sg.setup({ pipeline_pool_size=16, buffer_pool_size=16, shader_pool_size=16, environment=sglue.environment(), logger={func=slog.func} })
    fmt.printf("--- Init Start ---\n")

    audio.init_audio()
    graphics.init_rendering()

    // sokol-debugtext for shop labels. Single context, one font (kc854 — readable 8x8 bitmap).
    sdtx_desc: sdtx.Desc
    sdtx_desc.fonts[0] = sdtx.font_kc854()
    sdtx_desc.logger = {func=slog.func}
    sdtx.setup(sdtx_desc)

    shared.state.next_particle_index = 0; shared.state.num_active_particles = 0
    shared.state.next_enemy_index = 0; shared.state.num_active_enemies = 0
    shared.state.next_blackhole_index = 0; shared.state.num_active_blackholes = 0

    shared.state.player_pos = {0,0}; shared.state.player_vel = {0,0}
    shared.state.player_max_hp = shared.PLAYER_MAX_HP_VALUE
    shared.state.player_hp = shared.state.player_max_hp
    shared.state.player_invulnerable_timer = 0.0
    shared.state.player_defeated_message_shown = false

    // Initial effective-value mirrors. Shop upgrades modify these; gameplay reads them.
    // CLI flag --test-stage drops us into the debug spawn arena (no waves, no boss, no shop).
    shared.state.game_mode             = .PLAYING
    for arg in os.args[1:] {
        if arg == "--test-stage" {
            shared.state.game_mode = .TEST
            fmt.printf("--- TEST MODE: waves disabled, debug spawn keys (1-6, R) active ---\n")
        }
    }
    shared.state.eff_lmb_damage        = shared.LMB_PROJECTILE_DAMAGE
    shared.state.eff_lmb_cooldown      = shared.PROJECTILE_BLACKHOLE_COOLDOWN
    shared.state.eff_rmb_max_charge    = shared.RMB_MAX_CHARGE_DEFAULT
    shared.state.eff_rmb_charge_rate   = shared.RMB_CHARGE_RATE_DEFAULT
    shared.state.eff_rmb_damage_mult   = 1.0
    shared.state.eff_player_max_speed  = shared.PLAYER_MAX_SPEED
    shared.state.eff_dash_cooldown     = shared.PLAYER_DASH_COOLDOWN
    shared.state.eff_invul_duration    = shared.PLAYER_INVULNERABILITY_DURATION

    shared.state.key_shift_down = false
    shared.state.is_dashing = false
    shared.state.dash_timer = 0.0
    shared.state.dash_cooldown_timer = 0.0
    shared.state.player_dash_trail_count = 0
    shared.state.dash_trail_spawn_timer = 0.0

    shared.state.rmb_down=false; shared.state.previous_rmb_down=false; shared.state.rmb_cooldown_timer=0.0
    shared.state.lmb_down=false; shared.state.previous_lmb_down=false; shared.state.lmb_cooldown_timer=0.0
    shared.state.mouse_screen_pos = {0,0}

    shared.state.rmb_charge = 0.0

    shared.state.first_grunt_killed = false
    shared.state.first_slowboy_killed = false

    // Seed the global rand state with wall-clock so per-run randomness (boss laser shuffle,
    // wander vectors, sniper jitter) actually differs between sessions. The progression RNG
    // below uses its own state so the wave system stays seedable independently.
    global_seed := u64(time.time_to_unix_nano(time.now()))
    rand.reset(global_seed)

    random_generator_progression_seed: u64 = u64(sapp.frame_count()) + 12345
    shared.random_generator_progression = rand.create(random_generator_progression_seed)

    progression.init_progression()

    fmt.printf("--- Init Complete ---\n")
}

event :: proc "c" (event: ^sapp.Event) {
    context = runtime.default_context()
    player.handle_player_input(event)
    testmode.handle_test_input(event)
}

frame :: proc "c" () {
    context = runtime.default_context()
    width_f := sapp.widthf(); height_f := sapp.heightf(); aspect_f := width_f / height_f
    current_time_f := f32(sapp.frame_count()) / 60.0
    delta_time_f := f32(sapp.frame_duration()); delta_time_f = math.min(delta_time_f, 1.0/15.0)

    if shared.state.game_mode != .SHOP {
        // PLAYING and TEST both run player simulation. Shop pauses everything.
        shared.state.player_invulnerable_timer = math.max(0.0, shared.state.player_invulnerable_timer - delta_time_f)
        shared.state.rmb_cooldown_timer = math.max(0.0, shared.state.rmb_cooldown_timer - delta_time_f)
        shared.state.lmb_cooldown_timer = math.max(0.0, shared.state.lmb_cooldown_timer - delta_time_f)
        shared.state.dash_timer = math.max(0.0, shared.state.dash_timer - delta_time_f)
        shared.state.dash_cooldown_timer = math.max(0.0, shared.state.dash_cooldown_timer - delta_time_f)
        // Fire flashes are visual-only and decay quickly so the next shot reads as a fresh pulse.
        shared.state.lmb_fire_flash = math.max(0.0, shared.state.lmb_fire_flash - delta_time_f * 2.5)
        shared.state.rmb_fire_flash = math.max(0.0, shared.state.rmb_fire_flash - delta_time_f * 2.5)

        player.update_player(delta_time_f)
    } else {
        // Shop is open: zero player velocity so the world feels properly paused.
        shared.state.player_vel = {0, 0}
    }

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

    // --- Deadzone-follow camera update ---
    // Tight follow: camera holds still only inside a small 25% deadzone, then slides just
    // enough to put the player back on the deadzone edge. Tighter than the original 70% so
    // off-screen snipers come into view as soon as the player even slightly turns toward them.
    cam_half_w_dz := shared.ORTHO_HEIGHT * aspect_f
    cam_half_h_dz := f32(shared.ORTHO_HEIGHT)
    deadzone_w := cam_half_w_dz * 0.25
    deadzone_h := cam_half_h_dz * 0.25
    rel_dz := shared.state.player_pos - shared.state.camera_pos
    if rel_dz.x >  deadzone_w { shared.state.camera_pos.x += rel_dz.x - deadzone_w }
    if rel_dz.x < -deadzone_w { shared.state.camera_pos.x += rel_dz.x + deadzone_w }
    if rel_dz.y >  deadzone_h { shared.state.camera_pos.y += rel_dz.y - deadzone_h }
    if rel_dz.y < -deadzone_h { shared.state.camera_pos.y += rel_dz.y + deadzone_h }

    progression.update_wave_system(delta_time_f)
    audio.update_music(delta_time_f)

    if shared.state.game_mode == .SHOP {
        // Shop mode: feed the shop's update so it can read mouse hover + 1/2/3 picks.
        shop.update_shop(width_f, height_f)
    } else {
        // PLAYING + TEST both tick entities and run collision.
        shared.state.num_active_particles = particle.update_and_instance_particles(delta_time_f)
        shared.state.num_active_enemies = enemy.update_and_instance_enemies(delta_time_f)
        shared.state.num_active_blackholes = projectile.update_and_instance_blackholes(delta_time_f)

        collision.check_LMB_projectile_enemy_collisions()
        collision.check_RMB_particle_enemy_collisions()
        player.check_player_enemy_collisions()
        player.check_player_boss_laser_collision()
    }

    // --- Compute mouse-aim direction in world space (used by player shader for the aim blade) ---
    {
        ndc_x := (2.0 * shared.state.mouse_screen_pos.x / width_f) - 1.0
        ndc_y := 1.0 - (2.0 * shared.state.mouse_screen_pos.y / height_f)
        mouse_world_x := ndc_x * (shared.ORTHO_HEIGHT * aspect_f) + shared.state.camera_pos.x
        mouse_world_y := ndc_y * shared.ORTHO_HEIGHT + shared.state.camera_pos.y
        diff := m.vec2{mouse_world_x - shared.state.player_pos.x, mouse_world_y - shared.state.player_pos.y}
        if m.len_sq_vec2(diff) > 0.0001 {
            shared.state.player_aim_dir = m.norm_vec2(diff)
        } else {
            shared.state.player_aim_dir = {0, 1}
        }
    }

    hp_ratio: f32 = 0.0
    if shared.state.player_max_hp > 0 {
        hp_ratio = f32(shared.state.player_hp) / f32(shared.state.player_max_hp)
    }
    // Wave-button HUD uniform: x=next_wave_index (0..10), y=remaining (10-x), z=player_in_range (0..1),
    // w=press_flash (decays). bg_fs reads this and renders the centre button + pip indicators.
    in_range_dist_sq := m.len_sq_vec2(shared.state.player_pos)
    in_range: f32 = 1.0 if in_range_dist_sq <= shared.WAVE_BUTTON_PRESS_RANGE * shared.WAVE_BUTTON_PRESS_RANGE else 0.0
    button_state := m.vec4{
        f32(shared.state.wave_system.next_wave_to_press),
        f32(shared.WAVE_BUTTON_TOTAL_WAVES - shared.state.wave_system.next_wave_to_press),
        in_range,
        shared.state.wave_system.button_press_flash,
    }
    // Shop uniforms — only meaningful when game_mode == .SHOP, but always written so the shader
    // sees a consistent struct. tier vector packs the tier (1/2/3) of each card.
    shop_active: f32 = 0.0
    shop_hover: f32 = -1.0
    shop_pre_boss: f32 = 0.0
    shop_tier_vec: m.vec4 = {1, 1, 1, 0}
    if shared.state.game_mode == .SHOP {
        shop_active = 1.0
        shop_hover  = f32(shared.state.shop.hovered)
        if shared.state.shop.is_pre_boss { shop_pre_boss = 1.0 }
        shop_tier_vec = m.vec4{
            f32(shop.upgrade_tier(shared.state.shop.options[0])),
            f32(shop.upgrade_tier(shared.state.shop.options[1])),
            f32(shop.upgrade_tier(shared.state.shop.options[2])),
            0.0,
        }
    }
    shared.state.bg_fs_params={
        tick=current_time_f, resolution={width_f,height_f}, bg_option=1,
        player_hp_ratio=hp_ratio, camera_pos=shared.state.camera_pos,
        wave_button_state=button_state,
        shop_state={shop_active, shop_hover, shop_pre_boss, 0.0},
        shop_tiers=shop_tier_vec,
    }
    shared.state.player_fs_params={
        tick=current_time_f, resolution={width_f,height_f}, player_hp_uniform=f32(shared.state.player_hp),
        player_max_hp_uniform=f32(shared.state.player_max_hp), player_invulnerable_timer_uniform = shared.state.player_invulnerable_timer,
        player_invulnerability_duration_uniform = shared.state.eff_invul_duration,
        player_aim_dir = shared.state.player_aim_dir,
        lmb_fire_flash = shared.state.lmb_fire_flash,
        rmb_fire_flash = shared.state.rmb_fire_flash,
        rmb_charge_ratio = shared.state.rmb_charge / shared.RMB_BEAM_THRESHOLD,
        rmb_max_charge_ratio = shared.state.eff_rmb_max_charge / shared.RMB_BEAM_THRESHOLD,
    }
    shared.state.particle_fs_params={tick=current_time_f}
    shared.state.enemy_fs_params={tick=current_time_f}
    shared.state.blackhole_fs_params={tick=current_time_f}

    ortho_width_vp_f := shared.ORTHO_HEIGHT*aspect_f
    proj_f := m.ortho(-ortho_width_vp_f,ortho_width_vp_f,-shared.ORTHO_HEIGHT,shared.ORTHO_HEIGHT,-1.0,1.0)
    // Deadzone-follow camera: view translates the world by -camera_pos.
    view_f := m.translate(m.vec3{-shared.state.camera_pos.x, -shared.state.camera_pos.y, 0.0})
    view_proj_f := m.mul(proj_f,view_f)

    scale_mat_f := m.scale(m.vec3{shared.PLAYER_SCALE,shared.PLAYER_SCALE,1.0})
    translate_mat_f := m.translate(m.vec3{shared.state.player_pos.x,shared.state.player_pos.y,0.0})
    model_f := m.mul(translate_mat_f,scale_mat_f)
    shared.state.player_vs_params.mvp=m.mul(view_proj_f,model_f)

    shared.state.particle_vs_params.view_proj=view_proj_f
    shared.state.enemy_vs_params.view_proj=view_proj_f
    shared.state.blackhole_vs_params.view_proj=view_proj_f


    // Build sokol-debugtext labels for the shop BEFORE the pass — sdtx.draw() submits the
    // accumulated commands inside the active pass.
    sdtx_canvas_w: f32 = width_f * 0.5
    sdtx_canvas_h: f32 = height_f * 0.5
    sdtx.canvas(sdtx_canvas_w, sdtx_canvas_h)
    sdtx.layer(0)
    if shared.state.game_mode == .SHOP {
        shop.render_text(sdtx_canvas_w, sdtx_canvas_h)
    }

    sg.begin_pass({action=shared.state.pass_action, swapchain=sglue.swapchain() })
    // Background pass also renders the arena ring + outside-arena darkening + shop card overlay (see fs_bg in shader.glsl).
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
    // Shop text overlay last so it sits on top of everything.
    sdtx.draw()
    sg.end_pass(); sg.commit()
}


cleanup :: proc "c" () {
    context = runtime.default_context()
    audio.cleanup_audio()
    if sa.isvalid() { sa.shutdown(); fmt.printf("--- Sokol Audio shutdown ---\n") }
    sdtx.shutdown()
    sg.shutdown()
}

// Default window is 1080p with high-DPI awareness so the backing surface matches physical pixels
// on modern displays. Camera math is resolution-independent (everything is in world units +
// orthographic projection sized off ORTHO_HEIGHT), so smaller windows just see less of the world.
main :: proc () {
    sapp.run({
        init_cb=init, frame_cb=frame, cleanup_cb=cleanup, event_cb=event,
        width=1920, height=1080, high_dpi=true, sample_count=4,
        window_title="GeoWars Odin",
        icon={sokol_default=true}, logger={func=slog.func},
    })
}
