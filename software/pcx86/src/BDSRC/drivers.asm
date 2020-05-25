	include	dev.inc

DEV	segment word public 'CODE'

        ASSUME	CS:DEV, DS:NOTHING, ES:NOTHING, SS:NOTHING

	extrn	init:near
;
; This must be the first object module in the image.
;
	jmp	init
;
; Standard device drivers
;
	public	NUL,KBD,SCR,CON,AUX,PRN
	public	COM1,COM2,COM3,COM4,LPT1,LPT2,LPT3,LPT4
	public	CLOCK,DRIVEA,DRIVEB,DRIVEC,DRIVED

NUL	DDH	<offset KBD,DDATTR_CHAR,offset ddent,offset ddint>
	db	"NUL:    "
KBD	DDH	<offset SCR,DDATTR_CHAR,offset ddent,offset ddint>
	db	"KBD:    "
SCR	DDH	<offset CON,DDATTR_CHAR,offset ddent,offset ddint>
	db	"SCR:    "
CON	DDH	<offset AUX,DDATTR_CHAR,offset ddent,offset ddint>
	db	"CON:    "
AUX	DDH	<offset COM1,DDATTR_CHAR,offset ddent,offset ddint>
	db	"AUX:    "
COM1	DDH	<offset COM2,DDATTR_CHAR,offset ddent,offset ddint>
	db	"COM1:   "
COM2	DDH	<offset COM3,DDATTR_CHAR,offset ddent,offset ddint>
	db	"COM2:   "
COM3	DDH	<offset COM4,DDATTR_CHAR,offset ddent,offset ddint>
	db	"COM3:   "
COM4	DDH	<offset PRN,DDATTR_CHAR,offset ddent,offset ddint>
	db	"COM4:   "
PRN	DDH	<offset LPT1,DDATTR_CHAR,offset ddent,offset ddint>
	db	"PRN:    "
LPT1	DDH	<offset LPT2,DDATTR_CHAR,offset ddent,offset ddint>
	db	"LPT1:   "
LPT2	DDH	<offset LPT3,DDATTR_CHAR,offset ddent,offset ddint>
	db	"LPT2:   "
LPT3	DDH	<offset LPT4,DDATTR_CHAR,offset ddent,offset ddint>
	db	"LPT3:   "
LPT4	DDH	<offset CLOCK,DDATTR_CHAR,offset ddent,offset ddint>
	db	"LPT4:   "
CLOCK	DDH	<offset DRIVEA,DDATTR_CHAR,offset ddent,offset ddint>
	db	"CLOCK:  "
DRIVEA	DDH	<offset DRIVEB,DDATTR_BLOCK,offset ddent,offset ddint>
	db	"A:      "
DRIVEB	DDH	<offset DRIVEC,DDATTR_BLOCK,offset ddent,offset ddint>
	db	"B:      "
DRIVEC	DDH	<offset DRIVED,DDATTR_BLOCK,offset ddent,offset ddint>
	db	"C:      "
DRIVED	DDH	<-1,DDATTR_BLOCK,offset ddent,offset ddint>
	db	"D:      "

ddent	proc	far
	ret
ddent	endp

ddint	proc	far
	ret
ddint	endp

DEV	ends

	end
