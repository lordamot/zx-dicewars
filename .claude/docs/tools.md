# Tools

All standalone Python 3 CLIs (standard library + Pillow only for the
debug screenshots), run from the repository root.

## Project-specific

### build_dicewars.py

The whole pipeline. `python3 tools/build_dicewars.py build/dicewars.trd
[--build-dir build] [--force]`: generates font + music asm, tokenizes the
BASIC loader (appending the TR-DOS `80 AA <line>` autostart trailer),
assembles with `bin/sjasmplus`, packs the `.trd` via `trd_build.py` with
`boot`<B> (param1 = program length) and `dicewars`<C> (param1 = 24576
load address).

### font_gen.py

`src/res/font/font8.txt` -> `build/font8.asm`. Input is `char X` blocks
of 8 rows x 8 cols of `#`/`.`. Output: `font8` (ASCII 32..95, blank for
undrawn chars) and `dicefont` (bold digits 1..8 for the map). Edit the
txt, rebuild, done.

### music_gen.py

`src/music/tune.txt` -> `build/tune.asm`. Text tracker: `tempo N`,
`pattern NAME` + rows of three cells (channels A bass / B arpeggio /
C lead), each `A-2` / `C#4` / `---` (keep) / `off` (release), then
`order P1 P2 ...`. Output: `music_tempo`, `ay_note_table` (96 AY periods
for the 1.77MHz 128K clock, A-4 = 440Hz) and `song_a/b/c` byte streams
(0 keep, 1 release, note+2, #FF loop). The player is
`src/game/music.asm`.

### text_gen.py

`src/res/text/strings.txt` (UTF-8, `label|text` lines) ->
`build/strings.asm` (`s_<label>` DB rows). Game text encoding: 32..95 =
ASCII, 96..127 = А..Я in alphabet order (Ё -> Е, lowercase uppercased).
The font table from font_gen.py covers the same 96 codes; trailing
spaces in strings are preserved (used to overprint longer values).

### game_state.py

Read the live game state (areas, owners, dice, centers, adjacency,
players, cursor) out of emulated RAM: the build writes
`build/dicewars.sym` and this tool combines it with ZRCP `read-memory`.
Run it for a dump, or import it (`state()`, `moves_to()`,
`plan_attack()`) from test scripts. `--port` selects the emulator
instance.

### photo2bmp.py

Asset preparation for the photo screens (the one tool needing Pillow;
not part of `make build`): crop a photo full-width from `--top`, resize
to 256x192, grayscale + autocontrast + unsharp mask + gamma - tuned so
faces survive Floyd dithering. `make screens` runs it for the three
photos in `orig/`; the resulting `src/res/screens/*.bmp` are the
committed source art.

## Copied from ../zx-openit (see its docs for the full story)

- `bmp2zx.py` - BMP -> ZX screen bytes (15-colour reduction, 2-per-cell
  attribute rule, `--dither floyd/bayer`), used at build time for the
  three photo screens.
- `trd_build.py` / `trd_unpack.py` / `trdlib.py` - TR-DOS images.
- `basic_tokenize.py` / `basic_detokenize.py` / `basiclib.py` - ZX BASIC
  text <-> tokenized bytes (supports `\xNN` escapes for token bytes).
- `zx_control.py` - drive the bundled ZEsarUX over ZRCP: `launch --trd`,
  `boot-trdos` (Pentagon boot-menu navigation), `press KEY [--held N]`,
  `screenshot`, `ocr`, `raw "<zrcp command>"`.

  **Extended here**: `press --held N --release N` - the game polls the
  keyboard once per frame, so the default 1-frame pulse races with the
  scan; use `--held 3` when driving the game.

  `raw` is the debug superpower: `raw "read-memory ADDR LEN"` and
  `raw "write-memory ADDR B B B..."` inspect and patch live game state.

## Debug scripts (tmp/, not committed)

`tmp/autoplay.py` boots the disk and plays a human attack (cursor
navigation via game_state); `tmp/fullgame.py` plays a complete game and
reports the outcome; `tmp/deselect_test.py` checks select/deselect.
