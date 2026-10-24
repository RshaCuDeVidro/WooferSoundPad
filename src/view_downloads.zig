//! Downloads: live progress of everything being fetched or processed.

const std = @import("std");
const ui = @import("ui.zig");
const sys = @import("sys.zig");
const jobs = @import("jobs.zig");
const view = @import("view.zig");
const app_mod = @import("app.zig");
const App = app_mod.App;
const icons = ui.icons;
const Rect = ui.Rect;
const Rgba = ui.Rgba;

pub fn draw(a: *App, area: Rect) void {
    var r = area.insetXY(view.page_pad_x, 0);
    const actions = view.header(&r, a.t.downloads_title, a.t.downloads_sub);
    var finished: usize = 0;
    for (a.jobs.jobs.items) |j| {
        switch (j.getState()) {
            .done, .failed, .canceled => finished += 1,
            else => {},
        }
    }
    if (finished > 0) {
        if (ui.button(ui.id("dl-clear", 0), .{ .x = actions.right() - 170, .y = actions.y, .w = 170, .h = 38 }, a.t.clear_finished, .{ .icon = icons.trash_2, .style = .ghost })) {
            a.jobs.clearFinished();
        }
    }

    if (a.jobs.jobs.items.len == 0) {
        const act = view.emptyState(r, icons.download, a.t.no_downloads, a.t.no_downloads_body);
        var row = act;
        const b1 = row.cutLeft(195);
        _ = row.cutLeft(10);
        const b2 = row.cutLeft(195);
        if (ui.button(ui.id("dl-empty-explore", 0), b1, a.t.empty_explore, .{ .icon = icons.compass, .style = .primary })) a.goto(.explore);
        if (ui.button(ui.id("dl-empty-online", 0), b2, a.t.empty_online, .{ .icon = icons.globe })) a.goto(.online);
        return;
    }

    const row_h: f32 = 76;
    var y = ui.beginScroll(ui.id("dl-scroll", 0), r);
    const start = y;
    var i = a.jobs.jobs.items.len;
    while (i > 0) {
        i -= 1;
        const j = a.jobs.jobs.items[i];
        const row: Rect = .{ .x = r.x, .y = y, .w = r.w - 10, .h = row_h };
        y += row_h + 10;
        drawJob(a, j, row);
    }
    ui.endScroll(y - start);
}

fn drawJob(a: *App, j: *jobs.Job, r_in: Rect) void {
    const key = ui.id("job", j.id);
    const appear = ui.animFrom(ui.sub(key, 1), 0, 1, 10);
    ui.pushAlpha(appear);
    defer ui.popAlpha();
    const r = r_in.offset(0, (1 - appear) * 10);
    const state = j.getState();
    const accent = switch (state) {
        .done => ui.colors.success,
        .failed => ui.colors.danger,
        .canceled => ui.colors.text_faint,
        else => ui.colors.accent,
    };
    ui.rect(r, ui.radius_lg, ui.colors.surface);
    ui.border(r, ui.radius_lg, 1, ui.colors.border);

    // Kind icon (spins while working)
    const ic: u21 = switch (j.kind) {
        .sound => icons.music,
        .media => icons.youtube,
        .tool => icons.package,
        .edit => icons.scissors,
    };
    const chip: ui.Vec2 = .{ .x = r.x + 34, .y = r.y + r.h / 2 };
    ui.border(.{ .x = chip.x - 18, .y = chip.y - 18, .w = 36, .h = 36 }, ui.radius_md, 1, accent.alpha(0.6));
    if (state == .running) ui.arc(chip, 23, 2, ui.time * 300, ui.time * 300 + 90, accent);
    const state_icon: u21 = switch (state) {
        .done => icons.check,
        .failed => icons.triangle_alert,
        .canceled => icons.ban,
        else => ic,
    };
    ui.icon(state_icon, chip, 18, accent);

    // Title + status line
    const text_x = r.x + 68;
    const text_w = r.w - 68 - 140;
    ui.label(j.title, .{ .x = text_x, .y = r.y + 14, .w = text_w, .h = 20 }, 14, .semibold, ui.colors.text, .left);
    const progress = j.progress.get();
    var status_buf: [256]u8 = undefined;
    const status: []const u8 = switch (state) {
        .queued => a.t.state_queued,
        .running => blk: {
            const stage_name = switch (j.stage.load(.acquire)) {
                0 => a.t.state_downloading,
                1 => if (j.kind == .tool) a.t.state_unpacking else a.t.state_converting,
                else => a.t.state_processing,
            };
            break :blk if (progress >= 0) std.fmt.bufPrint(&status_buf, "{s} · {d:.0}%", .{ stage_name, progress * 100 }) catch stage_name else stage_name;
        },
        .done => if (j.workspace_name.len > 0) std.fmt.bufPrint(&status_buf, "{s} · {s}", .{ a.t.state_done, j.workspace_name }) catch a.t.state_done else a.t.state_done,
        .failed => std.fmt.bufPrint(&status_buf, "{s} · {s}", .{ a.t.state_failed, j.errorText() }) catch a.t.state_failed,
        .canceled => a.t.state_canceled,
    };
    ui.label(status, .{ .x = text_x, .y = r.y + 36, .w = text_w, .h = 18 }, 12, .regular, if (state == .failed) ui.colors.danger else ui.colors.text_muted, .left);

    if (state == .running or state == .queued) {
        const shown = if (progress >= 0) ui.anim(ui.sub(key, 3), progress, 12) else -1;
        ui.progressBar(.{ .x = text_x, .y = r.y + 60, .w = text_w, .h = 4 }, shown, accent);
    }

    // Actions
    const btn_y = r.y + (r.h - 34) / 2;
    var bx = r.right() - 46;
    switch (state) {
        .queued, .running => {
            if (ui.iconButton(ui.sub(key, 10), .{ .x = bx, .y = btn_y, .w = 34, .h = 34 }, icons.x, .{ .tooltip = a.t.cancel, .size = 16 })) a.jobs.cancel(j);
        },
        .failed, .canceled => {
            if (ui.iconButton(ui.sub(key, 11), .{ .x = bx, .y = btn_y, .w = 34, .h = 34 }, icons.rotate_ccw, .{ .tooltip = a.t.retry, .size = 16 })) a.jobs.retry(j);
        },
        .done => {
            if ((j.kind == .sound or j.kind == .media) and j.workspace_dir.len > 0) {
                if (ui.iconButton(ui.sub(key, 12), .{ .x = bx, .y = btn_y, .w = 34, .h = 34 }, icons.folder_open, .{ .tooltip = a.t.show_in_folder, .size = 16 })) {
                    const p = sys.join(&.{ j.workspace_dir, j.result }) catch null;
                    if (p) |path| {
                        sys.revealFile(path);
                        sys.gpa.free(path);
                    }
                }
                bx -= 40;
                if (ui.iconButton(ui.sub(key, 13), .{ .x = bx, .y = btn_y, .w = 34, .h = 34 }, icons.layout_grid, .{ .tooltip = a.t.nav_soundboard, .size = 16 })) {
                    if (a.lib.find(j.workspace_name)) |wi| a.switchWorkspace(wi);
                    a.goto(.soundboard);
                }
            }
        },
    }
}
