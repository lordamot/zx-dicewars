# DiceWars ZX

**DiceWars** — the classic territorial dice game (original: Copyright (C)
2001 GAMEDESIGN, gamedesign.jp) — remade from scratch for the **ZX Spectrum
128 / Pentagon**, shipped as a bootable TR-DOS `.trd` disk image.

The game logic is a faithful port of the sibling browser remake in
[`../dicewars`](../dicewars): the same percolation map generator, the same
battle rules (all dice vs all dice, ties go to the defender), the same
largest-connected-group reinforcements with a 64-dice stock, and the same
computer opponent — including its quirks (the runaway-leader filter, the
"mostly attack on even dice" coin toss). What changed is everything the
8-bit platform dictates — see below.

```sh
make build    # src/ -> build/dicewars.trd
make run      # build it, launch the bundled ZEsarUX, boot TR-DOS, RUN it
```

Everything on the disk is generated from readable source: Z80 assembly for
sjasmplus, a UTF-8 BASIC loader, a hand-drawn text-bitmap font and a text
tracker score. No binaries live in `src/`.

## Playing

- **2..8 players** (keys `2`-`8` on the title screen), **1 or 2 humans**
  (`H` toggles; hotseat with a shared keyboard), `S` toggles music.
- `ENTER`/`SPACE` starts; accept the generated map with `Y` or roll
  another with `N`.
- On your turn: move the cell cursor with `Q`/`A`/`O`/`P`, press
  `SPACE`/`ENTER`/`M` on your own area with 2+ dice (it starts flashing),
  then on an adjacent enemy area to attack. Both sides roll **all** their
  dice; the higher total wins, ties go to the defender. A win moves all
  but one die into the captured area. Press the selected area again to
  deselect.
- `E` ends your turn: you receive one die per area of your largest
  connected group, spread randomly over your not-yet-full areas (max 8
  per area; the excess is stocked, up to 64).
- Eliminate everyone to win. Player 1 is purple (magenta), player 2 in
  hotseat is green — the same seats as the browser remake.

## The port: what the Spectrum dictated

| | browser remake | ZX Spectrum |
|---|---|---|
| map | 28x32 hex cells, free-form rendering | **32x20 grid of 8x8 cells** — one cell = one attribute cell, so every territory is a solid colour block and attribute clash *cannot happen* by construction |
| adjacency | 6-way (hexes) | 4-way (squares) |
| dice stacks | isometric pips, 28px dice | a bold digit 1-8 in each area's center cell |
| player colours | 8 arbitrary RGB | 8 of the Spectrum's 15: bright magenta, bright green, green, bright white, olive, bright cyan, bright yellow, bright red (P1/P2 keep the remake's purple/green identity) |
| selection | outline highlight | the whole area FLASHes (hardware flash attribute) |
| battle animation | 3D dice tumbling in | each die flickers through random faces and settles left-to-right with an AY noise click, then the totals appear |
| sound | mp3 samples | a 3-channel AY-3-8912 pattern player (bass / arpeggio / lead, A-minor loop) + effects on channel C |
| history replay | yes | dropped (out of scope for 48K of code + buffers) |

The map generator is the same algorithm cell-for-cell: shuffled random
priorities drive percolation growth of up to 31 areas, the leftover
frontier is absorbed, sub-6-cell areas sink back into the sea, and each
area's dice digit sits on the cell nearest the bounding-box center with
border cells penalised.

## Repo layout

```
src/
  basic/boot.bas.txt       the BASIC loader, plain UTF-8 text (3 lines)
  game/*.asm               the game: ~4400 lines of commented Z80
    dicewars.asm             top level: ORG #6000, includes, SAVEBIN
    main.asm                 entry, title, flow, human turn, endgame
    map.asm                  map generation, connectivity (set_area_tc)
    ai.asm                   com_thinking - the computer opponent
    battle.asm               battles, dice animation, reinforcements
    render.asm               cells, borders, digits, text, big text
    hud.asm                  message line and the player status row
    input.asm                keyboard matrix scan with edge detection
    music.asm                IM2 handler, AY pattern player, SFX
    random.asm               xorshift PRNG
    const/vars/bss.asm       constants, state, work buffers
  music/tune.txt           the soundtrack as a text tracker score
  res/font/font8.txt       the 8x8 font as text bitmaps ('#' = pixel)
tools/                     standalone CLI tools (below)
bin/                       sjasmplus + ZEsarUX, prebuilt (from ../zx-openit)
build/                     output (gitignored)
.claude/docs/              design and tooling notes
```

## Build pipeline

`tools/build_dicewars.py` runs the lot:

1. `font_gen.py` compiles `src/res/font/font8.txt` (edit glyphs as
   `#`/`.` pixel art) into `build/font8.asm`.
2. `music_gen.py` compiles `src/music/tune.txt` (edit notes as `A-2`,
   `C#4`, per-row per-channel) into the AY period table and three song
   streams in `build/tune.asm`.
3. `basic_tokenize.py` turns the BASIC text into tokenized bytes plus the
   TR-DOS autostart trailer.
4. `sjasmplus` assembles the whole game to one CODE block at `#6000`
   (7.9K); work buffers and the IM2 vector page live above it in RAM.
5. `trd_build.py` packs `boot`&lt;B&gt; + `dicewars`&lt;C&gt; into a
   640K TR-DOS image. Typing `RUN` in TR-DOS boots it.

## Tools

| Tool | What it does |
|---|---|
| `build_dicewars.py` | the whole pipeline: sources -> bootable `.trd` |
| `font_gen.py` | text-bitmap font -> `.asm` |
| `music_gen.py` | text tracker score -> AY note table + song data `.asm` |
| `game_state.py` | dump the live game state out of emulated RAM (symbol table + ZRCP) |
| `trd_build.py` / `trd_unpack.py` | TR-DOS disk images in and out *(from zx-openit)* |
| `basic_tokenize.py` / `basic_detokenize.py` | ZX BASIC text <-> tokenized bytes *(from zx-openit)* |
| `zx_control.py` | drive the bundled ZEsarUX: boot a disk, press keys (now with `--held` for per-frame-polling programs), screenshot, read/write memory *(from zx-openit, extended)* |

Development is fully closed-loop: the emulator's remote protocol lets the
build be booted, played (`tmp/` holds autoplay scripts that read the game
state straight out of emulated RAM and drive the keyboard) and
screenshotted without a human in the chair.

## Technical notes

- **Memory map**: CODE at `#6000`..`#7EDF`ish (game + font + music data),
  BSS buffers to ~`#8C00`, stack below `#FDF0`, IM2 vector table at
  `#FE00` with the handler thumb at `#FDFD` (classic single-byte-table
  trick). Runs in 48K address space; the 128 is needed for the AY.
- **Interrupts**: IM2 handler = frame counter + music player + SFX +
  writing the 11 AY shadow registers. The main thread syncs with `HALT`.
- **Colour**: each map cell owns its attribute byte, ink black (white on
  the dark colours), paper = owner. Borders are ink pixels on cell edges
  where the neighbouring cell belongs to someone else. The 640 map cells
  map 1:1 onto the first 640 attribute bytes — `cel[]` index == attribute
  offset.
- **Music**: `tune.txt` compiles to one byte per row per channel
  (keep / release / note); the player retriggers a software envelope per
  note (init volume, decay to sustain). Effects (dice click, capture
  slide, defeat slide, your-turn beeps, win arpeggio, supply tick) borrow
  channel C and the noise mixer until their timer expires.

## Credits

Original game by **GAMEDESIGN** (gamedesign.jp), 2001. Browser remake:
[`../dicewars`](../dicewars). Build/emulator tooling and project
organisation from [`../zx-openit`](../zx-openit). This is a fan
preservation/porting exercise.
