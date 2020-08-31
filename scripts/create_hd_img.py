import sys

size_size = 4

sector_size = int(sys.argv[1])
in_file = sys.argv[2]
out_file = sys.argv[3]

with open(in_file, "rb") as f:
    content = f.read()
content_size = len(content)
with open(out_file, "wb") as f:
    f.write(
        content_size.to_bytes(size_size, 'little') +
        content +
        b'\x00' * (sector_size - (((size_size + content_size) % sector_size) % sector_size)));
