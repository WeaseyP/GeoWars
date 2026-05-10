package audio

import ma "../vendor/miniaudio"
import "core:math"
import "core:fmt"
import rand "core:math/rand"
import shared "../shared"


// --- Per-enemy music tracks + boss track ---
// Each enemy type has its own loop. update_music ticks every frame, computes the target volume
// for each track based on which enemy types are alive, and smoothly fades the running volumes
// toward those targets. When the arena is empty AND no wave is mid-spawn, all tracks fade out.

MUSIC_SAMPLE_RATE :: 44100
MUSIC_CHANNELS    :: 1

splitter_track_pcm:  []f32
splitter_track_buf:  ma.audio_buffer
sniper_track_pcm:    []f32
sniper_track_buf:    ma.audio_buffer
disruptor_track_pcm: []f32
disruptor_track_buf: ma.audio_buffer
boss_track_pcm:      []f32
boss_track_buf:      ma.audio_buffer

// Active master volumes per track type. Targets jump on enemy state changes; current values lerp.
@(private)
music_state: struct {
    target_grunt:     f32, current_grunt:     f32,
    target_slowboy:   f32, current_slowboy:   f32,
    target_splitter:  f32, current_splitter:  f32,
    target_sniper:    f32, current_sniper:    f32,
    target_disruptor: f32, current_disruptor: f32,
    target_boss:      f32, current_boss:      f32,
    current_boss_pitch: f32, target_boss_pitch: f32,
    initialized: bool,
}

// --- Per-track active volumes (when fully on). Tuned so 2-3 layered tracks don't clip. ---
GRUNT_TRACK_VOL     :: 0.55
SLOWBOY_TRACK_VOL   :: 0.55
SPLITTER_TRACK_VOL  :: 0.50
SNIPER_TRACK_VOL    :: 0.45
DISRUPTOR_TRACK_VOL :: 0.55
BOSS_TRACK_VOL      :: 0.85

MUSIC_FADE_RATE :: f32(2.5) // volume per second; 0.4s to fully fade in/out

// ============================================================================
// PCM helpers — small synth voices
// ============================================================================

@(private)
add_kick :: proc(pcm: []f32, start_frame: int, length_frames: int, amp: f32) {
    sr := f64(MUSIC_SAMPLE_RATE)
    phase: f64 = 0.0
    for i in 0..<length_frames {
        idx := start_frame + i
        if idx < 0 || idx >= len(pcm) { continue }
        progress := f64(i) / f64(length_frames)
        env := math.pow(1.0 - progress, 2.5)
        if env < 0 { env = 0 }
        freq := 120.0 * math.pow(40.0/120.0, progress)
        pcm[idx] += f32(math.sin(phase) * env * f64(amp))
        phase += 2.0 * math.PI * freq / sr
        if phase >= 2.0 * math.PI { phase -= 2.0 * math.PI }
    }
}

@(private)
add_snare :: proc(pcm: []f32, start_frame: int, length_frames: int, amp: f32) {
    for i in 0..<length_frames {
        idx := start_frame + i
        if idx < 0 || idx >= len(pcm) { continue }
        progress := f64(i) / f64(length_frames)
        env := math.pow(1.0 - progress, 3.0)
        if env < 0 { env = 0 }
        // pseudo-noise from a deterministic hash of frame index
        h := math.sin(f64(idx) * 12.9898 + 78.233) * 43758.5453
        n := h - math.floor(h)             // 0..1
        sample := (n - 0.5) * 2.0          // -1..1
        pcm[idx] += f32(sample * env * f64(amp))
    }
}

@(private)
add_hihat :: proc(pcm: []f32, start_frame: int, length_frames: int, amp: f32) {
    for i in 0..<length_frames {
        idx := start_frame + i
        if idx < 0 || idx >= len(pcm) { continue }
        progress := f64(i) / f64(length_frames)
        env := math.pow(1.0 - progress, 5.0)
        if env < 0 { env = 0 }
        h := math.sin(f64(idx) * 91.1234 + 13.7) * 91827.331
        n := h - math.floor(h)
        sample := (n - 0.5) * 2.0
        pcm[idx] += f32(sample * env * f64(amp))
    }
}

@(private)
add_pulse :: proc(pcm: []f32, start_frame: int, length_frames: int, amp: f32, freq: f64, decay: f64) {
    sr := f64(MUSIC_SAMPLE_RATE)
    phase: f64 = 0.0
    for i in 0..<length_frames {
        idx := start_frame + i
        if idx < 0 || idx >= len(pcm) { continue }
        progress := f64(i) / f64(length_frames)
        env := math.pow(1.0 - progress, decay)
        if env < 0 { env = 0 }
        pcm[idx] += f32(math.sin(phase) * env * f64(amp))
        phase += 2.0 * math.PI * freq / sr
        if phase >= 2.0 * math.PI { phase -= 2.0 * math.PI }
    }
}

@(private)
add_drone :: proc(pcm: []f32, start_frame: int, length_frames: int, amp: f32, freq: f64) {
    sr := f64(MUSIC_SAMPLE_RATE)
    phase: f64 = 0.0
    fade_frames := length_frames / 16
    for i in 0..<length_frames {
        idx := start_frame + i
        if idx < 0 || idx >= len(pcm) { continue }
        env: f64 = 1.0
        if i < fade_frames               { env = f64(i) / f64(fade_frames) }
        if i > length_frames - fade_frames { env = f64(length_frames - i) / f64(fade_frames) }
        pcm[idx] += f32(math.sin(phase) * env * f64(amp))
        phase += 2.0 * math.PI * freq / sr
        if phase >= 2.0 * math.PI { phase -= 2.0 * math.PI }
    }
}

@(private)
add_bass_note :: proc(pcm: []f32, start_frame: int, length_frames: int, amp: f32, freq: f64) {
    sr := f64(MUSIC_SAMPLE_RATE)
    phase: f64 = 0.0
    attack := length_frames / 30
    if attack < 1 { attack = 1 }
    release := length_frames / 6
    if release < 1 { release = 1 }
    sustain_end := length_frames - release
    for i in 0..<length_frames {
        idx := start_frame + i
        if idx < 0 || idx >= len(pcm) { continue }
        env: f64 = 1.0
        if i < attack { env = f64(i) / f64(attack) }
        else if i > sustain_end { env = math.max(0.0, f64(length_frames - i) / f64(release)) }
        // sawtooth
        saw_phase := phase / (2.0 * math.PI)
        sample := 2.0 * (saw_phase - math.floor(0.5 + saw_phase))
        pcm[idx] += f32(sample * env * f64(amp))
        phase += 2.0 * math.PI * freq / sr
        if phase >= 2.0 * math.PI { phase -= 2.0 * math.PI }
    }
}

// Sax-like voice: saw + 2nd + 3rd harmonics, ADSR with longer tail, slight vibrato
@(private)
add_sax_note :: proc(pcm: []f32, start_frame: int, length_frames: int, amp: f32, freq: f64) {
    sr := f64(MUSIC_SAMPLE_RATE)
    phase: f64 = 0.0
    attack := length_frames / 14
    if attack < 1 { attack = 1 }
    decay := length_frames / 10
    if decay < 1 { decay = 1 }
    release := length_frames / 5
    if release < 1 { release = 1 }
    sustain_end := length_frames - release
    sustain_lvl :: f64(0.75)
    for i in 0..<length_frames {
        idx := start_frame + i
        if idx < 0 || idx >= len(pcm) { continue }
        env: f64 = 0.0
        if i < attack {
            env = f64(i) / f64(attack)
        } else if i < attack + decay {
            t := f64(i - attack) / f64(decay)
            env = 1.0 + (sustain_lvl - 1.0) * t
        } else if i < sustain_end {
            env = sustain_lvl
        } else {
            t := f64(i - sustain_end) / f64(release)
            env = math.max(0.0, sustain_lvl * (1.0 - t))
        }
        // 5Hz vibrato, ±1.5%
        t_sec := f64(i) / sr
        vibrato := 1.0 + 0.015 * math.sin(2.0 * math.PI * 5.0 * t_sec)
        eff_freq := freq * vibrato
        // sawtooth + 2nd + 3rd harmonics for reedy timbre
        saw := 2.0 * (phase / (2.0 * math.PI) - math.floor(0.5 + phase / (2.0 * math.PI)))
        h2  := math.sin(phase * 2.0)
        h3  := math.sin(phase * 3.0)
        sample := 0.55 * saw + 0.30 * h2 + 0.15 * h3
        pcm[idx] += f32(sample * env * f64(amp))
        phase += 2.0 * math.PI * eff_freq / sr
        if phase >= 2.0 * math.PI { phase -= 2.0 * math.PI }
    }
}

@(private)
clamp_pcm :: proc(pcm: []f32) {
    for i in 0..<len(pcm) {
        pcm[i] = math.clamp(pcm[i], -0.95, 0.95)
    }
}

// ============================================================================
// Track generators
// ============================================================================

@(private)
gen_splitter_track :: proc() {
    // 90 BPM, 4 bars of 4/4 = 16 beats.
    bpm: f32 = 90.0
    fpb := int(60.0 / bpm * f32(MUSIC_SAMPLE_RATE))
    total := fpb * 16
    splitter_track_pcm = make([]f32, total)
    for i in 0..<total { splitter_track_pcm[i] = 0.0 }

    // Bass: A1 (55Hz), A1, E2 (82.4Hz), A1 (one bar pattern, repeated 4 times)
    bass_freqs := [4]f64{ 55.0, 55.0, 82.4, 55.0 }
    for bar in 0..<4 {
        for beat in 0..<4 {
            note_start := (bar * 4 + beat) * fpb
            add_bass_note(splitter_track_pcm, note_start, fpb, 0.45, bass_freqs[beat])
        }
    }
    // Heavy kick on beats 1 and 3 of each bar
    kick_len := fpb / 3
    for bar in 0..<4 {
        for beat in 0..<4 {
            if beat == 0 || beat == 2 {
                add_kick(splitter_track_pcm, (bar * 4 + beat) * fpb, kick_len, 0.55)
            }
        }
    }
    clamp_pcm(splitter_track_pcm)
    fmt.printf("--- Splitter track generated (%d frames). ---\n", total)
}

@(private)
gen_sniper_track :: proc() {
    // 130 BPM, 4 bars. High pulse on every quarter. Low drone underneath.
    bpm: f32 = 130.0
    fpb := int(60.0 / bpm * f32(MUSIC_SAMPLE_RATE))
    total := fpb * 16
    sniper_track_pcm = make([]f32, total)
    for i in 0..<total { sniper_track_pcm[i] = 0.0 }

    // Low drone (G1 = 49Hz) across the whole loop
    add_drone(sniper_track_pcm, 0, total, 0.18, 49.0)

    // Tense high pulses (A5 = 880Hz) on every 8th note
    pulse_len := fpb / 4
    for step in 0..<32 {
        start := step * (fpb / 2)
        // Slight pitch bend on every 4th pulse
        freq := 880.0
        if step % 4 == 3 { freq = 1108.0 } // C#6 — leading-tone tension
        add_pulse(sniper_track_pcm, start, pulse_len, 0.30, freq, 4.5)
    }
    // Sub-bass thud on beat 1 of each bar
    for bar in 0..<4 {
        add_kick(sniper_track_pcm, bar * 4 * fpb, fpb / 4, 0.30)
    }
    clamp_pcm(sniper_track_pcm)
    fmt.printf("--- Sniper track generated (%d frames). ---\n", total)
}

@(private)
gen_disruptor_track :: proc() {
    // 180 BPM, 2 bars. Industrial four-on-the-floor + 16th hats.
    bpm: f32 = 180.0
    fpb := int(60.0 / bpm * f32(MUSIC_SAMPLE_RATE))
    total := fpb * 8
    disruptor_track_pcm = make([]f32, total)
    for i in 0..<total { disruptor_track_pcm[i] = 0.0 }

    // Kick every beat
    kick_len := fpb / 3
    for beat in 0..<8 {
        add_kick(disruptor_track_pcm, beat * fpb, kick_len, 0.6)
    }
    // Snare on 2 and 4 of each bar
    snare_len := fpb / 4
    for bar in 0..<2 {
        add_snare(disruptor_track_pcm, (bar * 4 + 1) * fpb, snare_len, 0.4)
        add_snare(disruptor_track_pcm, (bar * 4 + 3) * fpb, snare_len, 0.4)
    }
    // Hi-hat 16ths
    hat_len := fpb / 8
    for step in 0..<32 {
        start := step * (fpb / 4)
        add_hihat(disruptor_track_pcm, start, hat_len, 0.18)
    }
    // Buzzy bass riff on beats
    for beat in 0..<8 {
        f := 65.0 // C2
        if beat % 4 == 2 { f = 77.78 } // D#2
        add_bass_note(disruptor_track_pcm, beat * fpb, fpb / 2, 0.30, f)
    }
    clamp_pcm(disruptor_track_pcm)
    fmt.printf("--- Disruptor track generated (%d frames). ---\n", total)
}

@(private)
gen_boss_track :: proc() {
    // 105 BPM, 4 bars. Drums + sax-style melody. Pitch is later modulated upwards
    // via ma_sound_set_pitch as the boss takes damage, so the music intensifies.
    bpm: f32 = 105.0
    fpb := int(60.0 / bpm * f32(MUSIC_SAMPLE_RATE))
    total := fpb * 16
    boss_track_pcm = make([]f32, total)
    for i in 0..<total { boss_track_pcm[i] = 0.0 }

    // Drums: kick on 1+3, snare on 2+4, ride hat on every 8th
    kick_len  := fpb / 3
    snare_len := fpb / 4
    hat_len   := fpb / 6
    for bar in 0..<4 {
        for beat in 0..<4 {
            base := (bar * 4 + beat) * fpb
            if beat == 0 || beat == 2 { add_kick(boss_track_pcm, base, kick_len, 0.55) }
            if beat == 1 || beat == 3 { add_snare(boss_track_pcm, base, snare_len, 0.42) }
            // 8ths in this beat
            add_hihat(boss_track_pcm, base, hat_len, 0.16)
            add_hihat(boss_track_pcm, base + fpb / 2, hat_len, 0.16)
        }
    }

    // Sax line — D minor pentatonic walk (D2, F2, G2, A2, C3, A2, G2, F2 across bars 1-4),
    // each note held a half-bar so it feels like a slow ballad lead.
    // D2=73.42 F2=87.31 G2=98.00 A2=110.00 C3=130.81
    sax_pattern := [16]f64{
        // bar 1
        73.42, 73.42, 87.31, 87.31,
        // bar 2
        98.00, 98.00, 110.00, 110.00,
        // bar 3
        130.81, 110.00, 98.00, 87.31,
        // bar 4
        110.00, 98.00, 87.31, 73.42,
    }
    quarter := fpb
    for q in 0..<16 {
        add_sax_note(boss_track_pcm, q * quarter, quarter, 0.32, sax_pattern[q])
    }
    // Low sustained sax pad an octave below for warmth
    add_drone(boss_track_pcm, 0,            total / 2, 0.10, 36.71) // D1 first half
    add_drone(boss_track_pcm, total / 2, total / 2, 0.10, 49.00) // G1 second half

    clamp_pcm(boss_track_pcm)
    fmt.printf("--- Boss track generated (%d frames). ---\n", total)
}

// ============================================================================
// Init / cleanup / update
// ============================================================================

@(private)
init_music_sound :: proc(pcm: []f32, buf: ^ma.audio_buffer, snd: ^ma.sound, allow_pitch: bool, label: string) {
    cfg := ma.audio_buffer_config_init(.f32, u32(MUSIC_CHANNELS), u64(len(pcm)), rawptr(&pcm[0]), nil)
    if ma.audio_buffer_init_copy(&cfg, buf) != .SUCCESS {
        fmt.eprintf("!!! music: audio_buffer_init_copy failed for %s\n", label)
        return
    }
    flags: ma.sound_flags = { .NO_SPATIALIZATION }
    if !allow_pitch { flags |= { .NO_PITCH } }
    if ma.sound_init_from_data_source(&shared.state.audio_engine, (^ma.data_source)(buf), flags, nil, snd) != .SUCCESS {
        fmt.eprintf("!!! music: sound_init failed for %s\n", label)
        ma.audio_buffer_uninit(buf)
        return
    }
    ma.sound_set_looping(snd, true)
    ma.sound_set_volume(snd, 0.0)
    ma.sound_start(snd)
    fmt.printf("--- music track '%s' running (volume 0, looped) ---\n", label)
}

init_music_tracks :: proc() {
    if music_state.initialized { return }
    gen_splitter_track()
    gen_sniper_track()
    gen_disruptor_track()
    gen_boss_track()

    init_music_sound(splitter_track_pcm,  &splitter_track_buf,  &shared.state.splitter_track_sound,  false, "splitter")
    init_music_sound(sniper_track_pcm,    &sniper_track_buf,    &shared.state.sniper_track_sound,    false, "sniper")
    init_music_sound(disruptor_track_pcm, &disruptor_track_buf, &shared.state.disruptor_track_sound, false, "disruptor")
    // Boss track allows pitch shifting so we can speed it up as HP drops.
    init_music_sound(boss_track_pcm,      &boss_track_buf,      &shared.state.boss_track_sound,      true,  "boss")

    music_state.current_boss_pitch = 1.0
    music_state.target_boss_pitch  = 1.0
    music_state.initialized = true

    // Existing grunt + slowboy tracks: also run at vol 0 from boot and let update_music control them.
    ma.sound_set_volume(&shared.state.drum_track_sound, 0.0)
    ma.sound_set_volume(&shared.state.synth_track_sound, 0.0)
    if ma.sound_start(&shared.state.drum_track_sound) != .SUCCESS {
        fmt.eprintf("warn: drum_track_sound start (already started?)\n")
    }
    if ma.sound_start(&shared.state.synth_track_sound) != .SUCCESS {
        fmt.eprintf("warn: synth_track_sound start (already started?)\n")
    }
    _ = rand.float32 // keep rand import used elsewhere consistent
}

cleanup_music_tracks :: proc() {
    if !music_state.initialized { return }
    ma.sound_uninit(&shared.state.splitter_track_sound)
    ma.sound_uninit(&shared.state.sniper_track_sound)
    ma.sound_uninit(&shared.state.disruptor_track_sound)
    ma.sound_uninit(&shared.state.boss_track_sound)
    ma.audio_buffer_uninit(&splitter_track_buf)
    ma.audio_buffer_uninit(&sniper_track_buf)
    ma.audio_buffer_uninit(&disruptor_track_buf)
    ma.audio_buffer_uninit(&boss_track_buf)
    delete(splitter_track_pcm)
    delete(sniper_track_pcm)
    delete(disruptor_track_pcm)
    delete(boss_track_pcm)
}

@(private)
approach :: proc(current, target, step: f32) -> f32 {
    if current < target { return math.min(current + step, target) }
    if current > target { return math.max(current - step, target) }
    return current
}

update_music :: proc(dt: f32) {
    if !music_state.initialized { return }

    // Capture boss HP if present, and count live disruptors (the only alive-gated track).
    boss_alive := false
    boss_hp_ratio: f32 = 1.0
    disruptor_n: int = 0
    for i in 0..<shared.MAX_ENEMIES {
        e := &shared.state.enemies[i]
        if !e.active || e.is_dying { continue }
        if e.type == .DISRUPTOR { disruptor_n += 1 }
        if e.type == .BOSS_CHROME_ORB {
            boss_alive = true
            if shared.ENEMY_BOSS_CHROME_ORB_MAX_HP > 0 {
                boss_hp_ratio = math.clamp(f32(e.hp) / f32(shared.ENEMY_BOSS_CHROME_ORB_MAX_HP), 0.0, 1.0)
            }
        }
    }

    // Default targets: silence everything.
    music_state.target_grunt     = 0
    music_state.target_slowboy   = 0
    music_state.target_splitter  = 0
    music_state.target_sniper    = 0
    music_state.target_disruptor = 0
    music_state.target_boss      = 0
    music_state.target_boss_pitch = 1.0

    if boss_alive {
        // Boss music takes over solo; pitch ramps up as boss takes damage.
        music_state.target_boss = BOSS_TRACK_VOL
        chaos := 1.0 - boss_hp_ratio
        music_state.target_boss_pitch = 1.0 + chaos * 0.55
    } else {
        // Persistent unlocks: each track activates on first kill of that type and stays on.
        if shared.state.first_grunt_killed     { music_state.target_grunt    = GRUNT_TRACK_VOL }
        if shared.state.first_slowboy_killed   { music_state.target_slowboy  = SLOWBOY_TRACK_VOL }
        if shared.state.first_splitter_killed  { music_state.target_splitter = SPLITTER_TRACK_VOL }
        if shared.state.first_sniper_killed    { music_state.target_sniper   = SNIPER_TRACK_VOL }
        // Disruptor stays alive-gated — the runner-up only haunts you while it's actually rushing.
        if disruptor_n > 0                     { music_state.target_disruptor = DISRUPTOR_TRACK_VOL }
    }

    // Lerp current volumes toward targets.
    step := MUSIC_FADE_RATE * dt
    music_state.current_grunt     = approach(music_state.current_grunt,     music_state.target_grunt,     step)
    music_state.current_slowboy   = approach(music_state.current_slowboy,   music_state.target_slowboy,   step)
    music_state.current_splitter  = approach(music_state.current_splitter,  music_state.target_splitter,  step)
    music_state.current_sniper    = approach(music_state.current_sniper,    music_state.target_sniper,    step)
    music_state.current_disruptor = approach(music_state.current_disruptor, music_state.target_disruptor, step)
    music_state.current_boss      = approach(music_state.current_boss,      music_state.target_boss,      step)

    ma.sound_set_volume(&shared.state.drum_track_sound,      music_state.current_grunt)
    ma.sound_set_volume(&shared.state.synth_track_sound,     music_state.current_slowboy)
    ma.sound_set_volume(&shared.state.splitter_track_sound,  music_state.current_splitter)
    ma.sound_set_volume(&shared.state.sniper_track_sound,    music_state.current_sniper)
    ma.sound_set_volume(&shared.state.disruptor_track_sound, music_state.current_disruptor)
    ma.sound_set_volume(&shared.state.boss_track_sound,      music_state.current_boss)

    // Pitch on the boss track changes more slowly so it's perceived as "speeding up over time"
    // rather than snapping with each laser added.
    pitch_step := f32(0.25) * dt
    music_state.current_boss_pitch = approach(music_state.current_boss_pitch, music_state.target_boss_pitch, pitch_step)
    ma.sound_set_pitch(&shared.state.boss_track_sound, music_state.current_boss_pitch)
}
