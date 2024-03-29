// Executable and Linkable Format (ELF)
//
// File Format for Code
//
// For Reference See:
//   ELF Spec: http://refspecs.linuxbase.org/elf/elf.pdf
//   ELF Wikipedia Page: https://en.wikipedia.org/wiki/Executable_and_Linkable_Format
//   ELF on OSDev Wiki: https://wiki.osdev.org/ELF
//   man elf

const georgios = @import("georgios");
const utils = @import("utils");

const io = @import("io.zig");
const print = @import("print.zig");
const Allocator = @import("memory.zig").Allocator;
const List = @import("list.zig").List;

const debug = false;
const dump_segments = false;

pub const Error = georgios.elf.Error;

// TODO: Create Seperate 32 and 64 bit Versions ([ui]size -> [ui]32, [ui]64)
const SectionHeader = packed struct {
    name_index: u32, // sh_name
    kind: u32, // sh_type
    flags: u32, // sh_flags
    address: usize, // sh_addr
    offset: isize,  // sh_offset
    size: u32, // sh_size
    link: u32, // sh_link
    info: u32, // sh_info
    addralign: u32, // sh_addralign
    entsize: u32, // sh_entsize
};

// TODO: Create Seperate 32 and 64 bit Versions ([ui]size -> [ui]32, [ui]64)
const ProgramHeader = packed struct {
    kind: u32, // p_type
    offset: isize,  // p_offset
    virtual_address: usize, // p_vaddr
    physical_address: usize, // p_paddr
    size_in_file: u32, // p_filesz
    size_in_memory: u32, // p_memsz
    flags: u32, // p_flags
    address_align: u32, // p_align
};

const Magic = [4]u8;
pub const expected_magic: Magic = [_]u8 {0x7f, 'E', 'L', 'F'};

// TODO: Create Seperate 32 and 64 bit Versions ([ui]size -> [ui]32, [ui]64)
const Header = packed struct {
    pub const Class = enum(u8) {
        Invalid = 0, // ELFCLASSNONE
        Is32 = 1, // ELFCLASS32
        Is64 = 2, // ELFCLASS64
    };

    pub const Data = enum(u8) {
        Invalid = 0, // ELFDATANONE
        Little = 1, // ELFDATA2LSB
        Big = 2, // ELFDATA2MSB
    };

    pub const HeaderVersion = enum(u8) {
        Invalid = 0, // EV_NONE
        Current = 1, // EV_CURRENT
    };

    pub const ObjectType = enum(u16) {
        None = 0, // ET_NONE
        Relocatable = 1, // ET_REL
        Executable = 2, // ET_EXEC
        Shared = 3, // ET_DYN
        CoreDump = 4, // ET_CORE
    };

    pub const Machine = enum(u16) {
        None = 0x00, // ET_NONE
        X86_32 = 0x03, // ET_386
        X86_64 = 0x3e,
        Arm32  = 0x28,
        Arm64 = 0xb7,
        RiscV = 0xf3,
        // There are others, but I'm not going to put them in.
    };

    pub const ObjectVersion = enum(u32) {
        Invalid = 0, // EV_NONE
        Current = 1, // EV_CURRENT
    };

    // e_ident
    magic: Magic, // EI_MAG0 - EI_MAG3
    class: Class, // EI_CLASS
    data: Data, // EI_DATA
    header_version: HeaderVersion, // EI_VERSION
    unused_abi_os: u8, // EI_OSABI
    unused_abi_version: u8, //EI_ABIVERSION
    // TODO: This adds 8 to the size of the struct, not 7. Retest with zig master.
    // reserved: [7]u8, // EI_PAD
    reserved0: u8,
    reserved1: u8,
    reserved2: u8,
    reserved3: u8,
    reserved4: u8,
    reserved5: u8,
    reserved6: u8,

    object_type: ObjectType, // e_type
    machine: Machine, // e_machine
    object_version: ObjectVersion, // e_version
    entry: usize, // e_entry
    program_header_offset: isize, // e_phoff
    section_header_offset: isize, // e_shoff
    flags: u32, // e_flags
    header_size: u16, // e_ehsize
    program_header_entry_size: u16, // e_phentsize
    program_header_entry_count: u16, // e_phnum
    section_header_entry_size: u16, // e_shentsize
    section_header_entry_count: u16, // e_shnum
    section_header_string_table_index: u16, // e_shstrndx

    pub fn verify_elf(self: *const Header) Error!void {
        const invalid =
            !utils.memory_compare(self.magic[0..], expected_magic[0..]) or
            !utils.valid_enum(Class, self.class) or
            self.class == .Invalid or
            !utils.valid_enum(Data, self.data) or
            self.data == .Invalid or
            !utils.valid_enum(HeaderVersion, self.header_version) or
            self.header_version == .Invalid or
            !utils.valid_enum(ObjectVersion, self.object_version) or
            self.object_version == .Invalid;
        if (invalid) {
            return Error.InvalidElfFile;
        }
    }

    pub fn verify_compatible(self: *const Header) Error!void {
        // TODO: Make machine depend on platform and other checks
        if (self.machine != .X86_32) {
            return Error.InvalidElfPlatform;
        }
    }

    pub fn verify_executable(self: *const Header) Error!void {
        try self.verify_elf();
        if (self.object_type != .Executable) {
            return Error.InvalidElfObjectType;
        }
        try self.verify_compatible();
    }
};

pub const Object = struct {
    pub const Segment = struct {
        const WhatKind = enum {
            Data,
            UndefinedMemory,
        };
        const What = union(WhatKind) {
            Data: []u8,
            UndefinedMemory: usize,
        };

        what: What = undefined,
        address: usize,

        pub fn teardown(self: *Segment, alloc: *Allocator) !void {
            switch (self.what) {
                .Data => |data| try alloc.free_array(data),
                else => {},
            }
        }

        pub fn size(self: *const Segment) usize {
            return switch (self.what) {
                .Data => |data| data.len,
                .UndefinedMemory => |size| size,
            };
        }
    };
    pub const Segments = List(Segment);

    alloc: *Allocator,
    data_alloc: *Allocator,
    header: Header = undefined,
    section_headers: []SectionHeader = undefined,
    program_headers: []ProgramHeader = undefined,
    segments: Segments = undefined,

    pub fn from_file(alloc: *Allocator, data_alloc: *Allocator, file: *io.File) !Object {
        var object = Object{.alloc = alloc, .data_alloc = data_alloc};
        object.segments = Segments{.alloc = alloc};
        errdefer object.teardown() catch unreachable;

        // Read Header
        _ = try file.read(utils.to_bytes(&object.header));
        if (debug) print.format("Header Size: {}\n", .{@as(usize, @sizeOf(Header))});
        try object.header.verify_executable();

        if (debug) print.format("Entry: {:a}\n", .{@as(usize, @sizeOf(Header))});

        // Read Section Headers
        if (debug) print.format("Section Header Count: {}\n",
            .{object.header.section_header_entry_count});
        {
            _ = try file.seek(
                @intCast(isize, object.header.section_header_offset), .FromStart);
            const count = @intCast(usize, object.header.section_header_entry_count);
            const size = @intCast(usize, object.header.section_header_entry_size);
            const skip = @intCast(isize, size - @sizeOf(SectionHeader));
            object.section_headers = try alloc.alloc_array(SectionHeader, count);
            for (object.section_headers) |*section_header| {
                _ = try file.read(utils.to_bytes(section_header));
                _ = try file.seek(skip, .FromHere);
            }
        }
        for (object.section_headers) |*section_header| {
            if (debug) print.format("section: kind: {} offset: {:x} size: {:x}\n", .{
                section_header.kind,
                @bitCast(usize, section_header.offset),
                section_header.size});
        }

        // Read Program Headers
        if (debug) print.format("Program Header Count: {}\n",
            .{object.header.program_header_entry_count});
        {
            _ = try file.seek(@intCast(isize, object.header.program_header_offset), .FromStart);
            const count = @intCast(usize, object.header.program_header_entry_count);
            const size = @intCast(usize, object.header.program_header_entry_size);
            const skip = @intCast(isize, size - @sizeOf(ProgramHeader));
            object.program_headers = try alloc.alloc_array(ProgramHeader, count);
            for (object.program_headers) |*program_header| {
                _ = try file.read(utils.to_bytes(program_header));
                _ = try file.seek(skip, .FromHere);
            }
        }
        for (object.program_headers) |*program_header| {
            if (debug) print.format("program: kind: {} offset: {:x} " ++
                "size in file: {:x} size in memory: {:x}\n", .{
                program_header.kind,
                @bitCast(usize, program_header.offset),
                program_header.size_in_file,
                program_header.size_in_memory});
            // Read the Program
            // TODO: Remove/Make More Proper?
            if (program_header.kind == 0x1) {
                if (debug) print.format(
                    "segment at {} kind {} file size {} memory size {}\n", .{
                        program_header.virtual_address, program_header.kind,
                        program_header.size_in_file, program_header.size_in_memory,
                        });
                if (program_header.size_in_file > program_header.size_in_memory) {
                    return Error.InvalidElfFile;
                }
                var address = program_header.virtual_address;
                var left = program_header.size_in_memory;
                if (program_header.size_in_file > 0) {
                    const segment = Segment{
                        .address = address,
                        .what = Segment.What{
                            .Data = try data_alloc.alloc_array(u8, program_header.size_in_file)
                        },
                    };
                    _ = try file.seek(@intCast(isize, program_header.offset), .FromStart);
                    _ = try file.read_or_error(segment.what.Data);
                    if (dump_segments) print.dump_bytes(segment.what.Data);
                    try object.segments.push_back(segment);
                    left -= program_header.size_in_file;
                    address += program_header.size_in_file;
                }
                if (left > 0) {
                    try object.segments.push_back(
                        .{.address = address, .what = Segment.What{.UndefinedMemory = left}});
                }
            }
        }
        if (object.segments.len == 0) {
            print.string("No LOADs in ELF!\n");
            return Error.InvalidElfFile;
        }

        return object;
    }

    pub fn teardown(self: *Object) !void {
        try self.alloc.free_array(self.section_headers);
        try self.alloc.free_array(self.program_headers);
        var iter = self.segments.iterator();
        while (iter.next()) |*segment| {
            try segment.teardown(self.data_alloc);
        }
        try self.segments.clear();
    }
};
