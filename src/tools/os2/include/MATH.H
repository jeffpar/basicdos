/***
*math.h - definitions and declarations for math library
*
*	Copyright (c) 1985-1990, Microsoft Corporation.  All rights reserved.
*
*Purpose:
*	This file contains constant definitions and external subroutine
*	declarations for the math subroutine library.
*	[ANSI/System V]
*
****/


/* definition of exception struct - this struct is passed to the matherr
 * routine when a floating point exception is detected
 */

#ifndef _EXCEPTION_DEFINED
struct exception {
	int type;		/* exception type - see below */
	char *name;		/* name of function where error occured */
	double arg1;		/* first argument to function */
	double arg2;		/* second argument (if any) to function */
	double retval;		/* value to be returned by function */
	} ;
#define _EXCEPTION_DEFINED
#endif


/* definition of a complex struct to be used by those who use cabs and
 * want type checking on their argument
 */

#ifndef _COMPLEX_DEFINED
struct complex {
	double x,y;	/* real and imaginary parts */
	} ;
#define _COMPLEX_DEFINED
#endif


/* Constant definitions for the exception type passed in the exception struct
 */

#define DOMAIN		1	/* argument domain error */
#define SING		2	/* argument singularity */
#define OVERFLOW	3	/* overflow range error */
#define UNDERFLOW	4	/* underflow range error */
#define TLOSS		5	/* total loss of precision */
#define PLOSS		6	/* partial loss of precision */

#define EDOM		33
#define ERANGE		34


/* definitions of HUGE and HUGE_VAL - respectively the XENIX and ANSI names
 * for a value returned in case of error by a number of the floating point
 * math routines
 */

#ifndef _DLL
extern double _cdecl HUGE;
#define HUGE_VAL HUGE

#else	/* _DLL */

#define HUGE		1.7976931348623158e+308 	/* max value */
#define HUGE_VAL	1.7976931348623158e+308 	/* max value */
#endif	/* _DLL */


/* function prototypes */

int	_cdecl abs(int);
double	_cdecl acos(double);
double	_cdecl asin(double);
double	_cdecl atan(double);
double	_cdecl atan2(double, double);
double	_cdecl atof(const char *);
double	_cdecl cabs(struct complex);
double	_cdecl ceil(double);
double	_cdecl cos(double);
double	_cdecl cosh(double);
int	_cdecl dieeetomsbin(double *, double *);
int	_cdecl dmsbintoieee(double *, double *);
double	_cdecl exp(double);
double	_cdecl fabs(double);
int	_cdecl fieeetomsbin(float *, float *);
double	_cdecl floor(double);
double	_cdecl fmod(double, double);
int	_cdecl fmsbintoieee(float *, float *);
double	_cdecl frexp(double, int *);
double	_cdecl hypot(double, double);
double	_cdecl j0(double);
double	_cdecl j1(double);
double	_cdecl jn(int, double);
long	_cdecl labs(long);
double	_cdecl ldexp(double, int);
double	_cdecl log(double);
double	_cdecl log10(double);
int	_cdecl matherr(struct exception *);
double	_cdecl modf(double, double *);
double	_cdecl pow(double, double);
double	_cdecl sin(double);
double	_cdecl sinh(double);
double	_cdecl sqrt(double);
double	_cdecl tan(double);
double	_cdecl tanh(double);
double	_cdecl y0(double);
double	_cdecl y1(double);
double	_cdecl yn(int, double);
