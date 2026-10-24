//! Color themes. The UI never reads a `Theme` directly: it reads `ui.colors`,
//! which eases toward the selected theme so switching themes cross-fades.

const std = @import("std");

pub const Rgba = struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32 = 1,

    pub fn hex(v: u32) Rgba {
        return .{
            .r = @as(f32, @floatFromInt((v >> 16) & 0xff)) / 255,
            .g = @as(f32, @floatFromInt((v >> 8) & 0xff)) / 255,
            .b = @as(f32, @floatFromInt(v & 0xff)) / 255,
        };
    }

    pub fn alpha(c: Rgba, a: f32) Rgba {
        return .{ .r = c.r, .g = c.g, .b = c.b, .a = c.a * a };
    }

    pub fn lerp(a: Rgba, b: Rgba, t: f32) Rgba {
        return .{
            .r = a.r + (b.r - a.r) * t,
            .g = a.g + (b.g - a.g) * t,
            .b = a.b + (b.b - a.b) * t,
            .a = a.a + (b.a - a.a) * t,
        };
    }

    /// Mixes toward white (amount > 0) or black (amount < 0)
    pub fn shade(c: Rgba, amount: f32) Rgba {
        const target: Rgba = if (amount > 0) .{ .r = 1, .g = 1, .b = 1, .a = c.a } else .{ .r = 0, .g = 0, .b = 0, .a = c.a };
        return lerp(c, target, @abs(amount));
    }

    pub fn luminance(c: Rgba) f32 {
        return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
    }
};

pub const Colors = struct {
    bg: Rgba,
    sidebar: Rgba,
    surface: Rgba,
    surface_hover: Rgba,
    elevated: Rgba,
    border: Rgba,
    text: Rgba,
    text_muted: Rgba,
    text_faint: Rgba,
    accent: Rgba,
    accent2: Rgba,
    accent_text: Rgba,
    success: Rgba,
    warning: Rgba,
    danger: Rgba,
    shadow: Rgba,
    overlay: Rgba,

    pub fn lerp(a: Colors, b: Colors, t: f32) Colors {
        var out: Colors = undefined;
        inline for (comptime std.meta.fieldNames(Colors)) |name| {
            @field(out, name) = Rgba.lerp(@field(a, name), @field(b, name), t);
        }
        return out;
    }
};

pub const Theme = struct {
    id: []const u8,
    name: []const u8,
    dark: bool,
    colors: Colors,
};

const Hex = struct {
    bg: u32,
    sidebar: u32,
    surface: u32,
    surface_hover: u32,
    elevated: u32,
    border: u32,
    text: u32,
    text_muted: u32,
    text_faint: u32,
    accent: u32,
    accent2: u32,
    accent_text: u32,
    success: u32 = 0x34D399,
    warning: u32 = 0xFBBF24,
    danger: u32 = 0xF87171,
};

fn make(id: []const u8, name: []const u8, dark: bool, h: Hex) Theme {
    var colors: Colors = undefined;
    inline for (comptime std.meta.fieldNames(Hex)) |field| {
        @field(colors, field) = Rgba.hex(@field(h, field));
    }
    colors.shadow = if (dark) (Rgba{ .r = 0, .g = 0, .b = 0, .a = 0.55 }) else (Rgba{ .r = 0.1, .g = 0.12, .b = 0.2, .a = 0.16 });
    colors.overlay = if (dark) (Rgba{ .r = 0, .g = 0, .b = 0, .a = 0.6 }) else (Rgba{ .r = 0.06, .g = 0.08, .b = 0.14, .a = 0.35 });
    return .{ .id = id, .name = name, .dark = dark, .colors = colors };
}

pub const themes = [_]Theme{
    make("husky", "Husky", true, .{
        .bg = 0x121212,
        .sidebar = 0x0C0C0C,
        .surface = 0x1A1A1A,
        .surface_hover = 0x222222,
        .elevated = 0x1F1F1F,
        .border = 0x2B2B2B,
        .text = 0xEDEAE3,
        .text_muted = 0x9E9A92,
        .text_faint = 0x5F5C57,
        .accent = 0xFF6B1A,
        .accent2 = 0xFFB020,
        .accent_text = 0x140800,
        .success = 0x7FD48C,
        .warning = 0xFFC53D,
        .danger = 0xFF4A3D,
    }),
    make("snow", "Snow", false, .{
        .bg = 0xF4F7FB,
        .sidebar = 0xEAF0F7,
        .surface = 0xFFFFFF,
        .surface_hover = 0xF0F4F9,
        .elevated = 0xFFFFFF,
        .border = 0xDCE4EE,
        .text = 0x0F1A2A,
        .text_muted = 0x5B6B82,
        .text_faint = 0x94A3B8,
        .accent = 0x2F80ED,
        .accent2 = 0x7C5CFF,
        .accent_text = 0xFFFFFF,
        .success = 0x16A34A,
        .warning = 0xD97706,
        .danger = 0xDC2626,
    }),
    make("midnight", "Midnight", true, .{
        .bg = 0x000000,
        .sidebar = 0x07070A,
        .surface = 0x0F0F14,
        .surface_hover = 0x17171F,
        .elevated = 0x1B1B24,
        .border = 0x24242F,
        .text = 0xEDEDF2,
        .text_muted = 0x9A9AAE,
        .text_faint = 0x5E5E70,
        .accent = 0xA78BFA,
        .accent2 = 0xF472B6,
        .accent_text = 0x0B0716,
    }),
    make("aurora", "Aurora", true, .{
        .bg = 0x08161A,
        .sidebar = 0x0A1C21,
        .surface = 0x10262C,
        .surface_hover = 0x153239,
        .elevated = 0x183840,
        .border = 0x1F444D,
        .text = 0xE3F6F5,
        .text_muted = 0x8FB8B5,
        .text_faint = 0x5B8581,
        .accent = 0x2DD4BF,
        .accent2 = 0xA78BFA,
        .accent_text = 0x04201C,
    }),
    make("dracula", "Dracula", true, .{
        .bg = 0x21222C,
        .sidebar = 0x1E1F29,
        .surface = 0x282A36,
        .surface_hover = 0x313445,
        .elevated = 0x343746,
        .border = 0x44475A,
        .text = 0xF8F8F2,
        .text_muted = 0xA9ACC4,
        .text_faint = 0x6272A4,
        .accent = 0xBD93F9,
        .accent2 = 0xFF79C6,
        .accent_text = 0x1E1F29,
        .success = 0x50FA7B,
        .warning = 0xF1FA8C,
        .danger = 0xFF5555,
    }),
    make("nord", "Nord", true, .{
        .bg = 0x2E3440,
        .sidebar = 0x2A2F3A,
        .surface = 0x3B4252,
        .surface_hover = 0x434C5E,
        .elevated = 0x434C5E,
        .border = 0x4C566A,
        .text = 0xECEFF4,
        .text_muted = 0xC0C8D6,
        .text_faint = 0x7B88A1,
        .accent = 0x88C0D0,
        .accent2 = 0x81A1C1,
        .accent_text = 0x2E3440,
        .success = 0xA3BE8C,
        .warning = 0xEBCB8B,
        .danger = 0xBF616A,
    }),
    make("mocha", "Catppuccin Mocha", true, .{
        .bg = 0x1E1E2E,
        .sidebar = 0x181825,
        .surface = 0x262637,
        .surface_hover = 0x313244,
        .elevated = 0x363648,
        .border = 0x45475A,
        .text = 0xCDD6F4,
        .text_muted = 0xA6ADC8,
        .text_faint = 0x6C7086,
        .accent = 0xCBA6F7,
        .accent2 = 0xF5C2E7,
        .accent_text = 0x1E1E2E,
        .success = 0xA6E3A1,
        .warning = 0xF9E2AF,
        .danger = 0xF38BA8,
    }),
    make("latte", "Catppuccin Latte", false, .{
        .bg = 0xEFF1F5,
        .sidebar = 0xE6E9EF,
        .surface = 0xF8F9FB,
        .surface_hover = 0xE9ECF2,
        .elevated = 0xFFFFFF,
        .border = 0xCCD0DA,
        .text = 0x4C4F69,
        .text_muted = 0x6C6F85,
        .text_faint = 0x9CA0B0,
        .accent = 0x8839EF,
        .accent2 = 0xEA76CB,
        .accent_text = 0xFFFFFF,
        .success = 0x40A02B,
        .warning = 0xDF8E1D,
        .danger = 0xD20F39,
    }),
    make("gruvbox", "Gruvbox", true, .{
        .bg = 0x1D2021,
        .sidebar = 0x1A1C1D,
        .surface = 0x282828,
        .surface_hover = 0x32302F,
        .elevated = 0x3C3836,
        .border = 0x504945,
        .text = 0xEBDBB2,
        .text_muted = 0xBDAE93,
        .text_faint = 0x7C6F64,
        .accent = 0xFABD2F,
        .accent2 = 0xFE8019,
        .accent_text = 0x1D2021,
        .success = 0xB8BB26,
        .warning = 0xFABD2F,
        .danger = 0xFB4934,
    }),
    make("tokyo", "Tokyo Night", true, .{
        .bg = 0x16161E,
        .sidebar = 0x13131A,
        .surface = 0x1A1B26,
        .surface_hover = 0x24283B,
        .elevated = 0x292E42,
        .border = 0x2F3549,
        .text = 0xC0CAF5,
        .text_muted = 0x9AA5CE,
        .text_faint = 0x565F89,
        .accent = 0x7AA2F7,
        .accent2 = 0xBB9AF7,
        .accent_text = 0x16161E,
        .success = 0x9ECE6A,
        .warning = 0xE0AF68,
        .danger = 0xF7768E,
    }),
    make("rosepine", "Rosé Pine", true, .{
        .bg = 0x191724,
        .sidebar = 0x16141F,
        .surface = 0x1F1D2E,
        .surface_hover = 0x26233A,
        .elevated = 0x2A2740,
        .border = 0x393552,
        .text = 0xE0DEF4,
        .text_muted = 0x908CAA,
        .text_faint = 0x6E6A86,
        .accent = 0xEBBCBA,
        .accent2 = 0xC4A7E7,
        .accent_text = 0x191724,
        .success = 0x9CCFD8,
        .warning = 0xF6C177,
        .danger = 0xEB6F92,
    }),
    make("synthwave", "Synthwave '84", true, .{
        .bg = 0x1A1032,
        .sidebar = 0x160D2B,
        .surface = 0x241B44,
        .surface_hover = 0x2E2652,
        .elevated = 0x342B5C,
        .border = 0x3D3370,
        .text = 0xF3E8FF,
        .text_muted = 0xB8A6D9,
        .text_faint = 0x7A6A9E,
        .accent = 0xFF7EDB,
        .accent2 = 0x36F9F6,
        .accent_text = 0x1A1032,
        .success = 0x72F1B8,
        .warning = 0xFEDE5D,
        .danger = 0xFE4450,
    }),
    make("sakura", "Sakura", false, .{
        .bg = 0xFFF5F8,
        .sidebar = 0xFCEBF1,
        .surface = 0xFFFFFF,
        .surface_hover = 0xFDEFF4,
        .elevated = 0xFFFFFF,
        .border = 0xF5D0DC,
        .text = 0x3D1F2B,
        .text_muted = 0x8A5A6B,
        .text_faint = 0xC4A1AE,
        .accent = 0xE85D8F,
        .accent2 = 0xF5A3C0,
        .accent_text = 0xFFFFFF,
        .success = 0x2FAE7A,
        .warning = 0xE39B1B,
        .danger = 0xD93F5C,
    }),
    make("forest", "Forest", true, .{
        .bg = 0x0F1612,
        .sidebar = 0x0C120F,
        .surface = 0x16201A,
        .surface_hover = 0x1C2A22,
        .elevated = 0x203027,
        .border = 0x2A3D31,
        .text = 0xE4F1E8,
        .text_muted = 0x9DB8A6,
        .text_faint = 0x5F7A68,
        .accent = 0x6EE7A1,
        .accent2 = 0xFACC15,
        .accent_text = 0x0B1A12,
    }),
};

pub fn find(id: []const u8) *const Theme {
    for (&themes) |*t| {
        if (std.mem.eql(u8, t.id, id)) return t;
    }
    return &themes[0];
}

/// Colors users can give to their pads. Index 0 means "use the theme accent".
pub const pad_palette = [_]u32{
    0xFF6B1A, 0xFFB020, 0xE8E04A, 0x8BD448, 0x3FC98A, 0x2EC4C4,
    0x3D9BFF, 0x7A6CFF, 0xC85CF0, 0xFF5C9A, 0xFF4A3D, 0xB8B2A7,
};

pub fn padColor(index: u8, accent: Rgba) Rgba {
    if (index == 0 or index > pad_palette.len) return accent;
    return Rgba.hex(pad_palette[index - 1]);
}
