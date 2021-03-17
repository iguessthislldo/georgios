import sys
from pathlib import Path
import subprocess
import re

def git(*args):
    result = subprocess.run(["git"] + list(args), check=True, stdout=subprocess.PIPE)
    return result.stdout.decode('utf-8').split('\n')

def get_files():
    # Get Tracked Files
    files = set([Path(p) for p in git("ls-files") if p])
    if not files:
        sys.exit("Error: No Tracked Files")
    # Get Untracked Files
    files |= set([Path(p[3:]) for p in git("status", "--porcelain=v1") if p.startswith('??')])
    return sorted(list(files))

status = 0

trailing_whitespace = re.compile(r'.*\s$')
zig_test = re.compile(r'^test ".*" {$')
zig_test_files = set()
main_test_file = "kernel/test.zig"
for path in get_files():
    if not path.is_file() or path.suffix in ('.img', '.png'):
        continue
    with path.open() as f:
        try:
            lines = [line[:-1] for line in f.readlines()]
        except Exception as e:
            print(str(path), str(e), file=sys.stderr)
            status = 1
            continue
        zig_file = path.suffix == ".zig"
        lineno = 1
        for line in lines:
            if trailing_whitespace.match(line):
                print('Trailing space on {}:{}'.format(str(path), lineno))
                status = 1
            if zig_file and str(path) != main_test_file and zig_test.match(line):
                zig_test_files |= {str(path)}
            lineno += 1

# Check that the files that have tests are the same as the files in kernel/test.zig
zig_test_import_re = re.compile(r'const \w+ = @import\("(\w+.zig)"\);')
zig_test_imports = set()
with open(main_test_file) as f:
    for line in f.readlines():
        m = zig_test_import_re.search(line)
        if m:
            zig_test_imports |= {'kernel/' + m.group(1)}
missing_from_test_zig = zig_test_files - zig_test_imports
if missing_from_test_zig:
    print('Missing from', main_test_file + ':', ', '.join(missing_from_test_zig))
    status = 1
missing_zig_tests = zig_test_imports - zig_test_files
if missing_zig_tests:
    print('Imports in', main_test_file, 'without tests:', ', '.join(missing_zig_tests))
    status = 1

sys.exit(status)
