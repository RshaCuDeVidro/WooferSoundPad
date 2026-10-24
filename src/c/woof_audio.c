#include "woof_audio.h"
#include "woof_dsp.h"

#include <stdio.h>
#include <time.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>

// OGG through stb_vorbis (shipped with raylib); WAV/MP3/FLAC are built into miniaudio
#define STB_VORBIS_HEADER_ONLY
#include "external/stb_vorbis.c"

#define MA_NO_GENERATION
#define MA_NO_ENCODING
#define MINIAUDIO_IMPLEMENTATION
#include "external/miniaudio.h"

#undef STB_VORBIS_HEADER_ONLY
#include "external/stb_vorbis.c"

#ifdef _WIN32
// fopen() on Windows does not understand UTF-8, so paths go through the wide API
static wchar_t *utf8_to_wide(const char *path) {
    int len = MultiByteToWideChar(CP_UTF8, 0, path, -1, NULL, 0);
    if (len <= 0) return NULL;
    wchar_t *wide = (wchar_t *)malloc(sizeof(wchar_t) * (size_t)len);
    if (wide == NULL) return NULL;
    MultiByteToWideChar(CP_UTF8, 0, path, -1, wide, len);
    return wide;
}
#endif

static ma_result sound_init_from_path(ma_engine *engine, const char *path, ma_uint32 flags, ma_sound *sound) {
#ifdef _WIN32
    wchar_t *wide = utf8_to_wide(path);
    if (wide == NULL) return MA_INVALID_ARGS;
    ma_result result = ma_sound_init_from_file_w(engine, wide, flags, NULL, NULL, sound);
    free(wide);
    return result;
#else
    return ma_sound_init_from_file(engine, path, flags, NULL, NULL, sound);
#endif
}

typedef struct {
    char name[256];
    ma_device_id id;
    ma_bool32 is_default;
} WoofDevice;

// One per playing voice, between the sound and the output: runs the effect
// chain and measures the level for the mixer. Created on a voice's first play.
typedef struct {
    ma_node_base base; // must stay first
    WoofDsp dsp;
    WoofFx chains[2][WOOF_FX_MAX]; // the audio thread reads chains[front]
    int counts[2];
    ma_uint32 front;
    ma_uint32 reset;
    // Playback position for automation, in output frames
    ma_uint64 pos;
    volatile ma_uint64 reset_pos; // where `pos` restarts on reset (a seek)
    volatile ma_uint64 len_frames; // length of one play, 0 = unknown
    volatile ma_bool32 looping;
    volatile float peak;
    volatile ma_uint32 silent_frames;
    ma_bool32 running;
} WoofFxNode;

typedef struct {
    ma_sound *voices[WOOF_MAX_VOICES]; // voice 0 is loaded from file, the rest are lazy copies
    WoofFxNode *fx[WOOF_MAX_VOICES];
    ma_bool8 paused[WOOF_MAX_VOICES];
    ma_bool8 fading[WOOF_MAX_VOICES]; // fade-out already started
    ma_bool8 fade_stop[WOOF_MAX_VOICES]; // the mixer asked for a fade-out
} WoofVoices;

typedef struct {
    char name[256];
    ma_device_id id;
    ma_bool32 is_default;
} WoofCapture;

typedef struct {
    ma_engine engine;
    ma_bool32 active;
    float volume;
    WoofVoices sounds[WOOF_MAX_SOUNDS];
} WoofOutput;

typedef struct {
    char *path;
    int last_voice;
    float trim_start;
    float trim_end;
    ma_bool32 loop;
    float speed;
    float fade_in;
    float fade_out;
    WoofFx fx[WOOF_FX_MAX];
    int fx_count;
    float volume; // pad volume of the current play
    float live_volume; // mixer multiplier
    ma_bool32 muted;
} WoofSound;

static ma_context g_context;
static ma_resource_manager g_resources; // shared, so each file is decoded once for both outputs
static ma_bool32 g_ready;
static WoofDevice g_devices[WOOF_MAX_DEVICES];
static int g_device_count;
static WoofOutput g_outputs[WOOF_OUT_COUNT];
static WoofSound g_sounds[WOOF_MAX_SOUNDS];
static ma_sound g_preview;
static ma_bool32 g_preview_loaded;
static WoofCapture g_captures[WOOF_MAX_DEVICES];
static int g_capture_count;

static const ma_uint32 k_sound_flags = MA_SOUND_FLAG_DECODE | MA_SOUND_FLAG_ASYNC | MA_SOUND_FLAG_NO_SPATIALIZATION;

// Every sound is decoded to this rate by the resource manager, so trim points
// convert to frames without asking the (possibly still loading) decoder.
#define WOOF_RATE 48000

static ma_bool32 valid_id(int id) {
    return id >= 0 && id < WOOF_MAX_SOUNDS && g_sounds[id].path != NULL;
}

// Length of the decoded file, ignoring any range set on this voice
static ma_uint64 full_length_frames(ma_sound *voice) {
    ma_resource_manager_data_source *ds = (ma_resource_manager_data_source *)ma_sound_get_data_source(voice);
    ma_uint64 length = 0;
    if (ds == NULL || ma_resource_manager_data_buffer_get_length_in_pcm_frames(&ds->backend.buffer, &length) != MA_SUCCESS) return 0;
    return length;
}

static float sound_speed(int id) {
    return g_sounds[id].speed > 0.01f ? g_sounds[id].speed : 1.0f;
}

// Trim (as a data source range), looping and speed for one voice
static void apply_params(int id, ma_sound *voice) {
    const WoofSound *s = &g_sounds[id];
    ma_uint64 full = full_length_frames(voice);
    ma_uint64 beg = (ma_uint64)(s->trim_start > 0 ? s->trim_start * WOOF_RATE : 0);
    ma_uint64 end = s->trim_end > 0 ? (ma_uint64)(s->trim_end * WOOF_RATE) : ~(ma_uint64)0;
    if (full > 0 && end != ~(ma_uint64)0 && end >= full) end = ~(ma_uint64)0;
    if (full > 0 && beg >= full) beg = 0;
    if (end != ~(ma_uint64)0 && end <= beg) end = ~(ma_uint64)0;
    ma_data_source_set_range_in_pcm_frames(ma_sound_get_data_source(voice), beg, end);
    ma_sound_set_looping(voice, s->loop);
    ma_sound_set_pitch(voice, sound_speed(id));
}

// ── Effect nodes ────────────────────────────────────────────────────────────

static void fx_node_process(ma_node *node, const float **frames_in, ma_uint32 *count_in, float **frames_out, ma_uint32 *count_out) {
    WoofFxNode *n = (WoofFxNode *)node;
    ma_uint32 frames = *count_out;
    if (*count_in < frames) frames = *count_in;
    const ma_uint32 ch = n->dsp.channels;
    float *out = frames_out[0];
    if (frames_in != NULL && frames_in[0] != NULL) {
        memcpy(out, frames_in[0], (size_t)frames * ch * sizeof(float));
    } else {
        memset(out, 0, (size_t)frames * ch * sizeof(float));
    }
    if (ma_atomic_exchange_32(&n->reset, 0)) {
        dsp_reset(&n->dsp);
        n->pos = n->reset_pos;
    }

    ma_uint32 f = ma_atomic_load_32(&n->front) & 1;
    int count = n->counts[f];
    if (count > 0) {
        WoofFx chain[WOOF_FX_MAX];
        if (count > WOOF_FX_MAX) count = WOOF_FX_MAX;
        memcpy(chain, n->chains[f], sizeof(WoofFx) * (size_t)count);
        // Automation, once per block (a few milliseconds: smooth enough)
        ma_uint64 len = n->len_frames;
        if (len > 0) {
            ma_uint64 at = n->looping ? n->pos % len : (n->pos < len ? n->pos : len);
            float t = (float)at / (float)len;
            for (int i = 0; i < count; i++) {
                int k = chain[i].auto_param;
                if (k >= 0 && k < 4) chain[i].p[k] += (chain[i].auto_to - chain[i].p[k]) * t;
            }
        }
        dsp_process(&n->dsp, chain, count, out, frames);
    }
    n->pos += frames;

    float peak = 0;
    const size_t total = (size_t)frames * ch;
    for (size_t i = 0; i < total; i++) {
        float v = fabsf(out[i]);
        if (v > peak) peak = v;
    }
    if (peak > n->peak) n->peak = peak;
    n->silent_frames = peak < 1e-5f ? n->silent_frames + frames : 0;
    *count_in = frames;
    *count_out = frames;
}

static ma_node_vtable g_fx_vtable = {fx_node_process, NULL, 1, 1, MA_NODE_FLAG_CONTINUOUS_PROCESSING};

// UI thread: allocates what the chain needs, then hands it to the audio thread
static void fx_push(WoofFxNode *n, const WoofFx *chain, int count) {
    if (count > WOOF_FX_MAX) count = WOOF_FX_MAX;
    if (count < 0) count = 0;
    dsp_prepare(&n->dsp, chain, count);
    ma_uint32 back = 1 - (ma_atomic_load_32(&n->front) & 1);
    if (count > 0) memcpy(n->chains[back], chain, sizeof(WoofFx) * (size_t)count);
    n->counts[back] = count;
    ma_atomic_exchange_32(&n->front, back);
}

static void fx_wake(WoofFxNode *n) {
    if (n == NULL) return;
    n->silent_frames = 0;
    if (!n->running) {
        ma_node_set_state(&n->base, ma_node_state_started);
        n->running = MA_TRUE;
    }
}

static void fx_free(WoofFxNode **node) {
    if (*node == NULL) return;
    ma_node_uninit(&(*node)->base, NULL);
    dsp_free(&(*node)->dsp);
    free(*node);
    *node = NULL;
}

// The effect node of a voice, created and wired in on first use
static WoofFxNode *voice_fx(WoofOutput *out, int id, int v) {
    WoofVoices *voices = &out->sounds[id];
    if (voices->fx[v] != NULL) return voices->fx[v];
    if (voices->voices[v] == NULL) return NULL;
    ma_uint32 channels = ma_engine_get_channels(&out->engine);
    if (channels == 0 || channels > WOOF_DSP_CH) return NULL;
    WoofFxNode *n = (WoofFxNode *)calloc(1, sizeof(WoofFxNode));
    if (n == NULL) return NULL;
    ma_node_config config = ma_node_config_init();
    config.vtable = &g_fx_vtable;
    config.pInputChannels = &channels;
    config.pOutputChannels = &channels;
    if (ma_node_init(ma_engine_get_node_graph(&out->engine), &config, NULL, &n->base) != MA_SUCCESS) {
        free(n);
        return NULL;
    }
    n->running = MA_TRUE;
    dsp_init(&n->dsp, channels, ma_engine_get_sample_rate(&out->engine));
    fx_push(n, g_sounds[id].fx, g_sounds[id].fx_count);
    ma_node_attach_output_bus(&n->base, 0, ma_engine_get_endpoint(&out->engine), 0);
    ma_node_attach_output_bus(voices->voices[v], 0, &n->base, 0);
    voices->fx[v] = n;
    return n;
}

static float effective_volume(int id) {
    const WoofSound *s = &g_sounds[id];
    return s->muted ? 0.0f : s->volume * s->live_volume;
}

static void apply_volume(int id) {
    float vol = effective_volume(id);
    for (int i = 0; i < WOOF_OUT_COUNT; i++) {
        if (!g_outputs[i].active) continue;
        for (int v = 0; v < WOOF_MAX_VOICES; v++) {
            ma_sound *voice = g_outputs[i].sounds[id].voices[v];
            if (voice != NULL) ma_sound_set_volume(voice, vol);
        }
    }
}

static void voice_free(ma_sound **voice) {
    if (*voice == NULL) return;
    ma_sound_uninit(*voice);
    free(*voice);
    *voice = NULL;
}

static void output_load_sound(WoofOutput *out, int id) {
    ma_sound *voice = (ma_sound *)calloc(1, sizeof(ma_sound));
    if (voice == NULL) return;
    if (sound_init_from_path(&out->engine, g_sounds[id].path, k_sound_flags, voice) != MA_SUCCESS) {
        free(voice);
        return;
    }
    out->sounds[id].voices[0] = voice;
    apply_params(id, voice);
}

static void output_unload_sound(WoofOutput *out, int id) {
    for (int v = 0; v < WOOF_MAX_VOICES; v++) {
        // The sound first, so nothing feeds the effect node anymore
        voice_free(&out->sounds[id].voices[v]);
        fx_free(&out->sounds[id].fx[v]);
        out->sounds[id].paused[v] = MA_FALSE;
        out->sounds[id].fading[v] = MA_FALSE;
        out->sounds[id].fade_stop[v] = MA_FALSE;
    }
}

static void output_shutdown(WoofOutput *out) {
    if (!out->active) return;
    for (int id = 0; id < WOOF_MAX_SOUNDS; id++) output_unload_sound(out, id);
    ma_engine_uninit(&out->engine);
    out->active = MA_FALSE;
}

// The output whose voices decide what "playing" means (monitor, or the mic if the monitor failed)
static WoofOutput *reference_output(void) {
    for (int i = 0; i < WOOF_OUT_COUNT; i++) {
        if (g_outputs[i].active) return &g_outputs[i];
    }
    return NULL;
}

int woof_init(void) {
    if (ma_context_init(NULL, 0, NULL, &g_context) != MA_SUCCESS) return -1;

    ma_resource_manager_config rm_config = ma_resource_manager_config_init();
    rm_config.decodedFormat = ma_format_f32;
    rm_config.decodedSampleRate = 48000;
    if (ma_resource_manager_init(&rm_config, &g_resources) != MA_SUCCESS) {
        ma_context_uninit(&g_context);
        return -1;
    }

    for (int i = 0; i < WOOF_OUT_COUNT; i++) g_outputs[i].volume = 1.0f;
    g_ready = MA_TRUE;
    woof_refresh_devices();
    return woof_set_output(WOOF_OUT_MONITOR, -1);
}

void woof_deinit(void) {
    if (!g_ready) return;
    woof_rec_discard();
    woof_preview_stop();
    for (int i = 0; i < WOOF_OUT_COUNT; i++) output_shutdown(&g_outputs[i]);
    for (int id = 0; id < WOOF_MAX_SOUNDS; id++) {
        free(g_sounds[id].path);
        g_sounds[id].path = NULL;
    }
    ma_resource_manager_uninit(&g_resources);
    ma_context_uninit(&g_context);
    g_ready = MA_FALSE;
}

int woof_refresh_devices(void) {
    if (!g_ready) return 0;
    ma_device_info *infos = NULL;
    ma_uint32 count = 0;
    ma_device_info *cap_infos = NULL;
    ma_uint32 cap_count = 0;
    g_device_count = 0;
    g_capture_count = 0;
    if (ma_context_get_devices(&g_context, &infos, &count, &cap_infos, &cap_count) != MA_SUCCESS) return 0;
    for (ma_uint32 i = 0; i < cap_count && g_capture_count < WOOF_MAX_DEVICES; i++) {
        WoofCapture *cap = &g_captures[g_capture_count++];
        strncpy(cap->name, cap_infos[i].name, sizeof(cap->name) - 1);
        cap->name[sizeof(cap->name) - 1] = '\0';
        cap->id = cap_infos[i].id;
        cap->is_default = cap_infos[i].isDefault;
    }
    for (ma_uint32 i = 0; i < count && g_device_count < WOOF_MAX_DEVICES; i++) {
        WoofDevice *dev = &g_devices[g_device_count++];
        strncpy(dev->name, infos[i].name, sizeof(dev->name) - 1);
        dev->name[sizeof(dev->name) - 1] = '\0';
        dev->id = infos[i].id;
        dev->is_default = infos[i].isDefault;
    }
    return g_device_count;
}

int woof_device_count(void) {
    return g_device_count;
}

const char *woof_device_name(int index) {
    if (index < 0 || index >= g_device_count) return "";
    return g_devices[index].name;
}

int woof_device_is_default(int index) {
    if (index < 0 || index >= g_device_count) return 0;
    return g_devices[index].is_default ? 1 : 0;
}

int woof_set_output(int slot, int device_index) {
    if (!g_ready || slot < 0 || slot >= WOOF_OUT_COUNT) return -1;
    WoofOutput *out = &g_outputs[slot];
    if (slot == WOOF_OUT_MONITOR) woof_preview_stop(); // the preview lives on the monitor engine
    output_shutdown(out);

    if (slot == WOOF_OUT_MIC && device_index < 0) return 0;

    ma_engine_config config = ma_engine_config_init();
    config.pContext = &g_context;
    config.pResourceManager = &g_resources;
    if (device_index >= 0 && device_index < g_device_count) {
        config.pPlaybackDeviceID = &g_devices[device_index].id;
    }
    if (ma_engine_init(&config, &out->engine) != MA_SUCCESS) return -1;
    out->active = MA_TRUE;
    ma_engine_set_volume(&out->engine, out->volume);

    for (int id = 0; id < WOOF_MAX_SOUNDS; id++) {
        if (g_sounds[id].path != NULL) output_load_sound(out, id);
    }
    return 0;
}

int woof_output_active(int slot) {
    if (slot < 0 || slot >= WOOF_OUT_COUNT) return 0;
    return g_outputs[slot].active ? 1 : 0;
}

void woof_set_output_volume(int slot, float volume) {
    if (slot < 0 || slot >= WOOF_OUT_COUNT) return;
    g_outputs[slot].volume = volume;
    if (g_outputs[slot].active) ma_engine_set_volume(&g_outputs[slot].engine, volume);
}

int woof_load(const char *path) {
    if (!g_ready || path == NULL) return -1;
    int id = -1;
    for (int i = 0; i < WOOF_MAX_SOUNDS; i++) {
        if (g_sounds[i].path == NULL) {
            id = i;
            break;
        }
    }
    if (id < 0) return -1;

    size_t len = strlen(path);
    g_sounds[id].path = (char *)malloc(len + 1);
    if (g_sounds[id].path == NULL) return -1;
    memcpy(g_sounds[id].path, path, len + 1);
    g_sounds[id].last_voice = 0;
    g_sounds[id].trim_start = 0;
    g_sounds[id].trim_end = 0;
    g_sounds[id].loop = MA_FALSE;
    g_sounds[id].speed = 1;
    g_sounds[id].fade_in = 0;
    g_sounds[id].fade_out = 0;
    g_sounds[id].fx_count = 0;
    g_sounds[id].volume = 1;
    g_sounds[id].live_volume = 1;
    g_sounds[id].muted = MA_FALSE;

    ma_bool32 ok = MA_FALSE;
    for (int i = 0; i < WOOF_OUT_COUNT; i++) {
        if (!g_outputs[i].active) continue;
        output_load_sound(&g_outputs[i], id);
        if (g_outputs[i].sounds[id].voices[0] != NULL) ok = MA_TRUE;
    }
    if (!ok) {
        woof_unload(id);
        return -1;
    }
    return id;
}

void woof_unload(int id) {
    if (id < 0 || id >= WOOF_MAX_SOUNDS || g_sounds[id].path == NULL) return;
    for (int i = 0; i < WOOF_OUT_COUNT; i++) output_unload_sound(&g_outputs[i], id);
    free(g_sounds[id].path);
    g_sounds[id].path = NULL;
}

static ma_sound *reference_voice(int id, int voice) {
    if (id < 0 || id >= WOOF_MAX_SOUNDS || g_sounds[id].path == NULL) return NULL;
    WoofOutput *out = reference_output();
    if (out == NULL) return NULL;
    return out->sounds[id].voices[voice];
}

int woof_is_ready(int id) {
    ma_sound *voice = reference_voice(id, 0);
    if (voice == NULL) return 0;
    float length = 0;
    return ma_sound_get_length_in_seconds(voice, &length) == MA_SUCCESS && length > 0 ? 1 : 0;
}

float woof_length(int id) {
    ma_sound *voice = reference_voice(id, 0);
    float length = 0;
    if (voice == NULL || ma_sound_get_length_in_seconds(voice, &length) != MA_SUCCESS) return 0;
    return length;
}

static ma_bool32 voice_playing(ma_sound *voice) {
    return voice != NULL && ma_sound_is_playing(voice);
}

// Picks the voice slot to (re)start for an overlapping play
static int pick_voice(int id) {
    WoofOutput *ref = reference_output();
    int oldest = 0;
    float oldest_cursor = -1;
    for (int v = 0; v < WOOF_MAX_VOICES; v++) {
        ma_sound *voice = ref->sounds[id].voices[v];
        if (voice == NULL || !voice_playing(voice)) return v;
        float cursor = 0;
        ma_sound_get_cursor_in_seconds(voice, &cursor);
        if (cursor > oldest_cursor) {
            oldest_cursor = cursor;
            oldest = v;
        }
    }
    return oldest;
}

static void start_voice(WoofOutput *out, int id, int v, float volume) {
    WoofVoices *voices = &out->sounds[id];
    if (voices->voices[0] == NULL) return;
    if (voices->voices[v] == NULL) {
        ma_sound *copy = (ma_sound *)calloc(1, sizeof(ma_sound));
        if (copy == NULL) return;
        if (ma_sound_init_copy(&out->engine, voices->voices[0], k_sound_flags, NULL, copy) != MA_SUCCESS) {
            free(copy);
            return;
        }
        voices->voices[v] = copy;
    }
    ma_sound *voice = voices->voices[v];
    apply_params(id, voice);
    // A fade-out from the previous play leaves a stop time in the past
    ma_sound_reset_stop_time_and_fade(voice);
    if (g_sounds[id].fade_in > 0) ma_sound_set_fade_in_milliseconds(voice, 0, 1, (ma_uint64)(g_sounds[id].fade_in * 1000));
    voices->paused[v] = MA_FALSE;
    voices->fading[v] = MA_FALSE;
    voices->fade_stop[v] = MA_FALSE;
    (void)volume;
    ma_sound_set_volume(voice, effective_volume(id));
    WoofFxNode *fx = voice_fx(out, id, v);
    if (fx != NULL) {
        float seconds = 0;
        ma_sound_get_length_in_seconds(voice, &seconds);
        fx->len_frames = (ma_uint64)(seconds / sound_speed(id) * (float)ma_engine_get_sample_rate(&out->engine));
        fx->looping = g_sounds[id].loop;
        fx->reset_pos = 0;
        ma_atomic_exchange_32(&fx->reset, 1);
        fx_wake(fx);
    }
    ma_sound_seek_to_pcm_frame(voice, 0);
    ma_sound_start(voice);
}

void woof_play(int id, float volume, int mode) {
    if (reference_voice(id, 0) == NULL) return;

    if (mode == WOOF_MODE_TOGGLE && woof_is_playing(id)) {
        woof_stop(id);
        return;
    }

    int v = mode == WOOF_MODE_OVERLAP ? pick_voice(id) : 0;
    if (mode != WOOF_MODE_OVERLAP) woof_stop(id);
    g_sounds[id].volume = volume;
    g_sounds[id].live_volume = 1;
    g_sounds[id].muted = MA_FALSE;
    for (int i = 0; i < WOOF_OUT_COUNT; i++) {
        if (g_outputs[i].active) start_voice(&g_outputs[i], id, v, volume);
    }
    g_sounds[id].last_voice = v;
}

void woof_stop(int id) {
    if (id < 0 || id >= WOOF_MAX_SOUNDS) return;
    for (int i = 0; i < WOOF_OUT_COUNT; i++) {
        if (!g_outputs[i].active) continue;
        WoofVoices *voices = &g_outputs[i].sounds[id];
        for (int v = 0; v < WOOF_MAX_VOICES; v++) {
            if (voices->voices[v] != NULL) ma_sound_stop(voices->voices[v]);
            if (voices->fx[v] != NULL) ma_atomic_exchange_32(&voices->fx[v]->reset, 1);
            voices->paused[v] = MA_FALSE;
            voices->fading[v] = MA_FALSE;
            voices->fade_stop[v] = MA_FALSE;
        }
    }
}

void woof_stop_all(void) {
    for (int id = 0; id < WOOF_MAX_SOUNDS; id++) {
        if (g_sounds[id].path != NULL) woof_stop(id);
    }
    woof_preview_stop();
}

int woof_is_playing(int id) {
    for (int v = 0; v < WOOF_MAX_VOICES; v++) {
        if (voice_playing(reference_voice(id, v))) return 1;
    }
    return 0;
}

float woof_cursor(int id) {
    if (id < 0 || id >= WOOF_MAX_SOUNDS) return 0;
    ma_sound *voice = reference_voice(id, g_sounds[id].last_voice);
    float cursor = 0;
    if (voice == NULL || ma_sound_get_cursor_in_seconds(voice, &cursor) != MA_SUCCESS) return 0;
    return cursor;
}

int woof_playing_count(void) {
    int count = 0;
    for (int id = 0; id < WOOF_MAX_SOUNDS; id++) {
        if (g_sounds[id].path != NULL && woof_is_playing(id)) count++;
    }
    return count;
}

// ── Per-sound settings ──────────────────────────────────────────────────────

void woof_set_params(int id, float trim_start, float trim_end, int loop, float speed, float fade_in, float fade_out) {
    if (!valid_id(id)) return;
    WoofSound *s = &g_sounds[id];
    s->trim_start = trim_start > 0 ? trim_start : 0;
    s->trim_end = trim_end > 0 ? trim_end : 0;
    s->loop = loop ? MA_TRUE : MA_FALSE;
    s->speed = speed > 0.01f ? speed : 1.0f;
    s->fade_in = fade_in > 0 ? fade_in : 0;
    s->fade_out = fade_out > 0 ? fade_out : 0;
    // Voices pick everything up on their next start; loop and speed also apply live
    for (int i = 0; i < WOOF_OUT_COUNT; i++) {
        if (!g_outputs[i].active) continue;
        for (int v = 0; v < WOOF_MAX_VOICES; v++) {
            ma_sound *voice = g_outputs[i].sounds[id].voices[v];
            if (voice == NULL) continue;
            if (ma_sound_is_playing(voice) || g_outputs[i].sounds[id].paused[v]) {
                ma_sound_set_looping(voice, s->loop);
                ma_sound_set_pitch(voice, sound_speed(id));
            } else {
                apply_params(id, voice);
            }
        }
    }
}

float woof_full_length(int id) {
    ma_sound *voice = reference_voice(id, 0);
    if (voice == NULL) return 0;
    return (float)full_length_frames(voice) / WOOF_RATE;
}

// ── Pause / resume ──────────────────────────────────────────────────────────

void woof_pause(int id) {
    if (!valid_id(id)) return;
    for (int i = 0; i < WOOF_OUT_COUNT; i++) {
        if (!g_outputs[i].active) continue;
        WoofVoices *voices = &g_outputs[i].sounds[id];
        for (int v = 0; v < WOOF_MAX_VOICES; v++) {
            if (!voice_playing(voices->voices[v])) continue;
            ma_sound_stop(voices->voices[v]);
            // A scheduled fade-out would fire the moment the voice resumes
            ma_sound_reset_stop_time_and_fade(voices->voices[v]);
            voices->paused[v] = MA_TRUE;
            voices->fading[v] = MA_FALSE;
        }
    }
}

void woof_resume(int id) {
    if (!valid_id(id)) return;
    for (int i = 0; i < WOOF_OUT_COUNT; i++) {
        if (!g_outputs[i].active) continue;
        WoofVoices *voices = &g_outputs[i].sounds[id];
        for (int v = 0; v < WOOF_MAX_VOICES; v++) {
            if (!voices->paused[v]) continue;
            voices->paused[v] = MA_FALSE;
            fx_wake(voices->fx[v]);
            if (voices->voices[v] != NULL) ma_sound_start(voices->voices[v]);
        }
    }
}

int woof_is_paused(int id) {
    if (!valid_id(id)) return 0;
    WoofOutput *out = reference_output();
    if (out == NULL) return 0;
    for (int v = 0; v < WOOF_MAX_VOICES; v++) {
        if (out->sounds[id].paused[v]) return 1;
    }
    return 0;
}

void woof_pause_all(void) {
    for (int id = 0; id < WOOF_MAX_SOUNDS; id++) {
        if (g_sounds[id].path != NULL) woof_pause(id);
    }
}

void woof_resume_all(void) {
    for (int id = 0; id < WOOF_MAX_SOUNDS; id++) {
        if (g_sounds[id].path != NULL) woof_resume(id);
    }
}

int woof_paused_count(void) {
    int count = 0;
    for (int id = 0; id < WOOF_MAX_SOUNDS; id++) {
        if (g_sounds[id].path != NULL && woof_is_paused(id)) count++;
    }
    return count;
}

static void rec_update(void);

// Effect nodes of voices that stopped keep running until their tail dies out
static void sleep_idle_fx(void) {
    for (int i = 0; i < WOOF_OUT_COUNT; i++) {
        WoofOutput *out = &g_outputs[i];
        if (!out->active) continue;
        ma_uint32 idle = ma_engine_get_sample_rate(&out->engine);
        for (int id = 0; id < WOOF_MAX_SOUNDS; id++) {
            if (g_sounds[id].path == NULL) continue;
            WoofVoices *voices = &out->sounds[id];
            for (int v = 0; v < WOOF_MAX_VOICES; v++) {
                WoofFxNode *n = voices->fx[v];
                if (n == NULL || !n->running || voices->paused[v] || voice_playing(voices->voices[v])) continue;
                if (n->silent_frames < idle) continue;
                ma_node_set_state(&n->base, ma_node_state_stopped);
                n->running = MA_FALSE;
            }
        }
    }
}

void woof_update(void) {
    sleep_idle_fx();
    rec_update();
    for (int id = 0; id < WOOF_MAX_SOUNDS; id++) {
        const WoofSound *s = &g_sounds[id];
        if (s->path == NULL || s->fade_out <= 0 || s->loop) continue;
        for (int i = 0; i < WOOF_OUT_COUNT; i++) {
            if (!g_outputs[i].active) continue;
            WoofVoices *voices = &g_outputs[i].sounds[id];
            for (int v = 0; v < WOOF_MAX_VOICES; v++) {
                ma_sound *voice = voices->voices[v];
                if (voices->fading[v] || !voice_playing(voice)) continue;
                float length = 0, cursor = 0;
                if (ma_sound_get_length_in_seconds(voice, &length) != MA_SUCCESS || length <= 0) continue;
                ma_sound_get_cursor_in_seconds(voice, &cursor);
                float remaining = (length - cursor) / sound_speed(id);
                if (remaining > s->fade_out) continue;
                ma_uint32 rate = ma_engine_get_sample_rate(&g_outputs[i].engine);
                ma_sound_stop_with_fade_in_pcm_frames(voice, (ma_uint64)(remaining * (float)rate));
                voices->fading[v] = MA_TRUE;
            }
        }
    }
}

// ── Waveform ────────────────────────────────────────────────────────────────

#define WAVE_RATE 8000
#define WAVE_BLOCK 40 // 5 ms per stored peak

int woof_waveform(const char *path, float *peaks, int bins, float *duration) {
    if (path == NULL || peaks == NULL || bins <= 0) return 0;
    ma_decoder_config config = ma_decoder_config_init(ma_format_f32, 1, WAVE_RATE);
    ma_decoder decoder;
#ifdef _WIN32
    wchar_t *wide = utf8_to_wide(path);
    if (wide == NULL) return 0;
    ma_result result = ma_decoder_init_file_w(wide, &config, &decoder);
    free(wide);
#else
    ma_result result = ma_decoder_init_file(path, &config, &decoder);
#endif
    if (result != MA_SUCCESS) return 0;

    // Loudness (RMS) of 5 ms blocks first, since the total length may be unknown
    // up front. RMS gives a readable shape even for heavily compressed files,
    // where plain peaks would all sit at the top.
    size_t cap = 4096, count = 0;
    float *blocks = (float *)malloc(cap * sizeof(float));
    float chunk[WAVE_BLOCK * 64];
    ma_uint64 total = 0;
    while (blocks != NULL) {
        ma_uint64 read = 0;
        if (ma_decoder_read_pcm_frames(&decoder, chunk, WAVE_BLOCK * 64, &read) != MA_SUCCESS || read == 0) break;
        total += read;
        for (ma_uint64 b = 0; b < read; b += WAVE_BLOCK) {
            float sum = 0;
            ma_uint64 n = 0;
            for (ma_uint64 f = b; f < b + WAVE_BLOCK && f < read; f++, n++) sum += chunk[f] * chunk[f];
            float peak = n > 0 ? sqrtf(sum / (float)n) : 0;
            if (count == cap) {
                cap *= 2;
                float *grown = (float *)realloc(blocks, cap * sizeof(float));
                if (grown == NULL) break;
                blocks = grown;
            }
            blocks[count++] = peak;
        }
    }
    ma_decoder_uninit(&decoder);
    if (blocks == NULL || count == 0) {
        free(blocks);
        return 0;
    }

    for (int i = 0; i < bins; i++) {
        size_t from = (size_t)((double)i * count / bins);
        size_t to = (size_t)((double)(i + 1) * count / bins);
        if (to <= from) to = from + 1;
        float peak = 0;
        for (size_t b = from; b < to && b < count; b++) {
            if (blocks[b] > peak) peak = blocks[b];
        }
        peaks[i] = peak > 1 ? 1 : peak;
    }
    free(blocks);
    if (duration != NULL) *duration = (float)total / WAVE_RATE;
    return bins;
}

// ── Preview ─────────────────────────────────────────────────────────────────

int woof_preview_play(const char *path, float volume) {
    woof_preview_stop();
    WoofOutput *monitor = &g_outputs[WOOF_OUT_MONITOR];
    if (!monitor->active) return -1;
    ma_uint32 flags = MA_SOUND_FLAG_STREAM | MA_SOUND_FLAG_NO_SPATIALIZATION;
    if (sound_init_from_path(&monitor->engine, path, flags, &g_preview) != MA_SUCCESS) return -1;
    g_preview_loaded = MA_TRUE;
    ma_sound_set_volume(&g_preview, volume);
    ma_sound_start(&g_preview);
    return 0;
}

void woof_preview_stop(void) {
    if (!g_preview_loaded) return;
    ma_sound_uninit(&g_preview);
    g_preview_loaded = MA_FALSE;
}

int woof_preview_is_playing(void) {
    return g_preview_loaded && ma_sound_is_playing(&g_preview) ? 1 : 0;
}

float woof_preview_cursor(void) {
    float cursor = 0;
    if (g_preview_loaded) ma_sound_get_cursor_in_seconds(&g_preview, &cursor);
    return cursor;
}

float woof_preview_length(void) {
    float length = 0;
    if (g_preview_loaded) ma_sound_get_length_in_seconds(&g_preview, &length);
    return length;
}

// ── Live effects ────────────────────────────────────────────────────────────

void woof_set_fx(int id, const WoofFx *chain, int count) {
    if (!valid_id(id)) return;
    if (count < 0 || chain == NULL) count = 0;
    if (count > WOOF_FX_MAX) count = WOOF_FX_MAX;
    WoofSound *s = &g_sounds[id];
    if (count > 0) memcpy(s->fx, chain, sizeof(WoofFx) * (size_t)count);
    s->fx_count = count;
    for (int i = 0; i < WOOF_OUT_COUNT; i++) {
        if (!g_outputs[i].active) continue;
        for (int v = 0; v < WOOF_MAX_VOICES; v++) {
            WoofFxNode *n = g_outputs[i].sounds[id].fx[v];
            if (n != NULL) fx_push(n, s->fx, s->fx_count);
        }
    }
}

// ── Mixer ───────────────────────────────────────────────────────────────────

void woof_set_live_volume(int id, float volume) {
    if (!valid_id(id)) return;
    g_sounds[id].live_volume = volume < 0 ? 0 : (volume > 2 ? 2 : volume);
    apply_volume(id);
}

float woof_live_volume(int id) {
    return valid_id(id) ? g_sounds[id].live_volume : 1;
}

void woof_set_muted(int id, int muted) {
    if (!valid_id(id)) return;
    g_sounds[id].muted = muted ? MA_TRUE : MA_FALSE;
    apply_volume(id);
}

int woof_is_muted(int id) {
    return valid_id(id) && g_sounds[id].muted ? 1 : 0;
}

void woof_fade_stop(int id, float seconds) {
    if (!valid_id(id)) return;
    ma_uint64 ms = (ma_uint64)((seconds > 0.01f ? seconds : 0.01f) * 1000);
    for (int i = 0; i < WOOF_OUT_COUNT; i++) {
        if (!g_outputs[i].active) continue;
        WoofVoices *voices = &g_outputs[i].sounds[id];
        for (int v = 0; v < WOOF_MAX_VOICES; v++) {
            if (voices->paused[v]) {
                // A paused voice has nothing to fade: just forget it
                voices->paused[v] = MA_FALSE;
                continue;
            }
            if (!voice_playing(voices->voices[v])) continue;
            ma_sound_stop_with_fade_in_milliseconds(voices->voices[v], ms);
            voices->fading[v] = MA_TRUE;
            voices->fade_stop[v] = MA_TRUE;
        }
    }
}

int woof_is_fading(int id) {
    if (!valid_id(id)) return 0;
    WoofOutput *out = reference_output();
    if (out == NULL) return 0;
    for (int v = 0; v < WOOF_MAX_VOICES; v++) {
        if (out->sounds[id].fade_stop[v] && voice_playing(out->sounds[id].voices[v])) return 1;
    }
    return 0;
}

float woof_level(int id) {
    if (!valid_id(id)) return 0;
    WoofOutput *out = reference_output();
    if (out == NULL) return 0;
    float peak = 0;
    for (int v = 0; v < WOOF_MAX_VOICES; v++) {
        WoofFxNode *n = out->sounds[id].fx[v];
        if (n == NULL) continue;
        float p = n->peak;
        n->peak = 0;
        if (p > peak) peak = p;
    }
    return peak;
}

void woof_seek(int id, float seconds) {
    if (!valid_id(id)) return;
    int v = g_sounds[id].last_voice;
    ma_uint64 frame = (ma_uint64)((seconds > 0 ? seconds : 0) * WOOF_RATE);
    for (int i = 0; i < WOOF_OUT_COUNT; i++) {
        if (!g_outputs[i].active) continue;
        ma_sound *voice = g_outputs[i].sounds[id].voices[v];
        if (voice == NULL) continue;
        ma_sound_seek_to_pcm_frame(voice, frame);
        WoofFxNode *n = g_outputs[i].sounds[id].fx[v];
        if (n != NULL) {
            n->reset_pos = (ma_uint64)((seconds > 0 ? seconds : 0) / sound_speed(id) * (float)ma_engine_get_sample_rate(&g_outputs[i].engine));
            ma_atomic_exchange_32(&n->reset, 1);
        }
    }
}

void woof_play_from(int id, float volume, float seconds) {
    if (reference_voice(id, 0) == NULL) return;
    woof_play(id, volume, WOOF_MODE_RESTART);
    if (seconds > 0) woof_seek(id, seconds);
}

// ── Recorder ────────────────────────────────────────────────────────────────

#define REC_CH 2
#define REC_CHUNK WOOF_REC_RATE // frames per allocation (one second)
#define REC_MAX_FRAMES ((ma_uint32)WOOF_REC_MAX_SECONDS * WOOF_REC_RATE)
#define REC_BLOCK (WOOF_REC_RATE / WOOF_REC_PEAKS_PER_SECOND)
#define REC_MAX_PEAKS (WOOF_REC_MAX_SECONDS * WOOF_REC_PEAKS_PER_SECOND)

static ma_device g_rec_device;
static ma_bool32 g_rec_open;
static ma_int16 *g_rec_chunks[WOOF_REC_MAX_SECONDS];
static ma_uint32 g_rec_frames;      // written by the capture thread
static ma_uint32 g_rec_peak_count;  // written by the capture thread
static float g_rec_peak_data[REC_MAX_PEAKS];
static float g_rec_block_peak;
static ma_uint32 g_rec_block_fill;
static volatile float g_rec_level;

static void rec_callback(ma_device *device, void *output, const void *input, ma_uint32 frame_count) {
    (void)device;
    (void)output;
    const float *in = (const float *)input;
    if (in == NULL) return;
    ma_uint32 pos = ma_atomic_load_32(&g_rec_frames);
    ma_uint32 peaks = ma_atomic_load_32(&g_rec_peak_count);
    float level = 0;
    for (ma_uint32 f = 0; f < frame_count; f++) {
        if (pos >= REC_MAX_FRAMES) break;
        ma_int16 *chunk = g_rec_chunks[pos / REC_CHUNK];
        if (chunk == NULL) break; // the UI thread fell behind allocating
        ma_int16 *dst = chunk + (size_t)(pos % REC_CHUNK) * REC_CH;
        for (int c = 0; c < REC_CH; c++) {
            float v = in[(size_t)f * REC_CH + c];
            if (v > 1) v = 1;
            if (v < -1) v = -1;
            dst[c] = (ma_int16)(v * 32767.0f);
            float a = fabsf(v);
            if (a > g_rec_block_peak) g_rec_block_peak = a;
            if (a > level) level = a;
        }
        pos++;
        if (++g_rec_block_fill >= REC_BLOCK) {
            if (peaks < REC_MAX_PEAKS) g_rec_peak_data[peaks++] = g_rec_block_peak;
            g_rec_block_peak = 0;
            g_rec_block_fill = 0;
        }
    }
    if (level > g_rec_level) g_rec_level = level;
    ma_atomic_exchange_32(&g_rec_peak_count, peaks);
    ma_atomic_exchange_32(&g_rec_frames, pos);
}

// Keeps a couple of seconds of buffer allocated ahead of the capture thread
static void rec_update(void) {
    if (!g_rec_open) return;
    ma_uint32 chunk = ma_atomic_load_32(&g_rec_frames) / REC_CHUNK;
    for (ma_uint32 c = chunk; c < chunk + 3 && c < WOOF_REC_MAX_SECONDS; c++) {
        if (g_rec_chunks[c] == NULL) g_rec_chunks[c] = (ma_int16 *)malloc(sizeof(ma_int16) * REC_CHUNK * REC_CH);
    }
    if (ma_atomic_load_32(&g_rec_frames) >= REC_MAX_FRAMES) woof_rec_stop();
}

int woof_capture_count(void) {
    return g_capture_count;
}

const char *woof_capture_name(int index) {
    if (index < 0 || index >= g_capture_count) return "";
    return g_captures[index].name;
}

int woof_capture_is_default(int index) {
    if (index < 0 || index >= g_capture_count) return 0;
    return g_captures[index].is_default ? 1 : 0;
}

static int find_monitor_capture(void) {
    for (int i = 0; i < g_capture_count; i++) {
        if (strstr(g_captures[i].name, "Monitor") != NULL || strstr(g_captures[i].name, "monitor") != NULL) return i;
    }
    return -1;
}

int woof_rec_system_supported(void) {
    if (!g_ready) return 0;
    if (g_context.backend == ma_backend_wasapi || g_context.backend == ma_backend_pulseaudio) return 1;
    return find_monitor_capture() >= 0 ? 1 : 0;
}

static ma_result rec_open(ma_device_type type, const ma_device_id *id) {
    ma_device_config config = ma_device_config_init(type);
    config.capture.format = ma_format_f32;
    config.capture.channels = REC_CH;
    config.capture.pDeviceID = (ma_device_id *)id;
    config.sampleRate = WOOF_REC_RATE;
    config.dataCallback = rec_callback;
    return ma_device_init(&g_context, &config, &g_rec_device);
}

int woof_rec_start(int source) {
    if (!g_ready) return -1;
    woof_rec_discard();
    for (int c = 0; c < 3; c++) {
        g_rec_chunks[c] = (ma_int16 *)malloc(sizeof(ma_int16) * REC_CHUNK * REC_CH);
        if (g_rec_chunks[c] == NULL) return -1;
    }

    ma_result result = MA_ERROR;
    if (source == WOOF_REC_SYSTEM) {
        if (g_context.backend == ma_backend_wasapi) {
            result = rec_open(ma_device_type_loopback, NULL);
        } else {
            if (g_context.backend == ma_backend_pulseaudio) {
                // The monitor of whatever output is the default right now
                ma_device_id id;
                memset(&id, 0, sizeof(id));
                strncpy(id.pulse, "@DEFAULT_MONITOR@", sizeof(id.pulse) - 1);
                result = rec_open(ma_device_type_capture, &id);
            }
            if (result != MA_SUCCESS) {
                int mon = find_monitor_capture();
                if (mon >= 0) result = rec_open(ma_device_type_capture, &g_captures[mon].id);
            }
        }
    } else if (source == WOOF_REC_DEFAULT_MIC) {
        result = rec_open(ma_device_type_capture, NULL);
    } else if (source >= 0 && source < g_capture_count) {
        result = rec_open(ma_device_type_capture, &g_captures[source].id);
    }
    if (result != MA_SUCCESS) {
        woof_rec_discard();
        return -2;
    }
    g_rec_open = MA_TRUE;
    if (ma_device_start(&g_rec_device) != MA_SUCCESS) {
        woof_rec_discard();
        return -3;
    }
    return 0;
}

void woof_rec_stop(void) {
    if (!g_rec_open) return;
    ma_device_uninit(&g_rec_device);
    g_rec_open = MA_FALSE;
}

int woof_rec_active(void) {
    return g_rec_open ? 1 : 0;
}

float woof_rec_seconds(void) {
    return (float)ma_atomic_load_32(&g_rec_frames) / WOOF_REC_RATE;
}

float woof_rec_level(void) {
    float v = g_rec_level;
    g_rec_level = 0;
    return v;
}

int woof_rec_peak_count(void) {
    return (int)ma_atomic_load_32(&g_rec_peak_count);
}

const float *woof_rec_peaks(void) {
    return g_rec_peak_data;
}

static void put_u32(unsigned char *p, ma_uint32 v) {
    p[0] = (unsigned char)(v & 0xff);
    p[1] = (unsigned char)((v >> 8) & 0xff);
    p[2] = (unsigned char)((v >> 16) & 0xff);
    p[3] = (unsigned char)((v >> 24) & 0xff);
}

static void put_u16(unsigned char *p, ma_uint16 v) {
    p[0] = (unsigned char)(v & 0xff);
    p[1] = (unsigned char)((v >> 8) & 0xff);
}

static FILE *open_utf8(const char *path, const char *mode) {
#ifdef _WIN32
    wchar_t *wide = utf8_to_wide(path);
    wchar_t *wmode = utf8_to_wide(mode);
    FILE *f = (wide != NULL && wmode != NULL) ? _wfopen(wide, wmode) : NULL;
    free(wide);
    free(wmode);
    return f;
#else
    return fopen(path, mode);
#endif
}

int woof_rec_save(const char *path, float start, float end) {
    if (path == NULL) return -1;
    ma_uint32 total = ma_atomic_load_32(&g_rec_frames);
    ma_uint32 from = start > 0 ? (ma_uint32)(start * WOOF_REC_RATE) : 0;
    ma_uint32 to = end > 0 ? (ma_uint32)(end * WOOF_REC_RATE) : total;
    if (to > total) to = total;
    if (from >= to) return -1;
    ma_uint32 frames = to - from;
    ma_uint32 data_bytes = frames * REC_CH * 2;

    FILE *f = open_utf8(path, "wb");
    if (f == NULL) return -1;
    unsigned char h[44];
    memcpy(h, "RIFF", 4);
    put_u32(h + 4, 36 + data_bytes);
    memcpy(h + 8, "WAVEfmt ", 8);
    put_u32(h + 16, 16);
    put_u16(h + 20, 1); // PCM
    put_u16(h + 22, REC_CH);
    put_u32(h + 24, WOOF_REC_RATE);
    put_u32(h + 28, WOOF_REC_RATE * REC_CH * 2);
    put_u16(h + 32, REC_CH * 2);
    put_u16(h + 34, 16);
    memcpy(h + 36, "data", 4);
    put_u32(h + 40, data_bytes);
    int ok = fwrite(h, 1, sizeof(h), f) == sizeof(h);

    unsigned char buf[4096];
    size_t fill = 0;
    for (ma_uint32 pos = from; pos < to && ok; pos++) {
        const ma_int16 *chunk = g_rec_chunks[pos / REC_CHUNK];
        for (int c = 0; c < REC_CH; c++) {
            ma_int16 v = chunk != NULL ? chunk[(size_t)(pos % REC_CHUNK) * REC_CH + c] : 0;
            put_u16(buf + fill, (ma_uint16)v);
            fill += 2;
        }
        if (fill + REC_CH * 2 > sizeof(buf)) {
            ok = fwrite(buf, 1, fill, f) == fill;
            fill = 0;
        }
    }
    if (ok && fill > 0) ok = fwrite(buf, 1, fill, f) == fill;
    if (fclose(f) != 0) ok = 0;
    return ok ? 0 : -1;
}

void woof_rec_discard(void) {
    woof_rec_stop();
    for (int c = 0; c < WOOF_REC_MAX_SECONDS; c++) {
        free(g_rec_chunks[c]);
        g_rec_chunks[c] = NULL;
    }
    ma_atomic_exchange_32(&g_rec_frames, 0);
    ma_atomic_exchange_32(&g_rec_peak_count, 0);
    g_rec_block_peak = 0;
    g_rec_block_fill = 0;
    g_rec_level = 0;
}

// ── Loudness ────────────────────────────────────────────────────────────────

#define LOUD_RATE 16000
#define LOUD_BLOCK (LOUD_RATE / 10)

int woof_loudness(const char *path, float *loudness_db, float *peak_db) {
    if (path == NULL) return -1;
    ma_decoder_config config = ma_decoder_config_init(ma_format_f32, 2, LOUD_RATE);
    ma_decoder decoder;
#ifdef _WIN32
    wchar_t *wide = utf8_to_wide(path);
    if (wide == NULL) return -1;
    ma_result result = ma_decoder_init_file_w(wide, &config, &decoder);
    free(wide);
#else
    ma_result result = ma_decoder_init_file(path, &config, &decoder);
#endif
    if (result != MA_SUCCESS) return -1;

    size_t cap = 1024, count = 0;
    double *blocks = (double *)malloc(cap * sizeof(double));
    float chunk[LOUD_BLOCK * 2];
    float peak = 0;
    while (blocks != NULL) {
        ma_uint64 read = 0;
        if (ma_decoder_read_pcm_frames(&decoder, chunk, LOUD_BLOCK, &read) != MA_SUCCESS || read == 0) break;
        double sum = 0;
        for (ma_uint64 i = 0; i < read * 2; i++) {
            float v = chunk[i];
            sum += (double)v * v;
            if (fabsf(v) > peak) peak = fabsf(v);
        }
        if (count == cap) {
            cap *= 2;
            double *grown = (double *)realloc(blocks, cap * sizeof(double));
            if (grown == NULL) break;
            blocks = grown;
        }
        // Mean over both channels; short tail blocks count as what they hold
        blocks[count++] = sum / (double)(read * 2);
    }
    ma_decoder_uninit(&decoder);
    if (blocks == NULL || count == 0) {
        free(blocks);
        return -1;
    }
    // Absolute gate at -70 dB, then a relative gate 10 dB under the mean
    double abs_gate = pow(10.0, -70.0 / 10.0);
    double sum = 0;
    size_t n = 0;
    for (size_t i = 0; i < count; i++) {
        if (blocks[i] > abs_gate) {
            sum += blocks[i];
            n++;
        }
    }
    if (n == 0) {
        free(blocks);
        return -1; // silence
    }
    double rel_gate = (sum / (double)n) * 0.1;
    double gated = 0;
    size_t m = 0;
    for (size_t i = 0; i < count; i++) {
        if (blocks[i] > abs_gate && blocks[i] > rel_gate) {
            gated += blocks[i];
            m++;
        }
    }
    free(blocks);
    if (m == 0) return -1;
    if (loudness_db) *loudness_db = (float)(10.0 * log10(gated / (double)m));
    if (peak_db) *peak_db = peak > 0 ? 20.0f * log10f(peak) : -100.0f;
    return 0;
}

// ── Misc ────────────────────────────────────────────────────────────────────

int woof_utc_offset(void) {
    time_t now = time(NULL);
    struct tm local = *localtime(&now);
    struct tm utc = *gmtime(&now);
    // Both read back as local time; the difference is the zone offset
    local.tm_isdst = 0;
    utc.tm_isdst = 0;
    return (int)difftime(mktime(&local), mktime(&utc));
}
