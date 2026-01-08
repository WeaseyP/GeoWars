package grid

import sg "../../vendor/sokol/gfx"
import m "../../vendor/math"
import shared "../../shared"
import "core:math"
import rand "core:math/rand"

// --- Constants ---
GRID_COLS :: 40
GRID_ROWS :: 30
GRID_SPACING :: 1.0 // Adjust based on Arena Size (30x20) -> maybe 30 cols, 20 rows?
// With 30 width: 40 cols -> 0.75 spacing.
// Let's ensure it covers ARENA_WIDTH/HEIGHT (+ margin).

POINT_MASS :: 1.0
SPRING_STIFFNESS :: 15.0
DAMPING :: 6.0

GridPoint :: struct {
    pos: m.vec2,
    base_pos: m.vec2,
    vel: m.vec2,
    // Neighbors? Implicit grid.
}

Grid :: struct {
    points: [GRID_COLS][GRID_ROWS]GridPoint,
    cols: int,
    rows: int,
}

init_grid :: proc() -> Grid {
    g: Grid
    g.cols = GRID_COLS
    g.rows = GRID_ROWS

    // Center grid in arena
    start_x := -(f32(GRID_COLS) * GRID_SPACING) * 0.5
    start_y := -(f32(GRID_ROWS) * GRID_SPACING) * 0.5

    for y in 0..<GRID_ROWS {
        for x in 0..<GRID_COLS {
            pos := m.vec2{
                start_x + f32(x) * GRID_SPACING,
                start_y + f32(y) * GRID_SPACING,
            }
            g.points[x][y] = GridPoint{
                pos = pos,
                base_pos = pos,
                vel = {0, 0},
            }
        }
    }
    return g
}

update_grid :: proc(g: ^Grid, dt: f32) {
    for y in 0..<g.rows {
        for x in 0..<g.cols {
            p := &g.points[x][y]

            // Spring force towards base
            displacement := p.pos - p.base_pos
            spring_force := -displacement * SPRING_STIFFNESS

            // Damping force
            damping_force := -p.vel * DAMPING

            total_force := spring_force + damping_force
            accel := total_force / POINT_MASS

            p.vel += accel * dt
            p.pos += p.vel * dt
        }
    }
}

apply_force :: proc(g: ^Grid, pos: m.vec2, force: f32, radius: f32) {
    for y in 0..<g.rows {
        for x in 0..<g.cols {
            p := &g.points[x][y]
            
            // Vector from explosion center to point
            dir := p.pos - pos
            dist_sq := m.len_sq_vec2(dir)
            
            if dist_sq < radius * radius {
                dist := math.sqrt(dist_sq)
                // Force falls off with distance
                // Normalized dir
                n_dir := m.vec2{0,1} // Default
                if dist > 0.001 {
                    n_dir = dir * (1.0 / dist)
                }

                // Impulse
                // 1.0 at center, 0.0 at radius
                pct := 1.0 - (dist / radius)
                if pct < 0.0 do pct = 0.0
                
                // Classic inverse square or linear? Linear is cleaner for "shockwave"
                impulse := n_dir * force * pct
                p.vel += impulse
            }
        }
    }
}

// In geowars legacy, lines were drawn with immediate mode.
// Here we might need to push vertices to a buffer.
// For now, let's assume we have a simple line renderer or we construct line vertices.
// We'll return a list of line segments to be drawn by geowars.odin using a line pipeline?
// Or we can just interact with `sg` if we share the pipeline?

// For simplicity, let's expose specific functions to get vertices.

get_grid_line_vertices :: proc(g: ^Grid, vertices: ^[dynamic]shared.Vertex) {
    // Horizontal lines
    for y in 0..<g.rows {
        for x in 0..<g.cols-1 {
            p1 := g.points[x][y]
            p2 := g.points[x+1][y]
            
            // Color based on displacement?
            c1 := get_color_for_point(p1)
            c2 := get_color_for_point(p2)

            append(vertices, shared.Vertex{pos = {p1.pos.x, p1.pos.y, 0}, color = c1})
            append(vertices, shared.Vertex{pos = {p2.pos.x, p2.pos.y, 0}, color = c2})
        }
    }

    // Vertical lines
    for x in 0..<g.cols {
        for y in 0..<g.rows-1 {
            p1 := g.points[x][y]
            p2 := g.points[x][y+1]
            
            c1 := get_color_for_point(p1)
            c2 := get_color_for_point(p2)

            append(vertices, shared.Vertex{pos = {p1.pos.x, p1.pos.y, 0}, color = c1})
            append(vertices, shared.Vertex{pos = {p2.pos.x, p2.pos.y, 0}, color = c2})
        }
    }
}

get_color_for_point :: proc(p: GridPoint) -> m.vec4 {
    // Base color: Dark Blue
    base := m.vec4{0.1, 0.1, 0.3, 0.3} 
    
    // Brighten based on displacement velocity
    disp := m.len_sq_vec2(p.pos - p.base_pos)
    v := m.len_sq_vec2(p.vel)
    
    energy := disp + v * 0.1
    amount := math.clamp(energy * 2.0, 0.0, 1.0)
    
    // Mix with Bright Cyan
    highlight := m.vec4{0.2, 0.8, 1.0, 0.8}
    return m.lerp(base, highlight, amount)
}
