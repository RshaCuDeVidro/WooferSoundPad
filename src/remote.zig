//! Local HTTP control for OBS (browser source overlay), Stream Deck and anything
//! else that can open a URL. The server itself is src/c/woof_http.c; this side
//! starts it from the settings, publishes the app state and runs commands.

const std = @import("std");
const c = @import("c");
const assets = @import("assets");
const sys = @import("sys.zig");
const config = @import("config.zig");
const audio = @import("audio.zig");
const theme = @import("theme.zig");
const ui = @import("ui.zig");

const gpa = sys.gpa;

pub const Status = enum { off, running, failed };
pub var status: Status = .off;

var running_port: u16 = 0;
var running_lan = false;
var published_at: f32 = -10;

/// 32 hex characters from the OS random source
pub fn newToken(buf: *[32]u8) []const u8 {
    var bytes: [16]u8 = undefined;
    sys.io.randomSecure(&bytes) catch sys.io.random(&bytes);
    const hex = "0123456789abcdef";
    for (bytes, 0..) |b, i| {
        buf[i * 2] = hex[b >> 4];
        buf[i * 2 + 1] = hex[b & 15];
    }
    return buf[0..];
}

/// Starts, restarts or stops the server to match the settings
pub fn apply(cfg: *config.Config) void {
    if (!cfg.http_enabled) {
        stop();
        return;
    }
    if (cfg.http_token.len < 16) {
        var buf: [32]u8 = undefined;
        config.setString(&cfg.http_token, newToken(&buf));
    }
    if (status == .running and running_port == cfg.http_port and running_lan == cfg.http_lan) return;
    stop();
    c.woof_http_set_page("/deck", "text/html; charset=utf-8", assets.deck_html.ptr, assets.deck_html.len);
    c.woof_http_set_page("/overlay", "text/html; charset=utf-8", assets.overlay_html.ptr, assets.overlay_html.len);
    const token = gpa.dupeSentinel(u8, cfg.http_token, 0) catch return;
    defer gpa.free(token);
    if (c.woof_http_start(cfg.http_port, @intFromBool(cfg.http_lan), token.ptr) == 0) {
        status = .running;
        running_port = cfg.http_port;
        running_lan = cfg.http_lan;
    } else {
        status = .failed;
    }
}

pub fn stop() void {
    if (status == .running) c.woof_http_stop();
    status = .off;
}

pub fn running() bool {
    return status == .running;
}

/// Next command as (verb, argument)
pub fn poll(buf: *[256]u8) ?struct { verb: []const u8, arg: []const u8 } {
    if (status != .running) return null;
    const n: usize = @intCast(c.woof_http_poll(buf, buf.len));
    if (n == 0) return null;
    const line = buf[0..n];
    const sp = std.mem.indexOfScalar(u8, line, ' ') orelse return .{ .verb = line, .arg = "" };
    return .{ .verb = line[0..sp], .arg = std.mem.trim(u8, line[sp + 1 ..], " ") };
}

pub const SoundState = struct {
    uid: u32,
    name: []const u8,
    color: []const u8,
    hotkey: []const u8,
    fx: usize,
    playing: bool,
};

pub const PlayingState = struct {
    uid: u32,
    name: []const u8,
    color: []const u8,
    progress: f32,
    left: f32,
    paused: bool,
    loop: bool,
};

pub const State = struct {
    workspace: []const u8,
    workspaces: []const []const u8,
    master: f32,
    stage: bool,
    playing: []const PlayingState,
    sounds: []const SoundState,
};

/// "#FF6B1A" for a pad color
pub fn colorHex(buf: *[7]u8, index: u8) []const u8 {
    const col = theme.padColor(index, ui.colors.accent);
    const r: u8 = @intFromFloat(std.math.clamp(col.r, 0, 1) * 255);
    const g: u8 = @intFromFloat(std.math.clamp(col.g, 0, 1) * 255);
    const b: u8 = @intFromFloat(std.math.clamp(col.b, 0, 1) * 255);
    return std.fmt.bufPrint(buf, "#{X:0>2}{X:0>2}{X:0>2}", .{ r, g, b }) catch "#FF6B1A";
}

/// Sends the state to the server, a few times per second
pub fn publish(state: State) void {
    if (status != .running) return;
    if (ui.time - published_at < 0.1) return;
    published_at = ui.time;
    const json = std.json.Stringify.valueAlloc(gpa, state, .{}) catch return;
    defer gpa.free(json);
    c.woof_http_set_state(json.ptr, @intCast(json.len));
}

pub fn shouldPublish() bool {
    return status == .running and ui.time - published_at >= 0.1;
}
