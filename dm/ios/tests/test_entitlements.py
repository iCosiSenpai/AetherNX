#!/usr/bin/env python3
"""The entitlements build_ipa.sh writes for a prepared Xcode project: its own lines, run on a scratch Gen/DmIOS.entitlements. DM_ICLOUD_CONTAINER adds the iCloud
container, the ubiquity container and iCloud Documents beside the Increased Memory Limit (a key's dots must be escaped for plutil, which reads keys as key paths)"""
import os
import plistlib
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / 'tools' / 'build_ipa.sh'


def icloud_block():   # the script's `if [ -n "${DM_ICLOUD_CONTAINER:-}" ]; then … fi` lines
    text = SCRIPT.read_text()
    m = re.search(r'^  if \[ -n "\$\{DM_ICLOUD_CONTAINER:-\}" \]; then\n.*?^  fi$', text, re.M | re.S)
    assert m, 'build_ipa.sh has no DM_ICLOUD_CONTAINER block'
    return m[0]


@unittest.skipUnless(Path('/usr/bin/plutil').exists(), 'macOS plutil')
class Entitlements(unittest.TestCase):
    def test_the_icloud_container_reaches_the_entitlements(self):
        with tempfile.TemporaryDirectory() as tmp:
            gen = Path(tmp) / 'Gen'; gen.mkdir()
            with open(gen / 'DmIOS.entitlements', 'wb') as f: plistlib.dump({'com.apple.developer.kernel.increased-memory-limit': True}, f)
            script = 'die() { echo "FAIL: $*" >&2; exit 1; }\n' + icloud_block()
            r = subprocess.run(['/bin/bash', '-c', script], cwd=tmp, capture_output=True, text=True,
                               env={**os.environ, 'DM_ICLOUD_CONTAINER': 'iCloud.com.example.test'})
            self.assertEqual(r.returncode, 0, r.stderr)
            with open(gen / 'DmIOS.entitlements', 'rb') as f: ent = plistlib.load(f)
            self.assertEqual(ent, {'com.apple.developer.kernel.increased-memory-limit': True,
                                   'com.apple.developer.icloud-container-identifiers': ['iCloud.com.example.test'],
                                   'com.apple.developer.ubiquity-container-identifiers': ['iCloud.com.example.test'],
                                   'com.apple.developer.icloud-services': ['CloudDocuments']})


if __name__ == '__main__':
    unittest.main()
