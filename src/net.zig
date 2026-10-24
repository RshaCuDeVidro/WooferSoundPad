//! HTTP through the system `curl` (bundled with Linux distros and Windows
//! 10/11). Zig's own resolver trips over some resolv.conf setups (scoped IPv6
//! nameservers), and curl brings proxies, HTTP/2 and compression for free.

const std = @import("std");
const sys = @import("sys.zig");

const gpa = sys.gpa;

pub const user_agent = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36";

/// Shared between a worker thread and the UI
pub const Progress = struct {
    fraction: std.atomic.Value(u32) = .init(@bitCast(@as(f32, -1))), // -1 = unknown
    cancel: std.atomic.Value(bool) = .init(false),

    pub fn set(p: *Progress, f: f32) void {
        p.fraction.store(@bitCast(f), .release);
    }

    pub fn get(p: *const Progress) f32 {
        return @bitCast(p.fraction.load(.acquire));
    }

    pub fn canceled(p: *const Progress) bool {
        return p.cancel.load(.acquire);
    }
};

pub const Response = struct {
    status: u16,
    body: []u8,

    pub fn deinit(r: Response) void {
        gpa.free(r.body);
    }
};

/// GET a page or API. Non-2xx statuses are returned, not treated as errors.
pub fn get(url: []const u8, max_bytes: usize) !Response {
    const curl = sys.systemTool("curl");
    const res = sys.run(&.{
        curl,         "-sS",            "-L",      "--compressed",
        "--max-time", "25",             "--retry", "1",
        "-A",         user_agent,       "-H",      "Accept-Language: en-US,en;q=0.9",
        "-w",         "\n%{http_code}", url,
    }, max_bytes) catch |err| return switch (err) {
        error.FileNotFound => error.CurlMissing,
        else => err,
    };
    if (!res.ok) {
        std.log.warn("curl {s}: {s}", .{ url, res.stderr });
        res.deinit();
        return error.NetworkError;
    }
    gpa.free(res.stderr);
    // The status code is the last line (from -w)
    const body = res.stdout;
    const nl = std.mem.lastIndexOfScalar(u8, body, '\n') orelse {
        gpa.free(body);
        return error.BadResponse;
    };
    const status = std.fmt.parseInt(u16, std.mem.trim(u8, body[nl + 1 ..], " \r\n"), 10) catch 0;
    const trimmed = gpa.realloc(body, nl) catch body[0..nl];
    return .{ .status = status, .body = trimmed };
}

/// Downloads `url` to `dest`, reporting progress. Honors `progress.cancel`.
pub fn download(url: []const u8, dest: []const u8, progress: *Progress) !void {
    const curl = sys.systemTool("curl");
    var child = std.process.spawn(sys.io, .{
        .argv = &.{ curl, "-L", "-f", "--connect-timeout", "20", "--retry", "2", "-A", user_agent, "-#", "-o", dest, url },
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .pipe,
        .create_no_window = true,
    }) catch |err| return switch (err) {
        error.FileNotFound => error.CurlMissing,
        else => err,
    };

    // curl -# prints "####   45.6%" chunks separated by carriage returns
    var buf: [4096]u8 = undefined;
    var reader = child.stderr.?.readerStreaming(sys.io, &buf);
    while (true) {
        if (progress.canceled()) {
            child.kill(sys.io);
            sys.deleteFile(dest);
            return error.Canceled;
        }
        const chunk = reader.interface.takeDelimiter('\r') catch break orelse break;
        if (parsePercent(chunk)) |pct| progress.set(pct / 100);
    }
    const term = try child.wait(sys.io);
    switch (term) {
        .exited => |code| if (code != 0) {
            sys.deleteFile(dest);
            return error.DownloadFailed;
        },
        else => return error.DownloadFailed,
    }
    progress.set(1);
}

/// Finds the number right before the last '%' in a progress line
pub fn parsePercent(s: []const u8) ?f32 {
    const pct = std.mem.lastIndexOfScalar(u8, s, '%') orelse return null;
    var start = pct;
    while (start > 0 and (std.ascii.isDigit(s[start - 1]) or s[start - 1] == '.')) start -= 1;
    if (start == pct) return null;
    return std.fmt.parseFloat(f32, s[start..pct]) catch null;
}

/// Percent-encodes a query parameter value
pub fn encodeQuery(out: *std.ArrayList(u8), s: []const u8) !void {
    for (s) |ch| {
        if (std.ascii.isAlphanumeric(ch) or ch == '-' or ch == '_' or ch == '.' or ch == '~') {
            try out.append(gpa, ch);
        } else {
            try out.print(gpa, "%{X:0>2}", .{ch});
        }
    }
}

test "parsePercent" {
    try std.testing.expectEqual(@as(?f32, 45.6), parsePercent("#####    45.6%"));
    try std.testing.expectEqual(@as(?f32, 100), parsePercent("100.0%"));
    try std.testing.expectEqual(@as(?f32, null), parsePercent("nothing"));
}

test "encodeQuery" {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    try encodeQuery(&out, "husky howl&ç");
    try std.testing.expectEqualStrings("husky%20howl%26%C3%A7", out.items);
}
