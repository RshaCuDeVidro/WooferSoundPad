//! Command-line control of a running instance (Linux).
//!
//!   WooferSoundPad --play "bruh"     plays a sound from the active workspace
//!   WooferSoundPad --queue "bruh"    adds it to the play queue
//!   WooferSoundPad --stop            stops everything
//!   WooferSoundPad --pause           pauses / resumes everything
//!   WooferSoundPad --workspace Memes switches workspace
//!
//! The running app listens on a FIFO in $XDG_RUNTIME_DIR. This is how
//! Wayland users bind sounds to desktop shortcuts (KDE, GNOME, Hyprland, Sway…),
//! since Wayland doesn't let apps grab keys globally.

const std = @import("std");
const builtin = @import("builtin");
const sys = @import("sys.zig");

pub const supported = builtin.os.tag == .linux;

extern "c" fn mkfifo(path: [*:0]const u8, mode: c_uint) c_int;
extern "c" fn open(path: [*:0]const u8, flags: c_int, ...) c_int;
extern "c" fn read(fd: c_int, buf: [*]u8, n: usize) isize;
extern "c" fn write(fd: c_int, buf: [*]const u8, n: usize) isize;
extern "c" fn close(fd: c_int) c_int;

const O_RDONLY = 0;
const O_WRONLY = 1;
const O_NONBLOCK = 0o4000;

pub const Verb = enum { play, queue, stop, pause, next, random, mute_voice, workspace, show, quit };

pub const Command = struct {
    verb: Verb,
    arg: [256]u8 = undefined,
    arg_len: usize = 0,

    pub fn argument(cmd: *const Command) []const u8 {
        return cmd.arg[0..cmd.arg_len];
    }
};

var fifo_path_buf: [512]u8 = undefined;
var fifo_path: [:0]const u8 = "";
var mutex: std.Io.Mutex = .init;
var queue: [16]Command = undefined;
var queue_len: usize = 0;
var running = std.atomic.Value(bool).init(false);

fn path() [:0]const u8 {
    if (fifo_path.len == 0) {
        fifo_path = std.fmt.bufPrintSentinel(&fifo_path_buf, "{s}/woofersoundpad.fifo", .{sys.runtimeDir()}, 0) catch "/tmp/woofersoundpad.fifo";
    }
    return fifo_path;
}

pub fn parse(line: []const u8) ?Command {
    const trimmed = std.mem.trim(u8, line, " \r\n\t");
    const space = std.mem.indexOfScalar(u8, trimmed, ' ');
    const verb_text = if (space) |s| trimmed[0..s] else trimmed;
    const arg = if (space) |s| std.mem.trim(u8, trimmed[s + 1 ..], " ") else "";
    var cmd: Command = .{ .verb = std.meta.stringToEnum(Verb, verb_text) orelse return null };
    cmd.arg_len = @min(arg.len, cmd.arg.len);
    @memcpy(cmd.arg[0..cmd.arg_len], arg[0..cmd.arg_len]);
    return cmd;
}

/// Server side: starts the listener thread
pub fn listen() void {
    if (supported) listenImpl();
}

fn listenImpl() void {
    const p = path();
    _ = mkfifo(p.ptr, 0o600); // fails harmlessly if it already exists
    running.store(true, .release);
    const t = std.Thread.spawn(.{}, listenLoop, .{}) catch return;
    t.detach();
}

fn listenLoop() void {
    const p = path();
    var buf: [4096]u8 = undefined;
    while (running.load(.acquire)) {
        // Blocks until a client opens the FIFO for writing
        const fd = open(p.ptr, O_RDONLY);
        if (fd < 0) return;
        var len: usize = 0;
        while (true) {
            const n = read(fd, buf[len..].ptr, buf.len - len);
            if (n <= 0) break;
            len += @intCast(n);
            if (len == buf.len) break;
        }
        _ = close(fd);
        var lines = std.mem.tokenizeScalar(u8, buf[0..len], '\n');
        while (lines.next()) |l| {
            if (parse(l)) |cmd| {
                if (cmd.verb == .quit) return;
                mutex.lockUncancelable(sys.io);
                defer mutex.unlock(sys.io);
                if (queue_len < queue.len) {
                    queue[queue_len] = cmd;
                    queue_len += 1;
                }
            }
        }
    }
}

pub fn poll() ?Command {
    mutex.lockUncancelable(sys.io);
    defer mutex.unlock(sys.io);
    if (queue_len == 0) return null;
    const cmd = queue[0];
    std.mem.copyForwards(Command, queue[0 .. queue_len - 1], queue[1..queue_len]);
    queue_len -= 1;
    return cmd;
}

pub fn shutdown() void {
    if (supported) shutdownImpl();
}

fn shutdownImpl() void {
    if (!running.load(.acquire)) return;
    running.store(false, .release);
    _ = sendImpl("quit"); // unblocks the listener's open()
    std.Io.Dir.cwd().deleteFile(sys.io, path()) catch {};
}

/// Client side: returns false when no instance is listening
pub fn send(line: []const u8) !bool {
    return if (supported) sendImpl(line) else error.Unsupported;
}

fn sendImpl(line: []const u8) bool {
    const fd = open(path().ptr, O_WRONLY | O_NONBLOCK);
    if (fd < 0) return false; // ENXIO: nobody reading, ENOENT: not running
    defer _ = close(fd);
    _ = write(fd, line.ptr, line.len);
    _ = write(fd, "\n", 1);
    return true;
}

test "parse ipc commands" {
    const cmd = parse("play  bruh sound \n").?;
    try std.testing.expectEqualStrings("bruh sound", cmd.argument());
    try std.testing.expect(parse("nope") == null);
    try std.testing.expect(parse("stop").?.verb == .stop);
    try std.testing.expect(parse("mute_voice").?.verb == .mute_voice);
    try std.testing.expectEqualStrings("a b", parse("queue a b").?.argument());
}
