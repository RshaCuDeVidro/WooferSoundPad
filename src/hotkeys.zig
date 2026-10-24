//! Hotkeys: parsing/formatting ("Ctrl+Shift+F1"), in-window detection through
//! raylib, and system-wide hotkeys (RegisterHotKey on Windows, XGrabKey on X11).
//!
//! While the app window is focused the global grabs are released and keys are
//! read through raylib instead, so typing into text fields never fires sounds.

const std = @import("std");
const builtin = @import("builtin");
const c = @import("c");
const sys = @import("sys.zig");

pub const Mods = packed struct(u4) {
    ctrl: bool = false,
    shift: bool = false,
    alt: bool = false,
    super: bool = false,

    pub fn any(m: Mods) bool {
        return @as(u4, @bitCast(m)) != 0;
    }
};

pub const Hotkey = struct {
    mods: Mods = .{},
    key: c_int = 0,

    pub fn eql(a: Hotkey, b: Hotkey) bool {
        return a.key == b.key and @as(u4, @bitCast(a.mods)) == @as(u4, @bitCast(b.mods));
    }
};

const KeyInfo = struct {
    key: c_int,
    name: []const u8,
    x11: u32, // keysym
    vk: u32, // Windows virtual-key code
};

const key_table = blk: {
    var t: []const KeyInfo = &.{};
    // Letters and digits
    for (0..26) |i| {
        const upper = 'A' + i;
        t = t ++ [_]KeyInfo{.{ .key = @intCast(upper), .name = &[_]u8{upper}, .x11 = 'a' + i, .vk = upper }};
    }
    for (0..10) |i| {
        const d = '0' + i;
        t = t ++ [_]KeyInfo{.{ .key = @intCast(d), .name = &[_]u8{d}, .x11 = d, .vk = d }};
    }
    // F1–F12
    for (0..12) |i| {
        t = t ++ [_]KeyInfo{.{ .key = c.KEY_F1 + @as(c_int, @intCast(i)), .name = std.fmt.comptimePrint("F{d}", .{i + 1}), .x11 = 0xFFBE + i, .vk = 0x70 + i }};
    }
    // Numpad
    for (0..10) |i| {
        t = t ++ [_]KeyInfo{.{ .key = c.KEY_KP_0 + @as(c_int, @intCast(i)), .name = std.fmt.comptimePrint("Num{d}", .{i}), .x11 = 0xFFB0 + i, .vk = 0x60 + i }};
    }
    t = t ++ [_]KeyInfo{
        .{ .key = c.KEY_KP_DECIMAL, .name = "Num.", .x11 = 0xFFAE, .vk = 0x6E },
        .{ .key = c.KEY_KP_DIVIDE, .name = "Num/", .x11 = 0xFFAF, .vk = 0x6F },
        .{ .key = c.KEY_KP_MULTIPLY, .name = "Num*", .x11 = 0xFFAA, .vk = 0x6A },
        .{ .key = c.KEY_KP_SUBTRACT, .name = "Num-", .x11 = 0xFFAD, .vk = 0x6D },
        .{ .key = c.KEY_KP_ADD, .name = "Num+", .x11 = 0xFFAB, .vk = 0x6B },
        .{ .key = c.KEY_KP_ENTER, .name = "NumEnter", .x11 = 0xFF8D, .vk = 0x0D },
        .{ .key = c.KEY_SPACE, .name = "Space", .x11 = 0x20, .vk = 0x20 },
        .{ .key = c.KEY_APOSTROPHE, .name = "'", .x11 = 0x27, .vk = 0xDE },
        .{ .key = c.KEY_COMMA, .name = ",", .x11 = 0x2C, .vk = 0xBC },
        .{ .key = c.KEY_MINUS, .name = "-", .x11 = 0x2D, .vk = 0xBD },
        .{ .key = c.KEY_PERIOD, .name = ".", .x11 = 0x2E, .vk = 0xBE },
        .{ .key = c.KEY_SLASH, .name = "/", .x11 = 0x2F, .vk = 0xBF },
        .{ .key = c.KEY_SEMICOLON, .name = ";", .x11 = 0x3B, .vk = 0xBA },
        .{ .key = c.KEY_EQUAL, .name = "=", .x11 = 0x3D, .vk = 0xBB },
        .{ .key = c.KEY_LEFT_BRACKET, .name = "[", .x11 = 0x5B, .vk = 0xDB },
        .{ .key = c.KEY_BACKSLASH, .name = "\\", .x11 = 0x5C, .vk = 0xDC },
        .{ .key = c.KEY_RIGHT_BRACKET, .name = "]", .x11 = 0x5D, .vk = 0xDD },
        .{ .key = c.KEY_GRAVE, .name = "`", .x11 = 0x60, .vk = 0xC0 },
        .{ .key = c.KEY_ENTER, .name = "Enter", .x11 = 0xFF0D, .vk = 0x0D },
        .{ .key = c.KEY_TAB, .name = "Tab", .x11 = 0xFF09, .vk = 0x09 },
        .{ .key = c.KEY_BACKSPACE, .name = "Backspace", .x11 = 0xFF08, .vk = 0x08 },
        .{ .key = c.KEY_INSERT, .name = "Insert", .x11 = 0xFF63, .vk = 0x2D },
        .{ .key = c.KEY_DELETE, .name = "Delete", .x11 = 0xFFFF, .vk = 0x2E },
        .{ .key = c.KEY_RIGHT, .name = "Right", .x11 = 0xFF53, .vk = 0x27 },
        .{ .key = c.KEY_LEFT, .name = "Left", .x11 = 0xFF51, .vk = 0x25 },
        .{ .key = c.KEY_DOWN, .name = "Down", .x11 = 0xFF54, .vk = 0x28 },
        .{ .key = c.KEY_UP, .name = "Up", .x11 = 0xFF52, .vk = 0x26 },
        .{ .key = c.KEY_PAGE_UP, .name = "PageUp", .x11 = 0xFF55, .vk = 0x21 },
        .{ .key = c.KEY_PAGE_DOWN, .name = "PageDown", .x11 = 0xFF56, .vk = 0x22 },
        .{ .key = c.KEY_HOME, .name = "Home", .x11 = 0xFF50, .vk = 0x24 },
        .{ .key = c.KEY_END, .name = "End", .x11 = 0xFF57, .vk = 0x23 },
        .{ .key = c.KEY_SCROLL_LOCK, .name = "ScrollLock", .x11 = 0xFF14, .vk = 0x91 },
        .{ .key = c.KEY_PRINT_SCREEN, .name = "PrintScreen", .x11 = 0xFF61, .vk = 0x2C },
        .{ .key = c.KEY_PAUSE, .name = "Pause", .x11 = 0xFF13, .vk = 0x13 },
    };
    break :blk t;
};

fn infoFor(key: c_int) ?KeyInfo {
    for (key_table) |k| {
        if (k.key == key) return k;
    }
    return null;
}

pub fn parse(s: []const u8) ?Hotkey {
    if (s.len == 0) return null;
    var hk: Hotkey = .{};
    var parts = std.mem.splitScalar(u8, s, '+');
    var last: []const u8 = "";
    while (parts.next()) |raw| {
        // "Num+" style names contain the separator; re-attach an empty tail
        const p = std.mem.trim(u8, raw, " ");
        if (p.len == 0) {
            if (last.len > 0 and std.mem.endsWith(u8, last, "Num")) last = "Num+";
            continue;
        }
        if (std.ascii.eqlIgnoreCase(p, "ctrl") or std.ascii.eqlIgnoreCase(p, "control")) hk.mods.ctrl = true else if (std.ascii.eqlIgnoreCase(p, "shift")) hk.mods.shift = true else if (std.ascii.eqlIgnoreCase(p, "alt")) hk.mods.alt = true else if (std.ascii.eqlIgnoreCase(p, "super") or std.ascii.eqlIgnoreCase(p, "win") or std.ascii.eqlIgnoreCase(p, "meta")) hk.mods.super = true else last = p;
    }
    for (key_table) |k| {
        if (std.ascii.eqlIgnoreCase(k.name, last)) {
            hk.key = k.key;
            return hk;
        }
    }
    return null;
}

pub fn format(hk: Hotkey, buf: []u8) []const u8 {
    var w: std.Io.Writer = .fixed(buf);
    if (hk.mods.ctrl) w.writeAll("Ctrl+") catch {};
    if (hk.mods.shift) w.writeAll("Shift+") catch {};
    if (hk.mods.alt) w.writeAll("Alt+") catch {};
    if (hk.mods.super) w.writeAll("Super+") catch {};
    w.writeAll(if (infoFor(hk.key)) |k| k.name else "?") catch {};
    return w.buffered();
}

fn currentMods() Mods {
    return .{
        .ctrl = c.IsKeyDown(c.KEY_LEFT_CONTROL) or c.IsKeyDown(c.KEY_RIGHT_CONTROL),
        .shift = c.IsKeyDown(c.KEY_LEFT_SHIFT) or c.IsKeyDown(c.KEY_RIGHT_SHIFT),
        .alt = c.IsKeyDown(c.KEY_LEFT_ALT) or c.IsKeyDown(c.KEY_RIGHT_ALT),
        .super = c.IsKeyDown(c.KEY_LEFT_SUPER) or c.IsKeyDown(c.KEY_RIGHT_SUPER),
    };
}

/// In-window check (raylib). Exact modifier match.
pub fn pressedLocal(hk: Hotkey) bool {
    if (!c.IsKeyPressed(hk.key)) return false;
    return @as(u4, @bitCast(currentMods())) == @as(u4, @bitCast(hk.mods));
}

/// Hotkey capture for the editor: returns a combo once a non-modifier key is pressed
pub fn capture() ?Hotkey {
    var key = c.GetKeyPressed();
    while (key != 0) : (key = c.GetKeyPressed()) {
        if (infoFor(key) != null) return .{ .mods = currentMods(), .key = key };
    }
    return null;
}

// ── Global hotkeys ──────────────────────────────────────────────────────────

pub const Binding = struct {
    hotkey: Hotkey,
    action: u32,
};

const max_bindings = 256;

/// Thread-safe mailbox between the UI and the platform hotkey thread
var mutex: std.Io.Mutex = .init;
var bindings: [max_bindings]Binding = undefined;
var binding_count: usize = 0;
var generation: u32 = 0;
var suspended = true;
var fired: [32]u32 = undefined;
var fired_count: usize = 0;
var running = std.atomic.Value(bool).init(false);
pub var failed_count = std.atomic.Value(u32).init(0);
pub var backend_ok = std.atomic.Value(bool).init(false);

pub fn start() void {
    if (running.swap(true, .acq_rel)) return;
    const t = std.Thread.spawn(.{}, threadMain, .{}) catch {
        running.store(false, .release);
        return;
    };
    t.detach();
}

pub fn stop() void {
    running.store(false, .release);
}

/// Replaces the global bindings. Grabs are (re)applied by the hotkey thread.
pub fn setBindings(list: []const Binding) void {
    mutex.lockUncancelable(sys.io);
    defer mutex.unlock(sys.io);
    binding_count = @min(list.len, max_bindings);
    @memcpy(bindings[0..binding_count], list[0..binding_count]);
    generation +%= 1;
}

/// Suspends grabs (while our own window has focus)
pub fn setSuspended(s: bool) void {
    mutex.lockUncancelable(sys.io);
    defer mutex.unlock(sys.io);
    if (suspended != s) {
        suspended = s;
        generation +%= 1;
    }
}

pub fn poll() ?u32 {
    mutex.lockUncancelable(sys.io);
    defer mutex.unlock(sys.io);
    if (fired_count == 0) return null;
    const a = fired[0];
    std.mem.copyForwards(u32, fired[0 .. fired_count - 1], fired[1..fired_count]);
    fired_count -= 1;
    return a;
}

fn push(action: u32) void {
    mutex.lockUncancelable(sys.io);
    defer mutex.unlock(sys.io);
    if (fired_count < fired.len) {
        fired[fired_count] = action;
        fired_count += 1;
    }
}

/// Copies the current bindings if they changed since `seen`
fn snapshot(seen: *u32, out: []Binding) ?usize {
    mutex.lockUncancelable(sys.io);
    defer mutex.unlock(sys.io);
    if (generation == seen.*) return null;
    seen.* = generation;
    if (suspended) return 0;
    @memcpy(out[0..binding_count], bindings[0..binding_count]);
    return binding_count;
}

fn sleepMs(ms: i64) void {
    sys.io.sleep(.fromMilliseconds(ms), .awake) catch {};
}

fn threadMain() void {
    if (builtin.os.tag == .windows) windowsLoop() else x11Loop();
    running.store(false, .release);
}

// ── Windows: RegisterHotKey ─────────────────────────────────────────────────

const win = struct {
    const MSG = extern struct {
        hwnd: ?*anyopaque,
        message: u32,
        wParam: usize,
        lParam: isize,
        time: u32,
        pt_x: i32,
        pt_y: i32,
        lPrivate: u32,
    };
    extern "user32" fn RegisterHotKey(hwnd: ?*anyopaque, id: c_int, mods: c_uint, vk: c_uint) callconv(.winapi) c_int;
    extern "user32" fn UnregisterHotKey(hwnd: ?*anyopaque, id: c_int) callconv(.winapi) c_int;
    extern "user32" fn PeekMessageW(msg: *MSG, hwnd: ?*anyopaque, min: c_uint, max: c_uint, remove: c_uint) callconv(.winapi) c_int;
    const WM_HOTKEY = 0x0312;
    const PM_REMOVE = 1;
    const MOD_ALT = 1;
    const MOD_CONTROL = 2;
    const MOD_SHIFT = 4;
    const MOD_WIN = 8;
    const MOD_NOREPEAT = 0x4000;
};

fn windowsLoop() void {
    var seen: u32 = 0;
    var current: [max_bindings]Binding = undefined;
    var registered: usize = 0;
    backend_ok.store(true, .release);
    while (running.load(.acquire)) {
        if (snapshot(&seen, &current)) |n| {
            var i: usize = 0;
            while (i < registered) : (i += 1) _ = win.UnregisterHotKey(null, @intCast(i + 1));
            var failures: u32 = 0;
            for (current[0..n], 0..) |b, idx| {
                const info = infoFor(b.hotkey.key) orelse continue;
                var mods: c_uint = win.MOD_NOREPEAT;
                if (b.hotkey.mods.ctrl) mods |= win.MOD_CONTROL;
                if (b.hotkey.mods.shift) mods |= win.MOD_SHIFT;
                if (b.hotkey.mods.alt) mods |= win.MOD_ALT;
                if (b.hotkey.mods.super) mods |= win.MOD_WIN;
                if (win.RegisterHotKey(null, @intCast(idx + 1), mods, info.vk) == 0) failures += 1;
            }
            registered = n;
            failed_count.store(failures, .release);
        }
        var msg: win.MSG = undefined;
        while (win.PeekMessageW(&msg, null, 0, 0, win.PM_REMOVE) != 0) {
            if (msg.message == win.WM_HOTKEY and msg.wParam >= 1 and msg.wParam <= registered) {
                push(current[msg.wParam - 1].action);
            }
        }
        sleepMs(10);
    }
    var i: usize = 0;
    while (i < registered) : (i += 1) _ = win.UnregisterHotKey(null, @intCast(i + 1));
}

// ── X11: XGrabKey on the root window ────────────────────────────────────────

const x11 = struct {
    const Display = opaque {};
    const Window = c_ulong;
    const XKeyEvent = extern struct {
        type: c_int,
        serial: c_ulong,
        send_event: c_int,
        display: ?*Display,
        window: Window,
        root: Window,
        subwindow: Window,
        time: c_ulong,
        x: c_int,
        y: c_int,
        x_root: c_int,
        y_root: c_int,
        state: c_uint,
        keycode: c_uint,
        same_screen: c_int,
    };
    const XEvent = extern union {
        type: c_int,
        xkey: XKeyEvent,
        pad: [24]c_long,
    };
    const ErrorHandler = *const fn (?*Display, ?*anyopaque) callconv(.c) c_int;
    extern "X11" fn XOpenDisplay(name: ?[*:0]const u8) ?*Display;
    extern "X11" fn XCloseDisplay(d: *Display) c_int;
    extern "X11" fn XDefaultRootWindow(d: *Display) Window;
    extern "X11" fn XKeysymToKeycode(d: *Display, keysym: c_ulong) u8;
    extern "X11" fn XGrabKey(d: *Display, keycode: c_int, mods: c_uint, win: Window, owner_events: c_int, pointer_mode: c_int, keyboard_mode: c_int) c_int;
    extern "X11" fn XUngrabKey(d: *Display, keycode: c_int, mods: c_uint, win: Window) c_int;
    extern "X11" fn XPending(d: *Display) c_int;
    extern "X11" fn XNextEvent(d: *Display, ev: *XEvent) c_int;
    extern "X11" fn XSync(d: *Display, discard: c_int) c_int;
    extern "X11" fn XSetErrorHandler(handler: ?ErrorHandler) ?ErrorHandler;
    const ShiftMask = 1;
    const LockMask = 2;
    const ControlMask = 4;
    const Mod1Mask = 8; // Alt
    const Mod2Mask = 16; // NumLock
    const Mod4Mask = 64; // Super
    const KeyPress = 2;
    const GrabModeAsync = 1;
    const AnyKey = 0;
    const AnyModifier = 1 << 15;
};

fn ignoreXErrors(_: ?*x11.Display, _: ?*anyopaque) callconv(.c) c_int {
    // BadAccess when another app already owns a combo: just skip it
    return 0;
}

fn x11Mods(m: Mods) c_uint {
    var out: c_uint = 0;
    if (m.ctrl) out |= x11.ControlMask;
    if (m.shift) out |= x11.ShiftMask;
    if (m.alt) out |= x11.Mod1Mask;
    if (m.super) out |= x11.Mod4Mask;
    return out;
}

fn x11Loop() void {
    if (builtin.os.tag == .windows) return;
    const dpy = x11.XOpenDisplay(null) orelse return;
    defer _ = x11.XCloseDisplay(dpy);
    _ = x11.XSetErrorHandler(ignoreXErrors);
    const root = x11.XDefaultRootWindow(dpy);
    backend_ok.store(true, .release);

    var seen: u32 = 0;
    var current: [max_bindings]Binding = undefined;
    var codes: [max_bindings]u8 = undefined;
    var count: usize = 0;
    const lock_variants = [_]c_uint{ 0, x11.LockMask, x11.Mod2Mask, x11.LockMask | x11.Mod2Mask };
    const relevant: c_uint = x11.ShiftMask | x11.ControlMask | x11.Mod1Mask | x11.Mod4Mask;

    while (running.load(.acquire)) {
        if (snapshot(&seen, &current)) |n| {
            _ = x11.XUngrabKey(dpy, x11.AnyKey, x11.AnyModifier, root);
            count = n;
            for (current[0..n], 0..) |b, i| {
                codes[i] = 0;
                const info = infoFor(b.hotkey.key) orelse continue;
                codes[i] = x11.XKeysymToKeycode(dpy, info.x11);
                if (codes[i] == 0) continue;
                for (lock_variants) |extra| {
                    _ = x11.XGrabKey(dpy, codes[i], x11Mods(b.hotkey.mods) | extra, root, 1, x11.GrabModeAsync, x11.GrabModeAsync);
                }
            }
            _ = x11.XSync(dpy, 0);
        }
        while (x11.XPending(dpy) > 0) {
            var ev: x11.XEvent = undefined;
            _ = x11.XNextEvent(dpy, &ev);
            if (ev.type != x11.KeyPress) continue;
            const mods = ev.xkey.state & relevant;
            for (current[0..count], 0..) |b, i| {
                if (codes[i] == ev.xkey.keycode and x11Mods(b.hotkey.mods) == mods) push(b.action);
            }
        }
        sleepMs(8);
    }
    _ = x11.XUngrabKey(dpy, x11.AnyKey, x11.AnyModifier, root);
}

/// Wayland sessions only see grabs while an XWayland window has focus
pub fn waylandSession() bool {
    if (sys.is_windows) return false;
    const t = sys.getenv("XDG_SESSION_TYPE") orelse return false;
    return std.ascii.eqlIgnoreCase(t, "wayland");
}

test "hotkey parse and format" {
    var buf: [32]u8 = undefined;
    const hk = parse("Ctrl+Shift+F1").?;
    try std.testing.expect(hk.mods.ctrl and hk.mods.shift and !hk.mods.alt);
    try std.testing.expectEqualStrings("Ctrl+Shift+F1", format(hk, &buf));
    const plus = parse("Alt+Num+").?;
    try std.testing.expectEqualStrings("Alt+Num+", format(plus, &buf));
    try std.testing.expect(parse("Ctrl+") == null);
}
