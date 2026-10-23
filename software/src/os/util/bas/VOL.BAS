	' VOL.BAS: displays the volume label of a drive
	'
	'   VOL [d:]
	'
	' The label is found with DIR$ (attribute 8 finds only the volume label),
	' which returns it in NAME.EXT form, so its first 8 characters are put
	' back together with the rest.
	'
	DEFINT A-Z
	D$ = UCASE$(ARG$(1)) : IF D$ = "" THEN D$ = LEFT$(CURDIR$, 2)
	IF LEN(D$) <> 2 OR RIGHT$(D$, 1) <> ":" THEN PRINT "Usage: VOL [d:]" : END
	ON ERROR GOTO 90
	F$ = DIR$(D$ + MID$(CURDIR$, 3, 1) + "*.*", 8)
	ON ERROR GOTO 0
	IF F$ = "" THEN PRINT " Volume in drive "; LEFT$(D$, 1); " has no label" : END
	N$ = MID$(F$, 10) : I = INSTR(N$, ".")
	IF I THEN N$ = LEFT$(LEFT$(N$, I - 1) + SPACE$(8), 8) + MID$(N$, I + 1)
	PRINT " Volume in drive "; LEFT$(D$, 1); " is "; N$
	END
90	PRINT "Invalid drive specification" : END
