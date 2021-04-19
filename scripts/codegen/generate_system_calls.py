#!/usr/bin/env python3

# Generates system call interface functions that can be called by programs
# based on the implementation file.

import sys
from pathlib import Path
import re
from subprocess import check_output, PIPE


debug = False
impl_file = Path('kernel/platform/system_calls.zig')
interface_file = Path('libs/georgios/system_calls.zig')
this_file = Path(__file__)
syscall_error_values_file = Path('tmp/syscall_error_values.zig')

int_num = None
syscall = None
syscalls = {}
syscall_regs = {}
imports = {'utils': 'utils'}


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


decompose_sig_re = re.compile(r'^(\w+)\((.*)\) (?:([^ :]+): )?((?:([^ !]+)!)?([\w\.]+))$')
error_re = re.compile(r'^(.*)!')
def decompose_sig(sig):
    m = decompose_sig_re.match(sig)
    if not m:
        error("Could not decompose signature of ", repr(sig))
    name, args, return_name, return_type, error_return, value_return = m.groups()
    if return_name is None:
        return_name = 'rv'
    return name, args, return_name, return_type, error_return, value_return


# See if we can skip generating the file
need_to_generate = False
if not interface_file.exists():
    log('Missing', str(interface_file), ' so need to generate')
    need_to_generate = True
else:
    interface_modified = interface_file.stat().st_mtime
    if this_file.stat().st_mtime >= interface_modified:
        log('Script changed so need to generate')
        need_to_generate = True
    elif impl_file.stat().st_mtime >= interface_modified:
        log(str(interface_file), 'was updated so need to generate')
        need_to_generate = True
if not need_to_generate:
    log('No need to generate', str(interface_file), 'so exiting')
    sys.exit(0);


# Parse the System Call Implementations =======================================

int_num_re = re.compile(r'\s*pub const interrupt_number: u8 = (\d+);$')
syscall_sig_re = re.compile(r'\s*// SYSCALL: (.*)')
syscall_num_re = re.compile(r'\s*(\d+) => ')
syscall_arg_re = re.compile(r'\s*const arg(\d+) = interrupt_stack.(\w+);')
import_re = re.compile(r'\s*// IMPORT: ([^ ]+) "([^" ]+)"')

with impl_file.open() as f:
    for i, line in enumerate(f):
        lineno = i + 1

        # System Call Interrupt Number
        m = int_num_re.match(line)
        if m:
            if syscall:
                error("Interrupt Number in syscall on line", lineno)
            if int_num is not None:
                error(("Found duplicate interrupt number {} on line {}, " +
                    "already found {}").format(m.group(1), lineno, int_num))
            int_num = m.group(1)
            continue

        # Registers Available for Return and Arguments
        m = syscall_arg_re.match(line)
        if m:
            if syscall:
                error("Syscall register in syscall on line", lineno)
            syscall_regs[int(m.group(1))] = m.group(2)
            continue

        # System Call Pseudo-Signature (see implementation file for details)
        m = syscall_sig_re.match(line)
        if m:
            if syscall:
                error("Syscall signature", repr(syscall),
                    "without a syscall number before line ", lineno)
            syscall = m.group(1)
            continue

        # Import Needed for the System Call
        m = import_re.match(line)
        if m:
            if syscall is None:
                error("Import without a syscall signature on line", lineno)
            imports[m.group(1)] = m.group(2)
            continue

        # System Call Number, Concludes System Call Info
        m = syscall_num_re.match(line)
        if m:
            if syscall is None:
                error("Syscall number without a syscall signature on line", lineno)
            syscalls[int(m.group(1))] = syscall
            syscall = None
            continue


# Error Translation ===========================================================

# Get Existing Error Codes
# Do this to make sure error value are the same between runs.
error_code_re = re.compile(r'    (\w+) = (\d+),')
in_error_code = False
all_error_codes = {}
max_error_code = 0
with interface_file.open('r') as f:
    for i, line in enumerate(f):
        lineno = i + 1
        if in_error_code:
            m = error_code_re.search(line)
            if m:
                ec = int(m.group(2))
                all_error_codes[m.group(1)] = ec
                max_error_code = max(max_error_code, ec)
            elif line == '};\n':
                break
        elif line == 'const ErrorCode = enum(u32) {\n':
            in_error_code = True

# Get Errors Used by System Calls
error_types = {}
for call in syscalls.values():
    error_type = decompose_sig(call)[4]
    if error_type:
        error_types[error_type] = []

# Get all the error values/codes of the error types used by the system calls.
syscall_error_values_file.parent.mkdir(parents=True, exist_ok=True)
for error_type in error_types:
    with syscall_error_values_file.open('w') as f:
        print('''\
            const std = @import("std");
            const georgios = @import("georgios");
            pub fn main() !void {
                const stdout = std.io.getStdOut().writer();
                for (@typeInfo(''' + error_type + ''').ErrorSet.?) |field| {
                    try stdout.print("{s}\\n", .{field.name});
                }
            }
            ''', file=f)

    error_codes = [s for s in check_output([
        'zig', 'run',
        '--pkg-begin', 'georgios', 'libs/georgios/georgios.zig',
        '--pkg-begin', 'utils', 'libs/utils/utils.zig',
        str(syscall_error_values_file),
        '--pkg-end',
        '--pkg-end']).decode('utf-8').split('\n') if s]

    error_types[error_type] = error_codes
    for error_code in error_codes:
        if error_code not in all_error_codes:
            max_error_code += 1
            all_error_codes[error_code] = max_error_code


# Print Debug Info ============================================================

if int_num is None:
    error("Didn't find interrupt number")
if debug:
    log('System Call Interrupt Number:', int_num)

if len(syscall_regs) == 0:
    error("No registers found!")

if debug:
    for num, reg in syscall_regs.items():
        log('Arg {} is reg %{}'.format(num, reg))

if len(syscalls) == 0:
    error("No system calls found!")

if debug:
    for pair in imports.items():
        log('Import', *pair)


# Write Interface File ========================================================

with interface_file.open('w') as f:
    print('''\
// Generated by scripts/codegen/generate_system_calls.py from
// kernel/platform/system_calls.zig. See system_calls.zig for more info.
''', file=f)

    for pair in imports.items():
        print('const {} = @import("{}");'.format(*pair), file=f)

    print('const ErrorCode = enum(u32) {', file=f)
    for name, value in all_error_codes.items():
        print('    {} = {},'.format(name, value), file=f)
    print('''\
    _,
};

pub fn ValueOrError(comptime ValueType: type, comptime ErrorType: type) type {
    return union (enum) {
        const Self = @This();

        value: ValueType,
        error_code: ErrorCode,

        pub fn set_value(self: *Self, value: ValueType) void {
            self.* = Self{.value = value};
        }

        pub fn set_error(self: *Self, err: ErrorType) void {
            self.* = Self{.error_code = switch (ErrorType) {''', file=f)

    for error_type, error_values in error_types.items():
        print('                {} => switch (err) {{'.format(error_type), file=f)
        for error_value in error_values:
            print('                    {0}.{1} => ErrorCode.{1},'.format(
                error_type, error_value), file=f)
        print('                },', file=f)

    print('''\
                else => @compileError(
                    "Invalid ErrorType for " ++ @typeName(Self) ++ ".set_error: " ++
                    @typeName(ErrorType)),
            }};
        }

        pub fn get(self: *const Self) ErrorType!ValueType {
            return switch (self.*) {
                Self.value => |value| return value,
                Self.error_code => |error_code| switch (ErrorType) {''', file=f)

    for error_type, error_values in error_types.items():
        print('                    {} => switch (error_code) {{'.format(error_type), file=f)
        for error_value in error_values:
            print('                        .{0} => {1}.{0},'.format(
                error_value, error_type), file=f)
        print('                        {} => utils.Error.Unknown,'.format(
            '_' if len(error_values) == len(all_error_codes) else 'else'), file=f)
        print('                    },', file=f)

    print('''\
                    else => @compileError(
                            "Invalid ErrorType for " ++ @typeName(Self) ++ ".get: " ++
                            @typeName(ErrorType)),
                },
            };
        }
    };
}
''', file=f)

    for num, sig in syscalls.items():
        name, args, return_name, return_type, error_return, value_return = decompose_sig(sig)
        args = args.split(', ')
        if len(args) == 1 and args[0] == '':
            args = []
        if debug:
            log(num, '=>', repr(name), 'args', args,
                'return', repr(return_name), ': ', repr(return_type))
        noreturn = return_type == 'noreturn'
        has_return = not (return_type == 'void' or noreturn)
        return_expr = return_name
        if error_return:
            internal_return_type = 'ValueOrError({}, {})'.format(value_return, error_return)
            return_expr += '.get()'
        else:
            internal_return_type = return_type

        required_regs = len(args) + 1 if has_return else 0
        avail_regs = len(syscall_regs)
        if required_regs > avail_regs:
            error('System call {} requires {} registers, but the max is',
                repr(sig), required_regs, avail_regs)

        print('\npub inline fn {}({}) {} {{'.format(
            name,
            ', '.join([a[1:] if a.startswith('&') else a for a in args]),
            return_type), file=f)

        return_value = ''
        if has_return:
            print('    var {}: {} = undefined;'.format(
                return_name, internal_return_type), file=f)

        print((
            '    asm volatile ("int ${}" ::\n' +
            '        [syscall_number] "{{eax}}" (@as(u32, {})),'
            ).format(int_num, num), file=f)

        arg_num = 1
        def add_arg(arg_num , what):
            if ':' in what:
                what = what.split(':')[0]
            if what.startswith('&'):
                what = '@ptrToInt(' + what + ')'
            print('        [arg{}] "{{{}}}" ({}),'.format(
                arg_num, syscall_regs[arg_num], what), file=f)
            return arg_num + 1

        for arg in args:
            arg_num = add_arg(arg_num, arg)

        if has_return:
            arg_num = add_arg(arg_num, '&' + return_name)

        print(
            '        );', file=f)

        if has_return:
            print('    return {};'.format(return_expr), file=f)
        elif noreturn:
            print('    unreachable;', file=f)
        print('}', file=f)
