pub const Key = @import("keys.zig").Key;

pub const Kind = enum {
    Pressed, // Key is depressed. Should be followed by a release.
    Released, // Key was released.
    Hit, // Key doesn't support seperate pressed and released states.
};

pub const Modifiers = struct {
    right_shift_is_pressed: bool = false,
    left_shift_is_pressed: bool = false,
    right_alt_is_pressed: bool = false,
    left_alt_is_pressed: bool = false,
    right_control_is_pressed: bool = false,
    left_control_is_pressed: bool = false,

    pub fn shift_is_pressed(self: *const Modifiers) bool {
        return self.right_shift_is_pressed or self.left_shift_is_pressed;
    }

    pub fn alt_is_pressed(self: *const Modifiers) bool {
        return self.right_alt_is_pressed or self.left_alt_is_pressed;
    }

    pub fn control_is_pressed(self: *const Modifiers) bool {
        return self.right_control_is_pressed or self.left_control_is_pressed;
    }

    pub fn update(self: *Modifiers, event: *const Event) void {
        switch (event.unshifted_key) {
            .Key_LeftShift => self.left_shift_is_pressed = event.kind == .Pressed,
            .Key_RightShift => self.right_shift_is_pressed = event.kind == .Pressed,
            .Key_LeftAlt => self.left_alt_is_pressed = event.kind == .Pressed,
            .Key_RightAlt => self.right_alt_is_pressed = event.kind == .Pressed,
            .Key_LeftControl => self.left_control_is_pressed = event.kind == .Pressed,
            .Key_RightControl => self.right_control_is_pressed = event.kind == .Pressed,
            else => {},
        }
    }
};

pub const Event = struct {
    unshifted_key: Key,
    kind: Kind,
    modifiers: Modifiers,
    key: Key,
    char: ?u8,

    pub fn new(
            unshifted_key: Key, shifted_key: ?Key,
            kind: Kind, modifiers: *const Modifiers) Event {
        return Event {
            .unshifted_key = unshifted_key,
            .kind = kind,
            .modifiers = modifiers.*,
            .key = if (shifted_key != null and modifiers.shift_is_pressed())
                shifted_key.? else unshifted_key,
            .char = null,
        };
    }
};
