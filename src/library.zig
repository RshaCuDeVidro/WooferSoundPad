//! The sound library: one folder per workspace, each holding its audio files
//! plus a `workspace.json` with names, colors, hotkeys, volumes and stats.
//! Files dropped into a workspace folder by hand are picked up on reload.

const std = @import("std");
const sys = @import("sys.zig");
const audio = @import("audio.zig");
const fx = @import("fx.zig");

const gpa = sys.gpa;

pub const audio_extensions = [_][]const u8{ ".mp3", ".wav", ".ogg", ".flac" };

pub fn isAudioFile(name: []const u8) bool {
    const ext = std.fs.path.extension(name);
    for (audio_extensions) |e| {
        if (std.ascii.eqlIgnoreCase(ext, e)) return true;
    }
    return false;
}

pub const Sound = struct {
    file: []u8, // file name inside the workspace folder
    name: []u8,
    color: u8 = 0,
    volume: f32 = 1,
    hotkey: []u8 = &.{},
    favorite: bool = false,
    plays: u32 = 0,
    added: i64 = 0,
    source: []u8 = &.{},
    // Playback settings, applied live (the file is never changed by these)
    trim_start: f32 = 0,
    trim_end: f32 = 0,
    loop: bool = false,
    speed: f32 = 1,
    fade_in: f32 = 0,
    fade_out: f32 = 0,
    /// Live effect chain (the file is never changed by it)
    fx: fx.Chain = .{},
    /// Stable id inside the workspace; variants of one file share `file` but not `uid`
    uid: u32 = 0,
    play_seconds: f32 = 0,
    last_played: i64 = 0,
    /// Measured loudness in dB (0 = not measured yet, 1 = can't be measured)
    loudness: f32 = 0,
    peak_db: f32 = 0,

    // Runtime only
    audio_id: c_int = -1,
    /// Smoothed output level for meters (0..1)
    level: f32 = 0,

    fn deinit(s: *Sound) void {
        gpa.free(s.file);
        gpa.free(s.name);
        gpa.free(s.hotkey);
        gpa.free(s.source);
    }

    pub fn setName(s: *Sound, name: []const u8) !void {
        const copy = try gpa.dupe(u8, name);
        gpa.free(s.name);
        s.name = copy;
    }

    pub fn setHotkey(s: *Sound, hotkey: []const u8) !void {
        const copy = try gpa.dupe(u8, hotkey);
        gpa.free(s.hotkey);
        s.hotkey = copy;
    }

    pub fn params(s: *const Sound) audio.Params {
        return .{
            .trim_start = s.trim_start,
            .trim_end = s.trim_end,
            .loop = s.loop,
            .speed = s.speed,
            .fade_in = s.fade_in,
            .fade_out = s.fade_out,
        };
    }

    pub fn setParams(s: *Sound, p: audio.Params) void {
        s.trim_start = p.trim_start;
        s.trim_end = p.trim_end;
        s.loop = p.loop;
        s.speed = p.speed;
        s.fade_in = p.fade_in;
        s.fade_out = p.fade_out;
    }

    /// True when any playback setting differs from a plain play
    pub fn hasEffects(s: *const Sound) bool {
        return s.trim_start > 0 or s.trim_end > 0 or s.loop or s.speed != 1 or s.fade_in > 0 or s.fade_out > 0 or s.fx.active() > 0;
    }
};

pub const Workspace = struct {
    name: []u8,
    dir: []u8,
    icon: u8 = 0,
    color: u8 = 0,
    sounds: std.ArrayList(Sound) = .empty,

    fn deinit(w: *Workspace) void {
        for (w.sounds.items) |*s| s.deinit();
        w.sounds.deinit(gpa);
        gpa.free(w.name);
        gpa.free(w.dir);
    }

    pub fn soundPath(w: *const Workspace, s: *const Sound) ![:0]u8 {
        return sys.joinZ(&.{ w.dir, s.file });
    }

    pub fn findByFile(w: *const Workspace, file: []const u8) ?usize {
        for (w.sounds.items, 0..) |s, i| {
            if (std.mem.eql(u8, s.file, file)) return i;
        }
        return null;
    }

    pub fn findByUid(w: *const Workspace, uid: u32) ?usize {
        for (w.sounds.items, 0..) |s, i| {
            if (s.uid == uid) return i;
        }
        return null;
    }

    /// How many sounds play this file (variants share one)
    pub fn fileUsers(w: *const Workspace, file: []const u8) usize {
        var n: usize = 0;
        for (w.sounds.items) |s| {
            if (std.mem.eql(u8, s.file, file)) n += 1;
        }
        return n;
    }

    pub fn newUid(w: *const Workspace) u32 {
        var top: u32 = 0;
        for (w.sounds.items) |s| top = @max(top, s.uid);
        return top + 1;
    }

    /// Gives every sound a unique uid (old files have none)
    fn fixUids(w: *Workspace) void {
        for (w.sounds.items, 0..) |*s, i| {
            var dup = s.uid == 0;
            for (w.sounds.items[0..i]) |other| {
                if (other.uid == s.uid) dup = true;
            }
            if (dup) s.uid = w.newUid();
        }
    }
};

// ── JSON shapes ─────────────────────────────────────────────────────────────

const SoundJson = struct {
    file: []const u8,
    name: []const u8 = "",
    color: u8 = 0,
    volume: f32 = 1,
    hotkey: []const u8 = "",
    favorite: bool = false,
    plays: u32 = 0,
    added: i64 = 0,
    source: []const u8 = "",
    trim_start: f32 = 0,
    trim_end: f32 = 0,
    loop: bool = false,
    speed: f32 = 1,
    fade_in: f32 = 0,
    fade_out: f32 = 0,
    fx: []const fx.Stored = &.{},
    uid: u32 = 0,
    play_seconds: f32 = 0,
    last_played: i64 = 0,
    loudness: f32 = 0,
    peak_db: f32 = 0,
};

const WorkspaceJson = struct {
    version: u32 = 1,
    icon: u8 = 0,
    color: u8 = 0,
    sounds: []const SoundJson = &.{},
};

const meta_file = "workspace.json";

// ── Library ─────────────────────────────────────────────────────────────────

pub const Library = struct {
    root: []u8 = &.{},
    workspaces: std.ArrayList(Workspace) = .empty,

    pub fn deinit(lib: *Library) void {
        for (lib.workspaces.items) |*w| w.deinit();
        lib.workspaces.deinit(gpa);
        gpa.free(lib.root);
    }

    /// (Re)loads every workspace under `root`. Creates a first workspace when empty.
    pub fn open(lib: *Library, root: []const u8, default_name: []const u8) !void {
        for (lib.workspaces.items) |*w| w.deinit();
        lib.workspaces.clearRetainingCapacity();
        const new_root = try gpa.dupe(u8, root);
        gpa.free(lib.root);
        lib.root = new_root;

        try sys.makePath(root);
        const entries = try sys.listDir(root);
        defer sys.freeEntries(entries);
        for (entries) |e| {
            if (!e.is_dir) continue;
            lib.loadWorkspace(e.name) catch |err| {
                std.log.warn("skipping workspace {s}: {s}", .{ e.name, @errorName(err) });
            };
        }
        if (lib.workspaces.items.len == 0) _ = try lib.createWorkspace(default_name);
        lib.sortWorkspaces();
    }

    fn sortWorkspaces(lib: *Library) void {
        std.mem.sort(Workspace, lib.workspaces.items, {}, struct {
            fn lt(_: void, a: Workspace, b: Workspace) bool {
                return std.ascii.lessThanIgnoreCase(a.name, b.name);
            }
        }.lt);
    }

    fn loadWorkspace(lib: *Library, name: []const u8) !void {
        var ws: Workspace = .{
            .name = try gpa.dupe(u8, name),
            .dir = try sys.join(&.{ lib.root, name }),
            .color = @intCast(std.hash.Wyhash.hash(7, name) % 12 + 1),
        };
        errdefer ws.deinit();

        // Metadata first, so order and settings survive
        const meta_path = try sys.join(&.{ ws.dir, meta_file });
        defer gpa.free(meta_path);
        if (sys.readFile(meta_path, 8 * 1024 * 1024)) |data| {
            defer gpa.free(data);
            if (std.json.parseFromSlice(WorkspaceJson, gpa, data, .{ .ignore_unknown_fields = true })) |parsed| {
                defer parsed.deinit();
                ws.icon = parsed.value.icon;
                ws.color = parsed.value.color;
                for (parsed.value.sounds) |sj| {
                    if (sj.file.len == 0 or std.mem.indexOfAny(u8, sj.file, "/\\") != null) continue;
                    try ws.sounds.append(gpa, .{
                        .file = try gpa.dupe(u8, sj.file),
                        .name = try gpa.dupe(u8, if (sj.name.len > 0) sj.name else stem(sj.file)),
                        .color = sj.color,
                        .volume = std.math.clamp(sj.volume, 0, 2),
                        .hotkey = try gpa.dupe(u8, sj.hotkey),
                        .favorite = sj.favorite,
                        .plays = sj.plays,
                        .added = sj.added,
                        .source = try gpa.dupe(u8, sj.source),
                        .trim_start = @max(sj.trim_start, 0),
                        .trim_end = @max(sj.trim_end, 0),
                        .loop = sj.loop,
                        .speed = std.math.clamp(sj.speed, 0.25, 4),
                        .fade_in = std.math.clamp(sj.fade_in, 0, 30),
                        .fade_out = std.math.clamp(sj.fade_out, 0, 30),
                        .fx = fx.Chain.fromStored(sj.fx),
                        .uid = sj.uid,
                        .play_seconds = if (std.math.isFinite(sj.play_seconds)) @max(sj.play_seconds, 0) else 0,
                        .last_played = sj.last_played,
                        .loudness = if (std.math.isFinite(sj.loudness)) std.math.clamp(sj.loudness, -100, 1) else 0,
                        .peak_db = if (std.math.isFinite(sj.peak_db)) std.math.clamp(sj.peak_db, -100, 6) else 0,
                    });
                }
            } else |err| std.log.warn("{s}: {s}", .{ meta_path, @errorName(err) });
        } else |_| {}

        // Then reconcile with what is actually on disk
        const entries = try sys.listDir(ws.dir);
        defer sys.freeEntries(entries);
        var i: usize = 0;
        while (i < ws.sounds.items.len) {
            var found = false;
            for (entries) |e| {
                if (std.mem.eql(u8, e.name, ws.sounds.items[i].file)) found = true;
            }
            if (found) i += 1 else {
                var gone = ws.sounds.orderedRemove(i);
                gone.deinit();
            }
        }
        for (entries) |e| {
            if (e.is_dir or !isAudioFile(e.name) or ws.findByFile(e.name) != null) continue;
            try ws.sounds.append(gpa, .{
                .file = try gpa.dupe(u8, e.name),
                .name = try gpa.dupe(u8, stem(e.name)),
                .color = autoColor(e.name),
                .added = now(),
            });
        }
        ws.fixUids();
        try lib.workspaces.append(gpa, ws);
    }

    pub fn find(lib: *const Library, name: []const u8) ?usize {
        for (lib.workspaces.items, 0..) |w, i| {
            if (std.mem.eql(u8, w.name, name)) return i;
        }
        return null;
    }

    pub fn createWorkspace(lib: *Library, raw_name: []const u8) !usize {
        var buf: [128]u8 = undefined;
        const base = sys.sanitizeFileName(&buf, std.mem.trim(u8, raw_name, " "));
        var name_buf: [160]u8 = undefined;
        var name: []const u8 = base;
        var n: usize = 2;
        while (lib.find(name) != null) : (n += 1) {
            name = try std.fmt.bufPrint(&name_buf, "{s} ({d})", .{ base, n });
        }
        const dir = try sys.join(&.{ lib.root, name });
        errdefer gpa.free(dir);
        try sys.makePath(dir);
        try lib.workspaces.append(gpa, .{ .name = try gpa.dupe(u8, name), .dir = dir, .color = @intCast(lib.workspaces.items.len % 12 + 1) });
        const idx = lib.workspaces.items.len - 1;
        try lib.save(idx);
        lib.sortWorkspaces();
        return lib.find(name).?;
    }

    pub fn renameWorkspace(lib: *Library, idx: usize, raw_name: []const u8) !void {
        var buf: [128]u8 = undefined;
        const name = sys.sanitizeFileName(&buf, std.mem.trim(u8, raw_name, " "));
        const ws = &lib.workspaces.items[idx];
        if (std.mem.eql(u8, name, ws.name)) return;
        if (lib.find(name) != null) return error.AlreadyExists;
        const new_dir = try sys.join(&.{ lib.root, name });
        errdefer gpa.free(new_dir);
        try sys.rename(ws.dir, new_dir);
        gpa.free(ws.dir);
        ws.dir = new_dir;
        const new_name = try gpa.dupe(u8, name);
        gpa.free(ws.name);
        ws.name = new_name;
        lib.sortWorkspaces();
    }

    /// Deletes the workspace folder and everything in it
    pub fn deleteWorkspace(lib: *Library, idx: usize) void {
        var ws = lib.workspaces.orderedRemove(idx);
        sys.deleteTree(ws.dir);
        ws.deinit();
    }

    pub fn save(lib: *Library, idx: usize) !void {
        const ws = &lib.workspaces.items[idx];
        var sounds = try gpa.alloc(SoundJson, ws.sounds.items.len);
        defer gpa.free(sounds);
        const stored = try gpa.alloc([fx.max]fx.Stored, ws.sounds.items.len);
        defer gpa.free(stored);
        for (ws.sounds.items, 0..) |*s, i| {
            sounds[i] = .{
                .file = s.file,
                .name = s.name,
                .color = s.color,
                .volume = s.volume,
                .hotkey = s.hotkey,
                .favorite = s.favorite,
                .plays = s.plays,
                .added = s.added,
                .source = s.source,
                .trim_start = s.trim_start,
                .trim_end = s.trim_end,
                .loop = s.loop,
                .speed = s.speed,
                .fade_in = s.fade_in,
                .fade_out = s.fade_out,
                .fx = s.fx.toStored(&stored[i]),
                .uid = s.uid,
                .play_seconds = s.play_seconds,
                .last_played = s.last_played,
                .loudness = s.loudness,
                .peak_db = s.peak_db,
            };
        }
        const doc: WorkspaceJson = .{ .icon = ws.icon, .color = ws.color, .sounds = sounds };
        const json = try std.json.Stringify.valueAlloc(gpa, doc, .{ .whitespace = .indent_2 });
        defer gpa.free(json);
        const meta_path = try sys.join(&.{ ws.dir, meta_file });
        defer gpa.free(meta_path);
        try sys.writeFileAtomic(meta_path, json);
    }

    /// Copies an audio file into the workspace. Returns the new sound's index.
    pub fn importFile(lib: *Library, idx: usize, src: []const u8) !usize {
        if (!isAudioFile(src)) return error.UnsupportedFormat;
        const ws = &lib.workspaces.items[idx];
        const base = std.fs.path.basename(src);
        const dest_name = try uniqueName(ws.dir, stem(base), std.fs.path.extension(base));
        defer gpa.free(dest_name);
        const dest = try sys.join(&.{ ws.dir, dest_name });
        defer gpa.free(dest);
        try sys.copyFile(src, dest);
        return lib.adopt(idx, dest_name, stem(base), "");
    }

    /// Registers a file that already sits in the workspace folder
    pub fn adopt(lib: *Library, idx: usize, file: []const u8, name: []const u8, source: []const u8) !usize {
        const ws = &lib.workspaces.items[idx];
        if (ws.findByFile(file)) |existing| return existing;
        try ws.sounds.append(gpa, .{
            .file = try gpa.dupe(u8, file),
            .name = try gpa.dupe(u8, name),
            .source = try gpa.dupe(u8, source),
            .color = autoColor(name),
            .added = now(),
            .uid = ws.newUid(),
        });
        lib.save(idx) catch {};
        return ws.sounds.items.len - 1;
    }

    /// Another pad for the same file, with its own name, settings and effects
    pub fn addVariant(lib: *Library, idx: usize, sound_idx: usize, name: []const u8, chain: fx.Chain) !usize {
        const ws = &lib.workspaces.items[idx];
        const src = ws.sounds.items[sound_idx];
        var v: Sound = .{
            .file = try gpa.dupe(u8, src.file),
            .name = try gpa.dupe(u8, name),
            .source = try gpa.dupe(u8, src.source),
            .color = src.color,
            .volume = src.volume,
            .added = now(),
            .uid = ws.newUid(),
            .fx = chain,
            .loudness = src.loudness,
            .peak_db = src.peak_db,
        };
        v.setParams(src.params());
        errdefer v.deinit();
        try ws.sounds.insert(gpa, sound_idx + 1, v);
        lib.save(idx) catch {};
        return sound_idx + 1;
    }

    pub fn removeSound(lib: *Library, idx: usize, sound_idx: usize, delete_file_wanted: bool) void {
        const ws = &lib.workspaces.items[idx];
        var s = ws.sounds.orderedRemove(sound_idx);
        // Variants of the same file keep it alive
        const delete_file = delete_file_wanted and ws.fileUsers(s.file) == 0;
        if (delete_file) {
            const p = sys.join(&.{ ws.dir, s.file }) catch null;
            if (p) |pp| {
                sys.deleteFile(pp);
                gpa.free(pp);
            }
        }
        s.deinit();
        lib.save(idx) catch {};
    }

    /// Moves a sound (and its file) to another workspace
    pub fn moveSound(lib: *Library, from: usize, sound_idx: usize, to: usize) !void {
        if (from == to) return;
        const src_ws = &lib.workspaces.items[from];
        const s = src_ws.sounds.items[sound_idx];
        const dst_ws = &lib.workspaces.items[to];
        const dest_name = try uniqueName(dst_ws.dir, stem(s.file), std.fs.path.extension(s.file));
        defer gpa.free(dest_name);
        const src_path = try sys.join(&.{ src_ws.dir, s.file });
        defer gpa.free(src_path);
        const dst_path = try sys.join(&.{ dst_ws.dir, dest_name });
        defer gpa.free(dst_path);
        if (src_ws.fileUsers(s.file) > 1) {
            // Other variants still play this file here
            try sys.copyFile(src_path, dst_path);
        } else {
            sys.rename(src_path, dst_path) catch {
                // Different drives: copy then delete
                try sys.copyFile(src_path, dst_path);
                sys.deleteFile(src_path);
            };
        }
        var moved = src_ws.sounds.orderedRemove(sound_idx);
        gpa.free(moved.file);
        moved.file = try gpa.dupe(u8, dest_name);
        moved.audio_id = -1;
        moved.uid = dst_ws.newUid();
        try dst_ws.sounds.append(gpa, moved);
        lib.save(from) catch {};
        lib.save(to) catch {};
    }
};

/// Stable palette color (1–12) for a name
pub fn autoColor(name: []const u8) u8 {
    return @intCast(std.hash.Wyhash.hash(42, name) % 12 + 1);
}

pub fn now() i64 {
    return std.Io.Timestamp.now(sys.io, .real).toSeconds();
}

/// File name without extension
pub fn stem(name: []const u8) []const u8 {
    const base = std.fs.path.basename(name);
    const ext = std.fs.path.extension(base);
    return base[0 .. base.len - ext.len];
}

/// "name.mp3", or "name (2).mp3" etc. if taken
pub fn uniqueName(dir: []const u8, raw_stem: []const u8, ext: []const u8) ![]u8 {
    var buf: [120]u8 = undefined;
    const clean = sys.sanitizeFileName(&buf, raw_stem);
    var n: usize = 1;
    while (n < 10000) : (n += 1) {
        const candidate = if (n == 1)
            try std.fmt.allocPrint(gpa, "{s}{s}", .{ clean, ext })
        else
            try std.fmt.allocPrint(gpa, "{s} ({d}){s}", .{ clean, n, ext });
        const full = try sys.join(&.{ dir, candidate });
        defer gpa.free(full);
        if (!sys.exists(full)) return candidate;
        gpa.free(candidate);
    }
    return error.TooManyFiles;
}

test "stem and audio detection" {
    try std.testing.expectEqualStrings("bruh", stem("/a/b/bruh.mp3"));
    try std.testing.expect(isAudioFile("x.MP3"));
    try std.testing.expect(!isAudioFile("x.txt"));
}
