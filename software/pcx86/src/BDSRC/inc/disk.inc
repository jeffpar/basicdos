;
; Media IDs
;
MEDIA_160K	equ	0FEh
MEDIA_320K	equ	0FFh
MEDIA_180K	equ	0FCh
MEDIA_360K	equ	0FDh
MEDIA_HARD	equ	0F8h

BPB		struc
BPB_OEM		db	"PCJS.ORG"	; 03h: OEM signature
BPB_SECBYTES	dw	?		; 0Bh: bytes per sector (eg, 0x200)
BPB_CLUSSECS	db	?		; 0Dh: sectors per cluster (eg, 1)
BPB_RESSECS	dw	?		; 0Eh: reserved sectors (pre-FAT)
BPB_FATS	db	?		; 10h: FAT copies (eg, 2)
BPB_DIRENTS	dw	?		; 11h: root directory entries
BPB_TOTALSECS	dw	?		; 13h: number of total sectors
BPB_MEDIA	db	?		; 15h: media ID; should match FAT ID
BPB_FATSECS	dw	?		; 16h: sectors per FAT (eg, 1)
BPB_TRACKSECS	dw	?		; 18h: sectors per track (eg, 8)
BPB_TOTALHEADS	dw	?		; 1Ah: number of heads (eg, 1)
BPB_HIDDENSECS	dw	?		; 1Ch: number of hidden sectors
BPB		ends

DIRENT		struc
DIR_NAME	db	11 dup (?)	; filename:
					; 1st byte = E5 -> free entry
					;	   = 00 -> end of directory
DIR_ATTR	db	?		; attribute bits (see below)
DIR_PAD		db	10 dup (?)	; reserved for expansion
DIR_TIME	dw	?		; time of last write (see below)
DIR_DATE	dw	?		; date of last write (see below)
DIR_FIRST	dw	?		; first allocation unit of file
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
