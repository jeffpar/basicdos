	include	dos.inc

DOS	segment word public 'CODE'

	ASSUME	CS:DOS, DS:DOS, ES:BIOS, SS:NOTHING

	public	tty_echo
tty_echo proc near
	ret
tty_echo endp

	public	tty_write
tty_write proc near
	ret
tty_write endp

	public	aux_read
aux_read proc near
	ret
aux_read endp

	public	aux_write
aux_write proc near
	ret
aux_write endp

	public	prn_write
prn_write proc near
	ret
prn_write endp

	public	tty_io
tty_io	proc near
	ret
tty_io	endp

	public	tty_in
tty_in	proc near
	ret
tty_in	endp

	public	tty_read
tty_read proc near
	ret
tty_read endp

	public	tty_print
tty_print proc near
	ret
tty_print endp

	public	tty_input
tty_input proc near
	ret
tty_input endp

	public	tty_status
tty_status proc near
	ret
tty_status endp

	public	tty_flush
tty_flush proc near
	ret
tty_flush endp

DOS	ends

	end
