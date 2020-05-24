	include	bios.inc

CODE    segment

	org	0000h

        ASSUME	CS:CODE, DS:BIOS_DATA, ES:BIOS_DATA, SS:BIOS_DATA

	jmp	init
;
; Initialization code
;
init:	int 3

CODE	ends

	end
