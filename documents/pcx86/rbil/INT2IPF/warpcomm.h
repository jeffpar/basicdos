/*
        здбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбд©
        цдедедададададададададададададададададададададададададададададедед╢
        цдед╢   PROJECT      : <WARPSPEED COMMON DLL>                 цдед╢
        цдед╢   FILE         : WARPCOMM.H - Common routines in a DLL  цдед╢
        цдед╢   Last modified: 18 Jun 95                              цдед╢
        цдедедбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдбдедед╢
        юдадададададададададададададададададададададададададададададададады

    WARPCOMM
*/
#define         WARPCOMM

/* ------------------------------------------------------------------------ */
/* History                                                                  */
/* ------------------------------------------------------------------------ */
/*
    2.00    31/08/96    VERSION V2.00 RELEASE
*/
/* ------------------------------------------------------------------------ */
/* Definitions                                                              */
/* ------------------------------------------------------------------------ */


/* ------------------------------------------------------------------------ */
/* For MSC only                                                             */
/* ------------------------------------------------------------------------ */
#ifdef  _MSC_VER

typedef     USHORT              APIUINT, FAR *PAPIUINT ;
typedef     SHORT               APIINT, FAR *PAPIINT ;
typedef     USHORT              APIRET ;
typedef     USHORT              VIOUINT ;
typedef     USHORT              MOUUINT ;

#define     DLLENTRY            EXPENTRY _export
#define     CDLLENTRY           cdecl far _export _loadds
#define     THREAD              far
#define     PFNEXPENTRY         EXPENTRY *

/* fopen mode definitions */
#define     READ_TEXT           "rt"
#define     WRITE_TEXT          "wt"
#define     APPEND_TEXT         "at"
#define     READ_BINARY         "rb"
#define     WRITE_BINARY        "wb"
#define     APPEND_BINARY       "ab"

#endif      /* _MSC_VER */

/* ------------------------------------------------------------------------ */
/* For IBM CSet only                                                        */
/* ------------------------------------------------------------------------ */
#if  defined(__IBMC__) || defined(__IBMCPP__)

typedef     ULONG               APIUINT, *PAPIUINT ;
typedef     LONG                APIINT, *PAPIINT ;
typedef     USHORT              VIOUINT ;
typedef     USHORT              MOUUINT ;

#define     DLLENTRY            EXPENTRY
#define     CDLLENTRY           DLLENTRY
#define     THREAD
#define     PFNEXPENTRY         * EXPENTRY

/* fopen mode definitions */
#define     READ_TEXT           "r"
#define     WRITE_TEXT          "w"
#define     APPEND_TEXT         "a"
#define     READ_BINARY         "rb"
#define     WRITE_BINARY        "wb"
#define     APPEND_BINARY       "ab"

#endif      /* __IBMC__ */

/* ------------------------------------------------------------------------ */
/* For WATCOM C10 only                                                      */
/* ------------------------------------------------------------------------ */
#ifdef  __WATCOMC__

typedef     ULONG               APIUINT, *PAPIUINT ;
typedef     LONG                APIINT, *PAPIINT ;
typedef     USHORT              VIOUINT ;
typedef     USHORT              MOUUINT ;

#define     DLLENTRY            EXPENTRY __export
#define     CDLLENTRY           DLLENTRY
#define     THREAD              far
#define     PFNEXPENTRY         EXPENTRY *

/* fopen mode definitions */
#define     READ_TEXT           "rt"
#define     WRITE_TEXT          "wt"
#define     APPEND_TEXT         "at"
#define     READ_BINARY         "rb"
#define     WRITE_BINARY        "wb"
#define     APPEND_BINARY       "ab"

#endif      /* __WATCOMC__ */

/* ------------------------------------------------------------------------ */
/* For Metaware Power/PC compiler only                                      */
/* ------------------------------------------------------------------------ */
#ifdef  __HIGHC__

typedef     ULONG               APIUINT, *PAPIUINT ;
typedef     LONG                APIINT, *PAPIINT ;
typedef     ULONG               VIOUINT ;
typedef     ULONG               MOUUINT ;

#define     DLLENTRY            EXPENTRY
#define     CDLLENTRY           DLLENTRY
#define     THREAD
#define     PFNEXPENTRY         * EXPENTRY

/* fopen mode definitions */
#define     READ_TEXT           "r"
#define     WRITE_TEXT          "w"
#define     APPEND_TEXT         "a"
#define     READ_BINARY         "rb"
#define     WRITE_BINARY        "wb"
#define     APPEND_BINARY       "ab"

/* Assorted macros from STDLIB.H...                     */
#define     min(a, b)           (((a) < (b))? (a) : (b))
#define     max(a, b)           (((a) > (b))? (a) : (b))

/* A fix for MS & Borland style _beginthread()          */
/* Not needed when using the XPG4 libraries...          */
/*
#define     _beginthread(A,B,C,D)   _beginthread(A,C,D)
*/

#endif      /* __HIGHC__ or _PPC */

/* ------------------------------------------------------------------------ */
/* Other general defines for all models, compilers etc                      */
/* ------------------------------------------------------------------------ */

#ifndef PPSZ
typedef PSZ *       PPSZ ;
#endif

/* ------------------------------------------------------------------------ */
/* Other Include Files                                                      */
/* ------------------------------------------------------------------------ */

/* ------------------------------------------------------------------------ */
/* Forward Refences                                                         */
/* ------------------------------------------------------------------------ */
