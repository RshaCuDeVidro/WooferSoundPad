//! Pads that play by themselves: every N minutes, or every day at a set time.

const std = @import("std");

/// A daily time still fires if the app was busy (or the PC asleep) for up to
/// this long past it, but not hours later
const daily_window_min = 10;

pub const Clock = struct {
    /// Unix seconds
    now: i64,
    /// Seconds east of UTC
    utc_offset: i64,

    fn localMinute(c: Clock) i64 {
        return @divFloor(@mod(c.now + c.utc_offset, 86400), 60);
    }

    fn localDay(c: Clock) i64 {
        return @divFloor(c.now + c.utc_offset, 86400);
    }
};

/// Advances one pad's schedule and says whether it plays now. `next_fire`
/// and `fired_day` are its runtime state; set both to 0 to re-arm it.
pub fn tick(every_min: u32, at_min: i32, next_fire: *i64, fired_day: *i64, clock: Clock) bool {
    var fire = false;
    if (every_min > 0) {
        const period = @as(i64, every_min) * 60;
        // Armed for the first time, or the period was shortened
        if (next_fire.* == 0 or next_fire.* > clock.now + period) next_fire.* = clock.now + period;
        if (clock.now >= next_fire.*) {
            fire = true;
            next_fire.* = clock.now + period;
        }
    } else next_fire.* = 0;

    if (at_min >= 0) {
        const day = clock.localDay();
        const late = clock.localMinute() - at_min;
        // A time that already went by today waits for tomorrow
        if (fired_day.* == 0) fired_day.* = if (late >= 0) day else day - 1;
        if (late >= 0 and late < daily_window_min and day > fired_day.*) {
            fire = true;
            fired_day.* = day;
        }
    } else fired_day.* = 0;
    return fire;
}

/// "09:30" from a minute of the day
pub fn formatTime(buf: []u8, minute_of_day: i32) []const u8 {
    const m: u32 = @intCast(std.math.clamp(minute_of_day, 0, 24 * 60 - 1));
    return std.fmt.bufPrint(buf, "{d:0>2}:{d:0>2}", .{ m / 60, m % 60 }) catch "";
}

/// "9:30", "09:30" or "930" to a minute of the day
pub fn parseTime(text: []const u8) ?i32 {
    const s = std.mem.trim(u8, text, " ");
    var h: i32 = 0;
    var m: i32 = 0;
    if (std.mem.indexOfAny(u8, s, ":.h")) |sep| {
        h = std.fmt.parseInt(i32, s[0..sep], 10) catch return null;
        const rest = s[sep + 1 ..];
        m = if (rest.len == 0) 0 else std.fmt.parseInt(i32, rest, 10) catch return null;
    } else {
        const v = std.fmt.parseInt(i32, s, 10) catch return null;
        if (s.len <= 2) h = v else {
            h = @divTrunc(v, 100);
            m = @mod(v, 100);
        }
    }
    if (h < 0 or h > 23 or m < 0 or m > 59) return null;
    return h * 60 + m;
}

test "every N minutes" {
    var next: i64 = 0;
    var day: i64 = 0;
    const t0: i64 = 1_000_000;
    try std.testing.expect(!tick(5, -1, &next, &day, .{ .now = t0, .utc_offset = 0 }));
    try std.testing.expect(!tick(5, -1, &next, &day, .{ .now = t0 + 299, .utc_offset = 0 }));
    try std.testing.expect(tick(5, -1, &next, &day, .{ .now = t0 + 300, .utc_offset = 0 }));
    try std.testing.expect(!tick(5, -1, &next, &day, .{ .now = t0 + 301, .utc_offset = 0 }));
    try std.testing.expect(tick(5, -1, &next, &day, .{ .now = t0 + 600, .utc_offset = 0 }));
    // Shortening the period re-arms it
    try std.testing.expect(!tick(1, -1, &next, &day, .{ .now = t0 + 610, .utc_offset = 0 }));
    try std.testing.expect(tick(1, -1, &next, &day, .{ .now = t0 + 670, .utc_offset = 0 }));
}

test "daily at a time, in local time" {
    var next: i64 = 0;
    var day: i64 = 0;
    const midnight: i64 = 20_000 * 86400; // UTC
    const offset: i64 = -3 * 3600; // Brasília
    const at: i32 = 9 * 60;
    // 08:59 local: nothing yet
    try std.testing.expect(!tick(0, at, &next, &day, .{ .now = midnight + 3 * 3600 + 8 * 3600 + 59 * 60, .utc_offset = offset }));
    // 09:00 local: plays once
    try std.testing.expect(tick(0, at, &next, &day, .{ .now = midnight + 12 * 3600, .utc_offset = offset }));
    try std.testing.expect(!tick(0, at, &next, &day, .{ .now = midnight + 12 * 3600 + 30, .utc_offset = offset }));
    // Next day at 09:05 (a little late): plays
    try std.testing.expect(tick(0, at, &next, &day, .{ .now = midnight + 86400 + 12 * 3600 + 300, .utc_offset = offset }));

    // Started after the time went by: waits for tomorrow, and a day missed by hours stays missed
    var day2: i64 = 0;
    try std.testing.expect(!tick(0, at, &next, &day2, .{ .now = midnight + 15 * 3600, .utc_offset = offset }));
    try std.testing.expect(!tick(0, at, &next, &day2, .{ .now = midnight + 86400 + 15 * 3600, .utc_offset = offset }));
}

test "time text" {
    var buf: [8]u8 = undefined;
    try std.testing.expectEqualStrings("07:05", formatTime(&buf, 7 * 60 + 5));
    try std.testing.expectEqual(@as(?i32, 9 * 60 + 30), parseTime("9:30"));
    try std.testing.expectEqual(@as(?i32, 21 * 60), parseTime("21"));
    try std.testing.expectEqual(@as(?i32, 7 * 60 + 45), parseTime("0745"));
    try std.testing.expectEqual(@as(?i32, null), parseTime("25:00"));
    try std.testing.expectEqual(@as(?i32, null), parseTime("ab"));
}
