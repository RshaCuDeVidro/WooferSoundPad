//! Background loudness analysis for library-wide volume normalization.
//! Files are measured one at a time on a worker thread; results are copied
//! into each Sound (and saved), so every file is measured once.

const std = @import("std");
const sys = @import("sys.zig");
const audio = @import("audio.zig");
const library = @import("library.zig");

const gpa = sys.gpa;

const State = enum(u8) { pending, loading, ready, failed };

const Entry = struct {
    state: std.atomic.Value(State) = .init(.pending),
    path: [:0]u8,
    loud: f32 = 0,
    peak: f32 = 0,
};

var entries: std.StringHashMapUnmanaged(*Entry) = .empty;
var busy: std.atomic.Value(bool) = .init(false);

pub const Result = struct { loud: f32, peak: f32 };

/// The measurement for `path` once it is done. Starts one if the worker is free.
/// `failed` is set when the file can't be measured (silence, unreadable...).
pub fn get(path: []const u8, failed: *bool) ?Result {
    failed.* = false;
    const e = entries.get(path) orelse blk: {
        const ne = gpa.create(Entry) catch return null;
        ne.* = .{ .path = gpa.dupeSentinel(u8, path, 0) catch {
            gpa.destroy(ne);
            return null;
        } };
        entries.put(gpa, ne.path, ne) catch {
            gpa.free(ne.path);
            gpa.destroy(ne);
            return null;
        };
        break :blk ne;
    };
    switch (e.state.load(.acquire)) {
        .ready => return .{ .loud = e.loud, .peak = e.peak },
        .failed => {
            failed.* = true;
            return null;
        },
        .loading => return null,
        .pending => {
            if (busy.swap(true, .acq_rel)) return null;
            e.state.store(.loading, .release);
            const t = std.Thread.spawn(.{}, work, .{e}) catch {
                e.state.store(.failed, .release);
                busy.store(false, .release);
                return null;
            };
            t.detach();
            return null;
        },
    }
}

fn work(e: *Entry) void {
    defer busy.store(false, .release);
    if (audio.loudness(e.path)) |r| {
        e.loud = r.loud;
        e.peak = r.peak;
        e.state.store(.ready, .release);
    } else e.state.store(.failed, .release);
}

/// Call after a file was rewritten
pub fn invalidate(path: []const u8) void {
    if (entries.get(path)) |e| {
        if (e.state.load(.acquire) != .loading) e.state.store(.pending, .release);
    }
}

/// Gain (linear) that brings a sound to `target_db`, never pushing its peak
/// past -1 dBFS and never more than ±15 dB
pub fn gainFor(s: *const library.Sound, target_db: f32) f32 {
    if (s.loudness >= 0) return 1; // not measured yet
    var g = target_db - s.loudness;
    g = @min(g, -1 - s.peak_db);
    g = std.math.clamp(g, -15, 15);
    return std.math.pow(f32, 10, g / 20);
}
