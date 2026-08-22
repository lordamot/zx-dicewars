; Screen rendering.
;
; The map occupies character rows 0..19 (32x20 cells); the 640 map cells
; map 1:1 onto the first 640 attribute bytes at #5800, so cell index ==
; attribute offset. A cell is drawn as: PAPER = owning player's colour,
; border lines in INK on the edges where the neighbouring cell belongs to
; a different area (or to the sea, or is off-map), and - in the area's
; center cell - a bold dice-count digit, OR-ed over the borders.

; --- address calculators ---------------------------------------------------

; B=char row 0..23, C=col 0..31 -> HL = screen address of the top scanline.
; Destroys A only.
pix_addr:
    ld a,b
    and #18
    or #40
    ld h,a
    ld a,b
    and 7
    rrca
    rrca
    rrca                           ; (row&7)<<5
    or c
    ld l,a
    ret

; B=char row, C=col -> HL = attribute address. Destroys A only.
attr_addr:
    ld a,b
    rrca
    rrca
    rrca
    and 3
    or #58
    ld h,a
    ld a,b
    and 7
    rrca
    rrca
    rrca
    or c
    ld l,a
    ret

; --- whole-screen / row clears --------------------------------------------

; clear all pixels and set all attributes to black
cls:
    ld hl,SCREEN
    ld bc,6144+768
    xor a
    call mem_fill
    ret

; HL=start, BC=len (>=2), A=fill value. Preserves DE.
mem_fill:
    ld (hl),a
    push de
    ld d,h
    ld e,l
    inc de
    dec bc
    ldir
    pop de
    ret

; clear the pixels of char row B (all 32 columns)
clear_pixrow:
    ld c,0
    call pix_addr
    ld d,8
.line:
    push hl
    xor a
    ld b,32
.col:
    ld (hl),a
    inc l
    djnz .col
    pop hl
    inc h
    dec d
    jr nz,.line
    ret

; B=row, C=col, D=len, A=attr: fill D attribute cells
fill_attr:
    ld e,a
    call attr_addr
    ld a,e
.fill:
    ld (hl),a
    inc hl
    dec d
    jr nz,.fill
    ret

; --- text ------------------------------------------------------------------

; A=char (32..95), B=row, C=col. Preserves BC.
print_char:
    push bc
    sub 32
    ld l,a
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    ld de,font8
    add hl,de
    ex de,hl                       ; DE = glyph
    call pix_addr
    ld b,8
.row:
    ld a,(de)
    ld (hl),a
    inc de
    inc h
    djnz .row
    pop bc
    ret

; HL=0-terminated string, B=row, C=col
print_str:
.next:
    ld a,(hl)
    or a
    ret z
    push hl
    call print_char
    pop hl
    inc hl
    inc c
    jr .next

; A=value 0..255 printed decimal at B,C without leading zeros; C advances
print_num:
    ld d,0                         ; bit0: "digit already printed"
    ld e,100
    call pn_digit
    ld e,10
    call pn_digit
    add a,'0'
    call print_char
    inc c
    ret
pn_digit:
    ld h,'0'-1
.sub:
    inc h
    sub e
    jr nc,.sub
    add a,e
    push af                        ; remainder
    ld a,h
    cp '0'
    jr nz,.show
    bit 0,d
    jr z,.skip
.show:
    set 0,d
    push de
    ld a,h
    call print_char
    pop de
    inc c
.skip:
    pop af
    ret

; --- double-size text (title / endgame banners) ----------------------------

; HL=string, B=top row, C=left col; each char covers 2x2 cells
print_str2x:
.next:
    ld a,(hl)
    or a
    ret z
    push hl
    call bigchar
    pop hl
    inc hl
    inc c
    inc c
    jr .next

; A=char, B=top row, C=left col; preserves BC
bigchar:
    push bc
    sub 32
    ld l,a
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    ld bc,font8
    add hl,bc
    ; expand the 8 glyph rows into 32 bytes (16 lines x 2 bytes)
    ld a,8
    ld (tmp8),a
    ld ix,bigbuf
.row:
    ld a,(hl)
    inc hl
    push hl
    call expand_byte               ; A -> DE, bits doubled
    ld (ix+0),d
    ld (ix+1),e
    ld (ix+2),d
    ld (ix+3),e
    ld bc,4
    add ix,bc
    pop hl
    ld a,(tmp8)
    dec a
    ld (tmp8),a
    jr nz,.row
    pop bc
    ; blit: top half-cell, then the one below
    push bc
    call pix_addr
    ld de,bigbuf
    call blit_half
    pop bc
    inc b
    push bc
    call pix_addr
    ld de,bigbuf+16
    call blit_half
    pop bc
    dec b
    ret

; A -> DE with every bit doubled (#F0 -> #FF00)
expand_byte:
    ld de,0
    ld b,8
.bit:
    sla e
    rl d
    sla e
    rl d
    add a,a
    jr nc,.zero
    ld c,a
    ld a,e
    or 3
    ld e,a
    ld a,c
.zero:
    djnz .bit
    ret

; HL=screen addr of a cell's top scanline, DE=16 source bytes (8 lines x 2)
blit_half:
    ld b,8
.line:
    ld a,(de)
    ld (hl),a
    inc de
    inc l
    ld a,(de)
    ld (hl),a
    inc de
    dec l
    inc h
    djnz .line
    ret

tmp8:   DB 0

; --- map cells -------------------------------------------------------------

; redraw the whole map (rows 0..YMAX-1)
draw_map:
    ld b,0
.row:
    ld c,0
.col:
    push bc
    call draw_cell
    pop bc
    inc c
    ld a,c
    cp XMAX
    jr nz,.col
    inc b
    ld a,b
    cp YMAX
    jr nz,.row
    ret

dc_area: DB 0

; draw one map cell. B=row 0..YMAX-1, C=col. Preserves BC.
draw_cell:
    ; HL = cel + row*32 + col
    ld l,b
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    ld a,l
    or c
    ld l,a
    ld de,cel
    add hl,de
    ld a,(hl)
    ld (dc_area),a
    or a
    jr nz,.land

    ; sea: black cell, no pixels
    call pix_addr
    xor a
    DUP 7
    ld (hl),a
    inc h
    EDUP
    ld (hl),a
    call attr_addr
    ld (hl),A_BLACK
    ret

.land:
    ; start with an empty 8-byte pixel buffer
    push hl
    ld hl,cellbuf
    xor a
    DUP 7
    ld (hl),a
    inc hl
    EDUP
    ld (hl),a
    pop hl

    ; top edge: map edge or different area above
    ld a,b
    or a
    jr z,.top_border
    push hl
    ld de,-32
    add hl,de
    ld a,(dc_area)
    cp (hl)
    pop hl
    jr z,.no_top
.top_border:
    ld a,#FF
    ld (cellbuf),a
.no_top:
    ; bottom edge
    ld a,b
    cp YMAX-1
    jr z,.bot_border
    push hl
    ld de,32
    add hl,de
    ld a,(dc_area)
    cp (hl)
    pop hl
    jr z,.no_bot
.bot_border:
    ld a,#FF
    ld (cellbuf+7),a
.no_bot:
    ; left edge
    ld a,c
    or a
    jr z,.left_border
    push hl
    dec hl
    ld a,(dc_area)
    cp (hl)
    pop hl
    jr z,.no_left
.left_border:
    push hl
    ld hl,cellbuf
    DUP 8
    ld a,(hl)
    or #80
    ld (hl),a
    inc hl
    EDUP
    pop hl
.no_left:
    ; right edge
    ld a,c
    cp XMAX-1
    jr z,.right_border
    push hl
    inc hl
    ld a,(dc_area)
    cp (hl)
    pop hl
    jr z,.no_right
.right_border:
    push hl
    ld hl,cellbuf
    DUP 8
    ld a,(hl)
    or #01
    ld (hl),a
    inc hl
    EDUP
    pop hl
.no_right:

    ; dice digit if this is the area's center cell
    ld a,(dc_area)
    ld e,a
    ld d,0
    ld hl,a_crow
    add hl,de
    ld a,(hl)
    cp b
    jr nz,.no_digit
    ld hl,a_ccol
    add hl,de
    ld a,(hl)
    cp c
    jr nz,.no_digit
    ld hl,a_dice
    add hl,de
    ld a,(hl)                      ; 1..8
    dec a
    add a,a
    add a,a
    add a,a
    ld l,a
    ld h,0
    ld de,dicefont
    add hl,de
    ld de,cellbuf
    DUP 8
    ld a,(de)
    or (hl)
    ld (de),a
    inc hl
    inc de
    EDUP
.no_digit:

    ; blit pixels and set the attribute
    call pix_addr
    ld de,cellbuf
    DUP 7
    ld a,(de)
    ld (hl),a
    inc de
    inc h
    EDUP
    ld a,(de)
    ld (hl),a
    call attr_addr
    ld a,(dc_area)
    ld e,a
    ld d,0
    push hl
    ld hl,a_arm
    add hl,de
    ld e,(hl)
    ld hl,player_attr
    add hl,de
    ld a,(hl)
    pop hl
    ld (hl),a
    ret

; redraw the center cell of area A (used when its dice count changes)
draw_area_center:
    ld e,a
    ld d,0
    ld hl,a_crow
    add hl,de
    ld b,(hl)
    ld hl,a_ccol
    add hl,de
    ld c,(hl)
    jp draw_cell

; --- area highlight (FLASH attribute) --------------------------------------

; set FLASH on every cell of area A
area_flash_on:
    ld c,a
    ld hl,cel
    ld de,ATTRS
    exx
    ld bc,CEL_MAX
    exx
.loop:
    ld a,(hl)
    cp c
    jr nz,.skip
    ld a,(de)
    or FLASH_BIT
    ld (de),a
.skip:
    inc hl
    inc de
    exx
    dec bc
    ld a,b
    or c
    exx
    jr nz,.loop
    ret

; clear FLASH on every cell of area A
area_flash_off:
    ld c,a
    ld hl,cel
    ld de,ATTRS
    exx
    ld bc,CEL_MAX
    exx
.loop:
    ld a,(hl)
    cp c
    jr nz,.skip
    ld a,(de)
    and ~FLASH_BIT
    ld (de),a
.skip:
    inc hl
    inc de
    exx
    dec bc
    ld a,b
    or c
    exx
    jr nz,.loop
    ret

; --- full-screen pictures --------------------------------------------------

; copy a 6912-byte screen (pixels + attributes) to the display
show_scr:
    ld de,SCREEN
    ld bc,6912
    ldir
    ret

; --- cursor ----------------------------------------------------------------

; XOR the cursor frame into the cell at (cursor_row, cursor_col);
; calling it twice removes it again.
cursor_xor:
    ld a,(cursor_row)
    ld b,a
    ld a,(cursor_col)
    ld c,a
    call pix_addr
    ld de,cursor_pat
    DUP 7
    ld a,(de)
    xor (hl)
    ld (hl),a
    inc de
    inc h
    EDUP
    ld a,(de)
    xor (hl)
    ld (hl),a
    ret

cursor_pat:
    DB #FF,#FF,#C3,#C3,#C3,#C3,#FF,#FF
