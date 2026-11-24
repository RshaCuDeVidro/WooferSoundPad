//! Keeps pads in step with workspace folders while the app runs: audio files
//! dropped in by hand become pads, pads whose file was deleted go away.
//! Polls every couple of seconds; a new file is only adopted once its size
//! held still between two polls (so a copy in progress is left alone).

const std = @import("std");
const sys = @import("sys.zig");
const library = @import("library.zig");
const jobs = @import("jobs.zig");

const gpa = sys.gpa;

pub const interval: f32 = 2;

pub const Event = struct {
    ws: usize,
    kind: enum { added, removed },
    /// added: file name in the workspace folder
    file: []u8 = &.{},
    /// removed: the pad's uid
    uid: u32 = 0,
};

const Seen = struct {
    ws_name: []u8,
    file: []u8,
    size: u64,
    /// Polls in a row it was found (new files) or missing (pads)
    polls: u8 = 1,
    alive: bool = true,
};

var new_files: std.ArrayList(Seen) = .empty;
var gone_files: std.ArrayList(Seen) = .empty;

/// Looks at every workspace except those a job is still writing into, and
/// appends what changed to `out`. Free the events with `freeEvents`.
pub fn poll(lib: *const library.Library, busy: *const jobs.Manager, out: *std.ArrayList(Event)) void {
    for (new_files.items) |*n| n.alive = false;
    for (gone_files.items) |*g| g.alive = false;

    for (lib.workspaces.items, 0..) |*ws, wi| {
        if (busy.busyIn(ws.name)) {
            keep(ws.name);
            continue;
        }
        const entries = sys.listDir(ws.dir) catch continue;
        defer sys.freeEntries(entries);

        for (entries) |e| {
            if (e.is_dir or !library.isAudioFile(e.name) or ws.findByFile(e.name) != null) continue;
            const full = sys.join(&.{ ws.dir, e.name }) catch continue;
            defer gpa.free(full);
            const size = sys.fileSize(full);
            if (find(&new_files, ws.name, e.name)) |n| {
                n.alive = true;
                if (n.size == size and size > 0) {
                    n.polls +|= 1;
                    if (n.polls == 2) emit(out, .{ .ws = wi, .kind = .added, .file = gpa.dupe(u8, e.name) catch continue });
                } else {
                    n.size = size;
                    n.polls = 1;
                }
            } else track(&new_files, ws.name, e.name, size);
        }

        for (ws.sounds.items) |s| {
            var present = false;
            for (entries) |e| {
                if (std.mem.eql(u8, e.name, s.file)) present = true;
            }
            if (present) continue;
            if (find(&gone_files, ws.name, s.file)) |g| {
                g.alive = true;
                g.polls +|= 1;
                if (g.polls == 2) emit(out, .{ .ws = wi, .kind = .removed, .uid = s.uid });
            } else track(&gone_files, ws.name, s.file, 0);
        }
    }
    prune(&new_files);
    prune(&gone_files);
}

pub fn freeEvents(events: *std.ArrayList(Event)) void {
    for (events.items) |e| gpa.free(e.file);
    events.clearRetainingCapacity();
}

/// Forgets everything seen so far (after the library is reopened)
pub fn reset() void {
    for (new_files.items) |n| free(n);
    for (gone_files.items) |g| free(g);
    new_files.clearRetainingCapacity();
    gone_files.clearRetainingCapacity();
}

fn emit(out: *std.ArrayList(Event), e: Event) void {
    out.append(gpa, e) catch gpa.free(e.file);
}

fn find(list: *std.ArrayList(Seen), ws_name: []const u8, file: []const u8) ?*Seen {
    for (list.items) |*s| {
        if (std.mem.eql(u8, s.ws_name, ws_name) and std.mem.eql(u8, s.file, file)) return s;
    }
    return null;
}

fn track(list: *std.ArrayList(Seen), ws_name: []const u8, file: []const u8, size: u64) void {
    const n = gpa.dupe(u8, ws_name) catch return;
    const f = gpa.dupe(u8, file) catch {
        gpa.free(n);
        return;
    };
    list.append(gpa, .{ .ws_name = n, .file = f, .size = size }) catch {
        gpa.free(n);
        gpa.free(f);
    };
}

/// A skipped workspace keeps what was seen in it
fn keep(ws_name: []const u8) void {
    for (new_files.items) |*n| {
        if (std.mem.eql(u8, n.ws_name, ws_name)) n.alive = true;
    }
    for (gone_files.items) |*g| {
        if (std.mem.eql(u8, g.ws_name, ws_name)) g.alive = true;
    }
}

fn prune(list: *std.ArrayList(Seen)) void {
    var i: usize = 0;
    while (i < list.items.len) {
        if (list.items[i].alive) {
            i += 1;
        } else {
            free(list.swapRemove(i));
        }
    }
}

fn free(s: Seen) void {
    gpa.free(s.ws_name);
    gpa.free(s.file);
}
