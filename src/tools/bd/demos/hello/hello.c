/*
 * BASIC-DOS "Hello World" Sample for Microsoft C 4.00
 *
 * This builds BIN\HELLO.EXE, an NE program that BASIC-DOS runs in protected
 * mode and, thanks to the NE loader stub that STUB adds, in real mode as well
 * (on BASIC-DOS or any other DOS).  To build it, run:
 *
 *      MAKE MAKEFILE
 *
 * or to build BDC\HELLO.EXE with BDC, the BASIC-DOS C compiler, run:
 *
 *      MAKE MAKEBDC
 *
 * or to build 386\HELLO.EXE, a 32-bit version for an 80386, with the
 * Microsoft 386 C Compiler, run:
 *
 *      MAKE MAKE386
 */

#include <stdio.h>

main(argc, argv)
int argc;
char **argv;
{
    printf("Hello, %s!\n", argc > 1 ? argv[1] : "world");
    return 0;
}
