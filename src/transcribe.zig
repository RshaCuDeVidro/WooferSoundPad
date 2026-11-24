//! Search by what is said: whisper.cpp (run as a program, nothing linked in)
//! transcribes each sound once, in the background and fully offline. The
//! text is stored in workspace.json and matched by the pad search.

const std = @import("std");
const sys = @import("sys.zig");
const net = @import("net.zig");
const tools = @import("tools.zig");

const gpa = sys.gpa;

/// Multilingual "base": small enough to download, good enough for short clips
pub const model_name = "ggml-base.bin";
const model_url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin";
pub const model_size_mb: u32 = 148;
/// whisper.cpp publishes Windows builds; on Linux it comes from the package manager
pub const can_install_program = sys.is_windows;
const program_zip = "https://github.com/ggml-org/whisper.cpp/releases/latest/download/whisper-bin-x64.zip";
pub const program_size_mb: u32 = 4;
/// Only the start of long files: plenty to find a meme by its words
const max_seconds: f32 = 60;

const program_names = [_][]const u8{ "whisper-cli", "whisper-cpp" };

pub var program: ?[]u8 = null;

/// custom path from settings → our own copy (Windows) → PATH
pub fn detect(custom: []const u8) void {
    if (program) |p| gpa.free(p);
    program = null;
    if (custom.len > 0 and sys.exists(custom)) {
        program = gpa.dupe(u8, custom) catch null;
        return;
    }
    if (bundledDir()) |dir| {
        defer gpa.free(dir);
        program = sys.findFile(dir, "whisper-cli" ++ sys.exe_suffix);
        if (program != null) return;
    }
    for (program_names) |name| {
        program = sys.which(name);
        if (program != null) return;
    }
}

fn bundledDir() ?[]u8 {
    if (tools.tools_dir.len == 0) return null;
    return sys.join(&.{ tools.tools_dir, "whisper" }) catch null;
}

pub fn modelPath() ![]u8 {
    return sys.join(&.{ tools.tools_dir, model_name });
}

pub fn modelReady() bool {
    const p = modelPath() catch return false;
    defer gpa.free(p);
    return sys.fileSize(p) > 1024 * 1024;
}

pub fn ready() bool {
    return program != null and modelReady();
}

// ── Setup: downloads the model (and the program on Windows) ─────────────────

pub const State = enum(u8) { running, done, failed };

pub const Setup = struct {
    state: std.atomic.Value(State) = .init(.running),
    /// 0 = the model, 1 = the program
    stage: std.atomic.Value(u8) = .init(0),
    progress: net.Progress = .{},

    pub fn start() !*Setup {
        const s = try gpa.create(Setup);
        s.* = .{};
        const thread = std.Thread.spawn(.{}, work, .{s}) catch |err| {
            gpa.destroy(s);
            return err;
        };
        thread.detach();
        return s;
    }

    fn work(s: *Setup) void {
        const ok = if (s.install()) true else |err| blk: {
            std.log.warn("whisper setup: {s}", .{@errorName(err)});
            break :blk false;
        };
        s.state.store(if (ok) .done else .failed, .release);
    }

    fn install(s: *Setup) !void {
        try sys.makePath(tools.tools_dir);
        if (!modelReady()) {
            const final = try modelPath();
            defer gpa.free(final);
            const tmp = try std.fmt.allocPrint(gpa, "{s}.part", .{final});
            defer gpa.free(tmp);
            try net.download(model_url, tmp, &s.progress);
            try sys.rename(tmp, final);
        }
        if (can_install_program and program == null) {
            s.stage.store(1, .release);
            s.progress.set(-1);
            const dir = bundledDir() orelse return error.NoToolsDir;
            defer gpa.free(dir);
            const archive = try std.fmt.allocPrint(gpa, "{s}.zip", .{dir});
            defer gpa.free(archive);
            try net.download(program_zip, archive, &s.progress);
            defer sys.deleteFile(archive);
            sys.deleteTree(dir);
            try sys.unzip(archive, dir);
        }
    }

    /// Once the state is no longer running
    pub fn free(s: *Setup) void {
        gpa.destroy(s);
    }
};

// ── Transcribing one sound ──────────────────────────────────────────────────

pub const Task = struct {
    state: std.atomic.Value(State) = .init(.running),
    src: [:0]u8,
    ws_name: []u8,
    uid: u32,
    /// The transcript, once done
    text: []u8 = &.{},

    pub fn start(src: []const u8, ws_name: []const u8, uid: u32) !*Task {
        const t = try gpa.create(Task);
        errdefer gpa.destroy(t);
        const src_copy = try gpa.dupeSentinel(u8, src, 0);
        errdefer gpa.free(src_copy);
        t.* = .{ .src = src_copy, .ws_name = try gpa.dupe(u8, ws_name), .uid = uid };
        errdefer gpa.free(t.ws_name);
        const thread = try std.Thread.spawn(.{}, work, .{t});
        thread.detach();
        return t;
    }

    fn work(t: *Task) void {
        const ok = if (t.transcribe()) true else |err| blk: {
            std.log.warn("transcribe {s}: {s}", .{ t.src, @errorName(err) });
            break :blk false;
        };
        t.state.store(if (ok) .done else .failed, .release);
    }

    fn transcribe(t: *Task) !void {
        const audio = @import("audio.zig");
        const exe = program orelse return error.NoWhisper;
        const model = try modelPath();
        defer gpa.free(model);
        // whisper.cpp wants 16 kHz mono
        var name_buf: [64]u8 = undefined;
        const name = try std.fmt.bufPrint(&name_buf, "whisper-{d}-{x}.wav", .{ t.uid, std.hash.Wyhash.hash(0, t.src) });
        const wav = try sys.joinZ(&.{ tools.tools_dir, name });
        defer gpa.free(wav);
        defer sys.deleteFile(wav);
        if (!audio.exportWav(t.src, 0, max_seconds, 16000, 1, wav)) return error.Decode;

        // One core stays free for the UI and the audio
        var threads_buf: [8]u8 = undefined;
        const cores = std.Thread.getCpuCount() catch 2;
        const threads = std.fmt.bufPrint(&threads_buf, "{d}", .{std.math.clamp(cores -| 1, 1, 8)}) catch "2";
        // whisper always encodes a 30 s window; a short clip only needs part of
        // it, which makes the encoder several times faster
        var ctx_buf: [8]u8 = undefined;
        const ctx = std.fmt.bufPrint(&ctx_buf, "{d}", .{audioContext(sys.fileSize(wav))}) catch "0";
        const res = try sys.run(&.{ exe, "-m", model, "-f", wav, "-l", "auto", "-nt", "-np", "-t", threads, "-ac", ctx }, 256 * 1024);
        defer res.deinit();
        if (!res.ok) return error.WhisperFailed;
        var buf: [1024]u8 = undefined;
        t.text = try gpa.dupe(u8, clean(&buf, res.stdout));
    }

    /// Once the state is no longer running
    pub fn free(t: *Task) void {
        gpa.free(t.src);
        gpa.free(t.ws_name);
        gpa.free(t.text);
        gpa.destroy(t);
    }
};

/// whisper's audio context for a 16 kHz mono WAV of `wav_bytes`: 1500 frames
/// cover 30 s; shorter clips get their share plus some margin (0 = all of it)
fn audioContext(wav_bytes: u64) u32 {
    const seconds = @as(f32, @floatFromInt(wav_bytes -| 44)) / (16000 * 2);
    if (seconds >= 25) return 0;
    const frames: u32 = @intFromFloat(@ceil(seconds / 30 * 1500));
    return std.math.clamp(frames + 128, 256, 1500);
}

/// Drops whisper's sound tags ("[Music]", "(laughs)", "*applause*") and
/// squeezes whitespace into single spaces
pub fn clean(out: []u8, raw: []const u8) []const u8 {
    var n: usize = 0;
    var depth: u8 = 0;
    var starred = false;
    var space = true;
    for (raw) |ch| {
        switch (ch) {
            '[', '(' => depth +|= 1,
            ']', ')' => depth -|= 1,
            '*' => starred = !starred,
            else => {
                if (depth > 0 or starred) continue;
                const ws = ch == ' ' or ch == '\n' or ch == '\r' or ch == '\t';
                if (ws and space) continue;
                if (n == out.len) break;
                out[n] = if (ws) ' ' else ch;
                n += 1;
                space = ws;
            },
        }
    }
    return std.mem.trimEnd(u8, out[0..n], " ");
}

test "audio context grows with the clip" {
    try std.testing.expectEqual(@as(u32, 256), audioContext(44 + 2 * 32000));
    try std.testing.expectEqual(@as(u32, 628), audioContext(44 + 10 * 32000));
    try std.testing.expectEqual(@as(u32, 0), audioContext(44 + 40 * 32000));
}

test "clean whisper output" {
    var buf: [128]u8 = undefined;
    try std.testing.expectEqualStrings("Ai meu Deus! que isso", clean(&buf, " [Music]\n Ai meu Deus!  (laughs) que\n isso\n"));
    try std.testing.expectEqualStrings("", clean(&buf, " [BLANK_AUDIO]\n"));
    try std.testing.expectEqualStrings("bruh", clean(&buf, "*applause* bruh"));
}
