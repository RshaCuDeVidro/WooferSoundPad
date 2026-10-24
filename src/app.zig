//! Application state and the logic shared by every view.

const std = @import("std");
const c = @import("c");
const build_options = @import("build_options");
const ui = @import("ui.zig");
const theme = @import("theme.zig");
const sys = @import("sys.zig");
const config = @import("config.zig");
const library = @import("library.zig");
const audio = @import("audio.zig");
const jobs = @import("jobs.zig");
const market = @import("market.zig");
const tools = @import("tools.zig");
const hotkeys = @import("hotkeys.zig");
const ipc = @import("ipc.zig");
const i18n = @import("i18n.zig");
const vmic = @import("vmic.zig");
const waves = @import("waves.zig");
const fx = @import("fx.zig");
const stats = @import("stats.zig");
const loudness = @import("loudness.zig");
const remote = @import("remote.zig");

const gpa = sys.gpa;
pub const icons = ui.icons;

pub const Page = enum { soundboard, explore, online, downloads, stats, settings };

pub const Ripple = struct {
    pad: usize,
    x: f32,
    y: f32,
    born: f32,
};

pub const MenuKind = enum { pad, workspace };
pub const MenuState = struct {
    kind: MenuKind,
    index: usize,
    pos: ui.Vec2,
};

pub const Dialog = union(enum) {
    none,
    create_workspace,
    rename_workspace: usize,
    delete_workspace: usize,
    delete_sound: usize,
    edit_sound: usize,
    download_media: void,
    record: void,
};

/// Which hotkey field is waiting for a key press
pub const Capture = enum { none, pad, stop, pause, next, random, mute_voice };

/// Global hotkey actions; sounds use `sound_base + index`
pub const Action = struct {
    pub const stop: u32 = 0;
    pub const pause: u32 = 1;
    pub const next: u32 = 2;
    pub const random: u32 = 3;
    pub const mute_voice: u32 = 4;
    pub const sound_base: u32 = 16;
};

pub const EditorTab = enum { sound, effects, pad };

pub const Editor = struct {
    name: ui.TextField = .{},
    color: u8 = 0,
    volume: f32 = 1,
    favorite: bool = false,
    hotkey: [48]u8 = undefined,
    hotkey_len: usize = 0,
    /// Trim, speed, loop and fades being edited; previewed live
    params: audio.Params = .{},
    /// What the sound had when the editor opened (restored on cancel)
    original: audio.Params = .{},
    normalize: bool = false,
    saved: bool = false,
    drag: enum { none, start, end, fade_in, fade_out, select, pan } = .none,
    /// Live effect chain being edited, and what the sound had
    fx: fx.Chain = .{},
    original_fx: fx.Chain = .{},
    tab: EditorTab = .sound,
    /// Visible part of the waveform, in seconds of the file
    view_start: f32 = 0,
    view_len: f32 = 0,
    drag_from: f32 = 0,
    drag_moved: bool = false,
    start_field: ui.TextField = .{},
    end_field: ui.TextField = .{},
    loop_preview: bool = false,
    /// Effect card whose "add" menu is open
    add_menu: bool = false,
    /// Set by openEditor so the undo history starts fresh
    undo_reset: bool = true,

    pub fn hotkeyText(e: *const Editor) []const u8 {
        return e.hotkey[0..e.hotkey_len];
    }

    pub fn setHotkey(e: *Editor, s: []const u8) void {
        e.hotkey_len = @min(s.len, e.hotkey.len);
        @memcpy(e.hotkey[0..e.hotkey_len], s[0..e.hotkey_len]);
    }
};

/// Sounds waiting to play one after another
pub const Queue = struct {
    /// Sound uids in the active workspace (stable while sounds get reordered)
    items: std.ArrayList(u32) = .empty,
    current: ?usize = null,
    started_at: f32 = 0,
    drag: ?usize = null,
    drag_offset: f32 = 0,
};

pub const QueryKind = enum { trending, search, category };

pub const ExploreState = struct {
    source: usize = 0,
    search: ui.TextField = .{},
    kind: QueryKind = .trending,
    query: [128]u8 = undefined,
    query_len: usize = 0,
    category: ?usize = null,
    task: ?*jobs.MarketTask = null,
    items: std.ArrayList(market.Item) = .empty,
    page: u32 = 0,
    has_more: bool = false,
    failed: bool = false,
    loaded: bool = false,
    sbw_categories: std.ArrayList([]u8) = .empty,
    preview_task: ?*jobs.PreviewTask = null,
    preview_url: []u8 = &.{},
    preview_started: bool = false,
    added: std.StringHashMapUnmanaged(void) = .empty,
    target: usize = 0,
    generation: u32 = 0,

    pub fn queryText(e: *const ExploreState) []const u8 {
        return e.query[0..e.query_len];
    }
};

pub const OnlineState = struct {
    platform: usize = 0,
    search: ui.TextField = .{},
    link: ui.TextField = .{},
    task: ?*jobs.MediaTask = null,
    results: std.ArrayList(tools.MediaResult) = .empty,
    failed: bool = false,
    searched: bool = false,
    generation: u32 = 0,
    // Download dialog
    dlg_url: []u8 = &.{},
    dlg_title: []u8 = &.{},
    dlg_duration: f32 = 0,
    dlg_name: ui.TextField = .{},
    dlg_start: ui.TextField = .{},
    dlg_end: ui.TextField = .{},
    dlg_normalize: bool = true,
    dlg_target: usize = 0,
};

pub const RecState = enum { idle, recording, recorded };

pub const Recorder = struct {
    state: RecState = .idle,
    name: ui.TextField = .{},
    target: usize = 0,
    started_at: f32 = 0,
    failed: bool = false,
    /// Sources for the dropdown: [0] computer, [1] default mic, then devices
    source_idx: usize = 0,
    /// Selection kept from the recording, in seconds
    keep_start: f32 = 0,
    keep_end: f32 = 0,
    drag: enum { none, start, end } = .none,
    level: f32 = 0,
};

pub const App = struct {
    cfg: config.Config,
    t: *const i18n.Strings = &i18n.en,
    lib: library.Library = .{},
    ws: usize = 0,
    page: Page = .soundboard,
    page_changed_at: f32 = -10,
    jobs: jobs.Manager = .{},
    logo: c.Texture = undefined,
    version: []const u8 = build_options.version,

    cfg_dirty_at: ?f32 = null,
    ws_dirty_at: ?f32 = null,
    bindings_dirty: bool = true,
    ws_generation: u32 = 0,
    applied_scale: f32 = 0,

    // Soundboard
    search: ui.TextField = .{},
    favorites_only: bool = false,
    view: std.ArrayList(usize) = .empty,
    ripples: [12]Ripple = undefined,
    ripple_count: usize = 0,
    menu: ?MenuState = null,
    /// When a click outside closed the pad menu (so the same click on its
    /// "more" button doesn't open it again)
    menu_dismissed_index: usize = std.math.maxInt(usize),
    menu_dismissed_at: f32 = -10,
    dialog: Dialog = .none,
    dialog_closing: Dialog = .none,
    name_field: ui.TextField = .{},
    editor: Editor = .{},
    capture: Capture = .none,
    focus_search: bool = false,
    queue: Queue = .{},
    bindings: std.ArrayList(hotkeys.Binding) = .empty,
    space_bound: bool = false,
    rng: u64 = 0x9E37_79B9_7F4A_7C15,
    last_random: ?usize = null,

    explore: ExploreState = .{},
    online: OnlineState = .{},

    onboarding_open: bool = false,
    onboarding_step: usize = 0,

    /// Full-screen performance view
    stage: bool = false,
    stage_went_fullscreen: bool = false,
    rec: Recorder = .{},
    preset_name: ui.TextField = .{},
    port_field: ui.TextField = .{},
    stats_saved_at: f32 = 0,
    /// Time played since workspace.json was last written
    play_time_unsaved: bool = false,

    cache_size: ?u64 = null,
    vmic_exists: ?bool = null,
    vmic_has_voice: bool = false,
    vmic_include_mic: bool = true,

    quit_requested: bool = false,

    // ── Setup ───────────────────────────────────────────────────────────────

    pub fn init(a: *App) void {
        a.t = i18n.get(a.cfg.language);
        ui.animations = a.cfg.animations;
        ui.setTheme(theme.find(a.cfg.theme), true);

        audio.init();
        if (!audio.ok) ui.toast(.err, a.t.audio_failed);
        _ = audio.setOutput(.monitor, a.cfg.monitor_device);
        if (a.cfg.mic_device.len > 0 and !audio.setOutput(.mic, a.cfg.mic_device)) {
            std.log.warn("virtual mic device \"{s}\" not found", .{a.cfg.mic_device});
        }
        audio.applyVolumes(&a.cfg);

        stats.load();
        a.openLibrary();
        tools.init();
        tools.detect(&a.cfg);
        jobs.init();
        remote.apply(&a.cfg);
        if (a.cfg.global_hotkeys) hotkeys.start();
        ipc.listen();

        a.online.dlg_normalize = a.cfg.normalize_audio;
        a.explore.source = @backingInt(a.cfg.explore_source);
        a.online.platform = @backingInt(a.cfg.online_platform);
        a.onboarding_open = !a.cfg.onboarding_done;
        // pactl forgets loopback volumes when PipeWire restarts
        if (a.cfg.voice_volume != 1 or a.cfg.voice_muted) vmic.setVoice(a.cfg.voice_volume, a.cfg.voice_muted);
        a.rng ^= @bitCast(@as(i64, library.now()));
    }

    pub fn deinit(a: *App) void {
        a.flushSaves();
        remote.stop();
        hotkeys.stop();
        ipc.shutdown();
        a.queueClear();
        a.queue.items.deinit(gpa);
        a.bindings.deinit(gpa);
        a.unloadWorkspaceAudio();
        audio.deinit();
        a.jobs.deinit();
        a.lib.deinit();
        stats.deinit();
    }

    fn libraryRoot(a: *const App) ![]u8 {
        if (a.cfg.library_dir.len > 0) return gpa.dupe(u8, a.cfg.library_dir);
        return sys.defaultLibraryDir();
    }

    pub fn openLibrary(a: *App) void {
        a.queueClear();
        a.unloadWorkspaceAudio();
        const root = a.libraryRoot() catch return;
        defer gpa.free(root);
        a.lib.open(root, a.t.default_workspace) catch |err| {
            ui.toastFmt(.err, "Library: {s}", .{@errorName(err)});
            return;
        };
        a.ws = a.lib.find(a.cfg.active_workspace) orelse 0;
        a.loadWorkspaceAudio();
    }

    // ── Workspaces ──────────────────────────────────────────────────────────

    pub fn workspace(a: *App) *library.Workspace {
        return &a.lib.workspaces.items[a.ws];
    }

    fn loadWorkspaceAudio(a: *App) void {
        if (a.lib.workspaces.items.len == 0) return;
        const ws = a.workspace();
        for (ws.sounds.items) |*s| a.loadSound(ws, s);
        a.bindings_dirty = true;
        a.ws_generation +%= 1;
    }

    fn loadSound(_: *App, ws: *library.Workspace, s: *library.Sound) void {
        const path = ws.soundPath(s) catch return;
        defer gpa.free(path);
        s.audio_id = audio.load(path);
        if (s.audio_id < 0) {
            std.log.warn("could not load {s}", .{path});
            return;
        }
        audio.setParams(s.audio_id, s.params());
        audio.setFx(s.audio_id, &s.fx);
    }

    fn unloadWorkspaceAudio(a: *App) void {
        if (a.ws >= a.lib.workspaces.items.len) return;
        for (a.workspace().sounds.items) |*s| {
            audio.unload(s.audio_id);
            s.audio_id = -1;
        }
    }

    /// After an output device changes. The engine reloads its sounds by
    /// itself; volumes are re-applied because each output owns its own.
    pub fn reloadAudio(a: *App) void {
        audio.applyVolumes(&a.cfg);
    }

    pub fn switchWorkspace(a: *App, idx: usize) void {
        if (idx >= a.lib.workspaces.items.len) return;
        if (idx == a.ws) return;
        a.flushSaves();
        a.queueClear();
        a.unloadWorkspaceAudio();
        a.ws = idx;
        config.setString(&a.cfg.active_workspace, a.workspace().name);
        a.markConfig();
        a.search.clear();
        a.loadWorkspaceAudio();
    }

    pub fn createWorkspace(a: *App, name: []const u8) void {
        if (std.mem.trim(u8, name, " ").len == 0) return;
        const active_name = gpa.dupe(u8, a.workspace().name) catch return;
        defer gpa.free(active_name);
        const idx = a.lib.createWorkspace(name) catch |err| {
            ui.toastFmt(.err, "{s}", .{@errorName(err)});
            return;
        };
        // Sorting may have moved the active workspace
        a.ws = a.lib.find(active_name) orelse 0;
        a.switchWorkspace(idx);
        ui.toast(.success, a.t.ws_created);
    }

    pub fn renameWorkspace(a: *App, idx: usize, name: []const u8) void {
        const active_name = gpa.dupe(u8, a.workspace().name) catch return;
        defer gpa.free(active_name);
        const was_active = idx == a.ws;
        a.lib.renameWorkspace(idx, name) catch |err| {
            ui.toast(.err, if (err == error.AlreadyExists) a.t.ws_exists else @errorName(err));
            return;
        };
        if (was_active) {
            var buf: [128]u8 = undefined;
            const clean = sys.sanitizeFileName(&buf, std.mem.trim(u8, name, " "));
            a.ws = a.lib.find(clean) orelse 0;
            config.setString(&a.cfg.active_workspace, a.workspace().name);
            a.markConfig();
        } else {
            a.ws = a.lib.find(active_name) orelse 0;
        }
    }

    pub fn deleteWorkspace(a: *App, idx: usize) void {
        if (idx == a.ws) {
            a.queueClear();
            a.unloadWorkspaceAudio();
        }
        const active_name = gpa.dupe(u8, a.workspace().name) catch return;
        defer gpa.free(active_name);
        const deleting_active = idx == a.ws;
        a.lib.deleteWorkspace(idx);
        if (a.lib.workspaces.items.len == 0) {
            _ = a.lib.createWorkspace(a.t.default_workspace) catch {};
        }
        a.ws = if (deleting_active) 0 else (a.lib.find(active_name) orelse 0);
        if (deleting_active) a.loadWorkspaceAudio();
        config.setString(&a.cfg.active_workspace, a.workspace().name);
        a.markConfig();
        a.bindings_dirty = true;
    }

    // ── Sounds ──────────────────────────────────────────────────────────────

    /// A pad click or hotkey: queues the sound in queue mode, plays it otherwise
    pub fn playSound(a: *App, idx: usize) void {
        const ws = a.workspace();
        // A paused pad always continues, even in queue mode
        const paused = idx < ws.sounds.items.len and audio.isPaused(ws.sounds.items[idx].audio_id);
        if (a.cfg.queue_mode and !paused) a.enqueue(idx) else a.playNow(idx);
    }

    pub fn playNow(a: *App, idx: usize) void {
        const ws = a.workspace();
        if (idx >= ws.sounds.items.len) return;
        const s = &ws.sounds.items[idx];
        if (s.audio_id < 0) a.loadSound(ws, s);
        // A paused pad continues where it stopped
        if (audio.isPaused(s.audio_id)) {
            audio.@"resume"(s.audio_id);
            return;
        }
        audio.play(s.audio_id, a.padVolume(s, s.volume), a.cfg.play_mode);
        a.countPlay(s);
    }

    /// What a pad plays at: its own volume, times the normalization gain when on
    pub fn padVolume(a: *const App, s: *const library.Sound, volume: f32) f32 {
        if (!a.cfg.normalize_library) return volume;
        return volume * loudness.gainFor(s, a.cfg.normalize_target);
    }

    /// Measures the active workspace's sounds one by one while normalization is on
    fn updateLoudness(a: *App) void {
        if (!a.cfg.normalize_library) return;
        const ws = a.workspace();
        for (ws.sounds.items) |*s| {
            if (s.loudness != 0) continue;
            var path_buf: [1024]u8 = undefined;
            const path = std.fmt.bufPrint(&path_buf, "{s}{c}{s}", .{ ws.dir, std.fs.path.sep, s.file }) catch return;
            var failed = false;
            if (loudness.get(path, &failed)) |r| {
                // Every pad that plays this file (variants) gets the result
                for (ws.sounds.items) |*o| {
                    if (!std.mem.eql(u8, o.file, s.file)) continue;
                    o.loudness = @min(r.loud, -0.01);
                    o.peak_db = r.peak;
                }
                a.markWorkspace();
            } else if (failed) {
                s.loudness = 1;
                a.markWorkspace();
            }
            return; // one file at a time
        }
    }

    /// How many sounds of the active workspace are measured (for the settings page)
    pub fn loudnessProgress(a: *App) struct { done: usize, total: usize } {
        var done: usize = 0;
        for (a.workspace().sounds.items) |s| {
            if (s.loudness != 0) done += 1;
        }
        return .{ .done = done, .total = a.workspace().sounds.items.len };
    }

    /// Statistics for a play that just started
    fn countPlay(a: *App, s: *library.Sound) void {
        s.plays += 1;
        s.last_played = library.now();
        stats.recordPlay(a.workspace().name, s);
        a.markWorkspace();
    }

    /// Stops every sound and the queue
    pub fn stopAll(a: *App) void {
        a.queue.current = null;
        audio.stopAll();
    }

    /// Pauses whatever plays, or resumes what was paused
    pub fn togglePause(a: *App) void {
        if (audio.playingCount() > 0) {
            audio.pauseAll();
        } else if (audio.pausedCount() > 0) {
            audio.resumeAll();
        } else if (a.queue.current == null and a.queue.items.items.len > 0) {
            a.queuePlayAt(0);
        }
    }

    pub fn anythingPaused(_: *App) bool {
        return audio.playingCount() == 0 and audio.pausedCount() > 0;
    }

    /// Plays a random sound from what the soundboard shows (never the same twice in a row)
    pub fn playRandom(a: *App) void {
        const ws = a.workspace();
        const n = ws.sounds.items.len;
        if (n == 0) return;
        const pool_len = if (a.view.items.len > 0) a.view.items.len else n;
        var pick: usize = 0;
        for (0..4) |_| {
            const r: usize = @intCast(a.nextRandom() % pool_len);
            pick = if (a.view.items.len > 0) a.view.items[r] else r;
            if (pool_len < 2 or a.last_random == null or a.last_random.? != pick) break;
        }
        a.last_random = pick;
        a.playSound(pick);
    }

    fn nextRandom(a: *App) u64 {
        // splitmix64
        a.rng +%= 0x9E37_79B9_7F4A_7C15;
        var z = a.rng;
        z = (z ^ (z >> 30)) *% 0xBF58_476D_1CE4_E5B9;
        z = (z ^ (z >> 27)) *% 0x94D0_49BB_1331_11EB;
        return z ^ (z >> 31);
    }

    /// Whether the virtual mic carries your real mic (asks pactl once, cached)
    pub fn voiceAvailable(a: *App) bool {
        if (sys.is_windows) return false;
        if (a.vmic_exists == null) {
            a.vmic_exists = vmic.exists();
            a.vmic_has_voice = a.vmic_exists.? and vmic.hasVoice();
        }
        return a.vmic_has_voice;
    }

    pub fn toggleVoiceMute(a: *App) void {
        if (!a.voiceAvailable()) {
            ui.toast(.info, a.t.voice_unavailable);
            return;
        }
        a.cfg.voice_muted = !a.cfg.voice_muted;
        vmic.setVoice(a.cfg.voice_volume, a.cfg.voice_muted);
        a.markConfig();
        ui.toast(.info, if (a.cfg.voice_muted) a.t.voice_muted_toast else a.t.voice_unmuted_toast);
    }

    // ── Queue ───────────────────────────────────────────────────────────────

    pub fn enqueue(a: *App, idx: usize) void {
        const ws = a.workspace();
        if (idx >= ws.sounds.items.len) return;
        a.queue.items.append(gpa, ws.sounds.items[idx].uid) catch return;
        // An idle queue starts right away, so queue mode feels like playing
        if (a.queue.current == null) {
            a.queuePlayAt(a.queue.items.items.len - 1);
        } else if (!a.cfg.queue_open) {
            // With the panel open the new row is feedback enough
            ui.toast(.info, a.tf(a.t.queued_sound, .{ws.sounds.items[idx].name}));
        }
    }

    /// Index in the workspace of a queue entry, if the sound still exists
    pub fn queueSound(a: *App, qi: usize) ?usize {
        if (qi >= a.queue.items.items.len) return null;
        return a.workspace().findByUid(a.queue.items.items[qi]);
    }

    pub fn queuePlayAt(a: *App, start: usize) void {
        var qi = start;
        while (qi < a.queue.items.items.len) : (qi += 1) {
            const idx = a.queueSound(qi) orelse continue; // deleted or moved away
            const ws = a.workspace();
            const s = &ws.sounds.items[idx];
            if (s.audio_id < 0) a.loadSound(ws, s);
            if (s.audio_id < 0) continue;
            audio.play(s.audio_id, a.padVolume(s, s.volume), .restart);
            a.countPlay(s);
            a.queue.current = qi;
            a.queue.started_at = ui.time;
            return;
        }
        a.queue.current = null;
    }

    fn queueCurrentId(a: *App) c_int {
        const qi = a.queue.current orelse return -1;
        const idx = a.queueSound(qi) orelse return -1;
        return a.workspace().sounds.items[idx].audio_id;
    }

    pub fn queueNext(a: *App) void {
        const qi = a.queue.current orelse {
            if (a.queue.items.items.len > 0) a.queuePlayAt(0);
            return;
        };
        audio.stop(a.queueCurrentId());
        a.queueAdvanceFrom(qi);
    }

    fn queueAdvanceFrom(a: *App, qi: usize) void {
        if (qi + 1 < a.queue.items.items.len) {
            a.queuePlayAt(qi + 1);
        } else if (a.cfg.queue_repeat and a.queue.items.items.len > 0) {
            a.queuePlayAt(0);
        } else {
            a.queue.current = null;
        }
    }

    pub fn queuePrev(a: *App) void {
        const qi = a.queue.current orelse return;
        audio.stop(a.queueCurrentId());
        // Like music players: early on goes back, later restarts the current one
        a.queuePlayAt(if (ui.time - a.queue.started_at < 2 and qi > 0) qi - 1 else qi);
    }

    pub fn queueStop(a: *App) void {
        audio.stop(a.queueCurrentId());
        a.queue.current = null;
    }

    /// A sound was stopped by hand: if the queue was playing it, the queue stops too
    pub fn queueForget(a: *App, uid: u32) void {
        const qi = a.queue.current orelse return;
        if (qi < a.queue.items.items.len and a.queue.items.items[qi] == uid) a.queue.current = null;
    }

    pub fn queueClear(a: *App) void {
        a.queueStop();
        a.queue.items.clearRetainingCapacity();
        a.queue.drag = null;
    }

    pub fn queueRemove(a: *App, qi: usize) void {
        if (qi >= a.queue.items.items.len) return;
        const was_current = a.queue.current != null and a.queue.current.? == qi;
        if (was_current) audio.stop(a.queueCurrentId());
        _ = a.queue.items.orderedRemove(qi);
        if (a.queue.current) |cur| {
            if (was_current) {
                if (qi < a.queue.items.items.len) a.queuePlayAt(qi) else a.queue.current = null;
            } else if (qi < cur) {
                a.queue.current = cur - 1;
            }
        }
    }

    pub fn queueMove(a: *App, from: usize, to: usize) void {
        const items = a.queue.items.items;
        if (from >= items.len or to >= items.len or from == to) return;
        const moved = items[from];
        if (from < to) {
            std.mem.copyForwards(u32, items[from..to], items[from + 1 .. to + 1]);
        } else {
            std.mem.copyBackwards(u32, items[to + 1 .. from + 1], items[to..from]);
        }
        items[to] = moved;
        if (a.queue.current) |cur| {
            if (cur == from) {
                a.queue.current = to;
            } else if (from < cur and to >= cur) {
                a.queue.current = cur - 1;
            } else if (from > cur and to <= cur) {
                a.queue.current = cur + 1;
            }
        }
    }

    /// Shuffles what hasn't played yet
    pub fn queueShuffle(a: *App) void {
        const items = a.queue.items.items;
        const first = if (a.queue.current) |cur| cur + 1 else 0;
        if (items.len < first + 2) return;
        var i = items.len - 1;
        while (i > first) : (i -= 1) {
            const j = first + @as(usize, @intCast(a.nextRandom() % (i - first + 1)));
            std.mem.swap(u32, &items[i], &items[j]);
        }
    }

    /// Queue position of a pad's sound (first pending occurrence), for its badge
    pub fn queuePosition(a: *App, uid: u32) ?usize {
        const first = a.queue.current orelse return null;
        for (a.queue.items.items[@min(first, a.queue.items.items.len)..], first..) |u, qi| {
            if (u == uid) return qi;
        }
        return null;
    }

    fn updateQueue(a: *App) void {
        const qi = a.queue.current orelse return;
        const id = a.queueCurrentId();
        // Grace period: async decoding may not have started the voice yet
        if (ui.time - a.queue.started_at < 0.3) return;
        if (id >= 0 and (audio.isPlaying(id) or audio.isPaused(id))) return;
        a.queueAdvanceFrom(qi);
    }

    pub fn findSoundByName(a: *App, name: []const u8) ?usize {
        const ws = a.workspace();
        for (ws.sounds.items, 0..) |s, i| {
            if (std.ascii.eqlIgnoreCase(s.name, name)) return i;
        }
        for (ws.sounds.items, 0..) |s, i| {
            if (std.ascii.findIgnoreCase(s.name, name) != null) return i;
        }
        return null;
    }

    pub fn addRipple(a: *App, pad: usize, x: f32, y: f32) void {
        if (a.ripple_count == a.ripples.len) {
            std.mem.copyForwards(Ripple, a.ripples[0 .. a.ripples.len - 1], a.ripples[1..]);
            a.ripple_count -= 1;
        }
        a.ripples[a.ripple_count] = .{ .pad = pad, .x = x, .y = y, .born = ui.time };
        a.ripple_count += 1;
    }

    pub fn importPaths(a: *App, paths: []const []const u8) void {
        var imported: usize = 0;
        for (paths) |p| {
            if (sys.isDir(p)) {
                const entries = sys.listDir(p) catch continue;
                defer sys.freeEntries(entries);
                for (entries) |e| {
                    if (e.is_dir or !library.isAudioFile(e.name)) continue;
                    const full = sys.join(&.{ p, e.name }) catch continue;
                    defer gpa.free(full);
                    if (a.importOne(full)) imported += 1;
                }
                continue;
            }
            if (!library.isAudioFile(p)) {
                ui.toast(.warning, a.tf(a.t.file_unsupported, .{std.fs.path.basename(p)}));
                continue;
            }
            if (a.importOne(p)) imported += 1;
        }
        if (imported > 0) ui.toast(.success, a.tf(a.t.imported_n, .{imported}));
    }

    fn importOne(a: *App, path: []const u8) bool {
        const idx = a.lib.importFile(a.ws, path) catch {
            ui.toast(.err, a.tf(a.t.import_failed, .{std.fs.path.basename(path)}));
            return false;
        };
        const ws = a.workspace();
        a.loadSound(ws, &ws.sounds.items[idx]);
        return true;
    }

    pub fn openImportDialog(a: *App) void {
        const patterns = [_][*c]const u8{ "*.mp3", "*.wav", "*.ogg", "*.flac" };
        const title = a.tfz(a.t.import_files_title, .{});
        const result = c.tinyfd_openFileDialog(title.ptr, null, patterns.len, &patterns, "Audio", 1) orelse return;
        const s = std.mem.span(result);
        var list: std.ArrayList([]const u8) = .empty;
        defer list.deinit(gpa);
        var it = std.mem.splitScalar(u8, s, '|');
        while (it.next()) |p| {
            if (p.len > 0) list.append(gpa, p) catch {};
        }
        a.importPaths(list.items);
    }

    /// Copies a sound (file and settings, not the hotkey) into the same workspace
    pub fn duplicateSound(a: *App, idx: usize) void {
        const ws = a.workspace();
        if (idx >= ws.sounds.items.len) return;
        const src = ws.sounds.items[idx];
        const src_path = sys.join(&.{ ws.dir, src.file }) catch return;
        defer gpa.free(src_path);
        const new_idx = a.lib.importFile(a.ws, src_path) catch {
            ui.toast(.err, a.tf(a.t.import_failed, .{src.name}));
            return;
        };
        const copy = &a.workspace().sounds.items[new_idx];
        const original = a.workspace().sounds.items[idx];
        copy.setName(a.tf(a.t.copy_name, .{original.name})) catch {};
        copy.color = original.color;
        copy.volume = original.volume;
        copy.setParams(original.params());
        copy.fx = original.fx;
        a.lib.save(a.ws) catch {};
        a.loadSound(a.workspace(), copy);
        ui.toast(.success, a.t.duplicated);
    }

    /// Another pad for the same file, e.g. "BRUH (Demonic)". Opens its effects.
    pub fn createVariant(a: *App, idx: usize, preset: ?usize) void {
        const ws = a.workspace();
        if (idx >= ws.sounds.items.len) return;
        const src = ws.sounds.items[idx];
        var chain: fx.Chain = src.fx;
        var suffix: []const u8 = a.t.variant_suffix;
        if (preset) |p| {
            if (p < fx.builtins.len) {
                chain = fx.Chain.fromSlice(fx.builtins[p].effects);
                suffix = a.t.fx_preset_names[fx.builtins[p].name];
            }
        }
        const name = a.tf("{} ({})", .{ src.name, suffix });
        const new_idx = a.lib.addVariant(a.ws, idx, name, chain) catch |err| {
            ui.toastFmt(.err, "{s}", .{@errorName(err)});
            return;
        };
        const v = &a.workspace().sounds.items[new_idx];
        a.loadSound(a.workspace(), v);
        a.bindings_dirty = true;
        ui.toast(.success, a.t.variant_created);
        a.openEditor(new_idx);
        a.editor.tab = .effects;
    }

    pub fn deleteSound(a: *App, idx: usize) void {
        const ws = a.workspace();
        if (idx >= ws.sounds.items.len) return;
        audio.unload(ws.sounds.items[idx].audio_id);
        a.lib.removeSound(a.ws, idx, true);
        a.bindings_dirty = true;
    }

    pub fn moveSound(a: *App, idx: usize, to: usize) void {
        const ws = a.workspace();
        if (idx >= ws.sounds.items.len or to == a.ws) return;
        audio.unload(ws.sounds.items[idx].audio_id);
        ws.sounds.items[idx].audio_id = -1;
        a.lib.moveSound(a.ws, idx, to) catch |err| {
            ui.toastFmt(.err, "{s}", .{@errorName(err)});
            a.loadSound(ws, &ws.sounds.items[idx]);
            return;
        };
        ui.toast(.success, a.tf(a.t.sound_moved, .{a.lib.workspaces.items[to].name}));
        a.bindings_dirty = true;
    }

    // ── Editor ──────────────────────────────────────────────────────────────

    pub fn openEditor(a: *App, idx: usize) void {
        const s = &a.workspace().sounds.items[idx];
        a.editor = .{};
        a.editor.name.set(s.name);
        a.editor.color = s.color;
        a.editor.volume = s.volume;
        a.editor.favorite = s.favorite;
        a.editor.setHotkey(s.hotkey);
        a.editor.params = s.params();
        a.editor.original = s.params();
        a.editor.fx = s.fx;
        a.editor.original_fx = s.fx;
        a.editor.view_len = 0; // fit on first draw
        a.capture = .none;
        a.dialog = .{ .edit_sound = idx };
    }

    /// Lets the editor's preview button hear changes before saving
    pub fn previewEditorParams(a: *App, idx: usize) void {
        const ws = a.workspace();
        if (idx >= ws.sounds.items.len) return;
        audio.setParams(ws.sounds.items[idx].audio_id, a.editor.params);
    }

    pub fn previewEditorFx(a: *App, idx: usize) void {
        const ws = a.workspace();
        if (idx >= ws.sounds.items.len) return;
        audio.setFx(ws.sounds.items[idx].audio_id, &a.editor.fx);
    }

    /// Editor closed without saving
    pub fn cancelEditor(a: *App, idx: usize) void {
        const ws = a.workspace();
        if (idx >= ws.sounds.items.len) return;
        const s = &ws.sounds.items[idx];
        audio.stop(s.audio_id);
        audio.setParams(s.audio_id, s.params());
        audio.setFx(s.audio_id, &s.fx);
    }

    pub fn saveEditor(a: *App, idx: usize) void {
        const ws = a.workspace();
        if (idx >= ws.sounds.items.len) return;
        const s = &ws.sounds.items[idx];
        const name = std.mem.trim(u8, a.editor.name.text(), " ");
        if (name.len > 0) s.setName(name) catch {};
        s.color = a.editor.color;
        s.volume = a.editor.volume;
        s.favorite = a.editor.favorite;
        s.setHotkey(a.editor.hotkeyText()) catch {};
        s.setParams(a.editor.params);
        s.fx = a.editor.fx;
        audio.setParams(s.audio_id, s.params());
        audio.setFx(s.audio_id, &s.fx);
        a.editor.saved = true;
        a.lib.save(a.ws) catch {};
        a.bindings_dirty = true;
    }

    /// Which sound already uses this hotkey (to warn about conflicts)
    pub fn hotkeyOwner(a: *App, hk_text: []const u8, except: ?usize) ?usize {
        const hk = hotkeys.parse(hk_text) orelse return null;
        for (a.workspace().sounds.items, 0..) |s, i| {
            if (except != null and except.? == i) continue;
            const other = hotkeys.parse(s.hotkey) orelse continue;
            if (other.eql(hk)) return i;
        }
        return null;
    }

    pub fn startEditJob(a: *App, idx: usize) void {
        const ws = a.workspace();
        const s = &ws.sounds.items[idx];
        const input = sys.join(&.{ ws.dir, s.file }) catch return;
        defer gpa.free(input);
        _ = a.jobs.add(.{
            .kind = .edit,
            .title = s.name,
            .url = input,
            .workspace_name = ws.name,
            .sound_name = s.file,
            .sound_uid = s.uid,
            .post = .{
                .normalize = a.editor.normalize,
                .start = if (a.editor.params.trim_start > 0) a.editor.params.trim_start else null,
                .end = if (a.editor.params.trim_end > 0) a.editor.params.trim_end else null,
            },
        }) catch return;
        ui.toast(.info, a.t.processing);
    }

    // ── Explore ─────────────────────────────────────────────────────────────

    pub fn exploreQuery(a: *App, kind: QueryKind, text: []const u8, category: ?usize) void {
        const e = &a.explore;
        if (e.task) |t| t.release();
        e.task = null;
        for (e.items.items) |it| it.deinit();
        e.items.clearRetainingCapacity();
        e.kind = kind;
        e.query_len = @min(text.len, e.query.len);
        @memcpy(e.query[0..e.query_len], text[0..e.query_len]);
        e.category = category;
        e.page = 0;
        e.has_more = false;
        e.failed = false;
        e.loaded = true;
        e.generation +%= 1;
        a.exploreLoadMore();
    }

    pub fn exploreLoadMore(a: *App) void {
        const e = &a.explore;
        if (e.task != null) return;
        const source: config.ExploreSource = @fromBackingInt(@intCast(e.source));
        const query: market.Query = switch (e.kind) {
            .trending => .trending,
            .search => .{ .search = e.queryText() },
            .category => .{ .category = e.queryText() },
        };
        e.failed = false;
        e.task = jobs.MarketTask.start(source, query, e.page + 1, source == .soundbuttonsworld and e.sbw_categories.items.len == 0) catch null;
    }

    fn pollExplore(a: *App) void {
        const e = &a.explore;
        const task = e.task orelse return;
        switch (task.state()) {
            .running, .abandoned => return,
            .done => {
                e.items.appendSlice(gpa, task.result.items.items) catch {};
                task.result.items.clearRetainingCapacity(); // ownership moved
                e.has_more = task.result.has_more;
                e.page += 1;
                if (task.categories) |*cats| {
                    for (e.sbw_categories.items) |s| gpa.free(s);
                    e.sbw_categories.clearRetainingCapacity();
                    e.sbw_categories.appendSlice(gpa, cats.items) catch {};
                    cats.clearRetainingCapacity();
                }
            },
            .failed => e.failed = true,
        }
        task.release();
        e.task = null;
    }

    pub fn previewItem(a: *App, url: []const u8) void {
        const e = &a.explore;
        // Clicking the item that is playing stops it
        if (std.mem.eql(u8, e.preview_url, url) and (audio.previewPlaying() or e.preview_task != null)) {
            a.stopPreview();
            return;
        }
        a.stopPreview();
        gpa.free(e.preview_url);
        e.preview_url = gpa.dupe(u8, url) catch &.{};
        e.preview_task = jobs.PreviewTask.start(url) catch null;
        e.preview_started = false;
    }

    pub fn stopPreview(a: *App) void {
        const e = &a.explore;
        if (e.preview_task) |t| t.release();
        e.preview_task = null;
        audio.previewStop();
        gpa.free(e.preview_url);
        e.preview_url = &.{};
    }

    fn pollPreview(a: *App) void {
        const e = &a.explore;
        const task = e.preview_task orelse return;
        switch (task.state()) {
            .running, .abandoned => return,
            .done => {
                const path = gpa.dupeSentinel(u8, task.path, 0) catch return;
                defer gpa.free(path);
                if (!audio.previewPlay(path, a.cfg.preview_volume * a.cfg.master_volume)) ui.toast(.err, a.t.preview_failed);
                e.preview_started = true;
            },
            .failed => ui.toast(.err, a.t.preview_failed),
        }
        task.release();
        e.preview_task = null;
    }

    pub fn previewProgressFor(a: *App, url: []const u8) ?f32 {
        const e = &a.explore;
        if (!std.mem.eql(u8, e.preview_url, url)) return null;
        if (e.preview_task != null) return -1; // still downloading
        if (audio.previewPlaying()) return audio.previewProgress();
        return null;
    }

    pub fn addMarketItem(a: *App, item: *const market.Item, ws_idx: usize) void {
        const ws = &a.lib.workspaces.items[@min(ws_idx, a.lib.workspaces.items.len - 1)];
        const cached = jobs.previewPath(item.audio_url) catch null;
        defer if (cached) |p| gpa.free(p);
        _ = a.jobs.add(.{
            .kind = .sound,
            .title = item.name,
            .url = item.audio_url,
            .local_source = if (cached) |p| (if (sys.exists(p)) p else "") else "",
            .workspace_dir = ws.dir,
            .workspace_name = ws.name,
            .sound_name = item.name,
            .use_ffmpeg = a.cfg.normalize_audio or a.cfg.max_clip_seconds > 0,
            .post = .{ .format = .mp3, .normalize = a.cfg.normalize_audio, .max_seconds = a.cfg.max_clip_seconds },
        }) catch return;
        const key = gpa.dupe(u8, item.audio_url) catch return;
        a.explore.added.put(gpa, key, {}) catch gpa.free(key);
    }

    // ── Online ──────────────────────────────────────────────────────────────

    pub fn onlineSearch(a: *App) void {
        const o = &a.online;
        const q = std.mem.trim(u8, o.search.text(), " ");
        if (q.len == 0) return;
        if (o.task) |t| t.release();
        for (o.results.items) |r| r.deinit();
        o.results.clearRetainingCapacity();
        o.failed = false;
        o.searched = true;
        o.generation +%= 1;
        const platform: tools.Platform = if (o.platform == 1) .soundcloud else .youtube;
        o.task = jobs.MediaTask.start(platform, q, a.cfg.results_per_search) catch null;
    }

    fn pollOnline(a: *App) void {
        const o = &a.online;
        const task = o.task orelse return;
        switch (task.state()) {
            .running, .abandoned => return,
            .done => {
                o.results.appendSlice(gpa, task.results.items) catch {};
                task.results.clearRetainingCapacity();
            },
            .failed => o.failed = true,
        }
        task.release();
        o.task = null;
    }

    pub fn openDownloadDialog(a: *App, url: []const u8, title: []const u8, duration: f32) void {
        const o = &a.online;
        gpa.free(o.dlg_url);
        gpa.free(o.dlg_title);
        o.dlg_url = gpa.dupe(u8, url) catch &.{};
        o.dlg_title = gpa.dupe(u8, title) catch &.{};
        o.dlg_duration = duration;
        o.dlg_name.set(cleanTitle(title));
        o.dlg_start.clear();
        o.dlg_end.clear();
        o.dlg_normalize = a.cfg.normalize_audio;
        o.dlg_target = a.ws;
        a.dialog = .download_media;
    }

    pub fn confirmDownload(a: *App) void {
        const o = &a.online;
        const ws = &a.lib.workspaces.items[@min(o.dlg_target, a.lib.workspaces.items.len - 1)];
        const name = std.mem.trim(u8, o.dlg_name.text(), " ");
        const start = parseSeconds(o.dlg_start.text());
        const end = parseSeconds(o.dlg_end.text());
        _ = a.jobs.add(.{
            .kind = .media,
            .title = if (name.len > 0) name else o.dlg_title,
            .url = o.dlg_url,
            .workspace_dir = ws.dir,
            .workspace_name = ws.name,
            .sound_name = if (name.len > 0) name else cleanTitle(o.dlg_title),
            .media = .{ .format = a.cfg.download_format },
            .use_ffmpeg = o.dlg_normalize or start != null or end != null or a.cfg.max_clip_seconds > 0,
            .post = .{
                .format = a.cfg.download_format,
                .normalize = o.dlg_normalize,
                .start = start,
                .end = end,
                .max_seconds = if (start == null and end == null) a.cfg.max_clip_seconds else 0,
            },
        }) catch return;
        ui.toast(.info, a.t.queued_toast);
    }

    pub fn installTool(a: *App, tool: tools.Tool) void {
        if (a.jobs.isInstalling(tool) != null) return;
        const title = switch (tool) {
            .ytdlp => "yt-dlp",
            .ffmpeg => "ffmpeg",
            .deno => "Deno",
        };
        _ = a.jobs.add(.{ .kind = .tool, .title = title, .tool = tool }) catch return;
    }

    // ── Finished jobs ───────────────────────────────────────────────────────

    fn handleJob(a: *App, j: *jobs.Job) void {
        switch (j.getState()) {
            .failed => ui.toast(.err, a.tf(a.t.download_failed_toast, .{j.errorText()})),
            .canceled => {},
            .done => switch (j.kind) {
                .tool => {
                    tools.detect(&a.cfg);
                    ui.toast(.success, a.tf(a.t.tool_installed, .{j.title}));
                },
                .sound, .media => {
                    const ws_idx = a.lib.find(j.workspace_name) orelse return;
                    const display = if (j.sound_name.len > 0) j.sound_name else library.stem(j.result);
                    const idx = a.lib.adopt(ws_idx, j.result, display, j.url) catch return;
                    if (ws_idx == a.ws) {
                        const ws = a.workspace();
                        a.loadSound(ws, &ws.sounds.items[idx]);
                    }
                    ui.toast(.success, a.tf(a.t.download_done_toast, .{display}));
                },
                .edit => a.finishEdit(j),
            },
            else => {},
        }
    }

    fn finishEdit(a: *App, j: *jobs.Job) void {
        const ws_idx = a.lib.find(j.workspace_name) orelse return;
        const ws = &a.lib.workspaces.items[ws_idx];
        const idx = ws.findByUid(j.sound_uid) orelse ws.findByFile(j.sound_name) orelse return;
        const s = &ws.sounds.items[idx];
        audio.unload(s.audio_id);
        s.audio_id = -1;
        if (ws.fileUsers(s.file) > 1) {
            // Variants keep the uncut file; this pad gets a file of its own
            const new_name = library.uniqueName(ws.dir, library.stem(s.name), std.fs.path.extension(s.file)) catch return;
            const dest = sys.join(&.{ ws.dir, new_name }) catch {
                gpa.free(new_name);
                return;
            };
            defer gpa.free(dest);
            sys.rename(j.result, dest) catch sys.copyFile(j.result, dest) catch {};
            gpa.free(s.file);
            s.file = new_name;
            s.trim_start = 0;
            s.trim_end = 0;
            s.loudness = 0;
            a.lib.save(ws_idx) catch {};
            if (ws_idx == a.ws) a.loadSound(ws, s);
            ui.toast(.success, a.t.edit_done);
            return;
        }
        const original = sys.join(&.{ ws.dir, s.file }) catch return;
        defer gpa.free(original);
        sys.deleteFile(original);
        sys.rename(j.result, original) catch sys.copyFile(j.result, original) catch {};
        // The cut is now in the file itself
        s.trim_start = 0;
        s.trim_end = 0;
        s.loudness = 0;
        loudness.invalidate(original);
        a.lib.save(ws_idx) catch {};
        waves.invalidate(original);
        if (ws_idx == a.ws) a.loadSound(ws, s);
        ui.toast(.success, a.t.edit_done);
    }

    // ── Per-frame update ────────────────────────────────────────────────────

    pub fn update(a: *App) void {
        a.t = i18n.get(a.cfg.language);

        while (a.jobs.update()) |j| a.handleJob(j);
        audio.update();
        a.updatePlayback();
        a.updateLoudness();
        a.updateQueue();
        a.pollExplore();
        a.pollPreview();
        a.pollOnline();

        // Files dropped on the window
        if (c.IsFileDropped()) {
            const dropped = c.LoadDroppedFiles();
            defer c.UnloadDroppedFiles(dropped);
            var list: std.ArrayList([]const u8) = .empty;
            defer list.deinit(gpa);
            for (dropped.paths[0..dropped.count]) |p| list.append(gpa, std.mem.span(p)) catch {};
            a.importPaths(list.items);
        }

        // Commands from `WooferSoundPad --play …`
        while (ipc.poll()) |cmd| switch (cmd.verb) {
            .play => if (a.findSoundByName(cmd.argument())) |i| a.playNow(i) else ui.toast(.warning, a.tf(a.t.not_found_play, .{cmd.argument()})),
            .queue => if (a.findSoundByName(cmd.argument())) |i| a.enqueue(i) else ui.toast(.warning, a.tf(a.t.not_found_play, .{cmd.argument()})),
            .stop => a.stopAll(),
            .pause => a.togglePause(),
            .next => a.queueNext(),
            .random => a.playRandom(),
            .mute_voice => a.toggleVoiceMute(),
            .workspace => if (a.lib.find(cmd.argument())) |i| a.switchWorkspace(i),
            .show => c.SetWindowFocused(),
            .quit => {},
        };

        a.updateRemote();
        a.updateHotkeys();
        a.updateSaves();
    }

    // ── OBS / Stream Deck ───────────────────────────────────────────────────

    fn updateRemote(a: *App) void {
        var buf: [256]u8 = undefined;
        while (remote.poll(&buf)) |cmd| a.runRemote(cmd.verb, cmd.arg);
        if (remote.shouldPublish()) a.publishRemote();
    }

    /// Sound named by a remote command: "#<uid>" or a name
    fn remoteSound(a: *App, arg: []const u8) ?usize {
        if (arg.len > 1 and arg[0] == '#') {
            const uid = std.fmt.parseInt(u32, arg[1..], 10) catch return null;
            return a.workspace().findByUid(uid);
        }
        if (arg.len == 0) return null;
        return a.findSoundByName(arg);
    }

    fn runRemote(a: *App, verb: []const u8, arg: []const u8) void {
        const eql = std.mem.eql;
        if (eql(u8, verb, "play")) {
            if (a.remoteSound(arg)) |i| a.playNow(i);
        } else if (eql(u8, verb, "queue")) {
            if (a.remoteSound(arg)) |i| a.enqueue(i);
        } else if (eql(u8, verb, "stop")) {
            a.stopAll();
        } else if (eql(u8, verb, "pause")) {
            a.togglePause();
        } else if (eql(u8, verb, "fade")) {
            a.fadeOutAll();
        } else if (eql(u8, verb, "next")) {
            a.queueNext();
        } else if (eql(u8, verb, "random")) {
            a.playRandom();
        } else if (eql(u8, verb, "mute_voice")) {
            a.toggleVoiceMute();
        } else if (eql(u8, verb, "stage")) {
            a.setStage(!a.stage);
        } else if (eql(u8, verb, "workspace")) {
            if (a.lib.find(arg)) |i| a.switchWorkspace(i);
        } else if (eql(u8, verb, "show")) {
            c.SetWindowFocused();
        }
    }

    fn publishRemote(a: *App) void {
        const ws = a.workspace();
        var ws_names: [64][]const u8 = undefined;
        const n_ws = @min(a.lib.workspaces.items.len, ws_names.len);
        for (a.lib.workspaces.items[0..n_ws], 0..) |w, i| ws_names[i] = w.name;

        const n = ws.sounds.items.len;
        const sounds = gpa.alloc(remote.SoundState, n) catch return;
        defer gpa.free(sounds);
        const colors = gpa.alloc([7]u8, n) catch return;
        defer gpa.free(colors);
        var playing: [256]remote.PlayingState = undefined;
        var n_playing: usize = 0;
        for (ws.sounds.items, 0..) |*s, i| {
            const hex = remote.colorHex(&colors[i], s.color);
            const is_playing = audio.isPlaying(s.audio_id);
            const is_paused = !is_playing and audio.isPaused(s.audio_id);
            sounds[i] = .{ .uid = s.uid, .name = s.name, .color = hex, .hotkey = s.hotkey, .fx = s.fx.active(), .playing = is_playing };
            if ((is_playing or is_paused) and n_playing < playing.len) {
                const speed = if (s.speed > 0.01) s.speed else 1;
                const p = audio.progress(s.audio_id);
                playing[n_playing] = .{
                    .uid = s.uid,
                    .name = s.name,
                    .color = hex,
                    .progress = p,
                    .left = audio.length(s.audio_id) / speed * (1 - p),
                    .paused = is_paused,
                    .loop = s.loop,
                };
                n_playing += 1;
            }
        }
        remote.publish(.{
            .workspace = ws.name,
            .workspaces = ws_names[0..n_ws],
            .master = a.cfg.master_volume,
            .stage = a.stage,
            .playing = playing[0..n_playing],
            .sounds = sounds,
        });
    }

    /// Meters and time-played statistics
    fn updatePlayback(a: *App) void {
        if (a.lib.workspaces.items.len == 0) return;
        var any = false;
        for (a.workspace().sounds.items) |*s| {
            if (s.audio_id < 0) continue;
            const peak = audio.level(s.audio_id);
            // Fast attack, slow release, like a VU meter
            s.level = if (peak > s.level) peak else s.level * @exp(-6 * ui.dt);
            if (s.level < 0.001) s.level = 0;
            if (audio.isPlaying(s.audio_id)) {
                s.play_seconds += ui.dt;
                any = true;
            }
        }
        if (any) {
            stats.addSeconds(ui.dt);
            a.play_time_unsaved = true;
        }
        if (stats.isDirty() and ui.time - a.stats_saved_at > 20) {
            stats.save();
            a.stats_saved_at = ui.time;
        }
        if (a.rec.state == .recording and !audio.recActive()) a.stopRecording();
    }

    // ── Mixer ───────────────────────────────────────────────────────────────

    pub fn fadeOutAll(a: *App) void {
        a.queue.current = null;
        for (a.workspace().sounds.items) |s| {
            if (audio.isPlaying(s.audio_id) or audio.isPaused(s.audio_id)) audio.fadeStop(s.audio_id, a.cfg.mixer_fade_seconds);
        }
        audio.previewStop();
    }

    /// Sounds playing or paused right now, in workspace order
    pub fn activeSounds(a: *App, out: []usize) []usize {
        var n: usize = 0;
        for (a.workspace().sounds.items, 0..) |s, i| {
            if (n == out.len) break;
            if (s.audio_id < 0) continue;
            if (audio.isPlaying(s.audio_id) or audio.isPaused(s.audio_id)) {
                out[n] = i;
                n += 1;
            }
        }
        return out[0..n];
    }

    // ── Stage mode ──────────────────────────────────────────────────────────

    pub fn setStage(a: *App, on: bool) void {
        if (a.stage == on) return;
        a.stage = on;
        a.menu = null;
        a.page_changed_at = ui.time;
        if (on and a.cfg.stage_fullscreen and !c.IsWindowState(c.FLAG_BORDERLESS_WINDOWED_MODE)) {
            c.ToggleBorderlessWindowed();
            a.stage_went_fullscreen = true;
        } else if (!on and a.stage_went_fullscreen) {
            if (c.IsWindowState(c.FLAG_BORDERLESS_WINDOWED_MODE)) c.ToggleBorderlessWindowed();
            a.stage_went_fullscreen = false;
        }
    }

    // ── Recorder ────────────────────────────────────────────────────────────

    pub fn openRecorder(a: *App) void {
        if (a.rec.state == .idle) {
            audio.refreshDevices();
            a.rec.target = a.ws;
            a.rec.source_idx = switch (a.cfg.rec_source) {
                -1 => 0,
                -2 => 1,
                else => |i| @intCast(i + 2),
            };
        }
        a.dialog = .record;
    }

    pub fn recSource(a: *const App) c_int {
        return switch (a.rec.source_idx) {
            0 => audio.rec_system,
            1 => audio.rec_default_mic,
            else => |i| @intCast(i - 2),
        };
    }

    pub fn startRecording(a: *App) void {
        a.rec.failed = false;
        const src = a.recSource();
        a.cfg.rec_source = src;
        a.markConfig();
        if (!audio.recStart(src)) {
            a.rec.failed = true;
            a.rec.state = .idle;
            ui.toast(.err, a.t.rec_failed);
            return;
        }
        a.rec.state = .recording;
        a.rec.started_at = ui.time;
        if (a.rec.name.len == 0) {
            var buf: [64]u8 = undefined;
            a.rec.name.set(std.fmt.bufPrint(&buf, "{s} {d}", .{ a.t.rec_default_name, a.workspace().sounds.items.len + 1 }) catch "Rec");
        }
    }

    pub fn stopRecording(a: *App) void {
        audio.recStop();
        a.rec.state = .recorded;
        const total = audio.recSeconds();
        a.rec.keep_start = 0;
        a.rec.keep_end = total;
        if (a.cfg.rec_auto_trim) {
            const peaks = audio.recPeaks();
            const thr: f32 = 0.012;
            var first: usize = 0;
            while (first < peaks.len and peaks[first] < thr) first += 1;
            var last: usize = peaks.len;
            while (last > first and peaks[last - 1] < thr) last -= 1;
            if (last > first) {
                const pps = audio.rec_peaks_per_second;
                a.rec.keep_start = @max(0, @as(f32, @floatFromInt(first)) / pps - 0.08);
                a.rec.keep_end = @min(total, @as(f32, @floatFromInt(last)) / pps + 0.15);
            }
        }
    }

    pub fn discardRecording(a: *App) void {
        audio.recDiscard();
        a.rec.state = .idle;
        a.rec.name.clear();
    }

    pub fn saveRecording(a: *App) void {
        const ws_idx = @min(a.rec.target, a.lib.workspaces.items.len - 1);
        const ws = &a.lib.workspaces.items[ws_idx];
        const raw = std.mem.trim(u8, a.rec.name.text(), " ");
        const name = if (raw.len > 0) raw else a.t.rec_default_name;
        const file = library.uniqueName(ws.dir, name, ".wav") catch return;
        defer gpa.free(file);
        const path = sys.joinZ(&.{ ws.dir, file }) catch return;
        defer gpa.free(path);
        if (!audio.recSave(path, a.rec.keep_start, a.rec.keep_end)) {
            ui.toast(.err, a.t.rec_save_failed);
            return;
        }
        const idx = a.lib.adopt(ws_idx, file, name, "") catch return;
        a.discardRecording();
        ui.toast(.success, a.tf(a.t.rec_saved, .{name}));
        if (ws_idx == a.ws) {
            const w = a.workspace();
            a.loadSound(w, &w.sounds.items[idx]);
            a.bindings_dirty = true;
            a.openEditor(idx);
        } else {
            a.switchWorkspace(ws_idx);
            a.openEditor(idx);
        }
    }

    fn rebuildBindings(a: *App) void {
        a.bindings.clearRetainingCapacity();
        const globals = [_]struct { text: []const u8, action: u32 }{
            .{ .text = a.cfg.stop_hotkey, .action = Action.stop },
            .{ .text = a.cfg.pause_hotkey, .action = Action.pause },
            .{ .text = a.cfg.next_hotkey, .action = Action.next },
            .{ .text = a.cfg.random_hotkey, .action = Action.random },
            .{ .text = a.cfg.mute_voice_hotkey, .action = Action.mute_voice },
        };
        for (globals) |g| {
            if (hotkeys.parse(g.text)) |hk| a.bindings.append(gpa, .{ .hotkey = hk, .action = g.action }) catch {};
        }
        for (a.workspace().sounds.items, 0..) |s, i| {
            if (hotkeys.parse(s.hotkey)) |hk| a.bindings.append(gpa, .{ .hotkey = hk, .action = Action.sound_base + @as(u32, @intCast(i)) }) catch {};
        }
        a.space_bound = false;
        const space = hotkeys.parse("Space");
        for (a.bindings.items) |b| {
            if (space != null and b.hotkey.eql(space.?)) a.space_bound = true;
        }
        hotkeys.setBindings(a.bindings.items);
    }

    fn runAction(a: *App, action: u32) void {
        switch (action) {
            Action.stop => a.stopAll(),
            Action.pause => a.togglePause(),
            Action.next => a.queueNext(),
            Action.random => a.playRandom(),
            Action.mute_voice => a.toggleVoiceMute(),
            else => if (action >= Action.sound_base) a.playSound(action - Action.sound_base),
        }
    }

    fn updateHotkeys(a: *App) void {
        const focused = c.IsWindowFocused();
        hotkeys.setSuspended(focused or !a.cfg.global_hotkeys);

        if (a.bindings_dirty) {
            a.bindings_dirty = false;
            a.rebuildBindings();
        }

        while (hotkeys.poll()) |action| a.runAction(action);

        // In-window keys (also covers global hotkeys while our window is focused)
        if (!focused or ui.keyboardCaptured() or a.capture != .none) return;
        for (a.bindings.items) |b| {
            if (hotkeys.pressedLocal(b.hotkey)) a.runAction(b.action);
        }
        const no_overlay = a.dialog == .none and a.menu == null and !a.onboarding_open;
        if (no_overlay and c.IsKeyPressed(c.KEY_ESCAPE)) a.stopAll();
        if (no_overlay and !a.space_bound and c.IsKeyPressed(c.KEY_SPACE)) a.togglePause();
        const ctrl = c.IsKeyDown(c.KEY_LEFT_CONTROL) or c.IsKeyDown(c.KEY_RIGHT_CONTROL);
        if (ctrl) {
            const pages = [_]Page{ .soundboard, .explore, .online, .downloads, .stats, .settings };
            for (pages, 0..) |p, i| {
                if (c.IsKeyPressed(c.KEY_ONE + @as(c_int, @intCast(i)))) a.goto(p);
            }
            if (c.IsKeyPressed(c.KEY_F) and a.page == .soundboard) a.focus_search = true;
            if (c.IsKeyPressed(c.KEY_O) and a.page == .soundboard) a.openImportDialog();
            return;
        }
        if (c.IsKeyPressed(c.KEY_F11)) a.setStage(!a.stage);
        if (c.IsKeyPressed(c.KEY_F1)) {
            a.onboarding_open = true;
            a.onboarding_step = 0;
        }
        if (a.cfg.number_keys_play and (a.page == .soundboard or a.stage) and no_overlay) {
            const keys = [_]c_int{ c.KEY_ONE, c.KEY_TWO, c.KEY_THREE, c.KEY_FOUR, c.KEY_FIVE, c.KEY_SIX, c.KEY_SEVEN, c.KEY_EIGHT, c.KEY_NINE, c.KEY_ZERO };
            for (keys, 0..) |k, i| {
                if (c.IsKeyPressed(k) and i < a.view.items.len) a.playSound(a.view.items[i]);
            }
        }
    }

    pub fn goto(a: *App, p: Page) void {
        if (p != .soundboard) a.setStage(false);
        if (a.page == p) return;
        a.page = p;
        a.page_changed_at = ui.time;
        a.menu = null;
        if (p == .explore and !a.explore.loaded) a.exploreQuery(.trending, "", null);
        if (p == .settings) a.cache_size = null;
    }

    // ── Persistence ─────────────────────────────────────────────────────────

    pub fn markConfig(a: *App) void {
        a.cfg_dirty_at = ui.time;
    }

    pub fn markWorkspace(a: *App) void {
        a.ws_dirty_at = ui.time;
    }

    fn updateSaves(a: *App) void {
        if (a.cfg_dirty_at) |at| {
            if (ui.time - at > 0.6) {
                config.save(&a.cfg);
                a.cfg_dirty_at = null;
            }
        }
        if (a.ws_dirty_at) |at| {
            if (ui.time - at > 1.5) {
                a.lib.save(a.ws) catch {};
                a.ws_dirty_at = null;
                a.play_time_unsaved = false;
            }
        }
    }

    pub fn flushSaves(a: *App) void {
        if (a.cfg_dirty_at != null) config.save(&a.cfg);
        if ((a.ws_dirty_at != null or a.play_time_unsaved) and a.ws < a.lib.workspaces.items.len) a.lib.save(a.ws) catch {};
        a.cfg_dirty_at = null;
        a.ws_dirty_at = null;
        a.play_time_unsaved = false;
        stats.save();
    }

    // ── Text helpers ────────────────────────────────────────────────────────

    var frame_buf: [32 * 1024]u8 = undefined;
    var frame_used: usize = 0;

    pub fn beginFrame(_: *App) void {
        frame_used = 0;
    }

    /// Formats a translated template ("{} sounds") into per-frame memory
    pub fn tf(_: *App, template: []const u8, args: anytype) []const u8 {
        const out = i18n.format(frame_buf[frame_used..], template, args);
        frame_used += out.len;
        return out;
    }

    /// Same as `tf` but null-terminated, for C APIs
    pub fn tfz(a: *App, template: []const u8, args: anytype) [:0]const u8 {
        const s = a.tf(template, args);
        if (frame_used < frame_buf.len) {
            frame_buf[frame_used] = 0;
            frame_used += 1;
        }
        return frame_buf[frame_used - 1 - s.len .. frame_used - 1 :0];
    }
};

/// "1:05" / "12:30" / "1:02:03"
pub fn formatDuration(buf: []u8, seconds: f32) []const u8 {
    const total: u32 = @intFromFloat(@max(0, @round(seconds)));
    const h = total / 3600;
    const m = (total / 60) % 60;
    const s = total % 60;
    if (h > 0) return std.fmt.bufPrint(buf, "{d}:{d:0>2}:{d:0>2}", .{ h, m, s }) catch "";
    return std.fmt.bufPrint(buf, "{d}:{d:0>2}", .{ m, s }) catch "";
}

/// Accepts "12", "12.5", "1:05" or "1:02:03"
pub fn parseSeconds(s_in: []const u8) ?f32 {
    const s = std.mem.trim(u8, s_in, " ");
    if (s.len == 0) return null;
    var total: f32 = 0;
    var it = std.mem.splitScalar(u8, s, ':');
    while (it.next()) |part| {
        const v = std.fmt.parseFloat(f32, std.mem.trim(u8, part, " ")) catch return null;
        total = total * 60 + v;
    }
    return if (total >= 0) total else null;
}

/// Drops "(Official Video)"-style noise from media titles
pub fn cleanTitle(title: []const u8) []const u8 {
    var t = title;
    for ([_][]const u8{ " (Official", " [Official", " | ", " (Lyrics", " (Audio" }) |marker| {
        if (std.ascii.findIgnoreCase(t, marker)) |pos| {
            if (pos > 3) t = t[0..pos];
        }
    }
    return std.mem.trim(u8, t[0..@min(t.len, 80)], " -");
}

pub fn formatBytes(buf: []u8, bytes: u64) []const u8 {
    const b: f64 = @floatFromInt(bytes);
    if (b < 1024 * 1024) return std.fmt.bufPrint(buf, "{d:.0} KB", .{b / 1024}) catch "";
    if (b < 1024 * 1024 * 1024) return std.fmt.bufPrint(buf, "{d:.1} MB", .{b / (1024 * 1024)}) catch "";
    return std.fmt.bufPrint(buf, "{d:.2} GB", .{b / (1024 * 1024 * 1024)}) catch "";
}
