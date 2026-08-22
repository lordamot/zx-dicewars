; Keyboard input.
;
; key_scan reads the half-row ports directly and produces three state
; bytes plus their "newly pressed since last scan" edge counterparts:
;
;   key_state / key_new    bit 0  up      Q
;                          bit 1  down    A
;                          bit 2  left    O
;                          bit 3  right   P
;                          bit 4  fire    SPACE, ENTER or M
;                          bit 5  end     E   (end turn)
;                          bit 6  yes     Y
;                          bit 7  no      N
;   key2_state / key2_new  bits 0..6 = digits 2..8, bit 7 = H
;   key3_state / key3_new  bit 0 = S (music toggle)

KB_UP    EQU %00000001
KB_DOWN  EQU %00000010
KB_LEFT  EQU %00000100
KB_RIGHT EQU %00001000
KB_FIRE  EQU %00010000
KB_END   EQU %00100000
KB_YES   EQU %01000000
KB_NO    EQU %10000000

key_state:  DB 0
key_new:    DB 0
key2_state: DB 0
key2_new:   DB 0
key3_state: DB 0
key3_new:   DB 0

key_scan:
    ; remember previous state for edge detection
    ld a,(key_state)
    ld d,a
    ld a,(key2_state)
    ld e,a
    push de
    ld a,(key3_state)
    push af

    ; --- key_state -> D --------------------------------------------------
    ld d,0
    ld bc,#FBFE                    ; row Q W E R T (active low)
    in a,(c)
    cpl
    rrca                           ; carry = Q
    jr nc,.noQ
    set 0,d                        ; up
.noQ:
    and %00000010                  ; E (bit 2 before rrca -> bit 1 now)
    jr z,.noE
    set 5,d                        ; end turn
.noE:
    ld b,#FD                       ; row A S D F G
    in a,(c)
    cpl
    ld e,a
    rrca
    jr nc,.noA
    set 1,d                        ; down
.noA:
    ld b,#DF                       ; row P O I U Y
    in a,(c)
    cpl
    rrca                           ; carry = P
    jr nc,.noP
    set 3,d                        ; right
.noP:
    rrca                           ; carry = O
    jr nc,.noO
    set 2,d                        ; left
.noO:
    and %00000100                  ; Y (bit 4 before, bit 2 after 2x rrca)
    jr z,.noY
    set 6,d
.noY:
    ld b,#7F                       ; row SPACE SYM M N B
    in a,(c)
    cpl
    ld h,a
    and %00000101                  ; SPACE or M
    jr z,.noFire1
    set 4,d                        ; fire
.noFire1:
    ld a,h
    and %00001000                  ; N
    jr z,.noN
    set 7,d
.noN:
    ld b,#BF                       ; row ENTER L K J H
    in a,(c)
    cpl
    ld h,a
    rrca                           ; carry = ENTER
    jr nc,.noEnt
    set 4,d                        ; fire
.noEnt:

    ; --- key2_state -> L: digits 2..8 (bits 0..6), H (bit 7) ------------
    ld l,0
    ld a,h
    and %00010000                  ; H (from the ENTER row read above)
    jr z,.noH
    set 7,l
.noH:
    ld b,#F7                       ; row 1 2 3 4 5
    in a,(c)
    cpl
    rrca                           ; skip 1
    and %00001111                  ; 2 3 4 5 -> bits 0..3
    or l
    ld l,a
    ld b,#EF                       ; row 0 9 8 7 6
    in a,(c)
    cpl
    ld h,a
    and %00010000                  ; 6 -> bit 4
    or l
    ld l,a
    ld a,h
    and %00001000                  ; 7 -> bit 5
    jr z,.no7
    set 5,l
.no7:
    ld a,h
    and %00000100                  ; 8 -> bit 6
    jr z,.no8
    set 6,l
.no8:

    ; --- key3_state: S ---------------------------------------------------
    ld h,0
    ld a,e                         ; saved A-row bits (cpl'd)
    and %00000010                  ; S
    jr z,.noS
    set 0,h
.noS:

    ; --- store states, derive edges -------------------------------------
    ld a,d
    ld (key_state),a
    ld a,l
    ld (key2_state),a
    ld a,h
    ld (key3_state),a
    pop af                         ; old key3
    cpl
    and h
    ld (key3_new),a
    pop de                         ; D = old key_state, E = old key2
    ld a,d
    cpl
    ld d,a
    ld a,(key_state)
    and d
    ld (key_new),a
    ld a,e
    cpl
    and l
    ld (key2_new),a
    ret
