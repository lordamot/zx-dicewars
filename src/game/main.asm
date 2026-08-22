; Entry point and game flow: title -> map preview -> turns (human via the
; map cursor / computer via com_thinking) -> battles -> reinforcements ->
; win / game-over banner -> back to the title.

start:
    di
    ld sp,#FDF0                    ; below the IM2 vector at #FDFD
    xor a
    out (#FE),a                    ; black border
    call setup_im2
    call music_init
    call ay_mute
    ei
    call splash_hold               ; the loading screen is still on display
main_loop:
    call title_screen
    call preview
    call start_game
    call game_run
    jr main_loop

; --- per-frame housekeeping ------------------------------------------------

; one frame: wait for the interrupt, stir the PRNG with the refresh
; register (human timing = entropy), scan the keys, honour the music key
wait_frame:
    halt
    call rand_stir
    call key_scan
    ld a,(key3_new)
    and 1
    ret z
    ld a,(music_on)
    xor 1
    ld (music_on),a
    ret

; B frames of wait_frame
wait_frames:
    push bc
    call wait_frame
    pop bc
    djnz wait_frames
    ret

; --- title screen ----------------------------------------------------------

ink_cycle:
    DB 2,6,4,5,3,7                 ; red yellow green cyan magenta white

title_screen:
    call cls
    ld hl,ATTRS
    ld bc,768
    ld a,A_HUDTEXT
    call mem_fill                  ; readable text everywhere by default

    ; big logo, each letter in its own bright colour
    ld b,1
    ld c,7
    call draw_logo

    ; a row of dice showing the eight player colours
    ld e,0
.dice:
    push de
    ld a,e
    add a,a
    add a,a
    add a,a
    ld l,a
    ld h,0
    ld bc,dicefont
    add hl,bc
    ex de,hl                       ; DE = bold digit glyph
    pop bc                         ; C = player (was E)... restore below
    push bc
    ld a,12
    add a,c
    ld c,a
    ld b,5
    call pix_addr
    ld b,8
.glyph:
    ld a,(de)
    ld (hl),a
    inc de
    inc h
    djnz .glyph
    pop de                         ; E = player again
    push de
    ld a,e
    call player_attr_of
    pop de
    push de
    ld c,a
    ld a,12
    add a,e
    ld b,a
    ld a,c
    ld c,b
    ld b,5
    ld d,1
    call fill_attr
    pop de
    inc e
    ld a,e
    cp 8
    jr nz,.dice

    ; menu and credits
    ld hl,s_players
    ld b,8
    ld c,3
    call print_str
    ld hl,s_humans
    ld b,10
    ld c,3
    call print_str
    ld hl,s_music
    ld b,12
    ld c,3
    call print_str
    ld hl,s_start
    ld b,15
    ld c,5
    call print_str
    ld hl,s_keys
    ld b,17
    ld c,2
    call print_str
    ld hl,s_orig
    ld b,21
    ld c,2
    call print_str
    ld hl,s_remake
    ld b,22
    ld c,2
    call print_str
    ; highlight the start line
    ld b,15
    ld c,5
    ld d,22
    ld a,A_SELECT
    call fill_attr

.loop:
    call title_values
    call wait_frame
    ; number keys 2..8 set the player count
    ld a,(key2_new)
    ld d,a
    and %01111111
    jr z,.nodig
    ld e,2
.findbit:
    rra
    jr c,.setp
    inc e
    jr .findbit
.setp:
    ld a,e
    ld (pmax),a
.nodig:
    bit 7,d                        ; H: 1 <-> 2 humans
    jr z,.noh
    ld a,(humans)
    xor 3
    ld (humans),a
.noh:
    ld a,(key_new)
    and KB_FIRE
    jr z,.loop
    ret

; reprint the current menu values
title_values:
    ld a,(pmax)
    add a,'0'
    ld b,8
    ld c,23
    call print_char
    ld a,(humans)
    add a,'0'
    ld b,10
    ld c,23
    call print_char
    ld a,(music_on)
    or a
    ld hl,s_off
    jr z,.mus
    ld hl,s_on
.mus:
    ld b,12
    ld c,23
    jp print_str

; --- map preview: "play this map?" -----------------------------------------

preview:
    ld hl,s_generating
    call msg_print
    call clear_player_row
    call make_map
    call draw_map
    ld hl,s_playmap
    call msg_print
.loop:
    call wait_frame
    ld a,(key_new)
    ld d,a
    and KB_YES|KB_FIRE
    ret nz
    ld a,d
    and KB_NO
    jr z,.loop
    jr preview                     ; roll another map

; --- new game --------------------------------------------------------------

sg_i:   DB 0

start_game:
    ; turn order: identity, then shuffle the first pmax entries (as JS)
    ld hl,jun
    ld b,8
    xor a
.ident:
    ld (hl),a
    inc hl
    inc a
    djnz .ident
    xor a
    ld (sg_i),a
.shuffle:
    ld a,(pmax)
    call rand_n
    ld e,a
    ld d,0
    ld hl,jun
    add hl,de
    ld c,(hl)
    push hl
    ld a,(sg_i)
    ld e,a
    ld hl,jun
    add hl,de
    ld b,(hl)
    ld (hl),c
    pop hl
    ld (hl),b
    ld a,(sg_i)
    inc a
    ld (sg_i),a
    ld e,a
    ld a,(pmax)
    cp e
    jr nz,.shuffle
    xor a
    ld (ban),a
    ld (game_state),a
    ; reset all per-player state (p_area_tc..p_dice_c are contiguous)
    ld hl,p_area_tc
    ld bc,8+8+8+16
    xor a
    call mem_fill
    ; initial connectivity for everyone
    xor a
.tc:
    push af
    call set_area_tc
    pop af
    inc a
    cp 8
    jr c,.tc
    ret

; --- the turn loop ---------------------------------------------------------

game_run:
.turn:
    call draw_player_row
    call get_cur_pn
    ld hl,humans
    cp (hl)
    jr nc,.com
    call human_turn
    jr .check
.com:
    call com_turn
.check:
    ld a,(game_state)
    or a
    jr nz,.over
    call supply
    call next_player
    jr .turn
.over:
    cp 1
    jr z,.lost
    jp win_screen
.lost:
    jp game_over_screen

; advance ban to the next player still on the board; beep for humans
next_player:
    ld a,(pmax)
    ld b,a
.next:
    ld a,(ban)
    inc a
    ld hl,pmax
    cp (hl)
    jr c,.wrap
    xor a
.wrap:
    ld (ban),a
    call get_cur_pn
    ld e,a
    ld d,0
    ld hl,p_area_tc
    add hl,de
    ld a,(hl)
    or a
    jr nz,.found
    djnz .next
.found:
    call get_cur_pn
    ld hl,humans
    cp (hl)
    ret nc
    ld a,4                         ; your-turn beeps
    jp sfx_play

; --- human turn ------------------------------------------------------------

ht_sel: DB 0                       ; selected attacker area, #FF = none
ht_rep: DB 0                       ; cursor auto-repeat countdown

human_turn:
    ld a,#FF
    ld (ht_sel),a
    call msg_pick
    xor a
    ld (ht_rep),a
    call cursor_xor
.loop:
    call wait_frame
    call cursor_move
    ld a,(key_new)
    ld d,a
    and KB_FIRE
    jr nz,.fire
    ld a,d
    and KB_END
    jr z,.loop
    ; end of turn
    call cursor_xor
    ld a,(ht_sel)
    cp #FF
    ret z
    call area_flash_off
    ret
.fire:
    call cursor_area
    or a
    jr z,.loop                     ; sea
    ld c,a
    ld a,(ht_sel)
    cp #FF
    jr nz,.second
    ; picking the attacker: own area with 2+ dice
    push bc
    call get_cur_pn
    ld e,a
    pop bc
    push de
    ld a,c
    call area_arm_of
    pop de
    cp e
    jr nz,.loop
    ld a,c
    push bc
    call area_dice_of
    pop bc
    cp 2
    jr c,.loop
    ld a,c
    ld (ht_sel),a
    call area_flash_on
    ld a,1
    call sfx_play
    call msg_attack
    jr .loop
.second:
    ld b,a                         ; B = selected, C = clicked
    ld a,c
    cp b
    jr nz,.notsame
    ; clicking the selection again deselects it
    ld a,b
    call area_flash_off
    ld a,#FF
    ld (ht_sel),a
    ld a,1
    call sfx_play
    call msg_pick
    jr .loop
.notsame:
    ; must be an adjacent enemy area
    push bc
    call get_cur_pn
    ld e,a
    pop bc
    push de
    ld a,c
    call area_arm_of
    pop de
    cp e
    jr z,.loop                     ; own area
    push bc
    call areas_joined
    pop bc
    jp z,.loop                     ; not a neighbour
    ld a,b
    ld (area_from),a
    ld a,c
    ld (area_to),a
    call cursor_xor
    call battle
    ld a,#FF
    ld (ht_sel),a
    ld a,(game_state)
    or a
    ret nz
    call msg_pick
    call cursor_xor
    jp .loop

msg_pick:
    call get_cur_pn
    ld hl,s_pick
    jp msg_player
msg_attack:
    call get_cur_pn
    ld hl,s_attack
    jp msg_player

; move the cursor from the held direction keys, with auto-repeat
cursor_move:
    ld a,(key_state)
    and %00001111
    jr nz,.held
    xor a
    ld (ht_rep),a
    ret
.held:
    ld c,a
    ld a,(key_new)
    and %00001111
    jr z,.repeat
    ld c,a                         ; a fresh press moves at once
    ld a,10
    ld (ht_rep),a
    jr .move
.repeat:
    ld a,(ht_rep)
    or a
    jr z,.fire
    dec a
    ld (ht_rep),a
    ret nz
.fire:
    ld a,4
    ld (ht_rep),a
.move:
    push bc                        ; C = direction bits (cursor_xor eats C)
    call cursor_xor                ; off
    pop bc
    ld a,(cursor_row)
    ld d,a
    ld a,(cursor_col)
    ld e,a
    bit 0,c
    jr z,.ndu
    ld a,d
    or a
    jr z,.ndu
    dec d
.ndu:
    bit 1,c
    jr z,.ndd
    ld a,d
    cp YMAX-1
    jr nc,.ndd
    inc d
.ndd:
    bit 2,c
    jr z,.ndl
    ld a,e
    or a
    jr z,.ndl
    dec e
.ndl:
    bit 3,c
    jr z,.ndr
    ld a,e
    cp XMAX-1
    jr nc,.ndr
    inc e
.ndr:
    ld a,d
    ld (cursor_row),a
    ld a,e
    ld (cursor_col),a
    jp cursor_xor                  ; back on

; -> A = area number under the cursor (0 = sea)
cursor_area:
    ld a,(cursor_row)
    ld l,a
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    ld a,(cursor_col)
    or l
    ld l,a
    ld de,cel
    add hl,de
    ld a,(hl)
    ret

; A = area -> A = owner / dice count
area_arm_of:
    ld e,a
    ld d,0
    ld hl,a_arm
    add hl,de
    ld a,(hl)
    ret
area_dice_of:
    ld e,a
    ld d,0
    ld hl,a_dice
    add hl,de
    ld a,(hl)
    ret

; B,C = two area numbers -> NZ if adjacent
areas_joined:
    ld l,b
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    ld e,c
    ld d,0
    add hl,de
    ld de,a_join
    add hl,de
    ld a,(hl)
    or a
    ret

; --- computer turn ---------------------------------------------------------

com_turn:
    call get_cur_pn
    ld hl,s_thinking
    call msg_player
.loop:
    ld b,12
    call wait_frames
    call com_thinking
    ret c                          ; nothing worth attacking: end turn
    ld a,(area_from)
    call area_flash_on
    ld b,10
    call wait_frames
    ld a,(area_to)
    call area_flash_on
    ld b,10
    call wait_frames
    call battle
    ld a,(game_state)
    or a
    ret nz
    call get_cur_pn
    ld hl,s_thinking
    call msg_player
    jr .loop

; --- the photo screens (splash, win, game over) ----------------------------

ge_attr: DB 0
ge_row:  DB 0
ge_col:  DB 0
ge_len:  DB 0
sp_timer: DW 0

; the "DICE WARS" logo: double-size text at B=top row, C=left col, each
; letter in its own bright colour on black cells (shared by the title
; screen and the loading-screen splash)
draw_logo:
    ld a,b
    ld (ge_row),a
    ld a,c
    ld (ge_col),a
    push bc
    ld hl,s_logo
    call print_str2x
    pop bc
.lrow:
    ld a,(ge_col)
    ld c,a
    ld e,0                         ; cell index within the logo
.lcol:
    ld a,e
    srl a                          ; letter index
.mod6:
    cp 6
    jr c,.ink
    sub 6
    jr .mod6
.ink:
    push de
    ld e,a
    ld d,0
    ld hl,ink_cycle
    add hl,de
    ld a,(hl)
    or %01000000
    pop de
    push bc
    push de
    ld d,1
    call fill_attr
    pop de
    pop bc
    inc c
    inc e
    ld a,e
    cp 18
    jr nz,.lcol
    inc b
    ld a,(ge_row)
    add a,2
    cp b
    jr nz,.lrow
    ret

; double-size banner: text HL at B=top row, C=left col, attribute A
; (black paper + the caller's ink) over both banner cell rows
banner2x:
    ld (ge_attr),a
    ld a,b
    ld (ge_row),a
    ld a,c
    ld (ge_col),a
    push hl                        ; measure the text
    ld d,0
.len:
    ld a,(hl)
    or a
    jr z,.lend
    inc hl
    inc d
    jr .len
.lend:
    sla d                          ; cells = 2 * chars
    ld a,d
    ld (ge_len),a
    pop hl
    call print_str2x
    ld a,(ge_row)
    ld b,a
    ld a,(ge_col)
    ld c,a
    ld a,(ge_len)
    ld d,a
    ld a,(ge_attr)
    call fill_attr
    ld a,(ge_row)
    inc a
    ld b,a
    ld a,(ge_col)
    ld c,a
    ld a,(ge_len)
    ld d,a
    ld a,(ge_attr)
    jp fill_attr

; caption bar on the bottom row: "PRESS ANY KEY" over the photo
splash_prompt:
    ld b,23
    call clear_pixrow
    ld b,23
    ld c,0
    ld d,32
    ld a,A_HUDTEXT
    call fill_attr
    ld hl,s_anykey
    ld b,23
    ld c,9
    jp print_str

; hold the loading screen (already at #4000, put there by the BASIC
; loader): brand it with the logo and wait for a key or ~8 seconds
splash_hold:
    ld b,0
    ld c,0
    call draw_logo
    call splash_prompt
    ld hl,400
    ld (sp_timer),hl
.wait:
    call wait_frame
    ld a,(key_new)
    ld d,a
    ld a,(key2_new)
    or d
    ret nz
    ld hl,(sp_timer)
    dec hl
    ld (sp_timer),hl
    ld a,h
    or l
    jr nz,.wait
    ret

game_over_screen:
    ld a,3
    call sfx_play
    ld hl,scr_gameover
    call show_scr
    ld hl,s_gameover
    ld b,0
    ld c,7
    ld a,%01000010                 ; bright red ink
    call banner2x
    call splash_prompt
    jp wait_anykey

win_screen:
    ld a,5
    call sfx_play
    ld hl,scr_youwin
    call show_scr
    ; banner ink = the winner's colour
    ld a,(winner)
    call player_attr_of
    rra
    rra
    rra
    and 7
    or %01000000
    ld e,a
    ld a,(humans)
    cp 2
    jr nc,.named
    ld hl,s_youwin
    ld b,0
    ld c,9
    ld a,e
    call banner2x
    jr .prompt
.named:
    ld a,(winner)
    add a,'1'
    ld (s_pwins+7),a
    ld hl,s_pwins
    ld b,0
    ld c,3
    ld a,e
    call banner2x
.prompt:
    call splash_prompt
    jp wait_anykey

; short pause, then wait for a fresh keypress (with all keys released
; first); the caller draws its own prompt
wait_anykey:
    ld b,30
    call wait_frames
.release:
    call wait_frame
    ld a,(key_state)
    ld e,a
    ld a,(key2_state)
    or e
    jr nz,.release
.wait:
    call wait_frame
    ld a,(key_new)
    ld e,a
    ld a,(key2_new)
    or e
    jr z,.wait
    ret

; --- strings ---------------------------------------------------------------

s_logo:       DB "DICE WARS",0
s_players:    DB "PLAYERS (KEYS 2-8):",0
s_humans:     DB "HUMANS  (KEY H)   :",0
s_music:      DB "MUSIC   (KEY S)   :",0
s_on:         DB "ON ",0
s_off:        DB "OFF",0
s_start:      DB "ENTER OR SPACE - START",0
s_keys:       DB "QAOP-MOVE  SPACE-FIRE  E-END",0
s_orig:       DB "ORIGINAL (C) 2001 GAMEDESIGN",0
s_remake:     DB "ZX SPECTRUM 128 REMAKE, 2026",0
s_generating: DB "GENERATING MAP...",0
s_playmap:    DB "PLAY THIS MAP?  Y-YES  N-NO",0
s_pick:       DB "PICK YOUR AREA    E-END TURN",0
s_attack:     DB "NOW PICK AN ENEMY NEIGHBOUR",0
s_thinking:   DB "THINKING...",0
s_battle:     DB "BATTLE!",0
s_captured:   DB "AREA CAPTURED!",0
s_failed:     DB "ATTACK FAILED",0
s_supply:     DB "GETS REINFORCEMENTS",0
s_anykey:     DB "PRESS ANY KEY",0
s_gameover:   DB "GAME OVER",0
s_youwin:     DB "YOU WIN",0
s_pwins:      DB "PLAYER 1 WINS",0
