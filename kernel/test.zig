test "kernel test root" {
    _ = @import("fprint.zig");
    _ = @import("buddy_allocator.zig");
    _ = @import("list.zig");
    _ = @import("map.zig");
    _ = @import("mapped_list.zig");
    _ = @import("log.zig");
    _ = @import("fs.zig");
    _ = @import("fs/RamDisk.zig");
    _ = @import("sync.zig");
}
