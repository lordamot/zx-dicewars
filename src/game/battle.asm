; Battles, reinforcements and end-of-game detection.
;
; A battle rolls all dice of both areas; the higher total wins, ties go
; to the defender (as the original). The animation shows the two hands of
; dice tumbling in the HUD strip: every die flickers through random faces
; and settles left-to-right on its final value with a click, then the
; side's total appears. On a win, all but one die move into the captured
; area; either way the attacker keeps a single die behind.

b_arm0:     DB 0                   ; attacker player
b_arm1:     DB 0                   ; defender player
bat_n:      DB 0                   ; attacker dice count
bat_m:      DB 0                   ; defender dice count
bat_suma:   DB 0
bat_sumd:   DB 0
an_count:   DB 0                   ; animation: dice in this hand
an_col:     DB 0                   ; leftmost column of the hand
an_faces:   DW 0                   ; final face values
an_f:       DB 0                   ; frame counter
an_i:       DB 0
game_state: DB 0                   ; 0 = playing, 1 = game over, 2 = won
winner:     DB 0

ATT_COL     EQU 2                  ; attacker hand starts here
DEF_COL_END EQU 30                 ; defender hand ends here (exclusive)

; fight area_from -> area_to, animate, apply the outcome, update both
; players' connectivity, redraw, and refresh game_state
battle:
    ; counts and owners
    ld a,(area_from)
    ld e,a
    ld d,0
    ld hl,a_dice
    add hl,de
    ld a,(hl)
    ld (bat_n),a
    ld hl,a_arm
    add hl,de
    ld a,(hl)
    ld (b_arm0),a
    ld a,(area_to)
    ld e,a
    ld hl,a_dice
    add hl,de
    ld a,(hl)
    ld (bat_m),a
    ld hl,a_arm
    add hl,de
    ld a,(hl)
    ld (b_arm1),a

    ; roll both hands up front (the animation only reveals the result)
    ld hl,bat_att
    ld a,(bat_n)
    call roll_hand
    ld (bat_suma),a
    ld hl,bat_def
    ld a,(bat_m)
    call roll_hand
    ld (bat_sumd),a

    ; highlight both areas
    ld a,(area_from)
    call area_flash_on
    ld a,(area_to)
    call area_flash_on

    ; battle strip
    call clear_player_row
    ld hl,s_battle
    call msg_print
    ; attacker dice cells in his colour
    ld a,(b_arm0)
    call player_attr_of
    ld b,ROW_HUD2
    ld c,ATT_COL
    ld e,a
    ld a,(bat_n)
    ld d,a
    ld a,e
    call fill_attr
    ; defender dice cells
    ld a,(b_arm1)
    call player_attr_of
    ld e,a
    ld a,(bat_m)
    ld d,a
    ld a,DEF_COL_END
    sub d
    ld c,a
    ld b,ROW_HUD2
    ld a,e
    call fill_attr

    ; attacker hand tumbles first, then the defender's
    ld a,(bat_n)
    ld (an_count),a
    ld a,ATT_COL
    ld (an_col),a
    ld hl,bat_att
    ld (an_faces),hl
    call bat_anim
    ld a,(bat_suma)
    ld b,ROW_HUD3
    ld c,ATT_COL
    call print_num

    ld a,(bat_m)
    ld (an_count),a
    ld a,DEF_COL_END
    ld e,a
    ld a,(bat_m)
    ld d,a
    ld a,e
    sub d
    ld (an_col),a
    ld hl,bat_def
    ld (an_faces),hl
    call bat_anim
    ld a,(bat_sumd)
    ld b,ROW_HUD3
    ld c,DEF_COL_END-4
    call print_num

    ld b,20
    call wait_frames

    ; --- resolve --------------------------------------------------------
    ld a,(bat_sumd)
    ld e,a
    ld a,(bat_suma)
    cp e
    jr z,.fail
    jr c,.fail
    ; captured: defender area gets attacker's dice minus one
    ld a,(area_from)
    ld e,a
    ld d,0
    ld hl,a_dice
    add hl,de
    ld a,(hl)
    dec a
    ld (hl),1
    push af
    ld a,(area_to)
    ld e,a
    ld hl,a_dice
    add hl,de
    pop af
    ld (hl),a
    ld a,(area_to)
    ld e,a
    ld hl,a_arm
    add hl,de
    ld a,(b_arm0)
    ld (hl),a
    ld hl,s_captured
    call msg_print
    ld a,2
    call sfx_play
    jr .after
.fail:
    ; failed: the attacker is left with a single die
    ld a,(area_from)
    ld e,a
    ld d,0
    ld hl,a_dice
    add hl,de
    ld (hl),1
    ld hl,s_failed
    call msg_print
    ld a,3
    call sfx_play
.after:
    ld b,20
    call wait_frames
    ; connectivity of both involved players changed
    ld a,(b_arm0)
    call set_area_tc
    ld a,(b_arm1)
    call set_area_tc
    ; full redraw also clears the FLASH highlights
    call draw_map
    call draw_player_row
    call clear_msg
    jp check_end

; roll A dice into buffer HL -> A = their sum
roll_hand:
    ld b,a
    ld c,0
.die:
    push bc
    push hl
    call rand_d6
    pop hl
    pop bc
    ld (hl),a
    inc hl
    add a,c
    ld c,a
    djnz .die
    ld a,c
    ret

; A = player -> A = his attribute byte
player_attr_of:
    ld e,a
    ld d,0
    ld hl,player_attr
    add hl,de
    ld a,(hl)
    ret

; animate one hand: an_count dice at an_col, faces at (an_faces).
; die i settles at frame 16+3i with a click.
bat_anim:
    xor a
    ld (an_f),a
.frame:
    call wait_frame
    xor a
    ld (an_i),a
.die:
    ld a,(an_i)
    ld b,a
    add a,a
    add a,b
    add a,16                       ; settle frame for this die
    ld b,a
    ld a,(an_f)
    cp b
    jr c,.tumble
    jr z,.settle
    jr .dnext                      ; already settled
.tumble:
    call rand_d6
    jr .show
.settle:
    ld a,(an_i)
    ld e,a
    ld d,0
    ld hl,(an_faces)
    add hl,de
    ld a,(hl)
    push af
    ld a,1
    call sfx_play
    pop af
.show:
    add a,'0'
    ld e,a
    ld a,(an_col)
    ld c,a
    ld a,(an_i)
    add a,c
    ld c,a
    ld b,ROW_HUD2
    ld a,e
    call print_char
.dnext:
    ld a,(an_i)
    inc a
    ld (an_i),a
    ld e,a
    ld a,(an_count)
    cp e
    jr nz,.die
    ; run until every die has settled (16 + 3*count + 4 frames)
    ld a,(an_f)
    inc a
    ld (an_f),a
    ld b,a
    ld a,(an_count)
    ld c,a
    add a,a
    add a,c
    add a,16+4
    cp b
    jr nc,.frame
    ret

; --- reinforcements at end of turn -----------------------------------------

; current player receives dice equal to his largest connected group
; (capped stock of 64), spread one per tick over random non-full areas
supply:
    call get_cur_pn
    push af
    call set_area_tc
    pop af
    ld e,a
    ld d,0
    ld hl,p_area_tc
    add hl,de
    ld b,(hl)
    ld hl,p_stock
    add hl,de
    ld a,(hl)
    add a,b
    cp STOCK_MAX+1
    jr c,.cap
    ld a,STOCK_MAX
.cap:
    ld (hl),a
    call get_cur_pn
    ld hl,s_supply
    call msg_player
    call draw_player_row
.place:
    call get_cur_pn
    ld e,a
    ld d,0
    ld hl,p_stock
    add hl,de
    ld a,(hl)
    or a
    ret z                          ; stock all placed
    call get_cur_pn
    ld (bl_pn),a
    call build_supply_list
    or a
    ret z                          ; every area is full: excess stays stocked
    call rand_n
    ld e,a
    ld d,0
    ld hl,alist
    add hl,de
    ld a,(hl)
    push af
    ld e,a
    ld hl,a_dice
    add hl,de
    inc (hl)
    call get_cur_pn
    ld e,a
    ld d,0
    ld hl,p_stock
    add hl,de
    dec (hl)
    pop af
    call draw_area_center
    ld a,6
    call sfx_play
    ld b,3
    call wait_frames
    jr .place

; --- end of game -----------------------------------------------------------

; refresh game_state: 1 when no human is left alive, 2 (+winner) when a
; single player owns everything that is left
check_end:
    ld a,(humans)
    ld b,a
    ld hl,p_area_tc
    ld c,0
.hum:
    ld a,(hl)
    or a
    jr z,.hn
    inc c
.hn:
    inc hl
    djnz .hum
    ld a,c
    or a
    jr nz,.alive
    ld a,1
    ld (game_state),a
    ret
.alive:
    ld a,(pmax)
    ld b,a
    ld hl,p_area_tc
    ld c,0                         ; survivors
    ld d,0                         ; last survivor seen
    ld e,0                         ; player number being checked
.pl:
    ld a,(hl)
    or a
    jr z,.pn
    inc c
    ld d,e
.pn:
    inc hl
    inc e
    djnz .pl
    ld a,c
    cp 1
    ret nz
    ld a,2
    ld (game_state),a
    ld a,d
    ld (winner),a
    ret
