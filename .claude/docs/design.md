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

## Text and encoding

All strings are UTF-8 Russian in src/res/text/strings.txt, compiled by
text_gen.py into the game's encoding: 32..95 ASCII, 96..127 = А..Я
alphabet order (no Ё). font8.txt draws both alphabets (Cyrillic letters
shaped like Latin ones are `alias` entries). Layout constraints live as
comments in strings.txt: 32 columns, tagged messages start at column 3
(<= 29 chars), banners take 2 columns per char. The player tag is
"И1".."И8" (CH_PLAYER in const.asm). The logo is 13 chars = 26 cells
(LOGO_CELLS).

## Photo screens

Three digitized photos (from `orig/*.jpg`, the author at his bench):

- `screen`<C> on disk = the loading screen, loaded straight to #4000 by
  the BASIC loader before the game CODE, so it shows during the load.
  After init, `splash_hold` brands it (draw_logo at 0,0 + the prompt
  bar) and waits for a key or ~8s.
- `scr_youwin` / `scr_gameover` are INCBIN-ed into the game;
  `win_screen` / `game_over_screen` blit them (`show_scr`) and overlay a
  `banner2x` (double-size text, black cells, coloured ink - the winner's
  colour / bright red) on rows 0-1 plus the row-23 prompt bar.

Conversion pipeline: `photo2bmp.py` (crop to 4:3, resize 256x192,
grayscale, autocontrast, **unsharp mask radius 3 / 220%** - this is what
makes faces survive the dither - gamma 0.8) then `bmp2zx.py --dither
floyd`. Colour versions were tried and rejected: skin maps to blotchy
red/yellow attribute patches; 1-bit Floyd is the classic ZX digitized
look (openit's prize photos are the same style).

## Timing

Map generation is ~2s (Pentagon 3.5MHz): random priorities, ~31
percolations with a frontier *list* for the min-search (`fr_list` -
the full-grid scan cost 3x more), the absorb/hole/size/center passes,
then `draw_map` (~2 frames). Battles are ~1s per hand of dice
(16 + 3*count frames plus pauses).
