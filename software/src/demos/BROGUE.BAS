	' BROGUE.BAS: a dungeon crawl in the spirit of Rogue (work in progress)
	'
	' Each depth is an 80x22 map of 2 to 6 rooms, joined in a path by
	' hallways.  You (u) start on the stairs up (<) in the first room,
	' and the stairs down (>) are in the last.  Every room is a puzzle:
	' stones (O) are in the way, and a stone that's pushed rolls until
	' something stops it.  Move with the cursor keys or h, j, k, and l; R
	' resets the room you're in, N makes a new map, and Q quits.
	'
	' The screen's top row is for messages and row 24 is for status, so the
	' map (M$) is on rows 2-23, which fits a VT100 as well as a video
	' display.  Walls (H$ and V$, and the corners) and blocks (P$) are the
	' PC's line-drawing characters, which a VT100 console displays with
	' its own (a checkerboard for the blocks).  A door is an opening in a
	' wall with a corner on either side, turned outward, so it's always 2
	' or more cells from the room's corners.  A hallway is a path of blank
	' cells between two doors, with a wall on either side that joins the
	' doors' corners, so the only blank cells that can be reached are in
	' hallways and doors.
	'
	' Rooms are placed in a grid of 3x2 cells: map rows 1-9 and 14-22, and
	' columns 2-25, 29-52, and 56-79, so there are always 4 or more columns
	' between rooms in a row.  The rooms are numbered in a path through the
	' cells (along the top row, then back along the bottom row), so linking
	' each room to the next never crosses another room; the hallway from
	' the top row to the bottom row turns in a free row between them (G).
	'
	' The puzzles are in the DATA at the end (see BROGUE.md, which shows
	' and rates them all): each has 2 doors, and can be solved from either
	' one.  A room gets a puzzle near the depth's difficulty with doors
	' that suit its walls, randomly flipped and turned (TF).  A room larger
	' than its puzzle is filled with blocks, and blank cells run in from
	' its doors to the puzzle's, so the puzzle is no easier; stones roll
	' only on floor (.), never onto a blank cell.
	'
	DEFINT A-Z
	DIM M$(23), I$(22), X1(6), Y1(6), X2(6), Y2(6), KC(6)
	DIM EX(6), EY(6), LX(6), LY(6)
	DIM PD(40), PT(40), PA(40), PB(40), PH(40), PS(40), PU(40), R$(240)
	DEF FNR(N) = RND% MOD N
	RANDOMIZE
	H$ = CHR$(196) : V$ = CHR$(179) : P$ = CHR$(177)
	B$ = SPACE$(80) : C$ = CHR$(19) + CHR$(24) + CHR$(5) + CHR$(4)
	' The corners on either side of a door, for each wall (W is 1-4 for
	' the left, bottom, top, and right walls, like the moves)
	Q$ = CHR$(217) + CHR$(191) + CHR$(191) + CHR$(218)
	Q$ = Q$ + CHR$(217) + CHR$(192) + CHR$(192) + CHR$(218)
	' Read the puzzles: difficulty (PD), doors (PT is 0 for left and right
	' walls, at rows PA and PB, or 1 for left and bottom walls, at row PA
	' and column PB), and PH rows (R$) of floor, blocks (#), and stones
	READ NP : J = 0
	FOR P = 1 TO NP
	READ PD(P), PT(P), PA(P), PB(P), PH(P) : PS(P) = J
	FOR I = 1 TO PH(P) : J = J + 1 : READ R$(J) : NEXT
	NEXT
	L = 1
	' Choose NR of the 6 cells (KC); NT counts the rooms in the top row
10	CLS : PRINT "Depth" + STR$(L);
	FOR Y = 0 TO 23 : M$(Y) = B$ : NEXT
	NR = 2 + FNR(2) + L \ 2 : IF NR > 6 THEN NR = 6
	N = 0 : NT = 0 : D = FNR(2) : G = 11 + FNR(2) : GN = GN + 1
	FOR K = 0 TO 5
	IF FNR(6 - K) >= NR - N THEN GOTO 15
	N = N + 1 : KC(N) = K : IF K < 3 THEN NT = N
15	NEXT
	' Room R is in row K and column C, and the path enters by wall WA and
	' leaves by wall WB; the stairs take the place of a door in the first
	' and last rooms, on any wall that isn't opposite a top or bottom door
	FOR R = 1 TO N
	K = KC(R) : C = K MOD 3 : K = K \ 3 : IF K <> D THEN C = 2 - C
	WB = 4 - 3 * D : IF K THEN WB = 5 - WB
	WA = 5 - WB : IF R = NT + 1 AND NT > 0 THEN WA = 3
	IF R = NT AND N > NT THEN WB = 2
	IF R = 1 THEN WA = 0
	IF R = N THEN WB = 0
	IF WA + WB = 0 THEN WB = 1 + 3 * FNR(2)
	IF WA > 0 AND WB > 0 THEN GOTO 25
20	U = 1 + FNR(4) : V = WA + WB
	IF U = V OR (U + V = 5 AND U > 1 AND U < 4) THEN GOTO 20
	IF WA THEN WB = U ELSE WA = U
	' Choose puzzle Q at random from those of the room's type (T) that
	' are within 2 of the depth's difficulty and not yet used in this
	' map (PU), widening the range if there are none
25	T = -(WA + WB <> 5) : IF R = 1 THEN SW = WA
	HI = L : IF HI > 10 THEN HI = 10
	LO = HI - 2
30	J = 0
	FOR P = 1 TO NP
	IF PT(P) <> T OR PD(P) < LO OR PD(P) > HI OR PU(P) = GN THEN GOTO 35
	J = J + 1 : IF FNR(J) = 0 THEN Q = P
35	NEXT
	IF J = 0 THEN LO = LO - 1 : HI = HI + 1 : GOTO 30
	PU(Q) = GN : PW = LEN(R$(PS(Q) + 1))
	' Choose a transformation (see 400) that puts the puzzle's doors on
	' walls WA and WB, in a puzzle no more than 7 rows high
40	TF = FNR(8) : TW = PW : TH = PH(Q) : IF TF AND 4 THEN SWAP TW, TH
	IF TH > 7 THEN GOTO 40
	I = 0 : J = PA(Q) : GOSUB 400 : AU = U : AV = V : A = W
	I = PB(Q) : J = PH(Q) + 1 : IF T = 0 THEN I = PW + 1 : J = PB(Q)
	GOSUB 400 : BU = U : BV = V : BW = W
	IF (A <> WA OR W <> WB) AND (A <> WB OR W <> WA) THEN GOTO 40
	' Make the room up to 3 columns and 2 rows larger than the puzzle,
	' fill it with blocks, and copy the puzzle's other cells into it
	RW = TW + 2 + FNR(4) : IF RW > 24 THEN RW = 24
	RH = TH + 2 + FNR(3) : IF RH > 9 THEN RH = 9
	X = 2 + 27 * C + FNR(25 - RW) : Y = 1 + 13 * K + FNR(10 - RH)
	X1(R) = X : Y1(R) = Y : X2(R) = X + RW - 1 : Y2(R) = Y + RH - 1
	T$ = STRING$(RW - 2, H$)
	MID$(M$(Y), X) = CHR$(218) + T$ + CHR$(191)
	MID$(M$(Y2(R)), X) = CHR$(192) + T$ + CHR$(217)
	T$ = V$ + STRING$(RW - 2, P$) + V$
	FOR J = Y + 1 TO Y2(R) - 1 : MID$(M$(J), X) = T$ : NEXT
	X0 = X + FNR(RW - 1 - TW) : Y0 = Y + FNR(RH - 1 - TH)
	FOR J = 1 TO PH(Q)
	T$ = R$(PS(Q) + J)
	FOR I = 1 TO PW
	K$ = MID$(T$, I, 1)
	IF K$ <> "#" THEN GOSUB 400 : MID$(M$(Y0 + V), X0 + U, 1) = K$
	NEXT I, J
	X = X0 + AU : Y = Y0 + AV : W = A : GOSUB 420
	X = X0 + BU : Y = Y0 + BV : W = BW : GOSUB 420
	' For variety, open a few of the blocks around the puzzle that have
	' no floor, stone, or blank cell next to them (so they can't be
	' reached)
	FOR J = 1 TO ((RW - 2) * (RH - 2) - TW * TH) \ 4
	X = X1(R) + 1 + FNR(RW - 2) : Y = Y1(R) + 1 + FNR(RH - 2)
	T$ = MID$(M$(Y - 1), X, 1) + MID$(M$(Y), X - 1, 3)
	T$ = T$ + MID$(M$(Y + 1), X, 1)
	I = INSTR(T$, ".") + INSTR(T$, "O") + INSTR(T$, " ")
	IF I = 0 AND MID$(T$, 3, 1) = P$ THEN MID$(M$(Y), X, 1) = "."
	NEXT J, R
	' Link each room's exit to the next room's entrance, and save the
	' map (I$) for R
	FOR R = 1 TO N - 1
	X = LX(R) : Y = LY(R) : U = EX(R + 1) : V = EY(R + 1)
	IF R = NT THEN GOSUB 200 ELSE GOSUB 100
	NEXT
	FOR Y = 1 TO 22
	I$(Y) = M$(Y)
	IF M$(Y) <> B$ THEN LOCATE Y + 1, 1 : PRINT M$(Y);
	NEXT
	LOCATE 1, 6 + LEN(STR$(L))
	PRINT ": push the stones (O) out of your way to the stairs (>)";
	LOCATE 24, 1
	PRINT "Move: h j k l  Reset room: R  New map: N  Quit: Q";
	PX = EX(1) : PY = EY(1) : SX = PX : SY = PY
	' Each move (D is 1-4 for left, down, up, and right) must be to a
	' floor, blank, or stairs cell, or else push a stone; the cursor stays
	' on the player.  A cursor key is a null and a scan code, or one of
	' the codes in C$.  (SX,SY) is the last cell the player was on that
	' wasn't floor, which is where R puts the player.  The stairs up are
	' in wall SW, and the only way off them is back into the room.
50	LOCATE PY + 1, PX : PRINT "u"; : LOCATE PY + 1, PX
	K$ = INPUT$(1) : IF K$ = CHR$(0) THEN K$ = K$ + INPUT$(1)
	D = INSTR("hjkl", K$) + INSTR(C$, K$)
	IF ASC(K$) = 0 THEN D = INSTR("KPHM", RIGHT$(K$, 1))
	K$ = UCASE$(K$)
	IF K$ = "N" THEN GOTO 10
	IF K$ = "Q" THEN CLS : END
	IF K$ = "R" THEN GOTO 70
	DX = (D = 1) - (D = 4) : DY = (D = 3) - (D = 2)
	X = PX + DX : Y = PY + DY : T$ = MID$(M$(Y), X, 1)
	IF D = 0 OR (D = SW AND PX = EX(1) AND PY = EY(1)) THEN GOTO 50
	IF T$ = "O" THEN GOTO 60
	IF INSTR("<>. ", T$) = 0 THEN GOTO 50
	PRINT MID$(M$(PY), PX, 1); : PX = X : PY = Y
	IF T$ <> "." THEN SX = X : SY = Y
	IF T$ = ">" THEN L = L + 1 : GOTO 10
	GOTO 50
	' Roll the stone at (X,Y) a cell at a time, for as long as the next
	' cell is floor (SOUND waits for the last one to end: a clock tick)
60	IF MID$(M$(Y + DY), X + DX, 1) <> "." THEN GOTO 50
	MID$(M$(Y), X, 1) = "." : LOCATE Y + 1, X : PRINT ".";
	X = X + DX : Y = Y + DY
	MID$(M$(Y), X, 1) = "O" : LOCATE Y + 1, X : PRINT "O";
	SOUND 32767, 1
	GOTO 60
	' Restore the room that the player is in (if any), and put the
	' player back at its door
70	FOR R = 1 TO N
	IF PX < X1(R) OR PX > X2(R) OR PY < Y1(R) OR PY > Y2(R) THEN GOTO 75
	FOR Y = Y1(R) + 1 TO Y2(R) - 1
	X = X1(R) + 1 : T$ = MID$(I$(Y), X, X2(R) - X)
	MID$(M$(Y), X) = T$ : LOCATE Y + 1, X : PRINT T$;
	NEXT
	PX = SX : PY = SY
75	NEXT
	GOTO 50
	' Link doors (X,Y) and (U,V), which are in side walls that face each
	' other, with a hallway that turns up or down (S) in a column between
	' them (I), unless they're in the same row.  The hallway's cells are
	' already blank, so only its walls are drawn: one that turns outside
	' column I, and one that turns inside it.
100	IF X > U THEN SWAP X, U : SWAP Y, V
	S = SGN(V - Y) : T$ = STRING$(U - X - 1, H$)
	IF S THEN GOTO 110
	MID$(M$(Y - 1), X + 1) = T$ : MID$(M$(Y + 1), X + 1) = T$
	RETURN
110	I = X + 2 + FNR(U - X - 3) : K$ = CHR$(204 - 13 * S)
	MID$(M$(Y - S), X + 1) = STRING$(I - X, H$) + K$
	MID$(M$(Y + S), X + 1) = STRING$(I - X - 2, H$) + K$
	K$ = CHR$(205 - 13 * S)
	MID$(M$(V - S), I + 1) = K$ + STRING$(U - I - 2, H$)
	MID$(M$(V + S), I - 1) = K$ + STRING$(U - I, H$)
	FOR J = Y TO V - 2 * S STEP S : MID$(M$(J), I + 1, 1) = V$ : NEXT
	FOR J = Y + 2 * S TO V STEP S : MID$(M$(J), I - 1, 1) = V$ : NEXT
	RETURN
	' Link door (X,Y), in a bottom wall, and door (U,V), in a top wall,
	' with a hallway that goes down to row G, left or right (S), and down
	' again, unless they're in the same column
200	S = SGN(U - X)
	IF S THEN GOTO 210
	FOR J = Y + 1 TO V - 1 : MID$(M$(J), X - 1, 3) = V$ + " " + V$ : NEXT
	RETURN
210	FOR J = Y + 1 TO G : MID$(M$(J), X - S, 1) = V$ : NEXT
	FOR J = Y + 1 TO G - 2 : MID$(M$(J), X + S, 1) = V$ : NEXT
	FOR J = G + 2 TO V - 1 : MID$(M$(J), U - S, 1) = V$ : NEXT
	FOR J = G TO V - 1 : MID$(M$(J), U + S, 1) = V$ : NEXT
	T$ = STRING$(ABS(U - X) - 1, H$)
	IF S = 1 THEN T$ = CHR$(192) + T$ + CHR$(191)
	IF S < 0 THEN T$ = CHR$(218) + T$ + CHR$(217)
	IF X > U THEN X = U
	MID$(M$(G + 1), X - S) = T$ : MID$(M$(G - 1), X + S) = T$
	RETURN
	' Transform puzzle cell (I,J) to (U,V): TF bit 2 swaps columns and
	' rows, then bit 0 flips the columns and bit 1 flips the rows, in a
	' puzzle that's now TW by TH.  The cells around the puzzle (eg,
	' column 0) are its walls, so this works for doors as well, and W is
	' the wall that (U,V) is in, if any.
400	U = I : V = J : IF TF AND 4 THEN SWAP U, V
	IF TF AND 1 THEN U = TW + 1 - U
	IF TF AND 2 THEN V = TH + 1 - V
	W = -(U = 0) - 4 * (U > TW) - 3 * (V = 0) - 2 * (V > TH)
	RETURN
	' Make a door for the puzzle's door at (X,Y), in wall W: blank cells
	' from there to the room's wall, and the wall's corners (see Q$); it's
	' the room's entrance (EX,EY) if W is WA, or else its exit (LX,LY).
	' The first room's entrance and the last room's exit are stairs
	' instead, which have no corners.
420	DX = (W = 1) - (W = 4) : DY = (W = 3) - (W = 2)
430	MID$(M$(Y), X, 1) = " "
	IF X = X1(R) OR X = X2(R) OR Y = Y1(R) OR Y = Y2(R) THEN GOTO 440
	X = X + DX : Y = Y + DY : GOTO 430
440	IF W = WA THEN EX(R) = X : EY(R) = Y ELSE LX(R) = X : LY(R) = Y
	IF R = 1 AND W = WA THEN MID$(M$(Y), X, 1) = "<" : RETURN
	IF R = N AND W <> WA THEN MID$(M$(Y), X, 1) = ">" : RETURN
	I = -(W = 2 OR W = 3) : J = 1 - I
	MID$(M$(Y - J), X - I, 1) = MID$(Q$, 2 * W - 1, 1)
	MID$(M$(Y + J), X + I, 1) = MID$(Q$, 2 * W, 1)
	RETURN
	' The puzzles (see BROGUE.md): the first item is how many there are
	DATA 25
	DATA 1,0,2,3,4,"...","O..","...","..."
	DATA 1,0,2,2,3,"..O..","..O..","..O.."
	DATA 1,0,2,4,5,"O....",".O...","..O..","...O.","....O"
	DATA 1,1,2,2,3,"...","O..","..."
	DATA 1,1,2,2,3,"...",".O.","#.#"
	DATA 1,1,2,3,4,".O..","O...","..O.","...."
	DATA 2,0,2,2,3,"..#..","..O..","..#.."
	DATA 2,0,2,4,5,"...","O..","...","..O","..."
	DATA 2,1,2,2,3,"...","O..",".O."
	DATA 3,0,3,3,4,".#..","..O.","O.O.","...#"
	DATA 4,0,2,2,3,".O.",".O.",".O."
	DATA 4,1,2,2,5,"....","O...",".#..","#.O.",".O.#"
	DATA 4,1,2,3,4,"#...",".O..",".O..","#.O."
	DATA 5,0,3,3,5,"..O.O..","..O.O..","..O.O..","..O.O..","..O.O.."
	DATA 5,1,2,2,5,".#..",".O..",".OO.","#..#","..#."
	DATA 6,0,2,2,3,"..O..#..",".O.OO.O.","..#..O.."
	DATA 7,0,2,4,5,".#....","O..#..",".O.#..",".OO..O","..O..."
	DATA 7,1,4,5,5,"......","#.##..",".O..O#","O.#...",".#..O."
	DATA 8,0,2,3,5,"...O..","O...#.","..#.O.","#.O.O.","...#.."
	DATA 8,1,3,2,5,"...#..","....O.","..O.OO","##OO..","....#."
	DATA 8,1,4,6,5,"..#....",".OO.#..","..OO.#.",".#.OO..",".#...O."
	DATA 9,0,3,4,5,"..#....","..#.O..",".#.OO.O","O.OO.#.","....#.."
	DATA 9,1,3,3,7,"......#","...#.O.","O.#.O..","..#.O.#",".#.#OO."
	DATA "#....O.","..O.#.."
	DATA 10,0,3,2,5,"...#....","..O.#..O","O.O.O.#.","..#.O..#","...#...."
	DATA 10,1,3,3,6,"..O..#",".O.O..","O..#O.",".##..O","#..OO.","..O..#"
