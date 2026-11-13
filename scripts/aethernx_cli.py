#!/usr/bin/env python3
"""AetherNX command-line tool (run through ./aethernx).

  scan [folders...] [--json]          list the games in your library folders
  unpack <archive|folder> [--out DIR] extract .zip / .rar / .7z / .tar archives of game packages
  build <game folder> [--target T]    build a game: mac (default), ios, ios-slim or xcode; other options go to build_ipa_from_nsp.py
  devices [--json]                    the iPhones and iPads paired with this Mac, and the Apple teams it can sign with
  install <game folder> [--device D]  build a game, sign it with your Apple team and install it on a paired iPhone or iPad
  move-build <game folder> [--here]   move a game's build folder and Mac apps to the builds folder ($AETHERNX_BUILDS), or back beside the game
  decomp-init <game folder>           function and symbol tables of an extracted game, with a C++ starter project
  lift <game folder>                  translate an extracted module to C with nxrt (vendor/nxrt)
  report <game folder|title ID>       a zip for a bug report: logs, versions and settings, never game data (scripts/bug_report.py)
  setup [--tools]                     create .venv and install the Python packages the build needs
  doctor [--json]                     check the tools and files a build needs
  studio [--rebuild]                  build (once) and open AetherNX Studio
  version

The build itself is scripts/build_ipa_from_nsp.py; this tool only finds games, prepares folders and starts it.
"""
import argparse
import contextlib
import errno
import json
import os
import platform
import plistlib
import re
import shlex
import shutil
import signal
import struct
import subprocess
import sys
import time
from pathlib import Path
from xml.parsers.expat import ExpatError

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT / 'scripts'), str(ROOT / 'dm' / 'tools'), str(ROOT / 'dm' / 'games')]

VERSION = (ROOT / 'VERSION').read_text().strip() if (ROOT / 'VERSION').is_file() else '0.0.0'
PACKAGE_SUFFIXES = ('.nsp', '.xci', '.nsz', '.xcz')
ARCHIVE_SUFFIXES = ('.zip', '.rar', '.7z', '.tar', '.tar.gz', '.tgz', '.tar.xz', '.txz', '.tar.zst', '.001')
TARGETS = {
    'mac': ['--platform', 'mac-app'],
    'ios': ['--platform', 'ios'],
    'ios-slim': ['--platform', 'ios', '--romfs', 'separate', '--keep-extracted'],   # the image stays for the one-time copy to the phone (the build refuses --romfs separate without it)
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


def built_apps(folder, tid):
    """The Mac apps built from the game in folder: app bundles whose Info.plist names its title ID (DMTitleID, which dm/mac/pack_app.py writes). Any other app there (one
    downloaded into the same folder) is not the game's: Studio would open it with Play and the Danger Zone would remove it and its settings"""
    out = []
    for p in sorted(folder.glob('*.app')):
        try:
            with open(p / 'Contents' / 'Info.plist', 'rb') as f: info = plistlib.load(f)
        except (OSError, ValueError, ExpatError): continue   # no Info.plist, or a damaged one (plistlib.InvalidFileException is a ValueError)
        if isinstance(info, dict) and str(info.get('DMTitleID', '')).upper() == tid: out.append(str(p))
    return out


# ---- where builds live ----
# A game's build folder is <game folder>/<title ID>_build unless a builds folder is set (AETHERNX_BUILDS, Studio's Settings → Storage): there each game gets
# <builds folder>/<game folder's name>/<title ID>_build, and its Mac app is written beside it, so a drive or a network share holds what a build makes instead of the
# Mac. Where a game's build is goes into BUILD_POINTER in its folder whenever it is not beside the game, so the scan still finds it after the setting changed and
# says the build is on a disk that is not connected instead of building again from scratch on the Mac.
BUILD_POINTER = '.aethernx-build'


def builds_root():   # the builds folder, or None: beside each game
    v = os.environ.get('AETHERNX_BUILDS', '').strip()
    return Path(v).expanduser().absolute() if v else None


def safe_name(name):   # a folder name a network share or an exFAT drive takes too (they refuse : \ * ? " < > | that APFS allows)
    return re.sub(r'[\x00-\x1f/:\\*?"<>|]', '_', name).strip(' .') or 'game'


def volume_of(path):   # the mount point holding path: /Volumes/<name> for a drive or a share, / for the Mac's own disk
    parts = Path(path).absolute().parts
    return Path('/', parts[1], parts[2]) if len(parts) > 2 and parts[1] == 'Volumes' else Path('/')


def reachable(path):   # whether the disk that holds path is there: an unplugged drive or a share not connected leaves no mount at /Volumes/<name>
    v = volume_of(path)
    return v == Path('/') or os.path.ismount(v)


def recorded_work(folder):   # the build folder BUILD_POINTER names: one that exists, or one on a disk that is not there now
    try: text = (folder / BUILD_POINTER).read_text(encoding='utf-8').strip()
    except (OSError, UnicodeDecodeError): return None
    p = Path(text) if text else None
    return p if p and p.is_absolute() and (p.exists() or not reachable(p)) else None


def wanted_work(folder, tid, root=None):   # where a new build of the game goes: the builds folder's, else beside the game
    root = root or builds_root()
    return root / safe_name(folder.name) / f'{tid}_build' if root else folder / f'{tid}_build'


def work_folder(folder, tid):
    """The game's build folder: the recorded one, else the one beside the game when it is there, else where a new build goes. A build beside the game stays in
    use after a builds folder is set, until move-build moves it: changing the setting never makes a game build again from the start"""
    if (w := recorded_work(folder)): return w
    here = folder / f'{tid}_build'
    return here if here.exists() else wanted_work(folder, tid)


def record_work(folder, tid, work):   # BUILD_POINTER names the build folder when it is not beside the game, and goes away when it is
    pointer = folder / BUILD_POINTER
    with contextlib.suppress(OSError):
        if work == folder / f'{tid}_build': pointer.unlink(missing_ok=True)
        else: pointer.write_text(f'{work}\n', encoding='utf-8')


def prepare_work(folder, tid, work):   # a build folder that is not beside the game: its disk must be there, and its folder made and recorded
    if work == folder / f'{tid}_build': return
    if not reachable(work): raise CliError(f'the build folder {work} is on {volume_of(work).name}, which is not connected: connect it, or move the build (aethernx move-build)')
    try: work.parent.mkdir(parents=True, exist_ok=True)
    except OSError as e: raise CliError(f'cannot make {work.parent}: {e.strerror}') from e
    record_work(folder, tid, work)


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
        m = re.search(r'\[v(\d+)\]', p.name) or re.search(r'(?<![0-9A-Za-z])v(\d{5,}|0)(?![0-9])(?!\.\d)', p.name)   # [v327680], else a bare v327680 (versions are 0 or multiples of 65536)
        v = int(m[1]) if m else 0
        out[p] = [('Application' if t & 0xFFF == 0 else 'Patch' if t & 0xFFF == 0x800 else 'AddOnContent', t, v) for t in dict.fromkeys(tids)]
    # A cartridge dump (XCI / XCZ) has no ticket, and No-Intro names ("Game (USA, Europe) (En,Ja,...).xci") carry no title ID. Beside the update or DLC of one game it is
    # that game's base: the build reads its content meta with prod.keys and stops if it is not (Hyrule Warriors: Age of Calamity, an XCI and its v327680 update NSP)
    apps = {t & ~0xFFF if t & 0xFFF in (0, 0x800) else (t & ~0xFFF) - 0x1000 for m in out.values() if not isinstance(m, str) for _, t, _ in m}
    for p, m in out.items():
        if isinstance(m, str) and len(apps) == 1 and is_cartridge(p): out[p] = [('Application', next(iter(apps)), 0)]
    return out


def is_cartridge(path):   # an XCI / XCZ: the card header's magic at 0x100 (is_package in the packing script)
    try:
        with open(path, 'rb') as f: f.seek(0x100); return f.read(4) == b'HEAD'
    except OSError: return False


def device_install_record(work):
    try:
        with open(work / 'xcode' / 'install.json') as f: rec = json.load(f)
    except (OSError, ValueError): return None
    if not isinstance(rec, dict): return None
    return {k: str(rec[k]) for k in ('team', 'bundle_id', 'device', 'device_name', 'installed') if isinstance(rec.get(k), str)} or None


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
    work = work_folder(folder, tid)
    online = reachable(work)
    wanted = wanted_work(folder, tid)
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
        'work_reachable': online,   # false: the build is on a drive or a share that is not connected now
        'work_moves_to': str(wanted) if online and work.exists() and wanted != work else None,   # where move-build would put it (the builds folder, or back beside the game)
        'extracted_versions': extracted,
        'display_version': display_version,   # from the newest extraction's control data, once the game was built
        'icon': str(newest / 'icon.jpg') if newest and (newest / 'icon.jpg').is_file() else None,
        'mac_apps': built_apps(folder, tid) + (built_apps(work.parent, tid) if work.parent != folder and online else []),   # a build elsewhere writes its app beside it
        'ipas': [str(p) for d in dict.fromkeys([folder, work.parent]) if d == folder or online for p in sorted(d.glob('*.ipa')) if p.is_file()],
        'device_install': device_install_record(work),   # the last ./aethernx install: the device, the team and the bundle ID it was signed with
        'save_dir': str(HORIZON_SUPPORT / tid),
        'log_file': str(HORIZON_LOGS / f'{tid}.log'),
        'decomp_dir': str(decomp) if (decomp / 'manifest.json').is_file() else None,
        'lifted_files': len(list(lifted.rglob('*.c'))) if lifted.is_dir() else 0,
        'notes': notes,
    }


def scan_library(roots):
    """Each library folder's games. A folder that is one game's own (its packages or a dump at its top: a single game's folder added as a library folder) is that game;
    otherwise each folder in it is a game, and an archive at its top a game still to unpack. A folder that cannot be read, and one game that does not read, is an error
    beside the others' games, never the end of the scan"""
    b = builder()
    games, errors, seen = [], [], set()
    for root in roots:
        root = root.expanduser().resolve()
        if not root.is_dir():
            errors.append({'folder': str(root), 'message': 'not a folder'}); continue
        try:
            entries = sorted(root.iterdir())
            own = has_packages_here(root) or (root / 'base').is_dir() or b.dump_folder(root)
        except OSError as e:   # one that macOS's privacy settings or its permissions keep from this process
            errors.append({'folder': str(root), 'message': f'cannot be read ({e.strerror or e})'}); continue
        subdirs = [d for d in entries if d.is_dir() and not d.name.startswith('.') and not d.name.endswith(('_build', '_survey', '.app'))]
        if own and root not in seen:
            seen.add(root)
            try: g = scan_game(root)
            except Exception as e:   # CliError, or an unexpected failure: reported, and the game folders in it still listed
                why = str(e) if isinstance(e, CliError) else f'{type(e).__name__}: {e}'
                if not subdirs: errors.append({'folder': str(root), 'message': why}); continue
                # Packages dropped at the top of a library of game folders: the build reads the folder with its subfolders, so it is no one game. It used to take
                # the whole library down with it (one error, no game listed); the games in its folders are listed as always
                errors.append({'folder': str(root), 'message': f'{why} (the game folders in it are listed on their own; its top level is no game)'})
            else:
                if g: games.append(g); continue
                # no game at its top after all (a folder named base that is not a dump's): the folders in it are the games
        elif own: continue   # the same game folder named twice
        # an archive straight in the library folder is a game still to unpack, unless unpack already made its folder
        games += [{'id': str(a), 'kind': 'archives', 'title_id': None, 'name': re.sub(r'\s*[\[(].*$', '', archive_stem(a)).strip() or a.name, 'folder': str(root),
                   'profile': False, 'archives': [file_entry(a)], 'notes': ['The game is still in an archive: unpack it first.']}
                  for a in entries if a.is_file() and is_archive(a) and not (root / archive_stem(a)).is_dir()]
        for folder in subdirs:
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
            print(f"{g['name']}: archived ({len(g['archives'])} archive(s)), run ./aethernx unpack {shlex.quote(g['id'])}"); continue   # the archive itself when it lies at the top of a library folder (unpacking that folder would extract every archive of the library into it)
        upd = f"update v{g['updates'][-1]['version']}" if g['updates'] else 'no update'
        built = 'Mac app built' if g['mac_apps'] else 'not built'
        prof = 'tested profile' if g['profile'] else 'no profile (best effort)'
        print(f"{g['name']} [{g['title_id']}]: {upd}, {len(g['dlc'])} DLC, {prof}, {built}")
    for e in errors: print(f"! {e['folder']}: {e['message']}", file=sys.stderr)
    if not games and not errors: print('No games found.')
    return 0


# ---- unpack ----

TAR_SUFFIXES = ('.tar', '.tar.gz', '.tgz', '.tar.xz', '.txz', '.tar.zst')


def extract_archive(arc, dest):
    dest.mkdir(parents=True, exist_ok=True)
    seven, unar = shutil.which('7zz') or shutil.which('7z'), shutil.which('unar')
    low = arc.name.lower()
    # A tar, compressed or not, goes to bsdtar, which reads it whole: 7-Zip takes off one layer only, so Game.tar.gz gave Game.tar and no package
    if low.endswith(TAR_SUFFIXES): cmd = ['tar', '-xf', str(arc), '-C', str(dest)]
    elif seven: cmd = [seven, 'x', '-y', f'-o{dest}', str(arc)]
    elif unar and not low.endswith('.zip'): cmd = [unar, '-q', '-f', '-o', str(dest), str(arc)]
    elif low.endswith('.zip'): cmd = ['ditto', '-x', '-k', str(arc), str(dest)]
    else: cmd = ['tar', '-xf', str(arc), '-C', str(dest)]   # bsdtar reads tar, 7z and older RAR archives
    # No terminal for a password prompt: an encrypted archive fails at once instead of waiting, unseen, for a password (the output is captured)
    r = subprocess.run(cmd, capture_output=True, text=True, errors='replace', stdin=subprocess.DEVNULL)
    if r.returncode:
        text = (r.stderr or r.stdout).strip()
        hint = '' if seven or unar or low.endswith(TAR_SUFFIXES) else ' (for RAR 5 archives: brew install sevenzip)'
        if 'password' in text.lower() or 'Break signaled' in text: hint = ' (it is encrypted: extract it with its password, then unpack or add the folder)'   # 7-Zip's answer to a password it could not ask for
        raise CliError(f'could not extract {arc.name}{hint}: {text[-400:]}')


def archive_volumes(arc):
    """An archive and the rest of its volumes, as Studio's Danger Zone takes them (archiveParts): Game.part1.rar → Game.part2.rar …, Game.rar → Game.r00 …,
    Game.7z.001 → Game.7z.002 …"""
    name = arc.name
    if m := re.fullmatch(r'(.*)\.part\d+\.rar', name, re.I): pattern = re.compile(re.escape(m[1]) + r'\.part\d+\.rar', re.I)
    elif m := re.fullmatch(r'(.*)\.\d{3}', name): pattern = re.compile(re.escape(m[1]) + r'\.\d{3}')
    elif m := re.fullmatch(r'(.*)\.rar', name, re.I): pattern = re.compile(re.escape(m[1]) + r'\.r(ar|\d{2})', re.I)
    else: return [arc]
    try: return sorted(p for p in arc.parent.iterdir() if p.is_file() and pattern.fullmatch(p.name))
    except OSError: return [arc]


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
    b = builder()
    packages = [str(p) for p in b.package_files(dest)]
    try: dumps = [str(d) for d in [dest, *sorted(p for p in dest.iterdir() if p.is_dir())] if b.dump_folder(d)]
    except OSError: dumps = []
    # Nothing a build takes came out (an archive of something else, or one an extractor only partly opened): the archives stay, whatever --delete-archives says
    if not packages and not dumps:
        raise CliError(f'{len(todo)} archive(s) extracted to {dest}, and no game package (.nsp, .xci, .nsz, .xcz) or dump folder is there' + (': the archives are kept' if args.delete_archives else ''))
    if args.delete_archives:   # every volume of a multi-part archive, not only its first
        for arc in todo:
            for part in archive_volumes(arc): part.unlink(missing_ok=True)
    if args.json: print(json.dumps({'folder': str(dest), 'archives': [str(a) for a in todo], 'packages': packages, 'dumps': dumps}, ensure_ascii=False))
    else: print(f'{len(todo)} archive(s) extracted to {dest}: {len(packages)} game package(s) and {len(dumps)} dump folder(s) there')
    return 0


# ---- build ----

def with_work_dir(folder, rest):   # the build script's arguments with --work-dir when the game's build folder is not beside it (a builds folder, a recorded one)
    if '--work-dir' in rest: return rest
    with contextlib.redirect_stdout(sys.stderr):
        try: g = scan_game(folder)
        except CliError: return rest   # the build script says what is wrong with the folder
    if not g or not g.get('title_id'): return rest
    work = Path(g['work_dir'])
    prepare_work(folder, g['title_id'], work)
    return rest if work == folder / f"{g['title_id']}_build" else ['--work-dir', str(work), *rest]


def cmd_build(args, rest):
    folder = Path(args.folder).expanduser().resolve()
    if not folder.is_dir(): raise CliError(f'no such folder: {folder}')
    keys = []
    if args.keys: keys = ['-k', str(Path(args.keys).expanduser())]
    elif (k := default_keys()) is not None: keys = ['-k', str(k)]
    rest = with_work_dir(folder, rest)
    cmd = [sys.executable, str(ROOT / 'scripts' / 'build_ipa_from_nsp.py'), str(folder), *keys, *TARGETS[args.target], *rest]
    sys.stdout.flush()
    os.execv(sys.executable, cmd)


# ---- devices, install ----

def cmd_devices(args):
    import device_install as di
    try: devices, teams = di.list_devices(), di.signing_teams()
    except di.InstallError as e: raise CliError(str(e)) from e
    if args.json:
        print(json.dumps({'version': 1, 'devices': devices, 'teams': teams}, ensure_ascii=False, indent=1)); return 0
    how = {'cable': 'connected by cable', 'network': 'on the network', 'none': 'not reachable now'}
    for d in devices:
        mode = '' if d['developer_mode'] is not False else ', Developer Mode off'
        print(f"{d['name']}: {d['model'] or d['kind']}, {d['os']}, {how[d['connection']]}{mode}  [{d['udid']}]")
    if not devices: print('No paired iPhone or iPad. Connect one with a cable, unlock it and choose Trust.')
    print()
    for t in teams: print(f"team {t['id']}: {t['name']} ({t['identity']})")
    if not teams: print('No Apple development certificate on this Mac: sign in with your Apple ID in Xcode › Settings › Accounts, then Manage Certificates › + › Apple Development.')
    return 0


def cmd_install(args, rest):
    import device_install as di
    folder = Path(args.folder).expanduser().resolve()
    if not folder.is_dir(): raise CliError(f'no such folder: {folder}')
    if '--work-dir' in rest:   # the build folder is the one the packing script is told to use
        at = rest.index('--work-dir')
        if at + 1 >= len(rest): raise CliError('--work-dir needs a folder')
        work = Path(rest[at + 1]).expanduser().resolve()
    else:
        with contextlib.redirect_stdout(sys.stderr):
            g = scan_game(folder)
        if not g or g['kind'] == 'archives': raise CliError(f'no game in {folder}')
        work = Path(g['work_dir'])
        prepare_work(folder, g['title_id'], work)
        if work != folder / f"{g['title_id']}_build": rest = ['--work-dir', str(work), *rest]   # device_install hands rest to the build script
    keys = Path(args.keys).expanduser() if args.keys else default_keys()
    try:
        return di.install(folder, work, build_args=rest, keys=keys, device=args.device, team=args.team, files=args.files, icloud_container=args.icloud_container or '',
                          launch=args.launch, as_json=args.progress == 'json', api_key=args.api_key, api_key_id=args.api_key_id, api_issuer=args.api_issuer)
    except di.InstallError as e:
        if args.progress == 'json': print(json.dumps({'ev': 'say', 't': round(time.time(), 3), 'msg': f'[RED] {e}'}, ensure_ascii=False), flush=True)
        raise CliError(str(e)) from e


# ---- move-build ----

class MoveReport:   # move-build's events: --progress json as the build script writes them (docs/frontends.md), else plain lines
    def __init__(self, as_json, n):
        self.as_json, self.n, self.k, self.name, self.t0, self.last = as_json, n, 0, '', time.time(), 0.0

    def emit(self, ev, **fields): print(json.dumps({'ev': ev, 't': round(time.time(), 3), **fields}, ensure_ascii=False), flush=True)

    def say(self, msg):
        if self.as_json: self.emit('say', msg=msg)
        else: print(msg, flush=True)

    def stage(self, name, step=''):
        self.k += 1; self.name, self.t0, self.last = name, time.time(), 0.0
        if self.as_json: self.emit('stage', k=self.k, n=self.n, name=name, step=step)
        else: print(f'[{self.k}/{self.n}] {name}', flush=True)

    def progress(self, done, total, step, force=False):
        now = time.time()
        if not force and now - self.last < 0.5: return
        self.last = now
        elapsed = now - self.t0
        eta = (total - done) * elapsed / done if done and total and elapsed > 2 else None
        if self.as_json:
            self.emit('progress', k=self.k, name=self.name, step=step, done=done, total=total, unit='B', est=False, note='',
                      frac=min(done / total, 0.99) if total else None, eta=round(eta) if eta is not None else None, elapsed=round(elapsed, 1))

    def end(self, ok, summary=''):
        if self.as_json: self.emit('stage_end', k=self.k, name=self.name, ok=ok, summary=summary, elapsed=round(time.time() - self.t0, 1))
        elif summary: print(f'      {summary}', flush=True)


def tree_listing(root):   # {relative path: size of a file, or 'link:<target>', or 'dir'} of a folder, a bundle or one file
    root = Path(root)
    if root.is_symlink() or root.is_file(): return {'.': f'link:{os.readlink(root)}' if root.is_symlink() else root.stat().st_size}
    out: dict[str, int | str] = {'.': 'dir'}
    for d, dirs, files in os.walk(root):
        for name in dirs + files:
            p = Path(d) / name
            rel = str(p.relative_to(root))
            if p.is_symlink(): out[rel] = f'link:{os.readlink(p)}'
            elif p.is_dir(): out[rel] = 'dir'
            else: out[rel] = p.stat().st_size
    return out


def copy_file(src, dst, on_bytes):   # one file, its data in 8 MB pieces so a large one (a game's RomFS image) reports its progress; then its mode and times
    with open(src, 'rb') as f, open(dst, 'wb') as g:
        while chunk := f.read(8 << 20):
            g.write(chunk); on_bytes(len(chunk))
    with contextlib.suppress(OSError): shutil.copystat(src, dst)   # a network share may refuse some of it; the data is what counts


def network_share(path):   # whether path is on a network share (smbfs, afpfs, nfs, webdav), from mount's list
    v = str(volume_of(path))
    if v == '/': return False
    try: out = subprocess.run(['/sbin/mount'], capture_output=True, text=True, timeout=10).stdout
    except (OSError, subprocess.SubprocessError): return False
    return any(re.search(rf' on {re.escape(v)} \((smbfs|afpfs|nfs|webdav)', line) for line in out.splitlines())


def keeps_links(folder):
    """Whether a disk keeps symbolic links. Not a network share: on an SMB share (macOS smbfs) a link read back right after it was made, and a few seconds
    later, with other files written beside it, lstat still called it a link and readlink refused it (EINVAL). The builds AetherNX makes have none"""
    if network_share(folder): return False
    t = Path(folder) / f'.aethernx-link-test-{os.getpid()}'
    try:
        os.symlink('aethernx', t)
        return os.readlink(t) == 'aethernx'
    except OSError: return False
    finally:
        with contextlib.suppress(OSError): t.unlink()


def tree_bytes(root):   # the bytes in a folder being written by another process: a file that goes away while it is counted (ditto's .BC.T_ temporaries) counts 0
    total = 0
    for d, _, files in os.walk(root):
        for name in files:
            with contextlib.suppress(OSError): total += os.lstat(os.path.join(d, name)).st_size
    return total


def copy_tree(src, dst, on_bytes, jobs=8):
    """A folder, keeping its links as links: the folders and links first, then the files, several at a time (on a network share each file costs round
    trips, and a build folder holds thousands: 2,000 shader files one by one took most of five minutes over SMB)"""
    if src.is_symlink(): os.symlink(os.readlink(src), dst); return
    if src.is_file(): copy_file(src, dst, on_bytes); return
    import concurrent.futures
    import threading
    lock = threading.Lock()
    def counted(n):
        with lock: on_bytes(n)
    dst.mkdir()
    todo, links = [], []
    for d, dirs, files in os.walk(src):
        here = dst / Path(d).relative_to(src)
        for name in dirs + files:
            q = Path(d) / name
            if q.is_symlink(): links.append((os.readlink(q), here / name))
            elif q.is_dir(): (here / name).mkdir()
            else: todo.append((q, here / name))
        dirs[:] = [n for n in dirs if not (Path(d) / n).is_symlink()]
    with concurrent.futures.ThreadPoolExecutor(jobs) as pool:
        for f in [pool.submit(copy_file, a, b, counted) for a, b in todo]: f.result()   # the first failure stops the move
    # The links last, one at a time, each read back: on an SMB share (macOS smbfs) a link made while other writes run stayed a stub that lstat calls a
    # link and readlink refuses (EINVAL), 2,000 parallel file copies beside it; made alone afterwards, it holds
    for target, path in links:
        os.symlink(target, path)
        if os.readlink(path) != target: raise OSError(errno.EIO, f'the link {path.name} does not read back')


def copy_bundle(src, dst, on_bytes):   # an app with ditto, which keeps all of a signed bundle; its progress from the size copied so far
    proc = subprocess.Popen(['/usr/bin/ditto', str(src), str(dst)], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    seen = 0
    while proc.poll() is None:
        time.sleep(1)
        now = tree_bytes(dst) if dst.exists() else 0
        if now > seen: on_bytes(now - seen); seen = now
    if proc.returncode: raise CliError(f'ditto could not copy {src.name}: {(proc.stderr.read() if proc.stderr else "").strip()[-300:]}')
    total = tree_bytes(dst)
    if total > seen: on_bytes(total - seen)


def cmd_move_build(args):
    """Moves a game's build folder, and the Mac apps and IPAs beside it, to the builds folder (--to, else AETHERNX_BUILDS), or back beside the game (--here).
    Copies, compares the copy with the original file by file, then deletes the original and records where the build is (BUILD_POINTER). Stopped or failed, the
    copy is removed and the original stays as it was"""
    rep = MoveReport(args.progress == 'json', 3)
    folder = Path(args.folder).expanduser().resolve()
    if not folder.is_dir(): raise CliError(f'no such folder: {folder}')
    with contextlib.redirect_stdout(sys.stderr): g = scan_game(folder)
    if not g or not g.get('title_id'): raise CliError(f'no game in {folder}')
    tid, src = g['title_id'], Path(g['work_dir'])
    if not g['work_reachable']: raise CliError(f'the build of {g["name"]} is on {volume_of(src).name}, which is not connected')
    if not src.is_dir(): raise CliError(f'{g["name"]} has no build to move yet: its next build goes to {wanted_work(folder, tid)}')
    if args.here: dst = folder / f'{tid}_build'
    else:
        root = Path(args.to).expanduser().absolute() if args.to else builds_root()
        if not root: raise CliError('no builds folder: give --to <folder> (or set AETHERNX_BUILDS), or --here to move the build back beside the game')
        dst = wanted_work(folder, tid, root)
    if dst == src:
        rep.say(f'the build of {g["name"]} is in {dst} already'); return 0
    if not reachable(dst): raise CliError(f'{volume_of(dst).name} is not connected')
    beside = [Path(a) for a in g['mac_apps'] + g['ipas'] if Path(a).parent == src.parent]
    moves = [(src, dst)] + [(a, dst.parent / a.name) for a in beside]
    for a, b in moves:
        if b.exists() or b.is_symlink(): raise CliError(f'{b} is there already: remove it, or move the build somewhere else')
    for a in beside:
        if a.suffix == '.app' and subprocess.run(['/usr/bin/pgrep', '-f', str(a / 'Contents' / 'MacOS')], capture_output=True).returncode == 0:
            raise CliError(f'{a.name} is open: quit it, then move the build')
    listings = {a: tree_listing(a) for a, _ in moves}
    total = sum(v for lst in listings.values() for v in lst.values() if isinstance(v, int))
    base = dst.parent
    while not base.exists(): base = base.parent
    free = shutil.disk_usage(base).free
    if free < total + (1 << 30): raise CliError(f'{volume_of(dst).name} has {free / 1e9:.1f} GB free; the build and its apps need {total / 1e9:.1f} GB')
    new_parent = not dst.parent.exists()
    dst.parent.mkdir(parents=True, exist_ok=True)
    links = sum(1 for lst in listings.values() for v in lst.values() if isinstance(v, str) and v.startswith('link:'))
    if links and not keeps_links(dst.parent):
        if new_parent:
            with contextlib.suppress(OSError): dst.parent.rmdir()
        raise CliError(f'{volume_of(dst).name} does not keep symbolic links reliably (a network share), and the build has {links}: choose a folder on a drive')
    made = []
    def stop(signum, frame): raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, stop)
    where = 'beside the game' if args.here else f'to {dst.parent}'
    try:
        rep.stage(f'copy the build {where}', step=f'{total / 1e9:.1f} GB')
        done = 0
        def on_bytes(n):
            nonlocal done
            done += n; rep.progress(done, total, 'copying')
        for a, b in moves:
            made.append(b)
            (copy_bundle if a.suffix == '.app' else copy_tree)(a, b, on_bytes)
        rep.progress(total, total, 'copied', force=True)
        rep.end(True, f'{total / 1e9:.1f} GB')
        rep.stage('check the copy', step='every file and its size')
        for a, b in moves:
            got = tree_listing(b)
            if got != listings[a]:
                diff = sorted(set(got.items()) ^ set(listings[a].items()))[:3]
                raise CliError(f'the copy of {a.name} differs from the original ({", ".join(f"{k}: {v}" for k, v in diff)}); the original is unchanged')
        rep.end(True, f'{sum(len(lst) for lst in listings.values()):,} items match')
    except BaseException as e:
        for b in made:
            with contextlib.suppress(OSError):
                if b.is_dir() and not b.is_symlink(): shutil.rmtree(b)
                else: b.unlink()
        if new_parent:
            with contextlib.suppress(OSError): dst.parent.rmdir()   # the game's folder on that disk, made for this move and empty again
        if isinstance(e, OSError): raise CliError(f'the copy to {volume_of(dst).name} stopped ({e.strerror or e}); the original is unchanged') from e
        raise
    finally:
        signal.signal(signal.SIGTERM, signal.SIG_DFL)
    rep.stage('remove the original')
    record_work(folder, tid, dst)   # from here the scan finds the copy, whatever the removal leaves
    left = []
    for a, _ in moves:
        try:
            if a.is_dir() and not a.is_symlink(): shutil.rmtree(a)
            else: a.unlink()
        except OSError as e: left.append(f'{a} ({e.strerror})')
    if not left and src.parent != folder:
        with contextlib.suppress(OSError): src.parent.rmdir()   # the game's folder on the disk it left, empty now
    rep.end(not left, 'removed' if not left else f'not all removed: {"; ".join(left)}')
    if left: rep.say(f'[RED] the build is now in {dst}, but these could not be removed: {"; ".join(left)}'); return 1
    rep.say(f'the build of {g["name"]} is now in {dst}')
    return 0


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


# ---- report ----

def cmd_report(args):
    cmd = [sys.executable, str(ROOT / 'scripts' / 'bug_report.py'), args.target]
    if args.ios_log: cmd += ['--ios-log', args.ios_log]
    if args.out: cmd += ['--out', args.out]
    sys.stdout.flush()
    os.execv(sys.executable, cmd)


# ---- setup ----

def cmd_setup(args):
    if sys.version_info < (3, 12): raise CliError(f'Python 3.12 or later is needed, this is {platform.python_version()} ({sys.executable})')
    venv = ROOT / '.venv'
    py = venv / 'bin' / 'python3'
    if not py.exists():
        print(f'creating {venv}', file=sys.stderr)
        subprocess.run([sys.executable, '-m', 'venv', str(venv)], check=True)
    pkgs = ['-r', str(ROOT / 'scripts' / 'requirements.txt')] + (['-r', str(ROOT / 'scripts' / 'requirements-tools.txt')] if args.tools else [])   # pinned: the versions the tools are tested with
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


# What each check is for, in a sentence a player reads before installing anything (Studio shows its own translation, by the check's key), and how a front end
# can install it without a terminal: "brew:<formula>", "cask:<cask>", "run:<command> <args>" (no administrator password), "open:<url>", or "" (only by hand:
# the fix says how). docs/frontends.md, The setup check.
WHY = {
    'xcode': 'Apple\'s developer app: it compiles the engine and the Metal shaders, and signs and installs the iPhone and iPad apps. Free from the App Store.',
    'xcode-select': 'The command-line tools must be Xcode\'s own, not the smaller Command Line Tools package, which has no Metal compiler and no iOS SDK.',
    'xcode-license': 'Xcode does nothing from the command line until its license is accepted and its first-launch components are installed.',
    'metal-toolchain': 'Compiles the translated shaders into Metal libraries for Apple GPUs. Xcode downloads it as a separate component.',
    'metal-compiler': 'The shaders are tested with one version of Apple\'s Metal compiler: another one could make wrong pictures, so the build checks it.',
    'ios-sdk': 'Needed only for iPhone and iPad builds: the system libraries the app is compiled against.',
    'git': 'Downloads AetherNX and its updates, and the engine\'s parts kept in other repositories. It comes with Xcode.',
    'homebrew': 'The package manager that installs the open-source tools below (Python, zstd, glslang…) with one command, and updates them.',
    'python': 'The build scripts are written in Python: it unpacks the game, rewrites its code and translates the shaders.',
    'python-arm64': 'An Intel Python runs under Rosetta and is several times slower at the long steps.',
    'lz4': 'Decompresses the code modules of the games.',
    'fonttools': 'Converts the system fonts the games ask for.',
    'capstone': 'Disassembles the game code, so the rewriter knows what it is changing.',
    'zstd-python': 'Reads and writes zstd-compressed data in the game files and the shader cache.',
    'nsz': 'Only for compressed packages (.nsz, .xcz): turns them into plain ones.',
    'zbic': 'Decrypts the files of games made with the console\'s system 22.0.0 or later; the build uses it for every game.',
    'dotnet': 'Runs the shader translator of this engine version.',
    'zstd': 'Compresses and decompresses the game data and the caches quickly.',
    'glslang': 'Checks and compiles the shaders of games that use Vulkan or OpenGL.',
    'xcodegen': 'Only for iPhone and iPad builds: writes the Xcode project the app is signed with.',
    'archives': 'Only for games kept in RAR or 7z archives: extracts them (zip and tar work without it).',
    'afcclient': 'Optional, for iPhone and iPad: copies a large game to the device over the cable at full speed, once, so later installs do not copy it again.',
    'signing': 'Optional, for iPhone and iPad: the certificate that signs the apps with your own Apple team. Xcode makes it when you sign in with your Apple ID.',
    'keys': 'Your prod.keys, dumped from your own Switch: they decrypt the game packages. Never uploaded, never put in the apps.',
    'nxrt': 'For developers: the static recompiler that translates a module to C.',
    'nnheaders': 'For developers: the SDK headers of the decompilation project.',
    'sead': 'For developers: the headers of Nintendo\'s sead library.',
    'unicorn': 'For developers: the CPU emulator nxrt uses.',
}


def doctor():
    checks = []
    def check(key, group, name, ok, detail='', fix='', required=True, install=''):
        checks.append({'key': key, 'group': group, 'name': name, 'ok': bool(ok), 'required': required, 'detail': detail, 'fix': fix,
                       'why': WHY.get(key, ''), 'install': '' if ok else install})
    brew = shutil.which('brew') or next((b for b in ('/opt/homebrew/bin/brew', '/usr/local/bin/brew') if os.access(b, os.X_OK)), None)
    def via_brew(formula, cask=False):
        return (f'cask:{formula}' if cask else f'brew:{formula}') if brew else ''

    code, out = run_out(['xcodebuild', '-version'])
    xcode = out.splitlines()[0] if code == 0 and out else ''
    check('xcode', 'Xcode', 'Xcode', code == 0, xcode or out[-200:], 'install Xcode 27.2 from the App Store, open it once, then: sudo xcode-select -s /Applications/Xcode.app',
          install='open:macappstore://apps.apple.com/app/id497799835')
    _, selected = run_out(['xcode-select', '-p'])
    check('xcode-select', 'Xcode', "Xcode's command-line tools selected", '.app/' in selected, selected or 'none',
          'sudo xcode-select -s /Applications/Xcode.app (in Terminal: it asks for your password)')
    if code == 0:
        lcode, lout = run_out(['xcodebuild', '-checkFirstLaunchStatus'], timeout=60)
        check('xcode-license', 'Xcode', 'Xcode license and first launch', lcode == 0, '', 'open Xcode once and accept its license (or, in Terminal: sudo xcodebuild -runFirstLaunch)')
    check('metal-toolchain', 'Xcode', 'Metal toolchain', run_out(['xcrun', '-sdk', 'macosx', 'metal', '--version'])[0] == 0, '', 'xcodebuild -downloadComponent MetalToolchain',
          install='run:xcodebuild -downloadComponent MetalToolchain')
    # The Metal compiler the shaders were tested with (dmsh_chain.lock): another one stops an NVN game's build before its shader steps, so "ready" must not be said without it.
    # own_compilers.py's own stop message is the fix: it names the Xcode to install and --allow-other-metal (DM_ALLOW_OTHER_METAL=1 here passes the check, as it passes the build)
    if code == 0:
        mcode, mout = run_out([sys.executable, str(ROOT / 'dm' / 'gfx' / 'tools' / 'own_compilers.py'), '--check-metal'], timeout=60)
        check('metal-compiler', 'Xcode', "Metal compiler of the tested shaders (NVN games)", mcode == 0, '', '' if mcode == 0 else mout[-600:] or 'python3 dm/gfx/tools/own_compilers.py --check-metal failed')
    check('ios-sdk', 'Xcode', 'iOS SDK (iPhone and iPad builds)', run_out(['xcrun', '--sdk', 'iphoneos', '--show-sdk-version'])[0] == 0, '', 'Xcode → Settings → Components → iOS',
          required=False, install='run:xcodebuild -downloadPlatform iOS')
    gcode, gout = run_out(['git', '--version'])
    check('git', 'Tools', 'Git', gcode == 0, gout if gcode == 0 else 'not found', 'install Xcode (it brings Git), or: xcode-select --install')
    check('homebrew', 'Tools', 'Homebrew', brew, brew or 'not found', 'install it from https://brew.sh (one command in Terminal; it asks for your password)',
          required=False, install='open:https://brew.sh')

    pip = f'{sys.executable} -m pip install' if not (ROOT / '.venv').exists() else f'{ROOT}/.venv/bin/pip install'
    check('python', 'Python', f'Python {platform.python_version()}', sys.version_info >= (3, 12), sys.executable, 'brew install python, then ./aethernx setup', install=via_brew('python'))
    rosetta = run_out(['sysctl', '-n', 'sysctl.proc_translated'])[1] == '1'
    check('python-arm64', 'Python', 'Native arm64 Python', not rosetta, platform.machine(), 'use an Apple-silicon Python (/opt/homebrew/bin/python3), not an Intel one')
    for mod, label, key in (('lz4.block', 'lz4', 'lz4'), ('fontTools', 'fonttools', 'fonttools')):
        check(key, 'Python', label, importable(mod), '', f'./aethernx setup (or {pip} {label})', install='run:./aethernx setup')
    cap, cap_version = None, 'missing'
    if importable('capstone'):
        import capstone
        cap, cap_version = capstone.cs_version()[0], capstone.__version__
    check('capstone', 'Python', 'capstone 5', cap == 5, cap_version, f'{pip} "capstone>=5,<6"', install='run:./aethernx setup')
    check('zstd-python', 'Python', 'zstd', importable('compression.zstd') or importable('backports.zstd'), '', f'{pip} backports.zstd', install='run:./aethernx setup')
    check('nsz', 'Python', 'nsz (for .nsz / .xcz packages)', importable('nsz') or shutil.which('nsz'), '', f'{pip} nsz', required=False, install='run:./aethernx setup')
    check('zbic', 'Python', 'zbic (for games built with system 22.0.0 or later; the build needs it for every game)', importable('zbic'), '', f'{pip} zbic', install='run:./aethernx setup')

    for key, tool, formula, cask, req in (('dotnet', 'dotnet', 'dotnet-sdk', True, True), ('zstd', 'zstd', 'zstd', False, True), ('glslang', 'glslangValidator', 'glslang', False, True),
                                          ('xcodegen', 'xcodegen', 'xcodegen', False, False)):
        found = shutil.which(tool)
        check(key, 'Tools', tool, found, found or 'not found', f'brew install {"--cask " if cask else ""}{formula}', required=req, install=via_brew(formula, cask))
    arch = shutil.which('7zz') or shutil.which('7z') or shutil.which('unar')
    check('archives', 'Tools', '7-Zip or unar (RAR 5 archives)', arch, arch or 'zip and tar archives still work', 'brew install sevenzip', required=False, install=via_brew('sevenzip'))

    afc = shutil.which('afcclient')
    check('afcclient', 'iPhone and iPad', 'afcclient (libimobiledevice)', afc, afc or 'not found: large games are copied inside the app at every install',
          'brew install libimobiledevice', required=False, install=via_brew('libimobiledevice'))
    _, idents = run_out(['/usr/bin/security', 'find-identity', '-v', '-p', 'codesigning'])
    dev = re.findall(r'"((?:Apple Development|iPhone Developer)[^"]*)"', idents)
    check('signing', 'iPhone and iPad', 'Apple Development certificate', dev, f'{len(set(dev))} found' if dev else 'none on this Mac',
          'sign in with your Apple ID in Xcode › Settings › Accounts, then Manage Certificates › + › Apple Development', required=False)

    keys = default_keys()
    check('keys', 'Keys', 'prod.keys', keys and keys.is_file(), str(keys) if keys else 'not in ~/.switch/prod.keys',
          'put your prod.keys in ~/.switch/prod.keys, set AETHERNX_KEYS, or pass -k (Studio: Settings → Keys)', required=False)

    for sub, use in (('nxrt', 'lift'), ('nnheaders', 'decomp-init headers'), ('sead', 'decomp-init headers')):
        present = any((ROOT / 'vendor' / sub).iterdir()) if (ROOT / 'vendor' / sub).is_dir() else False
        check(sub, 'Developer tools', f'vendor/{sub} ({use})', present, '', f'git submodule update --init --depth 1 vendor/{sub}', required=False,
              install=f'run:git submodule update --init --depth 1 vendor/{sub}')
    check('unicorn', 'Developer tools', 'unicorn (lift)', importable('unicorn'), '', './aethernx setup --tools', required=False, install='run:./aethernx setup --tools')
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
        if not c['ok'] and c['why']: print(f'      why: {c["why"]}')
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
    p = sub.add_parser('devices', help='the iPhones and iPads paired with this Mac, and the Apple teams it can sign with', allow_abbrev=False)
    p.add_argument('--json', action='store_true')
    p = sub.add_parser('install', help='build a game, sign it with your Apple team and install it on a paired iPhone or iPad (other options go to scripts/build_ipa_from_nsp.py)',
                       allow_abbrev=False)
    p.add_argument('folder', help="the game's folder: base game, update and DLC packages")
    p.add_argument('--device', help='the device: its UDID or its name (default: the only one connected; ./aethernx devices lists them)')
    p.add_argument('--team', help='your Apple team ID (default: $AETHERNX_TEAM, else the team this game was last signed with, else the only one with a certificate on this Mac)')
    p.add_argument('--files', choices=('auto', 'bundle', 'separate'), default='auto',
                   help='auto = separate on a cable with afcclient, else bundle (default); bundle = the game files inside the app; separate = a small app, and the files copied '
                        'to its Documents once, and not again while they are the same')
    p.add_argument('--icloud-container', help='sign with this iCloud container for automatic iCloud saves (your team must own it: iCloud.<…>); without it, choose a cloud saves folder in the app')
    p.add_argument('--launch', action='store_true', help='open the game on the device once it is installed')
    p.add_argument('--progress', choices=('plain', 'json'), default='plain', help='json = one JSON event per line, as the build script writes them (docs/frontends.md)')
    p.add_argument('-k', '--keys', help='your prod.keys (default: $AETHERNX_KEYS, else ~/.switch/prod.keys)')
    p.add_argument('--api-key', help='an App Store Connect API key file (AuthKey_<ID>.p8) for signing, when Xcode has no Apple ID signed in (default: $AETHERNX_ASC_KEY)')
    p.add_argument('--api-key-id', help="the API key's ID (default: from the file's name, else $AETHERNX_ASC_KEY_ID)")
    p.add_argument('--api-issuer', help="the API key's issuer ID (default: $AETHERNX_ASC_ISSUER)")
    p = sub.add_parser('move-build', help="move a game's build folder and Mac apps to the builds folder ($AETHERNX_BUILDS), or back beside the game", allow_abbrev=False)
    p.add_argument('folder', help="the game's folder")
    p.add_argument('--to', help='the builds folder to move it to (default: $AETHERNX_BUILDS)')
    p.add_argument('--here', action='store_true', help='move it back beside the game')
    p.add_argument('--progress', choices=('plain', 'json'), default='plain', help='json = one JSON event per line, as the build script writes them (docs/frontends.md)')
    p = sub.add_parser('decomp-init', help='function and symbol tables of an extracted game', allow_abbrev=False)
    p.add_argument('folder')
    p.add_argument('--json', action='store_true')
    p = sub.add_parser('lift', help='translate an extracted module to C with nxrt', allow_abbrev=False)
    p.add_argument('folder')
    p.add_argument('--module', default='main', help='the ExeFS module (default: main)')
    p.add_argument('--limit', type=int, default=0, help='at most this many functions (for a quick test)')
    p.add_argument('--json', action='store_true')
    p = sub.add_parser('report', help='a zip for a bug report: logs, versions and settings, never game data', allow_abbrev=False)
    p.add_argument('target', help="the game's folder, its title ID or its Mac app")
    p.add_argument('--ios-log', metavar='FILE', help='log.txt from the iPhone or iPad (Files app)')
    p.add_argument('--out', metavar='FILE', help='the zip to write (default: HorizonNative-report-<title ID>-<date>.zip here)')
    p = sub.add_parser('setup', help='create .venv and install the Python packages', allow_abbrev=False)
    p.add_argument('--tools', action='store_true', help='also the packages the developer tools need (unicorn, numpy: scripts/requirements-tools.txt)')
    p = sub.add_parser('doctor', help='check the tools and files a build needs', allow_abbrev=False)
    p.add_argument('--json', action='store_true')
    p = sub.add_parser('studio', help='build (once) and open AetherNX Studio', allow_abbrev=False)
    p.add_argument('--rebuild', action='store_true')
    sub.add_parser('version', help='print the version')
    sub.add_parser('help', help='show this help')

    args, rest = ap.parse_known_args(argv)
    if rest and args.cmd not in ('build', 'install'): ap.error(f'unrecognized arguments: {" ".join(rest)}')
    if args.cmd in (None, 'help'): ap.print_help(); return 0
    if args.cmd == 'version': print(f'AetherNX {VERSION}'); return 0
    try:
        if args.cmd == 'build': return cmd_build(args, rest)
        if args.cmd == 'install': return cmd_install(args, rest)
        return {'devices': cmd_devices, 'report': cmd_report, 'scan': cmd_scan, 'unpack': cmd_unpack, 'decomp-init': cmd_decomp_init, 'lift': cmd_lift, 'setup': cmd_setup,
                'doctor': cmd_doctor, 'studio': cmd_studio, 'move-build': cmd_move_build}[args.cmd](args)
    except CliError as e:
        if args.cmd == 'move-build' and args.progress == 'json': print(json.dumps({'ev': 'say', 't': round(time.time(), 3), 'msg': f'[RED] {e}'}, ensure_ascii=False), flush=True)
        print(f'aethernx: {e}', file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        return 130


if __name__ == '__main__':
    sys.exit(main())
