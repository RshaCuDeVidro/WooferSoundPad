//! "Slice at silences": finds the loud stretches of a long file and writes each
//! one as its own WAV, so one recording becomes a row of pads.
//! Detection works on the waveform envelope the editor already has; the
//! cutting decodes the file again at full quality on a worker thread.

const std = @import("std");
const sys = @import("sys.zig");

const gpa = sys.gpa;

pub const Segment = struct { start: f32, end: f32 };

pub const Options = struct {
    /// Envelope level (dB) below which audio counts as silence
    threshold_db: f32 = -36,
    /// Gaps shorter than this don't split a piece
    min_silence: f32 = 0.4,
    /// Pieces shorter than this are dropped
    min_length: f32 = 0.3,
};

/// Lead-in and tail kept around each piece, so attacks and decays survive
const pad_before: f32 = 0.04;
const pad_after: f32 = 0.12;

/// Splits an envelope (`env`, 0..1 per equal slice of `duration` seconds)
/// into pieces. Returns how many were written to `out`.
pub fn segments(env: []const f32, duration: f32, opts: Options, out: []Segment) usize {
    if (env.len == 0 or duration <= 0 or out.len == 0) return 0;
    const thr = std.math.pow(f32, 10, opts.threshold_db / 20);
    const bin = duration / @as(f32, @floatFromInt(env.len));
    var n: usize = 0;
    var i: usize = 0;
    while (i < env.len) {
        while (i < env.len and env[i] < thr) i += 1;
        if (i == env.len) break;
        const first = i;
        // Extend over loud bins and over gaps too short to count
        var last = i;
        while (i < env.len) {
            if (env[i] >= thr) {
                last = i;
                i += 1;
                continue;
            }
            var gap_end = i;
            while (gap_end < env.len and env[gap_end] < thr) gap_end += 1;
            if (gap_end == env.len or @as(f32, @floatFromInt(gap_end - i)) * bin >= opts.min_silence) break;
            i = gap_end;
        }
        const start = @as(f32, @floatFromInt(first)) * bin;
        const end = @as(f32, @floatFromInt(last + 1)) * bin;
        if (end - start >= opts.min_length) {
            out[n] = .{ .start = start, .end = end };
            n += 1;
            if (n == out.len) break;
        }
    }
    // Breathing room, without overlapping the neighbours
    for (out[0..n], 0..) |*s, k| {
        const lo: f32 = if (k == 0) 0 else out[k - 1].end;
        const hi: f32 = if (k + 1 < n) out[k + 1].start else duration;
        s.start = @max(lo, s.start - pad_before);
        s.end = @min(hi, s.end + pad_after);
    }
    return n;
}

// ── Cutting ─────────────────────────────────────────────────────────────────

pub const State = enum(u8) { running, done };

/// Writes the pieces on a worker thread. The UI polls `state`, then adopts
/// `files` (names inside `dir`, null where writing failed) and calls `free`.
pub const Task = struct {
    state: std.atomic.Value(State) = .init(.running),
    written: std.atomic.Value(u32) = .init(0),
    src: [:0]u8,
    dir: []u8,
    base: []u8,
    ws_name: []u8,
    /// The pad that was sliced; the pieces go right after it
    uid: u32,
    pieces: []Segment,
    files: []?[]u8,

    pub fn start(src: []const u8, dir: []const u8, base: []const u8, ws_name: []const u8, uid: u32, pieces: []const Segment) !*Task {
        const t = try gpa.create(Task);
        errdefer gpa.destroy(t);
        t.* = .{
            .src = try gpa.dupeSentinel(u8, src, 0),
            .dir = try gpa.dupe(u8, dir),
            .base = try gpa.dupe(u8, base),
            .ws_name = try gpa.dupe(u8, ws_name),
            .uid = uid,
            .pieces = try gpa.dupe(Segment, pieces),
            .files = try gpa.alloc(?[]u8, pieces.len),
        };
        @memset(t.files, null);
        const thread = try std.Thread.spawn(.{}, work, .{t});
        thread.detach();
        return t;
    }

    fn work(t: *Task) void {
        const audio = @import("audio.zig");
        const library = @import("library.zig");
        for (t.pieces, 0..) |p, i| {
            var stem_buf: [160]u8 = undefined;
            const stem = std.fmt.bufPrint(&stem_buf, "{s} {d:0>2}", .{ t.base, i + 1 }) catch t.base;
            const name = library.uniqueName(t.dir, stem, ".wav") catch continue;
            const out = sys.joinZ(&.{ t.dir, name }) catch {
                gpa.free(name);
                continue;
            };
            defer gpa.free(out);
            if (audio.exportWav(t.src, p.start, p.end, 48000, 2, out)) {
                t.files[i] = name;
            } else {
                gpa.free(name);
                sys.deleteFile(out);
            }
            _ = t.written.fetchAdd(1, .acq_rel);
        }
        t.state.store(.done, .release);
    }

    pub fn progress(t: *const Task) f32 {
        if (t.pieces.len == 0) return 1;
        return @as(f32, @floatFromInt(t.written.load(.acquire))) / @as(f32, @floatFromInt(t.pieces.len));
    }

    /// Only once `state` is done
    pub fn free(t: *Task) void {
        for (t.files) |f| if (f) |name| gpa.free(name);
        gpa.free(t.files);
        gpa.free(t.pieces);
        gpa.free(t.src);
        gpa.free(t.dir);
        gpa.free(t.base);
        gpa.free(t.ws_name);
        gpa.destroy(t);
    }
};

test "segments split at long silences only" {
    // 0.1 s bins: loud 0.0-0.5, short gap, loud 0.6-1.0, long gap, loud 2.0-2.3
    var env: [30]f32 = @splat(0);
    for (0..5) |i| env[i] = 0.5;
    for (6..10) |i| env[i] = 0.5;
    for (20..23) |i| env[i] = 0.5;
    var out: [8]Segment = undefined;
    const n = segments(&env, 3.0, .{ .threshold_db = -30, .min_silence = 0.4, .min_length = 0.2 }, &out);
    try std.testing.expectEqual(@as(usize, 2), n);
    try std.testing.expectApproxEqAbs(@as(f32, 0), out[0].start, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.12), out[0].end, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.96), out[1].start, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 2.42), out[1].end, 0.001);
}

test "segments drop blips and respect the output size" {
    var env: [40]f32 = @splat(0);
    env[3] = 1; // 0.1 s blip
    for (10..20) |i| env[i] = 1;
    for (25..35) |i| env[i] = 1;
    var out: [1]Segment = undefined;
    const n = segments(&env, 4.0, .{ .min_length = 0.3, .min_silence = 0.3 }, &out);
    try std.testing.expectEqual(@as(usize, 1), n);
    try std.testing.expectApproxEqAbs(@as(f32, 0.96), out[0].start, 0.001);

    var none: [4]Segment = undefined;
    const silent: [10]f32 = @splat(0);
    try std.testing.expectEqual(@as(usize, 0), segments(&silent, 1, .{}, &none));
}
