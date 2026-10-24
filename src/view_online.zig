//! YouTube, SoundCloud and direct links, powered by yt-dlp (no API keys).

const std = @import("std");
const ui = @import("ui.zig");
const sys = @import("sys.zig");
const tools = @import("tools.zig");
const jobs = @import("jobs.zig");
const view = @import("view.zig");
const app_mod = @import("app.zig");
const App = app_mod.App;
const icons = ui.icons;
const Rect = ui.Rect;
const Rgba = ui.Rgba;

pub fn draw(a: *App, area: Rect) void {
    var r = area.insetXY(view.page_pad_x, 0);
    const o = &a.online;
    _ = view.header(&r, a.t.online_title, a.t.online_sub);

    // Missing tools
    if (!tools.available(.ytdlp)) {
        toolBanner(a, &r, .ytdlp, icons.download, ui.colors.danger, a.t.ytdlp_missing_title, a.t.ytdlp_missing_body);
    }
    if (tools.available(.ytdlp)) {
        if (tools.ytdlpAgeDays()) |age| {
            if (age > tools.outdated_after_days) {
                toolBanner(a, &r, .ytdlp, icons.refresh_cw, ui.colors.warning, a.t.ytdlp_outdated_title, a.tf(a.t.ytdlp_outdated_body, .{age}));
            }
        }
    }
    if (!tools.available(.ffmpeg)) {
        toolBanner(a, &r, .ffmpeg, icons.wand_sparkles, ui.colors.warning, a.t.ffmpeg_missing_title, a.t.ffmpeg_missing_body);
    }
    if (o.platform == 0 and tools.available(.ytdlp) and !tools.available(.deno)) {
        toolBanner(a, &r, .deno, icons.zap, ui.colors.accent, a.t.deno_missing_title, a.t.deno_missing_body);
    }

    // Platform + query
    var bar = r.cutTop(44);
    _ = r.cutTop(18);
    const segs = [_]ui.Segment{
        .{ .label = a.t.platform_youtube, .icon = icons.youtube },
        .{ .label = a.t.platform_soundcloud, .icon = icons.cloud },
        .{ .label = a.t.platform_link, .icon = icons.link },
    };
    if (ui.segmented(ui.id("online-platform", 0), bar.cutLeft(390), &segs, &o.platform)) {
        if (o.platform < 2) {
            a.cfg.online_platform = @fromBackingInt(@intCast(o.platform));
            a.markConfig();
            if (o.searched) a.onlineSearch();
        }
    }
    _ = bar.cutLeft(12);
    const disabled = !tools.available(.ytdlp);
    if (o.platform == 2) {
        const go_r = bar.cutRight(130);
        _ = bar.cutRight(8);
        const res = ui.textInput(ui.id("online-link", 0), bar, &o.link, .{ .placeholder = a.t.paste_link, .icon = icons.link });
        const go = ui.button(ui.id("online-link-go", 0), go_r, a.t.download, .{ .style = .primary, .icon = icons.download, .disabled = disabled });
        const url = std.mem.trim(u8, o.link.text(), " ");
        if ((go or (res.submitted and !disabled)) and url.len > 0) a.openDownloadDialog(url, "", 0);
        drawLinkHelp(a, r);
        return;
    }
    const go_r = bar.cutRight(110);
    _ = bar.cutRight(8);
    const placeholder = if (o.platform == 0) a.t.search_youtube else a.t.search_soundcloud;
    const res = ui.textInput(ui.id("online-search", 0), bar, &o.search, .{ .placeholder = placeholder, .icon = icons.search });
    const go = ui.button(ui.id("online-go", 0), go_r, a.t.search, .{ .style = .primary, .icon = icons.search, .disabled = disabled, .loading = o.task != null });
    if ((go or (res.submitted and !disabled))) a.onlineSearch();

    // Results
    if (o.task != null) {
        for (0..6) |i| {
            const row: Rect = .{ .x = r.x, .y = r.y + @as(f32, @floatFromInt(i)) * 96, .w = r.w, .h = 84 };
            if (row.bottom() > r.bottom()) break;
            ui.skeleton(row, 14);
            ui.rect(.{ .x = row.x + 10, .y = row.y + 8, .w = 120, .h = 68 }, ui.radius_lg, ui.colors.surface_hover.alpha(0.6));
            ui.rect(.{ .x = row.x + 146, .y = row.y + 22, .w = row.w * 0.4, .h = 12 }, 6, ui.colors.surface_hover.alpha(0.6));
            ui.rect(.{ .x = row.x + 146, .y = row.y + 46, .w = row.w * 0.2, .h = 10 }, 5, ui.colors.surface_hover.alpha(0.5));
        }
        return;
    }
    if (o.failed) {
        _ = view.emptyState(r, icons.triangle_alert, a.t.search_failed, "");
        return;
    }
    if (o.results.items.len == 0) {
        if (o.searched) {
            _ = view.emptyState(r, icons.search, a.tf(a.t.no_results, .{o.search.text()}), "");
        } else {
            _ = view.emptyState(r, if (o.platform == 0) icons.youtube else icons.cloud, a.t.search_hint, a.t.online_sub);
        }
        return;
    }

    const row_h: f32 = 88;
    const scroll_key = ui.id("online-scroll", o.generation);
    var y = ui.beginScroll(scroll_key, r);
    const start_y = y;
    for (o.results.items, 0..) |*res_item, i| {
        const row: Rect = .{ .x = r.x, .y = y, .w = r.w - 10, .h = row_h };
        y += row_h + 10;
        if (row.bottom() < r.y - 10 or row.y > r.bottom() + 10) continue;
        drawResult(a, res_item, i, row);
    }
    ui.endScroll(y - start_y);
}

fn toolBanner(a: *App, r: *Rect, tool: tools.Tool, ic: u21, accent: Rgba, title: []const u8, body: []const u8) void {
    const b = r.cutTop(76);
    _ = r.cutTop(12);
    const action = view.banner(b, ic, accent, title, body);
    if (a.jobs.isInstalling(tool)) |job| {
        const p = job.progress.get();
        ui.progressBar(.{ .x = action.x, .y = action.y + 22, .w = action.w, .h = 6 }, p, accent);
        var pct_buf: [32]u8 = undefined;
        const txt = if (p >= 0) std.fmt.bufPrint(&pct_buf, "{s} {d:.0}%", .{ a.t.installing, p * 100 }) catch a.t.installing else a.t.installing;
        _ = ui.text(txt, action.x, action.y, 12, .semibold, ui.colors.text_muted);
    } else if (ui.button(ui.idStr("install", @tagName(tool)), action, a.tf(a.t.install_size, .{tools.downloadSizeMb(tool)}), .{ .icon = icons.download, .style = .primary })) {
        a.installTool(tool);
    }
}

fn drawLinkHelp(a: *App, r: Rect) void {
    const sites = [_]struct { name: []const u8, icon: u21 }{
        .{ .name = "YouTube", .icon = icons.youtube },
        .{ .name = "SoundCloud", .icon = icons.cloud },
        .{ .name = "TikTok", .icon = icons.music },
        .{ .name = "X / Twitter", .icon = icons.hash },
        .{ .name = "Instagram", .icon = icons.image },
        .{ .name = "Twitch", .icon = icons.monitor },
        .{ .name = "Reddit", .icon = icons.globe },
        .{ .name = "Bandcamp", .icon = icons.disc_3 },
    };
    _ = view.emptyState(.{ .x = r.x, .y = r.y, .w = r.w, .h = r.h * 0.75 }, icons.link, a.t.paste_link_title, a.t.paste_link);
    const chip_w: f32 = 132;
    const per_row: usize = @max(1, @min(sites.len, @as(usize, @intFromFloat((r.w + 10) / (chip_w + 10)))));
    const rows = (sites.len + per_row - 1) / per_row;
    const total_w = @as(f32, @floatFromInt(per_row)) * (chip_w + 10) - 10;
    const y0 = r.y + r.h * 0.75 - @as(f32, @floatFromInt(rows)) * 20;
    for (sites, 0..) |s, i| {
        const col = i % per_row;
        const row = i / per_row;
        const cr: Rect = .{ .x = r.x + (r.w - total_w) / 2 + @as(f32, @floatFromInt(col)) * (chip_w + 10), .y = y0 + @as(f32, @floatFromInt(row)) * 42, .w = chip_w, .h = 32 };
        const float = @sin(ui.time * 1.5 + @as(f32, @floatFromInt(i)) * 0.7) * 2;
        const fr = cr.offset(0, float);
        ui.rect(fr, ui.radius_lg, ui.colors.surface);
        ui.border(fr, ui.radius_lg, 1, ui.colors.border);
        ui.icon(s.icon, .{ .x = fr.x + 18, .y = fr.y + 16 }, 14, ui.colors.accent);
        ui.label(s.name, .{ .x = fr.x + 32, .y = fr.y, .w = fr.w - 40, .h = fr.h }, 12, .semibold, ui.colors.text_muted, .left);
    }
}

fn drawResult(a: *App, item: *const tools.MediaResult, index: usize, r: Rect) void {
    const key = ui.idStr("media", item.url);
    const appear = ui.animFrom(ui.sub(ui.sub(key, 0xA9), a.online.generation), 0, 1, 10);
    const t = std.math.clamp(appear * 1.5 - @as(f32, @floatFromInt(@min(index, 10))) * 0.04, 0, 1);
    ui.pushAlpha(t);
    defer ui.popAlpha();
    const row = r.offset((1 - t) * 20, 0);
    const in = ui.interact(key, row);
    ui.rect(row, ui.radius_lg, Rgba.lerp(ui.colors.surface, ui.colors.surface_hover, in.hover_t));
    ui.border(row, ui.radius_lg, 1, Rgba.lerp(ui.colors.border, ui.colors.accent.alpha(0.4), in.hover_t));

    // Thumbnail
    const thumb: Rect = .{ .x = row.x + 10, .y = row.y + 9, .w = 124, .h = 70 };
    if (jobs.thumbnail(item.thumbnail, 16.0 / 9.0)) |tex| {
        const fade = ui.animFrom(ui.sub(key, 7), 0, 1, 8);
        ui.rect(thumb, ui.radius_lg, ui.colors.surface_hover);
        ui.image(tex, thumb, ui.radius_lg, .{ .r = 1, .g = 1, .b = 1, .a = fade });
    } else {
        ui.skeleton(thumb, ui.radius_md);
        ui.icon(if (a.online.platform == 0) icons.youtube else icons.cloud, thumb.center(), 22, ui.colors.text_faint);
    }
    if (item.duration > 0) {
        var buf: [16]u8 = undefined;
        const d = app_mod.formatDuration(&buf, item.duration);
        const w = ui.measure(d, 11, .semibold) + 10;
        const br: Rect = .{ .x = thumb.right() - w - 5, .y = thumb.bottom() - 21, .w = w, .h = 17 };
        ui.rect(br, 5, Rgba{ .r = 0, .g = 0, .b = 0, .a = 0.75 });
        ui.label(d, br, 11, .semibold, Rgba{ .r = 1, .g = 1, .b = 1 }, .center);
    }

    // Text
    const text_x = thumb.right() + 16;
    const text_w = row.right() - text_x - 190;
    ui.label(item.title, .{ .x = text_x, .y = row.y + 20, .w = text_w, .h = 22 }, 15, .semibold, ui.colors.text, .left);
    ui.label(item.uploader, .{ .x = text_x, .y = row.y + 46, .w = text_w, .h = 20 }, 13, .regular, ui.colors.text_muted, .left);
    if (in.hovered and ui.measure(item.title, 15, .semibold) > text_w) ui.tooltip(key, item.title);

    // Actions
    const dl_r: Rect = .{ .x = row.right() - 172, .y = row.y + (row.h - 38) / 2, .w = 118, .h = 38 };
    if (ui.button(ui.sub(key, 1), dl_r, a.t.download, .{ .icon = icons.download, .style = .subtle }) or in.double_clicked) {
        a.openDownloadDialog(item.url, item.title, item.duration);
    }
    if (ui.iconButton(ui.sub(key, 2), .{ .x = row.right() - 46, .y = dl_r.y, .w = 38, .h = 38 }, icons.external_link, .{ .tooltip = a.t.open_page, .size = 16 })) {
        sys.openUrl(item.url);
    }
}
