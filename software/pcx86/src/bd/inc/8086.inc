;
; BASIC-DOS ROM BIOS Interface and Data Area Definitions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2021 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;

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
OP_POP_DS	equ	01Fh
OP_SEG_ES	equ	026h
OP_PUSH_AX	equ	050h
OP_PUSH_DX	equ	052h
OP_PUSH_BX	equ	053h
OP_PUSH_BP	equ	055h
OP_PUSH_DI	equ	057h
OP_POP_AX	equ	058h
OP_POP_DX	equ	05Ah
OP_POP_BP	equ	05Dh
OP_NOP		equ	090h
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
OP_INT03	equ	0CCh		; INT3
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

OP_INT06	equ	006CDh		; INT 06h
OP_INT20	equ	020CDh		; INT 20h
OP_INT21	equ	021CDh		; INT 21h
OP_POP_BP8	equ	0468Fh		; POP [BP+nn]
OP_POP_BP16	equ	0868Fh		; POP [BP+nnnn]
OP_ZERO_AX	equ	0C031h		; XOR AX,AX
OP_MOV_DS_AX	equ	0D88Eh		; MOV DS,AX
OP_MOV_ES_AX	equ	0C08Eh		; MOV ES,AX
OP_MOV_AX_SP	equ	089E0h		; MOV AX,SP
OP_POP_DX_AX	equ	05A58h		; POP AX, POP DX
OP_OR_AX_DX	equ	0D009h		; OR  AX,DX
OP_JZ_SELF	equ	0FE74h		; JZ  $
OP_MOV_BP_SP	equ	0E589h		; MOV BP,SP
OP_MOV_SP_BP	equ	0EC89h		; MOV SP,BP
OP_PUSH_BP8	equ	076FFh		; PUSH [BP+nn]
OP_PUSH_BP16	equ	0B6FFh		; PUSH [BP+nnnn]
