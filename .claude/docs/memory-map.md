# Memory map

Everything runs in the 48K address space; 128K hardware is needed only
for the AY-3-8912. No bank switching.

| Range | What |
|---|---|
| `#4000`-`#57FF` | screen pixels |
| `#5800`-`#5AFF` | attributes; the first 640 bytes are the map rows 0..19, cell index == attribute offset |
| `#5B00`-`#5FFF` | free (BASIC leftovers; CLEAR 24575 puts BASIC's stack here) |
| `#6000` | **CODE block start** = entry point (`start:` in main.asm). Loaded from disk (`dicewars`<C>, ~7.9K) |
| ... | game code, initialised vars, font (`font8`, `dicefont`), music data (`ay_note_table`, `song_a/b/c`) |
| `code_end` | end of the loaded file |
| `code_end`..`bss_end` | uninitialised work buffers (bss.asm): `cel`/`map_num`/`rcel`/`next_f` (640 each), `a_join` (1024), AI attack lists (2x256), `fr_list` (256), scratch. `ASSERT bss_end < #F000` |
| `#F000`-`#FDEF` | free headroom |
| `#FDF0` | initial SP (grows down) |
| `#FDFD` | IM2 handler stub: `JP isr` (3 bytes) |
| `#FE00`-`#FF00` | IM2 vector table, 257 x `#FD` |

The BASIC loader does `CLEAR 24575`, loads the CODE at 24576 and
`RANDOMIZE USR 24576`; `start:` immediately takes over SP and interrupts,
so nothing else depends on BASIC's state.
