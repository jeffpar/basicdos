	' ATAXX.BAS: a game of infection on a 7x7 board, against the computer
	'
	' You (solid pieces) and the computer (hollow pieces) start with two
	' pieces each, in opposite corners.  A move is to an empty cell: a cell
	' next to one of your pieces (in any of the 8 directions) grows a new
	' piece there, and a cell 2 away (in the ring around those) jumps the
	' piece there instead.  Either way, every one of the other player's
	' pieces next to that cell becomes yours.  When the player whose turn
	' it is can't move, the game ends, and the other player gets every
	' empty cell; whoever has more pieces wins.
	'
	' Move the cursor with the cursor keys (Home, PgUp, End, and PgDn for
	' the diagonals) or h, j, k, l, y, u, b, and n.  Space (or Enter) on an
	' empty cell next to one of your pieces grows a piece there, and on one
	' of your pieces, it picks that piece: the cells it can grow into are
	' marked with a dot, and the cells it can jump to with 4 dots, and Space
	' on one of those moves it there (Space on the piece again, or Esc,
	' puts it back).  1-4 set the level (how many moves the computer looks
	' ahead; it's 2 unless the command line gives one), N starts a new game
	' (the players take turns moving first), and Q quits.
	'
	' The board is 22 rows by 29 columns, or 43 on a console of 80 or more
	' columns (each cell is 3 rows by 4 or 6 columns, sharing its borders
	' with the cells around it, so a piece is 2 rows by 3 or 5 columns),
	' centered on the console, whose size IOCTL &HD1 gives, with the score
	' on the row above it and messages on the row below it, so it fits on
	' any console of 40 or more columns and 24 or more rows (eg, a 40-column
	' PC display or a VT100).  The board's lines are the PC's line-drawing
	' characters, which a VT100 displays with its own, along with the
	' computer's pieces (double lines on a PC), and it displays the solid
	' blocks of your pieces as checkerboards.
	'
	' The board (B) has 11 rows of 11, so that every cell has 2 more around
	' it in every direction: P = 11 * (row + 2) + column + 2 (Q lists the
	' 49 cells, and N has the offsets of the 8 cells next to a cell and the
	' 16 cells 2 away).  Your pieces are 1, the computer's are 32, empty
	' cells are 0, and the cells off the board are 1024, so adding up the
	' cells around a cell counts each player's pieces: (sum \ 1) AND 31 is
	' yours, and (sum \ 32) AND 31 is the computer's.
	'
	DEFINT A-Z
	DIM B(120), Q(49), N(24), G1$(4), G2$(4), PC(4), FR$(3)
	DIM SD(5), AL(5), BE(5), BV(5), CI(5), JI(5), TT(5), SS(5), G(5), PS(5)
	DIM FB(5), FL(40), NS(120), EL(49), EP(120)
	C$ = CHR$(19) + CHR$(24) + CHR$(5) + CHR$(4)
	A$ = ARG$(1) : LV = 2 : IF A$ <> "" THEN LV = INSTR("1234", A$)
	IF LV = 0 OR LEN(A$) > 1 OR ARG$(2) <> "" THEN GOTO 990
	FOR I = 1 TO 24 : READ N(I) : NEXT
	DATA -12, -11, -10, -1, 1, 10, 11, 12
	DATA -24, -23, -22, -21, -20, -13, -9, -2, 2, 9, 13, 20, 21, 22, 23, 24
	FOR I = 1 TO 49 : Q(I) = 24 + 11 * ((I - 1) \ 7) + (I - 1) MOD 7 : NEXT
	' Center the board (its top left corner is at row R0, column C0) and
	' the messages (39 columns, from column MC) on the console; with 80 or
	' more columns, whose characters are half as wide, the inside of a cell
	' is 5 columns wide instead of 3 (IW), and a cell is CW columns
	DOS &H44D1, 1 : W = DOS(3) AND 255 : H = DOS(3) \ 256
	IF W < 40 OR H < 24 THEN PRINT "ATAXX needs 40 columns and 24 rows" : END 1
	IW = 3 - 2 * (W >= 80) : CW = IW + 1
	C0 = (W - 7 * CW - 1) \ 2 + 1 : R0 = (H - 24) \ 2 + 2 : MC = (W - 39) \ 2 + 1
	' The top and bottom rows of each kind of cell (K): empty, yours, the
	' computer's, and empty cells that the picked piece can grow into (3)
	' or jump to (4), and their colors (PC)
	T$ = STRING$(IW - 2, 219) : U$ = SPACE$((IW - 3) \ 2)
	G1$(0) = SPACE$(IW) : G2$(0) = G1$(0) : PC(0) = 7
	G1$(1) = CHR$(220) + T$ + CHR$(220) : PC(1) = 12
	G2$(1) = CHR$(223) + T$ + CHR$(223)
	T$ = STRING$(IW - 2, 205)
	G1$(2) = CHR$(201) + T$ + CHR$(187) : PC(2) = 11
	G2$(2) = CHR$(200) + T$ + CHR$(188)
	G1$(3) = U$ + " . " + U$ : G2$(3) = U$ + " ' " + U$ : PC(3) = 14
	G1$(4) = U$ + ". ." + U$ : G2$(4) = U$ + "' '" + U$ : PC(4) = 14
	' The board's rows (FR$): the top, the rows between cells, the bottom,
	' and the rows inside cells, each made from its left, middle, and right
	' characters in F$
	F$ = CHR$(218) + CHR$(194) + CHR$(191) + CHR$(195) + CHR$(197)
	F$ = F$ + CHR$(180) + CHR$(192) + CHR$(193) + CHR$(217) + STRING$(3, 179)
	FOR K = 0 TO 3 : T$ = STRING$(IW, 196) : IF K = 3 THEN T$ = SPACE$(IW)
	U$ = MID$(F$, 3 * K + 1, 1)
	FOR I = 1 TO 7 : U$ = U$ + T$ + MID$(F$, 3 * K + 2 - (I = 7), 1) : NEXT
	FR$(K) = U$ : NEXT
	RANDOMIZE : FS = 1 : CX = 3 : CY = 3
	' Start a new game: S is the player whose turn it is (1 or 32), and FS
	' moves first in the next game
10	FOR I = 0 TO 120 : B(I) = 1024 : NEXT
	FOR I = 1 TO 49 : B(Q(I)) = 0 : NEXT
	B(Q(1)) = 1 : B(Q(49)) = 1 : B(Q(7)) = 32 : B(Q(43)) = 32
	COLOR 7, 0 : CLS : SL = 0 : HL = 0
	FOR Y = 0 TO 21 : K = 3 : IF Y MOD 3 = 0 THEN K = 1 + (Y = 0) - (Y = 21)
	LOCATE R0 + Y, C0 : PRINT FR$(K); : NEXT
	FOR I = 1 TO 49 : P = Q(I) : GOSUB 500 : NEXT
	S = FS : FS = 33 - FS
	' Display the score, and end the game if player S can't move
20	GOSUB 600 : IF HM = 0 THEN GOTO 80
	IF S = 32 THEN GOTO 60
	' Your move: the cursor (CX,CY) is the highlighted cell P, and SL is
	' the picked piece (or 0)
30	M$ = "Your move (Space picks, N new, Q quits)" : GOSUB 700
35	P = 24 + 11 * CY + CX : HL = 1 : GOSUB 500 : HL = 0 : LOCATE Y, X + IW \ 2
	K$ = INPUT$(1) : IF K$ = CHR$(0) THEN K$ = K$ + INPUT$(1)
	D = INSTR("hjklyubn", K$) + INSTR(C$, K$)
	IF ASC(K$) = 0 THEN D = INSTR("KPHMGIOQ", RIGHT$(K$, 1))
	IF D = 0 THEN GOTO 40
	GOSUB 500
	X = CX + ASC(MID$("01120202", D, 1)) - 49
	Y = CY + ASC(MID$("12010022", D, 1)) - 49
	IF X >= 0 AND X < 7 AND Y >= 0 AND Y < 7 THEN CX = X : CY = Y
	GOTO 35
40	K$ = UCASE$(K$) : I = INSTR("1234", K$)
	IF I THEN LV = I : GOSUB 600 : GOTO 35
	IF K$ = "Q" THEN GOTO 95
	IF K$ = "N" THEN GOTO 10
	IF K$ = CHR$(27) THEN GOSUB 550 : GOTO 30
	IF K$ <> " " AND K$ <> CHR$(13) THEN GOTO 35
	MT = P : MS = 0 : IF B(P) = 1 THEN GOTO 45
	IF B(P) THEN M$ = "That's one of the computer's pieces" : GOSUB 700 : GOTO 35
	' An empty cell: the picked piece jumps there if it's 2 away, or else
	' a piece next to it grows one there
	IF SL = 0 THEN GOTO 42
	DS = ABS(SL MOD 11 - P MOD 11) : A = ABS(SL \ 11 - P \ 11)
	IF A > DS THEN DS = A
	IF DS = 2 THEN MS = SL : GOTO 50
42	A = 0 : FOR J = 1 TO 8 : A = A OR (B(P + N(J)) = 1) : NEXT
	IF A THEN GOTO 50
	M$ = "You can't move there" : GOSUB 700 : GOTO 35
	' One of your pieces: pick it (or put it back, if it's picked)
45	IF SL = P THEN GOSUB 550 : GOTO 30
	GOSUB 550 : SL = MT : GOSUB 560
	M$ = "Move to a marked cell (Esc cancels)" : GOSUB 700 : GOTO 35
50	GOSUB 550 : MV = 1 : GOSUB 450 : S = 32 : GOTO 20
	' The computer's move: make the neighbor sums and the list of empty
	' cells (see 300), search for the best move (BT, from BS, or 0 to grow
	' one), unless it has only jumps that take nothing (see 650), and
	' highlight its cells for a moment before making it
60	M$ = "Thinking..." : GOSUB 700 : E = 0
	FOR I = 1 TO 49 : T = Q(I)
	NS(T) = B(T - 12) + B(T - 11) + B(T - 10) + B(T - 1) + B(T + 1) + B(T + 10) + B(T + 11) + B(T + 12)
	IF B(T) = 0 THEN E = E + 1 : EL(E) = T : EP(T) = E
	NEXT
	D = 1 : SD(1) = 32 : AL(1) = -999 : BE(1) = 999
	FP = 0 : BT = 0 : GOSUB 300 : IF BT = 0 THEN GOSUB 650
	HL = 1 : P = BT : GOSUB 500 : IF BS THEN P = BS : GOSUB 500
	HL = 0 : SOUND 32767, 6 : SOUND 32767, 1
	MS = BS : MT = BT : MV = 32 : GOSUB 450 : S = 1 : GOTO 20
	' Player S can't move, so the other player gets the empty cells (and
	' with all 49 cells filled, there's never a tie); a cursor key's scan
	' code is skipped
80	Z = 33 - S
	FOR I = 1 TO 49 : P = Q(I) : IF B(P) = 0 THEN B(P) = Z : GOSUB 500
	NEXT
	GOSUB 600 : A = C1 : Z = C2 : M$ = "You win"
	IF C2 > C1 THEN SWAP A, Z : M$ = "Computer wins"
	M$ = M$ + STR$(A) + "-" + MID$(STR$(Z), 2) + " (N new, Q quits)"
	GOSUB 700
85	K$ = UCASE$(INPUT$(1)) : IF K$ = "N" THEN GOTO 10
	IF K$ = CHR$(0) THEN K$ = INPUT$(1) : GOTO 85
	IF K$ <> "Q" THEN GOTO 85
95	COLOR 7, 0 : CLS
	END
	' Search for the best move of player SD(D) (D is the search's depth,
	' from 1 to the level, LV), the one with the most gain: 1 for growing
	' a piece, plus 2 for each piece taken, less the best gain of the other
	' player's reply (unless D is LV).  As in SUCKS1.C, a jump that takes
	' nothing isn't a move unless there are no others (see 360), but the
	' search is alpha-beta (AL and BE; the gain of a move whose reply
	' gains BE or more doesn't matter), and it makes each move on the board
	' and takes it back (see 400), instead of copying the board.  R is the
	' best gain, and the cells and gains of the moves being tried (TT, SS,
	' and G) and the best gain so far (BV) are kept for each depth.
	'
	' Since every array access is slow (about 250 microseconds on a 4.77
	' MHz PC), NS keeps the sum of the cells next to each cell, and EL lists
	' the E empty cells (EP is each one's place in the list); the moves
	' change them as they change the board (see 400 and 470).  Moves that
	' take 2 or more pieces are tried first, then those that take 1, and
	' then the rest (PS is the pass), so that alpha-beta skips more.
300	IF D = LV AND D > 1 THEN GOTO 350
	BV(D) = -999 : PS(D) = 0
305	PS(D) = PS(D) + 1 : CI(D) = 0 : IF PS(D) > 3 THEN GOTO 340
310	CI(D) = CI(D) + 1 : IF CI(D) > E THEN GOTO 305
	T = EL(CI(D)) : MV = SD(D) : TT(D) = T : Z = NS(T)
	K = (Z \ (33 - MV)) AND 31 : G(D) = K + K
	IF 3 + (K > 0) + (K > 1) <> PS(D) THEN GOTO 310
	IF (Z \ MV) AND 31 THEN SS(D) = 0 : G(D) = G(D) + 1 : GOSUB 400 : G(D) = G(D) - 1 : IF AL(D) >= BE(D) THEN GOTO 345
	IF G(D) = 0 THEN GOTO 310
	JI(D) = 8
320	JI(D) = JI(D) + 1 : IF JI(D) > 24 THEN GOTO 310
	SS(D) = TT(D) + N(JI(D)) : IF B(SS(D)) <> SD(D) THEN GOTO 320
	GOSUB 400 : IF AL(D) >= BE(D) THEN GOTO 345
	GOTO 320
340	IF BV(D) = -999 THEN GOTO 360
345	R = BV(D) : RETURN
	' The last depth (if it isn't the first) needs only the best gain,
	' not the move, and it stops at a gain of BE or more (WB): a jump that
	' takes nothing counts here, and a cell can be skipped if it can't
	' gain more than the best so far (E is the number of empty cells,
	' which the other player gets if this one can't move)
350	MV = SD(D) : OV = 33 - MV : R = -999 : WB = BE(D)
	FOR I = 1 TO E : Z = NS(EL(I)) : K = (Z \ OV) AND 31
	IF K + K < R THEN GOTO 355
	IF (Z \ MV) AND 31 THEN Z = K + K + 1 : GOTO 353
	IF K + K <= R THEN GOTO 355
	T = EL(I) : Z = -999 : FOR J = 9 TO 24 : IF B(T + N(J)) = MV THEN Z = K + K
	NEXT
353	IF Z > R THEN R = Z : IF R >= WB THEN I = E
355	NEXT
	IF R = -999 THEN R = -E
	RETURN
	' Player SD(D) has no move but a jump that takes nothing (which gains
	' nothing), or no move at all
360	R = -E : MV = SD(D)
	FOR I = 1 TO E : T = EL(I)
	FOR J = 9 TO 24 : IF B(T + N(J)) = MV THEN R = 0
	NEXT J, I
	RETURN
	' Try the move to TT(D) (from SS(D), or 0 to grow a piece), with gain
	' G(D): make it (FL lists the pieces it takes, from FB(D) + 1 to FP),
	' search the other player's replies, and take it back, restoring NS,
	' and EL in its original order.  The best move at the first depth is
	' the computer's move, and one of the moves with the same gain is
	' chosen at random (NT counts them).
400	R = 0 : IF D = LV THEN GOTO 420
	T = TT(D) : MV = SD(D) : OV = 33 - MV : U = SS(D)
	B(T) = MV : X = T : DL = MV : GOSUB 470
	L = EL(E) : EL(EP(T)) = L : EP(L) = EP(T) : E = E - 1
	IF U THEN B(U) = 0 : X = U : DL = -MV : GOSUB 470 : E = E + 1 : EL(E) = U : EP(U) = E
	FB(D) = FP : DL = MV - OV
	FOR J = 1 TO 8 : X = T + N(J) : IF B(X) = OV THEN B(X) = MV : FP = FP + 1 : FL(FP) = X : GOSUB 470
	NEXT
	SD(D + 1) = OV : AL(D + 1) = G(D) - BE(D) : BE(D + 1) = G(D) - AL(D)
	D = D + 1 : GOSUB 300 : D = D - 1
	MV = SD(D) : OV = 33 - MV : DL = OV - MV
	FOR J = FB(D) + 1 TO FP : X = FL(J) : B(X) = OV : GOSUB 470 : NEXT : FP = FB(D)
	T = TT(D) : U = SS(D)
	IF U THEN B(U) = MV : X = U : DL = MV : GOSUB 470 : E = E - 1
	B(T) = 0 : X = T : DL = -MV : GOSUB 470
	E = E + 1 : L = EL(EP(T)) : EL(E) = L : EP(L) = E : EL(EP(T)) = T
420	V = G(D) - R : IF D = 1 THEN GOTO 430
	IF V > BV(D) THEN BV(D) = V : IF V > AL(D) THEN AL(D) = V
	RETURN
	' At the first depth, AL stays 1 less than the best gain, so that the
	' search finds the gain of every move that's as good
430	IF V < BV(1) THEN RETURN
	IF V > BV(1) THEN BV(1) = V : AL(1) = V - 1 : NT = 0
	NT = NT + 1 : IF RND% MOD NT = 0 THEN BT = TT(1) : BS = SS(1)
	RETURN
	' Make the move to cell MT (from MS, or 0 to grow a piece) for player
	' MV, displaying each piece it takes in turn
450	OV = 33 - MV : IF MS THEN P = MS : B(P) = 0 : GOSUB 500
	P = MT : B(P) = MV : GOSUB 500
	FOR J = 1 TO 8 : P = MT + N(J) : IF B(P) = OV THEN B(P) = MV : SOUND 32767, 1 : GOSUB 500
	NEXT
	RETURN
	' Add DL to the sums (NS) of the cells next to cell X
470	NS(X - 12) = NS(X - 12) + DL : NS(X - 11) = NS(X - 11) + DL
	NS(X - 10) = NS(X - 10) + DL : NS(X - 1) = NS(X - 1) + DL
	NS(X + 1) = NS(X + 1) + DL : NS(X + 10) = NS(X + 10) + DL
	NS(X + 11) = NS(X + 11) + DL : NS(X + 12) = NS(X + 12) + DL
	RETURN
	' Display cell P (highlighted if HL is set), at column X and row Y;
	' while a piece is picked (SL), it blinks, and the empty cells 1 or 2
	' away are marked
500	K = 0 : IF B(P) = 1 THEN K = 1
	IF B(P) = 32 THEN K = 2
	IF K OR SL = 0 THEN GOTO 505
	DS = ABS(SL MOD 11 - P MOD 11) : A = ABS(SL \ 11 - P \ 11)
	IF A > DS THEN DS = A
	IF DS < 3 THEN K = 2 + DS
505	A = PC(K) : IF P = SL THEN A = A + 16
	IF HL THEN COLOR 0, 7 ELSE COLOR A, 0
	X = C0 + CW * (P MOD 11 - 2) + 1 : Y = R0 + 3 * (P \ 11) - 5
	LOCATE Y, X : PRINT G1$(K); : LOCATE Y + 1, X : PRINT G2$(K);
	COLOR 7, 0 : RETURN
	' Put the picked piece back (550), or pick SL (560), and display it
	' and the empty cells around it (Z)
550	IF SL = 0 THEN RETURN
	Z = SL : SL = 0 : GOTO 565
560	Z = SL
565	FOR J = 1 TO 24 : P = Z + N(J) : IF B(P) = 0 THEN GOSUB 500
	NEXT
	P = Z : GOSUB 500 : RETURN
	' Count the pieces (C1 and C2), set HM if player S can move, and
	' display the score and level
600	C1 = 0 : C2 = 0 : HM = 0
	FOR I = 1 TO 49 : T = Q(I) : Z = B(T) : C1 = C1 - (Z = 1) : C2 = C2 - (Z = 32)
	IF Z OR HM THEN GOTO 605
	FOR J = 1 TO 24 : IF B(T + N(J)) = S THEN HM = 1
	NEXT
605	NEXT
	T$ = "You" + STR$(C1) + "    Level" + STR$(LV) + "    Computer" + STR$(C2)
	Y = R0 - 1 : GOTO 705
	' The computer has only jumps that take nothing: choose one
650	FOR I = 1 TO 49 : T = Q(I) : IF B(T) THEN GOTO 655
	FOR J = 9 TO 24 : IF B(T + N(J)) = 32 THEN BT = T : BS = T + N(J)
	NEXT
655	NEXT
	RETURN
	' Display message M$ below the board (or T$ on row Y), centered
700	Y = R0 + 22 : T$ = M$
705	LOCATE Y, MC : PRINT LEFT$(SPACE$((39 - LEN(T$)) \ 2) + T$ + SPACE$(39), 39);
	RETURN
990	END 80 ' BERR_USAGE
