;
; BASIC-DOS Video and Keyboard (VKD$) Device Driver Definitions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; The context and adapter definitions that the VKD$ driver's modules
; (condev.asm and convid.asm) share.
;
;
; A context of "80,25,1" requests a border, so logical cursor positions are
; 1,1 to 78,23.  Physical character and cursor positions will be adjusted by
; the offset address in CT_SCREEN.
;
CONTEXT		struc
CT_NEXT		dw	?	; 00h: segment of next context, 0 if end
CT_REFS		db	?	; 02h: # of references
CT_STATUS	db	?	; 03h: context status bits (CTSTAT_*)
CT_CONDIM	dw	?	; 04h: eg, context dimensions (0-based)
CT_CONPOS	dw	?	; 06h: eg, context position (X,Y) of top left
CT_CURPOS	dw	?	; 08h: eg, cursor X (lo) and Y (hi) position
CT_CURMIN	dw	?	; 0Ah: eg, cursor X (lo) and Y (hi) minimums
CT_CURMAX	dw	?	; 0Ch: eg, cursor X (lo) and Y (hi) maximums
CT_CURDIM	dw	?	; 0Eh: width and height (for cursor movement)
CT_EQUIP	dw	?	; 10h: BIOS equipment flags (snapshot)
CT_PORT		dw	?	; 12h: eg, 3D4h
CT_MODE		db	?	; 14h: active video mode (see MODE_*)
CT_SIG		db	?	; 15h: (holds SIG_CT in DEBUG builds)
CT_COLS		dw	?	; 16h: eg, 80 (50h; ie, column width of screen)
CT_PARENT	dw	?	; 18h: context that it took focus from
CT_SCREEN	dd	?	; 1Ah: eg, B800:00A2h with full-screen border
CT_COLOR	dw	?	; 1Eh: fill (LO) and border (HI) attributes
CT_CURTYPE	dw	?	; 20h: current cursor type (HI=top, LO=bottom)
CT_DEFTYPE	dw	?	; 22h: default cursor type (HI=top, LO=bottom)
;
; Context save region, used to save critical BIOS data area variables around
; BIOS operations.  TODO: Decide where/how to handle TBD variables.
;
CTS_MODE	db	?	; 24h: saves CRT_MODE before writing CT_MODE
CTS_PAGE	db	?	; 25h: saves ACTIVE_PAGE before writing TBD
CTS_COLS	dw	?	; 26h: saves CRT_COLS before writing CT_COLS
CT_SLOT		dw	?	; 28h: video memory selector ID (set_slot)
CTS_START	dw	?	; 2Ah: saves CRT_START before writing TBD
CTS_PORT	dw	?	; 2Ch: saves ADDR_6845 before writing CT_PORT
;
; The context's original mode and geometry, so that they can be restored when
; the mode is set back to the original mode (see update_mode).
;
CTO_MODE	db	?	; 2Eh: original video mode
CTO_STATUS	db	?	; 2Fh: original CTSTAT_BORDER
CTO_DIM		dw	?	; 30h: original columns (LO) and rows (HI)
CTO_POS		dw	?	; 32h: original position (X,Y) of top left
CT_SCAN		db	?	; 34h: pending scan code (see pull_kbd)
CT_PAGE		db	?	; 35h: video page (see get_start)
CTO_PAGE	db	?	; 36h: original video page
CT_SCRMIN	dw	?	; 37h: CT_CURMIN, with first scrolling row
CT_SCRMAX	dw	?	; 39h: CT_CURMAX, with last scrolling row
CONTEXT		ends
SIG_CT		equ	'C'

CTSTAT_BORDER	equ	01h	; context has border
CTSTAT_ADAPTER	equ	02h	; context is using alternate adapter
CTSTAT_SAME	equ	04h	; session's adapter requested (ddcon_open only)
CTSTAT_ABORT	equ	08h	; ABORT condition detected
CTSTAT_INT10	equ	10h	; context writes characters using INT 10h
CTSTAT_RAWKEYS	equ	20h	; hotkeys are just keys (see IOCTL_SETKEYS)
CTSTAT_INPUT	equ	40h	; context is waiting for input
CTSTAT_PAUSED	equ	80h	; context is paused (triggered by CTRLS hotkey)

ADAPTER_MDA	equ	01h	; MDA (port 3B4h) is present
ADAPTER_CGA	equ	02h	; CGA (port 3D4h) is present
ADAPTER_EGA	equ	04h	; and it's an EGA or VGA (see chk_snow)

PAGE_LEN	equ	4000	; bytes of a page that contexts use (80*25*2)
MAX_PAGES	equ	8	; pages per adapter (see CURSOR_POSN)

;
; CRT Controller Registers
;
CRTC_CURTOP	equ	0Ah	; cursor top (mirrored at CURSOR_MODE.HIB)
CRTC_STARTHI	equ	0Ch	; display start address (high)
CRTC_CURHI	equ	0Eh	; cursor start address (high)
