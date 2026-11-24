//! CHANGELOG.md (and its Portuguese twin) baked into the binary.

const std = @import("std");

pub const en = @embedFile("changelog_en");
pub const pt = @embedFile("changelog_pt");

/// Markdown emphasis and code marks removed, into `buf`
pub fn plain(buf: []u8, line: []const u8) []const u8 {
    var n: usize = 0;
    for (line, 0..) |ch, i| {
        if (n >= buf.len) break;
        if (ch == '`') continue;
        if (ch == '*' and ((i + 1 < line.len and line[i + 1] == '*') or (i > 0 and line[i - 1] == '*'))) continue;
        buf[n] = ch;
        n += 1;
    }
    return buf[0..n];
}

pub const Section = struct {
    version: []const u8,
    date: []const u8,
    body: []const u8,
};

/// Splits the changelog at its "## [version] - date" headings
pub fn next(rest: *[]const u8) ?Section {
    const marker = "\n## [";
    const start = std.mem.indexOf(u8, rest.*, marker) orelse return null;
    const after = rest.*[start + marker.len ..];
    const close = std.mem.indexOfScalar(u8, after, ']') orelse return null;
    const eol = std.mem.indexOfScalar(u8, after, '\n') orelse after.len;
    const heading_tail = after[close + 1 .. eol];
    const body_start = @min(eol + 1, after.len);
    const end = std.mem.indexOf(u8, after[body_start..], marker) orelse after.len - body_start;
    rest.* = after[body_start + end ..];
    return .{
        .version = after[0..close],
        .date = std.mem.trim(u8, heading_tail, " -\u{2013}"),
        .body = after[body_start .. body_start + end],
    };
}

test "changelog sections" {
    var rest: []const u8 = en;
    const first = next(&rest).?;
    try std.testing.expect(first.version.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, first.body, "\n## [") == null);
    var count: usize = 1;
    while (next(&rest)) |_| count += 1;
    try std.testing.expect(count >= 3);

    var rest_pt: []const u8 = pt;
    try std.testing.expectEqualStrings(first.version, next(&rest_pt).?.version);
}
