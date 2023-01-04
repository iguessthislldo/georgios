# This is to figure out the "bottom-up" bitmap buffered reading for bmp files

class Bmp:
    def __init__(self):
        self.pos = 0
        self.width = 4
        self.height = 3
        self.bmp_data = [
            8, 9, 10, 11,
            4, 5, 6, 7,
            0, 1, 2, 3,
        ]
        self.len = len(self.bmp_data)
        self.read_pos = 0

    def read(self, buffer, start, end):
        count = min(end - start, self.len - self.read_pos)
        for i, byte in enumerate(self.bmp_data[self.read_pos:self.read_pos + count]):
            buffer[start + i] = byte
        self.read_pos += count
        return count

    def seek(self, pos):
        self.read_pos = pos

    def read_bitmap(self, buffer):
        got = 0
        while got < len(buffer) and self.pos < self.len:
            row = self.pos // self.width
            col = self.pos % self.width
            seek_to = self.len - self.width * (row + 1) + col
            count = min(self.width - col, len(buffer) - got)
            print('pos =', self.pos, 'row =', row, 'col =', col, 'seek_to =', seek_to, 'count =', count)
            self.seek(seek_to)
            assert count == self.read(buffer, got, got + count)
            got += count
            self.pos += count
        return got

bmp = Bmp()
print(bmp.bmp_data)
buffer = [0xaa] * 5
print(buffer[0:bmp.read_bitmap(buffer)])
print(buffer[0:bmp.read_bitmap(buffer)])
print(buffer[0:bmp.read_bitmap(buffer)])
