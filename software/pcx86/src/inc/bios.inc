;
; BASIC-DOS ROM BIOS Interface and Data Area Definitions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	disk.inc
;
; Standard PC BIOS vectors (first few are really standard 8086 vectors)
;
; Page numbers are from the first IBM 5150 Technical Reference Manual (1981)
;
INT_DV		EQU	00h	; #DE (divide error)
INT_DB		EQU	01h	; #DB (debug aka single-step)
INT_NMI		EQU	02h	; NMI
INT_BP		EQU	03h	; #BP (breakpoint)
INT_OF		EQU	04h	; #OF (overflow)
INT_PRTSC	EQU	05h	; PRINT_SCREEN (p. A-79)
INT_HW_TMR	EQU	08h	;
INT_HW_KBD	EQU	09h	;
INT_VIDEO	EQU	10h	; VIDEO_IO (p. A-43)
INT_EQUIP	EQU	11h	; EQUIPMENT_DETERMINATION (p. A-67)
INT_MEMORY	EQU	12h	; MEMORY_SIZE_DETERMINE (p. A-67)
INT_FDC		EQU	13h	; DISKETTE_IO (p. A-32)
INT_COM		EQU	14h	; RS232_IO (p. A-20)
INT_CASSETTE	EQU	15h	; CASSETTE_IO (p. A-68)
INT_KBD		EQU	16h	; KEYBOARD_IO (p. A-23)
INT_LPT		EQU	17h	; PRINTER_IO (p. A-42)
INT_BASIC	EQU	18h	;
INT_REBOOT	EQU	19h	; BOOT_STRAP (p. A-20)
INT_TIME	EQU	1Ah	; TIME_OF_DAY (p. A-77)
INT_BREAK	EQU	1Bh	; CTRL_BREAK
INT_TICK	EQU	1Ch	; TIMER TICK
INT_VPT		EQU	1Dh	; VIDEO PARAMETER TABLE
INT_DPT		EQU	1Eh	; DISKETTE PARAMETER TABLE
INT_VGCDATA	EQU	1Fh	; VIDEO GRAPHICS CHARACTER DATA

;
; INT_VIDEO functions
;
VIDEO_TTYOUT	EQU	0Eh	; AL=char, BH=display page

;
; INT_FDC (Floppy Disk Controller) and INT_HDC (Hard Disk Controller) functions
;
FDC_READ	EQU	02h	;
FDC_WRITE	EQU	03h	;
HDC_GETPARMS	EQU	08h	; DL=80h; DL:=# drives (if carry clear)

FDCERR_BADCMD	EQU	01h	; bad (BIOS) command
FDCERR_BADMARK	EQU	02h	; bad address mark
FDCERR_WP	EQU	03h	; write-protect error
FDCERR_NOSECTOR	EQU	04h	; sector not found
FDCERR_DMAOVR	EQU	08h	; DMA overrun error
FDCERR_DMA64K	EQU	09h	; DMA (64K) boundary error
FDCERR_CRC	EQU	10h	; CRC error
FDCERR_CTRL	EQU	20h	; controller failure
FDCERR_SEEK	EQU	40h	; seek failure
FDCERR_NOTREADY	EQU	80h	; aka timeout

;
; INT_KBD functions
;
KBD_READ	EQU	00h	; returns char code in AL, scan code in AH
KBD_CHECK	EQU	01h	; returns ZF set if no key

;
; INT_TIME functions
;
TIME_GETTICKS	EQU	00h	; returns CX:DX, and AL != 0 if wrapped

REG16	struc
LO		db	?
HI		db	?
REG16	ends

FARPTR	struc
OFF		dw	?
SEG		dw	?
FARPTR	ends

;
; Diskette Parameter Table (11 bytes pointed by INT_DSKPARMS (1Eh))
;
; Early utilities (like SPEEDUP; see https://www.pcjs.org/blog/2017/07/21/)
; changed:
;
;	DPT_SPECIFY1:	from CFh to DFh (step rate from 8ms to 6ms)
;	DPT_HEADSETTLE:	from 19h to 00h (head settle from 25ms to 0ms)
;
DPT		struc
DP_SPECIFY1	db	?	; CFh: SRT=C, HD UNLOAD=0F (1ST SPECIFY BYTE)
DP_SPECIFY2	db	?	; 02h: HD LOAD=1, MODE=DMA (2ND SPECIFY BYTE)
DP_MOTOROFF	db	?	; 25h: WAIT AFTER OPN TIL MOTOR OFF
DP_BPS		db	?	; 02h: 512 BYTES/SECTOR
DP_SPT		db	?	; 08h: EOT (LAST SECTOR ON TRACK)
DP_GAP		db	?	; 2Ah: GAP LENGTH
DP_DTL		db	?	; FFh: DTL
DP_GAP3		db	?	; 50h: GAP LENGTH FOR FORMAT
DP_FILL		db	?	; F6h: FILL BYTE FOR FORMAT
DP_HEADSETTLE	db	?	; 19h: HEAD SETTLE TIME (MS)
DP_MOTORON	db	?	; 04h: MOTOR-ON START TIME (1/8 SECS)
DPT		ends

;
; ROM BIOS DATA AREA
;
; We'll assume that all 256 bytes from 40:00h to 40:FFh are used or reserved.
;
; I've also made the strategic decision to NOT use segment value 40h to access
; ROM BIOS data, as 00h is more useful.
;
BIOS		segment at 0
IVT		dd    256 DUP(?);
RS232_BASE	dw	4 DUP(?); 400h: ADDRESSES OF RS232 ADAPTERS
PRINTER_BASE	dw	4 DUP(?); 408h: ADDRESSES OF PRINTERS
EQUIP_FLAG	dw	?	; 410h: INSTALLED HARDWARE
;
; EQUIP_FLAG bits
;
EQ_NUM_PRINT	EQU	0C000h	; NUMBER OF PRINTERS ATTACHED
EQ_GAME_CTRL	EQU	1000h	; GAME I/O ATTACHED
EQ_NUM_RS232	EQU	0E00h	; NUMBER OF RS232 CARDS ATTACHED
EQ_NUM_DRIVES	EQU	00C0h	; NUMBER OF DISKETTE DRIVES
				; (00=1,01=2,10=3,11=4) ONLY IF IPL_DRIVE SET
EQ_VIDEO_MODE	EQU	0030h	; INITIAL VIDEO MODE (see below)
EQ_VIDEO_CO40	EQU	0010h	;
EQ_VIDEO_CO80	EQU	0020h	;
EQ_VIDEO_MONO	EQU	0030h	;
EQ_RAM_SIZE	EQU	00C0h	; PLANAR RAM SIZE (00=16K,01=32K,10=48K,11=64K)
EQ_IPL_DRIVE	EQU	0001h	; IPL (Initial Program Load) FROM DISKETTE
				; (ie, diskette drives exist)

MFG_TEST	db	?	; 412h: INITIALIZATION FLAG
MEMORY_SIZE	dw	?	; 413h: MEMORY SIZE IN K BYTES
IO_RAM_SIZE	dw	?	; 415h: MEMORY IN I/O CHANNEL
KB_FLAG		db	?	; 417h: FIRST BYTE OF KEYBOARD STATUS
;
; KB_FLAG bits
;
INS_STATE	EQU	80h	; INSERT STATE IS ACTIVE
CAPS_STATE	EQU	40h	; CAPS LOCK STATE HAS BEEN TOGGLED
NUM_STATE	EQU	20h	; NUM LOCK STATE HAS BEEN TOGGLED
SCROLL_STATE	EQU	10h	; SCROLL LOCK STATE HAS BEEN TOGGLED
ALT_SHIFT	EQU	08h	; ALTERNATE SHIFT KEY DEPRESSED
CTL_SHIFT	EQU	04h	; CONTROL SHIFT KEY DEPRESSED
LEFT_SHIFT	EQU	02h	; LEFT SHIFT KEY DEPRESSED
RIGHT_SHIFT	EQU	01h	; RIGHT SHIFT KEY DEPRESSED

KB_FLAG_1	db	?	; 418h: SECOND BYTE OF KEYBOARD STATUS
ALT_INPUT	db	?	; 419h: STORAGE FOR ALTERNATE KEYPAD ENTRY
BUFFER_HEAD	dw	?	; 41Ah: POINTER TO HEAD OF KEYBOARD BUFFER
BUFFER_TAIL	dw	?	; 41Ch: POINTER TO TAIL OF KEYBOARD BUFFER
KB_BUFFER	dw     16 DUP(?); 41Eh: ROOM FOR 15 ENTRIES

SEEK_STATUS	db	?	; 43Eh: DRIVE RECALIBRATION STATUS
                        	;	BIT 3-0 = DRIVE 3-0 NEEDS RECAL BEFORE
                        	;	NEXT SEEK IF BIT IS = 0
INT_FLAG	EQU	80h	;	INTERRUPT OCCURRENCE FLAG
MOTOR_STATUS	db	?	; 43Fh: MOTOR STATUS
				;	BIT 3-0 = DRIVE 3-0 IS CURRENTLY RUNNING
				;	BIT 7 = CURRENT OPERATION IS A WRITE, REQUIRES DELAY
MOTOR_COUNT	db	?	; 440h: TIME OUT COUNTER FOR DRIVE TURN OFF
                        	;	37 = TWO SECONDS OF COUNTS FOR MOTOR TURN OFF
DISKETTE_STATUS	db	?	; 441h: SINGLE BYTE OF RETURN CODE INFO FOR STATUS
;
; DISKETTE_STATUS bits
;
TIME_OUT	EQU	80h	; ATTACHMENT FAILED TO RESPOND
BAD_SEEK	EQU	40h	; SEEK OPERATION FAILED
BAD_NEC		EQU	20h	; NEC CONTROLLER HAS FAILED
BAD_CRC		EQU	10h	; BAD CRC ON DISKETTE READ
DMA_BOUNDARY	EQU	09h	; ATTEMPT TO DMA ACROSS 64K BOUNDARY
BAD_DMA		EQU	08h	; DMA OVERRUN ON OPERATION
RECORD_NOT_FND	EQU	04h	; REQUESTED SECTOR NOT FOUND
WRITE_PROTECT	EQU	03h	; WRITE ATTEMPTED ON WRITE PROT DISK
BAD_ADDR_MARK	EQU	02h	; ADDRESS MARK NOT FOUND
BAD_CMD		EQU	01h	; BAD COMMAND PASSED TO DISKETTE I/O

NEC_STATUS	db	7 DUP(?); 442h: STATUS BYTES FROM NEC
;
; VIDEO DISPLAY DATA AREA
;
CRT_MODE	db	?	; 449h: CURRENT CRT MODE
CRT_COLS	dw	?	; 44Ah: NUMBER OF COLUMNS ON SCREEN
CRT_LEN		dw	?	; 44Ch: LENGTH OF REGEN IN BYTES
CRT_START	dw	?	; 44Eh: STARTING ADDRESS IN REGEN BUFFER
CURSOR_POSN	dw	8 DUP(?); 450h: CURSOR FOR EACH OF UP TO 8 PAGES
CURSOR_MODE	dw	?	; 460h: CURRENT CURSOR MODE SETTING
ACTIVE_PAGE	db	?	; 462h: CURRENT PAGE BEING DISPLAYED
ADDR_6845	dw	?	; 463h: BASE ADDRESS FOR ACTIVE DISPLAY CARD
CRT_MODE_SET	db	?	; 465h: CURRENT SETTING OF THE 3X8 REGISTER
CRT_PALLETTE	db	?	; 466h: CURRENT PALLETTE SETTING COLOR CARD
;
; CASSETTE DATA AREA
;
EDGE_CNT	dw	?	; 467h: PC: TIME COUNT AT DATA EDGE (word)
CRC_REG		dw	?	; 469h: PC: CRC REGISTER (word)
LAST_VAL	db	?	; 46Bh: PC: LAST INPUT VALUE (byte)
;
; TIMER DATA AREA
;
TIMER_LOW	dw	?	; 46Ch: LOW WORD OF TIMER COUNT
TIMER_HIGH	dw	?	; 46Eh: HIGH WORD OF TIMER COUNT
TIMER_OFL	db	?	; 470h: TIMER HAS ROLLED OVER SINCE LAST READ
;
; SYSTEM DATA AREA
;
BIOS_BREAK	db	?	; 471h: BIT 7 = 1 IF BREAK KEY HAS BEEN DEPRESSED
;
; RESET_FLAG is the traditional end of the RBDA, as originally defined by the IBM PC
;
RESET_FLAG	dw	?	; 472h: SET TO 0x1234 IF KEYBOARD RESET UNDERWAY

		db    	8Ch DUP(?)
;
; Define BASIC-DOS low memory usage, starting at offset 500h.
;
; Unfortunately, there's a byte at 500h (STATUS_BYTE) used by the ROM BIOS
; PRINT_SCREEN function, and apparently the ROM BASIC can use bytes from 510h
; through 51Dh.  There was also a DOS convention for using the byte at 504h
; to indicate whether the diskette drive in a single-drive system was operating
; as drive A (00h) or drive B (01h).
;
; Some DOS boot sectors would read the first directory sector into 500h,
; which would result in the starting clusters of IO.SYS and MSDOS.SYS residing
; in 51Ah and 53Ah, respectively.  Other boot sectors would create an 11-byte
; copy of the BIOS Diskette Parameters Table (DPT) at 522h.  We do the latter.
;
		db	4 dup (?)	; 500h: reserved
LOGICAL_DRIVE	db	?		; 504h: (00h for A: or 01h for B:)
FDC_UNITS	db	?		; 505h
FDC_DEVICE	dd	?		; 506h
		db	20 dup (?)	; reserved
DD_LIST		dd	?		; 51Eh: head of device driver list
DPT_ACTIVE	DPT	<>		; 522h: active DPT
BOOT_KEY	dw	?		; set by boot sector
		db	1 dup (?)	; paragraph padding
DDINT_ENTER	db	5 dup (?)	; room for a 5-byte far jump
DDINT_LEAVE	db	5 dup (?)	; room for a 5-byte far jump
		db	6 dup (?)	; paragraph padding
;
; We move the boot sector from BOOT_SECTOR to FAT_SECTOR.
;
BOOT_SECTOR	equ	7C00h
BOOT_SECTOR_LO	equ	550h
FAT_BUFHDR	BUFHDR	<>		; 540h
FAT_SECTOR	db	512 dup (?)	; 550h

DIR_BUFHDR	BUFHDR	<>		; 750h
DIR_SECTOR_OFF	equ	760h
DIR_SECTOR	db	512 dup (?)	; 760h
		ASSERT 	<offset IVT + DIR_SECTOR_OFF>,EQ,<offset DIR_SECTOR>

BIOS_END	label	byte		; 960h

BIOS		ends

;
; The ROM stores some BIOS offsets relative to segment 40h (eg, BUFFER_HEAD
; and BUFFER_TAIL), so if we want to use those offsets within BIOS segment 00h,
; we must add BIOS_DATA (ie, 400h) to them.
;
BIOS_DATA	equ	RS232_BASE

;
; BIOS-generated char codes and scan codes that we care about.
;
CHR_CTRLA	equ	01h
CHR_CTRLB	equ	02h
CHR_CTRLC	equ	03h
CHR_CTRLD	equ	04h	; alias for SCAN_RIGHT and SCAN_F1
CHR_CTRLE	equ	05h	; alias for SCAN_UP and SCAN_F3
CHR_CTRLF	equ	06h
CHR_CTRLG	equ	07h
CHR_BACKSPACE	equ	08h
CHR_TAB		equ	09h
CHR_LINEFEED	equ	0Ah
CHR_VTAB	equ	0Bh
CHR_RETURN	equ	0Dh
CHR_CTRLP	equ	10h
CHR_CTRLQ	equ	11h
CHR_CTRLR	equ	12h
CHR_CTRLS	equ	13h	; alias for SCAN_LEFT
CHR_CTRLT	equ	14h
CHR_CTRLU	equ	15h
CHR_CTRLV	equ	16h	; alias for SCAN_INS
CHR_CTRLW	equ	17h
CHR_CTRLX	equ	18h	; alias for SCAN_DOWN
CHR_CTRLY	equ	19h
CHR_CTRLZ	equ	1Ah
CHR_ESC		equ	1Bh
CHR_SPACE	equ	20h
CHR_DBLQUOTE	equ	22h
CHR_SLASH	equ	2Fh
CHR_DEL		equ	7Fh	; alias for SCAN_DEL

SCAN_TAB	equ	0Fh
SCAN_F1		equ	3Bh
SCAN_F2		equ	3Ch
SCAN_F3		equ	3Dh
SCAN_F4		equ	3Eh
SCAN_F5		equ	3Fh
SCAN_F6		equ	40h
SCAN_F7		equ	41h
SCAN_F8		equ	42h
SCAN_F9		equ	43h
SCAN_F10	equ	44h
SCAN_UP		equ	48h	; up-arrow
SCAN_LEFT	equ	4Bh	; left-arrow
SCAN_RIGHT	equ	4Dh	; right-arrow
SCAN_DOWN	equ	50h	; down-arrow
SCAN_INS	equ	52h	; ins
SCAN_DEL	equ	53h	; del


;
; Miscellaneous processor definitions (for lack of a better place)
;
FL_CARRY	equ	0001h
FL_ZERO		equ	0040h
FL_SIGN		equ	0080h
FL_TRAP		equ	0100h
FL_INTS		equ	0200h
FL_DOWN		equ	0400h
FL_OVFL		equ	0800h

OP_CALLF	equ	09Ah
OP_RETF		equ	0CBh
OP_IRET		equ	0CFh
OP_JMPF		equ	0EAh
OP_STC		equ	0F9h
