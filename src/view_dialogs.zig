//! Modal dialogs. A closing dialog keeps drawing until its fade-out ends.

const std = @import("std");
const c = @import("c");
const ui = @import("ui.zig");
const theme = @import("theme.zig");
const audio = @import("audio.zig");
const tools = @import("tools.zig");
const hotkeys = @import("hotkeys.zig");
const waves = @import("waves.zig");
const editor = @import("view_editor.zig");
const app_mod = @import("app.zig");
const App = app_mod.App;
const Dialog = app_mod.Dialog;
const icons = ui.icons;
const Rect = ui.Rect;
const Rgba = ui.Rgba;

pub fn close(a: *App) void {
    // Leaving the editor without saving undoes its live preview
    switch (a.dialog) {
        .edit_sound => |i| if (!a.editor.saved) a.cancelEditor(i),
        else => {},
    }
    a.dialog_closing = a.dialog;
    a.dialog = .none;
    a.capture = .none;
    ui.focus = 0;
}

pub fn draw(a: *App) void {
    const open = a.dialog != .none;
    const d: Dialog = if (open) a.dialog else a.dialog_closing;
    switch (d) {
        .none => {},
        .create_workspace => nameDialog(a, open, a.t.new_workspace, a.t.create, null),
        .rename_workspace => |i| nameDialog(a, open, a.t.rename_workspace, a.t.save, i),
        .delete_workspace => |i| deleteWorkspace(a, open, i),
        .delete_sound => |i| deleteSound(a, open, i),
        .edit_sound => |i| editor.draw(a, open, i),
        .download_media => downloadMedia(a, open),
        .record => recordDialog(a, open),
    }
}

pub fn finished(a: *App) void {
    a.dialog_closing = .none;
}

fn titleBar(a: *App, r: Rect, title: []const u8) void {
    _ = ui.text(title, r.x + 24, r.y + 22, 18, .display, ui.colors.text);
    if (ui.iconButton(ui.id("dlg-x", 0), .{ .x = r.right() - 48, .y = r.y + 16, .w = 32, .h = 32 }, icons.x, .{ .size = 17 })) close(a);
}

pub fn fieldLabel(x: f32, y: f32, s: []const u8) void {
    _ = ui.text(s, x, y, 12, .semibold, ui.colors.text_muted);
}

// ── Workspace name ──────────────────────────────────────────────────────────

fn nameDialog(a: *App, open: bool, title: []const u8, action: []const u8, index: ?usize) void {
    const m = ui.beginModal(ui.id("dlg-name", 0), 440, 222, open) orelse return finished(a);
    defer ui.endModal();
    if (m.close_requested) close(a);
    const r = m.rect;
    titleBar(a, r, title);
    fieldLabel(r.x + 24, r.y + 70, a.t.workspace_name);
    const res = ui.textInput(ui.id("dlg-name-field", 0), .{ .x = r.x + 24, .y = r.y + 92, .w = r.w - 48, .h = 42 }, &a.name_field, .{ .placeholder = a.t.default_workspace, .icon = icons.layers, .autofocus = open });
    const valid = std.mem.trim(u8, a.name_field.text(), " ").len > 0;
    if (ui.button(ui.id("dlg-name-cancel", 0), .{ .x = r.right() - 252, .y = r.bottom() - 62, .w = 110, .h = 40 }, a.t.cancel, .{ .style = .ghost })) close(a);
    const ok = ui.button(ui.id("dlg-name-ok", 0), .{ .x = r.right() - 134, .y = r.bottom() - 62, .w = 110, .h = 40 }, action, .{ .style = .primary, .disabled = !valid });
    if (open and valid and (ok or res.submitted)) {
        if (index) |i| a.renameWorkspace(i, a.name_field.text()) else a.createWorkspace(a.name_field.text());
        close(a);
    }
}

// ── Confirmations ───────────────────────────────────────────────────────────

fn confirm(a: *App, open: bool, key: u64, title: []const u8, body: []const u8) bool {
    const m = ui.beginModal(key, 460, 236, open) orelse {
        finished(a);
        return false;
    };
    defer ui.endModal();
    if (m.close_requested) close(a);
    const r = m.rect;
    ui.rect(.{ .x = r.x, .y = r.y + 30, .w = 4, .h = 40 }, 1, ui.colors.danger);
    ui.icon(icons.trash_2, .{ .x = r.x + 46, .y = r.y + 50 }, 20, ui.colors.danger);
    _ = ui.text(title, r.x + 84, r.y + 38, 18, .display, ui.colors.text);
    _ = ui.paragraph(body, .{ .x = r.x + 84, .y = r.y + 72, .w = r.w - 110, .h = 80 }, 13, .regular, ui.colors.text_muted, 1.5, true);
    if (ui.button(ui.sub(key, 1), .{ .x = r.right() - 252, .y = r.bottom() - 62, .w = 110, .h = 40 }, a.t.cancel, .{ .style = .ghost })) close(a);
    return open and ui.button(ui.sub(key, 2), .{ .x = r.right() - 134, .y = r.bottom() - 62, .w = 110, .h = 40 }, a.t.delete, .{ .style = .danger, .icon = icons.trash_2 });
}

fn deleteWorkspace(a: *App, open: bool, i: usize) void {
    if (i >= a.lib.workspaces.items.len) return close(a);
    const ws = &a.lib.workspaces.items[i];
    if (confirm(a, open, ui.id("dlg-del-ws", 0), a.t.delete_ws_title, a.tf(a.t.delete_ws_body, .{ ws.name, ws.sounds.items.len }))) {
        a.deleteWorkspace(i);
        close(a);
    }
}

fn deleteSound(a: *App, open: bool, i: usize) void {
    const ws = a.workspace();
    if (i >= ws.sounds.items.len) return close(a);
    if (confirm(a, open, ui.id("dlg-del-sound", 0), a.t.delete_sound_title, a.tf(a.t.delete_sound_body, .{ws.sounds.items[i].name}))) {
        a.deleteSound(i);
        close(a);
    }
}

// ── Hotkey capture (used by the editor) ─────────────────────────────────────

pub fn hotkeyCapture(a: *App, idx: usize, r: Rect) void {
    const e = &a.editor;
    const key = ui.id("ed-hotkey", 0);
    const capturing = a.capture == .pad;
    if (capturing) {
        ui.claimFocus(key);
        if (c.IsKeyPressed(c.KEY_ESCAPE)) {
            a.capture = .none;
            ui.focus = 0;
        } else if (hotkeys.capture()) |hk| {
            var buf: [48]u8 = undefined;
            e.setHotkey(hotkeys.format(hk, &buf));
            a.capture = .none;
            ui.focus = 0;
        }
    }
    _ = idx;
    const field: Rect = .{ .x = r.x, .y = r.y, .w = r.w - 46, .h = r.h };
    const in = ui.interact(key, field);
    if (in.clicked) a.capture = if (capturing) .none else .pad;
    const cap_t = ui.anim(ui.sub(key, 1), if (capturing) 1 else 0, 14);
    if (cap_t > 0.01) ui.rect(field.grow(3), ui.radius_lg, ui.colors.accent.alpha(0.16 * cap_t));
    ui.rect(field, ui.radius_lg, Rgba.lerp(ui.colors.surface, ui.colors.accent.alpha(0.1), cap_t));
    ui.border(field, ui.radius_lg, 1, Rgba.lerp(ui.colors.border, ui.colors.accent, cap_t));
    ui.icon(icons.keyboard, .{ .x = field.x + 20, .y = field.y + field.h / 2 }, 16, Rgba.lerp(ui.colors.text_faint, ui.colors.accent, cap_t));
    if (capturing) {
        const pulse = 0.6 + 0.4 * @sin(ui.time * 6);
        ui.label(a.t.hotkey_press, .{ .x = field.x + 38, .y = field.y, .w = field.w - 46, .h = field.h }, 13, .semibold, ui.colors.accent.alpha(pulse), .left);
    } else if (e.hotkey_len > 0) {
        _ = ui.keycap(field.x + 38, field.y + (field.h - 20) / 2, e.hotkeyText());
    } else {
        ui.label(a.t.hotkey_click, .{ .x = field.x + 38, .y = field.y, .w = field.w - 46, .h = field.h }, 13, .regular, ui.colors.text_faint, .left);
    }
    if (ui.iconButton(ui.id("ed-hotkey-clear", 0), .{ .x = r.right() - 40, .y = r.y + 2, .w = 38, .h = r.h - 4 }, icons.x, .{ .tooltip = a.t.clear, .size = 15, .disabled = e.hotkey_len == 0 })) {
        e.hotkey_len = 0;
    }
}

// ── Download options ────────────────────────────────────────────────────────

fn downloadMedia(a: *App, open: bool) void {
    const o = &a.online;
    const m = ui.beginModal(ui.id("dlg-dl", 0), 540, 486, open) orelse return finished(a);
    defer ui.endModal();
    if (m.close_requested) close(a);
    const r = m.rect;
    titleBar(a, r, a.t.download_title);
    const x = r.x + 24;
    const w = r.w - 48;
    var y = r.y + 58;
    const src = if (o.dlg_title.len > 0) o.dlg_title else o.dlg_url;
    ui.label(src, .{ .x = x, .y = y, .w = w, .h = 18 }, 12, .regular, ui.colors.text_faint, .left);
    y += 32;

    fieldLabel(x, y, a.t.name);
    y += 22;
    const res = ui.textInput(ui.id("dl-name", 0), .{ .x = x, .y = y, .w = w, .h = 42 }, &o.dlg_name, .{ .icon = icons.music_2, .placeholder = a.t.name, .autofocus = open });
    y += 58;

    fieldLabel(x, y, a.t.save_to);
    y += 22;
    var names: [64][]const u8 = undefined;
    const n_ws = @min(a.lib.workspaces.items.len, names.len);
    for (a.lib.workspaces.items[0..n_ws], 0..) |ws, i| names[i] = ws.name;
    _ = ui.dropdown(ui.id("dl-target", 0), .{ .x = x, .y = y, .w = w, .h = 40 }, names[0..n_ws], &o.dlg_target);
    y += 58;

    const has_ffmpeg = tools.available(.ffmpeg);
    fieldLabel(x, y, a.t.trim_optional);
    if (o.dlg_duration > 0) {
        var buf: [16]u8 = undefined;
        ui.label(a.tf(a.t.length_label, .{app_mod.formatDuration(&buf, o.dlg_duration)}), .{ .x = x + w - 160, .y = y - 2, .w = 160, .h = 16 }, 12, .regular, ui.colors.text_faint, .right);
    }
    y += 22;
    ui.pushAlpha(if (has_ffmpeg) 1 else 0.45);
    _ = ui.textInput(ui.id("dl-start", 0), .{ .x = x, .y = y, .w = (w - 10) / 2, .h = 40 }, &o.dlg_start, .{ .placeholder = a.t.start_sec, .icon = icons.timer, .clearable = false, .size = 13 });
    _ = ui.textInput(ui.id("dl-end", 0), .{ .x = x + (w + 10) / 2, .y = y, .w = (w - 10) / 2, .h = 40 }, &o.dlg_end, .{ .placeholder = a.t.end_sec, .icon = icons.timer, .clearable = false, .size = 13 });
    y += 54;
    _ = ui.toggle(ui.id("dl-norm", 0), .{ .x = x, .y = y, .w = 44, .h = 36 }, &o.dlg_normalize);
    ui.label(a.t.normalize, .{ .x = x + 54, .y = y, .w = w - 54, .h = 36 }, 13, .regular, ui.colors.text_muted, .left);
    ui.popAlpha();
    if (!has_ffmpeg) {
        o.dlg_start.clear();
        o.dlg_end.clear();
        o.dlg_normalize = false;
        ui.label(a.t.needs_ffmpeg, .{ .x = x, .y = y + 36, .w = w, .h = 18 }, 12, .regular, ui.colors.warning, .left);
    }

    const fy = r.bottom() - 64;
    if (ui.button(ui.id("dl-cancel", 0), .{ .x = r.right() - 272, .y = fy, .w = 110, .h = 40 }, a.t.cancel, .{ .style = .ghost })) close(a);
    const go = ui.button(ui.id("dl-go", 0), .{ .x = r.right() - 154, .y = fy, .w = 130, .h = 40 }, a.t.download, .{ .style = .primary, .icon = icons.download });
    if (open and (go or res.submitted)) {
        a.confirmDownload();
        close(a);
    }
}

// ── Recorder ────────────────────────────────────────────────────────────────

fn recordDialog(a: *App, open: bool) void {
    const rec = &a.rec;
    const m = ui.beginModal(ui.id("dlg-rec", 0), 680, 560, open) orelse return finished(a);
    defer ui.endModal();
    // Closing never loses a recording: it stays until saved or discarded
    if (m.close_requested and rec.drag == .none) close(a);
    const r = m.rect;
    titleBar(a, r, a.t.record_title);
    const x = r.x + 24;
    const w = r.w - 48;
    var y = r.y + 62;
    ui.label(a.t.record_subtitle, .{ .x = x, .y = y, .w = w, .h = 18 }, 13, .regular, ui.colors.text_muted, .left);
    y += 34;

    // Source
    fieldLabel(x, y, a.t.rec_source);
    y += 22;
    var names_buf: [66][]const u8 = undefined;
    names_buf[0] = if (audio.recSystemSupported()) a.t.rec_src_system else a.t.rec_src_system_na;
    names_buf[1] = a.t.rec_src_mic;
    const caps = audio.captureNames(names_buf[2..]);
    const n_src = 2 + caps.len;
    if (rec.source_idx >= n_src) rec.source_idx = 0;
    ui.pushAlpha(if (rec.state == .idle) 1 else 0.5);
    var src_idx = rec.source_idx;
    if (ui.dropdown(ui.id("rec-src", 0), .{ .x = x, .y = y, .w = w, .h = 40 }, names_buf[0..n_src], &src_idx) and rec.state == .idle) rec.source_idx = src_idx;
    ui.popAlpha();
    y += 56;

    // Big record button, timer and level
    const stage: Rect = .{ .x = x, .y = y, .w = w, .h = 190 };
    ui.rect(stage, ui.radius_lg, ui.colors.bg.alpha(0.6));
    ui.border(stage, ui.radius_lg, 1, if (rec.state == .recording) ui.colors.danger.alpha(0.6) else ui.colors.border);
    const btn_c: ui.Vec2 = .{ .x = stage.x + 70, .y = stage.y + 64 };
    const btn_key = ui.id("rec-btn", 0);
    const bin = ui.interactOpts(btn_key, .{ .x = btn_c.x - 36, .y = btn_c.y - 36, .w = 72, .h = 72 }, rec.state != .recorded);
    const recording = rec.state == .recording;
    const pulse: f32 = if (recording) 0.5 + 0.5 * @sin(ui.time * 5) else 0;
    if (recording) ui.border(.{ .x = btn_c.x - 36, .y = btn_c.y - 36, .w = 72, .h = 72 }, 36, 2, ui.colors.danger.alpha(0.3 + 0.5 * pulse));
    ui.circle(btn_c, 30 * (1 - bin.press_t * 0.06), ui.colors.danger.shade(bin.hover_t * 0.1 - (if (rec.state == .recorded) @as(f32, 0.4) else 0)));
    if (recording) {
        ui.rect(.{ .x = btn_c.x - 10, .y = btn_c.y - 10, .w = 20, .h = 20 }, 4, Rgba{ .r = 1, .g = 1, .b = 1 });
    } else {
        ui.circle(btn_c, 11, Rgba{ .r = 1, .g = 1, .b = 1 });
    }
    if (bin.hovered) ui.tooltip(btn_key, if (recording) a.t.rec_stop else a.t.rec_start);
    if (bin.clicked) {
        if (recording) a.stopRecording() else a.startRecording();
    }
    // Timer
    var tb: [24]u8 = undefined;
    const secs = audio.recSeconds();
    const tenths: u32 = @intFromFloat(@mod(secs * 10, 10));
    var db: [16]u8 = undefined;
    const time_txt = std.fmt.bufPrint(&tb, "{s}.{d}", .{ app_mod.formatDuration(&db, @floor(secs)), tenths }) catch "";
    _ = ui.text(time_txt, stage.x + 128, stage.y + 36, 30, .display, if (recording) ui.colors.text else ui.colors.text_muted);
    const state_txt = switch (rec.state) {
        .idle => a.t.rec_ready,
        .recording => a.t.rec_recording,
        .recorded => a.t.rec_done,
    };
    _ = ui.text(state_txt, stage.x + 130, stage.y + 78, 11, .mono, if (recording) ui.colors.danger else ui.colors.text_faint);
    // Level meter
    const lvl = audio.recLevel();
    rec.level = if (lvl > rec.level) lvl else rec.level * @exp(-5 * ui.dt);
    ui.meter(.{ .x = stage.x + 300, .y = stage.y + 52, .w = stage.right() - stage.x - 324, .h = 8 }, if (recording) rec.level else 0, !recording);
    var lim: [32]u8 = undefined;
    ui.label(a.tf(a.t.rec_limit, .{std.fmt.bufPrint(&lim, "{d:.0}", .{audio.rec_max_seconds / 60}) catch ""}), .{ .x = stage.x + 300, .y = stage.y + 68, .w = stage.right() - stage.x - 324, .h = 16 }, 11, .regular, ui.colors.text_faint, .right);

    // Live waveform; after stopping, handles pick what to keep
    const wr: Rect = .{ .x = stage.x + 16, .y = stage.y + 112, .w = stage.w - 32, .h = 62 };
    drawRecWave(a, wr);

    y = stage.bottom() + 18;
    if (rec.state == .recorded) {
        fieldLabel(x, y, a.t.name);
        fieldLabel(x + w * 0.55 + 10, y, a.t.save_to);
        y += 22;
        const res = ui.textInput(ui.id("rec-name", 0), .{ .x = x, .y = y, .w = w * 0.55, .h = 40 }, &rec.name, .{ .icon = icons.music_2, .placeholder = a.t.rec_default_name });
        var names: [64][]const u8 = undefined;
        const n_ws = @min(a.lib.workspaces.items.len, names.len);
        for (a.lib.workspaces.items[0..n_ws], 0..) |ws, i| names[i] = ws.name;
        _ = ui.dropdown(ui.id("rec-target", 0), .{ .x = x + w * 0.55 + 10, .y = y, .w = w * 0.45 - 10, .h = 40 }, names[0..n_ws], &rec.target);
        if (res.submitted) {
            a.saveRecording();
            if (a.dialog == .record) close(a);
            return;
        }
    } else {
        _ = ui.toggle(ui.id("rec-autotrim", 0), .{ .x = x, .y = y + 6, .w = 44, .h = 36 }, &a.cfg.rec_auto_trim);
        ui.label(a.t.rec_auto_trim, .{ .x = x + 54, .y = y + 6, .w = w - 54, .h = 36 }, 13, .regular, ui.colors.text_muted, .left);
        if (rec.source_idx == 0) ui.label(a.t.rec_system_hint, .{ .x = x, .y = y + 44, .w = w, .h = 18 }, 11, .regular, ui.colors.text_faint, .left);
    }

    const fy = r.bottom() - 64;
    if (rec.state == .recorded) {
        if (ui.button(ui.id("rec-discard", 0), .{ .x = x, .y = fy, .w = 130, .h = 40 }, a.t.rec_discard, .{ .style = .danger, .icon = icons.trash_2 })) a.discardRecording();
        if (ui.button(ui.id("rec-again", 0), .{ .x = x + 140, .y = fy, .w = 150, .h = 40 }, a.t.rec_again, .{ .style = .ghost, .icon = icons.rotate_ccw })) {
            a.discardRecording();
            a.startRecording();
        }
        const keep = rec.keep_end - rec.keep_start;
        if (ui.button(ui.id("rec-save", 0), .{ .x = r.right() - 214, .y = fy, .w = 190, .h = 40 }, a.t.rec_save, .{ .style = .primary, .icon = icons.check, .disabled = keep < 0.05 }) and open) {
            a.saveRecording();
            if (a.dialog == .record) close(a);
        }
    } else {
        if (ui.button(ui.id("rec-close", 0), .{ .x = r.right() - 134, .y = fy, .w = 110, .h = 40 }, a.t.close, .{ .style = .ghost })) close(a);
    }
}

fn drawRecWave(a: *App, wr: Rect) void {
    const rec = &a.rec;
    ui.rect(wr, ui.radius_lg, ui.colors.surface);
    const peaks = audio.recPeaks();
    if (peaks.len == 0) {
        ui.label(a.t.rec_wave_hint, wr, 12, .regular, ui.colors.text_faint, .center);
        return;
    }
    const inner = wr.insetXY(8, 6);
    const pps = audio.rec_peaks_per_second;
    const total = audio.recSeconds();
    // While recording the view scrolls, showing the last 10 seconds at least
    const span = if (rec.state == .recording) @max(10, total) else total;
    const bars: usize = @intFromFloat(@max(10, inner.w / 3));
    const step = inner.w / @as(f32, @floatFromInt(bars));
    const mid = inner.y + inner.h / 2;
    const done = rec.state == .recorded;
    const xOf = struct {
        fn f(in: Rect, t: f32, sp: f32) f32 {
            return in.x + std.math.clamp(t / sp, 0, 1) * in.w;
        }
    }.f;
    const ks = xOf(inner, rec.keep_start, span);
    const ke = xOf(inner, rec.keep_end, span);
    for (0..bars) |b| {
        const t0 = span * @as(f32, @floatFromInt(b)) / @as(f32, @floatFromInt(bars));
        const t1 = span * @as(f32, @floatFromInt(b + 1)) / @as(f32, @floatFromInt(bars));
        const p0: usize = @intFromFloat(t0 * pps);
        const p1: usize = @max(p0 + 1, @as(usize, @intFromFloat(t1 * pps)));
        if (p0 >= peaks.len) break;
        var v: f32 = 0;
        for (peaks[p0..@min(p1, peaks.len)]) |p| v = @max(v, p);
        const h = @max(2, @sqrt(v) * inner.h);
        const bx = inner.x + @as(f32, @floatFromInt(b)) * step;
        const inside = !done or (bx >= ks and bx <= ke);
        ui.rect(.{ .x = bx, .y = mid - h / 2, .w = @max(1.5, step * 0.6), .h = h }, 1, if (inside) ui.colors.danger.alpha(0.85) else ui.colors.text_faint.alpha(0.3));
    }
    if (!done) return;
    ui.rect(.{ .x = wr.x, .y = wr.y, .w = @max(0, ks - wr.x), .h = wr.h }, 0, ui.colors.bg.alpha(0.45));
    ui.rect(.{ .x = ke, .y = wr.y, .w = @max(0, wr.right() - ke), .h = wr.h }, 0, ui.colors.bg.alpha(0.45));
    const hs = recHandle(ui.id("rec-h", 0), ks, wr);
    const he = recHandle(ui.id("rec-h", 1), ke, wr);
    if (hs.pressed) rec.drag = .start;
    if (he.pressed) rec.drag = .end;
    if (rec.drag != .none) {
        if (!ui.mouseDown()) rec.drag = .none else {
            const t = std.math.clamp((ui.mouse.x - inner.x) / inner.w, 0, 1) * span;
            switch (rec.drag) {
                .start => rec.keep_start = std.math.clamp(t, 0, rec.keep_end - 0.05),
                .end => rec.keep_end = std.math.clamp(t, rec.keep_start + 0.05, total),
                .none => {},
            }
            ui.setCursor(c.MOUSE_CURSOR_RESIZE_EW);
        }
    }
    var b1: [24]u8 = undefined;
    var b2: [24]u8 = undefined;
    ui.label(a.tf(a.t.rec_keep, .{ editor.fmtTime(&b1, rec.keep_end - rec.keep_start), editor.fmtTime(&b2, total) }), .{ .x = wr.x, .y = wr.bottom() + 2, .w = wr.w, .h = 16 }, 11, .regular, ui.colors.text_faint, .right);
}

fn recHandle(key: u64, hx: f32, wr: Rect) ui.Interaction {
    const in = ui.interact(key, .{ .x = hx - 9, .y = wr.y - 2, .w = 18, .h = wr.h + 4 });
    const grow = @max(in.hover_t, in.press_t);
    ui.rect(.{ .x = hx - 1.5, .y = wr.y, .w = 3, .h = wr.h }, 1.5, ui.colors.danger);
    const knob: Rect = .{ .x = hx - 6 - grow, .y = wr.y + wr.h / 2 - 12, .w = 12 + grow * 2, .h = 24 };
    ui.rect(knob, 6, Rgba{ .r = 1, .g = 1, .b = 1 });
    ui.border(knob, 6, 1.5, ui.colors.danger);
    if (in.hovered) ui.setCursor(c.MOUSE_CURSOR_RESIZE_EW);
    return in;
}
