const builtin = @import("builtin");
const std = @import("std");

/// Returns true if the contents of the slices `a` and `b` are the same.
pub fn memory_compare(a: []const u8, b: []const u8) callconv(.Inline) bool {
    if (a.len != b.len) return false;
    for (a[0..]) |value, i| {
        if (value != b[i]) return false;
    }
    return true;
}

pub const Key = struct {
    pub const Modifiers = struct {
        right_shift_is_pressed: bool = false,
        left_shift_is_pressed: bool = false,
        alt_is_pressed: bool = false,
        control_is_pressed: bool = false,

        pub fn shifted(self: *const Modifiers) bool {
            return self.right_shift_is_pressed or self.left_shift_is_pressed;
        }
    };

    pub fn shifted_char(self: *const Key) ?u8 {
        if (self.unshifted_char) |c| {
            return if (!self.modifiers.shifted() and c >= 'A' and c <= 'Z')
                c + 'a' - 'A' else c;
        }
        return null;
    }

    unshifted_char: ?u8,
    modifiers: Modifiers,
};
