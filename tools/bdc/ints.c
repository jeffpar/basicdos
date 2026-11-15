#include <stdio.h>
#include <string.h>

struct pt { int x, y; char c; long l; };
struct pt gp = { 3, 4, 'q', 100000L };
struct pt arr[3];
int tab[5] = { 1, 2, 3 };
char msg[] = "hello";
char *names[] = { "zero", "one", "two" };
int grid[2][3] = { 1, 2, 3, 4, 5, 6 };
unsigned gu = 60000;
char gc = -5;
unsigned char guc = 250;
static int scount;

int add(a, b) int a, b; { return a + b; }
int fact(n) int n; { return n <= 1 ? 1 : n * fact(n - 1); }
int sum(p, n) int *p; int n; { int s; s = 0; while (n--) s += *p++; return s; }
void bump() { static int k = 10; k += 5; scount = k; }
int cmpstr(a, b) char *a, *b; { while (*a && *a == *b) { a++; b++; } return *a - *b; }

main()
{
    int i, j, k, a[10];
    char buf[20], *p;
    struct pt q, *pq;
    unsigned u;

    printf("add %d fact %d\n", add(2, 3), fact(7));
    for (i = 0; i < 10; i++) a[i] = i * i - 3;
    printf("sum %d\n", sum(a, 10));
    j = 0;
    for (i = 0; i < 10; i++) {
        if (i == 3) continue;
        if (i == 8) break;
        j += a[i] % 7;
    }
    printf("j %d\n", j);
    i = 17; j = 5;
    printf("%d %d %d %d %d\n", i + j, i - j, i * j, i / j, i % j);
    printf("%d %d %d %d %d\n", i & j, i | j, i ^ j, i << 3, i >> 2);
    printf("%d %d %d\n", -i, ~i, !i);
    i = -17;
    printf("%d %d %d %d\n", i / 5, i % 5, i >> 2, i << 1);
    u = 50000; 
    printf("%u %u %u %u\n", u / 7, u % 7, u >> 3, u + gu);
    printf("%d %d %d %d\n", u > 100, i < 0, u > i, (int)u < 0);
    printf("%d %d %d\n", gc, guc, gc + guc);
    gc += 3; guc -= 10; gc *= 2; guc >>= 1;
    printf("%d %d\n", gc, guc);
    k = 0;
    for (i = 0; i < 6; i++) {
        switch (i) {
        case 0: k += 1; break;
        case 1:
        case 2: k += 10;
        case 3: k += 100; break;
        default: k += 1000;
        }
    }
    printf("k %d\n", k);
    strcpy(buf, msg);
    strcat(buf, ", w");
    printf("%s %d %c %d\n", buf, strlen(buf), buf[1], sizeof(msg));
    for (i = 0; i < 3; i++) printf("%s ", names[i]);
    printf("\n");
    for (i = 0; i < 2; i++) for (j = 0; j < 3; j++) printf("%d ", grid[i][j]);
    printf("%d %d %d\n", tab[2], tab[4], sizeof(grid));
    q = gp;
    pq = &arr[1];
    *pq = q;
    pq->x += 10; pq->l *= 3; arr[1].c++;
    printf("%d %d %c %ld %d\n", arr[1].x, arr[1].y, arr[1].c, arr[1].l, sizeof(struct pt));
    p = buf; i = 0;
    while (*p) { if (*p++ == 'l') i++; }
    printf("l's %d cmp %d %d\n", i, cmpstr("abc", "abd"), cmpstr("x", "x"));
    bump(); bump();
    printf("static %d\n", scount);
    i = 5; j = i++ + ++i; k = i-- - --i;
    printf("%d %d %d\n", i, j, k);
    i = 3; j = (i > 2 && i < 10) || i == 99; k = !(i == 3) || (i & 1);
    printf("%d %d %d\n", j, k, (i, j + 5));
    do { i--; } while (i > 0);
    printf("i %d\n", i);
    i = 10;
loop:
    i += 7;
    if (i < 30) goto loop;
    printf("goto %d\n", i);
    a[2] = 5; a[a[2]] = 9; p = (char *)a;
    printf("%d %d %d\n", a[5], *(a + 2), &a[5] - &a[2]);
    return 0;
}
