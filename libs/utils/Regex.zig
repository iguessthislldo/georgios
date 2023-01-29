// ===========================================================================
// A VM-based Regular Expression Engine
// ===========================================================================
//
// VM concept based on https://swtch.com/~rsc/regexp/regexp2.html
//
// Supports:
//   . ^ $ ?
//   Groups
//
// Reference:
//   https://en.wikipedia.org/wiki/Regular_expression

const std = @import("std");

const utils = @import("utils");

pub const Error = error {
    RegexIsInvalid,
    RegexRecursionLimit,
    OutOfMemory,
};

fn View(comptime Type: type) type {
    return struct {
        const Self = @This();

        items: []const Type = undefined,
        pos: usize = 0,

        fn init(self: *Self, items: []const Type) void {
            self.* = .{.items = items};
        }

        fn limit(self: *Self, by: ?usize) void {
            if (by) |limit_by| {
                self.items = self.items[0..self.pos + limit_by + 1];
            }
        }

        fn done(self: *const Self) bool {
            return self.pos >= self.items.len;
        }

        fn first(self: *const Self) bool {
            return self.items.len > 0 and self.pos == 0;
        }

        fn last(self: *const Self) bool {
            return self.items.len > 0 and self.pos == self.items.len - 1;
        }

        fn get(self: *const Self) ?Type {
            return if (self.done()) null else self.items[self.pos];
        }

        fn inc(self: *Self) void {
            if (!self.done()) self.pos += 1;
        }

        fn move(self: *Self, by: isize) void {
            const new_pos = @intCast(usize, @intCast(isize, self.pos) + by);
            if (new_pos > self.items.len) {
                @panic("Moved to invalid position");
            }
            self.pos = new_pos;
        }

        fn seen(self: *Self, from: usize) []const Type {
            return self.items[from..self.pos];
        }

        fn consume_exact(self: *Self, expected: []const u8) bool {
            const len = @minimum(self.items.len - self.pos, expected.len);
            if (std.mem.eql(u8, self.items[self.pos..self.pos + len], expected)) {
                self.pos += len;
                return true;
            }
            return false;
        }
    };
}

const StrView = View(u8);

const Inst = union (enum) {
    matched: enum {
        InputCanContinue,
        InputMustBeDone,
    },
    literal: u8,
    any,
    jump: isize,
    split: [2]isize,
    repeat: struct {
        len: u16,
        min: u32 = 0,
        max: u32 = std.math.maxInt(u32),
    },
};

pub const CompiledRegex = []const Inst;

const Vm = struct {
    insts: CompiledRegex,
    level_limit: ?u16 = null,

    const Context = struct {
        layer: u16 = 0,
        insts: View(Inst) = .{},
        match_at_end: bool = false,
        input: StrView = .{},

        fn init(self: *Context, insts: CompiledRegex, input: []const u8) void {
            self.insts.init(insts);
            self.input.init(input);
        }

        fn new_nested(self: *const Context, inst_offset: isize, match_after: ?usize) Context {
            var copy = self.*;
            copy.layer += 1;
            copy.insts.limit(match_after);
            copy.match_at_end = match_after != null;
            copy.jump(inst_offset);
            return copy;
        }

        fn inst(self: *const Context) ?Inst {
            return self.insts.get();
        }

        fn jump(self: *Context, by: isize) void {
            if (by == 0) {
                @panic("Trying to jump by 0");
            }
            self.insts.move(by);
        }

        fn char(self: *const Context) ?u8 {
            return self.input.get();
        }

        fn matched(self: *const Context, yes: bool) ?usize {
            return if (yes) self.input.pos else null;
        }

        fn status(self: *const Context) void {
            std.debug.print("L{} inst: {s}@{} char ",
                .{self.layer, @tagName(self.inst().?), self.insts.pos});
            if (self.char()) |c| {
                std.debug.print("'{c}' @ {}\n", .{c, self.input.pos});
            } else {
                std.debug.print("end @ {}\n", .{self.input.pos});
            }
        }
    };

    fn matches_i(self: *const Vm, ctx: *Context) Error!?usize
    {
        if (self.level_limit) |level_limit| {
            if (ctx.layer > level_limit) {
                return Error.RegexRecursionLimit;
            }
        }
        while (true) {
            const inst = ctx.inst() orelse if (ctx.match_at_end) return ctx.matched(true)
                else @panic("Missing matched instruction?");
            // ctx.status();
            switch (inst) {
                .matched => |cond|
                    return ctx.matched((cond == .InputCanContinue) or ctx.input.done()),
                .literal => |expected_char| {
                    if (ctx.char()) |char| {
                        if (char != expected_char) return ctx.matched(false);
                        ctx.insts.inc();
                        ctx.input.inc();
                    } else return ctx.matched(false);
                },
                .any => {
                    if (ctx.input.done()) return ctx.matched(false);
                    ctx.insts.inc();
                    ctx.input.inc();
                },
                .jump => |by| ctx.jump(by),
                .split => |branches| {
                    var nested = ctx.new_nested(branches[1], null);
                    if (try self.matches_i(&nested)) |input_pos| {
                        return input_pos;
                    }
                    ctx.jump(branches[0]);
                },
                .repeat => |loop| {
                    // std.debug.print("  L{} repeat: {} len {} -> {}\n", .{ctx.layer, loop.len, loop.min, loop.max});
                    var count: u32 = 0;
                    while (count < loop.max) {
                        // std.debug.print("    L{} repeat: #{} @ {}\n", .{ctx.layer, count, ctx.input.pos});
                        var nested = ctx.new_nested(1, loop.len);
                        if (try self.matches_i(&nested)) |input_pos| {
                            ctx.input.pos = input_pos;
                            count += 1;
                        } else break;
                    }
                    // std.debug.print("    L{} repeat done after {}\n", .{ctx.layer, count});
                    if (count < loop.min) return ctx.matched(false);
                    ctx.jump(loop.len + 1);
                },
            }
        }
    }

    fn matches(self: *const Vm, input: []const u8) Error!bool
    {
        var ctx = Context{};
        ctx.init(self.insts, input);
        return (try self.matches_i(&ctx)) != null;
    }

    fn expect_matches(self: *const Vm, expect_match: bool, input: []const u8) !void
    {
        try std.testing.expect(expect_match == (try self.matches(input)));
    }
};

test "Vm" {
    // s//
    {
        const insts = [_]Inst{
            .{.matched = .InputCanContinue},
        };
        const vm = Vm{.insts = insts[0..]};
        try vm.expect_matches(true, "");
        try vm.expect_matches(true, "a");
        try vm.expect_matches(true, "anything");
    }

    // s/^a/
    {
        const insts = [_]Inst{
            .{.literal = 'a'},
            .{.matched = .InputCanContinue},
        };
        const vm = Vm{.insts = insts[0..]};
        try vm.expect_matches(false, "");
        try vm.expect_matches(false, "b");
        try vm.expect_matches(true, "a");
        try vm.expect_matches(true, "abc");
    }

    // s/^abc/
    {
        const insts = [_]Inst{
            .{.literal = 'a'},
            .{.literal = 'b'},
            .{.literal = 'c'},
            .{.matched = .InputCanContinue},
        };
        const vm = Vm{.insts = insts[0..]};
        try vm.expect_matches(false, "");
        try vm.expect_matches(false, "a");
        try vm.expect_matches(false, "ab");
        try vm.expect_matches(true, "abc");
        try vm.expect_matches(true, "abcdef");
        try vm.expect_matches(false, "aabc");
    }

    // s/^abc$/
    {
        const insts = [_]Inst{
            .{.literal = 'a'},
            .{.literal = 'b'},
            .{.literal = 'c'},
            .{.matched = .InputMustBeDone},
        };
        const vm = Vm{.insts = insts[0..]};
        try vm.expect_matches(false, "");
        try vm.expect_matches(false, "a");
        try vm.expect_matches(false, "ab");
        try vm.expect_matches(true, "abc");
        try vm.expect_matches(false, "abcdef");
        try vm.expect_matches(false, "aabc");
    }

    // s/^a.c/
    {
        const insts = [_]Inst{
            .{.literal = 'a'},
            .any,
            .{.literal = 'c'},
            .{.matched = .InputCanContinue},
        };
        const vm = Vm{.insts = insts[0..]};
        try vm.expect_matches(false, "");
        try vm.expect_matches(false, "a");
        try vm.expect_matches(false, "ab");
        try vm.expect_matches(true, "abc");
        try vm.expect_matches(true, "a c");
        try vm.expect_matches(false, "aabc");
    }

    // s/^ab?c/
    {
        const insts = [_]Inst{
            .{.literal = 'a'},
            .{.split = .{1, 2}},
            .{.literal = 'b'},
            .{.literal = 'c'},
            .{.matched = .InputCanContinue},
        };
        const vm = Vm{.insts = insts[0..]};
        try vm.expect_matches(false, "ab");
        try vm.expect_matches(true, "ac");
        try vm.expect_matches(true, "abc");
    }

    // s/^a(bbb)?c/
    {
        const insts = [_]Inst{
            .{.literal = 'a'},
            .{.split = .{1, 4}},
            .{.literal = 'b'},
            .{.literal = 'b'},
            .{.literal = 'b'},
            .{.literal = 'c'},
            .{.matched = .InputCanContinue},
        };
        const vm = Vm{.insts = insts[0..]};
        try vm.expect_matches(false, "ab");
        try vm.expect_matches(true, "ac");
        try vm.expect_matches(false, "abc");
        try vm.expect_matches(false, "abbc");
        try vm.expect_matches(true, "abbbc");
    }

    // s/^ab|cd/
    {
        const insts = [_]Inst{
            .{.literal = 'a'},
            .{.split = .{1, 3}},
            .{.literal = 'b'},
            .{.jump = 2},
            .{.literal = 'c'},
            .{.literal = 'd'},
            .{.matched = .InputCanContinue},
        };
        const vm = Vm{.insts = insts[0..]};
        try vm.expect_matches(false, "ad");
        try vm.expect_matches(false, "ab");
        try vm.expect_matches(false, "ac");
        try vm.expect_matches(true, "abd");
        try vm.expect_matches(true, "acd");
        try vm.expect_matches(false, "abcd");
        try vm.expect_matches(true, "abdc");
        try vm.expect_matches(true, "acdb");
    }

    // s/^ab*c/
    {
        const insts = [_]Inst{
            .{.literal = 'a'},
            .{.repeat = .{.len = 1}},
            .{.literal = 'b'},
            .{.literal = 'c'},
            .{.matched = .InputCanContinue},
        };
        const vm = Vm{.insts = insts[0..]};
        try vm.expect_matches(false, "a");
        try vm.expect_matches(false, "ab");
        try vm.expect_matches(false, "abb");
        try vm.expect_matches(false, "abbb");
        try vm.expect_matches(false, "abbbb");
        try vm.expect_matches(true, "ac");
        try vm.expect_matches(true, "abc");
        try vm.expect_matches(true, "abbc");
        try vm.expect_matches(true, "abbbc");
        try vm.expect_matches(true, "abbbbc");
    }

    // s/^ab+c/
    {
        const insts = [_]Inst{
            .{.literal = 'a'},
            .{.repeat = .{.len = 1, .min = 1}},
            .{.literal = 'b'},
            .{.literal = 'c'},
            .{.matched = .InputCanContinue},
        };
        const vm = Vm{.insts = insts[0..]};
        try vm.expect_matches(false, "a");
        try vm.expect_matches(false, "ab");
        try vm.expect_matches(false, "abb");
        try vm.expect_matches(false, "abbbbbb");
        try vm.expect_matches(false, "ac");
        try vm.expect_matches(true, "abc");
        try vm.expect_matches(true, "abbc");
        try vm.expect_matches(true, "abbbbbbc");
    }

    // s/^ab{2,3}c/
    {
        const insts = [_]Inst{
            .{.literal = 'a'},
            .{.repeat = .{.len = 1, .min = 2, .max = 3}},
            .{.literal = 'b'},
            .{.literal = 'c'},
            .{.matched = .InputCanContinue},
        };
        const vm = Vm{.insts = insts[0..]};
        try vm.expect_matches(false, "a");
        try vm.expect_matches(false, "ab");
        try vm.expect_matches(false, "abb");
        try vm.expect_matches(false, "abbb");
        try vm.expect_matches(false, "abbbb");
        try vm.expect_matches(false, "ac");
        try vm.expect_matches(false, "abc");
        try vm.expect_matches(true, "abbc");
        try vm.expect_matches(true, "abbbc");
        try vm.expect_matches(false, "abbbbc");
    }
}

const Compiler = struct {
    const Insts = utils.List(Inst);

    input: StrView = .{},
    insts: Insts = undefined,
    group_level: usize = 0,

    fn init(self: *Compiler, alloc: std.mem.Allocator, input: []const u8) void {
        self.input.init(input);
        self.insts = Insts{.alloc = alloc};
    }

    fn m_int(self: *Compiler) Error!usize {
        const start = self.input.pos;
        while (self.input.get()) |char| {
            if (char >= '0' and char <= '9') {
                self.input.inc();
            } else break;
        }
        if (std.fmt.parseUnsigned(usize, self.input.seen(start), 10) catch null) |int| {
            return int;
        } else {
            self.input.pos = start;
            return Error.RegexIsInvalid;
        }
    }

    fn m_int_maybe(self: *Compiler) ?usize {
        return self.m_int() catch null;
    }

    fn m_exact_maybe(self: *Compiler, expected: []const u8) bool {
        return self.input.consume_exact(expected);
    }

    fn m_exact(self: *Compiler, expected: []const u8) Error!void {
        if (!self.m_exact_maybe(expected)) return Error.RegexIsInvalid;
    }

    fn m_group(self: *Compiler) Error!void {
        try self.m_exact("(");
        self.group_level += 1;
        // std.debug.print("entering m_group {}\n", .{self.group_level});
        defer self.group_level -= 1;
        try self.m_expr();
        try self.m_exact(")");
        // std.debug.print("leaving m_group {}\n", .{self.group_level});
    }

    fn m_expr(self: *Compiler) Error!void {
        // std.debug.print("m_expr\n", .{});
        var last = self.insts.tail;
        var last_index = self.insts.len;
        while (self.input.get()) |char| {
            // std.debug.print("{} {c}: ", .{self.insts.len, char});
            switch (char) {
                '.' => {
                    // std.debug.print("any\n", .{});
                    last = self.insts.tail;
                    last_index = self.insts.len;
                    try self.insts.push_back(.any);
                    self.input.inc();
                },
                '?' => {
                    const jump = @intCast(isize, self.insts.len - last_index + 1);
                    // std.debug.print("? {}\n", .{jump});
                    try self.insts.insert_after(last, .{.split = .{1, jump}});
                    self.input.inc();
                },
                '(' => {
                    last = self.insts.tail;
                    last_index = self.insts.len;
                    try self.m_group();
                },
                ')' => {
                    if (self.group_level == 0) return Error.RegexIsInvalid;
                    return;
                },
                '^' => {
                    return Error.RegexIsInvalid;
                },
                '$' => {
                    if (!self.input.last()) {
                        return Error.RegexIsInvalid;
                    }
                    return;
                },
                else => {
                    // std.debug.print("literal\n", .{});
                    last = self.insts.tail;
                    last_index = self.insts.len;
                    try self.insts.push_back(.{.literal = char});
                    self.input.inc();
                },
            }
        }
    }

    fn compile_regex(self: *Compiler) Error!CompiledRegex {
        defer self.insts.clear();
        // If no ^, then insert the equivalent of a non-greedy .* at the start
        if (!self.m_exact_maybe("^")) {
            try self.insts.push_back(.{.split = .{3, 1}});
            try self.insts.push_back(.any);
            try self.insts.push_back(.{.jump = -2});
        }
        try self.m_expr();
        if (self.group_level != 0) return Error.RegexIsInvalid;
        try self.insts.push_back(.{.matched =
            if (self.m_exact_maybe("$")) .InputMustBeDone else .InputCanContinue});
        return self.insts.to_slice();
    }
};

pub fn compile(alloc: std.mem.Allocator, regex: []const u8) Error!CompiledRegex {
    var c = Compiler{};
    c.init(alloc, regex);
    return c.compile_regex();
}

test "Compiler" {
    const Invalid = Error.RegexIsInvalid;
    const eq = std.testing.expectEqual;
    const eq_slices = std.testing.expectEqualSlices;
    const er = std.testing.expectError;

    var ta = utils.TestAlloc{};
    defer ta.deinit(.Panic);
    errdefer ta.deinit(.NoPanic);
    const alloc = ta.alloc();

    // Terminal Elements
    {
        var c = Compiler{};
        c.input.items = "abc xyz 123 456";

        // Try Incorrectly at start
        try eq(@as(usize, 0), c.input.pos);
        try er(Invalid, c.m_exact("xyz"));
        try eq(@as(usize, 0), c.input.pos);
        try eq(false, c.m_exact_maybe("1"));
        try eq(@as(usize, 0), c.input.pos);
        try er(Invalid, c.m_int());
        try eq(@as(usize, 0), c.input.pos);
        try eq(@as(?usize, null), c.m_int_maybe());

        // abc
        try eq(@as(usize, 0), c.input.pos);
        try c.m_exact("abc");

        try eq(@as(usize, 3), c.input.pos);
        try c.m_exact(" ");

        // xyz
        try eq(@as(usize, 4), c.input.pos);
        try eq(true, c.m_exact_maybe("xyz"));

        try eq(@as(usize, 7), c.input.pos);
        try c.m_exact(" ");

        // 123
        try eq(@as(usize, 8), c.input.pos);
        try eq(@as(usize, 123), try c.m_int());

        try eq(@as(usize, 11), c.input.pos);
        try c.m_exact(" ");

        try eq(@as(usize, 12), c.input.pos);
        try eq(@as(?usize, 456), c.m_int_maybe());

        try eq(@as(usize, c.input.items.len), c.input.pos);
    }

    // Expr with '.', '?', and simple groups
    {
        const compiled = try compile(alloc, "ab.d?(ef)?g");
        defer alloc.free(compiled);
        try eq_slices(Inst, &[_]Inst{
            .{.split = .{3, 1}},
            .any,
            .{.jump = -2},
            .{.literal = 'a'},
            .{.literal = 'b'},
            .any,
            .{.split = .{1, 2}},
            .{.literal = 'd'},
            .{.split = .{1, 3}},
            .{.literal = 'e'},
            .{.literal = 'f'},
            .{.literal = 'g'},
            .{.matched = .InputCanContinue},
        }, compiled);
        const vm = Vm{.insts = compiled};
        try eq(false, try vm.matches(""));
        try eq(false, try vm.matches("a"));
        try eq(false, try vm.matches("ab"));
        try eq(true, try vm.matches("abcg"));
        try eq(true, try vm.matches("abxg"));
        try eq(true, try vm.matches("abcdg"));
        try eq(true, try vm.matches("abxdg"));
        try eq(false, try vm.matches("abcdeg"));
        try eq(true, try vm.matches("abcdefg"));
        try eq(false, try vm.matches("abcdeffg"));
        // Test that not having ^ means the match doesn't need to be at the
        // start.
        try eq(true, try vm.matches("xabcdefg"));
        // Test taht not having $ means there can be anything after the match.
        try eq(true, try vm.matches("abcdefghij"));
        try eq(true, try vm.matches("abcdefghijklmnop"));
    }

    // Expr with '^', '$', and nested groups
    {
        const compiled = try compile(alloc, "^a((b)?((c(de)?)?f(g)?)?)?hi$");
        defer alloc.free(compiled);
        try eq_slices(Inst, &[_]Inst{
            .{.literal = 'a'},
            .{.split = .{1, 12}},
            .{.split = .{1, 2}},
            .{.literal = 'b'},
            .{.split = .{1, 9}},
            .{.split = .{1, 5}},
            .{.literal = 'c'},
            .{.split = .{1, 3}},
            .{.literal = 'd'},
            .{.literal = 'e'},
            .{.literal = 'f'},
            .{.split = .{1, 2}},
            .{.literal = 'g'},
            .{.literal = 'h'},
            .{.literal = 'i'},
            .{.matched = .InputMustBeDone},
        }, compiled);
        const vm = Vm{.insts = compiled};
        try eq(false, try vm.matches(""));
        try eq(true, try vm.matches("ahi"));
        try eq(false, try vm.matches("achi"));
        try eq(true, try vm.matches("afhi"));
        try eq(true, try vm.matches("abfhi"));
        try eq(true, try vm.matches("abcfhi"));
        try eq(false, try vm.matches("abcdfhi"));
        try eq(true, try vm.matches("abcdefhi"));
        try eq(false, try vm.matches("abcdefxhi"));
        try eq(true, try vm.matches("abcdefghi"));
        // Test that having ^ means the match need to be at the start.
        try eq(false, try vm.matches("xabcdefghi"));
        // Test that having $ means there can't be anything after the match.
        try eq(false, try vm.matches("abcdefghij"));
        try eq(false, try vm.matches("abcdefghijklmnop"));
    }
}

pub fn match(alloc: std.mem.Allocator, regex: []const u8, str: []const u8) Error!bool {
    const compiled = try compile(alloc, regex);
    defer alloc.free(compiled);
    const vm = Vm{.insts = compiled};
    return vm.matches(str);
}
