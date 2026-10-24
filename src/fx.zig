//! Live effect chains: what each effect is, its parameters, and the built-in
//! presets. The DSP itself lives in src/c/woof_dsp.h.

const std = @import("std");
const c = @import("c");
const icons = @import("icons.zig");

pub const max = c.WOOF_FX_MAX;

pub const Kind = enum(u8) {
    pitch,
    lowpass,
    highpass,
    bandpass,
    distortion,
    bitcrush,
    echo,
    reverb,
    chorus,
    tremolo,
    robot,
    gain,

    pub fn cType(k: Kind) c_int {
        return switch (k) {
            .pitch => c.WOOF_FX_PITCH,
            .lowpass => c.WOOF_FX_LOWPASS,
            .highpass => c.WOOF_FX_HIGHPASS,
            .bandpass => c.WOOF_FX_BANDPASS,
            .distortion => c.WOOF_FX_DISTORTION,
            .bitcrush => c.WOOF_FX_BITCRUSH,
            .echo => c.WOOF_FX_ECHO,
            .reverb => c.WOOF_FX_REVERB,
            .chorus => c.WOOF_FX_CHORUS,
            .tremolo => c.WOOF_FX_TREMOLO,
            .robot => c.WOOF_FX_ROBOT,
            .gain => c.WOOF_FX_GAIN,
        };
    }

    pub fn icon(k: Kind) u21 {
        return switch (k) {
            .pitch => icons.arrow_up_down,
            .lowpass => icons.trending_down,
            .highpass => icons.trending_up,
            .bandpass => icons.radio,
            .distortion => icons.flame,
            .bitcrush => icons.gamepad_2,
            .echo => icons.repeat,
            .reverb => icons.mountain_snow,
            .chorus => icons.layers,
            .tremolo => icons.activity,
            .robot => icons.bot,
            .gain => icons.volume_2,
        };
    }
};

pub const all_kinds = [_]Kind{ .pitch, .lowpass, .highpass, .bandpass, .distortion, .bitcrush, .echo, .reverb, .chorus, .tremolo, .robot, .gain };

pub const Unit = enum { semitones, hz, seconds, percent, db, bits, times };

pub const Param = struct {
    /// Index into Strings.fx_params
    label: ParamLabel,
    min: f32,
    max: f32,
    default: f32,
    unit: Unit,
    /// Sliders move on a log scale (frequencies)
    log: bool = false,
    step: f32 = 0,
};

pub const ParamLabel = enum { semitones, cutoff, resonance, center, width, drive, mix, bits, hold, time, feedback, room, damping, rate, depth, frequency, gain };

pub fn params(k: Kind) []const Param {
    return switch (k) {
        .pitch => &.{.{ .label = .semitones, .min = -12, .max = 12, .default = -5, .unit = .semitones, .step = 0.5 }},
        .lowpass => &.{
            .{ .label = .cutoff, .min = 80, .max = 18000, .default = 900, .unit = .hz, .log = true },
            .{ .label = .resonance, .min = 0.5, .max = 10, .default = 0.9, .unit = .times, .step = 0.1 },
        },
        .highpass => &.{
            .{ .label = .cutoff, .min = 40, .max = 8000, .default = 700, .unit = .hz, .log = true },
            .{ .label = .resonance, .min = 0.5, .max = 10, .default = 0.9, .unit = .times, .step = 0.1 },
        },
        .bandpass => &.{
            .{ .label = .center, .min = 200, .max = 6000, .default = 1600, .unit = .hz, .log = true },
            .{ .label = .width, .min = 0.4, .max = 6, .default = 1.3, .unit = .times, .step = 0.1 },
        },
        .distortion => &.{
            .{ .label = .drive, .min = 0, .max = 1, .default = 0.55, .unit = .percent },
            .{ .label = .mix, .min = 0, .max = 1, .default = 1, .unit = .percent },
        },
        .bitcrush => &.{
            .{ .label = .bits, .min = 2, .max = 16, .default = 6, .unit = .bits, .step = 1 },
            .{ .label = .hold, .min = 1, .max = 32, .default = 6, .unit = .times, .step = 1 },
            .{ .label = .mix, .min = 0, .max = 1, .default = 1, .unit = .percent },
        },
        .echo => &.{
            .{ .label = .time, .min = 0.03, .max = 1, .default = 0.28, .unit = .seconds, .step = 0.01 },
            .{ .label = .feedback, .min = 0, .max = 0.9, .default = 0.45, .unit = .percent },
            .{ .label = .mix, .min = 0, .max = 1, .default = 0.5, .unit = .percent },
        },
        .reverb => &.{
            .{ .label = .room, .min = 0, .max = 1, .default = 0.75, .unit = .percent },
            .{ .label = .damping, .min = 0, .max = 1, .default = 0.4, .unit = .percent },
            .{ .label = .mix, .min = 0, .max = 1, .default = 0.4, .unit = .percent },
        },
        .chorus => &.{
            .{ .label = .rate, .min = 0.1, .max = 6, .default = 1.2, .unit = .hz, .step = 0.1 },
            .{ .label = .depth, .min = 0, .max = 1, .default = 0.6, .unit = .percent },
            .{ .label = .mix, .min = 0, .max = 1, .default = 0.6, .unit = .percent },
        },
        .tremolo => &.{
            .{ .label = .rate, .min = 0.5, .max = 20, .default = 6, .unit = .hz, .step = 0.1 },
            .{ .label = .depth, .min = 0, .max = 1, .default = 0.7, .unit = .percent },
        },
        .robot => &.{
            .{ .label = .frequency, .min = 10, .max = 800, .default = 70, .unit = .hz, .log = true },
            .{ .label = .mix, .min = 0, .max = 1, .default = 1, .unit = .percent },
        },
        .gain => &.{.{ .label = .gain, .min = -24, .max = 24, .default = 6, .unit = .db, .step = 0.5 }},
    };
}

pub const Effect = struct {
    kind: Kind,
    on: bool = true,
    p: [4]f32 = .{ 0, 0, 0, 0 },
    /// Automated parameter (-1 = none): glides from p[auto] to auto_to over the sound
    auto: i8 = -1,
    auto_to: f32 = 0,

    pub fn init(k: Kind) Effect {
        var e: Effect = .{ .kind = k };
        for (params(k), 0..) |spec, i| e.p[i] = spec.default;
        return e;
    }

    /// Keeps parameters in range (files can be edited by hand)
    pub fn sanitized(e: Effect) Effect {
        var out = e;
        const specs = params(e.kind);
        for (specs, 0..) |spec, i| {
            out.p[i] = if (std.math.isFinite(e.p[i])) std.math.clamp(e.p[i], spec.min, spec.max) else spec.default;
        }
        if (out.auto < 0 or out.auto >= specs.len) {
            out.auto = -1;
        } else {
            const spec = specs[@intCast(out.auto)];
            out.auto_to = if (std.math.isFinite(e.auto_to)) std.math.clamp(e.auto_to, spec.min, spec.max) else spec.default;
        }
        return out;
    }
};

/// An effect as written to JSON. The kind is plain text so a file with an
/// effect this version doesn't know still loads (that effect is skipped).
pub const Stored = struct {
    kind: []const u8,
    on: bool = true,
    p: [4]f32 = .{ 0, 0, 0, 0 },
    auto: i8 = -1,
    auto_to: f32 = 0,

    pub fn from(e: *const Effect) Stored {
        return .{ .kind = @tagName(e.kind), .on = e.on, .p = e.p, .auto = e.auto, .auto_to = e.auto_to };
    }

    pub fn effect(st: Stored) ?Effect {
        const k = std.meta.stringToEnum(Kind, st.kind) orelse return null;
        return .{ .kind = k, .on = st.on, .p = st.p, .auto = st.auto, .auto_to = st.auto_to };
    }
};

pub const Chain = struct {
    items: [max]Effect = undefined,
    len: usize = 0,

    pub fn slice(ch: *const Chain) []const Effect {
        return ch.items[0..ch.len];
    }

    pub fn has(ch: *const Chain, k: Kind) bool {
        for (ch.slice()) |e| {
            if (e.kind == k) return true;
        }
        return false;
    }

    pub fn active(ch: *const Chain) usize {
        var n: usize = 0;
        for (ch.slice()) |e| {
            if (e.on) n += 1;
        }
        return n;
    }

    pub fn add(ch: *Chain, e: Effect) void {
        if (ch.len >= max or ch.has(e.kind)) return;
        ch.items[ch.len] = e.sanitized();
        ch.len += 1;
    }

    pub fn remove(ch: *Chain, i: usize) void {
        if (i >= ch.len) return;
        std.mem.copyForwards(Effect, ch.items[i .. ch.len - 1], ch.items[i + 1 .. ch.len]);
        ch.len -= 1;
    }

    pub fn swap(ch: *Chain, i: usize, j: usize) void {
        if (i >= ch.len or j >= ch.len) return;
        std.mem.swap(Effect, &ch.items[i], &ch.items[j]);
    }

    pub fn fromSlice(effects: []const Effect) Chain {
        var ch: Chain = .{};
        for (effects) |e| ch.add(e);
        return ch;
    }

    pub fn fromStored(stored: []const Stored) Chain {
        var ch: Chain = .{};
        for (stored) |st| {
            if (st.effect()) |e| ch.add(e);
        }
        return ch;
    }

    /// For saving; points into `buf`
    pub fn toStored(ch: *const Chain, buf: *[max]Stored) []const Stored {
        for (ch.slice(), 0..) |*e, i| buf[i] = Stored.from(e);
        return buf[0..ch.len];
    }

    pub fn eql(a: *const Chain, b: *const Chain) bool {
        if (a.len != b.len) return false;
        for (a.slice(), b.slice()) |x, y| {
            if (x.kind != y.kind or x.on != y.on or !std.mem.eql(f32, &x.p, &y.p) or x.auto != y.auto or (x.auto >= 0 and x.auto_to != y.auto_to)) return false;
        }
        return true;
    }

    /// Enabled effects in the engine's format
    pub fn toC(ch: *const Chain, out: *[max]c.WoofFx) c_int {
        var n: usize = 0;
        for (ch.slice()) |e| {
            if (!e.on) continue;
            out[n] = .{ .type = e.kind.cType(), .p = e.p, .auto_param = e.auto, .auto_to = e.auto_to };
            n += 1;
        }
        return @intCast(n);
    }
};

// ── Presets ─────────────────────────────────────────────────────────────────

pub const Builtin = struct {
    /// Index into Strings.fx_preset_names
    name: usize,
    icon: u21,
    effects: []const Effect,
};

fn fx(k: Kind, p: [4]f32) Effect {
    return .{ .kind = k, .p = p };
}

/// Effect whose parameter `param` glides to `to` over the sound
fn glide(k: Kind, p: [4]f32, param: i8, to: f32) Effect {
    return .{ .kind = k, .p = p, .auto = param, .auto_to = to };
}

pub const builtins = [_]Builtin{
    .{ .name = 0, .icon = icons.skull, .effects = &.{
        fx(.pitch, .{ -6, 0, 0, 0 }),
        fx(.distortion, .{ 0.35, 0.55, 0, 0 }),
        fx(.reverb, .{ 0.8, 0.35, 0.35, 0 }),
    } },
    .{ .name = 1, .icon = icons.rabbit, .effects = &.{
        fx(.pitch, .{ 8, 0, 0, 0 }),
    } },
    .{ .name = 2, .icon = icons.bot, .effects = &.{
        fx(.robot, .{ 55, 1, 0, 0 }),
        fx(.bitcrush, .{ 8, 3, 0.7, 0 }),
        fx(.echo, .{ 0.04, 0.3, 0.3, 0 }),
    } },
    .{ .name = 3, .icon = icons.radio, .effects = &.{
        fx(.bandpass, .{ 1700, 1.4, 0, 0 }),
        fx(.distortion, .{ 0.25, 0.5, 0, 0 }),
    } },
    .{ .name = 4, .icon = icons.mountain_snow, .effects = &.{
        fx(.reverb, .{ 1, 0.15, 0.6, 0 }),
        fx(.echo, .{ 0.35, 0.35, 0.3, 0 }),
    } },
    .{ .name = 5, .icon = icons.waves, .effects = &.{
        fx(.lowpass, .{ 450, 1.2, 0, 0 }),
        fx(.chorus, .{ 0.6, 0.8, 0.7, 0 }),
    } },
    .{ .name = 6, .icon = icons.flame, .effects = &.{
        fx(.gain, .{ 14, 0, 0, 0 }),
        fx(.distortion, .{ 0.9, 1, 0, 0 }),
    } },
    .{ .name = 7, .icon = icons.ghost, .effects = &.{
        fx(.pitch, .{ 3, 0, 0, 0 }),
        fx(.chorus, .{ 0.4, 1, 0.8, 0 }),
        fx(.reverb, .{ 0.9, 0.6, 0.55, 0 }),
    } },
    .{ .name = 8, .icon = icons.disc_3, .effects = &.{
        fx(.bitcrush, .{ 7, 4, 1, 0 }),
        fx(.lowpass, .{ 3500, 0.8, 0, 0 }),
    } },
    .{ .name = 9, .icon = icons.repeat, .effects = &.{
        fx(.echo, .{ 0.22, 0.6, 0.55, 0 }),
    } },
    .{ .name = 10, .icon = icons.power, .effects = &.{
        glide(.pitch, .{ 0, 0, 0, 0 }, 0, -12),
        glide(.lowpass, .{ 18000, 0.9, 0, 0 }, 0, 300),
    } },
    .{ .name = 11, .icon = icons.rocket, .effects = &.{
        glide(.pitch, .{ -2, 0, 0, 0 }, 0, 9),
        glide(.highpass, .{ 40, 1.5, 0, 0 }, 0, 1500),
        fx(.reverb, .{ 0.6, 0.4, 0.25, 0 }),
    } },
};

/// User preset as stored in config.json
pub const UserPreset = struct {
    name: []const u8,
    fx: []const Stored = &.{},
};

// ── Display ─────────────────────────────────────────────────────────────────

/// "−5 st", "900 Hz", "0.28 s", "45%", "+6 dB"
pub fn formatValue(buf: []u8, spec: Param, v: f32) []const u8 {
    return switch (spec.unit) {
        .semitones => std.fmt.bufPrint(buf, "{s}{d:.1} st", .{ if (v > 0) "+" else "", v }) catch "",
        .hz => if (v >= 1000)
            std.fmt.bufPrint(buf, "{d:.1} kHz", .{v / 1000}) catch ""
        else
            std.fmt.bufPrint(buf, "{d:.0} Hz", .{v}) catch "",
        .seconds => std.fmt.bufPrint(buf, "{d:.0} ms", .{v * 1000}) catch "",
        .percent => std.fmt.bufPrint(buf, "{d:.0}%", .{v * 100}) catch "",
        .db => std.fmt.bufPrint(buf, "{s}{d:.1} dB", .{ if (v > 0) "+" else "", v }) catch "",
        .bits => std.fmt.bufPrint(buf, "{d:.0} bit", .{v}) catch "",
        .times => std.fmt.bufPrint(buf, "{d:.1}×", .{v}) catch "",
    };
}

/// Slider position (0..1) for a value, honoring log scales
pub fn toSlider(spec: Param, v: f32) f32 {
    if (spec.log) return std.math.clamp(@log(v / spec.min) / @log(spec.max / spec.min), 0, 1);
    return std.math.clamp((v - spec.min) / (spec.max - spec.min), 0, 1);
}

pub fn fromSlider(spec: Param, t: f32) f32 {
    var v = if (spec.log) spec.min * std.math.pow(f32, spec.max / spec.min, t) else spec.min + t * (spec.max - spec.min);
    if (spec.step > 0) v = @round(v / spec.step) * spec.step;
    return std.math.clamp(v, spec.min, spec.max);
}

test "chain keeps one effect per kind" {
    var ch: Chain = .{};
    ch.add(Effect.init(.pitch));
    ch.add(Effect.init(.pitch));
    ch.add(Effect.init(.reverb));
    try std.testing.expectEqual(@as(usize, 2), ch.len);
    ch.swap(0, 1);
    try std.testing.expectEqual(Kind.reverb, ch.items[0].kind);
    ch.remove(0);
    try std.testing.expectEqual(Kind.pitch, ch.items[0].kind);
}

test "log slider round trip" {
    const spec = params(.lowpass)[0];
    const v = fromSlider(spec, toSlider(spec, 900));
    try std.testing.expect(@abs(v - 900) < 1);
}
