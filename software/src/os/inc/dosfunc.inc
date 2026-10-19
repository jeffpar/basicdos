;
; BASIC-DOS Function Numbers
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; INT_DOSFUNC (21h) and INT_DOSUTIL (32h) function numbers.  Only modules that
; call DOS (including through the DOSUTIL, PRINTF, or DPRINTF macros) need
; this file; the rest of the DOS interfaces are in dosapi.inc, which does not
; depend on this file.
;

;
; INT_DOSFUNC functions
;
DOS_PSP_TERM	equ	00h	; same function as INT 20h
DOS_TTY_ECHO	equ	01h	; read char (AL) from CON and echo
DOS_TTY_WRITE	equ	02h	; write char (DL) to CON
DOS_AUX_READ	equ	03h	; read char (AL) from AUX
DOS_AUX_WRITE	equ	04h	; write char (DL) to AUX
DOS_PRN_WRITE	equ	05h	; write char (DL) to PRN
DOS_TTY_IO	equ	06h	; read (AL) from CON or write (DL) to CON
DOS_TTY_IN	equ	07h	; read char (AL) from CON
DOS_TTY_READ	equ	08h	; read char (AL) from CON; checks CTRLC
DOS_TTY_PRINT	equ	09h	; write string (DS:DX) to CON
DOS_TTY_INPUT	equ	0Ah	; read line (DS:DX) from CON
DOS_TTY_STATUS	equ	0Bh	; get CON status (AL = 0 if nothing, or FFh)
DOS_TTY_FLUSH	equ	0Ch	; flush and invoke 01h, 06h, 07h, 08h, or 0Ah
DOS_DSK_RESET	equ	0Dh	; disk reset
DOS_DSK_SETDRV	equ	0Eh	; set current drive (DL), return # drives (AL)
DOS_FCB_OPEN	equ	0Fh	; open FCB (DS:DX)
DOS_FCB_CLOSE	equ	10h	; close FCB (DS:DX)
DOS_FCB_FFIRST	equ	11h	; find first FCB (DS:DX)
DOS_FCB_FNEXT	equ	12h	; find next FCB (DS:DX)
DOS_FCB_DELETE	equ	13h	; delete matching files (DS:DX)
DOS_FCB_SREAD	equ	14h	; read sequential record for FCB (DS:DX)
DOS_FCB_SWRITE	equ	15h	; write sequential FCB record (DS:DX)
DOS_FCB_CREATE	equ	16h	; create FCB (DS:DX)
DOS_FCB_RENAME	equ	17h	; rename matching files (DS:DX)
DOS_DSK_GETDRV	equ	19h	; get current drive (AL)
DOS_DSK_SETDTA	equ	1Ah	; set DTA (DS:DX)
DOS_FCB_RREAD	equ	21h	; read random record for FCB (DS:DX)
DOS_FCB_RWRITE	equ	22h	; write random FCB record (DS:DX)
DOS_FCB_SIZE	equ	23h	; get size in FCB records (DS:DX)
DOS_FCB_SETREL	equ	24h	; set relative record for FCB (DS:DX)
DOS_MSC_SETVEC	equ	25h	; set vector (AL) to addr (DS:DX)
DOS_PSP_COPY	equ	26h	; copy PSP to segment (DX)
DOS_FCB_RBREAD	equ	27h	; read (CX) records for FCB (DS:DX)
DOS_FCB_RBWRITE	equ	28h	; write (CX) FCB records (DS:DX)
DOS_FCB_PARSE	equ	29h	; parse filespec (DS:SI) into FCB (ES:DI)
DOS_MSC_GETDATE	equ	2Ah	; get date (CX=year, DH=mon, DL=day, AL=wkday)
DOS_MSC_SETDATE	equ	2Bh	; set date (CX=year, DH=mon, DL=day)
DOS_MSC_GETTIME	equ	2Ch	; get time (CH=hour, CL=min, DH=sec, DL=1/100s)
DOS_MSC_SETTIME	equ	2Dh	; set time (CH=hour, CL=min, DH=sec, DL=1/100s)
DOS_DSK_GETDTA	equ	2Fh	; get DTA (ES:BX)
DOS_MSC_GETVER	equ	30h	; get version (AL,AH,BH,BL,CX)
DOS_DSK_GETDPB	equ	32h	; get DPB (DS:BX, AL=FFh if invalid drive)
DOS_MSC_CTRLC	equ	33h	; get/set CTRLC state
DOS_MSC_GETVEC	equ	35h	; get vector (AL) addr (ES:BX)
DOS_DSK_GETINFO	equ	36h	; get disk info; eg, available clusters (BX)
DOS_MSC_GETSWC	equ   3700h	; get switch char (DL) (undocumented)
DOS_MSC_GETPCH	equ   3704h	; get path char (DL) (BASIC-DOS only)
DOS_DSK_MKDIR	equ	39h	; create directory (DS:DX)
DOS_DSK_RMDIR	equ	3Ah	; remove directory (DS:DX)
DOS_DSK_CHDIR	equ	3Bh	; change current directory (DS:DX)
DOS_HDL_CREATE	equ	3Ch	; return handle for new file (DS:DX)
DOS_HDL_OPEN	equ	3Dh	; return handle for device/file (DS:DX)
DOS_HDL_OPENRO	equ   3D00h	; return handle with R/O access
DOS_HDL_OPENWO	equ   3D01h	; return handle with W/O access
DOS_HDL_OPENRW	equ   3D02h	; return handle with R/W access
DOS_HDL_CLOSE	equ	3Eh	; close handle (BX)
DOS_HDL_READ	equ	3Fh	; read (CX) bytes at (DS:DX) with handle (BX)
DOS_HDL_WRITE	equ	40h	; write (CX) bytes at (DS:DX) with handle (BX)
DOS_DSK_DELETE	equ	41h	; delete file (DS:DX)
DOS_HDL_SEEK	equ	42h	; seek to (CX:DX) w/method (AL) and handle (BX)
DOS_HDL_SEEKBEG	equ   4200h	; seek from beginning
DOS_HDL_SEEKCUR	equ   4201h	; seek from current position
DOS_HDL_SEEKEND	equ   4202h	; seek from end
DOS_HDL_IOCTL	equ   	44h	; send device request (AL) for handle (BX)
DOS_DSK_GETCWD	equ	47h	; get current dir of drive (DL) at (DS:SI)
DOS_MEM_ALLOC	equ	48h	; allocate (BX) paras (returns segment AX)
DOS_MEM_FREE	equ	49h	; free segment (ES)
DOS_MEM_REALLOC	equ	4Ah	; reallocate size of segment (ES) to paras (BX)
DOS_PSP_EXEC	equ   4B00h	; load program (DS:DX) with EPB (ES:BX)
DOS_PSP_EXEC1	equ   4B01h	; load program w/o starting (undocumented)
DOS_PSP_EXEC2	equ   4B02h	; start program (BASIC-DOS only)
DOS_PSP_RETURN	equ	4Ch	; return to caller with exit code (AL)
DOS_PSP_RETCODE	equ	4Dh	; return exit code (AL) and exit type (AH)
DOS_DSK_FFIRST	equ	4Eh	; find first filespec (DS:DX) with attr (CX)
DOS_DSK_FNEXT	equ	4Fh	; find next filespec (DTA)
DOS_PSP_SET	equ	50h	; set current PSP (BX) (undocumented)
DOS_PSP_GET	equ	51h	; get current PSP (BX) (undocumented)
DOS_MSC_GETVARS	equ	52h	; get variables pointer (ES:BX) (undocumented)
DOS_PSP_CREATE	equ	55h	; create PSP in segment (DX) (undocumented)
DOS_DSK_RENAME	equ	56h	; rename file (DS:DX) to (ES:DI)

;
; INT_DOSUTIL functions
;
DOS_UTL_STRLEN	equ	00h	; return string (DS:SI) length (AX)
DOS_UTL_STRSTR	equ	01h	; find string (CS:SI) in string (ES:DI)
DOS_UTL_STRUPR	equ	02h	; upper-case string (DS:SI)
DOS_UTL_PRINTF	equ	03h	; printf to console
DOS_UTL_HPRINTF	equ	04h	; printf to SFH (BL), like DOS_UTL_PRINTF
DOS_UTL_DPRINTF	equ	05h	; printf to DEBUG context, if any
DOS_UTL_TPRINTF	equ	06h	; printf (DS:BX) to console, typed parameters
DOS_UTL_SPRINTF	equ	07h	; sprintf to buffer (ES:DI)
DOS_UTL_ITOA	equ	08h	; convert number (DX:SI) to string (ES:DI)
DOS_UTL_ATOI16	equ	09h	; convert string (DS:SI) to 16-bit int (AX)
DOS_UTL_ATOI32	equ	0Ah	; convert string (DS:SI) to 32-bit int (DX:AX)
DOS_UTL_ATOI32D	equ	0Bh	; convert decimal string to 32-bit int (DX:AX)
DOS_UTL_TOKEN1	equ	0Ch	; tokenize string (DS:SI) using generic syntax
DOS_UTL_TOKEN2	equ	0Dh	; tokenize string (DS:SI) using BASIC syntax
DOS_UTL_TOKID	equ	0Eh	; convert string (DS:SI) into token ID (AX)
DOS_UTL_PARSESW	equ	0Fh	; parse TOKBUF (ES:DI) for switches
DOS_UTL_GETDEV	equ	10h	; get DDH (ES:DI) for device (DS:DX)
DOS_UTL_GETCSN	equ	11h	; get current session number (CL)
DOS_UTL_QRYSCB	equ	12h	; query session (CL)
DOS_UTL_LOAD	equ	13h	; load program (SPB at ES:BX) into a session
DOS_UTL_START	equ	14h	; start session (CL)
DOS_UTL_STOP	equ	15h	; stop session (CL)
DOS_UTL_END	equ	16h	; end session (CL)
DOS_UTL_WAITEND	equ	17h	; wait for session to end (CL)
DOS_UTL_YIELD	equ	18h	; yield
DOS_UTL_SLEEP	equ	19h	; sleep (CX:DX) milliseconds
DOS_UTL_WAIT	equ	1Ah	; wait on ID (DX:DI) until end wait
DOS_UTL_ENDWAIT	equ	1Bh	; end wait on ID (DX:DI)
DOS_UTL_HOTKEY	equ	1Ch	; CON detected hotkey (DL) (eg, CTRLC, CTRLP)
DOS_UTL_LOCK	equ	1Dh	; lock current session
DOS_UTL_UNLOCK	equ	1Eh	; unlock current session
DOS_UTL_QRYMEM	equ	1Fh	; query memory block N (CX) of type (DL)
DOS_UTL_TERM	equ	20h	; terminate with exit code (DL) and type (DH)
DOS_UTL_RESTART	equ	21h	; restart ("reboot") the system
DOS_UTL_GETDATE	equ	22h	; get date (AX) in "packed" format
DOS_UTL_GETTIME	equ	23h	; get time (AX) in "packed" format
DOS_UTL_INCDATE	equ	24h	; increment date (CX=year, DH=month, DL=day)
DOS_UTL_EDITLN	equ	25h	; edit line (DS:DX)
DOS_UTL_SOUND	equ	26h	; sound (DX = PIT divisor) for CX ticks
DOS_UTL_HDLCTL	equ	(DOS_HDL_IOCTL + 80h)
