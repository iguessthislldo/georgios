const georgios = @import("georgios");
comptime {_ = georgios;}
const system_calls = georgios.system_calls;

const Game = struct {
    const Dir = enum {
        Up,
        Down,
        Right,
        Left,
    };

    const max_x = 78;
    const default_x = max_x / 2;
    const max_y = 24;
    const default_y = max_y / 2;

    running: bool = true,
    x: u32 = undefined,
    y: u32 = undefined,
    dir: Dir = .Right,

    fn get_input(self: *Game) void {
        while (system_calls.get_key(.NonBlocking)) |key_event| {
            if (key_event.kind == .Pressed) {
                switch (key_event.unshifted_key) {
                    .Key_CursorUp => if (self.dir != .Down) {
                        self.dir = .Up;
                    },
                    .Key_CursorDown => if (self.dir != .Up) {
                        self.dir = .Down;
                    },
                    .Key_CursorRight => if (self.dir != .Left) {
                        self.dir = .Right;
                    },
                    .Key_CursorLeft => if (self.dir != .Right) {
                        self.dir = .Left;
                    },
                    .Key_Escape => {
                        system_calls.print_string("\x1bc");
                        system_calls.exit(0);
                    },
                    else => {},
                }
            }
        }
    }

    fn draw(self: *const Game, alive: bool) void {
        var buffer: [128]u8 = undefined;
        var ts = georgios.utils.ToString{.buffer = buffer[0..]};
        ts.string("\x1b[") catch unreachable;
        ts.uint(self.y) catch unreachable;
        ts.char(';') catch unreachable;
        ts.uint(self.x) catch unreachable;
        ts.char('H') catch unreachable;
        ts.string(if (alive) "♦" else "‼") catch unreachable;
        system_calls.print_string(ts.get());
    }

    pub fn reset(self: *Game) void {
        system_calls.print_string("\x1bc\x1b[25l");
        self.x = default_x;
        self.y = default_y;
        self.draw(true);
    }

    pub fn tick(self: *Game) void {
        self.get_input();
        if ((self.dir == .Up and self.y == 0) or (self.dir == .Down and self.y == max_y) or
                (self.dir == .Right and self.x == max_x) or (self.dir == .Left and self.x == 0)) {
            self.draw(false); // Dead
            system_calls.sleep_milliseconds(500);
            self.reset();
            return;
        }
        switch (self.dir) {
            .Up => self.y -= 1,
            .Down => self.y += 1,
            .Right => self.x += 1,
            .Left => self.x -= 1,
        }
        self.draw(true);
        var delay: usize = 100;
        if (self.dir == .Down or self.dir == .Up) {
            delay *= 2;
        }
        system_calls.sleep_milliseconds(delay);
    }
};

pub fn main() void {
    var game = Game{};
    game.reset();
    while (game.running) {
        game.tick();
    }
}
