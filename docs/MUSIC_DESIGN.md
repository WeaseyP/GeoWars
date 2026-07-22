# GeoWars Music & Sound Design — Skald Suite

19 Skald instrument files live in the Skald repo at `skald-backend/Skald/GeoWars - *.json`
(one instrument per file, all validated through `codegen.exe`). This doc is the strategy:
which instrument belongs to which character, and — the important part — **how each
instrument gets edited live while the game runs**.

## The core idea: instruments that morph, not tracks that swap

The current system already has the right instinct (boss music pitch ramps up as HP drops;
enemy layers fade in per type). This design generalizes that: every instrument exposes
named parameters, and Skald's codegen emits a typed setter for each one
(e.g. `GW_Boss_War_Tuba_set_Rage_mix(&p, 0.6)`). Game state drives those setters every
frame. The Normal Sax → Growly Sax pair proved the concept as two saved patches; here it
becomes **one patch whose knobs the game turns** — the same tuba is a ballad at full boss
HP and a filthy growl at 10%.

Rule of thumb carried over from `music.odin`: never snap a parameter. Slew every value
with the existing `approach()` pattern (fast for volumes ~2.5/s, slow for timbre ~0.25/s)
so morphs read as "the music is turning mean" rather than a preset click.

## Shared musical grid (fixes the current tempo clash)

The current per-enemy tracks run at 90/130/160/180 BPM simultaneously — they can't stack.
New rule:

| Context | BPM | Key | Why |
|---|---|---|---|
| Enemy bed (all 5 enemy layers + drums) | 128 | D minor | Any subset layers cleanly |
| Boss suite | 112 | D minor | Plays solo-ish; engine pitch ramp takes it to ~174 feel |
| Gold elite | 128 | **D major** | Same root, raised third — gleams against the minor bed |
| Shop | 116 | F major | Relative major of Dm — friendly, but one chord from combat |
| Death / lull | 84 | D minor | Breath Ballad tuba |

Everything shares root D, so any crossfade between contexts is harmonically safe.

## Per-enemy instruments (the identity layers)

Each replaces one hand-written PCM track in `music.odin`. Keep the existing rules:
unlock on first kill, fade at MUSIC_FADE_RATE, disruptor stays alive-gated.

### GRUNT — `GW Grunt Swarm Bass` (pink #E91E8C)
Galloping saw bass on 8ths, D natural minor. Probability ghost-notes on the off-16ths make
the loop non-identical each bar.
**Live edits:** `cutoff` 750→2600 Hz and `drive` 8→20 scale with **live grunt count**
(0→15 grunts). One grunt = dull thump; a swarm = snarling wall. Mirrors how grunts
already spin harder when faster.

### SLOWBOY — `GW Slowboy Doom Tuba` (blue #4FB3E8) — tuba #1
Half-note sub-tuba doom riff (D2/A1). Contains a **Windup Shake LFO wired to oscillator
amplitude, defaulted to zero** — inaudible until the game touches it.
**Live edits:** when any slowboy enters WINDUP, ramp `Windup Shake.frequency` 0.5→9 Hz and
`.amplitude` 0→0.5 with the windup progress (`1 - ai_state_timer/ai_state_total`) — the
tuba trembles exactly in sync with the on-screen shake. On CHARGE, spike `drive` to 18 for
the charge duration, then decay. The music telegraphs the attack.

### SPLITTER — `GW Splitter Echo Stab` (orange #D98C40)
Square-wave pluck stabs through a BPM-synced 1/8 delay.
**Live edits:** the delay is the enemy. Baseline `feedback` 0.35. When a splitter dies
(the moment it splits into 3 minis), kick `feedback` to 0.8 and `mix` to 0.5, decaying
back over ~1.5 s — **the note audibly splits into copies of itself**, same as the enemy.

### SNIPER — `GW Sniper Laser Wire` (red #F04050)
Nervous high square ticks with a sample-and-hold pitch jitter; several notes have
probability < 1 so the pattern twitches.
**Live edits:** `cutoff` on the bandpass "Aim Riser" tracks the **max aim progress across
all AIMING snipers**: 800 Hz idle → 5000 Hz at full lock. The player *hears* the beam
charging even off-screen; on FIRING it resets, which reads as the shot's exhale.
`resonance` 3→5 past the lock-on threshold (when the sniper stops tracking) — the sound
goes rigid exactly when dodging matters.

### DISRUPTOR — `GW Disruptor Alarm` (cyan #40E8E8)
E↔F semitone klaxon stabs — a klaxon because this enemy *is* an alarm. Stays alive-gated.
**Live edits:** `feedback`/`mix` on the Panic Echo scale with **1 − (distance to button /
arena radius)** of the closest disruptor. Far away: dry warning blips. About to press:
self-feeding echo panic. Volume can also ride the same value.

### Drum bed — `GW Kick Warhead`, `GW Snare Shrapnel`, `GW Hat Static`
Real drums replacing the sine-wave placeholders (the current "snare" and "hi-hat" are
literally sines — these use proper noise sources). Hats use **P-locks** (`decay`
overridden per-step) for open/closed articulation.
**Live edits:** kick `drive` and `mix` scale with total enemy count (shared "how bad is
it" channel). Suggested unlock: drums come in with wave number — wave 1 kick only, wave 3
adds snare, wave 5 adds hats — the soundtrack literally grows with the run.

## Boss music — the centerpiece

Keep the pitch ramp (it's great). Layer three more morph systems on top so the whole
fight is one continuous escalation:

**`GW Boss War Tuba`** (chrome #C0C0C8) — tuba #2, the flagship. Full Growly-Sax-style
architecture in tuba register: reed → parallel body/formant filters + breath-noise air
channel → distortion → amp, with pitch-scoop and vibrato. Defaults are the *clean ballad*
state. Map **boss HP ratio** (1.0 → 0.0) onto:

| Parameter (setter) | 100% HP | 10% HP | Feel |
|---|---|---|---|
| `set_drive` | 6 | 30 | growl |
| `set_Rage_mix` | 0.12 | 0.6 | filth |
| `set_Breath_amplitude` | 0.06 | 0.3 | spit and air |
| `set_Formant_cutoff` | 600 | 1100 | vowel opens to a snarl |
| `set_Body_cutoff` | 320 | 900 | brightness |
| `set_Vibrato_frequency` | 4.5 | 7 | nervous |
| `set_Vibrato_amplitude` | 0.015 | 0.04 | wide, unhinged |

Plus discrete hits: **each new laser** (boss_laser_count up-tick) bumps drive +3 instantly
then relaxes to the HP curve — every added laser audibly angers the tuba.
**Phase 2 entry**: momentarily drop `Body_cutoff` to 150 for one bar then release — a
"swallow" before the second wind.

**`GW Boss Chrome Pad`** — wavetable pad, slow LFO scanning the table (sine→saw morph =
chrome sheen). Dm → Bb whole-note chords under the tuba.
**Live edits:** `position` rides `boss_laser_count/6` (more lasers = glassier), `cutoff`
rides HP.

**Reuse the enemy drum bed under the boss** instead of muting everything: keep Kick/Snare/
Hat running (they're 128 BPM; the boss engine-pitch-ramp applies to the boss instruments
only, or simpler: run the whole boss mix through the existing single-sound pitch ramp as
today). Enemy identity layers fade out as now.

## Golden (and silver) elites — their own music

Gold tier already exists (`ELITE_TIER_GOLD` tint, stat multipliers). Music rules:

- **Gold spawn:** fire `GW SFX Gold Chime` once (trigger at note 93). Unmissable announcement.
- **While a gold elite is alive:** start `GW Gold Midas Bells` + `GW Gold Gilded Fanfare`
  on top of the bed, and duck all enemy identity layers to ~40% (drums stay). Both gold
  tracks are **D major** over the D-minor bed — deliberately "wrong" in a way that
  glitters; the mixture chord = something valuable and dangerous is here.
- **Gold elite killed:** bells' `feedback` on the Sparkle delay to 0.7 for a two-second
  shimmer-out payoff, then stop both layers.
- **Silver tier:** no new layer — just brighten: +10% cutoff on whichever identity layer
  matches the elite's base type, and let the Hat Static layer in early. Silver is a hint;
  gold is an event.
- **Bells get greedier as the gold elite hurts you:** if the gold enemy damages the player,
  bump `Carrier.modIndex` 5→8 for a bar (harsher, more metallic bells).

## Ammo / combat SFX (replace the hand-written PCM in `audio.odin`)

| File | Replaces | Trigger point | Live edits |
|---|---|---|---|
| `GW SFX Blackhole Pew` | `lmb_sound` (1200→400 sine sweep — same character, now editable) | LMB fire | velocity = 0.7 + 0.3·rand for variety; `Sweep.decay` shortens as fire-rate upgrades stack (snappier gun) |
| `GW SFX Kill Explosion` | `lmb_kill_sound` | enemy death | velocity scales with enemy size (grunt 0.6 → slowboy 1.0); trigger note −12 for elites (bigger boom) |
| `GW SFX Sniper Rail` | (new) sniper FIRING moment | `sniper_fire_hitscan` | none needed — comb-delay ring is baked |
| `GW SFX Button Slam` | (new) disruptor button press | `disruptor_press_button` | also fire when the *player* presses F, at velocity 0.6 — same sound, smaller, teaches the association |
| `GW SFX Gold Chime` | (new) gold elite spawn | `spawn_enemy_tiered` gold branch | trigger note 93; note 81 for silver at velocity 0.5 |

SFX are trigger-per-event polyphonic voices (voiceCount 4–8), so overlapping kills no
longer need the shared-buffer volume tricks the RMB swirl uses.

## Tuba options (the full stable)

1. **`GW Slowboy Doom Tuba`** — sub-register menace, shake-LFO windup telegraph.
2. **`GW Boss War Tuba`** — clean ballad → growl monster morph; the boss fight IS this tuba.
3. **`GW Tuba Oompah Shop`** — F-major sousaphone oom-pah at 116 BPM for the shop. Comic
   relief between waves; glide 0.03 gives it that slightly drunk brass-band slide.
   *Live edit:* as shop timer runs out, ramp session-level pitch/volume down — the band
   packs up, get out of the store.
4. **`GW Tuba Breath Ballad`** — 84 BPM, breath-noise-forward, long reverb. Death screen /
   run-summary music. *Live edit:* `Breath.amplitude` up + `Warm Body.cutoff` down as the
   death animation plays — the tuba runs out of air with you.

Plus the existing `Tuba.json` / `Tuba - 2 Breath Bloom` patches in the library remain the
reference lineage these were built from.

## More "boss music gets faster" ideas (the requested idea bank)

- **Player HP as a global filter:** at ≤2 HP, pull every music layer's cutoff down and let
  the Kick Warhead's sub through — the classic underwater near-death muffle, done with
  3–4 `set_cutoff` calls.
- **Wave-button countdown:** the 3-2-1 spawn queue pulses the Disruptor Alarm's bandpass
  `cutoff` on each tick even when no disruptor is alive — the arena itself uses the klaxon voice.
- **Combo heat:** kills within a short window raise Hat Static `decay` (hats open up) and
  Swarm Bass `resonance` — streaks make the groove sizzle; dropping the streak closes it.
- **Splitter mini-swarm:** while ≥6 mini-grunts are alive, double-time the Swarm Bass by
  starting a second processor instance one octave up at half volume — swarm-of-swarms.
- **Black hole in flight:** RMB swirl hum already sums per-particle; route the same sum
  into Chrome Pad `Shimmer.amplitude` during boss fights so your own bullets ripple the
  boss's pad.
- **Probability as danger:** every `probability` field in these patterns can be pushed
  toward 1.0 as wave number climbs — early waves play sparse patterns, wave 10 plays
  every ghost note. One multiplier, whole-soundtrack density curve. (Needs the pattern
  data queried/re-fed at runtime, or bake 2–3 density variants per patch.)

## Integration checklist

1. `codegen.exe -in:"Skald/GeoWars - <name>.json" -out:<geowars>/src/audio/generated/<name>.odin -package:gw_audio`
   per file (or one combined project JSON later).
2. Generated processors produce samples via `<Name>_process` — feed them from
   `geowars_audio_stream_callback` alongside (eventually instead of) the miniaudio buffers.
3. Music layers: call `<Name>_start` once, control audibility with a volume multiply on
   the processor output using the existing `music_state` target/approach machinery.
4. Timbre morphs: one `update_music_morphs(dt)` proc that reads `shared.state` (enemy
   counts, ai_state progress, boss HP/lasers, elite tiers, player HP) and calls the
   setters listed above through slewed values.
5. Keep `clamp`-style master safety: sum of layers through a final soft-clip, as today.
