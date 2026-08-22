; Map generation and territory bookkeeping.
;
; A faithful port of the browser remake's make_map() (js/game.js in
; ../dicewars), moved from a 28x32 hex grid to the 32x20 cell grid with
; 4-way adjacency: areas grow by percolation (each cell has a random
; priority, an area repeatedly claims the lowest-priority frontier cell),
; the remaining frontier is absorbed, sub-6-cell areas are dropped, and
; each area gets a center cell (closest to the bounding-box center,
; border cells penalised) where its dice stack is shown.
;
; Cell index = row*32 + col, so col = idx & 31 and row = idx >> 5.

PERC_CMAX   EQU 8                  ; target cells per area before absorbing

cur_an:     DB 0                   ; area being grown
pc_pos:     DW 0                   ; percolation: current cell
pc_count:   DB 0
fm_base:    DW 0                   ; find_min_flag: flag array base
fm_best:    DW 0
fm_min:     DB 0
fm_found:   DB 0
nb_count:   DB 0                   ; get_neighbors output
nb_list:    DS 8
fh_land:    DB 0
cc_col:     DB 0                   ; calc_centers scratch
cc_row:     DB 0
cc_len:     DB 0
cc_f:       DB 0
aa_arm:     DB 0
pid_left:   DB 0
pid_p:      DB 0
bl_pn:      DB 0
tc_pn:      DB 0                   ; set_area_tc scratch
tc_i:       DB 0
tc_j:       DB 0
fr_count:   DB 0                   ; frontier list length (percolate)

; --- neighbours ------------------------------------------------------------

; DE = cell index -> nb_count / nb_list = the 2..4 valid 4-way neighbours.
; Preserves BC,DE; destroys A,HL.
get_neighbors:
    xor a
    ld (nb_count),a
    ; up (idx >= 32)
    ld a,d
    or a
    jr nz,.up_ok
    ld a,e
    cp 32
    jr c,.no_up
.up_ok:
    ld hl,-32
    add hl,de
    call nb_add
.no_up:
    ; down (idx < 640-32 = #260)
    ld a,d
    cp 2
    jr c,.down_ok
    ld a,e
    cp #60
    jr nc,.no_down
.down_ok:
    ld hl,32
    add hl,de
    call nb_add
.no_down:
    ; left (col > 0)
    ld a,e
    and 31
    jr z,.no_left
    ld hl,-1
    add hl,de
    call nb_add
.no_left:
    ; right (col < 31)
    ld a,e
    and 31
    cp 31
    jr z,.no_right
    ld hl,1
    add hl,de
    call nb_add
.no_right:
    ret

nb_add:                            ; HL = neighbour index; preserves BC,DE
    push de
    push bc
    ex de,hl
    ld a,(nb_count)
    ld l,a
    inc a
    ld (nb_count),a
    ld h,0
    add hl,hl
    ld bc,nb_list
    add hl,bc
    ld (hl),e
    inc hl
    ld (hl),d
    pop bc
    pop de
    ret

; --- lowest-priority candidate search --------------------------------------

; Find the cell with the lowest map_num among unclaimed cells flagged in
; rcel (area seeds) / next_f (percolation frontier).
; -> HL = index, or carry set if there is none.
find_min_rcel:
    ld hl,rcel
find_min_flag:
    ld (fm_base),hl
    ld a,#FF
    ld (fm_min),a
    xor a
    ld (fm_found),a
    ld de,0
.loop:
    ld hl,cel
    add hl,de
    ld a,(hl)
    or a
    jr nz,.next                    ; already claimed
    ld hl,(fm_base)
    add hl,de
    ld a,(hl)
    or a
    jr z,.next                     ; not flagged
    ld hl,map_num
    add hl,de
    ld a,(hl)
    ld c,a
    ld a,(fm_min)
    cp c
    jr c,.next                     ; existing min is lower
    ld a,c
    ld (fm_min),a
    ld (fm_best),de
    ld a,1
    ld (fm_found),a
.next:
    inc de
    ld a,d
    cp HIGH CEL_MAX
    jr nz,.loop
    ld a,e
    cp LOW CEL_MAX
    jr nz,.loop
    ld a,(fm_found)
    or a
    jr z,.none
    ld hl,(fm_best)
    or a                           ; clear carry
    ret
.none:
    scf
    ret

; like find_min_flag, but only over the cells collected in fr_list
; -> HL = index, or carry set if every listed cell is already claimed
find_min_frlist:
    ld a,(fr_count)
    or a
    jr z,.none
    ld b,a
    ld hl,fr_list
    ld a,#FF
    ld (fm_min),a
    xor a
    ld (fm_found),a
.loop:
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    push hl
    ld hl,cel
    add hl,de
    ld a,(hl)
    or a
    jr nz,.next                    ; claimed meanwhile
    ld hl,map_num
    add hl,de
    ld a,(hl)
    ld c,a
    ld a,(fm_min)
    cp c
    jr c,.next
    ld a,c
    ld (fm_min),a
    ld (fm_best),de
    ld a,1
    ld (fm_found),a
.next:
    pop hl
    djnz .loop
    ld a,(fm_found)
    or a
    jr z,.none
    ld hl,(fm_best)
    or a
    ret
.none:
    scf
    ret

; --- percolation -----------------------------------------------------------

FR_MAX      EQU 128                ; frontier list capacity (real max ~40)

; Grow area (cur_an) from cell HL: claim up to PERC_CMAX cells walking the
; lowest-priority frontier, then absorb the whole remaining frontier and
; flag its neighbours in rcel as seed candidates for the next area.
; The frontier is kept both as next_f flags (used by the absorb pass) and
; as a small list (fr_list), so the min-search below touches only actual
; frontier cells instead of scanning the whole grid.
percolate:
    ld (pc_pos),hl
    ld hl,next_f
    ld bc,CEL_MAX
    xor a
    call mem_fill
    xor a
    ld (pc_count),a
    ld (fr_count),a
.claim:
    ld de,(pc_pos)
    ld hl,cel
    add hl,de
    ld a,(cur_an)
    ld (hl),a
    ld a,(pc_count)
    inc a
    ld (pc_count),a
    ; flag the 4 neighbours as frontier (and list the new ones)
    call get_neighbors
    ld a,(nb_count)
    or a
    jr z,.nomark
    ld b,a
    ld hl,nb_list
.mark:
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    push hl
    ld hl,next_f
    add hl,de
    ld a,(hl)
    or a
    jr nz,.marked                  ; already on the frontier
    ld (hl),1
    ld a,(fr_count)
    cp FR_MAX
    jr nc,.marked                  ; list full: still flagged for absorb
    ld l,a
    ld h,0
    add hl,hl
    push bc
    ld bc,fr_list
    add hl,bc
    pop bc
    ld (hl),e
    inc hl
    ld (hl),d
    ld a,(fr_count)
    inc a
    ld (fr_count),a
.marked:
    pop hl
    djnz .mark
.nomark:
    ld a,(pc_count)
    cp PERC_CMAX
    jr nc,.absorb
    call find_min_frlist
    jr c,.absorb                   ; frontier exhausted
    ld (pc_pos),hl
    jr .claim

.absorb:
    ; every unclaimed frontier cell joins the area; its neighbours become
    ; rcel seed candidates for the next area
    ld de,0
.ab:
    ld hl,next_f
    add hl,de
    ld a,(hl)
    or a
    jr z,.abnext
    ld hl,cel
    add hl,de
    ld a,(hl)
    or a
    jr nz,.abnext
    ld a,(cur_an)
    ld (hl),a
    call get_neighbors
    push de
    ld a,(nb_count)
    or a
    jr z,.abdone
    ld b,a
    ld hl,nb_list
.abn:
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    push hl
    ld hl,rcel
    add hl,de
    ld (hl),1
    pop hl
    djnz .abn
.abdone:
    pop de
.abnext:
    inc de
    ld a,d
    cp HIGH CEL_MAX
    jr nz,.ab
    ld a,e
    cp LOW CEL_MAX
    jr nz,.ab
    ret

; --- make_map --------------------------------------------------------------

make_map:
    ; random cell priorities; clear cel / rcel
    ld hl,cel
    ld bc,CEL_MAX
    xor a
    call mem_fill
    ld hl,rcel
    ld bc,CEL_MAX
    xor a
    call mem_fill
    ld hl,map_num
    ld bc,CEL_MAX
.pri:
    push bc
    push hl
    call rand16
    ld a,l
    pop hl
    ld (hl),a
    inc hl
    pop bc
    dec bc
    ld a,b
    or c
    jr nz,.pri

    ; seed candidate cell, then grow areas 1..31
    call rand_cel
    ld de,rcel
    add hl,de
    ld (hl),1
    ld a,1
    ld (cur_an),a
.grow:
    call find_min_rcel
    jr c,.grown
    call percolate
    ld a,(cur_an)
    inc a
    ld (cur_an),a
    cp AREA_MAX
    jr c,.grow
.grown:

    ; fill sea cells completely surrounded by land
    ld de,0
.fh:
    ld hl,cel
    add hl,de
    ld a,(hl)
    or a
    jr nz,.fhnext
    call get_neighbors
    push de
    xor a
    ld (fh_land),a
    ld a,(nb_count)
    ld b,a
    ld c,0                         ; c = "some neighbour is sea"
    ld hl,nb_list
.fhn:
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    push hl
    ld hl,cel
    add hl,de
    ld a,(hl)
    pop hl
    or a
    jr nz,.fhland
    ld c,1
    jr .fhcont
.fhland:
    ld (fh_land),a
.fhcont:
    djnz .fhn
    pop de
    ld a,c
    or a
    jr nz,.fhnext
    ld a,(fh_land)
    or a
    jr z,.fhnext
    ld hl,cel
    add hl,de
    ld (hl),a
.fhnext:
    inc de
    ld a,d
    cp HIGH CEL_MAX
    jr nz,.fh
    ld a,e
    cp LOW CEL_MAX
    jr nz,.fh

    call calc_sizes
    call calc_centers
    call assign_arms
    call place_initial_dice
    ret

; --- area sizes ------------------------------------------------------------

calc_sizes:
    ; clear all per-area arrays (a_size..a_lenmin are contiguous) + join
    ld hl,a_size
    ld bc,12*AREA_MAX
    xor a
    call mem_fill
    ld hl,a_join
    ld bc,AREA_MAX*AREA_MAX
    xor a
    call mem_fill
    ; count cells per area
    ld de,0
.cnt:
    ld hl,cel
    add hl,de
    ld a,(hl)
    or a
    jr z,.cn
    push de
    ld e,a
    ld d,0
    ld hl,a_size
    add hl,de
    inc (hl)
    jr nz,.nosat
    dec (hl)                       ; saturate at 255
.nosat:
    pop de
.cn:
    inc de
    ld a,d
    cp HIGH CEL_MAX
    jr nz,.cnt
    ld a,e
    cp LOW CEL_MAX
    jr nz,.cnt
    ; drop areas of 5 cells or less
    ld hl,a_size+1
    ld b,AREA_MAX-1
.drop:
    ld a,(hl)
    cp 6
    jr nc,.keep
    ld (hl),0
.keep:
    inc hl
    djnz .drop
    ; return dropped areas' cells to the sea
    ld de,0
.cl:
    ld hl,cel
    add hl,de
    ld a,(hl)
    or a
    jr z,.cln
    push de
    push hl
    ld e,a
    ld d,0
    ld hl,a_size
    add hl,de
    ld a,(hl)
    pop hl
    pop de
    or a
    jr nz,.cln
    ld (hl),0
.cln:
    inc de
    ld a,d
    cp HIGH CEL_MAX
    jr nz,.cl
    ld a,e
    cp LOW CEL_MAX
    jr nz,.cl
    ret

; --- centers and adjacency -------------------------------------------------

calc_centers:
    ; init bbox scan values
    ld hl,a_left+1
    ld bc,AREA_MAX-1
    ld a,XMAX
    call mem_fill
    ld hl,a_right+1
    ld bc,AREA_MAX-1
    xor a
    call mem_fill
    ld hl,a_top+1
    ld bc,AREA_MAX-1
    ld a,YMAX
    call mem_fill
    ld hl,a_bottom+1
    ld bc,AREA_MAX-1
    xor a
    call mem_fill
    ld hl,a_lenmin+1
    ld bc,AREA_MAX-1
    ld a,#FF
    call mem_fill

    ; pass 1: bounding boxes
    ld de,0
.p1:
    ld hl,cel
    add hl,de
    ld a,(hl)
    or a
    jr z,.p1n
    push de
    ld c,a                         ; C = area
    call idx_rowcol                ; -> cc_row / cc_col
    ld b,0
    ld a,(cc_col)
    ld e,a
    ld hl,a_left
    ld a,c
    add a,l
    ld l,a
    jr nc,.l1
    inc h
.l1:
    ld a,e
    cp (hl)
    jr nc,.l2
    ld (hl),a                      ; new left
.l2:
    ld hl,a_right
    ld a,c
    add a,l
    ld l,a
    jr nc,.r1
    inc h
.r1:
    ld a,e
    cp (hl)
    jr c,.r2
    ld (hl),a                      ; new right
.r2:
    ld a,(cc_row)
    ld e,a
    ld hl,a_top
    ld a,c
    add a,l
    ld l,a
    jr nc,.t1
    inc h
.t1:
    ld a,e
    cp (hl)
    jr nc,.t2
    ld (hl),a                      ; new top
.t2:
    ld hl,a_bottom
    ld a,c
    add a,l
    ld l,a
    jr nc,.b1
    inc h
.b1:
    ld a,e
    cp (hl)
    jr c,.b2
    ld (hl),a                      ; new bottom
.b2:
    pop de
.p1n:
    inc de
    ld a,d
    cp HIGH CEL_MAX
    jr nz,.p1
    ld a,e
    cp LOW CEL_MAX
    jr nz,.p1

    ; pass 2: bbox centers
    ld b,AREA_MAX-1
    ld c,1
.p2:
    ld e,c
    ld d,0
    ld hl,a_left
    add hl,de
    ld a,(hl)
    push hl
    ld hl,a_right
    add hl,de
    add a,(hl)
    rra                            ; /2 (carry from add is bit 8)
    ld hl,a_cx
    add hl,de
    ld (hl),a
    pop hl
    ld hl,a_top
    add hl,de
    ld a,(hl)
    push hl
    ld hl,a_bottom
    add hl,de
    add a,(hl)
    rra
    ld hl,a_cy
    add hl,de
    ld (hl),a
    pop hl
    inc c
    djnz .p2

    ; pass 3: per-cell distance to center; pick center cell, record joins
    ld de,0
.p3:
    ld hl,cel
    add hl,de
    ld a,(hl)
    or a
    jp z,.p3n
    push de
    push af
    call idx_rowcol
    pop af
    ld c,a                         ; C = area
    ; len = |cx - col| + |cy - row|
    ld e,a
    ld d,0
    ld hl,a_cx
    add hl,de
    ld a,(hl)
    ld hl,cc_col
    sub (hl)
    jr nc,.ax
    neg
.ax:
    ld b,a
    ld hl,a_cy
    add hl,de
    ld a,(hl)
    ld hl,cc_row
    sub (hl)
    jr nc,.ay
    neg
.ay:
    add a,b
    ld (cc_len),a
    ; border check + adjacency
    xor a
    ld (cc_f),a
    pop de
    push de
    call get_neighbors             ; preserves DE
    ld a,(nb_count)
    ld b,a
    ld hl,nb_list
.p3j:
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    push hl
    ld hl,cel
    add hl,de
    ld a,(hl)
    pop hl
    cp c
    jr z,.p3jn
    ; different area (or sea): border cell; record join[c][a]
    push hl
    push bc
    ld b,a                         ; neighbour area
    ld a,1
    ld (cc_f),a
    ld l,c
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl                      ; c*32
    ld e,b
    ld d,0
    add hl,de
    ld de,a_join
    add hl,de
    ld (hl),1
    pop bc
    pop hl
.p3jn:
    djnz .p3j
    ; apply border penalty
    ld a,(cc_f)
    or a
    jr z,.nopen
    ld a,(cc_len)
    add a,4
    ld (cc_len),a
.nopen:
    ; new minimum -> this cell becomes the center
    ld e,c
    ld d,0
    ld hl,a_lenmin
    add hl,de
    ld a,(cc_len)
    cp (hl)
    jr nc,.nomin
    ld (hl),a
    ld hl,a_crow
    add hl,de
    ld a,(cc_row)
    ld (hl),a
    ld hl,a_ccol
    add hl,de
    ld a,(cc_col)
    ld (hl),a
.nomin:
    pop de
.p3n:
    inc de
    ld a,d
    cp HIGH CEL_MAX
    jp nz,.p3
    ld a,e
    cp LOW CEL_MAX
    jp nz,.p3
    ret

; DE = cell index -> cc_row / cc_col. Preserves DE,BC.
idx_rowcol:
    ld a,e
    and 31
    ld (cc_col),a
    ld a,e
    rlca
    rlca
    rlca
    and 7                          ; e>>5
    ld l,a
    ld a,d
    rlca
    rlca
    rlca
    and #F8                        ; d<<3 (d is 0..2)
    or l
    ld (cc_row),a
    ret

; --- player assignment -----------------------------------------------------

; deal the areas to players: repeatedly pick a random unassigned area and
; give it to the next player round-robin
assign_arms:
    ld hl,a_arm
    ld bc,AREA_MAX
    ld a,#FF
    call mem_fill
    xor a
    ld (aa_arm),a
.round:
    ; collect unassigned live areas
    ld c,0
    ld e,1
    ld b,AREA_MAX-1
    ld hl,alist
.col:
    ld d,0
    push hl
    ld hl,a_size
    add hl,de
    ld a,(hl)
    or a
    jr z,.no
    ld hl,a_arm
    add hl,de
    ld a,(hl)
    inc a                          ; #FF -> 0 = unassigned
    jr nz,.no
    pop hl
    ld (hl),e
    inc hl
    inc c
    jr .cont
.no:
    pop hl
.cont:
    inc e
    djnz .col
    ld a,c
    or a
    ret z
    call rand_n
    ld e,a
    ld d,0
    ld hl,alist
    add hl,de
    ld a,(hl)
    ld e,a
    ld hl,a_arm
    add hl,de
    ld a,(aa_arm)
    ld (hl),a
    inc a
    ld hl,pmax
    cp (hl)
    jr c,.keep
    xor a
.keep:
    ld (aa_arm),a
    jr .round

; --- initial dice ----------------------------------------------------------

; 1 die everywhere, then 2 more per area on average, dealt round-robin to
; a random not-yet-full area of each player in turn
place_initial_dice:
    ld c,0                         ; live area count
    ld e,1
    ld b,AREA_MAX-1
.one:
    ld d,0
    ld hl,a_size
    add hl,de
    ld a,(hl)
    or a
    jr z,.on
    ld hl,a_dice
    add hl,de
    ld (hl),1
    inc c
.on:
    inc e
    djnz .one
    ld a,c
    add a,a                        ; total extra dice = areas * (PUT_DICE-1)
    ld (pid_left),a
    xor a
    ld (pid_p),a
.place:
    ld a,(pid_left)
    or a
    ret z
    dec a
    ld (pid_left),a
    ld a,(pid_p)
    ld (bl_pn),a
    call build_supply_list
    or a
    ret z                          ; a player ran full: stop dealing (as JS)
    call rand_n
    ld e,a
    ld d,0
    ld hl,alist
    add hl,de
    ld a,(hl)
    ld e,a
    ld hl,a_dice
    add hl,de
    inc (hl)
    ; next player
    ld a,(pid_p)
    inc a
    ld hl,pmax
    cp (hl)
    jr c,.pk
    xor a
.pk:
    ld (pid_p),a
    jr .place

; areas owned by player (bl_pn) with dice < 8 -> alist; A = count
build_supply_list:
    ld c,0
    ld e,1
    ld b,AREA_MAX-1
    push ix
    ld ix,alist
.scan:
    ld d,0
    ld hl,a_size
    add hl,de
    ld a,(hl)
    or a
    jr z,.next
    ld hl,a_arm
    add hl,de
    ld a,(bl_pn)
    cp (hl)
    jr nz,.next
    ld hl,a_dice
    add hl,de
    ld a,(hl)
    cp DICE_MAX
    jr nc,.next
    ld (ix+0),e
    inc ix
    inc c
.next:
    inc e
    djnz .scan
    pop ix
    ld a,c
    ret

; --- largest connected group (reinforcement count) --------------------------

; A = player number: recompute p_area_tc[A] by union-merging his areas
; over the adjacency matrix (straight port of set_area_tc)
set_area_tc:
    ld (tc_pn),a
    ld hl,chk
    ld b,AREA_MAX
    xor a
.init:
    ld (hl),a
    inc hl
    inc a
    djnz .init
.outer:
    ld a,1
    ld (tc_i),a
.iloop:
    ld a,(tc_i)
    call area_own_check
    jr nc,.inext
    ld a,1
    ld (tc_j),a
.jloop:
    ld a,(tc_j)
    call area_own_check
    jr nc,.jnext
    ; adjacent?
    ld a,(tc_i)
    ld l,a
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    ld a,(tc_j)
    ld e,a
    ld d,0
    add hl,de
    ld de,a_join
    add hl,de
    ld a,(hl)
    or a
    jr z,.jnext
    ; different group labels? merge to the smaller label and restart
    ld a,(tc_i)
    ld e,a
    ld d,0
    ld hl,chk
    add hl,de
    ld b,(hl)                      ; chk[i]
    push hl
    ld a,(tc_j)
    ld e,a
    ld hl,chk
    add hl,de
    ld c,(hl)                      ; chk[j], HL -> chk[j]
    ld a,b
    cp c
    jr nz,.differ
    pop hl
    jr .jnext
.differ:
    jr c,.iSmaller
    pop hl                         ; chk[i] > chk[j]: chk[i] = chk[j]
    ld (hl),c
    jr .outer
.iSmaller:
    ld (hl),b                      ; chk[j] = chk[i]
    pop hl
    jr .outer
.jnext:
    ld a,(tc_j)
    inc a
    ld (tc_j),a
    cp AREA_MAX
    jr c,.jloop
.inext:
    ld a,(tc_i)
    inc a
    ld (tc_i),a
    cp AREA_MAX
    jr c,.iloop

    ; count group sizes, take the maximum
    ld hl,tcbuf
    ld bc,AREA_MAX
    xor a
    call mem_fill
    ld a,1
.cnt:
    ld (tc_i),a
    call area_own_check
    jr nc,.cn
    ld a,(tc_i)
    ld e,a
    ld d,0
    ld hl,chk
    add hl,de
    ld a,(hl)
    ld e,a
    ld hl,tcbuf
    add hl,de
    inc (hl)
.cn:
    ld a,(tc_i)
    inc a
    cp AREA_MAX
    jr c,.cnt
    ld hl,tcbuf
    ld b,AREA_MAX
    ld c,0
.max:
    ld a,(hl)
    cp c
    jr c,.m2
    ld c,a
.m2:
    inc hl
    djnz .max
    ld a,(tc_pn)
    ld e,a
    ld d,0
    ld hl,p_area_tc
    add hl,de
    ld (hl),c
    ret

; A = area number -> carry set if it exists and belongs to player (tc_pn)
area_own_check:
    ld e,a
    ld d,0
    ld hl,a_size
    add hl,de
    ld a,(hl)
    or a
    jr z,.no
    ld hl,a_arm
    add hl,de
    ld a,(tc_pn)
    cp (hl)
    jr nz,.no
    scf
    ret
.no:
    or a
    ret
