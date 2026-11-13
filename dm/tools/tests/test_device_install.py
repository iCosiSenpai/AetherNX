"""./aethernx devices and install (scripts/device_install.py): the device list and the teams it reads, the signing command and what it does when a team cannot sign
what the project asks for, and the whole install against a stand-in build script, xcodebuild, devicectl and push script. No device, account, keychain or game file."""
import contextlib
import importlib.util
import io
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

REPO = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('device_install', REPO / 'scripts/device_install.py')
assert spec is not None and spec.loader is not None
di = importlib.util.module_from_spec(spec); spec.loader.exec_module(di)

UDID, TEAM, TITLE = '00008150-0000000000000001', 'A1B2C3D4E5', '0100000000990000'
BUNDLE = f'io.github.icosisenpai.horizonnative.{TITLE.lower()}'


def device(name='Fixture iPhone', udid=UDID, transport='wired', kind='iPhone', mode='enabled', **hardware):
    return {'identifier': 'CORE-' + udid[-4:], 'hardwareProperties': dict({'udid': udid, 'deviceType': kind, 'platform': 'iOS', 'marketingName': f'{kind} 17 Pro', 'reality': 'physical'}, **hardware),
            'deviceProperties': {'name': name, 'osVersionNumber': '27.2', 'developerModeStatus': mode},
            'connectionProperties': dict({'pairingState': 'paired'}, **({'transportType': transport} if transport else {}))}


class Devices(unittest.TestCase):
    def test_only_iphones_and_ipads_and_the_reachable_ones_first(self):
        listing = {'result': {'devices': [
            device('Away', '00008150-00000000000000A0', transport=''), device('Watch', '00008301-00000000000000B0', kind='appleWatch'),
            device('On Wi-Fi', '00008150-00000000000000C0', transport='localNetwork'), device('Tablet', '00008150-00000000000000D0', kind='iPad'),
            device('Simulated', '00008150-00000000000000E0', reality='simulated')]}}
        found = di.parse_devices(listing)
        self.assertEqual([d['name'] for d in found], ['Tablet', 'On Wi-Fi', 'Away'])   # cable, then network, then not reachable
        self.assertEqual([d['connection'] for d in found], ['cable', 'network', 'none'])
        self.assertTrue(all(d['paired'] and d['developer_mode'] for d in found))
        self.assertEqual(di.parse_devices({}), [])   # no result at all: no device, not an exception

    def test_a_device_is_named_by_udid_identifier_or_name(self):
        found = di.parse_devices({'result': {'devices': [device(), device('Other', '00008150-0000000000000002')]}})
        for wanted in (UDID, UDID.lower(), 'CORE-0001', 'fixture iphone'):
            self.assertEqual(di.pick_device(found, wanted)['udid'], UDID)
        with self.assertRaisesRegex(di.InstallError, 'several devices'): di.pick_device(found, None)
        self.assertEqual(di.pick_device(found[:1], None)['udid'], UDID)   # the only one connected needs no name
        with self.assertRaisesRegex(di.InstallError, 'no paired'): di.pick_device(found, 'Missing')

    def test_two_devices_of_one_name_and_a_device_that_cannot_take_an_app(self):
        twins = di.parse_devices({'result': {'devices': [device('iPhone'), device('iPhone', '00008150-0000000000000002', transport='')]}})
        self.assertEqual(di.pick_device(twins, 'iPhone')['udid'], UDID)   # the reachable one of two with the same name
        both = di.parse_devices({'result': {'devices': [device('iPhone'), device('iPhone', '00008150-0000000000000002')]}})
        with self.assertRaisesRegex(di.InstallError, 'give the UDID'): di.pick_device(both, 'iPhone')
        away = di.parse_devices({'result': {'devices': [device(transport='')]}})
        with self.assertRaisesRegex(di.InstallError, 'not reachable'): di.pick_device(away, UDID)
        with self.assertRaisesRegex(di.InstallError, 'no iPhone or iPad is connected'): di.pick_device(away, None)
        off = di.parse_devices({'result': {'devices': [device(mode='disabled')]}})
        with self.assertRaisesRegex(di.InstallError, 'Developer Mode'): di.pick_device(off, None)


class Teams(unittest.TestCase):
    def test_the_team_is_the_certificates_unit_not_the_code_in_its_name(self):
        team = di.parse_subject('subject=C=US,O=Jane Doe,OU=A1B2C3D4E5,CN=Apple Development: Jane Doe (Z9Y8X7W6V5),UID=ABCDEFGHIJ')
        self.assertEqual(team, {'id': 'A1B2C3D4E5', 'name': 'Jane Doe'})
        self.assertEqual(di.parse_subject(r'subject=C=US,O=Doe\, Inc.,OU=A1B2C3D4E5,CN=x')['name'], 'Doe, Inc.')
        self.assertIsNone(di.parse_subject('subject=CN=Developer ID Certification Authority,OU=Apple Certification Authority,O=Apple Inc.,C=US'))

    def test_which_team_signs(self):
        one, two = [{'id': TEAM, 'name': 'Jane'}], [{'id': TEAM, 'name': 'Jane'}, {'id': 'Z9Y8X7W6V5', 'name': 'Acme'}]
        never = mock.Mock(side_effect=AssertionError('the keychain is not read when the team is named'))
        self.assertEqual(di.pick_team('Z9Y8X7W6V5', teams=never), 'Z9Y8X7W6V5')
        self.assertEqual(di.pick_team(None, teams=lambda: one), TEAM)
        self.assertEqual(di.pick_team(None, saved='Z9Y8X7W6V5', teams=lambda: two), 'Z9Y8X7W6V5')   # the team the game was signed with last
        self.assertEqual(di.pick_team(None, saved='GONE000000', teams=lambda: one), TEAM)   # a saved team this Mac no longer has a certificate for
        with self.assertRaisesRegex(di.InstallError, 'several signing teams'): di.pick_team(None, teams=lambda: two)
        with self.assertRaisesRegex(di.InstallError, 'no Apple development certificate'): di.pick_team(None, teams=list)
        with self.assertRaisesRegex(di.InstallError, 'ten letters'): di.pick_team('jane@example.com', teams=never)

    def test_the_identifier_of_a_second_team(self):
        self.assertEqual(di.team_variant(BUNDLE, TEAM), BUNDLE + '.a1b2c3d4e5')
        self.assertEqual(di.team_variant(BUNDLE + '.a1b2c3d4e5', TEAM), BUNDLE + '.a1b2c3d4e5')   # never a variant of the variant

    def test_api_key_options(self):
        self.assertEqual(di.api_key_args(None, None, None), [])
        with tempfile.TemporaryDirectory() as tmp:
            key = Path(tmp) / 'AuthKey_ABC123DEF4.p8'; key.write_text('fixture')
            self.assertEqual(di.api_key_args(str(key), None, 'issuer-1'),
                             ['-authenticationKeyPath', str(key.resolve()), '-authenticationKeyID', 'ABC123DEF4', '-authenticationKeyIssuerID', 'issuer-1'])
            with self.assertRaisesRegex(di.InstallError, 'issuer'): di.api_key_args(str(key), None, None)
            other = Path(tmp) / 'key.p8'; other.write_text('fixture')
            with self.assertRaisesRegex(di.InstallError, 'key ID'): di.api_key_args(str(other), None, 'issuer-1')
            self.assertEqual(di.api_key_args(str(other), 'XYZ', 'issuer-1')[3], 'XYZ')
        with self.assertRaisesRegex(di.InstallError, 'no such API key'): di.api_key_args('/nonexistent/AuthKey_A.p8', None, 'issuer-1')
        with self.assertRaisesRegex(di.InstallError, '--api-key'): di.api_key_args(None, None, 'issuer-1')


class Failures(unittest.TestCase):
    def test_xcodebuilds_words(self):
        for words, kind in (
            (f'error: Provisioning profile "iOS Team Provisioning Profile: {BUNDLE}" doesn\'t include the Increased Memory Limit capability.', 'memory'),
            ("error: Provisioning profile \"x\" doesn't include the com.apple.developer.kernel.increased-memory-limit entitlement.", 'memory'),
            ("error: Provisioning profile \"x\" doesn't include the iCloud capability.", 'icloud'),
            ("error: Provisioning profile \"x\" doesn't include the com.apple.developer.icloud-container-identifiers entitlement.", 'icloud'),
            (f'error: Failed to register bundle identifier: The app identifier "{BUNDLE}" cannot be registered to your development team because it is not available.', 'bundle'),
            (f"error: No profiles for '{BUNDLE}' were found: Xcode couldn't find any iOS App Development provisioning profiles matching '{BUNDLE}'.", 'bundle'),
            ('error: No Accounts: Add a new account in Accounts settings.', 'account'),
            ('error: No Account for Team "A1B2C3D4E5". Add a new account in Accounts settings', 'account'),
            # without an account Xcode falls back to the team's wildcard profile: the capability errors after it are its consequence, not the cause
            ('error: No Accounts: Add a new account in Accounts settings.\nerror: Provisioning profile "iOS Team Provisioning Profile: *" doesn\'t include the Increased Memory Limit capability.', 'account'),
            ('error: Authentication failed: Make sure a bearer token was provided, it is properly configured and signed, and it has not expired.\n'
             'error: Provisioning profile "iOS Team Provisioning Profile: *" doesn\'t include the iCloud capability.', 'api_key'),
            ('xcodebuild: error: Unable to find a destination matching the provided destination specifier:\n\t\t{ id:0000 }', 'destination'),
            ('error: Your account already has the maximum number of App IDs. (9120)', 'app_ids'),
            ('error: The maximum number of apps for free development profiles has been reached.', 'free_limit'),
        ):
            with self.subTest(words=words[:60]): self.assertEqual(di.classify(words, BUNDLE)[0], kind)
        # words this does not know: the last error line, without the file it was in
        self.assertEqual(di.classify('note: x\n/tmp/a.c:3:1: error: use of undeclared identifier\n** BUILD FAILED **'), ('', 'use of undeclared identifier'))
        self.assertEqual(di.classify('** BUILD FAILED **'), ('', ''))
        # another identifier's missing profile is not this game's identifier being taken
        self.assertEqual(di.classify("error: No profiles for 'com.example.other' were found", BUNDLE)[0], '')

    def test_the_signing_command(self):
        facts = {'scheme': 'Fixture Game (0100000000990000)', 'output': Path('/work/xcode-derived-data')}
        cmd = di.sign_command('/work/xcode/DmIOS.xcodeproj', facts, UDID, TEAM)
        self.assertEqual(cmd[:3], ['xcodebuild', '-project', '/work/xcode/DmIOS.xcodeproj'])
        for word in ('-allowProvisioningUpdates', '-allowProvisioningDeviceRegistration', f'id={UDID}', f'DEVELOPMENT_TEAM={TEAM}', 'Release', 'build'): self.assertIn(word, cmd)
        self.assertFalse(any(w.startswith(('PRODUCT_BUNDLE_IDENTIFIER', 'CODE_SIGN_ENTITLEMENTS')) for w in cmd))   # the project's own, unless a retry overrides them
        again = di.sign_command('/p', facts, UDID, TEAM, bundle_id='com.example.x', entitlements='', auth=['-authenticationKeyPath', '/k.p8'])
        self.assertIn('PRODUCT_BUNDLE_IDENTIFIER=com.example.x', again); self.assertIn('CODE_SIGN_ENTITLEMENTS=', again); self.assertIn('/k.p8', again)

    def test_auto_keeps_the_files_on_a_cabled_device_with_afcclient(self):
        cable, network = {'connection': 'cable'}, {'connection': 'network'}
        self.assertEqual(di.files_mode('auto', cable, afcclient='/opt/homebrew/bin/afcclient'), 'separate')
        self.assertEqual(di.files_mode('auto', cable, afcclient=''), 'bundle')
        self.assertEqual(di.files_mode('auto', network, afcclient='/opt/homebrew/bin/afcclient'), 'bundle')
        self.assertEqual(di.files_mode('auto', network, afcclient='/opt/homebrew/bin/afcclient', has_image=True), 'separate', 'on the network, when the device has the image')
        self.assertEqual(di.files_mode('auto', network, afcclient='', has_image=True), 'bundle')
        self.assertEqual(di.files_mode('bundle', cable, afcclient='/x'), 'bundle')
        self.assertEqual(di.files_mode('separate', network, afcclient=''), 'separate')

    def test_the_device_has_the_image_when_its_identity_matches(self):
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp); (work / 'extract/v1').mkdir(parents=True); (work / 'extract/v1/RomFS.img').write_bytes(b'x')
            calls = []
            def run(cmd, timeout=60, env=None, answer='DMROMFSID1 size=1 index=ab'):
                calls.append(cmd)
                if '--identity' in cmd: return 0, answer + '\n', ''
                Path(cmd[-1]).write_text(answer)   # afcclient get <remote> <local>
                return 0, '', ''
            dev = {'udid': UDID, 'connection': 'network'}
            self.assertTrue(di.device_has_image(dev, 'b.id', work, afcclient='/x/afcclient', run=run))
            self.assertIn('-n', calls[-1]); self.assertEqual(calls[-1][-4:-1], ['--', 'get', '/Documents/romfs.img.id'])
            self.assertFalse(di.device_has_image(dev, 'b.id', work, afcclient='/x/afcclient',
                                                 run=lambda c, timeout=60, env=None: run(c, answer='DMROMFSID1 size=1 index=cd') if 'get' in c else run(c)))
            self.assertFalse(di.device_has_image(dev, '', work, afcclient='/x/afcclient', run=run), 'no bundle ID: not installed from here yet')
            self.assertFalse(di.device_has_image(dev, 'b.id', Path(tmp) / 'nothing', afcclient='/x/afcclient', run=run), 'no image built yet')

    def test_progress_words(self):
        self.assertEqual(di.xcode_step('CompileC /a/b.o /src/b.c normal arm64'), 'compiling')
        self.assertEqual(di.xcode_step('PhaseScriptExecution Copy\\ game\\ resources /x.sh'), 'copying the game files into the app')
        self.assertEqual(di.xcode_step('CodeSign /a/DmIOS.app'), 'signing')
        self.assertIsNone(di.xcode_step('    cd /a'))
        self.assertEqual(di.percent_in('Installing... 45%'), 0.45); self.assertEqual(di.percent_in('250%'), 1.0); self.assertIsNone(di.percent_in('App installed'))


# The stand-ins: a build script that makes the project a real --prepare-xcode leaves (its scheme, where its build goes, its signing settings), an xcodebuild that
# answers from a plan (one word per call: ok, or a failure's words) and makes the app, a devicectl, and a push script. Each appends its arguments to a file.
FAKE_BUILD = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
with open(os.environ['FAKE_CALLS'], 'a') as f: f.write('build ' + json.dumps(args) + ' icloud=' + os.environ.get('DM_ICLOUD_CONTAINER', '') + '\n')
if os.environ.get('FAKE_BUILD_FAILS'):
    print(json.dumps({'ev': 'say', 't': 0, 'msg': '[RED] no update in the folder'})); sys.exit(1)
folder = Path(args[0]); work = folder / '%(title)s_build'; project = work / 'xcode' / 'DmIOS.xcodeproj'
(project / 'xcshareddata' / 'xcschemes').mkdir(parents=True, exist_ok=True)
(project / 'xcshareddata' / 'xcschemes' / 'Fixture Game (%(title)s).xcscheme').write_text('<Scheme/>')
bundle = args[args.index('--bundle-id') + 1] if '--bundle-id' in args else '%(bundle)s'
team = args[args.index('--team-id') + 1]
(project / 'project.pbxproj').write_text(json.dumps({'objects': {
    'T': {'isa': 'PBXNativeTarget', 'name': 'DmIOS', 'buildConfigurationList': 'L'}, 'L': {'buildConfigurations': ['R']},
    'R': {'name': 'Release', 'buildSettings': {'PRODUCT_BUNDLE_IDENTIFIER': bundle, 'DEVELOPMENT_TEAM': team}}}}))
gen = work / 'xcode' / 'Gen'; gen.mkdir(exist_ok=True)
(gen / 'dm.xcconfig').write_text('OTHER_LDFLAGS = -x\nDM_XCODE_OUTPUT_ROOT = %%s\n' %% (work / 'xcode-derived-data'))
(gen / 'resources.env').write_text('DM_RESOURCE_ROMFS=/x\n')
for k in (1, 2):
    print(json.dumps({'ev': 'stage', 't': 0, 'k': k, 'n': 2, 'name': ['extract', 'prepare Xcode'][k - 1], 'step': ''}))
    if k == 1: print(json.dumps({'ev': 'game', 't': 0, 'title_id': '%(title)s', 'name': 'Fixture Game', 'version': '1.0.0', 'bundle_id': bundle, 'out': None, 'icon': None}))
    print(json.dumps({'ev': 'stage_end', 't': 0, 'k': k, 'name': 'x', 'ok': True, 'summary': '', 'elapsed': 0}))
print(json.dumps({'ev': 'say', 't': 0, 'msg': '[12:00:00] ready'}))
''' % {'title': TITLE, 'bundle': BUNDLE}

FAKE_XCODEBUILD = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
with open(os.environ['FAKE_CALLS'], 'a') as f: f.write('xcodebuild ' + json.dumps(args) + '\n')
plan = Path(os.environ['FAKE_PLAN']); words = plan.read_text().splitlines(); word = words.pop(0) if words else 'ok'; plan.write_text('\n'.join(words))
print('CompileC /o/main.o /src/main.c normal arm64'); print('CodeSign /o/DmIOS.app')
if word != 'ok':
    print('error: ' + word); print('** BUILD FAILED **'); sys.exit(65)
out = Path(args[args.index('-derivedDataPath') + 1]) / 'Build' / 'Products' / 'Release-iphoneos' / 'DmIOS.app'
out.mkdir(parents=True, exist_ok=True); print('** BUILD SUCCEEDED **')
'''

FAKE_XCRUN = r'''#!/usr/bin/env python3
import json, os, sys
args = sys.argv[1:]
if args[:3] == ['devicectl', 'list', 'devices']:
    with open(args[args.index('--json-output') + 1], 'w') as f: f.write(os.environ['FAKE_DEVICES'])
    sys.exit(0)
with open(os.environ['FAKE_CALLS'], 'a') as f: f.write('xcrun ' + json.dumps(args) + '\n')
if args[:4] == ['devicectl', 'device', 'install', 'app']:
    if os.environ.get('FAKE_INSTALL_FAILS'): print('ERROR: The device is locked. (com.apple.dt.CoreDeviceError error 4)'); sys.exit(1)
    print('Installing... 45%\rInstalling... 100%'); print('App installed:')
'''

FAKE_PUSH = '''#!/bin/bash
printf 'push %s via=%s\\n' "$*" "${ROMFS_PUSH_VIA:-}" >> "$FAKE_CALLS"
if [ -n "${FAKE_PUSH_FAILS:-}" ]; then echo "[RED] the copy is incomplete: Documents/romfs.img.part holds 5 of 10 bytes" >&2; exit 1; fi
echo "game files on the phone: $2"
'''


class Install(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='device install '); self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.folder = self.root / 'Fixture Game'; self.folder.mkdir()
        self.work = self.folder / f'{TITLE}_build'
        self.calls = self.root / 'calls'; self.plan = self.root / 'plan'; self.plan.write_text('')
        tools = self.root / 'bin'; tools.mkdir()
        for name, text in (('xcodebuild', FAKE_XCODEBUILD), ('xcrun', FAKE_XCRUN), ('build.py', FAKE_BUILD), ('push.sh', FAKE_PUSH)):
            (tools / name).write_text(text); (tools / name).chmod(0o755)
        self.environ = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ['PATH'], FAKE_CALLS=str(self.calls), FAKE_PLAN=str(self.plan),
                            FAKE_DEVICES=json.dumps({'result': {'devices': [device()]}}))
        for name in ('AETHERNX_TEAM', 'DM_TEAM_ID', 'AETHERNX_ASC_KEY', 'AETHERNX_ASC_KEY_ID', 'AETHERNX_ASC_ISSUER', 'ROMFS_PUSH_VIA', 'DM_ICLOUD_CONTAINER'): self.environ.pop(name, None)
        for patcher in (mock.patch.object(di, 'BUILD_SCRIPT', tools / 'build.py'), mock.patch.object(di, 'PUSH_SCRIPT', tools / 'push.sh'),
                        mock.patch.dict(os.environ, self.environ, clear=True)):   # list_devices and the tools are found through the process's own PATH
            patcher.start(); self.addCleanup(patcher.stop)

    def run_install(self, as_json, options):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = di.install(self.folder, self.work, build_args=options.pop('build_args', []), team=options.pop('team', TEAM), as_json=as_json,
                              environ=self.environ, **options)
        return code, out.getvalue()

    def install(self, **options):   # (exit code, the JSON events)
        code, text = self.run_install(True, options)
        return code, [json.loads(line) for line in text.splitlines()]

    def called(self, tool):
        if not self.calls.exists(): return []
        return [line.split(' ', 1)[1] for line in self.calls.read_text().splitlines() if line.startswith(tool + ' ')]

    def test_build_sign_install(self):
        code, events = self.install()
        self.assertEqual(code, 0)
        stages = [(e['k'], e['n'], e['name']) for e in events if e['ev'] == 'stage']
        self.assertEqual(stages, [(1, 4, 'extract'), (2, 4, 'prepare Xcode'), (3, 4, di.SIGN), (4, 4, di.INSTALL)])   # the build's two stages, counted with the two after them
        build = json.loads(self.called('build')[0].rsplit(' icloud=', 1)[0])
        self.assertEqual(build[:1] + build[1:], [str(self.folder), '--prepare-xcode', '--keep-extracted', '--team-id', TEAM, '--progress', 'json'])
        sign = json.loads(self.called('xcodebuild')[0])
        self.assertIn(f'id={UDID}', sign); self.assertIn(f'DEVELOPMENT_TEAM={TEAM}', sign); self.assertIn('Fixture Game (0100000000990000)', sign)
        app = self.work / 'xcode-derived-data/Build/Products/Release-iphoneos/DmIOS.app'
        self.assertEqual(json.loads(self.called('xcrun')[0]), ['devicectl', 'device', 'install', 'app', '--device', UDID, str(app)])
        self.assertEqual(len(self.called('xcrun')), 1)   # not opened on the device unless asked
        self.assertFalse(self.called('push'))   # the game files are in the app
        steps = [e['step'] for e in events if e['ev'] == 'step']
        self.assertIn('compiling', steps); self.assertIn('signing', steps)
        self.assertTrue(any(e['ev'] == 'progress' and e['frac'] == 0.45 for e in events))
        self.assertTrue(all(e['ok'] for e in events if e['ev'] == 'stage_end'))
        self.assertTrue(events[-1]['msg'].startswith('done: Fixture Game is on Fixture iPhone as ' + BUNDLE))
        saved = json.loads((self.work / 'xcode/install.json').read_text())
        self.assertEqual((saved['team'], saved['bundle_id'], saved['device']), (TEAM, BUNDLE, UDID))
        self.assertTrue((self.work / 'logs/device_build.log').read_text().strip())

    def test_plain_output_names_the_stages(self):
        code, text = self.run_install(False, {})
        self.assertEqual(code, 0)
        self.assertIn('[1/4] extract', text); self.assertIn(f'[3/4] {di.SIGN}', text); self.assertIn('      signing', text)
        self.assertIn('ready', text); self.assertNotIn('[12:00:00]', text); self.assertNotIn('{"ev"', text)

    def test_a_failed_build_signs_nothing(self):
        self.environ['FAKE_BUILD_FAILS'] = '1'
        with mock.patch.dict(os.environ, self.environ): code, events = self.install()
        self.assertEqual(code, 1)
        self.assertEqual(events[-1]['msg'], '[RED] no update in the folder')
        self.assertFalse(self.called('xcodebuild')); self.assertFalse(self.called('xcrun'))

    def test_a_profile_without_the_memory_capability_signs_without_it(self):
        self.plan.write_text('Provisioning profile "x" doesn\'t include the Increased Memory Limit capability.\n')
        code, events = self.install()
        self.assertEqual(code, 0)
        first, second = (json.loads(c) for c in self.called('xcodebuild'))
        self.assertFalse(any(w.startswith('CODE_SIGN_ENTITLEMENTS') for w in first)); self.assertIn('CODE_SIGN_ENTITLEMENTS=', second)
        said = [e['msg'] for e in events if e['ev'] == 'say']
        self.assertTrue(any('signed without the Increased Memory Limit' in m for m in said))
        self.assertEqual(len(self.called('xcrun')), 1)

    def test_an_identifier_of_another_team_is_signed_under_this_teams_and_kept(self):
        self.plan.write_text(f'Failed to register bundle identifier: The app identifier "{BUNDLE}" cannot be registered to your development team\n')
        code, _ = self.install()
        self.assertEqual(code, 0)
        variant = BUNDLE + '.' + TEAM.lower()
        self.assertIn(f'PRODUCT_BUNDLE_IDENTIFIER={variant}', json.loads(self.called('xcodebuild')[1]))
        self.assertEqual(json.loads((self.work / 'xcode/install.json').read_text())['bundle_id'], variant)
        code, events = self.install()   # the next install prepares the project with that identifier: the same app on the device, with its saves
        self.assertEqual(code, 0)
        again = json.loads(self.called('build')[1].rsplit(' icloud=', 1)[0])
        self.assertEqual(again[again.index('--bundle-id') + 1], variant)
        self.assertFalse(any(w.startswith('PRODUCT_BUNDLE_IDENTIFIER') for w in json.loads(self.called('xcodebuild')[2])))
        self.assertIn(variant, events[-1]['msg'])

    def test_the_identifier_is_not_carried_to_another_team(self):
        self.install()
        self.install(team='Z9Y8X7W6V5')
        self.assertNotIn('--bundle-id', json.loads(self.called('build')[1].rsplit(' icloud=', 1)[0]))

    def test_a_team_without_the_icloud_container_keeps_the_memory_capability(self):
        self.plan.write_text('Provisioning profile "x" doesn\'t include the iCloud capability.\n')
        code, events = self.install(icloud_container='iCloud.com.example.saves')
        self.assertEqual(code, 0)
        self.assertTrue(self.called('build')[0].endswith(' icloud=iCloud.com.example.saves'))
        retry = json.loads(self.called('xcodebuild')[1])
        entitlements = next(w.split('=', 1)[1] for w in retry if w.startswith('CODE_SIGN_ENTITLEMENTS='))
        import plistlib
        with open(entitlements, 'rb') as f: self.assertEqual(plistlib.load(f), {di.MEMORY_ENTITLEMENT: True})
        self.assertTrue(any('without the iCloud container' in e['msg'] for e in events if e['ev'] == 'say'))

    def test_no_account_stops_with_what_to_do(self):
        self.plan.write_text('No Accounts: Add a new account in Accounts settings.\n')
        with mock.patch.object(di, 'screen_locked', return_value=False):
            code, events = self.install()
        self.assertEqual(code, 1)
        self.assertEqual(len(self.called('xcodebuild')), 1)   # nothing to retry
        self.assertFalse(self.called('xcrun'))
        last = events[-1]['msg']
        self.assertTrue(last.startswith('[RED] signing for Fixture iPhone failed: Xcode has no Apple account')); self.assertIn('device_build.log', last)
        self.assertFalse(next(e for e in events if e['ev'] == 'stage_end' and e['name'] == di.SIGN)['ok'])
        self.assertFalse((self.work / 'xcode/install.json').exists())
        # the Mac's screen locked: Xcode cannot read its Apple ID, and wildcard-profile errors follow; one run, and the words say to unlock it
        self.environ['FAKE_CALLS_RESET'] = '1'
        self.plan.write_text("No Accounts: Add a new account in Accounts settings.\nProvisioning profile \"iOS Team Provisioning Profile: *\" doesn't include the Increased Memory Limit capability.\n")
        with mock.patch.object(di, 'screen_locked', return_value=True):
            code, events = self.install()
        self.assertEqual(code, 1)
        self.assertIn("while this Mac's screen is locked", events[-1]['msg'])

    def test_a_failure_it_does_not_know_shows_xcodebuilds_own_line(self):
        self.plan.write_text('use of undeclared identifier\n')
        code, events = self.install()
        self.assertEqual(code, 1)
        self.assertIn('use of undeclared identifier', events[-1]['msg'])

    def test_a_failed_install_is_reported(self):
        self.environ['FAKE_INSTALL_FAILS'] = '1'
        with mock.patch.dict(os.environ, self.environ): code, events = self.install()
        self.assertEqual(code, 1)
        self.assertIn('The device is locked', events[-1]['msg'])
        self.assertFalse((self.work / 'xcode/install.json').exists())

    def test_separate_game_files_are_copied_after_the_install(self):
        real = di.shutil.which   # afcclient installed (CI's runner has none: devicectl would copy, the next test)
        with mock.patch.object(di.shutil, 'which', lambda n: '/opt/homebrew/bin/afcclient' if n == 'afcclient' else real(n)):
            code, events = self.install(files='separate')
        self.assertEqual(code, 0)
        self.assertIn('--romfs', json.loads(self.called('build')[0].rsplit(' icloud=', 1)[0]))
        self.assertEqual([(e['k'], e['n']) for e in events if e['ev'] == 'stage'][-1], (5, 5))
        self.assertEqual(self.called('push'), [f'{UDID} {BUNDLE} {self.work / "xcode/Gen/resources.env"} via='])   # by cable: over AFC, the script's default

    def test_over_the_network_the_files_go_through_afc_else_devicectl(self):
        # afcclient reaches a device on the network too (push_romfs.sh adds -n) and streams the image; without it devicectl copies
        self.environ['FAKE_DEVICES'] = json.dumps({'result': {'devices': [device(transport='localNetwork')]}})
        real = di.shutil.which
        with mock.patch.dict(os.environ, self.environ), mock.patch.object(di.shutil, 'which', lambda n: '/opt/homebrew/bin/afcclient' if n == 'afcclient' else real(n)):
            code, _ = self.install(files='separate')
        self.assertEqual(code, 0)
        self.assertTrue(self.called('push')[0].endswith(' via='), self.called('push'))
        self.environ['FAKE_CALLS_RESET'] = '1'
        with mock.patch.dict(os.environ, self.environ), mock.patch.object(di.shutil, 'which', lambda n: None if n == 'afcclient' else real(n)):
            code, _ = self.install(files='separate')
        self.assertEqual(code, 0)
        self.assertTrue(self.called('push')[-1].endswith(' via=devicectl'))

    def test_files_that_did_not_reach_the_device_fail_the_install(self):
        self.environ['FAKE_PUSH_FAILS'] = '1'
        code, events = self.install(files='separate')
        self.assertEqual(code, 1)
        self.assertIn('its game files are not', events[-1]['msg']); self.assertIn('incomplete', events[-1]['msg'])
        self.assertTrue((self.work / 'xcode/install.json').exists())   # the app itself is installed: the next run signs it the same way

    def test_launch_opens_the_game(self):
        code, _ = self.install(launch=True)
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(self.called('xcrun')[1]), ['devicectl', 'device', 'process', 'launch', '--device', UDID, BUNDLE])

    def test_an_api_key_goes_to_xcodebuild(self):
        key = self.root / 'AuthKey_ABC123DEF4.p8'; key.write_text('fixture')
        code, _ = self.install(api_key=str(key), api_issuer='issuer-1')
        self.assertEqual(code, 0)
        sign = json.loads(self.called('xcodebuild')[0])
        self.assertEqual(sign[sign.index('-authenticationKeyID') + 1], 'ABC123DEF4'); self.assertEqual(sign[sign.index('-authenticationKeyIssuerID') + 1], 'issuer-1')


if __name__ == '__main__': unittest.main()
