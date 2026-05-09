package projectile
import m "../../vendor/math"
import "base:runtime"
import sapp "../../vendor/sokol/app"
import rand "core:math/rand"
import "core:math"
import shared "../../shared"


// --- Black Hole Projectile System (LMB Weapon) ---
emit_blackhole_projectile :: proc(proj: shared.Blackhole_Projectile) {
    context = runtime.default_context()
    shared.state.blackholes[shared.state.next_blackhole_index] = proj
    shared.state.blackholes[shared.state.next_blackhole_index].active = true
    shared.state.next_blackhole_index = (shared.state.next_blackhole_index + 1) % shared.MAX_BLACKHOLES
}

get_mouse_world_pos :: proc() -> m.vec2 {
    context = runtime.default_context()
    screen_width_mouse := sapp.widthf()
    screen_height_mouse := sapp.heightf()
    ndc_x_mouse := (2.0 * shared.state.mouse_screen_pos.x / screen_width_mouse) - 1.0
    ndc_y_mouse := 1.0 - (2.0 * shared.state.mouse_screen_pos.y / screen_height_mouse)
    aspect_ratio_mouse := screen_width_mouse / screen_height_mouse
    ortho_width_vp_mouse := shared.ORTHO_HEIGHT * aspect_ratio_mouse
    // Mouse position in camera-local space, then offset by the camera's world position
    // so the result is the actual world coordinate the mouse is hovering over.
    world_x_mouse := ndc_x_mouse * ortho_width_vp_mouse + shared.state.camera_pos.x
    world_y_mouse := ndc_y_mouse * shared.ORTHO_HEIGHT  + shared.state.camera_pos.y
    return {world_x_mouse, world_y_mouse}
}

spawn_blackhole_projectile_weapon :: proc() {
    context = runtime.default_context()
    if shared.state.player_hp <= 0 { return }
    spawn_pos_bhpw := shared.state.player_pos
    target_world_pos_bhpw := get_mouse_world_pos()
    direction_to_mouse_bhpw := target_world_pos_bhpw - spawn_pos_bhpw
    direction_bhpw: m.vec2
    if m.len_sq_vec2(direction_to_mouse_bhpw) > 0.0001 {
        direction_bhpw = m.norm_vec2(direction_to_mouse_bhpw)
    } else {
        if m.len_sq_vec2(shared.state.player_vel) > 0.001 { direction_bhpw = m.norm_vec2(shared.state.player_vel)
        } else { direction_bhpw = {0, 1} }
    }
    vel_bhpw := direction_bhpw * shared.PROJECTILE_BLACKHOLE_INITIAL_SPEED
    life_bhpw := f32(shared.PROJECTILE_BLACKHOLE_LIFETIME)
    rotation_angle_bhpw := math.atan2(direction_bhpw.y, direction_bhpw.x) - m.PI / 2.0
    new_proj_bhpw := shared.Blackhole_Projectile {
        pos = spawn_pos_bhpw, vel = vel_bhpw, size = shared.PROJECTILE_BLACKHOLE_SCALE, rotation = rotation_angle_bhpw,
        angular_vel = 0, life_remaining = life_bhpw, life_max = life_bhpw, active = false,
    }
    emit_blackhole_projectile(new_proj_bhpw)
}

update_and_instance_blackholes :: proc(dt: f32) -> int {
    context = runtime.default_context()
    live_count_bh := 0
    for i in 0..<shared.MAX_BLACKHOLES {
        if !shared.state.blackholes[i].active { continue }
        p_bh := &shared.state.blackholes[i]
        p_bh.life_remaining -= dt
        if p_bh.life_remaining <= 0.0 { p_bh.active = false; continue }
        p_bh.pos += p_bh.vel * dt
        p_bh.rotation += p_bh.angular_vel * dt
        if p_bh.rotation > m.TAU { p_bh.rotation -= m.TAU }
        if p_bh.rotation < 0    { p_bh.rotation += m.TAU }
        life_ratio_bh := p_bh.life_remaining / p_bh.life_max
        if live_count_bh < shared.MAX_BLACKHOLES {
            inst_bh := &shared.state.blackhole_instance_data[live_count_bh]
            inst_bh.instance_pos_size_rot = {p_bh.pos.x, p_bh.pos.y, p_bh.size, p_bh.rotation}
            inst_bh.instance_color = {1.0, 1.0, 1.0, life_ratio_bh}
            live_count_bh += 1
        }
    }
    return live_count_bh
}
