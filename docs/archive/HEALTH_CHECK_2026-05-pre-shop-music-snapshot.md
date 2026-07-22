# GeoWars repo health check

Snapshot taken after the music-track + sniper-range work. Verdict at a glance: **healthy, no
required refactors**. There are a handful of small dead-code items and two stale ad-hoc files
that are easy wins, listed below. Nothing is blocking, nothing is structurally rotten.

## What I checked

- Build: clean (`odin build geowars/src/core -o:speed`, no warnings from our code).
- Boot run: starts to main loop, all 6 music tracks initialise, wave system loads, RMB ammo regen ticks.
- File sizes (excluding generated `shared/shader.odin` and `vendor/`):
  ```
  596  game/enemy/enemy.odin
  579  audio/audio.odin
  454  audio/music.odin
  262  game/particle/particle.odin
  215  game/player/player.odin
  192  game/progression/progression.odin
  185  core/geowars.odin
  179  shared/constants.odin
  150  shared/types.odin
  145  game/collision/collisions.odin
   72  game/projectile/projectile.odin
   67  graphics/rendering.odin
   61  shared/state.odin
  ```
- Module coupling: clean DAG. `shared/*` is leaf; `game/*` depends on `shared/*`; `audio` depends
  only on `shared/*` and vendor; `core` wires it all. No cycles, no game subpackage reaching
  sideways into another.
- Imports: all used (manually grep-verified per package).
- TODO/FIXME/HACK in our own code: none.

## Minor findings (low priority)

### 1. Dead fields & constants — ~5 min to remove, 0 risk

| Symbol | Location | Why it's dead |
|---|---|---|
| `boss_detection_print_cooldown` | `shared/types.odin` (Enemy struct), initialised in `enemy.odin` spawn | Field is only written to `0.0` once at spawn; never read or updated. Leftover from the old "boss has a vision cone" system that was replaced when the orb's behaviour became state-driven. |
| `ai_origin_pos` | `shared/types.odin` (Enemy struct), written in `enemy.odin` slowboy WINDUP/CHARGE transitions | Only WRITTEN (twice), never READ. The slowboy charge logic uses `e.pos` directly when computing the velocity vector, so this snapshot is redundant. |
| `ENEMY_DEATH_ANIM_DURATION :: 1.0` | `shared/constants.odin` | Superseded by the per-type constants (`GRUNT_DEATH_ANIM_DURATION`, `SLOWBOY_DEATH_ANIM_DURATION`, etc.) used by the death-state branch. The umbrella constant is no longer referenced anywhere. |
| `ENEMY_BOSS_CHROME_ORB_WORLD_SCALE = 0.5` | `assets/shaders/shader.glsl` line ~589 (fs_enemy) | GLSL `const float` declared but never used in any shader path. Comment admits it's an old approximation for `PLAYER_SCALE * 2.5`. |

**Why not now:** all four are inert. Keeping them costs nothing per frame; deleting is a
cosmetic cleanup, easy to do whenever someone is already touching those files for another reason.

### 2. Stale ad-hoc files at `geowars/`

| Path | Size | Status |
|---|---|---|
| `geowars/geowars.odin.txt` | 2548 lines | Pre-refactor monolithic source dump. No build target imports it. Useful only as historical reference. |
| `geowars/error_to_fix.txt` | 29 lines | Historical RMB-particle debug print log (`RMB Hit: Enemy 0x7FF6...`). Not a build artefact, not a TODO list. |

**Recommendation:** delete or move to `docs/archive/`. They aren't loaded anywhere; their only
effect is making `ls` of the project root noisier. Strictly file-system hygiene.

### 3. Shader perf warning (informational, not a bug)

The `fs_enemy` boss block decodes the laser-slot permutation with three integer divisions:

```glsl
slot_order[0] = e - (e / 6) * 6;  // and similar 5x more
```

HLSL5 emits warning X3556 ("integer divides may be much slower, try using uints if possible") on
these. They're correct and they run fine — at most one boss exists at a time so the cost is a
rounding error. If we ever want to silence the warning, swap `int e` to `uint e` in the slot-order
decoder. **Not worth doing now.**

## Larger files — not pain points yet

- `enemy.odin` (596): organised as **spawn → per-type alive helpers (`update_grunt_alive`, `update_slowboy_alive`, …) → main loop dispatch**. Each section reads independently. The main loop is the only "fat" part because it has to handle dying/growing/alive branches plus the per-type switch, but the helpers are clean.
- `audio.odin` (579): two heavy PCM generators (drum + synth) plus a long flat init for SFX. It's monolithic but still mostly the original sokol template's structure. Adding a new SFX or base track inside it would mean scrolling, but nothing forces a redesign right now.

If audio churn picks up, I'd consider splitting `audio.odin` into:
- `audio/sfx.odin` — synth helpers (kick/snare/hihat/saw/sine envelopes), shared with `music.odin`
- `audio/sfx_lmb.odin`, `audio/sfx_rmb.odin`, `audio/sfx_enemy_hit.odin` — one-off effect generation
- `audio/base_tracks.odin` — the existing drum + synth tracks (matching `music.odin`'s style)

This isn't a correctness change, just shorter scroll distance per concern. **Don't do it speculatively** — wait until the next time audio.odin needs a real change and bundle the split with that.

## Cross-cutting observations (FYI only)

- **Effect-params overloading.** Many enemy types pack different meanings into the
  `Enemy_Instance_Data.instance_effect_params` `vec4`. This is intentional to keep the per-instance
  vertex format small (recompiling shaders is free, but new attributes mean another regen + binding
  index). Documented inline in the shader's per-type branch headers. Cost: anyone editing the
  shader needs to consult the matching encoder in `enemy.odin`'s update fn.
- **`shared.state` is a giant struct.** Today this is fine — total size is well under a cache
  line's worth of cache-miss cost per frame, and "everything is a global" is appropriate for a
  small game. If we ever go multi-level / multi-arena, the wave system + camera + audio fade
  state would want their own owned structs and a top-level `Game` aggregator.
- **No automated test coverage.** This is a hot-loop game with no unit tests. Adding tests for
  pure-data subsystems (wave directive scheduling, slowboy state machine timings) would be
  cheap if regressions ever start showing up; right now there's no churn to justify it.

## Recommendation summary

| Action | Effort | Value | Do now? |
|---|---|---|---|
| Delete 4 dead symbols (table 1) | 2 min | tiny | When next touching those files |
| Move/delete 2 stale `.txt` files | 30 sec | tiny | Yes, anytime |
| Switch slot decoder to `uint` (silence shader warning) | 5 min | aesthetic | Optional |
| Split `audio.odin` into per-voice files | 30 min | medium | Only when audio next needs a real change |

**Net:** the codebase is in a maintainable place. Keep building features; revisit this list
opportunistically.
