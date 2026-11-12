;
; BASIC-DOS V86 Utility Definitions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; V86.COM's modules: V86.ASM (startup, the machine's memory, and running it),
; V86DOS.ASM (DOS functions), V86PROC.ASM (memory blocks, loading programs,
; and FPU$), and V86UTIL.ASM (DOSUTIL functions, which ends with the heap).
;
	DOSPSP equ 1
	DOSFUNC equ 1
	include	macros.inc
	include	8086.inc
	include	bios.inc
	include	devapi.inc
	include	dosapi.inc
	include	cpu.inc
	include	v86.inc

;
; The machine's memory starts with its vectors (each pointing to its own HLT,
; at STUB_SEG:vector, so that the machine exits when a program's interrupt
; or exception goes to a default handler), then a copy of the BIOS data, the
; HLTs (and STUB_CTRLC, for the return from a program's CTRLC handler), and
; then MCBs, from ARENA_SEG to the end of its memory (V86_PARAS, unless the
; /M switch gave a size, from V86_MINK to V86_MAXK), for the programs' memory.
;
V86_MINK	equ	4	; least memory a machine can have, in K
V86_MAXK	equ	640	; and the most
V86_PARAS	equ	V86_MAXK SHL 6	; the default, in paragraphs
STUB_SEG	equ	0050h	; the HLTs (one for each vector)
STUB_CTRLC	equ	0100h	; (at STUB_SEG) a CTRLC handler's return
ARENA_SEG	equ	0061h	; the first MCB
ENV_PARAS	equ	40h	; size of the first program's environment
COM_MAX		equ	0FF00h - 2	; most of a COM program that can load
FL_RESULTS	equ	FL_CARRY OR FL_ZERO OR FL_SIGN OR FL_OVFL
PFT_LEN		equ	20	; (the size of PSP_PFT)

;
; The heap (VARS, after the image) holds the machine's registers, and then
; these buffers, followed by the stack.
;
NAME_LEN	equ	132		; (command lines are < 128 chars)
V_NAME		equ	size V86REGS	; the program's name, as given
V_PATH		equ	V_NAME + NAME_LEN	; with the directory found in
V_TAIL		equ	V_PATH + NAME_LEN + 16	; a command tail (for a PSP)
V_EPB		equ	V_TAIL + 128	; an EPB (or SPB)
V_HDR		equ	V_EPB + 24	; an EXE header (or a far pointer)
V_FCB		equ	V_HDR + 32	; an FCB (from DOS_FCB_PARSE)
V_REFS		equ	V_FCB + 40	; references to each SFH (see sfh_ref)
V_BUF		equ	V_REFS + 256	; (relocations, strings, tokens)
BUF_LEN		equ	512
V_STUB		equ	V_BUF + BUF_LEN	; INT 2Bh and a format (uprintf)
STUB_LEN	equ	512
V_PARMS		equ	V_STUB + STUB_LEN	; its parameters
PARMS_LEN	equ	256
V_END		equ	V_PARMS + PARMS_LEN
STACK_LEN	equ	2048
