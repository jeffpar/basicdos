;*****************************************************************
;  STRSTRI.ASM - Case-insensitive version of strstr() from        
;                standard C library.                              
;                                                                 
;  Copyright (c) 1996 Daniel D. Miller                            
;                                                                 
;  Last Update: 07-23-95 11:36pm                                  
;*****************************************************************

        .model  compact,c

        .code

;*****************************************************************
;  perform case-insensitive compare between two characters,       
;  return TRUE (nonzero) or FALSE (0) for the compare.            
;  This routine is used by strstri(), which follows.              
;*****************************************************************
; int caseless_equality(const char chr1, const char chr2)
compare_byte proc uses bx s1:byte, s2:byte
        mov     bx,0
        mov     bl,s1
        mov     ah,cs:[char_lookupi+bx]
        mov     bl,s2
        mov     al,cs:[char_lookupi+bx]
        cmp     ah,al
        je      okay
        mov     ax,-1
        ret
okay:
        mov     ax,0
        ret

compare_byte endp

;*****************************************************************
;  Perform case-insensitive search for first occurance of         
;  str2 within str1.  Returns MATCH (0) or NO_MATCH (0xFFFF).     
;int strstri(const char* str1, const char *str2)
;*****************************************************************
strstri proc uses bx ds si es di str1:ptr byte, str2:ptr byte
        local   hdptr:word

        lds     si,str1
        les     di,str2
        mov     bl,es:[di]      ; do only ONCE

not_matching:
        ;  search for initial match
        mov     bh,ds:[si]

        cmp     bh,0
        je      no_match
        cmp     bl,0
        je      no_match

        invoke  compare_byte, bh, bl
        cmp     ax,0
        je      matching
        inc     si
        jmp     not_matching

        ;  once a single-char match is found,
        ;  come here and continue trying to match later chars
matching:
        mov     hdptr, si
match_loop:
        inc     si
        inc     di

        mov     bh,ds:[si]      ; get char from str1
        mov     bl,es:[di]      ; get char from str2

        cmp     bl,0
        je      yes_match
        cmp     bh,0
        je      no_match

        invoke  compare_byte, bh, bl
        cmp     ax,0
        je      match_loop

        ;  match failed, start over
        les     di,str2
        mov     bl,es:[di]      ; get first char from str2
        mov     si,hdptr
        inc     si
        jmp     not_matching

        ;  exit points
no_match:
        mov     ax,-1
        ret

yes_match:
        mov     ax,0
        ret

strstri endp

;*****************************************************************
;  quick lookup table for character compare.  Every entry is same 
;  as IBM ASCII, except that lower-case entries (0x60 - 0x7A) are 
;  same as upper-case entries (0x40 - 0x5A).                      
;*****************************************************************
;uchar char_lookupi[256] = {
char_lookupi    db      000h,001h,002h,003h,004h,005h,006h,007h
        db      008h,009h,00Ah,00Bh,00Ch,00Dh,00Eh,00Fh
        db      010h,011h,012h,013h,014h,015h,016h,017h
        db      018h,019h,01Ah,01Bh,01Ch,01Dh,01Eh,01Fh
        db      020h,021h,022h,023h,024h,025h,026h,027h
        db      028h,029h,02Ah,02Bh,02Ch,02Dh,02Eh,02Fh
        db      030h,031h,032h,033h,034h,035h,036h,037h
        db      038h,039h,03Ah,03Bh,03Ch,03Dh,03Eh,03Fh
        db      040h,041h,042h,043h,044h,045h,046h,047h
        db      048h,049h,04Ah,04Bh,04Ch,04Dh,04Eh,04Fh
        db      050h,051h,052h,053h,054h,055h,056h,057h
        db      058h,059h,05Ah,05Bh,05Ch,05Dh,05Eh,05Fh
        db      040h,041h,042h,043h,044h,045h,046h,047h
        db      048h,049h,04Ah,04Bh,04Ch,04Dh,04Eh,04Fh
        db      050h,051h,052h,053h,054h,055h,056h,057h
        db      058h,059h,05Ah,07Bh,07Ch,07Dh,07Eh,07Fh
        db      080h,081h,082h,083h,084h,085h,086h,087h
        db      088h,089h,08Ah,08Bh,08Ch,08Dh,08Eh,08Fh
        db      090h,091h,092h,093h,094h,095h,096h,097h
        db      098h,099h,09Ah,09Bh,09Ch,09Dh,09Eh,09Fh
        db      0A0h,0A1h,0A2h,0A3h,0A4h,0A5h,0A6h,0A7h
        db      0A8h,0A9h,0AAh,0ABh,0ACh,0ADh,0AEh,0AFh
        db      0B0h,0B1h,0B2h,0B3h,0B4h,0B5h,0B6h,0B7h
        db      0B8h,0B9h,0BAh,0BBh,0BCh,0BDh,0BEh,0BFh
        db      0C0h,0C1h,0C2h,0C3h,0C4h,0C5h,0C6h,0C7h
        db      0C8h,0C9h,0CAh,0CBh,0CCh,0CDh,0CEh,0CFh
        db      0D0h,0D1h,0D2h,0D3h,0D4h,0D5h,0D6h,0D7h
        db      0D8h,0D9h,0DAh,0DBh,0DCh,0DDh,0DEh,0DFh
        db      0E0h,0E1h,0E2h,0E3h,0E4h,0E5h,0E6h,0E7h
        db      0E8h,0E9h,0EAh,0EBh,0ECh,0EDh,0EEh,0EFh
        db      0F0h,0F1h,0F2h,0F3h,0F4h,0F5h,0F6h,0F7h
        db      0F8h,0F9h,0FAh,0FBh,0FCh,0FDh,0FEh,0FFh

        end
