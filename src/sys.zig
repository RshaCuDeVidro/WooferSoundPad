//! Platform glue: file system, processes and well-known folders.
//! Paths are absolute and UTF-8 everywhere in the app.

const std = @import("std");
const builtin = @import("builtin");

pub const is_windows = builtin.os.tag == .windows;
pub const sep = std.fs.path.sep_str;
pub const exe_suffix = if (is_windows) ".exe" else "";

pub const gpa = std.heap.c_allocator;

pub var io: std.Io = undefined;
var env: *std.process.Environ.Map = undefined;

pub fn init(the_io: std.Io, environ: *std.process.Environ.Map) void {
    io = the_io;
    env = environ;
}

pub fn getenv(name: []const u8) ?[]const u8 {
    const v = env.get(name) orelse return null;
    return if (v.len == 0) null else v;
}

pub fn join(parts: []const []const u8) ![]u8 {
    return std.fs.path.join(gpa, parts);
}

/// Like `join` but returns a null-terminated string (for C APIs)
pub fn joinZ(parts: []const []const u8) ![:0]u8 {
    const p = try std.fs.path.join(gpa, parts);
    defer gpa.free(p);
    return gpa.dupeSentinel(u8, p, 0);
}

fn cwd() std.Io.Dir {
    return std.Io.Dir.cwd();
}

pub fn exists(path: []const u8) bool {
    cwd().access(io, path, .{}) catch return false;
    return true;
}

pub fn isDir(path: []const u8) bool {
    var d = cwd().openDir(io, path, .{}) catch return false;
    d.close(io);
    return true;
}

pub fn makePath(path: []const u8) !void {
    try cwd().createDirPath(io, path);
}

pub fn readFile(path: []const u8, max: usize) ![]u8 {
    return cwd().readFileAlloc(io, path, gpa, .limited(max));
}

pub fn writeFile(path: []const u8, data: []const u8) !void {
    try cwd().writeFile(io, .{ .sub_path = path, .data = data });
}

/// Writes to a temporary file first, so a crash never leaves a half-written file
pub fn writeFileAtomic(path: []const u8, data: []const u8) !void {
    const tmp = try std.fmt.allocPrint(gpa, "{s}.tmp", .{path});
    defer gpa.free(tmp);
    try writeFile(tmp, data);
    try cwd().rename(tmp, cwd(), path, io);
}

pub fn rename(from: []const u8, to: []const u8) !void {
    try cwd().rename(from, cwd(), to, io);
}

pub fn copyFile(from: []const u8, to: []const u8) !void {
    try cwd().copyFile(from, cwd(), to, io, .{});
}

pub fn deleteFile(path: []const u8) void {
    cwd().deleteFile(io, path) catch {};
}

pub fn deleteTree(path: []const u8) void {
    cwd().deleteTree(io, path) catch {};
}

pub fn fileSize(path: []const u8) u64 {
    const st = cwd().statFile(io, path, .{}) catch return 0;
    return st.size;
}

pub const DirEntry = struct {
    name: []u8,
    is_dir: bool,
};

/// Lists a directory. Free with `freeEntries`.
pub fn listDir(path: []const u8) ![]DirEntry {
    var dir = try cwd().openDir(io, path, .{ .iterate = true });
    defer dir.close(io);
    var list: std.ArrayList(DirEntry) = .empty;
    errdefer freeEntries(list.items);
    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.name.len == 0 or entry.name[0] == '.') continue;
        try list.append(gpa, .{
            .name = try gpa.dupe(u8, entry.name),
            .is_dir = entry.kind == .directory,
        });
    }
    return list.toOwnedSlice(gpa);
}

pub fn freeEntries(entries: []DirEntry) void {
    for (entries) |e| gpa.free(e.name);
    gpa.free(entries);
}

/// Finds a file named `name` anywhere under `root` (used after unpacking archives)
pub fn findFile(root: []const u8, name: []const u8) ?[]u8 {
    const entries = listDir(root) catch return null;
    defer freeEntries(entries);
    for (entries) |e| {
        if (!e.is_dir and std.ascii.eqlIgnoreCase(e.name, name)) return join(&.{ root, e.name }) catch null;
    }
    for (entries) |e| {
        if (!e.is_dir) continue;
        const child = join(&.{ root, e.name }) catch continue;
        defer gpa.free(child);
        if (findFile(child, name)) |found| return found;
    }
    return null;
}

/// Extracts a .zip archive with Zig's own unzipper (no external tools needed)
pub fn unzip(archive: []const u8, dest: []const u8) !void {
    try makePath(dest);
    var dir = try cwd().openDir(io, dest, .{});
    defer dir.close(io);
    const file = try cwd().openFile(io, archive, .{});
    defer file.close(io);
    var buf: [16 * 1024]u8 = undefined;
    var reader = file.reader(io, &buf);
    try std.zip.extract(dir, &reader, .{});
}

// ── Well-known folders ──────────────────────────────────────────────────────

fn home() []const u8 {
    if (is_windows) return getenv("USERPROFILE") orelse "C:\\";
    return getenv("HOME") orelse "/tmp";
}

pub var portable_root: ?[]u8 = null;

/// Portable mode: a `portable.txt` (or `portable`) file next to the executable
/// keeps every file inside the app's folder.
pub fn detectPortable() void {
    const dir = std.process.executableDirPathAlloc(io, gpa) catch return;
    for ([_][]const u8{ "portable.txt", "portable" }) |marker| {
        const p = join(&.{ dir, marker }) catch continue;
        defer gpa.free(p);
        if (exists(p)) {
            portable_root = join(&.{ dir, "data" }) catch null;
            break;
        }
    }
    gpa.free(dir);
}

/// Settings: ~/.config/WooferSoundPad or %APPDATA%\WooferSoundPad
pub fn configDir() ![]u8 {
    if (portable_root) |p| return gpa.dupe(u8, p);
    if (is_windows) return join(&.{ getenv("APPDATA") orelse home(), "WooferSoundPad" });
    if (getenv("XDG_CONFIG_HOME")) |x| return join(&.{ x, "WooferSoundPad" });
    return join(&.{ home(), ".config", "WooferSoundPad" });
}

/// Tools, cache: ~/.local/share/WooferSoundPad or %LOCALAPPDATA%\WooferSoundPad
pub fn dataDir() ![]u8 {
    if (portable_root) |p| return gpa.dupe(u8, p);
    if (is_windows) return join(&.{ getenv("LOCALAPPDATA") orelse home(), "WooferSoundPad" });
    if (getenv("XDG_DATA_HOME")) |x| return join(&.{ x, "WooferSoundPad" });
    return join(&.{ home(), ".local", "share", "WooferSoundPad" });
}

/// Default sound library: ~/Music/WooferSoundPad
pub fn defaultLibraryDir() ![]u8 {
    if (portable_root) |p| return join(&.{ p, "Library" });
    return join(&.{ home(), "Music", "WooferSoundPad" });
}

pub fn runtimeDir() []const u8 {
    if (getenv("XDG_RUNTIME_DIR")) |r| return r;
    return "/tmp";
}

// ── Processes ───────────────────────────────────────────────────────────────

/// Resolves an executable on PATH. Returns an owned absolute path.
pub fn which(name: []const u8) ?[]u8 {
    if (std.fs.path.isAbsolute(name)) return if (exists(name)) gpa.dupe(u8, name) catch null else null;
    const path = getenv(if (is_windows) "Path" else "PATH") orelse getenv("PATH") orelse return null;
    var it = std.mem.tokenizeScalar(u8, path, if (is_windows) ';' else ':');
    while (it.next()) |dir| {
        const full = std.fmt.allocPrint(gpa, "{s}" ++ sep ++ "{s}{s}", .{ dir, name, if (is_windows and !std.mem.endsWith(u8, name, ".exe")) ".exe" else "" }) catch continue;
        if (exists(full) and !isDir(full)) return full;
        gpa.free(full);
    }
    return null;
}

/// Windows ships curl.exe and tar.exe in System32 since Windows 10 1803.
/// Calling them by full path avoids picking up Git/MSYS versions on PATH.
pub fn systemTool(name: []const u8) []const u8 {
    if (!is_windows) return name;
    const root = getenv("SystemRoot") orelse "C:\\Windows";
    const p = std.fmt.allocPrint(gpa, "{s}\\System32\\{s}.exe", .{ root, name }) catch return name;
    if (exists(p)) return p;
    gpa.free(p);
    return name;
}

pub const RunResult = struct {
    ok: bool,
    exit_code: u8,
    stdout: []u8,
    stderr: []u8,

    pub fn deinit(r: RunResult) void {
        gpa.free(r.stdout);
        gpa.free(r.stderr);
    }
};

/// Runs a program to completion and captures its output
pub fn run(argv: []const []const u8, max_output: usize) !RunResult {
    const res = try std.process.run(gpa, io, .{
        .argv = argv,
        .stdout_limit = .limited(max_output),
        .stderr_limit = .limited(1024 * 1024),
        .create_no_window = true,
    });
    const code: u8 = switch (res.term) {
        .exited => |c| c,
        else => 255,
    };
    return .{ .ok = code == 0, .exit_code = code, .stdout = res.stdout, .stderr = res.stderr };
}

/// Starts a program and forgets about it (a helper thread reaps it)
pub fn spawnDetached(argv: []const []const u8) void {
    var child = std.process.spawn(io, .{
        .argv = argv,
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
        .create_no_window = true,
    }) catch return;
    const t = std.Thread.spawn(.{}, reap, .{child}) catch {
        child.kill(io);
        return;
    };
    t.detach();
}

fn reap(child_in: std.process.Child) void {
    var child = child_in;
    _ = child.wait(io) catch {};
}

pub fn openFolder(path: []const u8) void {
    if (is_windows) {
        spawnDetached(&.{ "explorer.exe", path });
    } else {
        spawnDetached(&.{ "xdg-open", path });
    }
}

/// Opens the folder containing `file` with the file selected when possible
pub fn revealFile(file: []const u8) void {
    if (is_windows) {
        const arg = std.fmt.allocPrint(gpa, "/select,{s}", .{file}) catch return;
        defer gpa.free(arg);
        spawnDetached(&.{ "explorer.exe", arg });
    } else {
        openFolder(std.fs.path.dirname(file) orelse file);
    }
}

pub fn openUrl(url: []const u8) void {
    if (is_windows) {
        spawnDetached(&.{ "rundll32.exe", "url.dll,FileProtocolHandler", url });
    } else {
        spawnDetached(&.{ "xdg-open", url });
    }
}

pub fn makeExecutable(path: []const u8) void {
    if (is_windows) return;
    const res = run(&.{ "chmod", "755", path }, 1024) catch return;
    res.deinit();
}

// ── Small string helpers ────────────────────────────────────────────────────

/// Turns any text into a safe file name (keeps UTF-8, drops path separators
/// and characters Windows rejects)
pub fn sanitizeFileName(out: []u8, name: []const u8) []const u8 {
    var n: usize = 0;
    for (name) |ch| {
        if (n >= out.len) break;
        const bad = ch < 32 or switch (ch) {
            '/', '\\', ':', '*', '?', '"', '<', '>', '|' => true,
            else => false,
        };
        out[n] = if (bad) '_' else ch;
        n += 1;
    }
    // Windows dislikes trailing dots and spaces
    while (n > 0 and (out[n - 1] == '.' or out[n - 1] == ' ')) n -= 1;
    // Never cut a UTF-8 sequence in half
    while (n > 0 and out[n - 1] & 0xC0 == 0x80) {
        var start = n - 1;
        while (start > 0 and out[start] & 0xC0 == 0x80) start -= 1;
        const len = std.unicode.utf8ByteSequenceLength(out[start]) catch 1;
        if (start + len <= n) break;
        n = start;
    }
    if (n == 0) {
        const fallback = "sound";
        @memcpy(out[0..fallback.len], fallback);
        return out[0..fallback.len];
    }
    return out[0..n];
}

test "sanitizeFileName" {
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("a_b_c", sanitizeFileName(&buf, "a/b:c"));
    try std.testing.expectEqualStrings("Ação", sanitizeFileName(&buf, "Ação..."));
    try std.testing.expectEqualStrings("sound", sanitizeFileName(&buf, "..."));
}
