"""AetherNX Companion (docs/companion.md): its game-folder logic compiled for the Mac and run by companion_check.swift against synthetic folders
(the demo library among them), and every string the app shows has its Italian. No Simulator, window, iCloud or game file is needed."""
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

COMPANION = Path(__file__).resolve().parents[1]
MAC_TARGET = 'arm64-apple-macos26.0'
SIM_TARGET = 'arm64-apple-ios26.0-simulator'   # project.yml's deployment target


def strings_keys(path):
    """The keys of a .strings file, in file order, as written."""
    return [m.group(1) for m in re.finditer(r'^"((?:[^"\\]|\\.)*)"\s*=', path.read_text(encoding='utf-8'), re.M)]


def simulator_sdk():
    found = subprocess.run(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'], capture_output=True, text=True)
    return found.stdout.strip() if found.returncode == 0 else None


@unittest.skipUnless(sys.platform == 'darwin' and shutil.which('xcrun'), 'needs macOS and its Swift toolchain')
class CompanionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)
        self.cache = ['-module-cache-path', str(self.dir / 'module-cache')]

    def test_game_folder_logic(self):
        lib = self.dir / 'lib'
        lib.mkdir()
        core = sorted(map(str, (COMPANION / 'Sources/Core').glob('*.swift')))
        built = subprocess.run(['xcrun', 'swiftc', '-emit-library', '-enable-testing', '-swift-version', '5', '-target', MAC_TARGET, *self.cache,
                                '-module-name', 'CompanionCore', '-emit-module', '-emit-module-path', str(lib / 'CompanionCore.swiftmodule'),
                                *core, '-o', str(lib / 'libCompanionCore.dylib')], capture_output=True, text=True, timeout=600)
        self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
        check = self.dir / 'companion_check'
        built = subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-target', MAC_TARGET, *self.cache, '-I', str(lib), '-L', str(lib), '-lCompanionCore',
                                '-Xlinker', '-rpath', '-Xlinker', str(lib), str(Path(__file__).with_name('companion_check.swift')), '-o', str(check)],
                               capture_output=True, text=True, timeout=600)
        self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
        scratch = self.dir / 'scratch'
        scratch.mkdir()
        ran = subprocess.run([str(check), str(scratch)], capture_output=True, text=True, timeout=120)
        self.assertEqual(ran.returncode, 0, ran.stdout + ran.stderr)
        self.assertIn('companion check: 0 failed', ran.stdout)

    @unittest.skipUnless(simulator_sdk(), 'needs the iOS Simulator SDK')
    def test_every_string_has_its_italian(self):
        strings = self.dir / 'strings'
        strings.mkdir()
        sources = sorted(map(str, (COMPANION / 'Sources').rglob('*.swift')))
        built = subprocess.run(['xcrun', '--sdk', 'iphonesimulator', 'swiftc', '-emit-library', '-parse-as-library', '-swift-version', '5', '-target', SIM_TARGET,
                                '-sdk', simulator_sdk(), *self.cache, '-module-name', 'AetherNXCompanion', '-emit-localized-strings',
                                '-emit-localized-strings-path', str(strings), *sources, '-o', str(self.dir / 'libAetherNXCompanion.dylib')],
                               capture_output=True, text=True, timeout=900)
        self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
        used = {}
        for data in strings.glob('*.stringsdata'):
            d = json.loads(data.read_text())
            for table, entries in d['tables'].items():
                for e in entries:
                    if e['key']: used.setdefault((table, e['key']), f"{Path(d['source']).name}:{e['location']['startingLine']}")
        self.assertTrue(used, 'the compiler gave no localizable strings')
        self.assertEqual({table for table, _ in used}, {'Localizable'})
        self.assertTrue((COMPANION / 'Resources/en.lproj/Localizable.strings').exists(), 'the English table (the keys themselves)')
        italian = COMPANION / 'Resources/it.lproj/Localizable.strings'
        written = strings_keys(italian)
        self.assertEqual(sorted(k for k in set(written) if written.count(k) > 1), [], 'keys given twice')
        keys = set(json.loads(subprocess.run(['plutil', '-convert', 'json', '-o', '-', str(italian)], capture_output=True, text=True, check=True).stdout))
        self.assertEqual(len(keys), len(written), 'every key the file has is read back')
        self.assertEqual(sorted(f'{k!r} ({where})' for (_, k), where in used.items() if k not in keys), [], 'strings with no Italian')
        self.assertEqual(sorted(k for k in keys if ('Localizable', k) not in used), [], 'Italian strings no source uses')


if __name__ == '__main__':
    unittest.main()
