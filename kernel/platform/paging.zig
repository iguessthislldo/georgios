const kutil = @import("../util.zig");

pub const frame_size = kutil.Ki(4);

const table_count = putil.Ki(1);
const table_size = frame_size * table_count;

inline fn page_is_present(entry: u32) bool {
    return (entry & 1) == 1;
}

inline fn get_page_address(entry: u32) u32 {
    return entry & 0xfffff000;
}

inline fn get_directory_index(address: u32) u32 {
    return (address & 0xffc00000) >> 22;
}

inline fn get_table_index(address: u32) u32 {
    return (address & 0x003ff000) >> 12;
}

inline fn get_page_index(address: u32) u32 {
    return address & 0x00000fff;
}
