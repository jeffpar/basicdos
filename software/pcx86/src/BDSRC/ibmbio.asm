	include	bios.inc

CODE    segment

	org	0000h

        ASSUME	CS:CODE, DS:BIOS_DATA, ES:BIOS_DATA, SS:BIOS_DATA

	jmp	init
;
; Put device drivers here
;
init:	int 3

CODE	ends

	end
