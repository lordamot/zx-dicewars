; Game state. Everything here lives inside the loaded CODE block so it has
; defined initial values; the big scratch buffers are in bss.asm (after the
; end of the saved binary - they are (re)initialised at runtime).

; --- player palette --------------------------------------------------------
; One attribute byte per player, PAPER = the player's colour, INK = the
; colour borders and dice digits are drawn in. Mirrors the browser remake's
; palette order (purple, green, dark green, pink->white, orange->olive,
; cyan, yellow, red) within the Spectrum's fixed 15 colours. Players 0 and
; 1 (the human seats) get the remake's signature purple and green.
player_attr:
    DB %01011000                   ; P0 bright magenta ("purple")
    DB %01100000                   ; P1 bright green
    DB %00100111                   ; P2 green, white ink ("dark green")
    DB %01111000                   ; P3 bright white ("pink")
    DB %00110000                   ; P4 yellow ("orange" -> olive)
    DB %01101000                   ; P5 bright cyan
    DB %01110000                   ; P6 bright yellow
    DB %01010000                   ; P7 bright red

; --- settings chosen on the title screen -----------------------------------
pmax:       DB 7                   ; number of players 2..8
humans:     DB 1                   ; human players 1..2 (player numbers 0..humans-1)
music_on:   DB 1

; --- per-game state --------------------------------------------------------
jun:        DB 0,1,2,3,4,5,6,7     ; turn order (shuffled at game start)
ban:        DB 0                   ; index into jun[]: current player
area_from:  DB 0
area_to:    DB 0

cursor_row: DB 10                  ; map cursor, persists between turns
cursor_col: DB 16

; --- per-player data (indexed by player number 0..7) -----------------------
p_area_tc:  DS 8                   ; largest connected group (0 = eliminated)
p_dice_jun: DS 8                   ; rank by total dice (AI)
p_stock:    DS 8                   ; reinforcements not yet placed
p_dice_c:   DS 16                  ; total dice, words (AI)

; --- per-area data (indexed by area number 0..31) --------------------------
a_size:     DS AREA_MAX            ; cells in area, 0 = area does not exist
a_arm:      DS AREA_MAX            ; owning player
a_dice:     DS AREA_MAX            ; dice count 1..8
a_crow:     DS AREA_MAX            ; center cell (dice digit position)
a_ccol:     DS AREA_MAX
a_left:     DS AREA_MAX            ; bbox / center scratch used during
a_right:    DS AREA_MAX            ; map generation
a_top:      DS AREA_MAX
a_bottom:   DS AREA_MAX
a_cx:       DS AREA_MAX
a_cy:       DS AREA_MAX
a_lenmin:   DS AREA_MAX

; --- misc ------------------------------------------------------------------
rnd_state:  DW #C0DE               ; PRNG state, never zero
frames:     DB 0                   ; incremented by the IM2 handler
