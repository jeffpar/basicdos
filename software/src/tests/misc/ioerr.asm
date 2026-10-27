;
; BASIC-DOS File I/O Error Tests
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
	DOSPSP equ 1
	DOSFUNC equ 1
	include	macros.inc
	include	dosapi.inc
	include	8086.inc

CODE	SEGMENT
	ASSUME	CS:CODE, DS:CODE, ES:CODE, SS:CODE
	org	100h
;
; Run IOERR.BAS in COMMAND /C with an INT 21h hook that can return errors
; or a short write for a selected handle.  Test-only IOCTLs F0h and F1h arm
; a fault and report the BASIC test result.  All other calls go to DOS.
;
; Then run the real VI with scripted keys: insert text, :wq, :q, :q!.
; A failed save must consume the final :q!; a successful save must exit at
; :wq.  Faults cover close failure, write failure, and short writes.
;
DEFPROC	main
	cld
	mov	dx,offset starting
	call	print
;
; BASIC-DOS puts COMSPEC first in the environment.  Use its drive for the
; executables so the test can also run from the separate tests diskette.
;
	mov	es,ds:[PSP_ENVSEG]
	mov	al,es:[8]
	mov	[command],al
	mov	[vi_program],al
	DOSUTIL	GETCSN			; CL = our session # (see dos_hook)
	mov	[session],cl
	mov	ax,(DOS_MSC_GETVEC SHL 8) OR 21h
	int	21h
	mov	[old_dos].OFF,bx
	mov	[old_dos].SEG,es
	push	cs
	pop	es
	mov	[exec_parms].EPB_CMDTAIL.OFF,offset cmd_tail
	mov	[exec_parms].EPB_CMDTAIL.SEG,cs
	mov	[exec_parms].EPB_FCB1.SEG,cs
	mov	[exec_parms].EPB_FCB2.SEG,cs
	mov	dx,offset dos_hook
	mov	ax,(DOS_MSC_SETVEC SHL 8) OR 21h
	int	21h
	mov	dx,offset command
	call	run
	jc	m1
	cmp	[basic_result],0		; BASIC must report every check successful
	jne	m1
	cmp	[arms],6		; all six BASIC fault cases must run
	jne	m1
	cmp	[hits],6		; every armed fault must be exercised
	je	m2
m1:
	mov	[bad],1
m2:
	mov	si,offset vi_cases
m3:
	mov	[vi_active],0
	mov	[fault_mode],0
	mov	dx,offset vi_file
	mov	ah,DOS_DSK_DELETE
	int	21h			; each VI case starts with a fresh file
	mov	[vi_active],1
	lodsb
	mov	[vi_fault],al
	mov	[keyptr],offset keys
	mov	[key_overrun],0
	mov	[exec_parms].EPB_CMDTAIL.OFF,offset vi_tail
	push	si
	mov	dx,offset vi_program
	call	run
	pop	si
	jc	m4
	mov	ax,offset keys_end
	cmp	[vi_fault],0		; the successful :wq should exit earlier
	jne	m3a
	mov	ax,offset keys_saved
m3a:
	cmp	[keyptr],ax		; failed saves must remain open and modified
	jne	m4
	cmp	[key_overrun],0		; no unexpected input requests are allowed
	je	m5
m4:
	mov	[bad],1
m5:
	cmp	[vi_fault],0		; the success case is last
	je	m6
	jmp	m3
m6:
	mov	[vi_active],0
	push	ds
	lds	dx,[old_dos]
	mov	ax,(DOS_MSC_SETVEC SHL 8) OR 21h
	int	21h
	pop	ds
	mov	dx,offset vi_file
	mov	ah,DOS_DSK_DELETE
	int	21h
	cmp	[arms],9		; six BASIC faults and three VI faults
	jne	m8
	cmp	[hits],9		; no fault may be skipped or repeated
	jne	m8
	cmp	[bad],0			; did any child or state check fail?
	jne	m8
	mov	dx,offset passed
	call	print
	mov	ax,DOS_PSP_RETURN SHL 8
	int	21h
m8:
	mov	dx,offset failed
	call	print
	mov	ax,(DOS_PSP_RETURN SHL 8) OR 1
	int	21h
ENDPROC	main

;
; run
;
; Execute DS:DX with the current command tail, preserving the parent's
; registers.  Carry reports either a load error or a nonzero child exit.
;
DEFPROC	run
	push	bx
	mov	bx,offset exec_parms
	mov	ax,DOS_PSP_EXEC
	int	21h
	jc	r9
	mov	ah,DOS_PSP_RETCODE
	int	21h
	cmp	ax,0			; the child must terminate normally with code 0
	je	r9
	stc
r9:
	pop	bx
	ret
ENDPROC	run

;
; dos_hook
;
; Modes: 1 = seek error, 2 = read error, 3 = write error, 4 = short write,
; 5 = close error.  Close really closes the handle before returning the
; simulated commit error, as BASIC-DOS does for an actual commit failure.
;
; INT 21h is shared by every session, so calls from other sessions (eg, one
; running STRESS) go straight to DOS; otherwise, their handles and input could
; trigger our faults and consume our keys.
;
DEFPROC	dos_hook,far
	push	ax
	push	cx
	DOSUTIL	GETCSN			; CL = current session #
	cmp	cl,cs:[session]		; is it our session?
	pop	cx
	pop	ax
	je	h0
	jmp	cs:[old_dos]		; no
h0:
	push	ds
	push	cs
	pop	ds			; DS = CS (for the test state below)
	cmp	ah,DOS_HDL_IOCTL		; test-only control requests?
	jne	h1
	cmp	al,0F0h			; arm a fault on the supplied file handle?
	jne	h0a
	mov	[fault_mode],cl
	mov	[fault_handle],bx
	inc	[arms]
	xor	ax,ax
	jmp	h_ok
h0a:
	cmp	al,0F1h			; report the BASIC test result?
	jne	h1
	mov	[basic_result],cl
	xor	ax,ax
	jmp	h_ok
h1:
	cmp	[vi_active],0		; are we running VI?
	je	h2
	cmp	ah,DOS_TTY_IN		; supply the next scripted key?
	jne	h1a
	push	si
	mov	si,[keyptr]
	mov	al,[si]
	inc	si
	test	al,al			; did VI request input past the script?
	jnz	h1k
	mov	[key_overrun],1
	mov	si,offset force_quit
	lodsb
h1k:
	mov	[keyptr],si
	pop	si
	jmp	h_ok
h1a:
	cmp	ah,DOS_HDL_CREATE	; arm VI's fault after its output file opens
	jne	h2
	pop	ds			; DS:DX -> caller's filename
	push	ds
	pushf
	call	cs:[old_dos]
	push	cs
	pop	ds
	jnc	h1b
	jmp	h_err
h1b:
	mov	[fault_handle],ax
	cmp	[vi_fault],0		; no fault in the successful save case
	jne	h1c
	jmp	h_ok
h1c:
	push	ax
	mov	al,[vi_fault]
	mov	[fault_mode],al
	pop	ax
	inc	[arms]
	jmp	h_ok
h2:
	cmp	bx,[fault_handle]	; affect only the selected handle
	je	h2a
	jmp	h_forward
h2a:
	cmp	[fault_mode],1		; failing a seek?
	jne	h3
	cmp	ah,DOS_HDL_SEEK		; leave other operations alone
	je	h_fail
	jmp	short h_forward
h3:
	cmp	[fault_mode],2		; failing a read?
	jne	h4
	cmp	ah,DOS_HDL_READ		; leave other operations alone
	je	h_fail
	jmp	short h_forward
h4:
	cmp	[fault_mode],3		; failing a write?
	je	h4a
	cmp	[fault_mode],4		; or returning a short write?
	jne	h5
h4a:
	cmp	ah,DOS_HDL_WRITE		; leave other operations alone
	jne	h_forward
	cmp	[fault_mode],4		; short writes succeed (smaller count)
	jne	h_fail
	mov	[fault_mode],0
	inc	[hits]
	mov	ax,cx
	dec	ax
	jmp	short h_ok
h5:
	cmp	[fault_mode],5		; failing a close/commit?
	jne	h_forward
	cmp	ah,DOS_HDL_CLOSE		; leave other operations alone
	jne	h_forward
	mov	[fault_mode],0
	inc	[hits]
	pushf
	call	cs:[old_dos]
	jmp	short h_error
h_fail:
	mov	[fault_mode],0
	inc	[hits]
h_error:
	mov	ax,ERR_GENFAIL
h_err:
	pop	ds
	push	bp
	mov	bp,sp
	or	word ptr [bp+6],FL_CARRY
	pop	bp
	iret
h_forward:
	pop	ds
	jmp	cs:[old_dos]
h_ok:
	pop	ds
	push	bp
	mov	bp,sp
	and	word ptr [bp+6],NOT FL_CARRY
	pop	bp
	iret
ENDPROC	dos_hook

DEFPROC	print
	mov	ah,DOS_TTY_PRINT
	int	21h
	ret
ENDPROC	print

old_dos		dd	0
fault_handle	dw	0
fault_mode	db	0
session		db	0
basic_result	db	0FFh
arms		db	0
hits		db	0
bad		db	0
vi_active	db	0
vi_fault	db	0
key_overrun	db	0
keyptr		dw	keys
vi_cases	db	5,3,4,0
keys		db	'iX',27,':wq',13
keys_saved	db	':q',13,':q!',13
keys_end	db	0
force_quit	db	27,':q!',13,0
command		db	"A:\COMMAND.COM",0
vi_program	db	"A:\EXT\VI.COM",0
vi_file		db	"VIERR.TMP",0
exec_parms	EPB	<0,0,PSP_FCB1,PSP_FCB2>
cmd_tail	db	cmd_end-cmd_text-1
cmd_text	db	"/C \TESTS\REGRESS\IOERR.BAS",13
cmd_end		label	byte
vi_tail		db	9,"VIERR.TMP",13
starting	db	"IOERR starting",13,10,'$'
passed		db	"IOERR passed",13,10,'$'
failed		db	"IOERR failed",13,10,'$'
	COMHEAP	1024
CODE	ENDS
	end	main
