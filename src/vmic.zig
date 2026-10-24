//! Virtual microphone helpers.
//!
//! Linux (PipeWire/PulseAudio): creates a null sink the app plays into, loops
//! your real mic into it, and exposes its monitor as a microphone source.
//! Windows: detects VB-Audio Virtual Cable ("CABLE Input").

const std = @import("std");
const sys = @import("sys.zig");

pub const sink_name = "woofer_sink";
pub const mic_name = "woofer_mic";
/// Description of the playback device the app should output to
pub const output_label = "WooferSoundPad";
pub const vbcable_label = "CABLE Input";
pub const vbcable_url = "https://vb-audio.com/Cable/";

fn pactl(args: []const []const u8) ?sys.RunResult {
    var argv: [12][]const u8 = undefined;
    argv[0] = "pactl";
    @memcpy(argv[1 .. args.len + 1], args);
    return sys.run(argv[0 .. args.len + 1], 1024 * 1024) catch null;
}

pub fn pactlAvailable() bool {
    if (sys.is_windows) return false;
    const p = sys.which("pactl") orelse return false;
    sys.gpa.free(p);
    return true;
}

/// True when the WooferSoundPad null sink exists
pub fn exists() bool {
    if (sys.is_windows) return false;
    const res = pactl(&.{ "list", "short", "sinks" }) orelse return false;
    defer res.deinit();
    return std.mem.indexOf(u8, res.stdout, sink_name) != null;
}

pub fn create(include_real_mic: bool) !void {
    if (sys.is_windows) return error.Unsupported;
    remove();
    const steps = [_][]const []const u8{
        &.{ "load-module", "module-null-sink", "sink_name=" ++ sink_name, "sink_properties=device.description=" ++ output_label },
        &.{ "load-module", "module-loopback", "source=@DEFAULT_SOURCE@", "sink=" ++ sink_name, "latency_msec=20" },
        &.{ "load-module", "module-remap-source", "master=" ++ sink_name ++ ".monitor", "source_name=" ++ mic_name, "source_properties=device.description=\"WooferSoundPad Mic\"" },
    };
    for (steps, 0..) |args, i| {
        if (i == 1 and !include_real_mic) continue;
        const res = pactl(args) orelse return error.PactlMissing;
        defer res.deinit();
        if (!res.ok) {
            std.log.err("pactl: {s}", .{res.stderr});
            return error.PactlFailed;
        }
    }
}

pub fn remove() void {
    if (sys.is_windows) return;
    const res = pactl(&.{ "list", "short", "modules" }) orelse return;
    defer res.deinit();
    var lines = std.mem.tokenizeScalar(u8, res.stdout, '\n');
    while (lines.next()) |l| {
        if (std.mem.indexOf(u8, l, sink_name) == null and std.mem.indexOf(u8, l, mic_name) == null) continue;
        const tab = std.mem.indexOfAny(u8, l, "\t ") orelse continue;
        const unload = pactl(&.{ "unload-module", l[0..tab] }) orelse continue;
        unload.deinit();
    }
}

/// Does this playback device look like a virtual mic target?
pub fn isVirtualOutput(device_name: []const u8) bool {
    return std.mem.indexOf(u8, device_name, output_label) != null or
        std.mem.indexOf(u8, device_name, vbcable_label) != null;
}

// ── Your voice on the virtual mic ───────────────────────────────────────────
//
// The real microphone reaches the virtual sink through a module-loopback,
// which shows up as a sink-input whose volume pactl can change.

/// Sink-input id of the loopback feeding your mic into the virtual sink
fn voiceSinkInput() ?u32 {
    const mods = pactl(&.{ "list", "short", "modules" }) orelse return null;
    defer mods.deinit();
    const inputs = pactl(&.{ "list", "short", "sink-inputs" }) orelse return null;
    defer inputs.deinit();
    return findVoiceSinkInput(mods.stdout, inputs.stdout);
}

/// From `pactl list short modules` and `pactl list short sink-inputs` output
fn findVoiceSinkInput(modules: []const u8, sink_inputs: []const u8) ?u32 {
    var module: ?[]const u8 = null;
    var lines = std.mem.tokenizeScalar(u8, modules, '\n');
    while (lines.next()) |l| {
        if (std.mem.indexOf(u8, l, "module-loopback") == null or std.mem.indexOf(u8, l, "sink=" ++ sink_name) == null) continue;
        module = firstField(l);
        break;
    }
    const mod = module orelse return null;
    lines = std.mem.tokenizeScalar(u8, sink_inputs, '\n');
    while (lines.next()) |l| {
        // id <tab> sink <tab> owner module <tab> ...
        var fields = std.mem.tokenizeAny(u8, l, "\t ");
        const id = fields.next() orelse continue;
        _ = fields.next() orelse continue;
        const owner = fields.next() orelse continue;
        if (std.mem.eql(u8, owner, mod)) return std.fmt.parseInt(u32, id, 10) catch null;
    }
    return null;
}

fn firstField(line: []const u8) []const u8 {
    const end = std.mem.indexOfAny(u8, line, "\t ") orelse line.len;
    return line[0..end];
}

/// True when the virtual mic includes your real microphone
pub fn hasVoice() bool {
    if (sys.is_windows) return false;
    return voiceSinkInput() != null;
}

// Latest wanted state, packed as volume‰ | muted << 31. A worker thread
// applies it so dragging the slider never blocks the UI on pactl.
var voice_target = std.atomic.Value(u32).init(std.math.maxInt(u32));
var voice_busy = std.atomic.Value(bool).init(false);

/// Sets how loud your own voice is on the virtual mic (1 = 100%)
pub fn setVoice(volume: f32, muted: bool) void {
    if (sys.is_windows) return;
    const permille: u32 = @intFromFloat(std.math.clamp(volume, 0, 1.5) * 1000);
    voice_target.store(permille | (@as(u32, @intFromBool(muted)) << 31), .release);
    if (voice_busy.swap(true, .acq_rel)) return;
    const t = std.Thread.spawn(.{}, voiceWorker, .{}) catch {
        voice_busy.store(false, .release);
        return;
    };
    t.detach();
}

fn voiceWorker() void {
    var applied: u32 = std.math.maxInt(u32);
    while (true) {
        const target = voice_target.load(.acquire);
        if (target == applied) {
            voice_busy.store(false, .release);
            // Another value may have arrived right before we cleared the flag
            if (voice_target.load(.acquire) == applied or voice_busy.swap(true, .acq_rel)) return;
            continue;
        }
        applyVoice(target);
        applied = target;
    }
}

fn applyVoice(target: u32) void {
    const id = voiceSinkInput() orelse return;
    var id_buf: [16]u8 = undefined;
    var vol_buf: [16]u8 = undefined;
    const id_s = std.fmt.bufPrint(&id_buf, "{d}", .{id}) catch return;
    const vol_s = std.fmt.bufPrint(&vol_buf, "{d}%", .{(target & 0x7fff_ffff) / 10}) catch return;
    const muted = target >> 31 != 0;
    if (pactl(&.{ "set-sink-input-volume", id_s, vol_s })) |r| r.deinit();
    if (pactl(&.{ "set-sink-input-mute", id_s, if (muted) "1" else "0" })) |r| r.deinit();
}

test "find the voice loopback" {
    const modules =
        "536870913\tmodule-null-sink\tsink_name=woofer_sink sink_properties=device.description=WooferSoundPad\n" ++
        "536870914\tmodule-loopback\tsource=@DEFAULT_SOURCE@ sink=other\n" ++
        "536870915\tmodule-loopback\tsource=@DEFAULT_SOURCE@ sink=woofer_sink latency_msec=20\n";
    const inputs =
        "101\t55\t536870914\tPipeWire\tfloat32le 2ch 48000Hz\n" ++
        "102\t56\t536870915\tPipeWire\tfloat32le 2ch 48000Hz\n";
    try std.testing.expectEqual(@as(?u32, 102), findVoiceSinkInput(modules, inputs));
    try std.testing.expectEqual(@as(?u32, null), findVoiceSinkInput("1\tmodule-null-sink\tsink_name=woofer_sink\n", inputs));
}
