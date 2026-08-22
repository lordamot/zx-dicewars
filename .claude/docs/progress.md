# Progress

## Done (2026-08-23)

- Repo scaffolded after ../zx-openit: tools/ + bin/ copied (trd, basic,
  zx_control; sjasmplus, ZEsarUX), .claude rules, Makefile.
- Full game implemented in Z80 (~4400 lines, 7.9K code): title menu,
  map preview, human turn (cursor/select/attack/deselect/end),
  AI turns, battle animation with dice tumble + AY clicks, supply,
  hotseat 2-human mode, win / game-over banners, AY soundtrack + SFX.
- Resources as editable text: font8.txt (text-bitmap font),
  tune.txt (tracker score), boot.bas.txt (BASIC loader).
- Build: `make build` -> bootable build/dicewars.trd; `make run` boots
  it in the bundled ZEsarUX.
- Closed-loop testing: tmp/zxstate.py reads game state from emulated
  RAM via the sjasmplus symbol table; tmp/autoplay.py / tmp/fullgame.py
  play the game via ZRCP key injection. A complete automated game was
  played to its end screen.

## Bugs found and fixed during bring-up

- nb_add clobbered BC -> corrupted a_join + missing area centers.
- pr_slot_col clobbered A before print_num / fill_attr -> player row
  showed slot offsets, colour cells lost their colour.
- cursor_xor clobbered C -> cursor never moved (direction bits lost).
- zx_control 1-frame key pulses race the game's once-per-frame scan ->
  added `press --held N`.
- Map generation took 6.3s; frontier list (fr_list) for percolation's
  min-search cut it to 2.3s.

## Possible future work

- Kempston/Sinclair joystick support.
- History replay (the remake has it; dropped here for scope).
- A second tune, title-screen attract mode.
- 128K banking for more/larger content (all-RAM currently fits in 48K).
