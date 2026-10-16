	' FORMAT.BAS: formats a diskette or a hard disk volume for BASIC-DOS
	'
	'   FORMAT d: [/S] [/1] [/8]
	'
	' /S copies the system files (from the root of the current drive), /1
	' formats one side of a diskette, and /8 formats 8 sectors per track
	' (for PC DOS 1.x).
	'
	' The drive's volume is opened for writing (an unformatted diskette or
	' a new hard disk has "unknown media", but can still be opened), and the
	' diskette driver formats and verifies each track (IOCTL &HF2), after
	' it's given the new diskette's BPB (IOCTL &HF1); then the boot sector
	' (copied from the current drive, with the new BPB), the FATs, and the
	' root directory are written to the volume as one stream of bytes.
	' Cluster and root directory sizes follow the PC DOS 2.x rules, with
	' 12-bit FATs, except that a hard disk volume of more than 32680 sectors
	' gets a 16-bit FAT (as PC DOS 3.x did), since a 12-bit FAT can't hold
	' more than 4084 clusters.
	'
	' A hard disk's partition table is displayed first (IOCTL$ &HF3): if it
	' has FAT volumes, one of them is formatted (as above, without track
	' formatting), and if it has no partition table, FORMAT offers to create
	' one (IOCTL &HF4) with a single volume of the requested size.
	'
	DEFINT A-Z
	D$ = "" : S = 0 : H = 2 : T = 9
	FOR I = 1 TO 4
	A$ = UCASE$(ARG$(I))
	IF A$ = "/S" OR A$ = "-S" THEN S = 1
	IF A$ = "/1" OR A$ = "-1" THEN H = 1
	IF A$ = "/8" OR A$ = "-8" THEN T = 8
	IF LEN(A$) = 2 AND RIGHT$(A$, 1) = ":" THEN D$ = A$
	NEXT
	IF D$ = "" THEN PRINT "Drive letter required (eg, FORMAT A:)" : END
	V$ = LEFT$(CURDIR$, 2)
	IF D$ = V$ THEN PRINT "Cannot format the current drive" : END
	Z = 0 : U = 0
	ON ERROR GOTO 90
	OPEN D$ FOR OUTPUT AS #1
	P$ = IOCTL$(1, &HF3)
	IF P$ <> "" THEN GOTO 100
	' Diskette geometry: 40 cylinders, H heads, T sectors per track, N sectors;
	' the media ID is FE (1 head, 8 sectors), FF (2, 8), FC (1, 9), or FD (2, 9)
	N = 40 * H * T : HS = 0
	M = &HFC - 2 * (T = 8) - (H = 2)
10	PRINT "Insert new diskette for drive "; D$
	PRINT "and strike any key when ready"
	GOSUB 60
	GOSUB 50
	PRINT "Formatting...";
	Z = 1
	FOR C = 0 TO 39 : FOR I = 0 TO H - 1 : IOCTL #1, &HF2, C, I : NEXT : NEXT
	Z = 0
	GOSUB 70
	GOSUB 80
	PRINT
	PRINT "Format another (Y/N)? ";
	GOSUB 60
	PRINT A$
	IF A$ <> "Y" THEN END
	CLOSE
	OPEN D$ FOR OUTPUT AS #1
	GOTO 10
	DATA "BASDEV.COM", "BASDOS.COM", "COMMAND.COM"
50	' Choose the cluster size (K sectors), root directory entries (E), and
	' FAT size (F sectors) for N sectors: PC DOS 2.x used 1-sector clusters
	' and 64 entries up to 256K, 2 and 112 up to 1Mb, 4 and 256 up to 4Mb,
	' 8 and 512 up to 16Mb, and 16 and 1024 above that; with 12-bit FAT
	' entries for an even number of clusters, from the sectors on the volume
	' (an overestimate, like PC DOS 2.x).  Larger hard disk volumes (more
	' than 32680 sectors) get 2K clusters and a 16-bit FAT, like PC DOS 3.x.
	' The root directory (R sectors) follows the two FATs, so B sectors are
	' used by the system, and the FAT ID (Y bytes) begins each FAT.
	K = 1 : E = 64 : Y = 3
	IF N > 512 THEN K = 2 : E = 112
	IF N > 2048 THEN K = 4 : E = 256
	IF N > 8192 THEN K = 8 : E = 512
	IF N > 32768 THEN K = 16 : E = 1024
	F = ((((N + K - 1) \ K + 1) AND -2) * 3 \ 2 + 511) \ 512
	IF N > 32680 THEN K = 4 : E = 512 : Y = 4 : F = ((N \ K + 2) * 2 + 511) \ 512
	R = E \ 16 : B = 1 + 2 * F + R
	' Copy the boot sector from the current drive, replacing its BPB; the BPB
	' ends with the drive, sectors per cylinder, and first root directory and
	' data sectors, which the boot code relies on; then give the volume the
	' BPB (so that it can be written, if its media was unknown)
	OPEN V$ AS #2 LEN = 255
	FIELD #2, 255 AS R$
	GET #2, 1 : B1$ = R$
	GET #2, 2 : B2$ = R$
	GET #2, 3 : B3$ = LEFT$(R$, 2)
	CLOSE #2
	P$ = MID$(B1$, 4, 8) + MKI$(512) + CHR$(K) + MKI$(1) + CHR$(2) + MKI$(E)
	P$ = P$ + MKI$(N) + CHR$(M) + MKI$(F) + MKI$(T) + MKI$(H) + MKL$(HS) + MKL$(0)
	P$ = P$ + CHR$(0) + MKI$(H * T) + MKI$(1 + 2 * F) + MKI$(B)
	B1$ = LEFT$(B1$, 3) + P$ + MID$(B1$, 44)
	IOCTL #1, &HF1, P$
	RETURN
60	' Wait for a key (in A$), discarding any keys already typed
	WHILE INKEY$ <> "" : WEND
	A$ = ""
	WHILE A$ = "" : A$ = UCASE$(INKEY$) : WEND
	RETURN
70	' Write the boot sector, the FATs (each begins with the media ID and FFh
	' bytes), and the empty root directory, then close the volume (which
	' rebuilds its BPB from the new boot sector)
	Z$ = STRING$(255, 0)
	PRINT #1, B1$; B2$; B3$;
	FOR I = 1 TO 2
	PRINT #1, CHR$(M); STRING$(Y - 1, 255); : L = F * 512 - Y : GOSUB 75
	NEXT
	L = R * 512 : GOSUB 75
	CLOSE #1
	PRINT "Format complete"
	RETURN
75	' Write L zero bytes to the volume
	WHILE L > 255 : PRINT #1, Z$; : L = L - 255 : WEND
	IF L > 0 THEN PRINT #1, LEFT$(Z$, L);
	RETURN
80	' Copy the system files (/S), adding their sizes (rounded up to clusters)
	' to U, and report the space on the volume
	ON ERROR GOTO 0
	IF S = 0 THEN GOTO 85
	RESTORE
	FOR I = 1 TO 3
	READ F$
	F$ = V$ + MID$(CURDIR$, 3, 1) + F$
	COPY F$ D$
	IF ERRORLEVEL <> 0 THEN PRINT "Unable to copy "; F$ : GOTO 85
	OPEN F$ FOR INPUT AS #2
	L = LOF(2) + K * 512 - 1
	U = U + L - L MOD (K * 512)
	CLOSE #2
	NEXT
	PRINT "System transferred"
85	PRINT
	L = ((N - B) \ K) * K * 512
	PRINT L; "bytes total disk space"
	IF S THEN PRINT U; "bytes used by system"
	PRINT L - U; "bytes available on disk"
	RETURN
90	' Report the error (eg, a write-protected diskette) and stop
	CLOSE
	PRINT
	IF ERR = 55 THEN PRINT "Cannot format drive "; D$; " (files are open)" : END
	IF ERR = 70 THEN PRINT "Write protect error" : END
	IF ERR = 71 THEN PRINT "Drive not ready" : END
	IF ERR = 72 AND Z THEN PRINT "Track"; C; "bad - disk unusable" : END
	IF ERR = 75 THEN PRINT "Invalid drive: "; D$ : END
	PRINT "Format failed (error"; ERR; ")"
	END
100	' Hard disk: P$ holds the disk's cylinders, heads, and sectors per track,
	' its BIOS drive number, whether its MBR is valid, the drive letter of
	' each partition (0 if it isn't a volume), and the partition table, so
	' display the table, with the size of each partition in Mb
	CY = CVI(LEFT$(P$, 2)) : H = ASC(MID$(P$, 3)) : T = ASC(MID$(P$, 4))
	PRINT "Disk"; ASC(MID$(P$, 5)) - 127; "has"; CY; "cylinders,"; H; "heads,";
	PRINT " and"; T; "sectors per track ("; (CY * H * T) \ 2048; "Mb)"
	IF ASC(MID$(P$, 6)) = 0 THEN PRINT "and no partition table" : GOTO 200
	PRINT
	PRINT "Partition  Type    Start  Sectors   Size  Drive"
	NV = 0
	FOR I = 0 TO 3
	E$ = MID$(P$, 11 + I * 16, 16)
	Y = ASC(MID$(E$, 5))
	IF Y = 0 THEN GOTO 110
	T$ = RIGHT$("  " + HEX$(Y), 2) + "h  "
	IF Y = 1 THEN T$ = "FAT12" ELSE IF Y = 4 THEN T$ = "FAT16"
	L$ = MID$(P$, 7 + I, 1)
	IF L$ = CHR$(0) THEN L$ = "" ELSE NV = NV + 1 : L$ = L$ + ":"
	SS = CVL(MID$(E$, 9, 4)) : NS = CVL(MID$(E$, 13, 4))
	PRINT "    "; I + 1; "     "; T$; RIGHT$(SPACE$(8) + STR$(SS), 8);
	PRINT RIGHT$(SPACE$(9) + STR$(NS), 9);
	PRINT RIGHT$(SPACE$(4) + STR$((NS + 1024) \ 2048), 4); " Mb  "; L$
110	NEXT
	PRINT
	IF NV = 0 THEN PRINT "The disk has no FAT volumes to format" : END
	' Format one of the disk's volumes: D$'s if it's one, otherwise ask
	I = INSTR(MID$(P$, 7, 4), LEFT$(D$, 1))
	IF I > 0 OR NV = 1 THEN GOTO 120
	PRINT "Format which drive";
	FOR I = 0 TO 3
	IF MID$(P$, 7 + I, 1) <> CHR$(0) THEN PRINT " "; MID$(P$, 7 + I, 1); ":";
	NEXT
	PRINT "? ";
	GOSUB 60 : PRINT A$
	I = INSTR(MID$(P$, 7, 4), A$)
	IF I = 0 THEN PRINT "No such volume" : END
120	IF I = 0 THEN I = 1 : WHILE MID$(P$, 6 + I, 1) = CHR$(0) : I = I + 1 : WEND
	A$ = MID$(P$, 6 + I, 1) + ":"
	IF A$ <> D$ THEN CLOSE #1 : D$ = A$ : OPEN D$ FOR OUTPUT AS #1
	E$ = MID$(P$, 11 + (I - 1) * 16, 16)
	PRINT "WARNING: all data on drive "; D$; " will be lost!"
	PRINT "Proceed with format (Y/N)? ";
	GOSUB 60 : PRINT A$
	IF A$ <> "Y" THEN END
	GOTO 300
200	' Create a partition table with one volume: the volume starts at the
	' second track (the first holds the MBR) and ends at a cylinder boundary,
	' and like PC DOS, it can't have more than 65535 sectors (32Mb)
	PRINT "Create a partition table (Y/N)? ";
	GOSUB 60 : PRINT A$
	IF A$ <> "Y" THEN END
	CS = H * T : MC = (65535 + T) \ CS
	IF MC > CY THEN MC = CY
	MM = (MC * CS - T) \ 2048
	PRINT "Size of the volume in Mb (1-"; MID$(STR$(MM), 2); ", ENTER for all)";
	INPUT L$
	C = MC
	IF L$ <> "" THEN L = VAL(L$) : C = (L * 2048 + T) \ CS
	IF C < 1 OR C > MC THEN PRINT "Invalid size" : END
	HS = T : N = C * CS - T
	' The entry has the status (80h = active), the CHS address of the first
	' and last sectors (head, sector in bits 0-5 and cylinder bits 8-9 in bits
	' 6-7, and cylinder bits 0-7), the type (01h = FAT12, 04h = FAT16), and
	' the starting LBA and sector count
	Y = 1 : IF N > 32680 THEN Y = 4
	E$ = CHR$(&H80) + CHR$(1) + CHR$(1) + CHR$(0) + CHR$(Y)
	E$ = E$ + CHR$(H - 1) + CHR$(T + ((C - 1) \ 256) * 64) + CHR$((C - 1) AND 255)
	E$ = E$ + MKL$(HS) + MKL$(N)
	IOCTL #1, &HF4, E$ + STRING$(48, 0)
	PRINT "Partition table created"
300	' Format the hard disk volume described by the entry in E$ (HS = its
	' first sector, N = its size), which needs no track formatting
	HS = CVL(MID$(E$, 9, 4)) : N = CVL(MID$(E$, 13, 4)) : M = &HF8
	PRINT "Formatting...";
	GOSUB 50
	GOSUB 70
	GOSUB 80
	END
