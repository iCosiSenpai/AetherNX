#!/usr/bin/env python3
"""Fuzz dm/gfx/tools/forge.py's readers of Ubisoft forge archives: entries (the file, archive and table headers, the index and meta tables), read of every datafile it lists (the
FILEDATA header, the dependency count), datafile (the two compressed sections: chunk tables, stored and decoder chunks), objects (the object table and its trailer) and nvn_shaders
over every object. The game's Oodle is a stand-in that returns the requested number of bytes, so the decoder's own checks are out of scope.
Seeds: an archive of a raw GlobalMetaFile, a material template with one shader record whose objects are split over a stored and a decoder chunk, and a world cell's DataBlock file
(dependency pairs, an object table with its trailer); the same archive with a cleared slot. The chunk checksums are right, so a mutation reaches the layers past them only where
it leaves the chunk's bytes alone.
Clean rejection: forge.Error (a ValueError), which every reader raises for what does not fit. Any other exception (struct.error from a read past the end of a table, for one), a hang
or an oversized allocation is a finding. Usage: see fuzzlib.py"""
import struct
import sys
import zlib

import fuzzlib
import forge

HARNESS = 'forge'
fuzzlib.guard(forge)


def record():
    """A shader record: {control length, code offset, code length} and 0x24 bytes, a 0x880-byte control section (+0x20 its length, +0x704 the code's), a code area of one stage"""
    code = bytearray(forge.GFX_MAGIC + bytes(0x2c) + struct.pack('<I', 5 << 10) + bytes(0x4c) + bytes(0x40))
    ctl = bytearray(0x880); ctl[:4] = forge.CTL_MAGIC; struct.pack_into('<I', ctl, 0x20, len(ctl)); struct.pack_into('<I', ctl, 0x704, len(code))
    return struct.pack('<3I', len(ctl), len(ctl), len(code)) + bytes(0x24) + bytes(ctl) + bytes(code)


def obj(typ, name, body): return struct.pack('<III', typ, len(body), len(name)) + name + b'\0' + body


def section(data, coded=()):   # 32 KB chunks; a coded one is stored as an Oodle block header and its size, which decode below answers
    chunks = [data[i:i + 0x8000] for i in range(0, len(data), 0x8000)]
    stored = [b'\x8c\x0c' + struct.pack('<I', len(c)) if k in coded else c for k, c in enumerate(chunks)]
    head = forge.BLOCK_MAGIC + struct.pack('<HBHHH', 1, 6, 0x8000, 0x8000, len(chunks)) + b''.join(struct.pack('<HH', len(c), len(s)) for c, s in zip(chunks, stored))
    return head + b''.join(struct.pack('<I', zlib.adler32(s, 0)) + s for s in stored)


def datafile(name, fid, objs=(), raw=None, deps=0, extra=b''):
    if raw is None:
        table = struct.pack('<H', len(objs)) + b''.join(struct.pack('<IIH', i + 1, len(o), 0xffff) for i, o in enumerate(objs)) + struct.pack('<I', len(extra)) + extra
        raw = bytes(8 * deps) + section(table) + section(b''.join(objs), coded={1}) + bytes(4)
    head = bytearray(forge.HEAD); head[:8] = forge.FILEDATA; head[8:8 + len(name)] = name
    struct.pack_into('<II', head, 0x187, fid, len(raw)); struct.pack_into('<I', head, 0x1b8, deps)
    return bytes(head) + raw


def archive(files, cleared=()):
    slots = 4; toff = 0x416 + 0x28; ioff = toff + forge.TABLE; moff = ioff + forge.INDEX * slots; at = moff + forge.META * slots
    idx, meta, blob = bytearray(), bytearray(), bytearray()
    for k, (name, fid, df) in enumerate(files):
        idx += struct.pack('<QII', at + len(blob), 0 if k in cleared else fid, 0 if k in cleared else len(df) - forge.HEAD); blob += df
        m = bytearray(forge.META); struct.pack_into('<I', m, 0, len(df) - forge.HEAD); m[0x2c:0x2c + len(name)] = name; meta += m
    out = bytearray(forge.MAGIC + struct.pack('<IQ', 31, 0x416)).ljust(0x416, b'\0')
    out += struct.pack('<IIqqIIQ', len(files), 1, 0, -1, slots, 1, toff) + struct.pack('<IIQqIIQQ', len(files), 1, ioff, -1, 0, slots - 1, moff, at)
    return bytes(out + idx.ljust(forge.INDEX * slots, b'\0') + meta.ljust(forge.META * slots, b'\0') + blob)


def seeds():
    material = obj(0xbcfb3c7a, b'Default Material Template', b'\x01' + record() + bytes(0x8000))
    files = [(b'GlobalMetaFile', 0x10, datafile(b'GlobalMetaFile', 0x10, raw=bytes(0xcf))),
             (b'Default Material Template', 0x2f, datafile(b'Default Material Template', 0x2f, [material, obj(0x1234, b'Tex', bytes(64))])),
             (b'Cell00461_DataBlock', 0x571b, datafile(b'Cell00461_DataBlock', 0x571b, [obj(0x1234, b'Cell', bytes(32))], deps=2, extra=b'cell'))]
    return {'archive': archive(files), 'cleared': archive(files, cleared={1})}


def decode(comp, n): return bytes(n)   # the game's Oodle, as far as these readers can tell: n bytes, n at most a chunk's u16 size


_file = fuzzlib.InputFile('DataNX.forge')


def check(data):
    try:
        path = _file.write(data)
        es = forge.entries(path)
        with open(path, 'rb') as f:
            for e in es:
                try:
                    r = forge.datafile(*forge.read(f, e), decode)
                    for _, _, _, b in forge.objects(*r) if r else []: forge.nvn_shaders(b)
                except forge.Error: continue   # one datafile left out, as shader_split.py forge_shaders does
    except forge.Error: return


if __name__ == '__main__':
    sys.exit(fuzzlib.main(HARNESS, check, seeds))
