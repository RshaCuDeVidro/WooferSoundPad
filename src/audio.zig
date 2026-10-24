//! Zig side of the audio engine (src/c/woof_audio.c).

const std = @import("std");
const c = @import("c");
const config = @import("config.zig");
const vmic = @import("vmic.zig");
const fx = @import("fx.zig");

pub const Output = enum(c_int) { monitor = c.WOOF_OUT_MONITOR, mic = c.WOOF_OUT_MIC };

pub var ok = false;
/// Device names for dropdowns: [0] is "System default" / "Off", then devices
pub var device_names: std.ArrayList([]const u8) = .empty;

pub fn init() void {
    ok = c.woof_init() == 0;
    if (!ok) std.log.err("audio engine failed to start", .{});
    refreshDevices();
}

pub fn deinit() void {
    c.woof_deinit();
    device_names.deinit(std.heap.c_allocator);
}

pub fn refreshDevices() void {
    _ = c.woof_refresh_devices();
    device_names.clearRetainingCapacity();
    const n = c.woof_device_count();
    var i: c_int = 0;
    while (i < n) : (i += 1) {
        device_names.append(std.heap.c_allocator, std.mem.span(c.woof_device_name(i))) catch {};
    }
}

pub fn deviceIndex(name: []const u8) ?c_int {
    if (name.len == 0) return null;
    for (device_names.items, 0..) |d, i| {
        if (std.mem.eql(u8, d, name)) return @intCast(i);
    }
    return null;
}

/// First device that looks like a virtual microphone target
pub fn findVirtualDevice() ?c_int {
    for (device_names.items, 0..) |d, i| {
        if (vmic.isVirtualOutput(d)) return @intCast(i);
    }
    return null;
}

pub fn setOutput(out: Output, device_name: []const u8) bool {
    const idx: c_int = deviceIndex(device_name) orelse -1;
    if (out == .mic and idx < 0) {
        _ = c.woof_set_output(@backingInt(out), -1);
        return device_name.len == 0;
    }
    return c.woof_set_output(@backingInt(out), idx) == 0;
}

pub fn outputActive(out: Output) bool {
    return c.woof_output_active(@backingInt(out)) != 0;
}

pub fn applyVolumes(cfg: *const config.Config) void {
    c.woof_set_output_volume(c.WOOF_OUT_MONITOR, cfg.master_volume * cfg.monitor_volume);
    c.woof_set_output_volume(c.WOOF_OUT_MIC, cfg.master_volume * cfg.mic_volume);
}

pub fn load(path: [:0]const u8) c_int {
    return c.woof_load(path.ptr);
}

pub fn unload(id: c_int) void {
    if (id >= 0) c.woof_unload(id);
}

pub fn play(id: c_int, volume: f32, mode: config.PlayMode) void {
    const m: c_int = switch (mode) {
        .restart => c.WOOF_MODE_RESTART,
        .overlap => c.WOOF_MODE_OVERLAP,
        .toggle => c.WOOF_MODE_TOGGLE,
    };
    c.woof_play(id, volume, m);
}

/// Playback settings stored per sound (see library.Sound)
pub const Params = struct {
    trim_start: f32 = 0,
    trim_end: f32 = 0, // 0 = until the end
    loop: bool = false,
    speed: f32 = 1,
    fade_in: f32 = 0,
    fade_out: f32 = 0,
};

pub fn setParams(id: c_int, p: Params) void {
    if (id < 0) return;
    c.woof_set_params(id, p.trim_start, p.trim_end, @intFromBool(p.loop), p.speed, p.fade_in, p.fade_out);
}

/// Length of the whole file in seconds (the trim is ignored)
pub fn fullLength(id: c_int) f32 {
    if (id < 0) return 0;
    return c.woof_full_length(id);
}

pub fn pause(id: c_int) void {
    if (id >= 0) c.woof_pause(id);
}

pub fn @"resume"(id: c_int) void {
    if (id >= 0) c.woof_resume(id);
}

pub fn isPaused(id: c_int) bool {
    return id >= 0 and c.woof_is_paused(id) != 0;
}

pub fn pauseAll() void {
    c.woof_pause_all();
}

pub fn resumeAll() void {
    c.woof_resume_all();
}

pub fn pausedCount() usize {
    return @intCast(c.woof_paused_count());
}

/// Once per frame
pub fn update() void {
    c.woof_update();
}

/// Seconds into the current play, relative to the trim start
pub fn cursor(id: c_int) f32 {
    if (id < 0) return 0;
    return c.woof_cursor(id);
}

/// Peak envelope of a file; safe to call from any thread
pub fn waveform(path: [:0]const u8, peaks: []f32, duration: *f32) bool {
    return c.woof_waveform(path.ptr, peaks.ptr, @intCast(peaks.len), duration) > 0;
}

pub fn stop(id: c_int) void {
    c.woof_stop(id);
}

/// Stops everything, including paused sounds and the preview
pub fn stopAll() void {
    c.woof_stop_all();
}

pub fn isPlaying(id: c_int) bool {
    return id >= 0 and c.woof_is_playing(id) != 0;
}

pub fn progress(id: c_int) f32 {
    if (id < 0) return 0;
    const len = c.woof_length(id);
    if (len <= 0) return 0;
    return std.math.clamp(c.woof_cursor(id) / len, 0, 1);
}

/// Seconds of audio between the trim points (before speed is applied)
pub fn length(id: c_int) f32 {
    if (id < 0) return 0;
    return c.woof_length(id);
}

pub fn playingCount() usize {
    return @intCast(c.woof_playing_count());
}

pub fn previewPlay(path: [:0]const u8, volume: f32) bool {
    return c.woof_preview_play(path.ptr, volume) == 0;
}

pub fn previewStop() void {
    c.woof_preview_stop();
}

pub fn previewPlaying() bool {
    return c.woof_preview_is_playing() != 0;
}

pub fn previewProgress() f32 {
    const len = c.woof_preview_length();
    if (len <= 0) return 0;
    return std.math.clamp(c.woof_preview_cursor() / len, 0, 1);
}

// ── Live effects ────────────────────────────────────────────────────────────

pub fn setFx(id: c_int, chain: *const fx.Chain) void {
    if (id < 0) return;
    var buf: [fx.max]c.WoofFx = undefined;
    const n = chain.toC(&buf);
    c.woof_set_fx(id, &buf, n);
}

// ── Mixer ───────────────────────────────────────────────────────────────────

pub fn setLiveVolume(id: c_int, v: f32) void {
    if (id >= 0) c.woof_set_live_volume(id, v);
}

pub fn liveVolume(id: c_int) f32 {
    return if (id >= 0) c.woof_live_volume(id) else 1;
}

pub fn setMuted(id: c_int, muted: bool) void {
    if (id >= 0) c.woof_set_muted(id, @intFromBool(muted));
}

pub fn isMuted(id: c_int) bool {
    return id >= 0 and c.woof_is_muted(id) != 0;
}

pub fn fadeStop(id: c_int, seconds: f32) void {
    if (id >= 0) c.woof_fade_stop(id, seconds);
}

pub fn isFading(id: c_int) bool {
    return id >= 0 and c.woof_is_fading(id) != 0;
}

/// Output peak since the previous call; call once per frame per sound
pub fn level(id: c_int) f32 {
    return if (id >= 0) c.woof_level(id) else 0;
}

pub fn seek(id: c_int, seconds: f32) void {
    if (id >= 0) c.woof_seek(id, seconds);
}

pub fn playFrom(id: c_int, volume: f32, seconds: f32) void {
    if (id >= 0) c.woof_play_from(id, volume, seconds);
}

// ── Recorder ────────────────────────────────────────────────────────────────

pub const rec_system: c_int = c.WOOF_REC_SYSTEM;
pub const rec_default_mic: c_int = c.WOOF_REC_DEFAULT_MIC;
pub const rec_max_seconds: f32 = c.WOOF_REC_MAX_SECONDS;
pub const rec_peaks_per_second: f32 = c.WOOF_REC_PEAKS_PER_SECOND;

pub fn captureNames(out: [][]const u8) [][]const u8 {
    const n: usize = @intCast(@max(0, c.woof_capture_count()));
    const count = @min(n, out.len);
    for (0..count) |i| out[i] = std.mem.span(c.woof_capture_name(@intCast(i)));
    return out[0..count];
}

pub fn recSystemSupported() bool {
    return c.woof_rec_system_supported() != 0;
}

pub fn recStart(source: c_int) bool {
    return c.woof_rec_start(source) == 0;
}

pub fn recStop() void {
    c.woof_rec_stop();
}

pub fn recActive() bool {
    return c.woof_rec_active() != 0;
}

pub fn recSeconds() f32 {
    return c.woof_rec_seconds();
}

pub fn recLevel() f32 {
    return c.woof_rec_level();
}

pub fn recPeaks() []const f32 {
    const n: usize = @intCast(@max(0, c.woof_rec_peak_count()));
    return c.woof_rec_peaks()[0..n];
}

pub fn recSave(path: [:0]const u8, start: f32, end: f32) bool {
    return c.woof_rec_save(path.ptr, start, end) == 0;
}

pub fn recDiscard() void {
    c.woof_rec_discard();
}

/// Loudness (dB) and peak (dBFS) of a file; slow, call from a worker thread
pub fn loudness(path: [:0]const u8) ?struct { loud: f32, peak: f32 } {
    var l: f32 = 0;
    var p: f32 = 0;
    if (c.woof_loudness(path.ptr, &l, &p) != 0) return null;
    return .{ .loud = l, .peak = p };
}
