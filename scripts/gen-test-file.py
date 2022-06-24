#!/usr/bin/env python3

int_size = 4
total_size = 1048576
int_count = total_size // int_size
with open('tmp/root/files/test-file', 'bw') as f:
    for i in range(0, int_count):
        f.write(i.to_bytes(int_size, 'little'))
