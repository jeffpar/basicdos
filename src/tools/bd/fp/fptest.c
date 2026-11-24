/*
 * BASIC-DOS Floating-Point Test for Microsoft C 4.00 Programs
 *
 * @author Jeff Parsons <Jeff@pcjs.org>
 * @copyright (c) 2026 Jeff Parsons
 * @license MIT <https://basicdos.com/LICENSE.txt>
 *
 * This file is part of PCjs, a computer emulation software project at pcjs.org
 *
 * Compiled with /FPa, this prints the same 23 lines with Microsoft's
 * alternate math library (eg, SLIBFA.LIB) as with the BASIC-DOS version of
 * it (see bdfp.asm and bdmath.c), in every memory model.  To build it, run
 * "MAKE MAKEFILE" in this folder.
 */
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

double g1 = 7.5, g2 = -2.25, g3 = 3.0;
float f1 = 1.1, f2;
int i1;
long l1;
unsigned u1;

double twice(x) double x; { return x + x; }

main()
{
    double d, ip;
    float f;
    int n;
    char buf[40];

    printf("add %g sub %g mul %g div %g\n", g1 + g2, g1 - g2, g1 * g2, g1 / g2);
    printf("stack %g %g %g %g\n", (g1 + g2) - (g2 * g3), (g1 + g2) / (g2 * g3), g1 - g2 * g3, g1 / (g2 + g3));
    printf("neg %g cmp %d%d%d%d%d%d\n", -g1, g1 < g2, g1 <= g2, g1 > g2, g1 >= g2, g1 == g2, g1 != g2);
    printf("cmp2 %d%d%d %d\n", g2 < g1, g1 == g1, g2 >= g1, g3 ? 1 : 2);
    i1 = g1; l1 = g2 * 100000.0; u1 = g3 * 20000.0;
    printf("conv %d %ld %u %d %d\n", i1, l1, u1, (int)-7.9, (int)7.9);
    d = i1; printf("back %g", d); d = l1; printf(" %g", d); d = u1; printf(" %g\n", d);
    f = g1 / 3.0; f2 = f * f1; d = f2;
    printf("float %f %f %.9g\n", f, f2, d);
    f = 16777217.0; printf("round %.1f %g %g\n", f, (float)1e-30 * (float)1e-30, (float)0.1);
    printf("call %g %g\n", twice(g1) * 2.0, twice(twice(0.125)));
    printf("fmt %f|%e|%g|%10.3f|%-10.2e|%.0f|%.15g\n", 3.14159265358979, 31415.9265, 0.0001234, -2.5, 12345.678, 2.5, 0.1);
    printf("zero %f %e %g %g\n", 0.0, 0.0, 0.0, -0.0);
    printf("big %g %g %e %f\n", 1e300, 1e-300, 123456789012345.0, 1e15);
    printf("sqrt %.12f sin %.12f cos %.12f tan %.12f\n", sqrt(2.0), sin(1.0), cos(1.0), tan(1.0));
    printf("atan %.12f log %.12f exp %.12f pow %.6f\n", atan(1.0), log(10.0), exp(1.0), pow(2.0, 0.5));
    printf("log10 %.12f asin %.12f acos %.12f atan2 %.12f\n", log10(2.0), asin(0.5), acos(0.5), atan2(-1.0, -1.0));
    printf("sinh %.10f cosh %.10f tanh %.10f\n", sinh(1.0), cosh(1.0), tanh(1.0));
    printf("floor %g %g ceil %g %g fabs %g\n", floor(2.5), floor(-2.5), ceil(2.5), ceil(-2.5), fabs(g2));
    d = modf(-3.75, &ip);
    printf("fmod %g %g modf %g %g ldexp %g %g\n", fmod(7.5, 2.0), fmod(-7.5, 2.0), d, ip, ldexp(1.5, 10), ldexp(1.0, -3));
    d = frexp(48.0, &n);
    printf("frexp %g %d hypot %g\n", d, n, hypot(3.0, 4.0));
    printf("atof %g %g %g %g\n", atof("  -12.5e2x"), atof("abc"), atof(".5"), atof("1e-5"));
    sscanf("3.25 -1e3", "%lf %f", &d, &f);
    printf("scanf %g %g\n", d, f);
    sprintf(buf, "%8.3f", 1234.56789); printf("[%s] %s\n", buf, gcvt(0.000123456, 4, buf + 12));
    for (d = 0.0, n = 0; n < 1000; n++) d += n * 0.001;
    printf("sum %.10f\n", d);
    return 0;
}
