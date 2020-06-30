;
; BASIC-DOS Command Include File
;
; @author Jeff Parsons <Jeff@pcjs.org>
; @copyright © 2012-2020 Jeff Parsons
; @license MIT <https://www.pcjs.org/LICENSE.txt>
;
; This file is part of PCjs, a computer emulation software project at pcjs.org
;

;
; Define the command workspace as a structure
;
CMD_INPUT	struc
INP_MAX		db	?
INP_CNT		db	?
INP_BUF		db	32 dup (?)
CMD_INPUT	ends

CMD_TOKENS	struc
TOK_MAX		db	?
TOK_CNT		db	?
TOK_BUF		dw	32 dup (?)
CMD_TOKENS	ends

CMD_WS		struc
INPUT		CMD_INPUT	<>
TOKENS		CMD_TOKENS	<>
CMD_WS		ends
