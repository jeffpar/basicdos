	' SYS.BAS: transfers the system files to a drive, making it bootable
	'
	'   SYS d:
	'
	' Copies BASDEV.COM, BASDOS.COM, and COMMAND.COM from the root directory
	' of the current drive to the root directory of drive d (replacing any
	' copies already there), makes them read-only system files (and BASDEV
	' and BASDOS hidden, too), and then gives d's boot sector the current
	' drive's boot code, keeping d's BPB (its disk parameters).  The boot code
	' follows the system files' FAT chains, so they can be anywhere on d.
	'
	' The BPB ends with the drive, sectors per cylinder, and first root
	' directory and data sectors, which the boot code relies on, so they're
	' recalculated from the rest of d's BPB (which another DOS may have
	' written).
	'
	DEFINT A-Z
	D$ = UCASE$(ARG$(1))
	IF LEN(D$) <> 2 OR RIGHT$(D$, 1) <> ":" THEN PRINT "Usage: SYS d:" : END
	V$ = LEFT$(CURDIR$, 2) : PC$ = MID$(CURDIR$, 3, 1)
	IF D$ = V$ THEN PRINT "Cannot transfer the system to the current drive" : END
	ON ERROR GOTO 90
	' Read the current drive's boot sector (records of 255, 255, and 2 bytes)
	OPEN V$ AS #1 LEN = 255
	FIELD #1, 255 AS R$
	GET #1, 1 : B1$ = R$ : GET #1, 2 : B2$ = R$ : GET #1, 3 : B3$ = LEFT$(R$, 2)
	CLOSE #1
	' Check d's BPB: 512-byte sectors and a FAT media ID
	OPEN D$ AS #1 LEN = 255
	FIELD #1, 255 AS R$
	GET #1, 1 : T$ = R$
	CLOSE #1
	IF CVI(MID$(T$, 12, 2)) <> 512 OR ASC(MID$(T$, 22)) < &HF0 THEN GOTO 85
	' Copy each system file (first clearing the attributes of any copy that's
	' already there, so it can be replaced), and set its attributes (DOS
	' function &H4301: 1 = read-only, 2 = hidden, 4 = system)
	FOR I = 1 TO 3
	READ N$, A
	F$ = D$ + PC$ + N$ : S$ = V$ + PC$ + N$ : Q$ = D$ + PC$
	IF EXISTS(F$) THEN DOS &H4301, 0, 0, F$
	COPY S$ Q$
	IF ERRORLEVEL THEN PRINT "Unable to copy "; N$ : END
	DOS &H4301, 0, A, F$
	NEXT
	DATA "BASDEV.COM", 7, "BASDOS.COM", 7, "COMMAND.COM", 5
	' Build the new boot sector: the boot code (and its signature, at the
	' start of record 3) with d's BPB, and write it back, along with the
	' rest of d's record 3 (the start of its first FAT)
	H = CVI(MID$(T$, 27, 2)) * CVI(MID$(T$, 25, 2))
	R = CVI(MID$(T$, 15, 2)) + ASC(MID$(T$, 17)) * CVI(MID$(T$, 23, 2))
	B = R + (CVI(MID$(T$, 18, 2)) * 32 + 511) \ 512
	P$ = MID$(T$, 4, 33) + CHR$(0) + MKI$(H) + MKI$(R) + MKI$(B)
	OPEN D$ AS #1 LEN = 255
	FIELD #1, 255 AS R$
	GET #1, 3 : B3$ = B3$ + MID$(R$, 3)
	LSET R$ = LEFT$(B1$, 3) + P$ + MID$(B1$, 44) : PUT #1, 1
	LSET R$ = B2$ : PUT #1, 2
	LSET R$ = B3$ : PUT #1, 3
	CLOSE #1
	PRINT "System transferred"
	END
85	PRINT "Drive "; D$; " doesn't have a FAT volume" : END
90	CLOSE
	IF ERR = 70 THEN PRINT "Write protect error" : END
	IF ERR = 71 THEN PRINT "Drive not ready" : END
	IF ERR = 75 THEN PRINT "Invalid drive specification" : END
	PRINT "Unable to transfer the system (error"; ERR; ")"
	END
