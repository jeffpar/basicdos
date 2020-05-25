	include	macros.inc
;
; Media IDs
;
MEDIA_160K	equ	0FEh
MEDIA_320K	equ	0FFh
MEDIA_180K	equ	0FCh
MEDIA_360K	equ	0FDh
MEDIA_HARD	equ	0F8h

;
; The venerable BIOS Parameter Block.
;
BPB		struc
BPB_OEM		db	"PCJS.ORG"	; 00h: OEM signature
BPB_SECBYTES	dw	?		; 08h: bytes per sector (eg, 0x200)
BPB_CLUSSECS	db	?		; 0Ah: sectors per cluster (eg, 1)
BPB_RESSECS	dw	?		; 0Bh: reserved sectors (before FAT)
BPB_FATS	db	?		; 0Dh: FAT copies (eg, 2)
BPB_DIRENTS	dw	?		; 0Eh: root directory entries
BPB_DISKSECS	dw	?		; 10h: number of sectors on disk
BPB_MEDIA	db	?		; 12h: media ID; should match FAT ID
BPB_FATSECS	dw	?		; 13h: sectors per FAT (eg, 1)
BPB_TRACKSECS	dw	?		; 15h: sectors per track (eg, 8)
BPB_DRIVEHEADS	dw	?		; 17h: number of heads (eg, 1)
BPB_HIDDENSECS	dd	?		; 19h: number of hidden sectors
BPB_LARGESECS	dd	?		; 1Dh: if TOTALSECS is 0 (see DOS 3.31)
;
; BPB extensions
;
BPB_DRIVE	db	?		; 21h: physical drive #
BPB_LBAROOT	dw	?		; 22h: LBA of 1st root dir sector
BPB_LBADATA	dw	?		; 24h: LBA of 1st data sector
BPB		ends

DIRENT		struc
DIR_NAME	db	11 dup (?)	; filename:
					; 1st byte = E5 -> free entry
					;	   = 00 -> end of directory
DIR_ATTR	db	?		; attribute bits (see below)
DIR_PAD		db	10 dup (?)	; reserved for expansion
DIR_TIME	dw	?		; time of last write (see below)
DIR_DATE	dw	?		; date of last write (see below)
DIR_CLN		dw	?		; first cluster number of file
DIR_SIZE_L	dw	?		; low 16 bits of file size
DIR_SIZE_H	dw	?		; high 16 bits of file size
DIRENT		ends

DIRENT_SIZE	EQU	(size DIRENT)	; Size of directory entry in bytes
;
;   Time:   Bits 0-4 = seconds/2, bits 5-10 = minute, 11-15 = hour
;   Date:   Bits 0-4 = day, bits 5-8 = month, bits 9-15 = year-1980
;
ATTR_READ_ONLY	equ	00000001b	; write protect attribute
ATTR_HIDDEN	equ	00000010b	; hidden file attribute
ATTR_SYSTEM	equ	00000100b	; system file attribute
ATTR_VOLUME_ID	equ	00001000b	; volume name attribute
ATTR_DIRECTORY	equ	00010000b	; directory attribute
ATTR_ARCHIVE	equ	00100000b	; backup attribute
