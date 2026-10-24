//! Unit tests for the parts that don't need a window or audio device.
//! Run with `zig build test`.

test {
    _ = @import("market.zig");
    _ = @import("net.zig");
    _ = @import("tools.zig");
    _ = @import("sys.zig");
    _ = @import("library.zig");
    _ = @import("i18n.zig");
    _ = @import("ipc.zig");
    _ = @import("vmic.zig");
}
