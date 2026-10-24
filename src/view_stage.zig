//! Stage mode: a full-screen soundboard for games, calls and streams. Huge
//! pads with their hotkeys, what is playing, and a panic button. No sidebar,
//! no toolbar, nothing to misclick.

const std = @import("std");
const ui = @import("ui.zig");
const theme = @import("theme.zig");
const audio = @import("audio.zig");
const soundboard = @import("view_soundboard.zig");
const mixer = @import("view_mixer.zig");
const view = @import("view.zig");
const app_mod = @import("app.zig");
const App = app_mod.App;
const icons = ui.icons;
const Rect = ui.Rect;
const Rgba = ui.Rgba;

pub fn draw(a: *App) void {
    soundboard.rebuildView(a);
    const screen = ui.screen;
    const t = if (ui.animations) ui.easeOutCubic((ui.time - a.page_changed_at) / 0.2) else 1;
    ui.rect(screen, 0, ui.colors.bg);
    ui.pushAlpha(t);
    defer ui.popAlpha();

    var r = screen.insetXY(18, 0);
    topBar(a, r.cutTop(68));
    nowPlaying(a, r.cutTop(44));
    _ = r.cutTop(14);
    _ = r.cutBottom(16);
    if (a.cfg.stage_mixer) {
        const dock = r.cutBottom(soundboard.dock_h);
        _ = r.cutBottom(12);
        mixer.drawDock(a, dock, false);
    }
    grid(a, r);
}

fn topBar(a: *App, r: Rect) void {
    const ws = a.workspace();
    ui.rect(.{ .x = 0, .y = r.bottom() - 1, .w = ui.screen.w, .h = 1 }, 0, ui.colors.border);
    ui.image(a.logo, .{ .x = r.x, .y = r.y + 20, .w = 28, .h = 28 }, 0, .{ .r = 1, .g = 1, .b = 1 });
    const live_x = r.x + 40;
    // "LIVE" lamp, the way stage gear says it
    const lamp: Rect = .{ .x = live_x, .y = r.y + 25, .w = 44, .h = 18 };
    ui.rect(lamp, 2, ui.colors.danger);
    ui.label("LIVE", lamp, 10, .mono_bold, Rgba{ .r = 1, .g = 1, .b = 1 }, .center);
    const name_w = ui.text(ws.name, lamp.right() + 12, r.y + 23, 20, .display, ui.colors.text);

    // Workspace switcher
    var x = lamp.right() + 12 + name_w + 24;
    const right_reserved: f32 = 400;
    for (a.lib.workspaces.items, 0..) |w, i| {
        if (a.lib.workspaces.items.len < 2) break;
        const cw = ui.chipWidth(null, w.name);
        if (x + cw > r.right() - right_reserved) break;
        const cr: Rect = .{ .x = x, .y = r.y + 20, .w = cw, .h = 28 };
        if (ui.chip(ui.idStr("stage-ws", w.name), cr, null, w.name, i == a.ws, theme.padColor(w.color, ui.colors.accent))) a.switchWorkspace(i);
        x += cw + 6;
    }

    // Right: pause, mixer, exit, then the panic button
    var rr = r;
    const stop_r = rr.cutRight(210);
    const big: Rect = .{ .x = stop_r.x, .y = r.y + 12, .w = stop_r.w, .h = 44 };
    const any = audio.playingCount() > 0 or audio.pausedCount() > 0 or a.queue.current != null;
    const in = ui.interact(ui.id("stage-stop", 0), big);
    const br = big.offset(0, in.press_t * 2);
    ui.rect(br, ui.radius_md, ui.colors.danger.shade(in.hover_t * 0.1 - in.press_t * 0.15));
    const white: Rgba = .{ .r = 1, .g = 1, .b = 1 };
    ui.icon(icons.octagon_x, .{ .x = br.x + 24, .y = br.y + br.h / 2 }, 18, white);
    _ = ui.text(a.t.panic_button, br.x + 44, br.y + 8, 14, .mono_bold, white);
    const hk = if (a.cfg.stop_hotkey.len > 0) a.tf("ESC / {}", .{a.cfg.stop_hotkey}) else "ESC";
    _ = ui.text(hk, br.x + 44, br.y + 26, 10, .mono, white.alpha(if (any) 0.85 else 0.6));
    if (in.clicked) a.stopAll();

    _ = rr.cutRight(12);
    const bs: f32 = 38;
    const by = r.y + 15;
    const exit_r = rr.cutRight(bs);
    if (ui.iconButton(ui.id("stage-exit", 0), .{ .x = exit_r.x, .y = by, .w = bs, .h = bs }, icons.minimize, .{ .tooltip = a.t.stage_exit_tip, .background = true })) a.setStage(false);
    _ = rr.cutRight(6);
    const mx_r = rr.cutRight(bs);
    if (ui.iconButton(ui.id("stage-mixer", 0), .{ .x = mx_r.x, .y = by, .w = bs, .h = bs }, icons.sliders_vertical, .{ .tooltip = a.t.mixer, .active = a.cfg.stage_mixer, .background = true })) {
        a.cfg.stage_mixer = !a.cfg.stage_mixer;
        a.markConfig();
    }
    _ = rr.cutRight(6);
    const pause_r = rr.cutRight(bs);
    const paused_all = a.anythingPaused();
    if (ui.iconButton(ui.id("stage-pause", 0), .{ .x = pause_r.x, .y = by, .w = bs, .h = bs }, if (paused_all) icons.play else icons.pause, .{ .tooltip = if (paused_all) a.t.resume_play else a.t.pause_all, .background = true, .disabled = !any })) a.togglePause();
}

fn nowPlaying(a: *App, r: Rect) void {
    const ws = a.workspace();
    var buf: [256]usize = undefined;
    const active = a.activeSounds(&buf);
    const inner: Rect = .{ .x = r.x, .y = r.y + 8, .w = r.w, .h = r.h - 8 };
    _ = ui.text("ON AIR", inner.x, inner.y + 9, 10, .mono, ui.colors.text_faint);
    const list: Rect = .{ .x = inner.x + 56, .y = inner.y, .w = inner.w - 56, .h = inner.h };
    if (active.len == 0) {
        ui.label(a.t.stage_idle, list, 12, .regular, ui.colors.text_faint, .left);
        return;
    }
    var x = list.x;
    ui.pushClip(list);
    defer ui.popClip();
    for (active) |si| {
        const s = &ws.sounds.items[si];
        const col = theme.padColor(s.color, ui.colors.accent);
        const w = @min(240, ui.measure(s.name, 12, .semibold) + 56);
        const cr: Rect = .{ .x = x, .y = list.y + 2, .w = w, .h = list.h - 4 };
        if (cr.x > list.right()) break;
        const key = ui.id("stage-np", s.uid);
        const in = ui.interact(key, cr);
        const paused = audio.isPaused(s.audio_id) and !audio.isPlaying(s.audio_id);
        ui.rect(cr, ui.radius_sm, Rgba.lerp(ui.colors.surface, col, 0.12 + in.hover_t * 0.08));
        ui.border(cr, ui.radius_sm, 1, col.alpha(0.5));
        // Progress along the bottom
        ui.rect(.{ .x = cr.x, .y = cr.bottom() - 2, .w = cr.w * audio.progress(s.audio_id), .h = 2 }, 0, col);
        const led_on = !paused or @mod(ui.time, 1.0) < 0.5;
        if (in.hover_t > 0.5) {
            ui.icon(icons.square, .{ .x = cr.x + 14, .y = cr.y + cr.h / 2 }, 11, ui.colors.danger);
        } else {
            ui.rect(.{ .x = cr.x + 10, .y = cr.y + cr.h / 2 - 3.5, .w = 7, .h = 7 }, 1, if (led_on) col else col.alpha(0.25));
        }
        ui.label(s.name, .{ .x = cr.x + 26, .y = cr.y, .w = cr.w - 34, .h = cr.h }, 12, .semibold, ui.colors.text, .left);
        if (in.hovered) ui.tooltip(key, a.t.click_to_stop);
        if (in.clicked) {
            audio.fadeStop(s.audio_id, 0.15);
            a.queueForget(s.uid);
        }
        x += w + 6;
    }
}

fn grid(a: *App, area: Rect) void {
    const ws = a.workspace();
    if (ws.sounds.items.len == 0) {
        _ = view.emptyState(area, icons.paw_print, a.t.empty_title, a.t.empty_body);
        return;
    }
    const n = a.view.items.len;
    if (n == 0) return;
    const gap: f32 = 10;
    const inner_w = area.w - 10;
    // As big as possible while every pad still fits, down to a readable minimum
    var cols: usize = @max(2, @as(usize, @intFromFloat((inner_w + gap) / (260 + gap))));
    var pad_w: f32 = 0;
    var pad_h: f32 = 0;
    while (true) {
        const cf: f32 = @floatFromInt(cols);
        pad_w = (inner_w - gap * (cf - 1)) / cf;
        pad_h = std.math.clamp(pad_w * 0.6, 100, 220);
        const rows: f32 = @floatFromInt((n + cols - 1) / cols);
        if (rows * (pad_h + gap) <= area.h + gap or pad_w < 190) break;
        cols += 1;
    }

    const top = ui.beginScroll(ui.id("stage-scroll", a.ws), area);
    var max_y = top;
    for (a.view.items, 0..) |si, order| {
        const col_i = order % cols;
        const row_i = order / cols;
        const pr: Rect = .{
            .x = area.x + @as(f32, @floatFromInt(col_i)) * (pad_w + gap),
            .y = top + @as(f32, @floatFromInt(row_i)) * (pad_h + gap),
            .w = pad_w,
            .h = pad_h,
        };
        max_y = pr.bottom();
        if (pr.bottom() < area.y - 40 or pr.y > area.bottom() + 40) continue;
        bigPad(a, si, order, pr);
    }
    ui.endScroll(max_y - top + 12);
}

fn bigPad(a: *App, si: usize, order: usize, r: Rect) void {
    const s = &a.workspace().sounds.items[si];
    const key = ui.id("stage-pad", s.uid);
    const in = ui.interact(key, r);
    const playing = audio.isPlaying(s.audio_id);
    const paused = !playing and audio.isPaused(s.audio_id);
    const play_t = ui.anim(ui.sub(key, 1), if (playing) 1 else if (paused) 0.5 else 0, 14);
    const col = theme.padColor(s.color, ui.colors.accent);
    const pr = r.offset(0, in.press_t * 2);

    const lvl = std.math.clamp(s.level * 1.4, 0, 1);
    ui.rect(pr, ui.radius_lg, Rgba.lerp(ui.colors.surface, col, 0.1 + in.hover_t * 0.05 + play_t * (0.2 + 0.1 * lvl)));
    if (play_t > 0.01) {
        const p = audio.progress(s.audio_id);
        ui.pushClip(.{ .x = pr.x, .y = pr.y, .w = pr.w * p, .h = pr.h });
        ui.rect(pr, ui.radius_lg, col.alpha(0.12 * play_t));
        ui.popClip();
        ui.rect(.{ .x = pr.x + 1, .y = pr.bottom() - 4, .w = (pr.w - 2) * p, .h = 3 }, 0, col);
    }
    ui.border(pr, ui.radius_lg, if (play_t > 0.5) 2 else 1, Rgba.lerp(Rgba.lerp(ui.colors.border, col.alpha(0.6), in.hover_t), col, play_t));

    // Hotkey, big enough to read from across the room
    var hint_buf: [16]u8 = undefined;
    const hint: []const u8 = if (s.hotkey.len > 0)
        s.hotkey
    else if (a.cfg.number_keys_play and order < 10)
        std.fmt.bufPrint(&hint_buf, "{d}", .{(order + 1) % 10}) catch ""
    else
        "";
    if (hint.len > 0) {
        const kw = @max(34, ui.measure(hint, 18, .mono_bold) + 18);
        const kr: Rect = .{ .x = pr.x + 12, .y = pr.y + 12, .w = kw, .h = 32 };
        ui.border(kr, ui.radius_sm, 1, col.alpha(0.7));
        ui.label(hint, kr, 18, .mono_bold, col, .center);
    }
    // LED
    const led_on = playing or (paused and @mod(ui.time, 1.0) < 0.5);
    ui.rect(.{ .x = pr.right() - 24, .y = pr.y + 18, .w = 10, .h = 10 }, 1, if (led_on) col else ui.colors.text.alpha(0.12));

    // Name and time
    const name_size: f32 = if (pr.h > 170) 24 else if (pr.h > 130) 20 else 16;
    ui.label(s.name, .{ .x = pr.x + 14, .y = pr.bottom() - name_size - 36, .w = pr.w - 28, .h = name_size + 6 }, name_size, .bold, ui.colors.text, .left);
    const speed = if (s.speed > 0.01) s.speed else 1;
    const len = audio.length(s.audio_id) / speed;
    var db: [24]u8 = undefined;
    var x = pr.x + 14;
    if (len > 0) x += ui.text(app_mod.formatDuration(&db, if (playing or paused) len * (1 - audio.progress(s.audio_id)) else len), x, pr.bottom() - 28, 12, .mono, if (playing) col else ui.colors.text_muted) + 10;
    if (s.fx.active() > 0) x += ui.text("FX", x, pr.bottom() - 28, 11, .mono_bold, col) + 8;
    if (s.loop) _ = ui.text("LOOP", x, pr.bottom() - 28, 11, .mono_bold, col);

    if (in.clicked) {
        a.playSound(si);
        a.addRipple(si, ui.mouse.x, ui.mouse.y);
    }
    // Right click stops just this one
    if (in.right_clicked and (playing or paused)) {
        audio.fadeStop(s.audio_id, 0.12);
        a.queueForget(s.uid);
    }
}
