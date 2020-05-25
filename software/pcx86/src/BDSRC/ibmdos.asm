	include	dos.inc

	extrn	dosexit:near, doscall:near

CODE    segment byte public 'CODE'

	org	0000h

        ASSUME	CS:CODE, DS:BIOS_DATA, ES:BIOS_DATA, SS:BIOS_DATA

	call	init
done:	jmp	done

;
; Initialization code
;
init	proc	near
	int 3
	mov	si,offset int_tbl
	mov	di,INT_DOS_EXIT * 4
i1:	lodsw
	test	ax,ax
	jz	i9
	stosw
	mov	ax,cs
	stosw
	jmp	i1
i9:	ret
init	endp

int_tbl	dw	dosexit, doscall, 0

CODE	ends

	end
