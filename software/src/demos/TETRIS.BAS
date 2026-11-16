1 REM GW-BASIC TETRIS EXAMPLE - WRITTEN BY JOEL YLILUOMA - JULY 8 2010
2 REM FIRST PUBLISHED AT https://youtube.com/watch?v=JDnypVoQcPw
3 REM NEW IN 2020: If you want a QuickBasic/QBasic/QB64 compatible version,
4 REM              or a more readable version in general,
5 REM              check out https://iki.fi/bisqwit/jkp/qbtetris.bas
10 DEFINT A-Z
20 SCREEN 0: WIDTH 40,25: KEY OFF
30 ' Define all distinct tetromino shapes as bitmasks
31 DATA CC,8C4,6C,4444,F0,264,C6,E4,4C4,4E0,464,8E,C88,E2,226,2E,88C,E8,622
32 REM e.g. 8C4 = 1000, 2E = 0010
33 REM            1100       1110
34 REM            0100            and so on.
35 DIM SHAPES(18):  FOR A=0 TO 18: READ S$: SHAPES(A)=VAL("&H"+S$): NEXT
40 ' Define the mappings of block number -> block shape
41 DATA 0,0,0,0, 1,2,1,2, 3,4,3,4, 5,6,5,6, 7,8,9,10, 11,12,13,14, 15,16,17,18
45 DIM INDICES(28): FOR A=0 TO 27: READ INDICES(A): NEXT
50 ' This function reads the given slot from the given block in given rotation.
52 DIM BITMASKS(15): FOR A=0 TO 14: BITMASKS(A) = 2^A: NEXT'Note: a^15=overflow
55 DEF FNBLOCK(BL,ROT,X,Y) = SHAPES(INDICES(BL*4+ROT))AND BITMASKS(Y*4+X)
60 ' Bounds checking function
61 DEF FNBOUNDS(X,Y) = X>=0 AND Y>=0 AND X<12 AND Y<=24
70 ' Define the playing field.
80 DIM AREA(11,24)  ' Width and height, including borders.
81 DIM EMPTYLINE(23)
90 ' Initialize and draw the playing field.
92 DEF FNEMPTY$(X) = "."
95 C=23: FOR X=0 TO 11: FOR Y=0 TO 24: GOSUB 900: NEXT Y,X
96 C=0:  FOR X=1 TO 10: FOR Y=0 TO 23: GOSUB 900: NEXT Y,X
100 ' Main loop. Begin by generating a new piece.
101 CURBLOCK = INT(RND * 7)
102 CURROTATE = INT(RND * 4)
103 CURX = 4 : CURY = -2
104 COLORWHENMOVE = CURBLOCK+1
105 COLORWHENDONE = CURBLOCK+25
106 ' Test whether the new block immediately collides
107 GOSUB 800: IF COLLIDED THEN GOTO 999 ' Gameover if cannot spawn the block.
110 REM Flush input buffer: while inkey$<>"":wend
120 DROPPING=0
130 C=COLORWHENMOVE: GOSUB 700 ' Draw the current block
140 ' Wait for input before dropping the block a bit
150 TI! = TIMER + .5
160 WHILE TIMER < TI!
170   K$ = INKEY$
180   MX=CURX: MY=CURY: MR=CURROTATE
190   IF K$="w" THEN CURROTATE=(CURROTATE+1)AND 3: DROPPING=0: GOSUB 600
200   IF K$="a" THEN CURX=CURX-1: DROPPING=0: GOSUB 600
210   IF K$="d" THEN CURX=CURX+1: DROPPING=0: GOSUB 600
220   IF K$="q" THEN GOTO 999 ' Quitting is a game over. You lose!
230   IF K$="s" OR DROPPING=1 THEN 300 ' Try moving down
240   IF K$=" " THEN DROPPING=1
250 WEND ' done
300 ' Move down after timer elapsed
310 MX=CURX: MY=CURY: MR=CURROTATE
320 CURY=CURY+1: GOSUB 600     ' Try moving down
330 IF COLLIDED=0 THEN 150     ' Loop until collision
340 ' The block hit the ground.
350 C=COLORWHENDONE: GOSUB 700 ' Draw at final color
400 ' Make full lines empty
405 EMPTYCOUNT=0
410 FOR Y=1 TO 23
420   X=1: WHILE X<=10 AND AREA(X,Y)>0: X=X+1: WEND
421   EMPTY = X>10
422   EMPTYLINE(Y) = EMPTY: IF EMPTY THEN EMPTYCOUNT=EMPTYCOUNT+1
423 NEXT
424 IF EMPTYCOUNT=0 THEN 499
425 EMPTY$ = ".." + MID$("SINGLEDOUBLETRIPLETETRIS", EMPTYCOUNT*6-5,6) + ".."
426 DEF FNEMPTY$(X) = MID$(EMPTY$,X,1)
427 FOR Y=1 TO 23
428   EMPTY = EMPTYLINE(Y)
430   IF EMPTY THEN C=0: FOR X=1 TO 10: GOSUB 900: SOUND 40+RND*200,.1: NEXT
440 NEXT
445 DEF FNEMPTY$(X) = "."
450 ' Drop non-empty lines that are above empty lines
451 Y=23 ' Target of next non-empty line = bottom
460 FOR SOURCE=23 TO 1 STEP -1
462  SOUND 30+SOURCE*40,.5
465   X=1: WHILE X<=10 AND AREA(X,SOURCE)=0: X=X+1: WEND
470   EMPTY = X>10
480   IF Y<>SOURCE THEN FOR X=1 TO 10: C=AREA(X,SOURCE):GOSUB 900: NEXT
490   IF NOT EMPTY THEN Y=Y-1
495 NEXT
496 ' Clear the top in case it was not cleared yet
497 C=0
498 WHILE Y>1: FOR X=1 TO 10: GOSUB 900:NEXT: Y=Y-1: WEND
499 GOTO 100             ' Generate a new block
600 ' Subroutine for trying to move to a given direction
601 ' Params: curx,cury,curblock,currotate: Suggested new position
602 ' Params: mx,my,mr:                     Current position
603 ' Output: collided=1 -> No move (curx,.. reset to mx,...)
604 '         collided=0 -> Moved
605 '         In either case, mx,my,mr will be overwritten.
610 GOSUB 800 ' Test move
620 SWAP MX,CURX: SWAP MY,CURY: SWAP MR,CURROTATE
630 IF COLLIDED THEN RETURN 'No move
640 ' No obstacle for moving block
650 C=0: GOSUB 700              'Undraw at old location
660 SWAP MX,CURX: SWAP MY,CURY: SWAP MR,CURROTATE
670 C=COLORWHENMOVE: GOTO 700   'Draw at new location
700 ' Subroutine for plotting the current block.
701 ' Params: curx,cury, curblock,currotate, c
710 FOR BY=0 TO 3: FOR BX=0 TO 3
720   X=CURX+BX: Y=CURY+BY
730   IF FNBOUNDS(X,Y)AND FNBLOCK(CURBLOCK,CURROTATE,BX,BY)THEN GOSUB 900
740 NEXT BX,BY
750 RETURN
800 ' Subroutine for testing a block collision.
801 ' Params: curx,cury,curblock,currotate
802 ' Output: collided
810 FOR BY=0 TO 3: FOR BX=0 TO 3
820   IF FNBLOCK(CURBLOCK,CURROTATE,BX,BY)=0 THEN 860
830   X=CURX+BX: Y=CURY+BY
840   IF FNBOUNDS(X,Y)=0 THEN 860  ' this is a short-form for GOTO btw.
850   IF AREA(X,Y)AND 16 THEN COLLIDED=1: RETURN
860 NEXT BX,BY ' "btw" is short-form for "by the way, by the way
870 COLLIDED=0: RETURN
900 ' Subroutine for drawing a "pixel", i.e. one block slot.
901 ' Params: x,y, c
910 LOCATE Y+1,X+1: AREA(X,Y)=C
920 IF C THEN COLOR C AND 15: PRINT CHR$(219); : RETURN
930 COLOR 1: PRINT FNEMPTY$(X);
940 RETURN
999 WIDTH 80: COLOR 7,0: PRINT "GAME OVER": KEY ON: END ' simple.
