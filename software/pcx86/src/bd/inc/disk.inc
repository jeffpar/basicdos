;
; BASIC-DOS Disk Structure Definitions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2021 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;

;
; Media IDs
;
MEDIA_160K	equ	0FEh
MEDIA_320K	equ	0FFh
MEDIA_180K	equ	0FCh
MEDIA_360K	equ	0FDh
MEDIA_HARD	equ	0F8h

BOOT_BPB	equ	3		; BPB offset within boot sector

;
; The venerable BIOS Parameter Block (BPB).
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
BPB_LARGESECS	dd	?		; 1Dh: if DISKSECS is 0 (see DOS 3.31)
;
; Our on-disk additions to the BPB, which make it easier for the boot code
; to do its job, among other things.
;
; Note that external legacy BPBs won't have these, so the FDC must calculate
; and add them as part of the BUILDBPB process.
;
BPB_DRIVE	db	?		; 21h: drive # (filled in by boot code)
BPB_CYLSECS	dw	?		; 22h: sectors per cylinder (eg, 8)
BPB_LBAROOT	dw	?		; 24h: LBA of 1st root dir sector
BPB_LBADATA	dw	?		; 26h: LBA of 1st data sector
BPB		ends
;
; Beyond our on-disk additions to the BPB, we also have internal additions,
; hence the extended BPB (BPBEX) structure.  We do this instead of defining yet
; another structure -- like, say, a Drive Parameter Block (DPB).
;
BPBEX		struc			; our internal structure for bpb_table
BPB_STRUC	db	size BPB dup (?)
BPB_TIMESTAMP	dd	?		; 28h: ticks from last refresh
BPB_DEVICE	dd	?		; 2Ch: device driver
BPB_SIG		db	?		; 30h: (holds SIG_BPB in DEBUG builds)
BPB_CLUSLOG2	db	?		; 31h: shift count for CLUSSECS
BPB_CLUSBYTES	dw	?		; 32h: BPB_CLUSSECS * BPB_SECBYTES
BPB_CLUSTERS	dw	?		; 34h: total clusters on disk
BPBEX		ends
SIG_BPB		equ	'B'

;
; Let's compare and contrast the BPB with the DPB, as it existed beginning
; with DOS 2.0.  If we ever decide to support INT 21h function DOS_DSK_GETDPB
; (32h), this is the (annoyingly different) structure we'd have to return.
;
; DPB		struc
; DPB_DRIVE	db	?		; 00h: drive number
; DPB_UNIT	db	?		; 01h: unit number
; DPB_SECBYTES	dw	?		; 02h: bytes per sector (eg, 0x200)
; DPB_CLUSSECS1	db	?		; 04h: sectors per cluster - 1
; DPB_CLUSLOG2	db	?		; 05h: shift count of cluster size
; DPB_RESSECS	dw	?		; 06h: reserved (boot) sectors
; DPB_FATS	db	?		; 08h: FAT copies (eg, 2)
; DPB_DIRENTS	dw	?		; 09h: root directory entries
; DPB_LBADATA	dw	?		; 0Bh: first data sector
; DPB_CLUSMAX	dw	?		; 0Dh: largest CLN (total clusters + 1)
; DPB_FATSECS	db	?		; 0Fh: sectors per FAT
; DPB_LBAROOT	dw	?		; 10h: first root directory sector
; DPB_DRIVER	dd	?		; 12h: address of device driver
; DPB_MEDIA	db	?		; 16h: media ID
; DPB_REBUILD	db	?		; 17h: 0FFh if block must be rebuilt
; DPB_NEXT	dd	?		; 18h: address of next DPB
; DPB_DIRCLUS	dw	?		; 1Ch: 1st cluster of cur dir (0=root)
; DPB_DIRPATH	db	64 dup (?)	; 1Eh: ASCIIZ cur dir path string
; DPB		ends
;
; Interesting side note about DPB_FATSECS: it was changed to a WORD in DOS 4.0,
; which had unfortunate side-effects (see Feb 1989 PC Tech Journal article by
; Ted Mirecki).
;

CLN_BAD		equ	0FF7h
CLN_END		equ	0FF8h

DIRENT		struc
DIR_NAME	db	11 dup (?)	; 00h: filename (E5=free, 00=end)
DIR_ATTR	db	?		; 0Bh: attribute bits (see below)
DIR_PAD		db	10 dup (?)	; 0Ch: reserved for expansion
DIR_TIME	dw	?		; 16h: time of last write (see below)
DIR_DATE	dw	?		; 18h: date of last write (see below)
DIR_CLN		dw	?		; 1Ah: first cluster number of file
DIR_SIZE	dd	?		; 1Ch: 32-bit file size
DIRENT		ends
;
;   Time:   Bits 0-4 = seconds/2, bits 5-10 = minute, 11-15 = hour
;   Date:   Bits 0-4 = day, bits 5-8 = month, bits 9-15 = year-1980
;
DIRENT_END	equ	00h		; optimization introduced in DOS 2
DIRENT_DELETED	equ	0E5h

DIRENT_SIZE	equ	(size DIRENT)	; 20h: size of directory entry in bytes

DIRATTR_RDONLY	equ	00000001b	; write protect attribute
DIRATTR_HIDDEN	equ	00000010b	; hidden file attribute
DIRATTR_SYSTEM	equ	00000100b	; system file attribute
DIRATTR_VOLUME	equ	00001000b	; volume name attribute
DIRATTR_SUBDIR	equ	00010000b	; directory attribute
DIRATTR_ARCHIVE	equ	00100000b	; backup attribute
