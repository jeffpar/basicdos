	' BROGUE.BAS: a dungeon crawl in the spirit of Rogue
	'
	' Each level is a map of 2 to 4 rooms, joined in a path by hallways.
	' You (u) start on the stairs up (<) in the first room, and the stairs
	' down (>) are in the last.  The rooms are full of stones (O): walking
	' into one pushes it, and it rolls until something stops it.  Bricks
	' never move.  Move with the cursor keys (Home, PgUp, End, and PgDn
	' for the diagonals) or h, j, k, l, y, u, b, and n; R restarts the
	' level, N makes a new map, and Q quits.
	'
	' Every map is made from a 32-bit seed (SEED, on the top row) given to
	' RANDOMIZE, so R makes the same map again; only N and the stairs
	' choose a new seed.  Play uses no random numbers.  To play a map
	' again later, run BROGUE with its seed (and its level, if it isn't 1;
	' eg, BROGUE 36AF971E 4).
	'
	' The map (M$) is on rows 2-23, between the message row and the status
	' row, so it fits a VT100 as well as a video display.  A cell is every
	' other column (1, 3, ..., 79), so it's about as wide as it is tall;
	' every X here is a column, and a move across is 2 columns.  Walls (H$,
	' V$, and the corners) and bricks (P$) are the PC's line-drawing
	' characters, which a VT100 console displays with its own.  A door is
	' an opening in a wall with a corner on either side, turned outward, 2
	' or more cells from the room's corners, and a hallway is a path of
	' blank cells between two doors, with a wall on either side.
	'
	' BROGUE /M plays with every other BROGUE /M running in another
	' session: each one displays the others' players (on its own map) as
	' their session numbers (1-9, then A-W).  The first one makes the map,
	' and the others play it, starting anywhere in its first room; the
	' stairs choose the next seed from the current one, so the players who
	' take them meet again.  A BROGUE that arrives at a map that another
	' one is playing (by starting, by the stairs, or with R) gets that
	' one's stones, and a stone that a player pushes rolls on every map,
	' squashing any other player in its way.
	'
	' Rooms are placed in a grid of 2x2: map rows 1-9 and 14-22, and
	' columns 3-37 and 45-79, so there are always 4 or more cells between
	' rooms in a row.  The rooms are numbered in a path through the grid
	' (along the top row, then back along the bottom row), so linking
	' each room to the next never crosses another room; the hallway from
	' the top row to the bottom row turns in a free row between them (G).
	'
	DEFINT A-Z
	DIM M$(23), X1(4), Y1(4), X2(4), Y2(4), RC(4)
	DIM EX(4), EY(4), LX(4), LY(4), OX(32), OY(32)
	DEF FNR(N) = RND% MOD N
	H$ = CHR$(196) : V$ = CHR$(179) : P$ = CHR$(177)
	B$ = SPACE$(81) : C$ = CHR$(19) + CHR$(24) + CHR$(5) + CHR$(4)
	F$ = "" : FOR I = 1 TO 40 : F$ = F$ + ". " : NEXT
	' The corners on either side of a door, for each wall (W is 1-4 for
	' the left, bottom, top, and right walls, like the moves)
	Q$ = CHR$(217) + CHR$(191) + CHR$(191) + CHR$(218)
	Q$ = Q$ + CHR$(217) + CHR$(192) + CHR$(192) + CHR$(218)
	' A seed (in hex) and a level on the command line choose the map (I
	' counts them), and the switch char (W$) followed by M plays with
	' other BROGUEs (MP)
	DOS &H3700 : W$ = CHR$(DOS(3) AND 255)
	L = 1 : I = 0 : J = 1 : A$ = ARG$(1)
	WHILE A$ <> ""
	IF UCASE$(A$) = W$ + "M" THEN MP = 1 : GOTO 1
	IF LEFT$(A$, 1) = W$ OR I = 2 THEN GOTO 990
	I = I + 1 : IF I = 1 THEN SEED = VAL("&H" + A$) ELSE L = VAL(A$)
1	J = J + 1 : A$ = ARG$(J)
	WEND
	IF L < 1 THEN L = 1
	' In multiplayer, open the pipe that every BROGUE /M shares (#2), get
	' our session number (SN), and ask who's there (see 680); a reply
	' within 2 seconds gives the map to play (see 610)
	IF MP = 0 THEN GOTO 3
	N$ = "123456789ABCDEFGHIJKLMNOPQRSTUVW"
	DOS &H9100 : SN = (DOS(2) AND 255) + 1
	OPEN "PIPE$:BROGUE" AS #2 : GOSUB 680 : T = TIMER
2	IF LOC(2) THEN GOSUB 610
	IF ABS(TIMER - T) < 2 THEN GOTO 2
3	IF I OR JN THEN GOTO 10 ELSE GOTO 5
	' In multiplayer, the stairs choose the next seed from this one
4	IF MP THEN RANDOMIZE SEED : GOTO 6
	' Choose a new seed: RANDOMIZE uses the BIOS tick count, and NOT
	' gives the seed's top bit (which RND% never sets) a chance as well
5	RANDOMIZE
6	SEED = RND% : IF FNR(2) THEN SEED = NOT SEED
	' Choose NR of the 4 places in the grid (RC); NT counts the rooms in
	' the top row
10	RANDOMIZE SEED : E = 0 : CLS
	FOR Y = 0 TO 23 : M$(Y) = B$ : NEXT
	NR = 2 + FNR(2) + L \ 2 : IF NR > 4 THEN NR = 4
	N = 0 : NT = 0 : D = FNR(2) : G = 11 + FNR(2)
	FOR K = 0 TO 3
	IF FNR(4 - K) >= NR - N THEN GOTO 15
	N = N + 1 : RC(N) = K : IF K < 2 THEN NT = N
15	NEXT
	' Room R is in row K and column C, and the path enters by wall WA and
	' leaves by wall WB; the stairs take the place of a door in the first
	' and last rooms, on any other wall
	FOR R = 1 TO N
	K = RC(R) : C = K MOD 2 : K = K \ 2 : IF K <> D THEN C = 1 - C
	WB = 4 - 3 * D : IF K THEN WB = 5 - WB
	WA = 5 - WB : IF R = NT + 1 AND NT > 0 THEN WA = 3
	IF R = NT AND N > NT THEN WB = 2
	IF R = 1 THEN WA = 0
	IF R = N THEN WB = 0
	IF WA > 0 AND WB > 0 THEN GOTO 25
20	U = 1 + FNR(4) : IF U = WA + WB THEN GOTO 20
	IF WA THEN WB = U ELSE WA = U
	' Make the room 8-18 cells by 5-9 (walls included), with its doors,
	' bricks (in rows or columns of 1-3), and stones (a try for every 3
	' cells of floor), each where it touches only floor (see 450), so
	' there's always a way around them
25	RW = 8 + FNR(11) : RH = 5 + FNR(5) : A = (RW - 2) * (RH - 2)
	X = 3 + 42 * C + 2 * FNR(19 - RW) : Y = 1 + 13 * K + FNR(10 - RH)
	X1(R) = X : Y1(R) = Y : X2(R) = X + 2 * RW - 2 : Y2(R) = Y + RH - 1
	T$ = STRING$(2 * RW - 3, H$)
	MID$(M$(Y), X) = CHR$(218) + T$ + CHR$(191)
	MID$(M$(Y2(R)), X) = CHR$(192) + T$ + CHR$(217)
	T$ = V$ + " " + LEFT$(F$, 2 * RW - 4) + V$
	FOR J = Y + 1 TO Y2(R) - 1 : MID$(M$(J), X) = T$ : NEXT
	W = WA : GOSUB 420 : W = WB : GOSUB 420
	FOR J = 0 TO FNR(2 + A \ 20)
	U = FNR(2) : V = 1 - U : Q = FNR(3)
	IF V AND Q > RH - 5 THEN Q = RH - 5
	GOSUB 450 : IF F THEN GOTO 27
	IF U THEN MID$(M$(Y), X) = STRING$(2 * Q + 1, P$) : GOTO 27
	FOR I = 0 TO Q : MID$(M$(Y + I), X, 1) = P$ : NEXT
27	NEXT
	Q = 0
	FOR J = 1 TO A \ 3
	GOSUB 450 : IF F = 0 THEN MID$(M$(Y), X, 1) = "O"
	NEXT J, R
	' Link each room's exit to the next room's entrance, and display the
	' map
	FOR R = 1 TO N - 1
	X = LX(R) : Y = LY(R) : U = EX(R + 1) : V = EY(R + 1)
	IF R = NT THEN GOSUB 200 ELSE GOSUB 100
	NEXT
	FOR Y = 1 TO 22
	IF M$(Y) <> B$ THEN LOCATE Y + 1, 1 : PRINT LEFT$(M$(Y), 80);
	NEXT
	M1$ = "Welcome tae this wee dungeon!"
	PX = EX(1) : PY = EY(1) : GOSUB 500
	' In multiplayer, every BROGUE asks who's there; one that's arrived
	' by the stairs (or R) looks for a player who's already on this map
	' (see 630), and one that's joining another (JN) gets the objects of
	' that one's map (see 620), and if it's just starting (JR), it starts
	' in the first room (see 640)
	IF MP THEN GOSUB 680
	IF ZA THEN GOSUB 630
	IF JN THEN GOSUB 620 : JN = 0
	IF JR THEN GOSUB 640
	' Each move (D is 1-8 for left, down, up, right, and then up-left,
	' up-right, down-left, and down-right) must be to a floor, blank, or
	' stairs cell, or else push a stone; the cursor stays on the player.
	' A cursor key is a null and a scan code, or one of the codes in C$.
	' The only way off the stairs up is into the room.  In multiplayer,
	' the other players are displayed, too, a message from another BROGUE
	' (an empty K$; see 600) displays them again, and R gets the stones
	' from any other BROGUE on the map (ZA; see 630).
50	IF E THEN GOTO 86
	IF MP THEN GOSUB 660
	LOCATE PY + 1, PX : PRINT "u"; : LOCATE PY + 1, PX
	IF MP THEN GOSUB 600 : IF K$ = "" THEN GOTO 50
	IF MP = 0 THEN K$ = INPUT$(1)
	IF K$ = CHR$(0) THEN K$ = K$ + INPUT$(1)
	D = INSTR("hjklyubn", K$) + INSTR(C$, K$)
	IF ASC(K$) = 0 THEN D = INSTR("KPHMGIOQ", RIGHT$(K$, 1))
	IF D THEN GOTO 55
	K$ = UCASE$(K$)
	IF K$ = "N" THEN GOTO 5
	IF K$ = "R" THEN ZA = MP : GOTO 10
	IF K$ = "Q" THEN GOTO 95
	GOTO 50
55	DX = 2 * (ASC(MID$("01120202", D, 1)) - 49)
	DY = ASC(MID$("12010022", D, 1)) - 49
	X = PX + DX : Y = PY + DY : T$ = MID$(M$(Y), X, 1)
	IF T$ = "O" THEN GOTO 60
	IF T$ = " " AND MID$(M$(PY), PX, 1) = "<" THEN GOTO 50
	IF INSTR("<>. ", T$) = 0 THEN GOTO 50
	PRINT MID$(M$(PY), PX, 1); : PX = X : PY = Y
	IF MP THEN GOSUB 685
	IF T$ = ">" THEN L = L + 1 : ZA = MP : GOTO 4
	GOTO 50
	' Push the stone at (X,Y), unless the cell after it isn't floor; in
	' multiplayer, the other BROGUEs push it, too (see 610)
60	IF MID$(M$(Y + DY), X + DX, 1) <> "." THEN GOTO 50
	IF MP THEN ZD = D : GOSUB 685
	GOSUB 65 : GOTO 50
	' Roll the stone at (X,Y) in the push's direction (DX,DY) a cell at a
	' time, for as long as the next cell is floor; SOUND waits for the
	' last one to end (a clock tick).  A stone that another player pushed
	' squashes our player (E is set) if it rolls into it.
65	MID$(M$(Y), X, 1) = "." : LOCATE Y + 1, X : PRINT ".";
	X = X + DX : Y = Y + DY : IF X = PX AND Y = PY THEN E = 1
	MID$(M$(Y), X, 1) = "O" : LOCATE Y + 1, X : PRINT "O";
	SOUND 32767, 1
	IF MID$(M$(Y + DY), X + DX, 1) = "." THEN GOTO 65
	RETURN
	' Squashed (only in multiplayer, by a stone that another player
	' pushed)
86	M1$ = "SQUASHED!  R retries, N makes a new map, Q quits"
	GOSUB 500 : SOUND 100, 9
87	GOSUB 660 : GOSUB 600 : IF K$ = "" THEN GOTO 87
	K$ = UCASE$(K$)
	IF K$ = "R" THEN ZA = MP : GOTO 10
	IF K$ = "N" THEN GOTO 5
	IF K$ = "Q" THEN GOTO 95
	GOTO 87
	' Quit (in multiplayer, the other BROGUEs remove our player)
95	CLS : IF MP THEN PX = 0 : GOSUB 685
	END
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
110	I = X + 4 + 2 * FNR((U - X) \ 2 - 3) : K$ = CHR$(204 - 13 * S)
	MID$(M$(Y - S), X + 1) = STRING$(I - X + 1, H$) + K$
	MID$(M$(Y + S), X + 1) = STRING$(I - X - 3, H$) + K$
	K$ = CHR$(205 - 13 * S)
	MID$(M$(V - S), I + 2) = K$ + STRING$(U - I - 3, H$)
	MID$(M$(V + S), I - 2) = K$ + STRING$(U - I + 1, H$)
	FOR J = Y TO V - 2 * S STEP S : MID$(M$(J), I + 2, 1) = V$ : NEXT
	FOR J = Y + 2 * S TO V STEP S : MID$(M$(J), I - 2, 1) = V$ : NEXT
	RETURN
	' Link door (X,Y), in a bottom wall, and door (U,V), in a top wall,
	' with a hallway that goes down to row G, left or right (S), and down
	' again, unless they're in the same column
200	S = SGN(U - X)
	IF S THEN GOTO 210
	T$ = V$ + "   " + V$
	FOR J = Y + 1 TO V - 1 : MID$(M$(J), X - 2, 5) = T$ : NEXT
	RETURN
210	FOR J = Y + 1 TO G : MID$(M$(J), X - 2 * S, 1) = V$ : NEXT
	FOR J = Y + 1 TO G - 2 : MID$(M$(J), X + 2 * S, 1) = V$ : NEXT
	FOR J = G + 2 TO V - 1 : MID$(M$(J), U - 2 * S, 1) = V$ : NEXT
	FOR J = G TO V - 1 : MID$(M$(J), U + 2 * S, 1) = V$ : NEXT
	T$ = STRING$(ABS(U - X) - 1, H$)
	IF S = 1 THEN T$ = CHR$(192) + T$ + CHR$(191)
	IF S < 0 THEN T$ = CHR$(218) + T$ + CHR$(217)
	IF X > U THEN X = U
	MID$(M$(G + 1), X - 2 * S) = T$ : MID$(M$(G - 1), X + 2 * S) = T$
	RETURN
	' Make a door in wall W of room R, 2 or more cells from its corners,
	' with a corner on either side (see Q$, and blank columns between them
	' in a top or bottom wall); it's the room's entrance
	' (EX,EY) if W is WA, or else its exit (LX,LY).  The first room's
	' entrance and the last room's exit are stairs instead, which have no
	' corners.
420	X = X1(R) : IF W = 4 THEN X = X2(R)
	Y = Y1(R) : IF W = 2 THEN Y = Y2(R)
	IF W = 2 OR W = 3 THEN X = X + 4 + 2 * FNR(RW - 4) : GOTO 425
	Y = Y + 2 + FNR(RH - 4)
425	MID$(M$(Y), X, 1) = " "
	IF W = WA THEN EX(R) = X : EY(R) = Y ELSE LX(R) = X : LY(R) = Y
	IF R = 1 AND W = WA THEN MID$(M$(Y), X, 1) = "<" : RETURN
	IF R = N AND W <> WA THEN MID$(M$(Y), X, 1) = ">" : RETURN
	K$ = MID$(Q$, 2 * W - 1, 1) : T$ = MID$(Q$, 2 * W, 1)
	IF W = 2 OR W = 3 THEN MID$(M$(Y), X - 2) = K$ + "   " + T$ : RETURN
	MID$(M$(Y - 1), X, 1) = K$ : MID$(M$(Y + 1), X, 1) = T$
	RETURN
	' Choose a cell (X,Y) in room R for Q + 1 cells across (U is 1) or
	' down (V is 1), with a cell of floor between them and the walls, and
	' set F unless all of them, and every cell next to them, are floor
450	X = X1(R) + 4 + 2 * FNR(RW - 4 - Q * U)
	Y = Y1(R) + 2 + FNR(RH - 4 - Q * V)
	F = 0 : T$ = LEFT$(F$, 5 + 2 * Q * U)
	FOR I = Y - 1 TO Y + 1 + Q * V
	IF MID$(M$(I), X - 2, LEN(T$)) <> T$ THEN F = 1
	NEXT
	RETURN
	' Display the level and message (M1$) on the top row, with the
	' seed at the right, and the keys on the bottom row
500	T$ = "Level" + STR$(L) + ": " + M1$ + B$
	LOCATE 1, 1 : PRINT LEFT$(T$, 66) + "Seed " + RIGHT$("0000000" + HEX$(SEED), 8);
	T$ = "Move: hjklyubn (or the cursor keys)  Retry: R  New: N  Quit: Q"
	LOCATE 24, 1 : PRINT T$;
	RETURN
	' In multiplayer, wait for a key (K$), or a message from another
	' BROGUE (K$ is empty), which is 9 bytes: its session number (S), plus
	' 64 times its type (ZT); its seed (ZS) and level (ZM is set if
	' they're ours); and two values (X and Y) and a count (D), which
	' depend on the type:
	'
	'   0: its player's column and row, or 0 if it isn't playing a map,
	'      and the direction of the stone it just pushed (or 0)
	'   1: the same, and it's asking who's there (we send our position)
	'   2: it's asking session X for its map's objects, from object Y on
	'      (see 700)
	'   3: objects (stones) of its map for session X, in D more bytes
	'      (see 720), and Y is the next object, or 0 if there are no more
	'
	' A player on our map is displayed there (OX and OY; see 660), and
	' pushes our stone, too, if it's there.  If we're starting (PX is 0),
	' the first player to reply gives us its map (JN is its session
	' number, and JR is set); if we're arriving by the stairs or R (ZA),
	' the first player on our map gives us its objects (see 620).
600	K$ = INKEY$ : IF K$ <> "" THEN RETURN
	IF LOC(2) = 0 THEN GOTO 600
610	Z$ = INPUT$(9, #2) : S = ASC(Z$) AND 63 : ZT = ASC(Z$) \ 64
	ZS = CVL(MID$(Z$, 2, 4)) : X = ASC(MID$(Z$, 7, 1)) : Y = ASC(MID$(Z$, 8, 1))
	D = ASC(RIGHT$(Z$, 1)) : IF ZT = 1 THEN GOSUB 685
	IF ZT < 2 AND PX = 0 AND X > 0 AND JN = 0 THEN SEED = ZS : L = ASC(MID$(Z$, 6, 1)) : JN = S : JR = 1
	ZM = (ZS = SEED) AND (ASC(MID$(Z$, 6, 1)) = (L AND 255))
	IF ZT > 1 THEN GOTO 700
	IF ZM = 0 THEN X = 0
	IF ZA AND X > 0 AND JN = 0 THEN JN = S
	IF OX(S) THEN LOCATE OY(S) + 1, OX(S) : PRINT MID$(M$(OY(S)), OX(S), 1);
	OX(S) = X : OY(S) = Y
	IF X = 0 OR D = 0 OR PX = 0 THEN RETURN
	DX = 2 * (ASC(MID$("01120202", D, 1)) - 49)
	DY = ASC(MID$("12010022", D, 1)) - 49
	X = X + DX : Y = Y + DY : IF MID$(M$(Y), X, 1) <> "O" THEN RETURN
	IF MID$(M$(Y + DY), X + DX, 1) = "." THEN GOSUB 65
	RETURN
	' Get the objects of the map we're joining from that BROGUE (JN; see
	' 700), up to 40 at a time (ZK is the next one, and ZR is set when
	' they come), asking for each group up to 3 times, a second apart;
	' the first group replaces our objects (ZC is set to clear them)
620	ZK = 1 : ZC = 1
621	ZN = 0
622	ZN = ZN + 1 : IF ZN > 3 THEN RETURN
	PRINT #2, CHR$(SN + 128) + MKL$(SEED) + CHR$(L AND 255) + CHR$(JN) + CHR$(ZK) + CHR$(0);
	ZR = 0 : T = TIMER
623	IF LOC(2) THEN GOSUB 610
	IF ZR AND ZK THEN GOTO 621
	IF ZR THEN RETURN
	IF ABS(TIMER - T) < 1 THEN GOTO 623
	GOTO 622
	' Wait up to a second for a player on the map we've arrived at by the
	' stairs (JN; see 610)
630	T = TIMER
631	IF LOC(2) THEN GOSUB 610
	IF JN = 0 AND ABS(TIMER - T) < 1 THEN GOTO 631
	ZA = 0 : RETURN
	' Start a BROGUE that's joining another on a random floor cell in the
	' first room where no other player is, and tell the others
640	RANDOMIZE
641	X = X1(1) + 2 + 2 * FNR((X2(1) - X1(1)) \ 2 - 1)
	Y = Y1(1) + 1 + FNR(Y2(1) - Y1(1) - 1) : F = 0
	FOR I = 1 TO 32 : IF OX(I) = X AND OY(I) = Y THEN F = 1
	NEXT
	IF F OR MID$(M$(Y), X, 1) <> "." THEN GOTO 641
	PX = X : PY = Y : JR = 0 : GOSUB 685
	RETURN
	' Display the other players on our map, except where a stone is
660	FOR I = 1 TO 32 : X = OX(I) : Y = OY(I) : IF X = 0 THEN GOTO 665
	IF MID$(M$(Y), X, 1) <> "O" THEN LOCATE Y + 1, X : PRINT MID$(N$, I, 1);
665	NEXT
	RETURN
	' Ask the other BROGUEs who's there (they'll all reply), or send our
	' position (and the direction of a push, ZD; see 610) as one write,
	' so that each one gets all of it or none of it
680	FOR J = 1 TO 32 : OX(J) = 0 : NEXT : Z = 64
685	PRINT #2, CHR$(SN + Z) + MKL$(SEED) + CHR$(L AND 255) + CHR$(PX) + CHR$(PY) + CHR$(ZD);
	Z = 0 : ZD = 0
	RETURN
	' Send the objects of our map, from object ZQ on (see 750), to the
	' BROGUE that asked for them (S), if it asked us (X), up to 40 in one
	' message (D is the next one, or 0 if there are no more)
700	IF ZT = 3 THEN GOTO 720
	IF X <> SN OR ZM = 0 OR PX = 0 THEN RETURN
	ZQ = Y : IF ZQ = 1 THEN ZC = 0 : GOSUB 750
	T$ = MID$(TS$, 2 * ZQ - 1, 80) : D = ZQ + LEN(T$) \ 2
	IF 2 * D > LEN(TS$) THEN D = 0
	PRINT #2, CHR$(SN + 192) + MKL$(SEED) + CHR$(L AND 255) + CHR$(S) + CHR$(D) + CHR$(LEN(T$)) + T$;
	RETURN
	' Objects of the map we're joining, if they're the ones we asked for
	' (the next one, Y, is past ours, ZK): the first ones replace all of
	' ours
720	T$ = "" : IF D THEN T$ = INPUT$(D, #2)
	IF X <> SN OR S <> JN OR ZM = 0 OR (Y > 0 AND Y <= ZK) THEN RETURN
	ZK = Y : ZR = 1 : IF ZC THEN GOSUB 750
	FOR J = 1 TO LEN(T$) STEP 2
	X = ASC(MID$(T$, J, 1)) : Y = ASC(MID$(T$, J + 1, 1))
	MID$(M$(Y), X, 1) = "O" : LOCATE Y + 1, X : PRINT "O";
	NEXT
	RETURN
	' Clear the objects (stones) in our map's rooms if ZC is set, or else
	' list them in TS$, 2 bytes each (the column and the row)
750	TS$ = ""
	FOR R = 1 TO N : FOR Y = Y1(R) + 1 TO Y2(R) - 1
	FOR X = X1(R) + 2 TO X2(R) - 2 STEP 2
	IF MID$(M$(Y), X, 1) <> "O" THEN GOTO 755
	IF ZC THEN MID$(M$(Y), X, 1) = "." : LOCATE Y + 1, X : PRINT ".";
	IF ZC = 0 THEN TS$ = TS$ + CHR$(X) + CHR$(Y)
755	NEXT X, Y, R
	ZC = 0 : RETURN
990	END 80 ' BERR_USAGE
