/*
 * BASIC-DOS "Hello World" Sample for Microsoft C 4.00
 *
 * This builds HELLO.EXE, an NE program that BASIC-DOS runs in protected mode
 * and, thanks to the NE loader stub that STUB adds, in real mode as well (on
 * BASIC-DOS or any other DOS).  To build it, run:
 *
 *      MAKE MAKEFILE
 */

#include <stdio.h>

main(argc, argv)
int argc;
char **argv;
{
    printf("Hello, %s!\n", argc > 1 ? argv[1] : "world");
    return 0;
}
