package shop

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:strings"
import rand "core:math/rand"
import sdtx "../../vendor/sokol/debugtext"
import shared "../../shared"


// --- Shop module ---
// Opens a "pick 1 of 3" upgrade screen between certain waves. While the shop is open the world
// updates are paused (game_mode = .SHOP). When the player picks a card, that upgrade is applied
// to shared.state.eff_* mirrors and game_mode flips back to .PLAYING.

// ---------- Upgrade catalog ----------

UpgradeDef :: struct {
    id:              shared.UpgradeID,
    tier:            int,    // 1=common, 2=uncommon, 3=rare
    name:            string,
    desc:            string,
    apply:           proc(),
}

@(private)
apply_max_hp_plus_1 :: proc() {
    shared.state.player_max_hp += 1
    shared.state.player_hp     += 1
    if shared.state.player_hp > shared.state.player_max_hp { shared.state.player_hp = shared.state.player_max_hp }
}

@(private)
apply_max_hp_plus_2_full_heal :: proc() {
    shared.state.player_max_hp += 2
    shared.state.player_hp = shared.state.player_max_hp
}

@(private)
apply_lmb_damage_plus_1 :: proc() { shared.state.eff_lmb_damage += 1 }

@(private)
apply_lmb_damage_plus_2 :: proc() { shared.state.eff_lmb_damage += 2 }

@(private)
apply_lmb_rapid_fire :: proc() { shared.state.eff_lmb_cooldown *= 0.7 }

// When max_charge grows we scale charge_rate by the same ratio so time-to-100% stays
// roughly constant; otherwise stacking max-charge upgrades silently makes the meter feel
// broken in late rounds (a 50% bigger bar at the same fill rate is a 50% slower meter).
@(private)
scale_rmb_max_charge :: proc(delta: f32) {
    old_max := shared.state.eff_rmb_max_charge
    new_max := old_max + delta
    if old_max > 0.0 {
        shared.state.eff_rmb_charge_rate *= new_max / old_max
    }
    shared.state.eff_rmb_max_charge = new_max
}

@(private)
apply_rmb_extra_charge :: proc() { scale_rmb_max_charge(0.5) }

@(private)
apply_rmb_fast_regen :: proc() { shared.state.eff_rmb_charge_rate *= 1.5 }

@(private)
apply_rmb_instant_refill :: proc() {
    shared.state.rmb_charge = shared.state.eff_rmb_max_charge
}

@(private)
apply_rmb_overcharge :: proc() {
    scale_rmb_max_charge(1.0)
    shared.state.eff_rmb_damage_mult *= 1.4
}

@(private)
apply_max_speed_plus :: proc() { shared.state.eff_player_max_speed *= 1.15 }

@(private)
apply_fast_dash :: proc() { shared.state.eff_dash_cooldown *= 0.6 }

@(private)
apply_tough_skin :: proc() {
    shared.state.eff_invul_duration *= 1.35
    shared.state.player_max_hp += 1
    shared.state.player_hp     += 1
    if shared.state.player_hp > shared.state.player_max_hp { shared.state.player_hp = shared.state.player_max_hp }
}

// Master catalog. Index doesn't matter; we filter/weight by tier when rolling.
upgrade_catalog := [?]UpgradeDef{
    { .MAX_HP_PLUS_1,            1, "Tougher Hide",   "+1 max HP. Heals +1.",                       apply_max_hp_plus_1            },
    { .LMB_RAPID_FIRE,           1, "Quick Hands",    "LMB cooldown -30%.",                         apply_lmb_rapid_fire           },
    { .RMB_EXTRA_CHARGE,         1, "Bigger Bits",    "RMB max charge +50%; refill time unchanged.", apply_rmb_extra_charge        },
    { .RMB_FAST_REGEN,           1, "Quick Recharge", "RMB charges 50% faster.",                    apply_rmb_fast_regen           },
    { .MAX_SPEED_PLUS,           1, "Brisk",          "Max speed +15%.",                            apply_max_speed_plus           },
    { .FAST_DASH,                1, "Cooled Dash",    "Dash cooldown -40%.",                        apply_fast_dash                },

    { .LMB_DAMAGE_PLUS_1,        2, "Sharper Bullets","LMB damage +1.",                             apply_lmb_damage_plus_1        },
    { .RMB_INSTANT_REFILL,       2, "Topped Off",     "Fill RMB charge to max NOW.",                apply_rmb_instant_refill       },
    { .TOUGH_SKIN,               2, "Iron Skin",      "Invul +35%, +1 max HP.",                     apply_tough_skin               },

    { .LMB_DAMAGE_PLUS_2,        3, "Hot Shot",       "LMB damage +2.",                             apply_lmb_damage_plus_2        },
    { .MAX_HP_PLUS_2_FULL_HEAL,  3, "Steadfast",      "+2 max HP. Full heal.",                      apply_max_hp_plus_2_full_heal  },
    { .RMB_OVERCHARGE,           3, "Overcharge",     "RMB max +100% & damage +40%; refill time same.", apply_rmb_overcharge       },
}

@(private)
find_upgrade :: proc(id: shared.UpgradeID) -> ^UpgradeDef {
    for &u in upgrade_catalog {
        if u.id == id { return &u }
    }
    return nil
}

upgrade_name :: proc(id: shared.UpgradeID) -> string {
    if u := find_upgrade(id); u != nil { return u.name }
    return ""
}

upgrade_desc :: proc(id: shared.UpgradeID) -> string {
    if u := find_upgrade(id); u != nil { return u.desc }
    return ""
}

upgrade_tier :: proc(id: shared.UpgradeID) -> int {
    if u := find_upgrade(id); u != nil { return u.tier }
    return 0
}

// ---------- Roll & apply ----------

// Tier weight depends on which shop this is. Pre-boss shop biases hard toward higher tiers.
@(private)
tier_weight :: proc(tier: int, is_pre_boss: bool) -> int {
    if is_pre_boss {
        switch tier {
        case 1: return 1
        case 2: return 4
        case 3: return 5
        }
    } else {
        switch tier {
        case 1: return 6
        case 2: return 3
        case 3: return 1
        }
    }
    return 0
}

// Roll 3 distinct upgrades. Selection is weighted by tier and by pre-boss flag.
roll_shop :: proc(is_pre_boss: bool) -> [3]shared.UpgradeID {
    context = runtime.default_context()
    out: [3]shared.UpgradeID
    out[0] = .NONE; out[1] = .NONE; out[2] = .NONE

    picked_count := 0
    // Build a candidate pool (id, weight) and pick without replacement.
    candidates := make([dynamic]struct{id: shared.UpgradeID, w: int}, context.temp_allocator)
    for u in upgrade_catalog {
        w := tier_weight(u.tier, is_pre_boss)
        if w > 0 { append(&candidates, struct{id: shared.UpgradeID, w: int}{u.id, w}) }
    }

    for picked_count < 3 && len(candidates) > 0 {
        total := 0
        for c in candidates { total += c.w }
        if total <= 0 { break }
        roll := int(rand.float32() * f32(total))
        cum := 0
        chosen_idx := 0
        for c, idx in candidates {
            cum += c.w
            if roll < cum { chosen_idx = idx; break }
        }
        out[picked_count] = candidates[chosen_idx].id
        picked_count += 1
        // remove without preserving order
        candidates[chosen_idx] = candidates[len(candidates)-1]
        resize(&candidates, len(candidates)-1)
    }
    return out
}

open_shop :: proc(is_pre_boss: bool) {
    shared.state.shop = shared.ShopState {
        options     = roll_shop(is_pre_boss),
        hovered     = -1,
        is_pre_boss = is_pre_boss,
    }
    shared.state.game_mode = .SHOP
    fmt.printf("--- Shop opened (%s). Picks: %v / %v / %v ---\n",
        is_pre_boss ? "PRE-BOSS" : "regular",
        shared.state.shop.options[0], shared.state.shop.options[1], shared.state.shop.options[2])
}

choose :: proc(slot: int) {
    if shared.state.game_mode != .SHOP { return }
    if slot < 0 || slot >= 3 { return }
    id := shared.state.shop.options[slot]
    if id == .NONE { return }
    if u := find_upgrade(id); u != nil && u.apply != nil {
        u.apply()
        fmt.printf("--- Upgrade chosen: %s. ---\n", u.name)
    }
    shared.state.wave_system.shops_offered += 1
    shared.state.game_mode = .PLAYING
    shared.state.shop.hovered = -1
}

// Per-frame update during SHOP mode. Tracks hover (for visual feedback) and reads input picks.
update_shop :: proc(width, height: f32) {
    if shared.state.game_mode != .SHOP { return }

    // --- hover ---
    // Mouse origin: top-left, y down. NDC: x in [-1,1], y in [-1,1] (y up).
    if width > 0 && height > 0 {
        ndc_x := (2.0 * shared.state.mouse_screen_pos.x / width) - 1.0
        ndc_y := 1.0 - (2.0 * shared.state.mouse_screen_pos.y / height)

        card_half_w :: f32(0.20)
        card_half_h :: f32(0.30)
        card_y      :: f32(-0.05)
        centres := [3]f32{ -0.55, 0.0, 0.55 }

        shared.state.shop.hovered = -1
        for cx, idx in centres {
            if math.abs(ndc_x - cx) <= card_half_w && math.abs(ndc_y - card_y) <= card_half_h {
                shared.state.shop.hovered = idx
                break
            }
        }
    }

    // --- input ---
    if shared.state.shop_pick_1 { choose(0); shared.state.shop_pick_1 = false; return }
    if shared.state.shop_pick_2 { choose(1); shared.state.shop_pick_2 = false; return }
    if shared.state.shop_pick_3 { choose(2); shared.state.shop_pick_3 = false; return }
    // Mouse click: a fresh LMB press while hovering a card commits the pick.
    if shared.state.lmb_down && !shared.state.previous_lmb_down {
        if shared.state.shop.hovered >= 0 {
            choose(shared.state.shop.hovered)
        }
    }
}

// ---------- Text rendering (sokol-debugtext) ----------
// Caller is expected to have set sdtx.canvas() and the matching projection. We render the
// header + per-card hotkey + name + wrapped description.

@(private)
print_centered :: proc(text: string, centre_chars_x: f32, y_chars: f32) {
    chars := f32(len(text))
    sdtx.pos(centre_chars_x - chars * 0.5, y_chars)
    cstr := strings.clone_to_cstring(text, context.temp_allocator)
    sdtx.puts(cstr)
}

// Wrap a description into lines of at most max_chars and print them centred at start_y.
@(private)
print_wrapped_centered :: proc(text: string, centre_chars_x: f32, start_y: f32, max_chars: int) {
    if len(text) == 0 { return }
    line_start := 0
    line_count := 0
    for i := 0; i <= len(text); i += 1 {
        // Force a break at the end of the string or whenever we hit a soft limit on a space.
        force_break := i == len(text)
        if !force_break && i - line_start < max_chars { continue }
        // find last space in [line_start, i)
        cut := i
        if !force_break {
            for j := i; j > line_start; j -= 1 {
                if text[j-1] == ' ' { cut = j - 1; break }
            }
        }
        line := text[line_start:cut]
        print_centered(line, centre_chars_x, start_y + f32(line_count))
        line_count += 1
        line_start = cut
        // skip leading spaces on next line
        for line_start < len(text) && text[line_start] == ' ' { line_start += 1 }
        i = line_start
        if line_start >= len(text) { break }
    }
}

// Card layout in CHARACTER coordinates. Canvas is set to (canvas_w, canvas_h) by the caller —
// these are derived to match the shader's NDC card geometry. 8 px per character cell at the
// canvas's pixel scale.
CARD_CENTER_NDC_Y :: f32(-0.05)
CARD_CENTERS_NDC :: [3]f32{ -0.55, 0.0, 0.55 }

render_text :: proc(canvas_w, canvas_h: f32) {
    if shared.state.game_mode != .SHOP { return }
    chars_w := canvas_w / 8.0
    chars_h := canvas_h / 8.0

    // Header
    header := shared.state.shop.is_pre_boss ? "PRE-BOSS UPGRADE  -  PICK ONE" : "PICK AN UPGRADE"
    sdtx.color3b(255, 220, 110)
    print_centered(header, chars_w * 0.5, chars_h * 0.18)

    sub := "1/2/3 keys or click a card"
    sdtx.color3b(170, 170, 200)
    print_centered(sub, chars_w * 0.5, chars_h * 0.18 + 2.0)

    // Cards
    card_y_chars := (1.0 - CARD_CENTER_NDC_Y) * 0.5 * chars_h
    hotkey_y     := card_y_chars - chars_h * 0.18
    name_y       := card_y_chars - chars_h * 0.05
    desc_y       := card_y_chars + chars_h * 0.04
    tier_y       := card_y_chars + chars_h * 0.18

    desc_max_chars := int(chars_w * 0.18) // ~36 chars per line at chars_w=200
    if desc_max_chars < 12 { desc_max_chars = 12 }

    centres := CARD_CENTERS_NDC // copy compile-time constant into a local for indexing
    for i in 0..<3 {
        cx_ndc := centres[i]
        cx_chars := (1.0 + cx_ndc) * 0.5 * chars_w

        id := shared.state.shop.options[i]
        is_hovered := shared.state.shop.hovered == i
        tier := upgrade_tier(id)

        // Hotkey
        hk: string = "[1]"
        if i == 1 { hk = "[2]" } else if i == 2 { hk = "[3]" }
        if is_hovered {
            sdtx.color3b(255, 255, 200)
        } else {
            sdtx.color3b(220, 200, 130)
        }
        print_centered(hk, cx_chars, hotkey_y)

        // Name
        if is_hovered {
            sdtx.color3b(255, 255, 255)
        } else {
            sdtx.color3b(220, 220, 240)
        }
        print_centered(upgrade_name(id), cx_chars, name_y)

        // Description (wrapped)
        sdtx.color3b(170, 170, 200)
        print_wrapped_centered(upgrade_desc(id), cx_chars, desc_y, desc_max_chars)

        // Tier label
        switch tier {
        case 1: sdtx.color3b(110, 200, 250); print_centered("[ COMMON ]",   cx_chars, tier_y)
        case 2: sdtx.color3b(200, 130, 250); print_centered("[ UNCOMMON ]", cx_chars, tier_y)
        case 3: sdtx.color3b(255, 200, 80);  print_centered("[ RARE ]",     cx_chars, tier_y)
        }
    }
}
