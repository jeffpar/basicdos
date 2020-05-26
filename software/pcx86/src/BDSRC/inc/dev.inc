	include	bios.inc
;
; Device Driver Header
;
DDH		struc
DDH_NEXT_OFF	dw	?	; 00h: offset of next DDH (or FFFFh)
DDH_NEXT_SEG	dw	?	; 02h: segment of next DDH
DDH_ATTR	dw	?	; 04h: device attributes
DDH_STRATEGY	dw	?	; 06h: strategy entry point
DDH_INTERRUPT	dw	?	; 08h: interrupt entry point
DDH_NAME	dq	?	; 0Ah: device name
DDH_INIT	dw	?	; 12h: initialization handler
DDH		ends

DDATTR_CHAR	equ	8000h	; set if character device, clear if block
DDATTR_BLOCK	equ	0000h
