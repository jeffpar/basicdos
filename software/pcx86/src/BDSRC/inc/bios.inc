	include	disk.inc	; Disk structures
;
; Standard PC BIOS vectors (first few are really standard 8086 vectors)
;
; Page numbers are from the first IBM 5150 Technical Reference Manual (1981)
;
INT_DIV		EQU	00h	; #DE (divide error)
INT_STEP	EQU	01h	; #DB (debug aka single-step)
INT_NMI		EQU	02h	; NMI
INT_BP		EQU	03h	; #BP (breakpoint)
INT_OV		EQU	04h	; #OF (overflow)
INT_PRTSC	EQU	05h	; PRINT_SCREEN (p. A-79)
INT_VIDEO	EQU	10h	; VIDEO_IO (p. A-43)
INT_EQUIP	EQU	11h	; EQUIPMENT_DETERMINATION (p. A-67)
INT_MEMORY	EQU	12h	; MEMORY_SIZE_DETERMINE (p. A-67)
INT_DISK	EQU	13h	; DISKETTE_IO (p. A-32)
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
; INT_DISK functions
;
DISK_READ	EQU	02h	;
DISK_GETPARMS	EQU	08h	; DL=80h; DL:=# drives (if carry clear)

;
; INT_KBD functions
;
KBD_READ	EQU	00h	; returns char code in AL, scan code in AH
KBD_CHECK	EQU	01h	; returns ZF set if no key

;
; INT_TIME functions
;
TIME_GETTICKS	EQU	00h	; returns CX:DX, and AL != 0 if wrapped


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
EQUIP_FLAG	dw	?	; 400h: INSTALLED HARDWARE
;
; EQUIP_FLAG bits
;
EQ_NUM_PRINT	EQU	0C000h	; NUMBER OF PRINTERS ATTACHED
EQ_GAME_CTRL	EQU	1000h	; GAME I/O ATTACHED
EQ_NUM_RS232	EQU	0E00h	; NUMBER OF RS232 CARDS ATTACHED
EQ_NUM_DRIVES	EQU	00C0h	; NUMBER OF DISKETTE DRIVES (00=1, 01=2, 10=3,
				;	11=4) ONLY IF IPL_DRIVE SET
EQ_VIDEO_MODE	EQU	0030h	; INITIAL VIDEO MODE (00=UNUSED, 01=40X25 COLOR,
				;	10=80X25 COLOR, 11=80X25 MONO)
EQ_RAM_SIZE	EQU	00C0h	; PLANAR RAM SIZE (00=16K,01=32K,10=48K,11=64K)
EQ_IPL_DRIVE	EQU	0001h	; IPL (Initial Program Load) FROM DISKETTE (ie,
				;	diskette drives exist)

MFG_TEST	db	?	; 402h: INITIALIZATION FLAG
MEMORY_SIZE	dw	?	; 403h: MEMORY SIZE IN K BYTES
IO_RAM_SIZE	dw	?	; 405h: MEMORY IN I/O CHANNEL
KB_FLAG		db	?	; 407h: FIRST BYTE OF KEYBOARD STATUS
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
; copy of the BIOS Diskette Parameters Table at 522h.  We do the latter only.
;
		db	4 dup (?)	; 500h: reserved
LOGICAL_DRIVE	db	?		; 504h: (00h for A: or 01h for B:)
		db	29 dup (?)	; reserved
DPT_ACTIVE	DPT	<>		; 522h: active DPT
;
; We're going to move the boot sector from BOOT_SECTOR_HI to BOOT_SECTOR_LO,
; which overlaps where we'll maintain BPB_ACTIVE.
;
BOOT_SECTOR_HI	equ	7C00h
BOOT_SECTOR_LO	equ	0522h + size DPT

BOOT_SECTOR	db	3 dup (?)	; 52Dh: 3 bytes reserved for JMP
BPB_ACTIVE	BPB	<>		; 530h: active BPB

FAT_SECTOR	db	512 dup (?)	; 558h

DIR_SECTOR	db	512 dup (?)	; 758h
DIR_SECTOR_OFF	equ	758h
		ASSERT 	<offset IVT + DIR_SECTOR_OFF>,EQ,<offset DIR_SECTOR>

		dw	0EEEEh		; 958h (random marker)
		dw	147 dup (?)	; 95Ah
BIOS_STACK	equ	$		; A80h
BIOS_END	equ	0A80h
		ASSERT	<offset IVT + BIOS_END>,EQ,<offset BIOS_STACK>

BIOS		ends
