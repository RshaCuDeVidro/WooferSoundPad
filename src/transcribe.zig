//! Search by what is said: whisper.cpp (run as a program, nothing linked in)
//! transcribes each sound once, in the background and fully offline. The
//! text is stored in workspace.json and matched by the pad search.
//!
//! whisper.cpp uses the graphics card when its build has a GPU backend (CUDA,
//! Vulkan...); the app only asks for it (or not) and reports what was used.

const std = @import("std");
const sys = @import("sys.zig");
const net = @import("net.zig");
const tools = @import("tools.zig");
pub const Model = @import("config.zig").WhisperModel;

const gpa = sys.gpa;

const model_base_url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/";

/// "fast" is the tiny model: about 3x lighter, more mistakes (Portuguese
/// most of all). "precise" is base. Both are multilingual.
pub fn modelFile(m: Model) []const u8 {
    return switch (m) {
        .fast => "ggml-tiny.bin",
        .precise => "ggml-base.bin",
    };
}

pub fn modelSizeMb(m: Model) u32 {
    return switch (m) {
        .fast => 75,
        .precise => 148,
    };
}

/// Languages offered in Settings, as whisper codes ("auto" detects, which
/// costs a second pass over the audio)
pub const languages = [_][]const u8{ "auto", "pt", "en", "es", "fr", "de", "it" };

/// Seconds listened to at the start of each sound
pub const durations = [_]u32{ 15, 30, 60 };

/// whisper.cpp publishes Windows builds; on Linux it comes from the package manager
pub const can_install_program = sys.is_windows;

/// Which Windows build we downloaded: plain CPU, or with NVIDIA CUDA
pub const Flavor = enum { cpu, cuda };
pub const program_size_mb: u32 = 8;
pub const cuda_size_mb: u32 = 700;

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

/// The build we downloaded ourselves, if any
pub fn bundledFlavor() ?Flavor {
    const dir = bundledDir() orelse return null;
    defer gpa.free(dir);
    const marker = sys.join(&.{ dir, "flavor.txt" }) catch return null;
    defer gpa.free(marker);
    const data = sys.readFile(marker, 64) catch return null;
    defer gpa.free(data);
    return std.meta.stringToEnum(Flavor, std.mem.trim(u8, data, " \r\n"));
}

pub fn modelPath(m: Model) ![]u8 {
    return sys.join(&.{ tools.tools_dir, modelFile(m) });
}

pub fn modelReady(m: Model) bool {
    const p = modelPath(m) catch return false;
    defer gpa.free(p);
    return sys.fileSize(p) > 1024 * 1024;
}

pub fn ready(m: Model) bool {
    return program != null and modelReady(m);
}

// ── Setup: downloads the model (and the program on Windows) ─────────────────

pub const State = enum(u8) { running, done, failed };

pub const Setup = struct {
    state: std.atomic.Value(State) = .init(.running),
    /// 0 = the model, 1 = the program
    stage: std.atomic.Value(u8) = .init(0),
    progress: net.Progress = .{},
    model: Model,
    /// Windows: the program build to download (null: keep what is there)
    flavor: ?Flavor,

    pub fn start(model: Model, flavor: ?Flavor) !*Setup {
        const s = try gpa.create(Setup);
        s.* = .{ .model = model, .flavor = flavor };
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
        if (!modelReady(s.model)) {
            const final = try modelPath(s.model);
            defer gpa.free(final);
            const tmp = try std.fmt.allocPrint(gpa, "{s}.part", .{final});
            defer gpa.free(tmp);
            const url = try std.fmt.allocPrint(gpa, "{s}{s}", .{ model_base_url, modelFile(s.model) });
            defer gpa.free(url);
            try net.download(url, tmp, &s.progress);
            try sys.rename(tmp, final);
        }
        const flavor = s.flavor orelse return;
        if (!can_install_program) return;
        s.stage.store(1, .release);
        s.progress.set(-1);
        const url = try programUrl(flavor);
        defer gpa.free(url);
        const dir = bundledDir() orelse return error.NoToolsDir;
        defer gpa.free(dir);
        const archive = try std.fmt.allocPrint(gpa, "{s}.zip", .{dir});
        defer gpa.free(archive);
        try net.download(url, archive, &s.progress);
        defer sys.deleteFile(archive);
        sys.deleteTree(dir);
        try sys.unzip(archive, dir);
        const marker = try sys.join(&.{ dir, "flavor.txt" });
        defer gpa.free(marker);
        try sys.writeFile(marker, @tagName(flavor));
    }

    /// Once the state is no longer running
    pub fn free(s: *Setup) void {
        gpa.destroy(s);
    }
};

/// whisper.cpp's "latest" release can come without files; the Windows builds
/// sit on recent build releases, so look for the newest one that has ours
fn programUrl(flavor: Flavor) ![]u8 {
    const names: []const []const u8 = switch (flavor) {
        .cpu => &.{"whisper-bin-x64.zip"},
        .cuda => &.{ "whisper-bin-win-cuda-12.4.0-x64.zip", "whisper-cublas-12.4.0-bin-x64.zip" },
    };
    const res = try net.get("https://api.github.com/repos/ggml-org/whisper.cpp/releases?per_page=20", 8 * 1024 * 1024);
    defer res.deinit();
    if (res.status != 200) return error.NoRelease;
    return findAsset(res.body, names);
}

const ReleaseJson = struct {
    assets: []const struct {
        name: []const u8,
        browser_download_url: []const u8,
    } = &.{},
};

/// Download URL of the first asset named like one of `names`, newest release first
pub fn findAsset(releases_json: []const u8, names: []const []const u8) ![]u8 {
    const parsed = try std.json.parseFromSlice([]const ReleaseJson, gpa, releases_json, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    for (parsed.value) |rel| {
        for (rel.assets) |asset| {
            for (names) |n| {
                if (std.mem.eql(u8, asset.name, n)) return gpa.dupe(u8, asset.browser_download_url);
            }
        }
    }
    return error.NoAsset;
}

// ── Transcribing one sound ──────────────────────────────────────────────────

pub const Options = struct {
    model: Model = .precise,
    /// whisper language code, "auto" to detect
    language: []const u8 = "auto",
    seconds: u32 = 15,
    gpu: bool = true,
};

pub const Task = struct {
    state: std.atomic.Value(State) = .init(.running),
    src: [:0]u8,
    ws_name: []u8,
    uid: u32,
    model: Model,
    language: [8]u8 = undefined,
    language_len: usize = 0,
    seconds: u32,
    gpu: bool,
    /// The transcript, once done
    text: []u8 = &.{},
    /// What whisper ran on ("GPU · NVIDIA GeForce GTX 1050 Ti", "CPU")
    backend: [96]u8 = undefined,
    backend_len: usize = 0,

    pub fn start(src: []const u8, ws_name: []const u8, uid: u32, opts: Options) !*Task {
        const t = try gpa.create(Task);
        errdefer gpa.destroy(t);
        const src_copy = try gpa.dupeSentinel(u8, src, 0);
        errdefer gpa.free(src_copy);
        t.* = .{ .src = src_copy, .ws_name = try gpa.dupe(u8, ws_name), .uid = uid, .model = opts.model, .seconds = opts.seconds, .gpu = opts.gpu };
        errdefer gpa.free(t.ws_name);
        t.language_len = @min(opts.language.len, t.language.len);
        @memcpy(t.language[0..t.language_len], opts.language[0..t.language_len]);
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
        const model = try modelPath(t.model);
        defer gpa.free(model);
        // whisper.cpp wants 16 kHz mono
        var name_buf: [64]u8 = undefined;
        const name = try std.fmt.bufPrint(&name_buf, "whisper-{d}-{x}.wav", .{ t.uid, std.hash.Wyhash.hash(0, t.src) });
        const wav = try sys.joinZ(&.{ tools.tools_dir, name });
        defer gpa.free(wav);
        defer sys.deleteFile(wav);
        if (!audio.exportWav(t.src, 0, @floatFromInt(t.seconds), 16000, 1, wav)) return error.Decode;

        // One core stays free for the UI and the audio
        var threads_buf: [8]u8 = undefined;
        const cores = std.Thread.getCpuCount() catch 2;
        const threads = std.fmt.bufPrint(&threads_buf, "{d}", .{std.math.clamp(cores -| 1, 1, 8)}) catch "2";
        // whisper always encodes a 30 s window; a short clip only needs part of
        // it, which makes the encoder several times faster
        var ctx_buf: [8]u8 = undefined;
        const ctx = std.fmt.bufPrint(&ctx_buf, "{d}", .{audioContext(sys.fileSize(wav))}) catch "0";
        const lang = if (t.language_len > 0) t.language[0..t.language_len] else "auto";
        var argv_buf: [16][]const u8 = undefined;
        var argv: std.ArrayList([]const u8) = .initBuffer(&argv_buf);
        argv.appendSliceAssumeCapacity(&.{ exe, "-m", model, "-f", wav, "-l", lang, "-nt", "-t", threads, "-ac", ctx });
        if (!t.gpu) argv.appendAssumeCapacity("-ng");
        const res = try sys.runLowPriority(argv.items, 256 * 1024);
        defer res.deinit();
        t.backend_len = describeBackend(&t.backend, res.stderr).len;
        if (!res.ok) return error.WhisperFailed;
        var buf: [1024]u8 = undefined;
        t.text = try gpa.dupe(u8, clean(&buf, res.stdout));
    }

    pub fn backendText(t: *const Task) []const u8 {
        return t.backend[0..t.backend_len];
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

/// Reads whisper.cpp's log for the device it ran on: "GPU · <card name>"
/// (or the ggml device, e.g. "Vulkan0"), or "CPU"
pub fn describeBackend(out: []u8, stderr: []const u8) []const u8 {
    const using = "whisper_backend_init_gpu: using ";
    const at = std.mem.indexOf(u8, stderr, using) orelse return "CPU";
    const rest = stderr[at + using.len ..];
    const dev = rest[0 .. std.mem.indexOf(u8, rest, " backend") orelse return "CPU"];
    // The card's own name, as the Vulkan or CUDA backend logged it
    const card = between(stderr, "ggml_vulkan: 0 = ", " (") orelse
        between(stderr, "Device 0: ", ",") orelse dev;
    return std.fmt.bufPrint(out, "GPU · {s}", .{std.mem.trim(u8, card, " ")}) catch "GPU";
}

fn between(s: []const u8, start: []const u8, end: []const u8) ?[]const u8 {
    const a = std.mem.indexOf(u8, s, start) orelse return null;
    const rest = s[a + start.len ..];
    const b = std.mem.indexOfAny(u8, rest, "\n") orelse rest.len;
    const line = rest[0..b];
    return line[0 .. std.mem.indexOf(u8, line, end) orelse return null];
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

test "backend from whisper's log" {
    var buf: [96]u8 = undefined;
    const cpu_log = "whisper_backend_init_gpu: device 0: CPU (type: 0)\nwhisper_backend_init_gpu: no GPU found\n";
    try std.testing.expectEqualStrings("CPU", describeBackend(&buf, cpu_log));
    const vk_log =
        \\ggml_vulkan: Found 1 Vulkan devices:
        \\ggml_vulkan: 0 = NVIDIA GeForce GTX 1050 Ti (NVIDIA) | uma: 0 | fp16: 0 | warp size: 32
        \\whisper_backend_init_gpu: device 0: Vulkan0 (type: 1)
        \\whisper_backend_init_gpu: using Vulkan0 backend
    ;
    try std.testing.expectEqualStrings("GPU · NVIDIA GeForce GTX 1050 Ti", describeBackend(&buf, vk_log));
    const cuda_log =
        \\  Device 0: NVIDIA GeForce RTX 3060, compute capability 8.6, VMM: yes
        \\whisper_backend_init_gpu: using CUDA0 backend
    ;
    try std.testing.expectEqualStrings("GPU · NVIDIA GeForce RTX 3060", describeBackend(&buf, cuda_log));
}

test "find the Windows build among releases" {
    const json =
        \\[{"tag_name":"v1.9.6","assets":[]},
        \\ {"tag_name":"b5907","assets":[{"name":"whisper-bin-Win32.zip","browser_download_url":"u32"},
        \\   {"name":"whisper-bin-x64.zip","browser_download_url":"https://x/whisper-bin-x64.zip"}]}]
    ;
    const url = try findAsset(json, &.{"whisper-bin-x64.zip"});
    defer gpa.free(url);
    try std.testing.expectEqualStrings("https://x/whisper-bin-x64.zip", url);
    try std.testing.expectError(error.NoAsset, findAsset(json, &.{"whisper-bin-win-cuda-12.4.0-x64.zip"}));
}

test "clean whisper output" {
    var buf: [128]u8 = undefined;
    try std.testing.expectEqualStrings("Ai meu Deus! que isso", clean(&buf, " [Music]\n Ai meu Deus!  (laughs) que\n isso\n"));
    try std.testing.expectEqualStrings("", clean(&buf, " [BLANK_AUDIO]\n"));
    try std.testing.expectEqualStrings("bruh", clean(&buf, "*applause* bruh"));
}
