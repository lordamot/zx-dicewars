# DiceWars ZX - design notes

## Source of truth

The game logic is ported from `../dicewars/js/game.js` (map generation,
battles, reinforcements, AI) and `../dicewars/js/main.js` (flow). When in
doubt about a rule, that's where to look; the port keeps even the
original's quirks:

- the "rank players by dice" bubble sort swaps only the `dice_jun` values
  while comparing the *unsorted* `dice_c` totals - replicated as-is;
- an even-dice attack is taken with probability ~90% (`rand byte >= 26`),
  or always if attacker or defender is ranked first;
- a runaway leader (more than 2/5 of all dice) limits the AI to fights
  involving that leader;
- initial dice dealing stops entirely the moment one player's areas are
  all full (`if (c2 === 0) break` in JS - `ret z` after
  `build_supply_list` here).

Dropped relative to the remake: the history replay, and the map-preview
dice are shown but there is no isometric dice art - the dice count is a
bold digit in the area's center cell.

## The grid

- 32x20 cells (`XMAX`/`YMAX`), cell index = `row*32 + col`, so
  `col = idx & 31`, `row = idx >> 5` - and the 640 cells map 1:1 onto the
  first 640 attribute bytes at `#5800`.
- 4-way adjacency everywhere (the hex remake is 6-way): `get_neighbors`
  is the single authority for neighbour enumeration.
- Up to 31 areas (`AREA_MAX 32`, id 0 = sea). Percolation target is 8
  cells (`PERC_CMAX`) before the frontier absorb; areas of 5 cells or
  fewer are dropped, which matches the remake's `size <= 5`.

## Per-frame model

IM2 interrupt (table `#FE00`, all bytes `#FD`, handler stub at `#FDFD`)
runs: frame counter, music row/envelope, SFX state machine, then writes
the 11 AY shadow registers (`ay_regs`). The main thread calls
`wait_frame` = `HALT` + PRNG stir + `key_scan` (+ the `S` music toggle).
Everything interactive polls `key_new` (edge) / `key_state` (level) once
per frame.

Important consequence for emulator automation: a key must be held for
more than one frame to be seen reliably - `zx_control.py press --held 3`.

## Rendering rules

- `draw_cell` is self-contained: sea = black; land = owner's attribute,
  border ink lines on edges whose neighbour cell belongs to a different
  area (map edges count as borders), plus the bold dice digit if this is
  the area's center cell. Redrawing any cell is therefore always safe.
- Selection/attack highlight = FLASH bit OR-ed into the area's attribute
  cells; a full `draw_map` clears it (it rewrites all 640 attributes).
- The cursor is an XOR-ed 8x8 ring; XOR again to remove. Anyone moving
  the cursor must XOR it off first (and mind that `cursor_xor` uses BC).

## Player palette

`player_attr` in vars.asm, order mirrors the remake's palette:

| P | remake | ZX attr | note |
|---|---|---|---|
| 0 | purple | bright magenta | human 1 |
| 1 | green | bright green | human 2 in hotseat |
| 2 | dark green | green, white ink | |
| 3 | pink | bright white | |
| 4 | orange | olive (non-bright yellow) | |
| 5 | cyan | bright cyan | |
| 6 | yellow | bright yellow | |
| 7 | red | bright red | |

## Known Z80 pitfalls in this codebase

Bugs of this shape were already found and fixed - keep them in mind:

- `pr_slot_col`, `cursor_xor`, `get_neighbors` each destroy registers a
  caller may still need (A / BC); check the header comment of any helper
  before relying on registers across a call.
- `find_min_*` loop bounds compare DE against `#0280` (=640) as
  `d == 2 && e == #80` - only valid because DE never skips past it.
- `bat_anim` with `an_count = 0` would loop the die index 256 times -
  callers guarantee count >= 1 (an area always has at least 1 die).

## Timing

Map generation is ~2s (Pentagon 3.5MHz): random priorities, ~31
percolations with a frontier *list* for the min-search (`fr_list` -
the full-grid scan cost 3x more), the absorb/hole/size/center passes,
then `draw_map` (~2 frames). Battles are ~1s per hand of dice
(16 + 3*count frames plus pauses).
