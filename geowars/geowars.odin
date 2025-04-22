// File: geowars.odin (Revised for Slow Travel & Strong Radial Explosion)
//------------------------------------------------------------------------------
package main

import "base:runtime"
import "core:math"
import "core:mem"
import "core:fmt"
import slog "../sokol/log"
import sg "../sokol/gfx"
import sapp "../sokol/app"
import sglue "../sokol/glue"
import m "../math"
import rand "core:math/rand"

// =============================================================================
// START: Package-Level Declarations
// =============================================================================

MAX_PARTICLES :: 2048
DEATH_BURST_PARTICLE_COUNT :: 150

// --- Constants ---
ORTHO_HEIGHT :: 1.5
PLAYER_ACCELERATION      :: 15.0
PLAYER_REVERSE_FACTOR    :: 0.5
PLAYER_DAMPING           :: 2.5
PLAYER_MAX_SPEED         :: 7.0
PLAYER_SCALE             :: 0.25
PLAYER_CORE_SHADER_RADIUS :: 0.04
PLAYER_UV_SPACE_EXTENT   :: 0.5
PLAYER_CORE_WORLD_RADIUS :: (PLAYER_CORE_SHADER_RADIUS / PLAYER_UV_SPACE_EXTENT) * PLAYER_SCALE
BLACKHOLE_COOLDOWN_DURATION :: 1.0
MAX_SPIN_SPEED           :: f32(m.PI * 2.0)
// *** Swirl Charge Constants ***
SWIRL_CHARGE_DURATION_BASE  : f32 : 1.8
SWIRL_CHARGE_DURATION_RAND  : f32 : 0.5
SWIRL_RADIUS_SPAWN          : f32 : 0.05 // Tighter spawn
SWIRL_SPEED_ORBITAL_BASE    : f32 : 3.5  // Keep orbital speed
SWIRL_SPEED_INWARD_INITIAL  : f32 : -0.1 // Keep slight inward drift
SWIRL_PARTICLE_SIZE_BASE    : f32 : 0.03 // Smaller particles
SWIRL_PARTICLE_SIZE_RAND    : f32 : 0.01
// *** Cloud Travel Speed Constants ***
// --- MODIFIED: Decouple from player, slow base push ---
SWIRL_CLOUD_TRAVEL_FACTOR   : f32 : 0.0  // SET TO 0: Ignore player velocity entirely
SWIRL_CLOUD_BASE_PUSH       : f32 : 0.15 // Reduced FURTHER: Very slow drift away from player front
// ---

// *** Explosion Constants (after swirl) ***
EXPLOSION_LIFETIME_BASE : f32 : 1.0
EXPLOSION_LIFETIME_RAND : f32 : 0.8
// --- MODIFIED: Drastically increase explosion speed ---
EXPLOSION_SPEED_BASE    : f32 : 6.0  // Increased explosion speed SIGNIFICANTLY
EXPLOSION_SPEED_RAND    : f32 : 4.0  // Increased explosion speed variance SIGNIFICANTLY
// ---
EXPLOSION_PARTICLE_SPIN : f32 : 0.0  // No individual spin during explosion

// Rendering Internals
vertex_stride :: size_of(f32) * 7
particle_quad_stride :: size_of(f32) * 4

// --- Struct Definitions ---
Particle :: struct {
	pos:              m.vec2,
	vel:              m.vec2,
	cloud_travel_vel: m.vec2, // Velocity component for the cloud's overall travel
	color:            m.vec4,
	size:             f32,
	start_size:       f32,
	life_remaining:   f32,
	life_max:         f32,      // Max lifetime for the *current* phase (swirl OR explosion)
    swirl_duration:   f32,      // NEW: Store the original duration of the swirl phase
	rotation:         f32,
	angular_vel:      f32,
    charge_center_pos: m.vec2, // Initial origin point of the swirl
	is_burst_particle: bool,
    is_swirling_charge: bool, // True during swirl, False during explosion
	active:           bool,
}
Particle_Instance_Data :: struct #align(16) {
	using _: struct #packed {
		instance_pos:      m.vec2,
		instance_size:     f32,
		instance_rotation: f32,
		instance_color:    m.vec4,
	},
}

// --- Global State ---
state: struct {
    pass_action: sg.Pass_Action, bind: sg.Bindings,
    bg_pip: sg.Pipeline, player_pip: sg.Pipeline, particle_pip: sg.Pipeline,
    bg_fs_params: Bg_Fs_Params, player_vs_params: Player_Vs_Params, player_fs_params: Player_Fs_Params,
    particle_vs_params: Particle_Vs_Params, particle_fs_params: Particle_Fs_Params,
    player_pos: m.vec2, player_vel: m.vec2,
    key_w_down: bool, key_s_down: bool, key_a_down: bool, key_d_down: bool,
    rmb_down: bool, previous_rmb_down: bool, rmb_cooldown_timer: f32,
	particles: [MAX_PARTICLES]Particle, particle_instance_data: [MAX_PARTICLES]Particle_Instance_Data,
	particle_quad_vbo: sg.Buffer, particle_instance_vbo: sg.Buffer, particle_bind: sg.Bindings,
	next_particle_index: int, num_active_particles: int,
}
// =============================================================================
// END: Package-Level Declarations
// =============================================================================


init :: proc "c" () {
    // (init remains the same as your last working version, including pipelines)
    context = runtime.default_context()
    sg.setup({ pipeline_pool_size=10, buffer_pool_size=10, shader_pool_size=10, environment=sglue.environment(), logger={func=slog.func} })
    fmt.printf("--- Init Start ---\n")
    state.pass_action = {colors = {0={load_action = .DONTCARE}}}
    vertices := [?]f32 { -1,-1,0,0,0,0,0, 1,-1,0,1,0,0,0, -1,1,0,0,1,0,0, 1,1,0,1,1,0,0 }
    state.bind.vertex_buffers[0] = sg.make_buffer({ label="shared-quad", data=sg.Range{ptr=&vertices[0], size=size_of(vertices)}})
	particle_quad_verts := [?]f32{ -0.5,-0.5,0,0, 0.5,-0.5,1,0, -0.5,0.5,0,1, 0.5,0.5,1,1 }
	state.particle_quad_vbo = sg.make_buffer({ label="particle-quad", data=sg.Range{ptr=&particle_quad_verts[0], size=size_of(particle_quad_verts)}})
    state.particle_instance_vbo = sg.make_buffer({ label="particle-inst", size=MAX_PARTICLES*size_of(Particle_Instance_Data), type=.VERTEXBUFFER, usage=.STREAM })
    bg_shd := sg.make_shader(bg_shader_desc(sg.query_backend()))
    player_shd := sg.make_shader(player_shader_desc(sg.query_backend()))
    particle_shd := sg.make_shader(particle_shader_desc(sg.query_backend()))
    state.bg_pip = sg.make_pipeline({ label="bg-pip", shader=bg_shd, layout={buffers={0={stride=vertex_stride}},attrs={ATTR_bg_position={format=.FLOAT2}}}, primitive_type=.TRIANGLE_STRIP})
    state.player_pip = sg.make_pipeline({ label="player-pip", shader=player_shd, layout={buffers={0={stride=vertex_stride}},attrs={ATTR_player_position={format=.FLOAT2}}}, primitive_type=.TRIANGLE_STRIP, colors={0={blend={enabled=true, src_factor_rgb=.SRC_ALPHA,dst_factor_rgb=.ONE_MINUS_SRC_ALPHA}}}, depth={write_enabled=false, compare=.ALWAYS} })
    state.particle_pip = sg.make_pipeline({ label="particle-pip", shader=particle_shd,
        layout={ buffers={0={stride=particle_quad_stride,step_func=.PER_VERTEX}, 1={stride=size_of(Particle_Instance_Data),step_func=.PER_INSTANCE}}, attrs={ATTR_particle_quad_pos={buffer_index=0,offset=0,format=.FLOAT2}, ATTR_particle_quad_uv={buffer_index=0,offset=8,format=.FLOAT2}, ATTR_particle_instance_pos_size_rot={buffer_index=1,offset=0,format=.FLOAT4}, ATTR_particle_instance_color={buffer_index=1,offset=16,format=.FLOAT4}} },
        primitive_type=.TRIANGLE_STRIP, colors={0={blend={enabled=true, src_factor_rgb=.SRC_ALPHA, dst_factor_rgb=.ONE}}}, depth={write_enabled=false, compare=.ALWAYS}
    })
    pip_state := sg.query_pipeline_state(state.particle_pip);
    if pip_state != .VALID { fmt.eprintf("!!! CRITICAL: Particle pipeline creation failed! State: %v\n", pip_state); }
    else { fmt.printf("--- Particle pipeline created successfully ---\n"); }

    // --- Particle Bindings (Using simple {} syntax as requested) ---
	state.particle_bind = sg.Bindings{
        vertex_buffers = { 0=state.particle_quad_vbo, 1=state.particle_instance_vbo },
        // Remaining slots and index buffer implicitly zeroed
    }
    // --- End Particle Bindings ---

	state.next_particle_index = 0; state.num_active_particles = 0; state.player_pos = {0,0}; state.player_vel = {0,0};
    state.rmb_down=false; state.previous_rmb_down=false; state.rmb_cooldown_timer=0.0;
    fmt.printf("--- Init Complete ---\n")
}

// --- Event Callback Procedure ---
event :: proc "c" (event: ^sapp.Event) {
    // (Event handling code remains the same)
    context = runtime.default_context()
    #partial switch event.type {
    case .KEY_DOWN: #partial switch event.key_code { case .W: state.key_w_down=true; case .S: state.key_s_down=true; case .A: state.key_a_down=true; case .D: state.key_d_down=true; case .ESCAPE: sapp.request_quit(); }
    case .KEY_UP: #partial switch event.key_code { case .W: state.key_w_down=false; case .S: state.key_s_down=false; case .A: state.key_a_down=false; case .D: state.key_d_down=false; }
    case .MOUSE_DOWN: if event.mouse_button == .RIGHT { state.rmb_down = true }
	case .MOUSE_UP: if event.mouse_button == .RIGHT { state.rmb_down = false }
    }
}

// =============================================================================
// START: Particle Helper Functions
// =============================================================================

emit_particle :: proc(part: Particle) {
    // (emit_particle remains the same)
	context = runtime.default_context()
	start_index := state.next_particle_index
    state.particles[state.next_particle_index] = part
	state.particles[state.next_particle_index].active = true
	state.next_particle_index = (state.next_particle_index + 1) % MAX_PARTICLES
}

spawn_swirling_charge :: proc() {
	context = runtime.default_context()
	fmt.printf("-> spawn_swirling_charge called\n")

    charge_spawn_center := state.player_pos // Where the effect originates initially

	charge_duration := SWIRL_CHARGE_DURATION_BASE + rand.float32() * SWIRL_CHARGE_DURATION_RAND // This is the swirl duration
    start_size_val_base := SWIRL_PARTICLE_SIZE_BASE
    start_size_val_rand := SWIRL_PARTICLE_SIZE_RAND
	start_color := m.vec4{0.8, 0.3, 1.0, 1.0}

    // --- Calculate Cloud Travel Velocity (Opposite Player, 1/4 Speed) ---
    cloud_travel_vel: m.vec2 = {0, 0} // Default to no movement if player is still
    player_speed_sq := m.len_sq_vec2(state.player_vel)
    cloud_speed_factor : f32 = 0.25 // 1/4 speed

    if player_speed_sq > 0.001 { // Avoid normalization of zero vector
        player_speed := math.sqrt(player_speed_sq)
        player_dir_opposite := -m.norm_vec2(state.player_vel)
        cloud_travel_vel = player_dir_opposite * player_speed * cloud_speed_factor
    } else {
        // Optional: Give a slight default backward push if player is stationary?
        // cloud_travel_vel = {0.0, -0.5} // Example: small push down
    }
    // --- End Cloud Travel Velocity Calculation ---

	for _ in 0..<DEATH_BURST_PARTICLE_COUNT {
        start_size_val := start_size_val_base + rand.float32() * start_size_val_rand
        spawn_angle := rand.float32() * f32(m.TAU)
        spawn_dist := rand.float32() * SWIRL_RADIUS_SPAWN
        relative_pos := m.angle_to_vec2(spawn_angle) * spawn_dist
        start_pos := charge_spawn_center + relative_pos // Spawn relative to initial center

        // --- Calculate Swirl Velocities (Relative to Cloud Center) ---
        tangent_dir := m.vec2{-relative_pos.y, relative_pos.x}
        if m.len_sq_vec2(tangent_dir) > 0.001 { tangent_dir = m.norm_vec2(tangent_dir) }
        orbital_vel := tangent_dir * SWIRL_SPEED_ORBITAL_BASE * (0.8 + rand.float32() * 0.4)
        // Inward velocity should be relative to the *local* swirl center (which is {0,0} relative)
        inward_vel_dir: m.vec2 = {0,0}
        if m.len_sq_vec2(relative_pos) > 0.001 {
            inward_vel_dir = m.norm_vec2(-relative_pos)
        }
        inward_vel := inward_vel_dir * SWIRL_SPEED_INWARD_INITIAL
        // --- End Swirl Velocities ---

        // Combine cloud drift + relative swirl components for the final initial velocity
        start_vel := cloud_travel_vel + orbital_vel + inward_vel

        start_angular_vel := (rand.float32() * 2.0 - 1.0) * MAX_SPIN_SPEED * 2.5

		emit_particle(Particle{
			pos=start_pos,
            vel=start_vel,
            cloud_travel_vel=cloud_travel_vel, // Store the calculated cloud travel velocity
            color=start_color,
            size=start_size_val,
            start_size=start_size_val,
			life_remaining=charge_duration,
            life_max=charge_duration,
            swirl_duration=charge_duration,   // <-- STORE the original swirl duration
            rotation=rand.float32()*f32(m.TAU),
            angular_vel=start_angular_vel,
            charge_center_pos=charge_spawn_center, // Store initial spawn center
            is_burst_particle=false,
            is_swirling_charge=true,
            active=false, // emit_particle will set this true
		})
	}
}
// Modified update function
update_and_instance_particles :: proc(dt: f32) -> int {
    context = runtime.default_context()

    // --- Get Screen Boundaries (World Coordinates) ---
    // NOTE: Recalculating here. Alternatively, pass them from frame() or store in state.
    width := sapp.widthf()
    height := sapp.heightf()
    aspect := width / height
    ortho_width := ORTHO_HEIGHT * aspect

    // Base boundaries (center point)
    min_x_bound : f32 = -ortho_width
    max_x_bound : f32 =  ortho_width
    min_y_bound : f32 = -ORTHO_HEIGHT
    max_y_bound : f32 =  ORTHO_HEIGHT
    // ---

    live_particle_count := 0
    for i in 0..<MAX_PARTICLES {
        if !state.particles[i].active { continue }

        p := &state.particles[i]

        // --- Store original position before update (optional, for debugging) ---
        // old_pos := p.pos

        // --- Update Position based on current velocity ---
        p.pos += p.vel * dt
        p.rotation += p.angular_vel * dt // Keep rotation update separate

        // --- Boundary Collision Check and Response ---
        half_size := p.size * 0.5 // Particle "radius" assuming quad from -0.5 to 0.5

        // Check Left Boundary
        if p.pos.x - half_size < min_x_bound {
            p.pos.x = min_x_bound + half_size // Reposition inside
            p.vel.x *= -1.0                  // Reflect horizontal velocity
            // Optional: Dampen velocity on bounce
            // p.vel *= 0.9
        } // Check Right Boundary
        else if p.pos.x + half_size > max_x_bound {
            p.pos.x = max_x_bound - half_size // Reposition inside
            p.vel.x *= -1.0                  // Reflect horizontal velocity
            // Optional: Dampen velocity on bounce
            // p.vel *= 0.9
        } // Check Bottom Boundary
        if p.pos.y - half_size < min_y_bound {
            p.pos.y = min_y_bound + half_size // Reposition inside
            p.vel.y *= -1.0                  // Reflect vertical velocity
            // Optional: Dampen velocity on bounce
            // p.vel *= 0.9
        } // Check Top Boundary
        else if p.pos.y + half_size > max_y_bound {
            p.pos.y = max_y_bound - half_size // Reposition inside
            p.vel.y *= -1.0                  // Reflect vertical velocity
            // Optional: Dampen velocity on bounce
            // p.vel *= 0.9
        }
        // --- End Boundary Check ---


        // --- Update Lifetime & Check for State Transition/Death ---
        // (This logic remains AFTER position/bounce updates)
        p.life_remaining -= dt

        // Check if Swirl Phase Ends and Transition to Explosion
        if p.is_swirling_charge && p.life_remaining <= 0.0 {
            p.is_swirling_charge = false // Transition state to explosion

            new_life := EXPLOSION_LIFETIME_BASE + rand.float32() * EXPLOSION_LIFETIME_RAND
            p.life_remaining = new_life
            p.life_max = new_life

            explosion_center := p.charge_center_pos + p.cloud_travel_vel * p.swirl_duration

            relative_pos := p.pos - explosion_center
            outward_dir : m.vec2 = {rand.float32() * 2.0 - 1.0, rand.float32() * 2.0 - 1.0}
            len_sq := m.len_sq_vec2(relative_pos)
            if len_sq > 0.0001 {
                 outward_dir = relative_pos / math.sqrt(len_sq)
            } else if m.len_sq_vec2(outward_dir) > 0.0001 {
                 outward_dir = m.norm_vec2(outward_dir)
            } else {
                 outward_dir = {0.0, 1.0}
            }

            explosion_speed := EXPLOSION_SPEED_BASE + rand.float32() * EXPLOSION_SPEED_RAND
            p.vel = outward_dir * explosion_speed // Overwrite velocity for explosion
            p.angular_vel = EXPLOSION_PARTICLE_SPIN
        }

        // Check if Exploding Particle Dies
        if !p.is_swirling_charge && p.life_remaining <= 0.0 {
            p.active = false
            continue // Skip visual update and instancing
        }
        // --- End Lifetime/State Check ---

        // --- Update Visuals (Size/Alpha) ---
        life_ratio: f32 = 0.0
        if p.life_max > 0.0 {
            life_ratio = math.max(f32(0.0), p.life_remaining / p.life_max)
        }

		if p.is_swirling_charge {
            p.size = p.start_size
            p.color.a = 1.0
        } else {
			p.size = p.start_size * life_ratio * life_ratio;
			p.color.a = life_ratio * life_ratio;
		}
        // --- End Visual Update ---

        // --- Copy data to instance buffer ---
		if live_particle_count < MAX_PARTICLES {
			inst := &state.particle_instance_data[live_particle_count];
			inst.instance_pos = p.pos; // Use the potentially adjusted position
            inst.instance_size = p.size;
            inst.instance_rotation = p.rotation;
            inst.instance_color = p.color;
			live_particle_count += 1;
		}
	}
	return live_particle_count
}

// =============================================================================
// END: Particle Helper Functions
// =============================================================================


frame :: proc "c" () {
    context = runtime.default_context()

    // --- Timing and Basic Setup ---
    width := sapp.widthf()
    height := sapp.heightf()
    aspect := width / height
    current_time := f32(sapp.frame_count()) / 60.0 // Simple time based on frames
    delta_time := f32(sapp.frame_duration())
    delta_time = math.min(delta_time, 1.0/15.0) // Clamp delta time to avoid large jumps (frame limiter)

    // --- Update Cooldowns ---
    state.rmb_cooldown_timer = math.max(0.0, state.rmb_cooldown_timer - delta_time)

    // --- Player Input Handling ---
    accel_input := m.vec2_zero()
    if state.key_w_down { accel_input.y += 1.0 }
    if state.key_s_down { accel_input.y -= 1.0 }
    if state.key_a_down { accel_input.x -= 1.0 }
    if state.key_d_down { accel_input.x += 1.0 }

    // Normalize input vector if diagonal movement
    if m.len_sq_vec2(accel_input) > 0.001 {
        accel_input = m.norm_vec2(accel_input)
    }

    // --- Player Physics Update ---
    // Calculate acceleration force
    final_accel := accel_input * PLAYER_ACCELERATION
    // Apply reverse thrust modifier if only 'S' is pressed
    if state.key_s_down && !state.key_w_down && accel_input.y < -0.5 {
        final_accel *= PLAYER_REVERSE_FACTOR
    }

    // Apply acceleration to velocity
    state.player_vel += final_accel * delta_time

    // Apply damping (friction)
    damping_factor := math.max(0.0, 1.0 - PLAYER_DAMPING * delta_time)
    state.player_vel *= damping_factor

    // Clamp velocity to max speed
    if m.len_sq_vec2(state.player_vel) > f32(PLAYER_MAX_SPEED * PLAYER_MAX_SPEED) {
        state.player_vel = m.norm_vec2(state.player_vel) * PLAYER_MAX_SPEED
    }

    // Update position based on velocity
    state.player_pos += state.player_vel * delta_time

    // --- Player Boundary Clamping ---
    ortho_width : f32 = ORTHO_HEIGHT * aspect // Calculate world space horizontal extent
    player_half_extent : f32 = PLAYER_SCALE * 0.7   // Half the visual size based on scale

    min_x : f32 = -ortho_width + player_half_extent
    max_x : f32 =  ortho_width - player_half_extent
    min_y : f32 = -ORTHO_HEIGHT + player_half_extent
    max_y : f32 =  ORTHO_HEIGHT - player_half_extent

    state.player_pos.x = math.clamp(state.player_pos.x, min_x, max_x)
    state.player_pos.y = math.clamp(state.player_pos.y, min_y, max_y)

    // --- Right Mouse Button Ability ---
    can_fire_rmb := state.rmb_cooldown_timer <= 0.0
    rmb_pressed_this_frame := state.rmb_down && !state.previous_rmb_down

    if rmb_pressed_this_frame && can_fire_rmb {
        spawn_swirling_charge() // Call the function to spawn particles
        // Start cooldown if applicable
        if BLACKHOLE_COOLDOWN_DURATION > 0.0 {
            state.rmb_cooldown_timer = BLACKHOLE_COOLDOWN_DURATION
        }
    }
    state.previous_rmb_down = state.rmb_down // Track state for next frame

    // --- Update Shader Uniforms ---
    state.bg_fs_params = { tick = current_time, resolution = {width, height}, bg_option = 1 }
    state.player_fs_params = { tick = current_time, resolution = {width, height} }
    state.particle_fs_params = { tick = current_time }

    // --- Calculate Matrices ---
    // Projection matrix (Orthographic)
    proj := m.ortho(-ortho_width, ortho_width, -ORTHO_HEIGHT, ORTHO_HEIGHT, -1.0, 1.0)
    // View matrix (Identity for 2D top-down)
    view := m.identity()
    // Combined View-Projection matrix
    view_proj := m.mul(proj, view)

    // Player Model matrix (Scale * Translation)
    // NOTE: Uses the *clamped* state.player_pos
    scale_mat := m.scale(m.vec3{PLAYER_SCALE, PLAYER_SCALE, 1.0})
    translate_mat := m.translate(m.vec3{state.player_pos.x, state.player_pos.y, 0.0})
    model := m.mul(translate_mat, scale_mat)

    // Final Model-View-Projection matrix for the player
    state.player_vs_params.mvp = m.mul(view_proj, model)
    // View-Projection matrix for particles (applied in vertex shader)
    state.particle_vs_params.view_proj = view_proj

    // --- Update Particles ---
    state.num_active_particles = update_and_instance_particles(delta_time)

    // --- Rendering ---
    sg.begin_pass({ action = state.pass_action, swapchain = sglue.swapchain() })

    // Draw Background
    sg.apply_pipeline(state.bg_pip)
    sg.apply_bindings(state.bind) // Uses the shared quad VBO
    sg.apply_uniforms(UB_bg_fs_params, sg.Range{ptr = &state.bg_fs_params, size = size_of(Bg_Fs_Params)})
    sg.draw(0, 4, 1) // Draw 1 instance of the quad

    // Draw Player
    sg.apply_pipeline(state.player_pip)
    sg.apply_bindings(state.bind) // Uses the shared quad VBO
    sg.apply_uniforms(UB_Player_Vs_Params, sg.Range{ptr = &state.player_vs_params, size = size_of(Player_Vs_Params)})
    sg.apply_uniforms(UB_Player_Fs_Params, sg.Range{ptr = &state.player_fs_params, size = size_of(Player_Fs_Params)})
    sg.draw(0, 4, 1) // Draw 1 instance of the quad

    // Draw Particles (if any are active)
    if state.num_active_particles > 0 {
        sg.apply_pipeline(state.particle_pip)
        sg.apply_bindings(state.particle_bind) // Binds particle quad VBO and instance data VBO

        // Update the instance data buffer with current particle states
        sg.update_buffer(
            state.particle_instance_vbo,
            sg.Range{
                ptr = rawptr(&state.particle_instance_data[0]),
                size = uint(state.num_active_particles) * size_of(Particle_Instance_Data),
            },
        )

        // Apply particle uniforms
        sg.apply_uniforms(UB_particle_vs_params, sg.Range{ptr = &state.particle_vs_params, size = size_of(Particle_Vs_Params)})
        sg.apply_uniforms(UB_particle_fs_params, sg.Range{ptr = &state.particle_fs_params, size = size_of(Particle_Fs_Params)})

        // Draw particles (instanced rendering)
        sg.draw(0, 4, state.num_active_particles) // Draw quad base, instanced N times
    }

    // End Rendering Pass and Commit
    sg.end_pass()
    sg.commit()
}

cleanup :: proc "c" () { context=runtime.default_context(); sg.shutdown(); }
main :: proc () { sapp.run({ init_cb=init, frame_cb=frame, cleanup_cb=cleanup, event_cb=event, width=800, height=600, sample_count=4, window_title="GeoWars Odin - Traveling Swirl", icon={sokol_default=true}, logger={func=slog.func} }) }