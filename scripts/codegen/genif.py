#!/usr/bin/env python3

'''\
Georgios Interface Code Generator
'''

from argparse import ArgumentParser
from pathlib import Path

from bridle.type_files import add_type_file_argument_parsing, type_files_to_trees
import bridle.tree as ast
from bridle.tree import InterfaceNode
from bridle.tree import PrimitiveKind

indent = '    '

zig_primitives = {
    PrimitiveKind.boolean: 'bool',
    PrimitiveKind.byte: 'u8',
    PrimitiveKind.u8: 'u8',
    PrimitiveKind.i8: 'i8',
    PrimitiveKind.u16: 'u16',
    PrimitiveKind.i16: 'i16',
    PrimitiveKind.u32: 'u32',
    PrimitiveKind.i32: 'i32',
    PrimitiveKind.u64: 'u64',
    PrimitiveKind.i64: 'i64',
    PrimitiveKind.u128: 'u128',
    PrimitiveKind.i128: 'i128',
    PrimitiveKind.f32: 'f32',
    PrimitiveKind.f64: 'f64',
    PrimitiveKind.f128: 'f128',
    PrimitiveKind.c8: 'u8',
    PrimitiveKind.c16: 'u16',
    PrimitiveKind.s8: '[]const u8',
    PrimitiveKind.s16: '[]const u32',
}

def to_zig_type(type_node):
    if isinstance(type_node, ast.PrimitiveNode):
        return zig_primitives[type_node.kind]
    elif str(type_node) == 'void': # TODO: Should be a better way to do this
        return 'void'
    elif isinstance(type_node, ast.ScopedName):
        return '.'.join(type_node.parts)
    else:
        raise TypeError('Unsupported: ' + repr(type(type_node)) + ': ' + repr(type_node))


def arg_list(args):
    return ', '.join(args)


def zig_signature(return_type, args, preargs={}, postargs={}):
    all_args = {}
    for args in [preargs, args, postargs]:
        for name, type in args.items():
            all_args[name] = type
    return ('({}) georgios.DispatchError!{}'.format(arg_list(
        ['{}: {}'.format(name, type) for name, type in all_args.items()]), return_type), all_args)


def op_to_zig_signature(op, preargs={}, postargs={}):
    return zig_signature(to_zig_type(op.return_type),
        {name: to_zig_type(type.type) for name, type in op},
        preargs=preargs, postargs=postargs,
    )


class ZigFile:
    def __init__(self, source):
        self.path = source.parent / (source.stem + '.zig')
        self.file = self.path.open('w')
        self.indent_level = 0
        self.last_indent_change = 0
        self.print('// Generated from {} by ifgen.py\n', source)
        self.print('const georgios = @import("georgios.zig");', source)

    def print_i(self, what, *args, **kwargs):
        i = indent * self.indent_level
        formatted = what.format(*args, **kwargs)
        print(i + formatted.replace('\n', '\n' + i), file=self.file, flush=True)

    def print(self, what, *args, indent_change=0, **kwargs):
        # Insert a newline if a member is added or a new scope/block is being
        # opened after closing a nested scope/block or a new scope/block is
        # being opened after a member.
        if (indent_change >= 0 and self.last_indent_change < 0) or \
                (indent_change > 0 and self.last_indent_change == 0):
            print('', file=self.file, flush=True)
        # Decrease indent before closing scope/block
        if indent_change < 0:
            self.indent_level += indent_change

        self.print_i(what, *args, **kwargs)

        # Increate indent after opening scope/block
        if indent_change > 0:
            self.indent_level += indent_change
        self.last_indent_change = indent_change

    def open_scope(self, name, what, public=True):
        self.print('{}const {} = {} {{', 'pub ' if public else '', name, what, indent_change=1)

    def open_struct(self, name, public=True):
        self.open_scope(name, 'struct', public=public)

    def open_union(self, name, public=True):
        self.open_scope(name, 'union (enum)', public=public)

    def member(self, name, type, default = None):
        self.print('{}: {}{},', name, type, (' = ' + default) if default else '')

    def close_scope(self):
        self.print('}};', indent_change=-1)

    def open_block(self, what, *args, **kwargs):
        self.print(what + ' {{', *args, **kwargs, indent_change=1)

    def open_function_i(self, name, signature):
        self.open_block('pub fn {}{}', name, signature)

    def open_function(self, name, return_type, args, preargs={}, postargs={}):
        sig, all_args = zig_signature(return_type, args, preargs=preargs, postargs=postargs)
        return self.open_function_i(name, sig)

    def open_op_function(self, op, preargs={}, postargs={}, prefix='', postfix=''):
        sig, all_args = op_to_zig_signature(op, preargs=preargs, postargs=postargs)
        self.open_function_i(prefix + op.name + postfix, sig)
        return all_args

    def open_if(self, condition=None):
        self.open_block('if ({})', condition)

    def else_block(self, condition=None):
        self.indent_level -= 1
        self.print_i('}} else{} {{', '' if condition is None else (' if (' + condition + ')'))
        self.indent_level += 1
        self.last_indent_change = 1

    def close_block(self):
        self.print('}}', indent_change=-1)


def has_annotation(node, name):
    # TODO: Work on better way to get this info from the node in bridle
    for annotation in node.annotations:
        if annotation.name == name:
            return True
    return False


def gen_syscall(zig_file, node):
    for name, op in node:
        zig_file.open_op_function(op)
        zig_file.close_block()


def gen_dispatch(zig_file, node):

    self = {'self': '*' + node.name}

    # TODO: Zig Error Translation

    # Virtual Functions
    for name, op in node:
        all_args = zig_file.open_op_function(op, preargs=self)
        zig_file.print('return self._{}_impl({});', name, arg_list(all_args))
        zig_file.close_block()

    # Dispatch Argument Message Data
    zig_file.open_union('_ArgVals')
    for op_name, op in node:
        count = len(op)
        if count == 0:
            args_type = 'void'
        elif count == 1:
            args_type = to_zig_type(op.children[0].type)
        else:
            args_type = 'struct {\n'
            for arg_name, arg in op:
                args_type += '{}{}: {},\n'.format(indent, arg_name, to_zig_type(arg.type))
            args_type += '}'
        zig_file.member('_' + op_name, args_type)
    zig_file.close_scope()

    # Dispatch Return Message Data
    zig_file.open_union('_RetVals')
    for name, op in node:
        zig_file.member('_' + name, to_zig_type(op.return_type))
    zig_file.close_scope()

    # Dispatch Call/Send Implementations
    zig_file.open_struct('_dispatch_impls')
    for op_name, op in node:
        zig_file.open_op_function(op, preargs=self, prefix='_', postfix = '_impl')
        if len(op) == 1:
            for name in op.child_names():
                args = name
                break
        else:
            args = '.{' + arg_list(['.{0} = {0}'.format(name) for name in op.child_names()]) + '}'
        zig_file.print('return georgios.send_value(&_ArgVals{{.{} = {}}}, self._port_id, .{{}});',
            '_' + op_name, args)
        zig_file.close_block()
    zig_file.close_scope()

    # Dispatch Server Recv Implementation
    zig_file.open_function('_recv_value', 'void', {'dispatch': 'georgios.Dispatch'}, self)
    zig_file.open_block('return switch ((try georgios.msg_cast(_ArgVals, dispatch)).*)')
    for op_name, op in node:
        count = len(op)
        args = ['self']
        capture = ' |val|'
        if count == 0:
            capture = ''
        elif count == 1:
            args.append('val')
        else:
            args.extend(['val.' + arg for arg in op.child_names()])
        zig_file.print('._{} =>{} self._{}_impl({}),', op_name, capture, op_name, arg_list(args))
    zig_file.close_scope()
    zig_file.close_block()

    # TODO
    # Unsupported Implementations
    # zig_file.open_struct('_unsupported_impls')
    # for name, op in node:
    #     all_args = zig_file.open_op_function(op, preargs=self, prefix='_')
    #     for name in all_args.keys():
    #         zig_file.print('_ = {};', name)
    #     zig_file.print('@panic("TODO");') # TODO
    #     zig_file.close_block()
    # zig_file.close_scope()

    # TODO: Nop Implementation?

    # Implementation Functions Members
    zig_file.member('_port_id', 'georgios.PortId')
    for name, op in node:
        func_name = '_' + name + '_impl'
        zig_file.member(func_name, 'fn' + op_to_zig_signature(op, preargs=self)[0],
            default='_dispatch_impls.' + func_name)


def main():
    argparser = ArgumentParser(description=__doc__)
    add_type_file_argument_parsing(argparser)
    args = argparser.parse_args()

    trees = type_files_to_trees(args)
    for tree in trees:
        zig_file = ZigFile(tree.loc.source)
        for node in tree.children:
            if isinstance(node, InterfaceNode):
                zig_file.open_struct(node.name)

                if has_annotation(node, 'syscalls'):
                    gen_syscall(zig_file, node)
                elif has_annotation(node, 'virtual_dispatch'):
                    gen_dispatch(zig_file, node)
                else:
                    print(node.name, 'does not have an expected annotation')

                zig_file.close_scope()


if __name__ == "__main__":
    main()
