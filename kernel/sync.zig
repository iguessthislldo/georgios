// Synchronization Interfaces

const std = @import("std");

const kernel = @import("kernel.zig");
const print = @import("print.zig");
const threading = @import("threading.zig");
const List = @import("list.zig").List;
const memory = @import("memory.zig");

pub const Error = memory.MemoryError;

pub const Lock = struct {
    locked: bool = false,

    /// Try to set locked to true if it's false. Return true if we couldn't do that.
    pub fn lock(self: *Lock) bool {
        return @cmpxchgStrong(bool, &self.locked, false, true, .Acquire, .Monotonic) != null;
    }

    /// Try to acquire lock forever
    pub fn spin_lock(self: *Lock) void {
        while (@cmpxchgWeak(bool, &self.locked, false, true, .Acquire, .Monotonic) != null) {}
    }

    pub fn unlock(self: *Lock) void {
        if (@cmpxchgStrong(bool, &self.locked, true, false, .Release, .Monotonic) != null) {
            @panic("Lock.unlock: Already unlocked");
        }
    }
};

test "Lock" {
    var lock = Lock{};
    try std.testing.expect(!lock.lock());
    try std.testing.expect(lock.lock());
    lock.unlock();
    try std.testing.expect(!lock.lock());
    try std.testing.expect(lock.lock());
    lock.unlock();
    lock.spin_lock();
    try std.testing.expect(lock.lock());
    lock.unlock();
}

pub fn Semaphore(comptime Type: type) type {
    return struct {
        const Self = @This();

        lock: Lock = .{},
        value: Type = 1,
        queue: List(threading.Thread.Id) = undefined,

        pub fn init(self: *Self) void {
            self.queue = .{.alloc = kernel.memory.small_alloc};
        }

        pub fn wait(self: *Self) Error!void {
            self.lock.spin_lock();
            if (self.value == 0) {
                const thread = kernel.threading_manager.current_thread.?;
                try self.queue.push_back(thread.id);
                thread.state = .Wait;
                self.lock.unlock();
                kernel.threading_manager.yield();
            } else {
                self.value -= 1;
                self.lock.unlock();
            }
        }

        pub fn signal(self: *Self) Error!void {
            self.lock.spin_lock();
            self.value += 1;
            // TODO: Threads that exit with signalling should be done by kernel.
            while (try self.queue.pop_front()) |tid| {
                if (kernel.threading_manager.thread_list.find(tid)) |thread| {
                    thread.state = .Run;
                    break;
                }
            }
            self.lock.unlock();
        }
    };
}

var system_test_lock_1 = Lock{.locked = true};
var system_test_lock_2 = Lock{};
var system_test_semaphore = Semaphore(u8){};

pub fn system_test_thread_a() void {
    print.string("system_test_thread_a started\n");

    if (system_test_lock_2.lock()) @panic("system_test_lock_2 failed to lock lock 2");
    system_test_lock_1.spin_lock();
    print.string("system_test_thread_a got lock 1, getting semaphore, freeing lock 2...\n");
    system_test_lock_2.unlock();
    system_test_lock_1.unlock();

    system_test_semaphore.wait()
        catch @panic("system_test_thread_a system_test_semaphore.wait()");

    print.string("system_test_thread_a got semaphore\n");

    print.string("system_test_thread_a finished\n");
}

pub fn system_test_thread_b() void {
    print.string("system_test_thread_b started, unlocking lock 1 and waiting on lock 2\n");

    system_test_semaphore.wait()
        catch @panic("system_test_thread_b system_test_semaphore.wait()");

    system_test_lock_1.unlock();
    system_test_lock_2.spin_lock();
    print.string("system_test_thread_b got lock 2, releasing semaphore\n");
    system_test_lock_2.unlock();

    system_test_semaphore.signal()
        catch @panic("system_test_thread_b system_test_semaphore.signal()");

    print.string("system_test_thread_b finished\n");
}

pub fn system_tests() !void {
    system_test_semaphore.init();

    var thread_a = threading.Thread{.kernel_mode = true};
    try thread_a.init(false);
    thread_a.entry = @ptrToInt(system_test_thread_a);

    var thread_b = threading.Thread{.kernel_mode = true};
    try thread_b.init(false);
    thread_b.entry = @ptrToInt(system_test_thread_b);

    try kernel.threading_manager.insert_thread(&thread_a);
    try kernel.threading_manager.insert_thread(&thread_b);

    kernel.threading_manager.wait_for_thread(thread_a.id);
    kernel.threading_manager.wait_for_thread(thread_b.id);
}
