#!/usr/bin/env python3
"""
AetherNX — Universal Switch Library Scanner, Decomp & Static Recomp Workspace Generator
Copyright (c) 2026 Alessio Cosi (iCosiSenpai). Licensed under GPL-3.0 / MIT.

Commands:
  python3 scripts/aethernx_decomp.py scan [--json] [dir1 dir2 ...]
  python3 scripts/aethernx_decomp.py decomp-init <game_dir> [--json]
  python3 scripts/aethernx_decomp.py recomp-lift <game_dir> [--module main] [--limit 0]
  python3 scripts/aethernx_decomp.py doctor [--json]
"""
import argparse
import ast
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "scripts"))
sys.path.insert(0, str(REPO_ROOT / "dm/tools"))
sys.path.insert(0, str(REPO_ROOT / "dm/games"))

import build_ipa_from_nsp as builder
import game as gamemod
import nso
import nso_syms

DEFAULT_LIBRARY_ROOTS = [
    Path("~/Games"),
    Path("~/Games"),
]


def extract_eh_functions(img: bytes) -> dict[int, int]:
    """Extract {func_start_offset: func_size} from an NSO image's MOD0 .eh_frame_hdr table."""
    if len(img) < 0x20:
        return {}
    m0 = struct.unpack_from("<I", img, 4)[0]
    if m0 + 24 > len(img) or img[m0 : m0 + 4] != b"MOD0":
        return {}
    eh_off = struct.unpack_from("<i", img, m0 + 16)[0]
    if eh_off == 0:
        return {}
    ehs = m0 + eh_off
    if ehs + 12 > len(img):
        return {}
    _, penc, cenc, tenc = img[ehs : ehs + 4]
    if (penc, cenc, tenc) != (0x1B, 0x03, 0x3B):
        return {}
    n = struct.unpack_from("<I", img, ehs + 8)[0]
    fn: dict[int, int] = {}
    for i in range(n):
        entry = ehs + 12 + i * 8
        if entry + 8 > len(img):
            break
        loc, fde = struct.unpack_from("<ii", img, entry)
        loc += ehs
        fde += ehs
        if fde + 16 > len(img) or loc < 0:
            continue
        pc0 = fde + 8 + struct.unpack_from("<i", img, fde + 8)[0]
        size = struct.unpack_from("<I", img, fde + 12)[0]
        if pc0 != loc:
            continue
        fn[loc] = max(fn.get(loc, 0), size)
    return fn


def demangle_batch(symbols: list[str]) -> dict[str, str]:
    """Demangle Itanium C++ symbols using llvm-cxxfilt or c++filt."""
    if not symbols:
        return {}
    cpp_syms = [s for s in symbols if s.startswith("_Z")]
    if not cpp_syms:
        return {s: s for s in symbols}
    try:
        proc = subprocess.run(
            ["c++filt", "-n"],
            input="\n".join(cpp_syms),
            capture_output=True,
            text=True,
            timeout=15,
        )
        demangled_lines = proc.stdout.splitlines()
        mapping = dict(zip(cpp_syms, demangled_lines))
    except Exception:
        mapping = {}
    return {s: mapping.get(s, s) for s in symbols}


ARCHIVE_EXTS = (
    ".zip",
    ".rar",
    ".7z",
    ".tar",
    ".tar.gz",
    ".tgz",
    ".tar.xz",
    ".txz",
    ".tar.zst",
    ".001",
)


def _is_secondary_multipart(name: str) -> bool:
    low = name.lower()
    m_part = re.search(r"\.part(\d+)\.rar$", low)
    if m_part and int(m_part.group(1)) > 1:
        return True
    if re.search(r"\.r\d{2}$", low):
        return True
    m_split = re.search(r"\.(\d{3})$", low)
    if m_split and int(m_split.group(1)) > 1:
        return True
    return False


def _iter_archive_files(folder: Path) -> list[Path]:
    """Find archive files (.zip, .rar, .7z, .tar.*) inside a game folder, skipping build dirs and secondary split parts."""
    out: list[Path] = []

    def walk(d: Path, depth: int = 0) -> None:
        try:
            entries = sorted(d.iterdir(), key=lambda p: p.name)
        except OSError:
            return
        for p in entries:
            if p.name.startswith("."):
                continue
            if p.is_dir() and not p.is_symlink():
                if (
                    depth < 3
                    and p.name not in builder._SKIP_SCAN_DIRS
                    and not p.name.endswith(
                        ("_build", "_survey", ".app", ".xcworkspace", ".xcodeproj", ".partial")
                    )
                ):
                    walk(p, depth + 1)
            elif p.is_file():
                low = p.name.lower()
                if any(low.endswith(ext) for ext in ARCHIVE_EXTS) and not _is_secondary_multipart(low):
                    out.append(p)

    walk(folder)
    return out


def extract_single_archive(arc: Path, dest_dir: Path) -> None:
    """Extract a .zip, .rar, .7z, or .tar.* archive into dest_dir using unar, 7zz, ditto, unzip, or tar."""
    dest_dir.mkdir(parents=True, exist_ok=True)
    low = arc.name.lower()
    unar_bin = shutil.which("unar")
    sevenz_bin = shutil.which("7zz") or shutil.which("7z")

    if low.endswith((".rar", ".7z", ".001")):
        if unar_bin:
            subprocess.run([unar_bin, "-o", str(dest_dir), "-f", str(arc)], check=True)
            return
        if sevenz_bin:
            subprocess.run([sevenz_bin, "x", "-y", f"-o{dest_dir}", str(arc)], check=True)
            return
        raise RuntimeError(f"Cannot extract {arc.name}: install 'unar' or 'sevenzip' (brew install unar sevenzip)")

    if low.endswith(".zip"):
        if sevenz_bin:
            subprocess.run([sevenz_bin, "x", "-y", f"-o{dest_dir}", str(arc)], check=True)
            return
        if shutil.which("ditto"):
            subprocess.run(["ditto", "-x", "-k", str(arc), str(dest_dir)], check=True)
            return
        subprocess.run(["unzip", "-o", str(arc), "-d", str(dest_dir)], check=True)
        return

    if any(low.endswith(ext) for ext in (".tar", ".tar.gz", ".tgz", ".tar.xz", ".txz", ".tar.zst")):
        subprocess.run(["tar", "-xf", str(arc), "-C", str(dest_dir)], check=True)
        return

    if unar_bin:
        subprocess.run([unar_bin, "-o", str(dest_dir), "-f", str(arc)], check=True)
    elif sevenz_bin:
        subprocess.run([sevenz_bin, "x", "-y", f"-o{dest_dir}", str(arc)], check=True)
    else:
        raise RuntimeError(f"Unsupported archive format: {arc.name}")


def unpack_target(
    target: Path,
    out_dir: Path | None = None,
    decompress_nsz: bool = False,
    delete_archives: bool = False,
    keys_override: str | None = None,
) -> dict:
    """Unpack archives (.zip, .rar, .7z, .tar.*) and optionally decompress .nsz/.xcz packages."""
    if not target.exists():
        raise RuntimeError(f"Target path does not exist: {target}")

    extracted_archives: list[str] = []
    decompressed_nsz: list[str] = []

    if target.is_file():
        low = target.name.lower()
        clean_stem = re.sub(r"\.(tar\.(gz|xz|zst)|zip|rar|7z|tgz|txz|001|nsz|xcz|nsp|xci)$", "", target.name, flags=re.I)
        clean_stem = re.sub(r"\s*\[.*$", "", clean_stem).strip() or target.stem
        dest = out_dir or (DEFAULT_LIBRARY_ROOTS[0] / clean_stem if target.parent == Path.home() / "Downloads" else target.parent / clean_stem)
        dest.mkdir(parents=True, exist_ok=True)

        if any(low.endswith(ext) for ext in ARCHIVE_EXTS):
            extract_single_archive(target, dest)
            extracted_archives.append(str(target))
            if delete_archives:
                target.unlink(missing_ok=True)
        elif low.endswith((".nsz", ".xcz")):
            decompress_nsz = True
            dst_pkg = dest / target.name
            if dst_pkg.resolve() != target.resolve() and not dst_pkg.exists():
                shutil.copy2(target, dst_pkg)
        elif low.endswith((".nsp", ".xci")):
            dst_pkg = dest / target.name
            if dst_pkg.resolve() != target.resolve() and not dst_pkg.exists():
                shutil.copy2(target, dst_pkg)
    else:
        dest = out_dir or target
        dest.mkdir(parents=True, exist_ok=True)
        for arc in _iter_archive_files(target):
            extract_single_archive(arc, dest)
            extracted_archives.append(str(arc))
            if delete_archives:
                arc.unlink(missing_ok=True)

    if decompress_nsz:
        keys_file = Path(keys_override or builder.PROD_KEYS or "").expanduser().resolve()
        if not keys_file.is_file():
            raise RuntimeError(f"Cannot decompress .nsz/.xcz without a valid prod.keys file (checked: {keys_file})")
        pkgs = builder._iter_package_files(dest)
        nsz_files = [p for p in pkgs if p.suffix.lower() in (".nsz", ".xcz")]
        for nsz_path in nsz_files:
            out_ext = ".nsp" if nsz_path.suffix.lower() == ".nsz" else ".xci"
            expected_out = nsz_path.with_suffix(out_ext)
            if expected_out.is_file():
                continue
            with subprocess.Popen(
                [
                    sys.executable,
                    "-c",
                    "import sys; sys.argv[0] = 'nsz'; from nsz import main; main()",
                    "-D",
                    "-o",
                    str(nsz_path.parent),
                    str(nsz_path),
                ],
                cwd=str(keys_file.parent),
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
            ) as proc:
                keys_txt = keys_file.parent / "keys.txt"
                created_link = False
                if not keys_txt.exists():
                    try:
                        keys_txt.symlink_to(keys_file)
                        created_link = True
                    except OSError:
                        pass
                try:
                    out_text, _ = proc.communicate()
                finally:
                    if created_link:
                        keys_txt.unlink(missing_ok=True)
                if proc.returncode != 0:
                    raise RuntimeError(f"nsz decompression failed for {nsz_path.name}:\n{out_text}")
            if expected_out.is_file():
                decompressed_nsz.append(str(expected_out))
                if delete_archives:
                    nsz_path.unlink(missing_ok=True)

    final_pkgs = [str(p) for p in builder._iter_package_files(dest)]
    return {
        "target": str(target),
        "output_dir": str(dest),
        "extracted_archives": extracted_archives,
        "decompressed_nsz": decompressed_nsz,
        "packages_found": final_pkgs,
    }


def scan_game_folder(folder: Path) -> dict | None:
    """Inspect a single game directory and return full metadata about Base, Updates, DLCs, archives, and build artifacts."""
    archive_files = _iter_archive_files(folder)
    pkgs = builder._iter_package_files(folder)
    compressed_files = [p for p in pkgs if p.suffix.lower() in (".nsz", ".xcz")]
    try:
        if builder.dump_folder(folder):
            app, fam = builder.scan_dump(folder)
        else:
            if not pkgs:
                if not archive_files:
                    return None
                # Folder contains only unextracted archives (.zip / .rar / .7z)
                m_tid = re.search(r"([0-9A-Fa-f]{16})", " ".join(p.name for p in archive_files) + " " + folder.name)
                tid_hex = m_tid.group(1).upper() if m_tid else f"ARCHIVE_{abs(hash(folder.name)) & 0xFFFFFFFF:08X}"
                prof = gamemod.by_title(int(tid_hex, 16)) if len(tid_hex) == 16 and all(c in "0123456789ABCDEF" for c in tid_hex) else None
                return {
                    "title_id": tid_hex,
                    "name": (prof.get("name") if prof else None) or folder.name,
                    "directory": str(folder),
                    "folder": str(folder),
                    "work_dir": str(folder / f"{tid_hex}_build"),
                    "save_dir": str(Path.home() / "Library" / "Application Support" / "HorizonNative" / tid_hex),
                    "log_file": str(Path.home() / "Library" / "Logs" / "HorizonNative" / f"{tid_hex}.log"),
                    "has_base": False,
                    "is_archived_only": True,
                    "archive_files": [str(p) for p in archive_files],
                    "compressed_packages": [],
                    "has_verified_profile": prof is not None,
                    "profile_dir": str(prof.dir) if prof else None,
                    "fps_target": prof.get("fps_target", "30") if prof else "30",
                    "modules": prof.words("modules") if prof else ["main", "sdk"],
                    "shader_count": 0,
                    "build_exists": False,
                    "decomp_ready": False,
                    "recomp_ready": False,
                    "lifted_chunks": 0,
                    "mac_app": None,
                    "ipa_file": None,
                    "update_versions": [],
                    "dlc_ids": [],
                    "decomp_manifest": None,
                    "base": {"name": archive_files[0].name, "path": str(archive_files[0]), "size_bytes": archive_files[0].stat().st_size},
                    "updates": [],
                    "dlcs": [],
                    "build_status": {
                        "work_dir": str(folder / f"{tid_hex}_build"),
                        "extracted_versions": [],
                        "patched_versions": [],
                        "extracted_dlc_images": [],
                        "mac_apps": [],
                        "ios_ipas": [],
                        "decomp_ready": False,
                        "decomp_dir": None,
                        "recomp_ready": False,
                        "lifted_chunks": 0,
                    },
                }
            app, fam = builder.scan_nsps(folder)
    except Exception:
        return None

    tid_hex = f"{app:016X}"
    prof = gamemod.by_title(app)
    prof_name = prof.get("name") if prof else None
    base_path = fam["base"]
    game_name = prof_name or (
        re.sub(r"\s*\[.*$", "", base_path.stem).strip() if base_path else folder.name
    )

    work = folder / f"{tid_hex}_build"
    extract_dir = work / "extract"
    extracted_versions = (
        sorted(
            d.name
            for d in extract_dir.iterdir()
            if d.is_dir() and not d.name.endswith(".partial")
        )
        if extract_dir.is_dir()
        else []
    )
    patched_dirs = (
        sorted(
            d.name
            for d in work.glob("patched_*")
            if d.is_dir() and not d.name.endswith(".partial")
        )
        if work.is_dir()
        else []
    )
    aoc_files = (
        sorted(p.name for p in (work / "aoc").glob("*.img"))
        if (work / "aoc").is_dir()
        else []
    )
    mac_apps = sorted(
        str(p)
        for p in folder.glob("*.app")
        if p.is_dir() and not p.name.endswith(".partial")
    )
    ipas = sorted(
        str(p)
        for p in folder.glob("*.ipa")
        if p.is_file() and not p.name.endswith(".partial")
    )
    decomp_ws = work / "decomp_workspace"
    manifest_path = decomp_ws / "manifest.json"
    decomp_manifest = None
    if manifest_path.is_file():
        try:
            decomp_manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            mods = decomp_manifest.get("modules", [])
            for m in mods:
                m.setdefault("name", m.get("module", "unknown"))
                m.setdefault("code_size", m.get("text_size", 0))
                m.setdefault("functions", m.get("function_count", 0))
            decomp_manifest.setdefault(
                "total_functions", sum(m.get("functions", 0) for m in mods)
            )
            decomp_manifest.setdefault(
                "total_dynamic_symbols", sum(m.get("dynamic_symbols", 0) for m in mods)
            )
        except Exception:
            decomp_manifest = None

    lifted_dir = decomp_ws / "recomp" / "lifted_c"
    lifted_chunks = (
        len(list(lifted_dir.glob("main_*.c"))) if lifted_dir.is_dir() else 0
    )

    shader_count = 0
    if prof and prof.table("shader_map.tsv").is_file():
        shader_count = sum(
            1
            for ln in prof.table("shader_map.tsv")
            .read_text(errors="replace")
            .splitlines()
            if ln and not ln.startswith("#") and "\t" in ln
        )

    update_ints = [int(v) for v, _ in sorted(fam["updates"], key=lambda x: x[0] or 0) if v is not None]
    dlc_id_strs = [f"{t:016X}" for t, _, _ in sorted(fam["dlc"], key=lambda x: x[0])]
    modules_list = prof.words("modules") if prof else ["main", "sdk"]
    save_dir = Path.home() / "Library" / "Application Support" / "HorizonNative" / tid_hex
    log_file = Path.home() / "Library" / "Logs" / "HorizonNative" / f"{tid_hex}.log"

    return {
        "title_id": tid_hex,
        "name": game_name,
        "directory": str(folder),
        "folder": str(folder),
        "work_dir": str(work),
        "save_dir": str(save_dir),
        "log_file": str(log_file),
        "has_base": base_path is not None and base_path.exists(),
        "is_archived_only": False,
        "archive_files": [str(p) for p in archive_files],
        "compressed_packages": [str(p) for p in compressed_files],
        "has_verified_profile": prof is not None,
        "profile_dir": str(prof.dir) if prof else None,
        "fps_target": prof.get("fps_target", "30") if prof else "30",
        "modules": modules_list,
        "shader_count": shader_count,
        "build_exists": work.is_dir(),
        "decomp_ready": manifest_path.is_file(),
        "recomp_ready": lifted_chunks > 0,
        "lifted_chunks": lifted_chunks,
        "mac_app": mac_apps[0] if mac_apps else None,
        "ipa_file": ipas[0] if ipas else None,
        "update_versions": update_ints,
        "dlc_ids": dlc_id_strs,
        "decomp_manifest": decomp_manifest,
        "base": {
            "name": base_path.name if base_path else None,
            "path": str(base_path) if base_path else None,
            "size_bytes": base_path.stat().st_size if base_path and base_path.exists() else 0,
        },
        "updates": [
            {
                "version": f"v{v}" if v is not None else "unknown",
                "version_int": int(v) if v is not None else 0,
                "name": p.name,
                "path": str(p),
                "size_bytes": p.stat().st_size if p.exists() else 0,
            }
            for v, p in sorted(fam["updates"], key=lambda x: x[0] or 0)
        ],
        "dlcs": [
            {
                "title_id": f"{t:016X}",
                "index": t - app - 0x1000,
                "version": f"v{v}" if v is not None else "v0",
                "name": p.name,
                "path": str(p),
                "size_bytes": p.stat().st_size if p.exists() else 0,
            }
            for t, v, p in sorted(fam["dlc"], key=lambda x: x[0])
        ],
        "build_status": {
            "work_dir": str(work),
            "extracted_versions": extracted_versions,
            "patched_versions": patched_dirs,
            "extracted_dlc_images": aoc_files,
            "mac_apps": mac_apps,
            "ios_ipas": ipas,
            "decomp_ready": manifest_path.is_file(),
            "decomp_dir": str(decomp_ws) if manifest_path.is_file() else None,
            "recomp_ready": lifted_chunks > 0,
            "lifted_chunks": lifted_chunks,
        },
    }


def scan_libraries(roots: list[Path]) -> list[dict]:
    found: dict[str, dict] = {}
    for root in roots:
        if not root.is_dir():
            continue
        subdirs = [d for d in sorted(root.iterdir()) if d.is_dir() and not d.name.startswith(".")]
        for cand in subdirs + [root]:
            info = scan_game_folder(cand)
            if not info:
                continue
            tid = info["title_id"]
            if tid not in found or (
                not Path(found[tid]["build_status"]["work_dir"]).is_dir()
                and Path(info["build_status"]["work_dir"]).is_dir()
            ):
                found[tid] = info
    return list(found.values())


def init_decomp_workspace(game_dir: Path) -> dict:
    """Generate the complete Decomp & Static Recomp workspace for an extracted Switch game."""
    info = scan_game_folder(game_dir)
    if not info:
        raise RuntimeError(f"Could not identify a Switch game in {game_dir}")

    tid_hex = info["title_id"]
    work = Path(info["build_status"]["work_dir"])
    extract_root = work / "extract"
    if not extract_root.is_dir() or not info["build_status"]["extracted_versions"]:
        raise RuntimeError(
            f"No extracted ExeFS found in {extract_root}. Run native build/extraction first."
        )

    ver = info["build_status"]["extracted_versions"][-1]
    exefs = extract_root / ver / "ExeFS"
    if not exefs.is_dir():
        raise RuntimeError(f"ExeFS directory missing at {exefs}")

    ws = work / "decomp_workspace"
    for sub in ("functions", "symbols", "src", "include", "recomp"):
        (ws / sub).mkdir(parents=True, exist_ok=True)

    # Link Nintendo SDK (nnheaders) and EAD sead headers into include/
    for hdr_pkg in ("nnheaders", "sead"):
        src_hdr = REPO_ROOT / "decomp" / hdr_pkg
        dst_link = ws / "include" / hdr_pkg
        if src_hdr.exists() and not dst_link.exists():
            dst_link.symlink_to(src_hdr)

    modules_summary = []
    mod_names = [
        p.name
        for p in sorted(exefs.iterdir())
        if p.is_file() and p.name not in ("main.npdm",) and not p.name.startswith(".")
    ]

    for mname in mod_names:
        mpath = exefs / mname
        try:
            mod = nso.read(str(mpath))
        except Exception:
            continue
        img = bytes(mod.image)
        bid = mod.build_id[:16].hex()
        (t_off, t_sz), (r_off, r_sz), (d_off, d_sz) = mod.segments

        # 1. Dynamic symbols
        try:
            raw_syms = nso_syms.dynsyms(img)
            def_syms = nso_syms.defined(img)
        except Exception:
            raw_syms, def_syms = [], {}

        all_sym_names = [s for s, _, _ in raw_syms]
        demangled = demangle_batch(all_sym_names)

        sym_tsv = ws / "symbols" / f"{mname}_symbols.tsv"
        sym_lines = ["symbol\tdemangled\tdefined\toffset\tsize\tareas"]
        for s, is_def, _ in raw_syms:
            off, sz = def_syms.get(s, (0, 0))
            sym_lines.append(
                f"{s}\t{demangled.get(s, s)}\t{'1' if is_def else '0'}\t0x{off:08x}\t0x{sz:x}\t{nso_syms.area(s)}"
            )
        sym_tsv.write_text("\n".join(sym_lines) + "\n", encoding="utf-8")

        # 2. Function table from .eh_frame_hdr + defined symbols
        eh_fns = extract_eh_functions(img)
        addr_to_sym = {off: (s, sz) for s, (off, sz) in def_syms.items() if off < t_sz}
        for off, (_, sz) in addr_to_sym.items():
            if off not in eh_fns and sz > 0:
                eh_fns[off] = sz

        fn_tsv = ws / "functions" / f"{mname}_functions.tsv"
        fn_lines = ["address\tsize\tsymbol\tdemangled\tstatus"]
        for addr in sorted(eh_fns):
            sz = eh_fns[addr]
            sym_name = addr_to_sym.get(addr, (f"sub_{addr:08x}", sz))[0]
            dem_name = demangled.get(sym_name, sym_name)
            fn_lines.append(f"0x{addr:08x}\t0x{sz:x}\t{sym_name}\t{dem_name}\tunmatched")
        fn_tsv.write_text("\n".join(fn_lines) + "\n", encoding="utf-8")

        # 3. Quick AArch64 instruction census on .text
        words = struct.unpack_from(f"<{t_sz // 4}I", img, 0)
        svc_count = sum(1 for w in words if (w & 0xFFE0001F) == 0xD4000001)
        mrs_tpidr = sum(
            1 for w in words if (w & 0xFFFFFFE0) in (0xD53BD040, 0xD53BD060)
        )
        bl_count = sum(1 for w in words if (w & 0xFC000000) == 0x94000000)

        modules_summary.append(
            {
                "name": mname,
                "module": mname,
                "build_id": bid,
                "code_size": t_sz,
                "text_size": t_sz,
                "rodata_offset": r_off,
                "rodata_size": r_sz,
                "data_offset": d_off,
                "data_size": d_sz,
                "bss_size": mod.bss,
                "functions": len(eh_fns),
                "function_count": len(eh_fns),
                "dynamic_symbols": len(raw_syms),
                "defined_exports": len(def_syms),
                "imports": sum(1 for _, is_def, _ in raw_syms if not is_def),
                "svc_sites": svc_count,
                "tls_mrs_sites": mrs_tpidr,
                "bl_call_sites": bl_count,
            }
        )

        # 4. Generate starter C++ reconstruction unit for main
        if mname == "main":
            top_fns = sorted(eh_fns.items())[:40]
            cpp_lines = [
                f"// AetherNX Clean-Room Decompilation Unit — {info['name']} ({tid_hex})",
                f"// Module: main (Build ID: {bid}, Version: {ver})",
                f"// Total functions discovered in .eh_frame_hdr: {len(eh_fns):,}",
                "// Pre-wired with open-ead/nnheaders and open-ead/sead.",
                "",
                "#include <cstdint>",
                "#include <cstddef>",
                "",
                "namespace aethernx::decomp {",
                "",
            ]
            for addr, sz in top_fns:
                sym_name = addr_to_sym.get(addr, (f"sub_{addr:08x}", sz))[0]
                dem_name = demangled.get(sym_name, sym_name)
                cpp_lines += [
                    f"// Address: 0x{addr:08x} | Size: 0x{sz:x} bytes | Symbol: {sym_name}",
                    f"// Demangled: {dem_name}",
                    f"void sub_{addr:08x}() {{",
                    "    // TODO(aethernx-matcher): Reconstruct byte-matching AArch64 implementation",
                    "}",
                    "",
                ]
            cpp_lines.append("} // namespace aethernx::decomp\n")
            (ws / "src" / "main_reconstruct.cpp").write_text(
                "\n".join(cpp_lines), encoding="utf-8"
            )

    # 5. Generate CMakeLists.txt for Decomp verification
    cmake_text = f"""cmake_minimum_required(VERSION 3.22)
project(AetherNX_Decomp_{tid_hex} LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

include_directories(
    "${{CMAKE_CURRENT_SOURCE_DIR}}/include/nnheaders/include"
    "${{CMAKE_CURRENT_SOURCE_DIR}}/include/sead/include"
)

add_library(decomp_{tid_hex} STATIC
    src/main_reconstruct.cpp
)
"""
    (ws / "CMakeLists.txt").write_text(cmake_text, encoding="utf-8")

    # 6. Generate Static Recomp (nxrt) descriptor and lifter script
    main_mod = next((m for m in modules_summary if m["module"] == "main"), modules_summary[0])
    nxrt_desc = f"""/*
 * AetherNX Static Recompilation Descriptor (nxrt)
 * Game: {info['name']} ({tid_hex})
 * Packed Version: {ver} | Main Build ID: {main_mod['build_id']}
 */
#include <stdint.h>

typedef struct aethernx_recomp_game_info {{
    const char *title_id;
    const char *name;
    const char *version;
    const char *main_build_id;
    uint64_t text_size;
    uint64_t rodata_offset;
    uint64_t data_offset;
    uint64_t bss_size;
    uint32_t function_count;
}} aethernx_recomp_game_info_t;

const aethernx_recomp_game_info_t g_aethernx_game = {{
    .title_id      = "{tid_hex}",
    .name          = "{info['name']}",
    .version       = "{ver}",
    .main_build_id = "{main_mod['build_id']}",
    .text_size     = 0x{main_mod['text_size']:x}ULL,
    .rodata_offset = 0x{main_mod['rodata_offset']:x}ULL,
    .data_offset   = 0x{main_mod['data_offset']:x}ULL,
    .bss_size      = 0x{main_mod['bss_size']:x}ULL,
    .function_count = {main_mod['function_count']}U,
}};
"""
    (ws / "recomp" / "nxrt_game_desc.c").write_text(nxrt_desc, encoding="utf-8")

    lift_sh = f"""#!/usr/bin/env bash
set -euo pipefail
# AetherNX Static Lifter invocation for {info['name']} ({tid_hex})
AETHERNX_ROOT="{REPO_ROOT}"
EXEFS_DIR="{exefs}"
OUT_DIR="$(cd "$(dirname "$0")" && pwd)/lifted_c"
mkdir -p "$OUT_DIR"
echo "[AetherNX Recomp] Lifting ExeFS/main ({main_mod['function_count']} functions) via nxrt gen.py..."
PYTHONPATH="$AETHERNX_ROOT/recomp/nxrt/tools" \\
  "{sys.executable}" "$AETHERNX_ROOT/recomp/nxrt/tools/gen.py" \\
  main "$EXEFS_DIR/main" 0x7100000000 "$OUT_DIR" \\
  --hle "$AETHERNX_ROOT/recomp/nxrt/runtime/hle/hle_symbols.txt" "$@"
"""
    lift_script = ws / "recomp" / "lift_nso.sh"
    lift_script.write_text(lift_sh, encoding="utf-8")
    lift_script.chmod(0o755)

    total_fns = sum(m["function_count"] for m in modules_summary)
    total_syms = sum(m["dynamic_symbols"] for m in modules_summary)

    # 7. Write manifest.json and DECOMP_REPORT.md
    manifest = {
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "engine": "AetherNX Universal Decomp/Recomp/Comp Engine",
        "title_id": tid_hex,
        "name": info["name"],
        "version": ver,
        "total_functions": total_fns,
        "total_dynamic_symbols": total_syms,
        "base": info["base"],
        "updates": info["updates"],
        "dlcs": info["dlcs"],
        "shader_count": info["shader_count"],
        "modules": modules_summary,
    }
    (ws / "manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )

    updates_str = ", ".join(f"`{u['name']}` ({u['version']})" for u in info["updates"]) or "None"
    dlcs_str = ", ".join(f"`{d['title_id']}` ({d['name']})" for d in info["dlcs"]) or "None"
    report_md = [
        f"# AetherNX Decomp & Static Recomp Report — {info['name']} (`{tid_hex}`)",
        "",
        f"- **Packed Version**: `{ver}`",
        f"- **Base Container**: `{info['base']['name']}` ({info['base']['size_bytes'] / 2**30:.2f} GiB)",
        f"- **Updates Merged**: {updates_str}",
        f"- **DLCs Mounted**: {len(info['dlcs'])} ({dlcs_str})",
        f"- **Total Discovered Functions (`.eh_frame_hdr` + exports)**: **{total_fns:,}**",
        f"- **Total Dynamic Symbols**: **{total_syms:,}**",
        f"- **Total NVN/Metal Shaders**: **{info['shader_count']:,}**",
        "",
        "## Executable Modules (`ExeFS`)",
        "",
        "| Module | Build ID | `.text` (MiB) | `.rodata` (MiB) | `.data` (MiB) | `.bss` (MiB) | Functions | Dynamic Syms | `SVC` Sites | `TLS/MRS` Sites |",
        "|---|---|---|---|---|---|---|---|---|---|",
    ]
    for m in modules_summary:
        report_md.append(
            f"| `{m['module']}` | `{m['build_id']}` | {m['text_size']/2**20:.2f} | {m['rodata_size']/2**20:.2f} | "
            f"{m['data_size']/2**20:.2f} | {m['bss_size']/2**20:.2f} | {m['function_count']:,} | {m['dynamic_symbols']:,} | "
            f"{m['svc_sites']} | {m['tls_mrs_sites']} |"
        )
    report_md += [
        "",
        "## Generated Artifacts",
        "",
        "- `manifest.json` — Machine-readable module, symbol, function, and DLC manifest",
        "- `functions/<module>_functions.tsv` — Complete function table with start address, size, raw symbol, and demangled C++ signature",
        "- `symbols/<module>_symbols.tsv` — Exported and imported dynamic symbol table classified by SDK subsystem (`nn::*`, `nvn`, `sead`, `libc`)",
        "- `src/main_reconstruct.cpp` & `CMakeLists.txt` — Clean-room C++20 byte-matching decompilation unit pre-wired to `decomp/nnheaders` and `decomp/sead`",
        "- `recomp/nxrt_game_desc.c`, `recomp/lift_nso.sh` & `recomp/lifted_c/` — Static recompilation (`nxrt`) descriptor and AArch64-to-C11 translation units",
    ]
    (ws / "DECOMP_REPORT.md").write_text("\n".join(report_md) + "\n", encoding="utf-8")
    return manifest


def run_recomp_lift(game_dir: Path, module: str = "main", limit: int = 0) -> dict:
    """Run nxrt static AArch64-to-C11 lifter on an extracted Switch game module."""
    info = scan_game_folder(game_dir)
    if not info:
        raise RuntimeError(f"Could not identify a Switch game in {game_dir}")
    work = Path(info["build_status"]["work_dir"])
    if not info["build_status"]["extracted_versions"]:
        raise RuntimeError(f"No extracted ExeFS found in {work / 'extract'}")
    ver = info["build_status"]["extracted_versions"][-1]
    exefs = work / "extract" / ver / "ExeFS"
    nso_path = exefs / module
    if not nso_path.is_file():
        raise RuntimeError(f"Module {module} not found at {nso_path}")

    out_dir = work / "decomp_workspace" / "recomp" / ("lifted_c" if module == "main" else f"lifted_{module}")
    out_dir.mkdir(parents=True, exist_ok=True)
    base_addr = "0x7000000000" if module == "rtld" else "0x7100000000"
    gen_py = REPO_ROOT / "recomp" / "nxrt" / "tools" / "gen.py"
    hle_txt = REPO_ROOT / "recomp" / "nxrt" / "runtime" / "hle" / "hle_symbols.txt"

    cmd = [
        sys.executable,
        str(gen_py),
        module,
        str(nso_path),
        base_addr,
        str(out_dir),
        "--hle",
        str(hle_txt),
    ]
    if limit > 0:
        cmd += ["--limit", str(limit)]

    env = os.environ.copy()
    env["PYTHONPATH"] = str(REPO_ROOT / "recomp" / "nxrt" / "tools")
    subprocess.run(cmd, env=env, check=True)
    chunks = sorted(p.name for p in out_dir.glob(f"{module}_*.c"))
    return {
        "title_id": info["title_id"],
        "name": info["name"],
        "module": module,
        "output_dir": str(out_dir),
        "chunks_generated": len(chunks),
    }


def run_doctor() -> dict:
    """Comprehensive audit of the AetherNX environment, tools, skills, and repository integrity."""
    checks = []

    def add_check(name: str, ok: bool, detail: str):
        checks.append({"name": name, "ok": ok, "detail": detail})

    # 1. Python modules
    for mod_name in ("capstone", "lz4", "zstandard", "nsz"):
        try:
            __import__(mod_name)
            add_check(f"Python package: {mod_name}", True, "Installed")
        except ImportError as e:
            add_check(f"Python package: {mod_name}", False, str(e))

    # 2. External CLI tools
    for tool in ("clang", "clang++", "xcrun", "xcodebuild", "glslangValidator", "dotnet", "7zz", "unar"):
        path = shutil.which(tool)
        add_check(f"System tool: {tool}", path is not None, path or "Missing")

    # 3. Keys & Firmware auto-detection
    keys_path = builder.PROD_KEYS
    add_check(
        "Switch prod.keys",
        bool(keys_path and Path(keys_path).is_file()),
        keys_path or "Not configured",
    )
    fw_candidates = list(Path("~/.switch").glob("Firmware*.zip")) if Path("~/.switch").is_dir() else []
    fw_path = str(fw_candidates[-1]) if fw_candidates else None
    add_check(
        "Switch System Firmware",
        fw_path is not None,
        fw_path or "Optional (user-supplied Firmware.zip)",
    )

    # 4. Skills check
    skills_dir = REPO_ROOT / "skills"
    skill_files = sorted(skills_dir.glob("*/SKILL.md")) if skills_dir.is_dir() else []
    add_check("AI Agent Skills", len(skill_files) >= 15, f"{len(skill_files)} skills verified")

    # 5. Subsystems check
    for sub_rel in (
        "dm",
        "recomp/nxrt",
        "recomp/switchrecomp",
        "recomp/mush8-crates",
        "decomp/nnheaders",
        "decomp/sead",
        "decomp/dread-tools",
        "frontends/nx-play",
        "frontends/lumanx",
        "frontends/nx-library",
        "frontends/nx-os",
        "AetherNX.app/Contents/MacOS/AetherNX",
        "COPYRIGHT.md",
        "PROVENANCE.md",
        "README.md",
    ):
        p = REPO_ROOT / sub_rel
        add_check(f"Component: {sub_rel}", p.exists(), str(p))

    # 6. Python syntax check across all .py files (in-memory via ast.parse, no __pycache__ pollution)
    py_files = [p for p in REPO_ROOT.rglob("*.py") if not p.is_symlink()]
    syntax_errors = []
    for p in py_files:
        try:
            ast.parse(p.read_bytes(), filename=str(p))
        except Exception as e:
            syntax_errors.append(f"{p.relative_to(REPO_ROOT)}: {e}")
    add_check(
        "Repository-wide Python syntax audit",
        len(syntax_errors) == 0,
        f"{len(py_files)} files checked, {len(syntax_errors)} errors",
    )

    # 7. Broken symlinks audit
    broken_links = [
        str(p.relative_to(REPO_ROOT))
        for p in REPO_ROOT.rglob("*")
        if p.is_symlink() and not p.exists()
    ]
    add_check(
        "Symlink integrity audit",
        len(broken_links) == 0,
        "0 broken symlinks" if not broken_links else f"Broken: {', '.join(broken_links)}",
    )

    all_ok = all(c["ok"] for c in checks)
    return {"healthy": all_ok, "checks": checks}


def main():
    ap = argparse.ArgumentParser(description="AetherNX Library Scanner & Decomp/Recomp Generator")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p_scan = sub.add_parser("scan", help="Scan game library folders for Switch games, updates, and DLCs")
    p_scan.add_argument("dirs", nargs="*", help="Library directories to scan")
    p_scan.add_argument("--json", action="store_true", help="Output JSON")

    p_decomp = sub.add_parser("decomp-init", help="Initialize Decomp & Static Recomp workspace for an extracted game")
    p_decomp.add_argument("game_dir", help="Path to the game folder")
    p_decomp.add_argument("--json", action="store_true", help="Output JSON")

    p_lift = sub.add_parser("recomp-lift", help="Run static AArch64-to-C11 lifter (nxrt) on an extracted game")
    p_lift.add_argument("game_dir", help="Path to the game folder")
    p_lift.add_argument("--module", default="main", help="ExeFS module to lift (default: main)")
    p_lift.add_argument("--limit", type=int, default=0, help="Limit number of lifted functions (0 = all)")
    p_lift.add_argument("--json", action="store_true", help="Output JSON")

    p_unpack = sub.add_parser("unpack", help="Unpack .zip/.rar/.7z/.tar.* archives and optionally decompress .nsz/.xcz files")
    p_unpack.add_argument("target", help="Archive file (.zip, .rar, .7z, .nsz) or game directory")
    p_unpack.add_argument("--out", help="Optional output game folder")
    p_unpack.add_argument("--decompress-nsz", action="store_true", help="Also convert .nsz/.xcz to .nsp/.xci using prod.keys")
    p_unpack.add_argument("--delete-archive", action="store_true", help="Delete source archive after successful extraction")
    p_unpack.add_argument("-k", "--keys", help="Path to prod.keys for .nsz/.xcz decompression")
    p_unpack.add_argument("--json", action="store_true", help="Output JSON")

    p_doc = sub.add_parser("doctor", help="Run full AetherNX repository and toolchain audit")
    p_doc.add_argument("--json", action="store_true", help="Output JSON")

    args = ap.parse_args()
    if args.cmd == "scan":
        roots = [Path(d).expanduser().resolve() for d in args.dirs] if args.dirs else DEFAULT_LIBRARY_ROOTS
        games = scan_libraries(roots)
        if args.json:
            print(json.dumps({"games": games}, indent=2, ensure_ascii=False))
        else:
            for g in games:
                print(
                    f"[{g['title_id']}] {g['name']} | Updates: {len(g['updates'])} | DLCs: {len(g['dlcs'])} | "
                    f"Shaders: {g['shader_count']:,} | MacApp: {g['mac_app'] is not None} | "
                    f"DecompReady: {g['decomp_ready']} | RecompChunks: {g['lifted_chunks']}"
                )
    elif args.cmd == "decomp-init":
        manifest = init_decomp_workspace(Path(args.game_dir).expanduser().resolve())
        if args.json:
            print(json.dumps(manifest, indent=2, ensure_ascii=False))
        else:
            total_fns = sum(m["function_count"] for m in manifest["modules"])
            print(
                f"[AetherNX] Decomp & Recomp workspace initialized for {manifest['name']} ({manifest['title_id']} {manifest['version']}): "
                f"{len(manifest['modules'])} modules, {total_fns:,} functions mapped."
            )
    elif args.cmd == "recomp-lift":
        res = run_recomp_lift(Path(args.game_dir).expanduser().resolve(), args.module, args.limit)
        if args.json:
            print(json.dumps(res, indent=2, ensure_ascii=False))
        else:
            print(
                f"[AetherNX] Static Recomp (nxrt) completed for {res['name']} ({res['module']}): "
                f"{res['chunks_generated']} C11 files written to {res['output_dir']}"
            )
    elif args.cmd == "unpack":
        out_p = Path(args.out).expanduser().resolve() if args.out else None
        res = unpack_target(
            Path(args.target).expanduser().resolve(),
            out_dir=out_p,
            decompress_nsz=args.decompress_nsz,
            delete_archives=args.delete_archive,
            keys_override=args.keys,
        )
        if args.json:
            print(json.dumps(res, indent=2, ensure_ascii=False))
        else:
            print(
                f"[AetherNX] Unpack completed -> {res['output_dir']} | "
                f"Archives extracted: {len(res['extracted_archives'])} | "
                f"NSZ/XCZ decompressed: {len(res['decompressed_nsz'])} | "
                f"Packages ready: {len(res['packages_found'])}"
            )
    elif args.cmd == "doctor":
        rep = run_doctor()
        if args.json:
            print(json.dumps(rep, indent=2, ensure_ascii=False))
        else:
            for c in rep["checks"]:
                mark = "✔" if c["ok"] else "✘"
                print(f"  {mark} {c['name']}: {c['detail']}")
            print(f"\nOverall Status: {'HEALTHY (0 issues)' if rep['healthy'] else 'ISSUES DETECTED'}")
        sys.exit(0 if rep["healthy"] else 1)


if __name__ == "__main__":
    main()
