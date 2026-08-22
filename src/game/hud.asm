; HUD: the message line (row 20) and the player row (rows 21..23).
;
; Player row layout: one 4-column slot per seat in turn order (jun[]),
; up to 8 slots filling the full 32 columns:
;   row 21:  "P1"/"P2" tag over the human seats (hotseat marker)
;   row 22:  two cells in the player's colour showing his largest
;            connected group (= reinforcements he will get), then his
;            stock (unplaced reinforcements) in dim text, if any
; The current player's colour cells FLASH.

; clear the message row (pixels + white-on-black attributes)
clear_msg:
    ld b,ROW_MSG
    call clear_pixrow
    ld b,ROW_MSG
    ld c,0
    ld d,32
    ld a,A_HUDTEXT
    jp fill_attr

; print 0-terminated string HL on the message row, from column 0
msg_print:
    push hl
    call clear_msg
    pop hl
    ld b,ROW_MSG
    ld c,0
    jp print_str

; like msg_print, but with a coloured "P<n+1>" tag first: A = player number
msg_player:
    push hl
    push af
    call clear_msg
    pop af
    push af
    ; two colour cells with the player tag
    ld e,a
    ld d,0
    ld hl,player_attr
    add hl,de
    ld a,(hl)
    ld b,ROW_MSG
    ld c,0
    ld d,2
    call fill_attr
    ld a,CH_PLAYER                 ; 'И' - "И1".."И8" player tags
    ld b,ROW_MSG
    ld c,0
    call print_char
    pop af
    add a,'1'                      ; player number 0.. -> "1".."8"
    ld c,1
    call print_char
    ld c,3
    pop hl
    jp print_str

; clear HUD rows 21..23
clear_player_row:
    ld b,ROW_HUD1
    call clear_pixrow
    ld b,ROW_HUD2
    call clear_pixrow
    ld b,ROW_HUD3
    call clear_pixrow
    ld b,ROW_HUD1
    ld c,0
    ld d,32
    ld a,A_HUDTEXT
    call fill_attr
    ld b,ROW_HUD2
    ld c,0
    ld d,32
    ld a,A_HUDTEXT
    call fill_attr
    ld b,ROW_HUD3
    ld c,0
    ld d,32
    ld a,A_HUDTEXT
    jp fill_attr

pr_slot:  DB 0                     ; jun index being drawn
pr_pn:    DB 0                     ; its player number

; draw the player status row for all living players
draw_player_row:
    call clear_player_row
    xor a
    ld (pr_slot),a
.slot:
    ld a,(pmax)
    ld e,a
    ld a,(pr_slot)
    cp e
    ret nc                         ; all seats done
    ; p = jun[slot]
    ld e,a
    ld d,0
    ld hl,jun
    add hl,de
    ld a,(hl)
    ld (pr_pn),a
    ; alive?
    ld e,a
    ld hl,p_area_tc
    add hl,de
    ld a,(hl)
    or a
    jr z,.next                     ; eliminated: leave the slot empty
    ; colour cells at row 22, col slot*4 (+FLASH for the current player)
    call pr_slot_col               ; C = slot*4 (careful: destroys A)
    ld b,ROW_HUD2
    ld a,(pr_pn)
    ld e,a
    ld d,0
    ld hl,player_attr
    add hl,de
    ld a,(hl)
    ld e,a
    ld a,(pr_slot)
    ld hl,ban
    cp (hl)
    ld a,e
    jr nz,.noflash
    or FLASH_BIT
.noflash:
    ld d,2
    call fill_attr
    ; largest-group count on the colour cells
    call pr_slot_col
    ld b,ROW_HUD2
    ld a,(pr_pn)
    ld e,a
    ld d,0
    ld hl,p_area_tc
    add hl,de
    ld a,(hl)
    call print_num
    ; stock (if any) at row 23
    ld a,(pr_pn)
    ld e,a
    ld d,0
    ld hl,p_stock
    add hl,de
    ld a,(hl)
    or a
    jr z,.nostock
    ld e,a
    call pr_slot_col
    ld b,ROW_HUD3
    ld a,e
    call print_num
.nostock:
    ; "P1"/"P2" tag over human seats
    ld a,(humans)
    ld e,a
    ld a,(pr_pn)
    cp e
    jr nc,.next
    call pr_slot_col
    ld b,ROW_HUD1
    ld a,CH_PLAYER
    call print_char
    inc c
    ld a,(pr_pn)
    add a,'1'
    call print_char
.next:
    ld a,(pr_slot)
    inc a
    ld (pr_slot),a
    jp .slot

; -> C = 4 * pr_slot (the slot's left column); destroys A
pr_slot_col:
    ld a,(pr_slot)
    add a,a
    add a,a
    ld c,a
    ret
