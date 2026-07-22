# GeoWars repo health check

Snapshot taken 2026-05-10, after the big "added a lot of stuff" commit (shop, music, testmode,
shop UI, wave button, snap_sequence harness, screen-space HP feedback). Verdict at a glance:
**healthy with one rendering bug fixed, several real gameplay bugs flagged for follow-up, and
one stale README that needs to catch up to the current game**.

The previous health-check (taken before the shop / music / testmode work) is preserved at
`docs/archive/HEALTH_CHECK_2026-05-pre-shop-music-snapshot.md`. Most of its line-count claims
and "no required refactors" framing are out of date — see "Stale docs" below.

---

## 1. Bug fixed: "old white-oval bullet" was the LMB projectile clipping to white

### Symptom
The new LMB shot was supposed to render as a fancy purple swirl with a glow + trail; instead
it was rendering as a plain white oval (the "old bullet" look). The purple trail particles
showed up correctly behind it; the bullet body itself looked wrong.

### Root cause
`geowars/assets/shaders/shader.glsl`, fragment shader `fs_blackhole`, glow setup:

```glsl
vec3 glow_color = vec3(1.0, 0.7, 1.0) * 5.8; // Very bright, slightly pinkish-purple glow, boosted
```

The `* 5.8` multiplier was sized for an HDR pipeline with bloom — but no bloom or HDR pass
exists. The framebuffer is LDR, so values >1.0 get hard-clipped. The combine step is

```glsl
vec3 final_rgb = body_base_rgb + glow_color * effective_glow_strength;
```

`effective_glow_strength` peaks at ~0.6 around the body's spine, so the glow contribution is
~`(3.5, 2.4, 3.5)` — every channel saturates to 1.0 across the entire body, painting the
projectile flat white. The purple swirl underneath is computed but never visible because the
glow paints over it.

### Fix
Lowered the glow brightness to LDR-safe values so the swirl shows through:

```glsl
// shader.glsl, fs_blackhole
vec3 glow_color = vec3(0.95, 0.55, 1.0) * 1.1;
```

`build.bat` regenerates `shader.odin` and `geowars_windows.exe`; both have been rebuilt with
the fix in this session.

---

## 2. Real bugs to fix later (flagged, NOT touched this pass)

### 2a. Splitter mini-grunts stick together
**Where:** `geowars/src/game/collision/collisions.odin:17-26` (`splitter_spawn_minis`) and
`geowars/src/game/enemy/enemy.odin:248-268` (`update_grunt_alive`).

**What's broken:** `splitter_spawn_minis` correctly spawns three grunts with burst velocities
120° apart at `ENEMY_SPLITTER_MINI_BURST_SPEED`. But the mini-grunts are `EnemyType.GRUNT`,
and on the very next frame `update_grunt_alive` overwrites their velocity to a homing vector
toward the player. The burst direction is thrown away instantly, so all three minis leave the
splitter's death point heading the same direction (at the player) and stick to one another in
a moving stack.

**User's intended fix:** the minis should keep their burst direction for a few seconds (with
variation per mini), then "go back to regular grunt mode" and chase the player normally.

### 2b. RMB charge recharge is "wrong in later rounds"
**Where:** `geowars/src/game/player/player.odin:34-39` (passive recharge) and
`geowars/src/game/shop/shop.odin:50-64` (RMB-related upgrades).

**What's broken (per user):** RMB recharge feels off in the later rounds. `RMB_OVERCHARGE`
adds +1.0 to max with no rate adjustment, so a single overcharge stack pushes a 0→max
recharge from 20 s to 30 s (60 s if stacked twice). Players read this as "RMB doesn't recharge
anymore".

### 2c. Full-charge RMB beam is missing / unclear
**Where:** `geowars/src/game/player/player.odin:83-95` (RMB release branch),
`geowars/src/game/particle/particle.odin:97-116` (`spawn_rmb_pulse`),
`geowars/src/shared/constants.odin:222-231`.

**What's broken (per user):** the design called for a full-strength RMB to fire a clear,
purple, *beam* attack that warps the background — something the player can unmistakably read
as "I just fired the right-click weapon". What's actually wired up is just a ring of
outward-bursting particles. It doesn't visibly originate from the player ship's aim
direction, doesn't warp anything, and at a glance reads as another generic particle burst.

### 2d. Particle off-screen culling ignores camera
**Where:** `geowars/src/game/particle/particle.odin:128-139`.

**What's broken:** The cull rect is fixed at `±ORTHO_HEIGHT * aspect, ±ORTHO_HEIGHT` —
camera-local but **not** offset by `camera_pos`. Particles spawned at the player's position
when the player is far from origin can satisfy the "off-screen" predicate immediately and get
killed the frame they spawn.

---

## 3. Outdated / dead code (documented, not fixed)

### 3a. Carryovers from the previous health-check that are still dead

| Symbol | Where | Status |
|---|---|---|
| `boss_detection_print_cooldown` | `shared/types.odin:191`, written once at `enemy.odin:234` | Still write-only. No reader. |
| `ai_origin_pos` | `shared/types.odin:198`, written at `enemy.odin:239,327,359` | Still write-only. |
| `ENEMY_DEATH_ANIM_DURATION :: 1.0` | `shared/constants.odin:191` | Still unreferenced. |
| `ENEMY_BOSS_CHROME_ORB_WORLD_SCALE` GLSL const | `shader.glsl` (around `fs_enemy`) | Still declared, still unused. |

### 3b. New dead code introduced by the recent commit

| Symbol | Where | Note |
|---|---|---|
| `update_hover` proc | `shop.odin:205-221` | Defined, never called. Body just declares NDC card constants and does `_ = centres` etc. |
| `_ = rand.float32` workaround | `music.odin:408` | Comment admits "keep rand import used elsewhere consistent". `rand` not actually used elsewhere in `music.odin`. |
| `e.rotation += dt * 0.0` | `enemy.odin:300` (`update_disruptor_alive`) | Multiplied by zero. Dead arithmetic. |
| `DRUM_TRACK_AMPLITUDE`-based set_volume + `synth_track_sound` set_volume to 1.0 | `audio.odin:500` and `audio.odin:603` | Both volumes immediately overwritten to 0.0 by `init_music_tracks` before any frame runs. |

### 3c. fmt.printf calls missing newlines
`audio.odin` lines 106, 108, and 208 produce console output without `\n`.

### 3d. Boss laser slot decoder still emits HLSL5 X3556
The laser-slot permutation decoder in `fs_enemy` uses three integer divisions, triggering
HLSL5 warning X3556. Switch `int e` to `uint e` for a clean compile log.

### 3e. Files-at-`geowars/` from before the refactor
- `geowars/geowars.odin.txt` (2548 lines) — pre-refactor monolithic source dump.
- `geowars/error_to_fix.txt` (29 lines) — historical RMB-particle debug print log.

---

## 4. Stale docs

### 4a. README.md — has not been touched since the project's first commit

The current game has the player ship with HP/dash, LMB blackhole projectile + trail, RMB
charge meter & pulse, six enemy types, 10-wave director, three shops with 12 upgrade
definitions, six procedurally generated music tracks, low-HP screen tinting, deadzone-follow
camera, and a screenshot-harness test mode. None of this is in the README.

### 4b. `HEALTH_CHECK.md` — replaced by the post-shop/music snapshot
The previous health-check is at `docs/archive/HEALTH_CHECK_2026-05-pre-shop-music-snapshot.md`.

### 4c. `examples/` and `examples/all/` READMEs
Vendored Odin examples; leave alone.

---

## 5. Summary punch list for follow-up work

| Item | Effort | Severity | Where to look |
|---|---|---|---|
| Splitter mini-grunts stick together | medium (1–2h) | gameplay-visible bug | `enemy.odin:248-268`, `collision.odin:17-26` |
| RMB charge recharge feels broken late-game | small → medium | gameplay-visible bug | `player.odin:34-39`, `shop.odin:50-64` |
| Full-charge RMB beam (warping, clearly from RMB) is missing | medium-large | missing feature | `player.odin:83-95`, `particle.odin:97-116`, `shader.glsl` |
| Particle off-screen cull ignores camera_pos | tiny | intermittent visual | `particle.odin:128-139` |
| Rewrite `README.md` for current game state | small | docs hygiene | `README.md` |
| Delete `update_hover`, `dt * 0.0`, `_ = rand.float32`, dead set_volume calls | tiny | code-cleanup | per §3b |
| Delete or move `geowars/geowars.odin.txt`, `geowars/error_to_fix.txt` | tiny | repo hygiene | per §3e |
| Add `\n` to three `fmt.printf` calls in `audio.odin` | tiny | cosmetic | `audio.odin:106,108,208` |
| Clean up dead fields/constants from §3a | tiny | code-cleanup | per §3a |
| Switch boss laser-slot decoder ints → uints (HLSL5 X3556) | tiny | shader warning | `shader.glsl` `fs_enemy` |
