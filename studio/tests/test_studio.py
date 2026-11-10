"""Compile AetherNX Studio's sources as a library and run studio_check.swift against them: the Danger Zone's removal plan, the folders it
never removes whole, the build command, commands the app waits for, and the release archives its updater unpacks; and check that every string
the app shows has its Italian. Synthetic folders and archives only: no window, network or game files."""
import json
from pathlib import Path
import plistlib
import re
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
import unittest
import zipfile
import zlib

STUDIO = Path(__file__).resolve().parents[1]
TITLE = '0100000000990000'
TARGET = 'arm64-apple-macos26.0'   # studio/build.sh's


def write_plist(path, values):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, 'wb') as f:
        plistlib.dump(values, f)


def make_library(dz):
    """A game whose packages lie at the top of a library folder, beside the app of another game, an archive and an IPA."""
    lib = dz / 'lib'
    lib.mkdir(parents=True)
    (lib / f'Stray [{TITLE}].nsp').write_bytes(b'NSP0')
    (lib / 'random.zip').write_bytes(b'PK')
    write_plist(lib / 'Game.app/Contents/Info.plist', {'CFBundleIdentifier': f'io.github.icosisenpai.horizonnative.{TITLE}', 'DMTitleID': TITLE})
    (lib / 'Game.app.key').write_text('key\n')
    write_plist(lib / 'Other.app/Contents/Info.plist', {'CFBundleIdentifier': 'com.example.otherapp', 'DMTitleID': '0100000000880000'})
    (lib / 'some.ipa').write_bytes(b'PK')
    (lib / f'{TITLE}-work').mkdir()
    (dz / 'save' / TITLE).mkdir(parents=True)
    (dz / 'logs').mkdir()
    (dz / 'logs' / f'{TITLE}.log').write_text('log\n')
    (dz / 'logs' / f'{TITLE}.prev.log').write_text('previous log\n')
    (dz / 'link-to-lib').symlink_to(lib)


def make_volumes(parts):
    parts.mkdir()
    for name in ['Big.part1.rar', 'Big.part2.rar', 'Big.part10.rar', 'Bigger.part1.rar', 'Old.rar', 'Old.r00', 'Old.r01', 'Set.7z.001', 'Set.7z.002',
                 'Set2.7z.001', 'Single.zip']:
        (parts / name).write_bytes(b'x')


def local_header(name, data, method=0, flags=0, crc=None, packed=None, size=None):
    """One local file header and its data, sizes in the header."""
    crc = zlib.crc32(data) if crc is None else crc
    return struct.pack('<IHHHHHIIIHH', 0x04034b50, 20, flags, method, 0, 0x21, crc, len(data) if packed is None else packed,
                       len(data) if size is None else size, len(name), 0) + name + data


def central_record(name, data, offset, method=0, crc=None, packed=None, size=None, mode=0o100644):
    crc = zlib.crc32(data) if crc is None else crc
    return struct.pack('<IHHHHHHIIIHHHHHII', 0x02014b50, 0x0314, 20, 0, method, 0, 0x21, crc, len(data) if packed is None else packed,
                       len(data) if size is None else size, len(name), 0, 0, 0, 0, mode << 16, offset) + name


def end_record(count, directory_size, directory_offset):
    return struct.pack('<IHHHHIIH', 0x06054b50, 0, 0, count, count, directory_size, directory_offset, 0)


def deflate(data):
    packer = zlib.compressobj(9, zlib.DEFLATED, -15)
    return packer.compress(data) + packer.flush()


def make_archives(folder):
    """good-*.zip must be accepted and bad-*.zip refused."""
    folder.mkdir()
    app = folder / 'src/AetherNX.app'
    write_plist(app / 'Contents/Info.plist', {'CFBundleIdentifier': 'io.github.icosisenpai.aethernx', 'CFBundleShortVersionString': '9.9.9'})
    (app / 'Contents/MacOS').mkdir(parents=True)
    (app / 'Contents/MacOS/AetherNX').write_bytes(b'#!/bin/sh\n' * 50)
    (app / 'Contents/MacOS/AetherNX').chmod(0o755)
    (app / 'Contents/Resources').mkdir()
    (app / 'Contents/Resources/empty').write_bytes(b'')
    subprocess.run(['xattr', '-w', 'com.example.note', 'x', str(app / 'Contents/Info.plist')], check=True)   # metadata ditto puts under __MACOSX
    # The release format (studio/release.sh): data descriptors, deflate, empty files stored
    subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(app), str(folder / 'good-ditto.zip')], check=True)
    release = (folder / 'good-ditto.zip').read_bytes()

    def write(name, entries, comment=b''):
        with zipfile.ZipFile(folder / name, 'w', zipfile.ZIP_DEFLATED) as z:
            z.comment = comment
            for entry in entries:
                if isinstance(entry, tuple):
                    info = zipfile.ZipInfo(entry[0])
                    info.create_system = 3
                    info.external_attr = entry[1] << 16
                    z.writestr(info, entry[2])
                else:
                    z.writestr(entry, b'data')

    write('good-python.zip', [('AetherNX.app/', stat.S_IFDIR | 0o755, b''), 'AetherNX.app/Contents/Info.plist', '__MACOSX/AetherNX.app/._x'], comment=b'a comment')
    write('bad-dotdot.zip', ['AetherNX.app/ok', 'AetherNX.app/../../escape'])
    write('bad-absolute.zip', ['/tmp/escape'])
    write('bad-dot.zip', ['AetherNX.app/./x'])
    write('bad-empty-part.zip', ['AetherNX.app//x'])
    write('bad-backslash.zip', ['AetherNX.app\\..\\..\\escape'])
    write('bad-outside.zip', ['AetherNX.app/ok', 'Other/thing'])
    write('bad-symlink.zip', [('AetherNX.app/link', stat.S_IFLNK | 0o755, b'/tmp'), 'AetherNX.app/link/escape'])
    write('bad-no-entries.zip', [])
    with zipfile.ZipFile(folder / 'bad-zip64.zip', 'w') as z:
        with z.open('AetherNX.app/big', 'w', force_zip64=True) as f:
            f.write(b'data')
    (folder / 'bad-truncated.zip').write_bytes(release[:-10])
    (folder / 'bad-trailing.zip').write_bytes(release + b'junk')
    (folder / 'bad-not-a-zip.zip').write_bytes(b'not an archive at all, but longer than an end record')

    # The central directory names one file, the local header another of the same length: ditto names the entry from the local header
    first = local_header(b'AetherNX.app/../../escape', b'evil')
    directory = central_record(b'AetherNX.app/' + b'x' * 12, b'evil', 0)
    (folder / 'bad-name-mismatch.zip').write_bytes(first + directory + end_record(1, len(directory), len(first)))

    # A local entry the central directory leaves out: ditto unpacks it anyway
    ok = local_header(b'AetherNX.app/ok', b'ok')
    hidden = local_header(b'AetherNX.app/../../escape', b'evil')
    directory = central_record(b'AetherNX.app/ok', b'ok', 0)
    body = ok + hidden
    (folder / 'bad-hidden-entry.zip').write_bytes(body + directory + end_record(1, len(directory), len(body)))

    # A deflate stream that ends before its record's compressed size, a local header hidden in the rest: a reader that finds the end by
    # inflating reads that header next
    stream = deflate(b'ok') + local_header(b'AetherNX.app/../../escape', b'evil')
    early = local_header(b'AetherNX.app/ok', stream, method=8, crc=zlib.crc32(b'ok'), size=2)
    directory = central_record(b'AetherNX.app/ok', stream, 0, method=8, crc=zlib.crc32(b'ok'), size=2)
    (folder / 'bad-deflate-ends-early.zip').write_bytes(early + directory + end_record(1, len(directory), len(early)))

    # The same layout with a stream that does end on its last byte is fine
    stream = deflate(b'ok')
    exact = local_header(b'AetherNX.app/ok', stream, method=8, crc=zlib.crc32(b'ok'), size=2)
    directory = central_record(b'AetherNX.app/ok', stream, 0, method=8, crc=zlib.crc32(b'ok'), size=2)
    (folder / 'good-hand-made.zip').write_bytes(exact + directory + end_record(1, len(directory), len(exact)))

    # A local header whose sizes are not its record's
    wrong = local_header(b'AetherNX.app/ok', b'ok', packed=1)
    directory = central_record(b'AetherNX.app/ok', b'ok', 0)
    (folder / 'bad-size-mismatch.zip').write_bytes(wrong + directory + end_record(1, len(directory), len(wrong)))


def strings_keys(path):
    """The keys of a .strings file, in file order, as written (a key given twice: the later one wins, and the earlier translation is never shown)."""
    return [m.group(1) for m in re.finditer(r'^"((?:[^"\\]|\\.)*)"\s*=', path.read_text(encoding='utf-8'), re.M)]


@unittest.skipUnless(sys.platform == 'darwin' and shutil.which('xcrun') and shutil.which('ditto'), 'needs macOS and its Swift toolchain')
class StudioTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        """The app's sources compiled once as a testable library, with the keys of every localizable string the compiler finds (.stringsdata, as Xcode reads them)."""
        cls.tmp = tempfile.TemporaryDirectory()
        tmp = Path(cls.tmp.name)
        cls.library, cls.strings = tmp / 'library', tmp / 'strings'
        cls.library.mkdir(); cls.strings.mkdir()
        cls.cache = ['-module-cache-path', str(tmp / 'module-cache')]
        cls.built = subprocess.run(['xcrun', 'swiftc', '-emit-library', '-enable-testing', '-parse-as-library', '-swift-version', '5', '-target', TARGET, *cls.cache,
                                    '-module-name', 'AetherNXStudio', '-emit-module', '-emit-module-path', str(cls.library / 'AetherNXStudio.swiftmodule'),
                                    '-emit-localized-strings', '-emit-localized-strings-path', str(cls.strings),
                                    *sorted(map(str, (STUDIO / 'Sources').glob('*.swift'))), '-o', str(cls.library / 'libAetherNXStudio.dylib')],
                                   capture_output=True, text=True, timeout=900)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def setUp(self):
        self.assertEqual(self.built.returncode, 0, self.built.stdout + self.built.stderr)

    def test_studio_logic(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            fixtures = tmp / 'fixtures'
            make_library(fixtures / 'dz')
            make_volumes(fixtures / 'parts')
            make_archives(fixtures / 'archives')
            library = self.library
            check = tmp / 'studio_check'
            result = subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-target', TARGET, *self.cache, '-I', str(library), '-L', str(library), '-lAetherNXStudio',
                                     '-Xlinker', '-rpath', '-Xlinker', str(library), str(Path(__file__).with_name('studio_check.swift')), '-o', str(check)],
                                    capture_output=True, text=True, timeout=300)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            result = subprocess.run([str(check), str(fixtures)], capture_output=True, text=True, timeout=120)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('studio check: 0 failed', result.stdout)

    def test_every_string_has_its_italian(self):
        # A key with no Italian shows in English; a key given twice shows only its later translation (the Settings tab "Building" read "In compilazione",
        # the status of a running build); a key nothing uses is one a source change left behind
        used = {}
        for data in self.strings.glob('*.stringsdata'):
            d = json.loads(data.read_text())
            for table, entries in d['tables'].items():
                for e in entries:
                    if e['key']: used.setdefault((table, e['key']), f"{Path(d['source']).name}:{e['location']['startingLine']}")
        self.assertTrue(used, 'the compiler gave no localizable strings')
        self.assertEqual({table for table, _ in used}, {'Localizable'})
        italian = STUDIO / 'Resources/it.lproj/Localizable.strings'
        written = strings_keys(italian)
        self.assertEqual(sorted(k for k in set(written) if written.count(k) > 1), [], 'keys given twice')
        keys = set(json.loads(subprocess.run(['plutil', '-convert', 'json', '-o', '-', str(italian)], capture_output=True, text=True, check=True).stdout))
        self.assertEqual(len(keys), len(written), 'every key the file has is read back')
        self.assertEqual(sorted(f'{k!r} ({where})' for (_, k), where in used.items() if k not in keys), [], 'strings with no Italian')
        self.assertEqual(sorted(k for k in keys if ('Localizable', k) not in used), [], 'Italian strings no source uses')


if __name__ == '__main__':
    unittest.main()
