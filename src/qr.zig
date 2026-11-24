//! QR Code encoder for links a phone should open: byte mode, error correction
//! level M, versions 1 to 10 (up to 213 bytes). The symbol is built in a fixed
//! 57×57 grid, so there's no allocator and the result can be kept by value.
//!
//! Follows ISO/IEC 18004: Reed–Solomon over GF(256), block interleaving, and
//! the lowest-penalty of the eight data masks.

const std = @import("std");

/// Side of a version 10 symbol, the largest we make
pub const max_size = 57;

pub const Qr = struct {
    size: u8,
    modules: [max_size][max_size]bool,

    /// True for a dark module; `x` is the column, `y` the row. Anything
    /// outside the symbol reads as light, which is what the quiet zone needs.
    pub fn get(q: *const Qr, x: usize, y: usize) bool {
        return x < q.size and y < q.size and q.modules[y][x];
    }
};

/// The smallest symbol that holds `text`
pub fn encode(text: []const u8) error{TooLong}!Qr {
    return build(text, null);
}

/// Level M block structure per version (ISO/IEC 18004 table 9). Group 2
/// blocks carry one more data codeword than group 1 blocks.
const Layout = struct {
    ec_len: u8,
    blocks1: u8,
    data1: u8,
    blocks2: u8 = 0,

    fn blocks(l: Layout) usize {
        return l.blocks1 + l.blocks2;
    }

    fn dataLen(l: Layout) usize {
        return l.blocks() * l.data1 + l.blocks2;
    }
};

const layouts = [_]Layout{
    .{ .ec_len = 10, .blocks1 = 1, .data1 = 16 },
    .{ .ec_len = 16, .blocks1 = 1, .data1 = 28 },
    .{ .ec_len = 26, .blocks1 = 1, .data1 = 44 },
    .{ .ec_len = 18, .blocks1 = 2, .data1 = 32 },
    .{ .ec_len = 24, .blocks1 = 2, .data1 = 43 },
    .{ .ec_len = 16, .blocks1 = 4, .data1 = 27 },
    .{ .ec_len = 18, .blocks1 = 4, .data1 = 31 },
    .{ .ec_len = 22, .blocks1 = 2, .data1 = 38, .blocks2 = 2 },
    .{ .ec_len = 22, .blocks1 = 3, .data1 = 36, .blocks2 = 2 },
    .{ .ec_len = 26, .blocks1 = 4, .data1 = 43, .blocks2 = 1 },
};

/// Alignment pattern centres, used as both row and column coordinates
const alignment = [_][]const u8{
    &.{},        &.{ 6, 18 },     &.{ 6, 22 },     &.{ 6, 26 },     &.{ 6, 30 },
    &.{ 6, 34 }, &.{ 6, 22, 38 }, &.{ 6, 24, 42 }, &.{ 6, 26, 46 }, &.{ 6, 28, 50 },
};

const max_data = 216;
const max_ec = 26;
const max_blocks = 5;
const max_codewords = 346;

fn pickVersion(len: usize) error{TooLong}!u8 {
    for (layouts, 1..) |l, ver| {
        // mode indicator plus the character count, which grows at version 10
        const header: usize = if (ver < 10) 4 + 8 else 4 + 16;
        if (header + 8 * len <= 8 * l.dataLen()) return @intCast(ver);
    }
    return error.TooLong;
}

fn build(text: []const u8, forced_mask: ?u3) error{TooLong}!Qr {
    const ver = try pickVersion(text.len);
    var g: Grid = .{
        .qr = .{ .size = 17 + 4 * ver, .modules = @splat(@splat(false)) },
        .reserved = @splat(@splat(false)),
    };
    g.drawFunctionPatterns(ver);
    var buf: [max_codewords]u8 = undefined;
    g.drawCodewords(codewords(text, ver, &buf));

    const mask = forced_mask orelse best: {
        var best: u3 = 0;
        var best_score: u32 = std.math.maxInt(u32);
        for (0..8) |m| {
            const mask: u3 = @intCast(m);
            g.applyMask(mask);
            g.drawFormat(mask);
            const score = penalty(&g.qr);
            if (score < best_score) {
                best = mask;
                best_score = score;
            }
            g.applyMask(mask); // masks are XOR, so this undoes it
        }
        break :best best;
    };
    g.applyMask(mask);
    g.drawFormat(mask);
    return g.qr;
}

/// Data codewords followed by EC codewords, both interleaved across blocks
fn codewords(text: []const u8, ver: u8, out: *[max_codewords]u8) []const u8 {
    const l = layouts[ver - 1];
    var data_buf: [max_data]u8 = undefined;
    const data = data_buf[0..l.dataLen()];
    encodeData(text, ver, data);

    var divisor_buf: [max_ec]u8 = undefined;
    const divisor = divisor_buf[0..l.ec_len];
    rsDivisor(divisor);

    var blocks: [max_blocks][]const u8 = undefined;
    var ecc: [max_blocks][max_ec]u8 = undefined;
    var start: usize = 0;
    for (0..l.blocks()) |b| {
        const len = l.data1 + @intFromBool(b >= l.blocks1);
        blocks[b] = data[start..][0..len];
        rsRemainder(blocks[b], divisor, ecc[b][0..l.ec_len]);
        start += len;
    }

    var n: usize = 0;
    for (0..l.data1 + 1) |i| {
        for (blocks[0..l.blocks()]) |block| {
            if (i >= block.len) continue;
            out[n] = block[i];
            n += 1;
        }
    }
    for (0..l.ec_len) |i| {
        for (ecc[0..l.blocks()]) |block| {
            out[n] = block[i];
            n += 1;
        }
    }
    return out[0..n];
}

/// Byte-mode segment, terminator and 0xEC/0x11 padding, filling `out`
fn encodeData(text: []const u8, ver: u8, out: []u8) void {
    @memset(out, 0);
    var w: BitWriter = .{ .buf = out };
    w.put(0b0100, 4);
    w.put(@intCast(text.len), if (ver < 10) 8 else 16);
    for (text) |byte| w.put(byte, 8);
    w.put(0, @intCast(@min(4, 8 * out.len - w.len)));
    var pad: u8 = 0xEC;
    for ((w.len + 7) / 8..out.len) |i| {
        out[i] = pad;
        pad ^= 0xEC ^ 0x11;
    }
}

const BitWriter = struct {
    buf: []u8,
    len: usize = 0,

    /// Appends the low `bits` of `value`, most significant first
    fn put(w: *BitWriter, value: u16, bits: u5) void {
        var i = bits;
        while (i > 0) {
            i -= 1;
            if ((value >> @intCast(i)) & 1 != 0) w.buf[w.len / 8] |= @as(u8, 0x80) >> @intCast(w.len % 8);
            w.len += 1;
        }
    }
};

/// Product in GF(256) modulo x⁸ + x⁴ + x³ + x² + 1
fn gfMul(x: u8, y: u8) u8 {
    var z: u16 = 0;
    for (0..8) |i| {
        z = (z << 1) ^ ((z >> 7) * 0x11D);
        if ((y >> @intCast(7 - i)) & 1 != 0) z ^= x;
    }
    return @intCast(z);
}

/// Generator polynomial (x − α⁰)(x − α¹)…(x − αⁿ⁻¹) for n = `out.len`,
/// highest degree first with its leading 1 left out
fn rsDivisor(out: []u8) void {
    @memset(out, 0);
    out[out.len - 1] = 1;
    var root: u8 = 1;
    for (0..out.len) |_| {
        for (0..out.len) |j| {
            out[j] = gfMul(out[j], root);
            if (j + 1 < out.len) out[j] ^= out[j + 1];
        }
        root = gfMul(root, 2);
    }
}

/// EC codewords: the remainder of `data`·xⁿ divided by the generator
fn rsRemainder(data: []const u8, divisor: []const u8, out: []u8) void {
    @memset(out, 0);
    for (data) |byte| {
        const factor = byte ^ out[0];
        for (0..out.len - 1) |i| out[i] = out[i + 1];
        out[out.len - 1] = 0;
        for (out, divisor) |*r, d| r.* ^= gfMul(d, factor);
    }
}

/// 15-bit format word for level M (whose indicator is 00) and `mask`
fn formatBits(mask: u3) u15 {
    const data: u15 = mask;
    var rem: u15 = data;
    for (0..10) |_| rem = (rem << 1) ^ ((rem >> 9) * 0x537);
    return (data << 10 | rem) ^ 0x5412;
}

/// 18-bit version word, only drawn from version 7 up
fn versionBits(ver: u8) u18 {
    var rem: u18 = ver;
    for (0..12) |_| rem = (rem << 1) ^ ((rem >> 11) * 0x1F25);
    return @as(u18, ver) << 12 | rem;
}

fn bit(value: u32, i: usize) bool {
    return (value >> @intCast(i)) & 1 != 0;
}

fn dist(a: usize, b: usize) usize {
    return if (a > b) a - b else b - a;
}

const Grid = struct {
    qr: Qr,
    /// Function pattern modules, which data and masks leave alone
    reserved: [max_size][max_size]bool,

    fn set(g: *Grid, x: usize, y: usize, dark: bool) void {
        g.qr.modules[y][x] = dark;
        g.reserved[y][x] = true;
    }

    fn drawFunctionPatterns(g: *Grid, ver: u8) void {
        const n = g.qr.size;
        for (0..n) |i| {
            g.set(6, i, i % 2 == 0);
            g.set(i, 6, i % 2 == 0);
        }
        g.drawFinder(3, 3);
        g.drawFinder(n - 4, 3);
        g.drawFinder(3, n - 4);

        const centres = alignment[ver - 1];
        for (centres, 0..) |cy, i| {
            for (centres, 0..) |cx, j| {
                // three of the corners are taken by finder patterns
                const last = centres.len - 1;
                if ((i == 0 and j == 0) or (i == 0 and j == last) or (i == last and j == 0)) continue;
                g.drawAlignment(cx, cy);
            }
        }

        g.drawFormat(0); // claims the area; the chosen mask is written later
        if (ver >= 7) g.drawVersion(ver);
    }

    /// 7×7 finder plus its light separator, clipped at the symbol edge
    fn drawFinder(g: *Grid, cx: usize, cy: usize) void {
        const n = g.qr.size;
        for (cy -| 4..@min(cy + 5, n)) |y| {
            for (cx -| 4..@min(cx + 5, n)) |x| {
                const ring = @max(dist(x, cx), dist(y, cy));
                g.set(x, y, ring != 2 and ring != 4);
            }
        }
    }

    fn drawAlignment(g: *Grid, cx: usize, cy: usize) void {
        for (cy - 2..cy + 3) |y| {
            for (cx - 2..cx + 3) |x| g.set(x, y, @max(dist(x, cx), dist(y, cy)) != 1);
        }
    }

    /// Two copies: around the top-left finder, and split between the other two
    fn drawFormat(g: *Grid, mask: u3) void {
        const bits = formatBits(mask);
        const n = g.qr.size;
        for (0..6) |i| g.set(8, i, bit(bits, i));
        g.set(8, 7, bit(bits, 6));
        g.set(8, 8, bit(bits, 7));
        g.set(7, 8, bit(bits, 8));
        for (9..15) |i| g.set(14 - i, 8, bit(bits, i));

        for (0..8) |i| g.set(n - 1 - i, 8, bit(bits, i));
        for (8..15) |i| g.set(8, n - 15 + i, bit(bits, i));
        g.set(8, n - 8, true); // the "dark module", always set
    }

    /// 6×3 blocks above the bottom-left finder and left of the top-right one
    fn drawVersion(g: *Grid, ver: u8) void {
        const bits = versionBits(ver);
        const n = g.qr.size;
        for (0..18) |i| {
            const a = n - 11 + i % 3;
            const b = i / 3;
            g.set(a, b, bit(bits, i));
            g.set(b, a, bit(bits, i));
        }
    }

    /// Zigzags two-column strips from the bottom-right corner, alternating up
    /// and down; leftover remainder modules stay light
    fn drawCodewords(g: *Grid, data: []const u8) void {
        const n = g.qr.size;
        var i: usize = 0;
        for (0..(n - 1) / 2) |strip| {
            var right = n - 1 - 2 * strip;
            if (right <= 6) right -= 1; // hop over the vertical timing pattern
            for (0..n) |vert| {
                const y = if (strip % 2 == 0) n - 1 - vert else vert;
                for ([2]usize{ right, right - 1 }) |x| {
                    if (g.reserved[y][x] or i >= 8 * data.len) continue;
                    g.qr.modules[y][x] = (data[i / 8] >> @intCast(7 - i % 8)) & 1 != 0;
                    i += 1;
                }
            }
        }
    }

    fn applyMask(g: *Grid, mask: u3) void {
        for (0..g.qr.size) |y| {
            for (0..g.qr.size) |x| {
                if (!g.reserved[y][x] and maskBit(mask, x, y)) g.qr.modules[y][x] = !g.qr.modules[y][x];
            }
        }
    }
};

fn maskBit(mask: u3, x: usize, y: usize) bool {
    return switch (mask) {
        0 => (x + y) % 2 == 0,
        1 => y % 2 == 0,
        2 => x % 3 == 0,
        3 => (x + y) % 3 == 0,
        4 => (x / 3 + y / 2) % 2 == 0,
        5 => x * y % 2 + x * y % 3 == 0,
        6 => (x * y % 2 + x * y % 3) % 2 == 0,
        7 => ((x + y) % 2 + x * y % 3) % 2 == 0,
    };
}

/// ISO/IEC 18004 penalty score; lower is easier for scanners
fn penalty(q: *const Qr) u32 {
    const n = q.size;
    var score: u32 = 0;
    var dark: u32 = 0;
    for (0..n) |i| {
        var row: [max_size]bool = undefined;
        var col: [max_size]bool = undefined;
        for (0..n) |j| {
            row[j] = q.modules[i][j];
            col[j] = q.modules[j][i];
            dark += @intFromBool(row[j]);
        }
        score += linePenalty(row[0..n]) + linePenalty(col[0..n]);
    }

    // 2×2 blocks of one colour
    for (0..n - 1) |y| {
        for (0..n - 1) |x| {
            const c = q.modules[y][x];
            if (c == q.modules[y][x + 1] and c == q.modules[y + 1][x] and c == q.modules[y + 1][x + 1]) score += 3;
        }
    }

    // 10 points per 5% that the dark share strays from half
    const total = @as(u32, n) * n;
    const off = if (2 * dark > total) 2 * dark - total else total - 2 * dark;
    return score + off * 10 / total * 10;
}

/// Runs of five or more, and finder look-alikes, in one row or column
fn linePenalty(line: []const bool) u32 {
    var score: u32 = 0;
    var run: u32 = 1;
    for (1..line.len) |i| {
        if (line[i] == line[i - 1]) {
            run += 1;
        } else {
            if (run >= 5) score += run - 2;
            run = 1;
        }
    }
    if (run >= 5) score += run - 2;

    // 1:1:3:1:1 with four light modules on either side; past the edge is light
    const finder = [7]bool{ true, false, true, true, true, false, true };
    for (0..line.len - 6) |i| {
        if (!std.mem.eql(bool, line[i..][0..7], &finder)) continue;
        if (allLight(line[i -| 4..i]) or allLight(line[i + 7 .. @min(i + 11, line.len)])) score += 40;
    }
    return score;
}

fn allLight(modules: []const bool) bool {
    for (modules) |m| if (m) return false;
    return true;
}

test "reed-solomon matches the ISO/IEC 18004 annex example" {
    // "01234567" as version 1-M (numeric mode)
    const data = [_]u8{ 0x10, 0x20, 0x0C, 0x56, 0x61, 0x80, 0xEC, 0x11, 0xEC, 0x11, 0xEC, 0x11, 0xEC, 0x11, 0xEC, 0x11 };
    var divisor: [10]u8 = undefined;
    rsDivisor(&divisor);
    var ecc: [10]u8 = undefined;
    rsRemainder(&data, &divisor, &ecc);
    try std.testing.expectEqualSlices(u8, &.{ 0xA5, 0x24, 0xD4, 0xC1, 0xED, 0x36, 0xC7, 0x87, 0x2C, 0x55 }, &ecc);
}

test "format and version words match the standard tables" {
    const format = [8]u15{
        0b101010000010010, 0b101000100100101, 0b101111001111100, 0b101101101001011,
        0b100010111111001, 0b100000011001110, 0b100111110010111, 0b100101010100000,
    };
    for (format, 0..) |want, mask| try std.testing.expectEqual(want, formatBits(@intCast(mask)));
    try std.testing.expectEqual(@as(u18, 0x07C94), versionBits(7));
    try std.testing.expectEqual(@as(u18, 0x085BC), versionBits(8));
    try std.testing.expectEqual(@as(u18, 0x09A99), versionBits(9));
    try std.testing.expectEqual(@as(u18, 0x0A4D3), versionBits(10));
}

test "full symbol matches a reference encoder" {
    // `qrencode -8 -l M -m 0 -t ASCII WooferSound` (libqrencode also picks mask 3)
    const want = [21]*const [21]u8{
        "#######.#.....#######",
        "#.....#.#..##.#.....#",
        "#.###.#..##...#.###.#",
        "#.###.#.##....#.###.#",
        "#.###.#..#.#..#.###.#",
        "#.....#..#.##.#.....#",
        "#######.#.#.#.#######",
        "........#.###........",
        "#.##.###...##.#..#.##",
        ".#.###..#.########..#",
        "..##.#######.#.#..###",
        "#..#....#..#...#.#..#",
        "...##.##.#..####...#.",
        "........#.##.###..###",
        "#######.#.###..####..",
        "#.....#.##...#.######",
        "#.###.#...#.#....##..",
        "#.###.#.#.#...##.#.#.",
        "#.###.#.###.#.#......",
        "#.....#..###.###....#",
        "#######.##.#.####.#..",
    };
    const q = try encode("WooferSound");
    try std.testing.expectEqual(@as(u8, 21), q.size);
    for (want, 0..) |row, y| {
        for (row, 0..) |c, x| try std.testing.expectEqual(c == '#', q.get(x, y));
    }
}

test "smallest version that fits, at each level M byte capacity" {
    const capacity = [_]usize{ 14, 26, 42, 62, 84, 106, 122, 152, 180, 213 };
    const text: [213]u8 = @splat('x');
    for (capacity, 1..) |cap, ver| {
        try std.testing.expectEqual(17 + 4 * ver, (try encode(text[0..cap])).size);
        if (ver < 10) try std.testing.expectEqual(21 + 4 * ver, (try encode(text[0 .. cap + 1])).size);
    }
    try std.testing.expectEqual(@as(u8, 21), (try encode("")).size);
}

test "too long for version 10" {
    const text: [214]u8 = @splat('x');
    try std.testing.expectError(error.TooLong, encode(&text));
}
