	include	bios.inc
	include	disk.inc

BOOTORG	equ	7C00h

	org	BOOTORG

CODE    SEGMENT

        ASSUME  CS:CODE, DS:NOTHING, ES:NOTHING, SS:BOOTSTACK

	jmp	short start
	nop
	BPB	<,512,1,1,2,64,320,PC160K,1,8,1,0>
start:	mov	ax,RBDA
	mov	ds,ax
	ASSUME	ds:RBDA
loop:	jmp	loop

CODE	ENDS

	end
