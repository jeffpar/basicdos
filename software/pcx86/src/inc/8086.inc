;
; BASIC-DOS ROM BIOS Interface and Data Area Definitions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	include	macros.inc
;
; Processor-defined interrupt vectors
;
INT_DV		EQU	00h	; #DE (divide error)
INT_DB		EQU	01h	; #DB (debug aka single-step)
INT_NMI		EQU	02h	; NMI
INT_BP		EQU	03h	; #BP (breakpoint)
INT_OF		EQU	04h	; #OF (overflow)

REG16	struc
LOB		db	?
HIB		db	?
REG16	ends

REG32	struc
LOW		dw	?
HIW		dw	?
REG32	ends

FARPTR	struc
OFF		dw	?
SEG		dw	?
FARPTR	ends

;
; Processor flag definitions
;
FL_CARRY	equ	0001h
FL_ZERO		equ	0040h
FL_SIGN		equ	0080h
FL_TRAP		equ	0100h
FL_INTS		equ	0200h
FL_DOWN		equ	0400h
FL_OVFL		equ	0800h

;
; Processor opcode definitions
;
OP_PUSH_ES	equ	006h
OP_PUSH_CS	equ	00Eh
OP_PUSH_SS	equ	016h
OP_PUSH_DS	equ	01Eh
OP_PUSH_AX	equ	050h
OP_PUSH_DX	equ	052h
OP_PUSH_BX	equ	053h
OP_PUSH_DI	equ	057h
OP_XCHG_DX	equ	092h
OP_CALLF	equ	09Ah
OP_LODSW	equ	0ADh
OP_MOV_AL	equ	0B0h
OP_MOV_AX	equ	0B8h
OP_MOV_CX	equ	0B9h
OP_MOV_BX	equ	0BBh
OP_MOV_SI	equ	0BEh
OP_MOV_DI	equ	0BFh
OP_RETF_N	equ	0CAh
OP_RETF		equ	0CBh
OP_IRET		equ	0CFh
OP_CALL		equ	0E8h
OP_JMPF		equ	0EAh
OP_STC		equ	0F9h

OP_ZERO_AX	equ	0C031h		; XOR AX,AX
OP_MOV_AX_SP	equ	089E0h		; MOV AX,SP
