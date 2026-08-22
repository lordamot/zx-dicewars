; Global constants: map geometry, player palette, screen layout.

; --- map grid --------------------------------------------------------------
; The map is a 32x20 grid of 8x8-pixel character cells, one attribute cell
; per map cell (top 20 of the Spectrum's 24 character rows). One byte of
; cel[] per cell holds the area number, 0 = sea. This is the ZX answer to
; the original's 28x32 hex grid: squares instead of hexes, so every map
; cell owns its own colour attribute and player colours can never clash.
XMAX        EQU 32
YMAX        EQU 20
CEL_MAX     EQU XMAX*YMAX          ; 640

AREA_MAX    EQU 32                 ; area numbers 1..31, 0 = sea
PMAX_HARD   EQU 8                  ; up to 8 players
PUT_DICE    EQU 3                  ; average starting dice per area
STOCK_MAX   EQU 64                 ; reinforcement stock cap (as original)
DICE_MAX    EQU 8                  ; dice per area cap

; --- screen ----------------------------------------------------------------
SCREEN      EQU #4000
ATTRS       EQU #5800
ROW_MSG     EQU 20                 ; HUD: message line
ROW_HUD1    EQU 21                 ; HUD: player row / battle strip top
ROW_HUD2    EQU 22
ROW_HUD3    EQU 23

; --- attribute bytes -------------------------------------------------------
; attr = FLASH.BRIGHT.PAPER(3).INK(3)
A_BLACK     EQU %00000000
A_HUDTEXT   EQU %00000111          ; white on black (HUD text)
A_HUDDIM    EQU %00000001          ; blue-on-black (dim decoration)
A_TITLE     EQU %01000111          ; bright white on black
A_SELECT    EQU %01000110          ; bright yellow on black (menu highlight)
FLASH_BIT   EQU %10000000
