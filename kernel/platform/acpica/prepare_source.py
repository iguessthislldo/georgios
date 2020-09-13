#!/usr/bin/env python3

import sys
from pathlib import Path

def log(*args, prefix_message=None, **kwargs):
    f = kwargs[file] if 'file' in kwargs else sys.stdout
    prefix = lambda what: print(what, ": ", sep='', end='', file=f)
    prefix(sys.argv[0])
    if prefix_message is not None:
        prefix(prefix_message)
    print(*args, **kwargs)

def error(*args, **kwargs):
    log(*args, prefix_message='ERROR', **kwargs)
    sys.exit(1)

if len(sys.argv) != 2:
    error("Invalid argument count, pass the base path")

prefix_path = Path(sys.argv[1])
suffix_path = Path('include') / 'platform' / 'acenv.h'
src = prefix_path / 'acpica' / 'source' / suffix_path
dst = prefix_path / suffix_path
to_replace = '#error Unknown target environment'
to_insert = '#include "acgeorgios.h"'

if dst.is_file():
    log(str(dst), "already exists")
    sys.exit(0)

lines = src.read_text().split('\n')
indexes = []
for i, line in enumerate(lines):
    if line == to_replace:
        indexes.append(i)
log('Found', repr(to_replace), 'on line(s):', ','.join([str(i + 1) for i in indexes]))
if len(indexes) != 1:
   error("Was expecting just one line!")
lines[indexes[0]] = to_insert
dst.write_text('\n'.join(lines))
