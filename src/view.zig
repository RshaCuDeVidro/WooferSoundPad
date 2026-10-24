//! Frame layout: sidebar + current page + overlays.

const std = @import("std");
const c = @import("c");
const ui = @import("ui.zig");
const theme = @import("theme.zig");
const audio = @import("audio.zig");
const sys = @import("sys.zig");
const app_mod = @import("app.zig");
const App = app_mod.App;
const Page = app_mod.Page;
const icons = ui.icons;
const Rect = ui.Rect;
const Rgba = ui.Rgba;

const soundboard = @import("view_soundboard.zig");
const explore = @import("view_explore.zig");
const online = @import("view_online.zig");
const downloads = @import("view_downloads.zig");
const settings = @import("view_settings.zig");
const dialogs = @import("view_dialogs.zig");
const onboarding = @import("view_onboarding.zig");
const stage = @import("view_stage.zig");
const stats_view = @import("view_stats.zig");

pub const sidebar_w: f32 = 224;

pub fn draw(a: *App) void {
    if (a.stage) {
        stage.draw(a);
        drawOverlays(a);
        return;
    }
    const screen = ui.screen;
    var content = screen;
    const side = content.cutLeft(sidebar_w);

    // Page with a short fade/slide when switching
    const since = ui.time - a.page_changed_at;
    const t = if (ui.animations) ui.easeOutCubic(since / 0.28) else 1;
    ui.pushAlpha(0.15 + 0.85 * t);
    ui.pushTranslate(0, (1 - t) * 14);
    switch (a.page) {
        .soundboard => soundboard.draw(a, content),
        .explore => explore.draw(a, content),
        .online => online.draw(a, content),
        .downloads => downloads.draw(a, content),
        .stats => stats_view.draw(a, content),
        .settings => settings.draw(a, content),
    }
    ui.popTranslate();
    ui.popAlpha();

    drawSidebar(a, side);
    drawOverlays(a);
}

fn drawOverlays(a: *App) void {
    // Overlays, back to front
    if (a.menu) |m| switch (m.kind) {
        .pad => soundboard.drawPadMenu(a, m),
        .workspace => drawWorkspaceMenu(a, m),
    };
    dialogs.draw(a);
    onboarding.draw(a);
    ui.drawDropdownPopup();
    ui.drawToasts();
    ui.drawTooltip();
}

// ── Sidebar ─────────────────────────────────────────────────────────────────

fn drawSidebar(a: *App, r_in: Rect) void {
    var r = r_in;
    ui.rect(r, 0, ui.colors.sidebar);
    ui.rect(.{ .x = r.right() - 1, .y = r.y, .w = 1, .h = r.h }, 0, ui.colors.border);
    r = r.insetXY(12, 0);

    // Brand: logo + wordmark, no effects
    const brand = r.cutTop(60);
    ui.image(a.logo, .{ .x = brand.x + 2, .y = brand.y + 17, .w = 26, .h = 26 }, 0, .{ .r = 1, .g = 1, .b = 1 });
    const w1 = ui.text("WOOFER", brand.x + 36, brand.y + 22, 14, .mono_bold, ui.colors.text);
    _ = ui.text("PAD", brand.x + 36 + w1 + 4, brand.y + 22, 14, .mono_bold, ui.colors.accent);
    ui.label(a.version, .{ .x = brand.x, .y = brand.y + 22, .w = brand.w - 4, .h = 16 }, 10, .mono, ui.colors.text_faint, .right);
    ui.rect(.{ .x = r_in.x, .y = brand.bottom(), .w = r_in.w - 1, .h = 1 }, 0, ui.colors.border);
    _ = r.cutTop(10);

    // Navigation
    const nav = [_]struct { page: Page, icon: u21, label: []const u8 }{
        .{ .page = .soundboard, .icon = icons.layout_grid, .label = a.t.nav_soundboard },
        .{ .page = .explore, .icon = icons.compass, .label = a.t.nav_explore },
        .{ .page = .online, .icon = icons.globe, .label = a.t.nav_online },
        .{ .page = .downloads, .icon = icons.download, .label = a.t.nav_downloads },
        .{ .page = .stats, .icon = icons.bar_chart, .label = a.t.nav_stats },
        .{ .page = .settings, .icon = icons.settings, .label = a.t.nav_settings },
    };
    const item_h: f32 = 34;
    const nav_top = r.y;
    const active_idx: f32 = @floatFromInt(@backingInt(a.page));
    const bar_y = ui.anim(ui.id("nav-pill", 0), nav_top + active_idx * (item_h + 2), 22);
    ui.rect(.{ .x = r.x, .y = bar_y, .w = r.w, .h = item_h }, ui.radius_sm, ui.colors.surface);
    ui.rect(.{ .x = r.x, .y = bar_y + 8, .w = 2, .h = item_h - 16 }, 1, ui.colors.accent);

    for (nav, 0..) |item, i| {
        const row = r.cutTop(item_h + 2);
        const box: Rect = .{ .x = row.x, .y = row.y, .w = row.w, .h = item_h };
        const key = ui.id("nav", i);
        const in = ui.interact(key, box);
        if (in.clicked) a.goto(item.page);
        const active = a.page == item.page;
        if (!active) ui.rect(box, ui.radius_sm, ui.colors.text.alpha(in.hover_t * 0.04));
        const col = if (active) ui.colors.text else Rgba.lerp(ui.colors.text_muted, ui.colors.text, in.hover_t);
        ui.icon(item.icon, .{ .x = box.x + 18, .y = box.y + item_h / 2 }, 15, if (active) ui.colors.accent else col);
        ui.label(item.label, .{ .x = box.x + 36, .y = box.y, .w = box.w - 70, .h = item_h }, 13, if (active) .semibold else .regular, col, .left);

        var right_text: []const u8 = "";
        var key_buf: [8]u8 = undefined;
        if (item.page == .downloads and a.jobs.activeCount() > 0) {
            right_text = std.fmt.bufPrint(&key_buf, "{d}", .{a.jobs.activeCount()}) catch "";
            ui.label(right_text, .{ .x = box.right() - 40, .y = box.y, .w = 30, .h = item_h }, 11, .mono_bold, ui.colors.accent, .right);
        } else if (in.hover_t > 0.05) {
            ui.pushAlpha(in.hover_t);
            ui.label(std.fmt.bufPrint(&key_buf, "^{d}", .{i + 1}) catch "", .{ .x = box.right() - 40, .y = box.y, .w = 30, .h = item_h }, 10, .mono, ui.colors.text_faint, .right);
            ui.popAlpha();
        }
    }

    // Workspaces
    _ = r.cutTop(16);
    const head = r.cutTop(26);
    _ = ui.text(a.t.workspaces, head.x + 6, head.y + 8, 10, .mono, ui.colors.text_faint);
    if (ui.iconButton(ui.id("ws-add", 0), .{ .x = head.right() - 26, .y = head.y, .w = 26, .h = 26 }, icons.plus, .{ .tooltip = a.t.new_workspace, .size = 14 })) {
        a.name_field.clear();
        a.dialog = .create_workspace;
    }

    const bottom = r.cutBottom(176);
    const list = r;
    var y = ui.beginScroll(ui.id("ws-scroll", 0), list);
    const row_h: f32 = 30;
    for (a.lib.workspaces.items, 0..) |ws, i| {
        const row: Rect = .{ .x = list.x, .y = y, .w = list.w - 4, .h = row_h };
        y += row_h + 1;
        const key = ui.idStr("ws", ws.name);
        const in = ui.interact(key, row);
        const active = i == a.ws;
        if (in.clicked) {
            a.switchWorkspace(i);
            a.goto(.soundboard);
        }
        if (in.double_clicked) {
            a.name_field.set(ws.name);
            a.dialog = .{ .rename_workspace = i };
        }
        if (in.right_clicked) a.menu = .{ .kind = .workspace, .index = i, .pos = ui.mouse };
        if (active) ui.rect(row, ui.radius_sm, ui.colors.surface);
        ui.rect(row, ui.radius_sm, ui.colors.text.alpha(in.hover_t * 0.04));
        const dot_col = theme.padColor(ws.color, ui.colors.accent);
        ui.rect(.{ .x = row.x + 10, .y = row.y + row_h / 2 - 4, .w = 8, .h = 8 }, 1, if (active) dot_col else dot_col.alpha(0.55));
        var cnt_buf: [12]u8 = undefined;
        const cnt = std.fmt.bufPrint(&cnt_buf, "{d}", .{ws.sounds.items.len}) catch "";
        ui.label(cnt, .{ .x = row.right() - 40, .y = row.y, .w = 32, .h = row_h }, 11, .mono, ui.colors.text_faint, .right);
        ui.label(ws.name, .{ .x = row.x + 26, .y = row.y, .w = row.w - 70, .h = row_h }, 13, if (active) .semibold else .regular, if (active) ui.colors.text else ui.colors.text_muted, .left);
    }
    ui.endScroll(y - (list.y - ui.scrollInfo(ui.id("ws-scroll", 0)).offset));

    drawTransport(a, .{ .x = r_in.x, .y = bottom.y, .w = r_in.w - 1, .h = bottom.h });
}

/// Bottom of the sidebar: status, master meter and fader, stop / pause, virtual mic
fn drawTransport(a: *App, r: Rect) void {
    ui.rect(.{ .x = r.x, .y = r.y, .w = r.w, .h = 1 }, 0, ui.colors.border);
    const in_r = r.insetXY(14, 0);
    const playing = audio.playingCount();
    const paused = audio.pausedCount();

    // Status line with an LED
    var y = r.y + 16;
    const led_on = playing > 0;
    const blink = paused > 0 and playing == 0 and @mod(ui.time, 1.0) < 0.5;
    ui.rect(.{ .x = in_r.x, .y = y + 3, .w = 7, .h = 7 }, 1, if (led_on or blink) ui.colors.success else ui.colors.text_faint.alpha(0.4));
    const queue_name: ?[]const u8 = if (a.queue.current) |qi| (if (a.queueSound(qi)) |si| a.workspace().sounds.items[si].name else null) else null;
    var sb: [48]u8 = undefined;
    const status = if (queue_name) |n| n else if (playing > 0) (std.fmt.bufPrint(&sb, "{s}", .{a.tf(a.t.playing_count, .{playing})}) catch "") else if (paused > 0) a.t.paused else a.t.nothing_playing;
    ui.label(status, .{ .x = in_r.x + 14, .y = y - 2, .w = in_r.w - 14, .h = 18 }, 11, .mono, if (led_on) ui.colors.text else ui.colors.text_muted, .left);
    y += 24;

    // Master meter: the loudest sound right now
    var peak: f32 = 0;
    for (a.workspace().sounds.items) |s| peak = @max(peak, s.level);
    ui.meter(.{ .x = in_r.x, .y = y, .w = in_r.w, .h = 5 }, peak * a.cfg.master_volume, false);
    y += 14;

    // Master fader
    const vol_icon: u21 = if (a.cfg.master_volume <= 0.001) icons.volume_x else icons.volume_2;
    if (ui.iconButton(ui.id("np-mute", 0), .{ .x = in_r.x - 6, .y = y, .w = 28, .h = 28 }, vol_icon, .{ .size = 15 })) {
        a.cfg.master_volume = if (a.cfg.master_volume > 0.001) 0 else 0.8;
        audio.applyVolumes(&a.cfg);
        a.markConfig();
    }
    if (ui.slider(ui.id("np-vol", 0), .{ .x = in_r.x + 22, .y = y, .w = in_r.w - 58, .h = 28 }, &a.cfg.master_volume, 0, 1)) {
        audio.applyVolumes(&a.cfg);
        a.markConfig();
    }
    var vb: [8]u8 = undefined;
    ui.label(std.fmt.bufPrint(&vb, "{d:.0}", .{a.cfg.master_volume * 100}) catch "", .{ .x = in_r.right() - 30, .y = y, .w = 30, .h = 28 }, 11, .mono, ui.colors.text_muted, .right);
    y += 36;

    // Pause + stop
    const any = playing > 0 or paused > 0;
    const half = (in_r.w - 6) / 2;
    if (ui.button(ui.id("np-pause", 0), .{ .x = in_r.x, .y = y, .w = half, .h = 30 }, if (playing == 0 and paused > 0) a.t.resume_play else a.t.pause, .{
        .icon = if (playing == 0 and paused > 0) icons.play else icons.pause,
        .disabled = !any,
        .size = 12,
        .tooltip = a.t.pause_all,
    })) a.togglePause();
    if (ui.button(ui.id("np-stop", 0), .{ .x = in_r.x + half + 6, .y = y, .w = half, .h = 30 }, a.t.stop, .{
        .icon = icons.square,
        .style = if (any) .danger else .secondary,
        .disabled = !any and a.queue.current == null,
        .size = 12,
        .tooltip = "Esc",
    })) a.stopAll();
    y += 40;

    // Virtual mic
    const mic_on = audio.outputActive(.mic);
    const mic_row: Rect = .{ .x = in_r.x - 4, .y = y, .w = in_r.w + 8, .h = 26 };
    const in = ui.interact(ui.id("np-mic", 0), mic_row);
    if (in.clicked) a.goto(.settings);
    ui.rect(mic_row, ui.radius_sm, ui.colors.text.alpha(in.hover_t * 0.05));
    ui.rect(.{ .x = in_r.x, .y = y + 10, .w = 7, .h = 7 }, 1, if (mic_on) ui.colors.success else ui.colors.text_faint.alpha(0.4));
    ui.label(if (mic_on) a.t.mic_on else a.t.mic_off, .{ .x = in_r.x + 14, .y = y, .w = in_r.w - 46, .h = 26 }, 11, .mono, ui.colors.text_muted, .left);
    if (mic_on and a.voiceAvailable()) {
        const muted = a.cfg.voice_muted;
        if (ui.iconButton(ui.id("np-voice", 0), .{ .x = in_r.right() - 26, .y = y, .w = 26, .h = 26 }, if (muted) icons.mic_off else icons.mic, .{
            .tooltip = if (muted) a.t.unmute_voice else a.t.mute_voice,
            .color = if (muted) ui.colors.danger else null,
            .size = 13,
        })) a.toggleVoiceMute();
    }
}

fn drawWorkspaceMenu(a: *App, m: app_mod.MenuState) void {
    if (m.index >= a.lib.workspaces.items.len) {
        a.menu = null;
        return;
    }
    var menu = ui.beginMenu(ui.id("ws-menu", m.index), m.pos, 3, 1);
    var close = false;
    if (menu.item(icons.pencil, a.t.rename, false)) {
        a.name_field.set(a.lib.workspaces.items[m.index].name);
        a.dialog = .{ .rename_workspace = m.index };
        close = true;
    }
    if (menu.item(icons.folder_open, a.t.open_folder, false)) {
        sys.openFolder(a.lib.workspaces.items[m.index].dir);
        close = true;
    }
    menu.separator();
    if (menu.item(icons.trash_2, a.t.delete, true)) {
        a.dialog = .{ .delete_workspace = m.index };
        close = true;
    }
    if (ui.endMenu(&menu) or close) a.menu = null;
}

// ── Shared page pieces ──────────────────────────────────────────────────────

pub const page_pad_x: f32 = 28;

/// Title + subtitle. Returns the remaining area to the right for actions.
pub fn header(r: *Rect, title: []const u8, subtitle: []const u8) Rect {
    const h = r.cutTop(78);
    _ = ui.text(title, h.x, h.y + 24, 22, .display, ui.colors.text);
    ui.label(subtitle, .{ .x = h.x, .y = h.y + 52, .w = h.w * 0.6, .h = 18 }, 13, .regular, ui.colors.text_muted, .left);
    ui.rect(.{ .x = h.x, .y = h.bottom() - 1, .w = h.w, .h = 1 }, 0, ui.colors.border);
    _ = r.cutTop(14);
    return .{ .x = h.x + h.w * 0.45, .y = h.y + 22, .w = h.w * 0.55, .h = 36 };
}

/// Icon + text + optional buttons, quietly centered
pub fn emptyState(r: Rect, ic: u21, title: []const u8, body: []const u8) Rect {
    const cx = r.x + r.w / 2;
    const cy = r.y + r.h * 0.36;
    const box: Rect = .{ .x = cx - 30, .y = cy - 60, .w = 60, .h = 60 };
    ui.border(box, ui.radius_lg, 1, ui.colors.border);
    ui.icon(ic, box.center(), 26, ui.colors.text_muted);
    const tw = ui.measure(title, 16, .mono_bold);
    _ = ui.text(title, cx - tw / 2, cy + 22, 16, .mono_bold, ui.colors.text);
    const body_w = @min(r.w - 40, 440);
    const body_r: Rect = .{ .x = cx - body_w / 2, .y = cy + 52, .w = body_w, .h = 60 };
    const used = ui.paragraph(body, body_r, 13, .regular, ui.colors.text_muted, 1.5, false);
    centeredParagraph(body, body_r, 13, ui.colors.text_muted);
    return .{ .x = cx - 200, .y = body_r.y + used + 18, .w = 400, .h = 38 };
}

fn centeredParagraph(s: []const u8, r: Rect, size: f32, col: Rgba) void {
    var y = r.y;
    var start: usize = 0;
    while (start < s.len) {
        var end = start;
        var best = start;
        while (end < s.len) {
            var next = end;
            while (next < s.len and s[next] == ' ') next += 1;
            while (next < s.len and s[next] != ' ') next += 1;
            if (ui.measure(s[start..next], size, .regular) > r.w and best > start) break;
            best = next;
            end = next;
        }
        if (best == start) best = s.len;
        const line = std.mem.trim(u8, s[start..best], " ");
        const w = ui.measure(line, size, .regular);
        _ = ui.text(line, r.x + (r.w - w) / 2, y, size, .regular, col);
        y += size * 1.5;
        start = best;
        while (start < s.len and s[start] == ' ') start += 1;
    }
}

/// Notice with a colored edge, an icon, title, body and an action area on the right
pub fn banner(r: Rect, ic: u21, accent: Rgba, title: []const u8, body: []const u8) Rect {
    ui.rect(r, ui.radius_md, ui.colors.surface);
    ui.border(r, ui.radius_md, 1, ui.colors.border);
    ui.rect(.{ .x = r.x, .y = r.y, .w = 3, .h = r.h }, 0, accent);
    ui.icon(ic, .{ .x = r.x + 30, .y = r.y + r.h / 2 }, 18, accent);
    _ = ui.text(title, r.x + 54, r.y + r.h / 2 - 19, 14, .semibold, ui.colors.text);
    ui.label(body, .{ .x = r.x + 54, .y = r.y + r.h / 2 + 1, .w = r.w - 54 - 210, .h = 20 }, 13, .regular, ui.colors.text_muted, .left);
    return .{ .x = r.right() - 196, .y = r.y + (r.h - 36) / 2, .w = 180, .h = 36 };
}
