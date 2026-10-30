"""Packing tools reading game files: bounded inflation of NRO frames (dm/tools/nro_collect.py), RomFS images staged without following a link left at the staging path
(dm/tools/romfs_image.py), CPK members kept inside the output folder (dm/gfx/tools/cpk.py). Synthetic inputs only: no game files, keys or tools needed."""
import os
from pathlib import Path
import struct
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO / 'dm/tools')); sys.path.insert(0, str(REPO / 'dm/gfx/tools'))
import cpk, nro_collect, romfs_image


def nro_header(size):   # the 0x40 bytes nro_size() reads: NRO0 at +0x10, the total size at +0x18
    h = bytearray(0x40); h[0x10:0x14] = b'NRO0'; struct.pack_into('<I', h, 0x18, size); return bytes(h)


class NroFrames(unittest.TestCase):
    def setUp(self):
        try: self.zstd = nro_collect.zstd_mod()
        except SystemExit: self.skipTest('no zstd module')

    def test_a_frame_that_inflates_past_its_header_is_refused(self):
        bomb = self.zstd.compress(nro_header(0x80) + bytes(16 << 20))   # a few KB that inflate to 16 MiB, claiming a 128-byte NRO
        self.assertLess(len(bomb), 1 << 16)
        self.assertIsNone(nro_collect.frame(bomb, 0, self.zstd, 0x80))

    def test_a_frame_of_exactly_its_size_is_kept(self):
        body = nro_header(0x1000) + bytes(range(256)) * 15 + bytes(0x1000 - 0x40 - 256 * 15)
        frame = b'pad' + self.zstd.compress(body)
        self.assertEqual(nro_collect.frame(frame, 3, self.zstd, 0x1000), body)
        self.assertIsNone(nro_collect.frame(frame, 3, self.zstd, 0x1001))   # ends short of what the header says


class RomfsStaging(unittest.TestCase):
    def test_a_link_at_the_old_staging_path_is_not_followed(self):
        with tempfile.TemporaryDirectory() as td:
            td = Path(td); src = td / 'romfs'; (src / 'a').mkdir(parents=True); (src / 'a/b.bin').write_bytes(b'data')
            victim = td / 'precious.txt'; victim.write_text('keep me')
            dst = td / 'RomFS.img'; (td / 'RomFS.img.part').symlink_to(victim)
            romfs_image.pack(src, dst)
            self.assertEqual(victim.read_text(), 'keep me')
            self.assertEqual(romfs_image.read_index(dst)['a/b.bin'][2], 4)
            self.assertEqual(dst.stat().st_mode & 0o777, 0o666 & ~self.umask())
            self.assertEqual(sorted(p.name for p in td.iterdir() if p.name.endswith('.part') and p.name != 'RomFS.img.part'), [])   # no staging file left

    @staticmethod
    def umask():
        m = os.umask(0); os.umask(m); return m


class CpkMembers(unittest.TestCase):
    def test_members_stay_inside_the_output_folder(self):
        with tempfile.TemporaryDirectory() as td:
            td = Path(td); out = td / 'out'; out.mkdir(); victim = td / 'victim'; victim.write_text('keep me')
            (out / 'link').symlink_to(td)
            read = cpk.read
            cpk.read = lambda p, e: b'written'
            try:
                for name in ('../victim', '/tmp/victim', 'link/victim', 'a/../../victim'):
                    with self.subTest(name=name), self.assertRaises(ValueError): cpk.extract('x.cpk', [(name, 0, 7, 7)], out)
                cpk.extract('x.cpk', [('dir/ok.bin', 0, 7, 7)], out)
            finally: cpk.read = read
            self.assertEqual(victim.read_text(), 'keep me')
            self.assertEqual((out / 'dir/ok.bin').read_bytes(), b'written')


if __name__ == '__main__':
    unittest.main()
