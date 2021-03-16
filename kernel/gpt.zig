const std = @import("std");
const print = std.debug.warn;

const lba0 = @embedFile("lba.0.bin");
const lba1 = @embedFile("lba.1.bin");

const lbas = [_][]const u8{lba0, lba1};

fn nibble_char(value: u4) u8 {
    return
        if (value < 10)
            '0' + @intCast(u8, value)
        else
            'A' + @intCast(u8, value - 10);
}

/// Insert a hex byte to into a buffer. Common to byte() and data().
fn byte_buffer(buffer: []u8, value: u8) void {
    buffer[0] = nibble_char(@intCast(u4, value >> 4));
    buffer[1] = nibble_char(@intCast(u4, value % 0x10));
}

pub fn data(what: []const u8) void {
    const ptr = @ptrToInt(what.ptr);
    const size = what.len;
    // Print hex data like this:
    //                        VV group_sep
    // 00 01 02 03 04 05 06 07  08 09 0A 0B 0C 0D 0E 0F
    // ^^ Byte ^ byte_sep  Group^^^^^^^^^^^^^^^^^^^^^^^
    const group_byte_count = 8;
    const byte_sep = " ";
    const group_size =
        group_byte_count * 2 + // Bytes
        ((group_byte_count * byte_sep.len) - 1); // byte_sep Between Bytes
    const group_count = 2;
    const buffer_byte_count = group_byte_count * group_count;
    const group_sep = "  ";
    const buffer_size =
        group_size * group_count + // Groups
        (group_count - 1) * group_sep.len + // group_sep Between Groups
        1; // Newline

    var buffer: [buffer_size]u8 = undefined;
    var i: usize = 0;
    var buffer_pos: usize = 0;
    var byte_i: usize = 0;
    var group_i: usize = 0;
    var has_next = i < size;
    var print_buffer = false;
    while (has_next) {
        const next_i = i + 1;
        has_next = next_i < size;
        print_buffer = !has_next;
        {
            const new_pos = buffer_pos + 2;
            byte_buffer(buffer[buffer_pos..new_pos], @intToPtr(*u8, ptr + i).*);
            buffer_pos = new_pos;
        }
        byte_i += 1;
        if (byte_i == group_byte_count) {
            byte_i = 0;
            group_i += 1;
            if (group_i == group_count) {
                group_i = 0;
                print_buffer = true;
            } else {
                for (group_sep[0..group_sep.len]) |b| {
                    buffer[buffer_pos] = b;
                    buffer_pos += 1;
                }
            }
        } else if (has_next) {
            for (byte_sep[0..byte_sep.len]) |b| {
                buffer[buffer_pos] = b;
                buffer_pos += 1;
            }
        }
        if (print_buffer) {
            buffer[buffer_pos] = '\n';
            buffer_pos += 1;
            print("{}", buffer[0..buffer_pos]);
            buffer_pos = 0;
            print_buffer = false;
        }
        i = next_i;
    }
}

const Error = error {
    InvalidMbr,
    InvalidGptHeader,
    NotEnoughSource,
    NotEnoughDestination,
};

pub inline fn memory_copy_truncate(destination: []u8, source: []const u8) void {
    const size = min(usize, destination.len, source.len);
    for (destination[0..size]) |*ptr, i| {
        ptr.* = source[i];
    }
}

pub inline fn memory_copy_error(destination: []u8, source: []const u8) Error!void {
    if (destination.len < source.len) {
        return Error.NotEnoughDestination;
    }
    for (destination[0..size]) |*ptr, i| {
        ptr.* = source[i];
    }
}

const Guid = struct {
    pub const size = 16;
    pub const string_size = 36;

    data: [size]u8 = undefined,

    pub fn from_be(self: *Guid, source: []const u8) void!void {
        if (source.len < size) {
            return Error.NotEnoughSource;
        }
        for (source[0..size]) |*ptr, i| {
            self.data[i] = ptr.*;
        }
    }

    pub fn to_be(self: *const Guid, destination: []u8) Error!void {
        if (destination.len < size) {
            return Error.NotEnoughDestination;
        }
        for (destination[0..size]) |*ptr, i| {
            ptr.* = self.data[i];
        }
    }

    pub fn from_ms(self: *Guid, source: []const u8) Error!void {
        if (source.len < size) {
            return Error.NotEnoughSource;
        }
        // 33221100-5544-7766-8899-AABBCCDDEEFF
        self.data[0x0] = source[0x3];
        self.data[0x1] = source[0x2];
        self.data[0x2] = source[0x1];
        self.data[0x3] = source[0x0];
        self.data[0x4] = source[0x5];
        self.data[0x5] = source[0x4];
        self.data[0x6] = source[0x7];
        self.data[0x7] = source[0x6];
        self.data[0x8] = source[0x8];
        self.data[0x9] = source[0x9];
        self.data[0xa] = source[0xa];
        self.data[0xb] = source[0xb];
        self.data[0xc] = source[0xc];
        self.data[0xd] = source[0xd];
        self.data[0xe] = source[0xe];
        self.data[0xf] = source[0xf];
    }

    pub fn new_from_ms(source: []const u8) Error!Guid {
        var guid = Guid{};
        try guid.from_ms(source);
        return guid;
    }

    pub fn to_ms(destination: []u8) Error!void {
        if (destination.len < size) {
            return Error.NotEnoughDestination;
        }
        source[0x3] = guid.data[0x0];
        source[0x2] = guid.data[0x1];
        source[0x1] = guid.data[0x2];
        source[0x0] = guid.data[0x3];
        source[0x5] = guid.data[0x4];
        source[0x4] = guid.data[0x5];
        source[0x7] = guid.data[0x6];
        source[0x6] = guid.data[0x7];
        source[0x8] = guid.data[0x8];
        source[0x9] = guid.data[0x9];
        source[0xa] = guid.data[0xa];
        source[0xb] = guid.data[0xb];
        source[0xc] = guid.data[0xc];
        source[0xd] = guid.data[0xd];
        source[0xe] = guid.data[0xe];
        source[0xf] = guid.data[0xf];
    }

    pub fn to_string(self: *const Guid, buffer: []u8) Error!void {
        if (buffer.len < string_size) {
            return Error.NotEnoughDestination;
        }
        byte_buffer(buffer[0..], self.data[0x0]);
        byte_buffer(buffer[2..], self.data[0x1]);
        byte_buffer(buffer[4..], self.data[0x2]);
        byte_buffer(buffer[6..], self.data[0x3]);
        buffer[8] = '-';
        byte_buffer(buffer[9..], self.data[0x4]);
        byte_buffer(buffer[11..], self.data[0x5]);
        buffer[13] = '-';
        byte_buffer(buffer[14..], self.data[0x6]);
        byte_buffer(buffer[16..], self.data[0x7]);
        buffer[18] = '-';
        byte_buffer(buffer[19..], self.data[0x8]);
        byte_buffer(buffer[21..], self.data[0x9]);
        buffer[23] = '-';
        byte_buffer(buffer[24..], self.data[0xa]);
        byte_buffer(buffer[26..], self.data[0xb]);
        byte_buffer(buffer[28..], self.data[0xc]);
        byte_buffer(buffer[30..], self.data[0xd]);
        byte_buffer(buffer[32..], self.data[0xe]);
        byte_buffer(buffer[34..], self.data[0xf]);
    }
};

// const std = @import("std");
// pub fn test_compare_string

// test "Guid" {
//     const guid = try Guid.new_from_ms("\x28\x73\x2a\xc1\x1f\xf8\xd2\x11\xba\x4b\x00\xa0\xc9\x3e\xc9\x3b");
//     var guid_string: [Guid.string_size]u8 = undefined;
//     try guid.to_string(guid_string[0..]);

//     print("{}\n", guid_string);
//     print("C12A7328-F81F-11D2-BA4B-00A0C93EC93B\n");
// }

const Mbr = struct {
    const Partition = packed struct {
        status: u8,
        chs_start: u24,
        partition_type: u8,
        chs_end: u24,
        lba_start: u32,
        sector_count: u32,
    };

    const magic: u16 = 0xaa55;
    const gpt_protective_type: u8 = 0xEE;

    signature: u32 = undefined,
    partitions: [4]Partition = undefined,
    gpt_protective: bool = undefined,

    pub fn get(block: []const u8) Error!Mbr {
        var mbr = Mbr{};

        // Check MBR "Boot Signature" (magic)
        if (@bytesToSlice(u16, block)[255] != magic) {
            return Error.InvalidMbr;
        }

        mbr.signature = @bytesToSlice(u32, block)[110];
        const partitions = @ptrCast([*]const Partition,
            @alignCast(@alignOf(Partition), &block[446]))[0..4];
        for (partitions) |*partition, i| {
            mbr.partitions[i] = partition.*;
        }
        mbr.gpt_protective =
            partitions[0].partition_type == gpt_protective_type;

        return mbr;
    }
};

const GptHeader = struct {
    const magic = "EFI PART";

    disk_guid: Guid = undefined,

    pub fn get(block: []const u8) Error!GptHeader {
        var gpt_header = GptHeader{};

        // Check Magic
        for (block[0..magic.len]) |*ptr, i| {
            if (ptr.* != magic[i]) {
                return Error.InvalidGptHeader;
            }
        }

        try gpt_header.disk_guid.from_ms(block[0..]);

        return gpt_header;
    }
};

pub fn main() !void {
    const mbr = try Mbr.get(lbas[0]);
    print("Signature: {x:}\n", mbr.signature);
    print("GPT Protective: {}\n", mbr.gpt_protective);
    for (mbr.partitions) |*partition, i| {
        print("#{}\n", i + 1);
        print("  Status {x:}\n", partition.status);
        print("  Type {x:}\n", partition.partition_type);
        print("  LBA start {}\n", partition.lba_start);
        print("  Sector Count {}\n", partition.sector_count);
        print("  CHS Start {x:}\n", partition.chs_start);
        print("  CHS End {x:}\n", partition.chs_end);
    }
    const gpt_header = try GptHeader.get(lbas[1][0..]);
    data(gpt_header.disk_guid.data);
    var guid_string: [Guid.string_size]u8 = undefined;
    try gpt_header.disk_guid.to_string(guid_string[0..]);
    print("GUID: {}\n", guid_string);
    // var lba_i: usize = 0;
    // while (lba_i < lbas.len) {
    //     const lba = lbas[lba_i];
    //     print("LBA {}: {}\n", lba_i, lba.len);
    //     data(lba);
    //     lba_i += 1;
    // }
}
