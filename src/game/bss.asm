; Uninitialised work buffers. These live after the end of the saved CODE
; block (the .trd file does not carry them); everything here is written
; before it is read, at map-generation or battle time.

bss_start:

cel:        DS CEL_MAX             ; cell -> area number, 0 = sea
map_num:    DS CEL_MAX             ; random growth priority per cell
rcel:       DS CEL_MAX             ; candidate seed cells for the next area
next_f:     DS CEL_MAX             ; percolation frontier flags

a_join:     DS AREA_MAX*AREA_MAX   ; adjacency matrix, [a*32+b] = 1 if joined

chk:        DS AREA_MAX            ; union-find labels (set_area_tc)
tcbuf:      DS AREA_MAX            ; group sizes (set_area_tc)
alist:      DS AREA_MAX            ; scratch area list (deals, supply)

list_from:  DS 256                 ; AI candidate attacks
list_to:    DS 256

bat_att:    DS 8                   ; rolled dice faces
bat_def:    DS 8

fr_list:    DS FR_MAX*2           ; percolation frontier cells
cellbuf:    DS 8                   ; pixel scratch for one map cell
bigbuf:     DS 32                  ; pixel scratch for one double-size char
