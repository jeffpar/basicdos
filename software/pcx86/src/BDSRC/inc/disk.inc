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
; The venerable BPB: BIOS Parameter Block
;
BPB		struc
BPB_OEM		db	"PCJS.ORG"	; 00h: OEM signature
BPB_SECBYTES	dw	?		; 08h: bytes per sector (eg, 0x200)
BPB_CLUSSECS	db	?		; 0Ah: sectors per cluster (eg, 1)
BPB_RESSECS	dw	?		; 0Bh: reserved (boot) sectors
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
; Our additions to internal BPBs
;
BPB_DRIVE	db	?		; 21h: physical drive #
BPB_CYLSECS	dw	?		; 22h: sectors per cylinder (eg, 8)
BPB_LBAROOT	dw	?		; 24h: LBA of 1st root dir sector
BPB_LBADATA	dw	?		; 26h: LBA of 1st data sector
BPB		ends

;
; Let's compare and contrast the BPB with the DPB: Drive Parameter Block
;
DPB		struc
DPB_DRIVE	db	?		; 00h: drive number
DPB_UNIT	db	?		; 01h: unit number
DPB_SECBYTES	dw	?		; 02h: bytes per sector
DPB_CLUSSECS_1	db	?		; 04h: sectors per cluster - 1
DPB_CLUSLOG_2	db	?		; 05h: shift count of cluster size
DPB_RESSECS	dw	?		; 06h: reserved (boot) sectors
DPB_FATS	db	?		; 08h: FAT copies
DPB_DIRENTS	dw	?		; 09h: root directory entries
DPB_LBADATA	dw	?		; 0Bh: first data sector
DPB_CLUSMAX	dw	?		; 0Dh: largest CLN (total clusters + 1)
DPB_FATSECS	db	?		; 0Fh: sectors per FAT [2.0]
DPB_LBAROOT	dw	?		; 10h: first root directory sector [2.0]
DPB_DRIVER	dd	?		; 12h: address of device driver [2.0]
DPB_MEDIA	db	?		; 16h: media ID [2.0]
;
; DOS 2.0 added more, but let's stop here for now.  So, lots of annoying
; differences, which seems odd, since the DPB was first defined in DOS 1.x.
;
DPB		ends

CLN_BAD		equ	0FF7h
CLN_END		equ	0FF8h

DIRENT		struc
DIR_NAME	db	11 dup (?)	; 00h: filename (E5=free,00=end)
DIR_ATTR	db	?		; 0Bh: attribute bits (see below)
DIR_PAD		db	10 dup (?)	; 0Ch: reserved for expansion
DIR_TIME	dw	?		; 16h: time of last write (see below)
DIR_DATE	dw	?		; 18h: date of last write (see below)
DIR_CLN		dw	?		; 1Ah: first cluster number of file
DIR_SIZE_L	dw	?		; 1Ch: low 16 bits of file size
DIR_SIZE_H	dw	?		; 1Eh: high 16 bits of file size
DIRENT		ends

DIRENT_SIZE	equ	(size DIRENT)	; 20h: size of directory entry in bytes
;
;   Time:   Bits 0-4 = seconds/2, bits 5-10 = minute, 11-15 = hour
;   Date:   Bits 0-4 = day, bits 5-8 = month, bits 9-15 = year-1980
;
DIRATTR_RDONLY	equ	00000001b	; write protect attribute
DIRATTR_HIDDEN	equ	00000010b	; hidden file attribute
DIRATTR_SYSTEM	equ	00000100b	; system file attribute
DIRATTR_VOLUME	equ	00001000b	; volume name attribute
DIRATTR_SUBDIR	equ	00010000b	; directory attribute
DIRATTR_ARCHIVE	equ	00100000b	; backup attribute
