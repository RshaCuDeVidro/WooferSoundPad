//! Immediate-mode UI toolkit on top of raylib.
//!
//! Everything is laid out in logical pixels; a 2D camera scales the frame by
//! `scale`, and fonts are rasterized at the physical size so text stays crisp.
//! Shapes are drawn by one SDF "uber shader" that also handles regular
//! textured draws, so rounded rects, shadows, borders and text all batch together.

const std = @import("std");
const c = @import("c");
const assets = @import("assets");
const theme = @import("theme.zig");
pub const icons = @import("icons.zig");

pub const Rgba = theme.Rgba;
const gpa = std.heap.c_allocator;

// ── Geometry ────────────────────────────────────────────────────────────────

pub const Vec2 = struct {
    x: f32 = 0,
    y: f32 = 0,
};

pub const Rect = struct {
    x: f32 = 0,
    y: f32 = 0,
    w: f32 = 0,
    h: f32 = 0,

    pub fn contains(r: Rect, p: Vec2) bool {
        return p.x >= r.x and p.y >= r.y and p.x < r.x + r.w and p.y < r.y + r.h;
    }

    pub fn inset(r: Rect, d: f32) Rect {
        return .{ .x = r.x + d, .y = r.y + d, .w = @max(0, r.w - 2 * d), .h = @max(0, r.h - 2 * d) };
    }

    pub fn insetXY(r: Rect, dx: f32, dy: f32) Rect {
        return .{ .x = r.x + dx, .y = r.y + dy, .w = @max(0, r.w - 2 * dx), .h = @max(0, r.h - 2 * dy) };
    }

    pub fn offset(r: Rect, dx: f32, dy: f32) Rect {
        return .{ .x = r.x + dx, .y = r.y + dy, .w = r.w, .h = r.h };
    }

    pub fn grow(r: Rect, d: f32) Rect {
        return .{ .x = r.x - d, .y = r.y - d, .w = r.w + 2 * d, .h = r.h + 2 * d };
    }

    pub fn center(r: Rect) Vec2 {
        return .{ .x = r.x + r.w / 2, .y = r.y + r.h / 2 };
    }

    pub fn right(r: Rect) f32 {
        return r.x + r.w;
    }

    pub fn bottom(r: Rect) f32 {
        return r.y + r.h;
    }

    /// Scales around the center
    pub fn scaled(r: Rect, s: f32) Rect {
        const cx = r.x + r.w / 2;
        const cy = r.y + r.h / 2;
        return .{ .x = cx - r.w * s / 2, .y = cy - r.h * s / 2, .w = r.w * s, .h = r.h * s };
    }

    pub fn intersect(a: Rect, b: Rect) Rect {
        const x0 = @max(a.x, b.x);
        const y0 = @max(a.y, b.y);
        const x1 = @min(a.right(), b.right());
        const y1 = @min(a.bottom(), b.bottom());
        return .{ .x = x0, .y = y0, .w = @max(0, x1 - x0), .h = @max(0, y1 - y0) };
    }

    // "RectCut" layout: carve pieces off the edges of a rect.
    pub fn cutTop(r: *Rect, h: f32) Rect {
        const out: Rect = .{ .x = r.x, .y = r.y, .w = r.w, .h = @min(h, r.h) };
        r.y += out.h;
        r.h -= out.h;
        return out;
    }

    pub fn cutBottom(r: *Rect, h: f32) Rect {
        const hh = @min(h, r.h);
        r.h -= hh;
        return .{ .x = r.x, .y = r.y + r.h, .w = r.w, .h = hh };
    }

    pub fn cutLeft(r: *Rect, w: f32) Rect {
        const out: Rect = .{ .x = r.x, .y = r.y, .w = @min(w, r.w), .h = r.h };
        r.x += out.w;
        r.w -= out.w;
        return out;
    }

    pub fn cutRight(r: *Rect, w: f32) Rect {
        const ww = @min(w, r.w);
        r.w -= ww;
        return .{ .x = r.x + r.w, .y = r.y, .w = ww, .h = r.h };
    }

    /// Centers a w×h box inside r
    pub fn centered(r: Rect, w: f32, h: f32) Rect {
        return .{ .x = r.x + (r.w - w) / 2, .y = r.y + (r.h - h) / 2, .w = w, .h = h };
    }
};

// ── Frame state ─────────────────────────────────────────────────────────────

pub var colors: theme.Colors = theme.themes[0].colors;
var target_colors: theme.Colors = theme.themes[0].colors;
pub var dark: bool = true;

pub var scale: f32 = 1;
pub var dt: f32 = 1.0 / 60.0;
pub var time: f32 = 0;
pub var animations: bool = true;
pub var screen: Rect = .{};

pub var mouse: Vec2 = .{};
var mouse_pressed = false;
var mouse_released = false;
var mouse_down = false;
var right_pressed = false;
var wheel: f32 = 0;
var wheel_consumed = false;
var double_click = false;
var last_click_time: f32 = -10;

var hot: u64 = 0; // topmost hovered widget, from last frame
var hot_next: u64 = 0;
pub var active: u64 = 0; // widget holding the left mouse button
pub var focus: u64 = 0; // widget receiving keyboard input
var focus_claimed = false;
var want_cursor: c_int = c.MOUSE_CURSOR_DEFAULT;

/// Layer of what is being drawn now. Higher layers (popups, modals) block
/// mouse input to lower ones through rects registered in the previous frame.
pub var layer: u8 = 0;
const Blocker = struct { rect: Rect, layer: u8 };
var blockers: [32]Blocker = undefined;
var blocker_count: usize = 0;
var blockers_next: [32]Blocker = undefined;
var blocker_next_count: usize = 0;

var clip_stack: [16]Rect = undefined;
var clip_depth: usize = 0;

var alpha_stack: [16]f32 = undefined;
var alpha_depth: usize = 0;
pub var global_alpha: f32 = 1;

var anims: std.AutoHashMapUnmanaged(u64, f32) = .empty;

pub const Layer = struct {
    pub const base: u8 = 0;
    pub const popup: u8 = 1;
    pub const modal: u8 = 2;
    pub const modal_popup: u8 = 3;
    pub const toast: u8 = 5;
};

/// Corner radii. Kept small on purpose: hardware, not bubbles.
pub const radius_sm: f32 = 3;
pub const radius_md: f32 = 5;
pub const radius_lg: f32 = 7;

// ── IDs and animation ───────────────────────────────────────────────────────

pub fn id(comptime tag: []const u8, n: usize) u64 {
    var h = std.hash.Wyhash.init(0x5EED);
    h.update(tag);
    h.update(std.mem.asBytes(&n));
    return h.final();
}

pub fn idStr(comptime tag: []const u8, s: []const u8) u64 {
    var h = std.hash.Wyhash.init(0xD06);
    h.update(tag);
    h.update(s);
    return h.final();
}

pub fn sub(base: u64, n: u64) u64 {
    return std.hash.Wyhash.hash(base, std.mem.asBytes(&n));
}

/// Exponential ease toward `target`. `speed` is roughly "1/seconds".
pub fn anim(key: u64, target: f32, speed: f32) f32 {
    return animFrom(key, target, target, speed);
}

/// Like `anim`, but a value seen for the first time starts at `initial`
/// (entrance animations).
pub fn animFrom(key: u64, initial: f32, target: f32, speed: f32) f32 {
    const gop = anims.getOrPut(gpa, key) catch return target;
    if (!gop.found_existing) gop.value_ptr.* = initial;
    const v = gop.value_ptr;
    if (!animations) {
        v.* = target;
    } else {
        v.* += (target - v.*) * (1 - @exp(-speed * dt));
        if (@abs(target - v.*) < 0.0005) v.* = target;
    }
    return v.*;
}

pub fn animSet(key: u64, value: f32) void {
    anims.put(gpa, key, value) catch {};
}

pub fn easeOutBack(t: f32) f32 {
    const c1: f32 = 1.70158;
    const c3 = c1 + 1;
    const x = t - 1;
    return 1 + c3 * x * x * x + c1 * x * x;
}

pub fn easeOutCubic(t: f32) f32 {
    const x = 1 - std.math.clamp(t, 0, 1);
    return 1 - x * x * x;
}

// ── Theme ───────────────────────────────────────────────────────────────────

pub fn setTheme(t: *const theme.Theme, instant: bool) void {
    target_colors = t.colors;
    dark = t.dark;
    if (instant or !animations) colors = t.colors;
}

// ── Fonts ───────────────────────────────────────────────────────────────────

pub const FontKind = enum(u8) { regular, semibold, bold, display, icon, mono, mono_bold };

var fonts: std.AutoHashMapUnmanaged(u32, c.Font) = .empty;
var text_codepoints: [400]c_int = undefined;
var text_codepoint_count: usize = 0;
var icon_codepoints: [icons.all.len]c_int = undefined;

fn initCodepoints() void {
    var n: usize = 0;
    var cp: c_int = 32;
    while (cp <= 126) : (cp += 1) {
        text_codepoints[n] = cp;
        n += 1;
    }
    cp = 160;
    while (cp <= 255) : (cp += 1) {
        if (cp == 0xAD) continue; // soft hyphen: invisible, not in the font
        text_codepoints[n] = cp;
        n += 1;
    }
    for ([_]c_int{ 0x2013, 0x2014, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2026, 0x20AC, 0x2122, 0x203A, 0x221E, 0x2212, 0x25A0, 0x25B6 }) |extra| {
        text_codepoints[n] = extra;
        n += 1;
    }
    text_codepoint_count = n;
    for (icons.all, 0..) |icon_cp, i| icon_codepoints[i] = @intCast(icon_cp);
}

/// UI sizes are close to CSS em sizes; raylib sizes are full line heights
/// (ascent + descent), which would make Inter look ~20% too small.
const text_em: f32 = 1.12;

fn lineSize(kind: FontKind, size: f32) f32 {
    return if (kind == .icon) size else size * text_em;
}

pub fn font(kind: FontKind, size_in: f32) c.Font {
    const size = lineSize(kind, size_in);
    const px: u32 = @intFromFloat(@max(6, @round(size * scale)));
    const key = (@as(u32, @backingInt(kind)) << 16) | px;
    if (fonts.get(key)) |f| return f;

    const data: []const u8 = switch (kind) {
        .regular => assets.inter_regular,
        .semibold => assets.inter_semibold,
        .bold => assets.inter_bold,
        // Headings and numbers use the monospace: this is an instrument, not a landing page
        .display, .mono_bold => assets.mono_bold,
        .mono => assets.mono_medium,
        .icon => assets.lucide,
    };
    const cps: []c_int = if (kind == .icon) &icon_codepoints else text_codepoints[0..text_codepoint_count];
    const f = c.LoadFontFromMemory(".ttf", data.ptr, @intCast(data.len), @intCast(px), cps.ptr, @intCast(cps.len));
    c.SetTextureFilter(f.texture, c.TEXTURE_FILTER_BILINEAR);
    fonts.put(gpa, key, f) catch {};
    return f;
}

/// Font atlases are built for one scale; call when `scale` changes.
pub fn flushFonts() void {
    var it = fonts.valueIterator();
    while (it.next()) |f| c.UnloadFont(f.*);
    fonts.clearRetainingCapacity();
}

// ── Shader ──────────────────────────────────────────────────────────────────

const vertex_shader =
    \\#version 330
    \\in vec3 vertexPosition;
    \\in vec2 vertexTexCoord;
    \\in vec3 vertexNormal;
    \\in vec4 vertexColor;
    \\uniform mat4 mvp;
    \\out vec2 fragTexCoord;
    \\out vec4 fragColor;
    \\out vec3 fragParams;
    \\void main() {
    \\    fragTexCoord = vertexTexCoord;
    \\    fragColor = vertexColor;
    \\    fragParams = vertexNormal;
    \\    gl_Position = mvp * vec4(vertexPosition, 1.0);
    \\}
;

// fragParams = (half width, half height, packed radius/softness/thickness).
// x == 0 means a regular raylib draw (text, lines, rings): plain textured quad.
// x < 0 means a textured shape: the texture is masked by the rounded rect.
const fragment_shader =
    \\#version 330
    \\in vec2 fragTexCoord;
    \\in vec4 fragColor;
    \\in vec3 fragParams;
    \\uniform sampler2D texture0;
    \\uniform vec4 colDiffuse;
    \\uniform float uScale;
    \\out vec4 finalColor;
    \\float sdRoundBox(vec2 p, vec2 b, float r) {
    \\    vec2 q = abs(p) - b + r;
    \\    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
    \\}
    \\void main() {
    \\    if (fragParams.x == 0.0) {
    \\        finalColor = texture(texture0, fragTexCoord) * colDiffuse * fragColor;
    \\        return;
    \\    }
    \\    vec2 halfSize = vec2(abs(fragParams.x), fragParams.y);
    \\    float p = fragParams.z;
    \\    float t = floor(p / 262144.0); p -= t * 262144.0;
    \\    float s = floor(p / 1024.0);
    \\    float r = min(p - s * 1024.0, min(halfSize.x, halfSize.y));
    \\    vec4 base = fragColor;
    \\    vec2 local = fragTexCoord;
    \\    if (fragParams.x < 0.0) {
    \\        local = (fragTexCoord - 0.5) * 2.0 * halfSize;
    \\        base *= texture(texture0, fragTexCoord);
    \\    }
    \\    float d = sdRoundBox(local, halfSize, r);
    \\    if (t > 0.0) d = abs(d + t * 0.5) - t * 0.5;
    \\    float a = s > 0.0 ? 1.0 - smoothstep(-s, s, d) : clamp(0.5 - d * uScale, 0.0, 1.0);
    \\    finalColor = vec4(base.rgb, base.a * a);
    \\}
;

var shader: c.Shader = undefined;
var scale_loc: c_int = -1;

// ── Lifecycle ───────────────────────────────────────────────────────────────

pub fn init() void {
    initCodepoints();
    shader = c.LoadShaderFromMemory(vertex_shader, fragment_shader);
    scale_loc = c.GetShaderLocation(shader, "uScale");
}

pub fn deinit() void {
    flushFonts();
    c.UnloadShader(shader);
    anims.deinit(gpa);
    fonts.deinit(gpa);
}

pub fn beginFrame() void {
    dt = @min(c.GetFrameTime(), 0.1);
    time += dt;
    colors = theme.Colors.lerp(colors, target_colors, if (animations) 1 - @exp(-10 * dt) else 1);

    screen = .{ .w = @as(f32, @floatFromInt(c.GetScreenWidth())) / scale, .h = @as(f32, @floatFromInt(c.GetScreenHeight())) / scale };
    const m = c.GetMousePosition();
    mouse = .{ .x = m.x / scale, .y = m.y / scale };
    mouse_pressed = c.IsMouseButtonPressed(c.MOUSE_BUTTON_LEFT);
    mouse_released = c.IsMouseButtonReleased(c.MOUSE_BUTTON_LEFT);
    mouse_down = c.IsMouseButtonDown(c.MOUSE_BUTTON_LEFT);
    right_pressed = c.IsMouseButtonPressed(c.MOUSE_BUTTON_RIGHT);
    wheel = c.GetMouseWheelMove();
    wheel_consumed = false;
    double_click = false;
    if (mouse_pressed) {
        double_click = time - last_click_time < 0.35;
        last_click_time = time;
    }

    hot = hot_next;
    hot_next = 0;
    focus_claimed = false;
    want_cursor = c.MOUSE_CURSOR_DEFAULT;
    layer = Layer.base;

    blockers = blockers_next;
    blocker_count = blocker_next_count;
    blocker_next_count = 0;

    c.BeginDrawing();
    c.ClearBackground(toColor(colors.bg));
    c.BeginMode2D(.{ .offset = .{ .x = 0, .y = 0 }, .target = .{ .x = 0, .y = 0 }, .rotation = 0, .zoom = scale });
    c.BeginShaderMode(shader);
    c.SetShaderValue(shader, scale_loc, &scale, c.SHADER_UNIFORM_FLOAT);
}

/// Set to capture the next frame to a PNG (development screenshots)
pub var screenshot_path: ?[:0]const u8 = null;

pub fn endFrame() void {
    c.EndShaderMode();
    c.EndMode2D();
    if (screenshot_path) |p| {
        c.TakeScreenshot(p.ptr);
        screenshot_path = null;
    }
    c.EndDrawing();

    if (mouse_released) active = 0;
    // Clicking on empty space drops keyboard focus
    if (mouse_pressed and !focus_claimed) focus = 0;
    c.SetMouseCursor(want_cursor);
}

// ── Input helpers ───────────────────────────────────────────────────────────

fn blockedForLayer(p: Vec2) bool {
    for (blockers[0..blocker_count]) |b| {
        if (b.layer > layer and b.rect.contains(p)) return true;
    }
    return false;
}

/// Registers a rect that blocks mouse input for lower layers (next frame on).
pub fn block(r: Rect) void {
    if (blocker_next_count < blockers_next.len) {
        blockers_next[blocker_next_count] = .{ .rect = r, .layer = layer };
        blocker_next_count += 1;
    }
}

pub fn mouseIn(r: Rect) bool {
    if (!r.contains(mouse)) return false;
    if (clip_depth > 0 and !clip_stack[clip_depth - 1].contains(mouse)) return false;
    return !blockedForLayer(mouse);
}

pub fn clickedOutside(r: Rect) bool {
    return mouse_pressed and !r.contains(mouse);
}

pub fn mousePressed() bool {
    return mouse_pressed;
}

pub fn mouseReleased() bool {
    return mouse_released;
}

pub fn mouseDown() bool {
    return mouse_down;
}

pub fn rightPressed() bool {
    return right_pressed;
}

pub fn setCursor(cursor: c_int) void {
    want_cursor = cursor;
}

pub const Interaction = struct {
    hovered: bool = false,
    held: bool = false,
    clicked: bool = false,
    right_clicked: bool = false,
    double_clicked: bool = false,
    pressed: bool = false,
    /// 0..1 animated hover/press amounts, handy for styling
    hover_t: f32 = 0,
    press_t: f32 = 0,
};

pub fn interact(key: u64, r: Rect) Interaction {
    return interactOpts(key, r, true);
}

pub fn interactOpts(key: u64, r: Rect, enabled: bool) Interaction {
    var out: Interaction = .{};
    const inside = enabled and mouseIn(r);
    if (inside) hot_next = key;
    out.hovered = inside and hot == key;
    if (out.hovered) {
        want_cursor = c.MOUSE_CURSOR_POINTING_HAND;
        if (mouse_pressed) {
            active = key;
            out.pressed = true;
            out.double_clicked = double_click;
        }
        if (right_pressed) out.right_clicked = true;
    }
    out.held = active == key and mouse_down;
    out.clicked = mouse_released and active == key and out.hovered;
    out.hover_t = anim(sub(key, 0x1_0000_0001), if (out.hovered) 1 else 0, 16);
    out.press_t = anim(sub(key, 0x1_0000_0002), if (out.held) 1 else 0, 28);
    return out;
}

/// Animated 0..1 "the mouse is over this area", ignoring which widget is hot.
/// Use it for containers whose children are widgets too (a pad and its "more"
/// button): `interact` only reports hover for the topmost widget, so the
/// container would stop counting as hovered the moment a child takes over.
pub fn hoverArea(key: u64, r: Rect) f32 {
    return anim(sub(key, 0x1_0000_0003), if (mouseIn(r)) 1 else 0, 16);
}

pub fn claimFocus(key: u64) void {
    focus = key;
    focus_claimed = true;
}

pub fn keepFocus(key: u64) void {
    if (focus == key) focus_claimed = true;
}

/// True while a text field or key-capture widget owns the keyboard
pub fn keyboardCaptured() bool {
    return focus != 0;
}

pub fn consumeWheel() f32 {
    if (wheel_consumed) return 0;
    wheel_consumed = true;
    return wheel;
}

// ── Clipping and alpha ──────────────────────────────────────────────────────

pub fn pushClip(r: Rect) void {
    const clipped = if (clip_depth > 0) r.intersect(clip_stack[clip_depth - 1]) else r;
    clip_stack[clip_depth] = clipped;
    clip_depth += 1;
    applyClip(clipped);
}

pub fn popClip() void {
    clip_depth -= 1;
    if (clip_depth > 0) {
        applyClip(clip_stack[clip_depth - 1]);
    } else {
        c.EndScissorMode();
    }
}

fn applyClip(r: Rect) void {
    c.BeginScissorMode(
        @intFromFloat(@floor(r.x * scale)),
        @intFromFloat(@floor(r.y * scale)),
        @intFromFloat(@ceil(r.w * scale)),
        @intFromFloat(@ceil(r.h * scale)),
    );
}

pub fn currentClip() Rect {
    return if (clip_depth > 0) clip_stack[clip_depth - 1] else screen;
}

pub fn pushAlpha(a: f32) void {
    alpha_stack[alpha_depth] = global_alpha;
    alpha_depth += 1;
    global_alpha *= a;
}

pub fn popAlpha() void {
    alpha_depth -= 1;
    global_alpha = alpha_stack[alpha_depth];
}

/// Shifts everything drawn until `popTranslate` (used for page transitions)
pub fn pushTranslate(dx: f32, dy: f32) void {
    c.rlDrawRenderBatchActive();
    c.rlPushMatrix();
    c.rlTranslatef(dx, dy, 0);
}

pub fn popTranslate() void {
    c.rlDrawRenderBatchActive();
    c.rlPopMatrix();
}

// ── Drawing primitives ──────────────────────────────────────────────────────

pub fn toColor(col: Rgba) c.Color {
    const a = std.math.clamp(col.a * global_alpha, 0, 1);
    return .{
        .r = @intFromFloat(std.math.clamp(col.r, 0, 1) * 255),
        .g = @intFromFloat(std.math.clamp(col.g, 0, 1) * 255),
        .b = @intFromFloat(std.math.clamp(col.b, 0, 1) * 255),
        .a = @intFromFloat(a * 255),
    };
}

fn snap(v: f32) f32 {
    return @round(v * scale) / scale;
}

const Corners = struct { tl: c.Color, bl: c.Color, br: c.Color, tr: c.Color };

fn sdfQuad(r: Rect, radius: f32, soft: f32, thickness: f32, corners: Corners, texture: ?c.Texture) void {
    if (r.w <= 0 or r.h <= 0) return;
    const half_w = r.w / 2;
    const half_h = r.h / 2;
    const rad = @min(@max(radius, 0), 1023);
    const packed_params = @round(rad) + 1024 * @round(@min(soft, 255)) + 262144 * @round(@min(thickness, 63));
    const pad = soft;
    const x0 = r.x - pad;
    const y0 = r.y - pad;
    const x1 = r.right() + pad;
    const y1 = r.bottom() + pad;

    if (texture) |tex| c.rlSetTexture(tex.id) else c.rlSetTexture(c.rlGetTextureIdDefault());
    c.rlBegin(c.RL_QUADS);
    c.rlNormal3f(if (texture != null) -half_w else half_w, half_h, packed_params);

    const lx0: f32 = if (texture != null) 0 else -half_w - pad;
    const ly0: f32 = if (texture != null) 0 else -half_h - pad;
    const lx1: f32 = if (texture != null) 1 else half_w + pad;
    const ly1: f32 = if (texture != null) 1 else half_h + pad;

    c.rlColor4ub(corners.tl.r, corners.tl.g, corners.tl.b, corners.tl.a);
    c.rlTexCoord2f(lx0, ly0);
    c.rlVertex2f(x0, y0);
    c.rlColor4ub(corners.bl.r, corners.bl.g, corners.bl.b, corners.bl.a);
    c.rlTexCoord2f(lx0, ly1);
    c.rlVertex2f(x0, y1);
    c.rlColor4ub(corners.br.r, corners.br.g, corners.br.b, corners.br.a);
    c.rlTexCoord2f(lx1, ly1);
    c.rlVertex2f(x1, y1);
    c.rlColor4ub(corners.tr.r, corners.tr.g, corners.tr.b, corners.tr.a);
    c.rlTexCoord2f(lx1, ly0);
    c.rlVertex2f(x1, y0);

    c.rlEnd();
    c.rlNormal3f(0, 0, 1); // back to "plain raylib draw" for everything else
    c.rlSetTexture(0);
}

fn uniform(col: Rgba) Corners {
    const cc = toColor(col);
    return .{ .tl = cc, .bl = cc, .br = cc, .tr = cc };
}

pub fn rect(r: Rect, radius: f32, col: Rgba) void {
    if (col.a * global_alpha <= 0.001) return;
    sdfQuad(r, radius, 0, 0, uniform(col), null);
}

pub fn rectGradientV(r: Rect, radius: f32, top: Rgba, bottom: Rgba) void {
    const t = toColor(top);
    const b = toColor(bottom);
    sdfQuad(r, radius, 0, 0, .{ .tl = t, .tr = t, .bl = b, .br = b }, null);
}

pub fn rectGradientH(r: Rect, radius: f32, left: Rgba, right_col: Rgba) void {
    const l = toColor(left);
    const rr = toColor(right_col);
    sdfQuad(r, radius, 0, 0, .{ .tl = l, .bl = l, .tr = rr, .br = rr }, null);
}

pub fn border(r: Rect, radius: f32, thickness: f32, col: Rgba) void {
    if (col.a * global_alpha <= 0.001) return;
    sdfQuad(r, radius, 0, @max(1, thickness), uniform(col), null);
}

pub fn shadow(r: Rect, radius: f32, blur: f32, col: Rgba) void {
    if (col.a * global_alpha <= 0.001 or blur < 1) return;
    sdfQuad(r, radius, blur, 0, uniform(col), null);
}

pub fn circle(center: Vec2, radius: f32, col: Rgba) void {
    rect(.{ .x = center.x - radius, .y = center.y - radius, .w = radius * 2, .h = radius * 2 }, radius, col);
}

pub fn glow(center: Vec2, radius: f32, col: Rgba) void {
    shadow(.{ .x = center.x - radius / 2, .y = center.y - radius / 2, .w = radius, .h = radius }, radius / 2, radius / 2, col);
}

pub fn image(tex: c.Texture, r: Rect, radius: f32, tint: Rgba) void {
    sdfQuad(r, radius, 0, 0, uniform(tint), tex);
}

pub fn line(a: Vec2, b: Vec2, thickness: f32, col: Rgba) void {
    c.DrawLineEx(.{ .x = a.x, .y = a.y }, .{ .x = b.x, .y = b.y }, thickness, toColor(col));
}

/// Arc from `start` to `end` degrees (0 = right, clockwise)
pub fn arc(center: Vec2, radius: f32, thickness: f32, start: f32, end: f32, col: Rgba) void {
    c.DrawRing(.{ .x = center.x, .y = center.y }, radius - thickness / 2, radius + thickness / 2, start, end, 48, toColor(col));
}

pub fn spinner(center: Vec2, radius: f32, col: Rgba) void {
    const t = time * 360;
    const sweep = 90 + 60 * @sin(time * 3);
    arc(center, radius, @max(2, radius * 0.22), t, t + sweep, col);
}

// ── Text ────────────────────────────────────────────────────────────────────

pub const Utf8Iter = struct {
    s: []const u8,
    i: usize = 0,

    pub fn next(it: *Utf8Iter) ?u21 {
        if (it.i >= it.s.len) return null;
        const len = std.unicode.utf8ByteSequenceLength(it.s[it.i]) catch {
            it.i += 1;
            return 0xFFFD;
        };
        if (it.i + len > it.s.len) {
            it.i = it.s.len;
            return 0xFFFD;
        }
        const cp = std.unicode.utf8Decode(it.s[it.i..][0..len]) catch {
            it.i += 1;
            return 0xFFFD;
        };
        it.i += len;
        return cp;
    }
};

fn glyphAdvance(f: c.Font, gi: usize) f32 {
    const a = f.glyphs[gi].advanceX;
    return if (a != 0) @floatFromInt(a) else f.recs[gi].width;
}

pub fn measure(str: []const u8, size: f32, kind: FontKind) f32 {
    const f = font(kind, size);
    const k = lineSize(kind, size) / @as(f32, @floatFromInt(f.baseSize));
    var w: f32 = 0;
    var it: Utf8Iter = .{ .s = str };
    while (it.next()) |cp| {
        const gi: usize = @intCast(c.GetGlyphIndex(f, @intCast(cp)));
        w += glyphAdvance(f, gi) * k;
    }
    return w;
}

/// Draws text with its top-left at (x, y). Returns the advance width.
pub fn text(str: []const u8, x: f32, y_in: f32, size_in: f32, kind: FontKind, col: Rgba) f32 {
    const f = font(kind, size_in);
    const size = lineSize(kind, size_in);
    // Keep the glyphs centered on the box callers think they are drawing in
    const y = y_in - (size - size_in) / 2;
    const k = size / @as(f32, @floatFromInt(f.baseSize));
    const cc = toColor(col);
    var pen = x;
    var it: Utf8Iter = .{ .s = str };
    while (it.next()) |cp| {
        const gi: usize = @intCast(c.GetGlyphIndex(f, @intCast(cp)));
        if (cp != ' ' and cp != '\t' and cc.a > 0) {
            c.DrawTextCodepoint(f, @intCast(cp), .{ .x = snap(pen), .y = snap(y) }, size, cc);
        }
        pen += glyphAdvance(f, gi) * k;
    }
    return pen - x;
}

pub const Align = enum { left, center, right };

/// Single line, vertically centered in `r`, cut with "…" if it doesn't fit.
pub fn label(str: []const u8, r: Rect, size: f32, kind: FontKind, col: Rgba, alignment: Align) void {
    const y = r.y + (r.h - size) / 2 - size * 0.02;
    const full = measure(str, size, kind);
    if (full <= r.w) {
        const x = switch (alignment) {
            .left => r.x,
            .center => r.x + (r.w - full) / 2,
            .right => r.right() - full,
        };
        _ = text(str, x, y, size, kind, col);
        return;
    }
    const cut = fitEllipsis(str, r.w, size, kind);
    const w = measure(cut, size, kind) + measure("…", size, kind);
    const x = switch (alignment) {
        .left => r.x,
        .center => r.x + (r.w - w) / 2,
        .right => r.right() - w,
    };
    const adv = text(cut, x, y, size, kind, col);
    _ = text("…", x + adv, y, size, kind, col);
}

/// Longest prefix of `str` that fits in `max_w` together with an ellipsis
fn fitEllipsis(str: []const u8, max_w: f32, size: f32, kind: FontKind) []const u8 {
    const budget = max_w - measure("…", size, kind);
    const f = font(kind, size);
    const k = lineSize(kind, size) / @as(f32, @floatFromInt(f.baseSize));
    var w: f32 = 0;
    var it: Utf8Iter = .{ .s = str };
    var last: usize = 0;
    while (it.next()) |cp| {
        const gi: usize = @intCast(c.GetGlyphIndex(f, @intCast(cp)));
        w += glyphAdvance(f, gi) * k;
        if (w > budget) break;
        last = it.i;
    }
    return std.mem.trimEnd(u8, str[0..last], " ");
}

/// Word-wrapped paragraph. Returns the height used. Pass draw=false to measure.
pub fn paragraph(str: []const u8, r: Rect, size: f32, kind: FontKind, col: Rgba, line_height: f32, draw: bool) f32 {
    var y = r.y;
    var lines = std.mem.splitScalar(u8, str, '\n');
    while (lines.next()) |para| {
        var start: usize = 0;
        while (start <= para.len) {
            // Greedily take words while they fit
            var end = start;
            var best = start;
            while (end < para.len) {
                var next_end = end;
                while (next_end < para.len and para[next_end] == ' ') next_end += 1;
                while (next_end < para.len and para[next_end] != ' ') next_end += 1;
                if (measure(para[start..next_end], size, kind) > r.w and best > start) break;
                best = next_end;
                end = next_end;
            }
            if (best == start) best = para.len; // a single word wider than the box
            if (draw) _ = text(std.mem.trim(u8, para[start..best], " "), r.x, y, size, kind, col);
            y += size * line_height;
            start = best;
            while (start < para.len and para[start] == ' ') start += 1;
            if (start >= para.len) break;
        }
    }
    return y - r.y;
}

pub fn icon(cp: u21, center: Vec2, size: f32, col: Rgba) void {
    const f = font(.icon, size);
    const k = size / @as(f32, @floatFromInt(f.baseSize));
    const gi: usize = @intCast(c.GetGlyphIndex(f, @intCast(cp)));
    const g = f.glyphs[gi];
    const rec = f.recs[gi];
    // Center the glyph's ink box, not its advance box
    const ink_x = @as(f32, @floatFromInt(g.offsetX)) * k + rec.width * k / 2;
    const ink_y = @as(f32, @floatFromInt(g.offsetY)) * k + rec.height * k / 2;
    c.DrawTextCodepoint(f, @intCast(cp), .{ .x = snap(center.x - ink_x), .y = snap(center.y - ink_y) }, size, toColor(col));
}

pub fn iconIn(cp: u21, r: Rect, size: f32, col: Rgba) void {
    icon(cp, r.center(), size, col);
}

// ── Text fields ─────────────────────────────────────────────────────────────

pub const TextField = struct {
    buf: [512]u8 = undefined,
    len: usize = 0,
    cursor: usize = 0,
    anchor: usize = 0, // selection is [min(anchor,cursor), max(...))
    scroll: f32 = 0,

    pub fn text(f: *const TextField) []const u8 {
        return f.buf[0..f.len];
    }

    pub fn set(f: *TextField, s: []const u8) void {
        const n = @min(s.len, f.buf.len);
        @memcpy(f.buf[0..n], s[0..n]);
        f.len = n;
        f.cursor = n;
        f.anchor = n;
    }

    pub fn clear(f: *TextField) void {
        f.len = 0;
        f.cursor = 0;
        f.anchor = 0;
    }

    fn selection(f: *const TextField) struct { usize, usize } {
        return .{ @min(f.anchor, f.cursor), @max(f.anchor, f.cursor) };
    }

    fn deleteSelection(f: *TextField) bool {
        const a, const b = f.selection();
        if (a == b) return false;
        std.mem.copyForwards(u8, f.buf[a..], f.buf[b..f.len]);
        f.len -= b - a;
        f.cursor = a;
        f.anchor = a;
        return true;
    }

    fn insert(f: *TextField, s: []const u8) void {
        _ = f.deleteSelection();
        const n = @min(s.len, f.buf.len - f.len);
        std.mem.copyBackwards(u8, f.buf[f.cursor + n .. f.len + n], f.buf[f.cursor..f.len]);
        @memcpy(f.buf[f.cursor..][0..n], s[0..n]);
        f.len += n;
        f.cursor += n;
        f.anchor = f.cursor;
    }

    fn prevBoundary(f: *const TextField, i: usize) usize {
        var j = i;
        while (j > 0) {
            j -= 1;
            if (f.buf[j] & 0xC0 != 0x80) break;
        }
        return j;
    }

    fn nextBoundary(f: *const TextField, i: usize) usize {
        var j = i;
        if (j < f.len) j += 1;
        while (j < f.len and f.buf[j] & 0xC0 == 0x80) j += 1;
        return j;
    }

    fn wordLeft(f: *const TextField, i: usize) usize {
        var j = i;
        while (j > 0 and f.buf[j - 1] == ' ') j -= 1;
        while (j > 0 and f.buf[j - 1] != ' ') j -= 1;
        return j;
    }

    fn wordRight(f: *const TextField, i: usize) usize {
        var j = i;
        while (j < f.len and f.buf[j] == ' ') j += 1;
        while (j < f.len and f.buf[j] != ' ') j += 1;
        return j;
    }
};

pub const TextInputOptions = struct {
    placeholder: []const u8 = "",
    icon: ?u21 = null,
    clearable: bool = true,
    size: f32 = 14,
    autofocus: bool = false,
};

pub const TextInputResult = struct {
    changed: bool = false,
    submitted: bool = false,
    focused: bool = false,
};

fn keyRepeat(key: c_int) bool {
    return c.IsKeyPressed(key) or c.IsKeyPressedRepeat(key);
}

fn ctrlDown() bool {
    return c.IsKeyDown(c.KEY_LEFT_CONTROL) or c.IsKeyDown(c.KEY_RIGHT_CONTROL);
}

fn shiftDown() bool {
    return c.IsKeyDown(c.KEY_LEFT_SHIFT) or c.IsKeyDown(c.KEY_RIGHT_SHIFT);
}

pub fn textInput(key: u64, r: Rect, field: *TextField, opts: TextInputOptions) TextInputResult {
    var out: TextInputResult = .{};
    const hovered = mouseIn(r);
    if (hovered) {
        hot_next = key;
        want_cursor = c.MOUSE_CURSOR_IBEAM;
    }
    if (opts.autofocus and focus == 0) claimFocus(key);

    var text_x = r.x + 12;
    if (opts.icon != null) text_x += 22;
    var text_right = r.right() - 12;
    const show_clear = opts.clearable and field.len > 0;
    if (show_clear) text_right -= 22;
    const text_w = @max(10, text_right - text_x);

    // Clear button
    if (show_clear) {
        const clear_rect: Rect = .{ .x = r.right() - 32, .y = r.y + (r.h - 22) / 2, .w = 22, .h = 22 };
        const ci = interact(sub(key, 99), clear_rect);
        if (ci.clicked) {
            field.clear();
            out.changed = true;
            claimFocus(key);
        }
        rect(clear_rect.inset(2), radius_sm, colors.text_faint.alpha(ci.hover_t * 0.25));
        icon(icons.x, clear_rect.center(), 12, colors.text_muted);
    }

    if (hovered and mouse_pressed and hot == key) {
        claimFocus(key);
        active = key;
        field.cursor = indexAt(field, mouse.x - text_x + field.scroll, opts.size);
        if (!shiftDown()) field.anchor = field.cursor;
        if (double_click) {
            field.anchor = field.wordLeft(field.cursor);
            field.cursor = field.wordRight(field.cursor);
        }
    } else if (active == key and mouse_down) {
        field.cursor = indexAt(field, mouse.x - text_x + field.scroll, opts.size); // drag-select
    }

    const focused = focus == key;
    if (focused) {
        keepFocus(key);
        out.focused = true;
        // Typed characters
        var ch = c.GetCharPressed();
        while (ch > 0) : (ch = c.GetCharPressed()) {
            if (ch < 32) continue;
            var tmp: [4]u8 = undefined;
            const n = std.unicode.utf8Encode(@intCast(ch), &tmp) catch continue;
            field.insert(tmp[0..n]);
            out.changed = true;
        }
        const ctrl = ctrlDown();
        const shift = shiftDown();
        if (keyRepeat(c.KEY_BACKSPACE)) {
            if (!field.deleteSelection() and field.cursor > 0) {
                field.anchor = if (ctrl) field.wordLeft(field.cursor) else field.prevBoundary(field.cursor);
                _ = field.deleteSelection();
            }
            out.changed = true;
        }
        if (keyRepeat(c.KEY_DELETE)) {
            if (!field.deleteSelection() and field.cursor < field.len) {
                field.anchor = if (ctrl) field.wordRight(field.cursor) else field.nextBoundary(field.cursor);
                _ = field.deleteSelection();
            }
            out.changed = true;
        }
        if (keyRepeat(c.KEY_LEFT)) {
            field.cursor = if (ctrl) field.wordLeft(field.cursor) else field.prevBoundary(field.cursor);
            if (!shift) field.anchor = field.cursor;
        }
        if (keyRepeat(c.KEY_RIGHT)) {
            field.cursor = if (ctrl) field.wordRight(field.cursor) else field.nextBoundary(field.cursor);
            if (!shift) field.anchor = field.cursor;
        }
        if (c.IsKeyPressed(c.KEY_HOME)) {
            field.cursor = 0;
            if (!shift) field.anchor = 0;
        }
        if (c.IsKeyPressed(c.KEY_END)) {
            field.cursor = field.len;
            if (!shift) field.anchor = field.len;
        }
        if (ctrl and c.IsKeyPressed(c.KEY_A)) {
            field.anchor = 0;
            field.cursor = field.len;
        }
        if (ctrl and (c.IsKeyPressed(c.KEY_C) or c.IsKeyPressed(c.KEY_X))) {
            const a, const b = field.selection();
            if (a != b) {
                var tmp: [513]u8 = undefined;
                @memcpy(tmp[0 .. b - a], field.buf[a..b]);
                tmp[b - a] = 0;
                c.SetClipboardText(@ptrCast(&tmp));
                if (c.IsKeyPressed(c.KEY_X)) {
                    _ = field.deleteSelection();
                    out.changed = true;
                }
            }
        }
        if (ctrl and c.IsKeyPressed(c.KEY_V)) {
            if (c.GetClipboardText()) |clip| {
                const s = std.mem.span(clip);
                // Paste as a single line
                for (s) |b| {
                    const one = [1]u8{if (b == '\n' or b == '\r' or b == '\t') ' ' else b};
                    field.insert(&one);
                }
                out.changed = true;
            }
        }
        if (c.IsKeyPressed(c.KEY_ENTER) or c.IsKeyPressed(c.KEY_KP_ENTER)) out.submitted = true;
        if (c.IsKeyPressed(c.KEY_ESCAPE)) focus = 0;
    }

    // Keep the cursor visible
    const cursor_x = measure(field.buf[0..field.cursor], opts.size, .regular);
    if (cursor_x - field.scroll > text_w) field.scroll = cursor_x - text_w;
    if (cursor_x - field.scroll < 0) field.scroll = cursor_x;
    if (measure(field.text(), opts.size, .regular) < text_w) field.scroll = 0;

    // Drawing
    const focus_t = anim(sub(key, 3), if (focused) 1 else 0, 14);
    const hover_t = anim(sub(key, 4), if (hovered) 1 else 0, 14);
    rect(r, radius_md, Rgba.lerp(colors.bg, colors.surface, 0.5 + hover_t * 0.5));
    border(r, radius_md, 1, Rgba.lerp(Rgba.lerp(colors.border, colors.text_faint, hover_t * 0.6), colors.accent, focus_t));
    if (opts.icon) |ic| icon(ic, .{ .x = r.x + 20, .y = r.y + r.h / 2 }, 15, Rgba.lerp(colors.text_faint, colors.accent, focus_t));

    const text_rect: Rect = .{ .x = text_x, .y = r.y, .w = text_w, .h = r.h };
    pushClip(text_rect.grow(1));
    const ty = r.y + (r.h - opts.size) / 2 - opts.size * 0.02;
    if (field.len == 0) {
        _ = text(opts.placeholder, text_x, ty, opts.size, .regular, colors.text_faint);
    } else {
        const a, const b = field.selection();
        if (focused and a != b) {
            const sx = measure(field.buf[0..a], opts.size, .regular) - field.scroll;
            const sw = measure(field.buf[a..b], opts.size, .regular);
            rect(.{ .x = text_x + sx, .y = r.y + 7, .w = sw, .h = r.h - 14 }, 1, colors.accent.alpha(0.35));
        }
        _ = text(field.text(), text_x - field.scroll, ty, opts.size, .regular, colors.text);
    }
    if (focused and @mod(time, 1.0) < 0.6) {
        rect(.{ .x = text_x + cursor_x - field.scroll, .y = r.y + 8, .w = 2, .h = r.h - 16 }, 0, colors.accent);
    }
    popClip();
    return out;
}

fn indexAt(field: *const TextField, x: f32, size: f32) usize {
    var i: usize = 0;
    var w: f32 = 0;
    while (i < field.len) {
        const next = field.nextBoundary(i);
        const cw = measure(field.buf[i..next], size, .regular);
        if (w + cw / 2 > x) return i;
        w += cw;
        i = next;
    }
    return field.len;
}

// ── Widgets ─────────────────────────────────────────────────────────────────

pub const ButtonStyle = enum { primary, secondary, ghost, danger, subtle };

pub const ButtonOptions = struct {
    icon: ?u21 = null,
    style: ButtonStyle = .secondary,
    disabled: bool = false,
    loading: bool = false,
    size: f32 = 13,
    radius: f32 = radius_md,
    tooltip: ?[]const u8 = null,
};

pub fn button(key: u64, r: Rect, text_str: []const u8, opts: ButtonOptions) bool {
    const in = interactOpts(key, r, !opts.disabled and !opts.loading);
    const br = r.offset(0, in.press_t * 1);
    const dis: f32 = if (opts.disabled) 0.4 else 1;
    pushAlpha(dis);
    defer popAlpha();
    const rad = @min(opts.radius, radius_md);

    var fg = colors.text;
    switch (opts.style) {
        .primary => {
            rect(br, rad, colors.accent.shade(in.hover_t * 0.1 - in.press_t * 0.1));
            fg = colors.accent_text;
        },
        .danger => {
            rect(br, rad, colors.danger.alpha(0.1 + in.hover_t * 0.1));
            border(br, rad, 1, colors.danger.alpha(0.55 + in.hover_t * 0.3));
            fg = colors.danger;
        },
        .secondary => {
            rect(br, rad, Rgba.lerp(colors.surface, colors.surface_hover, in.hover_t));
            border(br, rad, 1, Rgba.lerp(colors.border, colors.text_faint, in.hover_t));
        },
        .ghost => {
            rect(br, rad, colors.text.alpha(in.hover_t * 0.06));
            fg = Rgba.lerp(colors.text_muted, colors.text, in.hover_t);
        },
        .subtle => {
            rect(br, rad, colors.accent.alpha(in.hover_t * 0.08));
            border(br, rad, 1, colors.accent.alpha(0.45 + in.hover_t * 0.35));
            fg = colors.accent;
        },
    }

    const tw = measure(text_str, opts.size, .semibold);
    const icon_w: f32 = if (opts.icon != null or opts.loading) opts.size + 2 + (if (text_str.len > 0) @as(f32, 7) else 0) else 0;
    const total = tw + icon_w;
    var x = br.x + (br.w - total) / 2;
    if (opts.loading) {
        spinner(.{ .x = x + opts.size / 2 + 1, .y = br.y + br.h / 2 }, opts.size * 0.45, fg);
        x += icon_w;
    } else if (opts.icon) |ic| {
        icon(ic, .{ .x = x + opts.size / 2 + 1, .y = br.y + br.h / 2 }, opts.size + 1, fg);
        x += icon_w;
    }
    if (text_str.len > 0) label(text_str, .{ .x = x, .y = br.y, .w = br.right() - x, .h = br.h }, opts.size, .semibold, fg, .left);
    if (opts.tooltip) |tip| {
        if (in.hovered) tooltip(key, tip);
    }
    return in.clicked;
}

pub const IconButtonOptions = struct {
    tooltip: ?[]const u8 = null,
    active: bool = false,
    color: ?Rgba = null,
    size: f32 = 18,
    disabled: bool = false,
    radius: f32 = 8,
    background: bool = false,
};

pub fn iconButton(key: u64, r: Rect, ic: u21, opts: IconButtonOptions) bool {
    const in = interactOpts(key, r, !opts.disabled);
    const act_t = anim(sub(key, 7), if (opts.active) 1 else 0, 14);
    pushAlpha(if (opts.disabled) 0.35 else 1);
    defer popAlpha();
    const rad = @min(opts.radius, radius_md);
    const br = r.offset(0, in.press_t);
    if (opts.background) {
        rect(br, rad, colors.surface);
        border(br, rad, 1, Rgba.lerp(colors.border, colors.accent.alpha(0.8), act_t));
    }
    rect(br, rad, colors.text.alpha(in.hover_t * 0.07));
    if (act_t > 0.01 and !opts.background) rect(br, rad, colors.accent.alpha(0.12 * act_t));
    const base = opts.color orelse colors.text_muted;
    const col = Rgba.lerp(Rgba.lerp(base, colors.text, in.hover_t), colors.accent, act_t);
    icon(ic, br.center(), @min(opts.size, 17), col);
    if (opts.tooltip) |tip| {
        if (in.hovered) tooltip(key, tip);
    }
    return in.clicked;
}

/// A hardware-style slide switch
pub fn toggle(key: u64, r: Rect, value: *bool) bool {
    const track: Rect = .{ .x = r.right() - 38, .y = r.y + (r.h - 20) / 2, .w = 38, .h = 20 };
    const in = interact(key, track.grow(4));
    var changed = false;
    if (in.clicked) {
        value.* = !value.*;
        changed = true;
    }
    const t = anim(sub(key, 5), if (value.*) 1 else 0, 18);
    rect(track, radius_sm, Rgba.lerp(colors.bg, colors.accent.alpha(0.9), t));
    border(track, radius_sm, 1, Rgba.lerp(colors.border, colors.accent, t));
    const knob: Rect = .{ .x = track.x + 3 + t * 17, .y = track.y + 3, .w = 15, .h = 14 };
    rect(knob, 2, Rgba.lerp(colors.text_muted, colors.accent_text, t).shade(in.hover_t * 0.15));
    return changed;
}

/// Thin track with a fader-cap knob
pub fn slider(key: u64, r: Rect, value: *f32, min: f32, max: f32) bool {
    const track: Rect = .{ .x = r.x + 8, .y = r.y + r.h / 2 - 1.5, .w = r.w - 16, .h = 3 };
    const in = interact(key, r);
    var changed = false;
    if (in.held) {
        const t = std.math.clamp((mouse.x - track.x) / track.w, 0, 1);
        const v = min + t * (max - min);
        if (v != value.*) {
            value.* = v;
            changed = true;
        }
    }
    if (in.hovered) {
        const wd = consumeWheel();
        if (wd != 0) {
            value.* = std.math.clamp(value.* + wd * (max - min) * 0.05, min, max);
            changed = true;
        }
    }
    const t = std.math.clamp((value.* - min) / (max - min), 0, 1);
    const shown = anim(sub(key, 6), t, 30);
    rect(track, 1, colors.border);
    rect(.{ .x = track.x, .y = track.y, .w = @max(2, track.w * shown), .h = track.h }, 1, colors.accent);
    const kx = track.x + track.w * shown;
    const cap: Rect = .{ .x = kx - 5, .y = track.y - 7, .w = 10, .h = 17 };
    rect(cap, 2, Rgba.lerp(colors.text_muted, colors.text, @max(in.hover_t, in.press_t)));
    rect(.{ .x = cap.x + 2, .y = cap.y + 8, .w = 6, .h = 1 }, 0, colors.bg);
    return changed;
}

pub const Segment = struct {
    label: []const u8,
    icon: ?u21 = null,
};

pub fn segmented(key: u64, r: Rect, items: []const Segment, selected: *usize) bool {
    rect(r, radius_md, colors.surface);
    border(r, radius_md, 1, colors.border);
    const inner = r.inset(3);
    const w = inner.w / @as(f32, @floatFromInt(items.len));
    const pos = anim(sub(key, 8), @floatFromInt(selected.*), 22);
    const pill: Rect = .{ .x = inner.x + pos * w, .y = inner.y, .w = w, .h = inner.h };
    rect(pill, radius_sm, colors.elevated.shade(if (dark) 0.06 else -0.04));
    rect(.{ .x = pill.x + 6, .y = pill.bottom() - 2, .w = pill.w - 12, .h = 2 }, 1, colors.accent);
    var changed = false;
    for (items, 0..) |item, i| {
        const cell: Rect = .{ .x = inner.x + @as(f32, @floatFromInt(i)) * w, .y = inner.y, .w = w, .h = inner.h };
        const in = interact(sub(key, 100 + i), cell);
        if (in.clicked and selected.* != i) {
            selected.* = i;
            changed = true;
        }
        const sel_t = 1 - @min(1, @abs(pos - @as(f32, @floatFromInt(i))));
        const fg = Rgba.lerp(Rgba.lerp(colors.text_faint, colors.text_muted, in.hover_t), colors.text, sel_t);
        const tw = measure(item.label, 12, .semibold) + (if (item.icon != null) @as(f32, 20) else 0);
        var x = cell.x + (cell.w - tw) / 2;
        if (item.icon) |ic| {
            icon(ic, .{ .x = x + 7, .y = cell.y + cell.h / 2 }, 14, fg);
            x += 20;
        }
        label(item.label, .{ .x = x, .y = cell.y, .w = cell.right() - x, .h = cell.h }, 12, .semibold, fg, .left);
    }
    return changed;
}

pub fn progressBar(r: Rect, t: f32, col: Rgba) void {
    rect(r, 1, colors.border.alpha(0.8));
    if (t < 0) {
        // Indeterminate: a sliding chunk
        const chunk = r.w * 0.3;
        const x = r.x + @mod(time * 0.8, 1.3) * r.w - chunk;
        pushClip(r);
        rect(.{ .x = x, .y = r.y, .w = chunk, .h = r.h }, 1, col);
        popClip();
        return;
    }
    const w = r.w * std.math.clamp(t, 0, 1);
    if (w > 0.5) rect(.{ .x = r.x, .y = r.y, .w = w, .h = r.h }, 1, col);
}

/// Shimmering placeholder used while content loads
pub fn skeleton(r: Rect, radius: f32) void {
    rect(r, radius, colors.surface);
    const sweep = @mod(time * 0.7, 1.6) - 0.3;
    const band_x = screen.w * sweep;
    pushClip(r);
    rectGradientH(.{ .x = band_x - 120, .y = r.y, .w = 120, .h = r.h }, 0, colors.surface_hover.alpha(0), colors.surface_hover);
    rectGradientH(.{ .x = band_x, .y = r.y, .w = 120, .h = r.h }, 0, colors.surface_hover, colors.surface_hover.alpha(0));
    popClip();
}

pub fn badge(r: Rect, text_str: []const u8, bg: Rgba, fg: Rgba) void {
    rect(r, radius_sm, bg);
    label(text_str, r, 11, .mono, fg, .center);
}

/// Hotkey label in a thin frame, e.g. on pads and menus
pub fn keycap(x: f32, y: f32, text_str: []const u8) f32 {
    const w = @max(20, measure(text_str, 11, .mono) + 10);
    const r: Rect = .{ .x = x, .y = y, .w = w, .h = 18 };
    border(r, radius_sm, 1, colors.text_faint.alpha(0.6));
    label(text_str, r, 11, .mono, colors.text_muted, .center);
    return w;
}

// ── Scroll areas ────────────────────────────────────────────────────────────

const ScrollState = struct {
    offset: f32 = 0,
    target: f32 = 0,
    content: f32 = 0,
    bar_t: f32 = 0,
    dragging: bool = false,
    drag_from: f32 = 0,
};

var scrolls: std.AutoHashMapUnmanaged(u64, ScrollState) = .empty;
var scroll_stack: [8]struct { key: u64, view: Rect } = undefined;
var scroll_depth: usize = 0;

/// Begins a vertically scrolling region. Lay content out starting at the
/// returned y; call `endScroll` with the content height.
pub fn beginScroll(key: u64, view: Rect) f32 {
    const gop = scrolls.getOrPut(gpa, key) catch unreachable;
    if (!gop.found_existing) gop.value_ptr.* = .{};
    scroll_stack[scroll_depth] = .{ .key = key, .view = view };
    scroll_depth += 1;
    pushClip(view);
    return view.y - gop.value_ptr.offset;
}

pub fn endScroll(content_height: f32) void {
    scroll_depth -= 1;
    const entry = scroll_stack[scroll_depth];
    popClip();
    const s = scrolls.getPtr(entry.key).?;
    const view = entry.view;
    s.content = content_height;
    const max_scroll = @max(0, content_height - view.h);

    if (mouseIn(view)) {
        const wd = consumeWheel();
        if (wd != 0) s.target -= wd * 90;
    }

    // Scrollbar
    const show = max_scroll > 0;
    const track: Rect = .{ .x = view.right() - 8, .y = view.y + 4, .w = 6, .h = view.h - 8 };
    const thumb_h = @max(30, track.h * view.h / @max(content_height, 1));
    const thumb_y = track.y + (track.h - thumb_h) * (if (max_scroll > 0) s.offset / max_scroll else 0);
    const thumb: Rect = .{ .x = track.x, .y = thumb_y, .w = track.w, .h = thumb_h };
    if (show) {
        const in = interact(sub(entry.key, 50), track.grow(4));
        if (in.pressed) {
            s.dragging = true;
            s.drag_from = mouse.y - thumb_y;
        }
        if (s.dragging) {
            if (!mouse_down) s.dragging = false else {
                const t = (mouse.y - s.drag_from - track.y) / @max(1, track.h - thumb_h);
                s.target = t * max_scroll;
            }
        }
        const near = mouseIn(view.grow(0)) or s.dragging;
        s.bar_t = anim(sub(entry.key, 51), if (near) 1 else 0.0, 8);
        if (s.bar_t > 0.01) rect(thumb, 3, colors.text_faint.alpha(0.35 * s.bar_t + in.hover_t * 0.3));
    }

    s.target = std.math.clamp(s.target, 0, max_scroll);
    if (animations) {
        s.offset += (s.target - s.offset) * (1 - @exp(-16 * dt));
        if (@abs(s.target - s.offset) < 0.3) s.offset = s.target;
    } else s.offset = s.target;
    s.offset = std.math.clamp(s.offset, 0, max_scroll);
}

pub fn scrollTo(key: u64, y: f32) void {
    if (scrolls.getPtr(key)) |s| s.target = y;
}

pub fn scrollInfo(key: u64) struct { offset: f32, content: f32 } {
    if (scrolls.get(key)) |s| return .{ .offset = s.offset, .content = s.content };
    return .{ .offset = 0, .content = 0 };
}

// ── Tooltips ────────────────────────────────────────────────────────────────

var tooltip_key: u64 = 0;
var tooltip_text: [256]u8 = undefined;
var tooltip_len: usize = 0;
var tooltip_since: f32 = 0;
var tooltip_seen_this_frame = false;

pub fn tooltip(key: u64, text_str: []const u8) void {
    if (tooltip_key != key) {
        tooltip_key = key;
        tooltip_since = time;
    }
    tooltip_len = @min(text_str.len, tooltip_text.len);
    @memcpy(tooltip_text[0..tooltip_len], text_str[0..tooltip_len]);
    tooltip_seen_this_frame = true;
}

pub fn drawTooltip() void {
    defer tooltip_seen_this_frame = false;
    if (!tooltip_seen_this_frame) {
        tooltip_key = 0;
        return;
    }
    const age = time - tooltip_since;
    if (age < 0.45) return;
    const t = easeOutCubic((age - 0.45) / 0.15);
    const s = tooltip_text[0..tooltip_len];
    const w = measure(s, 12, .semibold) + 18;
    var r: Rect = .{ .x = mouse.x + 12, .y = mouse.y + 20 + (1 - t) * 4, .w = w, .h = 26 };
    if (r.right() > screen.w - 8) r.x = screen.w - 8 - w;
    if (r.bottom() > screen.h - 8) r.y = mouse.y - 34;
    pushAlpha(t);
    rect(r, radius_sm, if (dark) colors.text else colors.text.alpha(0.92));
    label(s, r, 12, .semibold, colors.bg, .center);
    popAlpha();
}

// ── Toasts ──────────────────────────────────────────────────────────────────

pub const ToastKind = enum { info, success, warning, err };

const Toast = struct {
    kind: ToastKind,
    msg: [200]u8,
    len: usize,
    born: f32,
    life: f32,
    y: f32,
    key: u64,
};

var toasts: [6]Toast = undefined;
var toast_count: usize = 0;
var toast_serial: u64 = 0;

pub fn toast(kind: ToastKind, msg: []const u8) void {
    if (toast_count == toasts.len) {
        std.mem.copyForwards(Toast, toasts[0 .. toasts.len - 1], toasts[1..]);
        toast_count -= 1;
    }
    var t: Toast = .{ .kind = kind, .msg = undefined, .len = @min(msg.len, 200), .born = time, .life = if (kind == .err) 6 else 3.5, .y = -1, .key = 0 };
    @memcpy(t.msg[0..t.len], msg[0..t.len]);
    toast_serial += 1;
    t.key = id("toast", toast_serial);
    toasts[toast_count] = t;
    toast_count += 1;
}

pub fn toastFmt(kind: ToastKind, comptime fmt: []const u8, args: anytype) void {
    var buf: [200]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, fmt, args) catch buf[0..];
    toast(kind, s);
}

pub fn drawToasts() void {
    const saved_layer = layer;
    layer = Layer.toast;
    defer layer = saved_layer;

    var i: usize = 0;
    while (i < toast_count) {
        if (time - toasts[i].born > toasts[i].life + 0.4) {
            std.mem.copyForwards(Toast, toasts[i .. toast_count - 1], toasts[i + 1 .. toast_count]);
            toast_count -= 1;
        } else i += 1;
    }

    var y = screen.h - 20;
    var n = toast_count;
    while (n > 0) {
        n -= 1;
        const t = &toasts[n];
        const age = time - t.born;
        const in_t = easeOutCubic(std.math.clamp(age / 0.25, 0, 1));
        const out_t = std.math.clamp((age - t.life) / 0.35, 0, 1);
        const s = t.msg[0..t.len];
        const w = @min(420, measure(s, 13, .semibold) + 70);
        const h: f32 = 48;
        y -= h + 10;
        if (t.y < 0) t.y = y;
        t.y += (y - t.y) * (1 - @exp(-14 * dt));
        const x = screen.w - 20 - w + (1 - in_t) * (w + 40) + out_t * (w + 40);
        const r: Rect = .{ .x = x, .y = t.y, .w = w, .h = h };
        const accent_col = switch (t.kind) {
            .info => colors.accent,
            .success => colors.success,
            .warning => colors.warning,
            .err => colors.danger,
        };
        const ic: u21 = switch (t.kind) {
            .info => icons.info,
            .success => icons.circle_check,
            .warning => icons.triangle_alert,
            .err => icons.circle_x,
        };
        const in = interact(t.key, r);
        if (in.clicked) t.life = @min(t.life, age);
        shadow(r.offset(0, 4), radius_md, 12, colors.shadow.alpha(0.6));
        rect(r, radius_md, colors.elevated);
        border(r, radius_md, 1, colors.border);
        rect(.{ .x = r.x, .y = r.y, .w = 3, .h = r.h }, 0, accent_col);
        icon(ic, .{ .x = r.x + 24, .y = r.y + 24 }, 15, accent_col);
        label(s, .{ .x = r.x + 44, .y = r.y, .w = r.w - 56, .h = r.h }, 13, .semibold, colors.text, .left);
        // Lifetime bar
        const life_left = std.math.clamp(1 - age / t.life, 0, 1);
        rect(.{ .x = r.x + 3, .y = r.bottom() - 2, .w = (r.w - 3) * life_left, .h = 2 }, 0, accent_col.alpha(0.5));
        block(r);
    }
}

// ── Modals ──────────────────────────────────────────────────────────────────

pub const Modal = struct {
    rect: Rect,
    t: f32,
    close_requested: bool,
};

/// Draws the dimmed backdrop and the panel. `open_t` animates 0→1.
/// Returns the panel rect; draw contents inside on layer `Layer.modal`.
pub fn beginModal(key: u64, w: f32, h: f32, open: bool) ?Modal {
    const t = animFrom(key, 0, if (open) 1 else 0, 14);
    if (t < 0.01 and !open) return null;
    layer = Layer.modal;
    const eased = easeOutCubic(t);
    rect(screen, 0, colors.overlay.alpha(t));
    block(screen);
    const panel = screen.centered(@min(w, screen.w - 40), @min(h, screen.h - 40));
    const shown = panel.offset(0, (1 - eased) * 10);
    pushAlpha(t);
    shadow(shown.offset(0, 12), radius_lg, 30, colors.shadow.alpha(0.8));
    rect(shown, radius_lg, colors.elevated);
    border(shown, radius_lg, 1, colors.border.shade(if (dark) 0.08 else -0.05));
    const close = (mouse_pressed and !shown.contains(mouse) and !blockedForLayer(mouse)) or
        (c.IsKeyPressed(c.KEY_ESCAPE) and focus == 0);
    return .{ .rect = shown, .t = t, .close_requested = open and close };
}

pub fn endModal() void {
    popAlpha();
    layer = Layer.base;
}

// ── Dropdown (popup drawn at the end of the frame) ──────────────────────────

const DropdownPopup = struct {
    key: u64,
    anchor: Rect,
    items: []const []const u8,
    selected: *usize,
    layer: u8,
    changed: bool = false,
};

var dropdown_open: ?DropdownPopup = null;
var dropdown_changed_key: u64 = 0;

pub fn dropdown(key: u64, r: Rect, items: []const []const u8, selected: *usize) bool {
    const changed = dropdown_changed_key == key;
    if (changed) dropdown_changed_key = 0;
    const is_open = if (dropdown_open) |p| p.key == key else false;
    const in = interact(key, r);
    if (in.clicked) {
        dropdown_open = if (is_open) null else .{ .key = key, .anchor = r, .items = items, .selected = selected, .layer = layer };
    }
    if (dropdown_open) |*p| {
        if (p.key == key) {
            // Keep pointers fresh: the caller's data may have moved
            p.anchor = r;
            p.items = items;
            p.selected = selected;
        }
    }
    const open_t = anim(sub(key, 9), if (is_open) 1 else 0, 18);
    rect(r, radius_md, Rgba.lerp(colors.surface, colors.surface_hover, in.hover_t));
    border(r, radius_md, 1, Rgba.lerp(colors.border, colors.accent, open_t));
    const cur = if (selected.* < items.len) items[selected.*] else "";
    label(cur, .{ .x = r.x + 12, .y = r.y, .w = r.w - 40, .h = r.h }, 13, .regular, colors.text, .left);
    // Rotating chevron
    const chev: Vec2 = .{ .x = r.right() - 18, .y = r.y + r.h / 2 };
    if (open_t > 0.5) icon(icons.chevron_up, chev, 15, colors.accent) else icon(icons.chevron_down, chev, 15, colors.text_muted);
    return changed;
}

pub fn drawDropdownPopup() void {
    const p = &(dropdown_open orelse return);
    const saved_layer = layer;
    layer = p.layer + 1;
    defer layer = saved_layer;

    const t = animFrom(sub(p.key, 10), 0, 1, 18);
    const item_h: f32 = 32;
    const max_visible: f32 = 9;
    const n: f32 = @floatFromInt(p.items.len);
    const h = @min(n, max_visible) * item_h + 8;
    var r: Rect = .{ .x = p.anchor.x, .y = p.anchor.bottom() + 6, .w = @max(p.anchor.w, 180), .h = h };
    if (r.bottom() > screen.h - 10) r.y = p.anchor.y - 6 - h;
    const shown = r.offset(0, (1 - t) * -6);
    pushAlpha(t);
    defer popAlpha();
    shadow(shown.offset(0, 6), radius_lg, 14, colors.shadow.alpha(0.7));
    rect(shown, radius_lg, colors.elevated);
    border(shown, radius_lg, 1, colors.border.shade(if (dark) 0.08 else -0.05));
    block(shown);

    const inner = shown.inset(4);
    var y = beginScroll(sub(p.key, 11), inner);
    for (p.items, 0..) |item, i| {
        const row: Rect = .{ .x = inner.x, .y = y, .w = inner.w, .h = item_h };
        const in = interact(sub(p.key, 1000 + i), row);
        const sel = i == p.selected.*;
        if (sel) rect(.{ .x = row.x, .y = row.y + 8, .w = 2, .h = row.h - 16 }, 1, colors.accent);
        rect(row, radius_sm, colors.text.alpha(in.hover_t * 0.06));
        label(item, .{ .x = row.x + 10, .y = row.y, .w = row.w - 36, .h = row.h }, 13, if (sel) .semibold else .regular, if (sel) colors.accent else colors.text, .left);
        if (sel) icon(icons.check, .{ .x = row.right() - 16, .y = row.y + row.h / 2 }, 14, colors.accent);
        if (in.clicked) {
            p.selected.* = i;
            dropdown_changed_key = p.key;
            dropdown_open = null;
            endScroll(n * item_h);
            return;
        }
        y += item_h;
    }
    endScroll(n * item_h);
    if (mouse_pressed and !shown.contains(mouse) and !p.anchor.contains(mouse)) dropdown_open = null;
    if (c.IsKeyPressed(c.KEY_ESCAPE)) dropdown_open = null;
}

pub fn dropdownIsOpen() bool {
    return dropdown_open != null;
}

// ── Context menus ───────────────────────────────────────────────────────────

pub const Menu = struct {
    key: u64,
    rect: Rect,
    y: f32,
    t: f32,
    index: usize = 0,

    /// Small caption above a group of items (takes one row)
    pub fn header(m: *Menu, text_str: []const u8) void {
        label(text_str, .{ .x = m.rect.x + 14, .y = m.y + 4, .w = m.rect.w - 28, .h = 26 }, 11, .mono, colors.text_faint, .left);
        m.y += 32;
    }

    /// Item with a hint on the right (a hotkey, a count...)
    pub fn itemHint(m: *Menu, ic: u21, text_str: []const u8, hint: []const u8, danger: bool) bool {
        const hint_w = if (hint.len > 0) measure(hint, 11, .mono) + 10 else 0;
        const clicked = m.itemInner(ic, text_str, danger, hint_w);
        if (hint.len > 0) label(hint, .{ .x = m.rect.right() - 14 - hint_w, .y = m.y - 32, .w = hint_w, .h = 32 }, 11, .mono, colors.text_faint, .right);
        return clicked;
    }

    pub fn item(m: *Menu, ic: u21, text_str: []const u8, danger: bool) bool {
        return m.itemInner(ic, text_str, danger, 0);
    }

    fn itemInner(m: *Menu, ic: u21, text_str: []const u8, danger: bool, reserve: f32) bool {
        const row: Rect = .{ .x = m.rect.x + 4, .y = m.y, .w = m.rect.w - 8, .h = 32 };
        m.y += 32;
        m.index += 1;
        // Keyed by position in the menu, not by y: the panel scales while opening
        const in = interact(sub(m.key, m.index), row);
        const fg = if (danger) colors.danger else colors.text;
        rect(row, radius_sm, (if (danger) colors.danger else colors.text).alpha(in.hover_t * (if (danger) @as(f32, 0.12) else 0.07)));
        icon(ic, .{ .x = row.x + 18, .y = row.y + 16 }, 14, if (danger) colors.danger else colors.text_muted);
        label(text_str, .{ .x = row.x + 36, .y = row.y, .w = row.w - 40 - reserve, .h = row.h }, 13, .regular, fg, .left);
        return in.clicked;
    }

    pub fn separator(m: *Menu) void {
        rect(.{ .x = m.rect.x + 10, .y = m.y + 4, .w = m.rect.w - 20, .h = 1 }, 0, colors.border);
        m.y += 9;
    }
};

/// Context menu at `at`. `rows`/`separators` size the panel.
pub fn beginMenu(key: u64, at: Vec2, rows: usize, separators: usize) Menu {
    return beginMenuW(key, at, rows, separators, 220);
}

pub fn beginMenuW(key: u64, at: Vec2, rows: usize, separators: usize, width: f32) Menu {
    layer = Layer.popup;
    const t = animFrom(key, 0, 1, 20);
    const h = @as(f32, @floatFromInt(rows)) * 32 + @as(f32, @floatFromInt(separators)) * 9 + 8;
    var r: Rect = .{ .x = at.x, .y = at.y, .w = width, .h = h };
    if (r.right() > screen.w - 8) r.x = screen.w - 8 - r.w;
    if (r.bottom() > screen.h - 8) r.y = @max(8, at.y - h);
    const shown = r.offset(0, (1 - t) * -4);
    pushAlpha(t);
    shadow(shown.offset(0, 6), radius_lg, 16, colors.shadow.alpha(0.7));
    rect(shown, radius_lg, colors.elevated);
    border(shown, radius_lg, 1, colors.border.shade(if (dark) 0.08 else -0.05));
    block(shown);
    return .{ .key = key, .rect = shown, .y = shown.y + 4, .t = t };
}

pub fn endMenu(m: *const Menu) bool {
    popAlpha();
    layer = Layer.base;
    // Returns true when the menu should close
    return (mouse_pressed and !m.rect.contains(mouse)) or right_pressed and !m.rect.contains(mouse) or c.IsKeyPressed(c.KEY_ESCAPE);
}

// ── Meters, tabs, chips ─────────────────────────────────────────────────────

/// LED-style level meter, horizontal (green, then amber, then red near 0 dB)
pub fn meter(r: Rect, level_in: f32, dim: bool) void {
    const segs: usize = @max(6, @as(usize, @intFromFloat(r.w / 6)));
    const sw = r.w / @as(f32, @floatFromInt(segs));
    const lit = meterLit(level_in, segs);
    for (0..segs) |i| {
        const frac = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(segs));
        const on = i < lit;
        const col = meterColor(frac);
        rect(.{ .x = r.x + @as(f32, @floatFromInt(i)) * sw, .y = r.y, .w = sw - 1.5, .h = r.h }, 1, if (on) col.alpha(if (dim) 0.4 else 1) else colors.text.alpha(0.06));
    }
}

/// Same meter standing up, for channel strips
pub fn meterV(r: Rect, level_in: f32, dim: bool) void {
    const segs: usize = @max(6, @as(usize, @intFromFloat(r.h / 5)));
    const sh = r.h / @as(f32, @floatFromInt(segs));
    const lit = meterLit(level_in, segs);
    for (0..segs) |i| {
        const frac = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(segs));
        const on = i < lit;
        const col = meterColor(frac);
        const y = r.bottom() - @as(f32, @floatFromInt(i + 1)) * sh;
        rect(.{ .x = r.x, .y = y + 1, .w = r.w, .h = sh - 1.5 }, 0.5, if (on) col.alpha(if (dim) 0.4 else 1) else colors.text.alpha(0.06));
    }
}

fn meterLit(level_in: f32, segs: usize) usize {
    const lvl = std.math.clamp(level_in, 0, 1.2);
    // -48 dB .. 0 dB
    const db = 20 * std.math.log10(@max(lvl, 0.0001));
    const t = std.math.clamp((db + 48) / 48, 0, 1);
    return @intFromFloat(@round(t * @as(f32, @floatFromInt(segs))));
}

fn meterColor(frac: f32) Rgba {
    if (frac > 0.88) return colors.danger;
    if (frac > 0.7) return colors.warning;
    return colors.success;
}

pub const Tab = struct {
    label: []const u8,
    icon: ?u21 = null,
    badge: usize = 0,
};

/// Row of tabs with a sliding underline. Returns true when the selection changed.
pub fn tabs(key: u64, r: Rect, items: []const Tab, selected: *usize) bool {
    var changed = false;
    var x = r.x;
    var sel_x: f32 = r.x;
    var sel_w: f32 = 0;
    for (items, 0..) |item, i| {
        const tw = measure(item.label, 14, .semibold) + (if (item.icon != null) @as(f32, 24) else 0) + (if (item.badge > 0) @as(f32, 26) else 0) + 28;
        const cell: Rect = .{ .x = x, .y = r.y, .w = tw, .h = r.h };
        const in = interact(sub(key, 200 + i), cell);
        if (in.clicked and selected.* != i) {
            selected.* = i;
            changed = true;
        }
        const sel = selected.* == i;
        if (sel) {
            sel_x = cell.x;
            sel_w = cell.w;
        }
        rect(cell.insetXY(2, 4), 8, colors.text.alpha(in.hover_t * 0.05));
        const fg = if (sel) colors.text else Rgba.lerp(colors.text_muted, colors.text, in.hover_t);
        var cx = cell.x + 14;
        if (item.icon) |ic| {
            icon(ic, .{ .x = cx + 8, .y = cell.y + cell.h / 2 }, 15, if (sel) colors.accent else fg);
            cx += 24;
        }
        cx += text(item.label, cx, cell.y + (cell.h - 14) / 2, 14, .semibold, fg);
        if (item.badge > 0) {
            var buf: [8]u8 = undefined;
            const b = std.fmt.bufPrint(&buf, "{d}", .{item.badge}) catch "";
            badge(.{ .x = cx + 6, .y = cell.y + (cell.h - 18) / 2, .w = 20, .h = 18 }, b, colors.accent.alpha(0.18), colors.accent);
        }
        x += tw + 2;
    }
    rect(.{ .x = r.x, .y = r.bottom() - 1, .w = r.w, .h = 1 }, 0, colors.border);
    const ux = anim(sub(key, 1), sel_x, 18);
    const uw = anim(sub(key, 2), sel_w, 18);
    rect(.{ .x = ux + 10, .y = r.bottom() - 3, .w = @max(0, uw - 20), .h = 3 }, 1.5, colors.accent);
    return changed;
}

/// Pill-shaped toggle button with an optional icon. Returns true when clicked.
pub fn chip(key: u64, r: Rect, ic: ?u21, text_str: []const u8, active_on: bool, tint: ?Rgba) bool {
    const in = interact(key, r);
    const col = tint orelse colors.accent;
    const act_t = anim(sub(key, 7), if (active_on) 1 else 0, 16);
    const br = r.offset(0, in.press_t);
    rect(br, radius_sm, Rgba.lerp(colors.surface, col.alpha(0.16), act_t));
    rect(br, radius_sm, colors.text.alpha(in.hover_t * 0.05));
    border(br, radius_sm, 1, Rgba.lerp(Rgba.lerp(colors.border, colors.text_faint, in.hover_t), col, act_t));
    const fg = Rgba.lerp(colors.text_muted, colors.text, @max(in.hover_t, act_t));
    var x = br.x + 12;
    if (ic) |i| {
        icon(i, .{ .x = x + 7, .y = br.y + br.h / 2 }, 14, Rgba.lerp(fg, col, act_t));
        x += 20;
    }
    label(text_str, .{ .x = x, .y = br.y, .w = br.right() - x - 10, .h = br.h }, 12, .semibold, fg, .left);
    return in.clicked;
}

pub fn chipWidth(ic: ?u21, text_str: []const u8) f32 {
    return measure(text_str, 12, .semibold) + 24 + (if (ic != null) @as(f32, 20) else 0);
}

/// Slider with a custom fill color and 0..1 output; for compact rows (mixer)
pub fn miniSlider(key: u64, r: Rect, value: *f32, min: f32, max_v: f32, col: Rgba) bool {
    const track: Rect = .{ .x = r.x + 6, .y = r.y + r.h / 2 - 2, .w = r.w - 12, .h = 4 };
    const in = interact(key, r);
    var changed = false;
    if (in.held) {
        const t = std.math.clamp((mouse.x - track.x) / track.w, 0, 1);
        value.* = min + t * (max_v - min);
        changed = true;
    }
    if (in.hovered) {
        const wd = consumeWheel();
        if (wd != 0) {
            value.* = std.math.clamp(value.* + wd * (max_v - min) * 0.05, min, max_v);
            changed = true;
        }
    }
    const t = std.math.clamp((value.* - min) / (max_v - min), 0, 1);
    rect(track, 2, colors.border);
    rect(.{ .x = track.x, .y = track.y, .w = @max(4, track.w * t), .h = track.h }, 2, col);
    const knob: Vec2 = .{ .x = track.x + track.w * t, .y = track.y + 2 };
    const grow_t = @max(in.hover_t, in.press_t);
    if (grow_t > 0.01) circle(knob, 10 * grow_t, col.alpha(0.2 * grow_t));
    circle(knob, 5.5 + grow_t * 1.5, Rgba{ .r = 1, .g = 1, .b = 1 });
    border(.{ .x = knob.x - 6.5, .y = knob.y - 6.5, .w = 13, .h = 13 }, 6.5, 1, col.alpha(0.7));
    return changed;
}

/// Vertical fader like on a mixing desk. `unity` draws a tick (e.g. 100%).
pub fn faderV(key: u64, r: Rect, value: *f32, min: f32, max_v: f32, unity: ?f32, col: Rgba) bool {
    const track: Rect = .{ .x = r.x + r.w / 2 - 1.5, .y = r.y + 8, .w = 3, .h = r.h - 16 };
    const in = interact(key, r);
    var changed = false;
    if (in.held) {
        const t = std.math.clamp((track.bottom() - mouse.y) / track.h, 0, 1);
        value.* = min + t * (max_v - min);
        changed = true;
    }
    if (in.hovered) {
        const wd = consumeWheel();
        if (wd != 0) {
            value.* = std.math.clamp(value.* + wd * (max_v - min) * 0.04, min, max_v);
            changed = true;
        }
    }
    const t = std.math.clamp((value.* - min) / (max_v - min), 0, 1);
    rect(track, 1, colors.bg);
    border(track.grow(1), 1, 1, colors.border);
    // Scale ticks
    for (0..5) |i| {
        const ty = track.bottom() - track.h * @as(f32, @floatFromInt(i)) / 4;
        rect(.{ .x = track.x - 7, .y = ty, .w = 4, .h = 1 }, 0, colors.text_faint.alpha(0.5));
    }
    if (unity) |u| {
        const ut = std.math.clamp((u - min) / (max_v - min), 0, 1);
        const uy = track.bottom() - track.h * ut;
        rect(.{ .x = track.x - 9, .y = uy - 0.5, .w = 6, .h = 1.5 }, 0, colors.text_muted);
    }
    const fill_h = track.h * t;
    rect(.{ .x = track.x, .y = track.bottom() - fill_h, .w = track.w, .h = fill_h }, 1, col.alpha(0.8));
    const cy = track.bottom() - fill_h;
    const cap: Rect = .{ .x = r.x + r.w / 2 - 11, .y = cy - 6, .w = 22, .h = 12 };
    rect(cap, 2, Rgba.lerp(colors.text_muted, colors.text, @max(in.hover_t, in.press_t)));
    rect(.{ .x = cap.x + 3, .y = cap.y + 5.5, .w = cap.w - 6, .h = 1 }, 0, colors.bg);
    return changed;
}

/// Small square text button (mixer M / F buttons)
pub fn textToggle(key: u64, r: Rect, text_str: []const u8, on: bool, on_col: Rgba, tip: ?[]const u8) bool {
    const in = interact(key, r);
    rect(r, radius_sm, if (on) on_col else colors.text.alpha(0.05 + in.hover_t * 0.06));
    if (!on) border(r, radius_sm, 1, colors.border);
    label(text_str, r, 11, .mono_bold, if (on) colors.bg else Rgba.lerp(colors.text_muted, colors.text, in.hover_t), .center);
    if (tip) |t| {
        if (in.hovered) tooltip(key, t);
    }
    return in.clicked;
}
