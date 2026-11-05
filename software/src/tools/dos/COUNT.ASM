dosint      MACRO  function            ;; Call the DOS interrupt 
            mov    ah,function         ;; Put function number in AH 
            int    21h
            ENDM

error       MACRO  errnum              ;; Display error and exit
            mov    dx,OFFSET err&errnum;; Load address of error message
            dosint 09h                 ;; Display string function
            mov    al,errnum           ;; Exit with return code of errnum
            dosint 4Ch                 ;; Quit 
            ENDM

PUBLIC      prompt,namebuf,fname,buffer,err1,err2,count,new_flag
PUBLIC      get_file,open_file,ok,buff_read,done,conv_hex,rotate
PUBLIC      quit,word_c,next_char,new_word,old_word,out_word,get_out

stack       SEGMENT word stack 'STACK'
            DB     100h DUP (?)
stack       ENDS

data        SEGMENT word public 'DATA'
prompt      DB     'Enter file name: $'
namebuf     DB     15h,?               ; Maximum length of file name 
fname       DB     15h DUP(?)          ;   is 15h (21d)
buffer      DB     800h DUP(?)         ; Buffer size is 800h (2048d) 
err1        DB     'Can''t access file',0Dh,0Ah,'$'
err2        DB     'I/O error',0Dh,0Ah,'$'
count       DW     0                   ; Initialize word count to 0
new_flag    DB     1                   ; Initialize new word to true (1)
data        ENDS

code        SEGMENT byte public 'CODE'
            ASSUME cs:code,ds:data

start:      mov    ax,data
            mov    ds,ax               ; Load data segment address

            mov    dx,OFFSET prompt    ; Load address of prompt string
            dosint 09h                 ; Display it
get_file:   mov    dx,OFFSET namebuf   ; Load address for file name buffer 
            dosint 0Ah                 ; Get file name string
            mov    si,dx               ; Set SI to start of file name buffer
            mov    bl,BYTE PTR [si+1]  ; Put the number of bytes read in BL
            mov    BYTE PTR [si+bx+2],0; Put 0 at end to make ASCIIZ string 
                                       ;   (0 overrides CR from prompt)
            mov    dl,0Ah              ; Load linefeed character
            dosint 02h                 ; Print it  

open_file:  mov    dx,OFFSET fname     ; Load offset of ASCIIZ string 
            xor    al,al               ; Set code 0 - open for reading
            dosint 3Dh                 ; Try to open the file
            jnc    ok                  ; If opened, then process file 
access:     error  1                   ;   else error macro

ok:         mov    bx,ax               ; Move file handle to BX
            mov    dx,OFFSET buffer    ; Give address to dump file contents
io_loop:    mov    cx,800h             ; Set buffer size 
            dosint 3Fh                 ; Read a buffer of data from file
buff_read:  jc     io_err              ; If there's a read error, then quit
            cmp    ax,0                ;   else see if we read anything
            je     done                ; If not, we're done
            call   word_c              ;   else count what we read 
            jmp    SHORT io_loop       ; Do it again
io_err:     error  2                   ; Error macro

done:       dosint 3Eh                 ; Close (file handle already in BX)

            mov    bx,count            ; Put count in BX for processing 
conv_hex:   mov    cl,4                ; Load number of bits to rotate 
            mov    ch,4                ; Load count for digits
rotate:     rol    bx,cl               ; Rotate left digit to right
            mov    dl,bl               ; Move to DL for processing 
            and    dl,0Fh              ; Mask off left digit
            add    dl,30h              ; Convert to ASCII digit 
            cmp    dh,3Ah              ; Is it greater than 9?
            jl     show                ; If not, display character
            add    dl,07h              ;   else convert hex letter
show:       dosint 02h                 ; Display character function
            dec    ch                  ; Decrement the digit count
            jnz    rotate              ; If count isn't zero, do it again

quit:       xor    al,al               ;   else set 0 for return code
            dosint 4Ch                 ; Return to DOS function 

word_c      PROC   NEAR                ; Procedure to count words in buffer
            push   bx                  ; Save BX - it has file handle
            mov    si,OFFSET buffer-1  ; Load address one byte before buffer 
            mov    bx,0                ; Set BX to 0 for word count 
            mov    cx,ax               ; Put number of characters read in CX
            mov    ah,new_flag         ; Set new word flag (AH) 

next_char:  inc    si                  ; Bump index (adjust on first pass)
            mov    al,[si]             ; Get next character 
            cmp    al,20h              ; Compare to space 
            jle    out_word            ; If less, we're not in a word
            cmp    ah,1                ;   else is new word flag TRUE?
            je     new_word            ; If flag is TRUE, it's a new word
            jmp    old_word            ;   else it's an old word 

new_word:   inc    bx                  ; Bump word count 
            xor    ah,ah               ; Set new word flag to FALSE (0)
old_word:   loop   next_char           ; Get next character
            jmp    get_out             ; Fall through at end of buffer

out_word:   mov    ah,1                ; Set new word flag to true (1)
            loop   next_char           ; Get next character

get_out:    add    count,bx            ; Add buffer count to variable 
            mov    new_flag,ah         ; Save current flag status
            pop    bx                  ; Restore file handle
            ret
word_c      ENDP

code        ENDS
            END    start

