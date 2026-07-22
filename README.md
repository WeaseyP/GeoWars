# GeoWars

A twin-stick arena shooter written in Odin with sokol_gfx for rendering and miniaudio for
sound. The original goal was a game with no asset files: every visual is rendered live from
shader maths, and every sound is generated procedurally at boot.

## Build

Windows (this is the only platform currently set up):

```
build.bat
```

That regenerates the shader bindings (`geowars/src/shared/shader.odin`) from
`geowars/assets/shaders/shader.glsl` via the bundled `sokol-shdc.exe`, then compiles the game
to `geowars_windows.exe` in the repo root.

## Run

```
geowars_windows.exe
```

## Controls

| Input | Action |
|---|---|
| `WASD` | Move |
| `Shift` | Dash (i-frames; cooldown) |
| `LMB` | Fire blackhole projectile (homes-ish, leaves a purple trail) |
| `RMB` (tap) | Fire a small splash — droplet count scales with current charge |
| `RMB` (full charge) | Fires a directional purple **beam** plus an omnidirectional pulse |
| `F` (at origin) | Press the wave button to advance to the next wave |
| `1` / `2` / `3` | Pick the corresponding card while the shop is open (mouse click also works) |
| `Esc` | Quit |

The right-click charge meter passively fills to 200% (visible as the ring around the player).
You can fire at any fraction; the >=100% release triggers the headline beam + pulse.

## Game loop

Ten waves of enemies, with a shop after each batch of three:

1. Stand on the wave button at world origin and press `F` to start the next wave.
2. Survive until the wave is empty.
3. Every three waves, a shop opens — pick one of three upgrade cards.
4. After wave 10, the boss appears.

Disruptors that reach the wave button substitute for an `F` press and trigger the next wave
without the player's input — they're a soft pressure mechanic.

## Enemies

| Type | Behaviour |
|---|---|
| Grunt | Homes on the player with a wander offset |
| Slowboy | Approach → wind-up (locked aim, shake) → straight-line charge → recover |
| Splitter | Asteroid-style chaser; on death (LMB or contact) it splits into 3 mini-grunts that fan out before chasing — **kill it with RMB to skip the split** |
| Sniper | Idles, then telegraphs a hitscan beam and fires |
| Disruptor | Beelines for the wave button and presses it for you |
| Boss | Phase 1: orbits the arena, single rotating laser. Phase 2: centre orbit + sweeping multi-laser fan + minion spawns. Speeds up as HP drops. |

## Elite tiers

Most enemy types can roll silver (≈2× base) or gold (≈4× base) tiers, with corresponding
speed and damage multipliers. Visible as recoloured / larger sprites.

## Shop upgrades

12 upgrade definitions across three tiers (common / uncommon / rare). Pre-boss shops bias
toward higher tiers. RMB charge upgrades scale rate with cap so the time-to-fill stays
constant regardless of stacking.

## Layout

```
geowars/
  src/
    core/         entry point, frame loop
    audio/        miniaudio glue, procedural drum + synth + per-enemy tracks
    game/
      collision/  particle/projectile-vs-enemy, beam-vs-enemy
      enemy/      AI per type, wave director
      particle/   RMB swirl/pulse/trail particles
      player/     input, motion, fire logic
      progression/wave/shop progression
      projectile/ LMB blackhole projectile
      shop/       upgrade catalog, pick UI
      testmode/   screenshot harness (used by snap.bat)
    graphics/     pipeline + buffer setup
    shared/       global state, shader bindings, constants, types
    vendor/       miniaudio + sokol bindings, math helpers
  assets/shaders/ single shader.glsl with all passes (bg / player / particle / enemy / blackhole)
docs/archive/     historical snapshots, pre-refactor source dumps
```

## Repo health

See `HEALTH_CHECK.md` for the latest state-of-the-codebase audit.
