def bytearr(guid):
    s = guid.replace('-', '')
    return ', '.join(['0x' + s[i] + s[i + 1] for i in range(0, len(s), 2)])

def make_guid(name, guid, f):
    print("pub const {} = Guid{{.data= // {}\n    [_]u8{{{}}}}};".format(
        name, guid, bytearr(guid)), file=f)

guids = [
    ("nil", "00000000-0000-0000-0000-000000000000"),
    ("linux_partition_type", "0fc63daf-8483-4772-8e79-3d69d8477de4"),
]

with open('kernel/constant_guids.zig', 'w') as f:
    print('const Guid = @import("guid.zig");', file=f)
    for (guid, name) in guids:
        make_guid(guid, name, f)
