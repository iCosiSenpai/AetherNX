#!/usr/bin/env python3
"""Ubisoft's .forge archives (the Scimitar engine), as Assassin's Creed The Ezio Collection keeps its game data on the Switch: Assassin's Creed II in the RomFS (forge version 31,
27 archives, 5.5 GB) and Brotherhood and Revelations in add-on content index 1 (version 25, 29 archives, 6.8 GB). Used by shader_split.py (forge_jobs, forge_shaders) and
dm/games/profile_guess.py (build_sources). The files are untrusted input: every count, offset and size is checked against what holds it before it is used (Error, a ValueError).

Layout, both versions (little-endian, packed):
· 'scimitar\\0', u32 version, u64 offset of the archive header (0x416 in every archive here).
· Archive header: u32 file count, u32, u64, i64, u32 slots per table (5000), u32 table count, u64 offset of the first table header.
· Table header (0x30 bytes): u32 file count, u32, u64 index offset, i64 next table header (-1 for the last), u32 first and last slot, u64 meta table offset, u64 offset of a third table.
  An index entry is 16 bytes {u64 offset, u32 file ID, u32 data size}; a meta entry 0xbc bytes {u32 data size, u64 ID, …, i32 next and previous entry at +0x1c / +0x20, u32 time stamp
  at +0x28, the name at +0x2c (128 bytes, NUL-padded)}. A cleared slot has file ID 0 and size 0 in the index; its old data may still be in the file (DataNX_Common.forge has one), and it
  is left out. 45 textures of DataNX_Common.forge have a meta size a few bytes larger than the index's; the index's is the one the datafile header repeats.
· A datafile at its offset: a 0x1bc-byte header ('FILEDATA', the name, at +0x187 the file ID and the data size again, at +0x1b8 u32 the count of dependency pairs), then the data:
  that many 8-byte {u32 ID, u32 kind} pairs (the world cells' DataBlock files), two compressed sections (block_data) and a u32. GlobalMetaFile, first in every archive, is stored raw.
· A compressed section: magic 33 AA FB 57 99 FA 04 10, u16 version (1), u8 compression type, u16 largest chunk size (0x8000), u16 (0x8000), u16 chunk count, per chunk {u16 size, u16
  stored size}, then per chunk {u32 checksum, the stored bytes}. The checksum is Adler-32 of the stored bytes started at 0 instead of 1 (every chunk of the archives checked, both
  versions). A chunk stored at its size is kept as it is; the others are Oodle streams, which only the game's own decoder reads (shader_split.py oodle): compression type 6 is Oodle
  Leviathan (block header 8C 0C) in every AC2 archive, type 4 Oodle Mermaid (8C 0A) in every ACB one; none is zlib. The decoded length must be the chunk's size.
· The first section is the object table: u16 count, count × {u32 object ID, u32 size, u16 (0xffff, or a small index in the world cells' DataBlock files)}, then u32 n and n more bytes
  (0 in every datafile but the DataBlock ones). The second is the objects back to back in table order, each {u32 type, u32 body size, u32 name length, the name, a byte, …}: after a 1
  byte a property list comes before the body, so only the name is read here (objects).
· NVN shaders (nvn_shaders): the material templates (object type 0xbcfb3c7a) hold shader records, each 0x30 bytes {u32 control length, u32 code offset (the control length), u32 code
  length, …} followed by the control section and, right after it, the code area, unaligned: 224,124 records in AC2 1.3's archives (20,417 distinct shaders, vertex and pixel), 285,364 in
  Brotherhood's and Revelations' (24,123). main keeps the engine's built-in shaders the same way: 232 records, eight of them compute shaders whose code area has no header (SDK 11.4.3's
  GLSLC), known by the thread group their control section gives (+0x748).
Usage: forge.py <file.forge> lists the datafiles (offset, file ID, size, name)."""
import struct, sys, zlib, os as _os
sys.path.insert(0, _os.path.join(_os.path.dirname(_os.path.abspath(__file__)), '../../tools'))
from romfs import os, open

MAGIC = b'scimitar\0'
VERSIONS = (25, 31)   # Brotherhood / Revelations, Assassin's Creed II (The Ezio Collection 1.3); another version is reported, not guessed at
BLOCK_MAGIC = bytes.fromhex('33AAFB5799FA0410')
FILEDATA, HEAD = b'FILEDATA', 0x1bc
INDEX, META, TABLE = 16, 0xbc, 0x30
MAX_SLOTS = 1 << 20   # slots per table (5000 in every archive here)
CTL_MAGIC, GFX_MAGIC, CS_MAGIC = bytes.fromhex('34127698'), bytes.fromhex('78563412'), bytes.fromhex('79563412')


class Error(ValueError): pass


def is_forge(head): return head[:9] == MAGIC and len(head) >= 13 and struct.unpack_from('<I', head, 9)[0] in VERSIONS


def entries(path):
    """→ [(name, file ID, offset, data size)] of an archive's datafiles in index order, cleared slots left out. Error when a header, table or range does not fit in the file"""
    size = os.stat(path).st_size
    with open(path, 'rb') as f:
        def at(off, n, what):
            if not 0 <= off <= size - n: raise Error(f'{path}: {what} ({n:#x} bytes at {off:#x}) lies outside the {size:#x}-byte file')
            f.seek(off); b = f.read(n)
            if len(b) != n: raise Error(f'{path}: {what} is cut short')
            return b
        h = at(0, 0x15, 'the file header')
        if h[:9] != MAGIC: raise Error(f'{path}: not a forge archive')
        ver, hoff = struct.unpack_from('<IQ', h, 9)
        if ver not in VERSIONS: raise Error(f'{path}: forge version {ver}, not one this reader knows ({", ".join(map(str, VERSIONS))})')
        count, _, _, _, slots, ntab, toff = struct.unpack('<IIqqIIQ', at(hoff, 0x28, 'the archive header'))
        if not 0 < slots <= MAX_SLOTS or ntab > size // TABLE: raise Error(f'{path}: {ntab} tables of {slots} slots')
        out, seen = [], set()
        for _ in range(ntab):
            if toff in seen: raise Error(f'{path}: the table headers loop at {toff:#x}')
            seen.add(toff)
            n, _, ioff, nxt, _, _, moff, _ = struct.unpack('<IIQqIIQQ', at(toff, TABLE, f'the table header at {toff:#x}'))
            if n > slots: raise Error(f'{path}: a table of {n} files has {slots} slots')
            idx, meta = at(ioff, INDEX * n, 'an index table'), at(moff, META * n, 'a meta table')
            for k in range(n):
                off, fid, dsize = struct.unpack_from('<QII', idx, INDEX * k)
                if not fid and not dsize: continue   # a cleared slot
                if not 0 <= off <= size - HEAD - dsize: raise Error(f'{path}: datafile {k} ({dsize:#x} bytes at {off:#x}) lies outside the {size:#x}-byte file')
                name = meta[META * k + 0x2c:META * k + 0xac].split(b'\0')[0].decode('utf-8', 'replace')
                out.append((name, fid, off, dsize))
            if nxt < 0: break
            toff = nxt
        if len(out) > count: raise Error(f'{path}: {len(out)} datafiles where the header counts {count}')
        return out


def read(f, entry):
    """A datafile's data (entry from entries; f the archive, open) → (dependency count, data). Error when its header does not repeat the index's file ID and size"""
    name, fid, off, dsize = entry
    f.seek(off); b = f.read(HEAD + dsize)
    if len(b) != HEAD + dsize: raise Error(f'{name}: the datafile is cut short')
    if b[:8] != FILEDATA: raise Error(f'{name}: no FILEDATA header at {off:#x}')
    if struct.unpack_from('<II', b, 0x187) != (fid, dsize): raise Error(f'{name}: the datafile header names file {struct.unpack_from("<I", b, 0x187)[0]:#x} of {struct.unpack_from("<I", b, 0x18b)[0]:#x} bytes, the index {fid:#x} of {dsize:#x}')
    deps = struct.unpack_from('<I', b, 0x1b8)[0]
    if deps > dsize // 8: raise Error(f'{name}: {deps} dependency pairs in {dsize:#x} bytes')
    return deps, b[HEAD:]


def block_data(d, at, decode, where='forge'):
    """The compressed section at d[at:] → (its bytes, the offset after it). decode(stored bytes, size) is the game's Oodle (shader_split.py oodle); a stored chunk is not passed to it"""
    if d[at:at + 8] != BLOCK_MAGIC or at + 17 > len(d): raise Error(f'{where}: no compressed section at {at:#x}')
    ver, kind, big, _, n = struct.unpack_from('<HBHHH', d, at + 8)
    if ver != 1 or not n or not big: raise Error(f'{where}: a compressed section of version {ver}, {n} chunks of at most {big:#x} bytes is not a layout this reader knows')
    p = at + 17 + 4 * n
    if p > len(d): raise Error(f'{where}: the chunk table of {n} chunks runs past the data')
    sizes, out = struct.unpack_from(f'<{2 * n}H', d, at + 17), []
    for k in range(n):
        size, stored = sizes[2 * k], sizes[2 * k + 1]
        if not size or size > big or not stored or stored > size or p + 4 + stored > len(d): raise Error(f'{where}: chunk {k} ({stored:#x} stored bytes for {size:#x}) does not fit')
        c = d[p + 4:p + 4 + stored]
        if zlib.adler32(c, 0) != struct.unpack_from('<I', d, p)[0]: raise Error(f'{where}: chunk {k} does not match its checksum')
        p += 4 + stored
        if stored == size: out.append(c); continue
        if c[0] & 0x0f != 0x0c or stored < 2: raise Error(f'{where}: chunk {k} of compression type {kind} is not an Oodle stream (block header {c[:2].hex()})')
        x = decode(c, size)
        if len(x) != size: raise Error(f'{where}: chunk {k} decoded to {len(x):#x} bytes, not {size:#x}')
        out.append(x)
    return b''.join(out), p


def datafile(deps, d, decode, where='forge'):
    """A datafile's data (read) → (object table, objects), both decoded. None when it holds no compressed sections (GlobalMetaFile)"""
    p = 8 * deps
    if d[p:p + 8] != BLOCK_MAGIC: return None
    table, p = block_data(d, p, decode, where)
    data, p = block_data(d, p, decode, where)
    if len(d) - p != 4: raise Error(f'{where}: {len(d) - p} bytes after the objects, not a u32')
    return table, data


def objects(table, data, where='forge'):
    """The object table and the objects (datafile) → [(object ID, type, name, the object's bytes)]"""
    if len(table) < 6: raise Error(f'{where}: an object table of {len(table)} bytes')
    n = struct.unpack_from('<H', table)[0]
    extra = struct.unpack_from('<I', table, 2 + 10 * n)[0] if len(table) >= 2 + 10 * n + 4 else None
    if extra is None or len(table) != 2 + 10 * n + 4 + extra: raise Error(f'{where}: an object table of {len(table)} bytes for {n} objects')
    rows = [struct.unpack_from('<II', table, 2 + 10 * i) for i in range(n)]
    if sum(s for _, s in rows) != len(data): raise Error(f'{where}: {n} objects of {sum(s for _, s in rows):#x} bytes in {len(data):#x}')
    out, o = [], 0
    for oid, s in rows:
        b = data[o:o + s]; o += s
        typ, nl = (struct.unpack_from('<I', b)[0], struct.unpack_from('<I', b, 8)[0]) if s >= 12 else (0, 0)
        name = b[12:12 + nl].decode('utf-8', 'replace') if 12 + nl <= s else ''
        out.append((oid, typ, name, b))
    return out


def nvn_shaders(b):
    """The NVN shader records in an object's bytes (or main's) → [(control offset, control section, code area)]: a control section (magic 0x98761234, its own length at +0x20) whose
    record header, the 0x30 bytes before it, gives that length twice and the code area's length (control +0x704), and the code area right after it: with a code header magic, or without
    one for a compute shader (its control's thread group, +0x748, all non-zero)"""
    out, i = [], b.find(CTL_MAGIC, TABLE)
    while i >= 0:
        if i + 0x708 <= len(b):
            nctl, coff, ncode = struct.unpack_from('<3I', b, i - TABLE)
            if 0x760 <= nctl == coff and nctl == struct.unpack_from('<I', b, i + 0x20)[0] and ncode == struct.unpack_from('<I', b, i + 0x704)[0] and i + nctl + ncode <= len(b) \
               and (b[i + nctl:i + nctl + 4] in (GFX_MAGIC, CS_MAGIC) or i + 0x754 <= len(b) and all(struct.unpack_from('<3I', b, i + 0x748))):
                out.append((i, b[i:i + nctl], b[i + nctl:i + nctl + ncode]))
        i = b.find(CTL_MAGIC, i + 4)
    return out


if __name__ == '__main__':
    if len(sys.argv) != 2: sys.exit('usage: forge.py <file.forge>   lists the datafiles (offset, file ID, size, name)')
    try:
        for name, fid, off, dsize in entries(sys.argv[1]): print(f'{off:#012x}\t{fid:#010x}\t{dsize}\t{name}')
    except Error as e: sys.exit(f'[RED] {e}')
