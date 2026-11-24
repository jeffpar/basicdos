;
; BASIC-DOS Sound Device (SND$) Definitions
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; SND$ owns a Sound Blaster (its ports, its DMA channel, and its IRQ), and
; lends it to one V86 machine at a time (see v86.inc), whose host (eg,
; V86.COM) opens SND$ and sends it these IOCTLs; only SND$ and the host
; include this file.  Each open gets a context of its own, and the card goes
; back to SND$ (reset, with its DMA channel masked) when the handle that
; borrowed it closes, which DOS does for a program that ends without closing
; it (eg, after a CTRL-ALT-DEL).
;
;	IOCTL_SNDLEND with DX = the machine's first selector lends the card to
;	that machine: CPU$ gives the machine the card's ports, and the FM
;	synthesizer's (see CPU_V86), and SND$ counts the card's interrupts at
;	SND_IRQS in the machine.  It returns DL = the IRQ and DH = the DMA
;	channel, or fails if another machine has the card.
;
;	IOCTL_SNDDMA does an IN (CH = 0) or OUT (CH = 1) of DL at DMA port CL
;	(00h-0Fh, or 80h-8Fh for the page registers), and returns DL = the byte
;	for an IN.  SND$ keeps a virtual DMA controller for the machine, and
;	programs the real one for the card's channel only, with the machine's
;	addresses translated to physical ones; the other channels' ports read
;	as zero, and writing them does nothing.
;
; The host gives the machine an interrupt (INT 08h plus the IRQ) for each one
; that SND$ counted, and the machine's handler acknowledges the card itself.
;
IOCTL_SND	equ	0E8h
IOCTL_SNDLEND	equ	0E9h	; SND$: lend the card to machine (DX)
IOCTL_SNDDMA	equ	0EAh	; SND$: IN (CH=0) or OUT (CH=1) DL at port CL

SND_IRQS	equ	5EFh	; (in the machine) interrupts not given yet
