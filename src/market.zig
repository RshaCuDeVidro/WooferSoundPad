//! Sound "marketplaces": public sound-button sites.
//!
//! - MyInstants: server-rendered HTML, parsed with plain substring anchors.
//! - SoundButtonsWorld: the JSON API its Angular front-end uses.

const std = @import("std");
const sys = @import("sys.zig");
const net = @import("net.zig");
const Source = @import("config.zig").ExploreSource;

const gpa = sys.gpa;

pub const Item = struct {
    name: []u8,
    audio_url: []u8,
    page_url: []u8,
    color: u32,

    pub fn deinit(i: Item) void {
        gpa.free(i.name);
        gpa.free(i.audio_url);
        gpa.free(i.page_url);
    }
};

pub const Query = union(enum) {
    trending,
    search: []const u8,
    category: []const u8,
};

pub const Page = struct {
    items: std.ArrayList(Item) = .empty,
    has_more: bool = false,

    pub fn deinit(p: *Page) void {
        for (p.items.items) |i| i.deinit();
        p.items.deinit(gpa);
    }
};

pub const myinstants_categories = [_][]const u8{
    "memes",         "reactions", "games",         "movies",          "music",
    "tiktok trends", "viral",     "sound effects", "anime & manga",   "television",
    "pranks",        "sports",    "politics",      "whatsapp audios",
};

const mi_base = "https://www.myinstants.com";
const sbw_base = "https://soundbuttonsworld.com";
pub const sbw_page_size = 40;

pub fn fetch(source: Source, query: Query, page: u32) !Page {
    var url: std.ArrayList(u8) = .empty;
    defer url.deinit(gpa);
    switch (source) {
        .myinstants => switch (query) {
            .trending => try url.print(gpa, mi_base ++ "/en/index/us/?page={d}", .{page}),
            .search => |q| {
                try url.appendSlice(gpa, mi_base ++ "/en/search/?name=");
                try net.encodeQuery(&url, q);
                try url.print(gpa, "&page={d}", .{page});
            },
            .category => |cat| {
                try url.appendSlice(gpa, mi_base ++ "/en/categories/");
                try net.encodeQuery(&url, cat);
                try url.print(gpa, "/us/?page={d}", .{page});
            },
        },
        .soundbuttonsworld => switch (query) {
            .trending => try url.print(gpa, sbw_base ++ "/api/memes/trends?page={d}&pageSize={d}", .{ page, sbw_page_size }),
            .search => |q| {
                try url.print(gpa, sbw_base ++ "/api/memes/search?page={d}&pageSize={d}&q=", .{ page, sbw_page_size });
                try net.encodeQuery(&url, q);
            },
            .category => |cat| {
                try url.print(gpa, sbw_base ++ "/api/memes/getall?page={d}&pageSize={d}&category=", .{ page, sbw_page_size });
                var lower_buf: [128]u8 = undefined;
                try net.encodeQuery(&url, std.ascii.lowerString(&lower_buf, cat[0..@min(cat.len, lower_buf.len)]));
            },
        },
    }

    const res = try net.get(url.items, 8 * 1024 * 1024);
    defer res.deinit();
    var out: Page = .{};
    errdefer out.deinit();
    switch (source) {
        .myinstants => {
            // MyInstants answers 404 for "no results" and for pages past the end
            if (res.status == 404) return out;
            if (res.status != 200) return error.BadStatus;
            out.has_more = try parseMyInstants(res.body, &out.items);
        },
        .soundbuttonsworld => {
            if (res.status != 200) return error.BadStatus;
            out.has_more = try parseSoundButtons(res.body, page, &out.items);
        },
    }
    return out;
}

/// SoundButtonsWorld category names (fetched from its API)
pub fn fetchSbwCategories() !std.ArrayList([]u8) {
    const res = try net.get(sbw_base ++ "/api/categories/getall", 2 * 1024 * 1024);
    defer res.deinit();
    if (res.status != 200) return error.BadStatus;
    const Cat = struct { name: []const u8 = "", url: []const u8 = "" };
    const parsed = try std.json.parseFromSlice([]const Cat, gpa, res.body, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    var out: std.ArrayList([]u8) = .empty;
    for (parsed.value) |cat| {
        if (cat.name.len == 0 or std.mem.eql(u8, cat.url, "/random-roll")) continue;
        try out.append(gpa, try gpa.dupe(u8, std.mem.trim(u8, cat.name, " ")));
    }
    return out;
}

// ── MyInstants ──────────────────────────────────────────────────────────────

/// Appends every instant on the page. Returns whether a next page exists.
pub fn parseMyInstants(html: []const u8, out: *std.ArrayList(Item)) !bool {
    const marker = "<div class=\"instant\">";
    var pos = std.mem.indexOf(u8, html, marker) orelse return false;
    while (true) {
        const next = std.mem.indexOfPos(u8, html, pos + marker.len, marker);
        const block = html[pos .. next orelse html.len];

        const mp3 = between(block, "onclick=\"play('", "'") orelse {
            pos = next orelse break;
            continue;
        };
        const raw_name = between(block, "class=\"instant-link link-secondary\">", "</a>") orelse
            between(block, "title=\"Play ", " sound\"") orelse "Sound";
        const href = between(block, "<a href=\"", "\"") orelse "";
        const color_hex = between(block, "background-color:", ";") orelse "";

        const name = try decodeEntities(std.mem.trim(u8, raw_name, " \n\t"));
        errdefer gpa.free(name);
        const audio_url = if (std.mem.startsWith(u8, mp3, "http")) try gpa.dupe(u8, mp3) else try std.mem.concat(gpa, u8, &.{ mi_base, mp3 });
        errdefer gpa.free(audio_url);
        const page_url = if (href.len > 0 and href[0] == '/') try std.mem.concat(gpa, u8, &.{ mi_base, href }) else try gpa.dupe(u8, href);
        try out.append(gpa, .{
            .name = name,
            .audio_url = audio_url,
            .page_url = page_url,
            .color = parseHexColor(std.mem.trim(u8, color_hex, " ")) orelse 0xEF4444,
        });
        pos = next orelse break;
    }
    return std.mem.indexOf(u8, html, "rel=\"next\"") != null;
}

fn between(s: []const u8, start: []const u8, end: []const u8) ?[]const u8 {
    const a = std.mem.indexOf(u8, s, start) orelse return null;
    const from = a + start.len;
    const b = std.mem.indexOfPos(u8, s, from, end) orelse return null;
    return s[from..b];
}

fn parseHexColor(s: []const u8) ?u32 {
    if (s.len != 7 or s[0] != '#') return null;
    return std.fmt.parseInt(u32, s[1..], 16) catch null;
}

/// Decodes the HTML entities Django emits (&amp; &#x27; &#39; …)
pub fn decodeEntities(s: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == '&') {
            if (std.mem.indexOfScalarPos(u8, s, i, ';')) |semi| {
                if (semi - i <= 10) {
                    const ent = s[i + 1 .. semi];
                    const named: ?[]const u8 = if (std.mem.eql(u8, ent, "amp")) "&" else if (std.mem.eql(u8, ent, "lt")) "<" else if (std.mem.eql(u8, ent, "gt")) ">" else if (std.mem.eql(u8, ent, "quot")) "\"" else if (std.mem.eql(u8, ent, "apos")) "'" else if (std.mem.eql(u8, ent, "nbsp")) " " else null;
                    if (named) |n| {
                        try out.appendSlice(gpa, n);
                        i = semi + 1;
                        continue;
                    }
                    if (ent.len > 1 and ent[0] == '#') {
                        const cp = if (ent[1] == 'x' or ent[1] == 'X')
                            std.fmt.parseInt(u21, ent[2..], 16) catch null
                        else
                            std.fmt.parseInt(u21, ent[1..], 10) catch null;
                        if (cp) |code| {
                            var tmp: [4]u8 = undefined;
                            if (std.unicode.utf8Encode(code, &tmp)) |n| {
                                try out.appendSlice(gpa, tmp[0..n]);
                                i = semi + 1;
                                continue;
                            } else |_| {}
                        }
                    }
                }
            }
        }
        try out.append(gpa, s[i]);
        i += 1;
    }
    return out.toOwnedSlice(gpa);
}

// ── SoundButtonsWorld ───────────────────────────────────────────────────────

const SbwItem = struct {
    name: []const u8 = "",
    color: []const u8 = "",
    fileName: []const u8 = "",
    url: []const u8 = "",
};

const SbwPage = struct {
    total: u64 = 0,
    data: []const SbwItem = &.{},
    searchFound: ?bool = null,
};

pub fn parseSoundButtons(json: []const u8, page: u32, out: *std.ArrayList(Item)) !bool {
    const parsed = try std.json.parseFromSlice(SbwPage, gpa, json, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    // No match: the API returns 20 random sounds with "searchFound": false
    if (parsed.value.searchFound == false) return false;
    for (parsed.value.data) |it| {
        if (it.fileName.len == 0) continue;
        const name = try gpa.dupe(u8, std.mem.trim(u8, it.name, " "));
        errdefer gpa.free(name);
        const audio_url = try std.mem.concat(gpa, u8, &.{ sbw_base, "/uploads/", it.fileName });
        errdefer gpa.free(audio_url);
        const page_url = try std.mem.concat(gpa, u8, &.{ sbw_base, "/sound-button/", it.url });
        try out.append(gpa, .{ .name = name, .audio_url = audio_url, .page_url = page_url, .color = sbwColor(it.color) });
    }
    return @as(u64, page) * sbw_page_size < parsed.value.total;
}

fn sbwColor(name: []const u8) u32 {
    const table = .{
        .{ "red", 0xEF4444 },   .{ "blue", 0x3B82F6 },   .{ "purple", 0xA855F7 },
        .{ "black", 0x475569 }, .{ "yellow", 0xEAB308 }, .{ "green", 0x22C55E },
        .{ "gray", 0x9CA3AF },  .{ "grey", 0x9CA3AF },   .{ "orange", 0xF97316 },
        .{ "pink", 0xEC4899 },  .{ "white", 0xE2E8F0 },
    };
    inline for (table) |entry| {
        if (std.ascii.eqlIgnoreCase(name, entry[0])) return entry[1];
    }
    return 0x6EC1FF;
}

// ── Tests ───────────────────────────────────────────────────────────────────

test "parse myinstants markup" {
    const html =
        \\<div class="instant">
        \\<div class="circle small-button-background" style="background-color:#FF0000;"></div>
        \\<button class="small-button" onclick="play('/media/sounds/faaah.mp3', 'loader-502601', 'faaah-63455')" title="Play FAAAH sound" type="button"></button>
        \\<a href="/en/instant/faaah-63455/" class="instant-link link-secondary">I&#x27;ve got bark&amp;fart</a>
        \\</div>
        \\<div class="instant">
        \\<button class="small-button" onclick="play('/media/sounds/b.mp3', 'loader-1', 'b-1')" title="Play B sound" type="button"></button>
        \\</div>
        \\<a class="page-link" href="?page=2&name=meme" rel="next">Next page</a>
    ;
    var items: std.ArrayList(Item) = .empty;
    defer {
        for (items.items) |i| i.deinit();
        items.deinit(gpa);
    }
    const more = try parseMyInstants(html, &items);
    try std.testing.expect(more);
    try std.testing.expectEqual(@as(usize, 2), items.items.len);
    try std.testing.expectEqualStrings("I've got bark&fart", items.items[0].name);
    try std.testing.expectEqualStrings("https://www.myinstants.com/media/sounds/faaah.mp3", items.items[0].audio_url);
    try std.testing.expectEqual(@as(u32, 0xFF0000), items.items[0].color);
    try std.testing.expectEqualStrings("B", items.items[1].name);
}

test "parse soundbuttonsworld json" {
    const json =
        \\{"total":81,"data":[{"id":338,"name":"Wet Fart Meme ","color":"black","fileName":"f5.mp3","url":"wet-fart-meme-1"}]}
    ;
    var items: std.ArrayList(Item) = .empty;
    defer {
        for (items.items) |i| i.deinit();
        items.deinit(gpa);
    }
    try std.testing.expect(try parseSoundButtons(json, 1, &items));
    try std.testing.expectEqualStrings("Wet Fart Meme", items.items[0].name);
    try std.testing.expectEqualStrings("https://soundbuttonsworld.com/uploads/f5.mp3", items.items[0].audio_url);

    items.clearRetainingCapacity();
    const none =
        \\{"total":20,"searchFound":false,"data":[{"name":"x","fileName":"x.mp3"}]}
    ;
    try std.testing.expect(!try parseSoundButtons(none, 1, &items));
    try std.testing.expectEqual(@as(usize, 0), items.items.len);
}

test "decode entities" {
    const s = try decodeEntities("a &amp; b &#39;c&#x27; &lt;3 &#233;");
    defer gpa.free(s);
    try std.testing.expectEqualStrings("a & b 'c' <3 é", s);
}
