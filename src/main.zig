//! WooferSoundPad — a husky-themed soundboard for Linux and Windows.

const std = @import("std");
const c = @import("c");
const assets = @import("assets");
const build_options = @import("build_options");
const sys = @import("sys.zig");
const config = @import("config.zig");
const ui = @import("ui.zig");
const ipc = @import("ipc.zig");
const view = @import("view.zig");
const devtools = @import("devtools.zig");
const App = @import("app.zig").App;

const usage =
    \\WooferSoundPad {s} — a blazing-fast soundboard for Linux & Windows
    \\
    \\Usage:
    \\  WooferSoundPad                     start the app
    \\  WooferSoundPad --play "<name>"     play a sound in the running app
    \\  WooferSoundPad --queue "<name>"    add a sound to the play queue
    \\  WooferSoundPad --stop              stop every sound
    \\  WooferSoundPad --pause             pause / resume everything
    \\  WooferSoundPad --next              skip to the next sound in the queue
    \\  WooferSoundPad --random            play a random sound
    \\  WooferSoundPad --mute-voice        mute / unmute your voice on the virtual mic
    \\  WooferSoundPad --workspace "<name>" switch workspace
    \\  WooferSoundPad --show              bring the window to the front
    \\  WooferSoundPad --version
    \\
    \\Remote control (--play, --stop, ...) is available on Linux, so Wayland users
    \\can bind sounds to desktop shortcuts. Portable mode: put an empty file named
    \\"portable.txt" next to the executable to keep all data in ./data.
    \\
;

pub fn main(init: std.process.Init) !void {
    sys.init(init.io, init.environ_map);
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len > 1) {
        if (try handleCli(args)) return;
    }

    // Single instance (Linux): a second launch just brings the first one forward
    if (ipc.supported and (ipc.send("show") catch false)) {
        std.debug.print("WooferSoundPad is already running.\n", .{});
        return;
    }

    sys.detectPortable();
    var app: App = .{ .cfg = config.load() };

    c.SetTraceLogLevel(c.LOG_ERROR);
    c.SetConfigFlags(c.FLAG_WINDOW_RESIZABLE | c.FLAG_VSYNC_HINT | c.FLAG_MSAA_4X_HINT);
    c.InitWindow(app.cfg.window_width, app.cfg.window_height, "WooferSoundPad");
    defer c.CloseWindow();
    c.SetWindowMinSize(960, 600);
    c.SetExitKey(c.KEY_NULL); // Esc stops sounds instead of quitting
    if (app.cfg.window_maximized) c.MaximizeWindow();
    setWindowIcons();

    const logo_img = c.LoadImageFromMemory(".png", assets.logo_mark.ptr, assets.logo_mark.len);
    app.logo = c.LoadTextureFromImage(logo_img);
    c.UnloadImage(logo_img);
    c.GenTextureMipmaps(&app.logo);
    c.SetTextureFilter(app.logo, c.TEXTURE_FILTER_TRILINEAR);
    defer c.UnloadTexture(app.logo);

    ui.init();
    defer ui.deinit();
    applyScale(&app);

    app.init();
    defer app.deinit();
    devtools.init();

    while (!c.WindowShouldClose() and !app.quit_requested) {
        // Lighter when in the background; hotkeys still poll every frame
        c.SetTargetFPS(if (c.IsWindowFocused()) 60 else if (c.IsWindowMinimized()) 15 else 30);
        if (!ui.mouseDown()) applyScale(&app);

        ui.beginFrame();
        app.beginFrame();
        app.update();
        devtools.update(&app);
        view.draw(&app);
        ui.endFrame();

        if (c.IsWindowResized()) {
            const maximized = c.IsWindowMaximized();
            app.cfg.window_maximized = maximized;
            if (!maximized) {
                app.cfg.window_width = c.GetScreenWidth();
                app.cfg.window_height = c.GetScreenHeight();
            }
            app.markConfig();
        }
    }
}

/// UI scale = user setting × monitor DPI. Fonts are rebuilt when it changes.
fn applyScale(app: *App) void {
    const dpi = c.GetWindowScaleDPI();
    const s = std.math.clamp(app.cfg.ui_scale * @max(dpi.x, 1), 0.5, 4);
    if (@abs(s - ui.scale) < 0.001 and app.applied_scale != 0) return;
    ui.scale = s;
    app.applied_scale = s;
    ui.flushFonts();
}

fn setWindowIcons() void {
    var images: [3]c.Image = .{
        c.LoadImageFromMemory(".png", assets.icon_32.ptr, assets.icon_32.len),
        c.LoadImageFromMemory(".png", assets.icon_64.ptr, assets.icon_64.len),
        c.LoadImageFromMemory(".png", assets.icon_256.ptr, assets.icon_256.len),
    };
    c.SetWindowIcons(&images, images.len);
    for (images) |img| c.UnloadImage(img);
}

/// Returns true when the command was handled and the app should exit
fn handleCli(args: []const [:0]const u8) !bool {
    const cmd = args[1];
    const arg: []const u8 = if (args.len > 2) args[2] else "";
    if (std.mem.eql(u8, cmd, "--help") or std.mem.eql(u8, cmd, "-h")) {
        std.debug.print(usage, .{build_options.version});
        return true;
    }
    if (std.mem.eql(u8, cmd, "--version") or std.mem.eql(u8, cmd, "-v")) {
        std.debug.print("WooferSoundPad {s}\n", .{build_options.version});
        return true;
    }
    var line_buf: [512]u8 = undefined;
    const line: ?[]const u8 = if (std.mem.eql(u8, cmd, "--play"))
        try std.fmt.bufPrint(&line_buf, "play {s}", .{arg})
    else if (std.mem.eql(u8, cmd, "--queue"))
        try std.fmt.bufPrint(&line_buf, "queue {s}", .{arg})
    else if (std.mem.eql(u8, cmd, "--stop"))
        "stop"
    else if (std.mem.eql(u8, cmd, "--pause"))
        "pause"
    else if (std.mem.eql(u8, cmd, "--next"))
        "next"
    else if (std.mem.eql(u8, cmd, "--random"))
        "random"
    else if (std.mem.eql(u8, cmd, "--mute-voice"))
        "mute_voice"
    else if (std.mem.eql(u8, cmd, "--workspace"))
        try std.fmt.bufPrint(&line_buf, "workspace {s}", .{arg})
    else if (std.mem.eql(u8, cmd, "--show"))
        "show"
    else
        null;

    const l = line orelse {
        std.debug.print("Unknown option: {s}\n\n" ++ usage, .{ cmd, build_options.version });
        return true;
    };
    const delivered = ipc.send(l) catch {
        std.debug.print("Remote control is only available on Linux. Use global hotkeys on Windows.\n", .{});
        std.process.exit(1);
    };
    if (!delivered) {
        std.debug.print("WooferSoundPad is not running.\n", .{});
        std.process.exit(1);
    }
    return true;
}
