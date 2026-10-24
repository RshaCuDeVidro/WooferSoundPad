//! Play history and daily totals for the statistics page, kept in stats.json
//! next to config.json. Per-sound totals (plays, time played) live in each
//! workspace.json; this file only holds what spans workspaces and days.

const std = @import("std");
const c = @import("c");
const sys = @import("sys.zig");
const library = @import("library.zig");

const gpa = sys.gpa;

pub const max_history = 500;
pub const max_days = 120;

pub const Event = struct {
    t: i64,
    ws: []const u8,
    name: []const u8,
    uid: u32 = 0,
    color: u8 = 0,
};

pub const Day = struct {
    /// Days since 1970-01-01 in local time
    day: i64,
    plays: u32 = 0,
    seconds: f32 = 0,
};

const FileJson = struct {
    version: u32 = 1,
    history: []const Event = &.{},
    days: []const Day = &.{},
};

/// Oldest first
pub var history: std.ArrayList(Event) = .empty;
/// Oldest first, one entry per day that had any play
pub var days: std.ArrayList(Day) = .empty;

var path: []u8 = &.{};
var dirty = false;
var utc_offset: i64 = 0;

pub fn load() void {
    utc_offset = c.woof_utc_offset();
    const dir = sys.configDir() catch return;
    defer gpa.free(dir);
    path = sys.join(&.{ dir, "stats.json" }) catch return;
    const data = sys.readFile(path, 4 * 1024 * 1024) catch return;
    defer gpa.free(data);
    const parsed = std.json.parseFromSlice(FileJson, gpa, data, .{ .ignore_unknown_fields = true }) catch |err| {
        std.log.warn("stats.json: {s}", .{@errorName(err)});
        return;
    };
    defer parsed.deinit();
    for (parsed.value.history) |e| {
        const ws = gpa.dupe(u8, e.ws) catch continue;
        const name = gpa.dupe(u8, e.name) catch {
            gpa.free(ws);
            continue;
        };
        history.append(gpa, .{ .t = e.t, .ws = ws, .name = name, .uid = e.uid, .color = e.color }) catch {
            gpa.free(ws);
            gpa.free(name);
        };
    }
    for (parsed.value.days) |d| days.append(gpa, d) catch {};
}

pub fn deinit() void {
    save();
    for (history.items) |e| freeEvent(e);
    history.deinit(gpa);
    days.deinit(gpa);
    gpa.free(path);
}

fn freeEvent(e: Event) void {
    gpa.free(e.ws);
    gpa.free(e.name);
}

pub fn today() i64 {
    return @divFloor(library.now() + utc_offset, 86400);
}

/// Local day number of a timestamp
pub fn dayOf(t: i64) i64 {
    return @divFloor(t + utc_offset, 86400);
}

fn todayEntry() ?*Day {
    const d = today();
    if (days.items.len > 0 and days.items[days.items.len - 1].day == d) return &days.items[days.items.len - 1];
    days.append(gpa, .{ .day = d }) catch return null;
    if (days.items.len > max_days) _ = days.orderedRemove(0);
    return &days.items[days.items.len - 1];
}

pub fn recordPlay(ws_name: []const u8, s: *const library.Sound) void {
    if (todayEntry()) |d| d.plays += 1;
    const ws = gpa.dupe(u8, ws_name) catch return;
    const name = gpa.dupe(u8, s.name) catch {
        gpa.free(ws);
        return;
    };
    history.append(gpa, .{ .t = library.now(), .ws = ws, .name = name, .uid = s.uid, .color = s.color }) catch {
        gpa.free(ws);
        gpa.free(name);
        return;
    };
    if (history.items.len > max_history) freeEvent(history.orderedRemove(0));
    dirty = true;
}

pub fn addSeconds(seconds: f32) void {
    if (seconds <= 0) return;
    if (todayEntry()) |d| d.seconds += seconds;
    dirty = true;
}

/// Plays of a given day (0 when nothing played)
pub fn playsOn(day: i64) u32 {
    for (days.items) |d| {
        if (d.day == day) return d.plays;
    }
    return 0;
}

pub fn secondsOn(day: i64) f32 {
    for (days.items) |d| {
        if (d.day == day) return d.seconds;
    }
    return 0;
}

/// Consecutive days with plays, ending today or yesterday
pub fn streak() u32 {
    var n: u32 = 0;
    var d = today();
    if (playsOn(d) == 0) d -= 1;
    while (playsOn(d) > 0) : (d -= 1) n += 1;
    return n;
}

pub fn clear() void {
    for (history.items) |e| freeEvent(e);
    history.clearRetainingCapacity();
    days.clearRetainingCapacity();
    dirty = true;
    save();
}

pub fn isDirty() bool {
    return dirty;
}

pub fn save() void {
    if (!dirty or path.len == 0) return;
    const doc: FileJson = .{ .history = history.items, .days = days.items };
    const json = std.json.Stringify.valueAlloc(gpa, doc, .{}) catch return;
    defer gpa.free(json);
    sys.writeFileAtomic(path, json) catch |err| {
        std.log.err("could not save stats: {s}", .{@errorName(err)});
        return;
    };
    dirty = false;
}
