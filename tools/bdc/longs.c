#include <stdio.h>

long gl = 123456789L;
unsigned long gul = 0xB2D05E00L;
long la[4] = { 1L, -1L, 65536L, 0x12345678L };

long lmul(a, b) long a, b; { return a * b; }
long ldivx(a, b) long a, b; { return a / b; }
unsigned long ushift(a, n) unsigned long a; int n; { return a >> n; }

main()
{
    long a, b, c;
    unsigned long u;
    int i;
    long *p;

    a = 100000L; b = 7; i = 3;
    printf("%ld %ld %ld %ld %ld\n", a + b, a - b, a * b, a / b, a % b);
    printf("%ld %ld %ld\n", a & 0xFFFFL, a | 1, a ^ 0x10000L);
    printf("%ld %ld %ld %ld\n", a << 4, a >> 3, a << i, -a >> i);
    printf("%ld %ld\n", -a, ~a);
    printf("%d %d %d %d %d %d\n", a < b, a > b, a == b, a != b, a <= a, a >= b);
    c = -5;
    printf("%d %d %d %d\n", c < 0, c > -6L, c == -5, c < a);
    u = gul;
    printf("%lu %lu %lu %lu\n", u, u / 1000, u % 1000, u >> 5);
    printf("%d %d %d\n", u > 5, u < 5, (long)u < 0);
    printf("%lu\n", ushift(u, 12));
    printf("%ld %ld\n", lmul(123456L, 789L), ldivx(-1000000L, 37L));
    a += b; a -= 3; a *= 2; a /= 3; a %= 1000; 
    printf("%ld\n", a);
    a = 1; a <<= 20; a |= 5; a &= ~1L; a ^= 0xFF; a >>= 2;
    printf("%ld\n", a);
    a = gl; a++; ++a; a--; 
    printf("%ld %ld\n", a, gl);
    i = 40000 > 0; c = 40000; 
    printf("%d %ld %ld\n", i, c, c + 30000);
    c = i; c = c * 100000L; i = (int)(c / 1000);
    printf("%ld %d\n", c, i);
    p = la;
    printf("%ld %ld %ld %lx\n", p[0], *(p + 1), la[2], la[3]);
    p[1] += p[2]; la[0] = la[1] ? la[3] : 0;
    printf("%ld %lx %d\n", la[1], la[0], sizeof(la));
    if (a) printf("a nonzero\n");
    if (!a) printf("a zero\n");
    if (a && b) printf("both\n");
    a = 0;
    if (a || !b) printf("either\n"); else printf("neither\n");
    for (a = 0; a < 100000L; a += 30000) printf("%ld ", a);
    printf("\n");
    u = 0xFFFFFFFFL; u++; 
    printf("%lu %lu\n", u, u - 1);
    i = -2; a = i; u = i; c = (unsigned)i;
    printf("%ld %lu %ld\n", a, u, c);
    return 0;
}
