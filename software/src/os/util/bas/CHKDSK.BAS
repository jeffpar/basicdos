	' CHKDSK.BAS: checks a drive's FAT and directories, and reports its space
	'
	'   CHKDSK [d:] [/V]
	'
	' Every file's and directory's cluster chain is followed (and /V lists
	' them), to find chains that are cross-linked (sharing a cluster), that
	' don't match the file's size, or that contain invalid clusters, and
	' finally, lost clusters (in use, but in no chain).  CHKDSK only reports
	' these problems; it doesn't fix them (there's no /F).
	'
	' The volume is read directly: first with 32-byte records, for the boot
	' sector's BPB and the FAT, which is kept in 192-byte strings (Z$), so
	' that 12-bit and 16-bit entries can be decoded; and then with 224-byte
	' records (7 directory entries each), for the directories.  Records are
	' numbered from 1 to 65535, so only the first 14Mb of a volume can be
	' read, and a directory beyond that isn't checked.  A bitmap (U) marks
	' each cluster that's in a chain.
	'
	DEFINT A-Z
	D$ = LEFT$(CURDIR$, 2) : V = 0
	FOR I = 1 TO 2
	A$ = UCASE$(ARG$(I))
	IF A$ = "/V" OR A$ = "-V" THEN V = 1
	IF MID$(A$, 2, 1) = ":" THEN D$ = LEFT$(A$, 2)
	NEXT
	PC$ = MID$(CURDIR$, 3, 1)
	ON ERROR GOTO 90
	' From the BPB: the cluster size (K sectors, CB bytes), the first FAT
	' sector (F0), FAT sectors (FS), the root directory (R0, with RS
	' sectors), the first data sector (DB), and the number of clusters (NC)
	OPEN D$ AS #1 LEN = 32
	FIELD #1, 32 AS E$
	GET #1, 1
	IF CVI(MID$(E$, 12, 2)) <> 512 OR ASC(MID$(E$, 22)) < &HF0 THEN GOTO 85
	K = ASC(MID$(E$, 14)) : CB = K * 512 : F0 = CVI(MID$(E$, 15, 2))
	FS = CVI(MID$(E$, 23, 2)) : R0 = F0 + ASC(MID$(E$, 17)) * FS
	RS = (CVI(MID$(E$, 18, 2)) * 32 + 511) \ 512 : DB = R0 + RS
	N = CVI(MID$(E$, 20, 2)) AND &HFFFF
	IF N = 0 THEN GET #1, 2 : N = CVL(LEFT$(E$, 4))
	NC = (N - DB) \ K
	' A FAT with fewer than 4085 clusters has 12-bit entries (with end of
	' chain at FF8h or above, and FF7h for a bad cluster)
	F16 = (NC >= 4085) : EC = &HFF8 : BC = &HFF7
	IF F16 THEN EC = &HFFF8 : BC = &HFFF7
	DIM Z$(FS * 512 \ 192 + 1), U(NC \ 32 + 1), W(NC \ 32 + 1)
	FOR I = 0 TO FS * 512 \ 192
	Z$(I) = ""
	FOR J = 1 TO 6
	R = F0 * 16 + I * 6 + J
	IF R <= (F0 + FS) * 16 THEN GET #1, R : Z$(I) = Z$(I) + E$
	NEXT
	NEXT
	CLOSE #1
	OPEN D$ AS #1 LEN = 224
	FIELD #1, 224 AS E$
	LR = 0
	' Walk the directories, starting with the root (cluster 0), keeping a
	' queue of the subdirectories found (QC = first cluster, QP$ = path)
	DIM QC(300), QP$(300)
	QC(0) = 0 : QP$(0) = D$ + PC$ : QN = 1
	NH = 0 : BH = 0 : ND = 0 : BD = 0 : NU = 0 : BU = 0 : ER = 0 : VL$ = ""
	FOR QI = 0 TO 300
	IF QI >= QN THEN GOTO 40
	DC = QC(QI) : DJ = 0 : DS = DB + (DC - 2) * K : DN = K
	IF DC = 0 THEN DS = R0 : DN = RS
10	GOSUB 200
	IF Q$ = "" THEN GOTO 30
	C = ASC(Q$) : IF C = 0 THEN GOTO 30
	A = ASC(MID$(Q$, 12)) : IF C = &HE5 OR A = 15 THEN GOTO 10
	IF A AND 8 THEN VL$ = Q$ : GOTO 10
	IF C = 46 THEN GOTO 10
	X$ = LEFT$(Q$, 8) : GOSUB 500 : N$ = X$
	X$ = MID$(Q$, 9, 3) : GOSUB 500 : IF X$ <> "" THEN N$ = N$ + "." + X$
	N$ = QP$(QI) + N$
	C0 = CVI(MID$(Q$, 27, 2)) AND &HFFFF : S = CVL(MID$(Q$, 29, 4))
	IF V THEN PRINT N$
	GOSUB 400
	IF A AND 16 THEN GOTO 20
	IF (S + CB - 1) \ CB = L THEN GOTO 15
	PRINT N$; " allocation error (size"; S; "but"; L; "clusters)" : ER = ER + 1
15	IF A AND 2 THEN NH = NH + 1 : BH = BH + L * CB : GOTO 10
	NU = NU + 1 : BU = BU + L * CB
	GOTO 10
20	ND = ND + 1 : BD = BD + L * CB
	IF QN <= 300 THEN QC(QN) = C0 : QP$(QN) = N$ + PC$ : QN = QN + 1
	GOTO 10
30	NEXT
40	CLOSE #1
	' Count the free and bad clusters, and the lost ones (in use, but in no
	' chain), and their chains (lost clusters that no lost cluster leads to)
	NF = 0 : NB = 0 : NL = 0 : NX = 0
	FOR C = 2 TO NC + 1
	GOSUB 300
	IF F = 0 THEN NF = NF + 1 : GOTO 50
	IF F = BC THEN NB = NB + 1 : GOTO 50
	IF U(C \ 32) AND (1 << (C AND 31)) THEN GOTO 50
	NL = NL + 1
	IF F >= 2 AND F <= NC + 1 THEN W(F \ 32) = W(F \ 32) OR (1 << (F AND 31))
50	NEXT
	FOR C = 2 TO NC + 1
	GOSUB 300
	IF F = 0 OR F = BC OR (U(C \ 32) AND (1 << (C AND 31))) THEN GOTO 60
	IF (W(C \ 32) AND (1 << (C AND 31))) = 0 THEN NX = NX + 1
60	NEXT
	IF NL THEN PRINT NL; "lost clusters found in"; NX; "chains" : ER = ER + 1
	IF ER THEN PRINT "Errors found (CHKDSK reports them, but can't fix them)"
	' Report the label (with its date and time) and the space on the volume
	PRINT
	IF VL$ = "" THEN GOTO 70
	T = CVI(MID$(VL$, 23, 2)) AND &HFFFF : Y = CVI(MID$(VL$, 25, 2)) AND &HFFFF
	H = T \ 2048 : A$ = "a" : IF H >= 12 THEN A$ = "p"
	MO = (Y \ 32) AND 15 : DY = Y AND 31 : YR = Y \ 512 + 1980
	HR = (H + 11) MOD 12 + 1 : MI = (T \ 32) AND 63
	PRINTF USING "Volume %s created %02d-%02d-%d %2d:%02d%s"; LEFT$(VL$, 11), MO, DY, YR, HR, MI, A$
	PRINT
70	PRINTF USING "%12d bytes total disk space"; NC * CB
	IF NB THEN PRINTF USING "%12d bytes in bad sectors"; NB * CB
	IF NH THEN PRINTF USING "%12d bytes in %d hidden files"; BH, NH
	IF ND THEN PRINTF USING "%12d bytes in %d directories"; BD, ND
	IF NU THEN PRINTF USING "%12d bytes in %d user files"; BU, NU
	IF NL THEN PRINTF USING "%12d bytes in %d lost clusters"; NL * CB, NL
	PRINTF USING "%12d bytes available on disk"; NF * CB
	END
85	PRINT "Drive "; D$; " doesn't have a FAT volume" : END
90	CLOSE
	IF ERR = 71 THEN PRINT "Drive not ready" : END
	IF ERR = 75 THEN PRINT "Invalid drive specification" : END
	PRINT "Unable to check drive "; D$; " (error"; ERR; ")"
	END
200	' Get the next entry (Q$) of the directory being read (empty at its
	' end): DC is its current cluster (0 for the root), DS the current
	' sector, DN the sectors left in DC (or the root), and DJ the next of
	' the sector's 16 entries
	IF DJ < 16 THEN GOTO 210
	DJ = 0 : DS = DS + 1 : DN = DN - 1
	IF DN > 0 THEN GOTO 210
	Q$ = "" : IF DC = 0 THEN RETURN
	C = DC : GOSUB 300 : DC = F
	IF DC < 2 OR DC > NC + 1 THEN RETURN
	DS = DB + (DC - 2) * K : DN = K
210	O = DS * 512 + DJ * 32 : DJ = DJ + 1
	R = O \ 224 + 1
	IF R <= 65535 THEN GOTO 220
	PRINT QP$(QI); " is beyond the first 14Mb (not checked)"
	Q$ = ""
	RETURN
220	IF R <> LR THEN GET #1, R : LR = R
	Q$ = MID$(E$, (O MOD 224) + 1, 32)
	RETURN
300	' Get the FAT entry (F) for cluster C: in a 12-bit FAT, each pair of
	' entries takes 3 bytes (64 pairs per string), and in a 16-bit FAT,
	' each entry takes 2 bytes (96 per string)
	IF F16 = 0 THEN GOTO 310
	F = CVI(MID$(Z$(C \ 96), (C MOD 96) * 2 + 1, 2)) AND &HFFFF
	RETURN
310	G$ = MID$(Z$(C \ 128), ((C MOD 128) \ 2) * 3 + 1, 3)
	IF C AND 1 THEN F = ASC(MID$(G$, 2)) \ 16 + ASC(MID$(G$, 3)) * 16 : RETURN
	F = ASC(G$) + (ASC(MID$(G$, 2)) AND 15) * 256
	RETURN
400	' Follow the chain that starts with cluster C0 (for N$), counting its
	' clusters (L) and marking each one in U, and report a cluster that's
	' already marked (cross-linked) or invalid
	L = 0 : C = C0
	WHILE C >= 2 AND C <= NC + 1
	B = 1 << (C AND 31)
	IF (U(C \ 32) AND B) = 0 THEN GOTO 410
	PRINT N$; " is cross-linked on cluster"; C : ER = ER + 1
	RETURN
410	U(C \ 32) = U(C \ 32) OR B
	L = L + 1 : GOSUB 300 : C = F
	WEND
	IF L = 0 AND C = 0 THEN RETURN
	IF C < EC THEN PRINT N$; " has an invalid cluster"; C : ER = ER + 1
	RETURN
500	' Remove the trailing spaces of X$
	WHILE RIGHT$(X$, 1) = " " : X$ = LEFT$(X$, LEN(X$) - 1) : WEND
	RETURN
