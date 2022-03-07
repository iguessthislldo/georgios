import sys

# dump data in gdb using something like
#     dump binary memory FILE ((unsigned*)&WHAT) (((unsigned*)&WHAT)+1024)
#   This dumps the current one:
#     dump binary memory FILE ((unsigned*)($cr3+0xc0000000)) (((unsigned*)($cr3+0xc0000000))+1024)
# And read using:
#     read_paging.py directory FILE
#     read_paging.py table FILE
#     read_paging.py raw FILE

path = sys.argv[2]

data = {}
word_count = 0
with open(path, 'br') as f:
    role = []
    role_start = None
    word = []
    for byte in f.read():
        word.append(byte)
        if len(word) == 4:
            # 44 33 22 11 -> 0x11223344
            real_word = word[0] + (word[1] << 8) + (word[2] << 16) + (word[3] << 24)

            if real_word:
                if not role:
                    role_start = word_count
                role.append(real_word)
            elif role:
                data[role_start] = role
                role = []

            word_count += 1
            word = []

    if role:
        data[role_start] = role

    if word:
        sys.exit("Uneven ammount of bytes!")

def common_flags(value):
    what = []

    if value & (1 << 1):
        what.append("Writable")

    if value & (1 << 2):
        what.append("User")
    else:
        what.append("Non-user")

    if value & (1 << 3):
        what.append("Write-through")
    else:
        what.append("Write-back")

    if value & (1 << 4):
        what.append("Non-Cached")
    else:
        what.append("Cached")

    if value & (1 << 5):
        what.append("Accessed")

    return what

if sys.argv[1] == 'directory':
    for role_start, role in data.items():
        for index, value in enumerate(role):
            if value & 1:
                what = []

                what.extend(common_flags(value))

                if value & (1 << 6):
                    what.append("4MiB Pages")
                else:
                    what.append("4KiB Pages")

                print("+{:08X} -:- Page Table at {:08X}: {}".format(
                    (role_start + index) * 0x400000,
                    value & 0xfffff000, ", ".join(what)))

elif sys.argv[1] == 'table':
    for role_start, role in data.items():
        for index, value in enumerate(role):
            if value & 1:
                what = []

                what.extend(common_flags(value))

                if value & (1 << 6):
                    what.append("Dirty")
                else:
                    what.append("Clean")

                if value & (1 << 7):
                    what.append("PAT")

                if value & (1 << 7):
                    what.append("Global")

                print("+{:08X} -:- Page at {:08X}: {}".format(
                    (role_start + index) * 0x400000,
                    value & 0xfffff000, ", ".join(what)))

elif sys.argv[1] == 'raw':
    for role_start, role in data.items():
        print("+{:08X} ================================================".format(role_start*4))
        for index, value in enumerate(role):
            print("+{:08X} -:- {:08X}".format((role_start + index) * 4, value))

else:
    sys.exit(1)
