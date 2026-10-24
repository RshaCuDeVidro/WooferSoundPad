//! External helpers: yt-dlp (YouTube, SoundCloud and 1000+ sites, no API
//! keys), ffmpeg (conversion, trimming, loudness) and deno (the JavaScript
//! runtime yt-dlp needs for YouTube). System installs are used when present;
//! otherwise the app downloads standalone builds into its data folder.

const std = @import("std");
const sys = @import("sys.zig");
const net = @import("net.zig");
const Config = @import("config.zig").Config;
const AudioFormat = @import("config.zig").AudioFormat;

const gpa = sys.gpa;

pub const Tool = enum { ytdlp, ffmpeg, deno };

pub const Status = struct {
    path: ?[]u8 = null,
    bundled: bool = false, // downloaded by us, not the system's

    fn deinit(s: *Status) void {
        if (s.path) |p| gpa.free(p);
        s.* = .{};
    }
};

pub var tools_dir: []u8 = &.{};
pub var ytdlp: Status = .{};
pub var ffmpeg: Status = .{};
pub var deno: Status = .{};

pub fn status(tool: Tool) *Status {
    return switch (tool) {
        .ytdlp => &ytdlp,
        .ffmpeg => &ffmpeg,
        .deno => &deno,
    };
}

pub fn init() void {
    const data = sys.dataDir() catch return;
    defer gpa.free(data);
    tools_dir = sys.join(&.{ data, "tools" }) catch return;
    sys.makePath(tools_dir) catch {};
}

fn binaryName(tool: Tool) []const u8 {
    return switch (tool) {
        .ytdlp => "yt-dlp" ++ sys.exe_suffix,
        .ffmpeg => "ffmpeg" ++ sys.exe_suffix,
        .deno => "deno" ++ sys.exe_suffix,
    };
}

/// Finds every tool: custom path from settings → our bundled copy → PATH
pub fn detect(cfg: *const Config) void {
    detectOne(.ytdlp, cfg.ytdlp_path);
    detectOne(.ffmpeg, cfg.ffmpeg_path);
    detectOne(.deno, cfg.deno_path);
    probeVersions();
}

fn detectOne(tool: Tool, custom: []const u8) void {
    const s = status(tool);
    s.deinit();
    if (custom.len > 0 and sys.exists(custom)) {
        s.path = gpa.dupe(u8, custom) catch null;
        return;
    }
    const bundled = sys.join(&.{ tools_dir, binaryName(tool) }) catch return;
    if (sys.exists(bundled)) {
        s.path = bundled;
        s.bundled = true;
        return;
    }
    gpa.free(bundled);
    s.path = sys.which(binaryName(tool));
}

pub fn available(tool: Tool) bool {
    return status(tool).path != null;
}

/// Where yt-dlp should look for ffmpeg + ffprobe
fn ffmpegLocation() ?[]const u8 {
    const p = ffmpeg.path orelse return null;
    return std.fs.path.dirname(p);
}

// ── Installing ──────────────────────────────────────────────────────────────

const gh = "https://github.com";

fn downloadUrl(tool: Tool) []const u8 {
    return switch (tool) {
        .ytdlp => if (sys.is_windows) gh ++ "/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe" else gh ++ "/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux",
        .ffmpeg => if (sys.is_windows) gh ++ "/yt-dlp/FFmpeg-Builds/releases/latest/download/ffmpeg-master-latest-win64-gpl.zip" else gh ++ "/yt-dlp/FFmpeg-Builds/releases/latest/download/ffmpeg-master-latest-linux64-gpl.tar.xz",
        .deno => if (sys.is_windows) gh ++ "/denoland/deno/releases/latest/download/deno-x86_64-pc-windows-msvc.zip" else gh ++ "/denoland/deno/releases/latest/download/deno-x86_64-unknown-linux-gnu.zip",
    };
}

/// Approximate download size, shown before installing
pub fn downloadSizeMb(tool: Tool) u32 {
    return switch (tool) {
        .ytdlp => if (sys.is_windows) 18 else 41,
        .ffmpeg => if (sys.is_windows) 200 else 156,
        .deno => 43,
    };
}

/// Downloads and unpacks a tool into the data folder. Runs on a worker thread.
pub fn install(tool: Tool, progress: *net.Progress, stage: *std.atomic.Value(u8)) !void {
    try sys.makePath(tools_dir);
    const final = try sys.join(&.{ tools_dir, binaryName(tool) });
    defer gpa.free(final);

    switch (tool) {
        .ytdlp => {
            const tmp = try std.fmt.allocPrint(gpa, "{s}.part", .{final});
            defer gpa.free(tmp);
            try net.download(downloadUrl(tool), tmp, progress);
            sys.deleteFile(final);
            try sys.rename(tmp, final);
            sys.makeExecutable(final);
        },
        .ffmpeg, .deno => {
            const ext = if (tool == .ffmpeg and !sys.is_windows) ".tar.xz" else ".zip";
            const archive = try std.fmt.allocPrint(gpa, "{s}{s}", .{ final, ext });
            defer gpa.free(archive);
            try net.download(downloadUrl(tool), archive, progress);
            defer sys.deleteFile(archive);

            stage.store(1, .release); // "unpacking"
            progress.set(-1);
            const unpack = try std.fmt.allocPrint(gpa, "{s}.unpack", .{final});
            defer gpa.free(unpack);
            sys.deleteTree(unpack);
            try sys.makePath(unpack);
            defer sys.deleteTree(unpack);

            if (std.mem.endsWith(u8, archive, ".zip")) {
                try sys.unzip(archive, unpack);
            } else {
                const res = try sys.run(&.{ "tar", "-xJf", archive, "-C", unpack }, 64 * 1024);
                defer res.deinit();
                if (!res.ok) return error.UnpackFailed;
            }

            // Flatten: copy the binaries we need next to each other
            const wanted: []const []const u8 = if (tool == .ffmpeg)
                &.{ "ffmpeg" ++ sys.exe_suffix, "ffprobe" ++ sys.exe_suffix }
            else
                &.{"deno" ++ sys.exe_suffix};
            for (wanted) |name| {
                const found = sys.findFile(unpack, name) orelse return error.BinaryNotFound;
                defer gpa.free(found);
                const dest = try sys.join(&.{ tools_dir, name });
                defer gpa.free(dest);
                sys.deleteFile(dest);
                sys.rename(found, dest) catch try sys.copyFile(found, dest);
                sys.makeExecutable(dest);
            }
        },
    }
}

pub fn uninstall(tool: Tool) void {
    const names: []const []const u8 = switch (tool) {
        .ytdlp => &.{"yt-dlp" ++ sys.exe_suffix},
        .ffmpeg => &.{ "ffmpeg" ++ sys.exe_suffix, "ffprobe" ++ sys.exe_suffix },
        .deno => &.{"deno" ++ sys.exe_suffix},
    };
    for (names) |name| {
        const p = sys.join(&.{ tools_dir, name }) catch continue;
        defer gpa.free(p);
        sys.deleteFile(p);
    }
}

// ── Versions (probed in the background: yt-dlp takes ~1 s to start) ────────

var version_mutex: std.Io.Mutex = .init;
var version_bufs: [3][64]u8 = undefined;
var version_lens: [3]usize = .{ 0, 0, 0 };
var version_gen: u32 = 0;

fn probeVersions() void {
    version_mutex.lockUncancelable(sys.io);
    version_gen +%= 1;
    version_lens = .{ 0, 0, 0 };
    const gen = version_gen;
    version_mutex.unlock(sys.io);

    var paths: [3]?[]u8 = .{ null, null, null };
    for (std.enums.values(Tool), 0..) |tool, i| {
        if (status(tool).path) |p| paths[i] = gpa.dupe(u8, p) catch null;
    }
    const t = std.Thread.spawn(.{}, probeThread, .{ paths, gen }) catch {
        for (paths) |p| if (p) |pp| gpa.free(pp);
        return;
    };
    t.detach();
}

fn probeThread(paths: [3]?[]u8, gen: u32) void {
    for (std.enums.values(Tool), 0..) |tool, i| {
        const p = paths[i] orelse continue;
        defer gpa.free(p);
        const v = version(tool, p) orelse continue;
        defer gpa.free(v);
        version_mutex.lockUncancelable(sys.io);
        defer version_mutex.unlock(sys.io);
        if (gen != version_gen) continue; // tools changed meanwhile
        const n = @min(v.len, version_bufs[i].len);
        @memcpy(version_bufs[i][0..n], v[0..n]);
        version_lens[i] = n;
    }
}

/// Version text once known (copied into `out`)
pub fn versionText(tool: Tool, out: []u8) ?[]const u8 {
    version_mutex.lockUncancelable(sys.io);
    defer version_mutex.unlock(sys.io);
    const i = @backingInt(tool);
    if (version_lens[i] == 0) return null;
    const n = @min(version_lens[i], out.len);
    @memcpy(out[0..n], version_bufs[i][0..n]);
    return out[0..n];
}

/// yt-dlp versions are dates ("2026.07.04"). YouTube breaks old ones within
/// weeks, so the UI nags once a copy is this many days old.
pub const outdated_after_days = 60;

pub fn ytdlpAgeDays() ?i64 {
    var buf: [64]u8 = undefined;
    const v = versionText(.ytdlp, &buf) orelse return null;
    var it = std.mem.splitScalar(u8, v, '.');
    const y = std.fmt.parseInt(i64, it.next() orelse return null, 10) catch return null;
    const m = std.fmt.parseInt(i64, it.next() orelse return null, 10) catch return null;
    const d = std.fmt.parseInt(i64, it.next() orelse return null, 10) catch return null;
    const today = @divFloor(std.Io.Timestamp.now(sys.io, .real).toSeconds(), 86400);
    return today - daysFromCivil(y, m, d);
}

/// Days since 1970-01-01 (Howard Hinnant's algorithm)
fn daysFromCivil(y_in: i64, m: i64, d: i64) i64 {
    const y = if (m <= 2) y_in - 1 else y_in;
    const era = @divFloor(y, 400);
    const yoe = y - era * 400;
    const mp = if (m > 2) m - 3 else m + 9;
    const doy = @divFloor(153 * mp + 2, 5) + d - 1;
    const doe = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy;
    return era * 146097 + doe - 719468;
}

test "days from civil" {
    try std.testing.expectEqual(@as(i64, 0), daysFromCivil(1970, 1, 1));
    try std.testing.expectEqual(@as(i64, 20017), daysFromCivil(2024, 10, 21));
}

fn version(tool: Tool, p: []const u8) ?[]u8 {
    const arg: []const u8 = switch (tool) {
        .ytdlp => "--version",
        .ffmpeg => "-version",
        .deno => "--version",
    };
    const res = sys.run(&.{ p, arg }, 64 * 1024) catch return null;
    defer gpa.free(res.stderr);
    if (!res.ok) {
        gpa.free(res.stdout);
        return null;
    }
    const first = std.mem.trim(u8, std.mem.sliceTo(res.stdout, '\n'), " \r\n");
    var words = std.mem.tokenizeScalar(u8, first, ' ');
    var short: []const u8 = first;
    if (tool != .ytdlp) {
        _ = words.next(); // "ffmpeg" / "deno"
        if (words.next()) |w| short = if (std.mem.eql(u8, w, "version")) words.next() orelse w else w;
    }
    const out = gpa.dupe(u8, short) catch null;
    gpa.free(res.stdout);
    return out;
}

// ── Searching (YouTube / SoundCloud) ────────────────────────────────────────

pub const Platform = enum { youtube, soundcloud };

pub const MediaResult = struct {
    title: []u8,
    url: []u8,
    uploader: []u8,
    thumbnail: []u8,
    duration: f32,

    pub fn deinit(r: MediaResult) void {
        gpa.free(r.title);
        gpa.free(r.url);
        gpa.free(r.uploader);
        gpa.free(r.thumbnail);
    }
};

const search_template = "%(.{id,title,url,webpage_url,duration,uploader,channel,thumbnails.-1.url})j";

fn appendJsRuntime(argv: *std.ArrayList([]const u8), tmp: *std.ArrayList(u8)) !void {
    if (deno.path) |p| {
        tmp.clearRetainingCapacity();
        try tmp.print(gpa, "deno:{s}", .{p});
        try argv.appendSlice(gpa, &.{ "--js-runtimes", tmp.items });
    }
}

pub fn search(platform: Platform, query: []const u8, count: u32, out: *std.ArrayList(MediaResult)) !void {
    const exe = ytdlp.path orelse return error.YtDlpMissing;
    const target = try std.fmt.allocPrint(gpa, "{s}{d}:{s}", .{ if (platform == .youtube) "ytsearch" else "scsearch", count, query });
    defer gpa.free(target);

    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(gpa);
    var runtime_arg: std.ArrayList(u8) = .empty;
    defer runtime_arg.deinit(gpa);
    try argv.appendSlice(gpa, &.{ exe, "--no-update", "--no-warnings", "--flat-playlist", "--print", search_template });
    if (platform == .youtube) try appendJsRuntime(&argv, &runtime_arg);
    try argv.append(gpa, target);

    const res = try sys.run(argv.items, 16 * 1024 * 1024);
    defer res.deinit();
    if (!res.ok and res.stdout.len == 0) {
        std.log.warn("yt-dlp search failed: {s}", .{res.stderr});
        return error.SearchFailed;
    }
    try parseSearchOutput(res.stdout, out);
}

const SearchLine = struct {
    id: []const u8 = "",
    title: []const u8 = "",
    url: []const u8 = "",
    webpage_url: []const u8 = "",
    duration: ?f64 = null,
    uploader: ?[]const u8 = null,
    channel: ?[]const u8 = null,
    @"thumbnails.-1.url": ?[]const u8 = null,
};

pub fn parseSearchOutput(stdout: []const u8, out: *std.ArrayList(MediaResult)) !void {
    var lines = std.mem.tokenizeScalar(u8, stdout, '\n');
    while (lines.next()) |raw| {
        const line_text = std.mem.trim(u8, raw, " \r");
        if (line_text.len == 0 or line_text[0] != '{') continue;
        const parsed = std.json.parseFromSlice(SearchLine, gpa, line_text, .{ .ignore_unknown_fields = true }) catch continue;
        defer parsed.deinit();
        const v = parsed.value;
        // SoundCloud's `url` is an API link; the page link is what users expect
        const link = if (v.webpage_url.len > 0) v.webpage_url else v.url;
        if (link.len == 0) continue;
        const is_youtube = std.mem.indexOf(u8, link, "youtube.com/") != null or std.mem.indexOf(u8, link, "youtu.be/") != null;
        const thumb = if (is_youtube and v.id.len > 0)
            try std.fmt.allocPrint(gpa, "https://i.ytimg.com/vi/{s}/mqdefault.jpg", .{v.id})
        else
            try gpa.dupe(u8, v.@"thumbnails.-1.url" orelse "");
        try out.append(gpa, .{
            .title = try gpa.dupe(u8, if (v.title.len > 0) v.title else v.id),
            .url = try gpa.dupe(u8, link),
            .uploader = try gpa.dupe(u8, v.uploader orelse v.channel orelse ""),
            .thumbnail = thumb,
            .duration = if (v.duration) |d| @floatCast(d) else 0,
        });
    }
}

// ── Downloading media ───────────────────────────────────────────────────────

pub const MediaOptions = struct {
    format: AudioFormat = .mp3,
};

fn formatArg(f: AudioFormat) []const u8 {
    return switch (f) {
        .mp3 => "mp3",
        .ogg => "vorbis",
        .wav => "wav",
    };
}

fn formatSeconds(buf: []u8, s: f32) []const u8 {
    return std.fmt.bufPrint(buf, "{d:.2}", .{s}) catch "0";
}

/// Downloads `url` as audio into `out_dir`. Returns the produced file (owned).
pub fn downloadMedia(url: []const u8, out_dir: []const u8, opts: MediaOptions, progress: *net.Progress, stage: *std.atomic.Value(u8)) ![]u8 {
    const exe = ytdlp.path orelse return error.YtDlpMissing;
    try sys.makePath(out_dir);
    const template = try sys.join(&.{ out_dir, "%(title).80B [%(id)s].%(ext)s" });
    defer gpa.free(template);

    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(gpa);
    var runtime_arg: std.ArrayList(u8) = .empty;
    defer runtime_arg.deinit(gpa);
    try argv.appendSlice(gpa, &.{
        exe,                    "--no-update",                             "--no-warnings", "--no-playlist",
        "-f",                   "bestaudio/best",                          "-x",            "--audio-format",
        formatArg(opts.format), "--audio-quality",                         "192K",          "-o",
        template,               "--newline",                               "-q",            "--progress",
        "--progress-template",  "download:WOOF %(progress._percent_str)s", "--print",       "after_move:DONE %(filepath)s",
        "--restrict-filenames",
    });
    if (ffmpegLocation()) |loc| try argv.appendSlice(gpa, &.{ "--ffmpeg-location", loc });
    try appendJsRuntime(&argv, &runtime_arg);
    // Trimming happens afterwards with our own ffmpeg pass: YouTube rejects
    // the partial range requests yt-dlp's --download-sections makes.
    try argv.append(gpa, url);

    // stderr goes to a log file so the pipe can never fill up and stall yt-dlp
    const log_path = try sys.join(&.{ out_dir, "yt-dlp.log" });
    defer gpa.free(log_path);
    const log_file = try std.Io.Dir.cwd().createFile(sys.io, log_path, .{});
    defer {
        log_file.close(sys.io);
        sys.deleteFile(log_path);
    }

    var child = try std.process.spawn(sys.io, .{
        .argv = argv.items,
        .stdin = .ignore,
        .stdout = .pipe,
        .stderr = .{ .file = log_file },
        .create_no_window = true,
    });

    var produced: ?[]u8 = null;
    errdefer if (produced) |p| gpa.free(p);
    var buf: [16 * 1024]u8 = undefined;
    var reader = child.stdout.?.readerStreaming(sys.io, &buf);
    while (true) {
        if (progress.canceled()) {
            child.kill(sys.io);
            return error.Canceled;
        }
        const raw = reader.interface.takeDelimiter('\n') catch break orelse break;
        const line_text = std.mem.trim(u8, raw, " \r");
        if (std.mem.startsWith(u8, line_text, "WOOF")) {
            if (net.parsePercent(line_text)) |pct| {
                progress.set(pct / 100);
                if (pct >= 100) stage.store(1, .release); // converting
            }
        } else if (std.mem.startsWith(u8, line_text, "DONE ")) {
            if (produced) |p| gpa.free(p);
            produced = try gpa.dupe(u8, line_text[5..]);
        }
    }
    const term = try child.wait(sys.io);
    const ok = switch (term) {
        .exited => |code| code == 0,
        else => false,
    };
    if (!ok or produced == null) {
        logTail(log_path);
        return error.DownloadFailed;
    }
    return produced.?;
}

fn logTail(path: []const u8) void {
    const data = sys.readFile(path, 256 * 1024) catch return;
    defer gpa.free(data);
    const tail = data[data.len -| 600..];
    std.log.err("yt-dlp: {s}", .{tail});
}

// ── ffmpeg processing ───────────────────────────────────────────────────────

pub const ProcessOptions = struct {
    format: AudioFormat = .mp3,
    normalize: bool = false,
    start: ?f32 = null,
    end: ?f32 = null,
    max_seconds: u32 = 0,
};

pub fn extensionFor(format: AudioFormat) []const u8 {
    return switch (format) {
        .mp3 => ".mp3",
        .ogg => ".ogg",
        .wav => ".wav",
    };
}

/// Re-encodes `input` to `output`, optionally trimming and normalizing loudness
pub fn process(input: []const u8, output: []const u8, opts: ProcessOptions) !void {
    const exe = ffmpeg.path orelse return error.FfmpegMissing;
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(gpa);
    try argv.appendSlice(gpa, &.{ exe, "-hide_banner", "-loglevel", "error", "-y" });

    var a: [16]u8 = undefined;
    var b: [16]u8 = undefined;
    var m: [16]u8 = undefined;
    if (opts.start) |s| try argv.appendSlice(gpa, &.{ "-ss", formatSeconds(&a, s) });
    try argv.appendSlice(gpa, &.{ "-i", input });
    if (opts.end) |e| {
        const dur = e - (opts.start orelse 0);
        if (dur > 0) try argv.appendSlice(gpa, &.{ "-t", formatSeconds(&b, dur) });
    } else if (opts.max_seconds > 0) {
        try argv.appendSlice(gpa, &.{ "-t", std.fmt.bufPrint(&m, "{d}", .{opts.max_seconds}) catch "30" });
    }
    try argv.append(gpa, "-vn");
    if (opts.normalize) try argv.appendSlice(gpa, &.{ "-af", "loudnorm=I=-14:TP=-1.5:LRA=11" });
    try argv.appendSlice(gpa, &.{ "-ar", "48000" });
    switch (opts.format) {
        .mp3 => try argv.appendSlice(gpa, &.{ "-c:a", "libmp3lame", "-q:a", "2" }),
        .ogg => try argv.appendSlice(gpa, &.{ "-c:a", "libvorbis", "-q:a", "5" }),
        .wav => try argv.appendSlice(gpa, &.{ "-c:a", "pcm_s16le" }),
    }
    try argv.append(gpa, output);

    const res = try sys.run(argv.items, 1024 * 1024);
    defer res.deinit();
    if (!res.ok) {
        std.log.err("ffmpeg: {s}", .{res.stderr});
        return error.FfmpegFailed;
    }
}

test "parse yt-dlp search lines" {
    const out_text =
        \\{"id": "abc", "title": "Husky howl ♥", "url": "https://www.youtube.com/watch?v=abc", "webpage_url": "https://www.youtube.com/watch?v=abc", "duration": 76, "uploader": "Dogs", "thumbnails.-1.url": "https://i.ytimg.com/x.jpg"}
        \\{"id": "1", "title": "SC", "url": "https://api.soundcloud.com/tracks/1", "webpage_url": "https://soundcloud.com/a/b", "duration": 4.441, "uploader": "a"}
        \\not json
    ;
    var list: std.ArrayList(MediaResult) = .empty;
    defer {
        for (list.items) |r| r.deinit();
        list.deinit(gpa);
    }
    try parseSearchOutput(out_text, &list);
    try std.testing.expectEqual(@as(usize, 2), list.items.len);
    try std.testing.expectEqualStrings("Husky howl ♥", list.items[0].title);
    try std.testing.expectEqualStrings("https://soundcloud.com/a/b", list.items[1].url);
    try std.testing.expectEqual(@as(f32, 76), list.items[0].duration);
    try std.testing.expectEqualStrings("https://i.ytimg.com/vi/abc/mqdefault.jpg", list.items[0].thumbnail);
}
