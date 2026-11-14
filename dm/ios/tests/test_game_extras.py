"""The iPhone app and the game folder AetherNX Studio and AetherNX Companion share (docs/companion.md): its mods and cheats (dm/ios/Sources/GameExtras.swift,
compiled and run on macOS against synthetic folders by game_extras_check.swift), the same rules as Studio's, the cheats read after the launcher, and the
app's link aethernx-<title ID>:// in its Info.plist. No simulator, device or game files."""
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[3]
IOS = REPO / 'dm/ios'


def swift_function(path, name):
    """The text of a static func, from its line to the closing brace at its indent."""
    text = path.read_text()
    m = re.search(rf'^( *)static func {name}\b.*?^\1\}}', text, re.MULTILINE | re.DOTALL)
    assert m, f'no static func {name} in {path}'
    return m[0]


class GameExtrasTests(unittest.TestCase):
    @unittest.skipUnless(sys.platform == 'darwin' and shutil.which('xcrun'), 'needs the macOS Swift toolchain')
    def test_game_folder(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            exe = tmp / 'game_extras_check'
            r = subprocess.run(['xcrun', '-sdk', 'macosx', 'swiftc', '-swift-version', '5', '-parse-as-library', '-module-cache-path', str(tmp / 'module-cache'),
                                '-o', str(exe), str(IOS / 'Sources/GameExtras.swift'), str(Path(__file__).with_name('game_extras_check.swift'))],
                               capture_output=True, text=True, timeout=300)
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            (tmp / 'scratch').mkdir()
            r = subprocess.run([str(exe), str(tmp / 'scratch')], capture_output=True, text=True, timeout=60)
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            self.assertIn('game extras: 0 failed', r.stdout)

    def test_same_rules_as_studio(self):
        """A mod, its romfs and code folders, and a game's folder name, as Studio has them (studio/Sources/Mods.swift, CloudSaves.swift)."""
        ours, mods = (IOS / 'Sources/GameExtras.swift').read_text(), (REPO / 'studio/Sources/Mods.swift').read_text()
        for pattern in (r'let candidates = (\[.*?\])', r'let code = (\[.*?\])'):
            with self.subTest(pattern=pattern):
                self.assertEqual(re.search(pattern, ours)[1], re.search(pattern, mods)[1])
        body = lambda f: swift_function(f, 'folderName').split('\n', 1)[1]
        self.assertEqual(body(IOS / 'Sources/GameExtras.swift'), body(REPO / 'studio/Sources/CloudSaves.swift'))
        self.assertIn('home + "/Library/Mobile Documents/com~apple~CloudDocs/AetherNX"', (REPO / 'studio/Sources/CloudSaves.swift').read_text())
        self.assertIn('static let aetherSuffix = "/Mobile Documents/com~apple~CloudDocs/AetherNX"', ours)

    def test_cheats_are_read_after_the_launcher(self):
        """The iOS app loads the game at launch (dm_host_preload_start) and sets DM_CHEATS at Play: the host reads it once the loading is done, in main."""
        main = (REPO / 'dm/host/main.c').read_text()
        preload = re.search(r'^static void host_preload\(.*?^\}', main, re.MULTILINE | re.DOTALL)[0]
        entry = re.search(r'^int main\(.*?^\}', main, re.MULTILINE | re.DOTALL)[0]
        self.assertNotIn('dm_cheats_init', preload)
        self.assertIn('dm_cheats_init();', entry)
        self.assertLess(entry.index('host_preload(argc, argv);'), entry.index('dm_cheats_init();'))
        self.assertLess(entry.index('dm_cheats_init();'), entry.index('front_run(guest_loop);'))
        front = (IOS / 'Sources/front_ios.m').read_text()
        start = re.search(r'^- \(void\)startGame \{.*?^\}', front, re.MULTILINE | re.DOTALL)[0]
        self.assertLess(start.index('dm_cloud_saves_env();'), start.index('dm_game_extras_env();'))
        self.assertLess(start.index('dm_game_extras_env();'), start.index('front_ios_boot();'))

    def test_mac_launcher_reads_mods_json(self):
        """dm/mac/launcher.c takes the game folder's mods.json (Launcher.swift dm_mac_game_mods) before Studio's mods.folders, once DM_SAVE_SYNC is known."""
        c = (REPO / 'dm/mac/launcher.c').read_text()
        fn = re.search(r'^static void mods_and_cheats\(const char \*id\) \{.*?^\}', c, re.MULTILINE | re.DOTALL)[0]
        self.assertLess(fn.index('dm_mac_game_mods(id, ov, sizeof ov)'), fn.index('CFSTR("mods.folders")'))
        self.assertIn('getenv("DM_ROMFS_OVERLAY") || own ? NULL', fn)
        self.assertLess(c.index('    cloud_saves_folder();\n'), c.index('    mods_and_cheats(id);\n'))
        self.assertIn("'ios/Sources/GameExtras.swift'", (REPO / 'dm/mac/pack_app.py').read_text())
        with tempfile.TemporaryDirectory() as tmp:   # launcher.c compiles with the declaration it calls
            r = subprocess.run(['xcrun', '-sdk', 'macosx', 'clang', '-Wall', '-Werror', '-I', str(REPO / 'dm/host'), '-c', '-o', str(Path(tmp) / 'launcher.o'), str(REPO / 'dm/mac/launcher.c')],
                               capture_output=True, text=True, timeout=120) if sys.platform == 'darwin' and shutil.which('xcrun') else None
            if r: self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_url_scheme(self):
        """build_ipa.sh names the scheme after the base game's title ID, in lower case; project.yml puts it in CFBundleURLTypes; the scene takes the links."""
        line = next(l for l in (IOS / 'tools/build_ipa.sh').read_text().splitlines() if l.startswith('export DM_URL_SCHEME='))
        r = subprocess.run(['bash', '-c', f'GAME=0100ABCD12340000; {line}; printf %s "$DM_URL_SCHEME"'], capture_output=True, text=True, check=True)
        self.assertEqual(r.stdout, 'aethernx-0100abcd12340000')
        project = (IOS / 'project.yml').read_text()
        self.assertRegex(project, r'\n        CFBundleURLTypes:.*\n          - CFBundleURLName: \$\{DM_BUNDLE_ID\}\n            CFBundleURLSchemes:\n              - \$\{DM_URL_SCHEME\}')
        self.assertIn("DM_URL_SCHEME=f'aethernx-{profile.id.lower()}'", (IOS / 'tools/build_smoke.py').read_text())
        scene = (IOS / 'Sources/main.m').read_text()
        self.assertIn('for (UIOpenURLContext *c in o.URLContexts) front_ios_open_url(c.URL);', scene)
        self.assertIn('openURLContexts:(NSSet<UIOpenURLContext *> *)contexts', scene)


if __name__ == '__main__':
    unittest.main()
