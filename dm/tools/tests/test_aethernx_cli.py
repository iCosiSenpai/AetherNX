"""The aethernx command-line tool (scripts/aethernx_cli.py) on synthetic libraries and archives; no game files, keys or network.
scan: a game package dropped at the top of a library folder hides none of the game folders in it, a single game's folder with its update in a subfolder is one game, a
folder that cannot be read is an error beside the other folders' games, a game's Mac apps are only those built from it (DMTitleID), and the unpack hint names the archive.
unpack: a compressed tar comes out whole whatever 7-Zip is on the Mac, archives that give nothing a build takes are kept, --delete-archives deletes every volume, and an
encrypted archive fails at once. doctor checks the Metal compiler the shaders were tested with. setup installs the versions CI pins, and ios-slim keeps the extracted files."""
import contextlib
import importlib
import io
import os
import plistlib
import re
import shlex
import shutil
import struct
import subprocess
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path
from unittest import mock

REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO / 'scripts'))
cli = importlib.import_module('aethernx_cli')
SEVEN_ZIP = shutil.which('7zz') or shutil.which('7z') or ''   # a real 7-Zip, to make the volumes and the encrypted archive that unpack is given


def nsp(path, size=68):   # a PFS0 header with no entries: the scan takes the title ID from the [title ID] in the name, as for a package with no ticket
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b'PFS0' + struct.pack('<II', 0, 0) + os.urandom(size))


def app(path, title_id=None):
    (path / 'Contents').mkdir(parents=True)
    info = {'CFBundleIdentifier': f'com.example.{path.stem.lower()}'}
    if title_id: info['DMTitleID'] = title_id
    with open(path / 'Contents/Info.plist', 'wb') as f: plistlib.dump(info, f)


def run(*argv):   # (exit code, stdout, stderr) of the tool, in this process
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err): code = cli.main(list(argv))
    return code, out.getvalue(), err.getvalue()


def scan(*folders):
    import json
    code, out, err = run('scan', '--json', *map(str, folders))
    if code: raise AssertionError(f'scan exited {code}: {err}')
    d = json.loads(out)
    return {g['name']: g for g in d['games']}, d['errors']


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name).resolve()


class Scan(Base):
    def test_a_package_at_the_top_of_a_library_hides_no_game(self):
        lib = self.root / 'lib'
        nsp(lib / 'GameA/GameA [0100000000110000][v0].nsp'); nsp(lib / 'GameB/GameB [0100000000220000][v0].nsp')
        games, errors = scan(lib)
        self.assertEqual((sorted(games), errors), (['GameA', 'GameB'], []))
        nsp(lib / 'Stray [0100000000330000][v0].nsp')   # it used to make the library one game of three: no game listed, one error
        games, errors = scan(lib)
        self.assertEqual(sorted(games), ['GameA', 'GameB'])
        self.assertEqual([e['folder'] for e in errors], [str(lib)])
        self.assertIn('more than one game in the folder', errors[0]['message']); self.assertIn('listed on their own', errors[0]['message'])

    def test_a_single_games_folder_with_its_update_in_a_subfolder_is_one_game(self):
        single = self.root / 'Single'
        nsp(single / 'Single [0100000000440000][v0].nsp'); nsp(single / 'Update/Single [0100000000440800][v65536].nsp')
        games, errors = scan(single)
        self.assertEqual((list(games), errors), (['Single'], []))
        self.assertEqual((games['Single']['folder'], [u['version'] for u in games['Single']['updates']]), (str(single), [65536]))

    @unittest.skipIf(os.geteuid() == 0, 'root reads any folder')
    def test_a_folder_that_cannot_be_read_is_an_error_beside_the_others(self):
        lib, locked = self.root / 'lib', self.root / 'locked'
        nsp(lib / 'GameA/GameA [0100000000110000][v0].nsp'); locked.mkdir(); locked.chmod(0)
        self.addCleanup(locked.chmod, 0o755)
        games, errors = scan(lib, locked)   # it was a traceback and exit 1: Studio showed the whole library failing
        self.assertEqual(list(games), ['GameA'])
        self.assertEqual([(e['folder'], e['message']) for e in errors], [(str(locked), 'cannot be read (Permission denied)')])

    def test_a_games_mac_apps_are_only_those_built_from_it(self):
        game = self.root / 'lib/GameA'
        nsp(game / 'GameA [0100000000110000][v0].nsp')
        app(game / 'GameA.app', '0100000000110000'); app(game / 'Another.app'); app(game / 'OtherGame.app', '0100000000770000')
        (game / 'Broken.app/Contents').mkdir(parents=True); (game / 'Broken.app/Contents/Info.plist').write_text('<plist><dict><key>')
        games, _ = scan(self.root / 'lib')
        self.assertEqual(games['GameA']['mac_apps'], [str(game / 'GameA.app')])   # Studio plays the first, and the Danger Zone removes them with their settings

    def test_the_unpack_hint_names_the_archive_quoted(self):
        lib = self.root / 'lib'; nsp(lib / 'GameA/GameA [0100000000110000][v0].nsp')
        archive = lib / "Loose Game's.zip"; archive.write_bytes(b'PK\x05\x06' + bytes(18))
        code, out, _ = run('scan', str(lib))
        self.assertEqual(code, 0)
        self.assertIn(f'run ./aethernx unpack {shlex.quote(str(archive))}', out)   # not the library folder, every archive of which unpack would extract into it

    def test_an_empty_folder_holds_no_game(self):   # tests.yml's Studio job checks the same through ./aethernx
        empty = self.root / 'empty'; empty.mkdir()
        self.assertEqual(scan(empty), ({}, []))


def fake_seven(folder):   # a 7-Zip that fails whatever it is asked: what reaches it is not extracted
    seven = folder / '7zz'; seven.write_text('#!/bin/sh\necho "7-Zip was asked" >&2\nexit 2\n'); seven.chmod(0o755)
    return str(seven)


class Unpack(Base):
    def tar_gz(self, name, members):
        path = self.root / name
        with tarfile.open(path, 'w:gz') as t:
            for m in members: t.add(m, arcname=m.name)
        return path

    def test_a_compressed_tar_comes_out_whole_with_7zip_installed(self):
        game = self.root / 'src/Game [0100000000550000][v0].nsp'; nsp(game, 4000)
        archive = self.tar_gz('Game.tar.gz', [game])
        seven = fake_seven(self.root)
        with mock.patch.object(cli.shutil, 'which', side_effect=lambda n, *a, **k: seven if n in ('7zz', '7z') else None):
            code, _, err = run('unpack', str(archive))   # 7-Zip took off the gzip layer only: Game.tar and no package
        self.assertEqual(code, 0, err)
        self.assertEqual((self.root / 'Game' / game.name).read_bytes(), game.read_bytes())

    def test_archives_that_give_no_game_are_kept(self):
        notes = self.root / 'src/readme.txt'; notes.parent.mkdir(); notes.write_text('notes')
        archive = self.tar_gz('Notes.tar.gz', [notes])
        code, _, err = run('unpack', str(archive), '--delete-archives')
        self.assertEqual(code, 1)
        self.assertIn('no game package', err); self.assertIn('the archives are kept', err)
        self.assertTrue(archive.is_file())

    def test_volumes_of_one_archive(self):
        for n in ('Game.part1.rar', 'Game.part2.rar', 'Game.part10.rar', 'Other.part1.rar', 'X.rar', 'X.r00', 'X.r01', 'Y.r00', 'A.7z.001', 'A.7z.002', 'B.7z.001', 'Plain.zip'):
            (self.root / n).write_bytes(b'')
        names = lambda arc: [p.name for p in cli.archive_volumes(self.root / arc)]
        self.assertEqual(names('Game.part1.rar'), ['Game.part1.rar', 'Game.part10.rar', 'Game.part2.rar'])
        self.assertEqual(names('X.rar'), ['X.r00', 'X.r01', 'X.rar'])
        self.assertEqual(names('A.7z.001'), ['A.7z.001', 'A.7z.002'])
        self.assertEqual(names('Plain.zip'), ['Plain.zip'])

    @unittest.skipUnless(SEVEN_ZIP, 'needs 7-Zip to make a multi-volume archive')
    def test_delete_archives_removes_every_volume(self):
        game = self.root / 'src/Game [0100000000550000][v0].nsp'; nsp(game, 6000)   # random bytes: more than one 2 KB volume
        subprocess.run([SEVEN_ZIP, 'a', '-v2k', '-mx0', '-bso0', '-bsp0', str(self.root / 'Vol.7z'), str(game)], check=True)
        volumes = sorted(self.root.glob('Vol.7z.0*'))
        self.assertGreater(len(volumes), 1)
        code, _, err = run('unpack', str(volumes[0]), '--delete-archives')
        self.assertEqual(code, 0, err)
        self.assertEqual(list(self.root.glob('Vol.7z.0*')), [])   # only the first one went before
        self.assertTrue(any(p.name == game.name for p in self.root.rglob('*.nsp') if 'src' not in p.parts))

    @unittest.skipUnless(SEVEN_ZIP, 'needs 7-Zip to make an encrypted archive')
    def test_an_encrypted_archive_fails_at_once(self):
        secret = self.root / 'secret.txt'; secret.write_text('x')
        subprocess.run([SEVEN_ZIP, 'a', '-pSECRET', '-mem=AES256', '-bso0', '-bsp0', str(self.root / 'Enc.zip'), str(secret)], check=True)
        # stdin an open pipe nobody writes to, as a terminal nobody types in: the password prompt waited there for good, unseen behind the captured output
        with tempfile.TemporaryFile('w+') as log:
            r = subprocess.Popen([str(REPO / 'aethernx'), 'unpack', str(self.root / 'Enc.zip')], stdin=subprocess.PIPE, stdout=log, stderr=log, text=True)
            try: code = r.wait(timeout=30)
            except subprocess.TimeoutExpired: r.kill(); r.wait(); code = None
            finally:
                if r.stdin: r.stdin.close()
            log.seek(0); text = log.read()
        self.assertEqual(code, 1, text or 'unpack waited for a password'); self.assertIn('could not extract Enc.zip (it is encrypted', text)


class Doctor(unittest.TestCase):
    def test_the_metal_compiler_of_the_tested_shaders_is_checked(self):
        for answer, ok in (((1, 'Another Metal compiler: install Xcode 27.2'), False), ((0, ''), True)):
            def run_out(cmd, timeout=20, answer=answer):
                if cmd[0] == 'xcodebuild': return 0, 'Xcode 27.2'
                if any(str(c).endswith('own_compilers.py') for c in cmd): return answer
                return 0, ''
            with self.subTest(ok=ok), mock.patch.object(cli, 'run_out', run_out):
                c = next(c for c in cli.doctor()['checks'] if c['name'].startswith('Metal compiler of the tested shaders'))
                self.assertEqual((c['ok'], c['required'], c['fix']), (ok, True, '' if ok else 'Another Metal compiler: install Xcode 27.2'))


class Pins(unittest.TestCase):
    def pins(self, path):   # {package: version} of a requirements file's name==version lines (an environment marker after ';' is left out)
        out = {}
        for line in path.read_text().splitlines():
            line = line.split('#', 1)[0].split(';', 1)[0].strip()
            if not line: continue
            m = re.fullmatch(r'([A-Za-z0-9_.-]+)==([0-9][A-Za-z0-9.]*)', line)
            self.assertIsNotNone(m, f'{path.name}: {line!r} is not pinned with ==')
            if m: out[m[1].lower()] = m[2]
        return out

    def test_setup_installs_the_versions_ci_tests(self):
        ci = self.pins(REPO / '.github/requirements/tools.txt')
        for name in ('requirements.txt', 'requirements-tools.txt'):
            mine = self.pins(REPO / 'scripts' / name)
            self.assertEqual({k: v for k, v in mine.items() if k in ci}, {k: ci[k] for k in mine if k in ci}, f'scripts/{name} and .github/requirements/tools.txt')
        self.assertEqual(set(self.pins(REPO / 'scripts/requirements.txt')) - set(ci), {'backports.zstd'})   # only Pythons before 3.14 need it, which CI does not run


class Targets(unittest.TestCase):
    def test_ios_slim_keeps_the_extracted_files(self):   # the build refuses --romfs separate without them: the image stays for the copy to the phone
        self.assertEqual(cli.TARGETS['ios-slim'][-1], '--keep-extracted')


if __name__ == '__main__':
    unittest.main()
