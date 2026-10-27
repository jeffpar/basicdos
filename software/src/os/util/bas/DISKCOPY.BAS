	' DISKCOPY.BAS: copies a diskette to another diskette
	'
	'   DISKCOPY [drive1: [drive2:]]
	'
	' Copies the diskette in drive1 (or the current drive) to the
	' diskette in drive2 (or drive1), formatting each of the target's tracks
	' with the source's parameters as it goes, so the target needn't be
	' formatted first.  When both drives are the same, the copy is made in
	' passes, with as many tracks as memory allows, and DISKCOPY asks for
	' the source and target diskettes in turn.
	'
	' Both volumes are opened with 128-byte records (4 per sector), and the
	' target is given the source's parameters (IOCTL &HF1) before its tracks
	' are formatted and verified (IOCTL &HF2).  The parameters come from the
	' source's boot sector, or for a PC DOS 1.x diskette (which has no
	' parameters there), from the media ID that begins its FAT.
	'
	DEFINT A-Z
	S$ = UCASE$(ARG$(1)) : T$ = UCASE$(ARG$(2))
	IF S$ = "" THEN S$ = LEFT$(CURDIR$, 2)
	IF T$ = "" THEN T$ = S$
	IF LEN(S$) <> 2 OR RIGHT$(S$, 1) <> ":" THEN GOTO 95
	IF LEN(T$) <> 2 OR RIGHT$(T$, 1) <> ":" THEN GOTO 95
	ON ERROR GOTO 90
10	PRINT "Insert SOURCE diskette in drive "; S$
	IF S$ <> T$ THEN PRINT "Insert TARGET diskette in drive "; T$
	PRINT "Press any key when ready..."
	GOSUB 80
	' A hard disk's IOCTL &HF3 returns its partition table (more than one
	' byte), while a diskette's returns at most its drive type
	OPEN S$ AS #1 LEN = 128
	FIELD #1, 128 AS A$
	IF LEN(IOCTL$(1, &HF3)) > 1 THEN GOTO 85
	' Get the source's sectors per track (T), heads (H), total sectors (N),
	' media ID (M), sectors per cluster (K), root entries (E), and sectors
	' per FAT (F), and build the target's parameters (P$), as FORMAT does
	GET #1, 1
	T = CVI(MID$(A$, 25, 2)) : H = CVI(MID$(A$, 27, 2))
	N = CVI(MID$(A$, 20, 2)) AND &HFFFF : M = ASC(MID$(A$, 22))
	K = ASC(MID$(A$, 14)) : E = CVI(MID$(A$, 18, 2)) : F = CVI(MID$(A$, 23, 2))
	IF CVI(MID$(A$, 12, 2)) <> 512 OR T < 8 OR T > 18 THEN GOTO 12
	IF H >= 1 AND H <= 2 THEN GOTO 20
12	GET #1, 5 : M = ASC(A$)
	RESTORE
	FOR I = 1 TO 4
	READ Y, H, T, K, E, F
	IF Y = M THEN GOTO 15
	NEXT
	GOTO 85
15	N = 40 * H * T
	DATA &HFE, 1, 8, 1, 64, 1, &HFF, 2, 8, 2, 112, 1
	DATA &HFC, 1, 9, 1, 64, 2, &HFD, 2, 9, 2, 112, 2
20	R = 1 + 2 * F
	P$ = "BASICDOS" + MKI$(512) + CHR$(K) + MKI$(1) + CHR$(2) + MKI$(E) + MKI$(N)
	P$ = P$ + CHR$(M) + MKI$(F) + MKI$(T) + MKI$(H) + MKL$(0) + MKL$(0)
	P$ = P$ + CHR$(0) + MKI$(H * T) + MKI$(R) + MKI$(R + E \ 16)
	NT = N \ T : RT = T * 4
	PRINT "Copying"; NT \ H; "tracks,"; T; "sectors per track,"; H; "side(s)"
	IF S$ = T$ THEN GOTO 40
	' Two drives: format and copy each track
	OPEN T$ AS #2 LEN = 128
	FIELD #2, 128 AS C$
	IF LEN(IOCTL$(2, &HF3)) > 1 THEN GOTO 85
	IOCTL #2, &HF1, P$
	FOR J = 0 TO NT - 1
	IOCTL #2, &HF2, J \ H, J MOD H
	FOR R = J * RT + 1 TO (J + 1) * RT
	GET #1, R : LSET C$ = A$ : PUT #2, R
	NEXT
	NEXT
	CLOSE
	GOTO 70
40	' One drive: read as many tracks (TP) as memory allows, then write them
	CLOSE #1
	TP = (FRE(0) - 8192) \ (RT * 140)
	IF TP < 1 THEN PRINT "Not enough memory" : END
	IF TP > NT THEN TP = NT
	DIM B$(TP * RT)
	FOR J0 = 0 TO NT - 1 STEP TP
	J1 = J0 + TP - 1 : IF J1 > NT - 1 THEN J1 = NT - 1
	IF J0 > 0 THEN PRINT "Insert SOURCE diskette in drive "; S$ : GOSUB 75
	OPEN S$ AS #1 LEN = 128
	FIELD #1, 128 AS A$
	FOR R = J0 * RT + 1 TO (J1 + 1) * RT
	GET #1, R : B$(R - J0 * RT) = A$
	NEXT
	CLOSE #1
	PRINT "Insert TARGET diskette in drive "; T$ : GOSUB 75
	OPEN T$ AS #2 LEN = 128
	FIELD #2, 128 AS C$
	IOCTL #2, &HF1, P$
	FOR J = J0 TO J1
	IOCTL #2, &HF2, J \ H, J MOD H
	FOR R = J * RT + 1 TO (J + 1) * RT
	LSET C$ = B$(R - J0 * RT) : PUT #2, R
	NEXT
	NEXT
	CLOSE #2
	NEXT
	ERASE B$
70	PRINT "Copy complete"
	PRINT "Copy another diskette (Y/N)? ";
	GOSUB 80 : PRINT K$
	IF K$ = "Y" THEN GOTO 10
	END
75	PRINT "Press any key when ready..."
80	' Wait for a key (in K$), discarding any keys already typed
	WHILE INKEY$ <> "" : WEND
	K$ = ""
	WHILE K$ = "" : K$ = UCASE$(INKEY$) : WEND
	RETURN
85	CLOSE
	PRINT "DISKCOPY works only with diskettes in a known format" : END
90	CLOSE
	IF ERR = 70 THEN PRINT "Write protect error" : END
	IF ERR = 71 THEN PRINT "Drive not ready" : END
	IF ERR = 72 THEN PRINT "Unrecoverable read or format error" : END
	IF ERR = 75 THEN PRINT "Invalid drive specification" : END
	PRINT "Copy failed (error"; ERR; ")"
	END
95	PRINT "Usage: DISKCOPY [drive1: [drive2:]]"
	END
