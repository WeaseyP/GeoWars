package main
import m "../math"
import "base:runtime"
import sapp "../sokol/app"
import rand "core:math/rand"
import "core:math"



// --- Black Hole Projectile System (LMB Weapon) ---
emit_blackhole_projectile :: proc(proj: Blackhole_Projectile) {
    context = runtime.default_context()
    state.blackholes[state.next_blackhole_index] = proj
    state.blackholes[state.next_blackhole_index].active = true
    state.next_blackhole_index = (state.next_blackhole_index + 1) % MAX_BLACKHOLES
}

get_mouse_world_pos :: proc() -> m.vec2 {
    context = runtime.default_context()
    screen_width_mouse := sapp.widthf() // Renamed
    screen_height_mouse := sapp.heightf() // Renamed
    ndc_x_mouse := (2.0 * state.mouse_screen_pos.x / screen_width_mouse) - 1.0 // Renamed
    ndc_y_mouse := 1.0 - (2.0 * state.mouse_screen_pos.y / screen_height_mouse) // Renamed
    aspect_ratio_mouse := screen_width_mouse / screen_height_mouse // Renamed
    ortho_width_vp_mouse := ORTHO_HEIGHT * aspect_ratio_mouse // Renamed
    world_x_mouse := ndc_x_mouse * ortho_width_vp_mouse // Renamed
    world_y_mouse := ndc_y_mouse * ORTHO_HEIGHT // Renamed
    return {world_x_mouse, world_y_mouse}
}

spawn_blackhole_projectile_weapon :: proc() {
    context = runtime.default_context()
    if state.player_hp <= 0 { return; } 
    spawn_pos_bhpw := state.player_pos // Renamed
    target_world_pos_bhpw := get_mouse_world_pos() // Renamed
    direction_to_mouse_bhpw := target_world_pos_bhpw - spawn_pos_bhpw // Renamed
    direction_bhpw: m.vec2 // Renamed
    if m.len_sq_vec2(direction_to_mouse_bhpw) > 0.0001 { 
        direction_bhpw = m.norm_vec2(direction_to_mouse_bhpw)
    } else {
        if m.len_sq_vec2(state.player_vel) > 0.001 { direction_bhpw = m.norm_vec2(state.player_vel)
        } else { direction_bhpw = {0, 1} }
    }
    vel_bhpw := direction_bhpw * PROJECTILE_BLACKHOLE_INITIAL_SPEED // Renamed
    life_bhpw := f32(PROJECTILE_BLACKHOLE_LIFETIME) // Renamed
    rotation_angle_bhpw := math.atan2(direction_bhpw.y, direction_bhpw.x) - m.PI / 2.0 // Renamed
    new_proj_bhpw := Blackhole_Projectile { // Renamed
        pos = spawn_pos_bhpw, vel = vel_bhpw, size = PROJECTILE_BLACKHOLE_SCALE, rotation = rotation_angle_bhpw, 
        angular_vel = 0, life_remaining = life_bhpw, life_max = life_bhpw, active = false, 
    }
    emit_blackhole_projectile(new_proj_bhpw)
}

update_and_instance_blackholes :: proc(dt: f32) -> int {
    context = runtime.default_context()
    live_count_bh := 0 // Renamed
    for i in 0..<MAX_BLACKHOLES {
        if !state.blackholes[i].active { continue }
        p_bh := &state.blackholes[i] // Renamed
        p_bh.life_remaining -= dt
        if p_bh.life_remaining <= 0.0 { p_bh.active = false; continue }
        p_bh.pos += p_bh.vel * dt
        p_bh.rotation += p_bh.angular_vel * dt // This was 0 from spawn, but could be used
        if p_bh.rotation > m.TAU { p_bh.rotation -= m.TAU }
        if p_bh.rotation < 0    { p_bh.rotation += m.TAU }
        life_ratio_bh := p_bh.life_remaining / p_bh.life_max // Renamed
        if live_count_bh < MAX_BLACKHOLES {
            inst_bh := &state.blackhole_instance_data[live_count_bh] // Renamed
            inst_bh.instance_pos_size_rot = {p_bh.pos.x, p_bh.pos.y, p_bh.size, p_bh.rotation}
            inst_bh.instance_color = {1.0, 1.0, 1.0, life_ratio_bh} 
            live_count_bh += 1
        }
    }
    return live_count_bh
}
