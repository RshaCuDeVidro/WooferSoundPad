//! Self-update from GitHub releases. A check only asks the GitHub API about the
//! latest release; nothing is downloaded until the user says so. The new
//! binary is verified (SHA-256, then a `--version` run on this machine) and
//! swapped in next to the running one, so the next start is the new version.

const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const sys = @import("sys.zig");
const net = @import("net.zig");

const gpa = sys.gpa;

pub const State = enum(u8) { idle, checking, up_to_date, available, downloading, ready, failed };
pub const Failure = enum(u8) { none, network, no_asset, not_writable, checksum, bad_binary, other };

pub var state: std.atomic.Value(State) = .init(.idle);
/// Why the last check or install failed. Written before `state` turns `.failed`.
pub var failure: Failure = .none;
/// The failure happened while installing, not while checking
pub var failed_install: bool = false;
pub var progress: net.Progress = .{};
/// The download is done and the file is being checked and swapped in
pub var verifying: std.atomic.Value(bool) = .init(false);
/// The last check was started by the app, not by the user
pub var automatic: bool = false;
/// Set by "Restart now": main starts the new binary after shutting down
pub var relaunch_pending: bool = false;

/// Only builds published as releases look for updates on their own
pub const auto_supported = builtin.mode != .debug and
    std.mem.indexOfScalar(u8, build_options.version, '-') == null;

const repo = blk: {
    const prefix = "https://github.com/";
    const url = build_options.repo_url;
    break :blk if (std.mem.startsWith(u8, url, prefix)) url[prefix.len..] else "RshaCuDeVidro/WooferSoundPad";
};
const api_url = "https://api.github.com/repos/" ++ repo ++ "/releases/latest";
pub const all_releases_url = "https://github.com/" ++ repo ++ "/releases";
pub const releases_url = all_releases_url ++ "/latest";

// Release info: written by the check thread before `state` turns `.available`
var latest: []u8 = &.{};
var notes_text: []u8 = &.{};
var page: []u8 = &.{};
var asset_name: []u8 = &.{};
var asset_url: []u8 = &.{};
var asset_size: u64 = 0;
var sha256: ?[64]u8 = null;
var sums_url: []u8 = &.{};

/// Captured at start: after the swap Linux reports "<path> (deleted)"
var exe_path: ?[]u8 = null;

pub fn init() void {
    exe_path = std.process.executablePathAlloc(sys.io, gpa) catch null;
    const exe = exe_path orelse return;
    // Leftovers of the previous update
    const dir = std.fs.path.dirname(exe) orelse return;
    if (partPath(dir)) |p| {
        sys.deleteFile(p);
        gpa.free(p);
    } else |_| {}
    if (sys.is_windows) {
        const old = std.fmt.allocPrint(gpa, "{s}.old", .{exe}) catch return;
        defer gpa.free(old);
        sys.deleteFile(old);
    }
}

pub fn latestVersion() []const u8 {
    return latest;
}

pub fn notes() []const u8 {
    return notes_text;
}

pub fn pageUrl() []const u8 {
    return if (page.len > 0) page else releases_url;
}

pub fn downloadSize() u64 {
    return asset_size;
}

pub fn busy() bool {
    return switch (state.load(.acquire)) {
        .checking, .downloading => true,
        else => false,
    };
}

// ── Checking ────────────────────────────────────────────────────────────────

/// Asks GitHub about the latest release in the background
pub fn check(is_automatic: bool) void {
    switch (state.load(.acquire)) {
        .checking, .downloading, .ready => return,
        else => {},
    }
    automatic = is_automatic;
    state.store(.checking, .release);
    const t = std.Thread.spawn(.{}, checkThread, .{}) catch {
        fail(.other, false);
        return;
    };
    t.detach();
}

fn checkThread() void {
    if (fetchLatest()) |newer| {
        state.store(if (newer) .available else .up_to_date, .release);
    } else |err| {
        std.log.warn("update check: {s}", .{@errorName(err)});
        fail(switch (err) {
            error.NoAsset => .no_asset,
            error.CurlMissing, error.NetworkError, error.BadResponse, error.HttpStatus => .network,
            else => .other,
        }, false);
    }
}

fn fail(why: Failure, installing: bool) void {
    failure = why;
    failed_install = installing;
    state.store(.failed, .release);
}

const Asset = struct {
    name: []const u8 = "",
    browser_download_url: []const u8 = "",
    size: u64 = 0,
    digest: ?[]const u8 = null,
};

const Release = struct {
    tag_name: []const u8 = "",
    html_url: []const u8 = "",
    body: ?[]const u8 = null,
    draft: bool = false,
    prerelease: bool = false,
    assets: []const Asset = &.{},
};

/// Returns true when the latest release is newer than this build
fn fetchLatest() !bool {
    const res = try net.get(api_url, 4 * 1024 * 1024);
    defer res.deinit();
    if (res.status != 200) return error.HttpStatus;

    const parsed = try std.json.parseFromSlice(Release, gpa, res.body, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    const rel = parsed.value;
    if (rel.draft or rel.prerelease) return false;
    const version = std.mem.trimStart(u8, rel.tag_name, "vV");
    if (!isNewer(version, build_options.version)) return false;

    const wanted = assetSuffix() orelse return error.NoAsset;
    const asset = for (rel.assets) |as| {
        if (std.mem.endsWith(u8, as.name, wanted)) break as;
    } else return error.NoAsset;

    var notes_buf: std.ArrayList(u8) = .empty;
    defer notes_buf.deinit(gpa);
    try extractNotes(rel.body orelse "", &notes_buf);

    replace(&latest, version);
    replace(&notes_text, notes_buf.items);
    replace(&page, rel.html_url);
    replace(&asset_name, asset.name);
    replace(&asset_url, asset.browser_download_url);
    asset_size = asset.size;
    sha256 = null;
    if (asset.digest) |d| if (std.mem.startsWith(u8, d, "sha256:") and d.len == 7 + 64) {
        sha256 = d[7..][0..64].*;
    };
    replace(&sums_url, "");
    for (rel.assets) |as| {
        if (std.mem.eql(u8, as.name, "SHA256SUMS.txt")) replace(&sums_url, as.browser_download_url);
    }
    return true;
}

fn replace(field: *[]u8, value: []const u8) void {
    const copy = gpa.dupe(u8, value) catch return;
    gpa.free(field.*);
    field.* = copy;
}

/// The release file that replaces this executable
fn assetSuffix() ?[]const u8 {
    if (builtin.cpu.arch != .x86_64) return null;
    if (sys.is_windows) return "-windows-x86_64.exe";
    if (builtin.os.tag != .linux) return null;
    return if (isUpxPacked()) "-linux-x86_64-compact" else "-linux-x86_64";
}

/// The compact Linux build is UPX-packed; keep users on the flavor they chose
fn isUpxPacked() bool {
    const exe = exe_path orelse return false;
    var file = std.Io.Dir.cwd().openFile(sys.io, exe, .{}) catch return false;
    defer file.close(sys.io);
    var buf: [4096]u8 = undefined;
    const n = file.readPositionalAll(sys.io, &buf, 0) catch return false;
    return std.mem.indexOf(u8, buf[0..n], "UPX!") != null;
}

pub fn isNewer(candidate: []const u8, current: []const u8) bool {
    const cand = std.SemanticVersion.parse(candidate) catch return false;
    const cur = std.SemanticVersion.parse(current) catch return false;
    return cand.order(cur) == .gt;
}

/// The "What's new" part of the release notes, cleaned up: headings become
/// "### Title" and bullets "- text" (`view_changelog.notes` draws them)
pub fn extractNotes(body: []const u8, out: *std.ArrayList(u8)) !void {
    var text = body;
    if (std.mem.indexOf(u8, text, "## What's new")) |i| {
        text = text[i..];
        text = if (std.mem.indexOfScalar(u8, text, '\n')) |nl| text[nl + 1 ..] else "";
    }
    // Checksums and GitHub's generated notes follow the changelog section
    for ([_][]const u8{ "<details>", "## What's Changed", "**Full Changelog**" }) |end| {
        if (std.mem.indexOf(u8, text, end)) |i| text = text[0..i];
    }

    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        var line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or line[0] == '<' or line[0] == '|') continue; // HTML, tables
        if (std.mem.startsWith(u8, line, "- ") or std.mem.startsWith(u8, line, "* ")) {
            try out.appendSlice(gpa, "- ");
            line = line[2..];
        } else if (line[0] == '#') {
            try out.appendSlice(gpa, "### ");
            line = std.mem.trimStart(u8, line, "# ");
        }
        try out.appendSlice(gpa, line);
        try out.append(gpa, '\n');
    }
    while (out.items.len > 0 and out.items[out.items.len - 1] == '\n') out.items.len -= 1;
}

// ── Installing ──────────────────────────────────────────────────────────────

/// Downloads, verifies and swaps in the new version in the background
pub fn install() void {
    if (state.load(.acquire) != .available) return;
    progress = .{};
    verifying.store(false, .release);
    state.store(.downloading, .release);
    const t = std.Thread.spawn(.{}, installThread, .{}) catch {
        fail(.other, true);
        return;
    };
    t.detach();
}

pub fn cancel() void {
    progress.cancel.store(true, .release);
}

fn installThread() void {
    if (installNow()) {
        state.store(.ready, .release);
    } else |err| {
        std.log.warn("update install: {s}", .{@errorName(err)});
        if (err == error.Canceled) {
            state.store(.available, .release);
            return;
        }
        fail(switch (err) {
            error.NotWritable => .not_writable,
            error.ChecksumMismatch, error.NoChecksum => .checksum,
            error.BadBinary => .bad_binary,
            error.CurlMissing, error.DownloadFailed, error.NetworkError, error.HttpStatus => .network,
            else => .other,
        }, true);
    }
}

fn partPath(dir: []const u8) ![]u8 {
    return sys.join(&.{ dir, ".WooferSoundPad-update" ++ sys.exe_suffix });
}

fn installNow() !void {
    const exe = exe_path orelse return error.NoExePath;
    const dir = std.fs.path.dirname(exe) orelse return error.NoExePath;
    const part = try partPath(dir);
    defer gpa.free(part);

    // The new file goes next to the old one so the final rename is atomic
    sys.writeFile(part, "") catch return error.NotWritable;
    errdefer sys.deleteFile(part);
    try net.download(asset_url, part, &progress);
    verifying.store(true, .release);

    const expected = sha256 orelse try checksumFromSums();
    {
        const data = try sys.readFile(part, 256 * 1024 * 1024);
        defer gpa.free(data);
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(data, &digest, .{});
        const hex = std.fmt.bytesToHex(digest, .lower);
        if (!std.ascii.eqlIgnoreCase(&hex, &expected)) return error.ChecksumMismatch;
    }

    // A build that cannot start on this CPU never replaces a working one
    sys.makeExecutable(part);
    {
        const res = sys.run(&.{ part, "--version" }, 4096) catch return error.BadBinary;
        defer res.deinit();
        const said = std.mem.indexOf(u8, res.stderr, latest) != null or std.mem.indexOf(u8, res.stdout, latest) != null;
        if (!res.ok or !said) return error.BadBinary;
    }

    if (sys.is_windows) {
        // A running .exe cannot be overwritten, but it can be renamed
        const old = try std.fmt.allocPrint(gpa, "{s}.old", .{exe});
        defer gpa.free(old);
        sys.deleteFile(old);
        sys.rename(exe, old) catch return error.NotWritable;
        sys.rename(part, exe) catch |err| {
            sys.rename(old, exe) catch {};
            return err;
        };
    } else {
        sys.rename(part, exe) catch return error.NotWritable;
    }
}

/// Looks the asset up in the release's SHA256SUMS.txt
fn checksumFromSums() ![64]u8 {
    if (sums_url.len == 0) return error.NoChecksum;
    const res = try net.get(sums_url, 64 * 1024);
    defer res.deinit();
    if (res.status != 200) return error.HttpStatus;
    return findChecksum(res.body, asset_name) orelse error.NoChecksum;
}

/// Finds `name` in `sha256sum` output ("<hex>  <name>" or "<hex> *<name>")
pub fn findChecksum(sums: []const u8, name: []const u8) ?[64]u8 {
    var lines = std.mem.splitScalar(u8, sums, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, " \r");
        if (line.len < 66 or line[64] != ' ') continue;
        const file = std.mem.trimStart(u8, line[65..], " *");
        if (std.mem.eql(u8, file, name)) return line[0..64].*;
    }
    return null;
}

/// Called last in main, after the window, audio and IPC socket are closed
pub fn relaunchIfPending() void {
    if (!relaunch_pending) return;
    const exe = exe_path orelse return;
    _ = std.process.spawn(sys.io, .{
        .argv = &.{exe},
        .stdin = .ignore,
        .create_no_window = true,
    }) catch |err| std.log.warn("restart after update: {s}", .{@errorName(err)});
}

test "isNewer" {
    try std.testing.expect(isNewer("1.1.0", "1.0.1"));
    try std.testing.expect(isNewer("1.0.10", "1.0.9"));
    try std.testing.expect(isNewer("1.0.0", "1.0.0-ci.abc1234"));
    try std.testing.expect(!isNewer("1.0.1", "1.0.1"));
    try std.testing.expect(!isNewer("1.0.0", "1.0.1"));
    try std.testing.expect(!isNewer("garbage", "1.0.1"));
}

test "findChecksum" {
    const sums =
        "bd5576266616dd44c9b0d444046b9addcdc4992ea043df23cc27ef278c87998f  WooferSoundPad-1.0.1-linux-x86_64\n" ++
        "7d5054afca715c01d6fc5d369bb2b8b27ca26b888bc14e0be37f3f2aa2260688 *WooferSoundPad-1.0.1-linux-x86_64-compact\n";
    try std.testing.expectEqualStrings("bd5576266616dd44c9b0d444046b9addcdc4992ea043df23cc27ef278c87998f", &findChecksum(sums, "WooferSoundPad-1.0.1-linux-x86_64").?);
    try std.testing.expectEqualStrings("7d5054afca715c01d6fc5d369bb2b8b27ca26b888bc14e0be37f3f2aa2260688", &findChecksum(sums, "WooferSoundPad-1.0.1-linux-x86_64-compact").?);
    try std.testing.expect(findChecksum(sums, "WooferSoundPad-1.0.1-windows-x86_64.exe") == null);
}

test "extractNotes" {
    const body =
        "<p align=\"center\"><img src=\"banner.png\"></p>\n\n## Download\n\n| a | b |\n\n## What's new\n\n" ++
        "### Fixed\n\n- The **Linux** binaries ran `fine`.\n\n\n<details><summary>SHA</summary>\nabc\n</details>\n\n" ++
        "**Full Changelog**: v1.0.0...v1.0.1";
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    try extractNotes(body, &out);
    try std.testing.expectEqualStrings("### Fixed\n- The **Linux** binaries ran `fine`.", out.items);
}
