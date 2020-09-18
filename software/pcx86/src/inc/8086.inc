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
INT_DV		EQU	00h	; #DE (divide error exception)
INT_DB		EQU	01h	; #DB (debug aka single-step exception)
INT_NMI		EQU	02h	; NMI (non-maskable interrupt)
INT_BP		EQU	03h	; #BP (breakpoint trap)
INT_OF		EQU	04h	; #OF (overflow trap)
INT_BR		EQU	05h	; #BR (BOUND error fault; 80186 and up)
INT_UD		EQU	06h	; #UD (undefined opcode fault; 80186 and up)

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
FL_DEFAULT	equ    0F202h

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
OP_POP_AX	equ	058h
OP_POP_DX	equ	05Ah
OP_XCHG_DX	equ	092h
OP_CWD		equ	099h
OP_CALLF	equ	09Ah		; 32-bit absolute address
OP_LODSW	equ	0ADh
OP_MOV_AL	equ	0B0h
OP_MOV_AX	equ	0B8h
OP_MOV_CX	equ	0B9h
OP_MOV_BX	equ	0BBh
OP_MOV_SI	equ	0BEh
OP_MOV_DI	equ	0BFh
OP_RETF_N	equ	0CAh
OP_RETF		equ	0CBh
OP_INT3		equ	0CCh
OP_IRET		equ	0CFh
OP_CALL		equ	0E8h		; 16-bit displacement
OP_JMP		equ	0E9h		; 16-bit displacement
OP_JMPF		equ	0EAh		; 32-bit absolute address
OP_CLC		equ	0F8h
OP_STC		equ	0F9h
OP_CLI		equ	0FAh
OP_STI		equ	0FBh
OP_CLD		equ	0FCh
OP_STD		equ	0FDh

OP_INT21	equ	021CDh		; INT 21h
OP_ZERO_AX	equ	0C031h		; XOR AX,AX
OP_MOV_AX_SP	equ	089E0h		; MOV AX,SP
OP_POP_DX_AX	equ	05A58h		; POP AX, POP DX
OP_OR_AX_DX	equ	0D009h		; OR  AX,DX
OP_JZ_SELF	equ	0FE74h		; JZ  $
OP_MOV_BP_SP	equ	0E589h		; MOV BP,SP
OP_MOV_SP_BP	equ	0EC89h		; MOV SP,BP

;
; Operation checks are sprinkled throughout DEBUG BASIC-DOS binaries to
; signal assertion failures and internal breakpoints, and also to perform
; arithmetic validation tests in the PCjs emulator.  They invoke INT_UD
; (INT 06h) to trigger the operation, since that interrupt had no defined
; purpose on 8086/8088 processors (every opcode did something).  The concept
; of invalid opcodes came later, with the introduction of the 80186.
;
; With the exception of OP_ASSERT, these operations should have no effect
; in a non-PCjs environment (or on a real machine), since BASIC-DOS system
; initialization installs an INT_UD handler to deal with them.  And if you
; somehow run a DEBUG binary on a non-DEBUG system, INT_UD will still be
; set to an IRET, so the binaries should still run, albeit with side-effects.
;
OP_DBGBRK	equ	0CCh		; signal an internal breakpoint
OP_ASSERT	equ	0F9h		; signal an assertion failure
OP_MUL32	equ	0FBh		; verify 32-bit multiplication result
OP_DIV32	equ	0FCh		; verify 32-bit division result

OPCHECK	macro	op
	IFDEF DEBUG
	int	INT_UD			;; INT 06h
	db	op			;; next byte indicates the operation
	ENDIF
	endm
