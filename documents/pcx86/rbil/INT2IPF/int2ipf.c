/*
        здбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбд©
        цдедедададададададададададададададададададададададададададададедед╢
        цдед╢   PROJECT      : INT2IPF - Convert all files to .IPF    цдед╢
        цдед╢   FILE         : INT2IPF.C - Main Module                цдед╢
        цдед╢   Last modified: 20 Feb 97                              цдед╢
        цдедедбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдедед╢
        юдадададададададададададададададададададададададададададададададады

    INT2IPF - Convert INTERRUP.LST to .IPF format for the OS/2 IPF Compiler

    Processes the output of COMBINE.COM (interrup.lst)
    INT2IPF interrup.lst interrup.ipf
    Then use IPFC INTERRUP.IFP /INF
    IE:

    COMBINE
    INT2IPF interrup.lst interrup.ipf
    IPFC interrup.ipf /INF

WarpSpeed Computers - The Graham Utilities for OS/2.
Voice:  +61-3-9384-1060  PO Box 212   FidoNet:     3:632/344
FAX:    +61-3-9386-9979  Brunswick    Internet:    chrisg@warpspeed.com.au
BBS:    +61-3-9386-3104  VIC 3056     CompuServe:  100250,1645
300-28,800  N,8,1 ANSI   Australia    Web Pages:
                                      http://www.netins.net/showcase/spectre
                                      http://www.warpspeed.com.au

*/
#define         INT2IPF

/* ------------------------------------------------------------------------ */
/* History                                                                  */
/* ------------------------------------------------------------------------ */
/*
    1.00    08/02/97    Initial Version
    1.01    20/02/97    Added in index support. Due to duplicates the
                        :i2. tags have been commented out.
*/
/* ------------------------------------------------------------------------ */
/* Include files                                                            */
/* ------------------------------------------------------------------------ */

#define         INCL_DOS
#define         INCL_NOPM
#define         INCL_KBD
#include        <os2.h>

#include        <stdio.h>
#include        <malloc.h>
#include        <stdlib.h>
#include        <ctype.h>
#include        <stdarg.h>
#include        <string.h>

#include        "warpcomm.h"

/* ------------------------------------------------------------------------ */
/* Definitions                                                              */
/* ------------------------------------------------------------------------ */

#define     Version "[INT2IPF, V1.01 - 20/02/97 - (C) Chris Graham - WarpSpeed Computers]\n"

/* ------------------------------------------------------------------------ */
/* External references                                                      */
/* ------------------------------------------------------------------------ */

/* ------------------------------------------------------------------------ */
/* Foreward references                                                      */
/* ------------------------------------------------------------------------ */

BOOL                Convert_File( PSZ pszFileIn, PSZ pszFileOut ) ;
void                Parse_CmdLine( int *argc, char *argv[] ) ;
void                Usage( void ) ;
void                DoHeader( FILE * fpFileOut ) ;
void                DoFooter( FILE * fpFileOut ) ;
void                Replace_String( PSZ pszSource, PSZ pszSearch, PSZ pszReplace ) ;
void                ParseLine( PSZ pszLine ) ;
void                DoSeparator( FILE *fpFileOut, PSZ pszLine, ULONG ulCount ) ;

/* ------------------------------------------------------------------------ */
/* Constant Local Data                                                      */
/* ------------------------------------------------------------------------ */

/* ------------------------------------------------------------------------ */
/* Global Data                                                              */
/* ------------------------------------------------------------------------ */

/* ------------------------------------------------------------------------ */
/* Code                                                                     */
/* ------------------------------------------------------------------------ */

int                 main( int argc, char *argv[] )
{
    setvbuf( stdout, NULL, _IONBF, 0 ) ;

    printf( Version ) ;

    Parse_CmdLine( &argc, argv ) ;

    if ( 3 == argc )
        {
        if ( !Convert_File( argv[1], argv[2] ) )
            {
            Usage() ;
            }
        }
    else
        {
        Usage() ;
        exit( 1 ) ;
        }

    return( 0 ) ;
}

BOOL                Convert_File( PSZ pszFileIn, PSZ pszFileOut )
{
FILE                *fpFileIn, *fpFileOut ;
PSZ                 pszLine ;
ULONG               ulCount ;

    fpFileIn = fopen( pszFileIn, READ_TEXT ) ;
    if ( NULL == fpFileIn )
        {
        perror( pszFileIn ) ;
        return( FALSE ) ;
        }
    else
        {
        printf( "Processing %s\n", pszFileIn ) ;
        }

    fpFileOut = fopen( pszFileOut, WRITE_BINARY ) ;
    if ( NULL == fpFileOut )
        {
        perror( pszFileOut ) ;
        return( FALSE ) ;
        }
    else
        {
        printf( "Producing %s\n", pszFileOut ) ;
        }

    ulCount = 0L ;

    DoHeader( fpFileOut ) ;

    pszLine = (PSZ) malloc( (size_t) 32768 ) ;
    if ( NULL != pszLine )
        {
        while ( NULL != fgets( pszLine, (int) 32767, fpFileIn ) )
            {
            if ( 0 == strncmp( pszLine, "--------!---Section", 19 ) )
                {
                /* Remove the multiple section lines */
                fgets( pszLine, (int) 32767, fpFileIn ) ;
                fgets( pszLine, (int) 32767, fpFileIn ) ;
                ulCount = ulCount + 3 ;
                }
            else
                {
                /* Otherwise, process normal lines */
                ulCount++ ;
                ParseLine( pszLine ) ;
                if ( 0 == strncmp( pszLine, "--------", 8 ) )
                    {
                    /* Do the divider line */
                    DoSeparator( fpFileOut, pszLine, ulCount ) ;
                    }
                else
                    {
                    /* Do other lines */
                    fputs( pszLine, fpFileOut ) ;
                    }
                }
            }
        free( pszLine ) ;
        }

    DoFooter( fpFileOut ) ;

    fclose( fpFileOut ) ;
    fclose( fpFileIn ) ;

    printf( "%lu lines processed.\n", ulCount + 1 ) ;

    return( TRUE ) ;
}

void                Parse_CmdLine( int *argc, char *argv[] )
{
int                 i, j ;

    /* Parse for command line switches */
    for ( i = 1; argv[i]; i++ )
        {
        if ( '/' == *argv[i] || '-' == *argv[i] )
            {
            /* Accept slashes or dashes */
            for ( j = 1; argv[i][j]; j++ )
                {
                switch (tolower(argv[i][j]))
                    {
                    case '?':
                    case '*':
                        Usage() ;
                        exit(1) ;
                        break ;
                    default:
                        {
                        printf( "Unknown option \"%s\"\n", argv[i] ) ;
                        Usage() ;
                        exit(1) ;
                        }
                    }
                }
            for ( j = i; j < *argc; j++ )
                {
                /* remove that argv from the list */
                argv[j] = argv[j + 1] ;
                }
            argv[*argc] = NULL ;
            if ( i != *argc )
                {
                (*argc)-- ;
                }
            i-- ;
            }
        }
}

void                Usage( void )
{
    printf( "Usage: INT2IPF <File In> <File Out>\n" ) ;
}

void                DoHeader( FILE * fpFileOut )
{
    fprintf( fpFileOut, ".*****************************************************************************\n" ) ;
    fprintf( fpFileOut, ".* Ralf Browns' Interrupt List                                               *\n" ) ;
    fprintf( fpFileOut, ".*****************************************************************************\n" ) ;
    fprintf( fpFileOut, ":userdoc.\n" ) ;
    fprintf( fpFileOut, ":docprof toc=123.\n" ) ;
    fprintf( fpFileOut, ":title.Ralf Browns' Interrupt List\n" ) ;
    fprintf( fpFileOut, ":body.\n" ) ;
    fprintf( fpFileOut, ":h1.\n" ) ;
    fprintf( fpFileOut, "Ralf Browns' Interrupt List\n" ) ;
    fprintf( fpFileOut, ":xmp.\n" ) ;
}

void                DoFooter( FILE * fpFileOut )
{
    fprintf( fpFileOut, ":exmp.\n" ) ;
    fprintf( fpFileOut, ".*****************************************************************************\n" ) ;
    fprintf( fpFileOut, ":index.\n" ) ;
    fprintf( fpFileOut, ":euserdoc.\n" ) ;
}

void                Replace_String( PSZ pszSource, PSZ pszSearch, PSZ pszReplace )
{
PCHAR               pC1, pC2, pC3, pC4 ;
int                 i ;

    i = strlen( pszSearch ) ;
    pC3 = pC2 = malloc( (size_t) 32768 ) ;
    pC1 = pszSource ;
    while ( '\0' != *pC1 )
        {
        if ( 0 == strnicmp( pC1, pszSearch, i ) )
            {
            pC4 = pszReplace ;
            while ( *pC4 )
                {
                *pC2++ = *pC4++ ;
                }
            pC1++ ;
            }
        else
            {
            *pC2++ = *pC1++ ;
            }
        }
    *pC2 = '\0' ;
    strcpy( pszSource, pC3 ) ;
    free( pC3 ) ;
}

void                ParseLine( PSZ pszLine )
{
    /* TODO: Smart Tab Stops */
    Replace_String( pszLine, "\t", "        " ) ;
    Replace_String( pszLine, "&",  "&amp."    ) ;
    Replace_String( pszLine, ":",  "&colon."  ) ;
}

void                DoSeparator( FILE *fpFileOut, PSZ pszLine, ULONG ulCount )
{
static char         szINT[]        = "INT xx" ;
static char         szAX[]         = "AX = xxxx" ;
static char         szAH[]         = "AH = xx" ;
static char         szCurrentInt[] = "  " ;
static char         szInterrupt[]  = "Interrupt xxh" ;
static ULONG        ulRefID ;
char                szBuffer[100] ;
PSZ                 pC1, pC2 ;
int                 nLevel ;

    fprintf( fpFileOut, ":exmp.\n" ) ;
    szINT[4] = pszLine[10] ;
    szINT[5] = pszLine[11] ;
    if ( 0 == strcmp( szCurrentInt, "--" ) )
        {
        nLevel = 1 ;
        }
    else
        {
        if ( szINT[4] == szCurrentInt[0] && szINT[5] == szCurrentInt[1] )
            {
            /* Same level */
            nLevel = 2 ;
            }
        else
            {
            /* Different level, reset to primary level */
            szInterrupt[10] = pszLine[10] ;
            szInterrupt[11] = pszLine[11] ;
            if ( '-' != pszLine[10] && '-' != pszLine[11] )
                {
                fprintf( fpFileOut, ":h1 id=%lu.%s\n", ulCount - 1, szInterrupt ) ;
                fprintf( fpFileOut, ":i1 id=%lu.%s\n", ulCount - 1, szInterrupt ) ;
                ulRefID = ulCount - 1 ;
                /* IPFC whinges if there is no text between :h tags, so we give it some */
                fprintf( fpFileOut, "%s\n", szInterrupt ) ;
                }
            nLevel = 2 ;
            }
        }

    if ( '-' == pszLine[10] && '-' == pszLine[11] )
        {
        /* This covers the headers (no interrupt) */
        pC1 = &pszLine[12] ;
        pC2 = szBuffer ;
        while ( '\0' != *pC1 )
            {
            if ( '-' != *pC1 )
                {
                /* Copy non '-' chars */
                *pC2++ = *pC1++ ;
                }
            else
                {
                /* skip '-' chars */
                pC1++ ;
                }
            }
        *pC2 = '\0' ;
        fprintf( fpFileOut, ":h1 id=%lu.%s\n", ulCount, szBuffer ) ;
        fprintf( fpFileOut, ":i1 id=%lu.%s\n", ulCount, szBuffer ) ;
        ulRefID = ulCount ;
        }
    else
        {
        if ( '-' == pszLine[14] && '-' == pszLine[15] )
            {
            szAH[5] = pszLine[12] ;
            szAH[6] = pszLine[13] ;
            if ( '-' != pszLine[12] && '-' != pszLine[13] )
                {
                fprintf( fpFileOut, ":h%d id=%lu.%s %s\n", nLevel, ulCount, szINT, szAH ) ;
                /*
                fprintf( fpFileOut, ":i2 refid=%lu.%s %s\n", ulRefID, szINT, szAH ) ;
                */
                }
            else
                {
                fprintf( fpFileOut, ":h%d id=%lu.%s\n", nLevel, ulCount, szINT ) ;
                /*
                fprintf( fpFileOut, ":i2 refid=%lu.%s\n", ulRefID, szINT ) ;
                */
                }
            }
        else
            {
            szAX[5] = pszLine[12] ;
            szAX[6] = pszLine[13] ;
            szAX[7] = pszLine[14] ;
            szAX[8] = pszLine[15] ;
            fprintf( fpFileOut, ":h%d id=%lu.%s %s\n", nLevel, ulCount, szINT, szAX ) ;
            /*
            fprintf( fpFileOut, ":i2 refid=%lu.%s %s\n", ulRefID, szINT, szAX ) ;
            */
            }
        }

    if ( '-' != pszLine[10] && '-' != pszLine[11] )
        {
        szCurrentInt[0] = pszLine[10] ;
        szCurrentInt[1] = pszLine[11] ;
        }
    fprintf( fpFileOut, ":xmp.\n" ) ;
}
