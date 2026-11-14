#include <stdio.h>
#include <string.h>

typedef struct _sheet {
    long    bits[2];
} SHEET;

typedef struct _board {
    SHEET   Xbits;
    SHEET   Obits;
    SHEET   Qbits;
} BOARD;

typedef struct _spot {
    int     set;
    long    bMask;
    SHEET   Oozes;
    SHEET   Jumps;
} SPOT;

#define BAD     0
#define JUMP    1
#define OOZE    2

#define PLAYER0 0
#define PLAYER1 1

#define TRUE    1
#define FALSE   0

SPOT iPos[7][7] = {
    0,  0x00000001,  0x00000182, 0x00000000, 0x0001C204, 0x00000000, /* 1  */
    0,  0x00000002,  0x00000385, 0x00000000, 0x0003C408, 0x00000000, /* 2  */
    0,  0x00000004,  0x0000070A, 0x00000000, 0x0007C891, 0x00000000, /* 3  */
    0,  0x00000008,  0x00000E14, 0x00000000, 0x000F9122, 0x00000000, /* 4  */
    0,  0x00000010,  0x00001C28, 0x00000000, 0x001F2244, 0x00000000, /* 5  */
    0,  0x00000020,  0x00003850, 0x00000000, 0x001E0408, 0x00000000, /* 6  */
    0,  0x00000040,  0x00003020, 0x00000000, 0x001C0810, 0x00000000, /* 7  */
    0,  0x00000080,  0x0000C103, 0x00000000, 0x00E10204, 0x00000000, /* 8  */
    0,  0x00000100,  0x0001C287, 0x00000000, 0x01E20408, 0x00000000, /* 9  */
    0,  0x00000200,  0x0003850E, 0x00000000, 0x03E44891, 0x00000000, /* 10 */
    0,  0x00000400,  0x00070A1C, 0x00000000, 0x07C89122, 0x00000000, /* 11 */
    0,  0x00000800,  0x000E1438, 0x00000000, 0x0F912244, 0x00000000, /* 12 */
    0,  0x00001000,  0x001C2870, 0x00000000, 0x0F020408, 0x00000000, /* 13 */
    0,  0x00002000,  0x00181060, 0x00000000, 0x0E040810, 0x00000000, /* 14 */
    0,  0x00004000,  0x00608180, 0x00000000, 0x70810207, 0x00000000, /* 15 */
    0,  0x00008000,  0x00E14380, 0x00000000, 0xF102040F, 0x00000000, /* 16 */
    0,  0x00010000,  0x01C28700, 0x00000000, 0xF224489F, 0x00000001, /* 17 */
    0,  0x00020000,  0x03850E00, 0x00000000, 0xE448913E, 0x00000003, /* 18 */
    0,  0x00040000,  0x070A1C00, 0x00000000, 0xC891227C, 0x00000007, /* 19 */
    0,  0x00080000,  0x0E143800, 0x00000000, 0x81020478, 0x00000007, /* 20 */
    0,  0x00100000,  0x0C083000, 0x00000000, 0x02040870, 0x00000007, /* 21 */
    0,  0x00200000,  0x3040C000, 0x00000000, 0x40810380, 0x00000038, /* 22 */
    0,  0x00400000,  0x70A1C000, 0x00000000, 0x81020780, 0x00000078, /* 23 */
    0,  0x00800000,  0xE1438000, 0x00000000, 0x12244F80, 0x000000F9, /* 24 */
    0,  0x01000000,  0xC2870000, 0x00000001, 0x24489F00, 0x000001F2, /* 25 */
    0,  0x02000000,  0x850E0000, 0x00000003, 0x48913E00, 0x000003E4, /* 26 */
    0,  0x04000000,  0x0A1C0000, 0x00000007, 0x81023C00, 0x000003C0, /* 27 */
    0,  0x08000000,  0x04180000, 0x00000006, 0x02043800, 0x00000381, /* 28 */
    0,  0x10000000,  0x20600000, 0x00000018, 0x4081C000, 0x00001C20, /* 29 */
    0,  0x20000000,  0x50E00000, 0x00000038, 0x8103C000, 0x00003C40, /* 30 */
    0,  0x40000000,  0xA1C00000, 0x00000070, 0x1227C000, 0x00007C89, /* 31 */
    0,  0x80000000,  0x43800000, 0x000000E1, 0x244F8000, 0x0000F912, /* 32 */
    1,  0x00000001,  0x87000000, 0x000001C2, 0x489F0000, 0x0001F224, /* 33 */
    1,  0x00000002,  0x0E000000, 0x00000385, 0x811E0000, 0x0001E040, /* 34 */
    1,  0x00000004,  0x0C000000, 0x00000302, 0x021C0000, 0x0001C081, /* 35 */
    1,  0x00000008,  0x30000000, 0x00000C10, 0x40E00000, 0x00001020, /* 36 */
    1,  0x00000010,  0x70000000, 0x00001C28, 0x81E00000, 0x00002040, /* 37 */
    1,  0x00000020,  0xE0000000, 0x00003850, 0x13E00000, 0x00004489, /* 38 */
    1,  0x00000040,  0xC0000000, 0x000070A1, 0x27C00000, 0x00008912, /* 39 */
    1,  0x00000080,  0x80000000, 0x0000E143, 0x4F800000, 0x00011224, /* 40 */
    1,  0x00000100,  0x00000000, 0x0001C287, 0x8F000000, 0x00002040, /* 41 */
    1,  0x00000200,  0x00000000, 0x00018106, 0x0E000000, 0x00004081, /* 42 */
    1,  0x00000400,  0x00000000, 0x00000818, 0x70000000, 0x00001020, /* 43 */
    1,  0x00000800,  0x00000000, 0x00001438, 0xF0000000, 0x00002040, /* 44 */
    1,  0x00001000,  0x00000000, 0x00002870, 0xF0000000, 0x00004489, /* 45 */
    1,  0x00002000,  0x00000000, 0x000050E0, 0xE0000000, 0x00008913, /* 46 */
    1,  0x00004000,  0x00000000, 0x0000A1C0, 0xC0000000, 0x00011227, /* 47 */
    1,  0x00008000,  0x00000000, 0x00014380, 0x80000000, 0x00002047, /* 48 */
    1,  0x00010000,  0x00000000, 0x00008300, 0x00000000, 0x00004087, /* 49 */
};

int Count[256] = {
    0, 1, 1, 2, 1, 2, 2, 3, 1, 2, 2, 3, 2, 3, 3, 4,
    1, 2, 2, 3, 2, 3, 3, 4, 2, 3, 3, 4, 3, 4, 4, 5,
    1, 2, 2, 3, 2, 3, 3, 4, 2, 3, 3, 4, 3, 4, 4, 5,
    2, 3, 3, 4, 3, 4, 4, 5, 3, 4, 4, 5, 4, 5, 5, 6,
    1, 2, 2, 3, 2, 3, 3, 4, 2, 3, 3, 4, 3, 4, 4, 5,
    2, 3, 3, 4, 3, 4, 4, 5, 3, 4, 4, 5, 4, 5, 5, 6,
    2, 3, 3, 4, 3, 4, 4, 5, 3, 4, 4, 5, 4, 5, 5, 6,
    3, 4, 4, 5, 4, 5, 5, 6, 4, 5, 5, 6, 5, 6, 6, 7,
    1, 2, 2, 3, 2, 3, 3, 4, 2, 3, 3, 4, 3, 4, 4, 5,
    2, 3, 3, 4, 3, 4, 4, 5, 3, 4, 4, 5, 4, 5, 5, 6,
    2, 3, 3, 4, 3, 4, 4, 5, 3, 4, 4, 5, 4, 5, 5, 6,
    3, 4, 4, 5, 4, 5, 5, 6, 4, 5, 5, 6, 5, 6, 6, 7,
    2, 3, 3, 4, 3, 4, 4, 5, 3, 4, 4, 5, 4, 5, 5, 6,
    3, 4, 4, 5, 4, 5, 5, 6, 4, 5, 5, 6, 5, 6, 6, 7,
    3, 4, 4, 5, 4, 5, 5, 6, 4, 5, 5, 6, 5, 6, 6, 7,
    4, 5, 5, 6, 5, 6, 6, 7, 5, 6, 6, 7, 6, 7, 7, 8,
};

#define SHEETAT(s,x,y)  ((s)->bits[iPos[x][y].set] & iPos[x][y].bMask)

#define XAT(pb,x,y)     (((pb)->Xbits.bits[iPos[x][y].set]) & iPos[x][y].bMask)
#define OAT(pb,x,y)     (((pb)->Obits.bits[iPos[x][y].set]) & iPos[x][y].bMask)
#define QAT(pb,x,y)     (((pb)->Qbits.bits[iPos[x][y].set]) & iPos[x][y].bMask)

#define XSET(pb,x,y)    ((pb)->Xbits.bits[iPos[x][y].set]) |= iPos[x][y].bMask
#define OSET(pb,x,y)    ((pb)->Obits.bits[iPos[x][y].set]) |= iPos[x][y].bMask
#define XCLR(pb,x,y)    ((pb)->Xbits.bits[iPos[x][y].set]) &= ~(iPos[x][y].bMask)
#define OCLR(pb,x,y)    ((pb)->Obits.bits[iPos[x][y].set]) &= ~(iPos[x][y].bMask)

#define OPPOSITEPLAYER(x)   (1-x)

#define HEIGHT  7
#define WIDTH   7

typedef struct _move {
    int     iType;
    int     iPlayer;
    int     xfrom;
    int     yfrom;
    int     xto;
    int     yto;
} MOVE;

MOVE nullMove = {0};
BOARD nullBoard = {0};
SHEET nullSheet = {0};
int fDebug = FALSE;
unsigned long lAnalyze = 0;

void PrintBoard(board)
BOARD *board;
{
    int     x;
    int     y;
    int     Total0 = 0;
    int     Total1 = 0;

    printf("O's = %08lX %08lX\n", board->Obits.bits[1], board->Obits.bits[0] );
    printf("X's = %08lX %08lX\n", board->Xbits.bits[1], board->Xbits.bits[0] );

    printf("..0 1 2 3 4 5 6..\n");

    for ( y = HEIGHT-1; y >= 0; --y ) {
        printf("%d ", y );
        for ( x = 0; x < WIDTH; x++ ) {
            if ( QAT(board,x,y) ) {
                printf("? ");
            } else {
                if ( XAT(board,x,y) ) {
                    printf("X ");
                    Total1++;
                } else {
                    if ( OAT(board,x,y) ) {
                        printf("O ");
                        Total0++;
                    } else {
                        printf(". ");
                    }
                }
            }
        }
        printf("%d\n", y );
    }
    printf("..0 1 2 3 4 5 6..\n");
    printf("X has %d, O has %d\n", Total1,Total0);
}

void PrintMove(move)
MOVE *move;
{
    if ( move->iPlayer == PLAYER0 ) {
        printf("Player O");
    } else {
        printf("Player X");
    }
    if ( move->iType == JUMP ) {
        printf(" jumps from %d,%d to %d,%d\n",
              move->xfrom,move->yfrom,
              move->xto,move->yto );
    } else {
        printf(" oozes to %d,%d\n", move->xto, move->yto);
    }
}

int BestMove(board, iPlayer, best, iDepth)
BOARD *board;
int iPlayer;
MOVE *best;
int iDepth;
{
    BOARD   boardTemp;
    SHEET   PossibleOozes;
    SHEET   PossibleJumps;
    SHEET   *MyGuys;
    SHEET   *HisGuys;
    SHEET   OozeGuys;
    int     x;
    int     y;
    int     oldx;
    int     oldy;
    MOVE    thisMove;
    int     resultBest;
    int     result;
    int     MyTotal;
    int     HisTotal;
    int     cnt;
    unsigned char   *bytes;

    resultBest = -1000;

    if ( iPlayer == PLAYER0 ) {
        MyGuys = &board->Obits;
        HisGuys = &board->Xbits;
    } else {
        MyGuys = &board->Xbits;
        HisGuys = &board->Obits;
    }

    if ( iDepth == 0 ) {
        /*
        ** Just count the totals and return
        */

        MyTotal = 0;
        bytes = (char *)MyGuys;
        cnt = 8;
        while ( cnt ) {
            MyTotal += Count[*bytes++];
            --cnt;
        }

        HisTotal = 0;
        bytes = (char *)HisGuys;
        cnt = 8;
        while ( cnt ) {
            HisTotal += Count[*bytes++];
            --cnt;
        }
        lAnalyze++;
        if ( (lAnalyze % 4096) == 0 ) {
            printf("0x%08lX positions\r", lAnalyze);
        }
        return( MyTotal-HisTotal );
    }

    *best = nullMove;

    best->iPlayer = iPlayer;

    PossibleOozes = nullSheet;

    if ( iPlayer == PLAYER0 ) {
        MyGuys = &board->Obits;
        HisGuys = &board->Xbits;
    } else {
        MyGuys = &board->Xbits;
        HisGuys = &board->Obits;
    }
    y = 0;
    while ( y < HEIGHT ) {
        x = 0;
        while ( x < WIDTH ) {
            if ( SHEETAT(MyGuys,x,y) ) {
                PossibleOozes.bits[0] |= iPos[x][y].Oozes.bits[0];
                PossibleOozes.bits[1] |= iPos[x][y].Oozes.bits[1];
            }
            x++;
        }
        y++;
    }
    PossibleOozes.bits[0] &= ~(MyGuys->bits[0]);
    PossibleOozes.bits[1] &= ~(MyGuys->bits[1]);
    PossibleOozes.bits[0] &= ~(HisGuys->bits[0]);
    PossibleOozes.bits[1] &= ~(HisGuys->bits[1]);

    y = 0;
    while ( y < HEIGHT ) {
        x = 0;
        while ( x < WIDTH ) {
            if ( SHEETAT(&PossibleOozes,x,y) ) {
                boardTemp = *board;
                if ( iPlayer == PLAYER0 ) {
                    OSET(&boardTemp,x,y);
                    OozeGuys.bits[0] = board->Xbits.bits[0] &
                                          iPos[x][y].Oozes.bits[0];
                    OozeGuys.bits[1] = board->Xbits.bits[1] &
                                          iPos[x][y].Oozes.bits[1];
                    boardTemp.Obits.bits[0] |= OozeGuys.bits[0];
                    boardTemp.Obits.bits[1] |= OozeGuys.bits[1];
                    boardTemp.Xbits.bits[0] &= ~(OozeGuys.bits[0]);
                    boardTemp.Xbits.bits[1] &= ~(OozeGuys.bits[1]);
                } else {
                    XSET(&boardTemp,x,y);
                    OozeGuys.bits[0] = board->Obits.bits[0] &
                                          iPos[x][y].Oozes.bits[0];
                    OozeGuys.bits[1] = board->Obits.bits[1] &
                                          iPos[x][y].Oozes.bits[1];
                    boardTemp.Xbits.bits[0] |= OozeGuys.bits[0];
                    boardTemp.Xbits.bits[1] |= OozeGuys.bits[1];
                    boardTemp.Obits.bits[0] &= ~(OozeGuys.bits[0]);
                    boardTemp.Obits.bits[1] &= ~(OozeGuys.bits[1]);
                }
                result = -BestMove(&boardTemp,
                                  OPPOSITEPLAYER(iPlayer),
                                  &thisMove,
                                  iDepth-1 );

                if ( result > resultBest ) {
                    resultBest = result;
                    best->iType = OOZE;
                    best->xto = x;
                    best->yto = y;
                }
            }
            x++;
        }
        y++;
    }
    /*
    ** Now test for jumps
    */
    oldy = 0;
    while ( oldy < HEIGHT ) {
        oldx = 0;
        while ( oldx < WIDTH ) {
            if ( SHEETAT(MyGuys,oldx,oldy) ) {
                PossibleJumps = iPos[oldx][oldy].Jumps;
                y = 0;
                while ( y < HEIGHT ) {
                    x = 0;
                    while ( x < WIDTH ) {
                        if ( SHEETAT(&PossibleJumps,x,y) ) {
                            if ( SHEETAT(HisGuys,x,y) == 0 && SHEETAT(MyGuys,x,y) == 0 ) {
                                boardTemp = *board;

                                if ( iPlayer == PLAYER0 ) {
                                    OSET(&boardTemp,x,y);
                                    OCLR(&boardTemp,oldx,oldy);
                                    OozeGuys.bits[0] = board->Xbits.bits[0] &
                                                          iPos[x][y].Oozes.bits[0];
                                    OozeGuys.bits[1] = board->Xbits.bits[1] &
                                                          iPos[x][y].Oozes.bits[1];
                                    boardTemp.Obits.bits[0] |= OozeGuys.bits[0];
                                    boardTemp.Obits.bits[1] |= OozeGuys.bits[1];
                                    boardTemp.Xbits.bits[0] &= ~(OozeGuys.bits[0]);
                                    boardTemp.Xbits.bits[1] &= ~(OozeGuys.bits[1]);
                                } else {
                                    XSET(&boardTemp,x,y);
                                    XCLR(&boardTemp,oldx,oldy);
                                    OozeGuys.bits[0] = board->Obits.bits[0] &
                                                          iPos[x][y].Oozes.bits[0];
                                    OozeGuys.bits[1] = board->Obits.bits[1] &
                                                          iPos[x][y].Oozes.bits[1];
                                    boardTemp.Xbits.bits[0] |= OozeGuys.bits[0];
                                    boardTemp.Xbits.bits[1] |= OozeGuys.bits[1];
                                    boardTemp.Obits.bits[0] &= ~(OozeGuys.bits[0]);
                                    boardTemp.Obits.bits[1] &= ~(OozeGuys.bits[1]);
                                }
                                result = -BestMove(&boardTemp,
                                                  OPPOSITEPLAYER(iPlayer),
                                                  &thisMove,
                                                  iDepth-1 );
                                if ( result > resultBest ) {
                                    resultBest = result;
                                    best->iType = JUMP;
                                    best->xfrom = oldx;
                                    best->yfrom = oldy;
                                    best->xto = x;
                                    best->yto = y;
                                }
                            }
                        }
                        x++;
                    }
                    y++;
                }
            }
            oldx++;
        }
        oldy++;
    }

    return( resultBest );
}

int main()
{
    BOARD   board;
    MOVE    move;
    int     Score;
    int     iPlayer;
    int     iDepth;
    SHEET   OozeGuys;
    char    buffer[100];
    char    *comma;
    char    *space;
    char    *comma2;
    int     x;
    int     y;
    int     x2;
    int     y2;
    long    l;

    board = nullBoard;

    XSET(&board,0,0);
    XSET(&board,6,6);
    OSET(&board,0,6);
    OSET(&board,6,0);

    PrintBoard( &board );

more:

    iPlayer = 0;
    iDepth = 4;

    lAnalyze = 0;

    Score = BestMove( &board, iPlayer, &move, iDepth );

    printf("\n");

    PrintMove( &move );
    PrintBoard( &board );

    x = move.xto;
    y = move.yto;

    if ( move.iType == JUMP ) {
        OCLR(&board,move.xfrom,move.yfrom);
    }
    OSET(&board,x,y);

    OozeGuys.bits[0] = board.Xbits.bits[0] &
                          iPos[x][y].Oozes.bits[0];
    OozeGuys.bits[1] = board.Xbits.bits[1] &
                          iPos[x][y].Oozes.bits[1];
    board.Obits.bits[0] |= OozeGuys.bits[0];
    board.Obits.bits[1] |= OozeGuys.bits[1];
    board.Xbits.bits[0] &= ~(OozeGuys.bits[0]);
    board.Xbits.bits[1] &= ~(OozeGuys.bits[1]);

    PrintBoard( &board );
again:
    printf("x,y x,y:");

    gets( buffer );

    comma = strchr( buffer, ',' );
    if ( comma == NULL ) {
        goto again;
    }
    space = strchr( comma, ' ' );
    if ( space == NULL ) {
        goto again;
    }
    comma2 = strchr( space, ',' );
    if ( comma2 == NULL ) {
        goto again;
    }
    x = atoi(buffer);
    y = atoi(comma+1);
    x2= atoi(space+1);
    y2= atoi(comma2+1);

    if ( XAT(&board,x,y) == 0 ) {
        printf("But you're not on %d,%d\n",x,y);
        goto again;
    }
    if ( XAT(&board,x2,y2 ) != 0 || OAT(&board,x2,y2) != 0 ) {
        printf("But %d,%d is already occupied\n", x2,y2);
        goto again;
    }

    if ( iPos[x][y].Oozes.bits[iPos[x2][y2].set] & iPos[x2][y2].bMask ) {
        move.iPlayer = PLAYER1;
        move.iType = OOZE;
        move.xfrom = x;
        move.yfrom = y;
        move.xto = x2;
        move.yto = y2;
    } else {
        if ( iPos[x][y].Jumps.bits[iPos[x2][y2].set] & iPos[x2][y2].bMask ) {
            move.iPlayer = PLAYER1;
            move.iType = JUMP;
            move.xfrom = x;
            move.yfrom = y;
            move.xto = x2;
            move.yto = y2;
        } else {
            printf("Can't go from %d,%d to %d,%d via jump or ooze\n", x,y, x2,y2 );
            goto again;
        }
    }

    PrintMove( &move );

    x = move.xto;
    y = move.yto;

    if ( move.iType == JUMP ) {
        XCLR(&board,move.xfrom,move.yfrom);
    }
    XSET(&board,x,y);

    OozeGuys.bits[0] = board.Obits.bits[0] &
                          iPos[x][y].Oozes.bits[0];
    OozeGuys.bits[1] = board.Obits.bits[1] &
                          iPos[x][y].Oozes.bits[1];
    board.Xbits.bits[0] |= OozeGuys.bits[0];
    board.Xbits.bits[1] |= OozeGuys.bits[1];
    board.Obits.bits[0] &= ~(OozeGuys.bits[0]);
    board.Obits.bits[1] &= ~(OozeGuys.bits[1]);

    PrintBoard( &board );

    goto more;

}
