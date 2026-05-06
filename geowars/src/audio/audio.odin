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


// --- Global Variables and Constants ---

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
init_audio :: proc() {
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

    fmt.printf("--- Generating Revised Placeholder Drum Track PCM data (160 BPM)... ---");
    
    KICK_DURATION_FRAMES: int = DRUM_TRACK_FRAMES_PER_BEAT / 3; 
    KICK_START_FREQ :: 120.0; 
    KICK_END_FREQ :: 40.0;
    RELATIVE_KICK_AMPLITUDE  := 0.6; // Made it a normal variable for clarity inside init

    SNARE_DURATION_FRAMES: int = DRUM_TRACK_FRAMES_PER_BEAT / 6;
    SNARE_START_FREQ :: 220.0; 
    RELATIVE_SNARE_AMPLITUDE  := 0.4; // Made it a normal variable

    HIHAT_DURATION_FRAMES: int = DRUM_TRACK_FRAMES_PER_BEAT / 16;
    HIHAT_FREQ :: 6000.0; 
    RELATIVE_HIHAT_AMPLITUDE   := 0.15; // Made it a normal variable

    // Zero out the buffer first
    for i in 0..<DRUM_TRACK_TOTAL_FRAMES { 
        drum_track_pcm_data[i] = 0.0;
    }

    // Generate PCM data bar by bar (Corrected Loop Structure)
    for bar_idx in 0..<DRUM_TRACK_NUM_BARS {
        // --- KICK and SNARE ---
        for beat_num_in_bar in 0..<DRUM_TRACK_BEATS_PER_BAR {
            beat_start_frame_offset := beat_num_in_bar * DRUM_TRACK_FRAMES_PER_BEAT;
            current_beat_global_start_frame := (bar_idx * DRUM_TRACK_FRAMES_PER_BAR) + beat_start_frame_offset;

            // --- KICK DRUM ---
            if beat_num_in_bar == 0 || beat_num_in_bar == 2 {
                current_phase_kick: f64 = 0.0;
                for kick_i in 0..<KICK_DURATION_FRAMES {
                    frame_in_track := current_beat_global_start_frame + kick_i;
                    if frame_in_track >= DRUM_TRACK_TOTAL_FRAMES { break }

                    progress: f64 = f64(kick_i) / f64(KICK_DURATION_FRAMES);
                    amplitude_kick_env: f64 = math.pow_f64(f64(1.0) - progress, 2.5); // Renamed to avoid conflict
                    amplitude_kick_env = math.max(0.0, amplitude_kick_env);
                    current_freq_kick: f64 = f64(KICK_START_FREQ) * math.pow_f64(f64(KICK_END_FREQ) / f64(KICK_START_FREQ), progress);
                    
                    sample_val_kick: f64 = math.sin(current_phase_kick);
                    drum_track_pcm_data[frame_in_track] += f32(sample_val_kick * amplitude_kick_env * f64(RELATIVE_KICK_AMPLITUDE));
                    
                    current_phase_kick += (2.0 * f64(math.PI) * current_freq_kick) / f64(DRUM_TRACK_SAMPLE_RATE);
                    if current_phase_kick >= (2.0 * f64(math.PI)) { current_phase_kick -= (2.0 * f64(math.PI)) }
                }
            }

            // --- SNARE DRUM ---
            if beat_num_in_bar == 1 || beat_num_in_bar == 3 {
                current_phase_snare: f64 = 0.0;
                for snare_i in 0..<SNARE_DURATION_FRAMES {
                    frame_in_track := current_beat_global_start_frame + snare_i;
                    if frame_in_track >= DRUM_TRACK_TOTAL_FRAMES { break }

                    progress: f64 = f64(snare_i) / f64(SNARE_DURATION_FRAMES);
                    amplitude_snare_env: f64 = math.pow_f64(f64(1.0) - progress, 3.5); // Renamed
                    amplitude_snare_env = math.max(0.0, amplitude_snare_env);
                    
                    sample_val_snare: f64 = math.sin(current_phase_snare); // Simple sine for snare, noise would be better
                    drum_track_pcm_data[frame_in_track] += f32(sample_val_snare * amplitude_snare_env * f64(RELATIVE_SNARE_AMPLITUDE));
                    
                    current_phase_snare += (2.0 * f64(math.PI) * f64(SNARE_START_FREQ)) / f64(DRUM_TRACK_SAMPLE_RATE); // Using SNARE_START_FREQ as constant pitch for simplicity
                    if current_phase_snare >= (2.0 * f64(math.PI)) { current_phase_snare -= (2.0 * f64(math.PI)) }
                }
            }
        } // End KICK/SNARE for bar_idx

        // --- HI-HATS (across the entire bar_idx) ---
        for eighth_note_in_bar_idx in 0..<(DRUM_TRACK_BEATS_PER_BAR * 2) {
            eighth_note_offset_from_bar_start := eighth_note_in_bar_idx * (DRUM_TRACK_FRAMES_PER_BEAT / 2);
            hihat_global_start_frame := (bar_idx * DRUM_TRACK_FRAMES_PER_BAR) + eighth_note_offset_from_bar_start;
            
            is_on_kick_pos  := (eighth_note_in_bar_idx == 0 || eighth_note_in_bar_idx == 4); 
            is_on_snare_pos := (eighth_note_in_bar_idx == 2 || eighth_note_in_bar_idx == 6);

            if is_on_kick_pos || is_on_snare_pos { 
                // Skip hi-hat on main kick/snare beats
            } else {
                current_phase_hihat: f64 = 0.0;
                for hihat_i in 0..<HIHAT_DURATION_FRAMES {
                    frame_in_track := hihat_global_start_frame + hihat_i;
                    if frame_in_track >= DRUM_TRACK_TOTAL_FRAMES { break }

                    progress: f64 = f64(hihat_i) / f64(HIHAT_DURATION_FRAMES);
                    amplitude_hihat_env: f64 = math.pow_f64(f64(1.0) - progress, 2.0); // Renamed
                    amplitude_hihat_env = math.max(0.0, amplitude_hihat_env);

                    sample_val_hihat: f64 = math.sin(current_phase_hihat); // Simple sine for hi-hat, noise/filtered noise better
                    drum_track_pcm_data[frame_in_track] += f32(sample_val_hihat * amplitude_hihat_env * f64(RELATIVE_HIHAT_AMPLITUDE));

                    current_phase_hihat += (2.0 * f64(math.PI) * f64(HIHAT_FREQ)) / f64(DRUM_TRACK_SAMPLE_RATE);
                    if current_phase_hihat >= (2.0 * f64(math.PI)) { current_phase_hihat -= (2.0 * f64(math.PI)) }
                }
            }
        } // End HI-HATS for bar_idx
    } // End BAR loop
    
    for i_clamp in 0..<DRUM_TRACK_TOTAL_FRAMES { 
        drum_track_pcm_data[i_clamp] = math.clamp(drum_track_pcm_data[i_clamp], -0.95, 0.95);
    }
    fmt.printf("--- Revised Placeholder Drum Track PCM data generated. ---");

    // Sokol Audio Setup
    sokol_audio_desc := sa.Desc {
        sample_rate = LMB_SOUND_SAMPLE_RATE, 
        num_channels = LMB_SOUND_CHANNELS,   
        buffer_frames = 1024, 
        packet_frames = 0,   
        num_packets = 0,     
        stream_userdata_cb = geowars_audio_stream_callback,
        user_data = nil, 
    }
    sa.setup(sokol_audio_desc)
    if !sa.isvalid() {
        fmt.eprintf("!!! CRITICAL: Sokol Audio setup failed!\n")
    } else {
        fmt.printf("--- Sokol Audio Initialized (Sample Rate: %v, Channels: %v) ---\n", sa.sample_rate(), sa.channels())
    }

    // Miniaudio Engine Setup
    engine_config := ma.engine_config_init()
    engine_config.noDevice = true 
    engine_config.channels = u32(LMB_SOUND_CHANNELS)   
    engine_config.sampleRate = u32(LMB_SOUND_SAMPLE_RATE) 

    init_result := ma.engine_init(&engine_config, &shared.state.audio_engine)
    if init_result != .SUCCESS {
        fmt.eprintf("!!! CRITICAL: Miniaudio engine_init failed! Error: %v\n", init_result)
    } else {
        fmt.printf("--- Miniaudio Engine Initialized ---\n")
    }

    // Generate "Pew" Sound PCM Data
    fmt.printf("--- Generating 'Pew' sound PCM data... ---\n")
    current_phase_lmb: f64 = 0.0 // Renamed to avoid conflict
    
    for i in 0..<LMB_SOUND_FRAMES {
        progress := f64(i) / f64(LMB_SOUND_FRAMES)
        amplitude_lmb: f64 // Renamed
        attack_time_lmb := 0.15 
        if progress < attack_time_lmb {
            amplitude_lmb = progress / attack_time_lmb
        } else {
            amplitude_lmb = 1.0 - (progress - attack_time_lmb) / (1.0 - attack_time_lmb)
        }
        amplitude_lmb = math.max(0.0, amplitude_lmb) 

        ratio_lmb := LMB_SOUND_END_FREQ / LMB_SOUND_START_FREQ // Renamed
        exponent_lmb := progress // Renamed
        current_freq_f64_lmb := f64(LMB_SOUND_START_FREQ) * math.pow(f64(ratio_lmb), exponent_lmb) // Renamed

        sample_val_f64_lmb := math.sin(current_phase_lmb) // Renamed
        
        lmb_sound_pcm_data[i] = f32(sample_val_f64_lmb * amplitude_lmb * f64(LMB_SOUND_AMPLITUDE))

        current_phase_lmb += (2.0 * f64(math.PI) * current_freq_f64_lmb) / f64(LMB_SOUND_SAMPLE_RATE)
        if current_phase_lmb >= (2.0 * f64(math.PI)) {
            current_phase_lmb -= (2.0 * f64(math.PI))
        }
    }
    fmt.printf("--- 'Pew' sound PCM data generated. First sample: %v, Mid sample: %v, Last sample: %v ---\n", lmb_sound_pcm_data[0], lmb_sound_pcm_data[LMB_SOUND_FRAMES/2], lmb_sound_pcm_data[LMB_SOUND_FRAMES-1])

    audio_buffer_config_lmb := ma.audio_buffer_config_init(ma.format.f32, u32(LMB_SOUND_CHANNELS), u64(LMB_SOUND_FRAMES), rawptr(&lmb_sound_pcm_data[0]), nil) // Renamed
    init_ab_result_lmb := ma.audio_buffer_init_copy(&audio_buffer_config_lmb, &lmb_sound_audio_buffer) // Renamed
    if init_ab_result_lmb != .SUCCESS {
        fmt.eprintf("!!! CRITICAL: Miniaudio audio_buffer_init_copy for LMB sound failed! Error: %v\n", init_ab_result_lmb)
    } else {
        fmt.printf("--- Miniaudio audio_buffer initialized for LMB sound ---\n")
        sound_flags_lmb: ma.sound_flags = { .NO_PITCH, .NO_SPATIALIZATION } // Renamed
        p_data_source_for_lmb_sound := (^ma.data_source)(&lmb_sound_audio_buffer) // Renamed

        init_sound_result_lmb := ma.sound_init_from_data_source(&shared.state.audio_engine, p_data_source_for_lmb_sound, sound_flags_lmb, nil, &shared.state.lmb_sound) // Renamed
        if init_sound_result_lmb != .SUCCESS {
            fmt.eprintf("!!! CRITICAL: Miniaudio sound_init_from_data_source for lmb_sound failed! Error: %v\n", init_sound_result_lmb)
            ma.audio_buffer_uninit(&lmb_sound_audio_buffer); 
        } else {
            fmt.printf("--- Miniaudio lmb_sound initialized successfully ---\n")
        }
    }

    fmt.printf("--- Initializing RMB Particle Sounds ---\n")
    hum_waveform_config := ma.waveform_config_init( ma.format.f32, u32(LMB_SOUND_CHANNELS), u32(LMB_SOUND_SAMPLE_RATE), ma.waveform_type.sine, f64(RMB_HUM_AMPLITUDE), f64(RMB_HUM_FREQUENCY))
    hum_sine_wave_gen: ma.waveform
    init_hum_wf_result := ma.waveform_init(&hum_waveform_config, &hum_sine_wave_gen)
    if init_hum_wf_result == .SUCCESS {
        frames_read_hum: u64
        ma.waveform_read_pcm_frames(&hum_sine_wave_gen, rawptr(&rmb_hum_pcm_data[0]), u64(RMB_PARTICLE_SOUND_DURATION_FRAMES), &frames_read_hum)
        ma.waveform_uninit(&hum_sine_wave_gen) 
        fmt.printf("--- RMB Hum PCM data generated (%v frames). ---\n", frames_read_hum)
    } else {
        fmt.eprintf("!!! CRITICAL: Miniaudio waveform_init for RMB Hum failed! Error: %v\n", init_hum_wf_result)
    }

    whoosh_noise_config := ma.noise_config_init(ma.format.f32, u32(LMB_SOUND_CHANNELS), ma.noise_type.pink, 0, f64(RMB_WHOOSH_AMPLITUDE))
    whoosh_noise_gen: ma.noise
    init_whoosh_noise_result := ma.noise_init(&whoosh_noise_config, nil, &whoosh_noise_gen)
    if init_whoosh_noise_result == .SUCCESS {
        frames_read_whoosh: u64
        ma.noise_read_pcm_frames(&whoosh_noise_gen, rawptr(&rmb_whoosh_pcm_data[0]), u64(RMB_PARTICLE_SOUND_DURATION_FRAMES), &frames_read_whoosh)
        ma.noise_uninit(&whoosh_noise_gen, nil) 
        fmt.printf("--- RMB Whoosh PCM data generated (%v frames). ---\n", frames_read_whoosh)
    } else {
        fmt.eprintf("!!! CRITICAL: Miniaudio noise_init for RMB Whoosh failed! Error: %v\n", init_whoosh_noise_result)
    }

    hum_ab_config := ma.audio_buffer_config_init(ma.format.f32, u32(LMB_SOUND_CHANNELS), u64(RMB_PARTICLE_SOUND_DURATION_FRAMES), rawptr(&rmb_hum_pcm_data[0]), nil)
    init_hum_ab_result := ma.audio_buffer_init_copy(&hum_ab_config, &rmb_hum_audio_buffer)
    if init_hum_ab_result == .SUCCESS { fmt.printf("--- RMB Hum audio_buffer initialized. ---\n") } 
    else { fmt.eprintf("!!! CRITICAL: RMB Hum audio_buffer_init_copy failed! Error: %v\n", init_hum_ab_result) }

    whoosh_ab_config := ma.audio_buffer_config_init(ma.format.f32, u32(LMB_SOUND_CHANNELS), u64(RMB_PARTICLE_SOUND_DURATION_FRAMES), rawptr(&rmb_whoosh_pcm_data[0]), nil)
    init_whoosh_ab_result := ma.audio_buffer_init_copy(&whoosh_ab_config, &rmb_whoosh_audio_buffer)
    if init_whoosh_ab_result == .SUCCESS { fmt.printf("--- RMB Whoosh audio_buffer initialized. ---\n") } 
    else { fmt.eprintf("!!! CRITICAL: RMB Whoosh audio_buffer_init_copy failed! Error: %v\n", init_whoosh_ab_result) }
    fmt.printf("--- RMB Particle Sounds Initialized ---\n")

    fmt.printf("--- Generating 'Enemy Hit' sound PCM data... ---\n")
    current_phase_enemy_hit: f64 = 0.0
    for i in 0..<ENEMY_HIT_SOUND_FRAMES {
        progress_eh := f64(i) / f64(ENEMY_HIT_SOUND_FRAMES) // Renamed progress
        amplitude_eh: f64 // Renamed
        attack_time_eh := 0.1 
        if progress_eh < attack_time_eh { amplitude_eh = progress_eh / attack_time_eh } 
        else { amplitude_eh = 1.0 - (progress_eh - attack_time_eh) / (1.0 - attack_time_eh) }
        amplitude_eh = math.max(0.0, amplitude_eh)
        ratio_eh := ENEMY_HIT_SOUND_END_FREQ / ENEMY_HIT_SOUND_START_FREQ // Renamed
        current_freq_f64_eh := f64(ENEMY_HIT_SOUND_START_FREQ) * math.pow(f64(ratio_eh), progress_eh) // Renamed
        sample_val_f64_eh := math.sin(current_phase_enemy_hit) // Renamed
        enemy_hit_sound_pcm_data[i] = f32(sample_val_f64_eh * amplitude_eh * f64(ENEMY_HIT_SOUND_AMPLITUDE))
        current_phase_enemy_hit += (2.0 * f64(math.PI) * current_freq_f64_eh) / f64(LMB_SOUND_SAMPLE_RATE)
        if current_phase_enemy_hit >= (2.0 * f64(math.PI)) { current_phase_enemy_hit -= (2.0 * f64(math.PI)) }
    }
    fmt.printf("--- 'Enemy Hit' sound PCM data generated. ---\n")

    enemy_hit_ab_config := ma.audio_buffer_config_init(ma.format.f32, u32(LMB_SOUND_CHANNELS), u64(ENEMY_HIT_SOUND_FRAMES), rawptr(&enemy_hit_sound_pcm_data[0]), nil)
    init_enemy_hit_ab_result := ma.audio_buffer_init_copy(&enemy_hit_ab_config, &enemy_hit_sound_audio_buffer)
    if init_enemy_hit_ab_result == .SUCCESS {
        fmt.printf("--- Enemy Hit audio_buffer initialized. ---\n")
        sound_flags_rmb_hit: ma.sound_flags = { .NO_PITCH, .NO_SPATIALIZATION };
        p_data_source_rmb_hit := (^ma.data_source)(&enemy_hit_sound_audio_buffer);
        init_rmb_hit_sound_result := ma.sound_init_from_data_source(&shared.state.audio_engine, p_data_source_rmb_hit, sound_flags_rmb_hit, nil, &shared.state.rmb_hit_sound);
        if init_rmb_hit_sound_result == .SUCCESS {
            ma.sound_set_volume(&shared.state.rmb_hit_sound, ENEMY_HIT_SOUND_AMPLITUDE);
            fmt.printf("--- Miniaudio rmb_hit_sound initialized successfully (Volume: %.2f) ---\n", ENEMY_HIT_SOUND_AMPLITUDE);
        } else {
            fmt.eprintf("!!! CRITICAL: Miniaudio sound_init_from_data_source for rmb_hit_sound failed! Error: %v\n", init_rmb_hit_sound_result);
            ma.audio_buffer_uninit(&enemy_hit_sound_audio_buffer); 
        }
    } else {
        fmt.eprintf("!!! CRITICAL: Enemy Hit audio_buffer_init_copy failed! Error: %v\n", init_enemy_hit_ab_result)
    }

    fmt.printf("--- Generating 'Enemy Death' sound PCM data... ---\n")
    current_phase_enemy_death_sine: f64 = 0.0
    rng_seed_ed: u64 = 12345 // Renamed
    death_sound_rng_state := rand.create(rng_seed_ed) 
    death_sound_generator := runtime.default_random_generator(&death_sound_rng_state)
    for i in 0..<ENEMY_DEATH_SOUND_FRAMES {
        if i < ENEMY_DEATH_SOUND_NOISE_DURATION_FRAMES { 
            progress_noise_ed := f32(i) / f32(ENEMY_DEATH_SOUND_NOISE_DURATION_FRAMES) // Renamed
            decay_noise_ed := (1.0 - progress_noise_ed) // Renamed
            decay_noise_ed = math.max(0.0, decay_noise_ed) 
            random_sample_ed := (rand.float32(death_sound_generator) * 2.0 - 1.0) // Renamed
            enemy_death_sound_pcm_data[i] = random_sample_ed * ENEMY_DEATH_SOUND_NOISE_AMPLITUDE * decay_noise_ed
        } else {
            sine_progress_frames_ed := i - ENEMY_DEATH_SOUND_NOISE_DURATION_FRAMES // Renamed
            total_sine_frames_ed := ENEMY_DEATH_SOUND_FRAMES - ENEMY_DEATH_SOUND_NOISE_DURATION_FRAMES // Renamed
            progress_sine_ed := f64(sine_progress_frames_ed) / f64(total_sine_frames_ed) // Renamed
            amplitude_sine_decay_ed := 1.0 - progress_sine_ed // Renamed
            amplitude_sine_decay_ed = math.max(0.0, amplitude_sine_decay_ed) 
            ratio_sine_ed := ENEMY_DEATH_SOUND_SINE_END_FREQ / ENEMY_DEATH_SOUND_SINE_START_FREQ // Renamed
            current_freq_sine_f64_ed := f64(ENEMY_DEATH_SOUND_SINE_START_FREQ) * math.pow(f64(ratio_sine_ed), progress_sine_ed) // Renamed
            sample_val_sine_f64_ed := math.sin(current_phase_enemy_death_sine) // Renamed
            enemy_death_sound_pcm_data[i] = f32(sample_val_sine_f64_ed * amplitude_sine_decay_ed * f64(ENEMY_DEATH_SOUND_SINE_AMPLITUDE))
            current_phase_enemy_death_sine += (2.0 * f64(math.PI) * current_freq_sine_f64_ed) / f64(LMB_SOUND_SAMPLE_RATE)
            if current_phase_enemy_death_sine >= (2.0 * f64(math.PI)) { current_phase_enemy_death_sine -= (2.0 * f64(math.PI)) }
        }
    }
    fmt.printf("--- 'Enemy Death' sound PCM data generated. ---\n")

    enemy_death_ab_config := ma.audio_buffer_config_init(ma.format.f32, u32(LMB_SOUND_CHANNELS), u64(ENEMY_DEATH_SOUND_FRAMES), rawptr(&enemy_death_sound_pcm_data[0]), nil)
    init_enemy_death_ab_result := ma.audio_buffer_init_copy(&enemy_death_ab_config, &enemy_death_sound_audio_buffer)
    if init_enemy_death_ab_result == .SUCCESS {
        fmt.printf("--- Enemy Death audio_buffer initialized. ---\n")
        sound_flags_rmb_kill: ma.sound_flags = { .NO_PITCH, .NO_SPATIALIZATION };
        p_data_source_rmb_kill := (^ma.data_source)(&enemy_death_sound_audio_buffer);
        init_rmb_kill_sound_result := ma.sound_init_from_data_source(&shared.state.audio_engine, p_data_source_rmb_kill, sound_flags_rmb_kill, nil, &shared.state.rmb_kill_sound);
        if init_rmb_kill_sound_result == .SUCCESS {
            ma.sound_set_volume(&shared.state.rmb_kill_sound, ENEMY_DEATH_SOUND_SINE_AMPLITUDE + ENEMY_DEATH_SOUND_NOISE_AMPLITUDE);
            fmt.printf("--- Miniaudio rmb_kill_sound initialized successfully (Volume: %.2f) ---\n", ENEMY_DEATH_SOUND_SINE_AMPLITUDE + ENEMY_DEATH_SOUND_NOISE_AMPLITUDE);
        } else {
            fmt.eprintf("!!! CRITICAL: Miniaudio sound_init_from_data_source for rmb_kill_sound failed! Error: %v\n", init_rmb_kill_sound_result);
            ma.audio_buffer_uninit(&enemy_death_sound_audio_buffer); 
        }
    } else {
        fmt.eprintf("!!! CRITICAL: Enemy Death audio_buffer_init_copy failed! Error: %v\n", init_enemy_death_ab_result)
    }

    fmt.printf("--- Generating 'LMB Hit Whoosh' sound PCM data... ---\n")
    lmb_hit_rng_seed: u64 = 67890 
    lmb_hit_rng_state := rand.create(lmb_hit_rng_seed)
    lmb_hit_generator := runtime.default_random_generator(&lmb_hit_rng_state)
    for i in 0..<LMB_HIT_WHOOSH_DURATION_FRAMES {
        progress_lhw := f32(i) / f32(LMB_HIT_WHOOSH_DURATION_FRAMES) // Renamed
        amplitude_envelope_lhw: f32 // Renamed
        attack_time_whoosh_lhw : f32 = 0.05 // Renamed
        decay_time_whoosh_lhw : f32 = 0.95 // Renamed
        if progress_lhw < attack_time_whoosh_lhw { amplitude_envelope_lhw = progress_lhw / attack_time_whoosh_lhw } 
        else { amplitude_envelope_lhw = 1.0 - (progress_lhw - attack_time_whoosh_lhw) / decay_time_whoosh_lhw }
        amplitude_envelope_lhw = math.max(0.0, amplitude_envelope_lhw) 
        random_sample_lhw := (rand.float32(lmb_hit_generator) * 2.0 - 1.0) // Renamed
        lmb_hit_whoosh_pcm_data[i] = random_sample_lhw * LMB_HIT_WHOOSH_AMPLITUDE * amplitude_envelope_lhw
    }
    fmt.printf("--- 'LMB Hit Whoosh' sound PCM data generated. ---\n")

    lmb_hit_whoosh_ab_config := ma.audio_buffer_config_init(ma.format.f32, u32(LMB_SOUND_CHANNELS), u64(LMB_HIT_WHOOSH_DURATION_FRAMES), rawptr(&lmb_hit_whoosh_pcm_data[0]), nil)
    init_lmb_hit_whoosh_ab_result := ma.audio_buffer_init_copy(&lmb_hit_whoosh_ab_config, &lmb_hit_whoosh_audio_buffer)
    if init_lmb_hit_whoosh_ab_result == .SUCCESS {
        fmt.printf("--- LMB Hit Whoosh audio_buffer initialized. ---\n")
        sound_flags_lmb_hit: ma.sound_flags = { .NO_PITCH, .NO_SPATIALIZATION };
        p_data_source_lmb_hit := (^ma.data_source)(&lmb_hit_whoosh_audio_buffer);
        init_lmb_hit_sound_result := ma.sound_init_from_data_source(&shared.state.audio_engine, p_data_source_lmb_hit, sound_flags_lmb_hit, nil, &shared.state.lmb_hit_sound);
        if init_lmb_hit_sound_result == .SUCCESS {
            ma.sound_set_volume(&shared.state.lmb_hit_sound, LMB_HIT_WHOOSH_AMPLITUDE);
            fmt.printf("--- Miniaudio lmb_hit_sound initialized successfully (Volume: %.2f) ---\n", LMB_HIT_WHOOSH_AMPLITUDE);
        } else {
            fmt.eprintf("!!! CRITICAL: Miniaudio sound_init_from_data_source for lmb_hit_sound failed! Error: %v\n", init_lmb_hit_sound_result);
            ma.audio_buffer_uninit(&lmb_hit_whoosh_audio_buffer); 
        }
    } else {
        fmt.eprintf("!!! CRITICAL: LMB Hit Whoosh audio_buffer_init_copy failed! Error: %v\n", init_lmb_hit_whoosh_ab_result)
    }

    fmt.printf("--- Generating 'LMB Kill Explosion' sound PCM data... ---\n")
    lmb_kill_rng_seed: u64 = 78901 
    lmb_kill_rng_state := rand.create(lmb_kill_rng_seed)
    lmb_kill_generator := runtime.default_random_generator(&lmb_kill_rng_state)
    EXPLOSION_NOISE_FRAMES :: LMB_KILL_EXPLOSION_DURATION_FRAMES / 5 
    EXPLOSION_SINE_START_FREQ_lke :: 150.0 // Renamed
    EXPLOSION_SINE_END_FREQ_lke :: 40.0   // Renamed
    current_phase_lmb_kill_sine: f64 = 0.0
    for i in 0..<LMB_KILL_EXPLOSION_DURATION_FRAMES {
        if i < EXPLOSION_NOISE_FRAMES {
            progress_noise_lke := f32(i) / f32(EXPLOSION_NOISE_FRAMES) // Renamed
            decay_noise_lke := (1.0 - progress_noise_lke) * (1.0 - progress_noise_lke) // Renamed
            decay_noise_lke = math.max(0.0, decay_noise_lke)
            random_sample_lke := (rand.float32(lmb_kill_generator) * 2.0 - 1.0) // Renamed
            lmb_kill_explosion_pcm_data[i] = random_sample_lke * LMB_KILL_EXPLOSION_AMPLITUDE * decay_noise_lke * 0.7 
        } else {
            sine_progress_frames_lke := i - EXPLOSION_NOISE_FRAMES // Renamed
            total_sine_frames_lke := LMB_KILL_EXPLOSION_DURATION_FRAMES - EXPLOSION_NOISE_FRAMES // Renamed
            progress_sine_lke := f64(sine_progress_frames_lke) / f64(total_sine_frames_lke) // Renamed
            amplitude_sine_decay_lke := math.pow(1.0 - progress_sine_lke, 3.0) // Renamed
            amplitude_sine_decay_lke = math.max(0.0, amplitude_sine_decay_lke)
            ratio_sine_lke := EXPLOSION_SINE_END_FREQ_lke / EXPLOSION_SINE_START_FREQ_lke // Renamed
            current_freq_sine_f64_lke := EXPLOSION_SINE_START_FREQ_lke * math.pow(ratio_sine_lke, progress_sine_lke) // Renamed
            sample_val_sine_f64_lke := math.sin(current_phase_lmb_kill_sine) // Renamed
            lmb_kill_explosion_pcm_data[i] = f32(sample_val_sine_f64_lke * amplitude_sine_decay_lke * f64(LMB_KILL_EXPLOSION_AMPLITUDE))
            current_phase_lmb_kill_sine += (2.0 * f64(math.PI) * current_freq_sine_f64_lke) / f64(LMB_SOUND_SAMPLE_RATE)
            if current_phase_lmb_kill_sine >= (2.0 * f64(math.PI)) { current_phase_lmb_kill_sine -= (2.0 * f64(math.PI)) }
        }
    }
    fmt.printf("--- 'LMB Kill Explosion' sound PCM data generated. ---\n")

    lmb_kill_explosion_ab_config := ma.audio_buffer_config_init(ma.format.f32, u32(LMB_SOUND_CHANNELS), u64(LMB_KILL_EXPLOSION_DURATION_FRAMES), rawptr(&lmb_kill_explosion_pcm_data[0]), nil)
    init_lmb_kill_explosion_ab_result := ma.audio_buffer_init_copy(&lmb_kill_explosion_ab_config, &lmb_kill_explosion_audio_buffer)
    if init_lmb_kill_explosion_ab_result == .SUCCESS {
        fmt.printf("--- LMB Kill Explosion audio_buffer initialized. ---\n")
        sound_flags_lmb_kill: ma.sound_flags = { .NO_PITCH, .NO_SPATIALIZATION };
        p_data_source_lmb_kill := (^ma.data_source)(&lmb_kill_explosion_audio_buffer);
        init_lmb_kill_sound_result := ma.sound_init_from_data_source(&shared.state.audio_engine, p_data_source_lmb_kill, sound_flags_lmb_kill, nil, &shared.state.lmb_kill_sound);
        if init_lmb_kill_sound_result == .SUCCESS {
            ma.sound_set_volume(&shared.state.lmb_kill_sound, LMB_KILL_EXPLOSION_AMPLITUDE);
            fmt.printf("--- Miniaudio lmb_kill_sound initialized successfully (Volume: %.2f) ---\n", LMB_KILL_EXPLOSION_AMPLITUDE);
        } else {
            fmt.eprintf("!!! CRITICAL: Miniaudio sound_init_from_data_source for lmb_kill_sound failed! Error: %v\n", init_lmb_kill_sound_result);
            ma.audio_buffer_uninit(&lmb_kill_explosion_audio_buffer); 
        }
    } else {
        fmt.eprintf("!!! CRITICAL: LMB Kill Explosion audio_buffer_init_copy failed! Error: %v\n", init_lmb_kill_explosion_ab_result)
    }

    // Initialize Miniaudio audio_buffer for the drum track (This was the corrected drum generation block)
    drum_track_ab_config := ma.audio_buffer_config_init(ma.format.f32, u32(DRUM_TRACK_CHANNELS), u64(DRUM_TRACK_TOTAL_FRAMES), rawptr(&drum_track_pcm_data[0]), nil)
    init_drum_track_ab_result := ma.audio_buffer_init_copy(&drum_track_ab_config, &drum_track_audio_buffer)
    if init_drum_track_ab_result == .SUCCESS {
        fmt.printf("--- Drum Track audio_buffer initialized. ---\n")
        drum_track_sound_flags: ma.sound_flags = { .NO_PITCH, .NO_SPATIALIZATION }; 
        p_drum_track_data_source := (^ma.data_source)(&drum_track_audio_buffer);
        init_drum_sound_result := ma.sound_init_from_data_source(&shared.state.audio_engine, p_drum_track_data_source, drum_track_sound_flags, nil, &shared.state.drum_track_sound);
        if init_drum_sound_result == .SUCCESS {
            ma.sound_set_looping(&shared.state.drum_track_sound, true); 
            ma.sound_set_volume(&shared.state.drum_track_sound, DRUM_TRACK_AMPLITUDE); 
            fmt.printf("--- Miniaudio drum_track_sound initialized successfully (Looping, Volume: %.2f) ---\n", DRUM_TRACK_AMPLITUDE);
        } else {
            fmt.eprintf("!!! CRITICAL: Miniaudio sound_init_from_data_source for drum_track_sound failed! Error: %v\n", init_drum_sound_result);
            ma.audio_buffer_uninit(&drum_track_audio_buffer); 
        }
    } else {
        fmt.eprintf("!!! CRITICAL: Drum Track audio_buffer_init_copy failed! Error: %v\n", init_drum_track_ab_result)
    }

    // (<<< NEW SYNTH TRACK INITIALIZATION START >>>)
    fmt.printf("--- Generating Heavy Fast Synth Track PCM data (160 BPM)... ---\n");

    SYNTH_TRACK_SECONDS_PER_BEAT_CALC : f32 = 60.0 / SYNTH_TRACK_BPM; // Renamed to avoid conflict if used elsewhere
    SYNTH_TRACK_FRAMES_PER_BEAT_F32_CALC : f32 = SYNTH_TRACK_SECONDS_PER_BEAT_CALC * f32(SYNTH_TRACK_SAMPLE_RATE);
    SYNTH_TRACK_FRAMES_PER_BEAT_CALC := int(math.round_f32(SYNTH_TRACK_FRAMES_PER_BEAT_F32_CALC));
    SYNTH_TRACK_FRAMES_PER_BAR_CALC := SYNTH_TRACK_FRAMES_PER_BEAT_CALC * SYNTH_TRACK_BEATS_PER_BAR;
    SYNTH_TRACK_TOTAL_FRAMES_CALC := SYNTH_TRACK_FRAMES_PER_BAR_CALC * SYNTH_TRACK_NUM_BARS;

    synth_track_pcm_data = make([]f32, SYNTH_TRACK_TOTAL_FRAMES_CALC);
    if synth_track_pcm_data == nil {
        fmt.eprintf("!!! CRITICAL: Failed to allocate synth_track_pcm_data! Total Frames: %d\n", SYNTH_TRACK_TOTAL_FRAMES_CALC);
        return; // Cannot proceed
    } else {
        fmt.printf("--- Synth track PCM data slice allocated. Total Frames: %d ---\n", SYNTH_TRACK_TOTAL_FRAMES_CALC);
    }
    for i in 0..<SYNTH_TRACK_TOTAL_FRAMES_CALC { synth_track_pcm_data[i] = 0.0; }

    synth_attack_frames  := int(SYNTH_NOTE_ATTACK_TIME_S * f32(SYNTH_TRACK_SAMPLE_RATE));
    synth_decay_frames   := int(SYNTH_NOTE_DECAY_TIME_S * f32(SYNTH_TRACK_SAMPLE_RATE));
    synth_release_frames := int(SYNTH_NOTE_RELEASE_TIME_S * f32(SYNTH_TRACK_SAMPLE_RATE));

    NOTE_DURATION_FRAMES_8TH_SYNTH := SYNTH_TRACK_FRAMES_PER_BEAT_CALC / 2; // Renamed

    min_adsr_frames_synth := synth_attack_frames + synth_decay_frames + synth_release_frames; // Renamed
    if NOTE_DURATION_FRAMES_8TH_SYNTH < min_adsr_frames_synth {
        fmt.eprintf("!!! WARNING: Synth note duration (%d frames) is shorter than ADSR phases combined (%d frames). Adjust ADSR times.\n", NOTE_DURATION_FRAMES_8TH_SYNTH, min_adsr_frames_synth);
    }
    synth_sustain_duration_frames := NOTE_DURATION_FRAMES_8TH_SYNTH - synth_attack_frames - synth_decay_frames - synth_release_frames;
    if synth_sustain_duration_frames < 0 { synth_sustain_duration_frames = 0; } 

    note_frequencies_synth := [SYNTH_TRACK_NUM_BARS][SYNTH_TRACK_BEATS_PER_BAR * 2]f32 {}; // Renamed
    for i in 0..<(SYNTH_TRACK_BEATS_PER_BAR * 2) { note_frequencies_synth[0][i] = 110.0; } // A2
    for i in 0..<(SYNTH_TRACK_BEATS_PER_BAR * 2) { note_frequencies_synth[1][i] = 130.81; } // C3

    current_phase_synth_gen: f64 = 0.0; // Renamed

    for bar_s_idx in 0..<SYNTH_TRACK_NUM_BARS { // Renamed
        for eighth_note_s_idx in 0..<(SYNTH_TRACK_BEATS_PER_BAR * 2) { // Renamed
            note_start_frame_in_track_s := (bar_s_idx * SYNTH_TRACK_FRAMES_PER_BAR_CALC) + (eighth_note_s_idx * NOTE_DURATION_FRAMES_8TH_SYNTH); // Renamed
            current_note_freq_s := f64(note_frequencies_synth[bar_s_idx][eighth_note_s_idx]); // Renamed

            for frame_in_note_s in 0..<NOTE_DURATION_FRAMES_8TH_SYNTH { // Renamed
                global_frame_idx_s := note_start_frame_in_track_s + frame_in_note_s; // Renamed
                if global_frame_idx_s >= SYNTH_TRACK_TOTAL_FRAMES_CALC { break; }

                envelope_amp_s: f32 = 0.0; // Renamed
                if frame_in_note_s < synth_attack_frames {
                    envelope_amp_s = f32(frame_in_note_s) / f32(math.max(1,synth_attack_frames)); // max(1,..) to avoid div by zero if attack_frames is 0
                } else if frame_in_note_s < synth_attack_frames + synth_decay_frames {
                    progress_decay_s := f32(frame_in_note_s - synth_attack_frames) / f32(math.max(1,synth_decay_frames));
                    // Cast untyped float consts to f64 for m.lerp, and progress_decay_s to f64. Cast result to f32.
                    envelope_amp_s = f32(m.lerp(f32(1.0), f32(SYNTH_NOTE_SUSTAIN_LEVEL), f32(progress_decay_s)));
                } else if frame_in_note_s < synth_attack_frames + synth_decay_frames + synth_sustain_duration_frames {
                    envelope_amp_s = SYNTH_NOTE_SUSTAIN_LEVEL; // This is f32, ensure SYNTH_NOTE_SUSTAIN_LEVEL is assignable or cast
                                                              // SYNTH_NOTE_SUSTAIN_LEVEL :: 0.6 (untyped float, can assign to f32) - this line is OK
                } else { 
                    if synth_release_frames > 0 {
                        frames_into_release_s := frame_in_note_s - (synth_attack_frames + synth_decay_frames + synth_sustain_duration_frames);
                        progress_release_s := f32(frames_into_release_s) / f32(synth_release_frames);
                        // Cast untyped float consts to f64 for m.lerp, and progress_release_s to f64. Cast result to f32.
                        envelope_amp_s = f32(m.lerp(f32(SYNTH_NOTE_SUSTAIN_LEVEL), f32(0.0), f32(progress_release_s)));
                    } else { envelope_amp_s = 0.0; }
                }
                envelope_amp_s = math.clamp(envelope_amp_s, 0.0, 1.0);

                saw_phase_s := current_phase_synth_gen / (2.0 * f64(math.PI)); // Renamed
                sample_val_f64_s := 2.0 * (saw_phase_s - math.floor(0.5 + saw_phase_s)); // Renamed

                synth_track_pcm_data[global_frame_idx_s] += f32(sample_val_f64_s * f64(envelope_amp_s) * f64(SYNTH_TRACK_AMPLITUDE));
                
                current_phase_synth_gen += (2.0 * f64(math.PI) * current_note_freq_s) / f64(SYNTH_TRACK_SAMPLE_RATE);
                if current_phase_synth_gen >= (2.0 * f64(math.PI)) {
                    current_phase_synth_gen -= (2.0 * f64(math.PI));
                }
            }
            current_phase_synth_gen = 0.0; // Reset phase for next note
        }
    }
    for i_clamp in 0..<SYNTH_TRACK_TOTAL_FRAMES_CALC {
        synth_track_pcm_data[i_clamp] = math.clamp(synth_track_pcm_data[i_clamp], -0.95, 0.95);
    }
    fmt.printf("--- Heavy Fast Synth Track PCM data generated. ---\n");

    synth_track_ab_config := ma.audio_buffer_config_init(ma.format.f32, u32(SYNTH_TRACK_CHANNELS), u64(SYNTH_TRACK_TOTAL_FRAMES_CALC), rawptr(&synth_track_pcm_data[0]), nil);
    init_synth_track_ab_result := ma.audio_buffer_init_copy(&synth_track_ab_config, &synth_track_audio_buffer);
    if init_synth_track_ab_result == .SUCCESS {
        fmt.printf("--- Synth Track audio_buffer initialized. ---\n");
        synth_track_sound_flags: ma.sound_flags = { .NO_PITCH, .NO_SPATIALIZATION };
        p_synth_track_data_source := (^ma.data_source)(&synth_track_audio_buffer);
        init_synth_sound_result := ma.sound_init_from_data_source(&shared.state.audio_engine, p_synth_track_data_source, synth_track_sound_flags, nil, &shared.state.synth_track_sound);
        if init_synth_sound_result == .SUCCESS {
            ma.sound_set_looping(&shared.state.synth_track_sound, true);
            ma.sound_set_volume(&shared.state.synth_track_sound, 1.0); // PCM data already has SYNTH_TRACK_AMPLITUDE baked in, so master volume is 1.0 unless further adjustment needed
            fmt.printf("--- Miniaudio synth_track_sound initialized successfully (Looping, Volume: %.2f) ---\n", 1.0);
        } else {
            fmt.eprintf("!!! CRITICAL: Miniaudio sound_init_from_data_source for synth_track_sound failed! Error: %v\n", init_synth_sound_result);
            ma.audio_buffer_uninit(&synth_track_audio_buffer);
        }
    } else {
        fmt.eprintf("!!! CRITICAL: Synth Track audio_buffer_init_copy failed! Error: %v\n", init_synth_track_ab_result);
    }
}

geowars_audio_stream_callback :: proc "c" (buffer: ^f32, num_frames: c.int, num_channels: c.int, user_data: rawptr) {
    ma.engine_read_pcm_frames(&shared.state.audio_engine, buffer, u64(num_frames), nil)
}

cleanup_audio :: proc() {
    ma.sound_uninit(&shared.state.lmb_sound); fmt.printf("--- Miniaudio lmb_sound uninitialized ---\n")
    ma.audio_buffer_uninit(&lmb_sound_audio_buffer); fmt.printf("--- Miniaudio lmb_sound_audio_buffer uninitialized ---\n")

    ma.audio_buffer_uninit(&rmb_hum_audio_buffer); fmt.printf("--- RMB Hum global audio_buffer uninitialized ---\n")
    ma.audio_buffer_uninit(&rmb_whoosh_audio_buffer); fmt.printf("--- RMB Whoosh global audio_buffer uninitialized ---\n")

    ma.audio_buffer_uninit(&enemy_hit_sound_audio_buffer); fmt.printf("--- Enemy Hit audio_buffer uninitialized ---\n")
    ma.audio_buffer_uninit(&enemy_death_sound_audio_buffer); fmt.printf("--- Enemy Death audio_buffer uninitialized ---\n")

    ma.audio_buffer_uninit(&lmb_hit_whoosh_audio_buffer); fmt.printf("--- LMB Hit Whoosh audio_buffer uninitialized ---\n")
    ma.audio_buffer_uninit(&lmb_kill_explosion_audio_buffer); fmt.printf("--- LMB Kill Explosion audio_buffer uninitialized ---\n")

    delete(drum_track_pcm_data); fmt.printf("--- Drum track PCM data slice deleted ---\n")
    ma.audio_buffer_uninit(&drum_track_audio_buffer); fmt.printf("--- Drum Track audio_buffer uninitialized ---\n")

    delete(synth_track_pcm_data); fmt.printf("--- Synth track PCM data slice deleted ---\n")
    ma.audio_buffer_uninit(&synth_track_audio_buffer); fmt.printf("--- Synth Track audio_buffer uninitialized ---\n")

    ma.sound_uninit(&shared.state.lmb_hit_sound); fmt.printf("--- Miniaudio lmb_hit_sound uninitialized ---\n")
    ma.sound_uninit(&shared.state.lmb_kill_sound); fmt.printf("--- Miniaudio lmb_kill_sound uninitialized ---\n")
    ma.sound_uninit(&shared.state.rmb_hit_sound); fmt.printf("--- Miniaudio rmb_hit_sound uninitialized ---\n")
    ma.sound_uninit(&shared.state.rmb_kill_sound); fmt.printf("--- Miniaudio rmb_kill_sound uninitialized ---\n")
    ma.sound_uninit(&shared.state.drum_track_sound); fmt.printf("--- Miniaudio drum_track_sound uninitialized ---\n")
    ma.sound_uninit(&shared.state.synth_track_sound); fmt.printf("--- Miniaudio synth_track_sound uninitialized ---\n")

    ma.engine_uninit(&shared.state.audio_engine); fmt.printf("--- Miniaudio engine uninitialized ---\n")
}
