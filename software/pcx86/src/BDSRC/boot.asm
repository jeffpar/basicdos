	include	fat.inc

BOOTORG	equ	7C00h

	org	BOOTORG

CODE    SEGMENT

        ASSUME  CS:CODE,DS:CODE,ES:CODE,SS:CODE

	jmp	start
	db	90h
start:

CODE	ENDS

	end
