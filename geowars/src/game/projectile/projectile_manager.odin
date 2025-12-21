package projectile

import "core:math"
import "core:fmt"
import sg "../../vendor/sokol/gfx"
import m "../../vendor/math"
import shared "../../shared"

MAX_BLACKHOLES :: 64
PROJECTILE_BLACKHOLE_INITIAL_SPEED :: 12.0 // Boosted for pace (was 5.0, user requested faster)
PROJECTILE_BLACKHOLE_LIFETIME :: 3.0
PROJECTILE_BLACKHOLE_SCALE :: 0.12

ProjectileManager :: struct {
    blackholes: [MAX_BLACKHOLES]shared.Blackhole_Projectile,
    blackhole_instance_data: [MAX_BLACKHOLES]shared.Blackhole_Instance_Data,
    blackhole_instance_vbo: sg.Buffer,
    blackhole_bind: sg.Bindings,
    next_blackhole_index: int,
    num_active_blackholes: int,
    pipeline: sg.Pipeline,
}

init :: proc(manager: ^ProjectileManager, pip: sg.Pipeline, bind: sg.Bindings) {
    manager.pipeline = pip
    // Create VBO for instances
    manager.blackhole_instance_vbo = sg.make_buffer({
        label="blackhole-inst",
        size=MAX_BLACKHOLES*size_of(shared.Blackhole_Instance_Data),
        type=.VERTEXBUFFER,
        usage=.STREAM
    })

    // Copy the bind and replace the instance buffer
    manager.blackhole_bind = bind
    manager.blackhole_bind.vertex_buffers[1] = manager.blackhole_instance_vbo

    manager.next_blackhole_index = 0
    manager.num_active_blackholes = 0
}

spawn_blackhole :: proc(manager: ^ProjectileManager, pos: m.vec2, vel: m.vec2) {
    idx := manager.next_blackhole_index

    // Calculate rotation based on velocity
    rotation_angle := math.atan2(vel.y, vel.x) - m.PI / 2.0

    manager.blackholes[idx] = shared.Blackhole_Projectile {
        pos = pos,
        vel = vel,
        size = PROJECTILE_BLACKHOLE_SCALE,
        rotation = rotation_angle,
        angular_vel = 0,
        life_remaining = PROJECTILE_BLACKHOLE_LIFETIME,
        life_max = PROJECTILE_BLACKHOLE_LIFETIME,
        active = true,
    }

    manager.next_blackhole_index = (manager.next_blackhole_index + 1) % MAX_BLACKHOLES
}

update :: proc(manager: ^ProjectileManager, dt: f32) {
    live_count := 0
    for i in 0..<MAX_BLACKHOLES {
        if !manager.blackholes[i].active { continue }

        p := &manager.blackholes[i]
        p.life_remaining -= dt
        if p.life_remaining <= 0.0 {
            p.active = false
            continue
        }

        p.pos += p.vel * dt
        p.rotation += p.angular_vel * dt

        // Wrap rotation
        if p.rotation > m.TAU { p.rotation -= m.TAU }
        if p.rotation < 0    { p.rotation += m.TAU }

        // Instance Data
        life_ratio := p.life_remaining / p.life_max
        if live_count < MAX_BLACKHOLES {
            inst := &manager.blackhole_instance_data[live_count]
            inst.instance_pos_size_rot = {p.pos.x, p.pos.y, p.size, p.rotation}
            inst.instance_color = {1.0, 1.0, 1.0, life_ratio}
            live_count += 1
        }
    }
    manager.num_active_blackholes = live_count
}

draw :: proc(manager: ^ProjectileManager, vs_params: ^shared.Blackhole_Vs_Params, fs_params: ^shared.Blackhole_Fs_Params) {
    if manager.num_active_blackholes > 0 {
        sg.apply_pipeline(manager.pipeline)
        sg.apply_bindings(manager.blackhole_bind)

        // Update instance buffer
        sg.update_buffer(manager.blackhole_instance_vbo, sg.Range{
            ptr=rawptr(&manager.blackhole_instance_data[0]),
            size=uint(manager.num_active_blackholes)*size_of(shared.Blackhole_Instance_Data)
        })

        sg.apply_uniforms(shared.UB_blackhole_vs_params, sg.Range{ptr=vs_params, size=size_of(shared.Blackhole_Vs_Params)})
        sg.apply_uniforms(shared.UB_blackhole_fs_params, sg.Range{ptr=fs_params, size=size_of(shared.Blackhole_Fs_Params)})

        sg.draw(0, 4, manager.num_active_blackholes)
    }
}
