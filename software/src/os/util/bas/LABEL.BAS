	' LABEL.BAS: creates, changes, or deletes a drive's volume label
	'
	'   LABEL [drive:][label]
	'
	' Without a label, LABEL displays the current one and asks for a new
	' one (ENTER deletes the current label, after asking first).  A label
	' has up to 11 characters, which can't include * ? / \ | . , ; : + = [ ]
	' < > or ".
	'
	' The label is a root directory entry with attribute 8, so LABEL opens
	' the volume with 32-byte records (one per directory entry), finds the
	' root directory from the boot sector, and replaces the current label's
	' entry (or the first free entry) directly.
	'
	DEFINT A-Z
	A$ = UCASE$(ARG$) : D$ = LEFT$(CURDIR$, 2)
	IF MID$(A$, 2, 1) = ":" THEN D$ = LEFT$(A$, 2) : A$ = MID$(A$, 3)
	WHILE LEFT$(A$, 1) = " " : A$ = MID$(A$, 2) : WEND
	ON ERROR GOTO 90
	GOSUB 80
	IF A$ <> "" THEN GOTO 20
	PRINT " Volume in drive "; LEFT$(D$, 1);
	IF L$ = "" THEN PRINT " has no label" ELSE PRINT " is "; L$
	LINE INPUT "Volume label (11 characters, ENTER for none)? "; A$
	A$ = UCASE$(A$)
	IF A$ <> "" OR L$ = "" THEN GOTO 20
	PRINT "Delete current volume label (Y/N)? ";
	C$ = "" : WHILE C$ = "" : C$ = UCASE$(INKEY$) : WEND
	PRINT C$
	IF C$ <> "Y" THEN END
20	IF LEN(A$) > 11 THEN PRINT "Too many characters in volume label" : END
	FOR I = 1 TO LEN(A$)
	IF INSTR("*?/\|.,;:+=[]<>" + CHR$(34), MID$(A$, I, 1)) THEN GOTO 85
	NEXT
	IF A$ = "" AND L$ = "" THEN END
	' Find the root directory (R records into the volume, with NR entries):
	' the boot sector gives the bytes per sector, reserved sectors, number
	' of FATs, root directory entries, and sectors per FAT
	OPEN D$ AS #1 LEN = 32
	FIELD #1, 32 AS E$
	GET #1, 1
	S = CVI(MID$(E$, 12, 2)) \ 32 : NR = CVI(MID$(E$, 18, 2))
	R = (CVI(MID$(E$, 15, 2)) + ASC(MID$(E$, 17)) * CVI(MID$(E$, 23, 2))) * S
	' Look for the current label's entry (LE) and the first free one (FE):
	' E5h means deleted, and 0 means that it and the rest are unused
	LE = 0 : FE = 0
	FOR I = 1 TO NR
	GET #1, R + I
	C = ASC(E$) : Y = ASC(MID$(E$, 12))
	IF (C = 0 OR C = &HE5) AND FE = 0 THEN FE = I
	IF C = 0 THEN GOTO 30
	IF C <> &HE5 AND (Y AND 8) <> 0 AND Y <> 15 THEN LE = I
	NEXT
30	IF A$ <> "" THEN GOTO 40
	IF LE THEN GET #1, R + LE : LSET E$ = CHR$(&HE5) + MID$(E$, 2) : PUT #1, R + LE
	CLOSE
	END
40	IF LE THEN FE = LE
	IF FE = 0 THEN PRINT "Root directory full" : CLOSE : END
	' The new entry has the label, attribute 8, the current time and date,
	' and no clusters or size
	T$ = TIME$ : Y$ = DATE$
	T = VAL(T$) * 2048 + VAL(MID$(T$, 4)) * 32 + VAL(MID$(T$, 7)) \ 2
	Y = (VAL(MID$(Y$, 7)) - 1980) * 512 + VAL(Y$) * 32 + VAL(MID$(Y$, 4))
	E2$ = MKI$(T) + MKI$(Y) + MKI$(0) + MKL$(0)
	LSET E$ = LEFT$(A$ + SPACE$(11), 11) + CHR$(8) + STRING$(10, 0) + E2$
	PUT #1, R + FE
	CLOSE
	END
80	' Get the current label (L$, or empty if none), which DIR$ (attribute 8
	' finds only the label) returns in NAME.EXT form
	F$ = DIR$(D$ + MID$(CURDIR$, 3, 1) + "*.*", 8)
	L$ = MID$(F$, 10) : I = INSTR(L$, ".")
	IF I THEN L$ = LEFT$(LEFT$(L$, I - 1) + SPACE$(8), 8) + MID$(L$, I + 1)
	RETURN
85	PRINT "Invalid characters in volume label"
	END
90	CLOSE
	IF ERR = 70 THEN PRINT "Write protect error" : END
	IF ERR = 71 THEN PRINT "Drive not ready" : END
	IF ERR = 75 THEN PRINT "Invalid drive specification" : END
	PRINT "Unable to label drive "; D$; " (error"; ERR; ")"
	END
