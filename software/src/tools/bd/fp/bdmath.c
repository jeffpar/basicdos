/*
 * BASIC-DOS Math Functions for Microsoft C 4.00 Programs
 *
 * @author Jeff Parsons <Jeff@pcjs.org>
 * @copyright (c) 2026 Jeff Parsons
 * @license MIT <https://basicdos.com/LICENSE.txt>
 *
 * This file is part of PCjs, a computer emulation software project at pcjs.org
 *
 * These are the math functions that the FPU$ driver doesn't provide, written
 * with those that it does (see bdfp.asm).  Compile it with /FPa, for each
 * memory model (eg, /AS):
 *
 *      CL /c /AS /FPa /Gs BDMATH.C
 */

extern double atan(), exp(), floor(), log(), sqrt();

#define PI      3.14159265358979323846
#define HALFPI  1.57079632679489661923
#define LOG10E  0.43429448190325182765

double ceil(x)
double x;
{
    return -floor(-x);
}

static double trunc(x)
double x;
{
    return x < 0.0 ? -floor(-x) : floor(x);
}

double fmod(x, y)
double x, y;
{
    if (y == 0.0) return 0.0;
    return x - trunc(x / y) * y;
}

double modf(x, ip)
double x, *ip;
{
    *ip = trunc(x);
    return x - *ip;
}

double ldexp(x, n)
double x;
int n;
{
    double t;

    t = 2.0;
    if (n < 0) {
        n = -n;
        t = 0.5;
    }
    while (n) {
        if (n & 1) x *= t;
        n >>= 1;
        if (n) t *= t;
    }
    return x;
}

double log10(x)
double x;
{
    return log(x) * LOG10E;
}

double asin(x)
double x;
{
    if (x >= 1.0) return HALFPI;
    if (x <= -1.0) return -HALFPI;
    return atan(x / sqrt(1.0 - x * x));
}

double acos(x)
double x;
{
    return HALFPI - asin(x);
}

double atan2(y, x)
double y, x;
{
    if (x > 0.0) return atan(y / x);
    if (x < 0.0) return y < 0.0 ? atan(y / x) - PI : atan(y / x) + PI;
    return y > 0.0 ? HALFPI : y < 0.0 ? -HALFPI : 0.0;
}

double sinh(x)
double x;
{
    double e;

    e = exp(x);
    return (e - 1.0 / e) / 2.0;
}

double cosh(x)
double x;
{
    double e;

    e = exp(x);
    return (e + 1.0 / e) / 2.0;
}

double tanh(x)
double x;
{
    double e;

    if (x > 20.0) return 1.0;
    if (x < -20.0) return -1.0;
    e = exp(x + x);
    return (e - 1.0) / (e + 1.0);
}
