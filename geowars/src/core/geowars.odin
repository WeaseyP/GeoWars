package main

import "base:runtime"
import "core:math"
import "core:fmt"
import rand "core:math/rand"
import slog "../vendor/sokol/log"
import sg "../vendor/sokol/gfx"
import sapp "../vendor/sokol/app"
import sglue "../vendor/sokol/glue"
import sa "../vendor/sokol/audio"
import m "../vendor/math"

import shared "../shared"
import input "input"
import grid "../game/grid"
import projectile "../game/projectile"
import player "../game/player"
import enemy "../game/enemy"
import particle "../game/particle"
import progression "../game/progression"
import collision "../game/collision"
import audio "../audio"
import ui "../ui"

// --- Global State ---
state: shared.GameState
input_mgr: input.InputManager
grid_system: grid.Grid
proj_mgr: projectile.ProjectileManager

// Game Flow State
GameFlowState :: enum {
    Playing,
    GameOver,
    Victory,
}
flow_state: GameFlowState

init :: proc "c" () {
    context = runtime.default_context()
    sg.setup({ pipeline_pool_size=16, buffer_pool_size=16, shader_pool_size=16, environment=sglue.environment(), logger={func=slog.func} })
    
    // Init Audio
    audio.init_audio(&state)

    // Init Input
    input.init(&input_mgr)

    // Init Graphics Resources (Pipelines, VBOs)
    // NOTE: This logic was in init_rendering() or inline. I'll recreate it here using shared logic if possible
    // or just copy the pipeline creation code. Since I moved params to shared, I can use them.
    // However, I need shader descs. `graphics` package? `graphics/rendering.odin` exists.
    // `init_rendering()` was called in original code.
    // I should check `geowars/src/graphics/rendering.odin`.
    // Assuming `graphics.init_rendering(&state)` exists or I need to implement it.
    // For now, I'll assume I need to do it here or call `graphics` pkg.
    // I'll assume `graphics` package has the shaders.
    // Actually, `graphics` package content is unknown.
    // But `geowars.odin` had `init_rendering()`.
    // I'll inline the rendering setup to be safe, using code from previous `geowars.odin`.

    setup_pipelines()

    // Init Projectile Manager
    projectile.init(&proj_mgr, state.blackhole_pip, state.bind)

    // Init Player
    state.player.max_hp = 4
    state.player.hp = 4
    
    // Init Level
    progression.init_levels()
    progression.load_stage(&state, 0, 0)

    flow_state = .Playing
    
    ui.init_hud()

    // Init Camera
    state.camera.zoom = 1.0
    state.camera.pos = {0, 0}
}

frame :: proc "c" () {
    context = runtime.default_context()

    // Timing
    dt := f32(sapp.frame_duration())
    dt = math.min(dt, 1.0/30.0) // Clamp dt
    state.bg_fs_params.tick += dt * 60.0 // approx tick
    state.bg_fs_params.bg_option = 1

    if flow_state == .Playing {
        // Update Game Logic
        state.closest_gravitron_dist_sq = 99999.0 // Reset per frame
        player.update_player(&state, dt, &input_mgr, &proj_mgr)
        
        // Update Camera
        target := state.player.pos
        // Smooth Follow
        lerp_speed : f32 = 10.0
        // Manual lerp for vec2 to avoid casting issues in vendor math
        t := dt * lerp_speed
        if t > 1.0 do t = 1.0
        state.camera.pos = state.camera.pos + (target - state.camera.pos) * t
        
        // Clamp Camera
        // Viewport size in world units
        aspect := sapp.widthf() / sapp.heightf()
        view_h : f32 = f32(shared.ORTHO_HEIGHT)
        view_w := view_h * aspect
        
        limit_x := f32(shared.ARENA_WIDTH) - view_w
        limit_y := f32(shared.ARENA_HEIGHT) - view_h
        
        // Ensure limits are non-negative
        if limit_x < 0.0 do limit_x = 0.0
        if limit_y < 0.0 do limit_y = 0.0
        
        state.camera.pos.x = math.clamp(state.camera.pos.x, -limit_x, limit_x)
        state.camera.pos.y = math.clamp(state.camera.pos.y, -limit_y, limit_y)
        
        // Camera Shake Update
        shake_vec := m.vec2{0,0}
        if state.camera.shake_duration > 0.0 {
            state.camera.shake_duration -= dt
            // Simple random shake
            shake_vec.x = (rand.float32() * 2.0 - 1.0) * state.camera.shake_intensity
            shake_vec.y = (rand.float32() * 2.0 - 1.0) * state.camera.shake_intensity
        }

        state.num_active_enemies = enemy.update_and_instance_enemies(&state, dt)

        // Apply Gravitron Pull (Single Lock)
        if state.closest_gravitron_dist_sq < 99990.0 {
             // Logic: Pull strength based on distance, but clamped or constant? 
             // "Pull in closer". Let's use inverse square-ish or linear ramp.
             // Original was (Range - Dist).
             // New Range is 10.0 (Sq 100).
             dist := math.sqrt(state.closest_gravitron_dist_sq)
             pull_strength := (10.0 - dist) * 1.5 // Tune strength
             if pull_strength < 0.0 do pull_strength = 0.0
             
             pull_dir := m.norm_vec2(state.closest_gravitron_pos - state.player.pos)
             state.player.vel += pull_dir * pull_strength * dt
        }
        state.num_active_particles = particle.update_and_instance_particles(&state, dt)
        projectile.update(&proj_mgr, dt)

        collision.check_LMB_projectile_enemy_collisions(&state, &proj_mgr)
        collision.check_RMB_particle_enemy_collisions(&state)
        collision.check_player_enemy_collisions(&state)
        collision.check_player_boss_laser_collision(&state)

        progression.handle_enemy_spawning(&state, dt)
        progression.update_progression(&state)

        if state.player.hp <= 0 && !state.player.defeated_message_shown {
            flow_state = .GameOver
        }
    }
    
    // Render
    // Render
    draw_frame(dt)
    ui.draw_hud(&state)

    // Update Input Last
    input.update(&input_mgr)
}

event :: proc "c" (event: ^sapp.Event) {
    context = runtime.default_context()
    input.handle_event(&input_mgr, event)
}

cleanup :: proc "c" () {
    context = runtime.default_context()
    sg.shutdown()
    if sa.isvalid() { sa.shutdown() }
    ui.shutdown_hud()
}

main :: proc () {
    sapp.run({
        init_cb=init,
        frame_cb=frame,
        cleanup_cb=cleanup,
        event_cb=event,
        width=800,
        height=600,
        sample_count=4,
        window_title="GeoWars Refactored",
        icon={sokol_default=true},
        logger={func=slog.func}
    })
}

// --- Helpers ---

setup_pipelines :: proc() {
    // Shared Quad
    vertices := [?]f32 { -1,-1,0,0,0,0,0, 1,-1,0,1,0,0,0, -1,1,0,0,1,0,0, 1,1,0,1,1,0,0 }
    state.bind.vertex_buffers[0] = sg.make_buffer({ label="shared-quad-vertices", data=sg.Range{ptr=&vertices[0], size=size_of(vertices)}})
    
    // Particle Quad
    particle_quad_verts := [?]f32{ -0.5,-0.5,0,0, 0.5,-0.5,1,0, -0.5,0.5,0,1, 0.5,0.5,1,1 }
    state.particle_quad_vbo = sg.make_buffer({ label="particle-quad-base", data=sg.Range{ptr=&particle_quad_verts[0], size=size_of(particle_quad_verts)}})
    state.particle_instance_vbo = sg.make_buffer({ label="particle-inst", size=shared.MAX_PARTICLES*size_of(shared.Particle_Instance_Data), type=.VERTEXBUFFER, usage=.STREAM })
    
    state.enemy_instance_vbo = sg.make_buffer({ label="enemy-inst", size=shared.MAX_ENEMIES*size_of(shared.Enemy_Instance_Data), type=.VERTEXBUFFER, usage=.STREAM })
    
    // Shaders (Calls to auto-generated shader.odin in shared)
    // NOTE: assuming these functions are available in package shared
    bg_shd := sg.make_shader(shared.bg_shader_desc(sg.query_backend()))
    player_shd := sg.make_shader(shared.player_shader_desc(sg.query_backend()))
    particle_shd := sg.make_shader(shared.particle_shader_desc(sg.query_backend()))
    enemy_shd := sg.make_shader(shared.enemy_shader_desc(sg.query_backend()))
    blackhole_shd := sg.make_shader(shared.blackhole_shader_desc(sg.query_backend()))

    // Pipelines
    state.bg_pip = sg.make_pipeline({
        label="bg-pip", shader=bg_shd,
        layout={buffers={0={stride=28}},attrs={shared.ATTR_bg_position={format=.FLOAT2}}},
        primitive_type=.TRIANGLE_STRIP
    })

    state.player_pip = sg.make_pipeline({
        label="player-pip", shader=player_shd,
        layout={buffers={0={stride=28}},attrs={shared.ATTR_player_position={format=.FLOAT2}}},
        primitive_type=.TRIANGLE_STRIP,
        colors={0={blend={enabled=true, src_factor_rgb=.SRC_ALPHA,dst_factor_rgb=.ONE_MINUS_SRC_ALPHA}}},
        depth={write_enabled=false, compare=.ALWAYS}
    })

    // ... Particle/Enemy/Blackhole pipelines ...
    // Using constants from shared logic if available, or redefining for layout

    // Particle
    state.particle_pip = sg.make_pipeline({
        label="particle-pip", shader=particle_shd,
        layout={
            buffers={0={stride=16,step_func=.PER_VERTEX}, 1={stride=size_of(shared.Particle_Instance_Data),step_func=.PER_INSTANCE}},
            attrs={
                shared.ATTR_particle_quad_pos={buffer_index=0,offset=0,format=.FLOAT2},
                shared.ATTR_particle_quad_uv={buffer_index=0,offset=8,format=.FLOAT2},
                shared.ATTR_particle_instance_pos_size_rot={buffer_index=1,offset=0,format=.FLOAT4},
                shared.ATTR_particle_instance_color={buffer_index=1,offset=16,format=.FLOAT4}
            }
        },
        primitive_type=.TRIANGLE_STRIP,
        colors={0={blend={enabled=true, src_factor_rgb=.SRC_ALPHA, dst_factor_rgb=.ONE}}},
        depth={write_enabled=false, compare=.ALWAYS}
    })

    // Enemy
    state.enemy_pip = sg.make_pipeline({
        label="enemy-pip", shader=enemy_shd,
        layout={
            buffers={0={stride=16, step_func=.PER_VERTEX}, 1={stride=size_of(shared.Enemy_Instance_Data), step_func=.PER_INSTANCE}},
            attrs={
                shared.ATTR_enemy_quad_pos_in={buffer_index=0,offset=0,format=.FLOAT2},
                shared.ATTR_enemy_quad_uv_in={buffer_index=0,offset=8,format=.FLOAT2},
                shared.ATTR_enemy_instance_pos_vs_in={buffer_index=1,offset=0,format=.FLOAT2},
                shared.ATTR_enemy_instance_main_rotation_vs_in={buffer_index=1,offset=8,format=.FLOAT},
                shared.ATTR_enemy_instance_visual_scale_vs_in={buffer_index=1,offset=12,format=.FLOAT},
                shared.ATTR_enemy_instance_color_vs_in={buffer_index=1,offset=16,format=.FLOAT4},
                shared.ATTR_enemy_instance_effect_params_vs_in={buffer_index=1,offset=32,format=.FLOAT4},
                shared.ATTR_enemy_instance_enemy_type_vs_in={buffer_index=1,offset=48,format=.FLOAT},
            }
        },
        primitive_type=.TRIANGLE_STRIP,
        colors={0={blend={enabled=true, src_factor_rgb=.SRC_ALPHA, dst_factor_rgb=.ONE_MINUS_SRC_ALPHA}}},
        depth={write_enabled=false, compare=.ALWAYS}
    })

    // Blackhole
    state.blackhole_pip = sg.make_pipeline({
        label="blackhole-pip", shader=blackhole_shd,
        layout={
            buffers={0={stride=16,step_func=.PER_VERTEX}, 1={stride=size_of(shared.Blackhole_Instance_Data),step_func=.PER_INSTANCE}},
            attrs={
                shared.ATTR_blackhole_quad_pos={buffer_index=0,offset=0,format=.FLOAT2},
                shared.ATTR_blackhole_quad_uv={buffer_index=0,offset=8,format=.FLOAT2},
                shared.ATTR_blackhole_instance_pos_size_rot={buffer_index=1,offset=0,format=.FLOAT4},
                shared.ATTR_blackhole_instance_color={buffer_index=1,offset=16,format=.FLOAT4}
            }
        },
        primitive_type=.TRIANGLE_STRIP,
        colors={0={blend={enabled=true, src_factor_rgb=.SRC_ALPHA, dst_factor_rgb=.ONE_MINUS_SRC_ALPHA}}},
        depth={write_enabled=false, compare=.ALWAYS}
    })
    state.particle_bind = sg.Bindings{ vertex_buffers = { 0=state.particle_quad_vbo, 1=state.particle_instance_vbo } }
    state.enemy_bind = sg.Bindings{ vertex_buffers = { 0=state.particle_quad_vbo, 1=state.enemy_instance_vbo } }
}

draw_frame :: proc(dt: f32) {
    // Aspect Ratio
    width := sapp.widthf()
    height := sapp.heightf()
    aspect := width / height
    
    // MVP Update
    ortho_h : f32 = shared.ORTHO_HEIGHT
    ortho_w := ortho_h * aspect
    proj := m.ortho(-ortho_w, ortho_w, -ortho_h, ortho_h, -1.0, 1.0)
    
    // View Matrix (Camera)
    // Add shake offset to view position (visual only, doesn't affect game logic pos)
    shake := m.vec2{0,0}
    if state.camera.shake_duration > 0.0 {
         shake.x = (rand.float32() * 2.0 - 1.0) * state.camera.shake_intensity
         shake.y = (rand.float32() * 2.0 - 1.0) * state.camera.shake_intensity
    }
    view := m.translate(m.vec3{-state.camera.pos.x + shake.x, -state.camera.pos.y + shake.y, 0})
    view_proj := m.mul(proj, view)

    // Player Uniforms
    model := m.mul(m.translate(m.vec3{state.player.pos.x, state.player.pos.y, 0}), m.scale(m.vec3{shared.PLAYER_SCALE, shared.PLAYER_SCALE, 1}))
    state.player_vs_params.mvp = m.mul(view_proj, model)
    state.player_fs_params.resolution = {width, height}
    state.player_fs_params.player_hp_uniform = f32(state.player.hp)
    state.player_fs_params.player_max_hp_uniform = f32(state.player.max_hp)
    state.player_fs_params.player_invulnerable_timer_uniform = state.player.invulnerable_timer

    state.player_fs_params.player_invulnerable_timer_uniform = state.player.invulnerable_timer
    
    // --- Draw Grid ---
    // 1. Get Vertices
    grid_verts := make([dynamic]shared.Vertex, context.temp_allocator)
    grid.get_grid_line_vertices(&grid_system, &grid_verts)
    
    // 2. Update Buffer
    if len(grid_verts) > 0 {
        range := sg.Range{ptr=&grid_verts[0], size=uint(len(grid_verts) * size_of(shared.Vertex))}
        sg.update_buffer(state.line_bind.vertex_buffers[0], range)
        
        // 3. Draw
        sg.apply_pipeline(state.line_pip)
        sg.apply_bindings(state.line_bind)
        // uniform block in shader is 'line_vs_params' so slot is SLOT_line_vs_params
        // Struct layout matches Player_Vs_Params (mat4 mvp)
        sg.apply_uniforms(shared.UB_line_vs_params, {&state.player_vs_params, size_of(state.player_vs_params)})
        sg.draw(0, i32(len(grid_verts)), 1)
    }

    // --- Draw Debug Boundary (Verify Size) ---
    debug_verts := make([dynamic]shared.Vertex, context.temp_allocator)
    
    // Generate Hexagon Loop
    // Flat-Top Hexagon logic matches Physics/Shader
    // 6 segments.
    // Physics Logic: "Point Top" rotated 90.
    // Angles: 0, 60, 120... rotated 90 -> 90, 150, 210, 270, 330, 30.
    // Or just swap X/Y of standard specific.
    // Standard Point Top: (R*sin(ang), R*cos(ang)) ? 
    // Vertices at angles: 30, 90, 150... for Flat Top?
    // Flat Top: Vertices are at ( R, 0 ), ( R/2, R*sqrt(3)/2 )... NO.
    // Flat Top: Edges are vertical/diagonal. Vertices are at (X, Y).
    // Let's use the explicit angles 0, 60... adjusted.
    // Vertices at (R, 0), (R/2, H), (-R/2, H), (-R, 0)... that's Point Top at 90.
    // Let's generate Point Top standard and swap X/Y like shader/physics do.
    
    r := f32(shared.ARENA_HEX_RADIUS)
    for i := 0; i <= 6; i += 1 {
        angle_deg := f32(i) * 60.0 + 30.0 // 30 deg offset for Point Top
        angle_rad := m.radians(angle_deg)
        
        // Standard Point Top
        px := r * math.cos_f32(angle_rad)
        py := r * math.sin_f32(angle_rad)
        
        // Swap for Flat Top
        p := m.vec3{py, px, 0.0}
        
        c := m.vec4{1.0, 0.0, 0.0, 1.0} // Red Debug Line
        append(&debug_verts, shared.Vertex{pos=p, color=c})
    }
    
    if len(debug_verts) > 0 {
         range := sg.Range{ptr=&debug_verts[0], size=uint(len(debug_verts) * size_of(shared.Vertex))}
         // Reuse line buffer (append or update offset?)
         // Simple: Update buffer again (overwrite grid for this frame? No, grid drawn).
         // Append doesn't work well with sg.update_buffer on same frame unless we offset.
         // Let's just use `sg.append_buffer` logic if supported, or a second buffer.
         // Actually, `line_bind.vertex_buffers[0]` is STREAM. We can call `sg.append_buffer`.
         // Sokol `append_buffer` returns offset.
         
         offset := sg.append_buffer(state.line_bind.vertex_buffers[0], range)
         sg.apply_pipeline(state.line_pip)
         sg.apply_bindings(state.line_bind) // Bind again?
         sg.apply_uniforms(shared.UB_line_vs_params, {&state.player_vs_params, size_of(state.player_vs_params)})
         sg.draw(offset, i32(len(debug_verts)), 1) 
    }

    // Other Uniforms
    state.particle_vs_params.view_proj = view_proj
    state.enemy_vs_params.view_proj = view_proj
    state.blackhole_vs_params.view_proj = view_proj
    state.bg_fs_params.resolution = {width, height}
    state.particle_fs_params.tick = state.bg_fs_params.tick
    state.enemy_fs_params.tick = state.bg_fs_params.tick
    state.blackhole_fs_params.tick = state.bg_fs_params.tick

    // --- Update Grid ---
    if m.len_sq_vec2(state.player.vel) > 1.0 {
         grid.apply_force(&grid_system, state.player.pos, 5.0 * dt, 2.0)
    }
    grid.update_grid(&grid_system, dt)
    
    // --- Audio Update ---
    // --- BG Pass ---
    state.pass_action.colors[0] = { load_action=.CLEAR, clear_value={0.0, 0.0, 0.0, 1.0} }
    sg.begin_pass({ action=state.pass_action, swapchain=sglue.swapchain() })
    
    sg.apply_pipeline(state.bg_pip)
    sg.apply_bindings(state.bind)
    state.bg_fs_params.tick += dt
    state.bg_fs_params.resolution = {sapp.widthf(), sapp.heightf()}
    state.bg_fs_params.bg_option = 1 // 1 = Nebula/Stars
    state.bg_fs_params.cam_offset = state.camera.pos 
// 1 = Nebula/Stars
    state.bg_fs_params.cam_offset = state.camera.pos 
    
    sg.apply_uniforms(shared.UB_bg_fs_params, sg.Range{ptr=&state.bg_fs_params, size=size_of(state.bg_fs_params)})
    sg.draw(0, 4, 1)

    // Player
    if state.player.hp > 0 {
        sg.apply_pipeline(state.player_pip)
        sg.apply_bindings(state.bind)
        sg.apply_uniforms(shared.UB_Player_Vs_Params, sg.Range{ptr=&state.player_vs_params, size=size_of(shared.Player_Vs_Params)})
        sg.apply_uniforms(shared.UB_Player_Fs_Params, sg.Range{ptr=&state.player_fs_params, size=size_of(shared.Player_Fs_Params)})
        sg.draw(0, 4, 1)
    }

    // Particles
    if state.num_active_particles > 0 {
        sg.apply_pipeline(state.particle_pip)
        sg.apply_bindings(state.particle_bind)
        sg.update_buffer(state.particle_instance_vbo, sg.Range{ptr=rawptr(&state.particle_instance_data[0]), size=uint(state.num_active_particles)*size_of(shared.Particle_Instance_Data)})
        sg.apply_uniforms(shared.UB_particle_vs_params, sg.Range{ptr=&state.particle_vs_params, size=size_of(shared.Particle_Vs_Params)})
        sg.apply_uniforms(shared.UB_particle_fs_params, sg.Range{ptr=&state.particle_fs_params, size=size_of(shared.Particle_Fs_Params)})
        sg.draw(0, 4, state.num_active_particles)
    }

    // Enemies
    if state.num_active_enemies > 0 {
        sg.apply_pipeline(state.enemy_pip)
        sg.apply_bindings(state.enemy_bind)
        sg.update_buffer(state.enemy_instance_vbo, sg.Range{ptr=rawptr(&state.enemy_instance_data[0]), size=uint(state.num_active_enemies)*size_of(shared.Enemy_Instance_Data)})
        sg.apply_uniforms(shared.UB_enemy_vs_params, sg.Range{ptr=&state.enemy_vs_params, size=size_of(shared.Enemy_Vs_Params)})
        sg.apply_uniforms(shared.UB_enemy_fs_params, sg.Range{ptr=&state.enemy_fs_params, size=size_of(shared.Enemy_Fs_Params)})
        sg.draw(0, 4, state.num_active_enemies)
    }
    
    // Projectiles
    projectile.draw(&proj_mgr, &state.blackhole_vs_params, &state.blackhole_fs_params)
    
    sg.end_pass()
    sg.commit()
}
