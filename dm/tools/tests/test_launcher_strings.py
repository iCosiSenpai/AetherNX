"""The game app's texts in each language (dm/ios/Sources/<language>.lproj): the launcher, the in-game menu and the app's notices on the iPhone and iPad, and the Mac app's settings
window and alerts, which dm/mac/pack_app.py gives the same tables. The sources are in English and each English text is the key of its translation, as in Studio and Companion
(studio/tests/test_studio.py, companion/tests/test_companion.py). Two tables: Localizable.strings for the texts in the sources, Settings.strings for the settings list's
(dm/games/settings.tsv), which the app looks up when it shows them (LauncherSettings.swift Setting.text).

Everywhere: the tables' syntax and arguments, the settings list's texts, the notices the Objective-C and C sources look up, and every String(localized:) literal of the Swift
sources. On a Mac with Xcode: the keys the Swift compiler itself finds (the SwiftUI literals too, which the source text alone does not tell from other strings), so that no
text is without its translation and no key is left behind by a source change. No game files, keys or devices needed."""
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[3]
SOURCES = REPO / 'dm/ios/Sources'
MAC = REPO / 'dm/mac'
LANGUAGES = ['it']   # besides English, the sources' own
IOS_TARGET = 'arm64-apple-ios26.0'   # dm/ios/project.yml's deployment target


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader, path
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module


settings = load('launcher_strings_settings', REPO / 'dm/games/settings.py')
pack_app = load('launcher_strings_pack_app', MAC / 'pack_app.py')

ESCAPES = {'n': '\n', 't': '\t', '"': '"', '\\': '\\'}
ENTRY = re.compile(r'"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";')
ARGUMENT = re.compile(r'%(?:(\d+)\$)?(lld|ld|d|s|@|%)')


def unescape(text):
    return re.sub(r'\\(.)', lambda m: ESCAPES[m.group(1)], text)


def table(path):
    """A .strings file as its (key, translation) pairs in file order: comments and one "key" = "translation"; a line, nothing else"""
    pairs = []
    for line in re.sub(r'/\*.*?\*/', '', path.read_text(encoding='utf-8'), flags=re.S).splitlines():
        if not line.strip(): continue
        m = ENTRY.fullmatch(line.strip())
        if not m: raise AssertionError(f'{path.relative_to(REPO)}: not "key" = "translation";: {line}')
        pairs.append((unescape(m.group(1)), unescape(m.group(2))))
    return pairs


def arguments(text):
    """The arguments a text takes, in the order they are passed: %@ %lld %d %s, or numbered (%1$@) in any order"""
    found = [(n, kind) for n, kind in ARGUMENT.findall(text) if kind != '%']
    if any(n for n, _ in found): return [kind for _, kind in sorted(found, key=lambda f: int(f[0]) if f[0] else 0)]
    return [kind for _, kind in found]


def swift_literals(text):
    """The string literals of a Swift source outside its comments, each with the code before it on its line. An interpolation is kept as written"""
    out, i, start = [], 0, 0
    while i < len(text):
        c = text[i]
        if c == '\n': start = i + 1
        elif text.startswith('//', i):
            i = text.find('\n', i)
            if i < 0: break
            continue
        elif c == '"':
            j, depth = i + 1, 0
            while depth or text[j] != '"':
                if not depth and text.startswith('\\(', j): depth = 1; j += 2; continue
                if not depth and text[j] == '\\': j += 2; continue
                if depth and text[j] == '"':   # a literal inside an interpolation
                    j += 1
                    while text[j] != '"': j += 2 if text[j] == '\\' else 1
                elif depth and text[j] == '(': depth += 1
                elif depth and text[j] == ')': depth -= 1
                j += 1
            out.append((text[start:i].rstrip(), text[i + 1:j]))
            i = j
        i += 1
    return out


def shape(text, literal=False):
    """A key with every argument as one mark, so a Swift literal (whose \\(...) the compiler writes as %@ or %lld by its type) can be held against the table without the types"""
    if not literal: return ARGUMENT.sub(lambda m: m.group(0) if m.group(2) == '%' else '\0', text)
    out, i = '', 0
    while i < len(text):
        if text.startswith('\\(', i):
            depth, i = 1, i + 2
            while depth:
                if text[i] == '"':
                    i += 1
                    while text[i] != '"': i += 2 if text[i] == '\\' else 1
                elif text[i] == '(': depth += 1
                elif text[i] == ')': depth -= 1
                i += 1
            out += '\0'
        elif text[i] == '\\': out += ESCAPES[text[i + 1]]; i += 2
        else: out += text[i]; i += 1
    return out


def launcher_sources(platform):
    """The Swift sources of one app: every one of the iPhone project (dm/ios/project.yml takes the folder), the Mac window's as pack_app.py lists them"""
    return sorted(SOURCES.glob('*.swift')) if platform == 'ios' else pack_app.swift_sources()


def objc_keys():
    """NSLocalizedString(@"...", nil) in the iPhone app's Objective-C sources: the key is the literal. Any other form of the call is refused, since it could not be checked"""
    keys = {}
    for path in sorted(SOURCES.glob('*.m')):
        text = path.read_text(encoding='utf-8')
        found = re.findall(r'NSLocalizedString\(@"((?:[^"\\]|\\.)*)", nil\)', text)
        if len(found) != text.count('NSLocalizedString'): raise AssertionError(f'{path.name}: an NSLocalizedString that is not NSLocalizedString(@"literal", nil)')
        for k in found: keys.setdefault(unescape(k), path.name)
    return keys


def c_keys():
    """The messages of the Mac launcher's alert (launcher.c alert, which looks the message up): the literal of each call"""
    text = (MAC / 'launcher.c').read_text(encoding='utf-8')
    found = re.findall(r'\balert\(name, "((?:[^"\\]|\\.)*)"\)', text)
    if len(found) != len(re.findall(r'\balert\(', text)) - 1: raise AssertionError('launcher.c: an alert whose message is not a literal')   # - 1: its definition
    return {unescape(k): 'launcher.c' for k in found}


class Tables(unittest.TestCase):
    def test_each_language_has_both_tables_and_the_apps_list_it(self):
        self.assertEqual(sorted(p.name for p in SOURCES.glob('*.lproj')), sorted(f'{code}.lproj' for code in ['en'] + LANGUAGES))
        for code in ['en'] + LANGUAGES:
            self.assertEqual(sorted(p.name for p in (SOURCES / f'{code}.lproj').iterdir()), ['Localizable.strings', 'Settings.strings'])
        # English is the sources' own: its tables say so and hold nothing, so a text without a translation shows as written
        for name in ('Localizable', 'Settings'): self.assertEqual(table(SOURCES / f'en.lproj/{name}.strings'), [])
        project = (REPO / 'dm/ios/project.yml').read_text(encoding='utf-8')
        self.assertIn(f'CFBundleLocalizations: [{", ".join(["en"] + LANGUAGES)}]', project)   # the iPhone app's Info.plist
        self.assertIn('developmentLanguage: en', project)
        self.assertEqual(sorted({t.parent.stem for t in pack_app.string_tables()}), sorted(['en'] + LANGUAGES))   # the Mac app's (pack_app.py info_plist)

    def test_no_key_twice_and_the_same_arguments(self):
        for code in LANGUAGES:
            for name in ('Localizable', 'Settings'):
                pairs = table(SOURCES / f'{code}.lproj/{name}.strings')
                keys = [k for k, _ in pairs]
                self.assertEqual(sorted(k for k in set(keys) if keys.count(k) > 1), [], f'{code} {name}: keys given twice (only the later translation would show)')
                for key, text in pairs:
                    with self.subTest(language=code, table=name, key=key):
                        self.assertTrue(text.strip(), 'an empty translation')
                        self.assertEqual(arguments(text), arguments(key), 'the same arguments; in another order they need their numbers (%1$@ %2$@)')
                        self.assertNotIn('%', ARGUMENT.sub('', key + text), 'an argument the checks do not know')

    def test_the_settings_list(self):
        # dm/games/settings.tsv's texts reach the app in launcher.json as written; the app shows each one's translation (Setting.text), so a text added to the list
        # needs one, and one the list no longer has is left over
        listed = set(settings.texts())
        self.assertIn('Frame rate', listed); self.assertIn('Italian', listed); self.assertIn(settings.UNKNOWN_LANGUAGES, listed)
        for section in settings.SECTIONS: self.assertIn(section, listed)
        for code in LANGUAGES:
            keys = {k for k, _ in table(SOURCES / f'{code}.lproj/Settings.strings')}
            self.assertEqual(sorted(listed - keys), [], f'{code}: settings texts with no translation')
            self.assertEqual(sorted(keys - listed), [], f'{code}: translations of texts the settings list does not have')

    def test_the_notices_of_the_objective_c_and_c_sources(self):
        looked_up = {**objc_keys(), **c_keys()}
        self.assertGreater(len(objc_keys()), 10); self.assertEqual(len(c_keys()), 2)
        for code in LANGUAGES:
            keys = {k for k, _ in table(SOURCES / f'{code}.lproj/Localizable.strings')}
            self.assertEqual(sorted(f'{k!r} ({where})' for k, where in looked_up.items() if k not in keys), [], f'{code}: notices with no translation')

    def test_every_localized_literal_of_the_swift_sources(self):
        # String(localized: "...") is a key by its form. An interpolation's type decides %@ or %lld, which only the compiler knows, so the two are held together by their
        # shape here; the compiler's own list is checked below, on a Mac
        literals = {}
        for path in sorted(set(launcher_sources('ios')) | set(launcher_sources('mac'))):
            for before, literal in swift_literals(path.read_text(encoding='utf-8')):
                if before.endswith('String(localized:'): literals.setdefault(shape(literal, literal=True), path.name)
        self.assertGreater(len(literals), 50)
        for code in LANGUAGES:
            shapes = {shape(k) for k, _ in table(SOURCES / f'{code}.lproj/Localizable.strings')}
            self.assertEqual(sorted(f'{k!r} ({where})' for k, where in literals.items() if k not in shapes), [], f'{code}: String(localized:) texts with no translation')


def iphone_sdk():
    r = subprocess.run(['xcrun', '--sdk', 'iphoneos', '--show-sdk-path'], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else ''


@unittest.skipUnless(sys.platform == 'darwin' and shutil.which('xcrun') and shutil.which('plutil'), 'needs macOS and its Swift toolchain')
class CompilerKeys(unittest.TestCase):
    """The keys the Swift compiler finds in each app's sources (.stringsdata, as Xcode reads them), with the notices of the Objective-C and C sources, against the tables."""
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        tmp = Path(cls.tmp.name)
        cls.used, cls.failed, cls.complete = {}, [], bool(iphone_sdk())
        common = ['-c', '-parse-as-library', '-swift-version', '5', '-module-name', 'DmLauncher', '-module-cache-path', str(tmp / 'module-cache'), '-emit-localized-strings']
        builds = [('mac', ['xcrun', '--sdk', 'macosx', 'swiftc'])]
        if cls.complete:   # the iPhone app's sources call the front end and the host through the project's bridging header (project.yml SWIFT_OBJC_BRIDGING_HEADER)
            builds.append(('ios', ['xcrun', '--sdk', 'iphoneos', 'swiftc', '-sdk', iphone_sdk(), '-target', IOS_TARGET, '-import-objc-header', str(SOURCES / 'DmIOS-Bridging-Header.h'),
                                   '-I', str(REPO / 'dm/host'), '-Xcc', '-I' + str(REPO / 'dm/host')]))
        for platform, compiler in builds:
            out = tmp / platform; (out / 'strings').mkdir(parents=True)
            r = subprocess.run([*compiler, *common, '-emit-localized-strings-path', str(out / 'strings'), *map(str, launcher_sources(platform))],
                               cwd=out, capture_output=True, text=True, timeout=900)   # the objects go to the folder it runs in
            if r.returncode: cls.failed.append(f'{platform}: {r.stdout}{r.stderr}')
            for data in sorted((out / 'strings').glob('*.stringsdata')):
                d = json.loads(data.read_text())
                for name, entries in d['tables'].items():
                    for e in entries:
                        if e['key']: cls.used.setdefault((name, e['key']), f"{Path(d['source']).name}:{e['location']['startingLine']}")
        for key, where in {**objc_keys(), **c_keys()}.items(): cls.used.setdefault(('Localizable', key), where)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_every_text_has_its_translation_and_no_key_is_left_over(self):
        self.assertEqual(self.failed, [])
        self.assertGreater(len(self.used), 100, 'the compiler gave too few localizable strings')
        self.assertEqual({name for name, _ in self.used}, {'Localizable'})   # Settings.strings is looked up by name at run time (Setting.text): no source text is its key
        for code in LANGUAGES:
            path = SOURCES / f'{code}.lproj/Localizable.strings'
            written = [k for k, _ in table(path)]
            keys = set(json.loads(subprocess.run(['plutil', '-convert', 'json', '-o', '-', str(path)], capture_output=True, text=True, check=True).stdout))
            self.assertEqual(keys, set(written), f'{code}: every key the file has is read back as written')
            self.assertEqual(sorted(f'{k!r} ({where})' for (_, k), where in self.used.items() if k not in keys), [], f'{code}: texts with no translation')
            if not self.complete: self.skipTest('no iPhone SDK: the keys only the iPhone app uses cannot be told from keys nothing uses')
            self.assertEqual(sorted(k for k in keys if ('Localizable', k) not in self.used), [], f'{code}: translations no source uses')

    def test_the_settings_table_is_read_back(self):
        for code in LANGUAGES:
            path = SOURCES / f'{code}.lproj/Settings.strings'
            read = json.loads(subprocess.run(['plutil', '-convert', 'json', '-o', '-', str(path)], capture_output=True, text=True, check=True).stdout)
            self.assertEqual(read, dict(table(path)))


if __name__ == '__main__':
    unittest.main()
