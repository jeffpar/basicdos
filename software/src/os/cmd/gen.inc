;
; BASIC-DOS Code Generator Macros
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright (c) 2020-2026 Jeff Parsons
; @license MIT <https://basicdos.com/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;
; Included after cmd.inc by the gen*.asm files (see gencmd.asm).
;
;
; Code generation helper macros
;
; GENCALL generates a call the specified function.
;
GENCALL	macro	seg,off
	IFB	<off>			;; if there's no off parameter
	 IFDIF	<seg>,<cx>
	mov	cx,offset seg		;; then seg is really a function name
	 ENDIF
	call	genCallCS		;; inside the CS segment
	ELSE
	 IFDIF	<off>,<cx>
	mov	cx,off
	 ENDIF
	 IFDIF	<seg>,<dx>
	mov	dx,seg			;; otherwise DX:CX is the function addr
	 ENDIF
	call	genCallFar
	ENDIF
	endm
;
; GENPUSH generates code to push immediate 16-bit (via DX) or 32-bit
; values (via DX:CX).
;
; Modifies: AX, DX (and CX if GENPUSH dx,cx)
;
GENPUSH	macro	val1,val2
	IFDIF	<val1>,<dx>
	mov	dx,val1
	ENDIF
	IFNB	<val2>
	IFDIF	<val2>,<cx>
	mov	cx,val2
	ENDIF
	call	genPushImmLong
	ELSE
	call	genPushImm
	ENDIF
	endm
;
; GENPUSHB generates code to push an immediate byte value (via AL, AH,
; or a constant that will be loaded via AL).
;
GENPUSHB macro	val
	IFIDN	<val>,<al>
	call	genPushImmByteAL
	ELSE
	 IFIDN	<val>,<ah>
	call	genPushImmByteAH
	 ELSE
	mov	ax,OP_MOV_AL OR (val SHL 8)
	call	genPushImmByte
	 ENDIF
	ENDIF
	endm
