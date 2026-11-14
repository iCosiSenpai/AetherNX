#!/usr/bin/env python3
"""The NVN depth mode the build makes pipeline bases for (build_ipa_from_nsp.py depth_mode): the profile's depth_mode, else the build folder's record, else this Mac's log of
the game, else the build's own logs, else NVN's gl. A mode learned from a log is recorded. No game files needed"""
import importlib
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

REPO = Path(__file__).resolve().parents[3]
for folder in ('scripts', 'dm/tools', 'dm/games'):
    if str(REPO / folder) not in sys.path: sys.path.insert(0, str(REPO / folder))
build = importlib.import_module('build_ipa_from_nsp')


class Profile(dict):
    id = '0100000000990000'


class DepthMode(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.work = self.root / 'work'; (self.work / 'logs').mkdir(parents=True)
        self.home = self.root / 'home'; (self.home / 'Library/Logs/HorizonNative').mkdir(parents=True)
        patcher = mock.patch.object(build.Path, 'home', return_value=self.home); patcher.start(); self.addCleanup(patcher.stop)

    def test_the_profile_wins(self):
        (self.home / f'Library/Logs/HorizonNative/{Profile.id}.log').write_text('[dm] [nvn] depth mode near=-w (GL)\n')
        self.assertEqual(build.depth_mode(Profile(depth_mode='zero'), self.work), ('zero', 'the profile'))

    def test_without_a_run_it_is_nvns_default(self):
        self.assertEqual(build.depth_mode(Profile(), self.work), ('gl', None))
        self.assertFalse((self.work / 'depth_mode').exists())

    def test_this_macs_log_of_the_game_is_learned_and_recorded(self):
        log = self.home / f'Library/Logs/HorizonNative/{Profile.id}.log'
        log.write_text('[dm] boot\n[dm] [nvn] depth mode near=0 (as D3D / Metal)\n')
        self.assertEqual(build.depth_mode(Profile(), self.work), ('zero', str(log)))
        self.assertEqual((self.work / 'depth_mode').read_text(), f'zero\t{log}\n')
        log.unlink()   # the record keeps it for the next builds
        self.assertEqual(build.depth_mode(Profile(), self.work)[0], 'zero')

    def test_the_builds_own_runs_and_a_devices_record(self):
        (self.work / 'logs/heap_check.log').write_text('[dm] [nvn] depth mode near=0 (as D3D / Metal)\n')
        self.assertEqual(build.depth_mode(Profile(), self.work)[0], 'zero')
        (self.work / 'depth_mode').write_text("gl\tFixture iPhone's log of the game\n")   # what ./aethernx install read on the device wins over older logs
        self.assertEqual(build.depth_mode(Profile(), self.work), ('gl', "Fixture iPhone's log of the game"))

    def test_the_last_line_of_a_log_counts(self):
        log = self.root / 'host.log'
        log.write_text('[dm] [nvn] depth mode near=-w (GL)\n[dm] [nvn] depth mode near=0 (as D3D / Metal)\n')
        self.assertEqual(build.depth_in_log(log), 'zero')
        self.assertIsNone(build.depth_in_log(self.root / 'missing.log'))


if __name__ == '__main__':
    unittest.main()
