#!/usr/bin/env python3
"""Build the whole game: sources -> bootable TR-DOS disk image.

Usage:
    build_dicewars.py build/dicewars.trd [--build-dir build] [--force]

Steps:
    1. tools/font_gen.py   src/res/font/font8.txt -> build/font8.asm
    2. tools/music_gen.py  src/music/tune.txt     -> build/tune.asm
    3. tools/basic_tokenize.py src/basic/boot.bas.txt -> build/boot.B.bin
       (plus the TR-DOS autostart trailer #80 #AA <line>)
    4. bin/sjasmplus assembles src/game/dicewars.asm -> build/dicewars.bin
    5. tools/trd_build.py packs boot.B + dicewars.C -> the .trd

The resulting disk boots with TR-DOS's RUN (loads "boot", which CLEARs,
loads the CODE at #6000 and jumps to it).
"""

import argparse
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SJASMPLUS = ROOT / "bin" / "sjasmplus" / "sjasmplus"
AUTOSTART_LINE = 10
CODE_ORG = 24576


def run(cmd, **kw):
    printable = " ".join(str(c) for c in cmd)
    print(f"+ {printable}")
    res = subprocess.run(cmd, cwd=ROOT, **kw)
    if res.returncode != 0:
        sys.exit(f"error: command failed: {printable}")
    return res


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("output", type=Path, help="path of the .trd to write")
    ap.add_argument("--build-dir", type=Path, default=ROOT / "build")
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()

    build = args.build_dir
    build.mkdir(parents=True, exist_ok=True)
    out_trd = args.output
    if out_trd.exists() and not args.force:
        sys.exit(f"error: {out_trd} exists (use --force)")

    # 1-2: generated resources
    run([sys.executable, "tools/font_gen.py", "src/res/font/font8.txt",
         "--out", str(build / "font8.asm"), "--force"])
    run([sys.executable, "tools/music_gen.py", "src/music/tune.txt",
         "--out", str(build / "tune.asm"), "--force"])

    # 3: the BASIC loader (tokenized program + autostart trailer)
    res = subprocess.run(
        [sys.executable, "tools/basic_tokenize.py", "src/basic/boot.bas.txt"],
        cwd=ROOT, capture_output=True)
    if res.returncode != 0:
        sys.exit("error: basic_tokenize failed:\n" + res.stderr.decode())
    program = res.stdout
    body = program + bytes([0x80, 0xAA, AUTOSTART_LINE & 0xFF, AUTOSTART_LINE >> 8])
    (build / "boot.B.bin").write_bytes(body)
    print(f"build/boot.B.bin: {len(program)} bytes of BASIC + autostart trailer")

    # 4: assemble (the symbol table feeds tools/game_state.py)
    run([str(SJASMPLUS), "--nologo", f"--sym={build}/dicewars.sym",
         "src/game/dicewars.asm"])
    game = (build / "dicewars.bin").read_bytes()
    print(f"build/dicewars.bin: {len(game)} bytes at #{CODE_ORG:04X}")

    # 5: pack the disk
    manifest = {
        "label": "DICEWARS",
        "disk_type": 22,
        "files": [
            {"name": "boot", "type": "B",
             "param1": len(program), "length": len(program),
             "file": "boot.B.bin"},
            {"name": "dicewars", "type": "C",
             "param1": CODE_ORG, "length": len(game),
             "file": "dicewars.bin"},
        ],
    }
    manifest_path = build / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    run([sys.executable, "tools/trd_build.py", str(manifest_path),
         str(out_trd), "--force"])
    print(f"{out_trd}: ok")


if __name__ == "__main__":
    main()
