	' BROGUE.BAS: a dungeon crawl in the spirit of Rogue (work in progress)
	'
	' Generates an 80x22 map of 1 to 6 rooms, each connected to the next by
	' a passage one cell wide, between doors.  The screen's top row is for
	' messages and row 24 is for status, so the map (M$) is on rows 2-23,
	' which fits a VT100 as well as a video display.  Move "u" with the
	' cursor keys or h, j, k, and l; N makes a new map, and Q quits.
	'
	' Walls (H$ and V$, and the corners) and passages (P$) are the PC's
	' line-drawing characters (single lines), which a VT100 console
	' displays with its own (and a checkerboard for the passages), so the
	' map looks much the same on either.  A door is an opening in a wall
	' with a corner on either side, turned outward, so it's always 2 or
	' more cells from the room's corners.
	'
	' Rooms are placed in a grid of 3x2 cells: map rows 1-9 and 14-22, and
	' columns 2-25, 29-52, and 56-79, so there are always 4 or more columns
	' between rooms in a row.  The rooms are numbered in a path through the
	' cells (along the top row, then back along the bottom row), so linking
	' each room to the next never crosses another room; the passage from
	' the top row to the bottom row turns in a free row between them (G).
	' When both rows have 2 or more rooms, a passage may link the first and
	' last rooms as well, so every room has 1 or 2 passages.
	'
	DEFINT A-Z
	DIM M$(22), X1(6), Y1(6), X2(6), Y2(6)
	DEF FNR(N) = RND% MOD N
	RANDOMIZE
	H$ = CHR$(196) : V$ = CHR$(179) : P$ = CHR$(177)
	B$ = SPACE$(80) : C$ = CHR$(19) + CHR$(24) + CHR$(5) + CHR$(4)
	' Choose NR of the 6 cells, and give each a room of 5-24 columns by
	' 5-9 rows (walls included); NT counts the rooms in the top row
10	FOR Y = 1 TO 22 : M$(Y) = B$ : NEXT
	N = 0 : NT = 0 : NR = 1 + FNR(6) : D = FNR(2) : G = 11 + FNR(2)
	FOR K = 0 TO 5
	IF FNR(6 - K) >= NR - N THEN GOTO 20
	R = K \ 3 : C = K MOD 3 : IF R <> D THEN C = 2 - C
	W = 5 + FNR(20) : H = 5 + FNR(5)
	X = 2 + 27 * C + FNR(25 - W) : Y = 1 + 13 * R + FNR(10 - H)
	N = N + 1 : IF R = 0 THEN NT = N
	X1(N) = X : Y1(N) = Y : X2(N) = X + W - 1 : Y2(N) = Y + H - 1
	T$ = STRING$(W - 2, H$)
	MID$(M$(Y), X) = CHR$(218) + T$ + CHR$(191)
	MID$(M$(Y2(N)), X) = CHR$(192) + T$ + CHR$(217)
	FOR Y = Y + 1 TO Y2(N) - 1
	MID$(M$(Y), X) = V$ + STRING$(W - 2, ".") + V$
	NEXT
20	NEXT
	' Link each room to the next, and perhaps the last room to the first
	FOR I = 1 TO N - 1
	A = I : B = I + 1 : Q = 0
	IF I = NT THEN GOSUB 200 ELSE GOSUB 100
	NEXT
	A = 1 : B = N : Q = 1
	IF NT > 1 AND N - NT > 1 AND FNR(2) THEN GOSUB 200
	' Display the map, and put the player in a room
	CLS
	FOR Y = 1 TO 22
	IF M$(Y) <> B$ THEN LOCATE Y + 1, 1 : PRINT M$(Y);
	NEXT
	LOCATE 1, 1 : PRINT "Welcome tae this wee dungeon demo!";
	LOCATE 24, 1 : PRINT "Rooms:"; N; " Move: h j k l  New: N  Quit: Q";
	I = 1 + FNR(N)
	PX = X1(I) + 1 + FNR(X2(I) - X1(I) - 1)
	PY = Y1(I) + 1 + FNR(Y2(I) - Y1(I) - 1)
	' Each move (D is 1-4 for left, down, up, and right) must be to a
	' floor or passage cell; the cursor stays on the player.  A
	' cursor key is a null and a scan code, or one of the codes in C$.
30	LOCATE PY + 1, PX : PRINT "u"; : LOCATE PY + 1, PX
	K$ = INPUT$(1) : IF K$ = CHR$(0) THEN K$ = K$ + INPUT$(1)
	D = INSTR("hjkl", K$) + INSTR(C$, K$)
	IF ASC(K$) = 0 THEN D = INSTR("KPHM", RIGHT$(K$, 1))
	IF UCASE$(K$) = "N" THEN GOTO 10
	IF UCASE$(K$) = "Q" THEN CLS : END
	X = PX + (D = 1) - (D = 4) : Y = PY + (D = 3) - (D = 2)
	IF D = 0 OR INSTR("." + P$, MID$(M$(Y), X, 1)) = 0 THEN GOTO 30
	PRINT MID$(M$(PY), PX, 1); : PX = X : PY = Y
	GOTO 30
	' Link rooms A and B, which are in the same row of cells, with a
	' passage from a door in the left room's right wall to a column between
	' the rooms (X), up or down, and on to a door in the right room's left
	' wall
100	IF X1(A) > X1(B) THEN SWAP A, B
	U = Y1(A) + 2 + FNR(Y2(A) - Y1(A) - 3)
	V = Y1(B) + 2 + FNR(Y2(B) - Y1(B) - 3)
	X = X2(A) + 2 + FNR(X1(B) - X2(A) - 3)
	MID$(M$(U), X2(A)) = "." + STRING$(X - X2(A), P$)
	MID$(M$(V), X) = STRING$(X1(B) - X, P$) + "."
	MID$(M$(U - 1), X2(A), 1) = CHR$(192)
	MID$(M$(U + 1), X2(A), 1) = CHR$(218)
	MID$(M$(V - 1), X1(B), 1) = CHR$(217)
	MID$(M$(V + 1), X1(B), 1) = CHR$(191)
	IF U > V THEN SWAP U, V
	FOR Y = U TO V : MID$(M$(Y), X, 1) = P$ : NEXT
	RETURN
	' Link room A (top row) and room B (bottom row) with a passage from a
	' door in A's bottom wall down to row G, across, and down to a door in
	' B's top wall.  X to W are the columns it uses in row G (saved in S1
	' and S2); a second passage (Q is set) is skipped if it would touch
	' the first.
200	U = X1(A) + 2 + FNR(X2(A) - X1(A) - 3)
	V = X1(B) + 2 + FNR(X2(B) - X1(B) - 3)
	X = U : W = V : IF X > W THEN SWAP X, W
	IF Q AND X <= S2 + 1 AND W >= S1 - 1 THEN RETURN
	S1 = X : S2 = W
	MID$(M$(Y2(A)), U - 1) = CHR$(191) + "." + CHR$(218)
	MID$(M$(Y1(B)), V - 1) = CHR$(217) + "." + CHR$(192)
	FOR Y = Y2(A) + 1 TO G : MID$(M$(Y), U, 1) = P$ : NEXT
	FOR Y = G TO Y1(B) - 1 : MID$(M$(Y), V, 1) = P$ : NEXT
	MID$(M$(G), X) = STRING$(W - X + 1, P$)
	RETURN
