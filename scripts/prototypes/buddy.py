# Based on http://bitsquid.blogspot.com/2015/08/allocation-adventures-3-buddy-allocator.html

import math
from enum import Enum

def align_down(value, by):
    return value & (~by + 1)

def align_up(value, by):
    return align_down(value + by - 1, by)

# Get next power of two if the value is not one.
def pot(value):
    if value >= (1 << 32):
        raise ValueError
    value -= 1
    value |= value >> 1
    value |= value >> 2
    value |= value >> 4
    value |= value >> 8
    value |= value >> 16
    value += 1
    return value

class Memory:
    def __init__(self, size, start = 0):
        self.size = size
        self.start = start
        self.end = start + size
        self.contents = [None] * size

    def get(self, address):
        if address >= self.end:
            raise ValueError("Tried to get invalid address " + str(address))
        value = self.contents[address - self.start]
        if value is None:
            raise ValueError("Tried to get uninitialized address " + str(address))
        return value

    def set(self, address, value):
        if address >= self.end:
            raise ValueError("Tried to set invalid address " + str(address))
        self.contents[address - self.start] = value

    def __repr__(self):
        rv = []
        for value in self.contents:
            if value is None:
                rv.append('.')
            elif value is nil:
                rv.append('N')
            else:
                rv.append(str(value))
        return ' '.join(rv)

nil=(None,)

class BlockStatus(Enum):
    invalid = 0
    split = 1
    free = 2
    used = 3

    def __repr__(self):
        if self == self.invalid:
            return 'I'
        if self == self.split:
            return 'S'
        if self == self.free:
            return 'F'
        if self == self.used:
            return 'U'
        return super().__repr__()

# Example
#
# size = 32
# min_size = 4
#
# Index by Level
#
# 0 |               0               |
# 1 |       0       |       1       |
# 2 |   0   |   1   |   2   |   3   |
# 3 | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
#   |...|...|...|...|...|...|...|...|
#   0   4   8  12  16  20  24  28  32
#
# max_level_block_count = 32 / 4 = 8
# level_count = 4
#
# Unique Id
#
# 0 |               0               |
# 1 |       1       |       2       |
# 2 |   3   |   4   |   5   |   6   |
# 3 | 7 | 8 | 9 | 10| 11| 12| 13| 14|
#   |...|...|...|...|...|...|...|...|
#   0   4   8  12  16  20  24  28  32
#
# unique_block_count = 15

class OutOfMemory(Exception):
    pass

class WrongBlockStatus(Exception):
    pass

class InvalidPointer(Exception):
    pass

class Buddy:
    def __init__(self, start, size):
        self.start = start
        self.size = size
        self.min_size = 4

        self.max_level_block_count = self.size // self.min_size
        self.level_count = int(math.log2(self.max_level_block_count)) + 1
        self.unique_block_count = (1 << self.level_count) - 1

        # Simulated Memory Range to Control
        self.memory = Memory(size, start)

        # Intitialze Free List
        self.free_lists = Memory(self.level_count + 1)
        self.free_lists.set(0, start)
        for i in range(1, self.free_lists.size):
            self.free_lists.set(i, nil)
        self.set_prev_pointer(start, nil)
        self.set_next_pointer(start, nil)

        # Intitialze Block Statuses
        self.block_statuses = [BlockStatus.invalid] * self.unique_block_count
        self.block_statuses[0] = BlockStatus.free

    def get_free_list_pointer(self, address):
        if self.memory.get(address):
            return self.memory.get(address + 1)
        else:
            return nil

    def set_free_list_pointer(self, address, value):
        if value is nil:
            optional_value = 0
        else:
            optional_value = 1
            self.memory.set(address + 1, value)
        self.memory.set(address, optional_value)

    prev_offset = 0

    def get_prev_pointer(self, address):
        return self.get_free_list_pointer(address + self.prev_offset)

    def set_prev_pointer(self, address, value):
        return self.set_free_list_pointer(address + self.prev_offset, value)

    next_offset = 2

    def get_next_pointer(self, address):
        return self.get_free_list_pointer(address + self.next_offset)

    def set_next_pointer(self, address, value):
        return self.set_free_list_pointer(address + self.next_offset, value)

    def level_to_block_size(self, level):
        return self.size // (1 << level)

    def block_size_to_level(self, size):
        return self.level_count + 1 - int(math.log2(size))

    @staticmethod
    def unique_id(level, index):
        return (1 << level) + index - 1

    def get_unique_id(self, level, index, expected_status):
        unique_id = self.unique_id(level, index)
        status = self.block_statuses[unique_id]
        if status != expected_status:
            raise WrongBlockStatus(
                "unique id {} (level {}, index {}) was expected to be {}, not {}".format(
                    unique_id, level, index, expected_status, status))
        return unique_id

    def get_index(self, level, address):
        return (address - self.start) // self.level_to_block_size(level)

    def get_pointer(self, level, index):
        return index * self.level_to_block_size(level) + self.start

    @staticmethod
    def get_buddy_index(index):
        return index - 1 if index % 2 else index + 1

    # Remove block from double linked list
    def remove_block(self, level, ptr):
        old_prev = self.get_prev_pointer(ptr)
        old_next = self.get_next_pointer(ptr)
        if old_prev is nil:
            self.free_lists.set(level, old_next)
        else:
            self.set_next_pointer(old_prev, old_next)
        if old_next is not nil:
            self.set_prev_pointer(old_next, old_prev)

    def split(self, level, index):
        print('     - split', level, index)
        this_unique_id = self.get_unique_id(level, index, BlockStatus.free)

        this_ptr = self.get_pointer(level, index)
        new_level = level + 1
        new_index = index * 2
        buddy_index = new_index + 1
        buddy_ptr = self.get_pointer(new_level, buddy_index)

        self.remove_block(level, this_ptr)

        # Update New Pointer to This
        buddy_next = self.free_lists.get(new_level)
        self.free_lists.set(new_level, this_ptr)

        # Set Our Pointers
        self.set_prev_pointer(this_ptr, nil)
        self.set_next_pointer(this_ptr, buddy_ptr)
        self.set_prev_pointer(buddy_ptr, this_ptr)
        self.set_next_pointer(buddy_ptr, buddy_next)

        # Update Pointers to Buddy
        if buddy_next is not nil:
            self.set_prev_pointer(buddy_next, buddy_ptr)

        # Update Statuses
        self.block_statuses[this_unique_id] = BlockStatus.split
        self.block_statuses[self.unique_id(new_level, new_index)] = BlockStatus.free
        self.block_statuses[self.unique_id(new_level, buddy_index)] = BlockStatus.free

    def alloc(self, size):
        if size < self.min_size:
            raise ValueError(
                "Asked for size smaller than what the alloctor supports: " +
                size)
        if size > self.size:
            raise ValueError(
                "Asked for size greater than what the alloctor supports: " +
                size)

        target_size = pot(size)
        target_level = self.block_size_to_level(target_size)
        print(' - alloc(', size, '), Target Size:', target_size, 'Target Level:', target_level)

        # Figure out how many (if any) levels we need to split a block in to
        # get a free block in our target level.
        address = nil
        level = target_level
        while True:
            address = self.free_lists.get(level)
            print('     - split_loop: free list level', level, ':', address)
            if address is nil:
                if level == 0:
                    print('     - split_loop: reached level 0, no room!')
                    raise OutOfMemory()
                level -= 1
            else:
                break

        # If we need to split blocks, do that
        if level != target_level:
            for i in range(level, target_level):
                self.split(i, self.get_index(i, address))
                address = self.free_lists.get(i + 1)
                if address is nil:
                    raise ValueError('nil in split loop!')

        # Reserve it
        self.remove_block(target_level, address)
        index = self.get_index(target_level, address)
        unique_id = self.unique_id(target_level, index)
        self.block_statuses[unique_id] = BlockStatus.used

        print(" - Got", address)
        print(repr(self))
        return address

    def merge(self, level, index):
        if level == 0:
            raise ValueError('merge() was pased level 0')

        print('     - merge', level, index)

        buddy_index = self.get_buddy_index(index)
        new_level = level - 1
        new_index = index // 2

        # Assert existing blocks are free and new/parrent block is split
        this_unique_id = self.get_unique_id(level, index, BlockStatus.free)
        buddy_unique_id = self.get_unique_id(level, buddy_index, BlockStatus.free)
        new_unique_id = self.get_unique_id(new_level, new_index, BlockStatus.split)

        # Remove pointers to the old blocks
        this_ptr = self.get_pointer(level, index)
        buddy_ptr = self.get_pointer(level, buddy_index)
        self.remove_block(level, this_ptr)
        self.remove_block(level, buddy_ptr)

        # Set new pointers to and from the new block
        new_this_ptr = self.get_pointer(new_level, new_index)
        self.set_next_pointer(new_this_ptr, self.free_lists.get(new_level))
        self.free_lists.set(new_level, new_this_ptr)
        self.set_prev_pointer(new_this_ptr, nil)

        # Set New Statuses
        self.block_statuses[this_unique_id] = BlockStatus.invalid
        self.block_statuses[buddy_unique_id] = BlockStatus.invalid
        self.block_statuses[new_unique_id] = BlockStatus.free

    def free(self, address):
        found = False
        print(" - free(", address, ')')
        for level in range(self.level_count - 1, -1, -1):
            index = self.get_index(level, address)
            try:
                unique_id = self.get_unique_id(level, index, BlockStatus.used)
                found = True
                break
            except WrongBlockStatus:
                continue
        if not found:
            raise InvalidPointer()
        print("   - level:", level, "index:", index, "unique id:", unique_id)

        # Insert Block into List and Mark as Free
        next_ptr = self.free_lists.get(level)
        if next_ptr is not nil:
            self.set_prev_pointer(next_ptr, address)
        self.free_lists.set(level, address)
        self.set_prev_pointer(address, nil)
        self.set_next_pointer(address, next_ptr)
        self.block_statuses[unique_id] = BlockStatus.free

        # Merge Until Buddy isn't Free or Level Is 0
        for level in range(level, 0, -1):
            buddy_index = self.get_buddy_index(index)
            buddy_unique_id = self.unique_id(level, buddy_index)
            buddy_status = self.block_statuses[buddy_unique_id]
            print("   - merge level", level, "index", index, "uid", buddy_unique_id,
                "status", buddy_status)
            if buddy_status == BlockStatus.free:
                self.merge(level, index)
                index >>= 1;
            else:
                break
        print(repr(self))

    def __repr__(self):
        return 'free_lists: {}\nmemory: {}\nstatuses: {}'.format(
            repr(self.free_lists),
            repr(self.memory),
            repr(self.block_statuses))

def buddy_test(start):
    try:
        b = Buddy(start, 32)
        print(repr(b))

        b.alloc(4)
        b.alloc(4)
        b.alloc(4)
        b.alloc(4)
        b.alloc(4)
        b.alloc(4)
        b.alloc(4)
        b.alloc(4)

        try:
            b.alloc(4)
            assert(False)
        except OutOfMemory:
            pass

    except:
        print('State At Error:', repr(b))
        raise

    try:
        b = Buddy(start, 32)
        print(repr(b))

        p = b.alloc(4)
        b.free(p)

    except:
        print('State At Error:', repr(b))
        raise

    try:
        b = Buddy(start, 32)
        print(repr(b))

        p1 = b.alloc(8)
        p2 = b.alloc(4)
        p3 = b.alloc(16)
        b.free(p2)
        p4 = b.alloc(8)
        b.free(p3)
        b.free(p4)
        b.free(p1)

    except:
        print('State At Error:', repr(b))
        raise

    try:
        b = Buddy(start, 32)
        print(repr(b))

        p = b.alloc(16)
        b.free(p)
        try:
            b.free(p)
            assert(False)
        except InvalidPointer:
            print('Caught Expected InvalidPointer')

    except:
        print('State At Error:', repr(b))
        raise

buddy_test(0)
buddy_test(1)
buddy_test(7)
buddy_test(8)
buddy_test(127)

try:
    b = Buddy(0, 128)
    print(repr(b))

    b.alloc(64)

except:
    print('State At Error:', repr(b))
    raise
