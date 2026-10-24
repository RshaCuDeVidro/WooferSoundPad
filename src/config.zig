//! User settings, persisted as JSON in the config folder.

const std = @import("std");
const sys = @import("sys.zig");
const fx = @import("fx.zig");

pub const Language = enum { en, pt };
pub const PlayMode = enum { restart, overlap, toggle };
pub const PadSize = enum { small, medium, large };
pub const SortMode = enum { manual, name, recent, most_played };
pub const AudioFormat = enum { mp3, ogg, wav };
pub const ExploreSource = enum { myinstants, soundbuttonsworld };
pub const OnlinePlatform = enum { youtube, soundcloud, link };

pub const Config = struct {
    version: u32 = 1,

    // Appearance
    language: Language = .en,
    theme: []const u8 = "husky",
    ui_scale: f32 = 1.0,
    animations: bool = true,
    pad_size: PadSize = .medium,
    show_hotkeys_on_pads: bool = true,
    show_waveforms: bool = true,

    // Library
    library_dir: []const u8 = "",
    active_workspace: []const u8 = "",
    sort: SortMode = .manual,

    // Audio
    monitor_device: []const u8 = "",
    mic_device: []const u8 = "",
    master_volume: f32 = 0.9,
    monitor_volume: f32 = 1.0,
    mic_volume: f32 = 1.0,
    preview_volume: f32 = 0.8,
    play_mode: PlayMode = .restart,
    /// Your real mic on the virtual mic (Linux loopback)
    voice_volume: f32 = 1.0,
    voice_muted: bool = false,

    // Queue
    queue_mode: bool = false, // clicking a pad adds it to the queue
    queue_repeat: bool = false,
    queue_open: bool = false,

    // Hotkeys
    global_hotkeys: bool = true,
    stop_hotkey: []const u8 = "Pause",
    pause_hotkey: []const u8 = "",
    next_hotkey: []const u8 = "",
    random_hotkey: []const u8 = "",
    mute_voice_hotkey: []const u8 = "",
    number_keys_play: bool = true,

    // Downloads
    ytdlp_path: []const u8 = "",
    ffmpeg_path: []const u8 = "",
    deno_path: []const u8 = "",
    download_format: AudioFormat = .mp3,
    normalize_audio: bool = true,
    max_clip_seconds: u32 = 0,
    results_per_search: u32 = 20,

    // Effects: presets saved by the user (built-ins live in fx.zig)
    fx_presets: []const fx.UserPreset = &.{},

    // Mixer and stage mode
    mixer_open: bool = false,
    mixer_fade_seconds: f32 = 1.5,
    stage_fullscreen: bool = true,
    stage_mixer: bool = true,

    // Recorder: -1 = computer audio, -2 = default mic, otherwise a capture device
    rec_source: i32 = -1,
    rec_auto_trim: bool = true,

    // Library-wide volume normalization (off: every file plays as it is)
    normalize_library: bool = false,
    normalize_target: f32 = -16,

    // Local control server for OBS / Stream Deck (off by default)
    http_enabled: bool = false,
    http_port: u16 = 8737,
    http_lan: bool = false,
    http_token: []const u8 = "",

    // Statistics page
    stats_all_workspaces: bool = true,

    // Browsers
    explore_source: ExploreSource = .myinstants,
    online_platform: OnlinePlatform = .youtube,

    // Window
    window_width: i32 = 1280,
    window_height: i32 = 800,
    window_maximized: bool = false,

    onboarding_done: bool = false,
};

var arena_state: std.heap.ArenaAllocator = .init(std.heap.c_allocator);
/// Owns every string in the config (they are small and rarely change)
pub const arena = arena_state.allocator();

pub var path: []u8 = &.{};

pub fn load() Config {
    const dir = sys.configDir() catch return defaults();
    defer sys.gpa.free(dir);
    sys.makePath(dir) catch {};
    path = sys.join(&.{ dir, "config.json" }) catch return defaults();

    const data = sys.readFile(path, 1024 * 1024) catch return defaults();
    defer sys.gpa.free(data);
    const cfg = std.json.parseFromSliceLeaky(Config, arena, data, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    }) catch |err| {
        std.log.warn("config.json is invalid ({s}), using defaults", .{@errorName(err)});
        return defaults();
    };
    return sanitize(cfg);
}

fn defaults() Config {
    var cfg: Config = .{};
    // Portuguese speakers get Portuguese on first run
    const lang = sys.getenv("LANG") orelse sys.getenv("LC_ALL") orelse "";
    if (std.mem.startsWith(u8, lang, "pt")) cfg.language = .pt;
    // 0x16 is the primary language id of Portuguese
    if (sys.is_windows and GetUserDefaultUILanguage() & 0x3ff == 0x16) cfg.language = .pt;
    return cfg;
}

extern "kernel32" fn GetUserDefaultUILanguage() callconv(.winapi) u16;

fn sanitize(cfg_in: Config) Config {
    var cfg = cfg_in;
    cfg.ui_scale = std.math.clamp(cfg.ui_scale, 0.75, 2.0);
    cfg.master_volume = std.math.clamp(cfg.master_volume, 0, 1);
    cfg.monitor_volume = std.math.clamp(cfg.monitor_volume, 0, 1);
    cfg.mic_volume = std.math.clamp(cfg.mic_volume, 0, 1);
    cfg.preview_volume = std.math.clamp(cfg.preview_volume, 0, 1);
    cfg.voice_volume = std.math.clamp(cfg.voice_volume, 0, 1.5);
    cfg.results_per_search = std.math.clamp(cfg.results_per_search, 5, 50);
    cfg.mixer_fade_seconds = std.math.clamp(cfg.mixer_fade_seconds, 0.2, 10);
    cfg.normalize_target = std.math.clamp(cfg.normalize_target, -30, -8);
    cfg.window_width = @max(cfg.window_width, 960);
    cfg.window_height = @max(cfg.window_height, 600);
    return cfg;
}

pub fn save(cfg: *const Config) void {
    if (path.len == 0) return;
    const json = std.json.Stringify.valueAlloc(sys.gpa, cfg.*, .{ .whitespace = .indent_2 }) catch return;
    defer sys.gpa.free(json);
    sys.writeFileAtomic(path, json) catch |err| {
        std.log.err("could not save settings: {s}", .{@errorName(err)});
    };
}

/// Replaces a string setting (the old copy stays in the arena; settings are tiny)
pub fn setString(field: *[]const u8, value: []const u8) void {
    field.* = arena.dupe(u8, value) catch return;
}

/// Adds (or replaces, by name) a user effect preset
pub fn savePreset(cfg: *Config, name: []const u8, effects: []const fx.Effect) void {
    const name_copy = arena.dupe(u8, name) catch return;
    const fx_copy = arena.alloc(fx.Stored, effects.len) catch return;
    for (effects, fx_copy) |*e, *st| st.* = fx.Stored.from(e);
    for (cfg.fx_presets, 0..) |p, i| {
        if (std.ascii.eqlIgnoreCase(p.name, name)) {
            const list = arena.dupe(fx.UserPreset, cfg.fx_presets) catch return;
            list[i] = .{ .name = name_copy, .fx = fx_copy };
            cfg.fx_presets = list;
            return;
        }
    }
    const list = arena.alloc(fx.UserPreset, cfg.fx_presets.len + 1) catch return;
    @memcpy(list[0..cfg.fx_presets.len], cfg.fx_presets);
    list[cfg.fx_presets.len] = .{ .name = name_copy, .fx = fx_copy };
    cfg.fx_presets = list;
}

pub fn deletePreset(cfg: *Config, index: usize) void {
    if (index >= cfg.fx_presets.len) return;
    const list = arena.alloc(fx.UserPreset, cfg.fx_presets.len - 1) catch return;
    @memcpy(list[0..index], cfg.fx_presets[0..index]);
    @memcpy(list[index..], cfg.fx_presets[index + 1 ..]);
    cfg.fx_presets = list;
}
