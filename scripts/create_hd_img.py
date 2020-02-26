import sys
from array import array

sector_size = int(sys.argv[1])
in_file = sys.argv[2]
out_file = sys.argv[3]

size_sector = array('L', (0,) * (sector_size // 4))
with open(in_file, "rb") as f:
    content = f.read()
content_size = len(content)
size_sector[0] = content_size
padding = array('B', (0,) * (sector_size - (content_size % sector_size)))
with open(out_file, "wb") as f:
    f.write(size_sector.tobytes() + content + padding.tobytes())
