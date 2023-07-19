#!/usr/bin/env python3

"""\
Script for managing Zig versions in use.

The script uses and updates the version listed in the README.md file.
current-path can be used to add zig to PATH.
"""

import sys
import json
from argparse import ArgumentParser
from pathlib import Path
import urllib.request
import urllib
import re
import functools
import enum
import tarfile


# Utils =======================================================================

def download(url, msg=''):
    msg += '...'
    print('Downloading', url + msg)
    try:
        return urllib.request.urlopen(url)
    except urllib.error.URLError as e:
        sys.exit('Failed to download {}: {}'.format(url, str(e)))


def download_file(url, dest=None):
    if dest.is_dir():
        dest = dest / url.split('/')[-1]
    with dest.open('wb') as f:
        f.write(download(url, ', saving to' + str(dest)).read())
    return dest


def extract_archive(archive, dest):
    print('Extracting', archive, 'to', dest)
    with tarfile.open(archive) as tf:
        
        import os
        
        def is_within_directory(directory, target):
            
            abs_directory = os.path.abspath(directory)
            abs_target = os.path.abspath(target)
        
            prefix = os.path.commonprefix([abs_directory, abs_target])
            
            return prefix == abs_directory
        
        def safe_extract(tar, path=".", members=None, *, numeric_owner=False):
        
            for member in tar.getmembers():
                member_path = os.path.join(path, member.name)
                if not is_within_directory(path, member_path):
                    raise Exception("Attempted Path Traversal in Tar File")
        
            tar.extractall(path, members, numeric_owner=numeric_owner) 
            
        
        safe_extract(tf, dest)
    archive.unlink()


# Main Logic ==================================================================

georgios_root = Path(__file__).resolve().parent.parent
readme_path = georgios_root / 'README.md'
default_zigs_path = georgios_root / '../zigs'
if not default_zigs_path.is_dir():
    default_zigs_path = georgios_root / 'tmp/zigs'

os = 'linux'
cpu = 'x86_64'

zig_version_url = 'https://ziglang.org/download/index.json'

field = r'0|[1-9]\d*'
version_regex = r'({f})\.({f})\.({f})(?:-dev\.(\d+))?'.format(f=field)
version_re = re.compile(version_regex)
current_re = re.compile(
    r'(.*\[Zig\]\(https:\/\/ziglang.org\/\) )(?P<ver>{}.*)$'.format(version_regex))
zig_name_re = re.compile('zig-([\w-]+)-(?P<ver>{}.*)$'.format(version_regex))


@functools.total_ordering
class Zig:
    def __init__(self, zigs_path, name):
        self.name = name
        m = zig_name_re.match(name)
        if not m:
            raise ValueError('Invalid zig name: ' + name)
        self.version = m.group('ver')
        self.path = zigs_path / name

    def exists(self):
        return (self.path / 'zig').is_file()

    @classmethod
    def from_version(cls, zigs_path, version):
        return cls(zigs_path, 'zig-{}-{}-{}'.format(os, cpu, version))

    @classmethod
    def from_info(cls, zigs_path, info):
        return cls.from_version(zigs_path, info['version'])

    def is_release(self):
        return self.version_parts()[3] is None

    def guess_url(self):
        return "https://ziglang.org/{}/{}.tar.xz".format(
            "download/" + self.version if self.is_release() else "builds", self.name)

    def version_parts(self):
        return version_re.match(self.version).groups()

    def __eq__(self, other):
        return self.version == other.version

    def __lt__(self, other):
        ours = self.version_parts()
        theirs = other.version_parts()
        def lt(i):
            if i == 3:
                if theirs[3] is None:
                    return ours[3] is not None
                elif ours[3] is None:
                    return False
            elif ours[i] == theirs[i]:
                return lt(i + 1)
            return ours[i] < theirs[i]
        return lt(0)

    def __str__(self):
        return self.version

    def __repr__(self):
        return '<Zig: {}>'.format(self.name)


def get_current_version():
    with readme_path.open() as f:
        for line in f:
            m = current_re.match(line)
            if m:
                return m.group('ver')
        raise ValueError('Could not get current from README.md')


def set_current_version(version):
    lines = readme_path.read_text().split('\n')
    for i, line in enumerate(lines):
        m = current_re.search(line)
        if m:
            lines[i] = m.group(1) + version
    readme_path.write_text('\n'.join(lines))


def get_current(zigs_path):
    return Zig.from_version(zigs_path, get_current_version())


def get_downloaded(zigs_path):
    l = []
    for zig_path in zigs_path.glob('*'):
        try:
            zig = Zig(zigs_path, zig_path.name)
            if zig.exists():
                l.append(zig)
        except:
            pass
    return sorted(l)


def use(zigs_path, version=None, zig=None):
    if version is not None:
        zig = Zig.from_version(zigs_path, version)
    elif zig is None:
        raise ValueError
    print('Using', zig.version)
    if not zig.exists():
        raise ValueError('Trying to use a Zig that does not exist: ' + str(zig.path))
    set_current_version(zig.version)
    print('Refresh PATH if needed')


def get_latest_info():
    return json.load(download(zig_version_url))["master"]


class CheckStatus(enum.Enum):
    UsingLatest = enum.auto(),
    LatestNotCurrent = enum.auto(),
    NeedToDownloadLatest = enum.auto(),


def check(zigs_path, for_update=False):
    current = get_current(zigs_path)
    print('Current is', current)
    if not for_update and not current.exists():
        print('  It needs to be downloaded!')

    latest_info = get_latest_info()
    latest = Zig.from_info(args.zigs_path, latest_info)
    print('Latest is', latest)
    using_latest = latest == current
    if using_latest:
        print('  Same as current')
    if latest.exists():
        if using_latest:
            status = CheckStatus.UsingLatest
        else:
            print('  Latest was downloaded, but isn\'t current')
            status = CheckStatus.LatestNotCurrent
    else:
        if for_update:
            print('  Will download the latest')
        else:
            print('  Would need to be downloaded')
        status = CheckStatus.NeedToDownloadLatest

    return status, latest, latest_info


def download_zig(zigs_path, zig, url):
    extract_archive(download_file(url, zigs_path), zigs_path)


def update(zigs_path):
    status, latest, latest_info = check(args.zigs_path, for_update=True)
    if status == CheckStatus.UsingLatest:
        return

    if status == CheckStatus.NeedToDownloadLatest:
        download_zig(zigs_path, latest, latest_info['{}-{}'.format(cpu, os)]['tarball'])
        status = CheckStatus.LatestNotCurrent

    if status == CheckStatus.LatestNotCurrent:
        use(zigs_path, zig=latest)


# Subcommands =================================================================

def current_path_subcmd(args):
    zig = get_current(args.zigs_path)
    if not zig.exists():
        raise ValueError('Zig in README.md does not exist: ' + str(zig.path))
    print(zig.path.resolve())


def current_version_subcmd(args):
    print(get_current_version())


def check_subcmd(args):
    check(args.zigs_path)


def list_subcmd(args):
    for zig in reversed(get_downloaded(args.zigs_path)):
        print(zig.version)


def use_subcmd(args):
    use(args.zigs_path, version=args.version)


def update_subcmd(args):
    update(args.zigs_path)


def download_subcmd(args):
    zig = get_current(args.zigs_path)
    if zig.exists():
        print('Already downloaded', zig.version)
        return
    download_zig(args.zigs_path, zig, zig.guess_url())


# Main ========================================================================

if __name__ == '__main__':
    arg_parser = ArgumentParser(description=__doc__)

    arg_parser.add_argument('--zigs-path',
        type=Path, default=default_zigs_path,
        help='Where to store all the versions of Zig'
    )

    subcmds = arg_parser.add_subparsers()

    cp = subcmds.add_parser('current-path',
        help='Print the path of the current Zig',
    )
    cp.set_defaults(func=current_path_subcmd)

    cv = subcmds.add_parser('current-version',
        help='Print the the current version of Zig',
    )
    cv.set_defaults(func=current_version_subcmd)

    c = subcmds.add_parser('check',
        help='See if there is a new latest',
    )
    c.set_defaults(func=check_subcmd)

    l = subcmds.add_parser('list',
        help='List all downloaded versions',
    )
    l.set_defaults(func=list_subcmd)

    us = subcmds.add_parser('use',
        help='Use a specified downloaded version',
    )
    us.set_defaults(func=use_subcmd)
    us.add_argument('version', metavar='VERSION')

    up = subcmds.add_parser('update',
        help='Use the latest version, downloading if needed',
    )
    up.set_defaults(func=update_subcmd)

    dl = subcmds.add_parser('download',
        help='Downloading the current version if missing',
    )
    dl.set_defaults(func=download_subcmd)

    args = arg_parser.parse_args()
    if not hasattr(args, 'func'):
        arg_parser.error('Must provide a subcommand')
    if args.zigs_path == default_zigs_path:
        args.zigs_path.resolve().mkdir(parents=True, exist_ok=True)
    args.zigs_path = args.zigs_path.resolve()
    args.func(args)
