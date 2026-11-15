#include <stdio.h>
#include <stdlib.h>

typedef struct node { int v; struct node *next; } NODE;
typedef int (*FN)();
enum color { RED, GREEN = 5, BLUE };
union u { int i; char c[2]; long l; };

#define SQ(x) ((x) * (x))
#define MAX(a, b) ((a) > (b) ? (a) : (b))
#define NITEMS 4
#if NITEMS > 3 && !defined(NOTDEF)
#define BIG 1
#else
#define BIG 0
#endif

int twice(x) int x; { return x * 2; }
int thrice(x) int x; { return x * 3; }
FN ftab[] = { twice, thrice };
NODE pool[NITEMS];
int matrix[3][3];
char text[NITEMS][8] = { "ab", "cde", "f" };
struct { char a; int b; char c[3]; } odd = { 1, 2, { 3, 4, 5 } };
long big = SQ(300L);

int apply(f, x) FN f; int x; { return (*f)(x) + (*f)(x); }

NODE *build(n) int n;
{
    NODE *head, *p;
    int i;
    head = 0;
    for (i = 0; i < n; i++) {
        p = &pool[i];
        p->v = SQ(i + 1);
        p->next = head;
        head = p;
    }
    return head;
}

int cmp(a, b) int *a, *b; { return *a - *b; }

main()
{
    NODE *p;
    union u uu;
    int i, j, s, v[6];
    enum color c;
    char *q;

    for (p = build(NITEMS), s = 0; p; p = p->next) s += p->v;
    printf("list %d big %d %ld\n", s, BIG, big);
    printf("apply %d %d\n", apply(twice, 5), apply(ftab[1], 5));
    c = BLUE;
    printf("enum %d %d %d\n", RED, c, GREEN + 1);
    uu.l = 0; uu.i = 0x4142;
    printf("union %c %c %d\n", uu.c[0], uu.c[1], sizeof(uu));
    printf("max %d %d\n", MAX(3, 9), MAX(SQ(4), 15));
    for (i = 0; i < 3; i++) for (j = 0; j < 3; j++) matrix[i][j] = i * 3 + j;
    s = 0;
    for (i = 0; i < 3; i++) s += matrix[i][2 - i];
    printf("diag %d %d\n", s, matrix[2][1]);
    printf("text %s %s %s [%s] %d\n", text[0], text[1], text[2], text[3], sizeof(text));
    printf("odd %d %d %d %d\n", odd.a, odd.b, odd.c[2], sizeof(odd));
    v[0] = 5; v[1] = -2; v[2] = 9; v[3] = 0; v[4] = 7; v[5] = 3;
    qsort((char *)v, 6, sizeof(int), cmp);
    for (i = 0; i < 6; i++) printf("%d ", v[i]);
    printf("\n");
    q = "abcdef";
    printf("%c %c %s %d\n", q[2], *(q + 4), q + 3, atoi("123") + abs(-5));
    i = 7;
    i = i > 5 ? i < 10 ? 1 : 2 : 3;
    printf("cond %d %d\n", i, sizeof(NODE));
    i = 0x1234; j = (char)i; s = (unsigned char)0xF0;
    printf("%d %d %d %ld\n", j, s, (int)(char)200, (long)(unsigned)60000);
    {
        int i;
        i = 99;
        printf("inner %d\n", i);
    }
    printf("outer %d\n", i);
    exit(3 - 3);
}
