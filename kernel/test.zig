// I'm not sure if this is the best way to do this, but this runs all tests
// from these packages.
test "dummy" {
    const util = @import("util.zig");
    const io = @import("io.zig");
}
