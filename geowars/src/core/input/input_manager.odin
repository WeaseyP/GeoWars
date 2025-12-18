package input

import sapp "../../vendor/sokol/app"
import m "../../vendor/math"

InputManager :: struct {
    key_w_down: bool,
    key_s_down: bool,
    key_a_down: bool,
    key_d_down: bool,
    key_shift_down: bool,

    lmb_down: bool,
    rmb_down: bool,

    mouse_screen_pos: m.vec2,

    // For edge detection
    prev_lmb_down: bool,
    prev_rmb_down: bool,
}

init :: proc(im: ^InputManager) {
    im.key_w_down = false
    im.key_s_down = false
    im.key_a_down = false
    im.key_d_down = false
    im.key_shift_down = false
    im.lmb_down = false
    im.rmb_down = false
    im.mouse_screen_pos = {0,0}
    im.prev_lmb_down = false
    im.prev_rmb_down = false
}

update :: proc(im: ^InputManager) {
    im.prev_lmb_down = im.lmb_down
    im.prev_rmb_down = im.rmb_down
}

handle_event :: proc(im: ^InputManager, event: ^sapp.Event) {
    #partial switch event.type {
    case .KEY_DOWN:
        #partial switch event.key_code {
            case .W: im.key_w_down = true
            case .S: im.key_s_down = true
            case .A: im.key_a_down = true
            case .D: im.key_d_down = true
            case .LEFT_SHIFT: im.key_shift_down = true
            case .ESCAPE: sapp.request_quit()
        }
    case .KEY_UP:
        #partial switch event.key_code {
            case .W: im.key_w_down = false
            case .S: im.key_s_down = false
            case .A: im.key_a_down = false
            case .D: im.key_d_down = false
            case .LEFT_SHIFT: im.key_shift_down = false
        }
    case .MOUSE_DOWN:
        if event.mouse_button == .RIGHT { im.rmb_down = true }
        if event.mouse_button == .LEFT  { im.lmb_down = true }
    case .MOUSE_UP:
        if event.mouse_button == .RIGHT { im.rmb_down = false }
        if event.mouse_button == .LEFT  { im.lmb_down = false }
    case .MOUSE_MOVE:
        im.mouse_screen_pos = {event.mouse_x, event.mouse_y}
    }
}

get_movement_vector :: proc(im: ^InputManager) -> m.vec2 {
    dir := m.vec2{0, 0}
    if im.key_w_down { dir.y += 1.0 }
    if im.key_s_down { dir.y -= 1.0 }
    if im.key_a_down { dir.x -= 1.0 }
    if im.key_d_down { dir.x += 1.0 }

    if m.len_sq_vec2(dir) > 0.001 {
        return m.norm_vec2(dir)
    }
    return dir
}

lmb_pressed :: proc(im: ^InputManager) -> bool {
    return im.lmb_down && !im.prev_lmb_down
}

rmb_pressed :: proc(im: ^InputManager) -> bool {
    return im.rmb_down && !im.prev_rmb_down
}
