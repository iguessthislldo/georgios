#!/usr/bin/env python3

import sys

def bits(value):
    m = value.bit_length()
    for i in range(0, m):
        if value & (1<<i):
            print("Bit", i, "enabled")

def usage(rv):
    print("Supply ")
    sys.exit(rv)

if len(sys.argv) != 2:
    usage(1)

bits(int(sys.argv[1], 16))
