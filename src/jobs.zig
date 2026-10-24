//! Background work. Every job runs on its own thread and talks to the UI
//! thread only through atomics; results are read once the state says "done".
//!
//! Short-lived tasks (searches, previews) can be abandoned by the UI while
//! still running: whichever side finishes last frees the task.

const std = @import("std");
const c = @import("c");
const sys = @import("sys.zig");
const net = @import("net.zig");
const market = @import("market.zig");
const tools = @import("tools.zig");
const library = @import("library.zig");
const config = @import("config.zig");

const gpa = sys.gpa;

pub var cache_dir: []u8 = &.{};

pub fn init() void {
    const data = sys.dataDir() catch return;
    defer gpa.free(data);
    cache_dir = sys.join(&.{ data, "cache" }) catch return;
    for ([_][]const u8{ "downloads", "previews", "thumbs" }) |sub| {
        const p = sys.join(&.{ cache_dir, sub }) catch continue;
        defer gpa.free(p);
        sys.makePath(p) catch {};
    }
}

fn cachePath(sub: []const u8, key: []const u8, ext: []const u8) ![]u8 {
    const h = std.hash.Wyhash.hash(0, key);
    const name = try std.fmt.allocPrint(gpa, "{x:0>16}{s}", .{ h, ext });
    defer gpa.free(name);
    return sys.join(&.{ cache_dir, sub, name });
}

pub fn cacheSizeBytes() u64 {
    var total: u64 = 0;
    for ([_][]const u8{ "previews", "thumbs", "downloads" }) |sub| {
        const dir = sys.join(&.{ cache_dir, sub }) catch continue;
        defer gpa.free(dir);
        const entries = sys.listDir(dir) catch continue;
        defer sys.freeEntries(entries);
        for (entries) |e| {
            if (e.is_dir) continue;
            const p = sys.join(&.{ dir, e.name }) catch continue;
            defer gpa.free(p);
            total += sys.fileSize(p);
        }
    }
    return total;
}

pub fn clearCache() void {
    for ([_][]const u8{ "previews", "thumbs", "downloads" }) |sub| {
        const dir = sys.join(&.{ cache_dir, sub }) catch continue;
        defer gpa.free(dir);
        sys.deleteTree(dir);
        sys.makePath(dir) catch {};
    }
}

// ── Abandonable task plumbing ───────────────────────────────────────────────

pub const TaskState = enum(u8) { running, done, failed, abandoned };

const Shared = struct {
    state: std.atomic.Value(TaskState) = .init(.running),

    /// Worker side. Returns true if the UI already abandoned the task,
    /// meaning the worker must free it.
    fn finish(s: *Shared, ok: bool) bool {
        return s.state.cmpxchgStrong(.running, if (ok) .done else .failed, .acq_rel, .acquire) != null;
    }

    /// UI side. Returns true if the worker is done, meaning the UI must free it.
    fn abandon(s: *Shared) bool {
        return s.state.cmpxchgStrong(.running, .abandoned, .acq_rel, .acquire) != null;
    }

    pub fn get(s: *const Shared) TaskState {
        return s.state.load(.acquire);
    }
};

// ── Marketplace search ──────────────────────────────────────────────────────

pub const MarketTask = struct {
    shared: Shared = .{},
    source: config.ExploreSource,
    query_kind: std.meta.Tag(market.Query),
    query_text: []u8,
    page: u32,
    result: market.Page = .{},
    categories: ?std.ArrayList([]u8) = null,
    want_categories: bool = false,

    pub fn start(source: config.ExploreSource, query: market.Query, page: u32, want_categories: bool) !*MarketTask {
        const t = try gpa.create(MarketTask);
        t.* = .{
            .source = source,
            .query_kind = query,
            .query_text = try gpa.dupe(u8, switch (query) {
                .trending => "",
                .search, .category => |s| s,
            }),
            .page = page,
            .want_categories = want_categories,
        };
        const thread = std.Thread.spawn(.{}, work, .{t}) catch |err| {
            t.free();
            return err;
        };
        thread.detach();
        return t;
    }

    fn work(t: *MarketTask) void {
        const query: market.Query = switch (t.query_kind) {
            .trending => .trending,
            .search => .{ .search = t.query_text },
            .category => .{ .category = t.query_text },
        };
        var ok = true;
        if (market.fetch(t.source, query, t.page)) |page| {
            t.result = page;
        } else |err| {
            std.log.warn("marketplace: {s}", .{@errorName(err)});
            ok = false;
        }
        if (t.want_categories and t.source == .soundbuttonsworld) {
            t.categories = market.fetchSbwCategories() catch null;
        }
        if (t.shared.finish(ok)) t.free();
    }

    pub fn state(t: *const MarketTask) TaskState {
        return t.shared.get();
    }

    /// UI no longer cares; frees now or when the worker ends
    pub fn release(t: *MarketTask) void {
        if (t.shared.abandon()) t.free();
    }

    fn free(t: *MarketTask) void {
        t.result.deinit();
        if (t.categories) |*cats| {
            for (cats.items) |s| gpa.free(s);
            cats.deinit(gpa);
        }
        gpa.free(t.query_text);
        gpa.destroy(t);
    }
};

// ── YouTube / SoundCloud search ─────────────────────────────────────────────

pub const MediaTask = struct {
    shared: Shared = .{},
    platform: tools.Platform,
    query: []u8,
    count: u32,
    results: std.ArrayList(tools.MediaResult) = .empty,

    pub fn start(platform: tools.Platform, query: []const u8, count: u32) !*MediaTask {
        const t = try gpa.create(MediaTask);
        t.* = .{ .platform = platform, .query = try gpa.dupe(u8, query), .count = count };
        const thread = std.Thread.spawn(.{}, work, .{t}) catch |err| {
            t.free();
            return err;
        };
        thread.detach();
        return t;
    }

    fn work(t: *MediaTask) void {
        var ok = true;
        tools.search(t.platform, t.query, t.count, &t.results) catch |err| {
            std.log.warn("search: {s}", .{@errorName(err)});
            ok = false;
        };
        if (t.shared.finish(ok)) t.free();
    }

    pub fn state(t: *const MediaTask) TaskState {
        return t.shared.get();
    }

    pub fn release(t: *MediaTask) void {
        if (t.shared.abandon()) t.free();
    }

    fn free(t: *MediaTask) void {
        for (t.results.items) |r| r.deinit();
        t.results.deinit(gpa);
        gpa.free(t.query);
        gpa.destroy(t);
    }
};

// ── Previews ────────────────────────────────────────────────────────────────

/// Downloads a marketplace sound into the preview cache (once)
pub const PreviewTask = struct {
    shared: Shared = .{},
    url: []u8,
    path: []u8,
    progress: net.Progress = .{},

    pub fn start(url: []const u8) !*PreviewTask {
        const t = try gpa.create(PreviewTask);
        t.* = .{ .url = try gpa.dupe(u8, url), .path = try previewPath(url) };
        if (sys.exists(t.path)) {
            t.shared.state.store(.done, .release);
            return t;
        }
        const thread = std.Thread.spawn(.{}, work, .{t}) catch |err| {
            t.free();
            return err;
        };
        thread.detach();
        return t;
    }

    fn work(t: *PreviewTask) void {
        const tmp = std.fmt.allocPrint(gpa, "{s}.part", .{t.path}) catch {
            if (t.shared.finish(false)) t.free();
            return;
        };
        defer gpa.free(tmp);
        var ok = true;
        net.download(t.url, tmp, &t.progress) catch {
            ok = false;
        };
        if (ok) sys.rename(tmp, t.path) catch {
            ok = false;
        };
        if (t.shared.finish(ok)) t.free();
    }

    pub fn state(t: *const PreviewTask) TaskState {
        return t.shared.get();
    }

    pub fn release(t: *PreviewTask) void {
        if (t.shared.abandon()) t.free();
    }

    fn free(t: *PreviewTask) void {
        gpa.free(t.url);
        gpa.free(t.path);
        gpa.destroy(t);
    }
};

pub fn previewPath(url: []const u8) ![]u8 {
    const ext = std.fs.path.extension(url);
    const safe_ext = if (library.isAudioFile(url)) ext else ".mp3";
    return cachePath("previews", url, safe_ext);
}

// ── Download manager ────────────────────────────────────────────────────────

pub const Kind = enum { sound, media, tool, edit };
pub const State = enum(u8) { queued, running, done, failed, canceled };

pub const Job = struct {
    id: u32,
    kind: Kind,
    title: []u8,
    url: []u8, // remote URL, or the input file for edits
    local_source: []u8 = &.{}, // already-downloaded copy (preview cache)
    workspace_dir: []u8 = &.{},
    workspace_name: []u8 = &.{},
    sound_name: []u8 = &.{},
    sound_uid: u32 = 0,
    tool: tools.Tool = .ytdlp,
    media: tools.MediaOptions = .{},
    post: tools.ProcessOptions = .{},
    use_ffmpeg: bool = false,

    state: std.atomic.Value(State) = .init(.queued),
    stage: std.atomic.Value(u8) = .init(0),
    progress: net.Progress = .{},
    err_buf: [200]u8 = undefined,
    err_len: usize = 0,
    /// done: file name inside workspace_dir (sound/media) or temp file (edit)
    result: []u8 = &.{},
    handled: bool = false,
    created: i64 = 0,

    pub fn errorText(j: *const Job) []const u8 {
        return j.err_buf[0..j.err_len];
    }

    pub fn getState(j: *const Job) State {
        return j.state.load(.acquire);
    }

    fn fail(j: *Job, err: anyerror) void {
        const msg = switch (err) {
            error.Canceled => "Canceled",
            error.CurlMissing => "curl not found",
            error.YtDlpMissing => "yt-dlp is not installed",
            error.FfmpegMissing => "ffmpeg is not installed",
            error.DownloadFailed => "Download failed",
            error.FfmpegFailed => "Audio conversion failed",
            error.BinaryNotFound, error.UnpackFailed => "Could not unpack the archive",
            else => @errorName(err),
        };
        j.err_len = @min(msg.len, j.err_buf.len);
        @memcpy(j.err_buf[0..j.err_len], msg[0..j.err_len]);
        j.state.store(if (err == error.Canceled) .canceled else .failed, .release);
    }

    fn deinit(j: *Job) void {
        gpa.free(j.title);
        gpa.free(j.url);
        gpa.free(j.local_source);
        gpa.free(j.workspace_dir);
        gpa.free(j.workspace_name);
        gpa.free(j.sound_name);
        gpa.free(j.result);
        gpa.destroy(j);
    }
};

pub const JobSpec = struct {
    kind: Kind,
    title: []const u8,
    url: []const u8 = "",
    local_source: []const u8 = "",
    workspace_dir: []const u8 = "",
    workspace_name: []const u8 = "",
    sound_name: []const u8 = "",
    sound_uid: u32 = 0,
    tool: tools.Tool = .ytdlp,
    media: tools.MediaOptions = .{},
    post: tools.ProcessOptions = .{},
    use_ffmpeg: bool = false,
};

pub const max_parallel = 3;

pub const Manager = struct {
    jobs: std.ArrayList(*Job) = .empty,
    next_id: u32 = 1,

    pub fn add(m: *Manager, spec: JobSpec) !*Job {
        const j = try gpa.create(Job);
        j.* = .{
            .id = m.next_id,
            .kind = spec.kind,
            .title = try gpa.dupe(u8, spec.title),
            .url = try gpa.dupe(u8, spec.url),
            .local_source = try gpa.dupe(u8, spec.local_source),
            .workspace_dir = try gpa.dupe(u8, spec.workspace_dir),
            .workspace_name = try gpa.dupe(u8, spec.workspace_name),
            .sound_name = try gpa.dupe(u8, spec.sound_name),
            .sound_uid = spec.sound_uid,
            .tool = spec.tool,
            .media = spec.media,
            .post = spec.post,
            .use_ffmpeg = spec.use_ffmpeg,
            .created = library.now(),
        };
        m.next_id += 1;
        try m.jobs.append(gpa, j);
        return j;
    }

    /// Starts queued jobs and returns finished ones that still need handling
    pub fn update(m: *Manager) ?*Job {
        var running: usize = 0;
        for (m.jobs.items) |j| {
            if (j.getState() == .running) running += 1;
        }
        for (m.jobs.items) |j| {
            if (running >= max_parallel) break;
            if (j.getState() != .queued) continue;
            j.state.store(.running, .release);
            const thread = std.Thread.spawn(.{}, run, .{j}) catch |err| {
                j.fail(err);
                continue;
            };
            thread.detach();
            running += 1;
        }
        for (m.jobs.items) |j| {
            if (j.handled) continue;
            switch (j.getState()) {
                .done, .failed, .canceled => {
                    j.handled = true;
                    return j;
                },
                else => {},
            }
        }
        return null;
    }

    pub fn activeCount(m: *const Manager) usize {
        var n: usize = 0;
        for (m.jobs.items) |j| {
            switch (j.getState()) {
                .queued, .running => n += 1,
                else => {},
            }
        }
        return n;
    }

    pub fn isInstalling(m: *const Manager, tool: tools.Tool) ?*Job {
        for (m.jobs.items) |j| {
            if (j.kind != .tool or j.tool != tool) continue;
            switch (j.getState()) {
                .queued, .running => return j,
                else => {},
            }
        }
        return null;
    }

    pub fn cancel(_: *Manager, j: *Job) void {
        if (j.getState() == .queued) {
            j.fail(error.Canceled);
        } else {
            j.progress.cancel.store(true, .release);
        }
    }

    /// Drops finished jobs from the list
    pub fn clearFinished(m: *Manager) void {
        var i: usize = 0;
        while (i < m.jobs.items.len) {
            const j = m.jobs.items[i];
            const finished = switch (j.getState()) {
                .done, .failed, .canceled => j.handled,
                else => false,
            };
            if (finished) {
                _ = m.jobs.orderedRemove(i);
                j.deinit();
            } else i += 1;
        }
    }

    pub fn retry(_: *Manager, j: *Job) void {
        j.handled = false;
        j.err_len = 0;
        j.progress = .{};
        j.stage.store(0, .release);
        j.state.store(.queued, .release);
    }

    pub fn deinit(m: *Manager) void {
        // Running workers still reference their jobs; ask them to stop and leak those
        for (m.jobs.items) |j| {
            j.progress.cancel.store(true, .release);
            if (j.getState() != .running) j.deinit();
        }
        m.jobs.deinit(gpa);
    }
};

fn run(j: *Job) void {
    runInner(j) catch |err| {
        j.fail(err);
        return;
    };
    j.progress.set(1);
    j.state.store(.done, .release);
}

fn runInner(j: *Job) !void {
    switch (j.kind) {
        .tool => try tools.install(j.tool, &j.progress, &j.stage),
        .sound => {
            // 1. Fetch the file (or reuse the preview cache)
            const ext = blk: {
                const e = std.fs.path.extension(j.url);
                break :blk if (library.isAudioFile(j.url)) e else ".mp3";
            };
            const tmp = try std.fmt.allocPrint(gpa, "{s}" ++ sys.sep ++ "downloads" ++ sys.sep ++ "job-{d}{s}", .{ cache_dir, j.id, ext });
            defer gpa.free(tmp);
            if (j.local_source.len > 0 and sys.exists(j.local_source)) {
                try sys.copyFile(j.local_source, tmp);
            } else {
                try net.download(j.url, tmp, &j.progress);
            }
            defer sys.deleteFile(tmp);
            try finishSound(j, tmp);
        },
        .media => {
            const dir = try std.fmt.allocPrint(gpa, "{s}" ++ sys.sep ++ "downloads" ++ sys.sep ++ "job-{d}", .{ cache_dir, j.id });
            defer {
                sys.deleteTree(dir);
                gpa.free(dir);
            }
            sys.deleteTree(dir);
            const produced = try tools.downloadMedia(j.url, dir, j.media, &j.progress, &j.stage);
            defer gpa.free(produced);
            try finishSound(j, produced);
        },
        .edit => {
            j.stage.store(2, .release);
            j.progress.set(-1);
            const ext = std.fs.path.extension(j.url);
            const out = try std.fmt.allocPrint(gpa, "{s}" ++ sys.sep ++ "downloads" ++ sys.sep ++ "edit-{d}{s}", .{ cache_dir, j.id, ext });
            errdefer {
                sys.deleteFile(out);
                gpa.free(out);
            }
            var post = j.post;
            post.format = formatOf(ext);
            try tools.process(j.url, out, post);
            j.result = out;
        },
    }
}

fn formatOf(ext: []const u8) config.AudioFormat {
    if (std.ascii.eqlIgnoreCase(ext, ".ogg")) return .ogg;
    if (std.ascii.eqlIgnoreCase(ext, ".wav")) return .wav;
    return .mp3;
}

/// Optional ffmpeg pass, then moves the file into the workspace folder
fn finishSound(j: *Job, input: []const u8) !void {
    var source: []const u8 = input;
    var processed: ?[]u8 = null;
    defer if (processed) |p| {
        sys.deleteFile(p);
        gpa.free(p);
    };
    if (j.use_ffmpeg and tools.available(.ffmpeg)) {
        j.stage.store(2, .release);
        j.progress.set(-1);
        const out = try std.fmt.allocPrint(gpa, "{s}.processed{s}", .{ input, tools.extensionFor(j.post.format) });
        processed = out;
        try tools.process(input, out, j.post);
        source = out;
    }

    const ext = std.fs.path.extension(source);
    const name = try library.uniqueName(j.workspace_dir, j.sound_name, ext);
    errdefer gpa.free(name);
    const dest = try sys.join(&.{ j.workspace_dir, name });
    defer gpa.free(dest);
    sys.rename(source, dest) catch try sys.copyFile(source, dest);
    j.result = name;
}

// ── Thumbnails ──────────────────────────────────────────────────────────────

const ThumbState = enum(u8) { pending, loading, file_ready, failed, loaded };

const Thumb = struct {
    state: std.atomic.Value(ThumbState) = .init(.pending),
    url: []u8,
    path: []u8,
    texture: c.Texture = undefined,
};

var thumbs: std.StringHashMapUnmanaged(*Thumb) = .empty;
var thumbs_loading: std.atomic.Value(u32) = .init(0);

/// Returns the thumbnail texture once it is downloaded and decoded.
/// Images are center-cropped to `aspect` (width / height).
pub fn thumbnail(url: []const u8, aspect: f32) ?c.Texture {
    if (url.len == 0) return null;
    const t = thumbs.get(url) orelse blk: {
        const nt = gpa.create(Thumb) catch return null;
        nt.* = .{ .url = gpa.dupe(u8, url) catch return null, .path = cachePath("thumbs", url, ".img") catch return null };
        thumbs.put(gpa, nt.url, nt) catch return null;
        if (sys.exists(nt.path)) nt.state.store(.file_ready, .release);
        break :blk nt;
    };
    switch (t.state.load(.acquire)) {
        .pending => {
            if (thumbs_loading.load(.acquire) < 4) {
                t.state.store(.loading, .release);
                _ = thumbs_loading.fetchAdd(1, .acq_rel);
                const thread = std.Thread.spawn(.{}, fetchThumb, .{t}) catch {
                    t.state.store(.failed, .release);
                    _ = thumbs_loading.fetchSub(1, .acq_rel);
                    return null;
                };
                thread.detach();
            }
            return null;
        },
        .file_ready => {
            loadThumbTexture(t, aspect) catch {
                t.state.store(.failed, .release);
                return null;
            };
            t.state.store(.loaded, .release);
            return t.texture;
        },
        .loaded => return t.texture,
        .loading, .failed => return null,
    }
}

fn fetchThumb(t: *Thumb) void {
    defer _ = thumbs_loading.fetchSub(1, .acq_rel);
    var progress: net.Progress = .{};
    net.download(t.url, t.path, &progress) catch {
        t.state.store(.failed, .release);
        return;
    };
    t.state.store(.file_ready, .release);
}

fn loadThumbTexture(t: *Thumb, aspect: f32) !void {
    const data = try sys.readFile(t.path, 16 * 1024 * 1024);
    defer gpa.free(data);
    if (data.len < 4) return error.BadImage;
    const kind: [:0]const u8 = if (data[0] == 0xFF and data[1] == 0xD8) ".jpg" else if (data[0] == 0x89 and data[1] == 'P') ".png" else return error.UnsupportedImage;
    var img = c.LoadImageFromMemory(kind.ptr, data.ptr, @intCast(data.len));
    if (img.data == null) return error.BadImage;
    defer c.UnloadImage(img);

    // Center crop to the wanted aspect, then shrink
    const w: f32 = @floatFromInt(img.width);
    const h: f32 = @floatFromInt(img.height);
    var crop: c.Rectangle = .{ .x = 0, .y = 0, .width = w, .height = h };
    if (w / h > aspect) {
        crop.width = h * aspect;
        crop.x = (w - crop.width) / 2;
    } else {
        crop.height = w / aspect;
        crop.y = (h - crop.height) / 2;
    }
    c.ImageCrop(&img, crop);
    const target_w: c_int = @min(img.width, 360);
    const target_h: c_int = @intFromFloat(@as(f32, @floatFromInt(target_w)) / aspect);
    c.ImageResize(&img, target_w, target_h);
    t.texture = c.LoadTextureFromImage(img);
    c.SetTextureFilter(t.texture, c.TEXTURE_FILTER_BILINEAR);
}
