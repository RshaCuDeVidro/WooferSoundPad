//! Live mixer, laid out like a small desk: a master strip, then one channel
//! strip per sound playing right now (meter, fader, mute, fade-out, stop).
//! Docked under the soundboard and in stage mode.

const std = @import("std");
const ui = @import("ui.zig");
const theme = @import("theme.zig");
const audio = @import("audio.zig");
const library = @import("library.zig");
const app_mod = @import("app.zig");
const App = app_mod.App;
const icons = ui.icons;
const Rect = ui.Rect;
const Rgba = ui.Rgba;

pub fn activeCount(a: *App) usize {
    var buf: [256]usize = undefined;
    return a.activeSounds(&buf).len;
}

const strip_w: f32 = 84;
const master_w: f32 = 150;
const fade_steps = [_]f32{ 0.5, 1, 1.5, 3, 5 };

pub fn drawDock(a: *App, r: Rect, closable: bool) void {
    const ws = a.workspace();
    ui.rect(r, ui.radius_lg, ui.colors.sidebar);
    ui.border(r, ui.radius_lg, 1, ui.colors.border);

    var buf: [256]usize = undefined;
    const active = a.activeSounds(&buf);

    // Title strip along the top
    const head: Rect = .{ .x = r.x, .y = r.y, .w = r.w, .h = 30 };
    _ = ui.text("MIXER", head.x + 14, head.y + 9, 11, .mono_bold, ui.colors.text);
    var cb: [32]u8 = undefined;
    _ = ui.text(std.fmt.bufPrint(&cb, "{d} CH", .{active.len}) catch "", head.x + 66, head.y + 9, 11, .mono, if (active.len > 0) ui.colors.success else ui.colors.text_faint);
    if (closable) {
        if (ui.iconButton(ui.id("mx-close", 0), .{ .x = head.right() - 30, .y = head.y + 3, .w = 26, .h = 24 }, icons.x, .{ .size = 13, .tooltip = a.t.close })) {
            a.cfg.mixer_open = false;
            a.markConfig();
        }
    }
    ui.rect(.{ .x = r.x, .y = head.bottom(), .w = r.w, .h = 1 }, 0, ui.colors.border);

    const body: Rect = .{ .x = r.x, .y = head.bottom() + 1, .w = r.w, .h = r.h - head.h - 1 };
    masterStrip(a, .{ .x = body.x, .y = body.y, .w = master_w, .h = body.h }, active.len);
    ui.rect(.{ .x = body.x + master_w, .y = body.y, .w = 1, .h = body.h }, 0, ui.colors.border);

    const ch_area: Rect = .{ .x = body.x + master_w + 1, .y = body.y, .w = body.w - master_w - 1, .h = body.h };
    if (active.len == 0) {
        ui.label(a.t.mixer_empty_hint, ch_area.insetXY(24, 0), 12, .regular, ui.colors.text_faint, .left);
        return;
    }
    ui.pushClip(ch_area);
    defer ui.popClip();
    // More channels than fit: they get narrower, down to a minimum
    const fit_w = @max(56, @min(strip_w, ch_area.w / @as(f32, @floatFromInt(active.len))));
    for (active, 0..) |si, i| {
        const sr: Rect = .{ .x = ch_area.x + @as(f32, @floatFromInt(i)) * fit_w, .y = ch_area.y, .w = fit_w, .h = ch_area.h };
        if (sr.x > ch_area.right()) break;
        channel(a, &ws.sounds.items[si], sr);
        ui.rect(.{ .x = sr.right() - 1, .y = sr.y + 8, .w = 1, .h = sr.h - 16 }, 0, ui.colors.border.alpha(0.7));
    }
}

fn masterStrip(a: *App, r: Rect, n_active: usize) void {
    const in_r = r.insetXY(12, 10);
    _ = ui.text("MASTER", in_r.x, in_r.y, 10, .mono, ui.colors.text_faint);

    // Meter + fader
    var peak: f32 = 0;
    for (a.workspace().sounds.items) |s| peak = @max(peak, s.level);
    const fr: Rect = .{ .x = in_r.x, .y = in_r.y + 18, .w = 36, .h = in_r.h - 40 };
    ui.meterV(.{ .x = fr.right() + 2, .y = fr.y + 8, .w = 5, .h = fr.h - 16 }, peak * a.cfg.master_volume, false);
    if (ui.faderV(ui.id("mx-master", 0), fr, &a.cfg.master_volume, 0, 1, null, ui.colors.accent)) {
        audio.applyVolumes(&a.cfg);
        a.markConfig();
    }
    var vb: [8]u8 = undefined;
    ui.label(std.fmt.bufPrint(&vb, "{d:.0}", .{a.cfg.master_volume * 100}) catch "", .{ .x = in_r.x, .y = in_r.bottom() - 16, .w = 44, .h = 16 }, 10, .mono, ui.colors.text_muted, .center);

    // Actions on the right of the master fader
    const bx = in_r.x + 56;
    const bw = in_r.right() - bx;
    if (ui.button(ui.id("mx-fade-all", 0), .{ .x = bx, .y = in_r.y + 18, .w = bw, .h = 28 }, "FADE", .{ .icon = icons.trending_down, .size = 11, .disabled = n_active == 0, .tooltip = a.t.fade_all_tip })) a.fadeOutAll();
    if (ui.button(ui.id("mx-stop-all", 0), .{ .x = bx, .y = in_r.y + 52, .w = bw, .h = 28 }, "STOP", .{ .icon = icons.square, .style = .danger, .size = 11, .disabled = n_active == 0, .tooltip = a.t.stop_all })) a.stopAll();
    _ = ui.text("FADE T", bx, in_r.y + 96, 10, .mono, ui.colors.text_faint);
    var fb: [16]u8 = undefined;
    const fade_txt = std.fmt.bufPrint(&fb, "{d:.1}s", .{a.cfg.mixer_fade_seconds}) catch "";
    if (ui.chip(ui.id("mx-fade-len", 0), .{ .x = bx, .y = in_r.y + 110, .w = bw, .h = 26 }, null, fade_txt, false, null)) {
        var next: f32 = fade_steps[0];
        for (fade_steps) |st| {
            if (st > a.cfg.mixer_fade_seconds + 0.01) {
                next = st;
                break;
            }
        }
        a.cfg.mixer_fade_seconds = next;
        a.markConfig();
    }
    if (ui.mouseIn(.{ .x = bx, .y = in_r.y + 110, .w = bw, .h = 26 })) ui.tooltip(ui.id("mx-fade-len", 1), a.t.fade_length_tip);
}

fn channel(a: *App, s: *library.Sound, r: Rect) void {
    const key = ui.id("mx-ch", s.uid);
    const col = theme.padColor(s.color, ui.colors.accent);
    const id = s.audio_id;
    const paused = audio.isPaused(id) and !audio.isPlaying(id);
    const muted = audio.isMuted(id);
    const fading = audio.isFading(id);
    const appear = ui.animFrom(ui.sub(key, 1), 0, 1, 18);
    ui.pushAlpha(appear);
    defer ui.popAlpha();
    const in_r = r.insetXY(7, 8);

    // Color cap and name
    ui.rect(.{ .x = in_r.x, .y = in_r.y, .w = in_r.w, .h = 2 }, 0, col);
    ui.label(s.name, .{ .x = in_r.x, .y = in_r.y + 5, .w = in_r.w, .h = 16 }, 11, .semibold, if (muted) ui.colors.text_faint else ui.colors.text, .left);

    // M / F / stop
    const bw = (in_r.w - 4) / 3;
    const by = in_r.y + 24;
    if (ui.textToggle(ui.sub(key, 2), .{ .x = in_r.x, .y = by, .w = bw, .h = 20 }, "M", muted, ui.colors.warning, if (muted) a.t.unmute else a.t.mute)) audio.setMuted(id, !muted);
    if (ui.textToggle(ui.sub(key, 3), .{ .x = in_r.x + bw + 2, .y = by, .w = bw, .h = 20 }, "F", fading, ui.colors.accent, a.t.fade_out_now) and !paused) audio.fadeStop(id, a.cfg.mixer_fade_seconds);
    if (ui.textToggle(ui.sub(key, 4), .{ .x = in_r.x + 2 * (bw + 2), .y = by, .w = bw, .h = 20 }, "■", false, ui.colors.danger, a.t.stop)) {
        audio.stop(id);
        a.queueForget(s.uid);
    }

    // Meter + live volume fader
    const fr: Rect = .{ .x = in_r.x + in_r.w / 2 - 22, .y = by + 26, .w = 36, .h = in_r.bottom() - by - 26 - 32 };
    ui.meterV(.{ .x = fr.right() + 2, .y = fr.y + 8, .w = 5, .h = fr.h - 16 }, if (muted) 0 else s.level, paused);
    var vol = audio.liveVolume(id);
    if (ui.faderV(ui.sub(key, 5), fr, &vol, 0, 2, 1, col)) {
        // Snap to unity so "unchanged" is easy to hit
        if (@abs(vol - 1) < 0.05) vol = 1;
        audio.setLiveVolume(id, vol);
    }
    var vb: [16]u8 = undefined;
    ui.label(std.fmt.bufPrint(&vb, "{d:.0}%", .{vol * 100}) catch "", .{ .x = in_r.x, .y = in_r.bottom() - 30, .w = in_r.w, .h = 14 }, 10, .mono, if (vol != 1) col else ui.colors.text_faint, .center);

    // Time left (or loop / paused)
    const speed = if (s.speed > 0.01) s.speed else 1;
    const left = audio.length(id) / speed * (1 - audio.progress(id));
    var tb: [16]u8 = undefined;
    const time_txt = if (paused) "PAUSE" else if (s.loop) "LOOP" else app_mod.formatDuration(&tb, left);
    ui.label(time_txt, .{ .x = in_r.x, .y = in_r.bottom() - 14, .w = in_r.w, .h = 14 }, 10, .mono_bold, if (paused) ui.colors.warning else ui.colors.text_muted, .center);
}
