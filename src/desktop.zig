//! Linux desktop integration: puts WooferSoundPad in the app menu with its
//! icon and quick actions, the XDG way. Per user and without root by default
//! (~/.local); PREFIX=/usr/local installs system-wide. Also `--install`.

const std = @import("std");
const builtin = @import("builtin");
const assets = @import("assets");
const sys = @import("sys.zig");

const gpa = sys.gpa;

pub const supported = builtin.os.tag == .linux;

const app_id = "woofersoundpad";
const bin_name = "WooferSoundPad";

const Paths = struct {
    bin_dir: []u8,
    apps_dir: []u8,
    hicolor: []u8,

    fn deinit(p: Paths) void {
        gpa.free(p.bin_dir);
        gpa.free(p.apps_dir);
        gpa.free(p.hicolor);
    }

    fn desktopFile(p: Paths) ![]u8 {
        return sys.join(&.{ p.apps_dir, app_id ++ ".desktop" });
    }
};

fn paths() !Paths {
    var share: []u8 = undefined;
    var bin_dir: []u8 = undefined;
    if (sys.getenv("PREFIX")) |prefix| {
        share = try sys.join(&.{ prefix, "share" });
        bin_dir = try sys.join(&.{ prefix, "bin" });
    } else {
        const home = sys.getenv("HOME") orelse return error.NoHome;
        share = if (sys.getenv("XDG_DATA_HOME")) |x| try gpa.dupe(u8, x) else try sys.join(&.{ home, ".local", "share" });
        bin_dir = try sys.join(&.{ home, ".local", "bin" });
    }
    defer gpa.free(share);
    return .{
        .bin_dir = bin_dir,
        .apps_dir = try sys.join(&.{ share, "applications" }),
        .hicolor = try sys.join(&.{ share, "icons", "hicolor" }),
    };
}

/// True when an app menu entry exists, ours or a distro package's
pub fn installed() bool {
    if (!supported) return true;
    const p = paths() catch return false;
    defer p.deinit();
    const mine = p.desktopFile() catch return false;
    defer gpa.free(mine);
    if (sys.exists(mine)) return true;
    inline for (.{ "/usr/share/applications/", "/usr/local/share/applications/" }) |dir| {
        if (sys.exists(dir ++ app_id ++ ".desktop")) return true;
    }
    return false;
}

/// Where the installed copy lives (shown in Settings). Owned.
pub fn installedExe() ?[]u8 {
    const p = paths() catch return null;
    defer p.deinit();
    const desktop = p.desktopFile() catch return null;
    defer gpa.free(desktop);
    const data = sys.readFile(desktop, 64 * 1024) catch return null;
    defer gpa.free(data);
    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "TryExec=")) continue;
        return gpa.dupe(u8, std.mem.trim(u8, line["TryExec=".len..], " \r")) catch null;
    }
    return null;
}

const icon_sizes = [_]struct { size: u32, png: []const u8 }{
    .{ .size = 16, .png = assets.icon_16 },
    .{ .size = 24, .png = assets.icon_24 },
    .{ .size = 32, .png = assets.icon_32 },
    .{ .size = 48, .png = assets.icon_48 },
    .{ .size = 64, .png = assets.icon_64 },
    .{ .size = 128, .png = assets.icon_128 },
    .{ .size = 256, .png = assets.icon_256 },
    .{ .size = 512, .png = assets.icon_512 },
};

pub const Result = struct {
    /// The executable the menu entry starts. Owned.
    exe: []u8,
    /// The running binary was copied to `exe`
    copied: bool,
};

/// Copies the app to ~/.local/bin (unless portable), writes the icons and the
/// menu entry, and refreshes the desktop's caches
pub fn install() !Result {
    if (!supported) return error.Unsupported;
    const p = try paths();
    defer p.deinit();
    const self = try std.process.executablePathAlloc(sys.io, gpa);
    defer gpa.free(self);

    // Portable copies keep their data next to the binary: launch them in place
    var exe: []u8 = undefined;
    var copied = false;
    if (sys.portable_root != null) {
        exe = try gpa.dupe(u8, self);
    } else {
        exe = try sys.join(&.{ p.bin_dir, bin_name });
        errdefer gpa.free(exe);
        if (!std.mem.eql(u8, exe, self)) {
            try sys.makePath(p.bin_dir);
            const tmp = try std.fmt.allocPrint(gpa, "{s}.new", .{exe});
            defer gpa.free(tmp);
            sys.copyFile(self, tmp) catch |err| {
                sys.deleteFile(tmp);
                return err;
            };
            sys.makeExecutable(tmp);
            // A rename never disturbs an installed copy that is running
            try sys.rename(tmp, exe);
            copied = true;
        }
    }
    errdefer gpa.free(exe);

    for (icon_sizes) |ic| {
        var buf: [16]u8 = undefined;
        const dim = try std.fmt.bufPrint(&buf, "{d}x{d}", .{ ic.size, ic.size });
        try writeIcon(p.hicolor, dim, app_id ++ ".png", ic.png);
    }
    try writeIcon(p.hicolor, "scalable", app_id ++ ".svg", assets.icon_svg);

    try sys.makePath(p.apps_dir);
    const entry = try desktopEntry(exe);
    defer gpa.free(entry);
    const desktop = try p.desktopFile();
    defer gpa.free(desktop);
    try sys.writeFileAtomic(desktop, entry);

    refreshCaches(p);
    return .{ .exe = exe, .copied = copied };
}

fn writeIcon(hicolor: []const u8, dim: []const u8, name: []const u8, data: []const u8) !void {
    const dir = try sys.join(&.{ hicolor, dim, "apps" });
    defer gpa.free(dir);
    try sys.makePath(dir);
    const file = try sys.join(&.{ dir, name });
    defer gpa.free(file);
    try sys.writeFile(file, data);
}

/// Removes the menu entry, the icons and the copy in ~/.local/bin.
/// Sounds and settings stay.
pub fn uninstall() !void {
    if (!supported) return error.Unsupported;
    const p = try paths();
    defer p.deinit();

    // Only delete the binary we put there, never a portable copy elsewhere
    if (installedExe()) |exe| {
        defer gpa.free(exe);
        if (std.mem.eql(u8, std.fs.path.dirname(exe) orelse "", p.bin_dir)) sys.deleteFile(exe);
    }
    const desktop = try p.desktopFile();
    defer gpa.free(desktop);
    sys.deleteFile(desktop);
    for (icon_sizes) |ic| {
        var buf: [64]u8 = undefined;
        const rel = try std.fmt.bufPrint(&buf, "{d}x{d}/apps/" ++ app_id ++ ".png", .{ ic.size, ic.size });
        const file = try sys.join(&.{ p.hicolor, rel });
        defer gpa.free(file);
        sys.deleteFile(file);
    }
    const svg = try sys.join(&.{ p.hicolor, "scalable", "apps", app_id ++ ".svg" });
    defer gpa.free(svg);
    sys.deleteFile(svg);
    refreshCaches(p);
}

/// Menus and docks rescan on their own; these make it instant where available
fn refreshCaches(p: Paths) void {
    const cmds = [_][]const []const u8{
        &.{ "update-desktop-database", "-q", p.apps_dir },
        &.{ "gtk-update-icon-cache", "-q", "-t", "-f", p.hicolor },
        &.{ "touch", p.hicolor }, // a newer mtime makes GTK and Qt reload the theme
        &.{ "xdg-desktop-menu", "forceupdate" },
    };
    for (cmds) |argv| {
        const res = sys.run(argv, 16 * 1024) catch continue;
        res.deinit();
    }
}

/// The .desktop file, with the absolute path in Exec: ~/.local/bin is not on
/// PATH in every desktop session
pub fn desktopEntry(exe: []const u8) ![]u8 {
    var quoted: std.ArrayList(u8) = .empty;
    defer quoted.deinit(gpa);
    try quoteExec(&quoted, exe);
    const q = quoted.items;
    return std.fmt.allocPrint(gpa,
        \\[Desktop Entry]
        \\Type=Application
        \\Version=1.5
        \\Name=WooferSoundPad
        \\GenericName=Soundboard
        \\GenericName[pt_BR]=Mesa de sons
        \\Comment=Play sounds through your microphone in Discord, games and streams
        \\Comment[pt_BR]=Toque sons no seu microfone no Discord, em jogos e em lives
        \\TryExec={s}
        \\Exec={s}
        \\Icon=woofersoundpad
        \\Terminal=false
        \\Categories=AudioVideo;Audio;Mixer;
        \\Keywords=soundboard;sound;sfx;meme;discord;microphone;mic;stream;obs;
        \\Keywords[pt_BR]=soundboard;som;efeito;meme;discord;microfone;mic;live;obs;
        \\StartupNotify=true
        \\StartupWMClass=WooferSoundPad
        \\SingleMainWindow=true
        \\Actions=random;pause;stop-all;
        \\
        \\[Desktop Action random]
        \\Name=Play a random sound
        \\Name[pt_BR]=Tocar um som aleatório
        \\Exec={s} --random
        \\
        \\[Desktop Action pause]
        \\Name=Pause or resume
        \\Name[pt_BR]=Pausar ou continuar
        \\Exec={s} --pause
        \\
        \\[Desktop Action stop-all]
        \\Name=Stop all sounds
        \\Name[pt_BR]=Parar todos os sons
        \\Exec={s} --stop
        \\
    , .{ exe, q, q, q, q });
}

/// Exec quoting from the Desktop Entry spec: wrap in double quotes, escape
/// `"`, `` ` ``, `$` and `\`, and double `%` (field codes)
fn quoteExec(out: *std.ArrayList(u8), path: []const u8) !void {
    try out.append(gpa, '"');
    for (path) |ch| switch (ch) {
        '"', '`', '$', '\\' => try out.appendSlice(gpa, &.{ '\\', ch }),
        '%' => try out.appendSlice(gpa, "%%"),
        else => try out.append(gpa, ch),
    };
    try out.append(gpa, '"');
}

test "desktop entry quoting" {
    const entry = try desktopEntry("/home/me/My Apps/100%/Woofer$");
    defer gpa.free(entry);
    try std.testing.expect(std.mem.indexOf(u8, entry, "Exec=\"/home/me/My Apps/100%%/Woofer\\$\"\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, entry, "Exec=\"/home/me/My Apps/100%%/Woofer\\$\" --stop\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, entry, "TryExec=/home/me/My Apps/100%/Woofer$\n") != null);
}
