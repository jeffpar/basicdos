DIR_ENTRY	struc
DIR_NAME	db	11 dup (?)	; filename:
					; 1st byte = E5 -> free directory entry
					;	   = 00 -> end of allocated directory
DIR_ATTR	db	?		; attribute bits (see below)
DIR_PAD		db	10 dup (?)	; reserved for expansion
DIR_TIME	dw	?		; time of last write (see below)
DIR_DATE	dw	?		; date of last write (see below)
DIR_FIRST	dw	?		; first allocation unit of file
DIR_SIZE_L	dw	?		; low 16 bits of file size
DIR_SIZE_H	dw	?		; high 16 bits of file size
DIR_ENTRY	ends

DIR_ENTRY_SIZE	EQU	(size DIR_ENTRY); Size of directory entry in bytes
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
