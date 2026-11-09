#!/usr/bin/env python3
"""AetherNX command-line tool (run through ./aethernx).

  scan [folders...] [--json]          list the games in your library folders
  unpack <archive|folder> [--out DIR] extract .zip / .rar / .7z / .tar archives of game packages
  build <game folder> [--target T]    build a game: mac (default), ios, ios-slim or xcode; other options go to build_ipa_from_nsp.py
  decomp-init <game folder>           function and symbol tables of an extracted game, with a C++ starter project
  lift <game folder>                  translate an extracted module to C with nxrt (vendor/nxrt)
  setup [--tools]                     create .venv and install the Python packages the build needs
  doctor [--json]                     check the tools and files a build needs
  studio [--rebuild]                  build (once) and open AetherNX Studio
  version

The build itself is scripts/build_ipa_from_nsp.py; this tool only finds games, prepares folders and starts it.
"""
import argparse
import contextlib
import json
import os
import platform
import re
import shutil
import struct
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT / 'scripts'), str(ROOT / 'dm' / 'tools'), str(ROOT / 'dm' / 'games')]

VERSION = (ROOT / 'VERSION').read_text().strip() if (ROOT / 'VERSION').is_file() else '0.0.0'
PACKAGE_SUFFIXES = ('.nsp', '.xci', '.nsz', '.xcz')
ARCHIVE_SUFFIXES = ('.zip', '.rar', '.7z', '.tar', '.tar.gz', '.tgz', '.tar.xz', '.txz', '.tar.zst', '.001')
TARGETS = {
    'mac': ['--platform', 'mac-app'],
    'ios': ['--platform', 'ios'],
    'ios-slim': ['--platform', 'ios', '--romfs', 'separate'],
    'xcode': ['--prepare-xcode', '--keep-extracted'],
}
ALIASES = {'build-mac': 'mac', 'build-ios': 'ios', 'build-ios-slim': 'ios-slim', 'prepare-xcode': 'xcode'}
HORIZON_SUPPORT = Path.home() / 'Library' / 'Application Support' / 'HorizonNative'
HORIZON_LOGS = Path.home() / 'Library' / 'Logs' / 'HorizonNative'


class CliError(Exception):
    pass


def builder():   # the packing script, imported only by the commands that read game packages (it is large)
    import build_ipa_from_nsp
    return build_ipa_from_nsp


def default_library():
    env = os.environ.get('AETHERNX_LIBRARY')
    if env: return [Path(p).expanduser() for p in env.split(':') if p]
    home = Path.home() / 'Games'
    return [home] if home.is_dir() else []


def default_keys():
    env = os.environ.get('AETHERNX_KEYS')
    if env: return Path(env).expanduser()
    p = Path.home() / '.switch' / 'prod.keys'
    return p if p.is_file() else None


def size_of(p):
    try: return p.stat().st_size if p.is_file() else sum(f.stat().st_size for f in p.rglob('*') if f.is_file())
    except OSError: return 0


def file_entry(p):
    return {'name': p.name, 'path': str(p), 'size': size_of(p)}


# ---- scan ----

def is_archive(p):
    low = p.name.lower()
    if not low.endswith(ARCHIVE_SUFFIXES): return False
    part = re.search(r'\.part(\d+)\.rar$', low) or re.search(r'\.(\d{3})$', low)
    return not (part and int(part.group(1)) > 1) and not re.search(r'\.r\d{2}$', low)


def archive_stem(p):   # the folder unpack extracts an archive into: its name without the archive suffixes ("Game.part1.rar" → "Game")
    stem = re.sub(r'\.(tar\.(gz|xz|zst)|zip|rar|7z|tgz|txz|tar|001)$', '', p.name, flags=re.I)
    return re.sub(r'\.part\d+$', '', stem, flags=re.I).strip() or p.stem


def archives_in(folder, depth=0):
    out = []
    try: entries = sorted(folder.iterdir())
    except OSError: return out
    for p in entries:
        if p.name.startswith('.'): continue
        if p.is_dir() and not p.is_symlink() and depth < 2 and not p.name.endswith(('_build', '_survey', '.app')):
            out += archives_in(p, depth + 1)
        elif p.is_file() and is_archive(p):
            out.append(p)
    return out


def has_packages_here(folder):   # packages directly in the folder (not in its subfolders)
    try: return any(p.is_file() and p.suffix.lower() in PACKAGE_SUFFIXES and not p.name.startswith('._') for p in folder.iterdir())
    except OSError: return False


def package_contents(paths):
    """A keyless stand-in for the packing script's content-meta reader (package_reader, which needs prod.keys and builds nx_extract), enough to list a library: a package's
    title IDs from its tickets' names (an NSP or NSZ lists `<rights ID>.tik`, whose first 16 digits are the title ID), else from a [<title ID>] tag in its file name; its version
    from a [v<N>] tag, else 0. {path: [(type, title ID, version)]}, or {path: why} for one that tells neither. The build reads the content metas themselves"""
    out = {}
    for p in paths:
        tids = []
        try:
            with open(p, 'rb') as f:
                head = f.read(16)
                if len(head) == 16 and head[:4] == b'PFS0':
                    n, table = struct.unpack_from('<II', head, 4)
                    if n <= 4096 and table <= 1 << 20:
                        body = f.read(n * 24 + table); names = body[n * 24:]
                        for i in range(n if len(body) == n * 24 + table else 0):
                            at = struct.unpack_from('<I', body, i * 24 + 16)[0]
                            end = names.find(b'\0', at)
                            name = names[at:end if end >= 0 else len(names)].decode('ascii', 'replace')
                            if re.fullmatch(r'[0-9a-fA-F]{32}\.tik', name): tids.append(int(name[:16], 16))
        except OSError as e:
            out[p] = f'cannot be read ({e.strerror})'; continue
        if not tids and (m := re.search(r'\[([0-9A-Fa-f]{16})\]', p.name)): tids.append(int(m[1], 16))
        if not tids: out[p] = 'no ticket and no [title ID] in its name; a build reads its content meta with prod.keys'; continue
        v = int(m[1]) if (m := re.search(r'\[v(\d+)\]', p.name)) else 0
        out[p] = [('Application' if t & 0xFFF == 0 else 'Patch' if t & 0xFFF == 0x800 else 'AddOnContent', t, v) for t in dict.fromkeys(tids)]
    return out


def scan_game(folder):
    """One game folder as a dict, or None when the folder holds no game. Raises CliError with the reason when it holds an unreadable one."""
    b = builder()
    import game as profiles
    notes = []
    b.say = lambda msg: notes.append(re.sub(r'^\[[0-9:]+\] ', '', msg))   # the packing script's messages, kept as the game's notes instead of printed
    archives = archives_in(folder)
    kind = 'packages'
    try:
        if b.dump_folder(folder):
            app, fam = b.scan_dump(folder); kind = 'dump'
        elif b.package_files(folder):
            app, fam = b.scan_nsps(folder, package_contents)   # without keys: a scan only lists the library
        elif archives:
            return {'id': str(folder), 'kind': 'archives', 'title_id': None, 'name': folder.name, 'folder': str(folder), 'profile': False,
                    'archives': [file_entry(p) for p in archives], 'notes': ['The game is still in an archive: unpack it first.']}
        else:
            return None
    except b.BuildError as e:
        raise CliError(str(e)) from e
    tid = f'{app:016X}'
    prof = profiles.by_title(app)
    base = fam['base']
    name = (prof.get('name') if prof else None) or (re.sub(r'\s*[\[(].*$', '', base.stem).strip() if base and kind == 'packages' else folder.name)
    work = folder / f'{tid}_build'
    extracted = sorted((d.name for d in (work / 'extract').glob('v*') if (d / 'ExeFS').is_dir() and d.name[1:].isdigit()), key=lambda v: int(v[1:])) if (work / 'extract').is_dir() else []
    newest = work / 'extract' / extracted[-1] if extracted else None
    display_version = None
    if newest and (newest / 'control.nacp').is_file():
        import nacp
        with contextlib.suppress(Exception): display_version = nacp.version(str(newest / 'control.nacp')) or None
    decomp = work / 'decomp'
    lifted = decomp / 'lifted'
    return {
        'id': str(folder),
        'kind': kind,
        'title_id': tid,
        'name': name,
        'folder': str(folder),
        'profile': prof is not None,
        'base': file_entry(base) if base else None,
        'updates': [dict(file_entry(p), version=v or 0) for v, p in sorted(fam['updates'], key=lambda u: u[0] or 0)],
        'dlc': [dict(file_entry(p), title_id=f'{t:016X}', index=t - app - 0x1000) for t, _, p in sorted(fam['dlc'], key=lambda d: d[0])],
        'compressed': [str(p) for p in b.package_files(folder) if p.suffix.lower() in ('.nsz', '.xcz')] if kind == 'packages' else [],
        'archives': [file_entry(p) for p in archives],
        'work_dir': str(work),
        'extracted_versions': extracted,
        'display_version': display_version,   # from the newest extraction's control data, once the game was built
        'icon': str(newest / 'icon.jpg') if newest and (newest / 'icon.jpg').is_file() else None,
        'mac_apps': [str(p) for p in sorted(folder.glob('*.app')) if p.is_dir()],
        'ipas': [str(p) for p in sorted(folder.glob('*.ipa')) if p.is_file()],
        'save_dir': str(HORIZON_SUPPORT / tid),
        'log_file': str(HORIZON_LOGS / f'{tid}.log'),
        'decomp_dir': str(decomp) if (decomp / 'manifest.json').is_file() else None,
        'lifted_files': len(list(lifted.rglob('*.c'))) if lifted.is_dir() else 0,
        'notes': notes,
    }


def scan_library(roots):
    games, errors, seen = [], [], set()
    for root in roots:
        root = root.expanduser().resolve()
        if not root.is_dir():
            errors.append({'folder': str(root), 'message': 'not a folder'}); continue
        candidates = [root] if has_packages_here(root) or (root / 'base').is_dir() else sorted(d for d in root.iterdir() if d.is_dir() and not d.name.startswith('.') and not d.name.endswith(('_build', '_survey', '.app')))
        if candidates != [root]:   # an archive straight in the library folder is a game still to unpack, unless unpack already made its folder
            games += [{'id': str(a), 'kind': 'archives', 'title_id': None, 'name': re.sub(r'\s*[\[(].*$', '', archive_stem(a)).strip() or a.name, 'folder': str(root),
                       'profile': False, 'archives': [file_entry(a)], 'notes': ['The game is still in an archive: unpack it first.']}
                      for a in sorted(root.iterdir()) if a.is_file() and is_archive(a) and not (root / archive_stem(a)).is_dir()]
        for folder in candidates:
            if folder in seen: continue
            seen.add(folder)
            try: g = scan_game(folder)
            except CliError as e: errors.append({'folder': str(folder), 'message': str(e)}); continue
            except Exception as e:   # an unexpected failure in one folder must not hide the others
                errors.append({'folder': str(folder), 'message': f'{type(e).__name__}: {e}'}); continue
            if g: games.append(g)
    games.sort(key=lambda g: g['name'].lower())
    return games, errors


def cmd_scan(args):
    roots = [Path(d) for d in args.folders] or default_library()
    if not roots: raise CliError('name a library folder: ./aethernx scan ~/Games (or set AETHERNX_LIBRARY)')
    with contextlib.redirect_stdout(sys.stderr):   # nothing but the result goes to stdout
        games, errors = scan_library(roots)
    if args.json:
        print(json.dumps({'version': 1, 'games': games, 'errors': errors}, ensure_ascii=False, indent=1))
        return 0
    for g in games:
        if g['kind'] == 'archives':
            print(f"{g['name']}: archived ({len(g['archives'])} archive(s)), run ./aethernx unpack \"{g['folder']}\""); continue
        upd = f"update v{g['updates'][-1]['version']}" if g['updates'] else 'no update'
        built = 'Mac app built' if g['mac_apps'] else 'not built'
        prof = 'tested profile' if g['profile'] else 'no profile (best effort)'
        print(f"{g['name']} [{g['title_id']}]: {upd}, {len(g['dlc'])} DLC, {prof}, {built}")
    for e in errors: print(f"! {e['folder']}: {e['message']}", file=sys.stderr)
    if not games and not errors: print('No games found.')
    return 0


# ---- unpack ----

def extract_archive(arc, dest):
    dest.mkdir(parents=True, exist_ok=True)
    seven, unar = shutil.which('7zz') or shutil.which('7z'), shutil.which('unar')
    low = arc.name.lower()
    if seven: cmd = [seven, 'x', '-y', f'-o{dest}', str(arc)]
    elif unar and not low.endswith('.zip'): cmd = [unar, '-q', '-f', '-o', str(dest), str(arc)]
    elif low.endswith('.zip'): cmd = ['ditto', '-x', '-k', str(arc), str(dest)]
    else: cmd = ['tar', '-xf', str(arc), '-C', str(dest)]   # bsdtar reads tar, 7z and older RAR archives
    r = subprocess.run(cmd, capture_output=True, text=True, errors='replace')
    if r.returncode:
        hint = '' if seven or unar else ' (for RAR 5 archives: brew install sevenzip)'
        raise CliError(f'could not extract {arc.name}{hint}: {(r.stderr or r.stdout).strip()[-400:]}')


def cmd_unpack(args):
    target = Path(args.target).expanduser().resolve()
    if not target.exists(): raise CliError(f'no such file or folder: {target}')
    if target.is_file():
        if not is_archive(target): raise CliError(f'{target.name} is not an archive (.zip, .rar, .7z, .tar)')
        dest, todo = Path(args.out).expanduser() if args.out else target.parent / archive_stem(target), [target]
    else:
        dest, todo = Path(args.out).expanduser() if args.out else target, archives_in(target)
        if not todo: raise CliError(f'no archives in {target}')
    for arc in todo:
        print(f'extracting {arc.name} → {dest}', file=sys.stderr)
        extract_archive(arc, dest)
        if args.delete_archives: arc.unlink()
    packages = [str(p) for p in builder().package_files(dest)]
    if args.json: print(json.dumps({'folder': str(dest), 'archives': [str(a) for a in todo], 'packages': packages}, ensure_ascii=False))
    else: print(f'{len(todo)} archive(s) extracted to {dest}: {len(packages)} game package(s) there')
    return 0


# ---- build ----

def cmd_build(args, rest):
    folder = Path(args.folder).expanduser().resolve()
    if not folder.is_dir(): raise CliError(f'no such folder: {folder}')
    keys = []
    if args.keys: keys = ['-k', str(Path(args.keys).expanduser())]
    elif (k := default_keys()) is not None: keys = ['-k', str(k)]
    cmd = [sys.executable, str(ROOT / 'scripts' / 'build_ipa_from_nsp.py'), str(folder), *keys, *TARGETS[args.target], *rest]
    sys.stdout.flush()
    os.execv(sys.executable, cmd)


# ---- decomp-init ----

def eh_functions(img):   # {offset: size} of the functions an NSO image's .eh_frame_hdr lists (MOD0 → eh_frame_hdr, the table the compiler writes for unwinding)
    if len(img) < 0x20: return {}
    m0 = struct.unpack_from('<I', img, 4)[0]
    if m0 + 24 > len(img) or img[m0:m0 + 4] != b'MOD0': return {}
    rel = struct.unpack_from('<i', img, m0 + 16)[0]
    hdr = m0 + rel
    if not rel or hdr + 12 > len(img) or tuple(img[hdr + 1:hdr + 4]) != (0x1B, 0x03, 0x3B): return {}
    out = {}
    for i in range(struct.unpack_from('<I', img, hdr + 8)[0]):
        e = hdr + 12 + i * 8
        if e + 8 > len(img): break
        loc, fde = (x + hdr for x in struct.unpack_from('<ii', img, e))
        if loc < 0 or fde + 16 > len(img): continue
        if fde + 8 + struct.unpack_from('<i', img, fde + 8)[0] != loc: continue
        out[loc] = max(out.get(loc, 0), struct.unpack_from('<I', img, fde + 12)[0])
    return out


def demangle(names):
    mangled = [n for n in names if n.startswith('_Z')]
    if not mangled: return {}
    try: r = subprocess.run(['c++filt', '-n'], input='\n'.join(mangled), capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.SubprocessError): return {}
    return dict(zip(mangled, r.stdout.splitlines()))


def extracted_exefs(folder):
    with contextlib.redirect_stdout(sys.stderr):
        g = scan_game(folder)
    if not g or g['kind'] == 'archives': raise CliError(f'no game in {folder}')
    if not g['extracted_versions']:
        raise CliError(f'{g["name"]} has no extracted files yet: build it once (extracted files are kept by default), then run this again')
    ver = g['extracted_versions'][-1]
    return g, ver, Path(g['work_dir']) / 'extract' / ver / 'ExeFS'


def cmd_decomp_init(args):
    import nso
    import nso_syms
    g, ver, exefs = extracted_exefs(Path(args.folder).expanduser().resolve())
    out = Path(g['work_dir']) / 'decomp'
    for sub in ('functions', 'symbols', 'src'): (out / sub).mkdir(parents=True, exist_ok=True)
    modules = []
    for path in sorted(p for p in exefs.iterdir() if p.is_file() and p.name != 'main.npdm' and not p.name.startswith('.')):
        try: mod = nso.read(str(path))
        except Exception as e:   # a file of ExeFS that is not an NSO module
            print(f'skipping {path.name}: {e}', file=sys.stderr); continue
        img = bytes(mod.image)
        (text_off, text_size), (_, ro_size), (_, data_size) = mod.segments
        try: dyn, defined = nso_syms.dynsyms(img), nso_syms.defined(img)
        except Exception: dyn, defined = [], {}
        names = demangle([s for s, _, _ in dyn])
        rows = ['symbol\tdemangled\tdefined\toffset\tsize']
        for s, is_def, _ in dyn:
            off, size = defined.get(s, (0, 0))
            rows.append(f'{s}\t{names.get(s, s)}\t{int(bool(is_def))}\t0x{off:08x}\t0x{size:x}')
        (out / 'symbols' / f'{path.name}.tsv').write_text('\n'.join(rows) + '\n')
        fns = eh_functions(img)
        at = {off: s for s, (off, size) in defined.items() if text_off <= off < text_off + text_size}
        for off, s in at.items():   # exported functions the unwind table does not list
            if off not in fns and defined[s][1]: fns[off] = defined[s][1]
        rows = ['offset\tsize\tsymbol\tdemangled']
        for off in sorted(fns):
            s = at.get(off, f'sub_{off:08x}')
            rows.append(f'0x{off:08x}\t0x{fns[off]:x}\t{s}\t{names.get(s, s)}')
        (out / 'functions' / f'{path.name}.tsv').write_text('\n'.join(rows) + '\n')
        modules.append({'module': path.name, 'build_id': mod.build_id[:16].hex(), 'text_size': text_size, 'rodata_size': ro_size, 'data_size': data_size,
                        'bss_size': mod.bss, 'functions': len(fns), 'symbols': len(dyn), 'imports': sum(1 for _, d, _ in dyn if not d)})
    if not modules: raise CliError(f'no NSO modules in {exefs}')
    (out / 'CMakeLists.txt').write_text(
        'cmake_minimum_required(VERSION 3.22)\n'
        f'project(decomp_{g["title_id"]} LANGUAGES CXX)\n'
        'set(CMAKE_CXX_STANDARD 20)\n'
        f'set(AETHERNX "{ROOT}")\n'
        '# Nintendo SDK and sead headers: git submodule update --init vendor/nnheaders vendor/sead\n'
        'include_directories("${AETHERNX}/vendor/nnheaders/include" "${AETHERNX}/vendor/sead/include")\n'
        'file(GLOB SOURCES src/*.cpp)\n'
        'if(SOURCES)\n  add_library(decomp STATIC ${SOURCES})\nendif()\n')
    manifest = {'generated': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()), 'title_id': g['title_id'], 'name': g['name'], 'version': ver, 'modules': modules}
    (out / 'manifest.json').write_text(json.dumps(manifest, indent=1, ensure_ascii=False) + '\n')
    lines = [f'# {g["name"]} ({g["title_id"]}, {ver})', '', 'Made by `./aethernx decomp-init` from your own extracted game files. Keep this folder private: it describes the game\'s code.', '',
             '| Module | Build ID | Functions | Symbols | Imports | .text |', '|---|---|---|---|---|---|']
    lines += [f'| `{m["module"]}` | `{m["build_id"]}` | {m["functions"]:,} | {m["symbols"]:,} | {m["imports"]:,} | {m["text_size"] / 2**20:.1f} MiB |' for m in modules]
    lines += ['', '- `functions/<module>.tsv`: start offset, size and symbol of every function', '- `symbols/<module>.tsv`: the dynamic symbols, demangled', '- `CMakeLists.txt`, `src/`: an empty C++ project with the SDK headers on its include path']
    (out / 'README.md').write_text('\n'.join(lines) + '\n')
    if args.json: print(json.dumps(dict(manifest, folder=str(out)), ensure_ascii=False))
    else: print(f'{g["name"]}: {len(modules)} modules, {sum(m["functions"] for m in modules):,} functions → {out}')
    return 0


# ---- lift ----

def cmd_lift(args):
    gen = ROOT / 'vendor' / 'nxrt' / 'tools' / 'gen.py'
    if not gen.is_file(): raise CliError('nxrt is not checked out: git submodule update --init --depth 1 vendor/nxrt')
    try: import unicorn  # noqa: F401  # pyright: ignore[reportMissingImports]  # optional: nxrt resolves jump tables with it
    except ImportError: raise CliError(f'nxrt needs the unicorn package: {sys.executable} -m pip install unicorn (or ./aethernx setup --tools)') from None
    g, _, exefs = extracted_exefs(Path(args.folder).expanduser().resolve())
    nso_path = exefs / args.module
    if not nso_path.is_file(): raise CliError(f'no module {args.module} in {exefs}')
    out = Path(g['work_dir']) / 'decomp' / 'lifted' / args.module
    out.mkdir(parents=True, exist_ok=True)
    base = '0x7000000000' if args.module == 'rtld' else '0x7100000000'
    cmd = [sys.executable, str(gen), args.module, str(nso_path), base, str(out), '--hle', str(ROOT / 'vendor' / 'nxrt' / 'runtime' / 'hle' / 'hle_symbols.txt')]
    if args.limit: cmd += ['--limit', str(args.limit)]
    env = dict(os.environ, PYTHONPATH=str(gen.parent))
    r = subprocess.run(cmd, env=env, stdout=sys.stderr if args.json else None)
    if r.returncode: raise CliError(f'nxrt stopped with exit code {r.returncode}')
    files = len(list(out.glob('*.c')))
    if args.json: print(json.dumps({'module': args.module, 'folder': str(out), 'files': files}))
    else: print(f'{g["name"]}: {args.module} → {files} C files in {out}')
    return 0


# ---- setup ----

def cmd_setup(args):
    if sys.version_info < (3, 12): raise CliError(f'Python 3.12 or later is needed, this is {platform.python_version()} ({sys.executable})')
    venv = ROOT / '.venv'
    py = venv / 'bin' / 'python3'
    if not py.exists():
        print(f'creating {venv}', file=sys.stderr)
        subprocess.run([sys.executable, '-m', 'venv', str(venv)], check=True)
    pkgs = ['-r', str(ROOT / 'scripts' / 'requirements.txt')] + (['unicorn'] if args.tools else [])
    r = subprocess.run([str(py), '-m', 'pip', 'install', '--disable-pip-version-check', *pkgs])
    if r.returncode: raise CliError('pip could not install the packages (see above)')
    print(f'Python packages ready in {venv}. Run ./aethernx doctor to check the rest.')
    return 0


# ---- doctor ----

def run_out(cmd, timeout=20):
    try: r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, errors='replace')
    except (OSError, subprocess.SubprocessError) as e: return 1, str(e)
    return r.returncode, (r.stdout or r.stderr).strip()


def importable(name):
    import importlib.util
    try: return importlib.util.find_spec(name) is not None
    except (ImportError, ValueError): return False


def doctor():
    checks = []
    def check(group, name, ok, detail='', fix='', required=True):
        checks.append({'group': group, 'name': name, 'ok': bool(ok), 'required': required, 'detail': detail, 'fix': fix})
    pip = f'{sys.executable} -m pip install' if not (ROOT / '.venv').exists() else f'{ROOT}/.venv/bin/pip install'
    check('Python', f'Python {platform.python_version()}', sys.version_info >= (3, 12), sys.executable, 'brew install python, then ./aethernx setup')
    rosetta = run_out(['sysctl', '-n', 'sysctl.proc_translated'])[1] == '1'
    check('Python', 'Native arm64 Python', not rosetta, platform.machine(), 'use an Apple-silicon Python (/opt/homebrew/bin/python3), not an Intel one')
    for mod, label in (('lz4.block', 'lz4'), ('fontTools', 'fonttools')):
        check('Python', label, importable(mod), '', f'./aethernx setup (or {pip} {label})')
    cap, cap_version = None, 'missing'
    if importable('capstone'):
        import capstone
        cap, cap_version = capstone.cs_version()[0], capstone.__version__
    check('Python', 'capstone 5', cap == 5, cap_version, f'{pip} "capstone>=5,<6"')
    check('Python', 'zstd', importable('compression.zstd') or importable('backports.zstd'), '', f'{pip} backports.zstd')
    check('Python', 'nsz (for .nsz / .xcz packages)', importable('nsz') or shutil.which('nsz'), '', f'{pip} nsz', required=False)
    check('Python', 'zbic (for games built with system 22.0.0 or later; the build needs it for every game)', importable('zbic'), '', f'{pip} zbic')

    code, out = run_out(['xcodebuild', '-version'])
    xcode = out.splitlines()[0] if code == 0 and out else ''
    check('Xcode', 'Xcode', code == 0, xcode or out[-200:], 'install Xcode 27.2 and select it: sudo xcode-select -s /Applications/Xcode.app')
    check('Xcode', 'Metal toolchain', run_out(['xcrun', '-sdk', 'macosx', 'metal', '--version'])[0] == 0, '', 'xcodebuild -downloadComponent MetalToolchain')
    check('Xcode', 'iOS SDK (iPhone and iPad builds)', run_out(['xcrun', '--sdk', 'iphoneos', '--show-sdk-version'])[0] == 0, '', 'Xcode → Settings → Components → iOS', required=False)
    for tool, fix, req in (('dotnet', 'brew install --cask dotnet-sdk', True), ('zstd', 'brew install zstd', True), ('glslangValidator', 'brew install glslang', True),
                           ('xcodegen', 'brew install xcodegen (iPhone and iPad builds)', False)):
        check('Tools', tool, shutil.which(tool), shutil.which(tool) or 'not found', fix, required=req)
    arch = shutil.which('7zz') or shutil.which('7z') or shutil.which('unar')
    check('Tools', '7-Zip or unar (RAR 5 archives)', arch, arch or 'zip and tar archives still work', 'brew install sevenzip', required=False)

    keys = default_keys()
    check('Keys', 'prod.keys', keys and keys.is_file(), str(keys) if keys else 'not in ~/.switch/prod.keys',
          'put your prod.keys in ~/.switch/prod.keys, set AETHERNX_KEYS, or pass -k (Studio: Settings → Keys)', required=False)

    for sub, use in (('nxrt', 'lift'), ('nnheaders', 'decomp-init headers'), ('sead', 'decomp-init headers')):
        present = any((ROOT / 'vendor' / sub).iterdir()) if (ROOT / 'vendor' / sub).is_dir() else False
        check('Developer tools', f'vendor/{sub} ({use})', present, '', f'git submodule update --init --depth 1 vendor/{sub}', required=False)
    check('Developer tools', 'unicorn (lift)', importable('unicorn'), '', './aethernx setup --tools', required=False)
    return {'version': VERSION, 'ok': all(c['ok'] for c in checks if c['required']), 'checks': checks}


def cmd_doctor(args):
    rep = doctor()
    if args.json:
        print(json.dumps(rep, indent=1)); return 0 if rep['ok'] else 1
    group = None
    for c in rep['checks']:
        if c['group'] != group:
            group = c['group']; print(f'\n{group}')
        mark = '✓' if c['ok'] else ('✗' if c['required'] else '–')
        print(f'  {mark} {c["name"]}' + (f'  ({c["detail"]})' if c['detail'] and c['ok'] else ''))
        if not c['ok'] and c['fix']: print(f'      fix: {c["fix"]}')
    print('\nReady to build.' if rep['ok'] else '\nSome required pieces are missing (✗).')
    return 0 if rep['ok'] else 1


# ---- studio ----

def cmd_studio(args):
    app = ROOT / 'build' / 'AetherNX.app'
    if args.rebuild or not app.is_dir():
        subprocess.run(['bash', str(ROOT / 'studio' / 'build.sh')], check=True)
    subprocess.run(['open', str(app)], check=True)
    return 0


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if argv and argv[0] in ALIASES: argv = ['build', *argv[1:2], '--target', ALIASES[argv[0]], *argv[2:]]
    ap = argparse.ArgumentParser(prog='aethernx', description=f'AetherNX {VERSION}: native Mac, iPhone and iPad apps of the Switch games you own.', allow_abbrev=False,
                                 formatter_class=argparse.RawDescriptionHelpFormatter, epilog='Run ./aethernx <command> -h for the options of a command.')
    ap.add_argument('--version', action='version', version=f'AetherNX {VERSION}')
    sub = ap.add_subparsers(dest='cmd', metavar='<command>')
    p = sub.add_parser('scan', help='list the games in your library folders', allow_abbrev=False)
    p.add_argument('folders', nargs='*', help='library folders (default: $AETHERNX_LIBRARY, else ~/Games)')
    p.add_argument('--json', action='store_true')
    p = sub.add_parser('unpack', help='extract .zip / .rar / .7z / .tar archives of game packages', allow_abbrev=False)
    p.add_argument('target', help='an archive, or a folder whose archives to extract')
    p.add_argument('--out', help='where to extract (default: a folder named after the archive, or the folder itself)')
    p.add_argument('--delete-archives', action='store_true', help='delete each archive once extracted')
    p.add_argument('--json', action='store_true')
    p = sub.add_parser('build', help='build a game (other options go to scripts/build_ipa_from_nsp.py: see its --help)', allow_abbrev=False)
    p.add_argument('folder', help="the game's folder: base game, update and DLC packages")
    p.add_argument('--target', choices=TARGETS, default='mac', help='mac = a Mac app (default); ios = an IPA; ios-slim = an IPA without the game files; xcode = an Xcode project')
    p.add_argument('-k', '--keys', help='your prod.keys (default: $AETHERNX_KEYS, else ~/.switch/prod.keys)')
    p = sub.add_parser('decomp-init', help='function and symbol tables of an extracted game', allow_abbrev=False)
    p.add_argument('folder')
    p.add_argument('--json', action='store_true')
    p = sub.add_parser('lift', help='translate an extracted module to C with nxrt', allow_abbrev=False)
    p.add_argument('folder')
    p.add_argument('--module', default='main', help='the ExeFS module (default: main)')
    p.add_argument('--limit', type=int, default=0, help='at most this many functions (for a quick test)')
    p.add_argument('--json', action='store_true')
    p = sub.add_parser('setup', help='create .venv and install the Python packages', allow_abbrev=False)
    p.add_argument('--tools', action='store_true', help='also the packages the developer tools need (unicorn)')
    p = sub.add_parser('doctor', help='check the tools and files a build needs', allow_abbrev=False)
    p.add_argument('--json', action='store_true')
    p = sub.add_parser('studio', help='build (once) and open AetherNX Studio', allow_abbrev=False)
    p.add_argument('--rebuild', action='store_true')
    sub.add_parser('version', help='print the version')
    sub.add_parser('help', help='show this help')

    args, rest = ap.parse_known_args(argv)
    if rest and args.cmd != 'build': ap.error(f'unrecognized arguments: {" ".join(rest)}')
    if args.cmd in (None, 'help'): ap.print_help(); return 0
    if args.cmd == 'version': print(f'AetherNX {VERSION}'); return 0
    try:
        if args.cmd == 'build': return cmd_build(args, rest)
        return {'scan': cmd_scan, 'unpack': cmd_unpack, 'decomp-init': cmd_decomp_init, 'lift': cmd_lift, 'setup': cmd_setup,
                'doctor': cmd_doctor, 'studio': cmd_studio}[args.cmd](args)
    except CliError as e:
        print(f'aethernx: {e}', file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        return 130


if __name__ == '__main__':
    sys.exit(main())
