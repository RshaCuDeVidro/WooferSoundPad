#ifndef WOOF_AUDIO_H
#define WOOF_AUDIO_H

// Thin wrapper around miniaudio. miniaudio.h is huge and Zig's translate-c
// chokes on parts of it, so Zig only ever sees this small API.
//
// Every sound plays on up to two outputs at the same time: the monitor
// (your headphones) and the virtual microphone (null sink / VB-Cable).
// All functions must be called from the same thread (the UI thread).

#define WOOF_MAX_SOUNDS 1024
#define WOOF_MAX_VOICES 4
#define WOOF_MAX_DEVICES 64

#define WOOF_OUT_MONITOR 0
#define WOOF_OUT_MIC 1
#define WOOF_OUT_COUNT 2

#define WOOF_MODE_RESTART 0 // pressing again restarts the sound
#define WOOF_MODE_OVERLAP 1 // pressing again layers another voice on top
#define WOOF_MODE_TOGGLE 2  // pressing again stops the sound

int woof_init(void);
void woof_deinit(void);

// Re-enumerates playback devices. Returns the number of devices.
int woof_refresh_devices(void);
int woof_device_count(void);
const char *woof_device_name(int index);
int woof_device_is_default(int index);

// device_index -1: the monitor uses the system default, the mic gets disabled.
int woof_set_output(int slot, int device_index);
int woof_output_active(int slot);
void woof_set_output_volume(int slot, float volume);

// Paths are UTF-8. Returns a sound id or -1. Decoding happens in the background.
int woof_load(const char *path);
void woof_unload(int id);
int woof_is_ready(int id);
float woof_length(int id); // seconds, 0 while still decoding
void woof_play(int id, float volume, int mode);
void woof_stop(int id);
void woof_stop_all(void);
int woof_is_playing(int id);
float woof_cursor(int id); // seconds into the most recent voice, relative to the trim start
int woof_playing_count(void);

// Per-sound playback settings, applied without touching the file.
// trim_end <= 0 means "until the end". speed 1 = normal (also shifts pitch).
void woof_set_params(int id, float trim_start, float trim_end, int loop, float speed, float fade_in, float fade_out);
float woof_full_length(int id); // seconds, ignoring the trim

// Pausing keeps each voice's position; play/stop forget it.
void woof_pause(int id);
void woof_resume(int id);
int woof_is_paused(int id);
void woof_pause_all(void);
void woof_resume_all(void);
int woof_paused_count(void);

// Call once per frame: runs fade-outs near the end of each sound.
void woof_update(void);

// Decodes a file and writes `bins` loudness values (RMS, 0..1). Thread-safe: it does
// not touch the engine. Returns the number of bins written, 0 on failure.
int woof_waveform(const char *path, float *peaks, int bins, float *duration);

// Preview player: streams a file on the monitor only (used by the browsers).
int woof_preview_play(const char *path, float volume);
void woof_preview_stop(void);
int woof_preview_is_playing(void);
float woof_preview_cursor(void);
float woof_preview_length(void);

// ── Live effects ────────────────────────────────────────────────────────────
// Each sound has a chain of up to WOOF_FX_MAX effects, applied in order while
// it plays. Every type appears at most once per chain. Parameters are in real
// units; see woof_dsp.h for what p[0..3] mean for each type.

#define WOOF_FX_MAX 8
#define WOOF_FX_PITCH 0      // p0 semitones
#define WOOF_FX_LOWPASS 1    // p0 cutoff Hz, p1 resonance (Q)
#define WOOF_FX_HIGHPASS 2   // p0 cutoff Hz, p1 resonance (Q)
#define WOOF_FX_BANDPASS 3   // p0 center Hz, p1 Q ("radio / phone")
#define WOOF_FX_DISTORTION 4 // p0 drive 0..1, p1 mix
#define WOOF_FX_BITCRUSH 5   // p0 bits, p1 sample hold, p2 mix
#define WOOF_FX_ECHO 6       // p0 delay s, p1 feedback, p2 mix
#define WOOF_FX_REVERB 7     // p0 room 0..1, p1 damping, p2 mix
#define WOOF_FX_CHORUS 8     // p0 rate Hz, p1 depth, p2 mix
#define WOOF_FX_TREMOLO 9    // p0 rate Hz, p1 depth
#define WOOF_FX_ROBOT 10     // p0 ring frequency Hz, p1 mix
#define WOOF_FX_GAIN 11      // p0 dB
#define WOOF_FX_TYPES 12

typedef struct {
    int type;
    float p[4];
    // Automation: parameter `auto_param` (0..3, -1 = none) glides from p[auto_param]
    // to `auto_to` over the length of the sound (and starts over when it loops)
    int auto_param;
    float auto_to;
} WoofFx;

// Applies live, also to voices that are playing right now
void woof_set_fx(int id, const WoofFx *chain, int count);

// ── Mixer ───────────────────────────────────────────────────────────────────
// Live controls for what is playing. They reset on the next play.

void woof_set_live_volume(int id, float volume); // multiplies the pad volume
float woof_live_volume(int id);
void woof_set_muted(int id, int muted);
int woof_is_muted(int id);
void woof_fade_stop(int id, float seconds);
int woof_is_fading(int id);
float woof_level(int id); // output peak since the previous call (after effects)
void woof_seek(int id, float seconds); // relative to the trim start
void woof_play_from(int id, float volume, float seconds);

// ── Recorder ────────────────────────────────────────────────────────────────
// Records the computer's output (what you hear) or a microphone into memory,
// then writes a 16-bit WAV.

#define WOOF_REC_SYSTEM -1      // what the computer plays (loopback / monitor)
#define WOOF_REC_DEFAULT_MIC -2 // default input device
#define WOOF_REC_RATE 48000
#define WOOF_REC_MAX_SECONDS 600
#define WOOF_REC_PEAKS_PER_SECOND 50

int woof_capture_count(void);
const char *woof_capture_name(int index);
int woof_capture_is_default(int index);
int woof_rec_system_supported(void);
int woof_rec_start(int source); // 0 on success
void woof_rec_stop(void);
int woof_rec_active(void);
float woof_rec_seconds(void);
float woof_rec_level(void); // peak since the previous call
int woof_rec_peak_count(void);
const float *woof_rec_peaks(void); // WOOF_REC_PEAKS_PER_SECOND values per second, 0..1
int woof_rec_save(const char *path, float start, float end); // seconds, end <= 0 = until the end
void woof_rec_discard(void);

// Loudness of a file in dB (gated mean square of 100 ms blocks, like
// broadcast meters minus the K-weighting) and its sample peak in dBFS.
// Thread-safe (does not touch the engine). Returns 0 on success.
int woof_loudness(const char *path, float *loudness_db, float *peak_db);

// Seconds east of UTC right now (for "today" in statistics)
int woof_utc_offset(void);

#endif
