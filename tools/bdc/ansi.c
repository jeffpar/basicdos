// A self-checking test of things that C 4.00 doesn't accept
#include <stdio.h>
#include <string.h>

#define CHECK(n, c) if (!(c)) { printf("FAIL %d\n", n); fails++; }
#define CAT3(a, b, c) a b c
#define ADD(a, b) ((a) + (b))
#define TWICE(x) ADD(x, x)
#define MAX(a, b) ((a) > (b) ? (a) : (b))
#define EMPTY
#define STR "ab" "cd"
#if defined(MSDOS) && M_I86SM == 1
#define MODEL 1
#elif defined(NOPE)
#define MODEL 2
#else
#define MODEL 3
#endif
#ifndef NOPE
#undef EMPTY
#define EMPTY 7
#endif

int fails;

typedef struct { int a; long b; char c; } REC;
typedef unsigned char BYTE;

static int later(int x);                // defined below, and static
long widen(long v, int n);              // prototypes convert arguments
int narrow(char c, unsigned u);
void fill(REC *r, int a, long b);

REC recs[3] = { { 1, 2L, 'a' }, { 3 }, { 5, 6L, 'c' } };
int two[2][3] = { { 1, 2, 3 }, { 4 } };
char *words[] = { "alpha", "beta", STR };
BYTE bytes[4] = { 200, 100, 0xFF, 1 };
static int hidden = 42;
int *pint = &two[1][0];
char *pch = &"hello"[1];
long neg = -70000L;
unsigned big = 0xFFFF;

int sumv(int n, int *v)
{
    int s = 0, i;                       // initialized locals
    for (i = 0; i < n; i++) s += v[i];
    return s;
}

static int counter(void)
{
    static int n = 100;
    return n++;
}

long widen(long v, int n) { return v * n; }
int narrow(char c, unsigned u) { return c + (u > 40000u); }
void fill(REC *r, int a, long b) { r->a = a; r->b = b; r->c = (char)(a + b); }
unsigned long ul(unsigned long a, unsigned long b) { return a / b + a % b; }
int (*pick(int which))(int) { return which ? later : later; }

int main(int argc, char **argv)
{
    int i, j, k;
    unsigned u;
    long l;
    unsigned long m;
    char c, buf[16];
    BYTE b;
    REC r, *pr;
    int a[5];
    int *p, *q;

    CHECK(1, MODEL == 1 && EMPTY == 7);
    CHECK(2, TWICE(3) == 6 && ADD(TWICE(1), 2) == 4 && MAX(MAX(1, 9), MAX(4, ADD(2, 3))) == 9);
    CHECK(3, strcmp(CAT3("x", "y", "z"), "xyz") == 0 && strlen(STR) == 4);
    CHECK(4, widen(1000, 100) == 100000L);      /* int to long */
    CHECK(5, narrow(300, 50000u) == 45);        /* 300 becomes char 44 */
    fill(&r, 3, 4); CHECK(6, r.a == 3 && r.b == 4L && r.c == 7);
    CHECK(7, recs[0].c == 'a' && recs[1].a == 3 && recs[1].b == 0 && recs[2].b == 6);
    CHECK(8, two[0][2] == 3 && two[1][0] == 4 && two[1][2] == 0 && *pint == 4);
    CHECK(9, words[1][1] == 'e' && words[2][3] == 'd' && *pch == 'e');
    CHECK(10, bytes[0] == 200 && bytes[2] == 255 && bytes[0] + bytes[1] == 300);
    CHECK(11, later(5) == 47 && (*pick(0))(1) == 43);
    CHECK(12, counter() == 100 && counter() == 101);
    a[0] = 1; a[1] = 2; a[2] = 3; a[3] = 4; a[4] = 5;
    CHECK(13, sumv(5, a) == 15);
    p = a; q = &a[4];
    CHECK(14, q - p == 4 && p < q && q > p && p != q && *(q - 1) == 4 && p[2] == 3);
    p += 2; q--; CHECK(15, p + 1 == q && *p++ == 3 && *--q == 3);
    u = 65535u; i = -1;
    CHECK(16, u > 1 && i < 1 && u / 2 == 32767 && (u >> 1) == 32767u && (i >> 1) == -1);
    CHECK(17, -7 / 2 == -3 && -7 % 2 == -1 && 7 / -2 == -3 && big + 1 == 0);
    i = 7; j = -3;
    CHECK(18, i / j == -2 && i % j == 1 && i * j == -21 && (i ^ j) == -6);
    l = 100000L; m = 0xF0000000L;
    CHECK(19, l * 100 / 1000 == 10000L && -l / 7 == -14285 && l % 7 == 5);
    CHECK(20, m > 0x7FFFFFFFL && (long)m < 0 && m >> 28 == 15 && (long)m >> 28 == -1);
    CHECK(21, ul(m, 0x10000L) == 0xF000L && neg / 7 == -10000L && neg < 0);
    l = neg; l += 70001L; CHECK(22, l == 1 && !(l - 1) && (l << 31) < 0);
    pr = &recs[2]; pr->b *= 1000; pr->b += pr->a; pr->b /= 5; pr->b <<= 2; pr->b %= 1000;
    CHECK(23, pr->b == 804);
    c = 'A'; c += 2; c <<= 1; b = 250; b += 10; b >>= 2; b *= 3;
    CHECK(24, c == -122 && b == 3);
    c = 100; c *= 3; b = 9; b /= 2; b %= 3; c /= 4; c %= 5;
    CHECK(25, c == 44 / 4 % 5 && b == 1);
    i = 5; i <<= 2; i |= 3; i &= ~1; i ^= 0x10; i >>= 1; i *= 3; i /= 2; i %= 7; i -= 10;
    CHECK(26, i == -6);
    k = 0;
    for (i = 0; i < 4; i++) for (j = 0; j < 4; j++) { if (j > i) break; if ((i + j) & 1) continue; k += i * j + 1; }
    CHECK(27, k == 23);
    switch (k - 4) { case 19: k = 1; switch (k) { case 0: k = 9; break; default: k = 5; } break; case 5: k = 0; }
    CHECK(28, k == 5);
    i = 0; while (1) { if (++i == 10) break; } do i += 3; while (i < 20);
    CHECK(29, i == 22);
    i = 3; k = i++ * 2 + i-- + --i - ++i;
    CHECK(30, k == 6 + 4 + 2 - 3 && i == 3);
    strcpy(buf, "abc"); buf[3] = 'd'; buf[4] = 0;
    CHECK(31, sizeof(buf) == 16 && sizeof(REC) == 8 && sizeof(recs) / sizeof(recs[0]) == 3 && sizeof buf[0] == 1);
    CHECK(32, (i > 2 ? buf : "zz")[1] == 'b' && (i > 5 ? 1 : 2L) == 2L && sizeof(i > 5 ? 1 : 2L) == 4);
    k = (i = 4, j = i * 2, i + j); CHECK(33, k == 12);
    CHECK(34, hidden == 42 && !argv == 0 && argc >= 1);
    CHECK(35, (char)0x141 == 'A' && (unsigned char)-1 == 255 && (int)(unsigned char)-56 == 200 && (long)(char)-1 == -1L);
    CHECK(36, (unsigned)-1 > 0 && (long)(unsigned)-1 == 65535L && (unsigned long)-1 > 0x7FFFFFFFL);
    u = 40000u; CHECK(37, u + u == 14464u && (long)u + u == 80000L && u * 2L == 80000L);
    r = recs[0]; recs[1] = r; CHECK(38, recs[1].c == 'a' && recs[1].b == 2);
    i = 0; if (i || (i = 1)) k = 1; if (i && (k = 2)) i = 5; if (!i && k++) i = 9;
    CHECK(39, i == 5 && k == 2);
    p = 0; CHECK(40, !p && p == 0 && (p ? 1 : 2) == 2);
    l = 0; for (i = 0; i < 100; i++) l += (long)i * i;
    CHECK(41, l == 328350L);
    m = 1; for (i = 0; i < 31; i++) m <<= 1; CHECK(42, m == 0x80000000L && m - 1 == 0x7FFFFFFFL);
    CHECK(43, 'a' - 'A' == 32 && '\n' == 10 && '\x41' == 65 && '\101' == 65 && "a\tb"[1] == 9);
    goto end;
    fails++;
end:
    printf("fails %d\n", fails);
    return fails;
}

static int later(int x) { return x + hidden; }
