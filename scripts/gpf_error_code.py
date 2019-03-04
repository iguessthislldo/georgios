#!/usr/bin/env python3

import sys

if len(sys.argv) != 2:
    print("Pass Error Code from a General Protection Fault")
    sys.exit(1)

print("Error Caused By:")

value = int(sys.argv[1])
if value & 1:
    print("External To The CPU")
table = ["GDT", "IDT", "LDT", "IDT"][(value >> 1) & 3]
print("In the", table)
index = (value >> 3) & 8191
print("At Selector Index", index)
if (table == "IDT"):
    print("This is", ("Intel Interrupt " + str(index)) if index < 32 else ("IRQ " + str(index - 32)))
