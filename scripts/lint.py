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

# Find Files ==================================================================
trailing_whitespace = re.compile(r'.*\s$')
zig_test_re = re.compile(r'^test "(.*)" {$')
zig_test_roots = set()
zig_files_with_tests = set()
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
            if zig_file:
                m = zig_test_re.match(line)
                if m:
                    if m.group(1).endswith("test root"):
                        zig_test_roots |= {path}
                    else:
                        zig_files_with_tests |= {path}
            lineno += 1

# Make sure all tests are being tested ========================================

# Make sure all test roots are in build.zig
zig_add_tests_re = re.compile(r'add_tests\("([\w/]+.zig)"\);')
zig_add_tests = set()
with open('build.zig') as f:
    for line in f.readlines():
        m = zig_add_tests_re.search(line)
        if m:
            zig_add_tests |= {Path(m.group(1))}
missing_from_build_zig = zig_test_roots - zig_add_tests
if missing_from_build_zig:
    print('Missing from build.zig:',
        ', '.join([str(p) for p in missing_from_build_zig]))
    status = 1
missing_zig_test_roots = zig_add_tests - zig_test_roots
if missing_zig_test_roots:
    print('add_tests in build.zig that are not test roots:',
        ', '.join([str(p) for p in missing_zig_test_roots]))
    status = 1

# Make sure all zig files with tests are in a test root
imported_in_test_roots = set()
test_import_re = re.compile(r'const \w+ = @import\("(\w+.zig)"\);')
for zig_test_root in zig_test_roots:
    with open(zig_test_root) as f:
        for line in f.readlines():
            m = test_import_re.search(line)
            if m:
                imported_in_test_roots |= {zig_test_root.parent / m.group(1)}
missing_from_test_roots = zig_files_with_tests - imported_in_test_roots
if missing_from_test_roots:
    print('Missing from a test root:',
        ', '.join([str(p) for p in missing_from_test_roots]))
    status = 1
missing_zig_tests = imported_in_test_roots - zig_files_with_tests
if missing_zig_tests:
    print('Imports in test roots without tests:',
        ', '.join([str(p) for p in missing_zig_tests]))
    status = 1

sys.exit(status)
