	' DALEKS.BAS: the classic chase, in one room
	'
	' Each level is one large room, with a door on one side, where you (u)
	' come in, and a door on the opposite side, which is the way out.
	' Every time you move, each Dalek (D) moves a cell toward you; reach
	' the way out before a Dalek reaches you, and you go on to the next
	' level, which has more Daleks.  Daleks that move to the same cell, or
	' onto a heap of scrap (#), become one.  T teleports you to a random
	' cell (maybe next to a Dalek), and Z uses a sonic screwdriver, which
	' destroys every Dalek next to you: you get one at each level, and
	' keep the ones you don't use.  Move with the cursor keys (Home, PgUp,
	' End, and PgDn for the diagonals) or h, j, k, l, y, u, b, and n; .
	' waits, R starts the level over, and Q quits.
	'
	' The map (M$) is drawn as in BROGUE.BAS, on rows 2-23, with a cell
	' every other column (every X is a column).  R makes the level again
	' from its seed (SEED), with the screwdrivers you came with (SK).
	'
	DEFINT A-Z
	DIM M$(23), KX(110), KY(110), KR(110)
	DEF FNR(N) = RND% MOD N
	H$ = CHR$(196) : V$ = CHR$(179)
	B$ = SPACE$(81) : C$ = CHR$(19) + CHR$(24) + CHR$(5) + CHR$(4)
	F$ = "" : FOR I = 1 TO 40 : F$ = F$ + ". " : NEXT
	' The corners on either side of a door, for each wall (W is 1-4 for
	' the left, bottom, top, and right walls, like the moves)
	Q$ = CHR$(217) + CHR$(191) + CHR$(191) + CHR$(218)
	Q$ = Q$ + CHR$(217) + CHR$(192) + CHR$(192) + CHR$(218)
	IF ARG$(1) <> "" THEN GOTO 990
	L = 1 : SK = 1
5	RANDOMIZE : SEED = RND%
	' Make a room of RH rows (18-22, walls included) by RW cells (within 2
	' of RH), in the middle of the screen, with the entrance (EX,EY) in
	' wall WA and the way out (LX,LY) in the opposite wall
10	RANDOMIZE SEED : SD = SK : CLS
	FOR Y = 0 TO 23 : M$(Y) = B$ : NEXT
	RH = 18 + FNR(5) : RW = RH - 2 + FNR(5)
	X1 = 1 + 2 * ((40 - RW) \ 2) : Y1 = 1 + (22 - RH) \ 2
	X2 = X1 + 2 * RW - 2 : Y2 = Y1 + RH - 1
	T$ = STRING$(2 * RW - 3, H$)
	MID$(M$(Y1), X1) = CHR$(218) + T$ + CHR$(191)
	MID$(M$(Y2), X1) = CHR$(192) + T$ + CHR$(217)
	T$ = V$ + " " + LEFT$(F$, 2 * RW - 4) + V$
	FOR Y = Y1 + 1 TO Y2 - 1 : MID$(M$(Y), X1) = T$ : NEXT
	WA = 1 + FNR(4) : W = WA : GOSUB 420 : EX = X : EY = Y
	W = 5 - WA : GOSUB 420 : LX = X : LY = Y
	' Put K Daleks (7, and 3 more for each level) on the floor, 6 or more
	' cells from the entrance and 3 or more from the way out
	A = (RW - 2) * (RH - 2) : K = 4 + 3 * L : IF K > A \ 4 THEN K = A \ 4
	NK = 0
	FOR J = 1 TO 20 * K
	X = X1 + 2 + 2 * FNR(RW - 2) : Y = Y1 + 1 + FNR(RH - 2)
	IF NK = K OR MID$(M$(Y), X, 1) <> "." THEN GOTO 30
	IF ABS(X - EX) < 12 AND ABS(Y - EY) < 6 THEN GOTO 30
	IF ABS(X - LX) < 6 AND ABS(Y - LY) < 3 THEN GOTO 30
	NK = NK + 1 : KX(NK) = X : KY(NK) = Y : KR(NK) = 1
	MID$(M$(Y), X, 1) = "D"
30	NEXT
	FOR Y = Y1 TO Y2 : LOCATE Y + 1, 1 : PRINT LEFT$(M$(Y), 80); : NEXT
	' Teleports use the tick count, so they're different every time
	RANDOMIZE
	M1$ = "Reach the way out before a Dalek reaches you"
	PX = EX : PY = EY : GOSUB 500
	' Each move (D is 1-8, as in BROGUE.BAS) must be to a floor cell or a
	' door; the cursor stays on the player.
50	LOCATE PY + 1, PX : PRINT "u"; : LOCATE PY + 1, PX
	K$ = INPUT$(1) : IF K$ = CHR$(0) THEN K$ = K$ + INPUT$(1)
	D = INSTR("hjklyubn", K$) + INSTR(C$, K$)
	IF ASC(K$) = 0 THEN D = INSTR("KPHMGIOQ", RIGHT$(K$, 1))
	IF D THEN GOTO 55
	K$ = UCASE$(K$)
	IF K$ = "R" THEN GOTO 10
	IF K$ = "Q" THEN CLS : END
	IF K$ = "." THEN GOTO 80
	IF K$ = "T" THEN GOTO 60
	IF K$ <> "Z" THEN GOTO 50
	' Use a screwdriver on every Dalek next to the player
	M1$ = "You have no sonic screwdriver"
	IF SD = 0 THEN GOSUB 500 : GOTO 50
	SD = SD - 1 : M1$ = "" : GOSUB 500 : SOUND 2000, 2
	FOR I = 1 TO NK
	IF KR(I) = 0 OR ABS(KX(I) - PX) > 2 OR ABS(KY(I) - PY) > 1 THEN GOTO 52
	KR(I) = 0 : MID$(M$(KY(I)), KX(I), 1) = "."
	LOCATE KY(I) + 1, KX(I) : PRINT ".";
52	NEXT
	GOTO 80
55	DX = 2 * (ASC(MID$("01120202", D, 1)) - 49)
	DY = ASC(MID$("12010022", D, 1)) - 49
	X = PX + DX : Y = PY + DY : T$ = MID$(M$(Y), X, 1)
	IF T$ = " " AND (X <> EX OR Y <> EY) AND (X <> LX OR Y <> LY) THEN GOTO 50
	IF T$ <> "." AND T$ <> " " THEN GOTO 50
	LOCATE PY + 1, PX : PRINT MID$(M$(PY), PX, 1); : PX = X : PY = Y
	IF X <> LX OR Y <> LY THEN GOTO 80
	' The way out: on to the next level, with another screwdriver
	L = L + 1 : SK = SD + 1 : SOUND 1000, 2 : GOTO 5
	' Teleport to a random floor cell
60	X = X1 + 2 + 2 * FNR(RW - 2) : Y = Y1 + 1 + FNR(RH - 2)
	IF MID$(M$(Y), X, 1) <> "." THEN GOTO 60
	LOCATE PY + 1, PX : PRINT MID$(M$(PY), PX, 1); : PX = X : PY = Y
	' The Daleks move at once (as they did in BROGUE.BAS): each one makes
	' the first move that isn't blocked (see 90): toward the player
	' diagonally, across, or up or down, or else it stays put; Daleks in
	' the same cell, or on a heap, become a heap (#), and E is set if one
	' reaches the player.
80	FOR I = 1 TO NK : IF KR(I) = 0 THEN GOTO 82
	MID$(M$(KY(I)), KX(I), 1) = "." : LOCATE KY(I) + 1, KX(I) : PRINT ".";
82	NEXT
	E = 0
	FOR I = 1 TO NK : IF KR(I) = 0 THEN GOTO 85
	X = KX(I) : Y = KY(I) : U = 2 * SGN(PX - X) : V = SGN(PY - Y)
	GOSUB 90
	IF J OR U = 0 OR V = 0 THEN GOTO 83
	W = V : V = 0 : GOSUB 90 : IF J THEN GOTO 83
	U = 0 : V = W : GOSUB 90
83	IF J = 0 THEN U = 0 : V = 0 : GOSUB 90
	X = X + U : Y = Y + V : KX(I) = X : KY(I) = Y
	IF J = 4 THEN E = 1 ELSE MID$(M$(Y), X, 1) = MID$("D##", J, 1)
	IF J = 2 OR J = 3 THEN KR(I) = 0
	LOCATE Y + 1, X : PRINT MID$("D##D", J, 1);
85	NEXT
	FOR I = 1 TO NK
	IF KR(I) AND MID$(M$(KY(I)), KX(I), 1) = "#" THEN KR(I) = 0
	NEXT
	IF E = 0 THEN GOTO 50
	M1$ = "EXTERMINATED!  R retries the level, N starts over, Q quits"
	GOSUB 500 : SOUND 100, 9
87	K$ = UCASE$(INPUT$(1)) : IF K$ = CHR$(0) THEN K$ = INPUT$(1) : GOTO 87
	IF K$ = "R" THEN GOTO 10
	IF K$ = "N" THEN L = 1 : SK = 1 : GOTO 5
	IF K$ = "Q" THEN CLS : END
	GOTO 87
	' Set J for the move (U,V) of the Dalek at (X,Y): 0 if it's blocked,
	' 1-3 for floor, a Dalek that's already moved, or a heap, or 4 for the
	' player
90	J = INSTR(".D#", MID$(M$(Y + V), X + U, 1))
	IF X + U = PX AND Y + V = PY THEN J = 4
	RETURN
	' Make a door (X,Y) in wall W, 2 or more cells from its corners, with
	' a corner on either side (see Q$, and blank columns between them in a
	' top or bottom wall)
420	X = X1 : IF W = 4 THEN X = X2
	Y = Y1 : IF W = 2 THEN Y = Y2
	IF W = 2 OR W = 3 THEN X = X + 4 + 2 * FNR(RW - 4) : GOTO 425
	Y = Y + 2 + FNR(RH - 4)
425	MID$(M$(Y), X, 1) = " "
	K$ = MID$(Q$, 2 * W - 1, 1) : T$ = MID$(Q$, 2 * W, 1)
	IF W = 2 OR W = 3 THEN MID$(M$(Y), X - 2) = K$ + "   " + T$ : RETURN
	MID$(M$(Y - 1), X, 1) = K$ : MID$(M$(Y + 1), X, 1) = T$
	RETURN
	' Display the name, message (M1$), and level on the top row, and the
	' keys on the bottom row
500	T$ = "Level" + STR$(L)
	LOCATE 1, 1 : PRINT LEFT$("DALEKS   " + M1$ + B$, 79 - LEN(T$)) + T$;
	T$ = "Move: hjklyubn  Wait: .  Teleport: T  Zap: Z (" + MID$(STR$(SD), 2)
	LOCATE 24, 1 : PRINT T$ + " left)  Retry: R  Quit: Q  ";
	RETURN
990	END 80 ' BERR_USAGE
