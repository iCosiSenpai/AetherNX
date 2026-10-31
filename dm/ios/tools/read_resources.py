#!/usr/bin/env python3
"""Read a prepared project's Gen/resources.env (written by gen_resources.py) as data: print each DM_RESOURCE_* setting as name NUL value NUL for a shell to assign.
stage_resources.sh and scripts/push_romfs.sh used to `source` the file, which ran any command in it (a resources.env passed to push_romfs.sh may come from elsewhere);
now a line that is not NAME=<one shell word> with a DM_RESOURCE_ name stops the read.
Usage: read_resources.py <resources.env>"""
import re
import shlex
import sys


def settings(path):
    out = {}
    with open(path, encoding='utf-8') as f:
        for n, line in enumerate(f, 1):
            line = line.rstrip('\n')
            if not line.strip() or line.lstrip().startswith('#'): continue
            m = re.fullmatch(r'(DM_RESOURCE_[A-Z0-9_]+)=(.*)', line)
            if not m or '\0' in m.group(2): raise ValueError(f'{path}:{n}: not a DM_RESOURCE_ setting: {line[:80]}')
            words = shlex.split(m.group(2), comments=False, posix=True)
            if len(words) > 1: raise ValueError(f'{path}:{n}: more than one value: {line[:80]}')
            out[m.group(1)] = words[0] if words else ''
    return out


if __name__ == '__main__':
    if len(sys.argv) != 2: sys.exit(__doc__)
    try: values = settings(sys.argv[1])
    except (OSError, UnicodeError, ValueError) as e: sys.exit(f'[RED] {e}')
    sys.stdout.write(''.join(f'{k}\0{v}\0' for k, v in values.items()))
