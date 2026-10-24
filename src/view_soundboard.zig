//! The soundboard: the active workspace as a grid of animated pads.

const std = @import("std");
const c = @import("c");
const ui = @import("ui.zig");
const theme = @import("theme.zig");
const audio = @import("audio.zig");
const sys = @import("sys.zig");
const config = @import("config.zig");
const hotkeys = @import("hotkeys.zig");
const view = @import("view.zig");
const waves = @import("waves.zig");
const library = @import("library.zig");
const mixer = @import("view_mixer.zig");
const app_mod = @import("app.zig");
const App = app_mod.App;
const icons = ui.icons;
const Rect = ui.Rect;
const Rgba = ui.Rgba;

var shown_generation: u32 = std.math.maxInt(u32);
/// Where the first pad's "more" button sits (for devtools screenshots)
pub var debug_more_rect: Rect = .{};
var shown_at: f32 = 0;

pub fn rebuildView(a: *App) void {
    const ws = a.workspace();
    a.view.clearRetainingCapacity();
    const q = std.mem.trim(u8, a.search.text(), " ");
    for (ws.sounds.items, 0..) |s, i| {
        if (a.favorites_only and !s.favorite) continue;
        if (q.len > 0 and std.ascii.findIgnoreCase(s.name, q) == null) continue;
        a.view.append(sys.gpa, i) catch return;
    }
    const Ctx = struct {
        sounds: []const @import("library.zig").Sound,
        fn byName(ctx: @This(), x: usize, y: usize) bool {
            return std.ascii.lessThanIgnoreCase(ctx.sounds[x].name, ctx.sounds[y].name);
        }
        fn byRecent(ctx: @This(), x: usize, y: usize) bool {
            return ctx.sounds[x].added > ctx.sounds[y].added;
        }
        fn byPlays(ctx: @This(), x: usize, y: usize) bool {
            return ctx.sounds[x].plays > ctx.sounds[y].plays;
        }
    };
    const ctx: Ctx = .{ .sounds = ws.sounds.items };
    switch (a.cfg.sort) {
        .manual => {},
        .name => std.mem.sort(usize, a.view.items, ctx, Ctx.byName),
        .recent => std.mem.sort(usize, a.view.items, ctx, Ctx.byRecent),
        .most_played => std.mem.sort(usize, a.view.items, ctx, Ctx.byPlays),
    }
}

const side_w: f32 = 300;
pub const dock_h: f32 = 232;

pub fn draw(a: *App, area: Rect) void {
    rebuildView(a);
    var r = area.insetXY(view.page_pad_x, 0);
    const ws = a.workspace();
    const queue_t = ui.anim(ui.id("queue-open", 0), if (a.cfg.queue_open) 1 else 0, 16);
    const mixer_t = ui.anim(ui.id("mixer-open", 0), if (a.cfg.mixer_open) 1 else 0, 16);

    if (shown_generation != a.ws_generation) {
        shown_generation = a.ws_generation;
        shown_at = ui.time;
    }

    // ── Title row: workspace name, counts, record / stage ──
    const head = r.cutTop(62);
    const name_key = ui.id("ws-title", 0);
    const title_w = ui.text(ws.name, head.x, head.y + 22, 20, .display, ui.colors.text);
    const name_hover = ui.hoverArea(name_key, .{ .x = head.x, .y = head.y + 14, .w = title_w + 40, .h = 34 });
    if (name_hover > 0.02) {
        ui.pushAlpha(name_hover);
        if (ui.iconButton(ui.id("ws-rename", 0), .{ .x = head.x + title_w + 6, .y = head.y + 18, .w = 28, .h = 28 }, icons.pencil, .{ .tooltip = a.t.rename_workspace, .size = 13 })) {
            a.name_field.set(ws.name);
            a.dialog = .{ .rename_workspace = a.ws };
        }
        ui.popAlpha();
    }
    var with_hotkeys: usize = 0;
    var playing_n: usize = 0;
    for (ws.sounds.items) |s| {
        if (s.hotkey.len > 0) with_hotkeys += 1;
        if (audio.isPlaying(s.audio_id)) playing_n += 1;
    }
    const counts = a.tf(a.t.pads_count, .{ ws.sounds.items.len, with_hotkeys });
    _ = ui.text(counts, head.x + title_w + 44, head.y + 28, 11, .mono, ui.colors.text_faint);
    {
        var hr: Rect = .{ .x = head.x, .y = head.y + 16, .w = head.w, .h = 32 };
        const narrow = head.w < 760;
        const stage_r = hr.cutRight(if (narrow) 36 else 104);
        if (ui.button(ui.id("stage-open", 0), stage_r, if (narrow) "" else "STAGE", .{ .icon = icons.fullscreen, .style = .secondary, .size = 12, .tooltip = a.t.stage_mode_tip })) a.setStage(true);
        _ = hr.cutRight(8);
        const rec_r = hr.cutRight(if (narrow) 36 else 92);
        const recording = a.rec.state == .recording;
        if (ui.button(ui.id("rec-open", 0), rec_r, if (narrow) "" else "REC", .{ .icon = icons.circle_dot, .style = if (recording) .danger else .secondary, .size = 12, .tooltip = a.t.record_tip })) a.openRecorder();
        if (recording and @mod(ui.time, 1.0) < 0.6) ui.rect(.{ .x = rec_r.right() - 9, .y = rec_r.y + 5, .w = 5, .h = 5 }, 1, ui.colors.danger);
    }
    ui.rect(.{ .x = head.x, .y = head.bottom() - 1, .w = head.w, .h = 1 }, 0, ui.colors.border);
    _ = r.cutTop(12);

    // ── Mixer docked at the bottom, queue on the right ──
    if (mixer_t > 0.01) {
        const h = dock_h * ui.easeOutCubic(mixer_t);
        const dock = r.cutBottom(h + 16);
        ui.pushAlpha(mixer_t);
        mixer.drawDock(a, .{ .x = dock.x, .y = dock.y + 10, .w = dock.w, .h = dock_h }, true);
        ui.popAlpha();
    }
    if (queue_t > 0.01) {
        const panel_w = side_w * ui.easeOutCubic(queue_t);
        var panel = r.cutRight(panel_w);
        _ = r.cutRight(14 * queue_t);
        panel.w = side_w;
        panel.h -= 4;
        ui.pushAlpha(queue_t);
        drawQueue(a, panel);
        ui.popAlpha();
    }

    // ── Toolbar: search left, tools right ──
    var bar = r.cutTop(34);
    _ = r.cutTop(14);
    const compact = bar.w < 720;
    const tiny = bar.w < 520;
    const import_r = bar.cutRight(if (compact) 34 else 110);
    if (ui.button(ui.id("import", 0), import_r, if (compact) "" else a.t.import, .{ .icon = icons.upload, .style = .primary, .size = 12, .tooltip = if (compact) a.t.import else "Ctrl+O" })) a.openImportDialog();
    _ = bar.cutRight(8);
    const sort_items = [_][]const u8{ a.t.sort_manual, a.t.sort_name, a.t.sort_recent, a.t.sort_most_played };
    var sort_idx: usize = @backingInt(a.cfg.sort);
    if (tiny) {
        const sort_r = bar.cutRight(34);
        if (ui.iconButton(ui.id("sort-cycle", 0), sort_r, icons.arrow_up_down, .{ .tooltip = sort_items[sort_idx], .active = a.cfg.sort != .manual, .background = true })) {
            a.cfg.sort = @fromBackingInt(@intCast((sort_idx + 1) % sort_items.len));
            a.markConfig();
        }
    } else {
        const sort_r = bar.cutRight(if (compact) 140 else 160);
        if (ui.dropdown(ui.id("sort", 0), sort_r, &sort_items, &sort_idx)) {
            a.cfg.sort = @fromBackingInt(@intCast(sort_idx));
            a.markConfig();
        }
    }
    _ = bar.cutRight(12);
    // One joined group of view toggles
    const group = bar.cutRight(34 * 4);
    ui.rect(group, ui.radius_md, ui.colors.surface);
    ui.border(group, ui.radius_md, 1, ui.colors.border);
    const tools = [_]struct { key: u64, ic: u21, tip: []const u8, on: bool }{
        .{ .key = ui.id("fav-filter", 0), .ic = icons.star, .tip = a.t.favorites_only, .on = a.favorites_only },
        .{ .key = ui.id("random", 0), .ic = icons.dices, .tip = a.t.play_random, .on = false },
        .{ .key = ui.id("queue-toggle", 0), .ic = icons.list_music, .tip = a.t.queue, .on = a.cfg.queue_open or a.cfg.queue_mode },
        .{ .key = ui.id("mixer-toggle", 0), .ic = icons.sliders_vertical, .tip = a.t.mixer, .on = a.cfg.mixer_open },
    };
    for (tools, 0..) |tl, ti| {
        const cell: Rect = .{ .x = group.x + @as(f32, @floatFromInt(ti)) * 34, .y = group.y, .w = 34, .h = 34 };
        if (ti > 0) ui.rect(.{ .x = cell.x, .y = cell.y + 8, .w = 1, .h = 18 }, 0, ui.colors.border);
        if (ui.iconButton(tl.key, cell.inset(2), tl.ic, .{ .tooltip = tl.tip, .active = tl.on, .size = 15 })) switch (ti) {
            0 => a.favorites_only = !a.favorites_only,
            1 => a.playRandom(),
            2 => {
                a.cfg.queue_open = !a.cfg.queue_open;
                a.markConfig();
            },
            else => {
                a.cfg.mixer_open = !a.cfg.mixer_open;
                a.markConfig();
            },
        };
        if (tl.on) ui.rect(.{ .x = cell.x + 9, .y = cell.bottom() - 3, .w = 16, .h = 2 }, 1, ui.colors.accent);
    }
    // Small counters on the queue and mixer buttons
    const pending = queuePending(a);
    if (pending > 0) {
        var qb: [8]u8 = undefined;
        ui.label(std.fmt.bufPrint(&qb, "{d}", .{pending}) catch "", .{ .x = group.x + 2 * 34 + 20, .y = group.y + 1, .w = 12, .h = 12 }, 9, .mono_bold, ui.colors.accent, .center);
    }
    if (playing_n > 0 and !a.cfg.mixer_open) ui.rect(.{ .x = group.x + 3 * 34 + 25, .y = group.y + 5, .w = 5, .h = 5 }, 1, ui.colors.success);

    _ = bar.cutRight(12);
    const search_r = bar.cutLeft(@min(300, bar.w));
    if (a.focus_search) {
        ui.claimFocus(ui.id("pad-search", 0));
        a.focus_search = false;
    }
    if (search_r.w >= 40) _ = ui.textInput(ui.id("pad-search", 0), search_r, &a.search, .{ .placeholder = if (search_r.w < 150) "" else a.t.search_sounds, .icon = icons.search, .size = 13 });

    // ── Body ──
    if (ws.sounds.items.len == 0) {
        const actions = view.emptyState(r, icons.paw_print, a.t.empty_title, a.t.empty_body);
        var row = actions;
        const b1 = row.cutLeft(128);
        _ = row.cutLeft(8);
        const b2 = row.cutLeft(128);
        _ = row.cutLeft(8);
        const b3 = row.cutLeft(128);
        if (ui.button(ui.id("empty-import", 0), b1, a.t.import, .{ .icon = icons.upload, .style = .primary })) a.openImportDialog();
        if (ui.button(ui.id("empty-explore", 0), b2, a.t.empty_explore, .{ .icon = icons.compass })) a.goto(.explore);
        if (ui.button(ui.id("empty-online", 0), b3, a.t.empty_online, .{ .icon = icons.globe })) a.goto(.online);
        return;
    }
    if (a.view.items.len == 0) {
        _ = view.emptyState(r, icons.search, a.t.no_matches, "");
        return;
    }

    const dims: struct { w: f32, h: f32 } = switch (a.cfg.pad_size) {
        .small => .{ .w = 150, .h = 96 },
        .medium => .{ .w = 182, .h = 118 },
        .large => .{ .w = 226, .h = 148 },
    };
    const gap: f32 = 8;
    const grid = r;
    const inner_w = grid.w - 10; // room for the scrollbar
    const cols: usize = @max(1, @as(usize, @intFromFloat((inner_w + gap) / (dims.w + gap))));
    const cols_f: f32 = @floatFromInt(cols);
    const pad_w = (inner_w - gap * (cols_f - 1)) / cols_f;
    const pad_h = dims.h;

    const scroll_key = ui.id("pads-scroll", a.ws);
    const top = ui.beginScroll(scroll_key, grid);
    var max_y = top;
    for (a.view.items, 0..) |si, order| {
        const col = order % cols;
        const row = order / cols;
        const pr: Rect = .{
            .x = grid.x + @as(f32, @floatFromInt(col)) * (pad_w + gap),
            .y = top + @as(f32, @floatFromInt(row)) * (pad_h + gap),
            .w = pad_w,
            .h = pad_h,
        };
        max_y = pr.bottom();
        if (pr.bottom() < grid.y - 40 or pr.y > grid.bottom() + 40) continue;
        drawPad(a, si, order, pr);
    }
    ui.endScroll(max_y - top + 16);
}

/// One pad: a colored key with its number or hotkey, a status LED, the
/// waveform, the name and tags for whatever changes how it plays.
fn drawPad(a: *App, si: usize, order: usize, r: Rect) void {
    const ws = a.workspace();
    const s = &ws.sounds.items[si];
    const key = ui.id("pad", s.uid);
    const in = ui.interact(key, r);
    // Hover of the whole pad, children included: driving the "more" button
    // from `in.hover_t` made it flicker, since the button itself takes the
    // hover away from the pad as soon as it appears.
    const hover_t = ui.hoverArea(key, r);

    const delay = @as(f32, @floatFromInt(@min(order, 30))) * 0.012;
    const appear = std.math.clamp((ui.time - shown_at - delay) / 0.2, 0, 1);
    const playing = audio.isPlaying(s.audio_id);
    const paused = !playing and audio.isPaused(s.audio_id);
    const play_t = ui.anim(ui.sub(key, 40), if (playing) 1 else if (paused) 0.5 else 0, 14);
    const col = theme.padColor(s.color, ui.colors.accent);
    const pr = r.offset(0, in.press_t * 1.5);

    ui.pushAlpha(if (ui.animations) appear else 1);
    defer ui.popAlpha();

    // Body: dark tint of the pad color, lighting up while it plays
    const lvl = std.math.clamp(s.level * 1.4, 0, 1);
    const tint = 0.09 + 0.05 * hover_t + play_t * (0.16 + 0.08 * lvl) - in.press_t * 0.04;
    ui.rect(pr, ui.radius_lg, Rgba.lerp(ui.colors.surface, col, tint));
    ui.border(pr, ui.radius_lg, 1, Rgba.lerp(Rgba.lerp(ui.colors.border, col.alpha(0.5), hover_t), col, play_t));
    // Played part, as a darker veil that sweeps across
    if (play_t > 0.01) {
        const p = audio.progress(s.audio_id);
        ui.pushClip(.{ .x = pr.x, .y = pr.y, .w = pr.w * p, .h = pr.h });
        ui.rect(pr, ui.radius_lg, col.alpha(0.1 * play_t));
        ui.popClip();
    }

    // Ripples
    ui.pushClip(pr);
    for (a.ripples[0..a.ripple_count]) |rp| {
        if (rp.pad != si) continue;
        const age = ui.time - rp.born;
        if (age > 0.5) continue;
        const k = age / 0.5;
        ui.rect(pr, ui.radius_lg, col.alpha(0.22 * (1 - k)));
    }
    ui.popClip();

    if (a.cfg.show_waveforms) padWaveform(ws, s, pr, col, play_t, hover_t);

    // Top row: number or hotkey, tags, LED and the "more" button
    var hint_buf: [32]u8 = undefined;
    const hint: []const u8 = if (s.hotkey.len > 0)
        s.hotkey
    else if (a.cfg.number_keys_play and order < 10)
        std.fmt.bufPrint(&hint_buf, "{d:0>2}", .{(order + 1) % 10}) catch ""
    else
        std.fmt.bufPrint(&hint_buf, "{d:0>2}", .{order + 1}) catch "";
    const top_y = pr.y + 9;
    var tx = pr.x + 11;
    if (a.cfg.show_hotkeys_on_pads or s.hotkey.len == 0) {
        tx += ui.text(hint, tx, top_y, 11, if (s.hotkey.len > 0) .mono_bold else .mono, if (s.hotkey.len > 0) col else ui.colors.text_faint) + 8;
    }
    const menu_open = a.menu != null and a.menu.?.kind == .pad and a.menu.?.index == si;
    const more_t = if (menu_open) 1 else hover_t;
    const more_r: Rect = .{ .x = pr.right() - 32, .y = pr.y + 4, .w = 28, .h = 26 };
    if (order == 0) debug_more_rect = more_r;
    var tags_right = pr.right() - 14;
    // LED: on while playing, blinking while paused
    const led_on = playing or (paused and @mod(ui.time, 1.0) < 0.5);
    const led: Rect = .{ .x = pr.right() - 18, .y = top_y + 2, .w = 7, .h = 7 };
    if (more_t < 0.98) {
        ui.pushAlpha(1 - more_t);
        ui.rect(led, 1, if (led_on) col else ui.colors.text.alpha(0.12));
        ui.popAlpha();
    }
    tags_right = led.x - 8;
    if (more_t > 0.02) {
        ui.pushAlpha(more_t);
        if (ui.iconButton(ui.sub(key, 41), more_r, icons.ellipsis_vertical, .{ .size = 16, .tooltip = if (menu_open) null else a.t.more_options, .active = menu_open })) {
            // The press that reached this button already closed an open menu
            const just_dismissed = a.menu_dismissed_index == si and ui.time - a.menu_dismissed_at < 0.6;
            a.menu = if (menu_open or just_dismissed) null else .{ .kind = .pad, .index = si, .pos = .{ .x = more_r.right() - 240, .y = more_r.bottom() + 4 } };
        }
        ui.popAlpha();
    }
    // Tags, right to left: what changes how this pad plays
    var tag_buf: [6][12]u8 = undefined;
    var tags: [6][]const u8 = undefined;
    var n_tags: usize = 0;
    const n_fx = s.fx.active();
    if (n_fx > 0) {
        tags[n_tags] = std.fmt.bufPrint(&tag_buf[n_tags], "FX{d}", .{n_fx}) catch "FX";
        n_tags += 1;
    }
    const speed = if (s.speed > 0.01) s.speed else 1;
    if (speed != 1) {
        tags[n_tags] = std.fmt.bufPrint(&tag_buf[n_tags], "{d:.2}x", .{speed}) catch "";
        n_tags += 1;
    }
    if (s.loop) {
        tags[n_tags] = "LOOP";
        n_tags += 1;
    }
    if (s.trim_start > 0 or s.trim_end > 0) {
        tags[n_tags] = "CUT";
        n_tags += 1;
    }
    if (ws.fileUsers(s.file) > 1) {
        tags[n_tags] = "VAR";
        n_tags += 1;
    }
    if (a.queuePosition(s.uid)) |qi| {
        const is_current = a.queue.current != null and a.queue.current.? == qi;
        tags[n_tags] = if (is_current) "Q>" else (std.fmt.bufPrint(&tag_buf[n_tags], "Q{d}", .{qi - a.queue.current.?}) catch "Q");
        n_tags += 1;
    }
    for (tags[0..n_tags]) |tg| {
        const w = ui.measure(tg, 9, .mono_bold) + 8;
        if (tags_right - w < tx) break;
        const tr: Rect = .{ .x = tags_right - w, .y = top_y - 1, .w = w, .h = 14 };
        ui.border(tr, 2, 1, col.alpha(0.55));
        ui.label(tg, tr, 9, .mono_bold, col, .center);
        tags_right -= w + 4;
    }

    // Name and time
    const name_size: f32 = if (pr.h > 130) 15 else 13;
    const name_y = pr.bottom() - name_size - 14;
    const len = audio.length(s.audio_id) / speed;
    var dur_buf: [24]u8 = undefined;
    const dur: []const u8 = if (len > 0) blk: {
        if (playing or paused) break :blk app_mod.formatDuration(&dur_buf, len * (1 - audio.progress(s.audio_id)));
        break :blk app_mod.formatDuration(&dur_buf, len);
    } else if (s.audio_id < 0) "ERR" else "";
    const dur_w = ui.measure(dur, 11, .mono) + 4;
    if (s.favorite) ui.icon(icons.star, .{ .x = pr.x + 17, .y = name_y + name_size / 2 + 1 }, 11, ui.colors.warning);
    const name_x = pr.x + (if (s.favorite) @as(f32, 28) else 11);
    ui.label(s.name, .{ .x = name_x, .y = name_y - 2, .w = pr.right() - 12 - dur_w - name_x, .h = name_size + 4 }, name_size, .semibold, ui.colors.text, .left);
    ui.label(dur, .{ .x = pr.right() - 10 - dur_w, .y = name_y - 1, .w = dur_w, .h = name_size + 4 }, 11, .mono, if (s.audio_id < 0) ui.colors.danger else if (playing) col else ui.colors.text_faint, .right);

    // Progress line along the bottom edge
    if (play_t > 0.01) {
        const p = audio.progress(s.audio_id);
        ui.rect(.{ .x = pr.x + 1, .y = pr.bottom() - 3, .w = (pr.w - 2) * p, .h = 2 }, 0, col.alpha(play_t));
    }

    // Input: Shift+click always queues
    if (in.clicked) {
        const shift = c.IsKeyDown(c.KEY_LEFT_SHIFT) or c.IsKeyDown(c.KEY_RIGHT_SHIFT);
        if (shift) a.enqueue(si) else a.playSound(si);
        a.addRipple(si, ui.mouse.x, ui.mouse.y);
    }
    if (in.right_clicked) a.menu = .{ .kind = .pad, .index = si, .pos = ui.mouse };
    if (in.hovered and s.source.len > 0) ui.tooltip(key, s.name);
}

pub fn drawPadMenu(a: *App, m: app_mod.MenuState) void {
    const ws = a.workspace();
    if (m.index >= ws.sounds.items.len) {
        a.menu = null;
        return;
    }
    const s = &ws.sounds.items[m.index];
    var moves: usize = 0;
    for (a.lib.workspaces.items, 0..) |_, i| {
        if (i != a.ws and moves < 5) moves += 1;
    }
    const playing = audio.isPlaying(s.audio_id);
    const paused = audio.isPaused(s.audio_id);
    const extra: usize = if (playing or paused) 1 else 0;
    // header + play + (pause) + queue | edit, effects, variant, hotkey | favorite, duplicate, folder | (moves) | delete
    const rows = 1 + 2 + extra + 4 + 3 + (if (moves > 0) moves + 1 else 0) + 1;
    const seps: usize = 3 + (if (moves > 0) @as(usize, 1) else 0);
    var menu = ui.beginMenuW(ui.id("pad-menu", m.index), m.pos, rows, seps, 240);
    var close = false;
    menu.header(s.name);
    if (menu.itemHint(icons.play, a.t.play, s.hotkey, false)) {
        a.playNow(m.index);
        close = true;
    }
    if (playing and menu.item(icons.pause, a.t.pause, false)) {
        audio.pause(s.audio_id);
        close = true;
    } else if (paused and menu.item(icons.play, a.t.resume_play, false)) {
        audio.@"resume"(s.audio_id);
        close = true;
    }
    if (menu.itemHint(icons.list_plus, a.t.add_to_queue, "Shift+Click", false)) {
        a.enqueue(m.index);
        close = true;
    }
    menu.separator();
    if (menu.item(icons.scissors, a.t.edit_and_trim, false)) {
        a.openEditor(m.index);
        close = true;
    }
    var fx_buf: [8]u8 = undefined;
    const n_fx = s.fx.active();
    if (menu.itemHint(icons.wand_sparkles, a.t.effects, if (n_fx > 0) std.fmt.bufPrint(&fx_buf, "{d}", .{n_fx}) catch "" else "", false)) {
        a.openEditor(m.index);
        a.editor.tab = .effects;
        close = true;
    }
    if (menu.item(icons.git_fork, a.t.create_variant, false)) {
        a.createVariant(m.index, null);
        close = true;
    }
    if (menu.itemHint(icons.keyboard, a.t.set_hotkey, s.hotkey, false)) {
        a.openEditor(m.index);
        a.editor.tab = .pad;
        a.capture = .pad;
        close = true;
    }
    menu.separator();
    if (menu.item(icons.star, if (s.favorite) a.t.unfavorite else a.t.favorite, false)) {
        s.favorite = !s.favorite;
        a.lib.save(a.ws) catch {};
        close = true;
    }
    if (menu.item(icons.copy, a.t.duplicate, false)) {
        a.duplicateSound(m.index);
        close = true;
    }
    if (menu.item(icons.folder_open, a.t.show_in_folder, false)) {
        const p = sys.join(&.{ ws.dir, s.file }) catch null;
        if (p) |path| {
            sys.revealFile(path);
            sys.gpa.free(path);
        }
        close = true;
    }
    if (moves > 0) {
        menu.separator();
        menu.header(a.t.move_to_header);
        var shown: usize = 0;
        for (a.lib.workspaces.items, 0..) |other, i| {
            if (i == a.ws or shown >= 5) continue;
            shown += 1;
            if (menu.item(icons.folder, other.name, false)) {
                a.moveSound(m.index, i);
                close = true;
                break;
            }
        }
    }
    menu.separator();
    if (menu.item(icons.trash_2, a.t.delete, true)) {
        a.dialog = .{ .delete_sound = m.index };
        close = true;
    }
    if (ui.endMenu(&menu)) {
        a.menu = null;
        a.menu_dismissed_index = m.index;
        a.menu_dismissed_at = ui.time;
    }
    if (close) a.menu = null;
}

/// Waveform across the middle of the pad; the played part lights up
fn padWaveform(ws: *const library.Workspace, s: *const library.Sound, pr: Rect, col: Rgba, play_t: f32, hover_t: f32) void {
    var path_buf: [1024]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "{s}{c}{s}", .{ ws.dir, std.fs.path.sep, s.file }) catch return;
    const wave = waves.get(path, 160) orelse return;
    const appear = ui.animFrom(ui.idStr("pad-wave", s.file), 0, 1, 8);
    const n = wave.peaks.len;
    const full = @max(wave.duration, 0.001);
    const from: usize = @intFromFloat(std.math.clamp(s.trim_start / full, 0, 1) * @as(f32, @floatFromInt(n)));
    const to_f = if (s.trim_end > 0) std.math.clamp(s.trim_end / full, 0, 1) else 1;
    const to: usize = @max(from + 1, @as(usize, @intFromFloat(to_f * @as(f32, @floatFromInt(n)))));
    const peaks = wave.peaks[@min(from, n - 1)..@min(to, n)];

    const area: Rect = .{ .x = pr.x + 11, .y = pr.y + 30, .w = pr.w - 22, .h = pr.h - 30 - 34 };
    if (area.h < 8) return;
    const bars: usize = @intFromFloat(@max(8, area.w / 3));
    const step = area.w / @as(f32, @floatFromInt(bars));
    const mid = area.y + area.h / 2;
    const progress = if (play_t > 0.01) audio.progress(s.audio_id) else -1;
    for (0..bars) |b| {
        const p0 = b * peaks.len / bars;
        const p1 = @max(p0 + 1, (b + 1) * peaks.len / bars);
        var v: f32 = 0;
        for (peaks[p0..@min(p1, peaks.len)]) |p| v = @max(v, p);
        const h = @max(1, v * area.h * appear);
        const x = area.x + @as(f32, @floatFromInt(b)) * step;
        const played = progress >= 0 and (@as(f32, @floatFromInt(b)) + 0.5) / @as(f32, @floatFromInt(bars)) <= progress;
        const alpha: f32 = if (played) 0.95 else 0.28 + 0.12 * hover_t + 0.1 * play_t;
        ui.rect(.{ .x = x, .y = mid - h / 2, .w = @max(1, step - 1), .h = h }, 0, col.alpha(alpha));
    }
}

fn queuePending(a: *App) usize {
    const total = a.queue.items.items.len;
    const done = if (a.queue.current) |cur| cur else total;
    return total - @min(done, total);
}

// ── Queue panel ─────────────────────────────────────────────────────────────

const queue_row_h: f32 = 48;

fn drawQueue(a: *App, r: Rect) void {
    const q = &a.queue;
    const ws = a.workspace();
    ui.rect(r, ui.radius_lg, ui.colors.sidebar);
    ui.border(r, ui.radius_lg, 1, ui.colors.border);
    var in_r = r.insetXY(12, 0);

    // Title
    const head = in_r.cutTop(34);
    _ = ui.text("QUEUE", head.x + 2, head.y + 11, 11, .mono_bold, ui.colors.text);
    var cnt_buf: [16]u8 = undefined;
    _ = ui.text(std.fmt.bufPrint(&cnt_buf, "{d}", .{q.items.items.len}) catch "", head.x + 54, head.y + 11, 11, .mono, ui.colors.text_faint);
    ui.rect(.{ .x = r.x, .y = head.bottom(), .w = r.w, .h = 1 }, 0, ui.colors.border);
    if (ui.iconButton(ui.id("q-close", 0), .{ .x = head.right() - 26, .y = head.y + 5, .w = 26, .h = 24 }, icons.x, .{ .size = 13, .tooltip = a.t.close })) {
        a.cfg.queue_open = false;
        a.markConfig();
    }

    // Transport
    const ctl = in_r.cutTop(48);
    const running = q.current != null;
    const cur_id = if (q.current) |qi| (if (a.queueSound(qi)) |si| ws.sounds.items[si].audio_id else -1) else -1;
    const cur_paused = cur_id >= 0 and audio.isPaused(cur_id);
    const has_items = q.items.items.len > 0;
    var x = ctl.x;
    if (ui.iconButton(ui.id("q-prev", 0), .{ .x = x, .y = ctl.y + 6, .w = 36, .h = 36 }, icons.skip_back, .{ .size = 17, .disabled = !running, .tooltip = a.t.previous })) a.queuePrev();
    x += 40;
    const play_r: Rect = .{ .x = x, .y = ctl.y + 2, .w = 44, .h = 44 };
    {
        const in = ui.interactOpts(ui.id("q-play", 0), play_r, has_items);
        const pr = play_r.inset(4).offset(0, in.press_t);
        ui.pushAlpha(if (has_items) 1 else 0.4);
        ui.rect(pr, ui.radius_md, ui.colors.accent.shade(in.hover_t * 0.1));
        const ic = if (running and !cur_paused) icons.pause else icons.play;
        ui.icon(ic, .{ .x = pr.center().x + (if (ic == icons.play) @as(f32, 1.5) else 0), .y = pr.center().y }, 19, ui.colors.accent_text);
        ui.popAlpha();
        if (in.hovered) ui.tooltip(ui.id("q-play", 0), if (running and !cur_paused) a.t.pause else a.t.play);
        if (in.clicked) {
            if (!running) {
                a.queuePlayAt(0);
            } else if (cur_paused) {
                audio.@"resume"(cur_id);
            } else {
                audio.pause(cur_id);
            }
        }
    }
    x += 48;
    if (ui.iconButton(ui.id("q-next", 0), .{ .x = x, .y = ctl.y + 6, .w = 36, .h = 36 }, icons.skip_forward, .{ .size = 17, .disabled = !has_items, .tooltip = a.t.next })) a.queueNext();
    var rx = ctl.right();
    rx -= 34;
    if (ui.iconButton(ui.id("q-clear", 0), .{ .x = rx, .y = ctl.y + 7, .w = 34, .h = 34 }, icons.list_x, .{ .size = 16, .disabled = !has_items, .tooltip = a.t.clear_queue })) a.queueClear();
    rx -= 38;
    if (ui.iconButton(ui.id("q-repeat", 0), .{ .x = rx, .y = ctl.y + 7, .w = 34, .h = 34 }, icons.repeat, .{ .size = 16, .active = a.cfg.queue_repeat, .tooltip = a.t.repeat_queue })) {
        a.cfg.queue_repeat = !a.cfg.queue_repeat;
        a.markConfig();
    }
    rx -= 38;
    if (ui.iconButton(ui.id("q-shuffle", 0), .{ .x = rx, .y = ctl.y + 7, .w = 34, .h = 34 }, icons.shuffle, .{ .size = 16, .disabled = q.items.items.len < 2, .tooltip = a.t.shuffle })) a.queueShuffle();

    // Queue mode switch
    const mode = in_r.cutTop(46);
    ui.rect(.{ .x = mode.x, .y = mode.y + 4, .w = mode.w, .h = 38 }, ui.radius_md, ui.colors.surface);
    ui.icon(icons.mouse_pointer_click, .{ .x = mode.x + 18, .y = mode.y + 23 }, 14, if (a.cfg.queue_mode) ui.colors.accent else ui.colors.text_faint);
    ui.label(a.t.queue_mode, .{ .x = mode.x + 34, .y = mode.y + 4, .w = mode.w - 90, .h = 38 }, 12, .semibold, ui.colors.text_muted, .left);
    if (ui.toggle(ui.id("q-mode", 0), .{ .x = mode.right() - 52, .y = mode.y + 4, .w = 46, .h = 38 }, &a.cfg.queue_mode)) a.markConfig();
    _ = in_r.cutTop(8);

    // Footer: time left
    const foot = in_r.cutBottom(34);
    var left: f32 = 0;
    const first = q.current orelse q.items.items.len;
    for (q.items.items[@min(first, q.items.items.len)..], first..) |_, qi| {
        const si = a.queueSound(qi) orelse continue;
        const snd = &ws.sounds.items[si];
        const sp = if (snd.speed > 0.01) snd.speed else 1;
        const len = audio.length(snd.audio_id) / sp;
        left += if (q.current != null and qi == q.current.?) len * (1 - audio.progress(snd.audio_id)) else len;
    }
    if (left > 0) {
        var t_buf: [16]u8 = undefined;
        ui.label(a.tf(a.t.queue_left, .{app_mod.formatDuration(&t_buf, left)}), foot, 11, .mono, ui.colors.text_faint, .center);
    }

    // List
    if (!has_items) {
        const cy = in_r.y + in_r.h * 0.32;
        ui.icon(icons.list_plus, .{ .x = in_r.x + in_r.w / 2, .y = cy }, 24, ui.colors.text_faint);
        const tw2 = ui.measure(a.t.queue_empty, 14, .semibold);
        _ = ui.text(a.t.queue_empty, in_r.x + (in_r.w - tw2) / 2, cy + 44, 14, .semibold, ui.colors.text);
        _ = ui.paragraph(a.t.queue_empty_hint, .{ .x = in_r.x + 10, .y = cy + 70, .w = in_r.w - 20, .h = 80 }, 12, .regular, ui.colors.text_muted, 1.5, true);
        return;
    }

    // Finish a drag before drawing, so rows land where they were dropped
    const scroll_key = ui.id("q-scroll", 0);
    var just_dropped = false;
    if (q.drag) |from| {
        if (!ui.mouseDown()) {
            const target = dropIndex(a, in_r, scroll_key);
            a.queueMove(from, target);
            q.drag = null;
            just_dropped = true;
        }
    }

    var y = ui.beginScroll(scroll_key, in_r);
    const top = y;
    const drop_at: ?usize = if (q.drag != null) dropIndex(a, in_r, scroll_key) else null;
    for (q.items.items, 0..) |uid, qi| {
        const row: Rect = .{ .x = in_r.x, .y = y, .w = in_r.w - 6, .h = queue_row_h - 4 };
        y += queue_row_h;
        if (drop_at) |d| {
            if (d == qi and q.drag.? > qi) ui.rect(.{ .x = row.x + 6, .y = row.y - 3, .w = row.w - 12, .h = 2 }, 1, ui.colors.accent);
            if (d == qi and q.drag.? < qi) ui.rect(.{ .x = row.x + 6, .y = row.bottom() + 1, .w = row.w - 12, .h = 2 }, 1, ui.colors.accent);
        }
        if (q.drag != null and q.drag.? == qi) {
            // Ghost following the mouse is drawn after the list
            ui.rect(row, ui.radius_lg, ui.colors.text.alpha(0.04));
            continue;
        }
        queueRow(a, qi, uid, row, just_dropped);
    }
    ui.endScroll(y - top + 8);

    if (q.drag) |qi| {
        const ghost: Rect = .{ .x = in_r.x - 4, .y = ui.mouse.y - q.drag_offset, .w = in_r.w + 2, .h = queue_row_h - 4 };
        ui.shadow(ghost.offset(0, 4), ui.radius_md, ui.radius_lg, ui.colors.shadow);
        queueRow(a, qi, q.items.items[qi], ghost, true);
    }
}

fn dropIndex(a: *App, list: Rect, scroll_key: u64) usize {
    const off = ui.scrollInfo(scroll_key).offset;
    const rel = ui.mouse.y - list.y + off;
    const n = a.queue.items.items.len;
    if (rel < 0) return 0;
    return @min(n - 1, @as(usize, @intFromFloat(rel / queue_row_h)));
}

fn queueRow(a: *App, qi: usize, uid: u32, row: Rect, inert: bool) void {
    const q = &a.queue;
    const ws = a.workspace();
    const si = a.queueSound(qi);
    const snd: ?*library.Sound = if (si) |i| &ws.sounds.items[i] else null;
    const key = ui.id("q-row", uid) +% qi;
    const in = if (inert) ui.Interaction{} else ui.interact(key, row);
    const is_current = q.current != null and q.current.? == qi;
    const played = q.current != null and qi < q.current.?;
    const col = if (snd) |sp| theme.padColor(sp.color, ui.colors.accent) else ui.colors.text_faint;

    // Start dragging once the mouse moves a little
    if (in.pressed) q.drag_offset = ui.mouse.y - row.y;
    if (in.held and q.drag == null and @abs(ui.mouse.y - (row.y + q.drag_offset)) > 5) q.drag = qi;

    ui.pushAlpha(if (played) 0.5 else 1);
    defer ui.popAlpha();
    const cur_t = ui.anim(ui.sub(key, 3), if (is_current) 1 else 0, 12);
    ui.rect(row, ui.radius_sm, Rgba.lerp(ui.colors.surface.alpha(0), ui.colors.surface, @max(in.hover_t, inertAlpha(inert))));
    if (cur_t > 0.01) {
        ui.rect(row, ui.radius_sm, col.alpha(0.1 * cur_t));
        ui.rect(.{ .x = row.x, .y = row.y + 6, .w = 2, .h = row.h - 12 }, 1, col.alpha(cur_t));
    }

    // Number, or bars while playing
    const lead: ui.Vec2 = .{ .x = row.x + 18, .y = row.y + row.h / 2 };
    const playing = snd != null and audio.isPlaying(snd.?.audio_id);
    if (is_current and playing) {
        for (0..3) |i| {
            const fi: f32 = @floatFromInt(i);
            const wave = 0.5 + 0.5 * @sin(ui.time * (8 + fi * 2.7) + fi * 2.1);
            const h = 4 + 9 * wave;
            ui.rect(.{ .x = lead.x - 6 + fi * 4.5, .y = lead.y + 6 - h, .w = 3, .h = h }, 1.5, col);
        }
    } else if (in.hover_t > 0.5 and !inert) {
        ui.icon(icons.grip_vertical, lead, 14, ui.colors.text_faint);
    } else {
        var nb: [8]u8 = undefined;
        ui.label(std.fmt.bufPrint(&nb, "{d:0>2}", .{qi + 1}) catch "", .{ .x = lead.x - 12, .y = row.y, .w = 24, .h = row.h }, 11, .mono, if (is_current) col else ui.colors.text_faint, .center);
    }

    const name = if (snd) |sp| sp.name else a.t.queue_missing;
    ui.label(name, .{ .x = row.x + 36, .y = row.y + 6, .w = row.w - 90, .h = 18 }, 13, if (is_current) .semibold else .regular, if (snd != null) ui.colors.text else ui.colors.text_faint, .left);
    if (snd) |sp| {
        const speed = if (sp.speed > 0.01) sp.speed else 1;
        var d_buf: [16]u8 = undefined;
        _ = ui.text(app_mod.formatDuration(&d_buf, audio.length(sp.audio_id) / speed), row.x + 36, row.y + 25, 10, .mono, ui.colors.text_faint);
        if (is_current) ui.progressBar(.{ .x = row.x + 36, .y = row.bottom() - 6, .w = row.w - 50, .h = 3 }, audio.progress(sp.audio_id), col);
    }

    // Remove on hover
    if (!inert and in.hover_t > 0.05) {
        ui.pushAlpha(in.hover_t);
        if (ui.iconButton(ui.sub(key, 4), .{ .x = row.right() - 34, .y = row.y + (row.h - 28) / 2, .w = 28, .h = 28 }, icons.x, .{ .size = 14, .tooltip = a.t.remove })) {
            ui.popAlpha();
            a.queueRemove(qi);
            return;
        }
        ui.popAlpha();
    }
    if (in.clicked and q.drag == null) {
        if (is_current) a.queueStop();
        a.queuePlayAt(qi);
    }
}

fn inertAlpha(inert: bool) f32 {
    return if (inert) 1 else 0;
}
