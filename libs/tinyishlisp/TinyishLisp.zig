// Tinyish Lisp is based on:
// https://github.com/Robert-van-Engelen/tinylisp/blob/main/tinylisp.pdf
//
// TODO:
//   - Replace atom strings and environment with hash maps

const std = @import("std");
const Allocator = std.mem.Allocator;

const utils = @import("utils");
const streq = utils.memory_compare;
const GenericWriter = utils.GenericWriter;

const Self = @This();

const IntType = i64;

const debug = false;
const print_raw_list = false;

pub const Error = error {
    LispInvalidPrimitiveIndex,
    LispInvalidPrimitiveArgCount,
    LispUnexpectedEndOfInput,
    LispInvalidParens,
    LispInvalidSyntax,
    LispInvalidEnv,
} || utils.Error || std.mem.Allocator.Error || GenericWriter.GenericWriterError;

const ExprList = utils.List(Expr);
const AtomMap = std.StringHashMap(*Expr);
const ExprSet = std.AutoHashMap(*Expr, void);

allocator: Allocator,

// Expr/Values
atoms: AtomMap = undefined,
nil: *Expr = undefined,
tru: *Expr = undefined,
err: *Expr = undefined,
global_env: *Expr = undefined,
gc_owned: ExprList = undefined,
gc_keep: ExprSet = undefined,
parse_return: ?*Expr = null,

// Primitive Functions
builtin_primitives: [gen_builtin_primitives.len]Primitive = undefined,
extra_primitives: ?[]Primitive = null,

// Parsing
input: ?[]const u8 = null,
pos: usize = 0,
input_name: ?[]const u8 = null,
lineno: usize = 1,
out: ?*GenericWriter.Writer = null,
error_out: ?*GenericWriter.Writer = null,

pub fn new_barren(allocator: Allocator) Self {
    return .{
        .allocator = allocator,
        .atoms = AtomMap.init(allocator),
        .gc_owned = .{.alloc = allocator},
        .gc_keep = ExprSet.init(allocator),
    };
}

pub fn new(allocator: Allocator) Error!Self {
    var tl = new_barren(allocator);

    tl.nil = try tl.make_expr(.Nil);
    tl.tru = try tl.make_atom("#t", .NoCopy);
    tl.err = try tl.make_atom("#e", .NoCopy);
    tl.global_env = try tl.tack_pair_to_list(tl.tru, tl.tru, tl.nil);

    try tl.populate_primitives(gen_builtin_primitives[0..], 0, tl.builtin_primitives[0..]);

    return tl;
}

pub fn done(self: *Self) void {
    _ = self.collect(.All);
    self.gc_owned.clear();
    self.atoms.deinit();
    self.gc_keep.deinit();
}

pub fn set_input(self: *Self, input: []const u8, input_name: ?[]const u8) void {
    self.pos = 0;
    self.input = input;
    self.input_name = input_name;
}

pub fn got_zig_error(self: *Self, error_value: Error) Error {
    return self.print_zig_error(error_value);
}

pub fn got_lisp_error(self: *Self, reason: []const u8, expr: ?*Expr) *Expr {
    self.print_error(reason, expr);
    return self.err;
}

const TestTl = struct {
    var stderr = std.io.getStdErr().writer();

    ta: utils.TestAlloc = .{},
    tl: Self = undefined,
    generic_stderr_impl: utils.GenericWriterImpl(@TypeOf(stderr)) = .{},
    generic_stderr: utils.GenericWriter.Writer = undefined,

    fn init(self: *TestTl) Error!void {
        errdefer self.ta.deinit(.NoPanic);
        self.tl = try Self.new(self.ta.alloc());

        self.generic_stderr_impl.init(&stderr);
        self.generic_stderr = self.generic_stderr_impl.writer();
        self.tl.error_out = &self.generic_stderr;
    }

    fn done(self: *TestTl) void {
        self.tl.done();
        self.ta.deinit(.Panic);
    }
};

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
    pub const StringValue = struct {
        string: []const u8,
        gc_owned: bool,
    };

    pub const ConsValue = struct {
        x: *Expr,
        y: *Expr,
    };

    pub const Value = union (ExprKind) {
        Int: IntType,
        String: StringValue,
        Atom: *Expr,
        Primitive: usize, // Index in primitives
        Cons: ConsValue,
        Closure: *Expr, // Pointer to Cons List
        Nil: void,
    };

    pub const GcOwned = struct {
        marked: bool = false,
    };

    pub const Owner = union (enum) {
        Gc: GcOwned,
        Other: void,
    };

    value: Value = .Nil,
    owner: Owner = .Other,

    pub fn int(value: IntType) Expr {
        return Expr{.value = .{.Int = value}};
    }

    pub fn get_int(self: *const Expr, comptime As: type) ?As {
        return if (@as(ExprKind, self.value) != .Int) null else
            std.math.cast(As, self.value.Int) catch null;
    }

    pub fn get_cons(self: *Expr) *Expr {
        return switch (self.value) {
            ExprKind.Cons => self,
            ExprKind.Closure => |cons_expr| cons_expr,
            else => @panic("Expr.get_cons() called with non-list-like"),
        };
    }

    pub fn get_string(self: *const Expr) ?[]const u8 {
        return switch (self.value) {
            ExprKind.String => |string_value| string_value.string,
            ExprKind.Atom => |string_expr| string_expr.get_string(),
            else => null,
        };
    }

    pub fn primitive_obj(self: *Expr, tl: *Self) Error!*const Primitive {
        return switch (self.value) {
            ExprKind.Primitive => |index| try tl.get_primitive(index),
            else => @panic("Expr.primitive_obj() called with non-primitive"),
        };
    }

    pub fn call_primitive(self: *Expr, tl: *Self, args: *Expr, env: *Expr) Error!*Expr {
        return (try self.primitive_obj(tl)).rt_func(tl, args, env);
    }

    pub fn primitive_name(self: *Expr, tl: *Self) Error![]const u8 {
        return (try self.primitive_obj(tl)).name;
    }

    pub fn not(self: *const Expr) bool {
        return @as(ExprKind, self.value) == .Nil;
    }

    pub fn is_true(self: *const Expr) bool {
        return !self.not();
    }

    pub fn eq(self: *const Expr, other: *const Expr) bool {
        if (self == other) return true;
        return utils.any_equal(self.value, other.value);
    }
};

test "Expr" {
    const int1 = Expr.int(1);
    const int2 = Expr.int(2);
    var str = Expr{.value = .{.String = .{.string = "hello", .gc_owned = false}}};
    const atom = Expr{.value = .{.Atom = &str}};
    const nil = Expr{};
    try std.testing.expect(int1.eq(&int1));
    try std.testing.expect(!int1.eq(&int2));
    try std.testing.expect(!int1.eq(&str));
    try std.testing.expect(str.eq(&str));
    try std.testing.expect(!str.eq(&atom));
    try std.testing.expect(nil.eq(&nil));
    try std.testing.expect(!nil.eq(&int1));
}

pub fn get_string(self: *Self, expr: *Expr) []const u8 {
    if (expr.get_string()) |str| return str;
    const msg = "TinyishLisp.get_string called on non-string-like";
    self.print_error(msg, expr);
    @panic(msg);
}

// Garbage Collection =========================================================

pub fn make_expr(self: *Self, from: Expr.Value) std.mem.Allocator.Error!*Expr {
    try self.gc_owned.push_back(.{
        .value = from,
        .owner = .{.Gc = .{}},
    });
    return &self.gc_owned.tail.?.value;
}

pub fn keep_expr(self: *Self, expr: *Expr) Error!*Expr {
    try self.gc_keep.putNoClobber(expr, .{});
    return expr;
}

pub fn discard_expr(self: *Self, expr: *Expr) void {
    _ = self.gc_keep.remove(expr);
}

pub fn make_int(self: *Self, value: IntType) Error!*Expr {
    return self.make_expr(.{.Int = value});
}

pub fn make_bool(self: *const Self, value: bool) *Expr {
    return if (value) self.tru else self.nil;
}

const StringManage = enum {
    NoCopy, // Use string as is, do not free when done
    PassOwnership, // Use string as is, free when done
    Copy, // Copy string, free when done
};

pub fn make_string(self: *Self, str: []const u8, manage: StringManage) Error!*Expr {
    var string: []const u8 = str;
    var gc_owned = true;
    switch (manage) {
        .NoCopy => gc_owned = false,
        .Copy => string = try self.allocator.dupe(u8, str),
        .PassOwnership => {},
    }
    return self.make_expr(.{.String = .{.string = string, .gc_owned = gc_owned}});
}

pub fn make_atom(self: *Self, name: []const u8, manage: StringManage) Error!*Expr {
    if (self.atoms.get(name)) |atom| {
        if (manage == .PassOwnership) {
            @panic("make_atom: passed existing name with passing ownership");
        }
        return atom;
    }
    const atom = try self.make_expr(.{.Atom = undefined});
    errdefer _ = self.unmake_expr(atom, .All);
    const string = try self.make_string(name, manage);
    errdefer _ = self.unmake_expr(string, .All);
    try self.atoms.putNoClobber(self.get_string(string), atom);
    atom.value.Atom = string;
    return atom;
}

fn get_atom(self: *Self, name: []const u8) Error!*Expr {
    if (self.atoms.get(name)) |atom| {
        return atom;
    } else {
        if (debug) std.debug.print("error: {s} is not defined\n", .{name});
        return self.err;
    }
}

fn mark(self: *Self, expr: *Expr) void {
    _ = self;
    switch (expr.owner) {
        .Gc => |*gc| {
            if (gc.marked) {
                return;
            }
            gc.marked = true;
        },
        else => {},
    }
    switch (expr.value) {
        .Cons => |pair| {
            self.mark(pair.x);
            self.mark(pair.y);
        },
        .Closure => |ptr| {
            self.mark(ptr);
        },
        .Atom => |string_expr| {
            self.mark(string_expr);
        },
        else => {},
    }
}

const CollectKind = enum {
    Unused,
    All,
};

fn unmake_expr(self: *Self, expr: *Expr, kind: CollectKind) bool {
    switch (expr.owner) {
        .Gc => |*gc| {
            if (kind == .Unused and gc.marked) {
                gc.marked = false;
                return false;
            } else {
                switch (expr.value) {
                    .String => |string_value| {
                        if (string_value.gc_owned) {
                            self.allocator.free(string_value.string);
                        }
                    },
                    .Atom => |string_expr| {
                        _ = self.atoms.remove(self.get_string(string_expr));
                    },
                    else => {},
                }
                self.gc_owned.remove_node(@fieldParentPtr(ExprList.Node, "value", expr));
                return true;
            }
        },
        else => @panic("unmake_expr passed non-gc owned expr"),
    }
}

fn collect(self: *Self, kind: CollectKind) usize {
    // Mark Phase
    if (kind == .Unused) {
        self.mark(self.nil);
        self.mark(self.tru);
        self.mark(self.err);
        self.mark(self.global_env);

        {
            var it = self.atoms.valueIterator();
            while (it.next()) |atom| {
                self.mark(atom.*);
            }
        }

        {
            var it = self.gc_keep.keyIterator();
            while (it.next()) |expr| {
                self.mark(expr.*);
            }
        }

        if (self.parse_return) |expr| {
            self.mark(expr);
        }
    }

    // Sweep Phase
    var count: usize = 0;
    var node_maybe = self.gc_owned.head;
    while (node_maybe) |node| {
        node_maybe = node.next;
        if (self.unmake_expr(&node.value, kind)) {
            count += 1;
        }
    }
    return count;
}

test "gc" {
    var ta = utils.TestAlloc{};
    defer ta.deinit(.Panic);
    errdefer ta.deinit(.NoPanic);
    var tl = try Self.new(ta.alloc());
    defer tl.done();

    _ = try tl.make_expr(.Nil);
    try std.testing.expectEqual(@as(usize, 1), tl.collect(.Unused));
    try std.testing.expectEqual(@as(usize, 0), tl.collect(.Unused));

    _ = try tl.make_list([_]*Expr{
        try tl.make_int(1), // Cons + Int
        try tl.make_int(2), // Cons + Int
        try tl.make_int(3), // Cons + Int
    });
    try std.testing.expectEqual(@as(usize, 6), tl.collect(.Unused));
    try std.testing.expectEqual(@as(usize, 0), tl.collect(.Unused));

    {
        // Make a cycle
        //   +---+
        //   V   |
        // a>b>c>d
        const a = try tl.make_expr(.{.Cons = .{.x = tl.nil, .y = tl.nil}});
        const b = try tl.make_expr(.{.Cons = .{.x = tl.nil, .y = tl.nil}});
        const c = try tl.make_expr(.{.Cons = .{.x = tl.nil, .y = tl.nil}});
        const d = try tl.make_expr(.{.Cons = .{.x = tl.nil, .y = tl.nil}});
        a.value.Cons.y = b;
        b.value.Cons.y = c;
        c.value.Cons.y = d;
        d.value.Cons.y = b;

        try std.testing.expectEqual(@as(usize, 4), tl.collect(.Unused));
        try std.testing.expectEqual(@as(usize, 0), tl.collect(.Unused));
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
    .{.name = "print", .zig_func = print, .pass_arg_list = true},
    .{.name = "progn", .zig_func = progn,
        .preeval_args = false, .pass_env = true, .pass_arg_list = true},
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
        self.global_env = try self.tack_pair_to_list(try self.make_atom(gen[i].name, .NoCopy),
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

// List Functions =============================================================

// (cons x y): return the pair (x y)/list
pub fn cons(self: *Self, x: *Expr, y: *Expr) Error!*Expr {
    return self.make_expr(.{.Cons = .{.x = x, .y = y}});
}

fn car_cdr(self: *Self, x: *Expr, get_x: bool) Error!*Expr {
    return switch (x.value) {
        ExprKind.Cons => |*pair| if (get_x) pair.x else pair.y,
        else => blk: {
            break :blk self.got_lisp_error("value passed to cdr or car isn't a list", x);
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
    var tl = Self.new_barren(ta.alloc());
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

pub fn make_string_list(self: *Self, items: anytype, manage: StringManage) Error!*Expr {
    var head = self.nil;
    var i = items.len;
    while (i > 0) {
        i -= 1;
        head = try self.cons(try self.make_string(items[i], manage), head);
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

pub fn assert_next_in_list_iter(self: *Self, list_iter: **Expr) ?*Expr {
    return self.next_in_list_iter(list_iter) catch {
        @panic("assert_next_in_list_iter: not a list");
    };
}

test "make_list, next_in_list_iter" {
    var ta = utils.TestAlloc{};
    defer ta.deinit(.Panic);
    errdefer ta.deinit(.NoPanic);
    var tl = Self.new_barren(ta.alloc());
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

// print_expr =================================================================

const PrintKind = enum {
    Repr,
    RawRepr,
    Display,
};

// TODO: Remove error hack if https://github.com/ziglang/zig/issues/2971 is fixed
pub fn print_expr(self: *Self, writer: anytype, expr: *Expr, kind: PrintKind)
        @typeInfo(@typeInfo(@TypeOf(writer.write)).BoundFn.return_type.?).ErrorUnion.error_set!void {
    const repr = kind == .Repr or kind == .RawRepr;
    switch (expr.value) {
        .Int => |value| try writer.print("{}", .{value}),
        .Atom => |value| try self.print_expr(writer, value, .Display),
        .String => |string_value| if (repr) {
            try writer.print("\"{}\"", .{std.zig.fmtEscapes(string_value.string)});
        } else {
            _ = try writer.write(string_value.string);
        },
        .Cons => |*pair| {
            _ = try writer.write("(");
            if (kind == .RawRepr) {
                try self.print_expr(writer, pair.x, kind);
                _ = try writer.write(" . ");
                try self.print_expr(writer, pair.y, kind);
            } else {
                var cons_expr = expr;
                while (@as(ExprKind, cons_expr.value) == .Cons) {
                    try self.print_expr(writer, cons_expr.value.Cons.x, kind);
                    const next_cons_expr = cons_expr.value.Cons.y;
                    if (next_cons_expr.is_true()) {
                        if (@as(ExprKind, next_cons_expr.value) != .Cons) {
                            _ = try writer.write(" . ");
                            try self.print_expr(writer, next_cons_expr, kind);
                            break;
                        }
                        _ = try writer.write(" ");
                    }
                    cons_expr = next_cons_expr;
                }
            }
            _ = try writer.write(")");
        },
        .Closure => try self.print_expr(writer, expr.get_cons(), kind),
        .Primitive => try writer.print("#{s}",
            .{&(expr.primitive_name(self) catch "(could not get primitive name)")}),
        .Nil => if (repr) {
            _ = try writer.write("nil");
        },
    }
}

pub fn print_expr_to_string(self: *Self, expr: *Expr, kind: PrintKind) Error![]const u8 {
    var string_writer = utils.StringWriter.init(self.allocator);
    defer string_writer.deinit();
    try self.print_expr(string_writer.writer(), expr, kind);
    return string_writer.get();
}

test "print_expr" {
    var ta = utils.TestAlloc{};
    defer ta.deinit(.Panic);
    errdefer ta.deinit(.NoPanic);
    const alloc = ta.alloc();
    var tl = try Self.new(alloc);
    defer tl.done();

    var list = try tl.make_list([_]*Expr{
        try tl.make_int(30),
        tl.nil,
        try tl.make_int(-40),
        try tl.make_list([_]*Expr{
            try tl.make_string("Hello\n", .NoCopy),
        }),
    });

    {
        const str = try tl.print_expr_to_string(list, .Repr);
        defer alloc.free(str);
        try std.testing.expectEqualStrings("(30 nil -40 (\"Hello\\n\"))", str);
    }

    {
        const str = try tl.print_expr_to_string(list, .RawRepr);
        defer alloc.free(str);
        try std.testing.expectEqualStrings(
            "(30 . (nil . (-40 . ((\"Hello\\n\" . nil) . nil))))", str);
    }

    {
        const str = try tl.print_expr_to_string(list, .Display);
        defer alloc.free(str);
        // TODO: Better way to display list?
        try std.testing.expectEqualStrings("(30  -40 (Hello\n))", str);
    }
}

const TlExprPair = struct {
    tl: *Self,
    expr: *Expr,
};

fn fmt_expr_impl(pair: TlExprPair, comptime fmt: []const u8, options: std.fmt.FormatOptions,
        writer: anytype) !void {
    _ = options;
    try pair.tl.print_expr(writer, pair.expr,
        if (fmt.len == 0 or comptime std.mem.eql(u8, fmt, "display")) .Display
        else if (comptime std.mem.eql(u8, fmt, "repr")) .Repr);
}

pub fn fmt_expr(self: *Self, expr: *Expr) std.fmt.Formatter(fmt_expr_impl) {
    return .{.data = .{.tl = self, .expr = expr}};
}

fn expect_expr(self: *Self, expected: *Expr, result: *Expr) !void {
    const are_equal = expected.eq(result);
    if (!are_equal) {
        std.debug.print(
            \\
            \\Expected this expression: =====================================================
            \\{repr}
            \\But found this: ===============================================================
            \\{repr}
            \\===============================================================================
            \\
            , .{self.fmt_expr(expected), self.fmt_expr(result)});
    }
    try std.testing.expect(are_equal);
}

// eval and Helpers ===========================================================

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
    var tl = try Self.new(ta.alloc());
    defer tl.done();

    const tru = try tl.get_atom("#t");
    try tl.expect_expr(tru, try tl.assoc(tru, tl.global_env));
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
            break :blk self.got_lisp_error("value passed to apply isn't callable", callable);
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
    var tl = try Self.new(ta.alloc());
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

fn get_token(self: *Self) Error!?Token {
    if (self.input) |input| {
        while (self.pos < input.len) {
            switch (input[self.pos]) {
                '\n' => {
                    self.lineno += 1;
                    self.pos += 1;
                },
                ' ', '\t' => {
                    self.pos += 1;
                },
                ';' => {
                    while (self.pos < input.len and input[self.pos] != '\n') {
                        self.pos += 1;
                    }
                },
                else => break,
            }
        }
        var token: ?Token = null;
        var start: usize = self.pos;
        var first = true;
        while (self.pos < input.len) {
            var special_token: ?Token = null;
            switch (input[self.pos]) {
                '(' => special_token = Token.Open,
                ')' => special_token = Token.Close,
                '\'' => special_token = Token.Quote,
                '.' => special_token = Token.Dot,
                ' ', '\n', '\t' => {
                    break;
                },
                '"' => {
                    if (first) {
                        start = self.pos;
                        self.pos += 1; // starting quote
                        var escaped = false;
                        while (true) {
                            if (self.pos >= input.len) return Error.LispInvalidSyntax;
                            const c = input[self.pos];
                            switch (c) {
                                '\n' => return Error.LispInvalidSyntax,
                                '\\' => escaped = !escaped,
                                '"' => if (escaped) {
                                    escaped = false;
                                } else {
                                    break;
                                },
                                else => if (escaped) {
                                    escaped = false;
                                },
                            }
                            self.pos += 1;
                        }
                        self.pos += 1; // ending quote
                        token = Token{.String = input[start..self.pos]};
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
        const str = input[start..self.pos];
        if (token == null and str.len > 0) {
            const int_value: ?IntType = std.fmt.parseInt(IntType, str, 0) catch null;
            token = if (int_value) |iv| Token{.IntValue = iv} else Token{.Atom = str};
        }
        return token;
    }
    return null;
}

fn must_get_token(self: *Self) Error!Token {
    return (try self.get_token()) orelse self.print_zig_error(Error.LispUnexpectedEndOfInput);
}

fn print_error(self: *Self, reason: []const u8, expr: ?*Expr) void {
    if (self.error_out) |eo| {
        eo.print("ERROR on line {}", .{self.lineno}) catch unreachable;
        if (self.input_name) |in| {
            eo.print(" of {s}", .{in}) catch unreachable;
        }
        eo.print(": {s}\n", .{reason}) catch unreachable;
        if (expr) |e| {
            eo.print("Problem is with: {repr}\n", .{self.fmt_expr(e)}) catch unreachable;
        }
    }
}

fn print_zig_error(self: *Self, error_value: Error) Error {
    self.print_error(@errorName(error_value), null);
    return error_value;
}

test "tokenize" {
    var ta = utils.TestAlloc{};
    defer ta.deinit(.Panic);
    errdefer ta.deinit(.NoPanic);
    var tl = Self.new_barren(ta.alloc());
    defer tl.done();

    tl.input = "  (x 1( y \"hello\\\"\" ' ; This is a comment\n(24 . ab))c) ; comment at end";

    try std.testing.expect((try tl.must_get_token()).eq(Token.Open));
    try std.testing.expect((try tl.must_get_token()).eq(Token{.Atom = "x"}));
    try std.testing.expect((try tl.must_get_token()).eq(Token{.IntValue = 1}));
    try std.testing.expect((try tl.must_get_token()).eq(Token.Open));
    try std.testing.expect((try tl.must_get_token()).eq(Token{.Atom = "y"}));
    try std.testing.expect((try tl.must_get_token()).eq(Token{.String = "\"hello\\\"\""}));
    try std.testing.expect((try tl.must_get_token()).eq(Token.Quote));
    try std.testing.expect((try tl.must_get_token()).eq(Token.Open));
    try std.testing.expect((try tl.must_get_token()).eq(Token{.IntValue = 24}));
    try std.testing.expect((try tl.must_get_token()).eq(Token.Dot));
    try std.testing.expect((try tl.must_get_token()).eq(Token{.Atom = "ab"}));
    try std.testing.expect((try tl.must_get_token()).eq(Token.Close));
    try std.testing.expect((try tl.must_get_token()).eq(Token.Close));
    try std.testing.expect((try tl.must_get_token()).eq(Token{.Atom = "c"}));
    try std.testing.expect((try tl.must_get_token()).eq(Token.Close));
    try std.testing.expectError(Error.LispUnexpectedEndOfInput, tl.must_get_token());
}

fn parse_list(self: *Self) Error!*Expr {
    const token = try self.must_get_token();
    return switch (token) {
        TokenKind.Close => self.nil,
        TokenKind.Dot => dot_blk: {
            const second = self.must_parse_token();
            const expected_close = try self.must_get_token();
            if (@as(TokenKind, expected_close) != .Close) {
                return self.print_zig_error(Error.LispInvalidParens);
            }
            break :dot_blk second;
        },
        else => else_blk: {
            const first = try self.parse_i(token);
            const second = try self.parse_list();
            break :else_blk try self.cons(first, second);
        }
    };
}

fn parse_quote(self: *Self) Error!*Expr {
    return try self.cons(try self.get_atom("quote"),
        try self.cons(try self.must_parse_token(), self.nil));
}

fn parse_i(self: *Self, token: Token) Error!*Expr {
    return switch (token) {
        TokenKind.Open => self.parse_list(),
        TokenKind.Quote => self.parse_quote(),
        TokenKind.Atom => |name| try self.make_atom(name, .Copy),
        TokenKind.IntValue => |value| try self.make_int(value),
        TokenKind.String => |literal| blk: {
            var buf = std.ArrayList(u8).init(self.allocator);
            defer buf.deinit();
            switch (try std.zig.string_literal.parseAppend(&buf, literal)) {
                .success => {},
                else => return Error.LispInvalidSyntax,
            }
            break :blk try self.make_string(buf.toOwnedSlice(), .PassOwnership);
        },
        TokenKind.Close => self.print_zig_error(Error.LispInvalidParens),
        TokenKind.Dot => self.print_zig_error(Error.LispInvalidSyntax),
    };
}

fn must_parse_token(self: *Self) Error!*Expr {
    return self.parse_i(try self.must_get_token());
}

fn parse_tokenizer(self: *Self) Error!?*Expr {
    var rv: ?*Expr = null;
    if (try self.get_token()) |t| {
        defer _ = self.collect(.Unused);
        rv = try self.eval(try self.parse_i(t), self.global_env);
        self.parse_return = rv;
    } else if (self.parse_return != null) {
        self.parse_return = null;
        _ = self.collect(.Unused);
    }
    return rv;
}

fn parse_str(self: *Self, input: []const u8) Error!?*Expr {
    self.set_input(input, null);
    return self.parse_tokenizer();
}

test "parse_str" {
    var ta = utils.TestAlloc{};
    defer ta.deinit(.Panic);
    errdefer ta.deinit(.NoPanic);
    var tl = try Self.new(ta.alloc());
    defer tl.done();

    const n = try tl.keep_expr(try tl.make_int(6));
    try tl.expect_expr(n, (try tl.parse_str("(+ 1 2 3)")).?);
    try std.testing.expectEqualStrings("Hello", (try tl.parse_str("\"Hello\"")).?.get_string().?);
}

pub fn parse_input(self: *Self) Error!?*Expr {
    var rv: ?*Expr = null;
    rv = try self.parse_tokenizer();
    return rv;
}

pub fn parse_all_input(self: *Self, input: []const u8, input_name: ?[]const u8) Error!void {
    self.set_input(input, input_name);
    if (utils.starts_with(input, "#!")) {
        // Skip over shebang line
        while (true) {
            self.pos += 1;
            if (self.pos >= input.len) break;
            if (input[self.pos] == '\n') {
                self.pos += 1;
                break;
            }
        }
    }
    while (try self.parse_input()) |e| {
        _ = e;
    }
}

test "parse_all_input" {
    var ta = utils.TestAlloc{};
    defer ta.deinit(.Panic);
    errdefer ta.deinit(.NoPanic);
    var tl = try Self.new(ta.alloc());
    defer tl.done();

    try tl.parse_all_input("#!", null);

    try tl.parse_all_input(
        \\#!This isn't lisp
        \\(define a 5)
        \\(define b 3)
        \\(define func (lambda (x y) (+ (* x y) y)))
        , null
    );

    // Make sure both lists and pairs are parsed correctly
    try tl.parse_all_input(
        "(define begin (lambda (x . args) (if args (begin . args) x)))\n", null);

    const n = try tl.keep_expr(try tl.make_int(18));
    try tl.expect_expr(n, (try tl.parse_str("(func a b)")).?);
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
    var tl = try Self.new(ta.alloc());
    defer tl.done();

    const custom = [_]GenPrimitive{
        .{.name = "cp", .zig_func = custom_primitive},
    };
    var custom_primitives: [custom.len]Primitive = undefined;
    try tl.populate_extra_primitives(custom[0..], custom_primitives[0..]);

    const n = try tl.keep_expr(try tl.make_int(10));
    try tl.expect_expr(n, (try tl.parse_str("(cp 20)")).?);
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
                const kind = @as(ExprKind, arg.value);
                if (ek != kind) {
                    return self.got_lisp_error("inconsistent arg types in +, expected int", arg);
                }
            } else {
                expr_kind = @as(ExprKind, arg.value);
            }
            switch (@as(ExprKind, arg.value)) {
                .String => total_string_len += arg.get_string().?.len,
                .Int => {},
                else => {
                    return self.got_lisp_error("inconsistent arg types in +, expected int", arg);
                }
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
                    const s = arg.get_string().?;
                    for (s) |c| {
                        result[got] = c;
                        got += 1;
                    }
                }
                return self.make_string(result, .PassOwnership);
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
    var tl = try Self.new(ta.alloc());
    defer tl.done();

    const n = try tl.keep_expr(try tl.make_int(6));
    try tl.expect_expr(n, (try tl.parse_str("(+ 1 2 3)")).?);
    try std.testing.expectEqualStrings("Hello world", (
        try tl.parse_str("(+ \"Hello\" \" world\")")).?.get_string().?);
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
    var tl = try Self.new(ta.alloc());
    defer tl.done();

    const n = try tl.keep_expr(try tl.make_int(3));
    try tl.expect_expr(n, (try tl.parse_str("(cond ((eq? 'a 'b) 1) ((< 2 1) 2) (#t 3))")).?);
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
    var tl = try Self.new(ta.alloc());
    defer tl.done();

    const n = try tl.keep_expr(try tl.make_int(1));
    try tl.expect_expr(n, (try tl.parse_str("(if (eq? 'a 'a) 1 2)")).?);
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
    var tl = try Self.new(ta.alloc());
    defer tl.done();

    const n = try tl.keep_expr(try tl.make_int(12));
    try tl.expect_expr(n, (try tl.parse_str("(let* (a 3) (b (* a a)) (+ a b))")).?);
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
    var tl = try Self.new(ta.alloc());
    defer tl.done();

    const n = try tl.keep_expr(try tl.make_int(9));
    try tl.expect_expr(n, (try tl.parse_str("((lambda (x) (* x x)) 3)")).?);
}

// (define var expr)
pub fn define(self: *Self, env: *Expr, atom: *Expr, expr: *Expr) Error!*Expr {
    var use_atom = atom;
    if (@as(ExprKind, use_atom.value) == .String) {
        use_atom = try self.make_atom(use_atom.get_string().?, .Copy);
    }
    if (@as(ExprKind, use_atom.value) != .Atom) {
        return self.got_lisp_error("define got non-atom", use_atom);
    }
    self.global_env = try self.tack_pair_to_list(use_atom, try self.eval(expr, env), env);
    return use_atom;
}

test "define" {
    var ta = utils.TestAlloc{};
    defer ta.deinit(.Panic);
    errdefer ta.deinit(.NoPanic);
    var tl = try Self.new(ta.alloc());
    defer tl.done();

    _ = try tl.parse_str("(define x 1)");
    _ = try tl.parse_str("(define \"y\" 3)");
    const n = try tl.keep_expr(try tl.make_int(4));
    try tl.expect_expr(n, (try tl.parse_str("(+ x y)")).?);
}

pub fn print(self: *Self, args: *Expr) Error!*Expr {
    if (self.out) |out| {
        var check_iter = args;
        while (try self.next_in_list_iter(&check_iter)) |arg| {
            try self.print_expr(out, arg, .Display);
        }
    }
    return self.nil;
}

// (progn statement ... return_value)
// Eval every statement in args, discarding the result from each except the
// last one, which is returned.
pub fn progn(self: *Self, init_env: *Expr, statements: *Expr) Error!*Expr {
    var env = init_env;
    var result = self.nil;
    if (statements != self.err) { // TODO: Handle getting an error better here and elsewhere
        var iter = statements;
        while (try self.next_in_list_iter(&iter)) |statement| {
            result = try self.eval(statement, env);
            env = self.global_env;
        }
    }
    return result;
}

test "progn" {
    var ttl = TestTl{};
    try ttl.init();
    errdefer ttl.ta.deinit(.NoPanic);
    defer ttl.done();

    try ttl.tl.expect_expr(ttl.tl.nil, (try ttl.tl.parse_str("(progn ())")).?);
    try ttl.tl.parse_all_input(
        \\(define z (progn
        \\  (define x 1)
        \\  (define y (+ x 1))
        \\  ((lambda () y))
        \\))
        , null
    );
    const two = try ttl.tl.keep_expr(try ttl.tl.make_int(2));
    try ttl.tl.expect_expr(two, (try ttl.tl.parse_str("z")).?);
}
