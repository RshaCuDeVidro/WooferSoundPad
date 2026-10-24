//! First-run tour: a five-step carousel with animated illustrations.

const std = @import("std");
const ui = @import("ui.zig");
const sys = @import("sys.zig");
const app_mod = @import("app.zig");
const App = app_mod.App;
const icons = ui.icons;
const Rect = ui.Rect;
const Rgba = ui.Rgba;

const steps = 5;
var step_changed_at: f32 = 0;
var direction: f32 = 1;

pub fn draw(a: *App) void {
    const m = ui.beginModal(ui.id("onboarding", 0), 680, 540, a.onboarding_open) orelse return;
    defer ui.endModal();
    if (m.close_requested) finish(a);
    const r = m.rect;

    const step = @min(a.onboarding_step, steps - 1);
    const since = ui.time - step_changed_at;
    const t = if (ui.animations) ui.easeOutCubic(since / 0.35) else 1;

    // Illustration
    const art: Rect = .{ .x = r.x + 12, .y = r.y + 12, .w = r.w - 24, .h = 250 };
    ui.rect(art, ui.radius_md, ui.colors.sidebar);
    ui.border(art, ui.radius_md, 1, ui.colors.border);
    ui.pushClip(art);
    gridPaper(art);
    ui.pushAlpha(t);
    ui.pushTranslate((1 - t) * 40 * direction, 0);
    illustration(a, step, art);
    ui.popTranslate();
    ui.popAlpha();
    ui.popClip();

    // Text
    const texts = [_][2][]const u8{
        .{ a.t.ob1_title, a.t.ob1_body },
        .{ a.t.ob2_title, a.t.ob2_body },
        .{ a.t.ob3_title, a.t.ob3_body },
        .{ a.t.ob4_title, if (sys.is_windows) a.t.ob4_body_windows else a.t.ob4_body_linux },
        .{ a.t.ob5_title, a.t.ob5_body },
    };
    ui.pushAlpha(t);
    const title = texts[step][0];
    const tw = ui.measure(title, 24, .display);
    _ = ui.text(title, r.x + (r.w - tw) / 2 + (1 - t) * 20 * direction, art.bottom() + 30, 24, .display, ui.colors.text);
    const body_r: Rect = .{ .x = r.x + 70, .y = art.bottom() + 74, .w = r.w - 140, .h = 90 };
    centered(texts[step][1], body_r);
    ui.popAlpha();

    // Dots
    const dots_y = r.bottom() - 46;
    var dx = r.x + 28;
    for (0..steps) |i| {
        const active_t = ui.anim(ui.id("ob-dot", i), if (i == step) 1 else 0, 14);
        const w = 8 + active_t * 18;
        ui.rect(.{ .x = dx, .y = dots_y - 4, .w = w, .h = 8 }, 4, Rgba.lerp(ui.colors.border, ui.colors.accent, active_t));
        dx += w + 6;
    }

    // Buttons
    const by = r.bottom() - 66;
    const last = step == steps - 1;
    if (ui.button(ui.id("ob-next", 0), .{ .x = r.right() - 164, .y = by, .w = 140, .h = 42 }, if (last) a.t.ob_start else a.t.ob_next, .{ .style = .primary, .icon = if (last) icons.rocket else icons.arrow_right })) {
        if (last) finish(a) else go(a, step + 1);
    }
    if (step > 0) {
        if (ui.button(ui.id("ob-back", 0), .{ .x = r.right() - 284, .y = by, .w = 110, .h = 42 }, a.t.ob_back, .{ .style = .ghost, .icon = icons.arrow_left })) go(a, step - 1);
    } else if (ui.button(ui.id("ob-skip", 0), .{ .x = r.right() - 284, .y = by, .w = 110, .h = 42 }, a.t.ob_skip, .{ .style = .ghost })) finish(a);

    if (a.onboarding_open) {
        const c = @import("c");
        if (c.IsKeyPressed(c.KEY_RIGHT) and !last) go(a, step + 1);
        if (c.IsKeyPressed(c.KEY_LEFT) and step > 0) go(a, step - 1);
    }
}

fn go(a: *App, step: usize) void {
    direction = if (step > a.onboarding_step) 1 else -1;
    a.onboarding_step = step;
    step_changed_at = ui.time;
}

fn finish(a: *App) void {
    a.onboarding_open = false;
    if (!a.cfg.onboarding_done) {
        a.cfg.onboarding_done = true;
        a.markConfig();
    }
}

fn centered(s: []const u8, r: Rect) void {
    var y = r.y;
    var start: usize = 0;
    while (start < s.len) {
        var end = start;
        var best = start;
        while (end < s.len) {
            var next = end;
            while (next < s.len and s[next] == ' ') next += 1;
            while (next < s.len and s[next] != ' ') next += 1;
            if (ui.measure(s[start..next], 15, .regular) > r.w and best > start) break;
            best = next;
            end = next;
        }
        if (best == start) best = s.len;
        const line = std.mem.trim(u8, s[start..best], " ");
        const w = ui.measure(line, 15, .regular);
        _ = ui.text(line, r.x + (r.w - w) / 2, y, 15, .regular, ui.colors.text_muted);
        y += 23;
        start = best;
        while (start < s.len and s[start] == ' ') start += 1;
    }
}

/// Faint graph-paper grid behind the illustrations
fn gridPaper(r: Rect) void {
    const step: f32 = 24;
    var x = r.x + @mod(r.w / 2, step);
    while (x < r.right()) : (x += step) ui.rect(.{ .x = x, .y = r.y, .w = 1, .h = r.h }, 0, ui.colors.border.alpha(0.45));
    var y = r.y + @mod(r.h / 2, step);
    while (y < r.bottom()) : (y += step) ui.rect(.{ .x = r.x, .y = y, .w = r.w, .h = 1 }, 0, ui.colors.border.alpha(0.45));
}

/// Slowly drifting snow
fn particles(r: Rect) void {
    for (0..26) |i| {
        const fi: f32 = @floatFromInt(i);
        const speed = 10 + @mod(fi * 7.3, 14);
        const x = r.x + @mod(fi * 97.1 + @sin(ui.time * 0.6 + fi) * 14, r.w);
        const y = r.y + @mod(fi * 53.7 + ui.time * speed, r.h);
        const size = 1.2 + @mod(fi * 0.37, 2.2);
        ui.circle(.{ .x = x, .y = y }, size, ui.colors.text.alpha(0.18));
    }
}

fn bubble(center: ui.Vec2, radius: f32, ic: u21, col: Rgba) void {
    const box: Rect = .{ .x = center.x - radius, .y = center.y - radius, .w = radius * 2, .h = radius * 2 };
    ui.rect(box, ui.radius_md, ui.colors.surface);
    ui.border(box, ui.radius_md, 1, col);
    ui.icon(ic, center, radius * 0.8, col);
}

fn illustration(a: *App, step: usize, art: Rect) void {
    const cx = art.x + art.w / 2;
    const cy = art.y + art.h / 2;
    const bob = @sin(ui.time * 2) * 6;
    switch (step) {
        0 => {
            ui.image(a.logo, .{ .x = cx - 56, .y = cy - 56, .w = 112, .h = 112 }, 0, .{ .r = 1, .g = 1, .b = 1 });
        },
        1 => {
            const names = [_][]const u8{ "Memes", "Gaming", "Stream" };
            const cols = [_]Rgba{ ui.colors.accent, ui.colors.accent2, ui.colors.success };
            for (names, 0..) |n, i| {
                const fi: f32 = @floatFromInt(i);
                const appear = ui.easeOutCubic(std.math.clamp((ui.time - step_changed_at - fi * 0.1) / 0.3, 0, 1));
                const card: Rect = .{ .x = cx - 150 + fi * 105, .y = cy - 46, .w = 94, .h = 92 };
                const shown = card.offset(0, (1 - appear) * 10);
                ui.pushAlpha(appear);
                defer ui.popAlpha();
                ui.rect(shown, ui.radius_md, ui.colors.surface);
                ui.border(shown, ui.radius_md, 1, cols[i]);
                ui.icon(icons.folder, .{ .x = shown.x + shown.w / 2, .y = shown.y + 36 }, 26, cols[i]);
                ui.label(n, .{ .x = shown.x, .y = shown.y + 58, .w = shown.w, .h = 20 }, 13, .semibold, ui.colors.text, .center);
            }
        },
        2 => {
            bubble(.{ .x = cx, .y = cy + bob }, 46, icons.compass, ui.colors.accent);
            const orbit = [_]struct { ic: u21, col: Rgba }{
                .{ .ic = icons.youtube, .col = ui.colors.danger },
                .{ .ic = icons.cloud, .col = ui.colors.warning },
                .{ .ic = icons.zap, .col = ui.colors.accent2 },
                .{ .ic = icons.link, .col = ui.colors.success },
            };
            for (orbit, 0..) |o, i| {
                const ang = ui.time * 0.8 + @as(f32, @floatFromInt(i)) * std.math.pi / 2.0;
                bubble(.{ .x = cx + @cos(ang) * 140, .y = cy + @sin(ang) * 62 }, 24, o.ic, o.col);
            }
        },
        3 => {
            bubble(.{ .x = cx - 110, .y = cy + bob }, 40, icons.music, ui.colors.accent);
            bubble(.{ .x = cx + 110, .y = cy - bob }, 40, icons.headphones, ui.colors.success);
            // Sound flowing from the board to the voice chat
            for (0..5) |i| {
                const k = @mod(ui.time * 0.9 + @as(f32, @floatFromInt(i)) / 5.0, 1.0);
                const x = cx - 60 + k * 120;
                ui.circle(.{ .x = x, .y = cy + @sin(k * std.math.pi * 2) * 10 }, 5, ui.colors.accent.alpha(@sin(k * std.math.pi)));
            }
            bubble(.{ .x = cx, .y = cy + 70 + bob * 0.5 }, 26, icons.mic, ui.colors.accent2);
        },
        else => {
            const keys = [_][]const u8{ "Ctrl", "Shift", "1" };
            var x = cx - 150;
            for (keys, 0..) |k, i| {
                const fi: f32 = @floatFromInt(i);
                const press = @max(0, @sin(ui.time * 3 - fi * 0.5));
                const w: f32 = if (k.len > 1) 100 else 70;
                const kr: Rect = .{ .x = x, .y = cy - 34 + press * 6, .w = w, .h = 64 };
                ui.rect(kr.offset(0, 8 - press * 6), ui.radius_lg, ui.colors.border);
                ui.rect(kr, ui.radius_lg, ui.colors.elevated);
                ui.border(kr, ui.radius_lg, 1, Rgba.lerp(ui.colors.border, ui.colors.accent, press));
                ui.label(k, kr, 20, .bold, ui.colors.text, .center);
                x += w + 18;
                if (i < keys.len - 1) {
                    ui.label("+", .{ .x = x - 18, .y = cy - 34, .w = 18, .h = 64 }, 18, .bold, ui.colors.text_faint, .center);
                }
            }
            ui.glow(.{ .x = cx + 120, .y = cy }, 120, ui.colors.accent.alpha(0.3 * @max(0, @sin(ui.time * 3 - 1))));
        },
    }
}
