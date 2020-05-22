	include	bios.inc		; BIOS data
	include	disk.inc		; Disk structures
	include	macros.inc
;
; Define BASIC-DOS low memory usage, starting at BIOS DATA offset 500h.
;
; Unfortunately, there's a byte at 50:00h (STATUS_BYTE) used by the ROM BIOS
; PRINT_SCREEN function, and apparently the ROM BASIC can use bytes from 50:10h
; through 50:1Dh.  There was also a DOS convention for using the byte at 50:04h
; to indicate whether the diskette drive in a single-drive system was operating
; as drive A (00h) or drive B (01h).
;
; Some DOS boot sectors would read the first directory sector into 50:00h,
; which would result in the starting clusters of IO.SYS and MSDOS.SYS residing
; in 50:1Ah and 50:3Ah, respectively.  Other sectors would create an 11-byte
; copy of the BIOS Diskette Parameters table at 50:22h.  We do the latter only.
;
BDIO		SEGMENT AT 00h
		db	500h dup (?)
		db	4 dup (?)	; 500h: reserved
LOGICAL_DRIVE	db	1 dup (?)	; 504h: (00h for A: or 01h for B:)
		db	29 dup (?)	; reserved
DPT_COPY	DPT	<>		; copy of DPT (created by boot sector)
BPB_COPY	BPB	<>
FAT_BUFFER	db	512 dup (?)
DIR_BUFFER	db	512 dup (?)
BDIO		ENDS
