#!/usr/bin/env python3
"""Build a game, sign it with the player's own Apple team and install it on a paired iPhone or iPad: ./aethernx devices and ./aethernx install.

The build stays scripts/build_ipa_from_nsp.py --prepare-xcode, which makes the game's own Xcode project. This module then does what a player otherwise does by hand in
Xcode (docs/development.md, Build and run on a device with Xcode): xcodebuild signs the project for the chosen device (automatic signing, -allowProvisioningUpdates),
`devicectl device install app` installs it over the copy already there, which keeps the app's Documents (saves, game files copied earlier), and a build with the game
files separate gets them from scripts/push_romfs.sh. Nothing is signed or installed unless the player runs the command.

The route is NX2Apple's (LNPANDY/NX2Apple, MIT: frontend/Sources/NXCore/ShellInstall.swift), applied to AetherNX's one app per game: the same xcodebuild and devicectl
calls, the retry under the team's own identifier when the default one belongs to another team, and the retry without a capability the team's profile cannot carry.
"""
import json
import os
import plistlib
import shutil
import re
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILD_SCRIPT = ROOT / 'scripts' / 'build_ipa_from_nsp.py'
PUSH_SCRIPT = ROOT / 'scripts' / 'push_romfs.sh'
MEMORY_ENTITLEMENT = 'com.apple.developer.kernel.increased-memory-limit'
DEFAULT_BUNDLE_PREFIX = 'io.github.icosisenpai.horizonnative.'
# The stages after the build's own: sign, install, and the copy of the game files when they are separate
SIGN, INSTALL, COPY = 'sign for the device', 'install on the device', 'copy the game files'


class InstallError(Exception):
    pass


def run_text(cmd, timeout=60, env=None):
    try: r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, errors='replace', env=env, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.SubprocessError) as e: return 1, '', str(e)
    return r.returncode, r.stdout, r.stderr


# ---- devices and teams ----

def parse_devices(data):
    """The iPhones and iPads of `devicectl list devices --json-output`, the reachable ones first. `connection` is cable, network or none (paired once, not
    reachable now); `developer_mode` is None when the device does not say (it is off until the first development app is installed and the player turns it on)"""
    out = []
    for d in (data.get('result') or {}).get('devices') or []:
        hw, dp, cp = d.get('hardwareProperties') or {}, d.get('deviceProperties') or {}, d.get('connectionProperties') or {}
        if hw.get('deviceType') not in ('iPhone', 'iPad') or hw.get('reality', 'physical') != 'physical' or not hw.get('udid'): continue
        transport = str(cp.get('transportType') or '')
        out.append({'udid': hw['udid'], 'identifier': d.get('identifier') or '', 'name': dp.get('name') or hw.get('marketingName') or hw['deviceType'],
                    'model': hw.get('marketingName') or hw.get('productType') or '', 'kind': hw['deviceType'], 'os': dp.get('osVersionNumber') or '',
                    'connection': {'wired': 'cable', 'localNetwork': 'network'}.get(transport, 'none'),
                    'paired': cp.get('pairingState') == 'paired',
                    'developer_mode': {'enabled': True, 'disabled': False}.get(str(dp.get('developerModeStatus') or ''))})
    out.sort(key=lambda d: (d['connection'] == 'none', d['connection'] != 'cable', d['name'].lower(), d['udid']))
    return out


def list_devices():
    with tempfile.TemporaryDirectory(prefix='aethernx-devices-') as tmp:
        out = Path(tmp) / 'devices.json'
        code, _, err = run_text(['xcrun', 'devicectl', 'list', 'devices', '--json-output', str(out)], timeout=40)
        if code or not out.is_file():
            raise InstallError('devicectl could not list the devices' + (f': {err.strip().splitlines()[-1]}' if err.strip() else '') + ' (it comes with Xcode 15 or later)')
        try: data = json.loads(out.read_text())
        except ValueError as e: raise InstallError(f"devicectl's device list cannot be read: {e}") from e
    return parse_devices(data)


def parse_subject(subject):
    """The team of a signing certificate from `openssl x509 -subject -nameopt RFC2253`: its organizational unit (OU) is the team ID, its organization (O) the team's
    name. The code in the certificate's name, "Apple Development: Name (XXXXXXXXXX)", is the person's, not the team's"""
    fields = dict(re.findall(r'(?:^|,)\s*([A-Za-z]+)=((?:\\.|[^,\\])*)', subject.split('=', 1)[1] if subject.lower().startswith('subject') else subject))
    team = fields.get('OU', '')
    if not re.fullmatch(r'[A-Z0-9]{10}', team): return None
    return {'id': team, 'name': re.sub(r'\\(.)', r'\1', fields.get('O', '')) or team}


def signing_teams():
    """The teams this Mac has a development certificate for (Apple Development; iPhone Developer on older accounts), from the keychain. A team Xcode knows only
    through an account, with no certificate here yet, is not listed: --team takes its ID"""
    code, out, _ = run_text(['/usr/bin/security', 'find-identity', '-v', '-p', 'codesigning'])
    teams = {}
    for name in dict.fromkeys(re.findall(r'^\s*\d+\) [0-9A-F]{40} "((?:Apple Development|iPhone Developer)[^"]*)"', out if code == 0 else '', re.M)):
        code, pem, _ = run_text(['/usr/bin/security', 'find-certificate', '-c', name, '-p'])
        if code or not pem.strip(): continue
        try: r = subprocess.run(['/usr/bin/openssl', 'x509', '-noout', '-subject', '-nameopt', 'RFC2253'], input=pem, capture_output=True, text=True, timeout=20)
        except (OSError, subprocess.SubprocessError): continue
        team = parse_subject(r.stdout.strip()) if r.returncode == 0 else None
        if team and team['id'] not in teams: teams[team['id']] = dict(team, identity=name)
    return list(teams.values())


def pick_device(devices, wanted):
    """The device named by UDID, devicectl identifier or name; with none named, the only reachable one"""
    if wanted:
        low = wanted.lower()
        hits = [d for d in devices if low in (d['udid'].lower(), d['identifier'].lower())] or [d for d in devices if d['name'].lower() == low]
        if not hits: raise InstallError(f'no paired iPhone or iPad is named {wanted}: ./aethernx devices lists them')
        if len(hits) > 1:
            reachable = [d for d in hits if d['connection'] != 'none']
            if len(reachable) != 1: raise InstallError(f'{len(hits)} devices are named {wanted}: give the UDID (./aethernx devices)')
            hits = reachable
        dev = hits[0]
    else:
        reachable = [d for d in devices if d['connection'] != 'none']
        if not reachable: raise InstallError('no iPhone or iPad is connected: connect it with a cable (or have it on the same network, unlocked), then ./aethernx devices')
        if len(reachable) > 1: raise InstallError('several devices are connected: choose one with --device <UDID or name> (' + ', '.join(f"{d['name']} {d['udid']}" for d in reachable) + ')')
        dev = reachable[0]
    if dev['connection'] == 'none':
        raise InstallError(f"{dev['name']} is paired with this Mac but not reachable now: connect it with a cable, or unlock it on the same network")
    if dev['developer_mode'] is False:
        raise InstallError(f"Developer Mode is off on {dev['name']}: turn it on in Settings › Privacy & Security › Developer Mode (the phone restarts), then run this again")
    return dev


def pick_team(wanted, saved=None, teams=signing_teams):
    """The team named, else the one this game was last signed with, else the only one with a certificate here (the keychain is read only then)"""
    if wanted:
        if not re.fullmatch(r'[A-Z0-9]{10}', wanted): raise InstallError(f'a team ID is ten letters and digits, such as A1B2C3D4E5: {wanted}')
        return wanted
    teams = teams()
    if saved and (not teams or any(t['id'] == saved for t in teams)): return saved
    if len(teams) == 1: return teams[0]['id']
    if not teams:
        raise InstallError('no Apple development certificate on this Mac: sign in with your Apple ID in Xcode › Settings › Accounts and press Manage Certificates › + › '
                           'Apple Development, or give your team with --team <team ID>')
    raise InstallError('several signing teams on this Mac: choose one with --team (' + ', '.join(f"{t['id']} {t['name']}" for t in teams) + ')')


def api_key_args(key, key_id, issuer):
    """xcodebuild's App Store Connect API key options, for a Mac whose Xcode has no Apple ID signed in. The key ID comes from the file's name (AuthKey_<ID>.p8) when
    it is not given; the issuer ID is the account's and has no default"""
    if not key and not key_id and not issuer: return []
    if not key: raise InstallError('--api-key-id and --api-issuer go with --api-key <AuthKey_….p8>')
    path = Path(key).expanduser()
    if not path.is_file(): raise InstallError(f'no such API key file: {path}')
    key_id = key_id or (m[1] if (m := re.fullmatch(r'AuthKey_([A-Z0-9]+)\.p8', path.name)) else '')
    if not key_id: raise InstallError(f'give the key ID with --api-key-id: {path.name} does not carry it in its name (AuthKey_<ID>.p8)')
    if not issuer: raise InstallError('give the issuer ID of the API key with --api-issuer (App Store Connect › Users and Access › Integrations), or set AETHERNX_ASC_ISSUER')
    return ['-authenticationKeyPath', str(path.resolve()), '-authenticationKeyID', key_id, '-authenticationKeyIssuerID', issuer]


# ---- the project a build prepared ----

def project_facts(project):
    """What the prepared project says about itself: its scheme, the folder its build goes to and its signing settings"""
    project = Path(project)
    schemes = sorted((project / 'xcshareddata' / 'xcschemes').glob('*.xcscheme'))
    if len(schemes) != 1: raise InstallError(f'the Xcode project has {len(schemes)} schemes, not one: {project} (prepare the game again)')
    root = None
    try:
        for line in (project.parent / 'Gen' / 'dm.xcconfig').read_text().splitlines():
            if m := re.fullmatch(r'\s*DM_XCODE_OUTPUT_ROOT\s*=\s*(.+?)\s*', line): root = Path(m[1])
    except OSError: pass
    sys.path.insert(0, str(ROOT / 'dm' / 'ios' / 'tools'))
    import xcode_projects
    try: signing = xcode_projects.signing_settings(project)
    except ValueError as e: raise InstallError(str(e)) from e
    return {'scheme': schemes[0].stem, 'output': root or project.parent.parent / 'xcode-derived-data', 'bundle_id': signing.get('PRODUCT_BUNDLE_IDENTIFIER', ''),
            'team': signing.get('DEVELOPMENT_TEAM', '')}


def sign_command(project, facts, udid, team, bundle_id=None, entitlements=None, auth=()):
    """`bundle_id` and `entitlements` override the project's for this build only (a build setting on the command line wins over the project and its xcconfig);
    entitlements '' signs with none"""
    cmd = ['xcodebuild', '-project', str(project), '-scheme', facts['scheme'], '-configuration', 'Release', '-destination', f'id={udid}',
           '-derivedDataPath', str(facts['output']), '-allowProvisioningUpdates', '-allowProvisioningDeviceRegistration', *auth, f'DEVELOPMENT_TEAM={team}']
    if bundle_id: cmd.append(f'PRODUCT_BUNDLE_IDENTIFIER={bundle_id}')
    if entitlements is not None: cmd.append(f'CODE_SIGN_ENTITLEMENTS={entitlements}')
    return cmd + ['build']


def team_variant(bundle_id, team):
    """The identifier a second team signs a game with: an App ID belongs to the first team that registered it, so the default one, the same for every player, is
    taken for everyone but that team (and a paid team's identifiers cannot be registered by a free one either)"""
    tail = '.' + team.lower()
    return bundle_id if bundle_id.lower().endswith(tail) else bundle_id + tail


FAILURES = (
    # kind, pattern, what to tell the player (None: the caller retries). The account comes first: without one Xcode can only use the team's wildcard
    # profile, so the capability errors that follow are its consequence, and dropping capabilities would only end in the same failure
    ('api_key', r'Authentication failed: Make sure a bearer token|bearer token was provided',
     "the App Store Connect API key was refused: it must be a team key with the Admin or App Manager role (a key made for notarization only cannot manage profiles)"),
    ('account', r"No Accounts?:|No Account for Team|Add a new account in Accounts settings|doesn't have any .*accounts|Unable to log in with account|"
                r'Authentication failed|authentication credentials are missing or invalid',
     'Xcode has no Apple account for this team: add your Apple ID in Xcode › Settings › Accounts (or pass an App Store Connect API key: --api-key, --api-issuer), then run this again'),
    ('memory', r"doesn't include the Increased Memory Limit capability|doesn't include the com\.apple\.developer\.kernel\.increased-memory-limit entitlement", None),
    ('icloud', r"doesn't (?:include|support) the iCloud capability|doesn't include the com\.apple\.developer\.(?:icloud-container-identifiers|icloud-services|ubiquity-container-identifiers) entitlement|"
               r"doesn't match the entitlements file's value for the com\.apple\.developer\.(?:icloud|ubiquity)-container-identifiers entitlement|iCloud container .* (?:is not available|cannot be)", None),
    ('bundle', r'cannot be registered to your development team', None),
    ('app_ids', r'(?i)maximum number of app ids|maximum App ID limit|you have reached the limit of \d+ app ids|\b9120\b.*app id',
     'your Apple ID has no free App ID left: a free account registers ten in seven days. Wait for the oldest to expire, or use a paid team'),
    ('free_limit', r'(?i)maximum number of (?:provisioning profiles|installed apps|apps for free development profiles|provisioned iOS devices)|code -36607',
     'the limit of a free Apple ID is reached (three apps on a device, a few devices): remove an app you sideloaded from the device, or use a paid team'),
    ('agreement', r'(?i)(?:program license agreement|PLA Update available|agreement.*(?:must be|has not been|needs to be) accepted)',
     'Apple wants a new agreement accepted first: sign in at developer.apple.com/account and accept it, then run this again'),
    ('destination', r'Unable to find a destination matching the provided destination specifier',
     'Xcode cannot reach the device: unlock it, keep it connected and trusted (and Developer Mode on), then run this again'),
    ('space', r'No space left on device', 'the disk with the build folder is full: the first device build copies the whole game into the app'),
)


def screen_locked():   # this Mac's login screen is up: Xcode reads its Apple ID only from an unlocked session, and reports "No Accounts" meanwhile
    try: out = subprocess.run(['/usr/sbin/ioreg', '-n', 'Root', '-d1', '-a'], capture_output=True, timeout=10).stdout
    except (OSError, subprocess.SubprocessError): return False
    try: users = plistlib.loads(out).get('IOConsoleUsers') or []
    except Exception: return False
    return any(u.get('CGSSessionScreenIsLocked') for u in users if isinstance(u, dict))


def classify(output, bundle_id=''):
    """(kind, message) of a failed xcodebuild run; kind '' when its words are not ones this knows, the message then being its last error line"""
    for kind, pattern, message in FAILURES:
        if re.search(pattern, output): return kind, message
    if bundle_id and f"No profiles for '{bundle_id}'" in output: return 'bundle', None
    errors = [ln.strip() for ln in output.splitlines() if 'error:' in ln or ln.startswith('ERROR:')]
    return '', (re.sub(r'^.*?error:\s*', '', errors[-1]) if errors else '')


XCODE_STEPS = (('CompileC ', 'compiling'), ('SwiftCompile ', 'compiling'), ('CompileSwift ', 'compiling'), ('Ld ', 'linking'),
               ('PhaseScriptExecution Copy', 'copying the game files into the app'), ('ProcessProductPackaging ', 'provisioning'), ('CodeSign ', 'signing'))


def xcode_step(line):
    return next((name for prefix, name in XCODE_STEPS if line.startswith(prefix)), None)


def percent_in(line):   # devicectl's own progress: "… 45%"
    m = re.search(r'(\d{1,3})%', line)
    return min(int(m[1]), 100) / 100 if m else None


# ---- output: the build script's events, continued ----

class Report:
    """The front end's view of the whole install: with --progress json the build script's events pass through, their stage count raised by the stages that follow
    (docs/frontends.md), and those stages are reported the same way; without it, plain lines"""

    def __init__(self, as_json, extra):
        self.as_json, self.extra, self.k, self.n, self.stage_name, self.t0 = as_json, extra, 0, extra, '', time.time()
        self.game = {}

    def emit(self, ev, **fields):
        print(json.dumps({'ev': ev, 't': round(time.time(), 3), **fields}, ensure_ascii=False), flush=True)

    def say(self, msg):
        if self.as_json: self.emit('say', msg=msg)
        else: print(msg, flush=True)

    def build_line(self, line):
        """One stdout line of the build script (always run with --progress json)"""
        try: ev = json.loads(line) if line.startswith('{') else None
        except ValueError: ev = None
        if not isinstance(ev, dict) or 'ev' not in ev:
            if line.strip(): self.say(line.rstrip())
            return
        if ev['ev'] == 'stage':
            self.k = int(ev.get('k') or self.k); self.n = int(ev.get('n') or 0) + self.extra; ev['n'] = self.n
            if not self.as_json: print(f"[{self.k}/{self.n}] {ev.get('name', '')}", flush=True)
        elif ev['ev'] == 'game': self.game = ev
        elif ev['ev'] == 'say' and not self.as_json: print(re.sub(r'^\[[0-9:]+\] ', '', str(ev.get('msg', ''))), flush=True)
        elif ev['ev'] == 'stage_end' and not self.as_json and ev.get('summary'): print(f"      {ev['summary']}", flush=True)
        if self.as_json: print(json.dumps(ev, ensure_ascii=False), flush=True)

    def stage(self, name):
        self.k += 1; self.n = max(self.n, self.k); self.stage_name, self.t0, self._step = name, time.time(), ''
        if self.as_json: self.emit('stage', k=self.k, n=self.n, name=name, step='')
        else: print(f'[{self.k}/{self.n}] {name}', flush=True)

    def step(self, step):
        if step == getattr(self, '_step', ''): return
        self._step = step
        if self.as_json: self.emit('step', k=self.k, name=self.stage_name, step=step)
        else: print(f'      {step}', flush=True)

    def progress(self, frac):
        if self.as_json:
            self.emit('progress', k=self.k, name=self.stage_name, step=getattr(self, '_step', ''), done=round(frac * 100), total=100, unit='%', est=False, note='',
                      frac=min(frac, 0.99), eta=None, elapsed=round(time.time() - self.t0, 1))

    def end(self, ok, summary=''):
        if self.as_json: self.emit('stage_end', k=self.k, name=self.stage_name, ok=ok, summary=summary, elapsed=round(time.time() - self.t0, 1))
        elif summary: print(f'      {summary}', flush=True)


def stream(cmd, on_line, log=None, env=None):
    """Run a tool, hand each output line over and return (exit code, whole output). Ctrl-C and a front end's Stop (SIGINT, then SIGTERM) end the tool too"""
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL, text=True, errors='replace', env=env, start_new_session=True)
    lines, out = [], open(log, 'w') if log else None   # noqa: SIM115 (closed below, after the tool has ended)
    assert proc.stdout is not None
    try:
        for raw in proc.stdout:
            for line in raw.rstrip('\n').split('\r'):   # devicectl redraws its progress with carriage returns
                lines.append(line)
                if out: out.write(line + '\n')
                on_line(line)
        return proc.wait(), '\n'.join(lines)
    except KeyboardInterrupt:
        stop_group(proc)
        raise
    finally:
        proc.stdout.close()
        if out: out.close()


def stop_group(proc):   # the tool and what it started (xcodebuild's compilers, the build script's tools): its own process group
    for sig, wait in ((signal.SIGINT, 8), (signal.SIGTERM, 4), (signal.SIGKILL, 2)):
        try: os.killpg(proc.pid, sig)
        except (ProcessLookupError, PermissionError): return
        try: proc.wait(timeout=wait); return
        except subprocess.TimeoutExpired: continue


# ---- install ----

def remembered(work):
    try: data = json.loads((Path(work) / 'xcode' / 'install.json').read_text())
    except (OSError, ValueError): return {}
    return data if isinstance(data, dict) else {}


def remember(work, **facts):
    path = Path(work) / 'xcode' / 'install.json'
    tmp = path.with_suffix('.tmp')
    tmp.write_text(json.dumps(facts, indent=1) + '\n'); tmp.replace(path)


def memory_only_entitlements(folder):
    path = Path(folder) / 'DmIOS-memory.entitlements'
    with open(path, 'wb') as f: plistlib.dump({MEMORY_ENTITLEMENT: True}, f)
    return path


def files_mode(files, dev, afcclient=None, has_image=False):
    """'auto' as the device allows. The game files are kept on the device (separate), which makes every later install move only the app (Fire Emblem Fortune's
    Weave: 2.1 GB instead of 29 GB, push_romfs.sh skips an image the device already has), when afcclient can stream them and either the device is on the cable
    (about 30 MB/s) or it already holds this game's image (has_image). On the network only, a first copy over AFC runs at about 8 MB/s (an hour for 27 GB) where
    devicectl installs an app at about 36 MB/s, so a first install there puts the files in the app (bundle); --files separate copies them once all the same"""
    if files != 'auto': return files
    afc = afcclient if afcclient is not None else shutil.which('afcclient')
    if not afc: return 'bundle'
    return 'separate' if dev['connection'] == 'cable' or (dev['connection'] == 'network' and has_image) else 'bundle'


def local_image(work):
    """The newest RomFS image a build of this game left (<build>/extract/<version>/RomFS.img), else None"""
    images = [p for p in Path(work).glob('extract/*/RomFS.img') if p.is_file()]
    return max(images, key=lambda p: p.stat().st_mtime) if images else None


def device_has_image(dev, bundle_id, work, afcclient=None, run=None):
    """The device holds the image a separate install would copy: Documents/romfs.img.id, which push_romfs.sh writes after a complete copy, is the identity of the
    image this game's last build made. Read-only: afcclient copies that small file back. False when anything is missing"""
    run = run or run_text
    afc = afcclient if afcclient is not None else shutil.which('afcclient')
    image = local_image(work)
    if not afc or not image or not bundle_id: return False
    code, ident, _ = run([sys.executable, str(ROOT / 'dm' / 'tools' / 'romfs_image.py'), '--identity', str(image)], timeout=60)
    if code or not ident.strip(): return False
    with tempfile.TemporaryDirectory(prefix='aethernx-romfs-id-') as tmp:
        out = Path(tmp) / 'romfs.img.id'
        run([afc, '-u', dev['udid'], '--container', bundle_id, *(['-n'] if dev['connection'] == 'network' else []), '--', 'get', '/Documents/romfs.img.id', str(out)], timeout=60)
        return out.is_file() and out.read_text(errors='replace').strip() == ident.strip()


def install(folder, work, *, build_args, keys=None, device=None, team=None, files='bundle', icloud_container='', launch=False, as_json=False,
            api_key=None, api_key_id=None, api_issuer=None, python=sys.executable, environ=None):
    """Build the game in `folder` for the device, sign it, install it and copy its files when they are separate. Returns the exit code"""
    environ = dict(os.environ if environ is None else environ)
    work = Path(work)
    dev = pick_device(list_devices(), device)
    last = remembered(work)
    has_image = files == 'auto' and dev['connection'] == 'network' and device_has_image(dev, last.get('bundle_id'), work)
    asked, files = files, files_mode(files, dev, has_image=has_image)
    report = Report(as_json, 3 if files == 'separate' else 2)
    if asked == 'auto':
        if files == 'separate':
            report.say('the device already has this game\'s files: only the app is copied' if has_image
                       else 'the game files stay on the device (copied once over the cable): later installs copy only the app')
        elif not shutil.which('afcclient'):
            report.say('the game files go inside the app (brew install libimobiledevice keeps them on the device, so later installs copy only the app)')
        else:
            report.say('the game files go inside the app: the device is on the network, where a first copy of them is slow; connect it by cable once (or install with '
                       '--files separate) to keep them on the device')
    team = pick_team(team or environ.get('AETHERNX_TEAM') or environ.get('DM_TEAM_ID'), saved=last.get('team'))
    auth = api_key_args(api_key or environ.get('AETHERNX_ASC_KEY'), api_key_id or environ.get('AETHERNX_ASC_KEY_ID'), api_issuer or environ.get('AETHERNX_ASC_ISSUER'))
    report.say(f"installing on {dev['name']} ({dev['model'] or dev['kind']}, {dev['os']}; over the {'cable' if dev['connection'] == 'cable' else 'network'}), signed by team {team}")

    # 1: the game's Xcode project, with the identifier this team signed it with last time (another one would be a second app with its own saves)
    cmd = [python, str(BUILD_SCRIPT), str(folder), *(['-k', str(keys)] if keys else []), '--prepare-xcode', '--keep-extracted',
           '--team-id', team, '--progress', 'json', *(['--romfs', 'separate'] if files == 'separate' else []), *build_args]
    if last.get('team') == team and last.get('bundle_id') and '--bundle-id' not in build_args: cmd += ['--bundle-id', last['bundle_id']]
    env = dict(environ)
    if icloud_container: env['DM_ICLOUD_CONTAINER'] = icloud_container
    code, _ = stream(cmd, report.build_line, env=env)
    if code: return code
    project = work / 'xcode' / 'DmIOS.xcodeproj'
    if not project.is_dir(): raise InstallError(f'the build left no Xcode project at {project}')
    facts = project_facts(project)
    bundle_id = facts['bundle_id'] or report.game.get('bundle_id') or ''
    logs = work / 'logs'; logs.mkdir(parents=True, exist_ok=True)

    # 2: sign for the device, retrying once for each thing a team may not be able to sign
    report.stage(SIGN)
    override, entitlements, notes, tried = None, None, [], set()
    while True:
        report.step('starting xcodebuild')
        code, output = stream(sign_command(project, facts, dev['udid'], team, override, entitlements, auth), lambda ln: (s := xcode_step(ln)) and report.step(s),
                              log=logs / 'device_build.log')
        if code == 0: break
        kind, message = classify(output, override or bundle_id)
        if kind == 'bundle' and 'bundle' not in tried and team_variant(bundle_id, team) != (override or bundle_id):
            tried.add('bundle'); override = team_variant(bundle_id, team)
            report.say(f'{bundle_id} is registered to another team: signing as {override}')
            continue
        if kind == 'icloud' and 'icloud' not in tried and icloud_container:
            tried.add('icloud'); entitlements = str(memory_only_entitlements(logs))
            notes.append('signed without the iCloud container, which this team cannot use: choose a cloud saves folder in the app instead (Cloud saves)')
            report.say('this team cannot sign with the iCloud container: signing without it')
            continue
        if kind in ('memory', 'icloud') and 'memory' not in tried:
            tried.add('memory'); entitlements = ''
            notes.append("signed without the Increased Memory Limit, which this team's profile cannot carry: a large game may be closed by iOS for memory")
            report.say("the team's provisioning profile cannot carry the Increased Memory Limit: signing without it (a large game may run out of memory)")
            continue
        if kind == 'account' and screen_locked():
            message = "Xcode cannot read its Apple ID while this Mac's screen is locked: unlock the Mac, then install again"
        report.end(False, message or f'xcodebuild stopped with exit code {code}')
        report.say(f"[RED] signing for {dev['name']} failed: {message or f'xcodebuild stopped with exit code {code}'} (the whole output: {logs / 'device_build.log'})")
        return 1
    report.end(True)
    signed_as = override or bundle_id
    app = facts['output'] / 'Build' / 'Products' / 'Release-iphoneos' / 'DmIOS.app'
    if not app.is_dir(): raise InstallError(f'xcodebuild left no app at {app}')

    # 3: install over the copy already there, which keeps its Documents
    report.stage(INSTALL)
    code, output = stream(['xcrun', 'devicectl', 'device', 'install', 'app', '--device', dev['udid'], str(app)],
                          lambda ln: (f := percent_in(ln)) is not None and report.progress(f), log=logs / 'device_install.log')
    if code:
        why = next((ln.strip() for ln in reversed(output.splitlines()) if 'error' in ln.lower()), '') or f'devicectl stopped with exit code {code}'
        report.end(False, why)
        report.say(f"[RED] the install on {dev['name']} failed: {why} (keep the device unlocked; the whole output: {logs / 'device_install.log'})")
        return 1
    report.end(True)
    remember(work, team=team, bundle_id=signed_as, device=dev['udid'], device_name=dev['name'], installed=time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()))

    # 4: the game files of a build that leaves them out of the app
    if files == 'separate':
        report.stage(COPY)
        env = dict(environ)
        # afcclient streams the image, over the cable or the network (push_romfs.sh adds -n); without it devicectl copies, and refuses an image it cannot hold in memory
        if not shutil.which('afcclient'): env.setdefault('ROMFS_PUSH_VIA', 'devicectl')
        def copy_line(ln):
            frac = percent_in(ln)
            if frac is not None: report.progress(frac)
            elif ln.strip(): report.step(ln.strip()[:120])
        code, output = stream(['bash', str(PUSH_SCRIPT), dev['udid'], signed_as, str(project.parent / 'Gen' / 'resources.env')], copy_line,
                              log=logs / 'device_copy.log', env=env)
        if code:
            why = next((ln.strip() for ln in reversed(output.splitlines()) if '[RED]' in ln), '') or f'push_romfs.sh stopped with exit code {code}'
            report.end(False, why)
            report.say(f"[RED] the app is on {dev['name']}, its game files are not: {why.replace('[RED] ', '')}")
            return 1
        report.end(True)

    if launch:
        code, _, err = run_text(['xcrun', 'devicectl', 'device', 'process', 'launch', '--device', dev['udid'], signed_as], timeout=90)
        if code: notes.append(f"the app did not open by itself ({(err.strip().splitlines() or ['no reason given'])[-1]}): open it on the device")
    for note in notes: report.say(note)
    name = report.game.get('name') or Path(folder).name
    report.say(f"done: {name} is on {dev['name']} as {signed_as}. The first time, trust the developer on the device in Settings › General › VPN & Device Management")
    return 0
