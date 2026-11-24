/* Solver for SUCKS
 *
 * Created 21-May-1993, Jeffpar
 */


#include <stdio.h>
#include <stdlib.h>


#define TRUE            1
#define FALSE           0

#define PLAYER_NONE     -1
#define PLAYER_ONE      0
#define PLAYER_TWO      1
#define PLAYER_THREE    2
#define PLAYER_FOUR     3

#ifdef CLASSIC
#define MAX_PLAYERS     2
#define NEXT_PLAYER(p)  (PLAYER_TWO-(p))
#else
#define MAX_PLAYERS     4
#define NEXT_PLAYER(p)  ((p)==MAX_PLAYERS-1?PLAYER_ONE:(p)+1)
#endif

#ifdef CLASSIC
char achPlayer[] = {'.', 'X', 'O'};
#else
char achPlayer[] = {'.', 'D', 'K', 'M', 'J'};
#endif


#ifdef CLASSIC
#define BOARD_WIDTH     7
#define BOARD_HEIGHT    7
#else
#define BOARD_WIDTH     9
#define BOARD_HEIGHT    9
#endif
#define MIN_GAIN       -(BOARD_WIDTH*BOARD_HEIGHT)
#define MAX_GAIN        (BOARD_WIDTH*BOARD_HEIGHT)

#define XMIN            0
#define YMIN            0
#define XMAX            (BOARD_WIDTH-1)
#define YMAX            (BOARD_HEIGHT-1)

#define VALIDPOSITION(x,y)  ((x)>=XMIN && (x)<=XMAX && (y)>=YMIN && (y)<=YMAX)

#define EMPTYPOSITION(pb,x,y) ((pb)->aPieces[x][y] == PLAYER_NONE)


typedef struct _BOARD {
    char  aPlayer[MAX_PLAYERS];
    char  aPieces[BOARD_WIDTH][BOARD_HEIGHT];
} BOARD;
typedef BOARD *PBOARD;


#define MOVETYPE_NONE   -1
#define MOVETYPE_OOZE   0
#define MOVETYPE_JUMP   1

typedef struct _MOVE {
    int xFrom;
    int yFrom;
    int xTo;
    int yTo;
    int iType;
} MOVE;
typedef MOVE *PMOVE;

#define MAX_OOZE_MOVES  8

int adxdyOoze[MAX_OOZE_MOVES][2] = {
    {-1, -1},
    { 0, -1},
    { 1, -1},
    { 1,  0},
    { 1,  1},
    { 0,  1},
    {-1,  1},
    {-1,  0},
};

#define MAX_JUMP_MOVES  16

int adxdyJump[MAX_JUMP_MOVES][2] = {
    {-2, -2},
    {-1, -2},
    { 0, -2},
    { 1, -2},
    { 2, -2},
    { 2, -1},
    { 2,  0},
    { 2,  1},
    { 2,  2},
    { 1,  2},
    { 0,  2},
    {-1,  2},
    {-2,  2},
    {-2,  1},
    {-2,  0},
    {-2, -1},
};


void InitBoard(register PBOARD pb)
{
    int x, y;

    for (x=XMIN; x<=XMAX; x++)
        for (y=YMIN; y<=YMAX; y++)
            pb->aPieces[x][y] = PLAYER_NONE;

#ifdef CLASSIC
    pb->aPieces[XMIN][YMIN] = PLAYER_ONE;
    pb->aPieces[XMAX][YMIN] = PLAYER_TWO;
    pb->aPieces[XMAX][YMAX] = PLAYER_ONE;
    pb->aPieces[XMIN][YMAX] = PLAYER_TWO;

    pb->aPlayer[PLAYER_ONE] = 2;
    pb->aPlayer[PLAYER_TWO] = 2;
#else
    pb->aPieces[XMIN][YMIN] = PLAYER_ONE;
    pb->aPieces[XMAX][YMIN] = PLAYER_TWO;
    pb->aPieces[XMAX][YMAX] = PLAYER_THREE;
    pb->aPieces[XMIN][YMAX] = PLAYER_FOUR;

    pb->aPlayer[PLAYER_ONE]   = 1;
    pb->aPlayer[PLAYER_TWO]   = 1;
    pb->aPlayer[PLAYER_THREE] = 1;
    pb->aPlayer[PLAYER_FOUR]  = 1;
#endif
}


void PrintBoard(register PBOARD pb)
{
    int i, x, y;

//  7  X . . . . . . O
//  6  . . . . . . . .
//  5  . . . . . . . .
//  4  . . . . . . . .
//  3  . . . . . . . .
//  2  . . . . . . . .
//  1  . . . . . . . .
//  0  O . . . . . . X
//
//     0 1 2 3 4 5 6 7

    printf("\n");

    for (y=YMAX; y>=YMIN; y--) {

        printf("    %d  ", y);

        for (x=XMIN; x<=XMAX; x++) {
            printf("%c ", achPlayer[pb->aPieces[x][y]+1]);
        }

        printf("\n");
    }
    printf("\n       ");

    for (x=XMIN; x<=XMAX; x++)
        printf("%d ", x);

    printf("\n\n");
    for (i=0; i<MAX_PLAYERS; i++)
        printf("Player %c has %d  ", achPlayer[i+1], pb->aPlayer[i]);
    printf("\n\n");
}


void PrintMove(PBOARD pb, int iPlayer, register PMOVE pm)
{
    if (pm->iType == MOVETYPE_NONE) {
        printf("\nPlayer %c has no move\n", achPlayer[iPlayer+1]);
        return;
    }
    printf("\nPlayer %c %s from %d,%d to %d,%d\n",
            achPlayer[iPlayer+1],
            pm->iType == MOVETYPE_OOZE? "oozing" : "jumping",
            pm->xFrom, pm->yFrom, pm->xTo, pm->yTo);
}


int JumpMove(PBOARD pb, register PMOVE pm, int iMove)
{
    pm->xTo = pm->xFrom + adxdyJump[iMove][0];
    pm->yTo = pm->yFrom + adxdyJump[iMove][1];

    if (VALIDPOSITION(pm->xTo, pm->yTo)) {

        if (EMPTYPOSITION(pb, pm->xTo, pm->yTo)) {

            // In an effort to avoid costly recursion, we will
            // not consider jumps that jump to locations that are
            // not near any opposing pieces.  Hence the following call...

            if (!EvalMove(pb, pb->aPieces[pm->xFrom][pm->yFrom], pm))
                return FALSE;

            pm->iType = MOVETYPE_JUMP;
            return TRUE;
        }
    }
    return FALSE;
}


int OozeMove(PBOARD pb, register PMOVE pm, int iMove)
{
    pm->xTo = pm->xFrom + adxdyOoze[iMove][0];
    pm->yTo = pm->yFrom + adxdyOoze[iMove][1];

    if (VALIDPOSITION(pm->xTo, pm->yTo)) {

        if (EMPTYPOSITION(pb, pm->xTo, pm->yTo)) {
            pm->iType = MOVETYPE_OOZE;
            return TRUE;
        }
    }
    return FALSE;
}


int EvalMove(PBOARD pb, int iPlayer, PMOVE pm)
{
    int iMove, cOoze = 0;
    int xTo, yTo;
    int xFrom = pm->xTo, yFrom = pm->yTo;

    for (iMove=0; iMove<MAX_OOZE_MOVES; iMove++) {
        xTo = xFrom + adxdyOoze[iMove][0];
        yTo = yFrom + adxdyOoze[iMove][1];

        if (VALIDPOSITION(xTo, yTo)) {
            if (pb->aPieces[xTo][yTo] != iPlayer &&
                pb->aPieces[xTo][yTo] != PLAYER_NONE) {

                cOoze++;
            }
        }
    }
    return cOoze;
}


void ExecMove(PBOARD pb, int iPlayer, PMOVE pm)
{
    int iOther, iMove;
    int xTo, yTo;
    int xFrom = pm->xTo, yFrom = pm->yTo;

    // WARNING: The move must already be validated!

    if (pm->iType == MOVETYPE_NONE)
        return;

    if (pm->iType == MOVETYPE_OOZE)
        pb->aPlayer[iPlayer] += 1;
    else // if (pm->iType == MOVETYPE_JUMP)
        pb->aPieces[pm->xFrom][pm->yFrom] = PLAYER_NONE;

    pb->aPieces[pm->xTo][pm->yTo] = (char)iPlayer;

    for (iMove=0; iMove<MAX_OOZE_MOVES; iMove++) {
        xTo = xFrom + adxdyOoze[iMove][0];
        yTo = yFrom + adxdyOoze[iMove][1];

        if (VALIDPOSITION(xTo, yTo)) {
            iOther = pb->aPieces[xTo][yTo];
            if (iOther != iPlayer && iOther != PLAYER_NONE) {
                pb->aPlayer[iOther] -= 1;
                pb->aPieces[xTo][yTo] = (char)iPlayer;
                pb->aPlayer[iPlayer] += 1;
            }
        }
    }
}


int BestMove(PBOARD pb, int iPlayer, PMOVE pm, int iDepth, int maxGain)
{
    BOARD bTmp;
    int x, y, iMove;
    int thisGain, bestGain;
    MOVE thisMove, bestMove;
    char aOozed[BOARD_WIDTH][BOARD_HEIGHT];

    // Start off with worst possible gain (should be easy to beat,
    // unless this player has no possible moves)

    bestGain = MIN_GAIN;
    bestMove.iType = MOVETYPE_NONE;

    for (x=XMIN; x<=XMAX; x++)
        for (y=YMIN; y<=YMAX; y++)
            aOozed[x][y] = FALSE;

    for (thisMove.xFrom=XMIN; thisMove.xFrom<=XMAX; thisMove.xFrom++) {

        for (thisMove.yFrom=YMIN; thisMove.yFrom<=YMAX; thisMove.yFrom++) {

            // A valid move must, of course, start from a position
            // that the specified player occupies

            if (pb->aPieces[thisMove.xFrom][thisMove.yFrom] != iPlayer)
                continue;

            // look at the "ooze" possibilities first

            for (iMove=0; iMove<MAX_OOZE_MOVES; iMove++) {

                // When oozing into a cell, it doesn't matter
                // where we're oozing from, so we only need to look
                // at the thing once; aOozed keeps track of that for us

                if (OozeMove(pb, &thisMove, iMove) &&
                    !aOozed[thisMove.xTo][thisMove.yTo]++) {

                    // This OozeMove was successful, so automatically
                    // have a gain of 1.  Evaluate the cells surrounding
                    // (thisMove.xTo, thisMove.yTo);  for each cell that
                    // contains an opposing piece, add a net gain of 2.

                    thisGain = 1 + EvalMove(pb, iPlayer, &thisMove) * 2;

                    // Before we start the (potentially lengthy) recursion
                    // process, bail out if we've already found a gain that
                    // is "large enough"...

#ifdef DISABLE
                    if (thisGain > maxGain) {
                        if (pm)
                            *pm = thisMove;
                        return thisGain;
                    }
#endif
                    if (iDepth > 1) {

                        // Before we call BestMove again, we must provide
                        // it with a copy of the board, with the move we're
                        // looking at already executed.

                        bTmp = *pb;
                        ExecMove(&bTmp, iPlayer, &thisMove);

                        thisGain -= BestMove(&bTmp,
                                             NEXT_PLAYER(iPlayer),
                                             NULL,
                                             iDepth-1, thisGain);
                    }

                    if (thisGain > bestGain) {
                        bestGain = thisGain;
                        bestMove = thisMove;
                    }
                }
            }

            // next, look at the "jump" possibilities

            for (iMove=0; iMove<MAX_JUMP_MOVES; iMove++) {

                if (JumpMove(pb, &thisMove, iMove)) {

                    // This JumpMove was successful, but there is no
                    // automatic gain.  Evaluate the cells surrounding
                    // (thisMove.xTo, thisMove.yTo);  for each cell that
                    // contains an opposing piece, add a net gain of 2.

                    thisGain = EvalMove(pb, iPlayer, &thisMove) * 2;

                    // Before we start the (potentially lengthy) recursion
                    // process, bail out if we've already found a gain that
                    // is "large enough"...

#ifdef DISABLE
                    if (thisGain > maxGain) {
                        if (pm)
                            *pm = thisMove;
                        return thisGain;
                    }
#endif
                    if (iDepth > 1) {

                        // Before we call BestMove again, we must provide
                        // it with a copy of the board, with the move we're
                        // looking at already executed.

                        bTmp = *pb;
                        ExecMove(&bTmp, iPlayer, &thisMove);

                        thisGain -= BestMove(&bTmp,
                                             NEXT_PLAYER(iPlayer),
                                             NULL,
                                             iDepth-1, thisGain);
                    }

                    if (thisGain > bestGain) {
                        bestGain = thisGain;
                        bestMove = thisMove;
                    }
                }
            }
        }
    }
    if (pm)
        *pm = bestMove;

    return bestGain;
}


void ReadMove(PBOARD pb, int iPlayer, PMOVE pm)
{
    BOARD bTmp;
    MOVE moveTmp;
    int i, iDepth, iGain;

    do {
        printf("Enter move for player %c (x,y x,y): ",
                achPlayer[iPlayer+1]);

        pm->yFrom = 0;
        scanf("%d,%d %d,%d", &pm->xFrom, &pm->yFrom, &pm->xTo, &pm->yTo);

        if (pm->xFrom < 0) {
            i = pm->yFrom;
            iDepth = -(pm->xFrom);
            printf("\nComputing best move...\n");
            iGain = BestMove(pb, iPlayer, pm, iDepth, MAX_GAIN);

            if (i < 0) {
                bTmp = *pb;
                moveTmp = *pm;
                while (iDepth--) {
                    PrintMove(&bTmp, iPlayer, &moveTmp);
                    printf("Gain == %d, depth == %d\n", iGain, iDepth+1);
                    ExecMove(&bTmp, iPlayer, &moveTmp);
                    PrintBoard(&bTmp);
                    getch();
                    if (!iDepth)
                        break;
                    iPlayer = NEXT_PLAYER(iPlayer);
                    iGain = BestMove(&bTmp, iPlayer, &moveTmp, iDepth, MAX_GAIN);
                }
            }
            break;
        }

        if (VALIDPOSITION(pm->xFrom, pm->yFrom) &&
            VALIDPOSITION(pm->xTo, pm->yTo)) {
            if (pb->aPieces[pm->xFrom][pm->yFrom] != iPlayer) {
                printf("Player %c does not have a piece at %d,%d\n\n",
                        achPlayer[iPlayer+1], pm->xFrom, pm->yFrom);
            } else {
                i = max(abs(pm->xTo - pm->xFrom), abs(pm->yTo - pm->yFrom));
                if (i == 0)
                    printf("Cannot move to the same position\n");
                else if (i > 2)
                    printf("Cannot move that far\n");
                else if (!EMPTYPOSITION(pb, pm->xTo, pm->yTo))
                    printf("The position at %d,%d is not empty\n\n",
                            pm->xTo, pm->yTo);
                else {
                    pm->iType = MOVETYPE_OOZE;
                    if (i > 1)
                        pm->iType = MOVETYPE_JUMP;
                    break;
                }
            }
        }
        else
            printf("Invalid coordinates, redo from start\n\n");
    } while (TRUE);
}


main()
{
    MOVE move;
    BOARD board;
#ifdef CLASSIC
    int iPlayer = PLAYER_TWO;
#else
    int iPlayer = PLAYER_ONE;
#endif

    InitBoard(&board);
    do {
        PrintBoard(&board);
        ReadMove(&board, iPlayer, &move);
        PrintMove(&board, iPlayer, &move);
        ExecMove(&board, iPlayer, &move);
        iPlayer = NEXT_PLAYER(iPlayer);
    } while (TRUE);
}
