// Tinyish Lisp is based on:
// https://github.com/Robert-van-Engelen/tinylisp/blob/main/tinylisp.pdf
//
// TODO:
//   - Real garbage collection
//   - Replace atom strings and environment with hash maps

const std = @import("std");
const Allocator = std.mem.Allocator;

const utils = @import("utils");
const streq = utils.memory_compare;
const ToString = utils.ToString;

const Self = @This();

const IntType = i64;

const debug = false;
const print_raw_list = false;

const Error = error {
    LispOutOfMemory,
    LispInvalidPrimitiveIndex,
    LispInvalidPrimitiveArgKind,
    LispInvalidPrimitiveArgValue,
    LispInvalidPrimitiveArgCount,
    LispUnexpectedEndOfFile,
    LispInvalidParens,
    LispInvalidSyntax,
    LispInvalidEnv,
} || utils.Error || std.mem.Allocator.Error;

const Strings = std.AutoHashMap(usize, []const u8);

allocator: Allocator,
strings: Strings,
next_string_key: usize = 0,
mem: []Expr,
stack_pointer: usize, // in Expr count
heap_pointer: usize = 0, // in u8
nil: *Expr = undefined,
tru: *Expr = undefined,
err: *Expr = undefined,
global_env: *Expr = undefined,
builtin_primitives: [gen_builtin_primitives.len]Primitive = undefined,
extra_primitives: ?[]Primitive = null,
tokenizer: ?Tokenizer = null,
gc_head: ?*Expr = null,
gc_tail: ?*Expr = null,
gc_root: ?*Expr = null,

pub fn new_barren(mem: []Expr, allocator: Allocator) Self {
    return .{
        .allocator = allocator,
        .strings = Strings.init(allocator),
        .mem = mem,
        .stack_pointer = mem.len,
    };
}

pub fn new(mem: []Expr, allocator: Allocator) Error!Self {
    var tl = new_barren(mem, allocator);
    tl.nil = try tl.make_expr(.Nil);
    tl.tru = try tl.get_atom("#t");
    tl.err = try tl.get_atom("#e");
    tl.global_env = try tl.tack_pair_to_list(tl.tru, tl.tru, tl.nil);
    try tl.populate_primitives(gen_builtin_primitives[0..], 0, tl.builtin_primitives[0..]);
    return tl;
}

pub fn done(self: *Self) void {
    _ = self.collect();
    var it = self.strings.iterator();
    while (it.next()) |kv| {
        self.allocator.free(kv.value_ptr.*);
    }
    self.strings.deinit();
}

pub fn set_input(self: *Self,
        input: []const u8, input_name: ?[]const u8, error_out: ?*ToString) void {
    self.tokenizer = Tokenizer{.input = input, .input_name = input_name, .error_out = error_out};
}

pub fn got_zig_error(self: *Self, error_value: Error) Error {
    if (self.tokenizer) |*t| {
        return t.print_zig_error(error_value);
    }
    return error_value;
}

pub fn got_lisp_error(self: *Self, reason: []const u8) *Expr {
    if (self.tokenizer) |*t| {
        t.print_error(reason);
    }
    return self.err;
}

// Expr =======================================================================

pub const ExprKind = enum {
    Int,
    Atom, // Unique symbol
    String,
    Primitive, // Primitive function
    Cons, // (Cons)tructed List
    Closure,
    Nil,
};

pub const Expr = struct {
    pub const Value = union (ExprKind) {
        Int: IntType,
        Atom: []const u8,
        String: usize, // Key for strings hash map
        Primitive: usize, // Index in primitives
        Cons: struct {
            x: *Expr,
            y: *Expr,
        },
        Closure: *Expr,
        Nil: void,
    };

    value: Value = Value.Nil,
    gc_marked: bool = false,
    gc_next: ?*Expr = null,

    pub fn int(value: IntType) Expr {
        return Expr{.value = .{.Int = value}};
    }

    pub fn get_cons(self: *Expr) *Expr {
        return switch (self.value) {
            ExprKind.Cons => self,
            ExprKind.Closure => |cons_expr| cons_expr,
            else => @panic("Expr.get_cons() called with non list-like"),
        };
    }

    pub fn get_string(self: *const Expr, tl: *Self) []const u8 {
        return switch (self.value) {
            ExprKind.String => |key| blk: {
                if (tl.strings.get(key)) |str| {
                    break :blk str;
                }
                @panic("Expr.get_string() called with an invalid key");
            },
            else => @panic("Expr.get_string() called on non-string"),
        };
    }

    fn primitive_obj(self: *Expr, tl: *Self) Error!*const Primitive {
        return switch (self.value) {
            ExprKind.Primitive => |index| try tl.get_primitive(index),
            else => @panic("Expr.primitive_obj() called with non-primitive"),
        };
    }

    fn call_primitive(self: *Expr, tl: *Self, args: *Expr, env: *Expr) Error!*Expr {
        return (try self.primitive_obj(tl)).rt_func(tl, args, env);
    }

    fn primitive_name(self: *Expr, tl: *Self) Error![]const u8 {
        return (try self.primitive_obj(tl)).name;
    }

    fn not(self: *const Expr) bool {
        return @as(ExprKind, self.value) == .Nil;
    }

    fn is_true(self: *const Expr) bool {
        return !self.not();
    }

    fn eq(self: *const Expr, other: *const Expr) bool {
        if (self == other) return true;
        return utils.any_equal(self.value, other.value);
    }
};

test "Expr" {
    const int1 = Expr.int(1);
    const int2 = Expr.int(2);
    const str = Expr{.value = .{.String = 2}};
    const atom = Expr{.value = .{.Atom = "hello"}};
    const nil = Expr{};
    try std.testing.expect(int1.eq(&int1));
    try std.testing.expect(!int1.eq(&int2));
    try std.testing.expect(!int1.eq(&str));
    try std.testing.expect(str.eq(&str));
    try std.testing.expect(!str.eq(&atom));
    try std.testing.expect(nil.eq(&nil));
    try std.testing.expect(!nil.eq(&int1));
}

pub fn print_expr(self: *Self, out: *ToString, expr: *Expr) Error!void {
    return switch (expr.value) {
        ExprKind.Int => |value| try out.int(value),
        ExprKind.Atom => |value| try out.string(value),
        ExprKind.String => {
            try out.std_writer().print("\"{}\"", .{std.zig.fmtEscapes(expr.get_string(self))});
        },
        ExprKind.Primitive => {
            try out.char('#');
            try out.string(try expr.primitive_name(self));
        },
        ExprKind.Cons => {
            try out.char('(');
            if (print_raw_list) {
                try self.print_expr(out, try self.car(expr));
                try out.string(" . ");
                try self.print_expr(out, try self.cdr(expr));
            } else {
                var list_iter = expr;
                while (try self.next_in_list_iter(&list_iter)) |item| {
                    try self.print_expr(out, item);
                    if (list_iter.is_true()) {
                        if (@as(ExprKind, list_iter.value) != .Cons) {
                            try out.string(" . ");
                            try self.print_expr(out, list_iter);
                            break;
                        }
                        try out.char(' ');
                    }
                }
            }
            try out.char(')');
        },
        ExprKind.Closure => try self.print_expr(out, expr.get_cons()),
        ExprKind.Nil => try out.string("nil"),
    };
}

test "print_expr" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var buf: [128]u8 = undefined;
    var ts = ToString{.buffer = buf[0..], .truncate = "..."};
    var mem = [_]Expr{undefined} ** 254;
    var tl = try Self.new(&mem, arena.allocator());
    defer tl.done();

    var list = try tl.make_list([_]*Expr{
        try tl.make_int(30),
        tl.nil,
        try tl.make_int(-40),
        try tl.make_list([_]*Expr{
            try tl.make_string_copy("Hello\n"),
        }),
    });
    try tl.print_expr(&ts, list);
    try std.testing.expectEqualStrings("(30 nil -40 (\"Hello\\n\"))", ts.get());
}

var debug_print_buf: [256]u8 = undefined;

fn debug_print(self: *Self, expected: *Expr) Error![]const u8 {
    var ts = ToString{.buffer = debug_print_buf[0..], .truncate = "..."};
    try self.print_expr(&ts, expected);
    return ts.get();
}

fn expect_expr(self: *Self, expected: *Expr, result: *Expr) !void {
    const are_equal = expected.eq(result);
    if (!are_equal) {
        std.debug.print(
            \\
            \\Expected this expression: =====================================================
            \\{s}
            \\
            , .{self.debug_print(expected)});

        std.debug.print(
            \\But found this: ===============================================================
            \\{s}
            \\===============================================================================
            \\
            , .{self.debug_print(result)});
    }
    try std.testing.expect(are_equal);
}

// Garbage Collection =========================================================

fn make_expr(self: *Self, from: Expr.Value) std.mem.Allocator.Error!*Expr {
    const expr = try self.allocator.create(Expr);
    expr.* = .{};
    expr.value = from;
    if (self.gc_tail) |tail| {
        tail.gc_next = expr;
    } else {
        self.gc_head = expr;
    }
    self.gc_tail = expr;
    return expr;
}

fn make_string(self: *Self, str: []const u8) Error!*Expr {
    try self.strings.put(self.next_string_key, str);
    defer self.next_string_key += 1;
    return self.make_expr(.{.String = self.next_string_key});
}

pub fn make_int(self: *Self, value: IntType) Error!*Expr {
    return self.make_expr(.{.Int = value});
}

pub fn make_bool(self: *const Self, value: bool) *Expr {
    return if (value) self.tru else self.nil;
}

fn make_string_copy(self: *Self, str: []const u8) Error!*Expr {
    return self.make_string(try self.allocator.dupe(u8, str));
}

fn collect(self: *Self) usize {
    var expr_maybe = self.gc_root;

    // Sweep Phase
    expr_maybe = self.gc_head;
    var count: usize = 0;
    while (expr_maybe) |expr| {
        expr_maybe = expr.gc_next;
        if (!expr.gc_marked) {
            self.allocator.destroy(expr);
            count += 1;
        }
    }
    return count;
}

test "gc" {
    var ta = utils.TestAlloc{};
    defer ta.deinit(.Panic);
    errdefer ta.deinit(.NoPanic);
    var mem = [_]Expr{undefined} ** 2;
    var tl = Self.new_barren(&mem, ta.alloc());
    {
        _ = try tl.make_expr(.Nil);
        _ = tl.collect();
    }
}

// Primitive Function Support =================================================

pub const GenPrimitive = struct {
    name: []const u8,
    zig_func: anytype,
    preeval_args: bool = true,
    pass_env: bool = false,
    pass_arg_list: bool = false,
};

const gen_builtin_primitives = [_]GenPrimitive{
    // zig_func should be like fn(tl: *Self, [env: Expr,] [args: Expr|arg1: Expr, ...]) Error!Expr
    .{.name = "eval", .zig_func = eval},
    .{.name = "quote", .zig_func = quote, .preeval_args = false},
    .{.name = "cons", .zig_func = cons},
    .{.name = "car", .zig_func = car},
    .{.name = "cdr", .zig_func = cdr},
    .{.name = "+", .zig_func = add, .pass_arg_list = true},
    .{.name = "-", .zig_func = subtract, .pass_arg_list = true},
    .{.name = "*", .zig_func = multiply, .pass_arg_list = true},
    .{.name = "/", .zig_func = divide, .pass_arg_list = true},
    .{.name = "<", .zig_func = less},
    .{.name = "eq?", .zig_func = eq},
    .{.name = "or", .zig_func = @"or"},
    .{.name = "and", .zig_func = @"and"},
    .{.name = "not", .zig_func = not},
    .{.name = "cond", .zig_func = cond,
        .preeval_args = false, .pass_env = true, .pass_arg_list = true},
    .{.name = "if", .zig_func = @"if", .preeval_args = false, .pass_env = true},
    .{.name = "let*", .zig_func = leta,
        .preeval_args = false, .pass_env = true, .pass_arg_list = true},
    .{.name = "lambda", .zig_func = lambda, .preeval_args = false, .pass_env = true},
    .{.name = "define", .zig_func = define, .preeval_args = false, .pass_env = true},
};

pub const Primitive = struct {
    name: []const u8,
    rt_func: fn(tl: *Self, args: *Expr, env: *Expr) Error!*Expr,
};

// Use comptime info to dynamically setup, check, and pass arguments to
// primitive functions.
fn PrimitiveAdaptor(comptime prim: GenPrimitive) type {
    return struct {
        fn rt_func(tl: *Self, args: *Expr, env: *Expr) Error!*Expr {
            // TODO: assert expresion types and count
            const zfti = @typeInfo(@TypeOf(prim.zig_func)).Fn;
            if (zfti.args.len == 0) {
                @compileError(prim.name ++ " primitive fn must at least take *TinyishLisp");
            }
            if (zfti.return_type != Error!*Expr) {
                @compileError(prim.name ++ " primitive fn must return Error!*Expr");
            }
            var arg_tuple: std.meta.ArgsTuple(@TypeOf(prim.zig_func)) = undefined;
            var args_list = args;
            if (prim.preeval_args) {
                args_list = try tl.evlis(args_list, env);
            }
            inline for (zfti.args) |arg, i| {
                if (i == 0) {
                    if (arg.arg_type.? != *Self) {
                        @compileError(prim.name ++ " primitive fn 1st arg must be *TinyishLisp");
                    } else {
                        arg_tuple[0] = tl;
                    }
                } else if (arg.arg_type.? == *Expr) {
                    if (i == 1 and prim.pass_env) {
                        arg_tuple[i] = env;
                    } else if (prim.pass_arg_list) {
                        // Pass in args as a list
                        arg_tuple[i] = args_list;
                        break;
                    } else {
                        // Single Argument
                        arg_tuple[i] = try tl.car(args_list);
                        args_list = try tl.cdr(args_list);
                    }
                } else {
                    @compileError(prim.name ++ " invalid primitive fn arg: " ++
                        @typeName(arg.arg_type.?));
                }
            }

            return @call(.{}, prim.zig_func, arg_tuple);
        }
    };
}

fn populate_primitives(self: *Self, comptime gen: []const GenPrimitive,
        index_offset: usize, primitives: []Primitive) Error!void {
    comptime var i = 0;
    @setEvalBranchQuota(2000);
    inline while (i < gen.len) {
        primitives[i] = .{
            .name = gen[i].name,
            .rt_func = PrimitiveAdaptor(gen[i]).rt_func,
        };
        self.global_env = try self.tack_pair_to_list(try self.get_atom(gen[i].name),
            try self.make_expr(.{.Primitive = index_offset + i}), self.global_env);
        i += 1;
    }
}

pub fn populate_extra_primitives(self: *Self, comptime gen: []const GenPrimitive,
        primitives: []Primitive) Error!void {
    try self.populate_primitives(gen, self.builtin_primitives.len, primitives);
    self.extra_primitives = primitives;
}

fn get_primitive(self: *Self, index: usize) Error!*const Primitive {
    const bpl = self.builtin_primitives.len;
    if (index < bpl) {
        return &self.builtin_primitives[index];
    } else if (self.extra_primitives) |ep| {
        if (index < bpl + ep.len) {
            return &ep[index - bpl];
        }
    }

    return self.got_zig_error(Error.LispInvalidPrimitiveIndex);
}

// Atom Management ============================================================

fn next_atom(self: *Self, pos: *usize) ?[]const u8 {
    if (pos.* >= self.heap_pointer) return null;
    const heap = @ptrCast([*]const u8, &self.mem[0]);
    var i: usize = 0;
    while (heap[pos.* + i] != 0) {
        i += 1;
    }
    const end = pos.* + i;
    defer pos.* = end + 1;
    return heap[pos.*..end];
}

fn check_pointers(self: *Self, hp: usize, sp: usize) Error!void {
    if (hp > (sp - 1) * @sizeOf(Expr)) {
        return self.got_zig_error(Error.LispOutOfMemory);
    }
}

fn get_atom(self: *Self, name: []const u8) Error!*Expr {
    var pos: usize = 0;
    while (self.next_atom(&pos)) |str| {
        if (streq(str, name)) {
            return self.make_expr(.{.Atom = str});
        }
    }
    const end = pos + name.len;
    try self.check_pointers(end + 1, self.stack_pointer);
    const heap = @ptrCast([*]u8, &self.mem[0]);
    for (name) |c| {
        heap[self.heap_pointer] = c;
        self.heap_pointer += 1;
    }
    heap[self.heap_pointer] = 0;
    self.heap_pointer += 1;
    return self.make_expr(.{.Atom = heap[pos..end]});
}

test "atom" {
    var ta = utils.TestAlloc{};
    defer ta.deinit(.Panic);
    errdefer ta.deinit(.NoPanic);
    var mem = [_]Expr{undefined} ** 2;
    var tl = Self.new_barren(&mem, ta.alloc());
    defer tl.done();

    // Declare two atoms
    const str1 = "hello";
    const atom1 = try tl.get_atom(str1);
    try std.testing.expectEqualStrings("hello\x00",
        @ptrCast([*]const u8, tl.mem)[0..tl.heap_pointer]);
    const str2 = "world";
    _ = try tl.get_atom(str2);
    try std.testing.expectEqualStrings("hello\x00world\x00",
        @ptrCast([*]const u8, tl.mem)[0..tl.heap_pointer]);
    // Trying to get "hello" again doesn't add another hello
    const atom3 = try tl.get_atom(str1);
    try std.testing.expectEqualStrings("hello\x00world\x00",
        @ptrCast([*]const u8, tl.mem)[0..tl.heap_pointer]);
    // and is the same as the first hello
    try std.testing.expectEqual(atom1.value, atom3.value);

    // Trying to use too much space returns an error
    try std.testing.expectError(Error.LispOutOfMemory, tl.get_atom("a" ** 28));
    // And the memory is unchanged
    try std.testing.expectEqualStrings("hello\x00world\x00",
        @ptrCast([*]const u8, tl.mem)[0..tl.heap_pointer]);
}

// List Functions =============================================================

// (cons x y): return the pair (x y)/list
pub fn cons(self: *Self, x: *Expr, y: *Expr) Error!*Expr {
    return self.make_expr(.{.Cons = .{.x = x, .y = y}});
}

fn car_cdr(self: *Self, x: *Expr, get_x: bool) Error!*Expr {
    return switch (x.value) {
        ExprKind.Cons => |*pair| if (get_x) pair.x else pair.y,
        else => blk: {
            if (debug) {
                std.debug.print("error in car_cdr: {s} is not a list\n",
                    .{try self.debug_print(x)});
            }
            break :blk self.got_lisp_error("value passed to cdr or car isn't a list");
        }
    };
}

// (car x y): return x
pub fn car(self: *Self, x: *Expr) Error!*Expr {
    return try self.car_cdr(x, true);
}

// (cdr x y): return y
pub fn cdr(self: *Self, x: *Expr) Error!*Expr {
    return try self.car_cdr(x, false);
}

test "cons, car, cdr" {
    var ta = utils.TestAlloc{};
    defer ta.deinit(.Panic);
    errdefer ta.deinit(.NoPanic);
    var mem = [_]Expr{undefined} ** 16;
    var tl = Self.new_barren(&mem, ta.alloc());
    defer tl.done();

    const ten = try tl.make_int(10);
    const twenty = try tl.make_int(20);
    const list = try tl.cons(ten, twenty);

    try std.testing.expectEqual(ten, try tl.car(list));
    try std.testing.expectEqual(twenty, try tl.cdr(list));
}

pub fn make_list(self: *Self, items: anytype) Error!*Expr {
    var head = self.nil;
    var i = items.len;
    while (i > 0) {
        i -= 1;
        head = try self.cons(items[i], head);
    }
    return head;
}

pub fn next_in_list_iter(self: *Self, list_iter: **Expr) Error!?*Expr {
    if (list_iter.*.not()) {
        return null;
    }
    const value = try self.car(list_iter.*);
    const next_list_iter = try self.cdr(list_iter.*);
    list_iter.* = next_list_iter;
    return value;
}

test "make_list, next_in_list_iter" {
    var ta = utils.TestAlloc{};
    defer ta.deinit(.Panic);
    errdefer ta.deinit(.NoPanic);
    var mem = [_]Expr{undefined} ** 32;
    var tl = Self.new_barren(&mem, ta.alloc());
    tl.nil = try tl.make_expr(.Nil);
    defer tl.done();

    const items = [_]*Expr{try tl.make_int(30), try tl.make_expr(.Nil), try tl.make_int(40)};
    var list_iter = try tl.make_list(items);
    for (items) |item| {
        try std.testing.expect((try tl.next_in_list_iter(&list_iter)).?.eq(item));
    }
    const nul: ?*Expr = null;
    try std.testing.expectEqual(nul, try tl.next_in_list_iter(&list_iter));
}

// Tack a pair of "first" and "second" on to "list" and return the new list.
pub fn tack_pair_to_list(self: *Self, first: *Expr, second: *Expr, list: *Expr) Error!*Expr {
    return try self.cons(try self.cons(first, second), list);
}

// // eval and Helpers ===========================================================

// Find definition of atom
fn assoc(self: *Self, atom: *Expr, env: *Expr) Error!*Expr {
    var list_iter = env;
    while (try self.next_in_list_iter(&list_iter)) |item| {
        if (@as(ExprKind, item.value) != .Cons) {
            return self.got_zig_error(Error.LispInvalidEnv);
        }
        if (atom.eq(try self.car(item))) {
            return self.cdr(item);
        }
    }
    return self.nil;
}

test "assoc" {
    var ta = utils.TestAlloc{};
    defer ta.deinit(.Panic);
    errdefer ta.deinit(.NoPanic);
    var mem = [_]Expr{undefined} ** 254;
    var tl = try Self.new(&mem, ta.alloc());
    defer tl.done();

    try tl.expect_expr(try tl.make_expr(.{.Atom = "#t"}),
        try tl.assoc(try tl.get_atom("#t"), tl.global_env));
    try tl.expect_expr(try tl.make_expr(.{.Primitive = 5}),
        try tl.assoc(try tl.get_atom("+"), tl.global_env));
}

fn bind(self: *Self, vars: *Expr, args: *Expr, env: *Expr) Error!*Expr {
    return switch (vars.value) {
        ExprKind.Nil => env,
        ExprKind.Cons => try self.bind(try self.cdr(vars), try self.cdr(args),
            try self.tack_pair_to_list(try self.car(vars), try self.car(args), env)),
        else => try self.tack_pair_to_list(vars, args, env),
    };
}

// Eval every item in list "exprs"
fn evlis(self: *Self, exprs: *Expr, env: *Expr) Error!*Expr {
    return switch (exprs.value) {
        ExprKind.Cons => try self.cons(
            try self.eval(try self.car(exprs), env),
            try self.evlis(try self.cdr(exprs), env)
        ),
        else => try self.eval(exprs, env),
    };
}

// Run closure
fn reduce(self: *Self, closure: *Expr, args: *Expr, env: *Expr) Error!*Expr {
    const c = closure.get_cons();
    return try self.eval(
        try self.cdr(try self.car(c)),
        try self.bind(
            try self.car(try self.car(c)),
            try self.evlis(args, env),
            if ((try self.cdr(c)).not())
                self.global_env
            else
                try self.cdr(c)
        )
    );
}

// Run func with args and env
fn apply(self: *Self, callable: *Expr, args: *Expr, env: *Expr) Error!*Expr {
    return switch (callable.value) {
        ExprKind.Primitive => try callable.call_primitive(self, args, env),
        ExprKind.Closure => try self.reduce(callable, args, env),
        else => blk: {
            if (debug) {
                std.debug.print("error in apply: {s} is not callable\n",
                    .{try self.debug_print(callable)});
            }
            break :blk self.got_lisp_error("value passed to apply isn't callable");
        }
    };
}

pub fn eval(self: *Self, val: *Expr, env: *Expr) Error!*Expr {
    // if (debug) std.debug.print("eval: {s}\n", .{try self.debug_print(val)});
    const rv = switch (val.value) {
        ExprKind.Atom => try self.assoc(val, env),
        ExprKind.Cons => try self.apply(
            try self.eval(try self.car(val), env), try self.cdr(val), env),
        else => val,
    };
    // if (debug) std.debug.print("eval return: {s}\n", .{try self.debug_print(rv)});
    return rv;
}

test "eval" {
    var ta = utils.TestAlloc{};
    defer ta.deinit(.Panic);
    errdefer ta.deinit(.NoPanic);
    var mem = [_]Expr{undefined} ** 254;
    var tl = try Self.new(&mem, ta.alloc());
    defer tl.done();

    try tl.expect_expr(try tl.make_int(6), try tl.eval(
        try tl.make_list([_]*Expr{
            try tl.get_atom("+"),
            try tl.make_int(1),
            try tl.make_int(2),
            try tl.make_int(3),
        }),
        tl.global_env
    ));
}

// Parsing ====================================================================

const TokenKind = enum {
    IntValue,
    Atom,
    String,
    Open,
    Close,
    Quote,
    Dot,
};

const Token = union (TokenKind) {
    IntValue: IntType,
    Atom: []const u8,
    String: []const u8,
    Open: void,
    Close: void,
    Quote: void,
    Dot: void,

    fn eq(self: Token, other: Token) bool {
        return utils.any_equal(self, other);
    }
};

const Tokenizer = struct {
    input: []const u8,
    pos: usize = 0,
    input_name: ?[]const u8 = null,
    lineno: usize = 1,
    error_out: ?*ToString = null,

    fn get(self: *Tokenizer) ?Token {
        while (self.pos < self.input.len) {
            switch (self.input[self.pos]) {
                '\n' => {
                    self.lineno += 1;
                    self.pos += 1;
                },
                ' ', '\t' => {
                    self.pos += 1;
                },
                ';' => {
                    while (self.pos < self.input.len and self.input[self.pos] != '\n') {
                        self.pos += 1;
                    }
                },
                else => break,
            }
        }
        var token: ?Token = null;
        var start: usize = self.pos;
        var first = true;
        while (self.pos < self.input.len) {
            var special_token: ?Token = null;
            switch (self.input[self.pos]) {
                '(' => special_token = Token.Open,
                ')' => special_token = Token.Close,
                '\'' => special_token = Token.Quote,
                '.' => special_token = Token.Dot,
                ' ', '\n', '\t' => {
                    break;
                },
                '"' => {
                    if (first) {
                        self.pos += 1; // starting quote
                        start = self.pos;
                        while (self.input[self.pos] != '"') {
                            // TODO: Unexpected newline or eof
                            self.pos += 1;
                        }
                        token = Token{.String = self.input[start..self.pos]};
                        self.pos += 1; // ending quote
                    }
                    break;
                },
                else => {
                    first = false;
                    self.pos += 1;
                    continue;
                },
            }
            if (token == null and first) {
                token = special_token.?;
                self.pos += 1;
            }
            break;
        }
        const str = self.input[start..self.pos];
        if (token == null and str.len > 0) {
            const int_value: ?IntType = std.fmt.parseInt(IntType, str, 0) catch null;
            token = if (int_value) |iv| Token{.IntValue = iv} else Token{.Atom = str};
        }
        return token;
    }

    fn must_get(self: *Tokenizer) Error!Token {
        return self.get() orelse self.print_zig_error(Error.LispUnexpectedEndOfFile);
    }

    fn print_error(self: *Tokenizer, reason: []const u8) void {
        if (self.error_out) |eo| {
            eo.string("ERROR on line ") catch unreachable;
            eo.int(self.lineno) catch unreachable;
            if (self.input_name) |in| {
                eo.string(" of ") catch unreachable;
                eo.string(in) catch unreachable;
            }
            eo.string(": ") catch unreachable;
            eo.string(reason) catch unreachable;
            eo.char('\n') catch unreachable;
        }
    }

    fn print_zig_error(self: *Tokenizer, error_value: Error) Error {
        self.print_error(@errorName(error_value));
        return error_value;
    }
};

test "Tokenizer" {
    var t = Tokenizer{.input =
        "  (x 1( y \"hello\" ' ; This is a comment\n(24 . ab))c) ; comment at end"};
    try std.testing.expect((try t.must_get()).eq(Token.Open));
    try std.testing.expect((try t.must_get()).eq(Token{.Atom = "x"}));
    try std.testing.expect((try t.must_get()).eq(Token{.IntValue = 1}));
    try std.testing.expect((try t.must_get()).eq(Token.Open));
    try std.testing.expect((try t.must_get()).eq(Token{.Atom = "y"}));
    try std.testing.expect((try t.must_get()).eq(Token{.String = "hello"}));
    try std.testing.expect((try t.must_get()).eq(Token.Quote));
    try std.testing.expect((try t.must_get()).eq(Token.Open));
    try std.testing.expect((try t.must_get()).eq(Token{.IntValue = 24}));
    try std.testing.expect((try t.must_get()).eq(Token.Dot));
    try std.testing.expect((try t.must_get()).eq(Token{.Atom = "ab"}));
    try std.testing.expect((try t.must_get()).eq(Token.Close));
    try std.testing.expect((try t.must_get()).eq(Token.Close));
    try std.testing.expect((try t.must_get()).eq(Token{.Atom = "c"}));
    try std.testing.expect((try t.must_get()).eq(Token.Close));
    try std.testing.expectError(Error.LispUnexpectedEndOfFile, t.must_get());
}

fn parse_list(self: *Self, tokenizer: *Tokenizer) Error!*Expr {
    const token = try tokenizer.must_get();
    return switch (token) {
        TokenKind.Close => self.nil,
        TokenKind.Dot => dot_blk: {
            const second = self.must_parse(tokenizer);
            const expected_close = try tokenizer.must_get();
            if (@as(TokenKind, expected_close) != .Close) {
                return tokenizer.print_zig_error(Error.LispInvalidParens);
            }
            break :dot_blk second;
        },
        else => else_blk: {
            const first = try self.parse_i(tokenizer, token);
            const second = try self.parse_list(tokenizer);
            break :else_blk try self.cons(first, second);
        }
    };
}

fn parse_quote(self: *Self, tokenizer: *Tokenizer) Error!*Expr {
    return try self.cons(try self.get_atom("quote"),
        try self.cons(try self.must_parse(tokenizer), self.nil));
}

fn parse_i(self: *Self, tokenizer: *Tokenizer, token: Token) Error!*Expr {
    return switch (token) {
        TokenKind.Open => self.parse_list(tokenizer),
        TokenKind.Quote => self.parse_quote(tokenizer),
        TokenKind.Atom => |name| try self.get_atom(name),
        TokenKind.IntValue => |value| try self.make_int(value),
        TokenKind.String => |value| try self.make_string_copy(value),
        TokenKind.Close => tokenizer.print_zig_error(Error.LispInvalidParens),
        TokenKind.Dot => tokenizer.print_zig_error(Error.LispInvalidSyntax),
    };
}

fn must_parse(self: *Self, tokenizer: *Tokenizer) Error!*Expr {
    return self.parse_i(tokenizer, try tokenizer.must_get());
}

fn parse_tokenizer(self: *Self, tokenizer: *Tokenizer) Error!?*Expr {
    var rv: ?*Expr = null;
    if (tokenizer.get()) |t| {
        rv = try self.eval(try self.parse_i(tokenizer, t), self.global_env);
    }
    return rv;
}

fn parse_str(self: *Self, input: []const u8) Error!?*Expr {
    var tokenizer = Tokenizer{.input = input};
    return self.parse_tokenizer(&tokenizer);
}

test "parse_str" {
    var ta = utils.TestAlloc{};
    defer ta.deinit(.Panic);
    errdefer ta.deinit(.NoPanic);
    var mem = [_]Expr{undefined} ** 254;
    var tl = try Self.new(&mem, ta.alloc());
    defer tl.done();

    try tl.expect_expr(try tl.make_int(6), (try tl.parse_str("(+ 1 2 3)")).?);
    try std.testing.expectEqualStrings("Hello", (try tl.parse_str("\"Hello\"")).?.get_string(&tl));
}

pub fn parse_input(self: *Self) Error!?*Expr {
    var rv: ?*Expr = null;
    if (self.tokenizer) |*t| {
        rv = try self.parse_tokenizer(t);
    }
    return rv;
}

pub fn parse_all_input(self: *Self, input: []const u8,
        input_name: ?[]const u8, error_out: ?*ToString) Error!void {
    self.set_input(input, input_name, error_out);
    while (try self.parse_input()) |e| {
        _ = e;
    }
}

test "parse_all_input" {
    var ta = utils.TestAlloc{};
    defer ta.deinit(.Panic);
    errdefer ta.deinit(.NoPanic);
    var mem = [_]Expr{undefined} ** 254;
    var tl = try Self.new(&mem, ta.alloc());
    defer tl.done();

    try tl.parse_all_input(
        \\(define a 5)
        \\(define b 3)
        \\(define func (lambda (x y) (+ (* x y) y)))
        , null , null
    );

    // Make sure both lists and pairs are parsed correctly
    try tl.parse_all_input(
        "(define begin (lambda (x . args) (if args (begin . args) x)))\n", null, null);

    try tl.expect_expr(try tl.make_int(18), (try tl.parse_str("(func a b)")).?);
}

// Custom Primitive Functions =================================================

var custom_primitive_test_value: i64 = 10;
fn custom_primitive(self: *Self, value: *Expr) Error!*Expr {
    defer custom_primitive_test_value = value.value.Int;
    return self.make_int(custom_primitive_test_value);
}

test "custom primitive" {
    var ta = utils.TestAlloc{};
    defer ta.deinit(.Panic);
    errdefer ta.deinit(.NoPanic);
    var mem = [_]Expr{undefined} ** 254;
    var tl = try Self.new(&mem, ta.alloc());
    defer tl.done();

    const custom = [_]GenPrimitive{
        .{.name = "cp", .zig_func = custom_primitive},
    };
    var custom_primitives: [custom.len]Primitive = undefined;
    try tl.populate_extra_primitives(custom[0..], custom_primitives[0..]);

    try tl.expect_expr(try tl.make_int(10), (try tl.parse_str("(cp 20)")).?);
    try std.testing.expectEqual(@as(i64, 20), custom_primitive_test_value);
}

// Rest of Primitive Functions ================================================

// (` x): return x
fn quote(self: *Self, x: *Expr) Error!*Expr {
    _ = self;
    return x;
}

// (eq? x y): return tru if x equals y else nil
pub fn eq(self: *Self, x: *Expr, y: *Expr) Error!*Expr {
    return self.make_bool(x.eq(y));
}

pub fn add(self: *Self, args: *Expr) Error!*Expr {
    var expr_kind: ?ExprKind = null;
    var total_string_len: usize = 0;
    {
        var check_iter = args;
        while (try self.next_in_list_iter(&check_iter)) |arg| {
            if (expr_kind) |ek| {
                if (ek != @as(ExprKind, arg.value)) {
                    return Error.LispInvalidPrimitiveArgKind;
                }
            } else {
                expr_kind = @as(ExprKind, arg.value);
            }
            switch (@as(ExprKind, arg.value)) {
                .String => total_string_len += arg.get_string(self).len,
                .Int => {},
                else => return Error.LispInvalidPrimitiveArgKind,
            }
        }
    }
    if (expr_kind) |ek| {
        switch (ek) {
            ExprKind.Int => {
                var list_iter = args;
                var result: IntType = (try self.next_in_list_iter(&list_iter)).?.value.Int;
                while (try self.next_in_list_iter(&list_iter)) |arg| {
                    result += arg.value.Int;
                }
                return self.make_int(result);
            },
            ExprKind.String => {
                var list_iter = args;
                var result: []u8 = try self.allocator.alloc(u8, total_string_len);
                var got: usize = 0;
                while (try self.next_in_list_iter(&list_iter)) |arg| {
                    const s = arg.get_string(self);
                    for (s) |c| {
                        result[got] = c;
                        got += 1;
                    }
                }
                return self.make_string(result);
            },
            else => unreachable,
        }
    }
    return self.nil;
}

test "add" {
    var ta = utils.TestAlloc{};
    defer ta.deinit(.Panic);
    errdefer ta.deinit(.NoPanic);
    var mem = [_]Expr{undefined} ** 254;
    var tl = try Self.new(&mem, ta.alloc());
    defer tl.done();

    try tl.expect_expr(try tl.make_int(6), (try tl.parse_str("(+ 1 2 3)")).?);
    try std.testing.expectEqualStrings("Hello world", (
        try tl.parse_str("(+ \"Hello\" \" world\")")).?.get_string(&tl));
}

pub fn subtract(self: *Self, args: *Expr) Error!*Expr {
    var list_iter = args;
    var result: IntType = (try self.next_in_list_iter(&list_iter)).?.value.Int;
    while (try self.next_in_list_iter(&list_iter)) |arg| {
        result -= arg.value.Int;
    }
    return self.make_int(result);
}

pub fn multiply(self: *Self, args: *Expr) Error!*Expr {
    var list_iter = args;
    var result: IntType = (try self.next_in_list_iter(&list_iter)).?.value.Int;
    while (try self.next_in_list_iter(&list_iter)) |arg| {
        result *= arg.value.Int;
    }
    return self.make_int(result);
}

pub fn divide(self: *Self, args: *Expr) Error!*Expr {
    var list_iter = args;
    var result: IntType = (try self.next_in_list_iter(&list_iter)).?.value.Int;
    while (try self.next_in_list_iter(&list_iter)) |arg| {
        result = @divFloor(result, arg.value.Int);
    }
    return self.make_int(result);
}

pub fn less(self: *Self, x: *Expr, y: *Expr) Error!*Expr {
    return self.make_bool(x.value.Int < y.value.Int);
}

pub fn @"or"(self: *Self, x: *Expr, y: *Expr) Error!*Expr {
    return self.make_bool(x.is_true() or y.is_true());
}

pub fn @"and"(self: *Self, x: *Expr, y: *Expr) Error!*Expr {
    return self.make_bool(x.is_true() and y.is_true());
}

pub fn @"not"(self: *Self, x: *Expr) Error!*Expr {
    return self.make_bool(x.not());
}

pub fn cond(self: *Self, env: *Expr, args: *Expr) Error!*Expr {
    var list_iter = args;
    var rv = self.nil;
    while (try self.next_in_list_iter(&list_iter)) |cond_value| {
        var cond_value_it = cond_value;
        const test_cond = (try self.next_in_list_iter(&cond_value_it)).?;
        const return_value = (try self.next_in_list_iter(&cond_value_it)).?;
        if ((try self.eval(test_cond, env)).is_true()) {
            rv = try self.eval(return_value, env);
        }
    }
    return rv;
}

test "cond" {
    var ta = utils.TestAlloc{};
    defer ta.deinit(.Panic);
    errdefer ta.deinit(.NoPanic);
    var mem = [_]Expr{undefined} ** 254;
    var tl = try Self.new(&mem, ta.alloc());
    defer tl.done();

    try tl.expect_expr(try tl.make_int(3), (try tl.parse_str(
        "(cond ((eq? 'a 'b) 1) ((< 2 1) 2) (#t 3))")).?);
}

pub fn @"if"(self: *Self, env: *Expr, test_expr: *Expr,
        then_expr: *Expr, else_expr: *Expr) Error!*Expr {
    const result_expr = if ((try self.eval(test_expr, env)).is_true()) then_expr else else_expr;
    return try self.eval(result_expr, env);
}

test "if" {
    var ta = utils.TestAlloc{};
    defer ta.deinit(.Panic);
    errdefer ta.deinit(.NoPanic);
    var mem = [_]Expr{undefined} ** 254;
    var tl = try Self.new(&mem, ta.alloc());
    defer tl.done();

    try tl.expect_expr(try tl.make_int(1), (try tl.parse_str("(if (eq? 'a 'a) 1 2)")).?);
}

// (let* (a x) (b x) ... (+ a b))
pub fn leta(self: *Self, env: *Expr, args: *Expr) Error!*Expr {
    var list_iter = args;
    var this_env = env;
    while (try self.next_in_list_iter(&list_iter)) |arg| {
        if (list_iter.is_true()) {
            var var_value_it = arg;
            const var_expr = (try self.next_in_list_iter(&var_value_it)).?;
            const value_expr = (try self.next_in_list_iter(&var_value_it)).?;
            const value = try self.eval(value_expr, this_env);
            this_env = try self.tack_pair_to_list(var_expr, value, this_env);
        } else {
            return try self.eval(arg, this_env);
        }
    }
    return self.got_zig_error(Error.LispInvalidPrimitiveArgCount);
}

test "leta" {
    var ta = utils.TestAlloc{};
    defer ta.deinit(.Panic);
    errdefer ta.deinit(.NoPanic);
    var mem = [_]Expr{undefined} ** 254;
    var tl = try Self.new(&mem, ta.alloc());
    defer tl.done();

    try tl.expect_expr(try tl.make_int(12),
        (try tl.parse_str("(let* (a 3) (b (* a a)) (+ a b))")).?);
}

// (lambda args expr)
pub fn lambda(self: *Self, env: *Expr, args: *Expr, expr: *Expr) Error!*Expr {
    return self.make_expr(.{.Closure = try self.tack_pair_to_list(args, expr,
        if (env.eq(self.global_env)) self.nil else env)});
}

test "lambda" {
    var ta = utils.TestAlloc{};
    defer ta.deinit(.Panic);
    errdefer ta.deinit(.NoPanic);
    var mem = [_]Expr{undefined} ** 254;
    var tl = try Self.new(&mem, ta.alloc());
    defer tl.done();

    try tl.expect_expr(try tl.make_int(9), (try tl.parse_str("((lambda (x) (* x x)) 3)")).?);
}

// (define var expr)
pub fn define(self: *Self, env: *Expr, atom: *Expr, expr: *Expr) Error!*Expr {
    self.global_env = try self.tack_pair_to_list(atom, try self.eval(expr, env), env);
    return atom;
}

test "define" {
    var ta = utils.TestAlloc{};
    defer ta.deinit(.Panic);
    errdefer ta.deinit(.NoPanic);
    var mem = [_]Expr{undefined} ** 254;
    var tl = try Self.new(&mem, ta.alloc());
    defer tl.done();

    _ = try tl.parse_str("(define x 3)");
    try tl.expect_expr(try tl.make_int(4), (try tl.parse_str("(+ 1 x)")).?);
}
