"""forge.py and shader_split.py's forge reader on synthetic Ubisoft forge archives, without game files: the index and meta tables (a cleared slot among them), datafile headers with
dependency pairs, compressed sections of stored and decoder chunks, object tables (with the DataBlock files' trailer), NVN shader records, and the checks that keep a damaged archive
from reading outside its bytes."""
from pathlib import Path
import os
import struct
import sys
import tempfile
import unittest
import zlib

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
os.environ.setdefault('DM_GAME', '010015100B514000')
import forge
import shader_split as split

MATERIAL = 0xbcfb3c7a   # the type of AC2's material templates, which hold its shader records
TEXTURE = 0xa2b7e917


def program(stage, n=0x100, fill=0):
    """A code area and control section of one stage (the code area's SPH gives the stage)"""
    code = bytearray([fill]) * n; code[:4] = forge.GFX_MAGIC
    struct.pack_into('<I', code, 0x30, {'vs': 1, 'ps': 5}[stage] << 10)
    ctl = bytearray(0x880); ctl[:4] = forge.CTL_MAGIC
    struct.pack_into('<I', ctl, 0x20, len(ctl)); struct.pack_into('<I', ctl, 0x704, len(code))
    return bytes(code), bytes(ctl)


def record(stage, **kw):   # a shader record: {control length, code offset, code length, …} 0x30 bytes, the control section, the code area, then reflection data
    code, ctl = program(stage, **kw)
    return struct.pack('<3I', len(ctl), len(ctl), len(code)) + bytes(0x24) + ctl + code + b'refl' * 8


def obj(typ, name, body, flag=0):
    n = name.encode()
    return struct.pack('<III', typ, len(body), len(n)) + n + bytes([flag]) + body


def table(rows, extra=b''):
    return struct.pack('<H', len(rows)) + b''.join(struct.pack('<IIH', oid, len(b), x) for oid, b, x in rows) + struct.pack('<I', len(extra)) + extra


class Codec:
    """A stand-in for the game's Oodle: a coded chunk is 8C 0C and a token, which decodes to the bytes it stands for"""
    def __init__(self): self.plain, self.calls = {}, []

    def __call__(self, comp, n):
        self.calls.append((comp, n)); return self.plain[comp][:n]

    def section(self, data, coded=(), kind=6, big=0x8000):
        chunks = [data[i:i + big] for i in range(0, len(data), big)]
        stored = []
        for k, c in enumerate(chunks):
            if k in coded:
                s = bytes([0x8c, 0x0c]) + struct.pack('<I', len(self.plain)) + b'tok'
                self.plain[s] = c; stored.append(s)
            else: stored.append(c)
        head = forge.BLOCK_MAGIC + struct.pack('<HBHHH', 1, kind, big, big, len(chunks)) + b''.join(struct.pack('<HH', len(c), len(s)) for c, s in zip(chunks, stored))
        return head + b''.join(struct.pack('<I', zlib.adler32(s, 0)) + s for s in stored)


def datafile(codec, name, fid, rows, extra=b'', deps=(), coded=(1,), raw=None):
    """A datafile's header and data: dependency pairs, the object table and the objects as two sections, a u32"""
    body = raw if raw is not None else (b''.join(struct.pack('<II', d, 2) for d in deps) + codec.section(table(rows, extra))
                                        + codec.section(b''.join(b for _, b, _ in rows), coded) + struct.pack('<I', 0))
    head = bytearray(forge.HEAD); head[:8] = forge.FILEDATA; head[8:8 + len(name)] = name.encode()
    struct.pack_into('<IIQ', head, 0x187, fid, len(body), fid * 3); struct.pack_into('<I', head, 0x1b8, len(deps))
    return bytes(head) + body


def archive(files, version=31, slots=8, cleared=()):
    """files: [(name, file ID, datafile)] → the archive; the slots in cleared get ID 0 and size 0 in the index, their data stays"""
    hoff = 0x416; toff = hoff + 0x28; ioff = toff + forge.TABLE; moff = ioff + forge.INDEX * slots; data = moff + forge.META * slots
    idx, meta, blob = bytearray(), bytearray(), bytearray()
    for k, (name, fid, df) in enumerate(files):
        off = data + len(blob); blob += df.ljust((len(df) + 0x7ff) & ~0x7ff, b'\0')
        dsize = len(df) - forge.HEAD
        idx += struct.pack('<QII', off, 0, 0) if k in cleared else struct.pack('<QII', off, fid, dsize)
        m = bytearray(forge.META); struct.pack_into('<IQ', m, 0, dsize, fid * 3); struct.pack_into('<ii', m, 0x1c, k + 1, k - 1); m[0x2c:0x2c + len(name)] = name.encode(); meta += m
    idx = idx.ljust(forge.INDEX * slots, b'\0'); meta = meta.ljust(forge.META * slots, b'\0')
    out = bytearray(forge.MAGIC + struct.pack('<IQ', version, hoff)).ljust(hoff, b'\0')
    out += struct.pack('<IIqqIIQ', len(files), 1, 0, -1, slots, 1, toff)
    out += struct.pack('<IIQqIIQQ', len(files), 1, ioff, -1, 0, slots - 1, moff, data)
    return bytes(out + idx + meta + blob)


class ForgeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.dir = Path(self.tmp.name)
        self.codec = Codec()
        self.vs, self.ps = record('vs'), record('ps', n=0x200, fill=7)
        self.material = obj(MATERIAL, 'Default Material Template', b'\x01' + struct.pack('<II', 0x30, MATERIAL) + self.vs + bytes(13) + self.ps)
        self.texture = obj(TEXTURE, 'WhiteTexture', bytes(0x9000), flag=1)
        self.files = [('GlobalMetaFile', 0x10, datafile(self.codec, 'GlobalMetaFile', 0x10, None, raw=bytes(range(0xcf)))),
                      ('Default Material Template', 0x2f, datafile(self.codec, 'Default Material Template', 0x2f, [(0x2f, self.material, 0xffff), (0x77, self.texture, 0xffff)])),
                      ('Cell00461_DataBlock', 0x571b6b29, datafile(self.codec, 'Cell00461_DataBlock', 0x571b6b29, [(0x99, self.texture, 0)], extra=b'cell trailer', deps=(0x7a, 0x7b))),
                      ('old', 0x5, datafile(self.codec, 'old', 0x5, [(0x5, self.material, 0xffff)]))]

    def tearDown(self): self.tmp.cleanup()

    def write(self, data, name='DataNX_Test.forge'):
        p = self.dir / name; p.write_bytes(data); return str(p)

    def test_entries_leave_cleared_slots_out(self):
        path = self.write(archive(self.files, cleared={3}))
        es = forge.entries(path)
        self.assertEqual([(n, fid) for n, fid, _, _ in es], [('GlobalMetaFile', 0x10), ('Default Material Template', 0x2f), ('Cell00461_DataBlock', 0x571b6b29)])
        self.assertTrue(forge.is_forge(Path(path).read_bytes()[:13]))
        self.assertFalse(forge.is_forge(archive(self.files, version=30)[:13]))

    def test_datafile_objects_and_shader_records(self):
        path = self.write(archive(self.files))
        es = forge.entries(path)
        with open(path, 'rb') as f:
            self.assertIsNone(forge.datafile(*forge.read(f, es[0]), self.codec))   # stored raw: no sections
            table, data = forge.datafile(*forge.read(f, es[1]), self.codec)
            obs = forge.objects(table, data)
            self.assertEqual([(oid, typ, name) for oid, typ, name, _ in obs], [(0x2f, MATERIAL, 'Default Material Template'), (0x77, TEXTURE, 'WhiteTexture')])
            self.assertEqual(obs[1][3], self.texture)   # a 0x9000-byte object: two chunks, the second one through the decoder
            self.assertTrue(self.codec.calls and all(c[:2] == b'\x8c\x0c' for c, _ in self.codec.calls))
            shaders = forge.nvn_shaders(obs[0][3])
            self.assertEqual([(len(ctl), len(code)) for _, ctl, code in shaders], [(0x880, 0x100), (0x880, 0x200)])
            self.assertEqual([split.glslc_stage(ctl, code) for _, ctl, code in shaders], ['vs', 'ps'])
            self.assertEqual(forge.nvn_shaders(obs[1][3]), [])
            deps, d = forge.read(f, es[2])   # two dependency pairs before the sections, and an object table with the DataBlock trailer
            self.assertEqual((deps, struct.unpack_from('<I', d)[0]), (2, 0x7a))
            (oid, _, name, _), = forge.objects(*forge.datafile(deps, d, self.codec))
            self.assertEqual((oid, name), (0x99, 'WhiteTexture'))

    def test_damaged_archives(self):
        good = archive(self.files)
        def broken(*patches):   # (offset, format, value), …
            b = bytearray(good)
            for at, fmt, v in zip(*[iter(patches)] * 3): struct.pack_into(fmt, b, at, v)
            return self.write(bytes(b), 'bad.forge')
        for why, path in (('unknown version', broken(9, '<I', 30)),
                          ('header past the end', broken(13, '<Q', len(good))),
                          ('too many slots', broken(0x416 + 0x18, '<I', forge.MAX_SLOTS + 1)),
                          ('more files than slots', broken(0x43e, '<I', 9)),
                          ('index past the end', broken(0x43e + 8, '<Q', len(good) - 8)),
                          ('datafile past the end', broken(0x46e + forge.INDEX + 12, '<I', len(good))),
                          ('tables that loop', broken(0x416 + 0x1c, '<I', 2, 0x43e + 0x10, '<q', 0x43e)),
                          ('cut short', self.write(good[:0x500], 'bad.forge'))):
            with self.subTest(why), self.assertRaises(forge.Error): forge.entries(path)
        path = self.write(good)
        es = forge.entries(path)
        with open(path, 'rb') as f:
            with self.assertRaises(forge.Error): forge.read(f, (es[1][0], es[1][1] + 1, es[1][2], es[1][3]))   # the header names another file
        b = bytearray(datafile(self.codec, 'x', 1, [(1, self.texture, 0xffff)])); struct.pack_into('<I', b, 0x1b8, len(b))
        with open(self.write(archive([('x', 1, bytes(b))]), 'deps.forge'), 'rb') as f:
            with self.assertRaises(forge.Error): forge.read(f, forge.entries(f.name)[0])   # more dependency pairs than bytes

    def test_damaged_sections_and_tables(self):
        sec = self.codec.section(self.texture, coded={1})
        self.assertEqual(forge.block_data(sec, 0, self.codec), (self.texture, len(sec)))
        def bad(at, fmt, *v):
            b = bytearray(sec); struct.pack_into(fmt, b, at, *v); return bytes(b)
        n = 17 + 4 * 2   # the chunk table ends here
        for why, d, dec in (('version 2', bad(8, '<H', 2), self.codec),
                            ('no chunks', bad(15, '<H', 0), self.codec),
                            ('chunk table past the end', bad(15, '<H', 0x4000), self.codec),
                            ('chunk larger than the largest', bad(17, '<H', 0x9000), self.codec),
                            ('stored bytes past the end', bad(17 + 4, '<HH', 0x7000, 0x7000), self.codec),
                            ('stored larger than its size', bad(17 + 4 + 2, '<H', 0x1a), self.codec),
                            ('not an Oodle stream', bad(n + 4 + 0x8000 + 4, '<B', 0x78), self.codec),
                            ('decoder output short', sec, lambda c, k: b'x'),
                            ('cut short', sec[:-3], self.codec),
                            ('checksum', bad(n, '<I', zlib.adler32(sec[n + 4:n + 4 + 0x8000], 0) ^ 1), self.codec),
                            ('no magic', b'\0' + sec, self.codec)):
            with self.subTest(why), self.assertRaises(forge.Error): forge.block_data(d, 0, dec)
        t = table([(1, b'abcd', 0xffff)])
        self.assertEqual(len(forge.objects(t, b'abcd')), 1)
        for why, tb, data in (('rows past the table', t[:-6], b'abcd'), ('sizes add up to more', t, b'abc'), ('a trailer longer than the table', t[:-4] + struct.pack('<I', 9), b'abcd')):
            with self.subTest(why), self.assertRaises(forge.Error): forge.objects(tb, data)
        with self.assertRaises(forge.Error): forge.datafile(0, self.codec.section(t) + self.codec.section(b'abcd') + b'\0' * 7, self.codec)   # not one u32 after the objects

    def test_nvn_shaders_need_their_record(self):
        rec = self.vs
        self.assertEqual(len(forge.nvn_shaders(rec)), 1)
        self.assertEqual(forge.nvn_shaders(bytes(0x30) + rec[0x30:]), [])   # a control magic without its record header
        b = bytearray(rec); struct.pack_into('<I', b, 8, 0x104)
        self.assertEqual(forge.nvn_shaders(bytes(b)), [])   # the record's code length is not the control's
        self.assertEqual(forge.nvn_shaders(rec[:0x30 + 0x880 + 0x80]), [])   # the code area runs past the object
        b = bytearray(rec); b[0x30 + 0x880:0x30 + 0x884] = b'\0' * 4
        self.assertEqual(forge.nvn_shaders(bytes(b)), [])   # no code header right after the control section, and no thread group: not a compute shader
        struct.pack_into('<3I', b, 0x30 + 0x748, 8, 8, 1)   # a compute shader whose code area has no header (main's eight)
        (_, ctl, code), = forge.nvn_shaders(bytes(b))
        self.assertEqual(split.glslc_stage(ctl, code), 'cs')
        self.assertIsNone(split.check('cs', 'cs', ctl, code))

    def test_main_records(self):   # main keeps built-in shaders as records: read when the game has forge archives
        code, ctl = program('ps')
        img = b'\0' * 5 + record('vs') + b'text' + struct.pack('<3I', len(ctl), len(ctl), len(code)) + bytes(0x24) + ctl + code
        found = split.forge_main(img, 'main')
        self.assertEqual([(w.split('#')[0], st) for w, st, _, _ in found], [('main', 'vs'), ('main', 'ps')])
        self.assertEqual(split.group(found[0][0]), 'main')

    def test_split_reads_forge_archives(self):
        romfs = self.dir / 'RomFS'; (romfs / 'AC2').mkdir(parents=True)
        (romfs / 'AC2' / 'DataNX.forge').write_bytes(archive(self.files))
        (romfs / 'AC2' / 'DataNX_Next.forge').write_bytes(archive(self.files, version=30))
        (romfs / 'AC2' / 'notes.forge').write_bytes(b'not an archive')
        files = sorted((str(p), str(p.relative_to(romfs))) for p in romfs.rglob('*') if p.is_file())
        old = split.oodle; split.oodle = self.codec
        try:
            jobs, taken = split.forge_jobs(files, parts=2)
            self.assertEqual(taken, {str(romfs / 'AC2' / 'DataNX.forge'), str(romfs / 'AC2' / 'DataNX_Next.forge')})
            results = [split.scan_file(j) for j in jobs]
        finally: split.oodle = old
        self.assertEqual([r[3] for r in results if isinstance(r[3], tuple)][0][0], 'unreadable')   # version 30: reported, not scanned as a loose file
        keys = {k: v for r in results for k, v in r[1].items()}
        self.assertEqual(sorted(v[1] for v in keys.values()), ['ps', 'vs'])
        self.assertTrue(all(v[0].startswith('/AC2/DataNX.forge/') and '#FORGE@' in v[0] for v in keys.values()))
        pairs, cover = split.separable_pairs(keys)   # one stage each: the vertex shader is paired with the pixel shaders' cover
        vs = next(k for k, v in keys.items() if v[1] == 'vs'); ps = next(k for k, v in keys.items() if v[1] == 'ps')
        self.assertEqual((pairs, cover), ({(vs, ps)}, [ps]))

    def test_profile_guess_decodes_forge_archives(self):
        sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'games')); import profile_guess
        src = profile_guess.shader_sources({'nvnBootstrapLoader'}, 0, [], 0, 0, forge=27)
        self.assertTrue(src['oodle_packs'][0])
        self.assertIn('27 Ubisoft forge archive(s)', src['oodle_packs'][1])
        self.assertFalse(profile_guess.shader_sources({'nvnBootstrapLoader'}, 0, [], 0, 0)['oodle_packs'][0])


if __name__ == '__main__':
    unittest.main()
