//! The sound editor: a zoomable waveform for the cut and fades, playback
//! settings, the live effect chain with presets, and the pad's look and hotkey.
//! Everything previews live; nothing touches the file unless asked to.

const std = @import("std");
const c = @import("c");
const ui = @import("ui.zig");
const theme = @import("theme.zig");
const audio = @import("audio.zig");
const tools = @import("tools.zig");
const waves = @import("waves.zig");
const config = @import("config.zig");
const fx = @import("fx.zig");
const library = @import("library.zig");
const dialogs = @import("view_dialogs.zig");
const app_mod = @import("app.zig");
const App = app_mod.App;
const Editor = app_mod.Editor;
const icons = ui.icons;
const Rect = ui.Rect;
const Rgba = ui.Rgba;

const wave_bins = 4096;

// ── Undo history ────────────────────────────────────────────────────────────
// Every finished gesture (a slider released, a preset clicked, a handle
// dropped) becomes one step. The name field has its own text editing.

const Snapshot = struct {
    params: audio.Params,
    fx: fx.Chain,
    volume: f32,
    color: u8,
    favorite: bool,

    fn of(e: *const Editor) Snapshot {
        return .{ .params = e.params, .fx = e.fx, .volume = e.volume, .color = e.color, .favorite = e.favorite };
    }

    fn eql(x: *const Snapshot, y: *const Snapshot) bool {
        return std.meta.eql(x.params, y.params) and x.fx.eql(&y.fx) and x.volume == y.volume and x.color == y.color and x.favorite == y.favorite;
    }

    fn apply(snap: *const Snapshot, e: *Editor) void {
        e.params = snap.params;
        e.fx = snap.fx;
        e.volume = snap.volume;
        e.color = snap.color;
        e.favorite = snap.favorite;
    }
};

const max_undo = 100;
var undo_stack: [max_undo]Snapshot = undefined;
var undo_len: usize = 0;
var redo_stack: [max_undo]Snapshot = undefined;
var redo_len: usize = 0;
/// State after the last finished gesture
var committed: Snapshot = undefined;

fn pushBounded(stack: *[max_undo]Snapshot, len: *usize, snap: Snapshot) void {
    if (len.* == max_undo) {
        std.mem.copyForwards(Snapshot, stack[0 .. max_undo - 1], stack[1..max_undo]);
        len.* -= 1;
    }
    stack[len.*] = snap;
    len.* += 1;
}

/// Records a step once the mouse is released and something changed
fn trackUndo(e: *Editor) void {
    if (e.undo_reset) {
        e.undo_reset = false;
        undo_len = 0;
        redo_len = 0;
        committed = Snapshot.of(e);
        return;
    }
    if (ui.mouseDown() or e.drag != .none) return;
    const now = Snapshot.of(e);
    if (now.eql(&committed)) return;
    pushBounded(&undo_stack, &undo_len, committed);
    redo_len = 0;
    committed = now;
}

fn undo(a: *App, e: *Editor, idx: usize) void {
    if (undo_len == 0) return;
    pushBounded(&redo_stack, &redo_len, Snapshot.of(e));
    undo_len -= 1;
    undo_stack[undo_len].apply(e);
    committed = undo_stack[undo_len];
    a.previewEditorParams(idx);
    applyFx(a, e, idx);
}

fn redo(a: *App, e: *Editor, idx: usize) void {
    if (redo_len == 0) return;
    pushBounded(&undo_stack, &undo_len, Snapshot.of(e));
    redo_len -= 1;
    redo_stack[redo_len].apply(e);
    committed = redo_stack[redo_len];
    a.previewEditorParams(idx);
    applyFx(a, e, idx);
}

/// True while the editor started the preview (for loop preview)
var previewing = false;
/// Effects are bypassed while comparing with the dry sound
var bypass = false;

pub fn draw(a: *App, open: bool, idx: usize) void {
    const ws = a.workspace();
    if (idx >= ws.sounds.items.len) return dialogs.close(a);
    const s = &ws.sounds.items[idx];
    const m = ui.beginModal(ui.id("dlg-edit", 0), 1120, 780, open) orelse {
        previewing = false;
        bypass = false;
        return dialogs.finished(a);
    };
    defer ui.endModal();
    const e = &a.editor;
    if (m.close_requested and a.capture == .none and e.drag == .none) dialogs.close(a);
    const r = m.rect;
    const col = theme.padColor(e.color, ui.colors.accent);

    // Space plays / stops the preview; Ctrl+Z / Ctrl+Shift+Z (or Ctrl+Y) undo and redo
    trackUndo(e);
    if (open and !ui.keyboardCaptured() and a.capture == .none) {
        if (c.IsKeyPressed(c.KEY_SPACE)) togglePreview(a, s, e);
        const ctrl = c.IsKeyDown(c.KEY_LEFT_CONTROL) or c.IsKeyDown(c.KEY_RIGHT_CONTROL);
        const shift = c.IsKeyDown(c.KEY_LEFT_SHIFT) or c.IsKeyDown(c.KEY_RIGHT_SHIFT);
        if (ctrl and c.IsKeyPressed(c.KEY_Z)) {
            if (shift) redo(a, e, idx) else undo(a, e, idx);
        }
        if (ctrl and c.IsKeyPressed(c.KEY_Y)) redo(a, e, idx);
    }
    // Loop preview: start again when it ends
    if (previewing and !audio.isPlaying(s.audio_id) and !audio.isPaused(s.audio_id)) {
        if (e.loop_preview) playSelection(a, s, e) else previewing = false;
    }

    var body = r.insetXY(24, 0);
    header(a, s, e, body.cutTop(70), col, idx);
    // The waveform gives up height first on short windows
    const wave_h = std.math.clamp(r.h - 560, 170, 232);
    var changed = waveformPanel(a, s, e, body.cutTop(wave_h), col);
    changed = transport(a, s, e, body.cutTop(52), col) or changed;
    _ = body.cutTop(6);

    // Tabs
    var tab_idx: usize = @backingInt(e.tab);
    const tab_items = [_]ui.Tab{
        .{ .label = a.t.tab_sound, .icon = icons.sliders_horizontal },
        .{ .label = a.t.tab_effects, .icon = icons.wand_sparkles, .badge = e.fx.active() },
        .{ .label = a.t.tab_pad, .icon = icons.palette },
    };
    if (ui.tabs(ui.id("ed-tabs", 0), body.cutTop(44), &tab_items, &tab_idx)) {
        e.tab = @fromBackingInt(@intCast(tab_idx));
        e.add_menu = false;
    }
    const foot = body.cutBottom(72);
    _ = body.cutTop(14);
    var fx_changed = false;
    switch (e.tab) {
        .sound => changed = soundTab(a, e, body) or changed,
        .effects => fx_changed = effectsTab(a, s, e, body, col),
        .pad => padTab(a, s, e, body, idx),
    }
    if (changed) a.previewEditorParams(idx);
    if (fx_changed) applyFx(a, e, idx);

    footer(a, s, e, foot, idx, open);
}

fn applyFx(a: *App, e: *Editor, idx: usize) void {
    if (bypass) {
        const none: fx.Chain = .{};
        audio.setFx(a.workspace().sounds.items[idx].audio_id, &none);
    } else {
        a.previewEditorFx(idx);
    }
    _ = e;
}

fn fullLength(a: *App, s: *const library.Sound) f32 {
    var path_buf: [1024]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "{s}{c}{s}", .{ a.workspace().dir, std.fs.path.sep, s.file }) catch "";
    if (waves.get(path, wave_bins)) |wv| return wv.duration;
    return audio.fullLength(s.audio_id);
}

fn selection(e: *const Editor, full: f32) struct { start: f32, end: f32 } {
    const start = @min(e.params.trim_start, full);
    const end = if (e.params.trim_end > 0) @min(e.params.trim_end, full) else full;
    return .{ .start = start, .end = @max(end, start) };
}

fn playSelection(a: *App, s: *const library.Sound, e: *Editor) void {
    audio.play(s.audio_id, a.padVolume(s, e.volume), .restart);
    previewing = true;
}

fn togglePreview(a: *App, s: *const library.Sound, e: *Editor) void {
    if (audio.isPlaying(s.audio_id)) {
        audio.stop(s.audio_id);
        previewing = false;
    } else playSelection(a, s, e);
}

// ── Header ──────────────────────────────────────────────────────────────────

fn header(a: *App, s: *const library.Sound, e: *Editor, r: Rect, col: Rgba, idx: usize) void {
    ui.rect(.{ .x = r.x, .y = r.y + 22, .w = 4, .h = 44 }, 1, col);
    _ = ui.text(a.t.edit_sound, r.x + 16, r.y + 18, 10, .mono, ui.colors.text_faint);
    const name_r: Rect = .{ .x = r.x + 12, .y = r.y + 32, .w = @min(440, r.w - 260), .h = 36 };
    const res = ui.textInput(ui.id("ed-name", 0), name_r, &e.name, .{ .size = 15 });
    if (res.submitted) {
        a.saveEditor(idx);
        dialogs.close(a);
        return;
    }
    // Variant / shared-file note
    const ws = a.workspace();
    if (ws.fileUsers(s.file) > 1) {
        const nx = name_r.right() + 12;
        ui.icon(icons.git_fork, .{ .x = nx + 8, .y = name_r.y + name_r.h / 2 }, 13, ui.colors.text_faint);
        ui.label(a.t.shared_file, .{ .x = nx + 20, .y = name_r.y, .w = 200, .h = name_r.h }, 12, .regular, ui.colors.text_faint, .left);
    }
    if (ui.iconButton(ui.id("ed-undo", 0), .{ .x = r.right() - 184, .y = r.y + 22, .w = 40, .h = 40 }, icons.undo_2, .{ .size = 16, .tooltip = a.tf("{} (Ctrl+Z)", .{a.t.undo}), .disabled = undo_len == 0 })) undo(a, &a.editor, idx);
    if (ui.iconButton(ui.id("ed-redo", 0), .{ .x = r.right() - 140, .y = r.y + 22, .w = 40, .h = 40 }, icons.redo_2, .{ .size = 16, .tooltip = a.tf("{} (Ctrl+Shift+Z)", .{a.t.redo}), .disabled = redo_len == 0 })) redo(a, &a.editor, idx);
    if (ui.iconButton(ui.id("ed-fav", 0), .{ .x = r.right() - 88, .y = r.y + 22, .w = 40, .h = 40 }, icons.star, .{
        .tooltip = if (e.favorite) a.t.unfavorite else a.t.favorite,
        .color = if (e.favorite) ui.colors.warning else null,
        .radius = 10,
    })) e.favorite = !e.favorite;
    if (ui.iconButton(ui.id("dlg-x", 0), .{ .x = r.right() - 40, .y = r.y + 22, .w = 40, .h = 40 }, icons.x, .{ .size = 17, .radius = 10 })) dialogs.close(a);
}

// ── Waveform ────────────────────────────────────────────────────────────────

fn waveformPanel(a: *App, s: *const library.Sound, e: *Editor, r_in: Rect, col: Rgba) bool {
    var r = r_in;
    var changed = false;
    var path_buf: [1024]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "{s}{c}{s}", .{ a.workspace().dir, std.fs.path.sep, s.file }) catch "";
    const wave = waves.get(path, wave_bins);
    const full = if (wave) |wv| wv.duration else audio.fullLength(s.audio_id);
    const sel = selection(e, full);
    const trimmed = e.params.trim_start > 0 or e.params.trim_end > 0;

    // Tool row: title + info, zoom and cut tools
    const bar = r.cutTop(38);
    ui.icon(icons.scissors, .{ .x = bar.x + 8, .y = bar.y + 18 }, 14, ui.colors.accent);
    const tw = ui.text(a.t.trim, bar.x + 22, bar.y + 10, 14, .semibold, ui.colors.text);
    if (full > 0) {
        var b1: [24]u8 = undefined;
        var b2: [24]u8 = undefined;
        var b3: [24]u8 = undefined;
        const info = a.tf(a.t.trim_info, .{ fmtTime(&b1, sel.start), fmtTime(&b2, sel.end), fmtTime(&b3, (sel.end - sel.start) / e.params.speed) });
        ui.label(info, .{ .x = bar.x + 34 + tw, .y = bar.y, .w = 360, .h = bar.h }, 12, .regular, ui.colors.text_muted, .left);
    }
    var bx = bar.right();
    const tool = struct {
        fn f(key: u64, x: *f32, y: f32, ic: u21, tip: []const u8, disabled: bool) bool {
            x.* -= 34;
            return ui.iconButton(key, .{ .x = x.*, .y = y, .w = 32, .h = 30 }, ic, .{ .size = 15, .tooltip = tip, .disabled = disabled });
        }
    }.f;
    if (tool(ui.id("trim-reset", 0), &bx, bar.y + 4, icons.undo_2, a.t.reset_cut, !trimmed)) {
        e.params.trim_start = 0;
        e.params.trim_end = 0;
        changed = true;
    }
    if (tool(ui.id("trim-auto", 0), &bx, bar.y + 4, icons.wand_sparkles, a.t.auto_trim_tip, wave == null)) {
        if (wave) |wv| changed = autoTrim(e, wv) or changed;
    }
    bx -= 10;
    const zoomed = e.view_len > 0 and e.view_len < full * 0.98;
    if (tool(ui.id("zoom-sel", 0), &bx, bar.y + 4, icons.crop, a.t.zoom_selection, !trimmed)) zoomTo(e, sel.start - (sel.end - sel.start) * 0.08, (sel.end - sel.start) * 1.16, full);
    if (tool(ui.id("zoom-fit", 0), &bx, bar.y + 4, icons.maximize, a.t.zoom_fit, !zoomed)) zoomTo(e, 0, full, full);
    if (tool(ui.id("zoom-out", 0), &bx, bar.y + 4, icons.zoom_out, a.t.zoom_out, !zoomed)) zoomAround(e, e.view_start + e.view_len / 2, 1.6, full);
    if (tool(ui.id("zoom-in", 0), &bx, bar.y + 4, icons.zoom_in, a.t.zoom_in, full <= 0)) zoomAround(e, e.view_start + e.view_len / 2, 0.625, full);

    // Waveform box
    const overview_h: f32 = 16;
    const ruler_h: f32 = 20;
    const wr: Rect = .{ .x = r.x, .y = r.y + 4, .w = r.w, .h = r.h - ruler_h - overview_h - 14 };
    ui.rect(wr, ui.radius_lg, ui.colors.bg.alpha(0.75));
    ui.border(wr, ui.radius_lg, 1, ui.colors.border);
    const inner = wr.insetXY(10, 8);
    if (wave == null or full <= 0) {
        ui.skeleton(inner, ui.radius_md);
        ui.label(a.t.loading_wave, inner, 12, .regular, ui.colors.text_faint, .center);
        return changed;
    }
    const peaks = wave.?.peaks;
    if (e.view_len <= 0 or e.view_len > full) zoomTo(e, 0, full, full);
    const vs = e.view_start;
    const vl = e.view_len;
    const View = struct {
        inner: Rect,
        vs: f32,
        vl: f32,
        full: f32,
        fn x(v: @This(), secs: f32) f32 {
            return v.inner.x + (secs - v.vs) / v.vl * v.inner.w;
        }
        fn t(v: @This(), px: f32) f32 {
            return std.math.clamp(v.vs + (px - v.inner.x) / v.inner.w * v.vl, 0, v.full);
        }
    };
    const vw: View = .{ .inner = inner, .vs = vs, .vl = vl, .full = full };
    const sx = vw.x(sel.start);
    const ex = vw.x(sel.end);

    // Wheel: zoom around the mouse, Shift+wheel pans
    if (ui.mouseIn(wr)) {
        const wd = ui.consumeWheel();
        if (wd != 0) {
            const shift = c.IsKeyDown(c.KEY_LEFT_SHIFT) or c.IsKeyDown(c.KEY_RIGHT_SHIFT);
            if (shift) {
                e.view_start = std.math.clamp(e.view_start - wd * vl * 0.15, 0, full - vl);
            } else {
                zoomAround(e, vw.t(ui.mouse.x), if (wd > 0) 0.8 else 1.25, full);
            }
        }
    }

    ui.pushClip(wr);
    // Bars, mirrored around the middle
    const bars: usize = @intFromFloat(@max(20, inner.w / 3));
    const step = inner.w / @as(f32, @floatFromInt(bars));
    const mid = inner.y + inner.h / 2;
    const n_f: f32 = @floatFromInt(peaks.len);
    for (0..bars) |b| {
        const t0 = vs + vl * @as(f32, @floatFromInt(b)) / @as(f32, @floatFromInt(bars));
        const t1 = vs + vl * @as(f32, @floatFromInt(b + 1)) / @as(f32, @floatFromInt(bars));
        const p0: usize = @intFromFloat(std.math.clamp(t0 / full * n_f, 0, n_f - 1));
        const p1: usize = @max(p0 + 1, @as(usize, @intFromFloat(std.math.clamp(t1 / full * n_f, 0, n_f))));
        var v: f32 = 0;
        for (peaks[p0..@min(p1, peaks.len)]) |p| v = @max(v, p);
        const h = @max(2, v * inner.h);
        const bxp = inner.x + @as(f32, @floatFromInt(b)) * step;
        const tc = (t0 + t1) / 2;
        const inside = tc >= sel.start and tc <= sel.end;
        ui.rect(.{ .x = bxp, .y = mid - h / 2, .w = @max(1.5, step * 0.62), .h = h }, 1, if (inside) col.alpha(0.92) else ui.colors.text_faint.alpha(0.3));
    }
    // Dim what gets cut, outline what stays
    ui.rect(.{ .x = wr.x, .y = wr.y, .w = @max(0, sx - wr.x), .h = wr.h }, 0, ui.colors.bg.alpha(0.5));
    ui.rect(.{ .x = ex, .y = wr.y, .w = @max(0, wr.right() - ex), .h = wr.h }, 0, ui.colors.bg.alpha(0.5));
    ui.rect(.{ .x = sx, .y = wr.y, .w = @max(0, ex - sx), .h = wr.h }, 0, col.alpha(0.05));

    // Fades as ramps over the selection (in file seconds: playback time × speed)
    const fin_x = vw.x(@min(sel.start + e.params.fade_in * e.params.speed, sel.end));
    const fout_x = vw.x(@max(sel.end - e.params.fade_out * e.params.speed, sel.start));
    if (e.params.fade_in > 0) ui.rectGradientH(.{ .x = sx, .y = wr.y, .w = fin_x - sx, .h = wr.h }, 0, ui.colors.bg.alpha(0.55), ui.colors.bg.alpha(0));
    if (e.params.fade_out > 0) ui.rectGradientH(.{ .x = fout_x, .y = wr.y, .w = ex - fout_x, .h = wr.h }, 0, ui.colors.bg.alpha(0), ui.colors.bg.alpha(0.55));
    if (e.params.fade_in > 0) ui.line(.{ .x = sx, .y = wr.bottom() - 4 }, .{ .x = fin_x, .y = wr.y + 4 }, 1.5, col.alpha(0.7));
    if (e.params.fade_out > 0) ui.line(.{ .x = fout_x, .y = wr.y + 4 }, .{ .x = ex, .y = wr.bottom() - 4 }, 1.5, col.alpha(0.7));

    // Playhead (cursor is relative to the trim start, in file seconds)
    const playing = audio.isPlaying(s.audio_id) or audio.isPaused(s.audio_id);
    if (playing) {
        const px = vw.x(sel.start + audio.cursor(s.audio_id));
        ui.rect(.{ .x = px - 1, .y = wr.y + 2, .w = 2, .h = wr.h - 4 }, 1, ui.colors.text);
        ui.circle(.{ .x = px, .y = wr.y + 6 }, 4, ui.colors.text);
    }
    // Hover line with its time
    if (ui.mouseIn(wr) and e.drag == .none) {
        ui.rect(.{ .x = ui.mouse.x, .y = wr.y, .w = 1, .h = wr.h }, 0, ui.colors.text.alpha(0.25));
    }
    ui.popClip();

    // Interactions: area first, then the handles (drawn on top, they win)
    const area_in = ui.interact(ui.id("trim-area", 0), wr);
    const fin_in = fadeHandle(ui.id("fade-h", 0), fin_x, wr, col, e.params.fade_in > 0, a.t.fade_in);
    const fout_in = fadeHandle(ui.id("fade-h", 1), fout_x, wr, col, e.params.fade_out > 0, a.t.fade_out);
    const h_start = trimHandle(ui.id("trim-h", 0), sx, wr, col);
    const h_end = trimHandle(ui.id("trim-h", 1), ex, wr, col);
    if (area_in.pressed) {
        e.drag = .select;
        e.drag_from = vw.t(ui.mouse.x);
        e.drag_moved = false;
    }
    if (fin_in.pressed) e.drag = .fade_in;
    if (fout_in.pressed) e.drag = .fade_out;
    if (h_start.pressed) e.drag = .start;
    if (h_end.pressed) e.drag = .end;

    if (e.drag != .none and e.drag != .pan) {
        const t = vw.t(ui.mouse.x);
        const min_len: f32 = 0.05;
        if (!ui.mouseDown()) {
            // A click without dragging plays from there
            if (e.drag == .select and !e.drag_moved) {
                const rel = if (t >= sel.start and t < sel.end) t - sel.start else 0;
                audio.playFrom(s.audio_id, a.padVolume(s, e.volume), rel);
                previewing = true;
            }
            e.drag = .none;
        } else switch (e.drag) {
            .start => {
                const v = std.math.clamp(t, 0, sel.end - min_len);
                const stored: f32 = if (v < 0.005) 0 else v;
                if (stored != e.params.trim_start) {
                    e.params.trim_start = stored;
                    changed = true;
                }
                ui.setCursor(c.MOUSE_CURSOR_RESIZE_EW);
            },
            .end => {
                const v = std.math.clamp(t, sel.start + min_len, full);
                const stored: f32 = if (v >= full - 0.005) 0 else v;
                if (stored != e.params.trim_end) {
                    e.params.trim_end = stored;
                    changed = true;
                }
                ui.setCursor(c.MOUSE_CURSOR_RESIZE_EW);
            },
            .fade_in => {
                const v = std.math.clamp((t - sel.start) / e.params.speed, 0, 10);
                e.params.fade_in = if (v < 0.02) 0 else @round(v * 100) / 100;
                changed = true;
                ui.setCursor(c.MOUSE_CURSOR_RESIZE_EW);
            },
            .fade_out => {
                const v = std.math.clamp((sel.end - t) / e.params.speed, 0, 10);
                e.params.fade_out = if (v < 0.02) 0 else @round(v * 100) / 100;
                changed = true;
                ui.setCursor(c.MOUSE_CURSOR_RESIZE_EW);
            },
            .select => {
                if (@abs(ui.mouse.x - vw.x(e.drag_from)) > 4) e.drag_moved = true;
                if (e.drag_moved) {
                    const lo = @min(e.drag_from, t);
                    const hi = @max(e.drag_from, t);
                    if (hi - lo >= min_len) {
                        e.params.trim_start = if (lo < 0.005) 0 else lo;
                        e.params.trim_end = if (hi >= full - 0.005) 0 else hi;
                        changed = true;
                    }
                    ui.setCursor(c.MOUSE_CURSOR_RESIZE_EW);
                }
            },
            else => {},
        }
    }

    // Ruler
    const ruler: Rect = .{ .x = inner.x, .y = wr.bottom() + 3, .w = inner.w, .h = ruler_h };
    drawRuler(vw.inner, vs, vl, ruler);

    // Overview strip with the visible window (drag to pan)
    const ov: Rect = .{ .x = wr.x, .y = ruler.bottom() + 2, .w = wr.w, .h = overview_h - 4 };
    ui.rect(ov, 4, ui.colors.text.alpha(0.05));
    const ovb: usize = @intFromFloat(@max(10, ov.w / 3));
    for (0..ovb) |b| {
        const p0 = b * peaks.len / ovb;
        const p1 = @max(p0 + 1, (b + 1) * peaks.len / ovb);
        var v: f32 = 0;
        for (peaks[p0..@min(p1, peaks.len)]) |p| v = @max(v, p);
        const h = @max(1, v * ov.h);
        ui.rect(.{ .x = ov.x + @as(f32, @floatFromInt(b)) * ov.w / @as(f32, @floatFromInt(ovb)), .y = ov.y + (ov.h - h) / 2, .w = 1.5, .h = h }, 0, ui.colors.text_faint.alpha(0.5));
    }
    const win: Rect = .{ .x = ov.x + vs / full * ov.w, .y = ov.y - 1, .w = @max(6, vl / full * ov.w), .h = ov.h + 2 };
    const ov_in = ui.interact(ui.id("ed-overview", 0), ov.grow(3));
    ui.rect(win, 3, ui.colors.accent.alpha(if (zoomed) 0.25 + ov_in.hover_t * 0.1 else 0.1));
    ui.border(win, 3, 1, ui.colors.accent.alpha(if (zoomed) 0.7 else 0.25));
    if (ov_in.pressed and zoomed) {
        e.drag = .pan;
        e.drag_from = ui.mouse.x - win.x;
    }
    if (e.drag == .pan) {
        if (!ui.mouseDown()) e.drag = .none else {
            e.view_start = std.math.clamp((ui.mouse.x - e.drag_from - ov.x) / ov.w * full, 0, full - vl);
            ui.setCursor(c.MOUSE_CURSOR_RESIZE_EW);
        }
    }
    if (area_in.hovered and e.drag == .none) {
        var hb: [24]u8 = undefined;
        ui.tooltip(ui.id("trim-area-tip", 0), a.tf("{} · {}", .{ fmtTime(&hb, vw.t(ui.mouse.x)), a.t.trim_hint }));
    }
    return changed;
}

fn zoomTo(e: *Editor, start: f32, len: f32, full: f32) void {
    if (full <= 0) return;
    const l = std.math.clamp(len, @min(0.05, full), full);
    e.view_len = l;
    e.view_start = std.math.clamp(start, 0, full - l);
}

fn zoomAround(e: *Editor, center: f32, factor: f32, full: f32) void {
    if (full <= 0 or e.view_len <= 0) return;
    const new_len = std.math.clamp(e.view_len * factor, @min(0.05, full), full);
    // Keep the point under the mouse where it is
    const rel = (center - e.view_start) / e.view_len;
    zoomTo(e, center - rel * new_len, new_len, full);
}

fn autoTrim(e: *Editor, wv: *const waves.Wave) bool {
    const peaks = wv.peaks;
    const thr: f32 = 0.04;
    var first: usize = 0;
    while (first < peaks.len and peaks[first] < thr) first += 1;
    var last: usize = peaks.len;
    while (last > first and peaks[last - 1] < thr) last -= 1;
    if (last <= first) return false;
    const n: f32 = @floatFromInt(peaks.len);
    const start = @max(0, @as(f32, @floatFromInt(first)) / n * wv.duration - 0.03);
    const end = @min(wv.duration, @as(f32, @floatFromInt(last)) / n * wv.duration + 0.06);
    e.params.trim_start = if (start < 0.01) 0 else start;
    e.params.trim_end = if (end >= wv.duration - 0.01) 0 else end;
    return true;
}

fn drawRuler(inner: Rect, vs: f32, vl: f32, r: Rect) void {
    const steps = [_]f32{ 0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600 };
    const px_per_s = inner.w / vl;
    var stp: f32 = steps[steps.len - 1];
    for (steps) |st| {
        if (st * px_per_s >= 80) {
            stp = st;
            break;
        }
    }
    var t = @ceil(vs / stp) * stp;
    var guard: usize = 0;
    while (t <= vs + vl and guard < 200) : (guard += 1) {
        const x = inner.x + (t - vs) / vl * inner.w;
        ui.rect(.{ .x = x, .y = r.y, .w = 1, .h = 5 }, 0, ui.colors.text_faint.alpha(0.6));
        var b: [24]u8 = undefined;
        const txt = fmtTime(&b, t);
        const tw = ui.measure(txt, 10, .regular);
        if (x + tw / 2 < r.right() + 4 and x - tw / 2 > r.x - 14) _ = ui.text(txt, x - tw / 2, r.y + 6, 10, .regular, ui.colors.text_faint);
        // Minor ticks
        for (1..5) |k| {
            const mx = x + @as(f32, @floatFromInt(k)) * stp / 5 * px_per_s;
            if (mx < r.right()) ui.rect(.{ .x = mx, .y = r.y, .w = 1, .h = 3 }, 0, ui.colors.text_faint.alpha(0.3));
        }
        t += stp;
    }
}

fn trimHandle(key: u64, hx: f32, wr: Rect, col: Rgba) ui.Interaction {
    if (hx < wr.x - 10 or hx > wr.right() + 10) return .{};
    const in = ui.interact(key, .{ .x = hx - 10, .y = wr.y - 4, .w = 20, .h = wr.h + 8 });
    const grow = @max(in.hover_t, in.press_t);
    ui.rect(.{ .x = hx - 1.5, .y = wr.y, .w = 3, .h = wr.h }, 1.5, col);
    const knob: Rect = .{ .x = hx - 7 - grow, .y = wr.y + wr.h / 2 - 17, .w = 14 + grow * 2, .h = 34 };
    ui.shadow(knob.offset(0, 2), 7, 6, ui.colors.shadow.alpha(0.6));
    ui.rect(knob, 7, Rgba{ .r = 1, .g = 1, .b = 1 });
    ui.border(knob, 7, 1.5, col);
    for (0..2) |i| {
        const fi: f32 = @floatFromInt(i);
        ui.rect(.{ .x = hx - 2.5 + fi * 3.5, .y = knob.y + 10, .w = 1.5, .h = 14 }, 0.75, col.alpha(0.7));
    }
    if (in.hovered) ui.setCursor(c.MOUSE_CURSOR_RESIZE_EW);
    return in;
}

fn fadeHandle(key: u64, hx: f32, wr: Rect, col: Rgba, active: bool, tip: []const u8) ui.Interaction {
    if (hx < wr.x - 8 or hx > wr.right() + 8) return .{};
    const center: ui.Vec2 = .{ .x = hx, .y = wr.y + 9 };
    const in = ui.interact(key, .{ .x = hx - 9, .y = wr.y, .w = 18, .h = 18 });
    const grow = @max(in.hover_t, in.press_t);
    ui.circle(center, 6 + grow * 2, if (active) col else ui.colors.elevated);
    ui.border(.{ .x = center.x - 6 - grow * 2, .y = center.y - 6 - grow * 2, .w = 12 + grow * 4, .h = 12 + grow * 4 }, 6 + grow * 2, 1.5, col);
    if (in.hovered) {
        ui.setCursor(c.MOUSE_CURSOR_RESIZE_EW);
        ui.tooltip(key, tip);
    }
    return in;
}

/// "1.25 s" below a minute, "1:02.5" above
pub fn fmtTime(buf: []u8, seconds: f32) []const u8 {
    const t = @max(0, seconds);
    if (t < 60) return std.fmt.bufPrint(buf, "{d:.2} s", .{t}) catch "";
    const m: u32 = @intFromFloat(t / 60);
    return std.fmt.bufPrint(buf, "{d}:{d:0>4.1}", .{ m, t - @as(f32, @floatFromInt(m)) * 60 }) catch "";
}

// ── Transport and exact cut ─────────────────────────────────────────────────

fn transport(a: *App, s: *const library.Sound, e: *Editor, r: Rect, col: Rgba) bool {
    var changed = false;
    const playing = audio.isPlaying(s.audio_id);
    const y = r.y + 6;
    // Big play button
    const play_r: Rect = .{ .x = r.x, .y = y, .w = 132, .h = 40 };
    if (ui.button(ui.id("ed-play", 0), play_r, if (playing) a.t.stop else a.t.play_cut, .{ .icon = if (playing) icons.square else icons.play, .style = .primary, .tooltip = a.t.space_hint })) togglePreview(a, s, e);
    if (ui.chip(ui.id("ed-loop-prev", 0), .{ .x = play_r.right() + 8, .y = y + 4, .w = ui.chipWidth(icons.repeat, a.t.loop_preview), .h = 32 }, icons.repeat, a.t.loop_preview, e.loop_preview, col)) e.loop_preview = !e.loop_preview;

    // Start / end with nudges and "set here"
    const full = fullLength(a, s);
    const sel = selection(e, full);
    const cursor_t: ?f32 = if (playing or audio.isPaused(s.audio_id)) sel.start + audio.cursor(s.audio_id) else null;
    var x = r.right() - 2 * 262;
    changed = timeField(a, ui.id("ed-start", 0), &e.start_field, x, y, a.t.cut_start, sel.start, cursor_t, full, e, true) or changed;
    x += 262;
    changed = timeField(a, ui.id("ed-end", 0), &e.end_field, x, y, a.t.cut_end, sel.end, cursor_t, full, e, false) or changed;
    return changed;
}

fn timeField(a: *App, key: u64, field: *ui.TextField, x: f32, y: f32, caption: []const u8, value: f32, cursor_t: ?f32, full: f32, e: *Editor, is_start: bool) bool {
    var changed = false;
    _ = ui.text(caption, x, y + 12, 12, .semibold, ui.colors.text_muted);
    const fx_x = x + 46;
    if (ui.focus != key) {
        var b: [24]u8 = undefined;
        field.set(std.fmt.bufPrint(&b, "{d:.2}", .{value}) catch "");
    }
    const res = ui.textInput(key, .{ .x = fx_x, .y = y, .w = 86, .h = 40 }, field, .{ .clearable = false, .size = 13 });
    var target: ?f32 = null;
    if (res.changed or res.submitted) {
        if (app_mod.parseSeconds(field.text())) |v| target = v;
    }
    const shift = c.IsKeyDown(c.KEY_LEFT_SHIFT) or c.IsKeyDown(c.KEY_RIGHT_SHIFT);
    const nudge: f32 = if (shift) 0.1 else 0.01;
    if (ui.iconButton(ui.sub(key, 1), .{ .x = fx_x + 90, .y = y + 4, .w = 30, .h = 32 }, icons.chevron_left, .{ .size = 14, .tooltip = a.t.nudge_tip })) target = value - nudge;
    if (ui.iconButton(ui.sub(key, 2), .{ .x = fx_x + 122, .y = y + 4, .w = 30, .h = 32 }, icons.chevron_right, .{ .size = 14, .tooltip = a.t.nudge_tip })) target = value + nudge;
    if (ui.iconButton(ui.sub(key, 3), .{ .x = fx_x + 156, .y = y + 4, .w = 32, .h = 32 }, icons.step_forward, .{ .size = 14, .tooltip = a.t.set_at_playhead, .disabled = cursor_t == null })) target = cursor_t;
    if (target) |t_raw| {
        const min_len: f32 = 0.05;
        const sel = selection(e, full);
        if (is_start) {
            const v = std.math.clamp(t_raw, 0, sel.end - min_len);
            e.params.trim_start = if (v < 0.005) 0 else v;
        } else {
            const v = std.math.clamp(t_raw, sel.start + min_len, full);
            e.params.trim_end = if (v >= full - 0.005) 0 else v;
        }
        changed = true;
    }
    return changed;
}

// ── Sound tab ───────────────────────────────────────────────────────────────

fn soundTab(a: *App, e: *Editor, r: Rect) bool {
    var changed = false;
    const col_w = (r.w - 40) / 2;
    const lx = r.x;
    const rx = r.x + col_w + 40;
    var ly = r.y;
    var ry = r.y;

    // Volume
    {
        dialogs.fieldLabel(lx, ly, a.t.volume);
        var vbuf: [16]u8 = undefined;
        ui.label(std.fmt.bufPrint(&vbuf, "{d:.0}%", .{e.volume * 100}) catch "", .{ .x = lx + col_w - 60, .y = ly - 2, .w = 60, .h = 16 }, 12, .semibold, if (e.volume != 1) ui.colors.accent else ui.colors.text_muted, .right);
        ui.icon(icons.volume_1, .{ .x = lx + 8, .y = ly + 33 }, 14, ui.colors.text_faint);
        ui.icon(icons.volume_2, .{ .x = lx + col_w - 8, .y = ly + 33 }, 14, ui.colors.text_faint);
        if (ui.slider(ui.id("ed-vol", 0), .{ .x = lx + 18, .y = ly + 18, .w = col_w - 36, .h = 30 }, &e.volume, 0, 2)) {
            if (@abs(e.volume - 1) < 0.03) e.volume = 1;
        }
        ly += 66;
    }
    // Speed
    {
        dialogs.fieldLabel(lx, ly, a.t.speed);
        var sp_buf: [16]u8 = undefined;
        const speed_txt = std.fmt.bufPrint(&sp_buf, "{d:.2}×", .{e.params.speed}) catch "";
        ui.label(speed_txt, .{ .x = lx + col_w - 110, .y = ly - 2, .w = 80, .h = 16 }, 12, .semibold, if (e.params.speed != 1) ui.colors.accent else ui.colors.text_muted, .right);
        if (ui.iconButton(ui.id("ed-speed-reset", 0), .{ .x = lx + col_w - 24, .y = ly - 5, .w = 24, .h = 22 }, icons.rotate_ccw, .{ .size = 12, .tooltip = a.t.reset, .disabled = e.params.speed == 1 })) {
            e.params.speed = 1;
            changed = true;
        }
        ui.icon(icons.snail, .{ .x = lx + 8, .y = ly + 33 }, 14, ui.colors.text_faint);
        ui.icon(icons.rabbit, .{ .x = lx + col_w - 8, .y = ly + 33 }, 14, ui.colors.text_faint);
        if (ui.slider(ui.id("ed-speed", 0), .{ .x = lx + 18, .y = ly + 18, .w = col_w - 36, .h = 30 }, &e.params.speed, 0.5, 2)) {
            if (@abs(e.params.speed - 1) < 0.04) e.params.speed = 1;
            e.params.speed = @round(e.params.speed * 100) / 100;
            changed = true;
        }
        ui.label(a.t.speed_hint, .{ .x = lx, .y = ly + 48, .w = col_w, .h = 16 }, 11, .regular, ui.colors.text_faint, .left);
    }

    // Fades
    changed = fadeSlider(a, ui.id("ed-fadein", 0), rx, ry, col_w, a.t.fade_in, &e.params.fade_in) or changed;
    ry += 66;
    changed = fadeSlider(a, ui.id("ed-fadeout", 0), rx, ry, col_w, a.t.fade_out, &e.params.fade_out) or changed;
    ry += 66;
    // Loop
    const loop_r: Rect = .{ .x = rx, .y = ry, .w = col_w, .h = 44 };
    ui.rect(loop_r, ui.radius_lg, ui.colors.bg.alpha(0.55));
    ui.icon(icons.repeat, .{ .x = loop_r.x + 20, .y = loop_r.y + 22 }, 15, if (e.params.loop) ui.colors.accent else ui.colors.text_faint);
    ui.label(a.t.loop, .{ .x = loop_r.x + 38, .y = loop_r.y, .w = col_w - 100, .h = 44 }, 13, .semibold, ui.colors.text, .left);
    if (ui.toggle(ui.id("ed-loop", 0), .{ .x = loop_r.right() - 56, .y = loop_r.y, .w = 48, .h = 44 }, &e.params.loop)) changed = true;
    return changed;
}

fn fadeSlider(a: *App, key: u64, x: f32, y: f32, w: f32, title: []const u8, value: *f32) bool {
    dialogs.fieldLabel(x, y, title);
    var buf: [16]u8 = undefined;
    const txt = if (value.* <= 0.001) a.t.off_short else std.fmt.bufPrint(&buf, "{d:.2} s", .{value.*}) catch "";
    ui.label(txt, .{ .x = x + w - 60, .y = y - 2, .w = 60, .h = 16 }, 12, .semibold, if (value.* > 0) ui.colors.accent else ui.colors.text_muted, .right);
    if (ui.slider(key, .{ .x = x - 8, .y = y + 18, .w = w + 16, .h = 30 }, value, 0, 5)) {
        value.* = @round(value.* * 20) / 20;
        return true;
    }
    return false;
}

// ── Effects tab ─────────────────────────────────────────────────────────────

fn effectsTab(a: *App, s: *const library.Sound, e: *Editor, r_in: Rect, col: Rgba) bool {
    var r = r_in;
    var changed = false;

    // Presets: built-ins, then the user's
    const pr = r.cutTop(40);
    var x = pr.x;
    var row_y = pr.y;
    _ = ui.text(a.t.presets, x, row_y + 9, 12, .semibold, ui.colors.text_muted);
    x += ui.measure(a.t.presets, 12, .semibold) + 12;
    const save_w: f32 = 312;
    const chips_right = pr.right() - save_w - 12;
    var overflow = false;
    for (fx.builtins, 0..) |b, i| {
        const name = a.t.fx_preset_names[b.name];
        const w = ui.chipWidth(b.icon, name);
        if (x + w > chips_right) {
            overflow = true;
            break;
        }
        const on = e.fx.eql(&fx.Chain.fromSlice(b.effects));
        if (ui.chip(ui.id("preset-b", i), .{ .x = x, .y = row_y + 2, .w = w, .h = 30 }, b.icon, name, on, col)) {
            e.fx = fx.Chain.fromSlice(b.effects);
            changed = true;
            playSelection(a, s, e);
        }
        x += w + 6;
    }
    // Save as preset
    const save_r: Rect = .{ .x = pr.right() - save_w, .y = row_y, .w = save_w, .h = 34 };
    const name_res = ui.textInput(ui.id("preset-name", 0), .{ .x = save_r.x, .y = save_r.y, .w = save_w - 104, .h = 34 }, &a.preset_name, .{ .placeholder = a.t.preset_name_ph, .size = 12, .icon = icons.save });
    const can_save = e.fx.len > 0 and std.mem.trim(u8, a.preset_name.text(), " ").len > 0;
    if (ui.button(ui.id("preset-save", 0), .{ .x = save_r.right() - 96, .y = save_r.y, .w = 96, .h = 34 }, a.t.save_preset, .{ .size = 12, .style = .subtle, .disabled = !can_save }) or (name_res.submitted and can_save)) {
        config.savePreset(&a.cfg, std.mem.trim(u8, a.preset_name.text(), " "), e.fx.slice());
        a.markConfig();
        ui.toast(.success, a.tf(a.t.preset_saved, .{std.mem.trim(u8, a.preset_name.text(), " ")}));
        a.preset_name.clear();
        ui.focus = 0;
    }
    // Second row: what didn't fit, plus user presets
    const pr2 = r.cutTop(40);
    x = pr2.x;
    row_y = pr2.y;
    if (overflow) {
        for (fx.builtins, 0..) |b, i| {
            const name = a.t.fx_preset_names[b.name];
            const w = ui.chipWidth(b.icon, name);
            // Skip those already shown on the first row
            var shown_first = false;
            {
                var fx_x = pr.x + ui.measure(a.t.presets, 12, .semibold) + 12;
                for (fx.builtins[0 .. i + 1]) |bb| {
                    const ww = ui.chipWidth(bb.icon, a.t.fx_preset_names[bb.name]);
                    if (fx_x + ww > chips_right) break;
                    fx_x += ww + 6;
                } else shown_first = true;
            }
            if (shown_first) continue;
            if (x + w > pr2.right()) break;
            const on = e.fx.eql(&fx.Chain.fromSlice(b.effects));
            if (ui.chip(ui.id("preset-b", i), .{ .x = x, .y = row_y + 2, .w = w, .h = 30 }, b.icon, name, on, col)) {
                e.fx = fx.Chain.fromSlice(b.effects);
                changed = true;
                playSelection(a, s, e);
            }
            x += w + 6;
        }
    }
    var delete_preset: ?usize = null;
    for (a.cfg.fx_presets, 0..) |p, i| {
        const w = ui.chipWidth(icons.user, p.name) + 22;
        if (x + w > pr2.right()) break;
        const cr: Rect = .{ .x = x, .y = row_y + 2, .w = w, .h = 30 };
        const chain = fx.Chain.fromStored(p.fx);
        const on = e.fx.eql(&chain);
        if (ui.chip(ui.id("preset-u", i), .{ .x = cr.x, .y = cr.y, .w = cr.w - 22, .h = cr.h }, icons.user, p.name, on, col)) {
            e.fx = chain;
            changed = true;
            playSelection(a, s, e);
        }
        if (ui.iconButton(ui.id("preset-del", i), .{ .x = cr.right() - 26, .y = cr.y + 3, .w = 24, .h = 24 }, icons.x, .{ .size = 11, .tooltip = a.t.delete_preset })) delete_preset = i;
        x += w + 6;
    }
    if (delete_preset) |i| {
        config.deletePreset(&a.cfg, i);
        a.markConfig();
    }
    if (a.cfg.fx_presets.len == 0 and !overflow) {
        ui.label(a.t.presets_hint, .{ .x = pr2.x, .y = pr2.y, .w = pr2.w, .h = 34 }, 12, .regular, ui.colors.text_faint, .left);
    }

    // Chain actions
    const act = r.cutTop(40);
    _ = ui.text(a.t.fx_chain, act.x, act.y + 12, 12, .semibold, ui.colors.text_muted);
    var ax = act.right();
    ax -= 90;
    if (ui.button(ui.id("fx-clear", 0), .{ .x = ax, .y = act.y + 4, .w = 90, .h = 30 }, a.t.clear, .{ .icon = icons.eraser, .style = .ghost, .size = 12, .disabled = e.fx.len == 0 })) {
        e.fx = .{};
        changed = true;
    }
    ax -= 8 + ui.chipWidth(icons.ear, a.t.bypass);
    if (ui.chip(ui.id("fx-bypass", 0), .{ .x = ax, .y = act.y + 4, .w = ui.chipWidth(icons.ear, a.t.bypass), .h = 30 }, icons.ear, a.t.bypass, bypass, ui.colors.warning)) {
        bypass = !bypass;
        changed = true;
    }
    if (ui.mouseIn(.{ .x = ax, .y = act.y + 4, .w = ui.chipWidth(icons.ear, a.t.bypass), .h = 30 })) ui.tooltip(ui.id("fx-bypass", 1), a.t.bypass_tip);
    ax -= 8 + 150;
    if (ui.button(ui.id("fx-add", 0), .{ .x = ax, .y = act.y + 4, .w = 150, .h = 30 }, a.t.add_effect, .{ .icon = icons.plus, .style = if (e.add_menu) .primary else .subtle, .size = 12, .disabled = e.fx.len >= fx.max and !e.add_menu })) e.add_menu = !e.add_menu;
    _ = r.cutTop(6);

    if (e.add_menu) return effectPicker(a, e, r) or changed;

    if (e.fx.len == 0) {
        const cy = r.y + @min(r.h, 160) * 0.45;
        ui.icon(icons.wand_sparkles, .{ .x = r.x + r.w / 2, .y = cy }, 26, ui.colors.accent.alpha(0.8));
        ui.label(a.t.fx_empty, .{ .x = r.x, .y = cy + 22, .w = r.w, .h = 20 }, 14, .semibold, ui.colors.text, .center);
        ui.label(a.t.fx_empty_hint, .{ .x = r.x, .y = cy + 44, .w = r.w, .h = 18 }, 12, .regular, ui.colors.text_muted, .center);
        return changed;
    }

    // Cards, two per row, in chain order
    const gap: f32 = 14;
    const card_w = (r.w - gap - 10) / 2;
    var y = ui.beginScroll(ui.id("fx-scroll", 0), r);
    const top = y;
    var row_h: f32 = 0;
    var remove: ?usize = null;
    var swap_with: ?[2]usize = null;
    var i: usize = 0;
    while (i < e.fx.len) : (i += 1) {
        const effect = &e.fx.items[i];
        const ch = cardHeight(effect);
        const cx = r.x + @as(f32, @floatFromInt(i % 2)) * (card_w + gap);
        if (i % 2 == 0 and i > 0) {
            y += row_h + gap;
            row_h = 0;
        }
        row_h = @max(row_h, ch);
        const res = effectCard(a, effect, i, e.fx.len, .{ .x = cx, .y = y, .w = card_w, .h = ch }, col);
        if (res.changed) changed = true;
        if (res.remove) remove = i;
        if (res.move_left and i > 0) swap_with = .{ i, i - 1 };
        if (res.move_right and i + 1 < e.fx.len) swap_with = .{ i, i + 1 };
    }
    y += row_h;
    ui.endScroll(y - top + 10);
    if (remove) |ri| {
        e.fx.remove(ri);
        changed = true;
    }
    if (swap_with) |sw| {
        e.fx.swap(sw[0], sw[1]);
        changed = true;
    }
    return changed;
}

fn cardHeight(e: *const fx.Effect) f32 {
    return 52 + @as(f32, @floatFromInt(fx.params(e.kind).len)) * 50 + (if (e.auto >= 0) @as(f32, 44) else 0);
}

const CardResult = struct { changed: bool = false, remove: bool = false, move_left: bool = false, move_right: bool = false };

fn effectCard(a: *App, effect: *fx.Effect, i: usize, n: usize, r: Rect, col: Rgba) CardResult {
    var out: CardResult = .{};
    const key = ui.id("fx-card", @backingInt(effect.kind));
    const on_t = ui.anim(ui.sub(key, 1), if (effect.on) 1 else 0, 14);
    ui.rect(r, ui.radius_md, ui.colors.surface);
    ui.border(r, ui.radius_md, 1, ui.colors.border);
    ui.pushAlpha(0.5 + 0.5 * on_t);
    // Header: order, icon, name
    var nb: [4]u8 = undefined;
    ui.rect(.{ .x = r.x, .y = r.y, .w = 3, .h = r.h }, 0, Rgba.lerp(ui.colors.border, col, on_t));
    _ = ui.text(std.fmt.bufPrint(&nb, "{d:0>2}", .{i + 1}) catch "", r.x + 14, r.y + 18, 11, .mono, ui.colors.text_faint);
    ui.icon(effect.kind.icon(), .{ .x = r.x + 46, .y = r.y + 25 }, 15, col);
    ui.label(a.t.fx_names[@backingInt(effect.kind)], .{ .x = r.x + 60, .y = r.y + 14, .w = r.w - 60 - 170, .h = 22 }, 14, .semibold, ui.colors.text, .left);
    ui.popAlpha();
    var bx = r.right() - 36;
    if (ui.iconButton(ui.sub(key, 2), .{ .x = bx, .y = r.y + 10, .w = 30, .h = 30 }, icons.x, .{ .size = 14, .tooltip = a.t.remove })) out.remove = true;
    bx -= 32;
    if (ui.iconButton(ui.sub(key, 3), .{ .x = bx, .y = r.y + 10, .w = 30, .h = 30 }, icons.chevron_right, .{ .size = 14, .tooltip = a.t.move_later, .disabled = i + 1 >= n })) out.move_right = true;
    bx -= 30;
    if (ui.iconButton(ui.sub(key, 4), .{ .x = bx, .y = r.y + 10, .w = 30, .h = 30 }, icons.chevron_left, .{ .size = 14, .tooltip = a.t.move_earlier, .disabled = i == 0 })) out.move_left = true;
    bx -= 56;
    if (ui.toggle(ui.sub(key, 5), .{ .x = bx, .y = r.y + 4, .w = 50, .h = 42 }, &effect.on)) out.changed = true;

    // Parameters
    ui.pushAlpha(0.45 + 0.55 * on_t);
    defer ui.popAlpha();
    var y = r.y + 52;
    for (fx.params(effect.kind), 0..) |spec, pi| {
        const automated = effect.auto == @as(i8, @intCast(pi));
        _ = ui.text(if (automated) a.tf("{} · {}", .{ a.t.fx_params[@backingInt(spec.label)], a.t.auto_start }) else a.t.fx_params[@backingInt(spec.label)], r.x + 16, y, 12, .semibold, ui.colors.text_muted);
        var vb: [24]u8 = undefined;
        const changed_val = effect.p[pi] != spec.default;
        ui.label(fx.formatValue(&vb, spec, effect.p[pi]), .{ .x = r.right() - 158, .y = y - 2, .w = 90, .h = 16 }, 12, .semibold, if (changed_val) col else ui.colors.text_faint, .right);
        // Automation: this parameter glides to another value over the sound
        if (ui.iconButton(ui.sub(key, 30 + pi), .{ .x = r.right() - 62, .y = y - 5, .w = 24, .h = 22 }, icons.chart_line, .{ .size = 12, .tooltip = if (automated) a.t.auto_off_tip else a.t.auto_on_tip, .active = automated })) {
            if (automated) {
                effect.auto = -1;
            } else {
                effect.auto = @intCast(pi);
                // Start from somewhere audible: the other end of the range
                const mid = (spec.min + spec.max) / 2;
                effect.auto_to = if (effect.p[pi] > mid) spec.min else spec.max;
            }
            out.changed = true;
        }
        if (ui.iconButton(ui.sub(key, 20 + pi), .{ .x = r.right() - 36, .y = y - 5, .w = 24, .h = 22 }, icons.rotate_ccw, .{ .size = 11, .tooltip = a.t.reset, .disabled = !changed_val })) {
            effect.p[pi] = spec.default;
            out.changed = true;
        }
        var t = fx.toSlider(spec, effect.p[pi]);
        if (ui.slider(ui.sub(key, 10 + pi), .{ .x = r.x + 8, .y = y + 16, .w = r.w - 16, .h = 28 }, &t, 0, 1)) {
            const v = fx.fromSlider(spec, t);
            if (v != effect.p[pi]) {
                effect.p[pi] = v;
                out.changed = true;
            }
        }
        y += 50;
        if (automated) {
            // Where it ends up, with a ramp drawn between the two values
            _ = ui.text(a.t.auto_end, r.x + 16, y - 2, 12, .semibold, col);
            var eb: [24]u8 = undefined;
            ui.label(fx.formatValue(&eb, spec, effect.auto_to), .{ .x = r.right() - 158, .y = y - 4, .w = 90, .h = 16 }, 12, .semibold, col, .right);
            var te = fx.toSlider(spec, effect.auto_to);
            if (ui.slider(ui.sub(key, 40 + pi), .{ .x = r.x + 8, .y = y + 12, .w = r.w - 16, .h = 28 }, &te, 0, 1)) {
                const v = fx.fromSlider(spec, te);
                if (v != effect.auto_to) {
                    effect.auto_to = v;
                    out.changed = true;
                }
            }
            const x0 = r.x + 16 + (r.w - 32) * fx.toSlider(spec, effect.p[pi]);
            const x1 = r.x + 16 + (r.w - 32) * te;
            ui.line(.{ .x = x0, .y = y - 20 }, .{ .x = x1, .y = y + 26 }, 1, col.alpha(0.5));
            y += 44;
        }
    }
    return out;
}

fn effectPicker(a: *App, e: *Editor, r: Rect) bool {
    var changed = false;
    const cols: usize = 4;
    const gap: f32 = 10;
    const tw = (r.w - gap * @as(f32, @floatFromInt(cols - 1)) - 10) / @as(f32, @floatFromInt(cols));
    const th: f32 = 74;
    const y = ui.beginScroll(ui.id("fx-picker", 0), r);
    var n: usize = 0;
    for (fx.all_kinds) |k| {
        const used = e.fx.has(k);
        const cx = r.x + @as(f32, @floatFromInt(n % cols)) * (tw + gap);
        const cy = y + @as(f32, @floatFromInt(n / cols)) * (th + gap);
        n += 1;
        const tr: Rect = .{ .x = cx, .y = cy, .w = tw, .h = th };
        const key = ui.id("fx-pick", @backingInt(k));
        const in = ui.interactOpts(key, tr, !used and e.fx.len < fx.max);
        ui.pushAlpha(if (used) 0.4 else 1);
        ui.rect(tr, ui.radius_lg, Rgba.lerp(ui.colors.elevated, ui.colors.surface_hover, in.hover_t));
        ui.border(tr, ui.radius_lg, 1, Rgba.lerp(ui.colors.border, ui.colors.accent.alpha(0.7), in.hover_t));
        ui.icon(k.icon(), .{ .x = tr.x + 26, .y = tr.y + 37 }, 18, Rgba.lerp(ui.colors.text_muted, ui.colors.accent, in.hover_t));
        ui.label(a.t.fx_names[@backingInt(k)], .{ .x = tr.x + 54, .y = tr.y + 14, .w = tr.w - 62, .h = 20 }, 13, .semibold, ui.colors.text, .left);
        ui.label(if (used) a.t.fx_in_chain else a.t.fx_descs[@backingInt(k)], .{ .x = tr.x + 54, .y = tr.y + 36, .w = tr.w - 62, .h = 18 }, 11, .regular, ui.colors.text_muted, .left);
        ui.popAlpha();
        if (in.clicked) {
            e.fx.add(fx.Effect.init(k));
            e.add_menu = false;
            changed = true;
        }
    }
    const rows = (n + cols - 1) / cols;
    ui.endScroll(@as(f32, @floatFromInt(rows)) * (th + gap) + 10);
    return changed;
}

// ── Pad tab ─────────────────────────────────────────────────────────────────

fn padTab(a: *App, s: *const library.Sound, e: *Editor, r: Rect, idx: usize) void {
    const col_w = (r.w - 40) / 2;
    const lx = r.x;
    const rx = r.x + col_w + 40;
    var ly = r.y;

    // Color
    dialogs.fieldLabel(lx, ly, a.t.color);
    const spacing = @min(36, col_w / @as(f32, @floatFromInt(theme.pad_palette.len + 1)));
    for (0..theme.pad_palette.len + 1) |ci| {
        const col = theme.padColor(@intCast(ci), ui.colors.accent);
        const center: ui.Vec2 = .{ .x = lx + 13 + @as(f32, @floatFromInt(ci)) * spacing, .y = ly + 36 };
        const key = ui.id("ed-color", ci);
        const in = ui.interact(key, .{ .x = center.x - 14, .y = center.y - 14, .w = 28, .h = 28 });
        const sel_t = ui.anim(ui.sub(key, 1), if (e.color == ci) 1 else 0, 16);
        const sw: Rect = .{ .x = center.x - 12, .y = center.y - 12, .w = 24, .h = 24 };
        if (sel_t > 0.01) ui.border(sw.grow(3), ui.radius_sm + 2, 1.5, ui.colors.text.alpha(sel_t));
        ui.rect(sw.inset(-in.hover_t), ui.radius_sm, col);
        if (ci == 0) ui.icon(icons.sparkles, center, 10, ui.colors.accent_text);
        if (sel_t > 0.5 and ci != 0) ui.icon(icons.check, center, 11, Rgba{ .r = 1, .g = 1, .b = 1 });
        if (in.clicked) e.color = @intCast(ci);
    }
    ly += 70;

    // Hotkey
    dialogs.fieldLabel(lx, ly, a.t.hotkey_label);
    dialogs.hotkeyCapture(a, idx, .{ .x = lx, .y = ly + 22, .w = col_w, .h = 42 });
    if (a.hotkeyOwner(e.hotkeyText(), idx)) |owner| {
        ui.label(a.tf(a.t.hotkey_conflict, .{a.workspace().sounds.items[owner].name}), .{ .x = lx, .y = ly + 68, .w = col_w, .h = 16 }, 11, .semibold, ui.colors.warning, .left);
    }

    // About this sound
    const info: Rect = .{ .x = rx, .y = r.y, .w = col_w, .h = @min(r.h, 214) };
    ui.rect(info, ui.radius_lg, ui.colors.bg.alpha(0.5));
    var y = info.y + 14;
    const rows = [_]struct { ic: u21, label: []const u8, value: []const u8 }{
        .{ .ic = icons.file_audio, .label = a.t.info_file, .value = s.file },
        .{ .ic = icons.circle_play, .label = a.t.info_plays, .value = a.tf("{}", .{s.plays}) },
        .{ .ic = icons.clock, .label = a.t.info_time, .value = blk: {
            var b: [24]u8 = undefined;
            break :blk a.tf("{}", .{app_mod.formatDuration(&b, s.play_seconds)});
        } },
        .{ .ic = icons.git_fork, .label = a.t.info_variants, .value = a.tf("{}", .{a.workspace().fileUsers(s.file)}) },
        .{ .ic = icons.scale, .label = a.t.info_loudness, .value = blk: {
            if (s.loudness >= 0) break :blk "—";
            const gain = 20 * std.math.log10(@import("loudness.zig").gainFor(s, a.cfg.normalize_target));
            var lb: [32]u8 = undefined;
            const txt = if (a.cfg.normalize_library)
                std.fmt.bufPrint(&lb, "{d:.1} dB ({s}{d:.1} dB)", .{ s.loudness, if (gain >= 0) "+" else "", gain }) catch ""
            else
                std.fmt.bufPrint(&lb, "{d:.1} dB", .{s.loudness}) catch "";
            break :blk a.tf("{}", .{txt});
        } },
    };
    for (rows) |row| {
        ui.icon(row.ic, .{ .x = info.x + 22, .y = y + 12 }, 14, ui.colors.text_faint);
        _ = ui.text(row.label, info.x + 40, y + 4, 12, .regular, ui.colors.text_muted);
        ui.label(row.value, .{ .x = info.x + 150, .y = y, .w = info.w - 166, .h = 24 }, 12, .semibold, ui.colors.text, .right);
        y += 36;
    }
}

// ── Footer ──────────────────────────────────────────────────────────────────

fn footer(a: *App, s: *const library.Sound, e: *Editor, r: Rect, idx: usize, open: bool) void {
    const fy = r.y + 18;
    ui.rect(.{ .x = r.x - 24, .y = r.y + 2, .w = r.w + 48, .h = 1 }, 0, ui.colors.border.alpha(0.7));
    if (ui.button(ui.id("ed-delete", 0), .{ .x = r.x, .y = fy, .w = 110, .h = 40 }, a.t.delete, .{ .style = .danger, .icon = icons.trash_2 })) {
        a.cancelEditor(idx);
        a.dialog = .{ .delete_sound = idx };
        a.dialog_closing = .none;
        return;
    }
    if (ui.button(ui.id("ed-variant", 0), .{ .x = r.x + 120, .y = fy, .w = 160, .h = 40 }, a.t.create_variant, .{ .icon = icons.git_fork, .style = .ghost, .size = 13, .tooltip = a.t.variant_tip })) {
        // Keep this pad as it was; the variant starts from the edits
        const chain = e.fx;
        a.saveEditor(idx);
        a.createVariant(idx, null);
        a.editor.fx = chain;
        return;
    }
    const has_ffmpeg = tools.available(.ffmpeg);
    const trimmed = e.params.trim_start > 0 or e.params.trim_end > 0;
    if (ui.button(ui.id("ed-apply", 0), .{ .x = r.x + 290, .y = fy, .w = 170, .h = 40 }, a.t.apply_to_file, .{
        .icon = icons.scissors,
        .style = .ghost,
        .disabled = !has_ffmpeg or (!trimmed and !a.cfg.normalize_audio),
        .tooltip = if (has_ffmpeg) a.t.apply_to_file_tip else a.t.needs_ffmpeg,
        .size = 13,
    })) {
        e.normalize = a.cfg.normalize_audio;
        a.saveEditor(idx);
        a.startEditJob(idx);
        dialogs.close(a);
        return;
    }
    _ = s;
    if (ui.button(ui.id("ed-cancel", 0), .{ .x = r.right() - 252, .y = fy, .w = 110, .h = 40 }, a.t.cancel, .{ .style = .ghost })) {
        previewing = false;
        dialogs.close(a);
    }
    const save = ui.button(ui.id("ed-save", 0), .{ .x = r.right() - 134, .y = fy, .w = 134, .h = 40 }, a.t.save, .{ .style = .primary, .icon = icons.check });
    if (open and save) {
        previewing = false;
        bypass = false;
        a.saveEditor(idx);
        dialogs.close(a);
    }
}
