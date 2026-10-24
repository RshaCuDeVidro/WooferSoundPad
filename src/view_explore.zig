//! Explore: browse and search sound-button sites, preview, add in one click.

const std = @import("std");
const ui = @import("ui.zig");
const theme = @import("theme.zig");
const sys = @import("sys.zig");
const config = @import("config.zig");
const market = @import("market.zig");
const view = @import("view.zig");
const app_mod = @import("app.zig");
const App = app_mod.App;
const icons = ui.icons;
const Rect = ui.Rect;
const Rgba = ui.Rgba;

pub fn draw(a: *App, area: Rect) void {
    var r = area.insetXY(view.page_pad_x, 0);
    const e = &a.explore;
    if (!e.loaded) a.exploreQuery(.trending, "", null);

    // Header with the target workspace on the right
    const head = r.cutTop(96);
    _ = ui.text(a.t.explore_title, head.x, head.y + 26, 30, .display, ui.colors.text);
    _ = ui.text(a.t.explore_sub, head.x, head.y + 64, 14, .regular, ui.colors.text_muted);
    const target_r: Rect = .{ .x = head.right() - 220, .y = head.y + 40, .w = 220, .h = 38 };
    _ = ui.text(a.t.adding_to, target_r.x, target_r.y - 18, 12, .semibold, ui.colors.text_faint);
    var names: [64][]const u8 = undefined;
    const n_ws = @min(a.lib.workspaces.items.len, names.len);
    for (a.lib.workspaces.items[0..n_ws], 0..) |ws, i| names[i] = ws.name;
    if (e.target >= n_ws) e.target = a.ws;
    _ = ui.dropdown(ui.id("explore-target", 0), target_r, names[0..n_ws], &e.target);

    // Source + search
    var bar = r.cutTop(44);
    _ = r.cutTop(12);
    const seg_r = bar.cutLeft(360);
    const segs = [_]ui.Segment{
        .{ .label = "MyInstants", .icon = icons.zap },
        .{ .label = "SoundButtonsWorld", .icon = icons.radio },
    };
    if (ui.segmented(ui.id("explore-src", 0), seg_r, &segs, &e.source)) {
        a.cfg.explore_source = @fromBackingInt(@intCast(e.source));
        a.markConfig();
        a.stopPreview();
        const q = std.mem.trim(u8, e.search.text(), " ");
        if (q.len > 0) a.exploreQuery(.search, q, null) else a.exploreQuery(.trending, "", null);
    }
    _ = bar.cutLeft(12);
    const go_r = bar.cutRight(104);
    _ = bar.cutRight(8);
    const res = ui.textInput(ui.id("explore-search", 0), bar, &e.search, .{ .placeholder = a.t.search_buttons, .icon = icons.search });
    const go = ui.button(ui.id("explore-go", 0), go_r, a.t.search, .{ .style = .primary, .icon = icons.search });
    if (res.submitted or go) {
        const q = std.mem.trim(u8, e.search.text(), " ");
        if (q.len > 0) a.exploreQuery(.search, q, null) else a.exploreQuery(.trending, "", null);
    }

    // Category chips
    drawChips(a, &r);

    // Results
    const loading = e.task != null;
    if (e.items.items.len == 0 and !loading) {
        if (e.failed) {
            const actions = view.emptyState(r, icons.triangle_alert, a.t.load_failed, "");
            if (ui.button(ui.id("explore-retry", 0), actions.centered(150, 40), a.t.retry, .{ .icon = icons.refresh_cw, .style = .primary })) a.exploreLoadMore();
        } else if (e.page > 0) {
            _ = view.emptyState(r, icons.search, a.tf(a.t.no_results, .{e.queryText()}), "");
        }
        return;
    }

    const gap: f32 = 14;
    const card_min: f32 = 172;
    const card_h: f32 = 188;
    const inner_w = r.w - 10;
    const cols: usize = @max(1, @as(usize, @intFromFloat((inner_w + gap) / (card_min + gap))));
    const cols_f: f32 = @floatFromInt(cols);
    const card_w = (inner_w - gap * (cols_f - 1)) / cols_f;

    const scroll_key = ui.id("explore-scroll", e.generation);
    var top = ui.beginScroll(scroll_key, r);
    top += 4;
    const total = e.items.items.len + (if (loading) @as(usize, if (e.items.items.len == 0) 12 else cols * 2) else 0);
    var bottom = top;
    for (0..total) |i| {
        const cr: Rect = .{
            .x = r.x + @as(f32, @floatFromInt(i % cols)) * (card_w + gap),
            .y = top + @as(f32, @floatFromInt(i / cols)) * (card_h + gap),
            .w = card_w,
            .h = card_h,
        };
        bottom = cr.bottom();
        if (cr.bottom() < r.y - 20 or cr.y > r.bottom() + 20) continue;
        if (i < e.items.items.len) drawCard(a, &e.items.items[i], i, cr) else skeletonCard(cr);
    }
    var end_h: f32 = 30;
    if (!e.has_more and !loading and e.items.items.len > 0) {
        const msg = a.t.end_of_results;
        const w = ui.measure(msg, 13, .regular);
        _ = ui.text(msg, r.x + (r.w - w) / 2, bottom + 26, 13, .regular, ui.colors.text_faint);
        end_h = 70;
    } else if (e.failed) {
        if (ui.button(ui.id("explore-more-retry", 0), .{ .x = r.x + r.w / 2 - 75, .y = bottom + 20, .w = 150, .h = 38 }, a.t.retry, .{ .icon = icons.refresh_cw })) a.exploreLoadMore();
        end_h = 80;
    }
    const content_h = bottom - top + end_h;
    ui.endScroll(content_h);

    // Infinite scroll: fetch the next page when close to the bottom
    const info = ui.scrollInfo(scroll_key);
    if (e.has_more and !loading and !e.failed and info.offset + r.h > content_h - 400) a.exploreLoadMore();
}

fn drawChips(a: *App, r: *Rect) void {
    const e = &a.explore;
    var labels: [40][]const u8 = undefined;
    var n: usize = 0;
    labels[n] = a.t.trending;
    n += 1;
    if (e.source == 0) {
        for (market.myinstants_categories) |cat| {
            labels[n] = cat;
            n += 1;
        }
    } else {
        for (e.sbw_categories.items) |cat| {
            if (n == labels.len) break;
            labels[n] = cat;
            n += 1;
        }
    }

    const chip_h: f32 = 30;
    var x = r.x;
    var y = r.y;
    var rows: usize = 1;
    for (labels[0..n], 0..) |lbl, i| {
        const w = ui.measure(lbl, 13, .semibold) + 26;
        if (x + w > r.right()) {
            rows += 1;
            if (rows > 2) break;
            x = r.x;
            y += chip_h + 8;
        }
        const cr: Rect = .{ .x = x, .y = y, .w = w, .h = chip_h };
        x += w + 8;
        const selected = if (i == 0) e.kind == .trending else (e.kind == .category and e.category == i);
        const key = ui.idStr("chip", lbl);
        const in = ui.interact(key, cr);
        const sel_t = ui.anim(ui.sub(key, 1), if (selected) 1 else 0, 14);
        ui.rect(cr, chip_h / 2, Rgba.lerp(ui.colors.surface, ui.colors.accent, sel_t));
        if (sel_t < 0.99) ui.border(cr, chip_h / 2, 1, ui.colors.border.alpha(1 - sel_t));
        ui.rect(cr, chip_h / 2, ui.colors.text.alpha(in.hover_t * 0.06));
        const fg = Rgba.lerp(Rgba.lerp(ui.colors.text_muted, ui.colors.text, in.hover_t), ui.colors.accent_text, sel_t);
        // Capitalize the first letter of category names for display
        var cap_buf: [64]u8 = undefined;
        const shown = if (lbl.len > 0 and lbl.len <= cap_buf.len) blk: {
            @memcpy(cap_buf[0..lbl.len], lbl);
            cap_buf[0] = std.ascii.toUpper(cap_buf[0]);
            break :blk cap_buf[0..lbl.len];
        } else lbl;
        ui.label(shown, cr, 13, .semibold, fg, .center);
        if (in.clicked and !selected) {
            if (i == 0) a.exploreQuery(.trending, "", null) else a.exploreQuery(.category, lbl, i);
            e.search.clear();
        }
    }
    _ = r.cutTop(y - r.y + chip_h + 16);
}

fn skeletonCard(r: Rect) void {
    ui.skeleton(r, 16);
    ui.circle(.{ .x = r.x + r.w / 2, .y = r.y + 62 }, 36, ui.colors.surface_hover.alpha(0.6));
    ui.rect(.{ .x = r.x + 24, .y = r.y + 116, .w = r.w - 48, .h = 12 }, 6, ui.colors.surface_hover.alpha(0.6));
    ui.rect(.{ .x = r.x + 16, .y = r.bottom() - 48, .w = r.w - 32, .h = 32 }, ui.radius_md, ui.colors.surface_hover.alpha(0.4));
}

fn drawCard(a: *App, item: *const market.Item, index: usize, r: Rect) void {
    const e = &a.explore;
    const key = ui.idStr("mkt", item.audio_url);
    const appear = ui.animFrom(ui.sub(ui.sub(key, 0xA9), e.generation), 0, 1, 9);
    const delay_fade = std.math.clamp(appear * 1.4 - @as(f32, @floatFromInt(index % 12)) * 0.02, 0, 1);
    ui.pushAlpha(delay_fade);
    defer ui.popAlpha();
    const cr = r.offset(0, (1 - appear) * 12);
    const card_in = ui.interact(ui.sub(key, 3), cr);

    ui.shadow(cr.offset(0, 5), ui.radius_lg, 10 + card_in.hover_t * 8, ui.colors.shadow.alpha(0.45));
    ui.rect(cr, ui.radius_lg, Rgba.lerp(ui.colors.surface, ui.colors.surface_hover, card_in.hover_t * 0.6));
    ui.border(cr, ui.radius_lg, 1, ui.colors.border);

    // The big round sound button
    const col = Rgba.hex(item.color);
    const center: ui.Vec2 = .{ .x = cr.x + cr.w / 2, .y = cr.y + 62 };
    const btn_r: f32 = 34;
    const hit: Rect = .{ .x = center.x - btn_r, .y = center.y - btn_r, .w = btn_r * 2, .h = btn_r * 2 + 6 };
    const in = ui.interact(key, hit);
    const sink = in.press_t * 4;
    const progress = a.previewProgressFor(item.audio_url);
    const active = progress != null;
    if (in.hover_t > 0.01 or active) ui.glow(center, 110, col.alpha(0.25 * @max(in.hover_t, if (active) @as(f32, 1) else 0)));
    ui.circle(.{ .x = center.x, .y = center.y + 6 }, btn_r, col.shade(-0.45));
    ui.rectGradientV(.{ .x = center.x - btn_r, .y = center.y - btn_r + sink, .w = btn_r * 2, .h = btn_r * 2 }, btn_r, col.shade(0.25), col.shade(-0.1));
    ui.circle(.{ .x = center.x - 10, .y = center.y - 12 + sink }, 9, Rgba{ .r = 1, .g = 1, .b = 1, .a = 0.22 });
    const glyph_col = if (col.luminance() > 0.6) Rgba{ .r = 0.1, .g = 0.1, .b = 0.12 } else Rgba{ .r = 1, .g = 1, .b = 1 };
    if (progress) |p| {
        if (p < 0) {
            ui.spinner(.{ .x = center.x, .y = center.y + sink }, 12, glyph_col);
        } else {
            ui.icon(icons.square, .{ .x = center.x, .y = center.y + sink }, 18, glyph_col);
            ui.arc(center, btn_r + 7, 3, -90, -90 + 360 * p, ui.colors.accent);
        }
    } else {
        ui.icon(icons.play, .{ .x = center.x + 2, .y = center.y + sink }, 22, glyph_col.alpha(0.6 + 0.4 * in.hover_t));
    }
    if (in.clicked) a.previewItem(item.audio_url);
    if (in.hovered) ui.tooltip(key, a.t.preview);

    // Name
    ui.label(item.name, .{ .x = cr.x + 14, .y = cr.y + 108, .w = cr.w - 28, .h = 20 }, 13, .semibold, ui.colors.text, .center);
    if (card_in.hovered and ui.measure(item.name, 13, .semibold) > cr.w - 28) ui.tooltip(ui.sub(key, 3), item.name);

    // Actions
    const row: Rect = .{ .x = cr.x + 12, .y = cr.bottom() - 46, .w = cr.w - 24, .h = 34 };
    const added = a.explore.added.contains(item.audio_url);
    const add_r: Rect = .{ .x = row.x, .y = row.y, .w = row.w - 42, .h = row.h };
    if (added) {
        const t = ui.animFrom(ui.sub(key, 4), 0, 1, 12);
        ui.rect(add_r, ui.radius_md, ui.colors.success.alpha(0.14));
        const cx = add_r.x + add_r.w / 2;
        const lw = ui.measure(a.t.added, 13, .semibold);
        ui.icon(icons.check, .{ .x = cx - lw / 2 - 6, .y = add_r.y + add_r.h / 2 }, 15 * ui.easeOutBack(t), ui.colors.success);
        _ = ui.text(a.t.added, cx - lw / 2 + 6, add_r.y + 9, 13, .semibold, ui.colors.success);
    } else if (ui.button(ui.sub(key, 5), add_r, a.t.add, .{ .icon = icons.plus, .style = .subtle, .size = 13 })) {
        a.addMarketItem(item, e.target);
        const target_name = a.lib.workspaces.items[@min(e.target, a.lib.workspaces.items.len - 1)].name;
        ui.toast(.success, a.tf(a.t.added_toast, .{ item.name, target_name }));
    }
    if (ui.iconButton(ui.sub(key, 6), .{ .x = row.right() - 36, .y = row.y, .w = 36, .h = row.h }, icons.external_link, .{ .tooltip = a.t.open_page, .size = 15, .background = true, .radius = 9 })) {
        if (item.page_url.len > 0) sys.openUrl(item.page_url);
    }
}
