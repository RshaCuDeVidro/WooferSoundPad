//! Waveform peaks for pads and the sound editor. Files are decoded on
//! background threads and the peaks stay cached in memory.

const std = @import("std");
const sys = @import("sys.zig");
const audio = @import("audio.zig");

const gpa = sys.gpa;

const State = enum(u8) { pending, loading, ready, failed };

pub const Wave = struct {
    state: std.atomic.Value(State) = .init(.pending),
    /// Set when the file changed while it was being decoded
    stale: std.atomic.Value(bool) = .init(false),
    key: []u8,
    path: [:0]u8,
    peaks: []f32,
    duration: f32 = 0,
};

var waves: std.StringHashMapUnmanaged(*Wave) = .empty;
var loading: std.atomic.Value(u32) = .init(0);
const max_parallel = 2;

/// Peaks of `path` resampled to `bins` values (0..1), once decoded
pub fn get(path: []const u8, bins: usize) ?*const Wave {
    var key_buf: [1100]u8 = undefined;
    const key = std.fmt.bufPrint(&key_buf, "{d}|{s}", .{ bins, path }) catch return null;
    const w = waves.get(key) orelse blk: {
        const nw = create(key, path, bins) catch return null;
        waves.put(gpa, nw.key, nw) catch {
            destroy(nw);
            return null;
        };
        break :blk nw;
    };
    switch (w.state.load(.acquire)) {
        .ready => {
            if (w.stale.swap(false, .acq_rel)) w.state.store(.pending, .release);
            return w;
        },
        .pending => {
            if (loading.load(.acquire) < max_parallel) {
                w.state.store(.loading, .release);
                _ = loading.fetchAdd(1, .acq_rel);
                const thread = std.Thread.spawn(.{}, decode, .{w}) catch {
                    w.state.store(.failed, .release);
                    _ = loading.fetchSub(1, .acq_rel);
                    return null;
                };
                thread.detach();
            }
            return null;
        },
        .failed => {
            if (w.stale.swap(false, .acq_rel)) w.state.store(.pending, .release);
            return null;
        },
        .loading => return null,
    }
}

/// Call after a file was rewritten (trim applied, normalized...)
pub fn invalidate(path: []const u8) void {
    var it = waves.valueIterator();
    while (it.next()) |w| {
        if (std.mem.eql(u8, w.*.path, path)) w.*.stale.store(true, .release);
    }
}

fn create(key: []const u8, path: []const u8, bins: usize) !*Wave {
    const w = try gpa.create(Wave);
    errdefer gpa.destroy(w);
    const k = try gpa.dupe(u8, key);
    errdefer gpa.free(k);
    const p = try gpa.dupeSentinel(u8, path, 0);
    errdefer gpa.free(p);
    const peaks = try gpa.alloc(f32, bins);
    @memset(peaks, 0);
    w.* = .{ .key = k, .path = p, .peaks = peaks };
    return w;
}

fn destroy(w: *Wave) void {
    gpa.free(w.key);
    gpa.free(w.path);
    gpa.free(w.peaks);
    gpa.destroy(w);
}

fn decode(w: *Wave) void {
    defer _ = loading.fetchSub(1, .acq_rel);
    var duration: f32 = 0;
    if (!audio.waveform(w.path, w.peaks, &duration)) {
        w.state.store(.failed, .release);
        return;
    }
    // Scale so quiet files still show a shape
    var max: f32 = 0;
    for (w.peaks) |p| max = @max(max, p);
    if (max > 0.0001) {
        for (w.peaks) |*p| p.* = std.math.pow(f32, p.* / max, 1.4);
    }
    w.duration = duration;
    w.state.store(.ready, .release);
}
