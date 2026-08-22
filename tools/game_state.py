#!/usr/bin/env python3
"""Read DiceWars ZX game state out of the running ZEsarUX emulator.

Usage:
    game_state.py [--port 10000] [--sym build/dicewars.sym]

Uses the sjasmplus symbol table written by the build and ZRCP's
read-memory, so the live game (areas, owners, dice, centers, adjacency,
players, cursor) can be inspected - the backbone of closed-loop testing.
Importable: state(), read_mem(), moves_to(), plan_attack().
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SYM = {}
PORT = 10000


def load_syms(path=None):
    global SYM
    path = Path(path) if path else ROOT / "build" / "dicewars.sym"
    SYM = {}
    for line in path.read_text().splitlines():
        m = re.match(r"([\w.]+): EQU 0x([0-9A-F]+)", line)
        if m:
            SYM[m.group(1)] = int(m.group(2), 16)
    return SYM


def read_mem(addr, length):
    out = subprocess.run(
        [sys.executable, str(ROOT / "tools" / "zx_control.py"),
         "--port", str(PORT), "raw", f"read-memory {addr} {length}"],
        capture_output=True, text=True).stdout.strip()
    return bytes.fromhex(out)


def state():
    s = {}
    s["ban"] = read_mem(SYM["ban"], 1)[0]
    s["jun"] = list(read_mem(SYM["jun"], 8))
    s["pmax"] = read_mem(SYM["pmax"], 1)[0]
    s["humans"] = read_mem(SYM["humans"], 1)[0]
    s["cursor"] = (read_mem(SYM["cursor_row"], 1)[0],
                   read_mem(SYM["cursor_col"], 1)[0])
    for name in ("a_size", "a_arm", "a_dice", "a_crow", "a_ccol"):
        s[name] = list(read_mem(SYM[name], 32))
    s["join"] = read_mem(SYM["a_join"], 1024)
    s["p_area_tc"] = list(read_mem(SYM["p_area_tc"], 8))
    s["p_stock"] = list(read_mem(SYM["p_stock"], 8))
    s["game_state"] = read_mem(SYM["game_state"], 1)[0]
    return s


def moves_to(cur, dest):
    """QAOP key names to move the map cursor from cur to dest (row, col)."""
    keys = []
    r, c = cur
    tr, tc = dest
    while r > tr: keys.append("Q"); r -= 1
    while r < tr: keys.append("A"); r += 1
    while c > tc: keys.append("O"); c -= 1
    while c < tc: keys.append("P"); c += 1
    return keys


def plan_attack(s):
    """First (own 2+dice area, adjacent enemy area) for the current player."""
    pn = s["jun"][s["ban"]]
    for i in range(1, 32):
        if s["a_size"][i] == 0 or s["a_arm"][i] != pn or s["a_dice"][i] < 2:
            continue
        for j in range(1, 32):
            if s["a_size"][j] == 0 or s["a_arm"][j] == pn:
                continue
            if s["join"][i * 32 + j]:
                return i, j
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--port", type=int, default=10000)
    ap.add_argument("--sym", default=None)
    args = ap.parse_args()
    global PORT
    PORT = args.port
    load_syms(args.sym)

    s = state()
    pn = s["jun"][s["ban"]]
    print(f"ban={s['ban']} current_pn={pn} humans={s['humans']} pmax={s['pmax']}")
    print(f"cursor={s['cursor']} game_state={s['game_state']}")
    print(f"area_tc={s['p_area_tc']} stock={s['p_stock']}")
    alive = [(i, s['a_arm'][i], s['a_dice'][i], (s['a_crow'][i], s['a_ccol'][i]))
             for i in range(32) if s['a_size'][i]]
    print("areas (id, arm, dice, center):", alive)
    print("attack plan for current player:", plan_attack(s))


if __name__ == "__main__":
    main()
else:
    load_syms()
