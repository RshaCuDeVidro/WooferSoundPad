//! Settings: appearance, audio, virtual mic, hotkeys, library, tools, about.

const std = @import("std");
const c = @import("c");
const build_options = @import("build_options");
const ui = @import("ui.zig");
const theme = @import("theme.zig");
const sys = @import("sys.zig");
const config = @import("config.zig");
const audio = @import("audio.zig");
const tools = @import("tools.zig");
const jobs = @import("jobs.zig");
const vmic = @import("vmic.zig");
const hotkeys = @import("hotkeys.zig");
const view = @import("view.zig");
const remote = @import("remote.zig");
const app_mod = @import("app.zig");
const App = app_mod.App;
const icons = ui.icons;
const Rect = ui.Rect;
const Rgba = ui.Rgba;

const row_h: f32 = 66;
const control_w: f32 = 300;

const Layout = struct {
    x: f32,
    w: f32,
    y: f32,
};

pub fn draw(a: *App, area: Rect) void {
    var r = area.insetXY(view.page_pad_x, 0);
    _ = view.header(&r, a.t.settings_title, a.t.settings_sub);
    const width = @min(r.w - 10, 860);
    const scroll_key = ui.id("settings-scroll", 0);
    const top = ui.beginScroll(scroll_key, r);
    var l: Layout = .{ .x = r.x + (r.w - 10 - width) / 2, .w = width, .y = top };

    appearance(a, &l);
    audioSection(a, &l);
    virtualMic(a, &l);
    hotkeySection(a, &l);
    integrationsSection(a, &l);
    librarySection(a, &l);
    toolsSection(a, &l);
    about(a, &l);

    ui.endScroll(l.y - top + 30);
}

// ── Building blocks ─────────────────────────────────────────────────────────

fn sectionHeader(l: *Layout, ic: u21, title: []const u8) void {
    l.y += 12;
    ui.icon(ic, .{ .x = l.x + 9, .y = l.y + 15 }, 15, ui.colors.accent);
    _ = ui.text(title, l.x + 26, l.y + 7, 15, .display, ui.colors.text);
    l.y += 44;
}

/// Card background for `rows` rows plus `extra` pixels
fn card(l: *const Layout, rows: usize, extra: f32) Rect {
    const r: Rect = .{ .x = l.x, .y = l.y, .w = l.w, .h = @as(f32, @floatFromInt(rows)) * row_h + extra };
    ui.rect(r, ui.radius_lg, ui.colors.surface);
    ui.border(r, ui.radius_lg, 1, ui.colors.border);
    return r;
}

/// One setting row; returns the control area on the right
fn row(l: *Layout, title: []const u8, desc: []const u8, first: bool) Rect {
    const r: Rect = .{ .x = l.x, .y = l.y, .w = l.w, .h = row_h };
    if (!first) ui.rect(.{ .x = r.x + 18, .y = r.y, .w = r.w - 36, .h = 1 }, 0, ui.colors.border.alpha(0.7));
    const text_w = r.w - control_w - 50;
    if (desc.len > 0) {
        ui.label(title, .{ .x = r.x + 20, .y = r.y + 13, .w = text_w, .h = 20 }, 14, .semibold, ui.colors.text, .left);
        ui.label(desc, .{ .x = r.x + 20, .y = r.y + 34, .w = text_w, .h = 18 }, 12, .regular, ui.colors.text_muted, .left);
    } else {
        ui.label(title, .{ .x = r.x + 20, .y = r.y, .w = text_w, .h = r.h }, 14, .semibold, ui.colors.text, .left);
    }
    l.y += row_h;
    return .{ .x = r.right() - 20 - control_w, .y = r.y + (r.h - 36) / 2, .w = control_w, .h = 36 };
}

fn sectionEnd(l: *Layout) void {
    l.y += 22;
}

fn percentSlider(a: *App, key: u64, ctrl: Rect, value: *f32, min: f32, max: f32) bool {
    var buf: [16]u8 = undefined;
    const txt = std.fmt.bufPrint(&buf, "{d:.0}%", .{value.* * 100}) catch "";
    ui.label(txt, .{ .x = ctrl.right() - 48, .y = ctrl.y, .w = 48, .h = ctrl.h }, 13, .semibold, ui.colors.text_muted, .right);
    const changed = ui.slider(key, .{ .x = ctrl.x, .y = ctrl.y, .w = ctrl.w - 56, .h = ctrl.h }, value, min, max);
    if (changed) a.markConfig();
    return changed;
}

// ── Appearance ──────────────────────────────────────────────────────────────

fn appearance(a: *App, l: *Layout) void {
    sectionHeader(l, icons.palette, a.t.sec_appearance);

    // Theme gallery
    const tile_w: f32 = 152;
    const tile_h: f32 = 112;
    const gap: f32 = 12;
    const cols: usize = @max(1, @as(usize, @intFromFloat((l.w - 40 + gap) / (tile_w + gap))));
    const rows_n = (theme.themes.len + cols - 1) / cols;
    const gallery_h = @as(f32, @floatFromInt(rows_n)) * (tile_h + gap) - gap + 64;
    const cr = card(l, 6, gallery_h);
    _ = ui.text(a.t.theme, cr.x + 20, cr.y + 18, 14, .semibold, ui.colors.text);
    const cols_f: f32 = @floatFromInt(cols);
    const real_w = (l.w - 40 - gap * (cols_f - 1)) / cols_f;
    for (&theme.themes, 0..) |*th, i| {
        const tr: Rect = .{
            .x = cr.x + 20 + @as(f32, @floatFromInt(i % cols)) * (real_w + gap),
            .y = cr.y + 48 + @as(f32, @floatFromInt(i / cols)) * (tile_h + gap),
            .w = real_w,
            .h = tile_h,
        };
        themeTile(a, th, tr);
    }
    l.y += gallery_h;

    // Language
    var ctrl = row(l, a.t.language, "", false);
    const langs = [_][]const u8{ "English", "Português (Brasil)" };
    var lang_idx: usize = @backingInt(a.cfg.language);
    if (ui.dropdown(ui.id("set-lang", 0), ctrl, &langs, &lang_idx)) {
        a.cfg.language = @fromBackingInt(@intCast(lang_idx));
        a.markConfig();
    }

    // Interface size (applied when the slider is released)
    ctrl = row(l, a.t.ui_scale, a.t.ui_scale_desc, false);
    _ = percentSlider(a, ui.id("set-scale", 0), ctrl, &a.cfg.ui_scale, 0.75, 2.0);

    ctrl = row(l, a.t.animations, a.t.animations_desc, false);
    if (ui.toggle(ui.id("set-anim", 0), ctrl, &a.cfg.animations)) {
        ui.animations = a.cfg.animations;
        a.markConfig();
    }

    ctrl = row(l, a.t.pad_size, "", false);
    const sizes = [_]ui.Segment{ .{ .label = a.t.size_small }, .{ .label = a.t.size_medium }, .{ .label = a.t.size_large } };
    var size_idx: usize = @backingInt(a.cfg.pad_size);
    if (ui.segmented(ui.id("set-padsize", 0), ctrl, &sizes, &size_idx)) {
        a.cfg.pad_size = @fromBackingInt(@intCast(size_idx));
        a.markConfig();
    }

    ctrl = row(l, a.t.show_hotkeys, "", false);
    if (ui.toggle(ui.id("set-showkeys", 0), ctrl, &a.cfg.show_hotkeys_on_pads)) a.markConfig();

    ctrl = row(l, a.t.show_waveforms, a.t.show_waveforms_desc, false);
    if (ui.toggle(ui.id("set-waves", 0), ctrl, &a.cfg.show_waveforms)) a.markConfig();

    ctrl = row(l, a.t.stage_fullscreen, a.t.stage_fullscreen_desc, false);
    if (ui.toggle(ui.id("set-stage-fs", 0), ctrl, &a.cfg.stage_fullscreen)) a.markConfig();
    sectionEnd(l);
}

fn themeTile(a: *App, th: *const theme.Theme, r: Rect) void {
    const key = ui.idStr("theme", th.id);
    const in = ui.interact(key, r);
    const selected = std.mem.eql(u8, a.cfg.theme, th.id);
    const sel_t = ui.anim(ui.sub(key, 1), if (selected) 1 else 0, 14);
    const t = th.colors;
    const tr = r.offset(0, -in.hover_t * 3);

    ui.shadow(tr.offset(0, 4), ui.radius_lg, 8 + in.hover_t * 8, ui.colors.shadow.alpha(0.5));
    if (sel_t > 0.01) ui.rect(tr.grow(3), ui.radius_lg, ui.colors.accent.alpha(sel_t));
    // Mini app preview drawn in the theme's own colors
    ui.rect(tr, ui.radius_lg, t.bg);
    ui.rect(.{ .x = tr.x, .y = tr.y, .w = 34, .h = tr.h - 30 }, ui.radius_lg, t.sidebar);
    ui.rect(.{ .x = tr.x + 30, .y = tr.y, .w = 4, .h = tr.h - 30 }, 0, t.sidebar);
    for (0..3) |i| {
        const fi: f32 = @floatFromInt(i);
        ui.rect(.{ .x = tr.x + 8, .y = tr.y + 12 + fi * 12, .w = 18, .h = 5 }, 2.5, if (i == 0) t.accent else t.text_faint);
    }
    const pad_w = (tr.w - 34 - 30) / 3;
    const pad_cols = [_]Rgba{ t.accent, t.accent2, t.success };
    for (pad_cols, 0..) |pc, i| {
        const fi: f32 = @floatFromInt(i);
        const pr: Rect = .{ .x = tr.x + 42 + fi * (pad_w + 6), .y = tr.y + 14, .w = pad_w, .h = 36 };
        ui.rect(pr, 6, t.surface);
        ui.rectGradientV(pr, 6, pc.alpha(0.3), pc.alpha(0.05));
        ui.circle(.{ .x = pr.x + 9, .y = pr.y + 10 }, 5, pc);
    }
    ui.rect(.{ .x = tr.x + 42, .y = tr.y + 58, .w = tr.w * 0.4, .h = 5 }, 2.5, t.text_muted);
    // Name strip
    const strip: Rect = .{ .x = tr.x, .y = tr.bottom() - 30, .w = tr.w, .h = 30 };
    ui.rect(strip, ui.radius_lg, t.surface);
    ui.rect(.{ .x = strip.x, .y = strip.y, .w = strip.w, .h = 12 }, 0, t.surface);
    ui.label(th.name, strip.insetXY(10, 0), 12, .semibold, t.text, .left);
    if (sel_t > 0.01) {
        const b: ui.Vec2 = .{ .x = tr.right() - 16, .y = strip.y + 15 };
        ui.circle(b, 9 * ui.easeOutBack(sel_t), t.accent);
        ui.icon(icons.check, b, 11 * sel_t, t.accent_text);
    }
    ui.border(tr, ui.radius_lg, 1, t.border);

    if (in.clicked and !selected) {
        config.setString(&a.cfg.theme, th.id);
        ui.setTheme(th, false);
        a.markConfig();
    }
}

// ── Audio ───────────────────────────────────────────────────────────────────

var device_items: std.ArrayList([]const u8) = .empty;
var mic_items: std.ArrayList([]const u8) = .empty;

fn audioSection(a: *App, l: *Layout) void {
    sectionHeader(l, icons.headphones, a.t.sec_audio);
    if (ui.button(ui.id("set-refresh", 0), .{ .x = l.x + l.w - 190, .y = l.y - 46, .w = 190, .h = 34 }, a.t.refresh_devices, .{ .icon = icons.refresh_cw, .style = .ghost, .size = 13 })) {
        audio.refreshDevices();
        _ = audio.setOutput(.monitor, a.cfg.monitor_device);
        _ = audio.setOutput(.mic, a.cfg.mic_device);
    }
    _ = card(l, 8, 0);

    device_items.clearRetainingCapacity();
    mic_items.clearRetainingCapacity();
    device_items.append(sys.gpa, a.t.system_default) catch {};
    mic_items.append(sys.gpa, a.t.off) catch {};
    for (audio.device_names.items) |d| {
        device_items.append(sys.gpa, d) catch {};
        mic_items.append(sys.gpa, d) catch {};
    }

    var ctrl = row(l, a.t.output_device, a.t.output_desc, true);
    var mon_idx: usize = if (audio.deviceIndex(a.cfg.monitor_device)) |i| @as(usize, @intCast(i)) + 1 else 0;
    if (ui.dropdown(ui.id("set-out", 0), ctrl, device_items.items, &mon_idx)) {
        config.setString(&a.cfg.monitor_device, if (mon_idx == 0) "" else device_items.items[mon_idx]);
        if (!audio.setOutput(.monitor, a.cfg.monitor_device)) ui.toast(.err, a.t.audio_failed);
        a.reloadAudio();
        a.markConfig();
    }

    ctrl = row(l, a.t.mic_device, a.t.mic_desc, false);
    var mic_idx: usize = if (audio.deviceIndex(a.cfg.mic_device)) |i| @as(usize, @intCast(i)) + 1 else 0;
    if (ui.dropdown(ui.id("set-mic", 0), ctrl, mic_items.items, &mic_idx)) {
        config.setString(&a.cfg.mic_device, if (mic_idx == 0) "" else mic_items.items[mic_idx]);
        _ = audio.setOutput(.mic, a.cfg.mic_device);
        a.reloadAudio();
        a.markConfig();
    }

    ctrl = row(l, a.t.monitor_volume, "", false);
    if (percentSlider(a, ui.id("set-monvol", 0), ctrl, &a.cfg.monitor_volume, 0, 1)) audio.applyVolumes(&a.cfg);
    ctrl = row(l, a.t.mic_volume, "", false);
    if (percentSlider(a, ui.id("set-micvol", 0), ctrl, &a.cfg.mic_volume, 0, 1)) audio.applyVolumes(&a.cfg);
    ctrl = row(l, a.t.preview_volume, "", false);
    _ = percentSlider(a, ui.id("set-prevol", 0), ctrl, &a.cfg.preview_volume, 0, 1);

    ctrl = row(l, a.t.play_mode, "", false);
    const modes = [_]ui.Segment{ .{ .label = a.t.mode_restart }, .{ .label = a.t.mode_overlap }, .{ .label = a.t.mode_toggle } };
    var mode_idx: usize = @backingInt(a.cfg.play_mode);
    if (ui.segmented(ui.id("set-mode", 0), ctrl, &modes, &mode_idx)) {
        a.cfg.play_mode = @fromBackingInt(@intCast(mode_idx));
        a.markConfig();
    }

    // Library-wide normalization
    ctrl = row(l, a.t.normalize_lib, a.t.normalize_lib_desc, false);
    if (ui.toggle(ui.id("set-normlib", 0), ctrl, &a.cfg.normalize_library)) a.markConfig();
    const prog = a.loudnessProgress();
    const status = if (!a.cfg.normalize_library) a.t.normalize_off else if (prog.done < prog.total) a.tf(a.t.normalize_progress, .{ prog.done, prog.total }) else a.tf(a.t.normalize_done, .{prog.total});
    ctrl = row(l, a.t.normalize_target, status, false);
    ui.pushAlpha(if (a.cfg.normalize_library) 1 else 0.4);
    var tb: [16]u8 = undefined;
    ui.label(std.fmt.bufPrint(&tb, "{d:.0} dB", .{a.cfg.normalize_target}) catch "", .{ .x = ctrl.right() - 56, .y = ctrl.y, .w = 56, .h = ctrl.h }, 13, .mono, ui.colors.text_muted, .right);
    if (ui.slider(ui.id("set-normtarget", 0), .{ .x = ctrl.x, .y = ctrl.y, .w = ctrl.w - 64, .h = ctrl.h }, &a.cfg.normalize_target, -30, -8) and a.cfg.normalize_library) {
        a.cfg.normalize_target = @round(a.cfg.normalize_target);
        a.markConfig();
    }
    ui.popAlpha();
    sectionEnd(l);
}

// ── Virtual microphone ──────────────────────────────────────────────────────

fn virtualMic(a: *App, l: *Layout) void {
    sectionHeader(l, icons.mic, a.t.sec_vmic);
    if (sys.is_windows) {
        const found = audio.findVirtualDevice();
        const cr = card(l, 1, 140);
        const status_r: Rect = .{ .x = cr.x + 20, .y = cr.y + 18, .w = cr.w - 40, .h = 30 };
        statusDot(status_r, found != null, if (found != null) a.t.vbcable_found else a.t.vbcable_missing);
        var bx = cr.right() - 20;
        if (found) |idx| {
            const name = audio.device_names.items[@intCast(idx)];
            if (!std.mem.eql(u8, a.cfg.mic_device, name)) {
                bx -= 110;
                if (ui.button(ui.id("vb-use", 0), .{ .x = bx, .y = cr.y + 14, .w = 110, .h = 36 }, a.t.use_it, .{ .style = .primary, .icon = icons.check })) {
                    config.setString(&a.cfg.mic_device, name);
                    _ = audio.setOutput(.mic, name);
                    a.reloadAudio();
                    a.markConfig();
                }
                bx -= 10;
            }
        }
        bx -= 170;
        if (ui.button(ui.id("vb-get", 0), .{ .x = bx, .y = cr.y + 14, .w = 170, .h = 36 }, a.t.get_vbcable, .{ .icon = icons.external_link })) sys.openUrl(vmic.vbcable_url);
        const text_r: Rect = .{ .x = cr.x + 20, .y = cr.y + 66, .w = cr.w - 40, .h = 100 };
        const used = ui.paragraph(a.t.vmic_windows_desc, text_r, 13, .regular, ui.colors.text_muted, 1.45, true);
        const used2 = ui.paragraph(a.t.vmic_windows_tip, text_r.offset(0, used + 8), 12, .regular, ui.colors.text_faint, 1.45, true);
        _ = ui.paragraph(a.t.voice_windows_note, text_r.offset(0, used + used2 + 14), 12, .regular, ui.colors.text_faint, 1.45, true);
        l.y += row_h + 140;
        sectionEnd(l);
        return;
    }

    _ = a.voiceAvailable(); // refreshes the cached status
    const exists = a.vmic_exists.?;
    const voice_rows: usize = if (exists and a.vmic_has_voice) 2 else 0;
    const cr = card(l, 1 + voice_rows, 86);
    statusDot(.{ .x = cr.x + 20, .y = cr.y + 18, .w = cr.w - 40, .h = 30 }, exists, if (exists) a.t.vmic_status_on else a.t.vmic_status_off);
    const btn_r: Rect = .{ .x = cr.right() - 20 - 200, .y = cr.y + 14, .w = 200, .h = 38 };
    if (exists) {
        if (ui.button(ui.id("vmic-remove", 0), .{ .x = btn_r.right() - 120, .y = btn_r.y, .w = 120, .h = 38 }, a.t.vmic_remove, .{ .style = .danger, .icon = icons.trash_2 })) {
            if (a.cfg.mic_device.len > 0 and vmic.isVirtualOutput(a.cfg.mic_device)) {
                config.setString(&a.cfg.mic_device, "");
                _ = audio.setOutput(.mic, "");
            }
            vmic.remove();
            a.vmic_exists = null;
            audio.refreshDevices();
            a.markConfig();
        }
    } else if (ui.button(ui.id("vmic-create", 0), btn_r, a.t.vmic_create, .{ .style = .primary, .icon = icons.wand_sparkles })) {
        if (vmic.create(a.vmic_include_mic)) {
            audio.refreshDevices();
            if (audio.findVirtualDevice()) |idx| {
                config.setString(&a.cfg.mic_device, audio.device_names.items[@intCast(idx)]);
                _ = audio.setOutput(.mic, a.cfg.mic_device);
                a.reloadAudio();
                a.markConfig();
            }
            if (a.cfg.voice_volume != 1 or a.cfg.voice_muted) vmic.setVoice(a.cfg.voice_volume, a.cfg.voice_muted);
            ui.toast(.success, a.t.vmic_created);
        } else |_| ui.toast(.err, a.t.vmic_failed);
        a.vmic_exists = null;
    }
    ui.label(a.t.vmic_linux_desc, .{ .x = cr.x + 20, .y = cr.y + 58, .w = cr.w - 40, .h = 20 }, 12, .regular, ui.colors.text_muted, .left);
    l.y += 86;
    const toggle_ctrl = row(l, a.t.vmic_include_mic, if (exists) a.t.vmic_include_mic_desc else "", false);
    _ = ui.toggle(ui.id("vmic-include", 0), toggle_ctrl, &a.vmic_include_mic);

    // Your own voice, mixed in through the loopback
    if (voice_rows > 0) {
        var ctrl = row(l, a.t.voice_volume, a.t.voice_volume_desc, false);
        if (percentSlider(a, ui.id("set-voicevol", 0), ctrl, &a.cfg.voice_volume, 0, 1.5)) {
            vmic.setVoice(a.cfg.voice_volume, a.cfg.voice_muted);
        }
        ctrl = row(l, a.t.mute_voice, a.t.mute_voice_desc, false);
        if (ui.toggle(ui.id("set-voicemute", 0), ctrl, &a.cfg.voice_muted)) {
            vmic.setVoice(a.cfg.voice_volume, a.cfg.voice_muted);
            a.markConfig();
        }
    }
    sectionEnd(l);
}

fn statusDot(r: Rect, on: bool, text_str: []const u8) void {
    const col = if (on) ui.colors.success else ui.colors.warning;
    const pulse = 0.5 + 0.5 * @sin(ui.time * 3);
    ui.circle(.{ .x = r.x + 6, .y = r.y + r.h / 2 }, 6 + pulse * 4, col.alpha(0.25 * (1 - pulse)));
    ui.circle(.{ .x = r.x + 6, .y = r.y + r.h / 2 }, 5, col);
    ui.label(text_str, .{ .x = r.x + 22, .y = r.y, .w = r.w - 260, .h = r.h }, 14, .semibold, ui.colors.text, .left);
}

// ── Hotkeys ─────────────────────────────────────────────────────────────────

fn hotkeySection(a: *App, l: *Layout) void {
    sectionHeader(l, icons.keyboard, a.t.sec_hotkeys);
    const wayland = hotkeys.waylandSession();
    const voice_row: usize = if (sys.is_windows) 0 else 1;
    _ = card(l, 6 + voice_row, if (wayland) 96 else 0);

    var ctrl = row(l, a.t.global_hotkeys, a.t.global_hotkeys_desc, true);
    if (ui.toggle(ui.id("set-global", 0), ctrl, &a.cfg.global_hotkeys)) {
        if (a.cfg.global_hotkeys) hotkeys.start() else hotkeys.stop();
        a.bindings_dirty = true;
        a.markConfig();
    }
    const failed = hotkeys.failed_count.load(.acquire);
    if (failed > 0) {
        ui.label(a.tf(a.t.hotkeys_failed, .{failed}), .{ .x = ctrl.x - 240, .y = ctrl.y, .w = 230, .h = ctrl.h }, 12, .semibold, ui.colors.warning, .right);
    }

    ctrl = row(l, a.t.stop_hotkey, "", false);
    hotkeyField(a, ui.id("set-stopkey", 0), ctrl, .stop, &a.cfg.stop_hotkey);
    ctrl = row(l, a.t.pause_hotkey, a.t.pause_hotkey_desc, false);
    hotkeyField(a, ui.id("set-pausekey", 0), ctrl, .pause, &a.cfg.pause_hotkey);
    ctrl = row(l, a.t.next_hotkey, "", false);
    hotkeyField(a, ui.id("set-nextkey", 0), ctrl, .next, &a.cfg.next_hotkey);
    ctrl = row(l, a.t.random_hotkey, "", false);
    hotkeyField(a, ui.id("set-randkey", 0), ctrl, .random, &a.cfg.random_hotkey);
    if (voice_row > 0) {
        ctrl = row(l, a.t.mute_voice_hotkey, "", false);
        hotkeyField(a, ui.id("set-mutekey", 0), ctrl, .mute_voice, &a.cfg.mute_voice_hotkey);
    }

    ctrl = row(l, a.t.number_keys, "", false);
    if (ui.toggle(ui.id("set-numkeys", 0), ctrl, &a.cfg.number_keys_play)) a.markConfig();

    if (wayland) {
        const box: Rect = .{ .x = l.x + 20, .y = l.y + 4, .w = l.w - 40, .h = 80 };
        ui.label(a.t.wayland_note, .{ .x = box.x, .y = box.y, .w = box.w, .h = 20 }, 12, .regular, ui.colors.text_muted, .left);
        const cmd = "WooferSoundPad --play \"sound name\"";
        const code: Rect = .{ .x = box.x, .y = box.y + 28, .w = box.w - 110, .h = 38 };
        ui.rect(code, ui.radius_md, ui.colors.bg);
        ui.border(code, ui.radius_md, 1, ui.colors.border);
        ui.icon(icons.terminal, .{ .x = code.x + 18, .y = code.y + 19 }, 15, ui.colors.accent);
        _ = ui.text(cmd, code.x + 36, code.y + 11, 13, .semibold, ui.colors.text);
        if (ui.button(ui.id("copy-cmd", 0), .{ .x = code.right() + 10, .y = code.y, .w = 100, .h = 38 }, a.t.copy, .{ .icon = icons.copy })) {
            c.SetClipboardText(cmd);
            ui.toast(.success, a.t.copied);
        }
        l.y += 96;
    }
    sectionEnd(l);
}

fn hotkeyField(a: *App, key: u64, r: Rect, kind: app_mod.Capture, value: *[]const u8) void {
    const capturing = a.capture == kind;
    if (capturing) {
        ui.claimFocus(key);
        if (c.IsKeyPressed(c.KEY_ESCAPE)) {
            a.capture = .none;
            ui.focus = 0;
        } else if (hotkeys.capture()) |hk| {
            var buf: [48]u8 = undefined;
            config.setString(value, hotkeys.format(hk, &buf));
            a.capture = .none;
            ui.focus = 0;
            a.bindings_dirty = true;
            a.markConfig();
        }
    }
    const field: Rect = .{ .x = r.x, .y = r.y, .w = r.w - 44, .h = r.h };
    const in = ui.interact(key, field);
    if (in.clicked) a.capture = if (capturing) .none else kind;
    const cap_t = ui.anim(ui.sub(key, 1), if (capturing) 1 else 0, 14);
    ui.rect(field, ui.radius_md, Rgba.lerp(ui.colors.bg, ui.colors.accent.alpha(0.12), cap_t));
    ui.border(field, ui.radius_md, 1, Rgba.lerp(ui.colors.border, ui.colors.accent, cap_t));
    if (capturing) {
        const dots = @as(usize, @intFromFloat(@mod(ui.time * 3, 4)));
        var buf: [64]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "{s}{s}", .{ a.t.hotkey_press, "...."[0..dots] }) catch a.t.hotkey_press;
        ui.label(s, field.insetXY(12, 0), 13, .semibold, ui.colors.accent, .left);
    } else if (value.len > 0) {
        _ = ui.keycap(field.x + 10, field.y + 8, value.*);
    } else {
        ui.label(a.t.hotkey_click, field.insetXY(12, 0), 13, .regular, ui.colors.text_faint, .left);
    }
    if (ui.iconButton(ui.sub(key, 2), .{ .x = r.right() - 36, .y = r.y, .w = 36, .h = r.h }, icons.x, .{ .tooltip = a.t.clear, .size = 15, .disabled = value.len == 0 })) {
        config.setString(value, "");
        a.bindings_dirty = true;
        a.markConfig();
    }
}

// ── Library ─────────────────────────────────────────────────────────────────

// ── Integrations (OBS, Stream Deck) ────────────────────────────────────────

fn integrationsSection(a: *App, l: *Layout) void {
    sectionHeader(l, icons.plug, a.t.sec_integrations);
    const rows: usize = if (a.cfg.http_enabled) 6 else 1;
    _ = card(l, rows, if (a.cfg.http_enabled) 40 else 0);

    const status_txt = switch (remote.status) {
        .off => a.t.http_off,
        .running => a.tf(a.t.http_running, .{a.cfg.http_port}),
        .failed => a.tf(a.t.http_failed, .{a.cfg.http_port}),
    };
    var ctrl = row(l, a.t.http_enable, status_txt, true);
    if (ui.toggle(ui.id("set-http", 0), ctrl, &a.cfg.http_enabled)) {
        remote.apply(&a.cfg);
        a.markConfig();
    }
    if (!a.cfg.http_enabled) {
        sectionEnd(l);
        return;
    }

    // Port: applied on Enter or when the field loses focus
    ctrl = row(l, a.t.http_port, a.t.http_port_desc, false);
    const port_key = ui.id("set-http-port", 0);
    if (ui.focus != port_key) {
        var pb: [8]u8 = undefined;
        a.port_field.set(std.fmt.bufPrint(&pb, "{d}", .{a.cfg.http_port}) catch "");
    }
    const res = ui.textInput(port_key, .{ .x = ctrl.right() - 120, .y = ctrl.y, .w = 120, .h = ctrl.h }, &a.port_field, .{ .clearable = false, .size = 13 });
    if (res.submitted) {
        if (std.fmt.parseInt(u16, std.mem.trim(u8, a.port_field.text(), " "), 10)) |p| {
            if (p >= 1024) {
                a.cfg.http_port = p;
                remote.apply(&a.cfg);
                a.markConfig();
            }
        } else |_| {}
        ui.focus = 0;
    }

    ctrl = row(l, a.t.http_lan, a.t.http_lan_desc, false);
    if (ui.toggle(ui.id("set-http-lan", 0), ctrl, &a.cfg.http_lan)) {
        remote.apply(&a.cfg);
        a.markConfig();
    }

    var ub: [3][160]u8 = undefined;
    const base = "http://127.0.0.1";
    const deck = std.fmt.bufPrint(&ub[0], "{s}:{d}/deck?key={s}", .{ base, a.cfg.http_port, a.cfg.http_token }) catch "";
    const overlay = std.fmt.bufPrint(&ub[1], "{s}:{d}/overlay?key={s}", .{ base, a.cfg.http_port, a.cfg.http_token }) catch "";
    const example = std.fmt.bufPrint(&ub[2], "{s}:{d}/api/play?key={s}&name=BRUH", .{ base, a.cfg.http_port, a.cfg.http_token }) catch "";
    urlRow(a, l, ui.id("url-deck", 0), a.t.http_deck, a.t.http_deck_desc, deck, true);
    urlRow(a, l, ui.id("url-overlay", 0), a.t.http_overlay, a.t.http_overlay_desc, overlay, false);
    urlRow(a, l, ui.id("url-cmd", 0), a.t.http_command, a.t.http_command_desc, example, false);

    // Commands list + new key
    const foot: Rect = .{ .x = l.x, .y = l.y, .w = l.w, .h = 40 };
    ui.rect(.{ .x = foot.x + 18, .y = foot.y, .w = foot.w - 36, .h = 1 }, 0, ui.colors.border.alpha(0.7));
    ui.label(a.t.http_verbs, .{ .x = foot.x + 20, .y = foot.y, .w = foot.w - 200, .h = foot.h }, 11, .mono, ui.colors.text_faint, .left);
    if (ui.button(ui.id("set-http-token", 0), .{ .x = foot.right() - 170, .y = foot.y + 5, .w = 150, .h = 30 }, a.t.http_new_key, .{ .icon = icons.refresh_cw, .style = .ghost, .size = 12, .tooltip = a.t.http_new_key_tip })) {
        var buf: [32]u8 = undefined;
        config.setString(&a.cfg.http_token, remote.newToken(&buf));
        remote.stop();
        remote.apply(&a.cfg);
        a.markConfig();
    }
    l.y += foot.h;
    sectionEnd(l);
}

/// A row with a URL in mono and buttons to copy / open it
fn urlRow(a: *App, l: *Layout, key: u64, title: []const u8, desc: []const u8, url: []const u8, can_open: bool) void {
    const ctrl = row(l, title, desc, false);
    // Same width on every row; copy always in the same column, open after it
    const url_r: Rect = .{ .x = ctrl.x - 60, .y = ctrl.y, .w = ctrl.w + 60 - 76, .h = ctrl.h };
    ui.rect(url_r, ui.radius_sm, ui.colors.bg);
    ui.label(url, url_r.insetXY(10, 0), 11, .mono, ui.colors.text_muted, .left);
    if (can_open) {
        if (ui.iconButton(ui.sub(key, 2), .{ .x = ctrl.right() - 34, .y = ctrl.y + 2, .w = 32, .h = 32 }, icons.external_link, .{ .size = 14, .tooltip = a.t.open_in_browser })) sys.openUrl(url);
    }
    if (ui.iconButton(ui.sub(key, 1), .{ .x = ctrl.right() - 70, .y = ctrl.y + 2, .w = 32, .h = 32 }, icons.copy, .{ .size = 14, .tooltip = a.t.copy })) {
        var z: [200]u8 = undefined;
        const n = @min(url.len, z.len - 1);
        @memcpy(z[0..n], url[0..n]);
        z[n] = 0;
        c.SetClipboardText(@ptrCast(&z));
        ui.toast(.success, a.t.copied);
    }
}

fn librarySection(a: *App, l: *Layout) void {
    sectionHeader(l, icons.library, a.t.sec_library);
    _ = card(l, 3, 0);

    var ctrl = row(l, a.t.library_folder, a.lib.root, true);
    const browse_r: Rect = .{ .x = ctrl.x, .y = ctrl.y, .w = 120, .h = ctrl.h };
    if (ui.button(ui.id("lib-browse", 0), browse_r, a.t.browse, .{ .icon = icons.folder })) {
        const title = a.tfz(a.t.choose_library, .{});
        const root_z = sys.gpa.dupeSentinel(u8, a.lib.root, 0) catch null;
        defer if (root_z) |z| sys.gpa.free(z);
        if (c.tinyfd_selectFolderDialog(title.ptr, if (root_z) |z| z.ptr else null)) |picked| {
            config.setString(&a.cfg.library_dir, std.mem.span(picked));
            a.openLibrary();
            a.markConfig();
        }
    }
    if (ui.button(ui.id("lib-open", 0), .{ .x = browse_r.right() + 8, .y = ctrl.y, .w = 90, .h = ctrl.h }, a.t.open_folder, .{ .style = .ghost, .size = 13 })) sys.openFolder(a.lib.root);
    if (a.cfg.library_dir.len > 0) {
        if (ui.button(ui.id("lib-reset", 0), .{ .x = ctrl.right() - 74, .y = ctrl.y, .w = 74, .h = ctrl.h }, a.t.reset, .{ .style = .ghost, .size = 13 })) {
            config.setString(&a.cfg.library_dir, "");
            a.openLibrary();
            a.markConfig();
        }
    }

    if (a.cache_size == null) a.cache_size = jobs.cacheSizeBytes();
    var size_buf: [32]u8 = undefined;
    ctrl = row(l, a.t.cache, a.tf(a.t.cache_desc, .{app_mod.formatBytes(&size_buf, a.cache_size.?)}), false);
    if (ui.button(ui.id("cache-clear", 0), .{ .x = ctrl.right() - 150, .y = ctrl.y, .w = 150, .h = ctrl.h }, a.t.clear_cache, .{ .icon = icons.trash_2, .style = .ghost })) {
        a.stopPreview();
        jobs.clearCache();
        a.cache_size = null;
        ui.toast(.success, a.t.cache_cleared);
    }

    ctrl = row(l, a.t.config_folder, config.path, false);
    if (ui.button(ui.id("cfg-open", 0), .{ .x = ctrl.right() - 150, .y = ctrl.y, .w = 150, .h = ctrl.h }, a.t.open_folder, .{ .icon = icons.folder_open, .style = .ghost })) {
        sys.openFolder(std.fs.path.dirname(config.path) orelse ".");
    }
    sectionEnd(l);
}

// ── Downloads & tools ───────────────────────────────────────────────────────

fn toolsSection(a: *App, l: *Layout) void {
    sectionHeader(l, icons.wrench, a.t.sec_tools);
    _ = card(l, 7, 0);
    toolRow(a, l, .ytdlp, "yt-dlp", a.t.ytdlp_desc, true);
    toolRow(a, l, .ffmpeg, "ffmpeg", a.t.ffmpeg_desc, false);
    toolRow(a, l, .deno, "Deno", a.t.deno_desc, false);

    var ctrl = row(l, a.t.download_format, "", false);
    const fmts = [_]ui.Segment{ .{ .label = "MP3" }, .{ .label = "OGG" }, .{ .label = "WAV" } };
    var fmt_idx: usize = @backingInt(a.cfg.download_format);
    if (ui.segmented(ui.id("set-fmt", 0), ctrl, &fmts, &fmt_idx)) {
        a.cfg.download_format = @fromBackingInt(@intCast(fmt_idx));
        a.markConfig();
    }

    ctrl = row(l, a.t.normalize, a.t.normalize_desc, false);
    if (ui.toggle(ui.id("set-norm", 0), ctrl, &a.cfg.normalize_audio)) a.markConfig();

    ctrl = row(l, a.t.max_clip, a.t.max_clip_desc, false);
    var clip: f32 = @floatFromInt(a.cfg.max_clip_seconds);
    var clip_buf: [16]u8 = undefined;
    const clip_txt = if (a.cfg.max_clip_seconds == 0) a.t.unlimited else std.fmt.bufPrint(&clip_buf, "{d} s", .{a.cfg.max_clip_seconds}) catch "";
    ui.label(clip_txt, .{ .x = ctrl.right() - 80, .y = ctrl.y, .w = 80, .h = ctrl.h }, 13, .semibold, ui.colors.text_muted, .right);
    if (ui.slider(ui.id("set-clip", 0), .{ .x = ctrl.x, .y = ctrl.y, .w = ctrl.w - 88, .h = ctrl.h }, &clip, 0, 60)) {
        a.cfg.max_clip_seconds = @intFromFloat(@round(clip));
        a.markConfig();
    }

    ctrl = row(l, a.t.results_per_search, "", false);
    var n: f32 = @floatFromInt(a.cfg.results_per_search);
    var n_buf: [8]u8 = undefined;
    ui.label(std.fmt.bufPrint(&n_buf, "{d}", .{a.cfg.results_per_search}) catch "", .{ .x = ctrl.right() - 40, .y = ctrl.y, .w = 40, .h = ctrl.h }, 13, .semibold, ui.colors.text_muted, .right);
    if (ui.slider(ui.id("set-results", 0), .{ .x = ctrl.x, .y = ctrl.y, .w = ctrl.w - 48, .h = ctrl.h }, &n, 5, 50)) {
        a.cfg.results_per_search = @intFromFloat(@round(n));
        a.markConfig();
    }
    sectionEnd(l);
}

fn toolRow(a: *App, l: *Layout, tool: tools.Tool, name: []const u8, desc: []const u8, first: bool) void {
    const st = tools.status(tool);
    var ver_buf: [64]u8 = undefined;
    const ver = tools.versionText(tool, &ver_buf);

    var title_buf: [96]u8 = undefined;
    const title = if (ver) |v| std.fmt.bufPrint(&title_buf, "{s}  ·  {s}", .{ name, v[0..@min(v.len, 40)] }) catch name else name;
    const ctrl = row(l, title, desc, first);

    // Status pill
    const outdated = tool == .ytdlp and (tools.ytdlpAgeDays() orelse 0) > tools.outdated_after_days;
    const status_txt = if (st.path == null) a.t.tool_missing else if (outdated) a.t.tool_outdated else if (st.bundled) a.t.tool_bundled else a.t.tool_system;
    const pill_col = if (st.path == null or outdated) ui.colors.warning else ui.colors.success;
    const pw = ui.measure(status_txt, 11, .semibold) + 18;

    if (a.jobs.isInstalling(tool)) |job| {
        const p = job.progress.get();
        ui.progressBar(.{ .x = ctrl.x + 60, .y = ctrl.y + 16, .w = ctrl.w - 60, .h = 5 }, p, ui.colors.accent);
        ui.spinner(.{ .x = ctrl.x + 40, .y = ctrl.y + 18 }, 8, ui.colors.accent);
        return;
    }
    var bx = ctrl.right();
    {
        // System copies can be shadowed by a fresh bundled one (yt-dlp from
        // distro repos is often too old for YouTube)
        const label = if (st.path == null) a.t.install else if (st.bundled) a.t.update else a.t.install_latest;
        const bw: f32 = if (st.path != null and !st.bundled) 150 else 110;
        bx -= bw;
        if (ui.button(ui.idStr("tool-install", name), .{ .x = bx, .y = ctrl.y, .w = bw, .h = ctrl.h }, label, .{ .icon = icons.download, .style = if (st.path == null or outdated) .primary else .secondary, .size = 13 })) {
            a.installTool(tool);
        }
    }
    if (st.bundled) {
        bx -= 44;
        if (ui.iconButton(ui.idStr("tool-remove", name), .{ .x = bx, .y = ctrl.y, .w = 38, .h = ctrl.h }, icons.trash_2, .{ .tooltip = a.t.uninstall, .size = 15 })) {
            tools.uninstall(tool);
            tools.detect(&a.cfg);
        }
    }
    const pill: Rect = .{ .x = bx - pw - 10, .y = ctrl.y + 8, .w = pw, .h = 20 };
    ui.badge(pill, status_txt, pill_col.alpha(0.15), pill_col);
}

// ── About ───────────────────────────────────────────────────────────────────

fn about(a: *App, l: *Layout) void {
    sectionHeader(l, icons.info, a.t.sec_about);
    const cr = card(l, 0, 150);
    const logo_r: Rect = .{ .x = cr.x + 24, .y = cr.y + 24, .w = 96, .h = 96 };
    const bob = @sin(ui.time * 1.6) * 3;
    ui.glow(logo_r.center(), 140, ui.colors.accent.alpha(0.18));
    ui.image(a.logo, logo_r.offset(0, bob), 0, .{ .r = 1, .g = 1, .b = 1 });
    const tx = logo_r.right() + 24;
    const w1 = ui.text("Woofer", tx, cr.y + 30, 26, .display, ui.colors.text);
    _ = ui.text("SoundPad", tx + w1, cr.y + 30, 26, .display, ui.colors.accent);
    _ = ui.text(a.tf(a.t.version_fmt, .{a.version}), tx, cr.y + 64, 13, .semibold, ui.colors.text_muted);
    _ = ui.text(a.t.about_desc, tx, cr.y + 84, 13, .regular, ui.colors.text_muted);
    _ = ui.text(a.t.made_with, tx, cr.y + 104, 12, .regular, ui.colors.text_faint);

    var bx = cr.right() - 20;
    bx -= 130;
    if (ui.button(ui.id("about-gh", 0), .{ .x = bx, .y = cr.y + 24, .w = 130, .h = 36 }, "GitHub", .{ .icon = icons.github })) sys.openUrl(build_options.repo_url);
    if (ui.button(ui.id("about-tour", 0), .{ .x = bx, .y = cr.y + 68, .w = 130, .h = 36 }, a.t.show_tutorial, .{ .icon = icons.graduation_cap, .style = .subtle })) {
        a.onboarding_open = true;
        a.onboarding_step = 0;
    }
    l.y += 150;
    sectionEnd(l);
}
