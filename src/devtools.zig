//! Development aid: `WOOFER_AUTOSHOT=1 WooferSoundPad` walks through every
//! page, saves a screenshot of each into the working directory and quits.
//! Used to eyeball UI changes without clicking around.

const std = @import("std");
const sys = @import("sys.zig");
const ui = @import("ui.zig");
const app_mod = @import("app.zig");

var enabled = false;
/// WOOFER_GIF=1 also saves every frame of the mixer scene (gif-000.png...)
var gif = false;
var frame: u32 = 0;
var gif_name: [32]u8 = undefined;

pub fn init() void {
    enabled = sys.getenv("WOOFER_AUTOSHOT") != null;
    gif = sys.getenv("WOOFER_GIF") != null;
    if (enabled) @import("c").SetMousePosition(2, 790);
}

const Step = struct {
    at: u32,
    action: *const fn (*app_mod.App) void,
    shot: ?[:0]const u8 = null,
};

fn noop(_: *app_mod.App) void {}
fn closeTour(a: *app_mod.App) void {
    a.onboarding_open = false;
}
fn tourStep2(a: *app_mod.App) void {
    a.onboarding_step = 2;
}
fn soundboard(a: *app_mod.App) void {
    if (sys.getenv("WOOFER_AUTOSHOT_WS")) |name| {
        if (a.lib.find(name)) |i| a.switchWorkspace(i);
    }
    a.goto(.soundboard);
    for ([_]usize{ 1, 4 }) |i| {
        if (a.workspace().sounds.items.len > i) a.playSound(i);
    }
}
fn queue(a: *app_mod.App) void {
    a.stopAll();
    a.cfg.queue_open = true;
    for ([_]usize{ 2, 0, 5, 7, 3 }) |i| {
        if (a.workspace().sounds.items.len > i) a.enqueue(i);
    }
}
fn pause(a: *app_mod.App) void {
    a.togglePause();
}
fn resumeAndClose(a: *app_mod.App) void {
    a.togglePause();
    a.cfg.queue_open = false;
    a.queueClear();
}
fn padMenu(a: *app_mod.App) void {
    a.menu = .{ .kind = .pad, .index = 0, .pos = .{ .x = 520, .y = 320 } };
}
fn editor(a: *app_mod.App) void {
    a.menu = null;
    // A real recording makes a nicer waveform than a test tone
    const idx = a.findSoundByName("Howling") orelse 0;
    a.openEditor(idx);
    // Show a cut, a faster speed and a fade so every control has something to show
    const id = a.workspace().sounds.items[idx].audio_id;
    const full = @import("audio.zig").fullLength(id);
    a.editor.params.trim_start = full * 0.12;
    a.editor.params.trim_end = full * 0.78;
    a.editor.params.speed = 1.25;
    a.editor.params.fade_out = 0.4;
    a.previewEditorParams(idx);
    @import("audio.zig").play(id, 1, .restart);
}
fn closeDialog(a: *app_mod.App) void {
    @import("view_dialogs.zig").close(a);
}
fn explore(a: *app_mod.App) void {
    a.goto(.explore);
}
fn addFromExplore(a: *app_mod.App) void {
    const items = a.explore.items.items;
    for (items[0..@min(items.len, 2)]) |*it| a.addMarketItem(it, a.ws);
}
fn downloadClip(a: *app_mod.App) void {
    if (a.online.results.items.len == 0) return;
    const r = a.online.results.items[0];
    a.openDownloadDialog(r.url, r.title, r.duration);
    a.online.dlg_start.set("0");
    a.online.dlg_end.set("4");
}
fn confirmClip(a: *app_mod.App) void {
    if (a.dialog == .download_media) {
        a.confirmDownload();
        a.dialog = .none;
    }
}
fn online(a: *app_mod.App) void {
    a.goto(.online);
    a.online.search.set("husky howl");
    a.onlineSearch();
}
fn downloads(a: *app_mod.App) void {
    a.goto(.downloads);
}
fn settings(a: *app_mod.App) void {
    a.goto(.settings);
}
fn settingsScroll(_: *app_mod.App) void {
    ui.scrollTo(ui.id("settings-scroll", 0), 900);
}
fn settingsHotkeys(a: *app_mod.App) void {
    // Pretend the virtual mic exists to show the voice controls
    a.vmic_exists = true;
    a.vmic_has_voice = true;
    a.cfg.pause_hotkey = "Ctrl+Space";
    a.cfg.next_hotkey = "Ctrl+Right";
    ui.scrollTo(ui.id("settings-scroll", 0), 1420);
}
fn settingsScroll2(a: *app_mod.App) void {
    a.vmic_exists = null;
    ui.scrollTo(ui.id("settings-scroll", 0), 2400);
}
fn lightTheme(a: *app_mod.App) void {
    const theme = @import("theme.zig");
    ui.setTheme(theme.find("snow"), true);
    a.goto(.soundboard);
}
fn darkMixer(a: *app_mod.App) void {
    const theme = @import("theme.zig");
    ui.setTheme(theme.find("husky"), true);
    a.goto(.soundboard);
    a.cfg.mixer_open = true;
    a.cfg.queue_open = false;
    a.cfg.mixer_fade_seconds = 1.5;
    // A demonic variant, to show variants and effect tags on the pads
    if (a.workspace().sounds.items.len > 2 and a.workspace().fileUsers(a.workspace().sounds.items[2].file) < 2) {
        a.createVariant(2, 0);
        @import("view_dialogs.zig").close(a);
        a.dialog_closing = .none;
    }
    for ([_]usize{ 0, 2, 3 }) |i| {
        if (a.workspace().sounds.items.len > i) {
            a.workspace().sounds.items[i].loop = true;
            @import("audio.zig").setParams(a.workspace().sounds.items[i].audio_id, a.workspace().sounds.items[i].params());
            a.playSound(i);
        }
    }
}
fn hoverMore(_: *app_mod.App) void {
    const r = @import("view_soundboard.zig").debug_more_rect;
    @import("c").SetMousePosition(@intFromFloat((r.x + r.w / 2) * ui.scale), @intFromFloat((r.y + r.h / 2) * ui.scale));
}
fn openMoreMenu(a: *app_mod.App) void {
    const r = @import("view_soundboard.zig").debug_more_rect;
    a.menu = .{ .kind = .pad, .index = 0, .pos = .{ .x = r.right() - 240, .y = r.bottom() + 4 } };
}
fn stage(a: *app_mod.App) void {
    a.menu = null;
    @import("c").SetMousePosition(2, 790);
    a.cfg.stage_fullscreen = false;
    a.setStage(true);
}
fn stageOff(a: *app_mod.App) void {
    a.setStage(false);
    a.stopAll();
}
fn editorFx(a: *app_mod.App) void {
    const idx = a.findSoundByName("Howling") orelse 0;
    a.openEditor(idx);
    a.editor.tab = .effects;
    const fx = @import("fx.zig");
    a.editor.fx = fx.Chain.fromSlice(fx.builtins[10].effects);
    a.editor.params.trim_start = 0.3;
    a.editor.params.fade_in = 0.4;
    a.editor.params.fade_out = 0.6;
    a.previewEditorParams(idx);
    a.previewEditorFx(idx);
    @import("audio.zig").play(a.workspace().sounds.items[idx].audio_id, 1, .restart);
}
fn editorPicker(a: *app_mod.App) void {
    a.editor.add_menu = true;
}
fn editorSound(a: *app_mod.App) void {
    a.editor.add_menu = false;
    a.editor.tab = .sound;
    a.editor.view_start = 0.4;
    a.editor.view_len = 1.5;
}
fn editorPad(a: *app_mod.App) void {
    a.editor.tab = .pad;
}
fn recorder(a: *app_mod.App) void {
    @import("view_dialogs.zig").close(a);
    a.dialog_closing = .none;
    a.openRecorder();
    a.startRecording();
}
fn recorderStop(a: *app_mod.App) void {
    a.stopRecording();
}
fn statsPage(a: *app_mod.App) void {
    a.discardRecording();
    @import("view_dialogs.zig").close(a);
    a.goto(.stats);
}
fn integrations(a: *app_mod.App) void {
    a.goto(.settings);
    ui.scrollTo(ui.id("settings-scroll", 0), 2260);
}
fn quit(a: *app_mod.App) void {
    a.quit_requested = true;
}

const steps = [_]Step{
    .{ .at = 60, .action = noop, .shot = "shot-01-tour.png" },
    .{ .at = 61, .action = tourStep2 },
    .{ .at = 110, .action = noop, .shot = "shot-02-tour-step3.png" },
    .{ .at = 111, .action = closeTour },
    .{ .at = 112, .action = soundboard },
    .{ .at = 150, .action = noop, .shot = "shot-03-soundboard.png" },
    .{ .at = 151, .action = queue },
    .{ .at = 185, .action = noop, .shot = "shot-03b-queue.png" },
    .{ .at = 186, .action = pause },
    .{ .at = 205, .action = noop, .shot = "shot-03c-paused.png" },
    .{ .at = 206, .action = resumeAndClose },
    .{ .at = 207, .action = padMenu },
    .{ .at = 230, .action = noop, .shot = "shot-04-menu.png" },
    .{ .at = 231, .action = editor },
    .{ .at = 252, .action = noop, .shot = "shot-05-editor.png" },
    .{ .at = 276, .action = closeDialog },
    .{ .at = 290, .action = explore },
    .{ .at = 520, .action = noop, .shot = "shot-06-explore.png" },
    .{ .at = 521, .action = addFromExplore },
    .{ .at = 522, .action = online },
    .{ .at = 900, .action = noop, .shot = "shot-07-online.png" },
    .{ .at = 901, .action = downloadClip },
    .{ .at = 940, .action = noop, .shot = "shot-07b-download-dialog.png" },
    .{ .at = 941, .action = confirmClip },
    .{ .at = 942, .action = downloads },
    .{ .at = 980, .action = noop, .shot = "shot-08-downloads.png" },
    .{ .at = 981, .action = settings },
    .{ .at = 1030, .action = noop, .shot = "shot-09-settings.png" },
    .{ .at = 1031, .action = settingsScroll },
    .{ .at = 1070, .action = noop, .shot = "shot-10-settings2.png" },
    .{ .at = 1071, .action = settingsHotkeys },
    .{ .at = 1100, .action = noop, .shot = "shot-10b-hotkeys.png" },
    .{ .at = 1101, .action = settingsScroll2 },
    .{ .at = 1110, .action = noop, .shot = "shot-11-settings3.png" },
    .{ .at = 1111, .action = downloads },
    .{ .at = 1500, .action = noop, .shot = "shot-13-downloads-done.png" },
    .{ .at = 1501, .action = soundboard },
    .{ .at = 1560, .action = noop, .shot = "shot-14-soundboard-after.png" },
    .{ .at = 1561, .action = lightTheme },
    .{ .at = 1600, .action = noop, .shot = "shot-12-light.png" },
    .{ .at = 1601, .action = darkMixer },
    .{ .at = 1660, .action = noop, .shot = "shot-20-mixer.png" },
    .{ .at = 1661, .action = hoverMore },
    .{ .at = 1700, .action = noop, .shot = "shot-21-hover-more-a.png" },
    .{ .at = 1701, .action = noop, .shot = "shot-21-hover-more-b.png" },
    .{ .at = 1730, .action = noop, .shot = "shot-21-hover-more-c.png" },
    .{ .at = 1731, .action = openMoreMenu },
    .{ .at = 1760, .action = noop, .shot = "shot-22-pad-menu.png" },
    .{ .at = 1761, .action = stage },
    .{ .at = 1820, .action = noop, .shot = "shot-23-stage.png" },
    .{ .at = 1821, .action = stageOff },
    .{ .at = 1830, .action = editorFx },
    .{ .at = 1890, .action = noop, .shot = "shot-24-editor-fx.png" },
    .{ .at = 1891, .action = editorPicker },
    .{ .at = 1920, .action = noop, .shot = "shot-25-editor-picker.png" },
    .{ .at = 1921, .action = editorSound },
    .{ .at = 1950, .action = noop, .shot = "shot-26-editor-sound.png" },
    .{ .at = 1951, .action = editorPad },
    .{ .at = 1980, .action = noop, .shot = "shot-27-editor-pad.png" },
    .{ .at = 1981, .action = recorder },
    .{ .at = 2080, .action = noop, .shot = "shot-28-recording.png" },
    .{ .at = 2081, .action = recorderStop },
    .{ .at = 2110, .action = noop, .shot = "shot-29-recorded.png" },
    .{ .at = 2111, .action = statsPage },
    .{ .at = 2170, .action = noop, .shot = "shot-30-stats.png" },
    .{ .at = 2171, .action = integrations },
    .{ .at = 2230, .action = noop, .shot = "shot-31-integrations.png" },
    .{ .at = 2231, .action = quit },
};

/// Called once per frame before drawing
pub fn update(a: *app_mod.App) void {
    if (!enabled) return;
    frame += 1;
    if (gif and frame >= 1606 and frame < 1660) {
        ui.screenshot_path = std.fmt.bufPrintSentinel(&gif_name, "gif-{d:0>3}.png", .{frame - 1606}, 0) catch null;
    }
    for (steps) |s| {
        if (s.at == frame) {
            s.action(a);
            if (s.shot) |name| ui.screenshot_path = name;
        }
    }
}
