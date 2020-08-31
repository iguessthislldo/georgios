// Executable and Linkable Format (ELF)
//
// File Format for Code
//
// For Reference See:
//   ELF Spec: http://refspecs.linuxbase.org/elf/elf.pdf
//   ELF Wikipedia Page: https://en.wikipedia.org/wiki/Executable_and_Linkable_Format
//   ELF on OSDev Wiki: https://wiki.osdev.org/ELF
//   man elf

const io = @import("io.zig");
const util = @import("util.zig");
const print = @import("print.zig");

pub const Error = error {
    InvalidElfFile,
    InvalidElfObjectType,
    InvalidElfPlatform,
};

// TODO: Create Seperate 32 and 64 bit Versions ([ui]size -> [ui]32, [ui]64)
const Section = packed struct {
    name_index: u32, // sh_name
    section_type: u32, // sh_type
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
const Header = packed struct {
    const Magic = [4]u8;
    const expected_magic: Magic = [_]u8 {0x7f, 'E', 'L', 'F'};

    pub const Class = packed enum(u8) {
        Invalid = 0, // ELFCLASSNONE
        Is32 = 1, // ELFCLASS32
        Is64 = 2, // ELFCLASS64
    };

    pub const Data = packed enum(u8) {
        Invalid = 0, // ELFDATANONE
        Little = 1, // ELFDATA2LSB
        Big = 2, // ELFDATA2MSB
    };

    pub const HeaderVersion = packed enum(u8) {
        Invalid = 0, // EV_NONE
        Current = 1, // EV_CURRENT
    };

    pub const ObjectType = packed enum(u16) {
        None = 0, // ET_NONE
        Relocatable = 1, // ET_REL
        Executable = 2, // ET_EXEC
        Shared = 3, // ET_DYN
        CoreDump = 4, // ET_CORE
    };

    pub const Machine = packed enum(u16) {
        None = 0x00, // ET_NONE
        X86_32 = 0x03, // ET_386
        X86_64 = 0x3e,
        Arm32  = 0x28,
        Arm64 = 0xb7,
        RiscV = 0xf3,
        // There are others, but I'm not going to put them in.
    };

    pub const ObjectVersion = packed enum(u32) {
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
            !util.memory_compare(self.magic, expected_magic) or
            !util.valid_enum(Class, self.class) or
            self.class == .Invalid or
            !util.valid_enum(Data, self.data) or
            self.data == .Invalid or
            !util.valid_enum(HeaderVersion, self.header_version) or
            self.header_version == .Invalid or
            !util.valid_enum(ObjectVersion, self.object_version) or
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
    header: Header,
    sections: [16]Section, // TODO: Alloc Them Instead

    pub fn from_file(file: *io.File) !Object {
        var object: Object = undefined;

        // Read Header
        _ = try file.read(util.to_bytes(&object.header));
        print.format("Header Size: {}\n", usize(@sizeOf(Header)));
        try object.header.verify_executable();

        // Read Sections
        print.format("Section Count: {}\n", object.header.section_header_entry_count);
        _ = try file.seek(@intCast(isize, object.header.section_header_offset), .FromStart);
        const section_table_size =
            @intCast(usize, object.header.section_header_entry_count) *
            @intCast(usize, object.header.section_header_entry_size);
        const valid_sections = util.to_bytes(&object.sections)[0..section_table_size];
        _ = try file.read(valid_sections);
        for (object.sections[0..object.header.section_header_entry_count]) |*section| {
            print.format("section: type: {} offset: {:x} size: {:x}\n",
                section.section_type, @bitCast(usize, section.offset), section.size);
        }

        return object;
    }
};
