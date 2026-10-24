//! Statistics: totals, the meme ranking, plays per day and the play history.

const std = @import("std");
const ui = @import("ui.zig");
const theme = @import("theme.zig");
const view = @import("view.zig");
const stats = @import("stats.zig");
const library = @import("library.zig");
const app_mod = @import("app.zig");
const App = app_mod.App;
const icons = ui.icons;
const Rect = ui.Rect;
const Rgba = ui.Rgba;

const Ranked = struct {
    ws: usize,
    si: usize,
    plays: u32,
    seconds: f32,
};

const max_ranked = 2048;
var ranked_buf: [max_ranked]Ranked = undefined;

fn collect(a: *App) []Ranked {
    var n: usize = 0;
    for (a.lib.workspaces.items, 0..) |ws, wi| {
        if (!a.cfg.stats_all_workspaces and wi != a.ws) continue;
        for (ws.sounds.items, 0..) |s, si| {
            if (n == max_ranked) break;
            ranked_buf[n] = .{ .ws = wi, .si = si, .plays = s.plays, .seconds = s.play_seconds };
            n += 1;
        }
    }
    const items = ranked_buf[0..n];
    std.mem.sort(Ranked, items, {}, struct {
        fn lt(_: void, x: Ranked, y: Ranked) bool {
            if (x.plays != y.plays) return x.plays > y.plays;
            return x.seconds > y.seconds;
        }
    }.lt);
    return items;
}

fn fmtLong(buf: []u8, seconds: f32) []const u8 {
    const total: u64 = @intFromFloat(@max(0, seconds));
    const h = total / 3600;
    const m = (total / 60) % 60;
    const s = total % 60;
    if (h > 0) return std.fmt.bufPrint(buf, "{d}h {d:0>2}min", .{ h, m }) catch "";
    if (m > 0) return std.fmt.bufPrint(buf, "{d}min {d:0>2}s", .{ m, s }) catch "";
    return std.fmt.bufPrint(buf, "{d}s", .{s}) catch "";
}

pub fn draw(a: *App, area: Rect) void {
    var page = area.insetXY(view.page_pad_x, 0);
    const actions = view.header(&page, a.t.stats_title, a.t.stats_subtitle);

    // Scope + clear
    const seg_w: f32 = 300;
    var scope: usize = if (a.cfg.stats_all_workspaces) 0 else 1;
    const segs = [_]ui.Segment{ .{ .label = a.t.stats_all_ws, .icon = icons.layers }, .{ .label = a.t.stats_this_ws, .icon = icons.folder } };
    if (ui.segmented(ui.id("stats-scope", 0), .{ .x = actions.right() - seg_w - 150, .y = actions.y, .w = seg_w, .h = 40 }, &segs, &scope)) {
        a.cfg.stats_all_workspaces = scope == 0;
        a.markConfig();
    }
    if (ui.button(ui.id("stats-clear", 0), .{ .x = actions.right() - 140, .y = actions.y, .w = 140, .h = 40 }, a.t.stats_clear, .{ .icon = icons.eraser, .style = .ghost, .size = 13, .tooltip = a.t.stats_clear_tip, .disabled = stats.history.items.len == 0 })) {
        stats.clear();
        ui.toast(.info, a.t.stats_cleared);
    }

    const ranked = collect(a);
    var total_plays: u64 = 0;
    var total_secs: f32 = 0;
    var used: usize = 0;
    for (ranked) |r| {
        total_plays += r.plays;
        total_secs += r.seconds;
        if (r.plays > 0) used += 1;
    }

    var y = ui.beginScroll(ui.id("stats-scroll", 0), page);
    const top = y;
    const w = page.w - 12;
    const x = page.x;

    // ── Stat tiles ──
    {
        const gap: f32 = 14;
        const tw = (w - gap * 3) / 4;
        var b1: [32]u8 = undefined;
        var b2: [32]u8 = undefined;
        var b3: [32]u8 = undefined;
        var b4: [48]u8 = undefined;
        var b5: [48]u8 = undefined;
        const today = stats.today();
        const streak = stats.streak();
        tile(.{ .x = x, .y = y, .w = tw, .h = 112 }, icons.circle_play, a.t.stats_total_plays, std.fmt.bufPrint(&b1, "{d}", .{total_plays}) catch "", "", ui.colors.accent);
        tile(.{ .x = x + (tw + gap), .y = y, .w = tw, .h = 112 }, icons.clock, a.t.stats_total_time, fmtLong(&b2, total_secs), "", ui.colors.accent2);
        tile(.{ .x = x + (tw + gap) * 2, .y = y, .w = tw, .h = 112 }, icons.calendar, a.t.stats_today, std.fmt.bufPrint(&b3, "{d}", .{stats.playsOn(today)}) catch "", if (streak > 1) a.tf(a.t.stats_streak, .{streak}) else a.tf(a.t.stats_today_time, .{fmtLong(&b4, stats.secondsOn(today))}), ui.colors.success);
        tile(.{ .x = x + (tw + gap) * 3, .y = y, .w = tw, .h = 112 }, icons.music_2, a.t.stats_sounds_used, std.fmt.bufPrint(&b5, "{d} / {d}", .{ used, ranked.len }) catch "", "", ui.colors.warning);
        y += 112 + 14;
    }

    // ── Ranking + chart ──
    const left_w = w * 0.56;
    const right_w = w - left_w - 18;
    const rank_h: f32 = 460;
    ranking(a, .{ .x = x, .y = y, .w = left_w, .h = rank_h }, ranked);
    daysChart(a, .{ .x = x + left_w + 18, .y = y, .w = right_w, .h = rank_h });
    y += rank_h + 14;

    // ── History ──
    const hist_h = historyList(a, .{ .x = x, .y = y, .w = w, .h = 0 });
    y += hist_h + 30;

    ui.endScroll(y - top);
}

fn card(r: Rect, ic: u21, title: []const u8) Rect {
    _ = ic;
    ui.rect(r, ui.radius_md, ui.colors.surface);
    ui.border(r, ui.radius_md, 1, ui.colors.border);
    _ = ui.text(title, r.x + 16, r.y + 15, 11, .mono_bold, ui.colors.text);
    ui.rect(.{ .x = r.x, .y = r.y + 40, .w = r.w, .h = 1 }, 0, ui.colors.border);
    return .{ .x = r.x + 16, .y = r.y + 54, .w = r.w - 32, .h = r.h - 66 };
}

fn tile(r: Rect, ic: u21, caption: []const u8, value: []const u8, sub_text: []const u8, col: Rgba) void {
    _ = ic;
    ui.rect(r, ui.radius_md, ui.colors.surface);
    ui.border(r, ui.radius_md, 1, ui.colors.border);
    ui.rect(.{ .x = r.x + 16, .y = r.y + 18, .w = 6, .h = 6 }, 1, col);
    ui.label(caption, .{ .x = r.x + 30, .y = r.y + 12, .w = r.w - 44, .h = 18 }, 11, .mono, ui.colors.text_muted, .left);
    ui.label(value, .{ .x = r.x + 16, .y = r.y + 42, .w = r.w - 32, .h = 34 }, 30, .display, ui.colors.text, .left);
    if (sub_text.len > 0) ui.label(sub_text, .{ .x = r.x + 16, .y = r.y + 84, .w = r.w - 32, .h = 16 }, 11, .mono, ui.colors.text_faint, .left);
}

fn ranking(a: *App, r: Rect, ranked: []const Ranked) void {
    const in_r = card(r, icons.trophy, a.t.stats_ranking);
    var count: usize = 0;
    for (ranked) |it| {
        if (it.plays > 0) count += 1;
    }
    if (count == 0) {
        ui.label(a.t.stats_no_plays, in_r, 13, .regular, ui.colors.text_faint, .center);
        return;
    }
    const top_plays: f32 = @floatFromInt(ranked[0].plays);
    const row_h: f32 = 38;
    var y = in_r.y;
    var i: usize = 0;
    while (i < @min(count, 10)) : (i += 1) {
        if (y + row_h > in_r.bottom() + 6) break;
        const it = ranked[i];
        const s = &a.lib.workspaces.items[it.ws].sounds.items[it.si];
        const row: Rect = .{ .x = in_r.x, .y = y, .w = in_r.w, .h = row_h - 4 };
        const key = ui.id("rank-row", i);
        const in = ui.interact(key, row);
        ui.rect(row, ui.radius_sm, ui.colors.text.alpha(in.hover_t * 0.04));
        // Rank: the top three in the accent color
        var nb: [4]u8 = undefined;
        const rank_col = if (i < 3) ui.colors.accent else ui.colors.text_faint;
        ui.label(std.fmt.bufPrint(&nb, "{d:0>2}", .{i + 1}) catch "", .{ .x = row.x, .y = row.y, .w = 26, .h = row.h }, if (i < 3) 15 else 12, if (i < 3) .mono_bold else .mono, rank_col, .left);
        const col = theme.padColor(s.color, ui.colors.accent);
        ui.rect(.{ .x = row.x + 34, .y = row.y + row.h / 2 - 4, .w = 8, .h = 8 }, 1, col);
        const name_w = row.w * 0.4;
        ui.label(s.name, .{ .x = row.x + 50, .y = row.y, .w = name_w - 50, .h = row.h }, 13, if (i < 3) .semibold else .regular, ui.colors.text, .left);
        // Bar: one hue, square on the baseline, value in text ink
        const bar_x = row.x + name_w;
        const bar_w_max = row.w - name_w - 64;
        const t = @as(f32, @floatFromInt(it.plays)) / @max(top_plays, 1);
        const grow = ui.easeOutCubic(ui.animFrom(ui.sub(key, 1), 0, 1, 7));
        ui.rect(.{ .x = bar_x, .y = row.y + row.h / 2 - 4, .w = bar_w_max, .h = 8 }, 1, ui.colors.text.alpha(0.05));
        ui.rect(.{ .x = bar_x, .y = row.y + row.h / 2 - 4, .w = @max(3, bar_w_max * t * grow), .h = 8 }, 1, ui.colors.accent.alpha(if (i < 3) 1 else 0.6));
        var vb: [16]u8 = undefined;
        ui.label(std.fmt.bufPrint(&vb, "{d}", .{it.plays}) catch "", .{ .x = row.right() - 56, .y = row.y, .w = 52, .h = row.h }, 12, .mono, ui.colors.text_muted, .right);
        if (in.hovered) {
            var tb: [32]u8 = undefined;
            ui.tooltip(key, a.tf("{} · {} · {}", .{ a.lib.workspaces.items[it.ws].name, a.tf(a.t.stats_plays_n, .{it.plays}), fmtLong(&tb, it.seconds) }));
        }
        y += row_h;
    }
}

fn daysChart(a: *App, r: Rect) void {
    var in_r = card(r, icons.bar_chart, a.t.stats_last_days);
    const n_days: usize = 14;
    const today = stats.today();
    var max_plays: u32 = 0;
    var sum: u32 = 0;
    for (0..n_days) |i| {
        const p = stats.playsOn(today - @as(i64, @intCast(n_days - 1 - i)));
        max_plays = @max(max_plays, p);
        sum += p;
    }
    _ = ui.text(a.tf(a.t.stats_days_total, .{sum}), in_r.x, in_r.y - 6, 11, .mono, ui.colors.text_muted);
    _ = in_r.cutTop(24);
    const axis = in_r.cutBottom(24);
    const plot = in_r;

    // Recessive grid: three lines with the scale on the left
    const scale_max: f32 = @floatFromInt(@max(niceCeil(max_plays), 4));
    for (0..4) |g| {
        const gy = plot.bottom() - plot.h * @as(f32, @floatFromInt(g)) / 3;
        ui.rect(.{ .x = plot.x + 28, .y = gy, .w = plot.w - 28, .h = 1 }, 0, ui.colors.border.alpha(if (g == 0) 0.9 else 0.4));
        var gb: [12]u8 = undefined;
        const v = scale_max * @as(f32, @floatFromInt(g)) / 3;
        ui.label(std.fmt.bufPrint(&gb, "{d:.0}", .{v}) catch "", .{ .x = plot.x, .y = gy - 8, .w = 22, .h = 16 }, 10, .mono, ui.colors.text_faint, .right);
    }

    const bars_x = plot.x + 34;
    const bars_w = plot.w - 40;
    const slot = bars_w / @as(f32, @floatFromInt(n_days));
    const bw = @min(26, slot - 6);
    for (0..n_days) |i| {
        const day = today - @as(i64, @intCast(n_days - 1 - i));
        const plays = stats.playsOn(day);
        const bx = bars_x + @as(f32, @floatFromInt(i)) * slot + (slot - bw) / 2;
        const grow = ui.easeOutCubic(ui.animFrom(ui.id("day-bar", i), 0, 1, 5));
        const h = plot.h * @as(f32, @floatFromInt(plays)) / scale_max * grow;
        const hit: Rect = .{ .x = bars_x + @as(f32, @floatFromInt(i)) * slot, .y = plot.y, .w = slot, .h = plot.h };
        const key = ui.id("day-hit", i);
        const in = ui.interact(key, hit);
        if (in.hover_t > 0.01) ui.rect(hit, 6, ui.colors.text.alpha(0.04 * in.hover_t));
        const is_today = i == n_days - 1;
        if (plays > 0) {
            // Rounded at the data end, square on the baseline
            const bar: Rect = .{ .x = bx, .y = plot.bottom() - h, .w = bw, .h = h };
            ui.rect(bar, 1, ui.colors.accent.alpha(if (is_today) 1 else 0.6));
        }
        // Day labels every other day, plus today
        if (i % 2 == 1 or is_today) {
            var lb: [8]u8 = undefined;
            const lbl = if (is_today) a.t.stats_today_short else (std.fmt.bufPrint(&lb, "{d}", .{dayOfMonth(day)}) catch "");
            ui.label(lbl, .{ .x = bars_x + @as(f32, @floatFromInt(i)) * slot - 6, .y = axis.y + 4, .w = slot + 12, .h = 16 }, 10, if (is_today) .mono_bold else .mono, if (is_today) ui.colors.text else ui.colors.text_faint, .center);
        }
        if (in.hovered) {
            var tb: [32]u8 = undefined;
            ui.tooltip(key, a.tf("{}/{} · {} · {}", .{ dayOfMonth(day), monthOf(day), a.tf(a.t.stats_plays_n, .{plays}), fmtLong(&tb, stats.secondsOn(day)) }));
        }
    }
}

fn niceCeil(v: u32) u32 {
    if (v <= 4) return 4;
    // Multiples of 3 so the three grid lines land on whole numbers
    return (v + 2) / 3 * 3;
}

fn civil(day: i64) struct { y: i64, m: u32, d: u32 } {
    // Howard Hinnant's days_from_civil inverse
    const z = day + 719468;
    const era = @divFloor(z, 146097);
    const doe: i64 = z - era * 146097;
    const yoe = @divFloor(doe - @divFloor(doe, 1460) + @divFloor(doe, 36524) - @divFloor(doe, 146096), 365);
    const doy = doe - (365 * yoe + @divFloor(yoe, 4) - @divFloor(yoe, 100));
    const mp = @divFloor(5 * doy + 2, 153);
    const d: u32 = @intCast(doy - @divFloor(153 * mp + 2, 5) + 1);
    const m: u32 = @intCast(if (mp < 10) mp + 3 else mp - 9);
    return .{ .y = yoe + era * 400 + @as(i64, if (m <= 2) 1 else 0), .m = m, .d = d };
}

fn dayOfMonth(day: i64) u32 {
    return civil(day).d;
}

fn monthOf(day: i64) u32 {
    return civil(day).m;
}

/// Returns the height used
fn historyList(a: *App, r: Rect) f32 {
    const items = stats.history.items;
    const shown = @min(items.len, 40);
    const row_h: f32 = 36;
    const h: f32 = 72 + @max(1, @as(f32, @floatFromInt(shown))) * row_h + 10;
    const in_r = card(.{ .x = r.x, .y = r.y, .w = r.w, .h = h }, icons.history, a.t.stats_history);
    if (shown == 0) {
        ui.label(a.t.stats_no_plays, .{ .x = in_r.x, .y = in_r.y, .w = in_r.w, .h = row_h }, 13, .regular, ui.colors.text_faint, .left);
        return h;
    }
    const now = library.now();
    var y = in_r.y;
    var i: usize = 0;
    while (i < shown) : (i += 1) {
        const e = items[items.len - 1 - i];
        const row: Rect = .{ .x = in_r.x, .y = y, .w = in_r.w, .h = row_h - 4 };
        if (i > 0) ui.rect(.{ .x = row.x, .y = row.y - 2, .w = row.w, .h = 1 }, 0, ui.colors.border.alpha(0.6));
        const col = theme.padColor(e.color, ui.colors.accent);
        ui.rect(.{ .x = row.x + 12, .y = row.y + row.h / 2 - 4, .w = 8, .h = 8 }, 1, col);
        ui.label(e.name, .{ .x = row.x + 32, .y = row.y, .w = row.w * 0.45, .h = row.h }, 13, .semibold, ui.colors.text, .left);
        ui.label(e.ws, .{ .x = row.x + row.w * 0.5, .y = row.y, .w = row.w * 0.3, .h = row.h }, 11, .mono, ui.colors.text_muted, .left);
        var tb: [48]u8 = undefined;
        ui.label(ago(a, &tb, now - e.t), .{ .x = row.right() - 160, .y = row.y, .w = 148, .h = row.h }, 11, .mono, ui.colors.text_faint, .right);
        y += row_h;
    }
    return h;
}

fn ago(a: *App, buf: []u8, secs: i64) []const u8 {
    if (secs < 60) return a.t.stats_just_now;
    if (secs < 3600) return i18nFmt(buf, a.t.stats_min_ago, @divFloor(secs, 60));
    if (secs < 86400) return i18nFmt(buf, a.t.stats_hours_ago, @divFloor(secs, 3600));
    return i18nFmt(buf, a.t.stats_days_ago, @divFloor(secs, 86400));
}

fn i18nFmt(buf: []u8, template: []const u8, v: i64) []const u8 {
    return @import("i18n.zig").format(buf, template, .{v});
}
