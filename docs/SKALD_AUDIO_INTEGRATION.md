# Integrating Skald-generated audio into GeoWars

This guide records the workflow used for the boss-music demo. The intended long-term rule is:
Skald owns the instruments, sequences, and parameters; GeoWars owns playback, game-state routing,
mix levels, and lifecycle management.

The demo source is `boss-music-trial.odin`. It is generated code in package `generated_audio`,
not a WAV file and not a normal GeoWars `audio` package file.

## 1. Export and place the Skald source

Keep each Skald export intact. Do not copy individual oscillator or envelope functions into
`music.odin`.

For future tracks, prefer a stable package directory such as:

```text
geowars/src/generated_audio/boss/
geowars/src/generated_audio/grunt/
geowars/src/generated_audio/player/
```

The boss demo imports its repository-root trial with:

```odin
import boss_trial "../../.."
```

That was convenient for the demo. Moving future exports under `geowars/src/generated_audio/`
will make their ownership and import paths clearer.

Useful generated APIs are:

```odin
project_init(&project, sample_rate)
project_process(&project)
project_destroy(&project)

<Instrument>_set_<parameter>(processor, value)
<Instrument>_process(processor)
```

## 2. Render before the audio thread starts

GeoWars starts miniaudio's graph and then starts the Sokol audio thread. The graph must be fully
built before `sa.setup`. Do not allocate Skald processors, attach nodes, or mutate filter nodes
from the frame loop or audio callback.

The safe pattern is:

1. Allocate PCM slices during `init_music_tracks`.
2. Initialise the generated Skald project at 44,100 Hz.
3. Render samples by repeatedly calling the generated processors.
4. Copy the PCM into `ma.audio_buffer` objects.
5. Initialise and start all looping `ma.sound` objects at volume zero.
6. Start Sokol audio only after every sound and node exists.

This keeps the real-time callback limited to `ma.engine_read_pcm_frames`.

## 3. Render synchronized stems

Every stem that will be layered must have the same:

- sample rate;
- authored BPM;
- loop length;
- starting step;
- pitch value at runtime.

The boss demo renders eight bars at 145 BPM. It first renders one warm-up bar so ADSRs, filters,
echoes, and reverb have settled before the captured loop begins.

For a game-controlled arrangement, render separate synchronized stems instead of one finished
mix. The boss demo uses:

- restrained base;
- enraged/intensity difference;
- phase-2 sax difference;
- late-phase tuba difference;
- non-looping hit accent.

The difference-stem technique preserves Skald's master saturation:

```odin
base_pcm[i]      = restrained_mix
intensity_pcm[i] = enraged_mix - restrained_mix
sax_pcm[i]       = sax_mix - enraged_mix
tuba_pcm[i]      = full_mix - sax_mix
```

At full volume, adding the difference stems reconstructs the intended cumulative mix. At partial
volume, a difference stem becomes a clean crossfade instead of doubling the backing track.

## 4. Use Skald parameters for game-state variants

Create two identically seeded projects when the background needs to evolve continuously. Apply
different generated setters before rendering, then crossfade between their synchronized outputs.

The demo's restrained-to-enraged morph changes:

- hat cutoff and decay;
- bass cutoff, drive, distortion mix, resonance, and decay;
- stab cutoff, feedback, wet mix, pulse width, and resonance;
- sax breath, expression/growl, body filter, formant resonance, room, vibrato, drive, and tone.

This is preferable to mutating a live miniaudio filter from the game thread. Future exports can
define more purposeful Skald presets - calm, alert, phase 2, critical health - and GeoWars can render
and crossfade those presets without reimplementing the sound design.

## 5. Route stems from gameplay

`update_music(dt)` should translate game state into target volume and pitch only. Smooth current
values toward those targets to avoid clicks.

The boss demo currently routes:

```text
Boss appears       -> restrained base starts on a synchronized downbeat
Boss loses HP      -> intensity difference rises continuously
Phase 2 begins     -> sax enters for the first time
Boss reaches 25%   -> tuba enters halfway through phase 2
Boss loses HP      -> common pitch slowly rises from 1.00x to 1.18x
Boss is hit        -> non-looping accent plays over the uninterrupted music
```

When a boss first appears, seek every synchronized stem to PCM frame zero. Apply the same pitch to
all stems every frame or they will drift apart.

Game events should call a small public audio procedure such as `notify_boss_hit`; collision code
should not manipulate audio buffers or synth processors itself.

## 6. Levels and one-shots

Start new accents quietly. The demo hit accent is currently 20% volume because repeated combat
events stack perceptually against a dense backing mix.

For a Skald replacement:

1. export the accent as its own generated Skald asset;
2. render its natural one-shot duration at startup;
3. initialise a non-looping `ma.sound`;
4. seek it to frame zero and start it on each event;
5. tune only its playback volume and optional pitch from GeoWars.

The current `generate_boss_hit_stinger` implementation is temporary hand-authored demo code. It
should be deleted when the corresponding Skald-generated hit instrument exists.

## 7. Cleanup requirements

For every added stem, cleanup must perform all three operations:

1. `ma.sound_uninit`;
2. `ma.audio_buffer_uninit`;
3. `delete` the source PCM slice.

Stop Sokol audio before tearing down any miniaudio sound or node. GeoWars already does this in
`cleanup_audio`.

## 8. Replacing another existing GeoWars sound

Use this checklist for each migration:

1. Export the source from Skald and add it under `geowars/src/generated_audio/`.
2. Import the generated package from the GeoWars audio package.
3. Identify whether it is a loop, synchronized stem, or one-shot.
4. Render it to PCM during audio initialisation.
5. Add required `ma.audio_buffer` and `ma.sound` storage.
6. Initialise playback before `sa.setup`.
7. Route only volume, pitch, seek, and start/stop events at runtime.
8. Add matching cleanup calls.
9. Remove the replaced procedural generator only after the Skald version works.
10. Run `odin check geowars/src/core`, then `build.bat`, then perform a runtime smoke test.

## 9. Removing the temporary boss demo later

The old boss generator is deliberately retained as `gen_legacy_boss_track` in
`geowars/src/audio/music.odin`.

When this branch becomes main and the demo setup is no longer wanted:

1. Restore wave 1 in `game/progression/progression.odin` from the temporary boss directive to its
   intended enemy wave.
2. Remove `notify_boss_music_hit` calls from `game/collision/collisions.odin` if the final Skald
   design has no hit accent.
3. Remove the temporary chrome-stinger generator and its sound/buffer/state fields.
4. Replace or remove the demo-specific boss stems only after their final Skald exports are wired.
5. Keep `gen_legacy_boss_track` until the final boss score has been approved in-game.
6. Delete the repository-root trial only after nothing imports it.
7. Compile, rebuild, and smoke-test both normal progression and `--test-stage`.

Git branch `skald-boss-music-demo` and commit `4e5e21e` preserve the complete working demo for
reference even after its temporary gameplay wiring is removed.
