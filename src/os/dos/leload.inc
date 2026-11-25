;
; BASIC-DOS LE Program Definitions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; The layout of le_host's data, which follows the PSP in an LE program's PSP
; block, as load_le sets it up (see leload.asm) and le_host uses it (see
; lehost.asm), the offsets in its fault message (see LE_INIT), and the
; flat machine's page size (see le_mapseg).
;
LE_PGSIZE	equ	1000h		; the only page size we load
LE_MSGLEN	equ	42		; length of the fault message
LED_MACH	equ	size PSP	; word: the flat machine
LED_REGS	equ	LED_MACH + 2	; V86REGS: its registers
LED_DS		equ	LED_REGS + size V86REGS	; word: DS for a DOS call
LED_ES		equ	LED_DS + 2	; word: ES for a DOS call
LED_PTR		equ	LED_ES + 2	; dword: a transfer's next address
LED_CNT		equ	LED_PTR + 4	; dword: bytes left to transfer
LED_TOT		equ	LED_CNT + 4	; dword: bytes transferred
LED_MSG		equ	LED_TOT + 4	; fault message (see LE_INIT)
LED_TBL		equ	LED_MSG + LE_MSGLEN	; function table (see LE_INIT)
LE_MSGVEC	equ	10		; offsets of the vector,
LE_MSGERR	equ	17		; error code,
LE_MSGSEG	equ	26		; and address
