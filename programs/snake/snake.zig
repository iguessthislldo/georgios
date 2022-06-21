// TODO: Fix bug where the player can kill themselves with 2 segments when
// trashing around wildly.

const builtin = @import("builtin");

const georgios = @import("georgios");
comptime {_ = georgios;}
const system_calls = georgios.system_calls;

pub const panic = georgios.panic;

const Game = struct {
    const Rng = georgios.utils.Rand(u32);

    const Dir = enum {
        Up,
        Down,
        Right,
        Left,
    };

    const Point = struct {
        x: u32,
        y: u32,

        pub fn eql(self: *const Point, other: Point) bool {
            return self.x == other.x and self.y == other.y;
        }
    };

    max: Point = undefined,
    running: bool = true,
    head: Point = undefined,
    // NOTE: After 128, the snake will stop growing, but also will leave behind
    // a segment for each food it gets over 128.
    body: georgios.utils.CircularBuffer(Point, 128, .DiscardOldest) = .{},
    score: usize = undefined,
    dir: Dir = .Right,
    rng: Rng = undefined,
    food: Point = undefined,

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

    fn in_body(self: *const Game, point: Point) bool {
        var i: usize = 0;
        while (self.body.get(i)) |p| {
            if (p.eql(point)) return true;
            i += 1;
        }
        return false;
    }

    fn draw(s: []const u8, p: Point) void {
        var buffer: [128]u8 = undefined;
        var ts = georgios.utils.ToString{.buffer = buffer[0..]};
        ts.string("\x1b[") catch unreachable;
        ts.uint(p.y) catch unreachable;
        ts.char(';') catch unreachable;
        ts.uint(p.x) catch unreachable;
        ts.char('H') catch unreachable;
        ts.string(s) catch unreachable;
        system_calls.print_string(ts.get());
    }

    fn draw_head(self: *const Game, alive: bool) void {
        draw(if (alive) "♦" else "‼", self.head);
    }

    fn update_head_and_body(self: *Game, new_pos: Point) void {
        const old_pos = self.head;
        self.head = new_pos;
        self.draw_head(true);
        if (self.head.eql(self.food)) {
            self.body.push(old_pos);
            self.score += 1;
            self.show_score();
            self.gen_food();
        } else {
            if (self.score > 0) {
                self.body.push(old_pos);
                draw(" ", self.body.pop().?);
            } else {
                draw(" ", old_pos);
            }
        }
    }

    fn random_point(self: *Game) Point {
        return .{
            .x = self.rng.get() % self.max.x,
            .y = self.rng.get() % self.max.y,
        };
    }

    fn gen_food(self: *Game) void {
        self.food = self.random_point();
        while (self.in_body(self.food)) {
            self.food = self.random_point();
        }
        draw("@", self.food);
    }

    fn show_score(self: *Game) void {
        var p: Point = .{.x = 0, .y = self.max.y + 1};
        while (p.x < self.max.x + 1) {
            draw("▓", p);
            p.x += 1;
        }
        p.x = 1;
        var buffer: [128]u8 = undefined;
        var ts = georgios.utils.ToString{.buffer = buffer[0..]};
        ts.string("SCORE: ") catch unreachable;
        ts.uint(self.score) catch unreachable;
        draw(ts.get(), p);
    }

    pub fn reset(self: *Game) void {
        self.max = .{
            .x = system_calls.console_width() - 2,
            .y = system_calls.console_height() - 2,
        };
        self.rng = .{.seed = system_calls.time()};
        system_calls.print_string("\x1bc\x1b[25l");
        self.head = .{.x = self.max.x / 2, .y = self.max.y / 2};
        self.draw_head(true);
        self.gen_food();
        self.score = 0;
        self.show_score();
        self.body.reset();
    }

    pub fn game_over(self: *Game) usize {
        self.draw_head(false); // Dead
        system_calls.sleep_milliseconds(500);
        self.reset();
        return 500;
    }

    pub fn tick(self: *Game) usize {
        self.get_input();
        if ((self.dir == .Up and self.head.y == 0) or
                (self.dir == .Down and self.head.y == self.max.y) or
                (self.dir == .Right and self.head.x == self.max.x) or
                (self.dir == .Left and self.head.x == 0)) {
            return self.game_over();
        }
        var new_pos = self.head;
        switch (self.dir) {
            .Up => new_pos.y -= 1,
            .Down => new_pos.y += 1,
            .Right => new_pos.x += 1,
            .Left => new_pos.x -= 1,
        }
        if (self.in_body(new_pos)) {
            return self.game_over();
        }
        self.update_head_and_body(new_pos);
        // Speed up a bit as time goes on
        var delay: usize = if (self.score < 32) 100 - 10 * self.score / 4 else 20;
        if (self.dir == .Down or self.dir == .Up) {
            delay *= 2;
        }
        return delay;
    }
};

pub fn main() void {
    var game = Game{};
    game.reset();
    while (game.running) {
        // TODO: Delta time to correct for speed?
        system_calls.sleep_milliseconds(game.tick());
    }
}
