package ui

import "core:fmt"
import "core:strings"
import shared "../shared"
import slog "../vendor/sokol/log"
import sg "../vendor/sokol/gfx"
import sdtx "../vendor/sokol/debugtext"
import m "../vendor/math"
import sapp "../vendor/sokol/app"

// HUD State using DebugText for now as "Vector HUD" might require full shape rendering which is complex.
// The user said "Vector HUD", implying lines.
// But "Visual hits" implies feedback.
// Let's use DebugText for Score and Wave, and standard shapes (Quads) for HP for now?
// Or just DebugText for everything for simplicity in "Vertical Slice".
// No, "WOW" aesthetics request suggests actual shapes.
// I will render the HUD using the `player_pip` or a new `ui_pip`.
// For speed, let's reuse `sdtx` for Text and `shared`-like quads for HP bars.
// Actually, `sdtx` is for debug text.
// If I want "Premium", I should use the vector engine (lines).
// But I don't have a line renderer exposed easily yet (only quads).
// I will use `sdtx` for valid info first, then maybe polish. 
// "Vector HUD" -> `sdtx` text looks like vector text.

init_hud :: proc() {
    desc := sdtx.Desc{
        fonts = {
            0 = sdtx.font_kc853(), // Retro computer style
        },
    }
    sdtx.setup(desc)
}

draw_hud :: proc(game_state: ^shared.GameState) {
    sdtx.canvas(sapp.widthf() * 0.5, sapp.heightf() * 0.5)
    sdtx.origin(1.0, 1.0)
    
    // --- Score ---
    sdtx.color3f(0.1, 0.9, 0.9)
    sdtx.pos(1.0, 1.0)
    
    // Since we don't have a format string helper readily available in `sdtx`, we use `fmt.bprintf` and a buffer.
    // Or just `sdtx.puts`.
    
    // Score Top Center
    // We need to center it. Coordinates are grid based?
    // sdtx uses grid coords.
    // Let's print Score.
    
    buf: [64]u8
    
    // "SCORE: 0000"
    // Using `fmt` to format string
    s := fmt.tprintf("SCORE: %06d", game_state.score)
    
    // Center approx: Width 800 -> ~100 chars?
    sdtx.pos(35, 2)
    sdtx.puts(strings.clone_to_cstring(s, context.temp_allocator))

    // --- Wave / Time ---
    sdtx.pos(35, 4)
    wave_s := fmt.tprintf("WAVE: %d", game_state.progression.current_stage_index + 1)
    sdtx.puts(strings.clone_to_cstring(wave_s, context.temp_allocator))

    // --- HP Bar ---
    // Draw "HP" text and then Segments?
    sdtx.pos(2, 2)
    sdtx.color3f(1.0, 0.2, 0.2)
    hp_s := fmt.tprintf("HP:")
    sdtx.puts(strings.clone_to_cstring(hp_s, context.temp_allocator))

    // Draw HP Segments
    for i in 0..<game_state.player.hp {
        sdtx.pos(f32(6 + i*2), 2)
        sdtx.puts("||")
    }

    sdtx.draw()
}

shutdown_hud :: proc() {
    sdtx.shutdown()
}
