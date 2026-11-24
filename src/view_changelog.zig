//! Settings → Changelog: CHANGELOG.md baked into the binary, one card per
//! version. `notes` also draws the release notes in the update dialog.

const std = @import("std");
const ui = @import("ui.zig");
const updater = @import("update.zig");
const changelog = @import("changelog.zig");
const sys = @import("sys.zig");
const app_mod = @import("app.zig");
const App = app_mod.App;
const icons = ui.icons;
const Rect = ui.Rect;

/// Draws changelog-style text ("### Heading", "- bullet", plain lines) and
/// returns its height. With `visible` false it only measures.
pub fn notes(src: []const u8, x: f32, y0: f32, w: f32, visible: bool) f32 {
    var y = y0;
    var buf: [2048]u8 = undefined;
    var started = false;
    var lines = std.mem.splitScalar(u8, src, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0) continue;
        if (line[0] == '#') {
            if (started) y += 10;
            const title = changelog.plain(&buf, std.mem.trimStart(u8, line, "# "));
            if (visible) _ = ui.text(title, x, y, 11, .mono_bold, ui.colors.accent);
            y += 24;
        } else if (std.mem.startsWith(u8, line, "- ")) {
            const body = changelog.plain(&buf, line[2..]);
            if (visible) ui.rect(.{ .x = x + 2, .y = y + 7, .w = 5, .h = 5 }, 1, ui.colors.text_faint);
            y += ui.paragraph(body, .{ .x = x + 18, .y = y, .w = w - 18, .h = 0 }, 13, .regular, ui.colors.text, 1.5, visible) + 6;
        } else {
            const body = changelog.plain(&buf, line);
            y += ui.paragraph(body, .{ .x = x, .y = y, .w = w, .h = 0 }, 13, .regular, ui.colors.text_muted, 1.5, visible) + 8;
        }
        started = true;
    }
    return y - y0;
}

/// Card body heights, kept until the width, language or scale changes:
/// wrapping every release on every frame made the tab crawl
const HeightKey = struct { w: f32 = 0, pt: bool = false, scale: f32 = 0 };
var height_key: HeightKey = .{};
var heights: [128]f32 = undefined;
var heights_len: usize = 0;

/// Sections come in order every frame, so the cache fills front to back
fn bodyHeight(i: usize, body: []const u8, w: f32, pt: bool) f32 {
    const key: HeightKey = .{ .w = w, .pt = pt, .scale = ui.scale };
    if (!std.meta.eql(key, height_key)) {
        height_key = key;
        heights_len = 0;
    }
    if (i < heights_len) return heights[i];
    const h = notes(body, 0, 0, w, false);
    if (i == heights_len and i < heights.len) {
        heights[i] = h;
        heights_len += 1;
    }
    return h;
}

pub fn draw(a: *App, r: Rect) void {
    const width = @min(r.w - 10, 860);
    const scroll_key = ui.id("changelog-scroll", 0);
    const top = ui.beginScroll(scroll_key, r);
    const x = r.x + (r.w - 10 - width) / 2;
    var y = top + 8;

    // A newer version waiting on GitHub goes first
    const st = updater.state.load(.acquire);
    if (st == .available or st == .ready or st == .downloading) {
        const banner: Rect = .{ .x = x, .y = y, .w = width, .h = 64 };
        ui.rect(banner, ui.radius_lg, ui.colors.accent.alpha(0.1));
        ui.border(banner, ui.radius_lg, 1, ui.colors.accent.alpha(0.5));
        ui.icon(icons.download, .{ .x = banner.x + 30, .y = banner.y + 32 }, 18, ui.colors.accent);
        const msg = if (st == .ready) a.tf(a.t.upd_ready, .{updater.latestVersion()}) else a.tf(a.t.upd_available, .{updater.latestVersion()});
        ui.label(msg, .{ .x = banner.x + 54, .y = banner.y, .w = banner.w - 260, .h = banner.h }, 14, .semibold, ui.colors.text, .left);
        const br: Rect = .{ .x = banner.right() - 186, .y = banner.y + 14, .w = 170, .h = 36 };
        if (st == .ready) {
            if (ui.button(ui.id("cl-restart", 0), br, a.t.upd_restart, .{ .style = .primary, .icon = icons.refresh_cw })) a.restartForUpdate();
        } else if (ui.button(ui.id("cl-update", 0), br, a.t.upd_view, .{ .style = .primary, .icon = icons.download })) {
            a.dialog = .update;
        }
        y += banner.h + 18;
    }

    var rest: []const u8 = if (a.cfg.language == .pt) changelog.pt else changelog.en;
    var i: usize = 0;
    while (changelog.next(&rest)) |sec| : (i += 1) {
        const pad: f32 = 24;
        const head_h: f32 = 58;
        const body_h = bodyHeight(i, sec.body, width - pad * 2, a.cfg.language == .pt);
        const card: Rect = .{ .x = x, .y = y, .w = width, .h = head_h + body_h + pad };

        // Off-screen cards are only measured
        if (card.bottom() > r.y and card.y < r.bottom()) {
            const current = std.mem.eql(u8, sec.version, a.version);
            ui.rect(card, ui.radius_lg, ui.colors.surface);
            ui.border(card, ui.radius_lg, 1, if (current) ui.colors.accent.alpha(0.6) else ui.colors.border);
            if (current) ui.rect(.{ .x = card.x, .y = card.y + 20, .w = 3, .h = 26 }, 1, ui.colors.accent);

            const vw = ui.text(sec.version, card.x + pad, card.y + 20, 22, .mono_bold, if (current) ui.colors.accent else ui.colors.text);
            var bx = card.x + pad + vw + 14;
            if (sec.date.len > 0) bx += ui.text(sec.date, bx, card.y + 27, 12, .mono, ui.colors.text_faint) + 14;
            if (current) {
                const tag = a.t.cl_installed;
                const tw = ui.measure(tag, 11, .semibold) + 18;
                ui.badge(.{ .x = bx, .y = card.y + 25, .w = tw, .h = 20 }, tag, ui.colors.accent.alpha(0.15), ui.colors.accent);
            } else if (i == 0 and updater.isNewer(sec.version, a.version)) {
                const tag = a.t.cl_new;
                const tw = ui.measure(tag, 11, .semibold) + 18;
                ui.badge(.{ .x = bx, .y = card.y + 25, .w = tw, .h = 20 }, tag, ui.colors.success.alpha(0.15), ui.colors.success);
            }
            ui.rect(.{ .x = card.x + pad, .y = card.y + head_h - 6, .w = card.w - pad * 2, .h = 1 }, 0, ui.colors.border.alpha(0.7));
            _ = notes(sec.body, card.x + pad, card.y + head_h + 8, width - pad * 2, true);
        }
        y += card.h + 16;
    }

    if (ui.button(ui.id("cl-github", 0), .{ .x = x + (width - 260) / 2, .y = y + 6, .w = 260, .h = 36 }, a.t.cl_all_releases, .{ .icon = icons.external_link, .style = .ghost })) {
        sys.openUrl(updater.all_releases_url);
    }
    y += 60;
    ui.endScroll(y - top);
}
