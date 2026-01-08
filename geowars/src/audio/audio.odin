package audio

import ma "../vendor/miniaudio"
import m "../vendor/math"
import "core:math"
import "core:fmt"
import sa "../vendor/sokol/audio"
import rand "core:math/rand"
import "base:runtime"
import "core:c"
import shared "../shared"

// --- Global Variables and Constants (Internal to audio package) ---

// LMB Sound Definitions
LMB_SOUND_SAMPLE_RATE :: 44100
LMB_SOUND_CHANNELS :: 1
LMB_SOUND_DURATION_MS :: 100
LMB_SOUND_FRAMES :: LMB_SOUND_SAMPLE_RATE * LMB_SOUND_DURATION_MS / 1000
LMB_SOUND_START_FREQ :: 1200.0
LMB_SOUND_END_FREQ :: 400.0
LMB_SOUND_AMPLITUDE :: 0.25
lmb_sound_pcm_data: [LMB_SOUND_FRAMES]f32
lmb_sound_audio_buffer: ma.audio_buffer

// RMB Particle Sound Definitions
RMB_HUM_FREQUENCY :: 100.0
RMB_HUM_AMPLITUDE :: 0.1
RMB_PARTICLE_SOUND_DURATION_FRAMES :: LMB_SOUND_SAMPLE_RATE / 2
RMB_WHOOSH_AMPLITUDE :: 0.25
MAX_PARTICLE_SPEED_FOR_SOUND_EFFECT :: 5.0
rmb_hum_pcm_data: [RMB_PARTICLE_SOUND_DURATION_FRAMES]f32
rmb_whoosh_pcm_data: [RMB_PARTICLE_SOUND_DURATION_FRAMES]f32
rmb_hum_audio_buffer: ma.audio_buffer
rmb_whoosh_audio_buffer: ma.audio_buffer

// LMB Hit Sound Effects Definitions
LMB_HIT_WHOOSH_DURATION_FRAMES :: LMB_SOUND_SAMPLE_RATE / 10
LMB_HIT_WHOOSH_AMPLITUDE :: 0.4
LMB_KILL_EXPLOSION_DURATION_FRAMES :: LMB_SOUND_SAMPLE_RATE / 2
LMB_KILL_EXPLOSION_AMPLITUDE :: 0.5
lmb_hit_whoosh_pcm_data: [LMB_HIT_WHOOSH_DURATION_FRAMES]f32
lmb_hit_whoosh_audio_buffer: ma.audio_buffer
lmb_kill_explosion_pcm_data: [LMB_KILL_EXPLOSION_DURATION_FRAMES]f32
lmb_kill_explosion_audio_buffer: ma.audio_buffer

// Enemy Hit Sound Definitions
ENEMY_HIT_SOUND_DURATION_MS :: 50
ENEMY_HIT_SOUND_FRAMES :: LMB_SOUND_SAMPLE_RATE * ENEMY_HIT_SOUND_DURATION_MS / 1000
ENEMY_HIT_SOUND_START_FREQ :: 800.0
ENEMY_HIT_SOUND_END_FREQ :: 600.0
ENEMY_HIT_SOUND_AMPLITUDE :: 0.35
enemy_hit_sound_pcm_data: [ENEMY_HIT_SOUND_FRAMES]f32
enemy_hit_sound_audio_buffer: ma.audio_buffer

// Enemy Death Sound Definitions
ENEMY_DEATH_SOUND_DURATION_MS :: 200
ENEMY_DEATH_SOUND_FRAMES :: LMB_SOUND_SAMPLE_RATE * ENEMY_DEATH_SOUND_DURATION_MS / 1000
ENEMY_DEATH_SOUND_NOISE_DURATION_FRAMES :: ENEMY_DEATH_SOUND_FRAMES / 4
ENEMY_DEATH_SOUND_NOISE_AMPLITUDE :: 0.25
ENEMY_DEATH_SOUND_SINE_START_FREQ :: 250.0
ENEMY_DEATH_SOUND_SINE_END_FREQ :: 50.0
ENEMY_DEATH_SOUND_SINE_AMPLITUDE :: 0.20
enemy_death_sound_pcm_data: [ENEMY_DEATH_SOUND_FRAMES]f32
enemy_death_sound_audio_buffer: ma.audio_buffer

// Drum Track Definitions
DRUM_TRACK_SAMPLE_RATE :: LMB_SOUND_SAMPLE_RATE
DRUM_TRACK_CHANNELS :: LMB_SOUND_CHANNELS
DRUM_TRACK_BPM :: 160.0
DRUM_TRACK_BEATS_PER_BAR :: 4
DRUM_TRACK_NUM_BARS :: 2
DRUM_TRACK_SECONDS_PER_BEAT :: 60.0 / DRUM_TRACK_BPM
DRUM_TRACK_AMPLITUDE :: 0.6
drum_track_pcm_data: []f32
drum_track_audio_buffer: ma.audio_buffer

// SYNTH TRACK DEFINITIONS
SYNTH_TRACK_SAMPLE_RATE :: DRUM_TRACK_SAMPLE_RATE
SYNTH_TRACK_CHANNELS :: DRUM_TRACK_CHANNELS
SYNTH_TRACK_BPM :: DRUM_TRACK_BPM
SYNTH_TRACK_BEATS_PER_BAR :: DRUM_TRACK_BEATS_PER_BAR
SYNTH_TRACK_NUM_BARS :: DRUM_TRACK_NUM_BARS
SYNTH_TRACK_AMPLITUDE :: 0.30
SYNTH_NOTE_ATTACK_TIME_S :: 0.02
SYNTH_NOTE_DECAY_TIME_S :: 0.1
SYNTH_NOTE_SUSTAIN_LEVEL :: 0.6
SYNTH_NOTE_RELEASE_TIME_S :: 0.05
synth_track_pcm_data: []f32
synth_track_audio_buffer: ma.audio_buffer

// --- Procedures ---
init_audio :: proc(state: ^shared.GameState) {
    // Calculate Drum Track Frame Counts
    DRUM_TRACK_FRAMES_PER_BEAT_F32 := DRUM_TRACK_SECONDS_PER_BEAT * f32(DRUM_TRACK_SAMPLE_RATE);
    DRUM_TRACK_FRAMES_PER_BEAT := int(math.round_f32(DRUM_TRACK_FRAMES_PER_BEAT_F32));
    DRUM_TRACK_FRAMES_PER_BAR := DRUM_TRACK_FRAMES_PER_BEAT * DRUM_TRACK_BEATS_PER_BAR;
    DRUM_TRACK_TOTAL_FRAMES := DRUM_TRACK_FRAMES_PER_BAR * DRUM_TRACK_NUM_BARS;
    
    drum_track_pcm_data = make([]f32, DRUM_TRACK_TOTAL_FRAMES);
    if drum_track_pcm_data == nil {
        fmt.eprintf("!!! CRITICAL: Failed to allocate drum_track_pcm_data slice! Total Frames: %d", DRUM_TRACK_TOTAL_FRAMES);
        return; 
    }
    fmt.printf("--- Drum track PCM data slice allocated. Total Frames: %d ---", DRUM_TRACK_TOTAL_FRAMES);

    KICK_DURATION_FRAMES: int = DRUM_TRACK_FRAMES_PER_BEAT / 3; 
    KICK_START_FREQ :: 120.0; KICK_END_FREQ :: 40.0; RELATIVE_KICK_AMPLITUDE  := 0.6;
    SNARE_DURATION_FRAMES: int = DRUM_TRACK_FRAMES_PER_BEAT / 6;
    SNARE_START_FREQ :: 220.0; RELATIVE_SNARE_AMPLITUDE  := 0.4;
    HIHAT_DURATION_FRAMES: int = DRUM_TRACK_FRAMES_PER_BEAT / 16;
    HIHAT_FREQ :: 6000.0; RELATIVE_HIHAT_AMPLITUDE   := 0.15;

    // Zero out
    for i in 0..<DRUM_TRACK_TOTAL_FRAMES { drum_track_pcm_data[i] = 0.0 }

    for bar_idx in 0..<DRUM_TRACK_NUM_BARS {
        for beat_num_in_bar in 0..<DRUM_TRACK_BEATS_PER_BAR {
            beat_start_frame_offset := beat_num_in_bar * DRUM_TRACK_FRAMES_PER_BEAT;
            current_beat_global_start_frame := (bar_idx * DRUM_TRACK_FRAMES_PER_BAR) + beat_start_frame_offset;

            // Kick
            if beat_num_in_bar == 0 || beat_num_in_bar == 2 {
                current_phase_kick: f64 = 0.0;
                for kick_i in 0..<KICK_DURATION_FRAMES {
                    frame_in_track := current_beat_global_start_frame + kick_i;
                    if frame_in_track >= DRUM_TRACK_TOTAL_FRAMES { break }
                    progress := f64(kick_i) / f64(KICK_DURATION_FRAMES);
                    amp := math.max(0.0, math.pow_f64(1.0 - progress, 2.5));
                    freq := f64(KICK_START_FREQ) * math.pow_f64(f64(KICK_END_FREQ) / f64(KICK_START_FREQ), progress);
                    drum_track_pcm_data[frame_in_track] += f32(math.sin(current_phase_kick) * amp * f64(RELATIVE_KICK_AMPLITUDE));
                    current_phase_kick += (2.0 * f64(math.PI) * freq) / f64(DRUM_TRACK_SAMPLE_RATE);
                }
            }
            // Snare
            if beat_num_in_bar == 1 || beat_num_in_bar == 3 {
                current_phase_snare: f64 = 0.0;
                for snare_i in 0..<SNARE_DURATION_FRAMES {
                    frame_in_track := current_beat_global_start_frame + snare_i;
                    if frame_in_track >= DRUM_TRACK_TOTAL_FRAMES { break }
                    progress := f64(snare_i) / f64(SNARE_DURATION_FRAMES);
                    amp := math.max(0.0, math.pow_f64(1.0 - progress, 3.5));
                    drum_track_pcm_data[frame_in_track] += f32(math.sin(current_phase_snare) * amp * f64(RELATIVE_SNARE_AMPLITUDE));
                    current_phase_snare += (2.0 * f64(math.PI) * f64(SNARE_START_FREQ)) / f64(DRUM_TRACK_SAMPLE_RATE);
                }
            }
        }
        // HiHats
        for eighth_note_in_bar_idx in 0..<(DRUM_TRACK_BEATS_PER_BAR * 2) {
            eighth_note_offset_from_bar_start := eighth_note_in_bar_idx * (DRUM_TRACK_FRAMES_PER_BEAT / 2);
            hihat_global_start_frame := (bar_idx * DRUM_TRACK_FRAMES_PER_BAR) + eighth_note_offset_from_bar_start;
            
            is_on_kick_pos  := (eighth_note_in_bar_idx == 0 || eighth_note_in_bar_idx == 4); 
            is_on_snare_pos := (eighth_note_in_bar_idx == 2 || eighth_note_in_bar_idx == 6);

            if !is_on_kick_pos && !is_on_snare_pos {
                current_phase_hihat: f64 = 0.0;
                for hihat_i in 0..<HIHAT_DURATION_FRAMES {
                    frame_in_track := hihat_global_start_frame + hihat_i;
                    if frame_in_track >= DRUM_TRACK_TOTAL_FRAMES { break }
                    progress := f64(hihat_i) / f64(HIHAT_DURATION_FRAMES);
                    amp := math.max(0.0, math.pow_f64(1.0 - progress, 2.0));
                    drum_track_pcm_data[frame_in_track] += f32(math.sin(current_phase_hihat) * amp * f64(RELATIVE_HIHAT_AMPLITUDE));
                    current_phase_hihat += (2.0 * f64(math.PI) * f64(HIHAT_FREQ)) / f64(DRUM_TRACK_SAMPLE_RATE);
                }
            }
        }
    }
    
    // Clamp
    for i in 0..<DRUM_TRACK_TOTAL_FRAMES {
        drum_track_pcm_data[i] = math.clamp(drum_track_pcm_data[i], -0.95, 0.95);
    }

    // Sokol Audio Setup
    sokol_audio_desc := sa.Desc {
        sample_rate = LMB_SOUND_SAMPLE_RATE, 
        num_channels = LMB_SOUND_CHANNELS,   
        buffer_frames = 1024, 
        packet_frames = 0,   
        num_packets = 0,     
        stream_userdata_cb = geowars_audio_stream_callback,
        user_data = &state.audio_engine,
    }
    sa.setup(sokol_audio_desc)

    // Miniaudio Engine Setup
    engine_config := ma.engine_config_init()
    engine_config.noDevice = true 
    engine_config.channels = u32(LMB_SOUND_CHANNELS)   
    engine_config.sampleRate = u32(LMB_SOUND_SAMPLE_RATE) 

    ma.engine_init(&engine_config, &state.audio_engine)

    // Generate Pew Sound
    current_phase_lmb: f64 = 0.0
    for i in 0..<LMB_SOUND_FRAMES {
        progress := f64(i) / f64(LMB_SOUND_FRAMES)
        amp: f64
        attack_time := 0.15
        if progress < attack_time { amp = progress / attack_time }
        else { amp = 1.0 - (progress - attack_time) / (1.0 - attack_time) }
        amp = math.max(0.0, amp)
        ratio := LMB_SOUND_END_FREQ / LMB_SOUND_START_FREQ
        freq := f64(LMB_SOUND_START_FREQ) * math.pow(f64(ratio), progress)
        lmb_sound_pcm_data[i] = f32(math.sin(current_phase_lmb) * amp * f64(LMB_SOUND_AMPLITUDE))
        current_phase_lmb += (2.0 * math.PI * freq) / f64(LMB_SOUND_SAMPLE_RATE)
    }

    // Init Sounds
    audio_buffer_config_lmb := ma.audio_buffer_config_init(ma.format.f32, u32(LMB_SOUND_CHANNELS), u64(LMB_SOUND_FRAMES), rawptr(&lmb_sound_pcm_data[0]), nil)
    ma.audio_buffer_init_copy(&audio_buffer_config_lmb, &lmb_sound_audio_buffer)
    ma.sound_init_from_data_source(&state.audio_engine, (^ma.data_source)(&lmb_sound_audio_buffer), { .NO_PITCH, .NO_SPATIALIZATION }, nil, &state.lmb_sound)

    // Particle Sounds (Hum)
    hum_waveform_config := ma.waveform_config_init( ma.format.f32, u32(LMB_SOUND_CHANNELS), u32(LMB_SOUND_SAMPLE_RATE), ma.waveform_type.sine, f64(RMB_HUM_AMPLITUDE), f64(RMB_HUM_FREQUENCY))
    hum_sine_wave_gen: ma.waveform
    ma.waveform_init(&hum_waveform_config, &hum_sine_wave_gen)
    frames_read_hum: u64
    ma.waveform_read_pcm_frames(&hum_sine_wave_gen, rawptr(&rmb_hum_pcm_data[0]), u64(RMB_PARTICLE_SOUND_DURATION_FRAMES), &frames_read_hum)
    ma.waveform_uninit(&hum_sine_wave_gen)

    hum_ab_config := ma.audio_buffer_config_init(ma.format.f32, u32(LMB_SOUND_CHANNELS), u64(RMB_PARTICLE_SOUND_DURATION_FRAMES), rawptr(&rmb_hum_pcm_data[0]), nil)
    ma.audio_buffer_init_copy(&hum_ab_config, &rmb_hum_audio_buffer)

    // Particle Sounds (Whoosh)
    whoosh_noise_config := ma.noise_config_init(ma.format.f32, u32(LMB_SOUND_CHANNELS), ma.noise_type.pink, 0, f64(RMB_WHOOSH_AMPLITUDE))
    whoosh_noise_gen: ma.noise
    ma.noise_init(&whoosh_noise_config, nil, &whoosh_noise_gen)
    frames_read_whoosh: u64
    ma.noise_read_pcm_frames(&whoosh_noise_gen, rawptr(&rmb_whoosh_pcm_data[0]), u64(RMB_PARTICLE_SOUND_DURATION_FRAMES), &frames_read_whoosh)
    ma.noise_uninit(&whoosh_noise_gen, nil)

    whoosh_ab_config := ma.audio_buffer_config_init(ma.format.f32, u32(LMB_SOUND_CHANNELS), u64(RMB_PARTICLE_SOUND_DURATION_FRAMES), rawptr(&rmb_whoosh_pcm_data[0]), nil)
    ma.audio_buffer_init_copy(&whoosh_ab_config, &rmb_whoosh_audio_buffer)

    // Enemy Hit Sound
    current_phase_enemy_hit: f64 = 0.0
    for i in 0..<ENEMY_HIT_SOUND_FRAMES {
        progress := f64(i) / f64(ENEMY_HIT_SOUND_FRAMES)
        amp: f64
        attack := 0.1
        if progress < attack { amp = f64(progress) / attack } else { amp = 1.0 - (f64(progress) - attack) / (1.0 - attack) }
        amp = math.max(0.0, amp)
        ratio := ENEMY_HIT_SOUND_END_FREQ / ENEMY_HIT_SOUND_START_FREQ
        freq := f64(ENEMY_HIT_SOUND_START_FREQ) * math.pow(f64(ratio), progress)
        enemy_hit_sound_pcm_data[i] = f32(math.sin(current_phase_enemy_hit) * amp * f64(ENEMY_HIT_SOUND_AMPLITUDE))
        current_phase_enemy_hit += (2.0 * math.PI * freq) / f64(LMB_SOUND_SAMPLE_RATE)
    }

    enemy_hit_ab_config := ma.audio_buffer_config_init(ma.format.f32, u32(LMB_SOUND_CHANNELS), u64(ENEMY_HIT_SOUND_FRAMES), rawptr(&enemy_hit_sound_pcm_data[0]), nil)
    ma.audio_buffer_init_copy(&enemy_hit_ab_config, &enemy_hit_sound_audio_buffer)
    ma.sound_init_from_data_source(&state.audio_engine, (^ma.data_source)(&enemy_hit_sound_audio_buffer), { .NO_PITCH, .NO_SPATIALIZATION }, nil, &state.rmb_hit_sound)
    ma.sound_set_volume(&state.rmb_hit_sound, ENEMY_HIT_SOUND_AMPLITUDE)

    // Enemy Death Sound
    current_phase_enemy_death_sine: f64 = 0.0
    rng_seed: u64 = 12345
    death_rng := rand.create(rng_seed)
    for i in 0..<ENEMY_DEATH_SOUND_FRAMES {
        if i < ENEMY_DEATH_SOUND_NOISE_DURATION_FRAMES {
            progress := f32(i) / f32(ENEMY_DEATH_SOUND_NOISE_DURATION_FRAMES)
            decay := math.max(0.0, 1.0 - progress)
            gen := rand.default_random_generator(&death_rng)
            sample := (rand.float32(gen) * 2.0 - 1.0)
            enemy_death_sound_pcm_data[i] = sample * ENEMY_DEATH_SOUND_NOISE_AMPLITUDE * decay
        } else {
            sine_idx := i - ENEMY_DEATH_SOUND_NOISE_DURATION_FRAMES
            total := ENEMY_DEATH_SOUND_FRAMES - ENEMY_DEATH_SOUND_NOISE_DURATION_FRAMES
            progress := f64(sine_idx) / f64(total)
            decay := math.max(0.0, 1.0 - progress)
            ratio := ENEMY_DEATH_SOUND_SINE_END_FREQ / ENEMY_DEATH_SOUND_SINE_START_FREQ
            freq := f64(ENEMY_DEATH_SOUND_SINE_START_FREQ) * math.pow(f64(ratio), progress)
            enemy_death_sound_pcm_data[i] = f32(math.sin(current_phase_enemy_death_sine) * decay * f64(ENEMY_DEATH_SOUND_SINE_AMPLITUDE))
            current_phase_enemy_death_sine += (2.0 * math.PI * freq) / f64(LMB_SOUND_SAMPLE_RATE)
        }
    }

    enemy_death_ab_config := ma.audio_buffer_config_init(ma.format.f32, u32(LMB_SOUND_CHANNELS), u64(ENEMY_DEATH_SOUND_FRAMES), rawptr(&enemy_death_sound_pcm_data[0]), nil)
    ma.audio_buffer_init_copy(&enemy_death_ab_config, &enemy_death_sound_audio_buffer)
    ma.sound_init_from_data_source(&state.audio_engine, (^ma.data_source)(&enemy_death_sound_audio_buffer), { .NO_PITCH, .NO_SPATIALIZATION }, nil, &state.rmb_kill_sound)
    ma.sound_set_volume(&state.rmb_kill_sound, ENEMY_DEATH_SOUND_SINE_AMPLITUDE + ENEMY_DEATH_SOUND_NOISE_AMPLITUDE)

    // LMB Hit Whoosh
    lmb_hit_rng_seed: u64 = 67890
    lmb_hit_rng := rand.create(lmb_hit_rng_seed)
    for i in 0..<LMB_HIT_WHOOSH_DURATION_FRAMES {
        progress := f32(i) / f32(LMB_HIT_WHOOSH_DURATION_FRAMES)
        amp: f32
        attack : f32 = 0.05
        if progress < attack { amp = progress / attack } else { amp = 1.0 - (progress - attack) / 0.95 }
        amp = math.max(0.0, amp)
        gen := rand.default_random_generator(&lmb_hit_rng)
        sample := (rand.float32(gen) * 2.0 - 1.0)
        lmb_hit_whoosh_pcm_data[i] = sample * LMB_HIT_WHOOSH_AMPLITUDE * amp
    }

    lmb_hit_ab_config := ma.audio_buffer_config_init(ma.format.f32, u32(LMB_SOUND_CHANNELS), u64(LMB_HIT_WHOOSH_DURATION_FRAMES), rawptr(&lmb_hit_whoosh_pcm_data[0]), nil)
    ma.audio_buffer_init_copy(&lmb_hit_ab_config, &lmb_hit_whoosh_audio_buffer)
    ma.sound_init_from_data_source(&state.audio_engine, (^ma.data_source)(&lmb_hit_whoosh_audio_buffer), { .NO_PITCH, .NO_SPATIALIZATION }, nil, &state.lmb_hit_sound)
    ma.sound_set_volume(&state.lmb_hit_sound, LMB_HIT_WHOOSH_AMPLITUDE)

    // LMB Kill Explosion
    lmb_kill_rng_seed: u64 = 78901
    lmb_kill_rng := rand.create(lmb_kill_rng_seed)
    EXP_NOISE := LMB_KILL_EXPLOSION_DURATION_FRAMES / 5
    current_phase_exp: f64 = 0.0
    for i in 0..<LMB_KILL_EXPLOSION_DURATION_FRAMES {
        if i < EXP_NOISE {
            progress := f32(i) / f32(EXP_NOISE)
            decay := math.pow(1.0 - progress, 2.0)
            gen := rand.default_random_generator(&lmb_kill_rng)
            sample := (rand.float32(gen) * 2.0 - 1.0)
            lmb_kill_explosion_pcm_data[i] = sample * LMB_KILL_EXPLOSION_AMPLITUDE * decay * 0.7
        } else {
            sine_idx := i - EXP_NOISE
            total := LMB_KILL_EXPLOSION_DURATION_FRAMES - EXP_NOISE
            progress := f64(sine_idx) / f64(total)
            decay := math.pow(1.0 - progress, 3.0)
            ratio := 40.0 / 150.0 // End / Start
            freq := 150.0 * math.pow(ratio, progress)
            lmb_kill_explosion_pcm_data[i] = f32(math.sin(current_phase_exp) * decay * f64(LMB_KILL_EXPLOSION_AMPLITUDE))
            current_phase_exp += (2.0 * math.PI * freq) / f64(LMB_SOUND_SAMPLE_RATE)
        }
    }

    lmb_kill_ab_config := ma.audio_buffer_config_init(ma.format.f32, u32(LMB_SOUND_CHANNELS), u64(LMB_KILL_EXPLOSION_DURATION_FRAMES), rawptr(&lmb_kill_explosion_pcm_data[0]), nil)
    ma.audio_buffer_init_copy(&lmb_kill_ab_config, &lmb_kill_explosion_audio_buffer)
    ma.sound_init_from_data_source(&state.audio_engine, (^ma.data_source)(&lmb_kill_explosion_audio_buffer), { .NO_PITCH, .NO_SPATIALIZATION }, nil, &state.lmb_kill_sound)
    ma.sound_set_volume(&state.lmb_kill_sound, LMB_KILL_EXPLOSION_AMPLITUDE)

    // Drum Track
    drum_ab_config := ma.audio_buffer_config_init(ma.format.f32, u32(DRUM_TRACK_CHANNELS), u64(DRUM_TRACK_TOTAL_FRAMES), rawptr(&drum_track_pcm_data[0]), nil)
    ma.audio_buffer_init_copy(&drum_ab_config, &drum_track_audio_buffer)
    ma.sound_init_from_data_source(&state.audio_engine, (^ma.data_source)(&drum_track_audio_buffer), { .NO_PITCH, .NO_SPATIALIZATION }, nil, &state.drum_track_sound)
    ma.sound_set_looping(&state.drum_track_sound, true)
    ma.sound_set_volume(&state.drum_track_sound, DRUM_TRACK_AMPLITUDE)

    // Synth Track Generation & Init
    SYNTH_TRACK_SECONDS_PER_BEAT_CALC : f32 = 60.0 / SYNTH_TRACK_BPM;
    SYNTH_TRACK_FRAMES_PER_BEAT_F32_CALC : f32 = SYNTH_TRACK_SECONDS_PER_BEAT_CALC * f32(SYNTH_TRACK_SAMPLE_RATE);
    SYNTH_TRACK_FRAMES_PER_BEAT_CALC := int(math.round_f32(SYNTH_TRACK_FRAMES_PER_BEAT_F32_CALC));
    SYNTH_TRACK_FRAMES_PER_BAR_CALC := SYNTH_TRACK_FRAMES_PER_BEAT_CALC * SYNTH_TRACK_BEATS_PER_BAR;
    SYNTH_TRACK_TOTAL_FRAMES_CALC := SYNTH_TRACK_FRAMES_PER_BAR_CALC * SYNTH_TRACK_NUM_BARS;

    synth_track_pcm_data = make([]f32, SYNTH_TRACK_TOTAL_FRAMES_CALC);
    if synth_track_pcm_data == nil {
        fmt.eprintf("!!! CRITICAL: Failed to allocate synth_track_pcm_data! Total Frames: %d\n", SYNTH_TRACK_TOTAL_FRAMES_CALC);
        return;
    }
    for i in 0..<SYNTH_TRACK_TOTAL_FRAMES_CALC { synth_track_pcm_data[i] = 0.0; }

    synth_attack_frames  := int(SYNTH_NOTE_ATTACK_TIME_S * f32(SYNTH_TRACK_SAMPLE_RATE));
    synth_decay_frames   := int(SYNTH_NOTE_DECAY_TIME_S * f32(SYNTH_TRACK_SAMPLE_RATE));
    synth_release_frames := int(SYNTH_NOTE_RELEASE_TIME_S * f32(SYNTH_TRACK_SAMPLE_RATE));
    NOTE_DURATION_FRAMES_8TH_SYNTH := SYNTH_TRACK_FRAMES_PER_BEAT_CALC / 2;
    synth_sustain_duration_frames := NOTE_DURATION_FRAMES_8TH_SYNTH - synth_attack_frames - synth_decay_frames - synth_release_frames;
    if synth_sustain_duration_frames < 0 { synth_sustain_duration_frames = 0; } 

    note_frequencies_synth := [SYNTH_TRACK_NUM_BARS][SYNTH_TRACK_BEATS_PER_BAR * 2]f32 {};
    for i in 0..<(SYNTH_TRACK_BEATS_PER_BAR * 2) { note_frequencies_synth[0][i] = 110.0; } // A2
    for i in 0..<(SYNTH_TRACK_BEATS_PER_BAR * 2) { note_frequencies_synth[1][i] = 130.81; } // C3

    current_phase_synth_gen: f64 = 0.0;

    for bar_s_idx in 0..<SYNTH_TRACK_NUM_BARS {
        for eighth_note_s_idx in 0..<(SYNTH_TRACK_BEATS_PER_BAR * 2) {
            note_start_frame_in_track_s := (bar_s_idx * SYNTH_TRACK_FRAMES_PER_BAR_CALC) + (eighth_note_s_idx * NOTE_DURATION_FRAMES_8TH_SYNTH);
            current_note_freq_s := f64(note_frequencies_synth[bar_s_idx][eighth_note_s_idx]);

            for frame_in_note_s in 0..<NOTE_DURATION_FRAMES_8TH_SYNTH {
                global_frame_idx_s := note_start_frame_in_track_s + frame_in_note_s;
                if global_frame_idx_s >= SYNTH_TRACK_TOTAL_FRAMES_CALC { break; }

                envelope_amp_s: f32 = 0.0;
                if frame_in_note_s < synth_attack_frames {
                    envelope_amp_s = f32(frame_in_note_s) / f32(math.max(1,synth_attack_frames));
                } else if frame_in_note_s < synth_attack_frames + synth_decay_frames {
                    progress_decay_s := f32(frame_in_note_s - synth_attack_frames) / f32(math.max(1,synth_decay_frames));
                    envelope_amp_s = f32(m.lerp(f32(1.0), f32(SYNTH_NOTE_SUSTAIN_LEVEL), f32(progress_decay_s)));
                } else if frame_in_note_s < synth_attack_frames + synth_decay_frames + synth_sustain_duration_frames {
                    envelope_amp_s = f32(SYNTH_NOTE_SUSTAIN_LEVEL);
                } else { 
                    if synth_release_frames > 0 {
                        frames_into_release_s := frame_in_note_s - (synth_attack_frames + synth_decay_frames + synth_sustain_duration_frames);
                        progress_release_s := f32(frames_into_release_s) / f32(synth_release_frames);
                        envelope_amp_s = f32(m.lerp(f32(SYNTH_NOTE_SUSTAIN_LEVEL), f32(0.0), f32(progress_release_s)));
                    } else { envelope_amp_s = 0.0; }
                }
                envelope_amp_s = math.clamp(envelope_amp_s, 0.0, 1.0);

                saw_phase_s := current_phase_synth_gen / (2.0 * f64(math.PI));
                sample_val_f64_s := 2.0 * (saw_phase_s - math.floor(0.5 + saw_phase_s));

                synth_track_pcm_data[global_frame_idx_s] += f32(sample_val_f64_s * f64(envelope_amp_s) * f64(SYNTH_TRACK_AMPLITUDE));
                
                current_phase_synth_gen += (2.0 * f64(math.PI) * current_note_freq_s) / f64(SYNTH_TRACK_SAMPLE_RATE);
                if current_phase_synth_gen >= (2.0 * f64(math.PI)) {
                    current_phase_synth_gen -= (2.0 * f64(math.PI));
                }
            }
            current_phase_synth_gen = 0.0;
        }
    }
    for i_clamp in 0..<SYNTH_TRACK_TOTAL_FRAMES_CALC {
        synth_track_pcm_data[i_clamp] = math.clamp(synth_track_pcm_data[i_clamp], -0.95, 0.95);
    }

    synth_track_ab_config := ma.audio_buffer_config_init(ma.format.f32, u32(SYNTH_TRACK_CHANNELS), u64(SYNTH_TRACK_TOTAL_FRAMES_CALC), rawptr(&synth_track_pcm_data[0]), nil);
    ma.audio_buffer_init_copy(&synth_track_ab_config, &synth_track_audio_buffer);
    ma.sound_init_from_data_source(&state.audio_engine, (^ma.data_source)(&synth_track_audio_buffer), { .NO_PITCH, .NO_SPATIALIZATION }, nil, &state.synth_track_sound);
    ma.sound_set_looping(&state.synth_track_sound, true);
    ma.sound_set_volume(&state.synth_track_sound, 1.0);
    ma.sound_start(&state.synth_track_sound)

}

geowars_audio_stream_callback :: proc "c" (buffer: ^f32, num_frames: c.int, num_channels: c.int, user_data: rawptr) {
    engine := (^ma.engine)(user_data)
    ma.engine_read_pcm_frames(engine, buffer, u64(num_frames), nil)
}
