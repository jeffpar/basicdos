	include	bios.inc
;
; Device Driver Header
;
DDH		struc
DDH_NEXT	dd	?	; 00h: pointer to next DDH (or xxxx:FFFFh)
DDH_ATTR	dw	?	; 04h: device attributes
DDH_STRATEGY	dw	?	; 06h: strategy entry point
DDH_INTERRUPT	dw	?	; 08h: interrupt entry point
DDH		ends

DDATTR_CHAR	equ	8000h	; set if character device, clear if block
DDATTR_BLOCK	equ	0000h
