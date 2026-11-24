/***
*time.h - definitions/declarations for time routines
*
*	Copyright (c) 1985-1990, Microsoft Corporation.  All rights reserved.
*
*Purpose:
*	This file has declarations of time routines and defines
*	the structure returned by the localtime and gmtime routines and
*	used by asctime.
*	[ANSI/System V]
*
****/


/* define the implementation defined time type */

#ifndef _TIME_T_DEFINED
typedef long time_t;		/* time value */
#define _TIME_T_DEFINED 	/* avoid multiple def's of time_t */
#endif

#ifndef _CLOCK_T_DEFINED
typedef long clock_t;
#define _CLOCK_T_DEFINED
#endif

#ifndef _SIZE_T_DEFINED
typedef unsigned int size_t;
#define _SIZE_T_DEFINED
#endif

#ifndef _TM_DEFINED
struct tm {
	int tm_sec;	/* seconds after the minute - [0,59] */
	int tm_min;	/* minutes after the hour - [0,59] */
	int tm_hour;	/* hours since midnight - [0,23] */
	int tm_mday;	/* day of the month - [1,31] */
	int tm_mon;	/* months since January - [0,11] */
	int tm_year;	/* years since 1900 */
	int tm_wday;	/* days since Sunday - [0,6] */
	int tm_yday;	/* days since January 1 - [0,365] */
	int tm_isdst;	/* daylight savings time flag */
	};
#define _TM_DEFINED
#endif

#define CLK_TCK 1000


/* extern declarations for the global variables used by the ctime family of
 * routines.
 */

extern int _cdecl daylight;	/* non-zero if daylight savings time is used */
extern long _cdecl timezone;	/* difference in seconds between GMT and local time */
extern char * _cdecl tzname[2]; /* standard/daylight savings time zone names */


/* function prototypes */

char * _cdecl asctime(const struct tm *);
char * _cdecl ctime(const time_t *);
clock_t _cdecl clock(void);
double _cdecl difftime(time_t, time_t);
struct tm * _cdecl gmtime(const time_t *);
struct tm * _cdecl localtime(const time_t *);
time_t _cdecl mktime(struct tm *);
size_t _cdecl strftime(char *, size_t, const char *, const struct tm *);
char * _cdecl _strdate(char *);
char * _cdecl _strtime(char *);
time_t _cdecl time(time_t *);
void _cdecl tzset(void);
