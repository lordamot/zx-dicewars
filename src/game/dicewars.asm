; DiceWars ZX - top level. Assemble from the repository root:
;   bin/sjasmplus/sjasmplus src/game/dicewars.asm
; (tools/build_dicewars.py does this, after generating build/font8.asm
; and build/tune.asm from their editable sources.)
;
; The whole game is one CODE block loaded at #6000 by the BASIC loader
; (src/basic/boot.bas.txt); the scratch buffers after code_end and the
; IM2 vector page at #FE00 live in RAM beyond the loaded file.

    DEVICE ZXSPECTRUM48

    ORG #6000
code_start:

    INCLUDE "const.asm"
    INCLUDE "main.asm"
    INCLUDE "vars.asm"
    INCLUDE "render.asm"
    INCLUDE "hud.asm"
    INCLUDE "input.asm"
    INCLUDE "random.asm"
    INCLUDE "map.asm"
    INCLUDE "ai.asm"
    INCLUDE "battle.asm"
    INCLUDE "music.asm"

    ; generated resources (font_gen.py / music_gen.py)
    INCLUDE "../../build/font8.asm"
    INCLUDE "../../build/tune.asm"

    ; the endgame photos (bmp2zx.py from src/res/screens/*.bmp); the
    ; loading screen is a separate disk file, not part of this block
scr_youwin:
    INCBIN "../../build/youwin.scr"
scr_gameover:
    INCBIN "../../build/gameover.scr"

code_end:

    INCLUDE "bss.asm"
bss_end:

    ; the work buffers must stay clear of the stack (#FDF0 down) and the
    ; IM2 vector page (#FE00)
    ASSERT bss_end < #F000

    SAVEBIN "build/dicewars.bin", code_start, code_end - code_start
