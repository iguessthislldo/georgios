// I'm not sure if this is the best way to do this, but this runs all tests
// from these packages.
test "dummy" {
    const util = @import("util.zig");
    const io = @import("io.zig");
    const fprint = @import("fprint.zig");
    const buddy_allocator = @import("buddy_allocator.zig");
    const unicode = @import("unicode.zig");
    const list = @import("list.zig");
    const map = @import("map.zig");
    const mapped_list = @import("mapped_list.zig");
    const log = @import("log.zig");
    const filesystem = @import("filesystem.zig");
}
