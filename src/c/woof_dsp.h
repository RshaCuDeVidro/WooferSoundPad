// Live effect chain DSP. Plain C, no miniaudio: woof_audio.c wraps this in a
// node graph node per voice. Buffers are allocated by dsp_prepare() on the UI
// thread; dsp_process() runs on the audio thread and skips any effect whose
// buffer is not there yet.
#ifndef WOOF_DSP_H
#define WOOF_DSP_H

#include "woof_audio.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

#define WOOF_DSP_CH 8 // channels with their own effect state
#define WOOF_PI 3.14159265358979f

typedef struct {
    int kind; // effect type the coefficients were computed for, -1 = none
    float f0, q;
    float b0, b1, b2, a1, a2;
    float z1[WOOF_DSP_CH], z2[WOOF_DSP_CH];
} WoofBiquad;

typedef struct {
    float *buf;
    int len, pos;
    float store;
} WoofComb;

typedef struct {
    float *buf;
    int len, pos;
} WoofAllpass;

typedef struct {
    unsigned channels;
    unsigned rate;

    // Pitch shifter: two crossfaded read heads sliding through a delay line
    float *pitch_buf;
    unsigned pitch_len, pitch_mask, pitch_write;
    float pitch_window, pitch_phase;

    WoofBiquad bq[3]; // lowpass, highpass, bandpass

    float crush_hold[WOOF_DSP_CH];
    unsigned crush_count;

    float *echo_buf;
    unsigned echo_len, echo_pos;

    float *reverb_mem;
    WoofComb comb[WOOF_DSP_CH][8];
    WoofAllpass ap[WOOF_DSP_CH][4];

    float *chorus_buf;
    unsigned chorus_len, chorus_pos;
    float chorus_phase;

    float trem_phase;
    float robot_phase;
} WoofDsp;

static float dsp_clampf(float v, float lo, float hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

static void dsp_init(WoofDsp *d, unsigned channels, unsigned rate) {
    memset(d, 0, sizeof(*d));
    d->channels = channels < 1 ? 1 : (channels > WOOF_DSP_CH ? WOOF_DSP_CH : channels);
    d->rate = rate > 0 ? rate : 48000;
    for (int i = 0; i < 3; i++) d->bq[i].kind = -1;
}

static void dsp_free(WoofDsp *d) {
    free(d->pitch_buf);
    free(d->echo_buf);
    free(d->reverb_mem);
    free(d->chorus_buf);
    d->pitch_buf = NULL;
    d->echo_buf = NULL;
    d->reverb_mem = NULL;
    d->chorus_buf = NULL;
}

static const int k_comb_tuning[8] = {1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617};
static const int k_ap_tuning[4] = {556, 441, 341, 225};

// Allocates whatever the chain needs. Call before publishing the chain.
static void dsp_prepare(WoofDsp *d, const WoofFx *chain, int count) {
    unsigned ch = d->channels;
    for (int i = 0; i < count; i++) {
        switch (chain[i].type) {
        case WOOF_FX_PITCH:
            if (d->pitch_buf == NULL) {
                d->pitch_window = 0.05f * (float)d->rate;
                unsigned len = 1;
                while (len < (unsigned)d->pitch_window + 8) len <<= 1;
                float *buf = (float *)calloc((size_t)len * ch, sizeof(float));
                if (buf != NULL) {
                    d->pitch_len = len;
                    d->pitch_mask = len - 1;
                    d->pitch_buf = buf;
                }
            }
            break;
        case WOOF_FX_ECHO:
            if (d->echo_buf == NULL) {
                unsigned len = d->rate + 16; // up to one second
                float *buf = (float *)calloc((size_t)len * ch, sizeof(float));
                if (buf != NULL) {
                    d->echo_len = len;
                    d->echo_buf = buf;
                }
            }
            break;
        case WOOF_FX_REVERB:
            if (d->reverb_mem == NULL) {
                float k = (float)d->rate / 44100.0f;
                size_t total = 0;
                for (unsigned c = 0; c < ch; c++) {
                    int spread = (c & 1) ? 23 : 0;
                    for (int j = 0; j < 8; j++) total += (size_t)((float)(k_comb_tuning[j] + spread) * k) + 1;
                    for (int j = 0; j < 4; j++) total += (size_t)((float)(k_ap_tuning[j] + spread) * k) + 1;
                }
                float *mem = (float *)calloc(total, sizeof(float));
                if (mem == NULL) break;
                float *p = mem;
                for (unsigned c = 0; c < ch; c++) {
                    int spread = (c & 1) ? 23 : 0;
                    for (int j = 0; j < 8; j++) {
                        int len = (int)((float)(k_comb_tuning[j] + spread) * k) + 1;
                        d->comb[c][j] = (WoofComb){.buf = p, .len = len};
                        p += len;
                    }
                    for (int j = 0; j < 4; j++) {
                        int len = (int)((float)(k_ap_tuning[j] + spread) * k) + 1;
                        d->ap[c][j] = (WoofAllpass){.buf = p, .len = len};
                        p += len;
                    }
                }
                d->reverb_mem = mem;
            }
            break;
        case WOOF_FX_CHORUS:
            if (d->chorus_buf == NULL) {
                unsigned len = (unsigned)(0.06f * (float)d->rate) + 8;
                float *buf = (float *)calloc((size_t)len * ch, sizeof(float));
                if (buf != NULL) {
                    d->chorus_len = len;
                    d->chorus_buf = buf;
                }
            }
            break;
        default:
            break;
        }
    }
}

// Clears every tail (echo, reverb...), e.g. when a sound restarts
static void dsp_reset(WoofDsp *d) {
    unsigned ch = d->channels;
    if (d->pitch_buf) memset(d->pitch_buf, 0, sizeof(float) * d->pitch_len * ch);
    if (d->echo_buf) memset(d->echo_buf, 0, sizeof(float) * d->echo_len * ch);
    if (d->chorus_buf) memset(d->chorus_buf, 0, sizeof(float) * d->chorus_len * ch);
    if (d->reverb_mem) {
        for (unsigned c = 0; c < ch; c++) {
            for (int j = 0; j < 8; j++) {
                memset(d->comb[c][j].buf, 0, sizeof(float) * (size_t)d->comb[c][j].len);
                d->comb[c][j].store = 0;
            }
            for (int j = 0; j < 4; j++) memset(d->ap[c][j].buf, 0, sizeof(float) * (size_t)d->ap[c][j].len);
        }
    }
    for (int i = 0; i < 3; i++) {
        memset(d->bq[i].z1, 0, sizeof(d->bq[i].z1));
        memset(d->bq[i].z2, 0, sizeof(d->bq[i].z2));
    }
    memset(d->crush_hold, 0, sizeof(d->crush_hold));
    d->crush_count = 0;
}

// ── Effects ─────────────────────────────────────────────────────────────────

static void fx_pitch(WoofDsp *d, const WoofFx *fx, float *buf, unsigned frames) {
    if (d->pitch_buf == NULL) return;
    const unsigned ch = d->channels, len = d->pitch_len, mask = d->pitch_mask;
    const float semis = dsp_clampf(fx->p[0], -24, 24);
    const float ratio = powf(2.0f, semis / 12.0f);
    const float w = d->pitch_window;
    const float inc = (1.0f - ratio) / w;
    for (unsigned f = 0; f < frames; f++) {
        float *frame = buf + (size_t)f * ch;
        const unsigned wp = d->pitch_write;
        for (unsigned c = 0; c < ch; c++) d->pitch_buf[(size_t)c * len + wp] = frame[c];
        d->pitch_phase += inc;
        d->pitch_phase -= floorf(d->pitch_phase);
        float ph[2], gain[2];
        ph[0] = d->pitch_phase;
        ph[1] = ph[0] + 0.5f;
        if (ph[1] >= 1) ph[1] -= 1;
        for (int k = 0; k < 2; k++) gain[k] = 0.5f - 0.5f * cosf(2 * WOOF_PI * ph[k]);
        for (unsigned c = 0; c < ch; c++) {
            const float *line = d->pitch_buf + (size_t)c * len;
            float out = 0;
            for (int k = 0; k < 2; k++) {
                float rp = (float)(wp + len) - (ph[k] * w + 2.0f);
                unsigned i0 = (unsigned)rp;
                float frac = rp - (float)i0;
                float a = line[i0 & mask], b = line[(i0 + 1) & mask];
                out += gain[k] * (a + (b - a) * frac);
            }
            frame[c] = out;
        }
        d->pitch_write = (wp + 1) & mask;
    }
}

static void bq_update(WoofBiquad *q, int kind, float f0, float Q, float rate) {
    f0 = dsp_clampf(f0, 20, rate * 0.45f);
    Q = dsp_clampf(Q, 0.2f, 18);
    if (q->kind == kind && q->f0 == f0 && q->q == Q) return;
    q->kind = kind;
    q->f0 = f0;
    q->q = Q;
    float w0 = 2 * WOOF_PI * f0 / rate;
    float cs = cosf(w0), sn = sinf(w0);
    float alpha = sn / (2 * Q);
    float b0, b1, b2;
    if (kind == WOOF_FX_LOWPASS) {
        b0 = (1 - cs) / 2;
        b1 = 1 - cs;
        b2 = (1 - cs) / 2;
    } else if (kind == WOOF_FX_HIGHPASS) {
        b0 = (1 + cs) / 2;
        b1 = -(1 + cs);
        b2 = (1 + cs) / 2;
    } else {
        b0 = alpha;
        b1 = 0;
        b2 = -alpha;
    }
    float a0 = 1 + alpha;
    q->b0 = b0 / a0;
    q->b1 = b1 / a0;
    q->b2 = b2 / a0;
    q->a1 = -2 * cs / a0;
    q->a2 = (1 - alpha) / a0;
}

static void fx_biquad(WoofDsp *d, WoofBiquad *q, float *buf, unsigned frames, float makeup) {
    const unsigned ch = d->channels;
    for (unsigned f = 0; f < frames; f++) {
        float *frame = buf + (size_t)f * ch;
        for (unsigned c = 0; c < ch; c++) {
            float x = frame[c];
            float y = q->b0 * x + q->z1[c];
            q->z1[c] = q->b1 * x - q->a1 * y + q->z2[c];
            q->z2[c] = q->b2 * x - q->a2 * y;
            frame[c] = y * makeup;
        }
    }
}

static void fx_distortion(WoofDsp *d, const WoofFx *fx, float *buf, unsigned frames) {
    const float drive = dsp_clampf(fx->p[0], 0, 1);
    const float mix = dsp_clampf(fx->p[1], 0, 1);
    const float g = 1 + drive * drive * 60;
    const float out_gain = 0.75f;
    const size_t n = (size_t)frames * d->channels;
    for (size_t i = 0; i < n; i++) {
        float x = buf[i];
        buf[i] = x + (tanhf(x * g) * out_gain - x) * mix;
    }
}

static void fx_bitcrush(WoofDsp *d, const WoofFx *fx, float *buf, unsigned frames) {
    const unsigned ch = d->channels;
    const float bits = dsp_clampf(fx->p[0], 1, 16);
    const unsigned hold = (unsigned)dsp_clampf(fx->p[1], 1, 64);
    const float mix = dsp_clampf(fx->p[2], 0, 1);
    const float steps = powf(2.0f, bits - 1);
    for (unsigned f = 0; f < frames; f++) {
        float *frame = buf + (size_t)f * ch;
        if (d->crush_count == 0) {
            for (unsigned c = 0; c < ch; c++) d->crush_hold[c] = roundf(frame[c] * steps) / steps;
        }
        d->crush_count = (d->crush_count + 1) % hold;
        for (unsigned c = 0; c < ch; c++) frame[c] += (d->crush_hold[c] - frame[c]) * mix;
    }
}

static void fx_echo(WoofDsp *d, const WoofFx *fx, float *buf, unsigned frames) {
    if (d->echo_buf == NULL) return;
    const unsigned ch = d->channels, len = d->echo_len;
    unsigned delay = (unsigned)(dsp_clampf(fx->p[0], 0.02f, 1.0f) * (float)d->rate);
    if (delay >= len) delay = len - 1;
    const float fb = dsp_clampf(fx->p[1], 0, 0.95f);
    const float mix = dsp_clampf(fx->p[2], 0, 1);
    for (unsigned f = 0; f < frames; f++) {
        float *frame = buf + (size_t)f * ch;
        unsigned rp = (d->echo_pos + len - delay) % len;
        for (unsigned c = 0; c < ch; c++) {
            float *line = d->echo_buf + (size_t)c * len;
            float wet = line[rp];
            line[d->echo_pos] = frame[c] + wet * fb;
            frame[c] += wet * mix;
        }
        d->echo_pos = (d->echo_pos + 1) % len;
    }
}

static void fx_reverb(WoofDsp *d, const WoofFx *fx, float *buf, unsigned frames) {
    if (d->reverb_mem == NULL) return;
    const unsigned ch = d->channels;
    const float room = dsp_clampf(fx->p[0], 0, 1);
    const float damp1 = dsp_clampf(fx->p[1], 0, 1) * 0.4f;
    const float damp2 = 1 - damp1;
    const float mix = dsp_clampf(fx->p[2], 0, 1);
    const float feedback = room * 0.28f + 0.7f;
    const float dry = 1 - mix * 0.5f;
    for (unsigned f = 0; f < frames; f++) {
        float *frame = buf + (size_t)f * ch;
        float input = 0;
        for (unsigned c = 0; c < ch; c++) input += frame[c];
        input *= 0.015f * 2.0f / (float)ch;
        for (unsigned c = 0; c < ch; c++) {
            float out = 0;
            for (int j = 0; j < 8; j++) {
                WoofComb *cb = &d->comb[c][j];
                float y = cb->buf[cb->pos];
                cb->store = y * damp2 + cb->store * damp1;
                cb->buf[cb->pos] = input + cb->store * feedback;
                if (++cb->pos >= cb->len) cb->pos = 0;
                out += y;
            }
            for (int j = 0; j < 4; j++) {
                WoofAllpass *ap = &d->ap[c][j];
                float b = ap->buf[ap->pos];
                ap->buf[ap->pos] = out + b * 0.5f;
                out = b - out;
                if (++ap->pos >= ap->len) ap->pos = 0;
            }
            frame[c] = frame[c] * dry + out * 3.0f * mix;
        }
    }
}

static void fx_chorus(WoofDsp *d, const WoofFx *fx, float *buf, unsigned frames) {
    if (d->chorus_buf == NULL) return;
    const unsigned ch = d->channels, len = d->chorus_len;
    const float rate = dsp_clampf(fx->p[0], 0.05f, 8);
    const float depth = dsp_clampf(fx->p[1], 0, 1);
    const float mix = dsp_clampf(fx->p[2], 0, 1);
    const float base = 0.012f * (float)d->rate;
    const float swing = 0.018f * (float)d->rate * depth;
    const float inc = rate / (float)d->rate;
    for (unsigned f = 0; f < frames; f++) {
        float *frame = buf + (size_t)f * ch;
        d->chorus_phase += inc;
        if (d->chorus_phase >= 1) d->chorus_phase -= 1;
        for (unsigned c = 0; c < ch; c++) {
            float *line = d->chorus_buf + (size_t)c * len;
            line[d->chorus_pos] = frame[c];
            float lfo = 0.5f + 0.5f * sinf(2 * WOOF_PI * (d->chorus_phase + (float)c * 0.25f));
            float delay = base + swing * lfo;
            float rp = (float)(d->chorus_pos + len) - delay;
            unsigned i0 = (unsigned)rp;
            float frac = rp - (float)i0;
            float a = line[i0 % len], b = line[(i0 + 1) % len];
            float wet = a + (b - a) * frac;
            frame[c] = frame[c] * (1 - mix * 0.5f) + wet * mix * 0.7f;
        }
        d->chorus_pos = (d->chorus_pos + 1) % len;
    }
}

static void fx_tremolo(WoofDsp *d, const WoofFx *fx, float *buf, unsigned frames) {
    const unsigned ch = d->channels;
    const float inc = dsp_clampf(fx->p[0], 0.1f, 30) / (float)d->rate;
    const float depth = dsp_clampf(fx->p[1], 0, 1);
    for (unsigned f = 0; f < frames; f++) {
        d->trem_phase += inc;
        if (d->trem_phase >= 1) d->trem_phase -= 1;
        float g = 1 - depth * (0.5f - 0.5f * cosf(2 * WOOF_PI * d->trem_phase));
        for (unsigned c = 0; c < ch; c++) buf[(size_t)f * ch + c] *= g;
    }
}

static void fx_robot(WoofDsp *d, const WoofFx *fx, float *buf, unsigned frames) {
    const unsigned ch = d->channels;
    const float inc = dsp_clampf(fx->p[0], 5, 2000) / (float)d->rate;
    const float mix = dsp_clampf(fx->p[1], 0, 1);
    for (unsigned f = 0; f < frames; f++) {
        d->robot_phase += inc;
        if (d->robot_phase >= 1) d->robot_phase -= 1;
        float m = sinf(2 * WOOF_PI * d->robot_phase);
        for (unsigned c = 0; c < ch; c++) {
            float x = buf[(size_t)f * ch + c];
            buf[(size_t)f * ch + c] = x + (x * m * 1.4f - x) * mix;
        }
    }
}

static void fx_gain(WoofDsp *d, const WoofFx *fx, float *buf, unsigned frames) {
    const float g = powf(10.0f, dsp_clampf(fx->p[0], -30, 30) / 20.0f);
    const size_t n = (size_t)frames * d->channels;
    for (size_t i = 0; i < n; i++) buf[i] *= g;
}

static void dsp_process(WoofDsp *d, const WoofFx *chain, int count, float *buf, unsigned frames) {
    if (count > WOOF_FX_MAX) count = WOOF_FX_MAX;
    for (int i = 0; i < count; i++) {
        const WoofFx *fx = &chain[i];
        switch (fx->type) {
        case WOOF_FX_PITCH: fx_pitch(d, fx, buf, frames); break;
        case WOOF_FX_LOWPASS:
            bq_update(&d->bq[0], WOOF_FX_LOWPASS, fx->p[0], fx->p[1], (float)d->rate);
            fx_biquad(d, &d->bq[0], buf, frames, 1);
            break;
        case WOOF_FX_HIGHPASS:
            bq_update(&d->bq[1], WOOF_FX_HIGHPASS, fx->p[0], fx->p[1], (float)d->rate);
            fx_biquad(d, &d->bq[1], buf, frames, 1);
            break;
        case WOOF_FX_BANDPASS:
            bq_update(&d->bq[2], WOOF_FX_BANDPASS, fx->p[0], fx->p[1], (float)d->rate);
            // A narrow band loses a lot of level; give some of it back
            fx_biquad(d, &d->bq[2], buf, frames, 1.0f + dsp_clampf(fx->p[1], 0.2f, 18) * 0.35f);
            break;
        case WOOF_FX_DISTORTION: fx_distortion(d, fx, buf, frames); break;
        case WOOF_FX_BITCRUSH: fx_bitcrush(d, fx, buf, frames); break;
        case WOOF_FX_ECHO: fx_echo(d, fx, buf, frames); break;
        case WOOF_FX_REVERB: fx_reverb(d, fx, buf, frames); break;
        case WOOF_FX_CHORUS: fx_chorus(d, fx, buf, frames); break;
        case WOOF_FX_TREMOLO: fx_tremolo(d, fx, buf, frames); break;
        case WOOF_FX_ROBOT: fx_robot(d, fx, buf, frames); break;
        case WOOF_FX_GAIN: fx_gain(d, fx, buf, frames); break;
        default: break;
        }
    }
    // A runaway filter must never reach the speakers
    const size_t n = (size_t)frames * d->channels;
    for (size_t i = 0; i < n; i++) {
        if (!isfinite(buf[i])) {
            memset(buf, 0, n * sizeof(float));
            dsp_reset(d);
            for (int k = 0; k < 3; k++) d->bq[k].kind = -1;
            return;
        }
    }
}

#endif
