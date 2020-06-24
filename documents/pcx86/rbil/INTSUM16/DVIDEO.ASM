;*****************************************************************
;  DVIDEO.ASM - Video functions for INTSUM.EXE                    
;                                                                 
;  Copyright (c) 1996 Daniel D. Miller                            
;                                                                 
;  Last Update: 10-14-95 11:37am                                  
;*****************************************************************
        .model  compact,c

        .data
curx            word    0
cury            word    0
VideoSeg        word    0B800h
        public  screen_rows
screen_rows     word    0
        public  screen_cols
screen_cols     word    0

        .code

;  void select_video_seg(unsigned vseg) ;
;  If vseg == 0, this routine will check video mode to
;  determine video segment (if mode == 7, vseg = B000 else B800).
;  If vseg != 0, VideoSeg will be set to vseg.  No checking
;  for invalid values is done, so make sure you don't set bad data.
select_video_seg proto c vseg:word
select_video_seg proc  c uses ax bx vseg:word
        mov     ax,vseg
        cmp     ax,0
        je      read_video_mode
        ;  vseg is non-zero; copy it to VideoSeg
        mov     VideoSeg,ax
        ret

read_video_mode:
        mov     ah,0Fh
        int     10h
        cmp     al,7
        jne     setB800
        mov     ax,0B000h
        mov     VideoSeg,ax
        ret
setB800:
        mov     ax,0B800h
        mov     VideoSeg,ax
        ret
        
select_video_seg endp

;  unsigned get_video_seg(void) ;
get_video_seg proto c
get_video_seg proc  c
        mov     ax,VideoSeg
        ret
get_video_seg endp

;  uchar get_char_attr(void) ;
get_char_attr proto c
get_char_attr proc  c uses bx
        mov     ah,8
        mov     bh,0
        int     10h
        mov     al,ah
        ret
get_char_attr endp

;  void clear_display(uchar cattr) ;
clear_display proto c attr:byte
clear_display proc  c uses es di cx ax attr:byte
        ;  point at video buffer
        mov     ax,VideoSeg
        mov     es,ax
        xor     di,di

        ;  calculate screen size in words
        mov     ax,screen_rows
        mov     cx,screen_cols
        mul     cx
        mov     cx,ax

        ;  get fill data
        mov     al,' '
        mov     ah,attr

        ;  fill the screen
        rep     stosw
        ret
clear_display endp

;  void get_vsize(void) ;
get_vsize proto c
get_vsize proc  c uses ax bx cx si
        push    ds      ; DATA SEGMENT IS NOW INVALID!!
        mov     ax,0
        mov     ds,ax
        mov     si,044Ah        ; address of screen columns
        mov     ax,ds:[si]
        mov     bx,ax
        mov     si,0484h        ; address of screen rows
        mov     al,ds:[si]
        xor     ah,ah
        inc     ax      ; BIOS data is base-0
        mov     cx,ax
        pop     ds      ; restore data segment
        mov     screen_cols,bx
        mov     screen_rows,cx
        ret
get_vsize endp

;  void dgotoxy(unsigned x, unsigned y) ;
dgotoxy proto c  x:word, y:word
dgotoxy proc  c  uses ax x:word, y:word
        mov     ax,x
        mov     curx,ax
        mov     ax,y
        mov     cury,ax
        ret
dgotoxy endp

;  void dprintc(unsigned x, unsigned y, uchar attr, char outchr) ;
dprintc proto C x:word, y:word, attr:byte, outchr:byte
dprintc proc  C uses ax bx es di x:word, y:word, attr:byte, outchr:byte
        mov     ax,screen_cols
        mov     bx,y
        mul     bx      ; dx:ax <- ax * bx = screen_cols * y
        add     ax,x
        shl     ax,1    ;  ax <- (screen_width * 2 * y) + 2 * x
        ;  AX now contains offset to video destination
        mov     di,ax   
        mov     ax,VideoSeg
        mov     es,ax   ;  ES:DI -> video dest

        mov     ah,attr
        mov     al,outchr
        mov     es:[di],ax
        ;stosw           ;  ES:[DI++] <- AX
        ret
dprintc endp

;  void dprints(unsigned x, unsigned y, uchar attr, char* outstr) ;
dprints proto C x:word, y:word, attr:byte, outstr:far ptr byte
dprints proc  C uses ax bx es di ds si x:word, y:word, attr:byte, outstr:far ptr byte
        mov     ax,screen_cols
        mov     bx,y
        mul     bx      ; dx:ax <- ax * bx = screen_cols * y
        add     ax,x
        shl     ax,1    ;  ax <- (screen_width * 2 * y) + 2 * x
        ;  AX now contains offset to video destination
        mov     di,ax   
        mov     ax,VideoSeg
        mov     es,ax   ;  ES:DI -> video dest

        lds     si,outstr       ; DS:SI -> string to display
        mov     ah,attr
dpr_loop:
        mov     al,ds:[si]
        inc     si
        ;lodsb           ;  AL <- DS:[SI++]
        cmp     al,0
        je      dpr_done
        mov     es:[di],ax
        ;stosw           ;  ES:[DI++] <- AX
        inc     di
        inc     di
        jmp     dpr_loop

dpr_done:
        ret
dprints endp

; void mark_cursor_line(unsigned row, uchar attr) ;
mark_cursor_line proto C row:word, attr:byte
mark_cursor_line proc  C uses ax bx cx es di row:word, attr:byte
        mov     ax,screen_cols
        shl     ax,1    ; convert byte offset to word offset
        mov     bx,row
        mul     bx      ; dx:ax <- ax * bx = screen_cols * y
        ;  AX now contains offset to video destination
        mov     di,ax   
        mov     ax,VideoSeg
        mov     es,ax   ;  ES:DI -> video dest
        inc     di      ; point to attribute byte

        mov     al,attr
        mov     cx,80   ;  change attribute
@@:     mov     es:[di],al
        inc     di
        inc     di      ; skip character position
        loop    @B
        ret
mark_cursor_line endp


;********************************************************************
;include keycodes.h with get_key() and key_hit()  

;********************************************************************
; unsigned get_key(void)
;********************************************************************
get_key proc
        mov     ah,0
        int     16h
        ret
get_key endp

;**********************************************************
; int key_hit(void)
;**********************************************************
key_hit proc
        mov     ah,1
        int     16h
        jz      key_hit_not
        mov     ax,1
        ret
key_hit_not:
        mov     ax,0
        ret
key_hit endp

; //**********************************************************
; void hide_cursor(void)
hide_cursor proc uses ax bx dx
        mov     dh,100  ; row
        mov     dl,200  ; column
        mov     bh,0
        mov     ah,2
        int     10h
        ret
hide_cursor endp

; //**********************************************************
; void home_cursor(void)
home_cursor proc uses ax bx dx
        mov     dh,0    ; row
        mov     dl,2    ; column
        mov     bh,0
        mov     ah,2
        int     10h
        ret
home_cursor endp

        end
