; The computer opponent - a straight port of com_thinking() from the
; browser remake (js/game.js in ../dicewars):
;
;   - collect every attack from an own 2+ dice area onto an adjacent enemy
;     area that does not have MORE dice than ours;
;   - an EQUAL-dice attack is only taken sometimes: always if we or the
;     defender lead the dice ranking, otherwise with ~90% probability;
;   - if some player holds more than 2/5 of all dice on the board (a
;     runaway leader), only fights involving that leader are considered;
;   - pick one of the collected attacks uniformly at random.
;
; -> carry set = no acceptable attack (end the turn),
;    otherwise area_from / area_to are set.

ai_sum:   DW 0
ai_top:   DB 0                     ; runaway leader, #FF = none
ai_lc:    DB 0                     ; number of collected attacks
ai_i:     DB 0
ai_j:     DB 0
ai_pn:    DB 0
ai_di:    DB 0                     ; attacker dice
ai_swap:  DB 0

com_thinking:
    ; --- per-player dice totals -----------------------------------------
    ld hl,p_dice_c
    ld bc,16
    xor a
    call mem_fill
    ld hl,0
    ld (ai_sum),hl
    ld e,1
    ld b,AREA_MAX-1
.tot:
    ld d,0
    ld hl,a_size
    add hl,de
    ld a,(hl)
    or a
    jr z,.tn
    ld hl,a_dice
    add hl,de
    ld a,(hl)
    push de
    ld hl,a_arm
    add hl,de
    ld e,(hl)
    sla e                          ; word index
    ld d,0
    ld hl,p_dice_c
    add hl,de
    push bc
    ld c,a
    ld b,0
    ld a,(hl)
    add a,c
    ld (hl),a
    inc hl
    ld a,(hl)
    adc a,0
    ld (hl),a
    ld hl,(ai_sum)
    add hl,bc
    ld (ai_sum),hl
    pop bc
    pop de
.tn:
    inc e
    djnz .tot

    ; --- rank players by total dice (the original's quirky jun-swap sort)
    ld hl,p_dice_jun
    ld b,8
    xor a
.rk:
    ld (hl),a
    inc hl
    inc a
    djnz .rk
    xor a
    ld (ai_i),a
.ri:
    ld a,(ai_i)
    inc a
    ld (ai_j),a
.rj:
    ; dice_c[i] < dice_c[j] ?
    ld a,(ai_i)
    call dice_c_word               ; -> HL
    push hl
    ld a,(ai_j)
    call dice_c_word
    ex de,hl                       ; DE = dice_c[j]
    pop hl
    or a
    sbc hl,de
    jr nc,.noswap
    ; swap dice_jun[i] <-> dice_jun[j]
    ld a,(ai_i)
    ld e,a
    ld d,0
    ld hl,p_dice_jun
    add hl,de
    ld a,(hl)
    ld (ai_swap),a
    push hl
    ld a,(ai_j)
    ld e,a
    ld hl,p_dice_jun
    add hl,de
    ld a,(hl)
    ld c,a
    ld a,(ai_swap)
    ld (hl),a
    pop hl
    ld (hl),c
.noswap:
    ld a,(ai_j)
    inc a
    ld (ai_j),a
    cp 8
    jr c,.rj
    ld a,(ai_i)
    inc a
    ld (ai_i),a
    cp 7
    jr c,.ri

    ; --- runaway leader: 5 * dice_c[i] > 2 * sum ------------------------
    ld a,#FF
    ld (ai_top),a
    xor a
    ld (ai_i),a
.top:
    ld a,(ai_i)
    call dice_c_word               ; HL = dice_c[i]
    ld d,h
    ld e,l
    add hl,hl
    add hl,hl
    add hl,de                      ; *5
    ex de,hl
    ld hl,(ai_sum)
    add hl,hl                      ; *2
    ex de,hl
    ; HL = 5*dice, DE = 2*sum: leader if HL > DE
    or a
    sbc hl,de
    jr z,.tnx
    jr c,.tnx
    ld a,(ai_i)
    ld (ai_top),a
.tnx:
    ld a,(ai_i)
    inc a
    ld (ai_i),a
    cp 8
    jr c,.top

    ; --- collect acceptable attacks -------------------------------------
    xor a
    ld (ai_lc),a
    call get_cur_pn
    ld (ai_pn),a
    ld a,1
    ld (ai_i),a
.iloop:
    ; attacker: own, 2+ dice
    ld a,(ai_i)
    ld e,a
    ld d,0
    ld hl,a_size
    add hl,de
    ld a,(hl)
    or a
    jp z,.inext
    ld hl,a_arm
    add hl,de
    ld a,(ai_pn)
    cp (hl)
    jp nz,.inext
    ld hl,a_dice
    add hl,de
    ld a,(hl)
    ld (ai_di),a
    cp 2
    jp c,.inext
    ld a,1
    ld (ai_j),a
.jloop:
    ; defender: existing, enemy, adjacent
    ld a,(ai_j)
    ld e,a
    ld d,0
    ld hl,a_size
    add hl,de
    ld a,(hl)
    or a
    jp z,.jnext
    ld hl,a_arm
    add hl,de
    ld a,(ai_pn)
    cp (hl)
    jp z,.jnext
    ld c,(hl)                      ; C = defender's owner
    ld a,(ai_i)
    ld l,a
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,de                      ; + j (D is 0)
    ld de,a_join
    add hl,de
    ld a,(hl)
    or a
    jp z,.jnext
    ; runaway leader filter
    ld a,(ai_top)
    cp #FF
    jr z,.nofilter
    ld e,a
    ld a,(ai_pn)
    cp e
    jr z,.nofilter                 ; we are the leader
    ld a,c
    cp e
    jp nz,.jnext                   ; neither side is the leader
.nofilter:
    ; outnumbered?
    ld a,(ai_j)
    ld e,a
    ld d,0
    ld hl,a_dice
    add hl,de
    ld a,(ai_di)
    cp (hl)
    jp c,.jnext                    ; defender has more dice
    jr nz,.accept
    ; equal dice: attack if we lead, they lead, or with ~90% chance
    ld a,(ai_pn)
    ld e,a
    ld hl,p_dice_jun
    add hl,de
    ld a,(hl)
    or a
    jr z,.accept
    ld e,c
    ld hl,p_dice_jun
    add hl,de
    ld a,(hl)
    or a
    jr z,.accept
    call rand16
    ld a,l
    cp 26
    jp c,.jnext                    ; the ~10% "leave it" case
.accept:
    ld a,(ai_lc)
    cp 255
    jr nc,.jnext                   ; list full (cannot happen in practice)
    ld e,a
    inc a
    ld (ai_lc),a
    ld d,0
    ld hl,list_from
    add hl,de
    ld a,(ai_i)
    ld (hl),a
    ld hl,list_to
    add hl,de
    ld a,(ai_j)
    ld (hl),a
.jnext:
    ld a,(ai_j)
    inc a
    ld (ai_j),a
    cp AREA_MAX
    jp c,.jloop
.inext:
    ld a,(ai_i)
    inc a
    ld (ai_i),a
    cp AREA_MAX
    jp c,.iloop

    ; --- pick one at random ---------------------------------------------
    ld a,(ai_lc)
    or a
    jr nz,.pick
    scf
    ret
.pick:
    call rand_n
    ld e,a
    ld d,0
    ld hl,list_from
    add hl,de
    ld a,(hl)
    ld (area_from),a
    ld hl,list_to
    add hl,de
    ld a,(hl)
    ld (area_to),a
    or a
    ret

; A = player number -> HL = p_dice_c[A] (16-bit total)
dice_c_word:
    add a,a
    ld e,a
    ld d,0
    ld hl,p_dice_c
    add hl,de
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    ret

; -> A = current player number (jun[ban])
get_cur_pn:
    ld a,(ban)
    ld e,a
    ld d,0
    ld hl,jun
    add hl,de
    ld a,(hl)
    ret
