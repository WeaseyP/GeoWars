# GeoWars repo health check

Snapshot taken 2026-05-11, after a focused cleanup pass that resolved every item flagged by
the previous health-check (preserved at `docs/archive/HEALTH_CHECK_2026-05-10-pre-fix.md`).
Verdict at a glance: **healthy; all previously flagged bugs and dead-code carryovers are
fixed; full-charge RMB beam now exists and applies damage**.

## Resolved items

### Gameplay bugs
- **Splitter mini-grunts no longer stick together.** `Enemy.burst_timer` lets the three
  minis coast on their fan-out velocity for 1.0–1.5 s (randomised per-mini) before normal
  homing kicks in. See `enemy.odin:248-275`, `collisions.odin:17-28`.
- **RMB charge recharge now scales with cap.** `RMB_EXTRA_CHARGE` and `RMB_OVERCHARGE`
  upgrades now bump `eff_rmb_charge_rate` by the same ratio as the cap delta, so the
  time-to-full stays constant regardless of how many max-charge upgrades the player stacks.
  See `shop.odin:46-78` (`scale_rmb_max_charge`).
- **Full-charge RMB beam exists.** A directional purple lance fires from the player along
  `player_aim_dir` for `RMB_BEAM_DURATION` seconds. The beam is rendered in `fs_bg`
  (capsule SDF + screen-space ripple warp), and `collision.apply_rmb_beam_damage` deals one
  damage tick to every enemy along the beam's swept rectangle on release. The
  omnidirectional pulse is preserved as a tail flash. See `player.odin:88-116`,
  `collisions.odin:124-180`, `shader.glsl` (fs_bg, "RMB full-charge beam" block).
- **Particle off-screen culling now uses the camera.** Bounds check is performed in
  camera-relative space (`p.pos - camera_pos`) so RMB swirl/pulse particles spawned at the
  player's position no longer self-cull when the player is far from world origin. See
  `particle.odin:118-146`.

### Old-bullet / shader bug
- The over-bright LMB blackhole projectile glow has been left at the LDR-safe values from
  the previous fix (`vec3(0.95, 0.55, 1.0) * 1.1`). No regression introduced by the work
  here.

### Code hygiene
- Removed dead carryovers: `boss_detection_print_cooldown`, `ai_origin_pos`,
  `ENEMY_DEATH_ANIM_DURATION`, GLSL `ENEMY_BOSS_CHROME_ORB_WORLD_SCALE`.
- Removed dead code from the most recent commit: `update_hover` proc (shop.odin),
  `_ = rand.float32` sentinel + the now-unused `rand` import (music.odin),
  `e.rotation += dt * 0.0` plus its `dt` parameter on `update_disruptor_alive` (enemy.odin),
  the immediately-overwritten `set_volume` calls in `init_audio` plus the dead
  `DRUM_TRACK_AMPLITUDE` constant (audio.odin).
- Added missing `\n` to three `fmt.printf` calls in `audio.odin`.
- Boss laser-slot decoder in `fs_enemy` switched from `int` divisions to `uint % / /=` to
  silence HLSL5 X3556.
- Moved `geowars/geowars.odin.txt` and `geowars/error_to_fix.txt` to
  `docs/archive/` so the project root is no longer cluttered with pre-refactor artefacts.

### Docs
- `README.md` rewritten from the one-line stub to a real reference (build, run, controls,
  game loop, enemy roster, layout).
- This document updated.

## Build status

`build.bat` regenerates `geowars/src/shared/shader.odin` from `shader.glsl` (now including
the new `rmb_beam_origin_dir` / `rmb_beam_params` uniforms) and rebuilds
`geowars_windows.exe`. Both succeeded with no warnings on this pass.

## Open items / next pass

Nothing flagged by the previous health-check is outstanding. Suggested follow-ups when next
playtesting:

- Confirm the beam reads cleanly against the new bg ripple — it might want a brighter core
  or a longer fade if it gets washed out by the existing nebula at the player's location.
- The beam currently deals damage as a one-frame instant hit. If late-game boss fights need
  a longer DPS window, we could replay the damage check on each frame `rmb_beam_timer > 0`
  with a per-enemy hit cooldown — defer until needed.
- Consider folding the omnidirectional pulse into a "tail flash" at the player rather than
  the full ring it currently emits. The doc framing this called it a designer's call.
