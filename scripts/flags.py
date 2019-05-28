#!/usr/bin/env python3

import sys

if len(sys.argv) != 2:
    print("Pass x86 Flags Register Value as Hex")
    sys.exit(1)

value = int(sys.argv[1], 16)

if value & 0x0001:
    print("Carry")
if value & 0x0004:
    print("Parity")
if value & 0x0010:
    print("Adjust")
if value & 0x0040:
    print("Zero")
if value & 0x0080:
    print("Sign")
if value & 0x0100:
    print("Trap")
if value & 0x0200:
    print("Interrupts Enabled")
if value & 0x0400:
    print("Direction")
if value & 0x0800:
    print("Overflow")
# I/O Privilege Level (Ignore for now)
if value & 0x4000:
    print("Nested Task")
if value & 0x00010000:
    print("Resume")
if value & 0x00020000:
    print("Virutal 8086 Mode")
if value & 0x00040000:
    print("Virtual Interrupt")
if value & 0x00100000:
    print("Virtual Interrupt Pending")
if value & 0x00200000:
    print("Able to use CPUID")
