; Pseudo-random numbers.
;
; rand16 is John Metcalf's 16-bit xorshift (period 65535, state never 0).
; The state is additionally stirred from the R register while the title
; screen waits for input, so every game gets a different map.

; -> HL = next 16-bit pseudo-random value (also updates rnd_state)
rand16:
    ld hl,(rnd_state)
    ld a,h
    rra
    ld a,l
    rra
    xor h
    ld h,a
    ld a,l
    rra
    ld a,h
    rra
    xor l
    ld l,a
    xor h
    ld h,a
    ld (rnd_state),hl
    ret

; mix the R register into the PRNG state (called while waiting for keys)
rand_stir:
    ld a,r
    ld hl,(rnd_state)
    xor l
    ld l,a
    ld a,h
    or l
    jr nz,.ok                      ; state must never become 0
    inc l
.ok:
    ld (rnd_state),hl
    ret

; A = n (1..255)  ->  A = uniform-ish random 0..n-1  ((rand_byte * n) >> 8)
rand_n:
    ld e,a
    ld d,0
    call rand16
    ld a,l
    ; fall through: HL = A * DE, answer in H
; HL = A * DE (D must be 0; A is consumed MSB first)
mul8x16:
    ld hl,0
    ld b,8
.bit:
    add hl,hl
    rlca
    jr nc,.skip
    add hl,de
.skip:
    djnz .bit
    ld a,h
    ret

; -> HL = random cell index 0..CEL_MAX-1
; (mask to 10 bits then fold; the small bias does not matter here)
rand_cel:
    call rand16
    ld a,h
    and 3
    ld h,a                         ; HL = 0..1023
    ld de,-CEL_MAX
    ld a,h
    cp high CEL_MAX
    jr c,.done                     ; < #280 for sure only if H < 2
    jr nz,.fold                    ; H = 3 -> fold
    ld a,l
    cp low CEL_MAX
    jr c,.done
.fold:
    add hl,de                      ; HL -= 640
.done:
    ret

; -> A = random die face 1..6
rand_d6:
    ld a,6
    call rand_n
    inc a
    ret
